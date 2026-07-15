<#
.SYNOPSIS
    ISHA-X EDR — Windows Endpoint Setup
    Installs Sysmon 15.21 + Wazuh Agent 4.14.6.
    Wazuh Manager runs locally via Docker (start_local.ps1).

.DESCRIPTION
    Run as Administrator on EACH endpoint you want to monitor.
    Auto-detects if running on a Domain Controller and applies extra audit policies.

    Same machine as server?  -> Run with no arguments (defaults to 127.0.0.1)
    Another PC on LAN?       -> Run with -WazuhManagerIP <server-LAN-IP>

    Event sources by role:
      Endpoint + DC:
        System   EID 7045  - new service installed         (T1543.003)
        Security EID 4697  - service installed             (T1543.003)
        Security EID 4720  - local account created         (T1136.001)
        Security EID 4624  - logon type 10 (RDP)           (T1021.001)
        Security EID 4625  - failed logon                  (T1110.x)
        Security EID 4732  - member added to local group   (T1098.x)
        Sysmon   EID 1     - process create               (T1543.003)
        Sysmon   EID 13    - Services registry write       (T1543.003)

      DC only:
        Security EID 4662  - DS object access (DCSync)     (T1003.006)
        Security EID 4769  - Kerberos TGS request          (T1558.003)
        Security EID 4771  - Kerberos pre-auth failed      (T1110.x)
        Security EID 4741  - domain account created        (T1136.002)
        Security EID 4728  - member added to global group  (T1098.x)
        Security EID 4756  - member added to universal grp (T1098.x)

.PARAMETER WazuhManagerIP
    IP of the machine running Wazuh Manager (Docker).
    Default: 127.0.0.1 (same machine — most common local setup).

.PARAMETER WazuhAgentName
    Name for this agent. Defaults to computer name.

.PARAMETER SysmonConfigPath
    Path to sysmon_config.xml. Defaults to same folder as this script.

.EXAMPLE
    # Same machine as server (most common):
    .\endpoint_setup.ps1

    # Another PC on LAN:
    .\endpoint_setup.ps1 -WazuhManagerIP "192.168.1.10"

    # VM home lab:
    .\endpoint_setup.ps1 -WazuhManagerIP "192.168.1.10" -WazuhAgentName "lab-vm01"

.NOTES
    Sysmon 15.21: https://download.sysinternals.com/files/Sysmon.zip
    Wazuh 4.14.6: https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.6-1.msi
#>

#Requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)] [string]$WazuhManagerIP    = "127.0.0.1",
    [Parameter(Mandatory=$false)] [string]$WazuhAgentName    = $env:COMPUTERNAME,
    [Parameter(Mandatory=$false)] [string]$SysmonConfigPath  = "",
    [Parameter(Mandatory=$false)] [string]$InstallDir        = ""
)

Set-StrictMode -Version Latest

if ($SysmonConfigPath -eq "") {
    $SysmonConfigPath = Join-Path $PSScriptRoot "sysmon_config.xml"
}
$ProgramFilesX86 = ${env:ProgramFiles(x86)}
if ([string]::IsNullOrWhiteSpace($ProgramFilesX86)) { $ProgramFilesX86 = $env:ProgramFiles }
if ([string]::IsNullOrWhiteSpace($InstallDir)) {
    $InstallDir = Join-Path $ProgramFilesX86 "ISHA-X"
}
# Removed ErrorActionPreference = "Stop" to prevent native exe stderr from crashing script

# -- Helpers -------------------------------------------------------------------

function Write-Step    { param([string]$m) Write-Host "`n==> $m" -ForegroundColor Cyan }
function Write-OK      { param([string]$m) Write-Host "    [OK]   $m" -ForegroundColor Green }
function Write-Warn    { param([string]$m) Write-Host "    [WARN] $m" -ForegroundColor Yellow }
function Write-Fail    { param([string]$m) Write-Host "    [FAIL] $m" -ForegroundColor Red; throw $m }

