import sqlite3
from pathlib import Path

db_path = Path('c:/cursor/weknows/latestedr/server/pipeline/tenants/tenant_9dcb8fdc.db')
if not db_path.exists():
    print('DB file does not exist')
else:
    print(f'DB size: {db_path.stat().st_size} bytes')
    con = sqlite3.connect(str(db_path))
    try:
        tables = con.execute("SELECT name FROM sqlite_master WHERE type='table'").fetchall()
        print('Tables:', [t[0] for t in tables])
        cols = con.execute('PRAGMA table_info(events)').fetchall()
        pn_cols = [c for c in cols if c[1] == 'provider_name']
        print(f'provider_name occurrences in events table: {len(pn_cols)}')
        print('All event columns:', [c[1] for c in cols])
    except Exception as e:
        print(f'Error reading DB: {e}')
    finally:
        con.close()
