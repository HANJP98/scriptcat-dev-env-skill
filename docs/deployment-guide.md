# 部署指南

> 本文件是 `SKILL.md` 里 13 步部署流程的展开版。**先读 `SKILL.md` 了解分工与红线**，再按本文执行。
> 所有命令在 Windows PowerShell 5.1 / Git Bash 实测过。路径里的 `<...>` 必须替换为本机实际探测值。

## 占位符

| 占位符 | 含义 | 取值方式 |
| --- | --- | --- |
| `<USERPROFILE>` | 用户主目录 | PowerShell `$env:USERPROFILE` |
| `<EDGEAGENT_DIR>` | 开发环境根目录 | 默认 `<USERPROFILE>\EdgeAgent` |
| `<NODE_EXE>` | `node.exe` 绝对路径 | `where.exe node`；WorkBuddy 托管版在 `<USERPROFILE>\.workbuddy\binaries\node\versions\<ver>\node.exe` |
| `<EDGE_EXE>` | `msedge.exe` 绝对路径 | 常见 `C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe` |
| `<WORKSPACE>` | 你的脚本工作区 | 任意目录，会作为 MCP 的 `--workspace` |
| `<SKILLS_DIR>` | 宿主实际读取 skills 的目录 | 视宿主而定，见第 5 步 |

---

## 1. 环境探查（AI）

```powershell
node -v; npm -v
where.exe node
(Get-Item "$env:ProgramFiles(x86)\Microsoft\Edge\Application\msedge.exe").VersionInfo.ProductVersion
Get-NetTCPConnection -LocalPort 9222,8643 -State Listen -ErrorAction SilentlyContinue
Test-Path "$env:USERPROFILE\.workbuddy\mcp.json"
```

记录实际值；Node 必须 ≥ 20.19 / ≥ 22.12 / ≥ 23（21.x 不被支持）；Edge 需 Chromium 136+。
9222、8643 应为空闲，被占用要先查清是谁。

## 2. 建目录并锁定 MCP 版本（AI）

```powershell
New-Item -ItemType Directory -Force -Path "<EDGEAGENT_DIR>\mcp", "<EDGEAGENT_DIR>\out"
cd "<EDGEAGENT_DIR>\mcp"
npm init -y
npm install chrome-devtools-mcp@1.12.0 --save-exact
node -p "require('./node_modules/chrome-devtools-mcp/package.json').version"
```

**必须锁死版本**：该包 CLI 参数会随小版本漂移，一份写死的 `mcp.json` 配新版可能直接启动失败。
不要 `npm install -g`，也不要装进宿主的 `binaries` 目录。

## 3. 写 `mcp.json`（AI）

路径：`~/.workbuddy/mcp.json`（宿主不同则换成对应位置）。以 `config/mcp.json.example` 为模板。

| 参数 | 作用 |
| --- | --- |
| `--browserUrl=http://127.0.0.1:9222` | 接管**已经启动**的 Edge，不让 MCP 自己拉浏览器 |
| `--no-page-id-routing` | 工具调用不必带 pageId |
| `--no-usage-statistics` / `--no-performance-crux` | 关闭统计上报 |
| `--categoryExtensions` | 启用扩展相关工具、允许读取 `chrome-extension://` 页面（读 ScriptCat 日志页要用） |
| `--workspace=<dir>` | 允许 `take_screenshot` 等工具把文件写到该目录；可多次指定 |

**三个坑**

1. `command` 必须是 `node.exe` 的**绝对路径**；`args[0]` 是该包入口 JS 的绝对路径。
2. `env` 里**只留 `NO_PROXY` 一个键**。Windows 环境变量名大小写不敏感，同时写 `NO_PROXY` 和 `no_proxy` 会让 PowerShell 的 `ConvertFrom-Json` 报「重复的键」。
3. 参数名逐个对照 `--help`，别凭印象写：

```bash
node "<EDGEAGENT_DIR>/mcp/node_modules/chrome-devtools-mcp/build/src/bin/chrome-devtools-mcp.js" --help
```

完整的 CLI 参数分组、默认值与截图相关参数见 [`mcp-parameters.md`](mcp-parameters.md)；升级 `chrome-devtools-mcp` 后务必重新对照 `--help`。

改过 `mcp.json` 后信任指纹会变，**重新点一次「信任」即可，实测当场生效、不必重启宿主**；但改动命令行参数（如 `--workspace`）本身需要重启 MCP 进程才生效。

## 4. 启动器、快捷方式与自检脚本（AI）

