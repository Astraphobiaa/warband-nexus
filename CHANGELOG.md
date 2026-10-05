## v3.5.15 (2026-10-05)

Container try counter enhancements, multi-event loot tracking, and hierarchy ordering fixes.

### Added

- Added container try count support for holiday chests, paragon caches, and reward bags with drop percentage display.
- Added comprehensive drop tracking for Keg-Shaped Treasure Chest items including the Brewfest Barrel Bomber, Great Brewfest Kodo, and Swift Brewfest Ram.

### Fixed

- Fixed container try counting failing when items or currencies unpack directly into bags without opening a loot window.
- Fixed an issue where container drops were filtered out by chat loot fast-bail checks.
- Fixed faction hierarchy ordering to ensure follower reputations and sub-factions group correctly under their parent headers.
- Fixed visual overlap in the currency view between the search bar and category header text.
- Fixed warband bank reagent deposit filtering to exclude soulbound and non-reagent items.
