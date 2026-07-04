# Classic Theme — Factory & Main Shell Widget Coverage Audit

**Scope:** `SharedWidgets_ClassicTheme.lua`, `SharedWidgets*.lua`, `SharedWidgets_Factory.lua`, `WindowFactory.lua`, `UI.lua` (main shell), `FontManager.lua`, `SearchBoxComponent.lua`.

**Gate:** `themeMode == "classic"` → `ns.UI_IsClassicMode()` / `ns.UI_ShouldUseBlizzardChrome()` (defined in `SharedWidgets_ClassicTheme.lua`, re-exported from `SharedWidgets.lua` after load).

**Audit date:** 2026-07-03 (Factory Chrome primitives — dividers, ApplyBorder, widget facades)

---

## Factory Chrome primitives (`SharedWidgets_Factory_Chrome.lua`)

Loaded after `SharedWidgets_ClassicTheme.lua` + `SharedWidgets.lua`, before `SharedWidgets_Factory.lua`.

| API | Classic | Modern | Registry |
|-----|---------|--------|------------|
| `Factory:CreateThemeDivider` | Dialog-box rail strip (`UI_ApplyClassicRailDividerBackdrop`) or pane for `section` | `ApplyVisuals` quartet on thin container | `DIVIDER_REGISTRY` → `UI_RefreshThemeDividers` |
| `Factory:ApplyBorder` | `shell` / `card` / `panel` / `thin` / `iconWell` / `none` classic helpers | Elevated card / ApplyVisuals | via existing border refresh |
| `Factory:ApplyToolbarChrome` | Transparent edit host or classic pane | `UI_ApplySearchBoxChrome` / accent strip | `BORDER_REGISTRY` |
| `Factory:CreateSearchBox` | Delegates `ns.UI_CreateSearchBox` | Same | — |
| `Factory:CreateRadioButton` | `UIRadioButtonTemplate` via `UI_CreateThemedRadioButton` | Custom toggle dot | — |
| `Factory:CreateNavTabButton` | `UI.lua` registers `NavTabBuilder` | Same | — |
| `Factory:CreateProgressBar` | Delegates `UI_CreateStatusBar` | Same | — |
| `Factory:CreateListRow` | Delegates pooled `Acquire*Row` | Same | — |
| `Factory:CreateRailTabSeparator` | `nil` (gap-only) | `CreateThemeDivider` section | `DIVIDER_REGISTRY` |

**Migrated call sites (Phase 1):** main nav rail right edge (`UI.lua`), footer/settings-about seps, settings nav right edge, settings group dividers, settings category nav seps, vault button horizontal sep (via legacy shims → Factory).

**Governance:** `python scripts/check_ui_chrome_bypass.py` flags ad-hoc `SetColorTexture` divider textures outside allowlisted Factory files.

---

## Summary

| Metric | Count |
|--------|------:|
| **Factory + core SharedWidgets widget entry points audited** | **25** |
| **Direct classic branch** (explicit guard → Blizzard template / dialog chrome helper) | **11** |
| **Indirect classic** (delegates to `UI_ApplyVisuals`, `UI_ApplyMainWindowShellFill`, or `UI_CreateButton`) | **7** |
| **No classic branch** (always custom chrome) | **7** |
| **Total with classic routing (direct + indirect)** | **18 / 25 (72%)** |

Main shell **dialog box** (`UI-DialogBox-*`), **close button** (`UIPanelCloseButton`), **primary controls** (button / checkbox / slider / edit box via Factory), and **stock vertical scroll** (`UIPanelScrollFrameTemplate`) are covered. Largest visible gaps: **nav rail tabs**, **search EditBox shell**, **radio toggles**, **row/list chrome**, and **custom scroll-bar column** helpers still paint modern accent chrome when callers bypass `CreateScrollFrame`.

---

## Widget coverage table

