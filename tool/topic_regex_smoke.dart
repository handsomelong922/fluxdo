import 'dart:async';
import 'dart:collection';

import '../lib/utils/topic_regex_rules.dart';

/// Flutter 单测和无依赖命令行检查共用真实隔离任务，避免两套用例漂移。
final topicRegexSmokeTests = <String, Future<void> Function()>{
  '支持完整分组、多个通配段和大小写无关匹配': () async {
    await _matches(
      [r'^(求助|提问).*(手机|电脑).*AI$'],
      ['求助：手机使用 ai', '分享：手机使用 AI', '提问电脑 AI 后缀'],
      [true, false, false],
    );
    await _matches(
      [r'\b(?:AI|GPT)-\d{1,3}\b'],
      ['使用 gpt-123 工具', 'XAI-12', 'AI-1234'],
      [true, false, false],
    );
  },
  '支持正向和负向环视': () async {
    await _matches(
      [r'(?<=prefix)(?!bad)[a-z]+(?=suffix)'],
      ['prefixGOODsuffix', 'prefixbadsuffix', 'GOODSuffiX'],
      [true, false, false],
    );
    await _matches(
      [r'(?<!prefix)\bword\b(?!suffix)'],
      ['word', 'prefixword', 'wordsuffix'],
      [true, false, false],
    );
  },
  '支持数字反向引用和命名分组反向引用': () async {
    await _matches([r'^(ab|cd)\1$'], ['abab', 'cdCD', 'abcd'], [
      true,
      true,
      false,
    ]);
    await _matches(
      [r'(?<=prefix)(?<word>[a-z]+)\k<word>(?=$)'],
      ['prefixAbAb', 'prefixxyXY', 'prefixabac'],
      [true, true, false],
    );
  },
  '保留全部空白和完整标题，不截断也不修剪': () async {
    await _matches([' word '], ['word', ' word ', 'x word x'], [
      false,
      true,
      true,
    ]);
    await _matches([' '], ['word', ' '], [false, true]);
    await _matches([r'^a+$'], ['a' * 70000, '${'a' * 70000}!'], [true, false]);
  },
  '长规则和大重复次数不再受旧状态机上限约束': () async {
    final longPattern = 'x' * 8192;
    await _matches(['^$longPattern\$'], [longPattern, '${longPattern}y'], [
      true,
      false,
    ]);
    await _matches([r'^a{4096}$'], ['a' * 4096, 'a' * 4095], [true, false]);
    await TopicRegexRules.validate([
      for (var i = 0; i < 4; i++) 'a' * TopicRegexRules.maxPatternLength,
    ]);
    await TopicRegexRules.validate(List.filled(TopicRegexRules.maxRules, 'a'));
  },
  '每个标题返回任意规则匹配结果，空列表保持明确语义': () async {
    await _matches([r'^one$', r'^two$'], ['one', 'two', 'three'], [
      true,
      true,
      false,
    ]);
    await _matches([], ['one', 'two'], [false, false]);
    await _matches([r'a'], [], []);
    await TopicRegexRules.validate([]);
  },
  '无效语法明确失败，并保留 Dart 解析错误详情': () async {
    for (final pattern in [
      '[',
      '(',
      'a{3,2}',
      '(?<bad',
      r'(?<x>a)\k<missing>',
    ]) {
      final error = await _error(TopicRegexRules.validate([pattern]), 'syntax');
      _check(
        error.source is String && (error.source as String).isNotEmpty,
        '语法错误应保留解析详情：$pattern',
      );
    }
    // 即使前面的规则已命中，也不能悄悄跳过后面的坏规则。
    await _error(TopicRegexRules.match(['one', '['], ['one']).result, 'syntax');
  },
  '数量、单条长度和总长度越界全部拒绝，不截取前缀': () async {
    await _error(TopicRegexRules.validate(['']), 'length');
    await _error(
      TopicRegexRules.validate(['a' * (TopicRegexRules.maxPatternLength + 1)]),
      'length',
    );
    await _error(
      TopicRegexRules.validate(List.filled(TopicRegexRules.maxRules + 1, 'a')),
      'count',
    );
    await _error(
      TopicRegexRules.validate([
        for (var i = 0; i < 4; i++) 'a' * TopicRegexRules.maxPatternLength,
        'a',
      ]),
      'total',
    );
    await _error(
      TopicRegexRules.match(List.filled(33, 'a'), ['a']).result,
      'count',
    );
  },
  '输入快照异常明确失败，不返回部分结果': () async {
    await _error(TopicRegexRules.match(_BrokenList(), ['a']).result, 'worker');
  },
  '任务使用不可变输入快照': () async {
    final patterns = ['^a\$'];
    final titles = ['a', 'b'];
    final job = TopicRegexRules.match(patterns, titles);
    patterns[0] = '[';
    titles[0] = 'b';
    _same(await job.result, [true, false]);
    // 已完成后的重复取消不能更改成功结果。
    job.cancel();
    job.cancel();
    _same(await job.result, [true, false]);
  },
  '立即取消处理尚未启动的隔离任务，且取消可重复调用': () async {
    final job = TopicRegexRules.match([r'^(a+)+$'], ['${'a' * 20000}!']);
    final error = _error(job.result, 'cancelled');
    job.cancel();
    job.cancel();
    await error;
    await _matches(['fresh'], ['FRESH'], [true]);
  },
  '运行中的恶意回溯可取消，主事件循环仍可响应': () async {
    final job = TopicRegexRules.match([r'^(a|aa)+$'], ['${'a' * 20000}!']);
    final error = _error(job.result, 'cancelled');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    job.cancel();
    await error;
    await _matches(['fresh'], ['FRESH'], [true]);
  },
  '恶意回溯触发硬超时并终止工作隔离区': () async {
    var ticks = 0;
    final pulse = Timer.periodic(
      const Duration(milliseconds: 20),
      (_) => ticks++,
    );
    final stopwatch = Stopwatch()..start();
    try {
      await _error(
        TopicRegexRules.match([r'^(a+)+$'], ['${'a' * 20000}!']).result,
        'timeout',
      );
    } finally {
      pulse.cancel();
    }
    _check(ticks >= 3, '正则不能阻塞主隔离区的计时器');
    _check(
      stopwatch.elapsed <
          TopicRegexRules.jobTimeout + const Duration(seconds: 3),
      '超时后应及时释放任务',
    );
    await _matches(['fresh'], ['FRESH'], [true]);
  },
  '与 Dart 原生正则逐条交叉验证': () async {
    final patterns = [
      r'a',
      r'a*',
      r'^(ab|a)+$',
      r'(?:ab)?c',
      r'[a-c]{1,3}',
      r'\bAI\b',
      r'a.*b.*c',
      r'[^x]+$',
      r'(ab){2,3}',
      r'(手机|电脑).*(求助|提问)',
      r'^[中文]+$',
      r'\u4e2d',
      r'\x61',
      r'\Bai\B',
      r'^.$',
      r'[A-Z]+',
      r'[^中]+',
      r'\s+字',
      r'(?=ab)ab',
      r'(?<!x)ab',
      r'(ab)\1',
      r'(?<letter>[a-z])\k<letter>',
      r'a|',
      r'colou?r',
      r'a+?b',
    ];
    final texts = [
      '',
      'abc',
      'abab',
      'aaa!',
      'xabc',
      'AI tools',
      'XAI',
      'ababc',
      'axbyc',
      'xxx',
      'hello\n',
      '电脑：提问',
      '中文',
      '中',
      '😀',
      'é',
      'É',
      'K',
      'ſ',
      '\r\n',
      '字',
      ' 字',
      'main',
      'color',
    ];
    for (final pattern in patterns) {
      // 这里只交叉验证已知短小测试常量，生产代码不会在主隔离区编译用户规则。
      final native = RegExp(pattern, caseSensitive: false);
      await _matches([pattern], texts, texts.map(native.hasMatch).toList());
    }
  },
};

