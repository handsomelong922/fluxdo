# 技术设计

## 相关帖子数据流

沿用现有 `TopicDetailProvider -> TopicDetail.relatedTopics -> PostItem/PostFooterSection -> RelatedTopics` 流程，不新增接口或并行请求。修复树形路径中 `NestedPostCard -> PostFooterSection` 的字段传播，使所有入口最终进入同一详情组件后得到一致结果。

`RelatedTopics` 只负责排序、截断、标题渲染和点击导航。异步加载完成前不占用阻塞状态；空结果不显示区域。相关请求继续使用现有延迟调度、缓存和 in-flight 去重，失败保持空区域，不自动重试。

## 头像静态化

在 `PostAvatar` 的平台边界选择 URL：Android/iOS 直接从 `avatarTemplate` 解析静态 URL，桌面端继续使用 `Post.getAvatarUrl()` 的既有偏好策略。这样无需猜测 GIF 原图是否存在可替换扩展名，也不会扩大到个人主页等需要保留现有行为的场景。

`SmartAvatar` 继续处理通用缓存、尺寸和 fallback；不清空全局 image cache。Flair 暂不做不可靠的 URL 改写，因为服务端不保证 GIF 对应 PNG 存在，且本次日志最明确的高密度来源是帖子/Boost 头像。

## 首页恢复与访问风险

不新增网络行为。保留已经实现的分页游标推进、短冷却和用户手势触发恢复。401/403/419/429、Cloudflare 和确定性解析错误不自动重试，避免形成自动化访问特征。

## 兼容与回滚

- 相关帖子字段为空或接口不支持时，页面行为与旧版本一致。
- 移动端缺少静态模板时回退到现有 URL/fallback，不让头像异常阻塞帖子正文。
- 两项代码改动彼此独立，分别提交，可独立回滚。
