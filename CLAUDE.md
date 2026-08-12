# Warband Nexus — Claude Code Instructions

WoW retail addon (Lua 5.1). Target: **Midnight 12.1.0** (`## Interface: 120100`). The War Within is over.

---

## Micro-plan before any code change

Before any generate or modify:
1. Write a **1–2 line layout plan** (which layer, which file, which function/message).
2. Verify against SOA: Data → Service → `SendMessage("WN_*")` → View.
3. Localized edits only — **never rewrite an entire file** for a small fix; use surgical hunks.
4. If touching >~30% of a file without a user-requested full revision, pause and confirm.

---

## Architecture (SOA — strict unidirectional)

```
Data (AceDB, MigrationService, defaults)
  → Service (*Service, *Cache*, *Manager, *Scanner)
    → SendMessage("WN_*")
      → View (Modules/UI/**, WindowFactory, SharedWidgets)
```

**Rules:**
- Services NEVER call UI directly — use `SendMessage("WN_*")`.
- UI may not write `db.global` except through Service delegates.
- New features: implement on `ns.*Service` / `ns.*UI`, one-line shim on `WarbandNexus:Foo()` only if external callers need it. No heavy logic in `Core.lua`.

**Namespace:**
```lua
local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus  -- AceAddon (AceEvent, AceConsole, AceHook, AceTimer, AceBucket)
-- ns.L = AceLocale table
```

**Database:**
```lua
db.profile.*   -- Per-profile: settings, minimap, theme, notifications, fonts, modulesEnabled
db.global.*    -- Account-wide: characters, currencies, reputations, pveProgress, plans, tryCounts, warbandBank, trackDB
db.char.*      -- Per-character: personalBank, lastKnownGold
```

---

## Internal Messages (WN_*)

Emit after durable state is written. Only names from `Constants.EVENTS` — never invent new `WN_*` strings.

| Category | Messages |
|----------|----------|
| Character | `WN_CHARACTER_UPDATED`, `WN_CHARACTER_TRACKING_CHANGED` |
| Items | `WN_ITEMS_UPDATED`, `WN_BAGS_UPDATED`, `WN_ITEM_METADATA_READY` |
| Currency | `WN_CURRENCY_UPDATED`, `WN_CURRENCY_LOADING_STARTED`, `WN_CURRENCY_CACHE_READY`, `WN_CURRENCY_CACHE_CLEARED`, `WN_CURRENCY_GAINED` |
| Reputation | `WN_REPUTATION_UPDATED`, `WN_REPUTATION_LOADING_STARTED`, `WN_REPUTATION_CACHE_READY`, `WN_REPUTATION_CACHE_CLEARED`, `WN_REPUTATION_GAINED` |
| PvE | `WN_PVE_UPDATED` |
| Plans | `WN_PLANS_UPDATED`, `WN_PLAN_COMPLETED`, `WN_QUEST_COMPLETED`, `WN_VAULT_SLOT_COMPLETED`, `WN_VAULT_PLAN_COMPLETED`, `WN_VAULT_CHECKPOINT_COMPLETED` |
| Collections | `WN_COLLECTIBLE_OBTAINED`, `WN_COLLECTION_UPDATED`, `WN_COLLECTION_SCAN_COMPLETE`, `WN_COLLECTION_SCAN_PROGRESS` |
| Professions | `WN_PROFESSION_WINDOW_OPENED`, `WN_PROFESSION_WINDOW_CLOSED`, `WN_RECIPE_SELECTED`, `WN_RECIPE_DATA_UPDATED`, `WN_KNOWLEDGE_UPDATED`, `WN_CONCENTRATION_UPDATED`, `WN_CRAFTING_ORDERS_UPDATED` |
| UI | `WN_SEARCH_STATE_CHANGED`, `WN_SEARCH_QUERY_UPDATED`, `WN_TOOLTIP_SHOW`, `WN_TOOLTIP_HIDE`, `WN_FONT_CHANGED`, `WN_FONT_LIST_UPDATED`, `WN_UI_MAIN_REFRESH_REQUESTED` (`{ tab, skipCooldown }`) |
| System | `WN_MODULE_TOGGLED`, `WN_MONEY_UPDATED`, `WN_LOADING_COMPLETE`, `WN_LOADING_UPDATED`, `WN_SHOW_NOTIFICATION` |

UI-only redraws with no data change: `WarbandNexus:SendMessage("WN_UI_MAIN_REFRESH_REQUESTED", { tab = "items", skipCooldown = true })`.

---

## Lua 5.1 — WoW runtime rules (mandatory)

