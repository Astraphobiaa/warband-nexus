--[[
    Warband Nexus - Items Cache Service
    Hash-filtered bag/bank scans with per-character DB persistence.
    Session RAM (decompressedItemCache) is authoritative during play.
    Fast uncompressed AceDB write ~15s after last bag change (Alt+F4 safety);
    LibDeflate compress on logout / PLAYER_LEAVING_WORLD (/reload) only.
    Emits WN_ITEMS_UPDATED after writes.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue

-- Debug print helper (only prints if debug mode enabled)
local DebugPrint = ns.DebugPrint
local DebugVerbosePrint = ns.DebugVerbosePrint or function() end

-- Keystone detection moved to PvECacheService (C_MythicPlus API, event-driven)

-- Get library references for compression
local LibSerialize = LibStub("AceSerializer-3.0")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local debugprofilestop = debugprofilestop

-- CONSTANTS

local Constants = ns.Constants
local CACHE_VERSION = Constants.ITEMS_CACHE_VERSION

--- Persisted itemStorage key for the logged-in character (GUID slot when available).
local function ResolveCurrentItemStorageKey()
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, nil)
        if k and k ~= "" then return k end
    end
    local ck = CS and CS.ResolveCharactersTableKey and CS:ResolveCharactersTableKey(WarbandNexus)
    if not ck and ns.Utilities.GetCharacterStorageKey then
        ck = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    end
    if not ck and ns.Utilities.GetCharacterStorageKey then
        ck = ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    end
    return ck
end

local function CanonicalItemsMessageKey(storageKey)
    local k = storageKey
    if k and ns.Utilities.GetCanonicalCharacterKey then
        return ns.Utilities:GetCanonicalCharacterKey(k) or k
    end
    return k
end

-- Forward declaration (defined with the read-model helpers below); incremental
-- bag updates need alias-aware bucket resolution without the legacy merge.
local ResolveItemStorageRow

--- Bump when persisted bag/bank/warband data or item metadata changes so Gear storage scan cache invalidates.
local gearStorageBumpTimer = nil
local function BumpGearStorageScanGeneration()
    if gearStorageBumpTimer then return end
    gearStorageBumpTimer = C_Timer.NewTimer(0.25, function()
        gearStorageBumpTimer = nil
        ns._gearStorageInvGen = (ns._gearStorageInvGen or 0) + 1
    end)
end

local function BumpGearStorageScanGenerationImmediate()
    if gearStorageBumpTimer then
        gearStorageBumpTimer:Cancel()
        gearStorageBumpTimer = nil
    end
    ns._gearStorageInvGen = (ns._gearStorageInvGen or 0) + 1
end

local UPDATE_THROTTLE = Constants.THROTTLE.ITEMS_BAG_UPDATE or 0.5

-- Bag ID ranges
local INVENTORY_BAGS = ns.INVENTORY_BAGS or {0, 1, 2, 3, 4, 5} -- Includes reagent bag
local BANK_BAGS = ns.PERSONAL_BANK_BAGS or {-1, 6, 7, 8, 9, 10, 11}
local WARBAND_BAGS = ns.WARBAND_BAGS or {13, 14, 15, 16, 17}

-- O(1) bag type lookup table (replaces 3 sequential linear searches in ThrottledBagUpdate)
local BAG_TYPE_LOOKUP = {}  -- [bagID] = "inventory" | "bank" | "warband"
for i = 1, #INVENTORY_BAGS do
    local id = INVENTORY_BAGS[i]
    BAG_TYPE_LOOKUP[id] = "inventory"
end
for i = 1, #BANK_BAGS do
    local id = BANK_BAGS[i]
    BAG_TYPE_LOOKUP[id] = "bank"
end
for i = 1, #WARBAND_BAGS do
    local id = WARBAND_BAGS[i]
    BAG_TYPE_LOOKUP[id] = "warband"
end

-- STATE MANAGEMENT

-- Global loading state (accessible from UI)
ns.ItemsLoadingState = {
    isLoading = false,           -- Currently scanning bags
    scanProgress = 0,            -- 0-100 progress percentage
    loadingProgress = 0,       -- Mirror for UI_CreateLoadingStateCard (also reads loadingProgress)
    currentStage = nil,          -- Current stage (e.g., "Scanning Inventory")
}

-- Bank frame state (event-based detection)
local isBankOpen = false
local isWarbandBankOpen = false
local bankScanInProgress = false  -- True during OnBankOpened deferred scans; suppresses duplicate work
local bankOpenScanGeneration = 0   -- Supersede in-flight RunBudgetedBankOpenScan (bank close / new open)
local warbandBankScanGeneration = 0  -- Invalidate live warband tooltip tally (guildBankScanGeneration parity)
local liveOpenWarbandSummary = nil   -- { items = { [itemID] = N }, gen = N } session cache while bank open

-- Hash cache for bag change detection (RAM only)
local bagHashCache = {} -- [bagID] = hash

-- Throttle timers
local lastUpdateTime = {}
local pendingUpdates = {}

-- DECOMPRESSED DATA SESSION CACHE
-- Avoids repeated decompress+deserialize on every GetItemsData()/tooltip hover.
-- Invalidated per-key when items are scanned. Cleared on UI OnHide.
local decompressedItemCache = {}  -- [charKey] = { bags={}, bank={}, bagsLastUpdate=N, bankLastUpdate=N }
local decompressedWarbandCache = nil  -- { items={}, lastUpdate=N }

-- PRE-INDEXED ITEM COUNT SUMMARY
-- Instead of iterating ALL items on every tooltip hover, maintain a
-- pre-computed { [itemID] = { bags=N, bank=N } } per character.
-- Rebuilt lazily: marked "pending" when items change, processed on next tooltip access.
local itemSummaryIndex = {
    characters = {},  -- [charKey] = { [itemID] = { bags=N, bank=N } }
    warband = {},     -- [itemID] = N
    guild = {},       -- [guildName] = { [itemID] = N }
    pending = {},     -- [charKey] = true (needs rebuild)
    warbandPending = false,
    guildPending = false,
    coldInitDone = false,
    sessionGen = {},  -- [charKey] = { bags=N, bank=N } bumped on incremental writes
}

local SUMMARY_BUILD_BUDGET_MS = 4
local COMPRESS_FLUSH_BUDGET_MS = 8
local SESSION_ACTIVITY_PERSIST_SEC = 15  -- after last bag change; no LibDeflate (Alt+F4 window)
local SESSION_IDLE_FLUSH_SEC = 45       -- safety backup if activity timer missed
local COLLECTION_SNAPSHOT_TTL = 0.65
-- Session RAM is authoritative during play; see PersistSessionDirtyFast + FlushPendingCompressWrites.
local sessionDirtyBuckets = {}  -- [charKey .. "\0" .. dataType] = true
local pendingCompressSaves = {}  -- [charKey .. "\0" .. dataType] = { charKey, dataType, items }
local sessionIdleFlushTicker = nil
local sessionActivityPersistTimer = nil
local summaryDrainScheduled = false
local deferredThrottleTimer = nil
-- Forward declarations (mutual recursion + timer callback before definitions below).
local ThrottledBagUpdate
local ScheduleDeferredBagFlush
local FlushPendingCompressWrites
local PersistSessionDirtyFast
local ScheduleSessionActivityPersist

local function CompressSaveKey(charKey, dataType)
    return tostring(charKey) .. "\0" .. tostring(dataType)
end

local function V2BucketCacheHit(cached, charKey, dataType, bucketLU)
    if not cached then return false end
    if sessionDirtyBuckets[CompressSaveKey(charKey, dataType)] then
        if dataType == "bags" and cached.bags then return true end
        if dataType == "bank" and cached.bank then return true end
    end
    if bucketLU > 0 then
        if dataType == "bags" and cached.bags and cached.bagsLastUpdate == bucketLU then
            return true
        end
        if dataType == "bank" and cached.bank and cached.bankLastUpdate == bucketLU then
            return true
        end
    end
    return false
end

-- Session-only item metadata cache (never persisted)
-- C_Item.GetItemInfoInstant is fast but we still avoid redundant calls
local itemMetadataCache = {}       -- [itemID] = { name, link, icon, classID, subclassID, itemType, pending? }
local itemMetadataCacheOrder = {}  -- FIFO eviction order tracking (head index + count)
local itemMetadataCacheHead = 1    -- Circular buffer head index
local ITEM_METADATA_CACHE_MAX = 2048

-- Async item metadata resolution tracking
local pendingItemLoads = {}              -- [itemID] = true (prevents duplicate async loads)
local pendingMetadataRefreshTimer = nil  -- Debounce timer for UI refresh after batch resolution

-- COMPRESSION UTILITIES

---Compress item data for storage
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

--- v2 itemStorage bucket array without legacy merge; reuse session RAM when lastUpdate matches.
--- (GetItemsData merges legacy rows — unsafe for read-modify-write; this path is v2-only.)
local function AcquireV2BucketItemArray(charKey, dataType)
    local storage = ResolveItemStorageRow(charKey)
    local bucket = storage and storage[dataType]
    local bucketLU = bucket and bucket.lastUpdate or 0

    local cached = decompressedItemCache[charKey]
    if V2BucketCacheHit(cached, charKey, dataType, bucketLU) then
        local BP = ns.ItemsCacheBagPerf
        if BP and BP.NoteAcquire then BP.NoteAcquire(true) end
        if dataType == "bags" then
            return cached.bags, true
        end
        return cached.bank, true
    end

    local allItems
    if bucket and bucket.compressed then
        allItems = DecompressItemData(bucket.data) or {}
    elseif bucket then
        allItems = bucket.data or {}
    else
        allItems = {}
    end

    local BP = ns.ItemsCacheBagPerf
    if BP and BP.NoteAcquire then BP.NoteAcquire(false) end

    if not cached then
        cached = { bags = {}, bank = {}, bagsLastUpdate = 0, bankLastUpdate = 0 }
        decompressedItemCache[charKey] = cached
    end
    if dataType == "bags" then
        cached.bags = allItems
        cached.bagsLastUpdate = bucketLU
    else
        cached.bank = allItems
        cached.bankLastUpdate = bucketLU
    end
    return allItems, false
end

local function TouchDecompressedItemCache(charKey, dataType, items, lastUpdate)
    if not charKey or not dataType or not items then return end
    local ent = decompressedItemCache[charKey]
    if not ent then
        ent = { bags = {}, bank = {}, bagsLastUpdate = 0, bankLastUpdate = 0 }
        decompressedItemCache[charKey] = ent
    end
    local lu = lastUpdate or time()
    if dataType == "bags" then
        ent.bags = items
        ent.bagsLastUpdate = lu
    else
        ent.bank = items
        ent.bankLastUpdate = lu
    end
end

---Rolling hash of lean bucket rows; skip LibDeflate when semantic content unchanged.
local function ComputeBucketContentSig(items)
    local h = 5381
    for i = 1, #items do
        local it = items[i]
        if it and it.itemID then
            h = (h * 33 + (it.itemID or 0)) % 2147483647
            h = (h * 33 + (it.stackCount or 1)) % 2147483647
            h = (h * 33 + (it.bagID or 0)) % 2147483647
            h = (h * 33 + (it.slot or it.slotIndex or 0)) % 2147483647
        end
    end
    return h
end

local function BumpSummarySessionGen(charKey, dataType)
    local gen = itemSummaryIndex.sessionGen[charKey]
    if not gen then
        gen = { bags = 0, bank = 0 }
        itemSummaryIndex.sessionGen[charKey] = gen
    end
    if dataType == "bags" then
        gen.bags = (gen.bags or 0) + 1
    else
        gen.bank = (gen.bank or 0) + 1
    end
    return gen
end

local function SummaryIsCurrent(charKey)
    if itemSummaryIndex.pending[charKey] then return false end
    if not itemSummaryIndex.characters[charKey] then return false end
    local gen = itemSummaryIndex.sessionGen[charKey]
    if not gen then return false end
    local cached = decompressedItemCache[charKey]
    if not cached then return false end
    return gen.bags == (cached.bagsSessionGen or 0) and gen.bank == (cached.bankSessionGen or 0)
end

---O(slots in bag) tooltip summary patch — avoids full bags+bank walk on every loot move.
local function ApplyBagDeltaToSummary(charKey, dataType, oldBagItems, newBagItems)
    local field = (dataType == "bags") and "bags" or "bank"
    local summary = itemSummaryIndex.characters[charKey]
    if not summary then
        itemSummaryIndex.pending[charKey] = true
        return false
    end
    for i = 1, #oldBagItems do
        local item = oldBagItems[i]
        if item and item.itemID then
            local entry = summary[item.itemID]
            if entry then
                entry[field] = entry[field] - (item.stackCount or 1)
                if entry.bags <= 0 and entry.bank <= 0 then
                    summary[item.itemID] = nil
                end
            end
        end
    end
    for i = 1, #newBagItems do
        local item = newBagItems[i]
        if item and item.itemID then
            local entry = summary[item.itemID]
            if not entry then
                entry = { bags = 0, bank = 0 }
                summary[item.itemID] = entry
            end
            entry[field] = entry[field] + (item.stackCount or 1)
        end
    end
    itemSummaryIndex.pending[charKey] = nil
    BumpSummarySessionGen(charKey, dataType)
    local gen = itemSummaryIndex.sessionGen[charKey]
    local cached = decompressedItemCache[charKey]
    if cached and gen then
        if dataType == "bags" then
            cached.bagsSessionGen = gen.bags
        else
            cached.bankSessionGen = gen.bank
        end
    end
    return true
end

---Multiset of itemID:stackCount for one bag scan (reorder-only detection).
local function BagInventorySignature(items)
    local sig = {}
    for i = 1, #items do
        local it = items[i]
        if it and it.itemID then
            local k = tostring(it.itemID) .. ":" .. tostring(it.stackCount or 1)
            sig[k] = (sig[k] or 0) + 1
        end
    end
    return sig
end

local function BagSignaturesEqual(a, b)
    for k, v in pairs(a) do
        if (b[k] or 0) ~= v then return false end
    end
    for k, v in pairs(b) do
        if (a[k] or 0) ~= v then return false end
    end
    return true
end

---Share recent bag slot map with CollectionService_Scan (skip duplicate C_Container walks).
local function PublishBagSnapshotForCollection(bagID, bagItems)
    if bagID == nil or bagID < 0 or bagID > 4 then return end
    local snaps = ns.ItemsCacheBagSnapshots
    if not snaps then
        snaps = {}
        ns.ItemsCacheBagSnapshots = snaps
    end
    local entry = snaps[bagID]
    local slotMap = entry and entry.slots
    if not slotMap then
        slotMap = {}
    else
        wipe(slotMap)
    end
    for i = 1, #bagItems do
        local it = bagItems[i]
        local slot = it and (it.slot or it.slotIndex)
        if slot and it.itemID then
            slotMap[bagID .. "_" .. slot] = it.itemID
        end
    end
    if entry then
        entry.at = GetTime()
    else
        snaps[bagID] = { slots = slotMap, at = GetTime() }
    end
end

-- Perf stress phase capture (ItemsCacheService_PerfStress.lua; optional during /wn bagdebug stress)
local StressHooks = {}
ns.ItemsCacheStressHooks = StressHooks

local function RecordStressPhase(name)
    local rec = StressHooks._recording
    if not rec then return end
    local now = debugprofilestop()
    if rec.t0 then
        rec.phases[name] = (rec.phases[name] or 0) + (now - rec.t0)
    end
    rec.t0 = now
end

local function TouchDecompressedSessionGen(charKey, dataType)
    local ent = decompressedItemCache[charKey]
    if not ent then return end
    local gen = itemSummaryIndex.sessionGen[charKey]
    if not gen then return end
    if dataType == "bags" then
        ent.bagsSessionGen = gen.bags
    else
        ent.bankSessionGen = gen.bank
    end
end

-- ON-DEMAND ITEM METADATA RESOLVER (Session RAM only)

---Add a fully-resolved metadata entry to the FIFO eviction cache.
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

---Fill missing icon on metadata (async name resolution used to skip texture).
local function FillMetadataIcon(metadata, itemID, itemLink)
    if not metadata then return end
    if metadata.iconFileID and metadata.iconFileID ~= 0 then return end
    local U = ns.Utilities
    if not U or not U.ResolveItemIconFileID then return end
    local icon = U:ResolveItemIconFileID(itemLink or itemID)
    if icon and icon ~= 0 then
        metadata.icon = icon
        metadata.iconFileID = icon
    end
end

---Sync decompressed item cache with resolved metadata.
---HydrateItem does value copies (not references), so after async resolution
---the cached items still have name=nil, pending=true. This function patches
---them in-place so the UI sees updated names without a full re-hydration.
local function SyncDecompressedCacheWithMetadata()
    local syncedCount = 0

    local function PatchCachedItem(item)
        if not item or not item.itemID then return end
        local meta = itemMetadataCache[item.itemID]
        if not meta then return end
        FillMetadataIcon(meta, item.itemID, item.itemLink or item.link or meta.link)

        local changed = false
        if item.pending and not meta.pending then
            item.name = meta.name
            item.link = item.link or meta.link
            item.classID = item.classID or meta.classID
            item.pending = nil
            changed = true
        end
        local icon = meta.iconFileID or meta.icon
        if (not item.iconFileID or item.iconFileID == 0) and icon and icon ~= 0 then
            item.iconFileID = icon
            changed = true
        end
        if changed then
            syncedCount = syncedCount + 1
        end
    end

    -- Sync personal item caches (bags + bank per character)
    for charKey, data in pairs(decompressedItemCache) do
        local sources = {"bags", "bank"}
        for i = 1, #sources do
            local source = sources[i]
            local items = data[source]
            if items then
                for j = 1, #items do
                    PatchCachedItem(items[j])
                end
            end
        end
    end
    -- Sync warband bank cache
    if decompressedWarbandCache and decompressedWarbandCache.items then
        for i = 1, #decompressedWarbandCache.items do
            PatchCachedItem(decompressedWarbandCache.items[i])
        end
    end
    return syncedCount
end

---Debounced UI refresh after async item metadata resolution.
---Fires WN_ITEM_METADATA_READY so the UI can re-read metadata from the cache.
---Syncs decompressed caches before firing the event so items show resolved names.
local function ScheduleMetadataRefresh()
    if pendingMetadataRefreshTimer then
        pendingMetadataRefreshTimer:Cancel()
    end
    pendingMetadataRefreshTimer = C_Timer.NewTimer(0, function()
        pendingMetadataRefreshTimer = nil
        -- Patch cached items with resolved metadata before notifying UI
        local synced = SyncDecompressedCacheWithMetadata()
        -- Only notify UI if items were actually updated (prevents unnecessary redraws)
        if synced > 0 then
            -- Do NOT bump `ns._gearStorageInvGen` here: that invalidates Gear stash cache on every
            -- metadata batch and causes repeated full FindGearStorageUpgrades for the same character
            -- (visible as triple "Scan ... Reject/add" lines + frame spikes). Stash invalidation is
            -- driven from UI.lua on ITEM_METADATA_READY / GET_ITEM_INFO (narrow refresh; no invGen bump here).
            WarbandNexus:SendMessage(Constants.EVENTS.ITEM_METADATA_READY)
        end
    end)
end

---Queue async item load via Item:CreateFromItemID + ContinueOnItemLoad.
---When the item data becomes available, updates the metadata cache and schedules a UI refresh.
local function QueueAsyncItemLoad(itemID)
    if pendingItemLoads[itemID] then return end  -- Already queued
    pendingItemLoads[itemID] = true
    
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        pendingItemLoads[itemID] = nil
        
        -- Fetch now-available data (include texture — rows used to keep question-mark icons)
        local resolvedName, resolvedLink, _, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        if not resolvedName then return end  -- Safety: still not available (shouldn't happen)
        
        -- Update existing cache entry (or create new one)
        local existing = itemMetadataCache[itemID]
        if existing then
            existing.name = resolvedName
            existing.link = resolvedLink
            existing.pending = nil
            if texture and texture ~= 0 then
                existing.icon = texture
                existing.iconFileID = texture
            else
                FillMetadataIcon(existing, itemID, resolvedLink)
            end
            -- Now fully resolved: add to FIFO eviction
            AddToFIFOCache(itemID)
        end
        
        -- Schedule debounced UI refresh (batches multiple resolutions)
        ScheduleMetadataRefresh()
    end)
end

---Resolve item metadata from WoW API (session RAM cache, never persisted).
---Uses ContinueOnItemLoad for async resolution of uncached items.
local function ResolveItemMetadata(itemID)
    if not itemID or itemID == 0 then return nil end
    
    -- Check RAM cache (return immediately if fully resolved)
    local cached = itemMetadataCache[itemID]
    if cached and not cached.pending then
        FillMetadataIcon(cached, itemID)
        return cached
    end
    -- If pending, re-check API (may have resolved since last call)
    if cached and cached.pending then
        local name, link, _, _, _, _, _, _, _, texture
        if C_Item and C_Item.GetItemInfo then
            name, link, _, _, _, _, _, _, _, texture = C_Item.GetItemInfo(itemID)
        end
        if name then
            cached.name = name
            cached.link = link
            cached.pending = nil
            if texture and texture ~= 0 then
                cached.icon = texture
                cached.iconFileID = texture
            else
                FillMetadataIcon(cached, itemID, link)
            end
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
    
    FillMetadataIcon(metadata, itemID, link)

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

--[[
    Session cold-cache hint: prime RAM metadata for equipped items only (no GearService tooltip upgrade scan).
    PLAYER_ENTERING_WORLD (login/reload) schedules via InitializationService — ns.GEAR_SLOTS exists at runtime (GearService loads later in TOC but before timers fire).
]]
function WarbandNexus:PrefetchSessionEquippedItemMetadata()
    local mods = self.db and self.db.profile and self.db.profile.modulesEnabled
    if mods then
        if mods.items == false and mods.gear == false and mods.storage == false then
            return
        end
    end

    if ns.CharacterService and not ns.CharacterService:IsCharacterTracked(self) then
        return
    end

    local gearSlots = ns.GEAR_SLOTS
    if not gearSlots then return end

    for si = 1, #gearSlots do
        local slotDef = gearSlots[si]
        local slotID = slotDef and slotDef.id
        if slotID then
            local itemLink = GetInventoryItemLink("player", slotID)
            if itemLink and issecretvalue and issecretvalue(itemLink) then
                itemLink = nil
            end
            if itemLink then
                local itemID = nil
                pcall(function()
                    if C_Item and C_Item.GetItemInfoInstant then
                        itemID = C_Item.GetItemInfoInstant(itemLink)
                    end
                end)
                if not itemID and type(itemLink) == "string" and not (issecretvalue and issecretvalue(itemLink)) then
                    local idFromLink = itemLink:match("item:(%d+)")
                    itemID = idFromLink and tonumber(idFromLink) or nil
                end
                if itemID and itemID ~= 0 then
                    ResolveItemMetadata(itemID)
                end
            end
        end
    end
end

---Hydrate a lean item (from SV) with on-demand metadata (value copy, not reference).
---Sets item.pending = true if the item name is still being loaded asynchronously.
---NOTE: After async resolution, SyncDecompressedCacheWithMetadata() patches items in-place.
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
        item.iconFileID = item.iconFileID or metadata.iconFileID or metadata.icon
        item.classID = item.classID or metadata.classID
        item.subclassID = item.subclassID or metadata.subclassID
        item.itemType = item.itemType or metadata.itemType
        if item.itemType == "" then item.itemType = nil end
        if (not item.iconFileID or item.iconFileID == 0) and ns.Utilities and ns.Utilities.ResolveItemIconFileID then
            local icon = ns.Utilities:ResolveItemIconFileID(originalLink or item.itemID)
            if icon and icon ~= 0 then
                item.iconFileID = icon
            end
        end
        -- Propagate pending state to item (UI uses this to show loading indicator)
        item.pending = metadata.pending or nil
    end
    if item.itemType == "" then item.itemType = nil end
    
    return item
end

---Hydrate an array of lean items with metadata.
local function HydrateItems(items)
    if not items then return items end
    for i = 1, #items do
        local item = items[i]
        HydrateItem(item)
    end
    return items
end

---Same key used for itemStorage writes (GUID-first subsidiary key).
function WarbandNexus:ResolveItemStorageReadKey()
    return ResolveCurrentItemStorageKey()
end

---Drop one character's decompressed itemStorage RAM cache (e.g. tally vs list mismatch).
function WarbandNexus:InvalidateItemsDataCache(charKey)
    if not charKey or charKey == "" then return end
    decompressedItemCache[charKey] = nil
    itemSummaryIndex.pending[charKey] = true
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local alt = ns.Utilities:GetCanonicalCharacterKey(charKey)
        if alt and alt ~= charKey then
            decompressedItemCache[alt] = nil
            itemSummaryIndex.pending[alt] = true
        end
    end
end

local personalBankUIScanPending = false

---True when C_Container can read personal bank bags (bank frame open / API unlocked).
local function IsPersonalBankAPIAccessible()
    if isBankOpen or (WarbandNexus and WarbandNexus.bankIsOpen) then
        return true
    end
    local bankIdx = Enum.BagIndex and Enum.BagIndex.Bank
    if bankIdx then
        local n = C_Container.GetContainerNumSlots(bankIdx)
        if n and n > 0 then
            return true
        end
    end
    for i = 1, #BANK_BAGS do
        local n = C_Container.GetContainerNumSlots(BANK_BAGS[i])
        if n and n > 0 then
            return true
        end
    end
    return false
end

---Count occupied personal-bank slots via live API (only valid when bank is accessible).
local function CountLivePersonalBankOccupiedSlots()
    local count = 0
    for i = 1, #BANK_BAGS do
        local bagID = BANK_BAGS[i]
        local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bagID, slot)
            if info and info.itemID then
                count = count + 1
            end
        end
    end
    return count
