# Verify release build and safely port upstream P2

## Goal

先确认当前分支最新 GitHub Actions 能完整构建并发布可安装
Android APK 与 Windows 产物；如构建失败则先定位和修复。在此基础上，
按当前分支架构手工移植 2026-07-07 至 2026-07-10 上游 P2 中可
独立证明安全的请求收敛修复，防止瞬时大量请求、无间隔连续请求、
失效 endpoint 永久重试和短链重复查询被官方判定为自动化抓取，
同时不删减现有功能或改写首页详细展示等当前分支独有体验。

## Confirmed Facts

- 当前分支已推送到 `9faecd85`；GitHub Actions run
  `29099617349` 已完整成功，Android、Windows 与 upload/release job 均为
  `success`，并发布 `v0.6.103`。
- workflow 要求 Android arm64 APK 同时包含 `libdoh_proxy.so` 与
  `librhttp.so`，并且 release 必须恰好包含 APK、Windows setup 和 ZIP
  三个可安装产物。
- `v0.6.103` release 已核验为恰好三个非空产物；APK SHA-256 为
  `9877310988ffd2fe4933ce5089038cd57e5deb6fdce7a0f1119acfbb8251c524`，
  与 GitHub asset digest 一致，APK Signature Scheme v2 验证通过且包含
  两个要求的 arm64 原生库。
- 当前 `RequestSchedulerInterceptor` 按 host 共享状态，默认最大并发
  3、3 秒窗口最多 6 个请求、同 host 相邻请求最小间隔 250ms，
  并且 429 后遵循服务端 cooldown。
- 当前分支的最小请求间隔和 429 cooldown 比上游 `dev` 当前
  实现更保守；本次不使用上游版本覆盖当前调度器。
- 首页详细展示的摘要加载、主帖 preview 即时复用与评论渐进加载
  是必须保留的产品契约。
- 上游 `3013d17a` 仅放宽 fingerprint endpoint 的压缩函数名正则，
  不增加请求数。
- 上游 `4a3dff00` 修复旧 fingerprint endpoint 永久 404 时每 45 秒
  重启一整套 Headless WebView bootstrap 的循环，通过指数退避、旧候选作废
  和登录会话级成功状态降低请求与 CPU 负载。
- 上游 `87d7ac8e` 对 `lookup-urls` 成功但未返回的失效 upload 短链
  记录会话级负缓存，防止 widget 重建后重复 POST。
- 上游 `a0a60491` 对应的 `BoostDanmaku` 组件在当前分支不存在；
  不为移植单个 Ticker 优化而引入整套上游弹幕架构。

## Requirements

### 1. GitHub Actions 产物验证

- 持续监控 run `29099617349` 直到 completed，不得只以个别 job 或 tag
  创建成功作为整体构建成功的证据。
- Android、Windows 和 upload/release job 都必须成功。
- 核验 Actions artifacts 与 GitHub release 的 APK、Windows setup、Windows ZIP
  名称、数量和非空大小。
- 下载 APK 到本地临时目录，使用 `unzip`/`apkanalyzer` 或等价工具确认
  其为有效 APK，包含 arm64 `libdoh_proxy.so` 与 `librhttp.so`，并用
  `apksigner verify` 验证签名。
- 如 run 失败，先根据失败 step/log 做最小修复、定向验证、独立提交
  并推送，再监控新 run 到成功。

### 2. 请求安全边界

- 不降低当前默认最小请求间隔、滑动窗口限制、host 共享调度、
  优先级队列、取消过时请求和 429 cooldown。
- 不恢复已撤回的全局 visible-read 非阻塞扩张；已有用户主页两条
  安全 GET 的窄范围策略保持不变。
- 任何新的请求路径都必须经过现有共享调度器，不设置
  `skipScheduler`，除非它已是现有认证/CSRF 内部死锁规避路径。
- 后台、静默、预热和自动刷新必须使用低优先级、in-flight 去重、
  负缓存或指数退避；不得在失败后无间隔重试。
- 用户主动操作可以提升优先级，但不得绕过并发数、窗口数和最小间隔。

### 3. P2 fingerprint/bootstrap 收敛

- 基于当前 `WebViewSessionCookieRefreshService` 手工适配 `3013d17a` 与
  `4a3dff00`，不覆盖当前 cookie、BrowserTrust、CF 与诊断日志架构。
