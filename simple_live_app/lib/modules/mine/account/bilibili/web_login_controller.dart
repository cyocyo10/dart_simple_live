import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';

class BiliBiliWebLoginController extends BaseController {
  InAppWebViewController? webViewController;
  CookieManager? cookieManager;
  bool _capturing = false;
  bool _completed = false;
  bool _qrOpen = false;

  void onWebViewCreated(
    InAppWebViewController controller,
    CookieManager manager,
  ) {
    webViewController = controller;
    cookieManager = manager;
  }

  void toQRLogin() async {
    if (_qrOpen || _completed || isClosed) return;
    BiliBiliAccountService.instance.cancelPendingLogin();
    _qrOpen = true;
    try {
      final result = await Get.toNamed(RoutePath.kBiliBiliQRLogin);
      if (!isClosed && result == true && !_completed) {
        _completed = true;
        Get.back(result: true);
      }
    } finally {
      _qrOpen = false;
    }
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    if (uri != null &&
        isLoginHost(uri.host, 'bilibili.com') &&
        uri.host != 'passport.bilibili.com') {
      logined();
    }
  }

  Future<void> manualCapture() async {
    if (_capturing || _completed || _qrOpen || isClosed) return;
    if (!await logined() && !isClosed && !_completed && !_qrOpen) {
      SmartDialog.showToast('未检测到有效登录态，请先完成登录');
    }
  }

  @override
  void onClose() {
    BiliBiliAccountService.instance.cancelPendingLogin();
    super.onClose();
  }

  Future<bool> logined() async {
    if (_capturing ||
        _completed ||
        _qrOpen ||
        isClosed ||
        cookieManager == null) {
      return false;
    }
    _capturing = true;
    try {
      final cookies = await cookieManager!.getCookies(
        url: WebUri('https://www.bilibili.com/'),
      );
      if (isClosed || _qrOpen) return false;
      final cookie = cookies
          .where(
            (c) =>
                c.domain == null ||
                isLoginHost(
                  c.domain!.replaceFirst(RegExp(r'^\.'), ''),
                  'bilibili.com',
                ),
          )
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (!hasBiliSession(cookie)) return false;
      final account = BiliBiliAccountService.instance;
      if (!await account.loginCookie(cookie) || isClosed || _qrOpen) {
        return false;
      }
      _completed = true;
      Get.back(result: true);
      return true;
    } catch (_) {
      if (!isClosed) SmartDialog.showToast('读取登录信息失败，请重试或使用扫码登录');
      return false;
    } finally {
      _capturing = false;
    }
  }
}
