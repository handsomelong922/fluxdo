# Implementation Plan

1. 性能子任务
   - 写回归测试复现远距离变高列表回顶不能使用普通 extent 穿越。
   - 实现 index/key 级直接定位或等价有界重建，统一三个入口。
   - 运行 topics page 定向测试、analyze，独立提交。
2. 手势子任务
   - 写 widget tests：普通右滑返回、selection blocker、后代横向 `Scrollable`、向左 PageView 互不冲突。
   - 将 route 返回接入 gesture arena，保留动画 controller 和 blocker 取消语义。
   - 运行导航/内容定向测试、analyze，独立提交。
3. 相关帖子子任务
   - 先写模型解析、排序/截取、空/缺失字段、UI 展示与点击路由测试。
   - 扩展详情 JSON contract 和状态合并，新增默认展开列表与本地化文案。
   - 运行 model/provider/widget 定向测试和 l10n 生成检查，独立提交。
4. 集成门禁
   - 运行 `flutter analyze --no-pub`。
   - 运行 `flutter test --no-pub --reporter compact`。
   - 运行 `git diff --check`，检查提交列表与工作区隔离。
   - 执行 `trellis-break-loop`、判断并完成 spec 更新，归档子任务和父任务。
   - 最后一次性 `git push origin codex/rollback-to-v0.3.1`。

## Risky Files / Rollback Points

- `lib/pages/topics_page.dart`：首页滚动和分页触发共享；避免触发额外 load-more。
- `lib/services/navigation/pop_passthrough_material_page_route.dart`：所有启用水平 pop 的 route 共用；测试必须覆盖正常返回和取消。
- `lib/models/topic.dart`、详情 provider/service：分页合并不可丢失已有字段。
- 首帖 footer：只在 post 1 插入，避免每条评论重复显示。

## Validation Commands

```powershell
flutter test --no-pub test/pages/topics_page_header_progress_test.dart
flutter test --no-pub test/services/navigation/pop_passthrough_material_page_route_test.dart
flutter test --no-pub <related-topic targeted tests>
flutter analyze --no-pub
flutter test --no-pub --reporter compact
git diff --check
```
