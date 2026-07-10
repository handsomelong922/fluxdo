# 用户主页与 P1 性能移植设计

## Architecture Boundaries

### 用户主页数据流

`UserProfilePage.initState` 同时启动 `getUser` 与 `getUserSummary`。页面仍以 user 为
正式骨架门槛；summary 只负责统计与总结 tab。两个 Future 分别捕获错误，避免
`Future.wait` 的 fail-fast 让一条失败遮蔽另一条结果。

主页请求使用专用 `visibleUserProfileReadOptions()`：

- `priority=high`
- `skipWebViewSessionSync=true`
- `backgroundWebViewSessionSync=true`

auth interceptor 只对同时带 background 标记的 skip 请求触发 best-effort 后台同步。
该 helper 只在 `_fetchUser` 和 `_fetchUserSummary` 调用。

### 用户主页布局

统计区改为固定高度容器：第一行关注/粉丝，第二行四项 summary。两行使用单行
`FittedBox(scaleDown)` 保证窄屏不换行增高。summary 未完成时第二行渲染静态骨架，
失败时渲染等宽占位；容器本身始终存在，因此底部锚定 Column 的总高度稳定。

### 图片与滚动信号

`ScrollBusySignal` 是无监听器、无 rebuild 的时间戳状态：应用根部捕获 start/update
滚动通知并 `touch()`。AVIF completer 与 CF service 只查询 `isBusy`。

`LazyImage` 仍保留现有 Hero、手势、错误占位和固定尺寸 AspectRatio，但：

- 挂载即建立 `Image`，由 sliver/cacheExtent 和 Flutter scroll-aware 机制控制请求；
- provider 经 `ResizeImage(..., policy: fit)` 做宽度 × DPR 与 4096 高度 cap；
- 无尺寸图片监听相同 image stream 记忆宽高比，回收后按已知比例占位；
- 不接入 ImagePaintGate 或 AnchorGuard。

图片网格按 tile 长边 × DPR 同时设置 width/height cap。查看器仍直接使用原 provider，
AVIF 查看器的 `maxDimension: null` 保持不变。

### 帖子列表渐进物化

`TopicPostList` 维护 `_materializeCapBefore` / `_materializeCapAfter`：

- init：两侧各从 4 segment 开始，每帧 +4；
- append：after cap 从旧 after childCount +4 开始；
- prepend：before cap 从旧 before childCount +4 开始；
- cap 从不小于旧 childCount，因此不会卸载已存在 element；
- gap fill、replace、少量新增不启用分页 cap。

预热使用 generation 取消旧队列；每个 idle task 只处理一个新增帖子。长帖调用现有
`ChunkedHtmlContent.preload` 并在缓存可用后构造 `LongPostRenderData`，短帖复用已有
全局 preprocess/Pangu 缓存与分帧物化，不引入新 renderer contract。

### CF WebView

Android WebView 创建成功后启动 500ms ticker。目标状态为：

`ScrollBusySignal.isBusy && _initialTimer == null && !_isCallingRc`

状态变化时才发一次平台 pause/resume。dispose、stop、应用后台 pause 与新一代启动
都会取消 ticker；若旧实例处于滚动 pause，dispose 前不依赖 resume，原生实例销毁后
状态直接复位。

## Compatibility Notes

- 不修改 topic provider、preview seed cache、merge helper 或页面导航参数。
- 不修改树形列表；P1 materialization 只作用于普通 `TopicPostList`。
- 全局滚动信号没有订阅者，不会扩大 rebuild 边界。
- 用户主页非阻塞请求 helper 不复用到其他 endpoint，避免重演已撤回的全局扩张。
- 每个类别独立 commit，可单独 revert。

## Main Risks and Mitigations

- 主页 session 过旧：请求仍携带现有 cookie，并在后台继续 session sync；只有安全 GET
  跳过等待，401/CF 仍走现有 interceptor 恢复逻辑。
- 图片预取过早：依赖 sliver 虚拟化和 Flutter scroll-aware provider；decode cap 限制
  内存峰值，AVIF 滚动冻结限制持续 CPU/raster 负载。
- materialize cap 改变列表 extent：只向远端递增且不减少旧 childCount；preview 主帖
  位于 center/after 近端，首帧即物化。
- CF pause 打断挑战：首次计时器未结束或 RC 请求活跃时禁止 pause；异常时复位状态。
