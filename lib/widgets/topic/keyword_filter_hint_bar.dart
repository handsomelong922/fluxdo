import 'package:flutter/material.dart';
import 'package:app_icons/app_icons.dart';

import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../../pages/filtered_topics_page.dart';
import '../../utils/topic_keyword_filter.dart';

/// 忽略数量和复核页面共用同一份已加载、已确认的记录快照。
class KeywordFilterHintBar extends StatelessWidget {
  final List<FilteredTopic> hiddenTopics;
  final void Function(Topic) onOpenTopic;

  const KeywordFilterHintBar({
    super.key,
    required this.hiddenTopics,
    required this.onOpenTopic,
  });

  @override
  Widget build(BuildContext context) {
    final hiddenCount = hiddenTopics.length;
    if (hiddenCount <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = context.l10n;
    final mutedColor = theme.colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () async {
            final selected = await Navigator.of(context).push<Topic>(
              MaterialPageRoute(
                builder: (_) => FilteredTopicsPage(topics: hiddenTopics),
              ),
            );
            // 快照页面打开期间，刷新可能移除提示条；由源页面检查自身生命周期。
            if (selected != null) onOpenTopic(selected);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Symbols.visibility_off_rounded,
                  size: 14,
                  color: mutedColor,
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.topic_keywordFilter_hiddenCount(hiddenCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: mutedColor,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
