import 'package:flutter_test/flutter_test.dart';

import '../../tool/topic_keyword_matcher_smoke.dart' as smoke;

void main() {
  test('大规模字面索引与旧算法语义一致，并正确处理缓存失效和淘汰', smoke.main);
}
