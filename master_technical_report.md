# ISHAX EDR Master Technical Report

Date: 2026-07-13
Phase: Phase 2/3 implementation pass after Phase 1 audit
Status: Core Phase 2/3 repository work complete; live endpoint re-test still required

## Executive Status

| Area | Status | Evidence |
|---|---|---|
| Exact 8-technique scope | Fixed in active docs/code | Root `README.md`, `project.md`, Sigma rules, and detector header now align to T1036, T1219, T1059.001, T1059.005, T1059.007, T1027 overlay, T1543.003, T1547.001. |
| Endpoint package cleanup | Complete | Active `endpoint/` contains only deployment/runtime files; bulky ART/test runner content moved to `recovery/endpoint_extras/`. |
| Dynamic paths | Complete for active scripts touched in this pass | Root BAT files, `server/start_local.ps1`, endpoint install/uninstall scripts, frontend proxy, and DB utilities derive paths from script/project location. |
| AI removal | Complete | Active backend/frontend AI route, panel, API client method, and modal action removed. |
| API schema drift | Fixed | `/stats`, `/timeline`, and `/alerts/correlations` derive numeric scores from textual `severity`; no missing `alerts.severity_score` dependency remains in those endpoints. |
| Rule metadata | Fixed | `/rules` preserves exact MITRE subtechnique IDs; alert payloads include `rule_id`. |
| Rule toggle safety | Fixed | Unknown loaded-rule IDs return `404 Rule not found` when called with the required toggle payload. |
| Malformed/invalid config handling | Improved | Malformed AMSI payloads and invalid `disabled_rules.json` now emit warnings instead of silently defaulting. |
| Live detection proof | Not complete | Repository/API validation passed, but all 8 techniques still need fresh endpoint-generated test evidence. |

## Changes Applied

| Area | Change |
|---|---|
| Full architecture docs | Added `project.md` with project summary, folder architecture, data model, and end-to-end workflow. |
| Lab setup docs | Added `SETUP.md` for complete local lab setup, startup, endpoint install, verification, and cleanup. |
| Folder docs | Added README files across endpoint, server, backend, pipeline, Sigma rules, frontend, Wazuh, docs, legacy, garbage, recovery, and recovery endpoint extras. |
| Root README | Replaced stale/mojibake content with a clean current README matching the active 8-technique scope and current folder layout. |
| Root scripts | Rewrote `START EDR.bat` and `STOP EDR.bat` with relative path resolution, preflight checks, and clearer output. |
| Server startup | Rewrote `server/start_local.ps1` with dynamic project-root discovery, configurable ports, health handling, browser control, and project-scoped stop/status behavior. |
| Frontend proxy | Updated `server/frontend/vite.config.ts` to use `VITE_API_TARGET` and `VITE_DEV_PORT`. |
| Endpoint setup | Reworked `endpoint/SETUP ENDPOINT.bat` and `endpoint/endpoint_setup.ps1` to prompt for manager address, avoid hardcoded lab IPs, and stage runtime files under Program Files dynamically. |
| Endpoint uninstall | Reworked `endpoint/UNINSTALL ENDPOINT.bat` and `endpoint/uninstall_endpoint.ps1`; uninstall removes both current and legacy AMSI watcher service names. |
| Endpoint cleanup | Moved `endpoint/ART_Offline` and `endpoint/Automated_Test_Runner.ps1` to `recovery/endpoint_extras/`. |
| Recovery runner | Updated moved `Automated_Test_Runner.ps1` to resolve `ART_Offline` from its own folder. |
| DB utilities | Updated DB clear/migration/verification scripts to resolve `server/pipeline/edr.db` dynamically. |
| Backend API | Removed AI route, fixed severity drift, preserved exact subtechniques, added `rule_id`, hardened disabled-rule loading/saving, and rejected unknown rule toggles. |
| Frontend UI | Removed AI panel/client/action wiring. |
| Raw JSON preservation | Split event payload storage into `raw_json_original` and `raw_json_normalized`, while keeping `raw_json` as a normalized compatibility alias. |
| Pipeline | Removed active out-of-scope ingest-time technique candidates, improved malformed AMSI warnings, improved detector failure logging, and documented the 8-technique detector scope. |
| Dependencies | Added pySigma requirements to `server/pipeline/requirements.txt`. |
| Stale generated log | Removed `server/pipeline/ingestor.log` because it contained a machine-specific historical path. |

