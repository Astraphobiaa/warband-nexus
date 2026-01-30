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
                table.insert(items, {
                    bagID = bagID,
                    slot = slot,
                    itemID = itemID,
                    link = itemInfo.hyperlink,
                    stackCount = itemInfo.stackCount or 1,
                    quality = itemInfo.quality,
                    iconFileID = itemInfo.iconFileID,
                    isBound = itemInfo.isBound or false,
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
    
    for _, bagID in ipairs(INVENTORY_BAGS) do
        local bagItems = ScanBag(bagID)
        for _, item in ipairs(bagItems) do
            table.insert(allItems, item)
        end
    end
    
    -- Save to DB
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    if not self.db.global.characters[charKey] then
        self.db.global.characters[charKey] = {}
    end
    
    self.db.global.characters[charKey].items = allItems
    self.db.global.characters[charKey].itemsLastUpdate = time()
    
    return allItems
end

---Scan all bank bags for current character (only if bank is open)
---@param charKey string Character key
function WarbandNexus:ScanBankBags(charKey)
    if not isBankOpen then
        return nil -- Don't scan if bank is closed
    end
    
    if not charKey then
        charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    end
    
    local allItems = {}
    
    for _, bagID in ipairs(BANK_BAGS) do
        local bagItems = ScanBag(bagID)
        for _, item in ipairs(bagItems) do
            table.insert(allItems, item)
        end
    end
    
    -- Save to DB
    if not self.db.global.characters then
        self.db.global.characters = {}
    end
    
    if not self.db.global.characters[charKey] then
        self.db.global.characters[charKey] = {}
    end
    
    self.db.global.characters[charKey].bank = allItems
    self.db.global.characters[charKey].bankLastUpdate = time()
    
    return allItems
end

---Scan warband bank (only if warband bank is open)
function WarbandNexus:ScanWarbandBank()
    if not isWarbandBankOpen then
        return nil -- Don't scan if warband bank is closed
    end
    
    local allItems = {}
    
    for _, bagID in ipairs(WARBAND_BAGS) do
        local bagItems = ScanBag(bagID)
        for _, item in ipairs(bagItems) do
            table.insert(allItems, item)
        end
    end
    
    -- Save to global (warband bank is account-wide)
    if not self.db.global.warbandBank then
        self.db.global.warbandBank = {}
    end
    
    self.db.global.warbandBank.items = allItems
    self.db.global.warbandBank.lastUpdate = time()
    
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
function WarbandNexus:OnBankFrameOpened()
    isBankOpen = true
    
    -- Immediate scan on bank open
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    self:ScanBankBags(charKey)
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "bank", charKey = charKey})
    
    print("|cff00ff00[WN ItemsCache]|r Bank opened, scanning...")
end

---Handle BANKFRAME_CLOSED event
function WarbandNexus:OnBankFrameClosed()
    isBankOpen = false
    print("|cff9370DB[WN ItemsCache]|r Bank closed")
end

---Handle ACCOUNT_BANK_FRAME_OPENED event (Warband Bank)
function WarbandNexus:OnWarbandBankFrameOpened()
    isWarbandBankOpen = true
    
    -- Immediate scan on warband bank open
    self:ScanWarbandBank()
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "warband"})
    
    print("|cff00ff00[WN ItemsCache]|r Warband Bank opened, scanning...")
end

---Handle ACCOUNT_BANK_FRAME_CLOSED event (Warband Bank)
function WarbandNexus:OnWarbandBankFrameClosed()
    isWarbandBankOpen = false
    print("|cff9370DB[WN ItemsCache]|r Warband Bank closed")
end

---Handle PLAYERREAGENTBANKSLOTS_CHANGED event
function WarbandNexus:OnReagentBankChanged()
    -- Reagent bank is part of bank (bag 5)
    if isBankOpen then
        ThrottledBagUpdate(5) -- Reagent bag ID
    end
end

-- ============================================================================
-- PUBLIC API (FOR UI AND DATASERVICE)
-- ============================================================================

---Get items data for a specific character
---@param charKey string Character key
---@return table data {items, bank, lastUpdate}
function WarbandNexus:GetItemsData(charKey)
    if not self.db.global.characters or not self.db.global.characters[charKey] then
        return {items = {}, bank = {}, lastUpdate = 0}
    end
    
    local charData = self.db.global.characters[charKey]
    return {
        items = charData.items or {},
        bank = charData.bank or {},
        itemsLastUpdate = charData.itemsLastUpdate or 0,
        bankLastUpdate = charData.bankLastUpdate or 0,
    }
end

---Get warband bank data
---@return table data {items, lastUpdate}
function WarbandNexus:GetWarbandBankData()
    if not self.db.global.warbandBank then
        return {items = {}, lastUpdate = 0}
    end
    
    return {
        items = self.db.global.warbandBank.items or {},
        lastUpdate = self.db.global.warbandBank.lastUpdate or 0,
    }
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
