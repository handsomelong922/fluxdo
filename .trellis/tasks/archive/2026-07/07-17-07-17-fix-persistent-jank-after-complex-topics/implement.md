# 实施计划

1. 读取 Flutter/项目规范并复核图片 provider、详情缓存和预览 seed 的现有契约。
2. 先补图片查看器原图 provider 生命周期测试，再实现稳定复用与异步逐项释放。
3. 先补详情缓存内容规模和总预算测试，再实现估算、单条上限与 LRU 总预算。
4. 复核首页详细展示、预览 seed、目标楼层、评论渐进加载和图片查看器调用点，确认无行为删减。
5. 运行定向测试：
   - `flutter test --no-pub test/pages/image_viewer_page_test.dart`
   - `flutter test --no-pub test/services/topic_detail_cache_service_test.dart`
   - `flutter test --no-pub test/widgets/topic/topic_preview_dialog_test.dart`
   - `flutter test --no-pub test/pages/topic_detail_page/topic_detail_page_preview_test.dart test/pages/topic_detail_page/topic_detail_page_jump_target_test.dart test/pages/topic_detail_page/topic_detail_scroll_perf_test.dart`
6. 运行 `flutter test --no-pub`、`flutter analyze --no-pub`、`git diff --check`。
7. 按根因分别提交代码，再提交 spec/task/journal，最终一次性推送当前分支。

## 风险文件与回滚点

- `lib/pages/image_viewer_page.dart`：只修改 provider 创建/销毁，不改 UI 树和手势配置；可独立回滚。
- `lib/services/topic_detail_cache_service.dart`、`lib/providers/topic_detail_provider.dart`：只修改运行期缓存准入和淘汰，不改当前页面 state；可独立回滚。
- `test/pages/image_viewer_page_test.dart`、`test/services/topic_detail_cache_service_test.dart`：回归契约。

## 开始实现前复核

- 用户已明确授权修复、验证、拆分提交和推送。
- 当前分支与远端同步；大量既有未跟踪文件必须继续隔离。
- 不需要新增依赖或修改 pubspec。
