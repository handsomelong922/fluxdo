# 正文预热缓存一致性修复

## 边界

基于主仓库 c5c69f92，仅调整预热缓存条件，不引入惯性预热或数据落地后的新调度。
长帖各 chunk 对应一个 FluxdoRender，图片计数必须来自该 chunk 的完整节点集合。
短帖沿用完整短帖节点计数。筛选纯文段落不能改变计数口径，也不能重建 inlines。
图片尺寸保存在 cooked 中，修改尺寸通过统一的内容签名使解析缓存失效，再以新的
AST/inlines 身份使 flatten 缓存失效。长帖页面缓存直接复用 RenderParseCache 的签名。

## 交互安全

FlattenCache 的 key 不含 handler。SpanMountContext 仅刷新点击使用的 BuildContext，
不刷新被闭包捕获的帖子、引用回调或页面状态。因此不以默认 handler 预热可交互节点，
也不新建可能跨页面存活的 forPost 回调。仅预热纯文字、换行及递归的粗斜体段落；
其他节点包括链接、mention、图片、emoji、代码和未知节点均留给真实挂载创建。
因此不会让预热生成的默认点击行为覆盖原有图片菜单、链接追踪或个人功能。
这一保守选择可能减少富文本预热覆盖，但不增加预热节点数量。

## 调度与预算

维持原来的滚动停止/idle 调度、取消 generation 和 4ms 预算。每次最多处理一个
渲染块，使用原始节点游标跨块续跑；筛选与图片计数耗时从预算中扣除。
解析策略不扩张，长帖仍要求全部 chunk 已解析，短帖保持现有缓存入口。
单次节点遍历和原子 flatten 并非可抢占，因此 4ms 仍不是硬实时上限。

## 惯性预热评估：延后

只读参考 cc90e99dfa0771edfe64da8bcbc75bba0eadae8c。该方案改变触发时机、
方向队列、逐帧预算和取消行为，不能仅以静态逻辑保证在真机上不抢占帧时间。
post-frame 回调已晚于部分流水线工作，剩余预算估计不能代表 GPU/raster 压力，
不同刷新率和热降频还会改变可用余量。没有 60/120Hz 真机的 profile/release
基准、持续惯性滚动、重新触摸取消、图文长帖和主题/字号切换测试前，不实施。

## 验证

实际执行：
- dart tool/render_warmup_slice_smoke.dart：8 项通过。
- dart analyze lib/utils/render_warmup_slice.dart tool/render_warmup_slice_smoke.dart：通过。
- git diff --check：通过。

新增 test/utils/paragraph_warmup_safety_test.dart 覆盖：块边界、交互节点排除、
带图渲染块纯文缓存命中、图片数/主题/字号/节点身份失效、图片尺寸/正文编辑的
解析身份失效。环境缺 Flutter SDK，此测试尚未运行，不能据此声称 Flutter
集成测试或点击交互端到端测试通过。合入前需在完整 Flutter 环境执行该文件。
