# Implementation Plan

## 1. Related Topics And Entry Speed

- [x] 为 `TopicDetail.highestPostNumber` 添加解析、copyWith、预览快照与模型测试。
- [x] 添加 related loader 的 TTL、容量、in-flight、viewer 隔离测试，再实现 loader。
- [x] 添加 provider 回归：正文先完成、后台补取、初始已有字段不补取、最高楼编号、失败不破坏正文、私信/筛选跳过。
- [x] 为可选相关请求增加单次访问选项与服务请求测试。
- [x] 在首页共享 push 路径中于导航前获取 excerpt pause token，并补纯逻辑/组件测试。
- [x] 运行相关定向测试和 changed-file analyze。

## 2. Boost / Emoji Performance

- [x] 先补移动端初始面板策略、cacheExtent 和静态 Boost 头像测试。
- [x] 移动端默认关闭 EmojiPicker，桌面保留展开。
- [x] 降低 EmojiPicker cacheExtent。
- [x] 强制 Boost 高密度头像静态化并移除重复监听。
- [x] 运行 Boost、头像、Emoji 定向测试和 changed-file analyze。

## 3. Home Pagination Recovery

- [x] 添加成功空页/重复页仍推进页码的 provider 或状态回归测试。
- [x] 添加临时错误冷却、冷却后用户触发、429/CF/鉴权保持手动、手动 retry 测试。
- [x] 实现页码推进和无 Timer 的失败门禁。
- [x] 运行 topic-list 定向测试和 changed-file analyze。

## 4. Integration Quality Gate

- [x] `dart format` 仅格式化本次修改的 Dart 文件。
- [x] 运行全部定向测试。
- [x] 运行 `flutter test --no-pub`。
- [x] 运行 `flutter analyze --no-pub`。
- [x] 运行 `git diff --check`，检查无调试残留、无无关改动。
- [x] 执行 `trellis-check`，必要时修复后复验。
- [x] 因该功能连续回归，执行 `trellis-break-loop` 并把可执行合同写入相关 spec。

## 5. Commits And Push

- [ ] 独立提交：相关帖子展示与详情进入速度。
- [ ] 独立提交：Boost/Emoji/静态头像性能。
- [ ] 独立提交：首页分页恢复。
- [ ] 独立提交：Trellis 任务、规范与回顾记录（仅纳入本次明确文件）。
- [ ] 核对提交列表和远端分支后统一 push GitHub。

## Risky Files / Rollback Points

- `lib/models/topic.dart`：共享模型，必须完整验证构造、解析、copyWith。
- `lib/providers/topic_detail_provider.dart` 与 `_loading_methods.dart`：异步 state race 和 autoDispose。
- `lib/services/network/discourse_dio.dart`：只允许新增 opt-out，不改变普通请求的重试行为。
- `lib/providers/topic_list/topic_list_provider.dart`：分页页码和失败门禁必须通过真实顺序测试。
- `lib/widgets/post/post_boost/boost_input.dart`：键盘/表情切换行为需保持。

## Validation Commands

```powershell
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\dart.bat format <changed dart files>
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat test --no-pub <target tests>
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat test --no-pub
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat analyze --no-pub
git diff --check
```
