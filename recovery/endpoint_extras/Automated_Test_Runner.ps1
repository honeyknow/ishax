# =====================================================
# ISHA-X EDR: Phase A Automated Test Runner
# =====================================================

Write-Host "=====================================================" -ForegroundColor Cyan
Write-Host "     ISHA-X EDR: Phase A Automated Test Runner       " -ForegroundColor Cyan
Write-Host "=====================================================" -ForegroundColor Cyan

# 1. Defender Settings
Write-Host "`n[*] Step 1: Disabling Defender Real-Time Protection..." -ForegroundColor Yellow
Set-MpPreference -DisableRealtimeMonitoring $true
Write-Host "[OK] Real-Time Protection is OFF." -ForegroundColor Green
Write-Host "`n[!] CRITICAL: You must manually turn OFF Tamper Protection in Windows Security UI!" -ForegroundColor Red
Write-Host "Go to: Settings -> Virus & threat protection -> Manage settings -> Tamper Protection" -ForegroundColor Red
Read-Host "Press ENTER when Tamper Protection is confirmed OFF"

# 2. AMSI Sanity Check
Write-Host "`n[*] Step 2: AMSI Sanity Check..." -ForegroundColor Yellow
Write-Host "Running a simple EncodedCommand to trigger AMSI..."
# Encoded "Write-Host 'AMSI Sanity Check'"
powershell -EncodedCommand VwByAGkAdABlAC0ASABvAHMAdAAgACcAQQBNAFMASQAgAFMAYQBuAGkAdAB5ACAAQwBoAGUAYwBrACcA
Write-Host "[!] Check your EDR Dashboard/DB. Did the AMSI Watcher capture this?" -ForegroundColor Red
Read-Host "Press ENTER if AMSI capture is confirmed, or Ctrl+C to abort"

# 3. Setup Atomics
Write-Host "`n[*] Step 3: Setting up Invoke-AtomicRedTeam..." -ForegroundColor Yellow
$BaseDir = Join-Path $PSScriptRoot "ART_Offline"
$ModulePath = "$BaseDir\invoke-atomicredteam\Invoke-AtomicRedTeam.psd1"
$AtomicsPath = "$BaseDir\atomics"

if (-not (Test-Path $ModulePath)) {
    Write-Host "[!] ART_Offline folder not found at $BaseDir!" -ForegroundColor Red
    exit
}

# Fix powershell-yaml dependency
Import-Module "$BaseDir\powershell-yaml\0.4.12\powershell-yaml.psd1" -Force
Import-Module $ModulePath -Force
Write-Host "[+] ART Module Loaded." -ForegroundColor Green

# 4. Fetch Prereqs
Write-Host "`n[*] Step 4: Fetching Prerequisites for all techniques..." -ForegroundColor Yellow
Invoke-AtomicTest T1059.001 -GetPrereqs -PathToAtomicsFolder $AtomicsPath
Invoke-AtomicTest T1059.005 -GetPrereqs -PathToAtomicsFolder $AtomicsPath
Invoke-AtomicTest T1059.007 -GetPrereqs -PathToAtomicsFolder $AtomicsPath
Invoke-AtomicTest T1543.003 -GetPrereqs -PathToAtomicsFolder $AtomicsPath
Invoke-AtomicTest T1547.001 -GetPrereqs -PathToAtomicsFolder $AtomicsPath
Write-Host "[+] Prereqs fetched." -ForegroundColor Green

Write-Host "`n[!] CRITICAL SNAPSHOT TIME: Take a snapshot NOW named 'ready-to-fire'." -ForegroundColor Red
Write-Host "You will revert to this snapshot after noisy tests." -ForegroundColor Red
Read-Host "Press ENTER when snapshot is taken"

# 5. Execution Menu
function Run-Test {
    param($Technique, $Tests)
    Write-Host "`n=====================================================" -ForegroundColor Magenta
    Write-Host " Executing: $Technique (Tests: $Tests)" -ForegroundColor Magenta
    Write-Host "=====================================================" -ForegroundColor Magenta
    
    # PowerShell treats "1,2,3" as a single string. We must split it into an array.
    $TestArray = $Tests -split ','
    Invoke-AtomicTest $Technique -PathToAtomicsFolder $AtomicsPath -TestNumbers $TestArray
    
    Write-Host "`n[!] Test completed. Check DB/Dashboard for alerts." -ForegroundColor Yellow
}

Write-Host "`n[*] Order of Execution:"
Run-Test "T1059.001" "1,3,4,5,6,8,10,11,17,18,19"
Read-Host "Press ENTER to proceed to next technique"

Run-Test "T1059.005" "1,4"  # Omitting Word/Excel variants as requested
Read-Host "Press ENTER to proceed to next technique"

Run-Test "T1059.007" "1,2"
Read-Host "Press ENTER to proceed to next technique"

Run-Test "T1543.003" "1,2,3,4"
Write-Host "`n[!] WARNING: T1543.003 creates lingering services. Revert to 'ready-to-fire' snapshot NOW before continuing!" -ForegroundColor Red
Read-Host "Press ENTER once you have reverted, run this script again and skip to T1547 (Ctrl+C and run manually)"

Run-Test "T1547.001" "1"
Write-Host "`n[+] All Phase A Testing Complete!" -ForegroundColor Green
