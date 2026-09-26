import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/storage/app_data_store.dart';

void main() {
  test(
      'upgrade imports Hive and pending operations once, including shield and stable tag IDs',
      () async {
    final temp = await Directory.systemTemp.createTemp('alllive-migration-');
    final support = await Directory('${temp.path}/support').create();
    final documents = await Directory('${temp.path}/documents').create();
    Hive.registerAdapter(FollowUserAdapter());
    Hive.registerAdapter(FollowUserTagAdapter());
    Hive.registerAdapter(HistoryAdapter());
    try {
      Hive.init(documents.path);
      final shield = await Hive.openBox<String>('DanmuShield');
      await shield.put('blocked', 'blocked');
      await shield.close();
      Hive.init(support.path);
      final follows = await Hive.openBox<FollowUser>('FollowUser');
      final original = FollowUser(
          id: 'douyu_1',
          roomId: '1',
          siteId: 'douyu',
          userName: 'one',
          face: '',
          addTime: DateTime(2026));
      await follows.put(original.id, original);
      await follows.close();
      final tags = await Hive.openBox<FollowUserTag>('FollowUserTag');
      await tags.put(0, FollowUserTag(id: 'stable-id', tag: 'tag', userId: []));
      await tags.close();
      final events = await Directory('${support.path}/subwindow_sync/follow')
          .create(recursive: true);
      await File('${events.path}/1.json')
          .writeAsString(jsonEncode({'action': 'remove', 'id': original.id}));
      final store = AppDataStore.instance;
      await store.initialize(
          supportDirectory: support, legacyDocumentsDirectory: documents);
      expect(store.shared!.box('danmushield')['blocked'], 'blocked');
      expect(store.shared!.box('followuser'), isEmpty);
      expect(store.shared!.box('followusertag').keys, ['stable-id']);
      final box = await store.openBox<FollowUser>('FollowUser',
          (v) => FollowUser.fromJson(Map<String, dynamic>.from(v)));
      await box.put(original.id, original);
      box.get(original.id)!.liveStatus.value = 2;
      await store.shared!.mutate('localstorage', (v) {
        v['DanmuSize'] = 30;
      });
      expect(box.get(original.id)!.liveStatus.value, 2,
          reason: 'unrelated settings must preserve live status projections');
      await store.shared!.close();
      await store.initialize(
          supportDirectory: support, legacyDocumentsDirectory: documents);
      expect(store.shared!.box('followuser').containsKey(original.id), isTrue,
          reason: 'old remove event must not replay on next launch');
      expect(await File('${support.path}/followuser.hive').exists(), isTrue);
      expect(await File('${documents.path}/danmushield.hive').exists(), isTrue);
      expect(await File('${events.path}/1.json').exists(), isTrue);
      await store.shared!.close();
      store.shared = null;
    } finally {
      await Hive.close();
      await temp.delete(recursive: true);
    }
  });
}
