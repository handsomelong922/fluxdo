# 添加默认展开的相关帖子

## Goal

在详情页主帖底部展示与网页端同源的“相关帖子”，帮助用户继续阅读真正相关的话题。

## Confirmed API Contract

- 网页末页请求：`GET /t/{topicId}/{lastPostNumber}.json`。
- 响应顶层 `related_topics` 为 5 条相关话题，`suggested_topics` 是另一个“推荐”列表。
- 本功能只能消费 `related_topics`。

## Requirements

- 相关区放在主帖 `PostLinks` 下方，仅主帖显示。
- 默认展开，最多 5 条，只列标题。
- 客户端按 `created_at` 降序，最近创建在前。
- 点击标题使用统一 topic detail route。
- 空、缺失、失败时不显示；后续分页缺字段不得覆盖已取得的数据。
- UTC 创建时间通过 `TimeUtils` 解析。

## Acceptance Criteria

- [ ] JSON 正确区分并解析 `related_topics` 与 `suggested_topics`。
- [ ] 相关条目按创建时间降序且最多 5 条。
- [ ] 组件默认展开并位于主帖相关链接下方。
- [ ] 空数据不占位，点击能打开对应详情。
- [ ] 模型/provider/widget 定向测试、l10n 检查与 analyze 通过。

## Out Of Scope

- 不展示“推荐”列表，不实现客户端相关度算法。
