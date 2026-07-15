# 1. Bypass Execution Policy
Set-ExecutionPolicy Bypass -Scope Process -Force

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "     ISHA-X EDR: Offline Atomic Test Runner          " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 2. Check Defender Tamper Protection
$RTP = Get-MpPreference | Select-Object -ExpandProperty DisableRealtimeMonitoring
if (-not $RTP) {
    Write-Host "[WARNING] Defender Real-Time Protection is STILL ON!" -ForegroundColor Red
} else {
    Write-Host "[OK] Defender Real-Time Protection is OFF." -ForegroundColor Green
}
Write-Host "[!] Please ensure TAMPER PROTECTION is also manually turned OFF in Windows Security UI!" -ForegroundColor Yellow
Start-Sleep 3

# 3. Load Offline Module
$BaseDir = $PSScriptRoot

# Load powershell-yaml first from the offline folder
$YamlPath = Join-Path $BaseDir "powershell-yaml\0.4.12\powershell-yaml.psd1"
if (Test-Path $YamlPath) {
    Import-Module $YamlPath -Force
} else {
    Write-Host "[WARNING] powershell-yaml not found at $YamlPath. ART module might fail to load." -ForegroundColor Yellow
}

$ModulePath = Join-Path $BaseDir "invoke-atomicredteam\Invoke-AtomicRedTeam.psd1"
$AtomicsPath = Join-Path $BaseDir "atomics"

if (-not (Test-Path $ModulePath)) {
    Write-Host "[-] Cannot find module at $ModulePath. Run this script from inside the ART_Offline folder!" -ForegroundColor Red
    exit
}

Import-Module $ModulePath -Force
Write-Host "[+] Offline Module Loaded." -ForegroundColor Green

# 4. Techniques to test
$techniques = @(
    "T1059.001", # PowerShell
    "T1059.005", # VBA
    "T1059.007", # JS/VBS
    "T1543.003", # Services
    "T1547.001"  # Run Keys
)

Write-Host "`n[*] Starting Tests..." -ForegroundColor Cyan

foreach ($t in $techniques) {
    Write-Host "`n-----------------------------------------------------"
    Write-Host " Firing Technique: $t " -ForegroundColor Yellow
    Write-Host "-----------------------------------------------------"
    
    # We don't need -GetPrereqs because the offline folder has them downloaded!
    Invoke-AtomicTest $t -PathToAtomicsFolder $AtomicsPath -PromptForInputArgs:$false

    Write-Host "`n[?] Test $t fired. Check EDR database for telemetry." -ForegroundColor DarkGray
    Read-Host "Press ENTER to fire the next technique (or Ctrl+C to abort and revert snapshot)..."
}

Write-Host "`n=====================================================" -ForegroundColor Cyan
Write-Host " All Phase A Tests Executed Successfully!" -ForegroundColor Green
Write-Host "=====================================================" -ForegroundColor Cyan
