--[[
    Warband Nexus - English Localization (Base)
    
    This is the default/fallback locale for all other languages.
    
    NOTE: Many strings use Blizzard's built-in GlobalStrings for automatic localization!
    Examples:
    - CLOSE, SETTINGS, REFRESH, SEARCH → Blizzard globals
    - ITEM_QUALITY0_DESC through ITEM_QUALITY7_DESC → Quality names (Poor, Common, Rare, etc.)
    - BAG_FILTER_* → Category names (Equipment, Consumables, etc.)
    - CHARACTER, STATISTICS, LOCATION_COLON → Tooltip strings
    
    These strings are automatically localized by WoW in all supported languages:
    enUS, deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW
    
    Custom strings (Warband Nexus specific) are defined here as fallback.
]]

local ADDON_NAME, ns = ...

---@class WarbandNexusLocale
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "enUS", true, true)
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"

-- Slash Commands
L["KEYBINDING"] = "Keybinding"
L["KEYBINDING_UNBOUND"] = "Not set"
L["KEYBINDING_PRESS_KEY"] = "Press a key..."
L["KEYBINDING_TOOLTIP"] = "Click to set a keybinding for toggling Warband Nexus.\nPress ESC to cancel."
L["KEYBINDING_CLEAR"] = "Clear keybinding"
L["KEYBINDING_SAVED"] = "Keybinding saved."
L["KEYBINDING_COMBAT"] = "Cannot change keybindings in combat."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "General Settings"
L["SETTINGS_SECTION_GENERAL_FEATURES"] = "Features"
L["SETTINGS_SECTION_GENERAL_CONTROLS"] = "Controls & scaling"
L["SETTINGS_SECTION_MODULES_LIST"] = "Enabled modules"
L["SETTINGS_SECTION_VAULT_GENERAL"] = "Shortcut behavior"
L["SETTINGS_SECTION_VAULT_LOOK"] = "Look & opacity"
L["SETTINGS_SECTION_TAB_WARBAND"] = "Warband Bank"
L["SETTINGS_SECTION_TAB_PERSONAL_BANK"] = "Personal Bank"
L["SETTINGS_SECTION_TAB_INVENTORY"] = "Inventory"
L["SETTINGS_SECTION_NOTIF_TIMING"] = "Timing"
L["SETTINGS_SECTION_NOTIF_POSITION"] = "Position"
L["DEBUG_MODE"] = "Debug Logging"
L["DEBUG_MODE_DESC"] = "Output verbose debug messages to chat for troubleshooting"
L["DEBUG_TRYCOUNTER_LOOT"] = "Try Counter Loot Debug"
L["DEBUG_TRYCOUNTER_LOOT_DESC"] = "Log loot flow (numLoot, source, route, outcome). Use when try count is not counted (fast auto-loot, dumpster/object, fishing). Rep/currency cache logs suppressed."

-- Options Panel - Scanning

-- Options Panel - Deposit

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Display Settings"
L["DISPLAY_SETTINGS_DESC"] = "Configure visual appearance"
L["SHOW_ITEM_COUNT"] = "Show Item Count"

-- Options Panel - Tabs

-- Scanner Module

-- Banker Module

-- Warband Bank Operations

-- UI Module
L["SEARCH_CATEGORY_FORMAT"] = "Search %s..."

-- Main Tabs
L["TAB_STORAGE"] = "Storage"
L["TAB_PLANS"] = "To-Do"
L["TAB_REPUTATIONS"] = "Reputations"
L["TAB_CURRENCIES"] = "Currencies"
L["TAB_PVE"] = "PvE"

-- Characters Tab
L["HEADER_CURRENT_CHARACTER"] = "Current Character"
L["HEADER_WARBAND_GOLD"] = "Warband Gold"
L["HEADER_TOTAL_GOLD"] = "Total Gold"

L["YES"] = YES or "Yes"
L["NO"] = NO or "No"

-- Items Tab
L["ITEMS_HEADER"] = "Bank Items"
L["ITEMS_WARBAND_BANK"] = "Warband Bank"

-- Storage Tab
L["STORAGE_HEADER"] = "Storage Browser"
L["STORAGE_HEADER_DESC"] = "Browse all items organized by type"
L["STORAGE_EXPAND_ALL_TOOLTIP"] = "Expand all storage sections (personal banks, Warband Bank, guild banks, and nested categories)."
L["STORAGE_COLLAPSE_ALL_TOOLTIP"] = "Collapse all storage sections and nested categories."
L["STORAGE_WARBAND_BANK"] = "Warband Bank"

-- Plans Tab
L["COLLECTION_PLANS"] = "To-Do List"
L["SEARCH_PLANS"] = "Search plans..."
L["SHOW_COMPLETED"] = "Show Completed"
L["SHOW_COMPLETED_HELP"] = "To-Do List and Weekly Progress: unchecked shows plans still in progress; checked shows completed plans only. Browse tabs (Mounts, Pets, etc.): unchecked browses uncollected items (only those on your To-Do if Show Planned is on); checked adds collected entries that are on your To-Do (Show Planned still limits to list items when on)."
L["SHOW_PLANNED"] = "Show Planned"
L["SHOW_PLANNED_DISABLED_HERE"] = "Not used on To-Do List or Weekly Progress. Open Mounts, Pets, Toys, or another browse tab to use this filter."
L["SHOW_PLANNED_HELP"] = "Browse tabs only (hidden on To-Do List and Weekly Progress): when checked, only items you put on your To-Do for that category. With Show Completed off, planned items you still need; with Show Completed on, planned items you already finished; both on: all planned items in that category; both off: full uncollected browse."
L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"] = "No achievements to display"
L["PLANS_ACHIEVEMENTS_EMPTY_HINT"] = "Add achievements from this list to your To-Do, or change Show Planned / Show Completed. The list fills as achievements are scanned; try /reload if nothing appears."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP"] = "|cffccaa00Warband Nexus|r\nClick to add this achievement to your To-Do List (same as the To-Do button)."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_REMOVE"] = "|cffccaa00Warband Nexus|r\nClick to remove this achievement from your To-Do List."
L["RECENT_TOOLTIP_OBTAINED_BY"] = "Obtained by:"
L["RECENT_TOOLTIP_ACHIEVEMENT_EARNED_BY"] = "This achievement was earned by %s"
L["RECENT_TOOLTIP_EARNED_BY"] = "Obtained by %s"
L["POINTS_LABEL"] = "Points"
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMBAT"] = "Unavailable in combat."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_COMPLETE"] = "This achievement is already completed."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_IN_PLANS"] = "Already on your To-Do List."
L["ACHIEVEMENT_FRAME_WN_TOOLTIP_TRACKED"] = "Already tracked (watch bar)."
L["ACHIEVEMENT_FRAME_WN_ALREADY_PLANNED"] = "Already on your To-Do List."
L["ACHIEVEMENT_FRAME_WN_TRACK_FAILED"] = "Could not add this achievement to Blizzard's tracker (list may be full or unavailable)."
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_TITLE"] = "Nothing to show"
L["PLANS_BROWSE_EMPTY_PLANNED_ALL_DESC"] = "No planned items in this category match the current filters. Add entries to your To-Do or adjust Show Planned / Show Completed."
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_TITLE"] = "No completed To-Do items"
L["PLANS_BROWSE_EMPTY_COMPLETED_PLANNED_DESC"] = "Nothing on your To-Do List in this category is collected or completed yet. Turn off Show Completed to see entries still in progress."
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_TITLE"] = "No in-progress To-Do items"
L["PLANS_BROWSE_EMPTY_IN_PROGRESS_DESC"] = "Nothing on your To-Do List in this category is still uncollected. Turn on Show Completed to see finished ones, or add goals from this tab."

-- Plans Categories
L["CATEGORY_MY_PLANS"] = "To-Do List"
L["CATEGORY_DAILY_TASKS"] = "Weekly Progress"
L["CATEGORY_ILLUSIONS"] = "Illusions"

-- Reputation Tab

-- Currency Tab

-- PvE Tab

-- Statistics
L["TOTAL"] = TOTAL or "Total"

-- Tooltips
L["TOOLTIP_WARBAND_BANK"] = "Warband Bank"
L["CHARACTER_INVENTORY"] = "Inventory"
L["CHARACTER_BANK"] = "Bank"

-- Try Counter
L["SET_TRY_COUNT"] = "Set Try Count"
L["TRY_COUNT_CLICK_HINT"] = "Click to edit attempt count."
L["TRIES"] = "Tries"
L["COLLECTION_LIST_ATTEMPTS_FMT"] = "%d Attempts"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Set Reset Cycle"
L["DAILY_RESET"] = "Daily Reset"
L["WEEKLY_RESET"] = "Weekly Reset"
L["NONE_DISABLE"] = "None (Disable)"
L["RESET_CYCLE_LABEL"] = "Reset Cycle:"
L["RESET_NONE"] = "None"

-- Error Messages

-- Confirmation Dialogs

-- Update Notification
L["WHATS_NEW"] = "What's New"
L["GOT_IT"] = "Got it!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "Achievement Points"
L["MOUNTS_COLLECTED"] = "Mounts Collected"
L["BATTLE_PETS"] = "Battle Pets"
L["UNIQUE_PETS"] = "Unique Pets"
L["ACCOUNT_WIDE"] = "Account-wide"
L["STORAGE_OVERVIEW"] = "Storage Overview"
L["WARBAND_SLOTS"] = "Warband Slots"
L["PERSONAL_SLOTS"] = "Personal Slots"
L["TOTAL_FREE"] = "Total Free"
L["TOTAL_ITEMS"] = "Total Items"

-- Plans Tracker
L["WEEKLY_VAULT"] = "Weekly Vault"
L["CUSTOM"] = "Custom"
L["NO_PLANS_IN_CATEGORY"] = "No plans in this category.\nAdd plans from the Plans tab."
L["SOURCE_LABEL"] = "Source:"
L["ZONE_LABEL"] = "Zone:"
L["VENDOR_LABEL"] = "Vendor:"
L["DROP_LABEL"] = "Drop:"
L["REQUIREMENT_LABEL"] = "Requirement:"
L["CLICK_TO_DISMISS"] = "Click to dismiss"
L["TRACKED"] = "Tracked"
L["TRACK"] = "Track"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Track in Blizzard objectives (max 10)"
L["UNKNOWN"] = UNKNOWN or "Unknown"
L["NO_REQUIREMENTS"] = "No requirements (instant completion)"

-- Plans UI
L["NO_ACTIVE_CONTENT"] = "No active content this week"
L["UNKNOWN_QUEST"] = "Unknown Quest"
L["CURRENT_PROGRESS"] = "Current Progress"
L["QUEST_TYPES"] = "Quest Types:"
L["WORK_IN_PROGRESS"] = "Work in Progress"
L["RECIPE_BROWSER"] = "Recipe Browser"
L["TRY_ADJUSTING_SEARCH"] = "Try adjusting your search or filters."
L["ALL_COLLECTED_CATEGORY"] = "All %ss collected!"
L["COLLECTED_EVERYTHING"] = "You've collected everything in this category!"
L["PROGRESS_LABEL"] = "Progress:"
L["REQUIREMENTS_LABEL"] = "Requirements:"
L["INFORMATION_LABEL"] = "Information:"
L["DESCRIPTION_LABEL"] = "Description:"
L["REWARD_LABEL"] = "Reward:"
L["DETAILS_LABEL"] = "Details:"
L["COST_LABEL"] = "Cost:"
L["LOCATION_LABEL"] = "Location:"
L["TITLE_LABEL"] = "Title:"
L["COMPLETED_ALL_ACHIEVEMENTS"] = "You already completed all achievements in this category!"
L["DAILY_PLAN_EXISTS"] = "Daily Plan Already Exists"
L["WEEKLY_PLAN_EXISTS"] = "Weekly Plan Already Exists"

-- Characters Tab
L["YOUR_CHARACTERS"] = "Your Characters"
L["CHARACTERS_EXPAND_ALL"] = "Expand all"
L["CHARACTERS_EXPAND_ALL_TOOLTIP"] = "Expand Favorites, Characters, and Untracked sections."
L["CHARACTERS_COLLAPSE_ALL"] = "Collapse all"
L["CHARACTERS_COLLAPSE_ALL_TOOLTIP"] = "Collapse Favorites, Characters, and Untracked sections."
L["CHARACTERS_SECTION_TOGGLE_EXPAND_TOOLTIP"] = "Expand Favorites, Characters, and Untracked sections."
L["CHARACTERS_SECTION_TOGGLE_COLLAPSE_TOOLTIP"] = "Collapse Favorites, Characters, and Untracked sections."
L["CHARACTERS_TRACKED_FORMAT"] = "%d characters tracked"
L["NO_FAVORITES"] = "No favorite characters yet. Click the star icon to favorite a character."
L["ALL_FAVORITED"] = "All characters are favorited!"
L["UNTRACKED_CHARACTERS"] = "Untracked Characters"
L["ILVL_SHORT"] = "iLvl"
L["ONLINE"] = "Online"
L["TIME_LESS_THAN_MINUTE"] = "< 1m ago"
L["TIME_MINUTES_FORMAT"] = "%dm ago"
L["TIME_HOURS_FORMAT"] = "%dh ago"
L["TIME_DAYS_FORMAT"] = "%dd ago"
L["REMOVE_FROM_FAVORITES"] = "Remove from Favorites"
L["ADD_TO_FAVORITES"] = "Add to Favorites"
L["FAVORITES_TOOLTIP"] = "Favorite characters appear at the top of the list"
L["CLICK_TO_TOGGLE"] = "Click to toggle"
L["UNKNOWN_PROFESSION"] = "Unknown Profession"
L["POINTS_SHORT"] = " pts"
L["TRACKING_ACTIVE_DESC"] = "Data collection and updates are active."
L["TRACKING_ENABLED"] = "Tracking Enabled"
L["TRACKING_NOT_ENABLED_TOOLTIP"] = "Character tracking is disabled. Click to open Characters tab."
L["TRACKING_BADGE_CLICK_HINT"] = "Click to change tracking."
L["TRACKING_TAB_LOCKED_TITLE"] = "Character is not tracked"
L["TRACKING_TAB_LOCKED_DESC"] = "This tab works only for tracked characters.\nEnable tracking from the Characters page using the tracking icon."
L["OPEN_CHARACTERS_TAB"] = "Open Characters"
L["DELETE_CHARACTER_TITLE"] = "Delete Character?"
L["THIS_CHARACTER"] = "this character"
L["DELETE_CHARACTER"] = "Delete Character"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Remove %s from tracking"
L["CLICK_TO_DELETE"] = "Click to delete"
L["CONFIRM_DELETE"] = "Are you sure you want to delete |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "This action cannot be undone!"

-- Empty state cards (SharedWidgets EMPTY_STATE_CONFIG)
L["EMPTY_CHARACTERS_TITLE"] = "No Characters Found"
L["EMPTY_CHARACTERS_DESC"] = "Log in to your characters to start tracking them.\nCharacter data is collected automatically on each login."
L["EMPTY_ITEMS_TITLE"] = "No Items Cached"
L["EMPTY_ITEMS_DESC"] = "Open your Warband Bank or Personal Bank to scan items.\nItems are cached automatically on first visit."
L["EMPTY_INVENTORY_TITLE"] = "No Items in Inventory"
L["EMPTY_INVENTORY_DESC"] = "Your inventory bags are empty."
L["EMPTY_PERSONAL_BANK_TITLE"] = "No Items in Personal Bank"
L["EMPTY_PERSONAL_BANK_DESC"] = "Open your Personal Bank to scan items.\nItems are cached automatically on first visit."
L["EMPTY_WARBAND_BANK_TITLE"] = "No Items in Warband Bank"
L["EMPTY_WARBAND_BANK_DESC"] = "Open your Warband Bank to scan items.\nItems are cached automatically on first visit."
L["EMPTY_GUILD_BANK_TITLE"] = "No Items in Guild Bank"
L["EMPTY_GUILD_BANK_DESC"] = "Open your Guild Bank to scan items.\nItems are cached automatically on first visit."
L["EMPTY_STORAGE_TITLE"] = "No Storage Data"
L["EMPTY_STORAGE_DESC"] = "Items are scanned when you open banks or bags.\nVisit a bank to start tracking your storage."
L["EMPTY_PLANS_TITLE"] = "No Plans Yet"
L["EMPTY_PLANS_DESC"] = "Browse Mounts, Pets, Toys, or Achievements above\nto add collection goals and track your progress."
L["EMPTY_REPUTATION_TITLE"] = "No Reputation Data"
L["EMPTY_REPUTATION_DESC"] = "Reputations are scanned automatically on login.\nLog in to a character to start tracking faction standings."
L["EMPTY_CURRENCY_TITLE"] = "No Currency Data"
L["EMPTY_CURRENCY_DESC"] = "Currencies are tracked automatically across your characters.\nLog in to a character to start tracking currencies."
L["EMPTY_PVE_TITLE"] = "No PvE Data"
L["EMPTY_PVE_DESC"] = "PvE progress is tracked when you log into your characters.\nGreat Vault, Mythic+, and Raid lockouts will appear here."
L["EMPTY_STATISTICS_TITLE"] = "No Statistics Available"
L["EMPTY_STATISTICS_DESC"] = "Statistics are gathered from your tracked characters.\nLog in to a character to start collecting data."
L["COLLECTIONS_COMING_SOON_TITLE"] = "Coming Soon"
L["COLLECTIONS_COMING_SOON_DESC"] = "Collection overview (mounts, pets, toys, transmog) will be available here."

