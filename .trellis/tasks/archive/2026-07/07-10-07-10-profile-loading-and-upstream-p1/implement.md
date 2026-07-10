# 用户主页与 P1 性能移植执行计划

## Ordered Checklist

1. 读取 core Flutter/network/cross-layer/code-reuse 规范，确认 tracked 工作区无用户改动。
2. 实现用户主页请求并行、专用非阻塞 GET 选项和固定统计区；补请求策略与布局测试，
   运行定向 analyze/test，独立提交。
3. 实现正文/网格 decode cap、正文图 scroll-aware 挂载、比例记忆、全局滚动信号与
   AVIF 动画冻结；更新 LazyImage/信号测试，运行定向验证，独立提交。
4. 实现 TopicPostList 双侧首次/分页渐进物化和 generation 预热；扩展 preview、identity、
   跳楼/分页相关测试，独立提交。
5. 实现 Android CF WebView 安全 pause/resume ticker；补纯状态判定测试并运行网络/
   WebView 相关分析，独立提交。
6. 运行 `dart format`、`flutter analyze lib test` 和相关测试组；复查首页详细展示、
   preview 合并、评论渐进加载、树形/搜索/MessageBus 不受影响。
7. 判断并写入跨层 spec；按独立改动创建测试/规范/任务提交，不 squash。
8. 检查 `git log origin..HEAD`、每个 `git show --stat`、`git diff --check` 和工作区；
   推送当前分支全部未推送提交到 origin。
9. 归档 Trellis 任务并记录 session journal；如归档/journal 产生 tracked 变更，再独立
   提交并补推送，确保远端与本地 HEAD 一致。

## Validation Commands

- `dart format --output=none --set-exit-if-changed <changed dart files>`
- `flutter analyze <changed files and related tests>`
- `flutter test test/services/discourse/request_session_sync_policy_test.dart`
- `flutter test test/services/discourse/user_profile_request_options_test.dart`
- `flutter test test/widgets/user/user_profile_stats_area_test.dart`
- `flutter test test/widgets/content/lazy_image_test.dart`
- `flutter test test/utils/scroll_busy_signal_test.dart`
- `flutter test test/pages/topic_detail_page/topic_detail_page_preview_test.dart`
- `flutter test test/pages/topic_detail_page/topic_detail_page_jump_target_test.dart`
- `flutter test test/pages/topic_detail_page/widgets/topic_post_list_identity_test.dart`
- `flutter test test/pages/topic_detail_page/topic_detail_scroll_perf_test.dart`
- `flutter analyze lib test`
- `git diff --check`

## Rollback Points

- Commit A：用户主页加载与统计区固定。
- Commit B：图片 decode/AVIF 滚动策略。
- Commit C：帖子列表渐进物化与预热。
- Commit D：CF WebView 滚动挂起。
- Commit E：回归测试与跨层规范（如不能与对应行为提交同放）。

任何一类出现回归只 revert 对应 commit；禁止 reset 或覆盖用户未跟踪现场。
