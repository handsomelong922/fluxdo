import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/search_result.dart';
import '../../pages/ai_model_service_page.dart';
import '../../providers/search_ai_chat_provider.dart';
import '../../services/navigation/topic_detail_route.dart';
import '../../services/settings/ai_prompt_settings_service.dart';
import '../../utils/time_utils.dart';
import '../common/dismissible_popup_menu.dart';
import '../../pages/topic_detail_page/widgets/ai_chat_message_item.dart';

class SearchAiChatCard extends ConsumerStatefulWidget {
  const SearchAiChatCard({
    super.key,
    required this.query,
    required this.visiblePosts,
  });

  final String query;
  final List<SearchPost> visiblePosts;

  @override
  ConsumerState<SearchAiChatCard> createState() => _SearchAiChatCardState();
}

class _SearchAiChatCardState extends ConsumerState<SearchAiChatCard> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _lastMessageSignature = '';

  @override
  void didUpdateWidget(covariant SearchAiChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _lastMessageSignature = '';
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _maybeScroll(SearchAiChatState state) {
    final lastMessage = state.messages.isEmpty ? null : state.messages.last;
    final signature = lastMessage == null
        ? '0'
        : '${state.messages.length}:${lastMessage.id}:${lastMessage.content.length}:${lastMessage.status.name}';
    if (signature == _lastMessageSignature) return;
    _lastMessageSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _send(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    final selectedModel = ref.read(currentSearchAiModelProvider);
    if (selectedModel == null) return;
    unawaited(
      ref
          .read(searchAiChatProvider(widget.query).notifier)
          .sendMessage(
            searchQuery: widget.query,
            content: trimmed,
            selectedModel: selectedModel,
            visiblePosts: widget.visiblePosts.take(8).toList(growable: false),
            thinkingConfig: ref.read(aiThinkingConfigProvider),
            searchAssistantPrompt: ref
                .read(aiPromptSettingsProvider)
                .searchAssistantPrompt,
          ),
    );
    _controller.clear();
    setState(() {});
  }

  void _retry() {
    final selectedModel = ref.read(currentSearchAiModelProvider);
    if (selectedModel == null) return;
    ref
        .read(searchAiChatProvider(widget.query).notifier)
        .retryLastMessage(
          searchQuery: widget.query,
          selectedModel: selectedModel,
          visiblePosts: widget.visiblePosts.take(8).toList(growable: false),
          thinkingConfig: ref.read(aiThinkingConfigProvider),
          searchAssistantPrompt: ref
              .read(aiPromptSettingsProvider)
              .searchAssistantPrompt,
        );
  }

  void _openInternalTopicLink(
    int topicId,
    String? topicSlug,
    int? postNumber, {
    bool? initialNestedView,
  }) {
    Navigator.of(context).push(
      buildTopicDetailRoute<void>(
        topicId: topicId,
        initialTitle: topicSlug,
        scrollToPostNumber: postNumber,
        initialNestedView: initialNestedView,
      ),
    );
  }

  void _openHistorySheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _SearchAiHistorySheet(query: widget.query),
    );
  }

  void _openAiModelService() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AiModelServicePage()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(searchAiChatProvider(widget.query));
    final selectedModel = ref.watch(currentSearchAiModelProvider);
    _maybeScroll(state);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, theme, state, selectedModel),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.5)),
          if (selectedModel == null)
            _buildMissingModel(context, theme)
          else ...[
            if (state.messages.isEmpty)
              _buildStarter(context, theme)
            else
              _buildMessages(context, state),
            _buildInput(context, theme, state),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ThemeData theme,
    SearchAiChatState state,
    ({AiProvider provider, AiModel model})? selectedModel,
  ) {
    final modelLabel = selectedModel == null
        ? null
        : selectedModel.model.name?.trim().isNotEmpty == true
        ? selectedModel.model.name!.trim()
        : selectedModel.model.id;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            'AI 搜索助手',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          if (modelLabel != null) ...[
            Expanded(
              child: Text(
                modelLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else
            const Spacer(),
          IconButton(
            icon: const Icon(Icons.history_rounded, size: 18),
            tooltip: '历史记录',
            onPressed: _openHistorySheet,
            visualDensity: VisualDensity.compact,
          ),
          IconButton(
            icon: const Icon(Icons.tune_rounded, size: 18),
            tooltip: 'AI 模型与提示词',
            onPressed: _openAiModelService,
            visualDensity: VisualDensity.compact,
          ),
          if (state.messages.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.add_comment_outlined, size: 18),
              tooltip: '新对话',
              onPressed: state.isGenerating
                  ? null
                  : ref
                        .read(searchAiChatProvider(widget.query).notifier)
                        .startNewSession,
              visualDensity: VisualDensity.compact,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              tooltip: '删除当前对话',
              onPressed: state.isGenerating
                  ? null
                  : () => unawaited(
                      ref
                          .read(searchAiChatProvider(widget.query).notifier)
                          .clearMessages(),
                    ),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMissingModel(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            size: 20,
            color: theme.colorScheme.tertiary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '未配置 AI 模型',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiModelServicePage()),
              );
            },
            child: const Text('去配置'),
          ),
        ],
      ),
    );
  }

  Widget _buildStarter(BuildContext context, ThemeData theme) {
    final shortQuery = widget.query.length > 18
        ? '${widget.query.substring(0, 18)}...'
        : widget.query;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ActionChip(
          avatar: const Icon(Icons.manage_search_rounded, size: 18),
          label: Text('分析 "$shortQuery"'),
          onPressed: () => _send('分析当前搜索结果'),
        ),
      ),
    );
  }

  Widget _buildMessages(BuildContext context, SearchAiChatState state) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final maxHeight = (screenHeight * 0.68).clamp(320.0, 720.0).toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: state.messages.length,
        itemBuilder: (context, index) {
          final message = state.messages[index];
          return AiChatMessageItem(
            message: message,
            onRetry: message.status == MessageStatus.error ? _retry : null,
            onInternalLinkTap: _openInternalTopicLink,
          );
        },
      ),
    );
  }

  Widget _buildInput(
    BuildContext context,
    ThemeData theme,
    SearchAiChatState state,
  ) {
    final canSend = _controller.text.trim().isNotEmpty && !state.isGenerating;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _SearchThinkingSelector(ref: ref),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: '继续追问...',
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 8),
          state.isGenerating
              ? IconButton.filledTonal(
                  onPressed: ref
                      .read(searchAiChatProvider(widget.query).notifier)
                      .stopGeneration,
                  icon: const Icon(Icons.stop_rounded, size: 20),
                  tooltip: '停止',
                )
              : IconButton.filled(
                  onPressed: canSend ? () => _send(_controller.text) : null,
                  icon: const Icon(Icons.arrow_upward_rounded, size: 20),
                  tooltip: '发送',
                ),
        ],
      ),
    );
  }
}

