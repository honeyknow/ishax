# ISHA-X EDR Lab Setup Guide

This guide sets up the full local lab: Wazuh Manager, Python pipeline, FastAPI backend, React dashboard, and one Windows endpoint.

## 1. Requirements

Install these on the server machine:

| Dependency | Required for |
|---|---|
| Windows 10/11 or Windows Server | Primary supported lab host |
| Docker Desktop | Wazuh Manager container |
| Python 3.10+ | Ingestor and FastAPI backend |
| Node.js LTS with npm | React/Vite dashboard |
| PowerShell 5+ | Windows launchers and endpoint scripts |
| Administrator rights | Endpoint setup, Sysmon, Wazuh Agent, AMSI watcher |

## 2. Project Placement

The project can be placed in any folder. The active startup scripts resolve paths dynamically from their own locations.

Example:

```powershell
cd C:\Labs\latestedr
```

Do not hardcode this path in scripts. If a tool needs the project root, derive it from the script location.

## 3. Python Environment

From the project root:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r server\backend\requirements.txt
pip install -r server\pipeline\requirements.txt
```

The pipeline requires pySigma at runtime because `detector.py` imports Sigma modules. If your environment does not already have it:

```powershell
pip install pysigma sigma-cli
```

## 4. Frontend Dependencies

```powershell
cd server\frontend
npm install
cd ..\..
```

## 5. Start The Server Stack

Start Docker Desktop first, then run:

```bat
START EDR.bat
```

Expected services:

| Service | URL / location |
|---|---|
| Dashboard | `http://localhost:5173` |
| API health | `http://localhost:8000/health` |
| Wazuh Manager API | `http://localhost:55000` |
| SQLite DB | `server/pipeline/edr.db` |

Status check:

```powershell
powershell -ExecutionPolicy Bypass -File server\start_local.ps1 -Status
```

Stop:

```bat
STOP EDR.bat
```

## 6. Endpoint Setup

Copy the `endpoint/` folder to the Windows endpoint or run it locally if the endpoint and server are the same machine.

Required files in `endpoint/`:

| File | Required |
|---|---|
| `SETUP ENDPOINT.bat` | Yes |
| `UNINSTALL ENDPOINT.bat` | Yes |
| `endpoint_setup.ps1` | Yes |
| `uninstall_endpoint.ps1` | Yes |
| `sysmon_config.xml` | Yes |
| `amsi_watcher.exe` | Yes |
| `amsi_sanity_check.ps1` | Optional verification helper |

Run as Administrator:

```bat
endpoint\SETUP ENDPOINT.bat
```

When prompted, enter the Wazuh Manager IP or DNS name.

Use `127.0.0.1` only if the endpoint is the same machine running the server stack. For a VM or another LAN machine, use the server machine LAN IP.

The endpoint installer stages runtime files into:

```text
%ProgramFiles(x86)%\ISHA-X
```

That avoids binding Windows services to a temporary extraction folder.

## 7. Network Requirements

The endpoint must reach the server on:

| Port | Purpose |
|---:|---|
| 1514/tcp | Wazuh event forwarding |
| 1515/tcp | Wazuh agent enrollment if enabled by the compose/config |
| 8000/tcp | Optional deployment API routes |
| 5173/tcp | Dashboard access from browser |

For local-only testing, localhost is enough. For VM/LAN testing, allow inbound firewall rules on the server.

## 8. Verify Endpoint Services

On the endpoint:

```powershell
sc query WazuhSvc
sc query Sysmon64
sc query ISHAXAmsiWatcher
```

Optional AMSI check:

```powershell
powershell -ExecutionPolicy Bypass -File endpoint\amsi_sanity_check.ps1
```

## 9. Verify API Data Flow

On the server:

```powershell
Invoke-RestMethod http://localhost:8000/health | ConvertTo-Json -Depth 6
Invoke-RestMethod http://localhost:8000/rules | ConvertTo-Json -Depth 6
Invoke-RestMethod "http://localhost:8000/alerts?limit=5" | ConvertTo-Json -Depth 8
```

Healthy data flow looks like:

1. `events` count increases after endpoint activity.
2. `last_event` updates to a recent timestamp.
3. `warnings` no longer include stale event warnings.
4. Alert count increases only when a scoped detection rule matches.

## 10. Logs

| Log | Purpose |
|---|---|
| `server/pipeline/ingestor.log` | Ingestor stdout |
| `server/pipeline/ingestor.log.err` | Ingestor stderr |
| `server/backend/backend.log` | FastAPI stdout |
| `server/backend/backend.log.err` | FastAPI stderr |
| `server/frontend/frontend.log` | Vite stdout |
| `server/frontend/frontend.log.err` | Vite stderr |

## 11. Recovery Material

Non-runtime endpoint extras are stored in:

```text
recovery/endpoint_extras/
```

Use this folder if you need Atomic Red Team offline tests or older endpoint test runners. Do not copy it into the endpoint deployment package unless you are intentionally doing test execution.

## 12. Cleanup / Uninstall

Endpoint uninstall:

```bat
endpoint\UNINSTALL ENDPOINT.bat
```

Server shutdown:

```bat
STOP EDR.bat
```

Docker cleanup if needed:

```powershell
cd server\wazuh
docker compose down
```

