# 修复真实设备日志定位的持续滚动卡顿

## Goal

根据用户在魅族 21（Android 16、120Hz）上的性能追踪、应用日志和请求耗时记录，修复刷帖过程中可重复出现的首页大范围重建、滚动位置突变和性能诊断自干扰，同时保持所有现有功能、首页卡片样式、首页详细展示和详情页渐进加载语义不变。

## Confirmed Facts

- 性能追踪共 2069 条：298 条慢帧明细、49 个帧窗口、4 次 UI isolate stall；慢帧中 204 条以 `vsync_overhead` 为主。
- 首页 `/latest.json` 完成附近出现 144ms build 帧，同帧记录至少 65 个不同话题卡片 build label，并伴随约 1.1 万像素滚动位置跳变。
- 同类 `/latest.json` 完成附近还出现 10–18ms 的多卡片批量构建，说明刷新/分页结果提交会在滚动热路径替换列表头部状态。
- 当前显式首页刷新只保留第一批结果并把分页页码重置为 0；已经加载的尾部页会被丢弃，深滚动位置因此可能被强制 clamp，后续还会重复请求已加载分页。
- 当前话题列表项没有稳定 topic-id key，也没有 `findChildIndexCallback`，列表头部刷新或重排时无法按话题身份复用 element/state。
- 性能日志长期处于 2000 行保留阈值附近；当前 retention 在主 isolate 上读取整份约 0.9MB JSONL、split、逐行 UTF-8 计数并重写。日志中的 135ms、267ms、45ms isolate stall 与该阶段一致。
- 复杂帖子 2598738 出现 557ms raster 冻结和随后 516ms pipeline wait；当时 build 仅 1ms、没有同步 work 归因，也没有相邻网络响应完成，不能据此安全修改帖子内容、图片展示或渐进加载逻辑。
- 应用日志只有 info 级登录/会话 Cookie 轮换，没有 crash、error 或业务异常。MessageBus、presence 和 topics/timings 请求属于后台长轮询/阅读上报，没有证据证明网络等待阻塞 UI isolate。
- 附件绝对时间戳为 2026-07-17，晚于当前 2026-07-16；跨日志关联必须以同一会话的 `sessionAgeMs` 和请求 `+offset` 为准。

## Requirements

- 显式刷新已有首页列表时，更新最新头部数据但保留已加载且未重复的尾部话题、当前分页进度和后续 load-more 能力，避免深滚动时列表高度骤减。
- 话题列表 item 必须使用稳定 topic-id identity，并为 builder 提供 topic-id 到当前索引的查找，避免头部插入、重排或刷新时把 state 错配到其他话题。
- 性能诊断的首次行数统计和 retention 文本处理必须移出 UI isolate；文件写入顺序、2000 条/3MB 上限、分享/清空/关闭前 flush 语义保持不变。
- 不能修改首页帖子卡片几何、颜色、排版、动画样式或内容。
- 不能删除、关闭或弱化“首页详细展示”；已有主帖预览必须继续被详情页立即承接，不能重复请求或白屏。
- 不能改变评论渐进加载、目标楼层、搜索/书签/历史导航、嵌套回复、图片查看器或视频行为。
- 不针对只有 raster 证据、尚无具体组件归因的 557ms 峰值做猜测性功能修改；保留现有诊断数据用于后续真机复测。
- 独立根因形成独立 commit，不能混入用户已有未跟踪 Trellis 历史、密钥或其他文件。

## Acceptance Criteria

- [ ] 显式刷新已有多页列表后，新头部顺序正确、旧尾部去重保留、页码不倒退，下一次 load-more 不重复加载已存在页。
- [ ] 列表重排/头部插入后，topic-id key 可解析到正确 child index，卡片状态不会按旧 index 错配。
- [ ] 冷启动首次诊断写入和超过 retention 阈值时，整文件计数/裁剪计算在后台 isolate 完成；主 isolate 只负责轻量入队和结果提交。
- [ ] retention 的条数、字节上限、顺序和异常兜底测试通过。
- [ ] 首页详细展示关闭和开启两种路径、TopicCard/CompactTopicCard、预览承接、详情页渐进加载相关回归通过。
- [ ] 定向测试、全量 Flutter test、`flutter analyze --no-pub`、`git diff --check` 全部通过，无调试残留。
- [ ] 变更按“首页刷新稳定性”“诊断 retention 后台化”“规范/任务记录”分开提交，复核后一次性推送到 `origin/codex/rollback-to-v0.3.1`。

## Out of Scope

- 猜测性禁用图片、动图、视频、嵌套回复或首页摘要。
- 修改 UI 样式、交互逻辑、网络限流参数或站点后台请求协议。
- 把 MessageBus 长轮询耗时当作 UI 卡顿根因。
- 仅凭单次 GPU raster 峰值切换 Flutter renderer 或降低内容质量。

## Open Questions

- 无阻塞问题；用户已明确授权分析、修复、充分验证、分开提交并推送。