-- Items Tab
L["PERSONAL_ITEMS"] = "Personal Items"
L["ITEMS_SUBTITLE"] = "Browse your Warband Bank, Guild Bank, and Personal Items"
L["ITEMS_EXPAND_ALL_TOOLTIP"] = "Expand all item type groups for the current bank sub-tab (personal, Warband, guild, or inventory)."
L["ITEMS_COLLAPSE_ALL_TOOLTIP"] = "Collapse all item type groups for the current bank sub-tab."
L["ITEMS_DISABLED_TITLE"] = "Warband Bank Items"
L["ITEMS_LOADING"] = "Loading Inventory Data"
L["GUILD_BANK_REQUIRED"] = "You must be in a guild to access Guild Bank."
L["GUILD_JOINED_FORMAT"] = "Guild updated: %s"
L["GUILD_LEFT"] = "You are no longer in a guild. Guild Bank tab disabled."
L["NOT_IN_GUILD"] = "Not in guild"
L["ITEMS_SEARCH"] = "Search items..."
L["NEVER"] = "Never"
L["ITEM_FALLBACK_FORMAT"] = "Item %s"
L["ITEM_LOADING_NAME"] = "Loading..."
L["TAB_FORMAT"] = "Tab %d"
L["BAG_FORMAT"] = "Bag %d"
L["BANK_BAG_FORMAT"] = "Bank Bag %d"
L["ITEM_ID_LABEL"] = "Item ID:"
L["STACK_LABEL"] = "Stack:"
L["RIGHT_CLICK_MOVE"] = "Move to bag"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Split stack"
L["LEFT_CLICK_PICKUP"] = "Pick up"
L["ITEMS_BANK_NOT_OPEN"] = "Bank not open"
L["SHIFT_LEFT_CLICK_LINK"] = "Link in chat"
L["ITEMS_STATS_ITEMS"] = "%s items"
L["ITEMS_STATS_SLOTS"] = "%s/%s slots"
L["ITEMS_STATS_LAST"] = "Last: %s"

-- Storage Tab
L["STORAGE_DISABLED_TITLE"] = "Character Storage"
L["STORAGE_SEARCH"] = "Search storage..."

-- PvE Tab
L["PVE_TITLE"] = "PvE Progress"
L["PVE_SUBTITLE"] = "Great Vault, Raid Lockouts & Mythic+ across your Warband"
L["PVE_CREST_ADV"] = "Adventurer"
L["PVE_CREST_VET"] = "Veteran"
L["PVE_CREST_CHAMP"] = "Champion"
L["PVE_CREST_HERO"] = "Hero"
L["PVE_CREST_MYTH"] = "Myth"
L["PVE_CREST_EXPLORER"] = "Explorer"
L["PVE_COL_COFFER_SHARDS"] = "Coffer Shards"
L["PVE_COL_RESTORED_KEY"] = "Restored Key"
L["PVE_COL_VAULT_STATUS"] = "Vault Status"
L["PVE_COL_NEBULOUS_VOIDCORE"] = "Nebulous Voidcore"
L["PVE_COL_DAWNLIGHT_MANAFLUX"] = "Dawnlight Manaflux"
L["PVE_HEADER_RAID_SHORT"] = "Raid"
L["PVE_HEADER_MAP_SHORT"] = "Map"
L["PVE_HEADER_STATUS_SHORT"] = "Status"
L["PVE_COMPACT_COFFER_SHARD"] = "Coffer Shard"
L["PVE_COMPACT_RESTORED"] = "Restored"
L["PVE_COMPACT_VOIDCORE"] = "Voidcore"
L["PVE_COMPACT_MANAFLUX"] = "Manaflux"
L["PVE_CREST_GENERIC"] = "Crest"
L["VAULT_READY_TO_CLAIM"] = "Ready"
L["VAULT_SLOTS_EARNED"] = "Slots Earned"
L["VAULT_SLOTS_SHORT_FORMAT"] = "%d Slots"
L["PVE_VAULT_SLOT_COMPLETE_FORMAT"] = "Slot %d: |cff80ff80✓|r %s"
L["PVE_VAULT_SLOT_PROGRESS_FORMAT"] = "Slot %d: |cffff8888%d/%d|r"
L["PVE_VAULT_SLOT_EMPTY_FORMAT"] = "Slot %d: —"
L["PVE_VAULT_SLOT_UNLOCKED"] = "Unlocked"
L["VAULT_PENDING"] = "Pending\226\128\166"
L["CREST_SOURCES_HEADER"] = "Sources:"
L["CREST_TO_CAP_SUFFIX"] = "to season cap"
L["SHIFT_HINT_SEASON_PROGRESS"] = "Hold Shift for season progress"
L["SHIFT_HINT_SEASON_PROGRESS_SHORT"] = "Shift: Season progress"
L["LV_FORMAT"] = "Lv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_WORLD"] = "World"
L["VAULT_SLOT_FORMAT"] = "%s Slot %d"
L["OVERALL_SCORE_LABEL"] = "Overall Score:"
L["NOT_COMPLETED_SEASON"] = "Not completed this season"
L["LOADING_PVE"] = "Loading PvE Data..."
L["PVE_VAULT_TRACKER_SUBTITLE"] = "Unclaimed rewards and cleared vault rows"
L["PVE_VAULT_TRACKER_EMPTY_TITLE"] = "No vault rows yet"
L["PVE_VAULT_TRACKER_EMPTY_DESC"] = "No tracked character has weekly vault progress saved yet (nothing to claim or show as cleared).\nLog in on each character or turn off Weekly Vault Tracker to see full PvE progress."
L["NO_VAULT_DATA"] = "No vault data"
L["NO_DATA"] = "No data"
L["KEYSTONE"] = "Keystone"
L["NO_KEY"] = "No Key"
L["AFFIXES"] = "Affixes"
L["NO_AFFIXES"] = "No Affixes"
L["VAULT_BEST_KEY"] = "Best Key:"
L["VAULT_SCORE"] = "Score:"

-- Vault Tooltip (detailed)
L["VAULT_COMPLETED_ACTIVITIES"] = "Completed"
L["VAULT_CLICK_TO_OPEN"] = "Click to open Great Vault"
L["VAULT_TRACKER_CARD_CLICK_HINT"] = "Click to open Great Vault"
L["VAULT_REWARD"] = "Current Reward"
L["VAULT_DUNGEONS"] = "dungeons"
L["VAULT_BOSS_KILLS"] = "boss kills"
L["VAULT_WORLD_ACTIVITIES"] = "world activities"
L["VAULT_ACTIVITIES"] = "activities"
L["VAULT_REMAINING_SUFFIX"] = "remaining"
L["VAULT_IMPROVE_TO"] = "Improve to"
L["VAULT_COMPLETE_ON"] = "Complete this activity on %s"
L["VAULT_ENCOUNTER_LIST_FORMAT"] = "%s"
L["VAULT_TOP_RUNS_FORMAT"] = "Top %d Runs This Week"
L["VAULT_DELVE_TIER_FORMAT"] = "Tier %d (%d)"
L["VAULT_UNLOCK_REWARD"] = "Unlock Reward"
L["VAULT_COMPLETE_MORE_FORMAT"] = "Complete %d more %s this week to unlock."
L["VAULT_BASED_ON_FORMAT"] = "The item level of this reward will be based on the lowest of your top %d runs this week (currently %s)."
L["VAULT_RAID_BASED_FORMAT"] = "Reward based on highest difficulty defeated (currently %s)."

-- Delves Section (PvE Tab)
L["BOUNTIFUL_DELVE"] = "Trovehunter's Bounty"
L["PVE_BOUNTY_NEED_LOGIN"] = "No saved status for this character. Log in to refresh."
L["SEASON"] = "Season"
L["CURRENCY_LABEL_WEEKLY"] = "Weekly"

-- Reputation Tab
L["REP_TITLE"] = "Reputation Overview"
L["REP_SUBTITLE"] = "Track factions and renown across your warband"
L["REP_EXPAND_ALL_TOOLTIP"] = "Expand all reputation sections and expansion headers."
L["REP_COLLAPSE_ALL_TOOLTIP"] = "Collapse all reputation sections and expansion headers."
L["REP_DISABLED_TITLE"] = "Reputation Tracking"
L["REP_LOADING_TITLE"] = "Loading Reputation Data"
L["REP_SEARCH"] = "Search reputations..."
L["REP_PARAGON_TITLE"] = "Paragon Reputation"
L["REP_REWARD_AVAILABLE"] = "Reward available!"
L["REP_CONTINUE_EARNING"] = "Continue earning reputation for rewards"
L["REP_CYCLES_FORMAT"] = "Cycles: %d"
L["REP_PROGRESS_HEADER"] = "Progress: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Paragon Progress:"
L["REP_CYCLES_COLON"] = "Cycles:"
L["REP_CHARACTER_PROGRESS"] = "Character Progress:"
L["REP_RENOWN_FORMAT"] = "Renown %d"
L["REP_PARAGON_FORMAT"] = "Paragon (%s)"
L["REP_UNKNOWN_FACTION"] = "Unknown Faction"
L["REP_API_UNAVAILABLE_TITLE"] = "Reputation API Not Available"
L["REP_API_UNAVAILABLE_DESC"] = "The C_Reputation API is not available on this server. This feature requires WoW 12.0.5 (Midnight)."
L["REP_FOOTER_TITLE"] = "Reputation Tracking"
L["REP_FOOTER_DESC"] = "Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards."
L["REP_CLEARING_CACHE"] = "Clearing cache and reloading..."
L["REP_MAX"] = "Max."
L["ACCOUNT_WIDE_LABEL"] = "Account-Wide"
L["NO_RESULTS"] = "No results"
L["NO_ACCOUNT_WIDE_REPS"] = "No account-wide reputations"
L["NO_CHARACTER_REPS"] = "No character-based reputations"

-- Currency Tab
L["GOLD_LABEL"] = "Gold"
L["CURRENCY_TITLE"] = "Currency Tracker"
L["CURRENCY_SUBTITLE"] = "Track all currencies across your characters"
L["CURRENCY_EXPAND_ALL_TOOLTIP"] = "Expand all currency category headers in the list."
L["CURRENCY_COLLAPSE_ALL_TOOLTIP"] = "Collapse all currency category headers in the list."
L["CURRENCY_DISABLED_TITLE"] = "Currency Tracking"
L["CURRENCY_LOADING_TITLE"] = "Loading Currency Data"
L["CURRENCY_SEARCH"] = "Search currencies..."
L["CURRENCY_HIDE_EMPTY"] = "Hide Empty"
L["CURRENCY_SHOW_EMPTY"] = "Show Empty"
L["CURRENCY_WARBAND_TRANSFERABLE"] = "All Warband Transferable"
L["CURRENCY_CHARACTER_SPECIFIC"] = "Character-Specific Currencies"
L["CURRENCY_TRANSFER_NOTICE_TITLE"] = "Currency Transfer Limitation"
L["CURRENCY_TRANSFER_NOTICE_DESC"] = "Blizzard API does not support automated currency transfers. Please use the in-game currency frame to manually transfer Warband currencies."
L["CURRENCY_UNKNOWN"] = "Unknown Currency"

-- Plans Tab (extended)
L["REMOVE_COMPLETED_TOOLTIP"] = "Remove all completed plans from your My Plans list. This will delete all completed custom plans and remove completed mounts/pets/toys from your plans. This action cannot be undone!"
L["RECIPE_BROWSER_DESC"] = "Open your Profession window in-game to browse recipes.\nThe addon will scan available recipes when the window is open."
L["SOURCE_ACHIEVEMENT_FORMAT"] = "%s |cff00ff00[%s %s]|r"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s already has an active weekly vault plan. You can find it in the 'My Plans' category."
L["DAILY_PLAN_EXISTS_DESC"] = "%s already has an active weekly quest plan. You can find it in the 'Weekly Progress' category."
L["TRANSMOG_WIP_DESC"] = "Transmog collection tracking is currently under development.\n\nThis feature will be available in a future update with improved\nperformance and better integration with Warband systems."
L["WEEKLY_VAULT_CARD"] = "Weekly Vault Card"
L["WEEKLY_VAULT_COMPLETE"] = "Weekly Vault Card - Complete"
L["UNKNOWN_SOURCE"] = "Unknown source"
L["DAILY_TASKS_PREFIX"] = "Weekly Progress - "
L["COMPLETE_LABEL"] = "Complete"
L["PLANS_COUNT_FORMAT"] = "%d plans"
L["QUEST_LABEL"] = "Quest:"

-- Settings Tab
L["CURRENT_LANGUAGE"] = "Current Language:"
L["LANGUAGE_TOOLTIP"] = "Addon uses your WoW game client's language automatically. To change, update your Battle.net settings."
L["NOTIFICATION_DURATION"] = "Notification Duration"
L["NOTIFICATION_POSITION"] = "Notification Position"
L["SET_POSITION"] = "Set Position"
L["SET_BOTH_POSITION"] = "Set Both Position"
L["DRAG_TO_POSITION"] = "Drag to position\nRight-click to confirm"
L["RESET_DEFAULT"] = "Reset Default"
L["RESET_POSITION"] = "Reset Position"
L["TEST_NOTIFICATION"] = "Test Notification"
L["CUSTOM_COLOR"] = "Custom Color"
L["OPEN_COLOR_PICKER"] = "Open Color Picker"
L["COLOR_PICKER_TOOLTIP"] = "Open WoW's native color picker wheel to choose a custom theme color"
L["PRESET_THEMES"] = "Preset Themes"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus Settings"
L["NO_OPTIONS"] = "No Options"
L["TAB_FILTERING"] = "Tab Filtering"
L["SCROLL_SPEED"] = "Scroll Speed"
L["ANCHOR_FORMAT"] = "Anchor: %s  |  X: %d  |  Y: %d"
L["USE_ALERTFRAME_POSITION"] = "Use AlertFrame position"
L["USE_ALERTFRAME_POSITION_ACTIVE"] = "Using Blizzard AlertFrame position"
L["NOTIFICATION_GHOST_MAIN"] = "Achievement / notification"
L["NOTIFICATION_GHOST_CRITERIA"] = "Criteria progress"
L["SHOW_WEEKLY_PLANNER"] = "Weekly Planner (Characters)"
L["LOCK_MINIMAP_ICON"] = "Lock Minimap Button"
L["BACKPACK_LABEL"] = "Backpack"
L["REAGENT_LABEL"] = "Reagent"

