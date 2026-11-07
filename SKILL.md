---
name: scriptcat-dev-env-skill
description: 在 Windows 上搭建、重建或排查「用脚本猫 ScriptCat 开发和调试油猴脚本」的 AI 开发环境（Edge 独立 profile + chrome-devtools-mcp 9222 + sctl 8643 + 官方 AI skills）。当用户要求部署/重装/换机重建这套环境、环境某条链路失效、或询问 CDP MCP 与 sctl / sctl Browser 如何分工时使用。也覆盖「AI 代启浏览器为何会被回收」「Chromium 136+ 为何必须独立 profile」等实测结论。
license: MIT
---

# 油猴脚本开发环境（ScriptCat + AI）

这套环境的**唯一目的**是写、装、调试油猴脚本（userscript），运行器是[脚本猫 ScriptCat](https://docs.scriptcat.org/)。
它把脚本管理与页面调试拆到互不干扰的通道上，让 AI 能完成「改脚本 → 装进浏览器 → 打开目标页 → 看 console/network 效果」的完整闭环。

## 何时使用

- 重装系统 / 换机器后重建这套环境
- 环境某条链路断了（CDP 连不上、sctl 未接入、MCP 工具组消失、页面脚本不生效）
- 需要判断某个操作该走 CDP MCP 还是 sctl
- 用户问「脚本猫提供的调试扩展和 CDP MCP 哪个好」

**不适用**：只想写一个 `.user.js` 而不需要部署环境 → 直接用官方 `scriptcat-userscript` skill。

## 三条工作原则（必须遵守）

1. **AI 先自己跑完**：凡是脚本、命令、文件写入能完成的步骤，直接执行，不要先问、不要先出计划等确认。
2. **只有必须本人操作的才交给本人**，并且**一次性列全、不要挤牙膏**。典型四类：连接器页点「信任」+ 重启宿主、扩展安装 / 网站登录 / 权限策略勾选、`sctl connect` 配对码、浏览器确认页。
3. **跑完回头订正本仓库**：把实测到的版本、路径、输出、失败与退路写回本仓库的 `SKILL.md` / `docs/` 并提交；不要只写工作日志就结束。**本仓库是这套环境唯一维护的文档源**——不要在别处另存一份部署说明、脚本备份或实况档案，多份副本必然过时。

配套约定：如需为宿主环境单独启动浏览器，先确认用户是否已长期授权；**未授权时不要擅自代启**。

> **维护约定**：换机、重装、排障、版本订正都以本仓库为准。`scripts/` 是可移植模板，实机运行副本放在 `%USERPROFILE%\EdgeAgent\`（快捷方式与 `mcp.json` 引用的是这份）；改了模板要同步运行副本，但**不再另建备份目录**。本机实况（真实账号、绝对路径、PID、信任指纹、已有脚本名、权限策略）不写进公开仓库。

## 环境总览

| 组件 | 所在 profile | 通道 | 职责 |
| --- | --- | --- | --- |
| `chrome-devtools-mcp` 1.12.0 | `EdgeAgent` 独立 profile | CDP `9222` | 页面深度调试：DOM / a11y / console / network / 截图 / 执行 JS / 性能 trace / Lighthouse / 扩展页 DOM |
| `sctl` + ScriptCat「外部接入」 | 同一 `EdgeAgent` profile | WS `8643` | 脚本管理：列出 / 读源码 / 安装 / 编辑 / 启停 / 删除 |
| 官方 skill `scriptcat-userscript`、`sctl` | 用户级 skills 目录 | 本地文件 | 写脚本的规则、骨架、静态检查器；sctl 命令用法 |

**明确不装 `sctl Browser` 扩展**：CDP MCP 已覆盖并超过它的页面侧能力；sctl Browser 的 `page`/`debug`/`cdp` 通过 `chrome.debugger` 附着标签页，与 CDP MCP 对同一 target **互斥**，不装就没有调试器争抢和「正在调试」信息栏。ScriptCat 外部接入只走扩展消息，不 attach debugger，与 9222 无冲突。
代价仅是失去书签 / 历史 / 下载 / Cookie 管理，这些本就归日常浏览器。

两条通道 9222 / 8643 可同时运行；**同一任务里不要混用工具链**。

## 部署工作流

前置：Windows 10/11、Microsoft Edge（Chromium 136+）、Node.js ≥ 20.19 / 22.12（21.x 不被 `chrome-devtools-mcp` 支持）、npm、WorkBuddy 或兼容的 AI 宿主。

先把本仓库 `scripts/` 下的文件复制到 `%USERPROFILE%\EdgeAgent\`，`config/` 作为模板按需取用。所有 `<...>` 占位符必须替换为**实机探测到的真实值**，不要照抄文档。

| # | 步骤 | 谁 | 动作 | 验收点 |
| --- | --- | --- | --- | --- |
| 1 | 环境探查 | **AI** | 查 Node / Edge / npm 真实路径与版本、9222 与 8643 占用、`EdgeAgent` 与宿主 skills 目录现状、`mcp.json` 是否存在 | 记录实际值 |
| 2 | 建目录 + 装 MCP | **AI** | `EdgeAgent\{mcp,out}`；`npm init -y` + `npm install chrome-devtools-mcp@1.12.0 --save-exact` | 入口 JS 存在，版本锁死 1.12.0 |
| 3 | 写 `mcp.json` | **AI** | 以 `config/mcp.json.example` 为模板，`command` 用真实 `node.exe` 绝对路径；参数逐个对照该版本的 `--help` | JSON 可解析、参数名全部存在 |
| 4 | 启动器 / 快捷方式 / 自检 | **AI** | 生成 `start-agent-edge.bat`、`make-shortcut.ps1`、`start-agent-edge-detached.ps1`、`doctor.ps1`、`probe-mcp.mjs`；编码：`.bat` 与 `.ps1` 为 CRLF 无 BOM，`doctor.ps1` 为 CRLF **带 BOM** | 编码校验通过，静态项全过 |
| 5 | 装两个官方 skill | **AI** | `npx skills add scriptscat/scriptcat -g -a codebuddy -y` 与 `npx skills add scriptscat/sctl -g -a codebuddy -y`；若宿主读的是别的目录，建 Junction 指过去 | `npx skills check -g` 全部最新；`check.mjs` 跑一个已有 `.user.js` 返回 ok |
| 6 | 装 sctl | **AI** | `irm https://raw.githubusercontent.com/scriptscat/sctl/main/scripts/install.ps1 \| iex`；临时加 PATH；`sctl version` | 输出版本号 + commit |
| 7 | 注册后台服务 | **AI**（被拦则转用户） | `sctl service install` + `sctl service status` | `daemon running at 127.0.0.1:8643`、`starts at login` |
| 8 | 启动浏览器 | **AI**（若已授权） | 用系统 shell 执行快捷方式（`start-agent-edge-detached.ps1`），**不要**在 AI 会话内直接 `Start-Process` | CDP `/json/version` 返回 `Edg/...`，且 Edge 跨命令存活 |
| 9 | 同步运行副本 | **AI** | 把 `scripts/` 的可移植文件复制到 `%USERPROFILE%\EdgeAgent\` 作为运行副本（快捷方式、`mcp.json` 引用的是这里）；**不要另建备份目录**，仓库即唯一源 | 运行副本与仓库模板一致 |
| 10 | **点信任 + 重启宿主** | **用户** | 连接器管理页 → 自定义连接器 → 对 `chrome-devtools` 点**信任**；必要时重启宿主 | 出现 `mcp__chrome-devtools__*` 工具组 |
| 11 | **装扩展 / 登录 / 权限策略** | **用户** | 在 **EdgeAgent 窗口**装 ScriptCat 及需要的扩展、登录目标网站；ScriptCat 工具 → 外部接入 → 打开开关、选权限策略 | 扩展页可见、开关已开 |
| 12 | **配对** | **用户** | 终端 `sctl connect` → 把 8 位码输入 **EdgeAgent 窗口**的 ScriptCat「重新接入 / Enroll」；**日常 Edge 的 ScriptCat 不要也 Enroll** | `sctl status` → `extension connected: true`、`scriptcat: online` |
| 13 | 端到端验收 | **AI** | `doctor.ps1`；`node probe-mcp.mjs`；MCP `list_pages` / `take_snapshot`；`sctl status` / `sctl scriptcats` / `sctl get` | 见下方验收清单 |
| 14 | **回头订正本仓库** | **AI** | 把实际版本 / 路径、第 7/10/12 步输出、失败与退路写回 `SKILL.md` / `docs/`，提交并推送 | 仓库与实况一致，无过时表述，无第二份文档源 |

**只把第 10–12 步交给用户，一次性列全。** 配对码 2 分钟有效、只显示一次、不得进入对话或日志。
第 7 步若被安全策略拦截（某些 AI 会话禁用 `schtasks.exe`），直接转给用户并说明原因，**不要重试、不要找等价绕过**。

## 验收清单

- [ ] `doctor.ps1`：通过项全绿、失败 0
- [ ] `node probe-mcp.mjs`：`RESULT: PASS`，`initialize` 返回 `chrome_devtools@1.12.0`、工具列表含扩展工具
- [ ] MCP `list_pages` 读到 Edge 里的页面；`take_snapshot` 能拿 a11y 树
- [ ] `sctl status` → `extension connected: true` / `scriptcat: online`；`sctl get` 能列出脚本
- [ ] `sctl browsers` 为空（确认没装 sctl Browser）
- [ ] 浏览器进程在**下一条独立命令**里仍存活（不是只在启动它的那条命令里活着）

## 硬知识：踩过的坑（不要自己发明替代方案）

| 现象 | 原因 / 结论 | 处理 |
| --- | --- | --- |
| 默认 profile 上调试端口不生效 | **Chromium 136+ 对默认 user-data-dir 直接忽略 `--remote-debugging-port`** | 必须 `--user-data-dir` 指向独立 profile；登录态和扩展因此要在这个新窗口里重做一次 |
| AI 会话里 `Start-Process` 启动的浏览器，下一条命令就没了 | 子进程归属 AI 会话进程树，命令结束被回收 | 让系统 shell 执行快捷方式（`explorer.exe <lnk>` 或 ShellExecute），进程归桌面 shell，可跨命令存活 |
| 计划任务 `schtasks.exe` 被拒绝 | 部分 AI 会话把它列入安全黑名单 | 不重试、不绕行，转交用户；或用系统 shell 方案 |
| `workbuddy` 不是合法 agent 名 | `npx skills` 的有效名单里对应的是 **`codebuddy`** | 用 `-a codebuddy`；装完用 Junction 暴露给宿主实际读取的 skills 目录 |
| 官方安装脚本装完 `sctl` 提示「无法识别」 | 安装脚本**不会修改 PATH** | 当前窗口 `$env:Path += ";$env:LOCALAPPDATA\sctl\bin"`；永久生效用 .NET `SetEnvironmentVariable`（避免 `setx` 截断 1024 字符、避免官方提示里的双分号） |
| `netstat` 查不到 8643，但服务明明在跑 | 该端口是 WebSocket 端点，某些会话的 TCP 表不可见 | 用 `Invoke-WebRequest http://127.0.0.1:8643/` 探测，返回 **`426 Upgrade Required` 就是正常** |
| `sctl run` / `scripts_logs` 报 unknown command | `run` / `logs` 要求 sctl **> 0.3.0** 且 ScriptCat **> 1.5.0**；实测 0.3.0 / 1.5.0 都不满足 | 退回 console / network 路径；后台脚本让脚本自己 `GM_log`，再用 CDP MCP 打开 ScriptCat 日志页配合 `take_snapshot` 查看 |
| `list_extensions` 说没装扩展，profile 里却有扩展目录 | 那是 Edge 内置组件 | 别据此判断扩展已装 |
| 改过 `mcp.json` 后 MCP 工具组消失 | 信任指纹按整份服务配置计算 | 重新点信任并重启宿主 |
| `evaluate_script` 看不到脚本里的变量 / `GM_*` | 它跑在**页面主世界**，脚本猫在 isolated world | 让脚本自己 `GM_log` / `console.log` 输出，再从 console 读 |

## 写脚本时的验证闭环

1. 用 `scripts_install_request` / `scripts_edit_request` 安装或编辑脚本（权限策略若设为「需人工审批」，确认页由用户点，**不要循环重试**）。
2. **页面脚本不能用 `scripts_run` 跑**（官方限制），用 MCP 的 `navigate_page` / `new_page` 打开目标网址触发注入。
3. MCP 的 `take_snapshot` / `list_console_messages` / `list_network_requests` 观察脚本对页面产生的实际效果。
4. 后台 / 定时脚本的日志：受上表版本边界限制，按退路处理。
5. 首次安装后，**新开一个会话再开始写脚本**——新装的 skill 在当次会话不会加载。

## 红线

- **不删除 / 不重建 `EdgeAgent\profile`**：登录态、Cookie、扩展和脚本都在里面。
- 不外传登录态、Cookie、`%LOCALAPPDATA%\sctl\control.token`、配对码；不把脚本源码写进日志或对话（可能含 API key）。
- ScriptCat 外部接入的「写操作 / 源码读取」权限策略由用户决定；即使设为「直接允许」，AI 每次写操作前也要说明目标脚本、**不做批量改动**。
- 不在 AI 会话里手动起 `sctl serve`（会随会话退出，且与已注册服务抢 8643）。
- 不在同一任务里混用工具链。
- 用户未明确授权时，不代为启动 / 重启浏览器；重启前若窗口有未提交内容，先提示。

## 资源

| 文件 | 用途 |
| --- | --- |
| `docs/deployment-guide.md` | 完整部署指南（逐步命令与解释） |
| `docs/architecture.md` | 组件分工、链路与选型理由 |
| `docs/mcp-parameters.md` | chrome-devtools-mcp 1.12.0 CLI 参数速查（连接 / 工具集 / 路径 / 安全 / 截图） |
| `docs/troubleshooting.md` | 排障速查表（含原始输出示例与发布网络问题） |
| `scripts/start-agent-edge.bat` | 启动带独立 profile + 9222 的 Edge（幂等，CDP 握手检测） |
| `scripts/make-shortcut.ps1` | 生成桌面版与 AI 版两个快捷方式（AI 版带 `nopause`、隐藏窗口） |
| `scripts/start-agent-edge-detached.ps1` | AI 代启浏览器、轮询 CDP 就绪、已就绪则不重复开窗 |
| `scripts/doctor.ps1` | 只读自检（配置 / Node / MCP / 参数 / 端口 / profile / 信任记录） |
| `scripts/probe-mcp.mjs` | 不依赖宿主工具是否加载，直接走 stdio JSON-RPC 验证 MCP 握手与 `list_pages` |
| `config/mcp.json.example` | MCP 服务配置模板 |
| `config/package.json` | 锁定 `chrome-devtools-mcp@1.12.0` |

## 版本基线

本 skill 的结论实测于：Microsoft Edge 157.0.4341.42 / Node 22.22.2 / chrome-devtools-mcp 1.12.0 / sctl 0.3.0 / ScriptCat 1.5.0（2026-11-07）。
**任一组件升级后，参数名、子命令与版本门槛都要重新核对一遍**；`chrome-devtools-mcp` 的参数最容易随小版本漂移，务必对照 `node <entry> --help`。
