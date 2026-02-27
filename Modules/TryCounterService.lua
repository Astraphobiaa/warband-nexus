--[[
    Warband Nexus - Try Counter Service
    Automatic try counter with multi-method detection:
      NPC/Boss kills, GameObjects, Fishing, Container items, Zone-wide drops
    
    DB: db.global.tryCounts[type][id] = count
    
    Detection flow:
      LOOT_OPENED → central router dispatches to correct processing path:
        Route 1: isFromItem → ProcessContainerLoot (container items)
        Route 2: isFishing → ProcessFishingLoot (fishing)
        Route 3: isPickpocketing → skip (Rogue pickpocket)
        Route 4: isBlockingInteractionOpen → skip (bank/vendor/AH/mail)
        Route 5: isProfessionLooting → skip (skinning/mining/herbing/DE/prospect/mill)
        Route 6: ProcessNPCLoot → AoE-aware multi-source GUID scanning → increment/skip
      ENCOUNTER_END → Midnight fallback for instanced bosses (time-bounded for GameObjects)
      PLAYER_ENTERING_WORLD → instance entry → print collectible drops to chat
      UNIT_SPELLCAST_SENT → fishing/pickpocket/profession flags
      PLAYER_INTERACTION_MANAGER → bank/vendor/AH/mail open/close tracking
    
    Key reconciliation:
      WN_COLLECTIBLE_OBTAINED → migrate itemID-fallback keys to nativeID
      (ensures NotificationManager reads correct try count in toast)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- =====================================================================
-- CONSTANTS & UPVALUES (performance: resolved once at file load)
-- =====================================================================

local VALID_TYPES = { mount = true, pet = true, toy = true, illusion = true, item = true }
local RECENT_KILL_TTL = 15       -- seconds to keep CLEU kills in recentKills
-- NOTE: Encounter kills (isEncounter=true) never expire by TTL.
-- They persist until loot is processed or the player leaves the instance.
-- This handles arbitrarily long RP phases, cinematics, and AFK between kill and loot.
local PROCESSED_GUID_TTL = 300   -- seconds before allowing same GUID again
local CLEANUP_INTERVAL = 60      -- seconds between cleanup ticks
local ENCOUNTER_OBJECT_TTL = 90  -- seconds: max time between boss kill and chest loot for encounter+GameObject match

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

-- Quest-item mounts (Stonevault/Mechagon style): populated by BuildReverseIndices; used by GetQuestStarterMountsForBrowser and GetTryCount fallback
local questStarterMountToSourceItemID = {}
local questStarterMountList = {}

---Send try counter / drops message to all chat panels that have Loot, Currency, or Reputation
---enabled (via ChatMessageService), so messages appear on every such tab and when switching panels.
---Falls back to WarbandNexus:Print if ChatMessageService not available.
---@param message string
local function TryChat(message)
    if ns.SendToChatFramesLootRepCurrency then
        ns.SendToChatFramesLootRepCurrency(message)
    elseif WarbandNexus and WarbandNexus.Print then
        WarbandNexus:Print(message)
    end
end

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
    "LOOT_SLOT_CHANGED",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_CURRENCY",
    "CHAT_MSG_MONEY",
    "ENCOUNTER_END",
    "PLAYER_ENTERING_WORLD",
    "UNIT_SPELLCAST_SENT",
    "ITEM_LOCK_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_TARGET_CHANGED",
}

-- PlayerInteractionType values that should block ProcessNPCLoot.
-- When any of these UI panels are open, LOOT_OPENED events are either:
--   a) Not from NPC loot (bank/vendor interactions)
--   b) From profession UI (tradeskill window opens loot frames for some crafts)
-- Blocks loot processing when non-NPC UI interactions are open.
-- Values from Enum.PlayerInteractionType (warcraft.wiki.gg/wiki/Enum.PlayerInteractionType)
local BLOCKING_INTERACTION_TYPES = {
    [1] = true,   -- TradePartner
    [5] = true,   -- Merchant
    [8] = true,   -- Banker
    [10] = true,  -- GuildBanker
    [17] = true,  -- MailInfo
    [21] = true,  -- Auctioneer
    [26] = true,  -- VoidStorageBanker
    [27] = true,  -- BlackMarketAuctioneer
    [31] = true,  -- GarrTradeskill (Garrison profession window)
    [40] = true,  -- ScrappingMachine
    [44] = true,  -- ItemInteraction (enchanting/crafting UI)
}

-- Register events in an untainted path. Frame:RegisterEvent() is protected;
-- calling it from OnUpdate or other deferred context yields ADDON_ACTION_FORBIDDEN.
local function RegisterTryCounterEvents()
    if tryCounterEventsRegistered then return true end
    local ok, err = pcall(function()
        for i = 1, #TRYCOUNTER_EVENTS do
            tryCounterFrame:RegisterEvent(TRYCOUNTER_EVENTS[i])
        end
        tryCounterEventsRegistered = true
    end)
    if not ok and err then
        if WarbandNexus and WarbandNexus.Debug then
            WarbandNexus:Debug("[TryCounter] RegisterEvent deferred: %s", tostring(err))
        end
        return false
    end
    return tryCounterEventsRegistered
end

-- Try at load (safe for normal login). If forbidden (e.g. /reload in combat), InitializeTryCounter will retry.
RegisterTryCounterEvents()

