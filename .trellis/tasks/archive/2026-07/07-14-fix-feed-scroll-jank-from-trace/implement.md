# 实施计划

1. 读取 Flutter、性能与树形评论相关规范，确认现有可见帖子上报和滚动暂停合同。
2. 提取可测试的树形自动物化判断，覆盖可见、滚动暂停、最大深度、手动展开边界。
3. 在 `NestedPostList` 维护共享可见 post number notifier，并确保 dispose、空集合和 Sliver 回收安全。
4. 在 `NestedPostCard` 分离 expanded 与 materialized 状态；自动路径按视口逐层物化，手动路径立即物化，网络预取只对可见节点运行。
5. 增加树形物化诊断事件和定向测试。
6. 将 `RepaintBoundary` 从递归子树外层收缩到当前帖子主体，补结构回归测试。
7. 运行树形评论、自动展开、加载更多、跳帖、可见帖子、性能诊断和图片相关定向检查。
8. 使用 `trellis-check` 运行全量 analyze/test，复查样式、功能边界和无调试残留。
9. 使用 `trellis-break-loop` 记录“Sliver 根节点内部递归 Column 可绕过虚拟化”的复发机制，并更新 Flutter 性能规范。
10. 按“视口驱动物化”“重绘边界”“规范”分别本地提交；当前请求未授权推送，保留本地提交等待用户后续指示。

## 验证命令

- `flutter analyze --no-pub <changed paths>`
- `flutter test --no-pub test/widgets/post/reply_auto_expand_policy_test.dart`
- 新增/现有 nested post、nested load-more、topic detail、performance diagnostics 定向测试
- `flutter analyze --no-pub`
- `flutter test --no-pub --reporter compact`

## 高风险文件与回滚点

- `lib/pages/topic_detail_page/widgets/nested_post_list.dart`：必须保持可见帖子上报、跳帖 tag 和滚动监听顺序。
- `lib/widgets/nested/nested_post_card.dart`：必须保持手动展开即时性和树线布局。
- `lib/widgets/post/reply_auto_expand_policy.dart`：只增加可测试门禁，不改变通用阈值。