## Current Active Runtime Architecture

```text
Windows endpoint
  -> Sysmon + AMSI watcher + Wazuh agent
  -> Wazuh manager archives.json
  -> server/pipeline/ingestor.py
  -> server/pipeline/edr.db
  -> server/pipeline/detector.py
  -> server/backend/main.py
  -> server/frontend
```

Layer A is Python AMSI content detection. Layer B is Sigma YAML detection through pySigma. Both write to `raw_detections`; merge logic writes final `alerts`. T1027 is an obfuscation overlay score, not a separate alert source.

## Technique Scope

| Technique | Active source |
|---|---|
| T1036 | Sigma rule: process masquerading |
| T1219 | Sigma rule: RMM abuse |
| T1059.001 | AMSI patterns plus Sigma command-line detection |
| T1059.005 | AMSI patterns plus metadata YAML |
| T1059.007 | AMSI patterns plus metadata YAML |
| T1027 | Obfuscation score overlay on AMSI detections |
| T1543.003 | Sigma service creation rules |
| T1547.001 | Sigma Run key rule |

T1047, T1105, and T1055 remain outside the current active scope.

## Validation Results

| Check | Result |
|---|---|
| Python compile | Passed for backend, pipeline, ingestor, detector, migration, verification, and DB utility scripts. |
| PowerShell parser | Passed for `server/start_local.ps1`, endpoint setup/uninstall scripts, and recovery test runner. |
| Frontend lint | `npm run lint` passed. |
| Frontend build | `npm run build` passed; Vite reported only the existing >500 kB chunk-size warning. |
| Malformed AMSI payload | Passed: `ingestor.normalise()` warned and returned a normalized event without crashing. |
| Raw JSON split | Passed: ingest path now writes `raw_json_original`, `raw_json_normalized`, and compatibility `raw_json`; backend reads normalized payloads by default. |
| Backend invalid `disabled_rules.json` | Passed: warning emitted and empty set returned. |
| Detector invalid `disabled_rules.json` | Passed: warning emitted and empty cache returned. |
| FastAPI `/health` | 200 in TestClient. |
| FastAPI `/stats` | 200 in TestClient. |
| FastAPI `/timeline?host_id=all&hours=168` | 200 in TestClient. |
| FastAPI `/alerts/correlations` | 200 in TestClient. |
| FastAPI `/rules` | 200 in TestClient; exact technique IDs returned: T1036, T1059.001, T1059.005, T1059.007, T1219, T1543.003, T1547.001. |
| FastAPI `/alerts?limit=1` | 200 in TestClient; alert payload includes `rule_id`. |
| Unknown rule toggle | `POST /rules/not-a-real-rule/toggle` with JSON body returned 404. |
| Active AI scan | No active backend/frontend references to `AIPanel`, `queryAI`, `/ai/query`, Groq, or "View Intel in AI". |
| Active hardcoded-path scan | No active runtime/doc matches for old repo path or old hardcoded endpoint manager IP; historical/recovery content is separated. |

## Remaining Work Before Claiming Full Operational Coverage

| Item | Required action |
|---|---|
| Live endpoint validation | Generate fresh endpoint telemetry for all 8 scoped techniques and capture alert/evidence proof. |
| Rule suppression live proof | Disable one rule, generate matching endpoint telemetry, confirm suppression, re-enable rule, and confirm alert returns. |
| Optional security hardening | Add real backend API-key enforcement if the lab is exposed outside localhost/LAN. |
| Optional frontend optimization | Code-split the frontend bundle if the Vite chunk warning matters. |

## Operational Notes

- Restart any already-running Uvicorn/Vite process after these changes so it loads the edited source.
- Use `START EDR.bat` / `STOP EDR.bat` from the project root.
- Use `endpoint/SETUP ENDPOINT.bat` from an elevated shell on the endpoint.
- The active endpoint package is intentionally minimal; lab-only test assets are in `recovery/endpoint_extras/`.
