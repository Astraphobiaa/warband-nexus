# Changelog

All notable changes to **Warband Nexus** are documented here. In-game What's New uses locale key `CHANGELOG_V` + version without dots (e.g. `CHANGELOG_V2512` for 2.5.12).

## [2.5.12] - 2026-04-12

### UI

- **Notifications settings**: Try counter chat output dropdown opens **downward** with reserved vertical space so the open menu no longer overlaps the label or checkbox grid. Options use a **fixed route order** (Loot → dedicated Warband Nexus group → all standard tabs) instead of locale-sorted text.

### Bug fixes

- **GameTooltip:SetText**: Settings, Gold Management popup, and Plans UI pass numeric alpha only (Midnight-safe; fixes `bad argument #5 to 'SetText'`).

### Try Counter

- **Instance entry [WN-Drops]**: Drop list vs short hint uses consistent trackable / mount logic for difficulty messaging.
- **Manual drops / Rarity**: Non-repeatable collectibles already owned do not advance or inflate try counts from Rarity sync.

### Tooltips & collections

- Collectible/drop handling and DB alignment with Midnight `issecretvalue` patterns where touched in this release.

### Localization

- Locale key parity with enUS; shorter **[WN-TC]** probe format in chat.

---

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
