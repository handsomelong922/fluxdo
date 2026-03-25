import 'dart:async';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
import 'default_cookie_strategy.dart';

/// Android 平台 Cookie 策略
/// domain 保持原值，host-only cookie 保持 null
class AndroidCookieStrategy extends DefaultCookieStrategy {
  @override
  Future<void> clearWebViewCookies(CookieSyncContext ctx) async {
    // Bug #3 fix：deleteAllCookies 可能 ANR，加 timeout 保护
    try {
      await ctx.webViewCookieManager
          .deleteAllCookies()
          .timeout(const Duration(seconds: 5));
    } on TimeoutException catch (_) {
      debugPrint(
        '[CookieJar][Android] deleteAllCookies timed out after 5s, '
        'falling back to per-host deletion',
      );
      // 兜底：逐 host 删除
      await super.clearWebViewCookies(ctx);
      return;
    } catch (e) {
      debugPrint('[CookieJar][Android] deleteAllCookies failed: $e');
      await super.clearWebViewCookies(ctx);
      return;
    }

    // 补充逐个精确删除残留的 domain cookie
    for (final host in ctx.relatedHosts) {
      final url = 'https://$host';
      final existing = await ctx.webViewCookieManager.getCookies(
        url: WebUri(url),
      );
      for (final wc in existing) {
        await ctx.webViewCookieManager.deleteCookie(
          url: WebUri(url),
          name: wc.name,
          domain: wc.domain,
          path: wc.path ?? '/',
        );
      }
    }
  }

  @override
  List<WebViewCookieWriteAttempt> buildWriteAttempts(
    io.Cookie cookie,
    String sourceHost,
  ) {
    // Android 平台：保持 cookie.domain 原值（与 0.1.28 一致），
    // host-only cookie 保持 null
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
