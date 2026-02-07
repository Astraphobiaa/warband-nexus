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

-- Debug print helper (only prints if debug mode enabled)
local function DebugPrint(...)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
        _G.print(...)
    end
end

-- Keystone detection moved to PvECacheService (C_MythicPlus API, event-driven)

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

-- Global loading state (accessible from UI)
ns.ItemsLoadingState = {
    isLoading = false,           -- Currently scanning bags
    scanProgress = 0,            -- 0-100 progress percentage
    currentStage = nil,          -- Current stage (e.g., "Scanning Inventory")
}

-- Bank frame state (event-based detection)
local isBankOpen = false
local isWarbandBankOpen = false

-- Hash cache for bag change detection (RAM only)
local bagHashCache = {} -- [bagID] = hash

-- Throttle timers
local lastUpdateTime = {}
local pendingUpdates = {}

-- ============================================================================
-- DECOMPRESSED DATA SESSION CACHE
-- Avoids repeated decompress+deserialize on every GetItemsData()/tooltip hover.
-- Invalidated per-key when items are scanned. Cleared on UI OnHide.
-- ============================================================================
local decompressedItemCache = {}  -- [charKey] = { bags={}, bank={}, bagsLastUpdate=N, bankLastUpdate=N }
local decompressedWarbandCache = nil  -- { items={}, lastUpdate=N }

-- ============================================================================
-- PRE-INDEXED ITEM COUNT SUMMARY
-- Instead of iterating ALL items on every tooltip hover, maintain a
-- pre-computed { [itemID] = { bags=N, bank=N } } per character.
-- Rebuilt lazily: marked "pending" when items change, processed on next tooltip access.
-- ============================================================================
local itemSummaryIndex = {
    characters = {},  -- [charKey] = { [itemID] = { bags=N, bank=N } }
    warband = {},     -- [itemID] = N
    pending = {},     -- [charKey] = true (needs rebuild)
    warbandPending = false,
}

-- Session-only item metadata cache (never persisted)
-- C_Item.GetItemInfoInstant is fast but we still avoid redundant calls
local itemMetadataCache = {}       -- [itemID] = { name, link, icon, classID, subclassID, itemType }
local itemMetadataCacheOrder = {}  -- FIFO eviction order tracking (head index + count)
local itemMetadataCacheHead = 1    -- Circular buffer head index
local ITEM_METADATA_CACHE_MAX = 512

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
-- ON-DEMAND ITEM METADATA RESOLVER (Session RAM only)
-- ============================================================================

