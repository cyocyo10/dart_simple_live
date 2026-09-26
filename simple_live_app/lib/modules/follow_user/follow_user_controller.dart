// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';

class FollowUserController extends BasePageController<FollowUser> {
  StreamSubscription<dynamic>? onUpdatedIndexedStream;
  StreamSubscription<dynamic>? onUpdatedListStream;

  /// 0:全部 1:直播中 2:回放中 3:未开播
  var filterMode = FollowUserTag(id: "0", tag: "全部", userId: []).obs;
  RxList<FollowUserTag> tagList = [
    FollowUserTag(id: "0", tag: "全部", userId: []),
    FollowUserTag(id: "1", tag: "直播中", userId: []),
    FollowUserTag(id: "2", tag: "回放中", userId: []),
    FollowUserTag(id: "3", tag: "未开播", userId: []),
  ].obs;

  // 用户自定义标签
  RxList<FollowUserTag> userTagList = <FollowUserTag>[].obs;

  @override
  void onInit() {
    onUpdatedIndexedStream = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
      (index) {
        if (index == 1) {
          scrollToTopOrRefresh();
        }
      },
    );
    onUpdatedListStream =
        FollowService.instance.updatedListStream.listen((event) {
      if (isClosed) return;
      updateTagList();
      filterData();
    });
    super.onInit();
  }

  @override
  Future refreshData() async {
    await FollowService.instance.loadData();
    if (isClosed) return;
    updateTagList();
    await super.refreshData();
  }

  @override
  Future<List<FollowUser>> getData(int page, int pageSize) async {
    if (page > 1) {
      return Future.value([]);
    }
    if (filterMode.value.id == "0") {
      return FollowService.instance.followList.value;
    } else if (filterMode.value.id == "1") {
      return FollowService.instance.liveList.value;
    } else if (filterMode.value.id == "2") {
      return FollowService.instance.replayList.value;
    } else if (filterMode.value.id == "3") {
      return FollowService.instance.notLiveList.value;
    } else {
      FollowService.instance.filterDataByTag(filterMode.value);
      return FollowService.instance.curTagFollowList.value;
    }
  }

  void updateTagList() {
    final selectedId = filterMode.value.id;
    userTagList.assignAll(FollowService.instance.followTagList);
    tagList.assignAll([...tagList.take(4), ...userTagList]);
    filterMode.value = tagList.firstWhere((tag) => tag.id == selectedId,
        orElse: () => tagList.first);
  }

  void filterData() {
    if (isClosed) return;
    if (filterMode.value.id == "0") {
      list.assignAll(FollowService.instance.followList.value);
    } else if (filterMode.value.id == "1") {
      list.assignAll(FollowService.instance.liveList.value);
    } else if (filterMode.value.id == "2") {
      list.assignAll(FollowService.instance.replayList.value);
    } else if (filterMode.value.id == "3") {
      list.assignAll(FollowService.instance.notLiveList.value);
    } else {
      FollowService.instance.filterDataByTag(filterMode.value);
      list.assignAll(FollowService.instance.curTagFollowList);
    }
    pageEmpty.value = list.isEmpty;
  }

  void setFilterMode(FollowUserTag tag) {
    filterMode.value = tag;
    filterData();
  }

  Future<bool> _perform(Future<void> Function() action) async {
    try {
      await action();
      await FollowService.instance.loadData(updateStatus: false);
      if (!isClosed) {
        updateTagList();
        filterData();
      }
      return true;
    } catch (error, stack) {
      Log.e('关注操作失败: $error', stack);
      SmartDialog.showToast(exceptionToString(error));
      return false;
    }
  }

  Future<void> removeItem(FollowUser item) async {
    if (!await Utils.showAlertDialog('确定要取消关注${item.userName}吗?',
        title: '取消关注')) return;
    await _perform(() => DBService.instance.deleteFollow(item.id));
  }

  Future<void> updateItem(FollowUser item) async {
    await _perform(() => FollowService.instance.addFollow(item));
  }

  Future<void> setItemTag(FollowUser item, FollowUserTag target) async {
    await _perform(() => DBService.instance
        .setFollowTag(item.id, target.id == '0' ? null : target.id));
  }

  Future<void> removeTag(FollowUserTag tag) async {
    await _perform(() => DBService.instance.deleteFollowTag(tag.id));
  }

  Future<void> addTag(String tag) async {
    await _perform(() => FollowService.instance.addFollowUserTag(tag));
  }

  Future<void> updateTagName(FollowUserTag tag, String name) async {
    if (tag.tag == name) return;
    if (await _perform(
        () => DBService.instance.renameFollowTag(tag.id, name))) {
      SmartDialog.showToast('标签名修改成功');
    }
  }

  Future<void> updateTagOrder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final order = userTagList.toList();
    final item = order.removeAt(oldIndex);
    order.insert(newIndex, item);
    await _perform(() => DBService.instance.updateFollowTagOrder(order));
  }

  @override
  void onClose() {
    onUpdatedIndexedStream?.cancel();
    onUpdatedListStream?.cancel();
    super.onClose();
  }
}
