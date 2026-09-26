import 'dart:async';
import 'dart:convert';

import '../common/login_session.dart';

bool isDouyinLoginPage(Uri? uri) =>
    uri != null && uri.scheme == 'https' && isLoginHost(uri.host, 'douyin.com');

/// A document may be a passport API error even with HTTP 200.
String? douyinLoginPageError(String body) {
  if (body.length > 16384 || !body.trimLeft().startsWith('{')) return null;
  try {
    final value = jsonDecode(body);
    if (value is! Map || value['data'] is! Map) return null;
    final data = value['data'] as Map;
    if (data['error_code'] == 4031 || data['error_code'] == '4031') {
      return '抖音已阻止此次登录访问（4031）。请重试官方页面，或在浏览器登录后粘贴 Cookie。';
    }
    if (value['message'] == 'error' && data['error_code'] != null) {
      return '抖音暂时拒绝登录访问。请重试或在浏览器登录后粘贴 Cookie。';
    }
  } catch (_) {
    // Normal HTML / text documents are not API errors.
  }
  return null;
}

/// Read and persist at most one session at a time. Navigation/close invalidates
/// pending reads before they can persist credentials or signal completion.
class DouyinLoginCapture {
  bool _active = false;
  bool _busy = false;
  bool _completed = false;
  int _generation = 0;
  Completer<void>? _pending;

  Future<void> get idle => _pending?.future ?? Future.value();

  void resume() => _active = true;

  void pause() {
    _active = false;
    _generation++;
  }

  bool get completed => _completed;

  Future<bool> capture({
    required Future<String> Function() readCookie,
    required Future<void> Function(String) saveCookie,
  }) async {
    if (!_active || _busy || _completed) return false;
    _busy = true;
    _pending = Completer<void>();
    final generation = _generation;
    bool current() => _active && generation == _generation;
    try {
      final cookie = await readCookie();
      if (!current() || !hasDouyinSession(cookie)) return false;
      await saveCookie(cookie);
      if (!current()) return false;
      _completed = true;
      return true;
    } finally {
      _busy = false;
      _pending?.complete();
      _pending = null;
    }
  }
}

/// Only click a visible official login entry. Never inspect input values, invoke
/// private passport APIs, or submit a form. Retry from Dart while SPA hydrates.
const douyinOpenLoginScript = r'''
(() => {
  if (location.protocol !== 'https:' ||
      !(location.hostname === 'douyin.com' || location.hostname.endsWith('.douyin.com'))) {
    return 'outside';
  }
  const text = (document.body?.innerText || '').trim();
  if (text.length <= 16384 && text.startsWith('{')) return text;
  const visible = (element) => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.display !== 'none' &&
      style.visibility !== 'hidden' && style.opacity !== '0';
  };
  // An already open dialog must remain under the user's control.
  if (Array.from(document.querySelectorAll('[role="dialog"], [aria-modal="true"]'))
      .some(visible)) return 'dialog';
  const labels = new Set(['登录', '登录/注册', '登录 / 注册']);
  const candidates = Array.from(document.querySelectorAll('header button, header a, button, a'));
  const entry = candidates.find((element) => visible(element) &&
    !element.disabled && element.getAttribute('aria-disabled') !== 'true' &&
    labels.has((element.innerText || '').trim()) &&
    !element.closest('form, [role="dialog"], [aria-modal="true"]'));
  if (!entry) return 'waiting';
  entry.scrollIntoView({block: 'center'});
  entry.focus();
  entry.click();
  return 'opened';
})()
''';
