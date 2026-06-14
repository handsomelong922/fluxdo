import 'package:flutter/material.dart';

import '../services/navigation/topic_detail_route.dart';

void openInternalTopicLink(
  BuildContext context, {
  required int currentTopicId,
  required int targetTopicId,
  required String? topicSlug,
  required int? postNumber,
  required void Function(int postNumber)? onJumpToPost,
  bool preserveCurrentTopic = true,
  bool? initialNestedView,
}) {
  if (preserveCurrentTopic &&
      targetTopicId == currentTopicId &&
      postNumber != null &&
      onJumpToPost != null) {
    onJumpToPost(postNumber);
    return;
  }

  Navigator.of(context).push(
    buildTopicDetailRoute<void>(
      topicId: targetTopicId,
      initialTitle: topicSlug,
      scrollToPostNumber: postNumber,
      initialNestedView: initialNestedView,
    ),
  );
}
