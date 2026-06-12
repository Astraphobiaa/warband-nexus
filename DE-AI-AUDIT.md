# De-AI Audit — Warband Nexus

Branch: `chore/de-ai-fixes`  
Started: 2026-06-12

## Scope

| Area | Files | De-AI priority | Notes |
|------|------:|----------------|-------|
| `Modules/**/*.lua` | 138 | **P0** | Primary addon logic; mixed native + AI-era headers |
| `Core.lua`, `Config.lua` | 2 | P1 | Large config surface; some tutorial comments |
| `Locales/*.lua` | 12 | P2 | Player copy; check marketing tone vs enUS ASCII rules |
| `libs/**` | 47 | **Exclude** | Third-party Ace3/Lib* — do not rewrite |
| `.cursor/rules`, `.cursor/skills` | 46 | **Exclude** | Agent tooling; intentional prescriptive prose |
| `scripts/**` | 42 | P3 | Python tooling; lower player impact |
| `DESCRIPTION.md`, `CHANGELOG.md` | 2 | P3 | Marketing/docs; human-edited, not code smell |
| `Media/**` | 30 | Exclude | Assets only |

**Addon-owned Lua total:** 151 files (~200 with libs).

## AI artifact categories

### A — Verbose / inaccurate file headers (P0)

Tutorial-style blocks: `Features:`, `Architecture:`, `Key Features:`, semver essays, or claims not backed by code.

**Fixed (chore/de-ai-fixes P0 headers):** `CollectionRules.lua`, `Constants.lua`, `EventManager.lua`, `PvECacheService.lua`, `APIWrapper.lua`, `MinimapButton.lua`, `ItemsCacheService.lua`, `ReputationCacheService.lua`, `TooltipService.lua`, `DatabaseOptimizer.lua`, `ErrorHandler.lua`, `TransmogManager.lua`, `SearchResultsRenderer.lua`, `SearchStateManager.lua`, `CurrencyCacheService.lua`, `ChatMessageService.lua`, `DebugService.lua`, `ReputationScanner.lua`, `ReputationProcessor.lua`, `GoldManagementPopup.lua`

**Remaining (sample):**

- `Modules/UI/SearchBoxComponent.lua` — long UX spec in header (partially useful; trim not delete)
- `Modules/UI/SharedWidgets.lua` — Factory Phase 1 migration essay (~line 1536)

### B — `@param` / block JavaDoc on obvious functions (P0)

`--[[ @param ... @return ... ]]` blocks before local helpers. Native style uses short line comments or `---@` only where IDE value is high.

**Fixed in pass 1:** `CollectionRules.lua` (27 blocks), `APIWrapper.lua` (3), `EventManager.lua` (9)

**High density (grep `@param` count):**

- `TryCounterService.lua`, `GearService.lua`, `GearUI_Paperdoll.lua` (100+ each)
- `ItemsCacheService.lua`, `NotificationManager.lua`, `TooltipService.lua`, `CurrencyCacheService.lua`
- `PlanCardFactory.lua`, `DataService.lua`, `Utilities.lua`

### C — `---@` LuaLS annotations (P1)

~70 module files use `---@param` / `---@return`. Not always AI — but often redundant on private locals. Policy: keep on exported `ns.*` / `WarbandNexus:` APIs; strip on internal helpers in hot files.

### D — Section banner comments (P2)

`-- ===== STANDALONE LOADING OVERLAY =====`, `-- MOUNT RULES`, `-- UPDATE ORCHESTRATION`. Partially cleaned in `CollectionRules.lua`.

### E — Narration comments (P2)

`-- This ensures...`, `-- Helper function to...`, `-- Note: This function...` in UI hot paths (`PlanCardFactory.lua`, `PvEUI.lua`, `UI.lua`). Keep only non-obvious business logic.

### F — Dead / compat stubs (P1)

`kept for backward compatibility but does nothing` — verify callers, then delete (`PlanCardFactory.lua`, `DataService.lua`).

### G — Locale / marketing copy (P3)

`DESCRIPTION.md` is intentionally promotional. In-game `Locales/enUS.lua` — spot-check for unnatural phrasing; no mass rewrite without native speaker review.

### H — `.cursor/` agent corpus (Out of scope)

Rules/skills are meta-documentation for Cursor agents, not shipped addon code.

## Pass 1 changes (committed on chore/de-ai-fixes)

| File | Change |
|------|--------|
| `Modules/CollectionRules.lua` | Short header; removed Rule Interface doc + 27 `@param` blocks + section banners; fixed duplicate `GetItemInfo` in TRANSMOG |
| `Modules/Constants.lua` | Replaced 30-line semver essay with 3-line header |
| `Modules/EventManager.lua` | Removed false feature claims (priority queue, stats); stripped `@param` blocks |
| `Modules/PvECacheService.lua` | Trimmed architecture marketing header |
| `Modules/APIWrapper.lua` | Stripped `@param` block comments |
| 15 additional service/UI modules | Trimmed `Features:` / `Architecture:` headers (see git log) |

## Phased plan

### Phase 1 — Headers & lies (current)

- [x] Branch `chore/de-ai-fixes`
- [x] Inventory (this file)
- [x] 5-file pilot strip
- [x] Batch-trim remaining `Features:` / `Architecture:` headers in cache/service modules (20 files)
- [ ] Fix headers that describe non-existent behavior (audit each claim)

### Phase 2 — Comment noise in services

- Scripted strip of `--[[ ... @param ... ]]` in files with >20 occurrences
- Manual pass on `TryCounterService.lua` / `GearService.lua` (split: keep encounter-ID tables, trim prose)
- Remove `Helper function to` one-liners in `PvEUI.lua`, `ReputationUI.lua`

### Phase 3 — UI layer

- `SharedWidgets.lua`, `PlanCardFactory.lua`, `SettingsUI.lua` — narration comments only where logic is opaque
- Do **not** mass-delete `WN_FACTORY` / `WN_NONUI_UI` tags (agent markers, useful)

### Phase 4 — Dead code & compat

- Grep `backward compatibility`; delete no-op stubs after caller check
- `EventManager.lua` orphaned handler comment at EOF — verify and remove

### Phase 5 — Locales & docs

- Player-facing string review in `enUS.lua` only; mirror to locales after approval
- `DESCRIPTION.md` — optional human tone pass (separate from code de-ai)

## Verification

After each batch: `/reload` in-game, `python scripts/check_locales.py` if locales touched, no TOC changes expected for comment-only edits.

## User decisions needed

1. **`---@` LuaLS policy** — strip all internal annotations, or keep on `ns.*` exports only?
2. **`.cursor/` corpus** — leave as-is (recommended) or shorten agent rules separately?
3. **Large files** — de-ai only, or combine with planned splits (`TryCounterService`, `SharedWidgets`)?
4. **DESCRIPTION.md** — exclude from de-ai (marketing) or include tone edit?
