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

-- Minimal logging for operations
local function LogOperation(operationName, status, trigger)
    local timestamp = date("%H:%M")
    print(string.format("%s - %s → %s (%s)", timestamp, operationName, status, trigger or "Manual"))
end

--[[
    Scan the entire Warband bank
    Stores data in global.warbandBank (shared across all characters)
]]
function WarbandNexus:ScanWarbandBank()
    LogOperation("Warband Bank Scan", "Started", self.currentTrigger or "Manual")
    
    -- Verify bank is open
    local isOpen = self:IsWarbandBankOpen()
    
    if not isOpen then
        -- Try direct bag check using API wrapper
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        local numSlots = self:API_GetBagSize(firstBagID)
        
        if not numSlots or numSlots == 0 then
            return false
        end
    end
    
    -- Initialize structure if needed
    if not self.db.global.warbandBank then
        self.db.global.warbandBank = { items = {}, gold = 0, lastScan = 0 }
    end
    if not self.db.global.warbandBank.items then
        self.db.global.warbandBank.items = {}
    end
    
    -- Clear existing cache
    wipe(self.db.global.warbandBank.items)
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Iterate through all Warband bank tabs
    for tabIndex, bagID in ipairs(ns.WARBAND_BAGS) do
        self.db.global.warbandBank.items[tabIndex] = {}
        
        -- Use API wrapper (TWW compatible)
        local numSlots = self:API_GetBagSize(bagID)
        totalSlots = totalSlots + numSlots
        
        for slotID = 1, numSlots do
            -- Use API wrapper (TWW compatible)
            local itemInfo = self:API_GetContainerItemInfo(bagID, slotID)
            
            if itemInfo and itemInfo.itemID then
                usedSlots = usedSlots + 1
                totalItems = totalItems + (itemInfo.stackCount or 1)
                
                -- Get extended item info using API wrapper (TWW compatible)
                local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType, 
                      _, _, itemTexture, _, classID, subclassID = self:API_GetItemInfo(itemInfo.itemID)
                
                -- Special handling for Battle Pets (classID 17)
                -- Extract pet name from hyperlink: |Hbattlepet:speciesID:...|h[Pet Name]|h|r
                local displayName = itemName
                local displayIcon = itemInfo.iconFileID or itemTexture
                
                if classID == 17 and itemInfo.hyperlink then
                    -- Try to extract pet name from hyperlink
                    local petName = itemInfo.hyperlink:match("%[(.-)%]")
                    if petName and petName ~= "" and petName ~= "Pet Cage" then
                        displayName = petName
                        
                        -- Try to get actual pet icon from speciesID
                        local speciesID = tonumber(itemInfo.hyperlink:match("|Hbattlepet:(%d+):"))
                        if speciesID and C_PetJournal then
                            local _, petIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                            if petIcon then
                                displayIcon = petIcon
                            end
                        end
                    end
                end
                
                self.db.global.warbandBank.items[tabIndex][slotID] = {
                    itemID = itemInfo.itemID,
                    itemLink = itemInfo.hyperlink,
                    stackCount = itemInfo.stackCount or 1,
                    quality = itemInfo.quality or itemQuality or 0,
                    iconFileID = displayIcon,
                    -- Extended info
                    name = displayName,
                    itemLevel = itemLevel,
                    itemType = itemType,
                    itemSubType = itemSubType,
                    classID = classID,
                    subclassID = subclassID,
                }
            end
        end
    end
    
    -- Update metadata
    self.db.global.warbandBank.lastScan = time()
    self.db.global.warbandBank.totalSlots = totalSlots
    self.db.global.warbandBank.usedSlots = usedSlots
    
    -- Get Warband bank gold
    if C_Bank and C_Bank.FetchDepositedMoney then
        self.db.global.warbandBank.gold = C_Bank.FetchDepositedMoney(Enum.BankType.Account) or 0
    end
    
    -- Mark scan as successful
    self.lastScanSuccess = true
    self.lastScanTime = time()
    
    LogOperation("Warband Bank Scan", "Finished", self.currentTrigger or "Manual")
    
    -- Refresh UI to show "Up-to-Date" status
    if self.RefreshUI then
        self:RefreshUI()
    end
    
    return true
