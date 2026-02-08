--[[
    Warband Nexus - Try Counter Service
    Automatic try counter with multi-method detection:
      NPC/Boss kills, GameObjects, Fishing, Container items, Zone-wide drops
    
    DB: db.global.tryCounts[type][id] = count
    
    Detection flow:
      CLEU UNIT_DIED → recentKills → LOOT_OPENED → scan loot → increment/skip
      ENCOUNTER_END → Midnight fallback for instanced bosses
      PLAYER_ENTERING_WORLD → instance entry → print collectible drops to chat
      UNIT_SPELLCAST_SENT → fishing flag (auto-reset after 30s safety timer)
      LOOT_OPENED isFromItem → container loot routing
    
    Key reconciliation:
      WN_COLLECTIBLE_OBTAINED → migrate itemID-fallback keys to nativeID
      (ensures NotificationManager reads correct try count in toast)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- =====================================================================
-- CONSTANTS & UPVALUES (performance: resolved once at file load)
-- =====================================================================

local VALID_TYPES = { mount = true, pet = true, toy = true, illusion = true }
local RECENT_KILL_TTL = 15       -- seconds to keep CLEU kills in recentKills
-- NOTE: Encounter kills (isEncounter=true) never expire by TTL.
-- They persist until loot is processed or the player leaves the instance.
-- This handles arbitrarily long RP phases, cinematics, and AFK between kill and loot.
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
local isFishing = false      -- set on fishing cast, cleared on LOOT_CLOSED or safety timer
local fishingResetTimer = nil -- safety timer: auto-reset isFishing after 30s (handles cancelled casts)
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

    -- Create synthetic kill entries for all NPCs in this encounter.
    -- Include npcID in the GUID to avoid dedup collisions when multiple NPCs
    -- in the same encounter have drops (GetTime() returns the same value within a frame).
    local now = GetTime()
    for i = 1, #npcIDs do
        local npcID = npcIDs[i]
        if npcDropDB[npcID] then
            local syntheticGUID = "Encounter-" .. encounterID .. "-" .. npcID .. "-" .. now
            recentKills[syntheticGUID] = {
                npcID = npcID,
                name = encounterName or "Boss",
                time = now,
                isEncounter = true,  -- Flag: use ENCOUNTER_KILL_TTL (bosses have long RP/cinematic phases)
            }
        end
    end
end

-- =====================================================================
-- INSTANCE ENTRY NOTIFICATION (Midnight: tooltip can't show drops inside)
-- When a player enters a dungeon or raid, print collectible drops to chat
-- so they know which bosses drop mounts/pets/toys before engaging.
-- Uses Encounter Journal API:
--   EJ_GetCurrentInstance() → journalInstanceID for player's location
--   EJ_GetEncounterInfoByIndex(idx) → iterates encounters in that instance
--     7th return (dungeonEncounterID) matches our encounterDB keys
-- =====================================================================

-- Track the last instance we notified for (avoid spam on /reload inside same instance)
local lastNotifiedInstanceID = nil

---PLAYER_ENTERING_WORLD handler (detect instance entry and print collectible drops)
function WarbandNexus:OnTryCounterInstanceEntry(event, isInitialLogin, isReloadingUi)
    if not IsAutoTryCounterEnabled() then return end

    local inInstance, instanceType = IsInInstance()
    if not inInstance then
        lastNotifiedInstanceID = nil
        -- Clean up encounter kills when leaving instance (they persist until this point)
        for guid, data in pairs(recentKills) do
            if data.isEncounter then
                recentKills[guid] = nil
            end
        end
        return
    end

    -- Only notify for dungeons and raids (not arenas, pvp, scenarios)
    if instanceType ~= "party" and instanceType ~= "raid" then return end

    -- Get instance ID to avoid re-notifying on /reload inside same instance
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if not instanceID or instanceID == lastNotifiedInstanceID then return end
    lastNotifiedInstanceID = instanceID

    -- Delay to let the instance fully load and avoid combat lockdown issues
    C_Timer.After(3, function()
        local WN = WarbandNexus
        if not WN or not WN.Print then return end

        -- Ensure Encounter Journal addon is loaded (required for EJ_* APIs)
        if not InCombatLockdown() then
            if C_AddOns and C_AddOns.LoadAddOn then
                pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
            elseif LoadAddOn then
                pcall(LoadAddOn, "Blizzard_EncounterJournal")
            end
        end

        -- Get the Encounter Journal instance for player's current location
        if not EJ_GetCurrentInstance then return end
        local journalInstanceID = EJ_GetCurrentInstance()
        if not journalInstanceID or journalInstanceID == 0 then return end

        -- Select the instance in EJ (required before EJ_GetEncounterInfoByIndex works)
        if not EJ_SelectInstance or not EJ_GetEncounterInfoByIndex then return end
        EJ_SelectInstance(journalInstanceID)

        -- Iterate all encounters in this instance and cross-reference with our encounterDB
        local dropsToShow = {} -- { { bossName, drops = { {type, itemID, name}, ... } }, ... }
        local idx = 1
        while true do
            -- Returns: name, desc, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID, instanceID
            local encName, _, _, _, _, _, dungeonEncID = EJ_GetEncounterInfoByIndex(idx)
            if not encName then break end

            -- Our encounterDB is keyed by DungeonEncounterID (from ENCOUNTER_END event)
            local npcIDs = dungeonEncID and encounterDB[dungeonEncID]
            if npcIDs then
                local encounterDrops = {}
                local seenItems = {}
                for _, npcID in ipairs(npcIDs) do
                    local npcDrops = npcDropDB[npcID]
                    if npcDrops then
                        for j = 1, #npcDrops do
                            local drop = npcDrops[j]
                            if not seenItems[drop.itemID] then
                                seenItems[drop.itemID] = true
                                encounterDrops[#encounterDrops + 1] = drop
                            end
                        end
                    end
                end
                if #encounterDrops > 0 then
                    dropsToShow[#dropsToShow + 1] = {
                        bossName = encName,
                        drops = encounterDrops,
                    }
                end
            end
            idx = idx + 1
        end

        -- Nothing to show? Bail.
        if #dropsToShow == 0 then return end

        -- Pre-request item data so hyperlinks resolve (C_Item caches are async)
        for _, entry in ipairs(dropsToShow) do
            for _, drop in ipairs(entry.drops) do
                if C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, drop.itemID)
                end
            end
        end

        -- Small extra delay for item data to cache, then print
        C_Timer.After(1, function()
            if not WN or not WN.Print then return end

            WN:Print("|cff9370DB[WN-Drops]|r Collectible drops in this instance:")

            local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo

            for _, entry in ipairs(dropsToShow) do
                for _, drop in ipairs(entry.drops) do
                    -- Get item hyperlink (quality-colored, bracketed)
                    local _, itemLink
                    if GetItemInfo then
                        _, itemLink = GetItemInfo(drop.itemID)
                    end
                    if not itemLink then
                        itemLink = "|cffff8000[" .. (drop.name or "Unknown") .. "]|r"
                    end

                    -- Check collection status (these APIs work outside combat)
                    local collected = false
                    if drop.type == "mount" then
                        if C_MountJournal and C_MountJournal.GetMountFromItem then
                            local mountID = C_MountJournal.GetMountFromItem(drop.itemID)
                            if mountID and not (issecretvalue and issecretvalue(mountID)) then
                                local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(mountID)
                                if not (issecretvalue and isCollected and issecretvalue(isCollected)) then
                                    collected = isCollected == true
                                end
                            end
                        end
                    elseif drop.type == "pet" then
                        if C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                            local speciesID = C_PetJournal.GetPetInfoByItemID(drop.itemID)
                            if speciesID and not (issecretvalue and issecretvalue(speciesID)) then
                                local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
                                if not (issecretvalue and numCollected and issecretvalue(numCollected)) then
                                    collected = numCollected and numCollected > 0
                                end
                            end
                        end
                    elseif drop.type == "toy" then
                        if PlayerHasToy then
                            local hasToy = PlayerHasToy(drop.itemID)
                            if not (issecretvalue and hasToy and issecretvalue(hasToy)) then
                                collected = hasToy == true
                            end
                        end
                    end

                    -- Build status text
                    local status
                    if collected then
                        status = "|cff00ff00(Collected)|r"
                    else
                        -- Show try count (check itemID key - most reliable for chat display)
                        local tryCount = 0
                        if WN.GetTryCount then
                            tryCount = WN:GetTryCount(drop.type, drop.itemID) or 0
                        end
                        if tryCount > 0 then
                            status = "|cffffff00(" .. tryCount .. " attempts)|r"
                        else
                            local typeLabels = { mount = "Mount", pet = "Pet", toy = "Toy" }
                            status = "|cff888888(" .. (typeLabels[drop.type] or "") .. ")|r"
                        end
                    end

                    WN:Print("  " .. entry.bossName .. ": " .. itemLink .. " " .. status)
                end
            end
        end)
    end)
end

---UNIT_SPELLCAST_SENT handler (detect fishing casts)
function WarbandNexus:OnTryCounterSpellcastSent(event, unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    if FISHING_SPELLS[spellID] then
        isFishing = true
        -- Safety timer: if the cast is cancelled/interrupted and LOOT_CLOSED never fires,
        -- auto-reset after 30 seconds (max fishing channel duration) to prevent the next
        -- NPC loot from being misrouted to ProcessFishingLoot().
        if fishingResetTimer then fishingResetTimer:Cancel() end
        fishingResetTimer = C_Timer.NewTimer(30, function()
            isFishing = false
            fishingResetTimer = nil
        end)
    end
end

---LOOT_CLOSED handler (reset fishing flag and safety timer)
function WarbandNexus:OnTryCounterLootClosed()
    isFishing = false
    lastContainerItemID = nil
    if fishingResetTimer then
        fishingResetTimer:Cancel()
        fishingResetTimer = nil
    end
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
            -- Encounter kills never expire by TTL (RP phases, cinematics, AFK are unbounded)
            -- CLEU kills expire after RECENT_KILL_TTL seconds
            local alive = killData.isEncounter or (now - killData.time < RECENT_KILL_TTL)
            if alive then
                if killData.zoneMapID then
                    drops = zoneDropDB[killData.zoneMapID]
                else
                    drops = npcDropDB[killData.npcID]
                end
                if drops then
                    dedupGUID = guid
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
-- KEY RECONCILIATION (fix itemID→nativeID mismatch on obtain)
-- =====================================================================

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
    -- Toys always use itemID for both storage and lookup — no mismatch possible
    if data.type == "toy" then return end
    if not EnsureDB() then return end

    local nativeID = data.id
    local typeTable = WarbandNexus.db.global.tryCounts[data.type]
    if not typeTable then return end

    -- If we already have a count under the native ID, no migration needed
    local existing = typeTable[nativeID]
    if existing and type(existing) == "number" and existing > 0 then return end

    -- Search CollectibleSourceDB for any drop entries matching this type
    -- where the itemID was used as a fallback key in the try count table.
    --
    -- IMPORTANT: Only include sources whose values are drop-entry arrays.
    -- encounterDB has a DIFFERENT format: [encounterID] = { npcID1, npcID2 }
    --   → indexing a number crashes ("attempt to index a number value")
    -- containerDropDB uses nested format: [id] = { drops = { {...} } }
    --   → handled separately below
    local flatSources = {
        npcDropDB, objectDropDB, fishingDropDB, zoneDropDB,
    }

    -- Helper: check a single drop entry for fallback key migration
    local function TryMigrateDrop(drop)
        if not drop or type(drop) ~= "table" then return false end
        if drop.type ~= data.type or not drop.itemID then return false end
        local fallbackCount = typeTable[drop.itemID]
        if not fallbackCount or type(fallbackCount) ~= "number" or fallbackCount <= 0 then return false end
        -- Verify this itemID actually resolves to our nativeID
        -- (the API should work now since the player just obtained it)
        local resolvedID = ResolveCollectibleID(drop)
        if resolvedID ~= nativeID then return false end
        -- Migrate: move count from itemID key to nativeID key
        typeTable[nativeID] = fallbackCount
        typeTable[drop.itemID] = nil
        ns.DebugPrint(format(
            "|cff9370DB[TryCounter]|r Reconciled %s key: itemID %d → nativeID %d (%d attempts)",
            data.type, drop.itemID, nativeID, fallbackCount))
        return true
    end

    -- Check flat sources: [key] = { { type, itemID, name }, ... }
    for _, sourceTable in pairs(flatSources) do
        for _, drops in pairs(sourceTable) do
            if type(drops) == "table" then
                for _, drop in ipairs(drops) do
                    if TryMigrateDrop(drop) then return end
                end
            end
        end
    end

    -- Check containerDropDB separately: [containerID] = { drops = { {...}, ... } }
    for _, containerData in pairs(containerDropDB) do
        if type(containerData) == "table" then
            local drops = containerData.drops or containerData
            if type(drops) == "table" then
                for _, drop in ipairs(drops) do
                    if TryMigrateDrop(drop) then return end
                end
            end
        end
    end
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
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnTryCounterInstanceEntry")
    self:RegisterEvent("UNIT_SPELLCAST_SENT", "OnTryCounterSpellcastSent")

    -- Listen for collectible obtained → reconcile itemID fallback keys to native IDs
    -- so NotificationManager reads the correct try count in its toast
    if self.RegisterMessage then
        self:RegisterMessage("WN_COLLECTIBLE_OBTAINED", "OnTryCounterCollectibleObtained")
    end

    -- Periodic cleanup of stale GUIDs and kills (every 60s, batched)
    C_Timer.NewTicker(CLEANUP_INTERVAL, function()
        local now = GetTime()
        for guid, time in pairs(processedGUIDs) do
            if now - time > PROCESSED_GUID_TTL then
                processedGUIDs[guid] = nil
            end
        end
        for guid, data in pairs(recentKills) do
            -- Encounter kills persist until instance exit (cleaned by OnTryCounterInstanceEntry)
            -- CLEU kills expire after RECENT_KILL_TTL
            if not data.isEncounter and now - data.time > RECENT_KILL_TTL then
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
-- SIMULATION (for /wn testtrycounter - exercises the REAL code path)
-- =====================================================================

---Simulate a full try counter cycle for a given NPC ID.
---Exercises the real code path: recentKills inject → IsCollectibleCollected → 
---ScanLootForItems (empty = miss) → ProcessMissedDrops → IncrementTryCount
---@param npcID number The NPC ID to simulate killing
---@return table results { success, drops, missed, skippedCollected, messages }
local function SimulateNPCKill(npcID)
    local results = {
        success = false,
        npcID = npcID,
        drops = {},
        missed = {},
        skippedCollected = {},
        messages = {},
    }

    -- Step 1: Check if NPC is in database
    local drops = npcDropDB[npcID]
    if not drops then
        results.messages[#results.messages + 1] = "|cffff0000NPC " .. npcID .. " not found in drop database|r"
        return results
    end
    results.drops = drops
    results.messages[#results.messages + 1] = format("Found %d drop(s) for NPC %d", #drops, npcID)

    -- Step 2: Inject synthetic kill into recentKills (simulates CLEU UNIT_DIED)
    local syntheticGUID = "Creature-0-0-0-0-" .. npcID .. "-0000TEST"
    recentKills[syntheticGUID] = {
        npcID = npcID,
        name = "SimTest-" .. npcID,
        time = GetTime(),
    }
    results.messages[#results.messages + 1] = "Injected kill into recentKills"

    -- Step 3: Filter to uncollected drops (same as ProcessNPCLoot)
    local uncollected = {}
    for i = 1, #drops do
        local drop = drops[i]
        local collected = IsCollectibleCollected(drop)
        if collected then
            results.skippedCollected[#results.skippedCollected + 1] = drop
            results.messages[#results.messages + 1] = format(
                "  |cff00ff00SKIP|r [%s] %s (itemID=%d) - already collected",
                drop.type, drop.name or "?", drop.itemID)
        else
            uncollected[#uncollected + 1] = drop
            results.messages[#results.messages + 1] = format(
                "  |cffffcc00TRACK|r [%s] %s (itemID=%d) - not collected",
                drop.type, drop.name or "?", drop.itemID)
        end
    end

    if #uncollected == 0 then
        results.messages[#results.messages + 1] = "|cff00ff00All drops already collected - nothing to count|r"
        -- Clean up synthetic kill
        recentKills[syntheticGUID] = nil
        results.success = true
        return results
    end

    -- Step 4: Simulate "miss" - loot window is not open, so all items are missed
    -- (In real gameplay, ScanLootForItems would check the actual loot window)
    results.messages[#results.messages + 1] = "Simulating MISS (no loot window = all items missed)"

    -- Step 5: Process missed drops (same as ProcessMissedDrops - real code path)
    if not EnsureDB() then
        results.messages[#results.messages + 1] = "|cffff0000EnsureDB failed - cannot save try counts|r"
        recentKills[syntheticGUID] = nil
        return results
    end

    for i = 1, #uncollected do
        local drop = uncollected[i]
        local tryKey = GetTryCountKey(drop)
        if tryKey then
            local newCount = WarbandNexus:IncrementTryCount(drop.type, tryKey)
            results.missed[#results.missed + 1] = {
                drop = drop,
                tryKey = tryKey,
                newCount = newCount,
            }

            local collectibleID = ResolveCollectibleID(drop)
            local keySource = collectibleID and "API" or "itemID-fallback"

            results.messages[#results.messages + 1] = format(
                "  |cff9370DB+1|r [%s] %s → %d attempts (key=%d via %s)%s",
                drop.type, drop.name or "?", newCount, tryKey, keySource,
                drop.guaranteed and " |cffaaaaaaGUARANTEED|r" or "")
        else
            results.messages[#results.messages + 1] = format(
                "  |cffff0000FAIL|r [%s] %s - could not determine try count key",
                drop.type, drop.name or "?")
        end
    end

    -- Clean up synthetic kill
    recentKills[syntheticGUID] = nil

    results.success = true
    return results
end

-- =====================================================================
-- NAMESPACE EXPORT
-- =====================================================================

ns.TryCounterService = {
    GetTryCount = function(_, ct, id) return WarbandNexus:GetTryCount(ct, id) end,
    SetTryCount = function(_, ct, id, c) return WarbandNexus:SetTryCount(ct, id, c) end,
    IncrementTryCount = function(_, ct, id) return WarbandNexus:IncrementTryCount(ct, id) end,
    SimulateNPCKill = function(_, npcID) return SimulateNPCKill(npcID) end,
}
