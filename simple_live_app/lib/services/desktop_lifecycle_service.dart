import 'dart:async';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:window_manager/window_manager.dart';
import 'package:simple_live_app/app/log.dart';
import 'desktop_close_coordinator.dart';
import 'storage/app_data_store.dart';

class DesktopCloseParticipant {
  DesktopCloseParticipant({
    required this.silence,
    required this.restore,
    required this.finish,
  });
  final Future<void> Function() silence, restore, finish;
}

/// This service only tears down resources belonging to the current process.
class DesktopLifecycleService with WindowListener {
  static final instance = DesktopLifecycleService();
  final _participants = <Object, DesktopCloseParticipant>{};
  List<DesktopCloseParticipant> _closingParticipants = [];
  bool _tearingDown = false;
  late final _coordinator = DesktopCloseCoordinator(
    hide: () async {
      _closingParticipants = _participants.values.toList();
      await windowManager.hide();
      for (final participant in _closingParticipants) {
        // Native commands are serialized by the participant. A slow mute does
        // not hold up saving or delay visible feedback from the close button.
        unawaited(participant.silence().catchError((Object e, StackTrace s) {
          Log.e('关闭窗口静音失败: $e', s);
        }));
      }
    },
    restore: () async {
      // This path never closes storage or disables logging.
      Log.resume();
      await windowManager.show();
      await windowManager.focus();
      if (_tearingDown) return; // Native destruction failed; only retry close.
      for (final participant in _closingParticipants) {
        unawaited(participant.restore().catchError((Object e, StackTrace s) {
          Log.e('恢复窗口音量失败: $e', s);
        }));
      }
    },
    save: () => _stage('保存用户数据', () async {
      await AppDataStore.instance.shared?.flush();
    }),
    finish: () async {
      _tearingDown = true;
      // Closing the shared stream can wait forever for paused subscriptions.
      // Flush is sufficient before process destruction; OS releases its locks.
      await finishDesktopClose(
        stopPlayback: () => _stage('停止直播', () async {
          await Future.wait<void>(_closingParticipants.map((p) async {
            try {
              await p.finish();
            } catch (error, stack) {
              Log.e('直播资源清理失败，用户数据已保存: $error', stack);
            }
          }));
        }),
        shutdownLogs: () => _stage('关闭日志', () => Log.shutdown()),
        destroy: () => windowManager.destroy(),
        onCleanupError: (name, error, stack) {
          Log.e('关闭阶段 $name 失败或超时，用户数据已保存，继续退出: $error', stack);
        },
      );
    },
    onWaiting: () {
      Log.w('关闭窗口保存仍在进行，窗口已恢复，完成后可再次关闭');
      SmartDialog.showToast('数据仍在保存，窗口已恢复。请稍后再次关闭。',
          displayTime: const Duration(seconds: 6));
    },
    onError: (error, stack) {
      Log.e('关闭窗口失败: $error', stack);
      SmartDialog.showToast('关闭失败，窗口已恢复。请重试；若持续失败，请导出诊断日志。',
          displayTime: const Duration(seconds: 8));
    },
  );

  void register(Object owner, DesktopCloseParticipant participant) =>
      _participants[owner] = participant;
  void unregister(Object owner) => _participants.remove(owner);

  Future<void> _stage(String name, Future<void> Function() action) async {
    final watch = Stopwatch()..start();
    try {
      await action();
    } finally {
      Log.w('关闭阶段 $name: ${watch.elapsedMilliseconds}ms');
    }
  }

  Future<void> initialize() async {
    windowManager.addListener(this);
    await windowManager.setPreventClose(true);
  }

  @override
  void onWindowClose() {
    unawaited(closeProcess());
  }

  Future<void> closeProcess() => _coordinator.close();
}
