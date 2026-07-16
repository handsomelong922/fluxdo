# 技术设计

## 1. 首页刷新状态提交

为 `TopicListNotifier.refresh` 增加显式的“保留已加载尾部”模式，仅供用户主动刷新首页使用。刷新响应仍决定最新头部顺序和内容；随后按 topic id 追加当前列表中未出现在新头部的条目。该模式同时保留刷新前的最大已加载页和 `hasMore` 状态，防止下一次 load-more 从 page 1 重新请求。

筛选、排序、标签、stale tab 和 provider invalidate 继续使用完整替换语义，避免不同查询条件的数据混合。首页详细展示只消费 Topic 上的 excerpt/preview，不参与合并策略。

列表渲染为每个普通/置顶话题统一包裹稳定 `ValueKey<int>(topic.id)`，并由 `findChildIndexCallback` 使用当次 topics 快照构建的 O(1) id-index map 返回 child index。incoming slot 和 footer 使用独立 key 空间，避免与 topic id 冲突。

## 2. 性能诊断 retention 后台化

保留现有 `_writeChain` 串行文件写入。文件 I/O 仍使用异步 `File` API，但以下 CPU 密集工作改到 `Isolate.run`：

- 首次读取日志后的非空行计数；
- retention 的 split、trim、逐行 UTF-8 字节计数和尾部保留计算。

后台函数只接收可发送的 String/int 参数并返回 String/计数结果，不访问 Flutter binding、File 或 service 实例。主 isolate 在后台计算完成后按原顺序写回裁剪后的文本并更新 `_cachedEntryCount`。异常继续吞掉，诊断失败不得影响正常浏览。

不改变慢帧阈值、采样冷却、路由/滚动/图片归因字段和导出格式，保证用户下一轮日志仍可直接比较。

## 3. 风险与回滚

- 刷新合并仅用于显式用户刷新；如出现顺序或分页回归，可独立回滚首页提交。
- stable key 不改变任何 widget 样式，只改变 element identity；测试覆盖普通卡片、置顶卡片和头部插入。
- isolate 可能有启动开销，但 retention 每约 100 条后才触发，且其目的正是避免 0.9MB 文本处理占用 UI isolate；小文件首次计数也只执行一次。
- 557ms raster 峰值没有足够组件证据，不在本次修改图片/视频功能，避免以牺牲内容体验换取不可验证的改善。

## 4. 验证策略

- 纯函数测试：刷新头部与已有尾部的顺序、去重、空列表、分页保留。
- Widget 测试：话题列表刷新重排后 key/index 映射正确，现有卡片类型和首页摘要 widget 不变。
- 性能诊断测试：后台 retention 结果与现有同步契约一致；覆盖条数限制、UTF-8 字节限制、空行和顺序。
- 回归：首页、详情预览承接、渐进加载、目标楼层、图片和嵌套回复相关测试。
- 全量 `flutter test --no-pub`、`flutter analyze --no-pub`、`git diff --check`。
