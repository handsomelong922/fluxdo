# 二次分析并修复剩余卡顿

## Goal

消除从深层首页位置触发回顶时的大规模卡片物化，让性能成本不随会话中已加载话题数增长。

## Requirements

- 以新日志的 638ms/351ms build 峰值为回归目标。
- 远距离回顶不得调用会穿越完整变高 extent 的普通 `jumpTo/animateTo`。
- 近距离回顶保留 320ms 的短动画体验。
- 首页三个回顶入口统一，不清空话题列表、缓存或滚动 PageStorage。

## Acceptance Criteria

- [ ] 40000px 以上回顶使用有界定位分支，布局工作量与列表长度无关。
- [ ] 最终位置为 `minScrollExtent`，近距离路径仍有动画。
- [ ] 不额外触发 load-more，不破坏刷新/高亮清理。
- [ ] 定向测试和 analyze 通过。

## Out Of Scope

- 本子任务不处理详情页固有的单帖图片/光栅峰值。
- 不把 MessageBus 长轮询当作 UI 卡顿修复对象。
