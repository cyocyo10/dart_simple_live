import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

LiveRoomDetail room(String id) => LiveRoomDetail(
      roomId: id,
      title: id,
      cover: '',
      userName: id,
      userAvatar: '',
      online: 1,
      status: true,
      danmakuData: id,
      url: 'https://example.test/$id',
    );
Site site(FakeSite fake, [String id = 'fake']) =>
    Site(id: id, liveSite: fake, logo: '', name: id);
LivePlayQuality quality(String id) => LivePlayQuality(quality: id, data: id);

class FakeSite extends LiveSite {
  final requests = <String, Completer<LiveRoomDetail>>{};
  final urls = <String, Completer<LivePlayUrl>>{};
  final adapter = FakeDanmaku();
  @override
  LiveDanmaku getDanmaku() => adapter;
  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) =>
      (requests[roomId] ??= Completer<LiveRoomDetail>()).future;
  @override
  Future<List<LivePlayQuality>> getPlayQualites({
    required LiveRoomDetail detail,
  }) async =>
      [quality('high'), quality('low')];
  @override
  Future<LivePlayUrl> getPlayUrls({
    required LiveRoomDetail detail,
    required LivePlayQuality quality,
  }) =>
      (urls['${detail.roomId}/${quality.quality}'] ??= Completer<LivePlayUrl>())
          .future;
}

class FakeDanmaku extends LiveDanmaku {
  final started = <dynamic>[];
  @override
  Future<void> start(dynamic args) async {
    started.add(args);
  }

  @override
  Future<void> stop() async {}
}