### Scope and forward refs
- `local function foo()` is visible only **after** its definition line. Define helpers **above** first use or forward-declare:
  ```lua
  local LayoutLabels  -- forward declare
  function LayoutLabels(btn) ... end
  -- OR on module table (preferred):
  local M = ns.GearUI_Paperdoll or {}
  function M.LayoutLabels(btn) ... end
  ```
- Mutual recursion: pre-declare all locals, then assign.
- Cross-file: symbols live on `ns.*` / `WarbandNexus` after TOC load order.

### VM limits (split before hitting the wall)
- **~200 locals per main chunk** — `do...end` in the same file does NOT reset this.
- **~60 upvalues per function** — extract to module-level helpers.
- Target: **< 120** top-level `local` lines per file for headroom.
- File **> ~2.5k lines** with many `local function` → plan a split.
- Share state across files via `ns.<ModuleName>` tables; update `WarbandNexus.toc` in dependency order.

### Multi-return trap
```lua
-- BAD: loses 2nd+ return from GetThing()
local a = cond and GetThing()

-- GOOD
local a, b
if cond then a, b = GetThing() end
```

### Forbidden
- `io.*`, `os.*`, `loadfile`, `dofile` — not in WoW
- Lua 5.2+ features: `goto`, `::label::`, `table.pack/unpack`, `//`, native bitwise
- Global pollution — everything `local` or on `WarbandNexus`/`ns`
- `ipairs()` in hot paths — use `for i = 1, #tbl do`
- String `..` in loops — use `table.concat`
- Table creation inside OnUpdate or high-frequency event handlers
- `GetItemInfo()` blocking calls — use `Item:CreateFromItemID()` + `ContinueOnItemLoad()`

---

## API Verification (mandatory — no hallucination)

Before implementing or advising on any WoW API, event, FrameXML, or patch behavior:

