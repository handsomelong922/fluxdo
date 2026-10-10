import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';

import '../models/topic.dart';
import '../constants.dart';
import '../services/ai_topic_summary_task.dart';
import 'theme_provider.dart';
import '../services/ai_topic_summary_service.dart';
import '../services/ai_translation_service.dart';
import 'ai_post_review_provider.dart';
import 'core_providers.dart';

final aiTopicSummaryModelProvider = Provider<({AiProvider provider, AiModel model})?>((ref) {
  return resolveSelectedTextAiModel(ref, null);
});

typedef TopicSummaryModel = ({AiProvider provider, AiModel model});
typedef TopicSummarySelectionScope = ({String account, int topicId});
const _summaryModelChoicesKey = 'ai_topic_summary_model_choices_v1';

String _selectionKey(TopicSummarySelectionScope scope) =>
    sha256.convert(utf8.encode(jsonEncode([scope.account, scope.topicId]))).toString();

Map<String, dynamic> _readSummaryModelChoices(String? raw) {
  try { return Map<String, dynamic>.from(jsonDecode(raw ?? '{}') as Map); }
  catch (_) { return {}; }
}

TopicSummaryModel? _findSummaryModel(List<TopicSummaryModel> models, String? key) {
  final parsed = parseAiModelKey(key);
  if (parsed == null) return null;
  for (final item in models) {
    if (item.provider.id == parsed.providerId && item.model.id == parsed.modelId &&
        item.model.output.contains(Modality.text)) return item;
  }
  return null;
}

/// 非敏感的选模偏好按账号/站点/话题保存，重进页面后仍能找到同一总结缓存。
final aiTopicSummarySelectionProvider = StateProvider.family<
    TopicSummaryModel?, TopicSummarySelectionScope>((ref, scope) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final saved = _readSummaryModelChoices(prefs.getString(_summaryModelChoicesKey))[_selectionKey(scope)];
  if (saved is! String) return null;
  return _findSummaryModel(ref.watch(allAvailableAiModelsProvider), saved);
});

final aiTopicSummaryResolvedModelProvider = Provider.family<TopicSummaryModel?, int>((ref, topicId) {
  final account = ref.watch(aiTopicSummaryAccountProvider);
  final selected = ref.watch(topicSelectedAiModelProvider(topicId));
  final remembered = ref.watch(aiTopicSummarySelectionProvider((account: account, topicId: topicId)));
  final available = ref.watch(allAvailableAiModelsProvider);
  TopicSummaryModel? valid(TopicSummaryModel? item) => item == null ? null :
      _findSummaryModel(available, buildAiModelKey(item.provider.id, item.model.id));
  return valid(selected) ?? valid(remembered) ??
      _findSummaryModel(available, ref.watch(defaultTextAiModelKeyProvider)) ??
      _findSummaryModel(available, ref.watch(defaultAiModelKeyProvider)) ??
      valid(ref.watch(lastUsedTextAiModelProvider)) ??
      valid(ref.watch(lastUsedAiAssistantModelProvider)) ??
      ref.watch(aiTopicSummaryModelProvider);
});

Future<void> rememberTopicSummaryModel(WidgetRef ref, int topicId, TopicSummaryModel model) async {
  final scope = (account: ref.read(aiTopicSummaryAccountProvider), topicId: topicId);
  final prefs = ref.read(sharedPreferencesProvider);
  final choices = _readSummaryModelChoices(prefs.getString(_summaryModelChoicesKey));
  final key = _selectionKey(scope);
  choices.remove(key);
  choices[key] = buildAiModelKey(model.provider.id, model.model.id);
  while (choices.length > 100) { choices.remove(choices.keys.first); }
  ref.read(aiTopicSummarySelectionProvider(scope).notifier).state = model;
  ref.read(topicSelectedAiModelProvider(topicId).notifier).state = model;
  // 同时沿用现有助手选模记忆，不创建新的凭据或连接。
  await Future.wait([
    prefs.setString(_summaryModelChoicesKey, jsonEncode(choices)),
    setLastUsedAiAssistantModel(ref, model.provider.id, model.model.id, isImageMode: false),
  ]);
}

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

/// 账号切换时重建；生命周期不属于总结面板。
final aiTopicSummaryAccountProvider = Provider<String>((ref) {
  ref.watch(currentUserProvider);
  final user = ref.watch(discourseServiceProvider).currentUserNotifier;
  void changed() => ref.invalidateSelf();
  user.addListener(changed);
  ref.onDispose(() => user.removeListener(changed));
  return '${AppConstants.baseUrl}:${user.value?.id ?? "guest"}';
});

final aiTopicSummaryTasksProvider = Provider<AiTopicSummaryTasks>((ref) {
  ref.watch(aiTopicSummaryAccountProvider);
  final prefs = ref.watch(sharedPreferencesProvider);
  final tasks = AiTopicSummaryTasks(
    readCache: (key) => key.startsWith('private_') ? null : prefs.getString(key),
    writeCache: (key, value) async {
      if (key.startsWith('private_')) return true;
      final saved = await prefs.setString(key, value);
      if (!saved) return false;
      // 所有账号合计最多保留 100 个快照，避免不断切换 Prompt 无限增长。
      final keys = prefs.getKeys().where((k) => k.startsWith('ai_topic_summary_v1_')).toList();
      int savedAt(String k) {
        try { return (jsonDecode(prefs.getString(k)!) as Map<String, dynamic>)['savedAtMillis'] as int; }
        catch (_) { return 0; }
      }
      final excess = (keys.length - 100).clamp(0, keys.length);
      keys.remove(key);
      keys.sort((a, b) => savedAt(a).compareTo(savedAt(b)));
      for (final old in keys.take(excess)) {
        await prefs.remove(old);
      }
      return true;
    },
  );
  ref.onDispose(tasks.dispose);
  return tasks;
});

String topicSummaryTaskKey({required String account, required int topicId,
  required AiProvider provider, required AiModel model, required String prompt,
  bool isPrivateMessage = false}) {
  final identity = jsonEncode([account, topicId, provider.id, provider.baseUrl,
    provider.type.name, model.id, prompt.trim()]);
  return '${isPrivateMessage ? "private_" : ""}ai_topic_summary_v1_${sha256.convert(utf8.encode(identity))}';
}
