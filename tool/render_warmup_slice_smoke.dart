import '../lib/utils/render_warmup_slice.dart';

void runRenderWarmupSliceChecks() {
  void check(bool value, String label) {
    if (!value) throw StateError(label);
  }

  final first = [Object(), Object()];
  final second = [Object(), Object(), Object()];
  final blocks = [<Object>[], first, <Object>[], second, <Object>[]];
  final a = selectRenderWarmupSlice(blocks, 0)!;
  check(identical(a.nodes, first), '保留首块节点身份');
  check(a.offset == 0 && a.startIndex == 0 && a.hasMore, '首块游标');
  final b = selectRenderWarmupSlice(blocks, 1)!;
  check(identical(b.nodes, first) && b.startIndex == 1, '块内续跑');
  final c = selectRenderWarmupSlice(blocks, 2)!;
  check(identical(c.nodes, second), '跨块保持独立计数边界');
  check(c.offset == 2 && c.startIndex == 0 && !c.hasMore, '末块游标');
  check(selectRenderWarmupSlice(blocks, 5) == null, '完成');
  check(selectRenderWarmupSlice(<List<Object>>[], 0) == null, '空帖');
  check(selectRenderWarmupSlice([first], 0)!.hasMore == false, '短帖');
  final indices = [1, 3, 7];
  for (var i = 0; i < indices.length; i++) {
    final next = advanceRenderWarmupCursor(
      sourceIndices: indices,
      startIndex: i,
      nextIndex: i,
    );
    check(
      next == (i + 1 == indices.length ? -1 : indices[i + 1]),
      '连续零预算步骤必须前进或完成',
    );
  }
  check(
    advanceRenderWarmupCursor(
          sourceIndices: indices,
          startIndex: 0,
          nextIndex: 2,
        ) ==
        7,
    '已有进展映射回原游标',
  );
  check(
    advanceRenderWarmupCursor(
          sourceIndices: indices,
          startIndex: 0,
          nextIndex: -1,
        ) ==
        -1,
    '正常完成不重试',
  );
}

void main() {
  runRenderWarmupSliceChecks();
  print('PASS: 13 项预热块边界和游标检查');
}
