# Classic Theme Gaps — Tab & Satellite UI Audit

**Date:** 2026-07-02 (Phase 7: Settings nav, Plans editor/tracker cards, Gear paperdoll viewport)  
**Scope:** `Modules/UI/*UI*.lua`, `*Popup.lua`, `PlansTrackerWindow.lua`, `RecipeCompanion*.lua`, tracker windows (`ProfessionInfoWindow.lua`)  
**Method:** Grep for direct `CreateFrame("Button"|"ScrollFrame"|"Slider"|"CheckButton")`, raw `SetBackdrop` / `SetBackdropColor` outside `UI_ShouldUseBlizzardChrome`, and `ApplyVisuals` on chrome that bypasses Factory.  
**Cross-reference:** `docs/CLASSIC-THEME-GAPS-FACTORY.md` — not present in repo at audit time; Factory routing inferred from `SharedWidgets_Factory.lua` + `SharedWidgets_Icons.lua` (`UI_CreateButton`).

---

## Executive summary

| Metric | Count |
|--------|------:|
| Files scanned | **39** |
| Files with ≥1 **GAP** | **~5** |
| Classified gap hits (chrome widgets / paths) | **~12** |
| Tabs **classic-complete** (main panel chrome) | **5** |
| Tabs **partial** (Factory-heavy, local bypasses remain) | **6** |
| Tabs / satellites **chrome gaps remain** | **4+** |

**Infrastructure note:** `SharedWidgets_ClassicTheme.lua` defines `UI_ApplyBlizzardPanelBackdrop`, `UI_CanApplyCustomChrome`, and `UI_ApplyClassicNavTabActiveState`. `UI_ApplyVisuals` early-returns on Blizzard template widgets.

**Factory classic routing today** (`UI_ShouldUseBlizzardChrome`): `CreateContainer`, `CreateScrollFrame`, `CreateThemedSlider`, `CreateEditBox`, `ApplyHighlight`, `UI_CreateButton` / `CreateThemedButton`, plus partial paths in `WindowFactory.lua`.

---

## Tab / surface completeness

| Tab / surface | Status | Notes |
|---------------|--------|-------|
| **Currency** | Classic-complete | Containers, scroll, rows via `Factory`; no direct chrome `CreateFrame` in tab file. |
| **Statistics** | Classic-complete | Title card, buttons, cards via `Factory` / SharedWidgets exports. |
| **Reputation** | Classic-complete | Virtual list + pooled rows; only content `Frame` fallbacks. |
| **Collections** | Classic-complete | `CollectionsUI_Draw` / `_Lists` / `_Recent` / `_Shared` use `Factory:CreateContainer` + `CreateScrollFrame`. Sub-tabs via `UI_CreateSubTabBar` + classic `UI_ApplySubTabButtonVisuals`. |
| **Items** | Partial (P1 chrome) | Bank sub-tabs: Factory `UIPanelButtonTemplate` + shared sub-tab visuals (2026-07-02). Storage tree headers via `CreateCollapsibleHeader` classic panel. Custom `CreateItemsBankSubTabBar` not yet merged into `UI_CreateSubTabBar`. |
| **Characters** | Partial | Most chrome via `Factory`; delete-confirm + legacy fallback button at L155 uses Blizzard panel **textures** (OK) but not `UI_CreateButton` classic branch. |
| **PvE** (main) | Partial | Vault grid + column picker classic (Phase 6). Body uses Factory patterns. |
| **Plans** (browse / weekly) | Partial | Browse rows/cards via `ApplyPlansChrome`; custom plan editor classic toggles/steppers (Phase 7). |
| **Gear** | Partial (P1 chrome) | `GearUI_Chrome` + paperdoll viewport/pill/stash veil classic (Phase 7). Char selector + slots done Phase 6. |
| **Professions** | Partial (P1) | Column picker + row buttons guarded via `ApplyProfChrome` (Phase 6). Hit pads N/A. |
| **Settings** | Partial | Left nav rail classic UIPanelButtonTemplate (Phase 7); dropdowns/sliders via `ApplySettingsChrome`. |
| **Plans tracker** | Partial (P1) | Shell + header + plan card/row chrome classic (Phase 6–7). Header icon buttons low-impact gap. |
| **Recipe companion** | Partial (P1) | Dialog shell + header classic (Phase 6). Raw header `CreateFrame` geometry unchanged. |
| **Profession info** | Partial (P1) | Dialog shell + header classic (Phase 6). Scroll stock template OK. |
| **Popups** (mail / gold) | Partial | Mostly `Factory` + `ApplyVisuals`; money log tabs classic via `UI_ApplyClassicNavTabActiveState` (2026-07-02). |