end

---Scan personal bank when the Bank sub-tab is shown and WoW bank APIs are readable.
---@return boolean didScan
function WarbandNexus:RequestPersonalBankScanIfNeeded()
    if not ns.Utilities or not ns.Utilities.IsModuleEnabled or not ns.Utilities:IsModuleEnabled("items") then
        return false
    end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end
    if not IsPersonalBankAPIAccessible() then
        return false
    end

    isBankOpen = true
    self.bankIsOpen = true

    local charKey = ResolveCurrentItemStorageKey()
    if not charKey then return false end

    local cachedSlots = 0
    if self.GetItemStorageOccupiedSlotTally then
        cachedSlots = self:GetItemStorageOccupiedSlotTally(charKey, "bank", false) or 0
    end
    local liveSlots = CountLivePersonalBankOccupiedSlots()
    if cachedSlots > 0 and liveSlots <= cachedSlots then
        return false
    end
    if liveSlots == 0 and cachedSlots == 0 then
        -- Bank accessible but empty — still persist empty snapshot once.
        if cachedSlots == 0 and self.GetItemsData then
            local data = self:GetItemsData(charKey)
            if data and data.bankLastUpdate and data.bankLastUpdate > 0 then
                return false
            end
        end
    end

    if personalBankUIScanPending then
        return false
    end
    personalBankUIScanPending = true

    if self.ScanBankBags then
        self:ScanBankBags(charKey)
    end
    personalBankUIScanPending = false

    if self.SendMessage and Constants and Constants.EVENTS and Constants.EVENTS.ITEMS_UPDATED then
        self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {
            type = "personal_bank_scan",
            charKey = CanonicalItemsMessageKey(charKey),
        })
    end
    return true
