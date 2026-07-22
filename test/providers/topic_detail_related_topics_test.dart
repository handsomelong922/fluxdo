import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/theme_provider.dart';
import 'package:fluxdo/providers/topic_detail_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpClientAdapter originalAdapter;
  late List<Interceptor> originalInterceptors;
  late _TopicDetailAdapter adapter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dio = DiscourseService().dio;
    originalAdapter = dio.httpClientAdapter;
    originalInterceptors = List<Interceptor>.from(dio.interceptors);
    dio.interceptors.clear();
    adapter = _TopicDetailAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    final dio = DiscourseService().dio;
    dio.httpClientAdapter = originalAdapter;
    dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
  });

  test('loads related topics after reaching the final post page', () async {
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    const params = TopicDetailParams(42, instanceId: 'related-topics-test');
    final subscription = container.listen(
      topicDetailProvider(params),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final initial = await container.read(topicDetailProvider(params).future);
    expect(initial.relatedTopics, isNull);
    expect(initial.postStream.posts.map((post) => post.postNumber), [1]);

    await container.read(topicDetailProvider(params).notifier).loadMore();

    final loaded = container.read(topicDetailProvider(params)).requireValue;
    expect(loaded.postStream.posts.map((post) => post.postNumber), [1, 2, 3]);
    expect(loaded.relatedTopics?.map((topic) => topic.id), [7]);
    expect(
      adapter.paths,
      containsAllInOrder(['/t/42.json', '/t/42/posts.json', '/t/42/3.json']),
    );
  });

  test('keeps final posts when the related request fails', () async {
    adapter.failRelatedRequest = true;
    final preferences = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    const params = TopicDetailParams(
      42,
      instanceId: 'related-topics-failure-test',
    );
    final subscription = container.listen(
      topicDetailProvider(params),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(topicDetailProvider(params).future);
    await container.read(topicDetailProvider(params).notifier).loadMore();

    final loaded = container.read(topicDetailProvider(params)).requireValue;
    expect(loaded.postStream.posts.map((post) => post.postNumber), [1, 2, 3]);
    expect(loaded.relatedTopics, isNull);
    expect(adapter.paths, contains('/t/42/3.json'));
  });
}

Map<String, dynamic> _topicDetail() {
  return {
    'id': 42,
    'title': 'Topic',
    'slug': 'topic',
    'posts_count': 3,
    'category_id': 1,
    'post_stream': {
      'posts': [_post(1)],
      'stream': [101, 102, 103],
    },
  };
}

Map<String, dynamic> _post(int postNumber) {
  return {
    'id': 100 + postNumber,
    'topic_id': 42,
    'post_number': postNumber,
    'username': 'user$postNumber',
    'cooked': '<p>post $postNumber</p>',
    'created_at': '2026-07-01T00:00:00.000Z',
    'updated_at': '2026-07-01T00:00:00.000Z',
  };
}

class _TopicDetailAdapter implements HttpClientAdapter {
  final List<String> paths = [];
  bool failRelatedRequest = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (options.path == '/t/42/3.json' && failRelatedRequest) {
      return ResponseBody.fromString('{}', 500);
    }
    final Map<String, dynamic> body;
    switch (options.path) {
      case '/t/42.json':
        body = _topicDetail();
      case '/t/42/posts.json':
        body = {
          'post_stream': {
            'posts': [_post(2), _post(3)],
            'stream': [101, 102, 103],
          },
        };
      case '/t/42/3.json':
        body = {
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
              'created_at': '2026-06-01T00:00:00.000Z',
            },
          ],
        };
      default:
        body = const <String, dynamic>{};
    }
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
