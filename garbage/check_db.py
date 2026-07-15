
import sqlite3

conn = sqlite3.connect('c:/cursor/weknows/latestedr/server/pipeline/edr.db')
c = conn.cursor()

c.execute('SELECT rule_name, summary, amsi_matched_patterns, obfuscation_score FROM alerts ORDER BY rule_name')
for r in c.fetchall():
    print(f'[{r[0]}] {r[1]}')
    if r[2]:
        print(f'  AMSI Patterns: {r[2]}')
    if r[3]:
        print(f'  Obfuscation Score: {r[3]}')
    print('-'*50)
conn.close()

