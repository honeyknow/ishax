# ISHA-X EDR - Local Startup Script
# Run:    .\start_local.ps1
# Stop:   .\start_local.ps1 -Stop
# Status: .\start_local.ps1 -Status

param(
    [switch]$Stop,
    [switch]$Status,
    [int]$BackendPort = 8000,
    [int]$FrontendPort = 5173,
    [switch]$NoBrowser
)

$ROOT         = $PSScriptRoot
$COMPOSE_DIR  = Join-Path $ROOT "wazuh"
$PIPELINE_DIR = Join-Path $ROOT "pipeline"
$BACKEND_DIR  = Join-Path $ROOT "backend"
$FRONTEND_DIR = Join-Path $ROOT "frontend"

$BackendUrl  = "http://localhost:$BackendPort"
$FrontendUrl = "http://localhost:$FrontendPort"

function Write-Step($msg) { Write-Host "`n[STEP] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "  [OK]   $msg" -ForegroundColor Green }
function Write-Warn($msg) { Write-Host "  [WARN] $msg" -ForegroundColor Yellow }
function Write-Fail($msg) { Write-Host "  [FAIL] $msg" -ForegroundColor Red }

function Stop-ProcessTreeFromPidFile($pidFile, $name) {
    if (-not (Test-Path $pidFile)) { return }

    $procId = Get-Content $pidFile -ErrorAction SilentlyContinue
    if ($procId -match '^\d+$') {
        Write-Host "  Stopping $name (PID: $procId)..." -ForegroundColor DarkGray
        taskkill.exe /PID $procId /T /F > $null 2>&1
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Stop-OrphanProjectProcesses {
    $rootEscaped = [regex]::Escape((Resolve-Path $ROOT).Path)
    $query = "SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name='python.exe' OR Name='node.exe' OR Name='npm.cmd'"
    Get-CimInstance -Query $query -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and (
            ($_.CommandLine -match $rootEscaped) -or
            ($_.CommandLine -match "ingestor\.py") -or
            ($_.CommandLine -match "uvicorn main:app") -or
            ($_.CommandLine -match "vite")
        ) } |
        ForEach-Object {
            Write-Host "  Stopping orphan project process (PID: $($_.ProcessId))..." -ForegroundColor DarkGray
            taskkill.exe /PID $_.ProcessId /T /F > $null 2>&1
        }
}

function Test-Command($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

if ($Stop) {
    Write-Step "Stopping ISHA-X EDR services"

    Stop-ProcessTreeFromPidFile (Join-Path $PIPELINE_DIR "ingestor.pid") "Ingestor"
    Stop-ProcessTreeFromPidFile (Join-Path $BACKEND_DIR "backend.pid") "Backend API"
    Stop-ProcessTreeFromPidFile (Join-Path $FRONTEND_DIR "frontend.pid") "Frontend UI"
    Stop-OrphanProjectProcesses

    if ((Test-Path $COMPOSE_DIR) -and (Test-Command "docker")) {
        Write-Host "  Stopping Wazuh containers..." -ForegroundColor DarkGray
        Push-Location $COMPOSE_DIR
        docker compose -f docker-compose.yml down > $null 2>&1
        Pop-Location
    }

    Write-Ok "Stop sequence complete."
    exit 0
}

if ($Status) {
    Write-Step "Docker containers"
    if (Test-Command "docker") {
        Push-Location $COMPOSE_DIR
        docker compose -f docker-compose.yml ps
        Pop-Location
    } else {
        Write-Warn "Docker command not found."
    }

    Write-Step "Backend API"
    try {
        $r = Invoke-RestMethod "$BackendUrl/health" -TimeoutSec 3 -ErrorAction Stop
        Write-Ok "Running at $BackendUrl - status: $($r.status)"
    } catch {
        Write-Warn "Backend not reachable at $BackendUrl"
    }

    Write-Step "Frontend UI"
    try {
        Invoke-WebRequest $FrontendUrl -TimeoutSec 3 -UseBasicParsing -ErrorAction Stop | Out-Null
        Write-Ok "Running at $FrontendUrl"
    } catch {
        Write-Warn "Frontend not reachable at $FrontendUrl"
    }
    exit 0
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host " ISHA-X EDR - Local Lab Startup" -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta

Write-Step "Preflight"
if (-not (Test-Command "docker")) { Write-Fail "Docker is not installed or not in PATH."; exit 1 }
if (-not (Test-Command "python")) { Write-Fail "Python is not installed or not in PATH."; exit 1 }
if (-not (Test-Command "npm") -and -not (Test-Command "npm.cmd")) { Write-Fail "npm is not installed or not in PATH."; exit 1 }
Write-Ok "Required commands found."

Write-Host "  Cleaning up existing processes and ports..." -ForegroundColor DarkGray
Stop-ProcessTreeFromPidFile (Join-Path $PIPELINE_DIR "ingestor.pid") "Ingestor"
Stop-ProcessTreeFromPidFile (Join-Path $BACKEND_DIR "backend.pid") "Backend API"
Stop-ProcessTreeFromPidFile (Join-Path $FRONTEND_DIR "frontend.pid") "Frontend UI"
Stop-OrphanProjectProcesses

function Kill-Port($port) {
    $pids = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique
    foreach ($p in $pids) {
        if ($p -and $p -ne 0) {
            Write-Host "  Killing PID $p on port $port..." -ForegroundColor DarkGray
            try { Stop-Process -Id $p -Force -ErrorAction Stop } catch {}
            Start-Sleep -Milliseconds 500
        }
    }
}
Kill-Port $BackendPort
Kill-Port $FrontendPort

# Clear stale log files so we always see fresh output
Remove-Item (Join-Path $BACKEND_DIR "backend.log.err") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $BACKEND_DIR "backend.log") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $PIPELINE_DIR "ingestor.log") -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $FRONTEND_DIR "frontend.log") -Force -ErrorAction SilentlyContinue
Write-Ok "Required commands found."

docker info > $null 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Docker is installed but the daemon is not running. Start Docker Desktop first."
    exit 1
}
Write-Ok "Docker daemon is running."

