// CUSTOM: Keyword Filter
// 关键词屏蔽（正则）设置页 - 极简实现
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings/keyword_filter_service.dart';

// CUSTOM: Keyword Filter
class KeywordFilterPage extends ConsumerStatefulWidget {
  const KeywordFilterPage({super.key});

  @override
  ConsumerState<KeywordFilterPage> createState() => _KeywordFilterPageState();
}

class _KeywordFilterPageState extends ConsumerState<KeywordFilterPage> {
  final _controller = TextEditingController();
  final _editController = TextEditingController();
  bool _isEditing = false;
  String? _errorText;
  String? _editErrorText;

  @override
  void dispose() {
    _controller.dispose();
    _editController.dispose();
    super.dispose();
  }

  void _addPattern() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _errorText = '不能为空');
      return;
    }
    if (!KeywordFilterNotifier.isValidRegex(text)) {
      setState(() => _errorText = '无效的正则表达式');
      return;
    }
    final notifier = ref.read(keywordFilterProvider.notifier);
    final ok = notifier.add(text);
    if (!ok) {
      setState(() => _errorText = '已存在相同规则');
      return;
    }
    _controller.clear();
    setState(() => _errorText = null);
  }

  void _enterEditMode() {
    final patterns = ref.read(keywordFilterProvider);
    _editController.text = patterns.join('\n');
    setState(() {
      _isEditing = true;
      _errorText = null;
      _editErrorText = null;
    });
  }

  void _cancelEditMode() {
    _editController.clear();
    setState(() {
      _isEditing = false;
      _editErrorText = null;
    });
  }

  void _saveEditingPatterns() {
    if (_editController.text.trim().isEmpty) {
      final ok = ref
          .read(keywordFilterProvider.notifier)
          .replaceAllPatterns(const []);
      if (!ok) {
        setState(() => _editErrorText = '保存失败');
        return;
      }
      _editController.clear();
      setState(() {
        _isEditing = false;
        _editErrorText = null;
      });
      return;
    }

    final lines = _editController.text.split(RegExp(r'\r?\n'));
    final values = <String>[];
    final seen = <String, int>{};

    for (var i = 0; i < lines.length; i++) {
      final value = lines[i].trim();
      if (value.isEmpty) {
        setState(() => _editErrorText = '第 ${i + 1} 行不能为空');
        return;
      }
      if (!KeywordFilterNotifier.isValidRegex(value)) {
        setState(() => _editErrorText = '第 ${i + 1} 行不是有效的正则表达式');
        return;
      }
      final duplicateLine = seen[value];
      if (duplicateLine != null) {
        setState(
          () => _editErrorText = '第 ${i + 1} 行与第 ${duplicateLine + 1} 行重复',
        );
        return;
      }
      seen[value] = i;
      values.add(value);
    }

    final ok = ref
        .read(keywordFilterProvider.notifier)
        .replaceAllPatterns(values);
    if (!ok) {
      setState(() => _editErrorText = '与其它规则重复或保存失败');
      return;
    }

    _editController.clear();
    setState(() {
      _isEditing = false;
      _editErrorText = null;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('规则已保存'), duration: Duration(seconds: 1)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final patterns = ref.watch(keywordFilterProvider);
    final canEdit = patterns.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑屏蔽规则' : '关键词屏蔽'),
        actions: [
          if (_isEditing) ...[
            TextButton.icon(
              onPressed: _saveEditingPatterns,
              icon: const Icon(Icons.save_outlined),
              label: const Text('保存'),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: '取消编辑',
              onPressed: _cancelEditMode,
            ),
          ],
        ],
      ),
      body: _isEditing
          ? _buildFullscreenEditor(theme)
          : _buildRuleList(theme, patterns, canEdit),
    );
  }

  Widget _buildFullscreenEditor(ThemeData theme) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '每行一条正则规则。删除某一行即可移除规则，保存时会统一校验。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (_editErrorText != null) ...[
              const SizedBox(height: 8),
              Text(
                _editErrorText!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: TextField(
                controller: _editController,
                expands: true,
                minLines: null,
                maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                autofocus: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                  hintText: '广告|推广\n(?i)spam\n不想看到的关键词',
                ),
                style: const TextStyle(fontFamily: 'monospace', height: 1.35),
                onChanged: (_) {
                  if (_editErrorText != null) {
                    setState(() => _editErrorText = null);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleList(ThemeData theme, List<String> patterns, bool canEdit) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(
                    hintText: '输入正则表达式，例如 广告|推广',
                    errorText: _errorText,
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addPattern(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _addPattern, child: const Text('添加')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '命中标题的帖子将不会显示在列表中（大小写不敏感）',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: patterns.isEmpty
              ? Center(
                  child: Text(
                    '尚未添加屏蔽规则',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: patterns.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    return ListTile(
                      title: SelectableText(
                        patterns[index],
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            tooltip: '编辑',
                            onPressed: canEdit ? _enterEditMode : null,
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: '删除',
                            onPressed: () => ref
                                .read(keywordFilterProvider.notifier)
                                .removeAt(index),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
