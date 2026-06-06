import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';

void main() {
  group('TopicDetail accepted answer parsing', () {
    test('uses topic-level accepted_answer post_number', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          acceptedAnswer: {'post_number': 5},
          posts: [_post(id: 101, postNumber: 1), _post(id: 105, postNumber: 5)],
        ),
      );

      expect(detail.hasAcceptedAnswer, isTrue);
      expect(detail.acceptedAnswerPostNumber, 5);
    });

    test('parses multiple accepted_answers entries', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          acceptedAnswers: [
            {'post_number': 7, 'username': 'second'},
            {'post_number': 5, 'username': 'first'},
          ],
          posts: [
            _post(id: 101, postNumber: 1),
            _post(id: 105, postNumber: 5, username: 'first'),
            _post(id: 107, postNumber: 7, username: 'second'),
          ],
        ),
      );

      expect(detail.hasAcceptedAnswer, isTrue);
      expect(detail.acceptedAnswerPostNumber, 5);
      expect(detail.acceptedAnswerPostNumbers, [5, 7]);
      expect(detail.acceptedAnswers.map((answer) => answer.username), [
        'first',
        'second',
      ]);
    });

    test('uses accepted_answers_post_info metadata', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          acceptedAnswersPostInfo: [
            {
              'post_number': 5,
              'username': 'answerer',
              'name': 'Answer User',
              'excerpt': '<p>accepted</p>',
            },
          ],
          posts: [
            _post(id: 101, postNumber: 1),
            _post(id: 105, postNumber: 5, username: 'fallback'),
          ],
        ),
      );

      expect(detail.acceptedAnswerPostNumbers, [5]);
      expect(detail.acceptedAnswers.single.username, 'answerer');
      expect(detail.acceptedAnswers.single.name, 'Answer User');
      expect(detail.acceptedAnswers.single.excerpt, '<p>accepted</p>');
    });

    test('maps topic-level accepted_answer post id to post number', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          acceptedAnswer: 105,
          posts: [_post(id: 101, postNumber: 1), _post(id: 105, postNumber: 5)],
        ),
      );

      expect(detail.hasAcceptedAnswer, isTrue);
      expect(detail.acceptedAnswerPostNumber, 5);
    });

    test('maps accepted_answer object id to post number', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          acceptedAnswer: {'id': 105},
          posts: [_post(id: 101, postNumber: 1), _post(id: 105, postNumber: 5)],
        ),
      );

      expect(detail.hasAcceptedAnswer, isTrue);
      expect(detail.acceptedAnswerPostNumber, 5);
    });

    test('falls back to the loaded post accepted_answer flag', () {
      final detail = TopicDetail.fromJson(
        _topicJson(
          hasAcceptedAnswer: true,
          posts: [
            _post(id: 101, postNumber: 1),
            _post(id: 103, postNumber: 3, acceptedAnswer: true),
          ],
        ),
      );

      expect(detail.hasAcceptedAnswer, isTrue);
      expect(detail.acceptedAnswerPostNumber, 3);
    });
  });
}

Map<String, dynamic> _topicJson({
  Object? acceptedAnswer,
  List<Object?>? acceptedAnswers,
  List<Object?>? acceptedAnswersPostInfo,
  bool hasAcceptedAnswer = false,
  required List<Map<String, dynamic>> posts,
}) {
  final json = <String, dynamic>{
    'id': 42,
    'title': 'Solved topic',
    'slug': 'solved-topic',
    'posts_count': posts.length,
    'category_id': 1,
    'post_stream': {
      'posts': posts,
      'stream': posts.map((post) => post['id'] as int).toList(),
    },
    'has_accepted_answer': hasAcceptedAnswer,
  };
  if (acceptedAnswer != null) {
    json['accepted_answer'] = acceptedAnswer;
  }
  if (acceptedAnswers != null) {
    json['accepted_answers'] = acceptedAnswers;
  }
  if (acceptedAnswersPostInfo != null) {
    json['accepted_answers_post_info'] = acceptedAnswersPostInfo;
  }
  return json;
}

Map<String, dynamic> _post({
  required int id,
  required int postNumber,
  String username = 'tester',
  bool acceptedAnswer = false,
}) {
  return {
    'id': id,
    'post_number': postNumber,
    'username': username,
    'cooked': '<p>answer</p>',
    'accepted_answer': acceptedAnswer,
  };
}
