# Bug Analysis: CDK 返回帖子后重复请求触发 429

### 1. Root Cause Category

- **Category**: B - Cross-Layer Contract；D - Test Coverage Gap；E - Implicit Assumption
- **Specific Cause**: 路由层把“帖子页被子路由遮挡”错误等同于“帖子数据在隐藏期间一定变化”，返回时无条件发起完整详情刷新；CDK WebView 初始化又把“需要 Cookie priming”错误扩展为“需要静默 OAuth”。两个 UI 生命周期动作跨越 Provider/Service/Network 层制造了用户没有请求的流量。

### 2. Why Fixes Failed

1. 2026-06 已经移除过 LDC/CDK 自动请求，但约束只存在于一次任务记录，没有进入可执行 code-spec。
2. 2026-07 的 CDK 页面加速改动重新引入 `authorizeSilently()`，缺少“页面进入不得自动授权”的回归门禁。
3. topic channel 隐藏优化只验证了减少隐藏更新，没有验证 push/pop 一次子路由会额外发送多少网络请求。

### 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|----------|-----------|-----------------|--------|
| P0 | Architecture | 路由返回只恢复订阅，不把 route visibility 当作数据脏标志 | DONE |
| P0 | Test Coverage | 增加 CDK 静默 OAuth 与 topic route-return 自动刷新回归守卫 | DONE |
| P0 | Documentation | 在 `flutter-app.md` 写入 Topic Route Return Request Governance 七段式合同 | DONE |
| P1 | Code Review | WebView/Route 生命周期改动必须列出新增的自动请求和触发次数 | DONE via spec |

### 4. Systematic Expansion

- **Similar Issues**: App resume、底部 tab 重新激活、弹窗/预览关闭、登录/CF WebView 返回都可能把生命周期事件误当成数据变化。
- **Design Improvement**: 只有真实 MessageBus 事件、用户动作或明确缓存过期才能触发完整话题刷新；Cookie priming、OAuth、user-info 分别保持显式边界。
- **Process Improvement**: 性能“加速”或“补偿刷新”改动必须配套请求数量回归测试，不能只看页面首帧或 UI 状态。

### 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/flutter-app.md`。
- [x] 增加自动化回归守卫。
- [x] 记录根因提交链：`f94da2c7` 引入无条件 route catch-up，`fe3dfbc2` 重新引入 CDK 静默 OAuth。
- [x] 项目不存在 `src/templates/markdown/spec/` 镜像目录，无模板需要同步。
