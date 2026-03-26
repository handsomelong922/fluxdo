import 'dart:io' as io;

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../../constants.dart';
import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
import 'default_cookie_strategy.dart';

/// Windows 平台 Cookie 策略
/// 使用 CDP（Chrome DevTools Protocol）读写 cookie，处理 WebView2 的 domain 问题
class WindowsCookieStrategy extends DefaultCookieStrategy {
  @override
  Future<List<CollectedWebViewCookie>> readCookiesFromWebView(
    CookieSyncContext ctx,
  ) async {
    // 当 controller 可用时走 CDP
    if (ctx.controller != null) {
      return _readCookiesViaCDP(ctx);
    }
    // 否则走标准 CookieManager
    return super.readCookiesFromWebView(ctx);
  }

  /// 通过 CDP 读取 cookie
  Future<List<CollectedWebViewCookie>> _readCookiesViaCDP(
    CookieSyncContext ctx,
  ) async {
    final controller = ctx.controller!;
    final resolvedCurrentUrl =
        ctx.currentUrl ?? (await controller.getUrl())?.toString();
    final cdpUrls = <String>{
      AppConstants.baseUrl,
      '${AppConstants.baseUrl}/',
      if (resolvedCurrentUrl != null && resolvedCurrentUrl.isNotEmpty)
        resolvedCurrentUrl,
      for (final host in ctx.relatedHosts) 'https://$host',
    }.toList();

    final result = await controller.callDevToolsProtocolMethod(
      methodName: 'Network.getCookies',
      parameters: {'urls': cdpUrls},
    );
    final rawCookies = result is Map<String, dynamic>
        ? result['cookies']
        : null;
    if (rawCookies is! List || rawCookies.isEmpty) {
      return const [];
    }

    // 转换为 CollectedWebViewCookie
    final collected = <String, CollectedWebViewCookie>{};
    for (final raw in rawCookies.whereType<Map>()) {
      final name = raw['name']?.toString();
      final domain = raw['domain']?.toString() ?? '';
      if (name == null) continue;

      // 只保留与 baseHost 相关的 cookie
      final normalized = domain.replaceFirst(RegExp(r'^\.'), '');
      if (normalized.isNotEmpty &&
          normalized != ctx.baseUri.host &&
          !normalized.endsWith('.${ctx.baseUri.host}') &&
          !ctx.baseUri.host.endsWith('.$normalized')) {
        continue;
      }

      final path = raw['path']?.toString() ?? '/';
      final value = raw['value']?.toString() ?? '';

      // 构造 Cookie 对象
      final wc = Cookie(
        name: name,
        value: value,
        domain: domain.isEmpty ? null : domain,
        path: path,
        isSecure: raw['secure'] == true,
        isHttpOnly: raw['httpOnly'] == true,
      );

      // CDP 返回秒级时间戳
      final expiresRaw = raw['expires'];
      if (expiresRaw is num && expiresRaw > 0) {
        wc.expiresDate = (expiresRaw * 1000).round();
      }

      final host = normalized.isNotEmpty ? normalized : ctx.baseUri.host;
      final key = '$name|${normalized.isEmpty ? host : normalized}|$path';
      final snapshot = collected.putIfAbsent(
        key,
        () => CollectedWebViewCookie(cookie: wc, primaryHost: host),
      );
      snapshot.sourceHosts.add(host);
    }

    return collected.values.toList();
  }

  @override
  Future<String?> readLiveCookieValue(
    InAppWebViewController controller,
    String name, {
    String? currentUrl,
  }) async {
    try {
      final liveCookies = await _readLiveCookiesFromController(
        controller,
        currentUrl: currentUrl,
      );
      _DevToolsCookieSnapshot? fallback;
      for (final cookie in liveCookies) {
        if (cookie.name != name) continue;
        if (CookieJarService.matchesAppHost(cookie.domain) &&
            cookie.value.isNotEmpty) {
          return cookie.value;
        }
        fallback ??= cookie;
      }
      return fallback?.value;
    } catch (e) {
      debugPrint(
        '[CookieJar][Windows] Failed to read live cookie $name: $e',
      );
      return null;
    }
  }

