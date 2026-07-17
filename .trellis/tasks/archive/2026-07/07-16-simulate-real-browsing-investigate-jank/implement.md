# 实施计划

1. 记录起始 APK 哈希、AVD/GPU/ABI、日志开关、PID、页面和日志行号，保存初始截图/UI 层级。
2. 执行至少两轮首页自然浏览：中速滑动、阅读停留、短距离回看，记录各自行号区间。
3. 选择普通文字帖和长回复/树形帖子，各执行进入、等待、逐段慢读、回看、返回；不触发任何写操作。
4. 选择含图片或富媒体内容的帖子，观察图片加载、缓存增长、查看器往返和返回后持续流畅度；没有安全目标时不强行操作。
5. 执行多次页面往返和一次短暂后台/恢复，再回到首页自然浏览，检查是否出现随时间累积的退化。
6. 每 1–2 轮拉取新增性能日志和应用日志，按场景行区间汇总 slow/jank/severe/frozen、帧窗口、主导阶段、组件 build、图片缓存和 isolate stall。
7. 对候选热点复跑相同场景；不满足设计中的五项门禁则记录结论并保持源码不动。
8. 若门禁满足，加载 `trellis-before-dev` 和适用 spec，先补回归测试，再实施单一最小性能修复；禁止 UI/业务 diff。
9. 使用相同 ADB 行为场景复跑前后对比，运行定向测试、相关回归、analyze 和 `trellis-check`。
10. 再次校验原始 APK 哈希、crash/ANR、git diff 和任务边界，决定无代码结论或按独立性能根因提交。

## 验证命令与证据

- `adb devices -l`、`getprop`、`dumpsys package/activity/SurfaceFlinger`
- `wc -l`、`adb pull` 获取性能与应用日志
- PowerShell JSONL 聚合 slow-frame、frame-window、route、phase、attribution 和 imageCache
- `adb logcat -b crash` 与 fatal/ANR 检索
- 若改代码：相关 `flutter test --no-pub ...`、定向 `flutter analyze --no-pub <paths>`、必要的全量 analyze/test

## 回滚点

- ADB 浏览和日志拉取只读，不需要回滚。
- 任何源码候选修复保持单一提交；同场景无改善或行为变化时立即回滚该提交，不触碰用户已有改动。
