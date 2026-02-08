--[[
    Warband Nexus - Try Counter Service
    Automatic try counter with multi-method detection:
      NPC/Boss kills, GameObjects, Fishing, Container items, Zone-wide drops
    
    DB: db.global.tryCounts[type][id] = count
    
    Detection flow:
      CLEU UNIT_DIED → recentKills → LOOT_OPENED → scan loot → increment/skip
      ENCOUNTER_END → Midnight fallback for instanced bosses
      UNIT_SPELLCAST_SENT → fishing flag
      UNIT_SPELLCAST_SUCCEEDED → container tracking
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- =====================================================================
-- CONSTANTS & UPVALUES (performance: resolved once at file load)
-- =====================================================================

local VALID_TYPES = { mount = true, pet = true, toy = true, illusion = true }
local RECENT_KILL_TTL = 15       -- seconds to keep kills in recentKills
local PROCESSED_GUID_TTL = 300   -- seconds before allowing same GUID again
local CLEANUP_INTERVAL = 60      -- seconds between cleanup ticks

-- Upvalue WoW API functions (avoid global lookups in hot paths)
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitGUID = UnitGUID
local GetNumLootItems = GetNumLootItems
local GetLootSlotLink = GetLootSlotLink
local LootSlotHasItem = LootSlotHasItem
local GetItemInfoInstant = GetItemInfoInstant
local GetTime = GetTime
local strsplit = strsplit
local tonumber = tonumber
local pairs = pairs
local ipairs = ipairs
local format = string.format
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local C_ToyBox = C_ToyBox
local PlayerHasToy = PlayerHasToy
local C_Map = C_Map
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown

-- Midnight 12.0: Secret Values API (nil on pre-12.0 clients, backward-compatible)
-- Secret values are returned by combat APIs during instanced combat.
-- Tainted code cannot compare, do arithmetic, use as table keys, or string-operate on them.
-- issecretvalue(v) returns true if v is a secret value that cannot be operated on.
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

-- Fishing spell IDs
local FISHING_SPELLS = {
    [131474] = true,  -- Fishing (modern)
    [7620] = true,    -- Fishing (legacy)
    [110412] = true,  -- Fishing (Zen)
    [271990] = true,  -- Fishing (BfA)
    [271991] = true,  -- Fishing (KT variant)
}

-- =====================================================================
-- STATE (file-local, zero global pollution)
-- =====================================================================

-- DB references (set at init from ns.CollectibleSourceDB)
local npcDropDB = {}
local objectDropDB = {}
local fishingDropDB = {}
local containerDropDB = {}
local zoneDropDB = {}
local encounterDB = {}

-- Runtime state
local recentKills = {}       -- [guid] = { npcID = n, name = s, time = t }
local processedGUIDs = {}    -- [guid] = timestamp
local isFishing = false      -- set on fishing cast, cleared on LOOT_CLOSED
local lastContainerItemID = nil  -- set on container use
local resolvedIDs = {}       -- [itemID] = { type, collectibleID } - runtime resolved mount/pet IDs

-- =====================================================================
-- DATABASE HELPERS
-- =====================================================================

---Ensure SavedVariable structure exists
local function EnsureDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return false
    end
    if not WarbandNexus.db.global.tryCounts then
        WarbandNexus.db.global.tryCounts = {
            mount = {}, pet = {}, toy = {}, illusion = {},
        }
    end
    for t in pairs(VALID_TYPES) do
        if not WarbandNexus.db.global.tryCounts[t] then
            WarbandNexus.db.global.tryCounts[t] = {}
        end
    end
    return true
end

-- =====================================================================
-- PUBLIC API (manual get/set/increment - unchanged from before)
-- =====================================================================

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@return number count
function WarbandNexus:GetTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not EnsureDB() then return 0 end
    local count = WarbandNexus.db.global.tryCounts[collectibleType][id]
    return type(count) == "number" and count or 0
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@param count number
function WarbandNexus:SetTryCount(collectibleType, id, count)
    if not VALID_TYPES[collectibleType] or not id then return end
    if not EnsureDB() then return end
    count = tonumber(count)
    if not count or count < 0 then count = 0 end
    WarbandNexus.db.global.tryCounts[collectibleType][id] = count
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@return number newCount
function WarbandNexus:IncrementTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not EnsureDB() then return 0 end
    local current = WarbandNexus:GetTryCount(collectibleType, id)
    local newCount = current + 1
    WarbandNexus.db.global.tryCounts[collectibleType][id] = newCount
    return newCount
end

-- =====================================================================
-- GUID PARSING (minimal allocation)
-- =====================================================================

---Extract NPC ID from a creature/vehicle GUID
---@param guid string
---@return number|nil npcID
local function GetNPCIDFromGUID(guid)
    if not guid then return nil end
    -- Midnight 12.0: GUID may be a secret value during instanced combat
    if issecretvalue and issecretvalue(guid) then return nil end
    local unitType, _, _, _, _, npcID = strsplit("-", guid)
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end
    return nil
end

---Extract object ID from a GameObject GUID
---@param guid string
---@return number|nil objectID
local function GetObjectIDFromGUID(guid)
    if not guid then return nil end
    -- Midnight 12.0: GUID may be a secret value during instanced combat
    if issecretvalue and issecretvalue(guid) then return nil end
    local unitType, _, _, _, _, objectID = strsplit("-", guid)
    if unitType == "GameObject" then
        return tonumber(objectID)
    end
    return nil
end

-- =====================================================================
-- COLLECTIBLE ID RESOLUTION (runtime mount/pet ID lookup)
-- =====================================================================

---Resolve collectibleID from itemID at runtime
---Returns the native collectible ID (mountID/speciesID) if the API can resolve it.
---Does NOT cache nil results so the API can be retried on subsequent loot events
---(Blizzard_Collections may not be loaded on first call).
---@param drop table { type, itemID, name }
---@return number|nil collectibleID
local function ResolveCollectibleID(drop)
    if not drop or not drop.itemID then return nil end

    -- Check cache first (only successful resolutions are cached)
    local cached = resolvedIDs[drop.itemID]
    if cached then return cached end

    local id = nil

    if drop.type == "mount" then
        -- C_MountJournal.GetMountFromItem(itemID) -> mountID
        if C_MountJournal.GetMountFromItem then
            id = C_MountJournal.GetMountFromItem(drop.itemID)
            -- Midnight 12.0: return value may be secret
            if issecretvalue and id and issecretvalue(id) then id = nil end
        end
    elseif drop.type == "pet" then
        -- C_PetJournal.GetPetInfoByItemID(itemID) -> speciesID
        if C_PetJournal.GetPetInfoByItemID then
            id = C_PetJournal.GetPetInfoByItemID(drop.itemID)
            -- Midnight 12.0: return value may be secret
            if issecretvalue and id and issecretvalue(id) then id = nil end
        end
    elseif drop.type == "toy" then
        -- For toys, collectibleID == itemID
        id = drop.itemID
    end

    -- Only cache successful resolutions; nil is NOT cached so retries are possible
    if id then
        resolvedIDs[drop.itemID] = id
    end

    return id
end

---Get the try count key for a drop entry.
---Uses native collectibleID if available, falls back to itemID.
---This ensures try counts ALWAYS increment even if the API can't resolve the ID.
---@param drop table { type, itemID, name }
---@return number tryCountKey The ID to use for try count storage
local function GetTryCountKey(drop)
    -- Try native resolution first (mountID/speciesID)
    local collectibleID = ResolveCollectibleID(drop)
    if collectibleID then return collectibleID end
    -- Fallback: use itemID directly as the try count key
    -- This means the DB stores tryCounts.mount[itemID] instead of tryCounts.mount[mountID]
    -- for items where the API can't resolve. Slightly inconsistent keys but guarantees tracking.
    return drop.itemID
end

-- =====================================================================
-- COLLECTED CHECK (skip already-owned collectibles)
-- =====================================================================

---Check if a collectible is already collected
---Uses native collectibleID for accurate checks, with itemID-based fallbacks
---@param drop table { type, itemID, name }
---@return boolean
local function IsCollectibleCollected(drop)
    if not drop then return false end

    local collectibleID = ResolveCollectibleID(drop)

    if drop.type == "mount" then
        if collectibleID then
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(collectibleID)
            -- Midnight 12.0: isCollected may be a secret value (can't do boolean test)
            if issecretvalue and isCollected and issecretvalue(isCollected) then return false end
            return isCollected == true
        end
        -- Fallback: Can't determine without mountID, assume not collected (keep counting)
        return false
    elseif drop.type == "pet" then
        if collectibleID then
            local numCollected = C_PetJournal.GetNumCollectedInfo(collectibleID)
            -- Midnight 12.0: numCollected may be secret (can't compare > 0)
            if issecretvalue and numCollected and issecretvalue(numCollected) then return false end
            return numCollected and numCollected > 0
        end
        -- Fallback: Can't determine without speciesID, assume not collected (keep counting)
        return false
    elseif drop.type == "toy" then
        -- Toys: itemID IS the collectibleID, always works
        local hasToy = PlayerHasToy(drop.itemID)
        -- Midnight 12.0: hasToy may be secret
        if issecretvalue and hasToy and issecretvalue(hasToy) then return false end
        return hasToy == true
    end

    return false
end

-- =====================================================================
-- LOOT WINDOW SCANNING
-- =====================================================================

---Scan loot window and return set of found itemIDs
---@param expectedDrops table Array of drop entries
---@return table foundItemIDs Set of itemIDs found in loot { [itemID] = true }
local function ScanLootForItems(expectedDrops)
    local found = {}
    local numItems = GetNumLootItems()
    if not numItems or numItems == 0 then return found end

    -- Build expected set for O(1) lookup
    local expectedSet = {}
    for i = 1, #expectedDrops do
        expectedSet[expectedDrops[i].itemID] = true
    end

    for i = 1, numItems do
        if LootSlotHasItem(i) then
            local link = GetLootSlotLink(i)
            if link then
                local itemID = GetItemInfoInstant(link)
                if itemID and expectedSet[itemID] then
                    found[itemID] = true
                end
            end
        end
    end

    return found
end

-- =====================================================================
-- TRY COUNT INCREMENT + CHAT MESSAGE
-- =====================================================================

---Increment try count and print chat message for unfound drops
---Uses GetTryCountKey which falls back to itemID if API can't resolve collectibleID.
---This ensures try counts ALWAYS increment, even for items the WoW API can't resolve.
---@param drops table Array of drop entries that were NOT found in loot
local function ProcessMissedDrops(drops)
    if not drops or #drops == 0 then return end
    if not EnsureDB() then return end

    for i = 1, #drops do
        local drop = drops[i]
        local tryKey = GetTryCountKey(drop)
        if tryKey then
            local newCount = WarbandNexus:IncrementTryCount(drop.type, tryKey)
            if WarbandNexus.Print then
                -- Different message for guaranteed vs random drops
                local msgFormat = drop.guaranteed
                    and "|cff9370DB[WN-Counter]|r : %d kills (%s)"
                    or "|cff9370DB[WN-Counter]|r : %d attempts for |cffff8000%s|r"
                WarbandNexus:Print(format(msgFormat, newCount, drop.name or "Unknown"))
            end
        end
    end
end

-- =====================================================================
-- SETTING CHECK
-- =====================================================================

---Check if auto try counter is enabled
---@return boolean
local function IsAutoTryCounterEnabled()
    if not WarbandNexus or not WarbandNexus.db then return false end
    if not WarbandNexus.db.profile or not WarbandNexus.db.profile.notifications then return false end
    return WarbandNexus.db.profile.notifications.autoTryCounter == true
end

-- =====================================================================
-- EVENT HANDLERS
-- =====================================================================

---COMBAT_LOG_EVENT_UNFILTERED handler (HOT PATH - fires hundreds of times/sec)
---Only processes UNIT_DIED events for NPCs in our database
function WarbandNexus:OnTryCounterCombatLog()
    -- Single call, destructure only what we need
    local _, subevent, _, _, _, _, _, destGUID, destName = CombatLogGetCurrentEventInfo()

    -- Midnight 12.0: CLEU values are secret during instanced combat (raids, M+, delves).
    -- Secret values cannot be compared, string-operated, or used as table keys.
    -- When secret, bail out silently; ENCOUNTER_END handles instanced boss kills instead.
    if issecretvalue and issecretvalue(subevent) then return end

    -- EXIT 1: Not a death event (filters 99%+ of events immediately)
    if subevent ~= "UNIT_DIED" then return end

    -- Midnight 12.0: destGUID/destName may also be secret
    if issecretvalue and (issecretvalue(destGUID) or issecretvalue(destName)) then return end

    -- EXIT 2: Extract NPC ID, skip non-creatures (GetNPCIDFromGUID has its own secret guard)
    local npcID = GetNPCIDFromGUID(destGUID)
    if not npcID then return end

    -- EXIT 3: NPC not in our drop database (O(1) hash lookup)
    local inNpcDB = npcDropDB[npcID]
    if not inNpcDB then
        -- Secondary check: is current zone in zoneDropDB?
        if next(zoneDropDB) then
            local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            if mapID and zoneDropDB[mapID] then
                -- Store as zone kill (destGUID is verified non-secret above)
                recentKills[destGUID] = recentKills[destGUID] or {}
                local entry = recentKills[destGUID]
                entry.npcID = npcID
                entry.name = destName
                entry.time = GetTime()
                entry.zoneMapID = mapID
            end
        end
        return
    end

    -- Store kill (destGUID is verified non-secret above, safe as table key)
    recentKills[destGUID] = recentKills[destGUID] or {}
    local entry = recentKills[destGUID]
    entry.npcID = npcID
    entry.name = destName
    entry.time = GetTime()
    entry.zoneMapID = nil
end

---ENCOUNTER_END handler (Midnight 12.0-safe fallback for instanced bosses)
---NOTE: Event arguments passed via RegisterEvent are NOT secret values.
---Only CombatLogGetCurrentEventInfo() returns secrets during instanced combat.
---This handler is the primary kill detection path when CLEU data is secret.
---@param event string
---@param encounterID number
---@param encounterName string
---@param difficultyID number
---@param groupSize number
---@param success number 1 = killed, 0 = wipe
function WarbandNexus:OnTryCounterEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize, success)
    if not IsAutoTryCounterEnabled() then return end
    if success ~= 1 then return end -- Only on successful kills

    local npcIDs = encounterDB[encounterID]
    if not npcIDs then return end

    -- Create synthetic kill entries for all NPCs in this encounter
    for i = 1, #npcIDs do
        local npcID = npcIDs[i]
        if npcDropDB[npcID] then
            -- Use encounterID as a synthetic GUID for dedup
            local syntheticGUID = "Encounter-" .. encounterID .. "-" .. GetTime()
            recentKills[syntheticGUID] = {
                npcID = npcID,
                name = encounterName or "Boss",
                time = GetTime(),
            }
        end
    end
end

---UNIT_SPELLCAST_SENT handler (detect fishing casts)
function WarbandNexus:OnTryCounterSpellcastSent(event, unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    if FISHING_SPELLS[spellID] then
        isFishing = true
    end
end

---UNIT_SPELLCAST_SUCCEEDED handler (detect container item usage)
function WarbandNexus:OnTryCounterSpellcastSucceeded(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    -- Container items are tracked by their itemID, not spellID
    -- We set the flag based on recent item use; matched in LOOT_OPENED
end

---LOOT_CLOSED handler (reset fishing flag)
function WarbandNexus:OnTryCounterLootClosed()
    isFishing = false
    lastContainerItemID = nil
end

---LOOT_OPENED handler (CENTRAL ROUTER - dispatches to correct processing path)
---@param event string
---@param autoLoot boolean
---@param isFromItem boolean Added in 8.3.0, true if loot is from opening a container item
function WarbandNexus:OnTryCounterLootOpened(event, autoLoot, isFromItem)
    if not IsAutoTryCounterEnabled() then return end

    ns.DebugPrint("|cff9370DB[TryCounter]|r LOOT_OPENED | isFromItem=" .. tostring(isFromItem) .. " | isFishing=" .. tostring(isFishing))

    -- Route 1: Container item
    if isFromItem then
        self:ProcessContainerLoot()
        return
    end

    -- Route 2: Fishing
    if isFishing then
        self:ProcessFishingLoot()
        return
    end

    -- Route 3: NPC / Object / Zone
    self:ProcessNPCLoot()
end

-- =====================================================================
-- PROCESSING PATHS
-- =====================================================================

---Safely get target GUID (Midnight 12.0: UnitGUID returns secret values for NPC targets)
---@return string|nil guid Safe GUID string or nil
local function SafeGetTargetGUID()
    local ok, guid = pcall(UnitGUID, "target")
    if not ok or not guid then return nil end
    -- Midnight 12.0: UnitGUID returns secret values for non-player/pet targets.
    -- Use issecretvalue() (12.0+) as primary check, pcall(string.len) as fallback for TWW.
    if issecretvalue then
        if issecretvalue(guid) then return nil end
    else
        -- Pre-12.0 fallback: string.len fails on secret/protected values
        local ok2 = pcall(string.len, guid)
        if not ok2 then return nil end
    end
    return guid
end

---Process loot from NPC corpse or game object
function WarbandNexus:ProcessNPCLoot()
    -- SafeGetTargetGUID already filters secret values via issecretvalue
    local targetGUID = SafeGetTargetGUID()

    -- Try to match from recentKills first (most reliable, CLEU-based)
    local drops = nil
    local dedupGUID = nil

    if targetGUID then
        -- targetGUID is guaranteed non-secret by SafeGetTargetGUID, safe as table key
        if processedGUIDs[targetGUID] then return end

        -- Try NPC first (GetNPCIDFromGUID has its own secret guard)
        local npcID = GetNPCIDFromGUID(targetGUID)
        drops = npcID and npcDropDB[npcID]

        -- Try GameObject if not an NPC
        if not drops then
            local objectID = GetObjectIDFromGUID(targetGUID)
            drops = objectID and objectDropDB[objectID]
        end

        dedupGUID = targetGUID
    end

    -- Try zone-wide drops if neither NPC nor object matched
    if not drops and next(zoneDropDB) then
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        -- mapID is safe: C_Map returns player's own zone, not a combat-secret value
        if mapID then
            drops = zoneDropDB[mapID]
        end
    end

    -- Fallback: check recentKills for CLEU-tracked kills (if target changed or GUID was secret)
    -- recentKills keys are verified non-secret at insertion time (OnTryCounterCombatLog guards this)
    if not drops then
        local now = GetTime()
        for guid, killData in pairs(recentKills) do
            if now - killData.time < RECENT_KILL_TTL then
                if killData.zoneMapID then
                    drops = zoneDropDB[killData.zoneMapID]
                else
                    drops = npcDropDB[killData.npcID]
                end
                if drops then
                    dedupGUID = guid -- CLEU GUID already verified non-secret at insertion
                    break
                end
            end
        end
    end

    if not drops then return end

    -- Filter to uncollected drops only
    local uncollected = {}
    for i = 1, #drops do
        if not IsCollectibleCollected(drops[i]) then
            uncollected[#uncollected + 1] = drops[i]
        end
    end
    if #uncollected == 0 then return end -- All collected, skip

    -- Scan loot window
    local found = ScanLootForItems(uncollected)

    -- Mark GUID as processed (dedupGUID is verified non-secret)
    if dedupGUID then
        processedGUIDs[dedupGUID] = GetTime()
    end

    -- Find missed drops (not in loot)
    local missed = {}
    for i = 1, #uncollected do
        if not found[uncollected[i].itemID] then
            missed[#missed + 1] = uncollected[i]
        end
    end

    -- Increment try counts for missed drops
    ProcessMissedDrops(missed)
end

---Process loot from fishing
function WarbandNexus:ProcessFishingLoot()
    -- Get current zone
    local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

    -- Merge zone-specific + global fishing drops
    local drops = {}
    if fishingDropDB[0] then
        for i = 1, #fishingDropDB[0] do
            drops[#drops + 1] = fishingDropDB[0][i]
        end
    end
    if mapID and fishingDropDB[mapID] then
        for i = 1, #fishingDropDB[mapID] do
            drops[#drops + 1] = fishingDropDB[mapID][i]
        end
    end

    if #drops == 0 then return end

    -- Filter to uncollected
    local uncollected = {}
    for i = 1, #drops do
        if not IsCollectibleCollected(drops[i]) then
            uncollected[#uncollected + 1] = drops[i]
        end
    end
    if #uncollected == 0 then return end

    -- Scan loot window
    local found = ScanLootForItems(uncollected)

    -- Find missed drops
    local missed = {}
    for i = 1, #uncollected do
        if not found[uncollected[i].itemID] then
            missed[#missed + 1] = uncollected[i]
        end
    end

    ProcessMissedDrops(missed)
end

---Process loot from container items (Paragon caches, etc.)
function WarbandNexus:ProcessContainerLoot()
    -- For containers, we need to check ALL known container drops
    -- since isFromItem doesn't tell us WHICH container was opened
    -- We scan the loot window against all container DB entries

    local allContainerDrops = {}
    for containerItemID, containerData in pairs(containerDropDB) do
        local drops = containerData.drops or containerData
        for i = 1, #drops do
            allContainerDrops[#allContainerDrops + 1] = drops[i]
        end
    end

    if #allContainerDrops == 0 then return end

    -- Filter to uncollected
    local uncollected = {}
    for i = 1, #allContainerDrops do
        if not IsCollectibleCollected(allContainerDrops[i]) then
            uncollected[#uncollected + 1] = allContainerDrops[i]
        end
    end
    if #uncollected == 0 then return end

    -- Scan loot window
    local found = ScanLootForItems(uncollected)

    -- For containers, we DON'T increment on miss because we can't reliably
    -- determine which container was opened. Instead, we only track successful
    -- drops (handled by existing bag scan system).
    -- However, if a specific container was tracked via UNIT_SPELLCAST_SUCCEEDED,
    -- we could increment. For now, container tracking is passive.

    -- TODO: If lastContainerItemID is set and matches a known container,
    -- increment for that specific container's drops
end

-- =====================================================================
-- INITIALIZATION
-- =====================================================================

---Initialize the automatic try counter system
function WarbandNexus:InitializeTryCounter()
    EnsureDB()

    -- Load DB references
    local db = ns.CollectibleSourceDB
    if db then
        npcDropDB = db.npcs or {}
        objectDropDB = db.objects or {}
        fishingDropDB = db.fishing or {}
        containerDropDB = db.containers or {}
        zoneDropDB = db.zones or {}
        encounterDB = db.encounters or {}
    end

    if not self.RegisterEvent then return end

    -- Register events
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", "OnTryCounterCombatLog")
    self:RegisterEvent("LOOT_OPENED", "OnTryCounterLootOpened")
    self:RegisterEvent("LOOT_CLOSED", "OnTryCounterLootClosed")
    self:RegisterEvent("ENCOUNTER_END", "OnTryCounterEncounterEnd")
    self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnTryCounterSpellcastSent")

    -- Periodic cleanup of stale GUIDs and kills (every 60s, batched)
    C_Timer.NewTicker(CLEANUP_INTERVAL, function()
        local now = GetTime()
        for guid, time in pairs(processedGUIDs) do
            if now - time > PROCESSED_GUID_TTL then
                processedGUIDs[guid] = nil
            end
        end
        for guid, data in pairs(recentKills) do
            if now - data.time > RECENT_KILL_TTL then
                recentKills[guid] = nil
            end
        end
    end)

    ns.DebugPrint("|cff9370DB[TryCounter]|r Initialized | NPCs: " ..
        (db and db.npcs and tostring(ns.Utilities and ns.Utilities.TableCount and ns.Utilities:TableCount(db.npcs) or "?") or "0") ..
        " | Objects: " .. (db and db.objects and tostring(ns.Utilities and ns.Utilities.TableCount and ns.Utilities:TableCount(db.objects) or "?") or "0") ..
        " | Fishing zones: " .. (db and db.fishing and tostring(ns.Utilities and ns.Utilities.TableCount and ns.Utilities:TableCount(db.fishing) or "?") or "0") ..
        " | Containers: " .. (db and db.containers and tostring(ns.Utilities and ns.Utilities.TableCount and ns.Utilities:TableCount(db.containers) or "?") or "0"))
end

-- =====================================================================
-- NAMESPACE EXPORT
-- =====================================================================

ns.TryCounterService = {
    GetTryCount = function(_, ct, id) return WarbandNexus:GetTryCount(ct, id) end,
    SetTryCount = function(_, ct, id, c) return WarbandNexus:SetTryCount(ct, id, c) end,
    IncrementTryCount = function(_, ct, id) return WarbandNexus:IncrementTryCount(ct, id) end,
}
