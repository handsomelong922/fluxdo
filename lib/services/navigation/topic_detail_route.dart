import 'package:flutter/material.dart';

import '../../pages/topic_detail_page/topic_detail_page.dart';
import 'pop_passthrough_material_page_route.dart';

Route<T> buildTopicDetailRoute<T>({
  required int topicId,
  String? initialTitle,
  int? scrollToPostNumber,
  bool autoSwitchToMasterDetail = false,
  String? instanceId,
  bool? initialNestedView,
}) {
  return PopPassthroughMaterialPageRoute<T>(
    enableHorizontalPopGesture: true,
    builder: (_) => TopicDetailPage(
      topicId: topicId,
      initialTitle: initialTitle,
      scrollToPostNumber: scrollToPostNumber,
      autoSwitchToMasterDetail: autoSwitchToMasterDetail,
      instanceId: instanceId,
      initialNestedView: initialNestedView,
    ),
  );
}
