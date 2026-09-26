import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/modules/mine/account/douyin/login_flow.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:get/get.dart';

class DouyinWebLoginController extends BaseController {
  InAppWebViewController? webViewController;
  CookieManager? cookieManager;
  final pageMessage = ''.obs;
  final _capture = DouyinLoginCapture();
  Timer? _poll;
  Uri? _uri;
  int _generation = 0;
  int _entryAttempts = 0;
  bool _inspecting = false;
  bool _entryFinished = false;
  bool _foreground = true;
  bool _cookieInput = false;
  bool _captureFailed = false;

  void onWebViewCreated(
    InAppWebViewController controller,
    CookieManager manager,
  ) {
    webViewController = controller;
    cookieManager = manager;
  }

  void onLoadStart(Uri? uri) {
    pause();
    _uri = uri;
    _entryAttempts = 0;
    _entryFinished = false;
    pageMessage.value = '';
  }

  void onLoadStop(InAppWebViewController controller, Uri? uri) {
    _uri = uri;
    if (isDouyinLoginPage(uri)) resume();
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) {
      resume();
    } else {
      pause();
    }
  }

  void pause() {
    _generation++;
    _poll?.cancel();
    _poll = null;
    _capture.pause();
  }

  void resume() {
    if (isClosed ||
        !_foreground ||
        _cookieInput ||
        _capture.completed ||
        !isDouyinLoginPage(_uri)) {
      return;
    }
    _capture.resume();
    _poll ??= Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    _tick();
  }

  bool get _canCapture =>
      !isClosed &&
      _foreground &&
      !_cookieInput &&
      isDouyinLoginPage(_uri) &&
      Get.currentRoute == RoutePath.kDouyinWebLogin;

  Future<void> _tick() async {
    if (!_canCapture) {
      // Stop pending reads while another route is on top. Keep the timer to
      // notice returning from a browser or another in-app route.
      _capture.pause();
      return;
    }
    _capture.resume();
    await _inspectLoginEntry();
    await _tryCaptureLoginCookie();
  }

  Future<void> _inspectLoginEntry() async {
    if (_inspecting ||
        _entryFinished ||
        _entryAttempts >= 15 ||
        webViewController == null ||
        !_canCapture) {
      return;
    }
    _inspecting = true;
    final generation = _generation;
    _entryAttempts++;
    try {
      final result = await webViewController!.evaluateJavascript(
        source: douyinOpenLoginScript,
      );
      if (isClosed || generation != _generation || !_canCapture) return;
      if (result is String) {
        final error = douyinLoginPageError(result);
        if (error != null) {
          pageMessage.value = error;
          _entryFinished = true;
        } else if (result == 'opened' || result == 'dialog') {
          _entryFinished = true;
        } else if (_entryAttempts == 15) {
          pageMessage.value = '请点击官方页面右上方的“登录”，完成后会自动保存登录信息。';
        }
      }
    } catch (_) {
      // The official page remains clickable if automation is unsupported.
      if (!isClosed && generation == _generation) {
        pageMessage.value = '请手动点击官方页面的“登录”。';
      }
    } finally {
      _inspecting = false;
    }
  }

  Future<bool> _tryCaptureLoginCookie() async {
    if (!_canCapture || cookieManager == null) return false;
    _captureFailed = false;
    try {
      final saved = await _capture.capture(
        readCookie: () async {
          final values = <String, String>{};
          // Live-host scoped cookies and shared .douyin.com cookies may differ.
          for (final origin in ['https://www.douyin.com/', douyinLoginUrl]) {
            final cookies =
                await cookieManager!.getCookies(url: WebUri(origin));
            if (!_canCapture) return '';
            for (final cookie in cookies) {
              if (cookie.domain == null ||
                  isLoginHost(cookie.domain!.replaceFirst(RegExp(r'^\.'), ''),
                      'douyin.com')) {
                values[cookie.name] = cookie.value;
              }
            }
          }
          return values.entries
              .map((entry) => '${entry.key}=${entry.value}')
              .join('; ');
        },
        saveCookie: DouyinAccountService.instance.setSearchCookie,
      );
      if (!saved || !_canCapture) return false;
      pause();
      SmartDialog.showToast('抖音登录信息已保存，搜索功能已启用');
      Get.back(result: true);
      return true;
    } catch (_) {
      _captureFailed = true;
      if (_canCapture) {
        pageMessage.value = '读取或保存登录信息失败，请重试或使用 Cookie 登录';
      }
      return false;
    }
  }

  Future<void> manualCapture() async {
    if (_capture.completed || !_canCapture) return;
    if (!await _tryCaptureLoginCookie() && _canCapture && !_captureFailed) {
      SmartDialog.showToast('未检测到登录态，请先完成登录');
    }
  }

  Future<void> pasteCookie(Future<bool> Function() input) async {
    if (_cookieInput || isClosed || _capture.completed) return;
    _cookieInput = true;
    pause();
    try {
      // Drain old persistence before pasted credentials replace it.
      await _capture.idle;
      if (isClosed) return;
      if (await input() && !isClosed) Get.back(result: true);
    } finally {
      _cookieInput = false;
      if (!isClosed) resume();
    }
  }

  @override
  void onClose() {
    pause();
    super.onClose();
  }
}