把 `scripts/` 下 5 个文件复制到 `<EDGEAGENT_DIR>\`，然后：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<EDGEAGENT_DIR>\make-shortcut.ps1"
```

它会生成两个快捷方式：桌面版（带 pause，方便人看懂输出）和 `Start Agent Edge (ai).lnk`（带 `nopause`、隐藏窗口，供 AI 代启）。

**编码要求**（不遵守会出现中文乱码或 `.bat` 无法执行）：

| 文件 | 编码 |
| --- | --- |
| `*.bat`、普通 `*.ps1` | UTF-8 **无 BOM** + CRLF，`.bat` 内容保持纯 ASCII |
| `doctor.ps1` | UTF-8 **带 BOM** + CRLF（PowerShell 5.1 读中文注释需要） |

统一处理脚本：

```powershell
$noBom = New-Object System.Text.UTF8Encoding($false)
$bom   = New-Object System.Text.UTF8Encoding($true)
Get-ChildItem "<EDGEAGENT_DIR>" -Include *.bat,*.ps1 -Recurse | ForEach-Object {
  $t = [IO.File]::ReadAllText($_.FullName, $noBom)
  if ($t.Length -gt 0 -and $t[0] -eq [char]0xFEFF) { $t = $t.Substring(1) }
  $t = (($t -replace "`r`n", "`n") -replace "`n", "`r`n")
  $enc = if ($_.Name -eq 'doctor.ps1') { $bom } else { $noBom }
  [IO.File]::WriteAllText($_.FullName, $t, $enc)
}
```

### 为什么一定要独立 profile

Chromium **136+ 对默认 `user-data-dir` 直接忽略 `--remote-debugging-port`**。所以启动器必须带：

```
--remote-debugging-port=9222
--user-data-dir="<EDGEAGENT_DIR>\profile"
--profile-directory=Default
```

代价是这是个**全新 profile**：网站要在这个窗口里重新登录一次、扩展要重装一次。好处是登录态、Cookie、扩展、脚本全部落在 `profile\` 目录，重启浏览器 / 重启系统 / 重装 Edge 都不丢。**不要删除或重建这个目录**。

## 5. 装两个官方 skill（AI）

```bash
npx --yes skills add scriptscat/scriptcat -g -a codebuddy -y
npx --yes skills add scriptscat/sctl       -g -a codebuddy -y
npx --yes skills check -g
```

- `scriptcat-userscript`：写法规则、脚本骨架、API 参考，自带 `check.mjs` 静态检查器
- `sctl`：通过 sctl 操作浏览器和 ScriptCat 的命令用法

**坑**：`npx skills` 的有效 agent 名单里**没有 `workbuddy`**，对应的是 `codebuddy`。用 `-a workbuddy` 会静默装到错误位置。
装完实体通常在 `~/.codebuddy/skills/`。如果宿主读的是 `~/.workbuddy/skills/`，建目录联接保持单一数据源：

```powershell
New-Item -ItemType Junction -Path "$env:USERPROFILE\.workbuddy\skills\scriptcat-userscript" -Target "$env:USERPROFILE\.codebuddy\skills\scriptcat-userscript"
New-Item -ItemType Junction -Path "$env:USERPROFILE\.workbuddy\skills\sctl"               -Target "$env:USERPROFILE\.codebuddy\skills\sctl"
```

验证检查器可用（拿一个已有的 `.user.js` 跑）：

```bash
node "<SKILLS_DIR>/scriptcat-userscript/scripts/check.mjs" "<WORKSPACE>/some.user.js"
```

**新装的 skill 当次会话不加载，写脚本前开一个新会话。**

## 6. 安装 sctl（AI）

```powershell
irm https://raw.githubusercontent.com/scriptscat/sctl/main/scripts/install.ps1 | iex
$env:Path += ";$env:LOCALAPPDATA\sctl\bin"    # 仅当前窗口，立即生效
sctl version
```

官方安装脚本会下载 release zip、校验 SHA256、解压到 `%LOCALAPPDATA%\sctl\bin\sctl.exe`，但**不会修改 PATH**。
不需要管理员权限；PowerShell 执行策略为 `Restricted` 也不影响 `irm | iex`（内存执行）。

想永久生效，用 .NET 接口（避免 `setx` 的 1024 字符截断，也别照抄安装脚本提示里的双分号）：

```powershell
$d = "$env:LOCALAPPDATA\sctl\bin"
$p = [Environment]::GetEnvironmentVariable('Path','User')
if ($p -notlike "*$d*") { [Environment]::SetEnvironmentVariable('Path', ($p.TrimEnd(';') + ';' + $d), 'User') }
```

## 7. 注册后台服务（AI；被拦则交用户）

```powershell
sctl service install
sctl service status
```

正常输出含 `daemon running at 127.0.0.1:8643` 与 `starts at login`。它是**当前用户级计划任务**（登录时自启），不需要管理员。

- **不要**同时手动 `sctl serve`，两者会抢 8643。
- **不要**在 AI 会话里临时起服务：会话结束进程会被回收。
- 某些 AI 会话把 `schtasks.exe` 列入安全黑名单，此时直接转给用户并说明原因，**不要重试、不要找等价绕过**。

## 8. 启动浏览器（AI；需用户已授权代启）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "<EDGEAGENT_DIR>\start-agent-edge-detached.ps1"
```

