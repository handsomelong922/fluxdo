import 'package:flutter_test/flutter_test.dart';
import '../../tool/topic_new_post_retry_smoke.dart' as smoke;

void main() {
  test('新回复重试有界且重载隔离', smoke.main);
}
