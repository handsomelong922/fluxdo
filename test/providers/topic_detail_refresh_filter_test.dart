import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/topic_detail_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

Post _post(int id, {String? cooked}) => Post(
  id: id, username: 'u', avatarTemplate: '', cooked: cooked ?? '正文$id',
  postNumber: id, postType: 1, updatedAt: DateTime.utc(2026),
  createdAt: DateTime.utc(2026), likeCount: 0, replyCount: 0,
);

TopicDetail _detail(List<Post> posts, {PostStreamGaps? gaps}) => TopicDetail(
  id: 7, title: '', slug: '', postsCount: posts.length,
  postStream: PostStream(posts: posts, stream: posts.map((p) => p.id).toList(), gaps: gaps),
  categoryId: 1, closed: false, archived: false,
);

class _Service implements DiscourseService {
  final filters = <bool>[];
  final positions = <int?>[];
  TopicDetail detail = _detail([_post(1), _post(2)]);
  bool emulateTopFilter = true;
  bool delayDetails = false;
  final detailRequests = <Completer<TopicDetail>>[];
  int firstPostRequests = 0;
  final gapRequests = <Completer<PostStream>>[];
  final postRequests = <Completer<Post>>[];

  @override
  Future<TopicDetail> getTopicDetail(int id, {
    int? postNumber, bool trackVisit = false, String? filter,
    String? usernameFilters, bool filterTopLevelReplies = false,
  }) async {
    filters.add(filterTopLevelReplies);
    positions.add(postNumber);
    if (delayDetails) {
      final request = Completer<TopicDetail>();
      detailRequests.add(request);
      return request.future;
    }
    return filterTopLevelReplies && emulateTopFilter ? _detail([_post(2)]) : detail;
  }
  @override
  Future<Post> getPostByNumber(int topicId, int postNumber) async {
    firstPostRequests++;
    return _post(1);
  }
  @override
  Future<PostStream> getPosts(int topicId, List<int> postIds, {bool includeSuggested = false}) {
    final request = Completer<PostStream>();
    gapRequests.add(request);
    return request.future;
  }
  @override
  Future<Post> getPost(int id) {
    final request = Completer<Post>();
    postRequests.add(request);
    return request.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Service service;
  late ProviderContainer container;
  final provider = topicDetailProvider(const TopicDetailParams(7));
  setUp(() {
    service = _Service();
    container = ProviderContainer(overrides: [
      discourseServiceProvider.overrideWithValue(service),
    ]);
    container.listen(provider, (_, _) {});
  });
  tearDown(() => container.dispose());

  test('顶层过滤刷新保留主帖和过滤参数，不额外请求已有主帖', () async {
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    await notifier.showTopLevelReplies();
    await notifier.refreshWithPostNumber(42);
    expect(service.filters, [false, true, true]);
    expect(service.positions.last, isNull);
    expect(notifier.isTopLevelMode, isTrue);
    expect(container.read(provider).requireValue.postStream.posts.map((p) => p.id), [1, 2]);
    expect(container.read(provider).requireValue.postStream.stream, [1, 2]);
    expect(service.firstPostRequests, 0);
  });

  test('顶层刷新缺少主帖时补取一次', () async {
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    await notifier.showTopLevelReplies();
    notifier.removePost(1);
    await notifier.refreshWithPostNumber(42);
    expect(container.read(provider).requireValue.postStream.stream, [1, 2]);
    expect(service.firstPostRequests, 1);
  });

  for (final before in [true, false]) {
    for (final empty in [true, false]) {
      test('重载同锚点后丢弃旧 gap：before=$before，empty=$empty', () async {
        service.detail = _detail([_post(2)], gaps: PostStreamGaps(
          before: before ? {2: [1]} : {}, after: before ? {} : {2: [3]},
        ));
        await container.read(provider.future);
        final notifier = container.read(provider.notifier);
        final pending = before ? notifier.fillGapBefore(2) : notifier.fillGapAfter(2);
        service.detail = _detail([_post(2)], gaps: PostStreamGaps(
          before: before ? {2: [99]} : {}, after: before ? {} : {2: [99]},
        ));
        await notifier.refreshWithPostNumber(2);
        service.gapRequests.single.complete(PostStream(
          posts: empty ? [] : [_post(before ? 1 : 3)], stream: [],
        ));
        await pending;
        final stream = container.read(provider).requireValue.postStream;
        expect(stream.stream, [2]);
        expect(stream.posts.map((p) => p.id), [2]);
        expect((before ? stream.gaps!.before : stream.gaps!.after)[2], [99]);
      });
    }
  }

  test('同代前后 gap 可并行完成且目录保持顺序', () async {
    service.detail = _detail([_post(2)], gaps: PostStreamGaps(before: {2: [1]}, after: {2: [3]}));
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final before = notifier.fillGapBefore(2);
    final after = notifier.fillGapAfter(2);
    service.gapRequests[1].complete(PostStream(posts: [_post(3)], stream: [3]));
    await after;
    service.gapRequests[0].complete(PostStream(posts: [_post(1)], stream: [1]));
    await before;
    expect(container.read(provider).requireValue.postStream.stream, [1, 2, 3]);
    expect(notifier.hasMoreAfter, isFalse);
    expect(notifier.hasMoreBefore, isFalse);
  });

  test('重载后新单帖请求不被旧队列阻塞，旧响应不能覆盖新正文', () async {
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final old = notifier.refreshPost(2);
    await notifier.refreshWithPostNumber(2);
    final fresh = notifier.refreshPost(2);
    expect(service.postRequests, hasLength(2));
    service.postRequests[1].complete(_post(2, cooked: '新正文'));
    await fresh;
    service.postRequests[0].complete(_post(2, cooked: '过期正文'));
    await old;
    expect(container.read(provider).requireValue.postStream.posts.last.cooked, '新正文');
  });
  for (final route in ['过滤', '定位', '取消过滤定位']) {
    test('$route 重载 A→B 时旧 A 不覆盖 B', () async {
      await container.read(provider.future);
      final notifier = container.read(provider.notifier);
      service.delayDetails = true;
      final Future<void> old;
      if (route == '过滤') {
        old = notifier.showTopReplies();
      } else if (route == '定位') {
        old = notifier.reloadWithPostNumber(2);
      } else {
        old = notifier.cancelFilterAndReloadWithPostNumber(2);
      }
      // 两个定位入口会先让出一个事件循环，不使用计时器超时兜底。
      await Future<void>.delayed(Duration.zero);
      final fresh = notifier.showAuthorOnly('fresh');
      expect(service.detailRequests, hasLength(2));
      service.detailRequests[1].complete(_detail([_post(20)]));
      await fresh;
      service.detailRequests[0].complete(_detail([_post(10)]));
      await old;
      expect(container.read(provider).requireValue.postStream.stream, [20]);
      expect(notifier.hasMoreAfter, isFalse);
      expect(notifier.hasMoreBefore, isFalse);
    });
  }

  test('取消过滤并定位也隔离旧 gap', () async {
    service.detail = _detail([_post(2)], gaps: PostStreamGaps(before: {2: [1]}, after: {}));
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    final old = notifier.fillGapBefore(2);
    service.detail = _detail([_post(2)]);
    await notifier.cancelFilterAndReloadWithPostNumber(2);
    service.gapRequests.single.complete(PostStream(posts: [_post(1)], stream: [1]));
    await old;
    expect(container.read(provider).requireValue.postStream.stream, [2]);
  });

}
