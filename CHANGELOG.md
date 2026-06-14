# Warband Nexus — Release notes

Canonical source for CurseForge / Wago uploads (BigWigs packager `manual-changelog`).
Mirror the same bullets in `Locales/*/CHANGELOG_V*` for in-game What's New.

**Release ritual:** prepend a new `## vX.Y.Z (date)` section below; keep older sections for history.

## v3.1.8 (2026-06-14)

### Added

- Light mode accessibility option: choose Light or Dark under Settings > Theme & Appearance > Light / Dark.

### Fixed

- Tooltips: corrected secret-value taint errors and improved readable line colors in Light mode.
- Professions: concentration, knowledge, and recipe data save reliably when you close the profession window or log out.
- Saved data: login cleanup no longer deletes Warband Bank storage or alt character progress between sessions.
- Characters, Currency, PvE, Reputation, and Statistics tabs no longer fail to draw after internal UI refactors.

### Updated

- UI polish across tabs for Light mode surfaces, row highlights, icons, and scroll chrome.
- Collections browse: pinned sub-tab headers and faster list refresh when revisiting mounts, pets, toys, and achievements.
- Items Storage tab builds large Warband trees in stages to reduce tab-switch spikes.

## v3.1.7 (2026-06-06)

### Fixed

- Gear tab: recommended storage no longer stuck in a "Scanning storage..." loop or flashing results away after item info loads.
- PvE tab: alt currency, vault, crest, coffer, and try-counter progress no longer lost after logout or character-key cleanup.
- Plans To-Do: "Show Planned" checkbox now behaves correctly when unchecked on To-Do List and Weekly Progress (browse tabs unchanged).
- Search: checkbox and filter state standardized across Collections, Gear, Currency, and related browse lists.
- Collections: scroll area and list height corrected so content is not clipped; resize drag no longer causes list/preview flicker.
- UI scroll: virtual lists and scroll chrome aligned on Achievement browse, Collections, Currency, Reputation, and Professions tabs.

### Updated

- Saved-data pipeline: character cache migrations and database cleanup run more safely so progress rows are not dropped by mistake.
- Collection browse: mount/pet/toy lists and model panel refresh more reliably after search and filter changes.
