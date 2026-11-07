# 排障速查表

> 按「现象 → 原因 → 处理」组织。都是实机踩过的，遇到时**先查表，不要自己发明新方案**。

## 浏览器 / CDP

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 默认 Edge 上 `--remote-debugging-port` 无效 | Chromium 136+ 对默认 `user-data-dir` 直接忽略调试端口 | 必须指定独立 `--user-data-dir`；对应地，扩展和网站登录要在新 profile 里重做一次 |
| AI 会话里 `Start-Process` 启动 Edge，下一条命令 PID 就没了 | 子进程归属 AI 会话进程树，命令结束被回收 | 让系统 shell 执行快捷方式（ShellExecute / `explorer.exe <lnk>`），进程归桌面 shell；用 `start-agent-edge-detached.ps1` |
| `schtasks.exe` 被拒绝 | 部分 AI 会话把计划任务列入安全黑名单 | 不重试、不绕行，转给用户或用系统 shell 方案 |
| 9222 端口在监听，但 MCP 连不上 | 占用端口的不是 CDP 服务 | `curl http://127.0.0.1:9222/json/version` 看有没有 `"Browser"` 字段；启动器已内置这项握手检测 |
| `list_extensions` 说没装扩展，profile 里却有扩展目录 | 那些是 Edge 内置组件 | 别据此判断扩展已装，去 `edge://extensions` 看 |
| 重启宿主后 MCP 工具组消失 | 信任记录按**整份服务配置的 sha256 指纹**存于 `mcp-approvals.json`；改过 `mcp.json` 任意一处（增删参数、换路径、删一个冗余键）指纹就变，且**当前进程不受影响，要等下次启动才失效**，极易隔很久才被发现 | 连接器管理页重新点「信任」，**点完当场生效、不必重启**；核对 `mcp.json` 与 `mcp-approvals.json` 的 `LastWriteTime`，审批早于修改即命中。宿主自身更新**不会**让信任失效，别当成更新后的固定动作 |
| `take_screenshot` 写文件被拒 | 目标目录不在 `--workspace` 白名单 | 在 `mcp.json` 的 args 里加 `--workspace=<dir>`（可多次） |
| 截图报「超出图像大小限制」 | 图像 token 数跟**像素尺寸**挂钩，不是字节数 | 加 `--screenshotMaxWidth=1280` 比降 JPEG 质量更有效；完整参数见 [`mcp-parameters.md`](mcp-parameters.md) |
| 访问 `127.0.0.1:9222` 返回 502 | 机器设了 `http_proxy`，本地请求被送去代理 | curl 用 `--noproxy '*'`；PowerShell 用 `-Proxy $null`；`mcp.json` 的 `env` 设 `NO_PROXY` |
| 改了 `--workspace` 等参数没生效 | 连接 / 启动相关参数不能热更新 | 重启 MCP 进程；`--watchConfig` 只热更新工具开关 |
| 打不开 `chrome-extension://` 页面 | 报 `... is not allowed without --categoryExtensions` | 加 `--categoryExtensions`。它还有第二个作用：允许导航到扩展页，不只是启用扩展工具 |
| `msedge.exe --version` 弹出一个完整浏览器窗口、stdout 0 字节 | GUI 子系统程序没有控制台可写，`--version` 输出丢失但进程照常启动 | 别用这个查版本；读版本目录名，或用 `(Get-Item <exe>).VersionInfo.ProductVersion` |
| 重装浏览器后桌面快捷方式消失 | 重装会清理 `.lnk`，但不动 `--user-data-dir` 指向的 profile | 重跑一次 `make-shortcut.ps1` |
| 找不到 `msedge.exe` / `chrome.exe` | 用户级装在 `%LOCALAPPDATA%`，系统级装在 `%ProgramFiles%`（32 位更新器还可能落在 `Program Files (x86)`） | 三处依次探测，别把路径写死 |
| 第二个浏览器进程自己退出、调试端口没重复开 | 同一 `--user-data-dir` 有单实例锁，URL 被转发给已有实例 | 一个 profile 同时只跑一个主进程 |
| 9222 显示 LISTENING 但 MCP 连不上，占用者是残留主进程 | 僵尸进程树还占着端口 | `Get-CimInstance Win32_Process -Filter "Name='msedge.exe'"` 找主进程（`CommandLine` 不含 `--type=`），确认后 `taskkill /PID <pid> /T /F` |
| 换了机器后 profile 里的登录态全部失效 | Cookie 用 DPAPI / App-Bound Encryption 加密，绑定 Windows 用户账户（部分版本还绑 exe 路径） | 同机同账户复制有效，**跨机器 / 跨账户一定解不开**；别把 `profile\` 当可迁移备份 |
| 确实要重建 profile | 里面有登录态、Cookie、扩展和脚本 | 用回收站删（`Microsoft.VisualBasic.FileIO.FileSystem::DeleteDirectory` + `RecycleOption.SendToRecycleBin`），**删完就停手，不要清空回收站** |

## sctl / ScriptCat

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| 装完 `sctl` 提示「无法将 sctl 识别为 cmdlet」 | 官方安装脚本**不修改 PATH** | 当前窗口 `$env:Path += ";$env:LOCALAPPDATA\sctl\bin"`；永久生效用 .NET `SetEnvironmentVariable` |
| 官方提示的 `setx PATH "...WindowsApps;;..."` | 原 user PATH 末尾带空项，拼出了双分号 | 别照抄，用 `TrimEnd(';')` 处理 |
| `netstat` / `Get-NetTCPConnection` 查不到 8643，服务却明明在跑 | 该端口是 WebSocket 端点，某些会话的 TCP 表不可见 | `Invoke-WebRequest http://127.0.0.1:8643/` 返回 **`426 Upgrade Required` 就是正常**，别据 TCP 表误判 |
| `sctl connect` 报 daemon unreachable | 后台服务没起来 | `sctl service start`，再 `sctl service status` |
| 配对码过期 / 输错 | 2 分钟有效、一次性 | 重新跑 `sctl connect`；配对码只显示在终端，不进对话、不进日志 |
| `sctl status` 一直 `extension connected: false` | 外部接入没开 / 码输到了别的 ScriptCat 实例 | 确认是 **EdgeAgent 窗口**的 ScriptCat；检查开关地址 `ws://127.0.0.1:8643`；核对 `sctl scriptcats` |
| `scripts_*` 改到了正在用的脚本 | 两个 ScriptCat 实例（日常 Edge 也 Enroll 了）连同一个 `sctl serve` | 日常 Edge 的 ScriptCat 不要 Enroll；两个都要连就用 `--scriptcat <name>` 显式指定 |
| `sctl run --help` → `unknown command "run" for "sctl"` | `run` / `logs` 要求 sctl **> 0.3.0** 且 ScriptCat **> 1.5.0** | 当前版本没这条链路；退路见下 |
| 脚本日志读不到 | 同上，且 `scripts_run` 不支持页面脚本 | 页面脚本走 MCP 的 `list_console_messages` / `list_network_requests`；后台脚本让脚本 `GM_log`，再用 CDP MCP 打开 ScriptCat 日志扩展页 + `take_snapshot` |
| `sctl --help` 里列着 `tabs` / `page` / `debug` / `cdp` / `cookies` | 这些是给 **sctl Browser 扩展**用的 | 本方案不装该扩展，这些命令用不了，别误以为能力已在 |