Future<void> main() async {
  var passed = 0;
  for (final entry in topicRegexSmokeTests.entries) {
    await entry.value();
    passed++;
    print('PASS ${entry.key}');
  }
  print('$passed 个正则烟雾测试全部通过');
}

Future<void> _matches(
  List<String> patterns,
  List<String> titles,
  List<bool> expected,
) async {
  _same(await TopicRegexRules.match(patterns, titles).result, expected);
}

void _same(List<bool> actual, List<bool> expected) {
  _check(actual.length == expected.length, '匹配结果长度不同：$actual / $expected');
  for (var i = 0; i < expected.length; i++) {
    _check(actual[i] == expected[i], '第 $i 个匹配结果不同：$actual / $expected');
  }
}

Future<FormatException> _error(Future<Object?> result, String category) async {
  try {
    await result;
  } on FormatException catch (error) {
    _check(error.message == category, '预期 $category 错误，实际为 $error');
    return error;
  }
  throw StateError('预期 $category 错误，但任务成功');
}

void _check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

class _BrokenList extends ListBase<String> {
  @override
  int get length => 1;

  @override
  set length(int value) => throw UnsupportedError('只读测试数据');

  @override
  String operator [](int index) => throw StateError('模拟输入快照失败');

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('只读测试数据');
}
