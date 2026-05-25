import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_detail_page.dart';

void main() {
  group('shouldFallbackFilterAfterTargetLoaded', () {
    test('keeps top-level view when the target post is already loaded', () {
      final detail = _detail(
        posts: [_post(id: 101, postNumber: 1), _post(id: 120, postNumber: 20)],
        stream: [101, 120],
      );

      expect(
        shouldFallbackFilterAfterTargetLoaded(
          detail,
          wasSummaryMode: false,
          wasAuthorOnlyMode: false,
          wasTopLevelMode: true,
        ),
        isFalse,
      );
    });

    test('falls back from invalid author-only results', () {
      final detail = _detail(
        createdBy: TopicUser(
          id: 1,
          username: 'alice',
          avatarTemplate: '/avatar/{size}.png',
        ),
        posts: [
          _post(id: 101, postNumber: 1, username: 'alice'),
          _post(id: 102, postNumber: 2, username: 'bob'),
        ],
        stream: [101, 102],
      );

      expect(
        shouldFallbackFilterAfterTargetLoaded(
          detail,
          wasSummaryMode: false,
          wasAuthorOnlyMode: true,
          wasTopLevelMode: false,
        ),
        isTrue,
      );
    });
  });
}

TopicDetail _detail({
  required List<Post> posts,
  required List<int> stream,
  TopicUser? createdBy,
}) {
  return TopicDetail(
    id: 42,
    title: 'Topic',
    slug: 'topic',
    postsCount: stream.length,
    postStream: PostStream(posts: posts, stream: stream),
    categoryId: 1,
    closed: false,
    archived: false,
    createdBy: createdBy,
    hasSummary: true,
  );
}

Post _post({
  required int id,
  required int postNumber,
  String username = 'alice',
}) {
  final now = DateTime.utc(2026, 5, 25);
  return Post(
    id: id,
    username: username,
    avatarTemplate: '/avatar/{size}.png',
    cooked: '<p>post</p>',
    postNumber: postNumber,
    postType: 1,
    updatedAt: now,
    createdAt: now,
    likeCount: 0,
    replyCount: 0,
  );
}
