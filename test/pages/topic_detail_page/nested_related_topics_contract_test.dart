import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('nested post footer receives the detail related topics list', () {
    final source = File(
      'lib/widgets/nested/nested_post_card.dart',
    ).readAsStringSync();

    expect(source, contains('relatedTopics: widget.detail.relatedTopics'));
  });
}