**为什么不能直接在 AI 会话里 `Start-Process`**：实测窗口和 CDP 当场都正常，但命令一结束进程就被回收，下一条命令里 PID 已消失。让系统 shell 执行快捷方式（ShellExecute）后，Edge 归属桌面 shell，能跨命令稳定存活。

判断存活必须在**另一条独立命令**里做：

```powershell
(Invoke-WebRequest 'http://127.0.0.1:9222/json/version' -UseBasicParsing -TimeoutSec 3 -Proxy $null).Content
# 应返回 "Browser": "Edg/157..."
```

脚本是幂等的：CDP 已就绪时不会重复开窗。

## 9. 核对运行副本（AI）

第 4 步已把 `scripts/` 的 5 个文件放到 `<EDGEAGENT_DIR>\`；这里核对运行副本与仓库模板一致，快捷方式和 `mcp.json` 引用的都是这份。`config/package*.json` 用于锁定 MCP 版本。

独立配置目录 `profile\` 不进版本库、不跨机器复制。

---

## 10–12. 必须由用户完成（一次性列全）

| # | 操作 | 验收 |
| --- | --- | --- |
| 10 | 连接器管理页右上「自定义连接器」→ 对 `chrome-devtools` 点**信任**；必要时重启宿主 | 出现 `mcp__chrome-devtools__*` 工具组 |
| 11 | 在 **EdgeAgent 窗口**装 ScriptCat 和需要的扩展、登录目标网站；ScriptCat 工具 → 外部接入 → 打开开关（保持 `ws://127.0.0.1:8643`）、选择权限策略 | 扩展页可见、开关已开 |
| 12 | 终端 `sctl connect` → 把 8 位码输入**该窗口**的 ScriptCat「重新接入 / Enroll」 | `sctl status` → `extension connected: true` |

配对码 2 分钟有效、只显示一次、不进对话也不进日志；过期重跑 `sctl connect`。
**日常 Edge 里的 ScriptCat 不要也 Enroll**，避免两个实例连同一个 `sctl serve`，导致 `scripts_*` 写到正在用的那套脚本上。真要两个都连，用 `--scriptcat <name>` 显式指定并用 `sctl scriptcats` 核对。

## 13. 端到端验收（AI）

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File "<EDGEAGENT_DIR>\doctor.ps1"
node "<EDGEAGENT_DIR>\probe-mcp.mjs"
sctl status; sctl scriptcats; sctl get; sctl browsers
```

然后让 AI 实际调 MCP 工具：`list_pages` → `take_snapshot` → `evaluate_script` → `take_screenshot` → `navigate_page`。
只做 `initialize` 握手不算验收通过。

参考值（2026-11-07 实测环境）：`doctor.ps1` 30 项通过 / 0 警告 / 0 失败；`probe-mcp.mjs` 拿到 37 个工具（含 5 个扩展工具）、`RESULT: PASS`；`sctl get` 能列出脚本；`sctl browsers` 为空。

## 快速复验（环境已经在跑时）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\EdgeAgent\doctor.ps1"
node "%USERPROFILE%\EdgeAgent\probe-mcp.mjs"
sctl status
```

| 现象 | 结论 |
| --- | --- |
| `doctor.ps1` 失败 0 | 静态配置正常 |
| `probe-mcp.mjs` → `RESULT: PASS` | MCP 与 CDP 通路正常，不依赖宿主是否加载工具 |
| `sctl status` → `extension connected: true` | ScriptCat 配对正常 |
| `Invoke-WebRequest http://127.0.0.1:8643/` → `426 Upgrade Required` | **正常**，这是 WebSocket 端点 |
