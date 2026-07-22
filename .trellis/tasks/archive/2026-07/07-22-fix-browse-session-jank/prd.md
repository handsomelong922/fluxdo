# 修复连续浏览后的持续卡顿

## Goal

修复首页已加载大量话题后，回顶或恢复动作沿变高懒列表物化全部中间卡片所造成的冻结帧，让前面浏览和分页积累不再拖慢后续操作。

## Confirmed Facts

- 2026-07-22 追踪中最坏首页帧为 332ms/build 319ms，同帧归因至少 259 张话题卡片。
- 该帧前列表约 37,314px，随后出现从约 4,148px 到 0 的大跨度更新；当前代码对任意距离直接 `animateTo(0)`。
- 首页列表已明确关闭 automatic keep-alive，并将移动端 cache extent 限制为 120px；正常懒构建有效，问题集中在长距离动画穿越。
- 图片查看器退出后缓存回落，帖子详情 provider/caches 已有移动端保留和内容预算，MessageBus 请求为 silent 长轮询。

## Requirements

- 长距离回顶先无动画跳到距离顶部固定 viewport 数的 staging offset，再执行现有 320ms 顶部动画。
- staging 计算必须 clamp 到合法滚动范围；短距离保持现有单段动画。
- 顶栏 tab 重点、底栏首页动作和刷新回顶等现有入口复用同一策略。
- 不裁剪用户已加载的话题、不改变 PageStorageKey、加载更多、首页摘要、返回位置或帖子路由语义。
- 保留现有帖子页销毁清理，不增加无证据的全局缓存清空。

## Acceptance Criteria

- [x] 当前 offset 超过阈值时返回有界 staging offset，offset 已较近或滚动范围无效时不 staging。
- [x] 远距离回顶动画最多跨固定数量 viewport，不再随已加载话题数增长。
- [x] 短距离回顶仍为 320ms easeOutCubic 动画，首页交互语义不变。
- [x] 首页滚动相关定向测试、定向 analyze 和 diff check 通过；全量 analyze/test 在父任务集成门禁执行。

## Out of Scope

- 删除已加载话题或修改分页 API。
- 改写帖子详情渲染、图片缓存、MessageBus 和导航返回栈。

## Open Questions

- 无。
