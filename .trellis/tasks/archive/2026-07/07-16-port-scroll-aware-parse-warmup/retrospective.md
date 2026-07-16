# Bug Analysis: 详情页解析预热挤占滚动帧

## 1. Root Cause Category

- **Category**: E - Implicit Assumption
- **Specific Cause**: 旧实现假设 `Priority.idle` 足以保护滚动帧；实际上它只控制任务排序，帧间隙仍会开始不可抢占的 HTML/DOM 解析。任务一旦开始，30ms 级原子工作会推迟后续触摸事件和帧开工。

## 2. Why Fixes Failed

1. 既有渐进物化只限制 Widget 构建数量，没有覆盖独立的解析预热队列。
2. 长帖改为异步 chunk 解析降低了部分同步成本，但短帖 Gallery 解析和长帖后续渲染数据仍可在滚动期间启动。
3. 仅使用 idle priority 解决了与已排队帧任务的顺序问题，没有解决连续滚动帧之间的事件循环占用。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|---|---|---|---|
| P0 | Architecture | 用 generation-scoped `TopicPostParseWarmUpQueue` 统一门控、单 Timer 重试和取消 | DONE |
| P0 | Test Coverage | 覆盖繁忙暂停、空闲续跑、代际替换、取消、在途失效和异常续跑 | DONE |
| P1 | Documentation | 在详情页渐进物化 code-spec 中明确 idle 不等于滚动安全 | DONE |
| P1 | Runtime | 继续通过现有性能诊断观察详情页 stall/build/raster，不新增热路径日志 | DONE |

## 4. Systematic Expansion

- **Similar Issues**: AVIF 动画、MessageBus UI 投递和 CF 后台 WebView 已使用同一 `ScrollBusySignal`；后续新增主 isolate 后台任务时也应先判断其单次工作是否不可抢占。
- **Design Improvement**: 滚动热路径只更新时间戳；具体后台任务自行在开始原子工作前查询，不向滚动路径添加监听器、Provider 写入或 rebuild。
- **Process Improvement**: 性能移植不能只比较提交标题；需要逐条对照当前分支是否已有更严格的物化/缓存策略，并为真正缺失的调度合同先补测试。

## 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/flutter-app.md` 的详情页渐进物化合同。
- [x] 增加可执行的预热队列回归测试。
- [x] 保留首页预览首帖即时承接、目标楼层和评论渐进加载回归矩阵。
