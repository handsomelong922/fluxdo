import 'dart:math';

import '../lib/utils/topic_keyword_matcher.dart';

/// 基线算法来自优化前的 TopicKeywordFilter，供语义对照及桌面微基准使用。
String? baselineKeywordMatch(
  String title,
  List<String> keywords,
  bool wholeWord,
) {
  final lower = title.toLowerCase();
  for (final keyword in keywords) {
    if (keyword.isEmpty) continue;
    final boundary = wholeWord && keyword.codeUnits.every(isWordCode);
    var index = lower.indexOf(keyword);
    while (index >= 0) {
      final end = index + keyword.length;
      if (!boundary ||
          ((index == 0 || !isWordCode(lower.codeUnitAt(index - 1))) &&
              (end == lower.length || !isWordCode(lower.codeUnitAt(end))))) {
        return keyword;
      }
      index = lower.indexOf(keyword, index + 1);
    }
  }
  return null;
}

bool isWordCode(int code) =>
    (code >= 48 && code <= 57) ||
    (code >= 65 && code <= 90) ||
    (code >= 97 && code <= 122) ||
    code == 95;

void check(bool result, String message) {
  if (!result) throw StateError(message);
}

void main() {
  final random = Random(20261015);
  const alphabet = ['a', 'b', 'C', '_', '1', ' ', '中', '😀', '.', 'é', 'İ'];
  String text(int length) => List.generate(
    length,
    (_) => alphabet[random.nextInt(alphabet.length)],
  ).join();
  var cases = 0;
  for (final wholeWord in [false, true]) {
    for (var batch = 0; batch < 60; batch++) {
      final rules = List.generate(
        100,
        (_) => text(random.nextInt(8)).toLowerCase(),
      );
      final matcher = TopicKeywordMatcher(rules, wholeWord);
      for (var i = 0; i < 120; i++) {
        final title = text(random.nextInt(80));
        final expected = baselineKeywordMatch(title, rules, wholeWord);
        check(matcher.match(title) == expected, '首次匹配语义不一致');
        check(matcher.match(title) == expected, '缓存匹配语义不一致');
        cases++;
      }
    }
  }
  final rules = ['later', 'early', 'abc', 'ab', '', 'early'];
  final matcher = TopicKeywordMatcher(rules, true);
  check(matcher.match('early later') == 'later', '应按规则顺序归因');
  check(matcher.match('xabc abc') == 'abc', '应继续查找满足边界的位置');
  check(matcher.match('early') == 'early', '首次标题');
  check(matcher.match('visible') == null, '更新标题不能继承命中');
  rules[0] = 'changed';
  check(!matcher.hasRules(rules, true), '原地修改规则必须失效');
  check(!matcher.hasRules(matcher.keywords, false), '完整词开关必须失效');
  for (var i = 0; i < 3000; i++) {
    check(matcher.match('visible $i') == null, '缓存淘汰期间错误');
  }
  check(matcher.match('early later') == 'later', '淘汰后重算错误');
  check(matcher.match('${' ' * 262145}early') == 'early', '超长标题不能截断');
  final longRules = ['${'a' * 4000}b', 'aa'];
  final longTitle = '${'a' * 8000}b';
  for (final wholeWord in [false, true]) {
    check(
      TopicKeywordMatcher(longRules, wholeWord).match(longTitle) ==
          baselineKeywordMatch(longTitle, longRules, wholeWord),
      '长共同前缀回退必须保留首条规则归因与边界',
    );
  }
  print('PASS: $cases 随机语义对照，重复/边界/归因/换代/淘汰/超长标题');
}
