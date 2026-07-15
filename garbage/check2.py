import sqlite3
conn = sqlite3.connect("server/pipeline/edr.db")
conn.row_factory = sqlite3.Row

# 1. Verify both cols have Run key data
n1 = conn.execute("SELECT COUNT(*) c FROM events WHERE target_object LIKE '%CurrentVersion%Run%'").fetchone()["c"]
n2 = conn.execute("SELECT COUNT(*) c FROM events WHERE registry_path LIKE '%CurrentVersion%Run%'").fetchone()["c"]
print(f"target_object Run keys: {n1}")
print(f"registry_path Run keys: {n2}")

# 2. Check EID 13 Run key events specifically
rows = conn.execute("SELECT id,event_id,target_object,registry_path FROM events WHERE event_id=13 AND (target_object LIKE '%CurrentVersion%Run%' OR registry_path LIKE '%CurrentVersion%Run%') LIMIT 5").fetchall()
print(f"\nEID 13 + Run key: {len(rows)} rows")
for r in rows:
    print(f"  id={r['id']} eid={r['event_id']} tobj={r['target_object']} rp={r['registry_path']}")

# 3. EID 13 total count
n3 = conn.execute("SELECT COUNT(*) c FROM events WHERE event_id=13").fetchone()["c"]
print(f"\nTotal EID 13: {n3}")

# 4. The sigma rule condition: EID=13 AND registry_path LIKE Run
# Simulate the Sigma SQL that would run
n4 = conn.execute("SELECT COUNT(*) c FROM events WHERE event_id=13 AND (registry_path LIKE '%\\\\SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\Run\\\\%' OR registry_path LIKE '%\\\\SOFTWARE\\\\Microsoft\\\\Windows\\\\CurrentVersion\\\\RunOnce\\\\%' OR registry_path LIKE '%\\\\Winlogon\\\\Shell%')").fetchone()["c"]
print(f"\nSigma simulation (EID13+registry_path Run): {n4} events would match")

# 5. Check ingestion timestamps for EID 13 vs T1547 test window
# T1547 run was during 16:07-16:53 UTC (events ingestion range)
rows = conn.execute("SELECT id,event_id,target_object,registry_path,ingested_at FROM events WHERE event_id=13 LIMIT 5").fetchall()
print("\nEID 13 sample:")
for r in rows:
    print(f"  id={r['id']} tobj={r['target_object']} rp={r['registry_path']} ingested={r['ingested_at']}")
