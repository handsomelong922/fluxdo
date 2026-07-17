# Bug Analysis: 复杂帖子退出后应用仍持续卡顿

## 1. Root Cause Category

- **Category**: E - Implicit Assumption / A - Missing Spec
- **Specific Cause**: 图片缓存只设置了全局 72MB 上限，却默认路由独占的全尺寸原图可以长期参与全局 LRU；详情快照只按楼层数判断大小，默认“楼层少等于内容轻”。复杂图片和超长 HTML 都打破了这些假设。

## 2. Why Earlier Fixes Were Incomplete

1. 先前降低全局图片预算：限制了最坏上限，但没有表达全屏原图的路由所有权，因此退出查看器后仍可接近上限长期驻留。
2. 先前按楼层数跳过超大详情：覆盖“回复很多”的帖子，没有覆盖“楼层少但每层 HTML、代码、图片和链接很重”的帖子。
3. 先前主要优化当前详情页 build/raster：改善了单页滚动，却没有完全处理退出后的跨页面资源生命周期。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|---|---|---|---|
| P0 | Architecture | 路由独占全尺寸 provider 由路由登记并在销毁后逐项释放 | DONE |
| P0 | Runtime budget | 详情缓存同时限制楼层数、单条正文规模和总正文规模 | DONE |
| P0 | Test coverage | 覆盖 provider 异常隔离、内容超限、总预算 LRU 和 preview seed | DONE |
| P1 | Documentation | 将路由图片生命周期和 preview seed 缓存契约写入 Flutter spec | DONE |
| P1 | Monitoring | 后续真机日志继续观察退出查看器后的 imageCache 是否回落 | TODO (requires new device log) |

## 4. Systematic Expansion

- **Similar Issues**: 视频全屏控制器、WebView、动画图片和其他大对象缓存也必须区分“路由独占资源”与“全局复用资源”。
- **Design Improvement**: 新缓存不能只用条目数作为复杂度代理；至少需要内容/字节预算或明确所有权边界。
- **Process Improvement**: 对“退出页面后仍卡”的问题，日志审查必须比较 route pop 前后的资源快照，而不只看卡顿发生页面本身。

## 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/flutter-app.md`。
- [x] 新增图片查看器和详情缓存回归测试。
- [x] 保留下一轮真机日志验证项，不猜测性关闭内容功能。
