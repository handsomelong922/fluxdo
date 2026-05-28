import 'package:flutter/material.dart';

import '../pages/topic_detail_page/topic_detail_page.dart';

void openInternalTopicLink(
  BuildContext context, {
  required int currentTopicId,
  required int targetTopicId,
  required String? topicSlug,
  required int? postNumber,
  required void Function(int postNumber)? onJumpToPost,
  bool preserveCurrentTopic = true,
}) {
  if (preserveCurrentTopic &&
      targetTopicId == currentTopicId &&
      postNumber != null &&
      onJumpToPost != null) {
    onJumpToPost(postNumber);
    return;
  }

  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TopicDetailPage(
        topicId: targetTopicId,
        initialTitle: topicSlug,
        scrollToPostNumber: postNumber,
      ),
    ),
  );
}
