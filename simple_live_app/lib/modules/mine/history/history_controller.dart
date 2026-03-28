import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
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
    if (items.isEmpty) return;
    final generation = ++_loadGeneration;
    for (var item in items) {
      liveStatusMap[item.id] = 0;
    }
    const concurrency = 5;
    for (var i = 0; i < items.length; i += concurrency) {
      if (_loadGeneration != generation) return;
      final batch = items.skip(i).take(concurrency);
      await Future.wait(batch.map((item) => _updateItemStatus(item, generation)));
    }
  }

  Future<void> _updateItemStatus(History item, int generation) async {
    try {
      if (_loadGeneration != generation) return;
      var site = Sites.allSites[item.siteId];
      if (site == null) {
        liveStatusMap[item.id] = 1;
        return;
      }
      var status = await site.liveSite.getLiveStatusDetail(roomId: item.roomId);
      if (_loadGeneration != generation) return;
      liveStatusMap[item.id] = status;
    } catch (e) {
      Log.logPrint(e);
      if (_loadGeneration == generation) {
        liveStatusMap[item.id] = 0;
      }
    }
  }

  void clean() async {
    var result = await Utils.showAlertDialog("确定要清空观看记录吗?", title: "清空观看记录");
    if (!result) {
      return;
    }
    await DBService.instance.historyBox.clear();
    liveStatusMap.clear();
    refreshData();
  }

  void removeItem(History item) async {
    await DBService.instance.historyBox.delete(item.id);
    liveStatusMap.remove(item.id);
    refreshData();
  }
}
