import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/modules/mine/account/common/login_web_view.dart';
import 'package:simple_live_app/modules/mine/account/douyu/login_cookie.dart';

class DouyuWebLoginPage extends StatefulWidget {
  final VoidCallback openBrowser;
  final VoidCallback pasteCookie;
  const DouyuWebLoginPage({
    super.key,
    required this.openBrowser,
    required this.pasteCookie,
  });

  @override
  State<DouyuWebLoginPage> createState() => _DouyuWebLoginPageState();
}

class _DouyuWebLoginPageState extends State<DouyuWebLoginPage> {
  InAppWebViewController? _webView;
  CookieManager? _cookieManager;
  bool _capturing = false;
  bool _completed = false;

  Future<void> _capture() async {
    if (_capturing || _completed || _cookieManager == null) return;
    _capturing = true;
    try {
      final uri = await _webView?.getUrl();
      if (!mounted) return;
      if (uri == null || !isDouyuHost(uri.host) || uri.scheme != 'https') {
        SmartDialog.showToast('请在斗鱼网页完成登录');
        return;
      }
      final cookies = await _cookieManager!.getCookies(
        url: WebUri('https://www.douyu.com/'),
      );
      if (!mounted) return;
      final cookie = cookies
          .where(
            (c) =>
                c.domain == null ||
                isDouyuHost(c.domain!.replaceFirst(RegExp(r'^\.'), '')),
          )
          .map((c) => '${c.name}=${c.value}')
          .join('; ');
      if (!hasDouyuSession(cookie)) {
        SmartDialog.showToast('未检测到登录态，请先完成登录');
        return;
      }
      await AppSettingsController.instance.setDouyuCookie(cookie);
      if (!mounted) return;
      _completed = true;
      SmartDialog.showToast('斗鱼登录信息已保存');
      Get.back(result: true);
    } catch (_) {
      if (mounted) SmartDialog.showToast('无法读取登录信息，可使用浏览器和 Cookie 登录');
    } finally {
      _capturing = false;
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('斗鱼账号登录'),
          actions: [TextButton(onPressed: _capture, child: const Text('完成登录'))],
        ),
        body: LoginWebView(
          loginUrl: douyuLoginUrl,
          onCreated: (controller, manager) {
            _webView = controller;
            _cookieManager = manager;
          },
          fallbackActions: [
            TextButton(
              onPressed: widget.pasteCookie,
              child: const Text('粘贴 Cookie'),
            ),
          ],
        ),
      );
}
