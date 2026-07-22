# Implementation Plan

1. 读取 Flutter、网络、跨层与代码复用规范，复核当前 `related_topics` 模型、service、provider、UI 数据流。
2. 先添加失败回归测试：空 `id`、缺失 `id`、空标题、非 map 条目、非列表顶层值，并证明主帖仍可解析。
3. 实现单一的相关话题容错解析器，同时供 `TopicDetail.fromJson` 和 `getRelatedTopics` 使用，保留缺字段/`null`/空列表语义。
4. 扩展 service/provider 错误路径测试，确保单条坏数据和补取失败均不影响帖子正文与末页回复。
5. 建立入口合同测试，覆盖首页点击、预览交接、搜索、我的收藏和浏览历史的统一详情路由/数据提供者。
6. 将相关帖子外部响应容错和所有详情入口同步覆盖要求写入 `.trellis/spec/`，执行 `trellis-break-loop` 复盘。
7. 运行格式化、定向模型/service/provider/widget/入口测试、完整 `flutter analyze --no-pub`、完整 `flutter test --no-pub`、`git diff --check`。
8. 仅暂存本次相关文件，检查提交边界，建立独立修复提交和规范/任务记录提交，最后统一推送 GitHub。

## Risky Files And Rollback Points

- `lib/models/topic.dart`：共享话题模型，不得将相关条目容错扩大到普通话题列表。
- `lib/services/discourse/_topics.dart`：首帖预取与末页相关补取的共同边界。
- `lib/providers/topic_detail/_loading_methods.dart`：必须保持“相关请求失败不丢末页回复”。
- 入口页面不做产品逻辑分叉；如需改动，仅允许收敛到统一路由合同。
