import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/interceptors/redirect_interceptor.dart';

void main() {
  for (final location in [
    'https://cdn.example/final',
    'https://cdn.example/final?download=1',
    '//cdn.example/final',
    'http://linux.do/final',
    'https://linux.do:8443/final',
    'https://linux.do@cdn.example/final',
    'https://other@linux.do/final',
  ]) {
    test('重定向到 $location 不转发默认或请求级认证头', () async {
      final adapter = _RedirectOnceAdapter(location: location);
      final dio = Dio(
        BaseOptions(
          baseUrl: 'https://linux.do',
          followRedirects: false,
          headers: {
            'Authorization': 'Bearer default-token',
            'COOKIE': 'default',
          },
          queryParameters: {'private_parameter': 'original-only'},
          validateStatus: (status) => status != null && status < 400,
        ),
      )..httpClientAdapter = adapter;
      dio.interceptors.add(RedirectInterceptor(dio));
      await dio.get(
        '/file',
        options: Options(
          headers: {
            'x-CsRf-ToKeN': 'forum-token',
            'User-Api-Key': 'user-token',
            'Range': 'bytes=0-99',
          },
        ),
      );
      final target = adapter.requests.last;
      for (final name in [
        'cookie',
        'authorization',
        'x-csrf-token',
        'user-api-key',
      ]) {
        expect(
          target.headers.entries.where((e) => e.key.toLowerCase() == name),
          isEmpty,
          reason: '不能因重新合并 BaseOptions 带回 $name',
        );
      }
      expect(target.headers['Range'], 'bytes=0-99');
      expect(target.followRedirects, isFalse);
      expect(target.queryParameters, isEmpty);
      expect(
        target.uri.queryParameters.containsKey('private_parameter'),
        isFalse,
      );
      expect(
        target.uri.queryParameters['download'],
        Uri.parse(location).queryParameters['download'],
      );
    });
  }

  test('相对同源重定向保留认证但移除混合大小写 Cookie', () async {
    final adapter = _RedirectOnceAdapter(location: '../final');
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://linux.do',
        validateStatus: (status) => status != null && status < 400,
      ),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(RedirectInterceptor(dio));
    await dio.get(
      '/files/start',
      options: Options(
        headers: {
          'Authorization': 'Bearer same-origin-token',
          'cOoKiE': 'old-cookie',
          'X-CSRF-Token': 'forum-token',
        },
      ),
    );
    final target = adapter.requests.last;
    expect(target.uri.toString(), 'https://linux.do/final');
    expect(target.headers['Authorization'], 'Bearer same-origin-token');
    expect(target.headers['X-CSRF-Token'], 'forum-token');
    expect(
      target.headers.entries.where((e) => e.key.toLowerCase() == 'cookie'),
      isEmpty,
    );
  });

  test('大写协议先规范化，认证头判断与真实目标 URL 一致', () async {
    final adapter = _RedirectOnceAdapter(location: 'HTTPS://linux.do/final');
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://linux.do',
        validateStatus: (status) => status != null && status < 400,
        headers: {'Authorization': 'Bearer same-origin-token'},
      ),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(RedirectInterceptor(dio));
    await dio.get('/start');
    expect(adapter.requests.last.uri.toString(), 'https://linux.do/final');
    expect(
      adapter.requests.last.headers['Authorization'],
      'Bearer same-origin-token',
    );
  });

  test('内部重定向绕过调度器并保留原请求计数标记', () async {
    final adapter = _RedirectOnceAdapter();
    final requestExtras = <Map<String, dynamic>>[];
    final dio = Dio(
      BaseOptions(
        baseUrl: 'https://linux.do',
        validateStatus: (status) => status != null && status < 400,
      ),
    )..httpClientAdapter = adapter;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestExtras.add(Map<String, dynamic>.from(options.extra));
          handler.next(options);
        },
      ),
    );
    dio.interceptors.add(RedirectInterceptor(dio));

    final response = await dio.get(
      '/',
      options: Options(extra: {'_schedulerCounted': true}),
    );

    expect(response.statusCode, 200);
    expect(adapter.fetchCount, 2);
    expect(requestExtras, hasLength(2));
    expect(requestExtras.last['skipScheduler'], isTrue);
    expect(requestExtras.last['_redirectCount'], 1);
    expect(requestExtras.last['_schedulerCounted'], isTrue);
  });
}

class _RedirectOnceAdapter implements HttpClientAdapter {
  _RedirectOnceAdapter({this.location = 'https://linux.do/final'});
  final String location;
  int fetchCount = 0;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    requests.add(options);
    if (fetchCount == 1) {
      return ResponseBody.fromString(
        '',
        301,
        headers: {
          'location': [location],
        },
      );
    }
    return ResponseBody.fromString(
      '{"ok":true}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
