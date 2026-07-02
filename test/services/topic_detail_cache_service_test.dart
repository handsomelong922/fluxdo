import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/topic_detail_cache_service.dart';

void main() {
  group('TopicDetailCacheService', () {
    late DateTime now;
    late TopicDetailCacheService cache;

    setUp(() {
      now = DateTime.utc(2026, 6, 13, 10);
      cache = TopicDetailCacheService(maxEntries: 2, now: () => now);
    });

    test('returns cached detail for the same topic and user', () {
      final detail = _detail(topicId: 42, postNumbers: [1, 2]);

      cache.write(detail, username: 'alice');

      final entry = cache.read(42, username: 'alice');
      expect(entry?.detail, same(detail));
    });

    test('keeps entries isolated by username', () {
      cache.write(
        _detail(topicId: 42, postNumbers: [1], title: 'alice'),
        username: 'alice',
      );
      cache.write(
        _detail(topicId: 42, postNumbers: [1], title: 'bob'),
        username: 'bob',
      );

      expect(cache.read(42, username: 'alice')?.detail.title, 'alice');
      expect(cache.read(42, username: 'bob')?.detail.title, 'bob');
    });

    test('misses when target post is not loaded in the snapshot', () {
      cache.write(_detail(topicId: 42, postNumbers: [1, 2]));

      expect(cache.read(42, targetPostNumber: 9), isNull);
    });

    test('marks entries stale after the soft ttl', () {
      cache.write(_detail(topicId: 42, postNumbers: [1]));
      final fresh = cache.read(42)!;
      expect(cache.shouldRevalidate(fresh), isFalse);

      now = now.add(TopicDetailCacheService.defaultSoftTtl);
      final stale = cache.read(42)!;
      expect(cache.shouldRevalidate(stale), isTrue);
    });

    test('preview seed always revalidates in background', () {
      cache.writePreviewSeed(_detail(topicId: 42, postNumbers: [1]));

      final seeded = cache.read(42)!;
      expect(seeded.isPreviewSeed, isTrue);
      expect(cache.shouldRevalidate(seeded), isTrue);
    });

    test('expires entries after the hard ttl', () {
      cache.write(_detail(topicId: 42, postNumbers: [1]));

      now = now.add(TopicDetailCacheService.defaultHardTtl);

      expect(cache.read(42), isNull);
    });

    test('evicts the least recently used entry', () {
      cache.write(_detail(topicId: 1, postNumbers: [1]));
      cache.write(_detail(topicId: 2, postNumbers: [1]));
      cache.read(1);

      cache.write(_detail(topicId: 3, postNumbers: [1]));

      expect(cache.read(1), isNotNull);
      expect(cache.read(2), isNull);
      expect(cache.read(3), isNotNull);
    });
  });
}

TopicDetail _detail({
  required int topicId,
  required List<int> postNumbers,
  String title = 'Topic',
}) {
  final posts = [
    for (final postNumber in postNumbers)
      _post(id: topicId * 100 + postNumber, postNumber: postNumber),
  ];
  return TopicDetail(
    id: topicId,
    title: title,
    slug: 'topic-$topicId',
    postsCount: posts.length,
    postStream: PostStream(
      posts: posts,
      stream: posts.map((post) => post.id).toList(),
    ),
    categoryId: 1,
    closed: false,
    archived: false,
  );
}

Post _post({required int id, required int postNumber}) {
  final now = DateTime.utc(2026, 6, 13);
  return Post(
    id: id,
    username: 'alice',
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
