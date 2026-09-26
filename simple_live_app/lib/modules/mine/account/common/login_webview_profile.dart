import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';

/// One environment per process, backed by the shared app-support login profile.
class LoginWebViewProfile {
  static Future<WebViewEnvironment?>? _environment;

  static Future<WebViewEnvironment?> environment() async {
    if (!Platform.isWindows) return null;
    final pending = _environment ??= _create();
    try {
      return await pending;
    } catch (_) {
      if (identical(_environment, pending)) _environment = null;
      rethrow;
    }
  }

  static Future<WebViewEnvironment> _create() async {
    final version = await WebViewEnvironment.getAvailableVersion();
    if (version == null || version.isEmpty) {
      throw StateError('Edge WebView2 Runtime is unavailable');
    }
    final support = await getApplicationSupportDirectory();
    return WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: '${support.path}${Platform.pathSeparator}login_webview',
      ),
    );
  }

  static Future<void> clearCookiesForOrigins(List<String> origins) async {
    final manager = await cookieManager();
    for (final origin in origins) {
      final url = WebUri(origin);
      final cookies = await manager.getCookies(url: url);
      for (final cookie in cookies) {
        await manager.deleteCookie(
          url: url,
          name: cookie.name,
          domain: cookie.domain,
          path: cookie.path ?? '/',
        );
      }
    }
  }

  static Future<CookieManager> cookieManager() async =>
      CookieManager.instance(webViewEnvironment: await environment());
}
