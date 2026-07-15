@echo off
title ISHA-X EDR - Endpoint Setup
color 0E
setlocal enabledelayedexpansion
cd /d "%~dp0"

echo.
echo ============================================================
echo  ISHA-X EDR - Endpoint Setup
echo ============================================================
echo  Installs Sysmon, Wazuh Agent, and AMSI ETW watcher.
echo  This launcher works from any extracted endpoint folder path.
echo ============================================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [INFO] Requesting Administrator rights...
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "MISSING=0"
if not exist "%~dp0endpoint_setup.ps1" (echo [FAIL] Missing endpoint_setup.ps1 & set "MISSING=1")
if not exist "%~dp0sysmon_config.xml" (echo [FAIL] Missing sysmon_config.xml & set "MISSING=1")
if not exist "%~dp0amsi_watcher.exe" (echo [FAIL] Missing amsi_watcher.exe & set "MISSING=1")
if "!MISSING!"=="1" (
    echo.
    echo [FATAL] Endpoint package is incomplete. Re-copy the full endpoint folder.
    pause
    exit /b 1
)

set "MANAGER_IP=%~1"
if "%MANAGER_IP%"=="" (
    echo.
    echo Enter the Wazuh Manager IP or DNS name.
    set /p "MANAGER_IP=Manager IP [127.0.0.1]: "
)
if "%MANAGER_IP%"=="" set "MANAGER_IP=127.0.0.1"

echo.
echo [INFO] Manager        : %MANAGER_IP%
echo [INFO] Package folder : %~dp0
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0endpoint_setup.ps1" -WazuhManagerIP "%MANAGER_IP%"
set "EXITCODE=%ERRORLEVEL%"

echo.
if not "%EXITCODE%"=="0" (
    echo ============================================================
    echo  [FAILED] Endpoint setup returned exit code %EXITCODE%.
    echo  Review the PowerShell output above and Windows Event Viewer.
    echo ============================================================
    pause
    exit /b %EXITCODE%
)

echo ============================================================
echo  [READY] Endpoint setup completed.
echo  Verify services:
echo    sc query WazuhSvc
echo    sc query Sysmon64
echo    sc query ISHAXAmsiWatcher
echo ============================================================
pause
exit /b 0
