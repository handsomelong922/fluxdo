import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/s.dart';
import '../../../models/topic.dart';
import '../../../utils/dialog_utils.dart';
import '../../../services/settings/ai_prompt_settings_service.dart'; // CUSTOM: AI Prompt Settings
import '../../../services/topic_ai/topic_ai_context_service.dart';
import '../../../services/topic_ai/topic_ai_model_selection.dart';
import '../../../services/toast_service.dart';
import '../../../widgets/share/ai_share_image_preview.dart';
import '../../../widgets/common/dismissible_popup_menu.dart';
import 'ai_chat_input.dart';
import 'ai_chat_message_item.dart';
import 'ai_context_selector.dart';

/// AI 聊天全屏页面
class AiChatPage extends ConsumerStatefulWidget {
  final int topicId;
  final TopicDetail? detail;

  /// 状态栏高度（从父 context 传入，modal 内部会清零 padding.top）
  final double topPadding;

  /// 嵌入模式（PageView 中使用），渲染为 Scaffold + AppBar
  final bool embedded;

  /// 回复话题回调（将 AI 回复内容预填到回复框）
  final void Function(String content)? onReplyToTopic;

  const AiChatPage({
    super.key,
    required this.topicId,
    this.topPadding = 0,
    this.embedded = false,
    this.detail,
    this.onReplyToTopic,
  });

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  // CUSTOM: Stable AI Scroll
  final ScrollController _messageScrollController = ScrollController();

  /// 已获取到的上下文帖子（按 postNumber 升序）
  final List<TopicAiContextPost> _contextPosts = [];

  /// 是否正在加载上下文
  bool _isLoadingContext = false;

  /// 上一次加载使用的 scope，用于检测变化
  ContextScope? _lastLoadedScope;

  /// 多选模式
  bool _selectionMode = false;
  final Set<String> _selectedMessageIds = {};
  String? _lastSessionId;
  int _lastMessageCount = 0;

