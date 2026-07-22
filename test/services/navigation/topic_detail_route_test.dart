import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/pages/topic_detail_page/topic_detail_page.dart';
import 'package:fluxdo/services/navigation/horizontal_pop_gesture_blocker.dart';
import 'package:fluxdo/services/navigation/pop_passthrough_material_page_route.dart';
import 'package:fluxdo/services/navigation/topic_detail_route.dart';
import 'package:fluxdo/widgets/post/post_item/quote_selection_helper.dart';

void main() {
  test('帖子详情 route 启用首页同款横向返回手势', () {
    final route = buildTopicDetailRoute<void>(topicId: 42);

    expect(route, isA<PopPassthroughMaterialPageRoute<void>>());
    final topicRoute = route as PopPassthroughMaterialPageRoute<void>;
    expect(topicRoute.enableHorizontalPopGesture, isTrue);
    expect(
      topicRoute.horizontalPopGestureBlocker,
      same(QuoteSelectionHelper.selectionActiveListenable),
    );
    expect(
      topicRoute.additionalHorizontalPopGestureBlocker,
      same(HorizontalPopGestureBlocker.activeListenable),
    );
  });

  testWidgets('all topic entry data shapes build the shared detail page', (
    tester,
  ) async {
    final previewTopic = Topic(
      id: 42,
      title: 'Topic',
      slug: 'topic',
      postsCount: 3,
      replyCount: 2,
      views: 10,
      likeCount: 1,
      categoryId: '1',
    );
    final routes = [
      buildTopicDetailRoute<void>(
        topicId: 42,
        initialTopicPreview: previewTopic,
        initialFirstPostHtml: '<p>home</p>',
      ),
      buildTopicDetailRoute<void>(
        topicId: 42,
        initialTopicPreview: previewTopic,
        initialFirstPostHtml: '<p>preview dialog</p>',
      ),
      buildTopicDetailRoute<void>(
        topicId: 42,
        scrollToPostNumber: 2,
        initialTopicPreview: previewTopic,
        initialFirstPostHtml: '<p>search</p>',
      ),
      buildTopicDetailRoute<void>(
        topicId: 42,
        scrollToPostNumber: 3,
        initialTopicPreview: previewTopic,
        initialFirstPostHtml: '<p>bookmark</p>',
      ),
      buildTopicDetailRoute<void>(topicId: 42, scrollToPostNumber: 4),
    ];

    final builtPages = <TopicDetailPage>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            builtPages.addAll(
              routes.map(
                (route) =>
                    ((route as PopPassthroughMaterialPageRoute<void>).builder(
                          context,
                        )
                        as TopicDetailPage),
              ),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(builtPages, hasLength(5));
    expect(
      routes.map((route) => route.settings.name),
      everyElement('topic_detail'),
    );
    expect(builtPages.map((page) => page.topicId), everyElement(42));
    expect(builtPages[0].initialFirstPostHtml, '<p>home</p>');
    expect(builtPages[1].initialFirstPostHtml, '<p>preview dialog</p>');
    expect(builtPages[2].scrollToPostNumber, 2);
    expect(builtPages[3].scrollToPostNumber, 3);
    expect(builtPages[4].scrollToPostNumber, 4);
  });
}
