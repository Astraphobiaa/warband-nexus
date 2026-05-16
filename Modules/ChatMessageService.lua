--[[
    Warband Nexus - Chat Message Service
    Handles chat notifications for reputation gains, currency gains, and other game events
    
    Architecture:
    - Event-driven: Listens to internal addon events (WN_REPUTATION_GAINED, WN_CURRENCY_GAINED)
    - DB-first: Reputation events carry full display data from PROCESSED DB (after FullScan).
    - Currency events carry {currencyID, gainAmount, gainSource?}; display data from DB / live API.
    - FIFO message queue: ensures smooth output flow (0.15s per message), no overlap or loss.
    - Per-panel routing: ns.ChatOutput only (no raw DEFAULT_CHAT_FRAME:AddMessage) so
      Chattynator’s DEFAULT hook sees Interface/AddOns/WarbandNexus/ on the stack.
    
    Color Scheme:
    - [WN-Currency] prefix: WN brand purple (#9370DB)
    - [WN-Reputation] prefix: WN brand purple (#9370DB)
    - Currency name: quality-colored hyperlink via C_CurrencyInfo.GetCurrencyLink, fallback to ITEM_QUALITY_COLORS
    - Faction name: white (#ffffff)
    - Gain amount: green (#00ff00) — the "action" stands out
    - Current total: white (#ffffff)
    - Max / separator: gray (#888888)
    - Standing name: dynamic color from standing data (yellow fallback)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local issecretvalue = issecretvalue

---@param v any
---@return number|nil
local function SafeCurrencyNum(v)
    if v == nil then return nil end
    if issecretvalue and issecretvalue(v) then return nil end
    return tonumber(v)
end

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

local ChatOutput = ns.ChatOutput
local ROUTE_GROUP_LOOT       = ChatOutput and ChatOutput.MESSAGE_GROUPS.LOOT or "LOOT"
local ROUTE_GROUP_CURRENCY   = ChatOutput and ChatOutput.MESSAGE_GROUPS.CURRENCY or "CURRENCY"
local ROUTE_GROUP_REPUTATION = ChatOutput and ChatOutput.MESSAGE_GROUPS.REPUTATION or "COMBAT_FACTION_CHANGE"

---@param factionID number|string|nil
---@return string
local function FormatFactionFallbackName(factionID)
    local base = (ns.L and ns.L["REP_FACTION_FALLBACK"]) or "Faction"
    if factionID == nil then
        return base
    end
    return base .. " " .. tostring(factionID)
end

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

---Get item-quality hex color for a currency quality value.
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
-- MESSAGE QUEUE (FIFO — prevents overlap, ensures smooth flow)
-- Uses table.remove(1) only: a head index + Lua # on sparse tables drops or
-- corrupts queued lines when gains fire back-to-back (same as CurrencyCache fix).
-- ============================================================================

local messageQueue = {}
local isProcessing = false

---Drain one entry; schedule next after QUEUE_INTERVAL if more remain.
local function ProcessQueuePump()
    local entry = table.remove(messageQueue, 1)
    if not entry then
        isProcessing = false
        return
    end
    if ChatOutput and ChatOutput.SendToFramesWithGroup then
        ChatOutput.SendToFramesWithGroup(entry.text, entry.group)
    end
    if #messageQueue > 0 then
        C_Timer.After(QUEUE_INTERVAL, ProcessQueuePump)
    else
        isProcessing = false
    end
end

---Add a message to the FIFO queue and start processing if idle.
---@param message string Formatted chat message
---@param group string Message group name for per-panel routing
local function QueueMessage(message, group)
    messageQueue[#messageQueue + 1] = { text = message, group = group }

    if isProcessing then
        return
    end
    isProcessing = true
    -- Defer first line to next frame so currency/loot handlers finish before chat routing walks frames.
    C_Timer.After(0, function()
        if #messageQueue == 0 then
            isProcessing = false
            return
        end
        ProcessQueuePump()
    end)
end

-- ============================================================================
-- CURRENCY CHAT NOTIFICATIONS
-- ============================================================================

---Handle currency gain event
---Event payload: { currencyID, gainAmount, gainSource? = "quantity"|"progress" }
---Display data: read from DB via GetCurrencyData (fallback: live GetCurrencyInfo)
local function OnCurrencyGained(event, data)
    if not data or not data.currencyID then return end
    
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled or not notifs.showCurrencyGains then
        return
    end
    
    local dbData = WarbandNexus:GetCurrencyData(data.currencyID)
    if not dbData and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, data.currencyID)
        if ok and info then
            local q = SafeCurrencyNum(info.quantity) or 0
            local maxW = SafeCurrencyNum(info.maxWeeklyQuantity) or 0
            local maxQ = SafeCurrencyNum(info.maxQuantity) or 0
            local nm = info.name
            if nm and issecretvalue and issecretvalue(nm) then
                nm = nil
            end
            dbData = {
                currencyID = data.currencyID,
                quantity = q,
                name = nm or ("Currency #" .. tostring(data.currencyID)),
                maxQuantity = (maxW > 0) and maxW or maxQ,
                seasonMax = (maxQ > 0) and maxQ or nil,
                totalEarned = SafeCurrencyNum(info.totalEarned),
                quality = info.quality or 1,
            }
        end
    end
    if not dbData then return end
    
    local currencyName = dbData.name or ("Currency " .. data.currencyID)
    local gainAmount = data.gainAmount or 0
    local gainSource = data.gainSource or "quantity"
    local currentQuantity = dbData.quantity or 0
    local maxQuantity = dbData.maxQuantity
    local seasonMax = dbData.seasonMax
    local totalEarned = dbData.totalEarned
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
    if gainSource == "progress" and type(totalEarned) == "number" then
        local denom = (type(seasonMax) == "number" and seasonMax > 0) and seasonMax
            or (maxQuantity and maxQuantity > 0 and maxQuantity)
        if denom then
            message = string.format(
                "%s%s: |cff%s+%s|r |cff%s(%s / %s)|r",
                PREFIX_CURRENCY,
                displayName,
                COLOR_GAIN, FormatNumber(gainAmount),
                COLOR_REP_PROGRESS, FormatNumber(totalEarned), FormatNumber(denom)
            )
        else
            message = string.format(
                "%s%s: |cff%s+%s|r |cff%s(%s)|r",
                PREFIX_CURRENCY,
                displayName,
                COLOR_GAIN, FormatNumber(gainAmount),
                COLOR_REP_PROGRESS, FormatNumber(totalEarned)
            )
        end
    elseif maxQuantity and maxQuantity > 0 then
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
    
    local factionName = data.factionName or FormatFactionFallbackName(data.factionID)
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

    -- Renown tier-up (major factions): explicit line; avoids missing companion when MAJOR_FACTION_* did not fire.
    if data.isRenownLevelUp and type(data.renownLevel) == "number" and data.renownLevel > 0 then
        local tail = string.format(
            (ns.L and ns.L["WN_REPUTATION_RENOWN_LEVEL_UP"]) or "Reached renown level %d",
            data.renownLevel
        )
        local renownUpMsg = string.format(
            "%s|cff%s%s|r: %s",
            PREFIX_REPUTATION,
            factionColorHex, factionName,
            tail
        )
        QueueMessage(renownUpMsg, ROUTE_GROUP_REPUTATION)
    elseif data.wasStandingUp then
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
    self:RegisterMessage(E.REPUTATION_GAINED, OnReputationGained)
    self:RegisterMessage(E.CURRENCY_GAINED, OnCurrencyGained)
end
