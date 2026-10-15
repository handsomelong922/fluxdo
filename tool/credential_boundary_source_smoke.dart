import 'dart:io';

/// 仅检查接线契约；不能替代 Dio、WebView 或设备上的运行时验证。
void main() {
  final headers = File(
    'lib/services/network/interceptors/request_header_interceptor.dart',
  ).readAsStringSync();
  final boundary = headers.indexOf('isSameHttpsOrigin(');
  final injection = headers.indexOf('if (!skipCsrf)');
  _require(boundary >= 0 && boundary < injection, '注入 CSRF 前必须检查可信 HTTPS 源');
  _require(headers.contains('if (!trustedForumOrigin)'), '非论坛源必须清除遗留 CSRF');
  _require(
    headers.contains("entry.key.toLowerCase() != 'x-csrf-token'"),
    '清除 CSRF 时必须覆盖所有头名大小写',
  );
  print('通过：CSRF 源边界接线契约（非运行时集成测试）');
}

void _require(bool condition, String message) {
  if (!condition) throw StateError(message);
}
