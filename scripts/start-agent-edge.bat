@echo off
setlocal
title Start Agent Edge
rem ---------------------------------------------------------------
rem  Launch Microsoft Edge with a persistent, debuggable profile.
rem  chrome-devtools-mcp (WorkBuddy) attaches to 127.0.0.1:9222.
rem
rem  Profile: %USERPROFILE%\EdgeAgent\profile
rem  Logins and extensions live in that folder, so they survive restarts.
rem  A dedicated user-data-dir is REQUIRED on Chromium 136+ for CDP.
rem ---------------------------------------------------------------

set "PORT=9222"
set "PROFILE=%USERPROFILE%\EdgeAgent\profile"

set "EDGE="
if exist "%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe" set "EDGE=%ProgramFiles(x86)%\Microsoft\Edge\Application\msedge.exe"
if not defined EDGE if exist "%ProgramFiles%\Microsoft\Edge\Application\msedge.exe" set "EDGE=%ProgramFiles%\Microsoft\Edge\Application\msedge.exe"
if not defined EDGE if exist "%LOCALAPPDATA%\Microsoft\Edge\Application\msedge.exe" set "EDGE=%LOCALAPPDATA%\Microsoft\Edge\Application\msedge.exe"

echo.
echo   Edge       : %EDGE%
echo   Debug port : %PORT%
echo   Profile    : %PROFILE%
echo.

if not defined EDGE (
  echo   [X] Microsoft Edge not found. Install Edge first.
  goto :hold
)

netstat -ano | findstr ":%PORT% " | findstr "LISTENING" >nul 2>&1
if errorlevel 1 goto :launch

rem Listening is not enough - ask whether it is really a CDP endpoint.
where curl >nul 2>&1
if errorlevel 1 (
  echo   [i] Port %PORT% is listening and curl is unavailable - assuming Edge.
  goto :hold
)

curl -s --noproxy "*" --max-time 3 "http://127.0.0.1:%PORT%/json/version" | findstr /C:"Browser" >nul 2>&1
if not errorlevel 1 (
  echo   [ok] Port %PORT% already serves CDP - browser is ready.
  echo       Just talk to the agent, no need to start it again.
  goto :hold
)

echo   [!] Port %PORT% is LISTENING but does NOT answer CDP.
echo       Something else owns the port - the agent will NOT work.
echo       Fix the port conflict, or change PORT above.
goto :hold

:launch
if not exist "%PROFILE%" mkdir "%PROFILE%"

echo   Starting Edge ...
start "" "%EDGE%" --remote-debugging-port=%PORT% --user-data-dir="%PROFILE%" --profile-directory=Default --no-first-run --no-default-browser-check --start-maximized --disable-features=Translate about:blank

set "TRIES=0"
:wait
ping -n 2 127.0.0.1 >nul
netstat -ano | findstr ":%PORT% " | findstr "LISTENING" >nul 2>&1
if not errorlevel 1 goto :ready
set /a TRIES+=1
if %TRIES% lss 20 goto :wait

echo   [X] Port %PORT% did not come up in 20s.
echo       Check whether another Edge window uses the same profile.
goto :hold

:ready
echo   [ok] Debug port %PORT% is ready.
echo.
echo   Next: just ask the agent to use the browser.
echo   Log in / install extensions in THIS window - they persist in the profile above.

:hold
if /i not "%1"=="nopause" pause
endlocal
