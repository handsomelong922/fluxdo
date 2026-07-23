import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/models/topic.dart';
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

  test(
    'loads related topics after the initial body without blocking it',
    () async {
      final container = await _container(delay: Duration.zero);
      addTearDown(container.dispose);
      const params = TopicDetailParams(42, instanceId: 'initial-related');
      final subscription = container.listen(
        topicDetailProvider(params),
        (_, _) {},
        fireImmediately: true,
      );
      addTearDown(subscription.close);

      final initial = await container.read(topicDetailProvider(params).future);

      expect(initial.postStream.posts.single.cooked, '<p>post 1</p>');
      expect(initial.relatedTopics, isNull);
      expect(initial.highestPostNumber, 9);

      await adapter.relatedRequestStarted.future.timeout(
        const Duration(seconds: 1),
      );
      expect(adapter.paths, contains('/t/42/9.json'));
      expect(
        container.read(topicDetailProvider(params)).requireValue.relatedTopics,
        isNull,
      );

      adapter.releaseRelatedResponse.complete();
      await _waitUntil(
        () =>
            container
                .read(topicDetailProvider(params))
                .value
                ?.relatedTopics
                ?.isNotEmpty ==
            true,
      );

      final loaded = container.read(topicDetailProvider(params)).requireValue;
      expect(loaded.relatedTopics?.map((topic) => topic.id), [7]);
    },
  );

  test(
    'does not request again when the initial response carries an empty list',
    () async {
      adapter.includeInitialRelatedTopics = true;
      final container = await _container(delay: Duration.zero);
      addTearDown(container.dispose);
      const params = TopicDetailParams(42, instanceId: 'explicit-empty');

      final detail = await container.read(topicDetailProvider(params).future);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(detail.relatedTopics, isEmpty);
      expect(adapter.paths.where((path) => path == '/t/42/9.json'), isEmpty);
    },
  );

  test(
    'keeps the initial body when the optional related request fails',
    () async {
      adapter.failRelatedRequest = true;
      final container = await _container(delay: Duration.zero);
      addTearDown(container.dispose);
      const params = TopicDetailParams(42, instanceId: 'related-failure');

      await container.read(topicDetailProvider(params).future);
      await adapter.relatedRequestStarted.future.timeout(
        const Duration(seconds: 1),
      );
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final detail = container.read(topicDetailProvider(params)).requireValue;
      expect(detail.postStream.posts.single.cooked, '<p>post 1</p>');
      expect(detail.relatedTopics, isNull);
    },
  );

  test('skips background related requests for private messages', () async {
    adapter.privateMessage = true;
    final container = await _container(delay: Duration.zero);
    addTearDown(container.dispose);
    const params = TopicDetailParams(42, instanceId: 'private-message');

    final detail = await container.read(topicDetailProvider(params).future);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(detail.isPrivateMessage, isTrue);
    expect(adapter.paths.where((path) => path == '/t/42/9.json'), isEmpty);
  });

  test('reaching the final page remains a fallback trigger', () async {
    adapter.highestPostNumber = 3;
    adapter.stream = const [101, 102, 103];
    final container = await _container(delay: const Duration(days: 1));
    addTearDown(container.dispose);
    const params = TopicDetailParams(42, instanceId: 'final-page-fallback');
    final subscription = container.listen(
      topicDetailProvider(params),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    await container.read(topicDetailProvider(params).future);
    adapter.releaseRelatedResponse.complete();
    await container.read(topicDetailProvider(params).notifier).loadMore();

    final loaded = container.read(topicDetailProvider(params)).requireValue;
    expect(loaded.postStream.posts.map((post) => post.postNumber), [1, 2, 3]);
    expect(loaded.relatedTopics?.map((topic) => topic.id), [7]);
    expect(adapter.paths, contains('/t/42/3.json'));
  });

  test('refresh data that omits the field preserves loaded related topics', () {
    final current = TopicDetail.fromJson(
      _topicDetailJson(relatedTopics: [_relatedTopicJson()]),
    );
    final refreshed = TopicDetail.fromJson(_topicDetailJson());

    final merged = preserveRelatedTopicsOnRefresh(
      current: current,
      incoming: refreshed,
    );

    expect(merged.relatedTopics?.map((topic) => topic.id), [7]);
  });
}

Future<ProviderContainer> _container({required Duration delay}) async {
  final preferences = await SharedPreferences.getInstance();
  return ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(preferences),
      topicRelatedTopicsLoadDelayProvider.overrideWithValue(delay),
    ],
  );
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('condition was not met');
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

Map<String, dynamic> _topicDetailJson({
  List<Map<String, dynamic>>? relatedTopics,
}) {
  final body = <String, dynamic>{
    'id': 42,
    'title': 'Topic',
    'slug': 'topic',
    'posts_count': 1,
    'highest_post_number': 9,
    'category_id': 1,
    'post_stream': {
      'posts': [_post(1)],
      'stream': [101],
    },
  };
  if (relatedTopics != null) body['related_topics'] = relatedTopics;
  return body;
}

class _TopicDetailAdapter implements HttpClientAdapter {
  final List<String> paths = [];
  final Completer<void> relatedRequestStarted = Completer<void>();
  final Completer<void> releaseRelatedResponse = Completer<void>();
  bool failRelatedRequest = false;
  bool includeInitialRelatedTopics = false;
  bool privateMessage = false;
  int highestPostNumber = 9;
  List<int> stream = const [101];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    paths.add(options.path);
    if (options.path == '/t/42/$highestPostNumber.json') {
      if (!relatedRequestStarted.isCompleted) relatedRequestStarted.complete();
      if (failRelatedRequest) return _jsonResponse(const {}, statusCode: 500);
      await releaseRelatedResponse.future;
      return _jsonResponse({
        'related_topics': [_relatedTopicJson()],
      });
    }
    if (options.path == '/t/42/posts.json') {
      return _jsonResponse({
        'post_stream': {
          'posts': [_post(2), _post(3)],
          'stream': stream,
        },
      });
    }

    final body = <String, dynamic>{
      'id': 42,
      'title': 'Topic',
      'slug': 'topic',
      'posts_count': stream.length,
      'highest_post_number': highestPostNumber,
      'category_id': 1,
      'archetype': privateMessage ? 'private_message' : 'regular',
      'post_stream': {
        'posts': [_post(1)],
        'stream': stream,
      },
    };
    if (includeInitialRelatedTopics) {
      body['related_topics'] = <Map<String, dynamic>>[];
    }
    return _jsonResponse(body);
  }

  ResponseBody _jsonResponse(
    Map<String, dynamic> body, {
    int statusCode = 200,
  }) {
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
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
    'created_at': '2026-06-01T00:00:00.000Z',
  };
}
