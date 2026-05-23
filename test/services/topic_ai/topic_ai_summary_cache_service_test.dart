import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/topic_ai/topic_ai_summary_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('TopicAiSummaryCacheService', () {
    test('saves and loads summary by topic id', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final service = TopicAiSummaryCacheService(prefs);
      final updatedAt = DateTime.utc(2026, 5, 24, 8, 30);

      await service.saveSummary(
        42,
        TopicSummary(
          summarizedText: 'cached summary',
          algorithm: 'custom-ai',
          outdated: true,
          canRegenerate: true,
          newPostsSinceSummary: 3,
          updatedAt: updatedAt,
        ),
      );

      final cached = service.getSummary(42);

      expect(cached, isNotNull);
      expect(cached!.summarizedText, 'cached summary');
      expect(cached.algorithm, 'custom-ai');
      expect(cached.outdated, isTrue);
      expect(cached.canRegenerate, isTrue);
      expect(cached.newPostsSinceSummary, 3);
      expect(cached.updatedAt?.toUtc(), updatedAt);
    });

    test('ignores malformed cache entries', () async {
      SharedPreferences.setMockInitialValues({
        'topic_ai_summary_cache_42': '{not-json',
      });
      final prefs = await SharedPreferences.getInstance();
      final service = TopicAiSummaryCacheService(prefs);

      expect(service.getSummary(42), isNull);
    });
  });
}
