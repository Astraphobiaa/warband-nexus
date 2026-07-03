# Warband Nexus — File Map

**How to use this document:** every shipped Lua file has a **Tag**. When you want work done, reference the tag instead of guessing file names. Examples:

- `[UI-TAB:Currency] the totals column is misaligned`
- `[SERVICE:CurrencyCache] currency numbers wrong after login`
- `[UI-POPUP:MailDetails] popup is too narrow`
- `[WIDGET:SharedWidgets] make section headers taller`

If you are not sure which tag applies, use the **"When you want X, tag Y"** table at the bottom — it maps common requests to the right tags. Tagging is a hint, not a contract: the agent will still confirm the correct layer before editing.

Counts (Lines / Locals / Health) were measured for v3.2.3 and drift over time — the tags and roles are the stable part.

---

## Legend — layer tags

| Tag prefix | Meaning |
|---|---|
| **ENTRY** | Addon bootstrap (`Core.lua`) — initialization and lifecycle only, no feature logic. |
| **DATA** | Database shape: defaults, migrations, DB maintenance, and shipped static catalogs (quest/zone/collectible data). |
| **SERVICE** | Domain logic: listens to Blizzard events, writes the database, then announces changes via `WN_*` messages. Never touches the UI directly. |
| **CACHE** | A special kind of service that scans game data and keeps a persistent snapshot (currency, reputation, PvE, items). |
| **MANAGER** | Cross-cutting coordinators: plans, notifications, windows, modules, events. |
| **UI-SHELL** | The main window itself: shell, tab routing, refresh plumbing, layout, dialog builder. |
| **UI-TAB** | One main-window tab (Characters, Currency, Storage, PvE, ...). |
| **UI-SAT** | Satellite slice of a tab — the tab's code split across files (`_Draw`, `_Lists`, `_Chrome`, ...) because of Lua limits. |
| **UI-POPUP** | Standalone floating windows and dialogs (trackers, detail popups, Easy Access button). |
| **WIDGET** | Reusable UI building blocks: SharedWidgets, factories, pools, fonts. All tabs are built from these. |
| **HELPER** | Pure utilities: formatters, constants, classification rules. No events, no frames. |
| **DEBUG** | Developer tooling: profiler, debug commands, self-tests. Safe to ignore for features. |

**Health column:** `OK` = comfortable. `WATCH` = large file (over 2,500 lines or 100+ top-level locals) — edits should be surgical. `HOT` = at Lua 5.1 limits (over 4,000 lines or 150+ locals) — must not grow; new code goes into a satellite file.

---

## Third-party & translations (summary rows)

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `embeds.xml` + `Libs/**` | *(external)* | Ace3 and other third-party libraries — never edited by hand. | — | — | — |
| `Locales/*.lua` (11 files) | **HELPER:Locales** | All player-visible text. `enUS.lua` is the source of truth; the other 10 mirror its keys. | — | — | — |

---

## ENTRY

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Core.lua` | **ENTRY:Core** | Addon startup: creates the AceAddon, loads the database, wires modules together. Feature logic does not belong here. | 1873 | 12 | OK |

---

## DATA — database & shipped catalogs

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Config.lua` | **DATA:Config** | Legacy Blizzard options panel (AceConfig) + profile management. The modern in-addon settings live in UI-TAB:Settings. | 1527 | 12 | OK |
| `Modules/MigrationService.lua` | **DATA:Migration** | Upgrades saved data between addon versions. The only place allowed to change DB shape. | 1931 | 32 | OK |
| `Modules/DatabaseOptimizer.lua` | **DATA:DbOptimizer** | SavedVariables cleanup, cache backup/reset, optional login trim. | 747 | 6 | OK |
| `Modules/DatabaseCleanup.lua` | **DATA:DbCleanup** | Removes duplicate characters and deprecated storage from the DB. | 201 | 5 | OK |
| `Modules/CollectibleSourceDB.lua` | **DATA:CollectibleSources** | Shipped database of where mounts/pets/toys drop (NPCs, rares, fishing, containers) — feeds Try Counter and tooltips. | 2630 | 18 | WATCH |
| `Modules/Data/MidnightQuestCatalog.lua` | **DATA:QuestCatalog** | Curated Midnight weekly quests and content events for the Weekly Progress picker. | 197 | 10 | OK |
| `Modules/Data/ReminderMapContent.lua` | **DATA:ReminderMapContent** | Live map-scan of quest activity for Set Alert reminders. | 267 | 12 | OK |
| `Modules/Data/ReminderWorldQuestIndex.lua` | **DATA:ReminderWQIndex** | Per-zone world-quest scan index used by the Set Alert quest picker. | 537 | 18 | OK |
| `Modules/Data/ReminderMidnightFactionEmissaryData.lua` | **DATA:ReminderEmissary** | Shipped list of Midnight faction emissary world quests. | 98 | 4 | OK |
| `Modules/Data/ReminderMidnightWorldQuestData.lua` | **DATA:ReminderWQData** | Shipped Midnight world-quest catalog (generated from the wiki). | 108 | 1 | OK |
| `Modules/Data/ReminderWorldQuestCatalog.lua` | **DATA:ReminderWQCatalog** | Maintained world-quest list so the picker shows known WQs even when not currently active. | 292 | 6 | OK |
| `Modules/Data/ReminderHolidayEventCatalog.lua` | **DATA:ReminderHolidays** | Calendar holidays/world events for Set Alert (Darkmoon, micro-holidays, ...). | 270 | 17 | OK |
| `Modules/Data/ReminderQuestCatalog.lua` | **DATA:ReminderQuestCatalog** | Flat quest/event lists shown in the Set Alert dialog. | 245 | 9 | OK |
| `Modules/Data/ReminderQuestPickerCatalog.lua` | **DATA:ReminderQuestPicker** | Left-nav sections and grouping for the Set Alert quest picker. | 221 | 15 | OK |
| `Modules/Data/ReminderContentIndex.lua` | **DATA:ReminderContentIndex** | Single source of truth for reminder zone-picker rows (all expansions/continents). | 896 | 25 | OK |
| `Modules/Data/UIMapContentKind.lua` | **DATA:MapContentKind** | Classifies a map ID as zone/dungeon/raid/delve for the zone picker. | 242 | 13 | OK |
| `Modules/Data/ReminderZoneCatalog.lua` | **DATA:ReminderZoneCatalog** | Zone picker sections grouped by expansion and content kind. | 1008 | 35 | OK |
| `Modules/Data/PlanGeography.lua` | **DATA:PlanGeography** | Consistent zone/territory wording for plans and tooltips. | 105 | 6 | OK |

