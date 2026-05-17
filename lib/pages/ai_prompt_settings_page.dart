// CUSTOM: AI Prompt Settings
import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/s.dart';
import '../services/settings/ai_prompt_settings_service.dart';

class AiPromptSettingsPage extends ConsumerStatefulWidget {
  const AiPromptSettingsPage({super.key});

  @override
  ConsumerState<AiPromptSettingsPage> createState() =>
      _AiPromptSettingsPageState();
}

class _AiPromptSettingsPageState extends ConsumerState<AiPromptSettingsPage> {
  late final TextEditingController _summaryTopicController;
  late final TextEditingController _summaryAllRepliesController;
  late final TextEditingController _generateReplyController;
  late final TextEditingController _generateTitleController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(aiPromptSettingsProvider);
    _summaryTopicController = TextEditingController(
      text: state.summaryTopicPrompt,
    );
    _summaryAllRepliesController = TextEditingController(
      text: state.summaryAllRepliesPrompt,
    );
    _generateReplyController = TextEditingController(
      text: state.generateReplyPrompt,
    );
    _generateTitleController = TextEditingController(
      text: state.generateTitlePrompt,
    );
  }

  @override
  void dispose() {
    _summaryTopicController.dispose();
    _summaryAllRepliesController.dispose();
    _generateReplyController.dispose();
    _generateTitleController.dispose();
    super.dispose();
  }

  String _defaultSummaryTopicPrompt() => S.current.ai_summarizePrompt;

  String _defaultSummaryAllRepliesPrompt() => defaultSummaryAllRepliesPrompt();

  String _defaultGenerateReplyPrompt() => defaultGenerateReplyPrompt();

  String _defaultGenerateTitlePrompt() => AiL10n.current.titleGenerationPrompt;

  void _saveAll() {
    final notifier = ref.read(aiPromptSettingsProvider.notifier);
    notifier.setSummaryTopicPrompt(_summaryTopicController.text);
    notifier.setSummaryAllRepliesPrompt(_summaryAllRepliesController.text);
    notifier.setGenerateReplyPrompt(_generateReplyController.text);
    notifier.setGenerateTitlePrompt(_generateTitleController.text);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('AI 提示词配置已保存'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  Widget _buildPromptCard({
    required String title,
    required TextEditingController controller,
    required String defaultValue,
    required String description,
  }) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(
              description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 8,
              decoration: InputDecoration(
                hintText: defaultValue,
                border: const OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '留空或清空后保存，将自动回退到默认 prompt。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => controller.clear(),
                  icon: const Icon(Icons.delete_outline_rounded),
                  label: const Text('清空'),
                ),
                TextButton.icon(
                  onPressed: () {
                    controller.text = defaultValue;
                    controller.selection = TextSelection.collapsed(
                      offset: controller.text.length,
                    );
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('恢复默认'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 提示词配置'),
        actions: [TextButton(onPressed: _saveAll, child: const Text('保存'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPromptCard(
            title: 'AI 总结主贴 prompt',
            controller: _summaryTopicController,
            defaultValue: _defaultSummaryTopicPrompt(),
            description: '用于总结主贴内容，默认会结合主贴上下文发起请求。',
          ),
          const SizedBox(height: 12),
          _buildPromptCard(
            title: 'AI 总结全部回帖 prompt',
            controller: _summaryAllRepliesController,
            defaultValue: _defaultSummaryAllRepliesPrompt(),
            description: '用于总结整个话题的全部回帖内容。',
          ),
          const SizedBox(height: 12),
          _buildPromptCard(
            title: 'AI 生成回复 prompt',
            controller: _generateReplyController,
            defaultValue: _defaultGenerateReplyPrompt(),
            description: '用于让 AI 基于当前话题内容直接生成一条建议回复。',
          ),
          const SizedBox(height: 12),
          _buildPromptCard(
            title: 'AI 生成标题 prompt',
            controller: _generateTitleController,
            defaultValue: _defaultGenerateTitlePrompt(),
            description: '用于 AI 助手会话标题自动生成。',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _saveAll,
            icon: const Icon(Icons.save_rounded),
            label: const Text('保存全部'),
          ),
        ],
      ),
    );
  }
}
