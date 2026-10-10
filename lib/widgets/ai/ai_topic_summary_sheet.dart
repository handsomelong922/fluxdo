import 'dart:async';

import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/topic.dart';
import '../../providers/ai_post_review_provider.dart';
import '../../providers/ai_topic_summary_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/ai_topic_summary_service.dart';
import '../../services/ai_topic_summary_task.dart';
import 'ai_model_select_sheet.dart';
import 'ai_quick_prompts_sheet.dart';

/// 一次点击即使用已配置模型；后台任务和缓存不依赖面板生命周期。
class AiTopicSummaryButton extends StatefulWidget {
  const AiTopicSummaryButton({super.key, required this.detail});
  final TopicDetail detail;
  @override
  State<AiTopicSummaryButton> createState() => _AiTopicSummaryButtonState();
}

class _AiTopicSummaryButtonState extends State<AiTopicSummaryButton> {
  bool _open = false;
  @override
  Widget build(BuildContext context) => ActionChip(
    avatar: const Icon(Icons.auto_awesome_outlined, size: 16),
    label: const Text('AI 总结'),
    onPressed: _open ? null : () async {
      setState(() => _open = true);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => AiTopicSummarySheet(topicId: widget.detail.id,
            isPrivateMessage: widget.detail.isPrivateMessage),
      );
      if (mounted) setState(() => _open = false);
    },
  );
}

class AiTopicSummarySheet extends ConsumerStatefulWidget {
  const AiTopicSummarySheet({super.key, required this.topicId, this.isPrivateMessage = false});
  final int topicId;
  final bool isPrivateMessage;
  @override
  ConsumerState<AiTopicSummarySheet> createState() => _AiTopicSummarySheetState();
}

