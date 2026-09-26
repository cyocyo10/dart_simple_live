import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:simple_live_app/app/log.dart';

import 'package:flutter_easyrefresh/easy_refresh.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';

class BaseController extends GetxController {
  /// 加载中，更新页面
  var pageLoadding = false.obs;

  /// 加载中,不会更新页面
  var loadding = false;

  /// 空白页面
  var pageEmpty = false.obs;

  /// 页面错误
  var pageError = false.obs;

  /// 未登录
  var notLogin = false.obs;

  /// 错误信息
  var errorMsg = "".obs;

  /// 显示错误
  /// * [msg] 错误信息
  /// * [showPageError] 显示页面错误
  /// * 只在第一页加载错误时showPageError=true，后续页加载错误时使用Toast弹出通知
  void handleError(Object exception, {bool showPageError = false}) {
    Log.e(exception.toString(), StackTrace.current);
    var msg = exceptionToString(exception);

    if (showPageError) {
      pageError.value = true;
      errorMsg.value = msg;
    } else {
      SmartDialog.showToast(exceptionToString(msg));
    }
  }

  String exceptionToString(Object exception) {
    return exception.toString().replaceAll("Exception:", "");
  }

  void onLogin() {}
  void onLogout() {}
}

class BasePageController<T> extends BaseController {
  final ScrollController scrollController = ScrollController();
  final EasyRefreshController easyRefreshController = EasyRefreshController();
  int currentPage = 1;
  int count = 0;
  int maxPage = 0;
  int pageSize = 24;
  var canLoadMore = false.obs;
  var list = <T>[].obs;

  int _requestGeneration = 0;
  bool _disposed = false;

  void cancelPendingLoad() {
    _requestGeneration++;
    loadding = false;
    pageLoadding.value = false;
  }

  Future<void> refreshData() async {
    if (_disposed) return;
    cancelPendingLoad();
    currentPage = 1;
    list.clear();
    canLoadMore.value = false;
    await loadData();
  }

  Future<void> loadData() async {
    // Returning from inside try/finally used to release another request's gate.
    if (loadding || _disposed) return;
    final generation = _requestGeneration;
    final page = currentPage;
    loadding = true;
    pageError.value = false;
    pageEmpty.value = false;
    notLogin.value = false;
    pageLoadding.value = page == 1;
    try {
      final result = await getData(page, pageSize);
      if (_disposed || generation != _requestGeneration) return;
      if (page == 1) {
        list.assignAll(result);
      } else {
        list.addAll(result);
      }
      currentPage = result.isNotEmpty ? page + 1 : page;
      canLoadMore.value = result.isNotEmpty;
      pageEmpty.value = list.isEmpty;
    } catch (e) {
      if (!_disposed && generation == _requestGeneration) {
        handleError(e, showPageError: page == 1);
      }
    } finally {
      if (!_disposed && generation == _requestGeneration) {
        loadding = false;
        pageLoadding.value = false;
      }
    }
  }

  @override
  void onClose() {
    _disposed = true;
    _requestGeneration++;
    scrollController.dispose();
    easyRefreshController.dispose();
    super.onClose();
  }

  Future<List<T>> getData(int page, int pageSize) async {
    return [];
  }

  void scrollToTopOrRefresh() {
    if (scrollController.hasClients && scrollController.offset > 0) {
      scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.linear,
      );
    } else {
      easyRefreshController.callRefresh();
    }
  }
}
