import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/services/settings/content_filter_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('ContentFilterNotifier', () {
    test('normalizes blocked tags and users for repeated matching', () async {
      SharedPreferences.setMockInitialValues({
        ContentFilterNotifier.blockedTagsKey: ['Flutter', 'Dart'],
        ContentFilterNotifier.blockedUsersKey: ['Alice'],
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = ContentFilterNotifier(prefs);

      expect(notifier.state.normalizedBlockedTags, {'flutter', 'dart'});
      expect(notifier.state.normalizedBlockedUsers, {'alice'});
      expect(notifier.matchesTagName('FLUTTER'), isTrue);
      expect(notifier.matchesUsername('alice'), isTrue);
    });

    test('matches topic author and tags without changing semantics', () async {
      SharedPreferences.setMockInitialValues({
        ContentFilterNotifier.blockedTagsKey: ['福利'],
        ContentFilterNotifier.blockedUsersKey: ['bob'],
      });
      final prefs = await SharedPreferences.getInstance();
      final notifier = ContentFilterNotifier(prefs);

      expect(
        notifier.matchesTopic(_topic(tag: '福利', username: 'alice')),
        isTrue,
      );
      expect(notifier.matchesTopic(_topic(tag: '闲聊', username: 'Bob')), isTrue);
      expect(
        notifier.matchesTopic(_topic(tag: '闲聊', username: 'alice')),
        isFalse,
      );
    });
  });
}

Topic _topic({required String tag, required String username}) {
  return Topic(
    id: 1,
    title: 'topic',
    slug: 'topic',
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
    tags: [Tag(name: tag)],
    posters: [
      TopicPoster(
        userId: 1,
        description: 'Original Poster',
        extras: 'latest',
        user: TopicUser(
          id: 1,
          username: username,
          avatarTemplate: '/avatar/{size}.png',
        ),
      ),
    ],
  );
}
