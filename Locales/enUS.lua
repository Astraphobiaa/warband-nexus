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
L["ADDON_LOADED"] = "Warband Nexus loaded. Type /wn or /warbandnexus for options."

-- Slash Commands
L["SLASH_HELP"] = "Available commands:"
L["SLASH_OPTIONS"] = "Open options panel"
L["SLASH_SCAN"] = "Scan Warband bank"
L["SLASH_SHOW"] = "Show/hide main window"
L["SLASH_DEPOSIT"] = "Open deposit queue"
L["SLASH_SEARCH"] = "Search for an item"
L["KEYBINDING"] = "Keybinding"
L["KEYBINDING_UNBOUND"] = "Not set"
L["KEYBINDING_PRESS_KEY"] = "Press a key..."
L["KEYBINDING_TOOLTIP"] = "Click to set a keybinding for toggling Warband Nexus.\nPress ESC to cancel."
L["KEYBINDING_CLEAR"] = "Clear keybinding"
L["KEYBINDING_REPLACES"] = "That key was bound to %s — it is now used for Warband Nexus."
L["KEYBINDING_SAVED"] = "Keybinding saved."
L["KEYBINDING_COMBAT"] = "Cannot change keybindings in combat."
L["KEYBINDING_SETFAILED"] = "Could not assign that key. Try Esc > Options > Keybindings."
L["KEYBINDING_VERIFY_FAIL"] = "The key is still bound to another action (%s). Open Esc > Options > Keybindings, clear that binding, then assign again here."

-- Options Panel - General
L["GENERAL_SETTINGS"] = "General Settings"
L["GENERAL_SETTINGS_DESC"] = "Configure general addon behavior"
L["ENABLE_ADDON"] = "Enable Addon"
L["ENABLE_ADDON_DESC"] = "Enable or disable Warband Nexus functionality"
L["MINIMAP_ICON"] = "Show Minimap Icon"
L["MINIMAP_ICON_DESC"] = "Show or hide the minimap button"
L["DEBUG_MODE"] = "Debug Logging"
L["DEBUG_MODE_DESC"] = "Output verbose debug messages to chat for troubleshooting"
L["DEBUG_TRYCOUNTER_LOOT"] = "Try Counter Loot Debug"
L["DEBUG_TRYCOUNTER_LOOT_DESC"] = "Log loot flow (numLoot, source, route, outcome). Use when try count is not counted (fast auto-loot, dumpster/object, fishing). Rep/currency cache logs suppressed."

-- Options Panel - Scanning
L["SCANNING_SETTINGS"] = "Scanning Settings"
L["SCANNING_SETTINGS_DESC"] = "Configure bank scanning behavior"
L["AUTO_SCAN"] = "Auto-Scan on Bank Open"
L["AUTO_SCAN_DESC"] = "Automatically scan Warband bank when opened"
L["SCAN_DELAY"] = "Scan Throttle Delay"
L["SCAN_DELAY_DESC"] = "Delay between scan operations (in seconds)"

-- Options Panel - Deposit
L["DEPOSIT_SETTINGS"] = "Deposit Settings"
L["DEPOSIT_SETTINGS_DESC"] = "Configure item deposit behavior"
L["GOLD_RESERVE"] = "Gold Reserve"
L["GOLD_RESERVE_DESC"] = "Minimum gold to keep in personal inventory (in gold)"
L["AUTO_DEPOSIT_REAGENTS"] = "Auto-Deposit Reagents"
L["AUTO_DEPOSIT_REAGENTS_DESC"] = "Queue reagents for deposit when bank is opened"

-- Options Panel - Display
L["DISPLAY_SETTINGS"] = "Display Settings"
L["DISPLAY_SETTINGS_DESC"] = "Configure visual appearance"
L["SHOW_ITEM_LEVEL"] = "Show Item Level"
L["SHOW_ITEM_LEVEL_DESC"] = "Display item level on equipment"
L["SHOW_ITEM_COUNT"] = "Show Item Count"
L["SHOW_ITEM_COUNT_DESC"] = "Display stack counts on items"
L["HIGHLIGHT_QUALITY"] = "Highlight by Quality"
L["HIGHLIGHT_QUALITY_DESC"] = "Add colored borders based on item quality"

-- Options Panel - Tabs
L["TAB_SETTINGS"] = "Tab Settings"
L["TAB_SETTINGS_DESC"] = "Configure Warband bank tab behavior"
L["IGNORED_TABS"] = "Ignored Tabs"
L["IGNORED_TABS_DESC"] = "Select tabs to exclude from scanning and operations"
L["TAB_1"] = "Warband Tab 1"
L["TAB_2"] = "Warband Tab 2"
L["TAB_3"] = "Warband Tab 3"
L["TAB_4"] = "Warband Tab 4"
L["TAB_5"] = "Warband Tab 5"

-- Scanner Module
L["SCAN_STARTED"] = "Scanning Warband bank..."
L["SCAN_COMPLETE"] = "Scan complete. Found %d items in %d slots."
L["SCAN_FAILED"] = "Scan failed: Warband bank is not open."
L["SCAN_TAB"] = "Scanning tab %d..."
L["CACHE_CLEARED"] = "Item cache cleared."
L["CACHE_UPDATED"] = "Item cache updated."

-- Banker Module
L["BANK_NOT_OPEN"] = "Warband bank is not open."
L["DEPOSIT_STARTED"] = "Starting deposit operation..."
L["DEPOSIT_COMPLETE"] = "Deposit complete. Transferred %d items."
L["DEPOSIT_CANCELLED"] = "Deposit cancelled."
L["DEPOSIT_QUEUE_EMPTY"] = "Deposit queue is empty."
L["DEPOSIT_QUEUE_CLEARED"] = "Deposit queue cleared."
L["ITEM_QUEUED"] = "%s queued for deposit."
L["ITEM_REMOVED"] = "%s removed from queue."
L["GOLD_DEPOSITED"] = "%s gold deposited to Warband bank."
L["INSUFFICIENT_GOLD"] = "Insufficient gold for deposit."

-- Warband Bank Operations
L["INVALID_AMOUNT"] = "Invalid amount."
L["WITHDRAW_BANK_NOT_OPEN"] = "Bank must be open to withdraw!"
L["WITHDRAW_IN_COMBAT"] = "Cannot withdraw during combat."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "Not enough gold in Warband bank."
L["WITHDRAWN_LABEL"] = "Withdrawn:"
L["WITHDRAW_API_UNAVAILABLE"] = "Withdraw API not available."
L["SORT_IN_COMBAT"] = "Cannot sort while in combat."

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_CATEGORY_FORMAT"] = "Search %s..."
L["BTN_SCAN"] = "Scan Bank"
L["BTN_DEPOSIT"] = "Deposit Queue"
L["BTN_SORT"] = "Sort Bank"
L["BTN_CLEAR_QUEUE"] = "Clear Queue"
L["BTN_DEPOSIT_ALL"] = "Deposit All"
L["BTN_DEPOSIT_GOLD"] = "Deposit Gold"
L["ENABLE_MODULE"] = "Enable Module"

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
L["HEADER_REALM_GOLD"] = "Realm Gold"
L["HEADER_REALM_TOTAL"] = "Realm Total"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Last seen: %s"
L["CHARACTER_GOLD_FORMAT"] = "Gold: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Combined gold from all characters on this realm"

L["MAX_LEVEL"] = "Max level"
L["YES"] = YES or "Yes"
L["NO"] = NO or "No"

-- Items Tab
L["ITEMS_HEADER"] = "Bank Items"
L["ITEMS_HEADER_DESC"] = "Browse and manage your Warband and Personal bank"
L["ITEMS_WARBAND_BANK"] = "Warband Bank"
L["GROUP_CONTAINER"] = "Containers"

-- Storage Tab
L["STORAGE_HEADER"] = "Storage Browser"
L["STORAGE_HEADER_DESC"] = "Browse all items organized by type"
L["STORAGE_WARBAND_BANK"] = "Warband Bank"
L["STORAGE_PERSONAL_BANKS"] = "Personal Banks"
L["STORAGE_TOTAL_SLOTS"] = "Total Slots"
L["STORAGE_FREE_SLOTS"] = "Free Slots"
L["STORAGE_BAG_HEADER"] = "Warband Bags"
L["STORAGE_PERSONAL_HEADER"] = "Personal Bank"

-- Plans Tab
L["PLANS_MY_PLANS"] = "To-Do List"
L["PLANS_COLLECTIONS"] = "To-Do List"
L["PLANS_ADD_CUSTOM"] = "Add Custom Plan"
L["PLANS_NO_RESULTS"] = "No results found."
L["PLANS_ALL_COLLECTED"] = "All items collected!"
L["PLANS_RECIPE_HELP"] = "Right-click recipes in your inventory to add them here."
L["COLLECTION_PLANS"] = "To-Do List"
L["SEARCH_PLANS"] = "Search plans..."
L["COMPLETED_PLANS"] = "Completed Plans"
L["SHOW_COMPLETED"] = "Show Completed"
L["SHOW_COMPLETED_HELP"] = "To-Do List and Weekly Progress: unchecked shows plans still in progress; checked shows completed plans only. Browse tabs (Mounts, Pets, etc.): unchecked browses uncollected items (only those on your To-Do if Show Planned is on); checked adds collected entries that are on your To-Do (Show Planned still limits to list items when on)."
L["SHOW_PLANNED"] = "Show Planned"
L["SHOW_PLANNED_HELP"] = "Browse tabs only (hidden on To-Do List and Weekly Progress): when checked, only items you put on your To-Do for that category. With Show Completed off, planned items you still need; with Show Completed on, planned items you already finished; both on: all planned items in that category; both off: full uncollected browse."
L["NO_PLANNED_ITEMS"] = "No planned %ss yet"
L["PLANS_ACHIEVEMENTS_EMPTY_TITLE"] = "No achievements to display"
L["PLANS_ACHIEVEMENTS_EMPTY_HINT"] = "Add achievements from this list to your To-Do, or change Show Planned / Show Completed. The list fills as achievements are scanned; try /reload if nothing appears."
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
L["REP_HEADER_WARBAND"] = "Warband Reputation"
L["REP_HEADER_CHARACTER"] = "Character Reputation"
L["REP_STANDING_FORMAT"] = "Standing: %s"