Write-Step "Starting Wazuh Manager"
$existing = docker ps -q --filter "name=wazuh" 2>$null
if ($existing) {
    Write-Host "  Recycling existing Wazuh containers..." -ForegroundColor DarkGray
    docker stop $existing | Out-Null
    docker rm $existing | Out-Null
}

Push-Location $COMPOSE_DIR
docker compose -f docker-compose.yml up -d
$composeExit = $LASTEXITCODE
Pop-Location
if ($composeExit -ne 0) { Write-Fail "Docker Compose failed. Check server/wazuh/docker-compose.yml."; exit 1 }

$wazuhReady = $false
for ($i = 1; $i -le 15; $i++) {
    Start-Sleep -Seconds 2
    $container = docker ps --format "{{.Names}}" | Where-Object { $_ -match "wazuh" } | Select-Object -First 1
    if ($container) { $wazuhReady = $true; break }
    Write-Host -NoNewline "."
}
Write-Host ""
if ($wazuhReady) { Write-Ok "Wazuh container is running." } else { Write-Warn "Wazuh did not appear in docker ps yet." }

Write-Step "Starting ingestor"
$ingestorLog = Join-Path $PIPELINE_DIR "ingestor.log"
$ingestorPid = Join-Path $PIPELINE_DIR "ingestor.pid"
$env:ARCHIVES_JSON = "docker"
$env:MULTI_TENANT   = "1"
# EDR_DB_PATH no longer used in multi-tenant mode; routing via master.db
Remove-Item Env:\EDR_DB_PATH -ErrorAction SilentlyContinue


$ingestor = Start-Process -FilePath "python" `
    -ArgumentList "ingestor.py" `
    -WorkingDirectory $PIPELINE_DIR `
    -WindowStyle Hidden `
    -PassThru `
    -RedirectStandardOutput $ingestorLog `
    -RedirectStandardError "$ingestorLog.err"

$ingestor.Id | Out-File $ingestorPid -Encoding UTF8
Start-Sleep -Seconds 2
if ($ingestor.HasExited) { Write-Fail "Ingestor exited early. Check $ingestorLog"; exit 1 }
Write-Ok "Ingestor started. PID: $($ingestor.Id)"

Write-Step "Starting backend API"
$backendLog = Join-Path $BACKEND_DIR "backend.log"
$backendPid = Join-Path $BACKEND_DIR "backend.pid"

$backend = Start-Process -FilePath "python" `
    -ArgumentList "-m uvicorn main:app --host 0.0.0.0 --port $BackendPort" `
    -WorkingDirectory $BACKEND_DIR `
    -WindowStyle Hidden `
    -PassThru `
    -RedirectStandardOutput $backendLog `
    -RedirectStandardError "$backendLog.err"

$backend.Id | Out-File $backendPid -Encoding UTF8
$backendReady = $false
for ($i = 1; $i -le 60; $i++) {
    Start-Sleep -Seconds 1
    if ($backend.HasExited) { break }
    try {
        $health = Invoke-RestMethod "$BackendUrl/health" -TimeoutSec 30 -ErrorAction Stop
        if ($health.status -in @("healthy", "degraded", "empty", "ok")) {
            $backendReady = $true
            break
        }
    } catch {}
}
if (-not $backendReady) { Write-Fail "Backend not ready. Check $backendLog"; exit 1 }
Write-Ok "Backend ready at $BackendUrl - status: $($health.status)"

Write-Step "Starting frontend UI"
$frontendLog = Join-Path $FRONTEND_DIR "frontend.log"
$frontendPid = Join-Path $FRONTEND_DIR "frontend.pid"
$npmCmd = if (Get-Command "npm.cmd" -ErrorAction SilentlyContinue) { "npm.cmd" } else { "npm" }
$env:VITE_API_TARGET = $BackendUrl

$frontend = Start-Process -FilePath $npmCmd `
    -ArgumentList "run dev -- --host 0.0.0.0 --port $FrontendPort" `
    -WorkingDirectory $FRONTEND_DIR `
    -WindowStyle Hidden `
    -PassThru `
    -RedirectStandardOutput $frontendLog `
    -RedirectStandardError "$frontendLog.err"

$frontend.Id | Out-File $frontendPid -Encoding UTF8
$frontendReady = $false
for ($i = 1; $i -le 20; $i++) {
    Start-Sleep -Seconds 1
    if ($frontend.HasExited) { break }
    try {
        Invoke-WebRequest $FrontendUrl -TimeoutSec 1 -UseBasicParsing -ErrorAction Stop | Out-Null
        $frontendReady = $true
        break
    } catch {}
}

if ($frontendReady) {
    Write-Ok "Frontend ready at $FrontendUrl"
    if (-not $NoBrowser) { Start-Process $FrontendUrl }
} else {
    Write-Warn "Frontend may still be starting. Check $frontendLog"
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host " ISHA-X EDR stack is running" -ForegroundColor Green
Write-Host " Dashboard : $FrontendUrl" -ForegroundColor Green
Write-Host " API       : $BackendUrl/health" -ForegroundColor Green
Write-Host " Stop      : STOP EDR.bat" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