---

## SERVICE — domain logic

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/InitializationService.lua` | **SERVICE:Init** | Staged, combat-safe module startup after login. | 518 | 10 | OK |
| `Modules/LoadingTracker.lua` | **SERVICE:Loading** | Tracks which services finished their login work; fires the loading progress messages. | 83 | 11 | OK |
| `Modules/CharacterService.lua` | **SERVICE:Character** | Character tracking, favorites, and character-key resolution (GUID-first identity). | 1386 | 12 | OK |
| `Modules/DataService.lua` | **SERVICE:Data** | Saves the logged-in character's row; cross-character aggregation and legacy cache wrappers. | 2682 | 35 | WATCH |
| `Modules/DataService_Compression.lua` | **SERVICE:Data_Compression** | Compression helpers (LibDeflate) for stored data — split from DataService. | 117 | 4 | OK |
| `Modules/DataService_RosterHelpers.lua` | **SERVICE:Data_Roster** | Roster cache signature and safe money/storage row helpers — split from DataService. | 339 | 17 | OK |
| `Modules/CommandService.lua` | **SERVICE:Commands** | All `/wn` slash-command routing. | 1009 | 13 | OK |
| `Modules/CollectionService.lua` | **SERVICE:Collection** | Mount/pet/toy ownership cache + real-time "you just collected X" detection. | 5995 | 89 | HOT |
| `Modules/CollectionService_Materialize.lua` | **SERVICE:Collection_Materialize** | Chunked pet/toy journal loading — split from CollectionService. | 348 | 12 | OK |
| `Modules/CollectionService_NotifyDedup.lua` | **SERVICE:Collection_NotifyDedup** | Prevents duplicate "collected!" notifications (ring buffer + DB layers). | 332 | 33 | OK |
| `Modules/CollectionService_Scan.lua` | **SERVICE:Collection_Scan** | Bag/loot scanning that detects newly obtained collectibles. | 433 | 14 | OK |
| `Modules/CollectionRules.lua` | **SERVICE:CollectionRules** | Per-type rules: is this collected, can this character collect it. | 364 | 7 | OK |
| `Modules/ReputationScanner.lua` | **SERVICE:Reputation_Scanner** | Raw reputation reads from the WoW API (no transforms). | 352 | 9 | OK |
| `Modules/ReputationProcessor.lua` | **SERVICE:Reputation_Processor** | Normalizes scanner output into UI-ready standing/progress records. | 690 | 5 | OK |
| `Modules/ProfessionService.lua` | **SERVICE:Profession** | Collects profession data (concentration, knowledge, recipes) when the profession window opens. | 3616 | 104 | WATCH |
| `Modules/TooltipService.lua` | **SERVICE:Tooltip** | The addon's own tooltip: what shows when you hover WN rows and items. | 2133 | 80 | OK |
| `Modules/TooltipService_GameTooltip.lua` | **SERVICE:Tooltip_GameTooltip** | Injects WN lines (owned-by, try counts, concentration) into Blizzard's game tooltip. | 1936 | 55 | OK |
| `Modules/GuildBankScanner.lua` | **SERVICE:GuildBank** | Scans and caches guild bank contents. | 704 | 19 | OK |
| `Modules/VaultScanner.lua` | **SERVICE:VaultScanner** | Event-driven Great Vault data requests at login. | 345 | 9 | OK |
| `Modules/TryCounterService.lua` | **SERVICE:TryCounter** | Counts your kill/loot attempts for mount/pet drops (the "tries" numbers). | 8564 | 185 | HOT |
| `Modules/TryCounterService_Shared.lua` | **SERVICE:TryCounter_Shared** | Try Counter shared constants and chat helpers. | 69 | 5 | OK |
| `Modules/TryCounterService_Events.lua` | **SERVICE:TryCounter_Events** | Try Counter event tables. | 67 | 2 | OK |
| `Modules/TryCounterService_Process.lua` | **SERVICE:TryCounter_Process** | Loot-routing pipeline constants (skip/container/fishing/NPC). | 51 | 2 | OK |
| `Modules/TryCounterService_Handlers.lua` | **SERVICE:TryCounter_Handlers** | Encounter-end and loot event handlers for the Try Counter. | 709 | 22 | OK |
| `Modules/ReminderService.lua` | **SERVICE:Reminder** | Time- and location-based reminders for To-Do plans (login, reset, zone-enter triggers). | 1895 | 94 | OK |
| `Modules/GearService.lua` | **SERVICE:Gear** | Scans equipped gear, computes upgrade-track analysis and cross-character storage finds. | 2973 | 129 | WATCH |
| `Modules/GearService_Slots.lua` | **SERVICE:Gear_Slots** | Paper-doll slot tables (which slot is which). | 82 | 6 | OK |
| `Modules/GearService_UpgradeTracks.lua` | **SERVICE:Gear_UpgradeTracks** | Midnight upgrade-track item-level tables and crest currency map. | 58 | 7 | OK |
| `Modules/GearService_StorageFind.lua` | **SERVICE:Gear_StorageFind** | Finds gear upgrades sitting in your bags/banks across characters. | 1756 | 54 | OK |
| `Modules/GoldManagementService.lua` | **SERVICE:GoldManagement** | Watches deposit/withdraw targets against the Warband bank and notifies. | 118 | 8 | OK |
| `Modules/CharacterBankMoneyLogService.lua` | **SERVICE:MoneyLog** | Records every character-to-Warband-bank gold transaction. | 388 | 21 | OK |
| `Modules/MailSnapshotService.lua` | **SERVICE:MailSnapshot** | Captures each character's inbox summary (sender, subject, gold, items). | 895 | 59 | OK |
| `Modules/ChatIntegrationService.lua` | **SERVICE:ChatIntegration** | Single owner of chat-message filters (suppressing/annotating loot lines). | 875 | 20 | OK |
| `Modules/ChatMessageService.lua` | **SERVICE:ChatMessages** | Queues "reputation gained / currency gained" lines into chat. | 315 | 28 | OK |
| `Modules/MinimapButton.lua` | **SERVICE:Minimap** | The minimap button (LibDBIcon): toggle, right-click menu, position. | 377 | 7 | OK |

---

## CACHE — scan-and-snapshot services

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/CurrencyCacheService.lua` | **CACHE:Currency** | Per-character currency quantities + the header tree the Currency tab renders. | 2508 | 74 | WATCH |
| `Modules/ReputationCacheService.lua` | **CACHE:Reputation** | Per-character reputation snapshots; parses rep-gain chat events. | 2590 | 31 | WATCH |
| `Modules/PvECacheService.lua` | **CACHE:PvE** | Mythic+, Great Vault, lockouts, and weekly rewards per character. | 3104 | 66 | WATCH |
| `Modules/ItemsCacheService.lua` | **CACHE:Items** | Bag/bank/Warband-bank item scans with per-character persistence — the Storage tab's data. | 3192 | 119 | WATCH |

