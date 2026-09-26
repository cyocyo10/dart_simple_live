import '../lib/modules/mine/parse/room_link_parser.dart';

Future<void> main() async {
  var checks = 0;
  void check(bool condition, String label) {
    if (!condition) throw StateError(label);
    checks++;
  }

  var requests = 0;
  final direct = RoomLinkParser(redirect: (_) async {
    requests++;
    return null;
  });
  Future<void> room(String input, RoomLinkPlatform platform, String id) async {
    final link = await direct.parse(input);
    check(link?.platform == platform && link?.roomId == id, input);
  }

  await room('https://live.bilibili.com/12345?from=share',
      RoomLinkPlatform.bilibili, '12345');
  await room('分享直播：https://live.bilibili.com/12345。', RoomLinkPlatform.bilibili,
      '12345');
  await room('live.bilibili.com/12345', RoomLinkPlatform.bilibili, '12345');
  await room('https://www.douyu.com/topic/test?rid=999', RoomLinkPlatform.douyu,
      '999');
  await room(
      'https://m.douyu.com/roomAlias', RoomLinkPlatform.douyu, 'roomAlias');
  await room('https://www.huya.com/room_1', RoomLinkPlatform.huya, 'room_1');
  await room('https://live.douyin.com/100', RoomLinkPlatform.douyin, '100');
  await room('https://webcast.amemv.com/douyin/webcast/reflow/99999?from=share',
      RoomLinkPlatform.douyin, '99999');
  check(requests == 0, 'Direct links require no network request');
  for (final input in [
    '',
    'arbitrary text',
    'https://douyu.com.evil.test/123',
    'https://evildouyu.com/123',
    'https://evil.test/douyu.com/123',
    'https://www.douyu.com@evil.test/123',
    'https://user:secret@www.douyu.com/123',
    'https://www.douyu.com:1234/123',
    'javascript:https://www.douyu.com/123',
    'https://www.bilibili.com/video/BV123',
    'https://www.douyu.com/topic/test?rid=bad',
  ]) {
    check(await direct.parse(input) == null, 'Reject $input');
  }
  check(requests == 0, 'Untrusted inputs never make requests');
  final short = RoomLinkParser(redirect: (uri) async {
    if (uri.host == 'b23.tv') return Uri.parse('https://live.bilibili.com/42');
    return Uri.parse('https://webcast.amemv.com/webcast/reflow/84');
  });
  check((await short.parse('看看这个直播 https://b23.tv/Ab12 分享给你'))?.roomId == '42',
      'B23 share');
  check((await short.parse('分享 https://v.douyin.com/Ab12/'))?.roomId == '84',
      'Douyin share');
  var hops = 0;
  final relative = RoomLinkParser(redirect: (uri) async {
    hops++;
    return uri.path == '/a'
        ? Uri.parse('/b')
        : Uri.parse('https://live.bilibili.com/5');
  });
  check((await relative.parse('https://b23.tv/a'))?.roomId == '5' && hops == 2,
      'Relative redirect');
  hops = 0;
  final loop = RoomLinkParser(redirect: (uri) async {
    hops++;
    return uri;
  });
  check(await loop.parse('https://b23.tv/a') == null && hops == 1,
      'Loop stops immediately');
  hops = 0;
  final budget = RoomLinkParser(
      maxRedirects: 3,
      redirect: (_) async {
        hops++;
        return Uri.parse('https://b23.tv/hop$hops');
      });
  check(await budget.parse('https://b23.tv/start') == null && hops == 3,
      'Redirect budget respected');
  hops = 0;
  final foreign = RoomLinkParser(redirect: (_) async {
    hops++;
    return Uri.parse('https://evil.test/next');
  });
  check(await foreign.parse('https://v.douyin.com/a') == null && hops == 1,
      'Foreign redirect is never fetched');
  final failed = RoomLinkParser(
      redirect: (_) async =>
          throw StateError('Network failure without response'));
  check(await failed.parse('https://b23.tv/a') == null,
      'Response-less failure does not crash');
  final missing = RoomLinkParser(redirect: (_) async => null);
  check(await missing.parse('https://b23.tv/a') == null,
      'Missing Location handled');
  print('Room link parser verification: $checks checks passed');
}
