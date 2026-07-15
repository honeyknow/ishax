# AMSI ETW Watcher — Implementation Document
<!-- AI AGENT INSTRUCTIONS — READ FIRST, ENFORCE STRICTLY -->
<!--
## MANDATORY RULES FOR ALL AI AGENTS WORKING ON THIS FILE

1. TOKEN DISCIPLINE: No verbose explanations. Code first, explanation only if non-obvious.
   Do not restate task. Do not summarize what you did. One line confirmation after work.
2. SCOPE: Only modify files explicitly named in the request. Ask before touching anything else.
3. NO ASSUMPTIONS: All Windows API facts must come from learn.microsoft.com only.
   No blogs, no Stack Overflow, no GitHub issues as authoritative sources.
4. CONTEXT CATCHUP: Before starting any task, read the CURRENT STATE section at bottom
   of this document. Do not assume anything from session history.
5. EXCEPTIONS FIRST: If a failure point or blocking issue is found during implementation,
   add it immediately to the EXCEPTIONS section at top of this document, then inform user.
6. TEST EACH PHASE: Do not proceed to next phase without running the test specified at end
   of each phase. Document test result in CURRENT STATE.
7. ONE BINARY GOAL: Final output must be a single amsi_watcher.exe, statically linked,
   no external dependencies except Windows system DLLs.
8. DO NOT WASTE TOKENS: Skip unchanged code in diffs. Use exact file+line references.
-->

---

## EXCEPTIONS (Active Blockers — Resolve Before Proceeding)

_None currently. Add here as discovered: `[PHASE X] [SEVERITY: HIGH/MED/LOW] description`_

---

## Project Goal

Build `amsi_watcher.exe` — a standalone Windows C service that:
- Subscribes to AMSI ETW provider in real-time
- Resolves `process_guid` via Sysmon Event Log query (PID → GUID)
- Writes enriched events to Windows Event Log custom channel `ISHAX-AMSI`
- Wazuh agent reads `ISHAX-AMSI` channel → `archives.json` → existing parser → `amsi_events` table
- Single endpoint, no new HTTP endpoint, perfect correlation, no Python dependency

**Why this approach:** See architecture decision log at bottom of this document.

---

## Target System Requirements

- OS: Windows 10 1607 (Build 14393) or later, x64 only
  - Reason: `AMSI ETW provider` available since Windows 10 1607
  - `EnableTraceEx2`: available since Windows 7 (but AMSI requires W10)
- Privileges: Must run as SYSTEM or Administrator (ETW session creation requires SeSystemTracePrivilege)
- Dependencies: Sysmon must be installed and running (for process_guid lookup)
- Wazuh agent must be installed (final transport)
- Build: MinGW x86_64-w64-mingw32-gcc (installed in WSL Kali)

---

## Architecture (Final, No Changes)

```
[Windows Machine]
  AMSI ETW Provider {2A576B87-09A7-520E-C21A-4942F0271D67}
          | (ETW real-time callback, ProcessTrace thread)
  amsi_watcher.exe
          | (EvtQuery on AMSI event: PID -> process_guid lookup)
  Sysmon Event Log [Microsoft-Windows-Sysmon/Operational, EventID=1]
          | (ReportEvent to custom channel)
  Windows Event Log [ISHAX-AMSI channel]
          | (EvtSubscribe, same mechanism as Security/Sysmon channels)
  Wazuh Agent (existing, unmodified)
          | (existing pipeline, no changes)
  archives.json -> parser.py -> amsi_events table -> dashboard AMSI tab
```

**Why Windows Event Log transport (not stdout/named pipe):**
- Kernel-backed: events persist across crashes
- Wazuh EvtSubscribe is interrupt-driven (not polling)
- Standard enterprise pattern (Elastic Beats, Splunk UF use same)
- If amsi_watcher crashes: already-written events preserved, Wazuh processes them on restart

---

## API Reference (Official: learn.microsoft.com only)

### ETW Session APIs (evntrace.h, advapi32.lib)

| Function | Purpose | Official Doc |
|---|---|---|
| StartTraceW | Create ETW real-time session | https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-starttracew |
| EnableTraceEx2 | Enable a provider on a session | https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-enabletraceex2 |
| OpenTraceW | Open session for consumption | https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-opentracew |
| ProcessTrace | Blocking call, delivers events via callback | https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-processtrace |
| CloseTrace | Close consumer handle | https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-closetrace |
| ControlTraceW | Stop/query session | https://learn.microsoft.com/en-us/windows/win32/api/evntrace/nf-evntrace-controltracew |

