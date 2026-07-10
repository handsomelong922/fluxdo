import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/webview_session_cookie_refresh_service.dart';

void main() {
  test('bootstrap failure cooldown grows exponentially and caps at 15m', () {
    expect(
      webViewSessionFailureCooldownForStreak(0),
      const Duration(seconds: 45),
    );
    expect(
      webViewSessionFailureCooldownForStreak(1),
      const Duration(seconds: 45),
    );
    expect(
      webViewSessionFailureCooldownForStreak(2),
      const Duration(seconds: 90),
    );
    expect(
      webViewSessionFailureCooldownForStreak(3),
      const Duration(minutes: 3),
    );
    expect(
      webViewSessionFailureCooldownForStreak(4),
      const Duration(minutes: 6),
    );
    expect(
      webViewSessionFailureCooldownForStreak(5),
      const Duration(minutes: 12),
    );
    expect(
      webViewSessionFailureCooldownForStreak(6),
      const Duration(minutes: 15),
    );
    expect(
      webViewSessionFailureCooldownForStreak(99),
      const Duration(minutes: 15),
    );
  });

  group('fingerprint endpoint extraction', () {
    test('accepts changing minified JavaScript identifiers', () {
      expect(
        extractFingerprintEndpointForTesting(
          r'_("/old",{type:"POST",data:{visitor_id:',
        ),
        '/old',
      );
      expect(
        extractFingerprintEndpointForTesting(
          r'L("/cj2tt",{type:"POST",data:{visitor_id:',
        ),
        '/cj2tt',
      );
      expect(
        extractFingerprintEndpointForTesting(
          r'$a1("/next",{type:"POST",data:{visitor_id:',
        ),
        '/next',
      );
    });

    test('rejects invalid identifiers and incomplete request shapes', () {
      expect(
        extractFingerprintEndpointForTesting(
          r'1bad("/wrong",{type:"POST",data:{visitor_id:',
        ),
        isNull,
      );
      expect(
        extractFingerprintEndpointForTesting(
          r'L("/wrong",{type:"GET",data:{visitor_id:',
        ),
        isNull,
      );
      expect(
        extractFingerprintEndpointForTesting(
          r'L("/wrong",{type:"POST",data:{user_id:',
        ),
        isNull,
      );
    });
  });

  test(
    'cookie summary omits verbose cookie details outside developer mode',
    () {
      final entry = buildCookieSummaryLogEntry(
        timestamp: DateTime.utc(2026, 7, 3, 14),
        level: 'warning',
        reason: 'dio_request:POST',
        cookieNames: const ['_t', '_forum_session'],
        cookieDetails: const [
          {'name': '_t', 'valueLength': 10},
        ],
        includeCookieDetails: false,
        bootstrapOk: false,
      );

      expect(entry['cookieNames'], ['_t', '_forum_session']);
      expect(entry['cookieCount'], 2);
      expect(entry.containsKey('cookieDetails'), isFalse);
    },
  );

  test('cookie summary keeps details in verbose mode', () {
    final entry = buildCookieSummaryLogEntry(
      timestamp: DateTime.utc(2026, 7, 3, 14),
      level: 'info',
      reason: 'startup',
      cookieNames: const ['_t'],
      cookieDetails: const [
        {'name': '_t', 'valueLength': 10},
      ],
      includeCookieDetails: true,
    );

    expect((entry['cookieDetails'] as List).length, 1);
  });

  test('dedupe skips repeated non-verbose cookie summaries in window', () {
    final now = DateTime.utc(2026, 7, 3, 14, 0, 0);
    expect(
      shouldSkipRepeatedCookieSummary(
        signature: 'same',
        lastSignature: 'same',
        lastLoggedAt: now.subtract(const Duration(seconds: 30)),
        now: now,
        dedupeWindow: const Duration(minutes: 2),
        verboseMode: false,
      ),
      isTrue,
    );
  });
}