function Invoke-Download {
    param([string]$Url, [string]$Dest, [int]$Retries=3)
    Write-Host "    Downloading: $Url"
    
    # Avoid proxy blocks and set timeouts
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $wc = New-Object System.Net.WebClient
    $wc.Proxy = [System.Net.WebRequest]::GetSystemWebProxy()
    $wc.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials

    for ($i=1; $i -le $Retries; $i++) {
        try {
            $wc.DownloadFile($Url, $Dest)
            Write-OK "Saved to $Dest"
            return
        } catch {
            if ($i -eq $Retries) { Write-Fail "Download failed after $Retries attempts: $_" }
            Write-Warn "Download failed, retrying ($i/$Retries) in 5s... ($_)"
            Start-Sleep 5
        }
    }
}

# -- Detect if this machine is a Domain Controller -----------------------------

$IS_DC = $false
try {
    $role = (Get-WmiObject Win32_ComputerSystem).DomainRole
    # DomainRole: 4 = Backup DC, 5 = Primary DC
    if ($role -eq 4 -or $role -eq 5) { $IS_DC = $true }
} catch {}

if ($IS_DC) {
    Write-Host "`n  *** Domain Controller detected - DC-specific audit policies will be applied ***" -ForegroundColor Magenta
} else {
    Write-Host "`n  Endpoint role: Workstation / Member Server"
}

# -- Constants -----------------------------------------------------------------

$SYSMON_ZIP_URL     = "https://download.sysinternals.com/files/Sysmon.zip"
$SYSMON_ZIP_LOCAL   = "$env:TEMP\Sysmon.zip"
$SYSMON_EXTRACT_DIR = "$env:TEMP\SysmonEDR"
$SYSMON64_EXE       = "$SYSMON_EXTRACT_DIR\Sysmon64.exe"

$WAZUH_VERSION      = "4.8.0"
$WAZUH_MSI_URL      = "https://packages.wazuh.com/4.x/windows/wazuh-agent-${WAZUH_VERSION}-1.msi"
$WAZUH_MSI_LOCAL    = "$env:TEMP\wazuh-agent-${WAZUH_VERSION}-1.msi"
$WAZUH_CONF_PATH    = Join-Path $ProgramFilesX86 "ossec-agent\ossec.conf"

# == STEP 0: Preflight ==========================================================

Write-Step "Preflight checks"

if (-not (Test-Path $SysmonConfigPath)) {
    Write-Fail "sysmon_config.xml not found at '$SysmonConfigPath'. Ensure all files were copied together."
}

try {
    [xml]$testXml = Get-Content $SysmonConfigPath -Raw
    if ($null -eq $testXml.Sysmon) { throw "Root node <Sysmon> not found." }
} catch {
    Write-Fail "sysmon_config.xml is corrupted or invalid XML: $_"
}
Write-OK "Sysmon config is valid XML: $SysmonConfigPath"

if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}
foreach ($fileName in @("endpoint_setup.ps1", "uninstall_endpoint.ps1", "sysmon_config.xml", "amsi_watcher.exe")) {
    $sourcePath = Join-Path $PSScriptRoot $fileName
    if (Test-Path $sourcePath) {
        Copy-Item -LiteralPath $sourcePath -Destination (Join-Path $InstallDir $fileName) -Force
    }
}
$SysmonConfigPath = Join-Path $InstallDir "sysmon_config.xml"
Write-OK "Runtime files staged in $InstallDir"

$reach = Test-NetConnection -ComputerName $WazuhManagerIP -Port 1514 -WarningAction SilentlyContinue
if (-not $reach.TcpTestSucceeded) {
    Write-Warn "Port 1514 on $WazuhManagerIP unreachable. Ensure server is running and firewall allows port 1514."
    Write-Warn "The agent will install but will sit offline until the server is reachable."
} else {
    Write-OK "Wazuh manager reachable on port 1514"
}

# == STEP 1: Sysmon 15.21 =======================================================

Write-Step "Step 1: Sysmon 15.21 install / config update"

$svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue

