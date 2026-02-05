--[[
    Warband Nexus - Chat Message Service
    Handles chat notifications for reputation gains, currency gains, and other game events
    
    Architecture:
    - Event-driven: Listens to internal addon events (WN_REPUTATION_GAINED, WN_CURRENCY_GAINED)
    - DRY: Reusable formatting functions for consistent message style
    - Standardized: All chat messages follow the same pattern: [WN-Category] [Item]: Action +Amount (Current / Max)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Format large numbers with thousands separator (e.g., 1,234,567)
---@param number number
---@return string
local function FormatNumber(number)
    if not number then return "0" end
    return BreakUpLargeNumbers(number)
end

---Convert RGB table to hex color string
---@param rgb table {r, g, b} (values 0-1)
---@return string Hex color code (e.g., "00ff00")
local function RGBToHex(rgb)
    if not rgb then return "ffffff" end
    return string.format("%02x%02x%02x", 
        math.floor((rgb.r or 1) * 255),
        math.floor((rgb.g or 1) * 255),
        math.floor((rgb.b or 1) * 255)
    )
end

-- ============================================================================
-- REPUTATION CHAT NOTIFICATIONS
-- ============================================================================

---Handle reputation gain event and print chat message
---@param event string Event name
---@param data table {factionID, factionName, gainAmount, currentValue, maxValue, standingName, standingColor, wasStandingUp}
local function OnReputationGained(event, data)
    -- Validate data
    if not data or not data.factionName then
        return
    end
    
    -- Check if reputation notifications are enabled
    if not WarbandNexus.db.profile.notifications or not WarbandNexus.db.profile.notifications.showReputationGains then
        return
    end
    
    -- Extract data
    local factionName = data.factionName
    local gainAmount = data.gainAmount or 0
    local currentValue = data.currentValue or 0
    local maxValue = data.maxValue or 0
    local standingName = data.standingName or "Unknown"
    local standingColor = data.standingColor or {r=1, g=1, b=1}
    
    -- Build main message: "[WN-Reputation] [Faction Name]: Gained +xxx (current / max)"
    -- All text in cyan (|cff00ccff) except gain amount (+xxx) which is green
    local message = string.format(
        "|cff00ccff[WN-Reputation] [%s]: Gained |cff00ff00+%s|r |cff00ccff(%s / %s)|r",
        factionName,
        FormatNumber(gainAmount),
        FormatNumber(currentValue),
        FormatNumber(maxValue)
    )
    
    -- Print to chat
    print(message)
    
    -- If standing increased, add extra notification (all cyan except standing name)
    if data.wasStandingUp then
        local colorHex = RGBToHex(standingColor)
        local standingMessage = string.format(
            "|cff00ccff[WN-Reputation] [%s]: Reached |cff%s%s|r!",
            factionName,
            colorHex,
            standingName
        )
        print(standingMessage)
    end
end

-- ============================================================================
-- CURRENCY CHAT NOTIFICATIONS
-- ============================================================================

---Handle currency gain event and print chat message
---@param event string Event name
---@param data table {currencyID, currencyName, gainAmount, currentQuantity, maxQuantity, iconFileID}
local function OnCurrencyGained(event, data)
    -- Validate data
    if not data or not data.currencyName then
        return
    end
    
    -- Check if currency notifications are enabled
    if not WarbandNexus.db.profile.notifications or not WarbandNexus.db.profile.notifications.showCurrencyGains then
        return
    end
    
    -- Extract data
    local currencyName = data.currencyName
    local currencyID = data.currencyID or 0
    local gainAmount = data.gainAmount or 0
    local currentQuantity = data.currentQuantity or 0
    local maxQuantity = data.maxQuantity
    
    -- Build message: "[WN-Currency] [Currency Name]: Gained +xxx (current / max)"
    -- All text in cyan except gain amount (+xxx) which is green
    local message
    if maxQuantity and maxQuantity > 0 then
        message = string.format(
            "|cff00ccff[WN-Currency] [%s]: Gained |cff00ff00+%s|r |cff00ccff(%s / %s)|r",
            currencyName,
            FormatNumber(gainAmount),
            FormatNumber(currentQuantity),
            FormatNumber(maxQuantity)
        )
    else
        message = string.format(
            "|cff00ccff[WN-Currency] [%s]: Gained |cff00ff00+%s|r |cff00ccff(%s)|r",
            currencyName,
            FormatNumber(gainAmount),
            FormatNumber(currentQuantity)
        )
    end
    
    -- Print to chat
    print(message)
end

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

---Initialize chat message service (register event listeners)
function WarbandNexus:InitializeChatMessageService()
    -- Register reputation gain notifications
    self:RegisterMessage("WN_REPUTATION_GAINED", OnReputationGained)
    
    -- Register currency gain notifications
    self:RegisterMessage("WN_CURRENCY_GAINED", OnCurrencyGained)
    
    -- Future: Add more event listeners here (e.g., achievement, loot, quest completion)
    -- self:RegisterMessage("WN_ACHIEVEMENT_EARNED", OnAchievementEarned)
    -- self:RegisterMessage("WN_RARE_LOOT_OBTAINED", OnRareLootObtained)
end

-- Module loaded (silent)
