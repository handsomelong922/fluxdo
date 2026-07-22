# 优化 Windows Codex 命令执行环境

## Goal

在不破坏 Windows PowerShell 5.1 兼容性和现有用户配置的前提下，降低 Codex 在 Windows 上执行命令时的中文乱码、PowerShell 解析失败、无效重试与复杂命令 Token 浪费。

## Confirmed Facts

- 目标系统是 Windows，配置范围为当前用户。
- 必须以实际进程信息识别交互终端和 Agent 后台执行环境，不能根据安装文件猜测。
- 所有持久化修改必须保留现有内容、可重复执行且不会重复追加。
- 当前项目已有项目级 `AGENTS.md`，本任务不修改或新建项目级规则；长期规则写入全局 `~/.codex/AGENTS.md`。

## Requirements

1. 检测交互终端和后台执行器的进程路径、`PSVersion`、`PSEdition`、`PSHOME`。
2. 检测 PowerShell 7、`rg`、Git、Node.js、Python 与 pip 的实际解析路径；已有工具不重复安装。
3. 仅在 PowerShell 7 缺失时安装稳定版，保留 Windows PowerShell 5.1。
4. 若 Python 命中 WindowsApps 占位别名，定位真实解释器并以保留全部 PATH 条目的方式修正用户级 PATH 顺序。
5. 在 PowerShell 7 Profile 中用带标记的幂等块设置控制台输入、输出和 `$OutputEncoding` 为无 BOM UTF-8，并将代码页设为 65001；不得覆盖 Profile 其他内容。
6. 在全局 `~/.codex/AGENTS.md` 中保留原内容并用带标记的幂等块加入命令执行长期规则，避免重复内容。
7. 不修改无关配置，不创建或修改项目级 `AGENTS.md`。
8. 在读取新用户环境变量的新进程中验证 PowerShell、编码、中文和所有工具，并比较交互终端与 Agent 后台环境。
9. 任一步失败时记录准确原因，并继续其余安全步骤。

## Acceptance Criteria

- 报告两个环境的实际 PowerShell 进程与版本字段。
- `pwsh.exe` 的绝对路径和版本得到验证；若原本缺失则安装成功，若已存在则没有重复安装。
- 新启动的 PowerShell 7 中活动代码页为 65001，输入、输出与 `$OutputEncoding` 均为无 BOM UTF-8，中文往返输出正常。
- `rg`、Git、Node.js、Python、pip 均报告实际命令路径和版本；Python 不解析到 WindowsApps 占位别名。
- Profile、用户 PATH、全局 `AGENTS.md` 的变更幂等且保留既有条目和内容。
- 最终报告包含发现、修改、未修改原因、验证结果及 Codex 是否需重启。

## Out of Scope

- 卸载或替换 Windows PowerShell 5.1。
- 修改机器级 PATH、项目代码、项目级 `AGENTS.md` 或无关 Codex 设置。
- 为已存在且可用的工具重复安装或升级。

## Open Questions

无。用户已明确授权直接检查并执行必要的安全配置。
