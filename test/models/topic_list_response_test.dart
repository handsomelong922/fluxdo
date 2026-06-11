import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('TopicListResponse.fromJson', () {
    test('parses topic list from raw JSON string response', () {
      final response = TopicListResponse.fromJson(
        jsonEncode({
          'users': [],
          'topic_list': {
            'topics': [_topicJson()],
            'more_topics_url': '/latest.json?page=1',
          },
        }),
      );

      expect(response.topics, hasLength(1));
      expect(response.topics.single.id, 42);
      expect(response.topics.single.title, '测试话题');
      expect(response.moreTopicsUrl, '/latest.json?page=1');
    });

    test('throws FormatException for non JSON string response', () {
      expect(
        () => TopicListResponse.fromJson('<html>not json</html>'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

Map<String, dynamic> _topicJson() {
  return {
    'id': 42,
    'title': '测试话题',
    'slug': 'test-topic',
    'posts_count': 1,
    'reply_count': 0,
    'views': 0,
    'like_count': 0,
    'category_id': 1,
  };
}
