import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'cookie_jar_service.dart';
import 'cookie_sync_context.dart';

/// Windows 平台的 Cookie 诊断日志工具
class CookieDiagnostics {
  const CookieDiagnostics._();

  /// 记录 Windows cookie 同步状态
  static Future<void> logWindowsCookieSyncStatus(
    String phase, {
    required CookieJarService jar,
    required CookieSyncContext ctx,
    List<Cookie>? webViewCookies,
  }) async {
    if (!io.Platform.isWindows) return;

    final baseHost = ctx.baseUri.host;

    final effectiveWebViewCookies =
        webViewCookies ??
        await _collectWebViewCookiesFlat(baseHost, ctx.webViewCookieManager);

    final jarCookies = <io.Cookie>[];
    final seenJarKeys = <String>{};
    for (final host in ctx.relatedHosts) {
      final hostCookies = await jar.cookieJar.loadForRequest(
        Uri.parse('https://$host'),
      );
      for (final cookie in hostCookies) {
        final key =
            '${cookie.name}|${cookie.domain}|${cookie.path}|${cookie.value.hashCode}';
        if (seenJarKeys.add(key)) {
          jarCookies.add(cookie);
        }
      }
    }

    final missingInJar = <String>[];
    final missingInWebView = <String>[];
    final diagnostics = <String>[];

    for (final name in const ['_t', '_forum_session', 'cf_clearance']) {
      final webViewCookie = pickWebViewCookie(effectiveWebViewCookies, name);
      final jarCookie = pickJarCookie(jarCookies, name);

      if (webViewCookie != null && jarCookie == null) {
        missingInJar.add(name);
      }
      if (jarCookie != null && webViewCookie == null) {
        missingInWebView.add(name);
      }

      diagnostics.add(
        '$name(wv=${formatWebViewCookieState(webViewCookie)}, '
        'jar=${formatJarCookieState(jarCookie)})',
      );
    }

    final hasMismatch = missingInJar.isNotEmpty || missingInWebView.isNotEmpty;
    if (kDebugMode || hasMismatch) {
      debugPrint('[CookieJar][Windows] $phase ${diagnostics.join(', ')}');
    }
    if (hasMismatch) {
      debugPrint(
        '[CookieJar][Windows] $phase mismatch: '
        'missingInJar=$missingInJar, missingInWebView=$missingInWebView',
      );
    }
  }

  /// 记录 Windows WebView 中关键 cookie 的重复情况
  static Future<void> logWindowsDuplicateCriticalCookies(
    String phase,
    Iterable<String> hosts,
    CookieManager webViewCookieManager,
  ) async {
    if (!io.Platform.isWindows) return;

    for (final host in hosts) {
      final cookies = await webViewCookieManager.getCookies(
        url: WebUri('https://$host'),
      );
      final grouped = <String, List<Cookie>>{};
      for (final cookie in cookies) {
        if (!CookieJarService.isCriticalCookie(cookie.name)) continue;
        final key = '${cookie.name}|${cookie.path ?? "/"}';
        grouped.putIfAbsent(key, () => <Cookie>[]).add(cookie);
      }

      final duplicates = grouped.entries
          .where((entry) => entry.value.length > 1)
          .map((entry) {
            final name = entry.key.split('|').first;
            final states = entry.value
                .map(
                  (cookie) =>
                      '${cookie.domain ?? "host-only"}:${cookie.value.length}',
                )
                .join(', ');
            return '$name($states)';
          })
          .toList();

      if (duplicates.isNotEmpty) {
        debugPrint(
          '[CookieJar][Windows] $phase duplicate critical cookies on $host: '
          '${duplicates.join('; ')}',
        );
      }
    }
  }

  /// 从 WebView cookie 列表中选取指定名称的 cookie
  static Cookie? pickWebViewCookie(List<Cookie> cookies, String name) {
    Cookie? fallback;
    for (final cookie in cookies) {
      if (cookie.name != name) continue;
      if (cookie.value.isNotEmpty) return cookie;
      fallback ??= cookie;
    }
    return fallback;
  }

  /// 从 CookieJar cookie 列表中选取指定名称的 cookie
  static io.Cookie? pickJarCookie(List<io.Cookie> cookies, String name) {
    io.Cookie? fallback;
    for (final cookie in cookies) {
      if (cookie.name != name) continue;
      if (cookie.domain == null) return cookie;
      fallback ??= cookie;
    }
    return fallback;
  }

  /// 格式化 WebView cookie 状态
  static String formatWebViewCookieState(Cookie? cookie) {
    if (cookie == null) return '-';
    return '${cookie.value.length}:${cookie.domain ?? "host-only"}';
  }

  /// 格式化 CookieJar cookie 状态
  static String formatJarCookieState(io.Cookie? cookie) {
    if (cookie == null) return '-';
    return '${CookieValueCodec.decode(cookie.value).length}:${cookie.domain ?? "host-only"}';
  }

  /// 收集 WebView cookie 的扁平列表（用于诊断）
  static Future<List<Cookie>> _collectWebViewCookiesFlat(
    String baseHost,
    CookieManager webViewCookieManager,
  ) async {
    final hosts = [baseHost];
    final cookies = <Cookie>[];
    for (final host in hosts) {
      final hostCookies = await webViewCookieManager.getCookies(
        url: WebUri('https://$host'),
      );
      cookies.addAll(hostCookies);
    }
    return cookies;
  }
}
