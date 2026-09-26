/// Match a DNS label boundary, never accept lookalike domains.
bool isDouyuHost(String host) =>
    host.toLowerCase() == 'douyu.com' ||
    host.toLowerCase().endsWith('.douyu.com');

bool hasDouyuSession(String cookie) {
  final values = <String, String>{};
  for (final part in cookie.split(';')) {
    final separator = part.indexOf('=');
    if (separator > 0) {
      values[part.substring(0, separator).trim()] =
          part.substring(separator + 1).trim();
    }
  }
  return (values['acf_uid']?.isNotEmpty ?? false) &&
      values['acf_uid'] != '0' &&
      (values['acf_auth']?.isNotEmpty ?? false);
}
