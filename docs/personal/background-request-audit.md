# 后台请求干扰复核（2026-10-15）

基线：`c5c69f92`。本轮只做本地修改，不推送或触发构建。

## 修复：旧轮询不能清除新轮询的取消令牌

`MessageBusService._poll` 原先在每次网络请求的 `finally` 无条件清空
`_currentCancelToken`。`stopAll()` 会立即递增代次并取消旧请求，新订阅可以
立即启动新代次；如果旧请求的异步收尾随后才执行，就会把新请求令牌清空。
后续停止、退出登录或订阅变更因此不能及时取消新请求，直到网络自身结束。

改为只在令牌仍属于当前请求时清空，与该服务已有的延迟等待收尾一致。
保留原轮询代次、取消语义、退避、请求优先级、认证和跨设备实时同步。
没有改变 CF 挑战检测或关闭阅读统计。

`test/services/message_bus_cancellation_test.dart` 使用独立服务实例和受控 Dio，
覆盖旧请求迟到收尾、新请求仍可取消，以及正常停止不自行重启。测试构造器
不创建全局网络会话。现有 Dart formatter 已解析新增测试；完整 Flutter
测试因本地 SDK/依赖缺失未运行，未重试被拒绝的下载。

## 已存在的保护，不重复修改

- `network/interceptors/request_scheduler_interceptor.dart`：`isSilent` 请求低优先级；
  排队取消和 CF 期间静默请求门控已存在。
- `message_bus_service.dart`：独立轮询 Dio、350ms 订阅变化合并、取消令牌、
  轮询代次、429 Retry-After（至少 15 秒）、失败线性退避（最高 180 秒）。
- `screen_track.dart`：在途互斥、按话题合并、失败 5/10/20/40 秒退避；
  CF 验证期间冻结采集，`_presence.dart` 的 timings 请求已静默。
- `discourse/_users.dart`：按用户名合并在途资料/统计请求；后台 seeking
  用户请求有静默低优先级。`core_providers.dart` 静默刷新有成功后两分钟冷却，
  但未把所有当前用户读取改为静默，避免扩大本轮认证/前台错误语义改动。
- `webview_session_cookie_refresh_service.dart`：会话 bootstrap 合并在途、
  成功 TTL 15 分钟，失败从 45 秒指数退避到 15 分钟。
- `/unread.json` 的服务调用入口是话题列表筛选，不是独立周期轮询，未关闭或降级。

## 通知计数候选核对

只读检查参考仓库提交 `11c1fd3c975af09025be6053411d92d41bb161f2`。
当前 `_markNotificationRead` 只更新 recent 列表并发服务端已读请求，确实缺少
历史列表和计数的本地同步；当前计数 provider 只有 `update` / `markAllRead`。
参考提交处理的缺口尚在。但不能直接照搬：大屏播放列表是打开时的不可变快照，
来回翻页会重复把同一个 `read=false` 通知传入；直接每次减计数可能重复扣减。
真正修复应覆盖重复点击、列表快照、MessageBus 推送先后顺序及失败恢复。
本次只报告该候选，未混入轮询取消补丁。
