# Classic Theme Architecture

Warband Nexus **Classic** (`db.profile.themeMode == "classic"`) uses literal Blizzard FrameXML chrome instead of custom flat fills.

## Shell layers (main window)

| Layer | Frame | Classic behavior |
|-------|-------|------------------|
| Outer | `WarbandNexusFrame` | `SetClipsChildren(true)` |
| Dialog tile | `_wnClassicShellChrome` | `UI_ApplyBlizzardDialogBackdrop` — full bleed on root; decorative border is part of the backdrop texture |
| Header | `header` | Transparent (`UI_ApplyClassicInteriorFlatFill` alpha 0) — title/icons only |
| Nav rail | `navRail` | Transparent — Blizzard dialog bg shows through |
| Body | `content` | Transparent + `SetClipsChildren(true)` |
| Viewport | `viewportBorder` | Transparent — no WHITE8x8 fill, no viewport atlas underlay |
| Tabs | nav buttons | `UIPanelButtonTemplate` via ClassicFactory |

## Layout insets (classic vs dark/light)

**Dark/light:** `MAIN_SHELL.INTERIOR_INSET_*` are **0** (full-bleed interior; footer uses `INTERIOR_INSET_BOTTOM = 4`).

**Classic:** `UI_GetMainShellFrameInsets()` (`SharedWidgets_ClassicTheme.lua`) returns Blizzard dialog tile insets from `UI_CLASSIC_DIALOG_BACKDROP.insets`:

| Edge | px | Source |
|------|-----|--------|
| Left | 11 | `UI-DialogBox-Border` tile margin |
| Right | 12 | asymmetric Blizzard art |
| Top | 12 | |
| Bottom | 11 | |

`UI_ApplyMainShellLayout` anchors header, nav rail, content, footer, and resize grip inside this inner rect so opaque tab/viewport fills cannot paint into the decorative border zone.

## Interior transparency helpers

- `UI_ApplyClassicInteriorFlatFill(frame, {0,0,0,0})` — WHITE8x8 backdrop at alpha 0
- `UI_ApplyClassicTransparentInterior(frame)` — above + hides `_wnViewportAtlasUnderlay` / `_wnShellFill`

## Row striping

Classic list rows use `ApplyRowBackground` at **22%** of tier alpha so subtle zebra striping remains without a grey viewport slab.

## Related files

- `Modules/UI/SharedWidgets_ClassicTheme.lua` — backdrop tables, inset resolver, transparency helpers
- `Modules/UI.lua` — `CreateMainWindow`, `RefreshMainShellChrome`, `ApplyMainShellLayout`
- `Modules/UI/ClassicFactory.lua` — Blizzard template widgets
- `docs/CLASSIC-THEME-GAPS.md` — phased rollout tracker
