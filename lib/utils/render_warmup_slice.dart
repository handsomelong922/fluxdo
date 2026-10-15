/// 用全局节点游标选出所属渲染块，保留原节点列表和块内图片计数边界。
/// 长帖每个 chunk 独立挂载，不能把整帖合并后计算渲染缓存条件。
({List<T> nodes, int startIndex, int offset, bool hasMore})?
selectRenderWarmupSlice<T>(List<List<T>> blocks, int cursor) {
  var offset = 0;
  for (var i = 0; i < blocks.length; i++) {
    final nodes = blocks[i];
    if (cursor < offset + nodes.length) {
      return (
        nodes: nodes,
        startIndex: cursor - offset,
        offset: offset,
        hasMore: blocks.skip(i + 1).any((block) => block.isNotEmpty),
      );
    }
    offset += nodes.length;
  }
  return null;
}

/// 把筛选列表的返回游标映射回原节点列表。
/// 预算不足而未处理任何段落时跳过一个候选，避免 idle 链原地重试。
/// 被跳过的段落仍由真实挂载正常渲染，不强行超预算预热。
int advanceRenderWarmupCursor({
  required List<int> sourceIndices,
  required int startIndex,
  required int nextIndex,
}) {
  if (nextIndex == -1) return -1;
  final next = nextIndex <= startIndex ? startIndex + 1 : nextIndex;
  return next >= sourceIndices.length ? -1 : sourceIndices[next];
}