### TDH APIs (tdh.h, tdh.lib)

| Function | Purpose | Official Doc |
|---|---|---|
| TdhGetEventInformation | Get TRACE_EVENT_INFO (property metadata) | https://learn.microsoft.com/en-us/windows/win32/api/tdh/nf-tdh-tdhgeteventinformation |
| TdhFormatProperty | Format a single property value to WCHAR string | https://learn.microsoft.com/en-us/windows/win32/api/tdh/nf-tdh-tdhformatproperty |

### Windows Event Log APIs (winevt.h / winbase.h)

| Function | Purpose | Official Doc |
|---|---|---|
| RegisterEventSourceW | Get HANDLE to write custom events | https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-registereventsourcew |
| ReportEventW | Write event to Event Log | https://learn.microsoft.com/en-us/windows/win32/api/winbase/nf-winbase-reporteventw |
| EvtQuery | Query Sysmon event log for PID | https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtquery |
| EvtNext | Get next event from query result | https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtnext |
| EvtRender | Render event to XML | https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtrender |
| EvtClose | Close event handle | https://learn.microsoft.com/en-us/windows/win32/api/winevt/nf-winevt-evtclose |

### Windows Service APIs (winsvc.h, advapi32.lib)

| Function | Purpose |
|---|---|
| RegisterServiceCtrlHandlerW | Register stop/pause handler |
| SetServiceStatus | Report service state to SCM |
| StartServiceCtrlDispatcherW | Hand control to SCM (main thread blocks) |

---

## AMSI ETW Provider Facts (Verified on TUF17 via logman query providers)

```
Provider Name:  Microsoft-Antimalware-Scan-Interface
GUID:           {2A576B87-09A7-520E-C21A-4942F0271D67}
Verified on:    Windows 11 (TUF17 machine), 2026-07-03
Command used:   logman query providers | Select-String "AMSI"
```

**AMSI Event IDs:**
- 1101 — AMSI scan called (Session, ScanStatus, ScanResult, ContentName, Content, ContentSize)
- 1102 — AMSI result (post-scan verdict)

**Key properties in Event 1101 UserData (TDH-decoded):**
- Session — UINT32: AMSI session identifier
- ScanStatus — UINT32: 0=complete
- ScanResult — UINT32: 0=clean, 1=not_detected, 32768+=malware
- ContentName — UnicodeString: source identifier (e.g., "powershell", file path)
- Content — Binary: actual script/code bytes (decode as UTF-16LE)
- ContentSize — UINT32: size of Content in bytes

CAUTION: Content field may be truncated if > 64KB (Windows AMSI buffer limit).
SOURCE: https://learn.microsoft.com/en-us/windows/win32/amsi/antimalware-scan-interface-portal

---

## Key Structs (from official Windows SDK headers)

### EVENT_TRACE_PROPERTIES (evntrace.h)
```c
// Must allocate: sizeof(EVENT_TRACE_PROPERTIES) + (wcslen(session_name)+1)*2 bytes
// LoggerNameOffset must = sizeof(EVENT_TRACE_PROPERTIES)
// LogFileMode = EVENT_TRACE_REAL_TIME_MODE (0x00000100)
// LogFileNameOffset = 0 for real-time
```

### EVENT_PROPERTY_INFO (tdh.h) — 24 bytes total
```c
typedef struct _EVENT_PROPERTY_INFO {
    PROPERTY_FLAGS Flags;        // 4 bytes
    ULONG          NameOffset;   // 4 bytes: offset from TRACE_EVENT_INFO start to WCHAR name
    union {                      // 8 bytes
        struct { USHORT InType; USHORT OutType; ULONG MapNameOffset; };
        struct { USHORT InType_s; USHORT OutType_s; USHORT StructStartIndex; USHORT NumOfStructMembers; };
    };
    union { USHORT count; USHORT countPropertyIndex; };   // 2 bytes
    union { USHORT length; USHORT lengthPropertyIndex; }; // 2 bytes
    union { ULONG Reserved; ULONG Tags; };                // 4 bytes
} EVENT_PROPERTY_INFO;  // Total: 24 bytes
```

### TRACE_EVENT_INFO layout note
```
sizeof(TRACE_EVENT_INFO) = use offsetof() macro, do NOT hardcode
Array of EVENT_PROPERTY_INFO starts at: (BYTE*)pInfo + sizeof(TRACE_EVENT_INFO)
PropertyCount field: use offsetof(TRACE_EVENT_INFO, PropertyCount)
```