end

--[[
    Scan Personal bank (character-specific)
    Stores data in char.personalBank
]]
function WarbandNexus:ScanPersonalBank()
    LogOperation("Personal Bank Scan", "Started", self.currentTrigger or "Manual")
    
    -- Try to verify bank is accessible by checking slot count using API wrapper
    local mainBankSlots = self:API_GetBagSize(Enum.BagIndex.Bank or -1)
    
    -- If we believe bank is open (bankIsOpen=true), we should try to scan even if slots look empty initially
    -- (Sometimes API lags slightly or requires a frame update)
    if mainBankSlots == 0 then
        if not self.bankIsOpen then
            -- ... existing cache check code ...
            local hasCache = self.db.char.personalBank and self.db.char.personalBank.items
            if hasCache then
               -- ...
            end
            return false
        end
    end
    
    -- Initialize structure
    if not self.db.char.personalBank then
        self.db.char.personalBank = { items = {}, lastScan = 0 }
    end
    if not self.db.char.personalBank.items then
        self.db.char.personalBank.items = {}
    end
    
    -- Clear existing cache ONLY because we confirmed bank is accessible
    wipe(self.db.char.personalBank.items)
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Iterate through personal bank bags
    for bagIndex, bagID in ipairs(ns.PERSONAL_BANK_BAGS) do
        self.db.char.personalBank.items[bagIndex] = {}
        
        -- Use API wrapper (TWW compatible)
        local numSlots = self:API_GetBagSize(bagID)
        totalSlots = totalSlots + numSlots
        
        local bagItemCount = 0
        for slotID = 1, numSlots do
            -- Use API wrapper (TWW compatible)
            local itemInfo = self:API_GetContainerItemInfo(bagID, slotID)
            
            if itemInfo and itemInfo.itemID then
                usedSlots = usedSlots + 1
                totalItems = totalItems + (itemInfo.stackCount or 1)
                bagItemCount = bagItemCount + 1
                
                -- Use API wrapper (TWW compatible)
                local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                      _, _, itemTexture, _, classID, subclassID = self:API_GetItemInfo(itemInfo.itemID)
                
                -- Special handling for Battle Pets (classID 17)
                -- Extract pet name from hyperlink: |Hbattlepet:speciesID:...|h[Pet Name]|h|r
                local displayName = itemName
                local displayIcon = itemInfo.iconFileID or itemTexture
                
                if classID == 17 and itemInfo.hyperlink then
                    -- Try to extract pet name from hyperlink
                    local petName = itemInfo.hyperlink:match("%[(.-)%]")
                    if petName and petName ~= "" and petName ~= "Pet Cage" then
                        displayName = petName
                        
                        -- Try to get actual pet icon from speciesID
                        local speciesID = tonumber(itemInfo.hyperlink:match("|Hbattlepet:(%d+):"))
                        if speciesID and C_PetJournal then
                            local _, petIcon = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
                            if petIcon then
                                displayIcon = petIcon
                            end
                        end
                    end
                end
                
                self.db.char.personalBank.items[bagIndex][slotID] = {
                    itemID = itemInfo.itemID,
                    itemLink = itemInfo.hyperlink,
                    stackCount = itemInfo.stackCount or 1,
                    quality = itemInfo.quality or itemQuality or 0,
                    iconFileID = displayIcon,
                    name = displayName,
                    itemLevel = itemLevel,
                    itemType = itemType,
                    itemSubType = itemSubType,
                    classID = classID,
                    subclassID = subclassID,
                    actualBagID = bagID, -- Store the actual bag ID for item movement
                }
            end
        end
    end
    
    -- Update metadata
    self.db.char.personalBank.lastScan = time()
    self.db.char.personalBank.totalSlots = totalSlots
    self.db.char.personalBank.usedSlots = usedSlots
    
    -- Mark scan as successful
    self.lastScanSuccess = true
    self.lastScanTime = time()
    
    LogOperation("Personal Bank Scan", "Finished", self.currentTrigger or "Manual")
    
    -- Copy to global database for Storage tab
    if self.SaveCurrentCharacterData then
        self:SaveCurrentCharacterData()
    end
    
    -- Refresh UI to show "Up-to-Date" status
    if self.RefreshUI then
        self:RefreshUI()
    end
    
    return true
