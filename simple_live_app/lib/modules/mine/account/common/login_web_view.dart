import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:simple_live_app/modules/mine/account/common/login_webview_profile.dart';
import 'package:url_launcher/url_launcher.dart';

/// Keep the Windows cookie manager in the same environment as its WebView.
class LoginWebView extends StatefulWidget {
  final String loginUrl;
  final void Function(InAppWebViewController, CookieManager) onCreated;
  final void Function(InAppWebViewController, Uri?)? onLoadStop;
  final List<Widget> fallbackActions;
  final bool useNativeUserAgent;
  final String? helpText;
  final void Function(Uri?)? onLoadStart;

  const LoginWebView({
    super.key,
    required this.loginUrl,
    required this.onCreated,
    this.onLoadStop,
    this.onLoadStart,
    this.useNativeUserAgent = false,
    this.helpText,
    this.fallbackActions = const [],
  });

  @override
  State<LoginWebView> createState() => _LoginWebViewState();
}

class _LoginWebViewState extends State<LoginWebView> {
  WebViewEnvironment? _environment;
  InAppWebViewController? _controller;
  String? _error;
  bool _ready = false;
  int _progress = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    final generation = ++_generation;
    try {
      if (Platform.isLinux) {
        throw UnsupportedError('当前平台不支持内嵌登录网页');
      }
      _environment = await LoginWebViewProfile.environment();
      if (mounted && generation == _generation) {
        setState(() {
          _ready = true;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _error = Platform.isWindows
              ? '无法初始化登录网页，请确认已安装 Edge WebView2 Runtime。也可用浏览器登录。'
              : '当前无法打开登录网页，请使用浏览器或其他登录方式。',
        );
      }
    }
  }

  Future<void> _showLogin() async {
    if (!_ready) {
      setState(() => _error = null);
      await _initialize();
      return;
    }
    setState(() {
      _error = null;
      _progress = 0;
    });
    try {
      await _controller?.loadUrl(
        urlRequest: URLRequest(url: WebUri(widget.loginUrl)),
      );
    } catch (_) {
      if (mounted) setState(() => _error = '登录页面加载失败，请重试。');
    }
  }

  @override
  void dispose() {
    ++_generation;
    // The environment owns a profile also used by the cookie manager. It is
    // process-scoped; disposing it before WebView teardown breaks pending calls.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: _showLogin,
                icon: const Icon(Icons.login),
                label: const Text('显示登录框 / 重试'),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    final opened = await launchUrl(
                      Uri.parse(widget.loginUrl),
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && mounted) {
                      setState(() => _error = '无法打开浏览器，请使用其他登录方式。');
                    }
                  } catch (_) {
                    if (mounted) setState(() => _error = '无法打开浏览器，请使用其他登录方式。');
                  }
                },
                icon: const Icon(Icons.open_in_browser),
                label: const Text('浏览器登录'),
              ),
              ...widget.fallbackActions,
            ],
          ),
          if (widget.helpText != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Text(widget.helpText!),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
          if (_ready && _progress < 100)
            LinearProgressIndicator(value: _progress / 100),
          Expanded(
            child: !_ready
                ? Center(
                    child: _error == null
                        ? const CircularProgressIndicator()
                        : const Text('请重试或使用上方的其他登录方式。'),
                  )
                : InAppWebView(
                    webViewEnvironment: _environment,
                    initialUrlRequest: URLRequest(url: WebUri(widget.loginUrl)),
                    initialSettings: InAppWebViewSettings(
                      useShouldOverrideUrlLoading: true,
                      userAgent: !widget.useNativeUserAgent &&
                              (Platform.isWindows || Platform.isMacOS)
                          ? 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36'
                          : null,
                    ),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                      widget.onCreated(
                        controller,
                        CookieManager.instance(
                            webViewEnvironment: _environment),
                      );
                    },
                    onLoadStart: (_, uri) {
                      widget.onLoadStart?.call(uri);
                      if (mounted) {
                        setState(() {
                          _progress = 0;
                          _error = null;
                        });
                      }
                    },
                    onProgressChanged: (_, progress) {
                      if (mounted) setState(() => _progress = progress);
                    },
                    onLoadStop: (controller, uri) {
                      if (mounted) setState(() => _progress = 100);
                      widget.onLoadStop?.call(controller, uri);
                    },
                    onReceivedError: (_, request, __) {
                      if (request.isForMainFrame == true && mounted) {
                        setState(() {
                          _error = '登录页面加载失败，请点击“显示登录框 / 重试”。';
                          _progress = 100;
                        });
                      }
                    },
                    onReceivedHttpError: (_, request, response) {
                      if (request.isForMainFrame == true &&
                          mounted &&
                          (response.statusCode ?? 0) >= 400) {
                        setState(() {
                          _error = '登录页面暂时不可用，请重试或使用浏览器登录。';
                          _progress = 100;
                        });
                      }
                    },
                    shouldOverrideUrlLoading: (_, navigation) async {
                      final url = navigation.request.url;
                      return url != null &&
                              ['https', 'http'].contains(url.scheme)
                          ? NavigationActionPolicy.ALLOW
                          : NavigationActionPolicy.CANCEL;
                    },
                  ),
          ),
        ],
      );
}
