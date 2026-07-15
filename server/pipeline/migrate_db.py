import json
import sqlite3
from pathlib import Path

DB_PATH = Path(__file__).resolve().parent / "edr.db"


def migrate():
    print(f"Migrating DB GUIDs and AMSI payloads: {DB_PATH}")
    db = sqlite3.connect(DB_PATH)

    event_cols = {row[1] for row in db.execute("PRAGMA table_info(events)").fetchall()}
    if "raw_json_original" not in event_cols:
        db.execute("ALTER TABLE events ADD COLUMN raw_json_original TEXT")
    if "raw_json_normalized" not in event_cols:
        db.execute("ALTER TABLE events ADD COLUMN raw_json_normalized TEXT")

    tables = [
        ("alerts", "source_process_guid"),
        ("process_nodes", "process_guid"),
        ("process_nodes", "parent_process_guid"),
        ("process_edges", "process_guid"),
    ]

    for table, column in tables:
        db.execute(
            f"""UPDATE "{table}"
                SET "{column}" = '{{' || "{column}" || '}}'
                WHERE "{column}" NOT LIKE '{{%'
                  AND "{column}" IS NOT NULL
                  AND "{column}" != ''"""
        )
        print(f"Migrated {table}.{column}")

    db.execute(
        """
        UPDATE events
        SET raw_json_original = COALESCE(raw_json_original, raw_json),
            raw_json_normalized = COALESCE(raw_json_normalized, raw_json)
        WHERE raw_json_original IS NULL OR raw_json_normalized IS NULL
        """
    )

    rows = db.execute(
        "SELECT id, raw_json_original, raw_json_normalized, raw_json FROM events WHERE lower(channel) = 'ishax-amsi'"
    ).fetchall()
    migrated_amsi = 0
    for row_id, raw_json_original, raw_json_normalized, raw_json in rows:
        try:
            source_json = raw_json_normalized or raw_json or raw_json_original or "{}"
            obj = json.loads(source_json)
            original_json = raw_json_original or raw_json or source_json
            edata = obj.get("data", {}).get("win", {}).get("eventdata", {})
            param1 = edata.get("param1") or edata.get("data")
            if not isinstance(param1, str):
                continue
            if '\\"' in param1:
                param1 = param1.replace('\\"', '"')
            if "\\\\" in param1:
                param1 = param1.replace("\\\\", "\\")
            if "param1" in edata:
                edata["param1"] = param1
            elif "data" in edata:
                edata["data"] = param1
            normalized_json = json.dumps(obj, separators=(",", ":"))
            db.execute(
                """
                UPDATE events
                SET raw_json_original = ?,
                    raw_json_normalized = ?,
                    raw_json = ?
                WHERE id = ?
                """,
                (original_json, normalized_json, normalized_json, row_id),
            )
            migrated_amsi += 1
        except Exception as exc:
            print(f"Error migrating row {row_id}: {exc}")

    print(f"Migrated {migrated_amsi} AMSI event payloads.")
    db.commit()
    db.close()
    print("Migration complete.")


if __name__ == "__main__":
    migrate()
