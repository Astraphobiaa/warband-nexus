--[[
    Warband Nexus - Try Counter Service
    Classify-Lock-Process loot pipeline: one route per session (SKIP/CONTAINER/FISHING/NPC-OBJECT).
    Sources: CollectibleSourceDB + trackDB overlays; db.global.tryCounts[type][id].
    Found drop resets count; miss increments (+ ReseedStatistics when statisticIds exist).
    Midnight 12.0.x: issecretvalue on ENCOUNTER_*/GetLootSourceInfo/UnitGUID/CHAT_MSG_LOOT; no CLEU.
    ProcessNPCLoot resolver P1->P5; ENCOUNTER_END + CHAT_MSG_LOOT debounced fallbacks.
    Events: LOOT_*, CHAT_MSG_LOOT, ENCOUNTER_*, BOSS_KILL, spellcast/fishing hooks, ITEM_LOCK_CHANGED.

    WN_NONUI_UI: `tryCounterFrame` (near RAW EVENT FRAMES) is an AceEvent-only host (`CreateFrame`); owns no Visible UI chrome.
    LuaLS: retain ---@ on WarbandNexus: export surface only; IIFE locals stay comment-only.
]]

local ADDON_NAME, ns = ...

-- IIFE: Lua 5.1 / WoW cap ~200 locals per function; main chunk exceeded limit.
;(function()
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local E = ns.Constants.EVENTS
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled
-- Packed internal funcs: Lua 5.1 / WoW ~200 locals per function scope.
local Fns = {}
local TC = ns.TryCounter or {}

-- ops-030: shared runtime for TryCounterService_Handlers.lua (table refs + scalar bag)
local RT = ns.TryCounter.Runtime
if not RT then
    RT = {}
    ns.TryCounter.Runtime = RT
end
RT.vars = RT.vars or {}
local V = RT.vars

-- CONSTANTS & UPVALUES (performance: resolved once at file load)

local VALID_TYPES = TC.VALID_TYPES or { mount = true, pet = true, toy = true, illusion = true, item = true }
local RECENT_KILL_TTL = TC.RECENT_KILL_TTL or 15
local PROCESSED_GUID_TTL = TC.PROCESSED_GUID_TTL or 300
local MERGED_LOOT_TRY_DEDUP_TTL = TC.MERGED_LOOT_TRY_DEDUP_TTL or 600
local CLEANUP_INTERVAL = TC.CLEANUP_INTERVAL or 60
local ENCOUNTER_OBJECT_TTL = TC.ENCOUNTER_OBJECT_TTL or 300
local SANCTUM_RAID_TEMPLATE_INSTANCE_ID = TC.SANCTUM_RAID_TEMPLATE_INSTANCE_ID or 1193
local RAID_MYTHIC_DIFFICULTY_ID = TC.RAID_MYTHIC_DIFFICULTY_ID or 16
local SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID = TC.SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID or 368304

Fns.TryChat = TC.TryChat
Fns.BuildObtainedChat = TC.BuildObtainedChat

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
local format = string.format
local strfind = string.find
local tconcat = table.concat
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

local function StatisticSnapshotStorageKey()
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey and WarbandNexus then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, nil)
        if k then return k end
    end
    local raw = Utilities and Utilities.GetCharacterStorageKey and Utilities:GetCharacterStorageKey(WarbandNexus)
    if not raw then return nil end
    if Utilities and Utilities.GetCanonicalCharacterKey then
        return Utilities:GetCanonicalCharacterKey(raw) or raw
    end
    return raw
end

-- Quest-item mounts (Stonevault/Mechagon style): populated by BuildReverseIndices; used by GetQuestStarterMountsForBrowser and GetTryCount fallback
local questStarterMountToSourceItemID = {}
local questStarterSourceToStatisticIds = {}  -- sourceItemID -> { statId, ... } for "statistic + local" try count
local questStarterMountList = {}
-- Reverse of questStarterMountToSourceItemID: sourceItemID -> array of all mountKeys that map to it.
-- Built in BuildReverseIndices; updated inline wherever questStarterMountToSourceItemID is written.
-- Replaces the O(N) pairs() scan in GetTryCount with an O(1) array lookup.
local sourceItemToAllMountKeys = {}
-- Cache: mountID -> sourceItemID resolved via C_MountJournal.GetMountFromItem scan.
-- Avoids repeating the expensive API-loop fallback in GetTryCount on every call.
local mountJournalResolvedSourceCache = {}
-- GUID parse cache: GUID string -> parsed NPC/object ID (or false = "not applicable").
-- Avoids repeated { strsplit("-", guid) } table allocation on hot paths.
local guidNpcIDCache = {}
local guidObjectIDCache = {}

-- Forward declarations for state variables used in OnEvent closure (declared after it)
local npcDropDB
local tryCounterNpcEligible
local objectDropDB
local isBlockingInteractionOpen
local discoveryPendingNpcID
local questLogLockoutDebounceTimer
local QUEST_LOG_LOCKOUT_DEBOUNCE_SEC = 1.5 -- coalesce QUEST_LOG bursts during flight / zone transitions

-- TryChat / BuildObtainedChat: Modules/TryCounterService_Shared.lua (Fns.* aliases set above).

