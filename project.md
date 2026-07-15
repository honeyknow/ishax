# ISHA-X EDR Project Summary

This project is a Windows endpoint detection lab built around Wazuh event collection, a Python SQLite detection pipeline, a FastAPI API, and a React dashboard. The intended use is local lab validation and portfolio demonstration, not production containment or active response.

## Detection Scope

The locked detection scope is exactly these techniques:

| Technique | Role in project | Primary signal |
|---|---|---|
| T1036 | Process masquerading | Sysmon EID 1 process creation with PE metadata mismatch |
| T1219 | Remote management tool abuse | Sysmon EID 1 process creation with RMM tool path checks |
| T1059.001 | PowerShell execution | AMSI content layer plus Sysmon command-line layer |
| T1059.005 | VBA / Office macro execution | AMSI content layer |
| T1059.007 | JavaScript / VBScript execution | AMSI content layer |
| T1027 | Obfuscation | Overlay score on AMSI content, not a standalone alert |
| T1543.003 | Windows service creation | System EID 7045, Security EID 4697, and sc.exe process creation |
| T1547.001 | Registry Run key persistence | Sysmon EID 13 registry value set |

Any other technique references in legacy files, test assets, or old data are not active project scope unless explicitly reintroduced.

## High-Level Architecture

```text
Windows endpoint
  |
  |-- Sysmon
  |     |-- process creation, registry, file, network, process tree data
  |
  |-- Windows Security/System/PowerShell logs
  |     |-- service install and supporting event telemetry
  |
  |-- ISHA-X AMSI ETW watcher
        |-- AMSI script buffer metadata and content hex

Wazuh Agent
  |
  |-- ships Windows Event Log events to Wazuh Manager

Wazuh Manager container
  |
  |-- /var/ossec/logs/archives/archives.json

server/pipeline/ingestor.py
  |
  |-- tails archives.json through docker exec
  |-- normalizes Wazuh/Sysmon/AMSI fields
  |-- writes server/pipeline/edr.db
  |-- calls detector.py for rule execution

server/pipeline/detector.py
  |
  |-- runs AMSI content matching
  |-- runs pySigma converted SQLite queries
  |-- writes raw_detections
  |-- merges layers into final alerts

server/backend/main.py
  |
  |-- exposes health, alerts, evidence, rules, timeline, AMSI, hosts, process tree APIs

server/frontend
  |
  |-- React/Vite dashboard for overview, threat hunt, firehose, and rules engine
```

## Runtime Pipeline Workflow

1. Endpoint setup installs Sysmon, Wazuh Agent, and the AMSI watcher.
2. Sysmon captures process, registry, file, network, and process lifecycle events.
3. The AMSI watcher subscribes to the Microsoft AMSI ETW provider and writes captured script scan events into the `ISHAX-AMSI` Windows Event Log channel.
4. Wazuh Agent reads the configured Windows Event Log channels and forwards them to Wazuh Manager.
5. Wazuh Manager writes normalized event records into `archives.json`.
6. `server/pipeline/ingestor.py` tails `archives.json`, normalizes fields, and inserts rows into `events`.
7. The ingestor updates process graph tables:
   - `process_nodes` from Sysmon process start/stop events.
   - `process_edges` from network, file, and registry events.
8. `server/pipeline/detector.py` receives each normalized event and runs:
   - AMSI Layer A for T1059.001, T1059.005, T1059.007, and T1027 overlay score.
   - Sigma Layer B for process, service, and registry detections.
9. Matching layer detections are staged into `raw_detections`.
10. Merge logic groups detections by technique, process GUID, endpoint, and time window.
11. Final alerts are inserted into `alerts` and linked to context events through `alert_event_links`.
12. FastAPI reads SQLite and exposes alert/evidence APIs.
13. React dashboard polls the API and renders analyst views.

## SQLite Data Model

| Table | Purpose |
|---|---|
| `events` | Wazuh event records with mapped fields, `raw_json_original` for forensic replay, and `raw_json_normalized` for pipeline parsing. |
| `raw_detections` | Pre-alert detection hits from AMSI or Sigma layers. |
| `alerts` | Final merged alert records. |
| `alert_event_links` | Context links between alerts and source/window events. |
| `process_nodes` | Process graph nodes keyed by process GUID. |
| `process_edges` | Network/file/registry artifacts tied to process GUIDs. |
| `rules` | YAML rule metadata mirrored into SQLite. |
| `ingestion_state` | Archive offset tracking for tailing. |
| `threat_intel_queue` | Indicators queued for enrichment. |
| `threat_intel_cache` | Cached enrichment results. |

## Main Folders

| Path | Purpose |
|---|---|
| `endpoint/` | Minimal endpoint deployment package. Keep only files needed on a monitored Windows endpoint. |
| `server/` | Local lab server: Wazuh compose, pipeline, API, and frontend. |
| `server/pipeline/` | SQLite schema, ingestor, detector, Sigma rules, migrations, and verification helpers. |
| `server/backend/` | FastAPI API over the SQLite database. |
| `server/frontend/` | React/Vite analyst dashboard. |
| `server/wazuh/` | Wazuh Docker Compose and local Wazuh configuration/certs. |
| `docs/` | Deep implementation notes and supporting design documentation. |
| `legacy/` | Historical rules and manifest retained for reference only. |
| `recovery/` | Nonessential or bulky material moved out of active folders but kept recoverable. |
| `garbage/` | Old debug scripts, raw dumps, and scratch files. Treat as non-runtime material. |

## Startup And Shutdown

Use root launchers:

```bat
START EDR.bat
STOP EDR.bat
```

The BAT files resolve the project path from their own location. `server/start_local.ps1` resolves all child directories from `$PSScriptRoot`, so the project can be moved to a different folder without editing paths.

## Endpoint Package

Current endpoint runtime files:

| File | Purpose |
|---|---|
| `SETUP ENDPOINT.bat` | Admin launcher for endpoint installation. Prompts for Wazuh Manager address. |
| `UNINSTALL ENDPOINT.bat` | Admin launcher for uninstall. |
| `endpoint_setup.ps1` | Installs/configures Sysmon, Wazuh Agent, audit policy, and AMSI watcher. |
| `uninstall_endpoint.ps1` | Removes endpoint components. |
| `sysmon_config.xml` | Sysmon configuration needed for project detections. |
| `amsi_watcher.exe` | AMSI ETW watcher binary. |
| `amsi_sanity_check.ps1` | Manual endpoint verification helper. |

Moved out of active endpoint package:

| Moved item | New location | Reason |
|---|---|---|
| `endpoint/ART_Offline` | `recovery/endpoint_extras/ART_Offline` | Bulky Atomic Red Team test pack, not required for endpoint deployment. |
| `endpoint/Automated_Test_Runner.ps1` | `recovery/endpoint_extras/Automated_Test_Runner.ps1` | Lab test helper, not required for deployment. |

## Current Known Technical Risks

See `master_technical_report.md` for detailed audit status. Key active risks include:

| Risk | Current status |
|---|---|
| AI shell | Removed from active backend/frontend during Phase 2 cleanup. |
| API schema drift | Fixed in Phase 2: endpoints derive numeric severity scores from textual `severity`. |
| Rules API subtechnique parsing | Fixed in Phase 2: exact IDs such as `T1059.001` and `T1547.001` are preserved. |
| Live verification | Not all 8 techniques have fresh live endpoint proof. |
| Legacy references | Some old files still mention out-of-scope techniques. |
