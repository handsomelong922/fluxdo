import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/topic.dart';
import '../../providers/theme_provider.dart';
import '../../utils/time_utils.dart';

class TopicAiSummaryCacheService {
  TopicAiSummaryCacheService(this._prefs);

  static const _keyPrefix = 'topic_ai_summary_cache_';

  final SharedPreferences _prefs;

  CachedTopicSummary? getCachedSummary(int topicId) {
    final raw = _prefs.getString('$_keyPrefix$topicId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final summary = TopicSummary(
        summarizedText: json['summarized_text'] as String? ?? '',
        algorithm: json['algorithm'] as String?,
        outdated: json['outdated'] as bool? ?? false,
        canRegenerate: json['can_regenerate'] as bool? ?? true,
        newPostsSinceSummary: json['new_posts_since_summary'] as int? ?? 0,
        updatedAt: TimeUtils.parseUtcTime(json['updated_at'] as String?),
      );
      return CachedTopicSummary(
        summary: summary,
        postsCount: json['posts_count'] as int?,
      );
    } catch (_) {
      return null;
    }
  }

  TopicSummary? getSummary(int topicId) => getCachedSummary(topicId)?.summary;

  Future<void> saveSummary(
    int topicId,
    TopicSummary summary, {
    int? postsCount,
  }) async {
    final updatedAt = summary.updatedAt?.toIso8601String();
    final json = {
      'summarized_text': summary.summarizedText,
      if (summary.algorithm != null) 'algorithm': summary.algorithm,
      'outdated': summary.outdated,
      'can_regenerate': summary.canRegenerate,
      'new_posts_since_summary': summary.newPostsSinceSummary,
    };
    if (postsCount != null) json['posts_count'] = postsCount;
    if (updatedAt != null) json['updated_at'] = updatedAt;

    await _prefs.setString('$_keyPrefix$topicId', jsonEncode(json));
  }
}

class CachedTopicSummary {
  const CachedTopicSummary({required this.summary, required this.postsCount});

  final TopicSummary summary;
  final int? postsCount;

  bool isPossiblyOutdated({required int currentPostsCount, int threshold = 5}) {
    final cachedCount = postsCount;
    if (cachedCount == null || currentPostsCount <= cachedCount) return false;
    return currentPostsCount - cachedCount >= threshold;
  }
}

final topicAiSummaryCacheServiceProvider = Provider<TopicAiSummaryCacheService>(
  (ref) => TopicAiSummaryCacheService(ref.watch(sharedPreferencesProvider)),
);
