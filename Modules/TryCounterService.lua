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
local C_Container = C_Container
local InCombatLockdown = InCombatLockdown
local C_QuestLog = C_QuestLog

-- Midnight 12.0: Secret Values API (nil on pre-12.0 clients, backward-compatible)
-- Secret values are returned by combat APIs during instanced combat.
-- Tainted code cannot compare, do arithmetic, use as table keys, or string-operate on them.
-- issecretvalue(v) returns true if v is a secret value that cannot be operated on.
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

-- =====================================================================
-- RAW EVENT FRAME
-- COMBAT_LOG_EVENT_UNFILTERED removed: Blizzard marks it HasRestrictions,
-- causing ADDON_ACTION_FORBIDDEN on RegisterEvent() in protected states.
-- Open-world kill detection uses target-based lookup in ProcessNPCLoot()
-- (UnitGUID("target") → npcDropDB). Instance bosses use ENCOUNTER_END.
-- Only edge case lost: player changes target between kill and loot open.
-- =====================================================================
local tryCounterReady = false
local tryCounterEventsRegistered = false
local tryCounterFrame = CreateFrame("Frame")

local TRYCOUNTER_EVENTS = {
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "ENCOUNTER_END",
    "PLAYER_ENTERING_WORLD",
    "UNIT_SPELLCAST_SENT",
    "ITEM_LOCK_CHANGED",
}

local function RegisterTryCounterEvents()
    if tryCounterEventsRegistered then return end
    if InCombatLockdown() then return end
    for i = 1, #TRYCOUNTER_EVENTS do
        tryCounterFrame:RegisterEvent(TRYCOUNTER_EVENTS[i])
    end
    tryCounterEventsRegistered = true
end

tryCounterFrame:SetScript("OnUpdate", function(self)
    if InCombatLockdown() then return end
    RegisterTryCounterEvents()
    self:SetScript("OnUpdate", nil)
end)

