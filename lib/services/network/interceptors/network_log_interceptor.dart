import 'package:dio/dio.dart';

import '../../log/log_writer.dart';
import '../../log/runtime_log_settings.dart';
import '../adapters/adapter_log_metadata.dart';
import '../startup_request_recorder.dart';

/// 网络请求日志拦截器，记录每个请求的 method/url/statusCode/duration
class NetworkLogInterceptor extends Interceptor {
  static const String _startTimeKey = '_networkLog_startTime';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[_startTimeKey] = DateTime.now().millisecondsSinceEpoch;
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _logRequest(
      options: response.requestOptions,
      statusCode: response.statusCode,
      level: 'info',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final isSilent = err.requestOptions.extra['isSilent'] == true;
    final isTimeout =
        err.type == DioExceptionType.receiveTimeout ||
        err.type == DioExceptionType.connectionTimeout ||
        err.type == DioExceptionType.sendTimeout;

    // cancel: 长轮询频繁 cancel 是正常行为，记录为 debug
    // isSilent + 超时: MessageBus 长轮询超时是正常行为，记录为 debug
    // 其他错误: 记录为 warning
    final level =
        (err.type == DioExceptionType.cancel || (isSilent && isTimeout))
        ? 'debug'
        : 'warning';

    _logRequest(
      options: err.requestOptions,
      statusCode: err.response?.statusCode,
      level: level,
      errorType: err.type.name,
    );
    handler.next(err);
  }

  void _logRequest({
    required RequestOptions options,
    required int? statusCode,
    required String level,
    String? errorType,
  }) {
    final startTime = options.extra[_startTimeKey] as int?;
    final duration = startTime != null
        ? DateTime.now().millisecondsSinceEpoch - startTime
        : null;

    // URL 脱敏：不记录查询参数
    final uri = options.uri;
    final path = uri.path.isEmpty ? '/' : uri.path;
    final sanitizedUrl = '${uri.scheme}://${uri.host}$path';
    final priority = options.extra['priority']?.toString();
    final isSilent = options.extra['isSilent'] == true;
    final adapterName = getRequestAdapterLogName(options);
    final record = StartupRequestRecorder.instance.record(
      startedAtMillis: startTime,
      durationMs: duration,
      method: options.method,
      url: sanitizedUrl,
      path: path,
      statusCode: statusCode,
      level: level,
      priority: priority,
      isSilent: isSilent,
      networkAdapter: adapterName,
      errorType: errorType,
    );

    final entry = <String, dynamic>{
      'timestamp': DateTime.now().toIso8601String(),
      'level': level,
      'type': 'request',
      'message': '${options.method} $path',
      'method': options.method,
      'url': sanitizedUrl,
      'statusCode': statusCode,
      'duration': duration,
      'relativeStartMs': record.relativeStartMs,
    };
    if (priority != null) entry['priority'] = priority;
    if (isSilent) entry['isSilent'] = true;
    if (errorType != null) entry['errorType'] = errorType;
    final extraFields = options.extra['_networkLogFields'];
    if (extraFields is Map) {
      entry.addAll(extraFields.cast<String, dynamic>());
    }
    if (adapterName != null) {
      entry['networkAdapter'] = adapterName;
    }
    if (RuntimeLogSettings.shouldPersistRequestLog(
      level: level,
      isSilent: isSilent,
    )) {
      LogWriter.instance.write(entry);
    }
  }
}
