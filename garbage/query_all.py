import sqlite3, json

conn = sqlite3.connect("server/pipeline/edr.db")
conn.row_factory = sqlite3.Row
SEP = "\n" + "="*60 + "\n"

# 1. SCHEMA
print(SEP + "SCHEMA")
tables = conn.execute("SELECT name FROM sqlite_master WHERE type=''table''").fetchall()
for t in tables:
    cols = conn.execute(f"PRAGMA table_info({t[''name'']})")
    print(f"{t[''name'']}: {[c[''name''] for c in cols.fetchall()]}")

# 2. COUNTS
print(SEP + "ROW COUNTS")
for t in tables:
    n = conn.execute(f"SELECT COUNT(*) as c FROM {t[''name'']}").fetchone()
    print(f"  {t[''name'']}: {n[''c'']}")

# 3. ALL ALERTS
print(SEP + "ALL ALERTS (created_at ASC)")
try:
    rows = conn.execute("SELECT id,rule_id,confidence,obfuscation_score,amsi_matched_patterns,no_amsi_corroboration,created_at FROM alerts ORDER BY created_at ASC").fetchall()
    for r in rows: print(dict(r))
except Exception as e:
    cols = conn.execute("PRAGMA table_info(alerts)").fetchall()
    print("ERR:", e, "COLS:", [c["name"] for c in cols])

# 4. ALERT CLUSTERS
print(SEP + "ALERT CLUSTERS")
rows = conn.execute("SELECT rule_id,confidence,COUNT(*) cnt,MIN(created_at) first_ts,MAX(created_at) last_ts FROM alerts GROUP BY rule_id,confidence ORDER BY first_ts").fetchall()
for r in rows: print(dict(r))

# 5. OBFUSCATION
print(SEP + "OBFUSCATION_SCORE > 0")
rows = conn.execute("SELECT id,rule_id,obfuscation_score,no_amsi_corroboration,created_at FROM alerts WHERE obfuscation_score > 0").fetchall()
print(f"Count: {len(rows)}")
for r in rows: print(dict(r))

# 6. EVENTS
print(SEP + "EVENTS SCHEMA + COUNT")
try:
    cols = conn.execute("PRAGMA table_info(events)").fetchall()
    cnames = [c["name"] for c in cols]
    print("cols:", cnames)
    n = conn.execute("SELECT COUNT(*) as c FROM events").fetchone()
    print("total:", n["c"])
    ts = "created_at" if "created_at" in cnames else ("timestamp" if "timestamp" in cnames else None)
    if ts:
        r = conn.execute(f"SELECT MIN({ts}) mn, MAX({ts}) mx FROM events").fetchone()
        print("range:", r["mn"], "->", r["mx"])
    data_col = next((c for c in ["raw_event","raw_log","data","event_data","log"] if c in cnames), None)
    print("data_col:", data_col)
    if data_col:
        for sig,lbl in [("fax","T1543-1"),("vbsstartup","T1547-4"),("jsestartup","T1547-5"),("batstartup","T1547-6"),("mimikatz","T1059-1"),("SharpHound","T1059-3"),("mshta","T1059-8"),("AppPathBypass","T1059-5"),("cscript","T1059.007"),("wscript","T1059.007-2")]:
            r = conn.execute(f"SELECT COUNT(*) c FROM events WHERE {data_col} LIKE ?", (f"%{sig}%",)).fetchone()
            print(f"  MISS CHECK {lbl} ({sig}): {r['c']} events")
except Exception as e:
    print("EVENTS ERR:", e)

# 7. ONE FULL ALERT
print(SEP + "FULL LATEST ALERT")
row = conn.execute("SELECT * FROM alerts ORDER BY id DESC LIMIT 1").fetchone()
d = dict(row)
if "raw_event" in d and d["raw_event"]: d["raw_event"] = str(d["raw_event"])[:400]+"...[trunc]"
print(json.dumps(d, indent=2, default=str))
