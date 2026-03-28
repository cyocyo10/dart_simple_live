import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class AccountController extends GetxController {
  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
      }
    } else {
      //AppNavigator.toBiliBiliLogin();
      bilibiliLogin();
    }
  }

  void bilibiliLogin() {
    Utils.showBottomSheet(
      title: "登录哔哩哔哩",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("Web登录"),
              subtitle: const Text("填写用户名密码登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kBiliBiliWebLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text("扫码登录"),
            subtitle: const Text("使用哔哩哔哩APP扫描二维码登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              Get.toNamed(RoutePath.kBiliBiliQRLogin);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动输入Cookie登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doBiliBiliCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  void doBiliBiliCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入Cookie",
      hintText: "请输入Cookie",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    BiliBiliAccountService.instance.setCookie(cookie);
    await BiliBiliAccountService.instance.loadUserInfo();
  }

  void douyinTap() async {
    if (DouyinAccountService.instance.hasSearchCookie.value) {
      var result = await Utils.showAlertDialog(
        "退出后抖音搜索功能将不可用，ttwid 配置不受影响。",
        title: "退出抖音搜索账号",
      );
      if (result) {
        DouyinAccountService.instance.clearSearchCookie();
        SmartDialog.showToast("已退出，搜索将使用匿名模式");
      }
    } else {
      douyinLogin();
    }
  }

  void douyinLogin() {
    Utils.showBottomSheet(
      title: "抖音直播",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.search),
              title: const Text("登录以启用搜索"),
              subtitle: const Text("在 WebView 中登录抖音，仅用于搜索"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kDouyinWebLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("手动输入搜索 Cookie"),
            subtitle: const Text("从浏览器复制完整 Cookie"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doDouyinSearchCookieInput();
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text("配置 ttwid"),
            subtitle: const Text("自定义通用 Cookie（不影响搜索）"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doDouyinCookieConfig();
            },
          ),
        ],
      ),
    );
  }

  void doDouyinSearchCookieInput() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "输入抖音搜索 Cookie",
      hintText: "从浏览器登录 douyin.com 后复制完整 Cookie",
    );
    if (cookie == null || cookie.isEmpty) return;
    DouyinAccountService.instance.setSearchCookie(cookie);
    SmartDialog.showToast("搜索 Cookie 已保存");
  }

  void doDouyinCookieConfig() {
    // 初始化文本框时，只显示 ttwid 的值部分
    var savedCookie = DouyinAccountService.instance.cookie;
    var displayText = savedCookie;
    if (savedCookie.startsWith('ttwid=')) {
      displayText = savedCookie.substring(6); // 去掉 "ttwid="
    }
    var controller = TextEditingController(text: displayText);

    Get.dialog(
      AlertDialog(
        title: const Text("配置抖音 ttwid"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "默认已内置有效的 ttwid，可观看所有画质（包括蓝光）。\n如有需要可自定义配置。",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: "请粘贴 ttwid 值（留空则使用默认值）",
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {
                  // 提取 ttwid 的值部分（去掉 "ttwid=" 前缀）
                  var defaultValue = DouyinSite.kDefaultCookie;
                  if (defaultValue.startsWith('ttwid=')) {
                    defaultValue = defaultValue.substring(6); // 去掉 "ttwid="
                  }
                  controller.text = defaultValue;
                },
                icon: const Icon(Icons.restore),
                label: const Text("恢复默认 ttwid"),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              var input = controller.text.trim();
              Get.back();
              if (input.isEmpty) {
                DouyinAccountService.instance.clearCookie();
                SmartDialog.showToast("已清除自定义 Cookie，将使用默认 ttwid");
              } else {
                // 如果用户只输入了 ttwid 值，自动添加 "ttwid=" 前缀
                var cookie = input;
                if (!input.startsWith('ttwid=')) {
                  cookie = 'ttwid=$input';
                }
                DouyinAccountService.instance.setCookie(cookie);
                SmartDialog.showToast("ttwid 已保存");
              }
            },
            child: const Text("确定"),
          ),
        ],
      ),
    );
  }
}
