--[[
    Warband Nexus - Spanish (Mexico) Localization
    
    This is the default/fallback locale for all other languages.
    
    NOTE: Many strings use Blizzard's built-in GlobalStrings for automatic localization!
    Examples:
    - CLOSE, SETTINGS, REFRESH, SEARCH → Blizzard globals
    - ITEM_QUALITY0_DESC through ITEM_QUALITY7_DESC → Quality names (Poor, Common, Rare, etc.)
    - BAG_FILTER_* → Category names (Equipment, Consumables, etc.)
    - CHARACTER, STATISTICS, LOCATION_COLON → Tooltip strings
    
    These strings are automatically localized by WoW in all supported languages:
    esMX, deDE, esES, esMX, frFR, itIT, koKR, ptBR, ruRU, zhCN, zhTW
    
    Custom strings (Warband Nexus specific) are defined here as fallback.
]]

local ADDON_NAME, ns = ...

-- Initialize Custom Locale Storage
ns.Locales = ns.Locales or {}
ns.Locales["esMX"] = ns.Locales["esMX"] or {}
local L_store = ns.Locales["esMX"]

---@class WarbandNexusLocale
local AceL = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "esMX", true, true)
if not AceL then return end

-- Proxy L to write to both AceLocale and our Cache
local L = setmetatable({}, {
    __newindex = function(t, k, v)
        AceL[k] = v      -- Write to AceLocale
        L_store[k] = v   -- Write to Custom Store
    end,
    __index = AceL
})

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

-- UI Module
L["MAIN_WINDOW_TITLE"] = "Warband Nexus"
L["SEARCH_PLACEHOLDER"] = SEARCH .. "..." -- Blizzard Global
L["BTN_SCAN"] = "Scan Bank" -- Custom action
L["BTN_DEPOSIT"] = "Deposit Queue"
L["BTN_SORT"] = "Sort Bank"
L["BTN_CLOSE"] = CLOSE -- Blizzard Global
L["BTN_SETTINGS"] = SETTINGS -- Blizzard Global
L["BTN_REFRESH"] = REFRESH -- Blizzard Global
L["BTN_CLEAR_QUEUE"] = "Clear Queue"
L["BTN_DEPOSIT_ALL"] = "Deposit All"
L["BTN_DEPOSIT_GOLD"] = "Deposit Gold"