tryCounterFrame:SetScript("OnEvent", function(_, event, ...)
    local addon = WarbandNexus
    -- Log LOOT_OPENED as soon as event fires when loot debug is on (before tryCounterReady check)
    if event == "LOOT_OPENED" and addon and addon.db and addon.db.profile and addon.db.profile.debugTryCounterLoot then
        addon:Print("|cff9370DB[WN-TryCounter]|r LOOT_OPENED received (tryCounterReady=" .. tostring(tryCounterReady) .. ")")
    end
    if not tryCounterReady then return end
    if not addon then return end
    if event == "LOOT_OPENED" then
        addon:OnTryCounterLootOpened(event, ...)
    elseif event == "LOOT_CLOSED" then
        addon:OnTryCounterLootClosed()
    elseif event == "LOOT_SLOT_CHANGED" then
        addon:OnTryCounterLootSlotChanged(...)
    elseif event == "CHAT_MSG_LOOT" then
        addon:OnTryCounterChatMsgLoot(...)
    elseif event == "CHAT_MSG_CURRENCY" or event == "CHAT_MSG_MONEY" then
        addon:OnTryCounterChatMsgCurrency(...)
    elseif event == "ENCOUNTER_END" then
        addon:OnTryCounterEncounterEnd(event, ...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        addon:OnTryCounterInstanceEntry(event, ...)
    elseif event == "UNIT_SPELLCAST_SENT" then
        addon:OnTryCounterSpellcastSent(event, ...)
    elseif event == "ITEM_LOCK_CHANGED" then
        addon:OnTryCounterItemLockChanged(event, ...)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType and BLOCKING_INTERACTION_TYPES[interactionType] then
            isBlockingInteractionOpen = true
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if interactionType and BLOCKING_INTERACTION_TYPES[interactionType] then
            isBlockingInteractionOpen = false
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        local guid = SafeGetTargetGUID and SafeGetTargetGUID() or nil
        if guid then
            local nid = GetNPCIDFromGUID(guid)
            local oid = GetObjectIDFromGUID(guid)
            if (nid and npcDropDB[nid]) or (oid and objectDropDB[oid]) then
                lastLootSourceGUID = guid
                lastLootSourceTime = GetTime()
            end
        else
            lastLootSourceGUID = nil
        end
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

-- Pickpocket spell IDs (Rogue): opens loot window on a mob WITHOUT killing it.
-- LOOT_OPENED fires with isFromItem=false, isFishing=false → would fall through to
-- ProcessNPCLoot → sourceGUID matches a tracked NPC → false try counter increment.
-- Detection: set isPickpocketing flag on spell cast, skip ProcessNPCLoot, clear on LOOT_CLOSED.
local PICKPOCKET_SPELLS = {
    [921] = true,     -- Pick Pocket
}

-- Profession/gathering spell IDs that open a loot window on a corpse/node WITHOUT killing it.
-- These spells fire LOOT_OPENED, and the sourceGUID may be a tracked NPC (e.g., skinning a rare
-- corpse, mining a node near a boss chest). Without this guard, ProcessNPCLoot would run and
-- potentially match the sourceGUID against npcDropDB, causing a false try count increment.
-- Defense-in-depth: filters out profession-sourced loot events that share NPC GUIDs.
-- Flag set on UNIT_SPELLCAST_SENT, cleared on LOOT_CLOSED.
local PROFESSION_LOOT_SPELLS = {
    -- Skinning
    [8613] = true,      -- Skinning (generic)
    [194174] = true,    -- Skinning (Legion variant)
    [195125] = true,    -- Skinning (BfA variant)
    [265856] = true,    -- Skinning (BfA Kul Tiran)
    [265858] = true,    -- Skinning (BfA Zandalari)
    [324801] = true,    -- Skinning (Shadowlands)
    [366262] = true,    -- Skinning (Dragonflight)
    [423344] = true,    -- Skinning (TWW)
    -- Mining (these open loot on mining nodes, not corpses, but guard just in case)
    [2575] = true,      -- Mining (generic)
    [195122] = true,    -- Mining (BfA variant)
    [265854] = true,    -- Mining (BfA Kul Tiran)
    [265846] = true,    -- Mining (BfA Zandalari)
    [324802] = true,    -- Mining (Shadowlands)
    [366260] = true,    -- Mining (Dragonflight)
    [423343] = true,    -- Mining (TWW)
    -- Herbalism
    [2366] = true,      -- Herb Gathering (generic)
    [195114] = true,    -- Herbalism (BfA variant)
    [265852] = true,    -- Herbalism (BfA Kul Tiran)
    [265842] = true,    -- Herbalism (BfA Zandalari)
    [324804] = true,    -- Herbalism (Shadowlands)
    [366261] = true,    -- Herbalism (Dragonflight)
    [423342] = true,    -- Herbalism (TWW)
    -- Disenchanting
    [13262] = true,     -- Disenchant
    -- Prospecting
    [31252] = true,     -- Prospecting
    -- Milling
    [51005] = true,     -- Milling
    -- Salvaging (Garrison / Profession)
    [168065] = true,    -- Salvage (WoD Salvage Yard)
    [382984] = true,    -- Salvaging (DF variant)
    -- Milling / Prospecting new IDs (DF/TWW)
    [390396] = true,    -- Mass Milling (DF)
    [389191] = true,    -- Mass Prospecting (DF)
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
local isPickpocketing = false -- set on pickpocket cast, cleared on LOOT_CLOSED
local isProfessionLooting = false -- set on profession spell cast, cleared on LOOT_CLOSED
local isBlockingInteractionOpen = false -- true when bank/vendor/AH/mail/trade UI is open
local lastContainerItemID = nil  -- set on container use
local resolvedIDs = {}       -- [itemID] = { type, collectibleID } - runtime resolved mount/pet IDs
local lockoutAttempted = {}  -- [questID] = true : tracks which lockout quests we've already counted this reset period
                             -- Keyed by questID (not npcID) so multiple NPCs sharing the same quest
                             -- (e.g. Arachnoid Harvester 154342/151934 both use quest 55512) are handled correctly.
-- When loot has 0 item slots (only rep/currency), GetLootSourceInfo has nothing to return; target may be cleared.
-- Cache last targeted GUID that is in our DB so we can still attribute the loot open and count the try.
local lastLootSourceGUID = nil
local lastLootSourceTime = 0
local LAST_LOOT_SOURCE_TTL = 3  -- seconds
-- Snapshot at first line of LOOT_OPENED handler (before any routing) so ProcessNPCLoot can use them when GetLootSourceInfo fails.
local lootOpenedMouseoverGUID = nil
local lootOpenedTargetGUID = nil

-- Zone → objectID when no source GUID (e.g. instant loot cleared slots). Key = UiMapID from C_Map.GetBestMapForUnit (see warcraft.wiki.gg/wiki/InstanceID).
-- CHAT_MSG_LOOT fallback: itemID → npcID when loot window doesn't fire (direct loot, world boss, etc.).
-- Built from npcDropDB in BuildReverseIndices; hardcoded entries merged so they take precedence.
local chatLootItemToNpc = {}
local lastTryCountSourceKey = nil
local lastTryCountSourceTime = 0
local CHAT_LOOT_DEBOUNCE = 2.0  -- seconds: avoid double-count if LOOT_OPENED and CHAT_MSG_LOOT both fire

-- Try count is driven only by LOOT_OPENED. LOOT_SLOT_CHANGED is not used for NPC/object try count.

--- Log to chat when profile.debugTryCounterLoot is true (no rep/currency cache spam).
local function IsTryCounterLootDebugEnabled(addon)
    return addon and addon.db and addon.db.profile and addon.db.profile.debugTryCounterLoot
end

local function TryCounterLootDebug(addon, fmt, ...)
    if not IsTryCounterLootDebugEnabled(addon) then return end
    local n = select("#", ...)
    local msg = (n > 0) and string.format(tostring(fmt), ...) or tostring(fmt)
    addon:Print("|cff9370DB[WN-TryCounter]|r " .. msg)
end

-- =====================================================================
-- REVERSE LOOKUP INDICES (built once at InitializeTryCounter, O(1) lookups)
-- Keys: [type .. "\0" .. itemID] = true
-- These replace the old O(N) full-DB-scan approach in Is*Collectible().
-- =====================================================================
local guaranteedIndex = {}    -- drop.guaranteed == true
local repeatableIndex = {}    -- drop.repeatable == true
local dropSourceIndex = {}    -- any drop entry (exists in DB at all)
local dropDifficultyIndex = {} -- drop/NPC dropDifficulty string (e.g. "Mythic", "25H", "Heroic")
local repeatableItemDrops = {} -- [itemID] = drop for "item" type repeatable (reset + notify when received via CHAT_MSG_LOOT if loot window was cleared by autoLoot)
local reverseIndicesBuilt = false

-- =====================================================================
-- REVERSE INDEX BUILDER
-- Called once from InitializeTryCounter after DB references are loaded.
-- Iterates all drop sources once, building O(1) lookup tables keyed by
-- type+itemID. This eliminates the O(N) full-DB scans that previously
-- ran on every cache-miss call to Is*Collectible().
-- =====================================================================

---Index a single drop entry into the reverse lookup tables
---@param drop table { type, itemID, name [, guaranteed] [, repeatable] [, dropDifficulty] }
---@param npcDifficulty string|nil NPC-level dropDifficulty (item-level overrides this)
---@param hasStatistics boolean Whether the parent NPC has statisticIds (for default "All Difficulties")
local function IndexDrop(drop, npcDifficulty, hasStatistics)
    if not drop or not drop.type or not drop.itemID then return end

    local itemKey = drop.type .. "\0" .. tostring(drop.itemID)

    -- Every entry in the DB is a drop source
    dropSourceIndex[itemKey] = true

    if drop.guaranteed then
        guaranteedIndex[itemKey] = true
    end
    if drop.repeatable then
        repeatableIndex[itemKey] = true
        if drop.type == "item" and drop.itemID then
            repeatableItemDrops[drop.itemID] = drop
        end
    end

    -- dropDifficulty: item-level > NPC-level > "All Difficulties" (if NPC has statisticIds)
    local difficulty = drop.dropDifficulty or npcDifficulty
    if difficulty then
        dropDifficultyIndex[itemKey] = difficulty
    elseif hasStatistics then
        dropDifficultyIndex[itemKey] = "All Difficulties"
    end
end

---Index all drops from a flat array
---@param drops table|nil Array of drop entries (may also have .dropDifficulty / .statisticIds at the NPC level)
local function IndexDropArray(drops)
    if not drops then return end
    local npcDifficulty = drops.dropDifficulty  -- NPC-level difficulty (e.g. "Mythic")
    local hasStatistics = drops.statisticIds and #drops.statisticIds > 0
    for i = 1, #drops do
        IndexDrop(drops[i], npcDifficulty, hasStatistics)
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
    -- Zone drops support both old format (direct array) and new format ({ drops = {...}, raresOnly = true })
    for _, zData in pairs(zoneDropDB) do
        local drops = zData.drops or zData
        IndexDropArray(drops)
    end

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

    -- Quest-item -> mount mapping: so GetTryCount("mount", id) can fall back to item try count
    -- Plan cards use mountID (journal); we store count on item. Map both mountID and mount itemID to source item.
    questStarterMountToSourceItemID = {}
    for i = #questStarterMountList, 1, -1 do questStarterMountList[i] = nil end
    local seenMountItemID = {}
    local function IndexQuestStarterMounts(drops)
        if not drops then return end
        for i = 1, #drops do
            local drop = drops[i]
            if drop and drop.questStarters and drop.itemID then
                for j = 1, #drop.questStarters do
                    local qs = drop.questStarters[j]
                    if qs and qs.type == "mount" and qs.itemID then
                        questStarterMountToSourceItemID[qs.itemID] = drop.itemID
                        if not seenMountItemID[qs.itemID] then
                            seenMountItemID[qs.itemID] = true
                            questStarterMountList[#questStarterMountList + 1] = { itemID = qs.itemID, name = qs.name or ("ID:" .. tostring(qs.itemID)), mountID = qs.mountID }
                        end
                        -- Use hardcoded mountID first (works for unowned mounts); fallback to API
                        local mountID = qs.mountID
                        if not mountID and C_MountJournal and C_MountJournal.GetMountFromItem then
                            mountID = C_MountJournal.GetMountFromItem(qs.itemID)
                            if issecretvalue and mountID and issecretvalue(mountID) then mountID = nil end
                        end
                        if mountID and mountID ~= qs.itemID then
                            questStarterMountToSourceItemID[mountID] = drop.itemID
                        end
                    end
                end
            end
        end
    end
    for _, drops in pairs(npcDropDB) do IndexQuestStarterMounts(drops) end
    for _, drops in pairs(objectDropDB) do IndexQuestStarterMounts(drops) end
    for _, containerData in pairs(containerDropDB) do
        local list = containerData.drops or containerData
        if type(list) == "table" then
            local arr = list.drops or list
            if type(arr) == "table" then IndexQuestStarterMounts(arr) end
        end
    end

    -- itemID → npcID for CHAT_MSG_LOOT when loot window never opens (direct loot, world boss, etc.)
    chatLootItemToNpc = {}
    for npcID, npcData in pairs(npcDropDB) do
        for i = 1, #npcData do
            local drop = npcData[i]
            if drop and drop.itemID then
                if not chatLootItemToNpc[drop.itemID] then chatLootItemToNpc[drop.itemID] = npcID end
                if drop.questStarters then
                    for j = 1, #drop.questStarters do
                        local qs = drop.questStarters[j]
                        if qs and qs.itemID and not chatLootItemToNpc[qs.itemID] then
                            chatLootItemToNpc[qs.itemID] = npcID
                        end
                    end
                end
            end
        end
    end
    -- Hardcoded overrides (e.g. known edge cases)
    chatLootItemToNpc[235910] = 234621  -- Mint Condition Gallagio Anniversary Coin → Gallagio Garbage

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
    -- Quest-item mounts (Mechagon/Stonevault): item try count = boss kill count = mount try count (single source of truth)
    if collectibleType == "mount" then
        local sourceItemID = questStarterMountToSourceItemID[id]
        if not sourceItemID and C_MountJournal and C_MountJournal.GetMountFromItem then
            local idNum = tonumber(id)
            for mountKey, srcID in pairs(questStarterMountToSourceItemID) do
                if type(mountKey) == "number" and type(srcID) == "number" then
                    local resolved = C_MountJournal.GetMountFromItem(mountKey)
                    if resolved and tonumber(resolved) == idNum then
                        sourceItemID = srcID
                        break
                    end
                end
            end
        end
        if sourceItemID then
            local itemCount = WarbandNexus.db.global.tryCounts.item and WarbandNexus.db.global.tryCounts.item[sourceItemID]
            local stored = type(itemCount) == "number" and itemCount or 0
            -- Stonevault Mechsuit: Statistics(20500) = boss kills; show at least current char's stat when stored is 0
            if sourceItemID == 226683 and stored == 0 and GetStatistic then
                local val = GetStatistic(20500)
                if val and (not issecretvalue or not issecretvalue(val)) then
                    local n = tonumber(val)
                    if n and n > 0 then
                        if WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.debugMode then
                            WarbandNexus:Print(string.format("[TryCounter] Stonevault Mechsuit: using Statistics(%d) = %d", 20500, n))
                        end
                        return n
                    end
                end
            end
            return stored
        end
    end
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
    -- CRITICAL FIX: First attempt should be 1, not 0
    -- When user loots for first time, they want to see "1 attempt" not "0 attempts"
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

---Return quest-starter mounts (e.g. Stonevault Mechsuit) that are not yet collected, for Mounts browser.
---So they appear in Plans → Mounts tab even when not in C_MountJournal.GetMountIDs() yet (quest reward flow).
---@return table[] Array of { mountID = number, itemID = number, name = string }
function WarbandNexus:GetQuestStarterMountsForBrowser()
    if not reverseIndicesBuilt then BuildReverseIndices() end
    local out = {}
    for i = 1, #questStarterMountList do
        local entry = questStarterMountList[i]
        if entry and entry.itemID then
            local drop = { type = "mount", itemID = entry.itemID, name = entry.name }
            if not IsCollectibleCollected(drop) then
                local mountID = entry.itemID
                if C_MountJournal and C_MountJournal.GetMountFromItem then
                    local resolved = C_MountJournal.GetMountFromItem(entry.itemID)
                    if resolved and not (issecretvalue and issecretvalue(resolved)) then
                        mountID = resolved
                    end
                end
                out[#out + 1] = { mountID = mountID, itemID = entry.itemID, name = entry.name or ("ID:" .. tostring(entry.itemID)) }
            end
        end
    end
    return out
end

-- =====================================================================
-- GUID PARSING (minimal allocation)
-- =====================================================================

---Extract NPC ID from a creature/vehicle GUID
---@param guid string
---@return number|nil npcID
local function GetNPCIDFromGUID(guid)
    if not guid or type(guid) ~= "string" then return nil end
    -- Midnight 12.0: GUID may be a secret value during instanced combat
    if issecretvalue and issecretvalue(guid) then return nil end
    local unitType, npcID = guid:match("^(%a+)%-.-%-.-%-.-%-.-%-(%d+)")
    if unitType == "Creature" or unitType == "Vehicle" then
        return tonumber(npcID)
    end
    return nil
end

---Extract object ID from a GameObject GUID
---@param guid string
---@return number|nil objectID
local function GetObjectIDFromGUID(guid)
    if not guid or type(guid) ~= "string" then return nil end
    -- Midnight 12.0: GUID may be a secret value during instanced combat
    if issecretvalue and issecretvalue(guid) then return nil end
    local unitType, objectID = guid:match("^(%a+)%-.-%-.-%-.-%-.-%-(%d+)")
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

    if drop.type == "item" then
        -- Generic items (e.g. Miscellaneous Mechanica): collectibleID == itemID
        id = drop.itemID
    elseif drop.type == "mount" then
        -- Use hardcoded mountID first (works for unowned mounts); fallback to API
        if drop.mountID then
            id = drop.mountID
        elseif C_MountJournal.GetMountFromItem then
            id = C_MountJournal.GetMountFromItem(drop.itemID)
            -- Midnight 12.0: return value may be secret
            if issecretvalue and id and issecretvalue(id) then id = nil end
        end
    elseif drop.type == "pet" then
        -- C_PetJournal.GetPetInfoByItemID(itemID) -> speciesID (13th return value!)
        -- Returns: name, icon, petType, creatureID, sourceText, description,
        --          isWild, canBattle, isTradeable, isUnique, isObtainable,
        --          _, speciesID
        if C_PetJournal.GetPetInfoByItemID then
            local _, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(drop.itemID)
            id = speciesID
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
    if not drop or not drop.itemID then return nil end
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

-- questStarterMountToSourceItemID / questStarterMountList declared at top of file (used by BuildReverseIndices and GetQuestStarterMountsForBrowser)

-- Temporary cache for pre-reset try counts of repeatable mount/pet/toy drops.
-- When ProcessNPCLoot finds a repeatable drop in loot, it stores the count here
-- BEFORE resetting. CollectionService fires WN_COLLECTIBLE_OBTAINED later;
-- OnTryCounterCollectibleObtained reads from this cache so the notification
-- shows the correct attempt count instead of 0.
local pendingPreResetCounts = {}

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
---Checks user repeatableOverrides first (allows toggling repeatable from Settings).
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number collectibleID (mountID/speciesID) or itemID for toys
---@return boolean
function WarbandNexus:IsRepeatableCollectible(collectibleType, id)
    -- Check user override first
    if self.db and self.db.global and self.db.global.trackDB then
        local overrides = self.db.global.trackDB.repeatableOverrides
        if overrides then
            local overrideKey = (collectibleType or "") .. ":" .. tostring(id or 0)
            local val = overrides[overrideKey]
            if val ~= nil then return val end
        end
    end
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

-- Session cache for difficulty lookups
local difficultyCache = {}

-- Maps WoW difficultyID (from ENCOUNTER_END / GetRaidDifficultyID / GetDungeonDifficultyID)
-- to our dropDifficulty label strings.  Complete as of Patch 12.0.1 (Feb 2026).
-- https://warcraft.wiki.gg/wiki/DifficultyID
local DIFFICULTY_ID_TO_LABELS = {
    -- Mythic tier
    [16]  = "Mythic",   -- Mythic raid
    [23]  = "Mythic",   -- Mythic dungeon
    [8]   = "Mythic",   -- Mythic Keystone
    -- Heroic tier
    [15]  = "Heroic",   -- Heroic raid
    [2]   = "Heroic",   -- Heroic dungeon
    [5]   = "Heroic",   -- 10-player Heroic (legacy)
    [6]   = "25H",      -- 25-player Heroic (legacy)
    [24]  = "Heroic",   -- Timewalking dungeon
    [236] = "Heroic",   -- Lorewalking dungeon
    -- Normal tier
    [14]  = "Normal",   -- Normal raid (flex)
    [1]   = "Normal",   -- Normal dungeon
    [3]   = "10N",      -- 10-player Normal (legacy)
    [4]   = "25N",      -- 25-player Normal (legacy)
    [9]   = "Normal",   -- 40-player raid (MC, BWL, AQ40, Naxx)
    [33]  = "Normal",   -- Timewalking raid
    [150] = "Normal",   -- Normal dungeon (alternate)
    [172] = "Normal",   -- World Boss
    [205] = "Normal",   -- Follower dungeon
    [208] = "Normal",   -- Delves
    [220] = "Normal",   -- Story raid (solo)
    [241] = "Normal",   -- Lorewalking raid
    -- LFR tier
    [7]   = "LFR",      -- Looking for Raid (legacy, pre-SoO)
    [17]  = "LFR",      -- Looking for Raid (flex)
    [151] = "LFR",      -- Looking for Raid (Timewalking)
    -- Event tier (holiday bosses, world events)
    [18]  = "Normal",   -- Event raid
    [19]  = "Normal",   -- Event dungeon
    [232] = "Normal",   -- Event dungeon (alternate)
}

---Check if a difficultyID satisfies a dropDifficulty requirement.
---Midnight 12.0: guards against secret values to avoid ADDON_ACTION_FORBIDDEN.
---@param difficultyID number WoW difficultyID from ENCOUNTER_END or difficulty API
---@param requiredDifficulty string "Mythic"|"Heroic"|"25H"
---@return boolean true if the difficulty qualifies for the drop
local function DoesDifficultyMatch(difficultyID, requiredDifficulty)
    if not requiredDifficulty or requiredDifficulty == "All Difficulties" then
        return true
    end
    if not difficultyID then return false end
    if issecretvalue and issecretvalue(difficultyID) then return false end

    local label = DIFFICULTY_ID_TO_LABELS[difficultyID]
    if not label then return false end

    if requiredDifficulty == "Mythic" then
        return label == "Mythic"
    elseif requiredDifficulty == "Heroic" then
        return label == "Heroic" or label == "Mythic" or label == "25H"
    elseif requiredDifficulty == "25H" then
        return label == "25H"
    elseif requiredDifficulty == "Normal" then
        return label == "Normal" or label == "Heroic" or label == "Mythic" or label == "10N" or label == "25N"
    elseif requiredDifficulty == "10N" then
        return label == "10N"
    elseif requiredDifficulty == "25N" then
        return label == "25N"
    end
    return false
end

---Get the drop difficulty label for a collectible (type, id).
---Returns a string like "Mythic", "25H", "Heroic", or nil if no restriction (= all difficulties).
---O(1) index lookup via dropDifficultyIndex.
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number collectibleID (mountID/speciesID) or itemID for toys
---@return string|nil difficulty label, or nil if no restriction
function WarbandNexus:GetDropDifficulty(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return nil end

    local cacheKey = collectibleType .. "\0" .. tostring(id)
    if difficultyCache[cacheKey] ~= nil then
        -- false means "looked up, no difficulty"
        local v = difficultyCache[cacheKey]
        return v ~= false and v or nil
    end

    -- Direct lookup: id might already be an itemID
    local key = collectibleType .. "\0" .. tostring(id)
    if dropDifficultyIndex[key] then
        difficultyCache[cacheKey] = dropDifficultyIndex[key]
        return dropDifficultyIndex[key]
    end

    -- For non-toy types, caller may pass a native collectibleID (mountID/speciesID)
    -- but the index is keyed by itemID. Check resolved entries.
    if collectibleType ~= "toy" then
        for itemID, resolvedID in pairs(resolvedIDs) do
            if resolvedID == id then
                local altKey = collectibleType .. "\0" .. tostring(itemID)
                if dropDifficultyIndex[altKey] then
                    difficultyCache[cacheKey] = dropDifficultyIndex[altKey]
                    return dropDifficultyIndex[altKey]
                end
            end
        end
    end

    difficultyCache[cacheKey] = false
    return nil
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

    if drop.type == "item" then
        -- Accumulation items (Crackling Shard, Miscellaneous Mechanica): check if all
        -- yields (the end-goal mounts/pets they lead to) have been collected.
        -- If ALL yields are collected, stop tracking — no point farming further.
        -- This check applies EVEN to repeatable items: once Alunira is collected,
        -- no need to keep counting Crackling Shard attempts.
        if drop.yields and #drop.yields > 0 then
            local allCollected = true
            for _, yield in ipairs(drop.yields) do
                local yieldDrop = { type = yield.type, itemID = yield.itemID, name = yield.name }
                if not IsCollectibleCollected(yieldDrop) then
                    allCollected = false
                    break  -- At least one yield still missing → keep tracking
                end
            end
            if allCollected then
                -- Debug: All yields collected, stopping tracking
                return true  -- All yields collected → treat item as "collected"
            else
                -- Debug: At least one yield missing, continue tracking
                return false
            end
        end
        if drop.questStarters and #drop.questStarters > 0 then
            for _, qs in ipairs(drop.questStarters) do
                if not IsCollectibleCollected(qs) then
                    return false
                end
            end
            return true
        end
        return false  -- No yields defined → always trackable
    elseif drop.type == "mount" then
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
            -- Midnight 12.0: link can be secret in some contexts; guard before any string/table use
            if link and (not issecretvalue or not issecretvalue(link)) then
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

---Get the item hyperlink (quality-colored) for a drop entry.
---Falls back to orange-colored plain name if item data is not cached.
---@param drop table { type, itemID, name }
---@return string displayLink Formatted item link or colored name
local function GetDropItemLink(drop)
    if not drop or not drop.itemID then
        return "|cffff8000[" .. (drop and drop.name or "Unknown") .. "]|r"
    end
    local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    if GetItemInfo then
        local _, itemLink = GetItemInfo(drop.itemID)
        if itemLink then return itemLink end
    end
    -- Item not cached: request for future use, return orange fallback
    if C_Item and C_Item.RequestLoadItemDataByID then
        pcall(C_Item.RequestLoadItemDataByID, drop.itemID)
    end
    return "|cffff8000[" .. (drop.name or "Unknown") .. "]|r"
end

---Re-read WoW Statistics for specific drops and update try counts.
---Used for instance bosses with statisticIds — authoritative source of kill counts.
---Delayed slightly to allow WoW's statistic API to update after a kill.
---@param drops table Array of drop entries to re-seed
---@param statIds table Array of WoW statistic IDs for the source NPC
local function ReseedStatisticsForDrops(drops, statIds)
    if not drops or #drops == 0 or not statIds or #statIds == 0 then return end
    if not EnsureDB() then return end
    local GetStat = GetStatistic
    if not GetStat then return end

    -- Get character key
    local charKey
    if ns.Utilities and ns.Utilities.GetCharacterKey then
        charKey = ns.Utilities:GetCharacterKey()
    else
        local name = UnitName("player")
        local realm = GetRealmName()
        if name and realm then
            charKey = name:gsub("%s+", "") .. "-" .. realm:gsub("%s+", "")
        end
    end
    if not charKey then return end

    -- Ensure snapshot storage
    local snapshots = WarbandNexus.db.global.statisticSnapshots
    if not snapshots then
        WarbandNexus.db.global.statisticSnapshots = {}
        snapshots = WarbandNexus.db.global.statisticSnapshots
    end
    if not snapshots[charKey] then
        snapshots[charKey] = {}
    end
    local charSnapshot = snapshots[charKey]

    -- Sum all statisticIds for this boss on THIS character
    local thisCharTotal = 0
    for _, sid in ipairs(statIds) do
        local val = GetStat(sid)
        local num
        if val and not (issecretvalue and issecretvalue(val)) then
            num = tonumber(val)
        end
        if num and num > 0 then
            thisCharTotal = thisCharTotal + num
        end
    end

    local function ProcessSeedDrop(drop)
        if drop and not drop.guaranteed then
            -- During gameplay APIs are warm, so ResolveCollectibleID should work.
            -- Use GetTryCountKey as fallback to guarantee tracking even if API fails.
            local tryKey = ResolveCollectibleID(drop) or GetTryCountKey(drop)
            if tryKey then
                -- Store this character's contribution
                charSnapshot[tryKey] = thisCharTotal

                -- Sum across ALL characters
                local globalTotal = 0
                for _, snap in pairs(snapshots) do
                    local charVal = snap[tryKey]
                    if charVal and charVal > 0 then
                        globalTotal = globalTotal + charVal
                    end
                end

                -- Always set to globalTotal (authoritative source)
                WarbandNexus:SetTryCount(drop.type, tryKey, globalTotal)

                -- Quest-item mounts (Mechagon/Stonevault): mirror to mount so plan card shows same count
                if drop.type == "item" and drop.questStarters then
                    for _, qs in ipairs(drop.questStarters) do
                        if qs.type == "mount" and qs.itemID then
                            local mountKey1 = ResolveCollectibleID(qs)
                            local mountKey2 = qs.itemID
                            WarbandNexus:SetTryCount("mount", mountKey1 or mountKey2, globalTotal)
                            if mountKey1 and mountKey1 ~= mountKey2 then
                                WarbandNexus:SetTryCount("mount", mountKey2, globalTotal)
                            end
                            -- So GetTryCount("mount", mountID or itemID) can fall back to item count
                            questStarterMountToSourceItemID[mountKey1 or mountKey2] = drop.itemID
                            if mountKey1 and mountKey1 ~= mountKey2 then
                                questStarterMountToSourceItemID[mountKey2] = drop.itemID
                            end
                        end
                    end
                end

                local itemLink = GetDropItemLink(drop)
                TryChat(format("|cff9370DB[WN-Counter]|r |cff00ccff(Statistics)|r " .. ((ns.L and ns.L["TRYCOUNTER_ATTEMPTS_FOR"]) or "%d attempts for %s"), globalTotal, itemLink))
            end
        end
        if drop and drop.questStarters then
            for _, qs in ipairs(drop.questStarters) do
                ProcessSeedDrop(qs)
            end
        end
    end

    for i = 1, #drops do
        ProcessSeedDrop(drops[i])
    end

    -- Notify UI to refresh try counts on cards
    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage("WN_PLANS_UPDATED", { action = "statistics_reseeded" })
    end
end

---Increment try count and print chat message for unfound drops.
---Skips 100% (guaranteed) drops: no increment, no chat message.
---DEFERRED: Runs on next frame via C_Timer.After(0) to avoid blocking loot frame.
---Counter increments and chat messages don't need to be synchronous.
---
---For bosses with statisticIds: does NOT manually increment. Instead, re-reads
---WoW Statistics after a short delay (2s) to let the API update. This prevents
---double-counting since the statistic is the authoritative kill counter.
---@param drops table Array of drop entries that were NOT found in loot
---@param statIds table|nil Optional statisticIds from the NPC source
local function ProcessMissedDrops(drops, statIds)
    if not drops or #drops == 0 then return end
    if not EnsureDB() then return end

    -- Bosses with statisticIds: re-seed from Statistics (authoritative source).
    -- Delay 2s to allow WoW's GetStatistic API to update after the kill.
    if statIds and #statIds > 0 then
        C_Timer.After(2, function()
            ReseedStatisticsForDrops(drops, statIds)
        end)
        return
    end

    -- Non-statistic sources: increment manually (addon-counted).
    C_Timer.After(0, function()
        if not EnsureDB() then return end
        local function ProcessManualDrop(drop)
            if drop and not drop.guaranteed then
                local tryKey = GetTryCountKey(drop)
                if tryKey then
                    local newCount = WarbandNexus:IncrementTryCount(drop.type, tryKey)
                    -- Quest-item mounts: mirror same count to mount so plan card shows it
                    if drop.type == "item" and drop.questStarters then
                        for _, qs in ipairs(drop.questStarters) do
                            if qs.type == "mount" and qs.itemID then
                                local k1 = ResolveCollectibleID(qs)
                                local k2 = qs.itemID
                                WarbandNexus:SetTryCount("mount", k1 or k2, newCount)
                                if k1 and k1 ~= k2 then
                                    WarbandNexus:SetTryCount("mount", k2, newCount)
                                end
                                questStarterMountToSourceItemID[k1 or k2] = drop.itemID
                                if k1 and k1 ~= k2 then questStarterMountToSourceItemID[k2] = drop.itemID end
                            end
                        end
                    end
                    local itemLink = GetDropItemLink(drop)
                    TryChat(format("|cff9370DB[WN-Counter]|r " .. ((ns.L and ns.L["TRYCOUNTER_ATTEMPTS_FOR"]) or "%d attempts for %s"), newCount, itemLink))
                end
            end
            -- Recurse for questStarters only when we did not already mirror (item->mount already mirrored above)
            if drop and drop.questStarters then
                for _, qs in ipairs(drop.questStarters) do
                    if not (drop.type == "item" and qs.type == "mount") then
                        ProcessManualDrop(qs)
                    end
                end
            end
        end

        for i = 1, #drops do
            ProcessManualDrop(drops[i])
        end
    end)
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
    if not npcIDs then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "ENCOUNTER_END encID=%s not in DB", tostring(encounterID)) end
        return
    end
    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "ENCOUNTER_END encID=%s npcs=%d", tostring(encounterID), #npcIDs) end
    
    -- Check if this encounter was already processed in last 10 seconds (prevent double-counting)
    local encounterKey = "encounter_" .. tostring(encounterID)
    local now = GetTime()
    if lastTryCountSourceKey == encounterKey and (now - lastTryCountSourceTime) < 10 then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "ENCOUNTER_END encID=%s already counted", tostring(encounterID)) end
        return
    end

    -- Feed localized encounter name to TooltipService for name-based tooltip lookup.
    -- ENCOUNTER_END args are NOT secret values — encounterName is always the correct
    -- localized string. This is the critical fallback for Midnight instances where
    -- UnitGUID is secret AND EJ API may be restricted.
    if self.Tooltip and self.Tooltip._feedEncounterKill then
        self.Tooltip._feedEncounterKill(encounterName, encounterID)
    end

    -- Create synthetic kill entries for all NPCs in this encounter.
    -- Include npcID in the GUID to avoid dedup collisions when multiple NPCs
    -- in the same encounter have drops (GetTime() returns the same value within a frame).
    local now = GetTime()
    local addedCount = 0
    for i = 1, #npcIDs do
        local npcID = npcIDs[i]
        if npcDropDB[npcID] then
            local syntheticGUID = "Encounter-" .. encounterID .. "-" .. npcID .. "-" .. now
            local safeDiffID = difficultyID
            if issecretvalue and safeDiffID and issecretvalue(safeDiffID) then
                safeDiffID = nil
            end
            recentKills[syntheticGUID] = {
                npcID = npcID,
                name = encounterName or "Boss",
                time = now,
                isEncounter = true,
                difficultyID = safeDiffID,
            }
            addedCount = addedCount + 1
        end
    end
    if IsTryCounterLootDebugEnabled(self) and addedCount > 0 then TryCounterLootDebug(self, "recentKills +%d", addedCount) end

    -- DELAYED FALLBACK: If no loot window opens within 5 seconds (personal loot gave nothing,
    -- or extremely fast auto-loot), manually check recentKills and increment try counters.
    -- This ensures encounters count even when LOOT_OPENED never fires.
    -- Use encounterID-based dedup to prevent multiple NPCs from same encounter counting separately.
    if addedCount > 0 then
        C_Timer.After(5, function()
            if not IsAutoTryCounterEnabled() then return end
            
            -- Check if this encounter was already processed
            local encounterKey = "encounter_" .. tostring(encounterID)
            local now = GetTime()
            if lastTryCountSourceKey == encounterKey and (now - lastTryCountSourceTime) < 10 then
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "ENCOUNTER_END delayed: encID %s already counted", tostring(encounterID)) end
                return
            end
            
            -- Find first NPC with drops from this encounter
            local matchedNpcID = nil
            local trackable = {}
            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and (now - killData.time < 6) then
                    local drops = npcDropDB[killData.npcID]
                    if drops then
                        matchedNpcID = killData.npcID
                        -- Build trackable from this NPC's drops
                        for i = 1, #drops do
                            local drop = drops[i]
                            if not IsCollectibleCollected(drop) then
                                trackable[#trackable + 1] = drop
                            end
                        end
                        break -- Only process one NPC from this encounter
                    end
                end
            end
            
            if #trackable > 0 and matchedNpcID then
                lastTryCountSourceKey = encounterKey
                lastTryCountSourceTime = now
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "ENCOUNTER_END delayed: encID %s npc %s +%d (no loot window)", tostring(encounterID), tostring(matchedNpcID), #trackable) end
                
                local drops = npcDropDB[matchedNpcID]
                ProcessMissedDrops(trackable, drops.statisticIds)
            end
            
            -- Clean up all encounter entries from this encounter
            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and (now - killData.time < 6) then
                    recentKills[guid] = nil
                end
            end
        end)
    end
    
    -- DEFERRED RETRY: If a chest was opened BEFORE this encounter ended (RP/cinematic timing),
    -- ProcessNPCLoot found no drops because recentKills was empty. Now that we've added
    -- the encounter entries, retry processing. Short delay ensures loot window state is stable.
    if self._pendingEncounterLoot then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "pendingEncounterLoot retry in 0.5s") end
        self._pendingEncounterLoot = nil
        self._pendingEncounterLootRetried = true
        C_Timer.After(0.5, function()
            self._pendingEncounterLootRetried = nil
            self:ProcessNPCLoot()
        end)
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
local lastNotifiedInstanceID = nil   -- from GetInstanceInfo(), used to avoid re-scheduling
local lastShownJournalInstanceID = nil -- from EJ_GetCurrentInstance(), used to avoid re-printing on reload

---PLAYER_ENTERING_WORLD handler (detect instance entry and print collectible drops)
function WarbandNexus:OnTryCounterInstanceEntry(event, isInitialLogin, isReloadingUi)
    if not IsAutoTryCounterEnabled() then return end

    local inInstance, instanceType = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if issecretvalue and instanceType and issecretvalue(instanceType) then instanceType = nil end
    if not inInstance then
        lastNotifiedInstanceID = nil
        lastShownJournalInstanceID = nil
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

    -- Get instance ID to avoid re-notifying on /reload inside same instance.
    -- instanceID (8th return) can be 0 in some dungeons/Timewalking; only skip when we've already notified for this ID.
    local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
    if instanceID and instanceID ~= 0 and instanceID == lastNotifiedInstanceID then return end
    if instanceID and instanceID ~= 0 then
        lastNotifiedInstanceID = instanceID
    end

    -- Delay to let the instance fully load and avoid combat lockdown issues.
    -- T+4s: deferred past DataServices (T+0.5..3s) to avoid competing for frame time.
    C_Timer.After(4, function()
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

        if not EJ_GetCurrentInstance or not EJ_SelectInstance or not EJ_GetEncounterInfoByIndex then return end
        local journalInstanceID = EJ_GetCurrentInstance()
        -- EJ can return 0 for some instances (e.g. Mechagon, Timewalking) until fully ready; retry once after 2s
        if not journalInstanceID or journalInstanceID == 0 then
            C_Timer.After(2, function()
                if not WN or not WN.Print then return end
                local inInst = IsInInstance()
                if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
                if not inInst then return end
                local jid = EJ_GetCurrentInstance()
                if jid and jid ~= 0 and jid ~= lastShownJournalInstanceID then
                    lastShownJournalInstanceID = jid
                    TryCounterShowInstanceDrops(jid)
                end
            end)
            return
        end
        if journalInstanceID == lastShownJournalInstanceID then return end
        lastShownJournalInstanceID = journalInstanceID
        TryCounterShowInstanceDrops(journalInstanceID)
    end)
end

local function TryCounterShowInstanceDrops(journalInstanceID)
    local WN = WarbandNexus
    if not WN or not WN.Print then return end
    EJ_SelectInstance(journalInstanceID)

    -- Iterate all encounters in this instance and cross-reference with our encounterDB
        local dropsToShow = {} -- { { bossName, drops = { {type, itemID, name}, ... } }, ... }
        local idx = 1
        while true do
            -- Returns: name, desc, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID, instanceID
            local encName, _, _, _, _, _, dungeonEncID = EJ_GetEncounterInfoByIndex(idx)
            -- Guard: issecretvalue check MUST run before `not encName` to avoid
            -- ADDON_ACTION_FORBIDDEN when comparing a secret value with nil.
            local isSecret = issecretvalue and encName and issecretvalue(encName)
            if not isSecret and not encName then break end
            if not isSecret and dungeonEncID then
                isSecret = issecretvalue and issecretvalue(dungeonEncID)
            end
            if not isSecret then
                -- Our encounterDB is keyed by DungeonEncounterID (from ENCOUNTER_END event)
                local npcIDs = dungeonEncID and encounterDB[dungeonEncID]
                if npcIDs then
                    local encounterDrops = {}
                    local seenItems = {}
                    local dropDiffMap = {}
                    for _, npcID in ipairs(npcIDs) do
                        local npcDrops = npcDropDB[npcID]
                        if npcDrops then
                            local npcDiff = npcDrops.dropDifficulty
                            for j = 1, #npcDrops do
                                local drop = npcDrops[j]
                                if not seenItems[drop.itemID] then
                                    seenItems[drop.itemID] = true
                                    encounterDrops[#encounterDrops + 1] = drop
                                    local reqDiff = drop.dropDifficulty or npcDiff
                                    if reqDiff and reqDiff ~= "All Difficulties" then
                                        dropDiffMap[drop.itemID] = reqDiff
                                    end
                                end
                            end
                        end
                    end
                    if #encounterDrops > 0 then
                        dropsToShow[#dropsToShow + 1] = {
                            bossName = encName,
                            drops = encounterDrops,
                            diffMap = dropDiffMap,
                        }
                    end
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
            if not WN then return end

            TryChat("|cff9370DB[WN-Drops]|r " .. ((ns.L and ns.L["TRYCOUNTER_INSTANCE_DROPS"]) or "Collectible drops in this instance:"))

            for _, entry in ipairs(dropsToShow) do
                for _, drop in ipairs(entry.drops) do
                    -- Get item hyperlink (quality-colored, bracketed)
                    local itemLink = GetDropItemLink(drop)

                    -- Check collection status (these APIs work outside combat)
                    local collected = false
                    if drop.type == "item" then
                        -- Generic items: never "collected" (accumulation items)
                        collected = false
                    elseif drop.type == "mount" then
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
                            local _, _, _, _, _, _, _, _, _, _, _, _, speciesID = C_PetJournal.GetPetInfoByItemID(drop.itemID)
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
                        status = "|cff00ff00" .. ((ns.L and ns.L["TRYCOUNTER_COLLECTED_TAG"]) or "(Collected)") .. "|r"
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
                            status = "|cffffff00(" .. tryCount .. ((ns.L and ns.L["TRYCOUNTER_ATTEMPTS_SUFFIX"]) or " attempts") .. ")|r"
                        else
                            local typeLabels = {
                                mount = (ns.L and ns.L["TRYCOUNTER_TYPE_MOUNT"]) or "Mount",
                                pet = (ns.L and ns.L["TRYCOUNTER_TYPE_PET"]) or "Pet",
                                toy = (ns.L and ns.L["TRYCOUNTER_TYPE_TOY"]) or "Toy",
                                item = (ns.L and ns.L["TRYCOUNTER_TYPE_ITEM"]) or "Item",
                            }
                            status = "|cff888888(" .. (typeLabels[drop.type] or "") .. ")|r"
                        end
                    end

                    local diffTag = ""
                    local reqDiff = entry.diffMap and entry.diffMap[drop.itemID]
                    if reqDiff then
                        diffTag = " |cffff8800(" .. reqDiff .. ")|r"
                    end
                    TryChat("  " .. entry.bossName .. ": " .. itemLink .. diffTag .. " " .. status)
                end
            end
        end)
end

---UNIT_SPELLCAST_SENT handler (detect fishing casts)
function WarbandNexus:OnTryCounterSpellcastSent(event, unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    if target then
        lastGatherCastName = target
        lastGatherCastTime = GetTime()
    end
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
    elseif PICKPOCKET_SPELLS[spellID] then
        isPickpocketing = true
    elseif PROFESSION_LOOT_SPELLS[spellID] then
        isProfessionLooting = true
    end
end

-- =====================================================================
-- SAFE GUID HELPERS (must be defined before event handlers)
-- =====================================================================

---Safely get unit GUID (Midnight 12.0: UnitGUID returns secret values for NPC/object units)
---@param unit string e.g. "target", "mouseover"
---@return string|nil guid Safe GUID string or nil
local function SafeGetUnitGUID(unit)
    if not unit then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not guid then return nil end
    if type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    return guid
end

local function SafeGetTargetGUID()
    return SafeGetUnitGUID("target")
end

---Mouseover at LOOT_OPENED: when opening an object (e.g. dumpster) by right-click, mouse is often still over it.
local function SafeGetMouseoverGUID()
    return SafeGetUnitGUID("mouseover")
end

---Safely get a GUID string, guarding against Midnight 12.0 secret values.
---@param rawGUID any A potentially secret GUID value
---@return string|nil guid Safe GUID string or nil
local function SafeGuardGUID(rawGUID)
    if not rawGUID then return nil end
    if type(rawGUID) ~= "string" then return nil end
    if issecretvalue and issecretvalue(rawGUID) then return nil end
    return rawGUID
end

-- =====================================================================
-- LOOT CLOSED HANDLER
-- =====================================================================

---LOOT_CLOSED handler (reset fishing flag, pickpocket flag, safety timer)
---processedGUIDs is NOT cleared here — it persists with TTL-based cleanup (300s).
---This prevents double-counting when the same loot source (NPC corpse, chest, container)
---is opened multiple times in quick succession (user takes partial loot, closes, reopens).
---Different loot sources get their own GUID and are counted separately.
function WarbandNexus:OnTryCounterLootClosed()
    isFishing = false
    isPickpocketing = false
    isProfessionLooting = false
    isBlockingInteractionOpen = false  -- Safety reset: ensure flag doesn't persist if HIDE event missed
    lastContainerItemID = nil
    fishingResetTimer = nil
    lootOpenedMouseoverGUID = nil
    lootOpenedTargetGUID = nil
    -- Do NOT clear lastGatherCastName/lastGatherCastTime here (overwritten on next UNIT_SPELLCAST_SENT).
    -- DO NOT clear processedGUIDs here — let TTL-based cleanup handle it (PROCESSED_GUID_TTL = 300s)
    if fishingResetTimer then
        fishingResetTimer:Cancel()
        fishingResetTimer = nil
    end
end

---LOOT_SLOT_CHANGED: only used for vendor/mail/buy (blocking interaction) contexts; not used for try count.
---Try count is driven only by LOOT_OPENED. World boss direct drop is covered by CHAT_MSG_LOOT.
---@param slotIndex number
function WarbandNexus:OnTryCounterLootSlotChanged(slotIndex)
    if slotIndex ~= 1 then return end
    -- Run only when loot window is from vendor/mail/AH/bank (blocking interaction). No try count there.
    if not isBlockingInteractionOpen then return end
    -- Future: vendor/mail-specific logic could go here if needed.
end

---CHAT_MSG_LOOT fallback: (1) repeatable item obtained → reset try count + notification (loot window cleared by autoLoot);
---(2) item → NPC increment (e.g. Gallagio coin → 234621).
---@param message string
---@param author string
function WarbandNexus:OnTryCounterChatMsgLoot(message, author)
    if not message or not IsAutoTryCounterEnabled() then return end
    -- Midnight 12.0: message and author can be secret values; guard before any string op or comparison
    if issecretvalue then
        if issecretvalue(message) then return end
        if author and issecretvalue(author) then return end
    end
    local playerName = UnitName("player")
    if not playerName or author ~= playerName then return end
    local itemIDStr = message:match("|Hitem:(%d+):")
    if not itemIDStr then return end
    local itemID = tonumber(itemIDStr)
    if not itemID then return end

    -- Path A: repeatable trackable item obtained (e.g. Miscellaneous Mechanica) — reset + "Obtained! Try counter reset" + notification when loot window was cleared by autoLoot
    local drop = repeatableItemDrops[itemID]
    if drop then
        local tryKey = GetTryCountKey(drop)
        if tryKey then
            -- Check debounce: if we already processed this drop from LOOT_OPENED recently, skip
            local sourceKey = "item_" .. tostring(itemID)  -- synthetic key for item-based reset
            if lastTryCountSourceKey == sourceKey and (GetTime() - lastTryCountSourceTime) < CHAT_LOOT_DEBOUNCE then
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "CHAT skip: recent reset item=%s", tostring(itemID)) end
                return
            end
            
            local preResetCount = self:GetTryCount(drop.type, tryKey)
            self:ResetTryCount(drop.type, tryKey)
            lastTryCountSourceKey = sourceKey
            lastTryCountSourceTime = GetTime()
            
            local itemLink = GetDropItemLink(drop)
            TryChat("|cff9370DB[WN-Counter]|r " .. format((ns.L and ns.L["TRYCOUNTER_OBTAINED_RESET"]) or "Obtained %s! Try counter reset.", itemLink))
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
            local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
            if self.SendMessage then
                self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                    type = "item",
                    id = drop.itemID,
                    name = itemName or drop.name or "Unknown",
                    icon = itemIcon,
                    preResetTryCount = preResetCount,
                })
            end
        end
        return  -- Early return after Path A processing
    end

    -- Path B: item → NPC try count increment (direct loot, world boss, or when LOOT_OPENED was missed)
    local npcID = chatLootItemToNpc[itemID]
    if npcID then
        local drops = npcDropDB[npcID]
        if drops then
            local key = "npc_" .. tostring(npcID)
            if lastTryCountSourceKey == key and (GetTime() - lastTryCountSourceTime) < CHAT_LOOT_DEBOUNCE then
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "CHAT skip: already counted npc=%s", tostring(npcID)) end
                return
            end
            local trackable = {}
            for i = 1, #drops do
                local drop = drops[i]
                -- For repeatable items with yields (e.g. Crackling Shard), check if yields are collected
                if not IsCollectibleCollected(drop) then
                    trackable[#trackable + 1] = drop
                end
            end
            if #trackable > 0 then
                lastTryCountSourceKey = key
                lastTryCountSourceTime = GetTime()
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "CHAT +%d: item %s npc %s", #trackable, tostring(itemID), tostring(npcID)) end
                ProcessMissedDrops(trackable, drops.statisticIds)
                return
            end
        end
    end
    
    -- Path C: Encounter fallback (LOOT_OPENED never fired but chat shows loot from recent encounter kill)
    -- If LOOT_OPENED was missed (someone else looted, very fast auto-loot, etc.), recentKills won't be
    -- processed unless we have a fallback. Check if any recent encounter kill drops this itemID.
    if not recentKills or next(recentKills) == nil then return end
    
    local now = GetTime()
    for guid, killData in pairs(recentKills) do
        if killData.isEncounter then
            local drops = npcDropDB[killData.npcID]
            if drops then
                -- Check if any drop in this NPC's table matches the looted itemID
                local itemMatches = false
                for i = 1, #drops do
                    local drop = drops[i]
                    if drop.itemID == itemID then
                        itemMatches = true
                        break
                    end
                    -- Also check questStarters (for quest item drops like Malfunctioning Mechsuit)
                    if drop.questStarters then
                        for j = 1, #drop.questStarters do
                            if drop.questStarters[j].itemID == itemID then
                                itemMatches = true
                                break
                            end
                        end
                    end
                end
                
                if itemMatches then
                    -- Avoid double-count if LOOT_OPENED already processed this encounter
                    local key = "encounter_" .. tostring(killData.npcID)
                    if lastTryCountSourceKey == key and (GetTime() - lastTryCountSourceTime) < CHAT_LOOT_DEBOUNCE then
                        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "CHAT skip: encounter npc=%s already counted", tostring(killData.npcID)) end
                        return
                    end
                    
                    -- Build trackable
                    local trackable = {}
                    for i = 1, #drops do
                        local drop = drops[i]
                        -- For repeatable items with yields (e.g. Crackling Shard), check if yields are collected
                        if not IsCollectibleCollected(drop) then
                            trackable[#trackable + 1] = drop
                        end
                    end
                    
                    if #trackable > 0 then
                        lastTryCountSourceKey = key
                        lastTryCountSourceTime = GetTime()
                        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "CHAT encounter +%d: item %s npc %s", #trackable, tostring(itemID), tostring(killData.npcID)) end
                        ProcessMissedDrops(trackable, drops.statisticIds)
                        
                        -- Clean up this encounter entry to prevent re-use
                        recentKills[guid] = nil
                        return
                    end
                end
            end
        end
    end
end

---CHAT_MSG_CURRENCY / CHAT_MSG_MONEY fallback logic.
---In WoW, when gathering objects (like Overflowing Dumpster) that ONLY drop currency/money,
---LOOT_OPENED may not fire or closes instantly. This attributes currency to:
--- Reserved for future try-count attribution from currency (e.g. zone objects). Currently no-op.
---@param event string
---@param message string
function WarbandNexus:OnTryCounterChatMsgCurrency(event, message)
    if not IsAutoTryCounterEnabled() then return end
    -- Zone-object (dumpster) try count removed: attribution was unreliable (UNIT_SPELLCAST_SENT target often nil for objects).
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
    -- Snapshot mouseover/target immediately so ProcessNPCLoot can use them when GetLootSourceInfo returns nothing.
    if SafeGetMouseoverGUID then lootOpenedMouseoverGUID = SafeGetMouseoverGUID() else lootOpenedMouseoverGUID = nil end
    if SafeGetTargetGUID then lootOpenedTargetGUID = SafeGetTargetGUID() else lootOpenedTargetGUID = nil end

    if not IsAutoTryCounterEnabled() then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip: try counter disabled") end
        return
    end

    -- Route 1: Container item
    if isFromItem then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "route: container") end
        self:ProcessContainerLoot()
        return
    end

    -- Route 2: Fishing
    if isFishing then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "route: fishing") end
        self:ProcessFishingLoot()
        return
    end

    -- Route 3: Pickpocket — skip (source would match npcDropDB falsely)
    if isPickpocketing then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip: pickpocket") end
        return
    end

    -- Route 4: Blocking UI (bank/vendor/AH/mail/trade)
    if isBlockingInteractionOpen then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip: blocking UI") end
        return
    end

    -- Route 5: Profession loot (skin/mine/herb etc.) — skip false NPC match
    if isProfessionLooting then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip: profession loot") end
        return
    end

    -- Route 6: NPC / Object / Zone
    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "route: NPC/Object") end
    self:ProcessNPCLoot()
