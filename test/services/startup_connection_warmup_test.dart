import 'package:flutter_test/flutter_test.dart';

import '../../tool/startup_connection_warmup_smoke.dart';

void main() {
  for (final entry in startupWarmupSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
