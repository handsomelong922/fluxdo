# Technical Design

## 1. Related Topics Data Flow

1. `TopicDetail` 增加 `highestPostNumber`，从 `highest_post_number` 容错解析，缺失时回退 `posts_count`；`copyWith` 和首页预览快照完整传递该字段。
2. 新增小型 `TopicRelatedTopicsLoader`：
   - key 为 viewer/topic/highestPostNumber；
   - 复用 in-flight Future；
   - 成功结果写入有上限的短 TTL LRU 缓存，包含空列表；
   - 失败不缓存；
   - loader 本身不重试、不轮询。
3. `TopicDetailNotifier.build()` 返回正文详情前只安排一个延迟任务，不 await。延迟到期后重新读取最新 state；仅在普通、非筛选详情且 `relatedTopics == null` 时调用 loader。
4. 到达回复末页时保留一次后备调用，使用相同 loader，因此会命中缓存或复用正在进行的请求。
5. 服务层继续请求 `/t/{topicId}/{highestPostNumber}.json` 并只解析 `related_topics`。该可选请求标记为低优先级/静默，并禁用通用快速重试与 401 自愈重试，避免一个装饰性请求扩散成多次访问；请求调度器仍负责全局限速。
6. UI 沿用现有 `RelatedTopics`，因此所有进入共享 `TopicDetailPage` 的入口自动获得一致行为。

## 2. Topic Entry Latency

首页移动端 push 详情前先从 `HomeTopicExcerptPauseController` 获取独立 token。route Future 结束时在 `finally` 中释放。详情页自己的 token 在可见期继续持有暂停状态，二者通过 Set 计数不会互相提前解除。

暂停只阻止 excerpt loader 启动队列中的低优先级请求，不取消 active 请求，避免破坏缓存或请求生命周期。

## 3. Boost Rendering

- Boost sheet 初始状态由平台决定：mobile=false、desktop=true。
- 条件 widget 保证 `_showEmojiPanel == false` 时 EmojiPicker 完全不在树中。
- EmojiPicker 的 cacheExtent 通过纯函数按平台返回 160/480，便于单测。
- Boost 头像 URL 使用 `resolveTemplate` 后再显式 `resolveStaticAvatarUrl`；这只影响 Boost 高密度场景。
- 删除 BoostBubble 外层 `ValueListenableBuilder`，由静态 URL + `SmartAvatar` 自身生命周期完成渲染。

## 4. Home Pagination Recovery

- 成功响应后立即把 `_page` 设为 requested nextPage；可见列表是否增加只影响 state items，不影响远端游标已经前进的事实。
- 失败状态记录 `retryAfter` 与 `requiresManualRetry`：
  - timeout/connection/可重试 5xx：设置短冷却；新的滚底调用在冷却过期后清门禁并尝试一次；
  - 401/403/419/429、CF 异常、其他确定性响应：保持手动门禁；
  - 不创建 Timer，不在后台自行发请求。
- 手动 retry 清除两类门禁并立即调用 `loadMore()`。

## 5. Compatibility And Risk Controls

- 相关数据缺失继续以 `null` 表示“未请求/响应未携带”，空列表表示服务端明确无数据。
- 新增模型字段提供构造器回退，避免大量现有测试和调用方必须显式传参。
- cache 有 entry 上限与 TTL，避免长期浏览导致内存无限增长。
- 后台相关请求失败保持现有正文 state，不显示全局 error。
- 首页错误分类只改变下一次滚底是否可尝试，不改变 Dio 全局认证或限流策略。

## 6. Rollback Shape

- 相关功能可独立回滚 loader、provider 调度和模型字段提交。
- Boost 改动只涉及输入 sheet、EmojiPicker 和 BoostBubble，可独立回滚。
- 首页分页恢复只涉及 `TopicListNotifier` 及其测试，可独立回滚。

## 7. Break-Loop Analysis

### 1. Root Cause Category

- **B - Cross-Layer Contract**：`related_topics` 是可选附加字段，却曾通过严格模型解析和详情主 Future 传播错误；UI、provider、service 对“缺失 / 明确为空 / 已知数据”的语义没有统一。
- **D - Test Coverage Gap**：旧测试验证了列表能显示，却没有验证“初始 build 不导航”、坏行不破坏正文、所有共享入口都走同一详情路径。
- **E - Implicit Assumption**：首页分页默认“没有新增可见行等于远端页没有成功”，Boost 默认“面板隐藏或头像很小就成本低”，两者都与实际运行时行为不符。

### 2. Why Earlier Fixes Failed

1. 只在评论加载到末尾补取相关字段，范围不完整：短帖初始即在末页、用户不滚到底部、预览缓存刷新等路径都可能永远不触发。
2. 把 `related_topics` 直接交给通用 `Topic.fromJson` 严格解析，导致一条 `{id: null}` 的附加数据把整个帖子详情变成 `_TypeError`。
3. 只降低动态图本身的局部成本，没有移除移动端首次挂载的整个 EmojiPicker，也没有消除每个 Boost 头像的重复偏好监听。
4. 分页失败只增加重试或提示，没有修复成功空页仍停留在同一远端游标的根因。

### 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
| --- | --- | --- | --- |
| P0 | Architecture | 可选相关字段独立容错解析、延迟补取、错误与正文隔离 | DONE |
| P0 | Tests | 验证坏行不致命、正文先返回、初始标题不导航、点击才导航 | DONE |
| P0 | State contract | 成功响应无条件推进 requested page，失败按可恢复性分流 | DONE |
| P1 | Resource budget | Boost 静态头像、移动端 EmojiPicker 按需挂载、限制 cacheExtent | DONE |
| P1 | Documentation | 更新 related、分页恢复、高密度媒体的可执行 spec | DONE |

### 4. Systematic Expansion

- **Similar Issues**：所有预览到完整详情的 optional footer 字段都必须使用 preserve-known-on-omission 合并；所有过滤分页都必须区分远端游标与可见列表长度。
- **Design Improvement**：跨入口功能只放在共享 `TopicDetailPage`/provider 路径；低价值附加请求使用统一缓存和请求治理，不进入主加载错误边界。
- **Process Improvement**：详情功能测试必须覆盖首页 tap、预览 handoff、搜索、收藏、历史的共享路径，并加入“不发生副作用”的负向断言。

### 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/network-and-time.md` 的网页端相关帖子合同。
- [x] 更新 `.trellis/spec/core/flutter-app.md` 的分页游标恢复合同。
- [x] 更新 `.trellis/spec/core/flutter-app.md` 的高密度头像/重型面板资源合同。
