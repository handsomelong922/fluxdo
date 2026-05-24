# Upstream Reading Candidates

## Reviewed Upstream Range

- Remote: `upstream/main`
- Current upstream HEAD: `da463c8 Update changelog for v0.2.15`
- Remote dev HEAD after re-fetch: `5b9cc29 ✨ AI 提供商排序置顶与模型收藏排序，新增发帖 AI 审核，修复网页端草稿编辑问题 (#261)`
- Local base: `094834f fix: polish reading interactions and login persistence`
- Full diff scope: 442 files, too broad for safe wholesale merge.

## Safe Candidates To Integrate

### `5f9881b` 图片查看器体验优化

- Value: adds a close action to image context menu inside the viewer and stabilizes Hero slide transitions with `flightShuttleBuilder`.
- Conflict risk: low. Files are localized to image viewer and shared image menu.
- Integration decision: include.

### `cf64fc0` 用户签名显示支持

- Value: restores forum signature visibility in post reading contexts, improving information completeness for users who rely on signatures.
- Conflict risk: low to medium. It touches model parsing, preferences, settings, and three render surfaces.
- Local adaptation: use a shared `PostSignature` widget instead of duplicating UI in each render surface.
- Integration decision: include.

### `e9b55be` 树形视图体验优化

- Value: improves real-time new-reply handling in threaded reading mode.
- Conflict risk: medium. Current branch already has custom auto-expand and auto-load behavior in tree mode.
- Local adaptation: preserve existing auto-expand/load behavior, add only incremental new-root/new-child state with dedupe and non-invasive UI.
- Integration decision: include carefully.

## Candidates Deferred

### `3bd10f3` Cookie 同步到 webview 逻辑优化

- Reason: overlaps with existing custom login persistence and verification background work. It is valuable, but not directly a reading-experience merge and needs separate auth-focused regression testing.

### `17792c3` Boost 切换到帖子回复

- Reason: useful composition behavior, but mostly affects posting/composer flow rather than reading. It touches reply and boost input paths already customized locally.

### `78cd459` 剪贴板话题链接识别服务

- Reason: useful navigation feature, but not core in-topic reading and adds service/UI scope.

### `0cf898c` 新话题二级筛选

- Reason: topic discovery feature, not post reading. Also touches list filtering state.

### `5d5818b` AI 助手功能优化（upstream/dev）

- Reason: potentially useful long-term, but overlaps the local branch's custom AI summary persistence and assistant context work. Merging it now would touch topic detail, AI chat UI, provider state, and HTTP bridge code, so it needs a separate AI-focused design/test pass.

### `ca41231` 登录后加载交接修复（upstream/dev）

- Reason: auth-adjacent and valuable, but this branch already has custom third-party browser login persistence and verification background handling. It should be evaluated in an auth-specific task rather than mixed into reading UI changes.

### `5a0210e` rhttp 引擎开关持久化修复（upstream/dev）

- Reason: network settings reliability improvement, not directly a topic reading experience feature. It also touches dependencies/lockfile and platform settings, so it is outside this task's low-risk scope.

### `f2e4fee` 桌面布局与侧边栏导航分组（upstream/dev）

- Reason: desktop navigation improvement, but it changes adaptive scaffold/navigation structure and tests. It is not necessary for in-topic reading continuity and should be reviewed separately to avoid layout regressions.

### `5b9cc29` AI provider sorting, post AI review, draft edit fixes（upstream/dev）

- Reason: broad AI/composer feature set with 50+ files, package changes, localization additions, lockfile updates, and new services. High conflict risk with the current branch's AI assistant and reply/draft customizations; not safe to integrate in this reading-focused pass.

## Merge Strategy

- Do not cherry-pick commits directly.
- Manually port selected behavior into current code to preserve local customizations.
- Run targeted format/analyze/tests and inspect final diff before commit.
