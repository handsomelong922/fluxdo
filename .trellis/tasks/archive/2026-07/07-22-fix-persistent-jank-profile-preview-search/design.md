# 技术设计

## 任务边界

父任务只拥有日志结论、子任务映射和最终集成门禁，不把四项独立行为揉成共享抽象。性能子任务修改首页滚动策略；其余子任务分别限定在用户主页、预览底栏和搜索历史存储边界。

## 集成契约

- 性能修复不得缩短首页数据列表、删除帖子返回历史或全局清缓存。远距离回顶先瞬移到靠近顶部的有界 staging offset，再完成短动画，使构建数量由 viewport 决定而不是由列表总长度决定。
- 用户主页仍保留总结请求用于资料统计；默认“话题”只改变初始 Tab 和首个动作列表请求，不删除其他标签。
- 预览回复统计复用现有准确的 `postsCount - 1` 数据，只扩展 compact stat 的可选视觉参数。
- 搜索历史从 `SharedPreferences` 同步读取，UI 首帧直接获得数据。只有用户提交的查询写入本地历史；排序刷新和带 `initialQuery` 的程序化入口不重复污染历史。

## 兼容与回滚

- 四项代码分别提交，可以独立回滚。
- 不新增依赖、不改 API schema、不改本地数据迁移；本地搜索历史使用新 key，无旧数据时自然为空。
- 父任务在所有子任务完成后运行全量验证并检查提交边界。

## 风险

- `ExtendedNestedScrollView` 的 PrimaryScrollController 需要保持唯一 position；回顶 helper 必须复用现有 guards，并 clamp staging offset。
- 用户主页初始话题加载不能因预置 `_loadingCache` 而被错误去重。
- 预览统计放大后必须继续通过 `FittedBox` 在窄屏缩放，不能挤压中央按钮。
- `SharedPreferences.setStringList` 是异步写入；UI 状态先同步更新，持久化失败不能阻止搜索。
