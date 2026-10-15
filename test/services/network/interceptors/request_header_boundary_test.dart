import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/csrf_token_service.dart';
import 'package:fluxdo/services/network/interceptors/redirect_interceptor.dart';
import 'package:fluxdo/services/network/interceptors/request_header_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final csrf = CsrfTokenService();

  setUp(() => csrf.setCsrfToken('forum-token-for-test'));
  tearDown(csrf.clearCsrfToken);

  test('同源 API 保留 CSRF，显式 skipCsrf 保留同源调用方的 token', () async {
    final adapter = _RecordingAdapter();
    final dio = _dio(csrf, adapter);
    await dio.get('/latest.json');
    await dio.post(
      '/posts.json',
      options: Options(
        headers: {'X-CSRF-Token': 'caller-token'},
        extra: {'skipCsrf': true},
      ),
    );
    expect(_csrfHeader(adapter.requests[0]), 'forum-token-for-test');
    expect(_csrfHeader(adapter.requests[1]), 'caller-token');
  });

  for (final target in [
    'https://cdn.example/image.png',
    'https://auth.linux.do/resource',
    'http://linux.do/resource',
    'https://linux.do:8443/resource',
    'https://linux.do@cdn.example/resource',
    'https://other@linux.do/resource',
  ]) {
    test('直接请求 $target 不携带论坛 CSRF', () async {
      final adapter = _RecordingAdapter();
      final dio = _dio(csrf, adapter);
      await dio.get(target);
      await dio.get(
        target,
        options: Options(
          headers: {
            'x-CsRf-ToKeN': 'copied-forum-token',
            'Authorization': 'Bearer independent-api-token',
          },
          extra: {'skipCsrf': true},
        ),
      );
      expect(adapter.requests.every((r) => _csrfHeader(r) == null), isTrue);
      expect(
        adapter.requests.last.headers['Authorization'],
        'Bearer independent-api-token',
        reason: '直接调用的独立 API 凭证不属于论坛 CSRF 守卫',
      );
    });
  }

  test('无论坛 CSRF 时第三方 POST 不触发论坛刷新或被取消', () async {
    csrf.clearCsrfToken();
    final adapter = _RecordingAdapter();
    final response = await _dio(csrf, adapter).post('https://api.example/data');
    expect(response.statusCode, 200);
    expect(adapter.requests, hasLength(1));
    expect(_csrfHeader(adapter.requests.single), isNull);
  });

  test('图片从主站重定向到 CDN 时不会重新注入论坛 CSRF', () async {
    final adapter = _RecordingAdapter(
      redirect: 'https://cdn.example/image.png',
    );
    final dio = _dio(csrf, adapter);
    dio.interceptors.add(RedirectInterceptor(dio));
    await dio.get('/uploads/secure-uploads/image.png');
    expect(adapter.requests, hasLength(2));
    expect(_csrfHeader(adapter.requests.first), 'forum-token-for-test');
    expect(_csrfHeader(adapter.requests.last), isNull);
  });
}

Dio _dio(CsrfTokenService csrf, _RecordingAdapter adapter) {
  return Dio(
      BaseOptions(
        baseUrl: 'https://linux.do',
        followRedirects: false,
        validateStatus: (status) => status != null && status < 400,
      ),
    )
    ..httpClientAdapter = adapter
    ..interceptors.add(RequestHeaderInterceptor(csrf));
}

Object? _csrfHeader(RequestOptions options) {
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == 'x-csrf-token') return entry.value;
  }
  return null;
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter({this.redirect});
  final String? redirect;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (requests.length == 1 && redirect != null) {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': [redirect!],
        },
      );
    }
    return ResponseBody.fromString(
      '{}',
      200,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
