import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/bilibili/web_login_controller.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/modules/mine/account/common/login_web_view.dart';

class BiliBiliWebLoginPage extends GetView<BiliBiliWebLoginController> {
  const BiliBiliWebLoginPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('哔哩哔哩账号登录'),
          actions: [
            TextButton(
              onPressed: controller.manualCapture,
              child: const Text('完成登录'),
            ),
          ],
        ),
        body: LoginWebView(
          loginUrl: biliLoginUrl,
          onCreated: controller.onWebViewCreated,
          onLoadStop: controller.onLoadStop,
          fallbackActions: [
            TextButton.icon(
              onPressed: controller.toQRLogin,
              icon: const Icon(Icons.qr_code),
              label: const Text('二维码登录'),
            ),
          ],
        ),
      );
}
