import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/models/nested_topic.dart';
import 'package:fluxdo/providers/nested_topic_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late HttpClientAdapter originalAdapter;
  late List<Interceptor> originalInterceptors;
  late _NestedRootsAdapter adapter;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final dio = DiscourseService().dio;
    originalAdapter = dio.httpClientAdapter;
    originalInterceptors = List<Interceptor>.from(dio.interceptors);
    dio.interceptors.clear();
    adapter = _NestedRootsAdapter();
    dio.httpClientAdapter = adapter;
  });

  tearDown(() {
    final dio = DiscourseService().dio;
    dio.httpClientAdapter = originalAdapter;
    dio.interceptors
      ..clear()
      ..addAll(originalInterceptors);
  });

  test('ignores stale load-more response after sorting changes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final params = NestedTopicParams(topicId: 42);
    final subscription = container.listen(
      nestedTopicProvider(params),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final initialFuture = container.read(nestedTopicProvider(params).future);
    adapter.complete('top', 0, _roots(sort: 'top', page: 0, posts: [2]));
    await initialFuture;

    final notifier = container.read(nestedTopicProvider(params).notifier);
    final loadMoreFuture = notifier.loadMoreRoots();
    await _flushMicrotasks();

    final sortFuture = notifier.changeSort('new');
    await _flushMicrotasks();

    adapter.complete('new', 0, _roots(sort: 'new', page: 0, posts: [20, 21]));
    await sortFuture;

    var state = container.read(nestedTopicProvider(params)).requireValue;
    expect(state.sort, 'new');
    expect(_postNumbers(state.roots), [20, 21]);
    expect(state.isLoadingMore, isFalse);
    expect(state.isRefreshingSort, isFalse);

    adapter.complete('top', 1, _roots(sort: 'top', page: 1, posts: [3]));
    await loadMoreFuture;

    state = container.read(nestedTopicProvider(params)).requireValue;
    expect(state.sort, 'new');
    expect(_postNumbers(state.roots), [20, 21]);
    expect(state.currentPage, 0);
    expect(state.isLoadingMore, isFalse);
  });

  test('ignores stale sort response when user switches again', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final params = NestedTopicParams(topicId: 42);
    final subscription = container.listen(
      nestedTopicProvider(params),
      (_, _) {},
      fireImmediately: true,
    );
    addTearDown(subscription.close);

    final initialFuture = container.read(nestedTopicProvider(params).future);
    adapter.complete('top', 0, _roots(sort: 'top', page: 0, posts: [2]));
    await initialFuture;

    final notifier = container.read(nestedTopicProvider(params).notifier);
    final newSortFuture = notifier.changeSort('new');
    await _flushMicrotasks();
    final oldSortFuture = notifier.changeSort('old');
    await _flushMicrotasks();

    adapter.complete('old', 0, _roots(sort: 'old', page: 0, posts: [10, 11]));
    await oldSortFuture;

    var state = container.read(nestedTopicProvider(params)).requireValue;
    expect(state.sort, 'old');
    expect(_postNumbers(state.roots), [10, 11]);

    adapter.complete('new', 0, _roots(sort: 'new', page: 0, posts: [20, 21]));
    await newSortFuture;

    state = container.read(nestedTopicProvider(params)).requireValue;
    expect(state.sort, 'old');
    expect(_postNumbers(state.roots), [10, 11]);
    expect(state.isRefreshingSort, isFalse);
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

List<int> _postNumbers(List<NestedNode> roots) {
  return roots.map((node) => node.post.postNumber).toList(growable: false);
}

Map<String, dynamic> _roots({
  required String sort,
  required int page,
  required List<int> posts,
  bool hasMore = true,
}) {
  return {
    'topic': {'title': 'Topic'},
    'op_post': _post(1),
    'sort': sort,
    'roots': posts.map(_post).toList(growable: false),
    'has_more_roots': hasMore,
    'page': page,
  };
}

Map<String, dynamic> _post(int postNumber) {
  return {
    'id': 1000 + postNumber,
    'topic_id': 42,
    'username': 'user$postNumber',
    'avatar_template': '',
    'cooked': '<p>post $postNumber</p>',
    'post_number': postNumber,
    'post_type': 1,
    'updated_at': '2026-01-01T00:00:00.000Z',
    'created_at': '2026-01-01T00:00:00.000Z',
    'like_count': 0,
    'reply_count': 0,
  };
}

class _NestedRootsAdapter implements HttpClientAdapter {
  final Map<String, Completer<Map<String, dynamic>>> _responses = {};

  void complete(String sort, int page, Map<String, dynamic> body) {
    final completer = _responses.putIfAbsent(
      _key(sort, page),
      Completer<Map<String, dynamic>>.new,
    );
    completer.complete(body);
  }

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final sort = options.queryParameters['sort']?.toString() ?? 'top';
    final page = int.tryParse(options.queryParameters['page'].toString()) ?? 0;
    final completer = _responses.putIfAbsent(
      _key(sort, page),
      Completer<Map<String, dynamic>>.new,
    );
    final body = await completer.future;
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

  String _key(String sort, int page) => '$sort:$page';
}
