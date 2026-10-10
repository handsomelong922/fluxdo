import 'package:flutter_test/flutter_test.dart';

import '../../tool/topic_regex_filter_smoke.dart' as smoke;

void main() {
  // 离线命令行和 Flutter 单测共享生命周期回归用例。
  for (final entry in smoke.topicRegexFilterSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
