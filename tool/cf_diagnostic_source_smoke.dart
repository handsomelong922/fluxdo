import 'dart:io';

/// 只检查已修复日志入口的源码契约，不替代 Flutter 运行时集成测试，
/// 也不把有限的模式检查当作整个应用日志安全性的证明。
final cfDiagnosticSourceSmokeTests = <String, void Function()>{
  '验证页不输出完整响应头及加载错误正文': () {
    final source = File('lib/services/cf_challenge_service.dart')
        .readAsStringSync();
    for (final unsafe in [
      r'headers=${response?.headers}',
      r'headers=${errorResponse.headers}',
      r'Passed response headers: $headers',
      r'description=${error.description}',
      "'description': error.description,",
    ]) {
      _check(!source.contains(unsafe), '原始响应头或错误正文重新进入日志');
    }
    _check(
      source.contains("'description': cfDiagnosticError(error.description)"),
      '结构化错误也必须省略正文',
    );
    _check(
      source.contains(r'headersPresent=${response?.headers != null}'),
      '保留响应头存在性',
    );
  },
  '拦截器日志保留重试状态并移除原始 URL 与异常正文': () {
    final source = File(
      'lib/services/network/interceptors/cf_challenge_interceptor.dart',
    ).readAsStringSync();
    _check(!source.contains(r'$requestMethod $requestUrl'), '请求 URL 必须先脱敏');
    _check(!source.contains(r'url=${e.requestOptions.uri}'), '失败请求 URL 必须先脱敏');
    _check(!source.contains('error: e.toString()'), '不序列化异常对象');
    _check(
      source.contains(
        'statusCode: e is DioException ? e.response?.statusCode : null',
      ),
      '重试失败状态码不能丢失',
    );
  },
  '日志仍默认关闭且不记录 clearance 值': () {
    final source = File('lib/services/cf_challenge_logger.dart')
        .readAsStringSync();
    _check(source.contains('static bool _enabled = false;'), '默认日志不能启用');
    _check(
      source.contains(r'hasClearance=${cfClearance != null}'),
      '只记录 clearance 存在性',
    );
    _check(!source.contains(r'=$cfClearance'), '不能输出 clearance');
    _check(source.contains('cfDiagnosticUrl(url)'), '专用日志 URL 必须经过摘要');
  },
};

void main() {
  for (final entry in cfDiagnosticSourceSmokeTests.entries) {
    entry.value();
    print('通过：${entry.key}');
  }
  print('CF 诊断日志源码契约 ${cfDiagnosticSourceSmokeTests.length} 项全部通过');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
