@echo off
rem Wrapper so the build can be started by double-click or from cmd.exe.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build-windows.ps1" %*
if errorlevel 1 pause
