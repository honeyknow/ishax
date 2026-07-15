import sqlite3
conn = sqlite3.connect('c:/cursor/weknows/latestedr/server/pipeline/edr.db')
conn.row_factory = sqlite3.Row
cols = [r[1] for r in conn.execute('PRAGMA table_info(events)').fetchall()]
new = ['endpoint_id','event_source','technique_candidate','original_file_name','service_binary_path','process_path']
print('=== DB Migration Check ===')
for c in new:
    status = 'OK' if c in cols else 'MISSING'
    print('  ' + c + ': ' + status)
total = conn.execute('SELECT COUNT(*) FROM events').fetchone()[0]
print('  Total events in DB: ' + str(total))
alerts = conn.execute('SELECT COUNT(*) FROM alerts').fetchone()[0]
print('  Total alerts: ' + str(alerts))
print()
print('=== Last 5 alerts ===')
for row in conn.execute('SELECT rule_id, rule_name, severity, source_agent_name FROM alerts ORDER BY id DESC LIMIT 5').fetchall():
    print(dict(row))
