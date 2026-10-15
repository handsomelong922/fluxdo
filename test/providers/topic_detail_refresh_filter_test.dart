import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluxdo/models/topic.dart';
import 'package:fluxdo/providers/core_providers.dart';
import 'package:fluxdo/providers/topic_detail_provider.dart';
import 'package:fluxdo/services/discourse/discourse_service.dart';

class _Service implements DiscourseService {
  final filters = <bool>[];
  final positions = <int?>[];
  @override
  Future<TopicDetail> getTopicDetail(int id, {
    int? postNumber, bool trackVisit = false, String? filter,
    String? usernameFilters, bool filterTopLevelReplies = false,
  }) async {
    filters.add(filterTopLevelReplies);
    positions.add(postNumber);
    return TopicDetail(id: id, title: '', slug: '', postsCount: 0,
      postStream: PostStream(posts: [], stream: []), categoryId: 1,
      closed: false, archived: false);
  }
  @override
  Future<Post> getPostByNumber(int topicId, int postNumber) =>
      Future.error(StateError('此测试无主帖'));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('顶层过滤后的刷新保持过滤且不携带定位楼层', () async {
    final service = _Service();
    final container = ProviderContainer(overrides: [
      discourseServiceProvider.overrideWithValue(service),
    ]);
    addTearDown(container.dispose);
    final provider = topicDetailProvider(const TopicDetailParams(7));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final notifier = container.read(provider.notifier);
    await notifier.showTopLevelReplies();
    await notifier.refreshWithPostNumber(42);
    expect(service.filters, [false, true, true]);
    expect(service.positions.last, isNull);
    expect(notifier.isTopLevelMode, isTrue);
  });
}
