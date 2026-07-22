# Technical Design

沿现有详情分页响应解析 `related_topics`，优先复用 `Topic` 字段 contract。详情状态合并时采用“新响应有字段才替换”的策略。UI 通过纯函数过滤、`TimeUtils` 排序、截取 5 条，并在首帖 footer 的 `PostLinks` 后渲染默认展开标题列表。导航统一调用 `buildTopicDetailRoute(...)`。
