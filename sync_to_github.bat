@echo off
title FFRS Modpack Live Sync to GitHub
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0sync_to_github.ps1"
echo.
pause
