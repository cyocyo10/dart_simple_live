import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'app_box.dart';
import 'desktop_shared_store.dart';

class AppDataStore {
  AppDataStore._();
  static final instance = AppDataStore._();
  DesktopSharedStore? shared;

  Future<void> initialize(
      {Directory? supportDirectory,
      Directory? legacyDocumentsDirectory}) async {
    if (Platform.isAndroid || Platform.isIOS) return;
    final support = supportDirectory ?? await getApplicationSupportDirectory();
    shared = DesktopSharedStore(Directory('${support.path}/shared'));
    await shared!.initialize(() async {
      await _copyLegacyHive(support, legacyDocumentsDirectory);
      final boxes = <String, Map<String, dynamic>>{};
      for (final name in [
        'LocalStorage',
        'DanmuShield',
        'FollowUser',
        'History',
        'FollowUserTag'
      ]) {
        final box = await Hive.openBox(name);
        try {
          boxes[name.toLowerCase()] = {
            for (final entry in box.toMap().entries)
              // Older versions used positional keys for reordered tags.
              (entry.value is FollowUserTag
                  ? (entry.value as FollowUserTag).id
                  : entry.key.toString()): _encode(entry.value),
          };
        } finally {
          await box.close();
        }
      }
      // Import pending old-version events once, within the initialization lock.
      // Preserve all source files, including Hive, for rollback/manual recovery.
      for (final category in ['follow', 'history', 'shield', 'settings']) {
        final dir = Directory('${support.path}/subwindow_sync/$category');
        if (!await dir.exists()) continue;
        final files = await dir
            .list()
            .where((e) => e is File && e.path.endsWith('.json'))
            .toList();
        files.sort((a, b) => a.path.compareTo(b.path));
        for (final file in files) {
          try {
            final event = jsonDecode(await File(file.path).readAsString())
                as Map<String, dynamic>;
            switch (category) {
              case 'follow':
                if (event['action'] == 'remove') {
                  boxes['followuser']!.remove(event['id']);
                } else if (event['action'] == 'add') {
                  final user = FollowUser.fromJson(
                      {...event, 'tag': event['tag'] ?? '全部'});
                  boxes['followuser']![user.id] = user.toJson();
                }
                break;
              case 'history':
                final item = History.fromJson(event);
                final old = boxes['history']![item.id];
                if (old == null ||
                    !History.fromJson(Map<String, dynamic>.from(old))
                        .updateTime
                        .isAfter(item.updateTime)) {
                  boxes['history']![item.id] = item.toJson();
                }
                break;
              case 'shield':
                if (event['action'] == 'clear') boxes['danmushield']!.clear();
                if (event['action'] == 'add')
                  boxes['danmushield']![event['keyword'] as String] =
                      event['keyword'];
                if (event['action'] == 'remove')
                  boxes['danmushield']!.remove(event['keyword']);
                break;
              case 'settings':
                boxes['localstorage']![event['key'] as String] = event['value'];
                break;
            }
          } catch (error, stack) {
            // Do not silently complete migration with lost pending operations.
            Log.e('旧版窗口数据迁移失败，文件保留: ${file.path}: $error', stack);
            rethrow;
          }
        }
      }
      return boxes;
    });
  }

  Future<void> _copyLegacyHive(
      Directory support, Directory? legacyDocuments) async {
    final documents =
        legacyDocuments ?? await getApplicationDocumentsDirectory();
    for (final name in [
      'followuser',
      'followusertag',
      'history',
      'hostiry',
      'localstorage',
      'danmushield'
    ]) {
      final targetName = name == 'hostiry' ? 'history' : name;
      final target = File('${support.path}/$targetName.hive');
      final source = File('${documents.path}/$name.hive');
      if (!await target.exists() && await source.exists()) {
        await source.copy(target.path);
      }
    }
  }

  static dynamic _encode(dynamic value) {
    if (value is FollowUser) return value.toJson();
    if (value is History) return value.toJson();
    if (value is FollowUserTag) return value.toJson();
    return value;
  }

  Future<AppBox<T>> openBox<T>(String name, T Function(dynamic) decode) async {
    if (shared == null) return AppBox<T>.hive(await Hive.openBox<T>(name));
    return AppBox<T>.shared(shared!, name.toLowerCase(), _encode, decode);
  }
}