-- Currency Tab
L["CURRENCY_HEADER_WARBAND"] = "Warband Transferable"
L["CURRENCY_HEADER_CHARACTER"] = "Character Bound"

-- PvE Tab
L["PVE_HEADER_DELVES"] = "Delves"
L["PVE_HEADER_WORLD_BOSS"] = "World Bosses"

-- Statistics
L["STATS_TOTAL_ITEMS"] = "Total Items"
L["STATS_TOTAL_SLOTS"] = "Total Slots"
L["STATS_FREE_SLOTS"] = "Free Slots"
L["STATS_USED_SLOTS"] = "Used Slots"
L["STATS_TOTAL_VALUE"] = "Total Value"
L["COLLECTED"] = "Collected"
L["TOTAL"] = TOTAL or "Total"

-- Tooltips
L["TOOLTIP_WARBAND_BANK"] = "Warband Bank"
L["TOOLTIP_TAB"] = "Tab"
L["TOOLTIP_SLOT"] = "Slot"
L["TOOLTIP_COUNT"] = "Count"
L["CHARACTER_INVENTORY"] = "Inventory"
L["CHARACTER_BANK"] = "Bank"

-- Try Counter
L["TRY_COUNT"] = "Try Count"
L["SET_TRY_COUNT"] = "Set Try Count"
L["TRY_COUNT_RIGHT_CLICK_HINT"] = "Right-click to edit attempt count."
L["TRY_COUNT_CLICK_HINT"] = "Click to edit attempt count."
L["TRIES"] = "Tries"

-- Reset Cycle
L["SET_RESET_CYCLE"] = "Set Reset Cycle"
L["DAILY_RESET"] = "Daily Reset"
L["WEEKLY_RESET"] = "Weekly Reset"
L["NONE_DISABLE"] = "None (Disable)"
L["RESET_CYCLE_LABEL"] = "Reset Cycle:"
L["RESET_NONE"] = "None"
L["DOUBLECLICK_RESET"] = "Double-click to reset position"

-- Error Messages
L["ERROR_GENERIC"] = "An error occurred."
L["ERROR_API_UNAVAILABLE"] = "Required API is not available."
L["ERROR_BANK_CLOSED"] = "Cannot perform operation: bank is closed."
L["ERROR_INVALID_ITEM"] = "Invalid item specified."
L["ERROR_PROTECTED_FUNCTION"] = "Cannot call protected function in combat."

-- Confirmation Dialogs
L["CONFIRM_DEPOSIT"] = "Deposit %d items to Warband bank?"
L["CONFIRM_CLEAR_QUEUE"] = "Clear all items from deposit queue?"
L["CONFIRM_DEPOSIT_GOLD"] = "Deposit %s gold to Warband bank?"

-- Update Notification
L["WHATS_NEW"] = "What's New"
L["GOT_IT"] = "Got it!"

-- Statistics Tab
L["ACHIEVEMENT_POINTS"] = "Achievement Points"
L["MOUNTS_COLLECTED"] = "Mounts Collected"
L["BATTLE_PETS"] = "Battle Pets"
L["TOTAL_PETS"] = "Total Pets"
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
L["RIGHT_CLICK_REMOVE"] = "Right-click to remove"
L["CLICK_TO_DISMISS"] = "Click to dismiss"
L["TRACKED"] = "Tracked"
L["TRACK"] = "Track"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Track in Blizzard objectives (max 10)"
L["UNKNOWN"] = UNKNOWN or "Unknown"
L["NO_REQUIREMENTS"] = "No requirements (instant completion)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "No planned activity"
L["NO_ACTIVE_CONTENT"] = "No active content this week"
L["CLICK_TO_ADD_GOALS"] = "Click on Mounts, Pets, or Toys above to browse and add goals!"
L["UNKNOWN_QUEST"] = "Unknown Quest"
L["ALL_QUESTS_COMPLETE"] = "All quests complete!"
L["CURRENT_PROGRESS"] = "Current Progress"
L["SELECT_CONTENT"] = "Select Content:"
L["QUEST_TYPES"] = "Quest Types:"
L["WORK_IN_PROGRESS"] = "Work in Progress"
L["RECIPE_BROWSER"] = "Recipe Browser"
L["NO_RESULTS_FOUND"] = "No results found."
L["TRY_ADJUSTING_SEARCH"] = "Try adjusting your search or filters."
L["NO_COLLECTED_YET"] = "No collected %ss yet"
L["START_COLLECTING"] = "Start collecting to see them here!"
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
L["CHARACTERS_TRACKED_FORMAT"] = "%d characters tracked"
L["NO_CHARACTER_DATA"] = "No character data available"
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
L["SKILL_LABEL"] = "Skill:"
L["OVERALL_SKILL"] = "Overall Skill:"
L["BONUS_SKILL"] = "Bonus Skill:"
L["KNOWLEDGE_LABEL"] = "Knowledge:"
L["SPEC_LABEL"] = "Spec"
L["POINTS_SHORT"] = " pts"
L["RECIPES_KNOWN"] = "Recipes Known:"
L["OPEN_PROFESSION_HINT"] = "Open profession window"
L["FOR_DETAILED_INFO"] = "for detailed information"
L["CHARACTER_IS_TRACKED"] = "This character is being tracked."
L["TRACKING_ACTIVE_DESC"] = "Data collection and updates are active."
L["CLICK_DISABLE_TRACKING"] = "Click to disable tracking."
L["MUST_LOGIN_TO_CHANGE"] = "You must log in to this character to change tracking."
L["TRACKING_ENABLED"] = "Tracking Enabled"
L["CLICK_ENABLE_TRACKING"] = "Click to enable tracking for this character."
L["TRACKING_WILL_BEGIN"] = "Data collection will begin immediately."
L["CHARACTER_NOT_TRACKED"] = "This character is not being tracked."
L["MUST_LOGIN_TO_ENABLE"] = "You must log in to this character to enable tracking."
L["ENABLE_TRACKING"] = "Enable Tracking"
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

-- Items Tab
L["PERSONAL_ITEMS"] = "Personal Items"
L["ITEMS_SUBTITLE"] = "Browse your Warband Bank, Guild Bank, and Personal Items"
L["ITEMS_DISABLED_TITLE"] = "Warband Bank Items"
L["ITEMS_LOADING"] = "Loading Inventory Data"
L["GUILD_BANK_REQUIRED"] = "You must be in a guild to access Guild Bank."
L["GUILD_JOINED_FORMAT"] = "Guild updated: %s"
L["GUILD_LEFT"] = "You are no longer in a guild. Guild Bank tab disabled."
L["NO_PERMISSION"] = "No permission"
L["NOT_IN_GUILD"] = "Not in guild"
L["ITEMS_SEARCH"] = "Search items..."
L["NEVER"] = "Never"
L["ITEM_FALLBACK_FORMAT"] = "Item %s"
L["ITEM_LOADING_NAME"] = "Loading..."
L["TAB_FORMAT"] = "Tab %d"
L["BAG_FORMAT"] = "Bag %d"
L["BANK_BAG_FORMAT"] = "Bank Bag %d"
L["ITEM_ID_LABEL"] = "Item ID:"
L["QUALITY_TOOLTIP_LABEL"] = "Quality:"
L["STACK_LABEL"] = "Stack:"
L["RIGHT_CLICK_MOVE"] = "Move to bag"
L["SHIFT_RIGHT_CLICK_SPLIT"] = "Split stack"
L["LEFT_CLICK_PICKUP"] = "Pick up"
L["ITEMS_BANK_NOT_OPEN"] = "Bank not open"
L["SHIFT_LEFT_CLICK_LINK"] = "Link in chat"
L["ITEM_DEFAULT_TOOLTIP"] = "Item"
L["ITEMS_STATS_ITEMS"] = "%s items"
L["ITEMS_STATS_SLOTS"] = "%s/%s slots"
L["ITEMS_STATS_LAST"] = "Last: %s"

-- Storage Tab
L["STORAGE_DISABLED_TITLE"] = "Character Storage"
L["STORAGE_SEARCH"] = "Search storage..."

