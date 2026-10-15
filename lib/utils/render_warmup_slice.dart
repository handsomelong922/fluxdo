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