-- RAW EVENT FRAMES
-- tryCounterFrame: loot, chat, encounter, spellcast, etc.
--
-- Midnight 12.0+: RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") is a protected action for
-- addons. Invoking it (even inside pcall, even from another frame's OnEvent) still reports
-- ADDON_ACTION_FORBIDDEN and can mark the addon unsafe for the session. No CLEU subscription;
-- open-world AoE farms use loot-based farmCorpseMult (table + npcId + missed-item source scan).
local tryCounterReady = false
local tryCounterInitializing = false
local tryCounterEventsRegistered = false
local tryCounterFrame = CreateFrame("Frame")
local DEBUG_TRACE_EVENTS = TC.DEBUG_TRACE_EVENTS or {}

-- MUST be declared before tryCounterFrame:SetScript("OnEvent") — otherwise the closure resolves globals (nil).
local DEBUG_TRACE_DEDUP_LOOT_MS = 0.22
local lastDebugTraceLootTime = { LOOT_READY = 0 }
local pendingRuntimeStatNpcIds = {} -- [npcID] = GetTime(); incremental stat reseed after kills
local statIncrementalDebounceSerial = 0
local STAT_INCREMENTAL_DEBOUNCE_SEC = 4
local STAT_INCREMENTAL_MIN_INTERVAL_SEC = 10
local lastStatIncrementalReseedAt = 0

-- Encounter lifecycle: ENCOUNTER_START (pull), ENCOUNTER_END (12.0 secret args), BOSS_KILL fallback.
-- NEW_MOUNT_ADDED / NEW_PET_ADDED: definitive learn signals when loot frames never tie to the kill.
local TRYCOUNTER_EVENTS = TC.TRYCOUNTER_EVENTS or {}
assert(#TRYCOUNTER_EVENTS > 0, "TryCounterService: TryCounterService_Events must load first")

local BLOCKING_INTERACTION_TYPES = TC.BLOCKING_INTERACTION_TYPES or {}

function Fns.RegisterTryCounterEvents()
    if tryCounterEventsRegistered then
        return true
    end
    -- Per-event pcall: a single bad event name (e.g. removed in a future patch) must not block the
    -- rest. Without this, RegisterEvent throwing on one entry would leave the entire frame without
    -- any subscriptions and silently break try counting.
    local anyRegistered = false
    for i = 1, #TRYCOUNTER_EVENTS do
        local ev = TRYCOUNTER_EVENTS[i]
        local ok, err = pcall(tryCounterFrame.RegisterEvent, tryCounterFrame, ev)
        if ok then
            anyRegistered = true
        elseif IsDebugModeEnabled and IsDebugModeEnabled() then
            DebugPrint(format("[TryCounter] RegisterEvent failed for %s: %s", tostring(ev), tostring(err)))
        end
    end
    tryCounterEventsRegistered = anyRegistered
    return tryCounterEventsRegistered
end

-- Try at load (safe for normal login). If forbidden (e.g. /reload in combat), InitializeTryCounter will retry.
Fns.RegisterTryCounterEvents()

tryCounterFrame:SetScript("OnEvent", function(_, event, ...)
    local addon = WarbandNexus
    -- Event trace: helps diagnose "no log" scenarios (e.g. no LOOT_OPENED, only currency chat event).
    if Fns.IsTryCounterLootDebugEnabled(addon) and DEBUG_TRACE_EVENTS[event] then
        local nowTrace = GetTime()
        local dedupKey = (event == "LOOT_READY") and event or nil
        if dedupKey and lastDebugTraceLootTime[dedupKey]
            and (nowTrace - lastDebugTraceLootTime[dedupKey]) < DEBUG_TRACE_DEDUP_LOOT_MS then
            -- Same event twice in one tick/window — expected from the client; omit duplicate trace line.
        else
            if dedupKey then lastDebugTraceLootTime[dedupKey] = nowTrace end
            addon:Print("|cff9370DB[WN-TC]|r |cff666688" .. event .. "|r")
        end
    end
    -- Early-session bootstrap: first fishing cast/loot can happen before scheduled init
    -- (InitializationService runs TryCounter at T+1.5s). Preserve context and force init on first loot events.
    if not tryCounterReady then
        if addon and Fns.IsTryCounterModuleEnabled()
            and (event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_CHANNEL_START") then
            if event == "UNIT_SPELLCAST_SENT" then
                addon:OnTryCounterSpellcastSent(event, ...)
            else
                addon:OnTryCounterSpellcastChannelStart(event, ...)
            end
        end
        if addon and (event == "LOOT_READY" or event == "LOOT_OPENED" or event == "CHAT_MSG_LOOT"
            or event == "ENCOUNTER_START" or event == "ENCOUNTER_END" or event == "BOSS_KILL")
            and addon.InitializeTryCounter and not tryCounterInitializing then
            addon:InitializeTryCounter()
        end
        if not tryCounterReady then return end
    end
    if not addon then return end
    if event == "LOOT_READY" then
        addon:OnTryCounterLootReady(...)
    elseif event == "LOOT_OPENED" then
        addon:OnTryCounterLootOpened(event, ...)
    elseif event == "LOOT_CLOSED" then
        addon:OnTryCounterLootClosed()
    elseif event == "CHAT_MSG_LOOT" then
        addon:OnTryCounterChatMsgLoot(...)
    elseif event == "CHAT_MSG_CURRENCY" or event == "CHAT_MSG_MONEY" then
        addon:OnTryCounterChatMsgCurrency(...)
    elseif event == "ENCOUNTER_START" then
        addon:OnTryCounterEncounterStart(event, ...)
    elseif event == "ENCOUNTER_END" then
        addon:OnTryCounterEncounterEnd(event, ...)
    elseif event == "BOSS_KILL" then
        addon:OnTryCounterBossKill(event, ...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        addon:OnTryCounterInstanceEntry(event, ...)
    elseif event == "UNIT_SPELLCAST_SENT" then
        addon:OnTryCounterSpellcastSent(event, ...)
    elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
        addon:OnTryCounterSpellcastChannelStart(event, ...)
    elseif event == "ITEM_LOCK_CHANGED" then
        addon:OnTryCounterItemLockChanged(event, ...)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        addon:OnTryCounterSpellcastFailed(event, ...)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType and not (issecretvalue and issecretvalue(interactionType)) and BLOCKING_INTERACTION_TYPES[interactionType] then
            isBlockingInteractionOpen = true
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if interactionType and not (issecretvalue and issecretvalue(interactionType)) and BLOCKING_INTERACTION_TYPES[interactionType] then
            isBlockingInteractionOpen = false
        end
    elseif event == "NEW_MOUNT_ADDED" then
        addon:OnTryCounterNewMountAdded(...)
    elseif event == "NEW_PET_ADDED" then
        addon:OnTryCounterNewPetAdded(...)
    elseif event == "PLAYER_TARGET_CHANGED" then
        local guid = Fns.SafeGetTargetGUID()
        if guid then
            local nid = Fns.GetNPCIDFromGUID(guid)
            local oid = Fns.GetObjectIDFromGUID(guid)
            if (nid and npcDropDB[nid] and tryCounterNpcEligible[nid]) or (oid and objectDropDB[oid]) then
                RT.lastLootSourceGUID = guid
                RT.lastLootSourceTime = GetTime()
            end
        else
            RT.lastLootSourceGUID = nil
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if not (C_Timer and C_Timer.NewTimer) then
            if discoveryPendingNpcID then
                Fns.TryDiscoverLockoutQuest()
            end
            Fns.ProcessKnownLockoutQuestCompletions()
        else
            if questLogLockoutDebounceTimer then
                questLogLockoutDebounceTimer:Cancel()
            end
            questLogLockoutDebounceTimer = C_Timer.NewTimer(QUEST_LOG_LOCKOUT_DEBOUNCE_SEC, function()
                questLogLockoutDebounceTimer = nil
                if discoveryPendingNpcID then
                    Fns.TryDiscoverLockoutQuest()
                end
                Fns.ProcessKnownLockoutQuestCompletions()
            end)
        end
    elseif event == "CRITERIA_UPDATE" then
        -- CRITERIA_UPDATE has no payload and fires in bursts during quests/achievements.
        -- Only re-read Statistics for NPCs we recently killed (ENCOUNTER_END marks them).
        if next(pendingRuntimeStatNpcIds) then
            Fns.RequestTryCounterStatisticsIncrementalRefresh()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if next(pendingRuntimeStatNpcIds) then
            Fns.RequestTryCounterStatisticsIncrementalRefresh()
        end
        Fns.EnsureMergedStatisticSeedIndex()
    end
end)

-- ops-030: fishing + classify constants -> TryCounterService_Process.lua (mutable bobber table)
local FISHING_SPELLS = TC.FISHING_SPELLS or {}
local FISHING_BOBBER_NPC_IDS = TC.FISHING_BOBBER_NPC_IDS or {}
local probedNonFishingSpells = TC.probedNonFishingSpells or {}
TC.probedNonFishingSpells = probedNonFishingSpells

function Fns.IsFishingBobberNpcId(npcID)
    return npcID and FISHING_BOBBER_NPC_IDS[npcID] == true
end

function Fns.LootSessionSourcesAreOnlyGameObjects(sourceGUIDs)
    if not sourceGUIDs or #sourceGUIDs == 0 then return false end
    for i = 1, #sourceGUIDs do
        local g = sourceGUIDs[i]
        if type(g) ~= "string" then return false end
        if issecretvalue and issecretvalue(g) then return false end
        if not g:match("^GameObject") then return false end
    end
    return true
end

--- First tracked try-counter object in loot source GUIDs (e.g. Overflowing Dumpster 469857).
---@return number|nil objectID
---@return string|nil sourceGUID
function Fns.GetTrackedObjectIDFromSourceGUIDs(sourceGUIDs)
    if not sourceGUIDs or not objectDropDB then return nil end
    for i = 1, #sourceGUIDs do
        local guid = sourceGUIDs[i]
        if type(guid) == "string" and not (issecretvalue and issecretvalue(guid)) then
            local oid = Fns.GetObjectIDFromGUID(guid)
            if oid and objectDropDB[oid] then
                return oid, guid
            end
        end
    end
    return nil
end

function Fns.LootSessionHasTrackedObjectSource(sourceGUIDs)
    return Fns.GetTrackedObjectIDFromSourceGUIDs(sourceGUIDs) ~= nil
end

function Fns.LootSourcesLookLikeFishingOnly(sourceGUIDs)
    if not sourceGUIDs or #sourceGUIDs == 0 then return false end
    -- Fishing loot is bobber Creature(s) and/or a pool GameObject next to the bobber.
    -- GameObject-only sources are NOT enough (chests, gathering nodes, many world objects).
    -- A lone unknown Creature is ambiguous (new bobber id vs trash mob) — require known bobber
    -- or Creature+GO pair (legacy bobber id miss + pool).
    local unknownCreatureTemplates = 0
    local knownBobber = false
    local hasGameObject = false
    local hasCreatureOrVehicle = false
    for i = 1, #sourceGUIDs do
        local g = sourceGUIDs[i]
        if type(g) ~= "string" then return false end
        if issecretvalue and issecretvalue(g) then return false end
        if g:match("^GameObject") then
            hasGameObject = true
        elseif g:match("^Creature") or g:match("^Vehicle") then
            hasCreatureOrVehicle = true
            local nid = Fns.GetNPCIDFromGUID(g)
            if Fns.IsFishingBobberNpcId(nid) then
                knownBobber = true
            elseif nid and (tryCounterNpcEligible[nid] or npcDropDB[nid]) then
                return false
            elseif nid then
                unknownCreatureTemplates = unknownCreatureTemplates + 1
                if unknownCreatureTemplates > 1 then
                    return false
                end
            else
                return false
            end
        end
    end
    if knownBobber then return true end
    -- Pool/chest without creature: indistinguishable here — IsFishingLoot() / cast+API path only.
    if hasGameObject and not hasCreatureOrVehicle then
        return false
    end
    if unknownCreatureTemplates > 0 and not knownBobber and not hasGameObject then
        return false
    end
    return true
end

-- Pickpocket spell IDs (Rogue): opens loot window on a mob WITHOUT killing it.
-- LOOT_OPENED fires with isFromItem=false, fishingCtx.active=false → would fall through to
-- ProcessNPCLoot → sourceGUID matches a tracked NPC → false try counter increment.
-- Detection: set V.isPickpocketing flag on spell cast, skip ProcessNPCLoot, clear on LOOT_CLOSED.
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
    [471014] = true,    -- Skinning (Midnight 12.0)
    -- Mining (these open loot on mining nodes, not corpses, but guard just in case)
    [2575] = true,      -- Mining (generic)
    [195122] = true,    -- Mining (BfA variant)
    [265854] = true,    -- Mining (BfA Kul Tiran)
    [265846] = true,    -- Mining (BfA Zandalari)
    [324802] = true,    -- Mining (Shadowlands)
    [366260] = true,    -- Mining (Dragonflight)
    [423343] = true,    -- Mining (TWW)
    [471013] = true,    -- Mining (Midnight 12.0)
    -- Herbalism
    [2366] = true,      -- Herb Gathering (generic)
    [195114] = true,    -- Herbalism (BfA variant)
    [265852] = true,    -- Herbalism (BfA Kul Tiran)
    [265842] = true,    -- Herbalism (BfA Zandalari)
    [324804] = true,    -- Herbalism (Shadowlands)
    [366261] = true,    -- Herbalism (Dragonflight)
    [423342] = true,    -- Herbalism (TWW)
    [471022] = true,    -- Herbalism (Midnight 12.0)
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

-- STATE (file-local, zero global pollution)

-- DB references (set at init from ns.CollectibleSourceDB)
npcDropDB = {}
-- NPCs allowed for corpse/GUID/CHAT/target try-counter attribution (subset of npcDropDB keys)
tryCounterNpcEligible = {}
local TRY_COUNTER_SHARED_TRASH_NPC = {
    -- AQ40: six mob types share the same mount table — loot must not attribute to one arbitrary ID
    [15246] = true, [15317] = true, [15247] = true, [15311] = true, [15249] = true, [15310] = true,
}
objectDropDB = {}
local fishingDropDB = {}
local containerDropDB = {}
local zoneDropDB = {}
local encounterDB = {}
local npcIDToEncounterID = {} -- [npcID] = encounterID — built in BuildReverseIndices; O(1) GetEncounterIDForNpcID
local encounterNameToNpcs = {}  -- [encounterName (enUS)] = { npcID1, ... } — Midnight: fallback when encounterID is secret
local lockoutQuestsDB = {}  -- [npcID] = questID or { questID1, questID2, ... }
local instanceBossSlotOutcomeRules = {}
-- Merged Statistics API columns per (collectibleType, tryKey): union LFR+N+H+M across DB rows & NPCs (e.g. G.M.O.D.).
local mergedStatSeedByTypeKey = {} -- [type .. "\0" .. key] = { tcType, tryKey, statIds, drops }
local mergedStatSeedGroupList = {} -- stable iteration order for SeedFromStatistics
local statSeedTryKeyPending = {}   -- drops with stat IDs but tryKey nil at seed time (API cold)
local mergedStatSeedIndexDirty = true
local statSeedWorkQueue = {}       -- reused by SeedFromStatistics (avoid per-seed allocations)
local runtimeStatReseedDropScratch = {}
local RUNTIME_STAT_NPC_TTL = 180

-- Runtime state
local recentKills = {}       -- [guid] = { npcID = n, name = s, time = t }
local recentKillByNpcID = {} -- [npcID] = { guid = string, killData = table }
local processedGUIDs = {}    -- [guid] = timestamp
local mergedLootTryCountedAt = {}  -- [fingerprint] = GetTime() — open-world merged loot, one wave per GUID set
local tryCounterInstanceDiffCache = { instanceID = nil, difficultyID = nil }
local currentEncounterCache = {
    encounterID = nil,          -- number|nil (non-secret, captured at start)
    encounterName = nil,        -- string|nil (non-secret)
    difficultyID = nil,         -- number|nil (non-secret, preferred over END's secret value)
    groupSize = nil,            -- number|nil
    startTime = 0,              -- GetTime() at ENCOUNTER_START
    instanceID = nil,           -- GetInstanceInfo()[8] snapshot for scope checks
}
local ENCOUNTER_CACHE_TTL = 1200  -- 20 minutes (covers long wipes, phase-heavy fights, AFK loot)
local tryCounterInstanceEntryAnnounced = {}
local tryCounterJournalIDByTemplateInstID = {
    [2097] = 1178, -- Operation: Mechagon (JournalInstance.ID)
}
local JOURNAL_INSTANCE_TEMPLATE_SCAN_MAX = 2600
local lastSyncScheduleCharKey = nil
local perCharStatSyncSerial = 0
local PER_CHAR_STAT_SYNC_QUICK_SEC = 1
local PER_CHAR_STAT_SYNC_FULL_SEC = 8
local PER_CHAR_STAT_RARITY_SEC = 12
local lastDifficultySkipChatKey = nil
local lastDifficultySkipChatTime = 0
local lastLockoutSkipChatKey = nil
local lastLockoutSkipChatTime = 0
local SKIP_CHAT_DEDUP_SEC = TC.SKIP_CHAT_DEDUP_SEC or 15
local fishingCtx = {
    active = false,            -- set on fishing cast, cleared when fishing loot processed (or 30s timer)
    castTime = 0,              -- timestamp of last fishing cast
    lootWasFishing = false,    -- true after ProcessFishingLoot ran with trackable; LOOT_CLOSED only clears active then
    resetTimer = nil,          -- safety timer: auto-reset active after 30s (handles cancelled casts)
}
local FISHING_CAST_CONTEXT_TTL = TC.FISHING_CAST_CONTEXT_TTL or 35
V.isPickpocketing = false -- set on pickpocket cast, cleared on LOOT_CLOSED
V.isProfessionLooting = false -- set on profession spell cast, cleared on LOOT_CLOSED
isBlockingInteractionOpen = false -- true when bank/vendor/AH/mail/trade UI is open
V.lastContainerItemID = nil  -- set on container use
V.lastContainerItemTime = 0  -- timestamp when container use/lock was observed (for LOOT_CLOSED fallback)
local resolvedIDs = {}       -- [itemID] = { type, collectibleID } - runtime resolved mount/pet IDs
local resolvedIDsReverse = {} -- [collectibleID] = itemID - reverse lookup for O(1) IndexLookup
local lockoutAttempted = {}  -- [questID] = true : tracks which lockout quests we've already counted this reset period
                             -- Keyed by questID (not npcID) so multiple NPCs sharing the same quest
                             -- (e.g. Arachnoid Harvester 154342/151934 both use quest 55512) are handled correctly.
local lockoutQuestSnapshot = {} -- [questID] = true : completed lockout quests at last snapshot (QUEST_LOG_UPDATE diff)
local lockoutPreCompletedAtLogin = {} -- [questID] = true : quest was already complete at last SyncLockoutState (pre-kill skip chat only)
local lockoutQuestFallbackTimers = {} -- [questID] = C_Timer handle : deferred count when ground loot is delayed (phase rares)
local lockoutLootTouchedNpc = {} -- [npcID] = GetTime() : corpse loot opened for lockout rare (quest fallback must not pre-count)
local LOCKOUT_QUEST_LOOT_DEFER_SEC = 60 -- long glide / parachute before quest-only fallback when corpse loot never opens
-- Deferred loot session: one attempt decision at LOOT_CLOSED (slot scan + session obtain marks).
local pendingLootSessionFinalize = nil
local LOOT_SESSION_RECENT_TTL = 90 -- block ENCOUNTER_END pre-miss while corpse/chest loot may still open
-- When loot has 0 item slots (only rep/currency), GetLootSourceInfo has nothing to return; target may be cleared.
-- Cache last targeted GUID that is in our DB so we can still attribute the loot open and count the try.
RT.lastLootSourceGUID = nil
RT.lastLootSourceTime = 0
local LAST_LOOT_SOURCE_TTL = 3  -- seconds
-- Structured loot session state (active session used by all processors).
-- Captured at LOOT_OPENED (best quality, includes isFromItem) or promoted from lootReady
-- at LOOT_CLOSED time when LOOT_OPENED was skipped (fast auto-loot).
local lootSession = {
    numLoot = 0,           -- GetNumLootItems() at capture
    sourceGUIDs = {},      -- GetAllLootSourceGUIDs() at capture
    slotData = {},         -- [i] = { hasItem = bool, link = string|nil }
    mouseoverGUID = nil,   -- UnitGUID("mouseover") at capture time
    targetGUID = nil,      -- UnitGUID("target") at capture time
    npcGUID = nil,         -- UnitGUID("npc") at capture time
    opened = false,        -- true once LOOT_OPENED fires; LOOT_CLOSED processes when this stays false
}
-- Miss-increment chat lines queued while the loot window is open (flush on LOOT_CLOSED).
local pendingIncrementAnnounces = {}
local tryCounterSelfTestSyncMiss = false
local tryCounterSelfTestSlotInstance = nil
local tryCounterSelfTestBossTrackable = nil

-- State captured on LOOT_READY (wiki: "before the loot window is shown"; valid until LOOT_CLOSED).
-- LOOT_READY is the ONLY guaranteed event — LOOT_OPENED may be skipped by fast auto-loot.
-- All data (including unit GUIDs) is captured here so LOOT_CLOSED can process reliably.
local lootReady = {
    numLoot = 0,
    slotData = {},
    sourceGUIDs = {},
    mouseoverGUID = nil,
    targetGUID = nil,
    npcGUID = nil,
    time = 0,
    wasFishing = false,    -- snapshot of fishingCtx.active at LOOT_READY time
}
local LOOT_READY_STATE_TTL = 5  -- seconds; treat lootReady data as valid for this long

local lastLootReadyFlowDebugSig = nil
local lastLootReadyFlowDebugTime = 0
local lastChatLootWindowActiveDebugTime = 0

local lastGatherCastName = nil
local lastGatherCastTime = 0
local lastSafeMapID = nil  -- cached last known good mapID for fallback when API returns nil/secret

-- CHAT_MSG_LOOT fallback: itemID → npcID when loot window doesn't fire (direct loot, world boss, etc.).
-- Built from npcDropDB in BuildReverseIndices; hardcoded entries merged so they take precedence.
local chatLootItemToNpc = {}
local chatLootTrackedItems = {}
local chatLootItemUniqueNpc = {}
V.lastTryCountSourceKey = nil
V.lastTryCountSourceTime = 0
V.lastTryCountLootSourceGUID = nil
V.lastEncounterEndTime = 0  -- set on ANY successful ENCOUNTER_END (even unmatched); suppresses zone fallback
local CHAT_LOOT_DEBOUNCE = 2.0  -- seconds: avoid double-count if LOOT_OPENED and CHAT_MSG_LOOT both fire

-- [tcType .. "\0" .. tryKey] = true : marker set ONLY by stat-backed ReseedStatisticsForDrops
-- when GetStatistic(killStatID) includes the kill the player just made. Found-path consumes
-- this and subtracts 1 from preResetCount so the displayed total ("after N attempts") matches
-- the kill number rather than `kill + 1` (which would result if we naively added 1 to a count
-- that already counted this very kill via the stat).
--
-- Manual +1 increments (open-world rares, raid bosses without stat IDs) DO NOT mark — for those
-- the locally stored count reflects ONLY prior misses, and the dropping kill is not pre-counted,
-- so the natural `preResetCount + 1` math in BuildObtainedChat is already correct.
--
-- ID-stable: the mark survives any timing (chest opened seconds, hours, or days after the kill).
-- The mark is consumed exactly once on found-path; if the drop never appears (mount doesn't
-- drop), the mark is naturally refreshed on the next kill's stat reseed (idempotent max(stat,
-- current)) so it always reflects the most recent kill state.
local dropDelayedReseeded = {}
local journalMirrorBuildPending = false
local lastLockoutSyncAt = 0

function Fns.IsTryCounterLootDebugEnabled(addon)
    local p = addon and addon.db and addon.db.profile
    return p and p.debugMode == true and p.debugTryCounterLoot == true
end

-- Color-coded debug log. Categories:
--   "flow"  = |cff88ccff (light blue)  — events, routing, entry points
--   "match" = |cff44ff44 (green)       — source matched
--   "skip"  = |cff888888 (gray)        — skipped, debounced, lockout
--   "miss"  = |cffff8844 (orange)      — no match, ambiguous
--   "count" = |cffffcc00 (gold)        — increment/outcome
--   "reset" = |cff00ff88 (bright cyan) — try count reset (caught/obtained)
local LOG_COLORS = {
    flow  = "|cff88ccff",
    match = "|cff44ff44",
    skip  = "|cff888888",
    miss  = "|cffff8844",
    count = "|cffffcc00",
    reset = "|cff00ff88",
}

function Fns.TryCounterLootDebug(addon, cat, fmt, ...)
    if not Fns.IsTryCounterLootDebugEnabled(addon) then return end
    local color = LOG_COLORS[cat] or "|cffcccccc"
    local n = select("#", ...)
    local msg = (n > 0) and string.format(tostring(fmt), ...) or tostring(fmt)
    addon:Print("|cff9370DB[WN-TC]|r " .. color .. msg .. "|r")
end

function Fns.TryCounterLootDebugDropLines(addon, source, drops, mult)
    if not Fns.IsTryCounterLootDebugEnabled(addon) then return end
    local m = (mult and mult > 1) and mult or 1
    for i = 1, #drops do
        local d = drops[i]
        if type(d) == "table" then
            local rep = d.repeatable and "True" or "False"
            local whatIs = format("%s #%s %s", d.type or "?", tostring(d.itemID or "?"), tostring(d.name or "?"))
            Fns.TryCounterLootDebug(addon, "count",
                "+%d | Source: %s | InDB: True | Repeatable: %s | WhatIs: %s",
                m, source, rep, whatIs)
        end
    end
end

function Fns.LootDebugParseItemIDFromLink(link)
    if not link or type(link) ~= "string" then return nil end
    if issecretvalue and issecretvalue(link) then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

function Fns.FormatLootSourceSummary(sourceGUIDs, wasFishing)
    local guids = sourceGUIDs or {}
    local n = #guids
    if n == 0 then
        return wasFishing and "No GUIDs | fishCtx=true" or "No GUIDs"
    end
    local c, v, g, o = 0, 0, 0, 0
    for i = 1, n do
        local gguid = guids[i]
        if type(gguid) == "string" and not (issecretvalue and issecretvalue(gguid)) then
            local p = gguid:match("^(%a+)")
            if p == "Creature" then c = c + 1
            elseif p == "Vehicle" then v = v + 1
            elseif p == "GameObject" then g = g + 1
            else o = o + 1 end
        end
    end
    local bits = {}
    if c > 0 then bits[#bits + 1] = string.format("%d×NPC", c) end
    if v > 0 then bits[#bits + 1] = string.format("%d×Vehicle", v) end
    if g > 0 then bits[#bits + 1] = string.format("%d×Object", g) end
    if o > 0 then bits[#bits + 1] = string.format("%d×Other", o) end
    local body = #bits > 0 and table.concat(bits, ", ") or "Unknown"
    if wasFishing then body = body .. " | fishCtx=true" end
    return body
end

function Fns.FormatLootUnitToken(guid)
    if not guid or type(guid) ~= "string" then return "-" end
    local nid = Fns.GetNPCIDFromGUID(guid)
    if nid then return "npc:" .. tostring(nid) end
    local oid = Fns.GetObjectIDFromGUID(guid)
    if oid then return "obj:" .. tostring(oid) end
    local pfx = guid:match("^(%a+)")
    return pfx or "?"
end

function Fns.LootDebugDescribeSlots(slotData, numLoot, addon)
    local WN = addon or WarbandNexus
    local parts = {}
    local hasTC = false
    local repAny = false
    local max = tonumber(numLoot) or 0
    if max > 32 then max = 32 end
    for i = 1, max do
        local sd = slotData and slotData[i]
        if sd and sd.hasItem then
            local link = sd.link
            local itemID = Fns.LootDebugParseItemIDFromLink(link)
            if itemID then
                local itemName
                if C_Item and C_Item.GetItemInfo then
                    itemName = select(1, C_Item.GetItemInfo(itemID))
                elseif GetItemInfo then
                    itemName = select(1, GetItemInfo(itemID))
                end
                if itemName and issecretvalue and issecretvalue(itemName) then itemName = nil end
                local label = itemName or ("item:" .. tostring(itemID))
                local typ, tid, rep = nil, nil, false
                if WN.IsDropSourceCollectible and WN:IsDropSourceCollectible("toy", itemID) then
                    typ, tid = "toy", itemID
                else
                    local mid
                    if C_MountJournal and C_MountJournal.GetMountFromItem then
                        mid = C_MountJournal.GetMountFromItem(itemID)
                        if issecretvalue and mid and issecretvalue(mid) then mid = nil end
                    end
                    if mid and WN.IsDropSourceCollectible and WN:IsDropSourceCollectible("mount", mid) then
                        typ, tid = "mount", mid
                    elseif WN.IsDropSourceCollectible and WN:IsDropSourceCollectible("mount", itemID) then
                        typ, tid = "mount", itemID
                    elseif C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                        local _, _, _, _, _, _, _, _, _, _, _, _, sid = C_PetJournal.GetPetInfoByItemID(itemID)
                        if issecretvalue and sid and issecretvalue(sid) then sid = nil end
                        if sid and WN.IsDropSourceCollectible and WN:IsDropSourceCollectible("pet", sid) then
                            typ, tid = "pet", sid
                        end
                    end
                end
                if typ and tid then
                    hasTC = true
                    if WN.IsRepeatableCollectible and WN:IsRepeatableCollectible(typ, tid) then repAny = true end
                    parts[#parts + 1] = string.format("%s id=%s %s", typ, tostring(tid), label)
                else
                    parts[#parts + 1] = string.format("item id=%s %s (no try-key)", tostring(itemID), label)
                end
            end
        end
    end
    local whatIs = #parts > 0 and table.concat(parts, " | ") or "empty"
    return hasTC, repAny, whatIs
end

function Fns.CopyDropArray(drops)
    if type(drops) ~= "table" then return {} end
    local copy = {}
    for i = 1, #drops do
        copy[i] = drops[i]
    end
    if drops.statisticIds then copy.statisticIds = drops.statisticIds end
    if drops.dropDifficulty then copy.dropDifficulty = drops.dropDifficulty end
    return copy
end

function Fns.CopyContainerMap(src)
    local out = {}
    for key, data in pairs(src or {}) do
        if type(data) == "table" and data.drops then
            out[key] = { drops = Fns.CopyDropArray(data.drops) }
        else
            out[key] = Fns.CopyDropArray(data)
        end
    end
    return out
end

function Fns.CopyZoneMap(src)
    local out = {}
    for key, data in pairs(src or {}) do
        if type(data) == "table" and data.drops then
            out[key] = {
                drops = Fns.CopyDropArray(data.drops),
                raresOnly = data.raresOnly == true,
                hostileOnly = data.hostileOnly == true,
            }
        else
            out[key] = Fns.CopyDropArray(data)
        end
    end
    return out
end

function Fns.CopyEncounterMap(src)
    local out = {}
    for key, list in pairs(src or {}) do
        if type(list) == "table" then
            local copy = {}
            for i = 1, #list do
                copy[i] = list[i]
            end
            out[key] = copy
        end
    end
    return out
end

function Fns.AugmentEncounterNameToNpcsFromNpcNameIndex()
    local static = ns.CollectibleSourceDB
    if not static or type(static.npcNameIndex) ~= "table" then return end
    local npcToEncounterNpcs = {}
    for _, list in pairs(encounterDB or {}) do
        if type(list) == "table" then
            for i = 1, #list do
                local nid = list[i]
                if nid and not npcToEncounterNpcs[nid] then
                    npcToEncounterNpcs[nid] = list
                end
            end
        end
    end
    for name, ids in pairs(static.npcNameIndex) do
        if type(name) == "string" and name ~= "" and type(ids) == "table" then
            for i = 1, #ids do
                local list = npcToEncounterNpcs[ids[i]]
                if list then
                    encounterNameToNpcs[name] = list
                    break
                end
            end
        end
    end
end

function Fns.CopyKeyValueMap(src)
    local out = {}
    for key, value in pairs(src or {}) do
        out[key] = value
    end
    return out
end

function Fns.LoadRuntimeSourceTables()
    local db = ns.CollectibleSourceDB
    if not db then
        npcDropDB, objectDropDB, fishingDropDB, containerDropDB = {}, {}, {}, {}
        zoneDropDB, encounterDB, encounterNameToNpcs, lockoutQuestsDB = {}, {}, {}, {}
        wipe(npcIDToEncounterID)
        wipe(instanceBossSlotOutcomeRules)
        Fns.SyncTryCounterRTTableRefs()
        return
    end

    npcDropDB = {}
    for k, v in pairs(db.npcs or {}) do
        npcDropDB[k] = Fns.CopyDropArray(v)
    end
    for k, v in pairs(db.rares or {}) do
        if not npcDropDB[k] then
            npcDropDB[k] = Fns.CopyDropArray(v)
        end
    end

    objectDropDB = {}
    for k, v in pairs(db.objects or {}) do
        objectDropDB[k] = Fns.CopyDropArray(v)
    end

    fishingDropDB = Fns.CopyKeyValueMap(db.fishing or {})
    containerDropDB = Fns.CopyContainerMap(db.containers or {})
    zoneDropDB = Fns.CopyZoneMap(db.zones or {})
    encounterDB = Fns.CopyEncounterMap(db.encounters or {})
    encounterNameToNpcs = Fns.CopyEncounterMap(db.encounterNames or {})
    Fns.AugmentEncounterNameToNpcsFromNpcNameIndex()
    lockoutQuestsDB = Fns.CopyKeyValueMap(db.lockoutQuests or {})

    wipe(instanceBossSlotOutcomeRules)
    local slotRules = db.instanceBossSlotOutcomeRules
    if type(slotRules) == "table" then
        for i = 1, #slotRules do
            instanceBossSlotOutcomeRules[i] = slotRules[i]
        end
    end
    Fns.SyncTryCounterRTTableRefs()
end

--- Handlers read RT.*; LoadRuntimeSourceTables reassigns file-local DB tables — keep RT in sync.
function Fns.SyncTryCounterRTTableRefs()
    RT.npcDropDB = npcDropDB
    RT.encounterDB = encounterDB
    RT.encounterNameToNpcs = encounterNameToNpcs
    RT.tryCounterNpcEligible = tryCounterNpcEligible
end

function Fns.BuildTryCounterNpcEligible()
    wipe(tryCounterNpcEligible)
    local static = ns.CollectibleSourceDB
    if not static then return end

    local function mark(npcID)
        if not npcID or TRY_COUNTER_SHARED_TRASH_NPC[npcID] then return end
        if npcDropDB[npcID] then tryCounterNpcEligible[npcID] = true end
    end

    for npcID in pairs(static.rares or {}) do mark(npcID) end

    for _, list in pairs(encounterDB or {}) do
        if type(list) == "table" then
            for i = 1, #list do mark(list[i]) end
        end
    end
    for _, list in pairs(encounterNameToNpcs or {}) do
        if type(list) == "table" then
            for i = 1, #list do mark(list[i]) end
        end
    end

    local nidx = static.npcNameIndex
    if type(nidx) == "table" then
        for _, ids in pairs(nidx) do
            if type(ids) == "table" then
                for i = 1, #ids do mark(ids[i]) end
            end
        end
    end

    for npcID, drops in pairs(npcDropDB) do
        if TRY_COUNTER_SHARED_TRASH_NPC[npcID] then
            -- excluded
        elseif drops.statisticIds and #drops.statisticIds > 0 then
            tryCounterNpcEligible[npcID] = true
        elseif drops.dropDifficulty then
            tryCounterNpcEligible[npcID] = true
        else
            -- World / zone farm mounts (BfA Bloodfeaster, Goldenmane, Dune Scavenger, etc.): repeatable=true
            -- only — no statisticIds or dropDifficulty on the NPC. They must still drive loot-window try counts.
            for i = 1, #drops do
                local d = drops[i]
                if type(d) == "table" and (d.dropDifficulty or d.repeatable) then
                    tryCounterNpcEligible[npcID] = true
                    break
                end
            end
        end
    end

    if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.trackDB then
        local custom = WarbandNexus.db.global.trackDB.custom and WarbandNexus.db.global.trackDB.custom.npcs
        if type(custom) == "table" then
            for npcID in pairs(custom) do mark(tonumber(npcID)) end
        end
    end
end

-- REVERSE LOOKUP INDICES (built once at InitializeTryCounter, O(1) lookups)
-- Keys: [type .. "\0" .. itemID] = true
-- These replace the old O(N) full-DB-scan approach in Is*Collectible().
local guaranteedIndex = {}    -- drop.guaranteed == true
local repeatableIndex = {}    -- drop.repeatable == true
local dropSourceIndex = {}    -- any drop entry (exists in DB at all)
local dropDifficultyIndex = {} -- drop/NPC dropDifficulty string (e.g. "Mythic", "25H", "Heroic")
local repeatableItemDrops = {} -- [itemID] = drop for "item" type repeatable (reset + notify when received via CHAT_MSG_LOOT if loot window was cleared by autoLoot)
local reverseIndicesBuilt = false

-- REVERSE INDEX BUILDER
-- Called once from InitializeTryCounter after DB references are loaded.
-- Iterates all drop sources once, building O(1) lookup tables keyed by
-- type+itemID. This eliminates the O(N) full-DB scans that previously
-- ran on every cache-miss call to Is*Collectible().

function Fns.IndexDrop(drop, npcDifficulty, hasStatistics)
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
        local existing = dropDifficultyIndex[itemKey]
        if existing == false then
            -- already marked: conflicting requirements for same item key
        elseif existing == nil or existing == difficulty then
            dropDifficultyIndex[itemKey] = difficulty
        else
            dropDifficultyIndex[itemKey] = false -- multiple gates; GetDropDifficulty returns nil
        end
    elseif hasStatistics then
        local existing = dropDifficultyIndex[itemKey]
        if existing == nil then
            dropDifficultyIndex[itemKey] = "All Difficulties"
        elseif existing ~= false and existing ~= "All Difficulties" then
            dropDifficultyIndex[itemKey] = false
        end
    end

    -- DB rows are often type=item (quest item, container) while UI/plans use native mountID/speciesID.
    -- Without mirroring, IsDropSourceCollectible("mount", mountID) stays false (e.g. Stonevault Mechsuit).
    local function indexReflectCollectible(ref)
        if not ref or not ref.type then return end
        if ref.itemID then
            dropSourceIndex[ref.type .. "\0" .. tostring(ref.itemID)] = true
        end
        if ref.type == "mount" and ref.mountID then
            dropSourceIndex["mount\0" .. tostring(ref.mountID)] = true
        end
        if ref.type == "pet" and ref.speciesID then
            dropSourceIndex["pet\0" .. tostring(ref.speciesID)] = true
        end
        -- Do not call ResolveCollectibleID here: it is defined later in this file; Lua would treat it as a
        -- global (nil) inside IndexDrop. Mount/pet journal IDs from DB fields above + IndexQuestStarterMounts cover Mechasuit-style rows.
    end
    if drop.tryCountReflectsTo then
        indexReflectCollectible(drop.tryCountReflectsTo)
    end
    if drop.questStarters then
        for qi = 1, #drop.questStarters do
            indexReflectCollectible(drop.questStarters[qi])
        end
    end
end

function Fns.IndexDropArray(drops)
    if not drops then return end
    local npcDifficulty = drops.dropDifficulty  -- NPC-level difficulty (e.g. "Mythic")
    local hasStatistics = drops.statisticIds and #drops.statisticIds > 0
    for i = 1, #drops do
        Fns.IndexDrop(drops[i], npcDifficulty, hasStatistics)
    end
end

function Fns.BuildReverseIndices()
    if reverseIndicesBuilt then return end

    -- Flat sources: [key] = { { type, itemID, name }, ... }
    for _, drops in pairs(npcDropDB) do Fns.IndexDropArray(drops) end
    for _, drops in pairs(objectDropDB) do Fns.IndexDropArray(drops) end
    for _, drops in pairs(fishingDropDB) do Fns.IndexDropArray(drops) end
    -- Zone drops support both old format (direct array) and new format ({ drops = {...}, raresOnly = true })
    for _, zData in pairs(zoneDropDB) do
        local drops = zData.drops or zData
        Fns.IndexDropArray(drops)
    end

    -- Container source: [containerID] = { drops = { {...}, ... } } or direct array
    for _, containerData in pairs(containerDropDB) do
        local list = containerData.drops or containerData
        if type(list) == "table" then
            -- Handle both { drops = { ... } } and direct array formats
            local arr = list.drops or list
            if type(arr) == "table" then
                Fns.IndexDropArray(arr)
            end
        end
    end

    -- Encounter source: [encounterID] = { npcID1, npcID2, ... }
    -- npcIDToEncounterID: first encounter wins per npcID (same as legacy linear scan).
    Fns.RebuildNpcIDToEncounterIndex()

    -- Quest-item -> mount mapping: so GetTryCount("mount", id) can fall back to item try count
    -- Plan cards use mountID (journal); we store count on item. Map both mountID and mount itemID to source item.
    questStarterMountToSourceItemID = {}
    questStarterSourceToStatisticIds = {}
    for i = #questStarterMountList, 1, -1 do questStarterMountList[i] = nil end
    local seenMountItemID = {}
    local function IndexQuestStarterMounts(drops)
        if not drops then return end
        local statIds = drops.statisticIds
        for i = 1, #drops do
            local drop = drops[i]
            if drop and drop.questStarters and drop.itemID then
                if statIds and #statIds > 0 then
                    questStarterSourceToStatisticIds[drop.itemID] = statIds
                end
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
    -- If two eligible NPCs share an itemID with different drop tables → false (ambiguous).
    -- Same shared table (e.g. BfA zone-drop mounts: many NPCs → one _drops array) → keep first npcID;
    -- try counts use the same drops/mount key regardless of which spawner dropped loot.
    chatLootItemToNpc = {}
    wipe(chatLootTrackedItems)
    wipe(chatLootItemUniqueNpc)
    local itemNpcOwners = {}
    local function RecordItemOwner(itemID, npcID)
        if not itemID or not npcID or not tryCounterNpcEligible[npcID] then return end
        local bucket = itemNpcOwners[itemID]
        if not bucket then
            bucket = {}
            itemNpcOwners[itemID] = bucket
        end
        bucket[npcID] = true
    end
    local function MergeChatLootItemToNpc(itemID, npcID)
        if not itemID or not npcID then return end
        chatLootTrackedItems[itemID] = true
        RecordItemOwner(itemID, npcID)
        local ex = chatLootItemToNpc[itemID]
        if not ex then
            chatLootItemToNpc[itemID] = npcID
        elseif ex ~= npcID then
            local prevDrops = npcDropDB[ex]
            local newDrops = npcDropDB[npcID]
            if prevDrops ~= newDrops then
                chatLootItemToNpc[itemID] = false
            end
        end
    end
    for npcID, npcData in pairs(npcDropDB) do
        if tryCounterNpcEligible[npcID] then
            for i = 1, #npcData do
                local drop = npcData[i]
                if drop and drop.itemID then
                    MergeChatLootItemToNpc(drop.itemID, npcID)
                    if drop.questStarters then
                        for j = 1, #drop.questStarters do
                            local qs = drop.questStarters[j]
                            if qs and qs.itemID then
                                MergeChatLootItemToNpc(qs.itemID, npcID)
                            end
                        end
                    end
                end
            end
        end
    end
    -- Object/chest drops: same Merge rules (shared drop table ref or single eligible npc owner).
    local function MergeChatLootItemFromObjectDrop(itemID, objDrops)
        if not itemID or not objDrops then return end
        chatLootTrackedItems[itemID] = true
        local proxyNpc = nil
        for npcID, npcData in pairs(npcDropDB) do
            if tryCounterNpcEligible[npcID] then
                if npcData == objDrops then
                    MergeChatLootItemToNpc(itemID, npcID)
                    return
                end
                if Fns.NpcDropEntryContainsAnyItemSet(npcData, { [itemID] = true }) then
                    if proxyNpc and proxyNpc ~= npcID and npcDropDB[proxyNpc] ~= npcData then
                        MergeChatLootItemToNpc(itemID, false)
                        return
                    end
                    proxyNpc = npcID
                end
            end
        end
        if proxyNpc then
            MergeChatLootItemToNpc(itemID, proxyNpc)
        end
    end
    for _, objData in pairs(objectDropDB) do
        for i = 1, #objData do
            local drop = objData[i]
            if drop and drop.itemID then
                MergeChatLootItemFromObjectDrop(drop.itemID, objData)
                if drop.questStarters then
                    for j = 1, #drop.questStarters do
                        local qs = drop.questStarters[j]
                        if qs and qs.itemID then
                            MergeChatLootItemFromObjectDrop(qs.itemID, objData)
                        end
                    end
                end
            end
        end
    end
    for itemID, owners in pairs(itemNpcOwners) do
        local count, sole = 0, nil
        for nid in pairs(owners) do
            count = count + 1
            sole = nid
        end
        if count == 1 then
            chatLootItemUniqueNpc[itemID] = sole
        end
    end
    -- Hardcoded overrides (e.g. known edge cases)
    chatLootItemToNpc[235910] = 234621  -- Mint Condition Gallagio Anniversary Coin → Gallagio Garbage

    -- Mount/Pet journal mirror keys are non-critical for startup loot tracking.
    -- Build them in a deferred, budgeted pass to reduce /reload hitch.
    if Fns.ScheduleDeferredJournalMirrorIndexBuild then
        Fns.ScheduleDeferredJournalMirrorIndexBuild()
    end

    -- Build sourceItemToAllMountKeys: sourceItemID -> { mountKey1, mountKey2, ... }
    -- Enables O(1) lookup in GetTryCount instead of O(N) pairs() scan.
    wipe(sourceItemToAllMountKeys)
    wipe(mountJournalResolvedSourceCache)
    for mountKey, srcID in pairs(questStarterMountToSourceItemID) do
        local arr = sourceItemToAllMountKeys[srcID]
        if not arr then
            arr = {}
            sourceItemToAllMountKeys[srcID] = arr
        end
        arr[#arr + 1] = mountKey
    end

    reverseIndicesBuilt = true
end

function Fns.RebuildNpcIDToEncounterIndex()
    wipe(npcIDToEncounterID)
    for encID, npcList in pairs(encounterDB or {}) do
        if type(npcList) == "table" then
            for j = 1, #npcList do
                local nid = npcList[j]
                if nid and not npcIDToEncounterID[nid] then
                    npcIDToEncounterID[nid] = encID
                end
            end
        end
    end
end

function Fns.ScheduleDeferredJournalMirrorIndexBuild()
    if journalMirrorBuildPending then
        return
    end

    local BUDGET_MS = 2.5
    journalMirrorBuildPending = true
    C_Timer.After(0.5, function()
        journalMirrorBuildPending = false
        if not reverseIndicesBuilt then return end

        if ns.EnsureBlizzardCollectionsLoaded then
            ns.EnsureBlizzardCollectionsLoaded()
        end

        local work = {}
        local function PushDrops(drops)
            if type(drops) ~= "table" then return end
            for i = 1, #drops do
                work[#work + 1] = drops[i]
            end
        end

        for _, drops in pairs(npcDropDB) do PushDrops(drops) end
        for _, drops in pairs(objectDropDB) do PushDrops(drops) end
        for _, drops in pairs(fishingDropDB) do PushDrops(drops) end
        for _, zData in pairs(zoneDropDB) do
            PushDrops(zData.drops or zData)
        end
        for _, containerData in pairs(containerDropDB) do
            local list = containerData.drops or containerData
            if type(list) == "table" then
                PushDrops(list.drops or list)
            end
        end

        local idx = 1
        local function ProcessBatch()
            local batchStart = debugprofilestop()
            while idx <= #work do
                local drop = work[idx]

                if drop and drop.itemID then
                    if drop.type == "mount" then
                        local itemKey = "mount\0" .. tostring(drop.itemID)
                        if dropSourceIndex[itemKey] then
                            local journalID = drop.mountID
                            if not journalID and C_MountJournal and C_MountJournal.GetMountFromItem then
                                journalID = C_MountJournal.GetMountFromItem(drop.itemID)
                                if issecretvalue and journalID and issecretvalue(journalID) then journalID = nil end
                            end
                            journalID = journalID and tonumber(journalID) or nil
                            if journalID and journalID ~= tonumber(drop.itemID) then
                                local jKey = "mount\0" .. tostring(journalID)
                                dropSourceIndex[jKey] = true
                                if guaranteedIndex[itemKey] then guaranteedIndex[jKey] = true end
                                if repeatableIndex[itemKey] then repeatableIndex[jKey] = true end
                                local diff = dropDifficultyIndex[itemKey]
                                if diff then dropDifficultyIndex[jKey] = diff end
                            end
                        end
                    elseif drop.type == "pet" then
                        local itemKey = "pet\0" .. tostring(drop.itemID)
                        if dropSourceIndex[itemKey] then
                            local speciesID = drop.speciesID
                            if not speciesID and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
                                local _, _, _, _, _, _, _, _, _, _, _, _, sid = C_PetJournal.GetPetInfoByItemID(drop.itemID)
                                speciesID = sid
                                if issecretvalue and speciesID and issecretvalue(speciesID) then speciesID = nil end
                            end
                            speciesID = speciesID and tonumber(speciesID) or nil
                            if speciesID and speciesID ~= tonumber(drop.itemID) then
                                local sKey = "pet\0" .. tostring(speciesID)
                                dropSourceIndex[sKey] = true
                                if guaranteedIndex[itemKey] then guaranteedIndex[sKey] = true end
                                if repeatableIndex[itemKey] then repeatableIndex[sKey] = true end
                                local diff = dropDifficultyIndex[itemKey]
                                if diff then dropDifficultyIndex[sKey] = diff end
                            end
                        end
                    end
                end

                idx = idx + 1
                if debugprofilestop() - batchStart > BUDGET_MS then
                    C_Timer.After(0, ProcessBatch)
                    return
                end
            end
        end

        ProcessBatch()
    end)
end

local function RegisterQuestStarterMountKey(mountKey, srcItemID)
    if not mountKey or not srcItemID then return end
    questStarterMountToSourceItemID[mountKey] = srcItemID
    local arr = sourceItemToAllMountKeys[srcItemID]
    if not arr then
        arr = {}
        sourceItemToAllMountKeys[srcItemID] = arr
    end
    for i = 1, #arr do
        if arr[i] == mountKey then return end
    end
    arr[#arr + 1] = mountKey
end

-- DATABASE HELPERS

function Fns.EnsureDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then
        return false
    end
    if not WarbandNexus.db.global.tryCounts then
        WarbandNexus.db.global.tryCounts = {
            mount = {}, pet = {}, toy = {}, illusion = {}, item = {},
        }
    end
    for t in pairs(VALID_TYPES) do
        if not WarbandNexus.db.global.tryCounts[t] then
            WarbandNexus.db.global.tryCounts[t] = {}
        end
    end
    if not WarbandNexus.db.global.tryCounts.obtained then
        WarbandNexus.db.global.tryCounts.obtained = {}
    end
    local tc0 = WarbandNexus.db.global.tryCounts
    local oldSeedKey = "r" .. "arityMountsOneTimeSeedComplete"
    if tc0.legacyMountTrackerSeedComplete == nil then
        tc0.legacyMountTrackerSeedComplete = (tc0[oldSeedKey] == true) or false
    end
    tc0[oldSeedKey] = nil
    return true
end

function Fns.MarkItemObtained(itemID)
    if not itemID or not Fns.EnsureDB() then return end
    WarbandNexus.db.global.tryCounts.obtained[itemID] = true
end

function Fns.IsItemMarkedObtained(itemID)
    if not itemID then return false end
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return false end
    local tc = WarbandNexus.db.global.tryCounts
    return tc and tc.obtained and tc.obtained[itemID] == true
end

-- PUBLIC API (manual get/set/increment - unchanged from before)

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@return number count
function WarbandNexus:GetTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not Fns.EnsureDB() then return 0 end
    local idNum = tonumber(id)
    if idNum then id = idNum end
    -- Quest Starter = Mount Item = Mount: try count = statistic + local stored
    if collectibleType == "mount" then
        local sourceItemID = questStarterMountToSourceItemID[id] or (idNum and questStarterMountToSourceItemID[idNum])
        -- Fast reverse lookup: resolvedIDsReverse maps mountID -> itemID (teach item); that itemID
        -- may itself be a questStarterMountToSourceItemID key.
        if not sourceItemID and idNum then
            local itemIDForMount = resolvedIDsReverse[idNum]
            if itemIDForMount then
                sourceItemID = questStarterMountToSourceItemID[itemIDForMount]
            end
        end
        -- Last-resort: scan via C_MountJournal.GetMountFromItem (costly; result is cached to avoid repeat).
        if not sourceItemID and idNum then
            local cached = mountJournalResolvedSourceCache[idNum]
            if cached ~= nil then
                sourceItemID = cached or nil
            elseif C_MountJournal and C_MountJournal.GetMountFromItem then
                for mountKey, srcID in pairs(questStarterMountToSourceItemID) do
                    if type(mountKey) == "number" and type(srcID) == "number" then
                        local resolved = C_MountJournal.GetMountFromItem(mountKey)
                        if resolved and not (issecretvalue and issecretvalue(resolved)) and tonumber(resolved) == idNum then
                            sourceItemID = srcID
                            mountJournalResolvedSourceCache[idNum] = srcID
                            break
                        end
                    end
                end
                if not sourceItemID then mountJournalResolvedSourceCache[idNum] = false end
            end
        end
        if sourceItemID then
            local itemCount = WarbandNexus.db.global.tryCounts.item and WarbandNexus.db.global.tryCounts.item[sourceItemID]
            local localStored = type(itemCount) == "number" and itemCount or 0
            local mountCounts = WarbandNexus.db.global.tryCounts.mount
            if mountCounts then
                -- Check all known keys for this quest-starter mount (itemID, mountID, resolved ID)
                -- to find the highest stored count. Covers legacy data stored under different keys.
                local m1 = type(mountCounts[id]) == "number" and mountCounts[id] or 0
                if m1 > localStored then localStored = m1 end
                -- O(1) lookup via prebuilt reverse map (replaces O(N) pairs scan).
                local allKeys = sourceItemToAllMountKeys[sourceItemID]
                if allKeys then
                    for i = 1, #allKeys do
                        local mappedKey = allKeys[i]
                        if mappedKey ~= id then
                            local mv = type(mountCounts[mappedKey]) == "number" and mountCounts[mappedKey] or 0
                            if mv > localStored then localStored = mv end
                        end
                    end
                end
            end
            return localStored
        end
    end
    local count = WarbandNexus.db.global.tryCounts[collectibleType][id]
    local n = type(count) == "number" and count or 0
    return Fns.MaxTryCountAliasKeys(collectibleType, id, n)
end

function Fns.ForEachTryCountAliasKey(collectibleType, id, visit)
    local idNum = tonumber(id)
    if not idNum then return end
    if collectibleType ~= "mount" and collectibleType ~= "pet" then return end
    if resolvedIDsReverse and resolvedIDsReverse[idNum] then
        visit(resolvedIDsReverse[idNum])
    end
    if collectibleType == "mount" and C_MountJournal then
        if C_MountJournal.GetMountFromItem then
            local ok, mid = pcall(C_MountJournal.GetMountFromItem, idNum)
            if ok and type(mid) == "number" and mid > 0 and mid ~= idNum
                and not (issecretvalue and issecretvalue(mid)) then
                visit(mid)
            end
        end
        if C_MountJournal.GetMountItemID then
            local ok, itemID = pcall(C_MountJournal.GetMountItemID, idNum)
            if ok and type(itemID) == "number" and itemID > 0
                and not (issecretvalue and issecretvalue(itemID)) then
                visit(itemID)
            end
        end
    elseif collectibleType == "pet" and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local ok, sid = pcall(function()
            return select(13, C_PetJournal.GetPetInfoByItemID(idNum))
        end)
        if ok and type(sid) == "number" and sid > 0
            and not (issecretvalue and issecretvalue(sid)) then
            visit(sid)
        end
    end
end

function Fns.MaxTryCountAliasKeys(collectibleType, id, primary)
    local best = type(primary) == "number" and primary or 0
    if not VALID_TYPES[collectibleType] or not Fns.EnsureDB() then return best end
    local tbl = WarbandNexus.db.global.tryCounts[collectibleType]
    if not tbl then return best end
    Fns.ForEachTryCountAliasKey(collectibleType, id, function(key)
        local v = tbl[key]
        if type(v) == "number" and v > best then best = v end
    end)
    return best
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@param count number
function WarbandNexus:SetTryCount(collectibleType, id, count)
    if not VALID_TYPES[collectibleType] or not id then return end
    if not Fns.EnsureDB() then return end
    count = tonumber(count)
    if not count or count < 0 then count = 0 end
    WarbandNexus.db.global.tryCounts[collectibleType][id] = count
    Fns.SchedulePlansTryCountUIUpdate()
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@return number newCount
function WarbandNexus:IncrementTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not Fns.EnsureDB() then return 0 end
    
    local stored = WarbandNexus.db.global.tryCounts[collectibleType][id]
    local currentStored = type(stored) == "number" and stored or 0
    local newStored = currentStored + 1
    WarbandNexus.db.global.tryCounts[collectibleType][id] = newStored
    
    return WarbandNexus:GetTryCount(collectibleType, id)
end

---Add multiple attempts at once (AoE farm: N corpses × same repeatable mount table).
---@param collectibleType string
---@param id number
---@param delta number
---@return number newCount
function WarbandNexus:AddTryCountDelta(collectibleType, id, delta)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not Fns.EnsureDB() then return 0 end
    delta = tonumber(delta) or 0
    if delta <= 0 then return WarbandNexus:GetTryCount(collectibleType, id) end
    local stored = WarbandNexus.db.global.tryCounts[collectibleType][id]
    local currentStored = type(stored) == "number" and stored or 0
    WarbandNexus.db.global.tryCounts[collectibleType][id] = currentStored + delta
    return WarbandNexus:GetTryCount(collectibleType, id)
end

---Reset try count to 0 for a repeatable collectible (BoE/farmable mounts).
---Called when a repeatable mount is obtained so the counter restarts for the next farm session.
---Alias keys must be zeroed too: GetTryCount maxes across them, so a reset that only
---touched the exact key resurrected the old count on the next read.
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
function WarbandNexus:ResetTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return end
    if not Fns.EnsureDB() then return end
    local tbl = WarbandNexus.db.global.tryCounts[collectibleType]
    tbl[id] = 0
    Fns.ForEachTryCountAliasKey(collectibleType, id, function(key)
        if type(tbl[key]) == "number" and tbl[key] > 0 then
            tbl[key] = 0
        end
    end)
end

-- Bag scan (BAG_UPDATE_DELAYED) fires the same moment as loot; suppress duplicate mount/pet/toy toasts.
local tryCounterLootToastAtForBagScan = {}
local TRY_TC_BAG_SCAN_SUPPRESS_SEC = 8

---@param collectibleType string
---@param notifyId number|any id field sent in WN_COLLECTIBLE_OBTAINED
---@param sourceItemID number|nil teaching item / bag item when known
function WarbandNexus:RegisterTryCounterLootToastForBagDedupe(collectibleType, notifyId, sourceItemID)
    if not collectibleType or notifyId == nil then return end
    local now = GetTime()
    local function mark(key)
        if key then tryCounterLootToastAtForBagScan[key] = now end
    end
    mark(collectibleType .. "\0" .. tostring(notifyId))
    if collectibleType == "mount" and sourceItemID and type(sourceItemID) == "number" then
        mark("mount\0" .. tostring(sourceItemID))
        if C_MountJournal and C_MountJournal.GetMountFromItem then
            local mid = C_MountJournal.GetMountFromItem(sourceItemID)
            if mid and not (issecretvalue and issecretvalue(mid)) and type(mid) == "number" and mid > 0 then
                mark("mount\0" .. tostring(mid))
            end
        end
    end
    if collectibleType == "pet" and sourceItemID and type(sourceItemID) == "number" and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local sid = select(13, C_PetJournal.GetPetInfoByItemID(sourceItemID))
        if sid and not (issecretvalue and issecretvalue(sid)) and type(sid) == "number" and sid > 0 then
            mark("pet\0" .. tostring(sid))
        end
    end
    if collectibleType == "toy" and sourceItemID and type(sourceItemID) == "number" then
        mark("toy\0" .. tostring(sourceItemID))
    end
end

---@param collectibleType string
---@param collectibleID number
---@param itemID number|nil
---@return boolean
function WarbandNexus:ShouldSuppressBagCollectibleToastAsTryCounterDuplicate(collectibleType, collectibleID, itemID)
    if not collectibleType or collectibleID == nil then return false end
    local now = GetTime()
    local function recent(key)
        local t = tryCounterLootToastAtForBagScan[key]
        return t and (now - t) < TRY_TC_BAG_SCAN_SUPPRESS_SEC
    end
    if recent(collectibleType .. "\0" .. tostring(collectibleID)) then return true end
    if collectibleType == "mount" and itemID and type(itemID) == "number" then
        if recent("mount\0" .. tostring(itemID)) then return true end
        if C_MountJournal and C_MountJournal.GetMountFromItem then
            local mid = C_MountJournal.GetMountFromItem(itemID)
            if mid and not (issecretvalue and issecretvalue(mid)) and type(mid) == "number" and mid > 0 then
                if recent("mount\0" .. tostring(mid)) then return true end
            end
        end
    end
    if collectibleType == "pet" and itemID and type(itemID) == "number" and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
        local sid = select(13, C_PetJournal.GetPetInfoByItemID(itemID))
        if sid and not (issecretvalue and issecretvalue(sid)) and type(sid) == "number" and sid > 0 then
            if recent("pet\0" .. tostring(sid)) then return true end
        end
    end
    if collectibleType == "toy" and itemID and type(itemID) == "number" then
        if recent("toy\0" .. tostring(itemID)) then return true end
    end
    return false
end

local function SendTryCounterCollectibleObtained(self, payload, sourceItemID)
    if not self or not self.SendMessage or not payload then return end
    if not payload.obtainedBy then
        local name = UnitName("player")
        if name and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            payload.obtainedBy = name
        end
    end
    if payload.type and payload.id ~= nil then
        WarbandNexus:RegisterTryCounterLootToastForBagDedupe(payload.type, payload.id, sourceItemID)
    end
    self:SendMessage(E.COLLECTIBLE_OBTAINED, payload)
end

---Mark a drop item as obtained so the try counter stops tracking it.
---Useful for items with delayed yields (e.g. Nether-Warped Egg with 7-day hatch)
---or when the WoW collection API can't resolve the mount/pet ID.
---@param itemID number The item ID of the drop to mark
function WarbandNexus:MarkItemObtained(itemID)
    Fns.MarkItemObtained(itemID)
end

---Check if a drop item has been marked as obtained.
---@param itemID number
---@return boolean
function WarbandNexus:IsItemObtained(itemID)
    return Fns.IsItemMarkedObtained(itemID)
end

---Clear the obtained marker for a drop item (e.g. if marked by mistake).
---@param itemID number
function WarbandNexus:ClearItemObtained(itemID)
    if not itemID or not Fns.EnsureDB() then return end
    WarbandNexus.db.global.tryCounts.obtained[itemID] = nil
end

---Return quest-starter mounts (e.g. Stonevault Mechsuit) that are not yet collected, for Mounts browser.
---So they appear in Plans → Mounts tab even when not in C_MountJournal.GetMountIDs() yet (quest reward flow).
---@return table[] Array of { mountID = number, itemID = number, name = string }
function WarbandNexus:GetQuestStarterMountsForBrowser()
    if not reverseIndicesBuilt then Fns.BuildReverseIndices() end
    local out = {}
    for i = 1, #questStarterMountList do
        local entry = questStarterMountList[i]
        if entry and entry.itemID then
            local drop = { type = "mount", itemID = entry.itemID, name = entry.name }
            if not Fns.IsCollectibleCollected(drop) then
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

-- GUID PARSING (minimal allocation)

Fns.GetNPCIDFromGUID = function(guid)
    if not guid or type(guid) ~= "string" then return nil end
    -- Midnight 12.0: GUID may be a secret value during instanced combat
    if issecretvalue and issecretvalue(guid) then return nil end
    local cached = guidNpcIDCache[guid]
    if cached ~= nil then return cached or nil end
    local parts = { strsplit("-", guid) }
    local unitType = parts[1]
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        guidNpcIDCache[guid] = false
        return nil
    end
    local n = #parts
    if n < 3 then guidNpcIDCache[guid] = false; return nil end
    local last = parts[n]
    -- Final segment is usually hex spawn UID; entry id is the preceding numeric field.
    if last and last:match("^[0-9A-Fa-f]+$") and #last >= 10 then
        local pen = tonumber(parts[n - 1])
        if pen and pen > 0 then guidNpcIDCache[guid] = pen; return pen end
    end
    if n >= 7 then
        local id6 = tonumber(parts[6])
        if id6 and id6 > 0 then guidNpcIDCache[guid] = id6; return id6 end
    end
    if n >= 6 then
        local id5 = tonumber(parts[5])
        if id5 and id5 > 0 then guidNpcIDCache[guid] = id5; return id5 end
    end
    local ut, npcID = guid:match("^(%a+)%-.-%-.-%-.-%-.-%-(%d+)")
    if ut == unitType and npcID then
        local result = tonumber(npcID)
        guidNpcIDCache[guid] = result or false
        return result
    end
    guidNpcIDCache[guid] = false
    return nil
end

Fns.GetObjectIDFromGUID = function(guid)
    if not guid or type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    local cached = guidObjectIDCache[guid]
    if cached ~= nil then return cached or nil end
    local parts = { strsplit("-", guid) }
    if parts[1] ~= "GameObject" then
        guidObjectIDCache[guid] = false
        return nil
    end
    local n = #parts
    if n < 3 then guidObjectIDCache[guid] = false; return nil end
    local last = parts[n]
    if last and last:match("^[0-9A-Fa-f]+$") and #last >= 10 then
        local pen = tonumber(parts[n - 1])
        if pen and pen > 0 then guidObjectIDCache[guid] = pen; return pen end
    end
    if n >= 7 then
        local id6 = tonumber(parts[6])
        if id6 and id6 > 0 then guidObjectIDCache[guid] = id6; return id6 end
    end
    if n >= 6 then
        local id5 = tonumber(parts[5])
        if id5 and id5 > 0 then guidObjectIDCache[guid] = id5; return id5 end
    end
    local ut, objectID = guid:match("^(%a+)%-.-%-.-%-.-%-.-%-(%d+)")
    if ut == "GameObject" and objectID then
        local result = tonumber(objectID)
        guidObjectIDCache[guid] = result or false
        return result
    end
    guidObjectIDCache[guid] = false
    return nil
end

-- COLLECTIBLE ID RESOLUTION (runtime mount/pet ID lookup)

function Fns.ResolveCollectibleID(drop)
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
        resolvedIDsReverse[id] = drop.itemID
    end

    return id
end

function Fns.GetTryCountKey(drop)
    if not drop or not drop.itemID then return nil end
    -- Try native resolution first (mountID/speciesID)
    local collectibleID = Fns.ResolveCollectibleID(drop)
    if collectibleID then return collectibleID end
    -- Fallback: use itemID directly as the try count key
    -- This means the DB stores tryCounts.mount[itemID] instead of tryCounts.mount[mountID]
    -- for items where the API can't resolve. Slightly inconsistent keys but guarantees tracking.
    return drop.itemID
end

function Fns.GetTryCountTypeAndKey(drop)
    if not drop then return nil, nil end
    if drop.tryCountReflectsTo and drop.tryCountReflectsTo.type and drop.tryCountReflectsTo.itemID then
        local ref = drop.tryCountReflectsTo
        local key = Fns.ResolveCollectibleID(ref) or ref.itemID
        return ref.type, key
    end
    local key = Fns.GetTryCountKey(drop)
    return drop.type, key
end

-- PUBLIC QUERY API (O(1) index lookups, replaces old O(N) full-DB scans)
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
RT.pendingPreResetCounts = pendingPreResetCounts

-- ops-030: bind mutable tables/constants for handler satellite
RT.npcDropDB = npcDropDB
RT.tryCounterNpcEligible = tryCounterNpcEligible
RT.encounterDB = encounterDB
RT.encounterNameToNpcs = encounterNameToNpcs
RT.currentEncounterCache = currentEncounterCache
RT.recentKills = recentKills
RT.lootSession = lootSession
RT.pendingIncrementAnnounces = pendingIncrementAnnounces
RT.pendingLootSessionFinalize = pendingLootSessionFinalize
RT.lootReady = lootReady
RT.fishingCtx = fishingCtx
RT.repeatableItemDrops = repeatableItemDrops
RT.chatLootItemToNpc = chatLootItemToNpc
RT.chatLootTrackedItems = chatLootTrackedItems
RT.chatLootItemUniqueNpc = chatLootItemUniqueNpc
RT.ENCOUNTER_CACHE_TTL = ENCOUNTER_CACHE_TTL
RT.LOOT_READY_STATE_TTL = LOOT_READY_STATE_TTL
RT.LOOT_SESSION_RECENT_TTL = LOOT_SESSION_RECENT_TTL
RT.CHAT_LOOT_DEBOUNCE = CHAT_LOOT_DEBOUNCE
RT.FISHING_CAST_CONTEXT_TTL = FISHING_CAST_CONTEXT_TTL
V.isPickpocketing = V.isPickpocketing or false
V.isProfessionLooting = V.isProfessionLooting or false
V.lastContainerItemID = V.lastContainerItemID
V.lastContainerItemTime = V.lastContainerItemTime or 0
V.lastTrackedObjectInteractID = V.lastTrackedObjectInteractID
V.lastTrackedObjectInteractGUID = V.lastTrackedObjectInteractGUID
V.lastTrackedObjectInteractTime = V.lastTrackedObjectInteractTime or 0
V.lastEncounterEndTime = V.lastEncounterEndTime or 0
V.lastTryCountSourceKey = V.lastTryCountSourceKey
V.lastTryCountSourceTime = V.lastTryCountSourceTime or 0
V.lastTryCountLootSourceGUID = V.lastTryCountLootSourceGUID
RT.lastLootSourceGUID = RT.lastLootSourceGUID
RT.lastLootSourceTime = RT.lastLootSourceTime or 0
-- Coalesce WN_PLANS_UPDATED try_count_set (SetTryCount + ProcessMissedDrops) into one UI refresh burst.
local plansTryCountNotifyTimer = nil
local PLANS_TRY_COUNT_NOTIFY_DEBOUNCE = 0.35

function Fns.SchedulePlansTryCountUIUpdate()
    if not WarbandNexus or not WarbandNexus.SendMessage or not E then return end
    if plansTryCountNotifyTimer and plansTryCountNotifyTimer.Cancel then
        plansTryCountNotifyTimer:Cancel()
        plansTryCountNotifyTimer = nil
    end
    local delay = PLANS_TRY_COUNT_NOTIFY_DEBOUNCE
    if type(delay) ~= "number" or delay <= 0 then delay = 0.35 end
    if C_Timer and C_Timer.NewTimer then
        plansTryCountNotifyTimer = C_Timer.NewTimer(delay, function()
            plansTryCountNotifyTimer = nil
            WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "try_count_set" })
        end)
        return
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "try_count_set" })
        end)
        return
    end
    WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "try_count_set" })
end

-- Drops found on this kill (loot/chat/journal) — blocks deferred ProcessMissedDrops after reset.
local dropObtainedThisKill = {}
local DROP_OBTAINED_KILL_TTL = 45
-- Chat+reset already emitted for this drop (LOOT_CLOSED finalize vs late CHAT_MSG_LOOT).
local obtainOutcomeApplied = {}
local OBTAIN_OUTCOME_APPLIED_TTL = 45

function Fns.IndexLookup(index, cache, collectibleType, id)
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
    -- but the index is keyed by itemID. Use the O(1) reverse map to find the source itemID.
    if collectibleType ~= "toy" then
        local sourceItemID = resolvedIDsReverse[id]
        if sourceItemID then
            local altKey = collectibleType .. "\0" .. tostring(sourceItemID)
            if index[altKey] then
                cache[cacheKey] = true
                return true
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
    return Fns.IndexLookup(guaranteedIndex, guaranteedCache, collectibleType, id)
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
    return Fns.IndexLookup(repeatableIndex, repeatableCache, collectibleType, id)
end

---Check if a collectible (type, id) exists in the drop source database at all.
---Returns true only for collectibles obtainable from NPC kills, objects, fishing,
---containers, or zone drops. Returns false for achievement, vendor, quest sources.
---O(1) index lookup (built at InitializeTryCounter time).
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number collectibleID (mountID/speciesID) or itemID for toys
---@return boolean
function WarbandNexus:IsDropSourceCollectible(collectibleType, id)
    return Fns.IndexLookup(dropSourceIndex, dropSourceCache, collectibleType, id)
end

---Whether try-count controls should appear in UI (Collections header, toy detail, plan cards, tracker).
---Rule: show when count > 0, or when the collectible is a non-guaranteed drop source.
---@param collectibleType string mount|pet|toy|illusion
---@param id number mountID, speciesID, itemID (toy), or illusion source id
---@return boolean
function WarbandNexus:ShouldShowTryCountInUI(collectibleType, id)
    if not id or not self.GetTryCount then return false end
    local count = self:GetTryCount(collectibleType, id) or 0
    if count > 0 then return true end
    if not self.IsDropSourceCollectible or not self:IsDropSourceCollectible(collectibleType, id) then return false end
    if self.IsGuaranteedCollectible and self:IsGuaranteedCollectible(collectibleType, id) then return false end
    return true
end

-- Session cache for difficulty lookups
local difficultyCache = {}

-- Maps WoW difficultyID (from ENCOUNTER_END / GetRaidDifficultyID / GetDungeonDifficultyID)
-- to our dropDifficulty label strings.  Complete as of Patch 12.0.5 (May 2026).
-- https://warcraft.wiki.gg/wiki/DifficultyID
-- Regression: tests/test_trycounter.lua mirrors this table plus ResolveDifficultyLabel, DoesDifficultyMatch, FilterDropsByDifficulty.
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
    [216] = "Normal",   -- Quest (party) — Midnight leveling/quest dungeons
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

function Fns.ResolveDifficultyLabel(difficultyID)
    if not difficultyID or type(difficultyID) ~= "number" then return nil end
    if issecretvalue and issecretvalue(difficultyID) then return nil end
    local mapped = DIFFICULTY_ID_TO_LABELS[difficultyID]
    if mapped then return mapped end
    if _G.GetDifficultyInfo then
        local ok, _, _, isHeroic, isChallengeMode, _, displayMythic, _, isLFR = pcall(_G.GetDifficultyInfo, difficultyID)
        if ok and isLFR then
            return "LFR"
        end
        if ok and isChallengeMode then
            return "Mythic"
        end
        if ok and displayMythic then
            return "Mythic"
        end
        if ok and isHeroic then
            return "Heroic"
        end
    end
    return nil
end

function Fns.ResolveLiveInstanceDifficultyID(instanceType, giDifficulty)
    local d = giDifficulty
    if d and issecretvalue and issecretvalue(d) then d = nil end
    if type(d) == "number" and d > 0 then return d end

    local it = instanceType
    if it and issecretvalue and issecretvalue(it) then it = nil end

    if it == "party" then
        local CCM = C_ChallengeMode
        if CCM and CCM.GetActiveKeystoneInfo then
            local level = select(1, CCM.GetActiveKeystoneInfo())
            if level and not (issecretvalue and issecretvalue(level)) and type(level) == "number" and level > 0 then
                return 8 -- Mythic Keystone
            end
        end
        local dd = GetDungeonDifficultyID and GetDungeonDifficultyID()
        if dd and not (issecretvalue and issecretvalue(dd)) and type(dd) == "number" and dd > 0 then
            return dd
        end
    elseif it == "raid" then
        local rd = GetRaidDifficultyID and GetRaidDifficultyID()
        if rd and not (issecretvalue and issecretvalue(rd)) and type(rd) == "number" and rd > 0 then
            return rd
        end
    end
    return nil
end

local function MatchSingleDifficulty(label, requiredDifficulty)
    if requiredDifficulty == "Mythic" then
        return label == "Mythic"
    elseif requiredDifficulty == "Heroic" then
        -- Threshold: Heroic+ (Heroic, Mythic, legacy 25H) — matches standard "drops on Heroic or higher" mounts
        -- like Invincible's Reins (25H only, covered by "25H" explicit) or Life-Binder's Handmaiden (Heroic+).
        return label == "Heroic" or label == "Mythic" or label == "25H"
    elseif requiredDifficulty == "25H" then
        return label == "25H"
    elseif requiredDifficulty == "Normal" then
        -- Flex Normal / Heroic / Mythic raid & legacy sizes — excludes LFR/TW-LFR.
        return label == "Normal" or label == "Heroic" or label == "Mythic" or label == "10N" or label == "25N"
    elseif requiredDifficulty == "10N" then
        return label == "10N"
    elseif requiredDifficulty == "25N" then
        return label == "25N"
    elseif requiredDifficulty == "25-man" then
        -- Legacy 25-player only (exclude 10-player and LFR); e.g. Ulduar Mimiron's Head.
        return label == "25N" or label == "25H"
    elseif requiredDifficulty == "LFR" then
        return label == "LFR"
    end
    return false
end

function Fns.DoesDifficultyMatch(difficultyID, requiredDifficulty)
    if not requiredDifficulty or requiredDifficulty == "All Difficulties" then
        return true
    end
    if not difficultyID then return false end
    if issecretvalue and issecretvalue(difficultyID) then return false end

    local label = Fns.ResolveDifficultyLabel(difficultyID)
    if not label then return false end

    -- Array form: explicit whitelist (OR across entries, no threshold expansion).
    if type(requiredDifficulty) == "table" then
        for i = 1, #requiredDifficulty do
            local req = requiredDifficulty[i]
            if type(req) == "string" and MatchSingleDifficulty(label, req) then
                return true
            end
        end
        return false
    end

    return MatchSingleDifficulty(label, requiredDifficulty)
end

function Fns.ResolveEffectiveEncounterDifficultyID(inInstance, recentKillDiff)
    -- Priority 0: ENCOUNTER_START cache (captured at pull, typically non-secret in Midnight 12.0).
    -- This beats GetInstanceInfo because it persists through the brief secret-value window that
    -- can wrap GetInstanceInfo return values during active encounters.
    if currentEncounterCache.difficultyID
        and type(currentEncounterCache.difficultyID) == "number"
        and currentEncounterCache.difficultyID > 0
        and currentEncounterCache.startTime > 0
        and (GetTime() - currentEncounterCache.startTime) <= ENCOUNTER_CACHE_TTL then
        return currentEncounterCache.difficultyID
    end

    if inInstance then
        local _, typ, liveDiff, _, _, _, _, iid = GetInstanceInfo()
        local safeIid = iid
        if safeIid and issecretvalue and issecretvalue(safeIid) then safeIid = nil end
        local safeLive = liveDiff
        if safeLive and issecretvalue and issecretvalue(safeLive) then safeLive = nil end
        local resolvedLive = Fns.ResolveLiveInstanceDifficultyID(typ, safeLive)
        if tryCounterInstanceDiffCache.instanceID and safeIid
            and tryCounterInstanceDiffCache.instanceID == safeIid
            and tryCounterInstanceDiffCache.difficultyID
            and tryCounterInstanceDiffCache.difficultyID > 0 then
            return tryCounterInstanceDiffCache.difficultyID
        end
        if resolvedLive then
            return resolvedLive
        end
    end
    if recentKillDiff and not (issecretvalue and issecretvalue(recentKillDiff)) then
        return recentKillDiff
    end
    if inInstance then
        local raw = GetRaidDifficultyID and GetRaidDifficultyID()
            or GetDungeonDifficultyID and GetDungeonDifficultyID()
            or nil
        if raw and not (issecretvalue and issecretvalue(raw)) then
            return raw
        end
    end
    return nil
end

function Fns.ResolveEncounterDifficultyForLootGating(inInstance, recentKillDiff, liveDifficultyID)
    local d = Fns.ResolveEffectiveEncounterDifficultyID(inInstance, recentKillDiff)
    if d and issecretvalue and issecretvalue(d) then
        d = nil
    end
    if not d and liveDifficultyID and not (issecretvalue and issecretvalue(liveDifficultyID)) then
        d = liveDifficultyID
    end
    if not d and inInstance then
        local _, _, liveDiff = GetInstanceInfo()
        if liveDiff and not (issecretvalue and issecretvalue(liveDiff)) then
            d = liveDiff
        end
    end
    return d
end

function Fns.FilterDropsByDifficulty(drops, encounterDiffID)
    local trackable = {}
    local diffSkipped = nil
    if not drops then return trackable, diffSkipped end
    local npcDropDifficulty = drops.dropDifficulty
    local npcDifficultyIDs = drops.difficultyIDs
    for i = 1, #drops do
        local drop = drops[i]
        local reqDiff = drop.dropDifficulty or npcDropDifficulty
        local reqDiffIDs = drop.difficultyIDs or npcDifficultyIDs
        local diffOk = true
        if reqDiff then
            if encounterDiffID then
                diffOk = Fns.DoesDifficultyMatch(encounterDiffID, reqDiff)
            else
                -- Fail-closed: drop requires a specific difficulty but we could not
                -- determine the current difficulty → do NOT count.  Prevents e.g.
                -- Mythic-only mounts being incremented on Normal when API returns nil.
                diffOk = false
            end
        end
        -- difficultyIDs whitelist: when present, encounter difficultyID MUST be in the list.
        -- Required because the "Mythic" label aliases multiple WoW IDs (16 = Mythic raid,
        -- 8 = Mythic Keystone, 23 = Mythic dungeon). Same npcID can appear in M+ dungeon
        -- AND raid (e.g. Midnight Falls — npcID 214650 in March on Quel'Danas Mythic raid vs the
        -- same npcID appearing in M+ Mythic dungeon contexts); the raid-only
        -- mount must not increment on M+ kills.
        if diffOk and reqDiffIDs and type(reqDiffIDs) == "table" and #reqDiffIDs > 0 then
            if not encounterDiffID or (issecretvalue and issecretvalue(encounterDiffID)) then
                diffOk = false
            else
                local match = false
                for j = 1, #reqDiffIDs do
                    if reqDiffIDs[j] == encounterDiffID then match = true; break end
                end
                diffOk = match
            end
        end
        if diffOk then
            if drop.repeatable or not Fns.IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        elseif not diffSkipped then
            diffSkipped = { drop = drop, required = reqDiff }
        end
    end

    -- Per-drop instance MapID exclusions (GetInstanceInfo index 8): same npcID reused across
    -- unrelated instances (e.g. Legion Seat of the Triumvirate vs Midnight raid Midnight Falls).
    if #trackable > 0 then
        local mapInstanceID = select(8, GetInstanceInfo())
        if mapInstanceID and type(mapInstanceID) == "number" and mapInstanceID > 0
            and not (issecretvalue and issecretvalue(mapInstanceID)) then
            local filtered = {}
            for ti = 1, #trackable do
                local drop = trackable[ti]
                local excl = drop and drop.excludeInstanceIDs
                local skip = false
                if type(excl) == "table" then
                    for ei = 1, #excl do
                        if excl[ei] == mapInstanceID then
                            skip = true
                            break
                        end
                    end
                end
                if not skip then
                    filtered[#filtered + 1] = drop
                end
            end
            trackable = filtered
        end
    end

    return trackable, diffSkipped
end

function Fns.DebugLogDifficultyFilterEmpty(WN, context, drops, encounterDiffID, trackable, diffSkipped)
    if not WN or not Fns.IsTryCounterLootDebugEnabled(WN) then return end
    if trackable and #trackable > 0 then return end
    local label = Fns.ResolveDifficultyLabel(encounterDiffID)
    local req = diffSkipped and diffSkipped.required or (drops and drops.dropDifficulty) or "?"
    local drop = diffSkipped and diffSkipped.drop
    local collected = (drop and Fns.IsCollectibleCollected(drop)) and "yes" or "no"
    local encStr = (encounterDiffID ~= nil) and tostring(encounterDiffID) or "nil"
    local labelStr = label or "nil"
    local tmpl = (ns.L and ns.L["TRYCOUNTER_DIFF_FILTER_DEBUG"])
        or "Difficulty filter: no trackable drops (encDiff=%s, label=%s, required=%s, collected=%s)."
    WN:Print("|cff9370DB[WN-TC]|r " .. format(tmpl, encStr, labelStr, tostring(req), collected)
        .. " [" .. tostring(context) .. "]")
end

function Fns.TryCounterProbeRequirementText(reqDiff)
    local L = ns.L
    if not reqDiff or reqDiff == "" or reqDiff == "All Difficulties" then
        return (L and L["TRYCOUNTER_PROBE_REQ_ANY"]) or "any difficulty"
    end
    if reqDiff == "Mythic" then return (L and L["TRYCOUNTER_PROBE_REQ_MYTHIC"]) or "Mythic only" end
    if reqDiff == "LFR" then return (L and L["TRYCOUNTER_PROBE_REQ_LFR"]) or "LFR only" end
    if reqDiff == "Normal" then return (L and L["TRYCOUNTER_PROBE_REQ_NORMAL_PLUS"]) or "Normal+ raid (not LFR)" end
    if reqDiff == "Heroic" then return (L and L["TRYCOUNTER_PROBE_REQ_HEROIC"]) or "Heroic+ (includes Mythic & 25H)" end
    if reqDiff == "25H" then return (L and L["TRYCOUNTER_PROBE_REQ_25H"]) or "25-player Heroic only" end
    if reqDiff == "10N" then return (L and L["TRYCOUNTER_PROBE_REQ_10N"]) or "10-player Normal only" end
    if reqDiff == "25N" then return (L and L["TRYCOUNTER_PROBE_REQ_25N"]) or "25-player Normal only" end
    if reqDiff == "25-man" then return (L and L["TRYCOUNTER_PROBE_REQ_25MAN"]) or "25-player Normal or Heroic" end
    return tostring(reqDiff)
end

function Fns.TryCounterDebugEmitMountProbeLine(WN, encName, ann, drop, npcDropDifficulty, effDiff)
    if not WN or not ann or not drop then return end
    local L = ns.L
    local reqDiff = drop.dropDifficulty or npcDropDifficulty
    local reqText = Fns.TryCounterProbeRequirementText(reqDiff)
    local diffUnknown = not effDiff or (issecretvalue and issecretvalue(effDiff))
    local diffMatches = not diffUnknown
        and (not reqDiff or reqDiff == "All Difficulties" or Fns.DoesDifficultyMatch(effDiff, reqDiff))
    local collectedNonRepeat = (not drop.repeatable) and Fns.IsCollectibleCollected(drop)
    local statusText
    if collectedNonRepeat then
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_COLLECTED"]) or "Already collected"
    elseif diffUnknown then
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_DIFF_UNKNOWN"]) or "Difficulty unknown"
    elseif not diffMatches then
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_WRONG_DIFF"]) or "Not available on current difficulty"
    else
        statusText = (L and L["TRYCOUNTER_PROBE_STATUS_OBTAINABLE"]) or "Obtainable on current difficulty"
    end
    local mountDisp = tostring(ann.name or "?")
    local lineFmt = (L and L["TRYCOUNTER_PROBE_MOUNT_LINE"])
        or "%s > %s > %s > %s"
    local line = format(lineFmt,
        tostring(encName or "?"),
        mountDisp,
        reqText,
        statusText)
    Fns.TryCounterLootDebug(WN, "flow", "%s", line)
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
    -- but the index is keyed by itemID. Use O(1) reverse map instead of O(N) scan.
    if collectibleType ~= "toy" then
        local sourceItemID = resolvedIDsReverse[id]
        if sourceItemID then
            local altKey = collectibleType .. "\0" .. tostring(sourceItemID)
            local diff = dropDifficultyIndex[altKey]
            if diff then
                difficultyCache[cacheKey] = diff
                return diff
            end
        end
    end

    difficultyCache[cacheKey] = false
    return nil
end

-- COLLECTED CHECK (skip already-owned collectibles)

function Fns.IsMountLearnedByItemSpell(itemID)
    if not itemID or type(itemID) ~= "number" then return false end
    local spellID
    if C_Item and C_Item.GetItemSpell then
        _, spellID = C_Item.GetItemSpell(itemID)
    elseif _G.GetItemSpell then
        _, spellID = _G.GetItemSpell(itemID)
    end
    if not spellID or type(spellID) ~= "number" then return false end
    if issecretvalue and issecretvalue(spellID) then return false end
    local isk = _G.IsSpellKnown and _G.IsSpellKnown(spellID)
    if isk == true then return true end
    local isp = _G.IsPlayerSpell and _G.IsPlayerSpell(spellID)
    if isp == true then return true end
    -- Some clients expose spell book checks without globals
    if C_SpellBook and C_SpellBook.IsSpellInSpellBook then
        local ok, inBook = pcall(function()
            return C_SpellBook.IsSpellInSpellBook(spellID)
        end)
        if ok and inBook then return true end
    end
    return false
end

function Fns.IsPetLearnedByItemSpell(itemID)
    return Fns.IsMountLearnedByItemSpell(itemID)
end

Fns.IsCollectibleCollected = function(drop)
    if not drop then return false end

    local collectibleID = Fns.ResolveCollectibleID(drop)

    if drop.type == "item" then
        -- Short-circuit: if this item was already found in loot and marked as
        -- obtained (e.g. Nether-Warped Egg fished but mount still hatching),
        -- skip the yield/API check entirely.
        if Fns.IsItemMarkedObtained(drop.itemID) then return true end

        -- Accumulation items (Crackling Shard, Miscellaneous Mechanica): check if all
        -- yields (the end-goal mounts/pets they lead to) have been collected.
        -- If ALL yields are collected, stop tracking — no point farming further.
        -- This check applies EVEN to repeatable items: once Alunira is collected,
        -- no need to keep counting Crackling Shard attempts.
        if drop.yields and #drop.yields > 0 then
            local allCollected = true
            for i = 1, #drop.yields do
                local yield = drop.yields[i]
                local yieldDrop = { type = yield.type, itemID = yield.itemID, name = yield.name }
                if not Fns.IsCollectibleCollected(yieldDrop) then
                    allCollected = false
                    break  -- At least one yield still missing → keep tracking
                end
            end
            if allCollected then
                return true  -- All yields collected → treat item as "collected"
            else
                return false
            end
        end
        if drop.questStarters and #drop.questStarters > 0 then
            for i = 1, #drop.questStarters do
                local qs = drop.questStarters[i]
                if not Fns.IsCollectibleCollected(qs) then
                    return false
                end
            end
            return true
        end
        return false  -- No yields defined → always trackable
    elseif drop.type == "mount" then
        if collectibleID then
            local _, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(collectibleID)
            -- Midnight 12.0: isCollected may be a secret value — do not treat as "uncollected"
            if issecretvalue and isCollected and issecretvalue(isCollected) then
                return Fns.IsMountLearnedByItemSpell(drop.itemID)
            end
            if isCollected == true then return true end
            -- Journal false/nil but mount already learned (API lag, wrong ID resolution, or instance quirks)
            if Fns.IsMountLearnedByItemSpell(drop.itemID) then return true end
            return false
        end
        -- No journal ID (GetMountFromItem secret/unloaded): spell-known still detects learned mounts
        if Fns.IsMountLearnedByItemSpell(drop.itemID) then return true end
        return false
    elseif drop.type == "pet" then
        if collectibleID then
            local numCollected = C_PetJournal.GetNumCollectedInfo(collectibleID)
            -- Midnight 12.0: numCollected may be secret — use teach-spell fallback
            if issecretvalue and numCollected and issecretvalue(numCollected) then
                return Fns.IsPetLearnedByItemSpell(drop.itemID)
            end
            if numCollected and numCollected > 0 then return true end
            if Fns.IsPetLearnedByItemSpell(drop.itemID) then return true end
            return false
        end
        if Fns.IsPetLearnedByItemSpell(drop.itemID) then return true end
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

-- LOOT WINDOW SCANNING

function Fns.ScanLootForItems(expectedDrops, cachedNumLoot, cachedSlotData)
    local found = {}
    local numItems = (cachedNumLoot ~= nil and cachedSlotData ~= nil) and cachedNumLoot or (GetNumLootItems and GetNumLootItems() or 0)
    if not numItems or numItems == 0 then return found end

    local expectedSet = {}
    for i = 1, #expectedDrops do
        expectedSet[expectedDrops[i].itemID] = true
    end

    for i = 1, numItems do
        local hasItem, link
        if cachedSlotData and cachedSlotData[i] then
            hasItem = cachedSlotData[i].hasItem
            link = cachedSlotData[i].link
            -- Instance loot: links often resolve a frame after LOOT_OPENED; cached snapshot can be nil
            -- while the item is visible — refresh from live API so we don't double-count misses vs ENCOUNTER_END.
            if hasItem and (not link or type(link) ~= "string") and GetLootSlotLink then
                link = GetLootSlotLink(i)
                if link and issecretvalue and issecretvalue(link) then link = nil end
            end
        else
            hasItem = LootSlotHasItem and LootSlotHasItem(i)
            link = GetLootSlotLink and GetLootSlotLink(i)
            if link and issecretvalue and issecretvalue(link) then link = nil end
        end
        if hasItem and link and type(link) == "string"
            and not (issecretvalue and issecretvalue(link)) then
            -- GetItemInfoInstant's first return is item name, not ID — parse the hyperlink.
            local lootItemID = tonumber(link:match("|Hitem:(%d+):"))
            if lootItemID and expectedSet[lootItemID] then
                found[lootItemID] = true
            end
        end
    end

    return found
end

-- TRY COUNT INCREMENT + CHAT MESSAGE

function Fns.GetDropItemLink(drop)
    if not drop or not drop.itemID then
        return "|cffff8000[" .. (drop and drop.name or "Unknown") .. "]|r"
    end
    local GetItemInfo = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
    if GetItemInfo then
        local _, itemLink, itemQuality = GetItemInfo(drop.itemID)
        if itemLink then return itemLink end
        -- Not cached: GetItemInfo returns nil for all when item not loaded; quality from same call is nil. Use fallback color.
        -- Build fallback link with correct item quality color when we have quality
        if C_Item and C_Item.RequestLoadItemDataByID then
            pcall(C_Item.RequestLoadItemDataByID, drop.itemID)
        end
        local name = drop.name or "Unknown"
        local qualityColor = "|cffa335ee" -- Epic default when quality unknown
        if itemQuality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[itemQuality] then
            local c = ITEM_QUALITY_COLORS[itemQuality]
            qualityColor = format("|cff%02x%02x%02x", (c.r or 0) * 255, (c.g or 0) * 255, (c.b or 0) * 255)
        end
        return qualityColor .. "|Hitem:" .. drop.itemID .. ":0:0:0:0:0:0:0:0:0:0|h[" .. name .. "]|h|r"
    end
    return "|cffa335ee[" .. (drop.name or "Unknown") .. "]|r"
end

function Fns.BuildCollectibleObtainedChatLink(data)
    if not data or not data.type then
        return "|cffffffff[?]|r"
    end
    local nm = data.name
    if nm and issecretvalue and issecretvalue(nm) then nm = nil end
    if data.type == "mount" and C_MountJournal and data.id then
        if C_MountJournal.GetMountItemID then
            local ok, itemID = pcall(C_MountJournal.GetMountItemID, data.id)
            if ok and itemID and type(itemID) == "number" and itemID > 0 then
                return Fns.GetDropItemLink({ type = "mount", itemID = itemID, name = nm })
            end
        end
        local n = nm
        if (not n or n == "") and C_MountJournal.GetMountInfoByID then
            n = select(1, C_MountJournal.GetMountInfoByID(data.id))
            if n and issecretvalue and issecretvalue(n) then n = nil end
        end
        return "|cffffffff[" .. (n or "Mount") .. "]|r"
    end
    if data.type == "toy" or data.type == "item" then
        if data.id and type(data.id) == "number" then
            return Fns.GetDropItemLink({ type = data.type, itemID = data.id, name = nm })
        end
    end
    if data.type == "pet" and data.id and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, n = pcall(C_PetJournal.GetPetInfoBySpeciesID, data.id)
        if ok and n and type(n) == "string" and not (issecretvalue and issecretvalue(n)) and n ~= "" then
            return "|cff1eff00[" .. n .. "]|r"
        end
    end
    return "|cffffffff[" .. (nm or "?") .. "]|r"
end

function Fns.EmitTryCounterObtainChatFromCollectibleEvent(addon, data)
    if not addon or not data or data.fromTryCounter then return end
    -- Match NotificationManager try-count subtitle types (not title/achievement).
    local tryTypes = { mount = true, pet = true, toy = true, illusion = true, item = true }
    if not tryTypes[data.type] or data.id == nil then return end
    -- Loot path already printed chat and registered bag dedupe; NEW_MOUNT / journal fires shortly after.
    if addon.ShouldSuppressBagCollectibleToastAsTryCounterDuplicate
        and addon:ShouldSuppressBagCollectibleToastAsTryCounterDuplicate(data.type, data.id, nil) then
        return
    end
    if addon.IsGuaranteedCollectible and addon:IsGuaranteedCollectible(data.type, data.id) then return end

    local isDropSource = (data.preResetTryCount ~= nil)
        or (addon.IsDropSourceCollectible and addon:IsDropSourceCollectible(data.type, data.id))
    local failedCount = (data.preResetTryCount ~= nil) and data.preResetTryCount
        or (addon.GetTryCount and addon:GetTryCount(data.type, data.id))
        or 0
    local count = isDropSource and (failedCount + 1) or failedCount
    if count <= 0 then return end

    -- BuildObtainedChat uses preReset such that totalTries = preReset + 1. NotificationManager uses
    -- count = isDropSource and (failedCount + 1) or failedCount (no +1 when not a listed drop source).
    local preResetForChat = isDropSource and failedCount or math.max(0, failedCount - 1)
    local itemLink = Fns.BuildCollectibleObtainedChatLink(data)
    Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_OBTAINED", "Obtained %s!", itemLink, preResetForChat))
end

function Fns.NpcEntryHasStatisticIds(npcData)
    if not npcData or type(npcData) ~= "table" then return false end
    if npcData.statisticIds and #npcData.statisticIds > 0 then return true end
    for i = 1, #npcData do
        local d = npcData[i]
        if type(d) == "table" and d.statisticIds and #d.statisticIds > 0 then
            return true
        end
    end
    return false
end

function Fns.ResolveReseedStatIdsForDrop(drop, npcStatIds)
    if drop and drop.statisticIds and #drop.statisticIds > 0 then
        return drop.statisticIds
    end
    return npcStatIds
end

function Fns.MarkDropReseeded(tcType, tryKey)
    if not tcType or not tryKey then return end
    dropDelayedReseeded[tcType .. "\0" .. tostring(tryKey)] = true
end

function Fns.IsDropAlreadyCounted(tcType, tryKey)
    if not tcType or not tryKey then return false end
    return dropDelayedReseeded[tcType .. "\0" .. tostring(tryKey)] == true
end

function Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, tryKey)
    if not preResetCount or preResetCount <= 0 then return preResetCount end
    if not tcType or not tryKey then return preResetCount end
    local mk = tcType .. "\0" .. tostring(tryKey)
    if not dropDelayedReseeded[mk] then return preResetCount end
    dropDelayedReseeded[mk] = nil
    return preResetCount - 1
end

function Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
    if not tcType or not tryKey then return end
    local now = GetTime()
    local function mark(k)
        if k == nil then return end
        dropObtainedThisKill[tcType .. "\0" .. tostring(k)] = now
    end
    mark(tryKey)
    if drop and type(drop) == "table" and drop.itemID then
        mark(drop.itemID)
    end
    if tcType == "mount" and type(tryKey) == "number" and resolvedIDsReverse then
        local rev = resolvedIDsReverse[tryKey]
        if rev then mark(rev) end
    end
end

function Fns.IsDropObtainedThisKill(tcType, tryKey, drop)
    if not tcType or not tryKey then return false end
    local now = GetTime()
    local function recent(k)
        if k == nil then return false end
        local t = dropObtainedThisKill[tcType .. "\0" .. tostring(k)]
        return t and (now - t) < DROP_OBTAINED_KILL_TTL
    end
    if recent(tryKey) then return true end
    if drop and drop.itemID and recent(drop.itemID) then return true end
    return false
end

function Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
    if not tcType or not tryKey then return end
    local now = GetTime()
    local function mark(k)
        if k == nil then return end
        obtainOutcomeApplied[tcType .. "\0" .. tostring(k)] = now
    end
    mark(tryKey)
    if drop and type(drop) == "table" and drop.itemID then
        mark(drop.itemID)
    end
end

function Fns.IsObtainOutcomeApplied(tcType, tryKey, drop)
    if not tcType or not tryKey then return false end
    local now = GetTime()
    local function recent(k)
        if k == nil then return false end
        local t = obtainOutcomeApplied[tcType .. "\0" .. tostring(k)]
        return t and (now - t) < OBTAIN_OUTCOME_APPLIED_TTL
    end
    if recent(tryKey) then return true end
    if drop and drop.itemID and recent(drop.itemID) then return true end
    return false
end

function Fns.ClearTryCounterTransientKillMarks()
    wipe(dropObtainedThisKill)
    wipe(obtainOutcomeApplied)
end

function Fns.ShouldSkipMissIncrementForDrop(drop)
    if not drop then return false end
    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
    if not tryKey then return false end
    return Fns.IsDropObtainedThisKill(tcType, tryKey, drop)
end

---NEW_MOUNT_ADDED / NEW_PET_ADDED: definitive drop-acquired signal when no LOOT_OPENED ties to the kill
---(achievement grants, post-cinematic chests). Consumes the reseed mark so obtained chat shows the right count.
---@param tcType "mount"|"pet"
---@param collectibleID number mountID or speciesID
function Fns.HandleNewCollectibleAdded(tcType, collectibleID)
    if not Fns.IsAutoTryCounterEnabled() then return end
    if not collectibleID or type(collectibleID) ~= "number" or collectibleID <= 0 then return end
    if not Fns.EnsureDB() then return end

    local candidateKeys = { collectibleID }
    if tcType == "mount" and resolvedIDsReverse then
        local itemID = resolvedIDsReverse[collectibleID]
        if type(itemID) == "number" and itemID > 0 and itemID ~= collectibleID then
            candidateKeys[#candidateKeys + 1] = itemID
        end
    end

    local linkLabel = "|cffa335ee[#" .. tostring(collectibleID) .. "]|r"
    if tcType == "mount" and C_MountJournal and C_MountJournal.GetMountInfoByID then
        local ok, name = pcall(C_MountJournal.GetMountInfoByID, collectibleID)
        if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            linkLabel = "|cffa335ee[" .. name .. "]|r"
        end
    elseif tcType == "pet" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, name = pcall(C_PetJournal.GetPetInfoBySpeciesID, collectibleID)
        if ok and type(name) == "string" and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            linkLabel = "|cffa335ee[" .. name .. "]|r"
        end
    end

    for i = 1, #candidateKeys do
        local key = candidateKeys[i]
        if Fns.IsDropAlreadyCounted(tcType, key) then
            Fns.MarkDropObtainedThisKill(tcType, key, nil)
            local preResetCount = WarbandNexus:GetTryCount(tcType, key) or 0
            local adjusted = Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, key)
            local L = ns.L
            local total = (adjusted or 0) + 1
            local fmt
            if total <= 1 then
                fmt = (L and L["TRYCOUNTER_CHAT_OBTAINED_FIRST_LINK"]) or "You got %s on your first try!"
                Fns.TryChat("|cff9370DB[WN-Counter]|r |cffffffff" .. format(fmt, linkLabel) .. "|r")
            else
                fmt = (L and L["TRYCOUNTER_CHAT_OBTAINED_AFTER_LINK"]) or "You got %s after %d attempts!"
                Fns.TryChat("|cff9370DB[WN-Counter]|r |cffffffff" .. format(fmt, linkLabel, total) .. "|r")
            end
            return
        end
    end
end

function WarbandNexus:OnTryCounterNewMountAdded(mountID)
    if issecretvalue and mountID and issecretvalue(mountID) then return end
    Fns.HandleNewCollectibleAdded("mount", tonumber(mountID))
end

function WarbandNexus:OnTryCounterNewPetAdded(petGUID)
    if not petGUID or type(petGUID) ~= "string" or petGUID == "" then return end
    if issecretvalue and issecretvalue(petGUID) then return end
    if not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then return end
    local ok, speciesID = pcall(C_PetJournal.GetPetInfoByPetID, petGUID)
    if not ok or type(speciesID) ~= "number" or speciesID <= 0 then return end
    if issecretvalue and issecretvalue(speciesID) then return end
    Fns.HandleNewCollectibleAdded("pet", speciesID)
end

--- Self-test fixtures (slash: /wn tc test — Modules/TryCounterService_SelfTest.lua).
TC.SELF_TEST_FAKE_ITEM_ID = 987654321

function Fns.ClearDeferredLootSession()
    pendingLootSessionFinalize = nil
    RT.pendingLootSessionFinalize = nil
end

function Fns.SetDeferredLootSessionSnapshot(pending)
    pendingLootSessionFinalize = pending
    RT.pendingLootSessionFinalize = pending
end

function Fns.SetTryCounterSelfTestSyncMiss(enabled)
    tryCounterSelfTestSyncMiss = not not enabled
end

--- Optional env for slot-first self-tests (SoD Sylvanas replay; no raid / owned-mount safe).
function Fns.SetTryCounterSelfTestSlotOutcomeEnv(env)
    if not env then
        tryCounterSelfTestSlotInstance = nil
        tryCounterSelfTestBossTrackable = nil
        return
    end
    tryCounterSelfTestSlotInstance = env.instance
    tryCounterSelfTestBossTrackable = env.bossTrackable
end

function Fns.GetSelfTestSampleIds()
    local containerID = nil
    for cid in pairs(containerDropDB or {}) do
        containerID = cid
        break
    end
    return {
        fakeItemID = TC.SELF_TEST_FAKE_ITEM_ID,
        containerID = containerID,
        objectID = 469857,
        rareNpcID = 230995,
        raidBossNpcID = 241526,
        mechanicaItemID = 234741,
        dumpsterGUID = "GameObject-0-0-0-0-469857-000000000000",
        rareNpcGUID = "Creature-0-0-0-0-230995-000000000000",
        raidBossGUID = "Creature-0-0-0-0-241526-000000000000",
        herbGUID = "GameObject-0-0-0-0-999999-000000000000",
    }
end

function Fns.SumStatisticTotalsFromIds(statIds)
    if not statIds or #statIds == 0 then return 0, false end
    local GetStat = GetStatistic
    if not GetStat then return 0, false end
    local total = 0
    local hadReadable = false
    for i = 1, #statIds do
        local sid = statIds[i]
        local val = GetStat(sid)
        local num
        if val and not (issecretvalue and issecretvalue(val)) then
            hadReadable = true
            local s = string.gsub(tostring(val), "[^%d]", "")
            if s ~= "" then
                num = tonumber(s)
            end
        end
        if num and num > 0 then
            total = total + num
        end
    end
    return total, hadReadable
end

function Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, thisCharTotal, hadReadable)
    if not charSnapshot or not tryKey or not hadReadable then return end
    charSnapshot[tryKey] = thisCharTotal
end

function Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
    if not snapshots or not tryKey then return 0 end
    local globalTotal = 0
    for _, snap in pairs(snapshots) do
        local charVal = snap[tryKey]
        if charVal and charVal > 0 then
            globalTotal = globalTotal + charVal
        end
    end
    return globalTotal
end

function Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable)
    if not tryKey or not tcType or not Fns.EnsureDB() then return false end
    if not hadReadable then return false end
    local WN = WarbandNexus
    local currentCount = WN:GetTryCount(tcType, tryKey) or 0
    local syncDown = WN.db.profile.notifications
        and WN.db.profile.notifications.syncTryCountDownToStatistics == true
    local newCount = currentCount
    if globalTotal > currentCount then
        newCount = globalTotal
    elseif syncDown and globalTotal < currentCount then
        newCount = globalTotal
    end
    if newCount == currentCount then return false end
    WN:SetTryCount(tcType, tryKey, newCount)
    return true
end

function Fns.InvalidateMergedStatisticSeedIndex()
    mergedStatSeedIndexDirty = true
end

function Fns.EnsureMergedStatisticSeedIndex()
    if not mergedStatSeedIndexDirty and #mergedStatSeedGroupList > 0 then
        return
    end
    if InCombatLockdown and InCombatLockdown() then
        mergedStatSeedIndexDirty = true
        return
    end
    Fns.RebuildMergedStatisticSeedIndex()
end

function Fns.RebuildMergedStatisticSeedIndex()
    local P = ns.Profiler
    if P and P.enabled and P.StartSlice then P:StartSlice(P.CAT.SVC, "TC_RebuildMergedStatIndex") end
    wipe(mergedStatSeedByTypeKey)
    wipe(mergedStatSeedGroupList)
    wipe(statSeedTryKeyPending)
    if not npcDropDB then
        mergedStatSeedIndexDirty = false
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_RebuildMergedStatIndex") end
        return
    end
    for _, npcData in pairs(npcDropDB) do
        local npcStatIds = npcData.statisticIds
        for idx = 1, #npcData do
            local drop = npcData[idx]
            if type(drop) == "table" and drop.type and drop.itemID and not drop.guaranteed then
                local sids = Fns.ResolveReseedStatIdsForDrop(drop, npcStatIds)
                if sids and #sids > 0 then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tcType and tryKey then
                        local mk = tcType .. "\0" .. tostring(tryKey)
                        local bucket = mergedStatSeedByTypeKey[mk]
                        if not bucket then
                            bucket = {
                                tcType = tcType,
                                tryKey = tryKey,
                                idSet = {},
                                drops = {},
                            }
                            mergedStatSeedByTypeKey[mk] = bucket
                            mergedStatSeedGroupList[#mergedStatSeedGroupList + 1] = bucket
                        end
                        for j = 1, #sids do
                            bucket.idSet[sids[j]] = true
                        end
                        bucket.drops[#bucket.drops + 1] = drop
                    else
                        statSeedTryKeyPending[#statSeedTryKeyPending + 1] = {
                            drop = drop,
                            npcStatIds = npcStatIds,
                        }
                    end
                end
            end
        end
    end
    for b = 1, #mergedStatSeedGroupList do
        local bucket = mergedStatSeedGroupList[b]
        local arr = {}
        for sid in pairs(bucket.idSet) do
            arr[#arr + 1] = sid
        end
        table.sort(arr)
        bucket.statIds = arr
        bucket.idSet = nil
    end
    mergedStatSeedIndexDirty = false
    if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_RebuildMergedStatIndex") end
end

function Fns.ResolveMergedStatisticIdsForDrop(drop, resolvedDropStatIds)
    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
    if tcType and tryKey then
        local mk = tcType .. "\0" .. tostring(tryKey)
        local bucket = mergedStatSeedByTypeKey[mk]
        if bucket and bucket.statIds and #bucket.statIds > 0 then
            return bucket.statIds
        end
    end
    if resolvedDropStatIds and #resolvedDropStatIds > 0 then
        return resolvedDropStatIds
    end
    return nil
end

function Fns.PruneStatisticSnapshotsOrphanKeys()
    local P = ns.Profiler
    if P and P.enabled and P.StartSlice then P:StartSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
    if not Fns.EnsureDB() then
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
        return
    end
    local db = WarbandNexus.db.global
    local snaps = db.statisticSnapshots
    local chars = db.characters
    if not snaps or not chars or type(snaps) ~= "table" or type(chars) ~= "table" then
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
        return
    end
    local nChar = 0
    for _ in pairs(chars) do
        nChar = nChar + 1
    end
    if nChar == 0 then
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
        return
    end

    local CS = ns.CharacterService
    local removed = 0
    for ck in pairs(snaps) do
        local owned = false
        if CS and CS.CharacterOwnsSubsidiaryKey then
            owned = CS:CharacterOwnsSubsidiaryKey(WarbandNexus, ck)
        else
            owned = chars[ck] ~= nil
        end
        if not owned then
            snaps[ck] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        WarbandNexus:Debug("TryCounter: Pruned %d orphan statisticSnapshots (no roster match)", removed)
    end
    if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_PruneStatSnapshots") end
end

function Fns.ReseedStatisticsForDrops(drops, resolvedDropStatIds)
    local P = ns.Profiler
    if P and P.enabled and P.StartSlice then P:StartSlice(P.CAT.SVC, "TC_ReseedStatisticsForDrops") end
    local function finish()
        if P and P.enabled and P.StopSlice then P:StopSlice(P.CAT.SVC, "TC_ReseedStatisticsForDrops") end
    end
    if not drops or #drops == 0 then finish() return end
    if not Fns.EnsureDB() then finish() return end
    if not GetStatistic then finish() return end

    Fns.EnsureMergedStatisticSeedIndex()

    local charKey = StatisticSnapshotStorageKey()
    if not charKey then finish() return end

    local snapshots = WarbandNexus.db.global.statisticSnapshots
    if not snapshots then
        WarbandNexus.db.global.statisticSnapshots = {}
        snapshots = WarbandNexus.db.global.statisticSnapshots
    end
    if not snapshots[charKey] then
        snapshots[charKey] = {}
    end
    local charSnapshot = snapshots[charKey]

    local function ProcessSeedDrop(drop, statListOverride)
        if drop and not drop.guaranteed then
            local skipStatSeed = (drop.type == "mount" or drop.type == "pet" or drop.type == "toy")
                and Fns.IsCollectibleCollected(drop)
            if not skipStatSeed then
                local statList = statListOverride or Fns.ResolveMergedStatisticIdsForDrop(drop, resolvedDropStatIds)
                if statList and #statList > 0 then
                    local thisCharTotal, hadReadable = Fns.SumStatisticTotalsFromIds(statList)
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey and tcType then
                        Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, thisCharTotal, hadReadable)
                        local globalTotal = Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
                        Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable)
                        local newCount = WarbandNexus:GetTryCount(tcType, tryKey) or 0

                        if drop.type == "item" and drop.questStarters then
                            for i = 1, #drop.questStarters do
                                local qs = drop.questStarters[i]
                                if qs.type == "mount" and qs.itemID and not Fns.IsCollectibleCollected(qs) then
                                    local mountKey1 = Fns.ResolveCollectibleID(qs)
                                    local mountKey2 = qs.itemID
                                    local mk = mountKey1 or mountKey2
                                    WarbandNexus:SetTryCount("mount", mk, math.max(newCount, WarbandNexus:GetTryCount("mount", mk) or 0))
                                    if mountKey1 and mountKey1 ~= mountKey2 then
                                        WarbandNexus:SetTryCount("mount", mountKey2, math.max(newCount, WarbandNexus:GetTryCount("mount", mountKey2) or 0))
                                    end
                                    RegisterQuestStarterMountKey(mk, drop.itemID)
                                    if mountKey1 and mountKey1 ~= mountKey2 then
                                        RegisterQuestStarterMountKey(mountKey2, drop.itemID)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
        if drop and drop.questStarters then
            for i = 1, #drop.questStarters do
                local qs = drop.questStarters[i]
                ProcessSeedDrop(qs, nil)
            end
        end
    end

    for i = 1, #drops do
        ProcessSeedDrop(drops[i], nil)
    end

    if WarbandNexus.SendMessage then
        WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_reseeded" })
    end
    finish()
end

function Fns.DropsHaveStatBackedReseed(drops, npcStatIds)
    for i = 1, #drops do
        local sids = Fns.ResolveReseedStatIdsForDrop(drops[i], npcStatIds)
        if sids and #sids > 0 then return true end
    end
    return false
end

--- Queue miss-increment chat until LOOT_CLOSED so boss loot lines stay grouped (not item/item/try/item).
function Fns.RunOrDeferTryCounterIncrementAnnounce(emitFn)
    if type(emitFn) ~= "function" then return end
    if lootSession.opened then
        pendingIncrementAnnounces[#pendingIncrementAnnounces + 1] = emitFn
        return
    end
    emitFn()
end

function Fns.FlushDeferredTryCounterIncrementAnnounces()
    if #pendingIncrementAnnounces == 0 then return end
    local batch = pendingIncrementAnnounces
    pendingIncrementAnnounces = {}
    for i = 1, #batch do
        local fn = batch[i]
        if type(fn) == "function" then fn() end
    end
end

function Fns.EmitTryCounterIncrementAnnounce(incrementAnnounce)
    if not incrementAnnounce or not next(incrementAnnounce) then return end
    Fns.RunOrDeferTryCounterIncrementAnnounce(function()
        for _, info in pairs(incrementAnnounce) do
            local link = info.drop and Fns.GetDropItemLink(info.drop)
            local count = info.finalCount or info.added
            if link and count and count > 0 then
                local tmpl = (ns.L and ns.L["TRYCOUNTER_INCREMENT_CHAT"]) or "%d attempts for %s"
                Fns.TryChat("|cff9370DB[WN-Counter]|r |cffffffff" .. format(tmpl, count, link) .. "|r")
            end
        end
    end)
end

function Fns.ProcessMissedDrops(drops, statIds, options)
    if not drops or #drops == 0 then return end
    if not Fns.EnsureDB() then return end

    -- Drop entries queued before deferred run may now resolve as collected (journal/spell).
    -- Repeatable farm mounts stay eligible even when owned.
    -- Same-kill dedup: skip drops already found this kill (dropObtainedThisKill only).
    -- Do not reuse IsDropAlreadyCounted (dropDelayedReseeded) here — that mark is per tryKey and
    -- shared across open-world rares that drop the same mount; filtering on it would break farms.
    local filtered = {}
    for i = 1, #drops do
        local d = drops[i]
        if d and not Fns.ShouldSkipMissIncrementForDrop(d)
            and (d.repeatable or not Fns.IsCollectibleCollected(d)) then
            filtered[#filtered + 1] = d
        end
    end
    if #filtered == 0 then return end
    drops = filtered

    local attemptTimes = options and tonumber(options.attemptTimes) or 1
    if attemptTimes < 1 then attemptTimes = 1 end
    local statLootMissFb = options and options.statReseedLootMissFallback

    local allRepeatableMisses = true
    for i = 1, #drops do
        if not drops[i].repeatable then
            allRepeatableMisses = false
            break
        end
    end

    if Fns.DropsHaveStatBackedReseed(drops, statIds) and not allRepeatableMisses then
        local announceTry = Fns.IsAutoTryCounterEnabled()
        local syncNow = tryCounterSelfTestSyncMiss or (options and options.sync == true)

        local function runStatMissReseedJob()
            if not Fns.EnsureDB() then return end
            local WN = WarbandNexus
            local incrementAnnounce = {}
            for i = 1, #drops do
                local drop = drops[i]
                local sids = Fns.ResolveReseedStatIdsForDrop(drop, statIds)
                if sids and #sids > 0 then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    local prevCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
                    local statSumBefore = select(1, Fns.SumStatisticTotalsFromIds(sids))
                    Fns.ReseedStatisticsForDrops({ drop }, sids)
                    local newCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
                    if statLootMissFb and tryKey and newCount <= prevCount and drop and not drop.guaranteed
                        and (drop.repeatable or not Fns.IsCollectibleCollected(drop)) then
                        if prevCount > statSumBefore or (prevCount == 0 and statSumBefore == 0) then
                            newCount = WN:AddTryCountDelta(tcType, tryKey, 1)
                        end
                    end
                    if tryKey and newCount > prevCount then
                        Fns.MarkDropReseeded(tcType, tryKey)
                        if announceTry then
                            local mergeKey = tcType .. "\0" .. tostring(tryKey)
                            incrementAnnounce[mergeKey] = { drop = drop, finalCount = newCount }
                        end
                    end
                end
            end
            if announceTry and next(incrementAnnounce) then
                Fns.EmitTryCounterIncrementAnnounce(incrementAnnounce)
            end
        end

        if syncNow then
            runStatMissReseedJob()
        else
            C_Timer.After(2, runStatMissReseedJob)
        end
        return
    end

    local syncNow = tryCounterSelfTestSyncMiss or (options and options.sync == true)

    local function runManualMissIncrementJob()
        if not Fns.EnsureDB() then return end
        local WN = WarbandNexus
        local announceTry = Fns.IsAutoTryCounterEnabled()
        local incrementAnnounce = {}
        local function MirrorQuestStarterMountsToCount(drop, newCount)
            if drop.type ~= "item" or not drop.questStarters or drop.tryCountReflectsTo then return end
            for qi = 1, #drop.questStarters do
                local qs = drop.questStarters[qi]
                if qs.type == "mount" and qs.itemID and not Fns.IsCollectibleCollected(qs) then
                    local k1 = Fns.ResolveCollectibleID(qs)
                    local k2 = qs.itemID
                    WN:SetTryCount("mount", k1 or k2, newCount)
                    if k1 and k1 ~= k2 then
                        WN:SetTryCount("mount", k2, newCount)
                    end
                    RegisterQuestStarterMountKey(k1 or k2, drop.itemID)
                    if k1 and k1 ~= k2 then RegisterQuestStarterMountKey(k2, drop.itemID) end
                end
            end
        end

        local function ProcessManualDrop(drop, mult, fromRecursion)
            mult = tonumber(mult) or attemptTimes
            if mult < 1 then mult = 1 end
            if drop and drop.repeatable ~= true and Fns.IsCollectibleCollected(drop) then
                return
            end
            if drop and not drop.guaranteed then
                local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                if tryKey then
                    local prevCount = WN:GetTryCount(tcType, tryKey) or 0
                    local newCount = prevCount
                    for step = 1, mult do
                        newCount = WN:AddTryCountDelta(tcType, tryKey, 1)
                        MirrorQuestStarterMountsToCount(drop, newCount)
                    end
                    local added = (newCount or 0) - prevCount
                    if announceTry and not fromRecursion and added > 0 then
                        local mergeKey = tcType .. "\0" .. tostring(tryKey)
                        local ex = incrementAnnounce[mergeKey]
                        if ex then
                            ex.added = ex.added + added
                            ex.finalCount = newCount
                        else
                            incrementAnnounce[mergeKey] = {
                                drop = drop,
                                added = added,
                                finalCount = newCount,
                            }
                        end
                    end
                end
            end
            if drop and drop.questStarters then
                for i = 1, #drop.questStarters do
                    local qs = drop.questStarters[i]
                    if not (drop.type == "item" and qs.type == "mount") then
                        ProcessManualDrop(qs, 1, true)
                    end
                end
            end
        end

        for i = 1, #drops do
            ProcessManualDrop(drops[i], attemptTimes, false)
        end
        if announceTry and next(incrementAnnounce) then
            Fns.EmitTryCounterIncrementAnnounce(incrementAnnounce)
        end
        Fns.SchedulePlansTryCountUIUpdate()
    end

    if syncNow then
        runManualMissIncrementJob()
    else
        C_Timer.After(0, runManualMissIncrementJob)
    end
end

-- SETTING CHECK

function Fns.IsTryCounterModuleEnabled()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return false end
    if WarbandNexus.db.profile.modulesEnabled and WarbandNexus.db.profile.modulesEnabled.tryCounter == false then
        return false
    end
    return true
end

function Fns.GetTryCounterDisabledReason()
    if not Fns.IsTryCounterModuleEnabled() then return "module" end
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile.notifications then
        return "auto"
    end
    if WarbandNexus.db.profile.notifications.autoTryCounter ~= true then
        return "auto"
    end
    return nil
end

function Fns.PrintTryCounterDisabledHint(WN)
    WN = WN or WarbandNexus
    if not WN or not WN.Print then return end
    local reason = Fns.GetTryCounterDisabledReason()
    if not reason then return end
    local L = ns.L
    local key = (reason == "module") and "TRYCOUNTER_DISABLED_MODULE" or "TRYCOUNTER_DISABLED_AUTO"
    local msg = (L and L[key])
        or "Try Counter is disabled in Settings - kills are not counted."
    WN:Print("|cffff6600[WN-Counter]|r " .. msg)
end

function Fns.IsAutoTryCounterEnabled()
    return Fns.GetTryCounterDisabledReason() == nil
end

function Fns.IsTryCounterChatHidden()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile
        or not WarbandNexus.db.profile.notifications then
        return false
    end
    return WarbandNexus.db.profile.notifications.hideTryCounterChat == true
end

function Fns.IsTryCounterInstanceEntryDropLinesEnabled()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile or not WarbandNexus.db.profile.notifications then
        return true
    end
    local v = WarbandNexus.db.profile.notifications.tryCounterInstanceEntryDropLines
    if v == false then return false end
    return true
end

-- LOCKOUT QUEST CHECK (daily/weekly rare kill gating)

function Fns.IsLockoutDuplicate(npcID)
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

function Fns.SyncLockoutState()
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end

    -- Phase 1: Clean stale entries (quest has reset since last session)
    for questID, _ in pairs(lockoutAttempted) do
        if not C_QuestLog.IsQuestFlaggedCompleted(questID) then
            lockoutAttempted[questID] = nil
            lockoutPreCompletedAtLogin[questID] = nil
        end
    end

    -- Phase 2: Pre-populate from currently flagged quests.
    -- If a lockout quest is already flagged on login/reload, the player used their
    -- attempt in a prior session. Mark it so IsLockoutDuplicate() correctly skips.
    for _, questData in pairs(lockoutQuestsDB) do
        local questIDs = type(questData) == "table" and questData or { questData }
        for i = 1, #questIDs do
            local qid = questIDs[i]
            if C_QuestLog.IsQuestFlaggedCompleted(qid) then
                if not lockoutAttempted[qid] then
                    lockoutAttempted[qid] = true
                end
                lockoutPreCompletedAtLogin[qid] = true
            end
        end
    end

    Fns.RefreshLockoutQuestSnapshot()
end

function Fns.CancelLockoutQuestFallbackForNpc(npcID)
    if not npcID then return end
    local questData = lockoutQuestsDB[npcID]
    if not questData then return end
    local questIDs = type(questData) == "table" and questData or { questData }
    for i = 1, #questIDs do
        local qid = questIDs[i]
        local handle = lockoutQuestFallbackTimers[qid]
        if handle and handle.Cancel then
            handle:Cancel()
        end
        lockoutQuestFallbackTimers[qid] = nil
    end
end

function Fns.ScheduleLockoutQuestFallback(npcID, questID)
    if not npcID or not questID or lockoutAttempted[questID] then return end
    local existing = lockoutQuestFallbackTimers[questID]
    if existing and existing.Cancel then
        existing:Cancel()
    end
    lockoutQuestFallbackTimers[questID] = C_Timer.After(LOCKOUT_QUEST_LOOT_DEFER_SEC, function()
        lockoutQuestFallbackTimers[questID] = nil
        if not Fns.IsAutoTryCounterEnabled() then return end
        if lockoutAttempted[questID] then return end
        if pendingLootSessionFinalize then return end
        if Fns.IsLootSessionPendingOrRecent(LOOT_SESSION_RECENT_TTL) then return end
        if Fns.WasLockoutLootTouchedRecently(npcID, 180) then return end
        if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
        local ok, stillComplete = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
        if not ok or not stillComplete then return end
        Fns.ProcessLockoutQuestTryCount(npcID, questID)
    end)
end

function Fns.ShouldAnnounceLockoutSkip(npcID)
    if not npcID then return false end
    local questData = lockoutQuestsDB[npcID]
    if not questData then return false end
    local questIDs = type(questData) == "table" and questData or { questData }
    for i = 1, #questIDs do
        if lockoutPreCompletedAtLogin[questIDs[i]] then
            return true
        end
    end
    return false
end

function Fns.RefreshLockoutQuestSnapshot()
    wipe(lockoutQuestSnapshot)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
    for _, questData in pairs(lockoutQuestsDB) do
        local questIDs = type(questData) == "table" and questData or { questData }
        for i = 1, #questIDs do
            local qid = questIDs[i]
            local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
            if ok and result then
                lockoutQuestSnapshot[qid] = true
            end
        end
    end
end

--- Weekly/daily rare fallback: when the hidden lockout quest flips, count the attempt even if
--- LOOT_OPENED could not resolve a corpse GUID (phase rares, secret GUIDs, parachute delay).
function Fns.ProcessLockoutQuestTryCount(npcID, questID)
    if not npcID or not questID then return end
    if not tryCounterNpcEligible[npcID] or not npcDropDB[npcID] then return end

    local tryCountSourceKey = "lockout_quest_" .. tostring(questID)
    local now = GetTime()
    if V.lastTryCountSourceKey == tryCountSourceKey and (now - V.lastTryCountSourceTime) < 15 then
        return
    end

    local drops = npcDropDB[npcID]
    local trackable = Fns.FilterDropsByDifficulty(drops, nil)
    if #trackable == 0 then return end

    local dropsToIncrement = {}
    for i = 1, #trackable do
        local d = trackable[i]
        if not Fns.ShouldSkipMissIncrementForDrop(d)
            and (d.repeatable or not Fns.IsCollectibleCollected(d)) then
            dropsToIncrement[#dropsToIncrement + 1] = d
        end
    end
    if #dropsToIncrement == 0 then return end

    if pendingLootSessionFinalize then return end
    if Fns.IsLootSessionPendingOrRecent(LOOT_SESSION_RECENT_TTL) then return end
    if Fns.WasLockoutLootTouchedRecently(npcID, 180) then return end

    lockoutAttempted[questID] = true
    V.lastTryCountSourceKey = tryCountSourceKey
    V.lastTryCountSourceTime = now
    Fns.TryCounterLootDebugDropLines(WarbandNexus, "LockoutQuest", dropsToIncrement, 1)
    Fns.ProcessMissedDrops(dropsToIncrement, drops.statisticIds, { attemptTimes = 1 })
end

function Fns.MarkLockoutLootTouched(npcID)
    if not npcID then return end
    lockoutLootTouchedNpc[npcID] = GetTime()
end

function Fns.WasLockoutLootTouchedRecently(npcID, ttlSec)
    if not npcID then return false end
    local t = lockoutLootTouchedNpc[npcID]
    if not t then return false end
    return (GetTime() - t) < (ttlSec or 120)
end

function Fns.TryCancelLockoutFallbackFromSourceGUIDs(sourceGUIDs)
    if not sourceGUIDs then return end
    for i = 1, #sourceGUIDs do
        local nid = Fns.GetNPCIDFromGUID(sourceGUIDs[i])
        if nid and lockoutQuestsDB[nid] then
            Fns.MarkLockoutLootTouched(nid)
            Fns.CancelLockoutQuestFallbackForNpc(nid)
        end
    end
end

function Fns.IsLootSessionPendingOrRecent(ttlSec)
    if pendingLootSessionFinalize then return true end
    if lootSession.opened then return true end
    local ttl = ttlSec or LOOT_SESSION_RECENT_TTL
    if lootReady.time > 0 and (GetTime() - lootReady.time) < ttl then return true end
    return false
end

--- All slot-based try counting defers DB writes until LOOT_CLOSED (LOOT_OPENED may fire early).
function Fns.ShouldDeferLootOutcomeUntilClose(lootRouteSource)
    return lootRouteSource == "opened"
end

function Fns.SessionTrackableContainsItemID(trackable, itemID)
    if not trackable or not itemID then return false end
    for i = 1, #trackable do
        local d = trackable[i]
        if d and d.itemID == itemID then return true, d end
        if d and d.questStarters then
            for qi = 1, #d.questStarters do
                if d.questStarters[qi].itemID == itemID then return true, d end
            end
        end
    end
    return false, nil
end

function Fns.TryMarkSessionObtainFromChatItem(itemID)
    if not itemID then return false end
    local pending = pendingLootSessionFinalize
    if not pending or not pending.trackable then return false end
    local matched, drop = Fns.SessionTrackableContainsItemID(pending.trackable, itemID)
    if not matched or not drop then return false end
    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
    if not tryKey then return false end
    Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
    return true
end

function Fns.CaptureTryCountBaselines(trackable)
    local baselines = {}
    for i = 1, #trackable do
        local drop = trackable[i]
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if tryKey then
            baselines[tcType .. "\0" .. tostring(tryKey)] = WarbandNexus:GetTryCount(tcType, tryKey) or 0
        end
    end
    return baselines
end

function Fns.RefreshLootSessionSlotLinks(numLoot, slotData)
    if not numLoot or numLoot == 0 or not slotData then return end
    for i = 1, numLoot do
        local entry = slotData[i]
        if entry and entry.hasItem and GetLootSlotLink then
            local link = GetLootSlotLink(i)
            if link and issecretvalue and issecretvalue(link) then link = nil end
            if link then entry.link = link end
        end
    end
end

function Fns.BuildNpcLootFoundMap(trackable, numLoot, slotData)
    Fns.RefreshLootSessionSlotLinks(numLoot, slotData)
    local found = Fns.ScanLootForItems(trackable, numLoot, slotData)
    for i = 1, #trackable do
        local drop = trackable[i]
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if tryKey and Fns.IsDropObtainedThisKill(tcType, tryKey, drop) then
            found[drop.itemID] = true
        end
    end
    return found
end

function Fns.StageDeferredLootSession(ctx)
    if not ctx or not ctx.trackable or #ctx.trackable == 0 then return end
    pendingLootSessionFinalize = {
        kind = ctx.kind or "npc",
        matchedNpcID = ctx.matchedNpcID,
        matchedEncounterID = ctx.matchedEncounterID,
        lastMatchedObjectID = ctx.lastMatchedObjectID,
        dedupGUID = ctx.dedupGUID,
        drops = ctx.drops,
        trackable = ctx.trackable,
        encounterDiffID = ctx.encounterDiffID,
        allSourceGUIDs = ctx.allSourceGUIDs,
        slotOutcomeSourceKey = ctx.slotOutcomeSourceKey,
        slotBossNpcID = ctx.slotBossNpcID,
        containerItemID = ctx.containerItemID,
        baselineTryCounts = Fns.CaptureTryCountBaselines(ctx.trackable),
        stagedAt = GetTime(),
    }
    RT.pendingLootSessionFinalize = pendingLootSessionFinalize
    if ctx.matchedNpcID then
        Fns.MarkLockoutLootTouched(ctx.matchedNpcID)
        Fns.CancelLockoutQuestFallbackForNpc(ctx.matchedNpcID)
    end
    if ctx.slotBossNpcID then
        Fns.MarkLockoutLootTouched(ctx.slotBossNpcID)
    end
end

function Fns.FinalizeDeferredLootSessionOutcome(self)
    local pending = pendingLootSessionFinalize
    if not pending then return end
    pendingLootSessionFinalize = nil
    RT.pendingLootSessionFinalize = nil

    local kind = pending.kind or "npc"
    local found = Fns.BuildNpcLootFoundMap(pending.trackable, lootSession.numLoot, lootSession.slotData)
    local baseline = pending.baselineTryCounts

    if kind == "fishing" then
        Fns.ApplyFishingLootOutcomes(self, {
            trackable = pending.trackable,
            found = found,
            baselineTryCounts = baseline,
        })
        return
    end
    if kind == "container" then
        Fns.ApplyContainerLootOutcomes(self, {
            trackable = pending.trackable,
            found = found,
            containerItemID = pending.containerItemID,
            baselineTryCounts = baseline,
        })
        return
    end
    if kind == "slot_boss" then
        Fns.ApplySlotBossLootOutcomes(self, {
            trackable = pending.trackable,
            found = found,
            drops = pending.drops,
            slotOutcomeSourceKey = pending.slotOutcomeSourceKey,
            slotBossNpcID = pending.slotBossNpcID,
            allSourceGUIDs = pending.allSourceGUIDs,
            baselineTryCounts = baseline,
        })
        return
    end

    local matchedNpcID = pending.matchedNpcID
    local isLockoutSkip = matchedNpcID and Fns.IsLockoutDuplicate(matchedNpcID)
    Fns.ApplyNpcLootOutcomes(self, {
        trackable = pending.trackable,
        found = found,
        drops = pending.drops,
        matchedNpcID = matchedNpcID,
        matchedEncounterID = pending.matchedEncounterID,
        lastMatchedObjectID = pending.lastMatchedObjectID,
        dedupGUID = pending.dedupGUID,
        allSourceGUIDs = pending.allSourceGUIDs,
        isLockoutSkip = isLockoutSkip,
        baselineTryCounts = baseline,
    })
end

function Fns.ApplyNpcLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local drops = opts.drops
    local matchedNpcID = opts.matchedNpcID
    local matchedEncounterID = opts.matchedEncounterID
    local lastMatchedObjectID = opts.lastMatchedObjectID
    local dedupGUID = opts.dedupGUID
    local allSourceGUIDs = opts.allSourceGUIDs or {}
    local isLockoutSkip = opts.isLockoutSkip
    local baselineTryCounts = opts.baselineTryCounts

    local function preResetForDrop(drop)
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if not tryKey then return 0 end
        if baselineTryCounts then
            local ck = tcType .. "\0" .. tostring(tryKey)
            local base = baselineTryCounts[ck]
            if base ~= nil then
                return Fns.AdjustPreResetForDelayedReseed(base, tcType, tryKey)
            end
        end
        local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
        return Fns.AdjustPreResetForDelayedReseed(currentCount, tcType, tryKey)
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey and not Fns.IsObtainOutcomeApplied(tcType, tryKey, drop) then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                if drop.type == "item" then
                    V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    V.lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" and preResetCount and preResetCount > 0 then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_OBTAINED_RESET", "Obtained %s! Try counter reset.", itemLink, preResetCount))
                if drop.type == "item" then
                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                    SendTryCounterCollectibleObtained(WarbandNexus, {
                        type = "item",
                        id = drop.itemID,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                        fromTryCounter = true,
                    }, drop.itemID)
                end
                Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
            end
        end
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and found[drop.itemID] then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey and not Fns.IsObtainOutcomeApplied(tcType, tryKey, drop) then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local currentCount = preResetForDrop(drop)
                local cacheKey = tcType .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = currentCount or 0
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_OBTAINED", "Obtained %s!", itemLink, currentCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = drop.type,
                    id = (drop.type == "item") and drop.itemID or tryKey,
                    name = itemName or drop.name or "Unknown",
                    icon = itemIcon,
                    preResetTryCount = currentCount,
                    fromTryCounter = true,
                }, drop.itemID)
                Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
            end
        end
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and drop.type ~= "item" and not found[drop.itemID] then
            local tryKey = Fns.GetTryCountKey(drop)
            if tryKey then
                local currentCount = preResetForDrop(drop)
                local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = currentCount
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
            end
        end
    end

    if isLockoutSkip then
        if Fns.ShouldAnnounceLockoutSkip(matchedNpcID) then
            local lockDedupKey = (matchedEncounterID and ("lockskip_enc_" .. tostring(matchedEncounterID)))
                or (matchedNpcID and ("lockskip_npc_" .. tostring(matchedNpcID)))
                or "lockskip_generic"
            local tLock = GetTime()
            if lockDedupKey ~= lastLockoutSkipChatKey or (tLock - lastLockoutSkipChatTime) >= SKIP_CHAT_DEDUP_SEC then
                lastLockoutSkipChatKey = lockDedupKey
                lastLockoutSkipChatTime = tLock
                Fns.TryChat("|cff9370DB[WN-Counter]|r |cff888888" .. ((ns.L and ns.L["TRYCOUNTER_LOCKOUT_SKIP"]) or "Skipped: daily/weekly lockout active for this NPC."))
            end
        end
        return
    end

    local dropsToIncrement = {}
    for i = 1, #trackable do
        local d = trackable[i]
        if not found[d.itemID] and not Fns.ShouldSkipMissIncrementForDrop(d) then
            dropsToIncrement[#dropsToIncrement + 1] = d
        end
    end

    local now = GetTime()
    local farmCorpseMult = 1
    do
        local statBacked = drops and Fns.NpcEntryHasStatisticIds(drops)
        if matchedNpcID and not matchedEncounterID and not lastMatchedObjectID and not statBacked then
            local tableMult = Fns.CountCorpsesSharingDropTable(allSourceGUIDs, drops)
            local npcMult = Fns.CountUniqueLootSourcesForNpcID(allSourceGUIDs, matchedNpcID)
            local tryItemSet = Fns.BuildItemIdSetFromDropList(dropsToIncrement)
            local candidateList = Fns.BuildNpcIdsEligibleForDropItemSet(tryItemSet)
            local itemMult = Fns.CountCorpsesForMissedDropItems(allSourceGUIDs, tryItemSet, candidateList)
            farmCorpseMult = math.max(1, tableMult, npcMult, itemMult)
        end
    end

    local tryCountSourceKey = Fns.BuildTryCountSourceKey(matchedEncounterID, matchedNpcID, lastMatchedObjectID, dedupGUID)
    local encounterDedupTtl = 15
    if tryCountSourceKey and type(tryCountSourceKey) == "string" and tryCountSourceKey:match("^encounter_")
        and V.lastTryCountSourceKey == tryCountSourceKey then
        encounterDedupTtl = ENCOUNTER_OBJECT_TTL
    end
    if #dropsToIncrement > 0 and tryCountSourceKey
        and V.lastTryCountSourceKey == tryCountSourceKey and (now - V.lastTryCountSourceTime) < encounterDedupTtl then
        local statBackedOnly = {}
        local statIds = drops and drops.statisticIds
        for i = 1, #dropsToIncrement do
            local drop = dropsToIncrement[i]
            if Fns.DropsHaveStatBackedReseed({ drop }, statIds) then
                statBackedOnly[#statBackedOnly + 1] = drop
            end
        end
        dropsToIncrement = statBackedOnly
    end

    local mergeFp = nil
    local openWorldFarm = matchedNpcID and not matchedEncounterID and not lastMatchedObjectID
    local statNoStats = not (drops and Fns.NpcEntryHasStatisticIds(drops))
    if openWorldFarm and statNoStats and #dropsToIncrement > 0 and #allSourceGUIDs > 0 then
        mergeFp = tostring(matchedNpcID) .. "\1" .. Fns.BuildSortedSourceFingerprint(allSourceGUIDs)
        local tMerge = mergedLootTryCountedAt[mergeFp]
        if tMerge and (now - tMerge) < MERGED_LOOT_TRY_DEDUP_TTL then
            dropsToIncrement = {}
            farmCorpseMult = 1
            mergeFp = nil
        end
    end

    local willIncrementMisses = #dropsToIncrement > 0

    V.lastTryCountSourceKey = tryCountSourceKey
    V.lastTryCountSourceTime = GetTime()
    if tryCountSourceKey then
        V.lastTryCountLootSourceGUID = (type(dedupGUID) == "string" and dedupGUID) or allSourceGUIDs[1]
    else
        V.lastTryCountLootSourceGUID = nil
    end

    local statIds = drops and drops.statisticIds or nil
    Fns.TryCounterLootDebugDropLines(self, "NPC", dropsToIncrement, farmCorpseMult)
    Fns.ProcessMissedDrops(dropsToIncrement, statIds, { attemptTimes = farmCorpseMult })
    if mergeFp and willIncrementMisses then
        mergedLootTryCountedAt[mergeFp] = GetTime()
    end
end

function Fns.ApplyFishingLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local baselineTryCounts = opts.baselineTryCounts

    local function preResetForDrop(drop)
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if not tryKey then return 0 end
        if baselineTryCounts then
            local ck = tcType .. "\0" .. tostring(tryKey)
            local base = baselineTryCounts[ck]
            if base ~= nil then return base end
        end
        return WarbandNexus:GetTryCount(tcType, tryKey) or 0
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if found[drop.itemID] and drop.repeatable then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                if drop.type == "item" then
                    V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    V.lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount or 0
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_CAUGHT_RESET", "Caught %s! Try counter reset.", itemLink, preResetCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType, id = tryKey, name = itemName or drop.name or "Unknown", icon = itemIcon,
                    preResetTryCount = preResetCount, fromTryCounter = true,
                }, drop.itemID)
            end
        elseif found[drop.itemID] and not drop.repeatable then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                local cacheKey = tcType .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = preResetCount or 0
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                V.lastTryCountSourceTime = GetTime()
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_CAUGHT", "Caught %s!", itemLink, preResetCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType, id = tryKey, name = itemName or drop.name or "Unknown", icon = itemIcon,
                    preResetTryCount = preResetCount, fromTryCounter = true,
                }, drop.itemID)
            end
        end
    end

    local missed = {}
    for i = 1, #trackable do
        local d = trackable[i]
        if not found[d.itemID] and not Fns.ShouldSkipMissIncrementForDrop(d) then
            missed[#missed + 1] = d
        end
    end
    Fns.TryCounterLootDebugDropLines(self, "Fishing", missed)
    if #missed > 0 then
        V.lastTryCountSourceKey = "fishing_open"
        V.lastTryCountSourceTime = GetTime()
        Fns.ProcessMissedDrops(missed, nil)
    end
end

function Fns.ApplyContainerLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local baselineTryCounts = opts.baselineTryCounts

    local function preResetForDrop(drop)
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if not tryKey then return 0 end
        if baselineTryCounts then
            local ck = tcType .. "\0" .. tostring(tryKey)
            local base = baselineTryCounts[ck]
            if base ~= nil then return base end
        end
        return WarbandNexus:GetTryCount(tcType, tryKey) or 0
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if found[drop.itemID] then
            if not drop.repeatable and drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                Fns.ResolveCollectibleID(drop)
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                if drop.type == "item" then
                    V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    V.lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount or 0
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                local chatKey = drop.repeatable and "TRYCOUNTER_CONTAINER_RESET" or "TRYCOUNTER_CONTAINER"
                local chatFallback = drop.repeatable and "Obtained %s from container! Try counter reset." or "Obtained %s from container!"
                Fns.TryChat(Fns.BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType,
                    id = (drop.type == "item") and drop.itemID or tryKey,
                    name = itemName or drop.name or "Unknown", icon = itemIcon,
                    preResetTryCount = preResetCount, fromTryCounter = true,
                }, drop.itemID)
            end
        end
    end

    local missed = {}
    for i = 1, #trackable do
        if not found[trackable[i].itemID] then missed[#missed + 1] = trackable[i] end
    end
    Fns.ProcessMissedDrops(missed)
end

function Fns.ApplySlotBossLootOutcomes(self, opts)
    if not opts or not opts.trackable or #opts.trackable == 0 then return end
    local trackable = opts.trackable
    local found = opts.found or {}
    local drops = opts.drops
    local slotOutcomeSourceKey = opts.slotOutcomeSourceKey
    local slotBossNpcID = opts.slotBossNpcID
    local allSourceGUIDs = opts.allSourceGUIDs or {}
    local baselineTryCounts = opts.baselineTryCounts
    local now = GetTime()

    local anyFound = false
    for ti = 1, #trackable do
        local d = trackable[ti]
        if d and found[d.itemID] then anyFound = true; break end
    end

    if anyFound then
        Fns.ClearEncounterRecentKillsForNpcId(slotBossNpcID)
        if baselineTryCounts then
            Fns.ApplyBossSlotOutcomeFoundHandlers(trackable, found, drops, baselineTryCounts)
        else
            Fns.ApplyBossSlotOutcomeFoundHandlers(trackable, found, drops)
        end
        V.lastTryCountSourceKey = slotOutcomeSourceKey
        V.lastTryCountSourceTime = now
        V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
        return
    end

    -- Miss path: personal-loot chest slots may have hasItem=true while links are nil/secret at
    -- LOOT_CLOSED (Midnight / post-cinematic Sylvanas chest). Readable links are not required.
    if not Fns.LootSlotsHaveReadableItemLink(lootSession.slotData, lootSession.numLoot)
        and not Fns.LootSlotsHaveItemsPresent(lootSession.slotData, lootSession.numLoot) then
        return
    end

    local missed = {}
    for mi = 1, #trackable do
        local d = trackable[mi]
        if d and not found[d.itemID] and not Fns.ShouldSkipMissIncrementForDrop(d) then
            missed[#missed + 1] = d
        end
    end
    if #missed == 0 then return end

    if slotOutcomeSourceKey and V.lastTryCountSourceKey == slotOutcomeSourceKey
        and (now - V.lastTryCountSourceTime) < 15 then
        V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
        return
    end

    Fns.ClearEncounterRecentKillsForNpcId(slotBossNpcID)
    Fns.TryCounterLootDebugDropLines(self, "SlotOutcome", missed, 1)
    Fns.ProcessMissedDrops(missed, drops and drops.statisticIds, {
        attemptTimes = 1,
        statReseedLootMissFallback = true,
    })
    V.lastTryCountSourceKey = slotOutcomeSourceKey
    V.lastTryCountSourceTime = now
    V.lastTryCountLootSourceGUID = allSourceGUIDs[1]
end

function Fns.ProcessKnownLockoutQuestCompletions()
    if not Fns.IsAutoTryCounterEnabled() then return end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end

    for npcID, questData in pairs(lockoutQuestsDB) do
        local questIDs = type(questData) == "table" and questData or { questData }
        for i = 1, #questIDs do
            local qid = questIDs[i]
            if not lockoutQuestSnapshot[qid] then
                local ok, nowComplete = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
                if ok and nowComplete then
                    lockoutQuestSnapshot[qid] = true
                    -- Defer so ground-corpse LOOT_OPENED runs first (same as other weekly rares).
                    -- Phase rares (Sthaarbs/Shartabb) flag the quest on kill but loot lands seconds later.
                    if not lockoutAttempted[qid] then
                        Fns.ScheduleLockoutQuestFallback(npcID, qid)
                    end
                end
            end
        end
    end
end

-- LOCKOUT QUEST AUTO-DISCOVERY
-- When an NPC in our drop DB has no lockout quest, detect the hidden
-- tracking quest that flipped by comparing pre-kill and post-kill quest
-- flags.  Approach: maintain a running snapshot of completed quest IDs
-- in the Midnight range; on QUEST_LOG_UPDATE, diff to find new
-- completions.  If a loot event for an unknown-lockout NPC happened
-- recently, associate the newly-completed quest with that NPC.
-- Persisted to db.global.discoveredLockoutQuests so it survives reload.

local DISCOVERY_QUEST_RANGES = {
    { 89560, 89590 },   -- Zul'Aman rares
    { 90790, 90810 },   -- Sundereth the Caller area + Zul'Aman treasures
    { 91040, 91340 },   -- Various zone rares (Eruundi, Tremora, etc.)
    { 91620, 91850 },   -- Harandar rares + misc
    { 92020, 92200 },   -- Harandar / Eversong rares + world bosses (Thorm'belan 92034, Cragpine 92123)
    { 92350, 92650 },   -- Eversong rares + world bosses (Lu'ashal 92560, Predaxas 92636)
    { 93440, 93980 },   -- Newer rares (Voidstorm, Duskburn, Dame Bloodshed, etc.)
    { 94440, 94480 },   -- Arcantina rares (Orivane, Many-Broken, Abysslick, Nullspiral, Blackcore, Steellock)
    { 95005, 95020 },   -- Isle of Quel'Danas rares (Tarhu, Dripping Shadow)
}

local discoverySnapshot = {}           -- [questID] = true for quest IDs completed at snapshot time
discoveryPendingNpcID = nil      -- NPC ID awaiting lockout quest discovery
local discoveryPendingTime = 0         -- GetTime() when pending was set
local DISCOVERY_PENDING_TTL = 8        -- seconds to wait for QUEST_LOG_UPDATE after loot

function Fns.GetClaimedQuestIDs()
    local claimed = {}
    for _, questData in pairs(lockoutQuestsDB) do
        local qids = type(questData) == "table" and questData or { questData }
        for i = 1, #qids do claimed[qids[i]] = true end
    end
    return claimed
end

function Fns.TakeDiscoverySnapshot()
    wipe(discoverySnapshot)
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return end
    for ri = 1, #DISCOVERY_QUEST_RANGES do
        local lo, hi = DISCOVERY_QUEST_RANGES[ri][1], DISCOVERY_QUEST_RANGES[ri][2]
        for qid = lo, hi do
            local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
            if ok and result then
                discoverySnapshot[qid] = true
            end
        end
    end
end

Fns.TryDiscoverLockoutQuest = function()
    if not discoveryPendingNpcID then return end
    if GetTime() - discoveryPendingTime > DISCOVERY_PENDING_TTL then
        discoveryPendingNpcID = nil
        Fns.TakeDiscoverySnapshot()
        return
    end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        discoveryPendingNpcID = nil
        return
    end

    local claimed = Fns.GetClaimedQuestIDs()
    local candidates = {}
    for ri = 1, #DISCOVERY_QUEST_RANGES do
        local lo, hi = DISCOVERY_QUEST_RANGES[ri][1], DISCOVERY_QUEST_RANGES[ri][2]
        for qid = lo, hi do
            if not discoverySnapshot[qid] and not claimed[qid] then
                local ok, result = pcall(C_QuestLog.IsQuestFlaggedCompleted, qid)
                if ok and result then
                    candidates[#candidates + 1] = qid
                end
            end
        end
    end

    if #candidates == 1 then
        local questID = candidates[1]
        local npcID = discoveryPendingNpcID

        lockoutQuestsDB[npcID] = questID
        lockoutAttempted[questID] = true

        if WarbandNexus.db and WarbandNexus.db.global then
            if not WarbandNexus.db.global.discoveredLockoutQuests then
                WarbandNexus.db.global.discoveredLockoutQuests = {}
            end
            WarbandNexus.db.global.discoveredLockoutQuests[npcID] = questID
        end

        if ns.DebugPrint then
            ns.DebugPrint(format("|cff00ff00[LockoutDiscovery]|r NPC %d → quest %d", npcID, questID))
        end
    elseif #candidates > 1 and ns.DebugPrint then
        ns.DebugPrint(format("|cffff9900[LockoutDiscovery]|r NPC %d: %d candidates, skipping (ambiguous)", discoveryPendingNpcID, #candidates))
    end

    discoveryPendingNpcID = nil
    Fns.TakeDiscoverySnapshot()
end

function Fns.MergeDiscoveredLockoutQuests()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    local disc = WarbandNexus.db.global.discoveredLockoutQuests
    if type(disc) ~= "table" then return end
    for npcID, questID in pairs(disc) do
        if not lockoutQuestsDB[npcID] then
            lockoutQuestsDB[npcID] = questID
        end
    end
end

-- EVENT HANDLERS (encounter): Modules/TryCounterService_Handlers.lua

-- INSTANCE ENTRY (Encounter Journal helpers kept for debug / TryCounterShowInstanceDrops if invoked manually)
-- Full boss-by-boss chat dump on zone-in was removed (spam). On entry: optional [WN-Drops] lines if the
-- instance has any Try Counter mount in DB (wrong difficulty shows red); else a one-line hint only when
-- at least one drop is trackable on the current difficulty — see TryCounterAnnounceCollectibleMountsOnInstanceEntry.

local function TryCounterAnnounceCollectibleMountsOnInstanceEntry(WN)
    if not WN or not WN.Print then return end
    local autoEnabled = Fns.IsAutoTryCounterEnabled()
    if autoEnabled and Fns.IsTryCounterChatHidden() then return end
    local inI, it = IsInInstance()
    if issecretvalue and inI and issecretvalue(inI) then return end
    if not inI then return end
    if issecretvalue and it and issecretvalue(it) then it = nil end
    if it ~= "party" and it ~= "raid" then return end

    Fns.TryCounterLoadEncounterJournal()
    if not Fns.TryCounterEJ_HasCoreAPIs() then return end
    local jid = Fns.TryCounterGetJournalInstanceID()
    if not jid or jid == 0 then return end

    local sid = tryCounterInstanceDiffCache.instanceID
    local did = tryCounterInstanceDiffCache.difficultyID
    local throttleKey = (sid and did) and (tostring(sid) .. ":" .. tostring(did)) or nil
    if throttleKey and tryCounterInstanceEntryAnnounced[throttleKey] then return end

    EJ_SelectInstance(jid)
    local effDiff = Fns.ResolveEffectiveEncounterDifficultyID(true, nil)
    local idx = 1
    local EJ_ENCOUNTER_INDEX_CAP = 500
    -- Midnight: encName and/or dungeonEncID may be secret in some contexts — never spin forever (see issecretvalue break).
    local hasAnyMount = false
    local hasTrackableOnDiff = false
    while idx <= EJ_ENCOUNTER_INDEX_CAP do
        local encName, dungeonEncID = Fns.TryCounterResolveDungeonEncounterFromEJIndex(idx, jid)
        if issecretvalue and issecretvalue(encName) then break end
        if encName == nil then break end
        local dexSecret = issecretvalue and issecretvalue(dungeonEncID)
        if not dexSecret and dungeonEncID then
            local npcIDs = encounterDB[dungeonEncID]
            if npcIDs then
                for ni = 1, #npcIDs do
                    local npcID = npcIDs[ni]
                    local npcDrops = npcDropDB[npcID]
                    if npcDrops then
                        for di = 1, #npcDrops do
                            local drop = npcDrops[di]
                            if type(drop) == "table" and Fns.ResolveTryCounterMountAnnounceDrop(drop) then
                                hasAnyMount = true
                            end
                        end
                        if not hasTrackableOnDiff then
                            local trackable = Fns.FilterDropsByDifficulty(npcDrops, effDiff)
                            for ti = 1, #trackable do
                                if Fns.ResolveTryCounterMountAnnounceDrop(trackable[ti]) then
                                    hasTrackableOnDiff = true
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        idx = idx + 1
    end

    if not autoEnabled and hasAnyMount then
        if throttleKey then tryCounterInstanceEntryAnnounced[throttleKey] = true end
        Fns.PrintTryCounterDisabledHint(WN)
        return
    end
    if not autoEnabled then return end

    local showDropLines = Fns.IsTryCounterInstanceEntryDropLinesEnabled() and hasAnyMount
    local showHintOnly = (not showDropLines) and hasTrackableOnDiff
    if showDropLines or showHintOnly then
        if throttleKey then tryCounterInstanceEntryAnnounced[throttleKey] = true end
        if showDropLines then
            -- Same format as manual TryCounterShowInstanceDrops: item link + (reqDiff) green/red/amber vs current instance.
            Fns.TryCounterShowInstanceDrops(jid, { maxLines = 18 })
        else
            local L = ns.L
            local msg = (L and L["TRYCOUNTER_INSTANCE_ENTRY_HINT"])
                or "Collectible mount(s) are tracked in this instance. Type |cffffffff/wn check|r for bosses and difficulty."
            WN:Print("|cff00ccffWarband Nexus:|r " .. msg)
        end
    end
end

function Fns.TryCounterLoadEncounterJournal()
    if InCombatLockdown() then return end
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Blizzard_EncounterJournal")
    end
end

function Fns.TryCounterEJ_HasCoreAPIs()
    return EJ_SelectInstance and EJ_GetEncounterInfoByIndex
        and (EJ_GetCurrentInstance or EJ_GetInstanceForMap)
end

function Fns.TryCounterResolveDungeonEncounterFromEJIndex(encIndex, journalInstanceID)
    local encName, _, journalEncID, _, _, _, dungeonEncID
    local okEJ, a, b, c, d, e, f, g = pcall(function()
        if journalInstanceID and type(journalInstanceID) == "number" and journalInstanceID > 0 then
            return EJ_GetEncounterInfoByIndex(encIndex, journalInstanceID)
        end
        return EJ_GetEncounterInfoByIndex(encIndex)
    end)
    if okEJ and a then
        encName, _, journalEncID, _, _, _, dungeonEncID = a, b, c, d, e, f, g
    end
    if issecretvalue and journalEncID and issecretvalue(journalEncID) then journalEncID = nil end
    if issecretvalue and dungeonEncID and issecretvalue(dungeonEncID) then dungeonEncID = nil end
    -- Fallback only when ByIndex omitted dungeonEncounterID; pcall must use 6×_ so dex = 7th return (not journalInstanceID).
    if (not dungeonEncID or type(dungeonEncID) ~= "number" or dungeonEncID <= 0)
        and EJ_GetEncounterInfo and journalEncID and type(journalEncID) == "number" and journalEncID > 0 then
        -- Returns: name, desc, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID, instanceID
        local okInfo, _, _, _, _, _, _, dex = pcall(EJ_GetEncounterInfo, journalEncID)
        if okInfo and dex and type(dex) == "number" and dex > 0 then
            if not (issecretvalue and issecretvalue(dex)) then
                dungeonEncID = dex
            end
        end
    end
    return encName, dungeonEncID
end

function Fns.ResolveTryCounterMountAnnounceDrop(drop)
    if not drop or not drop.type then return nil end
    if drop.type == "mount" then return drop end
    if drop.type == "pet" or drop.type == "toy" then return nil end
    if drop.type == "item" then
        local r = drop.tryCountReflectsTo
        if r and r.type == "mount" then return r end
        local qs = drop.questStarters
        if type(qs) == "table" then
            for i = 1, #qs do
                local q = qs[i]
                if q and q.type == "mount" then return q end
            end
        end
        local yl = drop.yields
        if type(yl) == "table" then
            for i = 1, #yl do
                local y = yl[i]
                if y and y.type == "mount" then return y end
            end
        end
    end
    return nil
end

function Fns.TryCounterFindJournalInstanceIDByTemplateInstanceID(templateInstID)
    if not templateInstID or type(templateInstID) ~= "number" or templateInstID <= 0 then return nil end
    if issecretvalue and issecretvalue(templateInstID) then return nil end
    local cached = tryCounterJournalIDByTemplateInstID[templateInstID]
    if cached == false then return nil end
    if type(cached) == "number" and cached > 0 then return cached end
    if not EJ_GetInstanceInfo then return nil end
    Fns.TryCounterLoadEncounterJournal()
    local sawNamedInstance = false
    for jid = 1, JOURNAL_INSTANCE_TEMPLATE_SCAN_MAX do
        local ok, ejName, _, _, _, _, _, _, _, _, mapTpl = pcall(EJ_GetInstanceInfo, jid)
        if ok and ejName and not (issecretvalue and issecretvalue(ejName)) and type(ejName) == "string" and ejName ~= "" then
            sawNamedInstance = true
        end
        if ok and mapTpl and not (issecretvalue and issecretvalue(mapTpl)) and type(mapTpl) == "number" and mapTpl == templateInstID then
            tryCounterJournalIDByTemplateInstID[templateInstID] = jid
            return jid
        end
    end
    if sawNamedInstance then
        tryCounterJournalIDByTemplateInstID[templateInstID] = false
    end
    return nil
end

function Fns.TryCounterGetJournalInstanceID()
    local jid

    if EJ_GetInstanceForMap and C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID and not (issecretvalue and issecretvalue(mapID)) then
            jid = EJ_GetInstanceForMap(mapID)
        end
    end
    if jid and jid ~= 0 then return jid end

    local inInst = IsInInstance()
    if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
    if inInst and EJ_GetInstanceInfo then
        local _, _, _, _, _, _, _, templateInstID = GetInstanceInfo()
        if templateInstID and not (issecretvalue and issecretvalue(templateInstID)) and type(templateInstID) == "number" and templateInstID > 0 then
            jid = Fns.TryCounterFindJournalInstanceIDByTemplateInstanceID(templateInstID)
            if jid and jid ~= 0 then return jid end
        end
        -- If UiMap was nil but GetSafeMapID still has a floor id, only accept it when EJ template matches GetInstanceInfo (avoids SW cache).
        if EJ_GetInstanceForMap and type(Fns.GetSafeMapID) == "function" then
            local safeUm = Fns.GetSafeMapID()
            if safeUm and not (issecretvalue and issecretvalue(safeUm)) then
                local j2 = EJ_GetInstanceForMap(safeUm)
                if j2 and j2 ~= 0 and templateInstID and type(templateInstID) == "number" and templateInstID > 0 then
                    local okJ, _, _, _, _, _, _, _, _, _, ejTpl = pcall(EJ_GetInstanceInfo, j2)
                    if okJ and ejTpl and type(ejTpl) == "number" and ejTpl == templateInstID
                        and not (issecretvalue and issecretvalue(ejTpl)) then
                        return j2
                    end
                end
            end
        end
    end

    if EJ_GetCurrentInstance then
        jid = EJ_GetCurrentInstance()
        if jid and jid ~= 0 then return jid end
    end

    if jid == 0 then jid = nil end
    return jid
end

---PLAYER_ENTERING_WORLD handler (instance difficulty cache, fishing reset, statistics sync)
function WarbandNexus:OnTryCounterInstanceEntry(event, isInitialLogin, isReloadingUi)
    -- Statistics + Rarity: re-sync when character changes or UI reload (not every zone hop).
    if tryCounterReady then
        local k = StatisticSnapshotStorageKey()
        if k then
            if k ~= lastSyncScheduleCharKey or isReloadingUi then
                lastSyncScheduleCharKey = k
                Fns.SchedulePerCharacterStatisticsAndRaritySync()
            end
        end
    end

    if not Fns.IsAutoTryCounterEnabled() then return end

    -- Refresh safe map cache on zone transitions (login, reload, instance entry/exit)
    Fns.GetSafeMapID()

    local inInstance, instanceType = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if issecretvalue and instanceType and issecretvalue(instanceType) then instanceType = nil end
    if not inInstance then
        tryCounterInstanceDiffCache.instanceID = nil
        tryCounterInstanceDiffCache.difficultyID = nil
        -- ENCOUNTER_START cache is instance-scoped — clear on exit.
        if currentEncounterCache._graceTimer then currentEncounterCache._graceTimer:Cancel() end
        currentEncounterCache.encounterID = nil
        currentEncounterCache.encounterName = nil
        currentEncounterCache.difficultyID = nil
        currentEncounterCache.groupSize = nil
        currentEncounterCache.startTime = 0
        currentEncounterCache.instanceID = nil
        currentEncounterCache._graceTimer = nil
        for guid, data in pairs(recentKills) do
            if data.isEncounter then
                recentKills[guid] = nil
                -- Purge cached GUID parses for encounter GUIDs no longer relevant.
                guidNpcIDCache[guid] = nil
                guidObjectIDCache[guid] = nil
            end
        end
        wipe(recentKillByNpcID)
        return
    end

    -- Try counter: snapshot instance difficulty at entry (stable vs wrong ENCOUNTER_END args).
    tryCounterInstanceDiffCache.instanceID = nil
    tryCounterInstanceDiffCache.difficultyID = nil
    if instanceType == "party" or instanceType == "raid" then
        local _, _, diffID, _, _, _, _, instanceID = GetInstanceInfo()
        local sid = instanceID
        if sid and issecretvalue and issecretvalue(sid) then sid = nil end
        local gi = diffID
        if gi and issecretvalue and issecretvalue(gi) then gi = nil end
        local resolved = Fns.ResolveLiveInstanceDifficultyID(instanceType, gi)
        if sid then
            tryCounterInstanceDiffCache.instanceID = sid
            tryCounterInstanceDiffCache.difficultyID = resolved
                or (type(gi) == "number" and gi > 0 and gi)
                or nil
        end
    end

    if Fns.IsTryCounterLootDebugEnabled(self) then
        self:TryCounterDebugInstanceProbe()
    end

    if instanceType == "party" or instanceType == "raid" then
        C_Timer.After(2.5, function()
            TryCounterAnnounceCollectibleMountsOnInstanceEntry(WarbandNexus)
        end)
    end

    -- Clear fishing context on instance entry (prevents false fishing counts in Delves)
    fishingCtx.active = false
    fishingCtx.castTime = 0
    if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() fishingCtx.resetTimer = nil end
end

---When debugTryCounterLoot is on: immediate GetInstanceInfo + cache snapshot; deferred EJ walk vs encounterDB/npcDropDB with FilterDropsByDifficulty(same as loot path).
function WarbandNexus:TryCounterDebugInstanceProbe()
    if not Fns.IsTryCounterLootDebugEnabled(self) then return end
    local inInst = IsInInstance()
    if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
    if not inInst then return end

    local name, instType = GetInstanceInfo()
    if name and issecretvalue and issecretvalue(name) then name = nil end
    if instType and issecretvalue and issecretvalue(instType) then instType = nil end

    local encDiff = Fns.ResolveEffectiveEncounterDifficultyID(true, nil)
    local diffLabel = (encDiff and Fns.ResolveDifficultyLabel(encDiff)) or "?"
    local enterFmt = (ns.L and ns.L["TRYCOUNTER_PROBE_ENTER"])
        or "Entered: %s — difficulty: %s"
    Fns.TryCounterLootDebug(self, "flow", enterFmt,
        tostring(name or "?"),
        tostring(diffLabel))

    if instType ~= "party" and instType ~= "raid" then
        Fns.TryCounterLootDebug(self, "skip", "EJ/DB boss probe skipped (need party or raid instance type)")
        return
    end

    local WN = self
    C_Timer.After(0.75, function()
        if not WN or not Fns.IsTryCounterLootDebugEnabled(WN) then return end
        local inI = IsInInstance()
        if issecretvalue and inI and issecretvalue(inI) then inI = nil end
        if not inI then return end

        Fns.TryCounterLoadEncounterJournal()
        if not Fns.TryCounterEJ_HasCoreAPIs() then
            Fns.TryCounterLootDebug(WN, "miss",
                "DB probe: EJ APIs missing (EJ_SelectInstance=%s EJ_GetEncounterInfoByIndex=%s EJ_GetCurrentInstance=%s EJ_GetInstanceForMap=%s) — need Blizzard_EncounterJournal",
                tostring(not not EJ_SelectInstance),
                tostring(not not EJ_GetEncounterInfoByIndex),
                tostring(not not EJ_GetCurrentInstance),
                tostring(not not EJ_GetInstanceForMap))
            return
        end

        local jid = Fns.TryCounterGetJournalInstanceID()
        if not jid or jid == 0 then
            local missFmt = (ns.L and ns.L["TRYCOUNTER_PROBE_JOURNAL_MISS"])
                or "Could not resolve encounter journal for this instance."
            Fns.TryCounterLootDebug(WN, "miss", "%s", missFmt)
            return
        end

        EJ_SelectInstance(jid)
        local effDiff = Fns.ResolveEffectiveEncounterDifficultyID(true, nil)
        local effLabel = (effDiff and Fns.ResolveDifficultyLabel(effDiff)) or "?"
        local hdrFmt = (ns.L and ns.L["TRYCOUNTER_PROBE_DB_HEADER"])
            or "Mount sources (Try Counter DB) — your difficulty: %s"
        Fns.TryCounterLootDebug(WN, "flow", hdrFmt, tostring(effLabel or "?"))

        local idx = 1
        local EJ_ENCOUNTER_INDEX_CAP = 500
        local hadDbBoss = false
        while idx <= EJ_ENCOUNTER_INDEX_CAP do
            local encName, dungeonEncID = Fns.TryCounterResolveDungeonEncounterFromEJIndex(idx, jid)
            if issecretvalue and issecretvalue(encName) then break end
            if encName == nil then break end
            local dexSecret = issecretvalue and issecretvalue(dungeonEncID)
            if not dexSecret and dungeonEncID then
                local npcIDs = encounterDB[dungeonEncID]
                if npcIDs then
                    hadDbBoss = true
                    local printedMountLine = false
                    for ni = 1, #npcIDs do
                        local npcID = npcIDs[ni]
                        local npcDrops = npcDropDB[npcID]
                        if npcDrops then
                            local npcDiff = npcDrops.dropDifficulty
                            for di = 1, #npcDrops do
                                local drop = npcDrops[di]
                                if type(drop) == "table" and drop.type then
                                    local ann = Fns.ResolveTryCounterMountAnnounceDrop(drop)
                                    if ann and ann.itemID then
                                        printedMountLine = true
                                        Fns.TryCounterDebugEmitMountProbeLine(WN, encName, ann, drop, npcDiff, effDiff)
                                    end
                                end
                            end
                        end
                    end
                    if not printedMountLine then
                        local noFmt = (ns.L and ns.L["TRYCOUNTER_PROBE_ENC_NO_MOUNTS"])
                            or "%s: no mount entries in database"
                        Fns.TryCounterLootDebug(WN, "skip", noFmt, tostring(encName))
                    end
                end
            end
            idx = idx + 1
        end

        if not hadDbBoss then
            local nomapFmt = (ns.L and ns.L["TRYCOUNTER_PROBE_NO_MAPPED_BOSSES"])
                or "No bosses in this instance map to Try Counter data."
            Fns.TryCounterLootDebug(WN, "miss", "%s", nomapFmt)
        end
    end)
end

Fns.TryCounterShowInstanceDrops = function(journalInstanceID, opts)
    local WN = WarbandNexus
    if not WN or not WN.Print then return end
    opts = opts or {}
    local maxLines = opts.maxLines
    if type(maxLines) ~= "number" or maxLines < 1 then maxLines = nil end
    EJ_SelectInstance(journalInstanceID)

    -- Iterate all encounters in this instance and cross-reference with our encounterDB
        local dropsToShow = {} -- { { bossName, drops = { {type, itemID, name}, ... } }, ... }
        local idx = 1
        local EJ_ENCOUNTER_INDEX_CAP = 500
        while idx <= EJ_ENCOUNTER_INDEX_CAP do
            local encName, dungeonEncID = Fns.TryCounterResolveDungeonEncounterFromEJIndex(idx, journalInstanceID)
            if issecretvalue and issecretvalue(encName) then break end
            if encName == nil then break end
            local dexSecret = issecretvalue and issecretvalue(dungeonEncID)
            if not dexSecret then
                -- Our encounterDB is keyed by DungeonEncounterID (from ENCOUNTER_END event)
                local npcIDs = dungeonEncID and encounterDB[dungeonEncID]
                if npcIDs then
                    local encounterDrops = {}
                    local seenItems = {}
                    local dropDiffMap = {}
                    for i = 1, #npcIDs do
                        local npcID = npcIDs[i]
                        local npcDrops = npcDropDB[npcID]
                        if npcDrops then
                            local npcDiff = npcDrops.dropDifficulty
                            for j = 1, #npcDrops do
                                local drop = npcDrops[j]
                                local ann = Fns.ResolveTryCounterMountAnnounceDrop(drop)
                                if ann and ann.itemID then
                                    local iid = ann.itemID
                                    if not seenItems[iid] then
                                        seenItems[iid] = true
                                        encounterDrops[#encounterDrops + 1] = ann
                                        local reqDiff = drop.dropDifficulty or npcDiff
                                        if reqDiff and reqDiff ~= "All Difficulties" then
                                            dropDiffMap[iid] = reqDiff
                                        end
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
        for i = 1, #dropsToShow do
            local entry = dropsToShow[i]
            for j = 1, #entry.drops do
                local drop = entry.drops[j]
                if C_Item and C_Item.RequestLoadItemDataByID then
                    pcall(C_Item.RequestLoadItemDataByID, drop.itemID)
                end
            end
        end

        -- Small extra delay for item data to cache, then print
        C_Timer.After(1, function()
            if not WN then return end

            local encDiff = Fns.ResolveEffectiveEncounterDifficultyID(true, nil)

            local Ltc = ns.L
            local printed = 0
            local omitted = 0

            for i = 1, #dropsToShow do
                local entry = dropsToShow[i]
                for j = 1, #entry.drops do
                    local drop = entry.drops[j]
                    if maxLines and printed >= maxLines then
                        omitted = omitted + 1
                    else
                    -- Get item hyperlink (quality-colored, bracketed)
                    local itemLink = Fns.GetDropItemLink(drop)

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
                        -- Show try count (use reflected type/key for item->mount so mount count shows)
                        local tryCount = 0
                        if WN.GetTryCount then
                            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                            tryCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
                            if tryCount == 0 and tryKey ~= drop.itemID then
                                tryCount = WN:GetTryCount(drop.type, drop.itemID) or 0
                            end
                        end
                        local attSuffix = (ns.L and ns.L["TRYCOUNTER_ATTEMPTS_SUFFIX"]) or " attempts"
                        if tryCount > 0 then
                            status = "|cffffff00(" .. tryCount .. attSuffix .. ")|r"
                        else
                            status = "|cff888888(0" .. attSuffix .. ")|r"
                        end
                    end

                    -- Third segment: (req) colored green/red/amber; gray em dash when DB has no difficulty gate.
                    local diffSegment
                    local reqDiff = entry.diffMap and entry.diffMap[drop.itemID]
                    if reqDiff then
                        if encDiff and not (issecretvalue and issecretvalue(encDiff)) then
                            local color = Fns.DoesDifficultyMatch(encDiff, reqDiff) and "|cff00ff00" or "|cffff6666"
                            diffSegment = "(" .. color .. reqDiff .. "|r)"
                        else
                            diffSegment = "(|cffffaa00" .. reqDiff .. "|r)"
                        end
                    else
                        diffSegment = "|cff888888—|r"
                    end

                        Fns.TryChat("|cff9370DB[WN-Drops]|r " .. itemLink .. " - " .. diffSegment .. " - " .. status)
                        printed = printed + 1
                    end
                end
            end

            if omitted > 0 then
                local moreFmt = (Ltc and Ltc["TRYCOUNTER_INSTANCE_DROPS_TRUNCATED"])
                    or "… |cffffccff%d|r more — |cffffffff/wn check|r a boss (target or mouseover)."
                Fns.TryChat("|cff9370DB[WN-Drops]|r " .. format(moreFmt, omitted))
            end
        end)
end

---Begin fishing context when a known Fishing spell starts (shared by SENT + CHANNEL_START).
---@param spellID number|nil
function WarbandNexus:TryCounterBeginFishingContext(spellID)
    if spellID then
        if issecretvalue and issecretvalue(spellID) then return end
        if not FISHING_SPELLS[spellID] then return end
    end
    fishingCtx.active = true
    fishingCtx.castTime = GetTime()
    -- Safety: if the bite never completes and LOOT_CLOSED never fires, clear context so chests/mobs
    -- are not misclassified. Match FISHING_CAST_CONTEXT_TTL so long channels still count.
    if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() end
    fishingCtx.resetTimer = C_Timer.NewTimer(FISHING_CAST_CONTEXT_TTL, function()
        fishingCtx.active = false
        fishingCtx.castTime = 0
        fishingCtx.resetTimer = nil
    end)
end

--- One-shot GetSpellInfo probe for unknown player casts; caches confirmed non-fishing ids.
local function ResolveTryCounterFishingSpell(spellID)
    if not spellID then return false end
    if FISHING_SPELLS[spellID] then return true end
    if probedNonFishingSpells[spellID] then return false end
    if not C_Spell or not C_Spell.GetSpellInfo then
        return false
    end
    local ok, spellInfo = pcall(C_Spell.GetSpellInfo, spellID)
    if not ok or not spellInfo then
        probedNonFishingSpells[spellID] = true
        return false
    end
    local iconID = spellInfo.iconID
    if iconID and not (issecretvalue and issecretvalue(iconID)) and iconID == 136245 then
        FISHING_SPELLS[spellID] = true
        return true
    end
    probedNonFishingSpells[spellID] = true
    return false
end

---UNIT_SPELLCAST_SENT handler (detect fishing casts)
function WarbandNexus:OnTryCounterSpellcastSent(event, unit, target, castGUID, spellID)
    if unit ~= "player" then return end
    if not Fns.IsTryCounterModuleEnabled() then return end
    -- Midnight 12.0: target/spellID can be secret values during instanced combat
    if issecretvalue and target and issecretvalue(target) then target = nil end
    if issecretvalue and spellID and issecretvalue(spellID) then
        -- We cannot read the spellID. If it's fishing, we might be able to read the channel texture.
        -- UNIT_SPELLCAST_SENT fires slightly before the channel starts, so we might not have it yet.
        -- But we can rely on UNIT_SPELLCAST_CHANNEL_START to catch it.
        return
    end
    if target then
        lastGatherCastName = target
        lastGatherCastTime = GetTime()
    end

    -- Overflowing Dumpster and other objectDropDB nodes: target is often nil on UNIT_SPELLCAST_SENT;
    -- mouseover/target GUID is reliable for attributing currency-only opens (no LOOT_OPENED).
    do
        local goGUID = Fns.SafeGetMouseoverGUID() or Fns.SafeGetTargetGUID()
        local oid = goGUID and Fns.GetObjectIDFromGUID(goGUID)
        if oid and objectDropDB[oid] then
            V.lastTrackedObjectInteractID = oid
            V.lastTrackedObjectInteractGUID = goGUID
            V.lastTrackedObjectInteractTime = GetTime()
        end
    end

    if spellID and PICKPOCKET_SPELLS[spellID] then
        V.isPickpocketing = true
        return
    end
    if spellID and PROFESSION_LOOT_SPELLS[spellID] then
        V.isProfessionLooting = true
        return
    end

    if ResolveTryCounterFishingSpell(spellID) then
        self:TryCounterBeginFishingContext(spellID)
    end
end

---UNIT_SPELLCAST_CHANNEL_START — some fishing variants channel without a separate SENT we map.
---Args: unitTarget, castGUID, spellID
function WarbandNexus:OnTryCounterSpellcastChannelStart(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if not Fns.IsTryCounterModuleEnabled() then return end

    local isFishing = false
    local validSpellID = spellID

    if issecretvalue and spellID and issecretvalue(spellID) then
        validSpellID = nil
        -- Secret value during instanced combat. We can't read spellID.
        -- Try to detect via UnitChannelInfo texture.
        if UnitChannelInfo then
            local _, _, texture = UnitChannelInfo("player")
            if texture and not (issecretvalue and issecretvalue(texture)) and texture == 136245 then
                isFishing = true
            end
        end
        if not isFishing then return end
    else
        isFishing = ResolveTryCounterFishingSpell(spellID)
    end

    if isFishing then
        self:TryCounterBeginFishingContext(validSpellID)
    end
end

---UNIT_SPELLCAST_INTERRUPTED / UNIT_SPELLCAST_FAILED_QUIET handler.
---Clears fishing context immediately when the initial cast fails (player moved, interrupted).
---Without this, fishingCtx.active stays true for up to 20s (safety timer), during which
---unrelated loot events (chests, untracked mobs) could be misclassified as fishing.
---Args: (unit, castGUID, spellID) — note: no target param unlike UNIT_SPELLCAST_SENT.
---@param event string
---@param unit string
---@param castGUID string
---@param spellID number
function WarbandNexus:OnTryCounterSpellcastFailed(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    if issecretvalue and spellID and issecretvalue(spellID) then return end
    if not FISHING_SPELLS[spellID] then return end
    
    -- Clicking the bobber interrupts the fishing channel.
    -- If we clear the context instantly, LOOT_READY fires 0.1s later with NO fishing context.
    -- We delay the clearing by 1.5s to ensure the loot window can capture the context.
    local captureTime = fishingCtx.castTime
    C_Timer.After(1.5, function()
        if fishingCtx.active and fishingCtx.castTime == captureTime and not fishingCtx.lootWasFishing then
            fishingCtx.active = false
            fishingCtx.castTime = 0
            if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() fishingCtx.resetTimer = nil end
        end
    end)
end

-- SAFE GUID HELPERS (must be defined before event handlers)

Fns.SafeGetUnitGUID = function(unit)
    if not unit then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not guid then return nil end
    if type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    return guid
end

Fns.SafeGetTargetGUID = function()
    return Fns.SafeGetUnitGUID("target")
end

Fns.SafeGetMouseoverGUID = function()
    return Fns.SafeGetUnitGUID("mouseover")
end

Fns.SafeGuardGUID = function(rawGUID)
    if not rawGUID then return nil end
    if type(rawGUID) ~= "string" then return nil end
    if issecretvalue and issecretvalue(rawGUID) then return nil end
    return rawGUID
end

function Fns.SafeIsFishingLoot()
    if not IsFishingLoot then return false end
    local ok, v = pcall(IsFishingLoot)
    if not ok or v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return not not v
end

function Fns.IsFishingSourceCompatible(sourceGUIDs)
    if not sourceGUIDs or #sourceGUIDs == 0 then return true end
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if type(srcGUID) == "string" and not (issecretvalue and issecretvalue(srcGUID)) then
            local typeStr = srcGUID:match("^(%a+)")
            local npcID = Fns.GetNPCIDFromGUID(srcGUID)
            if npcID and npcDropDB[npcID] then return false end
            local objectID = Fns.GetObjectIDFromGUID(srcGUID)
            if objectID and objectDropDB[objectID] then return false end
        end
    end
    return true
end

-- LOOT / CHAT_MSG_LOOT handlers: Modules/TryCounterService_Handlers.lua

---CHAT_MSG_CURRENCY / CHAT_MSG_MONEY fallback for tracked world objects (Overflowing Dumpster).
---When loot is currency-only, LOOT_OPENED may not fire; attribute a miss once per interact.
function Fns.TryProcessTrackedObjectCurrencyFallback(self)
    if not self or not Fns.IsAutoTryCounterEnabled() then return end
    if RT.pendingLootSessionFinalize or RT.lootSession.opened then return end

    local now = GetTime()
    local objectID, sourceGUID = Fns.GetTrackedObjectIDFromSourceGUIDs(RT.lootReady.sourceGUIDs)
    if not objectID and V.lastTrackedObjectInteractID
        and (now - (V.lastTrackedObjectInteractTime or 0)) < 12 then
        objectID = V.lastTrackedObjectInteractID
        sourceGUID = V.lastTrackedObjectInteractGUID
    end
    if not objectID then return end

    local dedupKey = Fns.BuildTryCountSourceKey(nil, nil, objectID, sourceGUID)
    if dedupKey and V.lastTryCountSourceKey == dedupKey
        and (now - V.lastTryCountSourceTime) < RT.CHAT_LOOT_DEBOUNCE then
        return
    end

    local drops = objectDropDB[objectID]
    if not drops then return end
    local trackable = {}
    for i = 1, #drops do
        local drop = drops[i]
        if drop and (drop.repeatable or not Fns.IsCollectibleCollected(drop)) then
            trackable[#trackable + 1] = drop
        end
    end
    if #trackable == 0 then return end

    local allObtained = true
    for i = 1, #trackable do
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(trackable[i])
        if not tryKey or not Fns.IsObtainOutcomeApplied(tcType, tryKey, trackable[i]) then
            allObtained = false
            break
        end
    end
    if allObtained then return end

    Fns.ApplyNpcLootOutcomes(self, {
        trackable = trackable,
        found = {},
        lastMatchedObjectID = objectID,
        dedupGUID = sourceGUID,
        baselineTryCounts = Fns.CaptureTryCountBaselines(trackable),
    })
end

---CHAT_MSG_CURRENCY / CHAT_MSG_MONEY fallback logic.
---In WoW, when gathering objects (like Overflowing Dumpster) that ONLY drop currency/money,
---LOOT_OPENED may not fire or closes instantly. This attributes currency to:
--- Reserved for future try-count attribution from currency (e.g. zone objects). Currently no-op.
---@param event string
---@param message string
function WarbandNexus:OnTryCounterChatMsgCurrency(event, message)
    if not Fns.IsAutoTryCounterEnabled() then return end
    Fns.TryProcessTrackedObjectCurrencyFallback(self)
end

---ITEM_LOCK_CHANGED handler (detect container item usage for try count tracking)
---When a container item from our DB changes lock state, record its itemID so
---ProcessContainerLoot() knows which container was opened.
---@param event string
---@param bagID number Bag index (0-4 for bags, -1 for bank, etc.)
---@param slotID number|nil Slot index within the bag. nil = equipment slot change.
function WarbandNexus:OnTryCounterItemLockChanged(event, bagID, slotID)
    if not bagID or not slotID then return end
    if issecretvalue and (issecretvalue(bagID) or issecretvalue(slotID)) then return end
    if bagID < 0 or bagID > 4 then return end
    if not C_Container or not C_Container.GetContainerItemID then return end

    local itemID = C_Container.GetContainerItemID(bagID, slotID)
    if not itemID then return end
    if issecretvalue and issecretvalue(itemID) then return end
    if not containerDropDB[itemID] then return end

    V.lastContainerItemID = itemID
    V.lastContainerItemTime = GetTime()
end

Fns.GetSafeMapID = function()
    local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = (rawMapID and not (issecretvalue and issecretvalue(rawMapID))) and rawMapID or nil
    if mapID then
        lastSafeMapID = mapID
    else
        mapID = lastSafeMapID
    end
    return mapID
end

function Fns.CollectFishingDropsForZone()
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if inInstance then return {}, true end
    local mapID = Fns.GetSafeMapID()
    local drops = {}
    local seen = {}  -- dedup: same drop registered at child + parent map would double-count
    -- Do not auto-merge fishingDropDB[0] (global pool) into every map.
    -- Global entries (e.g. Sea Turtle) would make every zone look like a fishing
    -- try-counter zone and cause wrong attribution in Midnight maps.
    local currentMapID = mapID
    local depthGuard = 0
    while currentMapID and currentMapID > 0 do
        depthGuard = depthGuard + 1
        if depthGuard > 20 then break end  -- WoW map hierarchy is never deeper than ~5 levels
        if fishingDropDB[currentMapID] then
            local mapDrops = fishingDropDB[currentMapID]
            for i = 1, #mapDrops do
                local d = mapDrops[i]
                if d and d.itemID then
                    local key = (d.type or "item") .. "\0" .. tostring(d.itemID)
                    if not seen[key] then
                        seen[key] = true
                        drops[#drops + 1] = d
                    end
                end
            end
        end
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(currentMapID)
        local nextID = mapInfo and mapInfo.parentMapID
        currentMapID = (nextID and not (issecretvalue and issecretvalue(nextID))) and nextID or nil
    end
    return drops, false
end

Fns.GetFishingTrackableForCurrentZone = function()
    local drops, inInstance = Fns.CollectFishingDropsForZone()
    if inInstance then return {} end
    local trackable = {}
    for i = 1, #drops do
        local d = drops[i]
        if d.repeatable or not Fns.IsCollectibleCollected(d) then trackable[#trackable + 1] = d end
    end
    return trackable
end

Fns.GetFishingDropItemIDsForCurrentZone = function()
    local drops, inInstance = Fns.CollectFishingDropsForZone()
    if inInstance or #drops == 0 then return nil end
    local set = {}
    for i = 1, #drops do
        local id = drops[i] and drops[i].itemID
        if id then set[id] = true end
    end
    return set
end

Fns.IsInTrackableFishingZone = function()
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if inInstance then return false end
    local mapID = Fns.GetSafeMapID()
    if not mapID then return false end
    local current = mapID
    local depthGuard = 0
    while current and current > 0 do
        depthGuard = depthGuard + 1
        if depthGuard > 20 then break end  -- WoW map hierarchy is never deeper than ~5 levels
        if fishingDropDB[current] then return true end
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(current)
        local nextID = mapInfo and mapInfo.parentMapID
        current = (nextID and not (issecretvalue and issecretvalue(nextID))) and nextID or nil
    end
    return false
end

-- LOOT SESSION HELPERS (shared by LOOT_READY, LOOT_OPENED, LOOT_CLOSED)

function Fns.UnitGuidLooksLikeMobCorpse(guid)
    if type(guid) ~= "string" then return false end
    if issecretvalue and issecretvalue(guid) then return false end
    return guid:match("^Creature") ~= nil or guid:match("^Vehicle") ~= nil
end

function Fns.LootSessionHasAnyMobCorpseSources(sourceGUIDs)
    for i = 1, #(sourceGUIDs or {}) do
        local g = sourceGUIDs[i]
        if Fns.UnitGuidLooksLikeMobCorpse(g) then
            local nid = Fns.GetNPCIDFromGUID(g)
            if not Fns.IsFishingBobberNpcId(nid) then
                return true
            end
        end
    end
    return false
end

function Fns.LootEligibleNpcFromGuid(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local nid = Fns.GetNPCIDFromGUID(guid)
    if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then return nid end
    return nil
end

function Fns.CurrentUnitsHaveEligibleNpcContext()
    local mo = Fns.SafeGetMouseoverGUID()
    local tg = Fns.SafeGetTargetGUID()
    local npc = Fns.SafeGetUnitGUID("npc")
    return Fns.LootEligibleNpcFromGuid(mo) or Fns.LootEligibleNpcFromGuid(tg) or Fns.LootEligibleNpcFromGuid(npc)
end

local function IsBlockingMobCorpseGuid(guid)
    if not guid or not Fns.UnitGuidLooksLikeMobCorpse(guid) then return false end
    local nid = Fns.GetNPCIDFromGUID(guid)
    return not Fns.IsFishingBobberNpcId(nid)
end

function Fns.LootSessionHasMobLootContext()
    return IsBlockingMobCorpseGuid(lootSession.mouseoverGUID)
        or IsBlockingMobCorpseGuid(lootSession.targetGUID)
        or IsBlockingMobCorpseGuid(lootSession.npcGUID)
end

function Fns.LootReadySnapshotHasMobLootContext(mouseoverGUID, targetGUID, npcGUID)
    return IsBlockingMobCorpseGuid(mouseoverGUID)
        or IsBlockingMobCorpseGuid(targetGUID)
        or IsBlockingMobCorpseGuid(npcGUID)
end

Fns.CurrentUnitsHaveMobLootContext = function()
    local mo = Fns.SafeGetMouseoverGUID()
    local tg = Fns.SafeGetTargetGUID()
    local npc = Fns.SafeGetUnitGUID("npc")
    return IsBlockingMobCorpseGuid(mo) or IsBlockingMobCorpseGuid(tg) or IsBlockingMobCorpseGuid(npc)
end

Fns.ResetLootSession = function()
    lootSession.numLoot = 0
    lootSession.sourceGUIDs = {}
    wipe(lootSession.slotData)
    lootSession.mouseoverGUID = nil
    lootSession.targetGUID = nil
    lootSession.npcGUID = nil
    lootSession.opened = false
end

local function CopyArray(src)
    local out = {}
    if src then
        for i = 1, #src do
            out[i] = src[i]
        end
    end
    return out
end

local function CopyLootSlotData(src)
    local out = {}
    if src then
        for i = 1, #src do
            local slot = src[i]
            if slot then
                out[i] = {
                    hasItem = slot.hasItem,
                    link = slot.link,
                }
            end
        end
    end
    return out
end

Fns.SnapshotLootSessionState = function()
    return {
        numLoot = lootSession.numLoot or 0,
        sourceGUIDs = CopyArray(lootSession.sourceGUIDs),
        slotData = CopyLootSlotData(lootSession.slotData),
        mouseoverGUID = lootSession.mouseoverGUID,
        targetGUID = lootSession.targetGUID,
        npcGUID = lootSession.npcGUID,
        opened = lootSession.opened == true,
    }
end

Fns.ApplyLootSessionState = function(snapshot)
    snapshot = snapshot or {}
    lootSession.numLoot = snapshot.numLoot or 0
    lootSession.sourceGUIDs = CopyArray(snapshot.sourceGUIDs)
    wipe(lootSession.slotData)
    local slots = snapshot.slotData
    if slots then
        for i = 1, #slots do
            local slot = slots[i]
            if slot then
                lootSession.slotData[i] = {
                    hasItem = slot.hasItem,
                    link = slot.link,
                }
            end
        end
    end
    lootSession.mouseoverGUID = snapshot.mouseoverGUID
    lootSession.targetGUID = snapshot.targetGUID
    lootSession.npcGUID = snapshot.npcGUID
    lootSession.opened = snapshot.opened == true
end

local function ApplyLootReadySnapshotToSession(numLoot)
    local readyGuids = lootReady.sourceGUIDs
    for i = 1, #readyGuids do
        lootSession.sourceGUIDs[i] = readyGuids[i]
    end
    for i = 1, numLoot do
        local slot = lootReady.slotData[i]
        if slot then
            lootSession.slotData[i] = { hasItem = slot.hasItem, link = slot.link }
        end
    end
end

Fns.CaptureLootSessionState = function()
    Fns.ResetLootSession()
    lootSession.mouseoverGUID = Fns.SafeGetMouseoverGUID()
    lootSession.targetGUID = Fns.SafeGetTargetGUID()
    lootSession.npcGUID = Fns.SafeGetUnitGUID("npc")
    lootSession.numLoot = (GetNumLootItems and GetNumLootItems()) or 0

    local now = GetTime()
    local reuseReady = lootReady.time > 0
        and (now - lootReady.time) <= LOOT_READY_STATE_TTL
        and lootReady.numLoot == lootSession.numLoot

    if reuseReady then
        ApplyLootReadySnapshotToSession(lootSession.numLoot)
    else
        lootSession.sourceGUIDs = Fns.GetAllLootSourceGUIDs() or {}
        wipe(lootSession.slotData)
        for i = 1, lootSession.numLoot do
            local hasItem = LootSlotHasItem and LootSlotHasItem(i)
            local link = GetLootSlotLink and GetLootSlotLink(i)
            if link and issecretvalue and issecretvalue(link) then link = nil end
            lootSession.slotData[i] = { hasItem = not not hasItem, link = link }
        end
    end
end

Fns.PromoteLootReadyToSession = function()
    Fns.ResetLootSession()
    if lootReady.time > 0 and (GetTime() - lootReady.time) <= LOOT_READY_STATE_TTL then
        lootSession.mouseoverGUID = lootReady.mouseoverGUID
        lootSession.targetGUID = lootReady.targetGUID
        lootSession.npcGUID = lootReady.npcGUID
        lootSession.sourceGUIDs = lootReady.sourceGUIDs
        lootSession.numLoot = lootReady.numLoot
        for i = 1, #lootReady.slotData do lootSession.slotData[i] = lootReady.slotData[i] end
    end
end

-- CLASSIFY-LOCK-PROCESS ROUTER
-- Determines exactly ONE route per loot session. Once classified, no
-- other source type can run. Each classification is based on hard
-- signals (API flags, exact GUID types, spell context) — never heuristic
-- fallthrough from one source type to another.
--
-- Priority (first match wins, all others locked out):
--   1. SKIP       — pickpocket / blocking vendor UI / profession loot
--   2. CONTAINER  — isFromItem flag OR recent tracked container use
--   3. FISHING    — IsFishingLoot() API OR structural bobber/pool sources in fishable zone;
--                   never from cast timer + empty sources alone.
--   4. NPC/OBJECT — ProcessNPCLoot (exact GUID→ID match only)

Fns.ClassifyLootSession = function(source, isFromItem)
    -- 1. SKIP: non-combat loot sources
    if V.isPickpocketing then return "skip" end
    if isBlockingInteractionOpen then return "skip" end
    if V.isProfessionLooting then return "skip" end

    -- Gathering cast + only GameObject sources (herb/ore node) → skip
    local now = GetTime()
    -- Slightly wide window: slow clients / double LOOT_READY can exceed 5s; still only GO+no mob context.
    if lastGatherCastTime and (now - lastGatherCastTime) < 12 then
        local anyGameObject, anyMob = false, false
        for i = 1, #lootSession.sourceGUIDs do
            local guid = lootSession.sourceGUIDs[i]
            if type(guid) == "string" then
                if guid:match("^GameObject") then anyGameObject = true end
                if guid:match("^Creature") or guid:match("^Vehicle") then anyMob = true end
            end
        end
        if anyGameObject and not anyMob and not Fns.LootSessionHasMobLootContext() then
            if not Fns.LootSessionHasTrackedObjectSource(lootSession.sourceGUIDs) then
                return "skip"
            end
        end
    end

    -- GameObject-only loot (herb/ore) in open-world maps that have fishing DB entries is not fishing
    -- unless API or structural bobber/pool says so (prevents false ProcessFishingLoot on Thorncap etc.).
    -- Tracked objectDropDB sources (Overflowing Dumpster, raid chests) always use NPC/object path.
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if not inInstance and Fns.LootSessionSourcesAreOnlyGameObjects(lootSession.sourceGUIDs) and Fns.IsInTrackableFishingZone() then
        if not Fns.LootSessionHasTrackedObjectSource(lootSession.sourceGUIDs) then
            local structFish = Fns.LootSourcesLookLikeFishingOnly(lootSession.sourceGUIDs)
            local apiOpen = (source == "opened" and Fns.SafeIsFishingLoot() and not V.isProfessionLooting)
            local closedFish = (source == "closed" and lootReady.wasFishing)
            if not structFish and not apiOpen and not closedFish then
                return "skip"
            end
        end
    end

    -- 2. CONTAINER: isFromItem flag (Blizzard API) or recent tracked container use
    local safeIsFromItem = isFromItem
    if issecretvalue and safeIsFromItem and issecretvalue(safeIsFromItem) then safeIsFromItem = nil end
    if not safeIsFromItem and source ~= "opened" then
        safeIsFromItem = V.lastContainerItemID and containerDropDB[V.lastContainerItemID] and (now - V.lastContainerItemTime) < 3
    end
    if safeIsFromItem then return "container" end

    -- 3. FISHING: IsFishingLoot() API, LOOT_READY snapshot, or structural bobber/pool sources in zone.
    --    Removed: "fishable zone + cast TTL + empty sources" — that misclassified normal kills after fishing.
    local fishingFromSourcesOnly = Fns.LootSourcesLookLikeFishingOnly(lootSession.sourceGUIDs)
        and Fns.IsInTrackableFishingZone()
    local fishingLootAPI = false
    if source == "opened" then
        fishingLootAPI = Fns.SafeIsFishingLoot() and not V.isProfessionLooting
    elseif source == "closed" then
        -- LOOT_OPENED is often skipped by auto-loot; use LOOT_READY snapshot and API while still valid.
        if lootReady.wasFishing then
            fishingLootAPI = true
        else
            fishingLootAPI = Fns.SafeIsFishingLoot() and not V.isProfessionLooting
        end
    end
    
    -- Dynamically learn toy/oversized bobber NPC IDs when the API confirms it is fishing.
    -- Uses existing Midnight-safe GUID helpers (UnitGuidLooksLikeMobCorpse + GetNPCIDFromGUID).
    if fishingLootAPI and lootSession.sourceGUIDs then
        for i = 1, #lootSession.sourceGUIDs do
            local g = lootSession.sourceGUIDs[i]
            if type(g) == "string" and not (issecretvalue and issecretvalue(g))
               and g:match("^Creature") then
                local nid = Fns.GetNPCIDFromGUID(g)
                if nid and not FISHING_BOBBER_NPC_IDS[nid] then
                    FISHING_BOBBER_NPC_IDS[nid] = true
                end
            end
        end
    end
    local fishingContextFresh = fishingCtx.active and (now - fishingCtx.castTime) <= FISHING_CAST_CONTEXT_TTL
    local sourceCompatible = fishingContextFresh and Fns.IsFishingSourceCompatible(lootSession.sourceGUIDs)

    if fishingLootAPI or fishingFromSourcesOnly then
        -- Any real tracked mob corpse in loot must use NPC path, not fishing.
        -- When fishingFromSourcesOnly, unknown bobber NPC ids are not in FISHING_BOBBER_NPC_IDS yet —
        -- LootSessionHasAnyMobCorpseSources would falsely block; only DB/eligible NPCs count as corpses.
        local corpseInSources
        if fishingFromSourcesOnly then
            corpseInSources = false
            for i = 1, #lootSession.sourceGUIDs do
                local g = lootSession.sourceGUIDs[i]
                if Fns.UnitGuidLooksLikeMobCorpse(g) then
                    local nid = Fns.GetNPCIDFromGUID(g)
                    if nid and not Fns.IsFishingBobberNpcId(nid)
                        and (tryCounterNpcEligible[nid] or npcDropDB[nid]) then
                        corpseInSources = true
                        break
                    end
                end
            end
        else
            corpseInSources = Fns.LootSessionHasAnyMobCorpseSources(lootSession.sourceGUIDs)
        end
        local corpseFromUnits = Fns.LootSessionHasMobLootContext()
        -- When the client reports fishing loot (API or LOOT_READY snapshot), trust it over unit
        -- frames — target/mouseover often stays on a nearby corpse while reeling in.
        local corpsePresent = fishingLootAPI and corpseInSources
            or (not fishingLootAPI and (corpseInSources or (not fishingFromSourcesOnly and corpseFromUnits)))
        if not corpsePresent then return "fishing" end
    end
    -- Clear stale fishing context when source GUIDs point to a tracked NPC/object
    if fishingContextFresh and not sourceCompatible then
        fishingCtx.active = false
        fishingCtx.castTime = 0
        if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel(); fishingCtx.resetTimer = nil end
    end

    -- 4. NPC / Object / Zone / Encounter
    return "npc"
end

local function ScheduleLootRouteProcessor(addon, route, source)
    local sessionSnapshot = Fns.SnapshotLootSessionState()
    local containerItemIDSnapshot = V.lastContainerItemID
    local containerItemTimeSnapshot = V.lastContainerItemTime
    local professionLootingSnapshot = V.isProfessionLooting

    C_Timer.After(0, function()
        if not addon or not Fns.IsAutoTryCounterEnabled() then return end

        local liveSession = Fns.SnapshotLootSessionState()
        local liveContainerItemID = V.lastContainerItemID
        local liveContainerItemTime = V.lastContainerItemTime
        local liveProfessionLooting = V.isProfessionLooting

        Fns.ApplyLootSessionState(sessionSnapshot)
        V.lastContainerItemID = containerItemIDSnapshot
        V.lastContainerItemTime = containerItemTimeSnapshot
        V.isProfessionLooting = professionLootingSnapshot

        local ok, err
        local P = ns.Profiler
        local routeFn
        if route == "container" then
            routeFn = function() addon:ProcessContainerLoot(source) end
        elseif route == "fishing" then
            routeFn = function() addon:ProcessFishingLoot(source) end
        elseif route == "npc" then
            routeFn = function() addon:ProcessNPCLoot(source) end
        end
        if routeFn and P and P.enabled and P.RunSlice then
            ok, err = pcall(P.RunSlice, P, P.CAT.SVC, "TC_LootRoute_" .. route, routeFn)
        elseif routeFn then
            ok, err = pcall(routeFn)
        else
            ok = true
        end

        Fns.ApplyLootSessionState(liveSession)
        V.lastContainerItemID = liveContainerItemID
        V.lastContainerItemTime = liveContainerItemTime
        V.isProfessionLooting = liveProfessionLooting

        if route == "fishing" and ok and (source == "closed" or not liveSession.opened) then
            fishingCtx.active = false
            fishingCtx.castTime = 0
            fishingCtx.lootWasFishing = false
            if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() fishingCtx.resetTimer = nil end
        end

        if not ok then error(err) end
    end)
end

Fns.RouteLootSession = function(self, source, isFromItem)
    if not Fns.IsAutoTryCounterEnabled() then return end

    local route = Fns.ClassifyLootSession(source, isFromItem)

    if route == "skip" then return end
    if route == "container" then
        ScheduleLootRouteProcessor(self, route, source)
        return
    end
    if route == "fishing" then
        ScheduleLootRouteProcessor(self, route, source)
        return
    end
    if route == "npc" then
        -- Instance boss: slot-link outcome when GUIDs are secret (Midnight).
        if Fns.TryInstanceBossSlotOutcomeFirst(self, source) then return end
        ScheduleLootRouteProcessor(self, route, source)
        return
    end
end

-- LOOT EVENT HANDLERS

---LOOT_OPENED handler (warcraft.wiki.gg/wiki/LOOT_OPENED).
---Fires AFTER LOOT_READY, but ONLY when the loot frame is actually rendered.
---Fast auto-loot or third-party auto-loot addons may skip this entirely.
---When it does fire, it provides the best-quality data: fresh unit GUIDs + isFromItem flag.
---@param event string
---@param autoLoot boolean
---@param isFromItem boolean Added in 8.3.0, true if loot is from opening a container item
function WarbandNexus:OnTryCounterLootOpened(event, autoLoot, isFromItem)
    Fns.CaptureLootSessionState()
    lootSession.opened = true
    Fns.RouteLootSession(self, "opened", isFromItem)
end

-- PROCESSING PATHS

Fns.GetAllLootSourceGUIDs = function()
    local uniqueGUIDs = {}
    local seen = {}
    local slotCreatureCount = 0

    local inRaidForGo = false
    do
        local okII, inI, instType = pcall(IsInInstance)
        if okII and inI and not (issecretvalue and issecretvalue(inI)) and inI
            and instType and not (issecretvalue and issecretvalue(instType)) and instType == "raid" then
            inRaidForGo = true
        end
    end

    -- Method 1: GetLootSourceInfo per slot — unpack ALL guid,qty pairs per slot
    if GetLootSourceInfo then
        local numItems = GetNumLootItems()
        for i = 1, numItems or 0 do
            local ok, packed = pcall(function(slot)
                return { GetLootSourceInfo(slot) }
            end, i)
            if ok and packed then
                for k = 1, #packed, 2 do
                    local sourceGUID = packed[k]
                    local safeGUID = Fns.SafeGuardGUID(sourceGUID)
                    if safeGUID and not seen[safeGUID] then
                        seen[safeGUID] = true
                        uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
                        local pfx = safeGUID:match("^(%a+)")
                        if pfx == "Creature" or pfx == "Vehicle" then
                            slotCreatureCount = slotCreatureCount + 1
                        end
                    end
                end
            end
        end
    end

    -- Method 2: UnitGUID when slots are empty (instant autoloot) or GetLootSourceInfo missed a source.
    -- When Method 1 already reported a mob corpse, do NOT add mouseover/target: a living rare on
    -- target while looting trash adds its GUID to this list and P1 MatchGuidExact attributes the
    -- voidstorm mount pool to the wrong NPC (false try before the rare dies).
    -- Unit "npc" is still included (corpse interact token at LOOT_READY/OPENED).
    local unitTokens
    if slotCreatureCount > 0 then
        unitTokens = { "npc" }
    else
        unitTokens = { "npc", "mouseover", "target" }
    end
    for u = 1, #unitTokens do
        local okU, unitGuid = pcall(UnitGUID, unitTokens[u])
        if okU and unitGuid then
            local safeGUID = Fns.SafeGuardGUID(unitGuid)
            if safeGUID and not seen[safeGUID] then
                local pfx = safeGUID:match("^(%a+)")
                if pfx == "Creature" or pfx == "Vehicle" or Fns.GetNPCIDFromGUID(safeGUID) then
                    seen[safeGUID] = true
                    uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
                elseif pfx == "GameObject" and objectDropDB then
                    local oid = Fns.GetObjectIDFromGUID(safeGUID)
                    if oid and (objectDropDB[oid] or inRaidForGo) then
                        seen[safeGUID] = true
                        uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
                    end
                end
            end
        end
    end

    return uniqueGUIDs
end

-- SOURCE RESOLVERS (P1-P4) — each populates ctx when a match is found.
-- ProcessNPCLoot calls them in strict sequence; first match wins.
-- Every match requires EXACT ID equality (npcID in npcDropDB, objectID
-- in objectDropDB, etc.). No heuristic guessing.

function Fns.MatchGuidExact(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local npcID = Fns.GetNPCIDFromGUID(guid)
    if npcID and tryCounterNpcEligible[npcID] and npcDropDB[npcID] then
        return npcDropDB[npcID], npcID, nil
    end
    local objectID = Fns.GetObjectIDFromGUID(guid)
    if objectID and objectDropDB[objectID] then
        return objectDropDB[objectID], nil, objectID
    end
    return nil
end

function Fns.CountCorpsesSharingDropTable(allSourceGUIDs, dropsTable)
    if not dropsTable or not allSourceGUIDs or #allSourceGUIDs == 0 then return 1 end
    local seen = {}
    local n = 0
    for i = 1, #allSourceGUIDs do
        local g = allSourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
            if not g:match("^GameObject") and not seen[g] then
                seen[g] = true
                local d2 = Fns.MatchGuidExact(g)
                if d2 == dropsTable then
                    n = n + 1
                end
            end
        end
    end
    return math.max(1, n)
end

function Fns.CountUniqueLootSourcesForNpcID(allSourceGUIDs, npcID)
    if not npcID or not allSourceGUIDs or #allSourceGUIDs == 0 then return 0 end
    local needle = "-" .. tostring(npcID) .. "-"
    local seen = {}
    local n = 0
    for i = 1, #allSourceGUIDs do
        local g = allSourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) and not seen[g] then
            seen[g] = true
            if not g:match("^GameObject") then
                if Fns.GetNPCIDFromGUID(g) == npcID then
                    n = n + 1
                elseif (g:match("^Creature") or g:match("^Vehicle")) and g:find(needle, 1, true) then
                    n = n + 1
                end
            end
        end
    end
    return n
end

function Fns.NpcDropEntryContainsAnyItemSet(dropsTable, itemIdSet)
    if not dropsTable or not itemIdSet then return false end
    for i = 1, #dropsTable do
        local d = dropsTable[i]
        if type(d) == "table" and d.itemID and itemIdSet[d.itemID] then
            return true
        end
    end
    return false
end

function Fns.BuildItemIdSetFromDropList(dlist)
    local s = {}
    if not dlist then return s end
    for i = 1, #dlist do
        local d = dlist[i]
        if d and d.itemID then s[d.itemID] = true end
    end
    return s
end

function Fns.BuildNpcIdsEligibleForDropItemSet(itemIdSet)
    local out = {}
    if not itemIdSet then return out end
    local any = false
    for _ in pairs(itemIdSet) do any = true; break end
    if not any then return out end
    for npcId, dt in pairs(npcDropDB) do
        if tryCounterNpcEligible[npcId] and type(dt) == "table" and Fns.NpcDropEntryContainsAnyItemSet(dt, itemIdSet) then
            out[#out + 1] = npcId
        end
    end
    return out
end

function Fns.CountCorpsesForMissedDropItems(allSourceGUIDs, itemIdSet, candidateNpcIds)
    if not allSourceGUIDs or #allSourceGUIDs == 0 then return 0 end
    local anyItem = false
    for _ in pairs(itemIdSet or {}) do anyItem = true; break end
    if not anyItem then return 0 end
    local seen = {}
    local n = 0
    for i = 1, #allSourceGUIDs do
        local g = allSourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) and not seen[g] then
            seen[g] = true
            if not g:match("^GameObject") then
                local ok = false
                local nid = Fns.GetNPCIDFromGUID(g)
                if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then
                    if Fns.NpcDropEntryContainsAnyItemSet(npcDropDB[nid], itemIdSet) then
                        ok = true
                    end
                end
                if not ok and candidateNpcIds and #candidateNpcIds > 0 and (g:match("^Creature") or g:match("^Vehicle")) then
                    for c = 1, #candidateNpcIds do
                        local npcId = candidateNpcIds[c]
                        local needle = "-" .. tostring(npcId) .. "-"
                        if g:find(needle, 1, true) and npcDropDB[npcId] and Fns.NpcDropEntryContainsAnyItemSet(npcDropDB[npcId], itemIdSet) then
                            ok = true
                            break
                        end
                    end
                end
                if ok then n = n + 1 end
            end
        end
    end
    return n
end

function Fns.BuildSortedSourceFingerprint(guids)
    if not guids or #guids == 0 then return "" end
    local t = {}
    for i = 1, #guids do
        t[i] = guids[i]
    end
    table.sort(t)
    return table.concat(t, "\0")
end

function Fns.ResolveFromGUIDs(ctx, sourceGUIDs, addon)
    if not sourceGUIDs or #sourceGUIDs == 0 then return nil end

    local allProcessed = true
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if srcGUID:match("^GameObject") then ctx.sourceIsGameObject = true end
        if processedGUIDs[srcGUID] then
            -- already handled
        else
            allProcessed = false
            local drops, npcID, objectID = Fns.MatchGuidExact(srcGUID)
            if drops then
                ctx.drops = drops
                ctx.matchedNpcID = npcID
                ctx.lastMatchedObjectID = objectID
                ctx.dedupGUID = srcGUID
                return nil
            end
        end
    end
    if allProcessed then
        -- Every source GUID was already counted this session (PROCESSED_GUID_TTL). Partial loot + reopen
        -- hits this path so we do not apply another try increment for the same corpses.
        return true
    end
    -- Keep first unprocessed GUID for housekeeping even when no drop table matched
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if not processedGUIDs[srcGUID] then ctx.dedupGUID = srcGUID; break end
    end
    return nil
end

function Fns.P2CandidateGuidAllowed(guid, sourceGUIDs)
    if not guid or type(guid) ~= "string" then return false end
    if issecretvalue and issecretvalue(guid) then return false end

    local hasCreatureVehicle = false
    local nonSecretCount = 0
    local gameObjectOnlyCount = 0
    if sourceGUIDs then
        for i = 1, #sourceGUIDs do
            local g = sourceGUIDs[i]
            if type(g) ~= "string" or (issecretvalue and issecretvalue(g)) then
                -- Midnight: corpse GUID may be secret — skip for classification (cannot enforce membership).
            else
                nonSecretCount = nonSecretCount + 1
                if g:match("^Creature") or g:match("^Vehicle") then
                    hasCreatureVehicle = true
                    if g == guid then return true end
                elseif g:match("^GameObject") then
                    gameObjectOnlyCount = gameObjectOnlyCount + 1
                end
            end
        end
    end

    local candIsMob = guid:match("^Creature") or guid:match("^Vehicle")
    if nonSecretCount > 0 and gameObjectOnlyCount == nonSecretCount and not hasCreatureVehicle and candIsMob then
        return false
    end
    if hasCreatureVehicle then return false end
    return true
end

function Fns.ResolveFromUnits(ctx, numLoot, addon)
    if ctx.drops then return end
    local lootIsEmpty = (numLoot == 0)
    local sources = lootSession.sourceGUIDs

    local candidates = {
        lootSession.npcGUID,
        lootSession.mouseoverGUID,
        lootSession.targetGUID,
    }
    if RT.lastLootSourceGUID and (GetTime() - RT.lastLootSourceTime) <= LAST_LOOT_SOURCE_TTL then
        candidates[#candidates + 1] = RT.lastLootSourceGUID
    end
    for i = 1, #candidates do
        local guid = candidates[i]
        if guid and (lootIsEmpty or not processedGUIDs[guid]) then
            if not Fns.P2CandidateGuidAllowed(guid, sources) then
                -- skip
            else
                local drops, npcID, objectID = Fns.MatchGuidExact(guid)
                if drops then
                    ctx.drops = drops
                    ctx.matchedNpcID = npcID
                    ctx.lastMatchedObjectID = objectID
                    ctx.dedupGUID = guid
                    ctx.targetGUID = guid
                    return
                end
            end
        end
    end
end

function Fns.ResolveFromZone(ctx, inInstance, addon)
    if ctx.drops then return end
    if not next(zoneDropDB) then return end
    if ctx.sourceIsGameObject or inInstance then return end

    if (GetTime() - V.lastEncounterEndTime) < RECENT_KILL_TTL then return end

    local mapID = Fns.GetSafeMapID()
    while mapID and mapID > 0 do
        local zData = zoneDropDB[mapID]
        if type(zData) == "table" then
            if zData.hostileOnly == true and zData.raresOnly ~= true then
                ctx.drops = zData.drops or zData
                return
            end
        end
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local nextID = mapInfo and mapInfo.parentMapID
        mapID = (nextID and not (issecretvalue and issecretvalue(nextID))) and nextID or nil
    end
end

function Fns.GuidAllowsEncounterRecentKillFallback(guid)
    if not guid or type(guid) ~= "string" then return true end
    if issecretvalue and issecretvalue(guid) then return true end
    if guid:match("^Player%-") then return true end
    local nid = Fns.GetNPCIDFromGUID(guid)
    if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then return false end
    local oid = Fns.GetObjectIDFromGUID(guid)
    if oid and objectDropDB[oid] then return false end
    return true
end

function Fns.ResolveFromRecentKills(ctx, inInstance)
    if ctx.drops then return end
    local now = GetTime()
    local bestGuid, bestKill = nil, nil
    for guid, killData in pairs(recentKills) do
        if not processedGUIDs[guid] and killData.isEncounter then
            local alive = (now - killData.time < ENCOUNTER_OBJECT_TTL)
            -- Allow linking encounter kill when: no loot GUID yet, chest-shaped sources, or P1's
            -- first unprocessed GUID is not a row we already resolve (Player tokens / random mobs).
            local canMatch = (not ctx.dedupGUID) or ctx.sourceIsGameObject
                or Fns.GuidAllowsEncounterRecentKillFallback(ctx.dedupGUID)
            if alive and canMatch then
                local nid = killData.npcID
                if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then
                    if not bestKill or killData.time > bestKill.time then
                        bestKill = killData
                        bestGuid = guid
                    end
                end
            end
        end
    end
    if bestGuid and bestKill then
        ctx.drops = npcDropDB[bestKill.npcID]
        ctx.matchedNpcID = bestKill.npcID
        ctx.dedupGUID = bestGuid
    end
end

function Fns.ResolveFromEncounterCache(ctx, inInstance)
    if ctx.drops then return end
    if not inInstance then return end
    if currentEncounterCache.startTime == 0 then return end
    if (GetTime() - currentEncounterCache.startTime) > ENCOUNTER_CACHE_TTL then return end

    -- Try encounter ID path first (authoritative), then name path.
    local npcIDs = nil
    local dedupTag = nil
    if currentEncounterCache.encounterID and encounterDB[currentEncounterCache.encounterID] then
        npcIDs = encounterDB[currentEncounterCache.encounterID]
        dedupTag = "enc_cache_" .. tostring(currentEncounterCache.encounterID)
    elseif currentEncounterCache.encounterName and encounterNameToNpcs[currentEncounterCache.encounterName] then
        npcIDs = encounterNameToNpcs[currentEncounterCache.encounterName]
        dedupTag = "enc_cache_name_" .. currentEncounterCache.encounterName
    end
    if not npcIDs or #npcIDs == 0 then return end

    -- Pick the first eligible NPC that has a drop table. Multi-NPC encounters (e.g. council fights)
    -- share the same encounterID, so first-eligible is correct for attribution.
    for i = 1, #npcIDs do
        local nid = npcIDs[i]
        if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then
            ctx.drops = npcDropDB[nid]
            ctx.matchedNpcID = nid
            ctx.dedupGUID = dedupTag
            return
        end
    end
end

function Fns.ResolveSylvanasMythicChestFromRaidGameObject(ctx, inInstance, sourceGUIDs)
    if ctx.drops or not inInstance or not sourceGUIDs or #sourceGUIDs == 0 then return end
    local _, instType, diff, _, _, _, _, tmpl = GetInstanceInfo()
    if issecretvalue and instType and issecretvalue(instType) then instType = nil end
    if issecretvalue and diff and issecretvalue(diff) then diff = nil end
    if issecretvalue and tmpl and issecretvalue(tmpl) then tmpl = nil end
    if instType ~= "raid" or diff ~= RAID_MYTHIC_DIFFICULTY_ID or tmpl ~= SANCTUM_RAID_TEMPLATE_INSTANCE_ID then
        return
    end
    local firstGO = nil
    for i = 1, #sourceGUIDs do
        local g = sourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) and g:match("^GameObject") then
            if not processedGUIDs[g] then
                firstGO = g
                break
            end
        end
    end
    if not firstGO then return end
    local row = objectDropDB and objectDropDB[SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID]
    if not row then return end
    ctx.drops = row
    ctx.lastMatchedObjectID = SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID
    ctx.matchedNpcID = nil
    ctx.dedupGUID = firstGO
    ctx.sourceIsGameObject = true
end

function Fns.IsSanctumMythicRaid()
    local _, instType, diff, _, _, _, _, tmpl = GetInstanceInfo()
    if issecretvalue and instType and issecretvalue(instType) then instType = nil end
    if issecretvalue and diff and issecretvalue(diff) then diff = nil end
    if issecretvalue and tmpl and issecretvalue(tmpl) then tmpl = nil end
    return instType == "raid" and diff == RAID_MYTHIC_DIFFICULTY_ID and tmpl == SANCTUM_RAID_TEMPLATE_INSTANCE_ID
end

function Fns.SlotOutcomeRuleMatchesInstance(rule, instType, diff, tmpl)
    if not rule or type(rule.bossNpcID) ~= "number" then return false end
    if rule.instanceType and instType ~= rule.instanceType then return false end
    if rule.templateInstanceID and tmpl ~= rule.templateInstanceID then return false end
    if type(rule.difficultyIDs) == "table" and #rule.difficultyIDs > 0 then
        if not diff then return false end
        local ok = false
        for j = 1, #rule.difficultyIDs do
            if rule.difficultyIDs[j] == diff then
                ok = true
                break
            end
        end
        if not ok then return false end
    end
    return true
end

function Fns.UpdateRecentKillByNpcIDCache(guid, killData)
    if not guid or not killData or not killData.isEncounter or not killData.npcID then return end
    local npcID = killData.npcID
    local entry = recentKillByNpcID[npcID]
    if not entry or killData.time > entry.killData.time then
        recentKillByNpcID[npcID] = { guid = guid, killData = killData }
    end
end

function Fns.InvalidateRecentKillByNpcIDForGuid(guid)
    if not guid then return end
    for npcID, entry in pairs(recentKillByNpcID) do
        if entry.guid == guid then
            recentKillByNpcID[npcID] = nil
        end
    end
end

function Fns.GetFreshEncounterKillForNpc(npcId)
    if not npcId then return nil, nil end
    local entry = recentKillByNpcID[npcId]
    if not entry then return nil, nil end
    local guid, kd = entry.guid, entry.killData
    if not guid or not kd or recentKills[guid] ~= kd then
        recentKillByNpcID[npcId] = nil
        return nil, nil
    end
    if (GetTime() - kd.time) >= ENCOUNTER_OBJECT_TTL then
        recentKillByNpcID[npcId] = nil
        return nil, nil
    end
    return guid, kd
end

function Fns.ResolveChatPath2KillDifficulty(npcID, itemID, inInst)
    local _, cached = Fns.GetFreshEncounterKillForNpc(npcID)
    if cached and cached.difficultyID and not (issecretvalue and issecretvalue(cached.difficultyID)) then
        return cached.difficultyID
    end
    local chatP2KillDiff = nil
    local bestT = 0
    local tNow = GetTime()
    local itemSet = inInst and { [itemID] = true } or nil
    for _, killData in pairs(recentKills or {}) do
        if killData.isEncounter and killData.difficultyID
            and not (issecretvalue and issecretvalue(killData.difficultyID)) then
            if killData.npcID == npcID then
                return killData.difficultyID
            end
            if inInst and itemSet and killData.npcID and npcDropDB[killData.npcID]
                and tryCounterNpcEligible[killData.npcID]
                and (tNow - killData.time) < ENCOUNTER_OBJECT_TTL then
                if Fns.NpcDropEntryContainsAnyItemSet(npcDropDB[killData.npcID], itemSet) and killData.time > bestT then
                    bestT = killData.time
                    chatP2KillDiff = killData.difficultyID
                end
            end
        end
    end
    return chatP2KillDiff
end

function Fns.LootSourcesHaveForeignEligibleCreature(sources, bossNpcId)
    if not sources then return false end
    for i = 1, #sources do
        local g = sources[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
            if g:match("^Creature") or g:match("^Vehicle") then
                local nid = Fns.GetNPCIDFromGUID(g)
                if nid and nid ~= bossNpcId and tryCounterNpcEligible[nid] and npcDropDB[nid] then
                    return true
                end
            end
        end
    end
    return false
end

function Fns.LootSlotsHaveReadableItemLink(slotData, numLoot)
    if not numLoot or numLoot < 1 or not slotData then return false end
    for i = 1, numLoot do
        local sd = slotData[i]
        if sd and sd.hasItem then
            local link = sd.link
            if (not link or type(link) ~= "string") and GetLootSlotLink then
                link = GetLootSlotLink(i)
                if link and issecretvalue and issecretvalue(link) then link = nil end
            end
            if link and type(link) == "string" and not (issecretvalue and issecretvalue(link)) then
                return true
            end
        end
    end
    return false
end

function Fns.LootSlotsHaveItemsPresent(slotData, numLoot)
    if not numLoot or numLoot < 1 then return false end
    if slotData then
        for i = 1, numLoot do
            local sd = slotData[i]
            if sd and sd.hasItem then return true end
        end
    end
    if LootSlotHasItem then
        for i = 1, numLoot do
            local ok, has = pcall(LootSlotHasItem, i)
            if ok and has then return true end
        end
    end
    return false
end

function Fns.TryReplayPendingEncounterLoot(self)
    if not self or not Fns.IsAutoTryCounterEnabled() then return false end
    local snap = RT.pendingEncounterLootSnapshot
    RT.pendingEncounterLootSnapshot = nil
    if not snap or (snap.numLoot or 0) < 1 then return false end
    local live = Fns.SnapshotLootSessionState()
    Fns.ApplyLootSessionState(snap)
    local handled = Fns.TryInstanceBossSlotOutcomeFirst(self, "closed")
    if not handled then
        self:ProcessNPCLoot("closed")
    end
    Fns.ApplyLootSessionState(live)
    return true
end

function Fns.ClearEncounterRecentKillsForNpcId(npcId)
    if not npcId then return end
    for guid, kd in pairs(recentKills) do
        if kd and kd.isEncounter and kd.npcID == npcId then
            recentKills[guid] = nil
            Fns.InvalidateRecentKillByNpcIDForGuid(guid)
        end
    end
    recentKillByNpcID[npcId] = nil
end

function Fns.ApplyBossSlotOutcomeFoundHandlers(trackable, found, drops, baselineTryCounts)
    local function preResetForDrop(drop)
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
        if not tryKey then return 0 end
        if baselineTryCounts then
            local ck = tcType .. "\0" .. tostring(tryKey)
            local base = baselineTryCounts[ck]
            if base ~= nil then
                return Fns.AdjustPreResetForDelayedReseed(base, tcType, tryKey)
            end
        end
        local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
        return Fns.AdjustPreResetForDelayedReseed(currentCount, tcType, tryKey)
    end

    for i = 1, #trackable do
        local drop = trackable[i]
        if drop and drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey and not Fns.IsObtainOutcomeApplied(tcType, tryKey, drop) then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local preResetCount = preResetForDrop(drop)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                if drop.type == "item" then
                    V.lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    V.lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" and preResetCount and preResetCount > 0 then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_OBTAINED_RESET", "Obtained %s! Try counter reset.", itemLink, preResetCount))
                if drop.type == "item" then
                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                    SendTryCounterCollectibleObtained(WarbandNexus, {
                        type = "item",
                        id = drop.itemID,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                        fromTryCounter = true,
                    }, drop.itemID)
                end
                Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
            end
        end
    end
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop and not drop.repeatable and found[drop.itemID] then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey and not Fns.IsObtainOutcomeApplied(tcType, tryKey, drop) then
                Fns.MarkDropObtainedThisKill(tcType, tryKey, drop)
                local currentCount = preResetForDrop(drop)
                local cacheKey = tcType .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = currentCount or 0
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_OBTAINED", "Obtained %s!", itemLink, currentCount))
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = drop.type,
                    id = (drop.type == "item") and drop.itemID or tryKey,
                    name = itemName or drop.name or "Unknown",
                    icon = itemIcon,
                    preResetTryCount = currentCount,
                    fromTryCounter = true,
                }, drop.itemID)
                Fns.MarkObtainOutcomeApplied(tcType, tryKey, drop)
            end
        end
    end
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop and not drop.repeatable and drop.type ~= "item" and not found[drop.itemID] then
            local tryKey = Fns.GetTryCountKey(drop)
            if tryKey then
                local currentCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = currentCount
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
            end
        end
    end
end

function Fns.TryInstanceBossSlotOutcomeFirst(self, lootRouteSource)
    if not self or not Fns.IsAutoTryCounterEnabled() then return false end
    if #instanceBossSlotOutcomeRules == 0 then return false end
    lootRouteSource = lootRouteSource or "opened"

    local _, instType, diff, _, _, _, _, tmpl = GetInstanceInfo()
    if tryCounterSelfTestSlotInstance then
        instType = tryCounterSelfTestSlotInstance.instanceType or instType
        diff = tryCounterSelfTestSlotInstance.difficulty or diff
        tmpl = tryCounterSelfTestSlotInstance.templateInstanceID or tmpl
    end
    if issecretvalue and instType and issecretvalue(instType) then instType = nil end
    if issecretvalue and diff and issecretvalue(diff) then diff = nil end
    if issecretvalue and tmpl and issecretvalue(tmpl) then tmpl = nil end

    local bestRule, bestKillTime, bestKillData = nil, 0, nil
    for ri = 1, #instanceBossSlotOutcomeRules do
        local r = instanceBossSlotOutcomeRules[ri]
        if Fns.SlotOutcomeRuleMatchesInstance(r, instType, diff, tmpl) then
            if not Fns.IsLockoutDuplicate(r.bossNpcID) then
                local _, kd = Fns.GetFreshEncounterKillForNpc(r.bossNpcID)
                if kd and kd.time > bestKillTime then
                    bestKillTime = kd.time
                    bestRule = r
                    bestKillData = kd
                end
            end
        end
    end
    if not bestRule or not bestKillData then return false end

    local sources = lootSession.sourceGUIDs or {}
    if Fns.LootSourcesHaveForeignEligibleCreature(sources, bestRule.bossNpcID) then return false end

    local drops = npcDropDB[bestRule.bossNpcID]
    if not drops then return false end

    local killData = bestKillData

    local recentKillDiff = killData.difficultyID
    if issecretvalue and recentKillDiff and issecretvalue(recentKillDiff) then recentKillDiff = nil end
    local encounterDiffID = Fns.ResolveEncounterDifficultyForLootGating(true, recentKillDiff, diff)
    local trackable = tryCounterSelfTestBossTrackable and tryCounterSelfTestBossTrackable[bestRule.bossNpcID]
        or Fns.FilterDropsByDifficulty(drops, encounterDiffID)
    if #trackable == 0 then return false end

    local numLoot = lootSession.numLoot or 0
    if numLoot < 1 then return false end

    local encounterIDForKey = Fns.GetEncounterIDForNpcID(bestRule.bossNpcID) or bestRule.encounterJournalID
    local slotOutcomeSourceKey = encounterIDForKey
        and ("encounter_" .. tostring(encounterIDForKey))
        or ("inst_slot_" .. tostring(bestRule.bossNpcID))

    if lootRouteSource == "opened" then
        if not Fns.LootSlotsHaveReadableItemLink(lootSession.slotData, numLoot) then
            local foundEarly = Fns.ScanLootForItems(trackable, numLoot, lootSession.slotData)
            local anyEarly = false
            for ti = 1, #trackable do
                if trackable[ti] and foundEarly[trackable[ti].itemID] then anyEarly = true; break end
            end
            -- Miss on chest loot: mount absent but slots have gear (links may stay secret until close).
            if not anyEarly and not Fns.LootSlotsHaveItemsPresent(lootSession.slotData, numLoot) then
                return false
            end
        end
        Fns.StageDeferredLootSession({
            kind = "slot_boss",
            trackable = trackable,
            drops = drops,
            slotOutcomeSourceKey = slotOutcomeSourceKey,
            slotBossNpcID = bestRule.bossNpcID,
            allSourceGUIDs = sources,
        })
        return true
    end

    local found = Fns.BuildNpcLootFoundMap(trackable, numLoot, lootSession.slotData)
    local baseline = Fns.CaptureTryCountBaselines(trackable)
    Fns.ApplySlotBossLootOutcomes(self, {
        trackable = trackable,
        found = found,
        drops = drops,
        slotOutcomeSourceKey = slotOutcomeSourceKey,
        slotBossNpcID = bestRule.bossNpcID,
        allSourceGUIDs = sources,
        baselineTryCounts = baseline,
    })
    return true
end

-- ProcessNPCLoot — orchestrator: P1→P2→P3→P4, first match wins, exact IDs only.

function Fns.GetEncounterIDForNpcID(npcID)
    if not npcID then return nil end
    return npcIDToEncounterID[npcID]
end

function Fns.BuildTryCountSourceKey(matchedEncounterID, matchedNpcID, lastMatchedObjectID, dedupGUID)
    if matchedEncounterID then
        return "encounter_" .. tostring(matchedEncounterID)
    end
    if lastMatchedObjectID then
        if dedupGUID and type(dedupGUID) == "string" then
            return "obj_" .. tostring(lastMatchedObjectID) .. "\0" .. dedupGUID
        end
        return "obj_" .. tostring(lastMatchedObjectID)
    end
    if matchedNpcID then
        if dedupGUID and type(dedupGUID) == "string" and not dedupGUID:match("^zone_") then
            return "npc_" .. tostring(matchedNpcID) .. "\0" .. dedupGUID
        end
        return "npc_" .. tostring(matchedNpcID)
    end
    if dedupGUID and type(dedupGUID) == "string" then
        return dedupGUID
    end
    return nil
end

function WarbandNexus:ProcessNPCLoot(lootRouteSource)
    lootRouteSource = lootRouteSource or "opened"
    local ctx = {
        drops = nil,
        matchedNpcID = nil,
        dedupGUID = nil,
        targetGUID = nil,
        sourceIsGameObject = false,
        lastMatchedObjectID = nil,
    }
    local allSourceGUIDs = lootSession.sourceGUIDs
    local numLoot = lootSession.numLoot

    -- P1: Per-slot source GUIDs (most reliable — exact GUID→ID)
    local earlyExit = Fns.ResolveFromGUIDs(ctx, allSourceGUIDs, self)
    if earlyExit then return end

    -- P2: Unit GUIDs — only when P1 found nothing (no fallback after a P1 match)
    if not ctx.drops then
        Fns.ResolveFromUnits(ctx, numLoot, self)
    end

    -- P3: Zone-wide hostileOnly pools only (see ResolveFromZone — no raresOnly anonymous pools)
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if not ctx.drops then
        Fns.ResolveFromZone(ctx, inInstance, self)
    end

    -- P4: Encounter recentKills (instance boss bookkeeping)
    if not ctx.drops then
        Fns.ResolveFromRecentKills(ctx, inInstance)
    end

    -- P5: ENCOUNTER_START cache (Midnight 12.0 rescue when all GUIDs are secret).
    -- Only triggers inside an instance; start-time snapshot supplies non-secret IDs
    -- that encounterDB / encounterNameToNpcs can resolve to a drop table.
    if not ctx.drops then
        Fns.ResolveFromEncounterCache(ctx, inInstance)
    end

    if not ctx.drops then
        Fns.ResolveSylvanasMythicChestFromRaidGameObject(ctx, inInstance, allSourceGUIDs)
    end

    if not ctx.drops then
        if inInstance and not self._pendingEncounterLootRetried then
            self._pendingEncounterLoot = true
            if (lootSession.numLoot or 0) > 0 then
                RT.pendingEncounterLootSnapshot = Fns.SnapshotLootSessionState()
            end
        end
        return
    end
    self._pendingEncounterLoot = nil
    RT.pendingEncounterLootSnapshot = nil

    -- Unpack ctx into locals for readability in post-match processing
    local drops = ctx.drops
    local matchedNpcID = ctx.matchedNpcID
    local dedupGUID = ctx.dedupGUID
    local lastMatchedObjectID = ctx.lastMatchedObjectID

    -- Loot attributed to this NPC — cancel deferred quest fallback (phase-rare parachute path).
    if matchedNpcID and lockoutQuestsDB[matchedNpcID] then
        Fns.MarkLockoutLootTouched(matchedNpcID)
        Fns.CancelLockoutQuestFallbackForNpc(matchedNpcID)
    end

    -- Auto-discovery: if this NPC has drops but no lockout quest, schedule discovery
    if matchedNpcID and not lockoutQuestsDB[matchedNpcID] and (npcDropDB[matchedNpcID] or (ns.CollectibleSourceDB and ns.CollectibleSourceDB.rares and ns.CollectibleSourceDB.rares[matchedNpcID])) then
        discoveryPendingNpcID = matchedNpcID
        discoveryPendingTime = GetTime()
        C_Timer.After(2, Fns.TryDiscoverLockoutQuest)
    end

    -- Encounter recentKills cleanup runs before filtering (even when #trackable == 0) so multi-boss
    -- raids do not leak encounter entries into unrelated loot events.

    -- Resolve encounter difficulty BEFORE cleanup deletes recentKills.
    local recentKillDiff = nil
    if dedupGUID then
        local killEntry = recentKills[dedupGUID]
        if killEntry and killEntry.difficultyID then recentKillDiff = killEntry.difficultyID end
    end
    if not recentKillDiff and matchedNpcID then
        for _, killData in pairs(recentKills) do
            if killData.isEncounter and killData.npcID == matchedNpcID and killData.difficultyID then
                recentKillDiff = killData.difficultyID
                break
            end
        end
    end
    -- GameObject chests (e.g. Sylvanas's Chest): P1 matches objectDropDB first, so matchedNpcID is nil
    -- and the encounter-kill loop above never runs. Mythic-gated boss rows then fail-closed with nil
    -- encounterDiffID. Reuse difficulty from the freshest recent encounter kill whose NPC table lists
    -- any of this object's loot itemIDs (same boss session).
    if not recentKillDiff and inInstance and lastMatchedObjectID and objectDropDB[lastMatchedObjectID] then
        local objDrops = objectDropDB[lastMatchedObjectID]
        local itemSet = Fns.BuildItemIdSetFromDropList(objDrops)
        local tNow = GetTime()
        local bestT = 0
        for _, killData in pairs(recentKills) do
            if killData.isEncounter and killData.npcID
                and tryCounterNpcEligible[killData.npcID] and npcDropDB[killData.npcID]
                and (tNow - killData.time) < ENCOUNTER_OBJECT_TTL then
                if Fns.NpcDropEntryContainsAnyItemSet(npcDropDB[killData.npcID], itemSet) and killData.time > bestT then
                    bestT = killData.time
                    local kdDiff = killData.difficultyID
                    if kdDiff and not (issecretvalue and issecretvalue(kdDiff)) then
                        recentKillDiff = kdDiff
                    end
                end
            end
        end
    end
    local _, _, liveRaidDiff = GetInstanceInfo()
    local encounterDiffID = Fns.ResolveEncounterDifficultyForLootGating(inInstance, recentKillDiff, liveRaidDiff)

    -- Look up encounter ID for this NPC (reused for cleanup, dedup, and key setting).
    local matchedEncounterID = nil
    local matchedEncounterNpcs = nil
    if matchedNpcID then
        matchedEncounterID = npcIDToEncounterID[matchedNpcID]
        if matchedEncounterID then
            matchedEncounterNpcs = encounterDB[matchedEncounterID]
        end
    end

    -- Clean up encounter entries in recentKills for ALL NPCs in this encounter.
    if matchedNpcID then
        if matchedEncounterNpcs then
            local npcSet = {}
            for i = 1, #matchedEncounterNpcs do
                local nid = matchedEncounterNpcs[i]
                npcSet[nid] = true
            end
            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and npcSet[killData.npcID] then
                    recentKills[guid] = nil
                    Fns.InvalidateRecentKillByNpcIDForGuid(guid)
                end
            end
        else
            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and killData.npcID == matchedNpcID then
                    recentKills[guid] = nil
                    Fns.InvalidateRecentKillByNpcIDForGuid(guid)
                end
            end
        end
    end

    -- Filter drops: repeatable + uncollected, difficulty-gated (shared with CHAT / ENC delayed).
    local trackable, diffSkipped = Fns.FilterDropsByDifficulty(drops, encounterDiffID)
    if #trackable == 0 then
        if diffSkipped then
            local itemLink = Fns.GetDropItemLink(diffSkipped.drop)
            local currentLabel = DIFFICULTY_ID_TO_LABELS[encounterDiffID] or tostring(encounterDiffID or "?")
            local skipDedupKey = (matchedEncounterID and ("diffskip_enc_" .. tostring(matchedEncounterID)))
                or (matchedNpcID and ("diffskip_npc_" .. tostring(matchedNpcID)))
                or ("diffskip_item_" .. tostring(diffSkipped.drop and diffSkipped.drop.itemID or 0))
            local tSkip = GetTime()
            if skipDedupKey ~= lastDifficultySkipChatKey or (tSkip - lastDifficultySkipChatTime) >= SKIP_CHAT_DEDUP_SEC then
                lastDifficultySkipChatKey = skipDedupKey
                lastDifficultySkipChatTime = tSkip
                Fns.TryChat(format(
                    "|cff9370DB[WN-Counter]|r |cff888888" ..
                    ((ns.L and ns.L["TRYCOUNTER_DIFFICULTY_SKIP"]) or "Skipped: %s requires %s difficulty (current: %s)"),
                    itemLink, diffSkipped.required, currentLabel
                ))
            end
        end
        -- Do NOT set V.lastTryCountSourceKey here: no try was consumed. Setting it blocked the ENCOUNTER_END
        -- 5s delayed fallback (debounce saw a "phantom" encounter touch within 10s) and left mythic chest
        -- paths with nil difficulty permanently uncounted until a reload.
        return
    end

    -- Mark GUIDs only after we will consume a try (avoids poisoning chest reopen after diff-skip).
    local now = GetTime()
    if dedupGUID and (type(dedupGUID) ~= "string" or not dedupGUID:match("^zone_")) then
        processedGUIDs[dedupGUID] = now
    end
    for i = 1, #allSourceGUIDs do
        local srcGUID = allSourceGUIDs[i]
        if not processedGUIDs[srcGUID] then processedGUIDs[srcGUID] = now end
    end
    if ctx.targetGUID and not processedGUIDs[ctx.targetGUID] then
        processedGUIDs[ctx.targetGUID] = now
    end

    local deferOutcome = Fns.ShouldDeferLootOutcomeUntilClose(lootRouteSource)
    if deferOutcome then
        Fns.StageDeferredLootSession({
            kind = "npc",
            matchedNpcID = matchedNpcID,
            matchedEncounterID = matchedEncounterID,
            lastMatchedObjectID = lastMatchedObjectID,
            dedupGUID = dedupGUID,
            drops = drops,
            trackable = trackable,
            encounterDiffID = encounterDiffID,
            allSourceGUIDs = allSourceGUIDs,
        })
        return
    end

    local isLockoutSkip = matchedNpcID and Fns.IsLockoutDuplicate(matchedNpcID)
    local found = Fns.BuildNpcLootFoundMap(trackable, lootSession.numLoot, lootSession.slotData)
    local baselineTryCounts = Fns.CaptureTryCountBaselines(trackable)

    Fns.ApplyNpcLootOutcomes(self, {
        trackable = trackable,
        found = found,
        drops = drops,
        matchedNpcID = matchedNpcID,
        matchedEncounterID = matchedEncounterID,
        lastMatchedObjectID = lastMatchedObjectID,
        dedupGUID = dedupGUID,
        allSourceGUIDs = allSourceGUIDs,
        isLockoutSkip = isLockoutSkip,
        baselineTryCounts = baselineTryCounts,
    })
end

---Process loot from fishing.
---Algorithm (source-agnostic): one loot open in a trackable zone = one attempt.
---We do NOT care what dropped (common/rare); we only check: is the trackable drop (e.g. Nether-Warped Egg) in the loot?
---If yes → reset try count; if no → increment. So every fishing LOOT_OPENED in zone is counted.
function WarbandNexus:ProcessFishingLoot(lootRouteSource)
    lootRouteSource = lootRouteSource or "opened"
    -- Gathering/profession loot windows must never count zone fishing tries (e.g. herb in Voidstorm).
    if V.isProfessionLooting then return end
    local drops, inInstance = Fns.CollectFishingDropsForZone()
    if inInstance then return end
    if #drops == 0 then
        return
    end
    local trackable = {}
    for i = 1, #drops do
        local d = drops[i]
        if d.repeatable or not Fns.IsCollectibleCollected(d) then trackable[#trackable + 1] = d end
    end
    if #trackable == 0 then return end

    fishingCtx.lootWasFishing = true

    if Fns.ShouldDeferLootOutcomeUntilClose(lootRouteSource) then
        Fns.StageDeferredLootSession({ kind = "fishing", trackable = trackable })
        return
    end

    local found = Fns.BuildNpcLootFoundMap(trackable, lootSession.numLoot, lootSession.slotData)
    Fns.ApplyFishingLootOutcomes(self, {
        trackable = trackable,
        found = found,
        baselineTryCounts = Fns.CaptureTryCountBaselines(trackable),
    })
end

---Process loot from container items (Paragon caches, Wriggling Pinnacle Cache, etc.)
---Uses V.lastContainerItemID (set by ITEM_LOCK_CHANGED) to determine which container
---was opened, enabling targeted try count increment on miss.
function WarbandNexus:ProcessContainerLoot(lootRouteSource)
    lootRouteSource = lootRouteSource or "opened"
    local containerItemID = V.lastContainerItemID
    V.lastContainerItemID = nil  -- Consume immediately to prevent stale data

    -- If we know which container was opened, do targeted detection
    if containerItemID and containerDropDB[containerItemID] then
        local containerData = containerDropDB[containerItemID]
        local drops = containerData.drops or containerData
        if not drops or type(drops) ~= "table" or #drops == 0 then return end

        local trackable = {}
        for i = 1, #drops do
            local drop = drops[i]
            if drop.repeatable or not Fns.IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        end
        if #trackable == 0 then return end

        if Fns.ShouldDeferLootOutcomeUntilClose(lootRouteSource) then
            Fns.StageDeferredLootSession({
                kind = "container",
                trackable = trackable,
                containerItemID = containerItemID,
            })
            return
        end

        local found = Fns.BuildNpcLootFoundMap(trackable, lootSession.numLoot, lootSession.slotData)
        Fns.ApplyContainerLootOutcomes(self, {
            trackable = trackable,
            found = found,
            containerItemID = containerItemID,
            baselineTryCounts = Fns.CaptureTryCountBaselines(trackable),
        })
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
        if not Fns.IsCollectibleCollected(allContainerDrops[i]) then
            uncollected[#uncollected + 1] = allContainerDrops[i]
        end
    end
    if #uncollected == 0 then return end

    -- Scan loot window (passive only - can't increment without knowing which container)
    Fns.ScanLootForItems(uncollected)
end

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
        for cid, containerData in pairs(containerDropDB) do
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
    for _, containerData in pairs(containerDropDB) do
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
                        if not npcDropDB[npcID] then
                            npcDropDB[npcID] = {}
                        end
                        local existing = npcDropDB[npcID]
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
                        if not objectDropDB[objectID] then
                            objectDropDB[objectID] = {}
                        end
                        local existing = objectDropDB[objectID]
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
    end
    Fns.BuildTryCounterNpcEligible()
    Fns.SyncTryCounterRTTableRefs()
end

-- STATISTICS SEEDING (WoW Achievement Statistics API)

local SEED_BUDGET_MS = 3  -- max milliseconds per batch frame

function Fns.ScheduleDeferredRarityMountMaxSync(delaySec)
    local syncSerial = perCharStatSyncSerial
    delaySec = tonumber(delaySec) or 2
    C_Timer.After(delaySec, function()
        if syncSerial ~= perCharStatSyncSerial then return end
        if not tryCounterReady or not Fns.EnsureDB() then return end
        if WarbandNexus.SyncRarityMountAttemptsMax then
            WarbandNexus:SyncRarityMountAttemptsMax()
        end
    end)
end

function Fns.SeedFromStatistics(opts)
    opts = opts or {}
    if not Fns.EnsureDB() then return end
    if not GetStatistic then return end

    if opts.pruneOrphans then
        Fns.PruneStatisticSnapshotsOrphanKeys()
    end
    Fns.EnsureMergedStatisticSeedIndex()

    local charKey = StatisticSnapshotStorageKey()
    if not charKey then return end

    local P = ns.Profiler
    local seedLabel = P and P.SliceLabel and P:SliceLabel(P.CAT.SVC, "TC_SeedFromStatistics")
    if P and seedLabel then P:StartAsync(seedLabel) end
    local LT = ns.LoadingTracker
    if LT then LT:Register("trycounts", (ns.L and ns.L["TRYCOUNTER_TRY_COUNTS"]) or "Try Counts") end
    local snapshots = WarbandNexus.db.global.statisticSnapshots
    if not snapshots then
        WarbandNexus.db.global.statisticSnapshots = {}
        snapshots = WarbandNexus.db.global.statisticSnapshots
    end
    if not snapshots[charKey] then
        snapshots[charKey] = {}
    end
    local charSnapshot = snapshots[charKey]

    -- Merged buckets: one seed per (type, tryKey) with union of all difficulty/NPC statistic columns.
    -- Plus pending rows where tryKey was nil (journal cold) — same per-drop stat list as before.
    wipe(statSeedWorkQueue)
    local seedQueue = statSeedWorkQueue
    local seedQueueLen = 0
    for i = 1, #mergedStatSeedGroupList do
        seedQueueLen = seedQueueLen + 1
        seedQueue[seedQueueLen] = { bucket = mergedStatSeedGroupList[i] }
    end
    for p = 1, #statSeedTryKeyPending do
        local pend = statSeedTryKeyPending[p]
        local sids = Fns.ResolveReseedStatIdsForDrop(pend.drop, pend.npcStatIds)
        if sids and #sids > 0 then
            seedQueueLen = seedQueueLen + 1
            seedQueue[seedQueueLen] = {
                drop = pend.drop,
                statIds = sids,
                npcStatIds = pend.npcStatIds,
            }
        end
    end
    for i = seedQueueLen + 1, #seedQueue do
        seedQueue[i] = nil
    end

    local queueIdx = 1
    local seeded = 0
    local unresolvedDrops = {}

    local function ProcessBatch()
        if not Fns.EnsureDB() then return end
        local batchStart = debugprofilestop()

        while queueIdx <= #seedQueue do
            local entry = seedQueue[queueIdx]

            local function ProcessBatchDrop(drop, thisCharTotal, hadReadable, npcStatIdsForUnresolved)
                if not drop.guaranteed then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey then
                        Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, thisCharTotal, hadReadable)
                        local globalTotal = Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
                        if Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable) then
                            if drop.type == "item" and drop.questStarters then
                                for j = 1, #drop.questStarters do
                                    local qs = drop.questStarters[j]
                                    if qs and qs.type == "mount" and qs.itemID then
                                        local k1 = Fns.ResolveCollectibleID(qs)
                                        local k2 = qs.itemID
                                        RegisterQuestStarterMountKey(k1 or k2, drop.itemID)
                                        if k1 and k1 ~= k2 then RegisterQuestStarterMountKey(k2, drop.itemID) end
                                    end
                                end
                            end
                            seeded = seeded + 1
                        end
                    else
                        unresolvedDrops[#unresolvedDrops + 1] = {
                            drop = drop,
                            npcStatIds = npcStatIdsForUnresolved,
                        }
                    end
                end
                if drop and drop.questStarters then
                    for j = 1, #drop.questStarters do
                        local qs = drop.questStarters[j]
                        ProcessBatchDrop(qs, thisCharTotal, hadReadable, npcStatIdsForUnresolved)
                    end
                end
            end

            if entry.bucket then
                local b = entry.bucket
                local thisCharTotal, hadReadable = Fns.SumStatisticTotalsFromIds(b.statIds)
                for di = 1, #b.drops do
                    ProcessBatchDrop(b.drops[di], thisCharTotal, hadReadable, nil)
                end
            else
                local thisCharTotal, hadReadable = Fns.SumStatisticTotalsFromIds(entry.statIds)
                ProcessBatchDrop(entry.drop, thisCharTotal, hadReadable, entry.npcStatIds)
            end

            queueIdx = queueIdx + 1

            if debugprofilestop() - batchStart > SEED_BUDGET_MS then
                C_Timer.After(0, ProcessBatch)
                return
            end
        end

        if P and seedLabel then P:StopAsync(seedLabel) end
        if LT then LT:Complete("trycounts") end
        if seeded > 0 then
            WarbandNexus:Debug("TryCounter: Seeded %d entries from WoW Statistics (char: %s)", seeded, charKey)
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_seeded" })
            end
        end

        -- Rarity may load after this batch; two passes catch late `groups.mounts` availability (max never lowers WN).
        Fns.ScheduleDeferredRarityMountMaxSync(2)
        Fns.ScheduleDeferredRarityMountMaxSync(10)

        if #unresolvedDrops > 0 then
            WarbandNexus:Debug("TryCounter: %d drops unresolved, retrying in 10s...", #unresolvedDrops)
            C_Timer.After(10, function()
                if not Fns.EnsureDB() then return end
                Fns.EnsureMergedStatisticSeedIndex()
                local retrySeeded = 0
                local stillUnresolved = {}
                for i = 1, #unresolvedDrops do
                    local uEntry = unresolvedDrops[i]
                    local drop = uEntry.drop
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey then
                        local statList = Fns.ResolveMergedStatisticIdsForDrop(drop, Fns.ResolveReseedStatIdsForDrop(drop, uEntry.npcStatIds))
                        local t, hadReadable = Fns.SumStatisticTotalsFromIds(statList)
                        Fns.WriteStatisticSnapshotIfReadable(charSnapshot, tryKey, t, hadReadable)
                        local globalTotal = Fns.SumStatisticSnapshotsGlobal(snapshots, tryKey)
                        if Fns.ApplyTryCountFromStatisticTotals(tcType, tryKey, globalTotal, hadReadable) then
                            retrySeeded = retrySeeded + 1
                        end
                    else
                        stillUnresolved[#stillUnresolved + 1] = uEntry
                    end
                end
                if retrySeeded > 0 then
                    WarbandNexus:Debug("TryCounter: Retry resolved %d / %d entries", retrySeeded, #unresolvedDrops)
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_seeded" })
                    end
                end
                Fns.ScheduleDeferredRarityMountMaxSync(2)

                if #stillUnresolved > 0 then
                    WarbandNexus:Debug("TryCounter: %d still unresolved, final retry in 30s...", #stillUnresolved)
                    C_Timer.After(30, function()
                        if not Fns.EnsureDB() then return end
                        Fns.EnsureMergedStatisticSeedIndex()
                        local finalSeeded = 0
                        local snaps = WarbandNexus.db.global.statisticSnapshots
                        for j = 1, #stillUnresolved do
                            local fEntry = stillUnresolved[j]
                            local drop = fEntry.drop
                            local tcType, finalKey = Fns.GetTryCountTypeAndKey(drop)
                            if finalKey and snaps then
                                local statList = Fns.ResolveMergedStatisticIdsForDrop(drop, Fns.ResolveReseedStatIdsForDrop(drop, fEntry.npcStatIds))
                                local t, hadReadable = Fns.SumStatisticTotalsFromIds(statList)
                                if snaps[charKey] then
                                    Fns.WriteStatisticSnapshotIfReadable(snaps[charKey], finalKey, t, hadReadable)
                                end
                                local total = Fns.SumStatisticSnapshotsGlobal(snaps, finalKey)
                                if Fns.ApplyTryCountFromStatisticTotals(tcType, finalKey, total, hadReadable) then
                                    finalSeeded = finalSeeded + 1
                                end
                            end
                        end
                        if finalSeeded > 0 then
                            WarbandNexus:Debug("TryCounter: Final retry resolved %d / %d entries", finalSeeded, #stillUnresolved)
                            if WarbandNexus.SendMessage then
                                WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_seeded" })
                            end
                        end
                        Fns.ScheduleDeferredRarityMountMaxSync(2)
                    end)
                end
            end)
        end
    end

    ProcessBatch()
end

function Fns.PurgeStaleRuntimeStatReseedNpcs()
    local now = GetTime()
    for npcID, markedAt in pairs(pendingRuntimeStatNpcIds) do
        if now - markedAt > RUNTIME_STAT_NPC_TTL then
            pendingRuntimeStatNpcIds[npcID] = nil
        end
    end
end

function Fns.MarkNpcForRuntimeStatReseed(npcID)
    npcID = tonumber(npcID)
    if not npcID then return end
    pendingRuntimeStatNpcIds[npcID] = GetTime()
end

--- Reseed Statistics for recently killed NPCs only (not the full CollectibleSourceDB scan).
---@return boolean didWork
function Fns.ReseedStatisticsForPendingRuntimeNpcs()
    Fns.PurgeStaleRuntimeStatReseedNpcs()
    if not next(pendingRuntimeStatNpcIds) then return false end
    if not GetStatistic or not Fns.EnsureDB() then return false end

    Fns.EnsureMergedStatisticSeedIndex()

    wipe(runtimeStatReseedDropScratch)
    local drops = runtimeStatReseedDropScratch
    local dropCount = 0
    for npcID in pairs(pendingRuntimeStatNpcIds) do
        local npcData = npcDropDB and npcDropDB[npcID]
        if npcData then
            for idx = 1, #npcData do
                local drop = npcData[idx]
                if type(drop) == "table" and drop.type and drop.itemID then
                    dropCount = dropCount + 1
                    drops[dropCount] = drop
                end
            end
        end
    end
    for i = dropCount + 1, #drops do
        drops[i] = nil
    end
    if dropCount == 0 then
        wipe(pendingRuntimeStatNpcIds)
        return false
    end

    Fns.ReseedStatisticsForDrops(drops, nil)
    wipe(pendingRuntimeStatNpcIds)
    return true
end

function Fns.RequestTryCounterStatisticsIncrementalRefresh()
    if not GetStatistic then return end
    Fns.PurgeStaleRuntimeStatReseedNpcs()
    if not next(pendingRuntimeStatNpcIds) then return end
    statIncrementalDebounceSerial = statIncrementalDebounceSerial + 1
    local token = statIncrementalDebounceSerial
    C_Timer.After(STAT_INCREMENTAL_DEBOUNCE_SEC, function()
        if token ~= statIncrementalDebounceSerial then return end
        if not tryCounterReady or not Fns.EnsureDB() then return end
        local now = GetTime()
        if (now - lastStatIncrementalReseedAt) < STAT_INCREMENTAL_MIN_INTERVAL_SEC then return end
        lastStatIncrementalReseedAt = now
        Fns.ReseedStatisticsForPendingRuntimeNpcs()
        Fns.ScheduleDeferredRarityMountMaxSync(2)
    end)
end

--- Legacy name: encounter/loot paths mark pending NPCs then call incremental refresh.
function Fns.RequestTryCounterStatisticsRuntimeRefresh()
    Fns.RequestTryCounterStatisticsIncrementalRefresh()
end

local function HasPersistedTryCountEntries()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return false end
    local tc = WarbandNexus.db.global.tryCounts
    if type(tc) ~= "table" then return false end
    for _, bucket in pairs({ "mount", "pet", "item", "toy" }) do
        local tbl = tc[bucket]
        if type(tbl) == "table" and next(tbl) ~= nil then
            return true
        end
    end
    return false
end

function Fns.SchedulePerCharacterStatisticsAndRaritySync()
    local dbGlobal = WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
    local charKey = StatisticSnapshotStorageKey()
    local DF = ns.DataFreshness
    if DF and DF.IsTryCounterStatisticsWarm and dbGlobal and charKey
        and DF.IsTryCounterStatisticsWarm(dbGlobal, charKey) then
        return
    end
    perCharStatSyncSerial = perCharStatSyncSerial + 1
    local serial = perCharStatSyncSerial
    local function runSeed(pruneOrphans)
        if serial ~= perCharStatSyncSerial then return end
        if not tryCounterReady or not Fns.EnsureDB() then return end
        Fns.InvalidateMergedStatisticSeedIndex()
        Fns.SeedFromStatistics({ pruneOrphans = pruneOrphans == true })
    end
    local skipQuick = ns._wnPlayerReloading == true and HasPersistedTryCountEntries()
    if not skipQuick then
        C_Timer.After(PER_CHAR_STAT_SYNC_QUICK_SEC, function() runSeed(false) end)
    end
    C_Timer.After(PER_CHAR_STAT_SYNC_FULL_SEC, function() runSeed(true) end)
    C_Timer.After(PER_CHAR_STAT_RARITY_SEC, function()
        if serial ~= perCharStatSyncSerial then return end
        if WarbandNexus.SyncRarityMountAttemptsMax then
            WarbandNexus:SyncRarityMountAttemptsMax()
        end
    end)
end

--- Force Statistics re-read for the logged-in character (slash / alt refresh).
function WarbandNexus:ForceTryCounterStatisticsSync()
    if not tryCounterReady then
        if self.Print then
            self:Print("|cffff6600[WN]|r Try counter not ready yet.")
        end
        return
    end
    if not Fns.EnsureDB() then return end
    Fns.InvalidateMergedStatisticSeedIndex()
    Fns.SeedFromStatistics({ pruneOrphans = true })
    Fns.ScheduleDeferredRarityMountMaxSync(2)
    if self.Print then
        self:Print("|cff9370DB[WN]|r Statistics sync started for this character.")
    end
end

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

--- Rebuild runtime DB from CollectibleSourceDB + trackDB overlays.
--- Clears caches, re-loads DB references, merges custom/disabled, rebuilds indices.
function WarbandNexus:RebuildTrackDB()
    -- Reset reverse indices so they get rebuilt
    reverseIndicesBuilt = false
    wipe(npcIDToEncounterID)
    wipe(chatLootItemUniqueNpc)
    wipe(recentKillByNpcID)
    guaranteedIndex = {}
    repeatableIndex = {}
    dropSourceIndex = {}
    dropDifficultyIndex = {}
    wipe(repeatableItemDrops)
    difficultyCache = {}

    -- Re-load from static CollectibleSourceDB (typed sources already materialized there)
    Fns.LoadRuntimeSourceTables()

    -- Apply custom entries + disabled entries
    Fns.MergeTrackDB()

    -- Rebuild O(1) lookup indices
    Fns.BuildReverseIndices()
    Fns.InvalidateMergedStatisticSeedIndex()
    Fns.EnsureMergedStatisticSeedIndex()
end

-- INITIALIZATION

---Initialize the automatic try counter system
function WarbandNexus:InitializeTryCounter()
    if tryCounterReady or tryCounterInitializing then return end
    if self and self.db and self.db.profile and self.db.profile.modulesEnabled
        and self.db.profile.modulesEnabled.tryCounter == false then
        return
    end
    tryCounterInitializing = true
    local ok, err = xpcall(function()
    Fns.EnsureDB()

    -- Load DB references (initial load from static CollectibleSourceDB)
    Fns.LoadRuntimeSourceTables()

    -- Merge user-defined custom entries and remove disabled entries
    -- BEFORE building reverse indices so custom items are queryable.
    Fns.MergeTrackDB()

    -- Set V.lastContainerItemID before LOOT_OPENED: hook UseContainerItem so we know which
    -- container was opened even when LOOT_OPENED fires before ITEM_LOCK_CHANGED (e.g. Pinnacle Cache).
    if not self.useContainerItemHooked and _G.UseContainerItem and C_Container and C_Container.GetContainerItemID then
        local hookSelf = self
        local ok = pcall(function()
            hookSelf:RawHook("UseContainerItem", function(bagID, slotIndex)
                if bagID and slotIndex then
                    local safeBag = not (issecretvalue and issecretvalue(bagID)) and bagID or nil
                    local safeSlot = not (issecretvalue and issecretvalue(slotIndex)) and slotIndex or nil
                    if safeBag and safeSlot and safeBag >= 0 and safeBag <= 4 then
                        local itemID = C_Container.GetContainerItemID(safeBag, safeSlot)
                        if itemID and not (issecretvalue and issecretvalue(itemID)) and containerDropDB[itemID] then
                            V.lastContainerItemID = itemID
                            V.lastContainerItemTime = GetTime()
                        end
                    end
                end
                local orig = hookSelf.hooks["UseContainerItem"]
                if orig then return orig(bagID, slotIndex) end
            end)
        end)
        if ok then self.useContainerItemHooked = true end
    end

    -- Build reverse lookup indices for O(1) Is*Collectible() queries.
    -- Must run AFTER DB references are loaded and trackDB is merged.
    Fns.BuildReverseIndices()

    local dbGlobal = self.db and self.db.global
    local charKey = StatisticSnapshotStorageKey()
    local DF = ns.DataFreshness
    local statsWarm = DF and DF.IsTryCounterStatisticsWarm and dbGlobal and charKey
        and DF.IsTryCounterStatisticsWarm(dbGlobal, charKey)

    if not statsWarm then
        Fns.InvalidateMergedStatisticSeedIndex()
        Fns.EnsureMergedStatisticSeedIndex()
    else
        mergedStatSeedIndexDirty = true
    end

    -- Merge previously discovered lockout quests from SavedVariables
    Fns.MergeDiscoveredLockoutQuests()

    -- Sync lockout state with server quest flags (prevents false increments after /reload mid-farm)
    Fns.SyncLockoutState()
    lastLockoutSyncAt = GetTime() or 0

    -- Pre-resolve mount/pet IDs for all known drop items (warmup cache for SeedFromStatistics)
    -- Delayed 5s (absolute ~T+6.5s). Time-budgeted to prevent frame spikes.
    -- Skip when statistics snapshots already warm — event path resolves on demand.
    if not statsWarm then
    C_Timer.After(5, function()
        local RESOLVE_BUDGET_MS = 3
        local resolveQueue = {}
        for _, npcData in pairs(npcDropDB) do
            if Fns.NpcEntryHasStatisticIds(npcData) then
                for j = 1, #npcData do
                    local drop = npcData[j]
                    if type(drop) == "table" and drop.itemID and not resolvedIDs[drop.itemID] then
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
                local rid = Fns.ResolveCollectibleID(resolveQueue[idx])
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
    end

    -- Per-character Statistics seed + Rarity max overlay (PLAYER_ENTERING_WORLD also schedules on alt/reload).
    -- Quick pass T+1s, full pass T+8s (after pre-resolve ~T+5s warms mount/pet IDs).
    Fns.SchedulePerCharacterStatisticsAndRaritySync()
    local kSched = StatisticSnapshotStorageKey()
    if kSched then
        lastSyncScheduleCharKey = kSched
    end

    -- Sync lockout state with server quest flags (clean stale + pre-populate).
    -- Delayed 2s to ensure quest log data is available after login/reload.
    -- Also refreshes discovery snapshot so auto-discovery has a clean baseline.
    C_Timer.After(2, function()
        local now = GetTime() or 0
        if now - (lastLockoutSyncAt or 0) >= 1.5 then
            Fns.SyncLockoutState()
            lastLockoutSyncAt = now
        end
        Fns.TakeDiscoverySnapshot()
    end)

    -- Ensure events are registered (at load if allowed; retry here if load was in protected context).
    Fns.RegisterTryCounterEvents()
    tryCounterReady = true

    -- WN_COLLECTIBLE_OBTAINED: Handled by unified dispatch in NotificationManager.
    -- Do NOT register here — AceEvent allows only one handler per event per object.
    -- The dispatch handler in NotificationManager calls OnTryCounterCollectibleObtained.

    -- Periodic cleanup of stale GUIDs and kills (every 60s, batched)
    C_Timer.NewTicker(CLEANUP_INTERVAL, function()
        if not next(processedGUIDs) and not next(recentKills) and not next(mergedLootTryCountedAt) then
            return
        end
        local now = GetTime()
        for guid, time in pairs(processedGUIDs) do
            if now - time > PROCESSED_GUID_TTL then
                processedGUIDs[guid] = nil
                -- Evict from GUID parse caches so memory doesn't grow unbounded across long sessions.
                guidNpcIDCache[guid] = nil
                guidObjectIDCache[guid] = nil
            end
        end
        for guid, data in pairs(recentKills) do
            -- Encounter kills persist until instance exit (cleaned by OnTryCounterInstanceEntry)
            if not data.isEncounter and now - data.time > RECENT_KILL_TTL then
                recentKills[guid] = nil
                guidNpcIDCache[guid] = nil
                guidObjectIDCache[guid] = nil
            end
        end
        for fp, ts in pairs(mergedLootTryCountedAt) do
            if now - ts > MERGED_LOOT_TRY_DEDUP_TTL + 120 then
                mergedLootTryCountedAt[fp] = nil
            end
        end
    end)

    end, function(e)
        return tostring(e)
    end)

    tryCounterInitializing = false
    if not ok then
        ns.DebugPrint("|cffff4444[WN-TC]|r InitializeTryCounter failed: " .. tostring(err))
    end
end

---Debug: list merged Statistics-ID buckets for mounts (cross-difficulty / cross-NPC merge). Requires profile.debugMode.
function WarbandNexus:TryCounterAuditMountStatisticBuckets()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then
        if self.Print then
            self:Print("|cffff6600[WN]|r Enable debug first: |cff00ccff/wn debug|r")
        end
        return
    end
    if not tryCounterReady then
        if self.Print then
            self:Print("|cffff6600[WN]|r Try counter not ready yet.")
        end
        return
    end
    Fns.EnsureMergedStatisticSeedIndex()
    local n = 0
    local multi = 0
    for i = 1, #mergedStatSeedGroupList do
        local b = mergedStatSeedGroupList[i]
        if b.tcType == "mount" then
            n = n + 1
            local sidc = b.statIds and #b.statIds or 0
            if sidc > 1 then
                multi = multi + 1
            end
            local name = (b.drops[1] and b.drops[1].name) or "?"
            if self.Print then
                self:Print(format(
                    "  |cffffd100mount|r key=%s |cff888888statIds=%d drops=%d|r %s",
                    tostring(b.tryKey), sidc, b.drops and #b.drops or 0, name
                ))
            end
        end
    end
    if self.Print then
        self:Print(format("|cff9370DB[WN]|r Mount statistic buckets: |cffffffff%d|r (multi-column merge: |cffffffff%d|r)", n, multi))
    end
end

-- DEBUG: Try counter state simulation (/wn trydebug)

---Print current try-counter state to chat (instance, difficulty, loot sources, target, recentKills, zone, Statistics).
---Uses guarded APIs; secret values are shown as "(secret)". Call from /wn trydebug when debug mode is on.
function WarbandNexus:TryCounterDebugReport()
    local WN = self
    local function msg(s) Fns.TryChat("|cff9370DB[WN-TryDebug]|r " .. s) end
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
        if #sources == 0 then
            msg("  slot " .. slot .. ": (no GetLootSourceInfo)")
        else
            for k = 1, #sources, 2 do
                local guid = sources[k]
                local qty = sources[k + 1]
                local safeGuid = guid and Fns.SafeGuardGUID(guid) or nil
                local guidStr = safeStr(guid)
                local pairLabel = (#sources > 2) and (" pair " .. ((k + 1) / 2)) or ""
                if safeGuid then
                    local nid = Fns.GetNPCIDFromGUID(safeGuid)
                    local oid = Fns.GetObjectIDFromGUID(safeGuid)
                    local inNpc = nid and npcDropDB[nid] and "yes" or "no"
                    local inObj = oid and objectDropDB[oid] and "yes" or "no"
                    msg("  slot " .. slot .. pairLabel .. ": guid=" .. guidStr .. " qty=" .. safeStr(qty)
                        .. " npcID=" .. safeStr(nid) .. " inNpcDB=" .. inNpc .. " objectID=" .. safeStr(oid) .. " inObjDB=" .. inObj)
                else
                    msg("  slot " .. slot .. pairLabel .. ": guid=" .. guidStr .. " qty=" .. safeStr(qty))
                end
            end
        end
    end

    -- 4. Target (never call UnitGUID("target") raw — may be secret in instances)
    local safeTg = Fns.SafeGetUnitGUID("target")
    msg("Target GUID: " .. safeStr(safeTg))
    if safeTg then
        local nid = Fns.GetNPCIDFromGUID(safeTg)
        local oid = Fns.GetObjectIDFromGUID(safeTg)
        msg("  npcID=" .. safeStr(nid) .. " inNpcDB=" .. (nid and npcDropDB[nid] and "yes" or "no") .. " objectID=" .. safeStr(oid) .. " inObjDB=" .. (oid and objectDropDB[oid] and "yes" or "no"))
    end

    -- 5. recentKills (sample)
    local count = 0
    for guid, data in pairs(recentKills) do
        if count >= 2 then break end
        count = count + 1
        local diffStr = data.difficultyID
        if issecretvalue and diffStr and issecretvalue(diffStr) then diffStr = "(secret)" end
        if diffStr == nil then diffStr = "nil" elseif diffStr ~= "(secret)" then diffStr = tostring(diffStr) end
        msg("recentKills sample: npcID=" .. tostring(data.npcID) .. " isEncounter=" .. tostring(data.isEncounter) .. " difficultyID=" .. diffStr)
    end
    if count == 0 then msg("recentKills: (empty)") end

    -- 6. Map / zone (guard mapID for 12.0)
    local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = (rawMapID and not (issecretvalue and issecretvalue(rawMapID))) and rawMapID or nil
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
    for i = 1, #sampleStatIds do
        local sid = sampleStatIds[i]
        local val = GetStatistic(sid)
        local display = "(secret)"
        if not (issecretvalue and val and issecretvalue(val)) then
            display = tostring(val)
        end
        msg("GetStatistic(" .. sid .. ")=" .. display)
    end
    if #sampleStatIds == 0 then msg("GetStatistic: (no sample stat IDs in DB)") end
end

-- CHECK TARGET DROPS (debug helper)

---Check what collectibles drop from current target or mouseover
---Prints detailed info about NPC/Object drops, encounter mapping, and collection status
function WarbandNexus:CheckTargetDrops()
    local function msg(text) self:Print("|cff9370DB[WN-DropCheck]|r " .. text) end
    if Fns.GetTryCounterDisabledReason() then
        Fns.PrintTryCounterDisabledHint(self)
    end
    local function safeStr(val)
        if val == nil then return "nil" end
        if issecretvalue and issecretvalue(val) then return "(secret)" end
        return tostring(val)
    end

    -- Try mouseover first, then target (use SafeGetUnitGUID to avoid secret values)
    local unit = "mouseover"
    local guid = Fns.SafeGetUnitGUID(unit)
    if not guid then
        unit = "target"
        guid = Fns.SafeGetUnitGUID(unit)
    end
    
    if not guid then
        msg("|cffff6600No valid target or mouseover unit found.|r")
        msg("Target an NPC or GameObject and try again.")
        msg("|cff888888(In instances, target GUIDs may be restricted)|r")
        return
    end
    
    -- Unit name: avoid (UnitName() or "Unknown") — secret return must not pass through `or` / tostring
    local rawUnitName = UnitName(unit)
    local unitName = "Unknown"
    if type(rawUnitName) == "string" and rawUnitName ~= ""
        and not (issecretvalue and issecretvalue(rawUnitName)) then
        unitName = rawUnitName
    end
    
    -- Check if it's an NPC or GameObject (GUID is already safe from SafeGetUnitGUID)
    local npcID = Fns.GetNPCIDFromGUID(guid)
    local objectID = Fns.GetObjectIDFromGUID(guid)
    
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
                for j = 1, #npcList do
                    local nid = npcList[j]
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

-- LEGACY MOUNT TRACKER IMPORT (optional cross-addon merge)
-- Reads a third-party addon global (AceDB profile.groups.mounts); only mount rows with attempts > 0.
-- Try keys: mount journal ID from C_MountJournal.GetMountFromItem(itemId), else itemId.

local LEGACY_MOUNT_TRACKER_GLOBAL = "Ra" .. "rity"

function Fns.ResolveMountTryKeyFromItemId(itemId)
    if C_MountJournal and C_MountJournal.GetMountFromItem then
        local m = C_MountJournal.GetMountFromItem(itemId)
        if m and not (issecretvalue and issecretvalue(m)) then
            local n = tonumber(m)
            if n and n > 0 then
                return n
            end
        end
    end
    return itemId
end

function Fns.ApplyRarityMountAttemptsMaxToWN(self, itemId, extAttempts)
    if not itemId or itemId < 1 or not extAttempts or extAttempts < 1 then
        return false
    end
    local mountKey = Fns.ResolveMountTryKeyFromItemId(itemId)
    -- Non-repeatable mounts: after collection, WN count is the frozen "tries to obtain" value.
    -- Do not raise it from Rarity/backup merge (avoids post-drop inflation when Rarity kept counting).
    local probeDrop = { type = "mount", itemID = itemId }
    if not self:IsRepeatableCollectible("mount", mountKey)
        and not self:IsRepeatableCollectible("mount", itemId)
        and Fns.IsCollectibleCollected(probeDrop) then
        return false
    end
    local wnA = self:GetTryCount("mount", mountKey) or 0
    local wnB = (mountKey ~= itemId) and (self:GetTryCount("mount", itemId) or 0) or 0
    local base = wnA
    if wnB > base then
        base = wnB
    end
    local total = base
    if extAttempts > total then
        total = extAttempts
    end
    if total > base then
        self:SetTryCount("mount", mountKey, total)
        if mountKey ~= itemId then
            self:SetTryCount("mount", itemId, total)
        end
        return true
    end
    return false
end

function Fns.MergeRarityProfileMountsIntoWnBackup(mounts)
    if not Fns.EnsureDB() or type(mounts) ~= "table" then
        return
    end
    local tc = WarbandNexus.db.global.tryCounts
    if not tc.rarityImportBackup then
        tc.rarityImportBackup = {}
    end
    local b = tc.rarityImportBackup
    for key, entry in pairs(mounts) do
        if type(entry) == "table" and type(key) == "string" and key ~= "name" and entry.enabled ~= false then
            local itemId = tonumber(entry.itemId) or tonumber(entry.itemID)
            local attempts = tonumber(entry.attempts) or 0
            if itemId and itemId > 0 and attempts > 0 then
                b[itemId] = math.max(b[itemId] or 0, attempts)
            end
        end
    end
    tc.rarityImportBackupAt = time()
end

--- Re-apply stored backup (no Rarity addon required). Safe to run after Rarity is removed.
---@return number updated
---@return number scanned
function WarbandNexus:RestoreRarityImportBackup()
    if not Fns.EnsureDB() then
        return 0, 0
    end
    local b = WarbandNexus.db.global.tryCounts.rarityImportBackup
    if type(b) ~= "table" then
        return 0, 0
    end
    if ns.EnsureBlizzardCollectionsLoaded then
        ns.EnsureBlizzardCollectionsLoaded()
    end
    local updated = 0
    local scanned = 0
    for itemIdRaw, attRaw in pairs(b) do
        local itemId = tonumber(itemIdRaw)
        local attempts = tonumber(attRaw)
        if itemId and itemId > 0 and attempts and attempts > 0 then
            scanned = scanned + 1
            if Fns.ApplyRarityMountAttemptsMaxToWN(self, itemId, attempts) then
                updated = updated + 1
            end
        end
    end
    if updated > 0 and self.SendMessage then
        self:SendMessage(E.PLANS_UPDATED, { action = "legacy_mount_tracker_import" })
    end
    return updated, scanned
end

--- One-time handoff: try to load Rarity, merge several times (late AceDB init), refresh backup each successful read.
function WarbandNexus:ImportRarityMountHandoff()
    if not Fns.EnsureDB() then
        return
    end
    if InCombatLockdown() then
        self:Print("|cffff6600[WN]|r Exit combat, then run Rarity handoff again from Warband Nexus → Settings → Try Counter.")
        return
    end
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Rarity")
    end

    local delays = { 0.2, 1.0, 3.0, 8.0 }
    local pass = 0
    for i = 1, #delays do
        C_Timer.After(delays[i], function()
            if not Fns.EnsureDB() then
                return
            end
            WarbandNexus:SyncRarityMountAttemptsMax()
            pass = pass + 1
            if pass == #delays then
                -- Re-apply saved backup so mount journal / keys are consistent even if earlier passes were cold.
                WarbandNexus:RestoreRarityImportBackup()
                local bn = 0
                local bk = WarbandNexus.db.global.tryCounts.rarityImportBackup
                if type(bk) == "table" then
                    for _ in pairs(bk) do
                        bn = bn + 1
                    end
                end
                if bn > 0 then
                    self:Print(string.format(
                        "|cff00ff00[WN]|r Rarity handoff complete. |cffffffff%d|r mount itemID(s) copied into WN backup + try counts (max). You can disable Rarity. If a count looks wrong: use Restore from backup in Try Counter settings.|r",
                        bn
                    ))
                else
                    self:Print("|cffff6600[WN]|r No Rarity mount data found. Enable the |cffffcc00Rarity|r addon in Esc → AddOns, |cff00ccff/reload|r, then run Rarity handoff from Try Counter settings.|r")
                end
            end
        end)
    end
    self:Print("|cff9370DB[WN]|r Rarity import running (multiple passes). Wait ~8s for the summary line.|r")
end

--- Merge Rarity (or same-shape tracker) mount attempts using **max**, not sum — same boss kills as Statistics/Rarity must not double-count.
--- Runs on every schedule pass (login / alt / reload) so profile stays aligned with WN try counts.
--- On every successful read, merges into db.global.tryCounts.rarityImportBackup for offline restore.
---@return number updated rows touched
---@return number scanned rows with attempts > 0
function WarbandNexus:SyncRarityMountAttemptsMax()
    if not Fns.EnsureDB() then
        return 0, 0
    end

    local Ext = rawget(_G, LEGACY_MOUNT_TRACKER_GLOBAL)
    if not Ext or type(Ext) ~= "table" or not Ext.db or not Ext.db.profile or type(Ext.db.profile.groups) ~= "table" then
        return 0, 0
    end
    if ns.EnsureBlizzardCollectionsLoaded then
        ns.EnsureBlizzardCollectionsLoaded()
    end

    local mounts = Ext.db.profile.groups.mounts
    if type(mounts) ~= "table" then
        return 0, 0
    end

    local updated = 0
    local scanned = 0

    for key, entry in pairs(mounts) do
        if type(entry) == "table" and type(key) == "string" and key ~= "name" then
            if entry.enabled ~= false then
                local itemId = tonumber(entry.itemId) or tonumber(entry.itemID)
                local attempts = tonumber(entry.attempts) or 0
                if itemId and itemId > 0 and attempts > 0 then
                    scanned = scanned + 1
                    if Fns.ApplyRarityMountAttemptsMaxToWN(self, itemId, attempts) then
                        updated = updated + 1
                    end
                end
            end
        end
    end

    if scanned > 0 then
        Fns.MergeRarityProfileMountsIntoWnBackup(mounts)
        local tc = WarbandNexus.db.global.tryCounts
        tc.legacyMountTrackerSeedComplete = true
    end

    if updated > 0 and self.SendMessage then
        self:SendMessage(E.PLANS_UPDATED, { action = "legacy_mount_tracker_import" })
    end

    return updated, scanned
end

---@deprecated Use SyncRarityMountAttemptsMax; kept for API compatibility.
function WarbandNexus:ImportLegacyMountTrackerAttempts()
    return self:SyncRarityMountAttemptsMax()
end

function WarbandNexus:DebugResetLegacyMountTrackerSeed()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then
        self:Print("|cffff6600[WN]|r Enable debug mode first (/wn debug).")
        return
    end
    if not Fns.EnsureDB() then
        return
    end
    WarbandNexus.db.global.tryCounts.legacyMountTrackerSeedComplete = false
    self:Print("|cff00ff00[WN]|r Seed flag cleared (informational). Rarity merge does not use this flag — with Rarity enabled, wait for post-login sync or trigger merge from Try Counter settings.")
end

function WarbandNexus:DebugLegacyMountTrackerImportPreview()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then
        self:Print("|cffff6600[WN]|r Enable debug mode first (/wn debug).")
        return
    end
    local Ext = rawget(_G, LEGACY_MOUNT_TRACKER_GLOBAL)
    if not Ext or not Ext.db or not Ext.db.profile or type(Ext.db.profile.groups) ~= "table" then
        self:Print("|cffff6600[WN]|r Legacy mount tracker not loaded.")
        return
    end
    if ns.EnsureBlizzardCollectionsLoaded then
        ns.EnsureBlizzardCollectionsLoaded()
    end
    local mounts = Ext.db.profile.groups.mounts
    if type(mounts) ~= "table" then
        self:Print("|cffff6600[WN]|r No groups.mounts in tracker profile.")
        return
    end
    local seedDone = WarbandNexus.db.global.tryCounts and WarbandNexus.db.global.tryCounts.legacyMountTrackerSeedComplete
    self:Print("|cff9370DB[WN]|r Mount tracker preview | seed done: " .. tostring(seedDone == true) .. " | itemID → mountKey | ext | WN")
    local n = 0
    for key, entry in pairs(mounts) do
        if type(entry) == "table" and type(key) == "string" and key ~= "name" and entry.enabled ~= false then
            local itemId = tonumber(entry.itemId) or tonumber(entry.itemID)
            local attempts = tonumber(entry.attempts) or 0
            if itemId and itemId > 0 and attempts > 0 then
                n = n + 1
                if n <= 40 then
                    local mk = Fns.ResolveMountTryKeyFromItemId(itemId)
                    local wMk = self:GetTryCount("mount", mk)
                    local wItem = (mk ~= itemId) and self:GetTryCount("mount", itemId) or wMk
                    self:Print(format(
                        "  |cffffd100%s|r | item=%d key=%d | ext=%d | WN(key)=%d | WN(item)=%d",
                        key, itemId, mk, attempts, wMk, wItem
                    ))
                end
            end
        end
    end
    if n > 40 then
        self:Print(format("|cff888888... +%d rows (cap 40)|r", n - 40))
    end
    self:Print(format("|cff9370DB[WN]|r Mount rows with attempts: %d", n))
end

-- NAMESPACE EXPORT

--- Called from DatabaseCleanup (delayed) to drop snapshot rows for removed characters.
function WarbandNexus:PruneOrphanStatisticSnapshots()
    Fns.PruneStatisticSnapshotsOrphanKeys()
end

ns.TryCounterService = {
    GetTryCount = function(_, ct, id) return WarbandNexus:GetTryCount(ct, id) end,
    SetTryCount = function(_, ct, id, c) return WarbandNexus:SetTryCount(ct, id, c) end,
    IncrementTryCount = function(_, ct, id) return WarbandNexus:IncrementTryCount(ct, id) end,
    ResetTryCount = function(_, ct, id) return WarbandNexus:ResetTryCount(ct, id) end,
    IsGuaranteedCollectible = function(_, ct, id) return WarbandNexus:IsGuaranteedCollectible(ct, id) end,
    IsRepeatableCollectible = function(_, ct, id) return WarbandNexus:IsRepeatableCollectible(ct, id) end,
    IsDropSourceCollectible = function(_, ct, id) return WarbandNexus:IsDropSourceCollectible(ct, id) end,
    ShouldShowTryCountInUI = function(_, ct, id) return WarbandNexus:ShouldShowTryCountInUI(ct, id) end,
    -- CRUD API for Track Item DB
    AddCustomDrop = function(_, st, sid, drop, stats) return WarbandNexus:AddCustomDrop(st, sid, drop, stats) end,
    RemoveCustomDrop = function(_, st, sid, iid) return WarbandNexus:RemoveCustomDrop(st, sid, iid) end,
    SetBuiltinTracked = function(_, st, sid, iid, t) return WarbandNexus:SetBuiltinTracked(st, sid, iid, t) end,
    IsBuiltinTracked = function(_, st, sid, iid) return WarbandNexus:IsBuiltinTracked(st, sid, iid) end,
    SetBuiltinRepeatable = function(_, ct, iid, r) return WarbandNexus:SetBuiltinRepeatable(ct, iid, r) end,
    GetRepeatableOverride = function(_, ct, iid) return WarbandNexus:GetRepeatableOverride(ct, iid) end,
    LookupItem = function(_, iid, cb) return WarbandNexus:LookupItem(iid, cb) end,
    RebuildTrackDB = function() return WarbandNexus:RebuildTrackDB() end,
    ImportLegacyMountTrackerAttempts = function() return WarbandNexus:ImportLegacyMountTrackerAttempts() end,
    SyncRarityMountAttemptsMax = function() return WarbandNexus:SyncRarityMountAttemptsMax() end,
    ImportRarityMountHandoff = function() return WarbandNexus:ImportRarityMountHandoff() end,
    RestoreRarityImportBackup = function() return WarbandNexus:RestoreRarityImportBackup() end,
    TryCounterAuditMountStatisticBuckets = function() return WarbandNexus:TryCounterAuditMountStatisticBuckets() end,
}

TC.Fns = Fns

end)()
