import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/preloaded_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PreloadedDataService().reset();
  });

  tearDown(() {
    PreloadedDataService().reset();
  });

  test(
    'waitForInitialTopicListReady preserves cached startup topic list',
    () async {
      final preloaded = PreloadedDataService();
      final html = _preloadedHtml(
        topicList: {
          'users': [
            {
              'id': 7,
              'username': 'alice',
              'avatar_template': '/user_avatar/linux.do/alice/{size}/1_2.png',
            },
          ],
          'topic_list': {
            'more_topics_url': '/latest.json?page=1',
            'topics': [
              {
                'id': 42,
                'title': 'Startup preloaded topic',
                'slug': 'startup-preloaded-topic',
                'posts_count': 1,
                'reply_count': 0,
                'views': 10,
                'like_count': 3,
                'created_at': '2026-06-30T00:00:00.000Z',
                'last_posted_at': '2026-06-30T00:01:00.000Z',
                'category_id': 1,
                'posters': [
                  {
                    'user_id': 7,
                    'description': 'Original Poster',
                    'extras': 'latest',
                  },
                ],
              },
            ],
          },
        },
      );

      expect(await preloaded.hydrateFromHtml(html), isTrue);

      expect(
        await preloaded.waitForInitialTopicListReady(
          timeout: const Duration(seconds: 2),
        ),
        isTrue,
      );
      expect(preloaded.hasInitialTopicList, isTrue);

      final response = await preloaded.getInitialTopicList();

      expect(response, isNotNull);
      expect(response!.topics.map((topic) => topic.id), [42]);
      expect(response.moreTopicsUrl, '/latest.json?page=1');
      expect(preloaded.hasInitialTopicList, isFalse);
      expect(await preloaded.getInitialTopicList(), isNull);
    },
  );
}

String _preloadedHtml({required Map<String, dynamic> topicList}) {
  final payload = jsonEncode({
    'currentUser': {'id': 1, 'username': 'tester', 'name': 'Tester'},
    'siteSettings': {'min_topic_title_length': 15, 'min_post_length': 8},
    'site': {
      'categories': <Map<String, dynamic>>[],
      'post_action_types': <Map<String, dynamic>>[],
    },
    'topicList': topicList,
  });
  const htmlEscape = HtmlEscape(HtmlEscapeMode.attribute);
  final escapedPayload = htmlEscape.convert(payload);

  return '''
<!doctype html>
<html>
  <head>
    <meta id="data-discourse-setup" data-cdn="https://cdn.linux.do">
  </head>
  <body>
    <div id="data-preloaded" data-preloaded="$escapedPayload"></div>
  </body>
</html>
''';
}
