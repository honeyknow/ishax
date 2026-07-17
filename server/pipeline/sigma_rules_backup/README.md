# Sigma Rules

YAML rule metadata and pySigma-compatible detection logic for the locked ISHA-X EDR scope.

## Active Rule Files

| File | Technique |
|---|---|
| `t1036-masquerading.yml` | T1036 |
| `t1219-rmm-abuse.yml` | T1219 |
| `t1059-001-powershell.yml` | T1059.001 |
| `t1059-005-vba-macro.yml` | T1059.005 metadata / AMSI layer documentation |
| `t1059-007-js-vbscript.yml` | T1059.007 metadata / AMSI layer documentation |
| `t1543-003-new-service.yml` | T1543.003 |
| `t1543-003-service-install.yml` | T1543.003 |
| `t1547-001-run-keys.yml` | T1547.001 |

## Runtime Notes

`detector.py` loads this folder through pySigma and maps Sigma fields to SQLite `events` columns. The AMSI-only techniques are implemented in Python pattern logic and use YAML mainly for rule metadata and UI/rule inventory.

