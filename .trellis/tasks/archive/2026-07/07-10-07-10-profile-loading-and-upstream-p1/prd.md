# 优化用户主页加载并手工移植上游 P1

## Goal

先消除点击头像进入他人主页时的长时间等待与统计区晚到造成的页面上下跳动，
再基于当前分支架构手工移植 2026-07-07 至 2026-07-10 上游 P1 滚动性能
优化，降低图片解码、AVIF 动图、翻页落地和后台 CF WebView 对滚动帧的干扰，
同时严格保护当前分支独有的“首页详细展示”、主帖即时复用和评论渐进加载。

## Confirmed Facts

- 当前 `UserProfilePage` 先串行请求 `/u/:username.json`，拿到用户资料后才请求
  `/u/:username/summary.json`；两条请求都可能等待 WebView session sync。
- 主页在用户资料返回后立即切出全页骨架，但统计区只有 `_summary != null` 时才
  插入；统计区位于底部锚定的展开头部 Column 中，因此 summary 晚到会改变整组
  内容高度并造成明显位移。
- 2026-07-08 曾有提交 `12ddd1bb` 同时扩大所有 visible-read 的非阻塞范围，
  后按用户要求由 `6e625c18` 整体撤回；本次不得恢复那组全局请求策略，只允许对
  用户主页两条安全幂等 GET 做窄范围适配。
- 当前 legacy 正文图片仍使用逐图 `VisibilityDetector`，正文和图片网格没有
  decode-time 宽高双向 cap；帖内 AVIF 已有 2048 长边上限，但动画播放不会在
  全局滚动繁忙时让路。
- 当前帖子列表已有双向 `SliverList.builder`、主帖 preview 合并、长帖分段和
  HTML 预热，但没有首屏/翻页双侧渐进物化；滚动中到达的预热任务可能直接跳过。
- 当前 CF 自动续期使用持久 Headless WebView；Android 上它与滚动共享平台主线程，
  但现有生命周期 pause/resume 只覆盖应用前后台，不覆盖页面滚动。
- `upstream/dev` 已同步至 `e172ffb792137d3730bafffb3032ef70fb7249f8`。
  `aad051f1` 之后新增提交均为富文本编辑器、授权登录或编辑器图片交互，不属于本次
  帖子滚动 P1 移植范围。

## Requirements

### 1. 用户主页首屏加载

- 用户资料与 summary 必须在进入页面后立即并行发起；用户资料先返回时即可展示
  正式页面，summary 继续独立完成，任一请求失败不能取消另一请求。
- 仅 `/u/:username.json` 与 `/u/:username/summary.json` 使用高优先级、跳过阻塞
  WebView session sync、同时触发后台 session sync 的请求选项。
- 不把该策略扩展到登录、CSRF、CF challenge、mutation、私信、书签、话题列表或
  其他用户接口。
- 保留现有 in-flight 去重、summary 五分钟缓存、关注/屏蔽/通知级别语义。

### 2. 用户主页固定布局

- 用户资料返回后，展开头部必须立即为“关注/粉丝”和“获赞/访问/话题/回复”两行
  统计预留固定高度。
- summary 加载中显示与终态同尺寸的静态占位；加载失败时仍保持相同几何尺寸，
  不允许最近活动时间或头像/名称区域因统计数据晚到而上下移动。
- 窄屏和中英文标签不得让统计区换行增高；数值、关注/粉丝点击入口和 Tooltip
  行为保持可用。

### 3. P1 图片 decode 与 AVIF 滚动策略

- 正文独立图片和图片网格按实际显示逻辑尺寸 × DPR 做 decode-time 缩放，并同时
  设置高度/长边 cap，避免长截图和大图上传超大纹理；图片查看器继续走原图路径。
- 正文图片不再额外使用逐图 `VisibilityDetector` 推迟到已进入视口才加载；依赖
  sliver 虚拟化与 Flutter `ScrollAwareImageProvider` 的快滚延迟机制。
- 图片加载、动画和首帧绘制限定在图片自身 `RepaintBoundary`；无声明尺寸图片可
  记忆已解析宽高比以稳定回收后重建，但不得引入滚动锚定算法。
