import 'package:flutter_test/flutter_test.dart';

import '../../tool/cf_diagnostic_source_smoke.dart';

void main() {
  for (final entry in cfDiagnosticSourceSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
