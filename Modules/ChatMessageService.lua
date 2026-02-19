--[[
    Warband Nexus - Chat Message Service
    Handles chat notifications for reputation gains, currency gains, and other game events
    
    Architecture:
    - Event-driven: Listens to internal addon events (WN_REPUTATION_GAINED, WN_CURRENCY_GAINED)
    - DB-first: Reputation events carry full display data from PROCESSED DB (after FullScan).
    - Currency events carry {currencyID, gainAmount}; display data from DB.
    - FIFO message queue: ensures smooth output flow (0.15s per message), no overlap or loss.
    - Per-panel routing: messages are sent to all chat frames that have the relevant
      Blizzard message group enabled (via ChatFrame_ContainsMessageGroup /
      chatFrame.messageTypeList), preserving the user's per-panel chat configuration.
    
    Color Scheme:
    - [WN-Currency] prefix: WN brand purple (#9370DB)
    - [WN-Reputation] prefix: WN brand purple (#9370DB)
    - Currency name: rarity-colored hyperlink via C_CurrencyInfo.GetCurrencyLink, fallback to ITEM_QUALITY_COLORS
    - Faction name: white (#ffffff)
    - Gain amount: green (#00ff00) — the "action" stands out
    - Current total: white (#ffffff)
    - Max / separator: gray (#888888)
    - Standing name: dynamic color from standing data (yellow fallback)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local PREFIX_CURRENCY = "|cff9370DB[WN-Currency]|r "
local PREFIX_REPUTATION = "|cff9370DB[WN-Reputation]|r "

local COLOR_GAIN = "00ff00"
local COLOR_TOTAL = "ffffff"
local COLOR_MAX = "888888"
local COLOR_FACTION = "ffffff"
local COLOR_STANDING = "ffff00"
local COLOR_REP_PROGRESS = "ffff00"

local QUEUE_INTERVAL = 0.15

-- Blizzard message group names for per-panel routing via ChatFrame_ContainsMessageGroup
-- LOOT = try counter (mount try, found/obtained/caught/reset) only
-- CURRENCY = currency gain messages only
-- COMBAT_FACTION_CHANGE = reputation messages only
local ROUTE_GROUP_LOOT       = "LOOT"
local ROUTE_GROUP_CURRENCY   = "CURRENCY"
local ROUTE_GROUP_REPUTATION = "COMBAT_FACTION_CHANGE"

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

---Get rarity hex color for a currency quality value.
---@param quality number Quality index (0=Poor, 1=Common, 2=Uncommon, 3=Rare, 4=Epic, ...)
---@return string Hex color code
local function GetQualityHex(quality)
    if not quality or not ITEM_QUALITY_COLORS then return "ffffff" end
    local color = ITEM_QUALITY_COLORS[quality]
    if color then
        return string.format("%02x%02x%02x",
            math.floor(color.r * 255),
            math.floor(color.g * 255),
            math.floor(color.b * 255)
        )
    end
    return "ffffff"
end

-- ============================================================================
-- PER-PANEL MESSAGE ROUTING
-- ============================================================================

---Check if a chat frame has a Blizzard message group enabled.
---Uses ChatFrame_ContainsMessageGroup (checks frame.messageTypeList),
---which correctly reflects the user's per-panel chat settings regardless
---of which tab is currently active or visible.
---@param frame table ChatFrame
---@param group string Message group name (e.g., "CURRENCY", "COMBAT_FACTION_CHANGE")
---@return boolean
local function FrameHasMessageGroup(frame, group)
    if not frame then return false end
    if ChatFrame_ContainsMessageGroup then
        return ChatFrame_ContainsMessageGroup(frame, group) == true
    end
    if frame.messageTypeList then
        for i = 1, #frame.messageTypeList do
            if frame.messageTypeList[i] == group then
                return true
            end
        end
    end
    return false
end

---Check if a chat frame has any of the given message groups enabled.
---@param frame table ChatFrame
---@param groups table Array of message group names
---@return boolean
local function FrameHasAnyMessageGroup(frame, groups)
    if not frame or not groups then return false end
    for j = 1, #groups do
        if FrameHasMessageGroup(frame, groups[j]) then
            return true
        end
    end
    return false
end

---Send a message to all chat frames that have the specified message group
---enabled. Falls back to DEFAULT_CHAT_FRAME if no frames matched
---(e.g., user disabled the category on all panels).
---@param message string Formatted message to display
---@param group string Message group name (e.g., "CURRENCY", "COMBAT_FACTION_CHANGE")
local function SendToFramesWithGroup(message, group)
    local sent = false
    local numWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, numWindows do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage and FrameHasMessageGroup(frame, group) then
            frame:AddMessage(message)
            sent = true
        end
    end
    if not sent then
        local default = DEFAULT_CHAT_FRAME
        if default and default.AddMessage then
            default:AddMessage(message)
        end
    end
end

---Send a message to all chat frames that have ANY of the given message groups
---enabled (e.g. Loot, Currency, Reputation). Used for try counter messages so
---they appear on every tab that shows loot/rep/currency; switching tabs shows the same messages.
---@param message string Formatted message to display
---@param groups table Array of message group names (e.g. {"LOOT", "CURRENCY", "COMBAT_FACTION_CHANGE"})
local function SendToFramesWithAnyGroup(message, groups)
    if not groups or #groups == 0 then
        local default = DEFAULT_CHAT_FRAME
        if default and default.AddMessage then default:AddMessage(message) end
        return
    end
    local sent = false
    local numWindows = NUM_CHAT_WINDOWS or 10
    for i = 1, numWindows do
        local frame = _G["ChatFrame" .. i]
        if frame and frame.AddMessage and FrameHasAnyMessageGroup(frame, groups) then
            frame:AddMessage(message)
            sent = true
        end
    end
    if not sent then
        local default = DEFAULT_CHAT_FRAME
        if default and default.AddMessage then
            default:AddMessage(message)
        end
    end
end

---Public API for other modules: send try counter messages (mount try, found/obtained/
---caught/reset, instance drops, skip messages) only to chat frames that have LOOT enabled.
---Reputation and Currency use their own groups (COMBAT_FACTION_CHANGE, CURRENCY).
ns.SendToChatFramesLootRepCurrency = function(message)
    SendToFramesWithGroup(message, ROUTE_GROUP_LOOT)
end

-- ============================================================================
-- MESSAGE QUEUE (FIFO — prevents overlap, ensures smooth flow)
-- ============================================================================

local messageQueue = {}
local isProcessing = false

---Add a message to the FIFO queue and start processing if idle.
---@param message string Formatted chat message
---@param group string Message group name for per-panel routing
local function QueueMessage(message, group)
    messageQueue[#messageQueue + 1] = { text = message, group = group }
    
    if not isProcessing then
        isProcessing = true
        local first = table.remove(messageQueue, 1)
        if first then SendToFramesWithGroup(first.text, first.group) end
        
        if #messageQueue > 0 then
            local function ProcessNext()
                if #messageQueue == 0 then
                    isProcessing = false
                    return
                end
                local entry = table.remove(messageQueue, 1)
                if entry then SendToFramesWithGroup(entry.text, entry.group) end
                
                if #messageQueue > 0 then
                    C_Timer.After(QUEUE_INTERVAL, ProcessNext)
                else
                    isProcessing = false
                end
            end
            C_Timer.After(QUEUE_INTERVAL, ProcessNext)
        else
            isProcessing = false
        end
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
    
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled or not notifs.showCurrencyGains then
        return
    end
    
    local dbData = WarbandNexus:GetCurrencyData(data.currencyID)
    if not dbData then return end
    
    local currencyName = dbData.name or ("Currency " .. data.currencyID)
    local gainAmount = data.gainAmount or 0
    local currentQuantity = dbData.quantity or 0
    local maxQuantity = dbData.maxQuantity
    local quality = dbData.quality or 1
    
    if gainAmount <= 0 then return end
    
    local displayName
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
        displayName = C_CurrencyInfo.GetCurrencyLink(data.currencyID)
    end
    if not displayName then
        local qualityHex = GetQualityHex(quality)
        displayName = string.format("|cff%s[%s]|r", qualityHex, currencyName)
    end
    
    local message
    if maxQuantity and maxQuantity > 0 then
        message = string.format(
            "%s%s: |cff%s+%s|r |cff%s(%s / %s)|r",
            PREFIX_CURRENCY,
            displayName,
            COLOR_GAIN, FormatNumber(gainAmount),
            COLOR_REP_PROGRESS, FormatNumber(currentQuantity), FormatNumber(maxQuantity)
        )
    else
        message = string.format(
            "%s%s: |cff%s+%s|r |cff%s(%s)|r",
            PREFIX_CURRENCY,
            displayName,
            COLOR_GAIN, FormatNumber(gainAmount),
            COLOR_REP_PROGRESS, FormatNumber(currentQuantity)
        )
    end
    
    QueueMessage(message, ROUTE_GROUP_CURRENCY)
end

-- ============================================================================
-- REPUTATION CHAT NOTIFICATIONS
-- ============================================================================

---Handle reputation gain event (Snapshot-Diff payload)
---Event payload: {factionID, factionName, gainAmount, currentRep, maxRep, wasStandingUp, standingName?, standingColor?}
local function OnReputationGained(event, data)
    if not data or not data.factionID then return end
    
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled or not notifs.showReputationGains then
        return
    end
    
    local factionName = data.factionName or ("Faction " .. data.factionID)
    local gainAmount = data.gainAmount or 0
    local currentRep = data.currentRep or 0
    local maxRep = data.maxRep or 0
    
    local factionColorHex = COLOR_FACTION
    
    local standingName = data.standingName
    local standingHex = COLOR_STANDING
    if data.standingColor then
        standingHex = RGBToHex(data.standingColor)
    end
    
    if gainAmount > 0 then
        local message
        if maxRep > 0 then
            local progressPart = string.format("|cff%s(%s / %s)|r",
                COLOR_REP_PROGRESS, FormatNumber(currentRep), FormatNumber(maxRep))
            local standingPart = standingName and string.format(" |cff%s%s|r", standingHex, standingName) or ""
            
            message = string.format(
                "%s|cff%s%s|r: |cff%s+%s|r %s%s",
                PREFIX_REPUTATION,
                factionColorHex, factionName,
                COLOR_GAIN, FormatNumber(gainAmount),
                progressPart,
                standingPart
            )
        else
            local standingPart = standingName and string.format(" |cff%s%s|r", standingHex, standingName) or ""
            message = string.format(
                "%s|cff%s%s|r: |cff%s+%s|r%s",
                PREFIX_REPUTATION,
                factionColorHex, factionName,
                COLOR_GAIN, FormatNumber(gainAmount),
                standingPart
            )
        end
        QueueMessage(message, ROUTE_GROUP_REPUTATION)
    end
    
    if data.wasStandingUp then
        local upStandingName = data.standingName or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        local upStandingColor = data.standingColor or {r = 1, g = 1, b = 1}
        local upStandingHex = RGBToHex(upStandingColor)
        local standingMessage = string.format(
            "%s|cff%s%s|r: Now |cff%s%s|r",
            PREFIX_REPUTATION,
            factionColorHex, factionName,
            upStandingHex, upStandingName
        )
        QueueMessage(standingMessage, ROUTE_GROUP_REPUTATION)
    end
end

-- ============================================================================
-- MODULE INITIALIZATION
-- ============================================================================

---Initialize chat message service (register event listeners)
function WarbandNexus:InitializeChatMessageService()
    self:RegisterMessage("WN_REPUTATION_GAINED", OnReputationGained)
    self:RegisterMessage("WN_CURRENCY_GAINED", OnCurrencyGained)
end
