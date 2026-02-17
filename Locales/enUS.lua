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
L["VERSION"] = GAME_VERSION_LABEL or "Version"

-- Slash Commands
L["SLASH_HELP"] = "Available commands:"
L["SLASH_OPTIONS"] = "Open options panel"
L["SLASH_SCAN"] = "Scan Warband bank"
L["SLASH_SHOW"] = "Show/hide main window"
L["SLASH_DEPOSIT"] = "Open deposit queue"
L["SLASH_SEARCH"] = "Search for an item"

-- Options Panel - General
L["GENERAL_SETTINGS"] = "General Settings"
L["GENERAL_SETTINGS_DESC"] = "Configure general addon behavior"
L["ENABLE_ADDON"] = "Enable Addon"
L["ENABLE_ADDON_DESC"] = "Enable or disable Warband Nexus functionality"
L["MINIMAP_ICON"] = "Show Minimap Icon"
L["MINIMAP_ICON_DESC"] = "Show or hide the minimap button"
L["DEBUG_MODE"] = "Debug Logging"
L["DEBUG_MODE_DESC"] = "Output verbose debug messages to chat for troubleshooting"

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
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global: SEARCH
L["SEARCH_CATEGORY_FORMAT"] = "Search %s..."
L["BTN_SCAN"] = "Scan Bank"
L["BTN_DEPOSIT"] = "Deposit Queue"
L["BTN_SORT"] = "Sort Bank"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global: CLOSE
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global: SETTINGS
L["BTN_REFRESH"] = REFRESH -- Blizzard Global: REFRESH
L["BTN_CLEAR_QUEUE"] = "Clear Queue"
L["BTN_DEPOSIT_ALL"] = "Deposit All"
L["BTN_DEPOSIT_GOLD"] = "Deposit Gold"
L["ENABLE"] = ENABLE or "Enable" -- Blizzard Global
L["ENABLE_MODULE"] = "Enable Module"

-- Main Tabs (Blizzard Globals where available)
L["TAB_CHARACTERS"] = CHARACTER or "Characters" -- Blizzard Global
L["TAB_ITEMS"] = ITEMS or "Items" -- Blizzard Global
L["TAB_STORAGE"] = "Storage"
L["TAB_PLANS"] = "Plans"
L["TAB_REPUTATION"] = REPUTATION or "Reputation" -- Blizzard Global
L["TAB_REPUTATIONS"] = "Reputations"
L["TAB_CURRENCY"] = CURRENCY or "Currency" -- Blizzard Global
L["TAB_CURRENCIES"] = "Currencies"
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Statistics" -- Blizzard Global

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = ALL or "All Items" -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment" -- Blizzard Global
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables" -- Blizzard Global
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents" -- Blizzard Global
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods" -- Blizzard Global
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest Items" -- Blizzard Global
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous" -- Blizzard Global

-- Quality Filters (Using Blizzard Globals - automatically localized!)
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC -- Blizzard Global: "Poor"
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC -- Blizzard Global: "Common"
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC -- Blizzard Global: "Uncommon"
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC -- Blizzard Global: "Rare"
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC -- Blizzard Global: "Epic"
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC -- Blizzard Global: "Legendary"
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC -- Blizzard Global: "Artifact"
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC -- Blizzard Global: "Heirloom"

-- Characters Tab
L["HEADER_FAVORITES"] = FAVORITES or "Favorites" -- Blizzard Global
L["HEADER_CHARACTERS"] = CHARACTER or "Characters"
L["HEADER_CURRENT_CHARACTER"] = "CURRENT CHARACTER"
L["HEADER_WARBAND_GOLD"] = "WARBAND GOLD"
L["HEADER_TOTAL_GOLD"] = "TOTAL GOLD"
L["HEADER_REALM_GOLD"] = "REALM GOLD"
L["HEADER_REALM_TOTAL"] = "REALM TOTAL"
L["CHARACTER_LAST_SEEN_FORMAT"] = "Last seen: %s"
L["CHARACTER_GOLD_FORMAT"] = "Gold: %s"
L["CHARACTER_TOTAL_GOLD_TOOLTIP"] = "Combined gold from all characters on this realm"

