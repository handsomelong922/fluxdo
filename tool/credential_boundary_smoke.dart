import '../lib/services/network/credential_boundary.dart';

final credentialBoundarySmokeTests = <String, void Function()>{
  'HTTPS 同源允许不同路径、查询及显式默认端口': () {
    final origin = Uri.parse('https://linux.do');
    for (final value in [
      'https://linux.do/latest.json',
      'https://LINUX.DO/uploads/secure.png?download=1#image',
      'https://linux.do:443/t/42',
    ]) {
      _check(isSameHttpsOrigin(origin, Uri.parse(value)), value);
    }
  },
  '不同主机、子域、非默认端口和 HTTP 不属于可信源': () {
    final origin = Uri.parse('https://linux.do');
    for (final value in [
      'https://cdn.example/image.png',
      'https://auth.linux.do/session',
      'https://linux.do.evil.example/latest.json',
      'https://linux.do:8443/latest.json',
      'http://linux.do/latest.json',
      'http://linux.do:443/latest.json',
      'file:///latest.json',
      '/latest.json',
      '//linux.do/latest.json',
    ]) {
      _check(!isSameHttpsOrigin(origin, Uri.parse(value)), value);
    }
  },
  '拒绝带用户信息的 URL，不能被伪装成可信主机': () {
    final origin = Uri.parse('https://linux.do');
    for (final value in [
      'https://linux.do@evil.example/file',
      'https://evil.example@linux.do/file',
      'https://user:password@linux.do/file',
      'https://user%40linux.do@evil.example/file',
    ]) {
      _check(!isSameHttpsOrigin(origin, Uri.parse(value)), value);
      _check(!isSameHttpsOrigin(Uri.parse(value), origin), value);
    }
  },
  '自定义端口必须完全匹配，非 HTTPS 源不能自我授权': () {
    _check(
      isSameHttpsOrigin(
        Uri.parse('https://example.com:8443/a'),
        Uri.parse('https://example.com:8443/b'),
      ),
      '相同 HTTPS 非默认端口',
    );
    _check(
      !isSameHttpsOrigin(
        Uri.parse('http://linux.do/a'),
        Uri.parse('http://linux.do/b'),
      ),
      '两个 HTTP URL 不能授权敏感头',
    );
  },
};

void main() {
  for (final entry in credentialBoundarySmokeTests.entries) {
    entry.value();
    print('通过：${entry.key}');
  }
  print('凭据源边界 ${credentialBoundarySmokeTests.length} 项全部通过');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}