if ($svc) {
    Write-Warn "Sysmon64 is already installed. Attempting clean config update..."
    $existingExe = "C:\Windows\Sysmon64.exe"
    if (Test-Path $existingExe) {
        # Kill any hung instances
        Get-Process "Sysmon64" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        
        $proc = Start-Process -FilePath $existingExe -ArgumentList "-c `"$SysmonConfigPath`" -accepteula" -Wait -PassThru -NoNewWindow
        if ($proc.ExitCode -eq 0) {
            Write-OK "Config updated in-place successfully."
            # Ensure service is running
            if ($svc.Status -ne "Running") { Start-Service "Sysmon64" -ErrorAction SilentlyContinue }
        } else {
            Write-Warn "Config update failed (Exit: $($proc.ExitCode)). Will attempt fresh reinstall."
            $svc = $null
        }
    } else {
        Write-Warn "Sysmon64.exe missing from C:\Windows. Doing fresh install."
        $svc = $null
    }
}

if (-not $svc) {
    Invoke-Download -Url $SYSMON_ZIP_URL -Dest $SYSMON_ZIP_LOCAL

    if (Test-Path $SYSMON_EXTRACT_DIR) { Remove-Item $SYSMON_EXTRACT_DIR -Recurse -Force }
    Expand-Archive -Path $SYSMON_ZIP_LOCAL -DestinationPath $SYSMON_EXTRACT_DIR -Force

    if (-not (Test-Path $SYSMON64_EXE)) {
        Write-Fail "Sysmon64.exe missing after extraction. Zip contents may have changed - verify."
    }

    Write-Host "    Installing Sysmon64 with EDR config ..."
    $sysmonOutput = & $SYSMON64_EXE -accepteula -i $SysmonConfigPath 2>&1
    Write-Host "    Sysmon Output: $sysmonOutput" -ForegroundColor DarkGray

    Start-Sleep 3
    $svc = Get-Service -Name "Sysmon64" -ErrorAction SilentlyContinue
    if (-not $svc -or $svc.Status -ne "Running") {
        Write-Fail "Sysmon64 service not running after install."
    }
    Write-OK "Sysmon 15.21 installed and running."
}

# Log schema version for documentation
$schema = & "C:\Windows\Sysmon64.exe" -s 2>&1 | Select-String "schemaversion" | Select-Object -First 1
Write-Host "    Schema: $schema"

# == STEP 2: Audit Policies - ALL ENDPOINTS ====================================

Write-Step "Step 2: Windows Security Audit Policies (all endpoints)"

# Each subcategory maps directly to the event IDs we need to collect.
# auditpol /set is idempotent - safe to run multiple times.

$baselinePolicies = @(
    @{ Sub = "Logon";                    Desc = "EID 4624/4625 - RDP + Brute Force (T1021.001, T1110.x)" },
    @{ Sub = "Account Lockout";          Desc = "EID 4740 - lockout events during brute force" },
    @{ Sub = "User Account Management";  Desc = "EID 4720, 4741 - account creation (T1136.001/002)" },
    @{ Sub = "Security Group Management";Desc = "EID 4732, 4728, 4756 - group membership (T1098.x)" },
    @{ Sub = "Process Creation";         Desc = "EID 4688 - process creation audit (T1543.003 supplement)" },
    @{ Sub = "Security System Extension";Desc = "EID 4697 - service installed (T1543.003)" }
)

foreach ($pol in $baselinePolicies) {
    & auditpol /set /subcategory:"$($pol.Sub)" /success:enable /failure:enable 2>&1 | Out-Null
    Write-OK "Audit: '$($pol.Sub)' - $($pol.Desc)"
}

Write-Step "Step 2.1: Enable PowerShell ScriptBlock Logging"
$psLogKey = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging"
if (-not (Test-Path $psLogKey)) { New-Item -Path $psLogKey -Force | Out-Null }
Set-ItemProperty -Path $psLogKey -Name "EnableScriptBlockLogging" -Value 1 -Type DWord
Write-OK "PowerShell ScriptBlock Logging enabled (EID 4104)."

# == STEP 3: DC-Only Audit Policies ============================================

if ($IS_DC) {
    Write-Step "Step 3: DC-specific audit policies"

    $dcPolicies = @(
        @{ Sub = "Directory Service Access";  Desc = "EID 4662 - DCSync detection (T1003.006)" },
        @{ Sub = "Kerberos Service Ticket Operations"; Desc = "EID 4769 - Kerberoasting (T1558.003)" },
        @{ Sub = "Kerberos Authentication Service";   Desc = "EID 4771 - Kerberos pre-auth fail (T1110.x)" },
        @{ Sub = "Directory Service Changes"; Desc = "EID 5136 - DS object modification (supplementary)" }
    )

    foreach ($pol in $dcPolicies) {
        & auditpol /set /subcategory:"$($pol.Sub)" /success:enable /failure:enable 2>&1 | Out-Null
        Write-OK "DC Audit: '$($pol.Sub)' - $($pol.Desc)"
    }

    # DCSync also requires SACL on domain root - inform the operator.
    Write-Warn @"
ACTION REQUIRED - DCSync detection (T1003.006) needs SACL on the domain root:
  1. Open 'Active Directory Users and Computers'
  2. View -> Advanced Features
  3. Right-click the domain root -> Properties -> Security -> Advanced -> Auditing
  4. Add -> Select Principal: Everyone
     Type: Success
     Applies to: This object and all descendant objects
     Permissions: Replicate Directory Changes
                  Replicate Directory Changes All
                  Replicate Directory Changes In Filtered Set
  5. Apply

Without this SACL, EID 4662 will not be generated for replication operations.
"@
} else {
    Write-Step "Step 3: DC policies skipped (not a DC)"
}

# == STEP 4: Install AMSI ETW Watcher as Windows Service =======================
Write-Step "Step 4: Installing AMSI ETW Watcher service"

$AmsiWatcherPath = Join-Path $InstallDir "amsi_watcher.exe"
if (-not (Test-Path $AmsiWatcherPath)) {
    Write-Warn "amsi_watcher.exe not found at $AmsiWatcherPath - AMSI Layer A will not function."
} else {
    $svcName = "ISHAXAmsiWatcher"
    $existing = Get-Service -Name $svcName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "    Service already exists, updating..." -ForegroundColor DarkGray
        Stop-Service $svcName -Force -ErrorAction SilentlyContinue
        sc.exe delete $svcName | Out-Null
        Start-Sleep 2
    }
    sc.exe create $svcName binPath= "`"$AmsiWatcherPath`"" start= auto obj= LocalSystem DisplayName= "ISHAX AMSI ETW Watcher" | Out-Null
    sc.exe description $svcName "Monitors AMSI ETW provider for script content. ISHAX EDR component." | Out-Null
    Start-Service $svcName -ErrorAction SilentlyContinue
    $svc = Get-Service $svcName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        $p = Get-Process amsi_watcher -ErrorAction SilentlyContinue | Select-Object -First 1
        $pidStr = if ($p) { $p.Id } else { "Unknown" }
        Write-OK "AMSI ETW Watcher service running (PID: $pidStr)"
    } else {
        Write-Warn "AMSI ETW Watcher failed to start - check Event Viewer > Application"
    }
}

