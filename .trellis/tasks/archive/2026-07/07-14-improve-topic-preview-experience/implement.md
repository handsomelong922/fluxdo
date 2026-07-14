# 实施计划：话题预览触发与窗口体验

## 实施顺序

- [x] 增加 `TopicPreviewTrigger` 偏好、旧 key 迁移、setter、设置页单选器和四语种本地化。
- [x] 为普通/置顶 `TopicCard` 增加右侧全高透明预览热区，并在 `buildTopicItem` 统一按偏好绑定两种触发。
- [x] 为搜索卡片接入同一热区和共用预览弹窗，保留普通点击命中楼层导航。
- [x] 将 `TopicPreviewDialog` 改成固定 85% safe viewport 高度、快速无模糊动画、紧凑标题/顶部、单行小标签、完整 HTML 正文、无参与者行。
- [x] 重构底栏：移除关闭/分享，四项统计分布在居中“查看详情”两侧，并降低高度。
- [x] 预览加载保留 `TopicDetail`，查看详情前写入 `TopicDetailCacheService` preview seed。
- [x] 增加偏好迁移、卡片热区手势、搜索统一转换/预览交接和缓存复用测试。
- [x] 运行格式化、生成本地化、定向 analyze/test，再按变更风险扩展检查。

## 预期验证命令

```powershell
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\dart.bat format <changed-dart-files>
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat gen-l10n
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat analyze <changed-paths>
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat test test/providers/preferences_provider_test.dart test/widgets/topic/topic_card_test.dart test/widgets/search/search_post_card_test.dart test/services/topic_detail_cache_service_test.dart test/pages/topic_detail_page/topic_detail_page_preview_test.dart
```

## 风险文件与检查点

- `lib/providers/preferences_provider.dart`：构造函数/copyWith 字段较多，必须由 analyze 和偏好持久化测试覆盖。
- `lib/widgets/topic/topic_card.dart`：手势叠层可能造成点击冲突，必须分别测试热区内外点击。
- `lib/widgets/topic/topic_preview_dialog.dart`：小屏、文字放大和复杂 HTML 可能 overflow，使用弹性统计列、裁剪和滚动正文。
- `lib/pages/search_page.dart`：异步导航与搜索焦点处理保持不变，只替换预览入口。
- `lib/l10n/modules/settings/*.arb`：生成文件必须通过项目既有 `gen-l10n` 流程更新，不能手改生成文件。

## 启动前复核

- [x] 用户目标、触发边界、固定高度、底栏结构和缓存复用均有可测试验收项。
- [x] 首页、书签、浏览历史、搜索的现有入口与详情 preview-seed 数据流已定位。
- [x] 无阻塞产品问题；旧偏好迁移使用 PRD 中的保守映射。