end

---@deprecated use RequestPersonalBankScanIfNeeded
function WarbandNexus:EnsurePersonalBankScannedForDisplay()
    return self:RequestPersonalBankScanIfNeeded()
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
    liveOpenWarbandSummary = nil
    wipe(itemSummaryIndex.characters)
    wipe(itemSummaryIndex.warband)
    wipe(itemSummaryIndex.guild)
    wipe(itemSummaryIndex.pending)
    wipe(itemSummaryIndex.sessionGen)
    itemSummaryIndex.warbandPending = false
    itemSummaryIndex.guildPending = false
    itemSummaryIndex.coldInitDone = false
end

-- HASH GENERATION (CHANGE DETECTION) + BAG SCANNING

-- Per-bag cache: stores raw GetContainerItemInfo results from the hash pass
-- so ScanBag can reuse them instead of re-querying every slot.
local cachedSlotData = {}  -- [bagID] = { [slot] = itemInfo, numSlots = n }

---Generate hash for a bag to detect real changes.
---Also caches raw slot data for ScanBag to reuse (avoids double API calls).
---Hash includes: item count + item links (ignores durability, charges, cooldowns)
local function GenerateItemHash(bagID)
    local items = {}
    local n = 0
    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    local slotCache = { numSlots = numSlots }
    
    for slot = 1, numSlots do
        local itemInfo = C_Container.GetContainerItemInfo(bagID, slot)
        slotCache[slot] = itemInfo  -- Cache for ScanBag (nil entries are fine)
        if itemInfo and itemInfo.hyperlink then
            local hl = itemInfo.hyperlink
            if not (issecretvalue and issecretvalue(hl)) then
                -- Hash includes: hyperlink + stack count
                -- Does NOT include: durability, charges, cooldowns
                n = n + 1
                items[n] = hl .. ":" .. (itemInfo.stackCount or 1)
            end
        end
    end
    
    cachedSlotData[bagID] = slotCache
    return table.concat(items, "|")
end

---Check if bag contents actually changed (not just durability/charges)
local function HasBagChanged(bagID)
    local newHash = GenerateItemHash(bagID)
    local oldHash = bagHashCache[bagID]
    
    if newHash ~= oldHash then
        bagHashCache[bagID] = newHash
        local BP = ns.ItemsCacheBagPerf
        if BP and BP.NoteHashCheck then BP.NoteHashCheck(true) end
        return true
    end
    
    -- Hash unchanged: clear the cached slot data (not needed)
    cachedSlotData[bagID] = nil
    local BP = ns.ItemsCacheBagPerf
    if BP and BP.NoteHashCheck then BP.NoteHashCheck(false) end
    return false
end

--- Seed hash cache after a full bag scan so the next BAG_UPDATE bucket does not look like a change.
local function SeedBagHashForBag(bagID)
    local hash = GenerateItemHash(bagID)
    bagHashCache[bagID] = hash
end

local function SeedInventoryBagHashes()
    for i = 1, #INVENTORY_BAGS do
        SeedBagHashForBag(INVENTORY_BAGS[i])
    end
end

local function ShouldCaptureSlotItemLevel()
    return WarbandNexus.IsGearStorageRecommendationsEnabled
        and WarbandNexus:IsGearStorageRecommendationsEnabled()
end

--- Snapshot ilvl at scan time so Gear storage recommendations do not depend on cold GetItemInfo.
local function CaptureContainerSlotItemLevel(bagID, slot, itemID, itemLink)
    if bagID ~= nil and slot and ItemLocation and ItemLocation.CreateFromBagAndSlot
        and C_Item and C_Item.GetCurrentItemLevel then
        local okLoc, ilFromLoc = pcall(function()
            local loc = ItemLocation:CreateFromBagAndSlot(bagID, slot)
            if loc and loc.IsValid and loc:IsValid() then
                local v = C_Item.GetCurrentItemLevel(loc)
                if type(v) == "number" and v > 0 and not (issecretvalue and issecretvalue(v)) then
                    return v
                end
            end
            return 0
        end)
        if okLoc and ilFromLoc and ilFromLoc > 0 then return ilFromLoc end
    end
    if itemLink and not (issecretvalue and issecretvalue(itemLink)) and C_Item and C_Item.GetDetailedItemLevelInfo then
        local okD, det = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
        if okD and type(det) == "number" and det > 0 and not (issecretvalue and issecretvalue(det)) then
            return det
        end
    end
    if itemID and C_Item and C_Item.GetDetailedItemLevelInfo then
        local okI, detI = pcall(C_Item.GetDetailedItemLevelInfo, itemID)
        if okI and type(detI) == "number" and detI > 0 and not (issecretvalue and issecretvalue(detI)) then
            return detI
        end
    end
    return 0
end

---Resolve itemID from container slot (keystone hyperlinks may not parse via GetItemInfoInstant alone).
local function ResolveContainerSlotItemID(itemInfo, hl)
    local id = itemInfo and itemInfo.itemID
    if id and id > 0 then return id end
    if not hl or (issecretvalue and issecretvalue(hl)) then return nil end
    if C_Item and C_Item.GetItemInfoInstant then
        local ok, instantId = pcall(C_Item.GetItemInfoInstant, hl)
        if ok and instantId and instantId > 0 then return instantId end
    end
    if type(hl) == "string" then
        local idFromLink = hl:match("item:(%d+)")
        if idFromLink then
            local n = tonumber(idFromLink)
            if n and n > 0 then return n end
        end
    end
    return nil
end

---Scan a specific bag and return LEAN item data (metadata stripped).
---Reuses cached slot data from GenerateItemHash when available (single pass).
---Only stores: itemID, stackCount, quality, isBound, positional fields.
---Metadata (name, link, icon, classID) is resolved on-demand when reading.
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
                local hl = itemInfo.hyperlink
                if not (issecretvalue and issecretvalue(hl)) then
                    local itemID = ResolveContainerSlotItemID(itemInfo, hl)
                    if itemID then
                        n = n + 1
                        local snapIlvl = ShouldCaptureSlotItemLevel()
                            and CaptureContainerSlotItemLevel(bagID, slot, itemID, hl) or 0
                        local isKs = hl:find("|Hkeystone:", 1, true) ~= nil
                        items[n] = {
                            actualBagID = bagID,
                            bagID = bagID,
                            slotIndex = slot,
                            slot = slot,
                            itemID = itemID,
                            itemLink = hl,
                            stackCount = itemInfo.stackCount or 1,
                            quality = itemInfo.quality,
                            isBound = itemInfo.isBound or false,
                            itemLevel = (snapIlvl > 0) and snapIlvl or nil,
                            isKeystone = isKs or nil,
                        }
                    end
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
                local hl = itemInfo.hyperlink
                if not (issecretvalue and issecretvalue(hl)) then
                    local itemID = ResolveContainerSlotItemID(itemInfo, hl)
                    if itemID then
                        n = n + 1
                        local snapIlvl = ShouldCaptureSlotItemLevel()
                            and CaptureContainerSlotItemLevel(bagID, slot, itemID, hl) or 0
                        local isKs = hl:find("|Hkeystone:", 1, true) ~= nil
                        items[n] = {
                            actualBagID = bagID,
                            bagID = bagID,
                            slotIndex = slot,
                            slot = slot,
                            itemID = itemID,
                            itemLink = hl,
                            stackCount = itemInfo.stackCount or 1,
                            quality = itemInfo.quality,
                            isBound = itemInfo.isBound or false,
                            itemLevel = (snapIlvl > 0) and snapIlvl or nil,
                            isKeystone = isKs or nil,
                        }
                    end
                end
            end
        end
    end
    
    return items
end

---Replace one bag's rows in-place (keeps decompressedItemCache table reference).
---Optional outOldBagItems: capture removed rows in the same pass (avoids a second full-array walk).
local function ReplaceBagInItemArray(allItems, bagID, newBagItems, outOldBagItems)
    local writeIdx = 0
    local oldN = 0
    for i = 1, #allItems do
        local it = allItems[i]
        if it and it.bagID == bagID then
            if outOldBagItems then
                oldN = oldN + 1
                outOldBagItems[oldN] = it
            end
        elseif it then
            writeIdx = writeIdx + 1
            if writeIdx ~= i then
                allItems[writeIdx] = it
            end
        end
    end
    if outOldBagItems then
        for i = oldN + 1, #outOldBagItems do
            outOldBagItems[i] = nil
        end
    end
    for i = 1, #newBagItems do
        writeIdx = writeIdx + 1
        allItems[writeIdx] = newBagItems[i]
    end
    for i = writeIdx + 1, #allItems do
        allItems[i] = nil
    end
    return allItems, writeIdx
end

---Scan all inventory bags for current character
---INCREMENTAL UPDATE: Update only specific bag (single bag scan)
function WarbandNexus:UpdateSingleBag(charKey, bagID)
    -- GUARD: Only update bags if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not charKey then
        charKey = ResolveCurrentItemStorageKey()
    end
    
    local bagType = BAG_TYPE_LOOKUP[bagID]
    if bagType ~= "inventory" and bagType ~= "bank" then
        return {}
    end
    
    -- Read-modify-write the canonical v2 bucket only (alias-aware, NO legacy merge).
    -- Reuse decompressedItemCache when fresh — v3.1.8 regressed to decompress every
    -- BAG_UPDATE (LibSerialize+Deflate per loot tick); GetItemsData still merges legacy.
    local dataType = (bagType == "inventory") and "bags" or "bank"
    local BP = ns.ItemsCacheBagPerf
    local perfCtx = BP and BP.BeginBagUpdate and BP.BeginBagUpdate(bagID, charKey, dataType)
    if perfCtx and BP.SetActiveCtx then BP.SetActiveCtx(perfCtx) end

    local allItems, cacheHit = AcquireV2BucketItemArray(charKey, dataType)
    if perfCtx then
        perfCtx.cacheHit = cacheHit
        if BP.MarkPhase then BP.MarkPhase(perfCtx, "acquire") end
    end
    RecordStressPhase("acquire")

    local oldBagItems = {}
    local newBagItems = ScanBag(bagID)
    if perfCtx and BP.MarkPhase then
        BP.MarkPhase(perfCtx, "scan")
    end
    RecordStressPhase("scan")

    local _, slotCount = ReplaceBagInItemArray(allItems, bagID, newBagItems, oldBagItems)
    if perfCtx and BP.MarkPhase then
        BP.MarkPhase(perfCtx, "merge")
    end
    RecordStressPhase("merge")

    if dataType == "bags" and bagID >= 0 and bagID <= 4 then
        PublishBagSnapshotForCollection(bagID, newBagItems)
    end
    RecordStressPhase("snapshot")

    if not ApplyBagDeltaToSummary(charKey, dataType, oldBagItems, newBagItems) then
        itemSummaryIndex.pending[charKey] = true
    end
    if perfCtx and BP.MarkPhase then BP.MarkPhase(perfCtx, "summary") end
    RecordStressPhase("summary")

    local compositionChanged = not BagSignaturesEqual(
        BagInventorySignature(oldBagItems),
        BagInventorySignature(newBagItems)
    )
    
    -- Session RAM only — fast uncompressed persist debounced; LibDeflate on logout/reload
    self:SaveItemsCompressed(charKey, dataType, allItems)
    if compositionChanged then
        BumpGearStorageScanGeneration()
    end
    if perfCtx and BP.MarkPhase then BP.MarkPhase(perfCtx, "save") end
    RecordStressPhase("save")
    if perfCtx then
        perfCtx.slotCount = slotCount
        if BP.FinishBagUpdate then BP.FinishBagUpdate(perfCtx) end
        if BP.ClearActiveCtx then BP.ClearActiveCtx() end
    end
    
    return allItems
