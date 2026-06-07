# 修复帖子详情右滑返回与复杂链接跳转

## Goal

修复移动端帖子详情页的两个阅读导航问题：从首页进入帖子后，向右滑动应等同 Android 返回键回到首页；帖子内容中的复杂 Discourse topic 链接应自动规范化为可稳定识别的通用 topic 链接并正确打开对应帖子。

## Requirements

* 在帖子详情页启用 AI 滑动入口时，保留当前向左滑动进入 AI 助手的行为。
* 在帖子详情页处于话题页第 0 页时，用户从屏幕左侧向右滑动应触发 `Navigator.maybePop()`，效果等同返回键。
* 右滑返回不应影响搜索态返回逻辑；搜索态应优先关闭搜索。
* 右滑返回不应在 AI 助手页直接退出帖子；AI 助手页的返回应先回到帖子页。
* 帖子内容里的内部 Discourse topic 链接应支持 `/n/topic/<topicId>`、`/n/<slug>/<topicId>`、`/t/topic/<topicId>`、`/t/<slug>/<topicId>`、`/topic/<topicId>` 等变体。
* 解析复杂 topic 链接时，应忽略 `sort=old`、`u=...` 等不影响目标帖子的 query 参数，并保留明确楼层信息。
* 对 `/n/...` 这类视图模式链接，内容链接点击应提取核心 topicId/postNumber 并按通用 topic 导航打开；解析层可保留 `isNestedRoute` 标记供深链等其它入口使用。
* 同站内部 topic 链接应优先走原生帖子详情页，不应退化为 WebView。

## Acceptance Criteria

* [ ] 在 AI 滑动入口开启时，帖子页左滑仍进入 AI 助手。
* [ ] 在 AI 滑动入口开启且位于帖子页时，从左侧向右滑动会返回上一页。
* [ ] 在 AI 助手页按返回键或系统返回手势先回到帖子页。
* [ ] `https://linux.do/n/topic/388420?sort=old` 可解析为 topicId `388420`，slug 为空，并标记为嵌套视图链接。
* [ ] `https://linux.do/topic/388420` 可解析为 topicId `388420`。
* [ ] 现有 `/t/...`、`/n/<slug>/<id>/context/<post>`、`#post_8` 等测试继续通过。
* [ ] 相关 Dart tests、analyze 通过；若无法完整运行，明确说明原因与影响。

## Definition of Done

* 更新或补充解析与手势相关测试。
* 运行定向测试与静态检查。
* 判断是否需要更新 `.trellis/spec/`。
* 只提交本次任务涉及的代码与 Trellis task 文件，不混入历史未提交文件。

## Technical Approach

* 扩展 `DiscourseUrlParser.parseTopic`，将 `topic` 视作 Discourse 通用占位 slug，并增加 `/topic/<id>` 的解析路径。
* 为可识别 topic 链接提供 canonical path，兜底打开时把复杂链接转成 `/topic/<id>` 或 `/topic/<id>/<post>`。
* 在 AI 滑动模式的帖子详情 `PageView` 外层增加侧边右滑返回手势识别：只在第 0 页、非搜索态、非嵌入模式、移动端触发。
* 优先使用现有工具与导航入口，避免新增依赖。

## Decision (ADR-lite)

**Context**: 当前 `/n/topic/<id>` 被解析器误判为嵌套链接缺少 ID；AI 滑动入口使用 `PageView` 后，水平滑动只承担 0→1 的页面切换，没有 0→返回分支。

**Decision**: 在解析器层做通用 topic 链接规范化与语义识别，在 UI 层为话题页第 0 页增加边缘右滑返回；内容中的复杂链接最终统一映射到 topicId/postNumber 这组内部导航参数。

**Consequences**: 内部链接识别更宽容；所有正文和 onebox 渲染入口都必须传递同一个 `onInternalLinkTap` 回调，否则会退化到 WebView 兜底。

## Out of Scope

* 不改变 AI 助手滑动入口的默认开关或设置项。
* 不改外部浏览器打开策略。
* 不重构整个导航栈或帖子详情架构。

## Technical Notes

* 关键文件：`lib/pages/topic_detail_page/topic_detail_page.dart`、`lib/utils/discourse_url_parser.dart`、`lib/utils/link_launcher.dart`、`lib/utils/topic_link_navigation.dart`。
* 相关测试：`test/utils/discourse_url_parser_test.dart`、`test/utils/link_launcher_test.dart`、可新增帖子详情手势 widget 测试。
* 当前仓库只有 `core/doh_proxy/backend` spec 与通用 thinking guides；本任务主要使用通用代码复用/跨层思考指南。
