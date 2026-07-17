# 实施计划

1. 修改 `lib/pages/topic_detail_page/topic_detail_page.dart`
   - 删除 `_topicChannelNeedsCatchUp` 状态。
   - 隐藏路由时关闭订阅但不安排完整详情刷新。
   - 返回路由时只恢复订阅。
2. 修改 `lib/pages/cdk_page.dart`
   - 删除 CDK 页启动时的 `CdkOAuthService.authorizeSilently()`。
   - 保留 Cookie priming、WebView 创建、必要 reload 和可信 host 导航判断。
3. 补充/调整定向回归测试与静态断言，覆盖 CDK host、429 不重试和返回路径无自动刷新。
4. 运行 `dart format`、定向 `flutter analyze`、相关 `flutter test`、`git diff --check`，并复核禁止的时间 API 搜索。
5. 仅暂存本任务修改文件，创建一个独立本地 commit；确认提交内容后推送当前远端分支。

风险点：`TopicDetailPage` 返回后不再自动补拉隐藏期间的新回复，属于有意的请求语义收敛；用户显式刷新和实时频道重新订阅仍可恢复最新内容。
