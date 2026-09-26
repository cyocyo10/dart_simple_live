import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/data_import.dart';

class FollowService extends GetxService {
  FollowService({this.backgroundRefresh = true});

  /// Independent live windows share favorites, but only the main window polls
  /// every followed room. Explicit list refreshes remain available everywhere.
  final bool backgroundRefresh;
  StreamSubscription<dynamic>? subscription;
  static FollowService get instance => Get.find<FollowService>();

  final StreamController _updatedListController = StreamController.broadcast();
  Stream get updatedListStream => _updatedListController.stream;

  /// 关注用户列表
  RxList<FollowUser> followList = RxList<FollowUser>();

  /// 直播中的用户列表
  RxList<FollowUser> liveList = RxList<FollowUser>();

  /// 回放中的用户列表
  RxList<FollowUser> replayList = RxList<FollowUser>();

  /// 未直播的用户列表
  RxList<FollowUser> notLiveList = RxList<FollowUser>();

  /// 用户自定义的tag
  RxList<FollowUserTag> followTagList = RxList<FollowUserTag>();

  /// 当前tag的用户列表
  RxList<FollowUser> curTagFollowList = RxList<FollowUser>();

  /// 已经更新状态的数量
  var updatedCount = 0;

  /// 是否正在更新
  var updating = false.obs;

  Timer? updateTimer;
  int _statusGeneration = 0;

  @override
  void onInit() {
    subscription = EventBus.instance.listen(Constant.kUpdateFollow, (p0) {
      // 关注变更后立刻刷新内存列表，并通知关注页 UI
      unawaited(loadData(updateStatus: backgroundRefresh));
    });
    initTimer();
    super.onInit();
  }

  // 添加标签
  Future<void> addFollowUserTag(String tag) async {
    // 判断待添加tag是否已存在，存在则return
    if (followTagList.any((item) => item.tag == tag)) {
      SmartDialog.showToast("标签名重复，修改失败");
      return;
    }
    await DBService.instance.addFollowTag(tag);
    getAllTagList();
  }

  // 删除标签
  Future<void> delFollowUserTag(FollowUserTag tag) async {
    await DBService.instance.deleteFollowTag(tag.id);
    getAllTagList();
  }

  // 获取用户自定义标签列表
  void getAllTagList() {
    var list = DBService.instance.getFollowTagList();
    followTagList.assignAll(list);
  }

  // 修改标签
  Future<void> updateFollowUserTag(FollowUserTag tag) async {
    await DBService.instance.updateFollowTag(tag);
    getAllTagList();
  }

  // Filtering is read-only: a stale window must never delete tag membership.
  void filterDataByTag(FollowUserTag tag) {
    final ids = tag.userId.toSet();
    curTagFollowList
        .assignAll(followList.where((item) => ids.contains(item.id)));
    const priority = {2: 4, 3: 3, 1: 1, 0: 0};
    curTagFollowList.sort((a, b) => (priority[b.liveStatus.value] ?? 0)
        .compareTo(priority[a.liveStatus.value] ?? 0));
  }

  // 添加关注
  Future<void> addFollow(FollowUser follow) async {
    await DBService.instance.addFollow(follow);
  }

  void initTimer() {
    updateTimer?.cancel();
    updateTimer = null;
    if (!backgroundRefresh || isClosed) return;
    if (AppSettingsController.instance.autoUpdateFollowEnable.value) {
      updateTimer = Timer.periodic(
        Duration(
            minutes:
                AppSettingsController.instance.autoUpdateFollowDuration.value),
        (timer) {
          Log.logPrint("Update Follow Timer");
          loadData();
        },
      );
    }
  }

  Future<void> loadData({bool updateStatus = true}) async {
    if (isClosed) return;
    final generation = ++_statusGeneration;
    var list = DBService.instance.getFollowList();
    getAllTagList();
    if (list.isEmpty) {
      updating.value = false;
      followList.assignAll(list);
      liveList.clear();
      notLiveList.clear();
      replayList.clear();
      // 通知关注页（含清空后的 UI）
      _updatedListController.add(0);
      return;
    }
    followList.assignAll(list);
    if (updateStatus) {
      await startUpdateStatus(generation: generation);
    } else {
      // 不拉直播状态时也要刷新 live/notLive 分类并通知 UI
      // 新关注 liveStatus=0，会出现在「全部」中
      updating.value = false;
      filterData();
    }
  }

  /// 获取最优并发数
  /// 根据 CPU 核心数和用户设置自动计算
  int getOptimalConcurrency() {
    var userSetting =
        AppSettingsController.instance.updateFollowThreadCount.value;

    // 如果用户设置为 0，则自动根据 CPU 核心数计算
    if (userSetting == 0) {
      var cpuCount = Platform.numberOfProcessors;
      // 网络 I/O 密集型任务，并发数可以是 CPU 核心数的 2-3 倍
      var optimal = (cpuCount * 2.5).round();
      // 限制在合理范围内（最少 4，最多 20）
      return optimal.clamp(4, 20);
    }

    return userSetting.clamp(1, 20);
  }

  /// 按平台交错排列，避免单一平台阻塞
  List<FollowUser> interleaveByPlatform(List<FollowUser> list) {
    // 按平台分组
    var grouped = <String, Queue<FollowUser>>{};
    for (var item in list) {
      grouped.putIfAbsent(item.siteId, () => Queue<FollowUser>()).add(item);
    }

    // 交错处理
    var result = <FollowUser>[];
    while (grouped.values.any((queue) => queue.isNotEmpty)) {
      for (var queue in grouped.values) {
        if (queue.isNotEmpty) {
          result.add(queue.removeFirst());
        }
      }
    }

    return result;
  }

