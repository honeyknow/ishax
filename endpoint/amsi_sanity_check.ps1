# Run this AFTER Defender RTP is disabled and BEFORE any Atomic tests.
# Confirms AMSI ETW watcher is alive and forwarding events.

Write-Host "== AMSI Sanity Check ==" -ForegroundColor Cyan

# 1. Is the service running?
$svc = Get-Service ISHAXAmsiWatcher -ErrorAction SilentlyContinue
if (-not $svc -or $svc.Status -ne "Running") {
    Write-Host "[FAIL] ISHAXAmsiWatcher service not running. Start it first." -ForegroundColor Red
    exit 1
}
Write-Host "[OK] ISHAXAmsiWatcher service: Running" -ForegroundColor Green

# 2. Fire a known-detectable PowerShell payload (benign encoded string)
Write-Host "Firing test payload..." -ForegroundColor DarkGray
$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes("Invoke-Mimikatz -sanity-test"))
Start-Process powershell -ArgumentList "-NonInteractive -EncodedCommand $encoded" -ErrorAction SilentlyContinue

Start-Sleep 3

# 3. Check ISHAX-AMSI event log for the last 15 seconds
try {
    $events = Get-WinEvent -LogName "ISHAX-AMSI" -MaxEvents 5 -ErrorAction Stop |
              Where-Object { $_.TimeCreated -gt (Get-Date).AddSeconds(-15) }
    if ($events) {
        Write-Host "[OK] AMSI watcher captured $($events.Count) event(s) in last 15s" -ForegroundColor Green
        Write-Host "     AMSI is LIVE — safe to proceed with Atomic tests." -ForegroundColor Green
    } else {
        Write-Host "[WARN] No AMSI events in last 15s — watcher may be down or Defender blocking ETW" -ForegroundColor Yellow
        Write-Host "       Check: Get-WinEvent -LogName ISHAX-AMSI -MaxEvents 10" -ForegroundColor Yellow
    }
} catch {
    Write-Host "[FAIL] ISHAX-AMSI event log not found or inaccessible: $_" -ForegroundColor Red
    Write-Host "       Run endpoint_setup.ps1 first to create the log channel." -ForegroundColor Red
}
