import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants.dart';
import 'discourse/discourse_service.dart';
import 'network/cookie/cookie_jar_service.dart';
import 'preloaded_data_service.dart';
import 'webview_settings.dart';
import 'windows_webview_environment_service.dart';

/// 浏览器指纹采集与上报服务
///
/// 通过 Dio 获取 linux.do 页面 HTML，注入 XHR hook 后交给
/// HeadlessInAppWebView 执行，拦截 FingerprintJS 的上报请求
/// 获取动态端点路径和指纹数据，缓存后通过 Dio 上报。
class FingerprintService {
  static final FingerprintService instance = FingerprintService._();
  FingerprintService._();

  // SharedPreferences 存储键
  static const String _prefEndpoint = 'fingerprint_endpoint';
  static const String _prefBody = 'fingerprint_body';

  // 缓存的上报数据
  String? _endpoint;
  String? _body;

  // 采集状态
  bool _isCollecting = false;

  /// 是否已有缓存的指纹数据
  bool get hasCachedFingerprint => _endpoint != null && _body != null;

  /// 从本地存储加载缓存的指纹
  Future<void> loadCached() async {
    final prefs = await SharedPreferences.getInstance();
    _endpoint = prefs.getString(_prefEndpoint);
    _body = prefs.getString(_prefBody);
    if (hasCachedFingerprint) {
      debugPrint('[Fingerprint] 已加载缓存: endpoint=$_endpoint');
    }
  }

