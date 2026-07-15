# Database README

This document explains the SQLite database used by the pipeline in `server/pipeline/edr.db`.
It is written as a field-level data dictionary so you can trace each column back to its source,
see where it is consumed, and understand which values are missing from the raw logs.

## How the database is used

```text
Wazuh archives.json
  -> ingestor.py
  -> events
  -> detector.py
  -> raw_detections
  -> alerts
  -> backend main.py / frontend UI

Sysmon process data
  -> process_nodes / process_edges

Alert-derived indicators
  -> threat_intel_queue
  -> threat_intel_worker.py
  -> threat_intel_cache

Sigma YAML rules
  -> rules
  -> /rules API and Rules UI
```

## Source Legend

Use this legend when reading the tables below:

- `Wazuh envelope`: fields that come from the outer Wazuh JSON wrapper.
- `Windows system`: fields that come from the Windows Event `system` block.
- `Windows eventdata`: fields that come from the Windows Event `eventdata` block.
- `AMSI payload`: fields that come from the `ISHAX-AMSI` watcher JSON payload.
- `Derived in ingestor`: fields created or normalized by `server/pipeline/ingestor.py`.
- `Derived in detector`: fields created by `server/pipeline/detector.py`.
- `Derived in backend`: fields computed in `server/backend/main.py` and returned by API responses.
- `Generated`: internal fields with no direct raw-log source.

## Raw Log Coverage Matrix

This is the short version of the important source mapping:

| Raw event type | Common database fields |
|---|---|
| Wazuh wrapper | `wazuh_id`, `wazuh_ts`, `wazuh_ts_epoch`, `agent_*`, `raw_json_original`, `raw_json_normalized`, `raw_json` |
| Sysmon EID 1 | `process_guid`, `parent_process_guid`, `image_path`, `command_line`, `parent_image`, `parent_command_line`, `original_file_name`, `process_path`, `process_hash`, `hashes`, `username` |
| Sysmon EID 3 | `destination_ip`, `destination_port`, `source_ip`, `source_image`, `granted_access` |
| Sysmon EID 5 | `end_time` in `process_nodes` |
| Sysmon EID 11 / 23 | `target_filename`, `process_edges.target_label` |
| Sysmon EID 12 / 13 / 14 | `target_object`, `registry_path`, `access_mask`, `details`, `properties` |
| Security 4697 / System 7045 | `service_name`, `service_binary_path`, `source_event_id`, `source_channel` |
| PowerShell 4104 | `technique_candidate` heuristics, command/script text when present |
| `ISHAX-AMSI` channel | `amsi_scan_result`, `amsi_content_name`, `amsi_content_hex`, `process_guid` inside payload |

Not every raw log contains every field. In this project, nulls are normal and expected.
The ingest layer fills what it can, and missing values should be treated as "not present in
that event type" unless the doc says otherwise.

## Table: events

