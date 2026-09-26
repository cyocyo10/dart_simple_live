import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/mine/history/history_controller.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/storage/app_data_store.dart';
import 'package:simple_live_app/services/storage/desktop_shared_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DesktopSharedStore store;
  late DBService db;
  setUp(() async {
    Get.testMode = true;
    Log.detailed = false;
    directory = await Directory.systemTemp.createTemp('follow-regression-');
    store = DesktopSharedStore(directory);
    await store.initialize(() async => {});
    AppDataStore.instance.shared = store;
    db = DBService();
    await db.init();
    Get.put(db);
    final local = LocalStorageService();
    await local.init();
    Get.put(local);
  });
  tearDown(() async {
    Get.reset();
    await store.close();
    AppDataStore.instance.shared = null;
    await directory.delete(recursive: true);
  });
  FollowUser user(String room) => FollowUser(
      id: 'huya_$room',
      roomId: room,
      siteId: 'huya',
      userName: room,
      face: '',
      addTime: DateTime.utc(2026));

  test('tag rename, reassignment and deletion commit both namespaces together',
      () async {
    await db.addFollow(user('one'));
    final tag = await db.addFollowTag('游戏');
    await db.setFollowTag('huya_one', tag.id);
    var revision = store.revision;
    await db.renameFollowTag(tag.id, '音乐');
    expect(store.revision, revision + 1);
    expect(db.followBox.get('huya_one')!.tag, '音乐');
    expect(db.tagBox.get(tag.id)!.tag, '音乐');
    await db.deleteFollow('huya_one');
    expect(db.tagBox.get(tag.id)!.userId, isEmpty);
    await db.addFollow(user('two'));
    await db.setFollowTag('huya_two', tag.id);
    await db.deleteFollowTag(tag.id);
    expect(db.followBox.get('huya_two')!.tag, '全部');
    expect(db.tagBox.containsKey(tag.id), isFalse);
    revision = store.revision;
    await expectLater(db.setFollowTag('huya_two', tag.id), throwsStateError);
    expect(store.revision, revision);
  });

  test(
      'canonical room migration preserves tags and cannot resurrect an unfollow',
      () async {
    await db.addFollow(user('alias'));
    final tag = await db.addFollowTag('游戏');
    await db.setFollowTag('huya_alias', tag.id);
    await db.canonicalizeFollow('huya_alias', user('canonical'));
    expect(db.followBox.containsKey('huya_alias'), isFalse);
    expect(db.followBox.get('huya_canonical')!.tag, '游戏');
    expect(db.tagBox.get(tag.id)!.userId, ['huya_canonical']);
    await db.deleteFollow('huya_canonical');
    await db.canonicalizeFollow('huya_canonical', user('later'));
    expect(db.followBox.isEmpty, isTrue);
  });

  test('stale tag reorder preserves another window addition and rename',
      () async {
    final first = await db.addFollowTag('一');
    final stale = db.getFollowTagList();
    final other = DesktopSharedStore(directory);
    await other.initialize(() async => {});
    await other.mutate('followusertag', (tags) {
      tags[first.id] = first.copyWith(tag: '新名字').toJson();
      tags['new'] = FollowUserTag(id: 'new', tag: '二', userId: []).toJson();
    });
    await db.updateFollowTagOrder(stale);
    expect(db.tagBox.get(first.id)!.tag, '新名字');
    expect(db.tagBox.containsKey('new'), isTrue);
    await other.close();
  });

  test('bad final local import leaves follows and tags unchanged', () async {
    await db.addFollow(user('old'));
    final before = store.revision;
    final service = FollowService();
    await expectLater(
        service.inputJson(
            '[{"id":"huya_new","siteId":"huya","roomId":"new","addTime":"2026-01-01"}, {}]'),
        throwsFormatException);
    expect(store.revision, before);
    expect(db.followBox.toMap().keys, ['huya_old']);
    service.onClose();
  });

  test('tag filtering never deletes membership absent from a stale list',
      () async {
    final service = FollowService();
    service.followList.add(user('one'));
    final tag =
        FollowUserTag(id: 'tag', tag: '标签', userId: ['huya_one', 'huya_two']);
    service.filterDataByTag(tag);
    expect(service.curTagFollowList.map((item) => item.id), ['huya_one']);
    expect(tag.userId, ['huya_one', 'huya_two']);
    service.onClose();
  });

  test('history removal is awaited and the empty page updates', () async {
    final item = History(
        id: 'retired_one',
        roomId: 'one',
        siteId: 'retired',
        userName: '',
        face: '',
        updateTime: DateTime.utc(2026));
    await db.historyBox.put(item.id, item);
    final controller = HistoryController();
    await controller.refreshData();
    expect(controller.list.length, 1);
    expect(await controller.removeItem(item), isTrue);
    expect(db.historyBox.isEmpty, isTrue);
    expect(controller.list, isEmpty);
    expect(controller.pageEmpty.value, isTrue);
    controller.onClose();
  });

  test(
    'child favorites stay local on shared changes and refresh explicitly',
    () async {
      final settings = Get.put(AppSettingsController());
      settings.autoUpdateFollowEnable.value = true;
      final service = Get.put(_TrackingFollowService(backgroundRefresh: false));
      expect(service.updateTimer, isNull);
      // Shared settings updates must not enable a child timer.
      service.initTimer();
      expect(service.updateTimer, isNull);
      await db.addFollow(user('one'));
      EventBus.instance.emit(Constant.kUpdateFollow, null);
      await Future<void>.delayed(Duration.zero);
      expect(service.followList.map((item) => item.id), ['huya_one']);
      expect(service.notLiveList.length, 1);
      expect(service.statusRefreshes, 0);
      // Opening the list or clicking refresh is explicit.
      await service.loadData();
      expect(service.statusRefreshes, 1);
      await db.addFollow(user('two'));
      EventBus.instance.emit(Constant.kUpdateFollow, null);
      await Future<void>.delayed(Duration.zero);
      expect(service.followList.length, 2);
      expect(service.statusRefreshes, 1);
    },
  );

  test(
    'main favorites retain automatic timer and shared status refresh',
    () async {
      final settings = Get.put(AppSettingsController());
      settings.autoUpdateFollowEnable.value = true;
      settings.autoUpdateFollowDuration.value = 10;
      final service = Get.put(_TrackingFollowService());
      expect(service.updateTimer?.isActive, isTrue);
      await db.addFollow(user('one'));
      EventBus.instance.emit(Constant.kUpdateFollow, null);
      await Future<void>.delayed(Duration.zero);
      expect(service.statusRefreshes, 1);
      settings.autoUpdateFollowEnable.value = false;
      service.initTimer();
      expect(service.updateTimer, isNull);
    },
  );

  test(
    'child Bili restores playback credentials without profile requests',
    () async {
      final local = LocalStorageService.instance;
      await local.setValue(
        LocalStorageService.kBilibiliCookie,
        'SESSDATA=saved; DedeUserID=7',
      );
      var requests = 0;
      final account = Get.put(
        BiliBiliAccountService(
          refreshProfileOnRestore: false,
          fetchAccount: (_) async {
            requests++;
            return {
              'code': 0,
              'data': {'mid': 9, 'uname': '显式登录'},
            };
          },
        ),
      );
      expect(account.cookie, contains('saved'));
      expect(account.uid, 7);
      expect(account.logined.value, isTrue);
      final site = Sites.allSites[Constant.kBiliBili]!.liveSite as BiliBiliSite;
      expect(site.cookie, account.cookie);
      expect(site.userId, 7);
      expect(requests, 0);
      await local.setValue(
        LocalStorageService.kBilibiliCookie,
        'SESSDATA=other-window; DedeUserID=8',
      );
      account.reloadFromStorage();
      expect(account.uid, 8);
      expect(site.userId, 8);
      expect(requests, 0);
      expect(
        await account.loginCookie('SESSDATA=explicit; DedeUserID=9'),
        isTrue,
      );
      expect(requests, 1);
      expect(account.uid, 9);
      expect(account.name.value, '显式登录');
      expect(await account.loadUserInfo(), isTrue);
      expect(requests, 2);
    },
  );

  test(
    'main Bili still fetches profile on stored account restoration',
    () async {
      await LocalStorageService.instance.setValue(
        LocalStorageService.kBilibiliCookie,
        'SESSDATA=saved; DedeUserID=7',
      );
      var requests = 0;
      final account = Get.put(
        BiliBiliAccountService(
          fetchAccount: (_) async {
            requests++;
            return {
              'code': 0,
              'data': {'mid': 7, 'uname': '主窗口'},
            };
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(requests, 1);
      expect(account.name.value, '主窗口');
    },
  );

  test('Bili pending login cannot replace the account after cancellation',
      () async {
    final response = Completer<dynamic>();
    final account =
        BiliBiliAccountService(fetchAccount: (_) => response.future);
    await account.setCookie('SESSDATA=previous; DedeUserID=1');
    final pending = account.loginCookie('SESSDATA=candidate; DedeUserID=2');
    account.cancelPendingLogin();
    response.complete({
      'code': 0,
      'data': {'mid': 2, 'uname': 'candidate'}
    });
    expect(await pending, isFalse);
    expect(account.cookie, contains('previous'));
    expect(
        LocalStorageService.instance
            .getValue(LocalStorageService.kBilibiliCookie, ''),
        contains('previous'));
    expect(await account.loginCookie('anonymous=1'), isFalse);
    account.onClose();
  });

  test('Bili successful verification saves credentials and identity', () async {
    final account = BiliBiliAccountService(
        fetchAccount: (_) async => {
              'code': 0,
              'data': {'mid': 2, 'uname': '测试'}
            });
    expect(
        await account.loginCookie('SESSDATA=candidate; DedeUserID=2'), isTrue);
    expect(account.uid, 2);
    expect(account.name.value, '测试');
    expect(account.logined.value, isTrue);
    account.onClose();
  });
}

class _TrackingFollowService extends FollowService {
  _TrackingFollowService({super.backgroundRefresh});
  int statusRefreshes = 0;

  @override
  Future<void> startUpdateStatus({int? generation}) async {
    statusRefreshes++;
    filterData();
  }
}
