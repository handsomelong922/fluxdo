# 2026-07-16 模拟器真实浏览采样

## 环境与边界

- 采样窗口：2026-07-16 15:14–16:17（Asia/Shanghai），其中连续真实节奏操作超过 30 分钟，完整墙钟观察超过 60 分钟。
- AVD：`ctf_api30`，Android 11 / API 30 / x86_64，AMD host OpenGL，SurfaceFlinger `GPU missed frame count: 0`。
- 应用：`com.github.lingyan000.fluxdo`，PID 全程 `4721`，兼容包 `primaryCpuAbi=x86_64`。
- 日志：`pref_performance_diagnostics_enabled=true`、`pref_app_logs_enabled=true`；本轮起始性能日志为 715 行。
- GitHub 原始 APK SHA-256：`228CE9BB78458FE72B5C068C08D73CBE09A947F89F1D3A7D3AE87ACE3435FB8C`，采样前未变化，未安装替换、修改或重签。
- 交互只包含滑动、阅读停留、进帖、返回、图片查看器和 Android 前后台切换；未执行社区写操作或修改设置。

## 行为节奏

- 滑动持续约 550–1100ms；每轮 4–6 次。
- 普通停留约 2.9–8.6s；长阅读停留约 10–16s。
- 多轮包含短距离反向回看。
- 覆盖首页、短文字帖、48 回复且首帖含图片/链接卡片的长帖、评论中后段、图片查看器双击/轻移/返回、三次后台热恢复和恢复后的首页回访。

## 场景结果

下表的慢帧率使用诊断 `frame_window.frames` 汇总作为相对比较基线；它用于前后趋势，不等同于系统级精确 FPS。

| 场景 | 帧窗口帧数 | 采样慢帧 | 相对慢帧率 | severe/frozen | 最差帧 | 主导阶段 |
|---|---:|---:|---:|---:|---:|---|
| 首页 1 | 236 | 13 | 5.5% | 1/0 | 52ms | raster |
| 首页 2 | 233 | 10 | 4.3% | 0/0 | 34ms | raster |
| 首页 3 反向回看 | 231 | 8 | 3.5% | 0/0 | 38ms | raster |
| 首页 4 长停留 | 185 | 10 | 5.4% | 1/0 | 61ms | raster |
| 短文字帖阅读 | 4 | 0 | 0% | 0/0 | - | - |
| 长帖打开 | 21 | 3 | 14.3% | 0/0 | 38ms | raster；样本很小 |
| 长帖阅读 1 | 564 | 11 | 2.0% | 0/0 | 38ms | raster |
| 长帖阅读 2 | 1695 | 27 | 1.6% | 0/0 | 23ms | raster |
| 长帖阅读 3 | 1320 | 14 | 1.1% | 0/0 | 32ms | raster |
| 图片查看器打开 | 21 | 2 | 9.5% | 1/0 | 64ms | raster；路由首帧 |
| 图片缩放/轻移/返回 | 459 | 15 | 3.3% | 1/0 | 55ms | raster/vsync |
| 复杂场景后首页 1 | 337 | 12 | 3.6% | 0/0 | 47ms | raster |
| 复杂场景后首页 2 | 272 | 7 | 2.6% | 1/0 | 64ms | raster |
| 三次恢复后的干净首页 | 3089 | 50 | 1.6% | 0/0 | 40ms | 全部 raster，build 主导为 0 |

首页初始四轮聚合为 4.6%，长帖、图片查看器和前后台切换后的两轮首页聚合为 3.1%；最后一轮为 1.6%。没有出现“复杂操作后持续恶化”。

## 关键归因

### 1. 浏览/滚动

- 首页和长帖的慢帧绝大多数为 `raster_slow_without_image_events`，build 通常为 0–3ms。
- 长帖多轮没有 severe/frozen 或 UI isolate stall；慢帧率随继续阅读从 2.0% 降到 1.1%。
- 诊断中可见 `nested:card` / `post:footer` build，但出现次数少、单帧 build 很低，没有重现历史上的同步递归物化或数十/数百毫秒 build。
- 约 5 分钟自然空闲期间性能日志行数保持不变，排除持续后台重绘。

### 2. 图片查看器

- 打开原图和缩放时各出现一次 55–64ms raster severe，但未出现历史记录中的秒级冻结，也没有让返回后的首页持续变慢。
- 单次路由 raster 峰值不足以满足“至少两轮可重复且持续”的源码修改门禁。

### 3. 后台热恢复

- 三次热恢复分别出现 313ms、290/122ms、556ms frozen。
- 重复两次的最差帧 `buildMs=0`，`vsyncOverheadMs=214/462`；首次为 build 3ms、vsync overhead 219ms。
- 对应 `ui_isolate_stall` 快照明确为 `lifecycleState=inactive`，随后才记录 `resumed`；即诊断把模拟器暂停/恢复间的调度和 vsync 间隔计入恢复帧。
- 恢复后的首页慢帧率低于初始首页，证明它不是持续应用 build 卡顿。该现象归类为模拟器生命周期/诊断噪声，不据此改业务代码。

### 4. 外部与测试噪声

- 早期两次进帖遇到 HTTP 429 / `Too many requests`；冷却后正常进入。它是站点限流，不是 UI 卡顿。
- 一轮恢复后 ADB 有一次 `INJECT_EVENTS` 拒绝，前台 Activity 和 PID 正常；该轮不作为完整对照，随后补做了显式焦点确认的干净样本。
- 性能日志达到保留阈值后行号发生裁剪，后续改用 UTC 时间戳分段；裁剪前日志已保存到本地临时目录。
- ADB 第一张 host-GPU screencap 偶尔只包含增量 damage 区域而出现黑块，2 秒后的第二张恢复正常；后续设备内 `screencap` + `adb pull` 与 `exec-out` 哈希一致。该现象未持续，不归因于应用 UI。

## 当前结论

- 本轮没有形成满足修改门禁的新应用热点；当前可见慢帧主要是 x86_64 模拟器在 1080×2280 下的 host-GPU raster 基线。
- 历史上已经修复的树形物化、图片解码、内存压力和中心切换问题均未复现。
- 因此保持产品源码、UI 和业务行为不变是风险最低且证据最一致的结果。

## 本地证据

- 截图、UI 层级和分段日志：`C:\Users\User\AppData\Local\Temp\fluxdo-real-browse-0716`
- 关键快照：`performance-after-home2.jsonl`、`performance-after-long3.jsonl`、`performance-final-sampling.jsonl`、`performance-after-resume-repeats.jsonl`、`performance-after-retention.jsonl`
