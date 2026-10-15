import 'package:flutter_test/flutter_test.dart';

import '../../../tool/credential_boundary_smoke.dart';

void main() {
  for (final entry in credentialBoundarySmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
