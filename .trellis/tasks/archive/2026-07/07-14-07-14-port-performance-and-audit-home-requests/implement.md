# Implementation Plan

1. 建立启动/首页请求清单，标注端点、触发器、开关门禁、去重/缓存和周期性。
2. 为 `/latest` 单次处理补回归测试，移除二次转发，定向验证并提交。
3. 先为 MessageBus 投递队列写可测试策略/调度器，再接入 service；覆盖 FIFO、分批、取消和滚动繁忙边界后提交。
4. 为图片闸门写单测，实现 semaphore/codec/binding，替换启动 binding，分析与现有 AVIF/动图/内存压力代码的边界后提交。
5. 移除 `PreheatGate` 独立摘要预热，补充开关关闭时零 fetch 和开启时可见项渐进加载测试，验证预览种子进详情仍后台重验，单独提交。
6. 手工传递 categoryMap 快照并增加 Emoji 快速路径；用现有 TopicCard widget tests 保护样式/热区/摘要，单独提交。
7. 仅补头像 theme identity 失效并测试深浅主题切换，单独提交。
8. 运行定向 analyze/tests：MessageBus、request scheduler、home excerpt、topic preview/cache/provider、TopicCard、PostHeader、image gate。
9. 运行 `flutter analyze --no-pub` 和 `flutter test --no-pub --reporter compact`，复查 `git diff --check`、调试残留、请求端点和提交边界。
10. 判断是否需要 `trellis-break-loop` 和 `trellis-update-spec`；需要时记录“不得为同一首屏数据建立两个不共享 in-flight 的预热 loader”。
11. 逐提交复核 `git status`/`git diff --cached`，确认不带入 `.agents/`、`.claude/`、旧 `.trellis/tasks/`、keystore 或其它无关文件。
12. 复核本分支本批提交列表，一次推送到 `origin`。

## Validation Commands

```powershell
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat analyze --no-pub
C:\Users\User\AppData\Local\CodexFlutter\3.38.9\flutter\bin\flutter.bat test --no-pub --reporter compact
git diff --check
```

## Risky Files / Rollback Points

- `lib/main.dart`: binding 必须在任何 Flutter binding 使用之前建立。
- `lib/services/message_bus_service.dart`: 协议 lastMessageId 与 UI 投递顺序不得混合。
- `lib/pages/topics_page.dart` / `lib/widgets/topic/topic_card.dart`: 不得修改首页卡片样式和预览种子传递。
- `lib/widgets/preheat_gate.dart`: 只移除独立摘要预热，启动 HTML/topicList 预加载仍是首屏硬依赖。
- `lib/widgets/post/post_item/widgets/post_header_section.dart`: 只改缓存失效键。
