# 技术设计：话题预览触发与窗口体验

## 边界与复用

- 在 `preferences_provider.dart` 定义字符串持久化的 `TopicPreviewTrigger` 枚举，保留旧 `pref_long_press_preview` 仅用于一次性兼容读取；新 key 保存稳定枚举名。
- 设置声明使用 `ActionModel` + `SimpleDialog/RadioGroup`，避免把互斥选择伪装成两个可同时开启的开关。
- `TopicCard` 与 `CompactTopicCard` 接收独立的 `onPreviewTap`。卡片主体保持原 `InkWell.onTap`；当存在 `onPreviewTap` 时，在视觉内容之上增加右对齐、固定为元信息列基准宽度、覆盖卡片全高的透明手势层。
- `buildTopicItem` 根据 `TopicPreviewTrigger` 只绑定 `onLongPress` 或 `onPreviewTap`，统一普通列表入口。
- `SearchPostCard` 暴露相同的 `onPreviewTap`；搜索页的旧 `SearchPreviewDialog` 收敛为共用 `TopicPreviewDialog`，确保布局和首帖语义一致。

## 预览数据流

1. 用户触发预览后立即 push 固定尺寸 dialog route。
2. dialog 先读取 `HomeTopicExcerptLoader` 的内存 preview；未命中时请求 `getTopicFirstPostPreviewDetail`，保留完整的单首帖 `TopicDetail`，而不只保留 cooked 字符串。
3. UI 从该详情中的首帖 cooked 渲染；失败则回退列表 `Topic.excerpt`。
4. 用户点击“查看详情”时，以当前登录用户名为 cache scope 调用 `TopicDetailCacheService.writePreviewSeed`，随后关闭弹窗并执行原导航回调。
5. 详情 provider 首帧命中 preview seed，立即展示首帖；`isPreviewSeed` 强制后台 revalidate，补齐完整详情和评论。原目标楼层参数继续保留，完整数据到达后完成定位。

## 布局与动画

- dialog 高度使用 safe viewport 的固定 85%；宽度保持视口 90%、上限 500。
- 主卡片内部为：4px 顶部装饰条 + `Expanded` 可滚动正文区 + 紧凑固定底栏。加载 spinner 只替换正文内容，不参与外层尺寸计算。
- 顶部内容 padding 从 20 缩至约 14–16；标题使用 `titleMedium/titleLarge` 之间的紧凑样式。
- 分类/标签由单行、裁剪且按可用宽度选取的组件渲染；完整徽章放不下时停止追加并显示省略提示，绝不 Wrap。
- 底栏采用左侧两项统计列、中央查看详情按钮、右侧两项统计列；文字使用紧凑计数与相对时间，并对长文本缩放/截断。
- route 动画改为短时 `FadeTransition + ScaleTransition(0.97→1)`、`easeOutCubic`，禁用预览 route 的动态背景模糊，避免触发阶段的昂贵 backdrop filter 和回弹曲线。

## 兼容性与风险

- 旧 false 偏好不再表示关闭，而迁移为右侧点击；这是二选一产品约束下最接近原用户主动关闭长按的行为。
- 透明热区必须位于主 `InkWell` 上层，使用 `HitTestBehavior.opaque`，保证区域内点击不同时触发详情；区域外事件仍由原 `InkWell` 处理。
- 书签卡片带顶部/底部附属区，热区按整个最终卡片高度覆盖，但宽度只取右侧元信息基准，避免摘要区大面积误触。
- 搜索命中可能是回复；预览始终请求话题首帖。搜索卡片普通点击仍按原逻辑跳到命中楼层。
- 若完整 preview detail 请求失败，不写 preview seed，详情页按原路径正常请求。

## 回滚

- 设置可回滚为原布尔开关并忽略新 key。
- 卡片热区是独立回调，移除 `onPreviewTap` 即可恢复原点击树。
- 弹窗布局和缓存写入集中在共用预览组件，可单文件回退，不需要更改 API 或数据库。
