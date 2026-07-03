import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/webview_session_cookie_refresh_service.dart';

void main() {
  test('cookie summary omits verbose cookie details outside developer mode', () {
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
  });

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
