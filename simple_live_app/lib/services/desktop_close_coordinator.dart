import 'dart:async';

/// Saving is reversible. Only a successful, timely save may start teardown.
/// A timed-out save keeps running, but cannot close a window restored to use.
class DesktopCloseCoordinator {
  DesktopCloseCoordinator({
    required this.hide,
    required this.restore,
    required this.save,
    required this.finish,
    required this.onWaiting,
    required this.onError,
    this.saveTimeout = const Duration(milliseconds: 1500),
  });

  final Future<void> Function() hide, restore, save, finish;
  final void Function() onWaiting;
  final void Function(Object, StackTrace) onError;
  final Duration saveTimeout;
  Future<void>? _attempt;
  Future<void>? _saving;

  Future<void> close() => _attempt ??= _close().whenComplete(() {
        _attempt = null;
      });

  Future<void> _close() async {
    if (_saving != null) {
      onWaiting();
      return;
    }
    try {
      await hide();
      final saving = Future<void>.sync(save);
      _saving = saving;
      // Observe late failures as well as releasing the retry gate. This future
      // deliberately performs no irreversible cleanup when it finally settles.
      var timedOut = false;
      saving.then((_) {
        _saving = null;
      }, onError: (Object error, StackTrace stack) {
        _saving = null;
        if (timedOut) onError(error, stack);
      });
      try {
        await saving.timeout(saveTimeout, onTimeout: () {
          throw const _SaveStillPending();
        });
      } on _SaveStillPending {
        timedOut = true;
        await restore();
        onWaiting();
        return;
      }
      await finish();
    } catch (error, stack) {
      await restore();
      onError(error, stack);
    }
  }
}

class _SaveStillPending {
  const _SaveStillPending();
}

/// After data is safe, cleanup failure cannot strand an already closed player.
/// Destruction failure is propagated so the visible window can retry closing.
Future<void> finishDesktopClose({
  required Future<void> Function() stopPlayback,
  required Future<void> Function() shutdownLogs,
  required Future<void> Function() destroy,
  required void Function(String, Object, StackTrace) onCleanupError,
  Duration playbackTimeout = const Duration(milliseconds: 1500),
  Duration logTimeout = const Duration(milliseconds: 600),
}) async {
  for (final stage in [
    ('停止直播', stopPlayback, playbackTimeout),
    ('关闭日志', shutdownLogs, logTimeout),
  ]) {
    try {
      await Future<void>.sync(stage.$2).timeout(stage.$3);
    } catch (error, stack) {
      onCleanupError(stage.$1, error, stack);
    }
  }
  await destroy();
}
