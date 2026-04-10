import 'package:flutter/material.dart';
import '../../../models/topic.dart';
import '../../../services/discourse_cache_manager.dart';
import '../../../utils/url_helper.dart';

/// 单个 Boost 气泡
class BoostBubble extends StatelessWidget {
  final Boost boost;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const BoostBubble({
    super.key,
    required this.boost,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
        ),        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 用户头像
            CircleAvatar(
              radius: 9,
              backgroundImage: discourseImageProvider(
                UrlHelper.resolveUrlWithCdn(
                  boost.user.avatarTemplate.replaceAll('{size}', '48'),
                ),
              ),
              onBackgroundImageError: (_, _) {},
            ),
            const SizedBox(width: 4),
            // Boost 内容
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Text(
                _stripHtml(boost.cooked),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  height: 1.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 简单移除 HTML 标签，保留纯文本
  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .trim();
  }
}
