import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../constants.dart';
import 'cookie_jar_service.dart';
import 'cookie_logger.dart';
import 'strategy/platform_cookie_strategy.dart';

/// 边界同步服务：在登录成功、CF 验证成功等关键时机，
/// 从 WebView CookieManager 读取 cookie 写入 CookieJar。
///
/// 只在边界时机调用，不做常态同步。
class BoundarySyncService {
  BoundarySyncService._internal();

  static final BoundarySyncService instance = BoundarySyncService._internal();

  final CookieJarService _jar = CookieJarService();
  final PlatformCookieStrategy _strategy = PlatformCookieStrategy.create();

  /// 从 WebView 读 cookie 写入 jar。
  ///
  /// [currentUrl] 当前页面 URL，用于确定读取哪个域名的 cookie。
  /// [cookieNames] 只同步指定的 cookie 名；null 表示同步所有。
  Future<void> syncFromWebView({
    String? currentUrl,
    InAppWebViewController? controller,
    Set<String>? cookieNames,
  }) async {
    final url = currentUrl ?? AppConstants.baseUrl;
    final uri = Uri.parse(url);
    final host = uri.host;

    try {
      if (io.Platform.isWindows && controller != null) {
        final synced = await _jar.syncCriticalCookiesFromController(
          controller,
          currentUrl: url,
          cookieNames: cookieNames,
        );
        if (synced > 0) {
          CookieLogger.sync(
            direction: 'WebView(CDP) → CookieJar',
            count: synced,
            names: cookieNames?.toList() ?? const [],
            source: 'boundary_sync',
            url: url,
          );
          return;
        }
      }

      // 通过 strategy 读取（Linux 用 getAllCookies 兜底）
      final webViewCookies = await _strategy.readCookiesFromWebView(
        _jar.webViewCookieManager,
        url,
      );

      final toSave = <io.Cookie>[];

      for (final wc in webViewCookies) {
        final value = wc.value?.toString() ?? '';
        if (value.isEmpty) continue;
        if (cookieNames != null && !cookieNames.contains(wc.name)) continue;

        // domain 处理：优先用平台返回值，旧 Android 兜底
        String? domain;
        if (wc.domain != null && wc.domain!.trim().isNotEmpty) {
          // 新设备：平台返回了 domain，直接使用
          domain = wc.domain;
        } else {
          // 旧 Android（GET_COOKIE_INFO 不支持）：domain 为 null
          // 优先继承 jar 中已有的 domain
          final existing = await _jar.getCanonicalCookie(wc.name);
          if (existing != null &&
              existing.domain != null &&
              existing.domain!.trim().isNotEmpty) {
            domain = existing.domain;
            debugPrint(
              '[BoundarySync] ${wc.name}: domain=null, 继承 jar 已有 domain=${existing.domain}',
            );
          } else {
            // jar 也没有 → 兜底为 .{host}（domain cookie）
            // 宁可多发到子域名，不能因为 host-only 导致子域名拿不到关键 cookie
            domain = '.$host';
            debugPrint('[BoundarySync] ${wc.name}: domain=null, 兜底为 .$host');
          }
        }

        io.Cookie cookie;
        try {
          cookie = io.Cookie(wc.name, value);
        } catch (_) {
          // value 含 RFC 不允许的字符（如 { } " 等），编码后存储
          cookie = io.Cookie(wc.name, CookieValueCodec.encode(value));
        }
        cookie
          ..domain = domain
          ..path = wc.path ?? '/'
          ..secure = wc.isSecure ?? false
          ..httpOnly = wc.isHttpOnly ?? false;

        if (wc.expiresDate != null) {
          cookie.expires = DateTime.fromMillisecondsSinceEpoch(wc.expiresDate!);
        }

        toSave.add(cookie);
      }

      if (toSave.isEmpty) {
        debugPrint('[BoundarySync] 未从 WebView 读取到有效 cookie: url=$url');
        return;
      }

      if (!_jar.isInitialized) await _jar.initialize();
      await _jar.cookieJar.saveFromResponse(uri, toSave);

      CookieLogger.sync(
        direction: 'WebView → CookieJar',
        count: toSave.length,
        names: toSave.map((c) => c.name).toList(),
        source: 'boundary_sync',
        url: url,
      );
    } catch (e) {
      CookieLogger.error(operation: 'boundary_sync', error: e.toString());
    }
  }
}
