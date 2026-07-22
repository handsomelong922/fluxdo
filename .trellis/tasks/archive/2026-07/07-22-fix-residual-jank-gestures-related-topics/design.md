# Technical Design

## Boundaries

- 性能修复限制在首页列表回顶定位机制，不修改话题 provider 的分页/保留策略。
- 手势修复限制在通用 pop route 与详情页既有 selection blocker；后代滚动控件无需了解 route。
- 相关帖子沿现有 topic detail JSON 数据链路扩展：JSON -> model/service -> provider state -> 主帖 footer widget -> unified topic route。

## Performance Design

普通 `ScrollPosition.jumpTo` 对变高懒列表不是常数成本：大跨度跳转会通过 sliver dead reckoning 物化中间 child。远距离回顶应暂时使用一个只包含当前可见窗口和顶部锚点的定位层，或通过列表本身支持的 index/key 定位能力直接重建到 index 0；完成定位后恢复正常列表并执行短距离动画。实现必须让布局数量由可见窗口上界决定，而不是由列表总长度决定。

回顶入口继续集中到一个 helper，并保留近距离动画。测试用可注入/可观察的定位策略证明远距离分支不会调用跨越中间 extent 的普通 jump。

## Gesture Design

用参与 Flutter gesture arena 的水平 drag recognizer 取代原始 pointer `Listener` 的主动判定。route recognizer 与后代 `Scrollable`、selection recognizer 同场竞争：

- 后代水平控件可滚动时由后代获胜，route 不启动动画。
- 普通内容没有竞争 recognizer 时 route 接受向右拖动并执行交互返回。
- 向左拖动由 route recognizer 拒绝，继续交给详情页 `PageView` AI 入口。
- selection blocker 在 pointer down 和拖动过程中均可拒绝/取消 route，覆盖已有选择及选择刚刚激活的竞态。

route 只在 recognizer 真正赢得 arena 后创建 `_HorizontalPopGestureController`，避免页面在竞争结果确定前发生位移。

## Related Topics Data Flow

论坛详情分页响应在到达末页时携带顶层 `related_topics`。数据层解析为现有 `Topic`（若字段兼容）或最小相关主题模型，并在同一详情状态中保留。展示层执行稳定纯函数：过滤当前 topic/无效项 -> 按 `TimeUtils.parseUtcTime(createdAt)` 降序 -> 取前 5 条。

新增组件放在首帖 footer 的 `PostLinks` 之后，仅首帖渲染。组件默认展开，复用现有相关链接的间距、分隔和标题行语法，但列表只展示可点击标题。详情分页后续响应若携带该字段，应合并到最新 detail 而不能被缺字段的页覆盖为空。

## Compatibility And Failure Handling

- 旧服务器不返回 `related_topics`：模型使用空列表，不显示区域。
- 字段部分缺失：跳过无法导航或无标题的条目；时间缺失的条目排在有效时间之后。
- 相关区渲染或点击不新增网络请求；使用详情响应已有数据。
- 手势 recognizer 继续遵循 RTL/现有返回方向约定，不改变 desktop 鼠标按钮语义。

## Rollback

三个子任务独立提交，可分别回滚。相关字段解析保持向后兼容；UI commit 回滚不会影响服务请求。手势 commit 回滚恢复旧 route recognizer。性能 commit 回滚恢复现有 staging helper。
