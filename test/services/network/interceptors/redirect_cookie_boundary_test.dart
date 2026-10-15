import 'dart:io';
import 'dart:typed_data';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';
import 'package:fluxdo/services/network/interceptors/redirect_interceptor.dart';

/// 使用真实 CookieJar 和 Dio 拦截器，适配器仅记录请求并返回受控响应。
/// 不覆盖平台网络适配器、WebView 内部跳转或下载文件写入。
void main() {
  for (final (method, path, responseType) in [
    ('GET', '/latest.json', ResponseType.plain),
    ('GET', '/uploads/secure-uploads/image.png', ResponseType.bytes),
    ('HEAD', '/uploads/attachment.pdf', ResponseType.plain),
  ]) {
    test('$method $path 跳转后重取目标 Cookie，不转发原论坛会话', () async {
      final jar = CookieJar();
      await jar.saveFromResponse(Uri.parse('https://linux.do'), [
        Cookie('_t', 'forum-session')..secure = true,
      ]);
      await jar.saveFromResponse(Uri.parse('https://cdn.example'), [
        Cookie('target_session', 'cdn-session')..secure = true,
      ]);
      final adapter = _RedirectAdapter('https://cdn.example/file');
      final dio = _dio(jar, adapter);
      final response = await dio.request(
        path,
        options: Options(method: method, responseType: responseType),
      );
      expect(response.statusCode, 200);
      expect(adapter.requests, hasLength(2));
      expect(_cookies(adapter.requests.first), contains('_t=forum-session'));
      expect(_cookies(adapter.requests.last), 'target_session=cdn-session');
      expect(adapter.requests.last.method, method);
      expect(adapter.requests.last.followRedirects, isFalse);
      expect(
        response.headers.value('content-disposition'),
        'attachment; filename="file.pdf"',
      );
    });
  }

  for (final persistent in [false, true]) {
    final jarName = persistent ? '增强持久 jar' : '内存回退 jar';
    test('HTTPS 降到 HTTP 时 Secure Cookie 不从 $jarName 重装', () async {
      final CookieJar jar;
      if (persistent) {
        final directory = await Directory.systemTemp.createTemp(
          'redirect_cookie_boundary_',
        );
        addTearDown(() => directory.delete(recursive: true));
        jar = EnhancedPersistCookieJar(store: FileCookieStore(directory.path));
      } else {
        jar = CookieJar();
      }
      await jar.saveFromResponse(Uri.parse('https://linux.do'), [
        Cookie('_t', 'secure-session')..secure = true,
      ]);
      final adapter = _RedirectAdapter('http://linux.do/final');
      await _dio(jar, adapter).get('/start');
      expect(adapter.requests, hasLength(2));
      expect(adapter.requests.last.uri.scheme, 'http');
      expect(_cookies(adapter.requests.first), contains('_t=secure-session'));
      expect(_cookies(adapter.requests.last), isEmpty);
    });
  }

  test('附件 HEAD 的 303 仍以 HEAD 获取最终文件名', () async {
    final adapter = _RedirectAdapter('https://cdn.example/file', status: 303);
    final response = await _dio(CookieJar(), adapter).head('/attachment');
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.method, 'HEAD');
    expect(response.statusCode, 200);
    expect(
      response.headers.value('content-disposition'),
      'attachment; filename="file.pdf"',
    );
  });

  test('新增 HEAD 303 支持不改变写请求的既有行为', () async {
    final adapter = _RedirectAdapter('https://cdn.example/file', status: 303);
    final response = await _dio(
      CookieJar(),
      adapter,
    ).post('/posts', data: 'body');
    expect(adapter.requests, hasLength(1));
    expect(response.statusCode, 303);
  });
}

Dio _dio(CookieJar jar, _RedirectAdapter adapter) {
  final dio = Dio(
    BaseOptions(
      baseUrl: 'https://linux.do',
      followRedirects: false,
      validateStatus: (status) => status != null && status < 400,
    ),
  )..httpClientAdapter = adapter;
  dio.interceptors
    ..add(AppCookieManager(jar))
    ..add(RedirectInterceptor(dio));
  return dio;
}

String _cookies(RequestOptions options) {
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == 'cookie')
      return entry.value?.toString() ?? '';
  }
  return '';
}

class _RedirectAdapter implements HttpClientAdapter {
  _RedirectAdapter(this.location, {this.status = 302});
  final String location;
  final int status;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requests.length == 1) {
      return ResponseBody.fromString(
        '',
        status,
        headers: {
          'location': [location],
        },
      );
    }
    return ResponseBody.fromString(
      '',
      200,
      headers: {
        'content-disposition': ['attachment; filename="file.pdf"'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
