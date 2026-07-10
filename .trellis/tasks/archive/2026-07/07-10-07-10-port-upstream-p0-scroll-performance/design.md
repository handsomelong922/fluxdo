# P0 滚动性能手工移植设计

## Architecture Boundaries

### 1. 详情页 rebuild 边界

- `_TopicDetailPageState.build` 顶层只订阅“网络 detail 是否存在”的布尔边界，
  保留登录、搜索、AI 入口和布局偏好等页面级依赖。
- `Scaffold.body` 内建立局部 `Consumer`，在那里 watch 完整 detail，并始终通过
  `mergeTopicDetailWithInitialPreview` 合并 `_initialPreviewDetail`。
- 树形 provider watch 同样放入正文 Consumer，避免树形数据变化牵动外层 PageView。
- AI 页使用独立 Consumer 获取合并后的最新 detail；普通页面骨架不持有完整 detail。
- 主从布局切换需要标题时，在执行切换的 post-frame 回调中 `ref.read` 并合并当前
  detail，避免 build 期长期订阅完整对象。

该边界保持 preview 数据流不变：

`home card preview -> initialTopicPreview -> _initialPreviewDetail ->
mergeTopicDetailWithInitialPreview -> body Consumer -> TopicPostList`

### 2. Emoji paint isolation

- legacy raster emoji 在最内层 `Image` 外包 `RepaintBoundary`，外层 margin、
  `SelectableAdapter` 与文字选择结构保持不变。
- mention 状态 emoji、chat transcript 反应 emoji 采用同样的最小隔离。
- SVG emoji 不做额外处理：它不是逐帧 raster 动图来源，维持现有 SVG 渲染路径。

### 3. MessageBus batching and decode

- `TopicChannelNotifier` 用 `_pendingUpdates` 在当前同步派发结束后的微任务统一 flush。
- `TopicChannelState.postUpdates` 改为“最近一批”而非累积历史，并增加单调递增的
  `postUpdatesGeneration` 作为消费标记。
- 详情页 subscription 比较 generation，一次把整批交给 batch handler。
- batch handler复用当前 `_deferredPostUpdateKey`，保留 boost id 语义；超过 8 个
  需要网络刷新的不同帖子时，调用 `refreshWithPostNumber(anchor)` 获取最终态。
- 滚动延迟队列仍保存 notifier + update；滚停后转成同一 batch handler，确保实时
  批次和延迟批次共享同一套去重/坍缩规则。
- JSON chunk 小于 32 KiB 时同步解析；大于等于阈值时 `compute`。所有调用点 await，
  保证 chunk 与消息顺序不变。
- presence 使用 trailing 200ms Timer，在 pending list 上继续累积进入/离开事件；
  provider dispose 时取消 timer 并清理 pending。

### 4. Low-risk widget work

- `TopicProgress` 外包独立 `RepaintBoundary`，避免楼层号连续变化扩大列表脏区。
- `AutoScrollTag.builder` 直接返回现有 child，绕开项目未使用的默认 highlight
  transition；帖子自己的高亮参数仍是唯一高亮实现。

## Compatibility Notes

- 不修改 provider 加载、preview seed 写入和 `mergeTopicDetailWithInitialPreview`。
- 不引入上游新 renderer、`FrameJankMonitor`、`ScrollBusySignal` 或新 Flutter 转场
  API，保持 Flutter 3.38.9 兼容。
- MessageBus 坍缩刷新使用当前分支已有锚点计算，避免刷新后跳回顶部。
- 每个类别独立提交，可逐个 revert；若某项验证失败，只回滚该项，不牵连其他优化。

## Main Risks and Mitigations

- detail watch 下沉后 UI 状态不更新：所有实际消费 detail 的正文和 AI 页面都各自
  watch 合并后的 detail，并用现有 preview tests 验证首帖交接。
- batch 模式丢消息：boost 使用独立 key；created 不在滚动延迟范围；generation
  只在非空 flush 时递增。
- dispose 后异步写 provider：微任务检查 `_disposed`，Timer 在 dispose 取消。
- isolate 解析增加延迟：仅对 32 KiB 以上 chunk 使用，且严格串行 await。