-- Shared Widgets & Dialogs
L["MODULE_DISABLED"] = "Module Disabled"
L["LOADING"] = "Loading..."
L["PLEASE_WAIT"] = "Please wait..."
L["RESET_PREFIX"] = "Reset:"
L["SAVE"] = "Save"
L["CREATE_CUSTOM_PLAN"] = "Create Custom Plan"
L["REPORT_BUGS"] = "Report bugs or share suggestions on CurseForge to help improve the addon."
L["ADDON_OVERVIEW_DESC"] = "Warband Nexus provides a centralized interface for managing all your characters, currencies, reputations, items, and PvE progress across your entire Warband."
L["CHARACTERS_DESC"] = "View all characters with gold, level, iLvl, faction, race, class, professions, keystone, and last played info. Track or untrack characters, mark favorites."
L["ITEMS_DESC"] = "Search and browse items across all bags, banks, and warband bank. Auto-scans when you open a bank. Shows which characters own each item via tooltip."
L["STORAGE_DESC"] = "Aggregated inventory view from all characters — bags, personal bank, and warband bank combined in one place."
L["PVE_DESC"] = "Track Great Vault progress with next-tier indicators, Mythic+ scores and keys, keystone affixes, dungeon history, and upgrade currency across all characters."
L["REPUTATIONS_DESC"] = "Compare reputation progress across all characters. Shows Account-Wide vs Character-Specific factions with hover tooltips for per-character breakdown."
L["CURRENCY_DESC"] = "View all currencies organized by expansion. Compare amounts across characters with hover tooltips. Hide empty currencies with one click."
L["PLANS_DESC"] = "Track uncollected mounts, pets, toys, achievements, and transmogs. Add goals, view drop sources, and monitor try counts. Access via /wn plan or minimap icon."
L["STATISTICS_DESC"] = "View achievement points, mount/pet/toy/illusion/title collection progress, unique pet count, and bag/bank usage statistics."

-- PvE Difficulty Names
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Tier %d"
L["PREPARING"] = "Preparing"

-- Statistics Tab (extended)
L["ACCOUNT_STATISTICS"] = "Account Statistics"
L["STATISTICS_SUBTITLE"] = "Collection progress, gold, and storage overview"
L["WARBAND_WEALTH"] = "Warband Wealth"
L["WARBAND_BANK"] = "Warband Bank"
L["MOST_PLAYED"] = "Most Played"
L["PLAYED_DAYS"] = "Days"
L["PLAYED_HOURS"] = "Hours"
L["PLAYED_MINUTES"] = "Minutes"
L["PLAYED_DAY"] = "Day"
L["PLAYED_HOUR"] = "Hour"
L["PLAYED_MINUTE"] = "Minute"
L["MORE_CHARACTERS"] = "more character"
L["MORE_CHARACTERS_PLURAL"] = "more characters"

-- Information Dialog (extended)
L["WELCOME_TITLE"] = "Welcome to Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "AddOn Overview"

-- Plans UI (extended)
L["PLANS_SUBTITLE_TEXT"] = "Track your weekly goals & collections"
L["ACTIVE_PLAN_FORMAT"] = "%d active plan"
L["ACTIVE_PLANS_FORMAT"] = "%d active plans"

-- Plans - Type Names
L["TYPE_RECIPE"] = "Recipe"
L["TYPE_ILLUSION"] = "Illusion"
L["TYPE_TITLE"] = "Title"
L["TYPE_CUSTOM"] = "Custom"

-- Plans - Source Type Labels
L["SOURCE_TYPE_TRADING_POST"] = "Trading Post"
L["SOURCE_TYPE_TREASURE"] = "Treasure"
L["SOURCE_TYPE_PUZZLE"] = "Puzzle"
L["SOURCE_TYPE_RENOWN"] = "Renown"

-- Plans - Source Text Parsing Keywords
L["PARSE_SOLD_BY"] = "Sold by"
L["PARSE_CRAFTED"] = "Crafted"
L["PARSE_COST"] = "Cost"
L["PARSE_HOLIDAY"] = "Holiday"
L["PARSE_RATED"] = "Rated"
L["PARSE_BATTLEGROUND"] = "Battleground"
L["PARSE_DISCOVERY"] = "Discovery"
L["PARSE_CONTAINED_IN"] = "Contained in"
L["PARSE_GARRISON"] = "Garrison"
L["PARSE_GARRISON_BUILDING"] = "Garrison Building"
L["PARSE_STORE"] = "Store"
L["PARSE_ORDER_HALL"] = "Order Hall"
L["PARSE_COVENANT"] = "Covenant"
L["PARSE_FRIENDSHIP"] = "Friendship"
L["PARSE_PARAGON"] = "Paragon"
L["PARSE_MISSION"] = "Mission"
L["PARSE_EXPANSION"] = "Expansion"
L["PARSE_SCENARIO"] = "Scenario"
L["PARSE_CLASS_HALL"] = "Class Hall"
L["PARSE_CAMPAIGN"] = "Campaign"
L["PARSE_EVENT"] = "Event"
L["PARSE_SPECIAL"] = "Special"
L["PARSE_BRAWLERS_GUILD"] = "Brawler's Guild"
L["PARSE_CHALLENGE_MODE"] = "Challenge Mode"
L["PARSE_MYTHIC_PLUS"] = "Mythic+"
L["PARSE_TIMEWALKING"] = "Timewalking"
L["PARSE_ISLAND_EXPEDITION"] = "Island Expedition"
L["PARSE_WARFRONT"] = "Warfront"
L["PARSE_TORGHAST"] = "Torghast"
L["PARSE_ZERETH_MORTIS"] = "Zereth Mortis"
L["PARSE_HIDDEN"] = "Hidden"
L["PARSE_RARE"] = "Rare"
L["PARSE_WORLD_BOSS"] = "World Boss"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "From Achievement"
L["FALLBACK_UNKNOWN_PET"] = "Unknown Pet"

-- Plans - Fallback Labels
L["FALLBACK_PET_COLLECTION"] = "Pet Collection"
L["FALLBACK_TOY_COLLECTION"] = "Toy Collection"
L["FALLBACK_TOY_BOX"] = "Toy Box"
L["FALLBACK_WARBAND_TOY"] = "Warband Toy"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Transmog Collection"
L["FALLBACK_PLAYER_TITLE"] = "Player Title"
L["FALLBACK_ILLUSION_FORMAT"] = "Illusion %s"
L["SOURCE_ENCHANTING"] = "Enchanting"

-- Plans - Dialogs
L["RESET_COMPLETED_CONFIRM"] = "Are you sure you want to remove ALL completed plans?\n\nThis cannot be undone!"
L["YES_RESET"] = "Yes, Reset"
L["REMOVED_PLANS_FORMAT"] = "Removed %d completed plan(s)."

-- Plans - Buttons
L["ADD_CUSTOM"] = "Add Custom"
L["ADD_VAULT"] = "Add Vault"
L["ADD_QUEST"] = "Add Quest"
L["CREATE_PLAN"] = "Create Plan"

-- Plans - Quest Categories
L["QUEST_CAT_DAILY"] = "Daily"
L["QUEST_CAT_WORLD"] = "World"
L["QUEST_CAT_WEEKLY"] = "Weekly"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Unknown Category"
L["SCANNING_FORMAT"] = "Scanning %s"
L["CUSTOM_PLAN_SOURCE"] = "Custom plan"
L["POINTS_FORMAT"] = "%d Points"
L["SOURCE_NOT_AVAILABLE"] = "Source information not available"
L["PROGRESS_ON_FORMAT"] = "You are %d/%d on the progress"
L["COMPLETED_REQ_FORMAT"] = "You completed %d of %d total requirements"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["WEEKLY_RESET_LABEL"] = "Weekly Reset"
L["QUEST_TYPE_WEEKLY"] = "Weekly Quests"
L["QUEST_CAT_CONTENT_EVENTS"] = "Content Event"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mythic+"

-- PlanCardFactory
L["FACTION_LABEL"] = "Faction:"
L["FRIENDSHIP_LABEL"] = "Friendship"
L["RENOWN_TYPE_LABEL"] = "Renown"
L["ADD_BUTTON"] = "To-Do"
L["ADDED_LABEL"] = "Added"
L["TODO_SLOT_TOOLTIP_ADD"] = "Click to add to your To-Do list."
L["TODO_SLOT_TOOLTIP_REMOVE"] = "Click to remove from your To-Do list."
L["TRACK_SLOT_TOOLTIP_UNTRACK"] = "Click to stop tracking in Blizzard objectives."
L["TRACK_SLOT_DISABLED_COMPLETED"] = "Completed achievements cannot be tracked in objectives."

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s of %s (%s%%)"

-- Settings - General Tooltips
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Display stack counts on items in the storage and items view"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Show or hide the Weekly Planner section inside the Characters tab"
L["LOCK_MINIMAP_TOOLTIP"] = "Lock the minimap button in place so it cannot be dragged"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplier for scroll speed (1.0x = 28 px per step)"
L["UI_SCALE"] = "UI Scale"
L["UI_SCALE_TOOLTIP"] = "Scale the entire addon window. Reduce if the window takes up too much screen space."

-- Settings - Tab Filtering
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignore Warband Bank Tab %d from automatic scanning"
L["IGNORE_SCAN_FORMAT"] = "Ignore %s from automatic scanning"

-- Settings - Notifications
L["ENABLE_NOTIFICATIONS"] = "Enable All Notifications"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Master toggle — disables all popup notifications, chat alerts, and visual effects below"
L["VAULT_REMINDER"] = "Weekly Vault Reminder"
L["VAULT_REMINDER_TOOLTIP"] = "Show a reminder popup on login when you have unclaimed Great Vault rewards"
L["LOOT_ALERTS"] = "New Collectible Popup"
L["LOOT_ALERTS_TOOLTIP"] = "Master toggle for collectible popups. Disabling this hides all collectible notifications."
L["LOOT_ALERTS_MOUNT"] = "Mount Notifications"
L["LOOT_ALERTS_MOUNT_TOOLTIP"] = "Show notifications when you collect a new mount."
L["LOOT_ALERTS_PET"] = "Pet Notifications"
L["LOOT_ALERTS_PET_TOOLTIP"] = "Show notifications when you collect a new pet."
L["LOOT_ALERTS_TOY"] = "Toy Notifications"
L["LOOT_ALERTS_TOY_TOOLTIP"] = "Show notifications when you collect a new toy."
L["LOOT_ALERTS_TRANSMOG"] = "Appearance Notifications"
L["LOOT_ALERTS_TRANSMOG_TOOLTIP"] = "Show notifications when you collect a new armor or weapon appearance."
L["LOOT_ALERTS_ILLUSION"] = "Illusion Notifications"
L["LOOT_ALERTS_ILLUSION_TOOLTIP"] = "Show notifications when you collect a new weapon illusion."
L["LOOT_ALERTS_TITLE"] = "Title Notifications"
L["LOOT_ALERTS_TITLE_TOOLTIP"] = "Show notifications when you earn a new title."
L["LOOT_ALERTS_ACHIEVEMENT"] = "Achievement Notifications"
L["LOOT_ALERTS_ACHIEVEMENT_TOOLTIP"] = "Show notifications when you earn a new achievement."
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Replace Achievement Popup"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Replace Blizzard's default achievement popup with the Warband Nexus notification style"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS"] = "Criteria Progress Toast"
L["SHOW_CRITERIA_PROGRESS_NOTIFICATIONS_TOOLTIP"] = "Show a small notification when an achievement criteria is completed (Progress X/Y and criteria name)."
L["CRITERIA_PROGRESS_MSG"] = "Progress"
L["CRITERIA_PROGRESS_FORMAT"] = "Progress %d/%d"
L["CRITERIA_PROGRESS_CRITERION"] = "Criteria"
L["ACHIEVEMENT_PROGRESS_TITLE"] = "Achievement Progress"
L["REPUTATION_GAINS"] = "Rep Gains in Chat"
L["REPUTATION_GAINS_TOOLTIP"] = "Show [WN-Reputation] lines only for standing the game reports in chat (plus renown level-ups and delve companion XP loot). Does not broadcast every faction that changed during a scan."
L["CURRENCY_GAINS"] = "Currency Gains in Chat"
L["CURRENCY_GAINS_TOOLTIP"] = "Display currency gain messages in chat when you earn currencies"
L["SCREEN_FLASH_EFFECT"] = "Flash on Rare Drop"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Play a screen flash animation when you finally obtain a collectible after multiple farming attempts"
L["TRY_COUNTER_DROP_SCREENSHOT"] = "Screenshot on tracked drop"
L["TRY_COUNTER_DROP_SCREENSHOT_TOOLTIP"] = "Take an automatic game screenshot shortly after the popup when a try-tracked mount, pet, toy, or illusion drops. Turn off if you do not want extra files in your Screenshots folder."
L["AUTO_TRY_COUNTER"] = "Auto-Track Drop Attempts"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Automatically count failed drop attempts when looting NPCs, rares, bosses, fishing, or containers. With this on, each counted miss also prints a short line to chat (see Try counter chat output below for Loot vs separate filter vs all tabs). Attempt totals update in the UI; obtained / reset lines still print as before. Moving from Rarity: enable Rarity once and use the Try Counter section in these settings (Rarity handoff / backup restore), then you can disable Rarity."
L["SETTINGS_ESC_HINT"] = "Press |cff999999ESC|r to close this window."
L["HIDE_TRY_COUNTER_CHAT"] = "Hide Attempts on Chat"
L["HIDE_TRY_COUNTER_CHAT_TOOLTIP"] = "Suppress all try counter messages in chat ([WN-Counter], [WN-Drops], obtained/caught lines). Attempt totals still update in the UI and To-Do tab. Popups and screen flash are unchanged.\n\nWhile enabled, instance entry drop lines and chat routing options below are disabled."
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES"] = "Instance entry: list drops in chat"
L["TRYCOUNTER_INSTANCE_ENTRY_DROP_LINES_TOOLTIP"] = "When you enter a dungeon or raid that has Try Counter collectibles, print one |cff9370DB[WN-Drops]|r line per item:\n• Collectible link\n• Required difficulty (|cff00ff00green|r ok, |cffff6666red|r wrong, |cffffaa00amber|r unknown)\n• Attempt count or collected\n\nLarge instances cap at 18 lines plus |cff00ccff/wn check|r. Turn off for the short hint only."
L["TRYCOUNTER_CHAT_ROUTE_LABEL"] = "Try counter chat output"
L["TRYCOUNTER_CHAT_ROUTE_DESC"] = "Where try-counter lines are printed. Default matches tabs that show Loot. “Warband Nexus” uses the addon’s own message group (WN_TRYCOUNTER) so you can show try lines on different tabs than general loot; Blizzard’s chat settings may list it under that name when you right-click a tab → Settings. “All tabs” sends to every numbered chat window (ignores filters)."
L["TRYCOUNTER_CHAT_ROUTE_LOOT"] = "1) Same tabs as Loot (default)"
L["TRYCOUNTER_CHAT_ROUTE_DEDICATED"] = "2) Warband Nexus (separate filter)"
L["TRYCOUNTER_CHAT_ROUTE_ALL_TABS"] = "3) All standard chat tabs"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_BTN"] = "Add try counter to selected chat tab"
L["TRYCOUNTER_CHAT_ADD_TO_TAB_TOOLTIP"] = "Click the chat tab you want, then press this. Best for “Warband Nexus (separate filter)” mode. Adds the WN_TRYCOUNTER message group to that tab."
L["TRYCOUNTER_CHAT_ADD_TO_TAB_OK"] = "|cff9966ff[Warband Nexus]|r Try counter enabled on the selected chat tab."
L["TRYCOUNTER_CHAT_ADD_TO_TAB_FAIL"] = "|cffff6600[Warband Nexus]|r Could not update the chat tab (no chat frame or API blocked)."
L["DURATION_LABEL"] = "Duration"
L["DAYS_LABEL"] = "days"
L["WEEKS_LABEL"] = "weeks"
L["EXTEND_DURATION"] = "Extend Duration"

-- Settings - Position
L["DRAG_POSITION_MSG"] = "Drag the green frame to set popup position. Right-click to confirm."
L["DRAG_BOTH_POSITION_MSG"] = "Drag to position. Right-click to save same position for notification and criteria."
L["POSITION_RESET_MSG"] = "Popup position reset to default (Top Center)"
L["POSITION_SAVED_MSG"] = "Popup position saved!"
L["TEST_NOTIFICATION_TITLE"] = "Test Notification"
L["TEST_NOTIFICATION_MSG"] = "Position test"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notification"

-- Settings - Theme & Appearance
L["THEME_APPEARANCE"] = "Theme & Appearance"
L["SETTINGS_SECTION_THEME_COLORS"] = "Colors & accent"
L["SETTINGS_SECTION_THEME_TYPOGRAPHY"] = "Fonts & readability"
L["COLOR_PURPLE"] = "Purple"
L["COLOR_PURPLE_DESC"] = "Classic purple theme (default)"
L["COLOR_BLUE"] = "Blue"
L["COLOR_BLUE_DESC"] = "Cool blue theme"
L["COLOR_GREEN"] = "Green"
L["COLOR_GREEN_DESC"] = "Nature green theme"
L["COLOR_RED"] = "Red"
L["COLOR_RED_DESC"] = "Fiery red theme"
L["COLOR_ORANGE"] = "Orange"
L["COLOR_ORANGE_DESC"] = "Warm orange theme"
L["COLOR_CYAN"] = "Cyan"
L["COLOR_CYAN_DESC"] = "Bright cyan theme"
L["USE_CLASS_COLOR_ACCENT"] = "Use class color as accent"
L["USE_CLASS_COLOR_ACCENT_TOOLTIP"] = "Use your current character's class color for accents, borders, and tabs. Falls back to your saved theme color when the class cannot be resolved."

