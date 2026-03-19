import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../constants.dart';

/// WebView 配置工具类
/// 区分 Headless（后台同步）和 Visible（用户可见页面）两种场景
class WebViewSettings {
  WebViewSettings._();

  /// Windows 触摸板/滚轮 workaround（flutter_inappwebview_windows #2783）
  ///
  /// C++ 层 sendScroll 把 delta 乘以 6 后通过 SendMouseInput(WHEEL) 发给 WebView2，
  /// 但触摸板的小 delta（1~5px）乘以 6 仍远小于 WHEEL_DELTA(120)，被 WebView2 忽略。
  ///
  /// 方案：JS 完全接管滚动 ——
  /// 1. 注入 wheel 事件 preventDefault 阻止 C++ 层产生的重复原生滚动
  /// 2. Flutter Listener 捕获 PointerScrollEvent 后通过 JS 精确设置 scrollTop/scrollLeft
  static const _scrollFixJs = '''
(function(){
  if(window.__fluxdoScrollFix) return;
  window.__fluxdoScrollFix = true;
  window.addEventListener('wheel', function(e){ e.preventDefault(); }, {passive:false});
  window.__fluxdoScroll = function(dx, dy) {
    var el = document.scrollingElement || document.documentElement;
    el.scrollTop += dy;
    el.scrollLeft += dx;
  };
})();
''';

  /// 在 onLoadStop 中调用，为 Windows WebView 注入滚轮补丁
  static Future<void> injectScrollFix(InAppWebViewController controller) async {
    if (!Platform.isWindows) return;
    await controller.evaluateJavascript(source: _scrollFixJs);
  }

  /// 包裹 InAppWebView，在 Windows 上捕获滚轮事件并通过 JS 转发
  static Widget wrapWithScrollFix(
    Widget child, {
    required InAppWebViewController? Function() getController,
  }) {
    if (!Platform.isWindows) return child;
    return _JsonScrollListener(
      getController: getController,
      child: child,
    );
  }

  /// Headless WebView 配置（后台同步用，轻量）
  /// 用于 CookieSyncService、WebViewHttpAdapter、CF 自动验证等
  static InAppWebViewSettings get headless => InAppWebViewSettings(
    javaScriptEnabled: true,
    sharedCookiesEnabled: true,
    userAgent: AppConstants.webViewUserAgentOverride,

    // 性能优化 - 不加载不必要的资源
    blockNetworkImage: true,
    mediaPlaybackRequiresUserGesture: true,
    allowsInlineMediaPlayback: false,

    // 缓存优化
    cacheEnabled: true,
    cacheMode: CacheMode.LOAD_CACHE_ELSE_NETWORK,

    // 禁用不需要的回调以减少开销
    useShouldOverrideUrlLoading: false,
    useShouldInterceptRequest: false,
    useOnLoadResource: false,
    useOnDownloadStart: false,

    // 其他优化
    transparentBackground: true,
    disableContextMenu: true,
    supportZoom: false,

    // 安全相关
    thirdPartyCookiesEnabled: true,
  );

  /// 可见 WebView 配置（登录页、CF 手动验证等，完整功能）
  /// 用于 WebViewLoginPage、CF 手动验证页面等
  static InAppWebViewSettings get visible => InAppWebViewSettings(
    javaScriptEnabled: true,
    sharedCookiesEnabled: true,
    domStorageEnabled: true,
    userAgent: AppConstants.webViewUserAgentOverride,
    isInspectable: true,

    // 保持完整功能
    blockNetworkImage: false,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,

    // 缓存
    cacheEnabled: true,

    // 保持默认回调（可能需要）
    useShouldOverrideUrlLoading: false,

    // 启用下载拦截
    useOnDownloadStart: true,

    // 安全相关
    thirdPartyCookiesEnabled: true,
  );
}

/// Windows 滚轮/触摸板事件转发 widget
class _JsonScrollListener extends StatelessWidget {
  const _JsonScrollListener({
    required this.getController,
    required this.child,
  });

  final InAppWebViewController? Function() getController;
  final Widget child;

  void _doScroll(double dx, double dy) {
    final controller = getController();
    if (controller != null && (dx != 0 || dy != 0)) {
      controller.evaluateJavascript(
        source: 'window.__fluxdoScroll?.($dx,$dy)',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      // 鼠标滚轮
      onPointerSignal: (event) {
        if (event is PointerScrollEvent) {
          _doScroll(event.scrollDelta.dx, event.scrollDelta.dy);
        }
      },
      // 精确触摸板（Precision Touchpad）
      onPointerPanZoomUpdate: (event) {
        _doScroll(-event.panDelta.dx, -event.panDelta.dy);
      },
      child: child,
    );
  }
}
