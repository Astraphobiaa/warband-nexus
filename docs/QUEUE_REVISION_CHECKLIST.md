# Coroutine & Queue Revision — Closure Checklist

Use this after changes to scheduling, scans, or heavy UI paths.

## Midnight safety (taint / secret values)

- [ ] No string ops (`:find`, `:match`, `:lower`, `..`) on API returns without `issecretvalue` guard (tooltips, `GetLootSourceInfo`, `UnitGUID`, chat loot, `GetStatistic`, etc.).
- [ ] No `tonumber` / `not value` on possibly secret values without guarding.
- [ ] UI that touches secure state: defer with `PLAYER_REGEN_ENABLED` if needed; no bar/frame attribute edits in combat.

## Event & timer lifecycle

- [ ] `C_Timer` / `NewTicker` cancelled on disable, tab hide, or superseded work (guild bank: `InvalidateGuildBankScan`).
- [ ] Coalesced deferred work (`ScheduleEnsureCollectionDataDeferred`, `SchedulePopulateContent`) does not leak duplicate callbacks after hide.

## Services

- [ ] `EnsureCollectionData` / `ScanCollection` / achievement scan: loading flags cleared on error, timeout, or abort.
- [ ] Guild bank scan: invalidates on close; no finalize after `guildBankIsOpen == false`.
- [ ] Bank open scan (`RunBudgetedBankOpenScan`): `bankScanInProgress` cleared if bank closes mid-pipeline.

## UI smoke (manual)

- [ ] Main window: tab switch (chars, plans, collections, currency, reps) — no stuck loading overlays.
- [ ] Open guild bank — scan completes; close mid-scan — no Lua error; next open still works.
- [ ] Open character bank — items refresh without long freeze.
- [ ] Plans tab with many active plans — acceptable frame time (column precompute avoids O(n²) layout).

## Lint

- [ ] No new issues in edited Lua files (IDE diagnostics).

## Internal messages (`Constants.EVENTS`)

- [ ] New `SendMessage` calls use `Constants.EVENTS.*` (or module-local `E.*`), not raw `"WN_*"` strings.
- [ ] Spot-check: `ReputationCacheService`, `ModuleManager`, `EventManager`, `CharacterService` message names match `Constants.lua`.

## Performance notes (revision targets)

| Area | Before | After |
|------|--------|--------|
| Main UI event burst | Multiple `PopulateContent` per loot tick | `SchedulePopulateContent` debounce + optional cooldown skip |
| Currency/rep badges | Full populate on some updates | `UpdateTabCountBadges("currency" \| "reputations")` when tab not focused |
| Tab switch | Nested `C_Timer` chains | Single `C_Timer.After(0)` + pre-clear scroll |
| `EnsureCollectionData` burst | Many deferred calls | `ScheduleEnsureCollectionDataDeferred` coalesces to one frame |
| `ScanCollection` coroutine | `NewTicker(0.1)` | `FRAME_BUDGET_MS` resume loop |
| Guild bank scan | One frame for all slots | `FRAME_BUDGET_MS` chunks + invalidate on close |
| Bank open scan | Large sync block | `RunBudgetedBankOpenScan` one bag per frame |
| Plans My Plans grid | O(n²) column loop | O(n) `regularCountBefore` |
| Collections mounts/pets/toys | — | Existing `RunChunked*` + abort via `AbortCollectionsChunkedBuilds` on tab leave |