---

## MANAGER — cross-cutting coordinators

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/EventManager.lua` | **MANAGER:Events** | Central WoW event registration with throttle/debounce helpers. | 466 | 11 | OK |
| `Modules/ModuleManager.lua` | **MANAGER:Modules** | Enables/disables optional feature modules and their events. | 182 | 3 | OK |
| `Modules/WindowManager.lua` | **MANAGER:Windows** | Window lifecycle: ESC close order, hide-in-combat, restore after combat. | 454 | 17 | OK |
| `Modules/SearchStateManager.lua` | **MANAGER:SearchState** | Remembers each tab's search query. | 185 | 12 | OK |
| `Modules/PlansManager.lua` | **MANAGER:Plans** | Create/edit/delete To-Do plans (mounts, pets, toys, achievements, vault, quests). | 2311 | 19 | OK |
| `Modules/PlansManager_Vault.lua` | **MANAGER:Plans_Vault** | Weekly vault plan progress sync and reset. | 832 | 8 | OK |
| `Modules/PlansManager_Quests.lua` | **MANAGER:Plans_Quests** | Quest-completion hooks for quest plans. | 35 | 4 | OK |
| `Modules/DailyQuestManager.lua` | **MANAGER:DailyQuests** | Tracks daily/weekly/world quests and zone events for Midnight. | 1235 | 36 | OK |
| `Modules/DailyQuestManager_Tracking.lua` | **MANAGER:DailyQuests_Tracking** | Weekly Progress per-category / per-item tracking toggles. | 170 | 6 | OK |
| `Modules/NotificationManager.lua` | **MANAGER:Notifications** | All in-game toasts: collected items, plan completions, reminders (queue of 6). | 3884 | 117 | WATCH |
| `Modules/NotificationManager_Presentation.lua` | **MANAGER:Notifications_Presentation** | Chooses WN toast vs native Blizzard achievement alert. | 77 | 3 | OK |
| `Modules/NotificationManager_ToastFx.lua` | **MANAGER:Notifications_ToastFx** | Toast effect tier (minimal / celebration). | 24 | 2 | OK |
| `Modules/NotificationManager_ToastChrome.lua` | **MANAGER:Notifications_ToastChrome** | Per-type toast accent colors and icon borders. | 173 | 7 | OK |
| `Modules/NotificationManager_AlertStack.lua` | **MANAGER:Notifications_AlertStack** | Toast queue geometry: stacking, dismissing, repositioning. | 951 | 101 | WATCH |
| `Modules/NotificationManager_Changelog.lua` | **MANAGER:Notifications_Changelog** | The "What's New" changelog popup after updates. | 519 | 23 | OK |
| `Modules/AchievementFrameIntegration.lua` | **MANAGER:AchievementJournal** | Adds the WN "add to To-Do" button inside Blizzard's achievement journal. | 711 | 49 | OK |

---

## UI-SHELL — main window infrastructure

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/UI.lua` | **UI-SHELL:Main** | The main window: shell, navigation, tab switching, debounced repaint. | 5238 | 93 | HOT |
| `Modules/UI/UI_RefreshRouter.lua` | **UI-SHELL:RefreshRouter** | Listens to every `WN_*` data message and decides which tab repaints. | 754 | 1 | OK |
| `Modules/UI/LayoutCoordinator.lua` | **UI-SHELL:Layout** | Main-window resize/reposition pipeline shared by all tabs. | 436 | 17 | OK |
| `Modules/UI/WindowFactory.lua` | **UI-SHELL:WindowFactory** | Builder for every external dialog/popup (draggable header, ESC close). | 695 | 18 | OK |

