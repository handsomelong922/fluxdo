import 'package:flutter/material.dart';

import '../../../models/topic.dart';
import '../../../utils/time_utils.dart';

class EditsIndicator extends StatelessWidget {
  const EditsIndicator({
    super.key,
    required this.post,
    this.onShowHistory,
    this.onEnterEditor,
  });

  final Post post;
  final VoidCallback? onShowHistory;
  final VoidCallback? onEnterEditor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.onSurfaceVariant;
    final isWikiFirstVersion = post.wiki && post.version == 1;
    final canEnterEditor =
        isWikiFirstVersion && post.canEdit && onEnterEditor != null;
    final canShowHistory =
        post.canViewEditHistory && post.version > 1 && onShowHistory != null;
    final enabled = canEnterEditor || canShowHistory;
    final iconData = post.wiki
        ? Icons.auto_stories_outlined
        : Icons.edit_outlined;
    final color = base.withValues(alpha: enabled ? 0.8 : 0.35);

    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconData, size: 12, color: color),
        if (post.editsCount > 0) ...[
          const SizedBox(width: 2),
          Text(
            '${post.editsCount}',
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w500,
              height: 1,
            ),
          ),
        ],
      ],
    );

    return Tooltip(
      message: _tooltip(enabled: enabled),
      preferBelow: false,
      child: enabled
          ? InkResponse(
              radius: 14,
              customBorder: const StadiumBorder(),
              onTap: () {
                if (canEnterEditor) {
                  onEnterEditor?.call();
                } else if (canShowHistory) {
                  onShowHistory?.call();
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: content,
              ),
            )
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
              child: content,
            ),
    );
  }

  String _tooltip({required bool enabled}) {
    if (post.wiki && post.version <= 1) {
      return 'Wiki 帖，可由有权限的用户编辑';
    }
    final time = TimeUtils.formatTooltipTime(
      post.lastWikiEdit ?? post.updatedAt,
    );
    if (post.wiki) return 'Wiki 帖最后编辑于 $time';
    if (!enabled && post.version > 1) return '无权查看编辑历史';
    return '编辑于 $time';
  }
}
