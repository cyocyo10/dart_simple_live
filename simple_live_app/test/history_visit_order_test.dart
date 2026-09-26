import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:hive/hive.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/modules/mine/history/history_row.dart';
import 'package:simple_live_app/modules/mine/history/history_list.dart';
import 'package:simple_live_app/modules/mine/history/history_controller.dart';
import 'package:simple_live_app/modules/mine/history/history_page.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/storage/app_box.dart';
import 'package:simple_live_app/services/storage/app_data_store.dart';
import 'package:simple_live_app/services/storage/desktop_shared_store.dart';
import 'package:simple_live_core/simple_live_core.dart';

class _Settings extends AppSettingsController {
  @override
  // ignore: must_call_super
  void onInit() {}
}

class _Danmaku extends LiveDanmaku {
  @override
  Future<void> start(dynamic args) async {}
  @override
  Future<void> stop() async {}
}

class _RoomSite extends LiveSite {
  final responses = <String, Completer<LiveRoomDetail>>{};
  @override
  LiveDanmaku getDanmaku() => _Danmaku();
  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) =>
      (responses[roomId] ??= Completer<LiveRoomDetail>()).future;
}

class _Player extends Fake implements Player {
  @override
  Future<void> stop() async {}
}

class _RoomController extends LiveRoomController {
  _RoomController(Site site, String roomId, DateTime openedAt)
      : super(pSite: site, pRoomId: roomId, openedAt: openedAt);
  final native = _Player();
  @override
  Player get player => native;
  @override
  void showRoomLoading() {}
  @override
  void hideRoomLoading() {}
  @override
  void getSuperChatMessage() {}
  @override
  Future<void> getPlayQualites() async {}
  @override
  void startLiveDurationTimer() {}
}

LiveRoomDetail _detail(String room, {String? name}) => LiveRoomDetail(
      roomId: room,
      title: room,
      cover: '',
      userName: name ?? room,
      userAvatar: '',
      online: 1,
      status: true,
      danmakuData: room,
      url: 'https://example.test/$room',
    );

