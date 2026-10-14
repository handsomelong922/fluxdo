import 'package:flutter_test/flutter_test.dart';

import '../../tool/cf_verification_readiness_smoke.dart';

void main() {
  for (final entry in cfVerificationReadinessSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