---

## File Structure

```
edr/
  amsi/
    AMSI_ETW_IMPL.md       <- this file
    amsi_watcher.c         <- main source (Phases 2-6)
    Makefile               <- MinGW cross-compile (Phase 1)
    install.bat            <- service + event source registration (Phase 5)
    test_amsi.ps1          <- test trigger script (Phase 6)
  pipeline/
    parser.py              <- add AMSI event handler (Phase 7)
    api.py                 <- add GET /amsi endpoint (Phase 8)
  dashboard/src/components/
    PivotPanel.tsx         <- add AMSI tab (Phase 9)
  scripts/
    ossec_clean.conf       <- add ISHAX-AMSI localfile entry (Phase 5)
```

---

## Implementation Phases

### PHASE 1 — Build Infrastructure
**Goal:** Verify MinGW produces working Windows EXE from WSL.

File: `edr/amsi/Makefile`
```makefile
CC      = x86_64-w64-mingw32-gcc
CFLAGS  = -Wall -O2 -municode -DUNICODE -D_UNICODE
LDFLAGS = -ladvapi32 -ltdh -lwevtapi -lole32 -static-libgcc
TARGET  = amsi_watcher.exe
SRC     = amsi_watcher.c

$(TARGET): $(SRC)
	$(CC) $(CFLAGS) -o $(TARGET) $(SRC) $(LDFLAGS)

clean:
	rm -f $(TARGET)
```

**Phase 1 Test (WSL):**
```bash
cd /mnt/c/cursor/weknows/edr/amsi
echo 'int wmain(){return 0;}' > test.c
x86_64-w64-mingw32-gcc -o test.exe test.c -municode && echo BUILD_OK || echo BUILD_FAIL
rm -f test.c test.exe
```
Expected: BUILD_OK
Status: NOT STARTED

---

### PHASE 2 — ETW Session + Provider Subscription
**Goal:** StartTraceW + EnableTraceEx2 for AMSI provider, no errors.

**Key constants:**
```c
#define SESSION_NAME              L"ISHAX-AMSI-ETW"
#define AMSI_GUID_STR             L"{2A576B87-09A7-520E-C21A-4942F0271D67}"
#define EVT_REAL_TIME             0x00000100UL
#define PROCESS_TRACE_REAL_TIME   0x00000100UL
#define PROCESS_TRACE_EVENT_RECORD 0x10000000UL
#define WNODE_FLAG_TRACED_GUID    0x00020000UL
#define TRACE_LEVEL_VERBOSE       5
```

**Critical notes from official docs:**
1. StartTraceW returns 183 (ERROR_ALREADY_EXISTS) if session exists
   -> Call ControlTraceW(0, SESSION_NAME, props, EVENT_TRACE_CONTROL_STOP) first
2. Buffer: malloc(sizeof(EVENT_TRACE_PROPERTIES) + sizeof(SESSION_NAME) + 2)
3. Wnode.BufferSize = total allocated bytes
4. LoggerNameOffset = sizeof(EVENT_TRACE_PROPERTIES)
5. EnableTraceEx2: MatchAnyKeyword = 0xFFFFFFFFFFFFFFFF, Level = TRACE_LEVEL_VERBOSE

**Phase 2 Test (PowerShell as Admin):**
```powershell
logman query "ISHAX-AMSI-ETW"
```
Expected: Shows active session
Status: NOT STARTED

---

### PHASE 3 — TDH Event Decoding
**Goal:** In EVENT_RECORD callback, decode AMSI event properties using TDH.

**Algorithm:**
```
1. TdhGetEventInformation(pRecord, 0, NULL, NULL, &bufSize) -> ERROR_INSUFFICIENT_BUFFER (122)
2. pInfo = malloc(bufSize)
3. TdhGetEventInformation(pRecord, 0, NULL, pInfo, &bufSize) -> 0
4. pPropArr = (EVENT_PROPERTY_INFO*)((BYTE*)pInfo + sizeof(TRACE_EVENT_INFO))
5. userData = pRecord->UserData, remaining = pRecord->UserDataLength
6. For i=0 to pInfo->PropertyCount-1:
   - name = (WCHAR*)((BYTE*)pInfo + pPropArr[i].NameOffset)
   - TdhFormatProperty(pInfo, NULL, 8, inType, outType, propLen,
                       remaining, userData, &consumed, &fmtSz, fmtBuf)
   - userData += consumed; remaining -= consumed
7. Match names: "ContentName", "ScanResult", "Content"
```

