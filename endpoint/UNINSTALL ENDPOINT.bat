@echo off
title ISHA-X EDR - Endpoint Uninstall
color 0C
setlocal
cd /d "%~dp0"

echo.
echo ============================================================
echo  ISHA-X EDR - Endpoint Uninstaller
echo ============================================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Requesting Administrator rights...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

if not exist "%~dp0uninstall_endpoint.ps1" (
    echo [FATAL] Missing uninstall_endpoint.ps1.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0uninstall_endpoint.ps1"
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo [WARN] Uninstaller returned exit code %EXITCODE%.
) else (
    echo [DONE] Endpoint uninstall sequence completed.
)
echo ============================================================
pause
exit /b %EXITCODE%
