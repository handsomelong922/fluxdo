# 配置安卓模拟器并安装 0.6.112 APK

## Goal

让用户今后可以直接从终端调用昨天安装的 Android Emulator，并把当前项目 fork 发布的 `v0.6.112` APK 安装到现有虚拟设备中，为后续按真实使用场景配置和测试应用做好准备。

## Confirmed Facts

- Android Emulator `36.6.11` 安装于 `C:\Users\User\AppData\Local\Android\Sdk\emulator`，目录创建时间为 2026-07-15。
- 已存在 AVD `ctf_api30`。
- 用户级 `PATH` 已包含 Android `platform-tools`，可调用 `adb`，但尚未包含 Emulator 目录。
- `handsomelong922/fluxdo` 的最新 GitHub Release 为 `v0.6.112`，发布时间为 2026-07-16。
- `v0.6.112` Android 资产只包含 `arm64-v8a` 原生库；现有 `ctf_api30` 是 Android 11 / API 30 的 `x86_64` AVD。
- API 30 AVD 虽声明 `arm64-v8a` 转译支持，但应用启动后触发 `SIGILL`；crash buffer 明确记录 `ndk_translation: Undefined instruction`，致命栈位于 `libndk_translation.so`。
- APK 的 `minSdkVersion` 为 24，因此 API 30 高于最低版本要求；闪退不是普通的 Android 版本门槛问题。

## Requirements

- 仅向当前用户的 `PATH` 追加 Emulator 安装目录，保留所有现有条目并避免重复。
- 刷新当前会话的 `PATH`，验证 `emulator` 命令可直接解析。
- 从 `handsomelong922/fluxdo` 的 `v0.6.112` Release 下载 Android APK 资产，不使用旧版本或本地临时构建替代。
- 启动或复用 `ctf_api30`，等待 Android 启动完成后通过 `adb` 安装 APK。
- 从 APK 元数据识别包名和版本，并在设备端验证对应包已安装。
- 诊断并消除启动后的 native crash；允许在同一 Android Emulator 安装更新的系统镜像并新建兼容 AVD，同时保留原 `ctf_api30` 作为对照。
- 启动应用后持续观察进程、前台 Activity 和 crash buffer，不能再以短暂出现进程作为成功标准。
- 安装后只提供应用自定义配置建议，不擅自修改登录凭据、网络、AI 服务或其他应用内设置。

## Acceptance Criteria

- [x] 用户级 `PATH` 包含 `C:\Users\User\AppData\Local\Android\Sdk\emulator` 且只出现一次。
- [x] 新环境中 `emulator.exe` 与现有 `adb.exe` 均可解析。
- [x] 下载文件来自 `v0.6.112` Release，并记录资产名称、大小和校验值。
- [x] `ctf_api30` 启动完成，`adb` 报告设备状态为 `device`。
- [x] APK 安装成功，设备端包版本与下载资产的 APK 元数据一致。
- [x] FluxDO 在兼容 AVD 上启动后持续运行至少 30 秒，保持前台 Activity，期间 crash buffer 无新增 `SIGILL` / `FATAL EXCEPTION`。
- [x] 已向用户说明后续建议配置项与需要由用户提供的偏好信息。

## Out of Scope

- 不修改项目源码、依赖或构建配置。
- 不替换 Android Emulator 主程序，不删除原 `ctf_api30`，不安装 MSVC 工具链。
- 不替用户填写账号密码、API Key、Cookie、代理地址或 Notion 凭据。
- 不推送 GitHub 或改写现有 Git 历史。

## Open Questions

- 无阻塞问题；用户已明确授权定位、配置、下载与安装。具体应用内偏好在安装完成后再收集。

## Outcome

- 官方 `arm64-v8a` Release 资产保持原样并通过发布页 SHA-256 校验；因其在 API 30 x86_64 AVD 的 `ndk_translation` 中触发 `SIGILL`，模拟器改装同提交、同包版本、同签名的 `x86_64` direct 兼容包，未替换或上传官方资产。
- AVD 的软件渲染配置 `hw.gpu.enabled=no` 已改为宿主 AMD GPU 渲染。真实节奏首页浏览中慢帧事件率由 11.3% 降至 4.8%，最差帧由 58 ms 降至 41 ms，severe/frozen 帧归零。
- 应用在多轮首页滚动、帖子进入/返回和冷启动中保持稳定；最终 crash buffer、`SIGILL`、`FATAL EXCEPTION` 与 ANR 匹配均为 0。
- 帖子复测末段遇到站点 HTTP 429 / Cloudflare 限流；应用日志确认这是服务端响应，不是模拟器或 native crash。应用已返回首页。
