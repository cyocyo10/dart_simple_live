/// WS five-minute lease workaround from Pure Live commit a858550bb8753f47bc279a4e45f5cb2707cf5937.
/// Preserve signed bytes rather than decoding/re-encoding the query string.
String normalizeDouyuStreamUrl(String url) {
  final fragmentAt = url.indexOf('#');
  final main = fragmentAt < 0 ? url : url.substring(0, fragmentAt);
  final fragment = fragmentAt < 0 ? '' : url.substring(fragmentAt);
  final queryAt = main.indexOf('?');
  if (queryAt < 0) return url;
  String? cdn;
  String? expiry;
  for (final part in main.substring(queryAt + 1).split('&')) {
    final equalsAt = part.indexOf('=');
    if (equalsAt < 0) continue;
    final key = part.substring(0, equalsAt);
    final value = part.substring(equalsAt + 1);
    if (key == 'fcdn') cdn = value;
    if (key == 'expire') expiry = value;
  }
  if (cdn != 'ws' || expiry != '300') return url;
  return '$main${main.endsWith('&') ? '' : '&'}expire=0$fragment';
}
