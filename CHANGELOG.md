## v3.5.3 (2026-08-17)

### Updated

- Crest tracking now follows the active season automatically. Season 2 Mistcrests replace Season 1 Dawncrests in the Gear and PvE tabs, and future seasons will switch over on their own instead of waiting for an addon update.
- Gear upgrade tracks now use Season 2 item levels, so upgrade steps and costs read correctly on Season 2 gear.
- The Currencies tab now refreshes Blizzard's category tree after a game patch. Categories added in 12.1, such as Crests and Professions, no longer stay missing until a manual rescan.
- Currencies retired by a season change are no longer kept in the list forever.
- The Gilded Stash weekly count now shows the correct 3 per week for patch 12.1.
- Currency tooltips now always list your current character, even at zero, so an empty balance is no longer indistinguishable from missing data.

### Fixed

- Try counters for one-time collectibles no longer reset when you finally obtain them, so the number of tries it took stays on the card instead of dropping to zero. Repeatable drops still reset as before.
- Fixed try counters resetting from the wrong source when a drop credits its tries to another collectible, such as Crackling Shard counting toward Alunira.
- The obtained message in chat now only claims the counter was reset when it actually was.
- Fixed localized upgrade track names failing to resolve, which could leave gear rows without a track label.
