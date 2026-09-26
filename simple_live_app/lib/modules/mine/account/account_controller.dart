import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/modules/mine/account/douyu/login_cookie.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/modules/mine/account/common/login_webview_profile.dart';
import 'package:simple_live_app/modules/mine/account/douyu/web_login_page.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class AccountController extends GetxController {
  @override
  void onClose() {
    BiliBiliAccountService.instance.cancelPendingLogin();
    super.onClose();
  }

  Future<bool> _saveAccount(Future<void> Function() save) async {
    try {
      await save();
      return !isClosed;
    } catch (_) {
      SmartDialog.showToast('账号信息保存失败，请检查存储权限后重试');
      return false;
    }
  }

  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        await _saveAccount(BiliBiliAccountService.instance.logout);
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
          ListTile(
            leading: const Icon(Icons.account_circle_outlined),
            title: const Text("Web登录"),
            subtitle: const Text("填写用户名密码登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              Get.toNamed(RoutePath.kBiliBiliWebLogin);
            },
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
    if (!hasBiliSession(cookie)) {
      SmartDialog.showToast('Cookie 缺少有效的 SESSDATA / DedeUserID');
      return;
    }
    if (await BiliBiliAccountService.instance.loginCookie(cookie)) {
      SmartDialog.showToast('哔哩哔哩登录成功');
    }
  }

  Future<void> douyuTap() async {
    if (AppSettingsController.instance.douyuCookie.value.isNotEmpty) {
      if (await Utils.showAlertDialog(
        '确定要退出斗鱼账号并清除 Cookie 吗？',
        title: '退出登录',
      )) {
        if (!await _saveAccount(
            () => AppSettingsController.instance.setDouyuCookie(''))) return;
        // Clear only Douyu cookies so subsequent web login cannot reuse the session.
        try {
          await LoginWebViewProfile.clearCookiesForOrigins([
            'https://www.douyu.com/',
            'https://passport.douyu.com/',
          ]);
        } catch (_) {
          // WebView may not be installed; persisted app credentials are already cleared.
        }
        SmartDialog.showToast('已退出斗鱼账号');
      }
      return;
    }
    Utils.showBottomSheet(
      title: '登录斗鱼',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('网页登录'),
            subtitle: const Text('完成登录后点击“完成登录”保存账号'),
            onTap: () {
              Get.back();
              Get.to(
                () => DouyuWebLoginPage(
                  openBrowser: openDouyuBrowser,
                  pasteCookie: () => doDouyuCookieLogin(closeLoginPage: true),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: const Text('打开浏览器登录'),
            subtitle: const Text('直接打开斗鱼登录框，登录后复制 Cookie'),
            onTap: openDouyuBrowser,
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Cookie 登录'),
            onTap: () {
              Get.back();
              doDouyuCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  Future<void> openDouyuBrowser() async {
    try {
      final opened = await launchUrl(
        Uri.parse(douyuLoginUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) SmartDialog.showToast('无法打开浏览器');
    } catch (_) {
      SmartDialog.showToast('无法打开浏览器');
    }
  }

  Future<void> doDouyuCookieLogin({bool closeLoginPage = false}) async {
    final cookie = await Utils.showEditTextDialog(
      '',
      title: '输入斗鱼 Cookie',
      hintText: '从浏览器登录 douyu.com 后复制完整 Cookie',
    );
    if (cookie == null || cookie.trim().isEmpty) return;
    if (!hasDouyuSession(cookie)) {
      SmartDialog.showToast('Cookie 缺少斗鱼登录态 acf_uid / acf_auth');
      return;
    }
    if (!await _saveAccount(
        () => AppSettingsController.instance.setDouyuCookie(cookie))) return;
    if (closeLoginPage) Get.back();
    SmartDialog.showToast('斗鱼登录信息已保存');
  }

  void douyinTap() async {
    if (DouyinAccountService.instance.hasSearchCookie.value) {
      var result = await Utils.showAlertDialog(
        "退出后抖音搜索功能将不可用，ttwid 配置不受影响。",
        title: "退出抖音搜索账号",
      );
      if (result) {
        if (!await _saveAccount(
            DouyinAccountService.instance.clearSearchCookie)) return;
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
          ListTile(
            leading: const Icon(Icons.search),
            title: const Text("登录以启用搜索"),
            subtitle: const Text("在 WebView 中登录抖音，仅用于搜索"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              Get.toNamed(RoutePath.kDouyinWebLogin);
            },
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

  Future<bool> doDouyinSearchCookieInput() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "输入抖音搜索 Cookie",
      hintText: "从浏览器登录 douyin.com 后复制完整 Cookie",
    );
    if (cookie == null || cookie.isEmpty || isClosed) return false;
    if (!hasDouyinSession(cookie)) {
      SmartDialog.showToast('Cookie 中没有抖音登录态，请复制登录后的完整 Cookie');
      return false;
    }
    if (!await _saveAccount(
        () => DouyinAccountService.instance.setSearchCookie(cookie))) {
      return false;
    }
    SmartDialog.showToast("搜索 Cookie 已保存");
    return true;
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
          TextButton(onPressed: () => Get.back(), child: const Text("取消")),
          TextButton(
            onPressed: () async {
              var input = controller.text.trim();
              Get.back();
              if (input.isEmpty) {
                if (!await _saveAccount(
                    DouyinAccountService.instance.clearCookie)) return;
                SmartDialog.showToast("已清除自定义 Cookie，将使用默认 ttwid");
              } else {
                // 如果用户只输入了 ttwid 值，自动添加 "ttwid=" 前缀
                var cookie = input;
                if (!input.startsWith('ttwid=')) {
                  cookie = 'ttwid=$input';
                }
                if (!await _saveAccount(
                    () => DouyinAccountService.instance.setCookie(cookie)))
                  return;
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
