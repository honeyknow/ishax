<#
.SYNOPSIS
    T1547.001 Sysmon verification gate — §7 of ISHAX v2 rebuild spec.
    Run this on TUF17 (or the monitored endpoint) AFTER loading sysmon_config.xml.
    Do NOT skip this step. Prior v1 had 0/20 detections because this was never verified.

.DESCRIPTION
    1. Creates a test Run key value via REG ADD (triggers Sysmon EID 13)
    2. Waits 3 seconds for Sysmon to log it
    3. Queries Sysmon event log for EID 13 events containing the test value name
    4. Verifies TargetObject shows the actual Run key path (not a BAM/state path)
    5. Cleans up the test key
    6. Reports PASS / FAIL with the actual TargetObject value pasted

.NOTES
    Must run as Administrator (Sysmon event log query requires elevated access).
    Sysmon must be installed and the updated sysmon_config.xml must be loaded.
    Load config: sysmon64.exe -c endpoint\sysmon_config.xml
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"
$TestValueName = "ISHAX_T1547_VERIFY_$(Get-Random -Maximum 9999)"
$TestValueData = "C:\Windows\System32\calc.exe"  # benign binary — clean up after

Write-Host "`n[ISHAX T1547.001 Verification Gate]" -ForegroundColor Cyan
Write-Host "Test value name : $TestValueName"
Write-Host "Test value data : $TestValueData"
Write-Host ""

# Step 1: Write the test Run key (HKCU — doesn't require SYSTEM, just Admin)
$RunKeyPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
Write-Host "[+] Writing test Run key: $RunKeyPath\$TestValueName ..."
try {
    Set-ItemProperty -Path $RunKeyPath -Name $TestValueName -Value $TestValueData -Type String
    Write-Host "    REG ADD succeeded." -ForegroundColor Green
} catch {
    Write-Host "[FAIL] Could not write Run key: $_" -ForegroundColor Red
    exit 1
}

# Step 2: Wait for Sysmon to log
Write-Host "[+] Waiting 4 seconds for Sysmon EID 13 to log..."
Start-Sleep -Seconds 4

# Step 3: Query Sysmon event log for EID 13 with our test value
Write-Host "[+] Querying Sysmon event log (EID 13)..."
try {
    $Events = Get-WinEvent -LogName "Microsoft-Windows-Sysmon/Operational" `
        -FilterXPath "*[System[EventID=13]]" `
        -MaxEvents 100 -ErrorAction Stop |
        Where-Object { $_.Message -like "*$TestValueName*" }
} catch {
    Write-Host "[FAIL] Could not query Sysmon event log: $_" -ForegroundColor Red
    Write-Host "       Is Sysmon installed and running? (sc query sysmon64)" -ForegroundColor Yellow
    # Cleanup before exit
    Remove-ItemProperty -Path $RunKeyPath -Name $TestValueName -ErrorAction SilentlyContinue
    exit 1
}

# Step 4: Verify
Write-Host ""
if ($Events.Count -eq 0) {
    Write-Host "[FAIL] No Sysmon EID 13 event found for test value '$TestValueName'" -ForegroundColor Red
    Write-Host ""
    Write-Host "  Diagnosis checklist:" -ForegroundColor Yellow
    Write-Host "  1. Is Sysmon running?         sc query sysmon64"
    Write-Host "  2. Is config loaded?           sysmon64.exe -c endpoint\sysmon_config.xml"
    Write-Host "  3. Is there a duplicate <RegistryEvent> block in the config?"
    Write-Host "  4. Does the config have the Run key path in RegistryEvent include?"
    Write-Host "  5. Try: sysmon64.exe -c (reload), wait 5s, rerun this script."
    Write-Host ""
    Write-Host "  DO NOT write the Sigma rule until this passes." -ForegroundColor Red
} else {
    Write-Host "[PASS] Found $($Events.Count) Sysmon EID 13 event(s) for test value." -ForegroundColor Green
    Write-Host ""

    $PassedAll = $true
    foreach ($evt in $Events) {
        # Extract TargetObject from the message
        $TargetLine = ($evt.Message -split "`n" | Where-Object { $_ -match "TargetObject" }) | Select-Object -First 1
        Write-Host "  TargetObject (raw): $TargetLine"

        # Verify it contains the Run key path (not a BAM or SYSTEM\...\State path)
        $IsRunKey = $TargetLine -match "CurrentVersion\\Run" -and $TargetLine -notmatch "\\BAM\\" -and $TargetLine -notmatch "\\State\\"
        if ($IsRunKey) {
            Write-Host "  [OK] TargetObject shows correct Run key path." -ForegroundColor Green
        } else {
            Write-Host "  [WARN] TargetObject does NOT look like a Run key path!" -ForegroundColor Yellow
            Write-Host "         This is the BAM/state false-positive that caused 0/20 in v1." -ForegroundColor Yellow
            Write-Host "         Recheck sysmon_config.xml RegistryEvent block." -ForegroundColor Yellow
            $PassedAll = $false
        }
    }

    Write-Host ""
    if ($PassedAll) {
        Write-Host "=== VERIFICATION GATE: PASSED ===" -ForegroundColor Green
        Write-Host "Sysmon EID 13 correctly captures Run key writes."
        Write-Host "The Sigma rule t1547-001-run-keys.yml will fire correctly."
    } else {
        Write-Host "=== VERIFICATION GATE: FAILED ===" -ForegroundColor Red
        Write-Host "Fix the TargetObject path issue before deploying the Sigma rule."
    }
}

# Step 5: Cleanup
Write-Host ""
Write-Host "[+] Cleaning up test Run key..."
try {
    Remove-ItemProperty -Path $RunKeyPath -Name $TestValueName -ErrorAction Stop
    Write-Host "    Cleaned up: $RunKeyPath\$TestValueName" -ForegroundColor Green
} catch {
    Write-Host "[WARN] Cleanup failed — remove manually: $RunKeyPath\$TestValueName" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "[Done] Verification complete. Paste the TargetObject line above into your test report." -ForegroundColor Cyan
