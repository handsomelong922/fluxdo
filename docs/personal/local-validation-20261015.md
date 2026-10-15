# 本地验证环境检查点（2026-10-15）

## 当前状态

项目检查点：`3bc06e16ccacde668f35b57b82410761923e9a54`。本地验证受依赖访问限制阻塞后，用户已于 2026-10-15 授权恢复 GitHub Actions 完整验证与 ARM64 构建。已经上传的历史提交不删除、不强制回退；成功构建仍限制为 2–3 次。

已实际执行版本检查：

| 工具 | 版本 |
| --- | --- |
| Flutter | 3.47.4，源码 `9584c6713b324636289d067944a46fd6b49df14b` |
| Flutter engine | `06a2e2a110089dff50fe635cffd2a61e1b24fbcd` |
| Dart | 3.13.3，Flutter 官方初始化下载的配套版本 |
| DevTools | 2.60.0 |
| JDK / javac | Temurin 17.0.20.1+1 |
| Rust / Cargo | 1.99.0 |
| cargo-ndk | 4.1.2 |
| CMake | 3.31.10 |
| Ninja | 1.13.2 |
| Android SDK / Build Tools | API 36 revision 2 / 35.0.0 |
| Android NDK | 28.2.13676358 (r28c) |
| Platform Tools / Command-line Tools | 37.0.1 / 22.0 |

Linux Flutter 测试执行器已下载，动态库检查未显示缺失。Java、Rust 主机编译运行、CMake/Ninja 编译运行以及 AArch64 对象文件生成验证通过。这些不是本应用 APK 或界面测试通过。

## 安装路径与恢复

当前云工作区复用入口：

```bash
source /workspace/shared/fluxdo-local-env.sh
source /workspace/shared/toolchains/native-env.sh
source /workspace/shared/toolchains/android-env.sh
```

- Flutter：`/workspace/shared/flutter-sdk`
- Flutter/Dart HOME、XDG 配置和 pub 缓存：`/workspace/shared/dart-home`
- JDK：`/workspace/shared/toolchains/jdk-17`
- Rust：`/workspace/shared/toolchains/rustup`、`/workspace/shared/toolchains/cargo`
- CMake/Ninja：`/workspace/shared/toolchains/native-venv`

需将 HOME、XDG_CONFIG_HOME、XDG_CACHE_HOME 指向获准的可写目录，避免工具默认配置写入只读主目录。Flutter analytics 已关闭。编译并行数限制为 2；不要直接使用项目默认 8GB Gradle 堆在约 9.7GiB 内存机器上同时运行多个重任务。

Flutter 官方整包 URL 本次返回 HTTP 404 / NoSuchKey，不是当前网络策略拒绝。官方源码安装成功：

```bash
git clone --depth 1 --branch 3.47.4 https://github.com/flutter/flutter.git /workspace/shared/flutter-sdk
# 配置可写 HOME 和 XDG 目录后，运行官方初始化：
/workspace/shared/flutter-sdk/bin/flutter --version
```

这份记录描述实际可行路径，不保证任何下载端点将来持续可用。源码 Git 历史、固定版本、校验与配置文档可用于重建；SDK、缓存和工作区本身没有永久保留保证。不要把二进制工具链、依赖缓存、签名文件或凭据提交入库。

## 尚未通过的阶段

项目 `flutter pub get` 运行中收到明确的环境策略拒绝：访问 `https://pub.dev:443` 被阻止。停止该下载，没有换镜像规避。随后 `flutter pub get --offline` 失败，当前缓存不足以提供 `flutter_rust_bridge 2.12.0`。这不意味着该版本在公开仓库不存在，也不是应用源码编译错误。

因此以下均未执行/未通过：

- 完整项目 Flutter analyze
- 完整 provider/widget 测试及所有包回归
- Android 本地编译链接
- 模拟器或真机端到端验收

Android SDK/NDK 已安装并验证，路径为 `/workspace/shared/toolchains/android-sdk`；2026-10-15 经用户明确同意后接受了唯一提示的 Android SDK License Agreement，没有接受其他无关协议。ARM64 clang 运行及简单共享库编译链接通过（ELF64/AArch64），不是应用 APK 通过。当前无 `/dev/kvm` 和 CPU 虚拟化标记，不能获得已验证的 Linux 模拟器硬件加速；不影响 Flutter 单元/widget 测试或 APK 交叉编译的理论可行性。不能据此保证软件模拟器可启动或足够流畅。

## 后续验证顺序

在项目依赖访问已获准且可用后：

1. 保持锁文件，不升级依赖来掩盖缓存或下载问题。
2. `dart tool/project_prep.dart test` 获取依赖并生成 l10n；test 模式不生成代理证书。
3. 按 `.dart_tool/package_config.json` 找到 flutter_js 自带 QuickJS 动态库，配置 `LIBQUICKJSC_TEST_PATH`。
4. 执行变更相关测试，然后执行根目录和所有 workspace package 测试；准备 DevTools/插件 example 独立依赖后做全量分析。
5. SDK/NDK 与许可证准备完成后，通过 `dart tool/flutterw.dart build apk --debug --target-platform android-arm64 --dart-define=cronetHttpNoPlay=true` 做本地编译，限制内存与并发，禁止诊断符号上传。
6. 编译成功不等同于运行验证；debug 签名包也不是原签名的正式覆盖安装包。端到端验证仍需 WebView、网络和设备测试。

不以纯 Dart 烟测、替身测试、源码契约或工具版本检查冒充完整 Flutter/Android 验证，不承诺绝对零缺陷。

## 补充离线测试结果

17 份既有纯 Dart 测试的隔离副本共 148 个用例通过，随机顺序复跑也全部通过；对应 17 个生产文件和测试目录的 Dart 分析通过。临时副本仅将 flutter_test 导入改为真实缓存的 package:test，生产文件和断言未改，无生产依赖替身。被测生产模块只依赖 Dart SDK。测试框架的 47 个传递依赖中 35 个与项目锁文件匹配，12 个版本不同，因此这不是完整锁定环境的 Flutter 验证。

这批测试中只有标签解析的 2 个用例直接增加本批修改覆盖，其余 146 个是既有功能回归。WebView 响应编码用本地 Node 执行真实 JS 发送器，包含大于 1 MiB 数据分块往返和坏块拒绝，但不是 Android WebView 设备验收。

项目 338 个 hosted 依赖中，本地仅 51 个精确版本命中；22 个只有其他版本，265 个完全缺失。不能通过改锁文件或替身依赖宣称完整构建通过。Rust 官方依赖下载成功，但 native build.rs 会在缺证书时生成并复制 CA/私钥，故在该步骤前停止，未创建证书，未完成 Rust 项目测试。

## Actions 恢复检查

个人工作流 ID 为 380235176，状态 active；dev 当前提交无 skip 指令。检查时没有本批新运行，最近的成功运行 38533358428 属于旧基线，不能算本批成功。main 不含个人工作流文件；不要为解决触发而修改 main 或上游。当前连接未提供 workflow_dispatch 操作，本地 CLI 没有已认证会话；必须在已有授权的触发渠道可用后，核对新运行 head_sha 再继续。