## AI skill / 宿主

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `npx skills add ... -a workbuddy` 装完宿主读不到 | `npx skills` 有效名单里**没有** `workbuddy` | 用 `-a codebuddy`；再用 Junction 把实体暴露给宿主实际读取的 skills 目录 |
| 新装的 skill 不生效 | 当次会话不加载新 skill | 开一个新会话 |
| `browser use` 返回两个同名 Edge | 宿主扩展同时装在日常 profile 和开发 profile | 每次任务重新 `browsers_list` + `user_open_tabs`，按标签页内容区分；**id 不固定** |
| `type: desktop` 没有日常登录态 | 那是宿主内置浏览器（IAB），只有当前会话标签页 | 选 `type: extension` |
| `evaluate_script` 看不到脚本里的变量 / `GM_*` | 跑在**页面主世界**，脚本猫在 isolated world | 让脚本自己 `GM_log` / `console.log` 输出 |
| PowerShell 里 `New-Object -ComObject` / `Add-Type` 被拒绝 | 部分 AI 客户端的安全策略限制主会话 | 把逻辑写成 `.ps1` 文件，用子进程执行：`powershell -NoProfile -ExecutionPolicy Bypass -File <script.ps1>` |

## 编码 / 配置

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| `.bat` 中文乱码或无法执行 | 编码不对 | 纯 ASCII + UTF-8 无 BOM + CRLF |
| `doctor.ps1` 中文注释乱码 | PowerShell 5.1 需要 BOM | UTF-8 **带 BOM** + CRLF |
| PowerShell 报「重复的键」 | `env` 里同时写了 `NO_PROXY` 和 `no_proxy` | Windows 环境变量名大小写不敏感，**只留一个** |
| `mcp.json` 里的 node.exe 找不到 | 宿主升级后托管 Node 的版本号目录变了 | 重新 `where.exe node`，改 `command` 后重新点信任 |
| MCP 启动即报未知参数 | `chrome-devtools-mcp` 升级导致参数漂移 | `npm install chrome-devtools-mcp@1.12.0 --save-exact` 锁版本；或对照 `--help` 改参数 |

