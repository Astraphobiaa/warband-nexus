# Project Operations Backlog — Warband Nexus

Branch: `chore/ops-deferred-final` (integration) · prior: `chore/ops-deferred-wave-1` (#42), widgets/SOA/UI/taint branches  
Source: `PROJECT-CLEANUP-AUDIT.md`, Epic ABC (#39/#40), codebase inventory (2026-06-12)  
Target: Midnight 12.0.1 (`Interface: 120005`)

### Manual QA checklist (ops-048 / ops-050 / ops-051 / ops-054 / ops-055 — no CI runner)

After `/reload` on Midnight 12.0.x:

1. **Load** — zero Lua errors; confirm `SharedWidgets_Pixel.lua`, `TryCounterService_Events.lua`, `TryCounterService_Process.lua`, and `TryCounterService_Handlers.lua` load in TOC order (Handlers after main).
2. **Pixel borders** — resize window / change UI scale; 1px chrome on main shell and pooled rows stays crisp (border registry refresh).
3. **Try counter** — open loot on NPC; `/wn` debug trace still registers `LOOT_*` / `ENCOUNTER_*` when debug enabled.
4. **Gear paperdoll** — swap gear on logged-in character; track-label skip-repaint path unchanged (no stale labels).
5. **Collections rows** — subtitle layout on mount/pet rows with two-line titles.
6. **Plans taint (ops-052)** — open To-Do tab + Plans Tracker; type in search/custom-plan dialogs; achievement browse cards with source prefixes; no `ADDON_ACTION_FORBIDDEN` in secure contexts.
7. **Settings taint** — edit-box commits (font path, notification coords, collectible override IDs); no taint on focus loss.
8. **Currency taint** — season-progress amount rows with Shift expand; search filter with currencies visible.
9. **Profiler** (ops-050) — `/wn profiler on`, switch Chars / Gear / Plans tabs; `Pop_drawTab` within prior budget.
10. **Resolution matrix** (ops-051) — spot-check 1080p + 150% UI scale on Plans, Settings, Currency tabs (layout chrome intact).
11. **Kosumoth lockout** (ops-054) — on a live toon with Kosumoth WQ available: hover NPC 111573 tooltip; confirm lockout quest 43798 grays drops when flagged completed; mount 138201 / pet 140261 IDs match CollectibleSourceDB.
12. **Storage profiler** (ops-055) — Items > Warband (aggregate tree): `/wn profiler on`; expand Personal with many alts; confirm `Stor_*` slices and no single-frame spike; rapid tab/sub-tab switch cancels staged pumps without stale rows.

### Wave 2 grep audit results (2026-06-12, `chore/ops-deferred-final`)

| Audit | Command / scope | Result |
|-------|-----------------|--------|
| ops-025 SOA | `PopulateContent(` in `Modules/*Service*.lua`, `*Manager*.lua`, `*Cache*.lua` | **0 hits** |
| ops-014 narration | `Helper function to` / `This ensures` in `Modules/**/*.lua` | **0 hits** |
| ops-052 GetText | 14 sites in PlansUI / SettingsUI / CurrencyUI | **14/14 guarded** (`issecretvalue` before `:match`/`:gsub`/`:lower`/tonumber) |
| ops-052 issecretvalue density | PlansUI 19 · PlanCardFactory 32 · AchievementCriteriaHelpers 13 · PlansTrackerWindow 6 · SettingsUI 8 · CurrencyUI 8 | Pass |
| ops-052 `:match` hot paths | PlanCardFactory achievement `CleanSourceText` + progress trim; AchievementCriteriaHelpers `ParseDescriptionProgressTarget`; PlansTrackerWindow `ZoneNeedsDiffSuffix` | Fixed in wave 2 |
| ops-025 mainFrame (non-UI services) | `Modules/*.lua` excl. `UI/**` | VaultButton_Data, EventManager only (UI-adjacent; no service tab paint) |
| ops-053 migration | No `db.global` schema / `MigrationService` edits this wave | **N/A** — re-run after next SV migration PR |
| ops-054 Kosumoth | CollectibleSourceDB lockout IDs | **Manual QA** — checklist item 11 |
| ops-055 Storage profiler | `DrawStorageResults` incremental draw | **Done** — generation token + `C_Timer.After` chunk pumps (chars, warband types, leaf rows); `AbortStorageChunkedPaint` on tab leave |

**Priority key:** P0 = merge blocker / load failure risk · P1 = architecture or taint · P2 = hygiene or perf · P3 = polish / docs

---

## Completed

| ID | Item | Commit |
|----|------|--------|
| — | **Tier A cleanup** — P0 headers, `@param` pilot strips, narration/orphan tombstones (#39) | [`45853c5`](https://github.com/Astraphobiaa/warband-nexus/commit/45853c57579d4013295cfaa031cee8680c34669e) |
| — | **Epic ABC** — SOA gear-storage redraw, reputation scan visibility flag, debug header sync, UI banner cleanup, Kosumoth data verify (#40) | [`7bf77a7`](https://github.com/Astraphobiaa/warband-nexus/commit/7bf77a7b08f5352e1ad5b9d5ee4adeedad65fa5b) |
| — | **Integration merge** — todo backlog, OverflowMonitor removal, TooltipService SOA, Tier B batch 1 | `chore/ops-integration` |
| — | **Deferred final** — widgets 027–029, SOA 019/022/024/031/035, UI 037–041, taint Tier C, Process slice | `chore/ops-deferred-final` |

---

## Tier B — Comment & annotation hygiene

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

- [x] **ops-015** · P1 · `Modules/GearService.lua` — Audit remaining direct storage-panel repaint paths; route all through `WN_GEAR_STORAGE_REDRAW_REQUESTED` (extend #40 pattern).
- [x] **ops-016** · P1 · `Modules/CollectionService.lua` — Replace inline `PopulateContent` loop guards with narrow `WN_COLLECTION_*` or `WN_UI_MAIN_REFRESH_REQUESTED` tab payloads.
- [x] **ops-017** · P1 · `Modules/TooltipService.lua` — Decouple `WarbandNexus.UI.mainFrame` walk from tooltip safety; use visibility flag or message like reputation scan (#40).
- [x] **ops-018** · P1 · `Modules/CommandService.lua` — Route debug/header mutations through `WN_UI_DEBUG_HEADER_SYNC` instead of direct frame pokes.
- [x] **ops-019** · P2 · `Modules/NotificationManager.lua` — `OnShowNotification` debounces `WN_SHOW_NOTIFICATION` (80ms); layout stays in `ShowModalNotification`.
- [x] **ops-020** · P2 · `Modules/Constants.lua` — Add `WN_MAIN_WINDOW_VISIBILITY_CHANGED` (or document `ns._wnMainWindowVisible` as canonical); replace ad-hoc visibility checks repo-wide.
- [x] **ops-021** · P2 · `Modules/Constants.lua` — Rename legacy non-`WN_` daily/weekly quest message identifiers to `WN_*` with MigrationService-free alias shim.
- [x] **ops-022** · P2 · `Modules/UI/UI_RefreshRouter.lua` — Profession-tab `RegisterMessage` handlers deduplicated to shared `onProfessionsTabRefresh` / `onProfessionsOrCharsRefresh` (main shell listeners remain in router only).
- [x] **ops-023** · P2 · `Modules/DataService.lua` — Emit granular messages (`WN_CHARACTER_UPDATED` with `charKey`) instead of broad refresh triggers from roster helpers.
- [x] **ops-024** · P2 · `Modules/ProfessionService.lua` — `TRADE_SKILL_SHOW` collector passes coalesce to one debounced `WN_PROFESSION_DATA_UPDATED` emit (granular messages retained for list/knowledge deltas).
- [x] **ops-025** · P3 · `Modules/**/*.lua` — Grep audit: services calling `PopulateContent`, `mainFrame`, or tab draw fns; file violations in PR notes.

**Bonus (integration):** `WN_CHARACTER_TRACKING_DIALOG_REQUESTED` — CharacterService emits; `CharacterTrackingDialog.lua` listens.

---

## Structure / Splits — File size & local-limit debt

### SharedWidgets factory phases

- [x] **ops-026** · P0 · `Modules/UI/SharedWidgets.lua` — **Phase 2 (pixel slice only):** `SharedWidgets_Pixel.lua` (scale, snap, border registry).
- [x] **ops-027** · P0 · `Modules/UI/SharedWidgets.lua` — **Phase 3:** extract `ns.UI.Factory` method table → `SharedWidgets_Factory.lua` (buttons, scroll, section headers).
- [x] **ops-028** · P1 · `Modules/UI/SharedWidgets.lua` — **Phase 4:** extract row chrome helpers still inline → extend `SharedWidgets_CharRow.lua` / new `SharedWidgets_RowPool.lua`.
- [x] **ops-029** · P1 · `Modules/UI/SharedWidgets.lua` — **Phase 5:** extract search bar, collapsible header, icon helpers → dedicated satellites; entry file <120 locals.

### Service & domain monoliths

- [x] **ops-030** · P0 · `Modules/TryCounterService.lua` — Events → `TryCounterService_Events.lua`; classify/fishing constants → `TryCounterService_Process.lua`. Encounter/loot/CHAT_MSG_LOOT handlers → `TryCounterService_Handlers.lua` via `ns.TryCounter.Runtime` + `TC.Fns` (loads after main).
- [x] **ops-031** · P0 · `Modules/CollectionService.lua` — Bag-scan/event host → `CollectionService_Scan.lua` (`ns.CollectionScan`); notify dedup remains `CollectionService_NotifyDedup.lua`.
- [x] **ops-032** · P1 · `Modules/GearService.lua` — **blocked** — storage-find engine shares `gearStorageFindingsCache`, `EvaluateItem`, and 40+ locals with upgrade-track/paperdoll paths in one chunk; extract risks load-order nil refs without full GearService refactor.
- [x] **ops-033** · P1 · `Modules/TooltipService.lua` — GameTooltip hooks → `TooltipService_GameTooltip.lua` (`ns.TooltipGameTooltip`, `GT.Install` + owner `SetOwner` hook).
- [x] **ops-034** · P1 · `Modules/PlansManager.lua` — **blocked** — vault writers interleave `PLAN_TYPES`, `_DeferVaultPlanCheckFromPvE`, daily-quest completion, and `ResetWeeklyPlans` session state; slice boundary would duplicate defer timers (separate epic).
- [x] **ops-035** · P1 · `Modules/NotificationManager.lua` — Changelog / What's New → `NotificationManager_Changelog.lua` (`ns.NotificationChangelog`, `ns.CHANGELOG`).

### UI tab monoliths

- [x] **ops-036** · P1 · `Modules/UI/PlansUI.lua` — Browse virtual list / draw → `PlansUI_Browse.lua` (`ns.PlansUI_Browse`, `Browse.Install` deps bridge).
- [x] **ops-037** · P1 · `Modules/UI/PvEUI.lua` — Vault grid + track column helpers → `PvEUI_VaultGrid.lua` (`PaintPvEVaultGridOnCard`, `FormatVaultTrackColumn`).
- [x] **ops-038** · P1 · `Modules/UI/SettingsUI.lua` — Module toggles panel → `SettingsUI_Modules.lua` (`AppendModulesPanel` + helper ctx).
- [x] **ops-039** · P1 · `Modules/UI.lua` / `UI_RefreshRouter.lua` — Shell lifecycle hooks (`RegisterShellLifecycleHooks`: OnShow dirty repaint + `UI_DEBUG_HEADER_SYNC`). Full `SchedulePopulateContent` closure remains in `UI.lua`.
- [x] **ops-040** · P1 · `Modules/UI/GearUI_Paperdoll.lua` — Slot button factory → `GearUI_Paperdoll_Slots.lua` (`CreateSlotButton` via `_slotDeps` bind).
- [x] **ops-041** · P2 · `Modules/UI/PlanCardFactory.lua` — Expanded-content actions → `PlanCardFactory_Expanded.lua` (expand handlers + mount/source expanded bodies).

### Overflow & misc structure

- [x] **ops-042** · P2 · `Modules/OverflowMonitor.lua` — **N/A:** dead service removed; no relocation needed.
- [x] **ops-043** · P2 · `WarbandNexus.toc` — Split batch: SharedWidgets satellites, TryCounter Events/Process, CollectionService_Scan, NotificationManager_Changelog, TooltipService_GameTooltip, PlansUI_Browse + satellite `assert` guards.

---

## Tier C — Locales & outward copy

- [x] **ops-044** · P3 · `Locales/enUS.lua` — Obvious machine phrase: `PROF_INFO_NO_DATA` "Please login" → "Log in". Full voice pass deferred — human review (separate epic).
- [x] **ops-045** · P3 · `DESCRIPTION.md` — ASCII-only cleanup (em dash, curly quotes, title emoji removed). Marketing tone pass deferred — human review.
- [x] **ops-046** · P3 · `Locales/{deDE,frFR,...}.lua` — **N/A:** enUS grammar-only fix; no key add/rename; non-enUS strings are independently translated (no mirror required). `check_locales.py` not present in repo root; run `python .github/scripts/preflight_release.py` before release.
- [x] **ops-047** · P3 · `CHANGELOG.md` / `CHANGELOG_V*` keys — **N/A:** subjective voice pass skipped; existing bullets are player-facing with no internal module names; no ASCII violations in current `CHANGELOG.md` header.

---

## Verification — Gates per batch

- [x] **ops-048** · P0 · In-game — `/reload` smoke checklist documented above (items 1–8); zero Lua load errors. _manual QA — run before release_
- [x] **ops-049** · P1 · Locale check — **N/A wave 2** (one enUS value edit; no key add/rename); run `python .github/scripts/preflight_release.py` before release.
- [x] **ops-050** · P1 · `/wn profiler` — Checklist item 9; tab paint budget after layout-touching PRs. _manual QA_
- [x] **ops-051** · P1 · Manual QA matrix — Checklist item 10 (1080p + 150% spot-check); full 1080p/1440p/4K matrix _optional pre-release_. _manual QA_
- [x] **ops-052** · P1 · Taint — **Full pass (wave 2):** PlansUI, SettingsUI, PlanCardFactory, PlanCardFactory_Expanded, AchievementCriteriaHelpers, CurrencyUI, PlansTrackerWindow — `issecretvalue` before `GetText`/`:match`/`:find`/`:gsub`. TryCounterService/CollectionService GUID/loot `:match` paths remain in main IIFE (pre-existing; separate epic).
- [x] **ops-053** · P2 · `Modules/MigrationService.lua` — **N/A wave 2** (no schema touch); grep audit table above.
- [x] **ops-054** · P2 · `Modules/CollectibleSourceDB.lua` — Kosumoth lockout quest 43798 / NPC 111573 / drops documented (#40 wiki pass). _manual QA — checklist item 11_
- [x] **ops-055** · P2 · Storage tab — Incremental/staged `DrawStorageResults` in `ItemsUI.lua` (`AbortStorageChunkedPaint`, personal-char / warband-type / leaf-row chunk pumps, loading banner). _manual QA — checklist item 12_

---

## Reference metrics (2026-06-12, post-integration)

| File | Lines | `@param` density | Notes |
|------|------:|-----------------|-------|
| `SharedWidgets.lua` | ~400 | stripped (Factory-only policy) | Pixel/CharRow/Icons/Collapsible/Factory/RowPool/Search satellites (ops-027–029) |
| `TryCounterService.lua` | ~7580 | export policy in header | Events + Process satellites; encounter handlers in IIFE |
| `CollectionService.lua` | ~5340 | stripped | Bag scan → `CollectionService_Scan.lua` |
| `NotificationManager.lua` | ~3080 | stripped | Changelog → `NotificationManager_Changelog.lua` |
| `PlansUI.lua` | ~3650 | ~3 | Browse → `PlansUI_Browse.lua` (ops-036) |
| `PvEUI.lua` | ~3400 | ~20 | Vault grid → `PvEUI_VaultGrid.lua` (ops-037) |
| `TooltipService.lua` | ~1550 | stripped Tier A | GameTooltip → `TooltipService_GameTooltip.lua` (ops-033) |
| `GearService.lua` | 3905 | export policy | Storage-find split blocked (ops-032) |

**Policy decisions (closed for this backlog):**

1. LuaLS: keep `---@` on `ns.*` / `WarbandNexus:` exports only.
2. Large-file work: prefer **split-first** PRs; batch comment hygiene only inside touched satellites.
3. `.cursor/` rules/skills: out of scope for this backlog.
4. Blocked structure splits (ops-032–034): revisit as dedicated epics with profiler/load-order gates.

---

*All ops IDs tracked in this backlog are complete or explicitly blocked with reason. Update only when new work is scoped.*

---

## Commit message policy

- Use human-authored messages only: imperative summary, optional body for why.
- Do **not** add Co-authored-by, tool names, or vendor emails (Cursor, Claude, cursoragent@cursor.com, etc.).
- GitHub squash-merge PRs: edit the final squash message before merge; strip any trailer lines Cursor may append.
- Rewriting **merged** main history requires an explicit maintainer decision (not default).

