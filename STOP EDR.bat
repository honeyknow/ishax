@echo off
title ISHA-X EDR - Stop
color 0C
setlocal
cd /d "%~dp0"

echo.
echo ============================================================
echo  ISHA-X EDR - Server Stack Teardown
echo ============================================================
echo  Project root : %~dp0
echo.

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [FATAL] PowerShell is not available on this system.
    pause
    exit /b 1
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0server\start_local.ps1" -Stop
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo [WARN] Stop script returned exit code %EXITCODE%.
    echo        Check running Python, Node, and Docker processes manually if needed.
) else (
    echo [STOPPED] Stop sequence complete.
)
echo ============================================================
pause
exit /b %EXITCODE%
