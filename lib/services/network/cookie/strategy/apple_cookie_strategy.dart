import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../constants.dart';
import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
import '../raw_cookie_writer.dart';
import 'default_cookie_strategy.dart';

/// Apple 平台（iOS/macOS）Cookie 策略
/// 处理 domain 前导点、HTTPCookieStorage.shared 双写
class AppleCookieStrategy extends DefaultCookieStrategy {
  /// Apple 平台 platform channel，用于将 cookie 写入 HTTPCookieStorage.shared。
  /// WKWebView 的 sharedCookiesEnabled 在创建时从 HTTPCookieStorage.shared 读取 cookie，
  /// 比 WKHTTPCookieStore 的跨进程异步同步更可靠。
  static const _nativeCookieChannel = MethodChannel(
    'com.fluxdo/cookie_storage',
  );

  @override
  Future<int> writeCookiesToWebView(
    List<(io.Cookie, String)> cookies,
    CookieSyncContext ctx,
  ) async {
    final rawWriter = RawCookieWriter.instance;

    // 批量加载所有 cookie 的 Set-Cookie 头
    final rawHeaders = <String, String?>{};
    if (rawWriter.isSupported) {
      for (final (cookie, _) in cookies) {
        if (!rawHeaders.containsKey(cookie.name)) {
          rawHeaders[cookie.name] = await loadSetCookieHeader(cookie.name);
        }
      }
    }

    var written = 0;
    final cookieMaps = <Map<String, dynamic>>[];

    for (final (cookie, sourceHost) in cookies) {
      final value = CookieValueCodec.decode(cookie.value);
      final attempts = buildWriteAttempts(cookie, sourceHost);
      WebViewCookieWriteAttempt? appliedAttempt;

      for (final attempt in attempts) {
        for (final domain in buildDeleteDomainVariants(attempt.domain)) {
          await ctx.webViewCookieManager.deleteCookie(
            url: WebUri(attempt.url),
            name: cookie.name,
            domain: domain,
            path: cookie.path ?? '/',
          );
        }

        final rawHeader = rawHeaders[cookie.name];
        if (rawHeader != null && rawWriter.isSupported) {
          if (await rawWriter.setRawCookie(attempt.url, rawHeader)) {
            written++;
            continue; // 跳过 cookieMaps，避免 postSyncToWebView 重复写
          }
        }

        // Fallback：结构化 API
        final didSet = await ctx.webViewCookieManager.setCookie(
          url: WebUri(attempt.url),
          name: cookie.name,
          value: value.isEmpty ? ' ' : value,
          domain: attempt.domain,
          path: cookie.path ?? '/',
          isSecure: cookie.secure,
          isHttpOnly: cookie.httpOnly,
          expiresDate: cookie.expires?.millisecondsSinceEpoch,
          sameSite: (cookie.httpOnly && cookie.secure)
              ? HTTPCookieSameSitePolicy.NONE
              : null,
        );

        if (!didSet) continue;
        appliedAttempt = attempt;
        break;
      }

      if (appliedAttempt == null) {
        debugPrint(
          '[CookieJar] Failed to write cookie to WebView: ${cookie.name}',
        );
        continue;
      }
      written++;

      cookieMaps.add({
        'url': appliedAttempt.url,
        'name': cookie.name,
        'value': value.isEmpty ? ' ' : value,
        'domain': appliedAttempt.domain,
        'path': cookie.path ?? '/',
        'isSecure': cookie.secure,
        'isHttpOnly': cookie.httpOnly,
        'expiresDate': cookie.expires?.millisecondsSinceEpoch,
      });
    }

    if (written > 0) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    if (cookieMaps.isNotEmpty) {
      await postSyncToWebView(cookieMaps, ctx);
    }

    return written;
  }


  @override
  Future<void> postSyncToWebView(
    List<Map<String, dynamic>> cookieMaps,
    CookieSyncContext ctx,
  ) async {
    try {
      await _nativeCookieChannel.invokeMethod(
        'clearCookies',
        AppConstants.baseUrl,
      );
      await _nativeCookieChannel.invokeMethod('setCookies', cookieMaps);
    } catch (e) {
      debugPrint('[CookieJar] HTTPCookieStorage sync failed: $e');
    }
  }

  @override
  Future<void> clearWebViewCookies(CookieSyncContext ctx) async {
    await super.clearWebViewCookies(ctx);

    // 同时清除 HTTPCookieStorage.shared
    try {
      await _nativeCookieChannel.invokeMethod(
        'clearCookies',
        AppConstants.baseUrl,
      );
    } catch (e) {
      debugPrint('[CookieJar] HTTPCookieStorage clear failed: $e');
    }
  }

  @override
  List<WebViewCookieWriteAttempt> buildWriteAttempts(
    io.Cookie cookie,
    String sourceHost,
  ) {
    final normalizedCookieDomain =
        CookieJarService.normalizeWebViewCookieDomain(cookie.domain);
    if (normalizedCookieDomain != null) {
      // domain cookie：iOS setCookie 的 domain 必须带前导点（flutter_inappwebview #338）
      return [
        WebViewCookieWriteAttempt(
          url: 'https://$normalizedCookieDomain',
          domain: '.$normalizedCookieDomain',
        ),
      ];
    }
    // host-only cookie：domain 传 null，让 WebView 按 URL host 自动绑定
    return [
      WebViewCookieWriteAttempt(
        url: 'https://$sourceHost',
        domain: null,
      ),
    ];
  }
}
