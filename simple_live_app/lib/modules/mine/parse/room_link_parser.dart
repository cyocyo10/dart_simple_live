enum RoomLinkPlatform { bilibili, douyu, huya, douyin }

class RoomLink {
  final RoomLinkPlatform platform;
  final String roomId;
  const RoomLink(this.platform, this.roomId);
}

typedef RoomLinkRedirect = Future<Uri?> Function(Uri uri);

/// Resolve only known live platforms, with a fixed redirect budget and no recursion.
class RoomLinkParser {
  final RoomLinkRedirect redirect;
  final int maxRedirects;
  const RoomLinkParser({required this.redirect, this.maxRedirects = 5});

  static bool _domain(String host, String domain) =>
      host == domain || host.endsWith('.$domain');

  static bool isTrustedUri(Uri uri) {
    if (!['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty ||
        (uri.hasPort && ![80, 443].contains(uri.port))) {
      return false;
    }
    final host = uri.host.toLowerCase();
    return ['bilibili.com', 'douyu.com', 'huya.com']
            .any((d) => _domain(host, d)) ||
        ['b23.tv', 'v.douyin.com', 'live.douyin.com', 'webcast.amemv.com']
            .contains(host);
  }

  static Uri? extractUri(String text) {
    final matches = RegExp(r'''https?://[^\s<>"“”]+''', caseSensitive: false)
        .allMatches(text.trim());
    for (final match in matches) {
      // A URL embedded in another scheme or URL token is not a share link.
      if (match.start > 0 &&
          RegExp(r'[A-Za-z0-9_:/]').hasMatch(text.trim()[match.start - 1])) {
        continue;
      }
      final candidate =
          match.group(0)!.replaceFirst(RegExp(r'[。，、；！!？)）\]},;.]+$'), '');
      final uri = Uri.tryParse(candidate);
      if (uri != null && isTrustedUri(uri)) return uri;
    }
    // Also accept a pasted bare platform URL, but never a domain substring.
    if (matches.isEmpty && !RegExp(r'\s').hasMatch(text.trim())) {
      final uri = Uri.tryParse('https://${text.trim()}');
      if (uri != null && isTrustedUri(uri)) return uri;
    }
    return null;
  }

  Future<RoomLink?> parse(String text) async {
    var uri = extractUri(text);
    final seen = <String>{};
    for (var hop = 0; uri != null && hop <= maxRedirects; hop++) {
      if (!isTrustedUri(uri) || !seen.add(uri.toString())) return null;
      final direct = _direct(uri);
      if (direct != null) return direct;
      if (!['b23.tv', 'v.douyin.com'].contains(uri.host.toLowerCase()) ||
          hop == maxRedirects ||
          uri.pathSegments.isEmpty) {
        return null;
      }
      try {
        final next = await redirect(uri);
        uri = next == null ? null : uri.resolveUri(next);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  RoomLink? _direct(Uri uri) {
    final host = uri.host.toLowerCase();
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final first = segments.isEmpty ? '' : segments.first;
    final id = RegExp(r'^[A-Za-z0-9_]+$');
    final numeric = RegExp(r'^\d+$');
    if (_domain(host, 'bilibili.com') && numeric.hasMatch(first)) {
      return RoomLink(RoomLinkPlatform.bilibili, first);
    }
    if (_domain(host, 'douyu.com')) {
      final rid = uri.queryParameters['rid'];
      if (rid != null && numeric.hasMatch(rid)) {
        return RoomLink(RoomLinkPlatform.douyu, rid);
      }
      if (id.hasMatch(first) &&
          !['topic', 'directory', 'login'].contains(first)) {
        return RoomLink(RoomLinkPlatform.douyu, first);
      }
    }
    if (_domain(host, 'huya.com') && id.hasMatch(first) && first != 'g') {
      return RoomLink(RoomLinkPlatform.huya, first);
    }
    if (host == 'live.douyin.com' && id.hasMatch(first)) {
      return RoomLink(RoomLinkPlatform.douyin, first);
    }
    if (host == 'webcast.amemv.com') {
      final index = segments.indexOf('reflow');
      if (index >= 0 &&
          index + 1 < segments.length &&
          numeric.hasMatch(segments[index + 1])) {
        return RoomLink(RoomLinkPlatform.douyin, segments[index + 1]);
      }
    }
    return null;
  }
}
