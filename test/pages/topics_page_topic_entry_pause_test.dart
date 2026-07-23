import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('home topic push pauses excerpt work before navigation', () {
    final source = File('lib/pages/topics_page.dart').readAsStringSync();

    expect(source, contains('runWhilePaused'));
    expect(source, contains('buildTopicDetailRoute<void>'));
  });
}
