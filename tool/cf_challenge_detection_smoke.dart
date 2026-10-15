import '../lib/services/cf_challenge_detection.dart';

void main() {
  var count = 0;
  void check(bool value) {
    count++;
    if (!value) throw StateError('挑战判定回归失败：$count');
  }

  for (final status in [403, 429, 503]) {
    check(
      CfChallengeDetection.isResponse(status: status, mitigated: 'challenge'),
    );
    check(
      CfChallengeDetection.isResponse(
        status: status,
        contentType: 'TEXT/HTML; charset=UTF-8',
        body: '<script>window._cf_chl_opt={}</script>',
      ),
    );
    check(
      !CfChallengeDetection.isResponse(
        status: status,
        body: '<html>Service unavailable</html>',
      ),
    );
    check(
      !CfChallengeDetection.isResponse(
        status: status,
        mitigated: 'not-challenge',
        body: '{}',
      ),
    );
    check(
      !CfChallengeDetection.isResponse(
        status: status,
        contentType: 'application/json',
        body: '{"post":"cf_chl_opt"}',
      ),
    );
    check(
      !CfChallengeDetection.isResponse(
        status: status,
        body: {'post': 'cf_chl_opt'},
      ),
    );
  }
  check(!CfChallengeDetection.isResponse(status: 200, body: 'cf_chl_opt'));
  check(CfChallengeDetection.isResponse(status: 503, mitigated: ' Challenge '));
  check(!CfChallengeDetection.hasChallengeHeader('challenge-pending'));
  check(!CfChallengeDetection.isResponse(status: null));
  for (final method in ['POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS']) {
    check(!CfChallengeDetection.canEnterRecovery(503, method));
  }
  check(CfChallengeDetection.canEnterRecovery(503, 'GET'));
  check(CfChallengeDetection.canEnterRecovery(503, 'head'));
  print('$count 项挑战识别回归通过');
}
