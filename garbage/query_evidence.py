
import sqlite3
import json

conn = sqlite3.connect('c:/cursor/weknows/latestedr/server/pipeline/edr.db')
c = conn.cursor()

with open('raw_data_dump.txt', 'w', encoding='utf-8') as f:
    f.write('=== ALERTS DUMP ===\n')
    c.execute('SELECT id, fired_at, rule_name, severity, source_process_guid, summary, amsi_matched_patterns, no_amsi_corroboration, obfuscation_score FROM alerts ORDER BY fired_at ASC')
    alerts = c.fetchall()
    f.write(f'Total Alerts in DB: {len(alerts)}\n')
    for row in alerts:
        f.write(f'ID: {row[0]} | FiredAt: {row[1]} | Rule: {row[2]} | Sev: {row[3]} | GUID: {row[4]} | Summary: {row[5]} | AMSI: {row[6]} | No_AMSI: {row[7]} | Obf: {row[8]}\n')

    f.write('\n=== RAW EVENTS DUMP (T1543/T1547 Check) ===\n')
    c.execute('SELECT id, ingested_at, event_id, image_path, command_line, target_object FROM events WHERE event_id IN (1, 12, 13, 14, 7045) ORDER BY ingested_at ASC LIMIT 100')
    events = c.fetchall()
    f.write(f'Total relevant raw events found: {len(events)}\n')
    for ev in events:
        f.write(f'Ev: {ev}\n')

conn.close()

