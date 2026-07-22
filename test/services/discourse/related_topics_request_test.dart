import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

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
    },
  );
}

class _RelatedTopicsAdapter implements HttpClientAdapter {
  String? path;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    path = options.path;
    return ResponseBody.fromString(
      jsonEncode({
        'related_topics': [
          {
            'id': 7,
            'title': 'Related',
            'slug': 'related',
            'posts_count': 1,
            'reply_count': 0,
            'views': 0,
            'like_count': 0,
            'category_id': 1,
            'created_at': '2026-07-01T00:00:00.000Z',
          },
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
}