| Function | File:line | Classic branch? | Blizzard template if yes | Still custom in classic? | Priority |
|----------|-----------|-----------------|--------------------------|--------------------------|----------|
| **Button** | | | | | |
| `ns.UI_CreateButton` | `SharedWidgets_Icons.lua:387` | **Yes** | `UIPanelButtonTemplate` | Template chrome; caller still sets size/text | P0 |
| `ns.UI_CreateThemedButton` | `SharedWidgets.lua:5266` | **Yes** | `UIPanelButtonTemplate` | Same | P0 |
| `ns.UI.Factory:CreateButton` | `SharedWidgets_Factory.lua:1667` | **Yes** (delegate) | via `UI_CreateButton` | Same | P0 |
| Main nav tab `CreateTabButton` | `UI.lua:2990` | **No** | — | Flat `ApplyBorderlessSurface` / `ApplyVisuals` + accent `activeBar` | **P0** |
| Settings / header utility buttons | `UI.lua:2284+`, `SettingsUI.lua` | **Partial** | Only when routed through Factory/`UI_CreateButton` | Debug reload, color picker shells, dropdown triggers often custom | P1 |
| **ScrollFrame** | | | | | |
| `ns.UI.Factory:CreateScrollFrame` | `SharedWidgets_Factory.lua:583` | **Yes** | `UIPanelScrollFrameTemplate` (default) | Stock Blizzard scroll bar; no WN accent track | P0 |
| Main content scroll host | `UI.lua` (via Factory at build) | **Yes** if Factory used | `UIPanelScrollFrameTemplate` | Layout/insets custom | P0 |
| Nav rail `ScrollFrame` | `UI.lua:2675` | **No** | — | Raw `CreateFrame("ScrollFrame")` | P1 |
| **ScrollBar** | | | | | |
| Custom vertical bar chrome | `SharedWidgets_Factory.lua:600–881` | **Skipped** when classic | — (stock bar from template) | N/A when `CreateScrollFrame` used | — |
| `ns.UI.Factory:CreateScrollBarColumn` | `SharedWidgets_Factory.lua:1170` | **No** | — | Empty frame; pairs with custom bar | P1 |
| `ns.UI.Factory:CreateHorizontalScrollBar` | `SharedWidgets_Factory.lua:1337` | **No** | — | Full custom accent slider + arrow buttons | P1 |
| `ns.UI.Factory:PositionScrollBarInContainer` | `SharedWidgets_Factory.lua:1188` | **No** | — | Positions WN `ScrollUpBtn`/`ScrollDownBtn` | P1 |
| **Slider** | | | | | |
| `ns.UI.Factory:CreateThemedSlider` | `SharedWidgets_Factory.lua:1681` | **Yes** | `OptionsSliderTemplate` | Template track/thumb; `OnValueChanged` wired by caller | P0 |
| **Checkbox** | | | | | |
| `ns.UI_CreateThemedCheckbox` | `SharedWidgets.lua:5413` | **Yes** | `UICheckButtonTemplate` | Template check art | P0 |
| `ns.UI_CreateThemedRadioButton` | `SharedWidgets.lua:5475` | **No** | — | Custom `ApplyToggleVisuals` dot | **P0** (Settings theme picker, options) |
| **EditBox** | | | | | |
| `ns.UI.Factory:CreateEditBox` | `SharedWidgets_Factory.lua:1761` | **Yes** | `InputBoxTemplate` | Template border; FontManager optional | P0 |
| `ns.UI_CreateSearchBox` (inner field) | `SearchBoxComponent.lua:147` | **No** | — | Raw `CreateFrame("EditBox")` + FontManager | **P0** |
| **Container / Card** | | | | | |
| `ns.UI.Factory:CreateContainer` | `SharedWidgets_Factory.lua:1641` | **Yes** (`withBorder`) | `UI_ApplyBlizzardPanelBackdrop` | Borderless container = plain Frame | P1 |
| `ns.UI_CreateCard` | `SharedWidgets.lua:4489` | **Indirect** | via `ApplyVisuals` → panel backdrop | No elevated-card gradients in classic | P1 |
| `ns.UI_ApplyStandardCardElevatedChrome` | `SharedWidgets.lua:4125` | **Indirect** | via `ApplyVisuals` | Tooltip-style panel border | P1 |
| **ApplyVisuals / borders** | | | | | |
| `ns.UI_ApplyVisuals` | `SharedWidgets.lua:3019` | **Yes** | `UI_ApplyBlizzardPanelBackdrop` | Replaces WHITE8x8 quartet | P0 |
| `ns.UI_ApplyBorderlessSurface` | `SharedWidgets.lua:3249` | **Yes** | `UI_ApplyClassicInteriorFlatFill` | Flat interior inside dialog | P0 |
| `ns.UI_ApplyMainWindowShellFill` | `SharedWidgets.lua:3315` | **Yes** | `UI-DialogBox-Background` + `UI-DialogBox-Border` | `_wnClassicShellChrome` child frame | P0 |
| `ns.UI_ApplyAccentControlChrome` | `SharedWidgets.lua:2960` | **No** | — | WHITE8x8 edge + accent rail (search/stats strip) | **P0** |
| `ns.UI_ApplySearchBoxChrome` | `SharedWidgets.lua:1310` | **No** | — | Calls accent control chrome or transparent `ApplyVisuals` | **P0** |
| **Highlight / hover** | | | | | |
| `ns.UI.Factory:ApplyHighlight` | `SharedWidgets_Factory.lua:148` | **Yes** | `Interface\\QuestFrame\\UI-QuestTitleHighlight` | ADD blend; not WN accent wash | P0 |
| `ns.UI_ApplyNavButtonHighlight` | `SharedWidgets.lua:561` | **Indirect** | via `Factory:ApplyHighlight` | Same | P0 |
| **Close button** | | | | | |
| Main window close | `UI.lua:2242` | **Yes** | `UIPanelCloseButton` | Blizzard art | P0 |
| `CreateExternalWindow` close | `WindowFactory.lua:194` | **Yes** | `UIPanelCloseButton` | Blizzard art | P2 |
| **Dialog shell** | | | | | |
| `CreateExternalWindow` root | `WindowFactory.lua:121` | **Yes** (shell) | via `ApplyMainWindowShellFill` | Header still `ApplyVisuals` panel | P2 |
| Main `WarbandNexusFrame` | `UI.lua:2083` | **Yes** | Dialog box backdrop | Header/footer/content layout custom | P0 |
| **Nav rail tab** | | | | | |
| `CreateTabButton` + rail surface | `UI.lua:2624–3120` | **Partial** | — | Classic palette + hidden divider; buttons remain custom flat rows | **P0** |
| `ns.UI_GetNavRailSurfaceBackdrop` | `SharedWidgets.lua:342` | **Yes** (palette) | — | Color only, not template | P0 |
| **Search box** | | | | | |
| `ns.UI_CreateSearchBox` container | `SearchBoxComponent.lua:127` | **No** | — | `ApplySearchBoxChrome` / accent border | **P0** |
| **Collapsible header** | | | | | |
| `ns.UI_CreateCollapsibleHeader` | `SharedWidgets_Collapsible.lua:179` | **Indirect** | via `ApplyVisuals` on header | Accent stripe + row join textures remain | P1 |
| `ns.UI.Factory:CreateSectionHeader` | `SharedWidgets_Factory.lua:1867` | **Indirect** | via `ApplyVisuals` | Factory section hover uses backdrop color math | P1 |
| **Progress / status bar** | | | | | |
| `ns.UI_CreateStatusBar` | `SharedWidgets_Icons.lua:344` | **No** | — | WHITE8x8 track + `ApplyVisuals` border | P1 |
| **Row pool chrome** | | | | | |
| `FramePoolFactory` `Acquire*Row` | `FramePoolFactory.lua:75+` | **No** | — | `CreateFrame("Button")` + `ApplyVisuals` / highlights | P1 |
| `ns.UI.Factory:ApplyRowBackground` | `SharedWidgets_Factory.lua:1798` | **No** | — | `SetColorTexture` stripe rows | P1 |
| `ns.UI.Factory:CreateDataRow` | `SharedWidgets_Factory.lua:1849` | **No** | — | Uses `ApplyRowBackground` | P1 |
| `ns.UI.Factory:CreateCollectionListRow` | `SharedWidgets_Factory.lua:2021` | **Partial** | Icon shell via `CreateContainer(..., true)` | Row frame + labels custom | P1 |
| Character row class gradient | `SharedWidgets_RowPool.lua:47` | **Yes** (suppress) | — | Gradient hidden; row chrome unchanged | P2 |
| **Font / outline** | | | | | |
| `FontManager:GetAAFlags` | `FontManager.lua:470` | **Yes** | — | Classic follows dark outline policy (not light soft shadow) | P0 |

