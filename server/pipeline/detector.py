#!/usr/bin/env python3
"""
ISHAX v2 — Detection Engine
============================
Locked scope: exactly 8 techniques.

  Layer A — AMSI content matching (Python, this file):
      T1059.001  PowerShell
      T1059.005  VBA / Office macros
      T1059.007  JavaScript / VBScript

  Layer B — Sigma rule matching (pySigma → SQLite):
      T1036      process masquerading: PE metadata/path mismatch
      T1219      remote management tool abuse: known RMM process/path indicators
      T1059.001  cmdline: -EncodedCommand, hidden+nop, download-cradle
      T1543.003  service creation: EID 7045 / 4697 (primary) + sc.exe cmdline (secondary)
      T1547.001  Run key write: Sysmon EID 13 TargetObject on Run/RunOnce paths

  Overlay — T1027 obfuscation score:
      score_obfuscation(content) → float [0.0, 1.0]
      Attached to AMSI detection records as obfuscation_score field.
      Never emits a separate alert — badge only (§5).

  Dual-layer merge (§3):
      Both layers write to raw_detections staging table.
      Merge runs per-event: group by (technique, process_guid, endpoint_id) ± 30s.
        both layers   → confidence=HIGH, amsi+cmdline evidence attached
        AMSI only     → confidence=HIGH (AMSI content match is strong signal)
        cmdline only  → confidence=MEDIUM, no_amsi_corroboration=1
      Never emits two alerts for the same process_guid+technique within a 30s window.
      Upgrade path: if AMSI arrives after cmdline already emitted MEDIUM,
                    the existing alert is upgraded to HIGH in-place.

AMSI watcher method (confirmed from AMSI_ETW_IMPL.md):
  ETW real-time consumer via StartTraceW + EnableTraceEx2 on provider
  {2A576B87-09A7-520E-C21A-4942F0271D67} (Microsoft-Antimalware-Scan-Interface).
  Events written to ISHAX-AMSI Windows Event Log channel → Wazuh → archives.json.

AMSI bypass caveat (§2, documented not hidden):
  AMSI can be bypassed by patching amsi.dll AmsiScanBuffer in-process (reflection-
  based amsiInitFailed field tampering, memory patching). If only cmdline fires with
  no_amsi_corroboration=1, AMSI bypass may be the reason — both possibilities are
  worth investigating. No claim of near-100% coverage is made.

Production caveat (§2):
  ETW session (ISHAX-AMSI-ETW) must remain running continuously. If it stops,
  AMSI events silently stop flowing. The Microsoft-Windows-AMSI/Operational log
  is empty by default — nothing subscribes to it out of the box. Run ISHAXAmsi
  service health checks regularly.
"""
import json
import math
import os
import re
import sqlite3
import time
from pathlib import Path

from sigma.collection import SigmaCollection
from sigma.backends.sqlite.sqlite import sqliteBackend
from sigma.processing.pipeline import ProcessingPipeline, ProcessingItem
from sigma.processing.transformations import FieldMappingTransformation


# ==========================================================================
# Utility helpers
# ==========================================================================

def ci_get(obj: dict, *keys: str, default=None):
    """Case-insensitive dict get, tries each key in order."""
    if not isinstance(obj, dict):
        return default
    lowered = {str(k).lower(): v for k, v in obj.items()}
    for key in keys:
        v = lowered.get(str(key).lower())
        if v is not None:
            return v
    return default


def raw_eventdata(ev: dict) -> dict:
    try:
        raw_json = ev.get("raw_json_normalized") or ev.get("raw_json") or ev.get("raw_json_original") or "{}"
        return (json.loads(raw_json)
                .get("data", {}).get("win", {}).get("eventdata", {})) or {}
    except Exception:
        return {}


