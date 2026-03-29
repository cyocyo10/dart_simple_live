import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/models/db/follow_user.dart';

/// 子窗口→主窗口的关注同步机制
///
/// 子窗口进程有独立的 Hive 副本，关注/取关操作不会反映到主窗口。
/// 此服务将子窗口的操作写入主窗口目录下的 follow_sync/ 文件夹，
/// 主窗口在 loadData 时读取并应用这些变更。
class FollowSyncService {
  FollowSyncService._();

  /// 是否是子窗口进程
  static bool isSubWindow = false;

  /// 主窗口的 applicationSupport 目录（两端都需要设置）
  static String? baseDir;

  static String get _syncDir => p.join(baseDir!, 'follow_sync');

  /// 子窗口调用：写入一条"添加关注"事件
  static Future<void> syncFollow(FollowUser user) async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent({
      'action': 'add',
      'id': user.id,
      'roomId': user.roomId,
      'siteId': user.siteId,
      'userName': user.userName,
      'face': user.face,
      'addTime': user.addTime.toIso8601String(),
    });
  }

  /// 子窗口调用：写入一条"取消关注"事件
  static Future<void> syncUnfollow(String id) async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent({
      'action': 'remove',
      'id': id,
    });
  }

  /// 主窗口调用：读取并应用所有待处理的同步事件
  /// 返回是否有变更
  static Future<bool> applySyncEvents({
    required Future<void> Function(FollowUser) onAdd,
    required Future<void> Function(String) onRemove,
  }) async {
    if (baseDir == null) return false;
    final dir = Directory(_syncDir);
    if (!await dir.exists()) return false;

    var hasChanges = false;
    final files = await dir
        .list()
        .where((e) => e.path.endsWith('.json'))
        .toList();
    for (final entity in files) {
      try {
        final file = File(entity.path);
        final content = await file.readAsString();
        final event = jsonDecode(content) as Map<String, dynamic>;
        final action = event['action'] as String?;
        if (action == 'add') {
          final user = FollowUser(
            id: event['id'] as String,
            roomId: event['roomId'] as String,
            siteId: event['siteId'] as String,
            userName: event['userName'] as String? ?? '',
            face: event['face'] as String? ?? '',
            addTime: DateTime.tryParse(event['addTime'] as String? ?? '') ??
                DateTime.now(),
          );
          await onAdd(user);
          hasChanges = true;
        } else if (action == 'remove') {
          final id = event['id'] as String;
          await onRemove(id);
          hasChanges = true;
        }
        // 标记已处理
        await file.rename('${entity.path}.processed');
      } catch (e) {
        Log.logPrint('FollowSync: 处理同步文件失败 ${entity.path}: $e');
      }
    }
    return hasChanges;
  }

  static Future<void> _writeEvent(Map<String, dynamic> event) async {
    try {
      final dir = Directory(_syncDir);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(_syncDir, '${ts}_$pid.json'));
      await file.writeAsString(jsonEncode(event));
    } catch (e) {
      Log.logPrint('FollowSync: 写入同步事件失败: $e');
    }
  }
}
