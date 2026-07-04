import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/utils/blocked_user_filter.dart';

Topic _topic(int id, String username) {
  return Topic(
    id: id,
    title: 'topic-$id',
    slug: 'topic-$id',
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
    posters: [
      TopicPoster(
        userId: id,
        description: 'Original Poster',
        extras: '',
        user: TopicUser(
          id: id,
          username: username,
          avatarTemplate: '/user_avatar/test/$username/{size}/1.png',
        ),
      ),
    ],
  );
}

Post _post(int id, String username) {
  return Post(
    id: id,
    username: username,
    avatarTemplate: '/user_avatar/test/$username/{size}/1.png',
    cooked: '<p>post-$id</p>',
    postNumber: id,
    postType: 1,
    updatedAt: DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
    likeCount: 0,
    replyCount: 0,
  );
}

Boost _boost(int id, String username) {
  return Boost(
    id: id,
    cooked: '<p>boost-$id</p>',
    user: BoostUser(
      id: id,
      username: username,
      avatarTemplate: '/user_avatar/test/$username/{size}/1.png',
    ),
  );
}

void main() {
  const blocked = <String>{'blocked-user'};

  setUp(BlockedUserFilter.clearCaches);
  tearDown(BlockedUserFilter.clearCaches);

  test('filters blocked topics posts and boosts', () {
    final visibleTopics = BlockedUserFilter.visibleTopics([
      _topic(1, 'alice'),
      _topic(2, 'blocked-user'),
      _topic(3, 'bob'),
    ], blocked);
    final visiblePosts = BlockedUserFilter.visiblePosts([
      _post(1, 'alice'),
      _post(2, 'blocked-user'),
      _post(3, 'bob'),
    ], blocked);
    final visibleBoosts = BlockedUserFilter.visibleBoosts([
      _boost(1, 'alice'),
      _boost(2, 'blocked-user'),
      _boost(3, 'bob'),
    ], blocked);

    expect(visibleTopics.map((topic) => topic.id), [1, 3]);
    expect(visiblePosts.map((post) => post.id), [1, 3]);
    expect(visibleBoosts.map((boost) => boost.id), [1, 3]);
  });

  test('visible list caches stay bounded', () {
    final iterations = BlockedUserFilter.debugMaxVisibleCacheEntries + 12;

    for (var index = 0; index < iterations; index++) {
      BlockedUserFilter.visibleTopics([
        _topic(index * 10 + 1, 'blocked-user'),
        _topic(index * 10 + 2, 'visible-$index'),
      ], blocked);
      BlockedUserFilter.visiblePosts([
        _post(index * 10 + 1, 'blocked-user'),
        _post(index * 10 + 2, 'visible-$index'),
      ], blocked);
      BlockedUserFilter.visibleBoosts([
        _boost(index * 10 + 1, 'blocked-user'),
        _boost(index * 10 + 2, 'visible-$index'),
      ], blocked);
    }

    expect(
      BlockedUserFilter.debugVisibleTopicsCacheSize,
      lessThanOrEqualTo(BlockedUserFilter.debugMaxVisibleCacheEntries),
    );
    expect(
      BlockedUserFilter.debugVisiblePostsCacheSize,
      lessThanOrEqualTo(BlockedUserFilter.debugMaxVisibleCacheEntries),
    );
    expect(
      BlockedUserFilter.debugVisibleBoostsCacheSize,
      lessThanOrEqualTo(BlockedUserFilter.debugMaxVisibleCacheEntries),
    );
  });
}
