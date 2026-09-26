import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/modules/mine/account/common/login_webview_profile.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinAccountService extends GetxService {
  static DouyinAccountService get instance => Get.find<DouyinAccountService>();

  /// ttwid Cookie（通用请求：房间/分类/弹幕）
  var cookie = "";
  var hasCookie = false.obs;

  /// 登录 Cookie（仅搜索用，隐私隔离）
  var searchCookie = "";
  var hasSearchCookie = false.obs;

  @override
  void onInit() {
    reloadFromStorage();
    super.onInit();
  }

  void reloadFromStorage() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = cookie.isNotEmpty;
    searchCookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinSearchCookie, "");
    hasSearchCookie.value = searchCookie.isNotEmpty;
    setSite();
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
    site.searchCookie = searchCookie;
  }

  Future<void> setCookie(String cookie) async {
    this.cookie = cookie;
    await LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, cookie);
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  Future<void> setSearchCookie(String cookie) async {
    await LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinSearchCookie, cookie);
    searchCookie = cookie;
    hasSearchCookie.value = cookie.isNotEmpty;
    setSite();
  }

  Future<void> clearCookie() async {
    cookie = "";
    await LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = false;
    setSite();
  }

  Future<void> clearSearchCookie() async {
    searchCookie = "";
    await LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinSearchCookie, "");
    hasSearchCookie.value = false;
    setSite();
    try {
      await LoginWebViewProfile.clearCookiesForOrigins([
        'https://www.douyin.com/',
        'https://live.douyin.com/',
        'https://sso.douyin.com/',
      ]);
    } catch (_) {
      Log.w('抖音搜索账号已退出，网页登录缓存清理未完成');
    }
  }
}
