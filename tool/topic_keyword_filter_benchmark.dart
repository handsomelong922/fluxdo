import 'dart:io';

import '../lib/utils/topic_keyword_matcher.dart';
import 'topic_keyword_matcher_smoke.dart' show baselineKeywordMatch;

/// 纯 Dart 桌面 CPU 微基准，不代表 Flutter 真机帧率。
/// 模拟 300 个屏蔽用户，40 页每页 30 条，分页后重建整个已加载列表。
void main(List<String> args) {
  final cold = args.contains('--cold');
  print('Dart ${Platform.version}; ${Platform.operatingSystem}');
  for (final count in [500, 1000]) {
    final rules = List.generate(count, (i) => 'keyword_$i');
    final blocked = Set<String>.from(List.generate(300, (i) => 'blocked_$i'));
    final titles = List.generate(
      1200,
      (i) =>
          i % 7 == 0 ? '测试 Keyword_${count - 1} 帖子 $i' : '正常话题，讨论软件开发及日常生活 $i',
    );
    final authors = List.generate(
      1200,
      (i) => i % 11 == 0 ? 'blocked_${i % 300}' : 'user_$i',
    );
    for (final wholeWord in [false, true]) {
      int run(bool indexed) {
        final watch = Stopwatch()..start();
        final matcher = indexed ? TopicKeywordMatcher(rules, wholeWord) : null;
        var hits = 0;
        for (var page = cold ? 40 : 1; page <= 40; page++) {
          if (indexed && !matcher!.hasRules(rules, wholeWord)) {
            throw StateError('规则缓存意外失效');
          }
          for (var i = 0; i < page * 30; i++) {
            if (blocked.contains(authors[i].trim().toLowerCase())) {
              hits++;
              continue;
            }
            final match = indexed
                ? matcher!.match(titles[i])
                : baselineKeywordMatch(titles[i], rules, wholeWord);
            if (match != null) hits++;
          }
        }
        watch.stop();
        if (hits != (cold ? 266 : 5447)) throw StateError('过滤命中计数不一致: $hits');
        return watch.elapsedMicroseconds;
      }

      run(false);
      run(true);
      final before = List.generate(7, (_) => run(false))..sort();
      final after = List.generate(7, (_) => run(true))..sort();
      print(
        '$count 关键词, 完整词=$wholeWord, 300 用户, '
        '${cold ? "冷批次 1200 次" : "分页 24600 次"}访问: '
        '基线 ${before[3]} us [${before.first}, ${before.last}]; '
        '索引+缓存 ${after[3]} us [${after.first}, ${after.last}]; '
        '${(before[3] / after[3]).toStringAsFixed(1)}x（7 次中位数，含构建）',
      );
    }
  }
}
