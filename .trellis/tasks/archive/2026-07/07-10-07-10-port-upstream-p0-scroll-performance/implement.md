# P0 滚动性能执行计划

## Ordered Checklist

1. 读取 Flutter/project spec，记录当前 git 状态并确认无 tracked 用户改动。
2. 实现详情页 detail watch 下沉：
   - 新增当前合并 detail 的只读 helper。
   - 主从切换改为执行时读取。
   - Scaffold 正文与 AI 页分别建立局部 Consumer。
   - 保留 preview detail、树形预取、搜索和 overlay 数据流。
3. 运行 preview/跳楼/滚动性能相关测试和 changed-file analyze；独立提交。
4. 给 legacy 正文三个 emoji raster 路径增加 `RepaintBoundary`；补/运行定向
   widget 测试和 analyze；独立提交。
5. 实现 TopicChannel 微任务 batching、generation、详情页批量消费、滚停批量回放、
   积压坍缩、presence 防抖与大 JSON isolate decode。
6. 运行 MessageBus/provider、preview 与详情页定向测试和 analyze；独立提交。
7. 实现进度浮层 `RepaintBoundary` 与 `AutoScrollTag` 直通 builder；运行 overlay、
   post-list identity 测试和 analyze；独立提交。
8. 运行更广的 `flutter analyze lib test` 或项目允许的可靠替代，以及所有本次相关
   测试；检查无 debug 残留、无格式问题。
9. 逐提交检查 `git show --stat` 和最终 `git status`，确保未跟踪用户文件未进入提交。

## Validation Commands

- `dart format --output=none --set-exit-if-changed <changed dart files>`
- `flutter analyze <changed dart files and related tests>`
- `flutter test test/pages/topic_detail_page/topic_detail_page_preview_test.dart`
- `flutter test test/pages/topic_detail_page/topic_detail_page_jump_target_test.dart`
- `flutter test test/pages/topic_detail_page/topic_detail_scroll_perf_test.dart`
- `flutter test test/pages/topic_detail_page/widgets/topic_detail_overlay_test.dart`
- `flutter test test/pages/topic_detail_page/widgets/topic_post_list_identity_test.dart`
- 新增的 MessageBus/emoji 定向测试（若适用）

## Rollback Points

- Commit 1：详情页 rebuild 边界。
- Commit 2：legacy emoji 重绘隔离。
- Commit 3：MessageBus batching、presence 与大包解析。
- Commit 4：低风险 overlay/tag 包装优化。

任何一组出现行为回归时只回滚对应 commit；禁止用整分支 reset 覆盖用户工作区。
