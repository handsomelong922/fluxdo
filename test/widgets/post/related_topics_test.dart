import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/app_localizations.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/widgets/post/related_topics.dart';

void main() {
  test('selectRelatedTopics sorts, filters and limits related topics', () {
    final topics = [
      _topic(42, 'Current', DateTime.utc(2026, 7, 10)),
      _topic(1, 'Oldest', DateTime.utc(2026, 1, 1)),
      _topic(2, 'Second', DateTime.utc(2026, 7, 2)),
      _topic(3, '', DateTime.utc(2026, 7, 9)),
      _topic(4, 'Fourth', null),
      _topic(5, 'Newest', DateTime.utc(2026, 7, 5)),
      _topic(6, 'Third', DateTime.utc(2026, 7, 1)),
      _topic(7, 'Sixth', DateTime.utc(2025, 12, 1)),
    ];

    final selected = selectRelatedTopics(topics, currentTopicId: 42);

    expect(selected.map((topic) => topic.id), [5, 2, 6, 1, 7]);
  });

  testWidgets('is expanded by default and hides when there is no data', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RelatedTopics(
          currentTopicId: 42,
          topics: [_topic(7, 'Related title', DateTime.utc(2026, 7, 1))],
        ),
      ),
    );

    expect(find.text('Related title'), findsOneWidget);

    await tester.tap(find.text('相关帖子'));
    await tester.pumpAndSettle();
    expect(find.text('Related title'), findsNothing);

    await tester.pumpWidget(
      _app(const RelatedTopics(currentTopicId: 42, topics: [])),
    );
    expect(find.text('相关帖子'), findsNothing);
  });

  testWidgets('initial rendering only shows titles and does not navigate', (
    tester,
  ) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      _app(
        RelatedTopics(
          currentTopicId: 42,
          topics: [
            _topic(7, 'Related title', DateTime.utc(2026, 7, 1)),
            _topic(8, 'Another title', DateTime.utc(2026, 7, 2)),
          ],
        ),
        navigatorObservers: [observer],
      ),
    );

    expect(find.text('Related title'), findsOneWidget);
    expect(find.text('Another title'), findsOneWidget);
    expect(observer.topicDetailPushes, 0);
  });

  testWidgets('opens the shared topic detail route', (tester) async {
    final observer = _RecordingNavigatorObserver();
    await tester.pumpWidget(
      _app(
        RelatedTopics(
          currentTopicId: 42,
          topics: [_topic(7, 'Related title', DateTime.utc(2026, 7, 1))],
        ),
        navigatorObservers: [observer],
      ),
    );

    await tester.tap(find.text('Related title'));

    expect(observer.lastRoute?.settings.name, 'topic_detail');
    expect(observer.lastRoute?.settings.arguments, {'topicId': 7});
  });

  testWidgets('switching to another topic resets the section to expanded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        RelatedTopics(
          currentTopicId: 42,
          topics: [_topic(7, 'First related', DateTime.utc(2026, 7, 1))],
        ),
      ),
    );

    await tester.tap(find.text('相关帖子'));
    await tester.pumpAndSettle();
    expect(find.text('First related'), findsNothing);

    await tester.pumpWidget(
      _app(
        RelatedTopics(
          currentTopicId: 43,
          topics: [_topic(8, 'Next related', DateTime.utc(2026, 7, 2))],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Next related'), findsOneWidget);
  });
}

Widget _app(
  Widget child, {
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  return MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    navigatorObservers: navigatorObservers,
    home: Scaffold(body: child),
  );
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastRoute;
  int topicDetailPushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastRoute = route;
    if (route.settings.name == 'topic_detail') topicDetailPushes++;
    super.didPush(route, previousRoute);
  }
}

Topic _topic(int id, String title, DateTime? createdAt) {
  return Topic(
    id: id,
    title: title,
    slug: 'topic-$id',
    postsCount: 1,
    replyCount: 0,
    views: 0,
    likeCount: 0,
    categoryId: '1',
    createdAt: createdAt,
  );
}
