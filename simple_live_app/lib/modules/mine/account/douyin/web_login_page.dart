import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/modules/mine/account/common/login_web_view.dart';
import 'package:simple_live_app/modules/mine/account/douyin/web_login_controller.dart';

class DouyinWebLoginPage extends StatefulWidget {
  const DouyinWebLoginPage({super.key});

  @override
  State<DouyinWebLoginPage> createState() => _DouyinWebLoginPageState();
}

class _DouyinWebLoginPageState extends State<DouyinWebLoginPage>
    with WidgetsBindingObserver {
  final controller = Get.find<DouyinWebLoginController>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    controller.setForeground(state == AppLifecycleState.resumed);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.pause();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('抖音账号登录'),
          actions: [
            TextButton(
              onPressed: controller.manualCapture,
              child: const Text('完成登录'),
            ),
          ],
        ),
        body: Column(
          children: [
            Obx(() => controller.pageMessage.value.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(controller.pageMessage.value),
                  )),
            Expanded(
              child: LoginWebView(
                loginUrl: douyinLoginUrl,
                useNativeUserAgent: true,
                helpText:
                    '打开抖音官方登录框，登录后会自动保存。外部浏览器的登录信息不会自动共享，请复制后使用“粘贴 Cookie”。',
                onCreated: controller.onWebViewCreated,
                onLoadStart: controller.onLoadStart,
                onLoadStop: controller.onLoadStop,
                fallbackActions: [
                  TextButton.icon(
                    onPressed: () => controller.pasteCookie(
                      Get.find<AccountController>().doDouyinSearchCookieInput,
                    ),
                    icon: const Icon(Icons.content_paste),
                    label: const Text('粘贴 Cookie'),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
}