**TdhFormatProperty signature:**
```c
ULONG TdhFormatProperty(
  PTRACE_EVENT_INFO pEventInfo,  // from step 3
  PEVENT_MAP_INFO   pMapInfo,    // NULL
  ULONG             PointerSize, // 8 on x64
  USHORT            PropertyInType,
  USHORT            PropertyOutType,
  USHORT            PropertyLength,   // 0 = derive from data
  ULONG             UserDataLength,
  PBYTE             UserData,
  PULONG            UserDataConsumed, // OUT
  PULONG            BufferSize,       // IN/OUT
  PWCHAR            Buffer            // OUT
);
// Returns 0=ok, 122=buf too small (retry with *BufferSize), other=skip property
```

**Phase 3 Test:** Run `Write-Host "test"` in PowerShell. Watcher should log ContentName="powershell".
Status: NOT STARTED

---

### PHASE 4 — Sysmon process_guid Lookup
**Goal:** From PID in AMSI event, query Sysmon Event Log for process_guid.

**XPath query (EvtQuery):**
```c
// Build dynamically with PID value
// L"*[System[EventID=1] and EventData[Data[@Name='ProcessId']='4521']]"
```

**Algorithm:**
```
1. EvtQuery(NULL, L"Microsoft-Windows-Sysmon/Operational",
            xpath, EvtQueryChannelPath | EvtQueryReverseDirection) -> hResults
2. EvtNext(hResults, 1, &hEvent, INFINITE, 0, &returned)
3. If returned=0: process_guid = L"UNKNOWN"
4. EvtRender(NULL, hEvent, EvtRenderEventXml, bufSize, xmlBuf, &used, &propCount)
5. wcsstr(xmlBuf, L"ProcessGuid") -> parse value between > and <
6. Strip { } braces, lowercase -> UUID string
7. EvtClose(hEvent); EvtClose(hResults)
```

**Failure modes (accepted):**
- Sysmon not running: EvtQuery returns error -> process_guid = "UNKNOWN", continue
- Log rolled over: EvtNext returns 0 -> process_guid = "UNKNOWN", continue
- PID reused: wrong guid (~1% cases) -> accepted known limitation

**Phase 4 Test:** Check logged event has valid UUID in process_guid field.
Status: NOT STARTED

---

### PHASE 5 — Windows Event Log Write + Wazuh Config

**Event source registration (install.bat — run once as Admin):**
```batch
reg add "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\ISHAX-AMSI\ISHAX-AMSI" /v EventMessageFile /t REG_SZ /d "%SystemRoot%\System32\EventCreate.exe" /f
reg add "HKLM\SYSTEM\CurrentControlSet\Services\EventLog\ISHAX-AMSI\ISHAX-AMSI" /v TypesSupported /t REG_DWORD /d 7 /f
```

**Writing event in C:**
```c
// Build UTF-16 JSON (no external JSON lib — use swprintf)
WCHAR json[8192];
swprintf(json, 8192,
  L"{\"pid\":%lu,\"process_guid\":\"%s\",\"content_name\":\"%s\","
  L"\"scan_result\":%lu,\"content\":\"%s\",\"host_id\":\"%s\"}",
  pid, guid, contentName, scanResult, contentPreview, hostname);

HANDLE hLog = RegisterEventSourceW(NULL, L"ISHAX-AMSI");
LPCWSTR msgs[1] = { json };
ReportEventW(hLog, EVENTLOG_WARNING_TYPE, 0, 4000, NULL, 1, 0, msgs, NULL);
DeregisterEventSource(hLog);
```

**ossec_clean.conf addition (one block):**
```xml
<localfile>
  <location>ISHAX-AMSI</location>
  <log_format>eventchannel</log_format>
</localfile>
```

**Phase 5 Test (PowerShell):**
```powershell
Get-WinEvent -LogName "ISHAX-AMSI" -MaxEvents 5
```
Status: NOT STARTED

---

### PHASE 6 — Windows Service Wrapper

