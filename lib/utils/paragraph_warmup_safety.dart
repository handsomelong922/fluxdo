import 'package:flutter/widgets.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

/// 缓存不区分回调，故只预热不会捕获交互闭包或自定义 builder 的节点。
/// 不认识的新节点保守跳过，交由真实挂载路径创建。
bool canWarmInlineWithoutCallbacks(InlineNode node) => switch (node) {
  TextRun() || LineBreakRun() => true,
  EmRun(:final children) ||
  StrongRun(:final children) => children.every(canWarmInlineWithoutCallbacks),
  _ => false,
};

/// 图片数必须来自整个 FluxdoRender 块，不能取筛选后的段落或整篇长帖。
/// 筛选保留原 ParagraphNode/inlines 身份，返回值仍是原节点列表的游标。
int warmSafeParagraphs({
  required List<BlockNode> nodes,
  required WarmupContext ctx,
  required BuildContext context,
  int startIndex = 0,
  int budgetMicros = 4000,
}) {
  final watch = Stopwatch()..start();
  final safe = [
    for (var i = startIndex; i < nodes.length; i++)
      if (nodes[i] case ParagraphNode(:final inlines)
          when inlines.every(canWarmInlineWithoutCallbacks))
        (index: i, node: nodes[i]),
  ];
  if (safe.isEmpty) return -1;
  final totalImages = countImageRuns(nodes);
  final remaining = budgetMicros - watch.elapsedMicroseconds;
  if (remaining <= 0) return safe.first.index;
  final next = ParagraphWarmup.warmParagraphs(
    nodes: [for (final entry in safe) entry.node],
    ctx: ctx,
    context: context,
    totalImagesInPost: totalImages,
    budgetMicros: remaining,
  );
  return next == -1 ? -1 : safe[next].index;
}
