--[[
    Warband Nexus - Chat Message Service
    Handles chat notifications for reputation gains, currency gains, and other game events
    
    Architecture:
    - Event-driven: Listens to internal addon events (WN_REPUTATION_GAINED, WN_CURRENCY_GAINED)
    - DB-first: Reputation events carry full display data from PROCESSED DB (after FullScan).
    - Currency events carry {currencyID, gainAmount}; display data from DB.
    - FIFO message queue: ensures smooth output flow (0.15s per message), no overlap or loss.
    
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

local COLOR_GAIN = "00ff00"      -- Green: gain amount (action, must pop)
local COLOR_TOTAL = "ffffff"     -- White: current quantity (currency)
local COLOR_MAX = "888888"       -- Gray: max quantity / separator (currency)
local COLOR_FACTION = "ffffff"   -- White: faction name
local COLOR_STANDING = "ffff00"  -- Yellow: standing name fallback
local COLOR_REP_PROGRESS = "ffff00"  -- Yellow: reputation (current / max)

-- Queue processing interval (seconds between messages)
local QUEUE_INTERVAL = 0.15

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
---Uses Blizzard's ITEM_QUALITY_COLORS table.
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
-- ============================================================================

local messageQueue = {}
local isProcessing = false

---Add a message to the FIFO queue and start processing if idle.
---@param message string Formatted chat message
local function QueueMessage(message)
    messageQueue[#messageQueue + 1] = message
    
    if not isProcessing then
        isProcessing = true
        -- Process first message immediately (no delay for single messages)
        local first = table.remove(messageQueue, 1)
        if first then print(first) end
        
        -- If more messages remain, schedule sequential processing
        if #messageQueue > 0 then
            local function ProcessNext()
                if #messageQueue == 0 then
                    isProcessing = false
                    return
                end
                local msg = table.remove(messageQueue, 1)
                if msg then print(msg) end
                
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
    
    -- Check if notifications enabled (master toggle + specific toggle)
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled or not notifs.showCurrencyGains then
        return
    end
    
    -- Read display data from DB (single source of truth)
    local dbData = WarbandNexus:GetCurrencyData(data.currencyID)
    if not dbData then return end
    
    local currencyName = dbData.name or ("Currency " .. data.currencyID)
    local gainAmount = data.gainAmount or 0
    local currentQuantity = dbData.quantity or 0
    local maxQuantity = dbData.maxQuantity
    local quality = dbData.quality or 1
    
    if gainAmount <= 0 then return end
    
    -- Build currency display: hyperlink (rarity-colored by Blizzard) or fallback with rarity color
    local displayName
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyLink then
        displayName = C_CurrencyInfo.GetCurrencyLink(data.currencyID)
    end
    if not displayName then
        local qualityHex = GetQualityHex(quality)
        displayName = string.format("|cff%s[%s]|r", qualityHex, currencyName)
    end
    
    -- Format: [WN-Currency] [Valorstones]: +500 (1,234 / 2,000)
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
    
    QueueMessage(message)
end

-- ============================================================================
-- REPUTATION CHAT NOTIFICATIONS
-- ============================================================================

---Handle reputation gain event (Snapshot-Diff payload)
---Event payload: {factionID, factionName, gainAmount, currentRep, maxRep, wasStandingUp, standingName?, standingColor?}
---All display data comes directly from the WoW API via Snapshot-Diff.
local function OnReputationGained(event, data)
    if not data or not data.factionID then return end
    
    -- Check if notifications enabled (master toggle + specific toggle)
    local notifs = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not notifs or not notifs.enabled or not notifs.showReputationGains then
        return
    end
    
    -- All display data is in the event payload (from PROCESSED DB after FullScan)
    local factionName = data.factionName or ("Faction " .. data.factionID)
    local gainAmount = data.gainAmount or 0
    local currentRep = data.currentRep or 0
    local maxRep = data.maxRep or 0
    
    -- Faction name: always white
    local factionColorHex = COLOR_FACTION
    
    -- Standing display: use standing color if available, otherwise yellow
    local standingName = data.standingName
    local standingHex = COLOR_STANDING
    if data.standingColor then
        standingHex = RGBToHex(data.standingColor)
    end
    
    -- Gain message
    if gainAmount > 0 then
        local message
        if maxRep > 0 then
            -- Format: [WN-Reputation] Faction: +200 (3,000 / 42,000) Standing
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
            -- maxRep=0: faction has no trackable progress (e.g., max standing, header)
            local standingPart = standingName and string.format(" |cff%s%s|r", standingHex, standingName) or ""
            message = string.format(
                "%s|cff%s%s|r: |cff%s+%s|r%s",
                PREFIX_REPUTATION,
                factionColorHex, factionName,
                COLOR_GAIN, FormatNumber(gainAmount),
                standingPart
            )
        end
        QueueMessage(message)
    end
    
    -- Standing change notification (separate queued message)
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
        QueueMessage(standingMessage)
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

-- Module loaded (silent)
