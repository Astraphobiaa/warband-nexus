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

-- O(1) bag type lookup table (replaces 3 sequential linear searches in ThrottledBagUpdate)
local BAG_TYPE_LOOKUP = {}  -- [bagID] = "inventory" | "bank" | "warband"
for _, id in ipairs(INVENTORY_BAGS) do BAG_TYPE_LOOKUP[id] = "inventory" end
for _, id in ipairs(BANK_BAGS) do BAG_TYPE_LOOKUP[id] = "bank" end
for _, id in ipairs(WARBAND_BAGS) do BAG_TYPE_LOOKUP[id] = "warband" end

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
local bankScanInProgress = false  -- True during OnBankOpened deferred scans; suppresses duplicate work

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
local itemMetadataCache = {}       -- [itemID] = { name, link, icon, classID, subclassID, itemType, pending? }
local itemMetadataCacheOrder = {}  -- FIFO eviction order tracking (head index + count)
local itemMetadataCacheHead = 1    -- Circular buffer head index
local ITEM_METADATA_CACHE_MAX = 512

-- Async item metadata resolution tracking
local pendingItemLoads = {}              -- [itemID] = true (prevents duplicate async loads)
local pendingMetadataRefreshTimer = nil  -- Debounce timer for UI refresh after batch resolution

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

