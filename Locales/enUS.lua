--[[
    Warband Nexus - English Localization (Base)
    This is the default/fallback locale
]]

local ADDON_NAME, ns = ...

---@class WarbandNexusLocale
local L = LibStub("AceLocale-3.0"):NewLocale(ADDON_NAME, "enUS", true, true)
if not L then return end

-- General
L["ADDON_NAME"] = "Warband Nexus"
L["ADDON_LOADED"] = "Warband Nexus loaded. Type /wn or /warbandnexus for options."
L["VERSION"] = "Version"

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
L["SEARCH_PLACEHOLDER"] = "Search items..."
L["BTN_SCAN"] = "Scan Bank"
L["BTN_DEPOSIT"] = "Deposit Queue"
L["BTN_SORT"] = "Sort Bank"
L["BTN_CLOSE"] = "Close"
L["BTN_SETTINGS"] = "Settings"
L["BTN_REFRESH"] = "Refresh"
L["BTN_CLEAR_QUEUE"] = "Clear Queue"
L["BTN_DEPOSIT_ALL"] = "Deposit All"
L["BTN_DEPOSIT_GOLD"] = "Deposit Gold"

-- Item Categories
L["CATEGORY_ALL"] = "All Items"
L["CATEGORY_EQUIPMENT"] = "Equipment"
L["CATEGORY_CONSUMABLES"] = "Consumables"
L["CATEGORY_REAGENTS"] = "Reagents"
L["CATEGORY_TRADE_GOODS"] = "Trade Goods"
L["CATEGORY_QUEST"] = "Quest Items"
L["CATEGORY_MISCELLANEOUS"] = "Miscellaneous"

-- Quality Filters
L["QUALITY_POOR"] = "Poor"
L["QUALITY_COMMON"] = "Common"
L["QUALITY_UNCOMMON"] = "Uncommon"
L["QUALITY_RARE"] = "Rare"
L["QUALITY_EPIC"] = "Epic"
L["QUALITY_LEGENDARY"] = "Legendary"
L["QUALITY_ARTIFACT"] = "Artifact"
L["QUALITY_HEIRLOOM"] = "Heirloom"

-- Statistics
L["STATS_HEADER"] = "Statistics"
L["STATS_TOTAL_ITEMS"] = "Total Items"
L["STATS_TOTAL_SLOTS"] = "Total Slots"
L["STATS_FREE_SLOTS"] = "Free Slots"
L["STATS_USED_SLOTS"] = "Used Slots"
L["STATS_TOTAL_VALUE"] = "Total Value"

-- Tooltips
L["TOOLTIP_CHARACTER"] = "Character"
L["TOOLTIP_LOCATION"] = "Location"
L["TOOLTIP_WARBAND_BANK"] = "Warband Bank"
L["TOOLTIP_TAB"] = "Tab"
L["TOOLTIP_SLOT"] = "Slot"
L["TOOLTIP_COUNT"] = "Count"

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
