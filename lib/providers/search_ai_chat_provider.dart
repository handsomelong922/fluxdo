import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../models/search_result.dart';
import '../services/search_ai/search_ai_assistant_service.dart';
import 'core_providers.dart';

typedef SearchAiApiKeyLoader = Future<String?> Function(String providerId);

final searchAiAssistantServiceProvider = Provider<SearchAiAssistantService>((
  ref,
) {
  return SearchAiAssistantService(
    chatService: ref.watch(aiChatServiceProvider),
    forumGateway: DiscourseSearchAiForumGateway(
      ref.watch(discourseServiceProvider),
    ),
  );
});

final currentSearchAiModelProvider =
    Provider<({AiProvider provider, AiModel model})?>((ref) {
      return ref.watch(defaultAiModelProvider) ??
          ref.watch(lastUsedAiAssistantModelProvider);
    });

final searchAiChatProvider = StateNotifierProvider.autoDispose
    .family<SearchAiChatNotifier, SearchAiChatState, String>((ref, query) {
      final notifier = SearchAiChatNotifier(
        service: ref.watch(searchAiAssistantServiceProvider),
        apiKeyLoader: AiProviderListNotifier.getApiKey,
      );
      return notifier;
    });

class SearchAiChatState {
  const SearchAiChatState({
    this.messages = const [],
    this.isGenerating = false,
  });

  final List<AiChatMessage> messages;
  final bool isGenerating;

  SearchAiChatState copyWith({
    List<AiChatMessage>? messages,
    bool? isGenerating,
  }) {
    return SearchAiChatState(
      messages: messages ?? this.messages,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }
}

class SearchAiChatNotifier extends StateNotifier<SearchAiChatState> {
  SearchAiChatNotifier({
    required SearchAiAssistantService service,
    required SearchAiApiKeyLoader apiKeyLoader,
  }) : _service = service,
       _apiKeyLoader = apiKeyLoader,
       super(const SearchAiChatState());

  static const _uuid = Uuid();

  final SearchAiAssistantService _service;
  final SearchAiApiKeyLoader _apiKeyLoader;

  StreamSubscription<String>? _subscription;
  bool _cancelled = false;

  Future<void> sendMessage({
    required String searchQuery,
    required String content,
    required ({AiProvider provider, AiModel model}) selectedModel,
    List<SearchPost> visiblePosts = const [],
    ThinkingConfig thinkingConfig = const ThinkingConfig(),
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || state.isGenerating) return;

    final history = state.messages;
    _cancelled = false;

    final userMessage = AiChatMessage(
      id: _uuid.v4(),
      role: ChatRole.user,
      content: trimmed,
      createdAt: DateTime.now(),
    );
    final assistantMessage = AiChatMessage(
      id: _uuid.v4(),
      role: ChatRole.assistant,
      content: '',
      createdAt: DateTime.now(),
      status: MessageStatus.streaming,
    );

    state = state.copyWith(
      messages: [...state.messages, userMessage, assistantMessage],
      isGenerating: true,
    );

    try {
      final apiKey = await _apiKeyLoader(selectedModel.provider.id);
      if (!mounted) return;
      if (apiKey == null || apiKey.trim().isEmpty) {
        _updateAssistantMessage(
          assistantMessage.id,
          '',
          MessageStatus.error,
          errorMessage: AiL10n.current.apiKeyNotFoundError,
        );
        state = state.copyWith(isGenerating: false);
        return;
      }

      final stream = _service.sendSearchChat(
        provider: selectedModel.provider,
        model: selectedModel.model,
        apiKey: apiKey.trim(),
        searchQuery: searchQuery,
        userMessage: trimmed,
        history: history,
        visiblePosts: visiblePosts,
        thinkingConfig: thinkingConfig,
      );

      final buffer = StringBuffer();
      _subscription = stream.listen(
        (token) {
          if (_cancelled || !mounted) return;
          buffer.write(token);
          _updateAssistantMessage(
            assistantMessage.id,
            buffer.toString(),
            MessageStatus.streaming,
          );
        },
        onDone: () {
          if (!mounted) return;
          if (buffer.isEmpty) {
            _updateAssistantMessage(
              assistantMessage.id,
              '',
              MessageStatus.error,
              errorMessage: AiL10n.current.emptyResponseError,
            );
          } else {
            _updateAssistantMessage(
              assistantMessage.id,
              buffer.toString(),
              MessageStatus.completed,
            );
          }
          state = state.copyWith(isGenerating: false);
        },
        onError: (Object error) {
          if (!mounted) return;
          _updateAssistantMessage(
            assistantMessage.id,
            buffer.toString(),
            MessageStatus.error,
            errorMessage: error.toString(),
          );
          state = state.copyWith(isGenerating: false);
        },
        cancelOnError: true,
      );
    } catch (error) {
      if (!mounted) return;
      _updateAssistantMessage(
        assistantMessage.id,
        '',
        MessageStatus.error,
        errorMessage: error.toString(),
      );
      state = state.copyWith(isGenerating: false);
    }
  }

  void stopGeneration() {
    _cancelled = true;
    _subscription?.cancel();
    _subscription = null;
    if (!mounted) return;

    final messages = [...state.messages];
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].status == MessageStatus.streaming) {
        messages[i] = messages[i].copyWith(status: MessageStatus.completed);
        break;
      }
    }
    state = state.copyWith(messages: messages, isGenerating: false);
  }

  void clearMessages() {
    stopGeneration();
    state = const SearchAiChatState();
  }

  void retryLastMessage({
    required String searchQuery,
    required ({AiProvider provider, AiModel model}) selectedModel,
    List<SearchPost> visiblePosts = const [],
    ThinkingConfig thinkingConfig = const ThinkingConfig(),
  }) {
    final messages = [...state.messages];
    if (messages.length < 2 || messages.last.status != MessageStatus.error) {
      return;
    }
    final userContent = messages[messages.length - 2].content;
    messages.removeRange(messages.length - 2, messages.length);
    state = state.copyWith(messages: messages, isGenerating: false);
    unawaited(
      sendMessage(
        searchQuery: searchQuery,
        content: userContent,
        selectedModel: selectedModel,
        visiblePosts: visiblePosts,
        thinkingConfig: thinkingConfig,
      ),
    );
  }

  void _updateAssistantMessage(
    String messageId,
    String content,
    MessageStatus status, {
    String? errorMessage,
  }) {
    if (!mounted) return;
    final messages = state.messages
        .map((message) {
          if (message.id != messageId) return message;
          return message.copyWith(
            content: content,
            status: status,
            errorMessage: errorMessage,
          );
        })
        .toList(growable: false);
    state = state.copyWith(messages: messages);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
