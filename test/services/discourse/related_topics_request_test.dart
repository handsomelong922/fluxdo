import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:fluxdo/services/network/discourse_dio.dart';
import 'package:fluxdo/services/network/interceptors/self_healing_interceptor.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpClientAdapter originalAdapter;
  late List<Interceptor> originalInterceptors;
  late _RelatedTopicsAdapter adapter;

  setUp(() {
    final dio = DiscourseService().dio;
    originalAdapter = dio.httpClientAdapter;
    originalInterceptors = List<Interceptor>.from(dio.interceptors);
    dio.interceptors.clear();
    adapter = _RelatedTopicsAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    final dio = DiscourseService().dio;
    dio.httpClientAdapter = originalAdapter;
    dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
  });

  test(
    'requests the final topic page and returns related_topics only',
    () async {
      final topics = await DiscourseService().getRelatedTopics(
        42,
        postNumber: 99,
      );

      expect(adapter.path, '/t/42/99.json');
      expect(topics.map((topic) => topic.id), [7]);
      expect(topics.single.title, 'Related');
      expect(adapter.extra['priority'], 'low');
      expect(adapter.extra['isSilent'], isTrue);
      expect(adapter.extra['showErrorToast'], isFalse);
      expect(adapter.extra[disableAutomaticRetryExtraKey], isTrue);
      expect(adapter.extra[SelfHealingInterceptor.selfHealedExtraKey], isTrue);
    },
  );

  test('first-post preview ignores malformed related topics', () async {
    final detail = await DiscourseService().getTopicFirstPostPreviewDetail(42);

    expect(adapter.path, '/t/42/1.json');
    expect(detail?.id, 42);
    expect(detail?.postStream.posts.single.cooked, '<p>topic</p>');
    expect(detail?.relatedTopics?.map((topic) => topic.id), [7]);
  });
}

class _RelatedTopicsAdapter implements HttpClientAdapter {
  String? path;
  Map<String, dynamic> extra = const {};

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    extra = Map<String, dynamic>.from(options.extra);
    if (options.path == '/t/42/1.json') {
      return _jsonResponse({
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
        'related_topics': [
          {'id': null, 'title': 'Broken'},
          _relatedTopicJson(),
        ],
      });
    }
    return ResponseBody.fromString(
      jsonEncode({
        'related_topics': [
          {'id': null, 'title': 'Broken'},
          _relatedTopicJson(),
        ],
        'suggested_topics': [
          {
            'id': 8,
            'title': 'Suggested',
            'slug': 'suggested',
            'posts_count': 1,
            'reply_count': 0,
            'views': 0,
            'like_count': 0,
            'category_id': 1,
          },
        ],
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  ResponseBody _jsonResponse(Map<String, dynamic> body) {
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

Map<String, dynamic> _relatedTopicJson() {
  return {
    'id': 7,
    'title': 'Related',
    'slug': 'related',
    'posts_count': 1,
    'reply_count': 0,
    'views': 0,
    'like_count': 0,
    'category_id': 1,
    'created_at': '2026-07-01T00:00:00.000Z',
  };
}
