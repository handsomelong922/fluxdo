# 技术设计

## 回顶策略

增加可测试的 staging offset 计算。阈值和 staging 距离均以 viewport 为单位：当当前位置超过两个 viewport 时，先 `jumpTo(2 * viewport)`，随后沿用现有 320ms `animateTo(0)`；否则直接动画。

瞬移只布局目标附近的可见 children，不会逐项构建当前位置和顶部之间的所有变高卡片。最终短动画仍保留用户熟悉的回顶反馈。

## 入口统一

页面级 `_scrollCurrentHomeListToTop` 和列表级 `_scrollActiveTopicListToTop` 调用同一 helper。保留 `hasClients` 与单 position 检查，防止 NestedScrollView 多 position 异常。

## 风险与回滚

- `jumpTo` 可能发出一次不连续 scroll notification，但现有交互本来就是显式回顶；最终 offset 与事件语义不变。
- 不触碰 provider 列表内容和 PageStorage，因此回滚只涉及 helper 与两个调用点。
