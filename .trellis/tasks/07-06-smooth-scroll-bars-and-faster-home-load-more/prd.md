# 优化滚动导航栏动画和首页加载更多速度

## Goal

修复开启“滚动收起导航栏”后首页和帖子详情页顶栏/底栏瞬间消失、瞬间出现的问题，并让首页触底加载更多更早触发、加载提示更快，提升连续阅读手感。

## Requirements

* 首页顶部折叠区域和底部导航栏在移动端收起/出现时应有舒缓过渡，不再 0/1 瞬移。
* 帖子详情页移动端浮动顶栏收起/出现时使用轻量过渡动画，保持桌面现有行为。
* 动画必须使用 transform/opacity 这类合成层友好的方式，不引入滚动帧级 provider 写入或布局抖动。
* 首页列表接近底部时更早触发 `loadMore()`，减少用户看到加载条后等待的时间。
* 移动端线性加载条动画节奏加快，但不改变加载状态语义和失败重试逻辑。
* 保持“关闭滚动收起导航栏”时的复位行为不变。

## Acceptance Criteria

* [ ] 首页移动端顶栏和底栏切换可见性时有平滑动画。
* [ ] 帖子详情页移动端顶栏切换可见性时有平滑动画。
* [ ] 首页加载更多在距离底部更早的位置触发，且不会重复并发加载。
* [ ] 相关 widget/unit 测试通过。
* [ ] `flutter analyze` 通过相关变更文件。
* [ ] 上一个树形评论排序修复和本次修复分别提交，并一起推送到 GitHub。

## Definition of Done

* 使用现有 Flutter/Riverpod 结构，不引入新依赖。
* 增加或更新定向测试覆盖加载更多阈值/加载条速度等可测试行为。
* 运行定向测试与 analyze。
* 判断是否需要补充 spec。

## Out of Scope

* 不重写首页列表分页 API。
* 不增加多个并发 load-more 请求。
* 不改变用户设置项名称或默认值。
* 不改变帖子详情页平铺/树形评论加载逻辑。

## Technical Notes

* 首页移动端 header 当前会把 `searchProgress/sortProgress/barVisibility` 量化为 0/1，UI 端缺少动画导致跳变。
* 底部导航栏当前完全跟随 `barVisibilityProvider` 的 0/1 变化，需要在 UI 端平滑补间。
* 帖子详情页移动端 `_buildFloatingTopicChrome` 使用普通 `Transform.translate + Opacity`，桌面才使用 `AnimatedSlide + AnimatedOpacity`。
* 首页 `loadMore()` 触发阈值目前是 `maxScrollExtent - 200`，可以提前到一个响应式阈值，但仍由 provider 的 loading guard 防重复。