---Resolve item metadata from WoW API (session RAM cache, never persisted).
---@param itemID number
---@return table|nil { name, link, icon, classID, subclassID, itemType }
local function ResolveItemMetadata(itemID)
    if not itemID or itemID == 0 then return nil end
    
    -- Check RAM cache
    local cached = itemMetadataCache[itemID]
    if cached then return cached end
    
    -- C_Item.GetItemInfoInstant is synchronous and always works
    local _, itemType, itemSubType, _, icon, classID, subclassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, itemType, itemSubType, _, icon, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    end
    
    -- C_Item.GetItemInfo may return nil for uncached items (async)
    local name, link
    if C_Item and C_Item.GetItemInfo then
        name, link = C_Item.GetItemInfo(itemID)
    end
    
    local metadata = {
        name = name or ("Item " .. itemID),
        link = link,
        icon = icon,
        iconFileID = icon,
        classID = classID,
        subclassID = subclassID,
        itemType = itemType or "Miscellaneous",
    }
    
    -- Circular buffer eviction (O(1) instead of O(n) table.remove)
    if #itemMetadataCacheOrder >= ITEM_METADATA_CACHE_MAX then
        local evictID = itemMetadataCacheOrder[itemMetadataCacheHead]
        if evictID then
            itemMetadataCache[evictID] = nil
        end
        itemMetadataCacheOrder[itemMetadataCacheHead] = itemID
        itemMetadataCacheHead = (itemMetadataCacheHead % ITEM_METADATA_CACHE_MAX) + 1
    else
        itemMetadataCacheOrder[#itemMetadataCacheOrder + 1] = itemID
    end
    
    itemMetadataCache[itemID] = metadata
    
    return metadata
end

---Hydrate a lean item (from SV) with on-demand metadata.
---@param item table Lean item { itemID, stackCount, quality, isBound, bagID, slotIndex, ... }
---@return table hydrated Full item with name, link, icon, classID, etc.
local function HydrateItem(item)
    if not item or not item.itemID then return item end
    
    -- If already hydrated (legacy data), return as-is
    if item.name and item.iconFileID and item.classID then
        return item
    end
    
    local metadata = ResolveItemMetadata(item.itemID)
    if metadata then
        item.name = item.name or metadata.name
        item.link = item.link or metadata.link
        item.itemLink = item.link  -- Alias: many UI paths access item.itemLink
        item.iconFileID = item.iconFileID or metadata.iconFileID
        item.classID = item.classID or metadata.classID
        item.subclassID = item.subclassID or metadata.subclassID
        item.itemType = item.itemType or metadata.itemType
    end
    
    return item
end

---Hydrate an array of lean items with metadata.
---@param items table Array of lean items
---@return table items Same array, items hydrated in-place
local function HydrateItems(items)
    if not items then return items end
    for _, item in ipairs(items) do
        HydrateItem(item)
    end
    return items
end

---Clear session-only item metadata cache.
function WarbandNexus:ClearItemMetadataCache()
    wipe(itemMetadataCache)
    wipe(itemMetadataCacheOrder)
    itemMetadataCacheHead = 1
    -- Also clear decompressed data cache and summary index
    wipe(decompressedItemCache)
    decompressedWarbandCache = nil
    wipe(itemSummaryIndex.characters)
    wipe(itemSummaryIndex.warband)
    wipe(itemSummaryIndex.pending)
    itemSummaryIndex.warbandPending = false
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

---Scan a specific bag and return LEAN item data (metadata stripped).
---Only stores: itemID, stackCount, quality, isBound, positional fields.
---Metadata (name, link, icon, classID) is resolved on-demand when reading.
---@param bagID number Bag ID
---@return table items Array of lean item data
local function ScanBag(bagID)
    local items = {}
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    
    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
        if itemInfo and itemInfo.hyperlink then
            local itemID = C_Item.GetItemInfoInstant(itemInfo.hyperlink)
            
            if itemID then
                table.insert(items, {
                    -- Positional (needed to identify slot)
                    actualBagID = bagID,
                    bagID = bagID,
                    slotIndex = slot,
                    slot = slot,
                    -- Core data (can't be fetched for offline chars)
                    itemID = itemID,
                    stackCount = itemInfo.stackCount or 1,
                    quality = itemInfo.quality,
                    isBound = itemInfo.isBound or false,
                    -- NOTE: name, link, iconFileID, classID, subclassID, itemType
                    -- are NOT stored. They are resolved on-demand via ResolveItemMetadata().
                })
            end
        end
    end
    
    return items
end

---Scan all inventory bags for current character
---@param charKey string Character key
---INCREMENTAL UPDATE: Update only specific bag (single bag scan)
---@param charKey string Character key
---@param bagID number Specific bag to update
function WarbandNexus:UpdateSingleBag(charKey, bagID)
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Items Action] SingleBagUpdate triggered, bagID=" .. tostring(bagID))
    -- GUARD: Only update bags if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not charKey then
        charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    end
    
    -- Determine if this is an inventory bag or bank bag
    local isInventoryBag = false
    local isBankBag = false
    
    for _, invBagID in ipairs(INVENTORY_BAGS) do
        if bagID == invBagID then
            isInventoryBag = true
            break
        end
    end
    
    for _, bankBagID in ipairs(BANK_BAGS) do
        if bagID == bankBagID then
            isBankBag = true
            break
        end
    end
    
    if not isInventoryBag and not isBankBag then
        return {}
    end
    
    -- Get current data from DB
    local currentData = self:GetItemsData(charKey)
    local dataType = isInventoryBag and "bags" or "bank"
    local allItems = isInventoryBag and (currentData.bags or {}) or (currentData.bank or {})
    
    -- Remove old items from this specific bag
    for i = #allItems, 1, -1 do
        if allItems[i].bagID == bagID then
            table.remove(allItems, i)
        end
    end
    
    -- Scan only this bag
    local newBagItems = ScanBag(bagID)
    -- Incremental bag update
    
    -- Add new items from this bag
    for _, item in ipairs(newBagItems) do
        table.insert(allItems, item)
    end
    
    -- Save to DB (compressed)
    self:SaveItemsCompressed(charKey, dataType, allItems)
    
    return allItems
end

---FULL SCAN: Scan all inventory bags (used on login or manual refresh)
---@param charKey string Character key
function WarbandNexus:ScanInventoryBags(charKey)
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Items Action] InventoryScan triggered")
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return {}
    end
    
    if not charKey then
        charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    end
    
    local allItems = {}
    
    -- Scan ALL inventory bags
    for _, bagID in ipairs(INVENTORY_BAGS) do
        local bagItems = ScanBag(bagID)
    -- Scanning inventory bag
        for _, item in ipairs(bagItems) do
            table.insert(allItems, item)
        end
    end
    
    -- Save to DB (compressed)
    -- Saving inventory items
    self:SaveItemsCompressed(charKey, "bags", allItems)
    
    return allItems
