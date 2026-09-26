import 'dart:convert';

/// AllLive and Simple Live share this six-field JSON array format.
class HistoryTransfer {
  static const sites = {'bilibili', 'douyu', 'huya', 'douyin'};

  static Map<String, Map<String, dynamic>> decode(String source) {
    final data = jsonDecode(source.replaceFirst('\uFEFF', ''));
    if (data is! List) throw const FormatException('观看记录必须是 JSON 数组');
    final result = <String, Map<String, dynamic>>{};
    for (var i = 0; i < data.length; i++) {
      final row = data[i];
      if (row is! Map) throw FormatException('第 ${i + 1} 条记录格式错误');
      for (final key in [
        'siteId',
        'id',
        'roomId',
        'updateTime',
      ]) {
        if (row[key] is! String) {
          throw FormatException('第 ${i + 1} 条记录缺少 $key');
        }
      }
      for (final key in ['userName', 'face']) {
        if (row[key] != null && row[key] is! String)
          throw FormatException('第 ${i + 1} 条记录的 $key 无效');
      }
      final site = row['siteId'] as String;
      final room = row['roomId'] as String;
      final id = row['id'] as String;
      final time = DateTime.tryParse(row['updateTime'] as String);
      if (!sites.contains(site) ||
          room.trim().isEmpty ||
          id != '${site}_$room' ||
          time == null) {
        throw FormatException('第 ${i + 1} 条记录的平台、房间或时间无效');
      }
      final old = result[id];
      if (old == null || time.isAfter(DateTime.parse(old['updateTime']))) {
        result[id] = {
          'siteId': site,
          'id': id,
          'roomId': room,
          'userName': row['userName'] ?? '',
          'face': row['face'] ?? '',
          'updateTime': time.toIso8601String(),
        };
      }
    }
    return result;
  }

  static String encode(Iterable<Map<String, dynamic>> rows) =>
      const JsonEncoder.withIndent('  ').convert(rows.toList());
}