# == STEP 5: Wazuh Agent 4.14.6 ================================================

Write-Step "Step 5: Wazuh Agent $WAZUH_VERSION"

$wazuhProd = $null

if ($wazuhProd) {
    Write-Warn "Wazuh Agent is already installed ($($wazuhProd.Version))."
    # Service will just be restarted later
} else {
    Invoke-Download -Url $WAZUH_MSI_URL -Dest $WAZUH_MSI_LOCAL

    $msiLog  = "$env:TEMP\wazuh-install.log"
    $msiArgs = @(
        "/i", "`"$WAZUH_MSI_LOCAL`"",
        "WAZUH_MANAGER=`"$WazuhManagerIP`"",
        "WAZUH_AGENT_NAME=`"$WazuhAgentName`"",
        "/qn",
        "REBOOT=ReallySuppress",
        "/l*v", "`"$msiLog`""
    )

    Write-Host "    Running MSI installer silently (log: $msiLog) ..."
    $proc = Start-Process -FilePath "msiexec.exe" -ArgumentList $msiArgs -Wait -PassThru
    if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
        Write-Fail "MSI failed (exit $($proc.ExitCode)). See: $msiLog"
    }
    Write-OK "Wazuh Agent $WAZUH_VERSION installed."
}

# == STEP 6: Configure ossec.conf event channels ===============================

