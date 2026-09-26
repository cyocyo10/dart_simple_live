/// Only inspect session markers; never inspect credentials entered in the page.
Map<String, String> loginCookieValues(String cookie) {
  final values = <String, String>{};
  for (final part in cookie.split(';')) {
    final separator = part.indexOf('=');
    if (separator > 0) {
      values[part.substring(0, separator).trim()] =
          part.substring(separator + 1).trim();
    }
  }
  return values;
}

bool isLoginHost(String host, String domain) =>
    host.toLowerCase() == domain || host.toLowerCase().endsWith('.$domain');

bool hasBiliSession(String cookie) {
  final values = loginCookieValues(cookie);
  return (values['SESSDATA']?.isNotEmpty ?? false) &&
      (int.tryParse(values['DedeUserID'] ?? '') ?? 0) > 0;
}

bool hasDouyinSession(String cookie) {
  final values = loginCookieValues(cookie);
  return [
    'sessionid',
    'sessionid_ss',
    'sid_tt',
    'sid_guard',
  ].any((key) => values[key]?.isNotEmpty ?? false);
}

const douyuLoginUrl = 'https://passport.douyu.com/';
const biliLoginUrl = 'https://passport.bilibili.com/login';
// Use the official page's visible login button, never a passport JSON API.
const douyinLoginUrl = 'https://live.douyin.com/';
