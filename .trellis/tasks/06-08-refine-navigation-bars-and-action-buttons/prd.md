# 优化导航栏和关键按钮质感

## Goal

在不牺牲帖子列表与帖子正文内容完整性、不降低性能、不引入新交互风险的前提下，提升首页顶栏/底栏、发布话题按钮、帖子详情回复按钮和相关工具图标的视觉精致度，使整体更接近 iOS 风格的轻盈毛玻璃与高质感控制层。

## What I Already Know

* 用户希望整体更精致、美观，有类似 iPhone 软件的毛玻璃质感。
* 用户明确要求不能为了美观影响内容呈现，不能牺牲性能，不能引入 bug。
* 首页移动端底部导航已使用小面积 `BackdropFilter`，但内部仍是标准 `NavigationBar`，选中态和图标质感较朴素。
* 主页发布按钮在 `lib/pages/topics_screen.dart`，当前是普通 `FloatingActionButton`，并带刷新/发布模式切换和 speed dial。
* 帖子详情底部工具条在 `lib/pages/topic_detail_page/widgets/topic_bottom_bar.dart`，已有小面积毛玻璃容器。
* 帖子详情回复按钮在 `lib/pages/topic_detail_page/widgets/topic_detail_overlay.dart`，当前是默认 `FloatingActionButton`。
* 详情页顶部浮动返回和菜单按钮在 `lib/pages/topic_detail_page/topic_detail_page.dart`，已有 `_FloatingTopicChromeButtonSurface` 毛玻璃样式。
* 项目 spec 要求滚动联动动画保持 viewport 稳定，优先使用 transform/opacity，不改变布局尺寸。

## Research References

* [`research/ios-glass-ui-guidance.md`](research/ios-glass-ui-guidance.md) — Apple HIG / Liquid Glass 设计要点与本项目映射。

## Requirements

* 首页移动端底部导航栏保持浮动毛玻璃形态，但图标间距、选中态、背景材质、边框和阴影更精致。
* 底部导航不得增加遮挡内容的高度；现有 show/hide 动画仍必须通过 paint-level transform/opacity 实现。
* 首页发布话题 FAB 和刷新模式 FAB 需要更精致，支持现有发布/草稿 speed dial 与刷新逻辑，不改业务行为。
* 帖子详情右下角回复 FAB 需要与首页主按钮形成统一视觉语言，同时保持原有位置、动效和可点击面积。
* 帖子详情底部工具条图标按钮需要统一成更精致的玻璃工具按钮风格，激活态清楚但不喧宾夺主。
* 帖子详情顶部浮动返回/菜单按钮应与底部工具条和主按钮风格一致。
* 仅在小面积控制层使用 blur，不对大面积列表、正文、WebView、视频或滚动内容使用 blur。
* 不新增第三方依赖，不改变导航业务逻辑、登录逻辑、发帖/回复逻辑或列表数据逻辑。
* 兼容浅色/深色主题，保持无障碍 tooltip/语义标签。

## Acceptance Criteria

* [ ] 首页底部导航、侧栏/底栏图标选中态、发布 FAB 看起来更统一、更精致。
* [ ] 帖子详情顶部浮动按钮、底部工具条和回复 FAB 使用统一的高质感控制层语言。
* [ ] 内容区域可视高度不被新增固定控件压缩；列表和帖子正文布局不出现额外大面积遮挡。
* [ ] 滚动时底栏与回复按钮仍按原逻辑显示/隐藏，且不改变 scroll viewport。
* [ ] 发布话题、草稿菜单、刷新模式、回复按钮点击行为不变。
* [ ] 触达 Dart 文件 `dart analyze` 通过。
* [ ] 相关 widget/unit 测试通过；如全量检查受既有无关问题影响，必须明确说明。
* [ ] 提交代码，且不混入无关历史未跟踪文件。

## Definition of Done

* 代码实现完成并格式化。
* 定向 analyzer 和相关测试通过。
* 视觉 smoke 检查至少覆盖首页移动尺寸与帖子详情移动尺寸。
* 判断是否需要更新 `.trellis/spec/`；如产生可复用 UI 约束则记录。
* 提交本次任务相关代码、测试和 Trellis task 文件。

## Technical Approach

* 在 `adaptive_navigation.dart` 和 `adaptive_scaffold.dart` 中调整移动底部导航的玻璃容器与 item 选中态，优先小面积、低成本绘制。
* 在 `topics_screen.dart` 中抽取或局部实现玻璃主 FAB / speed dial item 样式，保留原 callback 和 heroTag。
* 在 `topic_detail_overlay.dart` 中替换默认回复 FAB 为统一的玻璃主按钮组件。
* 在 `topic_bottom_bar.dart` 中统一工具按钮尺寸、圆角、激活态、hover/press 材质，保留现有菜单和 bookmark 长按语义。
* 在 `topic_detail_page.dart` 中微调顶部浮动 chrome button，与新控制层视觉保持一致。
* 若发现重复按钮样式超过 2 处，抽到 `lib/widgets/common/` 中作为小型可复用组件；否则避免过度抽象。

## Decision (ADR-lite)

**Context**: 现有控件已有部分毛玻璃基础，但关键按钮和图标仍偏默认 Material，视觉语言不一致。用户重视内容完整性和性能。

**Decision**: 使用“小面积玻璃控制层 + 精细图标容器 + 统一主按钮”方案，不做内容层玻璃、不增加依赖、不改变页面布局 contract。

**Consequences**: 视觉提升集中在导航和操作控件；内容区域保持稳定。需要通过移动尺寸视觉 smoke 与 targeted tests 确认控件不遮挡主要内容。

## Out of Scope

* 不重设计帖子卡片、正文卡片或内容排版。
* 不改主题系统或增加全局新主题。
* 不引入 iOS-only 依赖或平台特化组件。
* 不改业务数据、网络、登录、发帖/回复流程。

## Technical Notes

* 关键文件候选：`lib/widgets/layout/adaptive_scaffold.dart`、`lib/widgets/layout/adaptive_navigation.dart`、`lib/pages/topics_screen.dart`、`lib/pages/topic_detail_page/widgets/topic_detail_overlay.dart`、`lib/pages/topic_detail_page/widgets/topic_bottom_bar.dart`、`lib/pages/topic_detail_page/topic_detail_page.dart`。
* 相关测试候选：`test/widgets/layout/adaptive_navigation_test.dart`、`test/widgets/layout/master_detail_layout_test.dart`、`test/pages/topic_detail_page/widgets/topic_detail_overlay_test.dart`、可新增小型 widget tests。