def source_process_guid(ev: dict) -> str | None:
    guid = ev.get("process_guid") or ci_get(
        raw_eventdata(ev), "ProcessGuid", "processGuid",
        "SourceProcessGUID", "sourceProcessGuid"
    )
    if guid:
        g = str(guid).strip().lower()
        if not g.startswith('{'): g = '{' + g
        if not g.endswith('}'): g = g + '}'
        return g
    
    # AMSI events carry process_guid inside the JSON payload
    system = ev.get("system") or ev.get("win", {}).get("system", {})
    if (system.get("channel", "") or "").lower() == "ishax-amsi":
        payload = ci_get(raw_eventdata(ev), "param1", "data", default="")
        try:
            amsi = json.loads(payload) if payload else {}
        except Exception:
            amsi = {}
        guid = ci_get(amsi, "process_guid", "processGuid")
        if guid:
            g = str(guid).strip().lower()
            if not g.startswith('{'): g = '{' + g
            if not g.endswith('}'): g = g + '}'
            return g
    return None


# ==========================================================================
# T1027 — Obfuscation overlay  (§5)
# ==========================================================================
# Rationale: MITRE ATT&CK T1027 indicators:
#   high entropy = encoded/compressed payload
#   encoding markers = Base64, char-array concat, IEX patterns
#   non-printable chars = binary shellcode embedded in script
# Components weighted: entropy 40%, markers 35%, non-printable 25%

_ENCODING_MARKERS_RE = re.compile(
    r"FromBase64String"
    r"|-enc\b|-EncodedCommand|-EncodedC\b"
    r"|\[Convert\]::"
    r"|char\(\d+\)"
    r"|\[char\]\s*\d+"
    r"|iex\s*\("
    r"|invoke-expression"
    r"|\.replace\(['\"].,.*\.\)"
    r"|split.*join|join.*split",
    re.IGNORECASE,
)


def score_obfuscation(content: str) -> float:
    """
    Returns T1027 obfuscation likelihood in [0.0, 1.0].
    Attach this score to detections — do NOT emit a separate alert (§5).
    Score >= 0.5 is flagged as high obfuscation in the dashboard.
    """
    if not content or len(content) < 10:
        return 0.0

    # Shannon entropy (max theoretical = log2(charset_size))
    freq: dict[str, int] = {}
    for ch in content:
        freq[ch] = freq.get(ch, 0) + 1
    n = len(content)
    entropy = -sum((f / n) * math.log2(f / n) for f in freq.values())
    entropy_score = min(entropy / 8.0, 1.0)

    # Encoding markers count
    marker_hits = len(_ENCODING_MARKERS_RE.findall(content))
    marker_score = min(marker_hits / 4.0, 1.0)

    # Non-printable / high-byte character ratio
    non_printable = sum(1 for c in content if ord(c) < 32 or ord(c) > 126)
    ratio_score = min((non_printable / n) * 10.0, 1.0)

    total = (entropy_score * 0.40) + (marker_score * 0.35) + (ratio_score * 0.25)
    return round(min(total, 1.0), 4)


# ==========================================================================
# AMSI content decode
# ==========================================================================

def decode_amsi_hex(hex_str: str) -> str:
    """
    Decode content_hex (hex-encoded UTF-16LE buffer from AMSI ETW event)
    to a readable Python string.
    The AMSI watcher stores content as hex per AMSI_ETW_IMPL.md §PHASE 5.
    """
    if not hex_str:
        return ""
    try:
        return bytes.fromhex(hex_str).decode("utf-16-le", errors="replace")
    except Exception:
        return ""


# ==========================================================================
# AMSI Layer A — detection patterns  (§3 Layer A, §4)
# ==========================================================================

# T1059.001 — PowerShell malicious content patterns
# Adapted from SigmaHQ:
#   rules/windows/powershell/powershell_script/posh_ps_malicious_commandlets.yml
#   rules/windows/powershell/powershell_script/posh_ps_download_cradle.yml
# (No direct SigmaHQ AMSI-content rule — this is custom for AMSI buffer matching.)
_PS_PATTERNS: list[str] = [
    "Invoke-Mimikatz", "Invoke-Mimikittenz", "Invoke-NanoDump",
    "Invoke-SafetyKatz", "Invoke-BetterSafetyKatz", "Invoke-DinvokeKatz",
    "sekurlsa", "logonpasswords", "lsadump", "dcsync",
    "Invoke-Shellcode", "Invoke-ReflectivePEInjection", "Invoke-PSInject",
    "Invoke-DllInjection", "VirtualAlloc", "CreateThread",
    "Get-GPPPassword", "Get-PassHashes", "Get-LSASecret",
    "Get-RemoteCachedCredential", "Get-VaultCredential",
    "Invoke-PowerDump", "Invoke-PowerDPAPI", "Invoke-DCSync",
    "Add-Persistence", "Get-Keystrokes", "Get-TimedScreenshot",
    "Net.WebClient", "DownloadString", "DownloadFile",
    "Invoke-WebRequest", "Start-BitsTransfer",
    "IEX(", "IEX (", "Invoke-Expression",
    "amsiInitFailed", "AmsiScanBuffer", "amsiContext",
    "amsi.dll", "AmsiScanString",
]

