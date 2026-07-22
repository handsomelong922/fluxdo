# 实施计划

1. 在现有首页滚动纯逻辑测试中先覆盖 staging 阈值、clamp 和近距离 no-op。
2. 在 `topics_page.dart` 实现共享回顶 helper，并替换两个直接 `animateTo(0)` 入口。
3. 运行首页滚动、首页摘要、加载更多相关定向测试。
4. 运行 analyze/test/diff check，提交性能修复。

## 回滚点

- 仅 `topics_page.dart` 和对应测试；不改 topic provider 数据。
