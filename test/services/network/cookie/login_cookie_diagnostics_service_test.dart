import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/network/cookie/login_cookie_diagnostics_service.dart';

void main() {
  group('LoginCookieDiagnosticsService', () {
    final service = LoginCookieDiagnosticsService();
    final checkedAt = DateTime.utc(2026, 5, 24, 12);

    test('summarizes a healthy logged-in cookie state without raw values', () {
      final diagnostics = service.buildFromDiagnostics(
        isLoggedIn: true,
        hasCfClearance: true,
        checkedAt: checkedAt,
        sessionDiagnostics: const [
          {'name': '_t', 'valueLength': 24, 'value': 'secret-token'},
          {'name': '_forum_session', 'valueLength': 48, 'value': 'secret'},
        ],
      );

      expect(diagnostics.isLoggedIn, isTrue);
      expect(diagnostics.hasTToken, isTrue);
      expect(diagnostics.hasForumSession, isTrue);
      expect(diagnostics.hasCfClearance, isTrue);
      expect(diagnostics.sessionCookieCount, 2);
      expect(diagnostics.hasDuplicateRisk, isFalse);
      expect(diagnostics.looksHealthy, isTrue);
      expect(diagnostics.statusLabel, '登录状态正常');
    });

    test('detects missing session cookies', () {
      final diagnostics = service.buildFromDiagnostics(
        isLoggedIn: true,
        hasCfClearance: false,
        checkedAt: checkedAt,
        sessionDiagnostics: const [
          {'name': '_t', 'valueLength': 24},
        ],
      );

      expect(diagnostics.hasTToken, isTrue);
      expect(diagnostics.hasForumSession, isFalse);
      expect(diagnostics.hasSessionCookies, isFalse);
      expect(diagnostics.looksHealthy, isFalse);
      expect(diagnostics.statusLabel, '登录 Cookie 不完整');
    });

    test('detects duplicate session cookie names', () {
      final diagnostics = service.buildFromDiagnostics(
        isLoggedIn: true,
        hasCfClearance: true,
        checkedAt: checkedAt,
        sessionDiagnostics: const [
          {'name': '_t', 'domain': null},
          {'name': '_t', 'domain': '.linux.do'},
          {'name': '_forum_session'},
        ],
      );

      expect(diagnostics.sessionCookieCount, 3);
      expect(diagnostics.duplicateSessionCookieNames, {'_t'});
      expect(diagnostics.hasDuplicateRisk, isTrue);
      expect(diagnostics.looksHealthy, isFalse);
      expect(diagnostics.statusLabel, '检测到 Cookie 多副本风险');
    });
  });
}
