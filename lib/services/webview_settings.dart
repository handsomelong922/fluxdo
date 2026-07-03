import 'dart:async';
import 'dart:collection' show UnmodifiableListView;
import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../constants.dart';
import 'eruda_settings_service.dart';
import 'log/log_writer.dart';
import 'log/runtime_log_settings.dart';
import 'network/doh/network_settings_service.dart';

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
    return _JsonScrollListener(getController: getController, child: child);
  }

  /// Gateway 模式下 WebView 的 SSL 信任回调
  ///
  /// 代理做 MITM 时会用自签 CA 签发证书，WKWebView/WebView 不信任它。
  /// 仅在本地代理网关模式运行时放行，其他情况走系统默认验证。
  static Future<ServerTrustAuthResponse?> handleServerTrustAuthRequest(
    URLAuthenticationChallenge challenge,
  ) async {
    // Android/macOS: gateway MITM 模式下放行代理 CA 证书。
    // iOS: 使用隧道模式（非 MITM），不会触发代理 CA 信任问题。
    if (NetworkSettingsService.instance.isGatewayMode) {
      return ServerTrustAuthResponse(
        action: ServerTrustAuthResponseAction.PROCEED,
      );
    }
    return null;
  }

  /// Headless WebView 配置（后台同步用，轻量）
  /// 用于 CsrfTokenService、WebViewHttpAdapter、会话 bootstrap 等
  static InAppWebViewSettings get headless => InAppWebViewSettings(
    javaScriptEnabled: true,
    sharedCookiesEnabled: true,
    userAgent: AppConstants.webViewUserAgentOverride,

    // 性能优化 - 不加载不必要的资源
    blockNetworkImage: true,
    loadsImagesAutomatically: false,
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
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableVerticalScroll: true,
    disableHorizontalScroll: true,
    supportZoom: false,

    // 安全相关
    thirdPartyCookiesEnabled: true,
  );

  /// Headless WebView 配置（CF/Turnstile 用）。
  ///
  /// CF 相关页面更看重浏览器环境接近默认行为，因此这里不禁图片、也不强制
  /// LOAD_CACHE_ELSE_NETWORK；资源占用主要交给 WebView2 memory target 处理。
  static InAppWebViewSettings get headlessCf => InAppWebViewSettings(
    javaScriptEnabled: true,
    sharedCookiesEnabled: true,
    userAgent: AppConstants.webViewUserAgentOverride,

    // 这些开关只影响 WebView 插件回调，不改变页面可见能力。
    useShouldOverrideUrlLoading: false,
    useShouldInterceptRequest: false,
    useOnLoadResource: false,
    useOnDownloadStart: false,

    transparentBackground: true,
    disableContextMenu: true,
    verticalScrollBarEnabled: false,
    horizontalScrollBarEnabled: false,
    disableVerticalScroll: true,
    disableHorizontalScroll: true,
    supportZoom: false,

    thirdPartyCookiesEnabled: true,
  );

  /// Windows WebView2 后台实例使用低内存目标。
  ///
  /// 该 API 只在支持 ICoreWebView2_19 的 Runtime 生效；旧 Runtime 会由插件
  /// native 层 no-op。这里异步 fire-and-forget，避免影响 WebView 创建流程。
  static void applyWindowsHeadlessMemoryTarget(
    InAppWebViewController controller,
  ) {
    if (!Platform.isWindows) return;
    unawaited(() async {
      try {
        await controller.setMemoryUsageTargetLevel(MemoryUsageTargetLevel.LOW);
      } catch (e) {
        debugPrint('[WebViewSettings] 设置 WebView2 低内存目标失败: $e');
      }
    }());
  }

  /// 老 WKWebView 兼容性脚本：core-js polyfill + Discourse 兼容补丁 + JS 错误回传。
  static const _polyfillAssetPath = 'assets/polyfill/compat-polyfill.js';
  static UnmodifiableListView<UserScript>? _compatPolyfillScripts;
  static bool _polyfillLoadAttempted = false;

  /// 启动期调用一次，把 asset 内容读入内存。
  static Future<void> preloadPolyfill() async {
    if (_polyfillLoadAttempted) return;
    _polyfillLoadAttempted = true;
    try {
      final source = await rootBundle.loadString(_polyfillAssetPath);
      _compatPolyfillScripts = UnmodifiableListView([
        UserScript(
          source: source,
          injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
          // es-module-shims 会创建 about:blank iframe 评估模块。若每个 iframe
          // 都注入这份 polyfill，会把 native bridge 和主线程压满。
          // 业务与 Discourse boot 只需要 main frame 注入。
          forMainFrameOnly: true,
        ),
      ]);
    } catch (e) {
      debugPrint(
        '[WebViewSettings] 加载 compat polyfill asset 失败: $e。'
        '请确认已运行 `cd tools/polyfill-bundle && pnpm build`。',
      );
      _compatPolyfillScripts = UnmodifiableListView<UserScript>([]);
      LogWriter.instance.write({
        'timestamp': DateTime.now().toIso8601String(),
        'level': 'error',
        'type': 'webview',
        'event': 'compat_polyfill_load_failed',
        'message': '加载 compat polyfill asset 失败',
        'asset': _polyfillAssetPath,
        'error': e.toString(),
      });
    }
  }

  /// Eruda 默认关闭时注入的禁用脚本：在 polyfill 之前抢先设置 guard，
  /// 让 bundle 内 eruda-init 跳过初始化。
  static final UserScript _erudaDisableScript = UserScript(
    source: 'window.__fluxdoErudaInited = true;',
    injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
    forMainFrameOnly: true,
  );

  /// 兼容性脚本列表，传给 InAppWebView.initialUserScripts。
  ///
  /// Eruda 开关关闭时（默认）会在 polyfill 前追加禁用脚本；打开时原样返回，
  /// 让 bundle 内 Eruda 在主页面初始化。
  static UnmodifiableListView<UserScript> get compatPolyfillScripts {
    final cached = _compatPolyfillScripts;
    if (cached == null) {
      if (!_polyfillLoadAttempted) {
        debugPrint(
          '[WebViewSettings] compatPolyfillScripts 在 preloadPolyfill() 完成前被读取，'
          '老 WebView 兼容性会缺失。请检查 main.dart 初始化序列。',
        );
      }
      return UnmodifiableListView<UserScript>([]);
    }
    if (!ErudaSettingsService.instance.enabled) {
      return UnmodifiableListView<UserScript>([_erudaDisableScript, ...cached]);
    }
    return cached;
  }

  /// 注册 JS 错误 / lifecycle 回传 handler，把 WebView 内的事件落到 LogWriter。
  static void registerJsErrorReporter(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: 'onWebViewJsError',
      callback: (args) {
        if (args.isEmpty) return null;
        try {
          final raw = args[0];
          if (raw is! Map) return null;
          final data = Map<String, dynamic>.from(raw);
          final source = data['source']?.toString() ?? 'unknown';

          if (source == 'lifecycle') {
            final message =
                data['message']?.toString() ?? 'compat_bundle_loaded';
            if (!RuntimeLogSettings.persistVerboseDiagnostics) {
              return null;
            }
            LogWriter.instance.write({
              'timestamp': DateTime.now().toIso8601String(),
              'level': 'info',
              'type': 'webview_compat',
              'event': message,
              'message': message,
              'probes': data['probes'],
              'missing': data['missing'],
              'stage': data['stage'],
              'stages': data['stages'],
              'extra': data['extra'],
              'hasSplash': data['hasSplash'],
              'pageUrl': data['url'],
              'pageUa': data['ua'],
              'platform': Platform.operatingSystem,
              'platformVersion': Platform.operatingSystemVersion,
            });
          } else {
            LogWriter.instance.write({
              'timestamp': DateTime.now().toIso8601String(),
              'level': 'error',
              'type': 'webview_js',
              'event': 'js_runtime_error',
              'message': data['message']?.toString() ?? 'unknown',
              'jsSource': source,
              'jsFilename': data['filename'],
              'jsLineno': data['lineno'],
              'jsColno': data['colno'],
              'jsStack': data['stack'],
              'jsEventType': data['eventType'],
              'jsTargetTag': data['targetTag'],
              'jsTargetSrc': data['targetSrc'],
              'pageUrl': data['url'],
              'pageUa': data['ua'],
              'platform': Platform.operatingSystem,
              'platformVersion': Platform.operatingSystemVersion,
            });
          }
        } catch (_) {}
        return null;
      },
    );
  }

  /// 可见 WebView 配置（登录页、CF 手动验证等，完整功能）
  /// 用于 WebViewLoginPage、CF 手动验证页面等
  static InAppWebViewSettings get visible => InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: true,
    sharedCookiesEnabled: true,
    domStorageEnabled: true,
    databaseEnabled: true,
    userAgent: AppConstants.webViewUserAgentOverride,
    isInspectable: true,
    incognito: false,

    // 保持完整功能
    blockNetworkImage: false,
    mediaPlaybackRequiresUserGesture: false,
    allowsInlineMediaPlayback: true,

    // 缓存
    cacheEnabled: true,
    cacheMode: CacheMode.LOAD_DEFAULT,

    // 保持默认回调（可能需要）
    useShouldOverrideUrlLoading: false,

    // 启用下载拦截
    useOnDownloadStart: true,

    // 安全相关
    thirdPartyCookiesEnabled: true,

    // 依赖系统/WebView profile 保存第三方登录会话与凭证建议，不在应用内采集第三方密码。
    generalAutofillEnabled: true,
    passwordAutosaveEnabled: true,
  );

  /// 登录 WebView 配置。
  ///
  /// 第三方登录常见的 `window.open`/弹窗跳转需要多窗口支持；
  /// 只在登录页打开，避免影响普通内置浏览器和 CF 后台验证。
  static InAppWebViewSettings get login => visible
    ..supportMultipleWindows = true
    ..useShouldOverrideUrlLoading = true;
}

/// Windows 滚轮/触摸板事件转发 widget
class _JsonScrollListener extends StatelessWidget {
  const _JsonScrollListener({required this.getController, required this.child});

  final InAppWebViewController? Function() getController;
  final Widget child;

  void _doScroll(double dx, double dy) {
    final controller = getController();
    if (controller != null && (dx != 0 || dy != 0)) {
      controller.evaluateJavascript(source: 'window.__fluxdoScroll?.($dx,$dy)');
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
