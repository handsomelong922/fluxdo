# 修复详情页右滑与内容手势冲突

## Goal

让详情页右滑返回只在普通内容区域生效，不再破坏文字选择、代码横向滚动或其他后代横向交互。

## Requirements

- route 返回必须参与 Flutter gesture arena，不再旁路消费所有原始指针移动。
- 已有文字选择状态继续阻断右滑返回和左滑 AI。
- 后代横向 `Scrollable` 获胜时 route animation 不移动。
- 普通右滑返回、普通左滑 AI、垂直滚动保持现状。

## Acceptance Criteria

- [ ] 已选文字左右扩展均保持选择且页面不 pop。
- [ ] 代码块可向两侧横向查看，右滑不触发返回。
- [ ] 普通内容右滑仍完成交互返回。
- [ ] 左滑 AI PageView 行为不回归。
- [ ] 导航与内容定向测试、analyze 通过。

## Out Of Scope

- 不改变右滑返回的完成阈值、动画视觉和 AI 设置入口。
