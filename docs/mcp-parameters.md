# chrome-devtools-mcp CLI 参数速查

> 来源：`node <entry> --help` 实测输出，对应 **chrome-devtools-mcp 1.12.0**。
> 参数名和默认值会随小版本漂移，升级后**必须重新跑一次 `--help`** 再对照本文。
> 另见 [`troubleshooting.md`](troubleshooting.md) 里与参数相关的具体故障。

## 连接方式（四选一）

| 参数 | 说明 |
| --- | --- |
| `-u, --browserUrl <url>` | 接管已开调试端口的实例，如 `http://127.0.0.1:9222`。**本方案用的就是它** |
| `-w, --wsEndpoint <ws>` | 直连 WebSocket，如 `ws://127.0.0.1:9222/devtools/browser/<id>` |
| `--autoConnect` | 自动连接本地 Chromium（144+），需先在 `chrome://inspect/#remote-debugging` 打开开关 |
| `--isolated` | 起临时 user-data-dir，关闭后自动清理。**做实验时用它，不污染正式 profile** |

`--browserUrl` / `--wsEndpoint` / `--autoConnect` 互斥；都不给则 MCP 自己拉起一个全新浏览器，**登录态和扩展都不在**，正是本方案要避免的。
`--categoryPwa` 只支持 pipe 连接，与 `--autoConnect` / `--browserUrl` / `--wsEndpoint` 不兼容。

## 工具集裁剪

| 参数 | 说明 |
| --- | --- |
| `--slim` | 只暴露 3 个工具（导航 / 执行脚本 / 截图），省上下文 |
| `--categoryExtensions` | 扩展工具 + 允许 `chrome-extension://` 导航（**双作用，见下**） |
| `--no-category-<name>` | 关掉某类工具：`input` / `navigation` / `emulation` / `performance` / `network` / `debugging` / `memory` |
| `--experimentalIncludeAllPages` | 把 webview、background pages 也算作 page |
| `--experimentalDevtools` | 允许自动化 DevTools UI 本身 |
| `--experimentalVision` | 开放坐标点击类工具（`click_at(x,y)`），需要能看图的模型 |

**`--categoryExtensions` 有两个作用**，`--help` 只写了第一个：

1. 启用扩展相关工具（安装 / 重载 / 触发扩展 action）。
2. 允许导航到 `chrome-extension://` URL —— 源码的导航校验会把 `categoryExtensions` 传给 `isAllowedUrl()`，不开就报 `Navigating to chrome-extension: URLs is not allowed without --categoryExtensions.`

要打开扩展页（例如 ScriptCat 的 `install.html` 或日志页）时，这个参数是必需的，不是可选项。

## 文件与路径

| 参数 | 说明 |
| --- | --- |
| `--wsHeaders` | 自定义 WebSocket 请求头（JSON），**只有长参数**。`-w` 是 `--wsEndpoint` 的短参数，与它无关；只能配 `--wsEndpoint` 用 |
| `--workspace <dir>` / `--filesystemRoot` | 允许读写的目录，**可重复**；默认只有 OS 临时目录 |
| `--fileNavigations` | 默认 true；设 false 禁止导航到 `file:` URL |
| `--logFile <path>` | 调试日志写文件，配合 `NODE_DEBUG=*` 看详细过程 |

截图报 `not within any of the configured workspace roots` 就是没配 `--workspace`。
**改 `mcp.json` 的命令行参数一律要重启 MCP 进程才生效**；`--watchConfig` 只能热更新工具开关，连接 / 启动相关参数仍需重启（`--help` 原文：`options used to launch or connect to the browser still require a restart`）。`--allowUnrestrictedPaths` 已 deprecated，官方建议用 `--workspace=/`（仅可信环境）。

控制截图体积与上下文占用：

| 参数 | 作用 |
| --- | --- |
| `--screenshotFormat` | `png`（默认）/ `jpeg` / `webp`，后两者体积小 3–5 倍 |
| `--screenshotQuality` | JPEG/WebP 压缩质量 0–100 |
| `--screenshotMaxWidth` / `--screenshotMaxHeight` | 最大宽高，超出等比缩小 |

遇到「截图超出图像大小限制」时，加 `--screenshotMaxWidth=1280` 比降格式质量更有效——图像 token 数跟**像素尺寸**挂钩，不是字节数。

## 网络与安全

| 参数 | 说明 |
| --- | --- |
| `--blockedUrlPattern` | 按 URL Pattern 屏蔽访问（黑名单） |
| `--allowedUrlPattern` | 只允许匹配的 URL（白名单，需 Chromium 149+） |
| `--redactNetworkHeaders` | 返回网络请求前脱敏敏感 header |
| `--javascriptEvaluation` | 默认 true；设 false 禁用 `evaluate_script`，并禁止 `javascript:` / `data:` / `vbscript:` 导航 |
| `--acceptInsecureCerts` | 忽略自签 / 过期证书错误 |
| `--no-usage-statistics` | 关闭使用统计；环境变量 `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS` 或 `CI` 也会自动关闭 |
| `--no-performance-crux` | 不把 trace 里的 URL 发给 CrUX 查真实性能数据 |

## 行为微调

| 参数 | 说明 |
| --- | --- |
| `--no-page-id-routing` | 不让每个工具调用都必须带 `pageId`（单会话更顺手） |
| `--maxNavigationSaved <1-25>` | 每页保留多少次导航的网络 / 控制台记录，默认 3 |
| `--viewport <WxH>` | MCP **自己启动**浏览器时的初始视口；接管已有实例时无效 |
| `--headless` | 无头模式；接管已有实例时无效 |
| `--config <json>` + `--watchConfig` | 用配置文件代替命令行，支持热更新工具开关 |
| `--sourceMaps` / `--no-source-maps` | 是否启用 source map |

## 代理相关

机器设了 `http_proxy` 时，访问 `127.0.0.1:9222` 会走代理并返回 **502**：

- curl：`--noproxy '*'`
- `mcp.json`：`env` 里设 `NO_PROXY`（**只留一个键**，见 troubleshooting）
- 脚本：`NO_PROXY=127.0.0.1,localhost`

PowerShell 里用 `Invoke-WebRequest` 探测本地端点时也要带 `-Proxy $null`。
