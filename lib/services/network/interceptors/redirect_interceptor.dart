import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../credential_boundary.dart';
import '../flux_request_spec.dart';

/// 重定向拦截器
/// 手动处理 301/302/307/308 及 HEAD 的 303，确保每跳使用正确的 Cookie。
class RedirectInterceptor extends Interceptor {
  RedirectInterceptor(this._dio);

  final Dio _dio;
  static const String _redirectCountKey = '_redirectCount';
  static const int _maxRedirects = 10;

  @override
  Future<void> onResponse(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    // 检查是否跳过重定向处理
    if (response.requestOptions.spec.skipRedirect) {
      return handler.next(response);
    }

    final statusCode = response.statusCode;
    if (statusCode == 301 ||
        statusCode == 302 ||
        (statusCode == 303 && response.requestOptions.method == 'HEAD') ||
        statusCode == 307 ||
        statusCode == 308) {
      final location = response.headers.value('location');
      if (location != null) {
        debugPrint('[Dio] Redirect $statusCode -> $location');

        final redirectCount =
            response.requestOptions.extra[_redirectCountKey] as int? ?? 0;
        if (redirectCount >= _maxRedirects) {
          return handler.reject(
            DioException(
              requestOptions: response.requestOptions,
              response: response,
              type: DioExceptionType.badResponse,
              error: '重定向次数超过上限 $_maxRedirects',
            ),
          );
        }

        // 解析重定向 URL
        final redirectUri = response.requestOptions.uri.resolve(location);
        // 规范化协议大小写后再交给 Dio，保证源判断与实际发送 URL 一致。
        final absoluteUrl = redirectUri.toString();

        // 每一跳重新计算凭据边界，CookieManager 再为目标 URL 加载 Cookie。
        final redirectExtra =
            Map<String, dynamic>.from(response.requestOptions.extra)
              // 当前原请求仍占用调度槽位。内部重定向必须绕过调度器，否则并发槽
              // 和速率窗口会被重定向链自己耗尽，外层响应也无法完成释放。
              ..['skipScheduler'] = true
              ..[_redirectCountKey] = redirectCount + 1;
        final newOptions =
            Options(
                method: response.requestOptions.method,
                extra: redirectExtra,
                responseType: response.requestOptions.responseType,
                validateStatus: response.requestOptions.validateStatus,
                followRedirects: false,
              ).compose(_dio.options, absoluteUrl)
              // Location 已给出目标查询串，不能再次并入起始请求的默认参数。
              ..queryParameters.clear()
              // compose 会合并 Dio 的默认头；必须在合并后清理，避免把默认
              // Authorization / Cookie 重新带到跨源目标。
              ..headers = redirectRequestHeaders(
                response.requestOptions.headers,
                source: response.requestOptions.uri,
                target: redirectUri,
              );

        try {
          final redirectResponse = await _dio.fetch(newOptions);
          return handler.resolve(redirectResponse);
        } catch (e) {
          if (e is DioException) {
            return handler.reject(e);
          }
          rethrow;
        }
      }
    }
    handler.next(response);
  }
}
