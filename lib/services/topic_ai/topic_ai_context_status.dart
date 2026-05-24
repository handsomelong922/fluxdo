import 'package:ai_model_manager/ai_model_manager.dart';

import 'topic_ai_context_service.dart';

class TopicAiContextStatus {
  const TopicAiContextStatus({
    required this.scope,
    required this.loadedPosts,
    required this.expectedPosts,
    required this.totalPosts,
    required this.isLoading,
    required this.hasTopicDetail,
  });

  final ContextScope scope;
  final int loadedPosts;
  final int expectedPosts;
  final int totalPosts;
  final bool isLoading;
  final bool hasTopicDetail;

  bool get isUnavailable => !hasTopicDetail || expectedPosts <= 0;
  bool get isComplete => !isUnavailable && loadedPosts >= expectedPosts;
  bool get isPartial => !isUnavailable && loadedPosts > 0 && !isComplete;

  String get semanticState {
    if (!hasTopicDetail) return 'unavailable';
    if (isLoading) return 'loading';
    if (isComplete) return 'complete';
    if (isPartial) return 'partial';
    return 'empty';
  }
}

class TopicAiContextStatusBuilder {
  const TopicAiContextStatusBuilder({
    this.contextService = const TopicAiContextService(),
  });

  final TopicAiContextService contextService;

  TopicAiContextStatus build({
    required ContextScope scope,
    required int loadedPosts,
    required int totalPosts,
    required bool isLoading,
    required bool hasTopicDetail,
  }) {
    final normalizedTotal = totalPosts < 0 ? 0 : totalPosts;
    final expectedPosts = hasTopicDetail
        ? contextService.postCountForScope(scope, normalizedTotal)
        : 0;
    return TopicAiContextStatus(
      scope: scope,
      loadedPosts: loadedPosts.clamp(0, expectedPosts),
      expectedPosts: expectedPosts,
      totalPosts: normalizedTotal,
      isLoading: isLoading,
      hasTopicDetail: hasTopicDetail,
    );
  }
}
