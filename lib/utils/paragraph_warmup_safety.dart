import 'package:flutter/widgets.dart';
import 'package:fluxdo_render/fluxdo_render.dart';

import 'render_warmup_slice.dart';

/// 缓存不区分回调，故只预热不会捕获交互闭包或自定义 builder 的节点。
/// 不认识的新节点保守跳过，交由真实挂载路径创建。
bool canWarmInlineWithoutCallbacks(InlineNode node) => switch (node) {
  TextRun() || LineBreakRun() => true,
  EmRun(:final children) ||
  StrongRun(:final children) => children.every(canWarmInlineWithoutCallbacks),
  _ => false,
};

/// 解析产物节点列表不可变；用弱引用缓存准备结果，不延长 AST 的存活期。
/// 内容/图片尺寸改变后新 AST 身份自然建立新计划。
final _plans = Expando<_WarmupPlan>();

class _WarmupPlan {
  _WarmupPlan(List<BlockNode> source) {
    for (var i = 0; i < source.length; i++) {
      if (source[i] case ParagraphNode(:final inlines)
          when inlines.every(canWarmInlineWithoutCallbacks)) {
        indices.add(i);
        nodes.add(source[i]);
      }
    }
    totalImages = countImageRuns(source);
  }

  final indices = <int>[];
  final nodes = <BlockNode>[];
  late final int totalImages;

  int startAt(int cursor) {
    var low = 0;
    var high = indices.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (indices[middle] < cursor) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }
}

/// 图片数来自完整 FluxdoRender 块，筛选保留原 ParagraphNode/inlines 身份。
/// 返回原节点列表游标。准备工作每块只做一次，预算耗尽且没有进展时
/// 跳过一个候选，避免无限重扫；实际挂载仍会正常排版该段落。
/// 准备扫描及单个 flatten 不可抢占，budgetMicros 是软预算而非硬时限。
int warmSafeParagraphs({
  required List<BlockNode> nodes,
  required WarmupContext ctx,
  required BuildContext context,
  int startIndex = 0,
  int budgetMicros = 4000,
}) {
  final watch = Stopwatch()..start();
  final plan = _plans[nodes] ??= _WarmupPlan(nodes);
  final safeStart = plan.startAt(startIndex);
  if (safeStart == plan.nodes.length) return -1;
  final remaining = budgetMicros - watch.elapsedMicroseconds;
  final next = remaining <= 0
      ? safeStart
      : ParagraphWarmup.warmParagraphs(
          nodes: plan.nodes,
          ctx: ctx,
          context: context,
          totalImagesInPost: plan.totalImages,
          startIndex: safeStart,
          budgetMicros: remaining,
        );
  return advanceRenderWarmupCursor(
    sourceIndices: plan.indices,
    startIndex: safeStart,
    nextIndex: next,
  );
}
