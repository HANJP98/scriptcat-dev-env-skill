# ================================================================
#  Edge DevTools MCP - 一键自检
#  只读脚本：不启动、不杀死任何进程，只做检查并输出结论。
#  用法：
#    powershell -NoProfile -ExecutionPolicy Bypass -File "%USERPROFILE%\EdgeAgent\doctor.ps1"
# ================================================================
param([string]$Port = "9222")

$ErrorActionPreference = "Continue"
$root       = $PSScriptRoot
$mcpJson    = Join-Path $env:USERPROFILE ".workbuddy\mcp.json"
$profileDir = Join-Path $root "profile"
$outDir     = Join-Path $root "out"
$entryJs    = Join-Path $root "mcp\node_modules\chrome-devtools-mcp\build\src\bin\chrome-devtools-mcp.js"
$pkgJson    = Join-Path $root "mcp\node_modules\chrome-devtools-mcp\package.json"

$script:pass = 0
$script:fail = 0
$script:warn = 0

function Head($m) { Write-Host ""; Write-Host $m -ForegroundColor Cyan }
function Ok($m)   { Write-Host ("  [ok] " + $m) -ForegroundColor Green; $script:pass++ }
function Bad($m, $fix) {
  Write-Host ("  [X]  " + $m) -ForegroundColor Red
  if ($fix) { Write-Host ("       -> " + $fix) -ForegroundColor DarkGray }
  $script:fail++
}
function Warn($m, $fix) {
  Write-Host ("  [!]  " + $m) -ForegroundColor Yellow
  if ($fix) { Write-Host ("       -> " + $fix) -ForegroundColor DarkGray }
  $script:warn++
}

