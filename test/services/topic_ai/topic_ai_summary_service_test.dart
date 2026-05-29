import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/topic_ai/topic_ai_summary_service.dart';

void main() {
  group('TopicAiSummaryService web search config', () {
    test('keeps model features when web search is already enabled', () {
      const base = AiModelFeatureConfig(
        webSearchEnabled: true,
        webSearchContextSize: AiWebSearchContextSize.low,
        webSearchMaxUses: 2,
      );

      final config = TopicAiSummaryService.summaryFeatureConfig(base, '总结这个帖子');

      expect(config.webSearchEnabled, isTrue);
      expect(config.webSearchContextSize, AiWebSearchContextSize.low);
      expect(config.webSearchMaxUses, 2);
    });

    test('enables high context web search for latest-information prompts', () {
      const base = AiModelFeatureConfig();

      final config = TopicAiSummaryService.summaryFeatureConfig(
        base,
        '请联网搜索最新消息后总结全部回帖',
      );

      expect(config.webSearchEnabled, isTrue);
      expect(config.webSearchContextSize, AiWebSearchContextSize.high);
    });

    test('does not enable web search for ordinary summary prompts', () {
      const base = AiModelFeatureConfig();

      final config = TopicAiSummaryService.summaryFeatureConfig(base, '总结全部回帖');

      expect(config.webSearchEnabled, isFalse);
    });
  });
}