class FakePlayer extends Fake implements Player {
  final opened = <String>[];
  final jumped = <int>[];
  Completer<void>? pendingStop;
  bool disposed = false;
  final volumes = <double>[];
  Completer<void>? pendingVolume;
  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    await pendingVolume?.future;
  }

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    if (disposed) throw StateError('open after dispose');
    final list = playable as Playlist;
    opened.add(list.medias[list.index].uri);
  }

  @override
  Future<void> stop() => pendingStop?.future ?? Future<void>.value();
  @override
  Future<void> jump(int index) async {
    jumped.add(index);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class FakeSettings extends AppSettingsController {
  // Deliberately skip the storage/theme initialization in isolated playback tests.
  @override
  // ignore: must_call_super
  void onInit() {}
}

class FakeDB extends DBService {
  @override
  bool getFollowExist(String id) => false;
}

class TestRoomController extends LiveRoomController {
  final native = FakePlayer();
  Completer<void>? pendingInitialization;
  final savedHistory = <String>[];
  final toasts = <String>[];
  final delayAnswer = Completer<bool>();
  int shutdowns = 0;
  bool skipRefresh = false;
  @override
  void refreshRoom() {
    if (!skipRefresh) super.refreshRoom();
  }

  TestRoomController(Site site, String room)
      : super(pSite: site, pRoomId: room);
  @override
  Player get player => native;
  @override
  Future<void> initializePlayer() =>
      pendingInitialization?.future ?? Future<void>.value();
  @override
  Future<int> getQualityLevel() async => 2;
  @override
  Future<void> addHistory() async {
    savedHistory.add(roomId);
  }

  @override
  void showRoomLoading() {}
  @override
  void hideRoomLoading() {}
  @override
  void showRoomToast(String message) {
    toasts.add(message);
  }

  @override
  Future resetSystem() async {}
  @override
  Future<bool> askAutoExitDelay() => delayAnswer.future;
  @override
  Future<void> shutdownAfterCountdown() async {
    shutdowns++;
    onClose();
  }
}

Future<void> settle() async {
  for (var i = 0; i < 12; i++) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    Get.testMode = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage([null]),
    );
    Get.put<AppSettingsController>(FakeSettings());
    Get.put<DBService>(FakeDB());
  });
  tearDown(() => Get.reset());

  test('suspended detail cannot save history; restore starts a fresh request',
      () async {
    final fake = FakeSite();
    final controller = TestRoomController(site(fake), 'room');
    final first = controller.loadData();
    await controller.silenceForDesktopClose();
    fake.requests['room']!.complete(room('room'));
    await first;
    expect(controller.savedHistory, isEmpty);
    expect(fake.adapter.started, isEmpty);
    fake.requests.remove('room');
    await controller.restoreAfterDesktopClose();
    await settle();
    fake.requests['room']!.complete(room('room'));
    await settle();
    expect(controller.savedHistory, ['room']);
    fake.urls['room/high']!
        .complete(LivePlayUrl(urls: ['https://example.test/room']));
    await settle();
    controller.onClose();
    await settle();
  });

  test('slow native volume writes coalesce to the latest drag position',
      () async {
    final controller = TestRoomController(site(FakeSite()), 'room');
    controller.native.pendingVolume = Completer<void>();
    controller.setRoomVolume(50, persistDefault: false);
    for (var value = 0; value <= 100; value++) {
      controller.setRoomVolume(value.toDouble(), persistDefault: false);
    }
    await settle();
    expect(controller.playbackVolume.value, 100);
    expect(controller.native.volumes, [50]);
    controller.native.pendingVolume!.complete();
    await settle();
    expect(controller.native.volumes, [50, 100]);
    controller.onClose();
    await settle();
  });

  test('failed in-flight volume still applies a newer pending target',
      () async {
    final controller = TestRoomController(site(FakeSite()), 'room');
    final failed = Completer<void>();
    controller.native.pendingVolume = failed;
    controller.setRoomVolume(50, persistDefault: false);
    controller.setRoomVolume(75, persistDefault: false);
    controller.native.pendingVolume = null;
    failed.completeError(StateError('old native command failed'));
    await settle();
    expect(controller.native.volumes, [50, 75]);
    expect(controller.playbackVolume.value, 75);
    controller.onClose();
    await settle();
  });

  test('volume changes accumulate and late mute cannot change restore target',
      () async {
    final controller = TestRoomController(site(FakeSite()), 'room');
    controller.setRoomVolume(50, persistDefault: false);
    controller.adjustRoomVolume(5);
    controller.adjustRoomVolume(5);
    expect(controller.playbackVolume.value, 60);
    await settle();
    controller.native.pendingVolume = Completer<void>();
    final muted = controller.silenceForDesktopClose();
    await settle();
    expect(controller.native.volumes.last, 0); // Mute has already begun.
    expect(controller.playbackVolume.value, 60);
    controller.skipRefresh = true;
    final restored = controller.restoreAfterDesktopClose();
    controller.native.pendingVolume!.complete();
    await Future.wait([muted, restored]);
    expect(controller.playbackVolume.value, 60);
    expect(controller.native.volumes.last, 60);
    controller.adjustRoomVolume(100);
    expect(controller.playbackVolume.value, 100);
    controller.adjustRoomVolume(-200);
    expect(controller.playbackVolume.value, 0);
    controller.onClose();
    await settle();
  });

  test(
    'old room detail cannot start the new adapter or write new-room history',
    () async {
      final old = FakeSite();
      final next = FakeSite();
      final controller = TestRoomController(site(old), 'old');
      final first = controller.loadData();
      final reset = controller.resetRoom(site(next, 'next'), 'new');
      await settle();
      next.requests['new']!.complete(room('new'));
      await reset;
      await settle();
      old.requests['old']!.complete(room('old'));
      await first;
      expect(controller.detail.value!.roomId, 'new');
      expect(old.adapter.started, isEmpty);
      expect(next.adapter.started, ['new']);
      expect(controller.savedHistory, ['new']);
      next.urls['new/high']!.complete(
        LivePlayUrl(urls: ['https://example.test/new']),
      );
      await settle();
      expect(controller.native.opened, ['https://example.test/new']);
      controller.onClose();
      await settle();
    },
  );

  test(
    'last requested quality wins even when the older URL finishes last',
    () async {
      final fake = FakeSite();
      final controller = TestRoomController(site(fake), 'room');
      controller.detail.value = room('room');
      controller.qualites.assignAll([quality('high'), quality('low')]);
      controller.currentQuality = 0;
      final high = controller.getPlayUrl();
      controller.currentQuality = 1;
      final low = controller.getPlayUrl();
      fake.urls['room/low']!.complete(
        LivePlayUrl(urls: ['https://example.test/low']),
      );
      await low;
      fake.urls['room/high']!.complete(
        LivePlayUrl(urls: ['https://example.test/high']),
      );
      await high;
      expect(controller.playUrls, ['https://example.test/low']);
      expect(controller.native.opened, ['https://example.test/low']);
      controller.onClose();
      await settle();
    },
  );

  test(
    'close during player initialization suppresses open and then disposes',
    () async {
      final fake = FakeSite();
      final controller = TestRoomController(site(fake), 'room');
      controller.pendingInitialization = Completer<void>();
      controller.playUrls.assignAll(['https://example.test/room']);
      controller.currentLineIndex = 0;
      final opening = controller.initPlaylist();
      await settle();
      controller.onClose();
      expect(controller.native.disposed, false);
      controller.pendingInitialization!.complete();
      await opening;
      await settle();
      expect(controller.native.opened, isEmpty);
      expect(controller.native.disposed, true);
    },
  );

  test(
    'refresh while reset stop awaits suppresses reset duplicate load',
    () async {
      final old = FakeSite();
      final next = FakeSite();
      final controller = TestRoomController(site(old), 'old');
      controller.native.pendingStop = Completer<void>();
      final reset = controller.resetRoom(site(next, 'next'), 'new');
      await settle();
      final refresh = controller.loadData();
      next.requests['new']!.complete(room('new'));
      await refresh;
      await settle();
      next.urls['new/high']!.complete(
        LivePlayUrl(urls: ['https://example.test/new']),
      );
      controller.native.pendingStop!.complete();
      await reset;
      await settle();
      expect(controller.savedHistory, ['new']);
      expect(next.adapter.started, ['new']);
      expect(controller.native.opened, ['https://example.test/new']);
      controller.onClose();
      await settle();
    },
  );

  test(
    'close before room response cannot start danmaku or load qualities',
    () async {
      final fake = FakeSite();
      final controller = TestRoomController(site(fake), 'room');
      final loading = controller.loadData();
      controller.onClose();
      fake.requests['room']!.complete(room('room'));
      await loading;
      await settle();
      expect(fake.adapter.started, isEmpty);
      expect(fake.urls, isEmpty);
      expect(controller.savedHistory, isEmpty);
      expect(controller.native.opened, isEmpty);
    },
  );

  test('close before URL response cannot reopen a disposed player', () async {
    final fake = FakeSite();
    final controller = TestRoomController(site(fake), 'room');
    controller.detail.value = room('room');
    controller.qualites.assignAll([quality('high')]);
    controller.currentQuality = 0;
    final resolving = controller.getPlayUrl();
    controller.onClose();
    await settle();
    fake.urls['room/high']!.complete(
      LivePlayUrl(urls: ['https://example.test/old']),
    );
    await resolving;
    expect(controller.native.disposed, true);
    expect(controller.native.opened, isEmpty);
  });

  test(
    'line selection during initialization prevents older playlist open',
    () async {
      final controller = TestRoomController(site(FakeSite()), 'room');
      controller.pendingInitialization = Completer<void>();
      controller.playUrls.assignAll([
        'https://example.test/first',
        'https://example.test/next',
      ]);
      controller.currentLineIndex = 0;
      final opening = controller.initPlaylist();
      await settle();
      controller.changePlayLine(1);
      controller.pendingInitialization!.complete();
      await opening;
      await settle();
      expect(controller.native.opened, ['https://example.test/next']);
      expect(controller.native.jumped, isEmpty);
      controller.onClose();
      await settle();
    },
  );

  testWidgets('delayed retry cannot jump after a new quality request',
      (tester) async {
    final fake = FakeSite();
    final controller = TestRoomController(site(fake), 'room');
    controller.detail.value = room('room');
    controller.qualites.assignAll([quality('high')]);
    controller.currentQuality = 0;
    controller.playUrls.assignAll(['https://example.test/old']);
    controller.currentLineIndex = 0;
    controller.mediaErrorRetryCount = 1;
    controller.mediaError('old');
    final resolving = controller.getPlayUrl();
    fake.urls['room/high']!
        .complete(LivePlayUrl(urls: ['https://example.test/new']));
    await tester.pump();
    await resolving;
    await tester.pump(const Duration(seconds: 2));
    expect(controller.native.opened, ['https://example.test/new']);
    expect(controller.native.jumped, isEmpty);
    expect(controller.mediaErrorRetryCount, 0);
    controller.onClose();
    await tester.pump();
  });

  test('stale automatic re-sign cannot override manual quality or show failure',
      () async {
    final fake = FakeSite();
    final controller = TestRoomController(site(fake), 'room');
    controller.detail.value = room('room');
    controller.qualites.assignAll([quality('high'), quality('low')]);
    controller.currentQuality = 0;
    controller.playUrls.assignAll(['https://example.test/expired']);
    controller.currentLineIndex = 0;
    controller.mediaErrorRetryCount = 2;
    controller.mediaError('expired');
    controller.currentQuality = 1;
    final resolving = controller.getPlayUrl();
    fake.urls['room/low']!
        .complete(LivePlayUrl(urls: ['https://example.test/low']));
    await resolving;
    fake.urls['room/high']!
        .complete(LivePlayUrl(urls: ['https://example.test/stale']));
    await settle();
    expect(controller.native.opened, ['https://example.test/low']);
    expect(controller.errorMsg.value, '');
    expect(controller.toasts, isEmpty);
    controller.onClose();
    await settle();
  });

  testWidgets('disabling auto-exit invalidates grace and pending dialog',
      (tester) async {
    final controller = TestRoomController(site(FakeSite()), 'room');
    controller.autoExitEnable.value = true;
    controller.autoExitMinutes.value = 0;
    controller.setAutoExit();
    await tester.pump(const Duration(seconds: 1));
    controller.autoExitEnable.value = false;
    controller.setAutoExit();
    await tester.pump(const Duration(seconds: 11));
    controller.delayAnswer.complete(false);
    await tester.pump();
    expect(controller.shutdowns, 0);
    controller.onClose();
    await tester.pump();
  });

  testWidgets(
      'normal auto-exit deadline fires once and late dialog cannot repeat it',
      (tester) async {
    final controller = TestRoomController(site(FakeSite()), 'room');
    controller.autoExitEnable.value = true;
    controller.autoExitMinutes.value = 0;
    controller.setAutoExit();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 10));
    expect(controller.shutdowns, 1);
    controller.delayAnswer.complete(false);
    await tester.pump();
    expect(controller.shutdowns, 1);
  });

  testWidgets(
    'leaving during auto-exit grace cancels delayed process shutdown',
    (tester) async {
      final controller = TestRoomController(site(FakeSite()), 'room');
      controller.autoExitEnable.value = true;
      controller.autoExitMinutes.value = 0;
      controller.setAutoExit();
      await tester.pump(const Duration(seconds: 1));
      controller.onClose();
      await tester.pump(const Duration(seconds: 11));
      controller.delayAnswer.complete(false);
      await tester.pump();
      expect(controller.shutdowns, 0);
    },
  );
}
