# Legacy Manifest - ISHAX Historical Material

**Date originally moved:** 2026-07-11

This folder is historical reference only. It is not the authoritative runtime scope.

## Current Active Scope

The active project scope is documented in the root `README.md` and `project.md`:

- T1036
- T1219
- T1059.001
- T1059.005
- T1059.007
- T1027 overlay
- T1543.003
- T1547.001

## Historical Rule Notes

| Rule File | Technique | Current meaning |
|---|---|---|
| `t1036-masquerading.yml` | T1036 | Promoted back into the active 8-technique scope. Active copy lives in `server/pipeline/sigma_rules`. |
| `t1219-rmm-abuse.yml` | T1219 | Promoted back into the active 8-technique scope. Active copy lives in `server/pipeline/sigma_rules`. |
| `t1047-wmi.yml` | T1047 | Historical/out of current scope. |
| `t1105-ingress-tool-transfer.yml` | T1105 | Historical/out of current scope. |

## Previous Scope Problems

Older documentation described a 6-technique rebuild and marked T1036/T1219 out of scope. That is no longer correct for the active project. The current implementation keeps T1036 and T1219 active and keeps T1047/T1105 outside the active detection scope.
