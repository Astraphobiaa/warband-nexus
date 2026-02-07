--[[
    Warband Nexus - Chat Message Service
    Handles chat notifications for reputation gains, currency gains, and other game events
    
    Architecture:
    - Event-driven: Listens to internal addon events (WN_REPUTATION_GAINED, WN_CURRENCY_GAINED)
    - API-direct: Reputation events carry full display data from Snapshot-Diff (no DB lookup)
    - Currency events carry {currencyID, gainAmount}; display data from DB.
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

---Handle reputation gain event (Snapshot-Diff payload)
---Event payload: {factionID, factionName, gainAmount, currentRep, maxRep, wasStandingUp, standingName?, standingColor?}
---All display data comes directly from the WoW API via Snapshot-Diff — no DB lookup needed.
local function OnReputationGained(event, data)
    if not data or not data.factionID then return end
    
    -- Check if notifications enabled
    if not WarbandNexus.db.profile.notifications or not WarbandNexus.db.profile.notifications.showReputationGains then
        return
    end
    
    -- All display data is in the event payload (from Snapshot-Diff API read)
    local factionName = data.factionName or ("Faction " .. data.factionID)
    local gainAmount = data.gainAmount or 0
    local currentRep = data.currentRep or 0
    local maxRep = data.maxRep or 0
    
    -- Gain message
    if gainAmount > 0 then
        local message
        if maxRep > 0 then
            message = string.format(
                (ns.L and ns.L["CHAT_REP_GAIN"]) or "|cffff8800[WN-Reputation]|r |cff00ff00[%s]|r: Gained |cff00ff00+%s|r |cff00ff00(%s / %s)|r",
                factionName,
                FormatNumber(gainAmount),
                FormatNumber(currentRep),
                FormatNumber(maxRep)
            )
        else
            -- maxRep=0: faction has no trackable progress (e.g., max standing, header)
            message = string.format(
                (ns.L and ns.L["CHAT_REP_GAIN_NOMAX"]) or "|cffff8800[WN-Reputation]|r |cff00ff00[%s]|r: Gained |cff00ff00+%s|r",
                factionName,
                FormatNumber(gainAmount)
            )
        end
        print(message)
    end
    
    -- Standing change notification
    if data.wasStandingUp then
        local standingName = data.standingName or "Unknown"
        local standingColor = data.standingColor or {r = 1, g = 1, b = 1}
        local colorHex = RGBToHex(standingColor)
        local standingMessage = string.format(
            (ns.L and ns.L["CHAT_REP_STANDING"]) or "|cffff8800[WN-Reputation]|r |cff00ff00[%s]|r: Now |cff%s%s|r",
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

---Handle currency gain event
---Event payload: {currencyID, gainAmount}
---Display data: read from DB via GetCurrencyData
local function OnCurrencyGained(event, data)
    if not data or not data.currencyID then return end
    
    -- Check if notifications enabled
    if not WarbandNexus.db.profile.notifications or not WarbandNexus.db.profile.notifications.showCurrencyGains then
        return
    end
    
    -- Read display data from DB (single source of truth — same as UI)
    local dbData = WarbandNexus:GetCurrencyData(data.currencyID)
    if not dbData then return end
    
    local currencyName = dbData.name or ("Currency " .. data.currencyID)
    local gainAmount = data.gainAmount or 0
    local currentQuantity = dbData.quantity or 0
    local maxQuantity = dbData.maxQuantity
    
    -- Build clickable currency hyperlink
    local currencyLink = nil
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
        currencyLink = C_CurrencyInfo.GetCurrencyLink(data.currencyID)
    end
    local displayName = currencyLink or ("|cff00ff00[" .. currencyName .. "]|r")
    
    -- Build message
    local message
    if maxQuantity and maxQuantity > 0 then
        message = string.format(
            (ns.L and ns.L["CHAT_CUR_GAIN"]) or "|cffcc66ff[WN-Currency]|r %s: Gained |cff00ff00+%s|r |cff00ff00(%s / %s)|r",
            displayName,
            FormatNumber(gainAmount),
            FormatNumber(currentQuantity),
            FormatNumber(maxQuantity)
        )
    else
        message = string.format(
            (ns.L and ns.L["CHAT_CUR_GAIN_NOMAX"]) or "|cffcc66ff[WN-Currency]|r %s: Gained |cff00ff00+%s|r |cff00ff00(%s)|r",
            displayName,
            FormatNumber(gainAmount),
            FormatNumber(currentQuantity)
        )
    end
    
    print(message)
end

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

---Initialize chat message service (register event listeners)
function WarbandNexus:InitializeChatMessageService()
    self:RegisterMessage("WN_REPUTATION_GAINED", OnReputationGained)
    self:RegisterMessage("WN_CURRENCY_GAINED", OnCurrencyGained)
end

-- Module loaded (silent)
