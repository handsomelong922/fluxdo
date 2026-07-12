enum TopicPostGrowth { append, prepend }

enum TopicPostMaterializationSide { before, after }

class TopicPostMaterializationPlan {
  final TopicPostMaterializationSide side;
  final int initialCap;

  const TopicPostMaterializationPlan({
    required this.side,
    required this.initialCap,
  });
}

TopicPostGrowth? detectTopicPostGrowth({
  required List<int>? oldPostIds,
  required List<int> newPostIds,
}) {
  if (oldPostIds == null ||
      oldPostIds.isEmpty ||
      newPostIds.length <= oldPostIds.length) {
    return null;
  }

  if (_matchesAt(newPostIds, oldPostIds, 0)) {
    return TopicPostGrowth.append;
  }

  final prependOffset = newPostIds.length - oldPostIds.length;
  if (_matchesAt(newPostIds, oldPostIds, prependOffset)) {
    return TopicPostGrowth.prepend;
  }
  return null;
}

TopicPostMaterializationPlan? planTopicPostPagingMaterialization({
  required TopicPostGrowth? growth,
  required int oldSegmentCount,
  required int newSegmentCount,
  required int oldCenterScrollIndex,
  int step = 4,
}) {
  if (growth == null ||
      oldSegmentCount <= 0 ||
      oldCenterScrollIndex < 0 ||
      newSegmentCount <= oldSegmentCount ||
      newSegmentCount - oldSegmentCount < step * 2) {
    return null;
  }

  final safeCenter = oldCenterScrollIndex.clamp(0, oldSegmentCount);
  return switch (growth) {
    TopicPostGrowth.append => TopicPostMaterializationPlan(
      side: TopicPostMaterializationSide.after,
      initialCap: oldSegmentCount - safeCenter + step,
    ),
    TopicPostGrowth.prepend => TopicPostMaterializationPlan(
      side: TopicPostMaterializationSide.before,
      initialCap: safeCenter + step,
    ),
  };
}

int initialAfterMaterializationCap({
  required List<int> segmentPostIds,
  required int centerScrollIndex,
  int step = 4,
}) {
  if (segmentPostIds.isEmpty ||
      centerScrollIndex < 0 ||
      centerScrollIndex >= segmentPostIds.length) {
    return step;
  }

  final centerPostId = segmentPostIds[centerScrollIndex];
  var cursor = centerScrollIndex;
  while (cursor < segmentPostIds.length &&
      segmentPostIds[cursor] == centerPostId) {
    cursor++;
  }
  return cursor - centerScrollIndex + step;
}

int materializedSegmentCount({required int total, required int? cap}) {
  if (total <= 0) return 0;
  if (cap == null) return total;
  return cap.clamp(0, total);
}

bool shouldAdvanceTopicPostMaterialization({
  required bool isScrollActive,
  required bool hasPendingMaterialization,
}) {
  return !isScrollActive && hasPendingMaterialization;
}

bool didTopicPostCenterChange({
  required List<int> oldPostNumbers,
  required int oldCenterPostIndex,
  required List<int> newPostNumbers,
  required int newCenterPostIndex,
}) {
  final oldCenter = _valueAt(oldPostNumbers, oldCenterPostIndex);
  final newCenter = _valueAt(newPostNumbers, newCenterPostIndex);
  return oldCenter != null && newCenter != null && oldCenter != newCenter;
}

bool _matchesAt(List<int> source, List<int> expected, int offset) {
  if (offset < 0 || offset + expected.length > source.length) return false;
  for (int index = 0; index < expected.length; index++) {
    if (source[offset + index] != expected[index]) return false;
  }
  return true;
}

int? _valueAt(List<int> values, int index) {
  if (index < 0 || index >= values.length) return null;
  return values[index];
}
