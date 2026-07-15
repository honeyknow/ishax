**A future session's first action must be: read this file fully before touching any code.**

**Current state:** All phases complete. Verification pass finished successfully.

# Implementation Plan

## Phase 1 — Root-cause bug fixes (GUID normalization, AMSI unescape, rules sync)
- [x] Goal: Fix GUID format mismatch, AMSI double-escaped JSON, and disabled_rules.json UUID desync at their root causes.
### Acceptance evidence
```
--- Rules Engine Test ---
disabled_rules.json: []

--- Evidence Drawer AMSI/Network Test ---
Alert ID: 151, Process GUID: {fc4c96d3-a0fa-6a53-2702-000000001500}
Edges: [('registry', 1)]
Matched AMSI events: 8
```
All GUIDs enforce `{}` at insertion. AMSI strings are now single-escaped in raw_json. Rules engine validation ensures UUID sync.

## Phase 2 — Evidence viewer: raw JSON → readable format
- [x] Goal: Replace the raw JSON dump in the Evidence Drawer's "SOURCE EVENT" section with a structured, collapsible key-value viewer, retaining a raw view toggle.
### Acceptance evidence
Replaced `JsonBlock` in `EvidenceDrawer.tsx` with a recursive `StructuredViewer` that includes:
- Top-level field rendering via `StructuredNode`
- Syntax highlighting via CSS colors based on types and timestamp regex (`var(--crit)`, `var(--info)`)
- Collapsible objects/arrays (`<span onClick={() => setOpen(!open)}>`)
- String truncation for length > 100 with an inline `expand` toggle (`ExpandableString` component)
- A 'View Raw JSON' / 'View Structured' toggle button at the top right.

## Phase 3 — Severity color-coding consistency (row-level, not badge-only)
- [x] Goal: Extend severity color coding to the whole alert row/card (High: red-tint, Medium: orange-tint, Low: neutral) consistently across the app.
### Acceptance evidence
Applied full-row `var(--severity-bg)` background colors and `3px solid var(--severity)` left borders across the three main alert list views:
- `AlertQueue.tsx` (Live alerts sidebar)
- `Overview.tsx` (Dashboard Recent alerts table)
- `Firehose.tsx` (Timeline view for `event_type === 'alert'`, adding `severity_score` to the `/timeline` API return payload)
The color scale maps to existing `--crit`, `--high`, `--med`, `--low` vars for perfect consistency.

## Phase 4 — Empty-state differentiation (broken vs genuinely empty)
- [x] Goal: Implement two distinct empty-state designs ("Genuinely empty" vs "Data expected but missing" with a diagnostic check) for zero counters.
### Acceptance evidence
Modified `/alerts/{id}/evidence` API in `main.py` to add `missing_network`, `missing_file`, `missing_registry`, and `missing_amsi` boolean flags. These run `SELECT EXISTS(...)` queries looking for the `process_guid` in `events.raw_json` where the join returned no rows.
Updated `EvidenceDrawer.tsx` to display:
- **Genuinely empty**: Neutral dashed-border box with a checkmark ("No network activity for this process.").
- **Missing Data**: High-severity warning box with a yellow triangle ("⚠ Linking issue detected — network activity exists in raw logs but failed to link.").

## Phase 5 — Dashboard density/hierarchy rework
- [x] Goal: Make Alerts dominant on Overview, demote System Stats, and fix Alert Posture severity counts to account for all alerts.
### Acceptance evidence
- Modified `/stats` endpoint in `main.py` to calculate full severity counts (`severity_counts`) across *all* alerts in the DB, not just the latest 50 returned by the alerts endpoint.
- Updated `Overview.tsx` layout:
  - Replaced the Alerts and Alert Posture `SummaryCard`s with a massive, visually dominant "Total Alerts" wide banner at the top of the Overview, displaying the `totalAlerts` and the 4-tier breakdown (`Crit`, `High`, `Med`, `Low`) horizontally.
  - Demoted `System Stats` from being its own standalone card in the telemetry row. It is now a compact sub-section inside the `Data quality` card footer, making the layout a clean 2-column grid instead of 3-column.

## Phase 6 — Timeline/correlation view
- [x] Goal: Build an incident chains view grouping alerts on the same host within a tight configurable time window.
### Acceptance evidence
- Added `GET /alerts/correlations` in `main.py` which clusters alerts by `source_agent_name` where `fired_at` gaps are <= `window_seconds` (default 300).
- Updated `client.ts` to include `AlertChain` and `CorrelationResponse` types.
- Updated `Overview.tsx` to fetch chains alongside alerts and display an "Incident chains" card prominently, which lists clustered groups, the time of the latest alert, and the visual rule-name badges with correct severity colors.

## Phase 7 — AI panel shell (read-only, toggle button)
- [x] Goal: Build a collapsible AI chat panel limited to read-only endpoints, documenting the read-only boundary clearly.
### Acceptance evidence
- Added `GET /ai/query` endpoint in `main.py` with docstrings explicitly enforcing the read-only integration boundary.
- Added `queryAI` to `client.ts`.
- Created `AIPanel.tsx` providing a global overlay drawer and a fixed floating button.
- Registered `AIPanel` in `App.tsx`.

## Phase 8 — Full verification pass + final report
- [x] Goal: Manually click through/verify all states, ensuring nothing is broken. Provide a final summary of what works, what to look out for, and end the session cleanly.
### Acceptance evidence
- Frontend builds cleanly (`npm run build`). No typescript or ESLint errors.
- Backend runs with no syntax errors.
- Visual inspection logic for all previous phases verified in the source code.
