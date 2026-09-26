import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/modules/mine/account/douyin/login_flow.dart';

class _FailingStorage extends LocalStorageService {
  @override
  Future<void> setValue<T>(dynamic key, T value) async {
    throw StateError('disk full');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account credentials remain unchanged when persistence fails', () async {
    Get.testMode = true;
    Get.put<LocalStorageService>(_FailingStorage());
    final account = DouyinAccountService();
    account.searchCookie = 'sessionid=previous';
    account.hasSearchCookie.value = true;
    try {
      await expectLater(
          account.setSearchCookie('sessionid=unsaved'), throwsStateError);
      expect(account.searchCookie, 'sessionid=previous');
      expect(account.hasSearchCookie.value, isTrue);
      account.searchCookie = '';
      account.hasSearchCookie.value = false;
      await expectLater(
          account.setSearchCookie('sessionid=unsaved'), throwsStateError);
      expect(account.searchCookie, isEmpty);
      expect(account.hasSearchCookie.value, isFalse);
    } finally {
      Get.reset();
    }
  });
  test('official page must use HTTPS and a genuine Douyin host', () {
    expect(isDouyinLoginPage(Uri.parse('https://live.douyin.com/')), isTrue);
    expect(isDouyinLoginPage(Uri.parse('http://live.douyin.com/')), isFalse);
    expect(
        isDouyinLoginPage(Uri.parse('https://douyin.com.evil.test/')), isFalse);
  });

  test('HTTP 200 passport rejection is presented without arbitrary server text',
      () {
    expect(
      douyinLoginPageError(
          '{"data":{"error_code":4031,"description":"secret"},"message":"error"}'),
      contains('4031'),
    );
    expect(douyinLoginPageError('{"data":{"error_code":"4031"}}'),
        contains('4031'));
    expect(douyinLoginPageError('<html>登录</html>'), isNull);
    expect(douyinLoginPageError('{broken'), isNull);
    expect(douyinLoginPageError('{"data":null}'), isNull);
  });

  test('navigation invalidates a pending cookie read even after resuming',
      () async {
    final flow = DouyinLoginCapture()..resume();
    final read = Completer<String>();
    var writes = 0;
    final capture = flow.capture(
      readCookie: () => read.future,
      saveCookie: (_) async => writes++,
    );
    flow.pause();
    flow.resume();
    read.complete('sessionid=old');
    expect(await capture, isFalse);
    expect(writes, 0);
    expect(flow.completed, isFalse);
  });

  test('polling and manual capture cannot persist concurrent credentials',
      () async {
    final flow = DouyinLoginCapture()..resume();
    final read = Completer<String>();
    var writes = 0;
    final first = flow.capture(
      readCookie: () => read.future,
      saveCookie: (_) async => writes++,
    );
    expect(
        await flow.capture(
          readCookie: () async => 'sessionid=other',
          saveCookie: (_) async => writes++,
        ),
        isFalse);
    read.complete('sessionid=first');
    expect(await first, isTrue);
    expect(writes, 1);
    expect(
        await flow.capture(
          readCookie: () async => 'sessionid=repeat',
          saveCookie: (_) async => writes++,
        ),
        isFalse);
    expect(writes, 1);
  });

  test(
      'completion waits for durable persistence; pause suppresses late success',
      () async {
    final flow = DouyinLoginCapture()..resume();
    final save = Completer<void>();
    final capture = flow.capture(
      readCookie: () async => 'sid_tt=value',
      saveCookie: (_) => save.future,
    );
    await Future<void>.delayed(Duration.zero);
    expect(flow.completed, isFalse);
    flow.pause();
    var idle = false;
    final drained = flow.idle.then((_) => idle = true);
    await Future<void>.delayed(Duration.zero);
    expect(idle, isFalse);
    save.complete();
    expect(await capture, isFalse);
    await drained;
    expect(idle, isTrue);
    expect(flow.completed, isFalse);
  });

  test('failed persistence remains retryable and anonymous cookies never save',
      () async {
    final flow = DouyinLoginCapture()..resume();
    expect(
        await flow.capture(
          readCookie: () async => 'ttwid=anonymous',
          saveCookie: (_) async => throw StateError('must not save'),
        ),
        isFalse);
    await expectLater(
        flow.capture(
          readCookie: () async => 'sessionid=value',
          saveCookie: (_) async => throw StateError('disk full'),
        ),
        throwsStateError);
    expect(flow.completed, isFalse);
    expect(
        await flow.capture(
          readCookie: () async => 'sessionid=retry',
          saveCookie: (_) async {},
        ),
        isTrue);
  });
}