---

## Files with gaps (detail)

Only files with **GAP** rows are listed. Hits marked **OK** use Factory/classic-routed APIs; **N/A** is hit-testing or content-only.

### `GearUI_Chrome.lua` — **2 GAP**

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 225+ | Stat / track pills `SetBackdrop` on raw frames | **GAP** | Upgrade track labels (viewport/subpanel classic Phase 4/6) |
| 29–37 | `ApplySubpanel` non-classic path only | **OK** | Classic uses `UI_ApplyBlizzardPanelBackdrop` |

### `GearUI_Paperdoll_Slots.lua` — **0 GAP** (Phase 6)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 75–161 | Slot `borderFrame` → `UI_ApplyBlizzardPanelBackdrop` in classic; quality `SetBackdropBorderColor` preserved | **OK** | Equipment slot rim |

### `GearUI.lua` — **0 GAP** (Phase 7)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 109–112 | Stash panel host veil | **OK** | Classic `UI_ApplyBlizzardPanelBackdrop` (Phase 7) |
| ~2457+ | Character selector + menu | **OK** | Classic panel via `ApplyGearControlChromeIdle` / `ApplyGearDropdownMenuChrome` (Phase 6) |
| 2263+ | Gear toolbar controls | **OK** | Guarded chrome helpers (Phase 6) |

### `GearUI_Paperdoll.lua` — **0 GAP** (Phase 7)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 175 | Model viewport fill | **OK** | Delegates `GearUI_Chrome.ApplyPaperdollViewport` |
| 2607, 2729 | Pills / model border | **OK** | Classic panel pill; model accent rim hidden in classic |

### `GearUI_Paperdoll_Slots.lua`

_(See Phase 6 note above — merged into Gear table.)_

### `ProfessionsUI.lua` — **0 GAP** (column chrome Phase 6)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 442 | Column picker click catcher | **N/A** | Transparent hit pad |
| 516+ | Menu rows via Factory `CreateButton` | **OK** | Classic `_wnBlizzardButton` / `_wnSkipCustomChrome` |
| 607+ | Menu fallback | **OK** | Classic `UI_ApplyBlizzardPanelBackdrop` (Phase 6) |
| 1931+ | Row action buttons | **OK** | `ApplyProfChrome` guard (Phase 6) |

### `SettingsUI_Shell.lua` — **0 GAP** (Phase 7)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 202+ | `CreateSettingsNavButton` | **OK** | Classic `UIPanelButtonTemplate` + LockHighlight active state |

### `SettingsUI.lua` — **1 GAP** (representative)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 638–796 | Nav / preset / theme buttons | **OK** | `ApplySettingsChrome` + classic preset LockHighlight |
| 1020–1105 | Custom dropdown menus | **OK** | `ApplySettingsChrome` on shell + rows |
| 1480+ | Slider border tint | **OK** | Skips `_wnBlizzardSlider` in `RefreshSubtitles` (Phase 7) |
| 2941–3292 | Keybind / notification sub-dialogs | **OK** | `ApplySettingsChrome` shells |
| 4663 | Nav column | **OK** | `ApplySettingsChrome` / borderless surface |
| 1440, 1751 | `CreateFrame("Frame")` capture anchors | **N/A** | Non-visual capture only |

### `PlansUI.lua` — **0 GAP** (Phase 7)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 2754–2967 | Reset toggles / steppers / selected state | **OK** | Factory or UIPanelButtonTemplate; LockHighlight |
| 3386 | Column `clickPad` `CreateFrame("Button")` | **N/A** | Plan grid hit area |
| 1444–3421 | Card/row chrome | **OK** | `ApplyPlansChrome` guard |