end

---Scan all bank bags for current character
---@param charKey string Character key
function WarbandNexus:ScanBankBags(charKey)
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Items Action] BankScan triggered")
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return {}
    end
    
    if not charKey then
        charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    end
    
    local allItems = {}
    
    -- Scan ALL bank bags (NO FLAG CHECK - just scan)
    for _, bagID in ipairs(BANK_BAGS) do
        local bagItems = ScanBag(bagID)
    -- Scanning bank bag
        for _, item in ipairs(bagItems) do
            table.insert(allItems, item)
        end
    end
    
    -- Save to DB (compressed)
    -- Saving bank items
    self:SaveItemsCompressed(charKey, "bank", allItems)
    
    return allItems
end

---Scan warband bank
function WarbandNexus:ScanWarbandBank()
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Items Action] WarbandBankScan triggered")
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return {}
    end
    
    local allItems = {}
    
    -- Scan ALL warband bank tabs (NO FLAG CHECK - just scan)
    for tabIndex, bagID in ipairs(WARBAND_BAGS) do
        local bagItems = ScanBag(bagID)
    -- Scanning warband tab
        for _, item in ipairs(bagItems) do
            -- Add tab index for warband bank (1-5)
            item.tabIndex = tabIndex
            table.insert(allItems, item)
        end
    end
    
    -- Save to global (compressed, warband bank is account-wide)
    -- Saving warband bank items
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
        -- Schedule pending update with timer
        if not pendingUpdates[bagID] then
            pendingUpdates[bagID] = true
            
            -- Schedule processing after throttle period
            C_Timer.After(UPDATE_THROTTLE - (currentTime - lastUpdate), function()
                if pendingUpdates[bagID] then
                    pendingUpdates[bagID] = nil
                    ThrottledBagUpdate(bagID)  -- Retry
                end
            end)
        end
        return
    end
    
    lastUpdateTime[bagID] = currentTime
    pendingUpdates[bagID] = nil
    
    -- Determine bag type and scan INCREMENTALLY (only changed bag)
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    
    -- Check if it's an inventory bag
    for _, invBagID in ipairs(INVENTORY_BAGS) do
        if bagID == invBagID then
            -- INCREMENTAL: Update only this bag (not all inventory)
            WarbandNexus:UpdateSingleBag(charKey, bagID)
            WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "inventory", charKey = charKey, bagID = bagID})
            return
        end
    end
    
    -- Check if it's a bank bag
    for _, bankBagID in ipairs(BANK_BAGS) do
        if bagID == bankBagID then
            if isBankOpen then
                -- INCREMENTAL: Update only this bag (not all bank)
                WarbandNexus:UpdateSingleBag(charKey, bagID)
                WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "bank", charKey = charKey, bagID = bagID})
            end
            return
        end
    end
    
    -- Check if it's a warband bag
    for _, warbandBagID in ipairs(WARBAND_BAGS) do
        if bagID == warbandBagID then
            if isWarbandBankOpen then
                -- Warband bank still uses full scan (simpler, less frequent)
                WarbandNexus:ScanWarbandBank()
                WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "warband", bagID = bagID})
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
---Handle BAG_UPDATE event (from RegisterBucketEvent)
---@param bagIDs table Table of bagIDs that were updated (from bucket)
function WarbandNexus:OnBagUpdate(bagIDs)
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Items Event] BAG_UPDATE (bucket) triggered")
    -- GUARD: Only process bag updates if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- RegisterBucketEvent passes a table of bagIDs
    if not bagIDs or type(bagIDs) ~= "table" then
        return
    end
    
    -- Process each bag that was updated
    for bagID in pairs(bagIDs) do
        -- Smart filter: Check if bag contents actually changed
        if HasBagChanged(bagID) then
            ThrottledBagUpdate(bagID)
        end
    end