---

## UI-TAB — main window tabs

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/UI/CharactersUI.lua` | **UI-TAB:Characters** | Characters tab: roster list with gold, level, mail, last seen. | 3680 | 93 | WATCH |
| `Modules/UI/CurrencyUI.lua` | **UI-TAB:Currency** | Currency tab: all currencies across characters, Blizzard header tree. | 1555 | 55 | OK |
| `Modules/UI/ItemsUI.lua` | **UI-TAB:Storage** | Storage tab: bags / bank / Warband bank / guild bank item browser. | 4409 | 131 | HOT |
| `Modules/UI/PvEUI.lua` | **UI-TAB:PvE** | PvE tab: Great Vault, Mythic+, raid lockouts per character. | 4972 | 138 | HOT |
| `Modules/UI/ReputationUI.lua` | **UI-TAB:Reputation** | Reputation tab: progress bars, Renown, Paragon across characters. | 2660 | 82 | WATCH |
| `Modules/UI/StatisticsUI.lua` | **UI-TAB:Statistics** | Statistics tab: account-wide gold, collections, playtime numbers. | 1237 | 66 | OK |
| `Modules/UI/CollectionsUI.lua` | **UI-TAB:Collections** | Collections tab entry point (draw + message listeners); heavy lifting in its satellites. | 720 | 34 | OK |
| `Modules/UI/PlansUI.lua` | **UI-TAB:Plans** | Plans (To-Do) tab: goal tracker for mounts, pets, toys, achievements. | 3613 | 95 | WATCH |
| `Modules/UI/ProfessionsUI.lua` | **UI-TAB:Professions** | Professions tab: per-character profession rows, knowledge, concentration. | 3673 | 172 | HOT |
| `Modules/UI/GearUI.lua` | **UI-TAB:Gear** | Gear tab: paperdoll, Dawncrest upgrade analysis, storage recommendations. | 3507 | 141 | WATCH |
| `Modules/UI/SettingsUI.lua` | **UI-TAB:Settings** | The in-addon Settings tab (grid-based panels). | 4904 | 100 | HOT |

---

## UI-SAT — tab satellite slices

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/UI/CollectionsUI_SourceData.lua` | **UI-SAT:Collections_SourceData** | Source/category tables and multiline source formatting. | 524 | 32 | OK |
| `Modules/UI/CollectionsUI_Shared.lua` | **UI-SAT:Collections_Shared** | Shared state, layout, and scroll helpers for the Collections tab. | 1332 | 64 | OK |
| `Modules/UI/CollectionsUI_Lists.lua` | **UI-SAT:Collections_Lists** | Mounts/pets/toys browse lists (chunked paint). | 1955 | 103 | WATCH |
| `Modules/UI/CollectionsUI_Model.lua` | **UI-SAT:Collections_Model** | Data model: what rows each sub-tab shows and their filter/sort. | 2781 | 104 | WATCH |
| `Modules/UI/CollectionsUI_Recent.lua` | **UI-SAT:Collections_Recent** | "Recently collected" strip. | 649 | 76 | OK |
| `Modules/UI/CollectionsUI_Draw.lua` | **UI-SAT:Collections_Draw** | Row/card painting for the Collections tab. | 1779 | 67 | OK |
| `Modules/UI/PlansUI_SourceParser.lua` | **UI-SAT:Plans_SourceParser** | Parses mount/pet/toy source text for browse tooltips. | 145 | 3 | OK |
| `Modules/UI/PlansUI_Browse.lua` | **UI-SAT:Plans_Browse** | The Plans "browse and add" list (virtual list + achievement browse). | 1464 | 43 | OK |
| `Modules/UI/PlansUI_WeeklyPlanner.lua` | **UI-SAT:Plans_WeeklyPlanner** | Weekly Progress plan create/edit dialog. | 559 | 8 | OK |
| `Modules/UI/ProfessionsUI_DrawTab.lua` | **UI-SAT:Professions_Draw** | Professions tab draw pass (split for Lua limits). | 802 | 4 | OK |
| `Modules/UI/GearUI_Chrome.lua` | **UI-SAT:Gear_Chrome** | Gear tab visual chrome primitives. | 344 | 10 | OK |
| `Modules/UI/GearUI_Paperdoll.lua` | **UI-SAT:Gear_Paperdoll** | Paperdoll, slot, and card drawing for the Gear tab. | 3858 | 163 | HOT |
| `Modules/UI/GearUI_Paperdoll_Slots.lua` | **UI-SAT:Gear_PaperdollSlots** | Paperdoll slot button factory. | 550 | 2 | OK |
| `Modules/UI/GearUI_LayoutGrid.lua` | **UI-SAT:Gear_LayoutGrid** | Gear tab responsive layout metrics (column widths, minimums). | 176 | 4 | OK |
| `Modules/UI/GearUI_Layout.lua` | **UI-SAT:Gear_Layout** | Hooks the Gear tab into the main layout coordinator. | 92 | 1 | OK |
| `Modules/UI/PvEUI_VaultGrid.lua` | **UI-SAT:PvE_VaultGrid** | Great Vault grid painting and tooltips. | 1285 | 41 | OK |
| `Modules/UI/PvEUI_ColumnPicker.lua` | **UI-SAT:PvE_ColumnPicker** | PvE column picker and low-level hide filter flyout. | 559 | 35 | OK |
| `Modules/UI/PvECharacterListRowChrome.lua` | **UI-SAT:PvE_RowChrome** | Per-character summary row chrome for the PvE tab. | 294 | 15 | OK |
| `Modules/UI/StorageSectionLayout.lua` | **UI-SAT:Storage_SectionLayout** | Storage tab section layout constants. | 17 | 2 | OK |
| `Modules/UI/SettingsUI_Shell.lua` | **UI-SAT:Settings_Shell** | Settings category navigation and panel routing. | 480 | 10 | OK |
| `Modules/UI/SettingsUI_Keybind.lua` | **UI-SAT:Settings_Keybind** | Toggle-keybind capture helpers. | 77 | 3 | OK |
| `Modules/UI/SettingsUI_Modules.lua` | **UI-SAT:Settings_Modules** | The module on/off toggles panel. | 193 | 1 | OK |