end

---INCREMENTAL UPDATE: Update only a specific warband bank bag (single tab scan)
---Avoids full ScanWarbandBank() which scans all 5 tabs on every change
function WarbandNexus:UpdateSingleWarbandBag(bagID)
    
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Determine tabIndex from WARBAND_BAGS array position
    local tabIndex = nil
    for i = 1, #WARBAND_BAGS do
        local warbandBagID = WARBAND_BAGS[i]
        if bagID == warbandBagID then
            tabIndex = i
            break
        end
    end
    
    if not tabIndex then
        return  -- Not a warband bag
    end
    
    -- Get current warband data from DB
    local warbandData = self:GetWarbandBankData()
    local allItems = warbandData.items or {}
    
    local newBagItems = ScanBag(bagID)
    
    for i = 1, #newBagItems do
        newBagItems[i].tabIndex = tabIndex
    end
    ReplaceBagInItemArray(allItems, bagID, newBagItems)
    
    -- Save to DB (compressed, warband bank is account-wide)
    self:SaveWarbandBankCompressed(allItems)
end

---FULL SCAN: Scan all inventory bags (used on login or manual refresh)
function WarbandNexus:ScanInventoryBags(charKey)
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return {}
    end
    
    if not charKey then
        charKey = ResolveCurrentItemStorageKey()
    end
    
    local allItems = {}
    local totalSlots = 0
    
    -- Scan ALL inventory bags
    for ii = 1, #INVENTORY_BAGS do
        local bagID = INVENTORY_BAGS[ii]
        totalSlots = totalSlots + (C_Container.GetContainerNumSlots(bagID) or 0)
        local bagItems = ScanBag(bagID)
        for i = 1, #bagItems do
            allItems[#allItems + 1] = bagItems[i]
        end
    end
    
    -- Save to DB (compressed)
    itemSummaryIndex.pending[charKey] = true
    self:SaveItemsCompressed(charKey, "bags", allItems)
    SeedInventoryBagHashes()
    
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
function WarbandNexus:ScanBankBags(charKey)
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return {}
    end
    
    if not charKey then
        charKey = ResolveCurrentItemStorageKey()
    end
    
    local allItems = {}
    
    -- Scan ALL bank bags (NO FLAG CHECK - just scan)
    for ii = 1, #BANK_BAGS do
        local bagID = BANK_BAGS[ii]
        local bagItems = ScanBag(bagID)
        for i = 1, #bagItems do
            allItems[#allItems + 1] = bagItems[i]
        end
    end
    
    -- Save to DB (compressed)
    itemSummaryIndex.pending[charKey] = true
    self:SaveItemsCompressed(charKey, "bank", allItems)
    
    return allItems
end

---Scan warband bank
function WarbandNexus:ScanWarbandBank()
    -- GUARD: Only scan if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return {}
    end
    
    local allItems = {}
    
    -- Scan ALL warband bank tabs (NO FLAG CHECK - just scan)
    for ii = 1, #WARBAND_BAGS do
        local bagID = WARBAND_BAGS[ii]
        local bagItems = ScanBag(bagID)
        for i = 1, #bagItems do
            local item = bagItems[i]
            -- Add tab index for warband bank (1-5)
            item.tabIndex = ii
            allItems[#allItems + 1] = item
        end
    end
    
    -- Save to global (compressed, warband bank is account-wide)
    self:SaveWarbandBankCompressed(allItems)
    
    return allItems
end

-- THROTTLED UPDATE SYSTEM

---One deferred flush for all throttled bags (avoids N timers + N WN_ITEMS_UPDATED after rapid same-bag spam).
ScheduleDeferredBagFlush = function(delaySec)
    delaySec = delaySec or UPDATE_THROTTLE
    if delaySec < 0.01 then delaySec = 0.01 end
    if deferredThrottleTimer then return end
    deferredThrottleTimer = C_Timer.After(delaySec, function()
        deferredThrottleTimer = nil
        local ok, err = pcall(function()
            if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
                return
            end
            local anyProcessed = false
            local bagIDs = {}
            for bagID, _ in pairs(pendingUpdates) do
                bagIDs[#bagIDs + 1] = bagID
            end
            for i = 1, #bagIDs do
                if ThrottledBagUpdate(bagIDs[i]) then
                    anyProcessed = true
                end
            end
            if anyProcessed then
                local msgKey = CanonicalItemsMessageKey(ResolveCurrentItemStorageKey())
                WarbandNexus:SendMessage(Constants.EVENTS.ITEMS_UPDATED, { type = "batch", charKey = msgKey })
            end
        end)
        if not ok and WarbandNexus and WarbandNexus.LogError then
            WarbandNexus:LogError(tostring(err), "ItemsCacheScheduleDeferredBagFlush")
        end
    end)
end

---Throttled bag update (prevents BAG_UPDATE spam)
---Returns true if the update was processed (or scheduled), false if suppressed.
ThrottledBagUpdate = function(bagID)
    -- Suppress during bank open deferred scans (OnBankOpened handles it)
    if bankScanInProgress then
        return false
    end
    
    local currentTime = GetTime()
    local lastUpdate = lastUpdateTime[bagID] or 0
    
    if currentTime - lastUpdate < UPDATE_THROTTLE then
        pendingUpdates[bagID] = true
        local BP = ns.ItemsCacheBagPerf
        if BP and BP.NoteThrottled then BP.NoteThrottled(bagID, "defer") end
        ScheduleDeferredBagFlush(UPDATE_THROTTLE - (currentTime - lastUpdate))
        return false
    end
    
    lastUpdateTime[bagID] = currentTime
    pendingUpdates[bagID] = nil
    
    -- Determine bag type via O(1) lookup and scan INCREMENTALLY (only changed bag)
    local charKey = ResolveCurrentItemStorageKey()
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
        local msgKey = CanonicalItemsMessageKey(ResolveCurrentItemStorageKey())
        self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "batch", charKey = msgKey})
    end
end

---Flush pending bag scans on PLAYER_LOGOUT (bypass throttle; no messages).
function WarbandNexus:FlushItemsCacheOnLogout()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    if deferredThrottleTimer and deferredThrottleTimer.Cancel then
        deferredThrottleTimer:Cancel()
        deferredThrottleTimer = nil
    end
    if sessionActivityPersistTimer and sessionActivityPersistTimer.Cancel then
        sessionActivityPersistTimer:Cancel()
        sessionActivityPersistTimer = nil
    end
    BumpGearStorageScanGenerationImmediate()
    self:ProcessPendingBagUpdates()
    local bagIDs = {}
    for bagID, _ in pairs(pendingUpdates) do
        bagIDs[#bagIDs + 1] = bagID
    end
    for i = 1, #bagIDs do
        local bagID = bagIDs[i]
        pendingUpdates[bagID] = nil
        lastUpdateTime[bagID] = 0
        ThrottledBagUpdate(bagID)
    end
    wipe(pendingUpdates)
    FlushPendingCompressWrites(true)
end

---Flush session-dirty buckets on PLAYER_LEAVING_WORLD (/reload, zone exit, logout).
function WarbandNexus:FlushItemsCacheOnLeavingWorld()
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    if sessionActivityPersistTimer and sessionActivityPersistTimer.Cancel then
        sessionActivityPersistTimer:Cancel()
        sessionActivityPersistTimer = nil
    end
    BumpGearStorageScanGenerationImmediate()
    FlushPendingCompressWrites(true)
end

-- EVENT HANDLERS (Will be registered by EventManager)

---Handle BAG_UPDATE event (from RegisterBucketEvent)
---Batches all bag updates and sends ONE coalesced ITEMS_UPDATED message
function WarbandNexus:OnBagUpdate(bagIDs)
    local P = ns.Profiler
    local traceT0 = (P and P.enabled and P.eventTrace) and debugprofilestop() or nil
    DebugVerbosePrint("|cff9370DB[WN ItemsCache]|r [Items Event] BAG_UPDATE (bucket) triggered")
    -- GUARD: Only process bag updates if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end

    if ns._pveVaultHandlerActive then
        ns._pendingBagUpdateAfterVault = bagIDs
        return
    end
    
    -- RegisterBucketEvent passes a table of bagIDs
    if not bagIDs or type(bagIDs) ~= "table" then
        return
    end
    
    -- Process each bag that was updated, track if any actually changed
    local changedBags = {}
    for bagID in pairs(bagIDs) do
        if HasBagChanged(bagID) then
            changedBags[#changedBags + 1] = bagID
        end
    end
    local changedCount = #changedBags
    if changedCount == 0 then return end

    local function traceBagUpdateDone(processed)
        if traceT0 and P and P.AppendTraceRow then
            local elapsed = debugprofilestop() - traceT0
            P:AppendTraceRow(
                "Bag",
                "OnBagUpdate",
                "bags=" .. tostring(changedCount) .. " ok=" .. (processed and "yes" or "no"),
                elapsed,
                elapsed >= (P.TRACE_ANOMALY_MS or 16.67) and "anomaly" or "bag"
            )
        elseif traceT0 and P and P.TraceInternalHandler then
            P:TraceInternalHandler(
                "ItemsOnBagUpdate",
                traceT0,
                "bags=" .. tostring(changedCount) .. " processed=" .. (processed and "yes" or "no")
            )
        end
    end

    local BP = ns.ItemsCacheBagPerf
    if BP and BP.NoteBucketEvent then
        BP.NoteBucketEvent(changedCount)
    end

    local anyProcessed = false
    local bagIdx = 1
    local processNextBag -- forward declare (runBagBatch was above this local — Lua 5.1 nil call)
    processNextBag = function()
        if bagIdx > changedCount then
            if anyProcessed then
                local msgKey = CanonicalItemsMessageKey(ResolveCurrentItemStorageKey())
                self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, { type = "batch", charKey = msgKey })
            end
            traceBagUpdateDone(anyProcessed)
            return
        end
        local bagID = changedBags[bagIdx]
        bagIdx = bagIdx + 1
        if ThrottledBagUpdate(bagID) then
            anyProcessed = true
        end
        if bagIdx <= changedCount then
            C_Timer.After(0, processNextBag)
        elseif anyProcessed then
            local msgKey = CanonicalItemsMessageKey(ResolveCurrentItemStorageKey())
            self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, { type = "batch", charKey = msgKey })
            traceBagUpdateDone(true)
        else
            traceBagUpdateDone(false)
        end
    end
    if P and P.enabled and P.RunSlice then
        P:RunSlice(P.CAT.SVC, "Items_OnBagUpdate_batch", processNextBag)
    else
        processNextBag()
    end
end

---Chunked bank-area scan: one bag (container) per frame to cap frame cost (inventory → bank → warband).
---Each bag/tab commits immediately (UpdateSingleBag / UpdateSingleWarbandBag) — guild-bank tab parity.
function WarbandNexus:RunBudgetedBankOpenScan(charKey)
    if not charKey then
        charKey = ResolveCurrentItemStorageKey()
    end

    bankOpenScanGeneration = bankOpenScanGeneration + 1
    local myGen = bankOpenScanGeneration

    local invIdx = 1
    local bankIdx = 1
    local wbIdx = 1

    local function scanStillActive()
        return myGen == bankOpenScanGeneration and isBankOpen
    end

    local function finishBankScan(aborted)
        bankScanInProgress = false
        if aborted and self.InvalidateLiveOpenWarbandBankSummary then
            self:InvalidateLiveOpenWarbandBankSummary()
        end
    end

    local runInv
    local runBank
    local runWarband

    runWarband = function()
        if not scanStillActive() then
            finishBankScan(true)
            return
        end
        if wbIdx > #WARBAND_BAGS then
            finishBankScan(false)
            self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, { type = "all", charKey = CanonicalItemsMessageKey(charKey) })
            return
        end
        self:UpdateSingleWarbandBag(WARBAND_BAGS[wbIdx])
        wbIdx = wbIdx + 1
        C_Timer.After(0, runWarband)
    end

    runBank = function()
        if not scanStillActive() then
            finishBankScan(true)
            return
        end
        if bankIdx > #BANK_BAGS then
            C_Timer.After(0, runWarband)
            return
        end
        self:UpdateSingleBag(charKey, BANK_BAGS[bankIdx])
        bankIdx = bankIdx + 1
        C_Timer.After(0, runBank)
    end

    runInv = function()
        if not scanStillActive() then
            finishBankScan(true)
            return
        end
        if invIdx > #INVENTORY_BAGS then
            if self.db and self.db.char then
                local data = self:GetItemsData(charKey)
                local bagItems = data and data.bags or {}
                local totalSlots = 0
                for i = 1, #INVENTORY_BAGS do
                    totalSlots = totalSlots + (C_Container.GetContainerNumSlots(INVENTORY_BAGS[i]) or 0)
                end
                if not self.db.char.bags then self.db.char.bags = {} end
                self.db.char.bags.usedSlots = #bagItems
                self.db.char.bags.totalSlots = totalSlots
                self.db.char.bags.lastScan = time()
            end
            C_Timer.After(0, runBank)
            return
        end
        self:UpdateSingleBag(charKey, INVENTORY_BAGS[invIdx])
        invIdx = invIdx + 1
        C_Timer.After(0, runInv)
    end

    runInv()
end

---Handle BANKFRAME_OPENED event
function WarbandNexus:OnBankOpened()
    DebugVerbosePrint("|cff9370DB[WN ItemsCache]|r [Bank Event] BANKFRAME_OPENED triggered")
    
    -- Set global flag for Gold Manager
    WarbandNexus.bankIsOpen = true
    
    -- GOLD MANAGER: Trigger gold management
    if self.TriggerGoldManagement then
        C_Timer.After(0.1, function()
            self:TriggerGoldManagement()
        end)
    end
    
    -- GUARD: Only process if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    isBankOpen = true
    isWarbandBankOpen = true
    bankScanInProgress = true  -- Suppress ThrottledBagUpdate while we do the full scan
    
    local charKey = ResolveCurrentItemStorageKey()
    
    -- One container per frame (replaces nested 0 + 0.05s timers; avoids large synchronous spikes)
    C_Timer.After(0, function()
        self:RunBudgetedBankOpenScan(charKey)
    end)
end

---Handle BANKFRAME_CLOSED event
function WarbandNexus:OnBankClosed()
    bankOpenScanGeneration = bankOpenScanGeneration + 1
    warbandBankScanGeneration = warbandBankScanGeneration + 1
    isBankOpen = false
    isWarbandBankOpen = false  -- Both tabs close together
    bankScanInProgress = false  -- Safety: ensure flag is cleared
    WarbandNexus.bankIsOpen = false  -- Clear global flag for Gold Manager
    if self.InvalidateLiveOpenWarbandBankSummary then
        self:InvalidateLiveOpenWarbandBankSummary()
    end
    DebugVerbosePrint("|cff9370DB[WN ItemsCache]|r [Bank Event] BANKFRAME_CLOSED")
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

-- COMPRESSED STORAGE (SAVE/LOAD)

local function ClearSessionDirtyKey(saveKey)
    sessionDirtyBuckets[saveKey] = nil
    pendingCompressSaves[saveKey] = nil
end

---Fast path: write uncompressed bucket to AceDB (no LibDeflate). Survives Alt+F4 if WoW flushes SV.
local function WriteSessionBucketUncompressed(charKey, dataType, items)
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    if not charKey or not dataType or not items then return end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
        return
    end
    if not WarbandNexus.db.global.itemStorage then
        WarbandNexus.db.global.itemStorage = {}
    end
    if not WarbandNexus.db.global.itemStorage[charKey] then
        WarbandNexus.db.global.itemStorage[charKey] = {}
    end
    local newSig = ComputeBucketContentSig(items)
    local existing = WarbandNexus.db.global.itemStorage[charKey][dataType]
    if existing and existing.contentSig == newSig and existing.compressed == false then
        return
    end
    local slotCount = #items
    local stackTotal = 0
    for si = 1, slotCount do
        stackTotal = stackTotal + (items[si].stackCount or 1)
    end
    local now = time()
    WarbandNexus.db.global.itemStorage[charKey][dataType] = {
        compressed = false,
        data = items,
        lastUpdate = now,
        slotCount = slotCount,
        stackTotal = stackTotal,
        contentSig = newSig,
    }
    TouchDecompressedItemCache(charKey, dataType, items, now)
end

PersistSessionDirtyFast = function()
    if InCombatLockdown and InCombatLockdown() then
        ScheduleSessionActivityPersist()
        return
    end
    if next(sessionDirtyBuckets) == nil then return end
    local queue = {}
    for saveKey in pairs(sessionDirtyBuckets) do
        local entry = pendingCompressSaves[saveKey]
        if entry then
            queue[#queue + 1] = { saveKey = saveKey, entry = entry }
        end
    end
    if #queue == 0 then return end
    local idx = 1
    local persistT0 = debugprofilestop()
    local persisted = 0
    local function persistNext()
        local budgetStart = debugprofilestop()
        while idx <= #queue do
            local row = queue[idx]
            idx = idx + 1
            local entry = row.entry
            WriteSessionBucketUncompressed(entry.charKey, entry.dataType, entry.items)
            persisted = persisted + 1
            if idx <= #queue and (debugprofilestop() - budgetStart) >= COMPRESS_FLUSH_BUDGET_MS then
                C_Timer.After(0, persistNext)
                return
            end
        end
        local BP = ns.ItemsCacheBagPerf
        if BP and BP.NoteFastPersist and persisted > 0 then
            BP.NoteFastPersist(debugprofilestop() - persistT0, persisted)
        end
    end
    persistNext()
end

ScheduleSessionActivityPersist = function()
    if sessionActivityPersistTimer and sessionActivityPersistTimer.Cancel then
        sessionActivityPersistTimer:Cancel()
    end
    sessionActivityPersistTimer = C_Timer.NewTimer(SESSION_ACTIVITY_PERSIST_SEC, function()
        sessionActivityPersistTimer = nil
        PersistSessionDirtyFast()
    end)
end

local function StartSessionIdleFlushTicker()
    if sessionIdleFlushTicker then return end
    sessionIdleFlushTicker = C_Timer.NewTicker(SESSION_IDLE_FLUSH_SEC, function()
        if InCombatLockdown and InCombatLockdown() then return end
        if next(sessionDirtyBuckets) == nil then return end
        PersistSessionDirtyFast()
    end)
end

FlushPendingCompressWrites = function(syncAll)
    local function finishEntry(saveKey, charKey, dataType, items)
        if WarbandNexus.SaveItemsCompressedImmediate then
            WarbandNexus:SaveItemsCompressedImmediate(charKey, dataType, items)
        end
        ClearSessionDirtyKey(saveKey)
    end
    if syncAll then
        local t0 = debugprofilestop()
        local count = 0
        for saveKey, entry in pairs(pendingCompressSaves) do
            finishEntry(saveKey, entry.charKey, entry.dataType, entry.items)
            count = count + 1
        end
        wipe(sessionDirtyBuckets)
        local BP = ns.ItemsCacheBagPerf
        if BP and BP.NoteCompressFlush and count > 0 then
            BP.NoteCompressFlush(debugprofilestop() - t0, count, true)
        end
        return
    end
    local queue = {}
    for saveKey, entry in pairs(pendingCompressSaves) do
        queue[#queue + 1] = { saveKey = saveKey, entry = entry }
    end
    if #queue == 0 then return end
    local idx = 1
    local flushT0 = debugprofilestop()
    local flushed = 0
    local function flushNext()
        local budgetStart = debugprofilestop()
        while idx <= #queue do
            local row = queue[idx]
            idx = idx + 1
            local entry = row.entry
            finishEntry(row.saveKey, entry.charKey, entry.dataType, entry.items)
            flushed = flushed + 1
            if idx <= #queue and (debugprofilestop() - budgetStart) >= COMPRESS_FLUSH_BUDGET_MS then
                C_Timer.After(0, flushNext)
                return
            end
        end
        local BP = ns.ItemsCacheBagPerf
        if BP and BP.NoteCompressFlush and flushed > 0 then
            BP.NoteCompressFlush(debugprofilestop() - flushT0, flushed, false)
        end
    end
    flushNext()
end

---Stress/dev only — production hot path never schedules timed compress coalesce.
local function ScheduleCompressCoalesce()
    C_Timer.After(0, function()
        FlushPendingCompressWrites(false)
    end)
end

---Persist items to DB immediately (LibSerialize + Deflate). Internal — use SaveItemsCompressed during play; flush on logout/leaving-world/idle.
function WarbandNexus:SaveItemsCompressedImmediate(charKey, dataType, items)
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

    local newSig = ComputeBucketContentSig(items)
    local saveKey = CompressSaveKey(charKey, dataType)
    local existing = self.db.global.itemStorage[charKey][dataType]
    if existing and existing.contentSig and existing.contentSig == newSig then
        TouchDecompressedItemCache(charKey, dataType, items, existing.lastUpdate or time())
        TouchDecompressedSessionGen(charKey, dataType)
        ClearSessionDirtyKey(saveKey)
        return
    end
    
    -- Compress data
    local BP = ns.ItemsCacheBagPerf
    local perfCtx = BP and BP._activeCtx
    local compressed = CompressItemData(items)
    if perfCtx and BP and BP.MarkPhase then
        BP.MarkPhase(perfCtx, "compress")
    end
    local slotCount = #items
    local stackTotal = 0
    for si = 1, slotCount do
        stackTotal = stackTotal + (items[si].stackCount or 1)
    end
    local now = time()
    if not compressed then
        -- Fallback: store uncompressed
        self.db.global.itemStorage[charKey][dataType] = {
            compressed = false,
            data = items,
            lastUpdate = now,
            slotCount = slotCount,
            stackTotal = stackTotal,
            contentSig = ComputeBucketContentSig(items),
        }
        TouchDecompressedItemCache(charKey, dataType, items, now)
        TouchDecompressedSessionGen(charKey, dataType)
        BumpGearStorageScanGeneration()
        return
    end
    
    -- Store compressed
    self.db.global.itemStorage[charKey][dataType] = {
        compressed = true,
        data = compressed,
        lastUpdate = now,
        slotCount = slotCount,
        stackTotal = stackTotal,
        contentSig = ComputeBucketContentSig(items),
    }
    
    TouchDecompressedItemCache(charKey, dataType, items, now)
    TouchDecompressedSessionGen(charKey, dataType)
    -- Summary invalidation: callers set pending (full scan) or ApplyBagDeltaToSummary (incremental).
    BumpGearStorageScanGeneration()
end

---Mark session bucket dirty and sync RAM. Fast uncompressed persist ~15s after last change; LibDeflate on logout/reload.
function WarbandNexus:SaveItemsCompressed(charKey, dataType, items)
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    if not charKey or not dataType or not items then return end

    local saveKey = CompressSaveKey(charKey, dataType)
    local bucket = ResolveItemStorageRow(charKey)
    bucket = bucket and bucket[dataType]

    sessionDirtyBuckets[saveKey] = true
    pendingCompressSaves[saveKey] = {
        charKey = charKey,
        dataType = dataType,
        items = items,
    }
    TouchDecompressedItemCache(charKey, dataType, items, (bucket and bucket.lastUpdate) or time())
    ScheduleSessionActivityPersist()
    local BP = ns.ItemsCacheBagPerf
    if BP and BP.NoteSessionDirty then
        BP.NoteSessionDirty(charKey, dataType)
    end
end

---Save warband bank data (compressed)
function WarbandNexus:SaveWarbandBankCompressed(items)
    if not items then return end
    
    -- Initialize structure
    if not self.db.global.itemStorage then
        self.db.global.itemStorage = {}
    end
    
    -- Compress data
    local compressed = CompressItemData(items)
    local slotCount = #items
    local stackTotal = 0
    for si = 1, slotCount do
        stackTotal = stackTotal + (items[si].stackCount or 1)
    end
    local now = time()
    if not compressed then
        -- Fallback: store uncompressed
        self.db.global.itemStorage.warbandBank = {
            compressed = false,
            data = items,
            lastUpdate = now,
            slotCount = slotCount,
            stackTotal = stackTotal,
        }
        decompressedWarbandCache = { items = items, lastUpdate = now }
        itemSummaryIndex.warbandPending = true
        warbandBankScanGeneration = warbandBankScanGeneration + 1
        BumpGearStorageScanGeneration()
        return
    end
    
    -- Store compressed
    self.db.global.itemStorage.warbandBank = {
        compressed = true,
        data = compressed,
        lastUpdate = now,
        slotCount = slotCount,
        stackTotal = stackTotal,
    }
    
    decompressedWarbandCache = { items = items, lastUpdate = now }
    itemSummaryIndex.warbandPending = true
    warbandBankScanGeneration = warbandBankScanGeneration + 1
    BumpGearStorageScanGeneration()
end

-- MERGE: v2 itemStorage + legacy character inventory + personalBanks
-- `itemStorage[charKey] = {}` (empty) or v2-only must still see legacy table rows;
-- `characters[charKey]` and canonical key may differ.

local function ItemMergeDedupeKey(item)
    if not item or not item.itemID then return nil end
    local link = item.itemLink or item.link
    if link and type(link) == "string" and link ~= "" then
        if issecretvalue and issecretvalue(link) then
            return "I:" .. tostring(item.itemID)
        end
        return "L:" .. link
    end
    return "I:" .. tostring(item.itemID) .. ":" .. tostring(item.quality or 0)
end

local function AddSeenFromItemList(list, seen)
    if not list or not seen then return end
    for i = 1, #list do
        local it = list[i]
        if it and it.itemID then
            local k = ItemMergeDedupeKey(it)
            if k then seen[k] = true end
        end
    end
end

local function AppendItemsDeduped(target, source, seen)
    if not target or not source or not seen then return end
    for i = 1, #source do
        local it = source[i]
        if it and it.itemID then
            local k = ItemMergeDedupeKey(it)
            if k and not seen[k] then
                seen[k] = true
                target[#target + 1] = it
            end
        end
    end
end

local function PersonalBankToItemArray(pb)
    if not pb then return {} end
    local bankData = pb.compressed and (DecompressItemData(pb.data) or {}) or (pb.data or {})
    local bankArr = {}
    if type(bankData) == "table" and not bankData[1] then
        for bagID, bagData in pairs(bankData) do
            if type(bagData) == "table" then
                for slotID, item in pairs(bagData) do
                    if type(item) == "table" and item.itemID then
                        bankArr[#bankArr + 1] = {
                            bagID = item.actualBagID or bagID,
                            slot = slotID,
                            slotIndex = slotID,
                            itemID = item.itemID,
                            itemLink = item.itemLink,
                            stackCount = item.stackCount or 1,
                            quality = item.quality,
                            isBound = item.isBound or false,
                        }
                    end
                end
            end
        end
    end
    return bankArr
end

local function MergeExtraItemSourcesIntoItemsData(self, result, charKey)
    if not result or not charKey or charKey == "" then return end
    result.bags = result.bags or {}
    result.bank = result.bank or {}
    local global = self.db and self.db.global
    if not global then return end

    local seen = {}
    AddSeenFromItemList(result.bags, seen)
    AddSeenFromItemList(result.bank, seen)

    local keys = {}
    local function addKey(k)
        if not k or k == "" then return end
        for i = 1, #keys do
            if keys[i] == k then return end
        end
        keys[#keys + 1] = k
    end
    addKey(charKey)
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        addKey(ns.Utilities:GetCanonicalCharacterKey(charKey))
    end

    for i = 1, #keys do
        local k = keys[i]
        local ch = global.characters and global.characters[k]
        if ch then
            if ch.items and #ch.items > 0 then
                AppendItemsDeduped(result.bags, HydrateItems(ch.items), seen)
            end
            if ch.bank and #ch.bank > 0 then
                AppendItemsDeduped(result.bank, HydrateItems(ch.bank), seen)
            end
        end
        local pb = global.personalBanks and global.personalBanks[k]
        if pb then
            local arr = PersonalBankToItemArray(pb)
            if #arr > 0 then
                AppendItemsDeduped(result.bank, HydrateItems(arr), seen)
            end
        end
    end
    HydrateItems(result.bags)
    HydrateItems(result.bank)
end

-- PUBLIC API (FOR UI AND DATASERVICE)

--- One-time slotCount backfill for legacy compressed buckets (persists in AceDB on next save).
local function LazyBackfillSlotCountFromCompressed(bucket)
    if not bucket or bucket.slotCount or not bucket.compressed or not bucket.data then
        return nil, nil
    end
    local items = DecompressItemData(bucket.data)
    if not items then
        return nil, nil
    end
    local slotCount = #items
    local stackTotal = 0
    for i = 1, slotCount do
        stackTotal = stackTotal + (items[i].stackCount or 1)
    end
    bucket.slotCount = slotCount
    bucket.stackTotal = stackTotal
    return slotCount, stackTotal
end

--- Occupied slots + stack totals from a persisted itemStorage bucket without decompress.
local function OccupiedSlotsFromStorageBucket(bucket, allowLazyBackfill)
    if not bucket then
        return nil, nil, nil
    end
    local lastUpdate = bucket.lastUpdate or 0
    if bucket.slotCount then
        return bucket.slotCount, bucket.stackTotal or bucket.slotCount, lastUpdate
    end
    if bucket.compressed == false and type(bucket.data) == "table" then
        local slots = #bucket.data
        local stacks = 0
        for i = 1, slots do
            local item = bucket.data[i]
            stacks = stacks + (item and item.stackCount or 1)
        end
        return slots, stacks, lastUpdate
    end
    if bucket.compressed and allowLazyBackfill ~= false then
        local slots, stacks = LazyBackfillSlotCountFromCompressed(bucket)
        if slots then
            return slots, stacks, lastUpdate
        end
    end
    return nil, nil, lastUpdate
end

--- Resolve v2 itemStorage row for a character key (GUID / Name-Realm aliases).
--- (Local is forward-declared near the top of the file.)
function ResolveItemStorageRow(charKey)
    local globalIS = WarbandNexus.db.global.itemStorage
    if not globalIS or not charKey or charKey == "" then
        return nil
    end
    local storage = globalIS[charKey]
    local function storageHasPayload(ent)
        return ent and (ent.bags or ent.bank)
    end
    if not storageHasPayload(storage) and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local alt = ns.Utilities:GetCanonicalCharacterKey(charKey)
        if alt and alt ~= charKey then
            local s2 = globalIS[alt]
            if storageHasPayload(s2) then
                storage = s2
            end
        end
    end
    if not storageHasPayload(storage) and not (ns.Utilities and ns.Utilities.IsGuidOnlySubsidiaryReads and ns.Utilities:IsGuidOnlySubsidiaryReads(WarbandNexus and WarbandNexus.db)) then
        local charData = WarbandNexus.db.global.characters and WarbandNexus.db.global.characters[charKey]
        local U = ns.Utilities
        if charData and U and U.GetCharacterKey then
            local legacyKey = U:GetCharacterKey(charData.name, charData.realm)
            if legacyKey and legacyKey ~= charKey then
                local sLegacy = globalIS[legacyKey]
                if storageHasPayload(sLegacy) then
                    storage = sLegacy
                end
            end
        end
    end
    return storage
end

--- Fast occupied-slot tally for one character bucket (bags/bank) — no decompress.
function WarbandNexus:GetItemStorageOccupiedSlotTally(charKey, dataType, allowLazyBackfill)
    local storage = ResolveItemStorageRow(charKey)
    local bucket = storage and storage[dataType]
    local slots, stacks, lastUpdate = OccupiedSlotsFromStorageBucket(bucket, allowLazyBackfill)
    if slots then
        return slots, stacks or slots, lastUpdate or 0
    end
    if bucket and (lastUpdate or bucket.lastUpdate or 0) > 0 then
        return 0, 0, lastUpdate or bucket.lastUpdate or 0
    end

    local cached = decompressedItemCache[charKey]
    if cached then
        local arr = dataType == "bags" and cached.bags or cached.bank
        if arr then
            local n = #arr
            local st = 0
            for i = 1, n do
                st = st + (arr[i].stackCount or 1)
            end
            local lu = dataType == "bags" and (cached.bagsLastUpdate or 0) or (cached.bankLastUpdate or 0)
            return n, st, lu
        end
    end

    if dataType == "bags" then
        local charData = self.db.global.characters and self.db.global.characters[charKey]
        if charData and charData.items then
            local n = #charData.items
            return n, n, charData.itemsLastUpdate or 0
        end
    elseif dataType == "bank" then
        local charData = self.db.global.characters and self.db.global.characters[charKey]
        if charData and charData.bank then
            local n = #charData.bank
            return n, n, charData.bankLastUpdate or 0
        end
        local pb = self.db.global.personalBanks and self.db.global.personalBanks[charKey]
        if pb then
            local n = pb.items and #pb.items or 0
            return n, n, pb.lastUpdate or 0
        end
    end

    return 0, 0, 0
end

--- Fast warband bank occupied slots — no decompress when slotCount metadata exists.
function WarbandNexus:GetWarbandBankOccupiedSlotTally(allowLazyBackfill)
    if decompressedWarbandCache and decompressedWarbandCache.items then
        local items = decompressedWarbandCache.items
        local n = #items
        local st = 0
        for i = 1, n do
            st = st + (items[i].stackCount or 1)
        end
        return n, st, decompressedWarbandCache.lastUpdate or 0
    end

    local storage = self.db.global.itemStorage and self.db.global.itemStorage.warbandBank
    local slots, stacks, lastUpdate = OccupiedSlotsFromStorageBucket(storage, allowLazyBackfill)
    if slots then
        return slots, stacks or slots, lastUpdate or 0
    end
    if storage and (lastUpdate or storage.lastUpdate or 0) > 0 then
        return 0, 0, lastUpdate or storage.lastUpdate or 0
    end

    if self.db.global.warbandBank and type(self.db.global.warbandBank.items) == "table" then
        local legacy = self.db.global.warbandBank.items
        local n = #legacy
        if n > 0 then
            return n, n, self.db.global.warbandBank.lastUpdate or 0
        end
    end

    return 0, 0, 0
end

--- Sum tracked roster personal storage using fast slot tallies (Items > Warband stats + tree scan).
function WarbandNexus:SumTrackedPersonalStorageSlotTally(allowLazyBackfill)
    local stackTotal, usedSlots, lastScan = 0, 0, 0
    local allCharacters = self.GetAllCharacters and self:GetAllCharacters() or {}
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        if char and char.isTracked ~= false and char._key then
            local bagSlots, bagStacks, bagLast = self:GetItemStorageOccupiedSlotTally(char._key, "bags", allowLazyBackfill)
            local bankSlots, bankStacks, bankLast = self:GetItemStorageOccupiedSlotTally(char._key, "bank", allowLazyBackfill)
            usedSlots = usedSlots + bagSlots + bankSlots
            stackTotal = stackTotal + bagStacks + bankStacks
            lastScan = math.max(lastScan, bagLast, bankLast)
        end
    end
    return stackTotal, usedSlots, lastScan
end

local function ItemStorageKeysMatch(a, b)
    if not a or not b then return false end
    if a == b then return true end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local ca = ns.Utilities:GetCanonicalCharacterKey(a) or a
        local cb = ns.Utilities:GetCanonicalCharacterKey(b) or b
        return ca == cb
    end
    return false
end

--- Account-wide personal bag+bank capacity for overview panels.
--- Logged-in character uses live C_Container totals; alts use cached occupied slots as a floor.
function WarbandNexus:SumTrackedPersonalStorageCapacity()
    local INVENTORY_BAGS = ns.INVENTORY_BAGS or { 0, 1, 2, 3, 4, 5 }
    local BANK_BAGS = ns.PERSONAL_BANK_BAGS or { -1, 6, 7, 8, 9, 10, 11 }
    local currentKey = ResolveCurrentItemStorageKey()
    local totalSlots = 0
    local allCharacters = self.GetAllCharacters and self:GetAllCharacters() or {}
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        if char and char.isTracked ~= false and char._key then
            local charKey = char._key
            if ItemStorageKeysMatch(charKey, currentKey) then
                local charTotal = 0
                for bi = 1, #INVENTORY_BAGS do
                    charTotal = charTotal + (C_Container.GetContainerNumSlots(INVENTORY_BAGS[bi]) or 0)
                end
                for bi = 1, #BANK_BAGS do
                    charTotal = charTotal + (C_Container.GetContainerNumSlots(BANK_BAGS[bi]) or 0)
                end
                if charTotal <= 0 then
                    local bagSlots = self:GetItemStorageOccupiedSlotTally(charKey, "bags", false)
                    local bankSlots = self:GetItemStorageOccupiedSlotTally(charKey, "bank", false)
                    charTotal = (bagSlots or 0) + (bankSlots or 0)
                end
                totalSlots = totalSlots + charTotal
            else
                local bagSlots = self:GetItemStorageOccupiedSlotTally(charKey, "bags", false)
                local bankSlots = self:GetItemStorageOccupiedSlotTally(charKey, "bank", false)
                totalSlots = totalSlots + (bagSlots or 0) + (bankSlots or 0)
            end
        end
    end
    return totalSlots
end

---Get items data for a specific character (decompressed + hydrated with metadata).
---Uses session RAM cache to avoid repeated decompression. Invalidated when items are scanned.
function WarbandNexus:GetItemsData(charKey)
    -- Check session cache first (avoids repeated decompress+deserialize)
    local cached = decompressedItemCache[charKey]
    if cached then return cached end
    
    local result = { bags = {}, bank = {}, bagsLastUpdate = 0, bankLastUpdate = 0 }
    -- v2 itemStorage is keyed by ResolveCurrentItemStorageKey (GUID when available); UI may pass Name-Realm.
    local globalIS = self.db.global.itemStorage
    local storage = nil
    if globalIS and charKey and charKey ~= "" then
        storage = globalIS[charKey]
        local function storageHasPayload(ent)
            return ent and (ent.bags or ent.bank)
        end
        if not storageHasPayload(storage) and ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            local alt = ns.Utilities:GetCanonicalCharacterKey(charKey)
            if alt and alt ~= charKey then
                local s2 = globalIS[alt]
                if storageHasPayload(s2) then
                    storage = s2
                end
            end
        end
        -- Pre-migration only: itemStorage may still be under legacy Name-Realm.
        if not storageHasPayload(storage) and not (ns.Utilities and ns.Utilities.IsGuidOnlySubsidiaryReads and ns.Utilities:IsGuidOnlySubsidiaryReads(self.db)) then
            local charData = self.db.global.characters and self.db.global.characters[charKey]
            local U = ns.Utilities
            if charData and U and U.GetCharacterKey then
                local legacyKey = U:GetCharacterKey(charData.name, charData.realm)
                if legacyKey and legacyKey ~= charKey then
                    local sLegacy = globalIS[legacyKey]
                    if storageHasPayload(sLegacy) then
                        storage = sLegacy
                    end
                end
            end
        end
    end
    local hasV2Data = storage and (storage.bags or storage.bank)

    if not hasV2Data then
        if self.db.global.characters and self.db.global.characters[charKey] then
            local charData = self.db.global.characters[charKey]
            result = {
                bags = HydrateItems(charData.items or {}),
                bank = HydrateItems(charData.bank or {}),
                bagsLastUpdate = charData.itemsLastUpdate or 0,
                bankLastUpdate = charData.bankLastUpdate or 0,
            }
        elseif self.db.global.personalBanks and self.db.global.personalBanks[charKey] then
            local pb = self.db.global.personalBanks[charKey]
            local arr = PersonalBankToItemArray(pb)
            result = {
                bags = {},
                bank = HydrateItems(arr),
                bagsLastUpdate = 0,
                bankLastUpdate = pb.lastUpdate or 0,
            }
        end
    else
        if storage.bags then
            if storage.bags.compressed then
                result.bags = DecompressItemData(storage.bags.data) or {}
            else
                result.bags = storage.bags.data or {}
            end
            HydrateItems(result.bags)
            result.bagsLastUpdate = storage.bags.lastUpdate or 0
        end
        if storage.bank then
            if storage.bank.compressed then
                result.bank = DecompressItemData(storage.bank.data) or {}
            else
                result.bank = storage.bank.data or {}
            end
            HydrateItems(result.bank)
            result.bankLastUpdate = storage.bank.lastUpdate or 0
            local metaSlots = storage.bank.slotCount
            if metaSlots and metaSlots > 0 and #result.bank == 0 then
                local retry = storage.bank.compressed and DecompressItemData(storage.bank.data) or storage.bank.data
                if retry and #retry > 0 then
                    result.bank = HydrateItems(retry)
                end
            end
        end
    end

    MergeExtraItemSourcesIntoItemsData(self, result, charKey)
    decompressedItemCache[charKey] = result
    return result
end

---Get warband bank data (decompressed + hydrated with metadata).
---Uses session RAM cache. Invalidated when warband bank is scanned.
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

    -- If v2 bucket exists but is empty, keep showing legacy SavedVariables (no data loss during migrations).
    if (#result.items == 0) and self.db.global.warbandBank and type(self.db.global.warbandBank.items) == "table" then
        local legacy = self.db.global.warbandBank.items
        if #legacy > 0 then
            result.items = HydrateItems(legacy)
        end
        if (not result.lastUpdate or result.lastUpdate == 0) and self.db.global.warbandBank.lastUpdate then
            result.lastUpdate = self.db.global.warbandBank.lastUpdate
        end
    end
    
    -- Cache for session (invalidated when warband bank is re-scanned)
    decompressedWarbandCache = result
    return result
end

-- PRE-INDEXED ITEM COUNT SUMMARY
-- O(1) tooltip lookup instead of iterating all items on every hover.
-- Summary rebuilt lazily: marked "pending" on item change, processed on next access.

---Build item count summary for a single character (bags + bank).
---v2 bucket only — AcquireV2BucketItemArray reuses session RAM; no GetItemsData legacy merge/hydrate.
local function BuildCharacterSummary(charKey, force)
    if not force and SummaryIsCurrent(charKey) then
        return
    end
    local summary = {}  -- [itemID] = { bags=N, bank=N }
    local U = ns.Utilities

    local bags = select(1, AcquireV2BucketItemArray(charKey, "bags"))
    if bags then
        for i = 1, #bags do
            local item = bags[i]
            if item.itemID and not item.isKeystone
                and not (U and U.IsKeystoneItemID and U:IsKeystoneItemID(item.itemID)) then
                local entry = summary[item.itemID]
                if not entry then
                    entry = { bags = 0, bank = 0 }
                    summary[item.itemID] = entry
                end
                entry.bags = entry.bags + (item.stackCount or 1)
            end
        end
    end

    local bank = select(1, AcquireV2BucketItemArray(charKey, "bank"))
    if bank then
        for i = 1, #bank do
            local item = bank[i]
            if item.itemID and not item.isKeystone
                and not (U and U.IsKeystoneItemID and U:IsKeystoneItemID(item.itemID)) then
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
    itemSummaryIndex.pending[charKey] = nil
    local gen = BumpSummarySessionGen(charKey, "bags")
    BumpSummarySessionGen(charKey, "bank")
    local cached = decompressedItemCache[charKey]
    if cached and gen then
        cached.bagsSessionGen = gen.bags
        cached.bankSessionGen = gen.bank
    end
end

---Build item count summary for warband bank.
local function BuildWarbandSummary()
    local summary = {}  -- [itemID] = N
    
    local warbandData = WarbandNexus:GetWarbandBankData()
    if warbandData and warbandData.items then
        local U = ns.Utilities
        for i = 1, #warbandData.items do
            local item = warbandData.items[i]
            if item.itemID and not item.isKeystone
                and not (U and U.IsKeystoneItemID and U:IsKeystoneItemID(item.itemID)) then
                summary[item.itemID] = (summary[item.itemID] or 0) + (item.stackCount or 1)
            end
        end
    end
    
    itemSummaryIndex.warband = summary
    itemSummaryIndex.warbandPending = false
end

---Build item count summary for cached guild bank vaults (account-wide scan cache).
local function BuildGuildSummary()
    local summary = {} -- [guildName] = { [itemID] = N }
    local gb = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.guildBank
    if gb then
        local U = ns.Utilities
        for guildName, guildData in pairs(gb) do
            if guildName and not (issecretvalue and issecretvalue(guildName)) and type(guildData) == "table" then
                local guildSum = {}
                for _, tabData in pairs(guildData.tabs or {}) do
                    for _, itemData in pairs(tabData.items or {}) do
                        local id = itemData.itemID
                        if id and not itemData.isKeystone
                            and not (U and U.IsKeystoneItemID and U:IsKeystoneItemID(id)) then
                            guildSum[id] = (guildSum[id] or 0) + (itemData.stackCount or 1)
                        end
                    end
                end
                if next(guildSum) then
                    summary[guildName] = guildSum
                end
            end
        end
    end
    itemSummaryIndex.guild = summary
    itemSummaryIndex.guildPending = false
end

---Process any pending summary rebuilds (call before tooltip lookup).
---Lazy rebuild on demand, not on every bag event.
local function ProcessPendingSummariesBudgeted(budgetMs)
    local t0 = debugprofilestop()
    local budget = budgetMs or SUMMARY_BUILD_BUDGET_MS

    local liveKey = ResolveCurrentItemStorageKey()
    if liveKey and itemSummaryIndex.pending[liveKey] then
        BuildCharacterSummary(liveKey)
        itemSummaryIndex.pending[liveKey] = nil
    end

    if itemSummaryIndex.warbandPending then
        BuildWarbandSummary()
    end

    if itemSummaryIndex.guildPending then
        BuildGuildSummary()
    end

    for charKey in pairs(itemSummaryIndex.pending) do
        if debugprofilestop() - t0 >= budget then
            break
        end
        BuildCharacterSummary(charKey)
        itemSummaryIndex.pending[charKey] = nil
    end
end

local function SummaryDrainHasWork()
    if itemSummaryIndex.warbandPending then return true end
    if itemSummaryIndex.guildPending then return true end
    return next(itemSummaryIndex.pending) ~= nil
end

--- Midnight-safe GetItemCount for tooltip live session row.
local function SafeGetItemCount(itemID, includeBank)
    if not itemID then return 0 end
    local ok, count
    if includeBank then
        ok, count = pcall(GetItemCount, itemID, true)
    else
        ok, count = pcall(GetItemCount, itemID)
    end
    if not ok or count == nil then return 0 end
    if issecretvalue and issecretvalue(count) then return 0 end
    return tonumber(count) or 0
end

local function CharacterKeysMatchForTooltip(charKey, liveKey)
    if not charKey or not liveKey then return false end
    if charKey == liveKey then return true end
    local U = ns.Utilities
    local rowCanon = (U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(charKey)) or charKey
    local liveCanon = (U and U.GetCanonicalCharacterKey and U:GetCanonicalCharacterKey(liveKey)) or liveKey
    if rowCanon == liveCanon then return true end
    if ns.VaultCharKeysMatch and ns.VaultCharKeysMatch(charKey, liveKey) then return true end
    return false
end

local function CountItemIDInArray(items, itemID)
    if not items or not itemID then return 0 end
    local U = ns.Utilities
    if U and U.IsKeystoneItemID and U:IsKeystoneItemID(itemID) then return 0 end
    local total = 0
    for i = 1, #items do
        local item = items[i]
        if item and item.itemID == itemID and not item.isKeystone then
            total = total + (item.stackCount or 1)
        end
    end
    return total
end

local function CountItemInWarbandBank(itemID)
    local warbandData = WarbandNexus:GetWarbandBankData()
    if warbandData and warbandData.items then
        return CountItemIDInArray(warbandData.items, itemID)
    end
    return 0
end

local function IsWarbandBankAccessibleForLiveScan()
    if isWarbandBankOpen or isBankOpen then
        return true
    end
    if WarbandNexus and WarbandNexus.bankIsOpen then
        return true
    end
    return false
end

local function InvalidateLiveOpenWarbandBankSummary()
    liveOpenWarbandSummary = nil
end

--- Live warband bank stacks while bank frame is open (session cache; tooltip WN Search parity with guild).
function WarbandNexus:BuildLiveOpenWarbandBankItemSummary()
    if not IsWarbandBankAccessibleForLiveScan() then
        return nil
    end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return nil
    end
    local gen = warbandBankScanGeneration
    if liveOpenWarbandSummary and liveOpenWarbandSummary.gen == gen then
        return liveOpenWarbandSummary
    end
    local items = {}
    local U = ns.Utilities
    for wi = 1, #WARBAND_BAGS do
        local bagID = WARBAND_BAGS[wi]
        local bagItems = ScanBag(bagID)
        for i = 1, #bagItems do
            local item = bagItems[i]
            local id = item and item.itemID
            if id and not item.isKeystone
                and not (U and U.IsKeystoneItemID and U:IsKeystoneItemID(id)) then
                items[id] = (items[id] or 0) + (item.stackCount or 1)
            end
        end
    end
    liveOpenWarbandSummary = { items = items, gen = gen }
    return liveOpenWarbandSummary
end

---@return number stackCount
function WarbandNexus:GetLiveOpenWarbandBankItemCountForTooltip(itemID)
    if not itemID then
        return 0
    end
    local summary = self:BuildLiveOpenWarbandBankItemSummary()
    if not summary then
        return 0
    end
    return summary.items[itemID] or 0
end

--- Drop live warband-bank tooltip tally (bank closed or scan superseded).
function WarbandNexus:InvalidateLiveOpenWarbandBankSummary()
    InvalidateLiveOpenWarbandBankSummary()
end

local function CollectGuildItemCountsFromDB(itemID, guildBank)
    local guildRows = {}
    if not itemID or not guildBank then return guildRows end
    local U = ns.Utilities
    for guildName, guildData in pairs(guildBank) do
        if guildName and not (issecretvalue and issecretvalue(guildName)) and type(guildData) == "table" then
            local count = 0
            for _, tabData in pairs(guildData.tabs or {}) do
                for _, itemData in pairs(tabData.items or {}) do
                    local id = itemData and itemData.itemID
                    if id == itemID and not itemData.isKeystone
                        and not (U and U.IsKeystoneItemID and U:IsKeystoneItemID(id)) then
                        count = count + (itemData.stackCount or 1)
                    end
                end
            end
            if count > 0 then
                guildRows[#guildRows + 1] = {
                    guildName = guildName,
                    count = count,
                    tabard = guildData.tabard,
                }
            end
        end
    end
    if #guildRows > 1 then
        table.sort(guildRows, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.guildName or "") < (b.guildName or "")
        end)
    end
    return guildRows
end

local function ResolveCharacterStorageKeyForCount(self, charKey)
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey then
        return CS:ResolveSubsidiaryCharacterKey(self, charKey) or charKey
    end
    return charKey
end

local function CountCharacterItemFromStorage(self, storageKey, itemID)
    local data = self:GetItemsData(storageKey)
    if not data then return 0, 0 end
    return CountItemIDInArray(data.bags, itemID), CountItemIDInArray(data.bank, itemID)
end

local function ScheduleBackgroundSummaryDrain()
    if summaryDrainScheduled or not SummaryDrainHasWork() then return end
    summaryDrainScheduled = true
    C_Timer.After(0, function()
        summaryDrainScheduled = false
        ProcessPendingSummariesBudgeted(SUMMARY_BUILD_BUDGET_MS)
        if SummaryDrainHasWork() then
            ScheduleBackgroundSummaryDrain()
        end
    end)
end

---Get detailed item counts for tooltip display (direct itemStorage / guildBank lookup by itemID).
function WarbandNexus:GetDetailedItemCountsFast(itemID)
    if not itemID then return nil end
    if ns.Utilities and ns.Utilities.IsKeystoneItemID and ns.Utilities:IsKeystoneItemID(itemID) then
        return nil
    end

    local liveRaw = ResolveCurrentItemStorageKey()
    local guildBank = self.db and self.db.global and self.db.global.guildBank

    local warbandCount = CountItemInWarbandBank(itemID)
    if IsWarbandBankAccessibleForLiveScan() and self.GetLiveOpenWarbandBankItemCountForTooltip then
        local okLive, liveCount = pcall(self.GetLiveOpenWarbandBankItemCountForTooltip, self, itemID)
        if okLive and liveCount ~= nil then
            warbandCount = liveCount
        end
    end
    local guildRows = CollectGuildItemCountsFromDB(itemID, guildBank)

    if self.guildBankIsOpen and self.GetLiveOpenGuildBankItemCountForTooltip then
        local okLive, liveGuildName, liveCount = pcall(self.GetLiveOpenGuildBankItemCountForTooltip, self, itemID)
        if okLive and liveGuildName and liveCount and liveCount > 0 then
            local merged = false
            for i = 1, #guildRows do
                if guildRows[i].guildName == liveGuildName then
                    guildRows[i].count = liveCount
                    merged = true
                    break
                end
            end
            if not merged then
                local gd = guildBank and guildBank[liveGuildName]
                guildRows[#guildRows + 1] = {
                    guildName = liveGuildName,
                    count = liveCount,
                    tabard = gd and gd.tabard,
                }
            end
        end
    end
    if #guildRows > 1 then
        table.sort(guildRows, function(a, b)
            if a.count ~= b.count then return a.count > b.count end
            return (a.guildName or "") < (b.guildName or "")
        end)
    end

    local result = {
        warbandBank = warbandCount,
        guilds = guildRows,
        personalBankTotal = 0,
        characters = {},
    }

    for charKey, charData in pairs(self.db.global.characters or {}) do
        local bagCount, bankCount = 0, 0
        if CharacterKeysMatchForTooltip(charKey, liveRaw) then
            bagCount = SafeGetItemCount(itemID, false)
            local totalIncBank = SafeGetItemCount(itemID, true)
            bankCount = totalIncBank - bagCount
            if bankCount < 0 then bankCount = 0 end
        else
            local storageKey = ResolveCharacterStorageKeyForCount(self, charKey)
            bagCount, bankCount = CountCharacterItemFromStorage(self, storageKey, itemID)
        end

        if bagCount > 0 or bankCount > 0 then
            result.personalBankTotal = result.personalBankTotal + bankCount
            result.characters[#result.characters + 1] = {
                charName = (function()
                    if charData.name then return charData.name end
                    if type(charKey) ~= "string" or charKey == "" then return nil end
                    if issecretvalue and issecretvalue(charKey) then return nil end
                    return charKey:match("^([^-]+)")
                end)(),
                classFile = charData.classFile or charData.class,
                bagCount = bagCount,
                bankCount = bankCount,
                total = bagCount + bankCount,
                isLiveSession = CharacterKeysMatchForTooltip(charKey, liveRaw),
            }
        end
    end

    table.sort(result.characters, function(a, b)
        if a.isLiveSession ~= b.isLiveSession then return a.isLiveSession end
        return a.total > b.total
    end)

    return result
end

---Invalidate item summary for a character (call when bags/bank change).
---The summary will be rebuilt lazily on next tooltip access.
function WarbandNexus:InvalidateItemSummary(charKey)
    if charKey then
        itemSummaryIndex.pending[charKey] = true
    else
        -- Invalidate everything
        for key in pairs(itemSummaryIndex.characters) do
            itemSummaryIndex.pending[key] = true
        end
        itemSummaryIndex.warbandPending = true
        itemSummaryIndex.guildPending = true
    end
end

---Invalidate guild vault item summary (call after guild bank scan or cache purge).
function WarbandNexus:InvalidateGuildItemSummary()
    itemSummaryIndex.guildPending = true
end

---Force refresh all bags (ignore cache)
function WarbandNexus:RefreshAllBags()
    local charKey = ResolveCurrentItemStorageKey()
    
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
    
    self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "all", charKey = CanonicalItemsMessageKey(charKey)})
end

-- INITIALIZATION

---Initialize items cache on login
function WarbandNexus:InitializeItemsCache()
    -- Both InitializationService P4 and ConfirmCharacterTracking can reach this;
    -- a second RegisterBucketEvent would create a duplicate 0.5s bucket (AceBucket
    -- does not overwrite re-registrations the way AceEvent does).
    if self._itemsCacheInitialized then return end
    self._itemsCacheInitialized = true

    -- ── Event Ownership (single owner for all bag/bank events) ──
    WarbandNexus:RegisterBucketEvent("BAG_UPDATE", 0.5, "OnBagUpdate")
    WarbandNexus:RegisterBucketEvent("PLAYERBANKSLOTS_CHANGED", 0.5, "OnBagUpdate")
    WarbandNexus:RegisterEvent("BANKFRAME_OPENED", "OnBankOpened")
    WarbandNexus:RegisterEvent("BANKFRAME_CLOSED", "OnBankClosed")
    WarbandNexus:RegisterEvent("BAG_UPDATE_DELAYED", "OnInventoryBagsChanged")
    WarbandNexus:RegisterEvent("PLAYER_LEAVING_WORLD", "FlushItemsCacheOnLeavingWorld")
    StartSessionIdleFlushTicker()
    
    -- Set loading state (initial scan in progress)
    ns.ItemsLoadingState.isLoading = true
    ns.ItemsLoadingState.currentStage = (ns.L and ns.L["ITEMS_LOADING_STAGE_WAIT"]) or "Waiting to start"
    ns.ItemsLoadingState.scanProgress = 0
    ns.ItemsLoadingState.loadingProgress = 0

    local function setItemsBootProgress(pct, stage)
        ns.ItemsLoadingState.scanProgress = pct
        ns.ItemsLoadingState.loadingProgress = pct
        if stage then
            ns.ItemsLoadingState.currentStage = stage
        end
    end

    -- Defer one tick so login init returns quickly; avoid multi-second fake progress (first Items tab paint uses saved data).
    C_Timer.After(0, function()
        if not ns.ItemsLoadingState.isLoading then return end
        setItemsBootProgress(60, (ns.L and ns.L["ITEMS_LOADING_STAGE_SCAN"]) or "Scanning inventory bags")

        local charKey = ResolveCurrentItemStorageKey()
        self:ScanInventoryBags(charKey)

        -- Warm bank decompress + summary after inventory session mark (avoid login frame stack).
        C_Timer.After(0.35, function()
            if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then return end
            local ck = ResolveCurrentItemStorageKey()
            if not ck then return end
            AcquireV2BucketItemArray(ck, "bank")
            if itemSummaryIndex.pending[ck] then
                BuildCharacterSummary(ck)
            end
        end)

        ns.ItemsLoadingState.scanProgress = 100
        ns.ItemsLoadingState.loadingProgress = 100
        ns.ItemsLoadingState.isLoading = false
        ns.ItemsLoadingState.currentStage = nil

        -- Notify UI that initial scan is done (fixes stuck loading state)
        self:SendMessage(Constants.EVENTS.ITEMS_UPDATED, {type = "all", charKey = CanonicalItemsMessageKey(charKey)})
    end)
end

-- DEBUG PERF STRESS HOOKS (ItemsCacheService_PerfStress.lua; requires /wn debug)

function StressHooks.ResolveCharKey()
    return ResolveCurrentItemStorageKey()
end

function StressHooks.AcquireV2(charKey, dataType)
    local t0 = debugprofilestop()
    local arr, hit = AcquireV2BucketItemArray(charKey, dataType)
    return arr, hit, debugprofilestop() - t0
end

function StressHooks.ClearSessionDecompressedCache()
    wipe(decompressedItemCache)
end

function StressHooks.ReplaceBagInArray(allItems, bagID, newBagItems)
    local t0 = debugprofilestop()
    local _, slotCount = ReplaceBagInItemArray(allItems, bagID, newBagItems)
    return slotCount, debugprofilestop() - t0
end

function StressHooks.GenerateItemHash(bagID)
    local t0 = debugprofilestop()
    local hash = GenerateItemHash(bagID)
    return hash, debugprofilestop() - t0
end

function StressHooks.HasBagChanged(bagID)
    local t0 = debugprofilestop()
    local changed = HasBagChanged(bagID)
    return changed, debugprofilestop() - t0
end

function StressHooks.ScanBag(bagID)
    local t0 = debugprofilestop()
    local items = ScanBag(bagID)
    return items, debugprofilestop() - t0
end

function StressHooks.BuildCharacterSummary(charKey, force)
    local t0 = debugprofilestop()
    BuildCharacterSummary(charKey, force)
    return debugprofilestop() - t0
end

function StressHooks.BumpGearStorageScanGeneration()
    BumpGearStorageScanGeneration()
end

function StressHooks.BumpGearStorageScanGenerationImmediate()
    BumpGearStorageScanGenerationImmediate()
end

function StressHooks.GetGearStorageInvGen()
    return ns._gearStorageInvGen or 0
end

function StressHooks.FlushPendingCompress(syncAll)
    FlushPendingCompressWrites(syncAll == true)
end

function StressHooks.ScheduleCompressCoalesce()
    ScheduleCompressCoalesce()
end

function StressHooks.HasPendingCompress()
    return next(sessionDirtyBuckets) ~= nil
end

function StressHooks.HasSessionDirty()
    return next(sessionDirtyBuckets) ~= nil
end

function StressHooks.SessionDirtyCount()
    local n = 0
    for _ in pairs(sessionDirtyBuckets) do
        n = n + 1
    end
    return n
end

function StressHooks.InvalidateSummary(charKey)
    if WarbandNexus.InvalidateItemSummary then
        WarbandNexus:InvalidateItemSummary(charKey)
    end
end

function StressHooks.WipeCharacterSummary(charKey)
    if charKey then
        itemSummaryIndex.characters[charKey] = nil
        itemSummaryIndex.sessionGen[charKey] = nil
    end
end

function StressHooks.BeginPhaseRecord()
    StressHooks._recording = { phases = {}, t0 = debugprofilestop() }
end

function StressHooks.EndPhaseRecord()
    local rec = StressHooks._recording
    StressHooks._recording = nil
    return rec and rec.phases
end

function StressHooks.FormatPhaseLine(phases)
    if not phases then return nil end
    local order = { "acquire", "scan", "merge", "snapshot", "summary", "save" }
    local parts = {}
    for i = 1, #order do
        local k = order[i]
        local ms = phases[k]
        if ms and ms > 0.01 then
            parts[#parts + 1] = string.format("%s=%.2f", k, ms)
        end
    end
    if #parts == 0 then return nil end
    return table.concat(parts, " ")
end

-- LOAD MESSAGE

-- Module loaded - verbose logging hidden (debug mode only)
