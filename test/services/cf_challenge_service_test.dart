import 'package:flutter_test/flutter_test.dart';

import 'package:fluxdo/services/cf_challenge_service.dart';

void main() {
  final service = CfChallengeService();

  setUp(service.debugResetBusinessTrafficBlock);
  tearDown(service.debugResetBusinessTrafficBlock);

  group('CfChallengeService.isOriginNotFound', () {
    test('识别 Discourse 404 的稳定标记且不区分大小写', () {
      expect(
        CfChallengeService.isOriginNotFound(
          '<html><body class="PAGE-NOT-FOUND">missing</body></html>',
        ),
        isTrue,
      );
      expect(
        CfChallengeService.isOriginNotFound(
          '<div>the page you requested does not exist or is private</div>',
        ),
        isTrue,
      );
      expect(
        CfChallengeService.isOriginNotFound('{"errorType":"notFound"}'),
        isTrue,
      );
    });

    test('不会把普通内容误判为源站 404', () {
      expect(
        CfChallengeService.isOriginNotFound(
          '<html><title>404 reasons users discuss</title><body>cloudflare 404 tips</body></html>',
        ),
        isFalse,
      );
      expect(CfChallengeService.isOriginNotFound(''), isFalse);
    });
  });

  group('CfChallengeService.hasActiveCfChallenge', () {
    test('识别常见的 Cloudflare challenge 标记', () {
      expect(
        CfChallengeService.hasActiveCfChallenge(
          '<div class="cf-turnstile"></div>',
        ),
        isTrue,
      );
      expect(
        CfChallengeService.hasActiveCfChallenge(
          '<script>var cf_chl_opt = {};</script>',
        ),
        isTrue,
      );
      expect(
        CfChallengeService.hasActiveCfChallenge(
          '<div class="challenge-running"></div>',
        ),
        isTrue,
      );
    });

    test('普通页面不应被识别为活跃 challenge', () {
      expect(
        CfChallengeService.hasActiveCfChallenge(
          '<html><body>normal page</body></html>',
        ),
        isFalse,
      );
    });
  });

  group('business traffic block', () {
    test('authoritative challenge blocks background business traffic', () {
      service.markChallengeDetected();

      expect(service.isBusinessTrafficBlocked, isTrue);
    });

    test('fresh verified clearance immediately releases traffic', () {
      service.markChallengeDetected();
      service.markClearanceResolved();

      expect(service.isBusinessTrafficBlocked, isFalse);
      expect(service.clearanceResolvedAt.value, isNotNull);
    });
  });
}