end

---Handle BANKFRAME_OPENED event
function WarbandNexus:OnBankOpened()
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Bank Event] BANKFRAME_OPENED triggered")
    
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    isBankOpen = true
    isWarbandBankOpen = true
    
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    
    self:ScanInventoryBags(charKey)
    self:ScanBankBags(charKey)
    self:ScanWarbandBank()
    
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "all", charKey = charKey})
end

---Handle BANKFRAME_CLOSED event
function WarbandNexus:OnBankClosed()
    isBankOpen = false
    isWarbandBankOpen = false  -- Both tabs close together
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Bank Event] BANKFRAME_CLOSED")
end

---Handle BAG_UPDATE_DELAYED (fires once after all bag operations complete)
---Uses fingerprint-based change detection to skip redundant scans
function WarbandNexus:OnInventoryBagsChanged()
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Bag Event] BAG_UPDATE_DELAYED triggered")
    
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Only scan if items module enabled
    if not self.db.profile.modulesEnabled or not self.db.profile.modulesEnabled.items then
        return
    end
    
    -- Only auto-scan if enabled
    if not self.db.profile.autoScan then
        return
    end
    
    -- OPTIMIZATION: Fingerprint comparison (cheap hash of all item IDs + counts)
    local totalSlots, usedSlots, newFingerprint = ns.Utilities:GetBagFingerprint()
    
    if not self.lastBagSnapshot then
        self.lastBagSnapshot = { fingerprint = "", totalSlots = 0, usedSlots = 0 }
    end
    
    if newFingerprint == self.lastBagSnapshot.fingerprint then
        return
    end
    
    self.lastBagSnapshot.fingerprint = newFingerprint
    self.lastBagSnapshot.totalSlots = totalSlots
    self.lastBagSnapshot.usedSlots = usedSlots
    
    -- DEBOUNCE: 1s delay for bulk operations (loot, mail, vendor)
    if self.pendingBagsScanTimer then
        self:CancelTimer(self.pendingBagsScanTimer)
    end
    
    self.pendingBagsScanTimer = self:ScheduleTimer(function()
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
        self:ScanInventoryBags(charKey)
        self.pendingBagsScanTimer = nil
        
        -- Fire message for downstream consumers (DataService, UI)
        self:SendMessage("WN_BAGS_UPDATED")
    end, 1.0)
    
    -- Keystone detection: REMOVED from bag handler
    -- Keystones are now detected via C_MythicPlus API (O(1)) triggered by proper events:
    --   CHALLENGE_MODE_COMPLETED, CHALLENGE_MODE_MAPS_UPDATE, CHALLENGE_MODE_KEYSTONE_SLOTTED
    -- See PvECacheService and EventManager for event ownership
    
    -- ── Collectible detection (bag scan for new collectibles) ──
    if self.OnBagUpdateForCollectibles then
        self:OnBagUpdateForCollectibles()
    end
end

---Handle ACCOUNT_BANK_FRAME_OPENED event (Warband Bank tab switched)
function WarbandNexus:OnWarbandBankFrameOpened()
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- This fires when user switches to Warband Bank TAB (bank already open)
    -- Re-scan to catch any changes
    self:ScanWarbandBank()
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "warband"})
    
    -- Warband Bank tab switched
