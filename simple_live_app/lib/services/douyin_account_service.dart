import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinAccountService extends GetxService {
  static DouyinAccountService get instance =>
      Get.find<DouyinAccountService>();

  /// ttwid Cookie（通用请求：房间/分类/弹幕）
  var cookie = "";
  var hasCookie = false.obs;

  /// 登录 Cookie（仅搜索用，隐私隔离）
  var searchCookie = "";
  var hasSearchCookie = false.obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = cookie.isNotEmpty;
    searchCookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinSearchCookie, "");
    hasSearchCookie.value = searchCookie.isNotEmpty;
    setSite();
    super.onInit();
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
    site.searchCookie = searchCookie;
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, cookie);
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void setSearchCookie(String cookie) {
    searchCookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinSearchCookie, cookie);
    hasSearchCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() {
    cookie = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = false;
    setSite();
  }

  void clearSearchCookie() {
    searchCookie = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinSearchCookie, "");
    hasSearchCookie.value = false;
    setSite();
  }
}