1. **Verify on [warcraft.wiki.gg](https://warcraft.wiki.gg/)** using WebFetch — this is mandatory, not optional.
2. Fallbacks: [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source) (FrameXML), [Ellypse stubs](https://github.com/Ellypse/IntelliJ-IDEA-Lua-IDE-WoW-API) (signatures), in-game verification.
3. If lookup unavailable, state what is **uncertain** and what to **verify in-game** — never invent.
4. Exception: purely local refactors with zero API/event/FrameXML surface may skip.

**Never:**
- Guess function names, API signatures, event payloads, or FrameXML template names.
- Invent `WN_*` strings not in `Constants.EVENTS`.
- Guess AceDB key paths or migration version numbers.

---

## Security — Taint & Secret Values (Midnight 12.0+)

```lua
-- MANDATORY before any string method on API-returned text
if issecretvalue and issecretvalue(val) then return end
val:find("pattern")  -- safe only after the check above
```

| Source | What's secret |
|--------|---------------|
| `line:GetText()` | Text during `SetWorldCursor` |
| `GetLootSourceInfo(slot)` | Creature/object GUIDs in instances |
| `UnitGUID("target")` | Target GUID during secure combat |
| `ENCOUNTER_END` args | `difficultyID` can be secret |
| `EJ_GetEncounterInfoByIndex` | `encName`, `dungeonEncID` |
| `IsInInstance()` | Return in secure frames |
| `GetStatistic()` | May return secret — guard before `tonumber` |
| `CHAT_MSG_LOOT` | Message/author in some contexts |

**Rules:**
1. Never call string methods on API text without `issecretvalue` check.
2. Never compare secret values with `==`, `~=`, or `not`.
3. Never pass secrets to `tonumber()`, `tostring()`, `string.find()` directly.
4. Always provide a safe fallback (usually `nil` or `return`).
5. Never taint globals — localize: `local tinsert = table.insert`.
6. `if InCombatLockdown() then return end` before touching secure frames.

---

## Event Handling

```lua
-- High frequency: AceBucket
self:RegisterBucketEvent("BAG_UPDATE", 0.5, "OnBagUpdateBucket")

-- Rate limit
self:Throttle("CURRENCY_SCAN", 1.0, function() ... end)

-- Coalesce redraw
self:Debounce("REPUTATION_UI", 0.2, function() ... end)
```

**Never** refresh UI directly from Blizzard handlers in services — persist → `SendMessage("WN_*")`.
**Never** poll with OnUpdate/NewTicker for data that has a Blizzard event.

**Adding a new event:** wiki pass first → implement in owning Service/Cache → after DB write emit `SendMessage` → add constant to `Modules/Constants.lua` if new `WN_*` → UI subscribes thin listener → debounced refresh.

---

## Character Identity — GUID-first

- Primary persisted row key: **player character GUID** (not Name-Realm).
- Live writes: `ns.Utilities:GetCharacterStorageKey(addon)` or `CharacterService:ResolveSubsidiaryCharacterKey`.
- Resolving inbound keys: `GetCanonicalCharacterKey` / `ResolveCharacterRowKey` / `UI_GetCharKey`.
- Never synthesize a GUID — only from `UnitGUID` / persisted `charData.guid`.
- Name-Realm only for: display labels, plans fields, legacy migration, fallback when GUID unavailable.
- GUIDs from secure contexts may be secret — always `issecretvalue` guard before `:sub`, `strsplit`, equality.

---

## UI — SharedWidgets & Factory (mandatory)

All UI surfaces through SharedWidgets/Factory — no ad-hoc `CreateFrame("Frame"|"Button")` for new UI.

| Need | Source |
|------|--------|
| Container | `ns.UI.Factory:CreateContainer(parent, w, h, withBorder)` or `ns.UI_CreateCard` |
| Button | `ns.UI.Factory:CreateButton(parent, w, h, noBorder)` or `ns.UI_CreateButton` |
| ScrollFrame | `ns.UI.Factory:CreateScrollFrame(parent, template, customStyle)` |
| Row | `ns.UI_Acquire*Row(parent, ...)` + `ns.UI_Release*Row` |
| Header | `ns.UI_CreateCollapsibleHeader(...)` |
| Section header | `ns.UI.Factory:CreateSectionHeader(...)` |
| Data row | `ns.UI.Factory:CreateDataRow(...)` |
| External dialog | `WindowFactory.CreateExternalWindow(config)` |

**Strata:** BACKGROUND < LOW < MEDIUM < HIGH < DIALOG < FULLSCREEN < FULLSCREEN_DIALOG < TOOLTIP.
Child strata cannot exceed parent.

**Banned:** default Blizzard or AceGUI widgets directly, magic number layouts, hardcoded colors.
**Always:** `ns.UI_LAYOUT`, `ns.UI_COLORS`, FontManager for all layout/color/font.

---

## UI — Layout & Padding

- **Single padding constant per axis** — one value for all left/right padding in a container.
- **Symmetric anchors** — if TOPLEFT uses `pad`, TOPRIGHT uses `-pad`.
- Content never under chrome — `scrollChild:SetWidth(scrollFrame:GetWidth() - SCROLLBAR_WIDTH)`.
- All pixel values live in one `UI` or `LAYOUT` table — no scattered magic numbers.

---

## UI — Theme (Light / Dark)

- `db.profile.themeMode`: `"dark"` | `"light"`.
- Dark mode is frozen baseline — do not regress.
- **Never** hardcode `{0.12, 0.12, 0.15}` button bg → use `UI_GetControlChromeBackdrop()`.
- **Never** `{0.08, 0.08, 0.10}` chrome → theme chrome helpers.
- **Never** `SetTextColor(1, 1, 1)` on light card → `UI_SetTextColorRole(fs, "Bright")`.
- **Never** `SetDesaturated(true)` or dark vertex on nav icons in light mode.
- **Never** WoW `OUTLINE` on light fonts → `FontManager:ApplyReadableEdge`.
- Icons: **white** in dark, **black** in light (via `UI_GetMonochromeIconVertex`).

**GRAY BAN:** Never ship grey/muted-grey RGB for user-facing labels in Collections rows, achievement meta, or WN action icons.

After theme toggle: `FontManager:RefreshThemeTypography()` + `UI_RefreshColors()`.

---

## UI — Tooltips

**Never hardcode tooltip RGB** — use semantic helpers:
- `UI_GetTooltipTitleColor()` — titles
- `UI_GetTooltipLabelColor()` — labels
- `UI_GetTooltipBodyColor()` — body lines
- `UI_GetTooltipDescColor()` — secondary notes
- `UI_RemapGameTooltipLineColor(r,g,b)` — Blizzard `colorRGB` from `C_TooltipInfo` lines (light mode remap)

Every `C_TooltipInfo` line path must call remap on `colorRGB` before `SetTextColor`. Dark mode: pass through unchanged.

---

## UI — Detail Popups

For `CreateExternalWindow` / shift+click details / mail details / `*Popup.lua`:

**Content paradigm (choose before coding):**
- Items with long names / ilvl / stack meta → **full-width list rows** (not icon grid).
- Fixed columns with known widths → table layout (like `CharacterBankMoneyLogPopup`).
- Single entity → fixed panel with scroll if needed.
- Many dynamic sections → stacked cards in scroll child.

**Reference-first — read one before implementing:**
- Dialog shell: `Modules/UI/WindowFactory.lua`
- Column width → window width: `Modules/UI/CharacterBankMoneyLogPopup.lua`
- Detail scroll + scrollbar: `Modules/UI/CollectionsUI_Shared.lua`

**Width formula:**
```lua
local POPUP_W = CONTENT_W + (PAD * 2) + SCROLLBAR_W + (DIALOG_INSET * 2)
local scrollChildW = CONTENT_W  -- NOT the outer dialog width
```

**Banned:** icon grid for readable names, `scrollChild:SetWidth(popupW)` ignoring scrollbar, shipping without reading reference files.

---

## Performance

**Hot paths:** AceBucket bursts, spammy events, WN_* refresh chains, scroll/virtual list refill, tooltip rebuild, login batch scans.

- Reuse scratch tables with `table.wipe`, no `{}` inside per-row renderers.
- Pool rows via Factory (`Release*` / `Acquire*`).
- Prefer async item flows (`Item:CreateFromItemID` + `ContinueOnItemLoad`) over blocking `GetItemInfo`.

**Heavy tab first paint (MUST for tabs that can exceed ~10–16ms):**
1. MUST NOT rely on unbounded single-frame build for Storage, large Collections/Plans trees.
2. Drive staged work with bounded continuations: `C_Timer.After` or `AceTimer` — not `OnUpdate` polling.
3. Use generation/request ID so tab switches cancel superseded partial renders.
4. Expose a loading state while content is incomplete.

**Debug timing:** `ns.Profiler`, `/wn profiler on`.

---

## Naming Conventions

- `PascalCase` — classes, services, public methods: `CharacterService`, `:GetData()`
- `camelCase` — variables, local functions: `charKey`, `function validateGUID()`
- `SCREAMING_SNAKE_CASE` — constants: `MAX_ITEMS`, `RECENT_KILL_TTL`
- Verb+noun for functions: `UpdateInventory()`, `HandleBagUpdate()`
- All internal: `local` or on `WarbandNexus`/`ns`

---

## File Size & Module Splitting

| Lines | Action |
|------:|--------|
| < 800 | OK if single concern |
| 800–2500 | Watch local count |
| > 2500 | Split (`ns.*` + TOC) before large features |
| > 4000 | **Must** split — tech debt |

Split pattern: `ns.Foo = {}`, `function M.Bar` in satellite files. Update `WarbandNexus.toc` (shared/helpers before entry). Use `assert(M and M.state, "...")` in satellites for mis-ordered TOC detection.

---

## Localization

- **Source of truth:** `Locales/enUS.lua` — `L["KEY"] = "..."`.
- Runtime access: `ns.L["KEY"]`.
- Add `L["NEW_KEY"]` to `enUS.lua` first, then mirror to **all** `Locales/*.lua` in TOC.
- Audit: `python .github/scripts/preflight_release.py` and `python scripts/check_locale_quality.py`.

**Character set policy:**
- `enUS.lua` values: **ASCII-only** (U+0020–U+007E) plus WoW tokens (`|c`, `|r`, `|T`, `|H`). No smart quotes, em dash, ellipsis, arrows.
- All other locales: **native letters and diacritics required** — never strip umlauts/accents to ASCII.

**Blizzard GlobalStrings** for shared vocabulary — same RHS expression in every locale file:
```lua
L["SAVE"] = SAVE or "Save"
L["CLOSE"] = CLOSE or "Close"
```

---

## Packaging & Release

### Release checklist (agent MUST follow this order)

**0) Pre-release gate (run first, fix all errors before tag):**
```
python .github/scripts/preflight_release.py
```

**A) Draft release notes — LATEST VERSION ONLY:**
- `git log` since last `v*` tag for player-visible changes.
- **REPLACE** the whole of `CHANGELOG.md` with a single `## vX.Y.Z (YYYY-MM-DD)` section. Do **not** prepend/keep older sections — `.pkgmeta` ships this file verbatim as the CurseForge/Wago release notes, so any old section shows up in every new release.
- One line per bullet; plain player language; no file paths or ticket IDs; 4–10 bullets total.
- Do **not** write a `Fixed:` bullet for something this same release lists under `Added:` — players never saw the broken state.