---

## P0 gaps (main window + Settings — user-visible)

1. **Nav rail / top tab buttons** (`UI.lua:2990`) — Custom flat buttons with accent `activeBar`; no Blizzard tab/list row template. Most visible non-dialog control on every session.
2. **Search box** (`SearchBoxComponent.lua:127–147`) — Container uses `UI_ApplySearchBoxChrome` / `UI_ApplyAccentControlChrome` (modern accent edge); EditBox is raw, not `InputBoxTemplate` or `Factory:CreateEditBox`.
3. **Radio toggles** (`UI_CreateThemedRadioButton`) — Settings theme mode and other radio grids still use custom toggle dots (theme picker sits next to Classic option).
4. **Header utility cluster** — Tracking chip, Patreon/Discord/debug/reload buttons use custom `ApplyVisuals` squares (not `UIPanelButtonTemplate`).
5. **Accent control chrome** — Search/stats/toolbar strips bypass classic panel helper; paint WHITE8x8 + accent rail in classic mode.

---

## P1 gaps (tabs)

1. **Virtual / pooled list rows** (`FramePoolFactory.lua`) — All `Acquire*Row` shells are custom `Button` frames with WN borders/highlights (classic highlight only affects `ApplyHighlight` callers).
2. **Alternating row backgrounds** — `Factory:ApplyRowBackground` / `CreateDataRow` use flat color textures, not panel rows.
3. **Horizontal scroll bar** — `CreateHorizontalScrollBar` always builds WN accent chrome (Items wide grids, mail logs, etc.).
4. **Scroll bar column layout** — Collections-style external bar columns assume custom `ScrollUpBtn`/`ScrollDownBtn`; irrelevant for classic vertical scroll unless callers reparent stock bars incorrectly.
5. **Status / reputation bars** — `UI_CreateStatusBar` custom track/fill.
6. **Collapsible / section headers** — Panel backdrop via `ApplyVisuals`, but left accent stripe and section join lines remain modern.
7. **Nav rail scroll host** — Raw scroll frame without template (low visual impact).