# T1059.005 — VBA / Office macro malicious patterns
# Custom — no equivalent SigmaHQ AMSI-content rule for VBA buffer.
# Source: https://learn.microsoft.com/en-us/microsoft-365/security/defender-endpoint/office-macro-amsi
_VBA_PATTERNS: list[str] = [
    "CreateObject", "Shell", "WScript.Shell", "PowerShell",
    "cmd.exe", "certutil", "bitsadmin", "mshta",
    "AutoOpen", "Document_Open", "Workbook_Open", "Auto_Open",
    "Environ(", "Chr(", "ChrW(", "CallByName",
    "VirtualAlloc", "RtlMoveMemory", "CreateThread",
    "URLDownloadToFile", "XMLHTTP", "WinHttpRequest",
    "Shell32", "Execute", "MacroSecurity",
]

# T1059.007 — JavaScript / VBScript malicious patterns
# Custom — no equivalent SigmaHQ AMSI-content rule for JS/VBS buffer.
# Source: https://learn.microsoft.com/en-us/windows/win32/amsi/how-amsi-helps
_JS_VBS_PATTERNS: list[str] = [
    "WScript.Shell", "Shell.Application", "ActiveXObject",
    "CreateObject", "GetObject",
    "eval(", "unescape(", "String.fromCharCode", "escape(",
    "VBScript.Encode", "JScript.Encode",
    "URLDownloadToFile", "XMLHTTP", "WinHttp",
    "PowerShell", "cmd.exe", "certutil",
    "RegExp(", "new Function(",
]


# Office process image names (for T1059.005 caller identification)
_OFFICE_IMAGES: frozenset[str] = frozenset({
    "winword.exe", "excel.exe", "powerpnt.exe",
    "outlook.exe", "onenote.exe", "access.exe",
    "msaccess.exe", "mspub.exe",
})

# Office document extensions in content_name (for T1059.005)
_OFFICE_EXTS: tuple[str, ...] = (
    ".docm", ".xlsm", ".xlam", ".dotm", ".pptm",
    ".xls", ".doc", ".xlsb", "VBA", "vba",
)

# WSH process image names (for T1059.007 caller identification)
_WSH_IMAGES: frozenset[str] = frozenset({
    "wscript.exe", "cscript.exe", "mshta.exe",
})

# Script file extensions in content_name (for T1059.007)
_SCRIPT_EXTS: tuple[str, ...] = (
    ".js", ".vbs", ".jse", ".vbe", ".wsf", ".wsh", ".hta",
)



def _get_process_image(con: sqlite3.Connection, process_guid: str) -> str:
    """Look up process image path from process_nodes. Returns '' if unknown."""
    if not process_guid:
        return ""
    try:
        row = con.execute(
            "SELECT image FROM process_nodes WHERE process_guid = ? LIMIT 1",
            (process_guid,),
        ).fetchone()
        return (row[0] or "").lower() if row else ""
    except Exception:
        return ""


