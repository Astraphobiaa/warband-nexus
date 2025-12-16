--[[
    Warband Nexus - Scanner Module
    Handles scanning and caching of Warband bank contents
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local L = ns.L

-- Local references for performance
local wipe = wipe
local pairs = pairs
local ipairs = ipairs
local tinsert = table.insert

-- Recycled table for temporary data (avoid garbage collection)
local tempItemData = {}

--[[
    Scan the entire Warband bank
    Iterates through all tabs and slots, caching item information
]]
function WarbandNexus:ScanWarbandBank()
    -- Verify bank is open
    if not self:IsWarbandBankOpen() then
        self:Print(L["SCAN_FAILED"])
        return false
    end
    
    self:Debug(L["SCAN_STARTED"])
    
    -- Initialize cache if needed
    if not self.db.global.warbandCache then
        self.db.global.warbandCache = {}
    end
    
    -- Wipe existing cache to prevent stale data
    wipe(self.db.global.warbandCache)
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Iterate through all Warband bank tabs
    for tabIndex, bagID in ipairs(ns.WARBAND_BAGS) do
        -- Skip ignored tabs
        if not self.db.profile.ignoredTabs[tabIndex] then
            self:Debug(string.format(L["SCAN_TAB"], tabIndex))
            
            -- Initialize tab cache
            self.db.global.warbandCache[tabIndex] = {}
            
            local numSlots = self:GetBagSize(bagID)
            totalSlots = totalSlots + numSlots
            
            -- Iterate through all slots in this tab
            for slotID = 1, numSlots do
                local itemInfo = self:GetContainerItemInfo(bagID, slotID)
                
                if itemInfo and itemInfo.itemID then
                    usedSlots = usedSlots + 1
                    totalItems = totalItems + (itemInfo.stackCount or 1)
                    
                    -- Store item data
                    self.db.global.warbandCache[tabIndex][slotID] = {
                        itemID = itemInfo.itemID,
                        itemLink = itemInfo.hyperlink,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality,
                        isLocked = itemInfo.isLocked,
                        isBound = itemInfo.isBound,
                        iconFileID = itemInfo.iconFileID,
                    }
                    
                    -- Cache extended item info for offline viewing
                    self:CacheItemInfo(itemInfo.itemID, itemInfo.hyperlink)
                end
            end
        end
    end
    
    -- Update statistics
    self.db.global.stats.totalScans = (self.db.global.stats.totalScans or 0) + 1
    self.db.global.stats.lastScanTime = time()
    
    -- Store slot statistics
    self.db.global.stats.totalSlots = totalSlots
    self.db.global.stats.usedSlots = usedSlots
    self.db.global.stats.freeSlots = totalSlots - usedSlots
    
    self:Print(string.format(L["SCAN_COMPLETE"], totalItems, usedSlots))
    
    -- Trigger UI refresh if available
    if self.RefreshUI then
        self:RefreshUI()
    end
    
    return true
end

--[[
    Get container item info with modern API
    Wrapper for C_Container.GetContainerItemInfo
    @param bagID number The bag ID
    @param slotID number The slot ID
    @return table|nil Item information table
]]
---@param bagID number The bag ID (Enum.BagIndex)
---@param slotID number The slot ID
---@return table|nil itemInfo The item information table
function WarbandNexus:GetContainerItemInfo(bagID, slotID)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bagID, slotID)
    end
    return nil
end

--[[
    Cache extended item information for offline viewing
    @param itemID number The item ID
    @param itemLink string The item hyperlink
]]
function WarbandNexus:CacheItemInfo(itemID, itemLink)
    if not itemID then return end
    
    -- Skip if already cached
    if self.db.global.itemDB[itemID] then return end
    
    -- Get item info (may return nil if not cached by client)
    local itemName, _, itemQuality, itemLevel, itemMinLevel, itemType, 
          itemSubType, itemStackCount, itemEquipLoc, itemTexture, 
          sellPrice, classID, subclassID, bindType, expansionID, 
          setID, isCraftingReagent = C_Item.GetItemInfo(itemLink or itemID)
    
    if itemName then
        self.db.global.itemDB[itemID] = {
            name = itemName,
            quality = itemQuality,
            level = itemLevel,
            minLevel = itemMinLevel,
            type = itemType,
            subType = itemSubType,
            maxStack = itemStackCount,
            equipLoc = itemEquipLoc,
            texture = itemTexture,
            sellPrice = sellPrice,
            classID = classID,
            subclassID = subclassID,
            bindType = bindType,
            isCraftingReagent = isCraftingReagent,
        }
    end
end

--[[
    Get all items from cache matching search criteria
    @param searchTerm string|nil Search string (item name)
    @param filters table|nil Filter options {quality, type, etc.}
    @return table Array of matching items
]]
function WarbandNexus:SearchCachedItems(searchTerm, filters)
    local results = {}
    
    -- Reuse temp table
    wipe(tempItemData)
    
    for tabIndex, tabData in pairs(self.db.global.warbandCache or {}) do
        for slotID, itemData in pairs(tabData) do
            local match = true
            local itemInfo = self.db.global.itemDB[itemData.itemID]
            
            -- Search by name
            if searchTerm and searchTerm ~= "" then
                local itemName = itemInfo and itemInfo.name or ""
                if not string.find(string.lower(itemName), string.lower(searchTerm)) then
                    match = false
                end
            end
            
            -- Apply filters
            if match and filters then
                -- Quality filter
                if filters.minQuality and itemData.quality then
                    if itemData.quality < filters.minQuality then
                        match = false
                    end
                end
                
                -- Type filter
                if filters.classID and itemInfo then
                    if itemInfo.classID ~= filters.classID then
                        match = false
                    end
                end
            end
            
            if match then
                tinsert(results, {
                    tabIndex = tabIndex,
                    slotID = slotID,
                    itemID = itemData.itemID,
                    itemLink = itemData.itemLink,
                    stackCount = itemData.stackCount,
                    quality = itemData.quality,
                    itemInfo = itemInfo,
                })
            end
        end
    end
    
    return results
end

--[[
    Get statistics about the Warband bank
    @return table Statistics table
]]
function WarbandNexus:GetBankStatistics()
    local stats = {
        totalSlots = self.db.global.stats.totalSlots or 0,
        usedSlots = self.db.global.stats.usedSlots or 0,
        freeSlots = self.db.global.stats.freeSlots or 0,
        totalItems = 0,
        totalValue = 0,
        lastScanTime = self.db.global.stats.lastScanTime or 0,
        itemsByQuality = {},
    }
    
    -- Initialize quality counts
    for i = 0, 8 do
        stats.itemsByQuality[i] = 0
    end
    
    -- Calculate totals from cache
    for tabIndex, tabData in pairs(self.db.global.warbandCache or {}) do
        for slotID, itemData in pairs(tabData) do
            stats.totalItems = stats.totalItems + (itemData.stackCount or 1)
            
            -- Count by quality
            local quality = itemData.quality or 0
            stats.itemsByQuality[quality] = (stats.itemsByQuality[quality] or 0) + 1
            
            -- Calculate value
            local itemInfo = self.db.global.itemDB[itemData.itemID]
            if itemInfo and itemInfo.sellPrice then
                stats.totalValue = stats.totalValue + (itemInfo.sellPrice * (itemData.stackCount or 1))
            end
        end
    end
    
    return stats
end

--[[
    Clear the Warband bank cache
]]
function WarbandNexus:ClearCache()
    wipe(self.db.global.warbandCache)
    wipe(self.db.global.itemDB)
    self:Print(L["CACHE_CLEARED"])
end

--[[
    Search items command handler
    @param searchTerm string The search term
]]
function WarbandNexus:SearchItems(searchTerm)
    if not searchTerm or searchTerm == "" then
        self:Print("Usage: /wn search <item name>")
        return
    end
    
    local results = self:SearchCachedItems(searchTerm)
    
    if #results == 0 then
        self:Print("No items found matching: " .. searchTerm)
        return
    end
    
    self:Print("Found " .. #results .. " items matching '" .. searchTerm .. "':")
    
    for i, item in ipairs(results) do
        if i <= 10 then -- Limit output
            local tabName = L["TAB_" .. item.tabIndex] or ("Tab " .. item.tabIndex)
            self:Print(string.format("  %s x%d (%s, Slot %d)", 
                item.itemLink or ("Item #" .. item.itemID),
                item.stackCount,
                tabName,
                item.slotID
            ))
        end
    end
    
    if #results > 10 then
        self:Print("  ... and " .. (#results - 10) .. " more")
    end
end

--[[
    Personal Bank Bag IDs
    BANK = -1 (main bank slots)
    BANKBAG_1 through BANKBAG_7 = bank bags
    REAGENTBANK = -3
]]
local PERSONAL_BANK_BAGS = {
    Enum.BagIndex.Bank,           -- Main bank
    Enum.BagIndex.BankBag_1,
    Enum.BagIndex.BankBag_2,
    Enum.BagIndex.BankBag_3,
    Enum.BagIndex.BankBag_4,
    Enum.BagIndex.BankBag_5,
    Enum.BagIndex.BankBag_6,
    Enum.BagIndex.BankBag_7,
    Enum.BagIndex.Reagentbank,    -- Reagent bank
}

--[[
    Check if Personal (Character) bank is currently open
    @return boolean
]]
function WarbandNexus:IsPersonalBankOpen()
    if C_Bank and C_Bank.IsOpen then
        return C_Bank.IsOpen(Enum.BankType.Character)
    end
    return false
end

--[[
    Scan the Personal (Character) bank
    Iterates through all bank bags and slots, caching item information
]]
function WarbandNexus:ScanPersonalBank()
    -- Verify bank is open
    if not self:IsPersonalBankOpen() then
        self:Print(L["PERSONAL_BANK_NOT_OPEN"])
        return false
    end
    
    self:Debug(L["PERSONAL_SCAN_STARTED"])
    
    -- Initialize cache if needed
    if not self.db.char.personalBankCache then
        self.db.char.personalBankCache = {}
    end
    
    -- Wipe existing cache to prevent stale data
    wipe(self.db.char.personalBankCache)
    
    local totalItems = 0
    local totalSlots = 0
    local usedSlots = 0
    
    -- Iterate through all Personal bank bags
    for _, bagID in ipairs(PERSONAL_BANK_BAGS) do
        local numSlots = self:GetBagSize(bagID)
        
        -- Skip bags with 0 slots (not purchased)
        if numSlots > 0 then
            self:Debug(string.format("Scanning personal bank bag %d (%d slots)", bagID, numSlots))
            
            -- Initialize bag cache
            self.db.char.personalBankCache[bagID] = {}
            
            totalSlots = totalSlots + numSlots
            
            -- Iterate through all slots in this bag
            for slotID = 1, numSlots do
                local itemInfo = self:GetContainerItemInfo(bagID, slotID)
                
                if itemInfo and itemInfo.itemID then
                    usedSlots = usedSlots + 1
                    totalItems = totalItems + (itemInfo.stackCount or 1)
                    
                    -- Store item data
                    self.db.char.personalBankCache[bagID][slotID] = {
                        itemID = itemInfo.itemID,
                        itemLink = itemInfo.hyperlink,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality,
                        isLocked = itemInfo.isLocked,
                        isBound = itemInfo.isBound,
                        iconFileID = itemInfo.iconFileID,
                    }
                    
                    -- Cache extended item info for offline viewing
                    self:CacheItemInfo(itemInfo.itemID, itemInfo.hyperlink)
                end
            end
        end
    end
    
    -- Update personal bank statistics
    self.db.char.personalBankStats = {
        totalSlots = totalSlots,
        usedSlots = usedSlots,
        freeSlots = totalSlots - usedSlots,
        lastScanTime = time(),
    }
    
    self:Print(string.format(L["PERSONAL_SCAN_COMPLETE"], totalItems, usedSlots))
    
    -- Trigger UI refresh if available
    if self.RefreshUI then
        self:RefreshUI()
    end
    
    return true
end

--[[
    Get statistics about the Personal bank
    @return table Statistics table
]]
function WarbandNexus:GetPersonalBankStatistics()
    local stats = self.db.char.personalBankStats or {
        totalSlots = 0,
        usedSlots = 0,
        freeSlots = 0,
        lastScanTime = 0,
    }
    
    local totalItems = 0
    local totalValue = 0
    local itemsByQuality = {}
    
    -- Initialize quality counts
    for i = 0, 8 do
        itemsByQuality[i] = 0
    end
    
    -- Calculate totals from cache
    for bagID, bagData in pairs(self.db.char.personalBankCache or {}) do
        for slotID, itemData in pairs(bagData) do
            totalItems = totalItems + (itemData.stackCount or 1)
            
            -- Count by quality
            local quality = itemData.quality or 0
            itemsByQuality[quality] = (itemsByQuality[quality] or 0) + 1
            
            -- Calculate value
            local itemInfo = self.db.global.itemDB[itemData.itemID]
            if itemInfo and itemInfo.sellPrice then
                totalValue = totalValue + (itemInfo.sellPrice * (itemData.stackCount or 1))
            end
        end
    end
    
    stats.totalItems = totalItems
    stats.totalValue = totalValue
    stats.itemsByQuality = itemsByQuality
    
    return stats
end


