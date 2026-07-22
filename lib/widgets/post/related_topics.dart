import 'package:flutter/material.dart';

import '../../l10n/s.dart';
import '../../models/topic.dart';
import '../../services/navigation/topic_detail_route.dart';

const int maxRelatedTopics = 5;

@visibleForTesting
List<Topic> selectRelatedTopics(
  Iterable<Topic> topics, {
  required int currentTopicId,
}) {
  final selected =
      topics
          .where(
            (topic) =>
                topic.id != currentTopicId && topic.title.trim().isNotEmpty,
          )
          .toList(growable: false)
        ..sort((a, b) {
          final dateComparison = _compareCreatedAtDescending(
            a.createdAt,
            b.createdAt,
          );
          return dateComparison != 0 ? dateComparison : b.id.compareTo(a.id);
        });
  return List<Topic>.unmodifiable(selected.take(maxRelatedTopics));
}

int _compareCreatedAtDescending(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return b.compareTo(a);
}

/// 网页端 `related_topics` 的话题列表。
class RelatedTopics extends StatefulWidget {
  const RelatedTopics({
    super.key,
    required this.currentTopicId,
    required this.topics,
  });

  final int currentTopicId;
  final List<Topic>? topics;

  @override
  State<RelatedTopics> createState() => _RelatedTopicsState();
}

class _RelatedTopicsState extends State<RelatedTopics> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final topics = selectRelatedTopics(
      widget.topics ?? const <Topic>[],
      currentTopicId: widget.currentTopicId,
    );
    if (topics.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: _expanded
                ? const BorderRadius.vertical(top: Radius.circular(8))
                : BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    Icons.topic_outlined,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.post_relatedTopics,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: !_expanded
                ? const SizedBox(width: double.infinity, height: 0)
                : Column(
                    children: [
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: theme.colorScheme.outlineVariant.withValues(
                          alpha: 0.3,
                        ),
                      ),
                      for (final topic in topics)
                        _RelatedTopicItem(topic: topic),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _RelatedTopicItem extends StatelessWidget {
  const _RelatedTopicItem({required this.topic});

  final Topic topic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        buildTopicDetailRoute<void>(
          topicId: topic.id,
          initialTitle: topic.title,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.subdirectory_arrow_right,
              size: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                topic.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_outward,
              size: 14,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
