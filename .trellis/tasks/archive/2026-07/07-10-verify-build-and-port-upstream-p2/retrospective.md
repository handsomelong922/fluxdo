# Bug Analysis: Request amplification and stale bootstrap loops

## 1. Root Cause Category

- **Primary: B — Cross-Layer Contract**：API 的“成功但缺 key”与“请求失败”都曾被表示为 null，widget/service 无法知道是否应该重试；WebView bootstrap 的插件缓存、endpoint 状态、登录会话和请求触发方也缺少统一失败契约。
- **Secondary: D — Test Coverage Gap**：此前没有同时证明 same-key in-flight、multi-key micro-batch、confirmed missing、transient recovery 和 logout generation 的回归矩阵。
- **Secondary: E — Implicit Assumption**：默认假设 fingerprint endpoint 失败是短暂的、45 秒后重试会恢复；生产端点轮换后该假设不成立。

## 2. Why Earlier Fix Paths Failed

1. **缓存 null 抑制重复请求**：只压住了请求数量，却把网络/429 临时失败永久变成裂图，牺牲恢复能力。
2. **固定 45 秒 bootstrap cooldown**：适合短暂失败，不适合永久 404；周期性请求会持续拉起完整 Headless WebView，造成 CPU 与滚动/输入卡顿。
3. **每个 widget 自己 FutureBuilder 解析**：没有 service 级微批与 active Future，同一帧多个短链仍可能各发一个 POST。
4. **直接照搬上游**：当前分支有有界 LRU、首页详细展示、BrowserTrust/Cookie 诊断和不同目录结构，整提交覆盖会丢失现有契约。

## 3. Prevention Mechanisms

| Priority | Mechanism | Specific Action | Status |
|---|---|---|---|
| P0 | Architecture | `ResolvedUploadUrl.missing` 区分 confirmed missing 与 transient failure | DONE |
| P0 | Architecture | service 级同 key Future + 8ms multi-key batch + bounded LRU | DONE |
| P0 | Runtime state | bootstrap 指数退避、stale candidate invalidation、login-session reset | DONE |
| P0 | Existing safety | 保留 3 并发、6/3s、250ms、host 共享和 429 cooldown；无新 bypass | DONE |
| P1 | Tests | 覆盖合并、负缓存、临时恢复、reset、Notion、首页 preview 与 full suite | DONE |
| P1 | Documentation | 在 `network-and-time.md` 写入两个 7-section 可执行契约 | DONE (`a2d93334`) |

## 4. Systematic Expansion

- **Similar issues**：后台预热、自动刷新、媒体解析、MessageBus backlog 和列表分页都可能出现“每个 consumer 自己请求”的放大模式；未来修改应先检查 in-flight、batch、bounded cache 和 generation。
- **Design improvement**：服务层负责请求合并和结果语义，widget 只做有界展示缓存；不要让 UI 自己判断 429/CF 是否永久失败。
- **Process improvement**：上游移植先比较请求触发频率和本分支 scheduler/Cookie 合约，再比较代码 diff；测试必须包含错误矩阵，而不只成功路径。
- **Knowledge gap**：当前 spec index 引用的 cross-layer guide 文件缺失，已记录在 `.learnings/ERRORS.md`；本任务使用 domain code-spec 作为真实约束，不虚构模板同步。

## 5. Knowledge Capture

- [x] 更新 `.trellis/spec/core/network-and-time.md`。
- [x] 新增 upload lookup integration tests 与 bootstrap policy tests。
- [x] 保留分类 commit，便于单独 revert。
- [x] 检查 `src/templates/markdown/spec`：当前应用仓库不存在该目录，模板同步不适用。
- [ ] 推送后监控新的 GitHub Actions 并验证 release 构建结果。
