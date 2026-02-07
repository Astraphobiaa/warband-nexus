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
L["DEBUG_MODE"] = "Debug Mode"
L["DEBUG_MODE_DESC"] = "Enable debug messages in chat"

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
L["GROUP_PROFESSION"] = "Profession"
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
L["CATEGORY_ILLUSIONS"] = "Illusions"
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
L["VAULT_RAID"] = "Raid"
L["VAULT_DUNGEON"] = "Dungeon"
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
L["SOURCE_ACHIEVEMENT_FORMAT"] = "Source: |cff00ff00[Achievement %s]|r"
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
L["SHOW_WEEKLY_PLANNER"] = "Show Weekly Planner"
L["LOCK_MINIMAP_ICON"] = "Lock Minimap Icon"
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
L["CHARACTERS_DESC"] = "View all your characters with gold, level, professions, and last played info."
L["ITEMS_DESC"] = "Search items across all bags and banks. Auto-updates when you open the bank."
L["STORAGE_DESC"] = "Browse your entire inventory aggregated from all characters and banks."
L["PVE_DESC"] = "Track Great Vault, Mythic+ keystones, and raid lockouts for all characters."
L["REPUTATIONS_DESC"] = "Monitor reputation progress with smart filtering (Account-Wide vs Character-Specific)."
L["CURRENCY_DESC"] = "View all currencies organized by expansion with filtering options."
L["PLANS_DESC"] = "Browse and track mounts, pets, toys, achievements, and transmogs you haven't collected yet."
L["STATISTICS_DESC"] = "View achievement points, collection progress, and bag/bank usage stats."

-- =============================================
-- PvE Difficulty Names
-- =============================================
L["DIFFICULTY_MYTHIC"] = "Mythic"
L["DIFFICULTY_HEROIC"] = "Heroic"
L["DIFFICULTY_NORMAL"] = "Normal"
L["DIFFICULTY_LFR"] = "LFR"
L["TIER_FORMAT"] = "Tier %d"
L["PVP_TYPE"] = "PvP"
L["PREPARING"] = "Preparing"

-- =============================================
-- Statistics Tab (extended)
-- =============================================
L["ACCOUNT_STATISTICS"] = "Account Statistics"
L["STATISTICS_SUBTITLE"] = "Collection progress, gold, and storage overview"

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

-- Plans - Type Names
L["TYPE_MOUNT"] = "Mount"
L["TYPE_PET"] = "Pet"
L["TYPE_TOY"] = "Toy"
L["TYPE_RECIPE"] = "Recipe"
L["TYPE_ILLUSION"] = "Illusion"
L["TYPE_TITLE"] = "Title"
L["TYPE_CUSTOM"] = "Custom"
L["TYPE_TRANSMOG"] = "Transmog"

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
L["RAIDS_LABEL"] = "Raids"

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
L["SHOW_ITEM_COUNT_TOOLTIP"] = "Display stack counts on items in storage view"
L["SHOW_WEEKLY_PLANNER_TOOLTIP"] = "Display the Weekly Planner section in the Characters tab"
L["LOCK_MINIMAP_TOOLTIP"] = "Lock the minimap icon in place (prevents dragging)"
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
L["ENABLE_NOTIFICATIONS"] = "Enable Notifications"
L["ENABLE_NOTIFICATIONS_TOOLTIP"] = "Master toggle for all notification pop-ups"
L["VAULT_REMINDER"] = "Vault Reminder"
L["VAULT_REMINDER_TOOLTIP"] = "Show reminder when you have unclaimed Weekly Vault rewards"
L["LOOT_ALERTS"] = "Loot Alerts"
L["LOOT_ALERTS_TOOLTIP"] = "Show notification when a NEW mount, pet, or toy enters your bag"
L["HIDE_BLIZZARD_ACHIEVEMENT"] = "Hide Blizzard Achievement Alert"
L["HIDE_BLIZZARD_ACHIEVEMENT_TOOLTIP"] = "Hide Blizzard's default achievement popup and use Warband Nexus notification instead"
L["REPUTATION_GAINS"] = "Reputation Gains"
L["REPUTATION_GAINS_TOOLTIP"] = "Show chat messages when you gain reputation with factions"
L["CURRENCY_GAINS"] = "Currency Gains"
L["CURRENCY_GAINS_TOOLTIP"] = "Show chat messages when you gain currencies"
L["DURATION_LABEL"] = "Duration"

