# isolate.ps1
# ISHAX EDR - Network Isolation Script
# Called by Wazuh Active Response to block all network traffic except Wazuh Manager.
# Run as: SYSTEM (via Wazuh service)
#
# Wazuh passes the alert JSON as arguments. We parse WAZUH_SERVER from environment
# which is set by ossec.conf (WAZUH_MANAGER) at install time.

param(
    [string]$WazuhManagerIP = "100.64.0.0"  # Tailscale IP range — overridden by env at runtime
)

$LogFile = "C:\Program Files (x86)\ossec-agent\active-response\active-responses.log"

function Write-AR-Log {
    param([string]$msg)
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $LogFile -Value "[$ts] [isolate.ps1] $msg" -ErrorAction SilentlyContinue
    Write-Host "[$ts] [isolate.ps1] $msg"
}

Write-AR-Log "=== NETWORK ISOLATION TRIGGERED ==="

# -- Get actual Wazuh Manager IP from the ossec.conf <server><address> tag --
try {
    $ossecConf = Get-Content "C:\Program Files (x86)\ossec-agent\ossec.conf" -Raw -ErrorAction Stop
    if ($ossecConf -match '<address>(.*?)</address>') {
        $WazuhManagerIP = $matches[1].Trim()
        Write-AR-Log "Detected Wazuh Manager IP: $WazuhManagerIP"
    }
} catch {
    Write-AR-Log "WARNING: Could not read ossec.conf, using default IP: $WazuhManagerIP"
}

Write-AR-Log "Step 1: Blocking ALL inbound and outbound traffic..."
netsh advfirewall set allprofiles firewallpolicy blockinbound,blockoutbound 2>&1 | ForEach-Object { Write-AR-Log $_ }

Write-AR-Log "Step 2: Allow loopback (localhost) traffic..."
netsh advfirewall firewall add rule `
    name="ISHAX-Allow-Loopback-In" `
    dir=in action=allow protocol=any `
    remoteip=127.0.0.1 `
    profile=any 2>&1 | ForEach-Object { Write-AR-Log $_ }

netsh advfirewall firewall add rule `
    name="ISHAX-Allow-Loopback-Out" `
    dir=out action=allow protocol=any `
    remoteip=127.0.0.1 `
    profile=any 2>&1 | ForEach-Object { Write-AR-Log $_ }

Write-AR-Log "Step 3: Allow Wazuh Manager connection (TCP 1514, 1515) to $WazuhManagerIP ..."
netsh advfirewall firewall add rule `
    name="ISHAX-Allow-Wazuh-Events" `
    dir=out action=allow protocol=TCP `
    remoteip=$WazuhManagerIP `
    remoteport=1514 `
    profile=any 2>&1 | ForEach-Object { Write-AR-Log $_ }

netsh advfirewall firewall add rule `
    name="ISHAX-Allow-Wazuh-Enroll" `
    dir=out action=allow protocol=TCP `
    remoteip=$WazuhManagerIP `
    remoteport=1515 `
    profile=any 2>&1 | ForEach-Object { Write-AR-Log $_ }

# Also allow Tailscale VPN port (UDP 41641) so Wazuh connection stays alive
netsh advfirewall firewall add rule `
    name="ISHAX-Allow-Tailscale-UDP" `
    dir=out action=allow protocol=UDP `
    remoteport=41641 `
    profile=any 2>&1 | ForEach-Object { Write-AR-Log $_ }

Write-AR-Log "=== ISOLATION COMPLETE. PC is now network-isolated. Only Wazuh connection allowed. ==="
