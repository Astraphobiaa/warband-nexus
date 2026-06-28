## v3.2.2 (2026-06-28)

### Added

- Characters, Professions, PvE, and Storage: sort character lists by class from the filter/sort menu.
- Settings: optional toggle to show or hide the numeric item ID at the bottom of item tooltips (enabled by default).
- PvE: Current and Weekly currency column views; click header cells to switch, or hold Shift to preview the other view.

### Updated

- Tab title bars: shared toolbar button styling and consistent layout across PvE, Items, To-Do, Gear, Currency, and Professions.
- Gold Manager: summary preview updates live when target amount, mode, or per-character settings change.
- Item tooltips: WN item counts grouped under Current Character, Alt Characters, Warband Bank, and Guild Bank headers.
- Character sorting: one shared sort engine for Characters, Professions, PvE, and Storage (name, class, level, ilvl, gold, realm, manual order).
- Currency cache: more reliable GUID-backed character binding for account transfers and cross-character totals.

### Fixed

- PvE: Favorites and Characters section expand/collapse state persists correctly after reload.
- Reputation: startup loading no longer stuck on the first progress track.
- Currency: quantities match the correct character when saved data uses GUID roster keys.
- Character Bank Money Logs: scroll bar no longer overlaps transaction rows.
