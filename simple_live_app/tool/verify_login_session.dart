import '../lib/modules/mine/account/common/login_session.dart';
import '../lib/modules/mine/account/douyu/login_cookie.dart';
import '../lib/modules/mine/account/douyin/login_flow.dart';

void main() {
  var count = 0;
  void check(bool condition, String message) {
    if (!condition) throw StateError(message);
    count++;
  }

  check(
    !hasBiliSession('buvid3=anonymous'),
    'Bili anonymous cookie is not login',
  );
  check(
    !hasBiliSession('SESSDATA=; DedeUserID=100'),
    'Empty Bili session rejected',
  );
  check(
    !hasBiliSession('SESSDATA=token; DedeUserID=0'),
    'Zero Bili user rejected',
  );
  check(
    hasBiliSession('SESSDATA=a=b; DedeUserID=123'),
    'Full Bili session accepted',
  );
  check(
    loginCookieValues('a=a=b; b= c ')['a'] == 'a=b',
    'Cookie equals preserved',
  );
  check(
    !hasDouyinSession('sessionid=; ttwid=anonymous'),
    'Empty Douyin session rejected',
  );
  check(
    !hasDouyinSession('ttwid=anonymous'),
    'Anonymous Douyin cookie rejected',
  );
  check(hasDouyinSession('sid_tt=token'), 'Douyin session accepted');
  check(
    !hasDouyuSession('acf_uid=0; acf_auth=token'),
    'Zero Douyu user rejected',
  );
  check(!hasDouyuSession('acf_uid=123'), 'Douyu auth required');
  check(
    hasDouyuSession('acf_uid=123; acf_auth=token'),
    'Douyu session accepted',
  );
  check(
    isLoginHost('passport.bilibili.com', 'bilibili.com'),
    'Bili login host accepted',
  );
  check(
    !isLoginHost('bilibili.com.evil.test', 'bilibili.com'),
    'Suffix lookalike rejected',
  );
  check(
    !isLoginHost('evilbilibili.com', 'bilibili.com'),
    'Prefix lookalike rejected',
  );
  check(!isDouyuHost('douyu.com.evil.test'), 'Douyu lookalike rejected');
  check(
    douyuLoginUrl == 'https://passport.douyu.com/',
    'Douyu targets login form',
  );
  check(douyinLoginUrl == 'https://live.douyin.com/',
      'Douyin uses its official HTML page, not a passport JSON API');
  check(!isDouyinLoginPage(Uri.parse('http://live.douyin.com/')),
      'Douyin login refuses plaintext navigation');
  check(
      douyinLoginPageError('{"data":{"error_code":4031},"message":"error"}') !=
          null,
      'Douyin passport rejection is recognized even with HTTP 200');
  print('Login session verification: $count checks passed');
}
