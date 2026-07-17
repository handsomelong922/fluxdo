# 技术设计

## 根因与边界

本次修复只处理客户端在“帖子 → 官方 CDK/credit WebView → 返回帖子”路径中制造的非必要请求，不改变服务端限流，也不放宽 429 处理。

请求链如下：

```text
子路由 push
  -> TopicDetailPage 关闭 topic channel subscription
  -> _topicChannelNeedsCatchUp = true（当前实现无条件设置）
  -> CDK/credit 页面退出
  -> didPopNext / _syncTopicChannelSubscription
  -> refreshWithPostNumber() 自动 GET 话题详情
  -> 用户手动刷新再次 GET 话题详情
```

CDK 页还存在额外链路：

```text
CdkPage.initState
  -> _seedSessionAndReloadIfNeeded
  -> CdkOAuthService.authorizeSilently
  -> OAuth login / approve / callback 请求及可能的重定向
```

credit 页使用通用 WebView，不执行第二条链路，但仍命中第一条。

## 方案

1. `TopicDetailPage` 隐藏时仍关闭实时频道订阅，但不再把“订阅关闭”本身当成发生了新事件；返回时只重新订阅，不自动完整刷新话题。用户显式下拉/点击刷新仍走现有请求和 429 保护。
2. `CdkPage` 保留打开 WebView 前的 Cookie priming 与必要 reload，但移除静默 OAuth。用户在 CDK/credit 页面内的实际登录、领取、支付交互不变。
3. 不修改 `RequestSchedulerInterceptor`、429 cooldown 或 Dio retry evaluator，避免把真实服务端限流掩盖为客户端策略变化。

## 兼容性与回滚

- 普通话题浏览、普通外链、CDK/credit WebView 导航和显式刷新保持原入口。
- 返回帖子后不再隐式拉取完整详情；这会把“返回后刷新”恢复为单次用户请求，实时隐藏期间的增量由用户显式刷新获取。
- 回滚只需恢复 `topic_detail_page.dart` 的返回刷新分支和 `cdk_page.dart` 的静默授权调用。

## 验证策略

- 静态检查确认 CDK 页不再引用 `authorizeSilently`，返回路径不再调用 `refreshWithPostNumber`。
- 运行 CDK host/link、话题初始加载 429 不重试、相关 topic route 单元测试。
- 对改动 Dart 文件执行定向 `flutter analyze`；不执行虚拟机持续模拟。