  Future<void> startUpdateStatus({int? generation}) async {
    final request = generation ?? ++_statusGeneration;
    updatedCount = 0;
    updating.value = true;
    final queue = Queue<FollowUser>.from(interleaveByPlatform(followList));
    bool active() => !isClosed && request == _statusGeneration;
    Future<void> worker() async {
      while (queue.isNotEmpty && active()) {
        final item = queue.removeFirst();
        await _updateLiveStatus(item, active);
        if (active()) updatedCount++;
      }
    }

    try {
      await Future.wait(
          List.generate(getOptimalConcurrency(), (_) => worker()));
    } finally {
      if (active()) {
        updating.value = false;
        filterData();
      }
    }
  }

  Future<void> _updateLiveStatus(
      FollowUser item, bool Function() active) async {
    try {
      final site = Sites.allSites[item.siteId];
      if (site == null) return;
      final status =
          await site.liveSite.getLiveStatusDetail(roomId: item.roomId);
      if (!active()) return;
      item.liveStatus.value = status;
      if (status == 2 || status == 3) {
        final detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
        if (!active()) return;
        item.liveStartTime = detail.showTime;
      } else {
        item.liveStartTime = null;
      }
    } catch (e) {
      Log.logPrint(e);
      if (active()) {
        item.liveStatus.value = 0;
        item.liveStartTime = null;
      }
    }
  }

  void filterData() {
    if (isClosed) return;
    // 排序优先级：直播(2) > 回放(3) > 未开播(1) > 加载中(0)
    const statusPriority = {2: 4, 3: 3, 1: 1, 0: 0};
    followList.sort((a, b) => (statusPriority[b.liveStatus.value] ?? 0)
        .compareTo(statusPriority[a.liveStatus.value] ?? 0));
    liveList.assignAll(followList.where((x) => x.liveStatus.value == 2));
    replayList.assignAll(followList.where((x) => x.liveStatus.value == 3));
    notLiveList.assignAll(followList
        .where((x) => x.liveStatus.value == 1 || x.liveStatus.value == 0));
    _updatedListController.add(0);
  }

  void exportFile() async {
    if (followList.isEmpty) {
      SmartDialog.showToast("列表为空");
      return;
    }

    try {
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("无权限");
        return;
      }

      var dir = "";
      if (Platform.isIOS) {
        dir = (await getApplicationDocumentsDirectory()).path;
      } else {
        dir = await FilePicker.platform.getDirectoryPath() ?? "";
      }

      if (dir.isEmpty) {
        return;
      }
      var jsonFile = File(
          '$dir/SimpleLive_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.json');
      var jsonText = generateJson();
      await jsonFile.writeAsString(jsonText);
      SmartDialog.showToast("已导出关注列表");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("导出失败：$e");
    }
  }

  void inputFile() async {
    try {
      var status = await Utils.checkStorgePermission();
      if (!status) {
        SmartDialog.showToast("无权限");
        return;
      }
      var file = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) {
        return;
      }
      var jsonFile = File(file.files.single.path!);
      await inputJson(await jsonFile.readAsString());
      SmartDialog.showToast("导入成功");
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("导入失败:$e");
    } finally {
      loadData();
    }
  }

  void exportText() {
    if (followList.isEmpty) {
      SmartDialog.showToast("列表为空");
      return;
    }
    var content = generateJson();
    Get.dialog(
      AlertDialog(
        title: const Text("导出为文本"),
        content: TextField(
          controller: TextEditingController(text: content),
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
          ),
          minLines: 5,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: const Text("关闭"),
          ),
          TextButton(
            onPressed: () {
              Utils.copyToClipboard(content);
              Get.back();
            },
            child: const Text("复制"),
          ),
        ],
      ),
    );
  }

  void inputText() async {
    final TextEditingController textController = TextEditingController();
    await Get.dialog(
      AlertDialog(
        title: const Text("从文本导入"),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: "请输入内容",
          ),
          minLines: 5,
          maxLines: 8,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Get.back();
            },
            child: const Text("关闭"),
          ),
          TextButton(
            onPressed: () async {
              var content = await Utils.getClipboard();
              if (content != null) {
                textController.text = content;
              }
            },
            child: const Text("粘贴"),
          ),
          TextButton(
            onPressed: () async {
              if (textController.text.isEmpty) {
                SmartDialog.showToast("内容为空");
                return;
              }
              try {
                await inputJson(textController.text);
                SmartDialog.showToast("导入成功");
                Get.back();
                loadData();
              } catch (e) {
                SmartDialog.showToast("导入失败，请检查内容是否正确");
              }
            },
            child: const Text("导入"),
          ),
        ],
      ),
    );
  }

  String generateJson() {
    var data = followList
        .map(
          (item) => {
            "siteId": item.siteId,
            "id": item.id,
            "roomId": item.roomId,
            "userName": item.userName,
            "face": item.face,
            "addTime": item.addTime.toString(),
            "tag": item.tag
          },
        )
        .toList();
    return jsonEncode(data);
  }

  Future<void> inputJson(String content) async {
    // Validate the final row as well before committing any follow or tag.
    final imported = DataImport.decodeFollowUsers(content);
    await DBService.instance.importFollows(imported);
  }

  @override
  void onClose() {
    _statusGeneration++;
    updateTimer?.cancel();
    subscription?.cancel();
    _updatedListController.close();
    super.onClose();
  }
}