---

## UI-POPUP — floating windows & dialogs

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/UI/PlansTrackerWindow.lua` | **UI-POPUP:PlansTracker** | Standalone floating To-Do tracker (`/wn todo`). | 2148 | 76 | OK |
| `Modules/UI/RecipeCompanionWindow.lua` | **UI-POPUP:RecipeCompanion** | Floating reagent-availability panel while crafting. | 1210 | 69 | OK |
| `Modules/UI/ProfessionInfoWindow.lua` | **UI-POPUP:ProfessionInfo** | Read-only profession detail window for any character. | 1239 | 67 | OK |
| `Modules/UI/MailDetailsPopup.lua` | **UI-POPUP:MailDetails** | Inbox snapshot popup (Shift+click the mail icon on Characters). | 631 | 41 | OK |
| `Modules/UI/GoldManagementPopup.lua` | **UI-POPUP:GoldManagement** | Configure deposit/withdraw gold targets. | 559 | 21 | OK |
| `Modules/UI/CharacterBankMoneyLogPopup.lua` | **UI-POPUP:MoneyLog** | Warband bank transaction log (All/Deposit/Withdraw/Contributions). | 870 | 56 | OK |
| `Modules/UI/InformationDialog.lua` | **UI-POPUP:About** | About/credits content (also feeds Settings > About). | 387 | 10 | OK |
| `Modules/UI/CharacterTrackingDialog.lua` | **UI-POPUP:CharacterTracking** | "Track this character?" confirmation dialogs. | 563 | 8 | OK |
| `Modules/UI/ReminderSetAlertDialog.lua` | **UI-POPUP:SetAlert** | The Set Alert dialog for plan reminders (main frame). | 1293 | 4 | OK |
| `Modules/UI/ReminderSetAlertDialog_Helpers.lua` | **UI-POPUP:SetAlert_Helpers** | Set Alert helpers (no frame wiring). | 63 | 3 | OK |
| `Modules/UI/ReminderSetAlertDialog_ZonePanel.lua` | **UI-POPUP:SetAlert_ZonePanel** | Zone location + manual map list panel. | 427 | 3 | OK |
| `Modules/UI/ReminderSetAlertDialog_ZoneCatalog.lua` | **UI-POPUP:SetAlert_ZoneCatalog** | Zone catalog picker panel. | 565 | 3 | OK |
| `Modules/UI/ReminderSetAlertDialog_QuestCatalog.lua` | **UI-POPUP:SetAlert_QuestCatalog** | Quest/event picker panel. | 948 | 3 | OK |

### Easy Access button (floating button next to the minimap, with tracker windows)

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/VaultButton_Core.lua` | **UI-POPUP:EasyAccess_Core** | Shared state/environment for all Easy Access files. | 720 | 5 | OK |
| `Modules/VaultButton_Data.lua` | **UI-POPUP:EasyAccess_Data** | Data helpers for the Easy Access views. | 919 | 8 | OK |
| `Modules/VaultButton_Table.lua` | **UI-POPUP:EasyAccess_Table** | Table rendering for the tracker views. | 709 | 10 | OK |
| `Modules/VaultButton_Tooltip.lua` | **UI-POPUP:EasyAccess_Tooltip** | Hover tooltip + badge on the button. | 699 | 11 | OK |
| `Modules/VaultButton_TrackerUI.lua` | **UI-POPUP:EasyAccess_Tracker** | The main floating button frame. | 260 | 6 | OK |
| `Modules/VaultButton_SavedInstances.lua` | **UI-POPUP:EasyAccess_Lockouts** | Saved raid/dungeon lockout data. | 600 | 11 | OK |
| `Modules/VaultButton_SavedInstancesUI.lua` | **UI-POPUP:EasyAccess_LockoutsUI** | Lockout list window. | 544 | 10 | OK |
| `Modules/VaultButton.lua` | **UI-POPUP:EasyAccess** | Entry point: shortcut menu and window toggles. | 814 | 14 | OK |