end

-- Scan Guild Bank
function WarbandNexus:ScanGuildBank()
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
]]
function WarbandNexus:GetWarbandBankItems(groupByCategory)
    local items = {}
    local warbandData = self.db.global.warbandBank
    
    if not warbandData or not warbandData.items then
        return items
    end
    
    for tabIndex, tabData in pairs(warbandData.items) do
        for slotID, itemData in pairs(tabData) do
            itemData.tabIndex = tabIndex
            itemData.slotID = slotID
            itemData.source = "warband"
            tinsert(items, itemData)
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
    Get all Personal bank items as a flat list
]]
function WarbandNexus:GetPersonalBankItems(groupByCategory)
    local items = {}
    local personalData = self.db.char.personalBank
    
    if not personalData or not personalData.items then
        return items
    end
    
    -- Return cached Personal bank items (scan already filtered them correctly)
    for bagIndex, bagData in pairs(personalData.items) do
        for slotID, itemData in pairs(bagData) do
            itemData.bagIndex = bagIndex
            itemData.slotID = slotID
            itemData.source = "personal"
            tinsert(items, itemData)
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

--[[
    Search items in Warband bank
]]
function WarbandNexus:SearchWarbandItems(searchTerm)
    local allItems = self:GetWarbandBankItems()
    local results = {}
    
    if not searchTerm or searchTerm == "" then
        return allItems
    end
    
    searchTerm = searchTerm:lower()
    
    for _, item in ipairs(allItems) do
        if item.name and item.name:lower():find(searchTerm, 1, true) then
            tinsert(results, item)
        end
    end
    
    return results
end

--[[
    Get bank statistics
]]
function WarbandNexus:GetBankStatistics()
    local stats = {
        warband = {
            totalSlots = 0,
            usedSlots = 0,
            freeSlots = 0,
            itemCount = 0,
            gold = 0,
            lastScan = 0,
        },
        personal = {
            totalSlots = 0,
            usedSlots = 0,
            freeSlots = 0,
            itemCount = 0,
            lastScan = 0,
        },
        guild = {
            totalSlots = 0,
            usedSlots = 0,
            freeSlots = 0,
            itemCount = 0,
            lastScan = 0,
        },
    }
    
    -- Warband stats
    local warbandData = self.db.global.warbandBank
    if warbandData then
        stats.warband.totalSlots = warbandData.totalSlots or 0
        stats.warband.usedSlots = warbandData.usedSlots or 0
        stats.warband.freeSlots = stats.warband.totalSlots - stats.warband.usedSlots
        stats.warband.gold = warbandData.gold or 0
        stats.warband.lastScan = warbandData.lastScan or 0
        
        -- Count items
        for _, tabData in pairs(warbandData.items or {}) do
            for _, itemData in pairs(tabData) do
                stats.warband.itemCount = stats.warband.itemCount + (itemData.stackCount or 1)
            end
        end
    end
    
    -- Personal stats
    local personalData = self.db.char.personalBank
    if personalData then
        stats.personal.totalSlots = personalData.totalSlots or 0
        stats.personal.usedSlots = personalData.usedSlots or 0
        stats.personal.freeSlots = stats.personal.totalSlots - stats.personal.usedSlots
        stats.personal.lastScan = personalData.lastScan or 0
        
        for _, bagData in pairs(personalData.items or {}) do
            for _, itemData in pairs(bagData) do
                stats.personal.itemCount = stats.personal.itemCount + (itemData.stackCount or 1)
            end
        end
    end
    
    -- Guild Bank stats
    local guildName = GetGuildInfo("player")
    if guildName and self.db.global.guildBank and self.db.global.guildBank[guildName] then
        local guildData = self.db.global.guildBank[guildName]
        stats.guild.totalSlots = guildData.totalSlots or 0
        stats.guild.usedSlots = guildData.usedSlots or 0
        stats.guild.freeSlots = stats.guild.totalSlots - stats.guild.usedSlots
        stats.guild.lastScan = guildData.lastScan or 0
        
        -- Count items from all tabs
        for _, tabData in pairs(guildData.tabs or {}) do
            for _, itemData in pairs(tabData.items or {}) do
                stats.guild.itemCount = stats.guild.itemCount + (itemData.stackCount or 1)
            end
        end
    end
    
    return stats
