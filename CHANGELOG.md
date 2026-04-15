# Changelog

All notable changes to **Warband Nexus** are documented here. In-game What's New uses locale key `CHANGELOG_V` + the numeric `x.y.z` only (e.g. `2.5.15-beta1` → `CHANGELOG_V2515`).

## [2.5.15-beta1] - 2026-04-15

_Pre-release (beta 1); not a final stable build._

### Performance

- **UI (`Modules/UI.lua`)**
  - **`SchedulePopulateContent`**: Debounce timer resets on each schedule (coalesced “last event wins”); `pendingPopulateSkipCooldown` OR-merge when `skipCooldown` (profession events bypass cooldown safely).
  - **`OnHide`**: Cancel populate timer; clear `pendingPopulateSkipCooldown`; `populateDebounceGen` invalidates any deferred callback (covers `C_Timer.After` fallback); store `After` return value when it exposes `:Cancel`.
  - **Main tab switch**: Single `C_Timer.After(0)` — pre-clear scroll child (pool + recycle), `PopulateContent`, then `isMainTabSwitch = false` (no chained nested defers).
  - **`PopulateContent`**: `UpdateTabButtonStates` only when not `isMainTabSwitch` (tab buttons already updated on click).
  - **`WN_CURRENCY_UPDATED`**: `SchedulePopulateContent` on currency/gear tab only; else `UpdateTabCountBadges("currency")`.
  - **`WN_REPUTATION_UPDATED` / `WN_REPUTATION_CACHE_READY`**: `UpdateTabCountBadges("reputations")` when not on reputations tab; no extra `PopulateContent` on that tab (ReputationUI owns redraw).
- **CollectionService**
  - **Post-scan debug**: Per-category cache key dump runs only when **debug verbose** is on (avoids `pairs` over all categories when verbose is off).
  - **`ScheduleEnsureCollectionDataDeferred`**: One next-frame coalesced `EnsureCollectionData`; `ns.ScheduleEnsureCollectionDataDeferred` exported.
  - **Empty-store getters**: All former `C_Timer.After(0, EnsureCollectionData)` paths use the scheduler.
  - **`ScanCollection`**: Coroutine resume loop budgeted with `FRAME_BUDGET_MS` (replaces `NewTicker(0.1)`).
  - **`BuildFullCollectionData`**: Batch slice uses `FRAME_BUDGET_MS` instead of a hardcoded 6 ms.
- **Guild bank & items cache**
  - **`GuildBankScanner`**: Frame-budget chunked scan; per-tab `tabItemsBuilding` then atomic assign; generation counter; `InvalidateGuildBankScan`; `Core:OnGuildBankClosed` invalidates in-flight work.
  - **`GuildBankScanner`**: Scan trace / completion logs use **debug verbose**; `GroupItemsByCategory` uses numeric `for` (no `ipairs`).
  - **`ItemsCacheService`**: `RunBudgetedBankOpenScan` — one bag per frame for inventory → bank → warband on bank open; `bankScanInProgress`; stop if bank closes during pipeline.
  - **`ItemsCacheService`**: `BAG_UPDATE` / bank open-close trace lines are **debug verbose** (high-frequency events).
- **Plans, Collections, Core**
  - **`PlansUI`**: `regularCountBefore` precompute for 2-column layout (O(n) vs O(n²) inner loop per card).
  - **`CollectionsUI`**: `AbortCollectionsChunkedBuilds` (mount/pet/toy draw gens).
  - **`Core` `AbortTabOperations`**: `collections` tab triggers `AbortCollectionsChunkedBuilds` (alongside existing plans/reputation/currency aborts).
- **Documentation**
  - **`docs/QUEUE_REVISION_CHECKLIST.md`**: Midnight/taint, timers, lifecycle, `Constants.EVENTS`, smoke tests, before/after table.

### Bug fixes

- **`WarbandNexus.toc`**: `Config.lua` after `Modules/Constants.lua` (fixes `ns.Constants` nil in `Config.lua` and `InitializeConfig` missing at init).
- **Main `OnHide`**: Populate timer cleared robustly after cancel.

### Localization

- **`GearUI`**: `LocalizeUpgradeTrackName` for paperdoll + tooltips (normal upgrades, crafted/recraft); maps to `PVE_CREST_*` including new **`PVE_CREST_EXPLORER`** (zhCN/zhTW 探索者; other locales keyed).
- **`GearUI` (follow-up)**: Crafted-item tooltip strings use **`GEAR_CRAFTED_*`** keys (max ilvl, recast line, Dawncrest cost, next-tier crests); **`GEAR_TRACK_CRAFTED_FALLBACK`** for the word “Crafted”.
- **`ProfessionService`**: `GetConcentrationTimeToFull` / `GetConcentrationTimeToFullDetailed` use **`PROF_CONCENTRATION_*`**.
- **`StatisticsUI`**: Steam-style “most played” time format uses **`STATS_PLAYED_STEAM_*`** instead of hardcoded `"Hours"`.
- **Locale parity**: **`GEAR_CRAFTED_*`**, **`STATS_PLAYED_STEAM_*`**, **`PROF_CONCENTRATION_*`** filled for de, fr, es, es-mx, it, pt, ru, ko, zhTW (in addition to enUS/zhCN coverage noted above).

---

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
