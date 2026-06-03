import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/search_result.dart';
import '../../providers/search_ai_chat_provider.dart';
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
  int _lastMessageCount = 0;

  @override
  void didUpdateWidget(covariant SearchAiChatCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) {
      _lastMessageCount = 0;
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
    if (state.messages.length == _lastMessageCount) return;
    _lastMessageCount = state.messages.length;
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
        );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(searchAiChatProvider(widget.query));
    final selectedModel = ref.watch(currentSearchAiModelProvider);
    _maybeScroll(state);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      child: Row(
        children: [
          Icon(Icons.auto_awesome, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            'AI 搜索助手',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (modelLabel != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                modelLabel,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          if (state.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, size: 18),
              tooltip: '清空',
              onPressed: state.isGenerating
                  ? null
                  : ref
                        .read(searchAiChatProvider(widget.query).notifier)
                        .clearMessages,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildMissingModel(BuildContext context, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
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
                MaterialPageRoute(builder: (_) => const AiProvidersPage()),
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
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
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
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 360),
      child: ListView.builder(
        controller: _scrollController,
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: state.messages.length,
        itemBuilder: (context, index) {
          final message = state.messages[index];
          return AiChatMessageItem(
            message: message,
            onRetry: message.status == MessageStatus.error ? _retry : null,
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
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
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
                  horizontal: 14,
                  vertical: 9,
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
