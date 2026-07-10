import 'package:flutter_test/flutter_test.dart';
import 'package:fluxdo/providers/message_bus/models.dart';
import 'package:fluxdo/providers/message_bus/post_update_batch.dart';

void main() {
  test('dedupePostUpdateBatch keeps the latest ordinary state', () {
    final first = _update(
      postId: 10,
      type: TopicMessageType.liked,
      likesCount: 1,
    );
    final latest = _update(
      postId: 10,
      type: TopicMessageType.liked,
      likesCount: 3,
      seconds: 1,
    );

    final result = dedupePostUpdateBatch([first, latest]);

    expect(result, hasLength(1));
    expect(result.single, same(latest));
  });

  test('dedupePostUpdateBatch preserves distinct boost increments', () {
    final boost1 = _update(
      postId: 10,
      type: TopicMessageType.boostAdded,
      boostData: const {'id': 101},
    );
    final boost2 = _update(
      postId: 10,
      type: TopicMessageType.boostAdded,
      boostData: const {'id': 102},
    );
    final boost1Latest = _update(
      postId: 10,
      type: TopicMessageType.boostAdded,
      boostData: const {'id': 101, 'cooked': 'latest'},
      seconds: 1,
    );
    final unknown1 = _update(postId: 10, type: TopicMessageType.boostRemoved);
    final unknown2 = _update(
      postId: 10,
      type: TopicMessageType.boostRemoved,
      seconds: 1,
    );

    final result = dedupePostUpdateBatch([
      boost1,
      boost2,
      boost1Latest,
      unknown1,
      unknown2,
    ]);

    expect(result, [
      same(boost1Latest),
      same(boost2),
      same(unknown1),
      same(unknown2),
    ]);
  });

  test('networkRefreshPostCount follows current notifier behavior', () {
    final result = networkRefreshPostCount([
      _update(postId: 1, type: TopicMessageType.revised),
      _update(postId: 1, type: TopicMessageType.acted),
      _update(postId: 2, type: TopicMessageType.liked),
      _update(postId: 3, type: TopicMessageType.liked, likesCount: 4),
      _update(postId: 4, type: TopicMessageType.deleted),
      _update(postId: 5, type: TopicMessageType.policyChanged),
    ]);

    expect(result, 3);
  });

  test('TopicChannelState copyWith retains and advances generation', () {
    const initial = TopicChannelState(postUpdatesGeneration: 4);
    final next = initial.copyWith(postUpdatesGeneration: 5);

    expect(initial.postUpdatesGeneration, 4);
    expect(next.postUpdatesGeneration, 5);
  });
}

PostUpdate _update({
  required int postId,
  required TopicMessageType type,
  int? likesCount,
  Map<String, dynamic>? boostData,
  int? boostId,
  int seconds = 0,
}) {
  return PostUpdate(
    postId: postId,
    type: type,
    updatedAt: DateTime(2026, 7, 10, 12, 0, seconds),
    likesCount: likesCount,
    boostData: boostData,
    boostId: boostId,
  );
}
