## v3.3.7 (2026-07-22)

### Added

- The try counter self-test (/wn tc test) now cross-checks its tracked boss data against the raid or dungeon you are standing in, and reports a mismatch instead of quietly passing.

### Updated

- Attempt counters now re-read WoW Statistics once a day. Attempts missed while you were in a cutscene, disconnected or otherwise untracked are repaired on their own, with no need to reset anything by hand.

### Fixed

- Fixed Mythic Sylvanas Windrunner kills never counting toward the Vengeance's Reins attempt counter. Both the Sanctum of Domination raid and the treasure chest that appears after her defeat were stored under the wrong IDs, so no kill and no chest was ever matched. The chest is now also correctly limited to Mythic, where the mount can actually drop.
- Fixed attempts being lost during long cinematics after a boss dies: a kill is no longer forgotten while the game briefly reports your location as unknown.
- Fixed raid-only mounts gaining attempts from Mythic+ runs when a dungeon boss shares its ID with the raid encounter, which affected Ashes of Belo'ren from Midnight Falls.
- Fixed attempts not being counted when the game reports an unknown difficulty in the moments right after a boss dies.
- Fixed attempt counters staying stuck for a full day when the first read of WoW Statistics came back empty.