-- =============================================
-- Settings - Position
-- =============================================
L["DRAG_POSITION_MSG"] = "Drag the green frame to set popup position. Right-click to confirm."
L["POSITION_RESET_MSG"] = "Popup position reset to default (Top Center)"

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
L["RESOLUTION_NORMALIZATION"] = "Resolution Normalization"
L["RESOLUTION_NORMALIZATION_TOOLTIP"] = "Adjust font sizes based on screen resolution and UI scale so text stays the same physical size across different monitors"

-- =============================================
-- Settings - Advanced
-- =============================================
L["ADVANCED_SECTION"] = "Advanced"

-- =============================================
-- Tooltip Service
-- =============================================
L["ITEM_LEVEL_FORMAT"] = "Item Level %s"
L["ITEM_NUMBER_FORMAT"] = "Item #%s"
L["CHARACTER_CURRENCIES"] = "Character Currencies:"
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
L["ACHIEVEMENT_COMPLETED_MSG"] = "Achievement completed!"
L["EARNED_TITLE_MSG"] = "You have earned a title"
L["COMPLETED_PLAN_MSG"] = "You have completed a plan"
L["DAILY_QUEST_CAT"] = "Daily Quest"
L["WORLD_QUEST_CAT"] = "World Quest"
L["WEEKLY_QUEST_CAT"] = "Weekly Quest"
L["SPECIAL_ASSIGNMENT_CAT"] = "Special Assignment"
L["DELVE_CAT"] = "Delve"
L["DUNGEON_CAT"] = "Dungeon"
L["RAID_CAT"] = "Raid"
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
L["USE_COMMANDS_MSG"] = "Use /wn show, /wn scan, /wn config"

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
L["THANK_YOU_MSG"] = "Thank you for using Warband Nexus!"

-- =============================================
-- Changelog (What's New) - v2.0.0
-- =============================================
L["CHANGELOG_V200"] = "MAJOR UPDATES:\n" ..
    "- Loot & Achievement Notifications: Get notified when you earn mounts, pets, toys, illusions, titles, and achievements\n" ..
    "- Weekly Vault Reminder: Toast when you have unclaimed vault rewards\n" ..
    "- Plans Tab: Organize your goals and track what you want to collect next\n" ..
    "- Font System: Customizable fonts across the addon\n" ..
    "- Theme Colors: Custom accent colors to personalize the UI\n" ..
    "- UI Improvements: Cleaner layout, better organization, search, and visual polish\n" ..
    "- Chat messages for Reputation & Currency gains: Real-time [WN-Reputation] and [WN-Currency] messages with progress\n" ..
    "- Tooltip System: Improved tooltips across the interface\n" ..
    "- Character Tracking: Choose which characters to track\n" ..
    "- Favorite Characters: Star your favorite characters in the list\n" ..
    "\n" ..
    "MINOR UPDATES:\n" ..
    "- Bank Module disabled\n" ..
    "- Old database system removed (improvements and bug fixes)\n" ..
    "- Option to hide Blizzard's achievement pop-up when using WN notifications\n" ..
    "- Configurable notification position for loot and achievement toasts\n" ..
    "\n" ..
    "Thank you for using Warband Nexus!\n" ..
    "\n" ..
    "If you'd like to report a bug or leave feedback, you can leave a comment on CurseForge - Warband Nexus."

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
L["VAULT_SLOT_DUNGEON"] = "Dungeon"
L["VAULT_SLOT_RAIDS"] = "Raids"
L["VAULT_SLOT_WORLD"] = "World"

-- =============================================
-- PvE Extra
-- =============================================
L["AFFIX_TITLE_FALLBACK"] = "Affix"

-- =============================================
-- Chat Messages
-- =============================================
L["CHAT_REP_GAIN"] = "|cffff8800[WN-Reputation]|r |cff00ff00[%s]|r: Gained |cff00ff00+%s|r |cff00ff00(%s / %s)|r"
L["CHAT_REP_GAIN_NOMAX"] = "|cffff8800[WN-Reputation]|r |cff00ff00[%s]|r: Gained |cff00ff00+%s|r"
L["CHAT_REP_STANDING"] = "|cffff8800[WN-Reputation]|r |cff00ff00[%s]|r: Now |cff%s%s|r"
L["CHAT_CUR_GAIN"] = "|cffcc66ff[WN-Currency]|r %s: Gained |cff00ff00+%s|r |cff00ff00(%s / %s)|r"
L["CHAT_CUR_GAIN_NOMAX"] = "|cffcc66ff[WN-Currency]|r %s: Gained |cff00ff00+%s|r |cff00ff00(%s)|r"

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

-- Profiles (AceDB)
L["PROFILES"] = "Profiles"
L["PROFILES_DESC"] = "Manage addon profiles"
