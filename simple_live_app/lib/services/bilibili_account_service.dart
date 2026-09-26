import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/models/account/bilibili_user_info_page.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/modules/mine/account/common/login_webview_profile.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class BiliBiliAccountService extends GetxService {
  BiliBiliAccountService({
    Future<dynamic> Function(String)? fetchAccount,
    this.refreshProfileOnRestore = true,
  }) : _fetchAccount = fetchAccount ?? _requestAccount;

  /// Playback windows need the shared session, not another profile request.
  /// Explicit login and loadUserInfo still perform server verification.
  final bool refreshProfileOnRestore;
  final Future<dynamic> Function(String) _fetchAccount;
  static BiliBiliAccountService get instance =>
      Get.find<BiliBiliAccountService>();
  final logined = false.obs;
  String cookie = '';
  int uid = 0;
  final name = '未登录'.obs;
  int _loginGeneration = 0;

  static Future<dynamic> _requestAccount(String cookie) =>
      HttpClient.instance.getJson(
        'https://api.bilibili.com/x/member/web/account',
        header: {'Cookie': cookie},
      );

  @override
  void onInit() {
    reloadFromStorage();
    super.onInit();
  }

  void reloadFromStorage() {
    final next = LocalStorageService.instance
        .getValue(LocalStorageService.kBilibiliCookie, '');
    if (next == cookie) return;
    cancelPendingLogin();
    _applyCookie(next);
    if (refreshProfileOnRestore) loadUserInfo();
  }

  void _applyCookie(String value) {
    cookie = value;
    logined.value = hasBiliSession(value);
    name.value = logined.value ? '已登录' : '未登录';
    uid = int.tryParse(
            RegExp(r'(?:^|;\s*)DedeUserID=(\d+)').firstMatch(value)?.group(1) ??
                '') ??
        0;
    setSite();
  }

  void cancelPendingLogin() => _loginGeneration++;

  /// A candidate replaces the saved account only after the server confirms it.
  Future<bool> loginCookie(String candidate) async {
    if (!hasBiliSession(candidate)) return false;
    final generation = ++_loginGeneration;
    try {
      final result = await _fetchAccount(candidate);
      if (generation != _loginGeneration || isClosed) return false;
      if (result['code'] != 0) {
        SmartDialog.showToast('登录验证失败，请重新登录或检查 Cookie');
        return false;
      }
      final info = BiliBiliUserInfoModel.fromJson(result['data']);
      if ((info.mid ?? 0) <= 0) return false;
      await LocalStorageService.instance
          .setValue(LocalStorageService.kBilibiliCookie, candidate);
      // The shared-store notification can already have applied this same cookie.
      // A logout or a different login must still take precedence.
      if (generation != _loginGeneration && cookie != candidate) return false;
      _applyCookie(candidate);
      name.value = info.uname ?? '已登录';
      uid = info.mid!;
      setSite();
      return true;
    } catch (error, stack) {
      Log.e('哔哩哔哩登录验证失败', stack);
      if (generation == _loginGeneration && !isClosed) {
        SmartDialog.showToast('登录验证失败，请检查网络后重试');
      }
      return false;
    }
  }

  Future<bool> loadUserInfo() async {
    if (cookie.isEmpty) return false;
    final requestedCookie = cookie;
    final generation = _loginGeneration;
    try {
      final result = await _fetchAccount(requestedCookie);
      if (cookie != requestedCookie ||
          generation != _loginGeneration ||
          isClosed) return false;
      if (result['code'] == 0) {
        final info = BiliBiliUserInfoModel.fromJson(result['data']);
        if ((info.mid ?? 0) <= 0) return false;
        name.value = info.uname ?? '已登录';
        uid = info.mid!;
        logined.value = true;
        setSite();
        return true;
      }
      // Temporary verification errors must not erase a shared credential.
    } catch (_) {
      // The account screen allows explicit retry or logout.
    }
    return false;
  }

  void setSite() {
    final site = Sites.allSites[Constant.kBiliBili]!.liveSite as BiliBiliSite;
    site.userId = uid;
    site.cookie = cookie;
  }

  Future<void> setCookie(String value) async {
    cancelPendingLogin();
    _applyCookie(value);
    await LocalStorageService.instance
        .setValue(LocalStorageService.kBilibiliCookie, value);
  }

  Future<void> logout() async {
    await setCookie('');
    try {
      await LoginWebViewProfile.clearCookiesForOrigins([
        'https://www.bilibili.com/',
        'https://passport.bilibili.com/',
        'https://live.bilibili.com/',
      ]);
    } catch (error) {
      Log.w('账号已退出，网页登录缓存清理未完成');
      Log.d('网页登录缓存清理错误: $error');
    }
  }
}
