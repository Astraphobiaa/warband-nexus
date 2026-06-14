# GUID / Character Key — In-game test plan

Run with `/wn debug on` for diagnostics.

## F1 — Migration reload

1. `/reload`
2. With debug verbose, confirm migration/cleanup merged duplicate rows (if any existed).
3. `/wn charkeys` — `duplicate merge candidates` should be 0 after cleanup.

## F2 — Duplicate roster / gold display

1. Open Characters tab.
2. No duplicate names (e.g. two Superluminal rows).
3. Offline alts show saved gold, not 0 (unless never logged in).
4. Total gold = sum of all alts + warband bank.

## F3 — Alt gold persist

1. Log alt A, note gold, `/reload`.
2. Log out, log alt B.
3. Characters tab: alt A gold unchanged from step 1.

## F4 — Subsidiary remap

1. `/wn charkeys` — no orphan `currencyData`, `itemStorage`, `reputationData` keys for tracked chars.
2. Currency / Reputation / Items / PvE tabs show data for alts after GUID migration.

## F5 — Money Logs

1. Reset Money Logs if needed.
2. Deposit/withdraw — Character column shows name, not raw GUID.
3. `entry.character` in SV is canonical storage key.

## F6 — Regresyon

1. Rename character (if applicable): single roster row, same GUID.
2. `/wn cleanup` — no new duplicates.
3. Craft / open bank — no duplicate `WN_*` storms from key mismatch.
