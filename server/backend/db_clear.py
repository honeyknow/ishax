from pathlib import Path
import sqlite3

DB_PATH = Path(__file__).resolve().parents[1] / "pipeline" / "edr.db"

conn = sqlite3.connect(DB_PATH)
c = conn.cursor()

c.execute("SELECT name FROM sqlite_master WHERE type='table';")
tables = [r[0] for r in c.fetchall()]
print("DB:", DB_PATH)
print("Tables in DB:", tables)

preserved = ("endpoints", "sqlite_sequence", "migrations", "schema_migrations", "agents")
tables_to_clear = [t for t in tables if t not in preserved]

for table_name in tables_to_clear:
    c.execute(f'DELETE FROM "{table_name}"')
    print(f"Cleared table: {table_name}")

conn.commit()
conn.close()
print("DB cleared; endpoint/agent metadata preserved where those tables exist.")