  @override
  void didUpdateWidget(AiChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.detail != oldWidget.detail && widget.detail != null) {
      _ensureContextPosts();
    }
  }

  @override
  void dispose() {
    _messageScrollController.dispose();
    super.dispose();
  }

  /// 确保上下文帖子已加载，根据当前 scope 需要的数量
  Future<void> _ensureContextPosts([ContextScope? scopeOverride]) async {
    final detail = widget.detail;
    if (detail == null || _isLoadingContext) return;

    final ContextScope scope =
        scopeOverride ?? ref.read(topicAiContextScopeProvider(widget.topicId));

    setState(() => _isLoadingContext = true);

    try {
      final posts = await ref
          .read(topicAiContextServiceProvider)
          .loadContextPosts(
            topicId: widget.topicId,
            detail: detail,
            scope: scope,
            fetchPosts: ref.read(topicAiPostsFetcherProvider),
            cachedPosts: _contextPosts,
          );

      _lastLoadedScope = scope;
      if (mounted) {
        _contextPosts
          ..clear()
          ..addAll(posts);
        _syncToNotifier(detail.title);
      }
    } catch (_) {
      // 加载失败仍允许聊天
    } finally {
      if (mounted) {
        setState(() => _isLoadingContext = false);
      }
    }
  }

  /// 当 scope 变更时检查是否需要加载更多帖子
  void _onScopeChanged(ContextScope newScope) {
    ref.read(topicAiContextScopeProvider(widget.topicId).notifier).state =
        newScope;

    if (_lastLoadedScope != newScope) {
      _ensureContextPosts(newScope);
    }
  }

  /// 同步上下文帖子到 Notifier
  void _syncToNotifier(String title) {
    ref
        .read(topicAiChatProvider(widget.topicId).notifier)
        .setContextPosts(
          title,
          _contextPosts.map((post) => post.toTopicPostContext()).toList(),
        );
  }

  ({AiProvider provider, AiModel model})? _currentModel() {
    return resolveTopicAiModel(ref, widget.topicId);
  }

  void _rememberModel(({AiProvider provider, AiModel model}) model) {
    unawaited(rememberTopicAiModel(ref, widget.topicId, model));
  }

  /// 获取话题标题
  String get _topicTitle => widget.detail?.title ?? '';

  /// 获取话题 slug
  String? get _topicSlug => widget.detail?.slug;

  /// 进入多选模式
  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedMessageIds.clear();
    });
  }

  /// 退出多选模式
  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedMessageIds.clear();
    });
  }

  /// 切换消息选中状态
  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedMessageIds.contains(messageId)) {
        _selectedMessageIds.remove(messageId);
      } else {
        _selectedMessageIds.add(messageId);
      }
    });
  }

  /// 导出选中的消息为图片
  void _exportSelectedMessages() {
    final chatState = ref.read(topicAiChatProvider(widget.topicId));
    final selectedMessages = chatState.messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();

    if (selectedMessages.isEmpty) {
      ToastService.show(S.current.ai_selectExportMessages);
      return;
    }

    _exitSelectionMode();

    AiShareImagePreview.showMessages(
      context,
      messages: selectedMessages,
      topicTitle: _topicTitle,
      topicId: widget.topicId,
      topicSlug: _topicSlug,
      onReplyToTopic: _onReplyImageReady,
    );
  }

  /// 单条消息导出图片
  void _shareMessageAsImage(AiChatMessage message) {
    AiShareImagePreview.show(
      context,
      message: message,
      topicTitle: _topicTitle,
      topicId: widget.topicId,
      topicSlug: _topicSlug,
      onReplyToTopic: _onReplyImageReady,
    );
  }

  /// 复制消息文本
  void _copyMessageText(AiChatMessage message) {
    Clipboard.setData(ClipboardData(text: message.content));
    ToastService.showSuccess(S.current.ai_copiedToClipboard);
  }

  /// 预览页上传完成后的回调
  void _onReplyImageReady(String imageMarkdown) {
    widget.onReplyToTopic?.call(imageMarkdown);
  }

  // CUSTOM: Stable AI Scroll 仅在新增消息或切换会话时滚动一次，
  // 流式 token 更新不会触发滚动，避免视口在生成过程中被强制移动。
  void _maybeAutoScrollMessages(TopicAiChatState chatState) {
    final sessionChanged = chatState.currentSessionId != _lastSessionId;
    final messageCountIncreased = chatState.messages.length > _lastMessageCount;
    _lastSessionId = chatState.currentSessionId;
    _lastMessageCount = chatState.messages.length;

    if (!sessionChanged && !messageCountIncreased) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_messageScrollController.hasClients) return;
      _scrollMessagesToBottom(
        animated: messageCountIncreased && !sessionChanged,
      );
    });
  }

  // CUSTOM: Stable AI Scroll
  void _scrollMessagesToBottom({bool animated = false}) {
    if (!_messageScrollController.hasClients) return;
    final targetOffset = _messageScrollController.position.maxScrollExtent;
    if (animated) {
      _messageScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _messageScrollController.jumpTo(targetOffset);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chatState = ref.watch(topicAiChatProvider(widget.topicId));
    final chatNotifier = ref.read(topicAiChatProvider(widget.topicId).notifier);
    _maybeAutoScrollMessages(chatState);

    // 首次 build 且有 detail 时加载上下文
    if (widget.detail != null && _lastLoadedScope == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureContextPosts();
      });
    }

    if (widget.embedded) {
      return _buildEmbedded(context, theme, chatState, chatNotifier);
    }
    return _buildSheet(context, theme, chatState, chatNotifier);
  }

  /// 嵌入模式（PageView 中使用）：Scaffold + AppBar
  Widget _buildEmbedded(
    BuildContext context,
    ThemeData theme,
    TopicAiChatState chatState,
    TopicAiChatNotifier chatNotifier,
  ) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: _selectionMode
            ? _buildSelectionToolbar(context, theme)
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 20,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(context.l10n.ai_title),
                ],
              ),
        centerTitle: false,
        actions: _selectionMode
            ? null
            : _buildToolbarActions(context, theme, chatState, chatNotifier),
      ),
      body: _buildBody(context, theme, chatState, chatNotifier),
    );
  }

  /// BottomSheet 模式（当前默认）
  Widget _buildSheet(
    BuildContext context,
    ThemeData theme,
    TopicAiChatState chatState,
    TopicAiChatNotifier chatNotifier,
  ) {
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.viewInsets.bottom;
    final screenHeight = mediaQuery.size.height;
    final contentHeight = (screenHeight * 0.9).clamp(
      0.0,
      screenHeight - widget.topPadding - bottomInset,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        height: contentHeight,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              // 顶部拖动条
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 自定义标题栏
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _selectionMode
                    ? _buildSelectionToolbar(context, theme)
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.auto_awesome,
                                size: 20,
                                color: theme.colorScheme.primary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                context.l10n.ai_title,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: _buildToolbarActions(
                              context,
                              theme,
                              chatState,
                              chatNotifier,
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 8),

              // Body
              Expanded(
                child: _buildBody(context, theme, chatState, chatNotifier),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 工具栏操作按钮（两种模式共用）
  List<Widget> _buildToolbarActions(
    BuildContext context,
    ThemeData theme,
    TopicAiChatState chatState,
    TopicAiChatNotifier chatNotifier,
  ) {
    return [
      Consumer(
        builder: (context, ref, _) {
          final scope = ref.watch(topicAiContextScopeProvider(widget.topicId));
          return AiContextSelector(
            currentScope: scope,
            onChanged: _onScopeChanged,
          );
        },
      ),
      if (chatState.messages.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.check_box_outlined),
          tooltip: context.l10n.ai_multiSelectExport,
          iconSize: 20,
          onPressed: _enterSelectionMode,
        ),
      SwipeDismissiblePopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        tooltip: context.l10n.ai_moreTooltip,
        iconSize: 20,
        onSelected: (value) {
          switch (value) {
            case 'new_session':
              chatNotifier.createNewSession();
            case 'history':
              _showSessionHistory(context, chatState, chatNotifier);
            case 'clear':
              _confirmClear(context, chatNotifier);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(
            value: 'new_session',
            child: ListTile(
              leading: const Icon(Icons.add_comment_outlined),
              title: Text(context.l10n.ai_newSession),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
          if (chatState.sessions.isNotEmpty)
            PopupMenuItem(
              value: 'history',
              child: ListTile(
                leading: const Icon(Icons.history),
                title: Text(context.l10n.ai_sessionHistory),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          if (chatState.messages.isNotEmpty)
            PopupMenuItem(
              value: 'clear',
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: Text(context.l10n.ai_clearChat),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
    ];
  }

  /// 聊天内容主体（两种模式共用）
  Widget _buildBody(
    BuildContext context,
    ThemeData theme,
    TopicAiChatState chatState,
    TopicAiChatNotifier chatNotifier,
  ) {
    return Column(
      children: [
        // 上下文加载提示
        if (_isLoadingContext)
          LinearProgressIndicator(
            minHeight: 2,
            color: theme.colorScheme.primary,
          ),

        // 聊天主要内容区
        Expanded(
          child: chatState.messages.isEmpty
              ? _buildEmptyState(context, theme)
              : _buildMessageList(context, ref, chatState),
        ),

        // 底部输入区
        AiChatInput(
          isGenerating: chatState.isGenerating,
          onSend: (content) {
            final scope = ref.read(topicAiContextScopeProvider(widget.topicId));
            final model = _currentModel();
            if (model == null) return;
            _rememberModel(model);
            chatNotifier.sendMessage(content, scope, selectedModel: model);
            // CUSTOM: Stable AI Scroll 用户主动发送时允许滚动到底部一次
            _maybeAutoScrollMessages(
              ref.read(topicAiChatProvider(widget.topicId)),
            );
          },
          onStop: chatNotifier.stopGeneration,
          bottomLeading: Consumer(
            builder: (context, ref, _) {
              final allModels = ref.watch(allAvailableAiModelsProvider);
              final selected = ref.watch(
                topicSelectedAiModelProvider(widget.topicId),
              );
              final lastUsedModel = ref.watch(lastUsedAiAssistantModelProvider);
              final defaultModel = ref.watch(defaultAiModelProvider);
              final current = selected ?? defaultModel ?? lastUsedModel;
              if (allModels.length <= 1 || current == null) {
                return const SizedBox.shrink();
              }
              return _AiModelSelector(
                allModels: allModels,
                current: current,
                onChanged: _rememberModel,
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _sendQuickPrompt(
    String prompt, {
    ContextScope? scopeOverride,
  }) async {
    final ContextScope scope =
        scopeOverride ?? ref.read(topicAiContextScopeProvider(widget.topicId));
    if (scopeOverride != null) {
      ref.read(topicAiContextScopeProvider(widget.topicId).notifier).state =
          scopeOverride;
    }
    await _ensureContextPosts(scope);
    final model = _currentModel();
    if (model == null) return;
    _rememberModel(model);
    ref
        .read(topicAiChatProvider(widget.topicId).notifier)
        .sendMessage(prompt, scope, selectedModel: model);
    // CUSTOM: Stable AI Scroll 快捷动作属于用户主动触发，允许滚动一次
    _maybeAutoScrollMessages(ref.read(topicAiChatProvider(widget.topicId)));
  }

  Widget _buildEmptyState(BuildContext context, ThemeData theme) {
    final promptSettings = ref.watch(aiPromptSettingsProvider);
    final summaryTopicPrompt =
        promptSettings.summaryTopicPrompt.trim().isNotEmpty
        ? promptSettings.summaryTopicPrompt.trim()
        : S.current.ai_summarizePrompt;
    final summaryAllRepliesPrompt =
        promptSettings.summaryAllRepliesPrompt.trim().isNotEmpty
        ? promptSettings.summaryAllRepliesPrompt.trim()
        : defaultSummaryAllRepliesPrompt();
    final generateReplyPrompt =
        promptSettings.generateReplyPrompt.trim().isNotEmpty
        ? promptSettings.generateReplyPrompt.trim()
        : defaultGenerateReplyPrompt();
    final quickPrompts =
        <({IconData icon, String label, String prompt, ContextScope? scope})>[
          (
            icon: Icons.summarize_outlined,
            label: S.current.ai_summarizeTopic,
            prompt: summaryTopicPrompt,
            scope: ContextScope.firstPostOnly,
          ),
          (
            icon: Icons.translate_outlined,
            label: S.current.ai_translatePost,
            prompt: S.current.ai_translatePrompt,
            scope: ContextScope.firstPostOnly,
          ),
          (
            icon: Icons.article_outlined,
            label: '总结全部回帖',
            prompt: summaryAllRepliesPrompt,
            scope: ContextScope.all,
          ),
          (
            icon: Icons.question_answer_outlined,
            label: S.current.ai_listViewpoints,
            prompt: S.current.ai_listViewpointsPrompt,
            scope: null,
          ),
          (
            icon: Icons.lightbulb_outlined,
            label: S.current.ai_highlights,
            prompt: S.current.ai_highlightsPrompt,
            scope: null,
          ),
          (
            icon: Icons.rate_review_outlined,
            label: '生成回复',
            prompt: generateReplyPrompt,
            scope: ContextScope.all,
          ),
        ];

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              context.l10n.ai_askTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.l10n.ai_askSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.7,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: quickPrompts.map((item) {
                return ActionChip(
                  avatar: Icon(item.icon, size: 18),
                  label: Text(item.label),
                  onPressed: () =>
                      _sendQuickPrompt(item.prompt, scopeOverride: item.scope),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList(
    BuildContext context,
    WidgetRef ref,
    TopicAiChatState chatState,
  ) {
    final messages = chatState.messages;
    return ListView.builder(
      controller: _messageScrollController,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final message = messages[index];
        return AiChatMessageItem(
          message: message,
          onRetry: message.status == MessageStatus.error
              ? () {
                  final scope = ref.read(
                    topicAiContextScopeProvider(widget.topicId),
                  );
                  final model = _currentModel();
                  if (model == null) return;
                  _rememberModel(model);
                  ref
                      .read(topicAiChatProvider(widget.topicId).notifier)
                      .retryLastMessage(scope, selectedModel: model);
                }
              : null,
          onShareAsImage:
              message.status == MessageStatus.completed &&
                  message.content.isNotEmpty
              ? () => _shareMessageAsImage(message)
              : null,
          onCopyText:
              message.status == MessageStatus.completed &&
                  message.content.isNotEmpty
              ? () => _copyMessageText(message)
              : null,
          selectionMode: _selectionMode,
          isSelected: _selectedMessageIds.contains(message.id),
          onSelectionToggle: _selectionMode
              ? () => _toggleMessageSelection(message.id)
              : null,
        );
      },
    );
  }

  /// 多选模式工具栏
  Widget _buildSelectionToolbar(BuildContext context, ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              iconSize: 20,
              onPressed: _exitSelectionMode,
            ),
            const SizedBox(width: 4),
            Text(
              context.l10n.ai_selectedCount(_selectedMessageIds.length),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: _selectedMessageIds.isEmpty
              ? null
              : _exportSelectedMessages,
          icon: const Icon(Icons.image_outlined, size: 18),
          label: Text(context.l10n.ai_exportImage),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          ),
        ),
      ],
    );
  }

  void _showSessionHistory(
    BuildContext context,
    TopicAiChatState chatState,
    TopicAiChatNotifier notifier,
  ) {
    showAppBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return _SessionHistorySheet(
          sessions: chatState.sessions,
          currentSessionId: chatState.currentSessionId,
          onSwitch: (sessionId) {
            notifier.switchSession(sessionId);
            Navigator.pop(ctx);
          },
          onDelete: (sessionId) async {
            await notifier.deleteSession(sessionId);
          },
        );
      },
    );
  }

  void _confirmClear(BuildContext context, TopicAiChatNotifier notifier) {
    showAppDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.ai_clearChatTitle),
        content: Text(context.l10n.ai_clearChatConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.common_cancel),
          ),
          FilledButton(
            onPressed: () {
              notifier.clearMessages();
              Navigator.pop(ctx);
            },
            child: Text(context.l10n.ai_clearLabel),
          ),
        ],
      ),
    );
  }
}

/// 模型选择器
class _AiModelSelector extends StatelessWidget {
  final List<({AiProvider provider, AiModel model})> allModels;
  final ({AiProvider provider, AiModel model}) current;
  final ValueChanged<({AiProvider provider, AiModel model})> onChanged;

  const _AiModelSelector({
    required this.allModels,
    required this.current,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SwipeDismissiblePopupMenuButton<int>(
      tooltip: S.current.ai_selectModel,
      onSelected: (index) => onChanged(allModels[index]),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 100),
              child: Text(
                current.model.name ?? current.model.id,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.unfold_more,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        return allModels.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isCurrent =
              item.provider.id == current.provider.id &&
              item.model.id == current.model.id;
          return PopupMenuItem<int>(
            value: index,
            child: Row(
              children: [
                if (isCurrent)
                  Icon(Icons.check, size: 18, color: theme.colorScheme.primary)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.model.name ?? item.model.id,
                        style: const TextStyle(fontSize: 14),
                      ),
                      Text(
                        item.provider.name,
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList();
      },
    );
  }
}

/// 会话历史记录列表
class _SessionHistorySheet extends StatefulWidget {
  final List<AiChatSession> sessions;
  final String? currentSessionId;
  final ValueChanged<String> onSwitch;
  final Future<void> Function(String) onDelete;

  const _SessionHistorySheet({
    required this.sessions,
    required this.currentSessionId,
    required this.onSwitch,
    required this.onDelete,
  });

  @override
  State<_SessionHistorySheet> createState() => _SessionHistorySheetState();
}

class _SessionHistorySheetState extends State<_SessionHistorySheet> {
  late List<AiChatSession> _sessions;

  @override
  void initState() {
    super.initState();
    _sessions = List.of(widget.sessions);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    S.current.ai_sessionHistory,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    S.current.ai_sessionCount(_sessions.length),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 列表
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final session = _sessions[index];
                  final isCurrent = session.id == widget.currentSessionId;

                  return ListTile(
                    leading: Icon(
                      isCurrent ? Icons.chat_bubble : Icons.chat_bubble_outline,
                      size: 20,
                      color: isCurrent
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      _formatSessionTitle(session, index),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isCurrent
                            ? FontWeight.w600
                            : FontWeight.normal,
                        color: isCurrent ? theme.colorScheme.primary : null,
                      ),
                    ),
                    subtitle: Text(
                      _formatTime(session.updatedAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: isCurrent
                        ? null
                        : IconButton(
                            icon: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: theme.colorScheme.error,
                            ),
                            onPressed: () async {
                              await widget.onDelete(session.id);
                              if (!mounted) return;
                              _sessions.removeWhere((s) => s.id == session.id);
                              if (_sessions.isEmpty) {
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              } else {
                                setState(() {});
                              }
                            },
                          ),
                    onTap: isCurrent ? null : () => widget.onSwitch(session.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatSessionTitle(AiChatSession session, int index) {
    return session.title ?? S.current.ai_sessionTitle(_sessions.length - index);
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return S.current.time_justNow;
    if (diff.inHours < 1) return S.current.time_minutesAgo(diff.inMinutes);
    if (diff.inDays < 1) return S.current.time_hoursAgo(diff.inHours);
    if (diff.inDays < 30) return S.current.time_daysAgo(diff.inDays);

    return '${time.month}/${time.day}';
  }
}