Write-Step "Step 6: ossec.conf - event channel configuration"

$waited = 0
while (-not (Test-Path $WAZUH_CONF_PATH) -and $waited -lt 30) { Start-Sleep 2; $waited += 2 }
if (-not (Test-Path $WAZUH_CONF_PATH)) {
    Write-Fail "ossec.conf not found at '$WAZUH_CONF_PATH'. Install may have failed."
}

[xml]$cfg = Get-Content $WAZUH_CONF_PATH -Raw

# Channels all endpoints need
$channels = [System.Collections.Generic.List[hashtable]]::new()
$channels.Add(@{ location = "Microsoft-Windows-Sysmon/Operational"; log_format = "eventchannel" })
$channels.Add(@{ location = "Security";                             log_format = "eventchannel" })
$channels.Add(@{ location = "System";                               log_format = "eventchannel" })
$channels.Add(@{ location = "Microsoft-Windows-PowerShell/Operational"; log_format = "eventchannel" })
$channels.Add(@{ location = "Microsoft-Windows-TerminalServices-LocalSessionManager/Operational"; log_format = "eventchannel" })
$channels.Add(@{ location = "ISHAX-AMSI";                           log_format = "eventchannel" })

# DC-only channel (Directory Service events)
if ($IS_DC) {
    $channels.Add(@{ location = "Directory Service"; log_format = "eventchannel" })
}

$changed = $false
foreach ($ch in $channels) {
    $exists = $cfg.ossec_config.localfile | Where-Object { $_.location -eq $ch.location }
    if ($exists) {
        Write-OK "Channel already present: $($ch.location)"
        continue
    }
    $frag = $cfg.CreateElement("localfile")
    $loc  = $cfg.CreateElement("location");  $loc.InnerText = $ch.location
    $fmt  = $cfg.CreateElement("log_format"); $fmt.InnerText = $ch.log_format
    $frag.AppendChild($loc)  | Out-Null
    $frag.AppendChild($fmt)  | Out-Null
    $cfg.DocumentElement.AppendChild($frag) | Out-Null
    Write-OK "Added channel: $($ch.location)"
    $changed = $true
}

if ($changed) {
    $bak = "$WAZUH_CONF_PATH.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item $WAZUH_CONF_PATH $bak
    $cfg.Save($WAZUH_CONF_PATH)
    Write-OK "ossec.conf updated (backup: $bak)"
}

# == STEP 6.1: Disable Wazuh-native modules that pollute our detection pipeline =

Write-Step "Step 6.1: Disabling syscheck / vuln-detector / SCA / active-response"
# WHY: These Wazuh-native subsystems generate their own alerts that are NOT
# based on our Sigma rules. If left enabled they flood the pipeline with
# false-positive-like noise and make it impossible to validate detection logic.
# We only want raw event forwarding (localfile) — nothing else.

$confRaw = Get-Content $WAZUH_CONF_PATH -Raw

# -- syscheck: Wazuh FIM (file integrity). We handle this via Sysmon EID 11.
if ($confRaw -match "<syscheck>") {
    $confRaw = $confRaw -replace "(<syscheck>[\s\S]*?<disabled>)(no)(</disabled>)", '${1}yes${3}'
    # If there is no <disabled> tag, inject one
    if ($confRaw -notmatch "<syscheck>[\s\S]*?<disabled>") {
        $confRaw = $confRaw -replace "(<syscheck>)", '<syscheck><disabled>yes</disabled>'
    }
    Write-OK "syscheck disabled (would duplicate Sysmon EID 11 events)"
} else {
    Write-OK "syscheck not present in config"
}

# -- vulnerability-detector: runs its own vuln scans, unrelated to our pipeline
$confRaw = $confRaw -replace "(<vulnerability-detector>[\s\S]*?<enabled>)(yes)(</enabled>)", '${1}no${3}'
Write-OK "vulnerability-detector disabled"