end

---Handle ACCOUNT_BANK_FRAME_CLOSED event (Warband Bank tab closed)
function WarbandNexus:OnWarbandBankFrameClosed()
    -- Tab switched away, but bank might still be open
    -- Don't change isWarbandBankOpen here (managed by BANKFRAME_CLOSED)
    -- Warband Bank tab closed
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
    -- GUARD: Only save if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
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
        -- Invalidate caches even on uncompressed fallback
        decompressedItemCache[charKey] = nil
        itemSummaryIndex.pending[charKey] = true
        return
    end
    
    -- Store compressed
    self.db.global.itemStorage[charKey][dataType] = {
        compressed = true,
        data = compressed,
        lastUpdate = time()
    }
    
    -- Invalidate decompressed cache + mark summary index pending for this character
    decompressedItemCache[charKey] = nil
    itemSummaryIndex.pending[charKey] = true
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
        decompressedWarbandCache = nil
        itemSummaryIndex.warbandPending = true
        return
    end
    
    -- Store compressed
    self.db.global.itemStorage.warbandBank = {
        compressed = true,
        data = compressed,
        lastUpdate = time()
    }
    
    -- Invalidate decompressed cache + mark warband summary pending
    decompressedWarbandCache = nil
    itemSummaryIndex.warbandPending = true
end

-- ============================================================================
-- PUBLIC API (FOR UI AND DATASERVICE)
-- ============================================================================

---Get items data for a specific character (decompressed + hydrated with metadata).
---Uses session RAM cache to avoid repeated decompression. Invalidated when items are scanned.
---@param charKey string Character key
---@return table data {bags, bank, lastUpdate}
function WarbandNexus:GetItemsData(charKey)
    -- Check session cache first (avoids repeated decompress+deserialize)
    local cached = decompressedItemCache[charKey]
    if cached then return cached end
    
    -- Check if new storage system exists
    if not self.db.global.itemStorage or not self.db.global.itemStorage[charKey] then
        -- Fallback: legacy storage (uncompressed)
        if self.db.global.characters and self.db.global.characters[charKey] then
            local charData = self.db.global.characters[charKey]
            local result = {
                bags = HydrateItems(charData.items or {}),
                bank = HydrateItems(charData.bank or {}),
                bagsLastUpdate = charData.itemsLastUpdate or 0,
                bankLastUpdate = charData.bankLastUpdate or 0,
            }
            decompressedItemCache[charKey] = result
            return result
        end
        
        -- No data found (silent - expected for new/unscanned characters)
        return {bags = {}, bank = {}, bagsLastUpdate = 0, bankLastUpdate = 0}
    end
    
    -- Decompress from DB storage (on-demand, cached for session)
    local storage = self.db.global.itemStorage[charKey]
    local result = {
        bags = {},
        bank = {},
        bagsLastUpdate = 0,
        bankLastUpdate = 0,
    }
    
    -- Decompress bags and hydrate with metadata
    if storage.bags then
        if storage.bags.compressed then
            result.bags = DecompressItemData(storage.bags.data) or {}
        else
            result.bags = storage.bags.data or {}
        end
        HydrateItems(result.bags)
        result.bagsLastUpdate = storage.bags.lastUpdate or 0
    end
    
    -- Decompress bank and hydrate with metadata
    if storage.bank then
        if storage.bank.compressed then
            result.bank = DecompressItemData(storage.bank.data) or {}
        else
            result.bank = storage.bank.data or {}
        end
        HydrateItems(result.bank)
        result.bankLastUpdate = storage.bank.lastUpdate or 0
    end
    
    -- Cache for session (invalidated when items are re-scanned)
    decompressedItemCache[charKey] = result
    return result
end