-- Settings - Font
L["FONT_FAMILY"] = "Font Family"
L["FONT_FAMILY_TOOLTIP"] = "Choose the font used throughout the addon UI"
L["FONT_SCALE"] = "Font Scale"
L["FONT_SCALE_TOOLTIP"] = "Adjust font size across all UI elements"
L["ANTI_ALIASING"] = "Anti-Aliasing"
L["ANTI_ALIASING_DESC"] = "Font edge rendering style (affects readability)"
L["FONT_SCALE_WARNING"] = "Warning: Higher font scale may cause text overflow in some UI elements."
L["RESOLUTION_NORMALIZATION"] = "Auto-Scale for Resolution"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Adjust font sizes for your monitor resolution (4K vs 1080p). WoW UI Scale still scales text with the rest of the interface; this option does not cancel UI Scale."

-- Settings - Advanced
L["ADVANCED_SECTION"] = "Advanced"

-- Settings - Module Management
L["MODULE_MANAGEMENT"] = "Module Management"
L["MODULE_MANAGEMENT_DESC"] = "Enable or disable specific data collection modules. Disabling a module will stop its data updates and hide its tab from the UI."
L["MODULE_CURRENCIES"] = "Currencies"
L["MODULE_CURRENCIES_DESC"] = "Track account-wide and character-specific currencies (Gold, Honor, Conquest, etc.)"
L["MODULE_REPUTATIONS"] = "Reputations"
L["MODULE_REPUTATIONS_DESC"] = "Track reputation progress with factions, renown levels, and paragon rewards"
L["MODULE_ITEMS"] = "Bank"
L["MODULE_ITEMS_DESC"] = "Track Warband Bank items, search functionality, and item categories"
L["MODULE_STORAGE"] = "Storage"
L["MODULE_STORAGE_DESC"] = "Track character bags, personal bank, and Warband Bank storage"
L["MODULE_PVE"] = "PvE"
L["MODULE_PVE_DESC"] = "Track Mythic+ dungeons, raid progress, and Weekly Vault rewards"
L["MODULE_PLANS"] = "To-Do"
L["MODULE_PLANS_DESC"] = "Track personal goals for mounts, pets, toys, achievements, and custom tasks"
L["MODULE_PROFESSIONS"] = "Professions"
L["MODULE_PROFESSIONS_DESC"] = "Track profession skills, concentration, knowledge, and recipe companion window"
L["MODULE_GEAR"] = "Gear"
L["MODULE_GEAR_DESC"] = "Gear management and item level tracking across characters"
L["MODULE_COLLECTIONS"] = "Collections"
L["MODULE_COLLECTIONS_DESC"] = "Mounts, pets, toys, transmog, and collection overview"
L["MODULE_TRY_COUNTER"] = "Try Counter"
L["MODULE_TRY_COUNTER_DESC"] = "Automatic drop attempt tracking for NPC kills, bosses, fishing, and containers. Disabling stops all try count processing, tooltips, and notifications."
L["PROFESSIONS_DISABLED_TITLE"] = "Professions"

-- Tooltip Service
L["ITEM_NUMBER_FORMAT"] = "Item #%s"
L["WN_SEARCH"] = "WN Search"

-- Notification Manager
L["COLLECTED_MOUNT_MSG"] = "You have collected a mount"
L["COLLECTED_PET_MSG"] = "You have collected a battle pet"
L["COLLECTED_TOY_MSG"] = "You have collected a toy"
L["COLLECTED_ILLUSION_MSG"] = "You have collected an illusion"
L["COLLECTED_ITEM_MSG"] = "You received a rare drop"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Achievement completed!"
L["HIDDEN_ACHIEVEMENT"] = "Hidden Achievement"
L["EARNED_TITLE_MSG"] = "You have earned a title"
L["COMPLETED_PLAN_MSG"] = "You have completed a plan"
L["DAILY_QUEST_CAT"] = "Daily Quest"
L["WORLD_QUEST_CAT"] = "World Quest"
L["WEEKLY_QUEST_CAT"] = "Weekly Quest"
L["SPECIAL_ASSIGNMENT_CAT"] = "Special Assignment"
L["DELVE_CAT"] = "Delve"
L["WORLD_CAT"] = "World"
L["ACTIVITY_CAT"] = "Activity"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progress"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progress Completed"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Weekly Vault Plan - %s"
L["ALL_SLOTS_COMPLETE"] = "All Slots Complete!"
L["QUEST_COMPLETED_SUFFIX"] = "Completed"
L["WEEKLY_VAULT_READY"] = "Weekly Vault Ready!"
L["VAULT_LOOT_READY_SHORT"] = "Ready!"
L["VAULT_TRACK_WAITING_RESET"] = "Waiting reset"
L["VAULT_TRACK_WAITING_RESET_SHORT"] = "Reset"
L["VAULT_SUMMARY_ALL_TITLE"] = "Great Vault — all characters"
L["VAULT_SUMMARY_ALL_SUB"] = "Raid · Mythic+ · World columns match the PvE tab rows."
L["VAULT_SUMMARY_COL_NAME"] = "Character"
L["VAULT_SUMMARY_COL_REALM"] = "Realm"
L["VAULT_SUMMARY_NO_CHARS"] = "No tracked characters."
L["VAULT_SUMMARY_MORE"] = "… and %d more (see PvE list)."
L["UNCLAIMED_REWARDS"] = "You have unclaimed rewards"

-- Minimap Button
L["TOTAL_GOLD_LABEL"] = "Total Gold:"
L["MINIMAP_CHARS_GOLD"] = "Characters Gold:"
L["LEFT_CLICK_TOGGLE"] = "Left-Click: Toggle window"
L["RIGHT_CLICK_PLANS"] = "Right-Click: Open Plans"
L["MINIMAP_SHOWN_MSG"] = "Minimap button shown"
L["MINIMAP_HIDDEN_MSG"] = "Minimap button hidden (re-enable under Warband Nexus → Settings → Minimap)."
L["TOGGLE_WINDOW"] = "Toggle Window"
L["SCAN_BANK_MENU"] = "Scan Bank"
L["TRACKING_DISABLED_SCAN_MSG"] = "Character tracking is disabled. Enable tracking in settings to scan bank."
L["SCAN_COMPLETE_MSG"] = "Scan complete!"
L["BANK_NOT_OPEN_MSG"] = "Bank is not open"
L["OPTIONS_MENU"] = "Options"
L["HIDE_MINIMAP_BUTTON"] = "Hide Minimap Button"
L["MENU_UNAVAILABLE_MSG"] = "Right-click menu unavailable"
L["USE_COMMANDS_MSG"] = "Use /wn show, /wn options, /wn help"

-- SharedWidgets (extended)
L["DATA_SOURCE_TITLE"] = "Data Source Information"
L["DATA_SOURCE_USING"] = "This tab is using:"
L["DATA_SOURCE_MODERN"] = "Modern cache service (event-driven)"
L["DATA_SOURCE_LEGACY"] = "Legacy direct DB access"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Needs migration to cache service"
L["GLOBAL_DB_VERSION"] = "Global DB Version:"

-- Information Dialog - Tab Headers
L["INFO_TAB_CHARACTERS"] = "Characters"
L["INFO_TAB_ITEMS"] = "Bank"
L["INFO_TAB_STORAGE"] = "Storage"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Reputations"
L["INFO_TAB_CURRENCY"] = "Currency"
L["INFO_TAB_PLANS"] = "To-Do"
L["INFO_TAB_GEAR"] = "Gear"
L["INFO_TAB_COLLECTIONS"] = "Collections"
L["INFO_TAB_STATISTICS"] = "Statistics"
L["INFO_CREDITS_SECTION_TITLE"] = "Credits & thanks"
L["INFO_CREDITS_LORE_SUBTITLE"] = "Special Thanks"
L["INFO_FEATURES_SECTION_TITLE"] = "Features overview"
L["HEADER_INFO_TOOLTIP"] = "Addon guide & credits"
L["HEADER_INFO_TOOLTIP_HINT"] = "Contributors and feature help — credits are at the top."
L["CONTRIBUTORS_TITLE"] = "Contributors"
L["THANK_YOU_MSG"] = "Thank you for using Warband Nexus!"

-- Information Dialog - Professions Tab
L["INFO_TAB_PROFESSIONS"] = "Professions"
L["PROFESSIONS_INFO_DESC"] = "Track profession skills, concentration, knowledge, and specialization trees across all characters. Includes Recipe Companion for reagent sourcing."

-- Information Dialog - Gear & Collections Tabs
L["GEAR_DESC"] = "View equipped gear, upgrade opportunities, storage recommendations (BoE/Warbound), and cross-character upgrade candidates with item level tracking."
L["COLLECTIONS_DESC"] = "Overview of mounts, pets, toys, transmog, and other collectibles across your account. Track collection progress and find missing items."

-- Command Help Strings
L["AVAILABLE_COMMANDS"] = "Available commands:"
L["CMD_OPEN"] = "Open addon window"
L["CMD_PLANS"] = "Toggle To-Do Tracker window"
L["CMD_FIRSTCRAFT"] = "List first-craft bonus recipes per expansion (open profession first)"
L["CMD_OPTIONS"] = "Open settings"
L["CMD_MINIMAP"] = "Toggle minimap button"
L["CMD_CHANGELOG"] = "Show changelog"
L["CMD_DEBUG"] = "Toggle debug mode"
L["CMD_PROFILER"] = "Performance profiler"
L["CMD_HELP"] = "Show this list"

L["PLANS_NOT_AVAILABLE"] = "Plans Tracker not available."
L["MINIMAP_NOT_AVAILABLE"] = "Minimap button module not loaded."
L["PROFILER_NOT_LOADED"] = "Profiler module not loaded."
L["UNKNOWN_COMMAND"] = "Unknown command."
L["TYPE_HELP"] = "Type"
L["FOR_AVAILABLE_COMMANDS"] = "for available commands."
L["UNKNOWN_DEBUG_CMD"] = "Unknown debug command:"
L["DEBUG_ENABLED"] = "Debug mode ENABLED."
L["DEBUG_RELOAD_UI_BTN"] = "Reload UI"
L["DEBUG_RELOAD_UI_TOOLTIP"] = "Reload the entire interface (/reload). WoW cannot hot-reload addon Lua; use this after saving files."
L["DEBUG_DISABLED"] = "Debug mode DISABLED."
L["CHARACTER_LABEL"] = "Character:"
L["TRACK_USAGE"] = "Usage: enable | disable | status"

-- Welcome Messages
L["CLICK_TO_COPY"] = "Click to copy invite link"

L["WELCOME_MSG_FORMAT"] = "Welcome to Warband Nexus v%s"
L["WELCOME_TYPE_CMD"] = "Please type"
L["WELCOME_OPEN_INTERFACE"] = "to open the interface."
L["WELCOME_NEW_VERSION_CHAT"] = "|cffffff00What's New:|r a popup may appear above chat, or type |cffffff00/wn changelog|r."
L["CONFIG_SHOW_LOGIN_CHAT"] = "Login message in chat"
L["CONFIG_SHOW_LOGIN_CHAT_DESC"] = "Print a short welcome line when notifications are enabled. Uses the System message group and a visible chat tab so addons like Chattynator can show it. (The What's New window is separate — fullscreen popup.)"
L["CONFIG_HIDE_PLAYED_TIME_CHAT"] = "Hide Time Played in chat"
L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"] = "Filter out Total time played and Time played this level system messages. Turn off to show them again (including when you type /played)."

-- What's New (only CHANGELOG_V<x><y><z> for current ADDON_VERSION — see NotificationManager.VersionToChangelogKey)

