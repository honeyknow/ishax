# ISHA-X EDR Lab

ISHAX is a Windows endpoint detection lab that collects Windows/Sysmon/AMSI telemetry through Wazuh, normalizes it into SQLite, runs deterministic detections, and exposes the result through a FastAPI + React dashboard.

## Current Detection Scope

| Technique | Coverage |
|---|---|
| T1036 | Process masquerading via Sysmon EID 1 PE metadata/path mismatch |
| T1219 | Remote management tool abuse via Sysmon EID 1 known RMM process/path indicators |
| T1059.001 | PowerShell via AMSI content patterns plus command-line Sigma rules |
| T1059.005 | VBA/Office macros via AMSI content patterns |
| T1059.007 | JavaScript/VBScript via AMSI content patterns |
| T1027 | Obfuscation overlay score on AMSI content; not a standalone alert |
| T1543.003 | Windows service creation via EID 7045/4697 plus command-line fallback |
| T1547.001 | Registry Run key persistence via Sysmon EID 13 |

## Pipeline

```text
Windows endpoint
  -> Wazuh agent
  -> Wazuh manager archives.json
  -> server/pipeline/ingestor.py
  -> server/pipeline/edr.db
  -> server/backend/main.py
  -> server/frontend
```

Detection has two layers:

- Layer A: Python AMSI content matching in `server/pipeline/detector.py`.
- Layer B: Sigma YAML rules in `server/pipeline/sigma_rules`, converted through pySigma.

Layer A and Layer B write to `raw_detections`; merge logic creates final `alerts`. T1027 is attached as an obfuscation score badge/field.

## Main Folders

| Path | Purpose |
|---|---|
| `endpoint/` | Minimal deployable endpoint package: setup/uninstall scripts, Sysmon config, AMSI watcher binary. |
| `server/pipeline/` | Ingestor, detector, SQLite schema/database, Sigma rules, pipeline utilities. |
| `server/backend/` | FastAPI dashboard API. |
| `server/frontend/` | React/Vite dashboard UI. |
| `server/wazuh/` | Wazuh Docker lab configuration. |
| `docs/` | Supporting technical notes. |
| `legacy/` | Historical reference only. |
| `recovery/endpoint_extras/` | Lab-only endpoint extras moved out of the deployable endpoint package. |
| `garbage/` | Old dumps/logs/raw material retained only for recovery/reference. |

## Quick Start

Full setup instructions are in `SETUP.md`.

```powershell
.\START EDR.bat
```

This starts the local Wazuh stack and launches `server/start_local.ps1`, which derives paths from the current project folder. The project is intended to be movable between systems without hardcoded repository paths.

Stop everything:

```powershell
.\STOP EDR.bat
```

## Endpoint Setup

Run from an elevated PowerShell/CMD on the Windows endpoint:

```powershell
.\endpoint\SETUP ENDPOINT.bat
```

The BAT prompts for the Wazuh manager IP/DNS and calls `endpoint_setup.ps1`. Runtime files are staged under `%ProgramFiles(x86)%\ISHA-X` by default.

Uninstall:

```powershell
.\endpoint\UNINSTALL ENDPOINT.bat
```

## Lab Test Assets

The active endpoint package is intentionally minimal. Bulky Atomic Red Team assets and the old automated runner were moved to:

```text
recovery/endpoint_extras/
```

Use those only for lab testing, not endpoint deployment.

## API and UI Notes

- `GET /health` reports DB/pipeline health.
- `GET /alerts` returns alert summaries including `rule_id`.
- `GET /rules` preserves exact MITRE subtechnique IDs such as `T1059.001`.
- `POST /rules/{rule_id}/toggle` only accepts known loaded Sigma rule IDs.
- AI/chat functionality has been removed from active backend and frontend code.

## Known Gaps

- Live endpoint retesting for all 8 scoped techniques is still required before claiming full operational coverage.
- AMSI bypass can defeat Layer A; Layer B command-line telemetry may still fire with medium confidence.
- If the `ISHAXAmsi` ETW watcher stops, AMSI events stop flowing.
- T1047, T1105, and T1055 are outside the current active scope.
