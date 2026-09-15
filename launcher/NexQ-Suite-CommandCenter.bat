@echo off
setlocal
set "SCRIPT=%~dp0NexQ-Suite-CommandCenter.ps1"
if not exist "%SCRIPT%" (
  echo Command Center script not found: %SCRIPT%
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
endlocal
