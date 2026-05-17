import 'package:ai_model_manager/ai_model_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/topic_ai/topic_ai_context_service.dart';

void main() {
  group('TopicAiContextService', () {
    const service = TopicAiContextService();

    test(
      'loadContextPosts reuses cache and only fetches missing posts',
      () async {
        final fetchCalls = <List<int>>[];
        final detail = TopicDetail(
          id: 42,
          title: 'Topic',
          slug: 'topic',
          postsCount: 4,
          postStream: PostStream(
            posts: [
              _buildPost(id: 1, postNumber: 1, username: 'alice'),
              _buildPost(id: 4, postNumber: 4, username: 'dave'),
            ],
            stream: const [1, 2, 3, 4],
          ),
          categoryId: 1,
          closed: false,
          archived: false,
        );

        final posts = await service.loadContextPosts(
          topicId: 42,
          detail: detail,
          scope: ContextScope.all,
          cachedPosts: const [
            TopicAiContextPost(
              postId: 2,
              postNumber: 2,
              username: 'bob',
              cooked: '<p>cached</p>',
            ),
          ],
          fetchPosts: (topicId, postIds) async {
            fetchCalls.add(postIds);
            return PostStream(
              posts: [_buildPost(id: 3, postNumber: 3, username: 'carol')],
              stream: postIds,
            );
          },
        );

        expect(fetchCalls, [
          [3],
        ]);
        expect(posts.map((post) => post.postId), [1, 2, 3, 4]);
        expect(posts.map((post) => post.postNumber), [1, 2, 3, 4]);
        expect(posts[1].username, 'bob');
        expect(posts[2].username, 'carol');
      },
    );

    test('postCountForScope respects configured limits', () {
      expect(service.postCountForScope(ContextScope.firstPostOnly, 8), 1);
      expect(service.postCountForScope(ContextScope.first5, 3), 3);
      expect(service.postCountForScope(ContextScope.first10, 12), 10);
      expect(service.postCountForScope(ContextScope.first20, 25), 20);
      expect(service.postCountForScope(ContextScope.all, 7), 7);
    });
  });
}

Post _buildPost({
  required int id,
  required int postNumber,
  required String username,
}) {
  final now = DateTime(2026, 1, 1);
  return Post(
    id: id,
    username: username,
    avatarTemplate: '',
    cooked: '<p>Post $postNumber</p>',
    postNumber: postNumber,
    postType: 1,
    updatedAt: now,
    createdAt: now,
    likeCount: 0,
    replyCount: 0,
  );
}