-- PvE Tab
L["PVE_TITLE"] = "PvE Progress"
L["PVE_SUBTITLE"] = "Great Vault, Raid Lockouts & Mythic+ across your Warband"
L["PVE_COL_EARNED"] = "Earned"
L["PVE_COL_OWNED"] = "Owned"
L["PVE_COL_STASHES"] = "Stashes"
L["PVE_COL_OWNED_VAULT"] = "Owned"
L["PVE_COL_LOOTED"] = "Looted"
L["PVE_COL_CREST"] = "Crest"
L["PVE_CREST_ADV"] = "Adventurer"
L["PVE_CREST_VET"] = "Veteran"
L["PVE_CREST_CHAMP"] = "Champion"
L["PVE_CREST_HERO"] = "Hero"
L["PVE_CREST_MYTH"] = "Myth"
L["PVE_COL_COFFER_SHARDS"] = "Coffer Shards"
L["PVE_COL_RESTORED_KEY"] = "Restored Key"
L["PVE_COL_VAULT_SLOT1"] = "Vault Slot 1"
L["PVE_COL_VAULT_SLOT2"] = "Vault Slot 2"
L["PVE_COL_VAULT_SLOT3"] = "Vault Slot 3"
L["PVE_NO_CHARACTER"] = "No character data available"
L["LV_FORMAT"] = "Lv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_WORLD"] = "World"
L["VAULT_SLOT_FORMAT"] = "%s Slot %d"
L["VAULT_NO_PROGRESS"] = "No progress yet"
L["VAULT_UNLOCK_FORMAT"] = "Complete %s activities to unlock"
L["VAULT_NEXT_TIER_FORMAT"] = "Next Tier: %d iLvL on complete %s"
L["VAULT_REMAINING_FORMAT"] = "Remaining: %s activities"
L["VAULT_PROGRESS_FORMAT"] = "Progress: %s / %s"
L["OVERALL_SCORE_LABEL"] = "Overall Score:"
L["BEST_KEY_FORMAT"] = "Best Key: +%d"
L["SCORE_FORMAT"] = "Score: %s"
L["NOT_COMPLETED_SEASON"] = "Not completed this season"
L["CURRENT_MAX_FORMAT"] = "Current: %s / %s"
L["PROGRESS_PERCENT_FORMAT"] = "Progress: %.1f%%"
L["NO_CAP_LIMIT"] = "No cap limit"
L["GREAT_VAULT"] = "Great Vault"
L["LOADING_PVE"] = "Loading PvE Data..."
L["PVE_APIS_LOADING"] = "Please wait, WoW APIs are initializing..."
L["NO_VAULT_DATA"] = "No vault data"
L["NO_DATA"] = "No data"
L["KEYSTONE"] = "Keystone"
L["NO_KEY"] = "No Key"
L["AFFIXES"] = "Affixes"
L["NO_AFFIXES"] = "No Affixes"
L["VAULT_BEST_KEY"] = "Best Key:"
L["VAULT_SCORE"] = "Score:"

-- Vault Tooltip (detailed)
L["VAULT_UNLOCKED"] = "Unlocked"
L["VAULT_LOCKED"] = "Locked"
L["VAULT_IN_PROGRESS"] = "In Progress"
L["VAULT_COMPLETED_ACTIVITIES"] = "Completed"
L["VAULT_CURRENT_TIER"] = "Current Tier"
L["VAULT_REWARD"] = "Current Reward"
L["VAULT_REWARD_ON_UNLOCK"] = "Reward on Unlock"
L["VAULT_UPGRADE_HINT"] = "Upgrade"
L["VAULT_MAX_TIER"] = "Max Tier"
L["VAULT_AT_MAX"] = "Maximum tier reached!"
L["VAULT_BEST_SO_FAR"] = "Best So Far"
L["VAULT_DUNGEONS"] = "dungeons"
L["VAULT_BOSS_KILLS"] = "boss kills"
L["VAULT_WORLD_ACTIVITIES"] = "world activities"
L["VAULT_ACTIVITIES"] = "activities"
L["VAULT_REMAINING_SUFFIX"] = "remaining"
L["VAULT_COMPLETE_PREFIX"] = "Complete"
L["VAULT_SLOT1_HINT"] = "First choice from this row"
L["VAULT_SLOT2_HINT"] = "Second choice (more options!)"
L["VAULT_SLOT3_HINT"] = "Third choice (max options)"
L["VAULT_IMPROVE_TO"] = "Improve to"
L["VAULT_COMPLETE_ON"] = "Complete this activity on %s"
L["VAULT_ENCOUNTER_LIST_FORMAT"] = "%s"
L["VAULT_TOP_RUNS_FORMAT"] = "Top %d Runs This Week"
L["VAULT_DELVE_TIER_FORMAT"] = "Tier %d (%d)"
L["VAULT_REWARD_HIGHEST"] = "Reward at Highest Item Level"
L["VAULT_UNLOCK_REWARD"] = "Unlock Reward"
L["VAULT_COMPLETE_MORE_FORMAT"] = "Complete %d more %s this week to unlock."
L["VAULT_BASED_ON_FORMAT"] = "The item level of this reward will be based on the lowest of your top %d runs this week (currently %s)."
L["VAULT_RAID_BASED_FORMAT"] = "Reward based on highest difficulty defeated (currently %s)."

-- Delves Section (PvE Tab)
L["DELVES"] = "Delves"
L["COMPANION"] = "Companion"
L["BOUNTIFUL_DELVE"] = "Trovehunter's Bounty"
L["PVE_BOUNTY_NEED_LOGIN"] = "No saved status for this character. Log in to refresh."
L["CRACKED_KEYSTONE"] = "Cracked Keystone"
L["SEASON"] = "Season"

-- Reputation Tab
L["REP_TITLE"] = "Reputation Overview"
L["REP_SUBTITLE"] = "Track factions and renown across your warband"
L["REP_DISABLED_TITLE"] = "Reputation Tracking"
L["REP_LOADING_TITLE"] = "Loading Reputation Data"
L["REP_SEARCH"] = "Search reputations..."
L["REP_PARAGON_TITLE"] = "Paragon Reputation"
L["REP_REWARD_AVAILABLE"] = "Reward available!"
L["REP_CONTINUE_EARNING"] = "Continue earning reputation for rewards"
L["REP_CYCLES_FORMAT"] = "Cycles: %d"
L["REP_PROGRESS_HEADER"] = "Progress: %d/%d"
L["REP_PARAGON_PROGRESS"] = "Paragon Progress:"
L["REP_PROGRESS_COLON"] = "Progress:"
L["REP_CYCLES_COLON"] = "Cycles:"
L["REP_CHARACTER_PROGRESS"] = "Character Progress:"
L["REP_RENOWN_FORMAT"] = "Renown %d"
L["REP_PARAGON_FORMAT"] = "Paragon (%s)"
L["REP_UNKNOWN_FACTION"] = "Unknown Faction"
L["REP_API_UNAVAILABLE_TITLE"] = "Reputation API Not Available"
L["REP_API_UNAVAILABLE_DESC"] = "The C_Reputation API is not available on this server. This feature requires WoW 11.0+ (The War Within)."
L["REP_FOOTER_TITLE"] = "Reputation Tracking"
L["REP_FOOTER_DESC"] = "Reputations are scanned automatically on login and when changed. Use the in-game reputation panel to view detailed information and rewards."
L["REP_CLEARING_CACHE"] = "Clearing cache and reloading..."
L["REP_LOADING_DATA"] = "Loading reputation data..."
L["REP_MAX"] = "Max."
L["REP_TIER_FORMAT"] = "Tier %d"
L["ACCOUNT_WIDE_LABEL"] = "Account-Wide"
L["NO_RESULTS"] = "No results"
L["NO_REP_MATCH"] = "No reputations match '%s'"
L["NO_REP_DATA"] = "No reputation data available"
L["REP_SCAN_TIP"] = "Reputations are scanned automatically. Try /reload if nothing appears."
L["ACCOUNT_WIDE_REPS_FORMAT"] = "Account-Wide Reputations (%s)"
L["NO_ACCOUNT_WIDE_REPS"] = "No account-wide reputations"
L["NO_CHARACTER_REPS"] = "No character-based reputations"

-- Currency Tab
L["GOLD_LABEL"] = "Gold"
L["CURRENCY_TITLE"] = "Currency Tracker"
L["CURRENCY_SUBTITLE"] = "Track all currencies across your characters"
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
L["NO_FOUND_FORMAT"] = "No %ss found"
L["PLANS_COUNT_FORMAT"] = "%d plans"
L["PET_BATTLE_LABEL"] = "Pet Battle:"
L["QUEST_LABEL"] = "Quest:"

-- Settings Tab
L["CURRENT_LANGUAGE"] = "Current Language:"
L["LANGUAGE_TOOLTIP"] = "Addon uses your WoW game client's language automatically. To change, update your Battle.net settings."
L["POPUP_DURATION"] = "Popup Duration"
L["NOTIFICATION_DURATION"] = "Notification Duration"
L["POPUP_POSITION"] = "Popup Position"
L["NOTIFICATION_POSITION"] = "Notification Position"
L["SET_POSITION"] = "Set Position"
L["SET_BOTH_POSITION"] = "Set Both Position"
L["DRAG_TO_POSITION"] = "Drag to position\nRight-click to confirm"
L["RESET_DEFAULT"] = "Reset Default"
L["RESET_POSITION"] = "Reset Position"
L["TEST_POPUP"] = "Test Popup"
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
L["POPUP_POSITION_MAIN"] = "Main (achievements, mounts, etc.)"
L["POPUP_POSITION_SAME_CRITERIA"] = "Same position for all (achievement, criteria progress, etc.)"
L["CRITERIA_POSITION_LABEL"] = "Criteria progress position"
L["SET_POSITION_CRITERIA"] = "Set Criteria Position"
L["RESET_CRITERIA_BLIZZARD"] = "Reset (right side)"
L["USE_ALERTFRAME_POSITION"] = "Use AlertFrame position"
L["USE_ALERTFRAME_POSITION_ACTIVE"] = "Using Blizzard AlertFrame position"
L["NOTIFICATION_GHOST_MAIN"] = "Achievement / notification"
L["NOTIFICATION_GHOST_CRITERIA"] = "Criteria progress"
L["SHOW_WEEKLY_PLANNER"] = "Weekly Planner (Characters)"
L["LOCK_MINIMAP_ICON"] = "Lock Minimap Button"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Show Items in Tooltips"
L["AUTO_SCAN_ITEMS"] = "Auto-Scan Items"
L["LIVE_SYNC"] = "Live Sync"
L["BACKPACK_LABEL"] = "Backpack"
L["REAGENT_LABEL"] = "Reagent"

