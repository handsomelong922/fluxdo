# Bug Analysis: 相关帖子在默认详情不可见与动态头像策略漏网

## 1. Root Cause Category

- **Category**: C - Change Propagation Failure
- **Specific Cause**: `relatedTopics` 已贯通模型、Provider、平面详情和页脚，但默认树形详情的 `NestedPostCard` 构造 `PostFooterSection` 时漏传字段。
- **Secondary Category**: D - Test Coverage Gap
- **Specific Cause**: 原测试覆盖数据解析、请求、缓存和独立相关列表组件，没有覆盖树形详情的 OP 页脚调用点。
- **Avatar Cause**: E - Implicit Assumption
- **Specific Cause**: 小头像静态化假设 URL 总含 `/user_avatar/`，但 `Post.getAvatarUrl()` 会优先返回 `animated_avatar` 原图；树形头像和 Flair 又有独立渲染路径。

## 2. Why Earlier Fixes Failed

1. 数据层修复：解决了 null 类型崩溃和接口获取，但没有验证用户默认使用的树形渲染路径。
2. 独立组件测试：证明“相关帖子组件能显示”，却没有证明详情页实际把数据传入组件。
3. Boost 静态化：修复了最显眼的 Boost 气泡，但普通帖子头像、树形头像和 Flair 仍可创建动态图 provider。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
| --- | --- | --- | --- |
| P0 | Test Coverage | 增加树形 `NestedPostCard -> PostFooterSection` 传播守卫 | DONE |
| P0 | Architecture | 平面和树形详情继续复用同一个 `PostFooterSection/RelatedTopics` | DONE |
| P0 | Runtime Policy | 移动端平面、树形头像和 Flair 统一拒绝无可靠静态候选的动态图 | DONE |
| P1 | Documentation | 更新 related topics 与高密度头像规范 | DONE |

## 4. Systematic Expansion

- **Similar Issues**: 新增 `TopicDetail` 可选字段时，应检查 `PostItem`、`SegmentedLongPost`、`NestedPostCard` 和预览种子合并路径。
- **Design Improvement**: 详情入口只负责提供 seed/定位参数，最终都由相同详情 Provider 和页脚组件消费数据。
- **Process Improvement**: 可选页脚功能必须同时有数据层测试、独立组件测试和默认详情模式传播测试。

## 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/network-and-time.md`
- [x] 更新 `.trellis/spec/core/flutter-app.md`
- [x] 增加相关帖子树形传播守卫
- [x] 增加移动端头像与 Flair 静态策略测试
