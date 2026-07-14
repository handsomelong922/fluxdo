import 'package:flutter/material.dart';

import '../../models/search_result.dart';
import '../../providers/preferences_provider.dart';
import '../topic/topic_preview_dialog.dart';
import 'search_post_card.dart';

/// 搜索结果预览统一复用话题预览弹窗，确保布局、动画和首帖缓存交接一致。
class SearchPreviewDialog {
  const SearchPreviewDialog._();

  static Future<void> show(
    BuildContext context, {
    required SearchPost post,
    VoidCallback? onOpen,
    TopicPreviewTrigger trigger = TopicPreviewTrigger.longPress,
  }) {
    return TopicPreviewDialog.show(
      context,
      topic: searchPostToTopicPreview(post, allowBlurbFallback: false),
      onOpen: onOpen,
      trigger: trigger,
    );
  }
}
