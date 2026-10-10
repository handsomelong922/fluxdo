import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final page in [
    'topics_page',
    'category_topics_page',
    'tag_topics_page',
  ]) {
    test('$page 显示与续加载使用相同正则规则，修改后重置续加载冷却', () {
      final source = File('lib/pages/$page.dart').readAsStringSync();
      expect(source, contains('Future<int> visibleItemCount() async'));
      expect(source, contains('await _regexFilter.settle('));
      expect(source, contains('_regexFilter.prepare(regexPatterns,'));
      expect(
        RegExp(r'regexMatches: _regexFilter.matches').allMatches(source),
        hasLength(2),
      );
      expect(source, contains('TopicKeywordFilter.inspect('));
      expect(source, contains('hiddenTopics:'));
      expect(source, contains('if (mounted) _openTopic(topic)'));
      expect(source, isNot(contains('hiddenCount: hidden')));
      expect(source, contains('TopicRegexFilterStatus('));
      expect(source, contains('_regexFilter.dispose()'));

      expect(
        RegExp(r'regexPatterns: regexPatterns').allMatches(source),
        hasLength(2),
      );
      expect(
        source,
        contains('final regexPatterns = prefs.topicFilterRegexPatterns'),
      );
      expect(
        source,
        contains(
          'preferencesProvider.select((p) => p.topicFilterRegexPatterns)',
        ),
      );
      expect(
        source,
        contains('regexPatterns.isNotEmpty || blockedUsernames.isNotEmpty'),
      );
      expect(
        source,
        contains('listEquals(_lastAutoLoadRegexPatterns, regexPatterns)'),
      );
      expect(
        source,
        contains(
          '_lastAutoLoadRegexPatterns = List.unmodifiable(regexPatterns)',
        ),
      );
      expect(
        source,
        contains(
          '_syncAutoLoadFilter(keywords, regexPatterns, wholeWord, blockedUsernames)',
        ),
      );
    });
  }
}
