import sqlite3, time, glob, os

dbs = glob.glob(r'C:\cursor\weknows\latestedr\server\pipeline\tenants\tenant_*.db')

for db_path in dbs:
    print('Injecting into:', db_path)
    
    tenant_conn = sqlite3.connect(db_path)
    now = int(time.time())
    
    alerts = [
        (now - 120, 'T1059.001', 'Suspicious PowerShell Execution', 'high', 'PowerShell executed with -EncodedCommand flag', 'host-alpha'),
        (now - 3600, 'T1078', 'Valid Accounts: Local Accounts', 'medium', 'Multiple failed login attempts from unknown IP', 'host-beta'),
        (now - 86400, 'T1562.001', 'Disable or Modify Tools', 'critical', 'Windows Defender Real-time monitoring disabled', 'host-gamma'),
    ]
    
    for a in alerts:
        tenant_conn.execute('''
            INSERT INTO alerts (fired_at, rule_id, mitre_technique, rule_name, severity, summary, source_agent_name)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (a[0], 'rule-' + str(now), a[1], a[2], a[3], a[4], a[5]))
        
    tenant_conn.commit()
    tenant_conn.close()
    print('Inserted 3 test alerts!')
