--[[
    Warband Nexus - Guild Bank Scanner
    Handles scanning and caching of Guild bank contents
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS
local FRAME_BUDGET_MS = Constants.FRAME_BUDGET_MS or 8
local issecretvalue = issecretvalue
local L = ns.L
local Utilities = ns.Utilities
local DebugVerbosePrint = ns.DebugVerbosePrint or function() end
local function CmpItemName(a, b)
    return (Utilities and Utilities.SafeLower and Utilities:SafeLower(a.name) or "") < (Utilities and Utilities.SafeLower and Utilities:SafeLower(b.name) or "")
end

-- Local references for performance
local wipe = wipe
local pairs = pairs
local tinsert = table.insert

-- Minimal logging for operations (disabled)
local function LogOperation(operationName, status, trigger)
    -- Logging disabled
end

-- Supersede in-flight chunked scans (new ScanGuildBank or close invalidates via guildBankIsOpen check)
local guildBankScanGeneration = 0
local MAX_GUILDBANK_SLOTS_PER_TAB = 98

-- Scan Guild Bank (frame-budgeted; returns true when a scan run is scheduled / validations pass)
function WarbandNexus:ScanGuildBank()
    DebugVerbosePrint("|cff888888[Guild Bank Scanner]|r ScanGuildBank() called")
    
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Character not tracked")
        return false
    end
    
    LogOperation("Guild Bank Scan", "Started", self.currentTrigger or "Manual")
    
    if not self.guildBankIsOpen then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Guild bank not open (guildBankIsOpen=false)")
        return false
    end
    
    if not IsInGuild() then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Player not in a guild")
        return false
    end
    
    local guildName = GetGuildInfo("player")
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Could not get guild name")
        return false
    end
    
    DebugVerbosePrint("|cff00ff00[Guild Bank Scanner]|r Starting scan for guild: " .. guildName)
    
    -- Initialize guild bank structure in global DB (guild bank is shared across characters)
    if not self.db.global.guildBank then
        self.db.global.guildBank = {}
    end
    
    if not self.db.global.guildBank[guildName] then
        local scanBy = UnitName("player")
        if scanBy and issecretvalue and issecretvalue(scanBy) then scanBy = nil end
        self.db.global.guildBank[guildName] = { 
            tabs = {},
            lastScan = 0,
            scannedBy = scanBy
        }
    end
    
    local guildData = self.db.global.guildBank[guildName]
    
    local numTabs = GetNumGuildBankTabs()
    
    if not numTabs or numTabs == 0 then
        return false
    end

    guildBankScanGeneration = guildBankScanGeneration + 1
    local myGen = guildBankScanGeneration

    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0

    local tabIndex = 1
    local slotID = 0
    local tabItemsBuilding = nil

    local function finalizeSuccess()
        guildData.lastScan = time()
        do
            local scanBy = UnitName("player")
            guildData.scannedBy = (scanBy and not (issecretvalue and issecretvalue(scanBy))) and scanBy or nil
        end
        guildData.totalItems = totalItems
        guildData.totalSlots = totalSlots
        guildData.usedSlots = usedSlots
        local guildGold = GetGuildBankMoney()
        if guildGold then
            guildData.cachedGold = guildGold
            guildData.goldLastUpdated = time()
        end
        DebugVerbosePrint("|cff00ff00[Guild Bank Scanner]|r Scan completed: " .. totalItems .. " items in " .. usedSlots .. " slots")
        LogOperation("Guild Bank Scan", "Finished", self.currentTrigger or "Manual")
        self:SendMessage(E.ITEMS_UPDATED)
    end

    local function processChunk()
        if myGen ~= guildBankScanGeneration then return end
        if not self.guildBankIsOpen then return end
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then return end

        local budgetStart = debugprofilestop()

        while (debugprofilestop() - budgetStart) < FRAME_BUDGET_MS do
            if myGen ~= guildBankScanGeneration then return end
            if not self.guildBankIsOpen then return end

            if tabIndex > numTabs then
                finalizeSuccess()
                return
            end

            if slotID == 0 then
                local name, icon, isViewable = GetGuildBankTabInfo(tabIndex)
                if not isViewable then
                    tabIndex = tabIndex + 1
                else
                    totalSlots = totalSlots + MAX_GUILDBANK_SLOTS_PER_TAB
                    if not guildData.tabs[tabIndex] then
                        guildData.tabs[tabIndex] = { name = name, icon = icon, items = {} }
                    else
                        guildData.tabs[tabIndex].name = name
                        guildData.tabs[tabIndex].icon = icon
                    end
                    tabItemsBuilding = {}
                    slotID = 1
                end
            else
                local tabData = guildData.tabs[tabIndex]
                if not tabData or not tabItemsBuilding then
                    tabIndex = tabIndex + 1
                    slotID = 0
                else
                    local itemLink = GetGuildBankItemLink(tabIndex, slotID)
                    if itemLink then
                        local texture, itemCount, locked = GetGuildBankItemInfo(tabIndex, slotID)
                        local itemID = nil
                        if type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
                            itemID = tonumber(itemLink:match("item:(%d+)"))
                        end
                        if itemID then
                            usedSlots = usedSlots + 1
                            totalItems = totalItems + (itemCount or 1)
                            local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                                  _, _, itemTexture, _, classID, subclassID = C_Item.GetItemInfo(itemID)
                            tabItemsBuilding[slotID] = {
                                itemID = itemID,
                                itemLink = itemLink,
                                name = itemName or ((ns.L and ns.L["UNKNOWN"]) or UNKNOWN or "Unknown"),
                                link = itemLink,
                                stackCount = itemCount or 1,
                                quality = itemQuality or 0,
                                itemLevel = itemLevel or 0,
                                itemType = itemType or "",
                                itemSubType = itemSubType or "",
                                iconFileID = texture or itemTexture,
                                classID = classID or 0,
                                subclassID = subclassID or 0
                            }
                        end
                    end
                    slotID = slotID + 1
                    if slotID > MAX_GUILDBANK_SLOTS_PER_TAB then
                        tabData.items = tabItemsBuilding
                        tabItemsBuilding = nil
                        tabIndex = tabIndex + 1
                        slotID = 0
                    end
                end
            end
        end

        C_Timer.After(0, processChunk)
    end

    C_Timer.After(0, processChunk)
    return true
end

---Abort in-flight chunked guild bank scan (window closed or superseded).
function WarbandNexus:InvalidateGuildBankScan()
    guildBankScanGeneration = guildBankScanGeneration + 1
end

--[[
    Get all Warband bank items as a flat list
    Groups by item category if requested
    v2: Uses GetWarbandBankV2() with fallback to current session data
]]

--[[
    Get all Guild Bank items as a flat list
]]
function WarbandNexus:GetGuildBankItems(groupByCategory)
    local items = {}
    local guildName = GetGuildInfo("player")
    
    -- Debug: Check guild status
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        -- Not in a guild (or name unavailable as plain string)
        return items
    end
    
    if not self.db.global.guildBank then
        -- Guild bank data structure doesn't exist
        return items
    end
    
    if not self.db.global.guildBank[guildName] then
        -- This guild hasn't been scanned yet
        -- Prompt user to open guild bank
        return items
    end
    
    local guildData = self.db.global.guildBank[guildName]
    
    -- Iterate through all tabs
    for tabIndex, tabData in pairs(guildData.tabs or {}) do
        for slotID, itemData in pairs(tabData.items or {}) do
            -- Copy item data and add metadata
            local item = {}
            for k, v in pairs(itemData) do
                item[k] = v
            end
            item.tabIndex = tabIndex
            item.slotID = slotID
            item.source = "guild"
            item.tabName = tabData.name
            tinsert(items, item)
        end
    end
    
    -- Sort by quality (highest first), then name
    table.sort(items, function(a, b)
        if (a.quality or 0) ~= (b.quality or 0) then
            return (a.quality or 0) > (b.quality or 0)
        end
        return CmpItemName(a, b)
    end)
    
    if groupByCategory then
        return self:GroupItemsByCategory(items)
    end
    
    return items
end

--[[
    Group items by category (classID)
]]
function WarbandNexus:GroupItemsByCategory(items)
    local groups = {}
    local categoryNames = {
        [0] = "Consumables",
        [1] = "Containers",
        [2] = "Weapons",
        [3] = "Gems",
        [4] = "Armor",
        [5] = "Reagents",
        [7] = "Trade Goods",
        [9] = "Recipes",
        [12] = "Quest Items",
        [15] = "Miscellaneous",
        [16] = "Glyphs",
        [17] = "Battle Pets",
        [18] = "WoW Token",
        [19] = "Profession",
    }
    
    for i = 1, #items do
        local item = items[i]
        local classID = item.classID or 15  -- Default to Miscellaneous
        local categoryName = categoryNames[classID] or "Other"
        
        if not groups[categoryName] then
            groups[categoryName] = {
                name = categoryName,
                classID = classID,
                items = {},
                expanded = true,
            }
        end
        
        tinsert(groups[categoryName].items, item)
    end
    
    -- Convert to array and sort
    local result = {}
    for _, group in pairs(groups) do
        tinsert(result, group)
    end
    
    table.sort(result, function(a, b)
        return a.name < b.name
    end)
    
    return result
end

-- Reputation scanning and metadata: Handled by ReputationCacheService.lua
