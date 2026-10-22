--[[
    Warband Nexus - Try Counter key reconciliation + Track Item DB (split from TryCounterService.lua, 2026-10-22)
    itemID -> native ID try-count migration on obtain, custom / disabled trackDB overlay merge and
    the trackDB CRUD API. Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
    DB tables are reassigned by LoadRuntimeSourceTables, so they are read as RT.* at the use site.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime

assert(Fns and RT and RT.pendingPreResetCounts and RT.repeatableCache, "TryCounterService_TrackDB: load TryCounterService.lua first")

-- Owned by TryCounterService.lua (separate chunk); shared through the Runtime table.
local pendingPreResetCounts = RT.pendingPreResetCounts
local repeatableCache = RT.repeatableCache

local VALID_TYPES = TC.VALID_TYPES or { mount = true, pet = true, toy = true, illusion = true, item = true }
local strsplit = strsplit
local tonumber = tonumber
local pairs = pairs
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local C_ToyBox = C_ToyBox
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

-- KEY RECONCILIATION (fix itemID→nativeID mismatch on obtain)

---When a collectible is obtained, the WoW API can now resolve the native ID
---(mountID/speciesID) reliably. If the TryCounter previously stored counts under
---an itemID fallback key (because the API couldn't resolve at LOOT_OPENED time),
---we need to migrate those counts to the native ID so NotificationManager reads
---the correct try count via GetTryCount(type, nativeID).
---This runs only once per obtained collectible — performance is not a concern.
---@param event string
---@param data table { type, id, name, icon }
function WarbandNexus:OnTryCounterCollectibleObtained(event, data)
    if not data or not data.type or not data.id then return end
    if not VALID_TYPES[data.type] then return end
    if not Fns.EnsureDB() then return end

    -- Inject pending pre-reset count (container or NPC loot reset) so notification can show "first try" / "X tries" and flash
    local cacheKey = data.type .. "\0" .. tostring(data.id)
    local pendingCount = pendingPreResetCounts[cacheKey]
    -- Mount: we may have stored by itemID at LOOT_OPENED (ResolveCollectibleID failed); CollectionService sends mountID
    if pendingCount == nil and data.type == "mount" and C_MountJournal and C_MountJournal.GetMountFromItem then
        for cid, containerData in pairs(RT.containerDropDB) do
            local drops = containerData.drops or containerData
            for d = 1, #drops do
                local drop = drops[d]
                if drop and drop.type == "mount" and drop.itemID then
                    local mid = C_MountJournal.GetMountFromItem(drop.itemID)
                    if mid and not (issecretvalue and issecretvalue(mid)) and mid == data.id then
                        pendingCount = pendingPreResetCounts["mount\0" .. tostring(drop.itemID)]
                        if pendingCount ~= nil then
                            pendingPreResetCounts["mount\0" .. tostring(drop.itemID)] = nil
                            break
                        end
                    end
                end
            end
            if pendingCount ~= nil then break end
        end
    end
    if pendingCount ~= nil then
        data.preResetTryCount = pendingCount
        pendingPreResetCounts[cacheKey] = nil
    end

    -- Check if this is a repeatable collectible -> reset try count instead of freezing
    if WarbandNexus:IsRepeatableCollectible(data.type, data.id) then
        if data.preResetTryCount == nil then
            data.preResetTryCount = WarbandNexus:GetTryCount(data.type, data.id)
        end
        WarbandNexus:ResetTryCount(data.type, data.id)
        return
    end

    -- Toys and generic items always use itemID for both storage and lookup — no mismatch possible
    if data.type == "toy" or data.type == "item" then
        Fns.EmitTryCounterObtainChatFromCollectibleEvent(WarbandNexus, data)
        return
    end

    local nativeID = data.id
    local typeTable = WarbandNexus.db.global.tryCounts[data.type]
    if not typeTable then
        Fns.EmitTryCounterObtainChatFromCollectibleEvent(WarbandNexus, data)
        return
    end

    -- If we already have a count under the native ID, no migration needed
    local existing = typeTable[nativeID]
    if existing and type(existing) == "number" and existing > 0 then
        Fns.EmitTryCounterObtainChatFromCollectibleEvent(WarbandNexus, data)
        return
    end

    -- Search CollectibleSourceDB for any drop entries matching this type
    -- where the itemID was used as a fallback key in the try count table.
    --
    -- Only include sources whose values are drop-entry arrays.
    -- encounterDB has a DIFFERENT format: [encounterID] = { npcID1, npcID2 }
    --   → indexing a number crashes ("attempt to index a number value")
    -- containerDropDB uses nested format: [id] = { drops = { {...} } }
    --   → handled separately below
    local flatSources = {
        RT.npcDropDB, RT.objectDropDB, RT.fishingDropDB, RT.zoneDropDB,
    }

    -- Helper: check a single drop entry for fallback key migration
    local function TryMigrateDrop(drop)
        if not drop or type(drop) ~= "table" then return false end
        if drop.type ~= data.type or not drop.itemID then return false end
        local fallbackCount = typeTable[drop.itemID]
        if not fallbackCount or type(fallbackCount) ~= "number" or fallbackCount <= 0 then return false end
        -- Verify this itemID actually resolves to our nativeID
        -- (the API should work now since the player just obtained it)
        local resolvedID = Fns.ResolveCollectibleID(drop)
        if resolvedID ~= nativeID then return false end
        -- Migrate: move count from itemID key to nativeID key
        typeTable[nativeID] = fallbackCount
        typeTable[drop.itemID] = nil
        return true
    end

    -- Check flat sources: [key] = { { type, itemID, name }, ... }
    -- zoneDropDB supports new format: { drops = {...}, raresOnly = true }
    for _, sourceTable in pairs(flatSources) do
        for _, entry in pairs(sourceTable) do
            if type(entry) == "table" then
                -- New format: { drops = {...}, raresOnly = true }
                local drops = entry.drops or entry
                if type(drops) == "table" then
                    for i = 1, #drops do
                        local drop = drops[i]
                        if TryMigrateDrop(drop) then
                            Fns.EmitTryCounterObtainChatFromCollectibleEvent(WarbandNexus, data)
                            return
                        end
                    end
                end
            end
        end
    end

    -- Check containerDropDB separately: [containerID] = { drops = { {...}, ... } }
    for _, containerData in pairs(RT.containerDropDB) do
        if type(containerData) == "table" then
            local drops = containerData.drops or containerData
            if type(drops) == "table" then
                for i = 1, #drops do
                    local drop = drops[i]
                    if TryMigrateDrop(drop) then
                        Fns.EmitTryCounterObtainChatFromCollectibleEvent(WarbandNexus, data)
                        return
                    end
                end
            end
        end
    end

    Fns.EmitTryCounterObtainChatFromCollectibleEvent(WarbandNexus, data)
end

-- TRACKDB MERGE (Custom entries overlay on CollectibleSourceDB)

function Fns.MergeTrackDB()
    if WarbandNexus.db and WarbandNexus.db.global then
        local trackDB = WarbandNexus.db.global.trackDB
        if trackDB then
            -- 1) Merge custom NPC entries into npcDropDB
            local customNpcs = trackDB.custom and trackDB.custom.npcs
            if customNpcs then
                for npcID, drops in pairs(customNpcs) do
                    npcID = tonumber(npcID)
                    if npcID and type(drops) == "table" then
                        if not RT.npcDropDB[npcID] then
                            RT.npcDropDB[npcID] = {}
                        end
                        local existing = RT.npcDropDB[npcID]
                        local existingByItemID = {}
                        for j = 1, #existing do
                            local ex = existing[j]
                            if ex and ex.itemID then
                                existingByItemID[ex.itemID] = true
                            end
                        end
                        for i = 1, #drops do
                            local drop = drops[i]
                            if drop and drop.itemID then
                                if not existingByItemID[drop.itemID] then
                                    existing[#existing + 1] = drop
                                    existingByItemID[drop.itemID] = true
                                end
                            end
                        end
                        -- Copy statisticIds from custom entry if present
                        if drops.statisticIds and not existing.statisticIds then
                            existing.statisticIds = drops.statisticIds
                        end
                    end
                end
            end

            -- 2) Merge custom Object entries into objectDropDB
            local customObjects = trackDB.custom and trackDB.custom.objects
            if customObjects then
                for objectID, drops in pairs(customObjects) do
                    objectID = tonumber(objectID)
                    if objectID and type(drops) == "table" then
                        if not RT.objectDropDB[objectID] then
                            RT.objectDropDB[objectID] = {}
                        end
                        local existing = RT.objectDropDB[objectID]
                        local existingByItemID = {}
                        for j = 1, #existing do
                            local ex = existing[j]
                            if ex and ex.itemID then
                                existingByItemID[ex.itemID] = true
                            end
                        end
                        for i = 1, #drops do
                            local drop = drops[i]
                            if drop and drop.itemID then
                                if not existingByItemID[drop.itemID] then
                                    existing[#existing + 1] = drop
                                    existingByItemID[drop.itemID] = true
                                end
                            end
                        end
                    end
                end
            end

            -- 3) Remove disabled entries (user-untracked built-in items)
            local disabled = trackDB.disabled
            if disabled then
                for key in pairs(disabled) do
                    local sourceType, sourceID, itemID = strsplit(":", key)
                    sourceID = tonumber(sourceID)
                    itemID = tonumber(itemID)
                    if sourceType and sourceID and itemID then
                        local db
                        if sourceType == "npc" then
                            db = RT.npcDropDB
                        elseif sourceType == "object" then
                            db = RT.objectDropDB
                        end
                        if db and db[sourceID] then
                            local drops = db[sourceID]
                            for i = #drops, 1, -1 do
                                if drops[i].itemID == itemID then
                                    table.remove(drops, i)
                                end
                            end
                            -- If no drops left, remove the source entry entirely
                            if #drops == 0 then
                                db[sourceID] = nil
                            end
                        end
                    end
                end
            end
        end
    end
    Fns.BuildTryCounterNpcEligible()
    Fns.SyncTryCounterRTTableRefs()
end

-- STATISTICS SEEDING: Modules/TryCounterService_Stats.lua


-- CRUD API (Track Item DB management)

--- Add a custom drop entry to the user's trackDB.
---@param sourceType string "npc" or "object"
---@param sourceID number NPC or Object ID
---@param drop table { type = "mount"|"pet"|"toy"|"item", itemID = number, name = string, [repeatable] = bool }
---@param statIds table|nil Optional array of WoW Statistic IDs
---@return boolean success
function WarbandNexus:AddCustomDrop(sourceType, sourceID, drop, statIds)
    if not self.db or not self.db.global then return false end
    sourceID = tonumber(sourceID)
    if not sourceID or not drop or not drop.itemID or not drop.type then return false end

    local trackDB = self.db.global.trackDB
    if not trackDB or not trackDB.custom then return false end

    local store
    if sourceType == "npc" then
        store = trackDB.custom.npcs
    elseif sourceType == "object" then
        store = trackDB.custom.objects
    else
        return false
    end

    if not store[sourceID] then
        store[sourceID] = {}
    end

    -- Check for duplicate
    local existing = store[sourceID]
    for i = 1, #existing do
        if existing[i].itemID == drop.itemID then
            return false  -- Already exists
        end
    end

    existing[#existing + 1] = {
        type = drop.type,
        itemID = drop.itemID,
        name = drop.name or ("Item " .. drop.itemID),
        repeatable = drop.repeatable or nil,
    }

    -- Attach statisticIds if provided
    if statIds and #statIds > 0 then
        existing.statisticIds = statIds
    end

    -- Rebuild runtime DB to pick up the new entry
    self:RebuildTrackDB()
    return true
end

--- Remove a custom drop entry from the user's trackDB.
---@param sourceType string "npc" or "object"
---@param sourceID number NPC or Object ID
---@param itemID number The item ID to remove
---@return boolean success
function WarbandNexus:RemoveCustomDrop(sourceType, sourceID, itemID)
    if not self.db or not self.db.global then return false end
    sourceID = tonumber(sourceID)
    itemID = tonumber(itemID)
    if not sourceID or not itemID then return false end

    local trackDB = self.db.global.trackDB
    if not trackDB or not trackDB.custom then return false end

    local store
    if sourceType == "npc" then
        store = trackDB.custom.npcs
    elseif sourceType == "object" then
        store = trackDB.custom.objects
    else
        return false
    end

    if not store[sourceID] then return false end

    local drops = store[sourceID]
    for i = #drops, 1, -1 do
        if drops[i].itemID == itemID then
            table.remove(drops, i)
            if #drops == 0 then
                store[sourceID] = nil
            end
            self:RebuildTrackDB()
            return true
        end
    end
    return false
end

--- Toggle tracking for a built-in CollectibleSourceDB entry.
---@param sourceType string "npc" or "object"
---@param sourceID number NPC or Object ID
---@param itemID number The item ID
---@param tracked boolean true = tracked (remove from disabled), false = untracked (add to disabled)
function WarbandNexus:SetBuiltinTracked(sourceType, sourceID, itemID, tracked)
    if not self.db or not self.db.global then return end
    sourceID = tonumber(sourceID)
    itemID = tonumber(itemID)
    if not sourceID or not itemID then return end

    local trackDB = self.db.global.trackDB
    if not trackDB then return end
    if not trackDB.disabled then trackDB.disabled = {} end

    local key = sourceType .. ":" .. sourceID .. ":" .. itemID
    if tracked then
        trackDB.disabled[key] = nil
    else
        trackDB.disabled[key] = true
    end

    self:RebuildTrackDB()
end

--- Check if a built-in entry is currently tracked (not disabled).
---@param sourceType string "npc" or "object"
---@param sourceID number NPC or Object ID
---@param itemID number The item ID
---@return boolean isTracked
function WarbandNexus:IsBuiltinTracked(sourceType, sourceID, itemID)
    if not self.db or not self.db.global then return true end
    local trackDB = self.db.global.trackDB
    if not trackDB or not trackDB.disabled then return true end
    local key = sourceType .. ":" .. sourceID .. ":" .. itemID
    return not trackDB.disabled[key]
end

--- Set a repeatable override for a collectible item.
--- Allows users to toggle repeatable status from Settings.
--- Pass nil to clear the override and revert to the DB default.
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"|"item"
---@param itemID number The item ID
---@param repeatable boolean|nil true/false = override, nil = revert to default
function WarbandNexus:SetBuiltinRepeatable(collectibleType, itemID, repeatable)
    if not self.db or not self.db.global then return end
    itemID = tonumber(itemID)
    if not collectibleType or not itemID then return end

    local trackDB = self.db.global.trackDB
    if not trackDB then return end
    if not trackDB.repeatableOverrides then trackDB.repeatableOverrides = {} end

    local key = collectibleType .. ":" .. tostring(itemID)
    trackDB.repeatableOverrides[key] = repeatable

    -- Clear cache so IsRepeatableCollectible picks up the new value
    wipe(repeatableCache)
end

--- Get the current repeatable override for a collectible, or nil if no override.
---@param collectibleType string
---@param itemID number
---@return boolean|nil override (true/false = overridden, nil = default)
function WarbandNexus:GetRepeatableOverride(collectibleType, itemID)
    if not self.db or not self.db.global then return nil end
    local trackDB = self.db.global.trackDB
    if not trackDB or not trackDB.repeatableOverrides then return nil end
    local key = (collectibleType or "") .. ":" .. tostring(itemID or 0)
    return trackDB.repeatableOverrides[key]
end

--- Lookup an item by ID and resolve its type, name, and icon.
---@param itemID number
---@param callback function Called with (itemID, name, icon, collectibleType) when data is available
function WarbandNexus:LookupItem(itemID, callback)
    itemID = tonumber(itemID)
    if not itemID or not callback then return end

    -- Use C_Item.RequestLoadItemDataByID to ensure item is cached, then resolve
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        local name = item:GetItemName()
        local icon = item:GetItemIcon()
        local collectibleType = "item"  -- default

        -- Try to detect mount
        if C_MountJournal.GetMountFromItem then
            local mountID = C_MountJournal.GetMountFromItem(itemID)
            if mountID and mountID > 0 then
                collectibleType = "mount"
            end
        end

        -- Try to detect pet
        if collectibleType == "item" and C_PetJournal.GetPetInfoByItemID then
            local petName = C_PetJournal.GetPetInfoByItemID(itemID)
            if petName then
                collectibleType = "pet"
            end
        end

        -- Try to detect toy
        if collectibleType == "item" and C_ToyBox and C_ToyBox.GetToyInfo then
            local toyItemID = C_ToyBox.GetToyInfo(itemID)
            if toyItemID then
                collectibleType = "toy"
            end
        end

        callback(itemID, name, icon, collectibleType)
    end)
end