### `ItemsUI.lua` — **0 GAP** (P1 sub-tab chrome fixed 2026-07-02)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| ~240–420 | Bank sub-tabs via `Factory:CreateButton` + `UI_ApplySubTabButtonVisuals` | **OK** | Classic: UIPanelButtonTemplate, LockHighlight, no custom hover/backdrop override |
| ~1398+ | `DrawStorageResults` / `CreateCollapsibleHeader` | **OK** | Section headers use classic panel in `SharedWidgets_Collapsible.lua` |
| Fallback | `BackdropTemplate` when Factory nil | **GAP (dev only)** | Rare; same geometry, custom chrome until Factory loads |

### `PvEUI_VaultGrid.lua` — **0 GAP** (Phase 6)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 869+ | Vault slot cells | **OK** | Classic panel + stripe state; `SetVaultSlotFill` / `EnsureVaultSlotClassicPanel` |

### `PvEUI_ColumnPicker.lua` — **0 GAP** (Phase 6)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 117 | Catcher `CreateFrame("Button")` | **N/A** | Modal dismiss |
| 150+ | Menu + reset/toggle | **OK** | `ApplyPvEChrome` guard; Factory container in classic |

### `CharactersUI.lua` — **0 GAP** (Phase 7)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 155–163 | `CreateThemedButton` fallback → panel button **textures** | **OK** | Blizzard textures; not Factory classic branch but acceptable |
| 111–163 | Delete dialog buttons | **OK** | `ApplyCharDialogChrome` guards `_wnBlizzardButton` hover |

### `PlansTrackerWindow.lua` — **1 GAP** (shell + cards Phase 6–7)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 1574+ | Window shell + header | **OK** | `UI_ApplyFloatingWindowShellChrome` + header flat fill (Phase 6) |
| 1327+ | Filter dropdown | **OK** | Factory buttons + `ApplyTrackerChrome` on menu shell |
| 937+ | Plan cards / rows | **OK** | `ApplyTrackerChrome` (Phase 7) |
| 1656+ | Header close/collapse/gear | **GAP** | Icon chrome still `ApplyVisuals` on skip-chrome buttons |

### `RecipeCompanionWindow.lua` — **1 GAP** (shell Phase 6)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 877+ | Main frame shell | **OK** | `UI_ApplyFloatingWindowShellChrome` (Phase 6) |
| 907 | Header raw `CreateFrame("Frame")` | **GAP** | Drag band geometry only; chrome via `UI_ApplyFloatingWindowHeaderChrome` |
| 1008–1013 | Resizer + grabber textures | **N/A** | Stock textures |

### `ProfessionInfoWindow.lua` — **0 GAP** (shell Phase 6)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 1016+ | Frame/header | **OK** | Floating shell + header classic (Phase 6) |
| 1082 | `UIPanelScrollFrameTemplate` scroll | **OK** | Stock scroll in classic |
| 1089 | Scroll child raw `Frame` | **N/A** | Content host |

### `CharacterBankMoneyLogPopup.lua` — **0 GAP** (tab bar classic 2026-07-02)

| Line(s) | Pattern | Class | Impact |
|---------|---------|-------|--------|
| 331–376 | Tab bar `Factory:CreateButton` + `setTabVisuals` | **OK** | Classic uses `UI_ApplyClassicNavTabActiveState` |

### Popups without tab-file GAPs

| File | Status |
|------|--------|
| `MailDetailsPopup.lua` | **Partial** — cards via `ApplyVisuals`; no raw button chrome in tab file. |
| `GoldManagementPopup.lua` | **Partial** — `Factory` + `ApplyVisuals`; edit box via Factory when available. |

### Scanned *UI* files with **no tab-level GAP hits**

`CurrencyUI.lua`, `ReputationUI.lua`, `StatisticsUI.lua`, `CollectionsUI.lua`, `CollectionsUI_Draw.lua`, `CollectionsUI_Lists.lua`, `CollectionsUI_Model.lua`, `CollectionsUI_Recent.lua`, `CollectionsUI_Shared.lua`, `CollectionsUI_SourceData.lua`, `PlansUI_Browse.lua`, `PlansUI_WeeklyPlanner.lua`, `PlansUI_SourceParser.lua`, `ProfessionsUI_DrawTab.lua`, `PvEUI.lua`, `GearUI_Layout.lua`, `GearUI_LayoutGrid.lua`, `SettingsUI_Keybind.lua`, `SettingsUI_Modules.lua`, `UIStyle.lua`, `UI_RefreshRouter.lua`

*(These may still inherit the global `ApplyVisuals` stub gap.)*

---