---

## WIDGET — shared UI building blocks

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/UI/SharedWidgets.lua` | **WIDGET:SharedWidgets** | The heart of the UI: colors, themes, layout constants, core widget helpers. | 6847 | 198 | HOT |
| `Modules/UI/SharedWidgets_Pixel.lua` | **WIDGET:Pixel** | Pixel-perfect scale helpers. | 137 | 10 | OK |
| `Modules/UI/SharedWidgets_CharRow.lua` | **WIDGET:CharRow** | Character row column layout (Characters/PvE lists). | 254 | 17 | OK |
| `Modules/UI/SharedWidgets_ClassicTheme.lua` | **WIDGET:ClassicTheme** | The Classic theme: literal Blizzard-style chrome. | 555 | 7 | OK |
| `Modules/UI/SharedWidgets_Icons.lua` | **WIDGET:Icons** | Icon helpers (monochrome stroke icons, vertex colors). | 933 | 54 | OK |
| `Modules/UI/SharedWidgets_Collapsible.lua` | **WIDGET:Collapsible** | Collapsible section headers. | 450 | 22 | OK |
| `Modules/UI/SharedWidgets_Factory.lua` | **WIDGET:Factory** | `ns.UI.Factory` — the mandatory builder for containers, buttons, scroll frames. | 2654 | 43 | WATCH |
| `Modules/UI/SharedWidgets_RowPool.lua` | **WIDGET:RowPool** | Acquire/release row pooling used by list tabs. | 1038 | 34 | OK |
| `Modules/UI/SharedWidgets_Search.lua` | **WIDGET:SearchWidgets** | Search-related widget helpers. | 857 | 30 | OK |
| `Modules/UI/SharedWidgets_EmptyState.lua` | **WIDGET:EmptyState** | "Nothing here" empty-state cards. | 602 | 17 | OK |
| `Modules/UI/SharedWidgets_CharacterFilter.lua` | **WIDGET:CharacterFilter** | Sort/filter flyouts and section pick menus. | 768 | 21 | OK |
| `Modules/UI/SharedWidgets_TitleToolbar.lua` | **WIDGET:TitleToolbar** | Standard tab title-card toolbar buttons. | 339 | 9 | OK |
| `Modules/UI/FramePoolFactory.lua` | **WIDGET:FramePool** | Frame pooling system (reuse instead of recreate). | 782 | 38 | OK |
| `Modules/UI/SearchBoxComponent.lua` | **WIDGET:SearchBox** | The search box with debounce used on every tab. | 402 | 14 | OK |
| `Modules/UI/CardLayoutManager.lua` | **WIDGET:CardLayout** | Dynamic card grid positioning (Plans cards). | 293 | 8 | OK |
| `Modules/UI/ExpandableRowFactory.lua` | **WIDGET:ExpandableRow** | Expandable rows (achievements/collections). | 861 | 23 | OK |
| `Modules/UI/SearchResultsRenderer.lua` | **WIDGET:SearchResults** | Clears result containers and toggles empty states during search. | 167 | 7 | OK |
| `Modules/UI/VirtualListModule.lua` | **WIDGET:VirtualList** | Virtual scrolling — only visible rows are rendered. | 905 | 24 | OK |
| `Modules/UI/TooltipFactory.lua` | **WIDGET:TooltipFactory** | Frame construction for the custom WN tooltip. | 1248 | 21 | OK |
| `Modules/UI/PlanCardFactory.lua` | **WIDGET:PlanCard** | Builds plan cards for every plan type. | 2987 | 50 | WATCH |
| `Modules/UI/PlanCardFactory_Expanded.lua` | **WIDGET:PlanCard_Expanded** | Expanded plan-card content and actions. | 1046 | 17 | OK |
| `Modules/UI/AchievementBrowseVirtualList.lua` | **WIDGET:AchievementBrowse** | Shared achievement category browser (Collections + Plans). | 923 | 35 | OK |
| `Modules/UI/NotificationToastFactory.lua` | **WIDGET:ToastFactory** | Toast host frame factory. | 128 | 2 | OK |
| `Modules/FontManager.lua` | **WIDGET:FontManager** | All fonts: typography roles, sizes, readable edges, theme refresh. | 1169 | 36 | OK |

---

## HELPER — pure utilities

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/Constants.lua` | **HELPER:Constants** | Version, `WN_*` message names (`Constants.EVENTS`), shared config. | 412 | 2 | OK |
| `Modules/Utilities.lua` | **HELPER:Utilities** | Common helpers, including the GUID-first character key functions. | 999 | 10 | OK |
| `Modules/APIWrapper.lua` | **HELPER:APIWrapper** | Money formatting and screen/window sizing utilities. | 170 | 2 | OK |
| `Modules/DataFreshness.lua` | **HELPER:DataFreshness** | Policy: fetch once at login, then event-driven deltas only. | 240 | 2 | OK |
| `Modules/UI/FormatHelpers.lua` | **HELPER:Format** | Number/money/text formatters for the UI. | 563 | 53 | OK |
| `Modules/UI/ColumnOrderHelpers.lua` | **HELPER:ColumnOrder** | Shared merge/move/reset logic for column pickers. | 149 | 5 | OK |
| `Modules/UI/AchievementCriteriaHelpers.lua` | **HELPER:AchievementCriteria** | Achievement criteria/progress interpretation. | 752 | 45 | OK |