-- Item Categories (Using Blizzard Globals where available)
L["CATEGORY_ALL"] = ALL -- Blizzard Global
L["CATEGORY_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment"
L["CATEGORY_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables"
L["CATEGORY_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents"
L["CATEGORY_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods"
L["CATEGORY_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest Items"
L["CATEGORY_MISCELLANEOUS"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"

-- Quality Filters (Using Blizzard Globals - automatically localized!)
L["QUALITY_POOR"] = ITEM_QUALITY0_DESC
L["QUALITY_COMMON"] = ITEM_QUALITY1_DESC
L["QUALITY_UNCOMMON"] = ITEM_QUALITY2_DESC
L["QUALITY_RARE"] = ITEM_QUALITY3_DESC
L["QUALITY_EPIC"] = ITEM_QUALITY4_DESC
L["QUALITY_LEGENDARY"] = ITEM_QUALITY5_DESC
L["QUALITY_ARTIFACT"] = ITEM_QUALITY6_DESC
L["QUALITY_HEIRLOOM"] = ITEM_QUALITY7_DESC

-- Statistics
L["STATS_HEADER"] = STATISTICS or "Statistics" -- Blizzard Global
L["STATS_TOTAL_ITEMS"] = "Total Items"
L["STATS_TOTAL_SLOTS"] = "Total Slots"
L["STATS_FREE_SLOTS"] = "Free Slots"
L["STATS_USED_SLOTS"] = "Used Slots"
L["STATS_TOTAL_VALUE"] = "Total Value"

-- Tooltips
L["TOOLTIP_CHARACTER"] = CHARACTER or "Character" -- Blizzard Global
L["TOOLTIP_LOCATION"] = LOCATION_COLON or "Location" -- Blizzard Global
L["TOOLTIP_WARBAND_BANK"] = "Warband Bank"
L["TOOLTIP_TAB"] = TAB or "Tab" -- Blizzard Global
L["TOOLTIP_SLOT"] = SLOT_ABBR or "Slot" -- Blizzard Global
L["TOOLTIP_COUNT"] = COUNT or "Count" -- Blizzard Global

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

-- Profiles (AceDB)
L["PROFILES"] = "Profiles"
L["PROFILES_DESC"] = "Manage addon profiles"

-- Warband Bank Operations (Withdraw/Sort)
L["INVALID_AMOUNT"] = "Invalid amount."
L["WITHDRAW_BANK_NOT_OPEN"] = "Bank must be open to withdraw!"
L["WITHDRAW_IN_COMBAT"] = "Cannot withdraw during combat."
L["WITHDRAW_INSUFFICIENT_FUNDS"] = "Not enough gold in Warband bank."
L["WITHDRAWN_LABEL"] = "Withdrawn:"
L["WITHDRAW_API_UNAVAILABLE"] = "Withdraw API not available."
L["SORT_IN_COMBAT"] = "Cannot sort while in combat."

-- Testing
L["TEST_LOCALIZATION"] = "Test Localization"
L["TEST_LOCALIZATION_DESC"] = "Print a test message to chat to verify language settings."

-- Dynamic UI Elements
L["TAB_CHARACTERS"] = CHARACTER or "Characters" -- Reuse global
L["TAB_ITEMS"] = ITEMS or "Items" -- Blizzard Global
L["TAB_STORAGE"] = "Storage"
L["TAB_PLANS"] = "Plans"
L["TAB_REPUTATION"] = REPUTATION or "Reputation" -- Blizzard Global
L["TAB_CURRENCY"] = CURRENCY or "Currency" -- Blizzard Global
L["TAB_PVE"] = "PvE"
L["TAB_STATISTICS"] = STATISTICS or "Statistics" -- Blizzard Global

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

-- Plans Tab
L["PLANS_MY_PLANS"] = "My Plans"
L["PLANS_COLLECTIONS"] = "Collection Plans"
L["PLANS_SEARCH_PLACEHOLDER"] = SEARCH .. "..."
L["PLANS_ADD_CUSTOM"] = "Add Custom Plan"
L["PLANS_NO_RESULTS"] = "No results found."
L["PLANS_ALL_COLLECTED"] = "All items collected!"
L["PLANS_RECIPE_HELP"] = "Right-click recipes in your inventory to add them here."
L["CATEGORY_DAILY_TASKS"] = "Daily Tasks"
L["CATEGORY_MOUNTS"] = MOUNTS or "Mounts" -- Blizzard Global
L["CATEGORY_PETS"] = PETS or "Pets" -- Blizzard Global
L["CATEGORY_TOYS"] = TOY_BOX or "Toys" -- Blizzard Global
L["CATEGORY_TRANSMOG"] = TRANSMOGRIFY or "Transmog" -- Blizzard Global
L["CATEGORY_ILLUSIONS"] = "Illusions"
L["CATEGORY_TITLES"] = "Titles"
L["CATEGORY_ACHIEVEMENTS"] = ACHIEVEMENTS or "Achievements" -- Blizzard Global
L["ITEMS_HEADER"] = "Bank Items"
L["ITEMS_HEADER_DESC"] = "Browse and manage your Warband and Personal bank"
L["ENABLE"] = ENABLE or "Enable" -- Blizzard Global

-- Items Tab (Groups)
L["GROUP_EQUIPMENT"] = BAG_FILTER_EQUIPMENT or "Equipment"
L["GROUP_CONSUMABLES"] = BAG_FILTER_CONSUMABLES or "Consumables"
L["GROUP_PROFESSION"] = "Profession"
L["GROUP_REAGENTS"] = PROFESSIONS_MODIFIED_REAGENTS or "Reagents"
L["GROUP_TRADE_GOODS"] = BAG_FILTER_TRADE_GOODS or "Trade Goods"
L["GROUP_QUEST"] = BAG_FILTER_QUEST_ITEMS or "Quest"
L["GROUP_MISC"] = BAG_FILTER_MISCELLANEOUS or "Miscellaneous"
L["GROUP_CONTAINER"] = "Containers"
L["ITEMS_SEARCH_PLACEHOLDER"] = SEARCH .. " items..."
L["ITEMS_WARBAND_BANK"] = "Warband Bank" -- ACCOUNT_BANK_PANEL_TITLE ?
L["ITEMS_PLAYER_BANK"] = BANK or "Player Bank" -- Blizzard Global
L["ITEMS_GUILD_BANK"] = GUILD_BANK or "Guild Bank" -- Blizzard Global

-- Storage Tab
L["STORAGE_HEADER"] = "Storage Browser"
L["STORAGE_HEADER_DESC"] = "Browse all items organized by type"
L["ENABLE_MODULE"] = "Enable Module"
L["STORAGE_WARBAND_BANK"] = "Warband Bank"
L["STORAGE_PERSONAL_BANKS"] = "Personal Banks"
L["STORAGE_TOTAL_SLOTS"] = "Total Slots"
L["STORAGE_FREE_SLOTS"] = "Free Slots"
L["STORAGE_BAG_HEADER"] = "Warband Bags"
L["STORAGE_PERSONAL_HEADER"] = "Personal Bank"

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

