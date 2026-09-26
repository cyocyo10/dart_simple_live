import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:simple_live_core/src/common/http_client.dart';

/// 斗鱼 H5 取流签名：getEncryption 服务端描述符 + 纯 Dart MD5，无 JS 依赖。
/// 斗鱼 H5 流地址带 wsAuth 短签名(5 分钟)，断流重连需重新走签名取流。
/// 移植自 pure_live 的纯 Dart 实现。
class DouyuUtils {
  static const String _apiGetEncryption =
      'https://www.douyu.com/wgapi/livenc/liveweb/websec/getEncryption';
  static const int _expirySafetySeconds = 30;
  static const int _maximumCacheAgeSeconds = 5 * 60;

  static const String userAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/128.0.0.0 Safari/537.36';

  static Map<String, dynamic> _encKey = <String, dynamic>{};
  static Future<void>? _encKeyRefresh;
  static int? _encKeyFetchedAtSeconds;
  static final String _sessionDeviceId = generateDeviceId();

  /// 可选的斗鱼账号 Cookie(浏览器登录斗鱼后复制整段 Cookie)，为空时保持匿名取流。
  /// 由 App 层在启动和设置变更时写入，其中的 dy_did/acf_did 会被进程 did 取代。
  static String accountCookie = '';

  /// 进程级随机设备 ID，签名与请求 Cookie 始终一致。
  static String get deviceId => _sessionDeviceId;

  static int _nowSeconds() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  static bool isEncryptionKeyUsable(
    Map<String, dynamic> value, {
    required int nowSeconds,
    int safetySeconds = _expirySafetySeconds,
  }) {
    final expiresAt = _asInt(value['expire_at']);
    final encTime = _asInt(value['enc_time']);
    return expiresAt != null &&
        expiresAt > nowSeconds + safetySeconds &&
        encTime != null &&
        encTime > 0 &&
        encTime <= 16 &&
        _nonEmpty(value['key']) &&
        _nonEmpty(value['rand_str']) &&
        _nonEmpty(value['enc_data']);
  }

  static bool _isCachedEncryptionKeyUsable(int nowSeconds) {
    final fetchedAt = _encKeyFetchedAtSeconds;
    return fetchedAt != null &&
        nowSeconds - fetchedAt < _maximumCacheAgeSeconds &&
        isEncryptionKeyUsable(_encKey, nowSeconds: nowSeconds);
  }

  static Future<void> _encKeyUpdate({bool forceRefresh = false}) async {
    final nowSeconds = _nowSeconds();
    if (!forceRefresh && _isCachedEncryptionKeyUsable(nowSeconds)) return;

    final activeRefresh = _encKeyRefresh;
    if (activeRefresh != null) {
      await activeRefresh;
      if (_isCachedEncryptionKeyUsable(_nowSeconds())) return;
    }

    final refresh = _fetchEncryptionKey();
    _encKeyRefresh = refresh;
    try {
      await refresh;
    } finally {
      if (identical(_encKeyRefresh, refresh)) _encKeyRefresh = null;
    }
  }

  static Future<void> _fetchEncryptionKey() async {
    final response = await HttpClient.instance.getJson(
      _apiGetEncryption,
      queryParameters: {'did': deviceId},
      header: requestHeaders(),
    );
    final rawData = response is Map ? response['data'] : null;
    if (rawData is! Map) {
      throw const FormatException('斗鱼加密描述符响应缺少 data');
    }
    final data = Map<String, dynamic>.from(rawData);
    if (!isEncryptionKeyUsable(data, nowSeconds: _nowSeconds())) {
      throw const FormatException('斗鱼加密描述符无效或已过期');
    }
    _encKey = data;
    _encKeyFetchedAtSeconds = _nowSeconds();
  }

  static String generateDeviceId({Random? random}) {
    final source = random ?? Random.secure();
    return List<String>.generate(
      32,
      (_) => source.nextInt(16).toRadixString(16),
    ).join();
  }

  /// 组装请求头，Cookie 中的 dy_did/acf_did 始终与签名 did 一致。
  static Map<String, String> requestHeaders([String roomId = '']) {
    final referer =
        roomId.isEmpty ? 'https://www.douyu.com/' : 'https://www.douyu.com/$roomId';
    return <String, String>{
      'accept': 'application/json, text/plain, */*',
      'origin': 'https://www.douyu.com',
      'referer': referer,
      'user-agent': userAgent,
      'cookie': cookieHeader(),
    };
  }

  /// 播放/录制请求头，补齐 Referer/Origin/UA/DID Cookie，避免 CDN 403。
  static Map<String, String> playbackHeaders(String roomId) =>
      <String, String>{
        'origin': 'https://www.douyu.com',
        'referer': 'https://www.douyu.com/$roomId',
        'user-agent': userAgent,
        'cookie': cookieHeader(),
      };

  static String cookieHeader() {
    final normalized = accountCookie
        .trim()
        .replaceFirst(RegExp(r'^Cookie:\s*', caseSensitive: false), '');
    final fields = <String>['dy_did=$deviceId', 'acf_did=$deviceId'];
    for (final piece in normalized.split(';')) {
      final separator = piece.indexOf('=');
      if (separator <= 0) continue;
      final name = piece.substring(0, separator).trim();
      if (name.isEmpty) continue;
      // dy_did/acf_did 必须与签名 did 一致，丢弃粘贴值中的旧 did
      if (name.toLowerCase() == 'dy_did' || name.toLowerCase() == 'acf_did') {
        continue;
      }
      fields.add('$name=${piece.substring(separator + 1).trim()}');
    }
    return fields.join('; ');
  }

  /// 构建 getH5PlayV1 的表单字符串。
  static Future<String> buildSignedData({
    required String roomId,
    int rate = -1,
    String cdn = '',
    bool forceRefresh = false,
  }) async {
    await _encKeyUpdate(forceRefresh: forceRefresh);
    final key = _encKey;
    final keyStr = key['key'].toString();
    final randStr = key['rand_str'].toString();
    final encTime = _asInt(key['enc_time'])!;
    final isSpecial = _asInt(key['is_special']) == 1;
    final tt = _nowSeconds();
    final salt = isSpecial ? '' : '$roomId$tt';

    var secret = randStr;
    for (var index = 0; index < encTime; index++) {
      secret = md5.convert(utf8.encode('$secret$keyStr')).toString();
    }
    final auth = md5.convert(utf8.encode('$secret$keyStr$salt')).toString();
    return Uri(
      queryParameters: <String, String>{
        'enc_data': key['enc_data'].toString(),
        'tt': tt.toString(),
        'did': deviceId,
        'auth': auth,
        'cdn': cdn,
        'rate': rate.toString(),
        'hevc': '0',
        'fa': '0',
        'ive': '0',
        'ver': 'Douyu_new',
        'iar': '0',
      },
    ).query;
  }

  static int? _asInt(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  static bool _nonEmpty(dynamic value) =>
      value?.toString().trim().isNotEmpty == true;
}