end

--[[
    Helper function to get table keys for debugging
]]
function WarbandNexus:GetTableKeys(tbl)
    local keys = {}
    if type(tbl) == "table" then
        for k, v in pairs(tbl) do
            table.insert(keys, tostring(k) .. "=" .. tostring(v))
        end
    end
    return keys
end

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
                        -- First child under top-level parent → append
                        table.insert(headerStack, factionData.name)
                    elseif #headerStack == 2 then
                        -- Already have a child header, this is a sibling → replace
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
    Scan Reputations (Modern approach with metadata separation)
    Stores only progress data in char.reputations
]]
function WarbandNexus:ScanReputations()
    LogOperation("Rep Scan", "Started", self.currentTrigger or "Manual")
    
    -- Get current character key
    local playerKey = UnitName("player") .. "-" .. GetRealmName()
    
    -- Initialize character data if needed
    if not self.db.global.characters[playerKey] then
        self.db.global.characters[playerKey] = {}
    end
    
    if not self.db.global.characters[playerKey].reputations then
        self.db.global.characters[playerKey].reputations = {}
    end
    
    -- Build metadata first (only adds new factions, doesn't overwrite)
    self:BuildFactionMetadata()
    
    local reputations = {}
    local headers = {}
    
    -- ========================================
    -- PART 1: Scan Classic Reputation System (Modern C_Reputation API)
    -- ========================================
    
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
    
    local currentHeader = nil
    local currentHeaderFactions = {}
    
    for i = 1, numFactions do
        local factionData = C_Reputation.GetFactionDataByIndex(i)
        
        if not factionData or not factionData.name then
            break
        end
        
        -- Handle headers (for non-filtered mode)
        if factionData.isHeader then
            -- Only create new top-level header if NOT isHeaderWithRep
            -- isHeaderWithRep headers (Cartels, Severed) are subfactions under their parent
            if not factionData.isHeaderWithRep then
                -- Save previous header if exists
                if currentHeader then
                    table.insert(headers, {
                        name = currentHeader,
                        index = #headers + 1,
                        isCollapsed = false,
                        factions = currentHeaderFactions,
                    })
                end
                
                -- Start new header
                currentHeader = factionData.name
                currentHeaderFactions = {}
            end
        end
        
        -- Process faction (regular factions OR isHeaderWithRep factions)
        -- Skip pure headers that don't have reputation
        if factionData.factionID and (not factionData.isHeader or factionData.isHeaderWithRep) then
            -- Calculate reputation progress
            local currentValue, maxValue
            local renownLevel, renownMaxLevel = nil, nil
            local isMajorFaction = false
            
            -- Check if this is a Renown faction AND if character has it unlocked
            -- Use GetMajorFactionRenownInfo as validation - returns nil if not unlocked
            local isRenownFaction = false
            if C_MajorFactions and C_MajorFactions.GetMajorFactionRenownInfo then
                local renownInfo = C_MajorFactions.GetMajorFactionRenownInfo(factionData.factionID)
                if renownInfo then  -- nil = not unlocked for this character
                    isRenownFaction = true
                    isMajorFaction = true
                    -- Try both possible field names (API inconsistency)
                    renownLevel = renownInfo.renownLevel or renownInfo.currentRenownLevel or 0
                    
                    -- Get correct max renown level (faction-specific)
                    if C_MajorFactions.GetMaximumRenownLevel then
                        renownMaxLevel = C_MajorFactions.GetMaximumRenownLevel(factionData.factionID) or 25
                    else
                        renownMaxLevel = 25  -- Fallback
                    end
                    
                    -- Get accurate renown progress within current level
                    if C_MajorFactions.HasMaximumRenown and C_MajorFactions.HasMaximumRenown(factionData.factionID) then
                        currentValue = 0
                        maxValue = 1
                    else
                        -- Use renownInfo for accurate progress
                        currentValue = renownInfo.renownReputationEarned or 0
                        maxValue = renownInfo.renownLevelThreshold or 1
                    end
                end
                -- If renownInfo is nil, faction is not unlocked - SKIP (do not store)
            end
            
            -- If not a Renown faction, check if it's inactive (classic reputation)
            if not isRenownFaction then
                local isInactive = false
                if factionData.isInactive ~= nil then
                    isInactive = factionData.isInactive
                elseif C_Reputation.IsFactionInactive then
                    local success, result = pcall(C_Reputation.IsFactionInactive, i)
                    if success then
                        isInactive = result or false
                    end
                end
                
                -- Only process if NOT inactive
                if not isInactive then
                    -- Use classic reputation calculation
                    currentValue = factionData.currentStanding - factionData.currentReactionThreshold
                    maxValue = factionData.nextReactionThreshold - factionData.currentReactionThreshold
                end
            end
            
            -- Only store if faction is valid (Renown unlocked OR classic non-inactive)
            if isRenownFaction or (not isRenownFaction and currentValue) then
                -- Check Paragon
                local paragonValue, paragonThreshold, paragonRewardPending = nil, nil, nil
                if C_Reputation.IsFactionParagon and C_Reputation.IsFactionParagon(factionData.factionID) then
                    local pValue, pThreshold, rewardQuestID, hasRewardPending = C_Reputation.GetFactionParagonInfo(factionData.factionID)
                    if pValue and pThreshold then
                        paragonValue = pValue % pThreshold
                        paragonThreshold = pThreshold
                        paragonRewardPending = hasRewardPending or false
                    end
                end
                
                -- Store ONLY progress data (metadata is separate)
                -- For Major Factions: no standingID (Renown doesn't use standings)
                reputations[factionData.factionID] = {
                    standingID = isMajorFaction and nil or factionData.reaction,  -- nil for Renown
                    currentValue = currentValue,
                    maxValue = maxValue,
                    renownLevel = renownLevel,
                    renownMaxLevel = renownMaxLevel,
                    paragonValue = paragonValue,
                    paragonThreshold = paragonThreshold,
                    paragonRewardPending = paragonRewardPending,
                    isWatched = factionData.isWatched or false,
                    atWarWith = factionData.atWarWith or false,
                    isMajorFaction = isMajorFaction,  -- Flag to prevent duplicate display
                    lastUpdated = time(),
                }
                
                -- Add to current header's factions
                if currentHeader then
                    table.insert(currentHeaderFactions, factionData.factionID)
                end
            end
        end
    end
    
    -- Save last header
    if currentHeader then
        table.insert(headers, {
            name = currentHeader,
            index = #headers + 1,
            isCollapsed = false,
            factions = currentHeaderFactions,
        })
    end
    
    -- Save to database
    self.db.global.characters[playerKey].reputations = reputations
    self.db.global.characters[playerKey].reputationHeaders = headers
    self.db.global.characters[playerKey].reputationsLastScan = time()
    
    -- Invalidate cache
    self:InvalidateReputationCache(playerKey)
    
    LogOperation("Rep Scan", "Finished", self.currentTrigger or "Manual")
    return true
end

--[[
    Categorize reputation (DEPRECATED - now using isRenown flag only)
    This function is kept minimal for backward compatibility
    @param factionID number
    @return isRenown boolean (true if Major Faction/Renown, false otherwise)
]]
function WarbandNexus:CategorizeReputation(factionID)
    -- Future-proof: Only check if it's a Renown faction using API
    -- No hardcoded expansion lists or faction ID ranges
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local majorData = C_MajorFactions.GetMajorFactionData(factionID)
        if majorData then
            return true  -- Is a Renown/Major Faction
        end
    end
    
    return false  -- Regular reputation
end