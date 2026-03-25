import 'dart:io' as io;

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../cookie_jar_service.dart';
import '../cookie_sync_context.dart';
import 'apple_cookie_strategy.dart';
import 'android_cookie_strategy.dart';
import 'windows_cookie_strategy.dart';
import 'linux_cookie_strategy.dart';
import 'default_cookie_strategy.dart';

/// 平台 Cookie 策略抽象基类
/// 封装不同平台在 WebView Cookie 读写上的差异行为
abstract class PlatformCookieStrategy {
  /// 从 WebView 读取 Cookie
  Future<List<CollectedWebViewCookie>> readCookiesFromWebView(
    CookieSyncContext ctx,
  );

  /// 将 Cookie 写入 WebView（逐个 setCookie，平台特有的 domain/前导点处理）
  /// 返回成功写入的 cookie 数量
  Future<int> writeCookiesToWebView(
    List<(io.Cookie, String)> cookies,
    CookieSyncContext ctx,
  );

  /// 清除 WebView Cookie
  Future<void> clearWebViewCookies(CookieSyncContext ctx);

  /// 从控制器读取单个实时 Cookie 值（Windows/Linux 有特殊实现）
  Future<String?> readLiveCookieValue(
    InAppWebViewController controller,
    String name, {
    String? currentUrl,
  });

  /// 从控制器同步关键 Cookie 到 CookieJar
  Future<void> syncCriticalFromController(
    InAppWebViewController controller,
    Set<String> names,
    CookieSyncContext ctx,
    CookieJarService jar,
  );

  /// 通过控制器直接写入 Cookie（Windows CDP，其他平台返回 false）
  Future<bool> writeViaController(
    InAppWebViewController controller,
    List<(io.Cookie, String)> cookies,
    CookieSyncContext ctx,
  );

  /// syncToWebView 后处理（Apple 写 HTTPCookieStorage.shared）
  Future<void> postSyncToWebView(
    List<Map<String, dynamic>> cookieMaps,
    CookieSyncContext ctx,
  );

  /// 构建 WebView 写入尝试列表（url + domain 组合）
  List<WebViewCookieWriteAttempt> buildWriteAttempts(
    io.Cookie cookie,
    String sourceHost,
  );

  /// 构建删除 WebView cookie 时应尝试的 domain 变体列表
  /// 默认只返回原始 domain；Windows/Linux 等平台可 override 以处理
  /// domain 前导点不一致问题（如 ".linux.do" vs "linux.do"）
  List<String?> buildDeleteDomainVariants(String? domain) => [domain];

  /// 是否需要验证 Windows cookie readback
  bool shouldVerifyReadback(io.Cookie cookie, String sourceHost) => false;

  /// syncToWebView 时的 cookie 去重/选择逻辑（Windows 有特殊处理）
  /// 返回 null 表示使用默认去重逻辑
  Map<String, (io.Cookie, String)>? selectCriticalCookies(
    List<String> relatedHosts,
    Future<List<io.Cookie>> Function(String host) loadCookies,
  ) => null;

  /// 创建平台对应策略
  static PlatformCookieStrategy create() {
    if (io.Platform.isIOS || io.Platform.isMacOS) {
      return AppleCookieStrategy();
    }
    if (io.Platform.isAndroid) {
      return AndroidCookieStrategy();
    }
    if (io.Platform.isWindows) {
      return WindowsCookieStrategy();
    }
    if (io.Platform.isLinux) {
      return LinuxCookieStrategy();
    }
    return DefaultCookieStrategy();
  }
}
