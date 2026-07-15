@echo off
title ISHA-X EDR - Start
color 0B
setlocal enabledelayedexpansion
cd /d "%~dp0"

set "ROOT=%~dp0"
set "BACKEND_PORT=8000"
set "FRONTEND_PORT=5173"

echo.
echo ============================================================
echo  ISHA-X EDR - Server Stack Startup
echo ============================================================
echo  Project root : %ROOT%
echo  Dashboard    : http://localhost:%FRONTEND_PORT%
echo  API health   : http://localhost:%BACKEND_PORT%/health
echo ============================================================
echo.

where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [FATAL] PowerShell is not available on this system.
    pause
    exit /b 1
)

where docker.exe >nul 2>&1
if errorlevel 1 (
    echo [FATAL] Docker was not found in PATH. Install Docker Desktop first.
    pause
    exit /b 1
)

where python.exe >nul 2>&1
if errorlevel 1 (
    echo [FATAL] Python was not found in PATH. Install Python 3.10+ first.
    pause
    exit /b 1
)

where npm.cmd >nul 2>&1
if errorlevel 1 (
    where npm.exe >nul 2>&1
    if errorlevel 1 (
        echo [FATAL] npm was not found in PATH. Install Node.js LTS first.
        pause
        exit /b 1
    )
)

echo [INFO] Starting local lab services...
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%ROOT%server\start_local.ps1" -BackendPort %BACKEND_PORT% -FrontendPort %FRONTEND_PORT%
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo ============================================================
    echo  [FAILED] Startup did not complete cleanly.
    echo  Check these logs:
    echo    server\pipeline\ingestor.log
    echo    server\backend\backend.log
    echo    server\frontend\frontend.log
    echo ============================================================
    pause
    exit /b %EXITCODE%
)

echo ============================================================
echo  [READY] ISHA-X EDR is running.
echo  Dashboard : http://localhost:%FRONTEND_PORT%
echo  API       : http://localhost:%BACKEND_PORT%/health
echo  Stop      : STOP EDR.bat
echo ============================================================
pause
exit /b 0
