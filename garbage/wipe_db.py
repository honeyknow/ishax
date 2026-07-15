import sqlite3
c = sqlite3.connect('server/pipeline/edr.db')
tables = c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'").fetchall()
for t in tables:
    table = t[0]
    print(f"Clearing table {table}...")
    c.execute(f"DELETE FROM {table}")
c.commit()
c.close()
print("Database cleared!")