-- Items Tab
L["ITEMS_HEADER"] = "Bank Items"
L["ITEMS_HEADER_DESC"] = "Browse and manage your Warband and Personal bank"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " items..."
L["ITEMS_WARBAND_BANK"] = "Warband Bank"
L["ITEMS_PLAYER_BANK"] = BANK or "Player Bank" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Guild Bank" -- Blizzard Global
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables"
L["GROUP_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession" -- Blizzard Global (auto-localized)
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
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
L["PLANS_MY_PLANS"] = "My Plans"
L["PLANS_COLLECTIONS"] = "Collection Plans"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Add Custom Plan"
L["PLANS_NO_RESULTS"] = "No results found."
L["PLANS_ALL_COLLECTED"] = "All items collected!"
L["PLANS_RECIPE_HELP"] = "Right-click recipes in your inventory to add them here."
L["COLLECTION_PLANS"] = "Collection Plans"
L["SEARCH_PLANS"] = "Search plans..."
L["COMPLETED_PLANS"] = "Completed Plans"
L["SHOW_COMPLETED"] = "Show Completed"

-- Plans Categories (Blizzard Globals where available)
L["CATEGORY_MY_PLANS"] = "My Plans"
L["CATEGORY_DAILY_TASKS"] = "Daily Tasks"
L["CATEGORY_MOUNTS"] = MOUNTS or "Mounts" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Pets" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Toys" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmog" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Illusions" -- No Blizzard global available; custom localization
L["CATEGORY_TITLES"] = TITLES or "Titles" -- Blizzard Global
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Achievements" -- Blizzard Global

-- Reputation Tab
L["REP_SEARCH_PLACEHOLDER"] = SEARCH .. " reputation..."
L["REP_HEADER_WARBAND"] = "Warband Reputation"
L["REP_HEADER_CHARACTER"] = "Character Reputation"
L["REP_STANDING_FORMAT"] = "Standing: %s"

-- Currency Tab
L["CURRENCY_SEARCH_PLACEHOLDER"] = SEARCH .. " currency..."
L["CURRENCY_HEADER_WARBAND"] = "Warband Transferable"
L["CURRENCY_HEADER_CHARACTER"] = "Character Bound"

-- PvE Tab
L["PVE_HEADER_RAIDS"] = RAIDS or "Raids" -- Blizzard Global
L["PVE_HEADER_DUNGEONS"] = DUNGEONS or "Dungeons" -- Blizzard Global
L["PVE_HEADER_DELVES"] = "Delves"
L["PVE_HEADER_WORLD_BOSS"] = "World Bosses"

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Statistics" -- Blizzard Global: STATISTICS
L["STATS_TOTAL_ITEMS"] = "Total Items"
L["STATS_TOTAL_SLOTS"] = "Total Slots"
L["STATS_FREE_SLOTS"] = "Free Slots"
L["STATS_USED_SLOTS"] = "Used Slots"
L["STATS_TOTAL_VALUE"] = "Total Value"
L["COLLECTED"] = "Collected"
L["TOTAL"] = "Total"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Character" -- Blizzard Global: CHARACTER
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Location" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Warband Bank"
L["TOOLTIP_TAB"] = "Tab"
L["TOOLTIP_SLOT"] = "Slot"
L["TOOLTIP_COUNT"] = "Count"
L["CHARACTER_INVENTORY"] = "Inventory"
L["CHARACTER_BANK"] = "Bank"

-- Try Counter
L["TRY_COUNT"] = "Try Count"
L["SET_TRY_COUNT"] = "Set Try Count"
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
L["ACHIEVEMENT_POINTS"] = "ACHIEVEMENT POINTS"
L["MOUNTS_COLLECTED"] = "MOUNTS COLLECTED"
L["BATTLE_PETS"] = "BATTLE PETS"
L["TOTAL_PETS"] = "Total Pets"
L["UNIQUE_PETS"] = "UNIQUE PETS"
L["ACCOUNT_WIDE"] = "Account-wide"
L["STORAGE_OVERVIEW"] = "Storage Overview"
L["WARBAND_SLOTS"] = "WARBAND SLOTS"
L["PERSONAL_SLOTS"] = "PERSONAL SLOTS"
L["TOTAL_FREE"] = "TOTAL FREE"
L["TOTAL_ITEMS"] = "TOTAL ITEMS"

-- Plans Tracker Window
L["WEEKLY_VAULT"] = "Weekly Vault"
L["CUSTOM"] = "Custom"
L["NO_PLANS_IN_CATEGORY"] = "No plans in this category.\nAdd plans from the Plans tab."
L["SOURCE_LABEL"] = "Source:"
L["ZONE_LABEL"] = "Zone:"
L["VENDOR_LABEL"] = "Vendor:"
L["DROP_LABEL"] = "Drop:"
L["REQUIREMENT_LABEL"] = "Requirement:"
L["RIGHT_CLICK_REMOVE"] = "Right-click to remove"
L["TRACKED"] = "Tracked"
L["TRACK"] = "Track"
L["TRACK_BLIZZARD_OBJECTIVES"] = "Track in Blizzard objectives (max 10)"
L["UNKNOWN"] = "Unknown"
L["NO_REQUIREMENTS"] = "No requirements (instant completion)"

-- Plans UI
L["NO_PLANNED_ACTIVITY"] = "No planned activity"
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

-- =============================================
-- Characters Tab
-- =============================================
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
L["DELETE_CHARACTER_TITLE"] = "Delete Character?"
L["THIS_CHARACTER"] = "this character"
L["DELETE_CHARACTER"] = "Delete Character"
L["REMOVE_FROM_TRACKING_FORMAT"] = "Remove %s from tracking"
L["CLICK_TO_DELETE"] = "Click to delete"
L["CONFIRM_DELETE"] = "Are you sure you want to delete |cff00ccff%s|r?"
L["CANNOT_UNDO"] = "This action cannot be undone!"
L["DELETE"] = DELETE or "Delete"
L["CANCEL"] = CANCEL or "Cancel"

-- =============================================
-- Items Tab
-- =============================================
L["PERSONAL_ITEMS"] = "Personal Items"
L["ITEMS_SUBTITLE"] = "Browse your Warband Bank and Personal Items (Bank + Inventory)"
L["ITEMS_DISABLED_TITLE"] = "Warband Bank Items"
L["ITEMS_LOADING"] = "Loading Inventory Data"
L["GUILD_BANK_REQUIRED"] = "You must be in a guild to access Guild Bank."
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

-- =============================================
-- Storage Tab
-- =============================================
L["STORAGE_DISABLED_TITLE"] = "Character Storage"
L["STORAGE_SEARCH"] = "Search storage..."

-- =============================================
-- PvE Tab
-- =============================================
L["PVE_TITLE"] = "PvE Progress"
L["PVE_SUBTITLE"] = "Great Vault, Raid Lockouts & Mythic+ across your Warband"
L["PVE_NO_CHARACTER"] = "No character data available"
L["LV_FORMAT"] = "Lv %d"
L["ILVL_FORMAT"] = "iLvl %d"
L["VAULT_RAID"] = RAID or "Raid" -- Blizzard Global
L["VAULT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon" -- Blizzard Global
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

-- =============================================
-- Reputation Tab
-- =============================================
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

-- =============================================
-- Currency Tab
-- =============================================
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

-- =============================================
-- Plans Tab (extended)
-- =============================================
L["REMOVE_COMPLETED_TOOLTIP"] = "Remove all completed plans from your My Plans list. This will delete all completed custom plans and remove completed mounts/pets/toys from your plans. This action cannot be undone!"
L["RECIPE_BROWSER_DESC"] = "Open your Profession window in-game to browse recipes.\nThe addon will scan available recipes when the window is open."
-- Format: "Source: |cff00ff00[Achievement %s]|r" - uses localized SOURCE_LABEL and SOURCE_TYPE_ACHIEVEMENT
L["SOURCE_ACHIEVEMENT_FORMAT"] = "%s |cff00ff00[%s %s]|r"
L["WEEKLY_PLAN_EXISTS_DESC"] = "%s already has an active weekly vault plan. You can find it in the 'My Plans' category."
L["DAILY_PLAN_EXISTS_DESC"] = "%s already has an active daily quest plan. You can find it in the 'Daily Tasks' category."
L["TRANSMOG_WIP_DESC"] = "Transmog collection tracking is currently under development.\n\nThis feature will be available in a future update with improved\nperformance and better integration with Warband systems."
L["WEEKLY_VAULT_CARD"] = "Weekly Vault Card"
L["WEEKLY_VAULT_COMPLETE"] = "Weekly Vault Card - Complete"
L["UNKNOWN_SOURCE"] = "Unknown source"
L["DAILY_TASKS_PREFIX"] = "Daily Tasks - "
L["NO_FOUND_FORMAT"] = "No %ss found"
L["PLANS_COUNT_FORMAT"] = "%d plans"
L["PET_BATTLE_LABEL"] = "Pet Battle:"
L["QUEST_LABEL"] = "Quest:"

-- =============================================
-- Settings Tab
-- =============================================
L["CURRENT_LANGUAGE"] = "Current Language:"
L["LANGUAGE_TOOLTIP"] = "Addon uses your WoW game client's language automatically. To change, update your Battle.net settings."
L["POPUP_DURATION"] = "Popup Duration"
L["POPUP_POSITION"] = "Popup Position"
L["SET_POSITION"] = "Set Position"
L["DRAG_TO_POSITION"] = "Drag to position\nRight-click to confirm"
L["RESET_DEFAULT"] = "Reset Default"
L["TEST_POPUP"] = "Test Popup"
L["CUSTOM_COLOR"] = "Custom Color"
L["OPEN_COLOR_PICKER"] = "Open Color Picker"
L["COLOR_PICKER_TOOLTIP"] = "Open WoW's native color picker wheel to choose a custom theme color"
L["PRESET_THEMES"] = "Preset Themes"
L["WARBAND_NEXUS_SETTINGS"] = "Warband Nexus Settings"
L["NO_OPTIONS"] = "No Options"
L["NONE_LABEL"] = NONE or "None"
L["TAB_FILTERING"] = "Tab Filtering"
L["NOTIFICATIONS_LABEL"] = NOTIFICATIONS or "Notifications"
L["SCROLL_SPEED"] = "Scroll Speed"
L["ANCHOR_FORMAT"] = "Anchor: %s  |  X: %d  |  Y: %d"
L["SHOW_WEEKLY_PLANNER"] = "Weekly Planner (Characters)"
L["LOCK_MINIMAP_ICON"] = "Lock Minimap Button"
L["SHOW_TOOLTIP_ITEM_COUNT"] = "Show Items in Tooltips"
L["AUTO_SCAN_ITEMS"] = "Auto-Scan Items"
L["LIVE_SYNC"] = "Live Sync"
L["BACKPACK_LABEL"] = "Backpack"
L["REAGENT_LABEL"] = "Reagent"

-- =============================================
-- Shared Widgets & Dialogs
-- =============================================
L["MODULE_DISABLED"] = "Module Disabled"
L["LOADING"] = "Loading..."
L["PLEASE_WAIT"] = "Please wait..."
L["RESET_PREFIX"] = "Reset:"
L["TRANSFER_CURRENCY"] = "Transfer Currency"
L["AMOUNT_LABEL"] = "Amount:"
L["TO_CHARACTER"] = "To Character:"
L["SELECT_CHARACTER"] = "Select character..."
L["CURRENCY_TRANSFER_INFO"] = "Currency window will be opened automatically.\nYou'll need to manually right-click the currency to transfer."
L["OK_BUTTON"] = OKAY or "OK"
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

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = PLAYER_DIFFICULTY6 or "Mythic" -- Blizzard Global
L["DIFFICULTY_HEROIC"] = PLAYER_DIFFICULTY2 or "Heroic" -- Blizzard Global
L["DIFFICULTY_NORMAL"] = PLAYER_DIFFICULTY1 or "Normal" -- Blizzard Global
L["DIFFICULTY_LFR"] = "LFR" -- No matching Blizzard global (PLAYER_DIFFICULTY3 = "10 Player")
L["TIER_FORMAT"] = "Tier %d"
L["PVP_TYPE"] = PVP or "PvP" -- Blizzard Global
L["PREPARING"] = "Preparing"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Account Statistics"
L["STATISTICS_SUBTITLE"] = "Collection progress, gold, and storage overview"
L["MOST_PLAYED"] = "MOST PLAYED"
L["PLAYED_DAYS"] = "Days"
L["PLAYED_HOURS"] = "Hours"
L["PLAYED_MINUTES"] = "Minutes"
L["PLAYED_DAY"] = "Day"
L["PLAYED_HOUR"] = "Hour"
L["PLAYED_MINUTE"] = "Minute"
L["MORE_CHARACTERS"] = "more character"
L["MORE_CHARACTERS_PLURAL"] = "more characters"

-- =============================================
-- Information Dialog (extended)
-- =============================================
L["WELCOME_TITLE"] = "Welcome to Warband Nexus!"
L["ADDON_OVERVIEW_TITLE"] = "AddOn Overview"

-- =============================================
-- Plans UI (extended)
-- =============================================
L["PLANS_SUBTITLE_TEXT"] = "Track your collection goals"
L["ACTIVE_PLAN_FORMAT"] = "%d active plan"
L["ACTIVE_PLANS_FORMAT"] = "%d active plans"
L["RESET_LABEL"] = RESET or "Reset"

-- Plans - Type Names (Using Blizzard Globals where available)
L["TYPE_MOUNT"] = MOUNT or "Mount" -- Blizzard Global
L["TYPE_PET"] = PET or "Pet" -- Blizzard Global
L["TYPE_TOY"] = TOY or "Toy" -- Blizzard Global
L["TYPE_RECIPE"] = "Recipe"
L["TYPE_ILLUSION"] = "Illusion"
L["TYPE_TITLE"] = "Title"
L["TYPE_CUSTOM"] = "Custom"
L["TYPE_TRANSMOG"] = TRANSMOGRIFY or "Transmog" -- Blizzard Global

-- Plans - Source Type Labels (Using Blizzard BATTLE_PET_SOURCE_* Globals for auto-localization)
L["SOURCE_TYPE_DROP"] = BATTLE_PET_SOURCE_1 or "Drop"
L["SOURCE_TYPE_QUEST"] = BATTLE_PET_SOURCE_2 or "Quest"
L["SOURCE_TYPE_VENDOR"] = BATTLE_PET_SOURCE_3 or "Vendor"
L["SOURCE_TYPE_PROFESSION"] = BATTLE_PET_SOURCE_4 or "Profession"
L["SOURCE_TYPE_PET_BATTLE"] = BATTLE_PET_SOURCE_5 or "Pet Battle"
L["SOURCE_TYPE_ACHIEVEMENT"] = BATTLE_PET_SOURCE_6 or "Achievement"
L["SOURCE_TYPE_WORLD_EVENT"] = BATTLE_PET_SOURCE_7 or "World Event"
L["SOURCE_TYPE_PROMOTION"] = BATTLE_PET_SOURCE_8 or "Promotion"
L["SOURCE_TYPE_TRADING_CARD"] = BATTLE_PET_SOURCE_9 or "Trading Card Game"
L["SOURCE_TYPE_IN_GAME_SHOP"] = BATTLE_PET_SOURCE_10 or "In-Game Shop"
L["SOURCE_TYPE_CRAFTED"] = BATTLE_PET_SOURCE_4 or "Crafted"
L["SOURCE_TYPE_TRADING_POST"] = "Trading Post"
L["SOURCE_TYPE_UNKNOWN"] = UNKNOWN or "Unknown"
L["SOURCE_TYPE_PVP"] = PVP or "PvP"
L["SOURCE_TYPE_TREASURE"] = "Treasure"
L["SOURCE_TYPE_PUZZLE"] = "Puzzle"
L["SOURCE_TYPE_RENOWN"] = "Renown"

-- Plans - Transmog Source Labels (Blizzard TRANSMOG_SOURCE_* Globals)
L["TRANSMOG_SOURCE_BOSS_DROP"] = TRANSMOG_SOURCE_1 or "Boss Drop"
L["TRANSMOG_SOURCE_QUEST"] = TRANSMOG_SOURCE_2 or "Quest"
L["TRANSMOG_SOURCE_VENDOR"] = TRANSMOG_SOURCE_3 or "Vendor"
L["TRANSMOG_SOURCE_WORLD_DROP"] = TRANSMOG_SOURCE_4 or "World Drop"
L["TRANSMOG_SOURCE_ACHIEVEMENT"] = TRANSMOG_SOURCE_5 or "Achievement"
L["TRANSMOG_SOURCE_PROFESSION"] = TRANSMOG_SOURCE_6 or "Profession"

-- Plans - Source Text Parsing Keywords (for matching API-localized source descriptions)
-- These MUST use Blizzard globals so they match the localized text returned by WoW APIs
L["PARSE_SOLD_BY"] = "Sold by"
L["PARSE_CRAFTED"] = "Crafted"
L["PARSE_ZONE"] = ZONE or "Zone"
L["PARSE_COST"] = "Cost"
L["PARSE_REPUTATION"] = REPUTATION or "Reputation"
L["PARSE_FACTION"] = FACTION or "Faction"
L["PARSE_ARENA"] = ARENA or "Arena"
L["PARSE_DUNGEON"] = DUNGEONS or "Dungeon"
L["PARSE_RAID"] = RAID or "Raid"
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
L["PARSE_DROP"] = BATTLE_PET_SOURCE_1 or "Drop"
L["PARSE_NPC"] = "NPC"
L["PARSE_FROM_ACHIEVEMENT"] = "From Achievement"
L["FALLBACK_UNKNOWN_PET"] = "Unknown Pet"

-- Plans - Fallback Labels (for CollectionService defaults)
L["FALLBACK_PET_COLLECTION"] = "Pet Collection"
L["FALLBACK_TOY_COLLECTION"] = "Toy Collection"
L["FALLBACK_TRANSMOG_COLLECTION"] = "Transmog Collection"
L["FALLBACK_PLAYER_TITLE"] = "Player Title"
L["FALLBACK_UNKNOWN_SOURCE"] = UNKNOWN or "Unknown"
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
L["PROGRESS_ON_FORMAT"] = "You are %d/%d on the progress"
L["COMPLETED_REQ_FORMAT"] = "You completed %d of %d total requirements"

-- Plans - Content & Quest Types
L["CONTENT_MIDNIGHT"] = "Midnight"
L["CONTENT_TWW"] = "The War Within"
L["QUEST_TYPE_DAILY"] = "Daily Quests"
L["QUEST_TYPE_DAILY_DESC"] = "Regular daily quests from NPCs"
L["QUEST_TYPE_WORLD"] = "World Quests"
L["QUEST_TYPE_WORLD_DESC"] = "Zone-wide world quests"
L["QUEST_TYPE_WEEKLY"] = "Weekly Quests"
L["QUEST_TYPE_WEEKLY_DESC"] = "Weekly recurring quests"
L["QUEST_TYPE_ASSIGNMENTS"] = "Assignments"
L["QUEST_TYPE_ASSIGNMENTS_DESC"] = "Special assignments and tasks"

-- Plans - Weekly Vault Progress
L["MYTHIC_PLUS_LABEL"] = "Mythic+"
L["RAIDS_LABEL"] = RAIDS or "Raids" -- Blizzard Global

-- PlanCardFactory
L["FACTION_LABEL"] = "Faction:"
L["FRIENDSHIP_LABEL"] = "Friendship"
L["RENOWN_TYPE_LABEL"] = "Renown"
L["ADD_BUTTON"] = "+ Add"
L["ADDED_LABEL"] = "Added"

-- PlansTrackerWindow
L["ACHIEVEMENT_PROGRESS_FORMAT"] = "%s of %s (%s%%)"

-- =============================================
-- Settings - General Tooltips
-- =============================================
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Display stack counts on items in the storage and items view"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Show or hide the Weekly Planner section inside the Characters tab"
L["LOCK_MINIMAP_TOOLTIP"] = "Lock the minimap button in place so it cannot be dragged"
L["SHOW_TOOLTIP_ITEM_COUNT_TOOLTIP"] = "Display Warband and Character item counts in tooltips (WN Search)."
L["AUTO_SCAN_TOOLTIP"] = "Automatically scan and cache items when you open banks or bags"
L["LIVE_SYNC_TOOLTIP"] = "Keep item cache updated in real-time while banks are open"
L["SHOW_ILVL_TOOLTIP"] = "Display item level badges on equipment in the item list"
L["SCROLL_SPEED_TOOLTIP"] = "Multiplier for scroll speed (1.0x = 28 px per step)"

-- =============================================
-- Settings - Tab Filtering
-- =============================================
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignore Warband Bank Tab %d from automatic scanning"
L["IGNORE_SCAN_FORMAT"] = "Ignore %s from automatic scanning"
L["BANK_LABEL"] = BANK or "Bank"

-- =============================================
-- Settings - Notifications
-- =============================================
L["ENABLE_NOTIFICATIONS"] = "Enable All Notifications"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Master toggle — disables all popup notifications, chat alerts, and visual effects below"
L["VAULT_REMINDER"] = "Weekly Vault Reminder"
L["VAULT_REMINDER_TOOLTIP"] = "Show a reminder popup on login when you have unclaimed Great Vault rewards"
L["LOOT_ALERTS"] = "New Collectible Popup"
L["LOOT_ALERTS_TOOLTIP"] = "Show a popup when a NEW mount, pet, toy, or achievement enters your collection. Also controls the try counter and screen flash below."
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Replace Achievement Popup"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Replace Blizzard's default achievement popup with the Warband Nexus notification style"
L["REPUTATION_GAINS"] = "Rep Gains in Chat"
L["REPUTATION_GAINS_TOOLTIP"] = "Display reputation gain messages in chat when you earn faction standing"
L["CURRENCY_GAINS"] = "Currency Gains in Chat"
L["CURRENCY_GAINS_TOOLTIP"] = "Display currency gain messages in chat when you earn currencies"
L["SCREEN_FLASH_EFFECT"] = "Flash on Rare Drop"
L["SCREEN_FLASH_EFFECT_TOOLTIP"] = "Play a screen flash animation when you finally obtain a collectible after multiple farming attempts"
L["AUTO_TRY_COUNTER"] = "Auto-Track Drop Attempts"
L["AUTO_TRY_COUNTER_TOOLTIP"] = "Automatically count failed drop attempts when looting NPCs, rares, bosses, fishing, or containers. Shows total attempt count in the popup when the collectible finally drops."
L["DURATION_LABEL"] = "Duration"
L["DAYS_LABEL"] = "days"
L["WEEKS_LABEL"] = "weeks"
L["EXTEND_DURATION"] = "Extend Duration"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Drag the green frame to set popup position. Right-click to confirm."
L["POSITION_RESET_MSG"] = "Popup position reset to default (Top Center)"
L["POSITION_SAVED_MSG"] = "Popup position saved!"
L["TEST_NOTIFICATION_TITLE"] = "Test Notification"
L["TEST_NOTIFICATION_MSG"] = "Position test"
L["NOTIFICATION_DEFAULT_TITLE"] = "Notification"

-- =============================================
-- Settings - Theme & Appearance
-- =============================================
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

-- =============================================
-- Settings - Font
-- =============================================
L["FONT_FAMILY"] = "Font Family"
L["FONT_FAMILY_TOOLTIP"] = "Choose the font used throughout the addon UI"
L["FONT_SCALE"] = "Font Scale"
L["FONT_SCALE_TOOLTIP"] = "Adjust font size across all UI elements"
L["ANTI_ALIASING"] = "Anti-Aliasing"
L["ANTI_ALIASING_DESC"] = "Font edge rendering style (affects readability)"
L["FONT_SCALE_WARNING"] = "Warning: Higher font scale may cause text overflow in some UI elements."
L["RESOLUTION_NORMALIZATION"] = "Auto-Scale for Resolution"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Automatically adjust font sizes based on your screen resolution and UI scale so text appears the same physical size across different monitors"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Advanced"

-- =============================================
-- Settings - Module Management
-- =============================================
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
L["MODULE_PLANS"] = "Plans"
L["MODULE_PLANS_DESC"] = "Track personal goals for mounts, pets, toys, achievements, and custom tasks"
L["MODULE_PROFESSIONS"] = "Professions"
L["MODULE_PROFESSIONS_DESC"] = "Track profession skills, concentration, knowledge, and recipe companion window"
L["PROFESSIONS_DISABLED_TITLE"] = "Professions"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Item Level %s"
L["ITEM_NUMBER_FORMAT"] = "Item #%s"
L["CHARACTER_CURRENCIES"] = "Character Currencies:"
L["CURRENCY_ACCOUNT_WIDE_NOTE"] = "Account-wide (Warband) — same balance on all characters."
L["YOU_MARKER"] = "(You)"
L["WN_SEARCH"] = "WN Search"
L["WARBAND_BANK_COLON"] = "Warband Bank:"
L["AND_MORE_FORMAT"] = "... and %d more"

-- =============================================
-- Notification Manager
-- =============================================
L["COLLECTED_MOUNT_MSG"] = "You have collected a mount"
L["COLLECTED_PET_MSG"] = "You have collected a battle pet"
L["COLLECTED_TOY_MSG"] = "You have collected a toy"
L["COLLECTED_ILLUSION_MSG"] = "You have collected an illusion"
L["COLLECTED_ITEM_MSG"] = "You received a rare drop"
L["ACHIEVEMENT_COMPLETED_MSG"] = "Achievement completed!"
L["EARNED_TITLE_MSG"] = "You have earned a title"
L["COMPLETED_PLAN_MSG"] = "You have completed a plan"
L["DAILY_QUEST_CAT"] = "Daily Quest"
L["WORLD_QUEST_CAT"] = "World Quest"
L["WEEKLY_QUEST_CAT"] = "Weekly Quest"
L["SPECIAL_ASSIGNMENT_CAT"] = "Special Assignment"
L["DELVE_CAT"] = "Delve"
L["DUNGEON_CAT"] = LFG_TYPE_DUNGEON or "Dungeon" -- Blizzard Global
L["RAID_CAT"] = RAID or "Raid" -- Blizzard Global
L["WORLD_CAT"] = "World"
L["ACTIVITY_CAT"] = "Activity"
L["PROGRESS_COUNT_FORMAT"] = "%d/%d Progress"
L["PROGRESS_COMPLETED_FORMAT"] = "%d/%d Progress Completed"
L["WEEKLY_VAULT_PLAN_FORMAT"] = "Weekly Vault Plan - %s"
L["ALL_SLOTS_COMPLETE"] = "All Slots Complete!"
L["QUEST_COMPLETED_SUFFIX"] = "Completed"
L["WEEKLY_VAULT_READY"] = "Weekly Vault Ready!"
L["UNCLAIMED_REWARDS"] = "You have unclaimed rewards"

-- =============================================
-- Minimap Button
-- =============================================
L["TOTAL_GOLD_LABEL"] = "Total Gold:"
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

-- =============================================
-- SharedWidgets (extended)
-- =============================================
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

-- =============================================
-- Information Dialog - Tab Headers
-- =============================================
L["INFO_TAB_CHARACTERS"] = "Characters"
L["INFO_TAB_ITEMS"] = "Items"
L["INFO_TAB_STORAGE"] = "Storage"
L["INFO_TAB_PVE"] = "PvE"
L["INFO_TAB_REPUTATIONS"] = "Reputations"
L["INFO_TAB_CURRENCY"] = "Currency"
L["INFO_TAB_PLANS"] = "Plans"
L["INFO_TAB_STATISTICS"] = "Statistics"
L["SPECIAL_THANKS"] = "Special Thanks"
L["SUPPORTERS_TITLE"] = "Supporters"
L["CONTRIBUTORS_TITLE"] = "Contributors"
L["THANK_YOU_MSG"] = "Thank you for using Warband Nexus!"

-- Information Dialog - Professions Tab
L["INFO_TAB_PROFESSIONS"] = "Professions"
L["PROFESSIONS_INFO_DESC"] = "Track profession skills, concentration, knowledge, and specialization trees across all characters. Includes Recipe Companion for reagent sourcing."

-- =============================================
-- Command Help Strings
-- =============================================
L["AVAILABLE_COMMANDS"] = "Available commands:"
L["CMD_OPEN"] = "Open addon window"
L["CMD_PLANS"] = "Toggle Plans Tracker window"
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

-- =============================================
-- Welcome Messages
-- =============================================
L["CLICK_TO_COPY"] = "Click to copy invite link"
L["COPIED_LABEL"] = "Copied!"

L["WELCOME_MSG_FORMAT"] = "Welcome to Warband Nexus v%s"
L["WELCOME_TYPE_CMD"] = "Please type"
L["WELCOME_OPEN_INTERFACE"] = "to open the interface."

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "NEW FEATURES:\n" ..
    "- Character Tracking: Choose which characters to track or untrack.\n" ..
    "- Smart Currency & Reputation Tracking: Real-time chat notifications with progress.\n" ..
    "- Mount Try Counter: Track your drop attempts (Work in Progress).\n" ..
    "- Inventory + Bank + Warband Bank Tracking: Track items across all storage.\n" ..
    "- Tooltip System: Brand new custom tooltip framework.\n" ..
    "- Tooltip Item Tracker: See which characters own an item on hover.\n" ..
    "- Plans Tab: Track your next goals — mounts, pets, toys, achievements, transmogs.\n" ..
    "- Plans Window: Quick access via /wn plan or right-click the minimap icon.\n" ..
    "- Smart Account Data Tracking: Automatic warband-wide data synchronization.\n" ..
    "- Localization: 11 languages supported.\n" ..
    "- Reputation & Currency Comparison: Hover tooltips show per-character breakdown.\n" ..
    "- Notification System: Loot, achievement, and vault reminders.\n" ..
    "- Custom Font System: Choose your preferred font and scaling.\n" ..
    "\n" ..
    "IMPROVEMENTS:\n" ..
    "- Character data: Faction, Race, iLvl, and Keystone info added.\n" ..
    "- Bank UI disabled (replaced by improved Storage).\n" ..
    "- Personal Items: Tracks your bank + inventory.\n" ..
    "- Storage: Tracks bank + inventory + warband bank across all characters.\n" ..
    "- PvE: Vault tier indicator, dungeon score/key tracker, affix display, upgrade currency.\n" ..
    "- Reputation tab: Simplified view (removed old filter system).\n" ..
    "- Currency tab: Simplified view (removed old filter system).\n" ..
    "- Statistics: Added Unique Pet counter.\n" ..
    "- Settings: Revised and reorganized.\n" ..
    "\n" ..
    "Thank you for your patience and interest.\n" ..
    "\n" ..
    "To report issues or share feedback, leave a comment on CurseForge - Warband Nexus."

-- =============================================
-- Changelog (What's New) - v2.1.0
-- =============================================
L["CHANGELOG_V210"] = "NEW FEATURES:\n" ..
    "- Professions Tab: Track profession skills, concentration, knowledge, and specialization trees across all characters.\n" ..
    "- Recipe Companion Window: Browse and track recipes with reagent sources from your Warband Bank.\n" ..
    "- Loading Overlay: Visual progress indicator during data synchronization.\n" ..
    "- Persistent Notification Deduplication: Collectible notifications no longer repeat across sessions.\n" ..
    "\n" ..
    "IMPROVEMENTS:\n" ..
    "- Performance: Significantly reduced login FPS drops with time-budgeted initialization.\n" ..
    "- Performance: Removed Encounter Journal scan to eliminate frame spikes.\n" ..
    "- PvE: Alt character data now correctly persists and displays across characters.\n" ..
    "- PvE: Great Vault data saved on logout to prevent async data loss.\n" ..
    "- Currency: Hierarchical header display matching Blizzard's native UI (Legacy, Season grouping).\n" ..
    "- Currency: Faster initial data population.\n" ..
    "- Notifications: Suppressed alerts for non-farmable items (quest rewards, vendor items).\n" ..
    "- Settings: Window now reuses frames and no longer drifts the main window on close.\n" ..
    "- Character Tracking: Data collection fully gated behind tracking confirmation.\n" ..
    "- Characters: Profession rows now display for characters without professions.\n" ..
    "- UI: Improved text spacing (X : Y format) across all displays.\n" ..
    "\n" ..
    "BUG FIXES:\n" ..
    "- Fixed recurring loot notification for already-owned collectibles on every login.\n" ..
    "- Fixed ESC menu becoming disabled after deleting a character.\n" ..
    "- Fixed main window anchor shifting when Settings is closed with ESC.\n" ..
    "- Fixed \"Most Played\" displaying characters incorrectly.\n" ..
    "- Fixed Great Vault data not showing for alt characters.\n" ..
    "- Fixed realm names displaying without spaces.\n" ..
    "- Fixed tooltip collectible info not showing on first hover.\n" ..
    "\n" ..
    "Thank you for your continued support!\n" ..
    "\n" ..
    "To report issues or share feedback, leave a comment on CurseForge - Warband Nexus."

-- =============================================
-- Confirm / Tracking Dialog
-- =============================================
L["CONFIRM_ACTION"] = "Confirm Action"
L["CONFIRM"] = "Confirm"
L["ENABLE_TRACKING_FORMAT"] = "Enable tracking for |cffffcc00%s|r?"
L["DISABLE_TRACKING_FORMAT"] = "Disable tracking for |cffffcc00%s|r?"

-- =============================================
-- Reputation Section Headers
-- =============================================
L["REP_SECTION_ACCOUNT_WIDE"] = "Account-Wide Reputations (%s)"
L["REP_SECTION_CHARACTER_BASED"] = "Character-Based Reputations (%s)"

-- =============================================
-- Reputation Processor Labels
-- =============================================
L["REP_REWARD_WAITING"] = "Reward Waiting"
L["REP_PARAGON_LABEL"] = "Paragon"

-- =============================================
-- Reputation Loading States
-- =============================================
L["REP_LOADING_PREPARING"] = "Preparing..."
L["REP_LOADING_INITIALIZING"] = "Initializing..."
L["REP_LOADING_FETCHING"] = "Fetching reputation data..."
L["REP_LOADING_PROCESSING"] = "Processing %d factions..."
L["REP_LOADING_PROCESSING_COUNT"] = "Processing... (%d/%d)"
L["REP_LOADING_SAVING"] = "Saving to database..."
L["REP_LOADING_COMPLETE"] = "Complete!"

-- =============================================
-- Gold Transfer
-- =============================================
L["GOLD_TRANSFER"] = "Gold Transfer"
L["GOLD_LABEL"] = "Gold"
L["SILVER_LABEL"] = "Silver"
L["COPPER_LABEL"] = "Copper"
L["DEPOSIT"] = "Deposit"
L["WITHDRAW"] = "Withdraw"
L["DEPOSIT_TO_WARBAND"] = "Deposit to Warband Bank"
L["WITHDRAW_FROM_WARBAND"] = "Withdraw from Warband Bank"
L["YOUR_GOLD_FORMAT"] = "Your Gold: %s"
L["WARBAND_BANK_FORMAT"] = "Warband Bank: %s"
L["NOT_ENOUGH_GOLD"] = "Not enough gold available."
L["ENTER_AMOUNT"] = "Please enter an amount."
L["ONLY_WARBAND_GOLD"] = "Only Warband Bank supports gold transfer."

-- =============================================
-- Status / Footer
-- =============================================
L["COMBAT_LOCKDOWN_MSG"] = "Cannot open window during combat. Please try again after combat ends."
L["BANK_IS_ACTIVE"] = "Bank is Active"
L["ITEMS_CACHED_FORMAT"] = "%d items cached"
L["UP_TO_DATE"] = "Up-to-Date"
L["NEVER_SCANNED"] = "Never Scanned"

-- =============================================
-- Table Headers (SharedWidgets)
-- =============================================
L["TABLE_HEADER_CHARACTER"] = "CHARACTER"
L["TABLE_HEADER_LEVEL"] = "LEVEL"
L["TABLE_HEADER_GOLD"] = "GOLD"
L["TABLE_HEADER_LAST_SEEN"] = "LAST SEEN"

-- =============================================
-- Search / Empty States
-- =============================================
L["NO_ITEMS_MATCH"] = "No items match '%s'"
L["NO_ITEMS_MATCH_GENERIC"] = "No items match your search"
L["ITEMS_SCAN_HINT"] = "Items are scanned automatically. Try /reload if nothing appears."
L["ITEMS_WARBAND_BANK_HINT"] = "Open Warband Bank to scan items (auto-scanned on first visit)"

-- =============================================
-- Currency Transfer Steps
-- =============================================
L["CURRENCY_TRANSFER_NEXT_STEPS"] = "Next steps:"
L["CURRENCY_TRANSFER_STEP_1"] = "Find |cffffffff%s|r in the Currency window"
L["CURRENCY_TRANSFER_STEP_2"] = "|cffff8800Right-click|r on it"
L["CURRENCY_TRANSFER_STEP_3"] = "Select |cffffffff'Transfer to Warband'|r"
L["CURRENCY_TRANSFER_STEP_4"] = "Choose |cff00ff00%s|r"
L["CURRENCY_TRANSFER_STEP_5"] = "Enter amount: |cffffffff%s|r"
L["CURRENCY_WINDOW_OPENED"] = "Currency window is now open!"
L["CURRENCY_TRANSFER_SECURITY"] = "(Blizzard security prevents automatic transfer)"

-- =============================================
-- Plans UI Extra
-- =============================================
L["ZONE_PREFIX"] = "Zone: "
L["ADDED"] = "Added"
L["WEEKLY_VAULT_TRACKER"] = "Weekly Vault Tracker"
L["DAILY_QUEST_TRACKER"] = "Daily Quest Tracker"
L["CUSTOM_PLAN_STATUS"] = "Custom plan '%s' %s"

-- =============================================
-- PlanCardFactory Vault Slots
-- =============================================
L["VAULT_SLOT_DUNGEON"] = LFG_TYPE_DUNGEON or "Dungeon" -- Blizzard Global
L["VAULT_SLOT_RAIDS"] = RAIDS or "Raids" -- Blizzard Global
L["VAULT_SLOT_WORLD"] = "World"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Affix"

-- =============================================
-- Chat Messages
-- =============================================
-- Chat messages are now formatted directly in ChatMessageService.lua with
-- rarity-colored currency hyperlinks, standing-colored faction names,
-- gold gain amounts, white totals, and gray max values.
-- Locale keys kept for reference but formatting is code-driven.
L["CHAT_REP_STANDING_LABEL"] = "Now"
L["CHAT_GAINED_PREFIX"] = "+"

-- =============================================
-- PlansManager Messages
-- =============================================
L["PLAN_COMPLETED"] = "Plan completed: "
L["WEEKLY_VAULT_PLAN_NAME"] = "Weekly Vault - %s"
L["VAULT_PLANS_RESET"] = "Weekly Great Vault plans have been reset! (%d plan%s)"

-- =============================================
-- Empty State Cards
-- =============================================
L["EMPTY_CHARACTERS_TITLE"] = "No Characters Found"
L["EMPTY_CHARACTERS_DESC"] = "Log in to your characters to start tracking them.\nCharacter data is collected automatically on each login."
L["EMPTY_ITEMS_TITLE"] = "No Items Cached"
L["EMPTY_ITEMS_DESC"] = "Open your Warband Bank or Personal Bank to scan items.\nItems are cached automatically on first visit."
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

-- =============================================
-- Character Tracking & Commands
-- =============================================
L["TRACK_CHARACTER_QUESTION"] = "Do you want to track this character?"
L["CLEANUP_NO_INACTIVE"] = "No inactive characters found (90+ days)"
L["CLEANUP_REMOVED_FORMAT"] = "Removed %d inactive character(s)"
L["TRACKING_ENABLED_MSG"] = "Character tracking ENABLED!"
L["TRACKING_DISABLED_MSG"] = "Character tracking DISABLED!"
L["TRACKING_ENABLED"] = "Tracking ENABLED"
L["TRACKING_DISABLED"] = "Tracking DISABLED (read-only mode)"
L["STATUS_LABEL"] = "Status:"
L["ERROR_LABEL"] = "Error:"
L["ERROR_NAME_REALM_REQUIRED"] = "Character name and realm required"
L["ERROR_WEEKLY_PLAN_EXISTS"] = "%s-%s already has an active weekly plan"

-- Profiles (AceDB)
L["PROFILES"] = "Profiles"
L["PROFILES_DESC"] = "Manage addon profiles"

-- =============================================
-- Achievement/Criteria Display
-- =============================================
L["NO_CRITERIA_FOUND"] = "No criteria found"
L["NO_REQUIREMENTS_INSTANT"] = "No requirements (instant completion)"

-- =============================================
-- Transmog Slot Names (Blizzard INVTYPE_* Globals)
-- =============================================
L["SLOT_HEAD"] = INVTYPE_HEAD or "Head"
L["SLOT_SHOULDER"] = INVTYPE_SHOULDER or "Shoulder"
L["SLOT_BACK"] = INVTYPE_CLOAK or "Back"
L["SLOT_CHEST"] = INVTYPE_CHEST or "Chest"
L["SLOT_SHIRT"] = INVTYPE_BODY or "Shirt"
L["SLOT_TABARD"] = INVTYPE_TABARD or "Tabard"
L["SLOT_WRIST"] = INVTYPE_WRIST or "Wrist"
L["SLOT_HANDS"] = INVTYPE_HAND or "Hands"
L["SLOT_WAIST"] = INVTYPE_WAIST or "Waist"
L["SLOT_LEGS"] = INVTYPE_LEGS or "Legs"
L["SLOT_FEET"] = INVTYPE_FEET or "Feet"
L["SLOT_MAINHAND"] = INVTYPE_WEAPONMAINHAND or "Main Hand"
L["SLOT_OFFHAND"] = INVTYPE_WEAPONOFFHAND or "Off Hand"

-- =============================================
-- Professions Tab
-- =============================================
L["TAB_PROFESSIONS"] = "Professions"
L["YOUR_PROFESSIONS"] = "Warband Professions"
L["PROFESSIONS_TRACKED_FORMAT"] = "%s characters with professions"
L["HEADER_PROFESSIONS"] = "Professions Overview"
L["NO_PROFESSIONS_DATA"] = "No profession data available yet. Open your profession window (default: K) on each character to collect data."
L["CONCENTRATION"] = "Concentration"
L["KNOWLEDGE"] = "Knowledge"
L["SKILL"] = "Skill"
L["RECIPES"] = "Recipes"
L["UNSPENT_POINTS"] = "Unspent Points"
L["COLLECTIBLE"] = "Collectible"
L["RECHARGE"] = "Recharge"
L["FULL"] = "Full"
L["PROF_OPEN_RECIPE"] = "Open"
L["PROF_OPEN_RECIPE_TOOLTIP"] = "Open this profession's recipe list"
L["PROF_ONLY_CURRENT_CHAR"] = "Only available for the current character"
L["NO_PROFESSION"] = "No Profession"

-- Professions: Column Headers
L["FIRST_CRAFT"] = "1st Craft"
L["SKILL_UPS"] = "Skill Ups"
L["COOLDOWNS"] = "Cooldowns"
L["ORDERS"] = "Orders"

-- Professions: Tooltips & Details
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

-- Track Item DB
L["TRACK_ITEM_DB"] = "Track Item DB"
L["TRACK_ITEM_DB_DESC"] = "Manage which collectible drops to track. Toggle built-in entries or add custom sources."
L["MANAGE_ITEMS"] = "Item Tracking"
L["SELECT_ITEM"] = "Select Item"
L["SELECT_ITEM_DESC"] = "Choose a collectible to manage."
L["SELECT_ITEM_HINT"] = "Select an item above to view details."
L["REPEATABLE_LABEL"] = "Repeatable"
L["YES"] = "Yes"
L["NO"] = "No"
L["SOURCE_SINGULAR"] = "source"
L["SOURCE_PLURAL"] = "sources"
L["TRACKED"] = "Tracked"
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

-- =============================================
-- Recipe Companion
-- =============================================
L["RECIPE_COMPANION_TITLE"] = "Recipe Companion"
L["SELECT_RECIPE"] = "Select a recipe"
L["CRAFTERS_SECTION"] = "Crafters"
L["TOTAL_REAGENTS"] = "Total Reagents"

-- =============================================
-- Database / Migration
-- =============================================
L["DATABASE_UPDATED_MSG"] = "Database updated to a new version."
L["DATABASE_RELOAD_REQUIRED"] = "A one-time reload is required to apply changes."
L["RELOAD_UI_BUTTON"] = "Reload UI"
L["MIGRATION_RESET_COMPLETE"] = "Reset complete. All data will be rescanned automatically."

-- =============================================
-- Sync / Loading
-- =============================================
L["SYNCING_COMPLETE"] = "Syncing complete!"
L["SYNCING_LABEL_FORMAT"] = "WN Syncing : %s"
L["SETTINGS_UI_UNAVAILABLE"] = "Settings UI not available. Try /wn to open the main window."

-- =============================================
-- Character Tracking Dialog
-- =============================================
L["TRACKED_LABEL"] = "Tracked"
L["TRACKED_DETAILED_LINE1"] = "Full detailed data"
L["TRACKED_DETAILED_LINE2"] = "All features enabled"
L["UNTRACKED_LABEL"] = "Untracked"
L["UNTRACKED_VIEWONLY_LINE1"] = "View-only mode"
L["UNTRACKED_VIEWONLY_LINE2"] = "Basic info only"
L["TRACKING_ENABLED_CHAT"] = "Character tracking enabled. Data collection will begin."
L["TRACKING_DISABLED_CHAT"] = "Character tracking disabled. Running in read-only mode."
L["ADDED_TO_FAVORITES"] = "Added to favorites:"
L["REMOVED_FROM_FAVORITES"] = "Removed from favorites:"

-- =============================================
-- Tooltip: Collectible Drop Lines
-- =============================================
L["TOOLTIP_ATTEMPTS"] = "attempts"
L["TOOLTIP_100_DROP"] = "100% Drop"
L["TOOLTIP_UNKNOWN"] = "Unknown"
L["TOOLTIP_WARBAND_BANK"] = "Warband Bank"
L["TOOLTIP_HOLD_SHIFT"] = "  Hold [Shift] for full list"
L["TOOLTIP_CONCENTRATION_MARKER"] = "Warband Nexus - Concentration"
L["TOOLTIP_FULL"] = "(Full)"

-- =============================================
-- SharedWidgets: UI Labels
-- =============================================
L["NO_RESULTS"] = "No results"
L["NO_ITEMS_CACHED_TITLE"] = "No items cached"
L["SEARCH_PLACEHOLDER"] = "Search..."
L["COMBAT_CURRENCY_ERROR"] = "Cannot open currency frame during combat. Try again after combat."
L["DB_LABEL"] = "DB:"

-- =============================================
-- DataService: Loading Stages & Alerts
-- =============================================
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

-- =============================================
-- DataService: Reputation Standings
-- =============================================
L["STANDING_HATED"] = "Hated"
L["STANDING_HOSTILE"] = "Hostile"
L["STANDING_UNFRIENDLY"] = "Unfriendly"
L["STANDING_NEUTRAL"] = "Neutral"
L["STANDING_FRIENDLY"] = "Friendly"
L["STANDING_HONORED"] = "Honored"
L["STANDING_REVERED"] = "Revered"
L["STANDING_EXALTED"] = "Exalted"

-- =============================================
-- TryCounterService: Messages
-- =============================================
L["TRYCOUNTER_ATTEMPTS_FOR"] = "%d attempts for %s"
L["TRYCOUNTER_OBTAINED_RESET"] = "Obtained %s! Try counter reset."
L["TRYCOUNTER_CAUGHT_RESET"] = "Caught %s! Try counter reset."
L["TRYCOUNTER_CONTAINER_RESET"] = "Obtained %s from container! Try counter reset."
L["TRYCOUNTER_LOCKOUT_SKIP"] = "Skipped: daily/weekly lockout active for this NPC."
L["TRYCOUNTER_INSTANCE_DROPS"] = "Collectible drops in this instance:"
L["TRYCOUNTER_COLLECTED_TAG"] = "(Collected)"
L["TRYCOUNTER_ATTEMPTS_SUFFIX"] = " attempts"
L["TRYCOUNTER_TYPE_MOUNT"] = "Mount"
L["TRYCOUNTER_TYPE_PET"] = "Pet"
L["TRYCOUNTER_TYPE_TOY"] = "Toy"
L["TRYCOUNTER_TYPE_ITEM"] = "Item"
L["TRYCOUNTER_TRY_COUNTS"] = "Try Counts"

-- =============================================
-- Loading Tracker Labels
-- =============================================
L["LT_CHARACTER_DATA"] = "Character Data"
L["LT_CURRENCY_CACHES"] = "Currency & Caches"
L["LT_REPUTATIONS"] = "Reputations"
L["LT_PROFESSIONS"] = "Professions"
L["LT_PVE_DATA"] = "PvE Data"
L["LT_COLLECTIONS"] = "Collections"

-- =============================================
-- Config: Settings Panel
-- =============================================
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
L["CONFIG_MOD_PLANS"] = "Plans"
L["CONFIG_MOD_PLANS_DESC"] = "Collection plan tracking and completion goals."
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
L["CONFIG_DB_STATS"] = "Show Database Statistics"
L["CONFIG_DB_STATS_DESC"] = "Display current database size and optimization statistics."
L["CONFIG_DB_OPTIMIZER_NA"] = "Database optimizer not loaded"
L["CONFIG_OPTIMIZE_NOW"] = "Optimize Database Now"
L["CONFIG_OPTIMIZE_NOW_DESC"] = "Run the database optimizer to clean up and compress stored data."
L["CONFIG_COMMANDS_HEADER"] = "Slash Commands"

-- Config: Additional keys used by sub-agent
L["CONFIG_AUTOMATION"] = "Automation"
L["CONFIG_AUTOMATION_DESC"] = "Control what happens automatically when you open your Warband Bank."
L["DISPLAY_SETTINGS"] = "Display"
L["DISPLAY_SETTINGS_DESC"] = "Customize how items and information are displayed."
L["THEME_APPEARANCE"] = "Theme & Appearance"
L["COLOR_PURPLE"] = "Purple Theme"
L["COLOR_PURPLE_DESC"] = "Classic purple theme (default)"
L["COLOR_BLUE"] = "Blue Theme"
L["COLOR_BLUE_DESC"] = "Cool blue theme"
L["COLOR_GREEN"] = "Green Theme"
L["COLOR_GREEN_DESC"] = "Nature green theme"
L["COLOR_RED"] = "Red Theme"
L["COLOR_RED_DESC"] = "Fiery red theme"
L["COLOR_ORANGE"] = "Orange Theme"
L["COLOR_ORANGE_DESC"] = "Warm orange theme"
L["COLOR_CYAN"] = "Cyan Theme"
L["COLOR_CYAN_DESC"] = "Bright cyan theme"
L["RESET_DEFAULT"] = "Reset to Default"
L["CONFIG_THEME_RESET_DESC"] = "Reset all theme colors to their default purple theme."
L["VAULT_REMINDER"] = "Weekly Vault Reminder"
L["VAULT_REMINDER_TOOLTIP"] = "Show a reminder popup on login when you have unclaimed Great Vault rewards"
L["LOOT_ALERTS"] = "Mount/Pet/Toy Loot Alerts"
L["LOOT_ALERTS_TOOLTIP"] = "Show a popup when a NEW mount, pet, toy, or achievement enters your collection."
L["REPUTATION_GAINS"] = "Show Reputation Gains"
L["REPUTATION_GAINS_TOOLTIP"] = "Display reputation gain messages in chat when you earn faction standing."
L["CURRENCY_GAINS"] = "Show Currency Gains"
L["CURRENCY_GAINS_TOOLTIP"] = "Display currency gain messages in chat when you earn currencies."
L["REMOVE_COMPLETED_TOOLTIP"] = "Remove all completed plans from your My Plans list. This action cannot be undone!"
L["IGNORE_WARBAND_TAB_FORMAT"] = "Ignore Tab %d"
L["IGNORE_SCAN_FORMAT"] = "Exclude %s from automatic scanning"
L["TAB_FORMAT"] = "Tab %d"
L["DELETE_CHARACTER"] = "Delete Selected Character"
L["FONT_FAMILY_TOOLTIP"] = "Choose the font used throughout the addon UI"
L["FONT_SCALE"] = "Font Scale"
L["FONT_SCALE_TOOLTIP"] = "Adjust font size across all UI elements."
L["ANTI_ALIASING"] = "Anti-Aliasing"
L["ANTI_ALIASING_DESC"] = "Font edge rendering style (affects readability)"
L["RESOLUTION_NORMALIZATION"] = "Resolution Normalization"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Adjust font sizes based on screen resolution and UI scale for consistent physical size across different displays"
