# Bug Analysis: malformed related topic blocked all home detail flows

## 1. Root Cause Category

- **Category**: B/D/E - Cross-Layer Contract, Test Coverage Gap, Implicit Assumption
- **Specific Cause**: `related_topics` 是非关键的外部附加列表，但上一轮把每条数据直接交给对 `id` 严格强转的通用 `Topic.fromJson`。测试夹具只包含理想数据，默认官方列表每条都有非空整数 `id`，没有覆盖真实 `{ "id": null }` 形状。

## 2. Why The Previous Fix Failed

1. 上一轮模型测试只覆盖“字段缺失/空列表/完整条目”，没有覆盖“列表存在但单条损坏”。
2. Service 夹具复制了干净的理想响应，因此同一个严格 `.map(Topic.fromJson)` 在 model 和 service 两层都被错误地证明为“可用”。
3. 完整测试数量很多，但没有一个用例组合 `/t/{id}/1.json` 首帖预取和损坏的 `related_topics`，所以首页/预览特有回归没有被发现。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
| --- | --- | --- | --- |
| P0 | Architecture | 使用共享 `parseRelatedTopics(...)` 逐条校验并隔离坏数据 | DONE |
| P0 | Test Coverage | 增加 `{ "id": null }`、缺失 id、空标题、非 map 和非列表夹具 | DONE |
| P0 | Integration | 用 `/t/{id}/1.json` 首帖预览 service 测试证明主帖不受相关坏数据影响 | DONE |
| P1 | Documentation | 在 network 规范中写入外部附加列表的逐条容错契约 | DONE |
| P1 | Process | 在 Flutter 规范中写入首页/预览/搜索/收藏/历史入口矩阵 | DONE |

## 4. Systematic Expansion

- **Similar Issues**: 任何从详情响应携带的非关键列表，若直接复用主列表严格 parser，都可能把局部数据质量问题扩大成整页失败。
- **Design Improvement**: 非关键附加数据应在 model/service 共享边界完成正规化，UI 只消费已验证类型。
- **Process Improvement**: 详情页共享行为改动必须在验证计划中显式列出全部入口，不再以“共用路由”作为未验证的假设。

## 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/network-and-time.md`。
- [x] 更新 `.trellis/spec/core/flutter-app.md`。
- [x] 将精确失败形状写入模型和 service 回归测试。
- [x] 项目不存在 spec template 同步目录，无需额外同步。
