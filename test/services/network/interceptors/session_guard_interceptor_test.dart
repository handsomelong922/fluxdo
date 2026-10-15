import 'dart:io';

import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/auth_session.dart';
import 'package:fluxdo/services/network/cookie/app_cookie_manager.dart';
import 'package:fluxdo/services/network/interceptors/session_guard_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('新 GET 记录当前代次并绑定会话取消令牌', () {
    final options = RequestOptions(path: 'https://linux.do/latest.json');
    final handler = _RequestHandler();
    SessionGuardInterceptor().onRequest(options, handler);
    expect(handler.forwarded, same(options));
    expect(options.extra['_sessionGeneration'], AuthSession().generation);
    expect(options.cancelToken, same(AuthSession().cancelToken));
  });

  test('切换账号后的旧 GET 重入不能重新标记为新账号', () {
    final session = AuthSession();
    final previousGeneration = session.generation;
    final options = RequestOptions(
      path: 'https://linux.do/latest.json',
      extra: {'_sessionGeneration': previousGeneration},
    );
    session.advance();
    final handler = _RequestHandler();
    SessionGuardInterceptor().onRequest(options, handler);
    expect(handler.forwarded, isNull);
    expect(handler.rejected?.type, DioExceptionType.cancel);
    expect(handler.callFollowingErrorInterceptor, isTrue);
    expect(options.extra['_sessionGeneration'], previousGeneration);
  });

  test('同一账号的 GET 重入仍允许通过', () {
    final options = RequestOptions(
      path: 'https://linux.do/latest.json',
      extra: {'_sessionGeneration': AuthSession().generation},
    );
    final handler = _RequestHandler();
    SessionGuardInterceptor().onRequest(options, handler);
    expect(handler.forwarded, same(options));
    expect(handler.rejected, isNull);
  });

  test('旧账号迟到成功响应被取消，不传给后续响应处理', () {
    final session = AuthSession();
    final options = RequestOptions(
      path: 'https://linux.do/latest.json',
      extra: {'_sessionGeneration': session.generation},
    );
    session.advance();
    final handler = _ResponseHandler();
    SessionGuardInterceptor().onResponse(
      Response(
        requestOptions: options,
        data: {'private': 'previous-account'},
        statusCode: 200,
      ),
      handler,
    );
    expect(handler.forwarded, isNull);
    expect(handler.rejected?.type, DioExceptionType.cancel);
    expect(handler.callFollowingErrorInterceptor, isTrue);
  });

  test('旧账号迟到错误转为取消，仍流经错误链以释放调度资源', () {
    final session = AuthSession();
    final options = RequestOptions(
      path: 'https://linux.do/latest.json',
      extra: {'_sessionGeneration': session.generation},
    );
    session.advance();
    final handler = _ErrorHandler();
    SessionGuardInterceptor().onError(
      DioException(
        requestOptions: options,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: options, statusCode: 403),
      ),
      handler,
    );
    expect(handler.forwarded?.type, DioExceptionType.cancel);
    expect(handler.forwarded?.response, isNull);
  });

  test('CookieManager 独立拒绝旧账号响应的 Set-Cookie', () async {
    final session = AuthSession();
    final uri = Uri.parse('https://linux.do/latest.json');
    final options = RequestOptions(
      path: uri.toString(),
      extra: {'_sessionGeneration': session.generation},
    );
    final jar = CookieJar();
    await jar.saveFromResponse(uri, [Cookie('theme', 'current')..path = '/']);
    session.advance();
    await AppCookieManager(jar).saveCookies(
      Response(
        requestOptions: options,
        statusCode: 200,
        headers: Headers.fromMap({
          'set-cookie': ['theme=previous; Path=/'],
        }),
      ),
    );
    expect((await jar.loadForRequest(uri)).single.value, 'current');
  });
}

class _RequestHandler extends RequestInterceptorHandler {
  RequestOptions? forwarded;
  DioException? rejected;
  bool? callFollowingErrorInterceptor;

  @override
  void next(RequestOptions options) => forwarded = options;

  @override
  void reject(
    DioException error, [
    bool callFollowingErrorInterceptor = false,
  ]) {
    rejected = error;
    this.callFollowingErrorInterceptor = callFollowingErrorInterceptor;
  }
}

class _ResponseHandler extends ResponseInterceptorHandler {
  Response? forwarded;
  DioException? rejected;
  bool? callFollowingErrorInterceptor;

  @override
  void next(Response response) => forwarded = response;

  @override
  void reject(
    DioException error, [
    bool callFollowingErrorInterceptor = false,
  ]) {
    rejected = error;
    this.callFollowingErrorInterceptor = callFollowingErrorInterceptor;
  }
}

class _ErrorHandler extends ErrorInterceptorHandler {
  DioException? forwarded;

  @override
  void next(DioException error) => forwarded = error;
}
