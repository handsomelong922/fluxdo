import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
import '../raw_cookie_writer.dart';
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
            '${wc.name}|$normalizedDomain|${wc.path ?? '/'}';
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
    final rawWriter = RawCookieWriter.instance;

    // 批量加载所有 cookie 的 Set-Cookie 头，避免循环内逐个查 jar
    final rawHeaders = <String, String?>{};
    if (rawWriter.isSupported) {
      for (final (cookie, _) in cookies) {
        if (!rawHeaders.containsKey(cookie.name)) {
          rawHeaders[cookie.name] = await loadSetCookieHeader(cookie.name);
        }
      }
    }

    var written = 0;
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
            appliedAttempt = attempt;
            break;
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
    }
    return written;
  }

  /// 从 EnhancedPersistCookieJar 获取 cookie 的 Set-Cookie 头
  /// 优先返回原始头（rawSetCookie），没有时从字段重建
  Future<String?> loadSetCookieHeader(String name) async {
    try {
      final jar = CookieJarService();
      final canonical = await jar.getCanonicalCookie(name);
      return canonical?.toSetCookieHeader();
    } catch (_) {
      return null;
    }
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
