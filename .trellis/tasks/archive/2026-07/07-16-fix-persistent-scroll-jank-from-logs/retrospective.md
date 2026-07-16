## Bug Analysis: 刷帖后持续掉帧与不跟手

### 1. Root Cause Category

- **Category**: E - Implicit Assumption；D - Test Coverage Gap
- **Specific Cause**: 首页刷新默认假设列表只有第一页，可以安全替换并把分页归零；
  lazy list 又默认 index 等同于 topic 身份。深滚动时这两个假设同时失效，导致列表高度
  骤减、scroll extent clamp 和大量卡片 state 重新绑定。诊断模块还隐式假设整份 JSONL
  的 split、UTF-8 计数和重组足够轻量，达到 retention 上限后反而在 UI isolate 制造 stall。
- **Concurrency subcategory**: 刷新 generation 过去只保护最终 `state`，分页字段与后台补页
  可能在校验前提交，属于异步状态提交边界不完整。

### 2. Why Fixes Failed

1. 先前优化集中在单张卡片 build、图片解码和详情页 rebuild boundary，降低了局部成本，
   但没有处理刷新时一次性替换整份多页列表的结构性跳变。
2. 诊断不断增加归因信息，却没有把诊断日志自身的 retention CPU 成本纳入观察对象，
   因此在长会话中会放大被测问题。
3. 单元测试覆盖了分页请求和卡片渲染，却缺少“已加载多页后刷新头部”和“列表头部重排后
   按 topic id 复用”的合同测试。
4. 最终审查发现 generation 检查最初只挡住 state 覆盖，没有挡住 `_page/_hasMore` 的提前
   修改；把异步计算与状态提交分离后才完整关闭竞态。

### 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|----------|-----------|-----------------|--------|
| P0 | Architecture | 刷新先局部计算，generation 校验后一次性提交列表和分页 | DONE |
| P0 | Test Coverage | 覆盖头部合并、去重、页码单调和稳定 topic key 映射 | DONE |
| P0 | Runtime | 整文件 trace retention 使用后台 isolate，写入仍串行 | DONE |
| P1 | Documentation | 将刷新身份、分页和诊断 retention 合同写入 Flutter spec | DONE |
| P1 | Code Review | 性能改动检查是否会缩短列表、重置分页或让诊断阻塞 UI | DONE |

### 4. Systematic Expansion

- **Similar Issues**: 搜索、书签、历史等可重排列表也应保持稳定业务 key；任何整文件日志、
  cache 或导出处理都应评估 UI isolate CPU 成本。
- **Design Improvement**: 异步 provider 将“计算结果”和“提交共享字段”分开，generation/token
  校验是提交事务的入口，而不是只包住最终 UI state。
- **Process Improvement**: 性能回归必须同时检查列表结构变化、滚动位置突变和诊断开销，
  不能只看单组件 build 时长。

### 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/flutter-app.md` 的可执行合同与测试矩阵。
- [x] 新增刷新合并、稳定 key 和后台 retention 回归测试。
- [x] 保留 557ms raster 峰值为后续真机证据，不做无归因的功能删减或画质降级。
