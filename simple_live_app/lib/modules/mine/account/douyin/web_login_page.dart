import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/douyin/web_login_controller.dart';

class DouyinWebLoginPage extends GetView<DouyinWebLoginController> {
  const DouyinWebLoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("抖音账号登录"),
        actions: [
          TextButton.icon(
            onPressed: controller.manualCapture,
            icon: const Icon(Icons.check),
            label: const Text("完成登录"),
          ),
        ],
      ),
      body: Stack(
        children: [
          InAppWebView(
            onWebViewCreated: controller.onWebViewCreated,
            onLoadStop: controller.onLoadStop,
            onProgressChanged: (webController, progress) {
              controller.loadProgress.value = progress;
            },
            initialSettings: InAppWebViewSettings(
              userAgent:
                  "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1",
              useShouldOverrideUrlLoading: true,
            ),
            shouldOverrideUrlLoading: (webController, navigationAction) async {
              var uri = navigationAction.request.url;
              if (uri == null) {
                return NavigationActionPolicy.ALLOW;
              }
              // 阻止跳转到抖音 App
              if (uri.scheme == "snssdk1128" || uri.scheme == "snssdk1233") {
                return NavigationActionPolicy.CANCEL;
              }
              return NavigationActionPolicy.ALLOW;
            },
          ),
          Obx(() {
            if (controller.loadProgress.value < 100) {
              return LinearProgressIndicator(
                value: controller.loadProgress.value / 100.0,
              );
            }
            return const SizedBox.shrink();
          }),
        ],
      ),
    );
  }
}
