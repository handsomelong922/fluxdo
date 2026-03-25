import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Cookie 同步上下文，封装一次同步操作所需的全部参数
class CookieSyncContext {
  const CookieSyncContext({
    required this.baseUri,
    required this.relatedHosts,
    this.currentUrl,
    this.controller,
    this.cookieNames,
    required this.webViewCookieManager,
  });

  /// 应用基础 URI（如 https://linux.do）
  final Uri baseUri;

  /// 所有相关域名（主域 + 子域）
  final List<String> relatedHosts;

  /// 当前页面 URL
  final String? currentUrl;

  /// WebView 控制器（可选）
  final InAppWebViewController? controller;

  /// 需要同步的 cookie 名称集合（null 表示全部）
  final Set<String>? cookieNames;

  /// WebView CookieManager
  final CookieManager webViewCookieManager;
}

/// 从 WebView 收集到的 cookie 快照（去重用）
class CollectedWebViewCookie {
  CollectedWebViewCookie({required this.cookie, required this.primaryHost})
    : sourceHosts = {primaryHost};

  final Cookie cookie;
  final String primaryHost;
  final Set<String> sourceHosts;
}

/// WebView cookie 写入尝试（url + domain 组合）
class WebViewCookieWriteAttempt {
  const WebViewCookieWriteAttempt({required this.url, required this.domain});

  final String url;
  final String? domain;
}
