import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/widgets/topic/topic_item_builder.dart';

void main() {
  group('topicChildIndexForKey', () {
    test('maps a stable topic ValueKey to its current child index', () {
      expect(
        topicChildIndexForKey(const ValueKey<int>(42), const <int, int>{42: 7}),
        7,
      );
    });

    test('ignores non-topic and missing keys', () {
      expect(
        topicChildIndexForKey(
          const ValueKey<String>('footer'),
          const <int, int>{42: 7},
        ),
        isNull,
      );
      expect(
        topicChildIndexForKey(const ValueKey<int>(99), const <int, int>{42: 7}),
        isNull,
      );
    });
  });
}