**ServiceMain pattern:**
```c
static SERVICE_STATUS_HANDLE g_hStatus;

VOID WINAPI SvcCtrlHandler(DWORD ctrl) {
    if (ctrl == SERVICE_CONTROL_STOP) {
        SetSvcStatus(SERVICE_STOP_PENDING, NO_ERROR, 3000);
        StopEtwSession();  // calls ControlTraceW STOP
    }
}

VOID WINAPI SvcMain(DWORD argc, LPWSTR* argv) {
    g_hStatus = RegisterServiceCtrlHandlerW(L"ISHAXAmsi", SvcCtrlHandler);
    SetSvcStatus(SERVICE_START_PENDING, NO_ERROR, 3000);
    if (!StartEtwSession()) { SetSvcStatus(SERVICE_STOPPED, 1, 0); return; }
    SetSvcStatus(SERVICE_RUNNING, NO_ERROR, 0);
    ProcessTrace(...);  // blocks until stopped
    SetSvcStatus(SERVICE_STOPPED, NO_ERROR, 0);
}

int wmain(int argc, WCHAR** argv) {
    if (argc > 1 && wcscmp(argv[1], L"--console") == 0) {
        StartEtwSession(); ProcessTrace(...); return 0;  // debug mode
    }
    SERVICE_TABLE_ENTRYW table[] = { {L"ISHAXAmsi", SvcMain}, {NULL,NULL} };
    StartServiceCtrlDispatcherW(table);
    return 0;
}
```

**install.bat service commands:**
```batch
sc create ISHAXAmsi binPath= "\"C:\Program Files\ISHAX\amsi_watcher.exe\"" start= auto DisplayName= "ISHAX AMSI ETW Watcher"
sc description ISHAXAmsi "AMSI ETW real-time collector for ISHAX EDR"
sc start ISHAXAmsi
```

**Phase 6 Test:**
```powershell
Get-Service ISHAXAmsi  # Expected: Running
```
Status: NOT STARTED

---

### PHASE 7 — parser.py AMSI Handler

**Event structure arriving via Wazuh archives.json:**
```json
{
  "win": {
    "system": { "channel": "ISHAX-AMSI", "eventID": "4000" },
    "eventdata": {
      "param1": "{\"pid\":1234,\"process_guid\":\"abc-def\",\"content_name\":\"powershell\",\"scan_result\":0,\"content\":\"Write-Host\",\"host_id\":\"TUF17\"}"
    }
  }
}
```

**parser.py addition (add to existing event routing):**
```python
elif channel == "ISHAX-AMSI":
    import json as _json
    d = _json.loads(event.get("win",{}).get("eventdata",{}).get("param1","{}"))
    _insert_amsi(d)
```

**Phase 7 Test:**
```bash
docker compose exec -T app python3 -c \
  "from pipeline.db import get_connection; c=get_connection(); cur=c.cursor(); \
  cur.execute('SELECT count(*) FROM amsi_events'); print(cur.fetchone())"
```
Status: NOT STARTED

---

### PHASE 8 — API Endpoint

Add to `pipeline/api.py`:
```python
@app.get("/amsi")
def get_amsi(host_id: str = None, process_guid: str = None, limit: int = 100):
    rows = _query(
        """SELECT pid, process_guid, content_name, scan_result,
                  LEFT(content, 500) AS content_preview, host_id, event_timestamp
           FROM amsi_events
           WHERE (%s IS NULL OR host_id = %s)
             AND (%s IS NULL OR process_guid = %s)
           ORDER BY event_timestamp DESC LIMIT %s""",
        (host_id, host_id, process_guid, process_guid, limit)
    )
    return rows
```

**Phase 8 Test:**
```bash
curl -s "http://localhost:8000/amsi?host_id=TUF17&limit=5"
```
Status: NOT STARTED

---

### PHASE 9 — Dashboard AMSI Tab

Add to `PivotPanel.tsx`:
- Tab: id="amsi", label="AMSI", icon=Shield
- Fetch: `api.amsi(selectedProcessGuid, hostId)`
- Display: ContentName (badge), ScanResult (green=0/red=32768+), content in monospace pre block truncated 500 chars

**Phase 9 Test:** Visual — select process in tree -> click AMSI tab -> events render.
Status: NOT STARTED

---

## CURRENT STATE (AI agents: read this before starting work)