# -- SCA (Security Configuration Assessment): generates policy-compliance alerts
$confRaw = $confRaw -replace "(<sca>[\s\S]*?<enabled>)(yes)(</enabled>)", '${1}no${3}'
Write-OK "SCA disabled"

# -- active-response: Wazuh can block IPs etc - dangerous in a lab / monitoring-only setup
$confRaw = $confRaw -replace "(<active-response>[\s\S]*?<disabled>)(no)(</disabled>)", '${1}yes${3}'
Write-OK "active-response disabled"

$confRaw | Set-Content $WAZUH_CONF_PATH -NoNewline
Write-OK "ossec.conf saved with all Wazuh-native modules disabled."

# == STEP 7: Start / Restart Wazuh Agent =======================================

Write-Step "Step 7: Starting WazuhSvc"

$svcW = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if (-not $svcW) { Write-Fail "WazuhSvc not found." }

if ($svcW.Status -eq "Running") {
    Restart-Service -Name "WazuhSvc" -Force
    Write-OK "WazuhSvc restarted to apply config."
} else {
    Start-Service -Name "WazuhSvc"
    Write-OK "WazuhSvc started."
}

Start-Sleep 5
$svcW.Refresh()
if ($svcW.Status -ne "Running") {
    Write-Fail "WazuhSvc failed to start. Check: C:\Program Files (x86)\ossec-agent\logs\ossec.log"
}

# (AMSI Watcher is now Step 4)

# == Final Summary ==============================================================

Write-Host "`n  ---------------------------- STATUS --------------------------------" -ForegroundColor Cyan
Write-Host "  Machine  : $env:COMPUTERNAME $(if ($IS_DC) { '[DOMAIN CONTROLLER]' } else { '[Endpoint]' })"
Write-Host "  Sysmon64 : $((Get-Service Sysmon64 -EA SilentlyContinue).Status)"
Write-Host "  WazuhSvc : $((Get-Service WazuhSvc -EA SilentlyContinue).Status)"
Write-Host "  AMSI Watcher : $((Get-Service ISHAXAmsiWatcher -EA SilentlyContinue).Status)"
Write-Host "  Manager  : $WazuhManagerIP"
Write-Host ""
Write-Host "  Audit Policy Summary:"
& auditpol /get /category:"Account Management","Logon/Logoff","DS Access" 2>$null |
    Where-Object { $_ -match "(Logon|Account|Directory|Kerberos)" } |
    ForEach-Object { Write-Host "    $_" }

Write-Host @"

  -------- PHASE 1 TESTING GATE - MANUAL TRIGGERS -------------------------

  Run these on THIS machine, then verify events appear in archives.json on
  the Oracle Cloud manager within the observed latency window.

  T1136.001 - Create Local Account (EID 4720):
    net user edr_test_local P@ssw0rd1! /add
    net user edr_test_local /delete

  T1543.003 - New Service (EID 7045 + Sysmon EID 1):
    sc create EDRTestSvc binPath= "C:\Windows\System32\calc.exe" start= demand
    sc delete EDRTestSvc

  T1021.001 - RDP logon (EID 4624 type 10):
    # Enable RDP, then RDP TO this machine from another host
    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" -Name fDenyTSConnections -Value 0

  T1110.x - Brute Force (EID 4625 x5+):
    for (`$i=0; `$i -lt 6; `$i++) { net use \\`$env:COMPUTERNAME\IPC$ /user:Administrator WrongPassword 2>`$null }

$(if ($IS_DC) { @"
  T1003.006 - DCSync (EID 4662):
    # Requires Mimikatz or Impacket (Run manually from your red-team toolkit)

  T1558.003 - Kerberoasting (EID 4769 + RC4):
    # Requires SPN-registered service accounts in AD (Run Rubeus manually)

  T1136.002 - Create Domain Account (EID 4741):
    New-ADUser -Name "EDRTestDomain" -AccountPassword (ConvertTo-SecureString "P@ssw0rd1!" -AsPlainText -Force)
    Remove-ADUser -Identity "EDRTestDomain" -Confirm:`$false
"@ })
  --------------------------------------------------------------------------
"@
