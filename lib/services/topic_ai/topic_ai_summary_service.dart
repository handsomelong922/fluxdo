import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/topic.dart';
import '../settings/ai_prompt_settings_service.dart';
import 'topic_ai_context_service.dart';
import 'topic_ai_model_selection.dart';

class TopicAiSummaryService {
  TopicAiSummaryService(this._ref);

  final Ref _ref;

  Future<TopicSummary> generateSummary({
    required int topicId,
    required TopicDetail detail,
    List<TopicAiContextPost> cachedPosts = const [],
  }) async {
    final selectedModel = resolveTopicAiModelFromRef(_ref, topicId);
    if (selectedModel == null) {
      throw Exception('No available AI model configured');
    }

    final apiKey = await AiProviderListNotifier.getApiKey(
      selectedModel.provider.id,
    );
    if (apiKey == null) {
      throw Exception(AiL10n.current.apiKeyNotFoundError);
    }

    final contextService = _ref.read(topicAiContextServiceProvider);
    final fetchPosts = _ref.read(topicAiPostsFetcherProvider);
    final contextPosts = await contextService.loadContextPosts(
      topicId: topicId,
      detail: detail,
      scope: ContextScope.all,
      fetchPosts: fetchPosts,
      cachedPosts: cachedPosts,
    );

    final promptSettings = _ref.read(aiPromptSettingsProvider);
    final summaryPrompt =
        promptSettings.summaryAllRepliesPrompt.trim().isNotEmpty
        ? promptSettings.summaryAllRepliesPrompt.trim()
        : defaultSummaryAllRepliesPrompt();

    final messages = <Map<String, String>>[
      {
        'role': 'user',
        'content': AiL10n.current.contextContentPrefix(
          _buildContextText(contextPosts),
        ),
      },
      {'role': 'assistant', 'content': AiL10n.current.contextReadyResponse},
      {'role': 'user', 'content': summaryPrompt},
    ];

    final stream = _ref
        .read(aiChatServiceProvider)
        .sendChatStream(
          provider: selectedModel.provider,
          model: selectedModel.model.id,
          apiKey: apiKey,
          messages: messages,
          systemPrompt: _buildSystemPrompt(detail.title),
        );

    final buffer = StringBuffer();
    await for (final token in stream) {
      buffer.write(token);
    }

    final summarizedText = buffer.toString().trim();
    if (summarizedText.isEmpty) {
      throw Exception(AiL10n.current.emptyResponseError);
    }

    return TopicSummary(
      summarizedText: summarizedText,
      algorithm: '${selectedModel.provider.name} · ${selectedModel.model.name}',
      outdated: false,
      canRegenerate: true,
      newPostsSinceSummary: 0,
      updatedAt: DateTime.now(),
    );
  }

  String _buildSystemPrompt(String title) {
    final buffer = StringBuffer()
      ..writeln(AiL10n.current.systemPromptIntro)
      ..writeln(AiL10n.current.systemPromptTopicTitle(title))
      ..writeln(AiL10n.current.systemPromptContextHint)
      ..writeln(AiL10n.current.systemPromptMarkdown);
    return buffer.toString();
  }

  String _buildContextText(List<TopicAiContextPost> posts) {
    final buffer = StringBuffer();
    for (final post in posts) {
      buffer.writeln('#${post.postNumber} @${post.username}:');
      buffer.writeln(_stripHtml(post.cooked));
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<p>'), '')
        .replaceAll(RegExp(r'</p>'), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll(RegExp(r'&amp;'), '&')
        .replaceAll(RegExp(r'&lt;'), '<')
        .replaceAll(RegExp(r'&gt;'), '>')
        .replaceAll(RegExp(r'&quot;'), '"')
        .replaceAll(RegExp(r'&#39;'), "'")
        .replaceAll(RegExp(r'&nbsp;'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}

final topicAiSummaryServiceProvider = Provider<TopicAiSummaryService>((ref) {
  return TopicAiSummaryService(ref);
});
