# 手工移植 7月7日至10日上游 P0 滚动性能优化

## Goal

在不改变当前分支阅读功能和加载语义的前提下，手工移植上游
`Lingyan000/fluxdo@dev` 2026-07-07 至 2026-07-10 中收益最高、可在当前
架构内安全落地的滚动性能优化，重点降低帖子详情持续滚动掉帧、动态表情
引起的整帖重绘，以及 MessageBus 积压恢复造成的主线程卡顿。

## Confirmed Facts

- 当前分支没有上游的新 `packages/fluxdo_render` 渲染器，帖子正文仍使用
  `discourse_html_content` legacy 渲染链，不能直接 cherry-pick renderer 提交。
- 当前分支已有独有的“首页详细展示”功能：话题卡片可展示主帖摘要，进入详情
  后立即复用已缓存的主帖 cooked HTML，再渐进加载其他楼层。
- 该交接链由 `initialTopicPreview`、`_initialPreviewDetail`、
  `mergeTopicDetailWithInitialPreview` 和 preview seed cache 共同实现。
- 当前详情页仍在顶层 watch 完整 `topicDetailProvider`，翻页和单帖状态更新会
  重建页面骨架；但当前分支曾回滚过一次更早的 rebuild 优化，因此必须基于
  当前页面结构重新划定边界，不能恢复旧提交。
- 当前 MessageBus 帖子更新逐条写入 provider 累积列表，详情页逐条消费；大 JSON
  仍在主 isolate 同步 `jsonDecode`。

## Requirements

- 仅手工对照并适配以下 P0 来源，不整体 cherry-pick：
  - `a0627a35`：完整 detail watch 下沉，减少页面骨架重建。
  - `eab5e959`：帖子正文 emoji 无条件使用独立 `RepaintBoundary`。
  - `48dabc53`：MessageBus 帖子更新微任务攒批、去重与积压坍缩。
  - `90cd49d6` 中可独立证明安全的部分：大包 isolate JSON 解析、typing/presence
    200ms 防抖、进度浮层重绘隔离、`AutoScrollTag` 直通 builder。
- rebuild 边界优化必须继续对 provider detail 与首页 preview detail 做合并；无论
  网络 detail 是否已经返回，只要 preview seed 可用，主帖内容都必须立即展示。
- 不改变首页详细展示开关、摘要请求、preview cache、进入详情的参数传递、首帖
  cooked 合并、评论分页、`loadMore`/`loadPrevious`、跳楼、树形评论或搜索逻辑。
- MessageBus batching 必须保持消息顺序语义：
  - 普通“同帖 + 同类型”更新只保留批内最后状态。
  - boost 增删是增量事件，按 boost id 保留，不能误合并。
  - `created` 仍即时处理；滚动期间会改变楼层高度的更新仍延迟到滚停。
  - 大规模积压只允许坍缩为一次带锚点的整流刷新，不能清空当前页面或跳回顶部。
- 大 JSON isolate 解析只对超过阈值的 chunk 生效，小消息保留低开销同步路径；
  chunk 必须串行 await，不能打乱 MessageBus 到达顺序。
- emoji 重绘隔离需覆盖当前 legacy 正文中的普通 emoji、mention 状态 emoji 和聊天
  transcript 反应 emoji，不改变尺寸、选择文本、点击和错误占位行为。
- 不移植 `90cd49d6` 中风险较高且会改变展示时序的图片首绘闸门、双侧分页渐进
  materialization、CF WebView 滚动挂起或整套全局滚动信号；这些留待独立任务。
- 每一类独立优化分别提交，本次不得 squash；只暂存本任务相关 tracked hunk，
  不提交现有未跟踪 Trellis、密钥或用户文件。

## Acceptance Criteria

- [x] detail 更新不再让 `LazyLoadScope`、`PopScope`、AI `PageView` 等页面骨架随
      每次翻页或单帖状态更新整体重建。
- [x] preview detail 可用且网络 detail 尚未返回时，仍立即显示主帖正文；网络
      detail 返回后继续保留 preview 主帖 cooked，并渐进展示其他回复。
- [x] 普通布局、AI 滑动入口、嵌入式主从布局、树形视图和搜索模式仍能获得最新
      detail，不出现旧标题、旧操作状态或 null detail 卡死。
- [x] legacy 正文所有 emoji 图片都位于独立 `RepaintBoundary` 内，选择和布局
      行为不变。
- [x] TopicChannel 帖子更新按微任务批次发布，详情页按 generation 一次消费；
      正常实时消息不丢失，boost 增量不被错误去重。
- [x] 超过阈值的 MessageBus JSON chunk 使用 isolate 解析且顺序消费，小 chunk
      继续走同步快速路径。
- [x] typing/presence 连续消息在 200ms 窗口内合并，dispose 后无延迟回调写状态。
- [x] 进度浮层与帖子列表 `AutoScrollTag` 的低风险包装优化通过现有 widget 测试。
- [x] `topic_detail_page_preview_test.dart`、相关帖子详情/overlay 测试、MessageBus
      定向测试与 changed-file analyze 通过；如全量 analyze 有既有问题需明确区分。
- [x] 创建多个本地提交，每个提交只包含一个可独立回滚的优化类别。

## Out of Scope

- 合并上游 `dev`，或引入 `packages/fluxdo_render`/富文本编辑器迁移。
- 改写首页详细展示、摘要缓存或主帖即时复用的产品逻辑。
- 图片首绘逐帧闸门、AVIF 全局滚动冻结、CF WebView pause/resume、分页双侧渐进
  物化和滚动锚定算法。
- 与滚动性能无关的编辑器、发布、登录、Notion、AI 功能变更。