---

## DEBUG — developer tooling

| File | Tag | One-line role | Lines | Locals | Health |
|---|---|---|---|---|---|
| `Modules/DebugPrint.lua` | **DEBUG:Print** | Debug print helper (silent unless debug mode). | 146 | 13 | OK |
| `Modules/DebugService.lua` | **DEBUG:Service** | Debug slash commands: logging toggles, probes, forced scans. | 360 | 7 | OK |
| `Modules/ErrorHandler.lua` | **DEBUG:Errors** | pcall wrappers and the error log ring buffer. | 400 | 6 | OK |
| `Modules/Profiler.lua` | **DEBUG:Profiler** | Performance measurement (`/wn profiler`), dev-only. | 1868 | 23 | OK |
| `Modules/Profiler_TraceUI.lua` | **DEBUG:ProfilerUI** | Profiler trace table window, dev-only. | 787 | 38 | OK |
| `Modules/ItemsCacheService_BagPerf.lua` | **DEBUG:BagPerf** | Bag-update performance debug (`/wn bagdebug`). | 401 | 15 | OK |
| `Modules/ItemsCacheService_PerfStress.lua` | **DEBUG:BagStress** | Bag/tooltip perf stress test. | 384 | 16 | OK |
| `Modules/PvECacheService_VaultSelfTest.lua` | **DEBUG:VaultSelfTest** | Great Vault claim smoke test (`/wn vault test`). | 255 | 11 | OK |
| `Modules/TryCounterService_SelfTest.lua` | **DEBUG:TryCounterSelfTest** | Try Counter smoke test (`/wn tc test`). | 653 | 19 | OK |

