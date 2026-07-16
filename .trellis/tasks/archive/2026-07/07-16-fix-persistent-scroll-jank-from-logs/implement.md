# 实施计划

1. 加载 `trellis-before-dev`，读取 Flutter app、代码复用和跨层规范。
2. 提取并测试刷新头部与已加载尾部的 topic-id 合并策略。
3. 为显式首页刷新接入保留尾部模式，并保留分页状态；筛选/排序/stale 路径维持完整替换。
4. 为首页 topic child 增加稳定 topic-id key 和 O(1) child index lookup，补 widget/纯逻辑测试。
5. 提取可在 isolate 中执行的性能日志计数/retention 计算，接入 `_loadEntryCountIfNeeded` 与 `_enforceRetentionIfNeeded`。
6. 运行定向 provider、topics page、性能诊断、首页摘要、TopicCard、详情预览与渐进加载测试。
7. 执行 Trellis check、全量 Flutter test、全量 analyze、diff/check 和行为审查。
8. 按首页刷新稳定性、诊断 retention 后台化、规范/任务记录拆分本地提交。
9. 复核远端、提交列表和工作区隔离后，一次性推送 GitHub。

## 验证命令

- `flutter test --no-pub test/services/performance_diagnostics_service_test.dart ...`
- `flutter test --no-pub`（全量）
- `flutter analyze --no-pub`
- `git diff --check`
- `git status --short --branch`
- `git log --oneline origin/codex/rollback-to-v0.3.1..HEAD`

## 高风险文件与回滚点

- `lib/providers/topic_list/topic_list_provider.dart`：只改显式刷新提交策略和分页保留。
- `lib/pages/topics_page.dart`：只改 item identity/index lookup，不改卡片构建参数或样式。
- `lib/services/performance_diagnostics_service.dart`：只改日志维护执行位置，不改诊断 schema。
- 每个产品根因独立 commit，可单独 revert；用户已有未跟踪文件不暂存。
