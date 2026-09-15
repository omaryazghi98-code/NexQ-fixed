@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-NexQSuiteAgent.ps1" %*
endlocal
