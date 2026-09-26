import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:simple_live_app/services/desktop_close_coordinator.dart';
import 'package:simple_live_app/modules/live_room/player/playback_lifecycle.dart';

void main() {
  test('suspend invalidates requests; terminal close cannot resume', () async {
    final lifecycle = PlaybackLifecycle();
    final old = lifecycle.beginPlayback();
    lifecycle.suspend();
    expect(lifecycle.ownsRoom(old.room), isFalse);
    expect(
        await lifecycle.command(old, () async => fail('old command')), isFalse);
    lifecycle.resume();
    expect(lifecycle.owns(old), isFalse);
    expect(lifecycle.owns(lifecycle.beginPlayback()), isTrue);
    lifecycle.close();
    lifecycle.resume();
    expect(lifecycle.owns(lifecycle.beginPlayback()), isFalse);
  });

  test('close responds before saving, and concurrent clicks share one attempt',
      () async {
    final saved = Completer<void>();
    final events = <String>[];
    final close = DesktopCloseCoordinator(
      hide: () async => events.add('hide'),
      restore: () async => events.add('restore'),
      save: () {
        events.add('save');
        return saved.future;
      },
      finish: () async => events.add('finish'),
      onWaiting: () => events.add('waiting'),
      onError: (_, __) => events.add('error'),
    );
    final first = close.close();
    final second = close.close();
    expect(identical(first, second), isTrue);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['hide', 'save']);
    saved.complete();
    await first;
    expect(events, ['hide', 'save', 'finish']);
  });

  test('late save cannot destroy a restored window; retry flushes new writes',
      () async {
    final saved = Completer<void>();
    final events = <String>[];
    var saves = 0;
    final close = DesktopCloseCoordinator(
      hide: () async => events.add('hide'),
      restore: () async => events.add('restore'),
      save: () {
        saves++;
        return saves == 1 ? saved.future : Future.value();
      },
      finish: () async => events.add('finish'),
      onWaiting: () => events.add('waiting'),
      onError: (_, __) => events.add('error'),
      saveTimeout: const Duration(milliseconds: 10),
    );
    await close.close();
    expect(events, ['hide', 'restore', 'waiting']);
    await close.close();
    expect(saves, 1);
    expect(events.last, 'waiting');
    saved.complete();
    await Future<void>.delayed(Duration.zero);
    expect(events, isNot(contains('finish')));
    await close.close();
    expect(saves, 2);
    expect(events.last, 'finish');
  });

  test('failed save restores window and reports once; retry can succeed',
      () async {
    var shouldFail = true;
    var errors = 0;
    var restores = 0;
    var finishes = 0;
    final close = DesktopCloseCoordinator(
      hide: () async {},
      restore: () async {
        restores++;
      },
      save: () async {
        if (shouldFail) throw TimeoutException('storage failure');
      },
      finish: () async {
        finishes++;
      },
      onWaiting: () => fail('Storage failure is not a close deadline'),
      onError: (_, __) {
        errors++;
      },
    );
    await close.close();
    expect([errors, restores, finishes], [1, 1, 0]);
    shouldFail = false;
    await close.close();
    expect(finishes, 1);
  });

  test('save failure arriving after timeout is observed without teardown',
      () async {
    final saved = Completer<void>();
    var errors = 0;
    var finishes = 0;
    final close = DesktopCloseCoordinator(
      hide: () async {},
      restore: () async {},
      save: () => saved.future,
      finish: () async {
        finishes++;
      },
      onWaiting: () {},
      onError: (_, __) {
        errors++;
      },
      saveTimeout: const Duration(milliseconds: 10),
    );
    await close.close();
    saved.completeError(StateError('disk write failed'));
    await Future<void>.delayed(Duration.zero);
    expect(errors, 1);
    expect(finishes, 0);
  });
  test('cleanup failures cannot prevent destruction after successful saving',
      () async {
    final events = <String>[];
    await finishDesktopClose(
      stopPlayback: () async {
        throw StateError('mpv failed');
      },
      shutdownLogs: () async {
        throw StateError('log failed');
      },
      destroy: () async => events.add('destroy'),
      onCleanupError: (name, _, __) => events.add(name),
    );
    expect(events, ['停止直播', '关闭日志', 'destroy']);
  });

  test('hung cleanup is bounded, but destruction failure remains retryable',
      () async {
    final errors = <String>[];
    await expectLater(
        finishDesktopClose(
          stopPlayback: () => Completer<void>().future,
          shutdownLogs: () async {},
          destroy: () async {
            throw StateError('native window destruction failed');
          },
          onCleanupError: (name, _, __) => errors.add(name),
          playbackTimeout: const Duration(milliseconds: 10),
        ),
        throwsStateError);
    expect(errors, ['停止直播']);
  });
}