---Get warband bank data (decompressed + hydrated with metadata).
---Uses session RAM cache. Invalidated when warband bank is scanned.
---@return table data {items, lastUpdate}
function WarbandNexus:GetWarbandBankData()
    -- Check session cache first
    if decompressedWarbandCache then return decompressedWarbandCache end
    
    -- Check if new storage system exists
    if not self.db.global.itemStorage or not self.db.global.itemStorage.warbandBank then
        -- Fallback: legacy storage
        if self.db.global.warbandBank then
            local result = {
                items = HydrateItems(self.db.global.warbandBank.items or {}),
                lastUpdate = self.db.global.warbandBank.lastUpdate or 0,
            }
            decompressedWarbandCache = result
            return result
        end
        
        return {items = {}, lastUpdate = 0}
    end
    
    -- Decompress from DB storage (on-demand, cached for session)
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
    HydrateItems(result.items)
    result.lastUpdate = storage.lastUpdate or 0
    
    -- Cache for session (invalidated when warband bank is re-scanned)
    decompressedWarbandCache = result
    return result
end

-- ============================================================================
-- PRE-INDEXED ITEM COUNT SUMMARY
-- O(1) tooltip lookup instead of iterating all items on every hover.
-- Summary rebuilt lazily: marked "pending" on item change, processed on next access.
-- ============================================================================

---Build item count summary for a single character (bags + bank).
---@param charKey string Character key
local function BuildCharacterSummary(charKey)
    local summary = {}  -- [itemID] = { bags=N, bank=N }
    
    -- Use the decompressed cache (GetItemsData populates it)
    local itemsData = WarbandNexus:GetItemsData(charKey)
    if not itemsData then
        itemSummaryIndex.characters[charKey] = summary
        return
    end
    
    -- Count bags
    if itemsData.bags then
        for _, item in ipairs(itemsData.bags) do
            if item.itemID then
                local entry = summary[item.itemID]
                if not entry then
                    entry = { bags = 0, bank = 0 }
                    summary[item.itemID] = entry
                end
                entry.bags = entry.bags + (item.stackCount or 1)
            end
        end
    end
    
    -- Count bank
    if itemsData.bank then
        for _, item in ipairs(itemsData.bank) do
            if item.itemID then
                local entry = summary[item.itemID]
                if not entry then
                    entry = { bags = 0, bank = 0 }
                    summary[item.itemID] = entry
                end
                entry.bank = entry.bank + (item.stackCount or 1)
            end
        end
    end
    
    itemSummaryIndex.characters[charKey] = summary
end

---Build item count summary for warband bank.
local function BuildWarbandSummary()
    local summary = {}  -- [itemID] = N
    
    local warbandData = WarbandNexus:GetWarbandBankData()
    if warbandData and warbandData.items then
        for _, item in ipairs(warbandData.items) do
            if item.itemID then
                summary[item.itemID] = (summary[item.itemID] or 0) + (item.stackCount or 1)
            end
        end
    end
    
    itemSummaryIndex.warband = summary
    itemSummaryIndex.warbandPending = false
end

---Process any pending summary rebuilds (call before tooltip lookup).
---Lazy rebuild on demand, not on every bag event.
local function ProcessPendingSummaries()
    -- Process pending characters
    for charKey in pairs(itemSummaryIndex.pending) do
        BuildCharacterSummary(charKey)
        itemSummaryIndex.pending[charKey] = nil
    end
    
    -- Process pending warband
    if itemSummaryIndex.warbandPending then
        BuildWarbandSummary()
    end
end