end

-- =====================================================================
-- PROCESSING PATHS
-- =====================================================================

---Collect ALL unique loot source GUIDs from the loot window.
---Uses GetLootSourceInfo(slotIndex) which returns the GUID of the entity
---that provided the loot for each slot (creature, game object, etc.).
---In AoE loot, different slots may come from different corpses.
---Falls back to UnitGUID("npc") which is set during some NPC/object interactions.
---@return table uniqueGUIDs Array of unique safe GUID strings (may be empty)
local function GetAllLootSourceGUIDs()
    local uniqueGUIDs = {}
    local seen = {}

    -- Method 1: GetLootSourceInfo per slot (most reliable, handles AoE loot)
    if GetLootSourceInfo then
        local numItems = GetNumLootItems()
        for i = 1, numItems or 0 do
            local ok, sourceGUID = pcall(GetLootSourceInfo, i)
            if ok and sourceGUID then
                local safeGUID = SafeGuardGUID(sourceGUID)
                if safeGUID and not seen[safeGUID] then
                    seen[safeGUID] = true
                    uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
                end
            end
        end
    end

    -- Method 2: UnitGUID("npc") - set during some NPC/object interactions
    -- Add only if not already seen from GetLootSourceInfo
    local ok, npcGUID = pcall(UnitGUID, "npc")
    if ok and npcGUID then
        local safeGUID = SafeGuardGUID(npcGUID)
        if safeGUID and not seen[safeGUID] then
            seen[safeGUID] = true
            uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
        end
    end

    return uniqueGUIDs
