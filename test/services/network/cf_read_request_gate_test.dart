import 'package:flutter_test/flutter_test.dart';

import '../../../tool/cf_read_request_gate_smoke.dart'
    show cfReadRequestGateSmokeTests;

void main() {
  for (final entry in cfReadRequestGateSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