---Add a fully-resolved metadata entry to the FIFO eviction cache.
---@param itemID number
local function AddToFIFOCache(itemID)
    if #itemMetadataCacheOrder >= ITEM_METADATA_CACHE_MAX then
        local evictID = itemMetadataCacheOrder[itemMetadataCacheHead]
        if evictID then
            -- Don't evict if the item is still pending async load
            if not (itemMetadataCache[evictID] and itemMetadataCache[evictID].pending) then
                itemMetadataCache[evictID] = nil
            end
        end
        itemMetadataCacheOrder[itemMetadataCacheHead] = itemID
        itemMetadataCacheHead = (itemMetadataCacheHead % ITEM_METADATA_CACHE_MAX) + 1
    else
        itemMetadataCacheOrder[#itemMetadataCacheOrder + 1] = itemID
    end
end

---Debounced UI refresh after async item metadata resolution.
---Invalidates decompressed caches and fires WN_ITEM_METADATA_READY.
local function ScheduleMetadataRefresh()
    if pendingMetadataRefreshTimer then
        pendingMetadataRefreshTimer:Cancel()
    end
    pendingMetadataRefreshTimer = C_Timer.NewTimer(0.3, function()
        pendingMetadataRefreshTimer = nil
        -- Invalidate decompressed data caches (they contain hydrated items with stale names)
        wipe(decompressedItemCache)
        decompressedWarbandCache = nil
        -- Fire event for UI refresh
        WarbandNexus:SendMessage(Constants.EVENTS.ITEM_METADATA_READY)
    end)
end

---Queue async item load via Item:CreateFromItemID + ContinueOnItemLoad.
---When the item data becomes available, updates the metadata cache and schedules a UI refresh.
---@param itemID number
local function QueueAsyncItemLoad(itemID)
    if pendingItemLoads[itemID] then return end  -- Already queued
    pendingItemLoads[itemID] = true
    
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        pendingItemLoads[itemID] = nil
        
        -- Fetch now-available data
        local resolvedName, resolvedLink = C_Item.GetItemInfo(itemID)
        if not resolvedName then return end  -- Safety: still not available (shouldn't happen)
        
        -- Update existing cache entry (or create new one)
        local existing = itemMetadataCache[itemID]
        if existing then
            existing.name = resolvedName
            existing.link = resolvedLink
            existing.pending = nil
            -- Now fully resolved: add to FIFO eviction
            AddToFIFOCache(itemID)
        end
        
        -- Schedule debounced UI refresh (batches multiple resolutions)
        ScheduleMetadataRefresh()
    end)
end

---Resolve item metadata from WoW API (session RAM cache, never persisted).
---Uses ContinueOnItemLoad for async resolution of uncached items.
---@param itemID number
---@return table|nil { name, link, icon, classID, subclassID, itemType, pending? }
local function ResolveItemMetadata(itemID)
    if not itemID or itemID == 0 then return nil end
    
    -- Check RAM cache (return immediately if fully resolved)
    local cached = itemMetadataCache[itemID]
    if cached and not cached.pending then return cached end
    -- If pending, re-check API (may have resolved since last call)
    if cached and cached.pending then
        local name, link
        if C_Item and C_Item.GetItemInfo then
            name, link = C_Item.GetItemInfo(itemID)
        end
        if name then
            cached.name = name
            cached.link = link
            cached.pending = nil
            AddToFIFOCache(itemID)
            pendingItemLoads[itemID] = nil
            return cached
        end
        return cached  -- Still pending
    end
    
    -- C_Item.GetItemInfoInstant is synchronous (icon, classID always available)
    local _, itemType, itemSubType, _, icon, classID, subclassID
    if C_Item and C_Item.GetItemInfoInstant then
        _, itemType, itemSubType, _, icon, classID, subclassID = C_Item.GetItemInfoInstant(itemID)
    end
    
    -- C_Item.GetItemInfo may return nil for uncached items (async)
    local name, link
    if C_Item and C_Item.GetItemInfo then
        name, link = C_Item.GetItemInfo(itemID)
    end
    
    local isPending = (name == nil)
    
    local metadata = {
        name = name,      -- nil if not yet resolved (NO fake "Item 123" fallback)
        link = link,
        icon = icon,
        iconFileID = icon,
        classID = classID,
        subclassID = subclassID,
        itemType = itemType or "Miscellaneous",
        pending = isPending or nil,
    }
    
    -- Store in lookup table (always, so we don't create duplicate entries)
    itemMetadataCache[itemID] = metadata
    
    if isPending then
        -- Queue async load (ContinueOnItemLoad fires when server responds)
        QueueAsyncItemLoad(itemID)
    else
        -- Fully resolved: add to FIFO eviction
        AddToFIFOCache(itemID)
    end
    
    return metadata
end

---Hydrate a lean item (from SV) with on-demand metadata.
---Sets item.pending = true if the item name is still being loaded asynchronously.
---@param item table Lean item { itemID, stackCount, quality, isBound, bagID, slotIndex, ... }
---@return table hydrated Full item with name, link, icon, classID, etc.
local function HydrateItem(item)
    if not item or not item.itemID then return item end
    
    -- If already hydrated (legacy data) and NOT pending, return as-is
    if item.name and item.iconFileID and item.classID and not item.pending then
        return item
    end
    
    local metadata = ResolveItemMetadata(item.itemID)
    if metadata then
        item.name = item.name or metadata.name
        -- Preserve original hyperlink from scan (contains bonus IDs, rank, ilvl).
        -- metadata.link is the base link from C_Item.GetItemInfo(itemID) — lacks bonus IDs.
        local originalLink = item.itemLink or item.link
        item.link = originalLink or metadata.link
        item.itemLink = item.link
        item.iconFileID = item.iconFileID or metadata.iconFileID
        item.classID = item.classID or metadata.classID
        item.subclassID = item.subclassID or metadata.subclassID
        item.itemType = item.itemType or metadata.itemType
        -- Propagate pending state to item (UI uses this to show loading indicator)
        item.pending = metadata.pending or nil
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
    wipe(pendingItemLoads)
    if pendingMetadataRefreshTimer then
        pendingMetadataRefreshTimer:Cancel()
        pendingMetadataRefreshTimer = nil
    end
    -- Also clear decompressed data cache and summary index
    wipe(decompressedItemCache)
    decompressedWarbandCache = nil
    wipe(itemSummaryIndex.characters)
    wipe(itemSummaryIndex.warband)
    wipe(itemSummaryIndex.pending)
    itemSummaryIndex.warbandPending = false
end

-- ============================================================================
-- HASH GENERATION (CHANGE DETECTION) + BAG SCANNING
-- ============================================================================

-- Per-bag cache: stores raw GetContainerItemInfo results from the hash pass
-- so ScanBag can reuse them instead of re-querying every slot.
local cachedSlotData = {}  -- [bagID] = { [slot] = itemInfo, numSlots = n }

---Generate hash for a bag to detect real changes.
---Also caches raw slot data for ScanBag to reuse (avoids double API calls).
---Hash includes: item count + item links (ignores durability, charges, cooldowns)
---@param bagID number Bag ID
---@return string hash Hash string
local function GenerateItemHash(bagID)
    local items = {}
    local n = 0
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    local slotCache = { numSlots = numSlots }
    
    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
        slotCache[slot] = itemInfo  -- Cache for ScanBag (nil entries are fine)
        if itemInfo and itemInfo.hyperlink then
            -- Hash includes: hyperlink + stack count
            -- Does NOT include: durability, charges, cooldowns
            n = n + 1
            items[n] = itemInfo.hyperlink .. ":" .. (itemInfo.stackCount or 1)
        end
    end
    
    cachedSlotData[bagID] = slotCache
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
    
    -- Hash unchanged: clear the cached slot data (not needed)
    cachedSlotData[bagID] = nil
    return false
end

---Scan a specific bag and return LEAN item data (metadata stripped).
---Reuses cached slot data from GenerateItemHash when available (single pass).
---Only stores: itemID, stackCount, quality, isBound, positional fields.
---Metadata (name, link, icon, classID) is resolved on-demand when reading.
---@param bagID number Bag ID
---@return table items Array of lean item data
local function ScanBag(bagID)
    local items = {}
    local n = 0  -- Manual count avoids #items overhead per insert
    local slotCache = cachedSlotData[bagID]
    local numSlots
    
    if slotCache then
        -- Fast path: reuse cached data from GenerateItemHash (no API calls)
        numSlots = slotCache.numSlots or 0
        for slot = 1, numSlots do
            local itemInfo = slotCache[slot]
            if itemInfo and itemInfo.hyperlink then
                local itemID = C_Item.GetItemInfoInstant(itemInfo.hyperlink)
                if itemID then
                    n = n + 1
                    items[n] = {
                        actualBagID = bagID,
                        bagID = bagID,
                        slotIndex = slot,
                        slot = slot,
                        itemID = itemID,
                        itemLink = itemInfo.hyperlink,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality,
                        isBound = itemInfo.isBound or false,
                    }
                end
            end
        end
        cachedSlotData[bagID] = nil  -- Consumed; free memory
    else
        -- Fallback: no cached data (bank bags, deferred updates, etc.)
        numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, numSlots do
            local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
            if itemInfo and itemInfo.hyperlink then
                local itemID = C_Item.GetItemInfoInstant(itemInfo.hyperlink)
                if itemID then
                    n = n + 1
                    items[n] = {
                        actualBagID = bagID,
                        bagID = bagID,
                        slotIndex = slot,
                        slot = slot,
                        itemID = itemID,
                        itemLink = itemInfo.hyperlink,
                        stackCount = itemInfo.stackCount or 1,
                        quality = itemInfo.quality,
                        isBound = itemInfo.isBound or false,
                    }
                end
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
        charKey = ns.Utilities:GetCharacterKey()
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
    -- Add new items from this bag
    for i = 1, #newBagItems do
        allItems[#allItems + 1] = newBagItems[i]
    end
    
    -- Save to DB (compressed)
    self:SaveItemsCompressed(charKey, dataType, allItems)
    
    return allItems
end

---INCREMENTAL UPDATE: Update only a specific warband bank bag (single tab scan)
---Avoids full ScanWarbandBank() which scans all 5 tabs on every change
---@param bagID number Warband bag ID (13-17)
function WarbandNexus:UpdateSingleWarbandBag(bagID)
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Items Action] SingleWarbandBagUpdate triggered, bagID=" .. tostring(bagID))
    
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Determine tabIndex from WARBAND_BAGS array position
    local tabIndex = nil
    for idx, warbandBagID in ipairs(WARBAND_BAGS) do
        if bagID == warbandBagID then
            tabIndex = idx
            break
        end
    end
    
    if not tabIndex then
        return  -- Not a warband bag
    end
    
    -- Get current warband data from DB
    local warbandData = self:GetWarbandBankData()
    local allItems = warbandData.items or {}
    
    -- Remove old items from this specific bag
    for i = #allItems, 1, -1 do
        if allItems[i].bagID == bagID then
            table.remove(allItems, i)
        end
    end
    
    -- Scan only this bag
    local newBagItems = ScanBag(bagID)
    
    -- Add new items with tabIndex
    for i = 1, #newBagItems do
        local item = newBagItems[i]
        item.tabIndex = tabIndex
        allItems[#allItems + 1] = item
    end
    
    -- Save to DB (compressed, warband bank is account-wide)
    self:SaveWarbandBankCompressed(allItems)
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
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    local allItems = {}
    local totalSlots = 0
    
    -- Scan ALL inventory bags
    for _, bagID in ipairs(INVENTORY_BAGS) do
        totalSlots = totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
        local bagItems = ScanBag(bagID)
        for i = 1, #bagItems do
            allItems[#allItems + 1] = bagItems[i]
        end
    end
    
    -- Save to DB (compressed)
    self:SaveItemsCompressed(charKey, "bags", allItems)
    
    -- Populate legacy metadata for ItemsUI header (usedSlots, totalSlots, lastScan).
    -- This replaces the expensive DataService:ScanCharacterBags() login scan which called
    -- C_Item.GetItemInfo() per slot. We compute the same metadata from our lean scan.
    if self.db and self.db.char then
        if not self.db.char.bags then self.db.char.bags = {} end
        self.db.char.bags.usedSlots = #allItems
        self.db.char.bags.totalSlots = totalSlots
        self.db.char.bags.lastScan = time()
    end
    
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
        charKey = ns.Utilities:GetCharacterKey()
    end
    
    local allItems = {}
    
    -- Scan ALL bank bags (NO FLAG CHECK - just scan)
    for _, bagID in ipairs(BANK_BAGS) do
        local bagItems = ScanBag(bagID)
        for i = 1, #bagItems do
            allItems[#allItems + 1] = bagItems[i]
        end
    end
    
    -- Save to DB (compressed)
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
        for i = 1, #bagItems do
            local item = bagItems[i]
            -- Add tab index for warband bank (1-5)
            item.tabIndex = tabIndex
            allItems[#allItems + 1] = item
        end
    end
    
    -- Save to global (compressed, warband bank is account-wide)
    self:SaveWarbandBankCompressed(allItems)
    
    return allItems
end

-- ============================================================================
-- THROTTLED UPDATE SYSTEM
-- ============================================================================

---Throttled bag update (prevents BAG_UPDATE spam)
---Returns true if the update was processed (or scheduled), false if suppressed.
---@param bagID number Bag ID
---@return boolean processed
local function ThrottledBagUpdate(bagID)
    -- Suppress during bank open deferred scans (OnBankOpened handles it)
    if bankScanInProgress then
        return false
    end
    
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
                    local processed = ThrottledBagUpdate(bagID)  -- Retry
                    -- Send coalesced message for deferred retry (no caller to batch with)
                    if processed then
                        local retryCharKey = ns.Utilities:GetCharacterKey()
                        WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "batch", charKey = retryCharKey})
                    end
                end
            end)
        end
        return false
    end
    
    lastUpdateTime[bagID] = currentTime
    pendingUpdates[bagID] = nil
    
    -- Determine bag type via O(1) lookup and scan INCREMENTALLY (only changed bag)
    local charKey = ns.Utilities:GetCharacterKey()
    local bagType = BAG_TYPE_LOOKUP[bagID]
    
    if bagType == "inventory" then
        WarbandNexus:UpdateSingleBag(charKey, bagID)
        return true  -- message sent by caller (batched)
    elseif bagType == "bank" then
        if isBankOpen then
            WarbandNexus:UpdateSingleBag(charKey, bagID)
            return true
        end
        return false
    elseif bagType == "warband" then
        if isWarbandBankOpen then
            WarbandNexus:UpdateSingleWarbandBag(bagID)
            return true
        end
        return false
    end
    
    return false
end

---Process pending bag updates (called by timer)
function WarbandNexus:ProcessPendingBagUpdates()
    local anyProcessed = false
    for bagID, _ in pairs(pendingUpdates) do
        if ThrottledBagUpdate(bagID) then
            anyProcessed = true
        end
    end
    -- Batch: one message for all processed pending bags
    if anyProcessed then
        local charKey = ns.Utilities:GetCharacterKey()
        self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "batch", charKey = charKey})
    end
end

-- ============================================================================
-- EVENT HANDLERS (Will be registered by EventManager)
-- ============================================================================

---Handle BAG_UPDATE event (from RegisterBucketEvent)
---Batches all bag updates and sends ONE coalesced ITEMS_UPDATED message
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
    
    -- Process each bag that was updated, track if any actually changed
    local anyProcessed = false
    for bagID in pairs(bagIDs) do
        -- Smart filter: Check if bag contents actually changed
        if HasBagChanged(bagID) then
            if ThrottledBagUpdate(bagID) then
                anyProcessed = true
            end
        end
    end
    
    -- Send ONE coalesced message for all processed bags (instead of per-bag)
    if anyProcessed then
        local charKey = ns.Utilities:GetCharacterKey()
        self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "batch", charKey = charKey})
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
    bankScanInProgress = true  -- Suppress ThrottledBagUpdate while we do the full scan
    
    local charKey = ns.Utilities:GetCharacterKey()
    
    -- Defer scans across frames to avoid a single-frame FPS spike
    -- (inventory + bank + warband = hundreds of slots scanned synchronously)
    C_Timer.After(0, function()
        self:ScanInventoryBags(charKey)
        C_Timer.After(0.05, function()
            self:ScanBankBags(charKey)
            C_Timer.After(0.05, function()
                self:ScanWarbandBank()
                bankScanInProgress = false  -- Re-enable incremental updates
                self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "all", charKey = charKey})
            end)
        end)
    end)
