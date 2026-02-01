--[[
    Warband Nexus - Items Cache Service
    Smart bag/bank scanning with hash-based change detection
    
    Architecture:
    - Hash-based BAG_UPDATE filtering (ignore durability/charges/cooldown changes)
    - Event-based bank frame detection (only scan when bank is open)
    - DB-backed persistence (per-character storage)
    - Throttled updates (2s spam prevention)
    
    Events fired:
    - WN_ITEMS_UPDATED: Bag/bank contents changed (UI should refresh)
    
    Events handled:
    - BAG_UPDATE(bagID) - Fires on item add/remove/move/durability/charges
    - BANKFRAME_OPENED - Bank UI opened
    - BANKFRAME_CLOSED - Bank UI closed
    - PLAYERREAGENTBANKSLOTS_CHANGED - Reagent bank changed
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Get library references for compression
local LibSerialize = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local Constants = ns.Constants
local CACHE_VERSION = Constants.ITEMS_CACHE_VERSION
local UPDATE_THROTTLE = Constants.THROTTLE.PERSONAL_FREQUENT

-- Bag ID ranges
local INVENTORY_BAGS = ns.INVENTORY_BAGS or {0, 1, 2, 3, 4, 5} -- Includes reagent bag
local BANK_BAGS = ns.PERSONAL_BANK_BAGS or {-1, 6, 7, 8, 9, 10, 11}
local WARBAND_BAGS = ns.WARBAND_BAGS or {13, 14, 15, 16, 17}

-- ============================================================================
-- STATE MANAGEMENT
-- ============================================================================

-- Bank frame state (event-based detection)
local isBankOpen = false
local isWarbandBankOpen = false

-- Hash cache for bag change detection (RAM only)
local bagHashCache = {} -- [bagID] = hash

-- Throttle timers
local lastUpdateTime = {}
local pendingUpdates = {}

-- Decompressed cache (in-memory, fast access)
local decompressedCache = {
    personalBanks = {}, -- [charKey] = bankData
    warbandBank = nil,  -- warband bank data
}

-- ============================================================================
-- COMPRESSION UTILITIES
-- ============================================================================

---Compress item data for storage
---@param data table Item data
---@return string|nil compressed Compressed string or nil on failure
local function CompressItemData(data)
    if not LibSerialize or not LibDeflate then
        return nil
    end
    
    if not data or type(data) ~= "table" then
        return nil
    end
    
    -- Serialize
    local serialized = LibSerialize:Serialize(data)
    if not serialized then
        return nil
    end
    
    -- Compress
    local compressed = LibDeflate:CompressDeflate(serialized)
    if not compressed then
        return nil
    end
    
    -- Encode for storage
    local encoded = LibDeflate:EncodeForPrint(compressed)
    if not encoded then
        return nil
    end
    
    return encoded
end

---Decompress item data from storage
---@param compressed string Compressed string
---@return table|nil data Decompressed data or nil on failure
local function DecompressItemData(compressed)
    if not LibSerialize or not LibDeflate then
        return nil
    end
    
    if not compressed or type(compressed) ~= "string" then
        return nil
    end
    
    -- Decode
    local decoded = LibDeflate:DecodeForPrint(compressed)
    if not decoded then
        return nil
    end
    
    -- Decompress
    local decompressed = LibDeflate:DecompressDeflate(decoded)
    if not decompressed then
        return nil
    end
    
    -- Deserialize
    local success, data = LibSerialize:Deserialize(decompressed)
    if not success or type(data) ~= "table" then
        return nil
    end
    
    return data
end

-- ============================================================================
-- HASH GENERATION (CHANGE DETECTION)
-- ============================================================================

---Generate hash for a bag to detect real changes
---Hash includes: item count + item links (ignores durability, charges, cooldowns)
---@param bagID number Bag ID
---@return string hash Hash string
local function GenerateItemHash(bagID)
    local items = {}
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    
    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
        if itemInfo and itemInfo.hyperlink then
            -- Hash includes: hyperlink + stack count
            -- Does NOT include: durability, charges, cooldowns
            table.insert(items, itemInfo.hyperlink .. ":" .. (itemInfo.stackCount or 1))
        end
    end
    
    return table.concat(items, "|")
end

---Check if bag contents actually changed (not just durability/charges)
---@param bagID number Bag ID
---@return boolean changed True if contents changed
local function HasBagChanged(bagID)
    local newHash = GenerateItemHash(bagID)
    local oldHash = bagHashCache[bagID]
    
    if newHash ~= oldHash then
        bagHashCache[bagID] = newHash
        return true
    end
    
    return false
end

-- ============================================================================
-- BAG SCANNING
-- ============================================================================

---Scan a specific bag and return item data
---@param bagID number Bag ID
---@return table items Array of item data
local function ScanBag(bagID)
    local items = {}
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    
    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
        if itemInfo and itemInfo.hyperlink then
            local itemID = C_Item.GetItemInfoInstant(itemInfo.hyperlink)
            
            if itemID then
                -- Get full item info from API (some values may be nil, cache not loaded yet)
                local itemName, itemLink, itemQuality, itemLevel, itemMinLevel, itemType, itemSubType, 
                      itemStackCount, itemEquipLoc, itemTexture, sellPrice, classID, subclassID = C_Item.GetItemInfo(itemInfo.hyperlink)
                
                -- Fallback: if API returns nil (not cached), use basic info
                if not itemName then
                    itemName = itemInfo.hyperlink:match("%[(.-)%]") or ("Item " .. itemID)
                end
                
                table.insert(items, {
                    -- CRITICAL: Use consistent field names with DataService
                    actualBagID = bagID,     -- For UI display
                    bagID = bagID,           -- Legacy compatibility
                    slotIndex = slot,        -- For UI display
                    slot = slot,             -- Legacy compatibility
                    itemID = itemID,
                    name = itemName,         -- Item name (for UI)
                    link = itemInfo.hyperlink,
                    stackCount = itemInfo.stackCount or 1,
                    quality = itemInfo.quality,
                    iconFileID = itemInfo.iconFileID,
                    isBound = itemInfo.isBound or false,
                    -- Category info (for UI grouping) - may be nil if not cached
                    itemType = itemType or "Miscellaneous",
                    classID = classID,
                    subclassID = subclassID,
                })
            end
        end
    end
    
    return items
end

---Scan all inventory bags for current character
---@param charKey string Character key
function WarbandNexus:ScanInventoryBags(charKey)
    if not charKey then
        charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    end
    
    local allItems = {}
    
    -- Scan ALL inventory bags
    for _, bagID in ipairs(INVENTORY_BAGS) do
        local bagItems = ScanBag(bagID)
        print(string.format("|cff9370DB[WN ItemsCache]|r Inventory BagID %d: %d items", bagID, #bagItems))
        for _, item in ipairs(bagItems) do
            table.insert(allItems, item)
        end
    end
    
    -- Save to DB (compressed)
    print(string.format("|cff00ff00[WN ItemsCache]|r Saving %d inventory items for %s", #allItems, charKey))
    self:SaveItemsCompressed(charKey, "bags", allItems)
    
    return allItems
end

---Scan all bank bags for current character
---@param charKey string Character key
function WarbandNexus:ScanBankBags(charKey)
    if not charKey then
        charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    end
    
    local allItems = {}
    
    -- Scan ALL bank bags (NO FLAG CHECK - just scan)
    for _, bagID in ipairs(BANK_BAGS) do
        local bagItems = ScanBag(bagID)
        print(string.format("|cff9370DB[WN ItemsCache]|r BagID %d: %d items", bagID, #bagItems))
        for _, item in ipairs(bagItems) do
            table.insert(allItems, item)
        end
    end
    
    -- Save to DB (compressed)
    print(string.format("|cff00ff00[WN ItemsCache]|r Saving %d bank items for %s", #allItems, charKey))
    self:SaveItemsCompressed(charKey, "bank", allItems)
    
    return allItems
end

---Scan warband bank
function WarbandNexus:ScanWarbandBank()
    local allItems = {}
    
    -- Scan ALL warband bank tabs (NO FLAG CHECK - just scan)
    for tabIndex, bagID in ipairs(WARBAND_BAGS) do
        local bagItems = ScanBag(bagID)
        print(string.format("|cff9370DB[WN ItemsCache]|r Warband Tab %d (BagID %d): %d items", tabIndex, bagID, #bagItems))
        for _, item in ipairs(bagItems) do
            -- Add tab index for warband bank (1-5)
            item.tabIndex = tabIndex
            table.insert(allItems, item)
        end
    end
    
    -- Save to global (compressed, warband bank is account-wide)
    print(string.format("|cff00ff00[WN ItemsCache]|r Saving %d warband bank items", #allItems))
    self:SaveWarbandBankCompressed(allItems)
    
    return allItems
end

-- ============================================================================
-- THROTTLED UPDATE SYSTEM
-- ============================================================================

---Throttled bag update (prevents BAG_UPDATE spam)
---@param bagID number Bag ID
local function ThrottledBagUpdate(bagID)
    local currentTime = GetTime()
    local lastUpdate = lastUpdateTime[bagID] or 0
    
    if currentTime - lastUpdate < UPDATE_THROTTLE then
        -- Schedule pending update
        pendingUpdates[bagID] = true
        return
    end
    
    lastUpdateTime[bagID] = currentTime
    pendingUpdates[bagID] = nil
    
    -- Determine bag type and scan
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    
    -- Check if it's an inventory bag
    for _, invBagID in ipairs(INVENTORY_BAGS) do
        if bagID == invBagID then
            WarbandNexus:ScanInventoryBags(charKey)
            WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "inventory", charKey = charKey})
            return
        end
    end
    
    -- Check if it's a bank bag
    for _, bankBagID in ipairs(BANK_BAGS) do
        if bagID == bankBagID then
            if isBankOpen then
                WarbandNexus:ScanBankBags(charKey)
                WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "bank", charKey = charKey})
            end
            return
        end
    end
    
    -- Check if it's a warband bag
    for _, warbandBagID in ipairs(WARBAND_BAGS) do
        if bagID == warbandBagID then
            if isWarbandBankOpen then
                WarbandNexus:ScanWarbandBank()
                WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "warband"})
            end
            return
        end
    end
end

---Process pending bag updates (called by timer)
function WarbandNexus:ProcessPendingBagUpdates()
    for bagID, _ in pairs(pendingUpdates) do
        ThrottledBagUpdate(bagID)
    end
end

-- ============================================================================
-- EVENT HANDLERS (Will be registered by EventManager)
-- ============================================================================

---Handle BAG_UPDATE event (with smart filtering)
---@param bagID number Bag ID
function WarbandNexus:OnBagUpdate(event, bagID)
    if not bagID then return end
    
    -- Smart filter: Check if bag contents actually changed
    if not HasBagChanged(bagID) then
        -- Ignore: only durability/charges/cooldown changed
        return
    end
    
    -- Real change detected: item added/removed/moved
    ThrottledBagUpdate(bagID)
end

---Handle BANKFRAME_OPENED event
function WarbandNexus:OnBankOpened()
    print("|cff00ff00[WN ItemsCache]|r ===== BANK OPENED =====")
    isBankOpen = true
    isWarbandBankOpen = true
    
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    print(string.format("|cff9370DB[WN ItemsCache]|r CharKey: %s", charKey))
    
    -- 1. SCAN INVENTORY (for Personal Items tab)
    print("|cff9370DB[WN ItemsCache]|r Scanning Inventory Bags...")
    self:ScanInventoryBags(charKey)
    
    -- 2. SCAN BANK (for Personal Items tab)
    print("|cff9370DB[WN ItemsCache]|r Scanning Personal Bank...")
    self:ScanBankBags(charKey)
    
    -- 3. SCAN WARBAND BANK (for Warband Bank tab)
    print("|cff9370DB[WN ItemsCache]|r Scanning Warband Bank...")
    self:ScanWarbandBank()
    
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "all", charKey = charKey})
    
    print("|cff00ff00[WN ItemsCache]|r ===== SCAN COMPLETE =====")
end

---Handle BANKFRAME_CLOSED event
function WarbandNexus:OnBankClosed()
    isBankOpen = false
    isWarbandBankOpen = false  -- Both tabs close together
    print("|cff9370DB[WN ItemsCache]|r Bank closed")
end

---Handle ACCOUNT_BANK_FRAME_OPENED event (Warband Bank tab switched)
function WarbandNexus:OnWarbandBankFrameOpened()
    -- This fires when user switches to Warband Bank TAB (bank already open)
    -- Re-scan to catch any changes
    self:ScanWarbandBank()
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "warband"})
    
    print("|cff9370DB[WN ItemsCache]|r Warband Bank tab switched, re-scanning...")
end

---Handle ACCOUNT_BANK_FRAME_CLOSED event (Warband Bank tab closed)
function WarbandNexus:OnWarbandBankFrameClosed()
    -- Tab switched away, but bank might still be open
    -- Don't change isWarbandBankOpen here (managed by BANKFRAME_CLOSED)
    print("|cff9370DB[WN ItemsCache]|r Warband Bank tab closed")
end

---Handle PLAYERREAGENTBANKSLOTS_CHANGED event
function WarbandNexus:OnReagentBankChanged()
    -- Reagent bank is part of bank (bag 5)
    if isBankOpen then
        ThrottledBagUpdate(5) -- Reagent bag ID
    end
end

-- ============================================================================
-- COMPRESSED STORAGE (SAVE/LOAD)
-- ============================================================================

---Save items data (compressed)
---@param charKey string Character key
---@param dataType string "bags" or "bank"
---@param items table Items array
function WarbandNexus:SaveItemsCompressed(charKey, dataType, items)
    if not charKey or not dataType or not items then return end
    
    -- Initialize structure
    if not self.db.global.itemStorage then
        self.db.global.itemStorage = {}
    end
    
    if not self.db.global.itemStorage[charKey] then
        self.db.global.itemStorage[charKey] = {}
    end
    
    -- Compress data
    local compressed = CompressItemData(items)
    if not compressed then
        -- Fallback: store uncompressed
        self.db.global.itemStorage[charKey][dataType] = {
            compressed = false,
            data = items,
            lastUpdate = time()
        }
        return
    end
    
    -- Store compressed
    self.db.global.itemStorage[charKey][dataType] = {
        compressed = true,
        data = compressed,
        lastUpdate = time()
    }
    
    -- Invalidate decompressed cache
    decompressedCache.personalBanks[charKey] = nil
end

---Save warband bank data (compressed)
---@param items table Items array
function WarbandNexus:SaveWarbandBankCompressed(items)
    if not items then return end
    
    -- Initialize structure
    if not self.db.global.itemStorage then
        self.db.global.itemStorage = {}
    end
    
    -- Compress data
    local compressed = CompressItemData(items)
    if not compressed then
        -- Fallback: store uncompressed
        self.db.global.itemStorage.warbandBank = {
            compressed = false,
            data = items,
            lastUpdate = time()
        }
        return
    end
    
    -- Store compressed
    self.db.global.itemStorage.warbandBank = {
        compressed = true,
        data = compressed,
        lastUpdate = time()
    }
    
    -- Invalidate decompressed cache
    decompressedCache.warbandBank = nil
end

-- ============================================================================
-- PUBLIC API (FOR UI AND DATASERVICE)
-- ============================================================================

---Get items data for a specific character (decompressed)
---@param charKey string Character key
---@return table data {bags, bank, lastUpdate}
function WarbandNexus:GetItemsData(charKey)
    -- Check in-memory cache first (FAST PATH)
    if decompressedCache.personalBanks[charKey] then
        return decompressedCache.personalBanks[charKey]
    end
    
    -- Check if new storage system exists
    if not self.db.global.itemStorage or not self.db.global.itemStorage[charKey] then
        -- Fallback: legacy storage (uncompressed)
        if self.db.global.characters and self.db.global.characters[charKey] then
            local charData = self.db.global.characters[charKey]
            local result = {
                bags = charData.items or {},
                bank = charData.bank or {},
                bagsLastUpdate = charData.itemsLastUpdate or 0,
                bankLastUpdate = charData.bankLastUpdate or 0,
            }
            -- Cache it
            decompressedCache.personalBanks[charKey] = result
            return result
        end
        
        -- No data found (silent - expected for new/unscanned characters)
        return {bags = {}, bank = {}, bagsLastUpdate = 0, bankLastUpdate = 0}
    end
    
    -- Decompress from new storage
    local storage = self.db.global.itemStorage[charKey]
    local result = {
        bags = {},
        bank = {},
        bagsLastUpdate = 0,
        bankLastUpdate = 0,
    }
    
    -- Decompress bags
    if storage.bags then
        if storage.bags.compressed then
            result.bags = DecompressItemData(storage.bags.data) or {}
        else
            result.bags = storage.bags.data or {}
        end
        result.bagsLastUpdate = storage.bags.lastUpdate or 0
    end
    
    -- Decompress bank
    if storage.bank then
        if storage.bank.compressed then
            result.bank = DecompressItemData(storage.bank.data) or {}
        else
            result.bank = storage.bank.data or {}
        end
        result.bankLastUpdate = storage.bank.lastUpdate or 0
    end
    
    -- Cache decompressed data
    decompressedCache.personalBanks[charKey] = result
    
    return result
end

---Get warband bank data (decompressed)
---@return table data {items, lastUpdate}
function WarbandNexus:GetWarbandBankData()
    -- Check in-memory cache first (FAST PATH)
    if decompressedCache.warbandBank then
        return decompressedCache.warbandBank
    end
    
    -- Check if new storage system exists
    if not self.db.global.itemStorage or not self.db.global.itemStorage.warbandBank then
        -- Fallback: legacy storage
        if self.db.global.warbandBank then
            local result = {
                items = self.db.global.warbandBank.items or {},
                lastUpdate = self.db.global.warbandBank.lastUpdate or 0,
            }
            decompressedCache.warbandBank = result
            return result
        end
        
        return {items = {}, lastUpdate = 0}
    end
    
    -- Decompress from new storage
    local storage = self.db.global.itemStorage.warbandBank
    local result = {
        items = {},
        lastUpdate = 0,
    }
    
    if storage.compressed then
        result.items = DecompressItemData(storage.data) or {}
    else
        result.items = storage.data or {}
    end
    result.lastUpdate = storage.lastUpdate or 0
    
    -- Cache decompressed data
    decompressedCache.warbandBank = result
    
    return result
end

---Force refresh all bags (ignore cache)
function WarbandNexus:RefreshAllBags()
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    
    -- Clear hash cache to force scan
    bagHashCache = {}
    
    -- Scan all
    self:ScanInventoryBags(charKey)
    
    if isBankOpen then
        self:ScanBankBags(charKey)
    end
    
    if isWarbandBankOpen then
        self:ScanWarbandBank()
    end
    
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "all", charKey = charKey})
    print("|cff00ff00[WN ItemsCache]|r Force refresh complete")
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize items cache on login
function WarbandNexus:InitializeItemsCache()
    -- Scan inventory bags on login (bank requires manual visit)
    C_Timer.After(2, function()
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
        self:ScanInventoryBags(charKey)
        print("|cff00ff00[WN ItemsCache]|r Initial inventory scan complete")
    end)
end

-- ============================================================================
-- LOAD MESSAGE
-- ============================================================================

print("|cff00ff00[WN ItemsCache]|r Loaded successfully")
print("|cff9370DB[WN ItemsCache]|r Features: Hash-based change detection, Event-based bank scanning")
print("|cff9370DB[WN ItemsCache]|r Cache version: " .. CACHE_VERSION)