---

## P2 gaps (popups / trackers)

1. **`WindowFactory` achievement popup** — Pooled card uses `ApplyStandardCardElevatedChrome`; action buttons use `CreateButton` (OK) but shell is nested custom card inside dialog shell.
2. **External dialog header band** (`WindowFactory.lua:156`) — `ApplyVisuals` nested panel inside dialog chrome (double-border risk).
3. **Floating trackers** (`PlansTrackerWindow`, `RecipeCompanionWindow`) — Separate resize/scroll paths; rely on Factory scroll where used but window chrome not re-audited here.
4. **Dropdown flyouts** — `Factory:ApplyDropdownScrollLayout` uses classic scroll when `CreateScrollFrame` called, but menu shell remains custom (`ApplyVisuals` / dropdown backdrops).

---

## Grep notes (2026-07-03)

Run `python scripts/check_ui_chrome_bypass.py` — remaining tab-file flat dividers (Characters, Gear, Items, PvP, trackers) are **P2 follow-up**; main shell + Settings rail edges are migrated to `CreateThemeDivider`.

### `UI_ShouldUseBlizzardChrome` / `UI_IsClassicMode` under `Modules/UI/**`

Present in: `SharedWidgets_ClassicTheme.lua`, `SharedWidgets.lua`, `SharedWidgets_Factory.lua`, `SharedWidgets_Icons.lua`, `SharedWidgets_RowPool.lua` (gradient suppress only), `WindowFactory.lua`, `UI.lua`, `FontManager.lua`.

