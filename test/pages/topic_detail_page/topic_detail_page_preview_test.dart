import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_detail_page.dart';

void main() {
  test(
    'buildTopicDetailPreviewFromTopic preserves header and first-post data',
    () {
      final topic = Topic(
        id: 42,
        title: '原始标题',
        slug: 'sample-topic',
        postsCount: 8,
        replyCount: 7,
        views: 321,
        likeCount: 12,
        categoryId: '9',
        createdAt: DateTime(2026, 6, 30, 12),
        tags: const [Tag(id: 1, name: 'flutter')],
        posters: [
          TopicPoster(
            userId: 7,
            description: 'Original Poster',
            extras: '',
            user: TopicUser(
              id: 7,
              username: 'alice',
              avatarTemplate: '/user_avatar/example/{size}/7.png',
            ),
          ),
        ],
        hasAcceptedAnswer: true,
      );

      final preview = buildTopicDetailPreviewFromTopic(
        topic: topic,
        previewHtml: '<p>首帖正文</p>',
        initialTitle: '详情页标题',
      );

      expect(preview.id, 42);
      expect(preview.title, '详情页标题');
      expect(preview.postsCount, 8);
      expect(preview.views, 321);
      expect(preview.likeCount, 12);
      expect(preview.categoryId, 9);
      expect(preview.hasAcceptedAnswer, isTrue);
      expect(preview.createdBy?.username, 'alice');
      expect(preview.postStream.posts, hasLength(1));
      expect(preview.postStream.posts.single.postNumber, 1);
      expect(preview.postStream.posts.single.username, 'alice');
      expect(preview.postStream.posts.single.cooked, '<p>首帖正文</p>');
    },
  );

  test(
    'mergeTopicDetailWithInitialPreview keeps preloaded first post html',
    () {
      final now = DateTime(2026, 6, 30, 12);
      final preview = TopicDetail(
        id: 42,
        title: '标题',
        slug: 'sample-topic',
        postsCount: 3,
        postStream: PostStream(
          posts: [
            _post(
              id: 42000001,
              postNumber: 1,
              cooked: '<p>首页预加载正文</p>',
              createdAt: now,
            ),
          ],
          stream: const [42000001],
        ),
        categoryId: 9,
        closed: false,
        archived: false,
      );
      final loaded = TopicDetail(
        id: 42,
        title: '标题',
        slug: 'sample-topic',
        postsCount: 3,
        postStream: PostStream(
          posts: [
            _post(
              id: 101,
              postNumber: 1,
              cooked: '<p>网络首帖正文</p>',
              createdAt: now,
            ),
            _post(
              id: 102,
              postNumber: 2,
              cooked: '<p>回复楼层</p>',
              createdAt: now,
            ),
          ],
          stream: const [101, 102, 103],
        ),
        categoryId: 9,
        closed: false,
        archived: false,
      );

      final merged = mergeTopicDetailWithInitialPreview(
        detail: loaded,
        previewDetail: preview,
      );

      expect(merged.postStream.posts.first.id, 101);
      expect(merged.postStream.posts.first.cooked, '<p>首页预加载正文</p>');
      expect(merged.postStream.posts[1].cooked, '<p>回复楼层</p>');
      expect(merged.postStream.stream, const [101, 102, 103]);
    },
  );
}

Post _post({
  required int id,
  required int postNumber,
  required String cooked,
  required DateTime createdAt,
}) {
  return Post(
    id: id,
    username: 'alice',
    avatarTemplate: '/avatar/{size}.png',
    cooked: cooked,
    postNumber: postNumber,
    postType: 1,
    updatedAt: createdAt,
    createdAt: createdAt,
    likeCount: 0,
    replyCount: 0,
  );
}