## 三分钟快速复验

```bash
# 1) 静态自检（应「通过 N 项 / 警告 0 项 / 失败 0 项」）
powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\EdgeAgent\doctor.ps1"

# 2) 不依赖宿主是否加载工具，直接验 MCP ↔ CDP 握手
node "%USERPROFILE%\EdgeAgent\probe-mcp.mjs"
#   期望 initialize -> chrome_devtools@1.12.0、工具列表含扩展工具、RESULT: PASS

# 3) sctl 链路
sctl status        # extension connected: true / scriptcat: online
sctl scriptcats    # 已配对的实例
sctl get           # 能列出脚本
sctl browsers      # 本方案应为空
```

再让 AI 实际调一次 `list_pages` + `take_snapshot`：只做 `initialize` 握手不算验收通过。

## 维护本仓库时的网络问题

| 现象 | 原因 | 处理 |
| --- | --- | --- |
| AI 会话里 `git push` 报 `Empty reply from server` | 会话注入了 `http_proxy`，git 走该代理时 `CONNECT github.com:443` 握手失败；去掉代理后直连 `github.com:443` 又超时 | **不要反复重试 push**。在普通终端里推；或若 `api.github.com` 可直连，改走 GitHub REST / Git Data API（逐文件建 blob → tree → commit → 更新 `refs/heads/main`） |
| 用 Git Data API 给空仓库建 blob 报 `409 Git Repository is empty` | 空仓库的对象库尚未初始化 | 先用 Contents API 写入一个文件（如 README）激活仓库，再建 blob |
| API 发布后本地 `git log` 与远端 HEAD 的 SHA 不一致 | GitHub 规范化了 commit 元数据，但**文件树哈希一致**、内容完全相同 | 在能连通 `github.com` 的终端里执行一次 `git pull --rebase` 对齐历史，之后正常 `git push` |

发布 / 维护脚本里会读取本地凭证，**这类脚本一律不进仓库、不打印凭证值、完成后删除**。往公开仓库提交前按 `SKILL.md` 的脱敏红线逐条核对。

## 上报问题时该给什么

- `doctor.ps1` 完整输出、`probe-mcp.mjs` 输出、`sctl status` 输出
- Edge 版本、Node 版本、`chrome-devtools-mcp` 版本、sctl 版本、ScriptCat 版本
- 具体是哪一条链路断了（CDP 9222 / sctl 8643 / browser use 扩展桥接）
- **不要**贴 `control.token`、配对码、Cookie、脚本源码或含密钥的日志
