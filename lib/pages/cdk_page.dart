import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/network/cookie/webview_cookie_priming.dart';
import '../services/cdk_oauth_service.dart';
import '../services/toast_service.dart';
import '../services/webview_settings.dart';
import '../services/windows_webview_environment_service.dart';
import '../l10n/s.dart';

@visibleForTesting
bool isTrustedCdkWebViewHost(String host) {
  final normalizedHost = host.toLowerCase();
  if (normalizedHost == 'cdk.linux.do' ||
      normalizedHost == 'credit.linux.do' ||
      normalizedHost == 'connect.linux.do' ||
      normalizedHost == 'linux.do') {
    return true;
  }
  return normalizedHost.endsWith('.linux.do');
}

/// CDK 专用领取页。
///
/// 仍然使用 WebView 承载 cdk.linux.do 的登录态与领取交互，但移除通用浏览器
/// 的地址栏、收藏、历史等壳层，让高频领取场景更接近应用内功能页。
class CdkPage extends StatefulWidget {
  static const String defaultUrl = 'https://cdk.linux.do';

  final String url;

  const CdkPage({super.key, this.url = defaultUrl});

  static Future<T?> open<T extends Object?>(
    BuildContext context, {
    String? url,
  }) {
    return Navigator.of(context).push<T>(
      MaterialPageRoute(builder: (_) => CdkPage(url: url ?? defaultUrl)),
    );
  }

  @override
  State<CdkPage> createState() => _CdkPageState();
}

class _CdkPageState extends State<CdkPage> {
  InAppWebViewController? _controller;
  bool _sessionSyncQueuedReload = false;
  bool _isLoading = true;
  double _progress = 0;
  String _currentUrl = '';
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _prepareSessionInBackground();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final windowsWebViewEnvironment =
        WindowsWebViewEnvironmentService.instance.environment;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: theme.colorScheme.tertiaryContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.token_rounded,
                  size: 18,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'LINUX DO CDK',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _handleBackNavigation,
            tooltip: context.l10n.common_close,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _controller?.reload(),
              tooltip: context.l10n.common_refresh,
            ),
            IconButton(
              icon: const Icon(Icons.open_in_browser_rounded),
              onPressed: _openExternal,
              tooltip: context.l10n.webview_openExternal,
            ),
          ],
          bottom: _isLoading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _progress > 0 && _progress < 1 ? _progress : null,
                    minHeight: 2,
                  ),
                )
              : null,
        ),
        body: Stack(
          children: [
            WebViewSettings.wrapWithScrollFix(
              InAppWebView(
                webViewEnvironment: windowsWebViewEnvironment,
                initialUrlRequest:
                    (!io.Platform.isWindows && widget.url.isNotEmpty)
                    ? URLRequest(url: WebUri(widget.url))
                    : null,
                initialSettings: WebViewSettings.visible
                  ..useShouldOverrideUrlLoading = true,
                initialUserScripts: WebViewSettings.compatPolyfillScripts,
                onReceivedServerTrustAuthRequest: (_, challenge) =>
                    WebViewSettings.handleServerTrustAuthRequest(challenge),
                shouldOverrideUrlLoading: (controller, navigationAction) async {
                  final uri = navigationAction.request.url;
                  if (uri == null) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  final targetFrame = navigationAction.targetFrame;
                  if (targetFrame == null || targetFrame.isMainFrame == false) {
                    if (_shouldOpenInsideCdkWebView(uri)) {
                      await controller.loadUrl(
                        urlRequest: URLRequest(url: uri),
                      );
                    }
                    return NavigationActionPolicy.CANCEL;
                  }

                  if (_shouldOpenInsideCdkWebView(uri)) {
                    return NavigationActionPolicy.ALLOW;
                  }

                  return NavigationActionPolicy.ALLOW;
                },
                onWebViewCreated: (controller) async {
                  _controller = controller;
                  WebViewSettings.registerJsErrorReporter(controller);
                  if (io.Platform.isWindows && widget.url.isNotEmpty) {
                    await controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri(widget.url)),
                    );
                  }
                  if (_sessionSyncQueuedReload) {
                    _sessionSyncQueuedReload = false;
                    unawaited(controller.reload());
                  }
                  if (io.Platform.isAndroid) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      const MethodChannel(
                        'com.fluxdo/webauthn',
                      ).invokeMethod('enableWebAuthentication');
                    });
                  }
                },
                onLoadStart: (_, url) {
                  setState(() {
                    _isLoading = true;
                    _loadError = null;
                    _currentUrl = url?.toString() ?? _currentUrl;
                  });
                },
                onProgressChanged: (_, progress) {
                  setState(() => _progress = progress / 100);
                },
                onLoadStop: (controller, url) async {
                  await WebViewSettings.injectScrollFix(controller);
                  setState(() {
                    _isLoading = false;
                    _currentUrl = url?.toString() ?? _currentUrl;
                  });
                },
                onReceivedError: (_, request, error) {
                  if (request.isForMainFrame == false) return;
                  setState(() {
                    _isLoading = false;
                    _loadError = error.description;
                  });
                },
                onReceivedHttpError: (_, request, response) {
                  if (request.isForMainFrame == false) return;
                  final statusCode = response.statusCode;
                  if (statusCode == null || statusCode < 400) return;
                  setState(() {
                    _isLoading = false;
                    _loadError = 'HTTP $statusCode';
                  });
                },
                onUpdateVisitedHistory: (controller, url, _) async {
                  setState(() {
                    _currentUrl = url?.toString() ?? _currentUrl;
                  });
                },
              ),
              getController: () => _controller,
            ),
            if (_loadError != null)
              Positioned.fill(
                child: ColoredBox(
                  color: theme.colorScheme.surface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 40,
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _loadError!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: () {
                              setState(() => _loadError = null);
                              _controller?.reload();
                            },
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(context.l10n.common_refresh),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _prepareSessionInBackground() {
    unawaited(_seedSessionAndReloadIfNeeded());
  }

  Future<void> _seedSessionAndReloadIfNeeded() async {
    if (widget.url.isEmpty) return;

    try {
      final uri = Uri.tryParse(widget.url);
      var shouldReload = false;

      if (uri != null && isTrustedCdkWebViewHost(uri.host)) {
        shouldReload = await CdkOAuthService().authorizeSilently();
      }

      if (!WebViewCookiePriming.instance.isPrimed || shouldReload) {
        await WebViewCookiePriming.instance.prime(widget.url);
        shouldReload = true;
      }

      if (!mounted || !shouldReload) return;
      final controller = _controller;
      if (controller != null) {
        await controller.reload();
      } else {
        _sessionSyncQueuedReload = true;
      }
    } catch (_) {}
  }

  Future<void> _handleBackNavigation() async {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openExternal() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      ToastService.showError(S.current.webview_cannotOpenBrowser);
      return;
    }
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) {
        ToastService.showError(S.current.webview_cannotOpenBrowser);
      }
    } catch (_) {
      if (!mounted) return;
      ToastService.showError(S.current.webview_cannotOpenBrowser);
    }
  }

  bool _shouldOpenInsideCdkWebView(WebUri uri) {
    return isTrustedCdkWebViewHost(uri.host);
  }
}
