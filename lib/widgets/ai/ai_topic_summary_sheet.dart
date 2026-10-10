import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// ignore: deprecated_member_use
import 'package:flutter_riverpod/legacy.dart';

import '../../models/topic.dart';
import '../../pages/topic_detail_page/topic_detail_page.dart';
import '../../providers/ai_post_review_provider.dart';
import '../../providers/ai_topic_summary_provider.dart';
import '../../providers/selected_topic_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/ai_topic_summary_service.dart';
import '../../services/ai_topic_summary_task.dart';
import '../common/relative_time_text.dart';
import '../markdown_editor/markdown_renderer.dart';
import '../topic/topic_summary_widget.dart';
import 'ai_model_select_sheet.dart';
import 'ai_quick_prompts_sheet.dart';

/// 展开状态只在当前账号的内存中保留；返回话题时重新订阅同一后台任务。
final aiTopicSummaryExpandedProvider =
    StateProvider.family<bool, ({String account, int topicId})>(
      (ref, identity) => false,
    );

/// 摘要芯片与通知同行，正文卡片紧随其后，不创建独立路由或面板。
class AiTopicSummaryButton extends ConsumerWidget {
  const AiTopicSummaryButton({
    super.key,
    required this.detail,
    this.headerExtra,
    this.onJumpToPost,
    this.onContinueConversation,
  });
  final TopicDetail detail;
  final Widget? headerExtra;
  final void Function(int postNumber)? onJumpToPost;
  final void Function(String summary)? onContinueConversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(aiTopicSummaryAccountProvider);
    final expandedProvider = aiTopicSummaryExpandedProvider((
      account: account,
      topicId: detail.id,
    ));
    final expanded = ref.watch(expandedProvider);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Semantics(
              button: true,
              expanded: expanded,
              child: InkWell(
                key: const ValueKey('ai-summary-toggle'),
                onTap: () =>
                    ref.read(expandedProvider.notifier).state = !expanded,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withValues(
                      alpha: 0.3,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'AI 摘要',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        turns: expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 300),
                        child: Icon(
                          Icons.expand_more,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (headerExtra != null) headerExtra!,
          ],
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AiTopicSummaryCard(
              key: ValueKey('ai-summary-$account-${detail.id}'),
              topicId: detail.id,
              isPrivateMessage: detail.isPrivateMessage,
              postsCount: detail.postsCount,
              onJumpToPost: onJumpToPost,
              onContinueConversation: onContinueConversation,
              siteSummary: detail.summarizable
                  ? CollapsibleTopicSummary(
                      topicId: detail.id,
                      topicDetail: detail,
                      onJumpToPost: onJumpToPost,
                      label: '站点摘要',
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

/// 内联结果沿用后台任务所有者，折叠、滚动销毁和离页都不会取消生成。
class AiTopicSummaryCard extends ConsumerStatefulWidget {
  const AiTopicSummaryCard({
    super.key,
    required this.topicId,
    this.isPrivateMessage = false,
    this.postsCount,
    this.onJumpToPost,
    this.onContinueConversation,
    this.siteSummary,
  });
  final int topicId;
  final bool isPrivateMessage;
  final int? postsCount;
  final void Function(int postNumber)? onJumpToPost;
  final void Function(String summary)? onContinueConversation;
  final Widget? siteSummary;
  @override
  ConsumerState<AiTopicSummaryCard> createState() => _AiTopicSummaryCardState();
}

class _AiTopicSummaryCardState extends ConsumerState<AiTopicSummaryCard> {
  late final TextEditingController _prompt;
  bool _settingsOpen = false;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(
      text:
          ref
              .read(sharedPreferencesProvider)
              .getString(topicSummaryPromptKey) ??
          ref.read(aiTopicSummaryDefaultPromptProvider),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start(retry: false);
    });
  }

  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  String _key(
    ({AiProvider provider, AiModel model}) selected,
    String account,
  ) => topicSummaryTaskKey(
    account: account,
    topicId: widget.topicId,
    provider: selected.provider,
    model: selected.model,
    prompt: _prompt.text,
    isPrivateMessage: widget.isPrivateMessage,
  );

  void _start({bool retry = true}) {
    if (_prompt.text.trim().isEmpty) return;
    final selected = ref.read(
      aiTopicSummaryResolvedModelProvider(widget.topicId),
    );
    if (selected == null) return;
    final account = ref.read(aiTopicSummaryAccountProvider);
    if (widget.isPrivateMessage && account.endsWith(':guest')) return;
    final tasks = ref.read(aiTopicSummaryTasksProvider);
    final factory = ref.read(aiTopicSummaryServiceFactoryProvider);
    final loadKey = ref.read(aiTopicSummaryApiKeyLoaderProvider);
    unawaited(
      tasks.start(
        _key(selected, account),
        prompt: _prompt.text.trim(),
        retry: retry,
        createService: () async {
          final apiKey = await loadKey(selected.provider.id);
          if (apiKey == null || apiKey.trim().isEmpty) {
            throw const TopicSummaryException('此服务尚未配置 API Key，请打开模型设置');
          }
          return factory(
            topicId: widget.topicId,
            provider: selected.provider,
            model: selected.model,
            apiKey: apiKey.trim(),
          );
        },
      ),
    );
  }

  Future<void> _editPrompt() async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _SummaryPromptDialog(
        initial: _prompt.text,
        defaultPrompt: ref.read(aiTopicSummaryDefaultPromptProvider),
      ),
    );
    if (value != null && mounted) {
      await ref
          .read(sharedPreferencesProvider)
          .setString(topicSummaryPromptKey, value);
      if (mounted) setState(() => _prompt.text = value);
    }
  }

  void _openLink(int topicId, String? slug, int? postNumber) {
    if (topicId == widget.topicId &&
        postNumber != null &&
        widget.onJumpToPost != null) {
      widget.onJumpToPost!(postNumber);
      return;
    }
    if (EmbeddedStackScope.maybePushTopic(
      context,
      topicId: topicId,
      initialTitle: slug,
      scrollToPostNumber: postNumber,
    ))
      return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TopicDetailPage(
          topicId: topicId,
          initialTitle: slug,
          scrollToPostNumber: postNumber,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(
      aiTopicSummaryResolvedModelProvider(widget.topicId),
    );
    final account = ref.watch(aiTopicSummaryAccountProvider);
    final tasks = ref.watch(aiTopicSummaryTasksProvider);
    final key = selected == null ? null : _key(selected, account);
    final theme = Theme.of(context);
    return StreamBuilder<void>(
      stream: tasks.changes,
      builder: (context, _) {
        final state = key == null
            ? const TopicSummaryTaskState()
            : tasks.state(key);
        final result = state.result;
        final busy = state.busy;
        final needsAccount =
            widget.isPrivateMessage && account.endsWith(':guest');
        return Container(
          key: const ValueKey('ai-summary-card'),
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'AI 摘要',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '摘要设置',
                    visualDensity: VisualDensity.compact,
                    onPressed: () =>
                        setState(() => _settingsOpen = !_settingsOpen),
                    icon: const Icon(Icons.tune, size: 18),
                  ),
                ],
              ),
              if (_settingsOpen || selected == null) ...[
                Text(
                  selected == null
                      ? '尚未配置文本模型'
                      : '${selected.provider.name} / ${selected.model.name ?? selected.model.id}',
                ),
                Text(
                  widget.isPrivateMessage
                      ? '这是私信，内容会发送给所选 AI 服务。结果仅在本次登录期间保留，不写入本地缓存。'
                      : '使用已配置 AI 总结主帖与全部可读取回复，可能产生 API 费用。离开帖子后继续生成，结果保存在本机。',
                  style: theme.textTheme.bodySmall,
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AiProvidersPage(),
                              ),
                            ),
                      child: const Text('模型设置'),
                    ),
                    if (selected != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () async {
                                final value = await showAiModelSelectSheet(
                                  context: context,
                                  allModels: ref.read(
                                    aiPostReviewAvailableModelsProvider,
                                  ),
                                  current: selected,
                                  mode: PromptType.text,
                                );
                                if (value == null || !mounted) return;
                                await rememberTopicSummaryModel(
                                  ref,
                                  widget.topicId,
                                  value,
                                );
                              },
                        child: const Text('切换模型'),
                      ),
                    TextButton(
                      onPressed: busy ? null : _editPrompt,
                      child: const Text('总结 Prompt'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => showAiQuickPromptsSheet(
                              context: context,
                              type: PromptType.text,
                              onPick: (preset, dimensions) async {
                                if (!mounted) return;
                                final value = appendDimensionFragments(
                                  preset.promptTemplate,
                                  preset.dimensions,
                                  dimensions,
                                );
                                await ref
                                    .read(sharedPreferencesProvider)
                                    .setString(topicSummaryPromptKey, value);
                                if (mounted)
                                  setState(() => _prompt.text = value);
                              },
                            ),
                      child: const Text('选择已有快捷词'),
                    ),
                    if (result != null)
                      TextButton.icon(
                        onPressed: () =>
                            Clipboard.setData(ClipboardData(text: result.text)),
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('复制总结'),
                      ),
                  ],
                ),
                if (widget.siteSummary != null) widget.siteSummary!,
              ],
              const SizedBox(height: 12),
              if (widget.isPrivateMessage)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text('私信内容会发送给所选 AI 服务；摘要仅在本次登录期间保留。'),
                ),
              if (needsAccount) const Text('请先登录后再总结私信。'),
              if (busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(
                  state.progress,
                  key: const ValueKey('ai-summary-progress'),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => tasks.cancel(key!),
                    child: const Text('取消'),
                  ),
                ),
              ],
              if (state.error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    state.error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (result != null) ...[
                if (widget.postsCount != null &&
                    widget.postsCount! > result.total)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text('此摘要可能未包含最新回复，可手动刷新更新'),
                  ),
                if (result.missingIds.isNotEmpty)
                  Text(
                    '已总结 ${result.readCount}/${result.total} 楼；${result.missingIds.length} 楼不可读取，本结果不包含这些楼层。',
                  ),
                MarkdownBody(data: result.text, onInternalLinkTap: _openLink),
                const SizedBox(height: 12),
              ],
              LayoutBuilder(
                builder: (context, constraints) {
                  final updatedAt = state.savedAt == null
                      ? const SizedBox.shrink()
                      : RelativeTimeText(
                          dateTime: state.savedAt,
                          displayStyle: TimeDisplayStyle.prefixed,
                          prefix: '更新于',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        );
                  final buttonStyle = TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: const Size(0, 32),
                  );
                  final actions = <Widget>[
                    if (result != null && widget.onContinueConversation != null)
                      TextButton.icon(
                        key: const ValueKey('ai-summary-continue'),
                        style: buttonStyle,
                        onPressed: busy
                            ? null
                            : () => widget.onContinueConversation!(result.text),
                        icon: const Icon(Icons.chat_bubble_outline, size: 16),
                        label: const Text('继续'),
                      ),
                    TextButton.icon(
                      key: const ValueKey('ai-summary-refresh'),
                      style: buttonStyle,
                      onPressed: busy || selected == null || needsAccount
                          ? null
                          : () => _start(),
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(
                        state.error != null
                            ? '重试'
                            : result != null
                            ? '刷新'
                            : '开始总结',
                      ),
                    ),
                  ];
                  // 常规字号对齐参考截图；极窄屏或大字时允许底部动作换行。
                  if (constraints.maxWidth >= 280 &&
                      MediaQuery.textScalerOf(context).scale(14) <= 18) {
                    return Row(
                      children: [
                        Expanded(child: updatedAt),
                        ...actions,
                      ],
                    );
                  }
                  return Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [updatedAt, ...actions],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 编辑器独立管理 controller，确保退出动画期间仍然可用。
class _SummaryPromptDialog extends StatefulWidget {
  const _SummaryPromptDialog({
    required this.initial,
    required this.defaultPrompt,
  });
  final String initial;
  final String defaultPrompt;
  @override
  State<_SummaryPromptDialog> createState() => _SummaryPromptDialogState();
}

class _SummaryPromptDialogState extends State<_SummaryPromptDialog> {
  late final _editor = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义总结 Prompt'),
    content: SizedBox(
      width: 500,
      child: TextField(
        controller: _editor,
        minLines: 4,
        maxLines: 10,
        maxLength: 4000,
        decoration: const InputDecoration(hintText: '例如：列出主要观点、反对意见和对应楼层'),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => _editor.text = widget.defaultPrompt,
        child: const Text('恢复内置'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          if (_editor.text.trim().isNotEmpty)
            Navigator.pop(context, _editor.text.trim());
        },
        child: const Text('保存'),
      ),
    ],
  );
}