class _AiTopicSummarySheetState extends ConsumerState<AiTopicSummarySheet> {
  ({AiProvider provider, AiModel model})? _selected;
  late final TextEditingController _prompt;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: ref.read(sharedPreferencesProvider).getString(topicSummaryPromptKey)
        ?? ref.read(aiTopicSummaryDefaultPromptProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _start(retry: false);
    });
  }
  @override
  void dispose() {
    _prompt.dispose();
    super.dispose();
  }

  ({AiProvider provider, AiModel model})? _resolveModel(
    List<({AiProvider provider, AiModel model})> available,
    ({AiProvider provider, AiModel model})? fallback,
  ) {
    for (final item in available) {
      if (item.provider.id == _selected?.provider.id && item.model.id == _selected?.model.id) return item;
    }
    return fallback;
  }

  String _key(({AiProvider provider, AiModel model}) selected, String account) =>
      topicSummaryTaskKey(account: account, topicId: widget.topicId,
        provider: selected.provider, model: selected.model, prompt: _prompt.text, isPrivateMessage: widget.isPrivateMessage);

  void _start({bool retry = true}) {
    if (_prompt.text.trim().isEmpty) return;
    final selected = _resolveModel(ref.read(aiPostReviewAvailableModelsProvider),
        ref.read(aiTopicSummaryModelProvider));
    if (selected == null) return;
    final account = ref.read(aiTopicSummaryAccountProvider);
    if (widget.isPrivateMessage && account.endsWith(':guest')) return;
    final tasks = ref.read(aiTopicSummaryTasksProvider);
    final factory = ref.read(aiTopicSummaryServiceFactoryProvider);
    final loadKey = ref.read(aiTopicSummaryApiKeyLoaderProvider);
    unawaited(tasks.start(_key(selected, account), prompt: _prompt.text.trim(), retry: retry,
      createService: () async {
        final apiKey = await loadKey(selected.provider.id);
        if (apiKey == null || apiKey.trim().isEmpty) {
          throw const TopicSummaryException('此服务尚未配置 API Key，请打开模型设置');
        }
        return factory(topicId: widget.topicId, provider: selected.provider,
          model: selected.model, apiKey: apiKey.trim());
      }));
  }

  Future<void> _editPrompt() async {
    final value = await showDialog<String>(context: context, builder: (_) => _SummaryPromptDialog(
      initial: _prompt.text, defaultPrompt: ref.read(aiTopicSummaryDefaultPromptProvider),
    ));
    if (value != null && mounted) {
      await ref.read(sharedPreferencesProvider).setString(topicSummaryPromptKey, value);
      if (mounted) setState(() => _prompt.text = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = ref.watch(aiPostReviewAvailableModelsProvider);
    final selected = _resolveModel(available, ref.watch(aiTopicSummaryModelProvider));
    final account = ref.watch(aiTopicSummaryAccountProvider);
    final tasks = ref.watch(aiTopicSummaryTasksProvider);
    final key = selected == null ? null : _key(selected, account);
    return StreamBuilder<void>(stream: tasks.changes, builder: (context, _) {
    final state = key == null ? const TopicSummaryTaskState() : tasks.state(key);
    final result = state.result;
    final busy = state.busy;
    final needsAccount = widget.isPrivateMessage && account.endsWith(':guest');
    return SizedBox(height: MediaQuery.sizeOf(context).height * 0.85, child: Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        Row(children: [
          const Expanded(child: Text('AI 整帖总结', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
          IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        Text(widget.isPrivateMessage
            ? '这是私信，内容会发送给所选 AI 服务，请注意参与者隐私。'
            : '使用已配置 AI 总结主帖与全部可读取回复，可能产生 API 费用。'),
        const SizedBox(height: 8),
        Text(selected == null ? '尚未配置文本模型' : '${selected.provider.name} / ${selected.model.name ?? selected.model.id}'),
        Text(widget.isPrivateMessage
            ? '关闭面板或离开帖子后会继续总结。私信结果仅在本次登录期间保留，不写入本地缓存。'
            : '关闭面板或离开帖子后会继续总结，返回可查看。结果保存在本机；长帖会分段合并。', style: const TextStyle(fontSize: 12)),
        if (needsAccount) const Text('请先登录后再总结私信。'),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: busy ? null : () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AiProvidersPage())), child: const Text('模型设置')),
          if (selected != null) TextButton(onPressed: busy ? null : () async {
            final value = await showAiModelSelectSheet(context: context,
                allModels: ref.read(aiPostReviewAvailableModelsProvider), current: selected, mode: PromptType.text);
            if (value != null && mounted) setState(() => _selected = value);
          }, child: const Text('切换模型')),
          TextButton(onPressed: busy ? null : _editPrompt, child: const Text('总结 Prompt')),
          TextButton(onPressed: busy ? null : () => showAiQuickPromptsSheet(
            context: context, type: PromptType.text, onPick: (preset, dimensions) async {
              if (!mounted) return;
              final value = appendDimensionFragments(preset.promptTemplate, preset.dimensions, dimensions);
              await ref.read(sharedPreferencesProvider).setString(topicSummaryPromptKey, value);
              if (mounted) setState(() => _prompt.text = value);
            },
          ), child: const Text('选择已有快捷词')),
        ]),
        if (busy) ...[const LinearProgressIndicator(), const SizedBox(height: 8), Text(state.progress)],
        if (state.error != null) Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (state.savedAt != null) Text('生成时间：${state.savedAt!.toLocal().toString().split(".").first}；新回复需重新总结。', style: const TextStyle(fontSize: 12)),
        if (result != null) Text('已总结 ${result.readCount}/${result.total} 楼'
            '${result.missingIds.isEmpty ? '' : '；${result.missingIds.length} 楼不可读取，本结果不包含这些楼层'}。'),
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: SelectableText(result?.text ?? '')),
        const Text('AI 可能遗漏或误解，请核对原帖。', style: TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(child: FilledButton(onPressed: busy || selected == null || needsAccount ? null : () => _start(),
              child: Text(result != null || state.error != null ? '重新总结' : '开始总结'))),
          if (busy) TextButton(onPressed: () => tasks.cancel(key!), child: const Text('取消')),
          if (result != null) IconButton(tooltip: '复制总结', onPressed: () => Clipboard.setData(ClipboardData(text: result.text)), icon: const Icon(Icons.copy)),
        ]),
      ]),
    ));
    });
  }
}

/// 编辑器独立管理 controller，确保退出动画期间仍然可用。
class _SummaryPromptDialog extends StatefulWidget {
  const _SummaryPromptDialog({required this.initial, required this.defaultPrompt});
  final String initial;
  final String defaultPrompt;
  @override
  State<_SummaryPromptDialog> createState() => _SummaryPromptDialogState();
}

class _SummaryPromptDialogState extends State<_SummaryPromptDialog> {
  late final _editor = TextEditingController(text: widget.initial);
  @override
  void dispose() { _editor.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('自定义总结 Prompt'),
    content: SizedBox(width: 500, child: TextField(controller: _editor, minLines: 4, maxLines: 10,
        maxLength: 4000, decoration: const InputDecoration(hintText: '例如：列出主要观点、反对意见和对应楼层'))),
    actions: [
      TextButton(onPressed: () => _editor.text = widget.defaultPrompt, child: const Text('恢复内置')),
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
      TextButton(onPressed: () {
        if (_editor.text.trim().isNotEmpty) Navigator.pop(context, _editor.text.trim());
      }, child: const Text('保存')),
    ],
  );
}
