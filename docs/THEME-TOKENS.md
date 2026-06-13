# Warband Nexus — Theme Tokens (Light / Dark)

Reference for `SURFACE_VARIANTS` and semantic helpers in `Modules/UI/SharedWidgets.lua`.

## Design intent

- **Dark mode:** frozen baseline; do not regress contrast or accent washes.
- **Light mode:** warm editorial off-white ladder (not clinical `#FFFFFF`), charcoal text, accent-tinted selection washes.

## Light surface ladder (WoW RGB 0–1)

| Token | RGBA | Reference HEX | Role |
|-------|------|---------------|------|
| `bg` | 0.848, 0.840, 0.828, 0.99 | ~#D8D6D3 | Main shell canvas |
| `surfaceViewport` | 0.872, 0.864, 0.852, 0.99 | ~#DEDCD8 | Scroll viewport |
| `bgLight` | 0.892, 0.886, 0.874, 0.99 | ~#E3E2DF | Raised panels |
| `bgCard` | 0.908, 0.902, 0.888, 0.99 | ~#E8E6E2 | Cards |
| `surfaceHeaderChrome` | 0.880, 0.874, 0.860, 0.99 | ~#E0DFDA | Section headers |
| `surfaceRowEven` | 0.900, 0.894, 0.880, 0.98 | ~#E5E4E0 | List stripe A |
| `surfaceRowOdd` | 0.862, 0.854, 0.838, 0.98 | ~#DCDAD5 | List stripe B |
| `borderLight` | 0.54, 0.54, 0.60, 1 | ~#8A8A99 | UI strokes (WCAG 1.4.11 target) |
| `tabInactive` | 0.858, 0.850, 0.836, 1 | ~#DBD9D5 | Idle sub-tab |

## Light text roles

| Token | RGB | Reference HEX | Min contrast target |
|-------|-----|---------------|---------------------|
| `textBright` | 0.12, 0.12, 0.14 | #1F1F24 | Primary labels (AA 4.5:1 on canvas) |
| `textNormal` | 0.24, 0.24, 0.28 | #3D3D47 | Body |
| `textMuted` | 0.38, 0.38, 0.42 | #61616B | Secondary |
| `textDim` | 0.50, 0.50, 0.54 | #808089 | Hints / disabled |

## Semantic (light)

| Token | Notes |
|-------|-------|
| `gold` | Darkened for broken-white backgrounds |
| `green` / `red` | Status chips — no white label text on light fills |
| `UI_GetSemanticPositiveCard` / `Negative` | Tracking yes/no cards |

## Markup helpers

| Export | Use |
|--------|-----|
| `UI_GetTextRoleHex(role)` | `\|cff` prefix for Bright/Normal/Muted/Dim |
| `UI_GetPlanUIColor(key)` | Plan card markup (`PLAN_UI_COLORS`, synced on refresh) |
| `UI_GetSemanticGoldHex` | Titles, rewards |
| `UI_GetQualityHex(tier)` | Item quality (game hues preserved) |

## Documented exceptions (do not theme-remap)

- WoW item **quality** `|cff` colors
- **Class / spec** colors from Blizzard APIs
- Plan **completed** green (`progressFull`, `completed`)
- **Money** silver/copper coin colors in `FormatMoney`
- **Disabled** UI (WCAG exempt for inactive components)
- **Chat / debug** markup in `TryCounterService*`, `Profiler` (dark chat/console background)
- **M+ score tier** white bracket in `PvEUI` dark mode (`PveMplusScoreColor500`)

## Refresh pipeline

1. `db.profile.themeMode` change
2. `UpdateColorsFromTheme()` + `SyncPlanUIColors()`
3. `UI_RefreshColors()` → `BORDER_REGISTRY`, open tabs
4. `FontManager:RefreshThemeTypography()` — light uses soft shadow, not OUTLINE

Verify pairs with [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) when adjusting tokens.
