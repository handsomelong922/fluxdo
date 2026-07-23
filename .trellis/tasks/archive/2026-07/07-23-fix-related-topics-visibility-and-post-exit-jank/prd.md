# 修复相关帖子未显示与复杂帖子退出后持续掉帧

## Goal

让所有帖子详情入口都能稳定、快速地显示官方“相关”结果，同时降低复杂帖子中大量动态头像持续解码造成的掉帧，避免离开帖子后继续影响浏览体验。

## Confirmed Facts

- 官方详情响应的 `related_topics` 一次提供 5 条相关帖子；它与 `suggested_topics`（推荐）是不同字段。
- 当前数据模型、请求、缓存和普通详情页脚已经支持 `related_topics`，但树形详情的主帖卡片没有把该字段传给页脚，导致默认详情模式不可见。
- 相关请求在正文首屏完成后延迟触发，并有缓存与 in-flight 去重；它不应阻塞正文展示，也不得轮询或自动重试。
- 移动端普通帖子头像仍可能优先选择 `animated_avatar` 的 GIF 原图，绕过只识别 `/user_avatar/` URL 的小头像静态化逻辑。
- 首页分页恢复逻辑已经区分临时网络错误和验证/限流错误；恢复只能由后续用户滚动或手动重试触发。

## Requirements

- 在树形和平面帖子详情中，主帖正文末尾、点赞/回复/更多操作栏上方默认展开“相关帖子”。
- 相关区域最多显示 5 个标题，按创建时间从近到远排序；不展示正文、预览或推荐内容。
- 初次渲染相关标题时不得自动打开任何帖子；仅点击某个标题后才进入对应帖子详情。
- 首页、搜索、收藏、浏览历史、预览弹窗及站内链接等入口必须汇入同一详情页数据与 UI 契约。
- 相关请求不得阻塞正文首屏，不得轮询、后台自动重试、绕过 Cloudflare 或增加脚本式访问频率。
- Android/iOS 的帖子列表与详情头像优先使用静态头像模板，避免大量 GIF 同时播放；桌面端保留现有头像偏好行为。
- 不通过全局清空 Flutter 图片缓存解决掉帧；保留已有按路由清理和缓存预算策略。
- 首页加载更多遇到临时失败时，仅允许后续用户滚动在冷却结束后恢复；验证、权限、限流和 Cloudflare 错误必须等待手动重试。

## Out Of Scope

- 不实现网页端“推荐”功能。
- 不预加载或自动打开 5 个相关帖子的正文。
- 不绕过论坛验证、限流或反自动化机制。
- 不改变桌面端动态头像的现有用户偏好语义。

## Acceptance Criteria

- [ ] 树形详情的主帖在异步收到 `relatedTopics` 后显示“相关帖子”和 5 个标题。
- [ ] 平面详情保持相同行为；有“相关链接”时相关帖子紧随其后，没有时仍占据正文末尾位置。
- [ ] 标题按 `createdAt` 从新到旧排列，超过 5 条时只显示前 5 条。
- [ ] 未点击标题时导航栈不变化；点击标题时通过统一 `TopicDetailPage` 路由进入目标帖子。
- [ ] 初始正文展示不等待相关请求；同一主题的重复详情构建不产生重复并发请求或自动重试。
- [ ] Android/iOS 帖子头像在同时存在 `animatedAvatar` 和 `avatarTemplate` 时使用静态模板 URL。
- [ ] 桌面端及全局“偏好静态头像”设置行为不回归。
- [ ] 首页失败恢复相关现有回归测试通过，且实现中不存在定时/轮询式自动请求。
- [ ] 定向测试、完整 `flutter analyze --no-pub`、完整 `flutter test --no-pub` 和 `git diff --check` 通过。

## Notes

- Keep `prd.md` focused on requirements, constraints, and acceptance criteria.
- Lightweight tasks can remain PRD-only.
- For complex tasks, add `design.md` for technical design and `implement.md` for execution planning before `task.py start`.
