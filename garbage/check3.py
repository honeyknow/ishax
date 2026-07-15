import sqlite3, datetime, json
conn = sqlite3.connect("server/pipeline/edr.db")
conn.row_factory = sqlite3.Row

rows = conn.execute("SELECT id, target_object, ingested_at FROM events WHERE id IN (8618,8670,8942)").fetchall()
for r in rows:
    t = datetime.datetime.utcfromtimestamp(r["ingested_at"]).strftime("%Y-%m-%dT%H:%M:%SZ") if r["ingested_at"] else "N/A"
    print(f"id={r['id']} ingested={t} tobj={r['target_object']}")

print()
with open("server/pipeline/disabled_rules.json") as f:
    disabled = json.load(f)
print("disabled_rules.json:", disabled)

t1547_id  = "ab575646-cd24-4903-875c-ce3d17db2402"
t059005   = "a1b2c3d4-e5f6-7890-abcd-ef1234567805"
t059007   = "b2c3d4e5-f6a7-8901-bcde-f12345678907"
print(f"T1547 disabled:   {t1547_id in disabled}")
print(f"T1059.005 disabled: {t059005 in disabled}")
print(f"T1059.007 disabled: {t059007 in disabled}")