This is the normalized telemetry table. It is the main landing zone for Wazuh archive events.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `id` | SQLite autoincrement | All joins and foreign keys | Generated, not from raw logs. |
| `wazuh_id` | SHA256 of `timestamp + raw_json_original` in `ingestor.py` | Deduplication, alert linkage, stable event identity | Generated. It is not the upstream Wazuh `id`. |
| `wazuh_ts` | Wazuh envelope `timestamp` | Sorting, UI timestamps, health checks | Missing only if the source line itself is invalid. |
| `wazuh_ts_epoch` | Derived from `wazuh_ts` | Range filters, lag checks, process windows | Generated. |
| `agent_id` | Wazuh envelope `agent.id` | Host grouping and evidence labels | May be empty on malformed wrapper records. |
| `agent_name` | Wazuh envelope `agent.name` | Host grouping, process trees, evidence | Used as the practical endpoint key. |
| `agent_ip` | Wazuh envelope `agent.ip` | Evidence and operational debugging | Often absent in lab setups. |
| `endpoint_id` | Derived from `agent_name` | Detection grouping and merge keys | Generated alias for host identity. |
| `event_source` | Derived from `event_id` / `channel` | High-level source labeling | Not in raw logs. |
| `technique_candidate` | Derived from event ID mapping | Heuristic hint, mostly for debugging | Not authoritative detection. Can be multi-valued like `T1059.001/T1036/T1219/T1543.003`. |
| `source_type` | Derived from raw source inspection | Backend filters, stats, evidence | Not in raw logs. |
| `channel` | Windows system `channel` | Detection, evidence, source labeling | Missing on malformed records. |
| `event_id` | Windows system `eventID` | Sigma matching, UI filters, graph logic | Missing on malformed records. |
| `provider_name` | Windows system `providerName` | Evidence, debugging | Often blank depending on source event. |
| `computer` | Windows system `computer` / `computerName` | Evidence and host context | Optional. |
| `subject_user` | Windows eventdata `SubjectUserName` / `subjectUserName` | Credential and logon events | Only present on relevant event types. |
| `target_user` | Windows eventdata `TargetUserName` / `targetUserName` | Credential and account events | Only present on relevant event types. |
| `logon_type` | Windows eventdata `LogonType` / `logonType` | Security event interpretation | Only on logon-related events. |
| `service_name` | Windows eventdata `ServiceName` / `serviceName` | Service creation detection | Usually empty except 7045 / 4697. |
| `image_path` | Windows eventdata `Image`, `ImagePath`, `NewProcessName` | Process detection, graph building, evidence | Missing on non-process events. |
| `command_line` | Windows eventdata `CommandLine` / `ProcessCommandLine` | Sigma rules, evidence, process tree | Missing on non-process events. |
| `parent_image` | Windows eventdata `ParentImage` | Process ancestry and UI display | Missing on non-process events. |
| `parent_command_line` | Windows eventdata `ParentCommandLine` | Evidence and forensic context | Often absent in Windows logs. |
| `process_guid` | Windows eventdata `ProcessGuid`; for AMSI events, recovered from payload `process_guid` | Core join key for process tree, correlation, merge logic | Can be missing on AMSI-only records unless reconstructed from payload. |
| `parent_process_guid` | Windows eventdata `ParentProcessGuid` | Process tree and ancestry | Missing on some event types. |
| `source_image` | Windows eventdata `SourceImage` | Access and remote-thread events | Only present on specific event types. |
| `target_image` | Windows eventdata `TargetImage` | Access and process events | Only present on specific event types. |
| `granted_access` | Windows eventdata `GrantedAccess` | Process access analysis | Usually process-access only. |
| `destination_ip` | Windows eventdata `DestinationIp` / `destinationIp` | Network graph, threat intel queue | Only present on network events such as Sysmon EID 3. |
| `destination_port` | Windows eventdata `DestinationPort` / `destinationPort` | Network graph, threat intel queue | Only present on network events. |
| `target_filename` | Windows eventdata `TargetFilename` / `targetFilename` | File edges, evidence drawer | Only present on file events such as EID 11 / 23. |
| `hashes` | Windows eventdata `Hashes` / `hashes` | Threat intel queue, evidence | Often absent on events that do not include file hashes. |
| `target_object` | Windows eventdata `TargetObject` / `targetObject` | Registry edge labeling and rules | Only present on registry events. |
| `details` | Windows eventdata `Details` / `details` | Registry and event-specific evidence | Event-specific. |
| `ticket_options` | Windows eventdata `ticketOptions` | Kerberos/security analysis | Rare; only on Kerberos-related records. |
| `ticket_enc_type` | Windows eventdata `ticketEncryptionType` | Kerberos/security analysis | Rare; only on Kerberos-related records. |
| `access_mask` | Windows eventdata `AccessMask` / `accessMask` | Access analysis | Usually process-access or object-access events. |
| `properties` | Windows eventdata `properties` / `Properties` | Generic event context | Event-specific. |
| `original_file_name` | Windows eventdata `OriginalFileName` | Masquerading and binary provenance checks | Missing unless Sysmon captured the PE metadata. |
| `service_binary_path` | Windows eventdata `ImagePath` or `ServiceFileName` | Service creation detection and evidence | Usually 7045 / 4697 only. |
| `service_start_delta_seconds` | Derived placeholder in ingestor | Currently not used in active logic | Always `0` today. This is a candidate cleanup field. |
| `command_line_flags` | Derived placeholder in ingestor | Currently not used in active logic | Always empty today. Candidate cleanup field. |
| `registry_path` | Normalized `TargetObject` | Registry-based detections and UI display | Derived. Lowercased and unescaped in ingestor. |
| `process_hash` | Windows eventdata `Hashes` | Historical compatibility field | Duplicates `hashes`. Consider removing one of them. |
| `process_path` | Windows eventdata `Image` | Sigma mapping, process UI, evidence | Duplicates `image_path` in practice. Consider unifying with `image_path`. |
| `source_ip` | Windows eventdata `SourceIp` / `sourceIp` | Network attribution | Often absent except on some network/process events. |
| `username` | Windows eventdata `User`, `SubjectUserName`, `TargetUserName` | UI labels, evidence, process nodes | Derived fallback chain. May be blank or ambiguous. |
| `amsi_scan_result` | AMSI payload `scan_result` | AMSI filtering, evidence, statistics | Missing on all non-AMSI events. `32768` indicates detected. |
| `amsi_content_name` | AMSI payload `content_name` | Evidence and debugging | Missing on non-AMSI events. |
| `amsi_content_hex` | AMSI payload `content_hex` | AMSI detection engine, evidence | Missing on non-AMSI events. This is the main script buffer. |
| `raw_json_original` | `json.dumps(raw)` before AMSI/GUID mutation in `ingestor.py` | Forensic replay, raw evidence, auditing | Immutable source snapshot for the current ingest pass. Older rows may contain backfilled values if they were ingested before this split existed. |
| `raw_json_normalized` | `json.dumps(raw)` after AMSI/GUID mutation in `ingestor.py` | Evidence, debugging, joins, fallback parsing | This is the ingest-ready copy used by the pipeline. |
| `raw_json` | Backward-compatible alias for `raw_json_normalized` | Legacy code paths, joins, fallback parsing | Kept for compatibility. New code should prefer `raw_json_normalized` for parsing and `raw_json_original` for forensic comparison. |
| `ingested_at` | SQLite default timestamp | Debugging and freshness checks | Generated. |

