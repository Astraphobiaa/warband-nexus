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

-- Supersede in-flight chunked scans (new ScanGuildBank or close invalidates via guildBankIsOpen check)
local guildBankScanGeneration = 0
local MAX_GUILDBANK_SLOTS_PER_TAB = 98
local activeScanCtx = nil

local function RecomputeGuildBankTotals(guildData)
    if not guildData then
        return 0, 0, 0
    end
    local totalItems, usedSlots = 0, 0
    for _, tabData in pairs(guildData.tabs or {}) do
        for _, itemData in pairs(tabData.items or {}) do
            usedSlots = usedSlots + 1
            totalItems = totalItems + (itemData.stackCount or 1)
        end
    end
    local totalSlots = guildData.totalSlots or 0
    if totalSlots < usedSlots then
        totalSlots = usedSlots
    end
    return totalItems, usedSlots, totalSlots
end

--- How many purchased guild bank tabs the current character may view (GetGuildBankTabInfo isViewable).
function WarbandNexus:CountViewableGuildBankTabs(numTabs)
    numTabs = numTabs or GetNumGuildBankTabs() or 0
    if numTabs <= 0 then
        return 0
    end
    local count = 0
    for tabIndex = 1, numTabs do
        local _, _, isViewable = GetGuildBankTabInfo(tabIndex)
        if isViewable then
            count = count + 1
        end
    end
    return count
end

-- Scan Guild Bank (frame-budgeted).
-- Returns success, and optional errCode ("no_viewable_tabs" when cache must be preserved).
function WarbandNexus:ScanGuildBank()
    DebugVerbosePrint("|cff888888[Guild Bank Scanner]|r ScanGuildBank() called")
    
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Character not tracked")
        return false, "not_tracked"
    end

    if not self.guildBankIsOpen then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Guild bank not open (guildBankIsOpen=false)")
        return false, "not_open"
    end
    
    if not IsInGuild() then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Player not in a guild")
        return false, "not_in_guild"
    end
    
    local guildName = GetGuildInfo("player")
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        ns.DebugPrint("|cffff6600[Guild Bank Scanner]|r Could not get guild name")
        return false, "no_guild_name"
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
        return false, "no_tabs"
    end

    local viewableTabCount = self:CountViewableGuildBankTabs(numTabs)
    if viewableTabCount == 0 then
        -- Character has no guild-bank tab view rights; never overwrite a scan from another alt.
        DebugVerbosePrint("|cffff9900[Guild Bank Scanner]|r No viewable tabs for this character — preserving cache")
        return false, "no_viewable_tabs"
    end

    guildBankScanGeneration = guildBankScanGeneration + 1
    local myGen = guildBankScanGeneration
    activeScanCtx = { myGen = myGen, guildData = guildData, tabIndex = 1, slotID = 0, tabItemsBuilding = nil }

    local scannedViewableTabs = 0
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0

    local tabIndex = 1
    local slotID = 0
    local tabItemsBuilding = nil

    local function finalizeSuccess()
        activeScanCtx = nil
        if scannedViewableTabs <= 0 then
            DebugVerbosePrint("|cffff9900[Guild Bank Scanner]|r Scan finished with no viewable tabs — cache unchanged")
            return
        end
        guildData.lastScan = time()
        do
            local scanBy = UnitName("player")
            guildData.scannedBy = (scanBy and not (issecretvalue and issecretvalue(scanBy))) and scanBy or nil
        end
        guildData.totalSlots = math.max(guildData.totalSlots or 0, totalSlots)
        local recomputedItems, recomputedUsed, recomputedSlots = RecomputeGuildBankTotals(guildData)
        guildData.totalItems = recomputedItems
        guildData.usedSlots = recomputedUsed
        guildData.totalSlots = math.max(guildData.totalSlots or 0, recomputedSlots, totalSlots)
        local guildGold = GetGuildBankMoney()
        if guildGold then
            guildData.cachedGold = guildGold
            guildData.goldLastUpdated = time()
        end
        DebugVerbosePrint("|cff00ff00[Guild Bank Scanner]|r Scan completed: " .. recomputedItems .. " items in " .. recomputedUsed .. " slots")
        ns._gearStorageInvGen = (ns._gearStorageInvGen or 0) + 1
        self:SendMessage(E.ITEMS_UPDATED)
    end

    local function syncScanCtx()
        if activeScanCtx and activeScanCtx.myGen == myGen then
            activeScanCtx.tabIndex = tabIndex
            activeScanCtx.slotID = slotID
            activeScanCtx.tabItemsBuilding = tabItemsBuilding
        end
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
                    scannedViewableTabs = scannedViewableTabs + 1
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

        syncScanCtx()
        C_Timer.After(0, processChunk)
    end

    C_Timer.After(0, processChunk)
    return true, nil
end

---Abort in-flight chunked guild bank scan (window closed or superseded).
function WarbandNexus:InvalidateGuildBankScan()
    guildBankScanGeneration = guildBankScanGeneration + 1
    activeScanCtx = nil
end

