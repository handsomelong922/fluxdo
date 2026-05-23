import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/topic_ai/topic_ai_context_status.dart';

void main() {
  group('TopicAiContextStatusBuilder', () {
    const builder = TopicAiContextStatusBuilder();

    test('reports complete loaded context', () {
      final status = builder.build(
        scope: ContextScope.first5,
        loadedPosts: 5,
        totalPosts: 12,
        isLoading: false,
        hasTopicDetail: true,
      );

      expect(status.expectedPosts, 5);
      expect(status.loadedPosts, 5);
      expect(status.isComplete, isTrue);
      expect(status.isPartial, isFalse);
      expect(status.semanticState, 'complete');
    });

    test('reports partial context before all expected posts are loaded', () {
      final status = builder.build(
        scope: ContextScope.first10,
        loadedPosts: 3,
        totalPosts: 10,
        isLoading: false,
        hasTopicDetail: true,
      );

      expect(status.expectedPosts, 10);
      expect(status.loadedPosts, 3);
      expect(status.isPartial, isTrue);
      expect(status.semanticState, 'partial');
    });

    test('reports unavailable without topic detail', () {
      final status = builder.build(
        scope: ContextScope.all,
        loadedPosts: 20,
        totalPosts: 20,
        isLoading: false,
        hasTopicDetail: false,
      );

      expect(status.expectedPosts, 0);
      expect(status.loadedPosts, 0);
      expect(status.isUnavailable, isTrue);
      expect(status.semanticState, 'unavailable');
    });

    test('loading state takes display priority', () {
      final status = builder.build(
        scope: ContextScope.firstPostOnly,
        loadedPosts: 0,
        totalPosts: 6,
        isLoading: true,
        hasTopicDetail: true,
      );

      expect(status.expectedPosts, 1);
      expect(status.semanticState, 'loading');
    });
  });
}
