import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('TopicDetail related_topics parsing', () {
    test('keeps null when the response omits related_topics', () {
      final detail = TopicDetail.fromJson(_topicJson());

      expect(detail.relatedTopics, isNull);
    });

    test('keeps an explicit empty related_topics list', () {
      final detail = TopicDetail.fromJson(
        _topicJson(relatedTopics: const <Map<String, dynamic>>[]),
      );

      expect(detail.relatedTopics, isEmpty);
    });

    test('parses related_topics and ignores suggested_topics', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          relatedTopics: [
            _relatedTopicJson(
              id: 7,
              title: 'Related',
              createdAt: '2026-07-01T00:00:00.000Z',
            ),
          ],
          suggestedTopics: [
            _relatedTopicJson(
              id: 8,
              title: 'Suggested',
              createdAt: '2026-07-02T00:00:00.000Z',
            ),
          ],
        ),
      );

      expect(detail.relatedTopics, hasLength(1));
      expect(detail.relatedTopics!.single.id, 7);
      expect(detail.relatedTopics!.single.title, 'Related');
      expect(
        detail.relatedTopics!.single.createdAt?.toUtc(),
        DateTime.utc(2026, 7, 1),
      );
    });

    test('copyWith preserves old data unless a new list is supplied', () {
      final related = [
        Topic(
          id: 7,
          title: 'Related',
          slug: 'related',
          postsCount: 1,
          replyCount: 0,
          views: 0,
          likeCount: 0,
          categoryId: '1',
        ),
      ];
      final detail = TopicDetail.fromJson(
        _topicJson(),
      ).copyWith(relatedTopics: related);

      expect(detail.copyWith(title: 'Updated').relatedTopics, same(related));
      expect(detail.copyWith(relatedTopics: const []).relatedTopics, isEmpty);
    });
  });
}

Map<String, dynamic> _topicJson({
  List<Map<String, dynamic>>? relatedTopics,
  List<Map<String, dynamic>>? suggestedTopics,
}) {
  final json = <String, dynamic>{
    'id': 42,
    'title': 'Topic',
    'slug': 'topic',
    'posts_count': 1,
    'category_id': 1,
    'post_stream': {
      'posts': [
        {
          'id': 101,
          'post_number': 1,
          'username': 'tester',
          'cooked': '<p>topic</p>',
        },
      ],
      'stream': [101],
    },
  };
  if (relatedTopics != null) {
    json['related_topics'] = relatedTopics;
  }
  if (suggestedTopics != null) {
    json['suggested_topics'] = suggestedTopics;
  }
  return json;
}

Map<String, dynamic> _relatedTopicJson({
  required int id,
  required String title,
  required String createdAt,
}) {
  return {
    'id': id,
    'title': title,
    'slug': 'topic-$id',
    'posts_count': 1,
    'reply_count': 0,
    'views': 0,
    'like_count': 0,
    'category_id': 1,
    'created_at': createdAt,
  };
}
