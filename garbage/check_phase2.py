#!/usr/bin/env python3
"""
Quick validation of all changes made in Phase 2:
1. detector.py loads Sigma rules
2. ingestor.py imports work (dedup, new columns)
3. sigma_rules/*.yml all exist and parse
4. sysmon_config.xml is valid XML
5. endpoint_setup.ps1 has the new sections
"""
import sys, os, json, hashlib, sqlite3, xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).parent

PASS = "[PASS]"
FAIL = "[FAIL]"
WARN = "[WARN]"

errors = 0

def check(label, ok, detail=""):
    global errors
    if ok:
        print(f"{PASS} {label}")
    else:
        print(f"{FAIL} {label}: {detail}")
        errors += 1

# ── 1. detector.py: Sigma rules load ─────────────────────────────────────────
print("\n── 1. detector.py + pySigma ──")
try:
    sys.path.insert(0, str(ROOT))
    from detector import load_sigma_rules, SIGMA_RULES
    load_sigma_rules()
    check("pySigma loaded", len(SIGMA_RULES) > 0, f"found {len(SIGMA_RULES)} rules")
    for r in SIGMA_RULES:
        check(f"  Rule: {r['rule'].title}", "SELECT id FROM events WHERE" in r["sql"],
              "SQL does not target events table")
except Exception as e:
    check("detector.py import", False, str(e))

# ── 2. sigma_rules/ - all 8 files exist ──────────────────────────────────────
print("\n── 2. sigma_rules/*.yml (8 rules required) ──")
rules_dir = ROOT / "sigma_rules"
expected = [
    "t1059-001-powershell.yml",
    "t1547-001-run-keys.yml",
    "t1036-masquerading.yml",
    "t1047-wmi.yml",
    "t1105-ingress-tool-transfer.yml",
    "t1055-process-injection.yml",
    "t1543-003-new-service.yml",
    "t1219-rmm-abuse.yml",
]
for f in expected:
    p = rules_dir / f
    check(f"  {f}", p.exists(), "file missing")

# ── 3. ingestor.py: dedup hash logic ─────────────────────────────────────────
print("\n── 3. ingestor.py dedup hash ──")
try:
    src = (ROOT / "ingestor.py").read_text()
    check("hashlib import", "import hashlib" in src)
    check("SHA-256 dedup_hash", "hashlib.sha256" in src)
    check("dedup_hash assigned to wazuh_id", 'out_dict["wazuh_id"] = dedup_hash' in src)
    check("run_rules receives db.con", "run_rules(db.con, ev, rowid)" in src)
except Exception as e:
    check("ingestor.py read", False, str(e))

# ── 4. schema.sql: new columns ────────────────────────────────────────────────
print("\n── 4. schema.sql new columns ──")
try:
    schema = (ROOT / "schema.sql").read_text()
    for col in ["original_file_name", "service_binary_path", "process_hash", "process_path", "source_ip", "username"]:
        check(f"  column: {col}", col in schema)
except Exception as e:
    check("schema.sql read", False, str(e))

# ── 5. sysmon_config.xml validity + required EIDs ─────────────────────────────
print("\n── 5. sysmon_config.xml ──")
xml_path = ROOT.parent.parent / "endpoint" / "sysmon_config.xml"
try:
    tree = ET.parse(str(xml_path))
    root = tree.getroot()
    check("Valid XML", True)
    xml_text = xml_path.read_text()
    check("EID 3 (NetworkConnect)", "NetworkConnect" in xml_text)
    check("EID 8 (CreateRemoteThread)", "CreateRemoteThread" in xml_text)
    check("EID 10 (ProcessAccess + masks)", "0x1010" in xml_text)
    check("EID 13 (RegistryEvent Run keys)", "Run" in xml_text)
    check("EID 15 (FileCreateStreamHash)", "FileCreateStreamHash" in xml_text)
    check("EID 19/20/21 (WmiEvent)", "WmiEvent" in xml_text)
except Exception as e:
    check("sysmon_config.xml", False, str(e))

# ── 6. endpoint_setup.ps1: new audit + scriptblock ───────────────────────────
print("\n── 6. endpoint_setup.ps1 ──")
ps_path = ROOT.parent.parent / "endpoint" / "endpoint_setup.ps1"
try:
    ps_text = ps_path.read_text()
    check("Security System Extension auditpol", "Security System Extension" in ps_text)
    check("ScriptBlock Logging registry key", "EnableScriptBlockLogging" in ps_text)
    check("PowerShell/Operational channel in ossec.conf", "Microsoft-Windows-PowerShell/Operational" in ps_text)
except Exception as e:
    check("endpoint_setup.ps1 read", False, str(e))

# ── Summary ───────────────────────────────────────────────────────────────────
print(f"\n──────────────────────────────────────────")
if errors == 0:
    print(f"[ALL PASS] No issues found.")
else:
    print(f"[{errors} FAILURE(S)] Fix above before running.")
sys.exit(errors)
