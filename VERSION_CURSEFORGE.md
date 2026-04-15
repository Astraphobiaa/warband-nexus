# CurseForge / Wago — **Warband Nexus v2.5.15-beta1** (2026-04-15)

## Summary for project description / changelog field

**v2.5.15 beta 1 (pre-release)** — Performance: main-window populate coalescing, tab-switch debounce, CollectionService budgeted scans, guild bank + bank-open chunked scans, Plans grid precompute, collections abort. Bug fixes: TOC loads `Config.lua` after `Constants.lua`; main frame OnHide clears populate timer. Localization: gear crafted lines, concentration timers, Steam-style played time; locale parity for `GEAR_CRAFTED_*`, `STATS_PLAYED_STEAM_*`, `PROF_CONCENTRATION_*` across supported languages. **Feedback welcome** before the stable 2.5.15 build.

## Full notes

### Performance

- **UI (`Modules/UI.lua`)**: `SchedulePopulateContent` debounce; `OnHide` timer cancel; single defer on tab switch; badge-only currency/reputation when off-tab.
- **CollectionService**: `ScheduleEnsureCollectionDataDeferred`; `ScanCollection` / `BuildFullCollectionData` use `FRAME_BUDGET_MS`.
- **Guild bank & ItemsCache**: chunked scans; atomic tab assign; invalidate on close.
- **Plans & Collections**: `regularCountBefore` O(n); `AbortCollectionsChunkedBuilds`; Core abort.

### Bug fixes

- **TOC**: `Config.lua` after `Modules/Constants.lua` (fixes `ns.Constants` at Config init).
- **Main `OnHide`**: populate timer cleared after cancel.

### Localization

- **GearUI**, **ProfessionService**, **StatisticsUI** keys; multi-locale parity (see CHANGELOG.md).

---

Package: `WarbandNexus-2.5.15-beta1.zip` from `python build_addon.py` at repo root. **`/reload`** after installing.
