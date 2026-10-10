import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/utils/topic_regex_rules.dart';

void main() {
  test('复杂分组、多个通配段与大小写无关匹配', () {
    final rule = TopicRegexRules.compile(r'^(求助|提问).*(手机|电脑).*AI$');
    expect(rule.hasMatch('求助：手机使用 ai'), isTrue);
    expect(rule.hasMatch('分享：手机使用 AI'), isFalse);
    expect(rule.hasMatch('提问电脑 AI 后缀'), isFalse);
  });

  test('支持非捕获分组、字符类、边界和重复次数', () {
    final rule = TopicRegexRules.compile(r'\b(?:AI|GPT)-\d{1,3}\b');
    expect(rule.hasMatch('使用 gpt-123 工具'), isTrue);
    expect(rule.hasMatch('XAI-12'), isFalse);
    expect(rule.hasMatch('AI-1234'), isFalse);
    expect(TopicRegexRules.compile(r'colou?r').hasMatch('color'), isTrue);
    expect(TopicRegexRules.compile(r'a+?b').hasMatch('aaab'), isTrue);
  });

  test('转义字符、空分支与中文字符类', () {
    expect(TopicRegexRules.compile(r'a\.b').hasMatch('a.b'), isTrue);
    expect(TopicRegexRules.compile(r'a\.b').hasMatch('axb'), isFalse);
    expect(TopicRegexRules.compile(r'^[中文]+$').hasMatch('中文中'), isTrue);
    expect(TopicRegexRules.compile(r'a|').hasMatch('anything'), isTrue);
  });

  test('无效或不支持的语法在保存前报错', () {
    for (final pattern in ['[', '(', 'a{3,2}', r'(a)\1', '(?=a)', '(?<=a)']) {
      expect(() => TopicRegexRules.compile(pattern), throwsFormatException,
          reason: pattern);
    }
    expect(() => TopicRegexRules.compile('a{65}'), throwsFormatException);
    expect(() => TopicRegexRules.compile('a' * 2049), throwsFormatException);
    expect(() => TopicRegexRules.validate(List.filled(33, 'a')),
        throwsFormatException);
  });

  test('导入损坏规则不会导致过滤崩溃', () {
    final rules = TopicRegexRules.compileValid(['[', r'^AI$', '(?=bad)']);
    expect(rules.length, 1);
    expect(rules.single.hasMatch('ai'), isTrue);
  });

  test('嵌套重复及歧义分支不会走指数回溯', () {
    final text = '${'a' * 2000}!';
    expect(TopicRegexRules.compile(r'^(a+)+$').hasMatch(text), isFalse);
    expect(TopicRegexRules.compile(r'^(a|aa)+$').hasMatch(text), isFalse);
    expect(TopicRegexRules.compile(r'a*a*a*b').hasMatch(text), isFalse);
  });

  test('编译状态与总复杂度有界，超长标题不截断后误匹配', () {
    expect(() => TopicRegexRules.compile('(abc){64}{2}'), throwsFormatException);
    expect(() => TopicRegexRules.compile('(abcdefghij){64}'), throwsFormatException);
    expect(() => TopicRegexRules.validate(List.generate(24, (i) => '${'a' * 100}$i')),
        throwsFormatException);
    expect(TopicRegexRules.compile(r'^a+$').hasMatch('a' * 4096), isTrue);
    expect(TopicRegexRules.compile(r'^a+$').hasMatch('a' * 4097), isFalse);
  });

  test('32条规则与100个不同长标题在有界工作量内完成', () {
    final rules = List.generate(32, (index) =>
        TopicRegexRules.compile('^(a|aa)+b$index'));
    final stopwatch = Stopwatch()..start();
    for (var index = 0; index < 100; index++) {
      final title = '${'a' * 255}!$index';
      expect(rules.any((rule) => rule.hasMatch(title)), isFalse);
    }
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('与 Dart 正则支持的子集交叉验证', () {
    final patterns = [r'a', r'a*', r'^(ab|a)+$', r'(?:ab)?c',
      r'[a-c]{1,3}', r'\bAI\b', r'a.*b.*c', r'[^x]+$', r'(ab){2,3}',
      r'(手机|电脑).*(求助|提问)', r'^[中文]+$', r'\u4e2d', r'\x61',
      r'\Bai\B', r'^.$', r'[A-Z]+', r'[^中]+', r'(a*)*b', r'\s+字'];
    final texts = ['', 'abc', 'abab', 'aaa!', 'xabc', 'AI tools', 'XAI',
      'ababc', 'axbyc', 'xxx', 'hello\n', '电脑：提问', '中文',
      '中', '😀', 'é', 'É', 'K', 'ſ', '\r\n', '字', ' 字', 'main' ];
    for (final pattern in patterns) {
      final actual = TopicRegexRules.compile(pattern);
      final expected = RegExp(pattern, caseSensitive: false);
      for (final text in texts) {
        expect(actual.hasMatch(text), expected.hasMatch(text),
            reason: '$pattern / $text');
      }
    }
  });
}