  @override
  Future<void> syncCriticalFromController(
    InAppWebViewController controller,
    Set<String> names,
    CookieSyncContext ctx,
    CookieJarService jar,
  ) async {
    try {
      final liveCookies = await _readLiveCookiesFromController(
        controller,
        currentUrl: ctx.currentUrl,
      );
      if (liveCookies.isEmpty) return;

      var synced = 0;
      for (final cookie in liveCookies) {
        if (!names.contains(cookie.name)) continue;
        if (!CookieJarService.matchesAppHost(cookie.domain) ||
            cookie.value.isEmpty) {
          continue;
        }

        await jar.setCookie(
          cookie.name,
          cookie.value,
          url: ctx.currentUrl,
          domain: cookie.persistedDomain,
          path: cookie.path,
          expires: cookie.expires,
          secure: cookie.secure,
          httpOnly: cookie.httpOnly,
        );
        synced++;
      }

      if (synced > 0) {
        debugPrint(
          '[CookieJar][Windows] Synced $synced live cookies from controller: '
          '${names.join(", ")}',
        );
      }
    } catch (e) {
      debugPrint('[CookieJar][Windows] Failed to sync live cookies: $e');
    }
  }

  @override
  Future<bool> writeViaController(
    InAppWebViewController controller,
    List<(io.Cookie, String)> cookies,
    CookieSyncContext ctx,
  ) async {
    if (cookies.isEmpty) return true;

    try {
      // Bug #6 fix：先启用 Network domain，确保 cookie 写入在页面网络请求之前生效
      try {
        await controller.callDevToolsProtocolMethod(
          methodName: 'Network.enable',
          parameters: {},
        );
      } catch (_) {
        // Network.enable 可能已经启用，忽略
      }

      var written = 0;
      for (final (cookie, sourceHost) in cookies) {
        final value = CookieValueCodec.decode(cookie.value);
        final normalizedDomain =
            CookieJarService.normalizeWebViewCookieDomain(cookie.domain);

        String cdpUrl;
        String? cdpDomain;
        if (normalizedDomain != null) {
          cdpUrl = 'https://$normalizedDomain';
          cdpDomain = cookie.domain!.startsWith('.')
              ? cookie.domain
              : '.$normalizedDomain';
        } else {
          cdpUrl = 'https://$sourceHost';
          cdpDomain = null;
        }

        final params = <String, dynamic>{
          'url': cdpUrl,
          'name': cookie.name,
          'value': value.isEmpty ? ' ' : value,
          'path': cookie.path ?? '/',
          'secure': cookie.secure,
          'httpOnly': cookie.httpOnly,
        };
        if (cdpDomain != null) {
          params['domain'] = cdpDomain;
        }
        if (cookie.expires != null) {
          params['expires'] =
              cookie.expires!.millisecondsSinceEpoch / 1000.0;
        }
        // HttpOnly + Secure → SameSite=None，匹配服务端行为，避免重复
        if (cookie.httpOnly && cookie.secure) {
          params['sameSite'] = 'None';
        }

        try {
          // 写入前先删除已有 cookie，防止 SameSite 差异导致重复
          await controller.callDevToolsProtocolMethod(
            methodName: 'Network.deleteCookies',
            parameters: {
              'name': cookie.name,
              'url': cdpUrl,
              if (cdpDomain != null) 'domain': cdpDomain,
              'path': cookie.path ?? '/',
            },
          );
          await controller.callDevToolsProtocolMethod(
            methodName: 'Network.setCookie',
            parameters: params,
          );
          written++;
        } catch (e) {
          debugPrint(
            '[CookieJar][Windows] CDP setCookie failed: ${cookie.name}, $e',
          );
        }
      }

      // Bug #6 fix：写完后延迟，确保 cookie 对后续 loadUrl 可见
      if (written > 0) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      debugPrint(
        '[CookieJar][Windows] writeViaController: $written/${cookies.length} cookies',
      );
      return written > 0;
    } catch (e) {
      debugPrint('[CookieJar][Windows] writeViaController failed: $e');
      return false;
    }
  }

