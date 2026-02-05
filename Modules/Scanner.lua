--[[
    Warband Nexus - Scanner Module
    Handles scanning and caching of Warband bank and Personal bank contents
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Local references for performance
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert

-- Minimal logging for operations (disabled)
local function LogOperation(operationName, status, trigger)
    -- Logging disabled
end

-- Scan Guild Bank
function WarbandNexus:ScanGuildBank()
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end
    
    LogOperation("Guild Bank Scan", "Started", self.currentTrigger or "Manual")
    
    -- Check if guild bank is accessible
    if not self.guildBankIsOpen then
        return false
    end
    
    -- Check if player is in a guild
    if not IsInGuild() then
        return false
    end
    
    -- Get guild name for storage key
    local guildName = GetGuildInfo("player")
    if not guildName then
        return false
    end
    
    -- Initialize guild bank structure in global DB (guild bank is shared across characters)
    if not self.db.global.guildBank then
        self.db.global.guildBank = {}
    end
    
    if not self.db.global.guildBank[guildName] then
        self.db.global.guildBank[guildName] = { 
            tabs = {},
            lastScan = 0,
            scannedBy = UnitName("player")
        }
    end
    
    local guildData = self.db.global.guildBank[guildName]
    
    -- Get number of tabs (player might not have access to all)
    local numTabs = GetNumGuildBankTabs()
    
    if not numTabs or numTabs == 0 then
        return false
    end
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Scan all tabs
    for tabIndex = 1, numTabs do
        -- Check if player has view permission for this tab
        local name, icon, isViewable, canDeposit, numWithdrawals = GetGuildBankTabInfo(tabIndex)
        
        if isViewable then
            if not guildData.tabs[tabIndex] then
                guildData.tabs[tabIndex] = {
                    name = name,
                    icon = icon,
                    items = {}
                }
            else
                -- Update tab info and clear items
                guildData.tabs[tabIndex].name = name
                guildData.tabs[tabIndex].icon = icon
                wipe(guildData.tabs[tabIndex].items)
            end
            
            local tabData = guildData.tabs[tabIndex]
            
            -- Guild bank has 98 slots per tab (14 columns x 7 rows)
            local MAX_GUILDBANK_SLOTS_PER_TAB = 98
            totalSlots = totalSlots + MAX_GUILDBANK_SLOTS_PER_TAB
            
            for slotID = 1, MAX_GUILDBANK_SLOTS_PER_TAB do
                local itemLink = GetGuildBankItemLink(tabIndex, slotID)
                
                if itemLink then
                    local texture, itemCount, locked = GetGuildBankItemInfo(tabIndex, slotID)
                    
                    -- Extract itemID from link
                    local itemID = tonumber(itemLink:match("item:(%d+)"))
                    
                    if itemID then
                        usedSlots = usedSlots + 1
                        totalItems = totalItems + (itemCount or 1)
                        
                        -- Get item info using API wrapper
                        local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                              _, _, itemTexture, _, classID, subclassID = self:API_GetItemInfo(itemID)
                        
                        -- Store item data
                        tabData.items[slotID] = {
                            itemID = itemID,
                            itemLink = itemLink,
                            itemName = itemName or "Unknown",
                            stackCount = itemCount or 1,
                            quality = itemQuality or 0,
                            itemLevel = itemLevel or 0,
                            itemType = itemType or "",
                            itemSubType = itemSubType or "",
                            icon = texture or itemTexture,
                            classID = classID or 0,
                            subclassID = subclassID or 0
                        }
                    end
                end
            end
        end
    end
    
    -- Update metadata
    guildData.lastScan = time()
    guildData.scannedBy = UnitName("player")
    guildData.totalItems = totalItems
    guildData.totalSlots = totalSlots
    guildData.usedSlots = usedSlots
    
    LogOperation("Guild Bank Scan", "Finished", self.currentTrigger or "Manual")
    
    -- Refresh UI
    if self.RefreshUI then
        self:RefreshUI()
    end
    
    return true
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
    
    if not guildName or not self.db.global.guildBank or not self.db.global.guildBank[guildName] then
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
        return (a.name or "") < (b.name or "")
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
    
    for _, item in ipairs(items) do
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

-- REMOVED: GetTableKeys() - debug helper, only used for debugging

--[[
    Build faction metadata (global, shared across all characters)
    Called once to populate faction information
]]
function WarbandNexus:BuildFactionMetadata()
    if not self.db.global.factionMetadata then
        self.db.global.factionMetadata = {}
    end
    
    local metadata = self.db.global.factionMetadata
    
    -- Check if C_Reputation API is available
    if not C_Reputation or not C_Reputation.GetNumFactions then
        return false
    end
    
    local numFactions = C_Reputation.GetNumFactions()
    if not numFactions or numFactions == 0 then
        return false
    end
    
    -- Expand all headers to get full faction list
    for i = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(i)
        if factionData and factionData.isHeader and factionData.isCollapsed then
            C_Reputation.ExpandFactionHeader(i)
        end
    end
    
    -- Rescan after expansion
    numFactions = C_Reputation.GetNumFactions()
    
    -- Track header stack for proper nested hierarchy (API-driven)
    local headerStack = {}  -- Stack of current headers for nested structure
    
    for i = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(i)
        
        if factionData and factionData.name then
            if factionData.isHeader then
                -- This is a header (might be top-level or nested)
                if factionData.isChild then
                    -- Child header: use depth-based logic for siblings vs nesting
                    if #headerStack == 1 then
                        -- First child under top-level parent â†’ append
                        table.insert(headerStack, factionData.name)
                    elseif #headerStack == 2 then
                        -- Already have a child header, this is a sibling â†’ replace
                        headerStack[2] = factionData.name
                    else
                        -- Safety: reset to parent + this child
                        headerStack = {headerStack[1], factionData.name}
                    end
                else
                    -- Top-level header: reset stack
                    headerStack = {factionData.name}
                end
                
                -- If isHeaderWithRep, ALSO store as faction (e.g., Severed Threads)
                if factionData.isHeaderWithRep and factionData.factionID then
                    -- Check if this is a renown faction
                    local isRenown = false
                    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                        local majorData = C_MajorFactions.GetMajorFactionData(factionData.factionID)
                        isRenown = (majorData ~= nil)
                    end
                    
                    -- Get faction icon
                    local iconTexture = nil
                    if C_Reputation.GetFactionDataByID then
                        local detailedData = C_Reputation.GetFactionDataByID(factionData.factionID)
                        if detailedData and detailedData.texture then
                            iconTexture = detailedData.texture
                        end
                    end
                    
                    -- Store as both header AND faction
                    -- parentHeaders = all parents EXCEPT itself
                    local parentHeaders = {}
                    for j = 1, #headerStack - 1 do
                        table.insert(parentHeaders, headerStack[j])
                    end
                    
                    metadata[factionData.factionID] = {
                        name = factionData.name,
                        description = factionData.description or "",
                        iconTexture = iconTexture,
                        isRenown = isRenown,
                        canToggleAtWar = factionData.canToggleAtWar or false,
                        parentHeaders = parentHeaders,  -- API-driven hierarchy
                        isHeader = true,
                        isHeaderWithRep = true,
                    }
                end
            elseif factionData.factionID and not factionData.isHeader then
                -- Regular faction (not a header)
                -- Only build metadata if not exists
                if not metadata[factionData.factionID] then
                    -- Check if this is a renown faction
                    local isRenown = false
                    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                        local majorData = C_MajorFactions.GetMajorFactionData(factionData.factionID)
                        isRenown = (majorData ~= nil)
                    end
                    
                    -- Get faction icon
                    local iconTexture = nil
                    if C_Reputation.GetFactionDataByID then
                        local detailedData = C_Reputation.GetFactionDataByID(factionData.factionID)
                        if detailedData and detailedData.texture then
                            iconTexture = detailedData.texture
                        end
                    end
                    
                    -- Copy current header path
                    local parentHeaders = {}
                    for j = 1, #headerStack do
                        table.insert(parentHeaders, headerStack[j])
                    end
                    
                    metadata[factionData.factionID] = {
                        name = factionData.name,
                        description = factionData.description or "",
                        iconTexture = iconTexture,
                        isRenown = isRenown,
                        canToggleAtWar = factionData.canToggleAtWar or false,
                        parentHeaders = parentHeaders,  -- Full path from API
                        isHeader = false,
                        isHeaderWithRep = false,
                    }
                end
            end
        end
    end
    
    return true
end

--[[
    DEPRECATED: ScanReputations
    This method is no longer used. Reputation scanning is now handled by ReputationCacheService.
    Kept for backward compatibility.
]]
function WarbandNexus:ScanReputations()
    -- DEPRECATED: ReputationCacheService handles all reputation scanning automatically
    -- This method is kept for backward compatibility with code that still calls it
    return true  -- Return success for compatibility
end-- REMOVED: CategorizeReputation() - deprecated, migration complete