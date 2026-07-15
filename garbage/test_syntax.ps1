if ($true) {
    if ($true) {
        Write-Host "Service already exists, updating..." -ForegroundColor DarkGray
    }
    sc.exe create svc binPath= "`"C:\path`"" start= auto obj= LocalSystem DisplayName= "ISHAX AMSI ETW Watcher" | Out-Null
    sc.exe description svc "Monitors AMSI ETW provider for script content. ISHAX EDR component." | Out-Null
    if ($true) {
        Write-Host "AMSI ETW Watcher service running (PID: $(Get-Process amsi_watcher -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty Id))"
    } else {
        Write-Host "AMSI ETW Watcher failed to start — check Event Viewer > Application"
    }
}
