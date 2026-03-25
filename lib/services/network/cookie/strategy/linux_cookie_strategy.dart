import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
import 'default_cookie_strategy.dart';

/// Linux 平台 Cookie 策略
/// WPE WebView 的 getCookies(url:) 可能匹配不到，使用 getAllCookies() 绕过
class LinuxCookieStrategy extends DefaultCookieStrategy {
  @override
  Future<List<CollectedWebViewCookie>> readCookiesFromWebView(
    CookieSyncContext ctx,
  ) async {
    // Bug #7 fix：使用 getAllCookies() 替代 getCookies(url:)
    // WPE WebView 的 URL 匹配可能不准确
    try {
      final allCookies = await ctx.webViewCookieManager.getAllCookies();
      final collected = <String, CollectedWebViewCookie>{};

      for (final wc in allCookies) {
        // 只保留与应用相关的 cookie
        if (!CookieJarService.matchesAppHost(wc.domain)) continue;

        final normalizedDomain =
            CookieJarService.normalizeWebViewCookieDomain(wc.domain) ??
            ctx.baseUri.host;
        final key =
            '${wc.name}|$normalizedDomain|${wc.path ?? '/'}|${wc.value.hashCode}';
        final snapshot = collected.putIfAbsent(
          key,
          () => CollectedWebViewCookie(
            cookie: wc,
            primaryHost: normalizedDomain,
          ),
        );
        snapshot.sourceHosts.add(normalizedDomain);
      }

      return collected.values.toList();
    } catch (e) {
      debugPrint(
        '[CookieJar][Linux] getAllCookies failed, falling back to default: $e',
      );
      return super.readCookiesFromWebView(ctx);
    }
  }

  @override
  Future<String?> readLiveCookieValue(
    InAppWebViewController controller,
    String name, {
    String? currentUrl,
  }) async {
    // Linux WPE: 无 CDP，用 getAllCookies() 绕过 URL 过滤
    try {
      final webViewCookieManager =
          CookieJarService().webViewCookieManager;
      final allCookies = await webViewCookieManager.getAllCookies();
      for (final c in allCookies) {
        if (c.name == name &&
            c.value.isNotEmpty &&
            CookieJarService.matchesAppHost(c.domain)) {
          return c.value;
        }
      }
    } catch (e) {
      debugPrint('[CookieJar][Linux] getAllCookies fallback for $name: $e');
    }
    return null;
  }

  @override
  Future<void> syncCriticalFromController(
    InAppWebViewController controller,
    Set<String> names,
    CookieSyncContext ctx,
    CookieJarService jar,
  ) async {
    // Linux WPE: 无 CDP，用 getAllCookies() 绕过 URL 匹配问题
    try {
      final allCookies = await ctx.webViewCookieManager.getAllCookies();
      if (allCookies.isEmpty) return;

      var synced = 0;
      for (final cookie in allCookies) {
        if (!names.contains(cookie.name)) continue;
        if (!CookieJarService.matchesAppHost(cookie.domain) ||
            cookie.value.isEmpty) {
          continue;
        }

        final rawDomain = cookie.domain?.trim();
        final persistedDomain =
            (rawDomain != null && rawDomain.startsWith('.'))
                ? rawDomain
                : null;

        await jar.setCookie(
          cookie.name,
          cookie.value,
          domain: persistedDomain,
          path: cookie.path ?? '/',
          expires: CookieJarService.parseWebViewCookieExpires(
            cookie.expiresDate,
          ),
          secure: cookie.isSecure ?? false,
          httpOnly: cookie.isHttpOnly ?? false,
        );
        synced++;
      }
      if (synced > 0) {
        debugPrint(
          '[CookieJar][Linux] Synced $synced live cookies via getAllCookies()',
        );
      }
    } catch (e) {
      debugPrint('[CookieJar][Linux] syncCriticalCookies failed: $e');
    }
  }
}
