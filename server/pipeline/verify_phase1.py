import json
import sqlite3
from pathlib import Path

PIPELINE_DIR = Path(__file__).resolve().parent
DB_PATH = PIPELINE_DIR / "edr.db"
DISABLED_RULES_PATH = PIPELINE_DIR / "disabled_rules.json"

db = sqlite3.connect(DB_PATH)

print("--- Rules Engine Test ---")
with DISABLED_RULES_PATH.open("r", encoding="utf-8") as f:
    disabled = json.load(f)
    print("disabled_rules.json:", disabled)

print("\n--- Evidence Drawer AMSI/Network Test ---")
alert = db.execute(
    "SELECT id, source_process_guid FROM alerts WHERE rule_name LIKE '%PowerShell%' LIMIT 1"
).fetchone()

if alert:
    alert_id, pguid = alert
    print(f"Alert ID: {alert_id}, Process GUID: {pguid}")

    edges = db.execute(
        "SELECT edge_type, COUNT(*) FROM process_edges WHERE process_guid = ? GROUP BY edge_type",
        (pguid,),
    ).fetchall()
    print("Edges:", edges)

    amsi_events = db.execute(
        "SELECT id, raw_json_original, raw_json_normalized, raw_json FROM events WHERE lower(channel) = 'ishax-amsi'"
    ).fetchall()
    matched = 0
    for row_id, raw_json_original, raw_json_normalized, raw_json in amsi_events:
        try:
            obj = json.loads(raw_json_normalized or raw_json or raw_json_original or "{}")
            edata = obj.get("data", {}).get("win", {}).get("eventdata", {})
            param1 = edata.get("param1") or edata.get("data")
            if not param1:
                continue
            amsi_obj = json.loads(param1)
            amsi_guid = amsi_obj.get("process_guid") or amsi_obj.get("processGuid")
            if not amsi_guid:
                continue
            amsi_guid = str(amsi_guid).strip().lower()
            if not amsi_guid.startswith("{"):
                amsi_guid = "{" + amsi_guid
            if not amsi_guid.endswith("}"):
                amsi_guid = amsi_guid + "}"
            if amsi_guid == pguid:
                matched += 1
        except Exception as exc:
            print(f"Skipping unparsable AMSI row {row_id}: {exc}")
    print("Matched AMSI events:", matched)
else:
    print("No PowerShell alert found for evidence test.")

db.close()
