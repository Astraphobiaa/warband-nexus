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

--[[
    Scan the entire Warband bank
    Stores data in global.warbandBank (shared across all characters)
]]
function WarbandNexus:ScanWarbandBank()
    -- Verify bank is open
    local isOpen = self:IsWarbandBankOpen()
    self:Debug("ScanWarbandBank called, IsWarbandBankOpen=" .. tostring(isOpen))
    
    if not isOpen then
        -- Try direct bag check
        local firstBagID = Enum.BagIndex.AccountBankTab_1
        local numSlots = C_Container.GetContainerNumSlots(firstBagID)
        
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
        
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        totalSlots = totalSlots + numSlots
        
        for slotID = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
            
            if itemInfo and itemInfo.itemID then
                usedSlots = usedSlots + 1
                totalItems = totalItems + (itemInfo.stackCount or 1)
                
                -- Get extended item info
                local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType, 
                      _, _, itemTexture, _, classID, subclassID = C_Item.GetItemInfo(itemInfo.itemID)
                
                self.db.global.warbandBank.items[tabIndex][slotID] = {
                    itemID = itemInfo.itemID,
                    itemLink = itemInfo.hyperlink,
                    stackCount = itemInfo.stackCount or 1,
                    quality = itemInfo.quality or itemQuality or 0,
                    iconFileID = itemInfo.iconFileID or itemTexture,
                    -- Extended info
                    name = itemName,
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
    self:Debug("ScanPersonalBank called, bankIsOpen=" .. tostring(self.bankIsOpen))
    
    self:Debug("PBSCAN: PERSONAL_BANK_BAGS count=" .. tostring(#ns.PERSONAL_BANK_BAGS))
    
    -- Try to verify bank is accessible by checking slot count
    local mainBankSlots = C_Container.GetContainerNumSlots(Enum.BagIndex.Bank or -1) or 0
    
    -- If we believe bank is open (bankIsOpen=true), we should try to scan even if slots look empty initially
    -- (Sometimes API lags slightly or requires a frame update)
    if mainBankSlots == 0 then
        if self.bankIsOpen then
            self:Debug("PBSCAN: mainBankSlots=0 but bankIsOpen=true. Forcing scan anyway.")
        else
            self:Debug("PBSCAN: Bank not accessible (slots=0) and bankIsOpen=false - KEEPING CACHED DATA")
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
        
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        totalSlots = totalSlots + numSlots
        
        self:Debug("PBSCAN: Scanning bagIndex=" .. bagIndex .. ", bagID=" .. tostring(bagID) .. ", slots=" .. numSlots)
        
        local bagItemCount = 0
        for slotID = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
            
            if itemInfo and itemInfo.itemID then
                usedSlots = usedSlots + 1
                totalItems = totalItems + (itemInfo.stackCount or 1)
                bagItemCount = bagItemCount + 1
                
                local itemName, _, itemQuality, itemLevel, _, itemType, itemSubType,
                      _, _, itemTexture, _, classID, subclassID = C_Item.GetItemInfo(itemInfo.itemID)
                
                self.db.char.personalBank.items[bagIndex][slotID] = {
                    itemID = itemInfo.itemID,
                    itemLink = itemInfo.hyperlink,
                    stackCount = itemInfo.stackCount or 1,
                    quality = itemInfo.quality or itemQuality or 0,
                    iconFileID = itemInfo.iconFileID or itemTexture,
                    name = itemName,
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
    
    return stats
end