---Persist partial guild bank tab progress on PLAYER_LOGOUT.
function WarbandNexus:FlushGuildBankScanOnLogout()
    if activeScanCtx and activeScanCtx.myGen == guildBankScanGeneration then
        local ctx = activeScanCtx
        if ctx.tabItemsBuilding and ctx.guildData and ctx.guildData.tabs and ctx.tabIndex then
            local tabData = ctx.guildData.tabs[ctx.tabIndex]
            if tabData then
                tabData.items = ctx.tabItemsBuilding
            end
        end
        guildBankScanGeneration = guildBankScanGeneration + 1
    end
    activeScanCtx = nil
end

--- Flat list for one guild row in db.global.guildBank[guildName] (tab/slot metadata attached).
function WarbandNexus:CollectGuildBankItemsFlat(guildName, guildData)
    local items = {}
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        return items
    end
    guildData = guildData or (self.db.global.guildBank and self.db.global.guildBank[guildName])
    if not guildData then
        return items
    end
    for tabIndex, tabData in pairs(guildData.tabs or {}) do
        for slotID, itemData in pairs(tabData.items or {}) do
            local item = {}
            for k, v in pairs(itemData) do
                item[k] = v
            end
            item.tabIndex = tabIndex
            item.slotID = slotID
            item.source = "guild"
            item.guildName = guildName
            item.tabName = (tabData and tabData.name) or nil
            tinsert(items, item)
        end
    end
    table.sort(items, function(a, b)
        if (a.quality or 0) ~= (b.quality or 0) then
            return (a.quality or 0) > (b.quality or 0)
        end
        return CmpItemName(a, b)
    end)
    return items
end

--- True when db.global.guildBank has at least one scanned guild (any character).
function WarbandNexus:HasGuildBankCache()
    local gb = self.db and self.db.global and self.db.global.guildBank
    if not gb then
        return false
    end
    for guildName, guildData in pairs(gb) do
        if guildName and not (issecretvalue and issecretvalue(guildName)) and type(guildData) == "table" then
            if (guildData.lastScan or 0) > 0 or (guildData.usedSlots or 0) > 0 then
                return true
            end
            for _, tabData in pairs(guildData.tabs or {}) do
                if tabData.items and next(tabData.items) then
                    return true
                end
            end
        end
    end
    return false
end

--- Guild Bank sub-tab: live guild membership or any account-wide cached scan.
function WarbandNexus:CanViewGuildBankTab()
    if IsInGuild() then
        return true
    end
    return self:HasGuildBankCache()
end

--- Roll up item/slot/gold stats across every cached guild (Items > Guild header).
function WarbandNexus:GetGuildBankCacheAggregateStats()
    local stats = {
        itemCount = 0,
        usedSlots = 0,
        totalSlots = 0,
        lastScan = 0,
        cachedGold = nil,
        goldLastUpdated = 0,
    }
    local entries = self:GetGuildBankSortedEntries()
    for i = 1, #entries do
        local gd = entries[i].data
        if gd then
            stats.usedSlots = stats.usedSlots + (gd.usedSlots or 0)
            stats.totalSlots = stats.totalSlots + (gd.totalSlots or 0)
            stats.lastScan = math.max(stats.lastScan, gd.lastScan or 0)
            for _, tabData in pairs(gd.tabs or {}) do
                for _, itemData in pairs(tabData.items or {}) do
                    stats.itemCount = stats.itemCount + (itemData.stackCount or 1)
                end
            end
            local goldUpdated = gd.goldLastUpdated or 0
            if gd.cachedGold and goldUpdated >= stats.goldLastUpdated then
                stats.cachedGold = gd.cachedGold
                stats.goldLastUpdated = goldUpdated
            end
        end
    end
    if stats.totalSlots < stats.usedSlots then
        stats.totalSlots = stats.usedSlots
    end
    return stats
end

