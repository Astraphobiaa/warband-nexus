# Warband Nexus – WoW Events Audit

This document lists every WoW event and chat filter used by the addon (Core, Modules; Config.lua does not register events). It ensures correct WoW API usage and notes taint-safe behavior.

---

## 1. Event registration summary

| Event | Where registered | Frame / object | Notes |
|-------|------------------|----------------|-------|
| **ADDON_LOADED** | libs/AceAddon | AceAddon.frame | Library |
| **PLAYER_LOGIN** | libs/AceAddon, LibDBIcon | AceAddon.frame, frame | Library |
| **PLAYER_LOGOUT** | Core, libs/AceDB | WarbandNexus (AceEvent), AceDB.frame | Session save; AceDB save |
| **PLAYER_ENTERING_WORLD** | Core (raw frame + AceEvent), PlansManager, VaultScanner, ChatThrottleLib | _rawEventFrame, WarbandNexus, scannerFrame, lib | Raw frame for early save; AceEvent for notifications |
| **PLAYER_LEAVING_WORLD** | TooltipService | WarbandNexus | Hide tooltip on logout |
| **PLAYER_REGEN_DISABLED** | Core, TooltipService | WarbandNexus | Combat start; hide UI + tooltip |
| **PLAYER_REGEN_ENABLED** | Core | WarbandNexus | Combat end; restore UI |
| **PLAYER_MONEY** | Core, CurrencyCacheService, DataService | WarbandNexus, CurrencyCache, DataService | Gold + currency scan |
| **ACCOUNT_MONEY** | Core | WarbandNexus | Warband bank gold |
| **BANKFRAME_OPENED** | Core, ItemsCacheService | WarbandNexus | Bank open |
| **BANKFRAME_CLOSED** | Core, ItemsCacheService | WarbandNexus | Bank close |
| **GUILDBANKFRAME_OPENED** | Core | WarbandNexus | Only if ENABLE_GUILD_BANK (10.0+ may not fire) |
| **GUILDBANKFRAME_CLOSED** | Core | WarbandNexus | Only if ENABLE_GUILD_BANK (10.0+ may not fire) |
| **GUILDBANKBAGSLOTS_CHANGED** | Core | WarbandNexus | Guild bank slots (if ENABLE_GUILD_BANK) |
| **PLAYERBANKSLOTS_CHANGED** | Core | WarbandNexus | Bucket 0.5s |
| **BAG_UPDATE** | Core, EventManager, ItemsCacheService | WarbandNexus (bucket 0.15s) | Throttled; EventManager replaces with OnBagUpdateThrottled |
| **BAG_UPDATE_DELAYED** | Core, EventManager | WarbandNexus | Bags + collectibles + keystone |
| **CURRENCY_DISPLAY_UPDATE** | Core, CurrencyCacheService | WarbandNexus, CurrencyCache | Currency changes |
| **UPDATE_FACTION** | ReputationCacheService (dedicated frame), EventManager, ModuleManager | eventFrame (CreateFrame), WarbandNexus | Snapshot-diff on dedicated frame to avoid AceEvent collision |
| **MAJOR_FACTION_RENOWN_LEVEL_CHANGED** | ReputationCacheService (dedicated frame), EventManager, ModuleManager | eventFrame, WarbandNexus | Renown |
| **MAJOR_FACTION_UNLOCKED** | EventManager, ModuleManager | WarbandNexus | Major faction unlock |
| **QUEST_TURNED_IN** | ReputationCacheService, DailyQuestManager | WarbandNexus | Rep diff + daily quest |
| **QUEST_LOG_UPDATE** | DailyQuestManager | WarbandNexus | Daily quest list |
| **NEW_MOUNT_ADDED** | Core (inline), EventManager (replaces with debounced) | WarbandNexus | EventManager wins (debounced) |
| **NEW_PET_ADDED** | Core, EventManager | WarbandNexus | Same |
| **NEW_TOY_ADDED** | Core, EventManager | WarbandNexus | Same |
| **TRANSMOG_COLLECTION_UPDATED** | Core, EventManager | WarbandNexus | Same |
| **ACHIEVEMENT_EARNED** | Core, CollectionService, PlansManager | WarbandNexus | Notifications + plans |
| **PET_JOURNAL_LIST_UPDATE** | EventManager | WarbandNexus | Debounced |
| **UI_SCALE_CHANGED** | EventManager, SharedWidgets | WarbandNexus, scaleHandler, scaleWatcher | UI scale refresh |
| **DISPLAY_SIZE_CHANGED** | EventManager, SharedWidgets | WarbandNexus, scaleHandler | Resolution change |
| **SKILL_LINES_CHANGED** | EventManager, DataService | WarbandNexus, DataService | Professions |
| **TRADE_SKILL_SHOW** | EventManager, DataService | WarbandNexus, DataService | Profession UI |
| **TRADE_SKILL_DATA_SOURCE_CHANGED** | EventManager | WarbandNexus | Profession data |
| **TRADE_SKILL_LIST_UPDATE** | EventManager | WarbandNexus | Profession list |
| **TRAIT_TREE_CURRENCY_INFO_UPDATED** | EventManager | WarbandNexus | Profession currency |
| **PLAYER_EQUIPMENT_CHANGED** | EventManager, DataService | WarbandNexus, DataService | Item level |
| **PLAYER_AVG_ITEM_LEVEL_UPDATE** | EventManager | WarbandNexus | Item level |
| **CHALLENGE_MODE_KEYSTONE_SLOTTED** | EventManager | WarbandNexus | M+ keystone |
| **MYTHIC_PLUS_CURRENT_AFFIX_UPDATE** | EventManager, PvECacheService | WarbandNexus, PvECacheService | M+ affixes |
| **CHALLENGE_MODE_COMPLETED** | Core (via ModuleManager), PlansManager, PvECacheService | WarbandNexus, PvECacheService | M+ completion |
| **WEEKLY_REWARDS_UPDATE** | Core (ModuleManager), PlansManager, VaultScanner, PvECacheService | WarbandNexus, scannerFrame, PvECacheService | Vault |
| **WEEKLY_REWARDS_ITEM_CHANGED** | PvECacheService | PvECacheService | Vault item |
| **UPDATE_INSTANCE_INFO** | ModuleManager, PvECacheService | WarbandNexus, PvECacheService | Instance/lockouts |
| **MYTHIC_PLUS_NEW_WEEKLY_RECORD** | PvECacheService | PvECacheService | M+ record |
| **ENCOUNTER_END** | PlansManager | WarbandNexus | Plans/vault |
| **PLAYER_LEVEL_UP** | DataService | DataService | Level |
| **PLAYER_SPECIALIZATION_CHANGED** | DataService | DataService | Spec |
| **PLAYER_UPDATE_RESTING** | DataService | DataService | Rest state |
| **ZONE_CHANGED** | DataService | DataService | Zone |
| **ZONE_CHANGED_NEW_AREA** | DataService | DataService | Area |
| **CHAT_MSG_ADDON** | libs/AceComm | AceComm.frame | Library |

