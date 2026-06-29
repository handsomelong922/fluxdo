import 'dart:io' as io;

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../windows_webview_environment_service.dart';
import 'cookie_full_info.dart';

/// Windows / Linux 平台的 RawCookieWriter Dart fallback 实现。
///
/// Android/iOS/macOS 走 native method channel；Win/Linux 没有 native
/// raw-cookie channel，这里用 flutter_inappwebview 的 CookieManager 实现同
/// 一组原语。
class RawCookieWriterFallback {
  RawCookieWriterFallback._();
  static final RawCookieWriterFallback instance = RawCookieWriterFallback._();

  CookieManager get _cookieManager {
    if (io.Platform.isWindows) {
      return WindowsWebViewEnvironmentService.instance.cookieManager;
    }
    return CookieManager.instance();
  }

  /// 通过原始 Set-Cookie 头写入 WebView。
  ///
  /// 使用项目内 [SetCookieParser] 保留 SameSite/Partitioned 等字段。
  Future<bool> setRawCookie(
    String url,
    String rawSetCookie, {
    bool writeSharedStorage = true,
  }) async {
    try {
      final uri = Uri.parse(url);
      final canonical = SetCookieParser.parse(rawSetCookie, uri: uri);

      return await _cookieManager.setCookie(
        url: WebUri(url),
        name: canonical.name,
        value: canonical.value,
        path: canonical.path.isEmpty ? '/' : canonical.path,
        domain: canonical.hostOnly ? null : canonical.domain,
        expiresDate: canonical.expiresAt?.millisecondsSinceEpoch,
        maxAge: canonical.maxAge,
        isSecure: canonical.secure,
        isHttpOnly: canonical.httpOnly,
        sameSite: _mapSameSite(canonical.sameSite),
      );
    } catch (e) {
      debugPrint('[RawCookieWriterFallback] setRawCookie failed: $e');
      return false;
    }
  }

  /// 删除指定 name 的所有变体。
  ///
  /// 优先：用 `getCookies` 枚举真实 cookie，按各自真实 (domain, path) 精确删
  /// （与 [countCookiesByName] 对齐，确保"数得到的一定删得到"）。
  /// 兜底：旧 WebView 枚举不到字段 / getCookies 失败时，回退到穷举候选组合。
  Future<int> nukeAllVariants({
    required String url,
    required String name,
    required List<String?> domainCandidates,
    required List<String> pathCandidates,
  }) async {
    final webUri = WebUri(url);

    try {
      final cookies = await _cookieManager.getCookies(url: webUri);
      final matching = cookies.where((c) => c.name == name).toList();
      if (matching.isNotEmpty) {
        var deleted = 0;
        for (final c in matching) {
          try {
            final ok = await _cookieManager.deleteCookie(
              url: webUri,
              name: name,
              path: c.path ?? '/',
              domain: c.domain,
            );
            if (ok) deleted++;
          } catch (e) {
            debugPrint(
              '[RawCookieWriterFallback] deleteCookie(real $name, '
              '${c.domain}, ${c.path}) failed: $e',
            );
          }
        }
        return deleted;
      }
    } catch (e) {
      debugPrint(
        '[RawCookieWriterFallback] enumerate for nuke failed, '
        'fallback to candidates: $e',
      );
    }

    // 兜底：穷举 (domainCandidates × pathCandidates)。
    var deleted = 0;
    for (final domain in domainCandidates) {
      for (final path in pathCandidates) {
        try {
          final ok = await _cookieManager.deleteCookie(
            url: webUri,
            name: name,
            path: path,
            domain: domain,
          );
          if (ok) deleted++;
        } catch (e) {
          debugPrint(
            '[RawCookieWriterFallback] deleteCookie($name, $domain, $path) '
            'failed: $e',
          );
        }
      }
    }
    return deleted;
  }

  Future<bool> deleteExactCookie({
    required String url,
    required String name,
    required String? domain,
    required String path,
  }) async {
    try {
      return await _cookieManager.deleteCookie(
        url: WebUri(url),
        name: name,
        path: path,
        domain: domain,
      );
    } catch (e) {
      debugPrint('[RawCookieWriterFallback] deleteExactCookie failed: $e');
      return false;
    }
  }

  Future<List<CookieFullInfo>> getAllCookieInfos(String url) async {
    try {
      final cookies = await _cookieManager.getCookies(url: WebUri(url));
      return cookies
          .map(CookieFullInfo.fromWebViewCookie)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[RawCookieWriterFallback] getAllCookieInfos failed: $e');
      return const [];
    }
  }

  Future<int> countCookiesByName(String url, String name) async {
    try {
      final cookies = await _cookieManager.getCookies(url: WebUri(url));
      return cookies.where((c) => c.name == name).length;
    } catch (e) {
      debugPrint('[RawCookieWriterFallback] countCookiesByName failed: $e');
      return 0;
    }
  }

  HTTPCookieSameSitePolicy? _mapSameSite(CookieSameSite sameSite) {
    switch (sameSite) {
      case CookieSameSite.lax:
        return HTTPCookieSameSitePolicy.LAX;
      case CookieSameSite.strict:
        return HTTPCookieSameSitePolicy.STRICT;
      case CookieSameSite.none:
        return HTTPCookieSameSitePolicy.NONE;
      case CookieSameSite.unspecified:
        return null;
    }
  }
}
