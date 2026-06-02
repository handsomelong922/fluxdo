import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../l10n/s.dart';
import '../services/network/cookie/boundary_sync_service.dart';
import '../services/network/cookie/webview_cookie_priming.dart';
import '../services/toast_service.dart';
import '../services/webview_settings.dart';
import '../services/windows_webview_environment_service.dart';

class OAuthWebViewResult {
  final String code;
  final String state;

  const OAuthWebViewResult({required this.code, required this.state});
}

/// 受控 OAuth WebView。
///
/// 用于在 App 内完成第三方授权，并在拿到回调参数前把 WebView
/// 会话同步回 CookieJar，避免和纯 Dio / 外部浏览器链路继续分裂。
class OAuthWebViewPage extends StatefulWidget {
  final String initialUrl;
  final String callbackBaseUrl;
  final String? title;

  const OAuthWebViewPage({
    super.key,
    required this.initialUrl,
    required this.callbackBaseUrl,
    this.title,
  });

  @override
  State<OAuthWebViewPage> createState() => _OAuthWebViewPageState();
}

class _OAuthWebViewPageState extends State<OAuthWebViewPage> {
  static const _allowedSchemes = {'http', 'https', 'about', 'data', 'blob'};

  InAppWebViewController? _controller;
  bool _isLoading = true;
  bool _isCompleting = false;
  double _progress = 0;
  bool _handledCallback = false;
  late final Uri _expectedCallbackUri;
  Future<void>? _initialCookieFlushFuture;

  @override
  void initState() {
    super.initState();
    _expectedCallbackUri = Uri.parse(widget.callbackBaseUrl);
    _initialCookieFlushFuture = WebViewCookiePriming.instance.prime(
      widget.initialUrl,
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _awaitInitialCookieFlush() async {
    final future = _initialCookieFlushFuture;
    if (future == null) return;
    try {
      await future.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  bool _isExpectedCallbackUri(Uri uri) {
    if (uri.scheme != _expectedCallbackUri.scheme ||
        uri.host != _expectedCallbackUri.host) {
      return false;
    }
    if (uri.hasPort != _expectedCallbackUri.hasPort) {
      return false;
    }
    if (uri.hasPort && uri.port != _expectedCallbackUri.port) {
      return false;
    }
    return uri.queryParameters['code'] != null &&
        uri.queryParameters['state'] != null;
  }

  Future<bool> _tryCompleteOAuth(
    InAppWebViewController controller,
    WebUri? webUri,
  ) async {
    if (_handledCallback || webUri == null) return false;
    final rawUrl = webUri.toString();
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || !_isExpectedCallbackUri(uri)) {
      return false;
    }

    final code = uri.queryParameters['code'];
    final state = uri.queryParameters['state'];
    if (code == null || state == null) {
      return false;
    }

    _handledCallback = true;
    await _awaitInitialCookieFlush();
    if (mounted) {
      setState(() {
        _isCompleting = true;
        _isLoading = true;
      });
    }

    await BoundarySyncService.instance.syncFromWebView(
      currentUrl: rawUrl,
      controller: controller,
      additionalUrls: [widget.initialUrl, widget.callbackBaseUrl],
    );

    if (!mounted) return true;
    Navigator.of(context).pop(OAuthWebViewResult(code: code, state: state));
    return true;
  }

  Future<NavigationActionPolicy> _shouldOverrideUrlLoading(
    InAppWebViewController controller,
    NavigationAction navigationAction,
  ) async {
    final uri = navigationAction.request.url;
    if (await _tryCompleteOAuth(controller, uri)) {
      return NavigationActionPolicy.CANCEL;
    }

    final scheme = uri?.scheme.toLowerCase();
    if (scheme == 'javascript') {
      return NavigationActionPolicy.CANCEL;
    }
    if (scheme != null && !_allowedSchemes.contains(scheme)) {
      return NavigationActionPolicy.ALLOW;
    }
    return NavigationActionPolicy.ALLOW;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? context.l10n.webviewLogin_title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isCompleting ? null : () => _controller?.reload(),
            tooltip: context.l10n.common_refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading || _isCompleting)
            LinearProgressIndicator(value: _isCompleting ? null : _progress),
          Expanded(
            child: Stack(
              children: [
                WebViewSettings.wrapWithScrollFix(
                  InAppWebView(
                    webViewEnvironment:
                        WindowsWebViewEnvironmentService.instance.environment,
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.initialUrl),
                    ),
                    initialSettings: WebViewSettings.visible
                      ..useShouldOverrideUrlLoading = true,
                    initialUserScripts: WebViewSettings.ios15PolyfillScripts,
                    shouldOverrideUrlLoading: _shouldOverrideUrlLoading,
                    onReceivedServerTrustAuthRequest: (_, challenge) =>
                        WebViewSettings.handleServerTrustAuthRequest(challenge),
                    onWebViewCreated: (controller) {
                      _controller = controller;
                    },
                    onLoadStart: (controller, url) async {
                      if (mounted) {
                        setState(() {
                          _isLoading = true;
                        });
                      }
                      await _tryCompleteOAuth(controller, url);
                    },
                    onProgressChanged: (_, progress) {
                      if (!mounted) return;
                      setState(() {
                        _progress = progress / 100;
                      });
                    },
                    onLoadStop: (controller, url) async {
                      if (mounted) {
                        setState(() {
                          _isLoading = false;
                        });
                      }
                      await WebViewSettings.injectScrollFix(controller);
                      await _tryCompleteOAuth(controller, url);
                    },
                    onUpdateVisitedHistory: (controller, url, _) {
                      _tryCompleteOAuth(controller, url);
                    },
                    onReceivedError: (controller, request, error) {
                      if (_handledCallback) return;
                      ToastService.showError(
                        context.l10n.cf_loadFailed(error.description),
                      );
                    },
                  ),
                  getController: () => _controller,
                ),
                if (_isCompleting)
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.colorScheme.surface.withValues(alpha: 0.88),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(),
                            const SizedBox(height: 16),
                            Text(context.l10n.webviewLogin_loginSuccess),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
