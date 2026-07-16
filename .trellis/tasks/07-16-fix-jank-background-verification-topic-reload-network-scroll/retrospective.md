# Bug Analysis: 复杂场景持续卡顿与异步状态破坏连续性

## Bayesian Review

### Priors

| Hypothesis | Prior | Reasoning |
|---|---:|---|
| H1：复杂树形帖子同步物化/图片解码超出单帧预算 | 45% | 用户明确指出复杂帖子后持续卡顿，历史日志已有树形构建事件。 |
| H2：性能诊断或后台网络任务持续争用 UI/调度资源 | 30% | 卡顿在运行一段时间后加重，且日志包含重复后台请求。 |
| H3：页面状态切换和异步布局变化造成白屏/滚动跳变 | 25% | 书签、搜索、网络设置均表现为异步完成后的突变。 |

### Evidence And Update

- 高可靠日志证据：同一帧出现 2–4 次 `nested:childrenMaterialized`，build 达 30–57ms；H1 显著升高。
- 高可靠日志证据：正文图片按 1898px 解码，而设备物理宽度为 1080px，ImageCache 约 75.1MB 并出现 194ms raster；H1 进一步升高。
- 高可靠日志证据：CF 403 后 `/topics/timings` 仍约每 7 秒发送；H2 升高。
- 代码证据：自动 browser trust 恢复显式传入前台模式；目标楼层窗口可不含 OP；`developer_mode` 首帧后异步插入控件；H3 升高。

最终判断：五条链路均有直接日志或代码证据，针对性修复置信度均超过 90%；没有用删除首页详细展示、取消目标楼层或改变卡片样式来规避问题。

## 1. Root Cause Category

- **Category**: E - Implicit Assumption（主因）
- **Specific Cause**: “可见且滚动空闲”被误当作足够的单帧预算；HTML 声明宽度被误当作移动端真实解码宽度；异步设置内容被假设不会在用户滚动期间改变列表几何。
- **Category**: B - Cross-Layer Contract
- **Specific Cause**: CF 挑战状态没有贯通到 `ScreenTrack`；目标楼层网络窗口与独立 OP 预览之间缺少明确承接契约。
- **Category**: D - Test Coverage Gap
- **Specific Cause**: 既有测试覆盖单节点门禁、普通预览和控件状态，但未覆盖多节点同帧预算、目标窗口缺 OP、首帧后列表高度变化。

## 2. Why Earlier Fixes Were Incomplete

1. 可见性/滚动空闲门禁：限制了“何时开始”，没有限制“同一帧全局最多做多少”，多个可见节点仍可同时物化。
2. 图片长边/声明尺寸限制：限制了单图上限，却没有先把 HTML 桌面宽度 clamp 到移动端真实视口。
3. CF 冻结意图：服务已有挑战状态，但阅读时间上报没有订阅/查询该状态，仍持续探测。
4. 预览承接：覆盖了完整响应含 OP 的情况，漏掉搜索/书签显式目标窗口不含 1 楼的正常 API 形态。
5. 设置页局部异步加载：关注控件正确性，漏查了异步完成时 `maxScrollExtent` 的变化。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|---|---|---|---|
| P0 | Architecture | 自动树形 UI 物化使用独立全局串行队列，每帧最多提交一个节点。 | DONE |
| P0 | Runtime contract | CF 权威挑战触发阅读遥测熔断，fresh clearance 后立即恢复。 | DONE |
| P0 | Test coverage | 覆盖多节点队列、视口解码宽度、目标窗口缺 OP、首帧设置结构。 | DONE |
| P1 | Documentation | 将性能预算、预览承接、后台验证、稳定滚动几何写入 code-spec。 | DONE |
| P1 | Code review | 评审滚动页面异步内容时检查首帧结构和 `maxScrollExtent` 是否稳定。 | DONE |

## 4. Systematic Expansion

- **Similar Issues**: 其他递归列表、富媒体 HTML、设置/资料页异步卡片、CF 后的非关键后台上报都应按相同契约检查。
- **Design Improvement**: 将“是否可执行”和“每帧预算”视为两个独立维度；把预览数据与权威网络窗口保持分离；用服务状态贯通跨层后台任务。
- **Process Improvement**: 性能日志同时核对 frame component、图片物理尺寸/缓存、请求频率和滚动范围变化，避免只在 widget build 单层查找。

## 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/flutter-app.md`：全局物化预算、视口解码、预览连续性、设置页稳定几何。
- [x] 更新 `.trellis/spec/core/network-and-time.md`：CF 遥测熔断和自动后台验证契约。
- [x] 增加对应单元/Widget 回归测试。
- [x] 全量 analyze 与 Flutter tests 验证。