---

## Data flow cheat sheet

Who feeds which tab, via which message (the ~10 main flows). `UI-SHELL:RefreshRouter` is the central listener that routes most of these into tab repaints.

| Data owner | Message(s) | Who repaints |
|---|---|---|
| CACHE:Items | `WN_ITEMS_UPDATED`, `WN_BAGS_UPDATED`, `WN_ITEM_METADATA_READY` | UI-TAB:Storage, UI-TAB:Statistics |
| CACHE:Currency | `WN_CURRENCY_UPDATED`, `WN_CURRENCY_CACHE_READY`, `WN_CURRENCY_GAINED` | UI-TAB:Currency |
| CACHE:Reputation | `WN_REPUTATION_UPDATED`, `WN_REPUTATION_CACHE_READY` | UI-TAB:Reputation |
| CACHE:PvE | `WN_PVE_UPDATED` | UI-TAB:PvE, UI-POPUP:EasyAccess |
| SERVICE:Collection | `WN_COLLECTION_UPDATED`, `WN_COLLECTIBLE_OBTAINED`, `WN_COLLECTION_SCAN_COMPLETE` | UI-TAB:Collections, UI-TAB:Statistics, MANAGER:Notifications |
| MANAGER:Plans | `WN_PLANS_UPDATED`, `WN_PLAN_COMPLETED`, `WN_VAULT_*` | UI-TAB:Plans, UI-POPUP:PlansTracker, MANAGER:Notifications |
| SERVICE:Profession | `WN_RECIPE_DATA_UPDATED`, `WN_CONCENTRATION_UPDATED`, `WN_KNOWLEDGE_UPDATED`, `WN_CRAFTING_ORDERS_UPDATED` | UI-TAB:Professions, UI-POPUP:RecipeCompanion, UI-POPUP:ProfessionInfo |
| SERVICE:Character / SERVICE:Data | `WN_CHARACTER_UPDATED`, `WN_MONEY_UPDATED`, `WN_CHARACTER_TRACKING_CHANGED` | UI-TAB:Characters, UI-TAB:Statistics |
| SERVICE:Gear | `WN_GEAR_UPDATED` (routed via RefreshRouter) | UI-TAB:Gear |
| SERVICE:GoldManagement / SERVICE:MoneyLog | `WN_GOLD_MANAGEMENT_CHANGED`, `WN_CHARACTER_BANK_MONEY_LOG_UPDATED` | UI-POPUP:GoldManagement, UI-POPUP:MoneyLog |
| WIDGET:FontManager | `WN_FONT_CHANGED` | every open window |
| Any tab (UI-only redraw) | `WN_UI_MAIN_REFRESH_REQUESTED` | UI-SHELL:Main → the named tab |

---

## When you want X, tag Y

| You want... | Tag(s) |
|---|---|
| Currency numbers wrong / stale | **CACHE:Currency** + **UI-TAB:Currency** |
| An item is missing from Storage | **CACHE:Items** + **UI-TAB:Storage** |
| Reputation bar/standing wrong | **CACHE:Reputation** + **UI-TAB:Reputation** |
| Great Vault / M+ / lockout wrong | **CACHE:PvE** + **UI-TAB:PvE** |
| Try counter didn't count an attempt | **SERVICE:TryCounter** (+ **DATA:CollectibleSources** if the drop source itself is missing) |
| "Collected!" toast missing, duplicated, or ugly | **SERVICE:Collection** + **MANAGER:Notifications** |
| To-Do plan behavior (create, complete, reset) | **MANAGER:Plans** + **UI-TAB:Plans** |
| Plan reminder alerts (zone/login/reset triggers) | **SERVICE:Reminder** + **UI-POPUP:SetAlert** |
| Floating To-Do tracker window issues | **UI-POPUP:PlansTracker** |
| Gear upgrade advice wrong | **SERVICE:Gear** + **UI-TAB:Gear** |
| Profession data missing/stale | **SERVICE:Profession** + **UI-TAB:Professions** |
| A tooltip is unreadable or missing lines | **SERVICE:Tooltip** (WN's own) or **SERVICE:Tooltip_GameTooltip** (Blizzard item tooltips) |
| Colors/theme/light-dark/classic look | **WIDGET:SharedWidgets** (+ **WIDGET:ClassicTheme** for the Classic skin) |
| Fonts too small / wrong outline | **WIDGET:FontManager** |
| Main window won't open / tab switching broken | **UI-SHELL:Main** (+ **UI-SHELL:RefreshRouter** if data never repaints) |
| A settings toggle does nothing | **UI-TAB:Settings** + the service that owns the feature |
| Minimap button problems | **SERVICE:Minimap** |
| Easy Access button / lockout list | **UI-POPUP:EasyAccess** |
| Text wrong or untranslated | **HELPER:Locales** (`Locales/enUS.lua` first) |
| Addon errors on login / after update | **DATA:Migration** + **ENTRY:Core** |
