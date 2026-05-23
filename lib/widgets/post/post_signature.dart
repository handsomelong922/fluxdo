import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/topic.dart';
import '../../providers/preferences_provider.dart';
import '../content/collapsed_html_content.dart';

/// 帖子签名展示，统一服务平铺视图、长帖分段和树形视图。
class PostSignature extends ConsumerWidget {
  final Post post;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry contentPadding;
  final double fontSize;
  final int maxLines;

  const PostSignature({
    super.key,
    required this.post,
    this.margin = const EdgeInsets.only(top: 8),
    this.contentPadding = const EdgeInsets.only(top: 8),
    this.fontSize = 12,
    this.maxLines = 2,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signature = post.signatureCooked?.trim();
    if (signature == null || signature.isEmpty) {
      return const SizedBox.shrink();
    }

    final showSignatures = ref.watch(
      preferencesProvider.select((value) => value.showSignatures),
    );
    if (!showSignatures) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.62),
      fontSize: fontSize,
      height: 1.4,
    );

    return SelectionContainer.disabled(
      child: Padding(
        padding: margin,
        child: Container(
          padding: contentPadding,
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.5,
              ),
            ),
          ),
          child: CollapsedHtmlContent(
            html: signature,
            textStyle: textStyle,
            maxLines: maxLines,
          ),
        ),
      ),
    );
  }
}
