## v3.5.18 (2026-10-12)

Centralized daily and weekly reset system, profession slot preservation and self-healing, and native in-game clock formatting.

### Added

- Added centralized daily and weekly reset management that automatically refreshes lockouts, plans, and quests on reset.

### Updated

- Updated reset countdowns and clock times to natively respect your in-game 12-hour or 24-hour time preferences.

### Fixed

- Fixed secondary profession slots occasionally being wiped from character data upon logout or partial background scans.
- Fixed switching between professions inside the Trade Skill window failing to track the newly selected profession.
- Fixed missing profession slots on alt characters by automatically reconstructing them from saved progression data.
- Fixed stale Mythic+ keystones and weekly lockouts failing to clear immediately when the weekly reset boundary passes.
- Fixed an infinite UI redraw loop occurring when opening the Professions tab.
- Fixed profession rows and column dividers failing to render completely on characters without scanned recipe data.
