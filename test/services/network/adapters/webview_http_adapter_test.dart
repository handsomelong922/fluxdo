import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/adapters/webview_http_adapter.dart';

void main() {
  group('WebViewHttpAdapter.resolveFetchCacheMode', () {
    RequestOptions buildOptions(String method, {Map<String, dynamic>? extra}) {
      return RequestOptions(
        path: '/latest.json',
        baseUrl: 'https://linux.do',
        method: method,
        extra: extra ?? <String, dynamic>{},
      );
    }

    test('GET 请求默认禁用浏览器缓存', () {
      final options = buildOptions('GET');

      expect(
        WebViewHttpAdapter.resolveFetchCacheMode(options),
        WebViewHttpAdapter.defaultApiFetchCacheMode,
      );
    });

    test('HEAD 请求默认禁用浏览器缓存', () {
      final options = buildOptions('HEAD');

      expect(
        WebViewHttpAdapter.resolveFetchCacheMode(options),
        WebViewHttpAdapter.defaultApiFetchCacheMode,
      );
    });

    test('非 GET/HEAD 请求默认不设置 cache 模式', () {
      final options = buildOptions('POST');

      expect(WebViewHttpAdapter.resolveFetchCacheMode(options), isNull);
    });

    test('支持通过 extra 覆盖 fetch cache 模式', () {
      final options = buildOptions(
        'GET',
        extra: {WebViewHttpAdapter.fetchCacheModeExtraKey: 'reload'},
      );

      expect(WebViewHttpAdapter.resolveFetchCacheMode(options), 'reload');
    });

    test('不支持的 cache 模式会回退到默认策略', () {
      final options = buildOptions(
        'GET',
        extra: {WebViewHttpAdapter.fetchCacheModeExtraKey: 'invalid-mode'},
      );

      expect(
        WebViewHttpAdapter.resolveFetchCacheMode(options),
        WebViewHttpAdapter.defaultApiFetchCacheMode,
      );
    });
  });

  group('WebViewHttpAdapter.trustsWebViewSessionFromResponse', () {
    RequestOptions buildOptions({Map<String, dynamic>? headers}) {
      return RequestOptions(
        path: '/session/current.json',
        baseUrl: 'https://linux.do',
        method: 'GET',
        headers: headers ?? <String, dynamic>{},
      );
    }

    test('登录态成功响应会信任 WebView session', () {
      final options = buildOptions(headers: {'Discourse-Logged-In': 'true'});

      expect(
        WebViewHttpAdapter.trustsWebViewSessionFromResponse(
          options,
          200,
          const {},
        ),
        isTrue,
      );
    });

    test('带 discourse-logged-out 头的响应不会信任 WebView session', () {
      final options = buildOptions(headers: {'Discourse-Logged-In': 'true'});

      expect(
        WebViewHttpAdapter.trustsWebViewSessionFromResponse(
          options,
          200,
          const {
            'discourse-logged-out': ['1'],
          },
        ),
        isFalse,
      );
    });

    test('未声明已登录的请求不会信任 WebView session', () {
      final options = buildOptions();

      expect(
        WebViewHttpAdapter.trustsWebViewSessionFromResponse(
          options,
          200,
          const {},
        ),
        isFalse,
      );
    });
  });
}
