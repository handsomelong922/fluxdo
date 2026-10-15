import 'package:flutter_test/flutter_test.dart';

import '../../tool/cf_diagnostic_redaction_smoke.dart';

void main() {
  for (final entry in cfDiagnosticRedactionSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
