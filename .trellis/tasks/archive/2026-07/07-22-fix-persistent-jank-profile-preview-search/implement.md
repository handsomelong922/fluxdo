# 实施计划

1. 完成性能子任务：补回顶 staging 纯逻辑测试，统一两个首页回顶入口，运行首页滚动定向测试并提交。
2. 完成用户主页子任务：设置初始“话题”索引和首次加载，补默认选择契约测试并提交。
3. 完成预览子任务：为回复统计增加强调样式，补视觉参数/布局回归测试并提交。
4. 完成搜索子任务：用本地历史替代云端历史加载与清除，补去重、上限、清空和页面无 spinner 测试并提交。
5. 使用 `trellis-check` 做跨任务复核，运行全量 analyze/test 和 diff check。
6. 判断并更新可复用的滚动与搜索本地状态规范；检查是否需要 `trellis-break-loop`。
7. 复核四个独立提交和工作区隔离，归档子任务与父任务。

## 验证命令

- `flutter test --no-pub test/pages/topics_page_header_progress_test.dart`
- 用户主页、预览弹窗和搜索历史新增定向测试
- `flutter test --no-pub test/widgets/topic/topic_preview_dialog_test.dart`
- `flutter analyze --no-pub`
- `flutter test --no-pub --reporter compact`
- `git diff --check`

## 回滚点

- 每个子任务一个独立代码提交。
- 性能 helper 不与 UI/搜索改动共享文件。
- 规范与任务记录不混入应用行为提交。
