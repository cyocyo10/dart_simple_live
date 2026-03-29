import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';

/// 子窗口→主窗口的数据同步机制
///
/// 子窗口进程有独立的 Hive 副本，数据操作不会反映到主窗口。
/// 此服务将子窗口的操作写入主窗口目录下的 subwindow_sync/ 子目录，
/// 主窗口定期读取并应用这些变更。
///
/// 同步类型：
/// - follow/ : 关注/取关事件
/// - history/ : 观看历史事件
/// - shield/ : 弹幕屏蔽词事件
/// - settings/ : 设置变更（按 key 覆盖写入）
class FollowSyncService {
  FollowSyncService._();

  /// 是否是子窗口进程
  static bool isSubWindow = false;

  /// 主窗口的 applicationSupport 目录（两端都需要设置）
  static String? baseDir;

  static String _syncDir(String category) =>
      p.join(baseDir!, 'subwindow_sync', category);

  // ==================== 关注同步 ====================

  static Future<void> syncFollow(FollowUser user) async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent('follow', {
      'action': 'add',
      'id': user.id,
      'roomId': user.roomId,
      'siteId': user.siteId,
      'userName': user.userName,
      'face': user.face,
      'addTime': user.addTime.toIso8601String(),
    });
  }

  static Future<void> syncUnfollow(String id) async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent('follow', {
      'action': 'remove',
      'id': id,
    });
  }

  static Future<bool> applyFollowEvents({
    required Future<void> Function(FollowUser) onAdd,
    required Future<void> Function(String) onRemove,
  }) async {
    return _applyEvents('follow', (event) async {
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
      } else if (action == 'remove') {
        await onRemove(event['id'] as String);
      }
    });
  }

  // ==================== 历史记录同步 ====================

  static Future<void> syncHistory(History history) async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent('history', history.toJson());
  }

  static Future<bool> applyHistoryEvents({
    required Future<void> Function(History) onAddOrUpdate,
  }) async {
    return _applyEvents('history', (event) async {
      final history = History.fromJson(event);
      await onAddOrUpdate(history);
    });
  }

  // ==================== 弹幕屏蔽词同步 ====================

  static Future<void> syncShieldAdd(String keyword) async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent('shield', {
      'action': 'add',
      'keyword': keyword,
    });
  }

  static Future<void> syncShieldRemove(String keyword) async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent('shield', {
      'action': 'remove',
      'keyword': keyword,
    });
  }

  static Future<void> syncShieldClear() async {
    if (!isSubWindow || baseDir == null) return;
    await _writeEvent('shield', {
      'action': 'clear',
    });
  }

  static Future<bool> applyShieldEvents({
    required void Function(String) onAdd,
    required void Function(String) onRemove,
    required void Function() onClear,
  }) async {
    return _applyEvents('shield', (event) async {
      final action = event['action'] as String?;
      if (action == 'add') {
        onAdd(event['keyword'] as String);
      } else if (action == 'remove') {
        onRemove(event['keyword'] as String);
      } else if (action == 'clear') {
        onClear();
      }
    });
  }

  // ==================== 设置同步 ====================
  // 设置用 key 作为文件名（覆盖写入），避免滑块等操作产生大量文件

  static Future<void> syncSetting(String key, dynamic value) async {
    if (!isSubWindow || baseDir == null) return;
    try {
      final dir = Directory(_syncDir('settings'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      // 用 key 的 hash 作为文件名，避免特殊字符问题
      final safeKey = key.replaceAll(RegExp(r'[^\w]'), '_');
      final file = File(p.join(dir.path, '$safeKey.json'));
      await file.writeAsString(jsonEncode({
        'key': key,
        'value': value,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
    } catch (e) {
      Log.logPrint('SubWindowSync: 写入设置同步失败 $key: $e');
    }
  }

  static Future<bool> applySettingEvents({
    required void Function(String key, dynamic value) onSet,
  }) async {
    if (baseDir == null) return false;
    final dir = Directory(_syncDir('settings'));
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
        final key = event['key'] as String;
        final value = event['value'];
        onSet(key, value);
        hasChanges = true;
        await file.rename('${entity.path}.processed');
      } catch (e) {
        Log.logPrint('SubWindowSync: 处理设置同步失败 ${entity.path}: $e');
      }
    }
    return hasChanges;
  }

  // ==================== 通用基础设施 ====================

  static Future<void> _writeEvent(
      String category, Map<String, dynamic> event) async {
    try {
      final dir = Directory(_syncDir(category));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File(p.join(dir.path, '${ts}_$pid.json'));
      await file.writeAsString(jsonEncode(event));
    } catch (e) {
      Log.logPrint('SubWindowSync: 写入同步事件失败 ($category): $e');
    }
  }

  static Future<bool> _applyEvents(
    String category,
    Future<void> Function(Map<String, dynamic> event) handler,
  ) async {
    if (baseDir == null) return false;
    final dir = Directory(_syncDir(category));
    if (!await dir.exists()) return false;

    var hasChanges = false;
    final files = await dir
        .list()
        .where((e) => e.path.endsWith('.json'))
        .toList();
    // 按文件名排序确保时间顺序
    files.sort((a, b) => a.path.compareTo(b.path));
    for (final entity in files) {
      try {
        final file = File(entity.path);
        final content = await file.readAsString();
        final event = jsonDecode(content) as Map<String, dynamic>;
        await handler(event);
        hasChanges = true;
        await file.rename('${entity.path}.processed');
      } catch (e) {
        Log.logPrint('SubWindowSync: 处理同步文件失败 ${entity.path}: $e');
      }
    }
    return hasChanges;
  }
}
