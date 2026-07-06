import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../raw_cookie_writer.dart';
import 'default_cookie_strategy.dart';

/// Android cookie 策略
///
/// - 读取优先走 raw_cookie 通道，其原生侧在 cookie HandlerThread 执行，
///   避免高频 CookieManager IPC 挤占平台主线程；失败时回退插件通道。
/// - deleteAllCookies 加 timeout 保护（避免 ANR）
/// - 补充逐 host 精确删除残留 domain cookie
class AndroidCookieStrategy extends DefaultCookieStrategy {
  @override
  Future<List<Cookie>> readCookiesFromWebView(
    CookieManager cookieManager,
    String url,
  ) async {
    try {
      final infos = await RawCookieWriter.instance.getAllCookieInfos(url);
      if (infos.isEmpty) {
        return super.readCookiesFromWebView(cookieManager, url);
      }
      return infos
          .map(
            (info) => Cookie(
              name: info.name,
              value: info.value,
              domain: info.domain,
              path: info.path,
              isSecure: info.isSecure,
              isHttpOnly: info.isHttpOnly,
              expiresDate: info.expiresMillis,
              sameSite: _sameSiteFromString(info.sameSite),
            ),
          )
          .toList(growable: false);
    } catch (e) {
      debugPrint('[CookieStrategy][Android] raw_cookie read failed: $e');
      return super.readCookiesFromWebView(cookieManager, url);
    }
  }

  HTTPCookieSameSitePolicy? _sameSiteFromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final normalized =
        value[0].toUpperCase() + value.substring(1).toLowerCase();
    return HTTPCookieSameSitePolicy.fromValue(normalized);
  }

  @override
  Future<void> clearWebViewCookies(
    CookieManager cookieManager,
    Set<String> knownHosts,
  ) async {
    // deleteAllCookies 可能 ANR，加 timeout
    try {
      await cookieManager.deleteAllCookies().timeout(
        const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint(
        '[CookieStrategy][Android] deleteAllCookies failed/timeout: $e',
      );
    }

    // 补充逐 host 精确删除残留 cookie（deleteAllCookies 在 Android 上可能不彻底）
    for (final host in knownHosts) {
      try {
        final url = WebUri('https://$host');
        final remaining = await cookieManager.getCookies(url: url);
        for (final wc in remaining) {
          await cookieManager.deleteCookie(
            url: url,
            name: wc.name,
            domain: wc.domain,
            path: wc.path ?? '/',
          );
        }
      } catch (e) {
        debugPrint(
          '[CookieStrategy][Android] per-host delete failed for $host: $e',
        );
      }
    }
  }
}
