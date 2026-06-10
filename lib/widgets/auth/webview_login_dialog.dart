import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../constants.dart';
import '../../services/discourse/discourse_service.dart';
import '../../services/network/cookie/boundary_sync_service.dart';
import '../../services/network/cookie/cookie_jar_service.dart';
import '../../services/webview_settings.dart';
import '../../services/windows_webview_environment_service.dart';

enum WebViewLoginStatus { success, failure, canceled }

class WebViewLoginDialogResult {
  const WebViewLoginDialogResult.success()
    : status = WebViewLoginStatus.success,
      loginErrorKind = null,
      errorMessage = null;

  const WebViewLoginDialogResult.canceled()
    : status = WebViewLoginStatus.canceled,
      loginErrorKind = null,
      errorMessage = null;

  const WebViewLoginDialogResult.failure(this.loginErrorKind, this.errorMessage)
    : status = WebViewLoginStatus.failure;

  final WebViewLoginStatus status;
  final LoginErrorKind? loginErrorKind;
  final String? errorMessage;
}

class WebViewLoginNeed2FA {
  const WebViewLoginNeed2FA({
    this.totpEnabled = false,
    this.backupEnabled = false,
    this.securityKeyEnabled = false,
    this.message,
  });

  final bool totpEnabled;
  final bool backupEnabled;
  final bool securityKeyEnabled;
  final String? message;
}

Future<WebViewLoginDialogResult?> showWebViewLoginDialog(
  BuildContext context, {
  required String siteKey,
  required String identifier,
  required String password,
  required Future<String?> Function(WebViewLoginNeed2FA need)
  onNeedSecondFactor,
}) {
  return showDialog<WebViewLoginDialogResult>(
    context: context,
    barrierColor: Colors.black54,
    barrierDismissible: false,
    builder: (_) => _WebViewLoginDialog(
      siteKey: siteKey,
      identifier: identifier,
      password: password,
      onNeedSecondFactor: onNeedSecondFactor,
    ),
  );
}

class _WebViewLoginDialog extends StatefulWidget {
  const _WebViewLoginDialog({
    required this.siteKey,
    required this.identifier,
    required this.password,
    required this.onNeedSecondFactor,
  });

  final String siteKey;
  final String identifier;
  final String password;
  final Future<String?> Function(WebViewLoginNeed2FA need) onNeedSecondFactor;

  @override
  State<_WebViewLoginDialog> createState() => _WebViewLoginDialogState();
}

class _WebViewLoginDialogState extends State<_WebViewLoginDialog> {
  InAppWebViewController? _controller;
  bool _loading = true;
  bool _processing = false;
  bool _finished = false;
  bool _cookiesPrimed = false;