---Get detailed item counts for tooltip display (O(1) lookup after lazy rebuild).
---Replaces the old DataService:GetDetailedItemCounts which iterated all items per hover.
---@param itemID number
---@return table|nil { warbandBank=N, personalBankTotal=N, characters={{charName,classFile,bagCount,bankCount,total},...} }
function WarbandNexus:GetDetailedItemCountsFast(itemID)
    if not itemID then return nil end
    
    -- Ensure all characters have summaries (first-time lazy build)
    -- Mark any character that doesn't have a summary yet as pending
    if self.db and self.db.global and self.db.global.characters then
        for charKey in pairs(self.db.global.characters) do
            if not itemSummaryIndex.characters[charKey] and not itemSummaryIndex.pending[charKey] then
                itemSummaryIndex.pending[charKey] = true
            end
        end
    end
    -- Also ensure warband summary exists
    if not next(itemSummaryIndex.warband) and not itemSummaryIndex.warbandPending then
        itemSummaryIndex.warbandPending = true
    end
    
    -- Process any pending rebuilds (lazy, batched)
    ProcessPendingSummaries()
    
    -- O(1) lookup: warband bank
    local warbandCount = itemSummaryIndex.warband[itemID] or 0
    
    -- O(1) lookup per character
    local result = {
        warbandBank = warbandCount,
        personalBankTotal = 0,
        characters = {},
    }
    
    local currentPlayerName = UnitName("player")
    local currentPlayerRealm = GetRealmName()
    local currentCharKey = currentPlayerName .. "-" .. currentPlayerRealm
    
    for charKey, charData in pairs(self.db.global.characters or {}) do
        local bagCount, bankCount = 0, 0
        
        if charKey == currentCharKey then
            -- Current character: use live Blizzard API (O(1), always accurate)
            bagCount = GetItemCount(itemID) or 0
            local totalIncBank = GetItemCount(itemID, true) or 0
            bankCount = totalIncBank - bagCount
        else
            -- Other characters: O(1) summary lookup
            local summary = itemSummaryIndex.characters[charKey]
            if summary and summary[itemID] then
                bagCount = summary[itemID].bags or 0
                bankCount = summary[itemID].bank or 0
            end
        end
        
        if bagCount > 0 or bankCount > 0 then
            result.personalBankTotal = result.personalBankTotal + bankCount
            result.characters[#result.characters + 1] = {
                charName = charKey:match("^([^-]+)"),
                classFile = charData.classFile or charData.class,
                bagCount = bagCount,
                bankCount = bankCount,
                total = bagCount + bankCount,
            }
        end
    end
    
    -- Sort: current character first, then by total descending
    table.sort(result.characters, function(a, b)
        local aIsCurrent = (a.charName == currentPlayerName)
        local bIsCurrent = (b.charName == currentPlayerName)
        if aIsCurrent ~= bIsCurrent then return aIsCurrent end
        return a.total > b.total
    end)
    
    return result
end

---Invalidate item summary for a character (call when bags/bank change).
---The summary will be rebuilt lazily on next tooltip access.
---@param charKey string|nil Character key (nil = invalidate all + warband)
function WarbandNexus:InvalidateItemSummary(charKey)
    if charKey then
        itemSummaryIndex.pending[charKey] = true
    else
        -- Invalidate everything
        for key in pairs(itemSummaryIndex.characters) do
            itemSummaryIndex.pending[key] = true
        end
        itemSummaryIndex.warbandPending = true
    end
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
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize items cache on login
function WarbandNexus:InitializeItemsCache()
    -- ── Event Ownership (single owner for all bag/bank events) ──
    WarbandNexus:RegisterBucketEvent("BAG_UPDATE", 0.5, "OnBagUpdate")
    WarbandNexus:RegisterBucketEvent("PLAYERBANKSLOTS_CHANGED", 0.5, "OnBagUpdate")
    WarbandNexus:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    WarbandNexus:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    WarbandNexus:RegisterEvent("BAG_UPDATE_DELAYED", "OnInventoryBagsChanged")
    
    -- Set loading state (initial scan in progress)
    ns.ItemsLoadingState.isLoading = true
    ns.ItemsLoadingState.currentStage = "Preparing scan"
    ns.ItemsLoadingState.scanProgress = 0
    
    -- Scan inventory bags on login (bank requires manual visit)
    C_Timer.After(2, function()
        ns.ItemsLoadingState.currentStage = "Scanning inventory bags"
        ns.ItemsLoadingState.scanProgress = 50
        
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
        self:ScanInventoryBags(charKey)
        
        -- Mark loading complete
        ns.ItemsLoadingState.isLoading = false
        ns.ItemsLoadingState.scanProgress = 100
        ns.ItemsLoadingState.currentStage = nil
        
    end)
end

-- ============================================================================
-- LOAD MESSAGE
-- ============================================================================

-- Module loaded - verbose logging hidden (debug mode only)