## Table: raw_detections

This is the staging table between detection and alert merging.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `id` | SQLite autoincrement | Staging identity | Generated. |
| `process_guid` | Event `process_guid`, or AMSI-recovered GUID | Merge grouping and alert upgrades | May be blank for some service events before fallback handling. |
| `endpoint_id` | Event `endpoint_id` or `agent_name` | Merge grouping | Generated alias for host identity. |
| `ts` | `wazuh_ts_epoch` or current time | Merge window selection | Generated. |
| `layer` | Detection path: `amsi`, `cmdline`, `service`, `registry` | Merge logic and debugging | Internal classifier. |
| `technique` | Detector output, normalized MITRE ID or rule ID fallback | Merge logic and final alert creation | Internal detection key, not raw log content. |
| `matched_pattern` | AMSI pattern text or Sigma rule title | Evidence and debugging | Detector-generated. |
| `obfuscation_score` | T1027 overlay from AMSI content | Alert confidence and UI badges | Only meaningful for AMSI-sourced detections. |
| `event_id_fk` | `events.id` | Merge joins, alert linkage | Foreign key to normalized event. |
| `merged` | Internal flag | Prevents duplicate promotions to `alerts` | Internal only. |
| `created_at` | SQLite default timestamp | Debugging and staging audit | Generated. |

Practical note: `raw_detections` is not a raw log store. It is a short-lived merge buffer.

## Table: alerts