-- Shared Widgets & Dialogs
L["MODULE_DISABLED"] = "Module Disabled"
L["LOADING"] = "Loading..."
L["PLEASE_WAIT"] = "Please wait..."
L["RESET_PREFIX"] = "Reset:"
L["TRANSFER_CURRENCY"] = "Transfer Currency"
L["AMOUNT_LABEL"] = "Amount:"
L["TO_CHARACTER"] = "To Character:"
L["SELECT_CHARACTER"] = "Select character..."
L["CURRENCY_TRANSFER_INFO"] = "Currency window will be opened automatically.\nYou'll need to manually right-click the currency to transfer."
L["SAVE"] = "Save"
L["TITLE_FIELD"] = "Title:"
L["DESCRIPTION_FIELD"] = "Description:"
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
L["CHARACTER_OVERVIEW"] = "Character Overview"
L["TOTAL_CHARACTERS"] = "TOTAL"
L["TRACKED_CHARACTERS"] = "TRACKED"
L["FACTION_SPLIT"] = "FACTION"
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
L["SET_TRY_COUNT_TEXT"] = "Set try count for:\n%s"
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
L["QUEST_CAT_ASSIGNMENT"] = "Assignment"

-- Plans - Browse
L["UNKNOWN_CATEGORY"] = "Unknown Category"
L["SCANNING_FORMAT"] = "Scanning %s"
L["CUSTOM_PLAN_SOURCE"] = "Custom plan"
L["POINTS_FORMAT"] = "%d Points"
L["SOURCE_NOT_AVAILABLE"] = "Source information not available"
L["SOURCE_QUEST_REWARD"] = "Quest reward"
L["PROGRESS_ON_FORMAT"] = "You are %d/%d on the progress"
L["COMPLETED_REQ_FORMAT"] = "You completed %d of %d total requirements"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["WEEKLY_RESET_LABEL"] = "Weekly Reset"
L["CROSS_CHAR_SUMMARY"] = "Character Overview"
L["QUEST_TYPE_DAILY"] = "Daily Quests"
L["QUEST_TYPE_DAILY_DESC"] = "Regular daily quests from NPCs"
L["QUEST_TYPE_WORLD"] = "World Quests"
L["QUEST_TYPE_WORLD_DESC"] = "Zone-wide world quests"
L["QUEST_TYPE_WEEKLY"] = "Weekly Quests"
L["QUEST_TYPE_WEEKLY_DESC"] = "Weekly recurring quests"
L["QUEST_TYPE_ASSIGNMENTS"] = "Assignments"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Special assignments and tasks"
L["QUEST_TYPE_CONTENT_EVENTS"] = "Content Events"
L["QUEST_TYPE_CONTENT_EVENTS_DESC"] = "Bonus objectives, event tasks, and campaign-style activities"
L["QUEST_CAT_CONTENT_EVENTS"] = "Content Event"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mythic+"

-- PlanCardFactory
L["FACTION_LABEL"] = "Faction:"
L["FRIENDSHIP_LABEL"] = "Friendship"
L["RENOWN_TYPE_LABEL"] = "Renown"
L["ADD_BUTTON"] = "+ Add"
L["ADDED_LABEL"] = "Added"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s of %s (%s%%)"

-- Settings - General Tooltips
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Display stack counts on items in the storage and items view"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Show or hide the Weekly Planner section inside the Characters tab"
L["LOCK_MINIMAP_TOOLTIP"] = "Lock the minimap button in place so it cannot be dragged"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Display Warband and Character item counts in tooltips (WN Search)."
L["AUTO_SCAN_TOOLTIP"] = "Automatically scan and cache items when you open banks or bags"
L["LIVE_SYNC_TOOLTIP"] = "Keep item cache updated in real-time while banks are open"
L["SHOW_ILVL_TOOLTIP"] = "Display item level badges on equipment in the item list"
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
L["REPUTATION_GAINS_TOOLTIP"] = "Display reputation gain messages in chat when you earn faction standing"
L["CURRENCY_GAINS"] = "Currency Gains in Chat"
L["CURRENCY_GAINS_TOOLTIP"] = "Display currency gain messages in chat when you earn currencies"
L["SCREEN_FLASH_EFFECT"] = "Flash on Rare Drop"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Play a screen flash animation when you finally obtain a collectible after multiple farming attempts"
L["AUTO_TRY_COUNTER"] = "Auto-Track Drop Attempts"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Automatically count failed drop attempts when looting NPCs, rares, bosses, fishing, or containers. With this on, each counted miss also prints a short line to chat (see Try counter chat output below for Loot vs separate filter vs all tabs). Attempt totals update in the UI; obtained / reset lines still print as before. Moving from Rarity: enable Rarity once, then |cff00ccff/wn rarityimport|r (copies data + backup), then you can disable Rarity; |cff00ccff/wn rarityrestore|r reapplies the saved backup if needed."
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
L["MODULE_ITEMS"] = "Items"
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
L["ITEM_LEVEL_FORMAT"] = "Item Level %s"
L["ITEM_NUMBER_FORMAT"] = "Item #%s"
L["CHARACTER_CURRENCIES"] = "Character Currencies:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Account-wide (Warband) — same balance on all characters."
L["YOU_MARKER"] = "(You)"
L["WN_SEARCH"] = "WN Search"
L["WARBAND_BANK_COLON"] = "Warband Bank:"
L["AND_MORE_FORMAT"] = "... and %d more"

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
L["UNCLAIMED_REWARDS"] = "You have unclaimed rewards"

-- Minimap Button
L["TOTAL_GOLD_LABEL"] = "Total Gold:"
L["MINIMAP_CHARS_GOLD"] = "Characters Gold:"
L["CHARACTERS_COLON"] = "Characters:"
L["LEFT_CLICK_TOGGLE"] = "Left-Click: Toggle window"
L["RIGHT_CLICK_PLANS"] = "Right-Click: Open Plans"
L["MINIMAP_SHOWN_MSG"] = "Minimap button shown"
L["MINIMAP_HIDDEN_MSG"] = "Minimap button hidden (use /wn minimap to show)"
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
L["MAX_BUTTON"] = "Max"
L["OPEN_AND_GUIDE"] = "Open & Guide"
L["FROM_LABEL"] = "From:"
L["AVAILABLE_LABEL"] = "Available:"
L["ONLINE_LABEL"] = "(Online)"
L["DATA_SOURCE_TITLE"] = "Data Source Information"
L["DATA_SOURCE_USING"] = "This tab is using:"
L["DATA_SOURCE_MODERN"] = "Modern cache service (event-driven)"
L["DATA_SOURCE_LEGACY"] = "Legacy direct DB access"
L["DATA_SOURCE_NEEDS_MIGRATION"] = "Needs migration to cache service"
L["GLOBAL_DB_VERSION"] = "Global DB Version:"

-- Information Dialog - Tab Headers
L["INFO_TAB_CHARACTERS"] = "Characters"
L["INFO_TAB_ITEMS"] = "Items"
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
L["SUPPORTERS_TITLE"] = "Supporters"
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
L["DEBUG_DISABLED"] = "Debug mode DISABLED."
L["CHARACTER_LABEL"] = "Character:"
L["TRACK_USAGE"] = "Usage: enable | disable | status"

-- Welcome Messages
L["CLICK_TO_COPY"] = "Click to copy invite link"
L["COPIED_LABEL"] = "Copied!"

L["WELCOME_MSG_FORMAT"] = "Welcome to Warband Nexus v%s"
L["WELCOME_TYPE_CMD"] = "Please type"
L["WELCOME_OPEN_INTERFACE"] = "to open the interface."
L["WELCOME_NEW_VERSION_CHAT"] = "|cffffff00What's New:|r a popup may appear above chat, or type |cffffff00/wn changelog|r."
L["CONFIG_SHOW_LOGIN_CHAT"] = "Login message in chat"
L["CONFIG_SHOW_LOGIN_CHAT_DESC"] = "Print a short welcome line when notifications are enabled. Uses the System message group and a visible chat tab so addons like Chattynator can show it. (The What's New window is separate — fullscreen popup.)"
L["CONFIG_HIDE_PLAYED_TIME_CHAT"] = "Hide Time Played in chat"
L["CONFIG_HIDE_PLAYED_TIME_CHAT_DESC"] = "Filter out Total time played and Time played this level system messages. Turn off to show them again (including when you type /played)."