- endpoint 提取正则匹配任意 JavaScript 标识符函数名，但仍以
  `POST + visitor_id` 稳定结构为边界，避免过度宽松误匹配。
- 失败冷却从 45s 开始指数增长，上限不超过 15min；成功、
  `markSynced` 和新登录会话必须正确复位失败计数。
- endpoint 404 或明确的 discover 过期需求必须作废预加载候选，
  下一轮仅进行一次 fresh discover，不在同一失败回调内紧接重试。
- 成功 bootstrap 在当前进程和登录会话内不反复执行；登出/换账号
  后复位，`force` CF 恢复路径仍可显式绕过成功态。

### 4. P2 upload 短链负缓存

- 基于当前有界 LRU 缓存手工适配 `87d7ac8e`，不恢复无界 Map。
- `lookup-urls` 请求成功但未返回的短链记为服务端确认不存在，
  会话内不再重试。
- 网络异常、CF/401/429 或其他临时失败不能记为永久 missing，
  需遵循现有 ErrorInterceptor/Retry-After/cooldown 后允许未来重试。
- 同一短链的同步重建必须共享 in-flight Future；同一微批窗口的多条
  短链合并为一个 `lookup-urls` POST，不得每张图独立请求。
- 保留图片、音频、视频、链接、Notion 附件和新上传回填的现有解析语义。

### 5. 移植范围与保护

- 不对上游整提交 cherry-pick，仅适配当前分支实际缺失的契约。
- `a0a60491` 在当前分支无对应弹幕组件，记录为不适用，不引入新 UI。
- 不移植滚动锚定、转场期隐藏正文/整页骨架、全局性导航转场重写、
  新 `fluxdo_render`、富文本编辑器、授权登录、编辑器图片工具或首页/分类 UI
  大改。
- `44ebd51d`/`459110da` 媒体兼容链涉及新 service、依赖、原生媒体处理
  和更多 URL 解析，不与本轮请求安全 P2 批次混合。
- 首页详细展示、`initialTopicPreview`、`_initialPreviewDetail`、
  `mergeTopicDetailWithInitialPreview`、评论渐进加载、搜索、跳楼、树形、AI 和
  MessageBus 语义不得降级。
- 每个独立修复分开提交，先本地验证和提交，全部完成后再一次
  推送 GitHub，不 squash，不提交既有未跟踪文件或密钥。

## Acceptance Criteria

- [ ] GitHub Actions run 完整成功，Android、Windows、upload/release jobs 均为
      success。
- [ ] release/artifact 包含且仅包含预期的 APK、Windows setup 与 ZIP；
      APK 签名有效且包含 arm64 `libdoh_proxy.so` 和 `librhttp.so`。
- [ ] fingerprint endpoint 提取兼容函数名混淆变化，无宽松到误匹配的正则。
- [ ] bootstrap 失败指数退避、成功/登录会话复位和过期插件候选换新
      行为通过测试，不会因持续 404 每 45 秒无限启动 WebView。
- [ ] 短链同帧/短窗口请求微批合并，同短链 in-flight 去重；服务端确认
      missing 会话内不重试，临时网络失败仍可恢复。
- [ ] 当前默认 3 并发、6/3s 窗口、250ms 最小间隔、优先级和 429
      cooldown 保持不变；未新增 scheduler bypass 或高频无穷重试。
- [ ] 用户主页、首页摘要、图片/媒体短链、登录/登出、Cookie/CF、帖子 preview
      与消息流相关回归测试通过，`flutter analyze lib test` 与完整 `flutter test`
      通过。
- [ ] 各修复按类别独立 commit，Actions 修复（如有）与各 P2 移植可分别
      revert，未跟踪用户现场不进入提交。
- [ ] 全部本地提交与验证完成后，当前分支成功推送到 GitHub，远端
      HEAD 与本地一致。

## Out of Scope

- 全量合并上游 `dev` 或重写当前请求调度器。
- 恢复 `12ddd1bb` 已撤回的全局 visible-read 策略。
- 移植当前分支无对应功能的 Boost 弹幕、新渲染器或富文本编辑器。
- 未经单独设计与验证的媒体重封装、授权登录、导航转场或首页 UI 重构。
- 为通过本地环境而降级签名、移除 native library 或放宽 release artifact 要求。
