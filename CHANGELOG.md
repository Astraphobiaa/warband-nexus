# Changelog

All notable changes to **Warband Nexus** are documented here. In-game What's New uses locale key `CHANGELOG_V` + version without dots (e.g. `CHANGELOG_V2511` for 2.5.11).

## [2.5.11] - 2026-04-07

### PvE

- **Trovehunter's Bounty / Bountiful column**: Per-character snapshot from PvE cache per header row; live `IsQuestFlaggedCompleted` only for the current character when cache is missing. Alts without a snapshot show an em dash until logged in.
- **Midnight-safe quest checks**: `SafeIsQuestFlaggedCompleted` (pcall + `issecretvalue`) for weekly flags in `PvECacheService`.
- **Weekly quest IDs**: `PVE_BOUNTIFUL_WEEKLY_QUEST_IDS` is **86371 only** for Trovehunter tracking (removed OR with Cracked Keystone 92600 and Bountiful Delves 81514 to avoid false "complete").
- Bountiful column tooltip; `PVE_BOUNTY_NEED_LOGIN` (enUS) for missing alt snapshot.

### Collections

- **Achievements tab**: `GetCategoryNumAchievements(categoryID, true)` so all achievements in each category are enumerated (fixes only the last earned achievement appearing).
- **One-time migration**: `wnAchievementIncludeAllScanV1` + cleared achievement scan cooldown so a full re-scan runs once after update.

### Try Counter & data

- Mount/pet collected handling, missed-drop filtering, `C_Timer.After` callback fix (`TryDiscoverLockoutQuest`).
- **CollectibleSourceDB**: Lucent Hawkstrider `mountID` correction.

### UI

- **Plans / To-Do**: Try-count popup configurable; cards use left-click-only for try popup (no accidental right-click popup).
- **Information**: "Special Thanks" credits block (Contributors-style).

### Localization

- Credits / Special Thanks subtitle updates across locales; `PVE_BOUNTY_NEED_LOGIN` in enUS.

---

## [2.5.10] - 2026-04-04

- Tooltip "(Planned)" only when mount/pet/toy still missing; generic `item` drops align with collection APIs.

(See `CHANGES.txt` and older `CHANGELOG_V2510` in locales for full history.)
