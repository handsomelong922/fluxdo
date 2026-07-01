import 'package:flutter/material.dart';

import '../../models/topic.dart';
import '../../pages/topic_detail_page/topic_detail_page.dart';
import '../../widgets/post/post_item/quote_selection_helper.dart';
import 'pop_passthrough_material_page_route.dart';

Route<T> buildTopicDetailRoute<T>({
  required int topicId,
  String? initialTitle,
  int? scrollToPostNumber,
  Topic? initialTopicPreview,
  String? initialFirstPostHtml,
  bool autoSwitchToMasterDetail = false,
  String? instanceId,
  bool? initialNestedView,
}) {
  return PopPassthroughMaterialPageRoute<T>(
    enableHorizontalPopGesture: true,
    horizontalPopGestureBlocker: QuoteSelectionHelper.selectionActiveListenable,
    builder: (_) => TopicDetailPage(
      topicId: topicId,
      initialTitle: initialTitle,
      scrollToPostNumber: scrollToPostNumber,
      initialTopicPreview: initialTopicPreview,
      initialFirstPostHtml: initialFirstPostHtml,
      autoSwitchToMasterDetail: autoSwitchToMasterDetail,
      instanceId: instanceId,
      initialNestedView: initialNestedView,
    ),
  );
}