This is the user-facing detection table. Most UI and API features read from here.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `id` | SQLite autoincrement | Alert identity in UI and API | Generated. |
| `fired_at` | SQLite default timestamp or merge time | Timeline, sorting, incident chains | Generated. |
| `rule_id` | Sigma UUID or internal technique mapping | Rules UI, alert detail, evidence, toggle validation | Not raw log data. This is the canonical rule identifier. |
| `rule_name` | Sigma title or internal detector meta | UI labels and summaries | Not raw log data. |
| `mitre_technique` | Sigma tags or detector technique | Filtering and MITRE display | Normalized MITRE ID; may come from Sigma or detector meta. |
| `severity` | Derived from merge confidence | Row color, stats, filtering | Textual severity only. Backend derives numeric score on the fly. |
| `event_id_fk` | `events.id` | Joins back to source event | Source-event foreign key. |
| `wazuh_event_id` | `events.wazuh_id` | Evidence and raw event lookup | Synthetic dedup key, not upstream Wazuh ID. |
| `source_process_guid` | Source event `process_guid` | Process tree, evidence, incident chains | May be null on incomplete records. |
| `source_agent_name` | Source event `agent_name` | Host grouping, evidence, correlation | This is effectively the host key in the app. |
| `source_type` | Event `source_type` | API filters and evidence | Derived in ingestor. |
| `source_channel` | Event `channel` | Evidence and UI layer labeling | Derived from event source. |
| `source_event_id` | Event `event_id` | Rule debugging and timeline | Derived from Windows system event. |
| `source_wazuh_ts_epoch` | Event `wazuh_ts_epoch` | Alert-to-event timing and correlation | Derived from Wazuh timestamp. |
| `summary` | Built by detector from rule name plus flags | Alert list, evidence drawer, timeline | Not raw log data. |
| `matched_json` | Source event `raw_json_normalized` | Evidence drawer and raw replay | Contains normalized raw event JSON. Use `raw_json_original` when you need the untouched archive payload. |
| `confidence` | Merge logic | Severity derivation, alert UX | Values: `HIGH`, `MEDIUM`, `LOW`. |
| `amsi_matched_patterns` | Detector output | Evidence and root-cause analysis | Only populated for AMSI-driven detections. |
| `no_amsi_corroboration` | Merge logic | Bypass indicator, row badges, evidence | `1` means cmdline fired without AMSI corroboration in the merge window. |
| `obfuscation_score` | T1027 overlay | UI badges and analyst triage | Meaningful only for AMSI content. |

Important backend note:

- `severity` is stored as text.
- The backend computes `severity_score()` dynamically for `/alerts`, `/stats`, and `/timeline`.
- There is no persistent `severity_score` column in the DB schema.

## Table: alert_event_links

This table connects one alert to one or more source events.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `alert_id` | `alerts.id` | Evidence drawer and alert graph | Foreign key to the final alert. |
| `event_id` | `events.id` | Evidence drawer and joined evidence | Foreign key to normalized telemetry. |
| `link_reason` | Generated by ingestor linkage logic | Explains why the event is attached | Current reasons are `source` and `process-window`. |

Why this table exists:

- The same alert can be supported by multiple raw events.
- The same event can support more than one analytical relationship.
- The `link_reason` column preserves the relationship type instead of hiding it in code.

Current caveat:

- The table does not store a weight, confidence, or timestamp for each link.
- If you want audit-grade evidence, a future revision should add `linked_at`, `link_score`, and maybe `link_source`.

## Table: ingestion_state

This is a tiny key/value state table.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `key` | Internal state key | Ingestor tail position tracking | Today the main key is `archives_offset`. |
| `value` | Internal serialized value | Ingestor resume state | Stored as text. |

This table is not related to raw logs. It exists so the ingestor can resume from the last processed
byte offset instead of re-reading the full `archives.json`.

## Table: process_nodes

This table stores the process tree used by the evidence drawer and process graph.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `process_guid` | Sysmon EID 1 `ProcessGuid`, or derived fallback from AMSI payload | Primary tree key | May be missing in some raw logs. |
| `parent_process_guid` | Sysmon EID 1 `ParentProcessGuid` | Tree ancestry | Often missing on incomplete records. |
| `pid` | Sysmon EID 1 `ProcessId` | Display and troubleshooting | Event-specific. |
| `image` | Sysmon EID 1 `Image` | Tree labels and evidence | Defaults to `Unknown` when absent. |
| `command_line` | Sysmon EID 1 `CommandLine` | Analyst context and rules | Often missing on non-process events. |
| `user_name` | Sysmon EID 1 `User` | Host context and evidence | May be blank. |
| `host_id` | Derived from `agent_name` | Host scoping for graph queries | Derived, not raw. |
| `start_time` | Event `wazuh_ts` from process creation | Timeline and ancestry | Generated from normalized event time. |
| `end_time` | Set when Sysmon EID 5 arrives | Process lifetime tracking | Derived. Missing if termination is not observed. |

