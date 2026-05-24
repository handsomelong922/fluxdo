# Assess upstream reading experience updates

## Goal

在当前稳定分支 `codex/rollback-to-v0.3.1` 上审慎吸收 upstream 近期对帖子阅读体验有实际收益、且与本地定制功能冲突风险低的改动。目标是提升阅读流畅度与信息完整性，同时避免引入 upstream 大规模工程迁移带来的回归。

## What I Already Know

- 当前分支已有多项本地定制：树形视图默认开启、AI 摘要持久化、阅读导航优化、验证后台化、登录持久化等。
- upstream/main 最新为 `da463c8 Update changelog for v0.2.15`。
- `HEAD..upstream/main` 涉及 442 个文件，包含 l10n/slang 迁移、AI 模型管理器大改、构建脚本和测试重组，不适合整段 merge/cherry-pick。
- 可低风险吸收的阅读体验增强集中在图片查看器、用户签名展示、树形视图新回复增量处理。

## Requirements

- 不整体合并 upstream/main，避免覆盖当前本地稳定改动。
- 整合图片查看器体验优化：
  - 图片查看页内的上下文菜单提供关闭入口。
  - Hero 滑动关闭动画避免飞行动画闪烁。
- 整合用户签名展示：
  - 从 Discourse `user_custom_fields.signature_cooked` 解析签名 HTML。
  - 正常视图、长帖分段视图、树形视图都能显示签名。
  - 阅读设置中提供显示/隐藏签名开关，默认开启。
  - 复用共享组件，避免多处复制样式。
- 整合树形视图新回复增量体验：
  - 自己回复后，树形视图立即插入对应根回复或子回复。
  - MessageBus 收到他人新回复时，根回复以按钮提示加载，子回复可插入父节点。
  - 去重，避免自己回复被 MessageBus 再插入一次。
- 保持现有定制行为：
  - 树形视图默认热门排序。
  - 树形视图自动展开和自动加载更多逻辑不回退。
  - AI 摘要、验证后台化、登录持久化逻辑不受影响。

## Acceptance Criteria

- [ ] `dart format` 已应用于改动 Dart 文件。
- [ ] 针对改动文件执行 `dart analyze`，不存在本轮新增错误。
- [ ] 偏好设置测试覆盖签名开关默认值与持久化。
- [ ] 树形视图加载更多相关测试仍通过。
- [ ] `git diff --check` 通过。
- [ ] 提交只包含本轮任务文档与明确代码改动，不纳入无关脏文件。

## Out of Scope

- 不迁移 upstream 的整套 slang/l10n 生成体系。
- 不合并 AI 模型管理器、构建工具链、发布脚本的大规模变更。
- 不引入新依赖。
- 不修改用户本地未跟踪/无关生成文件。

## Technical Notes

- 研究记录见 `research/upstream-reading-candidates.md`。
- 主要影响文件包括：
  - `lib/models/topic.dart`
  - `lib/providers/preferences_provider.dart`
  - `lib/settings/definitions/reading_defs.dart`
  - `lib/widgets/post/post_item/*`
  - `lib/widgets/nested/nested_post_card.dart`
  - `lib/pages/image_viewer_page.dart`
  - `lib/widgets/common/image_context_menu.dart`
  - `lib/providers/nested_topic_provider.dart`
  - `lib/pages/topic_detail_page/actions/_user_actions.dart`
