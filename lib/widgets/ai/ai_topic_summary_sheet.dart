import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/topic.dart';
import '../../providers/ai_post_review_provider.dart';
import '../../providers/ai_topic_summary_provider.dart';
import '../../providers/theme_provider.dart';
import '../../services/ai_topic_summary_service.dart';
import 'ai_model_select_sheet.dart';
import 'ai_quick_prompts_sheet.dart';

/// 标题区域入口；打开面板不会自动向 AI 发送帖子。
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
  TopicSummaryCancellation? _cancellation;
  ({AiProvider provider, AiModel model})? _selected;
  TopicSummaryResult? _result;
  String? _error;
  String _progress = '';
  bool _busy = false;
  late final TextEditingController _prompt;

  @override
  void initState() {
    super.initState();
    _prompt = TextEditingController(text: ref.read(sharedPreferencesProvider).getString(topicSummaryPromptKey)
        ?? ref.read(aiTopicSummaryDefaultPromptProvider));
  }
  @override
  void dispose() {
    _cancellation?.cancel();
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

  Future<void> _start() async {
    if (_busy || _prompt.text.trim().isEmpty) return;
    final available = ref.read(aiPostReviewAvailableModelsProvider);
    final selected = _resolveModel(available, ref.read(aiTopicSummaryModelProvider));
    if (selected == null) return;
    final cancellation = TopicSummaryCancellation();
    _cancellation = cancellation;
    setState(() { _busy = true; _error = null; _result = null; _progress = '正在准备…'; });
    try {
      final key = await cancellation.wait(ref.read(aiTopicSummaryApiKeyLoaderProvider)(selected.provider.id));
      cancellation.check();
      if (key == null || key.trim().isEmpty) {
        throw const TopicSummaryException('此服务尚未配置 API Key，请打开模型设置');
      }
      final service = ref.read(aiTopicSummaryServiceFactoryProvider)(topicId: widget.topicId,
          provider: selected.provider, model: selected.model, apiKey: key.trim());
      final result = await service.summarize(prompt: _prompt.text.trim(), cancellation: cancellation,
          onPrepared: (posts, total, chars, requests) async {
            if (!mounted || cancellation.isCancelled) return false;
            return await showDialog<bool>(context: context, builder: (context) => AlertDialog(
              title: const Text('确认发送给 AI'),
              content: Text('已读取 $posts/$total 楼（缺失 ${total - posts} 楼），将把 $chars 字符发送至 ${selected.provider.name} / ${selected.model.name ?? selected.model.id}。'
                  '\n服务地址：${selected.provider.baseUrl}'
                  '\n本次预计 $requests 次 AI 请求，可能产生 API 费用。'
                  '${widget.isPrivateMessage ? '\n内容包含私信，请确认参与者隐私。' : ''}'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
                FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('发送并总结')),
              ],
            )) ?? false;
          },
          onProgress: (value) {
            if (mounted && !cancellation.isCancelled) setState(() => _progress = value);
          });
      if (mounted && !cancellation.isCancelled) setState(() => _result = result);
    } catch (error) {
      if (mounted && identical(_cancellation, cancellation)) {
        setState(() => _error = cancellation.isCancelled ? '已取消总结'
            : error is TopicSummaryException ? error.message : '读取或总结失败，未生成完整总结。请重试或检查模型设置。');
      }
    } finally {
      if (mounted && identical(_cancellation, cancellation)) setState(() => _busy = false);
    }
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
    final result = _result;
    return SizedBox(height: MediaQuery.sizeOf(context).height * 0.85, child: Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(children: [
        Row(children: [
          const Expanded(child: Text('AI 整帖总结', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
          IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        Text(widget.isPrivateMessage
            ? '这是私信。开始后会将私信主帖和所有可读取回复发送给下方所选 AI 服务，请确认参与者隐私。'
            : '开始后会将主帖和所有可读取回复发送给下方所选 AI 服务。'),
        const SizedBox(height: 8),
        Text(selected == null ? '尚未配置文本模型' : '${selected.provider.name} / ${selected.model.name ?? selected.model.id}'),
        const Text('按开始时目录抓取；长帖会分段并合并，可能产生多次 API 费用。上限 10000 楼 / 9.6 万字符 / 16 段，超限会停止；最多 31 次 AI 请求。取消会关闭当前 AI 请求；已发出的论坛读取可能仍在结束中。', style: TextStyle(fontSize: 12)),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: _busy ? null : () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const AiProvidersPage())), child: const Text('模型设置')),
          if (selected != null) TextButton(onPressed: _busy ? null : () async {
            final value = await showAiModelSelectSheet(context: context,
                allModels: ref.read(aiPostReviewAvailableModelsProvider), current: selected, mode: PromptType.text);
            if (value != null && mounted) setState(() => _selected = value);
          }, child: const Text('切换模型')),
          TextButton(onPressed: _busy ? null : _editPrompt, child: const Text('总结 Prompt')),
          TextButton(onPressed: _busy ? null : () => showAiQuickPromptsSheet(
            context: context, type: PromptType.text, onPick: (preset, dimensions) async {
              if (!mounted) return;
              final value = appendDimensionFragments(preset.promptTemplate, preset.dimensions, dimensions);
              await ref.read(sharedPreferencesProvider).setString(topicSummaryPromptKey, value);
              if (mounted) setState(() => _prompt.text = value);
            },
          ), child: const Text('选择已有快捷词')),
        ]),
        if (_busy) ...[const LinearProgressIndicator(), const SizedBox(height: 8), Text(_progress)],
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (result != null) Text('已总结 ${result.readCount}/${result.total} 楼'
            '${result.missingIds.isEmpty ? '' : '；${result.missingIds.length} 楼不可读取，本结果不包含这些楼层'}。'),
        Padding(padding: const EdgeInsets.symmetric(vertical: 16), child: SelectableText(result?.text ?? '')),
        const Text('AI 可能遗漏或误解，请核对原帖。', style: TextStyle(fontSize: 12)),
        Row(children: [
          Expanded(child: FilledButton(onPressed: _busy || selected == null ? null : _start,
              child: Text(_result != null || _error != null ? '重新读取并总结' : '读取并准备总结'))),
          if (_busy) TextButton(onPressed: () {
            _cancellation?.cancel();
            setState(() => _progress = '正在取消…');
          }, child: const Text('取消')),
          if (result != null) IconButton(tooltip: '复制总结', onPressed: () => Clipboard.setData(ClipboardData(text: result.text)), icon: const Icon(Icons.copy)),
        ]),
      ]),
    ));
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
