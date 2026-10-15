import 'package:flutter_test/flutter_test.dart';
import '../../tool/topic_post_refresh_queue_smoke.dart' as smoke;

void main() {
  test('单帖尾部刷新保留 cooked 合并语义', smoke.main);
}