-- What's New (current release only; older entries are not kept in-repo)
L["CHANGELOG_V256"] = "v2.5.6\nImprovements:\n- Readable realm spacing in Gear, weekly plans, Plans tracker, tracking dialog (saved keys still use Blizzard normalized realm text)\n- Collectibles: wider BfA Bloodfeaster NPC list; clearer notes for chest vs boss and multi-corpse try counting\n- SplitCharacterKey + first-hyphen-only parsing for Name-Realm strings\n- Mount DB audits: community DB/Mounts Lua + Wowhead/WoWDB\n\nBug fixes:\n- Try Counter: chat loot + shared drop tables (e.g. Tamed Bloodfeaster) no longer lose CHAT try updates\n- Hyphenated realms (Azjol-Nerub): canonical keys, GetAllCharacters repair, stats/minimap labels; one-time realm-field migration\n- Mount item IDs: Verdant Skitterfly (192764), Red Qiraji crystal (21321)\n- Tracking dialog: GetRealmName guarded for secret values\n\nLocalization:\n- TRY_COUNT click / right-click hints in all locales\n\nRepo: Git tracks addon sources only (Core, Modules, Locales, toc, CHANGES)\n\nCurseForge: Warband Nexus"

L["CHANGELOG_V257"] = "v2.5.7b\nHotfix:\n- Gear tab character selector and dropdown layout.\n- About dialog credits and contributors.\n\nImprovements:\n- Characters: Default Order sort (online first, then level, name); new profiles default; sort menu maps unknown keys to first option\n- Characters: logged-in character always first in Favorites / Characters / Untracked; manual custom order seeds untracked; reorder keeps online at top\n- Settings: WindowManager POPUP strata and ESC stack with main window; keyboard re-enabled after Show; font rebuild unregisters frame\n- WindowManager: combat restore re-enables EnableKeyboard as well as keyboard propagation\n- Try Counter: instance difficulty from entry snapshot + GetInstanceInfo (fixes Mythic misread as Normal, e.g. Mechagon HK-8)\n- Try Counter: one difficulty filter for loot, delayed ENC, CHAT; matching encounter dedup keys\n- Try Counter: dedup key recorded when zero trackable drops after rules\n- Try Counter: merged open-world corpse multiplier for shared mount item across NPC templates\n- Try Counter: LOOT_READY double-fire keeps loot session; deduped debug trace spam\n- Try Counter: [WN-Drops] one line per drop — Collectible Detected : Boss - item - (difficulty) - tries; gated difficulty green/red/amber; em dash when any difficulty\n\nBug fixes:\n- Try Counter: counter could rise after a difficulty skip (loot vs delayed/CHAT)\n\nLocalization:\n- SORT_MODE_DEFAULT; TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED and related strings\n\nCurseForge: Warband Nexus"

L["CHANGELOG_V258"] = "v2.5.8\nBug fixes:\n- Try Counter: CHAT_MSG_LOOT no longer errors on the fishing attribution path (CurrentUnitsHaveMobLootContext forward declaration; was a nil global).\n\nCurseForge: Warband Nexus"

