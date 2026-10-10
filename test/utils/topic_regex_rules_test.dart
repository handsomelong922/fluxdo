import 'package:flutter_test/flutter_test.dart';

import '../../tool/topic_regex_smoke.dart' as smoke;

void main() {
  // 两种入口执行相同的真实 Isolate 用例；命令行版本不依赖 Flutter 或联网。
  for (final entry in smoke.topicRegexSmokeTests.entries) {
    test(entry.key, entry.value);
  }
}
