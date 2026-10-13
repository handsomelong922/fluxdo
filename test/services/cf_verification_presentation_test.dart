import 'package:flutter_test/flutter_test.dart';

import '../../tool/cf_verification_presentation_smoke.dart';

void main() {
  for (final entry in cfVerificationPresentationSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
