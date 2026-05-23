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

  TopicSummary? getSummary(int topicId) {
    final raw = _prefs.getString('$_keyPrefix$topicId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return TopicSummary(
        summarizedText: json['summarized_text'] as String? ?? '',
        algorithm: json['algorithm'] as String?,
        outdated: json['outdated'] as bool? ?? false,
        canRegenerate: json['can_regenerate'] as bool? ?? true,
        newPostsSinceSummary: json['new_posts_since_summary'] as int? ?? 0,
        updatedAt: TimeUtils.parseUtcTime(json['updated_at'] as String?),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSummary(int topicId, TopicSummary summary) async {
    await _prefs.setString(
      '$_keyPrefix$topicId',
      jsonEncode({
        'summarized_text': summary.summarizedText,
        if (summary.algorithm != null) 'algorithm': summary.algorithm,
        'outdated': summary.outdated,
        'can_regenerate': summary.canRegenerate,
        'new_posts_since_summary': summary.newPostsSinceSummary,
        if (summary.updatedAt != null)
          'updated_at': summary.updatedAt!.toIso8601String(),
      }),
    );
  }
}

final topicAiSummaryCacheServiceProvider = Provider<TopicAiSummaryCacheService>(
  (ref) => TopicAiSummaryCacheService(ref.watch(sharedPreferencesProvider)),
);
