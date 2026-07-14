import 'package:flutter/material.dart';
import '../../models/topic.dart';
import '../../providers/preferences_provider.dart';
import '../../utils/responsive.dart';
import 'topic_card.dart';
import 'topic_preview_dialog.dart';

/// 话题卡片渲染公共函数
///
/// 处理 pinned/normal 卡片选择、预览触发方式、响应式宽度包装。
Widget buildTopicItem({
  required BuildContext context,
  required Topic topic,
  required bool isSelected,
  required VoidCallback onTap,
  required TopicPreviewTrigger previewTrigger,
  Color? highlightColor,
  Color? titleColor,
  bool denseMetadata = false,
  int? maxVisibleTags,
  Widget? topWidget,
  Widget? bottomWidget,
  List<PreviewAction>? previewActions,
}) {
  void showPreview() {
    TopicPreviewDialog.show(
      context,
      topic: topic,
      onOpen: onTap,
      actions: previewActions,
      trigger: previewTrigger,
    );
  }

  final onLongPress = previewTrigger == TopicPreviewTrigger.longPress
      ? showPreview
      : null;
  final onPreviewTap = previewTrigger == TopicPreviewTrigger.rightSideTap
      ? showPreview
      : null;
  Widget child;

  if (topic.pinned) {
    child = CompactTopicCard(
      topic: topic,
      onTap: onTap,
      onLongPress: onLongPress,
      onPreviewTap: onPreviewTap,
      isSelected: isSelected,
      highlightColor: highlightColor,
    );
  } else {
    child = TopicCard(
      topic: topic,
      onTap: onTap,
      onLongPress: onLongPress,
      onPreviewTap: onPreviewTap,
      isSelected: isSelected,
      highlightColor: highlightColor,
      topWidget: topWidget,
      bottomWidget: bottomWidget,
      titleColor: titleColor,
      denseMetadata: denseMetadata,
      maxVisibleTags: maxVisibleTags,
    );
  }

  if (!Responsive.isMobile(context)) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: Breakpoints.maxContentWidth,
        ),
        child: child,
      ),
    );
  }
  return child;
}
