import '../lib/services/cf_diagnostic_redaction.dart';

final cfDiagnosticRedactionSmokeTests = <String, void Function()>{
  '删除 URL 用户信息、查询和片段，保留来源与路径': () {
    _equal(
      cfDiagnosticUrl(
        'https://user:password@example.com:8443/latest.json?token=secret#cookie',
      ),
      'https://example.com:8443/latest.json',
    );
  },
  '支持 HTTP、IPv6 和相对绝对路径': () {
    _equal(
      cfDiagnosticUrl('http://example.com/t/42?key=x'),
      'http://example.com/t/42',
    );
    _equal(
      cfDiagnosticUrl('https://u:p@[::1]:8443/a?x#y'),
      'https://[::1]:8443/a',
    );
    _equal(cfDiagnosticUrl('/latest.json?api_key=secret#x'), '/latest.json');
  },
  '编码后的认证和查询不能残留': () {
    _equal(
      cfDiagnosticUrl('https://u%40x:p%23y@example.com/a%20b?token=a%26b#c'),
      'https://example.com/a%20b',
    );
  },
  '无查询 URL 保持必要诊断路径': () {
    _equal(
      cfDiagnosticUrl('https://example.com/challenge'),
      'https://example.com/challenge',
    );
    _equal(cfDiagnosticUrl('https://example.com'), 'https://example.com');
  },
  '无法识别、控制字符和非 HTTP 输入整段省略': () {
    for (final value in [
      '',
      'token=secret',
      '//user:password@example.com/a',
      'data:text/plain,token',
      'file:///private/token',
      'https://[bad/token',
      'https:///token',
      'https://example.com/a\nCookie: secret',
      'https://example.com/a\u0000secret',
      'https://example.com/a secret',
    ]) {
      _equal(cfDiagnosticUrl(value), '[URL omitted]');
    }
  },
  '省略任意错误正文，不能因缺少敏感关键词而泄露': () {
    for (final error in [
      'Cookie: session=secret',
      'Authorization: Bearer secret',
      'https://user:password@example.com?token=secret',
      'unexpected payload secret',
      '',
    ]) {
      _equal(cfDiagnosticError(error), '[error detail omitted]');
    }
    _equal(cfDiagnosticError(null), 'not provided');
  },
  '异常对象不调用可能泄露正文的 toString': () {
    _equal(cfDiagnosticError(_UnsafeError()), '[error detail omitted]');
  },
  '重复 URL 脱敏保持一致': () {
    final safe = cfDiagnosticUrl('https://u:p@example.com/a?token=s#s');
    _equal(cfDiagnosticUrl(safe), safe);
  },
};

void main() {
  for (final entry in cfDiagnosticRedactionSmokeTests.entries) {
    entry.value();
    print('通过：${entry.key}');
  }
  print('CF 诊断脱敏 ${cfDiagnosticRedactionSmokeTests.length} 项全部通过');
}

void _equal(Object? actual, Object? expected) {
  if (actual != expected) throw StateError('期望 $expected，实际 $actual');
}

class _UnsafeError {
  @override
  String toString() => throw StateError('不能对异常序列化');
}