**B) Mirror to all locales — LATEST KEY ONLY, ENGLISH:**
- Every `Locales/*.lua` carries exactly **one** `L["CHANGELOG_VXYZ"]` (key: `3.1.7` → `CHANGELOG_V317`). **DELETE the previous version's key** in the same commit: `NotificationManager_Changelog.lua` derives the key from `ADDON_VERSION` and only ever reads the current one, so older keys are dead weight shipped to every player.
- Changelog copy stays **English in every locale**, headers included (`Added:` / `Updated:` / `Fixed:`). Do not translate it.
- Keep the trailing `CurseForge: Warband Nexus` line.

**C) Version bump (three places simultaneously):**
- `Modules/Constants.lua` → `ADDON_VERSION`, `ADDON_RELEASE_DATE`
- `WarbandNexus.toc` → `## Version`

**D) Ship:**
- Commit all changed files.
- `git tag vX.Y.Z` then `git push origin main` and `git push origin vX.Y.Z`.

**Never:** bump version without CHANGELOG.md + locale CHANGELOG_V* parity. Never commit API keys.

### TOC rules
- Correct load order — dependencies before dependents.
- `SavedVariables: WarbandNexusDB` — never rename.
- Every shipped file listed; case must match exactly (Linux packager).
- `## Interface: 120100` (Midnight 12.1.0).