Why it matters:

- `load_process_chain()` and the evidence drawer use this table to reconstruct ancestry.
- It is the basis of the process graph in the UI.

Current caveat:

- Some legacy rows may not have full ancestry or termination data.
- `end_time` is only trustworthy when a corresponding EID 5 was ingested.

## Table: process_edges

This table stores non-process activity tied to a process.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `process_guid` | Sysmon event `ProcessGuid` | Graph and evidence | Primary process link. |
| `host_id` | Derived from `agent_name` | UI scoping and backend filters | Some legacy rows lack this column value. |
| `edge_type` | Derived from event ID | Graph styling and evidence | Current values: `network`, `file`, `registry`. |
| `target_label` | Derived target field | Graph display | Loses the original structured type unless the caller re-parses it. |
| `timestamp` | Event `wazuh_ts` | Chronology in evidence | Generated from normalized event time. |

Event-to-edge mapping:

- EID 3 -> network edge, `target_label = destination_ip:destination_port`
- EID 11 / 23 -> file edge, `target_label = target_filename`
- EID 12 / 13 / 14 -> registry edge, `target_label = target_object`

Current caveat:

- `target_label` is a compact display field, not a typed schema.
- If you need forensic-quality structure later, split it into explicit columns like `target_ip`, `target_port`, `target_path`, and `target_registry_key`.

## Table: threat_intel_cache

This is the local cache for enrichment results.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `indicator` | Alert-derived hash or IP | Cache key | Comes from alert-linked events, not raw logs directly. |
| `indicator_type` | Derived as `sha256` or `ip` | Worker routing and API display | Limited to the supported types in the worker. |
| `provider` | Worker config | Display and debugging | Currently defaults to `virustotal`. |
| `verdict` | Worker response classification | UI labels and triage | Derived from VT response. |
| `score` | Worker classification score | UI and analyst triage | Derived, not raw. |
| `raw_json` | Full VT API response | Audit and troubleshooting | Large payload, external-source data. |
| `checked_at` | Worker timestamp | Freshness checks | Generated. |
| `stale_after` | Worker timestamp + TTL | Cache expiry | Generated. |

Why it matters:

- The worker only enriches indicators that were queued from alerts.
- The cache prevents repeated external lookups for the same indicator.

## Table: threat_intel_queue

This is the work queue for enrichment jobs.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `id` | SQLite autoincrement | Queue identity | Generated. |
| `alert_id` | `alerts.id` | Traceback to the source alert | Null only if the queue row was created manually, which is not the normal path. |
| `indicator` | Derived from linked event hashes or IPs | Worker lookup | Not a raw log field. |
| `indicator_type` | Derived as `sha256` or `ip` | Worker API path choice | Worker currently supports only those two types. |
| `status` | Worker state machine | Monitoring and retries | Values: `queued`, `running`, `done`, `error`. |
| `attempts` | Worker retry counter | Retry throttling | Internal. |
| `next_run_at` | Worker scheduling timestamp | Worker polling | Internal. |
| `last_error` | Worker exception text | Troubleshooting | Internal. |
| `created_at` | Queue creation timestamp | Audit and ordering | Generated. |
| `updated_at` | Queue update timestamp | Audit and ordering | Generated. |

## Table: rules

This mirrors the Sigma rule set that the UI exposes and the detector compiles.

| Field | Source | Used by | Missing / caveat |
|---|---|---|---|
| `id` | Sigma YAML `id` | Rules API, toggling, evidence | Canonical rule UUID. |
| `name` | Sigma YAML `title` | Rules UI and alert summaries | Human-readable rule name. |
| `description` | Sigma YAML `description` | Rules UI | Optional in YAML. |
| `mitre_technique` | Sigma YAML tags such as `attack.t1059.001` | MITRE display and filtering | Only the first matching attack tag is stored today. |
| `severity` | Sigma YAML `level` | Rules UI and sorting | Textual level from the YAML file, not the alert severity. |
| `yaml_content` | Full Sigma YAML file text | Rules page, debugging, future upload/import workflows | Raw rule text stored for traceability. |
| `enabled` | `disabled_rules.json` at migration time or toggle API updates | Rules UI and detector filtering | This is a runtime state mirror, not the original source of truth. |

