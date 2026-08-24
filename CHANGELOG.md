## v3.5.6 (2026-08-24)

Two new PvE weekly columns for patch 12.1, plus fixes for characters quietly losing their Tracking setting or their item level.

### Added

- The PvE tab can show two more weeklies: "A Nightmarish Task" and "Purging the Vaults". Both award a Trovehunter's Bounty, and both work like the existing Bounty column - a tick per character with a hover tooltip - and can be turned off from the Columns menu.
- Both weeklies can now be picked as objectives in Weekly Progress.

### Fixed

- Characters could quietly lose their Tracking setting between sessions. When it happened, that character stopped collecting data entirely - currency messages in chat were only the most visible symptom - and turning Tracking back on did not survive the next login. It hit a different character each time, depending on login timing.
- Item level could freeze at an old number on a single character and never move again, no matter how many times you logged out, changed gear or reloaded.
- Item level is now consistent everywhere it is shown; some places rounded up while others rounded down, so the same character could appear one level apart in two windows.
