# Fix Profile Follow, Boost Display, AI Summary, CDK Flow, and Topic Cache Assessment

## Goal

修复 Linux.do 交互中的四个明确问题：用户主页关注要真正调用服务端并实时反映状态，Boost 回复要完整显示 16 字以内内容，AI 摘要进入助手后要保留 Markdown 渲染并清理异常不可见字符，CDK 领取页要一键关闭并尽量减少手动认证。同时按确认后的推荐策略落地帖子详情 stale-while-revalidate 内存快照缓存。

## What I already know

* 用户提供的网页抓包显示关注接口为 `PUT https://linux.do/follow/Yelo.json`，响应 200，`x-discourse-route` 为 `follow/follow/follow`。
* 当前代码的关注接口在 `lib/services/discourse/_users.dart` 中使用 `/follow/$username`，没有 `.json` 后缀。
* 用户页本地状态位于 `lib/pages/user_profile_page.dart`，成功后只翻转 `_isFollowed`，没有基于服务端返回或重新拉取用户状态校准。
* Boost 展示集中在 `lib/widgets/post/post_boost/boost_bubble.dart` 和 `boost_list.dart`，当前存在宽度估算、单行文本和溢出处理逻辑。
* AI 摘要继续对话入口是 `TopicAiChatNotifier.continueFromSummary()`，当前把摘要作为 `TopicPostContext(cooked: summary)` 注入上下文，并添加用户/助手消息。
* AI 聊天消息 UI 使用 `AiChatMessageItem`，需要确认 Markdown 渲染和内容清洗链路是否一致。
* CDK/LDC 相关代码在 `lib/services/cdk_oauth_service.dart`、`lib/providers/cdk_providers.dart`、`lib/pages/metaverse_page.dart`、`lib/pages/webview_page.dart`。
* 帖子详情加载由 `lib/providers/topic_detail_provider.dart` 和 `lib/pages/topic_detail_page/` 驱动；当前已有 provider `keepAlive`/短期 dispose 行为，但用户观察到再次进入仍重新加载。

## Requirements

* 关注按钮必须调用 Linux.do 真实关注/取消关注接口，并在请求成功后显示服务端一致状态。
* 关注/取消关注失败时不得静默表现为成功；UI 需要恢复原状态或保持当前可信状态。
* Boost 气泡中的 16 字以内回复必须完整显示，不出现省略号、折叠或屏幕外遮挡。
* Boost 内容过长时优先通过换行、约束宽度和必要的字体自适应保证完整可见。
* AI 摘要点击“继续”进入 AI 助手后，摘要内容必须按 Markdown 渲染，而不是展示原始 `**`、列表符号、链接语法等。
* AI 摘要进入助手前需要清理可能导致 Markdown/JSON/Flutter 文本渲染异常的不可见控制字符，但不能破坏正常 Markdown。
* CDK 领取页从 `https://cdk.linux.do/receive/` 打开时，左上角按钮应始终作为关闭入口，一次点击退出整个 CDK 页面，而不是按 WebView history 返回三次。
* CDK 服务在应用启动时如果已开启，应自动刷新/认证，尽量避免用户领取时再次手动确认。
* 如果 CDK 服务未开启，是否自动开启需要用户确认后再改，因为这会改变用户授权边界。
* 帖子详情缓存按推荐策略落地安全 MVP：缓存完整 `TopicDetail` 快照，保留 `instanceId` 页面隔离，重新进入同帖时先渲染缓存，再按软 TTL/目标楼层后台刷新。

## Acceptance Criteria

* [ ] 关注用户后，服务端接口返回成功，重新进入该用户主页仍显示已关注。
* [ ] 取消关注后，重新进入用户主页显示未关注。
* [ ] 网络/API 失败时关注按钮不显示错误的成功状态。
* [ ] 14、15、16 字 Boost 内容在手机宽度内完整显示，无省略号。
* [ ] 多个 Boost 同行或换行布局不会超出屏幕宽度。
* [ ] AI 摘要继续到助手后，列表、加粗、链接等 Markdown 正常渲染。
* [ ] AI 摘要中的不可见控制字符被过滤，不影响正常换行、制表符和 Markdown 标记。
* [ ] CDK receive 页面左上角一次点击关闭页面。
* [ ] 已开启 CDK 服务时，应用启动会触发静默刷新/认证尝试。
* [ ] 帖子缓存方案明确说明缓存对象、有效期、刷新触发、内存/网络权衡和新评论处理。
* [ ] 同一用户重新进入 1 天内打开过的同一话题时，若目标楼层已在快照内，应立即显示缓存快照。
* [ ] 缓存超过软 TTL 或带目标楼层入口时，应先显示快照并后台刷新。
* [ ] 缓存缺失、硬过期或目标楼层不在快照中时，应回退到原网络加载路径。

## Definition of Done

* 读取适用 Trellis spec 后再改代码。
* 对修改文件运行窄范围 `flutter analyze` 或等效验证。
* 如涉及可测试纯逻辑，补充或运行相关单元测试。
* 不混入用户已有未提交改动。
* 判断是否需要更新 `.trellis/spec/`。

## Out of Scope

* 未确认前不自动替用户开启从未开启过的 CDK 服务。
* 不修改 Linux.do 服务端行为。
* 不引入新依赖，除非现有 Markdown/HTML 渲染组件无法复用。

## Technical Notes

* Attachment: `C:\Users\User\.codex\attachments\b4aecafc-b5c4-46ad-b164-436a11e8513c\pasted-text.txt` confirms `PUT /follow/Yelo.json` with empty body and `x-csrf-token`.
* Relevant spec index: `.trellis/spec/core/index.md`.
* Likely spec files to read before implementation: `.trellis/spec/core/project-conventions.md`, `.trellis/spec/core/flutter-app.md`, `.trellis/spec/core/network-and-time.md`, `../guides/cross-layer-thinking-guide.md`, `../guides/code-reuse-thinking-guide.md`.
* Current branch has many uncommitted Trellis/project files predating this task; commits must stage only this task's files.

## Research References

* [`research/topic-detail-cache-assessment.md`](research/topic-detail-cache-assessment.md) — recommends stale-while-revalidate topic snapshots with 24 hour hard TTL and short soft refresh.

## Technical Approach

* Use `/follow/{username}.json` for follow/unfollow and refresh the profile after mutation to align with server state.
* Let Boost chip text wrap inside a bounded text area instead of using single-line ellipsis.
* Store the generated summary as an assistant Markdown message when continuing into AI chat; keep a short user instruction message for conversation flow.
* Sanitize AI summary text by removing control characters and bidi controls before storing/displaying it.
* Make `CdkPage` close the whole route from the leading button/system back instead of traversing WebView history.
* For enabled CDK service, perform startup/resume silent refresh and silent OAuth approval where the HTTP flow can complete without WebView fallback.
* Implement topic detail caching as an in-memory LRU cache first because `TopicDetail` has no safe full-model `toJson` contract. Disk persistence is deferred until raw-response/model serialization contracts are explicit.

## Deferred Decision

* Disk persistence for full topic detail snapshots remains deferred. The implemented MVP uses a 1 day hard TTL in memory and can be extended later with raw JSON persistence once serialization contracts exist.
