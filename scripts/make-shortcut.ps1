param([string]$Name = "Start Agent Edge")

$ErrorActionPreference = "Stop"
$bat = Join-Path $PSScriptRoot "start-agent-edge.bat"
if (-not (Test-Path $bat)) { throw "launcher not found: $bat" }

$desktop = [Environment]::GetFolderPath('Desktop')
$lnk = Join-Path $desktop ($Name + ".lnk")

$edge = @(
  (Join-Path ${env:ProgramFiles(x86)} "Microsoft\Edge\Application\msedge.exe"),
  (Join-Path $env:ProgramFiles "Microsoft\Edge\Application\msedge.exe"),
  (Join-Path $env:LOCALAPPDATA "Microsoft\Edge\Application\msedge.exe")
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1

$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($lnk)
$s.TargetPath = $bat
$s.WorkingDirectory = $PSScriptRoot
if ($edge) { $s.IconLocation = "$edge,0" }
$s.Description = "Launch Edge with a debuggable, persistent profile (port 9222)"
$s.Save()

Write-Output "created: $lnk"
Write-Output "target : $bat"
Write-Output "icon   : $edge"

# AI-side launcher: same bat with nopause, hidden cmd, no lingering pause window.
$aiLnk = Join-Path $PSScriptRoot "Start Agent Edge (ai).lnk"
$ai = $sh.CreateShortcut($aiLnk)
$ai.TargetPath = $bat
$ai.Arguments = "nopause"
$ai.WorkingDirectory = $PSScriptRoot
if ($edge) { $ai.IconLocation = "$edge,0" }
$ai.WindowStyle = 7
$ai.Description = "AI-triggered launch (no pause) - see docs/deployment-guide.md (step 8)"
$ai.Save()
Write-Output "created: $aiLnk (nopause, hidden)"
