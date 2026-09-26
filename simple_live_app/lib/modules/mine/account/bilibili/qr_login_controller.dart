import 'dart:async';

import 'package:get/get.dart';
import 'package:simple_live_app/modules/mine/account/common/login_session.dart';
import 'package:simple_live_app/requests/http_client.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';

enum QRStatus { loading, unscanned, scanned, expired, failed }

class BiliBiliQRLoginController extends GetxController {
  Timer? timer;
  final qrcodeUrl = ''.obs;
  String qrcodeKey = '';
  final qrStatus = QRStatus.loading.obs;
  int _generation = 0;
  bool _polling = false;
  bool _completed = false;

  @override
  void onInit() {
    super.onInit();
    loadQRCode();
  }

  Future<void> loadQRCode() async {
    if (isClosed || _completed) return;
    BiliBiliAccountService.instance.cancelPendingLogin();
    final generation = ++_generation;
    timer?.cancel();
    qrcodeKey = '';
    qrStatus.value = QRStatus.loading;
    try {
      final result = await HttpClient.instance.getJson(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/generate',
      );
      if (isClosed || generation != _generation) return;
      if (result['code'] != 0) throw StateError('QR generation failed');
      final data = result['data'];
      qrcodeKey = data['qrcode_key'] as String;
      qrcodeUrl.value = data['url'] as String;
      if (qrcodeKey.isEmpty || qrcodeUrl.value.isEmpty) {
        throw StateError('Empty QR code');
      }
      qrStatus.value = QRStatus.unscanned;
      _schedulePoll(generation);
    } catch (_) {
      if (!isClosed && generation == _generation) {
        qrStatus.value = QRStatus.failed;
      }
    }
  }

  void _schedulePoll(int generation) {
    timer?.cancel();
    if (isClosed || generation != _generation || _completed) return;
    timer = Timer(const Duration(seconds: 3), () => pollQRStatus(generation));
  }

  Future<void> pollQRStatus([int? requestedGeneration]) async {
    final generation = requestedGeneration ?? _generation;
    if (_polling ||
        isClosed ||
        _completed ||
        qrcodeKey.isEmpty ||
        generation != _generation) {
      return;
    }
    _polling = true;
    try {
      final response = await HttpClient.instance.get(
        'https://passport.bilibili.com/x/passport-login/web/qrcode/poll',
        queryParameters: {'qrcode_key': qrcodeKey},
      );
      if (isClosed || generation != _generation) return;
      if (response.data['code'] != 0) throw StateError('QR poll failed');
      final code = response.data['data']['code'];
      if (code == 0) {
        final cookie = (response.headers['set-cookie'] ?? <String>[])
            .map((element) => element.split(';').first)
            .join('; ');
        if (!hasBiliSession(cookie)) throw StateError('Missing login session');
        timer?.cancel();
        final account = BiliBiliAccountService.instance;
        if (!await account.loginCookie(cookie)) {
          throw StateError('Login validation failed');
        }
        if (isClosed || generation != _generation) return;
        _completed = true;
        Get.back(result: true);
      } else if (code == 86038) {
        qrStatus.value = QRStatus.expired;
        qrcodeKey = '';
        timer?.cancel();
      } else if (code == 86090) {
        qrStatus.value = QRStatus.scanned;
      }
    } catch (_) {
      if (!isClosed && generation == _generation) {
        qrStatus.value = QRStatus.failed;
        qrcodeKey = '';
        timer?.cancel();
      }
    } finally {
      _polling = false;
      if (!isClosed && !_completed && qrcodeKey.isNotEmpty) {
        _schedulePoll(_generation);
      }
    }
  }

  @override
  void onClose() {
    ++_generation;
    timer?.cancel();
    BiliBiliAccountService.instance.cancelPendingLogin();
    super.onClose();
  }
}
