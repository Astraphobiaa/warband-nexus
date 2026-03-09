# Midnight 12.0 Validation & Regression Test Matrix

Manual test scenarios and slash-command checks for Midnight compatibility and post-refactor regression.

## Slash / in-game checks

| Check | Command / action | Expected |
|-------|------------------|----------|
| Tooltip diagnostics | `/wn validate tooltip` (or equivalent) | All checks pass; "issecretvalue API" and "ENCOUNTER_END feed" reported. |
| Try counter loot debug | Enable in Settings → Advanced → Try Counter Loot Debug, kill a boss in instance | Chat log shows ENCOUNTER_END / source resolution without errors. |
| API report | `/wn apireport` | No critical missing APIs. |
| Errors | `/wn errors` | No new errors after changes. |

## Midnight secret-value / taint scenarios

| Scenario | Steps | Expected (no ADDON_ACTION_FORBIDDEN) |
|----------|--------|--------------------------------------|
| Instanced boss kill | Enter dungeon/raid, kill a boss that drops a tracked collectible | Try counter updates; tooltip on same boss (or name fallback) shows drop info after first kill. |
| Loot window (instance) | Open loot from boss; optional: empty loot (only currency/rep) | No taint; try count or delayed fallback applies. |
| Unit tooltip in instance | Hover over boss (before/after kill) | Tooltip injects collectible lines when name/encounter cache is populated. |
| Collection tab (mount/pet/toy) | Open Collections, switch Mounts/Pets/Toys, select items | SafeGetMountInfoExtra / SafeGetPetInfoExtra used; no secret value errors. |
| Settings dropdowns | Open Settings, open any dropdown (e.g. font, module) | Menu uses Factory container/buttons; no taint. |

## UI / refactor regression

| Area | Steps | Expected |
|------|--------|----------|
| Settings window | `/wn config`; resize; open/close | Frame uses Factory; no duplicate frames; layout correct. |
| Settings – Track Item DB | Expand Track section; select an item; add custom item ID | Detail card and EditBox work; lookup responds. |
| Settings – notification position | Set position (green/blue ghosts); right-click to save | Ghosts use Factory container; position saves. |
| Collections – empty detail | Open Collections, Mounts; do not select an item | "Select a mount to see details" overlay (Factory container). |
| Collections – model viewer | Select a mount; drag to rotate model | Model rotation OnUpdate works; no errors. |

## Combat lockdown

| Scenario | Steps | Expected |
|----------|--------|----------|
| Open Settings in combat | Enter combat; run `/wn config` | Message: cannot open during combat; no taint. |
| Open main window in combat | Enter combat; run `/wn` | Same or allowed (per addon design). |

## Quick smoke sequence

1. `/reload`
2. `/wn` → main window opens
3. `/wn config` → settings open; close
4. Collections tab → Mounts → select one mount → check detail panel and model
5. If in 12.0 instance: kill a boss with try counter enabled; check tooltip on boss name
6. `/wn errors` → zero or unchanged count
