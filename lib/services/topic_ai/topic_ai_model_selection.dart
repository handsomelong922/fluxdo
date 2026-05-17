import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef TopicAiModelSelection = ({AiProvider provider, AiModel model});

Future<bool> hasConfiguredTopicAiModel(
  TopicAiModelSelection? selection, {
  Future<String?> Function(String providerId) readApiKey =
      AiProviderListNotifier.getApiKey,
}) async {
  if (selection == null) {
    return false;
  }

  final apiKey = await readApiKey(selection.provider.id);
  return apiKey?.trim().isNotEmpty == true;
}

({AiProvider provider, AiModel model})? resolveTopicAiModel(
  WidgetRef ref,
  int topicId,
) {
  final selected = ref.read(topicSelectedAiModelProvider(topicId));
  final defaultModel = ref.read(defaultAiModelProvider);
  final lastUsed = ref.read(lastUsedAiAssistantModelProvider);
  return selected ?? defaultModel ?? lastUsed;
}

({AiProvider provider, AiModel model})? resolveTopicAiModelFromRef(
  Ref ref,
  int topicId,
) {
  final selected = ref.read(topicSelectedAiModelProvider(topicId));
  final defaultModel = ref.read(defaultAiModelProvider);
  final lastUsed = ref.read(lastUsedAiAssistantModelProvider);
  return selected ?? defaultModel ?? lastUsed;
}

final hasConfiguredTopicAiModelProvider = FutureProvider.autoDispose
    .family<bool, int>((ref, topicId) async {
      return hasConfiguredTopicAiModel(
        resolveTopicAiModelFromRef(ref, topicId),
      );
    });

Future<void> rememberTopicAiModel(
  WidgetRef ref,
  int topicId,
  ({AiProvider provider, AiModel model}) model,
) async {
  ref.read(topicSelectedAiModelProvider(topicId).notifier).state = model;
  await setLastUsedAiAssistantModel(ref, model.provider.id, model.model.id);
}