class _SearchThinkingSelector extends StatelessWidget {
  const _SearchThinkingSelector({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final config = ref.watch(aiThinkingConfigProvider);
    final enabled = config.isEnabled;
    final color = enabled
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return SwipeDismissiblePopupMenuButton<ThinkingLevel>(
      tooltip: _thinkingLabel(config.level),
      onSelected: _setLevel,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              enabled ? Icons.psychology_alt : Icons.psychology_alt_outlined,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 3),
            Text(
              _shortLabel(config.level),
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ],
        ),
      ),
      itemBuilder: (context) {
        return ThinkingLevel.values.map((level) {
          final selected = level == config.level;
          return PopupMenuItem<ThinkingLevel>(
            value: level,
            child: Row(
              children: [
                if (selected)
                  Icon(Icons.check, size: 18, color: theme.colorScheme.primary)
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 8),
                Text(_thinkingLabel(level)),
              ],
            ),
          );
        }).toList();
      },
    );
  }

  void _setLevel(ThinkingLevel level) {
    final next = ref.read(aiThinkingConfigProvider).copyWith(level: level);
    ref.read(aiThinkingConfigProvider.notifier).state = next;
    ref.read(aiChatStorageServiceProvider).setThinkingConfig(next);
  }

  static String _shortLabel(ThinkingLevel level) {
    return switch (level) {
      ThinkingLevel.off => '关',
      ThinkingLevel.auto => '自动',
      ThinkingLevel.low => '低',
      ThinkingLevel.medium => '中',
      ThinkingLevel.high => '高',
      ThinkingLevel.custom => '自定',
    };
  }

  static String _thinkingLabel(ThinkingLevel level) {
    return switch (level) {
      ThinkingLevel.off => '关闭思考深度',
      ThinkingLevel.auto => '自动思考深度',
      ThinkingLevel.low => '低思考深度',
      ThinkingLevel.medium => '中思考深度',
      ThinkingLevel.high => '高思考深度',
      ThinkingLevel.custom => '自定义思考深度',
    };
  }
}

class _SearchAiHistorySheet extends ConsumerWidget {
  const _SearchAiHistorySheet({required this.query});

  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(searchAiChatProvider(query));
    final notifier = ref.read(searchAiChatProvider(query).notifier);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.62,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                children: [
                  Text('搜索对话历史', style: theme.textTheme.titleMedium),
                  const SizedBox(width: 8),
                  Text(
                    '${state.sessions.length}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: state.isGenerating
                        ? null
                        : () {
                            notifier.startNewSession();
                            Navigator.pop(context);
                          },
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    label: const Text('新对话'),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (state.sessions.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
                child: Text(
                  '暂无历史记录',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: state.sessions.length,
                  itemBuilder: (context, index) {
                    final session = state.sessions[index];
                    final isCurrent = session.id == state.currentSessionId;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isCurrent
                            ? Icons.chat_bubble_rounded
                            : Icons.chat_bubble_outline_rounded,
                        size: 20,
                        color: isCurrent
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      title: Text(
                        session.title?.trim().isNotEmpty == true
                            ? session.title!.trim()
                            : '搜索对话 ${state.sessions.length - index}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: isCurrent ? theme.colorScheme.primary : null,
                          fontWeight: isCurrent ? FontWeight.w600 : null,
                        ),
                      ),
                      subtitle: Text(
                        TimeUtils.formatRelativeTime(session.updatedAt),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      trailing: IconButton(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: theme.colorScheme.error,
                        ),
                        onPressed: state.isGenerating
                            ? null
                            : () =>
                                  unawaited(notifier.deleteSession(session.id)),
                      ),
                      onTap: isCurrent || state.isGenerating
                          ? null
                          : () {
                              notifier.switchSession(session.id);
                              Navigator.pop(context);
                            },
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
