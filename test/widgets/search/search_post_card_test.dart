import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/search_result.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/home_topic_excerpt_provider.dart';
import 'package:fluxdo/providers/category_provider.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/services/local_notification_service.dart';
import 'package:fluxdo/utils/time_utils.dart';
import 'package:fluxdo/widgets/search/search_post_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('searchPostToTopicPreview carries preview data for detail handoff', () {
    final createdAt = DateTime.now().subtract(const Duration(days: 1));
    final post = SearchPost(
      id: 1,
      username: 'tester',
      avatarTemplate: '/user_avatar/example/{size}/1.png',
      createdAt: createdAt,
      likeCount: 5,
      blurb: '<p>搜索摘要正文</p>',
      postNumber: 3,
      topic: SearchTopic(
        id: 9,
        title: '搜索结果标题',
        slug: 'search-topic',
        tags: const [Tag(id: 1, name: 'flutter')],
        postsCount: 12,
        views: 99,
        closed: false,
        archived: false,
      ),
    );

    final topic = searchPostToTopicPreview(post);

    expect(topic.id, 9);
    expect(topic.title, '搜索结果标题');
    expect(topic.slug, 'search-topic');
    expect(topic.excerpt, '<p>搜索摘要正文</p>');
    expect(topic.replyCount, 11);
    expect(topic.tags.single.name, 'flutter');
    expect(topic.posters.single.user?.username, 'tester');
  });

  test('searchPostPreviewHtml ignores blank blurbs', () {
    final post = SearchPost(
      id: 1,
      username: 'tester',
      avatarTemplate: '/user_avatar/example/{size}/1.png',
      createdAt: DateTime.now(),
      likeCount: 0,
      blurb: '   ',
      postNumber: 1,
    );

    expect(searchPostPreviewHtml(post), isNull);
    expect(searchPostToTopicPreview(post).excerpt, isNull);
  });

  test('searchPostDetailFallbackHtml only uses blurb for first-post hits', () {
    final firstPost = SearchPost(
      id: 1,
      username: 'tester',
      avatarTemplate: '/user_avatar/example/{size}/1.png',
      createdAt: DateTime.now(),
      likeCount: 0,
      blurb: '<p>主帖摘要</p>',
      postNumber: 1,
    );
    final replyHit = SearchPost(
      id: 2,
      username: 'tester',
      avatarTemplate: '/user_avatar/example/{size}/1.png',
      createdAt: DateTime.now(),
      likeCount: 0,
      blurb: '<p>回复命中片段</p>',
      postNumber: 8,
    );

    expect(searchPostDetailFallbackHtml(firstPost), '<p>主帖摘要</p>');
    expect(searchPostDetailFallbackHtml(replyHit), isNull);
  });

  test('searchPostToTopicPreview accepts explicit first-post html override', () {
    final createdAt = DateTime.now();
    final post = SearchPost(
      id: 1,
      username: 'tester',
      avatarTemplate: '/user_avatar/example/{size}/1.png',
      createdAt: createdAt,
      likeCount: 5,
      blurb: '<p>搜索命中片段</p>',
      postNumber: 3,
      topic: SearchTopic(
        id: 9,
        title: '搜索结果标题',
        slug: 'search-topic',
        tags: const [Tag(id: 1, name: 'flutter')],
        postsCount: 12,
        views: 99,
        closed: false,
        archived: false,
      ),
    );

    final topic = searchPostToTopicPreview(
      post,
      excerptHtml: '<p>真实主帖正文</p>',
    );

    expect(topic.excerpt, '<p>真实主帖正文</p>');
  });

  test('resolveSearchTopicDetailPreview prefers fetched first-post html', () async {
    final createdAt = DateTime.now();
    final post = SearchPost(
      id: 1,
      username: 'tester',
      avatarTemplate: '/user_avatar/example/{size}/1.png',
      createdAt: createdAt,
      likeCount: 5,
      blurb: '<p>搜索命中片段</p>',
      postNumber: 8,
      topic: SearchTopic(
        id: 9,
        title: '搜索结果标题',
        slug: 'search-topic',
        tags: const [Tag(id: 1, name: 'flutter')],
        postsCount: 12,
        views: 99,
        closed: false,
        archived: false,
      ),
    );
    final loader = HomeTopicExcerptLoader(
      fetchPreview: (topicId) async => _previewDetail(
        topicId,
        html: '<p>真实主帖正文</p>',
      ),
    );

    final preview = await resolveSearchTopicDetailPreview(
      loader: loader,
      post: post,
    );

    expect(preview.firstPostHtml, '<p>真实主帖正文</p>');
    expect(preview.topic.excerpt, '<p>真实主帖正文</p>');
  });

  test(
    'resolveSearchTopicDetailPreview does not fall back to reply blurb for non-first-post hits',
    () async {
      final createdAt = DateTime.now();
      final post = SearchPost(
        id: 1,
        username: 'tester',
        avatarTemplate: '/user_avatar/example/{size}/1.png',
        createdAt: createdAt,
        likeCount: 5,
        blurb: '<p>搜索命中片段</p>',
        postNumber: 8,
        topic: SearchTopic(
          id: 9,
          title: '搜索结果标题',
          slug: 'search-topic',
          tags: const [Tag(id: 1, name: 'flutter')],
          postsCount: 12,
          views: 99,
          closed: false,
          archived: false,
        ),
      );
      final loader = HomeTopicExcerptLoader(
        fetchPreview: (topicId) async => null,
      );

      final preview = await resolveSearchTopicDetailPreview(
        loader: loader,
        post: post,
      );

      expect(preview.firstPostHtml, isNull);
      expect(preview.topic.excerpt, isNull);
    },
  );

  testWidgets('SearchPostCard keeps home-style meta info on the right side', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final createdAt = DateTime.now().subtract(const Duration(days: 1));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          categoryMapProvider.overrideWithValue(const AsyncValue.data({})),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SearchPostCard(
              post: SearchPost(
                id: 1,
                username: 'tester',
                avatarTemplate: '/user_avatar/example/{size}/1.png',
                createdAt: createdAt,
                likeCount: 5,
                blurb: '<p>搜索摘要正文</p>',
                postNumber: 3,
                topic: SearchTopic(
                  id: 9,
                  title: '搜索结果标题',
                  slug: 'search-topic',
                  tags: const [Tag(id: 1, name: 'flutter')],
                  postsCount: 12,
                  views: 99,
                  closed: false,
                  archived: false,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text('搜索结果标题'), findsOneWidget);
    expect(find.text('搜索摘要正文'), findsOneWidget);
    expect(find.text('#3'), findsNothing);
    expect(find.text('11'), findsOneWidget);
    expect(find.text('5'), findsOneWidget);
    expect(find.text(TimeUtils.formatRelativeTime(createdAt)), findsOneWidget);
  });
}

TopicDetail _previewDetail(int topicId, {required String html}) {
  final now = DateTime.now();
  return TopicDetail(
    id: topicId,
    title: 'topic $topicId',
    slug: 'topic-$topicId',
    postsCount: 3,
    postStream: PostStream(
      posts: [
        Post(
          id: topicId * 1000 + 1,
          username: 'tester',
          avatarTemplate: '/user_avatar/example/{size}/1.png',
          cooked: html,
          postNumber: 1,
          postType: 1,
          updatedAt: now,
          createdAt: now,
          likeCount: 0,
          replyCount: 2,
        ),
      ],
      stream: [topicId * 1000 + 1],
    ),
    categoryId: 1,
    closed: false,
    archived: false,
  );
}
