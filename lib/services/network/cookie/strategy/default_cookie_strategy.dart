import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
import 'platform_cookie_strategy.dart';

/// 默认 Cookie 策略
/// 使用标准 CookieManager API，作为其他平台策略的基类
class DefaultCookieStrategy extends PlatformCookieStrategy {
  @override
  Future<List<CollectedWebViewCookie>> readCookiesFromWebView(
    CookieSyncContext ctx,
  ) async {
    final collected = <String, CollectedWebViewCookie>{};

    for (final host in ctx.relatedHosts) {
      final url = 'https://$host';
      final hostCookies = await ctx.webViewCookieManager.getCookies(
        url: WebUri(url),
      );
      for (final wc in hostCookies) {
        final normalizedDomain =
            CookieJarService.normalizeWebViewCookieDomain(wc.domain) ?? host;
        final key =
            '${wc.name}|$normalizedDomain|${wc.path ?? '/'}|${wc.value.hashCode}';
        final snapshot = collected.putIfAbsent(
          key,
          () => CollectedWebViewCookie(cookie: wc, primaryHost: host),
        );
        snapshot.sourceHosts.add(host);
      }
    }

    return collected.values.toList();
  }

  @override
  Future<int> writeCookiesToWebView(
    List<(io.Cookie, String)> cookies,
    CookieSyncContext ctx,
  ) async {
    var written = 0;
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
          // HttpOnly + Secure 的 cookie 服务端通常设 SameSite=None，
          // 必须匹配 SameSite 否则 WebView 会创建重复 cookie
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
    }
    return written;
  }

  @override
  Future<void> clearWebViewCookies(CookieSyncContext ctx) async {
    // 对每个相关 host 做一次无 domain 的批量删除
    for (final host in ctx.relatedHosts) {
      await ctx.webViewCookieManager.deleteCookies(
        url: WebUri('https://$host'),
      );
    }
    // 逐个 deleteCookie 精确清除 domain cookie
    for (final host in ctx.relatedHosts) {
      final url = 'https://$host';
      final existing = await ctx.webViewCookieManager.getCookies(
        url: WebUri(url),
      );
      for (final wc in existing) {
        final domainVariants = buildDeleteDomainVariants(wc.domain);
        for (final domain in domainVariants) {
          await ctx.webViewCookieManager.deleteCookie(
            url: WebUri(url),
            name: wc.name,
            domain: domain,
            path: wc.path ?? '/',
          );
        }
      }
    }
  }

  @override
  Future<String?> readLiveCookieValue(
    InAppWebViewController controller,
    String name, {
    String? currentUrl,
  }) async {
    return null;
  }

  @override
  Future<void> syncCriticalFromController(
    InAppWebViewController controller,
    Set<String> names,
    CookieSyncContext ctx,
    CookieJarService jar,
  ) async {
    // 默认不做任何事
  }

  @override
  Future<bool> writeViaController(
    InAppWebViewController controller,
    List<(io.Cookie, String)> cookies,
    CookieSyncContext ctx,
  ) async {
    return false;
  }

  @override
  Future<void> postSyncToWebView(
    List<Map<String, dynamic>> cookieMaps,
    CookieSyncContext ctx,
  ) async {
    // 默认不做任何事
  }

  @override
  List<WebViewCookieWriteAttempt> buildWriteAttempts(
    io.Cookie cookie,
    String sourceHost,
  ) {
    final normalizedCookieDomain =
        CookieJarService.normalizeWebViewCookieDomain(cookie.domain);
    return [
      WebViewCookieWriteAttempt(
        url: 'https://${normalizedCookieDomain ?? sourceHost}',
        domain: cookie.domain?.trim(),
      ),
    ];
  }

}
