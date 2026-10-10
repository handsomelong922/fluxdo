import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/topic.dart';
import '../services/ai_topic_summary_service.dart';
import '../services/ai_translation_service.dart';
import 'ai_post_review_provider.dart';
import 'core_providers.dart';

final aiTopicSummaryModelProvider = Provider<({AiProvider provider, AiModel model})?>((ref) {
  return resolveSelectedTextAiModel(ref, null);
});

/// 注入读取入口，测试不接触安全存储中的真实密钥。
final aiTopicSummaryApiKeyLoaderProvider = Provider<Future<String?> Function(String)>((ref) {
  return AiProviderListNotifier.getApiKey;
});

/// 总结自己的 Prompt 覆盖，默认仍取内置 summarize 快捷词。
const topicSummaryPromptKey = 'ai_topic_summary_prompt';
final aiTopicSummaryDefaultPromptProvider = Provider<String>((ref) {
  final presets = ref.watch(promptPresetListProvider);
  for (final preset in presets) {
    if (preset.id == 'builtin_text_summarize') return preset.promptTemplate;
  }
  return '请简要总结这个话题的主帖、回复要点、共识与分歧。';
});

typedef TopicSummaryServiceFactory = AiTopicSummaryService Function({
  required int topicId,
  required AiProvider provider,
  required AiModel model,
  required String apiKey,
});

final aiTopicSummaryServiceFactoryProvider = Provider<TopicSummaryServiceFactory>((ref) {
  final discourse = ref.watch(discourseServiceProvider);
  final chat = ref.watch(aiChatServiceProvider);
  final clientFactory = ref.watch(aiRequestClientFactoryProvider);
  SummaryPost convert(Post post) => SummaryPost(post.id, post.postNumber,
      post.username, AiTranslationService.extractPlainText(post.cooked));
  return ({required topicId, required provider, required model, required apiKey}) => AiTopicSummaryService(
    loadTopic: () async {
      // 不沿用当前阅读窗口或仅楼主/热门回复过滤后的 stream。
      final detail = await discourse.getTopicDetail(topicId);
      return SummarySnapshot(detail.title, detail.postStream.stream,
          detail.postStream.posts.map(convert).toList());
    },
    loadPosts: (ids) async => (await discourse.getPosts(topicId, ids)).posts.map(convert).toList(),
    generate: (instruction, content, cancellation) async {
      cancellation.check();
      final client = clientFactory();
      final done = Completer<String>();
      final buffer = StringBuffer();
      StreamSubscription<AiChatChunk>? subscription;
      void cancel() {
        client.close();
        unawaited(subscription?.cancel());
        if (!done.isCompleted) done.completeError(const TopicSummaryException('已取消总结'));
      }
      unawaited(cancellation.whenCancelled.then((_) {
        if (!done.isCompleted) cancel();
      }));
      try {
        subscription = chat.sendChatStream(
          provider: provider,
          model: model.id,
          apiKey: apiKey,
          systemPrompt: instruction,
          requestClient: client,
          messages: [AiChatMessage(id: 'topic-summary', role: ChatRole.user,
              content: content, createdAt: DateTime.now())],
        ).listen((chunk) {
          if (chunk is TextDelta) {
            buffer.write(chunk.text);
            if (buffer.length > 6000 && !done.isCompleted) {
              done.completeError(const TopicSummaryException('AI 输出过长，已停止，请缩短 Prompt 或更换模型'));
              client.close();
              unawaited(subscription?.cancel());
            }
          }
        }, onError: (Object error, StackTrace stack) {
          if (!done.isCompleted) done.completeError(error, stack);
        }, onDone: () {
          if (!done.isCompleted) done.complete(buffer.toString());
        });
        return await done.future.timeout(const Duration(minutes: 3));
      } finally {
        await subscription?.cancel();
        client.close();
      }
    },
  );
});
