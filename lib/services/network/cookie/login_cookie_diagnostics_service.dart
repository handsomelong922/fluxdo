import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cookie_jar_service.dart';

class LoginCookieDiagnostics {
  const LoginCookieDiagnostics({
    required this.isLoggedIn,
    required this.hasTToken,
    required this.hasForumSession,
    required this.hasCfClearance,
    required this.sessionCookieCount,
    required this.duplicateSessionCookieNames,
    required this.checkedAt,
  });

  final bool isLoggedIn;
  final bool hasTToken;
  final bool hasForumSession;
  final bool hasCfClearance;
  final int sessionCookieCount;
  final Set<String> duplicateSessionCookieNames;
  final DateTime checkedAt;

  bool get hasSessionCookies => hasTToken && hasForumSession;
  bool get hasDuplicateRisk => duplicateSessionCookieNames.isNotEmpty;
  bool get looksHealthy => isLoggedIn && hasSessionCookies && !hasDuplicateRisk;

  String get statusLabel {
    if (looksHealthy) return '登录状态正常';
    if (!isLoggedIn && !hasSessionCookies) return '未检测到登录会话';
    if (hasDuplicateRisk) return '检测到 Cookie 多副本风险';
    if (!hasSessionCookies) return '登录 Cookie 不完整';
    return '登录状态需关注';
  }
}

class LoginCookieDiagnosticsService {
  LoginCookieDiagnosticsService({CookieJarService? cookieJarService})
    : _cookieJarService = cookieJarService ?? CookieJarService();

  final CookieJarService _cookieJarService;

  Future<LoginCookieDiagnostics> load({required bool isLoggedIn}) async {
    final sessionDiagnostics = await _cookieJarService
        .getSessionCookieDiagnosticsForRequest();
    final cfClearance = await _cookieJarService.getCfClearance();

    return buildFromDiagnostics(
      isLoggedIn: isLoggedIn,
      sessionDiagnostics: sessionDiagnostics,
      hasCfClearance: cfClearance != null && cfClearance.isNotEmpty,
      checkedAt: DateTime.now(),
    );
  }

  LoginCookieDiagnostics buildFromDiagnostics({
    required bool isLoggedIn,
    required List<Map<String, dynamic>> sessionDiagnostics,
    required bool hasCfClearance,
    required DateTime checkedAt,
  }) {
    final countsByName = <String, int>{};
    for (final item in sessionDiagnostics) {
      final name = item['name']?.toString();
      if (name == null || name.isEmpty) continue;
      countsByName[name] = (countsByName[name] ?? 0) + 1;
    }

    final duplicates = countsByName.entries
        .where((entry) => entry.value > 1)
        .map((entry) => entry.key)
        .toSet();

    return LoginCookieDiagnostics(
      isLoggedIn: isLoggedIn,
      hasTToken: (countsByName['_t'] ?? 0) > 0,
      hasForumSession: (countsByName['_forum_session'] ?? 0) > 0,
      hasCfClearance: hasCfClearance,
      sessionCookieCount: countsByName.values.fold<int>(
        0,
        (total, count) => total + count,
      ),
      duplicateSessionCookieNames: duplicates,
      checkedAt: checkedAt,
    );
  }
}

final loginCookieDiagnosticsServiceProvider =
    Provider<LoginCookieDiagnosticsService>((ref) {
      return LoginCookieDiagnosticsService();
    });
