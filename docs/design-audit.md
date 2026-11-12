# Warband Nexus — UI Design System Audit

Scope: `Modules/UI/**/*.lua`, `Modules/FontManager.lua`, `Core.lua` (font defaults).
Method: `design-system audit` + `design-critique` against the repo's own rules in `CLAUDE.md`.
Read-only pass — no source file was modified.

---

## Summary

| Area | Verdict |
|---|---|
| Spacing / layout tokens | Broad and adopted (`PAGE_STACK` reaches 30 files), but the **ladder stops at the page level**. Row heights, icon tiles and popup padding have no tokens, so every file invents its own. |
| Color roles | Surfaces + text roles are a real system. **Semantic accents are not** — half of them live as literals inside function bodies, and the `light` variant is missing `red` entirely. |
| Markup colors (`\|cff…`) | The weakest layer. 61 per-file `*Hex()` shims re-wrap the same getters with conflicting fallbacks. One tab (`SettingsUI_Advanced`) is fully un-themed. |
| Components | Title card, search box and page stack are genuinely shared across 12 tabs — the strongest part of the system. Section headers have **two competing implementations** with tokens that encode the divergence. |
| Light mode | Structurally correct (surface ladder inverted, OUTLINE policy handled in `GetAAFlags`), but the **semantic accents were lightened instead of darkened**: gold and green sit at **1.2:1** on cards. |

---

## Findings (ordered by impact)

### F1 — Light-mode semantic gold and green are unreadable (1.2:1)

**What.** The `light` surface variant lightens the dark-mode accents instead of darkening them. Measured sRGB contrast against the light surfaces they actually sit on:

| Ink | on `bg` | on `bgCard` | on `surfaceRowOdd` |
|---|---|---|---|
| `gold` `{0.95, 0.78, 0.32}` | 1.49 | **1.20** | **1.14** |
| `green` `{0.55, 0.88, 0.45}` | 1.49 | **1.20** | **1.14** |
| *(dark mode, same roles)* | — | gold 11.34 / green 9.99 | gold 12.23 / green 10.78 |

**Where.** `Modules/UI/SharedWidgets_Theme.lua:183` (`light.gold`), `:184` (`light.green`); surfaces at `:175` (`bgCard`), `:178` (`surfaceRowOdd`).
`ThemeAPI.GetSemanticGoldColor` (`:1026`) passes gold through `AdjustRGBForLightOutline`, which only *raises* luminance toward a `minLum = 0.36` floor (`:324`) — it can never darken an already-bright accent, so gold comes back unchanged.

**Why it matters.** Gold is the money color and green the completion color — the two highest-frequency semantic inks in the addon. They survive in light mode only when the text happens to carry a WoW `OUTLINE`, and `GetAAFlags` (`:475`) returns `""` in light mode unless the caller passes `coloredInk`. Inline `|cff` markup never passes it, so every `|cff`-colored gold amount is bright-on-near-white with no edge.

**Rule.** A semantic accent is defined per variant by **target contrast against `bgCard`, minimum 4.5:1**, not by lightening or darkening the dark-mode value. Light-mode accents move toward the ink end of the ramp; dark-mode accents move toward white.

---

### F2 — `red` has no light-mode value, and two tabs read it directly

**What.** `SURFACE_VARIANTS.light` defines `gold` and `green` but **not `red`**, so `COLORS.red` keeps its dark value `{0.95, 0.30, 0.30}` in light mode. `ThemeAPI.GetSemanticRedColor` papers over this with a hardcoded light branch — but four call sites bypass the getter and read the raw row.

**Where.**
- Missing key: `Modules/UI/SharedWidgets_Theme.lua:170-190` (light variant block — neither it nor `dark` at `:153-169` declares `red`; it is inherited from `COLORS:142` and therefore never swapped).
- Getter with the inline fix: `Modules/UI/SharedWidgets_Theme.lua:1391-1397` (`return 0.78, 0.18, 0.18, 1`).
- Bypassing call sites: `Modules/UI/CurrencyUI.lua:180`, `Modules/UI/CurrencyUI.lua:235`, `Modules/UI/ReputationUI.lua:1240`, `Modules/UI/ReputationUI.lua:1538` — all `SemanticColorHex(COLORS.red)`.