end

---Process loot from NPC corpse or game object.
---Source resolution order (raid/dungeon/instance/open world/rare/zone — same flow):
---  (1) Loot slot GUIDs (GetLootSourceInfo) + UnitGUID("npc") -> npcDropDB / objectDropDB
---  (2) UnitGUID("target") -> same DBs
---  (3) Zone: C_Map.GetBestMapForUnit + parent chain -> zoneDropDB
---  (4) recentKills (ENCOUNTER_END/CLEU); GameObject allows encounter match within TTL; Creature (not in DB) does not.
function WarbandNexus:ProcessNPCLoot()
    local drops = nil
    local dedupGUID = nil
    local hasIdentifiedSource = false
    -- Track whether the identified source is a GameObject (chest/object).
    -- Used in recentKills fallback: Creature sources block the fallback (prevents
    -- trash mob loot from matching boss encounters), but GameObject sources allow it
    -- (boss chests may not be in objectDropDB but the encounter kill IS authoritative).
    local sourceIsGameObject = false
    local sourceIsCreature = false
    -- Track the matched npcID so we can clean up encounter entries after processing
    local matchedNpcID = nil
    local lastMatchedObjectID = nil  -- for lastTryCountSourceKey when source is object
    -- Store targetGUID separately for processedGUIDs marking at end
    local targetGUID = nil
    -- Store ALL source GUIDs for comprehensive processedGUIDs marking
    local allSourceGUIDs = {}

    -- Use snapshot taken at first line of OnTryCounterLootOpened (so before any routing).
    local cachedMouseoverGUID = lootOpenedMouseoverGUID
    local cachedTargetGUID = lootOpenedTargetGUID

    -- ===================================================================
    -- PRIORITY 1: Loot Source GUIDs (GetLootSourceInfo / UnitGUID("npc"))
    -- This is the ACTUAL entity providing the loot — most authoritative.
    -- AoE LOOT FIX: In AoE loot mode, different slots come from different corpses.
    -- GetLootSourceInfo(slotIndex) returns per-slot GUIDs. We collect ALL unique
    -- source GUIDs and check each against our databases. This prevents:
    --   Bug scenario (AoE loot):
    --     1. Player kills rare + 4 trash mobs → AoE loot window opens
    --     2. Old code: GetLootSourceInfo(1) → trash mob GUID → no npcDropDB match
    --     3. Rare's loot is in slot 5 → GetLootSourceInfo(5) → rare GUID → never checked!
    --     4. Falls to recentKills/target fallback → unreliable or no match
    --   With multi-source scanning:
    --     2. Collect all unique GUIDs from ALL slots
    --     3. Check each against npcDropDB → rare GUID matches! → process correctly
    -- Must be checked BEFORE UnitGUID("target") to prevent mis-attribution.
    -- ===================================================================
    allSourceGUIDs = GetAllLootSourceGUIDs()
    local numLoot = GetNumLootItems and GetNumLootItems() or 0
    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "ProcessNPCLoot slots=%d sourceGUIDs=%d", numLoot, #allSourceGUIDs) end
    -- When source GUIDs are empty we do NOT defer: we immediately fall through to target/zone.
    -- Deferring to next frame causes misses with fast auto-loot (window closed or target cleared by then).
    if #allSourceGUIDs > 0 then
        hasIdentifiedSource = true

        -- Check each source GUID against databases (prioritize NPC/object matches)
        for _, srcGUID in ipairs(allSourceGUIDs) do
            local typeStr = srcGUID:match("^(%a+)")
            if typeStr == "Creature" or typeStr == "Vehicle" then
                sourceIsCreature = true
            end
            
            if not processedGUIDs[srcGUID] then
                -- Try NPC from loot source
                local npcID = GetNPCIDFromGUID(srcGUID)
                local npcDrops = npcID and npcDropDB[npcID]
                if npcDrops then
                    drops = npcDrops
                    matchedNpcID = npcID
                    dedupGUID = srcGUID
                    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "source: npcID=%s", tostring(npcID)) end
                    break
                end

                -- Try GameObject from loot source
                local objectID = GetObjectIDFromGUID(srcGUID)
                local objDrops = objectID and objectDropDB[objectID]
                if objDrops then
                    drops = objDrops
                    dedupGUID = srcGUID
                    lastMatchedObjectID = objectID
                    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "source: objectID=%s", tostring(objectID)) end
                    break
                end

                -- Track if ANY source is a GameObject (for encounter fallback eligibility)
                if objectID then
                    sourceIsGameObject = true
                end
            end
        end
        -- If no drops found but all sources were already processed, skip entirely
        if not drops then
            local allProcessed = true
            for _, srcGUID in ipairs(allSourceGUIDs) do
                if not processedGUIDs[srcGUID] then
                    allProcessed = false
                    break
                end
            end
            if allProcessed then
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip: all source GUIDs already processed") end
                return
            end
        end

        -- Use the first unprocessed GUID as dedupGUID if we didn't find drops
        if not dedupGUID then
            for _, srcGUID in ipairs(allSourceGUIDs) do
                if not processedGUIDs[srcGUID] then
                    dedupGUID = srcGUID
                    break
                end
            end
        end
    end

    -- ===================================================================
    -- PRIORITY 2: When slots gave no source (rep/currency only) OR only gave generic objects (unrecognized GameObjects)
    -- Try mouseover first (cursor often still over the object you right-clicked), then target, then last-target cache.
    -- We allow P2 if #allSourceGUIDs == 0 OR if we found no drops AND the source was definitely not a creature.
    -- This fixes the issue where an unrecognized Dumpster Object ID yields a GUID but fails P1, bypassing the zone fallback.
    -- ===================================================================
    if not drops and (#allSourceGUIDs == 0 or not sourceIsCreature) then
        local now = GetTime()
        -- Check if loot window is completely empty (no items). If so, bypass processedGUIDs check
        -- because this is likely a "already looted by another player" scenario where we still want to count the attempt.
        local lootIsEmpty = (numLoot == 0)
        
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "P2 fallback: mouseover=%s target=%s lastLoot=%s (age=%.1fs) empty=%s",
            cachedMouseoverGUID and "set" or "nil", cachedTargetGUID and "set" or "nil",
            lastLootSourceGUID and "set" or "nil", lastLootSourceGUID and (now - lastLootSourceTime) or 0, tostring(lootIsEmpty)) end
        local function tryGuidAsSource(guid)
            if not guid then return false end
            -- NOTE: guid is already guarded by Safe* functions (SafeGetUnitGUID, SafeGuardGUID)
            -- before being passed here. GetNPCIDFromGUID and GetObjectIDFromGUID have
            -- additional issecretvalue guards as defense-in-depth (see lines 501, 515).
            -- If loot is empty, bypass processedGUIDs check (likely looted by another player, still count attempt)
            -- If loot has items, respect processedGUIDs to avoid double-counting in same session
            if not lootIsEmpty and processedGUIDs[guid] then return false end
            local nid = GetNPCIDFromGUID(guid)
            drops = nid and npcDropDB[nid]
            if drops then matchedNpcID = nid; dedupGUID = guid; targetGUID = guid; hasIdentifiedSource = true; return true end
            local oid = GetObjectIDFromGUID(guid)
            if oid and objectDropDB[oid] then
                drops = objectDropDB[oid]
                lastMatchedObjectID = oid
                sourceIsGameObject = true
                dedupGUID = guid
                targetGUID = guid
                hasIdentifiedSource = true
                return true
            end
            return false
        end

        -- 2a: Cached mouseover (snapshot at LOOT_OPENED — right-click leaves cursor over object)
        if not drops and cachedMouseoverGUID then
            if tryGuidAsSource(cachedMouseoverGUID) then if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "source: mouseover") end end
        end
        -- 2b: Cached target
        if not drops and cachedTargetGUID then
            if tryGuidAsSource(cachedTargetGUID) then if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "source: target") end end
        end
        -- 2c: Last targeted source (within TTL)
        if not drops and lastLootSourceGUID and (GetTime() - lastLootSourceTime) <= LAST_LOOT_SOURCE_TTL then
            if tryGuidAsSource(lastLootSourceGUID) then if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "source: lastLoot") end end
        end

        if not drops then if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "no match: mouseover/target/lastLoot") end end
    end

    -- Try zone-wide drops if neither NPC nor object matched
    -- Walks up the parent map chain (sub-zone → zone → continent) to find a match
    -- New format: { drops = {...}, raresOnly = true } - check if loot source is rare/elite
    if not drops and next(zoneDropDB) then
        local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local mapID = (rawMapID and (not issecretvalue or not issecretvalue(rawMapID))) and rawMapID or nil
        while mapID and mapID > 0 do
            local zData = zoneDropDB[mapID]
            if zData then
                local zDrops = zData.drops or zData
                local raresOnly = zData.drops and zData.raresOnly == true
                -- If raresOnly, check if loot source is rare/elite before including drops
                if raresOnly then
                    local ok, classification = pcall(UnitClassification, "npc")
                    if ok and classification and (not issecretvalue or not issecretvalue(classification)) then
                        if classification == "rare" or classification == "rareelite" or classification == "worldboss" then
                            drops = zDrops
                        end
                    end
                else
                    drops = zDrops
                end
                if drops then break end
            end
            local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
            local nextID = mapInfo and mapInfo.parentMapID
            mapID = (nextID and (not issecretvalue or not issecretvalue(nextID))) and nextID or nil
        end
    end

    -- Fallback: check recentKills for encounter/CLEU-tracked kills.
    -- Three modes based on source identification:
    --
    -- 1. hasIdentifiedSource = false (GUIDs were secret/nil):
    --    Match BOTH encounter AND CLEU entries (original behavior).
    --
    -- 2. hasIdentifiedSource = true, sourceIsGameObject = true:
    --    Source is a chest/object with a valid GUID not in objectDropDB.
    --    ONLY match ENCOUNTER entries (authoritative boss kills). This handles boss
    --    chests whose objectID isn't in our database (e.g. Sylvanas's chest).
    --    TIME WINDOW: Only match if the encounter kill was within ENCOUNTER_OBJECT_TTL
    --    seconds. Prevents stale encounter entries from matching random environmental
    --    chests opened later in the same instance (e.g. mining node, treasure chest).
    --
    -- 3. hasIdentifiedSource = true, sourceIsGameObject = false:
    --    Source is a known Creature (trash mob) not in npcDropDB.
    --    Block ALL recentKills matching — prevents trash mob loot from being
    --    mis-attributed to a prior boss encounter.
    if not drops then
        local now = GetTime()
        for guid, killData in pairs(recentKills) do
            -- Skip already-processed entries
            if not processedGUIDs[guid] then
                -- Creature source (trash mob) with valid GUID: block fallback entirely
                -- GameObject source (chest) with valid GUID: only match encounter entries within time window
                -- Secret/nil GUIDs: match everything (original behavior)
                local canMatch = false
                if not hasIdentifiedSource then
                    canMatch = true  -- No GUID info: match everything
                elseif killData.isEncounter and sourceIsGameObject then
                    -- Encounter + GameObject: apply time window to prevent stale matches
                    canMatch = (now - killData.time < ENCOUNTER_OBJECT_TTL)
                end
                -- Encounter kills persist until instance exit BUT are bounded by ENCOUNTER_OBJECT_TTL
                -- when matched against identified GameObjects (prevents chest-in-instance false positives).
                -- For secret/nil GUIDs, encounters have no TTL (RP, cinematics, AFK are unbounded).
                -- CLEU kills expire after RECENT_KILL_TTL seconds.
                local alive
                if killData.isEncounter then
                    alive = not hasIdentifiedSource or (now - killData.time < ENCOUNTER_OBJECT_TTL)
                else
                    alive = now - killData.time < RECENT_KILL_TTL
                end
                if canMatch and alive then
                    if killData.zoneMapID then
                        -- Walk parent chain for zone drop matching
                        -- New format: { drops = {...}, raresOnly = true }
                        local zMapID = killData.zoneMapID
                        while zMapID and zMapID > 0 do
                            local zData = zoneDropDB[zMapID]
                            if zData then
                                local zDrops = zData.drops or zData
                                local raresOnly = zData.drops and zData.raresOnly == true
                                -- For raresOnly, encounter kills count as "rare" (boss), others skip
                                if raresOnly and not killData.isEncounter then
                                    -- Non-encounter kill in raresOnly zone: skip
                                else
                                    drops = zDrops
                                end
                            end
                            if drops then break end
                            local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(zMapID)
                            zMapID = mapInfo and mapInfo.parentMapID
                        end
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

    if not drops then
        local recentKillsCount = 0
        for _ in pairs(recentKills) do recentKillsCount = recentKillsCount + 1 end
        if IsTryCounterLootDebugEnabled(self) then
            TryCounterLootDebug(self, "no match: slots=%d sources=%d recentKills=%d (pendingRetry=%s)", numLoot, #allSourceGUIDs, recentKillsCount, tostring(self._pendingEncounterLoot))
        end
        -- DEFERRED RETRY: If we're in an instance and found no drops, ENCOUNTER_END
        -- might not have fired yet (e.g. boss chest spawns during RP/cinematic).
        local inInstance = IsInInstance()
        if issecretvalue and inInstance and issecretvalue(inInstance) then
            inInstance = nil
        end
        if inInstance and not self._pendingEncounterLootRetried then
            self._pendingEncounterLoot = true
        end
        return
    end
    self._pendingEncounterLoot = nil
    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "drops matched") end

    -- Daily/weekly lockout check: if this NPC has a tracking quest and the player
    -- already used their attempt this reset period, skip try count increment.
    -- Must run BEFORE loot scanning to avoid false "missed drop" increments.
    -- matchedNpcID is set when drops came from npcDropDB (not objectDropDB/zoneDropDB).
    local isLockoutSkip = matchedNpcID and IsLockoutDuplicate(matchedNpcID)
    if isLockoutSkip then if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip: lockout npcID=%s", tostring(matchedNpcID)) end end

    -- ===================================================================
    -- HOUSEKEEPING: Mark GUIDs and clean encounter entries BEFORE filtering.
    -- These MUST run even when all drops are collected (#trackable == 0),
    -- otherwise encounter entries leak and block subsequent boss loot in
    -- multi-boss raids, or cause spurious matches on mining/herbing/skinning
    -- LOOT_OPENED events while still inside the instance.
    -- ===================================================================

    -- Mark GUIDs as processed (prevents re-counting on chest reopen)
    -- Record dedupGUID (the GUID that matched drops), ALL source GUIDs, and targetGUID
    -- to prevent duplicate processing from any angle (including AoE loot).
    local now = GetTime()
    if dedupGUID and (type(dedupGUID) ~= "string" or not dedupGUID:match("^zone_")) then
        processedGUIDs[dedupGUID] = now
    end
    -- Mark ALL loot source GUIDs as processed (AoE loot: multiple corpses in one window)
    for _, srcGUID in ipairs(allSourceGUIDs) do
        if not processedGUIDs[srcGUID] then
            processedGUIDs[srcGUID] = now
        end
    end
    if targetGUID and not processedGUIDs[targetGUID] then
        processedGUIDs[targetGUID] = now
    end

    -- Resolve the encounter difficulty from recentKills BEFORE cleanup deletes them.
    -- Used to skip drops whose dropDifficulty doesn't match the kill difficulty.
    local encounterDiffID = nil
    if dedupGUID then
        local killEntry = recentKills[dedupGUID]
        if killEntry and killEntry.difficultyID then
            encounterDiffID = killEntry.difficultyID
        end
    end
    -- Fallback: check other encounter entries for this NPC
    if not encounterDiffID and matchedNpcID then
        for _, killData in pairs(recentKills) do
            if killData.isEncounter and killData.npcID == matchedNpcID and killData.difficultyID then
                encounterDiffID = killData.difficultyID
                break
            end
        end
    end
    -- Last resort: use the current raid/dungeon difficulty setting
    if not encounterDiffID and matchedNpcID then
        local inInstance = IsInInstance()
        if issecretvalue and inInstance and issecretvalue(inInstance) then
            inInstance = nil
        end
        if inInstance then
            local rawDiff = GetRaidDifficultyID and GetRaidDifficultyID()
                or GetDungeonDifficultyID and GetDungeonDifficultyID()
                or nil
            if rawDiff and not (issecretvalue and issecretvalue(rawDiff)) then
                encounterDiffID = rawDiff
            end
        end
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

    -- NPC-level dropDifficulty (e.g. Fyrakk entire entry is "Mythic")
    local npcDropDifficulty = drops.dropDifficulty

    -- Filter drops: repeatable drops are always tracked (even if collected),
    -- non-repeatable drops only tracked if uncollected.
    -- Also skip drops whose difficulty requirement doesn't match the kill difficulty.
    local trackable = {}
    local diffSkipped = nil -- first drop skipped due to difficulty (for feedback)
    for i = 1, #drops do
        local drop = drops[i]
        local reqDiff = drop.dropDifficulty or npcDropDifficulty
        local diffOk = true
        if reqDiff and encounterDiffID then
            diffOk = DoesDifficultyMatch(encounterDiffID, reqDiff)
        end
        if diffOk then
            -- For repeatable items with yields (e.g. Crackling Shard), check if yields are collected
            if not IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        elseif not diffSkipped then
            diffSkipped = { drop = drop, required = reqDiff }
        end
    end
    if #trackable == 0 then
        if diffSkipped then
            local itemLink = GetDropItemLink(diffSkipped.drop)
            local currentLabel = DIFFICULTY_ID_TO_LABELS[encounterDiffID] or tostring(encounterDiffID or "?")
            TryChat(format(
                "|cff9370DB[WN-Counter]|r |cff888888" ..
                ((ns.L and ns.L["TRYCOUNTER_DIFFICULTY_SKIP"]) or "Skipped: %s requires %s difficulty (current: %s)"),
                itemLink, diffSkipped.required, currentLabel
            ))
        end
        return
    end

    -- Scan loot window
    local found = ScanLootForItems(trackable)

    -- Check for repeatable drops that were FOUND in loot -> reset their try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tryKey = GetTryCountKey(drop)
            if tryKey then
                -- Capture try count BEFORE reset (needed for notification message)
                local preResetCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                
                WarbandNexus:ResetTryCount(drop.type, tryKey)
                
                -- Set debounce key to prevent CHAT_MSG_LOOT from also resetting (if item type is "item")
                if drop.type == "item" then
                    lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    lastTryCountSourceTime = GetTime()
                end
                
                local itemLink = GetDropItemLink(drop)
                TryChat("|cff9370DB[WN-Counter]|r " .. format((ns.L and ns.L["TRYCOUNTER_OBTAINED_RESET"]) or "Obtained %s! Try counter reset.", itemLink))
                
                -- Store pre-reset count for mount/pet/toy so CollectionService's
                -- later WN_COLLECTIBLE_OBTAINED can read it (via OnTryCounterCollectibleObtained)
                if drop.type ~= "item" and preResetCount and preResetCount > 0 then
                    local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                
                -- Fire notification for item-type drops (mounts/pets/toys are handled by CollectionService)
                if drop.type == "item" and WarbandNexus.SendMessage then
                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                    WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                        type = "item",
                        id = drop.itemID,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                    })
                end
            end
        end
    end

    -- Non-repeatable drops FOUND in loot (e.g. mount from boss, quest item):
    -- DON'T reset counter - these are one-time drops, counter shows total attempts made.
    -- Store current count for notification, then mark as collected (IsCollectibleCollected will prevent future increments).
    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and found[drop.itemID] then
            local tryKey = GetTryCountKey(drop)
            if tryKey then
                -- Capture current try count for notification (don't reset!)
                local currentCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                
                -- Store current count so notification shows "You got it after X tries!"
                if drop.type ~= "item" and currentCount and currentCount > 0 then
                    local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = currentCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                
                -- Fire notification immediately for mount/pet/toy drops (don't wait for NEW_*_ADDED)
                if drop.type ~= "item" then
                    local itemLink = GetDropItemLink(drop)
                    TryChat("|cff9370DB[WN-Counter]|r " .. format((ns.L and ns.L["TRYCOUNTER_OBTAINED"]) or "Obtained %s!", itemLink))
                    
                    -- Fire WN_COLLECTIBLE_OBTAINED for notification toast
                    if WarbandNexus.SendMessage then
                        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                        WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                            type = drop.type,
                            id = tryKey,
                            name = itemName or drop.name or "Unknown",
                            icon = itemIcon,
                            preResetTryCount = currentCount, -- Shows "You got it after X tries!"
                        })
                    end
                end
                
                -- For quest-starter mounts (e.g. Stonevault Mechsuit), mirror count to mount
                if drop.type == "item" and drop.questStarters then
                    for _, qs in ipairs(drop.questStarters) do
                        if qs.type == "mount" and qs.itemID then
                            local k1 = ResolveCollectibleID(qs)
                            local k2 = qs.itemID
                            -- Store count for quest-starter mount
                            if currentCount and currentCount > 0 then
                                local mountCacheKey = "mount\0" .. tostring(k1 or k2)
                                pendingPreResetCounts[mountCacheKey] = currentCount
                                C_Timer.After(30, function() pendingPreResetCounts[mountCacheKey] = nil end)
                                if k1 and k1 ~= k2 then
                                    local mountCacheKey2 = "mount\0" .. tostring(k2)
                                    pendingPreResetCounts[mountCacheKey2] = currentCount
                                    C_Timer.After(30, function() pendingPreResetCounts[mountCacheKey2] = nil end)
                                end
                            end
                            
                            -- Fire notification for quest-starter mount item
                            local itemLink = GetDropItemLink(drop)
                            TryChat("|cff9370DB[WN-Counter]|r " .. format((ns.L and ns.L["TRYCOUNTER_OBTAINED"]) or "Obtained %s!", itemLink))
                            
                            if WarbandNexus.SendMessage then
                                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                                WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                                    type = "item",
                                    id = drop.itemID,
                                    name = itemName or drop.name or "Unknown",
                                    icon = itemIcon,
                                    preResetTryCount = currentCount,
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- For ALL mounts/pets/toys in trackable list (repeatable OR non-repeatable):
    -- Capture current try count BEFORE any increment happens.
    -- This handles:
    --   1. BoP items that auto-collect (never appear in loot window)
    --   2. Items that go to bags first (will be in loot window)
    -- The increment happens later in ProcessMissedDrops (for items NOT found in loot).
    -- When NEW_MOUNT/PET/TOY_ADDED fires, OnTryCounterCollectibleObtained reads from this cache.
    for i = 1, #trackable do
        local drop = trackable[i]
        -- Skip repeatable items (already handled above with reset logic)
        -- Skip "item" type (generic items use different flow)
        if not drop.repeatable and drop.type ~= "item" then
            local tryKey = GetTryCountKey(drop)
            if tryKey then
                local currentCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                -- Store current count (will be used if item is obtained)
                -- If item is NOT obtained, ProcessMissedDrops will increment and this cache entry is ignored
                pendingPreResetCounts[cacheKey] = currentCount
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
            end
        end
    end

    -- If lockout duplicate, skip try count increment entirely.
    -- GUID processing and encounter cleanup above still run (dedup must happen regardless),
    -- but we don't increment the try counter for a kill that can't drop the rare item.
    if isLockoutSkip then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip: lockout") end
        TryChat("|cff9370DB[WN-Counter]|r |cff888888" .. ((ns.L and ns.L["TRYCOUNTER_LOCKOUT_SKIP"]) or "Skipped: daily/weekly lockout active for this NPC."))
        return
    end

    -- Build list to increment: both repeatable and non-repeatable drops only increment when NOT found in loot.
    local dropsToIncrement = {}
    for i = 1, #trackable do
        local drop = trackable[i]
        if not found[drop.itemID] then
            dropsToIncrement[#dropsToIncrement + 1] = drop
        end
    end
    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "increment: %d drop(s)", #dropsToIncrement) end

    -- If we already counted this encounter from ENCOUNTER_END delayed (no loot opened), do not increment again.
    -- CRITICAL: Only skip INCREMENT, not reset! If mount dropped, reset must run even if already incremented.
    if #dropsToIncrement > 0 and matchedNpcID then
        -- First check if this NPC is part of an encounter
        local encounterID = nil
        for encID, npcList in pairs(encounterDB or {}) do
            for _, nid in ipairs(npcList) do
                if nid == matchedNpcID then
                    encounterID = encID
                    break
                end
            end
            if encounterID then break end
        end
        
        -- If this is an encounter, use encounter-based dedup
        if encounterID then
            local encKey = "encounter_" .. tostring(encounterID)
            if lastTryCountSourceKey == encKey and (GetTime() - lastTryCountSourceTime) < 15 then
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip increment: already counted encounter %s", tostring(encounterID)) end
                dropsToIncrement = {} -- Clear increment list but continue to set dedup key
            end
        else
            -- Non-encounter NPC, use NPC-based dedup
            local npcKey = "encounter_" .. tostring(matchedNpcID)
            if lastTryCountSourceKey == npcKey and (GetTime() - lastTryCountSourceTime) < 15 then
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip increment: already counted npc %s", tostring(matchedNpcID)) end
                dropsToIncrement = {} -- Clear increment list but continue to set dedup key
            end
        end
    end

    -- Set dedup key: prefer encounter ID if available, otherwise use NPC/object/GUID
    if matchedNpcID then
        -- Check if this NPC is part of an encounter
        local encounterID = nil
        for encID, npcList in pairs(encounterDB or {}) do
            for _, nid in ipairs(npcList) do
                if nid == matchedNpcID then
                    encounterID = encID
                    break
                end
            end
            if encounterID then break end
        end
        
        if encounterID then
            lastTryCountSourceKey = "encounter_" .. tostring(encounterID)
        else
            lastTryCountSourceKey = "npc_" .. tostring(matchedNpcID)
        end
    elseif lastMatchedObjectID then
        lastTryCountSourceKey = "obj_" .. tostring(lastMatchedObjectID)
    elseif dedupGUID and type(dedupGUID) == "string" then
        lastTryCountSourceKey = dedupGUID
    else
        lastTryCountSourceKey = nil
    end
    lastTryCountSourceTime = GetTime()

    -- Increment try counts. Pass statisticIds if the source NPC has them — ProcessMissedDrops
    -- will use Statistics API instead of manual increment to avoid double-counting.
    local statIds = drops and drops.statisticIds or nil
    ProcessMissedDrops(dropsToIncrement, statIds)
end

---Process loot from fishing
---For repeatable fishing mounts: resets try count when mount is caught (found in loot).
---For non-repeatable: increments on every fish where mount is NOT caught.
function WarbandNexus:ProcessFishingLoot()
    -- Get current zone (Midnight 12.0: mapID may be secret in some contexts)
    local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = (rawMapID and (not issecretvalue or not issecretvalue(rawMapID))) and rawMapID or nil

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

    -- For repeatable fishing mounts/items, check if yields are collected first.
    -- If all yields are collected (e.g. Alunira from Crackling Shard), stop tracking.
    -- Otherwise, track for AH sale or continued farming.
    local trackable = {}
    for i = 1, #drops do
        local drop = drops[i]
        -- For repeatable items with yields (e.g. Crackling Shard), check if yields are collected
        if not IsCollectibleCollected(drop) then
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
                local preResetCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                WarbandNexus:ResetTryCount(drop.type, tryKey)
                
                -- Set debounce key to prevent CHAT_MSG_LOOT from also resetting (if item type is "item")
                if drop.type == "item" then
                    lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    lastTryCountSourceTime = GetTime()
                end
                
                if drop.type ~= "item" and preResetCount and preResetCount > 0 then
                    local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = GetDropItemLink(drop)
                TryChat("|cff9370DB[WN-Counter]|r " .. format((ns.L and ns.L["TRYCOUNTER_CAUGHT_RESET"]) or "Caught %s! Try counter reset.", itemLink))
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

        -- Filter: check if yields are collected for repeatable items
        local trackable = {}
        for i = 1, #drops do
            local drop = drops[i]
            -- For repeatable items with yields (e.g. Crackling Shard), check if yields are collected
            if not IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        end
        if #trackable == 0 then return end

        -- Scan loot window
        local found = ScanLootForItems(trackable)

        -- Check for drops that were FOUND in loot (repeatable or not) -> reset try count, store preReset for notification
        for i = 1, #trackable do
            local drop = trackable[i]
            if found[drop.itemID] then
                local tryKey = GetTryCountKey(drop)
                if tryKey then
                    -- Populate resolvedIDs so IsDropSourceCollectible(mountID) works when CollectionService fires later
                    ResolveCollectibleID(drop)
                    -- Capture try count BEFORE reset (needed for "first try" / "X tries" in notification)
                    local preResetCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                    WarbandNexus:ResetTryCount(drop.type, tryKey)
                    if drop.type == "item" and drop.questStarters then
                        for _, qs in ipairs(drop.questStarters) do
                            if qs.type == "mount" and qs.itemID then
                                local k1 = ResolveCollectibleID(qs)
                                local k2 = qs.itemID
                                WarbandNexus:ResetTryCount("mount", k1 or k2)
                                if k1 and k1 ~= k2 then
                                    WarbandNexus:ResetTryCount("mount", k2)
                                end
                            end
                        end
                    end
                    -- Set debounce key to prevent CHAT_MSG_LOOT from also resetting (if item type is "item")
                    if drop.type == "item" then
                        lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                        lastTryCountSourceTime = GetTime()
                    end
                    -- Store preResetCount for mount/pet/toy (including 0 = first try) so notification shows correct message and flash
                    if drop.type ~= "item" then
                        local nativeID = ResolveCollectibleID(drop) or tryKey
                        local cacheKey = drop.type .. "\0" .. tostring(nativeID)
                        pendingPreResetCounts[cacheKey] = preResetCount or 0
                        C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                    end
                    local itemLink = GetDropItemLink(drop)
                    TryChat("|cff9370DB[WN-Counter]|r " .. format((ns.L and ns.L["TRYCOUNTER_CONTAINER_RESET"]) or "Obtained %s from container! Try counter reset.", itemLink))
                    
                    -- Fire notification for item-type drops (mounts/pets/toys are handled by CollectionService)
                    if drop.type == "item" and WarbandNexus.SendMessage then
                        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                        WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                            type = "item",
                            id = drop.itemID,
                            name = itemName or drop.name or "Unknown",
                            icon = itemIcon,
                            preResetTryCount = preResetCount,
                        })
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

    -- Fallback: container not identified via ITEM_LOCK_CHANGED (required for try count).
    -- Scan all container drops passively (no try count increment).
    -- Inferring container from loot slot item is error-prone; we do not increment without a known container.
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

    -- Inject pending pre-reset count (container or NPC loot reset) so notification can show "first try" / "X tries" and flash
    local cacheKey = data.type .. "\0" .. tostring(data.id)
    local pendingCount = pendingPreResetCounts[cacheKey]
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
    if data.type == "toy" or data.type == "item" then return end

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
    -- zoneDropDB supports new format: { drops = {...}, raresOnly = true }
    for _, sourceTable in pairs(flatSources) do
        for _, entry in pairs(sourceTable) do
            if type(entry) == "table" then
                -- New format: { drops = {...}, raresOnly = true }
                local drops = entry.drops or entry
                if type(drops) == "table" then
                    for _, drop in ipairs(drops) do
                        if TryMigrateDrop(drop) then return end
                    end
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
-- TRACKDB MERGE (Custom entries overlay on CollectibleSourceDB)
-- =====================================================================