---

## Debugging

| Need | Hook |
|------|------|
| General debug | `ns.DebugPrint` / `profile.debugMode` |
| Dense traces | `ns.DebugVerbosePrint` + `profile.debugVerbose` |
| Timing/spikes | `ns.Profiler`: `Start`/`Stop`, `/wn profiler *` |

**Never** concatenate or log raw API strings that might be secrets (tooltip text, GUIDs, ENCOUNTER_END args).

**Try Counter smoke test:** `/wn tc test` → `WarbandNexus:RunTryCounterSelfTest()`. Extend probes in `RunTryCounterSelfTest` only.

**Troubleshooting:**
1. Reproduce with minimal steps.
2. Confirm TOC load order.
3. Use AceDB reset paths only when intended (MigrationService).
4. For message bugs: trace `SendMessage` emit vs `RegisterMessage` listeners.
5. UI stale: distinguish missing message vs debounced/suppressed refresh.

---

## Version / Midnight Policy

- **Target: Midnight 12.1.0 only.** TWW is over.
- Currency IDs, crest names, encounter labels — always current Midnight data.
- Never hard-code expansion skillLineIDs — discover via `C_TradeSkillUI.GetChildProfessionInfos()`.
- Do NOT use `LE_EXPANSION_*` enums (deprecated) — use `ns.Constants.CURRENT_EXPANSION_INTERFACE`.
- `issecretvalue` guards are mandatory everywhere — see Security section.
- All `C_*` API calls: `pcall` for resilience.

---

## Authoritative Code Anchors

| Concern | File |
|---------|------|
| Internal messages | `Modules/Constants.lua` → `Constants.EVENTS` |
| Theme surfaces | `Modules/UI/SharedWidgets.lua` → `SURFACE_VARIANTS`, `COLORS` |
| Font outline policy | `Modules/FontManager.lua` → `GetAAFlags`, `ApplyReadableEdge` |
| Tooltip line remap | `SharedWidgets.lua` → `UI_RemapGameTooltipLineColor` |
| Tooltip rendering | `Modules/TooltipService.lua`, `Modules/UI/TooltipFactory.lua` |
| Layout constants | `UI_SPACING` / `UI_LAYOUT` in SharedWidgets |
| External dialogs | `Modules/UI/WindowFactory.lua` → `ns.UI_CreateExternalWindow` |
| Character key helpers | `Modules/Utilities.lua` → `GetCharacterStorageKey`, `GetCanonicalCharacterKey` |
| Migrations | `Modules/MigrationService.lua` |
| Event registration | `Modules/EventManager.lua` |

---

## PR Checklist (per file, before merge)

- [ ] **OWNERSHIP** — code in correct layer (not UI in service or vice versa)
- [ ] **WN_*** — emit after DB write; listeners thin; no duplicate `RegisterMessage` for same storm
- [ ] **Lua 5.1** — helpers above callers; no `and fn()` multi-return trap
- [ ] **Locals** — chunk stays under ~120 top-level local lines headroom
- [ ] **Secrets** — `issecretvalue` before string ops on API text
- [ ] **UI** — new surface via SharedWidgets/Factory
- [ ] **Identity** — character keys via `GetCanonicalCharacterKey`/`CharacterService` resolvers
- [ ] **Locales** — user strings in `Locales/enUS.lua` (ASCII values)
- [ ] **Migrations** — incompatible `db` shape bumped in MigrationService only

---

## Related project

**Artisan Nexus** (sibling repo): professions/crafting; same three-layer SOA, internal messages use **`AN_*`**. Map `WN_*` → `AN_*` and `WarbandNexus` → `ArtisanNexus` when sharing patterns.
