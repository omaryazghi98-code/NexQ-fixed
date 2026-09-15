@echo off
setlocal
set "SCRIPT=%~dp0Launch-NexQSuite.ps1"
if not exist "%SCRIPT%" (
  echo Launcher script not found: %SCRIPT%
  pause
  exit /b 1
)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
endlocal
