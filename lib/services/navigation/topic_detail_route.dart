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
  String? highlightBoostUsername,
  bool? initialNestedView,
}) {
  final routeArguments = <String, Object?>{'topicId': topicId};
  if (scrollToPostNumber != null) {
    routeArguments['postNumber'] = scrollToPostNumber;
  }
  if (initialTopicPreview != null) {
    routeArguments['hasTopicPreview'] = true;
  }
  if (initialFirstPostHtml != null) {
    routeArguments['hasFirstPostPreview'] = true;
  }
  if (autoSwitchToMasterDetail) {
    routeArguments['autoSwitchToMasterDetail'] = true;
  }
  if (instanceId != null) {
    routeArguments['hasInstanceId'] = true;
  }
  if (highlightBoostUsername != null) {
    routeArguments['hasBoostHighlight'] = true;
  }
  if (initialNestedView != null) {
    routeArguments['initialNestedView'] = initialNestedView;
  }

  return PopPassthroughMaterialPageRoute<T>(
    settings: RouteSettings(name: 'topic_detail', arguments: routeArguments),
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
      highlightBoostUsername: highlightBoostUsername,
      initialNestedView: initialNestedView,
    ),
  );
}
