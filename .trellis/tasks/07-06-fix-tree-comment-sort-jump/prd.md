# 修复树形评论排序切换后大帖乱跳

## Goal

修复帖子详情树形视图中，用户从默认热门排序切换到最新或最旧后，滚动或继续操作时评论区在不同排序结果之间来回跳动的问题。

## Requirements

* 树形视图当前排序切换后，旧排序的分页请求返回时不得覆盖新排序状态。
* 快速多次切换排序时，只有当前最新排序请求可以回写根评论列表。
* 加载更多、MessageBus 新回复入口、子回复懒加载继续使用当前排序，不引入额外 UI 防抖作为唯一修复。
* 保持现有默认排序仍为热门。

## Acceptance Criteria

* [ ] 从热门切到最新或最旧后，旧的热门分页响应不会把 `NestedTopicState.sort` 或 `roots` 回滚。
* [ ] 最新/最旧排序下滚动触发加载更多时，列表不会在热门和当前排序之间反复重排。
* [ ] 快速切换 `new` / `old` 时，较早返回的排序请求会被丢弃。
* [ ] 添加回归测试覆盖 stale load-more 响应和 stale sort 响应。
* [ ] 通过针对相关 Dart 文件的分析和测试。

## Definition of Done

* 代码遵循现有 Riverpod/provider 分层。
* 运行针对性 Flutter 测试。
* 运行针对变更文件的 `flutter analyze`，如环境允许。
* 判断是否需要更新 spec。

## Out of Scope

* 不改变树形评论排序算法本身。
* 不重写树形视图 UI 或虚拟列表机制。
* 不调整服务端 `/n/topic` API 协议。

## Technical Notes

* 初步根因：`NestedTopicNotifier.loadMoreRoots()` 捕获旧 `current` 后异步回写；切换排序期间旧分页请求返回时，会用旧 `current.copyWith(...)` 把 `sort` 和 `roots` 回滚到旧排序。
* 相关文件：
  * `lib/providers/nested_topic_provider.dart`
  * `lib/pages/topic_detail_page/widgets/nested_post_list.dart`
  * `lib/services/discourse/_nested.dart`
* 已读取规范：
  * `.trellis/spec/core/index.md`
  * `.trellis/spec/core/project-conventions.md`
  * `.trellis/spec/core/flutter-app.md`
  * `.trellis/spec/guides/code-reuse-thinking-guide.md`
* `.trellis/spec/guides/index.md` 提到的 `cross-layer-thinking-guide.md` 当前不存在。
