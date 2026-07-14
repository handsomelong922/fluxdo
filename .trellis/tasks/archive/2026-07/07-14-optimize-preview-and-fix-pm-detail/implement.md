# 实施计划

1. 修改共享预览弹窗的尺寸约束、动画和统一边框，更新 widget tests。
2. 定向 analyze/test，通过后只暂存预览相关代码与测试，形成第一个提交。
3. 在共享搜索预览入口推入弹窗前清除 focus scope 历史，添加打开/关闭焦点回归测试，形成第二个提交。
4. 修改详情页树形视图判定，确保私信强制平铺并延后普通话题树形 provider watch，添加纯逻辑回归测试。
5. 定向 analyze/test，通过后只暂存私信修复相关代码与测试，形成第三个提交。
6. 运行扩大回归、全量 `flutter analyze` 与 `tool/merge_l10n.dart --check`。
7. 归档 Trellis 任务、记录 journal，检查提交列表后一次性 push 当前分支。

## 风险文件

- `lib/widgets/topic/topic_preview_dialog.dart`：复杂 HTML 在 loose flex 中的滚动约束必须验证无 overflow。
- `lib/pages/topic_detail_page/topic_detail_page.dart`：树形 provider watch 与实际渲染判定必须使用同一条件。

## 验证命令

- `flutter test test/widgets/topic/topic_preview_dialog_test.dart`
- `flutter test test/pages/topic_detail_page/topic_detail_page_preview_test.dart`
- `flutter analyze`
- `dart run tool/merge_l10n.dart --check`