--- Sorted { name, data } entries for every scanned guild (account-wide cache).
function WarbandNexus:GetGuildBankSortedEntries()
    local out = {}
    local gb = self.db.global.guildBank
    if not gb then
        return out
    end
    for guildName, guildData in pairs(gb) do
        if guildName and not (issecretvalue and issecretvalue(guildName)) and guildData then
            out[#out + 1] = { name = guildName, data = guildData }
        end
    end
    table.sort(out, function(a, b)
        return (Utilities and Utilities.SafeLower and Utilities:SafeLower(a.name) or "")
            < (Utilities and Utilities.SafeLower and Utilities:SafeLower(b.name) or "")
    end)
    return out
end

--[[
    Get Guild Bank items as a flat list (current guild when guildName omitted).
]]
function WarbandNexus:GetGuildBankItems(groupByCategory, guildName)
    local items = {}
    if not guildName then
        guildName = GetGuildInfo("player")
    end
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        return items
    end
    if not self.db.global.guildBank or not self.db.global.guildBank[guildName] then
        return items
    end
    items = self:CollectGuildBankItemsFlat(guildName, self.db.global.guildBank[guildName])
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

--[[
    Guild membership cleanup policy (account-wide guild bank cache):

    db.global.guildBank[guildName] is shared across all characters. When the logged-in
    character leaves guild A or switches to guild B, we remove guildBank[A] only if no
    other row in db.global.characters still has guildName == A (excluding the current
    character row, which is updated after this runs). If an alt remains in A, their
    cached scan is preserved.

    Skips cleanup when IsInGuild() is true but GetGuildInfo("player") is nil/secret
    (API not ready on loading screens — see warcraft.wiki.gg/wiki/API_GetGuildInfo).
]]

--- Safe current guild name for "player", or nil when not in a guild / name unavailable.
---@return string? guildName
---@return boolean ambiguous True when still in a guild but name could not be read safely
function WarbandNexus:GetSafePlayerGuildName()
    if not IsInGuild() then
        return nil, false
    end
    local guildName = GetGuildInfo("player")
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        return nil, true
    end
    return guildName, false
end

--- Count character rows listing guildName (optionally excluding one storage key).
function WarbandNexus:CountCharactersInGuild(guildName, excludeCharKey)
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        return 0
    end
    local chars = self.db and self.db.global and self.db.global.characters
    if not chars then
        return 0
    end
    local count = 0
    local want = Utilities and Utilities.SafeLower and Utilities:SafeLower(guildName) or guildName
    for charKey, charData in pairs(chars) do
        if charKey ~= excludeCharKey and charData and charData.guildName then
            local rowGn = charData.guildName
            if not (issecretvalue and issecretvalue(rowGn)) then
                local cmp = Utilities and Utilities.SafeLower and Utilities:SafeLower(rowGn) or rowGn
                if cmp == want then
                    count = count + 1
                end
            end
        end
    end
    return count
end

--- Remove guild bank cache for guildName when no other character row still references it.
---@return boolean removed
function WarbandNexus:MaybeRemoveGuildBankCache(guildName, excludeCharKey)
    if not guildName or (issecretvalue and issecretvalue(guildName)) then
        return false
    end
    if self:CountCharactersInGuild(guildName, excludeCharKey) > 0 then
        return false
    end
    local gb = self.db.global.guildBank
    if not gb or not gb[guildName] then
        return false
    end
    gb[guildName] = nil
    DebugVerbosePrint("|cffff9900[Guild Bank Scanner]|r Removed stale cache for guild: " .. guildName)
    return true
end

--- Leave or guild-switch: drop old guild cache when no tracked alt remains in that guild.
--- Call before updating the current character row's guildName.
---@param oldGuildName string?
---@param newGuildName string?
---@param charKey string? Current character storage key (excluded from orphan check)
---@return boolean changed Whether cache was removed and listeners should refresh
function WarbandNexus:HandleGuildMembershipChange(oldGuildName, newGuildName, charKey)
    if oldGuildName and (issecretvalue and issecretvalue(oldGuildName)) then
        return false
    end
    if newGuildName and (issecretvalue and issecretvalue(newGuildName)) then
        return false
    end
    if oldGuildName == "" then oldGuildName = nil end
    if newGuildName == "" then newGuildName = nil end
    if not oldGuildName or oldGuildName == newGuildName then
        return false
    end
    -- Player still in a guild but name not readable yet — do not treat as leave.
    if newGuildName == nil and IsInGuild() then
        return false
    end
    local removed = self:MaybeRemoveGuildBankCache(oldGuildName, charKey)
    if removed then
        self:InvalidateGuildBankScan()
        self:SendMessage(E.ITEMS_UPDATED)
    end
    return removed
end

--- Sync logged-in character guildName with API; run orphan guild-bank cleanup when membership changed.
---@return string? oldGuildName
---@return string? newGuildName
---@return boolean ambiguous True when guild name could not be read safely
function WarbandNexus:SyncPlayerGuildMembership()
    local rawKey = ns.Utilities and ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)
    if not rawKey then
        return nil, nil, true
    end
    local tableKey = rawKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local resolved = ns.CharacterService:ResolveCharactersTableKey(self)
        if resolved then
            tableKey = resolved
        end
    end
    local chars = self.db and self.db.global and self.db.global.characters
    if not chars or not chars[tableKey] then
        return nil, nil, true
    end
    local charData = chars[tableKey]
    local oldGn = charData.guildName
    local newGn, ambiguous = self:GetSafePlayerGuildName()
    if ambiguous then
        return oldGn, nil, true
    end
    self:HandleGuildMembershipChange(oldGn, newGn, tableKey)
    if oldGn ~= newGn then
        charData.guildName = newGn
        charData.lastSeen = time()
        if ns.CharacterService and ns.CharacterService:IsCharacterTracked(self) then
            local msgKey = (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(self)) or rawKey
            if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
                msgKey = ns.Utilities:GetCanonicalCharacterKey(msgKey) or msgKey
            end
            self:SendMessage(E.CHARACTER_UPDATED, { charKey = msgKey, dataType = "guild" })
        end
    end
    return oldGn, newGn, false
end

-- Reputation scanning and metadata: Handled by ReputationCacheService.lua
