# 架构与选型

## 一条主线，三个组件

这套环境只为一件事服务：**写 / 装 / 调试油猴脚本**。把这件事拆成「管脚本」「看页面」两类互不干扰的操作。

| 组件 | 所在 profile | 通道 | 干什么 |
| --- | --- | --- | --- |
| `chrome-devtools-mcp` 1.12.0 | 开发用 `EdgeAgent` 独立 profile | CDP `9222` | 页面深度调试：DOM / a11y / console / network / 截图 / 执行 JS / 性能 trace / 堆快照 / Lighthouse / 扩展页 DOM |
| `sctl` + ScriptCat「外部接入」 | 同一个 `EdgeAgent` profile | WebSocket `8643` | 脚本管理：列出 / 读源码 / 安装 / 编辑 / 启停 / 删除 |
| 官方 skill `scriptcat-userscript`、`sctl` | 用户级 skills 目录 | 本地文件 | 写法规则、骨架、静态检查器；sctl 命令用法 |

两条通道端口和机制都不同，**可以同时运行**；但同一任务里不要混用工具链。

## 两个 profile，为什么

Chromium 136+ 起，对**默认** `user-data-dir` 会忽略 `--remote-debugging-port`。想让 CDP 可用，就必须给开发浏览器一个独立 `--user-data-dir`。

于是自然形成两个 profile：

- **`EdgeAgent`**：全新、干净、带 9222。装 ScriptCat 和调试用的扩展，登录测试网站。脚本、扩展、Cookie 全部持久化在 `EdgeAgent\profile\`。
- **日常 Edge**：不带调试端口，保留原有登录态 / 书签 / 扩展，日常上网用，不接入本方案的工具链。

> 独立 profile 是「全新」的，所以扩展和网站登录要在那个窗口里**做一次**。之后长期保留。
> 反过来也别把 `EdgeAgent\profile` 当成干净沙箱：如果你往里装了脚本，它里面就是有生产脚本的，所有 `scripts_*` 写操作都会作用在它们身上。

## 为什么不装 sctl Browser

脚本猫配套有两个不同的东西，容易混：

| | ScriptCat「外部接入」 | sctl Browser 扩展 |
| --- | --- | --- |
| 管什么 | **脚本本身**（列出 / 读源码 / 安装 / 编辑 / 启停 / 删除） | **浏览器本身**（标签页 / 页面自动化 / console / network / Cookie / 书签） |
| 机制 | 扩展消息 ↔ `sctl serve` | 部分能力用 `chrome.debugger` 附着标签页 |
| 与 CDP MCP | 不冲突 | **对同一 target 互斥** |
| 本方案 | 必装 | **不装** |

理由：

1. CDP MCP 已覆盖并**超过** sctl Browser 的页面侧能力（快照 / 点击 / 填入 / 截图 / console / 网络请求 / 执行 JS），还多出性能 trace、堆快照、Lighthouse、扩展页 DOM。
2. sctl Browser 的 `page` / `debug` / `cdp` 会 attach `chrome.debugger`，浏览器顶部弹「正在调试」信息栏，5 分钟空闲自动断开；与 CDP MCP 抢同一标签页。不装就彻底消掉这个冲突。
3. 让出的只有书签 / 历史 / 下载 / Cookie 管理 / tab group——本就属于日常浏览器。

**安全模型也相反**，值得留意：

- sctl Browser 官方说明里绝大多数操作**立即执行、无确认**，可读 Cookie、历史、未遮罩的请求头与正文，官方自己建议「考虑用单独的浏览器 profile」。
- ScriptCat 外部接入默认每次读源码 / 写脚本都弹浏览器确认页；若把策略改成「直接允许」，等于外部程序可无确认修改脚本。
- CDP MCP 同样是全权限无确认，但它绑在独立 profile 上，天然隔离。

## 写脚本的验证闭环

```
1. scripts_install_request / scripts_edit_request   装或改脚本
     └ 若权限策略=需人工审批，确认页由用户点，不要循环重试
2. MCP navigate_page / new_page                    打开目标网址触发注入
     └ 页面脚本不能用 scripts_run 跑（官方限制）
3. MCP take_snapshot / list_console_messages /
        list_network_requests                      观察脚本对页面的实际效果
4. 脚本内部状态 → 让它自己 GM_log / console.log，再从 console 读
     └ evaluate_script 在「页面主世界」，看不到 isolated world 的变量和 GM_* API
5. 后台 / 定时脚本日志：受版本门槛限制，见 troubleshooting.md
```

版本门槛：`sctl run` / `scripts_logs` 要求 sctl **> 0.3.0** 且 ScriptCat **> 1.5.0**。实测 0.3.0 的 `--help` 里根本没有 `run` / `logs`，ScriptCat 1.5.0 恰在边界上，因此这条链路当时不可用。退路是让脚本 `GM_log`，再用 CDP MCP 打开 ScriptCat 的日志扩展页（靠 `--categoryExtensions`）配合 `take_snapshot` 读取。

## 安全边界

- 不外传登录态、Cookie、`%LOCALAPPDATA%\sctl\control.token`、配对码。
- 读到的脚本源码可能含 API key / Cookie，不写进日志、不进对话、不进公开仓库。
- `profile\` 目录不备份到公开仓库、不跨机器复制。
- 写操作前说明目标脚本，不做批量改动；权限策略由用户决定，AI 不擅自改。
- 用户未授权时不代启浏览器；重启前若窗口有未提交内容，先提示。
