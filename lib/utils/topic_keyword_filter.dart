import '../models/topic.dart';
import 'blocked_user_filter.dart';

/// 标题关键词过滤工具。
///
/// 关键词在 [PreferencesNotifier] 保存时已 trim + 去重；调用方需传入
/// `normalizedFilterKeywords`（已 lowercase）以避免重复归一化开销。
class TopicKeywordFilter {
  TopicKeywordFilter._();

  static const int autoLoadVisibleThreshold = 5;
  static const int autoLoadMaxAttempts = 3;

  /// 兼容旧调用：只统计已确认的过滤结果，不把待验证标题计为命中。
  static (List<Topic>, int, int) apply(
    List<Topic> topics, {
    required List<String> normalizedKeywords,
    required bool wholeWord,
    List<String> regexPatterns = const [],
    Map<String, bool>? regexMatches,
    Set<String> blockedUsernames = const <String>{},
  }) {
    final result = inspect(
      topics,
      normalizedKeywords: normalizedKeywords,
      wholeWord: wholeWord,
      regexPatterns: regexPatterns,
      regexMatches: regexMatches,
      blockedUsernames: blockedUsernames,
    );
    return (result.visible, result.hidden.length, result.hiddenByBlocked);
  }

  /// 仅检查已加载的话题，按屏蔽用户、字面关键词、已确认正则命中的顺序归因。
  /// 未验证标题仍暂不展示，但不计入已忽略数量；相同话题 ID 只统计一次。
  static TopicFilterResult inspect(
    List<Topic> topics, {
    required List<String> normalizedKeywords,
    required bool wholeWord,
    List<String> regexPatterns = const [],
    Map<String, bool>? regexMatches,
    Set<String> blockedUsernames = const <String>{},
  }) {
    // 未启用过滤时保留原列表身份，避免首页索引和滚动锚点缓存失效。
    // 已确认隐藏的记录仍使用不可变快照。
    if (normalizedKeywords.isEmpty &&
        regexPatterns.isEmpty &&
        blockedUsernames.isEmpty) {
      return TopicFilterResult._unfiltered(topics);
    }
    if (topics.isNotEmpty && regexPatterns.isNotEmpty && regexMatches == null) {
      throw StateError('正则过滤必须先在后台匹配');
    }
    final visible = <Topic>[];
    final hidden = <FilteredTopic>[];
    final pending = <Topic>[];
    final seen = <int>{};
    for (final topic in topics) {
      if (!seen.add(topic.id)) continue;
      if (BlockedUserFilter.isBlockedTopic(topic, blockedUsernames)) {
        hidden.add(FilteredTopic(topic, TopicFilterReason.blockedUser));
        continue;
      }
      final keyword = _matchingKeyword(
        topic.title,
        normalizedKeywords,
        wholeWord,
      );
      if (keyword != null) {
        hidden.add(
          FilteredTopic(topic, TopicFilterReason.keyword, keyword: keyword),
        );
      } else if (regexPatterns.isNotEmpty &&
          regexMatches![topic.title] == true) {
        hidden.add(FilteredTopic(topic, TopicFilterReason.regex));
      } else if (regexPatterns.isNotEmpty &&
          regexMatches![topic.title] == null) {
        pending.add(topic);
      } else {
        visible.add(topic);
      }
    }
    return TopicFilterResult(visible, hidden, pending);
  }

  // 字面匹配和 ASCII 完整词边界均无需在界面隔离区执行正则。
  // 用户表达式仅由后台工作隔离区计算。
  static String? _matchingKeyword(
    String title,
    List<String> keywords,
    bool wholeWord,
  ) {
    final lower = title.toLowerCase();
    for (final keyword in keywords) {
      if (keyword.isEmpty) continue;
      final needsBoundary = wholeWord && keyword.codeUnits.every(_isWordCode);
      var index = lower.indexOf(keyword);
      while (index >= 0) {
        final end = index + keyword.length;
        if (!needsBoundary ||
            ((index == 0 || !_isWordCode(lower.codeUnitAt(index - 1))) &&
                (end == lower.length || !_isWordCode(lower.codeUnitAt(end))))) {
          return keyword;
        }
        index = lower.indexOf(keyword, index + 1);
      }
    }
    return null;
  }

  static bool _isWordCode(int code) =>
      (code >= 0x30 && code <= 0x39) ||
      (code >= 0x41 && code <= 0x5A) ||
      (code >= 0x61 && code <= 0x7A) ||
      code == 0x5F;

  /// loadMore 完成后判断是否需要自动再加载一次。
  ///
  /// 当关键词命中率高时，单次 loadMore 实际新增可见条目很少，会让用户感到
  /// "划到底什么也没出来"。本判定在以下都满足时返回 true：
  /// - 仍有更多页（[hasMore]）
  /// - 本次 loadMore 的可见增量小于 [threshold]
  /// - 自动续加载次数未超 [maxAttempts]
  static bool shouldAutoLoadMore({
    required int visibleBefore,
    required int visibleAfter,
    required bool hasMore,
    required int attempts,
    int threshold = autoLoadVisibleThreshold,
    int maxAttempts = autoLoadMaxAttempts,
  }) {
    if (!hasMore) return false;
    if (attempts >= maxAttempts) return false;
    return (visibleAfter - visibleBefore) < threshold;
  }
}

/// 只有已确认的原因才能进入忽略数量和复核列表。
enum TopicFilterReason { blockedUser, keyword, regex }

class FilteredTopic {
  const FilteredTopic(this.topic, this.reason, {this.keyword});
  final Topic topic;
  final TopicFilterReason reason;
  final String? keyword;
}

class TopicFilterResult {
  TopicFilterResult(
    List<Topic> visible,
    List<FilteredTopic> hidden,
    List<Topic> pending,
  ) : visible = List.unmodifiable(visible),
      hidden = List.unmodifiable(hidden),
      pending = List.unmodifiable(pending);
  TopicFilterResult._unfiltered(this.visible)
    : hidden = const [],
      pending = const [];
  final List<Topic> visible;
  final List<FilteredTopic> hidden;
  final List<Topic> pending;
  int get hiddenByBlocked => hidden
      .where((entry) => entry.reason == TopicFilterReason.blockedUser)
      .length;
}