-- What's New / changelog body for ADDON_VERSION 3.0.0 (key CHANGELOG_V300)
L["CHANGELOG_V300"] = [=[v3.0.0 (2026-05-09)

Bundled highlights (prior patch notes through 2.7.2)

Saved Instances & lockouts
- Account-wide Saved Instances window: raid + dungeon lockouts, themed Factory scroll, collapse/expand, symmetric header columns, FontManager typography, clearer borders and resize behavior.
- Backend: dungeon rows with difficulty pills; secret-safe raid detection; lockout freshness; collapse persistence; DataService staggered PvE capture aligned with PvECacheService.

Try Counter & sources
- ENCOUNTER_END-driven counting (next-frame schedule); clearer miss/stat paths; rare-farm off-by-one fix; encounter-specific dedup; per-corpse GUID dedup; NEW_MOUNT_ADDED / NEW_PET_ADDED backup; safer multi-event registration.
- CollectibleSourceDB / locale rows for Sylvanas SoD Mythic chest attribution across clients.

Gear, Vault & currencies
- Quick-access menu (Vault Tracker, Saved Instances, Plans, Settings).
- PvE Vault Status column + per-slot vault tooltips; live C_WeeklyRewards.HasAvailableRewards for ready state; alt weekly-reset promotion fixes; Status column width for localized labels.
- Dawncrest crest farming tooltips; Shift-expand currency rows (`<bag> · <earned> / <cap>`); tier-colored upgrade tracks; subtitle hints; `/wn maxonly` (hide alts below level 80).
- Gear paperdoll height/columns; recommendations scrollbar auto-hide; full currency names; Vault Tracker on FontManager; character order from Characters tab; enchant rank glyphs (R1–R3); Voidcore / coffer display fixes.

Plans & Collections
- Achievement Journal circular WN badge (add/remove To-Do), localized.
- Plans Tracker mirrors To-Do: ParseMultipleSources rows, type badges, portrait-aligned info rows, tries/delete alignment, ExpandableRow layout fixes, full achievement body text without MaxLines caps.
- Collections › Recent Obtains: full-height cards, auto-hiding scrollbars, tooltip detail (earned/obtained-by wording); 2.7.2 polish — title/subtitle, per-category reset, labeled tooltip sections, Plans metrics (`UI_PLANS_CARD_METRICS`), Weekly Progress accordion tween + scroll resync, Show Planned always visible (disabled on To-Do/Weekly with tooltip), themed checkbox accent fixes, tighter plan source icons.

Locales
- `SHOW_PLANNED_DISABLED_HERE` and `COLLECTIONS_RECENT_*` for all shipped languages; restored collections strings (koKR / ruRU / zhTW) and mojibake fixes (deDE / es / fr).

Full merged notes: repository CHANGES.md / CHANGES.txt · listing on CurseForge / Wago.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.7.0 (key CHANGELOG_V270)
L["CHANGELOG_V270"] = [=[v2.7.0 (2026-05-05)

Saved Instances — layout + readability pass
- Reworked the view into a clean header/row structure: `Instance (Difficulty)` with character progress rows directly underneath.
- Added per-group collapse/expand controls with larger chevrons and stable collapse state while the window is open.
- Added fixed right-side columns in headers (character count + progress) for symmetric vertical alignment across all groups.
- Synced row progress formatting with header progress formatting for consistent numeric alignment.

Saved Instances — theme and typography parity
- Header and character rows now use outlined borders (theme-colored) for clearer section boundaries.
- Font rendering now uses the selected addon font through `FontManager` in the Saved Instances surface.
- Theme refresh now re-renders Saved Instances when open, so color/font changes follow the main addon window immediately.

Saved Instances — scrolling + interaction
- Switched to the standardized Factory scrollframe + themed scrollbar column used by the main addon UI.
- Scrollbar visibility now updates automatically based on content size.
- Resizable window behavior was retained and integrated with content/scroll refresh.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.6.8 (key CHANGELOG_V268)
L["CHANGELOG_V268"] = [=[v2.6.8 (2026-05-04)

Try Counter — architectural overhaul
- Counting is now event-driven by ENCOUNTER_END (next frame instead of a 5-second wait). Chests, personal-loot bags, and post-cinematic loot can be opened seconds, hours, or days later without re-counting or off-by-one.
- Stat-backed miss path now prints "N attempts for [item]" — previously the reseed could complete silently and Sylvanas / LFR Jaina kills produced no try-counter line at all.
- Fixed off-by-one on open-world rare farms: 4 misses followed by a drop on kill 5 now correctly says "after 5 attempts" (was "after 4").
- Fixed encounter fallback being silently suppressed by unrelated tier-token / currency loot (Anima Vessels, etc.) inside the kill window.
- Added definitive NEW_MOUNT_ADDED / NEW_PET_ADDED backup so post-cinematic chest grants always emit the correct obtained line, even when the primary loot-window detection misses.

Sylvanas (Sanctum of Domination, Mythic)
- All client locales now resolve the Sylvanas encounter for Vengeance's Reins try counting. Added a slot-first outcome rule for the Mythic chest so secret-GUID loot is attributed by tracked itemID rather than failing to bind to the kill.

Saved Instances
- Now lists dungeon lockouts alongside raids: 5-player Normal / Heroic / Mythic / M+ rows surface with their own difficulty pills.
- Lockouts are filtered by reset time so expired rows no longer linger; collapse state per instance persists across sessions.
- isRaid is treated as advisory — falls back to DifficultyID + maxPlayers when the value is wrapped or missing in Midnight 12.0 contexts.

Data collection
- Per-character lockouts capture both raid and dungeon entries (matches the cache pipeline) so the Vault button now reflects everything you're saved to.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.6.7 (key CHANGELOG_V267)
L["CHANGELOG_V267"] = [=[v2.6.7 (2026-04-29)

PvE — Great Vault tracker
- Added Weekly Vault tracker visibility improvements for unclaimed rewards and completed vault rows.
- Claimable Great Vault rewards now show the short "loot ready" status label consistently across PvE and Plans surfaces.

UI — minimap shortcut
- Improved quick access flow through the minimap button and /wn minimap toggle shortcut.

Collections — loot alerts
- Bag scan now checks the permanent notified cache before firing mount, pet, and toy collectible toasts.
- Fixed repeated collectible popups caused by duplicate BAG_UPDATE-driven re-detection.
- Already-notified collectibles now stay silent across reloads and relogs.

Collections — recent list
- Recent obtained entries are now retention-pruned (7 days) so stale rows are cleaned automatically.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.6.6b (key CHANGELOG_V266)
L["CHANGELOG_V266"] = [=[v2.6.6b (2026-04-28)

Gear tab — Storage Upgrade Recommendations
- Recommendations now respect transferability: only BoE, Warbound, and Warbound-until-equipped items can surface from another character's bags or the Warband Bank. Soulbound items that were once BoE but have since been equipped are filtered out (they cannot be transferred).
- Two-handed main hand suppresses off-hand suggestions: equipping a 2H staff/polearm no longer brings up low-ilvl off-hand "upgrades" against an empty slot.
- Warband-until-Equipped (WuE) items are now correctly identified via the tooltip text — Blizzard's bindType API reports them as plain "BoE", which previously mislabelled every WuE item.
- Cross-character cold-cache fix: WuE and BoE items in another character's bag are now resolved through Blizzard's GET_ITEM_INFO_RECEIVED warm-up so their true ilvl (e.g. Champion 3/6 = 253) is used instead of the template base ilvl.
- Stat and level filters relaxed when previewing alts: C_Item.GetItemStats only reports the logged-in character's primary, and stale DB level snapshots can lag the live character — both checks now run only when the selected tab character is the player.

Gear tab — UI
- Storage Upgrade Recommendations card revised: subtitle clarifies "Transferable items only (BoE / Warbound)", row spacing increased, source font weight tuned for readability.
- Compact bind labels in the recommendation list: BoE / WuE / WB instead of long phrases.

Event-driven UI refresh
- Gear tab now refreshes on bag updates (newly looted BoEs surface immediately).
- Money, currency variants, collection events, vault events, character tracking changes, gold management edits, and bank money log updates all trigger the appropriate tab redraw.
- GET_ITEM_INFO_RECEIVED listener: gear tab re-scans once cold-cache hyperlinks finish async resolution.

Collections — loot alerts
- Bag-scan collectible detection now skips mounts, pets, and toys already marked as notified in SavedVariables (permanent dedupe).
- Prevents duplicate collection popups when repeated bag updates re-detected the same collectible.

Single-roof version system (no more wiped data on releases)
- Addon releases no longer invalidate any cache. Bumping the addon version preserves all character state, vault progress, mythic key history, and currency totals.
- Game build (WoW patch) is the trigger for API-bound cache invalidation (reputation, collection) where Blizzard's API shape may have shifted.
- Per-cache schema versions live in Constants.VERSIONS.CACHE; only the cache whose integer is bumped gets refreshed.
- Every invalidation creates an automatic backup at db.global.cacheBackups[name] before resetting; recoverable via WarbandNexus:RestoreCacheBackup(name).

Diagnostics
- New /wn dumpitem <itemID> command: prints all API data + every persisted bag/bank/warband-bank instance of an item to chat for troubleshooting.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.6.4 (key CHANGELOG_V264)
L["CHANGELOG_V264"] = [=[v2.6.4 (2026-04-26)

- Ashes of Belo'ren and L'ura references updated.
- Less delay when the Characters, Gear, and PvE tabs refresh their data.
- Bug fixes and small improvements.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.6.3 (key CHANGELOG_V263)
L["CHANGELOG_V263"] = [=[v2.6.3 (2026-04-21)

PvE cache & SavedVariables
- Character keys are normalized (GetCanonicalCharacterKey) on every PvE cache read/write so each character uses one SV bucket — migration, import, and live updates no longer split the same toon across different key spellings.
- Mythic+ dungeon scores: avoid wiping good SavedVariables when the API returns overall 0 with no per-map data while SV still has progress; per-map merge keeps prior rows when the API snapshot is all zeros.
- Great Vault: empty/nil C_WeeklyRewards.GetActivities() does not overwrite persisted vault data (wait for server / open Great Vault).
- Import from legacy/migration: skip destructive mythic, vault, or lockout writes when the incoming snapshot is empty but existing cache still has rows.
- Keystone: only clear stored key when the API reports level 0; nil map/level during API races does not wipe a cached key.
- MYTHIC_PLUS_CURRENT_AFFIX_UPDATE: refresh affixes; prune keystones by weekly reset timestamp only (no blanket wipe of all characters' keys).
- PLAYER_LOGOUT: persist cache without running a full PvE refresh (logout APIs often return empty/zero).

Debug (Config → Debug Mode)
- Optional chat diagnostics prefixed |cff00ccff[PvE Cache]|r: dungeon score save/skip, keystone decisions, Great Vault API empty vs saved, ImportLegacy branches, and bestRuns overall score line (parallel to dungeonScores).

Collections UI
- Search bar uses the full search row on the Recent sub-tab (Owned/Missing hidden); anchors refresh when switching sub-tabs so the field no longer leaves an empty reserved strip on the right.

CurseForge: Warband Nexus]=]

-- Keep previous version text for /wn changelog history if ever keyed by version
L["CHANGELOG_V262"] = [=[v2.6.2 (2026-04-21)

Currency & chat
- Fixed WN-Currency chat queue (FIFO with table.remove) so rapid lines are not dropped.
- Dawncrest / split currencies: fewer duplicate notifications when bag quantity and totalEarned update on different ticks; short defer when useful.
- Block internal Blizzard currency labels (Delves / System / Seasonal Affix / Events Active|Maximum, etc.) from WN-Currency; validate meta names on live API as well.
- Login: suppress WN-Currency notifications until the first full currency scan completes (stops login CURRENCY_DISPLAY_UPDATE burst from flooding chat).

Reputation
- Removed duplicate WN-Reputation line from companion delta watcher; DB pipeline owns chat.
- Companion XP loot: seed pre standing / renown so level-up and standing lines behave correctly.
- Optional "Reached renown level %d" (locale WN_REPUTATION_RENOWN_LEVEL_UP); renown level-up derived when MAJOR_FACTION events do not fire.

Keybind & settings UI
- Toggle keybind cannot be ESC; legacy ESC bindings are cleared on load/save (game menu path stays reliable).
- Settings: dedicated key capture (clear, combat-blocked); main window keyboard is suppressed while Settings is open so movement, chat, and Blizzard keybinding capture keep working.
- Settings root keeps frame keyboard off (large panel no longer steals the global key stack).

ESC & WindowManager
- ToggleGameMenu uses hooksecurefunc only — never replace the global (avoids taint / protected-call failures such as SpellStopCasting).
- Same ESC press no longer closes two layers (addon + game menu); aligns with CloseSpecialWindows / UISpecialFrames for the Settings panel.
- Combat restore no longer forces keyboard back on for the Settings panel.

Weekly Vault / PvE UI (ready state)
- When Great Vault rewards are claimable (live check or cached), Weekly Vault bars on plan cards, the Plans tracker, and the PvE tab show the localized short label (VAULT_LOOT_READY_SHORT) instead of only threshold ticks.
- PvE Dawncrest columns use Constants.DAWNCREST_UI (single source with Gear / currency).

Commands & professions
- /wn keys (party): strip link pipes from aggregated text for Midnight chat rules; use a visible separator between entries when packing lines.
- Profession window: optional "(N)" craft-from-materials count appended to the schematic title after init.

Localization & tooling
- Locale key parity maintained; scripts/check_locales.py for audits.

CurseForge: Warband Nexus]=]


-- Confirm / Tracking Dialog
L["CONFIRM_ACTION"] = "Confirm Action"
L["CONFIRM"] = "Confirm"
L["ENABLE_TRACKING_FORMAT"] = "Enable tracking for |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "Disable tracking for |cffffcc00%s|r?"

-- Reputation Section Headers
L["REP_SECTION_ACCOUNT_WIDE"] = "Account-Wide Reputations (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Character-Based Reputations (%s)"

-- Reputation Processor Labels
L["REP_REWARD_WAITING"] = "Reward Waiting"
L["REP_PARAGON_LABEL"] = "Paragon"

-- Reputation Loading States
L["REP_LOADING_PREPARING"] = "Preparing..."
L["REP_LOADING_INITIALIZING"] = "Initializing..."
L["REP_LOADING_FETCHING"] = "Fetching reputation data..."
L["REP_LOADING_PROCESSING"] = "Processing %d factions..."
L["REP_LOADING_SAVING"] = "Saving to database..."
L["REP_LOADING_COMPLETE"] = "Complete!"

-- Status / Footer
L["COMBAT_LOCKDOWN_MSG"] = "Cannot open window during combat. Please try again after combat ends."
L["BANK_IS_ACTIVE"] = "Bank is Active"
-- Table Headers (SharedWidgets, Professions)

-- Search / Empty States
L["NO_ITEMS_MATCH"] = "No items match '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "No items match your search"
L["ITEMS_SCAN_HINT"] = "Items are scanned automatically. Try /reload if nothing appears."
L["ITEMS_WARBAND_BANK_HINT"] = "Open Warband Bank to scan items (auto-scanned on first visit)"

-- Currency Transfer Steps

-- Plans UI Extra
L["ADDED"] = "Added"
L["WEEKLY_VAULT_TRACKER"] = "Weekly Vault Tracker"
L["VAULT_TRACKER_STATUS_PENDING"] = "Pending..."
L["VAULT_TRACKER_STATUS_READY_CLAIM"] = "Ready to Claim"
L["VAULT_TRACKER_STATUS_SLOTS_READY"] = "Slots Earned"

-- Easy Access (floating shortcut button)
L["CONFIG_VAULT_BUTTON"] = "Easy Access"
L["CONFIG_VAULT_BUTTON_DESC"] = "Show the draggable Easy Access shortcut on screen. Left-click runs your chosen action; right-click opens the WN shortcut menu."
L["CONFIG_VAULT_BUTTON_SECTION"] = "Easy Access"
L["CONFIG_VAULT_OPT_ENABLED"] = "Enable Easy Access"
L["CONFIG_VAULT_OPT_ENABLED_DESC"] = "Show the draggable Easy Access shortcut on screen."
L["CONFIG_VAULT_OPT_MOUSEOVER"] = "Hide Until Mouseover"
L["CONFIG_VAULT_OPT_MOUSEOVER_DESC"] = "Keep Easy Access invisible until the cursor is over its saved position."
L["CONFIG_VAULT_OPT_READY_ONLY"] = "Hide Until Ready"
L["CONFIG_VAULT_OPT_READY_ONLY_DESC"] = "Only show Easy Access when at least one character has a vault reward ready to claim."
L["CONFIG_VAULT_OPT_REALM"] = "Show Realm Names"
L["CONFIG_VAULT_OPT_REALM_DESC"] = "Show character realm names in Easy Access tables and tooltips."
L["CONFIG_VAULT_OPT_REWARD_ILVL"] = "Show Reward iLvl"
L["CONFIG_VAULT_OPT_REWARD_ILVL_DESC"] = "Show reward item levels in completed vault slots instead of ready-check icons."
L["CONFIG_VAULT_COL_RAID"] = "Raid Column"
L["CONFIG_VAULT_COL_RAID_DESC"] = "Show raid vault progress in the Easy Access tracker table."
L["CONFIG_VAULT_COL_DUNGEON"] = "Dungeon Column"
L["CONFIG_VAULT_COL_DUNGEON_DESC"] = "Show Mythic+ dungeon vault progress in the Easy Access tracker table."
L["CONFIG_VAULT_COL_WORLD"] = "World Column"
L["CONFIG_VAULT_COL_WORLD_DESC"] = "Show world activity vault progress in the Easy Access tracker table."
L["CONFIG_VAULT_COL_BOUNTY"] = "Trovehunter's Bounty Column"
L["CONFIG_VAULT_COL_BOUNTY_DESC"] = "Show Trovehunter's Bounty completion in the Easy Access tracker table."
L["CONFIG_VAULT_COL_VOIDCORE"] = "Nebulous Voidcore Column"
L["CONFIG_VAULT_COL_VOIDCORE_DESC"] = "Show Nebulous Voidcore progress in the Easy Access tracker table."
L["CONFIG_VAULT_COL_MANAFLUX"] = "Dawnlight Manaflux Column"
L["CONFIG_VAULT_COL_MANAFLUX_DESC"] = "Show Dawnlight Manaflux currency in the Easy Access tracker table."
L["CONFIG_VAULT_BUTTON_OPACITY"] = "Button Opacity"
L["CONFIG_VAULT_BUTTON_OPACITY_DESC"] = "Adjust Easy Access opacity when it is visible."
L["CONFIG_VAULT_OPT_SUMMARY_MOUSEOVER"] = "Warband Summary Mouseover"
L["CONFIG_VAULT_OPT_SUMMARY_MOUSEOVER_DESC"] = "Show the warband's vault summary on mouseover. Turning this off shows the current character's only."
L["CONFIG_VAULT_LEFT_CLICK_HEADER"] = "Left Click"
L["CONFIG_VAULT_LEFT_CLICK_PVE"] = "Left Click: PvE Tab"
L["CONFIG_VAULT_LEFT_CLICK_PVE_DESC"] = "Left-clicking Easy Access opens the PvE tab."
L["CONFIG_VAULT_LEFT_CLICK_CHARS"] = "Left Click: Characters Tab"
L["CONFIG_VAULT_LEFT_CLICK_CHARS_DESC"] = "Left-clicking Easy Access opens the Characters tab."
L["CONFIG_VAULT_LEFT_CLICK_VAULT"] = "Left Click: Vault Tracker"
L["CONFIG_VAULT_LEFT_CLICK_VAULT_DESC"] = "Left-clicking Easy Access opens the Vault Tracker window."
L["CONFIG_VAULT_LEFT_CLICK_SAVED"] = "Left Click: Saved Instances"
L["CONFIG_VAULT_LEFT_CLICK_SAVED_DESC"] = "Left-clicking Easy Access opens the Saved Instances mini window."
L["CONFIG_VAULT_LEFT_CLICK_PLANS"] = "Left Click: Plans/Todo"
L["CONFIG_VAULT_LEFT_CLICK_PLANS_DESC"] = "Left-clicking Easy Access opens the Plans/To-Do mini window."
L["CMD_QT"] = "Open Easy Access menu"
L["CONFIG_VAULT_QT_UNAVAILABLE"] = "Easy Access is not available yet."
L["VAULT_BUTTON_MENU_TITLE"] = "WN Menu"
L["VAULT_BUTTON_MENU_TRACKER"] = "Vault Tracker"
L["VAULT_BUTTON_MENU_SAVED"] = "Saved Instances"
L["VAULT_BUTTON_MENU_PLANS"] = "Plans / Todo"
L["VAULT_BUTTON_MENU_SETTINGS"] = "Settings"

-- Saved Instances window
L["SAVED_INSTANCES_TITLE"] = "Saved Instances"
L["SAVED_INSTANCES_EMPTY"] = "No raid or dungeon lockouts recorded yet.\nLog in a character with active lockouts to populate."
L["SAVED_INSTANCES_NO_FILTER_MATCH"] = "No instances match the current filters."
L["SAVED_INSTANCES_SUMMARY"] = "%d instances · %d characters"
L["SAVED_INSTANCES_WARBAND_CLEARED"] = "warband cleared"
L["SAVED_INSTANCES_EXPAND_HINT"] = "Click to expand character lockouts"
L["SAVED_INSTANCES_RESET_DAYS"] = "%dd"
L["SAVED_INSTANCES_RESET_HOURS"] = "%dh"
L["SAVED_INSTANCES_RESET_LESS_HOUR"] = "<1h"
L["DAILY_QUEST_TRACKER"] = "Daily Quest Tracker"

-- Achievement Popup
L["ACHIEVEMENT_NOT_COMPLETED"] = "Not Completed"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d pts"
L["ADD_PLAN"] = "To-Do"
L["PLANNED"] = "Planned"

-- PlanCardFactory Vault Slots
L["VAULT_SLOT_WORLD"] = "World"

-- PvE Extra
L["AFFIX_TITLE_FALLBACK"] = "Affix"

-- Chat Messages
L["WN_REPUTATION_RENOWN_LEVEL_UP"] = "Reached renown level %d"

-- PlansManager Messages
L["PLAN_COMPLETED"] = "Plan completed: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Weekly Vault - %s"
L["VAULT_PLANS_RESET"] = "Weekly Great Vault plans have been reset! (%d plan%s)"

-- Reminder System
L["SET_ALERT_TITLE"] = "Set Alert"
L["SET_ALERT"] = "Set Alert"
L["REMOVE_ALERT"] = "Remove Alert"
L["ALERT_ACTIVE"] = "Alert Active"
L["REMINDER_PREFIX"] = "Reminder"
L["REMINDER_DAILY_LOGIN"] = "Daily Login"
L["REMINDER_WEEKLY_RESET"] = "Weekly Reset"
L["REMINDER_DAYS_BEFORE"] = "%d days before reset"
L["REMINDER_ZONE_ENTER"] = "Entered %s"
L["REMINDER_OPT_DAILY"] = "Remind on daily login"
L["REMINDER_OPT_WEEKLY"] = "Remind after weekly reset"
L["REMINDER_OPT_DAYS_BEFORE"] = "Remind %d days before reset"
L["REMINDER_OPT_ZONE"] = "Remind when entering source zone"

-- Empty State Cards
L["NO_SCAN"] = "Not scanned"
L["NO_ADDITIONAL_INFO"] = "No additional information"

-- Character Tracking & Commands
L["TRACK_CHARACTER_QUESTION"] = "Do you want to track this character?"
L["CLEANUP_NO_INACTIVE"] = "No inactive characters found (90+ days)"
L["CLEANUP_REMOVED_FORMAT"] = "Removed %d inactive character(s)"
L["TRACKING_ENABLED_MSG"] = "Character tracking ENABLED!"
L["TRACKING_DISABLED_MSG"] = "Character tracking DISABLED!"
L["TRACKING_DISABLED"] = "Tracking DISABLED (read-only mode)"
L["STATUS_LABEL"] = "Status:"
L["ERROR_LABEL"] = "Error:"
L["ERROR_NAME_REALM_REQUIRED"] = "Character name and realm required"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s already has an active weekly plan"

-- Profiles (AceDB)

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "No criteria found"
L["NO_REQUIREMENTS_INSTANT"] = "No requirements (instant completion)"

-- Professions Tab
L["TAB_PROFESSIONS"] = "Professions"
L["TAB_COLLECTIONS"] = "Collections"
L["COLLECTIONS_SUBTITLE"] = "Mounts, pets, toys, and transmog overview"
L["COLLECTIONS_SUBTAB_RECENT"] = "Recent"
-- Collections sub-tab content headers (Recent + per-type; AceLocale returns key if missing — must define)
L["COLLECTIONS_CONTENT_TITLE_ACHIEVEMENTS"] = "Achievements"
L["COLLECTIONS_CONTENT_SUB_ACHIEVEMENTS"] = "Browse and search your achievements."
L["COLLECTIONS_CONTENT_TITLE_MOUNTS"] = "Mounts"
L["COLLECTIONS_CONTENT_SUB_MOUNTS"] = "Warband mount collection, sources, and preview."
L["COLLECTIONS_CONTENT_TITLE_PETS"] = "Pets"
L["COLLECTIONS_CONTENT_SUB_PETS"] = "Battle pets and companions across your account."
L["COLLECTIONS_CONTENT_TITLE_TOYS"] = "Toy Box"
L["COLLECTIONS_CONTENT_SUB_TOYS"] = "Toys and usable collectibles."
L["COLLECTIONS_CONTENT_TITLE_RECENT"] = "Recent Obtains"
L["COLLECTIONS_CONTENT_SUB_RECENT"] = "Newest achievements, mounts, pets, and toys recorded on your account."
L["COLLECTIONS_RECENT_JUST_NOW"] = "Just now"
L["COLLECTIONS_RECENT_MINUTES_AGO"] = "%d min ago"
L["COLLECTIONS_RECENT_HOURS_AGO"] = "%d hr ago"
L["COLLECTIONS_RECENT_DAYS_AGO"] = "%d days ago"
L["COLLECTIONS_ACQUIRED_LABEL"] = "Recorded"
L["COLLECTIONS_ACQUIRED_LINE"] = "%s: %s"
L["COLLECTIONS_RECENT_TAB_EMPTY"] = "Nothing recorded yet."
L["COLLECTIONS_RECENT_CHARACTER_SUFFIX"] = "|cff888888  ·  %s|r"
L["COLLECTIONS_RECENT_EMPTY"] = "Nothing recorded yet."
L["COLLECTIONS_RECENT_SEARCH_EMPTY"] = "No matching entries."
L["COLLECTIONS_RECENT_SECTION_NONE"] = "No entries yet."
L["COLLECTIONS_RECENT_CARD_RESET_TOOLTIP"] = "Clear recent entries for this category"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_CATEGORY"] = "Category"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_PROGRESS"] = "Progress"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_CHARACTER"] = "Character"
L["COLLECTIONS_RECENT_TOOLTIP_SECTION_TIME"] = "Recorded"
L["COLLECTIONS_RECENT_ROW_BY"] = "By %s"
L["COLLECTIONS_RECENT_ACH_HIDE_ALT_EARNED"] = "Completed on account before this character."
L["SELECT_MOUNT_FROM_LIST"] = "Select a mount from the list"
L["SELECT_PET_FROM_LIST"] = "Select a pet from the list"
L["SELECT_TO_SEE_DETAILS"] = "Select a %s to see details."
L["SOURCE"] = "Source"
L["YOUR_PROFESSIONS"] = "Warband Professions"
L["PROFESSIONS_EXPAND_ALL_TOOLTIP"] = "Expand Favorites, Characters, and Untracked sections."
L["PROFESSIONS_COLLAPSE_ALL_TOOLTIP"] = "Collapse Favorites, Characters, and Untracked sections."
L["PROFESSIONS_TRACKED_FORMAT"] = "%s characters with professions"
L["PROFESSIONS_WIDE_TABLE_HINT"] = "Tip: use the bar below or Shift+mouse wheel to see all columns."
L["NO_PROFESSIONS_DATA"] = "No profession data available yet. Open your profession window (default: K) on each character to collect data."
L["CONCENTRATION"] = "Concentration"
L["KNOWLEDGE"] = "Knowledge"
L["SKILL"] = "Skill"
L["RECIPES"] = "Recipes"
L["UNSPENT_POINTS"] = "Unspent Points"
L["UNSPENT_KNOWLEDGE_TOOLTIP"] = "Unspent knowledge points"
L["UNSPENT_KNOWLEDGE_COUNT"] = "%d unspent knowledge point(s)"
L["COLLECTIBLE"] = "Collectible"
L["RECHARGE"] = "Recharge"
L["FULL"] = "Full"
L["PROF_CONCENTRATION_FULL"] = "Full"
L["PROF_CONCENTRATION_HOURS_REMAINING"] = "%d Hours"
L["PROF_CONCENTRATION_MINUTES_REMAINING"] = "%d Min"
L["PROF_CONCENTRATION_DAYS_HOURS_MIN"] = "%d Days %d Hours %d Min"
L["PROF_CONCENTRATION_HOURS_MIN"] = "%d Hours %d Min"
L["PROF_CONCENTRATION_MINUTES_ONLY"] = "%d Min"
L["PROF_OPEN_RECIPE"] = "Open"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Open this profession's recipe list"
L["PROF_ONLY_CURRENT_CHAR"] = "Only available for the current character"
L["NO_PROFESSION"] = "No Profession"

-- Professions: Expansion filter (title card dropdown)
L["PROF_FILTER_ALL"] = "All"
L["PROF_FIRSTCRAFT_NO_DATA"] = "No profession data available."

-- Professions: Column Headers (label keys used by HEADER_DEFS)
L["FIRST_CRAFT"] = "First Craft"
L["UNIQUES"] = "Uniques"
L["TREATISE"] = "Treatise"
L["GATHERING"] = "Gathering"
L["CATCH_UP"] = "Catch Up"
L["MOXIE"] = "Moxie"
L["COOLDOWNS"] = "Cooldowns"
L["COLUMNS_BUTTON"] = "Columns"
L["HIDE_FILTER_BUTTON"] = "Hide"
L["HIDE_FILTER_LEVEL_80"] = "Level 80"
L["HIDE_FILTER_LEVEL_90"] = "Level 90"
L["HIDE_FILTER_STATE_OFF"] = "Off"
L["HIDE_FILTER_TOOLTIP_TOGGLE"] = "Toggle filters: Level 80 / Level 90"
L["HIDE_FILTER_TOOLTIP_CURRENT"] = "Current: %s"

-- Professions: Tooltips & Details

-- Professions: Crafting Orders

-- Professions: Equipment
L["EQUIPMENT"] = "Equipment"
L["TOOL"] = "Tool"
L["ACCESSORY"] = "Accessory"
L["PROF_EQUIPMENT_HINT"] = "Open profession (K) on this character to scan equipment."

-- Professions: Info Window
L["PROF_INFO_TOOLTIP"] = "View profession details"
L["PROF_INFO_NO_DATA"] = "No profession data available.\nPlease login on this character and open the Profession window (K) to collect data."
L["PROF_INFO_SKILLS"] = "Expansion Skills"
L["PROF_INFO_TOOL"] = "Tool"
L["PROF_INFO_ACC1"] = "Accessory 1"
L["PROF_INFO_ACC2"] = "Accessory 2"
L["PROF_INFO_KNOWN"] = "Known"
L["PROF_INFO_WEEKLY"] = "Weekly Knowledge Progress"
L["PROF_INFO_COOLDOWNS"] = "Cooldowns"
L["PROF_INFO_READY"] = "Ready"
L["PROF_INFO_LAST_UPDATE"] = "Last Updated"
L["PROF_INFO_LOCKED"] = "Locked"
L["PROF_INFO_UNLEARNED"] = "Unlearned"

-- Track Item DB
L["TRACK_ITEM_DB"] = "Track Item DB"
L["TRACK_ITEM_DB_DESC"] = "Manage which collectible drops to track. Toggle built-in entries or add custom sources."
L["MANAGE_ITEMS"] = "Item Tracking"
L["SELECT_ITEM"] = "Select Item"
L["SELECT_ITEM_DESC"] = "Choose a collectible to manage."
L["SELECT_ITEM_HINT"] = "Select an item above to view details."
L["REPEATABLE_LABEL"] = "Repeatable"
L["SOURCE_SINGULAR"] = "source"
L["SOURCE_PLURAL"] = "sources"
L["UNTRACKED"] = "Untracked"
L["CUSTOM_ENTRIES"] = "Custom Entries"
L["CURRENT_ENTRIES_LABEL"] = "Current:"
L["NO_CUSTOM_ENTRIES"] = "No custom entries."
L["ITEM_ID_INPUT"] = "Item ID"
L["ITEM_ID_INPUT_DESC"] = "Enter the item ID to track."
L["LOOKUP_ITEM"] = "Lookup"
L["LOOKUP_ITEM_DESC"] = "Resolve item name and type from ID."
L["ITEM_LOOKUP_FAILED"] = "Item not found."
L["SOURCE_TYPE"] = "Source Type"
L["SOURCE_TYPE_DESC"] = "NPC or Object."
L["SOURCE_TYPE_NPC"] = "NPC"
L["SOURCE_TYPE_OBJECT"] = "Object"
L["SOURCE_ID"] = "Source ID"
L["SOURCE_ID_DESC"] = "NPC ID or Object ID."
L["REPEATABLE_TOGGLE"] = "Repeatable"
L["REPEATABLE_TOGGLE_DESC"] = "Whether this drop can be attempted multiple times per lockout."
L["ADD_ENTRY"] = "+ Add Entry"
L["ADD_ENTRY_DESC"] = "Add this custom drop entry."
L["ENTRY_ADDED"] = "Custom entry added."
L["ENTRY_ADD_FAILED"] = "Item ID and Source ID are required."
L["REMOVE_ENTRY"] = "Remove Custom Entry"
L["REMOVE_ENTRY_DESC"] = "Select a custom entry to remove."
L["REMOVE_BUTTON"] = "- Remove Selected"
L["REMOVE_BUTTON_DESC"] = "Remove the selected custom entry."
L["ENTRY_REMOVED"] = "Entry removed."
L["SOURCE_NAME"] = "Source Name"
L["SOURCE_NAME_DESC"] = "Optional display name for the source (e.g. NPC or object name)."
L["STATISTIC_IDS"] = "Statistic IDs"
L["STATISTIC_IDS_DESC"] = "Comma-separated WoW Statistics IDs for kill/drop count (optional)."
L["MANAGE_BUILTIN"] = "Manage Built-in Entries"
L["MANAGE_BUILTIN_DESC"] = "Search and toggle built-in tracking entries by item ID."
L["SEARCH_BUILTIN"] = "Search Built-in by Item ID"
L["SEARCH_BUILTIN_DESC"] = "Enter item ID to find sources in the built-in database."
L["SEARCH_BUTTON"] = "Search"
L["CURRENTLY_UNTRACKED"] = "Currently Untracked"
L["ITEM_RESOLVED"] = "Item resolved: %s (%s)"

-- Plans / Collections (parse labels and UI)
L["ACHIEVEMENT"] = "Achievement"
L["CRITERIA"] = "Criteria"
L["CUSTOM_PLAN_COMPLETED"] = "Custom plan '%s' |cff00ff00completed|r"
L["DESCRIPTION"] = "Description"
L["PARSE_AMOUNT"] = "Amount"
L["PARSE_LOCATION"] = "Location"
L["SHOWING_X_OF_Y"] = "Showing %d of %d results"
L["SOURCE_UNKNOWN"] = "Unknown"
L["ZONE_DROP"] = "Zone drop"
L["FISHING"] = "Fishing"

-- Config (display names)
L["CONFIG_RECIPE_COMPANION"] = "Recipe Companion"
L["CONFIG_RECIPE_COMPANION_DESC"] = "Show the Recipe Companion window alongside the Professions UI, displaying reagent availability per character."

-- Try Counter
L["TRYCOUNTER_DIFFICULTY_SKIP"] = "Skipped: %s requires %s difficulty (current: %s)"
L["TRYCOUNTER_OBTAINED"] = "Obtained %s!"

-- Recipe Companion
L["RECIPE_COMPANION_TITLE"] = "Recipe Companion"
L["TOGGLE_TRACKER"] = "Toggle Tracker"
L["SELECT_RECIPE"] = "Select a recipe"
L["RECIPE_COMPANION_EMPTY"] = "Select a recipe to see reagent availability by character."
L["CRAFTERS_SECTION"] = "Crafters"
L["TOTAL_REAGENTS"] = "Total Reagents"

-- Database / Migration
L["DATABASE_UPDATED_MSG"] = "Database updated to a new version."
L["DATABASE_RELOAD_REQUIRED"] = "A one-time reload is required to apply changes."
L["MIGRATION_RESET_COMPLETE"] = "Reset complete. All data will be rescanned automatically."

-- Sync / Loading
L["SYNCING_COMPLETE"] = "Syncing complete!"
L["SYNCING_LABEL_FORMAT"] = "WN Syncing : %s"
L["SETTINGS_UI_UNAVAILABLE"] = "Settings UI not available. Try /wn to open the main window."

-- Character Tracking Dialog
L["TRACKED_LABEL"] = "Tracking"
L["TRACKED_DETAILED_LINE1"] = "Full detailed data"
L["TRACKED_DETAILED_LINE2"] = "All features enabled"
L["UNTRACKED_LABEL"] = "Not Tracking"
L["TRACKING_BADGE_TRACKING"] = "Tracking"
L["TRACKING_BADGE_UNTRACKED"] = "Not\nTracking"
L["TRACKING_BADGE_BANK"] = "Bank is\nActive"
L["UNTRACKED_VIEWONLY_LINE1"] = "View-only mode"
L["UNTRACKED_VIEWONLY_LINE2"] = "Basic info only"
L["TRACKING_ENABLED_CHAT"] = "Character tracking enabled. Data collection will begin."
L["TRACKING_DISABLED_CHAT"] = "Character tracking disabled. Running in read-only mode."
L["ADDED_TO_FAVORITES"] = "Added to favorites:"
L["REMOVED_FROM_FAVORITES"] = "Removed from favorites:"

-- Tooltip: Collectible Drop Lines
L["TOOLTIP_ATTEMPTS"] = "attempts"
L["TOOLTIP_100_DROP"] = "100% Drop"
L["TOOLTIP_UNKNOWN"] = "Unknown"
L["TOOLTIP_HOLD_SHIFT"] = "  Hold [Shift] for full list"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Concentration"
L["TOOLTIP_FULL"] = "(Full)"
L["TOOLTIP_NO_LOOT_UNTIL_RESET"] = "No loot until next reset"

-- SharedWidgets: UI Labels
L["NO_ITEMS_CACHED_TITLE"] = "No items cached"
L["DB_LABEL"] = "DB:"

-- DataService: Loading Stages & Alerts
L["COLLECTING_PVE"] = "Collecting PvE data"
L["PVE_PREPARING"] = "Preparing"
L["PVE_GREAT_VAULT"] = "Great Vault"
L["PVE_MYTHIC_SCORES"] = "Mythic+ Scores"
L["PVE_RAID_LOCKOUTS"] = "Raid Lockouts"
L["PVE_INCOMPLETE_DATA"] = "Some data may be incomplete. Try refreshing later."
L["VAULT_SLOTS_TO_FILL"] = "%d Great Vault slot%s to fill"
L["VAULT_SLOT_PLURAL"] = "s"
L["REP_RENOWN_NEXT"] = "Renown %d"
L["REP_TO_NEXT_FORMAT"] = "%s rep to %s (%s)"
L["REP_FACTION_FALLBACK"] = "Faction"
L["COLLECTION_CANCELLED"] = "Collection cancelled by user"
L["PERSONAL_BANK"] = "Personal Bank"
L["WARBAND_BANK_LABEL"] = "Warband Bank"
L["WARBAND_BANK_TAB_FORMAT"] = "Tab %d"
L["CURRENCY_OTHER"] = "Other"

-- DataService: Reputation Standings
L["STANDING_HATED"] = "Hated"
L["STANDING_HOSTILE"] = "Hostile"
L["STANDING_UNFRIENDLY"] = "Unfriendly"
L["STANDING_NEUTRAL"] = "Neutral"
L["STANDING_FRIENDLY"] = "Friendly"
L["STANDING_HONORED"] = "Honored"
L["STANDING_REVERED"] = "Revered"
L["STANDING_EXALTED"] = "Exalted"

-- Notification (popup) — "BAM" moment when farmed drop obtained
L["NOTIFICATION_FIRST_TRY"] = "You got it on your first try!"
L["NOTIFICATION_GOT_IT_AFTER"] = "You got it after %d attempts!"
L["NOTIFICATION_COLLECTIBLE_CHARACTER_LINE"] = "Character: %s"

-- TryCounterService: Messages
L["TRYCOUNTER_INCREMENT_CHAT"] = "%d attempts for %s"
-- TryCounterService: BuildObtainedChat (successful drop / reset) — do not reuse INCREMENT_CHAT wording.
L["TRYCOUNTER_CHAT_OBTAINED_FIRST_LINK"] = "You got %s on your first try!"
L["TRYCOUNTER_CHAT_OBTAINED_AFTER_LINK"] = "You got %s after %d attempts!"
L["TRYCOUNTER_CHAT_ATTEMPTS_FOR_LINK"] = "%d attempts for %s"
L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"] = "First attempt for %s"
L["TRYCOUNTER_CHAT_TAG_CONTAINER"] = "container"
L["TRYCOUNTER_CHAT_TAG_FISHING"] = "fishing"
L["TRYCOUNTER_CHAT_TAG_RESET"] = "counter reset"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d attempts for %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "Obtained %s! Try counter reset."
-- "What a grind" message shown when cumulative drop probability exceeded 70%.
-- Params: totalTries, cumulativePct (e.g. 87), itemLink
L["TRYCOUNTER_WHAT_A_GRIND"] = "What a grind! %d attempts (expected ~%d%% to have it by now) for %s"
L["TRYCOUNTER_CAUGHT_RESET"] = "Caught %s! Try counter reset."
L["TRYCOUNTER_CAUGHT"] = "Caught %s!"
L["TRYCOUNTER_CONTAINER_RESET"] = "Obtained %s from container! Try counter reset."
L["TRYCOUNTER_CONTAINER"] = "Obtained %s from container!"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Skipped: daily/weekly lockout active for this NPC."
L["TRYCOUNTER_INSTANCE_ENTRY_HINT"] = "This instance has mount(s) on the Try Counter for your difficulty. Type |cffffffff/wn check|r while targeting a boss (or mouseover) for details."
L["TRYCOUNTER_COLLECTED_TAG"] = "(Collected)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " attempts"
L["TRYCOUNTER_TRY_COUNTS"] = "Try Counts"
L["TRYCOUNTER_PROBE_ENTER"] = "Entered: %s — difficulty: %s"
L["TRYCOUNTER_PROBE_DB_HEADER"] = "Mount sources (Try Counter DB) — your difficulty: %s"
L["TRYCOUNTER_PROBE_MOUNT_LINE"] = "%s > %s > %s > %s"
L["TRYCOUNTER_PROBE_ENC_NO_MOUNTS"] = "%s: no mount entries in database"
L["TRYCOUNTER_PROBE_JOURNAL_MISS"] = "Could not resolve encounter journal for this instance."
L["TRYCOUNTER_PROBE_NO_MAPPED_BOSSES"] = "No bosses in this instance map to Try Counter data."
L["TRYCOUNTER_PROBE_STATUS_COLLECTED"] = "Already collected"
L["TRYCOUNTER_PROBE_STATUS_OBTAINABLE"] = "Obtainable on current difficulty"
L["TRYCOUNTER_PROBE_STATUS_WRONG_DIFF"] = "Not available on current difficulty"
L["TRYCOUNTER_PROBE_STATUS_DIFF_UNKNOWN"] = "Difficulty unknown"
L["TRYCOUNTER_PROBE_REQ_ANY"] = "any difficulty"
L["TRYCOUNTER_PROBE_REQ_MYTHIC"] = "Mythic only"
L["TRYCOUNTER_PROBE_REQ_LFR"] = "LFR only"
L["TRYCOUNTER_PROBE_REQ_NORMAL_PLUS"] = "Normal+ raid (not LFR)"
L["TRYCOUNTER_PROBE_REQ_HEROIC"] = "Heroic+ (includes Mythic & 25H)"
L["TRYCOUNTER_PROBE_REQ_25H"] = "25-player Heroic only"
L["TRYCOUNTER_PROBE_REQ_10N"] = "10-player Normal only"
L["TRYCOUNTER_PROBE_REQ_25N"] = "25-player Normal only"
L["TRYCOUNTER_PROBE_REQ_25MAN"] = "25-player Normal or Heroic"

-- Loading Tracker Labels
L["LT_CHARACTER_DATA"] = "Character Data"
L["LT_CURRENCY_CACHES"] = "Currency & Caches"
L["LT_REPUTATIONS"] = "Reputations"
L["LT_PROFESSIONS"] = "Professions"
L["LT_PVE_DATA"] = "PvE Data"
L["LT_COLLECTIONS"] = "Collections"
L["LT_COLLECTION_DATA"] = "Collection Data"

-- Collections tab (loading & filters)
L["LOADING_COLLECTIONS"] = "Loading collections..."
L["SYNC_COMPLETE"] = "Synced"
L["FILTER_COLLECTED"] = "Collected"
L["FILTER_UNCOLLECTED"] = "Uncollected"
L["FILTER_SHOW_OWNED"] = "Owned"
L["FILTER_SHOW_MISSING"] = "Missing"

-- Config: Settings Panel
L["CONFIG_HEADER"] = "Warband Nexus"
L["CONFIG_HEADER_DESC"] = "Modern Warband management and cross-character tracking."
L["CONFIG_GENERAL"] = "General Settings"
L["CONFIG_GENERAL_DESC"] = "Basic addon settings and behavior options."
L["CONFIG_ENABLE"] = "Enable Addon"
L["CONFIG_ENABLE_DESC"] = "Turn the addon on or off."
L["CONFIG_MINIMAP"] = "Minimap Button"
L["CONFIG_MINIMAP_DESC"] = "Show a button on the minimap for quick access."
L["CONFIG_SHOW_ITEMS_TOOLTIP"] = "Show Items in Tooltips"
L["CONFIG_SHOW_ITEMS_TOOLTIP_DESC"] = "Display Warband and Character item counts in item tooltips."
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN"] = "Request played time on login"
L["CONFIG_REQUEST_PLAYED_TIME_ON_LOGIN_DESC"] = "When enabled, the addon requests /played data in the background to update \"Most played\" and related stats. Chat output from that request is suppressed. When disabled, no automatic request is made on login (manual /played still works)."
L["CONFIG_MODULES"] = "Module Management"
L["CONFIG_MODULES_DESC"] = "Enable or disable individual addon modules. Disabled modules will not collect data or display UI tabs."
L["CONFIG_MOD_CURRENCIES"] = "Currencies"
L["CONFIG_MOD_CURRENCIES_DESC"] = "Track currencies across all characters."
L["CONFIG_MOD_REPUTATIONS"] = "Reputations"
L["CONFIG_MOD_REPUTATIONS_DESC"] = "Track reputations across all characters."
L["CONFIG_MOD_ITEMS"] = "Bank"
L["CONFIG_MOD_ITEMS_DESC"] = "Track items in bags and banks."
L["CONFIG_MOD_STORAGE"] = "Storage"
L["CONFIG_MOD_STORAGE_DESC"] = "Storage tab for inventory and bank management."
L["CONFIG_MOD_PVE"] = "PvE"
L["CONFIG_MOD_PVE_DESC"] = "Track Great Vault, Mythic+, and raid lockouts."
L["CONFIG_MOD_PLANS"] = "To-Do"
L["CONFIG_MOD_PLANS_DESC"] = "Weekly task tracking, collection goals, and vault progress."
L["CONFIG_MOD_PROFESSIONS"] = "Professions"
L["CONFIG_MOD_PROFESSIONS_DESC"] = "Track profession skills, recipes, and concentration."
L["CONFIG_AUTOMATION"] = "Automation"
L["CONFIG_AUTOMATION_DESC"] = "Control what happens automatically when you open your Warband Bank."
L["CONFIG_AUTO_OPTIMIZE"] = "Auto-Optimize Database"
L["CONFIG_AUTO_OPTIMIZE_DESC"] = "Automatically optimize the database on login to keep storage efficient."
L["CONFIG_SHOW_ITEM_COUNT"] = "Show Item Count"
L["CONFIG_SHOW_ITEM_COUNT_DESC"] = "Display item count tooltips showing how many of each item you have across all characters."
L["CONFIG_THEME_COLOR"] = "Master Theme Color"
L["CONFIG_THEME_COLOR_DESC"] = "Choose the primary accent color for the addon UI."
L["CONFIG_THEME_APPLIED"] = "%s theme applied!"
L["CONFIG_THEME_RESET_DESC"] = "Reset all theme colors to their default purple theme."
L["CONFIG_NOTIFICATIONS"] = "Notifications"
L["CONFIG_NOTIFICATIONS_DESC"] = "Configure which notifications appear."
L["CONFIG_ENABLE_NOTIFICATIONS"] = "Enable Notifications"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "Show popup notifications for collectible events."
L["CONFIG_SHOW_UPDATE_NOTES"] = "Show Update Notes Again"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "Display the What's New window on next login."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "Update notification will show on next login."
L["CONFIG_RESET_PLANS"] = "Reset Completed Plans"
L["CONFIG_RESET_PLANS_FORMAT"] = "Removed %d completed plan(s)."
L["CONFIG_TAB_FILTERING"] = "Tab Filtering"
L["CONFIG_TAB_FILTERING_DESC"] = "Choose which tabs are visible in the main window."
L["CONFIG_CHARACTER_MGMT"] = "Character Management"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Manage tracked characters and remove old data."
L["CONFIG_DELETE_CHAR"] = "Delete Character Data"
L["CONFIG_DELETE_CHAR_DESC"] = "Permanently remove all stored data for the selected character."
L["CONFIG_FONT_SCALING"] = "Font & Scaling"
L["CONFIG_FONT_SCALING_DESC"] = "Adjust font family and size scaling."
L["CONFIG_FONT_FAMILY"] = "Font Family"
L["CONFIG_ADVANCED"] = "Advanced"
L["CONFIG_ADVANCED_DESC"] = "Advanced settings and database management. Use with caution!"
L["CONFIG_DEBUG_MODE"] = "Debug Mode"
L["CONFIG_DEBUG_MODE_DESC"] = "Enable verbose logging for debugging purposes. Only enable if troubleshooting issues."
L["CONFIG_DEBUG_VERBOSE"] = "Debug Verbose (cache/scan/tooltip logs)"
L["CONFIG_DEBUG_VERBOSE_DESC"] = "When Debug Mode is on, also show currency/reputation cache, bag scan, tooltip and profession logs. Leave off to reduce chat spam."
L["CONFIG_DB_STATS"] = "Show Database Statistics"
L["CONFIG_DB_STATS_DESC"] = "Display current database size and optimization statistics."
L["CONFIG_OPTIMIZE_NOW"] = "Optimize Database Now"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Run the database optimizer to clean up and compress stored data."
L["CONFIG_COMMANDS_HEADER"] = "Slash Commands"

-- Sorting
L["SORT_BY_LABEL"] = "Sort By:"
L["SORT_MODE_DEFAULT"] = "Default Order"
L["SORT_MODE_MANUAL"] = "Manual (Custom Order)"
L["SORT_MODE_NAME"] = "Name (A-Z)"
L["SORT_MODE_LEVEL"] = "Level (Highest)"
L["SORT_MODE_ILVL"] = "Item Level (Highest)"
L["SORT_MODE_GOLD"] = "Gold (Highest)"

-- Gold Management
L["GOLD_MANAGER_BTN"] = "Gold Target"
L["GOLD_MANAGEMENT_TITLE"] = "Gold Target"
L["GOLD_MANAGEMENT_ENABLE"] = "Enable Gold Management"
L["GOLD_MANAGEMENT_MODE"] = "Management Mode"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "Deposit Only"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "If you have more than X gold, excess will be automatically deposited to warband bank."
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "Withdraw Only"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "If you have less than X gold, the difference will be automatically withdrawn from warband bank."
L["GOLD_MANAGEMENT_MODE_BOTH"] = "Both"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "Automatically maintain exactly X gold on your character (deposit if over, withdraw if under)."
L["GOLD_MANAGEMENT_TARGET"] = "Target Gold Amount"
L["GOLD_MANAGEMENT_HELPER"] = "Enter the amount of gold you want to keep on this character. The addon will automatically manage your gold when you open the bank."
L["GOLD_MANAGEMENT_CHAR_ONLY"] = "Only For This Character (%s)"
L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] = "Use separate gold management settings for this character only. Other characters will use the shared profile settings."
L["GOLD_MGMT_PROFILE_TITLE"] = "Profile (All Characters)"
L["GOLD_MGMT_USING_PROFILE"] = "Using profile"
L["GOLD_MGMT_MODE_SHORT_DEPOSIT"] = "Deposit"
L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] = "Withdraw"
L["GOLD_MGMT_MODE_SHORT_BOTH"] = "Both"
L["MONEY_LOGS_BTN"] = "Money Logs"
L["MONEY_LOGS_TITLE"] = "Money Logs"
L["MONEY_LOGS_SUMMARY_TITLE"] = "Character Contributions"
L["MONEY_LOGS_COLUMN_NET"] = "Net"
L["MONEY_LOGS_COLUMN_TIME"] = "Time"
L["MONEY_LOGS_COLUMN_CHARACTER"] = "Character"
L["MONEY_LOGS_COLUMN_TYPE"] = "Type"
L["MONEY_LOGS_COLUMN_TOFROM"] = "To / From"
L["MONEY_LOGS_COLUMN_AMOUNT"] = "Amount"
L["MONEY_LOGS_EMPTY"] = "No money transactions recorded yet."
L["MONEY_LOGS_DEPOSIT"] = "Deposit"
L["MONEY_LOGS_WITHDRAW"] = "Withdraw"
L["MONEY_LOGS_TO_WARBAND_BANK"] = "Warband Bank"
L["MONEY_LOGS_FROM_WARBAND_BANK"] = "From Warband Bank"
L["MONEY_LOGS_RESET"] = "Reset"
L["MONEY_LOGS_FILTER_ALL"] = "All"
L["MONEY_LOGS_CHAT_DEPOSIT"] = "|cff00ff00Money Log:|r Deposited %s to Warband Bank"
L["MONEY_LOGS_CHAT_WITHDRAW"] = "|cffff9900Money Log:|r Withdrew %s from Warband Bank"

-- Minimap Tooltip
L["MINIMAP_MORE_FORMAT"] = "... +%d more"

-- Gear UI
L["GEAR_UPGRADE_CURRENCIES"] = "Upgrade Currencies"
L["GEAR_DAWNCREST_PLAYBOOK_TITLE"] = "Dawncrest upgrade playbook"
L["GEAR_DAWNCREST_PLAYBOOK_SUMMARY"] = "Each upgrade step: %s Dawncrests + gold. Earn via delves, dungeons, Mythic+, and raids — hover header for tier sources."
L["GEAR_DAWNCREST_PLAYBOOK_TOOLTIP_LEAD"] = "Item upgrades spend %s Dawncrests per tier step (plus gold) at the upgrade vendor."
L["GEAR_DAWNCREST_PLAYBOOK_CAP_HINT"] = "Season and weekly caps apply — amounts are shown on each currency row (Shift: season progress)."
L["GEAR_DAWNCREST_PLAYBOOK_BY_TIER"] = "Sources by Dawncrest tier:"
L["GEAR_DAWNCREST_PLAYBOOK_NO_SOURCES"] = "Earn via seasonal PvE rewards matching this crest tier."

-- Gear tab currency footer + equipped-item Dawncrest tooltip (see GearService:GetGearItemUpgradeTooltipAppend)
L["GEAR_CURRENCY_PANEL_HOVER_HINT"] = "Hover equipped items for crest costs and sources."
L["GEAR_TT_DAWNCREST_WORD"] = "Dawncrest"
L["GEAR_TT_SECTION_DAWNCREST"] = "Dawncrest"
L["GEAR_TT_SECTION_SOURCES"] = "Sources"
L["GEAR_TT_TRACK_RANK_FORMAT"] = "%s %d/%d"
L["GEAR_TT_NEXT_STEP_CRESTS"] = "Next step: %d %s."
L["GEAR_TT_NEXT_STEP_GOLD_ONLY"] = "Next step: gold only (you already reached this item level on this slot)."
L["GEAR_TT_REMAINING_TRACK_CRESTS"] = "Remaining crest steps on track: %d (%d %s total)."
L["GEAR_TT_CRAFTED_NEXT_RECAST"] = "Next recraft target: %s (item level %d), %d %s."
L["GEAR_TT_UPGRADE_FALLBACK_LEAD"] = "Upgrades use Dawncrest (amounts on the currency panel). Examples by tier:"
L["GEAR_CHARACTER_STATS"] = "Character Stats"
L["GEAR_SECTION_CHARACTER"] = "Character"
L["GEAR_NO_ITEM_EQUIPPED"] = "No item equipped in this slot."
L["GEAR_NO_PREVIEW"] = "No Preview"
L["GEAR_OFFLINE_BADGE"] = "Offline"
L["GEAR_NO_PREVIEW_HINT"] = "Log in on this character to refresh the appearance preview."
L["GEAR_STATS_CURRENT_ONLY"] = "Stats available for\ncurrent character only"
L["GEAR_SLOT_RING1"] = "Ring 1"
L["GEAR_SLOT_RING2"] = "Ring 2"
L["GEAR_SLOT_TRINKET1"] = "Trinket 1"
L["GEAR_SLOT_TRINKET2"] = "Trinket 2"
    L["GEAR_MISSING_ENCHANT"] = "Missing Enchant"
    L["GEAR_MISSING_GEM"] = "Missing Gem"
L["GEAR_UPGRADE_AVAILABLE_FORMAT"] = "Available upgrade to %s %d/%d%s"
L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"] = "%d upgrade(s) with current currency"
L["GEAR_CRESTS_GOLD_ONLY"] = "Crests needed: 0 (gold only — previously reached)"
L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"] = "%d upgrade(s) gold only (previously reached)"
L["GEAR_NEED_MORE_CRESTS_FORMAT"] = "%s %d/%d — need more crests"
L["GEAR_CRAFTED_NO_CRESTS"] = "No crests available for recraft"
L["GEAR_TRACK_CRAFTED_FALLBACK"] = "Crafted"
L["GEAR_CRAFTED_MAX_ILVL_LINE"] = "%s (max ilvl %d)"
L["GEAR_CRAFTED_RECAST_TO_LINE"] = "Recraft to %s (ilvl %d)"
L["GEAR_CRAFTED_COST_DAWNCREST"] = "Cost: %d %s Dawncrest"
L["GEAR_CRAFTED_NEXT_TIER_CRESTS"] = "%s (ilvl %d): %d/%d crests (%d more needed)"

-- Characters UI
L["WOW_TOKEN_LABEL"] = "WoW Token"
L["WOW_TOKEN_COUNT_LABEL"] = "Tokens"
L["NOT_AVAILABLE_SHORT"] = "N/A"

-- SharedWidgets
L["FILTER_LABEL"] = FILTER or "Filter"

-- Statistics UI
L["FORMAT_BUTTON"] = "Format"
L["STATS_PLAYED_STEAM_ZERO"] = "0 Hours"
L["STATS_PLAYED_STEAM_FLOAT"] = "%.1f Hours"
L["STATS_PLAYED_STEAM_THOUSAND"] = "%d,%03d Hours"
L["STATS_PLAYED_STEAM_INT"] = "%d Hours"

-- Professions UI
L["SHOW_ALL"] = "Show All"

-- Social
L["DISCORD_TOOLTIP"] = "Warband Nexus Discord"
L["PATREON_TOOLTIP"] = "Warband Nexus on Patreon"
L["MAIN_FOOTER_LEFT"] = "Crafted with care, for everyone who plays."
L["MAIN_FOOTER_VERSION_FMT"] = "v%s"

-- Collection Source Filters
L["SOURCE_OTHER"] = "Other"

-- Expansion / Content Names
L["CONTENT_KHAZ_ALGAR"] = "Khaz Algar"
L["CONTENT_DRAGON_ISLES"] = "Dragon Isles"

-- Module Disabled
L["MODULE_DISABLED_DESC_FORMAT"] = "Enable it in %s to use %s."

-- Plans UI (extended)
L["PART_OF_FORMAT"] = "Part of: %s"
L["LOCKED_WORLD_QUESTS"] = "Locked — complete World Quests to unlock"
L["QUEST_ID_FORMAT"] = "Quest ID: %s"

-- Blizzard GlobalStrings (Auto-localized by WoW)
L["BANK_LABEL"] = BANK or "Bank"
L["BTN_SETTINGS"] = SETTINGS
L["CANCEL"] = CANCEL or "Cancel"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Achievements"
L["ACHIEVEMENT_SERIES"] = "Achievement Series"
L["LOADING_ACHIEVEMENTS"] = "Loading achievements..."
L["CATEGORY_ALL"] = ALL or "All Items"
L["CATEGORY_MOUNTS"] = MOUNTS or "Mounts"
L["CATEGORY_PETS"] = PETS or "Pets"
L["CATEGORY_TITLES"] = TITLES or "Titles"
L["CATEGORY_TOYS"] = TOY_BOX or "Toys"
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["DELETE"] = DELETE or "Delete"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic"
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Unknown"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["HEADER_CHARACTERS"] = CHARACTER or "Characters"
L["HEADER_FAVORITES"] = FAVORITES or "Favorites"
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Guild Bank"
L["ITEMS_PLAYER_BANK"] = BANK or "Player Bank"
L["NONE_LABEL"] = NONE or "None"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notifications"
L["OK_BUTTON"] = OKAY or "OK"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Drop"
L["PARSE_DUNGEON"] = DUNGEONS or "Dungeon"
L["PARSE_FACTION"] = FACTION or "Faction"
L["PARSE_RAID"] = RAID or "Raid"
L["PARSE_REPUTATION"] = REPUTATION or "Reputation"
L["PARSE_ZONE"] = ZONE or "Zone"
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Dungeons"
L["PVE_HEADER_RAIDS"] = RAIDS or "Raids"
L["PVP_TYPE"] = PVP or "PvP"
L["RAIDS_LABEL"] = RAIDS or "Raids"
L["RAID_CAT"] = RAID or "Raid"
L["RELOAD_UI_BUTTON"] = RELOADUI or "Reload UI"
L["RESET_LABEL"] = RESET or "Reset"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["SLOT_BACK"] = INVTYPE_CLOAK or "Back"
L["SLOT_CHEST"] = INVTYPE_CHEST or "Chest"
L["SLOT_FEET"] = INVTYPE_FEET or "Feet"
L["SLOT_HANDS"] = INVTYPE_HAND or "Hands"
L["SLOT_HEAD"] = INVTYPE_HEAD or "Head"
L["SLOT_LEGS"] = INVTYPE_LEGS or "Legs"
L["SLOT_MAINHAND"] = INVTYPE_WEAPONMAINHAND or "Main Hand"
L["SLOT_OFFHAND"] = INVTYPE_WEAPONOFFHAND or "Off Hand"
L["SLOT_SHIRT"] = INVTYPE_BODY or "Shirt"
L["SLOT_SHOULDER"] = INVTYPE_SHOULDER or "Shoulder"
L["SLOT_TABARD"] = INVTYPE_TABARD or "Tabard"
L["SLOT_WAIST"] = INVTYPE_WAIST or "Waist"
L["SLOT_WRIST"] = INVTYPE_WRIST or "Wrist"
L["PROFESSION_SUMMARY_SLOT_ACCESSORY"] = "Accessory"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Achievement"
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Drop"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "In-Game Shop"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Pet Battle"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promotion"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Quest"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Trading Card Game"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Unknown"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Vendor"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "World Event"
L["COLLECTION_RULE_API_NOT_AVAILABLE"] = "API not available"
L["COLLECTION_RULE_INVALID_MOUNT"] = "Invalid mount"
L["COLLECTION_RULE_FACTION_CLASS_RESTRICTED"] = "Faction or class restricted"
L["TAB_CHARACTERS"] = CHARACTER or "Characters"
L["TAB_CURRENCY"] = CURRENCY or "Currency"
L["TAB_ITEMS"] = "Bank"
L["TAB_GEAR"] = "Gear"
L["TAB_REPUTATION"] = REPUTATION or "Reputation"
L["TAB_STATISTICS"] = STATISTICS or "Statistics"

L["GEAR_TAB_TITLE"] = "Gear Management"
L["GEAR_TAB_DESC"] = "Equipped gear, upgrade options, and cross-character upgrade candidates"
L["GEAR_STORAGE_WARBOUND"] = "Warbound"
L["GEAR_STORAGE_BOE"] = "BoE"
L["GEAR_STORAGE_WARBOUND_UNTIL_EQUIPPED"] = "Warbound until equipped"
L["GEAR_STORAGE_TITLE"] = "Storage Upgrade Recommendations"
L["GEAR_STORAGE_SUBTITLE"] = "Transferable items only (BoE / Warbound)"
L["GEAR_STORAGE_EMPTY"] = "No better BoE / Warbound / Warbound-until-equipped upgrades found for this character."
L["GEAR_STORAGE_EMPTY_NO_BOE_WOE"] = "Can't find any BoE or WoE to upgrade on item slots."
L["GEAR_SLOT_FALLBACK_FORMAT"] = "Slot %d"
L["GEAR_ITEM_UPGRADE_RECOMMENDATIONS_TITLE"] = "Item Upgrade Recommendations"
L["ILVL_SHORT_LABEL"] = "iLvl"
L["TYPE_MOUNT"] = MOUNT or "Mount"
L["TYPE_PET"] = PET or "Pet"
L["TYPE_TOY"] = TOY or "Toy"
L["TYPE_ITEM"] = ITEM or "Item"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["STAT_STRENGTH"] = SPELL_STAT1_NAME or "Strength"
L["STAT_AGILITY"] = SPELL_STAT2_NAME or "Agility"
L["STAT_STAMINA"] = SPELL_STAT3_NAME or "Stamina"
L["STAT_INTELLECT"] = SPELL_STAT4_NAME or "Intellect"
L["STAT_CRITICAL_STRIKE"] = STAT_CRITICAL_STRIKE or "Critical Strike"
L["STAT_HASTE"] = STAT_HASTE or "Haste"
L["STAT_MASTERY"] = STAT_MASTERY or "Mastery"
L["STAT_VERSATILITY"] = STAT_VERSATILITY or "Versatility"
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon"
L["VAULT_SLOT_DUNGEON"] = DUNGEONS or "Dungeons"
L["VAULT_SLOT_RAIDS"] = RAIDS or "Raids"
L["VAULT_SLOT_SA"] = "Assignments"
L["TRACK_ACTIVITIES"] = "Track Activities"
L["VERSION"] = GAME_VERSION_LABEL or "Version"
L["FIRSTCRAFT"] = PROFESSIONS_FIRST_CRAFT or "First Craft"
L["WOWHEAD_LABEL"] = "Wowhead"
L["CTRL_C_LABEL"] = "Ctrl+C"
L["CLICK_TO_COPY_LINK"] = "Click to copy link"
L["PLAN_CHAT_LINK_TITLE"] = "Chat link"
L["PLAN_CHAT_LINK_HINT"] = "Click to insert into chat"
L["PLAN_CHAT_LINK_UNAVAILABLE"] = "Chat link is not available for this entry."
L["CLICK_FOR_WOWHEAD_LINK"] = "Click for Wowhead link"
L["PLAN_ACTION_COMPLETE"] = "Complete the Plan"
L["PLAN_ACTION_DELETE"] = "Delete the Plan"
L["OBJECTIVE_INDEX_FORMAT"] = "Objective %d"
L["QUEST_PROGRESS_FORMAT"] = "Progress: %d/%d (%d%%)"
L["QUEST_TIME_REMAINING_FORMAT"] = "%s remaining"
L["EVENT_GROUP_SOIREE"] = "Saltheril's Soiree"
L["EVENT_GROUP_ABUNDANCE"] = "Abundance"
L["EVENT_GROUP_HARANIR"] = "Legends of the Haranir"
L["EVENT_GROUP_STORMARION"] = "Stormarion Assault"
L["QUEST_CATEGORY_DESC_WEEKLY"] = "Weekly objectives, hunts, sparks, world boss, delves"
L["QUEST_CATEGORY_DESC_WORLD"] = "Zone-wide repeatable world quests"
L["QUEST_CATEGORY_DESC_DAILY"] = "Daily repeatable quests from NPCs"
L["QUEST_CATEGORY_DESC_EVENTS"] = "Bonus objectives, tasks, and activities"
L["GEAR_NO_TRACKED_CHARACTERS_TITLE"] = "No tracked characters"
L["GEAR_NO_TRACKED_CHARACTERS_DESC"] = "Log in to a character to start tracking gear."
L["SOURCE_TYPE_CATEGORY_FORMAT"] = "Category %d"

-- Keybinding globals (must be global for WoW's keybinding UI)
BINDING_HEADER_WARBANDNEXUS = "Warband Nexus"
BINDING_NAME_WARBANDNEXUS_TOGGLE = "Show/hide main window"
