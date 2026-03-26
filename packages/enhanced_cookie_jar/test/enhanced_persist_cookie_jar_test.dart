import 'dart:io';

import 'package:enhanced_cookie_jar/enhanced_cookie_jar.dart';
import 'package:test/test.dart';

void main() {
  group('EnhancedPersistCookieJar', () {
    late Directory tempDir;
    late EnhancedPersistCookieJar jar;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'enhanced_cookie_jar_test_',
      );
      jar = EnhancedPersistCookieJar(
        store: FileCookieStore(tempDir.path),
      );
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('domain cookie matches subdomain requests', () async {
      await jar.saveFromSetCookieHeaders(
        Uri.parse('https://linux.do'),
        ['cf_clearance=abc; Domain=.linux.do; Path=/; Secure; HttpOnly'],
      );

      final cookies = await jar.loadForRequest(
        Uri.parse('https://connect.linux.do/oauth2/authorize'),
      );

      expect(cookies.map((e) => e.name), contains('cf_clearance'));
    });

    test('host-only cookie only matches exact host', () async {
      await jar.saveFromSetCookieHeaders(
        Uri.parse('https://connect.linux.do/oauth2/authorize'),
        ['auth.session-token=token123; Path=/; Secure; HttpOnly; SameSite=Lax'],
      );

      final exactHostCookies = await jar.loadForRequest(
        Uri.parse('https://connect.linux.do/discourse/sso_callback'),
      );
      final siblingHostCookies = await jar.loadForRequest(
        Uri.parse('https://cdk.linux.do/callback'),
      );

      expect(exactHostCookies.map((e) => e.name), contains('auth.session-token'));
      expect(
        siblingHostCookies.map((e) => e.name),
        isNot(contains('auth.session-token')),
      );
    });

    test('invalid cookie values are encoded when converted to io.Cookie', () async {
      await jar.saveCanonicalCookies(
        Uri.parse('https://linux.do'),
        [
          CanonicalCookie(
            name: 'g_state',
            value: '{"i_l":0,"i_ll":1774544311822}',
            domain: 'linux.do',
            path: '/',
            originUrl: 'https://linux.do',
            hostOnly: false,
          ),
        ],
      );

      final cookies = await jar.loadForRequest(Uri.parse('https://linux.do'));
      final gState = cookies.firstWhere((e) => e.name == 'g_state');

      expect(gState.value, startsWith('~enc~'));
    });

    test('redirect oauth cookie stays available for same host', () async {
      await jar.saveFromSetCookieHeaders(
        Uri.parse(
          'https://connect.linux.do/oauth2/authorize?client_id=test',
        ),
        [
          'auth.session-token=oauth-token; Path=/; Secure; HttpOnly; SameSite=Lax',
        ],
      );

      final cookies = await jar.loadForRequest(
        Uri.parse('https://connect.linux.do/oauth2/approve/test'),
      );

      expect(
        cookies.any(
          (cookie) =>
              cookie.name == 'auth.session-token' &&
              cookie.value == 'oauth-token',
        ),
        isTrue,
      );
    });
  });
}
