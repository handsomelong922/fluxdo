import 'models.dart';

/// 返回可安全坍缩的更新键；null 表示该事件必须逐条保留。
///
/// 普通状态事件按“帖子 + 类型”只保留最后状态。boost 是增量事件，但同一个
/// boost id 的重复广播仍可去重；缺少 id 时无法证明等价，因此逐条保留。
String? postUpdateDedupeKey(PostUpdate update) {
  switch (update.type) {
    case TopicMessageType.boostAdded:
      final boostId = update.boostData?['id'];
      return boostId == null
          ? null
          : '${update.postId}:${update.type.name}:$boostId';
    case TopicMessageType.boostRemoved:
      final boostId = update.boostId;
      return boostId == null
          ? null
          : '${update.postId}:${update.type.name}:$boostId';
    default:
      return '${update.postId}:${update.type.name}';
  }
}

/// 批内去重并保持首次出现位置；同键后续事件替换为最新 payload。
List<PostUpdate> dedupePostUpdateBatch(Iterable<PostUpdate> updates) {
  final result = <PostUpdate>[];
  final indexByKey = <String, int>{};
  for (final update in updates) {
    final key = postUpdateDedupeKey(update);
    if (key == null) {
      result.add(update);
      continue;
    }
    final existing = indexByKey[key];
    if (existing == null) {
      indexByKey[key] = result.length;
      result.add(update);
    } else {
      result[existing] = update;
    }
  }
  return List<PostUpdate>.unmodifiable(result);
}

/// 当前分支里会触发逐帖网络请求的更新类型。
bool postUpdateRequiresNetworkRefresh(PostUpdate update) {
  switch (update.type) {
    case TopicMessageType.revised:
    case TopicMessageType.rebaked:
    case TopicMessageType.acted:
    case TopicMessageType.policyChanged:
      return true;
    case TopicMessageType.liked:
    case TopicMessageType.unliked:
      return update.likesCount == null;
    default:
      return false;
  }
}

/// 一批事件中需要逐帖网络刷新的不同帖子数。
int networkRefreshPostCount(Iterable<PostUpdate> updates) {
  return {
    for (final update in updates)
      if (postUpdateRequiresNetworkRefresh(update)) update.postId,
  }.length;
}