def check_amsi_layer(
    con: sqlite3.Connection, ev: dict, rowid: int
) -> list[dict]:
    """
    AMSI Layer A detection for T1059.001, T1059.005, T1059.007.
    Called only for events where channel = 'ishax-amsi'.

    Returns list of raw_detection dicts to insert into raw_detections.
    T1027 obfuscation score is computed here and attached to each hit.
    """
    hits: list[dict] = []

    content_hex   = ev.get("amsi_content_hex") or ""
    content_name  = (ev.get("amsi_content_name") or "").lower()
    content       = decode_amsi_hex(content_hex)

    if not content and not content_name:
        return hits

    process_guid = ev.get("process_guid") or source_process_guid(ev) or ""
    endpoint_id  = ev.get("endpoint_id") or ev.get("agent_name") or ""
    ts           = ev.get("wazuh_ts_epoch") or int(time.time())

    # T1027 overlay — computed once, attached to all hits from this event
    obf_score = score_obfuscation(content) if content else 0.0

    # Caller identification from process_nodes (joined via process_guid)
    process_image = _get_process_image(con, process_guid) if process_guid else ""

    def _build(technique: str, matched: list[str]) -> dict:
        return {
            "process_guid":    process_guid,
            "endpoint_id":     endpoint_id,
            "ts":              ts,
            "layer":           "amsi",
            "technique":       technique,
            "matched_pattern": ", ".join(matched[:8]),  # cap length
            "event_id_fk":     rowid,
            "obfuscation_score": obf_score,
        }

    # --- T1059.001 PowerShell ---
    # Filter: content_name starts with 'powershell_' OR process image = powershell.exe
    # ContentName for PowerShell: "PowerShell_<path>_<version>" per AMSI_ETW_IMPL.md sample
    is_ps = "powershell" in content_name or "powershell" in process_image
    if is_ps and content:
        matched = [p for p in _PS_PATTERNS if p.lower() in content.lower()]
        if matched:
            hits.append(_build("T1059.001", matched))

    # --- T1059.005 VBA / Office ---
    # Filter: calling process is an Office app OR content_name has Office extension
    # Documented appname values: "VBA", "Office 16.0", "VBE7" (varies by Office version)
    # We use process image as primary discriminator since appname is not captured by our watcher.
    is_office = any(img in process_image for img in _OFFICE_IMAGES)
    has_office_ext = any(ext in content_name for ext in _OFFICE_EXTS)
    if (is_office or has_office_ext) and content:
        matched = [p for p in _VBA_PATTERNS if p.lower() in content.lower()]
        if matched:
            hits.append(_build("T1059.005", matched))

    # --- T1059.007 JS / VBScript ---
    # Filter: calling process is wscript/cscript/mshta OR content_name has script extension
    # Documented appname values: "Windows Script Host", "JScript", "VBScript"
    # (exact string varies by Windows version — confirmed unverified, using process image)
    is_wsh = any(img in process_image for img in _WSH_IMAGES)
    has_script_ext = any(ext in content_name for ext in _SCRIPT_EXTS)
    if (is_wsh or has_script_ext) and content:
        matched = [p for p in _JS_VBS_PATTERNS if p.lower() in content.lower()]
        if matched:
            hits.append(_build("T1059.007", matched))

    return hits


# ==========================================================================
# T1543.003 — Service confidence enrichment  (§6)
# ==========================================================================
# Per §6: path is EVIDENCE for confidence, NOT a gate. Emit always.
# HIGH  → binary in staging dir OR service start near creation (suspicious timing)
# MEDIUM → system-path binary, unusual name/context (still emitted, still actionable)

_STAGING_MARKERS: tuple[str, ...] = (
    "\\temp\\", "\\appdata\\", "\\downloads\\", "\\users\\public\\",
    "\\tmp\\", "\\programdata\\",
)
_RANDOM_SVC_RE = re.compile(r"^[a-z0-9]{6,12}$")  # short random-looking service names


def enrich_service_confidence(ev: dict) -> str:
    """HIGH if staging path or suspicious service name, MEDIUM otherwise."""
    path = (
        ev.get("image_path") or ev.get("service_binary_path") or
        ev.get("command_line") or ""
    ).lower()

    if any(m in path for m in _STAGING_MARKERS):
        return "HIGH"

    svc_name = (ev.get("service_name") or "").lower().strip()
    if svc_name and (len(svc_name) <= 3 or bool(_RANDOM_SVC_RE.match(svc_name))):
        return "HIGH"

    return "MEDIUM"


# ==========================================================================
# Sigma rule loader  (Layer B)
# ==========================================================================

