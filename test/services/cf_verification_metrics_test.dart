import 'package:flutter_test/flutter_test.dart';

import '../../tool/cf_verification_metrics_smoke.dart';

void main() {
  for (final entry in cfVerificationMetricsSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
