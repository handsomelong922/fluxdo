/// 将实际取到的 gap ID 插回锚点原位，保留完整目录和已有 ID 的次序。
/// 锚点已被重载移除时返回 null，由调用方丢弃过期响应。
List<int>? mergeTopicGapStream({
  required List<int> stream,
  required int anchorId,
  required bool before,
  required Iterable<int> gapIds,
  required Iterable<int> fetchedIds,
}) {
  final index = stream.indexOf(anchorId);
  if (index < 0) return null;
  final fetched = fetchedIds.toSet();
  final seen = stream.toSet();
  final additions = gapIds.where((id) => fetched.contains(id) && seen.add(id));
  return [...stream]..insertAll(before ? index : index + 1, additions);
}
