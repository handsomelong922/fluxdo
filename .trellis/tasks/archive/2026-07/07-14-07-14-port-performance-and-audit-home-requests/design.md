# Technical Design

## Boundaries

- MessageBus 协议进度与 UI 投递分离：`lastMessageId` 收到即推进，只延迟订阅回调和广播。
- 图片解码限流只包装 Flutter 标准 codec 的首次 `getNextFrame()`；不修改 AVIF、sticker thumbnail 和 native animated provider。
- 首页列表优化只变更数据依赖和快速路径，不更换现有 Widget 结构和样式。
- 首页预览种子、TopicDetailCacheService 和 TopicDetailNotifier 后台重验契约保持不变。

## MessageBus Delivery Design

- `_handleMessage` 首先处理 status 和推进频道 `lastMessageId`。
- 需延迟时进入有界 FIFO；队列满时不直投新消息，而是从队头分批排空后再继续，保证顺序。
- 每批投递数量有上限，批间使用 event-loop yield；若又进入滚动繁忙则停止排空。
- `stopAll` 和 `dispose` 取消 timer，清空队列，通过 generation 防止已调度的旧 drain 继续投递。
- 向性能诊断记录队列深度/排空批次，但只走现有有界诊断入口。

## Image Decode Gate Design

- 新增一个小型 FIFO semaphore，默认标准首帧解码最多 2 个并发。
- `GatedImageCodec` 仅限流第一次 `getNextFrame`，后续帧直接转发。
- `dispose()` 标记 codec；排队任务获得令牌后若已 dispose，抛出可预期异常并归还令牌。
- 自定义 binding 只覆写 `instantiateImageCodecWithSize`，`main()` 最早期使用该 binding。
- 不接入 `native_animated_image.firstFrameGate`，因当前依赖版本无该稳定合同。

## Home Detailed Display Request Governance

- 删除 `PreheatGate` 的独立主帖预热 loader，从源头消除启动重复抓取；首屏仍由可见卡片的共享 provider loader 渐进加载。
- 开关关闭时不构建 `_HomeExcerptLoader`，不调用 fetcher。
- 关闭后不主动清除已有摘要缓存，以便用户点击时仍可立即承接首帖；读缓存不产生请求。
- 开启模式的请求仍经全局 scheduler 的 low/silent 通道，可见项销毁时取消未开始队列项。
- 如果代码/测试证明仅消除双 loader 仍不足以控制请求，再在 loader 内增加专用滑动窗口预算；不盲目降低全局调度器。

## Home Card Safe Optimization

- `TopicCard`/`CompactTopicCard` 增加可选 `categoryMap` 参数；未传时保留现有 provider fallback。
- `TopicsPage` 在页面层读取一次分类快照并向首页/分类列表传递；缓存或签名必须包含与展示相关的分类输入。
- Emoji 标题不包含 `:` 时返回普通 TextSpan，输出像素不变。

## Compatibility And Rollback

- 每个改动单独 commit，可逐个 revert。
- MessageBus 队列可通过一个局部常量关闭延迟分支，但不引入用户面向设置。
- 图片 binding 回滚只需恢复 `WidgetsFlutterBinding.ensureInitialized()` 并删除闸门文件。
- 首页预热回滚可单独恢复，不影响摘要 provider 和详情种子契约。
