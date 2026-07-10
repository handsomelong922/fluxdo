# Implementation Plan

## 0. Release Evidence

- [x] 等待 run `29099617349` 到 completed。
- [x] 确认 Android、Windows、upload/release jobs 全部 success。
- [x] 核验 release 恰好三个非空 assets。
- [x] 下载 APK，校验 SHA-256、v2 签名与两个 arm64 原生库。
- [x] 构建无需修复，不产生 workflow commit。

## 1. Fingerprint Regex Commit

- [ ] 将 endpoint 正则 pattern 收敛为合法 JS identifier + 稳定 POST 结构。
- [ ] 让 WebView 实际脚本与 Dart 回归 helper 共用同一 pattern。
- [ ] 测试 `_`、`L`、`$a1` 可匹配，非法/结构不完整样本不匹配。
- [ ] 运行：
  - `flutter test test/services/webview_session_cookie_refresh_service_test.dart`
  - `flutter analyze lib/services/webview_session_cookie_refresh_service.dart test/services/webview_session_cookie_refresh_service_test.dart`
- [ ] 独立提交：`fix fingerprint endpoint extraction`。

Rollback point：只 revert 此 commit 即恢复旧正则，不影响后续状态机。

## 2. Bootstrap Governance Commit

- [ ] 增加纯函数 failure cooldown 计算及测试。
- [ ] 在 `ensureSynced` 接入 failure streak、进程 × 登录会话成功态与日志字段。
- [ ] `runOnController` 接入 fresh plugin 标记、候选绕过、reload 与 404/discover
  失效逻辑；不得同回调立即重试。
- [ ] `PreloadedDataService.invalidatePluginCandidates()`。
- [ ] logout 调用 `resetSessionState()`，保留现有 Cookie/CF 清理顺序。
- [ ] 测试冷却序列、上限、candidate invalidation 与正则测试持续通过。
- [ ] 运行：
  - `flutter test test/services/webview_session_cookie_refresh_service_test.dart test/services/preloaded_data_service_test.dart`
  - `flutter analyze lib/services/webview_session_cookie_refresh_service.dart lib/services/preloaded_data_service.dart lib/services/discourse/_auth.dart test/services/webview_session_cookie_refresh_service_test.dart test/services/preloaded_data_service_test.dart`
- [ ] 独立提交：`throttle stale fingerprint bootstrap retries`。

Rollback point：revert 后回到 15min success TTL/45s failure cooldown；不影响正则 commit。

## 3. Upload Lookup Commit

- [ ] 增加 `ResolvedUploadUrl.missing`。
- [ ] service cache 改有界 LRU；成功缺失写负缓存，transient 不缓存。
- [ ] `resolveShortUpload` 增加同 URL active Future 与短窗口多 URL 微批。
- [ ] logout/reset 清空 upload lookup 会话状态，旧 generation 响应不得回写。
- [ ] `resolveShortUrl` / `resolveShortUrlForLink` 对 missing 返回 null。
- [ ] `DiscourseImageUtils` 不再缓存 transient null，confirmed missing 仍零请求裂图；
  保留当前有界 LRU 和所有 widget API。
- [ ] 新增 fake-adapter 测试：
  - 同 URL 两个调用只请求一次。
  - 同窗口不同 URL 合并一次 POST。
  - 成功未返回 key 后再次解析零请求。
  - transient failure 后下一次允许重新请求。
  - LRU/reset 不让 Future 悬挂。
- [ ] 运行：
  - `flutter test test/services/discourse_upload_lookup_test.dart`
  - `flutter analyze lib/services/discourse/discourse_service.dart lib/services/discourse/_uploads.dart lib/services/discourse/_auth.dart lib/widgets/content/discourse_html_content/image_utils.dart test/services/discourse_upload_lookup_test.dart`
- [ ] 独立提交：`dedupe upload short url lookups`。

Rollback point：只 revert 此 commit；不影响 bootstrap 或 topic preview 流程。

## 4. Cross-Feature Verification

- [ ] 检查 scheduler 常量与 skipScheduler 搜索，确认 3 / 6-per-3s / 250ms / 429
  cooldown 未改变且本任务没有新增绕过。
- [ ] 运行 `flutter analyze lib test`。
- [ ] 运行完整 `flutter test`。
- [ ] 运行首页摘要、topic preview、评论分页/渐进加载、用户主页与请求调度相关
  定向测试；若现有测试名变化，以 `rg --files test` 定位真实文件。
- [ ] `git diff --check`、逐 commit 检查 staged diff，不纳入未跟踪现场、密钥或
  `.learnings/`。

## 5. Finish

- [ ] 判断并更新 request-safety / bootstrap / upload lookup 长期 spec。
- [ ] 归档 Trellis task 并记录 journal。
- [ ] 检查当前分支提交列表保持分类边界，不 squash。
- [ ] 一次性推送 `codex/rollback-to-v0.3.1` 到 GitHub。
- [ ] 监控推送触发的新 Action；如失败，按失败 step 最小修复并再次验证。
