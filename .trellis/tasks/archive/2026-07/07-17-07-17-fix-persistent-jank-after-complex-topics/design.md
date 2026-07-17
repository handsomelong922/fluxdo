# 技术设计

## 1. 图片查看器原图缓存生命周期

`ImageViewerPage` 为每个实际构建过的原图 URL 保存一个稳定 `ImageProvider`。单图和画廊页都从该映射取 provider；thumbnail loading preview 继续使用独立 provider，不加入清理集合。

查看器 `dispose()` 时复制本次创建的 provider 列表并清空本地引用。实际 `evict()` 放到当前同步销毁流程之后异步执行，逐项捕获异常。这样不会在 pop 动画或 element finalization 中同步解析 image key，也不会调用全局 `imageCache.clear()`。正文图片通过 `ResizeImage(maxWidth/maxHeight)` 使用不同 key，磁盘文件由 `DiscourseCacheManager` 保留，因此功能语义不变。

## 2. 复杂详情快照按内容规模限额

为 `TopicDetailCacheService` 增加正文规模估算：对已加载 posts 的 `cooked`、签名等主要字符串求和，附加 stream 长度的轻量权重。每个缓存条目记录估算值。

普通完整详情同时受三类限制：最大帖子数、单条内容规模、全缓存总规模。单条超限时删除同 key 的旧 preview seed 并跳过写入；当前页面仍持有 notifier state，不受影响。插入普通条目后按 LRU 淘汰，直到条目数和总规模同时满足预算。

Preview seed 是首页/预览到详情的首帖即时承接契约：它不受单条普通快照上限阻断。写入 seed 后优先保留当前 seed，通过淘汰更旧条目收敛总预算；若当前 seed 自身超过总预算，允许暂时只保留这一条，保证当前导航体验。

移动端使用保守预算，桌面端保留更大空间。构造器默认值保持现有通用测试和外部调用兼容，平台 provider 显式传入移动/桌面预算。

## 3. 兼容性与风险

- 不更改 TopicDetail、Post、路由参数或 API 响应结构。
- 不更改首页详细展示；每次从已展示首帖进入详情时仍会重新 seed，因此淘汰旧详情快照不会造成首帖白屏。
- 原图被释放后再次打开需要从磁盘缓存重新解码，换取关闭查看器后不再长期占用数十 MB 解码纹理；网络文件不会重新下载。
- 不清理全局图片缓存，避免首页卡片和头像集体 cache miss。
- 若真机复测仍出现高 raster，但图片缓存已经在查看器退出后回落，再根据新日志处理剩余具体组件，不做猜测性降级。

## 4. 验证策略

- 纯函数/单元测试覆盖 provider 去重释放、异常隔离和只处理传入原图 provider。
- 详情缓存测试覆盖单条内容超限、总预算 LRU、preview seed 优先和现有目标楼层语义。
- 运行图片查看器、详情缓存、预览承接、详情页性能相关定向测试。
- 运行全量 Flutter test、analyze 和 diff check。
