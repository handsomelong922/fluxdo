# CF 验证诊断统计

统计沿用现有开发者诊断开关，默认关闭。开启时，每轮结束向现有
`cf_challenge` 日志写入一条 `[VERIFY_METRICS] Round completed`，没有新界面、
上传或网络探测。聚合器仅保存固定数量的数字和一个活动轮次，不保存历史列表；
它不落盘、不跨启动恢复。关闭诊断会清空聚合。已写出的诊断行仍遵循现有日志保留规则。

## 口径

- `startedRounds`：协调器真正进入验证状态的次数。并发加入、重复提升、页面重载
  都不增加轮次；冷却跳过或尚未取得 context 的调用也不计入。
- `foregroundPresentations`：验证面板完成首个前台帧的次数，每轮最多一次。
  初始前台和后台转前台均计入；纯后台完成不计入。此字段不是人工点击、勾选框操作
  或已完成 CAPTCHA 的次数，也不声称用户实际看到了屏幕。
- `completedRounds` / `pendingRounds`：已观察到终态的轮次和当前仍未结束的轮次。
  未结束、被进程终止、或没有到达既有清理路径的轮次不伪造耗时或失败。
- `succeededRounds`：页面已到达无盾源站，且既有 Cookie 快照与原生析构 readiness
  均完成。不等于签发了新 Cookie，也不保证之后的业务请求成功。
- `cancelledRounds`：页面的用户退出结果为 false，随后既有清理结束。
- `failedRounds`：已观察到的启动阶段提前中止，或页面通过后 readiness 失败/超时。
- `waitMs`：本轮从协调器开始至上述终态的单调时钟耗时，包含准备、页面等待和
  既有 Cookie/析构清理。不包含开始前的 context 等待，也不是每个请求各自的等待时间。
- `totalWaitMs` / `meanWaitMs` / `maxWaitMs`：当前连续开启诊断期间，已结束轮次
  的等待总和、均值与最大值。内部按微秒累加，仅输出时取整为毫秒；未结束轮次排除。

诊断在一轮中途开启时，不补记该轮；只从下一次观察到的真实开始计数。
这些新增字段只接受数字和固定结果枚举，不包含 URL、Cookie、账号、请求头或轮次标识。

## 验证

- `dart --enable-asserts tool/cf_verification_metrics_smoke.dart`：直接导入生产聚合器，
  覆盖禁用、合流去重、展示去重、终态去重、三类结果、单调耗时、未结束轮次、迟到回调、
  开关重置、精度及固定输出结构。
- `flutter test --no-pub test/services/cf_verification_metrics_test.dart
  test/services/cf_background_verification_test.dart`：在依赖完整环境执行。Widget 用例覆盖
  初始前台、到期提升、后台完成、合流、慢快照、快照失败、实际退出确认和禁用诊断。

单调计时策略的纯 Dart 测试不能代替 Widget 测试或真实设备上的 Cloudflare 行为验证。