Contrast of the value those four sites actually render in light mode: **2.50:1** on `surfaceRowOdd` (the correct getter value would give 3.85:1 — still short of 4.5, see F1's rule).

**Why it matters.** Currency cap warnings and hostile reputation standings are exactly the states that must not be missable. A palette key that exists in one variant and not another is a silent fallthrough — nothing errors, the color is just wrong.

**Rule.** Every key in `COLORS` must appear in **every** `SURFACE_VARIANTS` entry. No semantic value may live in a function body; `GetSemanticRedColor` reads the row, it does not define it.

---

### F3 — 61 per-file hex shims re-implement the same six colors with conflicting fallbacks

**What.** `Modules/UI` contains 61 local `*Hex()` / `*Color()` resolver functions. They wrap the same `ns.UI_Get*Hex` getters, but each carries its own hardcoded fallback, and the fallbacks disagree.

**Where.** Six separate "gold" shims, same intent, three different fallback values:

| File:line | Fallback |
|---|---|
| `Modules/UI/CharactersUI.lua:77` | `\|cffffd700` |
| `Modules/UI/PvEUI_VaultGrid.lua:149` | `\|cffffd700` |
| `Modules/UI/CharacterTrackingDialog.lua:52` | `\|cffffcc00` |
| `Modules/UI/CollectionsUI_Shared.lua:674` | `\|cffffcc00` |
| `Modules/UI/PlansUI.lua:66` | `\|cffffcc00` |
| `Modules/UI/InformationDialog.lua:22` | *(own copy)* |
| `Modules/UI/CollectionsUI_Extras.lua:271` | chains three resolvers in a different order |

Same pattern for `SemanticColorHex`, which is **byte-identical** in two files: `Modules/UI/CurrencyUI.lua:165` and `Modules/UI/ReputationUI.lua` (same body).

**Why it matters.** This is the system's "every page writes its own answer" failure mode. The fallback is not dead code — it fires during load before `SharedWidgets_Theme` finishes, and on that path Characters renders `ffd700` gold while Plans renders `ffcc00`. Worse, a shim freezes a value at *definition* time in some files, so a theme toggle does not reach it.

**Rule.** A file may **not** define a local color resolver. It imports `ns.UI_Get*Hex` / `ns.UI_Get*Color` at the call site, with no `or "|cff…"` fallback — if the theme is not ready, that is a load-order bug to fix in the TOC, not a color to guess.

---

### F4 — `ns.PLAN_UI_COLORS` is the correct pattern, built for one tab only

**What.** `Modules/UI/SharedWidgets_Theme.lua:1508` defines a **markup token table** — named roles (`title`, `label`, `descDim`, `completed`, `metric`) holding `|cff…` strings — re-synced on every theme change by `ThemeAPI.SyncPlanUIColors` (`:1526`). This is exactly the missing layer identified in F3, and it exists already. It serves Plans and nothing else.

**Where.** Table: `Modules/UI/SharedWidgets_Theme.lua:1508-1524`. Sync: `:1526-1555`. Consumers: `PlanCardFactory.lua:29`, `PlanCardFactory_Expanded.lua:22`, `PlansTrackerWindow.lua:24` (three copies of the same `PCol(key, fb)` accessor).

Every other surface reinvented it badly: `ResolveEmptyStateHex` (`SharedWidgets_EmptyState.lua:72`), `M.CollectionsBrightHex` (`CollectionsUI_Shared.lua:664`), `PveBrightHex` (`PvEUI.lua:34`), `VaultBrightHex` (`PvEUI_VaultGrid.lua:135`), `MutedHex` (`PvPUI.lua:98`), the eight `Season*Hex` functions in `FormatHelpers.lua:211-240`.

**Why it matters.** The token layer returns `(r, g, b)` tuples, but ~75% of colored text in this addon is inline `|cff` markup inside a localized string. There is no public markup token table, so every file bridges that gap itself. One tab solved it properly; nothing promoted the solution.

**Rule.** Promote `PLAN_UI_COLORS` to `ns.UI_HEX` — one addon-wide role→markup table, synced inside `ThemeAPI.SyncSemanticColorAliases` (`:1460`). `ns.UI_HEX.descDim` replaces every `*Hex()` shim and every bare `|cff888888`.

---

### F5 — `SettingsUI_Advanced` renders 29 hardcoded colors and calls zero theme helpers

**What.** Theme-helper adoption is uneven per tab. One file has none at all.

| File | `UI_Get(Text\|Semantic\|Themed)*` calls | `\|cff` literals |
|---|---:|---:|
| `Modules/UI/SettingsUI_Advanced.lua` | **0** | 29 |
| `Modules/UI/PvEUI_VaultGrid.lua` | 15 | 38 |
| `Modules/UI/SettingsUI_Notifications.lua` | 4 | 12 |
| `Modules/UI/CurrencyUI.lua` | 3 | 8 |
| `Modules/UI/PlansUI.lua` | 7 | 9 |

**Where.** `Modules/UI/SettingsUI_Advanced.lua:87` (`|cffffcc00` header), `:108` / `:110` / `:112` / `:114` / `:116` (five type badges, five raw hexes), `:200` (`|cff555555` placeholder — **1.9:1** on light `bg`), `:216` (`|cff00ff00`).

**Why it matters.** This is a whole settings page that does not participate in the theme. On light mode the `|cff555555` hint is a grey smear on near-white and the five type badges keep their dark-mode saturation. It also violates the project's own GRAY BAN rule.

**Rule.** Any file under `Modules/UI` that emits `|cff` must resolve it through `ns.UI_HEX` (F4). A preflight check can enforce this: a literal `|cff` in `Modules/UI/**` is an error outside `SharedWidgets_Theme.lua` and `SharedWidgets_ClassicTheme.lua`.

---

### F6 — Two section-header components, 2px apart, with tokens for both

**What.** The same visual element — collapsible section header with chevron, stripe and title — has two implementations, and `SharedWidgets_Layout.lua` defines a **separate chevron inset token for each** rather than one shared value.

**Where.**
- Tokens: `Modules/UI/SharedWidgets_Layout.lua:46` `SECTION_HEADER_COLLAPSE_CHEVRON_LEFT = 12` and `:47` `SECTION_HEADER_FACTORY_CHEVRON_LEFT = 10`.
- Implementation A — `ns.UI_CreateCollapsibleHeader`, `Modules/UI/SharedWidgets_Collapsible.lua:332` (chevron left 12), chevron size `SECTION_COLLAPSE_CHEVRON_SIZE = 26` at `:390`.
- Implementation B — `Factory:CreateSectionHeader`, `Modules/UI/SharedWidgets_RowPool.lua:726` (chevron left 10).
- A serves Characters, Currency, Items, Plans, PvE, Reputation, Collections, Professions. B serves Gear (`GearUI_Chrome.lua`, `GearUI_Paperdoll.lua`) and `RecipeCompanionWindow.lua`.

Chevron sizing is also doubled: `COLLAPSE_EXPAND_BUTTON_SIZE = 22` (`:88`) vs `SECTION_COLLAPSE_CHEVRON_SIZE = 26` (`:90`).

**Why it matters.** Gear's section headers are misaligned against every other tab's by 2px, and the token table *blesses* the drift instead of exposing it. A token whose name contains the implementation ("FACTORY", "COLLAPSE") is not a design token — it is a workaround with a constant's name.

**Rule.** One token per design decision, named after the decision, never after the implementation. `SECTION_HEADER_CHEVRON_LEFT` — one value, both components read it; delete the pair.

---

### F7 — No row-height or icon-size scale, so every surface picks its own

**What.** The two most repeated sizing decisions in a list-heavy addon have no complete token ladder. `UI_SPACING` offers `ROW_HEIGHT 26`, `STORAGE_ROW_HEIGHT 30`, `CHAR_ROW_HEIGHT 36` and `TABLE.ROW_H { compact 26, standard 30, identity 46 }`. The code ships **twelve** distinct row heights.

**Where (row heights with no token):**

| Value | Site |
|---:|---|
| 16 | `Modules/UI/TryCounterTestResultsWindow.lua:32` |
| 18 | `Modules/UI/SharedWidgets_Factory.lua:488` |
| 20 | `Modules/UI/PlansUI_Dialogs.lua:82` |
| 22 | `Modules/UI/RecipeCompanionWindow.lua:99`, `Modules/UI/StatisticsUI.lua:939`, `:1090` |
| 24 | `Modules/UI/PvPUI.lua:29`, `Modules/UI/PlansUI_WeeklyPlanner.lua:37`, `Modules/UI/SettingsUI.lua:63` |
| 28 | `Modules/UI/CollectionsUI_Shared.lua:89`, `Modules/UI/GearUI_LayoutGrid.lua:46-47` |
| 34 | `Modules/UI/GearUI_Paperdoll.lua:1689` |
| 46 | `Modules/UI/PvPUI_Overview.lua:29` |
| 52 | `Modules/UI/ProfessionsUI.lua:226` |

**Where (icon sizes with no token):** tokens cover 18/20/22/24/28/44; the code also ships 26 (`CharactersUI_Row.lua:353`, `CollectionsUI_Shared.lua:83`, `InformationDialog.lua:321`), 32 (`TooltipFactory.lua:115`), 34 (`PlansTrackerWindow.lua:127`), 36 (`MailDetailsPopup.lua:44`, `PlansUI_Dialogs.lua:64`), 40 (`WindowFactory.lua:457`, `CharacterSystemsPopup.lua:33`, `:42`), 48 (`PvEUI.lua:1740`, `PlansUI_Dialogs.lua:732`), 50 (`PvEUI.lua:1952`), and **39** (`CharactersUI_Row.lua:72`, `CELL_ICON = 39`).

**Why it matters.** `48` and `50` appear in the same file 200 lines apart for the same kind of tile — proof the value was chosen by eye, twice. `39` is off any plausible scale. A reader scanning Professions (52), PvP (24) and Statistics (22) sees three different list rhythms in one window.

**Rule.** Publish one ladder and forbid values outside it: `UI_SPACING.ROW_H = { xs 20, sm 24, md 26, lg 30, xl 36, hero 46 }` and `UI_SPACING.ICON = { xs 16, sm 20, md 24, lg 32, xl 40, hero 48 }`. A new surface picks a rung; it does not write a number.

---

### F8 — Popup side padding is 8 / 12 / 14 / 18 depending on which file you open

**What.** `PAGE_STACK.SIDE = 12` governs main tabs and `MAIN_SHELL.EXTERNAL_DIALOG_SIDE_INSET = 8` governs dialog shells, but every popup declares its own inner padding.

**Where.**

| Value | Site |
|---:|---|
| 8 | `Modules/UI/RecipeCompanionWindow.lua:83` |
| 12 | `Modules/UI/CharacterBankMoneyLogPopup.lua:68`, `Modules/UI/ProfessionInfoWindow.lua:60`, `Modules/UI/InformationDialog.lua:188` |
| 14 | `Modules/UI/PvPUI.lua:28`, `Modules/UI/TryCounterTestResultsWindow.lua:27`, `Modules/UI/WindowFactory.lua:456` |
| 18 | `Modules/UI/CharacterSystemsPopup.lua:37` |

`WindowFactory.lua:456` is the worst case: the shared dialog factory declares `local PADDING = 14` *inside a function*, so the one place that could have set the standard sets a fourth value privately.

**Why it matters.** `CLAUDE.md` already states the rule — "Single padding constant per axis". The token exists; the popups predate or ignore it. Opening two detail windows side by side shows two different gutters.

**Rule.** `PAGE_STACK.SIDE` is the only horizontal gutter. A popup that genuinely needs more declares `PAGE_STACK.SIDE * 1.5` as a named token in `SharedWidgets_Layout.lua`, never a local literal.

---

### F9 — The search box height is defined twice, in two tables, and the inner edit box ignores both

**What.** Two independent tokens express one height, and the component reads a third value.

**Where.**
- `Modules/UI/SharedWidgets_Layout.lua:386` — `PAGE_STACK.SEARCH_HEIGHT = 32` (what callers reserve in the page stack).
- `Modules/UI/SharedWidgets.lua:2065` — `UI_CONSTANTS.SEARCH_BOX_HEIGHT = 32` (what the component builds).
- `Modules/UI/SearchBoxComponent.lua:126` reads `UI_CONSTANTS.SEARCH_BOX_HEIGHT`; callers at `CurrencyUI.lua:1735`, `ItemsUI.lua:1621`, `ItemsUI_StorageDraw.lua:2320`, `ReputationUI.lua:2746`, `:2816`, `PlansUI_Browse.lua:297` reserve `PAGE_STACK.SEARCH_HEIGHT`. Both carry an inline `or 32` on top.
- `Modules/UI/SearchBoxComponent.lua:154-155` anchors the edit box `LEFT, 12` / `RIGHT, -10` — **asymmetric** — and then hard-sets `SetHeight(20)`, while the Blizzard branch at `:150-151` uses `4 / -4`.

**Why it matters.** Change either 32 and the reserved slot and the drawn box silently disagree. The 12/-10 anchor pair directly violates the "symmetric anchors" rule in `CLAUDE.md`; the 2px lean is visible against the symmetric title card above it.

**Rule.** One height token (`PAGE_STACK.SEARCH_HEIGHT`), read by both component and callers, with no `or 32` fallback — and the two horizontal insets are the same constant with opposite sign.

---

### F10 — Title text color is a caller decision in six tabs and a component decision in one

**What.** `ns.UI_CreateStandardTabTitleCard` is adopted by all 12 main tabs — a genuine strength. But the title's *ink* is passed in, not owned by the component, so one tab diverges.

**Where.** Six tabs wrap the title in caller-built markup: `CollectionsUI.lua:233`, `CurrencyUI.lua:1670`, `ItemsUI.lua:1449`, `ReputationUI.lua:2837`, `StatisticsUI.lua:698`, `PvEUI_BodyPaint.lua` / `PvPUI_Draw.lua` (same shape). `CharactersUI.lua:383` passes a plain localized string with no color at all, so the Characters title falls back to whatever the font role gives it.

**Why it matters.** The tab title is the top of the visual hierarchy; it is the one element that must be identical across tabs. Six files each compute `hexColor` locally (e.g. `StatisticsUI.lua:681`) to arrive at the same answer.

**Rule.** The title card owns the title ink. Callers pass plain localized text; `opts.titleText` must not contain `|cff`.

---

### F11 — `TITLE_CARD_UNDERLINE_ALPHA` is a dead token; three callers disable an underline that is already off

**What.** `Modules/UI/SharedWidgets_TitleCard.lua:457` gates the underline on `opts.showUnderline == true`. No caller in the repo ever passes `true`. Three callers pass a redundant `false`: `PvPUI_Draw.lua:50`, `SettingsUI.lua:1901`, `StatisticsUI.lua:700`.

**Where.** Dead token: `Modules/UI/SharedWidgets_Layout.lua:73` `TITLE_CARD_UNDERLINE_ALPHA = 0.5`.

**Why it matters.** Minor on its own, but it is the signature of a system nobody prunes: a removed design decision leaves a token, a code path and three opt-outs behind, and the next reader cannot tell whether the underline is "off" or "broken".

**Rule.** A token with no live consumer is deleted in the same change that removes its last consumer.

---

### F12 — `textDim` fails contrast on light cards (2.78 – 2.94:1)

**What.** The light ink ladder is correct at the top and fails at the bottom.

| Role | on `bgCard` | on `surfaceRowOdd` | WCAG AA (4.5) |
|---|---:|---:|---|
| `textBright` `{0.12,0.12,0.14}` | 12.30 | 11.66 | pass |
| `textNormal` `{0.24,0.24,0.28}` | 7.98 | 7.56 | pass |
| `textMuted` `{0.38,0.38,0.42}` | 4.57 | **4.33** | marginal / fail |
| `textDim` `{0.50,0.50,0.54}` | **2.94** | **2.78** | fail |

**Where.** `Modules/UI/SharedWidgets_Theme.lua:186-189` (light ink block). `textDim` is the role behind `PLAN_UI_COLORS.descDim` and `.notTracked` (`:1508`, `:1546-1547`) and every `ResolveEmptyStateHex("Dim", …)` call (`SharedWidgets_EmptyState.lua:72`, `:457`, `:505`).

**Why it matters.** Dim carries secondary descriptions and empty-state copy — text already working against the reader. In light mode it is below the 3:1 floor even for large text, and `GetAAFlags` returns `""` for achromatic ink (correctly, per `IsInkNearBlack` at `:280`), so there is no outline to rescue it.

**Rule.** Each light ink role is set to a contrast target against `surfaceRowOdd` (the darkest surface it can land on), not against `bg`: Bright ≥ 10, Normal ≥ 7, Muted ≥ 4.5, Dim ≥ 3.0.

---

## What works well

These are load-bearing and should not be disturbed:

- **`PAGE_STACK` is real.** One vertical rhythm defined at `SharedWidgets_Layout.lua:377`, with legacy names aliased to it at `:389-406` so the copies cannot drift. 30 files consume it.
- **Title card and search box are genuinely shared** across all 12 main tabs — no tab hand-rolls its header.
- **`GetAAFlags` light-mode policy is correct** (`FontManager.lua:475`): THICKOUTLINE downgraded, achromatic ink gets no outline, colored ink keeps one. `IsInkNearBlack` (`:280`) makes that decision on measured luminance and saturation, not a guess.
- **In-place `COLORS` mutation with alias re-sync** (`ThemeAPI.SyncSemanticColorAliases`, `:1460`) means a theme toggle reaches live frames with zero allocation — the right architecture for a WoW addon.
- **Direct `SetTextColor` / `SetColorTexture` literals are nearly gone** — 13 across all of `Modules/UI`, concentrated in `PvEUI_VaultGrid.lua` (5). The recent token work landed. The remaining color debt is entirely in `|cff` markup, which that pass did not cover.

---

## Heaviest files

Composite drift = `|cff` literals + RGB table literals + local hex shims + 2-digit magic numbers in `SetPoint`/`SetSize`.
`SharedWidgets_Theme.lua` (123) and `SharedWidgets_ClassicTheme.lua` (36) are excluded — they *are* the palette.

| # | File | Total | `\|cff` | RGB | Shims | Magic |
|---|---|---:|---:|---:|---:|---:|
| 1 | `Modules/UI/PvEUI_VaultGrid.lua` | 54 | 38 | 8 | 8 | 0 |
| 2 | `Modules/UI/PlanCardFactory.lua` | 52 | 20 | 12 | 0 | 20 |
| 3 | `Modules/UI/PlansTrackerWindow.lua` | 45 | 19 | 10 | 0 | 16 |
| 4 | `Modules/UI/PvEUI.lua` | 42 | 29 | 6 | 1 | 6 |
| 5 | `Modules/UI/SettingsUI_Advanced.lua` | 40 | 28 | 3 | 0 | 9 |
| 6 | `Modules/UI/StatisticsUI.lua` | 37 | 7 | 1 | 6 | 23 |
| 7 | `Modules/UI/CharactersUI_Row.lua` | 31 | 9 | 13 | 0 | 9 |
| 8 | `Modules/UI/SharedWidgets.lua` | 31 | 5 | 16 | 2 | 8 |
| 9 | `Modules/UI/CharacterTrackingDialog.lua` | 30 | 12 | 8 | 2 | 8 |
| 10 | `Modules/UI/ReputationUI.lua` | 29 | 12 | 14 | 1 | 2 |

Notes on individual entries:
- `PvEUI_VaultGrid.lua` carries 8 local shims *and* 38 literals — it both built the abstraction and bypassed it. See `:138`, `:151`, `:243`, `:482`, `:487`.
- `StatisticsUI.lua` is magic-number-dominated, and inconsistent with itself: card inner padding is `15` at `:225`, `:239`, `:630` and `10` at `:289`, `:290`, `:319` — two gutters inside one card, neither equal to `PAGE_STACK.SIDE = 12`.
- `SharedWidgets.lua:2071` ships `BUTTON_BG_COLOR = {0.1, 0.1, 0.1, 1}` — a dark-only literal inside the token table itself, with no consumer anywhere in the repo.

---

## Önce bunlar

1. **Fix light-mode `gold`, `green`, and add `red`** — `SharedWidgets_Theme.lua:170-190`. Re-derive each from a 4.5:1 target against `bgCard` instead of lightening the dark value (F1, F2). Highest user-visible impact, smallest diff, and it unblocks the rest: once the palette is right, moving call sites onto it is mechanical.

2. **Promote `PLAN_UI_COLORS` to `ns.UI_HEX`** — `SharedWidgets_Theme.lua:1508`, synced in `SyncSemanticColorAliases` (`:1460`) (F4). This is the missing layer that caused F3 and F5. The pattern is already written and proven on one tab; generalizing it is the single change that removes the most duplication.

3. **Delete the 61 local `*Hex()` shims and the four `COLORS.red` bypasses** — starting with `SettingsUI_Advanced.lua` (29 literals, 0 helpers), then `PvEUI_VaultGrid.lua`, `PlanCardFactory.lua`, `PlansTrackerWindow.lua` (F3, F5, F2). Land a preflight check in the same change: a bare `|cff` under `Modules/UI/**` outside the two theme files is an error.

4. **Publish the `ROW_H` and `ICON` ladders and collapse the two section-header chevron tokens into one** — `SharedWidgets_Layout.lua:46-47`, `:88-90` (F6, F7). Migrate the twelve stray row heights and the off-scale `CELL_ICON = 39` onto rungs.

5. **Unify the search-box height and gutter rules** — one `SEARCH_HEIGHT` token read by both component and callers, symmetric insets in `SearchBoxComponent.lua:154-155`, and `PAGE_STACK.SIDE` as the only popup gutter (F8, F9). Sweep `WindowFactory.lua:456` first, since it is the shared factory setting a private fourth value.
