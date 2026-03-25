import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../constants.dart';
import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
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
    var written = 0;
    final cookieMaps = <Map<String, dynamic>>[];

    for (final (cookie, sourceHost) in cookies) {
      final value = CookieValueCodec.decode(cookie.value);
      final attempts = buildWriteAttempts(cookie, sourceHost);
      WebViewCookieWriteAttempt? appliedAttempt;

      for (final attempt in attempts) {
        // 写入前先删除已有 cookie（含所有 domain 变体），
        // 防止 SameSite 属性差异导致 WebView 产生重复 cookie
        for (final domain in buildDeleteDomainVariants(attempt.domain)) {
          await ctx.webViewCookieManager.deleteCookie(
            url: WebUri(attempt.url),
            name: cookie.name,
            domain: domain,
            path: cookie.path ?? '/',
          );
        }

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

    // Bug #4 fix：批量写入后延迟，等待 WKHTTPCookieStore completionHandler 完成
    if (written > 0) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    // 同时写入 HTTPCookieStorage.shared 供后续 postSyncToWebView 使用
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
    // Apple 平台：iOS setCookie 的 domain 必须带前导点，否则静默失败
    // （flutter_inappwebview #338）
    final normalizedCookieDomain =
        CookieJarService.normalizeWebViewCookieDomain(cookie.domain);
    if (normalizedCookieDomain != null) {
      return [
        WebViewCookieWriteAttempt(
          url: 'https://$normalizedCookieDomain',
          domain: '.$normalizedCookieDomain',
        ),
      ];
    }
    return [
      WebViewCookieWriteAttempt(
        url: 'https://$sourceHost',
        domain: sourceHost,
      ),
    ];
  }
}