SIGMA_RULES: list[dict] = []

# Sigma standard field names → our events table column names
_FIELD_MAP: dict[str, str] = {
    "Image":            "process_path",
    "CommandLine":      "command_line",
    "OriginalFileName": "original_file_name",
    "TargetObject":     "registry_path",
    "ParentImage":      "parent_image",
    "GrantedAccess":    "granted_access",
    "SourceImage":      "source_image",
    "TargetImage":      "target_image",
    "TargetFilename":   "target_filename",
    "Hashes":           "hashes",
    "DestinationIp":    "destination_ip",
    "DestinationPort":  "destination_port",
    "User":             "username",
    # Service install events (EID 7045 / 4697)
    "ServiceName":      "service_name",
    "ImagePath":        "image_path",
    # Event envelope fields (for rules that filter by event_id)
    "EventID":          "event_id",
    "Channel":          "channel",
    # AMSI specific fields
    "AmsiContentName":  "amsi_content_name",
    "AmsiScanResult":   "amsi_scan_result",
    "AmsiContentHex":   "amsi_content_hex",
}


def load_sigma_rules():
    global SIGMA_RULES
    if SIGMA_RULES:
        return

    rules_dir = Path(__file__).parent / "sigma_rules"
    if not rules_dir.exists():
        print(f"[WARN] sigma_rules/ not found at {rules_dir}", flush=True)
        return

    pipeline = ProcessingPipeline()
    pipeline.items.append(ProcessingItem(
        transformation=FieldMappingTransformation(_FIELD_MAP)
    ))

    backend = sqliteBackend(processing_pipeline=pipeline)
    col = SigmaCollection.load_ruleset([str(rules_dir)])

    for rule in col.rules:
        try:
            for query in backend.convert_rule(rule):
                sql = query.replace(
                    "SELECT * FROM <TABLE_NAME> WHERE ",
                    "SELECT id FROM events WHERE "
                )
                SIGMA_RULES.append({"rule": rule, "sql": sql})
        except Exception as exc:
            print(f"[WARN] Sigma rule compile failed ({rule.id}): {exc}", flush=True)

    print(f"[INFO] Loaded {len(SIGMA_RULES)} Sigma rules via pySigma.", flush=True)


# ==========================================================================
# Disabled-rules cache
# ==========================================================================

_disabled_cache: set = set()
_last_mtime: float = 0.0


def load_disabled_rules():
    global _disabled_cache, _last_mtime
    path = os.path.join(os.path.dirname(__file__), "disabled_rules.json")
    try:
        mtime = os.path.getmtime(path)
        if mtime != _last_mtime:
            with open(path) as f:
                _disabled_cache = set(json.load(f))
            _last_mtime = mtime
    except FileNotFoundError:
        _disabled_cache = set()
    except json.JSONDecodeError as exc:
        print(f"[WARN] invalid disabled_rules.json ignored: {exc}", flush=True)
        _disabled_cache = set()
    except Exception as exc:
        print(f"[WARN] unable to load disabled_rules.json from {path}: {exc}", flush=True)
        _disabled_cache = set()

# ==========================================================================
# raw_detections staging table operations
# ==========================================================================