History _history(String room, DateTime time, {String? name}) => History(
      id: 'fake_$room',
      roomId: room,
      siteId: 'fake',
      userName: name ?? room,
      face: '',
      updateTime: time,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DesktopSharedStore store;
  late DBService db;
  final controllers = <_RoomController>[];
  setUp(() async {
    Get.testMode = true;
    Log.detailed = false;
    directory = await Directory.systemTemp.createTemp('history-visit-');
    store = DesktopSharedStore(directory);
    await store.initialize(() async => {});
    AppDataStore.instance.shared = store;
    db = DBService();
    await db.init();
    Get.put(db);
    Get.put<AppSettingsController>(_Settings());
  });
  tearDown(() async {
    for (final controller in controllers) {
      controller.preparePlayerClose();
    }
    controllers.clear();
    Get.reset();
    await store.close();
    AppDataStore.instance.shared = null;
    await directory.delete(recursive: true);
  });
  _RoomController open(_RoomSite source, String room, DateTime time) {
    final controller = _RoomController(
      Site(id: 'fake', liveSite: source, logo: '', name: '测试平台'),
      room,
      time,
    );
    controllers.add(controller);
    return controller;
  }

  test('slow earlier window cannot move above a later opened room', () async {
    final firstSite = _RoomSite();
    final nextSite = _RoomSite();
    final firstTime = DateTime.utc(2026, 9, 26, 10);
    final nextTime = firstTime.add(const Duration(seconds: 1));
    final first = open(firstSite, 'first', firstTime).loadData();
    final next = open(nextSite, 'next', nextTime).loadData();
    nextSite.responses['next']!.complete(_detail('next'));
    await next;
    firstSite.responses['first']!.complete(_detail('first'));
    await first;
    expect(db.getHistores().map((row) => row.roomId), ['next', 'first']);
    expect(db.getHistory('fake_first')!.updateTime, firstTime);
    expect(db.getHistory('fake_next')!.updateTime, nextTime);
  });

  test('two same-room windows retain the newer visit and metadata', () async {
    final firstSite = _RoomSite();
    final nextSite = _RoomSite();
    final firstTime = DateTime.utc(2026, 9, 26, 10);
    final nextTime = firstTime.add(const Duration(microseconds: 1));
    final first = open(firstSite, 'room', firstTime).loadData();
    final next = open(nextSite, 'room', nextTime).loadData();
    nextSite.responses['room']!.complete(_detail('room', name: 'newer'));
    await next;
    firstSite.responses['room']!.complete(_detail('room', name: 'older'));
    await first;
    expect(db.getHistores(), hasLength(1));
    expect(db.getHistory('fake_room')!.updateTime, nextTime);
    expect(db.getHistory('fake_room')!.userName, 'newer');
  });

  test(
    'refresh supplements metadata without moving an older visit to top',
    () async {
      final source = _RoomSite();
      final visit = DateTime.utc(2026, 9, 26, 10);
      final controller = open(source, 'room', visit);
      final first = controller.loadData();
      source.responses['room']!.complete(_detail('room', name: 'before'));
      await first;
      await db.addOrUpdateHistory(
        _history('later', visit.add(const Duration(seconds: 1))),
      );
      source.responses.remove('room');
      final refresh = controller.loadData();
      source.responses['room']!.complete(_detail('room', name: 'after'));
      await refresh;
      expect(db.getHistores().map((row) => row.roomId), ['later', 'room']);
      expect(db.getHistory('fake_room')!.updateTime, visit);
      expect(db.getHistory('fake_room')!.userName, 'after');
    },
  );

  test(
    'user switches room captures visit before its network response',
    () async {
      final source = _RoomSite();
      final controller = open(source, 'before', DateTime.utc(2020));
      final beforeSwitch = DateTime.now();
      final switching = controller.resetRoom(controller.site, 'after');
      for (var i = 0; i < 20 && !source.responses.containsKey('after'); i++) {
        await Future<void>.value();
      }
      final responseTime = DateTime.now();
      source.responses['after']!.complete(_detail('after'));
      await switching;
      final saved = db.getHistory('fake_after')!;
      expect(saved.updateTime.isBefore(beforeSwitch), isFalse);
      expect(saved.updateTime.isAfter(responseTime), isFalse);
    },
  );

  test(
    'older controller cannot mutate the newer Hive cached history object',
    () async {
      Hive.init('${directory.path}/hive');
      if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(HistoryAdapter());
      final box = await Hive.openBox<History>('visit-history');
      try {
        db.historyBox = AppBox<History>.hive(box);
        final nextTime = DateTime.utc(2026, 9, 26, 10);
        final newer = _history('room', nextTime, name: 'newer');
        await db.addOrUpdateHistory(newer);
        final controller = open(
          _RoomSite(),
          'room',
          nextTime.subtract(const Duration(seconds: 1)),
        );
        controller.detail.value = _detail('room', name: 'older');
        await controller.addHistory();
        expect(identical(box.get('fake_room'), newer), isTrue);
        expect(newer.updateTime, nextTime);
        expect(newer.userName, 'newer');
      } finally {
        await box.close();
      }
    },
  );

  testWidgets('history row wraps platform and status at 320px with 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final item = _history('123', DateTime.utc(2026), name: '');
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: HistoryRow(item: item, site: null, status: 0),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('房间 123'), findsOneWidget);
    expect(find.text('状态未知'), findsOneWidget);
    expect(find.text('未开播'), findsNothing);
    final status = tester.getRect(
      find.byKey(ValueKey('history-status-${item.id}')),
    );
    final time = tester.getRect(
      find.byKey(ValueKey('history-time-${item.id}')),
    );
    expect(time.top, greaterThanOrEqualTo(status.bottom));
    final text = tester.widget<Text>(
      find.byKey(ValueKey('history-time-${item.id}')),
    );
    expect(text.data, contains('观看于'));
    expect(text.data, '观看于 ${Utils.parseTime(item.updateTime.toLocal())}');
  });

  testWidgets('reordered keyed rows keep their names, avatars and statuses', (
    tester,
  ) async {
    final first = _history('first', DateTime.utc(2026), name: '主播 A');
    final next = _history('next', DateTime.utc(2026), name: '主播 B');
    final rows = ValueNotifier<List<History>>([first, next]);
    addTearDown(rows.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<List<History>>(
            valueListenable: rows,
            builder: (_, items, __) => ListView(
              children: [
                for (final item in items)
                  HistoryRow(
                    key: ValueKey(item.id),
                    item: item,
                    site: null,
                    status: item.id == first.id ? 2 : 3,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    rows.value = [next, first];
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(
      tester.getTopLeft(find.text('主播 B')).dy,
      lessThan(tester.getTopLeft(find.text('主播 A')).dy),
    );
    for (final item in [first, next]) {
      final row = find.byKey(ValueKey(item.id));
      expect(
        find.descendant(
          of: row,
          matching: find.byKey(ValueKey('history-avatar-${item.id}')),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: row,
          matching: find.text(item.id == first.id ? '直播中' : '回放中'),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('default 960px history is two ordered columns and resizes live', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(960, 540);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final items = [
      _history('first', DateTime.utc(2026), name: '首个主播的较长名称用于检查自然行高和换行显示'),
      _history('second', DateTime.utc(2026), name: '第二个'),
      _history('third', DateTime.utc(2026), name: '第三个'),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HistoryList(
            items: items,
            itemBuilder: (_, item) => HistoryRow(
              key: ValueKey(item.id),
              item: item,
              site: null,
              status: 0,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    Rect card(int index) =>
        tester.getRect(find.byKey(ValueKey(items[index].id)));
    expect(card(0).top, card(1).top);
    expect(card(0).left, lessThan(card(1).left));
    expect(card(2).left, card(0).left);
    expect(card(2).top, greaterThanOrEqualTo(card(0).bottom));
    expect(card(2).top, greaterThanOrEqualTo(card(1).bottom));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(320, 800);
    await tester.pump();
    expect(card(0).left, card(1).left);
    expect(card(1).top, greaterThanOrEqualTo(card(0).bottom));
    expect(card(2).top, greaterThanOrEqualTo(card(1).bottom));
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(960, 540);
    await tester.pump();
    expect(card(0).top, card(1).top);
    expect(card(0).left, lessThan(card(1).left));
    expect(tester.takeException(), isNull);
  });

  testWidgets('HistoryPage first refresh and shared changes fit 320px at 2x', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.runAsync(() => db.addOrUpdateHistory(
          _history('first', DateTime.utc(2026), name: '最初的主播'),
        ));
    final controller = Get.put(HistoryController());
    await tester.pumpWidget(
      GetMaterialApp(
        home: const HistoryPage(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
      ),
    );
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 400));
    }
    expect(controller.list.map((item) => item.roomId), ['first']);
    expect(find.text('最初的主播'), findsOneWidget);
    expect(find.text('状态未知'), findsOneWidget);
    expect(find.byTooltip('清空观看记录'), findsOneWidget);
    expect(find.byTooltip('刷新观看记录'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // An independent live window commits and broadcasts the same event.
    await tester.runAsync(() => db.addOrUpdateHistory(
          _history('next', DateTime.utc(2026, 1, 2), name: '新开的主播'),
        ));
    EventBus.instance.emit(Constant.kUpdateHistory, 'fake_next');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(controller.list.map((item) => item.roomId), ['next', 'first']);
    expect(find.text('新开的主播'), findsOneWidget);
    expect(find.text('最初的主播'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('新开的主播')).dy,
      lessThan(tester.getTopLeft(find.text('最初的主播')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await Get.delete<HistoryController>();
  });
}