- 新增全局轻量滚动繁忙信号；AVIF 动画在繁忙窗口冻结当前帧，静默后自动恢复。
- 不移植 `ImagePaintGate` 图片首绘逐帧闸门。

### 4. P1 翻页渐进物化与解析预热

- 帖子列表首次挂载时，center 两侧远端 segment 分帧增加；center、主帖 preview
  和其近邻必须首帧可见，不得等待网络或改变主帖即时展示。
- 只在纯尾部追加或纯头部插入且新增 segment 足够多时重启对应侧 materialize cap；
  已物化旧 segment 不得被卸载，中间 gap 填充和整页替换保持原行为。
- 新增帖子利用现有 `ChunkedHtmlContent` / `HtmlChunkCache` / `LongPostRenderData`
  在 idle 优先级预热；新一轮分页必须使旧预热队列失效，避免重复竞争。
- `loadMore`、`loadPrevious`、跳楼、搜索、树形评论、MessageBus 整流刷新和
  `mergeTopicDetailWithInitialPreview` 语义不变。

### 5. P1 CF WebView 滚动挂起

- 全局滚动信号只记录最近滚动时间，不在热路径做平台调用或触发 widget rebuild。
- Android CF Headless WebView 仅在首次 Turnstile 已完成、没有活跃 RC 请求且滚动
  繁忙时调用 `pause()`；静默后调用 `resume()`。
- pause/resume 失败必须恢复内部状态，不能让 WebView 永久卡在挂起态；stop、应用
  后台 pause、dispose 和新 WebView 启动必须取消 ticker 并清理滚动挂起状态。
- 非 Android 平台保持原行为。

### 6. 版本与范围

- 全部改动按当前架构手工适配，不 cherry-pick 上游整提交。
- 首页详细展示、`initialTopicPreview`、`_initialPreviewDetail`、
  `mergeTopicDetailWithInitialPreview`、评论渐进加载和 AI/树形/搜索入口不得删除或
  降级。
- 独立类别分开提交：主页加载与布局、图片/AVIF、分页物化、CF WebView、测试/规范
  可独立回滚；不得 squash。
- 只暂存本任务 tracked 文件；不得提交既有未跟踪 Trellis 历史、密钥、用户文件或
  `.learnings/`。
- 完成全部验证和本地提交后，将当前分支上尚未推送的 P0 与本次提交原样推送到
  `origin/codex/rollback-to-v0.3.1`。

## Acceptance Criteria

- [x] 点击头像后用户资料与 summary 并行请求，主页两条只读 GET 不再等待阻塞式
      WebView session sync，其他网络请求策略不变。
- [x] 用户资料返回后统计区始终占据固定两行高度；summary 成功、失败或加载中切换
      时，最近活动与上半部结构位置不变。
- [x] 正文图和网格图有 decode-time 宽高 cap，查看器原图不受影响；正文图不再有
      逐图 VisibilityDetector 热路径。
- [x] AVIF 动画滚动繁忙时停止继续解帧，滚停后恢复；全局滚动信号不触发 UI rebuild。
- [x] 首次进入详情仍立即显示 preview 主帖；评论和翻页新增 segment 分帧物化，旧段
      不被卸载，append/prepend/gap/replace 路径区分正确。
- [x] Android CF WebView 只在安全条件下随滚动 pause/resume，生命周期和错误路径无
      卡死或重复状态。
- [x] 用户主页、网络请求策略、LazyImage、帖子 preview/跳楼/分页、MessageBus、CF
      相关定向测试通过，`flutter analyze lib test` 通过。
- [x] 每类独立本地 commit 已创建，`git diff --check` 与提交内容检查通过。
- [ ] 当前分支全部待推送提交已成功推送到 GitHub，未跟踪用户现场未被上传。

## Out of Scope

- 合并上游 `dev`、引入 `packages/fluxdo_render` 或富文本编辑器功能。
- 图片首绘闸门、`AnchorGuardSliver`/滚动锚定、转场期隐藏正文或整页骨架延迟。
- 改写首页详细展示、主帖 preview 合并、评论分页产品逻辑。
- 将非阻塞 visible-read 策略重新扩展到所有列表或用户内容接口。
- 与滚动无关的 7 月 10 日新授权登录、编辑器图片操作和富文本编辑提交。
