## v3.5.17 (2026-10-11)

Profession and concentration tracking persistence, try counter encounter accuracy, and container counting improvements.

### Fixed

- Fixed profession and concentration tracking on alt characters being wiped after logging out.
- Fixed offline alt character concentration bars and recharge timers failing to display when the Midnight filter is active.
- Fixed try counting for dungeon and raid bosses when encounter end and boss kill events both fire.
- Fixed boss try counting double-counting if a boss corpse is looted after the fallback tracker already registered the kill.
- Fixed container try counting incrementing when an item was not actually consumed.
- Fixed login statistic sync unintentionally increasing try counts for already-collected mounts.
- Fixed fishing casts in Oceanic Vortex incorrectly counting towards Nether-Warped Egg tries.
- Fixed raid and dungeon lockout tracking when targeting a tracked rare or boss.