-- Combined What's New (2.5.6 through 2.5.9); fallback if CHANGELOG_V258 missing (2.5.8 uses V258)
L["CHANGELOG_V259"] = [=[v2.5.9 (2026-04-03)

Improvements
- Collectibles / Try Counter: Battle of Dazar'alor — Glacial Tidestorm remains Mythic-only from Lady Jaina (not LFR). G.M.O.D.: Raid Finder from Jaina; Normal/Heroic/Mythic from High Tinker Mekkatorque (2019 hotfix). Try Counter now matches LFR explicitly; statistics reseed uses per-drop statisticIds when one NPC has different difficulties per mount; login seeding and missed-loot reseed iterate drops with their own stat columns; Mekkatorque G.M.O.D. reseed no longer sums Jaina LFR kills (13379).
- CollectibleSourceDB: legacyEncounters (mount-only bosses) realigned to Midnight retail DungeonEncounter IDs.
- Repository: Git tracks addon sources only (Core, Modules, Locales, toc, CHANGES, LICENSE, README); dev documentation and audit scripts removed from the tree.

--- 2.5.8 ---
Bug fixes
- Try Counter: CHAT_MSG_LOOT no longer errors on the fishing attribution path (CurrentUnitsHaveMobLootContext forward declaration; was a nil global).

--- 2.5.7 / 2.5.7b ---
Hotfix
- Gear tab: character selector and dropdown layout.
- About / Info dialog: credits and contributors.

Improvements
- Characters tab: new Default Order sort (logged-in character first, then level high to low, then name A–Z). Core defaults set characterSort.key to default for new profiles. Sort dropdown maps unknown or invalid saved keys to the first menu option (per tab). Logged-in character stays at the top of Favorites, tracked, and Untracked for all sort modes including manual; manual custom-order seed includes every character in the section with the online character first; characterOrder gains an untracked list; reorder keeps the online character pinned to the top.
- Settings window: uses WindowManager (POPUP priority, shared ESC handler with the main window) instead of a fixed FULLSCREEN_DIALOG strata/frame level. RefreshSettingsKeyboard re-enables keyboard when showing an existing frame after Hide/Show. Font-related rebuilds unregister the settings frame from WindowManager before closing it.
- WindowManager: after combat, when restoring visible frames, call EnableKeyboard(true) in addition to SetPropagateKeyboardInput(true) so ESC/focus behavior is reliable.
- Try Counter: instance difficulty prefers a snapshot taken on instance entry (PLAYER_ENTERING_WORLD) keyed by instance ID, then live GetInstanceInfo, before ENCOUNTER_END and dungeon/raid APIs — fixes Mythic runs misread as Normal (e.g. Operation: Mechagon, HK-8). ResolveLiveInstanceDifficultyID handles M+ and APIs when GetInstanceInfo difficulty is 0; ResolveEffectiveEncounterDifficultyID centralizes effective difficulty for gating.
- Try Counter: FilterDropsByDifficulty (and shared collectible-collected checks) used consistently for loot processing, delayed ENCOUNTER_END handling, and CHAT_MSG_LOOT. CHAT path uses the same encounter dedup key as the loot window.
- Try Counter: when a boss loot pass yields zero trackable drops (difficulty gate or all collected), still record the encounter dedup key so delayed ENC/CHAT cannot increment the same kill again.
- Try Counter: merged open-world loot uses an item-ID-based corpse multiplier so mixed NPC templates that share the same mount drop (e.g. Nazmir Bloodfeaster) count every corpse, not only the first matched NPC id.
- Try Counter: LOOT_READY may fire twice while the window is open — second READY no longer clears an active loot session; debug trace lines for LOOT_READY/LOOT_CLOSED are deduped within a short window to reduce chat spam.
- Try Counter: [WN-Drops] instance reminder uses TRYCOUNTER_INSTANCE_DROPS_HEADER; when the DB gates a drop by difficulty, the required label is shown in parentheses after the item link — green if the current instance qualifies, red if not, amber if current difficulty cannot be verified (long prose wrong-diff messages removed from chat).

Bug fixes
- Try Counter: attempt counter could increase even after a skipped difficulty message (loot path vs delayed ENC / CHAT duplicate attribution).

Localization
- SORT_MODE_DEFAULT; TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED and related strings.

--- 2.5.6 ---
Improvements
- Readable realm spacing in Gear, weekly plans, Plans tracker, tracking dialog (saved keys still use Blizzard normalized realm text).
- Collectibles: wider BfA Tamed Bloodfeaster NPC list; clearer notes for chest vs boss and multi-corpse try counting.
- SplitCharacterKey + first-hyphen-only parsing for Name-Realm strings.
- Mount DB cross-checks: community DB/Mounts Lua + Wowhead/WoWDB.

Bug fixes
- Try Counter: chat loot + shared drop tables (e.g. Tamed Bloodfeaster) no longer lose CHAT try updates.
- Hyphenated realms (Azjol-Nerub): canonical keys, GetAllCharacters repair, stats/minimap labels; one-time realm-field migration.
- Mount item IDs: Verdant Skitterfly (192764), Red Qiraji crystal (21321).
- Tracking dialog: GetRealmName guarded for secret values.

Localization
- TRY_COUNT click / right-click hints in all locales.

What's next
- Further Midnight collectible and encounter-ID checks; Try Counter and notifications tuned from live raid and dungeon behavior.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.5.9b (key CHANGELOG_V259b)
L["CHANGELOG_V259b"] = [=[v2.5.9b (2026-04-04)

Improvements
- Tooltips: Collectible drop hints on NPC unit tooltips only show for hostile or attackable targets (fixes wrong mount lines on friendly delve objects and similar). Safe checks for UnitCanAttack, UnitIsDead, and UnitReaction (Midnight secret-value rules).
- Packaging: Maintainer ZIP builds use build_addon.py (Python 3.8+); archive entry names use forward slashes so Linux, macOS, and CurseForge Linux extract into Interface/AddOns/WarbandNexus correctly.

Bug fixes
- Try Counter: Clearer separation of fishing vs. profession gathering and game-object-only loot; fewer false increments (e.g. herb gathering vs. mount farming). Loot session timing and CHAT_MSG_LOOT handling tightened.

Plans UI
- To-Do List and Weekly Progress: Show Planned / Show Completed behavior aligned with browse tabs; clearer empty states for achievements and collection browsers.

Chat
- Try Counter lines can follow Loot tabs, a dedicated WN_TRYCOUNTER channel, or all standard tabs; button adds the channel to the selected chat tab. Optional login welcome line; settings to hide played-time spam and request /played quietly for stats.

Localization
- Filled previously missing keys in all supported locales.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.5.10 (key CHANGELOG_V2510)
L["CHANGELOG_V2510"] = [=[v2.5.10 (2026-04-04)

Bug fixes
- Tooltips: yellow "(Planned)" only when the mount, pet, or toy is still missing. NPC/container drop lines, yield sub-lines, and item tooltips use journal and toy ownership checks (Midnight-safe pcall and secret-value rules). Drops listed as generic type "item" in the database now resolve collection the same way so completed items no longer keep the Planned tag next to the checkmark.

CurseForge: Warband Nexus]=]

-- What's New / changelog body for ADDON_VERSION 2.5.11 (key CHANGELOG_V2511)
L["CHANGELOG_V2511"] = [=[v2.5.11 (2026-04-07)

PvE
- Trovehunter's Bounty / Bountiful column: per-character cache for each header row; live quest API only for the current character when no snapshot exists (alts show "—" until logged in).
- Midnight-safe weekly quest checks (pcall + secret guards) in PvE cache.
- Trovehunter weekly flag uses hidden quest 86371 only (removed OR with Cracked Keystone 92600 / Bountiful Delves 81514 so the column is not falsely "done").
- Bountiful cell tooltip; PVE_BOUNTY_NEED_LOGIN when an alt has no saved status yet.

Collections
- Achievements tab: full category enumeration via GetCategoryNumAchievements(categoryID, true) — fixes the list showing only the last earned achievement.
- One-time full achievement re-scan after this update (global wnAchievementIncludeAllScanV1).

Try Counter & data
- Mount/pet collected handling, missed-drop filtering, C_Timer.After callback fix; Lucent Hawkstrider mount ID in CollectibleSourceDB.

Plans / UI
- To-Do / tracker: try-count popup can be left-click only (no right-click popup on cards).
- Information dialog: Special Thanks block (Contributors-style).

Localization
- Credits / Special Thanks strings updated across locales; PVE_BOUNTY_NEED_LOGIN (enUS).

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
L["REP_LOADING_PROCESSING_COUNT"] = "Processing... (%d/%d)"
L["REP_LOADING_SAVING"] = "Saving to database..."
L["REP_LOADING_COMPLETE"] = "Complete!"

-- Status / Footer
L["COMBAT_LOCKDOWN_MSG"] = "Cannot open window during combat. Please try again after combat ends."
L["BANK_IS_ACTIVE"] = "Bank is Active"
L["ITEMS_CACHED_FORMAT"] = "%d items cached"
-- Table Headers (SharedWidgets, Professions)
L["TABLE_HEADER_CHARACTER"] = "Character"
L["TABLE_HEADER_LEVEL"] = "LEVEL"
L["TABLE_HEADER_GOLD"] = "GOLD"
L["TABLE_HEADER_LAST_SEEN"] = "Last Seen"

-- Search / Empty States
L["NO_ITEMS_MATCH"] = "No items match '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "No items match your search"
L["ITEMS_SCAN_HINT"] = "Items are scanned automatically. Try /reload if nothing appears."
L["ITEMS_WARBAND_BANK_HINT"] = "Open Warband Bank to scan items (auto-scanned on first visit)"

-- Currency Transfer Steps
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Next steps:"
L["CURRENCY_TRANSFER_STEP_1"] = "Find |cffffffff%s|r in the Currency window"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Right-click|r on it"
L["CURRENCY_TRANSFER_STEP_3"] = "Select |cffffffff'Transfer to Warband'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Choose |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Enter amount: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "Currency window is now open!"
L["CURRENCY_TRANSFER_SECURITY"] = "(Blizzard security prevents automatic transfer)"

-- Plans UI Extra
L["ZONE_PREFIX"] = "Zone: "
L["ADDED"] = "Added"
L["WEEKLY_VAULT_TRACKER"] = "Weekly Vault Tracker"
L["DAILY_QUEST_TRACKER"] = "Daily Quest Tracker"
L["CUSTOM_PLAN_STATUS"] = "Custom plan '%s' %s"

-- Achievement Popup
L["ACHIEVEMENT_COMPLETED"] = "Completed"
L["ACHIEVEMENT_NOT_COMPLETED"] = "Not Completed"
L["ACHIEVEMENT_POINTS_FORMAT"] = "%d pts"
L["ADD_PLAN"] = "Add"
L["PLANNED"] = "Planned"

-- PlanCardFactory Vault Slots
L["VAULT_SLOT_WORLD"] = "World"

-- PvE Extra
L["AFFIX_TITLE_FALLBACK"] = "Affix"

-- Chat Messages
L["CHAT_REP_STANDING_LABEL"] = "Now"
L["CHAT_GAINED_PREFIX"] = "+"

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
L["SAVE"] = "Save"

-- Empty State Cards
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
L["NO_SCAN"] = "Not scanned"
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
L["PROFILES"] = "Profiles"
L["PROFILES_DESC"] = "Manage addon profiles"

-- Achievement/Criteria Display
L["NO_CRITERIA_FOUND"] = "No criteria found"
L["NO_REQUIREMENTS_INSTANT"] = "No requirements (instant completion)"

-- Professions Tab
L["TAB_PROFESSIONS"] = "Professions"
L["TAB_COLLECTIONS"] = "Collections"
L["COLLECTIONS_SUBTITLE"] = "Mounts, pets, toys, and transmog overview"
L["COLLECTIONS_COMING_SOON_TITLE"] = "Coming Soon"
L["COLLECTIONS_COMING_SOON_DESC"] = "Collection overview (mounts, pets, toys, transmog) will be available here."
L["SELECT_MOUNT_FROM_LIST"] = "Select a mount from the list"
L["SELECT_PET_FROM_LIST"] = "Select a pet from the list"
L["SELECT_TO_SEE_DETAILS"] = "Select a %s to see details."
L["SOURCE"] = "Source"
L["YOUR_PROFESSIONS"] = "Warband Professions"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s characters with professions"
L["PROFESSIONS_WIDE_TABLE_HINT"] = "Tip: use the bar below or Shift+mouse wheel to see all columns."
L["HEADER_PROFESSIONS"] = "Professions Overview"
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
L["PROF_OPEN_RECIPE"] = "Open"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Open this profession's recipe list"
L["PROF_ONLY_CURRENT_CHAR"] = "Only available for the current character"
L["NO_PROFESSION"] = "No Profession"

-- Professions: Expansion filter (title card dropdown)
L["PROF_FILTER_EXPANSION"] = "Expansion filter"
L["PROF_FILTER_STRICT_NOTE"] = "Show only this expansion's profession data for all characters."
L["PROF_DATA_SOURCE_NOTE"] = "Concentration, knowledge, recipes update when you open the profession window (K) on each character."
L["PROF_FILTER_ALL"] = "All"
L["PROF_FIRSTCRAFT_OPEN_WINDOW"] = "Open a profession window first, then run this command again."
L["PROF_FIRSTCRAFT_NO_DATA"] = "No profession data available."
L["PROF_FIRSTCRAFT_HEADER"] = "First-craft bonus recipes"
L["PROF_FIRSTCRAFT_NONE"] = "No learned recipes with first-craft bonus remaining."
L["PROF_FIRSTCRAFT_TOTAL"] = "Total"
L["PROF_FIRSTCRAFT_RECIPES"] = "recipe(s)"

-- Professions: Column Headers (label keys used by HEADER_DEFS)
L["FIRST_CRAFT"] = "First Craft"
L["UNIQUES"] = "Uniques"
L["TREATISE"] = "Treatise"
L["GATHERING"] = "Gathering"
L["CATCH_UP"] = "Catch Up"
L["MOXIE"] = "Moxie"
L["COOLDOWNS"] = "Cooldowns"
L["ACCESSORY_1"] = "Acc 1"
L["ACCESSORY_2"] = "Acc 2"
L["COLUMNS_BUTTON"] = "Columns"
L["ORDERS"] = "Orders"

-- Professions: Tooltips & Details
L["RECIPES_COLUMN_FORMAT"] = "Column shows Learned / Total (total includes unlearned)"
L["LEARNED_RECIPES"] = "Learned Recipes"
L["UNLEARNED_RECIPES"] = "Unlearned Recipes"
L["LAST_SCANNED"] = "Last Scanned"
L["JUST_NOW"] = "Just now"
L["RECIPE_NO_DATA"] = "Open profession window to collect recipe data"
L["FIRST_CRAFT_AVAILABLE"] = "Available First Crafts"
L["FIRST_CRAFT_DESC"] = "Recipes that grant bonus XP on first craft"
L["SKILLUP_RECIPES"] = "Skill-up Recipes"
L["SKILLUP_DESC"] = "Recipes that can still increase your skill level"
L["NO_ACTIVE_COOLDOWNS"] = "No active cooldowns"

-- Professions: Crafting Orders
L["CRAFTING_ORDERS"] = "Crafting Orders"
L["PERSONAL_ORDERS"] = "Personal Orders"
L["PUBLIC_ORDERS"] = "Public Orders"
L["CLAIMS_REMAINING"] = "Claims Remaining"
L["NO_ACTIVE_ORDERS"] = "No active orders"
L["ORDER_NO_DATA"] = "Open profession at crafting table to scan"

-- Professions: Equipment
L["EQUIPMENT"] = "Equipment"
L["TOOL"] = "Tool"
L["ACCESSORY"] = "Accessory"
L["PROF_EQUIPMENT_HINT"] = "Open profession (K) on this character to scan equipment."

-- Professions: Info Window
L["PROF_INFO_TOOLTIP"] = "View profession details"
L["PROF_INFO_NO_DATA"] = "No profession data available.\nPlease login on this character and open the Profession window (K) to collect data."
L["PROF_INFO_SKILLS"] = "Expansion Skills"
L["PROF_INFO_SPENT"] = "Spent"
L["PROF_INFO_TOOL"] = "Tool"
L["PROF_INFO_ACC1"] = "Accessory 1"
L["PROF_INFO_ACC2"] = "Accessory 2"
L["PROF_INFO_KNOWN"] = "Known"
L["PROF_INFO_WEEKLY"] = "Weekly Knowledge Progress"
L["PROF_INFO_COOLDOWNS"] = "Cooldowns"
L["PROF_INFO_READY"] = "Ready"
L["PROF_INFO_LAST_UPDATE"] = "Last Updated"
L["PROF_INFO_UNLOCKED"] = "Unlocked"
L["PROF_INFO_LOCKED"] = "Locked"
L["PROF_INFO_UNLEARNED"] = "Unlearned"
L["PROF_INFO_NODES"] = "nodes"
L["PROF_INFO_RANKS"] = "ranks"

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
L["ADD_CUSTOM_DESC"] = "Add drop sources not in the built-in database, or remove existing custom entries."
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
L["NPC"] = "NPC"
L["OBJECT"] = "Object"
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
L["ADD_ITEMS_TO_PLANS"] = "Add items to your plans to see them here!"
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
L["COMBAT_CURRENCY_ERROR"] = "Cannot open currency frame during combat. Try again after combat."
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
L["CLEANUP_STALE_FORMAT"] = "Cleaned up %d stale character(s)"
L["PERSONAL_BANK"] = "Personal Bank"
L["WARBAND_BANK_LABEL"] = "Warband Bank"
L["WARBAND_BANK_TAB_FORMAT"] = "Tab %d"
L["CURRENCY_OTHER"] = "Other"
L["ERROR_SAVING_CHARACTER"] = "Error saving character:"

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
L["NOTIFICATION_GRIND_TRIES"] = "What a grind! %d attempts!"
L["NOTIFICATION_GOT_IT_AFTER"] = "You got it after %d tries!"
L["NOTIFICATION_TRY_SUBTITLE"] = "%d attempts"
L["NOTIFICATION_TRY_SUBTITLE_FIRST"] = "First attempt!"

-- TryCounterService: Messages
L["TRYCOUNTER_INCREMENT_CHAT"] = "%d attempts for %s"
L["TRYCOUNTER_CHAT_ATTEMPTS_FOR_LINK"] = "%d attempts for %s"
L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"] = "First attempt for %s"
L["TRYCOUNTER_CHAT_TAG_CONTAINER"] = "container"
L["TRYCOUNTER_CHAT_TAG_FISHING"] = "fishing"
L["TRYCOUNTER_CHAT_TAG_RESET"] = "counter reset"
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d attempts for %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "Obtained %s! Try counter reset."
L["TRYCOUNTER_CAUGHT_RESET"] = "Caught %s! Try counter reset."
L["TRYCOUNTER_CAUGHT"] = "Caught %s!"
L["TRYCOUNTER_CONTAINER_RESET"] = "Obtained %s from container! Try counter reset."
L["TRYCOUNTER_CONTAINER"] = "Obtained %s from container!"
L["TRYCOUNTER_AFTER_TRIES"] = "after %d tries"
L["TRYCOUNTER_FIRST_TRY"] = "on the first try!"
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Skipped: daily/weekly lockout active for this NPC."
L["TRYCOUNTER_INSTANCE_DROPS"] = "Collectible drops in this instance:"
L["TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED"] = "Collectible Detected : "
L["TRYCOUNTER_INSTANCE_WRONG_DIFF"] = "Wrong difficulty: needs %s (you are on %s)."
L["TRYCOUNTER_INSTANCE_REQUIRES_UNVERIFIED"] = "Requires %s (current difficulty unknown)."
L["TRYCOUNTER_COLLECTED_TAG"] = "(Collected)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " attempts"
L["TRYCOUNTER_TYPE_MOUNT"] = "Mount"
L["TRYCOUNTER_TYPE_PET"] = "Pet"
L["TRYCOUNTER_TYPE_TOY"] = "Toy"
L["TRYCOUNTER_TYPE_ITEM"] = "Item"
L["TRYCOUNTER_TRY_COUNTS"] = "Try Counts"

-- Loading Tracker Labels
L["LT_CHARACTER_DATA"] = "Character Data"
L["LT_CURRENCY_CACHES"] = "Currency & Caches"
L["LT_REPUTATIONS"] = "Reputations"
L["LT_PROFESSIONS"] = "Professions"
L["LT_PVE_DATA"] = "PvE Data"
L["LT_COLLECTIONS"] = "Collections"
L["LT_COLLECTION_DATA"] = "Collection Data"
L["LT_COLLECTION_SCAN"] = "Collection Scan"

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
L["CONFIG_MOD_ITEMS"] = "Items"
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
L["CONFIG_THEME_PRESETS"] = "Theme Presets"
L["CONFIG_THEME_APPLIED"] = "%s theme applied!"
L["CONFIG_THEME_RESET_DESC"] = "Reset all theme colors to their default purple theme."
L["CONFIG_NOTIFICATIONS"] = "Notifications"
L["CONFIG_NOTIFICATIONS_DESC"] = "Configure which notifications appear."
L["CONFIG_ENABLE_NOTIFICATIONS"] = "Enable Notifications"
L["CONFIG_ENABLE_NOTIFICATIONS_DESC"] = "Show popup notifications for collectible events."
L["CONFIG_NOTIFY_MOUNTS"] = "Mount Notifications"
L["CONFIG_NOTIFY_MOUNTS_DESC"] = "Show notifications when you learn a new mount."
L["CONFIG_NOTIFY_PETS"] = "Pet Notifications"
L["CONFIG_NOTIFY_PETS_DESC"] = "Show notifications when you learn a new pet."
L["CONFIG_NOTIFY_TOYS"] = "Toy Notifications"
L["CONFIG_NOTIFY_TOYS_DESC"] = "Show notifications when you learn a new toy."
L["CONFIG_NOTIFY_ACHIEVEMENTS"] = "Achievement Notifications"
L["CONFIG_NOTIFY_ACHIEVEMENTS_DESC"] = "Show notifications when you earn an achievement."
L["CONFIG_SHOW_UPDATE_NOTES"] = "Show Update Notes Again"
L["CONFIG_SHOW_UPDATE_NOTES_DESC"] = "Display the What's New window on next login."
L["CONFIG_UPDATE_NOTES_SHOWN"] = "Update notification will show on next login."
L["CONFIG_RESET_PLANS"] = "Reset Completed Plans"
L["CONFIG_RESET_PLANS_CONFIRM"] = "This will remove all completed plans. Continue?"
L["CONFIG_RESET_PLANS_FORMAT"] = "Removed %d completed plan(s)."
L["CONFIG_NO_COMPLETED_PLANS"] = "No completed plans to remove."
L["CONFIG_TAB_FILTERING"] = "Tab Filtering"
L["CONFIG_TAB_FILTERING_DESC"] = "Choose which tabs are visible in the main window."
L["CONFIG_CHARACTER_MGMT"] = "Character Management"
L["CONFIG_CHARACTER_MGMT_DESC"] = "Manage tracked characters and remove old data."
L["CONFIG_DELETE_CHAR"] = "Delete Character Data"
L["CONFIG_DELETE_CHAR_DESC"] = "Permanently remove all stored data for the selected character."
L["CONFIG_DELETE_CONFIRM"] = "Are you sure you want to permanently delete all data for this character? This cannot be undone."
L["CONFIG_DELETE_SUCCESS"] = "Character data deleted:"
L["CONFIG_DELETE_FAILED"] = "Character data not found."
L["CONFIG_FONT_SCALING"] = "Font & Scaling"
L["CONFIG_FONT_SCALING_DESC"] = "Adjust font family and size scaling."
L["CONFIG_FONT_FAMILY"] = "Font Family"
L["CONFIG_FONT_SIZE"] = "Font Size Scale"
L["CONFIG_FONT_PREVIEW"] = "Preview: The quick brown fox jumps over the lazy dog"
L["CONFIG_ADVANCED"] = "Advanced"
L["CONFIG_ADVANCED_DESC"] = "Advanced settings and database management. Use with caution!"
L["CONFIG_DEBUG_MODE"] = "Debug Mode"
L["CONFIG_DEBUG_MODE_DESC"] = "Enable verbose logging for debugging purposes. Only enable if troubleshooting issues."
L["CONFIG_DEBUG_VERBOSE"] = "Debug Verbose (cache/scan/tooltip logs)"
L["CONFIG_DEBUG_VERBOSE_DESC"] = "When Debug Mode is on, also show currency/reputation cache, bag scan, tooltip and profession logs. Leave off to reduce chat spam."
L["CONFIG_DB_STATS"] = "Show Database Statistics"
L["CONFIG_DB_STATS_DESC"] = "Display current database size and optimization statistics."
L["CONFIG_DB_OPTIMIZER_NA"] = "Database optimizer not loaded"
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
L["GOLD_MANAGEMENT_DESC"] = "Configure automatic gold management. Both deposits and withdrawals are performed automatically when the bank is open using C_Bank API."
L["GOLD_MANAGEMENT_WARNING"] = "|cff44ff44Fully Automatic:|r Both gold deposits and withdrawals are performed automatically when the bank is open. Set your target amount and let the addon manage your gold!"
L["GOLD_MANAGEMENT_ENABLE"] = "Enable Gold Management"
L["GOLD_MANAGEMENT_MODE"] = "Management Mode"
L["GOLD_MANAGEMENT_MODE_DEPOSIT"] = "Deposit Only"
L["GOLD_MANAGEMENT_MODE_DEPOSIT_DESC"] = "If you have more than X gold, excess will be automatically deposited to warband bank."
L["GOLD_MANAGEMENT_MODE_WITHDRAW"] = "Withdraw Only"
L["GOLD_MANAGEMENT_MODE_WITHDRAW_DESC"] = "If you have less than X gold, the difference will be automatically withdrawn from warband bank."
L["GOLD_MANAGEMENT_MODE_BOTH"] = "Both"
L["GOLD_MANAGEMENT_MODE_BOTH_DESC"] = "Automatically maintain exactly X gold on your character (deposit if over, withdraw if under)."
L["GOLD_MANAGEMENT_TARGET"] = "Target Gold Amount"
L["GOLD_MANAGEMENT_GOLD_LABEL"] = "gold"
L["GOLD_MANAGEMENT_HELPER"] = "Enter the amount of gold you want to keep on this character. The addon will automatically manage your gold when you open the bank."
L["GOLD_MANAGEMENT_CHAR_ONLY"] = "Only For This Character (%s)"
L["GOLD_MANAGEMENT_CHAR_ONLY_DESC"] = "Use separate gold management settings for this character only. Other characters will use the shared profile settings."
L["GOLD_MGMT_PROFILE_TITLE"] = "Profile (All Characters)"
L["GOLD_MGMT_TARGET_LABEL"] = "Target"
L["GOLD_MGMT_USING_PROFILE"] = "Using profile"
L["GOLD_MGMT_MODE_SHORT_DEPOSIT"] = "Deposit"
L["GOLD_MGMT_MODE_SHORT_WITHDRAW"] = "Withdraw"
L["GOLD_MGMT_MODE_SHORT_BOTH"] = "Both"
L["GOLD_MGMT_ACTIVE"] = "Active"
L["ENABLED"] = "Enabled"
L["DISABLED"] = "Disabled"
L["GOLD_MANAGEMENT_NOTIFICATION_DEPOSIT"] = "Deposit %s to warband bank (you have %s)"
L["GOLD_MANAGEMENT_NOTIFICATION_WITHDRAW"] = "Withdraw %s from warband bank (you have %s)"
L["GOLD_MANAGEMENT_DEPOSITED"] = "Deposited %s to warband bank"
L["GOLD_MANAGEMENT_WITHDRAWN"] = "Withdrawn %s from warband bank"
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
L["GEAR_CHARACTER_STATS"] = "Character Stats"
L["GEAR_NO_ITEM_EQUIPPED"] = "No item equipped in this slot."
L["GEAR_NO_PREVIEW"] = "No Preview"
L["GEAR_STATS_CURRENT_ONLY"] = "Stats available for\ncurrent character only"
L["GEAR_SLOT_RING1"] = "Ring 1"
L["GEAR_SLOT_RING2"] = "Ring 2"
L["GEAR_SLOT_TRINKET1"] = "Trinket 1"
L["GEAR_SLOT_TRINKET2"] = "Trinket 2"
L["GEAR_UPGRADE_AVAILABLE_FORMAT"] = "Available upgrade to %s %d/%d%s"
L["GEAR_UPGRADES_WITH_CURRENCY_FORMAT"] = "%d upgrade(s) with current currency"
L["GEAR_CRESTS_GOLD_ONLY"] = "Crests needed: 0 (gold only — previously reached)"
L["GEAR_UPGRADES_GOLD_ONLY_FORMAT"] = "%d upgrade(s) gold only (previously reached)"
L["GEAR_NEED_MORE_CRESTS_FORMAT"] = "%s %d/%d — need more crests"
L["GEAR_CRAFTED_RECRAFT_RANGE"] = "Recraft range: %d-%d (%s Dawncrest)"
L["GEAR_CRAFTED_CREST_COST"] = "Recraft cost: %d crests"
L["GEAR_CRAFTED_NO_CRESTS"] = "No crests available for recraft"

-- Characters UI
L["WOW_TOKEN_LABEL"] = "WoW Token"

-- SharedWidgets
L["FILTER_LABEL"] = FILTER or "Filter"

-- Statistics UI
L["FORMAT_BUTTON"] = "Format"

-- Professions UI
L["SHOW_ALL"] = "Show All"

-- Social
L["DISCORD_TOOLTIP"] = "Warband Nexus Discord"

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
L["BTN_CLOSE"] = CLOSE
L["BTN_REFRESH"] = REFRESH
L["BTN_SETTINGS"] = SETTINGS
L["CANCEL"] = CANCEL or "Cancel"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Achievements"
L["ACHIEVEMENT_SERIES"] = "Achievement Series"
L["CHILDREN_ACHIEVEMENTS"] = "Children Achievements"
L["LOADING_ACHIEVEMENTS"] = "Loading achievements..."
L["PARENT_ACHIEVEMENT"] = "Parent Achievement"
L["CATEGORY_ALL"] = ALL or "All Items"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables"
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["CATEGORY_MOUNTS"] = MOUNTS or "Mounts"
L["CATEGORY_PETS"] = PETS or "Pets"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest Items"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents"
L["CATEGORY_TITLES"] = TITLES or "Titles"
L["CATEGORY_TOYS"] = TOY_BOX or "Toys"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods"
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmog"
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " currency..."
L["DELETE"] = DELETE or "Delete"
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic"
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic"
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon"
L["ENABLE"] = ENABLE or "Enable"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Unknown"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables"
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods"
L["HEADER_CHARACTERS"] = CHARACTER or "Characters"
L["HEADER_FAVORITES"] = FAVORITES or "Favorites"
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Guild Bank"
L["ITEMS_PLAYER_BANK"] = BANK or "Player Bank"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " items..."
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
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Dungeons"
L["PVE_HEADER_RAIDS"] = RAIDS or "Raids"
L["PVP_TYPE"] = PVP or "PvP"
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC
L["RAIDS_LABEL"] = RAIDS or "Raids"
L["RAID_CAT"] = RAID or "Raid"
L["RELOAD_UI_BUTTON"] = RELOADUI or "Reload UI"
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " reputation..."
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
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Achievement"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Crafted"
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
L["STATS_HEADER"] = STATISTICS or "Statistics"
L["TAB_CHARACTERS"] = CHARACTER or "Characters"
L["TAB_CURRENCY"] = CURRENCY or "Currency"
L["TAB_ITEMS"] = ITEMS or "Items"
L["TAB_GEAR"] = "Gear"
L["TAB_REPUTATION"] = REPUTATION or "Reputation"
L["TAB_STATISTICS"] = STATISTICS or "Statistics"
L["GEAR_TAB_TITLE"] = "Gear Management"
L["GEAR_TAB_DESC"] = "Equipped gear, upgrade options, and cross-character upgrade candidates"
L["GEAR_SECTION_EQUIPPED"] = "Equipped Gear"
L["GEAR_SECTION_RESOURCES"] = "Resources"
L["GEAR_SECTION_UPGRADES"] = "Upgrade Opportunities"
L["GEAR_SECTION_STORAGE"] = "Storage Upgrades"
L["GEAR_SECTION_LIST"] = "All Equipped Items"
L["GEAR_UPGRADEABLE_SLOTS"] = "slot(s) upgradeable"
L["GEAR_NO_UPGRADES_AVAILABLE"] = "No upgrades available with current resources"
L["GEAR_NO_UPGRADE_ITEMS"] = "No upgrades available - all gear is at max tier or not supported."
L["GEAR_UPGRADE_CURRENT_CHAR_ONLY"] = "Upgrade info only available for current character."
L["GEAR_NO_STORAGE_FINDS"] = "No storage upgrades found. Open bank tabs to improve results."
L["GEAR_NO_CURRENCY_DATA"] = "No currency data yet"
L["GEAR_SEARCH_PLACEHOLDER"] = "Search equipped items..."
L["GEAR_NO_ITEMS_FOUND"] = "No matching equipped items found"
L["GEAR_STORAGE_BEST"] = "Best"
L["GEAR_STORAGE_WARBOUND"] = "Warbound"
L["GEAR_STORAGE_BOE"] = "BoE"
L["GEAR_STORAGE_UPGRADE_LINE"] = "%d → %d"
L["GEAR_STORAGE_TITLE"] = "Storage Upgrade Recommendations"
L["GEAR_STORAGE_DESC"] = "Best BoE / Warbound upgrades for each slot"
L["GEAR_STORAGE_EMPTY"] = "No better BoE / Warbound upgrades found for this character."
L["TOOLTIP_CHARACTER"] = CHARACTER or "Character"
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Location"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Achievement"
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Boss Drop"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Profession"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Quest"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Vendor"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "World Drop"
L["TYPE_MOUNT"] = MOUNT or "Mount"
L["TYPE_PET"] = PET or "Pet"
L["TYPE_TOY"] = TOY or "Toy"
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
L["VAULT_RAID"] = RAID or "Raid"
L["VAULT_SLOT_DUNGEON"] = DUNGEONS or "Dungeons"
L["VAULT_SLOT_RAIDS"] = RAIDS or "Raids"
L["VAULT_SLOT_SA"] = "Assignments"
L["TRACK_ACTIVITIES"] = "Track Activities"
L["VERSION"] = GAME_VERSION_LABEL or "Version"
L["FIRSTCRAFT"] = PROFESSIONS_FIRST_CRAFT or "First Craft"

-- Keybinding globals (must be global for WoW's keybinding UI)
BINDING_HEADER_WARBANDNEXUS = "Warband Nexus"
BINDING_NAME_WARBANDNEXUS_TOGGLE = "Show/hide main window"
