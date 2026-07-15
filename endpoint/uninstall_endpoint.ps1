<#
.SYNOPSIS
    ISHA-X EDR — Windows Endpoint Uninstaller (Robust)
    Removes Sysmon, Wazuh Agent, and AMSI Watcher cleanly.

.DESCRIPTION
    Run as Administrator to completely clean the endpoint of all EDR agent components.
#>

#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "SilentlyContinue" # We handle errors manually

function Write-Step($m) { Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-Ok($m)   { Write-Host "    [OK]   $m" -ForegroundColor Green }
function Write-Warn($m) { Write-Host "    [WARN] $m" -ForegroundColor Yellow }

$ProgramFilesX86 = ${env:ProgramFiles(x86)}
if ([string]::IsNullOrWhiteSpace($ProgramFilesX86)) { $ProgramFilesX86 = $env:ProgramFiles }

Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Yellow
Write-Host "    ISHA-X EDR  |  Endpoint Uninstaller" -ForegroundColor Yellow
Write-Host "  ============================================================" -ForegroundColor Yellow
Write-Host ""

# ── 1. AMSI Watcher ──────────────────────────────────────────────────────────
Write-Step "Removing AMSI ETW Watcher Service..."

foreach ($serviceName in @("ISHAXAmsiWatcher", "ISHAXAmsi")) {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        Write-Host "    Stopping $serviceName service..." -ForegroundColor DarkGray
        Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2

        Write-Host "    Deleting $serviceName service..." -ForegroundColor DarkGray
        sc.exe delete $serviceName > $null 2>&1
        Write-Ok "$serviceName service removed."
    } else {
        Write-Ok "$serviceName service already removed."
    }
}

# Kill any stuck processes
taskkill.exe /F /IM amsi_watcher.exe > $null 2>&1

# Unregister Event Log Source
Write-Host "    Unregistering ISHAX-AMSI Event Log channel..." -ForegroundColor DarkGray
reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\ISHAX-AMSI" /f > $null 2>&1
Write-Ok "Event Log channel unregistered."


# ── 2. Sysmon ───────────────────────────────────────────────────────────────
Write-Step "Uninstalling Sysmon..."
$sysmonPath = Join-Path $ProgramFilesX86 "ISHA-X\Sysmon64.exe"
$sysmonSysPath = "C:\Windows\Sysmon64.exe"

$sysmonFound = $false
if (Test-Path $sysmonPath) {
    $targetPath = $sysmonPath
    $sysmonFound = $true
} elseif (Test-Path $sysmonSysPath) {
    $targetPath = $sysmonSysPath
    $sysmonFound = $true
}

if ($sysmonFound) {
    Write-Host "    Running Sysmon uninstaller (this takes a moment)..." -ForegroundColor DarkGray
    $proc = Start-Process -FilePath $targetPath -ArgumentList "-u force" -Wait -PassThru -NoNewWindow
    if ($proc.ExitCode -eq 0) {
        Write-Ok "Sysmon successfully uninstalled."
    } else {
        Write-Warn "Sysmon uninstaller returned code $($proc.ExitCode)."
    }
} else {
    Write-Ok "Sysmon executable not found. Assuming already uninstalled."
}


# ── 3. Wazuh Agent ──────────────────────────────────────────────────────────
Write-Step "Uninstalling Wazuh Agent..."

$wazuhService = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if ($wazuhService) {
    Write-Host "    Stopping WazuhSvc..." -ForegroundColor DarkGray
    Stop-Service -Name "WazuhSvc" -Force -ErrorAction SilentlyContinue
}

# Find Wazuh Uninstall String from Registry (faster & safer than Win32_Product)
$wazuhFound = $false
$paths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

foreach ($path in $paths) {
    $keys = Get-ItemProperty $path -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -match "Wazuh Agent" }
    foreach ($key in $keys) {
        $wazuhFound = $true
        $uninstallString = $key.UninstallString
        if ($uninstallString -match "msiexec") {
            # Extract product code and run silent uninstall
            $guid = ($uninstallString -split " ")[1]
            Write-Host "    Uninstalling Wazuh Agent MSI ($guid)..." -ForegroundColor DarkGray
            $proc = Start-Process "msiexec.exe" -ArgumentList "/x $guid /qn" -Wait -PassThru
            if ($proc.ExitCode -eq 0) {
                Write-Ok "Wazuh Agent MSI uninstalled."
            } else {
                Write-Warn "Wazuh uninstall returned code $($proc.ExitCode)."
            }
        }
    }
}

if (-not $wazuhFound) {
    Write-Ok "Wazuh Agent not found in registry (already uninstalled)."
}

# Force cleanup Wazuh directory
$wazuhDir = Join-Path $ProgramFilesX86 "ossec-agent"
if (Test-Path $wazuhDir) {
    Write-Host "    Cleaning up left-over Wazuh files..." -ForegroundColor DarkGray
    Remove-Item -Path $wazuhDir -Recurse -Force -ErrorAction SilentlyContinue
    Write-Ok "Wazuh folder deleted."
}


# ── 4. ISHA-X Directory ─────────────────────────────────────────────────────
Write-Step "Removing ISHA-X Directory..."
$installDir = Join-Path $ProgramFilesX86 "ISHA-X"
if (Test-Path $installDir) {
    Remove-Item -Path $installDir -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path $installDir) {
        Write-Warn "Could not delete $installDir entirely (files may be locked)."
    } else {
        Write-Ok "Removed $installDir."
    }
} else {
    Write-Ok "Directory already removed."
}


Write-Host ""
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   [SUCCESS] Uninstallation Complete!" -ForegroundColor Green
Write-Host "  ============================================================" -ForegroundColor Green
Write-Host "   The ISHA-X EDR agents have been removed from this machine." -ForegroundColor Green
Write-Host ""
