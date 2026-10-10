import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/l10n/s.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/filtered_topics_page.dart';
import 'package:fluxdo/utils/topic_keyword_filter.dart';
import 'package:fluxdo/widgets/topic/keyword_filter_hint_bar.dart';

Topic _topic(int id, String title) => Topic(
  id: id,
  title: title,
  slug: 'topic-$id',
  postsCount: 1,
  replyCount: 0,
  views: 0,
  likeCount: 0,
  categoryId: '1',
  posters: [
    TopicPoster(
      userId: id,
      description: '',
      extras: '',
      user: TopicUser(id: id, username: 'author$id', avatarTemplate: ''),
    ),
  ],
);

void main() {
  testWidgets(
    'count opens loaded snapshot, no Manage, selecting uses source navigation',
    (tester) async {
      Topic? opened;
      final entries = [
        FilteredTopic(
          _topic(1, 'Literal hidden title'),
          TopicFilterReason.keyword,
          keyword: 'literal',
        ),
        FilteredTopic(_topic(2, 'Regex hidden title'), TopicFilterReason.regex),
        FilteredTopic(
          _topic(3, 'Blocked hidden title'),
          TopicFilterReason.blockedUser,
        ),
      ];
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: Scaffold(
              body: KeywordFilterHintBar(
                hiddenTopics: entries,
                onOpenTopic: (topic) => opened = topic,
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('Manage'), findsNothing);
      expect(find.textContaining('管理'), findsNothing);
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      expect(find.byType(FilteredTopicsPage), findsOneWidget);
      expect(find.text('Ignored topics (3)'), findsOneWidget);
      expect(find.textContaining('Snapshot of loaded topics'), findsOneWidget);
      expect(find.text('@author1 · Keyword: literal'), findsOneWidget);
      expect(find.text('@author2 · Regex match'), findsOneWidget);
      expect(find.text('@author3 · Blocked user'), findsOneWidget);
      expect(find.byType(ListTile), findsNWidgets(3));
      expect(find.byType(Image), findsNothing);
      expect(opened, isNull);
      await tester.tap(find.byKey(const ValueKey('filtered-topic-2')));
      await tester.pumpAndSettle();
      expect(opened?.id, 2);
      expect(find.byType(FilteredTopicsPage), findsNothing);
    },
  );

  testWidgets(
    'selection survives source banner removal while snapshot is open',
    (tester) async {
      late StateSetter updateSource;
      var showBanner = true;
      Topic? opened;
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                updateSource = setState;
                return Scaffold(
                  body: showBanner
                      ? KeywordFilterHintBar(
                          hiddenTopics: [
                            FilteredTopic(
                              _topic(9, 'Review me'),
                              TopicFilterReason.regex,
                            ),
                          ],
                          onOpenTopic: (topic) {
                            if (context.mounted) opened = topic;
                          },
                        )
                      : const SizedBox.shrink(),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.byType(InkWell).first);
      await tester.pumpAndSettle();
      updateSource(() => showBanner = false);
      await tester.pump();
      expect(
        find.byType(KeywordFilterHintBar, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(FilteredTopicsPage), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('filtered-topic-9')));
      await tester.pumpAndSettle();
      expect(opened?.id, 9);
    },
  );

  testWidgets('empty confirmed snapshot has no banner', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: KeywordFilterHintBar(
          hiddenTopics: const [],
          onOpenTopic: (_) => fail('No row to open'),
        ),
      ),
    );
    expect(find.byType(InkWell), findsNothing);
  });
}
