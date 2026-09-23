## v3.5.10 (2026-09-24)

Weekly reset synchronization for PvE and professions, bank auto-deposit protections, and collapsed header preservation.

### Added

- Added an option in the bank deposit manager to protect raid/dungeon consumables and food from auto-deposits.

### Fixed

- Delve weekly tasks, world boss lockouts, and Mythic+ weekly run history now automatically clear upon weekly reset.
- Weekly profession quests and weekly knowledge point tracking now accurately reset on weekly reset.
- Preserved Blizzard UI collapsed header states across reputation and currency panels during background scans.
- Resolved an infinite notification loop and stale cache issue caused by expired mail.
- Refined Warbound-until-Equipped bank deposit filtering to prevent depositing non-matching equipment.
- Resolved a Lua error when generating Great Vault and PvE change signatures.
