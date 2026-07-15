import os
import json
import sqlite3
import yaml

DB_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "edr.db"))
SIGMA_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "sigma_rules"))
DISABLED_RULES_PATH = os.path.abspath(os.path.join(os.path.dirname(__file__), "disabled_rules.json"))

def migrate_rules():
    print(f"Connecting to DB: {DB_PATH}")
    
    # Run the schema migration to ensure rules table exists if it doesn't already
    schema_path = os.path.abspath(os.path.join(os.path.dirname(__file__), "schema.sql"))
    with open(schema_path, "r", encoding="utf-8") as sf:
        schema_sql = sf.read()
        
    conn = sqlite3.connect(DB_PATH)
    conn.executescript(schema_sql)
    
    disabled_rules = []
    if os.path.exists(DISABLED_RULES_PATH):
        try:
            with open(DISABLED_RULES_PATH, "r") as f:
                disabled_rules = json.load(f)
        except Exception as e:
            print(f"Failed to read disabled_rules.json: {e}")

    inserted = 0
    updated = 0
    
    for filename in os.listdir(SIGMA_DIR):
        if not filename.endswith((".yml", ".yaml")):
            continue
            
        filepath = os.path.join(SIGMA_DIR, filename)
        try:
            with open(filepath, "r", encoding="utf-8") as f:
                content = f.read()
                docs = list(yaml.safe_load_all(content))
                if not docs or not docs[0]: continue
                
                doc = docs[0]
                rule_id = str(doc.get("id", filename))
                name = doc.get("title", filename)
                description = doc.get("description", "")
                
                tags = doc.get("tags", [])
                mitre_tech = "unknown"
                for t in tags:
                    if t.startswith("attack.t"):
                        mitre_tech = t.replace("attack.", "").upper()
                        break
                        
                severity = doc.get("level", "medium").lower()
                enabled = 0 if rule_id in disabled_rules else 1
                
                # Insert or update
                existing = conn.execute("SELECT id FROM rules WHERE id = ?", (rule_id,)).fetchone()
                if existing:
                    conn.execute("""
                        UPDATE rules SET name=?, description=?, mitre_technique=?, severity=?, yaml_content=?, enabled=? WHERE id=?
                    """, (name, description, mitre_tech, severity, content, enabled, rule_id))
                    updated += 1
                else:
                    conn.execute("""
                        INSERT INTO rules (id, name, description, mitre_technique, severity, yaml_content, enabled)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                    """, (rule_id, name, description, mitre_tech, severity, content, enabled))
                    inserted += 1
                    
        except Exception as e:
            print(f"Failed to migrate {filename}: {e}")
            
    conn.commit()
    conn.close()
    print(f"Migration complete. Inserted: {inserted}, Updated: {updated}")

if __name__ == "__main__":
    migrate_rules()
