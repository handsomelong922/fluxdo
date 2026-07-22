# Technical Design

## Failure Boundary

上一轮把 `related_topics` 的每个条目直接交给通用 `Topic.fromJson`。通用列表模型对主话题 `id` 等必填字段采用严格强转，但外部 `related_topics` 是附加数据，单条缺失/空值不应给整个详情加载扩大成致命错误。

## Parsing Contract

- 为 `related_topics` 建立一个共享、可容错的解析边界，同时由 `TopicDetail.fromJson` 和 `DiscourseService.getRelatedTopics` 复用。
- 顶层字段缺失时，`TopicDetail.relatedTopics == null`，以保留“末页后尚可补取”语义。
- 顶层字段存在但不是可解析列表，或列表中没有有效条目时，返回空列表，不重复补取且不展示 UI。
- 条目必须有可用的正整数 `id` 和非空 `title`；不满足时忽略该条，不抛出异常。
- 其他可选数值字段按现有 `Topic.fromJson` 默认值处理，不放宽普通话题列表本身的核心数据契约。
- 任何解析路径只读取 `related_topics`，不回退到 `suggested_topics`。

## Entry Coverage

所有入口最终都使用 `TopicDetailPage`/`topicDetailProvider`，差异只在初始预览种子与跳转楼层。本次不在各页面重复添加相关帖子 UI，而是保证共享详情数据流覆盖：

| 入口 | 初始数据形态 | 验证重点 |
| --- | --- | --- |
| 首页点击 | `Topic` + 可选首帖 HTML | 预览种子不阻断后台完整详情，真实相关数据后续显示 |
| 首页预览 | `/t/{id}/1.json` | 响应含异常相关条目时预览仍加载，“查看详情”正常交接 |
| 搜索 | 命中楼层 + 可选预览 | 指定楼层不影响共享详情相关区 |
| 我的收藏 | 收藏楼层/话题 + 可选预览 | 保留收藏跳转目标且显示相关区 |
| 浏览历史 | 最后阅读楼层 | 保留阅读位置且显示相关区 |

## Failure Isolation

- 详情首次响应中的无效相关条目在模型边界被过滤。
- 长帖到达末页后的独立相关请求继续采用 best-effort；失败不修改已加载帖子状态。
- UI 只接收已正规化的 `List<Topic>`，不承担 JSON 容错。

## Rollback

解析修复与入口测试保持独立提交边界。若修复引入新回归，可回退代码提交而保留规范中的入口覆盖约束。
