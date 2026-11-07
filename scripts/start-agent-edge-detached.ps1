# AI-side launcher: let the desktop shell execute the shortcut so that the
# browser process does NOT belong to the agent session job (see docs/deployment-guide.md (step 8)).
param([int]$WaitSeconds = 25)

$ErrorActionPreference = 'Continue'
$lnk = Join-Path $PSScriptRoot 'Start Agent Edge (ai).lnk'
if (-not (Test-Path $lnk)) {
  throw "AI launcher shortcut missing: $lnk  (run make-shortcut.ps1 first)"
}

try {
  $v = Invoke-WebRequest -Uri 'http://127.0.0.1:9222/json/version' -UseBasicParsing -TimeoutSec 2 -Proxy $null
  if ($v.Content -match '"Browser"') {
    Write-Output 'CDP already ready on 127.0.0.1:9222 - no new window opened.'
    exit 0
  }
} catch { }

Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $lnk + '"')

for ($i = 0; $i -lt $WaitSeconds; $i++) {
  Start-Sleep -Seconds 1
  try {
    $r = Invoke-WebRequest -Uri 'http://127.0.0.1:9222/json/version' -UseBasicParsing -TimeoutSec 2 -Proxy $null
    if ($r.Content -match '"Browser"') {
      Write-Output 'CDP ready on 127.0.0.1:9222 - Edge is alive outside the agent session.'
      exit 0
    }
  } catch { }
}
Write-Output "CDP did not come up within $WaitSeconds seconds."
exit 1