end

---Handle BANKFRAME_CLOSED event
function WarbandNexus:OnBankClosed()
    isBankOpen = false
    isWarbandBankOpen = false  -- Both tabs close together
    bankScanInProgress = false  -- Safety: ensure flag is cleared
    DebugPrint("|cff9370DB[WN ItemsCache]|r [Bank Event] BANKFRAME_CLOSED")
end

---Handle BAG_UPDATE_DELAYED (fires once after all pending bag operations complete)
---
---ARCHITECTURE NOTE: This is a lightweight "settled" signal, NOT a data scanner.
---Data updates are already handled by the BAG_UPDATE bucket → ThrottledBagUpdate → SingleBagUpdate.
---
---BAG_UPDATE_DELAYED "settled" signal handler.
---
---ARCHITECTURE: This is a NO-OP handler. Data updates are already handled by:
---  - BAG_UPDATE bucket (0.5s) → OnBagUpdate → ThrottledBagUpdate → fires WN_ITEMS_UPDATED
---  - CollectionService raw frame → ScanBagsForNewCollectibles (independent)
---
---Previously fired WN_BAGS_UPDATED here (1.0s debounce), causing DOUBLE UI refresh
---for every bag change: WN_ITEMS_UPDATED at ~0.5s + WN_BAGS_UPDATED at ~1.5s.
---The 800ms cooldown in UI.lua suppressed most of these but still caused unnecessary
---handler invocations and timer management overhead.
---
---REMOVED: WN_BAGS_UPDATED fire (redundant with WN_ITEMS_UPDATED from OnBagUpdate).
---REMOVED: GetBagFingerprint (~100+ API calls) and ScanInventoryBags (full redundant scan).
function WarbandNexus:OnInventoryBagsChanged()
    -- Intentionally empty: BAG_UPDATE bucket handles all data updates.
    -- This handler exists only to consume the BAG_UPDATE_DELAYED registration
    -- so no "unhandled event" warnings fire. All real work is in OnBagUpdate.
end

-- OnWarbandBankFrameOpened / OnWarbandBankFrameClosed: REMOVED — Dead code.
-- These handlers were defined but never registered to any event.
-- Warband bank scanning is handled by OnBankOpened (BANKFRAME_OPENED) which scans
-- all bank types including warband tabs. BAG_UPDATE bucket catches incremental changes.

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
    local charKey = ns.Utilities:GetCharacterKey()
    
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
        
        local charKey = ns.Utilities:GetCharacterKey()
        self:ScanInventoryBags(charKey)
        
        -- Mark loading complete
        ns.ItemsLoadingState.isLoading = false
        ns.ItemsLoadingState.scanProgress = 100
        ns.ItemsLoadingState.currentStage = nil
        
        -- Notify UI that initial scan is done (fixes stuck loading state)
        self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "all", charKey = charKey})
    end)
end

-- ============================================================================
-- LOAD MESSAGE
-- ============================================================================

-- Module loaded - verbose logging hidden (debug mode only)
