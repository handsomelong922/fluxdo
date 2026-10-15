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
  '同源跳转只清除 Cookie，保留调用方认证及普通资源头': () {
    final original = <String, dynamic>{
      'cOoKiE': 'old-cookie',
      'Authorization': 'Bearer same-origin-token',
      'X-CSRF-Token': 'forum-token',
      'Accept': 'image/*',
      'Range': 'bytes=0-99',
    };
    final result = redirectRequestHeaders(
      original,
      source: Uri.parse('https://linux.do/uploads/1'),
      target: Uri.parse('https://linux.do:443/uploads/2'),
    );
    _check(!result.containsKey('cOoKiE'), 'Cookie 必须从目标 jar 重取');
    _check(result['Authorization'] == original['Authorization'], '保留同源认证');
    _check(result['X-CSRF-Token'] == 'forum-token', '保留同源 CSRF');
    _check(result['Range'] == 'bytes=0-99', '保留资源请求头');
    _check(original['cOoKiE'] == 'old-cookie', '不能改写原请求');
  },
  '每个不可信跳转均清理所有大小写形式的原认证头': () {
    final original = <String, dynamic>{
      'COOKIE': 'cookie',
      'aUtHoRiZaTiOn': 'bearer',
      'Proxy-Authorization': 'proxy',
      'x-CsRf-ToKeN': 'csrf',
      'User-Api-Key': 'user-key',
      'Api-Key': 'api-key',
      'Api-Username': 'username',
      'User-Api-Client-Id': 'client-id',
      'Discourse-Logged-In': 'true',
      'Discourse-Present': 'true',
      'Accept': 'image/*',
    };
    for (final target in [
      'https://cdn.example/image.png',
      'https://sub.linux.do/image.png',
      'http://linux.do/image.png',
      'https://linux.do:8443/image.png',
      'https://linux.do@cdn.example/image.png',
      'https://user@linux.do/image.png',
    ]) {
      final result = redirectRequestHeaders(
        original,
        source: Uri.parse('https://linux.do/uploads/1'),
        target: Uri.parse(target),
      );
      _check(result.length == 1 && result['Accept'] == 'image/*', target);
    }
  },
  '跨源后再返回原源不能恢复中途清掉的调用方凭据': () {
    final forum = Uri.parse('https://linux.do/file');
    final cdn = Uri.parse('https://cdn.example/file');
    final outgoing = redirectRequestHeaders(
      {'Authorization': 'bearer', 'Accept': '*/*'},
      source: forum,
      target: cdn,
    );
    final returning = redirectRequestHeaders(
      outgoing,
      source: cdn,
      target: forum,
    );
    _check(!returning.containsKey('Authorization'), '凭据不得从早先快照恢复');
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
