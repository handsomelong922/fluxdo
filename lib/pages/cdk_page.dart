import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/network/cookie/raw_set_cookie_queue.dart';
import '../services/toast_service.dart';
import '../services/webview_settings.dart';
import '../services/windows_webview_environment_service.dart';
import '../l10n/s.dart';

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
  late final Future<void> _cookieSyncFuture;
  bool _isLoading = true;
  double _progress = 0;
  bool _canGoBack = false;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _cookieSyncFuture = _seedAndBarrier();
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
            icon: Icon(_canGoBack ? Icons.arrow_back_rounded : Icons.close),
            onPressed: _handleBackNavigation,
            tooltip: _canGoBack
                ? context.l10n.webview_goBack
                : context.l10n.common_close,
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
        body: FutureBuilder<void>(
          future: _cookieSyncFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox.shrink();
            }

            return WebViewSettings.wrapWithScrollFix(
              InAppWebView(
                webViewEnvironment: windowsWebViewEnvironment,
                initialUrlRequest:
                    (!io.Platform.isWindows && widget.url.isNotEmpty)
                    ? URLRequest(url: WebUri(widget.url))
                    : null,
                initialSettings: WebViewSettings.visible
                  ..useShouldOverrideUrlLoading = true,
                initialUserScripts: WebViewSettings.ios15PolyfillScripts,
                onReceivedServerTrustAuthRequest: (_, challenge) =>
                    WebViewSettings.handleServerTrustAuthRequest(challenge),
                onWebViewCreated: (controller) async {
                  _controller = controller;
                  if (io.Platform.isWindows && widget.url.isNotEmpty) {
                    await RawSetCookieQueue.instance.flushToWebView();
                    await controller.loadUrl(
                      urlRequest: URLRequest(url: WebUri(widget.url)),
                    );
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
                    _currentUrl = url?.toString() ?? _currentUrl;
                  });
                },
                onProgressChanged: (_, progress) {
                  setState(() => _progress = progress / 100);
                },
                onLoadStop: (controller, url) async {
                  await WebViewSettings.injectScrollFix(controller);
                  final canGoBack = await controller.canGoBack();
                  setState(() {
                    _isLoading = false;
                    _canGoBack = canGoBack;
                    _currentUrl = url?.toString() ?? _currentUrl;
                  });
                },
                onUpdateVisitedHistory: (controller, url, _) async {
                  final canGoBack = await controller.canGoBack();
                  setState(() {
                    _canGoBack = canGoBack;
                    _currentUrl = url?.toString() ?? _currentUrl;
                  });
                },
              ),
              getController: () => _controller,
            );
          },
        ),
      ),
    );
  }

  Future<void> _seedAndBarrier() async {
    if (io.Platform.isWindows) return;
    await RawSetCookieQueue.instance.flushToWebView();
  }

  Future<void> _handleBackNavigation() async {
    final controller = _controller;
    if (controller == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    if (await controller.canGoBack()) {
      await controller.goBack();
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openExternal() async {
    final url = _currentUrl.isNotEmpty ? _currentUrl : widget.url;
    final uri = Uri.tryParse(url);
    if (uri == null || !await canLaunchUrl(uri)) {
      ToastService.showError(S.current.webview_cannotOpenBrowser);
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) {
      return;
    }
  }
}