tryCounterFrame:SetScript("OnEvent", function(_, event, ...)
    if not tryCounterReady then return end
    local addon = WarbandNexus
    if not addon then return end
    if event == "LOOT_OPENED" then
        addon:OnTryCounterLootOpened(event, ...)
    elseif event == "LOOT_CLOSED" then
        addon:OnTryCounterLootClosed()
    elseif event == "ENCOUNTER_END" then
        addon:OnTryCounterEncounterEnd(event, ...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        addon:OnTryCounterInstanceEntry(event, ...)
    elseif event == "UNIT_SPELLCAST_SENT" then
        addon:OnTryCounterSpellcastSent(event, ...)
    elseif event == "ITEM_LOCK_CHANGED" then
        addon:OnTryCounterItemLockChanged(event, ...)
    end
end)

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
local lockoutQuestsDB = {}  -- [npcID] = questID or { questID1, questID2, ... }

-- Runtime state
local recentKills = {}       -- [guid] = { npcID = n, name = s, time = t }
local processedGUIDs = {}    -- [guid] = timestamp
local isFishing = false      -- set on fishing cast, cleared on LOOT_CLOSED or safety timer
local fishingResetTimer = nil -- safety timer: auto-reset isFishing after 30s (handles cancelled casts)
local lastContainerItemID = nil  -- set on container use
local resolvedIDs = {}       -- [itemID] = { type, collectibleID } - runtime resolved mount/pet IDs
local lockoutAttempted = {}  -- [questID] = true : tracks which lockout quests we've already counted this reset period
                             -- Keyed by questID (not npcID) so multiple NPCs sharing the same quest
                             -- (e.g. Arachnoid Harvester 154342/151934 both use quest 55512) are handled correctly.

-- =====================================================================
-- REVERSE LOOKUP INDICES (built once at InitializeTryCounter, O(1) lookups)
-- Keys: [type .. "\0" .. itemID] = true
-- These replace the old O(N) full-DB-scan approach in Is*Collectible().
-- =====================================================================
local guaranteedIndex = {}    -- drop.guaranteed == true
local repeatableIndex = {}    -- drop.repeatable == true
local dropSourceIndex = {}    -- any drop entry (exists in DB at all)
local reverseIndicesBuilt = false

-- =====================================================================
-- REVERSE INDEX BUILDER
-- Called once from InitializeTryCounter after DB references are loaded.
-- Iterates all drop sources once, building O(1) lookup tables keyed by
-- type+itemID. This eliminates the O(N) full-DB scans that previously
-- ran on every cache-miss call to Is*Collectible().
-- =====================================================================

---Index a single drop entry into the reverse lookup tables
---@param drop table { type, itemID, name [, guaranteed] [, repeatable] }
local function IndexDrop(drop)
    if not drop or not drop.type or not drop.itemID then return end

    local itemKey = drop.type .. "\0" .. tostring(drop.itemID)

    -- Every entry in the DB is a drop source
    dropSourceIndex[itemKey] = true

    if drop.guaranteed then
        guaranteedIndex[itemKey] = true
    end
    if drop.repeatable then
        repeatableIndex[itemKey] = true
    end
end

---Index all drops from a flat array
---@param drops table|nil Array of drop entries
local function IndexDropArray(drops)
    if not drops then return end
    for i = 1, #drops do
        IndexDrop(drops[i])
    end
end

---Build all reverse lookup indices from the loaded CollectibleSourceDB.
---Called once from InitializeTryCounter. After this, Is*Collectible()
---uses O(1) hash lookups instead of full-DB scans.
local function BuildReverseIndices()
    if reverseIndicesBuilt then return end

    -- Flat sources: [key] = { { type, itemID, name }, ... }
    for _, drops in pairs(npcDropDB) do IndexDropArray(drops) end
    for _, drops in pairs(objectDropDB) do IndexDropArray(drops) end
    for _, drops in pairs(fishingDropDB) do IndexDropArray(drops) end
    for _, drops in pairs(zoneDropDB) do IndexDropArray(drops) end

    -- Container source: [containerID] = { drops = { {...}, ... } } or direct array
    for _, containerData in pairs(containerDropDB) do
        local list = containerData.drops or containerData
        if type(list) == "table" then
            -- Handle both { drops = { ... } } and direct array formats
            local arr = list.drops or list
            if type(arr) == "table" then
                IndexDropArray(arr)
            end
        end
    end

    -- Encounter source: [encounterID] = { npcID1, npcID2, ... }
    -- These are already covered by npcDropDB above (encounters map to NPC IDs
    -- whose drops are in npcDropDB), so no extra indexing needed here.

    reverseIndicesBuilt = true
end

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

---Reset try count to 0 for a repeatable collectible (BoE/farmable mounts).
---Called when a repeatable mount is obtained so the counter restarts for the next farm session.
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
function WarbandNexus:ResetTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return end
    if not EnsureDB() then return end
    WarbandNexus.db.global.tryCounts[collectibleType][id] = 0
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
-- PUBLIC QUERY API (O(1) index lookups, replaces old O(N) full-DB scans)
-- =====================================================================
-- After InitializeTryCounter builds the reverse indices, these functions
-- do a simple hash table lookup instead of iterating the entire DB.
-- For non-toy types, we also check the native collectible ID (mountID/speciesID)
-- via ResolveCollectibleID, since the index is keyed by itemID but callers
-- may pass a mountID. A lightweight session cache avoids redundant API calls.

-- Session caches: "type\0id" -> boolean (populated on first query)
local guaranteedCache = {}
local repeatableCache = {}
local dropSourceCache = {}

---Lookup helper: check index for both the raw id (may be mountID/speciesID)
---and resolved itemIDs. Uses a session cache to avoid repeat lookups.
---@param index table The reverse index to query (guaranteedIndex/repeatableIndex/dropSourceIndex)
---@param cache table The session cache for this query type
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number collectibleID (mountID/speciesID) or itemID for toys
---@return boolean
local function IndexLookup(index, cache, collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return false end

    local cacheKey = collectibleType .. "\0" .. tostring(id)
    local cached = cache[cacheKey]
    if cached ~= nil then return cached end

    -- Direct lookup: id might already be an itemID (toys, or fallback storage)
    local key = collectibleType .. "\0" .. tostring(id)
    if index[key] then
        cache[cacheKey] = true
        return true
    end

    -- For non-toy types, the caller may pass a native collectibleID (mountID/speciesID)
    -- but the index is keyed by itemID. We need to check if any itemID resolves to this id.
    -- Since resolvedIDs maps itemID -> collectibleID, we can check the reverse.
    -- However, we can't reverse-iterate resolvedIDs efficiently.
    -- Instead, rely on the session cache: once a drop has been processed (via ProcessNPCLoot etc.),
    -- ResolveCollectibleID populates resolvedIDs. We check all resolved entries.
    if collectibleType ~= "toy" then
        for itemID, resolvedID in pairs(resolvedIDs) do
            if resolvedID == id then
                local altKey = collectibleType .. "\0" .. tostring(itemID)
                if index[altKey] then
                    cache[cacheKey] = true
                    return true
                end
            end
        end
    end

    cache[cacheKey] = false
    return false
end

---Check if a collectible (type, id) is from a 100% guaranteed drop source.
---Used to hide try count in UI for guaranteed drops.
---O(1) index lookup (built at InitializeTryCounter time).
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number collectibleID (mountID/speciesID) or itemID for toys
---@return boolean
function WarbandNexus:IsGuaranteedCollectible(collectibleType, id)
    return IndexLookup(guaranteedIndex, guaranteedCache, collectibleType, id)
end

---Check if a collectible (type, id) is from a repeatable (BoE/farmable) drop source.
---Used to show "X attempts" instead of "Collected" and to reset try count on obtain.
---O(1) index lookup (built at InitializeTryCounter time).
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number collectibleID (mountID/speciesID) or itemID for toys
---@return boolean
function WarbandNexus:IsRepeatableCollectible(collectibleType, id)
    return IndexLookup(repeatableIndex, repeatableCache, collectibleType, id)
end

---Check if a collectible (type, id) exists in the drop source database at all.
---Returns true only for collectibles obtainable from NPC kills, objects, fishing,
---containers, or zone drops. Returns false for achievement, vendor, quest sources.
---O(1) index lookup (built at InitializeTryCounter time).
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number collectibleID (mountID/speciesID) or itemID for toys
---@return boolean
function WarbandNexus:IsDropSourceCollectible(collectibleType, id)
    return IndexLookup(dropSourceIndex, dropSourceCache, collectibleType, id)
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

---Increment try count and print chat message for unfound drops.
---Skips 100% (guaranteed) drops: no increment, no chat message.
---@param drops table Array of drop entries that were NOT found in loot
local function ProcessMissedDrops(drops)
    if not drops or #drops == 0 then return end
    if not EnsureDB() then return end

    for i = 1, #drops do
        local drop = drops[i]
        if not drop.guaranteed then
            local tryKey = GetTryCountKey(drop)
            if tryKey then
                local newCount = WarbandNexus:IncrementTryCount(drop.type, tryKey)
                if WarbandNexus.Print then
                    WarbandNexus:Print(format("|cff9370DB[WN-Counter]|r : %d attempts for |cffff8000%s|r", newCount, drop.name or "Unknown"))
                end
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
-- LOCKOUT QUEST CHECK (daily/weekly rare kill gating)
-- =====================================================================

---Check if an NPC's lockout quest indicates a duplicate kill (no loot possible).
---Returns true if the try counter should SKIP this NPC (already attempted this period).
---
---Timing: When LOOT_OPENED fires, the tracking quest is already flagged completed
---from the current kill. We use lockoutAttempted[questID] to distinguish:
---  1. Quest NOT flagged → quest reset happened → clear tracker → allow (return false)
---  2. Quest flagged AND lockoutAttempted is set → duplicate kill → skip (return true)
---  3. Quest flagged AND lockoutAttempted NOT set → first kill → mark → allow (return false)
---
---Keyed by questID so multiple NPCs sharing the same quest are handled correctly.
---(e.g. Arachnoid Harvester uses NPC IDs 154342/151934, both map to quest 55512)
---
---@param npcID number The NPC ID to check
---@return boolean shouldSkip true if this kill should NOT be counted
local function IsLockoutDuplicate(npcID)
    if not npcID then return false end

    local questData = lockoutQuestsDB[npcID]
    if not questData then return false end  -- No lockout quest registered for this NPC

    -- Normalize to array
    local questIDs = type(questData) == "table" and questData or { questData }

    -- Check if ANY of the lockout quests are flagged completed
    local flaggedQuestID = nil
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        for i = 1, #questIDs do
            if C_QuestLog.IsQuestFlaggedCompleted(questIDs[i]) then
                flaggedQuestID = questIDs[i]
                break
            end
        end
    end

    if not flaggedQuestID then
        -- No quest flagged → lockout has reset since last attempt
        -- Clear all related quest trackers
        for i = 1, #questIDs do
            lockoutAttempted[questIDs[i]] = nil
        end
        return false  -- Allow counting
    end

    -- Quest IS flagged. Did THIS kill flag it, or was it already flagged?
    if lockoutAttempted[flaggedQuestID] then
        -- We already counted one attempt for this lockout period → skip
        return true
    end

    -- First time seeing this quest flagged → THIS kill triggered it → count it
    lockoutAttempted[flaggedQuestID] = true
    return false  -- Allow counting
end

---Sync lockout state with server quest flags on login/reload.
---Two-phase operation:
---  1. Clean stale entries: remove lockoutAttempted quest IDs that are no longer flagged
---  2. Pre-populate: mark quest IDs that are already flagged (from prior session)
---This prevents false try count increments after /reload mid-farm-session.
---Without phase 2, a /reload would reset lockoutAttempted to empty, causing the next
---kill of an already-locked rare to be incorrectly counted as a "first attempt".
local function SyncLockoutState()
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end

    -- Phase 1: Clean stale entries (quest has reset since last session)
    for questID, _ in pairs(lockoutAttempted) do
        if not C_QuestLog.IsQuestFlaggedCompleted(questID) then
            lockoutAttempted[questID] = nil
        end
    end

    -- Phase 2: Pre-populate from currently flagged quests.
    -- If a lockout quest is already flagged on login/reload, the player used their
    -- attempt in a prior session. Mark it so IsLockoutDuplicate() correctly skips.
    for _, questData in pairs(lockoutQuestsDB) do
        local questIDs = type(questData) == "table" and questData or { questData }
        for i = 1, #questIDs do
            local qid = questIDs[i]
            if not lockoutAttempted[qid] and C_QuestLog.IsQuestFlaggedCompleted(qid) then
                lockoutAttempted[qid] = true
            end
        end
    end
end

-- =====================================================================
-- EVENT HANDLERS
-- =====================================================================

---ENCOUNTER_END handler for instanced bosses
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

    -- Delay to let the instance fully load and avoid combat lockdown issues.
    -- T+5s: deferred past the main InitializationService startup window (Stages 1-3
    -- complete by ~3s) to avoid competing for frame time during PLAYER_ENTERING_WORLD.
    C_Timer.After(5, function()
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
                        -- Show try count using consistent key (mountID/speciesID when available)
                        local tryCount = 0
                        if WN.GetTryCount then
                            local tryKey = GetTryCountKey(drop)
                            tryCount = WN:GetTryCount(drop.type, tryKey) or 0
                            -- Fallback: check raw itemID if native key returned 0
                            -- (handles edge case where count was stored under itemID before migration)
                            if tryCount == 0 and tryKey ~= drop.itemID then
                                tryCount = WN:GetTryCount(drop.type, drop.itemID) or 0
                            end
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

---ITEM_LOCK_CHANGED handler (detect container item usage for try count tracking)
---When a container item from our DB changes lock state, record its itemID so
---ProcessContainerLoot() knows which container was opened.
---@param event string
---@param bagID number Bag index (0-4 for bags, -1 for bank, etc.)
---@param slotID number|nil Slot index within the bag. nil = equipment slot change.
function WarbandNexus:OnTryCounterItemLockChanged(event, bagID, slotID)
    -- Equipment slot changes have nil slotID - skip
    if not bagID or not slotID then return end

    -- Only check player bags (0-4), not bank or other containers
    if bagID < 0 or bagID > 4 then return end

    -- Check if C_Container is available
    if not C_Container or not C_Container.GetContainerItemID then return end

    -- Get the item in this slot
    local itemID = C_Container.GetContainerItemID(bagID, slotID)
    if not itemID then return end

    -- Check if this item is a known container in our DB
    if not containerDropDB[itemID] then return end

    -- Record the container item. We intentionally do NOT check isLocked here:
    -- some containers (especially holiday boxes like Heart-Shaped Box) are consumed
    -- so quickly that the isLocked state is never captured by the time this handler
    -- runs. Since lastContainerItemID is consumed immediately in ProcessContainerLoot
    -- and cleared in OnTryCounterLootClosed, false positives from bag moves are harmless.
    lastContainerItemID = itemID
end

---LOOT_OPENED handler (CENTRAL ROUTER - dispatches to correct processing path)
---@param event string
---@param autoLoot boolean
---@param isFromItem boolean Added in 8.3.0, true if loot is from opening a container item
function WarbandNexus:OnTryCounterLootOpened(event, autoLoot, isFromItem)
    if not IsAutoTryCounterEnabled() then return end

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

---Safely get a GUID string, guarding against Midnight 12.0 secret values.
---@param rawGUID any A potentially secret GUID value
---@return string|nil guid Safe GUID string or nil
local function SafeGuardGUID(rawGUID)
    if not rawGUID then return nil end
    if issecretvalue then
        if issecretvalue(rawGUID) then return nil end
    else
        local ok = pcall(string.len, rawGUID)
        if not ok then return nil end
    end
    return rawGUID
end

---Try to get the loot source GUID from the loot window.
---Uses GetLootSourceInfo(slotIndex) which returns the GUID of the entity
---that provided the loot (creature, game object, etc.).
---Falls back to UnitGUID("npc") which is set during object interaction.
---@return string|nil guid Safe GUID string or nil
local function GetLootSourceGUID()
    -- Method 1: GetLootSourceInfo (most reliable for objects/chests)
    if GetLootSourceInfo then
        local numItems = GetNumLootItems()
        for i = 1, numItems or 0 do
            local ok, sourceGUID = pcall(GetLootSourceInfo, i)
            if ok and sourceGUID then
                local safeGUID = SafeGuardGUID(sourceGUID)
                if safeGUID then return safeGUID end
            end
        end
    end

    -- Method 2: UnitGUID("npc") - set during some NPC/object interactions
    local ok, npcGUID = pcall(UnitGUID, "npc")
    if ok and npcGUID then
        local safeGUID = SafeGuardGUID(npcGUID)
        if safeGUID then return safeGUID end
    end

    return nil
end

---Process loot from NPC corpse or game object
function WarbandNexus:ProcessNPCLoot()
    -- SafeGetTargetGUID already filters secret values via issecretvalue
    local targetGUID = SafeGetTargetGUID()

    local drops = nil
    local dedupGUID = nil
    -- Track whether we got ANY valid GUID for the loot source.
    -- If a GUID exists but isn't in our DB, the source is identified and simply not tracked.
    -- The recentKills fallback should ONLY run when no GUID was available at all
    -- (e.g. Midnight 12.0 secret values), otherwise trash NPC loot can be mis-attributed
    -- to a previously killed boss whose encounter entry persists in recentKills.
    local hasIdentifiedSource = false
    -- Track the matched npcID so we can clean up encounter entries after processing
    local matchedNpcID = nil

    if targetGUID then
        hasIdentifiedSource = true
        -- targetGUID is guaranteed non-secret by SafeGetTargetGUID, safe as table key
        if processedGUIDs[targetGUID] then return end

        -- Try NPC first (GetNPCIDFromGUID has its own secret guard)
        local npcID = GetNPCIDFromGUID(targetGUID)
        drops = npcID and npcDropDB[npcID]
        if drops then matchedNpcID = npcID end

        -- Try GameObject if not an NPC
        if not drops then
            local objectID = GetObjectIDFromGUID(targetGUID)
            drops = objectID and objectDropDB[objectID]
        end

        dedupGUID = targetGUID
    end

    -- If target didn't match, try loot source GUID (critical for world objects/chests)
    -- UnitGUID("target") doesn't work for GameObjects; GetLootSourceInfo does.
    if not drops then
        local sourceGUID = GetLootSourceGUID()
        if sourceGUID then
            hasIdentifiedSource = true
            if processedGUIDs[sourceGUID] then return end

            -- Try NPC from loot source
            local npcID = GetNPCIDFromGUID(sourceGUID)
            drops = npcID and npcDropDB[npcID]
            if drops then matchedNpcID = npcID end

            -- Try GameObject from loot source
            if not drops then
                local objectID = GetObjectIDFromGUID(sourceGUID)
                drops = objectID and objectDropDB[objectID]
            end

            if drops then
                dedupGUID = sourceGUID
            end
        end
    end

    -- Try zone-wide drops if neither NPC nor object matched
    if not drops and next(zoneDropDB) then
        local mapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        -- mapID is safe: C_Map returns player's own zone, not a combat-secret value
        if mapID then
            drops = zoneDropDB[mapID]
        end
    end

    -- Fallback: check recentKills for encounter/CLEU-tracked kills.
    -- ONLY used when no loot source GUID was available at all (both target and source
    -- returned nil, e.g. Midnight 12.0 secret values in instanced combat).
    -- If we had a valid GUID that wasn't in our DB, the source is known and not tracked —
    -- falling through would mis-attribute trash NPC loot to a prior boss encounter.
    if not drops and not hasIdentifiedSource then
        local now = GetTime()
        for guid, killData in pairs(recentKills) do
            -- Skip already-processed entries
            if not processedGUIDs[guid] then
                -- Encounter kills never expire by TTL (RP phases, cinematics, AFK are unbounded)
                -- CLEU kills expire after RECENT_KILL_TTL seconds
                local alive = killData.isEncounter or (now - killData.time < RECENT_KILL_TTL)
                if alive then
                    if killData.zoneMapID then
                        drops = zoneDropDB[killData.zoneMapID]
                    else
                        drops = npcDropDB[killData.npcID]
                        if drops then matchedNpcID = killData.npcID end
                    end
                    if drops then
                        dedupGUID = guid
                        break
                    end
                end
            end
        end
    end

    if not drops then return end

    -- Daily/weekly lockout check: if this NPC has a tracking quest and the player
    -- already used their attempt this reset period, skip try count increment.
    -- Must run BEFORE loot scanning to avoid false "missed drop" increments.
    -- matchedNpcID is set when drops came from npcDropDB (not objectDropDB/zoneDropDB).
    local isLockoutSkip = matchedNpcID and IsLockoutDuplicate(matchedNpcID)

    -- Filter drops: repeatable drops are always tracked (even if collected),
    -- non-repeatable drops only tracked if uncollected.
    local trackable = {}
    for i = 1, #drops do
        local drop = drops[i]
        if drop.repeatable then
            trackable[#trackable + 1] = drop
        elseif not IsCollectibleCollected(drop) then
            trackable[#trackable + 1] = drop
        end
    end
    if #trackable == 0 then return end -- All collected (and none repeatable), skip

    -- Scan loot window
    local found = ScanLootForItems(trackable)

    -- Mark GUIDs as processed (prevents re-counting on chest reopen)
    -- Record BOTH targetGUID and dedupGUID: when loot source (chest) differs
    -- from kill source (encounter), both must be marked to prevent duplicates.
    local now = GetTime()
    if dedupGUID then
        processedGUIDs[dedupGUID] = now
    end
    if targetGUID and targetGUID ~= dedupGUID then
        processedGUIDs[targetGUID] = now
    end

    -- Clean up encounter entries in recentKills for this NPC.
    -- When boss loot is processed (via targetGUID/sourceGUID or recentKills fallback),
    -- remove ALL encounter entries that share the same npcID. This prevents the
    -- recentKills fallback from ever re-using these entries for subsequent loot events.
    if matchedNpcID then
        for guid, killData in pairs(recentKills) do
            if killData.isEncounter and killData.npcID == matchedNpcID then
                recentKills[guid] = nil
            end
        end
    end

    -- Check for repeatable drops that were FOUND in loot -> reset their try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tryKey = GetTryCountKey(drop)
            if tryKey then
                WarbandNexus:ResetTryCount(drop.type, tryKey)
                if WarbandNexus.Print then
                    WarbandNexus:Print(format("|cff9370DB[WN-Counter]|r |cff00ff00Obtained|r |cffff8000%s|r! Try counter reset.", drop.name or "Unknown"))
                end
            end
        end
    end

    -- If lockout duplicate, skip try count increment entirely.
    -- GUID processing and encounter cleanup above still run (dedup must happen regardless),
    -- but we don't increment the try counter for a kill that can't drop the rare item.
    if isLockoutSkip then
        if WarbandNexus.Print then
            WarbandNexus:Print(format("|cff9370DB[WN-Counter]|r |cff888888Skipped|r: daily/weekly lockout active for this NPC."))
        end
        return
    end

    -- Find missed drops (not in loot)
    local missed = {}
    for i = 1, #trackable do
        if not found[trackable[i].itemID] then
            missed[#missed + 1] = trackable[i]
        end
    end

    -- Increment try counts for missed drops
    ProcessMissedDrops(missed)
end

---Process loot from fishing
---For repeatable fishing mounts: resets try count when mount is caught (found in loot).
---For non-repeatable: increments on every fish where mount is NOT caught.
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

    -- For repeatable fishing mounts, we track ALL drops (even collected ones)
    -- because the player may want to farm them again for AH sale.
    local trackable = {}
    for i = 1, #drops do
        local drop = drops[i]
        if drop.repeatable then
            -- Always track repeatable drops regardless of collection status
            trackable[#trackable + 1] = drop
        elseif not IsCollectibleCollected(drop) then
            -- Non-repeatable: only track uncollected
            trackable[#trackable + 1] = drop
        end
    end
    if #trackable == 0 then return end

    -- Scan loot window
    local found = ScanLootForItems(trackable)

    -- Check for repeatable mounts that were FOUND in loot -> reset their try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tryKey = GetTryCountKey(drop)
            if tryKey then
                WarbandNexus:ResetTryCount(drop.type, tryKey)
                if WarbandNexus.Print then
                    WarbandNexus:Print(format("|cff9370DB[WN-Counter]|r |cff00ff00Caught|r |cffff8000%s|r! Try counter reset.", drop.name or "Unknown"))
                end
            end
        end
    end

    -- Find missed drops (not in loot) -> increment try count
    local missed = {}
    for i = 1, #trackable do
        if not found[trackable[i].itemID] then
            missed[#missed + 1] = trackable[i]
        end
    end

    ProcessMissedDrops(missed)
end

---Process loot from container items (Paragon caches, Wriggling Pinnacle Cache, etc.)
---Uses lastContainerItemID (set by ITEM_LOCK_CHANGED) to determine which container
---was opened, enabling targeted try count increment on miss.
function WarbandNexus:ProcessContainerLoot()
    local containerItemID = lastContainerItemID
    lastContainerItemID = nil  -- Consume immediately to prevent stale data

    -- If we know which container was opened, do targeted detection
    if containerItemID and containerDropDB[containerItemID] then
        local containerData = containerDropDB[containerItemID]
        local drops = containerData.drops or containerData
        if not drops or type(drops) ~= "table" or #drops == 0 then return end

        -- Filter: repeatable = always track, non-repeatable = only uncollected
        local trackable = {}
        for i = 1, #drops do
            local drop = drops[i]
            if drop.repeatable then
                trackable[#trackable + 1] = drop
            elseif not IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        end
        if #trackable == 0 then return end

        -- Scan loot window
        local found = ScanLootForItems(trackable)

        -- Check for repeatable drops that were FOUND in loot -> reset their try count
        for i = 1, #trackable do
            local drop = trackable[i]
            if drop.repeatable and found[drop.itemID] then
                local tryKey = GetTryCountKey(drop)
                if tryKey then
                    WarbandNexus:ResetTryCount(drop.type, tryKey)
                    if WarbandNexus.Print then
                        WarbandNexus:Print(format("|cff9370DB[WN-Counter]|r |cff00ff00Obtained|r |cffff8000%s|r from container! Try counter reset.", drop.name or "Unknown"))
                    end
                end
            end
        end

        -- Process missed drops (increment try count)
        local missed = {}
        for i = 1, #trackable do
            if not found[trackable[i].itemID] then
                missed[#missed + 1] = trackable[i]
            end
        end

        ProcessMissedDrops(missed)
        return
    end

    -- Fallback: container not identified via ITEM_LOCK_CHANGED.
    -- Scan all container drops passively (no try count increment).
    -- This handles edge cases where ITEM_LOCK_CHANGED didn't fire or wasn't captured.
    local allContainerDrops = {}
    for _, containerData in pairs(containerDropDB) do
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

    -- Scan loot window (passive only - can't increment without knowing which container)
    ScanLootForItems(uncollected)
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
    if not EnsureDB() then return end

    -- Check if this is a repeatable collectible -> reset try count instead of freezing
    if WarbandNexus:IsRepeatableCollectible(data.type, data.id) then
        WarbandNexus:ResetTryCount(data.type, data.id)
        return
    end

    -- Toys always use itemID for both storage and lookup — no mismatch possible
    if data.type == "toy" then return end

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
        lockoutQuestsDB = db.lockoutQuests or {}
    end

    -- Build reverse lookup indices for O(1) Is*Collectible() queries.
    -- Must run AFTER DB references are loaded above.
    BuildReverseIndices()

    -- Sync lockout state with server quest flags (clean stale + pre-populate).
    -- Delayed 3s to ensure quest log data is fully available after login/reload.
    C_Timer.After(3, SyncLockoutState)

    -- Events are registered on a raw frame at file parse time (combat-safe).
    -- Flip the ready flag so the OnEvent handler starts dispatching.
    tryCounterReady = true

    -- WN_COLLECTIBLE_OBTAINED: Handled by unified dispatch in NotificationManager.
    -- Do NOT register here — AceEvent allows only one handler per event per object.
    -- The dispatch handler in NotificationManager calls OnTryCounterCollectibleObtained.

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

end

-- =====================================================================
-- NAMESPACE EXPORT
-- =====================================================================

ns.TryCounterService = {
    GetTryCount = function(_, ct, id) return WarbandNexus:GetTryCount(ct, id) end,
    SetTryCount = function(_, ct, id, c) return WarbandNexus:SetTryCount(ct, id, c) end,
    IncrementTryCount = function(_, ct, id) return WarbandNexus:IncrementTryCount(ct, id) end,
    ResetTryCount = function(_, ct, id) return WarbandNexus:ResetTryCount(ct, id) end,
    IsGuaranteedCollectible = function(_, ct, id) return WarbandNexus:IsGuaranteedCollectible(ct, id) end,
    IsRepeatableCollectible = function(_, ct, id) return WarbandNexus:IsRepeatableCollectible(ct, id) end,
    IsDropSourceCollectible = function(_, ct, id) return WarbandNexus:IsDropSourceCollectible(ct, id) end,
}