  /// 保存到本地存储
  Future<void> _saveCached() async {
    if (!hasCachedFingerprint) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefEndpoint, _endpoint!);
    await prefs.setString(_prefBody, _body!);
  }

  /// 采集指纹：Dio 获取页面 HTML → 注入 XHR hook → HeadlessInAppWebView 执行
  Future<bool> collect() async {
    if (_isCollecting) return false;
    _isCollecting = true;
    debugPrint('[Fingerprint] 开始采集');

    try {
      // 1. 优先复用 PreloadedDataService 缓存的 HTML，避免额外网络请求
      var html = PreloadedDataService().consumeCachedHtml();
      if (html == null) {
        html = await _fetchPageHtml();
      }
      if (html == null) {
        debugPrint('[Fingerprint] 获取页面 HTML 失败');
        return false;
      }

      // 2. 注入 XHR hook
      final injectedHtml = _injectXhrHook(html);

      // 3. HeadlessInAppWebView 加载并执行
      return await _runHeadless(injectedHtml);
    } catch (e) {
      debugPrint('[Fingerprint] 采集异常: $e');
      return false;
    } finally {
      _isCollecting = false;
    }
  }

  /// 上报指纹到服务端
  Future<bool> report() async {
    if (!hasCachedFingerprint) {
      final collected = await collect();
      if (!collected) return false;
    }

    try {
      final tToken = await CookieJarService().getTToken();
      if (tToken == null || tToken.isEmpty) return false;

      debugPrint('[Fingerprint] 上报: $_endpoint');
      await DiscourseService().postFingerprint(
        endpoint: _endpoint!,
        body: _body!,
      );
      debugPrint('[Fingerprint] 上报成功');
      return true;
    } on DioException catch (e) {
      debugPrint('[Fingerprint] 上报失败: ${e.response?.statusCode} '
          'url=${e.requestOptions.uri} '
          'body=${e.response?.data}');
      return false;
    } catch (e) {
      debugPrint('[Fingerprint] 上报异常: $e');
      return false;
    }
  }

  /// 采集并上报
  Future<void> collectAndReport() async {
    if (!hasCachedFingerprint) {
      await collect();
    }
    await report();
  }

  /// 用 Dio 获取 linux.do 首页 HTML
  Future<String?> _fetchPageHtml() async {
    try {
      final dio = DiscourseService().dio;
      final response = await dio.get(
        '/',
        options: Options(
          headers: {
            'Accept': 'text/html',
            // 不发送 X-Requested-With，让服务端返回完整 HTML 而非 JSON
          },
          extra: const {
            'skipAuthCheck': true,
            'skipCsrf': true,
            'isSilent': true,
          },
          responseType: ResponseType.plain,
        ),
      );
      return response.data?.toString();
    } catch (e) {
      debugPrint('[Fingerprint] 获取 HTML 失败: $e');
      return null;
    }
  }

  /// 在 HTML 的 <head> 后注入 XHR hook 脚本
  String _injectXhrHook(String html) {
    // 匹配 fingerprint 请求：body 包含 visitor_id= 且包含指纹特征字段 "fonts"
    const hookScript = '''
<script>
(function() {
  function isFingerprintBody(body) {
    if (!body || typeof body !== 'string') return false;
    if (body.indexOf('visitor_id=') === -1) return false;
    return body.indexOf('%22fonts%22') !== -1 || body.indexOf('"fonts"') !== -1;
  }
  function isMessageBus(url) {
    return url && url.indexOf('/message-bus/') !== -1;
  }
  function notify(url, body) {
    try {
      window.flutter_inappwebview.callHandler('onFingerprintRequest', {
        url: url, body: body
      });
    } catch(e) {}
  }

  // Hook XMLHttpRequest
  var origOpen = XMLHttpRequest.prototype.open;
  var origSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.open = function(method, url) {
    this._fpMethod = method;
    this._fpUrl = url;
    return origOpen.apply(this, arguments);
  };
  XMLHttpRequest.prototype.send = function(body) {
    if (isMessageBus(this._fpUrl)) return;
    if (this._fpMethod === 'POST' && isFingerprintBody(body)) {
      notify(this._fpUrl, body);
      return;
    }
    return origSend.apply(this, arguments);
  };

  // Hook fetch
  var origFetch = window.fetch;
  window.fetch = function(input, init) {
    var url = typeof input === 'string' ? input : (input && input.url || '');
    if (isMessageBus(url)) return Promise.resolve(new Response('[]', {status: 200}));
    if (init && init.method && init.method.toUpperCase() === 'POST' && init.body) {
      var body = typeof init.body === 'string' ? init.body : '';
      if (!body && init.body instanceof URLSearchParams) {
        body = init.body.toString();
      }
      if (isFingerprintBody(body)) {
        notify(url, body);
        return Promise.resolve(new Response('{}', {status: 200}));
      }
    }
    return origFetch.apply(this, arguments);
  };
})();
</script>
''';
    // 在 <head> 后注入，确保 hook 在所有脚本之前生效
    final headIndex = html.indexOf('<head>');
    if (headIndex != -1) {
      return html.substring(0, headIndex + 6) +
          hookScript +
          html.substring(headIndex + 6);
    }
    // 兜底：直接拼接到开头
    return hookScript + html;
  }

  /// 运行 HeadlessInAppWebView 执行采集
  Future<bool> _runHeadless(String html) async {
    final completer = Completer<bool>();

    // 超时保护
    final timer = Timer(const Duration(seconds: 20), () {
      if (!completer.isCompleted) {
        debugPrint('[Fingerprint] 采集超时');
        completer.complete(false);
      }
    });

    final webView = HeadlessInAppWebView(
      webViewEnvironment:
          WindowsWebViewEnvironmentService.instance.environment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: AppConstants.webViewUserAgentOverride,
      ),
      onReceivedServerTrustAuthRequest: (_, challenge) =>
          WebViewSettings.handleServerTrustAuthRequest(challenge),
      onWebViewCreated: (controller) {
        controller.addJavaScriptHandler(
          handlerName: 'onFingerprintRequest',
          callback: (args) {
            if (args.isNotEmpty && args[0] is Map) {
              final result = args[0] as Map;
              final url = result['url']?.toString();
              final body = result['body']?.toString();

              if (url != null && url.isNotEmpty &&
                  body != null && body.isNotEmpty) {
                // 提取相对路径作为 endpoint
                _endpoint = url.startsWith('http')
                    ? Uri.tryParse(url)?.path ?? url
                    : url;
                _body = body;

                debugPrint('[Fingerprint] 拦截成功: endpoint=$_endpoint');
                unawaited(_saveCached());
                if (!completer.isCompleted) completer.complete(true);
              }
            }
            return null;
          },
        );
      },
      onReceivedError: (controller, request, error) {
        debugPrint('[Fingerprint] WebView 资源加载错误: ${error.description}');
      },
    );

    try {
      await webView.run();
      await webView.webViewController?.loadData(
        data: html,
        baseUrl: WebUri(AppConstants.baseUrl),
        mimeType: 'text/html',
        encoding: 'utf-8',
      );

      final success = await completer.future;
      timer.cancel();

      try {
        await webView.dispose();
      } catch (_) {}

      return success;
    } catch (e) {
      timer.cancel();
      try {
        await webView.dispose();
      } catch (_) {}
      rethrow;
    }
  }
}
