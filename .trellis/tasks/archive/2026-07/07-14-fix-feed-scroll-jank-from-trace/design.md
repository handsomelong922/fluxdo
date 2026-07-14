# 技术设计

## 证据与边界

本次只处理日志直接指向的树形评论热路径。普通平铺列表已有有界渐进物化；树形列表的问题来自根节点 Sliver 内部仍用递归 Column 构建整棵已展开子树，使离屏后代绕过 Sliver 回收。

## 视口驱动的子树物化

`NestedPostList` 继续使用现有 `AutoScrollController.tagMap` 计算可见楼层，不引入逐卡 `VisibilityDetector`。新增共享 `ValueNotifier<Set<int>>` 保存当前实际可见的 post number，并传给所有 `NestedPostCard`。

自动展开节点区分“逻辑上 expanded”和“子节点已经 materialized”。节点仍保留现有展开状态，但只有自身进入可见集合且滚动暂停关闭时，才在 post-frame 中物化直接子节点。直接子节点建立后，各子节点按相同规则在自己进入视口时再物化下一层，因此不会在同一帧递归展开整棵树。

用户手动展开绕过自动门禁，立即物化子节点；已经物化的子节点不会因为离开视口而卸载，避免高度回缩和滚动跳动。网络自动加载同样增加可见门禁，继续复用现有 FIFO `AutoReplyPrefetchQueue` 和滚动暂停信号。

`NestedRepliesState` 保存 materialized 状态，使根节点被 Sliver 回收后再进入时不会重复渐进或丢失用户状态。

## 重绘边界

移除包住整个递归 card 的最外层 `RepaintBoundary`，改为只包住当前帖子主体行。树线与子节点布局不变，但父节点不再把全部后代纳入同一个巨大重绘边界。

## 诊断合同

自动物化发生时通过现有 `PerformanceDiagnosticsService.noteFrameEvent` 写入 `nested:childrenMaterialized`，字段包含 `postNumber`、`depth`、`childCount` 和 `source`。关闭诊断时现有入口立即返回，不增加 JSON 写入。

## 兼容与回滚

- 数据 provider、API、排序和评论顺序不变。
- 首页详细展示和 preview seed 不经过该路径。
- 视口门禁与重绘边界分开提交，可独立回滚。
- 如果新 trace 仍显示单个可见动图导致 raster 卡顿，再单独设计仅针对动画 provider 的 listener 可见性门禁，不在本次无证据扩大范围。