  /// Windows：删除时尝试加/去前导点两种 domain 变体
  /// WebView2 的 CookieManager.getCookies() 返回的 domain 可能丢失前导点，
  /// 导致 deleteCookie 匹配不上实际存储的 cookie
  @override
  List<String?> buildDeleteDomainVariants(String? domain) {
    final variants = <String?>{domain};
    final trimmed = domain?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      if (trimmed.startsWith('.')) {
        variants.add(trimmed.substring(1));
      } else {
        variants.add('.$trimmed');
      }
    }
    return variants.toList();
  }

  @override
  List<WebViewCookieWriteAttempt> buildWriteAttempts(
    io.Cookie cookie,
    String sourceHost,
  ) {
    final attempts = <WebViewCookieWriteAttempt>[];
    final seen = <String>{};

    void addAttempt(String host, {String? domain}) {
      final normalizedHost = host.trim();
      if (normalizedHost.isEmpty) return;
      final normalizedDomain = domain?.trim();
      final key = '${normalizedDomain ?? ''}|$normalizedHost';
      if (!seen.add(key)) return;
      attempts.add(
        WebViewCookieWriteAttempt(
          url: 'https://$normalizedHost',
          domain: normalizedDomain,
        ),
      );
    }

    final normalizedCookieDomain =
        CookieJarService.normalizeWebViewCookieDomain(cookie.domain);

    // 关键 cookie 特殊处理
    if (CookieJarService.isCriticalCookie(cookie.name)) {
      if (normalizedCookieDomain != null) {
        final exactDomain = cookie.domain?.trim();
        addAttempt(normalizedCookieDomain, domain: exactDomain);
      } else {
        addAttempt(sourceHost, domain: null);
      }
      return attempts;
    }

    // 非关键 cookie
    if (normalizedCookieDomain != null) {
      final exactDomain = cookie.domain?.trim();
      if (exactDomain != null && exactDomain.isNotEmpty) {
        addAttempt(normalizedCookieDomain, domain: exactDomain);
      }
      if (exactDomain != null && exactDomain.startsWith('.')) {
        addAttempt(normalizedCookieDomain, domain: normalizedCookieDomain);
      } else {
        addAttempt(normalizedCookieDomain, domain: '.$normalizedCookieDomain');
      }
    } else {
      addAttempt(sourceHost, domain: null);

      final baseHost = Uri.parse(AppConstants.baseUrl).host;
      if (sourceHost != baseHost) {
        addAttempt(sourceHost, domain: sourceHost);
      }
    }

    return attempts;
  }

  @override
  bool shouldVerifyReadback(io.Cookie cookie, String sourceHost) {
    // 关键 cookie 不做 readback 验证
    if (CookieJarService.isCriticalCookie(cookie.name)) return false;

    final baseHost = Uri.parse(AppConstants.baseUrl).host;
    return cookie.domain == null && sourceHost != baseHost;
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
      final doVerify = shouldVerifyReadback(cookie, sourceHost);
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

        if (doVerify) {
          final syncedCookie = await ctx.webViewCookieManager.getCookie(
            url: WebUri(attempt.url),
            name: cookie.name,
          );
          final syncedValue = syncedCookie?.value.trim();
          if (syncedValue != null && syncedValue == value) {
            appliedAttempt = attempt;
            break;
          }
          debugPrint(
            '[CookieJar][Windows] Cookie readback mismatch after syncToWebView: '
            'name=${cookie.name}, domain=${attempt.domain}, url=${attempt.url}',
          );
          if (CookieJarService.isCriticalCookie(cookie.name)) {
            await ctx.webViewCookieManager.deleteCookie(
              url: WebUri(attempt.url),
              name: cookie.name,
              domain: attempt.domain,
              path: cookie.path ?? '/',
            );
          }
          continue;
        }

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

  /// Windows 专用：cookie 去重评分
  static int compareWindowsCriticalCookieCandidates(
    io.Cookie candidate,
    io.Cookie existing, {
    required String requestHost,
  }) {
    final scoreDiff =
        _scoreWindowsCriticalCookieCandidate(candidate, requestHost) -
        _scoreWindowsCriticalCookieCandidate(existing, requestHost);
    if (scoreDiff != 0) return scoreDiff;

    final candidateExpires = candidate.expires;
    final existingExpires = existing.expires;
    if (candidateExpires != null && existingExpires == null) return 1;
    if (candidateExpires == null && existingExpires != null) return -1;
    if (candidateExpires != null && existingExpires != null) {
      final expiryDiff = candidateExpires.compareTo(existingExpires);
      if (expiryDiff != 0) return expiryDiff;
    }

    return candidate.value.length.compareTo(existing.value.length);
  }

  static int _scoreWindowsCriticalCookieCandidate(
    io.Cookie cookie,
    String requestHost,
  ) {
    if (cookie.domain == null) return 400;

    final normalizedDomain =
        CookieJarService.normalizeWebViewCookieDomain(cookie.domain);
    if (normalizedDomain == null) return 100;
    if (normalizedDomain == requestHost) return 300;
    if (requestHost.endsWith('.$normalizedDomain')) {
      return 200 + normalizedDomain.length;
    }
    return 100;
  }

  /// 通过 DevTools Protocol 读取实时 cookie
  Future<List<_DevToolsCookieSnapshot>> _readLiveCookiesFromController(
    InAppWebViewController controller, {
    String? currentUrl,
  }) async {
    final resolvedCurrentUrl =
        currentUrl ?? (await controller.getUrl())?.toString();

    final urls = <String>{
      AppConstants.baseUrl,
      '${AppConstants.baseUrl}/',
      if (resolvedCurrentUrl != null && resolvedCurrentUrl.isNotEmpty)
        resolvedCurrentUrl,
    }.toList();

    final result = await controller.callDevToolsProtocolMethod(
      methodName: 'Network.getCookies',
      parameters: {'urls': urls},
    );
    final rawCookies = result is Map<String, dynamic>
        ? result['cookies']
        : null;
    if (rawCookies is! List) return const [];

    final cookies = rawCookies
        .whereType<Map>()
        .map(
          (raw) => _DevToolsCookieSnapshot.fromMap(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .whereType<_DevToolsCookieSnapshot>()
        .toList();

    if (cookies.isNotEmpty) {
      final names = cookies.map((e) => e.name).toSet().join(', ');
      debugPrint('[CookieJar][Windows] DevTools cookies: [$names]');
    }

    return cookies;
  }

  Future<void> _persistRawCdpCookies(
    ioCookieJar,
    List rawCookies, {
    String? currentUrl,
  }) async {
    if (ioCookieJar is! EnhancedPersistCookieJar) return;

    final cookies = rawCookies
        .whereType<Map>()
        .map((raw) => raw.map((key, value) => MapEntry(key.toString(), value)))
        .cast<Map<String, dynamic>>()
        .toList(growable: false);
    if (cookies.isEmpty) return;

    final uri = Uri.tryParse(currentUrl ?? '') ?? Uri.parse(AppConstants.baseUrl);
    try {
      await ioCookieJar.saveFromCdpCookies(uri, cookies);
    } catch (e) {
      debugPrint('[CookieJar][Windows] Failed to persist CDP cookies: $e');
    }
  }
}

/// DevTools Protocol 返回的 cookie 快照
class _DevToolsCookieSnapshot {
  const _DevToolsCookieSnapshot({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.expires,
    required this.secure,
    required this.httpOnly,
  });

  final String name;
  final String value;
  final String? domain;
  final String path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;

  /// 返回用于 CookieJar 持久化的 domain 属性
  String? get persistedDomain {
    final trimmed = domain?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.startsWith('.') ? trimmed : null;
  }

  static _DevToolsCookieSnapshot? fromMap(Map<String, dynamic> map) {
    final name = map['name']?.toString();
    final value = map['value']?.toString();
    if (name == null || value == null) return null;

    DateTime? expires;
    final expiresRaw = map['expires'];
    if (expiresRaw is num && expiresRaw > 0) {
      expires = DateTime.fromMillisecondsSinceEpoch(
        (expiresRaw * 1000).round(),
      );
    }

    return _DevToolsCookieSnapshot(
      name: name,
      value: value,
      domain: map['domain']?.toString(),
      path: map['path']?.toString() ?? '/',
      expires: expires,
      secure: map['secure'] == true,
      httpOnly: map['httpOnly'] == true,
    );
  }
}
