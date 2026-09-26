import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/modules/mine/history/history_transfer.dart';

import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/services/db_service.dart';

class HistoryController extends BasePageController<History> {
  /// 运行时直播状态，key = item.id, value = 0未知/1未开播/2直播中/3回放中
  final liveStatusMap = <String, int>{}.obs;

  /// 防止并发加载竞态
  int _loadGeneration = 0;

  StreamSubscription<dynamic>? _historySub;

  @override
  void onInit() {
    _historySub = EventBus.instance.listen(Constant.kUpdateHistory, (_) {
      refreshData();
    });
    super.onInit();
  }

  @override
  void onClose() {
    _loadGeneration++;
    _historySub?.cancel();
    super.onClose();
  }

  @override
  Future<List<History>> getData(int page, int pageSize) {
    if (page > 1) {
      return Future.value([]);
    }
    var items = DBService.instance.getHistores();
    Future.microtask(() => _loadLiveStatus(items));
    return Future.value(items);
  }

  /// 并发查询所有历史项的直播状态
  Future<void> _loadLiveStatus(List<History> items) async {
    final generation = ++_loadGeneration;
    final ids = items.map((item) => item.id).toSet();
    liveStatusMap.removeWhere((key, _) => !ids.contains(key));
    if (items.isEmpty || isClosed) return;
    for (var item in items) {
      liveStatusMap[item.id] = 0;
    }
    const concurrency = 5;
    for (var i = 0; i < items.length; i += concurrency) {
      if (isClosed || _loadGeneration != generation) return;
      final batch = items.skip(i).take(concurrency);
      await Future.wait(
        batch.map((item) => _updateItemStatus(item, generation)),
      );
    }
  }

  Future<void> _updateItemStatus(History item, int generation) async {
    try {
      if (isClosed || _loadGeneration != generation) return;
      var site = Sites.allSites[item.siteId];
      if (site == null) {
        liveStatusMap[item.id] = 0;
        return;
      }
      var status = await site.liveSite.getLiveStatusDetail(roomId: item.roomId);
      if (isClosed || _loadGeneration != generation) return;
      if (list.any((row) => row.id == item.id)) liveStatusMap[item.id] = status;
    } catch (e) {
      Log.logPrint(e);
      if (!isClosed &&
          _loadGeneration == generation &&
          list.any((row) => row.id == item.id)) {
        liveStatusMap[item.id] = 0;
      }
    }
  }

  Future<void> importHistory() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      final source = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();
      // Validate every row before touching storage. Empty imports are harmless.
      final rows = HistoryTransfer.decode(source);
      final additions = <String, History>{};
      for (final entry in rows.entries) {
        final item = History.fromJson(entry.value);
        final existing = DBService.instance.historyBox.get(entry.key);
        if (existing == null || item.updateTime.isAfter(existing.updateTime)) {
          additions[entry.key] = item;
        }
      }
      if (additions.isNotEmpty) {
        await DBService.instance.historyBox.putAll(additions);
        await DBService.instance.historyBox.flush();
        EventBus.instance.emit(Constant.kUpdateHistory, null);
        refreshData();
      }
      SmartDialog.showToast('导入完成，合并 ${additions.length} 条记录');
    } on FormatException catch (e) {
      SmartDialog.showToast('导入失败：${e.message}');
    } catch (_) {
      SmartDialog.showToast('导入失败，请检查文件和存储权限');
    }
  }

  Future<void> exportHistory() async {
    try {
      final source = HistoryTransfer.encode(
        DBService.instance.getHistores().map((item) => item.toJson()),
      );
      final bytes = Uint8List.fromList(utf8.encode(source));
      if (Platform.isAndroid || Platform.isIOS) {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(
                bytes,
                mimeType: 'application/json',
                name: 'history.json',
              ),
            ],
            fileNameOverrides: ['history.json'],
          ),
        );
        return;
      }
      final path = await FilePicker.platform.saveFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
        fileName: 'history.json',
      );
      if (path == null) return;
      await File(path).writeAsBytes(bytes, flush: true);
      SmartDialog.showToast('导出成功');
    } catch (_) {
      SmartDialog.showToast('导出失败，请检查存储权限');
    }
  }

  Future<void> clean() async {
    if (!await Utils.showAlertDialog("确定要清空观看记录吗?", title: "清空观看记录")) return;
    try {
      await DBService.instance.historyBox.clear();
      await DBService.instance.historyBox.flush();
      _loadGeneration++;
      liveStatusMap.clear();
      EventBus.instance.emit(Constant.kUpdateHistory, null);
      await refreshData();
    } catch (error, stack) {
      Log.e('清空观看记录失败: $error', stack);
      SmartDialog.showToast('清空失败，请检查存储权限');
    }
  }

  Future<bool> removeItem(History item) async {
    try {
      await DBService.instance.historyBox.delete(item.id);
      await DBService.instance.historyBox.flush();
      liveStatusMap.remove(item.id);
      list.removeWhere((row) => row.id == item.id);
      pageEmpty.value = list.isEmpty;
      EventBus.instance.emit(Constant.kUpdateHistory, null);
      return true;
    } catch (error, stack) {
      Log.e('删除观看记录失败: $error', stack);
      SmartDialog.showToast('删除失败，请重试');
      return false;
    }
  }
}
