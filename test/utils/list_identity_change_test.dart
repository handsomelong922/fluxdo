import 'package:flutter_test/flutter_test.dart';

import '../../tool/list_identity_change_smoke.dart';

void main() {
  test('过滤复制、尾追加与真实结构变化分别处理', runListIdentityChangeChecks);
}