## Top 15 highest-impact gaps (user-visible)

| Rank | Location | Widget / surface | Why it matters |
|------|----------|------------------|----------------|
| 1 | ~~`GearUI_Paperdoll_Slots.lua`~~ | ~~Per-slot quality borders~~ | **Fixed Phase 6** |
| 2 | ~~`GearUI_Chrome.lua` / `GearUI_Paperdoll.lua`~~ | ~~Viewport + subpanels + pills~~ | **Fixed Phase 7** (stat pills in Chrome remain) |
| 3 | ~~`GearUI.lua`~~ | ~~Character selector + menu~~ | **Fixed Phase 6** |
| 4 | ~~`SettingsUI_Shell.lua`~~ | ~~Settings category nav rail~~ | **Fixed Phase 7** |
| 5 | ~~`SettingsUI.lua`~~ | ~~Custom dropdown menus~~ | **Mostly fixed** via `ApplySettingsChrome` |
| 6 | ~~`ProfessionsUI.lua`~~ | ~~Column picker + row icon buttons~~ | **Fixed Phase 6** |
| 7 | ~~`PlansUI.lua`~~ | ~~Custom plan dialog toggles / steppers~~ | **Fixed Phase 7** |
| 8 | ~~`PvEUI_VaultGrid.lua`~~ | ~~Vault slot cells~~ | **Fixed Phase 6** |
| 9 | ~~`PlansTrackerWindow.lua`~~ | ~~Floating window shell + plan cards~~ | **Fixed Phase 6–7** (header icon buttons remain) |
| 10 | ~~`ItemsUI.lua`~~ | ~~Bank sub-tab strip~~ | **Fixed P1** |
| 11 | ~~`RecipeCompanionWindow.lua`~~ | ~~Companion window shell~~ | **Fixed Phase 6** |
| 12 | ~~`PvEUI_ColumnPicker.lua`~~ | ~~Column picker menu~~ | **Fixed Phase 6** |
| 13 | ~~`ProfessionInfoWindow.lua`~~ | ~~Profession tracker shell~~ | **Fixed Phase 6** |
| 14 | `CharacterBankMoneyLogPopup.lua` | Money log tab bar | Shift+click bank log popup |
| 15 | ~~**Global**~~ | ~~`UI_ApplyBlizzardPanelBackdrop` undefined~~ | **Fixed** — `SharedWidgets_ClassicTheme.lua` |

---

## Worst offenders (by gap hit count)

| File | GAP hits | Tab |
|------|----------|-----|
| `GearUI_Chrome.lua` | ~2 | Gear (stat pills) |
| `PlansTrackerWindow.lua` | ~1 | Tracker (header icons) |
| `RecipeCompanionWindow.lua` | ~1 | Tracker |
| `SettingsUI.lua` | ~0 | Settings (ApplySettingsChrome) |

---

## Recommended fix order (audit + P1 progress)

1. ~~Land `UI_ApplyBlizzardPanelBackdrop` / dialog helpers~~ **Done** (`SharedWidgets_ClassicTheme.lua`).
2. ~~**Gear** slot borders + char selector + paperdoll viewport~~ **Done Phase 6–7**; stat pills in `GearUI_Chrome` remain.
3. ~~**Settings** nav + dropdowns~~ **Done Phase 7** (nav rail); dropdowns via `ApplySettingsChrome`.
4. ~~**Professions** / **PvE** column pickers~~ **Done Phase 6** (`ApplyProfChrome` / `ApplyPvEChrome`).
5. ~~**Floating trackers** + plan cards~~ **Done Phase 6–7** (`UI_ApplyFloatingWindowShellChrome` + `ApplyTrackerChrome`).
6. **Items** — optional: replace `CreateItemsBankSubTabBar` with `UI_CreateSubTabBar` (deferred: gold reserve / guild gate).

---

## Appendix — trackers outside `Modules/UI/` (informational)

Not in primary scope but same pattern: `Modules/VaultButton_TrackerUI.lua`, `VaultButton_SavedInstancesUI.lua` use raw `CreateFrame("Button")` + `ApplyVisuals` / `SetBackdrop` fallbacks for vault-button satellite UI.

---

*Last updated: Phase 7 classic chrome (Settings nav, Plans editor/tracker cards, Gear paperdoll viewport/stash veil). Re-run after major Factory/tab refactors.*
