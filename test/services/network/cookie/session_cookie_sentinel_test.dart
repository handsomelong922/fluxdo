import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/cookie_full_info.dart';
import 'package:fluxdo/services/network/cookie/cookie_jar_service.dart';
import 'package:fluxdo/services/network/cookie/raw_cookie_writer.dart';
import 'package:fluxdo/services/network/cookie/session_cookie_sentinel.dart';

void main() {
  tearDown(() {
    SessionCookieSentinel.instance
      ..replaceDependenciesForTest(
        writer: RawCookieWriter.instance,
        jar: CookieJarService(),
      )
      ..resetForTest();
  });

  group('SessionCookieSentinel', () {
    test('WebView 新值获胜时保留 jar canonical 元数据', () async {
      final expiresAt = DateTime.utc(2026, 7, 1, 12);
      final canonical = CanonicalCookie(
        name: 'cf_clearance',
        value: 'old-token',
        domain: '.linux.do',
        path: '/cdn-cgi/challenge-platform',
        expiresAt: expiresAt,
        secure: true,
        httpOnly: true,
        sameSite: CookieSameSite.none,
        hostOnly: false,
        persistent: true,
        originUrl: 'https://linux.do/',
        rawSetCookie:
            'cf_clearance=old-token; Domain=.linux.do; '
            'Path=/cdn-cgi/challenge-platform; Secure; HttpOnly; SameSite=None',
      );
      final writer = _FakeRawCookieWriter([
        CookieFullInfo(name: 'cf_clearance', value: 'old-token'),
        CookieFullInfo(name: 'cf_clearance', value: 'new-token'),
      ]);
      final jar = _FakeCookieJarService(canonical);

      SessionCookieSentinel.instance
        ..replaceDependenciesForTest(writer: writer, jar: jar)
        ..resetForTest();

      final result = await SessionCookieSentinel.instance.sweep(
        'https://linux.do/cdn-cgi/challenge-platform/h/b',
        'cf_clearance',
      );

      expect(result.status, SweepStatus.swept);
      expect(result.winnerSource, 'webview');

      expect(writer.writtenHeaders, hasLength(1));
      final header = writer.writtenHeaders.single;
      expect(header, contains('cf_clearance=new-token'));
      expect(header, contains('Domain=.linux.do'));
      expect(header, contains('Path=/cdn-cgi/challenge-platform'));
      expect(header, contains('Secure'));
      expect(header, contains('HttpOnly'));
      expect(header, contains('SameSite=None'));
      expect(header, isNot(contains('cf_clearance=old-token')));

      expect(jar.setCalls, hasLength(1));
      final call = jar.setCalls.single;
      expect(call.name, 'cf_clearance');
      expect(call.value, 'new-token');
      expect(call.domain, '.linux.do');
      expect(call.path, '/cdn-cgi/challenge-platform');
      expect(call.expires, expiresAt);
      expect(call.secure, isTrue);
      expect(call.httpOnly, isTrue);
    });
  });
}

class _FakeRawCookieWriter implements RawCookieWriter {
  _FakeRawCookieWriter(this._variants);

  List<CookieFullInfo> _variants;
  final writtenHeaders = <String>[];

  @override
  bool get isSupported => true;

  @override
  Future<int> countCookiesByName(String url, String name) async {
    return _variants.where((cookie) => cookie.name == name).length;
  }

  @override
  Future<List<CookieFullInfo>> getAllCookieInfos(String url) async {
    return List<CookieFullInfo>.from(_variants);
  }

  @override
  Future<int> nukeAllVariants({
    required String url,
    required String name,
    required List<String?> domainCandidates,
    required List<String> pathCandidates,
  }) async {
    final before = _variants.length;
    _variants = _variants.where((cookie) => cookie.name != name).toList();
    return before - _variants.length;
  }

  @override
  Future<bool> setRawCookie(String url, String rawSetCookie) async {
    writtenHeaders.add(rawSetCookie);
    _variants = [_cookieInfoFromHeader(rawSetCookie)];
    return true;
  }

  CookieFullInfo _cookieInfoFromHeader(String rawSetCookie) {
    final parts = rawSetCookie.split(';').map((part) => part.trim()).toList();
    final nameValue = parts.first;
    final eq = nameValue.indexOf('=');
    final name = nameValue.substring(0, eq);
    final value = nameValue.substring(eq + 1);

    String? domain;
    String? path;
    String? sameSite;
    bool? secure;
    bool? httpOnly;

    for (final attr in parts.skip(1)) {
      final lower = attr.toLowerCase();
      if (lower == 'secure') {
        secure = true;
      } else if (lower == 'httponly') {
        httpOnly = true;
      } else if (lower.startsWith('domain=')) {
        domain = attr.substring('Domain='.length);
      } else if (lower.startsWith('path=')) {
        path = attr.substring('Path='.length);
      } else if (lower.startsWith('samesite=')) {
        sameSite = attr.substring('SameSite='.length);
      }
    }

    return CookieFullInfo(
      name: name,
      value: value,
      domain: domain,
      path: path,
      isSecure: secure,
      isHttpOnly: httpOnly,
      sameSite: sameSite,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCookieJarService implements CookieJarService {
  _FakeCookieJarService(this.canonical);

  final CanonicalCookie canonical;
  final setCalls = <_SetCookieCall>[];

  @override
  bool get isInitialized => true;

  @override
  Future<List<CanonicalCookie>> loadCanonicalCookiesForRequest(Uri uri) async {
    return [canonical];
  }

  @override
  Future<CanonicalCookie?> getCanonicalCookie(String name) async {
    return canonical.name == name ? canonical : null;
  }

  @override
  Future<void> setCookie(
    String name,
    String value, {
    String? url,
    String? domain,
    String? path,
    DateTime? expires,
    bool secure = true,
    bool httpOnly = false,
  }) async {
    setCalls.add(
      _SetCookieCall(
        name: name,
        value: value,
        url: url,
        domain: domain,
        path: path,
        expires: expires,
        secure: secure,
        httpOnly: httpOnly,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SetCookieCall {
  const _SetCookieCall({
    required this.name,
    required this.value,
    required this.url,
    required this.domain,
    required this.path,
    required this.expires,
    required this.secure,
    required this.httpOnly,
  });

  final String name;
  final String value;
  final String? url;
  final String? domain;
  final String? path;
  final DateTime? expires;
  final bool secure;
  final bool httpOnly;
}