**Not present in:** `SharedWidgets_Search.lua`, `SharedWidgets_Collapsible.lua`, `SearchBoxComponent.lua`, `FramePoolFactory.lua`, main nav tab builder (`UI.lua:2990`).

### `CreateFrame("Button"` without classic guard (representative Factory-adjacent)

| Location | Notes |
|----------|-------|
| `UI.lua:2992` | Nav tab buttons — **P0** |
| `SharedWidgets_Factory.lua:708,796,1410,1458` | Custom scroll arrow buttons (non-classic scroll path only) |
| `SharedWidgets_Collapsible.lua:195` | Section header hit target (chrome via `ApplyVisuals`) |
| `SharedWidgets_RowPool.lua:446,564` | Row/header controls |
| `FramePoolFactory.lua` | All pooled rows |

### Blizzard templates in Factory layer

| Template | Routed in classic? |
|----------|-------------------|
| `UIPanelScrollFrameTemplate` | Yes — `Factory:CreateScrollFrame` |
| `UIPanelButtonTemplate` | Yes — `UI_CreateButton`, `UI_CreateThemedButton` |
| `UICheckButtonTemplate` | Yes — `UI_CreateThemedCheckbox` |
| `OptionsSliderTemplate` | Yes — `Factory:CreateThemedSlider` |
| `InputBoxTemplate` | Yes — `Factory:CreateEditBox` only |
| `UIPanelCloseButton` | Yes — main shell + external dialogs |
| Dialog box backdrops | Yes — `UI_ApplyBlizzardDialogBackdrop` / `UI_ApplyBlizzardPanelBackdrop` |

---

## Suggested fix pattern (canonical classic branch)

Use the same guard at the top of any widget creator; early-return Blizzard template and skip WN chrome registries.

```lua
function ns.UI.Factory:CreateEditBox(parent)
    if not parent then return nil end

    if ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome() then
        local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
        editBox:SetAutoFocus(false)
        editBox:SetMaxLetters(256)
        editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        editBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
        editBox._wnBlizzardEditBox = true
        return editBox
    end

    -- ... existing custom EditBox path (FontManager, insets, theme registry) ...
end
```

**Search box follow-up:** In `SearchBoxComponent.lua`, replace raw `CreateFrame("EditBox")` with `Factory:CreateEditBox(container)` and replace `UI_ApplySearchBoxChrome` classic path with either `UI_ApplyBlizzardPanelBackdrop(container)` or no outer chrome (dialog interior already provides context).

**Nav tab follow-up:** Option A — classic idle/active fills via `UI_ApplyClassicInteriorFlatFill` + quest highlight only; Option B — `UIPanelButtonTemplate` for rail rows (wide hit targets need width/height tuning).

---

## Related files (out of scope but flagged)

- `Modules/UI/FramePoolFactory.lua` — All tab rows; no classic routing.
- `Modules/UI/SettingsUI_Shell.lua:202` — Settings category list buttons (custom).
- Tab UIs with direct `CreateFrame("Button", …, "BackdropTemplate")` bypass Factory (grep hits in `PlansUI`, `ProfessionsUI`, reminder dialogs).

---

## Classic theme infrastructure (reference)

| Export | File | Role |
|--------|------|------|
| `UI_CLASSIC_SURFACE_VARIANT` | `SharedWidgets_ClassicTheme.lua:10` | Palette tokens |
| `UI_ApplyBlizzardDialogBackdrop` | `SharedWidgets_ClassicTheme.lua:94` | Main / external shell |
| `UI_ApplyBlizzardPanelBackdrop` | `SharedWidgets_ClassicTheme.lua:115` | Nested bordered panels |
| `UI_ApplyClassicInteriorFlatFill` | `SharedWidgets_ClassicTheme.lua:128` | Header / rail / viewport bands |
| `UI_GetMainShellFrameInsets` | `SharedWidgets_ClassicTheme.lua:150` | Layout parity across themes |