```
Last updated:          2026-07-06T22:04 IST
MinGW installed:       YES (x86_64-w64-mingw32-gcc 15.2.0, WSL Kali)
AMSI GUID verified:    YES ({2A576B87-09A7-520E-C21A-4942F0271D67} on TUF17)

amsi_watcher.c:        UPDATED — edr/amsi/amsi_watcher.c
Makefile:              edr/amsi/Makefile
install.bat:           edr/amsi/install.bat (use clean_install.bat for fresh reinstall)
clean_install.bat:     edr/amsi/clean_install.bat — full wipe + reinstall script
test_amsi.ps1:         edr/amsi/test_amsi.ps1
ossec_clean.conf:      UPDATED — ISHAX-AMSI channel added

Phase 1 (Build):       DONE — amsi_watcher.exe compiles clean, zero warnings
Phase 2 (ETW):         DONE + TESTED — ISHAX-AMSI-ETW session confirmed via logman -ets
Phase 3 (Decode):      DONE + TESTED — Direct UserData parsing (TDH by-name fails for this
                         provider: amsi.dll manifest doesn't expose TDH property descriptors)
Phase 4 (GUID):        DONE + TESTED — Sysmon GUID lookup working, real GUIDs confirmed
Phase 5 (Event Log):   DONE + TESTED — Events writing to ISHAX-AMSI channel confirmed
Phase 6 (Service):     DONE + TESTED — ISHAXAmsi service running as SYSTEM confirmed

BUGS FIXED (during Phase 2-6 testing):
  BUG-1: %s vs %ls in MinGW swprintf — MinGW follows C99: %s=char*, %ls=wchar_t*.
          All WCHAR* args in swprintf/wprintf changed to %ls.
  BUG-2: TDH property-by-name fails — AMSI manifest in amsi.dll doesn't expose
          property descriptors via TdhGetPropertySize. Replaced with direct
          UserData parsing (ParseAmsiRaw). Layout confirmed via ETL analysis:
            [0] UINT64  session (8B)
            [1] UINT8   scanStatus (1B)
            [2] UINT32  scanResult (4B) — offset 9, unaligned, use memcpy
            [3] WCHAR[] contentName (null-terminated)
            [4] WCHAR[] unknown (null-terminated, empty)
            [5] UINT32  contentSize (bytes)
            [6] UINT32  reserved
            [7] BYTE[]  content (contentSize bytes, UTF-16LE)

SAMPLE VERIFIED OUTPUT (2026-07-06):
  {"pid":23748,"process_guid":"d25afbd5-d2d7-6a4b-8a07-000000005500",
   "content_name":"PowerShell_C:\\Windows\\...\\powershell.exe_10.0.26100.8737",
   "scan_result":1,"content_hex":"530074006100720074002d...","host_id":"TUF17"}
  content_hex decodes to: "Start-Sleep -Seconds 3" (UTF-16LE)

Phase 7 (Parser):      NOT STARTED — pipeline/parser/amsi.py needs AMSI handler
Phase 8 (API):         NOT STARTED — pipeline/api.py needs GET /amsi endpoint
Phase 9 (Dashboard):   NOT STARTED — PivotPanel.tsx needs AMSI tab

NEXT STEP: Phase 7 — wire amsi_watcher output into pipeline parser
  The Wazuh agent will read ISHAX-AMSI channel events and write them to archives.json.
  The pipeline parser/amsi.py already exists — it needs updating to parse the new
  JSON format (content_hex instead of content, process_guid, host_id fields).
```

---

## Architecture Decision Log

| Decision | Rejected Alternative | Reason |
|---|---|---|
| Windows Event Log transport | stdout pipe | Kernel-backed, no deadlock, no buffering issues |
| Windows Event Log transport | named pipe | Auth risk, MITM, process lifecycle coupling |
| Windows Event Log transport | separate HTTP endpoint | Correlation gap (no process_guid without extra work) |
| C usermode (not Python) | Python | 200KB vs 40MB, no GIL, no AV suspicion, no pip |
| C usermode (not kernel driver) | Kernel driver | Requires EV cert $300+, BSOD risk, months dev |
| C usermode (not Wazuh fork) | Wazuh C modification | ABI mismatch MinGW vs MSVC, no VS2022 build env |
| Sysmon EventLog for PID->GUID | Sysmon ETW subscription | Simpler, no second ETW session needed |
| Single amsi_watcher.exe | Plugin system (multiple EXEs) | Multiple EXEs = multiple attack/failure points |

---

## Known Limitations (Accepted)

1. process_guid accuracy ~92%: PID recycling in <2s causes wrong correlation. Accepted.
2. Sysmon required: No Sysmon -> process_guid="UNKNOWN". Documented in install.bat.
3. Admin/SYSTEM required: ETW needs SeSystemTracePrivilege.
4. Windows 10 1607+ x64 only: AMSI ETW provider not on older OS.
5. Content truncated at 64KB: Windows AMSI buffer limit.