def _insert_raw_detection(con: sqlite3.Connection, det: dict) -> int | None:
    """
    Insert into raw_detections. The UNIQUE(event_id_fk, layer, technique)
    constraint prevents double-inserts on ingestor retry.
    Returns the new rowid, or None if this (event, layer, technique) already exists.
    """
    try:
        cur = con.execute(
            """INSERT OR IGNORE INTO raw_detections
               (process_guid, endpoint_id, ts, layer, technique,
                matched_pattern, obfuscation_score, event_id_fk)
               VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
            (
                det.get("process_guid"), det.get("endpoint_id"),
                det.get("ts"),           det.get("layer"),
                det.get("technique"),    det.get("matched_pattern"),
                det.get("obfuscation_score", 0.0), det.get("event_id_fk"),
            ),
        )
        con.commit()
        return cur.lastrowid if cur.rowcount else None
    except Exception as exc:
        print(f"[WARN] raw_detections insert: {exc}", flush=True)
        return None


# ==========================================================================
# Merge logic  (§3)
# ==========================================================================

_MERGE_WINDOW: int = 30          # seconds — tight per §3 to avoid flood
_AMSI_TECHNIQUES: frozenset[str] = frozenset({"T1059.001", "T1059.005", "T1059.007"})

# In-process alert upgrade tracker: (technique, process_guid) → (alert_id, ts, confidence)
# Allows upgrading a MEDIUM cmdline-only alert to HIGH when AMSI corroboration arrives.
# Lost on restart; 30s window is short enough that cross-restart upgrades are negligible.
_active_detections: dict[tuple, dict] = {}
_ACTIVE_TTL: int = 120  # purge entries older than 2 minutes to prevent unbounded growth


def _purge_active_detections():
    now = int(time.time())
    stale = [k for k, v in _active_detections.items() if now - v["ts"] > _ACTIVE_TTL]
    for k in stale:
        del _active_detections[k]


# Rule name / ID lookup for alerts built from raw_detections
_TECHNIQUE_META: dict[str, dict] = {
    "T1059.001": {
        "rule_id":   "c13454b6-ce2c-4903-875c-ce3d17db2388",
        "rule_name": "Suspicious PowerShell Execution (AMSI+Cmdline Dual-Layer)",
    },
    "T1059.005": {
        "rule_id":   "a1b2c3d4-e5f6-7890-abcd-ef1234567805",
        "rule_name": "Suspicious VBA Macro Execution (AMSI)",
    },
    "T1059.007": {
        "rule_id":   "b2c3d4e5-f6a7-8901-bcde-f12345678907",
        "rule_name": "Suspicious JS/VBScript Execution (AMSI)",
    },
    "T1543.003": {
        "rule_id":   "f7675646-cd24-4903-875c-ce3d17db2907",
        "rule_name": "New Suspicious Service Installation",
    },
    "T1547.001": {
        "rule_id":   "ab575646-cd24-4903-875c-ce3d17db2402",
        "rule_name": "Registry Run Key / Startup Folder Persistence",
    },
}


def _build_alert(
    technique:  str,
    pguid:      str | None,
    endpoint:   str | None,
    patterns:   str,
    confidence: str,
    no_amsi:    int,
    obf_score:  float,
    event_id_fk: int | None,
    ev:         dict,
) -> dict:
    meta = _TECHNIQUE_META.get(technique, {
        "rule_id": technique, "rule_name": technique
    })
    severity = "high" if confidence == "HIGH" else "medium"

    summary_parts = [meta["rule_name"]]
    if no_amsi:
        summary_parts.append("[no_amsi_corroboration — AMSI bypass possible or session down]")
    if obf_score >= 0.5:
        summary_parts.append(f"[T1027 obfuscated:{obf_score:.2f}]")

    return {
        "rule_id":               meta["rule_id"],
        "rule_name":             meta["rule_name"],
        "mitre_technique":       technique,
        "severity":              severity,
        "event_id_fk":           event_id_fk,
        "wazuh_event_id":        ev.get("wazuh_id"),
        "source_process_guid":   pguid or None,
        "source_agent_name":     endpoint or ev.get("agent_name"),
        "source_type":           ev.get("source_type"),
        "source_channel":        ev.get("channel"),
        "source_event_id":       ev.get("event_id"),
        "source_wazuh_ts_epoch": ev.get("wazuh_ts_epoch"),
        "summary":               " | ".join(summary_parts),
        "matched_json":          ev.get("raw_json_normalized") or ev.get("raw_json"),
        "confidence":            confidence,
        "amsi_matched_patterns": patterns or None,
        "no_amsi_corroboration": no_amsi,
        "obfuscation_score":     obf_score,
    }


def _run_merge(con: sqlite3.Connection, ev: dict) -> list[dict]:
    """
    Reads raw_detections window ±MERGE_WINDOW around ev's timestamp.
    Groups by (technique, process_guid, endpoint_id).
    Emits exactly one alert per group per window — upgrades in-place if needed.

    Returns:
      list[dict] — new alerts to INSERT (no _existing_alert_id key)
                   OR dicts with _existing_alert_id to UPDATE existing alert
    """
    ts  = ev.get("wazuh_ts_epoch") or int(time.time())
    fired: list[dict] = []

    try:
        pending = con.execute(
            """SELECT id, process_guid, endpoint_id, ts, layer, technique,
                      matched_pattern, event_id_fk, obfuscation_score
               FROM raw_detections
               WHERE merged = 0
                 AND ts BETWEEN ? AND ?
               ORDER BY technique, process_guid, ts""",
            (ts - _MERGE_WINDOW, ts + _MERGE_WINDOW),
        ).fetchall()
    except Exception as exc:
        print(f"[WARN] merge query: {exc}", flush=True)
        return []

    # Group by (technique, process_guid, endpoint_id)
    # For T1543.003 service-layer events (EID 7045, process_guid=NULL):
    # substitute service_name as the group key so each distinct service
    # install collapses into one alert instead of one per EID-7045 row.
    groups: dict[tuple, list[dict]] = {}
    for row in pending:
        pguid = row["process_guid"] or ""
        if row["technique"] == "T1543.003" and not pguid and row["event_id_fk"]:
            try:
                svc = con.execute(
                    "SELECT service_name FROM events WHERE id=?",
                    (row["event_id_fk"],)
                ).fetchone()
                pguid = f"svc:{(svc[0] or '').strip().lower()}" if svc and svc[0] else pguid
            except Exception:
                pass
        key = (
            row["technique"],
            pguid,
            row["endpoint_id"] or "",
        )
        groups.setdefault(key, []).append(dict(row))

    merged_row_ids: list[int] = []

    for (technique, pguid, endpoint), rows in groups.items():
        layers       = {r["layer"] for r in rows}
        all_patterns = ", ".join(filter(None, {r.get("matched_pattern") or "" for r in rows}))
        obf_score    = max(r.get("obfuscation_score") or 0.0 for r in rows)
        event_id_fk  = rows[0]["event_id_fk"]
        row_ids      = [r["id"] for r in rows]

        # --- Confidence determination (§3) ---
        if technique in _AMSI_TECHNIQUES:
            has_amsi    = "amsi" in layers
            has_cmdline = "cmdline" in layers

            if has_amsi and has_cmdline:
                confidence = "HIGH"
                no_amsi    = 0
            elif has_amsi:
                # §3.4: AMSI-only = HIGH (deobfuscated content match is strong)
                confidence = "HIGH"
                no_amsi    = 0
            else:
                # §3.3: cmdline-only = MEDIUM + corroboration flag
                # Could mean AMSI was bypassed or trace session was down.
                confidence = "MEDIUM"
                no_amsi    = 1
        elif technique == "T1543.003":
            confidence = enrich_service_confidence(ev)
            no_amsi    = 0
        else:
            # T1547.001 — registry write is strong signal
            confidence = "HIGH"
            no_amsi    = 0

        # --- Upgrade logic ---
        # If we already emitted an alert for (technique, pguid) within the window,
        # upgrade it in-place rather than emitting a duplicate.
        _purge_active_detections()
        track_key = (technique, pguid or "", endpoint or "")
        existing  = _active_detections.get(track_key)

        if existing and (ts - existing["ts"]) <= _MERGE_WINDOW:
            # Within the same 30s window — upgrade if confidence improved
            if confidence == "HIGH" and existing["confidence"] != "HIGH":
                alert = _build_alert(
                    technique, pguid or None, endpoint or None, all_patterns,
                    confidence, no_amsi, obf_score, event_id_fk, ev
                )
                alert["_existing_alert_id"] = existing["alert_id"]
                fired.append(alert)
                _active_detections[track_key]["confidence"] = "HIGH"
            # else: same or lower confidence, skip — §3.5 no duplicate
            merged_row_ids.extend(row_ids)
            continue

        # --- New alert ---
        alert = _build_alert(
            technique, pguid or None, endpoint or None, all_patterns,
            confidence, no_amsi, obf_score, event_id_fk, ev
        )
        fired.append(alert)
        # Track for potential future upgrade in this window
        _active_detections[track_key] = {
            "alert_id":   None,   # will be filled after insert by caller
            "ts":         ts,
            "confidence": confidence,
        }
        merged_row_ids.extend(row_ids)

    # Mark processed raw_detections as merged=1
    if merged_row_ids:
        placeholders = ",".join("?" * len(merged_row_ids))
        try:
            con.execute(
                f"UPDATE raw_detections SET merged = 1 WHERE id IN ({placeholders})",
                merged_row_ids,
            )
            con.commit()
        except Exception as exc:
            print(f"[WARN] merge mark: {exc}", flush=True)

    return fired


def register_alert_id(technique: str, pguid: str, endpoint: str, alert_id: int):
    """Called by ingestor after INSERT to fill in the alert_id for upgrade tracking."""
    key = (technique, pguid or "", endpoint or "")
    if key in _active_detections:
        _active_detections[key]["alert_id"] = alert_id


# ==========================================================================
# Main entry point — called by ingestor.py
# ==========================================================================

def run_rules(con: sqlite3.Connection, ev: dict, rowid: int) -> list[dict]:
    """
    Runs all detections for a single normalised event.

    Flow:
      1. If AMSI event: run Layer A (AMSI content matching) for T1059.001/005/007
      2. Run Layer B (Sigma rules) for all event types
      3. Write any hits to raw_detections staging table
      4. Run merge logic → return list of alert dicts

    Return value: list of dicts, each either:
      - New alert (no _existing_alert_id key)
      - Upgrade alert (_existing_alert_id key set → caller should UPDATE not INSERT)
    """
    load_sigma_rules()
    load_disabled_rules()

    channel = (ev.get("channel") or "").lower()

    # ------------------------------------------------------------------
    # Layer A — AMSI content detection
    # ------------------------------------------------------------------
    if channel == "ishax-amsi":
        amsi_hits = check_amsi_layer(con, ev, rowid)
        for hit in amsi_hits:
            _insert_raw_detection(con, hit)

    # ------------------------------------------------------------------
    # Layer B — Sigma rules (cmdline, registry, service events)
    # ------------------------------------------------------------------
    for r in SIGMA_RULES:
        rule_id = str(r["rule"].id)
        if rule_id in _disabled_cache:
            continue

        try:
            cur = con.execute(r["sql"] + " AND id = ?", (rowid,))
            if not cur.fetchone():
                continue
        except Exception as exc:
            print(f"[WARN] Sigma rule {rule_id}: {exc}", flush=True)
            continue

        # Map rule to technique for raw_detections
        tags = getattr(r["rule"], "tags", []) or []
        mitre_tag = next(
            (str(t).upper().replace("ATTACK.", "").replace(".00", ".")
             for t in tags if str(t).lower().startswith("attack.t")),
            None,
        )
        # Determine layer label from event type
        eid = ev.get("event_id")
        if eid in (7045, 4697):
            layer = "service"
        elif eid == 13 or "registry" in (ev.get("event_source") or ""):
            layer = "registry"
        else:
            layer = "cmdline"

        technique = mitre_tag or rule_id
        # Normalise technique (e.g. T1543.3 → T1543.003)
        # pySigma may strip leading zeros — re-add them
        _TECHNIQUE_NORM = {
            "T1059.1":   "T1059.001",
            "T1059.5":   "T1059.005",
            "T1059.7":   "T1059.007",
            "T1543.3":   "T1543.003",
            "T1547.1":   "T1547.001",
        }
        technique = _TECHNIQUE_NORM.get(technique, technique)

        raw_det = {
            "process_guid":    source_process_guid(ev),
            "endpoint_id":     ev.get("endpoint_id") or ev.get("agent_name"),
            "ts":              ev.get("wazuh_ts_epoch") or int(time.time()),
            "layer":           layer,
            "technique":       technique,
            "matched_pattern": r["rule"].title,
            "event_id_fk":     rowid,
            "obfuscation_score": 0.0,
        }
        _insert_raw_detection(con, raw_det)

    # ------------------------------------------------------------------
    # Merge — emit final alerts
    # ------------------------------------------------------------------
    return _run_merge(con, ev)
