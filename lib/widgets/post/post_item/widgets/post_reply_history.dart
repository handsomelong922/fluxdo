import 'package:flutter/material.dart';
import '../../../../l10n/s.dart';
import '../../../../models/topic.dart';
import '../../../../utils/html_excerpt.dart';
import '../../../common/smart_avatar.dart';

/// 回复历史预览组件
class PostReplyHistory extends StatelessWidget {
  final List<Post>? replyHistory;
  final ValueNotifier<bool> showReplyHistoryNotifier;
  final void Function(int postNumber)? onJumpToPost;
  final double contentFontScale;

  const PostReplyHistory({
    super.key,
    required this.replyHistory,
    required this.showReplyHistoryNotifier,
    this.onJumpToPost,
    this.contentFontScale = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (replyHistory == null || replyHistory!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Area
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                Icon(
                  Icons.format_quote_rounded,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  context.l10n.post_replyTo,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                InkWell(
                  onTap: () {
                    showReplyHistoryNotifier.value = false;
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      Icons.close,
                      size: 16,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 0.5,
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
          // Reply Items
          ...replyHistory!.map((replyPost) {
            final avatarUrl = replyPost.getAvatarUrl(size: 60);
            return InkWell(
              onTap: () => onJumpToPost?.call(replyPost.postNumber),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SmartAvatar(
                      imageUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
                      radius: 14,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      fallbackText: replyPost.username,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                (replyPost.name != null &&
                                        replyPost.name!.isNotEmpty)
                                    ? replyPost.name!
                                    : replyPost.username,
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '#${replyPost.postNumber}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const Spacer(),
                              Icon(
                                Icons.arrow_outward,
                                size: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cleanHtmlExcerpt(replyPost.cooked),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 13 * contentFontScale,
                              height: 1.4,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