--- Merge user-defined custom entries into runtime DB tables and
--- remove entries the user has disabled. Called from InitializeTryCounter
--- BEFORE BuildReverseIndices() so indices include custom entries.
local function MergeTrackDB()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    local trackDB = WarbandNexus.db.global.trackDB
    if not trackDB then return end

    -- 1) Merge custom NPC entries into npcDropDB
    local customNpcs = trackDB.custom and trackDB.custom.npcs
    if customNpcs then
        for npcID, drops in pairs(customNpcs) do
            npcID = tonumber(npcID)
            if npcID and type(drops) == "table" then
                if not npcDropDB[npcID] then
                    npcDropDB[npcID] = {}
                end
                local existing = npcDropDB[npcID]
                for i = 1, #drops do
                    local drop = drops[i]
                    if drop and drop.itemID then
                        local found = false
                        for j = 1, #existing do
                            if existing[j].itemID == drop.itemID then
                                found = true
                                break
                            end
                        end
                        if not found then
                            existing[#existing + 1] = drop
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
                if not objectDropDB[objectID] then
                    objectDropDB[objectID] = {}
                end
                local existing = objectDropDB[objectID]
                for i = 1, #drops do
                    local drop = drops[i]
                    if drop and drop.itemID then
                        local found = false
                        for j = 1, #existing do
                            if existing[j].itemID == drop.itemID then
                                found = true
                                break
                            end
                        end
                        if not found then
                            existing[#existing + 1] = drop
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
                    db = npcDropDB
                elseif sourceType == "object" then
                    db = objectDropDB
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

-- =====================================================================
-- STATISTICS SEEDING (WoW Achievement Statistics API)
-- =====================================================================

--- Seed try counts from WoW's Statistics system (GetStatistic).
--- Per-character accumulation: each character's stats are stored separately,
--- then summed across ALL characters to get the true global total.
--- Only increases existing counts - never decreases.
--- Uses time-budgeted batching to prevent frame spikes.
--- Called once on login with a delay to let APIs warm up.
local SEED_BUDGET_MS = 3  -- max milliseconds per batch frame

local function SeedFromStatistics()
    if not EnsureDB() then return end
    local GetStat = GetStatistic
    if not GetStat then return end
    local P = ns.Profiler
    if P then P:StartAsync("SeedFromStatistics") end
    local LT = ns.LoadingTracker
    if LT then LT:Register("trycounts", (ns.L and ns.L["TRYCOUNTER_TRY_COUNTS"]) or "Try Counts") end

    local charKey
    if ns.Utilities and ns.Utilities.GetCharacterKey then
        charKey = ns.Utilities:GetCharacterKey()
    else
        local name = UnitName("player")
        local realm = GetRealmName()
        if name and realm then
            charKey = name:gsub("%s+", "") .. "-" .. realm:gsub("%s+", "")
        end
    end
    if not charKey then return end

    local snapshots = WarbandNexus.db.global.statisticSnapshots
    if not snapshots then
        WarbandNexus.db.global.statisticSnapshots = {}
        snapshots = WarbandNexus.db.global.statisticSnapshots
    end
    if not snapshots[charKey] then
        snapshots[charKey] = {}
    end
    local charSnapshot = snapshots[charKey]

    -- Collect all NPC entries with statisticIds into a flat list for batched processing
    local npcQueue = {}
    for npcID, npcData in pairs(npcDropDB) do
        if npcData.statisticIds then
            npcQueue[#npcQueue + 1] = { npcID = npcID, data = npcData }
        end
    end

    local queueIdx = 1
    local seeded = 0
    local unresolvedDrops = {}

    local function ProcessBatch()
        if not EnsureDB() then return end
        local batchStart = debugprofilestop()

        while queueIdx <= #npcQueue do
            local entry = npcQueue[queueIdx]
            local npcData = entry.data
            local statIds = npcData.statisticIds

            local thisCharTotal = 0
            for _, sid in ipairs(statIds) do
                local val = GetStat(sid)
                local num
                if val and not (issecretvalue and issecretvalue(val)) then
                    num = tonumber(val)
                end
                if num and num > 0 then
                    thisCharTotal = thisCharTotal + num
                end
            end

            local function ProcessBatchDrop(drop)
                if not drop.guaranteed then
                    local tryKey = ResolveCollectibleID(drop) or GetTryCountKey(drop)
                    if tryKey then
                        charSnapshot[tryKey] = thisCharTotal
                        local globalTotal = 0
                        for _, snap in pairs(snapshots) do
                            local charVal = snap[tryKey]
                            if charVal and charVal > 0 then
                                globalTotal = globalTotal + charVal
                            end
                        end
                        local currentCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                        if globalTotal > currentCount then
                            WarbandNexus:SetTryCount(drop.type, tryKey, globalTotal)
                            -- Quest-item mounts (e.g. Malfunctioning Mechsuit -> Stonevault Mechsuit): mirror Statistics to mount
                            if drop.type == "item" and drop.questStarters then
                                for _, qs in ipairs(drop.questStarters) do
                                    if qs and qs.type == "mount" and qs.itemID then
                                        local k1 = ResolveCollectibleID(qs)
                                        local k2 = qs.itemID
                                        WarbandNexus:SetTryCount("mount", k1 or k2, globalTotal)
                                        if k1 and k1 ~= k2 then
                                            WarbandNexus:SetTryCount("mount", k2, globalTotal)
                                        end
                                        questStarterMountToSourceItemID[k1 or k2] = drop.itemID
                                        if k1 and k1 ~= k2 then questStarterMountToSourceItemID[k2] = drop.itemID end
                                    end
                                end
                            end
                            seeded = seeded + 1
                        end
                    else
                        unresolvedDrops[#unresolvedDrops + 1] = {
                            drop = drop,
                            thisCharTotal = thisCharTotal,
                        }
                    end
                end
                if drop and drop.questStarters then
                    for _, qs in ipairs(drop.questStarters) do
                        ProcessBatchDrop(qs)
                    end
                end
            end

            for _, drop in ipairs(npcData) do
                ProcessBatchDrop(drop)
            end

            queueIdx = queueIdx + 1

            if debugprofilestop() - batchStart > SEED_BUDGET_MS then
                C_Timer.After(0, ProcessBatch)
                return
            end
        end

        -- All NPCs processed — finalize
        if P then P:StopAsync("SeedFromStatistics") end
        if LT then LT:Complete("trycounts") end
        if seeded > 0 then
            WarbandNexus:Debug("TryCounter: Seeded %d entries from WoW Statistics (char: %s)", seeded, charKey)
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_PLANS_UPDATED", { action = "statistics_seeded" })
            end
        end

        -- Retry unresolved drops after 10s
        if #unresolvedDrops > 0 then
            WarbandNexus:Debug("TryCounter: %d drops unresolved, retrying in 10s...", #unresolvedDrops)
            C_Timer.After(10, function()
                if not EnsureDB() then return end
                local retrySeeded = 0
                local stillUnresolved = {}
                for _, uEntry in ipairs(unresolvedDrops) do
                    local drop = uEntry.drop
                    local tryKey = ResolveCollectibleID(drop)
                    if tryKey then
                        charSnapshot[tryKey] = uEntry.thisCharTotal
                        local globalTotal = 0
                        for _, snap in pairs(snapshots) do
                            local charVal = snap[tryKey]
                            if charVal and charVal > 0 then
                                globalTotal = globalTotal + charVal
                            end
                        end
                        local currentCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                        if globalTotal > currentCount then
                            WarbandNexus:SetTryCount(drop.type, tryKey, globalTotal)
                            retrySeeded = retrySeeded + 1
                        end
                    else
                        stillUnresolved[#stillUnresolved + 1] = uEntry
                    end
                end
                if retrySeeded > 0 then
                    WarbandNexus:Debug("TryCounter: Retry resolved %d / %d entries", retrySeeded, #unresolvedDrops)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage("WN_PLANS_UPDATED", { action = "statistics_seeded" })
                    end
                end

                if #stillUnresolved > 0 then
                    WarbandNexus:Debug("TryCounter: %d still unresolved, final retry in 30s...", #stillUnresolved)
                    C_Timer.After(30, function()
                        if not EnsureDB() then return end
                        local finalSeeded = 0
                        local snaps = WarbandNexus.db.global.statisticSnapshots
                        for _, fEntry in ipairs(stillUnresolved) do
                            local drop = fEntry.drop
                            local finalKey = ResolveCollectibleID(drop)
                            if finalKey and snaps then
                                if snaps[charKey] then
                                    snaps[charKey][finalKey] = fEntry.thisCharTotal
                                end
                                local total = 0
                                for _, snap in pairs(snaps) do
                                    local v = snap[finalKey]
                                    if v and v > 0 then total = total + v end
                                end
                                local cur = WarbandNexus:GetTryCount(drop.type, finalKey)
                                if total > cur then
                                    WarbandNexus:SetTryCount(drop.type, finalKey, total)
                                    finalSeeded = finalSeeded + 1
                                end
                            end
                        end
                        if finalSeeded > 0 then
                            WarbandNexus:Debug("TryCounter: Final retry resolved %d / %d entries", finalSeeded, #stillUnresolved)
                            if WarbandNexus.SendMessage then
                                WarbandNexus:SendMessage("WN_PLANS_UPDATED", { action = "statistics_seeded" })
                            end
                        end
                    end)
                end
            end)
        end
    end

    ProcessBatch()
end

-- =====================================================================
-- CRUD API (Track Item DB management)
-- =====================================================================

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

--- Rebuild runtime DB from CollectibleSourceDB + trackDB overlays.
--- Clears caches, re-loads DB references, merges custom/disabled, rebuilds indices.
function WarbandNexus:RebuildTrackDB()
    -- Reset reverse indices so they get rebuilt
    reverseIndicesBuilt = false
    guaranteedIndex = {}
    repeatableIndex = {}
    dropSourceIndex = {}
    dropDifficultyIndex = {}
    repeatableItemDrops = {}
    difficultyCache = {}

    -- Re-load from static CollectibleSourceDB (fresh copy of built-in data)
    local db = ns.CollectibleSourceDB
    if db then
        -- Deep-copy NPC and Object tables so we don't mutate the static DB
        npcDropDB = {}
        for k, v in pairs(db.npcs or {}) do
            local copy = {}
            for i = 1, #v do copy[i] = v[i] end
            if v.statisticIds then copy.statisticIds = v.statisticIds end
            if v.dropDifficulty then copy.dropDifficulty = v.dropDifficulty end
            npcDropDB[k] = copy
        end
        for k, v in pairs(db.rares or {}) do
            if not npcDropDB[k] then
                local copy = {}
                for i = 1, #v do copy[i] = v[i] end
                if v.statisticIds then copy.statisticIds = v.statisticIds end
                if v.dropDifficulty then copy.dropDifficulty = v.dropDifficulty end
                npcDropDB[k] = copy
            end
        end
        objectDropDB = {}
        for k, v in pairs(db.objects or {}) do
            local copy = {}
            for i = 1, #v do copy[i] = v[i] end
            objectDropDB[k] = copy
        end
        fishingDropDB = db.fishing or {}
        containerDropDB = db.containers or {}
        zoneDropDB = db.zones or {}
        encounterDB = db.encounters or {}
        lockoutQuestsDB = db.lockoutQuests or {}
    end

    -- Apply custom entries + disabled entries
    MergeTrackDB()

    -- Rebuild O(1) lookup indices
    BuildReverseIndices()
end

-- =====================================================================
-- INITIALIZATION
-- =====================================================================

---Initialize the automatic try counter system
function WarbandNexus:InitializeTryCounter()
    EnsureDB()

    -- Load DB references (initial load from static CollectibleSourceDB)
    local db = ns.CollectibleSourceDB
    if db then
        -- Deep-copy NPC and Object tables so MergeTrackDB can safely mutate them
        npcDropDB = {}
        for k, v in pairs(db.npcs or {}) do
            local copy = {}
            for i = 1, #v do copy[i] = v[i] end
            if v.statisticIds then copy.statisticIds = v.statisticIds end
            if v.dropDifficulty then copy.dropDifficulty = v.dropDifficulty end
            npcDropDB[k] = copy
        end
        for k, v in pairs(db.rares or {}) do
            if not npcDropDB[k] then
                local copy = {}
                for i = 1, #v do copy[i] = v[i] end
                if v.statisticIds then copy.statisticIds = v.statisticIds end
                if v.dropDifficulty then copy.dropDifficulty = v.dropDifficulty end
                npcDropDB[k] = copy
            end
        end
        objectDropDB = {}
        for k, v in pairs(db.objects or {}) do
            local copy = {}
            for i = 1, #v do copy[i] = v[i] end
            objectDropDB[k] = copy
        end
        fishingDropDB = db.fishing or {}
        containerDropDB = db.containers or {}
        zoneDropDB = db.zones or {}
        encounterDB = db.encounters or {}
        lockoutQuestsDB = db.lockoutQuests or {}
    end

    -- Merge user-defined custom entries and remove disabled entries
    -- BEFORE building reverse indices so custom items are queryable.
    MergeTrackDB()

    -- Build reverse lookup indices for O(1) Is*Collectible() queries.
    -- Must run AFTER DB references are loaded and trackDB is merged.
    BuildReverseIndices()

    -- Sync lockout state with server quest flags (prevents false increments after /reload mid-farm)
    SyncLockoutState()

    -- Pre-resolve mount/pet IDs for all known drop items (warmup cache for SeedFromStatistics)
    -- This ensures resolvedIDs is populated before statistics seeding runs.
    -- Delayed 5s (absolute ~T+6.5s). Time-budgeted to prevent frame spikes.
    C_Timer.After(5, function()
        local RESOLVE_BUDGET_MS = 3
        local resolveQueue = {}
        for _, npcData in pairs(npcDropDB) do
            if npcData.statisticIds then
                for _, drop in ipairs(npcData) do
                    if drop.itemID and not resolvedIDs[drop.itemID] then
                        resolveQueue[#resolveQueue + 1] = drop
                    end
                end
            end
        end
        
        local idx = 1
        local preResolved = 0
        local function ResolveBatch()
            local batchStart = debugprofilestop()
            while idx <= #resolveQueue do
                local rid = ResolveCollectibleID(resolveQueue[idx])
                if rid then
                    preResolved = preResolved + 1
                end
                idx = idx + 1
                if debugprofilestop() - batchStart > RESOLVE_BUDGET_MS then
                    C_Timer.After(0, ResolveBatch)
                    return
                end
            end
            if preResolved > 0 then
                WarbandNexus:Debug("TryCounter: Pre-resolved %d mount/pet IDs for statistics seeding", preResolved)
            end
        end
        ResolveBatch()
    end)

    -- Seed try counts from WoW Statistics API.
    -- Mount/Pet journal APIs may not resolve itemID→mountID/speciesID immediately.
    -- Only increases counts - never decreases. Safe to run every login.
    -- Delayed 10s (absolute ~T+11.5s) — gives pre-resolve (+5s) ~5s to complete.
    C_Timer.After(10, SeedFromStatistics)

    -- Sync lockout state with server quest flags (clean stale + pre-populate).
    -- Delayed 2s to ensure quest log data is available after login/reload.
    C_Timer.After(2, SyncLockoutState)

    -- Ensure events are registered (at load if allowed; retry here if load was in protected context).
    RegisterTryCounterEvents()
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
-- DEBUG: Try counter state simulation (/wn trydebug)
-- =====================================================================

---Print current try-counter state to chat (instance, difficulty, loot sources, target, recentKills, zone, Statistics).
---Uses guarded APIs; secret values are shown as "(secret)". Call from /wn trydebug when debug mode is on.
function WarbandNexus:TryCounterDebugReport()
    local WN = self
    local function msg(s) TryChat("|cff9370DB[WN-TryDebug]|r " .. s) end
    local function safeStr(v)
        if v == nil then return "nil" end
        if issecretvalue and issecretvalue(v) then return "(secret)" end
        return tostring(v)
    end

    -- 1. Instance / zone
    local inInst, instType = IsInInstance()
    if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
    if issecretvalue and instType and issecretvalue(instType) then instType = nil end
    msg("Instance: inInstance=" .. safeStr(inInst) .. " type=" .. safeStr(instType))
    local name, typ, diffID, diffName, maxPlayers, dynamic, isDyn, instanceID = GetInstanceInfo()
    msg("  GetInstanceInfo: name=" .. safeStr(name) .. " instanceType=" .. safeStr(typ) .. " difficultyID=" .. safeStr(diffID) .. " instanceID=" .. safeStr(instanceID))

    -- 2. Difficulty
    local raidDiff = GetRaidDifficultyID and GetRaidDifficultyID()
    local dungeonDiff = GetDungeonDifficultyID and GetDungeonDifficultyID()
    if issecretvalue and raidDiff and issecretvalue(raidDiff) then raidDiff = nil end
    if issecretvalue and dungeonDiff and issecretvalue(dungeonDiff) then dungeonDiff = nil end
    local raidLabel = (raidDiff and DIFFICULTY_ID_TO_LABELS[raidDiff]) or "(unknown)"
    local dungeonLabel = (dungeonDiff and DIFFICULTY_ID_TO_LABELS[dungeonDiff]) or "(unknown)"
    msg("Difficulty: raid=" .. safeStr(raidDiff) .. " (" .. raidLabel .. ") dungeon=" .. safeStr(dungeonDiff) .. " (" .. dungeonLabel .. ")")

    -- 3. Loot window
    local numLoot = GetNumLootItems and GetNumLootItems() or 0
    msg("Loot window: " .. numLoot .. " slots")
    for slot = 1, numLoot do
        local sources = GetLootSourceInfo and { GetLootSourceInfo(slot) } or {}
        local guid = sources[1]
        local safeGuid = guid and SafeGuardGUID(guid) or nil
        local guidStr = safeStr(guid)
        if safeGuid then
            local nid = GetNPCIDFromGUID(safeGuid)
            local oid = GetObjectIDFromGUID(safeGuid)
            local inNpc = nid and npcDropDB[nid] and "yes" or "no"
            local inObj = oid and objectDropDB[oid] and "yes" or "no"
            msg("  slot " .. slot .. ": guid=" .. guidStr .. " npcID=" .. safeStr(nid) .. " inNpcDB=" .. inNpc .. " objectID=" .. safeStr(oid) .. " inObjDB=" .. inObj)
        else
            msg("  slot " .. slot .. ": guid=" .. guidStr)
        end
    end

    -- 4. Target
    local tg = UnitGUID and UnitGUID("target")
    local safeTg = tg and SafeGuardGUID(tg) or nil
    msg("Target GUID: " .. safeStr(tg))
    if safeTg then
        local nid = GetNPCIDFromGUID(safeTg)
        local oid = GetObjectIDFromGUID(safeTg)
        msg("  npcID=" .. safeStr(nid) .. " inNpcDB=" .. (nid and npcDropDB[nid] and "yes" or "no") .. " objectID=" .. safeStr(oid) .. " inObjDB=" .. (oid and objectDropDB[oid] and "yes" or "no"))
    end

    -- 5. recentKills (sample)
    local count = 0
    for guid, data in pairs(recentKills) do
        if count >= 2 then break end
        count = count + 1
        local diffStr = data.difficultyID
        if diffStr ~= nil and issecretvalue and issecretvalue(diffStr) then diffStr = "(secret)" end
        if diffStr == nil then diffStr = "nil" elseif diffStr ~= "(secret)" then diffStr = tostring(diffStr) end
        msg("recentKills sample: npcID=" .. tostring(data.npcID) .. " isEncounter=" .. tostring(data.isEncounter) .. " difficultyID=" .. diffStr)
    end
    if count == 0 then msg("recentKills: (empty)") end

    -- 6. Map / zone (guard mapID for 12.0)
    local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = (rawMapID and (not issecretvalue or not issecretvalue(rawMapID))) and rawMapID or nil
    msg("Map: mapID=" .. safeStr(mapID) .. " zoneDropDB[mapID]=" .. (mapID and zoneDropDB[mapID] and "yes" or "no"))
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        local parent = info and info.parentMapID
        if parent then
            msg("  parentMapID=" .. tostring(parent) .. " zoneDropDB[parent]=" .. (zoneDropDB[parent] and "yes" or "no"))
        end
    end

    -- 7. Statistics (sample)
    local sampleStatIds = {}
    for npcID, data in pairs(npcDropDB) do
        if data.statisticIds and #data.statisticIds > 0 then
            for i = 1, math.min(2, #data.statisticIds) do
                sampleStatIds[#sampleStatIds + 1] = data.statisticIds[i]
            end
            if #sampleStatIds >= 2 then break end
        end
    end
    for _, sid in ipairs(sampleStatIds) do
        local val = GetStatistic(sid)
        local display = "(secret)"
        if val ~= nil and not (issecretvalue and issecretvalue(val)) then
            display = tostring(val)
        end
        msg("GetStatistic(" .. sid .. ")=" .. display)
    end
    if #sampleStatIds == 0 then msg("GetStatistic: (no sample stat IDs in DB)") end
end

-- =====================================================================
-- CHECK TARGET DROPS (debug helper)
-- =====================================================================

---Check what collectibles drop from current target or mouseover
---Prints detailed info about NPC/Object drops, encounter mapping, and collection status
function WarbandNexus:CheckTargetDrops()
    local function msg(text) self:Print("|cff9370DB[WN-DropCheck]|r " .. text) end
    local function safeStr(val) return val and tostring(val) or "nil" end
    
    -- Try mouseover first, then target (use SafeGetUnitGUID to avoid secret values)
    local unit = "mouseover"
    local guid = SafeGetUnitGUID(unit)
    if not guid then
        unit = "target"
        guid = SafeGetUnitGUID(unit)
    end
    
    if not guid then
        msg("|cffff6600No valid target or mouseover unit found.|r")
        msg("Target an NPC or GameObject and try again.")
        msg("|cff888888(In instances, target GUIDs may be restricted)|r")
        return
    end
    
    -- Get unit name (guard against secret values)
    local unitName = UnitName(unit) or "Unknown"
    if issecretvalue and issecretvalue(unitName) then unitName = "Unknown" end
    
    -- Check if it's an NPC or GameObject (GUID is already safe from SafeGetUnitGUID)
    local npcID = GetNPCIDFromGUID(guid)
    local objectID = GetObjectIDFromGUID(guid)
    
    if not npcID and not objectID then
        msg("|cffff6600Not a valid NPC or GameObject.|r")
        msg("GUID: " .. safeStr(guid))
        return
    end
    
    msg("|cff00ccff" .. unitName .. "|r")
    msg("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
    
    -- NPC drops
    if npcID then
        msg("Type: |cff00ff00NPC|r")
        msg("NPC ID: |cffffff00" .. npcID .. "|r")
        
        local drops = npcDropDB[npcID]
        if drops then
            msg("|cff00ff00✓ This NPC has tracked drops!|r")
            msg("")
            
            -- Check if it's a boss with encounter mapping
            local encounterIDs = {}
            for encID, npcList in pairs(encounterDB or {}) do
                for _, nid in ipairs(npcList) do
                    if nid == npcID then
                        encounterIDs[#encounterIDs + 1] = encID
                        break
                    end
                end
            end
            
            if #encounterIDs > 0 then
                msg("|cffff8800Boss Encounter|r (ID: " .. table.concat(encounterIDs, ", ") .. ")")
                msg("")
            end
            
            -- List all drops
            local dropCount = 0
            for i = 1, #drops do
                local drop = drops[i]
                if drop.type and drop.itemID and drop.name then
                    dropCount = dropCount + 1
                    
                    local typeIcon = ""
                    if drop.type == "mount" then typeIcon = "🐎"
                    elseif drop.type == "pet" then typeIcon = "🐾"
                    elseif drop.type == "toy" then typeIcon = "🎲"
                    elseif drop.type == "item" then typeIcon = "📦"
                    end
                    
                    local flags = {}
                    if drop.guaranteed then flags[#flags + 1] = "|cff00ff00Guaranteed|r" end
                    if drop.repeatable then flags[#flags + 1] = "|cffff8800Repeatable|r" end
                    if drop.dropDifficulty then flags[#flags + 1] = "|cffff6600" .. drop.dropDifficulty .. " only|r" end
                    
                    local flagStr = #flags > 0 and " (" .. table.concat(flags, ", ") .. ")" or ""
                    
                    msg(string.format("%d. %s |cff00ccff[%s]|r %s%s", 
                        dropCount, typeIcon, drop.type, drop.name, flagStr))
                    msg("   ItemID: |cffffff00" .. drop.itemID .. "|r")
                    
                    -- Check if collected
                    local isCollected = false
                    if drop.type == "mount" then
                        local mountID = C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(drop.itemID)
                        if mountID and not (issecretvalue and issecretvalue(mountID)) then
                            local _, _, _, _, _, _, _, _, _, _, collected = C_MountJournal.GetMountInfoByID(mountID)
                            if not (issecretvalue and issecretvalue(collected)) then
                                isCollected = (collected == true)
                            end
                        end
                    elseif drop.type == "pet" then
                        local speciesID = select(13, C_PetJournal.GetPetInfoByItemID(drop.itemID))
                        if speciesID and not (issecretvalue and issecretvalue(speciesID)) then
                            local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
                            if not (issecretvalue and issecretvalue(numCollected)) then
                                isCollected = (numCollected and numCollected > 0)
                            end
                        end
                    elseif drop.type == "toy" then
                        local hasToy = PlayerHasToy(drop.itemID)
                        if not (issecretvalue and issecretvalue(hasToy)) then
                            isCollected = hasToy
                        end
                    end
                    
                    if isCollected then
                        msg("   Status: |cff00ff00✓ Collected|r")
                    else
                        msg("   Status: |cffff8800✗ Not collected|r")
                        
                        -- Show try count if not collected
                        local tryCount = self:GetTryCount(drop.type, drop.itemID)
                        if tryCount > 0 then
                            msg("   Attempts: |cffffff00" .. tryCount .. "|r")
                        end
                    end
                    
                    -- Show yields if any
                    if drop.yields and #drop.yields > 0 then
                        msg("   |cff888888Yields:|r")
                        for j = 1, #drop.yields do
                            local yieldItem = drop.yields[j]
                            msg("      → " .. (yieldItem.name or "Unknown"))
                        end
                    end
                    
                    msg("")
                end
            end
            
            if dropCount == 0 then
                msg("|cffff6600No valid drops found in database.|r")
            end
            
            -- Show statistics IDs if any
            if drops.statisticIds and #drops.statisticIds > 0 then
                msg("|cff888888Statistics IDs:|r " .. table.concat(drops.statisticIds, ", "))
            end
        else
            msg("|cffff6600✗ No tracked drops from this NPC.|r")
            msg("")
            msg("This NPC is not in the CollectibleSourceDB.")
            msg("If it should drop something, please report it!")
        end
    end
    
    -- GameObject drops
    if objectID then
        msg("Type: |cff00ff00GameObject|r")
        msg("Object ID: |cffffff00" .. objectID .. "|r")
        
        local drops = objectDropDB[objectID]
        if drops then
            msg("|cff00ff00✓ This object has tracked drops!|r")
            msg("")
            
            -- List all drops (same format as NPC)
            local dropCount = 0
            for i = 1, #drops do
                local drop = drops[i]
                if drop.type and drop.itemID and drop.name then
                    dropCount = dropCount + 1
                    
                    local typeIcon = ""
                    if drop.type == "mount" then typeIcon = "🐎"
                    elseif drop.type == "pet" then typeIcon = "🐾"
                    elseif drop.type == "toy" then typeIcon = "🎲"
                    elseif drop.type == "item" then typeIcon = "📦"
                    end
                    
                    local flags = {}
                    if drop.guaranteed then flags[#flags + 1] = "|cff00ff00Guaranteed|r" end
                    if drop.repeatable then flags[#flags + 1] = "|cffff8800Repeatable|r" end
                    
                    local flagStr = #flags > 0 and " (" .. table.concat(flags, ", ") .. ")" or ""
                    
                    msg(string.format("%d. %s |cff00ccff[%s]|r %s%s", 
                        dropCount, typeIcon, drop.type, drop.name, flagStr))
                    msg("   ItemID: |cffffff00" .. drop.itemID .. "|r")
                    msg("")
                end
            end
            
            if dropCount == 0 then
                msg("|cffff6600No valid drops found in database.|r")
            end
        else
            msg("|cffff6600✗ No tracked drops from this object.|r")
            msg("")
            msg("This GameObject is not in the CollectibleSourceDB.")
        end
    end
    
    msg("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
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
    -- CRUD API for Track Item DB
    AddCustomDrop = function(_, st, sid, drop, stats) return WarbandNexus:AddCustomDrop(st, sid, drop, stats) end,
    RemoveCustomDrop = function(_, st, sid, iid) return WarbandNexus:RemoveCustomDrop(st, sid, iid) end,
    SetBuiltinTracked = function(_, st, sid, iid, t) return WarbandNexus:SetBuiltinTracked(st, sid, iid, t) end,
    IsBuiltinTracked = function(_, st, sid, iid) return WarbandNexus:IsBuiltinTracked(st, sid, iid) end,
    SetBuiltinRepeatable = function(_, ct, iid, r) return WarbandNexus:SetBuiltinRepeatable(ct, iid, r) end,
    GetRepeatableOverride = function(_, ct, iid) return WarbandNexus:GetRepeatableOverride(ct, iid) end,
    LookupItem = function(_, iid, cb) return WarbandNexus:LookupItem(iid, cb) end,
    RebuildTrackDB = function() return WarbandNexus:RebuildTrackDB() end,
}