Current caveat:

- The detector and backend both consult `disabled_rules.json` at runtime.
- The `rules.enabled` column is useful for the UI, but it can drift if files are edited manually.

## Backend-only Derived Fields

These fields are returned by the API but are not stored as DB columns.

| Field | Returned by | Source |
|---|---|---|
| `severity_score` | `/alerts`, `/stats`, `/timeline` | Computed from `alerts.severity` in `server/backend/main.py`. |
| `source_layer` | `/alerts` and `/alerts/{id}` | Computed from `source_channel`. |
| `raw_event_ref` | `/alerts` and `/alerts/{id}` | Computed from `source_process_guid` or raw event parsing. |
| `created_at` | `/alerts` and `/alerts/{id}` | Computed from `alerts.fired_at`. |
| `process_chain` | `/alerts` and `/alerts/{id}` | Built from `process_nodes` and `process_edges`. |

## Missing-Data Behavior

These are the main cases where data may be missing or intentionally blank:

- AMSI fields are only present for `ISHAX-AMSI` records.
- `destination_ip` / `destination_port` are only present for network events.
- `target_filename` is only present for file events.
- `target_object` / `registry_path` are only present for registry events.
- `service_name` / `service_binary_path` are only present for service-install events.
- `process_guid` may be missing on AMSI payloads unless the watcher payload carries it and the ingestor normalizes it.
- `end_time` is only present after a matching termination event.
- Some older `process_edges` rows may lack `host_id`.
- `service_start_delta_seconds` and `command_line_flags` are placeholder fields today.

## Improvement And Fix Suggestions

These are the strongest schema/pipeline improvements I would make next:

1. Split `technique_candidate` into a proper relation or JSON array.
   - Right now it is a slash-delimited string, which is fine for debugging but weak for queries.

2. Remove the duplicate process fields or give them explicit canonical names.
   - `hashes` and `process_hash` currently carry the same value.
   - `image_path` and `process_path` are also effectively duplicates.

3. Replace placeholder fields with real values or delete them.
   - `service_start_delta_seconds` is always `0`.
   - `command_line_flags` is always empty.
   - If they are not going to be populated, they should not stay as permanent columns.

4. Preserve raw and normalized JSON separately.
   - Implemented: `raw_json_original` preserves the original archive payload and `raw_json_normalized` preserves the ingest-ready version.
   - `raw_json` remains as a compatibility alias for the normalized copy.

5. Normalize the alert-to-event link table more fully.
   - Add `linked_at`, `link_score`, and maybe `link_source`.
   - That would make evidence auditing more deterministic.

6. Make `rules.enabled` and `disabled_rules.json` one source of truth.
   - Today they are synchronized, but they are still two places that describe the same state.
   - If a manual edit slips in, they can diverge.

7. Split `process_edges.target_label` into typed fields.
   - A network edge should not have the same storage model as a registry edge.
   - This would make the evidence drawer and graph filters much cleaner.

8. Add a schema version table.
   - That would make migrations explicit and easier to test.

9. Add `CHECK` constraints or stricter validation where the domain is known.
   - Example: `source_type`, `edge_type`, and `layer` already have implicit domain rules.
   - Encoding those more tightly would catch bad data earlier.

10. Add a small DB view layer for common backend reads.
   - The backend currently repeats a few joins and projections.
   - Views would reduce duplication and make future schema changes safer.

## Operational Notes

- `edr.db`, `-wal`, and `-shm` are runtime artifacts. Treat them as mutable state, not source.
- Rebuild the `rules` table after Sigma YAML changes if you edit rules outside the normal workflow.
- If the backend or detector sees stale or invalid `disabled_rules.json`, it now warns instead of failing silently.
- The API reads the DB dynamically from the project layout, so the project can move between systems without hardcoded paths.
