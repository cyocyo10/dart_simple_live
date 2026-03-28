import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';

class DouyinWebLoginController extends BaseController {
  InAppWebViewController? webViewController;
  final CookieManager cookieManager = CookieManager.instance();
  final loadProgress = 0.obs;

  void onWebViewCreated(InAppWebViewController controller) {
    webViewController = controller;
    webViewController!.loadUrl(
      urlRequest: URLRequest(
        url: WebUri("https://www.douyin.com/passport/general/login_guiding_strategy/?aid=6383"),
      ),
    );
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) async {
    if (uri == null) return;
    // 登录成功后会跳转到抖音主页
    if (uri.host == "www.douyin.com" && !uri.path.contains("passport")) {
      await _tryCaptureLoginCookie();
    }
  }

  Future<void> _tryCaptureLoginCookie() async {
    try {
      var cookies =
          await cookieManager.getCookies(url: WebUri("https://www.douyin.com"));
      if (cookies.isEmpty) return;

      // 检查是否包含登录态标识
      var hasSession = cookies.any((c) =>
          c.name == "sessionid" ||
          c.name == "sessionid_ss" ||
          c.name == "sid_tt" ||
          c.name == "sid_guard");
      if (!hasSession) return;

      var cookieStr = cookies.map((e) => "${e.name}=${e.value}").join(";");
      Log.i("[DouyinLogin] Cookie captured: ${cookieStr.length} chars");
      DouyinAccountService.instance.setSearchCookie(cookieStr);
      SmartDialog.showToast("抖音登录成功，搜索功能已启用");
      Get.back();
    } catch (e) {
      Log.e("[DouyinLogin] Failed to capture cookie", e);
    }
  }

  /// 手动触发 Cookie 抓取（给页面按钮用）
  Future<void> manualCapture() async {
    await _tryCaptureLoginCookie();
    var hasCookie = DouyinAccountService.instance.hasSearchCookie.value;
    if (!hasCookie) {
      SmartDialog.showToast("未检测到登录态，请先完成登录");
    }
  }
}
