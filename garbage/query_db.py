import sqlite3, datetime, json

conn = sqlite3.connect('server/pipeline/edr.db')
conn.row_factory = sqlite3.Row

def ts(epoch):
    return datetime.datetime.utcfromtimestamp(epoch).strftime('%Y-%m-%dT%H:%M:%SZ') if epoch else 'N/A'

# 1. RAW_DETECTIONS with human timestamps
print('=== RAW_DETECTIONS ===')
rows = conn.execute('SELECT id,process_guid,technique,layer,matched_pattern,obfuscation_score,merged,ts FROM raw_detections ORDER BY ts ASC').fetchall()
for r in rows:
    print(f"  id={r['id']} {ts(r['ts'])} tech={r['technique']} layer={r['layer']} merged={r['merged']} pguid={r['process_guid']}")
    print(f"    pattern={r['matched_pattern']} obf={r['obfuscation_score']}")

# 2. ALERTS with human timestamps
print('\n=== ALERTS ===')
rows = conn.execute('SELECT id,rule_name,mitre_technique,severity,confidence,obfuscation_score,no_amsi_corroboration,amsi_matched_patterns,fired_at FROM alerts ORDER BY fired_at ASC').fetchall()
for r in rows:
    print(f"  id={r['id']} {ts(r['fired_at'])} tech={r['mitre_technique']} conf={r['confidence']} no_amsi={r['no_amsi_corroboration']} obf={r['obfuscation_score']}")
    print(f"    rule={r['rule_name']}")
    print(f"    amsi_patterns={r['amsi_matched_patterns']}")

# 3. MISS ANALYSIS - command_line search in events
print('\n=== MISS ANALYSIS - events command_line ===')
for sig, lbl in [
    ('mimikatz', 'T1059-1 Mimikatz'), ('SharpHound', 'T1059-3 BloodHound'),
    ('AppPathBypass', 'T1059-5'), ('MsXml', 'T1059-6 MsXml'),
    ('mshta', 'T1059-8 mshta'), ('AtomicRedTeam', 'T1059-10 Fileless'),
    ('AlternateDataStream', 'T1059-11 ADS'), ('sys_info', 'T1059.007 JScript'),
    ('cscript', 'T1059.007-1'), ('wscript', 'T1059.007-2'),
    ('vbsstartup', 'T1547-4 VBS startup'), ('jsestartup', 'T1547-5 JSE startup'),
    ('batstartup', 'T1547-6 BAT startup'), ('fax', 'T1543-1 Fax svc'),
    ('W64Time', 'T1543-4 TinyTurla'), ('AtomicTestService', 'T1543-2/3 NewSvc'),
    ('calc_exe.lnk', 'T1547-7 Shortcut'), ('SystemBC', 'T1547-9'),
    ('BootExecute', 'T1547-17'), ('RunOnce', 'T1547-2'),
    ('vbscript', 'T1059-5 VBScript'), ('sys_info.vbs', 'T1059.005-1'),
]:
    r = conn.execute('SELECT COUNT(*) c FROM events WHERE command_line LIKE ?', (f'%{sig}%',)).fetchone()
    print(f"  [{r['c']:3d}] {lbl} ({sig})")

# 4. T1547 REGISTRY via target_object
print('\n=== T1547 REGISTRY target_object ===')
run_q = "SELECT COUNT(*) c FROM events WHERE target_object LIKE '%\\Run%' OR target_object LIKE '%\\RunOnce%'"
r = conn.execute(run_q).fetchone()
print(f"  Run/RunOnce registry events: {r['c']}")
startup_q = "SELECT COUNT(*) c FROM events WHERE target_object LIKE '%\\Startup%'"
r = conn.execute(startup_q).fetchone()
print(f"  Startup registry events: {r['c']}")
# Show sample target_objects
rows = conn.execute("SELECT DISTINCT target_object FROM events WHERE target_object LIKE '%Run%' AND target_object IS NOT NULL LIMIT 15").fetchall()
for r in rows:
    print(f"    {r['target_object']}")

# 5. T1547 ALERTS
print('\n=== T1547 IN ALERTS ===')
rows = conn.execute("SELECT id,rule_name,confidence,fired_at FROM alerts WHERE mitre_technique='T1547.001'").fetchall()
for r in rows:
    print(f"  id={r['id']} conf={r['confidence']} {ts(r['fired_at'])} rule={r['rule_name']}")
print(f"  Total: {len(rows)}")

# 6. T1059.005 / T1059.007 in alerts
print('\n=== T1059.005/007 IN ALERTS ===')
rows = conn.execute("SELECT id,rule_name,mitre_technique,confidence FROM alerts WHERE mitre_technique IN ('T1059.005','T1059.007')").fetchall()
print(f"  Count: {len(rows)}")
for r in rows:
    print(dict(r))

# 7. VBS/JS events in events table
print('\n=== VBS/JS EVENTS IN events TABLE ===')
for sig, lbl in [('vbs', 'VBScript ext'), ('wscript', 'wscript.exe'), ('cscript', 'cscript.exe'), ('sys_info.js', 'JScript sys_info')]:
    r = conn.execute('SELECT COUNT(*) c FROM events WHERE command_line LIKE ?', (f'%{sig}%',)).fetchone()
    print(f"  [{r['c']:3d}] {lbl}")

# 8. RUN BOUNDARY - find gap between T1059.001 run1 and run2
print('\n=== T1059.001 RAW_DETECTIONS TIMESTAMPS (boundary analysis) ===')
rows = conn.execute("SELECT id,ts,process_guid FROM raw_detections WHERE technique='T1059.001' ORDER BY ts ASC").fetchall()
for r in rows:
    print(f"  id={r['id']} ts={ts(r['ts'])} ({r['ts']}) pguid={r['process_guid']}")

# 9. events total + ingestion range
print('\n=== EVENTS INGESTION RANGE ===')
r = conn.execute('SELECT COUNT(*) c, MIN(ingested_at) mn, MAX(ingested_at) mx FROM events').fetchone()
print(f"  total={r['c']} ingested_at min={r['mn']} max={r['mx']}")
r2 = conn.execute('SELECT COUNT(*) c, MIN(wazuh_ts) mn, MAX(wazuh_ts) mx FROM events').fetchone()
print(f"  wazuh_ts range: min={r2['mn']} max={r2['mx']}")
