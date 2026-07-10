# Technical Design

## Boundaries

本任务只适配三个请求收敛契约，不合并上游 `dev`，不替换当前请求调度器，
不修改首页详细展示、主帖 preview 复用、评论渐进加载、帖子导航与渲染架构。

变更边界：

- `WebViewSessionCookieRefreshService`：fingerprint endpoint 提取、bootstrap
  失败状态与插件候选新鲜度。
- `PreloadedDataService`：只增加旧 plugin candidates 的显式失效入口。
- 认证登出路径：只复位 WebView bootstrap 登录会话状态与 upload lookup
  会话缓存，不改登录/登出顺序和 Cookie/CF 保留语义。
- `_UploadsMixin` 与 `DiscourseImageUtils`：减少 `lookup-urls` 重复 POST，
  区分 confirmed missing 与 transient failure。

## Build Verification Contract

GitHub Actions 是安装包权威构建路径。run `29099617349` 已完整成功，release
`v0.6.103` 恰好包含：

- `fluxdo-arm64-v8a-full.apk`
- `fluxdo-windows-x86_64-setup.exe`
- `fluxdo-windows-x86_64.zip`

APK 本地下载后使用 `apksigner 36.0.0` 验证 v2 签名，通过 ZIP 目录核验
`lib/arm64-v8a/libdoh_proxy.so` 与 `lib/arm64-v8a/librhttp.so`。因此本任务
无需修改 workflow 或构建脚本。

## Fingerprint Endpoint Extraction

endpoint 仍由 WebView 内的插件源码提取。正则只放宽调用函数名：

- 函数名必须是合法 JavaScript identifier：`[A-Za-z_$][\\w$]*`。
- 后续仍必须紧邻稳定结构 `("endpoint",{type:"POST",data:{visitor_id:`。
- 不匹配任意字符串、任意 POST 或模糊 endpoint，避免误取其他插件调用。

为了让回归测试与 WebView 实际执行同源，正则 pattern 作为 Dart 常量注入
JavaScript，并提供纯 Dart 提取 helper 做固定样本验证。此变更不新增请求。

## Bootstrap Retry State

保留现有单 active Future、BrowserTrust、CookieJar、BoundarySync、CF 与诊断日志。

状态机：

1. 未执行成功：允许正常尝试。
2. 失败：`failureStreak + 1`，冷却按 45s、90s、3m、6m、12m、15m 封顶。
3. endpoint 404 或 discover 失败：设置 `forceFreshPlugin`，废弃预加载候选；
   本轮结束，不立即重试。
4. 下一轮：不注入旧候选，插件 JS 使用 `cache: reload` 做一次 fresh discover。
5. 成功或 `markSynced`：清零 streak 与 fresh 标记。
6. 普通成功状态在当前进程 × 登录会话内保持，不再按 15 分钟周期重跑；
   `force` 仍可绕过成功态和冷却用于 CF 恢复。
7. logout/换会话：复位成功态、失败态、候选新鲜度和最后尝试时间。

不修改当前请求 scheduler；所有 native 请求仍受默认并发 3、3 秒 6 个、
同 host 250ms 间隔、优先级与 429 server cooldown 约束。

## Upload Lookup Coalescing

### Result Semantics

`ResolvedUploadUrl.missing` 表示 `lookup-urls` 请求成功，但响应没有对应短链。

- successful response + returned item：缓存解析结果。
- successful response + absent item：缓存 `missing`。
- 网络异常、401/403/429/CF 或其他 throw：不写 missing，未来可重试。

### Request Coalescing

`resolveShortUpload` 在 service 层维护：

- 同 short URL 的 active Future 去重。
- 一个很短的事件循环微批窗口，收集同帧/同构建周期的不同 short URL。
- 每批只发送一次 `/uploads/lookup-urls` POST，不做客户端三次重试。
- batch 完成后分别完成每个调用方 Future；临时失败全部返回 null 且不缓存。

service cache 改为有上限的 LRU，正负结果共用容量，防止上游无界 Map 在长
会话持续增长。logout 增加 generation 复位：旧会话在途响应不得写入新会话。

`DiscourseImageUtils` 保留现有有界 LRU 对 widget 重建的快速命中，但改为：

- 成功 URL 与 confirmed missing 可缓存。
- transient failure 不再缓存为 null。
- 同一 short URL 继续共享 service 层 active Future。

现有图片、画廊、音视频、链接、Notion 和新上传回填 API 形态保持兼容。

## Compatibility And Rollback

- 三类改动形成独立 commit，可单独 revert。
- fingerprint commit 不触及状态机。
- bootstrap commit 不触及上传解析。
- upload commit 不触及 topic preview、首页摘要或帖子分页。
- 如 full test 暴露回归，只回退对应分类 commit，不用上游整提交覆盖当前文件。

## Main Risks

- 过宽正则误匹配：由 identifier + 稳定 POST/data 结构限制并用正反样本测试。
- 登录切换后错误跳过 bootstrap：logout 显式 reset，force 登录/CF 路径保留。
- transient failure 被误判 missing：只有 HTTP 请求成功后才为未返回 key 写哨兵。
- microbatch Future 悬挂：reset 会完成尚未发送的 completer；已发送批次通过
  generation 终止旧会话写入并最终完成 Future。
- 缓存增长：service 与 widget 两层均保持有界容量。
