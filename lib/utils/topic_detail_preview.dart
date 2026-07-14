import '../models/topic.dart';

/// 将已经展示过的主帖 HTML 组装为只含首帖的详情快照。
TopicDetail buildTopicDetailPreview({
  required Topic topic,
  required String previewHtml,
  String? initialTitle,
}) {
  final createdBy = topic.posters.firstOrNull?.user;
  final previewTime = topic.createdAt ?? topic.lastPostedAt ?? DateTime.now();
  final previewPost = Post(
    id: topic.id * 1000000 + 1,
    topicId: topic.id,
    username: createdBy?.username ?? topic.lastPosterUsername ?? '',
    avatarTemplate: createdBy?.avatarTemplate ?? '',
    animatedAvatar: createdBy?.animatedAvatar,
    cooked: previewHtml,
    postNumber: 1,
    postType: 1,
    updatedAt: previewTime,
    createdAt: previewTime,
    likeCount: 0,
    // 临时首帖 id 不能用于请求 /posts/{id}/replies。
    replyCount: 0,
    read: true,
    userId: createdBy?.id,
  );

  return TopicDetail(
    id: topic.id,
    title: initialTitle ?? topic.title,
    slug: topic.slug,
    postsCount: topic.postsCount,
    postStream: PostStream(
      posts: [previewPost],
      stream: [previewPost.id],
      gaps: const PostStreamGaps(),
    ),
    categoryId: int.tryParse(topic.categoryId) ?? 0,
    closed: topic.closed,
    archived: topic.archived,
    tags: topic.tags,
    views: topic.views,
    likeCount: topic.likeCount,
    createdAt: topic.createdAt ?? previewTime,
    lastReadPostNumber: topic.lastReadPostNumber,
    createdBy: createdBy,
    bookmarked: topic.bookmarkableType == 'Topic' && topic.bookmarkId != null,
    bookmarkId: topic.bookmarkableType == 'Topic' ? topic.bookmarkId : null,
    bookmarkName: topic.bookmarkableType == 'Topic' ? topic.bookmarkName : null,
    bookmarkReminderAt: topic.bookmarkableType == 'Topic'
        ? topic.bookmarkReminderAt
        : null,
    hasAcceptedAnswer: topic.hasAcceptedAnswer,
  );
}