  String get _inlineHtml {
    final scheme = Theme.of(context).colorScheme;
    String hex(Color c) =>
        '#${(c.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    final titleColor = hex(scheme.onSurface);
    final subColor = hex(scheme.onSurfaceVariant);
    final accent = hex(scheme.primary);
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
  <style>
    html, body { margin: 0; padding: 0; height: 100%; background: transparent;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { overflow: hidden; }
    .wrap { box-sizing: border-box; min-height: 100vh; display: flex;
      flex-direction: column; align-items: center; justify-content: center;
      gap: 22px; padding: 24px; text-align: center; }
    .badge { width: 60px; height: 60px; border-radius: 50%; display: flex;
      align-items: center; justify-content: center; background: ${accent}1f;
      color: $accent; font-size: 30px; }
    .tip { font-size: 14px; line-height: 1.6; color: $subColor; margin: 0;
      max-width: 280px; }
    .tip b { color: $titleColor; font-weight: 600; }
  </style>
</head>
<body>
  <div class="wrap">
    <div class="badge">✓</div>
    <p class="tip">勾选下方方框，<b>确认你不是机器人</b>即可继续登录</p>
    <div id="cap" class="h-captcha"
      data-sitekey="${widget.siteKey}"
      data-callback="onPass"
      data-error-callback="onErr"
      data-expired-callback="onExp"
      data-size="normal"></div>
  </div>
  <script>
    function call(name, payload) {
      try { window.flutter_inappwebview.callHandler(name, payload); } catch (e) {}
    }
    function onPass(token) { call('hcaptcha_pass', token); }
    function onErr(err) { call('hcaptcha_error', String(err || 'unknown')); }
    function onExp() { call('hcaptcha_expired', null); }

    window.__fluxdoLogin = async function(identifier, password, hcaptchaToken, secondFactorToken) {
      function done(p) {
        try { window.flutter_inappwebview.callHandler('login_result', JSON.stringify(p)); } catch (e) {}
      }
      try {
        var c = await fetch('/session/csrf', {
          method: 'GET',
          credentials: 'include',
          cache: 'no-store',
          headers: { 'X-Requested-With': 'XMLHttpRequest', 'Accept': 'application/json' }
        });
        if (c.status !== 200) {
          return done({ phase: 'csrf', status: c.status, body: await c.text() });
        }
        var csrf = (await c.json()).csrf;

        if (hcaptchaToken) {
          var h = await fetch('/captcha/hcaptcha/create.json', {
            method: 'POST',
            credentials: 'include',
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
              'X-CSRF-Token': csrf,
              'X-Requested-With': 'XMLHttpRequest'
            },
            body: 'token=' + encodeURIComponent(hcaptchaToken)
          });
          if (h.status !== 200) {
            return done({ phase: 'hcaptcha', status: h.status, body: await h.text() });
          }
        }

        var form = 'login=' + encodeURIComponent(identifier) +
          '&password=' + encodeURIComponent(password);
        if (secondFactorToken) {
          form += '&second_factor_token=' + encodeURIComponent(secondFactorToken) +
            '&second_factor_method=1';
        }
        var s = await fetch('/session.json', {
          method: 'POST',
          credentials: 'include',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded',
            'X-CSRF-Token': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'Accept': 'application/json'
          },
          body: form
        });
        return done({ phase: 'session', status: s.status, body: await s.text() });
      } catch (e) {
        return done({ phase: 'exception', status: 0, body: String(e) });
      }
    };
  </script>
  <script src="https://js.hcaptcha.com/1/api.js" async defer></script>
</body>
</html>
''';
  }

  void _setupHandlers(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'hcaptcha_pass',
      callback: (args) {
        final token = args.isNotEmpty ? args.first?.toString() : null;
        if (token != null && token.isNotEmpty) {
          _runLogin(hcaptchaToken: token, secondFactorToken: null);
        }
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'hcaptcha_error',
      callback: (args) {
        debugPrint(
          '[WebViewLogin] hcaptcha error: ${args.isNotEmpty ? args.first : ''}',
        );
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'hcaptcha_expired',
      callback: (_) {
        debugPrint('[WebViewLogin] hcaptcha expired');
        return null;
      },
    );
    controller.addJavaScriptHandler(
      handlerName: 'login_result',
      callback: (args) {
        final raw = args.isNotEmpty ? args.first?.toString() : null;
        if (raw != null) _onLoginResult(raw);
        return null;
      },
    );
  }

  Future<void> _primeCookiesFromJar() async {
    if (_cookiesPrimed) return;
    _cookiesPrimed = true;
    try {
      final header = await CookieJarService().getCookieHeader();
      if (header == null || header.isEmpty) return;
      final cookieManager = Platform.isWindows
          ? WindowsWebViewEnvironmentService.instance.cookieManager
          : CookieManager.instance();
      final url = WebUri('${AppConstants.baseUrl}/');
      for (final pair in header.split('; ')) {
        final idx = pair.indexOf('=');
        if (idx <= 0) continue;
        final name = pair.substring(0, idx).trim();
        final value = pair.substring(idx + 1).trim();
        if (name.isEmpty) continue;
        await cookieManager.setCookie(url: url, name: name, value: value);
      }
    } catch (e) {
      debugPrint('[WebViewLogin] 预灌 cookie 失败: $e');
    }
  }

  Future<void> _runLogin({
    required String? hcaptchaToken,
    required String? secondFactorToken,
  }) async {
    final controller = _controller;
    if (controller == null || _finished) return;
    if (mounted) setState(() => _processing = true);

    await _primeCookiesFromJar();
    if (_finished) return;

    final id = jsonEncode(widget.identifier);
    final pwd = jsonEncode(widget.password);
    final token = hcaptchaToken == null ? 'null' : jsonEncode(hcaptchaToken);
    final second = secondFactorToken == null
        ? 'null'
        : jsonEncode(secondFactorToken);
    try {
      await controller.evaluateJavascript(
        source: 'window.__fluxdoLogin($id, $pwd, $token, $second);',
      );
    } catch (e) {
      debugPrint('[WebViewLogin] 执行登录脚本失败: $e');
      _finishFailure(LoginErrorKind.unknown, '登录脚本执行失败');
    }
  }

  Future<void> _onLoginResult(String raw) async {
    if (_finished) return;

    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      _finishFailure(LoginErrorKind.unknown, '登录响应解析失败');
      return;
    }

    final phase = payload['phase']?.toString();
    final status = (payload['status'] as num?)?.toInt() ?? 0;
    final body = payload['body']?.toString() ?? '';

    switch (phase) {
      case 'csrf':
        _finishFailure(
          LoginErrorKind.network,
          'Cloudflare 验证已失效 (CSRF $status)',
        );
        return;
      case 'hcaptcha':
        _finishFailure(LoginErrorKind.unknown, '人机验证失败 (hcaptcha $status)');
        return;
      case 'exception':
        _finishFailure(LoginErrorKind.network, '登录请求异常: $body');
        return;
      case 'session':
        break;
      default:
        _finishFailure(LoginErrorKind.unknown, '未知登录阶段: $phase');
        return;
    }

    final result = DiscourseService().parseSessionJsonBody(status, body);
    if (result is LoginSuccess) {
      await _finishSuccess();
      return;
    }

    final failure = result as LoginFailure;
    if (failure.kind == LoginErrorKind.secondFactorRequired) {
      await _handleSecondFactor(failure);
      return;
    }
    _finishFailure(failure.kind, failure.message);
  }

  Future<void> _handleSecondFactor(LoginFailure failure) async {
    if (_finished || !mounted) return;
    final code = await widget.onNeedSecondFactor(
      WebViewLoginNeed2FA(
        totpEnabled: failure.totpEnabled,
        backupEnabled: failure.backupEnabled,
        securityKeyEnabled: failure.securityKeyEnabled,
        message: failure.message,
      ),
    );
    if (_finished || !mounted) return;
    if (code == null || code.isEmpty) {
      _finishCanceled();
      return;
    }
    await _runLogin(hcaptchaToken: null, secondFactorToken: code);
  }

  Future<void> _finishSuccess() async {
    if (_finished) return;
    _finished = true;
    try {
      await BoundarySyncService.instance.syncFromWebView(
        controller: _controller,
        currentUrl: AppConstants.baseUrl,
        cookieNames: CookieJarService.sessionCookieNames,
        allowLowConfidenceSessionCookies: true,
      );
    } catch (e) {
      debugPrint('[WebViewLogin] 同步登录 cookie 失败: $e');
    }
    if (mounted) {
      Navigator.of(context).pop(const WebViewLoginDialogResult.success());
    }
  }

  void _finishFailure(LoginErrorKind kind, String? message) {
    if (_finished) return;
    _finished = true;
    if (mounted) {
      Navigator.of(
        context,
      ).pop(WebViewLoginDialogResult.failure(kind, message));
    }
  }

  void _finishCanceled() {
    if (_finished) return;
    _finished = true;
    if (mounted) {
      Navigator.of(context).pop(const WebViewLoginDialogResult.canceled());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 640;
            final horizontal = compact ? 12.0 : 24.0;
            final vertical = compact ? 12.0 : 24.0;
            final availableHeight = math.max(
              360.0,
              constraints.maxHeight - vertical * 2,
            );
            final panelHeight = math.min(availableHeight, 640.0);

            return Align(
              alignment: compact ? Alignment.bottomCenter : Alignment.center,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontal,
                  vertical: vertical,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: SizedBox(
                    width: double.infinity,
                    height: panelHeight,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Column(
                          children: [
                            _Header(onClose: _finishCanceled, scheme: scheme),
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: InAppWebView(
                                      webViewEnvironment: Platform.isWindows
                                          ? WindowsWebViewEnvironmentService
                                                .instance
                                                .environment
                                          : null,
                                      initialData: InAppWebViewInitialData(
                                        data: _inlineHtml,
                                        baseUrl: WebUri(AppConstants.baseUrl),
                                        mimeType: 'text/html',
                                        encoding: 'utf-8',
                                      ),
                                      initialSettings: InAppWebViewSettings(
                                        javaScriptEnabled: true,
                                        transparentBackground: true,
                                        supportZoom: false,
                                        sharedCookiesEnabled: true,
                                        thirdPartyCookiesEnabled: true,
                                        userAgent: AppConstants
                                            .webViewUserAgentOverride,
                                      ),
                                      initialUserScripts:
                                          WebViewSettings.compatPolyfillScripts,
                                      onReceivedServerTrustAuthRequest:
                                          (_, challenge) =>
                                              WebViewSettings.handleServerTrustAuthRequest(
                                                challenge,
                                              ),
                                      onWebViewCreated: (controller) {
                                        _controller = controller;
                                        WebViewSettings.registerJsErrorReporter(
                                          controller,
                                        );
                                        _setupHandlers(controller);
                                      },
                                      onLoadStop: (_, _) {
                                        if (mounted) {
                                          setState(() => _loading = false);
                                        }
                                      },
                                    ),
                                  ),
                                  if (_loading)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  if (_processing)
                                    Positioned.fill(
                                      child: ColoredBox(
                                        color: scheme.surface.withValues(
                                          alpha: 0.92,
                                        ),
                                        child: Center(
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              const CircularProgressIndicator(),
                                              const SizedBox(height: 16),
                                              Text(
                                                '正在登录...',
                                                style:
                                                    theme.textTheme.bodyMedium,
                                              ),
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
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, required this.scheme});

  final VoidCallback onClose;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, size: 20, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '完成人机验证',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 22),
            tooltip: '取消',
            onPressed: onClose,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
