// CUSTOM: Tag Filter
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/settings/content_filter_service.dart';

class TagFilterPage extends ConsumerStatefulWidget {
  const TagFilterPage({super.key});

  @override
  ConsumerState<TagFilterPage> createState() => _TagFilterPageState();
}

class _TagFilterPageState extends ConsumerState<TagFilterPage> {
  late final TextEditingController _controller;

  static const String _hint = '福利,抽奖,交易';
  static const String _description = '使用英文逗号分隔多个标签，命中标签的帖子将不会显示。';

  @override
  void initState() {
    super.initState();
    final initial = ref.read(contentFilterProvider).blockedTags.join(',');
    _controller = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    ref
        .read(contentFilterProvider.notifier)
        .setBlockedTagsFromInput(_controller.text);
    final normalized = ref.read(contentFilterProvider).blockedTags.join(',');
    if (_controller.text != normalized) {
      _controller.text = normalized;
      _controller.selection = TextSelection.collapsed(
        offset: normalized.length,
      );
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('标签屏蔽已保存'),
          duration: Duration(seconds: 1),
        ),
      );
  }

  void _restoreNormalized() {
    final current = ref.read(contentFilterProvider).blockedTags.join(',');
    _controller.text = current;
    _controller.selection = TextSelection.collapsed(offset: current.length);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockedTags = ref.watch(
      contentFilterProvider.select((state) => state.blockedTags),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('标签屏蔽')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: '屏蔽标签',
              hintText: _hint,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _description,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('保存'),
              ),
              OutlinedButton.icon(
                onPressed: () {
                  _controller.clear();
                  ref.read(contentFilterProvider.notifier).clearBlockedTags();
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('标签屏蔽已清空'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                },
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('清空'),
              ),
              TextButton.icon(
                onPressed: _restoreNormalized,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('恢复已保存'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text('当前规则', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          if (blockedTags.isEmpty)
            Text(
              '尚未设置标签屏蔽',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: blockedTags
                  .map((tag) => Chip(label: Text(tag)))
                  .toList(),
            ),
        ],
      ),
    );
  }
}
