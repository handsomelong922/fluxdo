# 实施计划

1. 为树形详情主帖补回归测试：异步注入相关帖子后显示标题，初始不导航，点击后才导航。
2. 在 `NestedPostCard` 向 `PostFooterSection` 传播 `TopicDetail.relatedTopics`，复验平面与树形路径。
3. 为移动端帖子头像补回归测试，覆盖 `animatedAvatar + avatarTemplate`、缺少模板和桌面端行为。
4. 修改 `PostAvatar` 的移动端 URL 选择，只使用可靠的静态模板，不改动桌面端全局偏好语义。
5. 运行相关帖子、详情入口、头像、Boost、首页分页恢复的定向测试。
6. 运行 `flutter analyze --no-pub`、`flutter test --no-pub`、`git diff --check`。
7. 执行 break-loop 分析并把入口传播/测试约束补入现有 Flutter spec；只暂存本任务文件。
8. 分别提交相关帖子可见性、移动端头像性能及规范记录，检查提交列表后统一推送当前分支。

## 风险文件与回滚点

- `lib/widgets/nested/nested_post_card.dart`：只增加字段传播，避免改动树形布局。
- `lib/widgets/post/post_item/widgets/post_header.dart`：只调整移动端 URL 选择，保留点击头像、Flair、边框和桌面逻辑。
- 新测试必须验证无自动导航和无额外请求，防止再次出现“展示链接”被误解为“打开内容”。
