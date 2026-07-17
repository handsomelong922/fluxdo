import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'returning from a child route does not trigger an automatic full refresh',
    () {
      final source = File(
        'lib/pages/topic_detail_page/topic_detail_page.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('_topicChannelNeedsCatchUp')));
      expect(source, isNot(contains('refreshWithPostNumber(postNumber)')));
    },
  );
}
