# 优化启动首屏请求与请求耗时排序

## Goal

让用户点开应用后尽快看到首页帖子标题和摘要，避免“我的”等非当前页面数据在首屏阶段抢占网络与构建资源，并提供可观察的启动期请求耗时排序，支持后续继续精确优化。

## Confirmed Facts

- 启动阶段 `PreheatGate` 会等待 `BrowserTrustCoordinator.ensurePreloaded()` 和 `PreloadedDataService.waitForInitialTopicListReady()`，然后才进入 `MainPage`。
- `PreloadedDataService` 通过 `GET /` 获取 Discourse 首页 HTML，并解析 `data-preloaded` 中的 `currentUser`、`siteSettings`、`site`、`topicList`、追踪状态和 emoji。
- 首页默认 `latest` 列表优先消费预加载的 `topicList`；拿不到才请求 `/latest.json`。
- `MainPage` 使用 `IndexedStack` 一次性构建所有底栏 page；默认底栏包含 `home` 和 `profile`。
- `ProfilePage` 即使不是 active，也会构建 `_ProfileHeader` 和 `ProfileStatsCard`。
- `ProfileStatsCard` 默认启用统计项，默认数据源是 `userSummaryProvider`，会触发 `/u/{username}/summary.json`。
- 当前用户头像可从 `GET /` 的 `currentUser` 拿到；头像本身不需要额外 summary 请求。
- LDC/CDK provider 首次 build 只读缓存，不主动请求第三方接口。
- 首页摘要是用户需要的首屏内容，不应简单延后到不可见；优化重点是减少其它非首屏请求干扰，并观察摘要请求耗时。
- 首页内容与登录账号相关；启动时用于恢复登录态、同步 Cookie/CF、获取带权限的预加载首页 HTML 的请求属于关键路径，本次不得修改或延后。

## Requirements

1. 非当前底栏页面不得在应用首屏阶段主动构建完整页面内容。
2. “我的”页面的统计请求不得在首页首屏阶段触发。
3. “我的”底栏头像仍可使用 `currentUser` 的预加载数据展示，不因为延后 profile 页面而退化。
4. 首页帖子标题和摘要仍是首屏优先目标；不要禁用首页摘要功能。
5. 启动期请求排序应能按耗时实时或近实时展示/记录，至少包含 method、URL path、status、duration、priority、是否 silent/background、相对启动时间。
6. 请求排序不应记录 query 参数、cookie、token 或正文内容。
7. 优化不得改变登录、通知、MessageBus、CF 验证、首页列表 fallback 的基本行为。
8. 不得修改登录态恢复、Cookie/CSRF/CF trust、`BrowserTrustCoordinator.ensurePreloaded()` 的语义；这些请求即使出现在启动阶段，也应保留为关键路径。

## Acceptance Criteria

- [ ] 冷启动停留在首页时，不再因为默认 `profile` 底栏 entry 构建而触发 `/u/{username}/summary.json`。
- [ ] 切换到“我的”后，统计卡正常展示缓存/加载状态，并按需触发 summary 请求。
- [ ] 首页首屏仍能使用 `data-preloaded.topicList` 或 `/latest.json` fallback 展示帖子标题。
- [ ] 首页摘要请求仍可执行，但不会被“我的”统计请求并发抢占。
- [ ] 启动请求榜可查看或导出当前启动 session 内请求，并按 duration 降序排序。
- [ ] 请求榜不包含敏感查询参数、cookie、token 或 request/response body。
- [ ] Flutter analyzer 对改动文件无新增错误。

## Out of Scope

- 不重写 Discourse 预加载 HTML 解析机制。
- 不取消首页摘要能力。
- 不更改网络适配器、CF challenge 或 Cookie 同步主流程。
- 不延后或跳过启动期登录态恢复、Cookie 同步、CF trust、账号权限相关首页预加载。
- 不处理所有历史页面的懒加载优化；本次聚焦默认首页 + 我的页 + 启动请求可观测性。
