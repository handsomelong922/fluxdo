# 个人 fork 恢复与改动手册

记录日期：2026-10-10。供工作区丢失、换机器、后续接手开发时恢复；不是临时环境的永久保留承诺。

## 1. 从哪里恢复

- 唯一开发与发布目标：[handsomelong922/fluxdo](https://github.com/handsomelong922/fluxdo)，分支 `dev`。只向自己的 fork 写入，不向上游推送、提 PR 或发布。
- 个人修改前的历史基线：`e40fde291bb98c66a08d47ef18f8737191eab881`。
- 本手册核对的已提交检查点：`447bc70a1fe7859d7238e97d6e4ddeee8e184c71`。之后的工作以 fork 的 `dev` 实际提交、CI 与本目录追加记录为准，不把此 SHA 当成永远最新。
- 本次已存在的目录：源码 `/workspace/shared/fluxdo`；SDK `/workspace/shared/flutter-sdk`。这些是路径记录，不代表换工作区后仍存在。
- 可恢复资产是已推送的源码、Git 历史、锁文件、子模块指针和这份文档。未提交的编辑、SDK 安装目录、依赖缓存、运行进程和本机凭据不能靠 Git 恢复；没有经核实的当前工作区永久保留期限。
- 使用现有获准的 shell、Git、Dart 与 GitHub 工具即可继续；不需要为恢复额外创建 Codex 任务或连接用户电脑。

### 在新空目录恢复最新 dev

以下命令需要可访问 GitHub；不会向远端写入。不要在有未保存修改的目录执行重置或清理。

```bash
git clone --branch dev --recurse-submodules https://github.com/handsomelong922/fluxdo.git fluxdo
cd fluxdo
git remote -v
git status --short
git log -8 --oneline
git submodule status --recursive
```

核对 origin 的 fetch/push 都属于 `handsomelong922/fluxdo`。子模块来自上游仅为读取固定依赖；不要使用 `git submodule update --remote` 把锁定版本悄悄升级，也不要向子模块远端写入。

如需重现上述历史检查点，在**另一个全新 clone** 中执行：

```bash
git checkout --detach 447bc70a1fe7859d7238e97d6e4ddeee8e184c71
git submodule update --init --recursive
```

继续开发则使用 `dev`。已有工作区先检查 `git status`，保存未提交改动，再考虑 `git pull --ff-only origin dev`；不要用 `reset --hard` 或 `clean -fdx` 做常规恢复。

## 2. 已完成的个人功能

本节描述截至 `447bc70a` 已提交的功能，测试是否通过另见第 5 节。

- 话题阅读：移除重复顶栏标题和背景闪动；首次进入直接使用目标阅读/树形模式，避免首帧切换；优化浮动透明栏、内容避让、目录定位与滚动跳转。
- 首页卡片：可隐藏头像，同时回收头像占用空间；默认行为与相关设置保留。
- 屏蔽编辑：标题关键词/正则规则可添加、点选编辑、删除、清空；用户名可批量输入，支持空格、换行、中英文逗号，移除 `@` 并去重。
- 标题正则：使用完整 Dart RegExp 语法，支持环视、反向引用、命名分组；不是 PCRE。忽略大小写，独立于完整词开关。保存前后台校验，匹配在 Isolate 中执行；2 秒超时终止，未验证标题保持隐藏并显示状态。每条上限 65536 字符、最多 32 条、总计 262144 字符。列表控制器处理缓存、分页、规则变化与页面销毁。
- 阅读手势：卡片右侧 25% 区域点击预览，可与长按并用；右侧预览默认关闭。支持普通页面滑动（默认）、淡入淡出、缩放、无动画，覆盖打开、返回及全屏返回手势；媒体查看器保留专用转场。
- 话题底栏：回顶、筛选、分享、收藏四个按钮可拖动排序，保存偏好并支持恢复默认；畸形或旧顺序会规范化。
- 整帖 AI 总结：按完整话题目录补取楼层、分块汇总，展示读取总数与缺失楼层，不把当前窗口冒充整帖；可配置 Prompt，错误和超限明确提示。任务不依赖页面/面板生命周期，关闭面板后在应用进程内继续；结果本地缓存、账号切换隔离、取消/重试受控。这里的“后台”不保证操作系统杀掉应用后仍继续运行。
- 自用 APK：自己的 `dev` push 自动分析、测试、构建 ARM64 APK，验证个人签名、原生库和 SHA-256；禁止上传 Crashlytics 符号/映射，使用占位 Firebase 配置。Artifact 与 Release 分开处理，发布权限不足不冒充发布成功。

关键代码入口：`lib/pages/topic_detail_page/`、`lib/widgets/topic/topic_card.dart` 及话题卡片相关文件、`lib/settings/widgets/topic_filter_rules_editor.dart`、`lib/utils/topic_regex*.dart`、`lib/providers/personal_*`、`lib/widgets/common/personal_page_transitions.dart`、`lib/widgets/common/fullscreen_swipe_back.dart`、`lib/services/ai_topic_summary*`、`lib/providers/ai_topic_summary_provider.dart`。

### 当前修订：页内 AI 已实现，等待本次提交 CI

本轮已把 AI 总结改为与参考截图对应的页内卡片，并加入通知提示 chip、Markdown 展示、继续追问、刷新、模型选择持久化。私密追问续写上下文仅保存在内存中，不作为持久化聊天记录保存。这是本轮工作区实现状态，**尚不能等同于本次精确提交的 CI 已通过或 APK 已交付**。

当前 AI 引擎没有参考旧方案使用的联网搜索传输层；这一差异已向用户说明。不得宣称当前版本自动联网搜索或已实现旧方案的搜索能力。

另一个本轮需求已实现、待本次 CI 验证：将“已忽略数量”提示中的管理入口替换为二级隐藏帖子明细，列出当前已加载且被隐藏的帖子标题、作者、隐藏原因，并支持打开帖子。最终行为、测试与交付以本次实际提交和 CI 为准；不要把未加载的远端帖子包含在此明细范围承诺中。

恢复工作时先检查 fork 的 `dev` 实际提交、代码和该 SHA 的 GitHub Actions，再判断上述项目是否已完成。`447bc70a` 和下方 4514 通过的记录始终属于**之前的历史检查点**，不是本轮修改的验证结果。

## 3. 个人提交索引

上游原有编辑器、媒体处理、表格等功能保留在基线历史中，不应误记为本轮新增。下面覆盖基线之后、检查点之前的全部个人提交，按时间顺序：

| 提交 | 作用 |
| --- | --- |
| `19d5d693` | 去除重复顶栏标题、修复背景闪动及契约测试 |
| `1271a4d1` | 隐藏首页头像设置、布局回收及测试 |
| `775cc152` | 自用 dev 自动测试、签名 APK 工作流 |
| `218aae96` | 独立工具/示例的分析依赖 |
| `360709f9` | Linux QuickJS 测试库、测试并发限制 |
| `637ec5ca` | 测试夹具及 APK 发布预检 |
| `40c53380` | 兼容验签输出、失败诊断产物 |
| `c5e75d40` | 固定来源的一次性 APK 恢复工作流 |
| `2c1635ac` | 树形首帧、透明浮动栏、滚动避让、发布预检 |
| `0b76dbb9` | 话题页卸载后延迟搜索清理测试 |
| `44339a92` | 屏蔽编辑、阅读手势、整帖 AI、底栏排序 |
| `ddba75a2` | 拖拽落点、总结滚动及头像测试夹具 |
| `9304ee27` | 完整后台正则、后台总结、全局返回动画、Release 权限路径 |
| `447bc70a` | 修复正则状态测试中真实 Isolate 与虚拟时钟等待冲突 |

核查任一提交用 `git show <SHA>`；完整差异用 `git diff e40fde29..447bc70a`。本手册后来随源码提交，文档自身的 SHA 不写死在自身内容中。

## 4. 工具链与依赖锁定

| 项目 | 核对值 / 复现要求 |
| --- | --- |
| Flutter | `3.47.4`，SDK commit `9584c6713b324636289d067944a46fd6b49df14b` |
| Flutter engine | `06a2e2a110089dff50fe635cffd2a61e1b24fbcd` |
| Dart | Flutter 自带 `3.13.3`；pubspec 要求 `^3.13.0` |
| DevTools | 本地 SDK 元数据 `2.60.0` |
| DoH 子模块 | `core/doh_proxy` → `08d3468f0a1eb2858840c525d61f8aa888696522` |
| Render 子模块 | `packages/fluxdo_render` → `ec42cbcfb63680325d43707ca372d769c23a0923` |
| Android NDK | CI 固定 `28.2.13676358` |
| CI Java | Temurin `17`；不能用本地 Java 版本冒充 CI 配置 |
| Gradle / AGP | wrapper `8.14` / Android Gradle Plugin `8.11.1` |
| Kotlin | `2.2.20` |
| Dart 依赖 | 根 `pubspec.lock` 已跟踪；workspace 配置见 `pubspec.yaml` |
| 当前本地辅助工具 | Git `2.52.0`；Python `3.12.14`；Node `24.19.0`；gh `2.46.0`；OpenJDK `21.0.12.1` |

最后一行是本次观测值，不是已锁定的 CI 依赖。当前 shell 未发现 `cargo`、`rustc`，不能宣称本地原生 Android 全套构建已就绪。

尚未完全固定：CI 使用 `ubuntu-latest`、Rust `stable`、未指定版本的 `cargo-ndk` 安装，以及若干按 major tag 引用的 Actions；Node/系统包也随 runner 变化。锁文件与 SDK 版本能降低恢复成本，但这还不是字节级可复现构建保证。后续若要锁定这些，应单独评估并修改工作流。

SDK 缺失时，在**网络/执行已获准且依赖来源可访问的新环境**按 Flutter 官方安装文档恢复对应版本；也可 checkout 官方 Flutter 仓库的上述 commit，再完成官方 SDK 初始化。不要为当前受阻下载尝试代理、镜像或其它规避路径。Git 源码 clone 本身不包含已下载的 Dart/engine 二进制。

## 5. 检查、测试与 CI

### 当前环境能做的无依赖检查

当前 Flutter pub 依赖下载及 SDK 元数据端点已被拒绝访问，**不重试该下载或绕过限制**。直接调用已存在的 Dart 可避免启动 Flutter wrapper 的下载检查：

```bash
DART=/workspace/shared/flutter-sdk/bin/cache/dart-sdk/bin/dart
"$DART" --version
"$DART" tool/topic_regex_smoke.dart
"$DART" tool/topic_regex_filter_smoke.dart
python3 -m unittest discover -s scripts/ci -p 'test_personal_release_preflight.py' -v
git diff --check
```

这些是纯 Dart 逻辑/预检验证，**不能替代 Flutter widget 全量测试或 APK 构建**。不要因为 SDK 目录存在就宣称 pub 依赖完备。无网络环境也可执行本目录 `inspect_environment.py`，只读取版本和 Git 状态，不安装、不下载、不打印环境变量或凭据。

### 依赖可访问的环境 / GitHub Actions

主入口详见 [开发文档](../development.md)。`just` 是可选快捷入口，真实实现为 `tool/*.dart`；无需为本任务额外安装 just/melos。

```bash
# 以下会获取依赖和生成文件，仅在网络允许的环境执行。
(cd devtools_extension && flutter pub get)
(cd packages/flutter_inappwebview_linux/example && flutter pub get)
dart tool/project_prep.dart app
dart tool/project_tasks.dart release:prepare --skip-test
dart tool/project_tasks.dart test:all test --concurrency=2
# 还需逐一运行 packages/*/test，完整范围以 personal-dev-apk.yaml 为准。
```

Linux 测试额外需要 `LIBQUICKJSC_TEST_PATH` 指向 `flutter_js` 包内 `linux/shared/libquickjs_c_bridge_plugin.so`。工作流从 `.dart_tool/package_config.json` 动态解析，不能硬编码旧机器缓存路径。正则异步 widget 测试必须尊重真实 Isolate 与虚拟测试时钟的边界，参考 `447bc70a`，不要通过跳过测试掩盖挂起。

正式个人构建以 [personal-dev-apk.yaml](../../.github/workflows/personal-dev-apk.yaml) 为准：

1. 校验签名 Secrets，精确 checkout 触发提交与子模块。
2. 准备独立包、l10n、QuickJS；分析错误阻断，沿用项目对 warning/info 的规则。
3. 根测试及各 package 测试逐包执行，并发 2，任一失败阻断构建发布。
4. 准备 Rust、cargo-ndk、CMake/Ninja、NDK；使用 `tool/flutterw.dart` 构建 release ARM64 APK，传入 `cronetHttpNoPlay=true`。
5. 校验证书资源同步、`libdoh_proxy.so`、`librhttp.so`、签名及 SHA-256；上传验证产物，再独立尝试 Release。

`personal-apk-recovery.yaml` 只用于一个固定历史提交/来源构建的恢复，**不是日常构建入口**，不要复制旧运行号重发新版本。个人工作流当前以 `dev` push / 手动触发为入口，仍需在获准发布范围内操作。

### 最近已知的历史验证

交接时记录的检查点构建为 [run #12](https://github.com/handsomelong922/fluxdo/actions/runs/38052738379)：4514 通过、176 跳过，产出[已验证 APK artifact](https://github.com/handsomelong922/fluxdo/actions/runs/38052738379/artifacts/11670644086)。本段是历史验证记录，不代表之后修改自动通过；精确 SHA 和最新结果应在运行详情中核对。

该 artifact 记录的到期日为 **2026-10-24**（工作流保留 14 天，下载需登录 GitHub）。失效后应从对应源码在获准环境重新构建，不把 artifact 链接当永久备份。失败诊断 artifact 仅保留 3 天，未验证 APK 不作为可安装发布。

## 6. 签名、Release 与安全边界

个人工作流涉及的 Secrets **只记名称，不记值**：

- `KEYSTORE_BASE64`
- `KEY_ALIAS`
- `KEY_PASSWORD`
- `STORE_PASSWORD`
- `RELEASE_PAT`（可选发布凭据；交接时未配置）
- `GITHUB_TOKEN`（Actions 自动提供，不是需要写进源码的个人 Token）

覆盖安装必须沿用现有个人签名；不能悄悄换 debug key 或生成新 key。Secrets 应由用户在 GitHub 仓库设置中管理；Git clone 无法恢复 Secret 值。不要把 keystore、密码、Token、签名 CSR、个人 Firebase 配置、API 密钥、账号缓存、日志中的凭据或整个 pub/Gradle/SDK 缓存提交到仓库。

交接时 **Release 未创建**。当前预检会在目标提交的工作流目录与默认分支不同时检查发布权限；普通 `GITHUB_TOKEN` 不能因此获得 Workflows 写权限。配置 `RELEASE_PAT` 涉及新增持久权限，应由用户明确同意并安全配置，不能在聊天中索要 Token。只给用户 fork 所需最小范围，按实际发布错误核对 Contents/Workflows 权限。预检通过也不等于 Release 已成功，必须看到发布步骤成功和真实 Release 链接。

即使 build 成功、release job 显示成功，也要检查发布步骤是否因权限预检而跳过。不能仅凭整个工作流绿色声称已经发布。

## 7. 后续每次交接要补什么

- 新功能/修复、对应提交、必要设置入口与未完成事项。
- 实际运行的检查及结果；明确本地未运行项目、CI 精确提交和跳过数量。
- APK/Release 链接、有效期、签名是否保持、发布是否真的成功。
- 工具链或子模块版本变化；不要把自动更新后的值仍称作固定版本。
- 在推送前 `git diff --check`，仅暂存本次明确文件，检查 `git diff --cached --stat` 与内容，确保无密钥和缓存；推送后核对 fork 远端 SHA。正文记录本身只有推送成功后才具有跨工作区恢复价值。

后续维护应优先核对 GitHub Actions 的**当前精确 SHA**，不要把旧 run 的通过状态套到新提交。最终测试结果、真实 APK/Release 链接及有效期只有验证后才能追加到用户聊天的交接记录；无需仅为把最新 CI 结果回写本文而再推一个文档提交、触发另一轮全量 CI。代码或功能有下一次正常提交时，再顺带更新仓库文档。

### 可离线重复的 AI 核心检查

纯 Dart 检查已收进源码，而非仅保留在临时目录。使用上述固定 SDK 的 Dart，可执行：

```bash
dart --enable-asserts tool/ai_summary_tasks_smoke.dart
dart --enable-asserts tool/ai_summary_source_smoke.dart
dart --enable-asserts tool/topic_regex_smoke.dart
dart --enable-asserts tool/topic_regex_filter_smoke.dart
```

这些检查不调用真实 AI，不替代 Flutter 组件测试或真机验收。不要为绕过环境明确拒绝的网络访问而切换下载源。
