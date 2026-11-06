@echo off
rem CrossPet Windows development launcher: build + stage + run from this checkout.
rem Double-click, or run from a terminal: dev.cmd -Reset -NoBuild -Inspect
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\dev-windows.ps1" %*
if errorlevel 1 pause
