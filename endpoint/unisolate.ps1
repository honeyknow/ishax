# unisolate.ps1
# ISHAX EDR - Network Restoration Script
# Called by Wazuh Active Response to RESTORE normal network access.
# Run as: SYSTEM (via Wazuh service)

$LogFile = "C:\Program Files (x86)\ossec-agent\active-response\active-responses.log"

function Write-AR-Log {
    param([string]$msg)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$ts] [unisolate.ps1] $msg" -ErrorAction SilentlyContinue
    Write-Host "[$ts] [unisolate.ps1] $msg"
}

Write-AR-Log "=== NETWORK RESTORATION TRIGGERED ==="

Write-AR-Log "Step 1: Restoring default firewall policy (allow all)..."
netsh advfirewall set allprofiles firewallpolicy allowinbound,allowoutbound 2>&1 | ForEach-Object { Write-AR-Log $_ }

Write-AR-Log "Step 2: Removing ISHAX isolation rules..."
$rulesToDelete = @(
    "ISHAX-Allow-Loopback-In",
    "ISHAX-Allow-Loopback-Out",
    "ISHAX-Allow-Wazuh-Events",
    "ISHAX-Allow-Wazuh-Enroll",
    "ISHAX-Allow-Tailscale-UDP"
)

foreach ($rule in $rulesToDelete) {
    netsh advfirewall firewall delete rule name="$rule" 2>&1 | ForEach-Object { Write-AR-Log $_ }
}

Write-AR-Log "=== RESTORATION COMPLETE. Normal network access has been restored. ==="
