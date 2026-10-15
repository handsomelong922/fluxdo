import 'package:flutter_test/flutter_test.dart';

import '../../tool/cf_challenge_detection_smoke.dart' as smoke;

void main() {
  test('精确识别挑战响应，普通 503 和业务内容不触发验证', smoke.main);
}