# 绕过系统代理取 CDP 信息（机器设了 http_proxy 时直连会很关键）
function Get-CdpContent([string]$Url) {
  $old = [System.Net.WebRequest]::DefaultWebProxy
  try {
    [System.Net.WebRequest]::DefaultWebProxy = New-Object System.Net.WebProxy
    $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
    return $r.Content
  } catch {
    return $null
  } finally {
    [System.Net.WebRequest]::DefaultWebProxy = $old
  }
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor White
Write-Host " Edge DevTools MCP 自检  ($(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
Write-Host "==============================================" -ForegroundColor White

# ---------- 1. mcp.json ----------
Head "[1] 配置文件 $mcpJson"
$cfg = $null
if (Test-Path $mcpJson) {
  try {
    $raw = Get-Content $mcpJson -Raw -Encoding UTF8
    $cfg = $raw | ConvertFrom-Json
    Ok "mcp.json 存在且 JSON 合法"
  } catch {
    $msg = $_.Exception.Message
    if ($msg -match '重复的键|duplicate') {
      Bad "mcp.json 含大小写不敏感的重复键，PowerShell 无法解析：$msg" "env 里别同时写 NO_PROXY 和 no_proxy —— Windows 环境变量名大小写不敏感，留一个即可（改完重启 WorkBuddy）"
    } else {
      Bad "mcp.json 不是合法 JSON：$msg" "用 JSON 校验器检查是否有中文引号或尾随逗号"
    }
  }
} else {
  Bad "mcp.json 不存在" "按 docs/deployment-guide.md 第 3 节创建"
}

$server = $null
if ($cfg -and $cfg.mcpServers -and $cfg.mcpServers.'chrome-devtools') {
  $server = $cfg.mcpServers.'chrome-devtools'
  Ok "存在服务条目 chrome-devtools"
} elseif ($cfg) {
  Bad "mcp.json 里没有 chrome-devtools 条目" "按 docs/deployment-guide.md 第 3 节补上；服务名必须叫 chrome-devtools"
}

# 信任指纹是按整份服务配置算的，改过 mcp.json 就得重新点信任（见 docs/troubleshooting.md）
if ($server) {
  $approvals = Join-Path (Split-Path $mcpJson -Parent) "mcp-approvals.json"
  $aprHit = $null
  if (Test-Path $approvals) {
    try {
      $aprRaw = (Get-Content $approvals -Raw -Encoding UTF8) | ConvertFrom-Json
      $aprHit = @($aprRaw.PSObject.Properties | Where-Object { $_.Name -match '::chrome-devtools$' }) |
        Sort-Object { [int64]$_.Value } | Select-Object -Last 1
    } catch { }
  }
  if ($aprHit) {
    $aprTime = [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$aprHit.Value).LocalDateTime
    $cfgTime = (Get-Item $mcpJson).LastWriteTime
    if ($cfgTime -gt $aprTime.AddSeconds(10)) {
      Warn ("mcp.json 比信任记录新 {0:N0} 分钟 —— 可能需要在连接器里重新点信任" -f ($cfgTime - $aprTime).TotalMinutes) `
        "连接器管理页右上角『自定义连接器』→ 对 chrome-devtools 点信任（见 docs/troubleshooting.md；点完当场生效，不用重启）"
    } else {
      Ok ("信任记录有效（{0:yyyy-MM-dd HH:mm:ss} 点过信任）" -f $aprTime)
    }
  } else {
    Warn "mcp-approvals.json 里找不到 chrome-devtools 的信任记录" `
      "连接器管理页右上角『自定义连接器』→ 对 chrome-devtools 点信任（见 docs/troubleshooting.md）"
  }
}

# ---------- 2. node ----------
Head "[2] Node 运行时"
$nodeExe = $null
if ($server -and $server.command) {
  $nodeExe = $server.command
  if (Test-Path $nodeExe) {
    Ok "command 指向的 node.exe 存在：$nodeExe"
    $v = (& $nodeExe -v) 2>$null
    if ($v -match '^v(\d+)\.(\d+)\.(\d+)') {
      $maj = [int]$Matches[1]; $min = [int]$Matches[2]
      $okVer = (($maj -eq 20 -and $min -ge 19) -or ($maj -eq 22 -and $min -ge 12) -or ($maj -ge 23))
      if ($okVer) {
        Ok "Node 版本 $v 满足 engines ^20.19.0 || ^22.12.0 || >=23"
      } else {
        Bad "Node 版本 $v 不满足 engines 要求（21.x 完全不支持）" "装 20.19+ / 22.12+ / 23+，再改 mcp.json 的 command"
      }
    } else {
      Warn "无法解析 Node 版本输出：$v"
    }
  } else {
    Bad "command 指向的 node.exe 不存在：$nodeExe" "WorkBuddy 升级过 Node 的话，版本号目录变了，见 docs/troubleshooting.md"
  }
} else {
  Bad "mcp.json 里缺少 command 字段" "按 docs/deployment-guide.md 第 3 节填写 node.exe 的绝对路径"
}

# ---------- 3. MCP 安装 ----------
Head "[3] chrome-devtools-mcp 安装"
if (Test-Path $entryJs) {
  Ok "入口文件存在"
  if (Test-Path $pkgJson) {
    try {
      $pkg = Get-Content $pkgJson -Raw -Encoding UTF8 | ConvertFrom-Json
      Ok "已安装版本 $($pkg.version)"
      $localPkg = Join-Path $root "mcp\package.json"
      if (Test-Path $localPkg) {
        $lp = Get-Content $localPkg -Raw -Encoding UTF8 | ConvertFrom-Json
        $dep = $lp.dependencies.'chrome-devtools-mcp'
        if ($dep -match '^[\^~]|^\*$|^>=') {
          Warn "package.json 里写的是范围版本 $dep，重装可能拉到新版。" "建议 npm install chrome-devtools-mcp@$($pkg.version) --save-exact 锁死"
        } else {
          Ok "版本已锁定为 $dep（重装可复现）"
        }
      }
    } catch {
      Warn "读不到 package.json 版本：$($_.Exception.Message)"
    }
  }
} else {
  Bad "入口文件缺失：$entryJs" "在 $root\mcp 里重新 npm install（见 docs/deployment-guide.md 第 2 节）"
}

# ---------- 4. 启动参数 ----------
Head "[4] 启动参数"
if ($server -and $server.args) {
  $args_ = @($server.args)
  $need = @{
    '--browserUrl'          = '接管已开调试端口的 Edge，缺了会自己拉起一个全新浏览器'
    '--no-page-id-routing'  = '每次调用都要带 pageId'
    '--categoryExtensions'  = '打不开 chrome-extension:// 页面，扩展工具不可用'
    '--no-usage-statistics' = '会向 Google 上报使用统计'
    '--no-performance-crux' = '会把 trace 里的 URL 发给 CrUX'
    '--workspace'           = '截图/导出会报 not within any of the configured workspace roots'
  }
  foreach ($k in $need.Keys) {
    $hit = $args_ | Where-Object { $_ -like "$k*" }
    if ($hit) {
      Ok "$k 已配置"
    } else {
      if ($k -eq '--workspace') { Bad "$k 缺失" $need[$k] } else { Warn "$k 缺失：$($need[$k])" }
    }
  }
  $ws = $args_ | Where-Object { $_ -like '--workspace=*' } | ForEach-Object { ($_ -split '=', 2)[1] }
  foreach ($w in $ws) {
    if (Test-Path $w) { Ok "workspace 目录存在：$w" }
    else { Warn "workspace 目录不存在：$w（不致命，但写文件时用不到它）" }
  }
  if ($server.env) {
    if ($server.env.NO_PROXY) { Ok "env.NO_PROXY = $($server.env.NO_PROXY)" }
    else { Warn "env.NO_PROXY 未设置" "机器设了 http_proxy 时连 9222 可能拿到 502" }
  }
} else {
  Warn "没有 args 字段，MCP 会用默认参数启动（通常不是你想要的）"
}

# ---------- 5. 调试端口 ----------
Head "[5] 调试端口 $Port"
$cdp = Get-CdpContent "http://127.0.0.1:$Port/json/version"
if ($cdp) {
  try {
    $j = $cdp | ConvertFrom-Json
    Ok "CDP 应答正常：$($j.Browser) / Protocol $($j.'Protocol-Version')"
  } catch {
    Warn "端口有应答但不是合法 JSON"
  }
} else {
  Bad "127.0.0.1:$Port 无 CDP 应答" "按 docs/deployment-guide.md 第 8 节启动（已授权时可由 AI 代启），或自己双击桌面 Start Agent Edge；若显示 LISTENING 却是别的程序占用，见docs/troubleshooting.md"
}

# ---------- 6. Edge 主进程 ----------
Head "[6] Edge 主进程"
$edgeMain = @(Get-CimInstance Win32_Process -Filter "Name='msedge.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' })
$hit = @($edgeMain | Where-Object { $_.CommandLine -match 'EdgeAgent' })
if ($hit.Count -gt 0) {
  Ok "找到带 EdgeAgent profile 的 Edge 主进程（PID $($hit[0].ProcessId)）"
  if ($hit[0].CommandLine -match "--remote-debugging-port=$Port") { Ok "命令行含 --remote-debugging-port=$Port" }
  else { Bad "命令行没有 --remote-debugging-port=$Port" "说明这个窗口不是用 start-agent-edge.bat 启动的" }
  if ($hit[0].CommandLine -match '--start-maximized') { Ok "带 --start-maximized（视口才够宽）" }
  else { Warn "没有 --start-maximized，视口可能偏小" }
  if ($hit[0].CommandLine -match '--user-data-dir=') { Ok "使用独立 --user-data-dir（Chromium 136+ 的硬性要求）" }
  else { Bad "没有 --user-data-dir，调试端口会被内核忽略" "必须通过 start-agent-edge.bat 启动" }
} elseif ($edgeMain.Count -gt 0) {
  Warn "有 $($edgeMain.Count) 个日常 Edge 主进程在跑，但没有一个使用 EdgeAgent\profile" "日常 Edge 不影响本方案；要被接管需启动 Start Agent Edge（已授权时可由 AI 代启，见 docs/deployment-guide.md 第 8 节）"
} else {
  Bad "没发现 Edge 主进程" "按 docs/deployment-guide.md 第 8 节启动（已授权时可由 AI 代启），或自己双击桌面 Start Agent Edge"
}

# ---------- 7. MCP 子进程 ----------
Head "[7] MCP 子进程（node）"
$nodeProc = @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -and $_.CommandLine -match 'chrome-devtools-mcp' })
if ($nodeProc.Count -gt 0) {
  Ok "找到 $($nodeProc.Count) 个 chrome-devtools-mcp 进程（PID $(($nodeProc | ForEach-Object { $_.ProcessId }) -join ',')）"
  $cl = $nodeProc[0].CommandLine
  if ($cl -match 'EdgeAgent') { Ok "命令行指向 EdgeAgent 下的入口脚本" }
  else { Warn "命令行不是 EdgeAgent 下的入口，可能加载了另一份安装" }
} else {
  Warn "当前没有 chrome-devtools-mcp 进程在跑" "若 MCP 工具不可用：重启 WorkBuddy，并在连接器管理页右上角『自定义连接器』里点信任"
}

# ---------- 8. 目录与写权限 ----------
Head "[8] 目录与写权限"
if (Test-Path $profileDir) { Ok "profile 目录存在：$profileDir" }
else { Warn "profile 目录还没生成" "让 AI 代启或双击快捷方式启动一次 Edge 就会创建" }

if (Test-Path $outDir) {
  try {
    $probe = Join-Path $outDir ".doctor-probe.tmp"
    "x" | Out-File -FilePath $probe -Encoding ASCII -NoNewline
    Remove-Item $probe -Force
    Ok "out 目录可写：$outDir"
  } catch {
    Bad "out 目录不可写：$($_.Exception.Message)" "检查磁盘权限/杀软"
  }
} else {
  Bad "out 目录不存在：$outDir" "mkdir `"$outDir`""
}

# ---------- 9. Edge 本体与持久化 ----------
Head "[9] Edge 可执行文件与持久化目录"
$edgeExe = @(
  (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
  (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
  (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\Application\msedge.exe")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if ($edgeExe) { Ok "Edge 可执行文件：$edgeExe" }
else { Bad "找不到 msedge.exe" "安装 Microsoft Edge" }

if (Test-Path (Join-Path $profileDir "Local State")) {
  Ok "profile 已初始化（Local State 存在，登录态与扩展会随 profile 持久保存）"
} else {
  Warn "profile 尚未初始化" "让 AI 代启或双击 Start Agent Edge 启动一次即可"
}
$extDir = Join-Path $profileDir "Default\Extensions"
if (Test-Path $extDir) {
  $n = @(Get-ChildItem $extDir -Directory -ErrorAction SilentlyContinue).Count
  Ok "扩展目录已生成，当前 $n 个扩展（在 Start Agent Edge 窗口里装的扩展会一直留着）"
} else {
  Warn "还没有扩展目录" "在 Start Agent Edge 窗口里安装扩展后自动生成；别用 Preferences 判断装没装上（见 docs/troubleshooting.md）"
}
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) "Start Agent Edge.lnk"
if (Test-Path $lnk) { Ok "桌面快捷方式存在：$lnk" }
else { Warn "桌面快捷方式不存在" "运行 make-shortcut.ps1 生成" }

# ---------- 汇总 ----------
Write-Host ""
Write-Host "==============================================" -ForegroundColor White
$color = if ($script:fail -eq 0) { "Green" } else { "Red" }
Write-Host (" 通过 $($script:pass) 项 / 警告 $($script:warn) 项 / 失败 $($script:fail) 项") -ForegroundColor $color
if ($script:fail -eq 0 -and $script:warn -eq 0) {
  Write-Host " 结论：一切正常，直接跟 agent 说需求即可。" -ForegroundColor Green
} elseif ($script:fail -eq 0) {
  Write-Host " 结论：能用，但有警告项建议处理。" -ForegroundColor Yellow
} else {
  Write-Host " 结论：有硬性失败项，先按上面的 -> 提示修。" -ForegroundColor Red
}
Write-Host "==============================================" -ForegroundColor White
Write-Host ""

if ($script:fail -gt 0) { exit 1 } else { exit 0 }
