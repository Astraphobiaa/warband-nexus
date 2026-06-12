# Project Operations Backlog — Warband Nexus

Branch: `chore/ops-deferred-wave-1` (wave 1) · prior: `chore/ops-integration` (#41)  
Source: `PROJECT-CLEANUP-AUDIT.md`, Epic ABC (#39/#40), codebase inventory (2026-06-12)  
Target: Midnight 12.0.1 (`Interface: 120005`)

### Wave 1 manual QA test plan (ops-048 / ops-050 / ops-051 — post-merge)

No in-game runner in CI. After `/reload` on Midnight 12.0.x:

1. **Load** — zero Lua errors; confirm `SharedWidgets_Pixel.lua` and `TryCounterService_Events.lua` load before dependents (TOC order).
2. **Pixel borders** — resize window / change UI scale; 1px chrome on main shell and pooled rows stays crisp (border registry refresh).
3. **Try counter** — open loot on NPC; `/wn` debug trace still registers `LOOT_*` / `ENCOUNTER_*` when debug enabled.
4. **Gear paperdoll** — swap gear on logged-in character; track-label skip-repaint path unchanged (no stale labels).
5. **Collections rows** — subtitle layout on mount/pet rows with two-line titles.
6. **Profiler** (optional) — `/wn profiler on`, switch Chars / Gear / Plans tabs; `Pop_drawTab` within prior budget.

**Priority key:** P0 = merge blocker / load failure risk · P1 = architecture or taint · P2 = hygiene or perf · P3 = polish / docs

---

## Completed

| ID | Item | Commit |
|----|------|--------|
| — | **Tier A cleanup** — P0 headers, `@param` pilot strips, narration/orphan tombstones (#39) | [`45853c5`](https://github.com/Astraphobiaa/warband-nexus/commit/45853c57579d4013295cfaa031cee8680c34669e) |
| — | **Epic ABC** — SOA gear-storage redraw, reputation scan visibility flag, debug header sync, UI banner cleanup, Kosumoth data verify (#40) | [`7bf77a7`](https://github.com/Astraphobiaa/warband-nexus/commit/7bf77a7b08f5352e1ad5b9d5ee4adeedad65fa5b) |
| — | **Integration merge** — todo backlog, OverflowMonitor removal, TooltipService SOA, Tier B batch 1 | `chore/ops-integration` |

---

## Tier B — Comment & annotation hygiene

Residual work deferred from Tier A per `PROJECT-CLEANUP-AUDIT.md`.

- [x] **ops-001** · P1 · `Modules/UI/SharedWidgets.lua` — Strip ~100 internal `---@param` blocks on Factory helpers; keep exports on `ns.UI.Factory` public methods only.
- [x] **ops-002** · P1 · `Modules/CollectionService.lua` — Strip ~64 internal `---@param` / block `@param` on materialize and scan helpers.
- [x] **ops-003** · P1 · `Modules/UI/PlanCardFactory.lua` — Strip ~46 local-helper LuaLS annotations; retain card-factory export surface.
- [x] **ops-004** · P1 · `Modules/UI/GearUI.lua` — Strip ~57 internal `---@param` on layout/chrome helpers.
- [x] **ops-005** · P1 · `Modules/PlansManager.lua` — Strip ~55 internal `---@param` on plan CRUD and vault helpers.
- [x] **ops-006** · P2 · `Modules/UI/SettingsUI.lua` — Remove residual section-banner comments in tab shell and module toggles.
- [x] **ops-007** · P2 · `Modules/UI/CharactersUI.lua` — Remove section-banner headers and stale architecture one-liners in row chrome.
- [x] **ops-008** · P2 · `Modules/UI/CurrencyUI.lua` — Trim remaining tutorial-style header blocks above expandable sections.
- [x] **ops-009** · P2 · `Modules/OverflowMonitor.lua` — **N/A:** module removed (`a0bf2d1`); no `@param` surface remains.
- [x] **ops-010** · P2 · `Modules/UI/FramePoolFactory.lua` — Strip ~26 redundant `---@param` on Acquire/Release pool helpers.
- [x] **ops-011** · P2 · `Modules/NotificationManager.lua` — Strip ~37 residual local `---@param`; keep version/changelog export annotations.
- [x] **ops-012** · P2 · `Modules/PvECacheService.lua`, `Modules/ReputationCacheService.lua` — Strip dense `---@param` clusters on cache snapshot helpers.
- [x] **ops-013** · P2 · `Modules/TryCounterService.lua`, `Modules/GearService.lua` — Document retained `WarbandNexus:` export `---@` policy in file headers (no further local strips).
- [x] **ops-014** · P3 · `Modules/**/*.lua` (grep `Helper function to`, `This ensures`) — Second-pass narration sweep on UI hot paths not touched in Tier A.

---

## SOA — Messaging & layer boundaries

Service → bus → view; no service-driven tab paint.

- [x] **ops-015** · P1 · `Modules/GearService.lua` — Audit remaining direct storage-panel repaint paths; route all through `WN_GEAR_STORAGE_REDRAW_REQUESTED` (extend #40 pattern).
- [x] **ops-016** · P1 · `Modules/CollectionService.lua` — Replace inline `PopulateContent` loop guards with narrow `WN_COLLECTION_*` or `WN_UI_MAIN_REFRESH_REQUESTED` tab payloads.
- [x] **ops-017** · P1 · `Modules/TooltipService.lua` — Decouple `WarbandNexus.UI.mainFrame` walk from tooltip safety; use visibility flag or message like reputation scan (#40).
- [x] **ops-018** · P1 · `Modules/CommandService.lua` — Route debug/header mutations through `WN_UI_DEBUG_HEADER_SYNC` instead of direct frame pokes.
- [ ] **ops-019** · P2 · `Modules/NotificationManager.lua` — Thin `RegisterMessage` handlers; move toast layout work behind `WN_SHOW_NOTIFICATION` debounce in UI layer. _deferred — separate epic_
- [x] **ops-020** · P2 · `Modules/Constants.lua` — Add `WN_MAIN_WINDOW_VISIBILITY_CHANGED` (or document `ns._wnMainWindowVisible` as canonical); replace ad-hoc visibility checks repo-wide.
- [x] **ops-021** · P2 · `Modules/Constants.lua` — Rename legacy non-`WN_` daily/weekly quest message identifiers to `WN_*` with MigrationService-free alias shim.
- [ ] **ops-022** · P2 · `Modules/UI.lua`, `Modules/UI/UI_RefreshRouter.lua` — Deduplicate overlapping `RegisterMessage` listeners that both call `SchedulePopulateContent`. _deferred — separate epic (tab modules already removed duplicate ITEMS/PLANS listeners)_
- [x] **ops-023** · P2 · `Modules/DataService.lua` — Emit granular messages (`WN_CHARACTER_UPDATED` with `charKey`) instead of broad refresh triggers from roster helpers.
- [ ] **ops-024** · P2 · `Modules/ProfessionService.lua` — Audit 20 `SendMessage` sites; coalesce profession-window bursts into `WN_PROFESSION_DATA_UPDATED` where safe. _deferred — separate epic_
- [x] **ops-025** · P3 · `Modules/**/*.lua` — Grep audit: services calling `PopulateContent`, `mainFrame`, or tab draw fns; file violations in PR notes.

**Bonus (integration):** `WN_CHARACTER_TRACKING_DIALOG_REQUESTED` — CharacterService emits; `CharacterTrackingDialog.lua` listens.

---

## Structure / Splits — File size & local-limit debt

Files >2500 lines or ~100 top-level `local` lines need `ns.*` satellite slices + TOC order updates.

### SharedWidgets factory phases

- [x] **ops-026** · P0 · `Modules/UI/SharedWidgets.lua` — **Phase 2 (pixel slice only):** `SharedWidgets_Pixel.lua` (scale, snap, border registry). _Phases 2 layout table + 3–5 still deferred — separate epic_
- [ ] **ops-027** · P0 · `Modules/UI/SharedWidgets.lua` — **Phase 3:** extract `ns.UI.Factory` method table → `SharedWidgets_Factory.lua` (buttons, scroll, section headers). _deferred — separate epic_
- [ ] **ops-028** · P1 · `Modules/UI/SharedWidgets.lua` — **Phase 4:** extract row chrome helpers still inline → extend `SharedWidgets_CharRow.lua` / new `SharedWidgets_RowPool.lua`. _deferred — separate epic_
- [ ] **ops-029** · P1 · `Modules/UI/SharedWidgets.lua` — **Phase 5:** extract search bar, collapsible header, icon helpers → dedicated satellites; entry file <120 locals. _deferred — separate epic_

### Service & domain monoliths

- [x] **ops-030** · P0 · `Modules/TryCounterService.lua` — **Partial:** event/debug/blocking tables → `TryCounterService_Events.lua`. _Encounter/loot handler split still deferred — separate epic_
- [ ] **ops-031** · P0 · `Modules/CollectionService.lua` (5510 lines) — Split bag-scan/event host → `CollectionService_Scanner.lua`; notify path already partial in `CollectionService_NotifyDedup.lua`. _deferred — separate epic_
- [ ] **ops-032** · P1 · `Modules/GearService.lua` (3905 lines) — Split storage recommendation engine → `GearService_Storage.lua` (slots/tracks already split). _deferred — separate epic_
- [ ] **ops-033** · P1 · `Modules/TooltipService.lua` (2731 lines) — Split GameTooltip hook/injection → `TooltipService_GameTooltip.lua`; keep `TooltipService.lua` as facade + `ns.TooltipService`. _deferred — separate epic_
- [ ] **ops-034** · P1 · `Modules/PlansManager.lua` (2930 lines) — Split vault/daily quest plan writers → `PlansManager_Vault.lua` and `PlansManager_Quests.lua`. _deferred — separate epic_
- [ ] **ops-035** · P1 · `Modules/NotificationManager.lua` (3245 lines) — Split changelog/what's-new UI from toast queue → `NotificationManager_Changelog.lua`. _deferred — separate epic_

### UI tab monoliths

- [ ] **ops-036** · P1 · `Modules/UI/PlansUI.lua` (4629 lines) — Split browse card grid → `PlansUI_Browse.lua`; keep thin orchestrator + `CardLayoutManager` hook. _deferred — separate epic_
- [ ] **ops-037** · P1 · `Modules/UI/PvEUI.lua` (4482 lines) — Split vault grid and character list chrome (partial rows exist) → `PvEUI_VaultGrid.lua`. _deferred — separate epic_
- [ ] **ops-038** · P1 · `Modules/UI/SettingsUI.lua` (4277 lines) — Finish shell split: move module toggles → `SettingsUI_Modules.lua` (extend `SettingsUI_Shell.lua`). _deferred — separate epic_
- [ ] **ops-039** · P1 · `Modules/UI.lua` (4163 lines) — Move refresh router-only code to `UI_RefreshRouter.lua`; target entry <2000 lines. _deferred — separate epic_
- [ ] **ops-040** · P1 · `Modules/UI/GearUI_Paperdoll.lua` (3886 lines) — Split slot button factory vs outward label paint → `GearUI_Paperdoll_Slots.lua`. _deferred — separate epic_
- [ ] **ops-041** · P2 · `Modules/UI/PlanCardFactory.lua` (3723 lines) — Split expanded-content actions vs collapsed card chrome → `PlanCardFactory_Expanded.lua`. _deferred — separate epic_

### Overflow & misc structure

- [x] **ops-042** · P2 · `Modules/OverflowMonitor.lua` — **N/A:** dead service removed; no relocation needed.
- [x] **ops-043** · P2 · `WarbandNexus.toc` — Wave-1 split batch: `SharedWidgets_Pixel`, `TryCounterService_Events` casing/order + satellite `assert` guards.

---

## Tier C — Locales & outward copy

- [ ] **ops-044** · P3 · `Locales/enUS.lua` — Spot-check player strings for unnatural phrasing; ASCII-only punctuation per `WN-LOCALES-warband-nexus.mdc`. _deferred — separate epic (human review)_
- [ ] **ops-045** · P3 · `DESCRIPTION.md` — Optional human tone pass (marketing); keep separate from code-hygiene PRs. _deferred — separate epic_
- [ ] **ops-046** · P3 · `Locales/{deDE,frFR,...}.lua` — Mirror approved enUS copy changes only after ops-044 sign-off. _deferred — separate epic_
- [ ] **ops-047** · P3 · `CHANGELOG.md` / `CHANGELOG_V*` keys — Voice review: player-facing bullets, no internal module names. _deferred — separate epic_

---

## Verification — Gates per batch

- [ ] **ops-048** · P0 · In-game — `/reload` smoke after every split or SOA PR; zero Lua load errors. _manual QA — test plan above_
- [x] **ops-049** · P1 · Locale check — **N/A wave 1** (no `Locales/` or `ns.L` key changes); `check_locales.py` not in repo root.
- [ ] **ops-050** · P1 · `/wn profiler` — Tab paint budget after layout-touching PRs. _manual QA — test plan above_
- [ ] **ops-051** · P1 · Manual QA matrix — 1080p/1440p/4K × UI scale 100–150% per tab. _manual QA — test plan above_
- [x] **ops-052** · P1 · Taint — **Wave-1 subset:** `GearUI_Paperdoll` track-label `GetText` + `trackText` guards; `SharedWidgets` collection row subtitle `GetText`. Grep audit: UI `GetText` hot paths in PlansUI/SettingsUI already guarded. _Remainder: TryCounterService/CollectionService/PlanCardFactory full pass — deferred_
- [ ] **ops-053** · P2 · `Modules/MigrationService.lua` — SV backup + migration smoke after any `db.global` schema touch.
- [ ] **ops-054** · P2 · `Modules/CollectibleSourceDB.lua` — In-game verify Kosumoth lockout quest/drop IDs (#40 wiki pass) on live toon. _deferred — manual QA_
- [ ] **ops-055** · P2 · Storage tab — Profiler evidence for incremental/staged draw if `ItemsUI`/`DrawStorageResults` refactors land (`WN-PERF-warband-nexus.mdc`). _deferred — separate epic_

---

## Reference metrics (2026-06-12)

| File | Lines | `@param` density | Notes |
|------|------:|-----------------|-------|
| `SharedWidgets.lua` | ~7820 | stripped (Factory-only policy) | Pixel → `SharedWidgets_Pixel.lua`; layout/factory phases deferred |
| `TryCounterService.lua` | ~7580 | export policy in header | Events → `TryCounterService_Events.lua`; encounter/loot split deferred |
| `CollectionService.lua` | 5510 | stripped | SOA + split deferred |
| `PlansUI.lua` | 4629 | ~3 | Split browse deferred |
| `PvEUI.lua` | 4482 | ~20 | Split vault grid deferred |
| `TooltipService.lua` | 2731 | stripped Tier A | Split hooks deferred |

**Policy decisions (open):**

1. LuaLS: keep `---@` on `ns.*` / `WarbandNexus:` exports only (recommended in audit).
2. Large-file work: prefer **split-first** PRs; batch comment hygiene only inside touched satellites.
3. `.cursor/` rules/skills: out of scope for this backlog.

---

## Suggested PR slicing

| Epic | Ops IDs | Story |
|------|---------|-------|
| SharedWidgets Phase 2 | ops-026, ops-043, ops-048 | Layout extract + TOC + reload |
| TryCounter split | ops-030, ops-052, ops-048 | Encounter slice + taint smoke |
| Tier B batch 6 | ops-001–ops-005, ops-048 | High-density `@param` strip |
| SOA pass 2 | ops-015–ops-018, ops-048 | Gear/collection/tooltip boundaries |

*Update checkbox state in this file when ops complete; link PR or commit in the ID row if helpful.*