---

## 2. Chat message event filters (non-tainting)

Filters use `ChatFrame_AddMessageEventFilter`. They only return `true` or `false` and do not modify message or other arguments.

| Chat event | File | Behavior | Taint |
|------------|------|----------|--------|
| **CHAT_MSG_COMBAT_FACTION_CHANGE** | ReputationCacheService.lua | Return `true` to suppress Blizzard message when tracking and snapshot ready; else `false`. | Safe: no Blizzard frame/state changed. |
| **CHAT_MSG_CURRENCY** | CurrencyCacheService.lua | Always return `false` (allow message); timer triggers full scan. | Safe: read-only + timer. |

Filter signature used: `function(self, event, message, ...)` (WoW passes frame as first arg). No modification of `message` or return of modified args.

---

## 3. Taint and safety

- **Combat:** `OnCombatStart` (PLAYER_REGEN_DISABLED) only hides the addon’s own `mainFrame`; no Blizzard secure frames or attributes are changed. `OnCombatEnd` restores it. No protected functions are called from event handlers in combat.
- **Frames:** All addon event frames are created with `CreateFrame("Frame")` (non-secure). ReputationCacheService uses a dedicated `CreateFrame("Frame")` for `UPDATE_FACTION` and `MAJOR_FACTION_RENOWN_LEVEL_CHANGED` to avoid AceEvent’s single-handler-per-object behavior.
- **Chat filters:** Only boolean return; no UIFrameFlash or other chat frame manipulation. Minimal execution path.
- **TooltipService:** Uses `TooltipDataProcessor` (TWW) where documented as taint-safe; combat/world leave only call addon’s `Hide()`.

---

## 4. Known API / behavior notes

- **GUILDBANKFRAME_OPENED / GUILDBANKFRAME_CLOSED:** In WoW 10.0+ these events may not fire (Blizzard bug). Addon still registers them when `ENABLE_GUILD_BANK` is true. `GUILDBANKBAGSLOTS_CHANGED` still fires when guild bank opens.
- **AceEvent:** One handler per event per object. Core and EventManager both register on `WarbandNexus`; InitializationService runs EventManager after Core, so EventManager’s debounced/throttled handlers replace Core’s for collection/bag events as intended.
- **PLAYER_ENTERING_WORLD:** Fired for both login and reload. Core uses a raw frame for early save logic and AceEvent for notifications; ReputationCacheService does not register this on WarbandNexus (to avoid overwriting Core’s handler) and builds snapshot via a 2s timer and after FullScan.

---

## 5. Config.lua

Config.lua does not call `RegisterEvent` or `RegisterBucketEvent`. No events are registered there.

---

*Last audit: 2026-02-06. Re-check when adding or changing event registration.*
