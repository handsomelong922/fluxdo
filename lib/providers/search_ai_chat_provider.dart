import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: depend_on_referenced_packages
import 'package:flutter_riverpod/legacy.dart';
import 'package:uuid/uuid.dart';

import '../models/search_result.dart';
import '../services/search_ai/search_ai_chat_storage_service.dart';
import '../services/search_ai/search_ai_assistant_service.dart';
import 'core_providers.dart';
import 'theme_provider.dart';

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

final searchAiChatStorageProvider = Provider<SearchAiChatStorageService>((ref) {
  return SearchAiChatStorageService(ref.watch(sharedPreferencesProvider));
});

final searchAiChatProvider =
    StateNotifierProvider.family<
      SearchAiChatNotifier,
      SearchAiChatState,
      String
    >((ref, query) {
      final notifier = SearchAiChatNotifier(
        query: query,
        service: ref.watch(searchAiAssistantServiceProvider),
        storage: ref.watch(searchAiChatStorageProvider),
        apiKeyLoader: AiProviderListNotifier.getApiKey,
      );
      return notifier;
    });

class SearchAiChatState {
  const SearchAiChatState({
    this.messages = const [],
    this.sessions = const [],
    this.currentSessionId,
    this.isGenerating = false,
  });

  final List<AiChatMessage> messages;
  final List<AiChatSession> sessions;
  final String? currentSessionId;
  final bool isGenerating;

  SearchAiChatState copyWith({
    List<AiChatMessage>? messages,
    List<AiChatSession>? sessions,
    String? currentSessionId,
    bool clearCurrentSessionId = false,
    bool? isGenerating,
  }) {
    return SearchAiChatState(
      messages: messages ?? this.messages,
      sessions: sessions ?? this.sessions,
      currentSessionId: clearCurrentSessionId
          ? null
          : currentSessionId ?? this.currentSessionId,
      isGenerating: isGenerating ?? this.isGenerating,
    );
  }
}

class SearchAiChatNotifier extends StateNotifier<SearchAiChatState> {
  SearchAiChatNotifier({
    required String query,
    required SearchAiAssistantService service,
    required SearchAiChatStorageService storage,
    required SearchAiApiKeyLoader apiKeyLoader,
  }) : _query = query,
       _service = service,
       _storage = storage,
       _apiKeyLoader = apiKeyLoader,
       super(_loadInitialState(storage, query));

  static const _uuid = Uuid();

  final String _query;
  final SearchAiAssistantService _service;
  final SearchAiChatStorageService _storage;
  final SearchAiApiKeyLoader _apiKeyLoader;

  StreamSubscription<String>? _subscription;
  bool _cancelled = false;

  static SearchAiChatState _loadInitialState(
    SearchAiChatStorageService storage,
    String query,
  ) {
    final sessions = storage.getQuerySessions(query);
    if (sessions.isEmpty) return const SearchAiChatState();
    final currentSession = sessions.first;
    return SearchAiChatState(
      sessions: sessions,
      currentSessionId: currentSession.id,
      messages: storage.loadSessionMessages(currentSession.id),
    );
  }

  Future<void> sendMessage({
    required String searchQuery,
    required String content,
    required ({AiProvider provider, AiModel model}) selectedModel,
    List<SearchPost> visiblePosts = const [],
    ThinkingConfig thinkingConfig = const ThinkingConfig(),
    String searchAssistantPrompt = '',
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty || state.isGenerating) return;

    final history = state.messages;
    _cancelled = false;
    final sessionId = state.currentSessionId ?? _uuid.v4();

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
      currentSessionId: sessionId,
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
        searchAssistantPrompt: searchAssistantPrompt,
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
            unawaited(_saveToStorage(sessionId));
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
    final sessionId = state.currentSessionId;
    if (sessionId != null && _hasAssistantContent(messages)) {
      unawaited(_saveToStorage(sessionId));
    }
  }

  Future<void> clearMessages() async {
    _cancelled = true;
    await _subscription?.cancel();
    _subscription = null;
    final sessionId = state.currentSessionId;
    if (sessionId != null) {
      await _storage.deleteSession(_query, sessionId);
    }
    if (!mounted) return;
    state = SearchAiChatState(sessions: _storage.getQuerySessions(_query));
  }

  void startNewSession() {
    stopGeneration();
    state = state.copyWith(
      messages: const [],
      clearCurrentSessionId: true,
      isGenerating: false,
    );
  }

  void switchSession(String sessionId) {
    if (state.isGenerating) return;
    state = state.copyWith(
      currentSessionId: sessionId,
      messages: _storage.loadSessionMessages(sessionId),
      sessions: _storage.getQuerySessions(_query),
    );
  }

  Future<void> deleteSession(String sessionId) async {
    if (sessionId == state.currentSessionId) {
      await clearMessages();
      return;
    }
    await _storage.deleteSession(_query, sessionId);
    if (!mounted) return;
    state = state.copyWith(sessions: _storage.getQuerySessions(_query));
  }

  void retryLastMessage({
    required String searchQuery,
    required ({AiProvider provider, AiModel model}) selectedModel,
    List<SearchPost> visiblePosts = const [],
    ThinkingConfig thinkingConfig = const ThinkingConfig(),
    String searchAssistantPrompt = '',
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
        searchAssistantPrompt: searchAssistantPrompt,
      ),
    );
  }

  Future<void> _saveToStorage(String sessionId) async {
    final messages = state.messages;
    await _storage.saveSessionMessages(
      _query,
      sessionId,
      messages,
      title: _buildSessionTitle(messages),
    );
    if (!mounted) return;
    state = state.copyWith(sessions: _storage.getQuerySessions(_query));
  }

  String? _buildSessionTitle(List<AiChatMessage> messages) {
    final firstUser = messages
        .where((message) => message.role == ChatRole.user)
        .map((message) => message.content.trim())
        .where((content) => content.isNotEmpty)
        .firstOrNull;
    if (firstUser == null) return null;
    return firstUser.length > 32
        ? '${firstUser.substring(0, 32)}...'
        : firstUser;
  }

  bool _hasAssistantContent(List<AiChatMessage> messages) {
    return messages.any(
      (message) =>
          message.role == ChatRole.assistant &&
          message.content.trim().isNotEmpty,
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
