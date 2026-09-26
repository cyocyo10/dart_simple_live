import 'dart:convert';

import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/storage/app_box.dart';

/// Validate the entire import before writing anything. AllLive's JSON arrays
/// remain supported; error messages never include a field's raw value.
class DataImport {
  static const sites = {'bilibili', 'douyu', 'huya', 'douyin'};

  static Object? _decode(Object? source) {
    if (source is! String) return source;
    try {
      return jsonDecode(source.replaceFirst('\uFEFF', ''));
    } on FormatException {
      // jsonDecode's exception embeds its input, which may include credentials.
      throw const FormatException('JSON 格式错误，请检查导入内容');
    }
  }

  static List _rows(Object? source) {
    final data = _decode(source);
    if (data is! List) throw const FormatException('数据必须是 JSON 数组');
    return data;
  }

  static Map<String, dynamic> _row(Object? source, int index) {
    if (source is! Map || source.keys.any((key) => key is! String)) {
      throw FormatException('第 ${index + 1} 条数据格式错误');
    }
    return Map<String, dynamic>.from(source);
  }

  static String _text(Map row, String key, int index, {bool optional = false}) {
    final value = row[key];
    if (optional && value == null) return '';
    if (value is! String || (!optional && value.trim().isEmpty)) {
      throw FormatException('第 ${index + 1} 条数据的 $key 无效');
    }
    return value;
  }

  static DateTime _time(Map row, String key, int index) {
    final time = DateTime.tryParse(_text(row, key, index));
    if (time == null) throw FormatException('第 ${index + 1} 条数据的 $key 无效');
    return time;
  }

  static void _room(Map<String, dynamic> row, int index) {
    final site = _text(row, 'siteId', index);
    final room = _text(row, 'roomId', index);
    final id = _text(row, 'id', index);
    if (!sites.contains(site) || room.trim() != room || id != '${site}_$room') {
      throw FormatException('第 ${index + 1} 条数据的平台或房间标识无效');
    }
    row['userName'] = _text(row, 'userName', index, optional: true);
    row['face'] = _text(row, 'face', index, optional: true);
  }

  static Map<String, FollowUser> decodeFollowUsers(Object? source) {
    final result = <String, FollowUser>{};
    final rows = _rows(source);
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], i);
      _room(row, i);
      row['addTime'] = _time(row, 'addTime', i).toIso8601String();
      if (row['tag'] != null && row['tag'] is! String) {
        throw FormatException('第 ${i + 1} 条数据的 tag 无效');
      }
      final user = FollowUser.fromJson(row);
      // Keep the newest duplicate record.
      final old = result[user.id];
      if (old == null || user.addTime.isAfter(old.addTime)) {
        result[user.id] = user;
      }
    }
    return result;
  }

  static Map<String, History> decodeHistory(Object? source) {
    final result = <String, History>{};
    final rows = _rows(source);
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], i);
      _room(row, i);
      row['updateTime'] = _time(row, 'updateTime', i).toIso8601String();
      final history = History.fromJson(row);
      final old = result[history.id];
      if (old == null || history.updateTime.isAfter(old.updateTime)) {
        result[history.id] = history;
      }
    }
    return result;
  }

  static Map<String, FollowUserTag> decodeTags(Object? source) {
    final result = <String, FollowUserTag>{};
    final names = <String>{};
    final rows = _rows(source);
    for (var i = 0; i < rows.length; i++) {
      final row = _row(rows[i], i);
      final id = _text(row, 'id', i);
      final name = _text(row, 'tag', i);
      final users = row['userId'];
      if (users is! List || users.any((user) => !_validUserId(user))) {
        throw FormatException('第 ${i + 1} 条标签的用户标识无效');
      }
      if (result.containsKey(id) || !names.add(name)) {
        throw FormatException('第 ${i + 1} 条标签重复');
      }
      result[id] = FollowUserTag(
        id: id,
        tag: name,
        userId: users.cast<String>().toSet().toList(),
      );
    }
    return result;
  }

  static bool _validUserId(Object? id) {
    if (id is! String) return false;
    final split = id.indexOf('_');
    if (split <= 0 || split == id.length - 1) return false;
    return sites.contains(id.substring(0, split)) && id.trim() == id;
  }

  static Map<String, String> decodeShieldWords(Object? source) {
    final result = <String, String>{};
    for (final word in _rows(source)) {
      if (word is! String) throw const FormatException('屏蔽词必须是字符串');
      final value = word.trim();
      if (value.isNotEmpty) result[value] = value;
    }
    return result;
  }

  static Map<String, dynamic> decodeSettings(Object? source) {
    final data = _decode(source);
    if (data is! Map || data.keys.any((key) => key is! String)) {
      throw const FormatException('设置必须是 JSON 对象');
    }
    // Also rejects unsupported nested types and non-finite numbers.
    try {
      jsonEncode(data);
    } catch (_) {
      throw const FormatException('设置包含无效数据');
    }
    return Map<String, dynamic>.from(data);
  }

  static String decodeCookie(Object? source) {
    final data = _decode(source);
    if (data is! Map || data['cookie'] is! String) {
      throw const FormatException('账号数据格式错误');
    }
    return data['cookie'] as String;
  }

  static Future<void> apply<T>(
    AppBox<T> box,
    Map<String, T> entries, {
    required bool overlay,
  }) async {
    if (overlay) {
      await box.replaceAll(entries);
    } else {
      await box.putAll(entries);
    }
  }
}
