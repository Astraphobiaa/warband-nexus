--[[
    Warband Nexus - Try Counter Service
    Classify-Lock-Process loot pipeline: one route per session (SKIP/CONTAINER/FISHING/NPC-OBJECT).
    Sources: CollectibleSourceDB + trackDB overlays; db.global.tryCounts[type][id].
    Found drop resets count; raid/dungeon miss from GetStatistic on ENCOUNTER_END (loot not required).
    Midnight 12.0.x: issecretvalue on ENCOUNTER_*/GetLootSourceInfo/UnitGUID/CHAT_MSG_LOOT; no CLEU.
    ProcessNPCLoot resolver P1->P5; ENCOUNTER_END + CHAT_MSG_LOOT debounced fallbacks.
    Events: LOOT_*, CHAT_MSG_LOOT, ENCOUNTER_*, BOSS_KILL, spellcast/fishing hooks, ITEM_LOCK_CHANGED.

    WN_NONUI_UI: `tryCounterFrame` (near RAW EVENT FRAMES) is an AceEvent-only host (`CreateFrame`); owns no Visible UI chrome.
    LuaLS: retain ---@ on WarbandNexus: export surface only; IIFE locals stay comment-only.
    Split (2026-10-22, chunk local budget + 4000-line rule): TryCounterService_Debug / _Import /
    _LootSession / _Outcomes / _Lockout / _Difficulty / _Instance / _TrackDB load right after this file
    and share state through ns.TryCounter.Runtime (RT / RT.vars) + TC.Fns.
]]

local ADDON_NAME, ns = ...

-- 12.1.5 removed the global item/coin fallbacks; bind the namespaced APIs.
local GetItemInfo = C_Item.GetItemInfo

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
RT.statState = RT.statState or {
    indexDirty = true,
    perCharStatSyncSerial = 0,
    statIncrementalDebounceSerial = 0,
    encounterStatRetrySerial = 0,
    lastStatIncrementalReseedAt = 0,
}
RT.tryCounterSelfTest = RT.tryCounterSelfTest or { slotInstance = nil }

-- CONSTANTS & UPVALUES (performance: resolved once at file load)

local VALID_TYPES = TC.VALID_TYPES or { mount = true, pet = true, toy = true, illusion = true, item = true }
local RECENT_KILL_TTL = TC.RECENT_KILL_TTL or 15
local PROCESSED_GUID_TTL = TC.PROCESSED_GUID_TTL or 300
local MERGED_LOOT_TRY_DEDUP_TTL = TC.MERGED_LOOT_TRY_DEDUP_TTL or 600
local CLEANUP_INTERVAL = TC.CLEANUP_INTERVAL or 60
local GUID_PARSE_CACHE_MAX = TC.GUID_PARSE_CACHE_MAX or 512

-- Forward declaration: fishingCtx is defined (assigned) further below, but Fns helpers
-- such as Fns.LootSessionHasFishingEvidence (defined earlier in this chunk) reference it.
-- Lua 5.1 resolves upvalues by lexical position, so it must be declared before those callers
-- or it falls back to a nil global (crash on fishing loot).
local fishingCtx
-- Same trap: the GUID parse caches are assigned below but trimmed from here.
local guidNpcIDCache, guidObjectIDCache

local function TrimGuidParseCachesIfOversized()
    local function trim(cache)
        if not cache then return end
        local n = 0
        for _ in pairs(cache) do
            n = n + 1
            if n > GUID_PARSE_CACHE_MAX then
                wipe(cache)
                return
            end
        end
    end
    trim(guidNpcIDCache)
    trim(guidObjectIDCache)
end
-- Removed 8 declaration-only locals here (three Sylvanas/raid constants read straight from TC
-- at their real call sites, strfind/tconcat aliases nothing used, and three debug scalars left
-- behind by a earlier refactor). This chunk is the tightest in the addon: 200 simultaneously
-- active locals is a hard load failure, and dead slots were spending that budget for nothing.
RT.ENCOUNTER_OBJECT_TTL = TC.ENCOUNTER_OBJECT_TTL or 300

Fns.TryChat = TC.TryChat
Fns.BuildObtainedChat = TC.BuildObtainedChat

-- Upvalue WoW API functions (avoid global lookups in hot paths)
local GetNumLootItems = GetNumLootItems
local GetLootSlotLink = GetLootSlotLink
local LootSlotHasItem = LootSlotHasItem
local GetTime = GetTime
local strsplit = strsplit
local tonumber = tonumber
local pairs = pairs
local format = string.format
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local PlayerHasToy = PlayerHasToy
local C_Timer = C_Timer
local C_Container = C_Container
local IsInInstance = IsInInstance

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
guidNpcIDCache = {}
guidObjectIDCache = {}

-- Forward declarations for state variables used in OnEvent closure (declared after it)
local npcDropDB
local tryCounterNpcEligible
local objectDropDB
V.discoveryPendingNpcID = nil
V.discoveryPendingTime = 0 -- GetTime() when pending was set (ScheduleLockoutDiscovery; read by TryDiscoverLockoutQuest)
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
---When true, InitializeTryCounter skips deferred instance-entry announce (PEW handler runs it in the same tick).
local tryCounterSkipPostInitInstanceEntry = false
local tryCounterEventsRegistered = false
local tryCounterFrame = CreateFrame("Frame")
local DEBUG_TRACE_EVENTS = TC.DEBUG_TRACE_EVENTS or {}

-- MUST be declared before tryCounterFrame:SetScript("OnEvent") — otherwise the closure resolves globals (nil).
local DEBUG_TRACE_DEDUP_LOOT_MS = 0.22
local lastDebugTraceLootTime = { LOOT_READY = 0 }
RT.pendingRuntimeStatNpcIds = {} -- [npcID] = { at, difficultyID? } encounter stat reseed queue
RT.STAT_INCREMENTAL_DEBOUNCE_SEC = 1.5
RT.STAT_INCREMENTAL_MIN_INTERVAL_SEC = 10
RT.ENCOUNTER_STAT_RETRY_DELAYS = { 0, 0.5, 1.5, 3, 6, 12 }

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
        -- UNIT_SPELLCAST_*: every handler drops units other than "player". RegisterUnitEvent filters
        -- in the client instead of firing for every party / raid / nameplate cast (2026-10-22).
        local ok, err
        if ev:sub(1, 15) == "UNIT_SPELLCAST_" and tryCounterFrame.RegisterUnitEvent then
            ok, err = pcall(tryCounterFrame.RegisterUnitEvent, tryCounterFrame, ev, "player")
        else
            ok, err = pcall(tryCounterFrame.RegisterEvent, tryCounterFrame, ev)
        end
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

local function TryCounterIsPartyOrRaidInstance()
    local inI, it = IsInInstance()
    if issecretvalue and inI and issecretvalue(inI) then return false end
    if not inI then return false end
    if issecretvalue and it and issecretvalue(it) then it = nil end
    return it == "party" or it == "raid"
end

local function ScheduleTryCounterInstanceEntryIfInside()
    if not Fns.IsAutoTryCounterEnabled() then return end
    if not TryCounterIsPartyOrRaidInstance() then return end
    C_Timer.After(0.5, function()
        local WN = WarbandNexus
        if WN and WN.OnTryCounterInstanceEntry then
            WN:OnTryCounterInstanceEntry("PLAYER_ENTERING_WORLD", false, false)
        end
    end)
end

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
    -- Early-session bootstrap: loot/fishing/instance entry can happen before scheduled init
    -- (InitializationService runs TryCounter at T+7.5s). Force init so PEW instance announce is not dropped.
    if not tryCounterReady then
        if addon and Fns.IsTryCounterModuleEnabled()
            and (event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_CHANNEL_START") then
            if event == "UNIT_SPELLCAST_SENT" then
                addon:OnTryCounterSpellcastSent(event, ...)
            else
                addon:OnTryCounterSpellcastChannelStart(event, ...)
            end
        end
        if addon and addon.InitializeTryCounter and not tryCounterInitializing then
            local bootstrap = (event == "LOOT_READY" or event == "LOOT_OPENED" or event == "CHAT_MSG_LOOT"
                or event == "ENCOUNTER_START" or event == "ENCOUNTER_END" or event == "BOSS_KILL")
            if not bootstrap and event == "PLAYER_ENTERING_WORLD" and TryCounterIsPartyOrRaidInstance() then
                bootstrap = true
                tryCounterSkipPostInitInstanceEntry = true
            end
            if bootstrap then
                addon:InitializeTryCounter()
                tryCounterSkipPostInitInstanceEntry = false
            end
        end
        if not tryCounterReady then return end
    end
    if not addon then return end
    -- Module off: these three only feed try counting (lockout quest sweep, loot-source target,
    -- statistic seed index) and had no gate of their own (2026-10-22).
    if (event == "QUEST_LOG_UPDATE" or event == "PLAYER_TARGET_CHANGED" or event == "PLAYER_REGEN_ENABLED")
        and not Fns.IsTryCounterModuleEnabled() then
        return
    end
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
            V.isBlockingInteractionOpen = true
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if interactionType and not (issecretvalue and issecretvalue(interactionType)) and BLOCKING_INTERACTION_TYPES[interactionType] then
            V.isBlockingInteractionOpen = false
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
                if nid then Fns.MaybeRefreshDiscoverySnapshotForNpc(nid) end
            end
        else
            RT.lastLootSourceGUID = nil
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if not (C_Timer and C_Timer.NewTimer) then
            if V.discoveryPendingNpcID then
                Fns.TryDiscoverLockoutQuest()
            end
            Fns.ProcessKnownLockoutQuestCompletions()
        else
            if questLogLockoutDebounceTimer then
                questLogLockoutDebounceTimer:Cancel()
            end
            questLogLockoutDebounceTimer = C_Timer.NewTimer(QUEST_LOG_LOCKOUT_DEBOUNCE_SEC, function()
                questLogLockoutDebounceTimer = nil
                if V.discoveryPendingNpcID then
                    Fns.TryDiscoverLockoutQuest()
                end
                Fns.ProcessKnownLockoutQuestCompletions()
            end)
        end
    elseif event == "CRITERIA_UPDATE" then
        -- CRITERIA_UPDATE has no payload and fires in bursts during quests/achievements.
        -- Only re-read Statistics for NPCs we recently killed (ENCOUNTER_END marks them).
        if next(RT.pendingRuntimeStatNpcIds) then
            Fns.RequestTryCounterStatisticsIncrementalRefresh()
        end
    elseif event == "PLAYER_REGEN_ENABLED" then
        if next(RT.pendingRuntimeStatNpcIds) then
            Fns.RequestTryCounterStatisticsIncrementalRefresh()
        end
        Fns.EnsureMergedStatisticSeedIndex()
    end
end)

-- ops-030: fishing + classify constants -> TryCounterService_Process.lua (mutable bobber table)
local FISHING_BOBBER_NPC_IDS = TC.FISHING_BOBBER_NPC_IDS or {}
local FISHING_BOBBER_OBJECT_IDS = TC.FISHING_BOBBER_OBJECT_IDS or {}

function Fns.IsFishingBobberNpcId(npcID)
    return npcID and FISHING_BOBBER_NPC_IDS[npcID] == true
end

--- The bobber / fishing hole is a GameObject (GAMEOBJECT_TYPE_FISHINGNODE 17, FISHINGHOLE 25),
--- so this is the id that actually appears in GetLootSourceInfo for live fishing loot.
function Fns.IsFishingBobberObjectId(objectID)
    return objectID and FISHING_BOBBER_OBJECT_IDS[objectID] == true
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
            -- A GameObject source is the normal shape for live fishing loot (the bobber is
            -- GAMEOBJECT_TYPE_FISHINGNODE). Only a LEARNED fishing-node id counts as evidence;
            -- an unknown GameObject is still ambiguous with herb/ore/chests and must not.
            local oid = Fns.GetObjectIDFromGUID(g)
            if oid and Fns.IsFishingBobberObjectId(oid) then
                knownBobber = true
            elseif oid and objectDropDB[oid] then
                return false   -- tracked object (dumpster, raid chest) owns its own route
            end
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
    -- Creature+GameObject without a known bobber is often mob loot near a world object (Midnight false tries).
    return false
end

function Fns.LootSessionHasKnownBobber(sourceGUIDs)
    for i = 1, #(sourceGUIDs or {}) do
        local g = sourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
            local nid = Fns.GetNPCIDFromGUID(g)
            if Fns.IsFishingBobberNpcId(nid) then
                return true
            end
        end
    end
    return false
end

--- Mob corpses that must block fishing classification (unknown lone creature may be an unlearned bobber).
function Fns.LootSessionHasBlockingMobCorpseForFishing(sourceGUIDs)
    if not sourceGUIDs or #sourceGUIDs == 0 then return false end
    local nonBobberCreatures = 0
    local hasGameObject = false
    for i = 1, #sourceGUIDs do
        local g = sourceGUIDs[i]
        if type(g) ~= "string" or (issecretvalue and issecretvalue(g)) then
            return false
        end
        if g:match("^GameObject") then
            hasGameObject = true
        elseif Fns.UnitGuidLooksLikeMobCorpse(g) then
            local nid = Fns.GetNPCIDFromGUID(g)
            if Fns.IsFishingBobberNpcId(nid) then
                -- known bobber — not a blocking corpse
            elseif nid and (tryCounterNpcEligible[nid] or npcDropDB[nid]) then
                return true
            else
                nonBobberCreatures = nonBobberCreatures + 1
            end
        end
    end
    if nonBobberCreatures > 1 then return true end
    if nonBobberCreatures == 1 and hasGameObject then return true end
    return false
end

function Fns.LootSessionHasFishingEvidence(sourceGUIDs)
    if V.isProfessionLooting then return false end
    if Fns.SafeIsFishingLoot() then return true end
    if Fns.LootSessionHasKnownBobber(sourceGUIDs) then return true end
    local now = GetTime()
    local castTTL = TC.FISHING_CAST_CONTEXT_TTL or 35
    if fishingCtx.active and fishingCtx.castTime and (now - fishingCtx.castTime) <= castTTL then
        return true
    end
    return false
end

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
RT.mergedStatSeedByTypeKey = {} -- [type .. "\0" .. key] = { tcType, tryKey, statIds, drops }
RT.mergedStatSeedGroupList = {} -- stable iteration order for SeedFromStatistics
RT.statSeedTryKeyPending = {}   -- drops with stat IDs but tryKey nil at seed time (API cold)
RT.statSeedWorkQueue = {}       -- reused by SeedFromStatistics (avoid per-seed allocations)
RT.runtimeStatReseedDropScratch = {}
RT.RUNTIME_STAT_NPC_TTL = 180

-- Runtime state
local recentKills = {}       -- [guid] = { npcID = n, name = s, time = t }
local recentKillByNpcID = {} -- [npcID] = { guid = string, killData = table }
local processedGUIDs = {}    -- [guid] = timestamp
local mergedLootTryCountedAt = {}  -- [fingerprint] = GetTime() — open-world merged loot, one wave per GUID set
RT.tryCounterInstanceDiffCache = { instanceID = nil, difficultyID = nil }
local currentEncounterCache = {
    encounterID = nil,          -- number|nil (non-secret, captured at start)
    encounterName = nil,        -- string|nil (non-secret)
    difficultyID = nil,         -- number|nil (non-secret, preferred over END's secret value)
    groupSize = nil,            -- number|nil
    startTime = 0,              -- GetTime() at ENCOUNTER_START
    instanceID = nil,           -- GetInstanceInfo()[8] snapshot for scope checks
    consumed = false,
}
RT.ENCOUNTER_CACHE_TTL = 1200  -- 20 minutes (covers long wipes, phase-heavy fights, AFK loot)
V.lastSyncScheduleCharKey = nil
RT.PER_CHAR_STAT_SYNC_QUICK_SEC = 1
RT.PER_CHAR_STAT_SYNC_FULL_SEC = 8
RT.PER_CHAR_STAT_RARITY_SEC = 12
V.lastDifficultySkipChatKey = nil
V.lastDifficultySkipChatTime = 0
RT.SKIP_CHAT_DEDUP_SEC = TC.SKIP_CHAT_DEDUP_SEC or 15
fishingCtx = {
    active = false,            -- set on fishing cast, cleared when fishing loot processed (or 30s timer)
    castTime = 0,              -- timestamp of last fishing cast
    lootWasFishing = false,    -- true after ProcessFishingLoot ran with trackable; LOOT_CLOSED only clears active then
    resetTimer = nil,          -- safety timer: auto-reset active after 30s (handles cancelled casts)
}
RT.FISHING_CAST_CONTEXT_TTL = TC.FISHING_CAST_CONTEXT_TTL or 35
V.isPickpocketing = false -- set on pickpocket cast, cleared on LOOT_CLOSED
V.isProfessionLooting = false -- set on profession spell cast, cleared on LOOT_CLOSED
V.isBlockingInteractionOpen = false -- true when bank/vendor/AH/mail/trade UI is open
V.lastContainerItemID = nil  -- set on container use
V.lastContainerItemTime = 0  -- timestamp when container use/lock was observed (for LOOT_CLOSED fallback)
V.lastObservedContainerItemID = nil -- persistent container ID from recent use/lock (fallback if lastContainerItemID cleared early)
V.lastObservedContainerItemTime = 0
V.bagSlotItemCache = {}  -- [slotKey] = itemID : caches itemID before consume/destruction (on V: main chunk is near the 200-local cap)
local resolvedIDs = {}       -- [itemID] = { type, collectibleID } - runtime resolved mount/pet IDs
local resolvedIDsReverse = {} -- [collectibleID] = itemID - reverse lookup for O(1) IndexLookup
local lockoutAttempted = {}  -- [questID] = true : tracks which lockout quests we've already counted this reset period
                             -- Keyed by questID (not npcID) so multiple NPCs sharing the same quest
                             -- (e.g. Arachnoid Harvester 154342/151934 both use quest 55512) are handled correctly.
-- Deferred loot session: one attempt decision at LOOT_CLOSED (slot scan + session obtain marks).
V.pendingLootSessionFinalize = nil
RT.LOOT_SESSION_RECENT_TTL = 90 -- block ENCOUNTER_END pre-miss while corpse/chest loot may still open
-- When loot has 0 item slots (only rep/currency), GetLootSourceInfo has nothing to return; target may be cleared.
-- Cache last targeted GUID that is in our DB so we can still attribute the loot open and count the try.
RT.lastLootSourceGUID = nil
RT.lastLootSourceTime = 0
RT.LAST_LOOT_SOURCE_TTL = 3  -- seconds
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
-- Miss-increment chat lines queued while the loot window is open (flush after loot chat settles).
local pendingIncrementAnnounces = {}
local incrementAnnounceFlushTimer = nil
local tryCounterSelfTestSyncMiss = false
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
    -- LOOT_CLOSED clears `time` (it gates the 5s replay window), which made the fishing
    -- diagnostic report "last LOOT_READY 43839s ago" — i.e. GetTime() since login — right
    -- after a loot. This stamp is never cleared, so triage can tell "never" from "just now".
    lastSeenAt = 0,
    wasFishing = false,    -- snapshot of fishingCtx.active at LOOT_READY time
}
RT.LOOT_READY_STATE_TTL = 5  -- seconds; treat lootReady data as valid for this long


-- CHAT_MSG_LOOT fallback: itemID → npcID when loot window doesn't fire (direct loot, world boss, etc.).
-- Built from npcDropDB in BuildReverseIndices; hardcoded entries merged so they take precedence.
local chatLootItemToNpc = {}
local chatLootTrackedItems = {}
local chatLootItemUniqueNpc = {}
V.lastTryCountSourceKey = nil
V.lastTryCountSourceTime = 0
V.lastTryCountLootSourceGUID = nil
V.lastEncounterEndTime = 0  -- set on ANY successful ENCOUNTER_END (even unmatched); suppresses zone fallback
RT.CHAT_LOOT_DEBOUNCE = 2.0  -- seconds: avoid double-count if LOOT_OPENED and CHAT_MSG_LOOT both fire
-- Attempt-announce flush delay. Deliberately NOT CHAT_LOOT_DEBOUNCE: that 2.0s is a double-count
-- guard between the LOOT_OPENED and CHAT_MSG_LOOT routes, and reusing it here made the "N attempts"
-- line land ~2s after the catch while "Caught X!" printed instantly. The queue only has to trail
-- the loot chat lines of the SAME loot event, and those arrive within a frame or two of LOOT_CLOSED.
-- RT fields rather than locals: this chunk already carries 175 top-level locals (~200 is the ceiling).
RT.INCREMENT_ANNOUNCE_FLUSH_DELAY = 0.25
-- Ceiling measured from the first queued line, so a multi-item loot burst cannot walk the flush
-- forward one bump at a time.
RT.INCREMENT_ANNOUNCE_MAX_DEFER = 1.0
RT.pendingIncrementAnnounceQueuedAt = 0
-- Auto-loot may LOOT_CLOSED (closed route) before LOOT_OPENED; skip late opened re-processing.
local LATE_LOOT_OPENED_SKIP_TTL = 10.0

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

function Fns.CopyDropArray(drops)
    if type(drops) ~= "table" then return {} end
    local copy = {}
    for i = 1, #drops do
        copy[i] = drops[i]
    end
    if drops.statisticIds then copy.statisticIds = drops.statisticIds end
    if drops.dropDifficulty then copy.dropDifficulty = drops.dropDifficulty end
    -- FilterDropsByDifficulty reads drops.difficultyIDs; without this the array-level whitelist
    -- (e.g. npc 214650 raid-only { 16 }) never reaches runtime and M+ kills leak into raid mounts.
    if drops.difficultyIDs then copy.difficultyIDs = drops.difficultyIDs end
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
    -- Learned lockouts live in SavedVariables. Merging them only at the end of Init lost them on every
    -- RebuildTrackDB (custom drop add/remove, builtin toggle) and ran after MergeTrackDB had already
    -- built NPC eligibility without them.
    if Fns.MergeDiscoveredLockoutQuests then Fns.MergeDiscoveredLockoutQuests() end

    wipe(instanceBossSlotOutcomeRules)
    local slotRules = db.instanceBossSlotOutcomeRules
    if type(slotRules) == "table" then
        for i = 1, #slotRules do
            instanceBossSlotOutcomeRules[i] = slotRules[i]
        end
    end
    Fns.SyncTryCounterRTTableRefs()
end

--- Idempotent load for slash self-test and early bootstrap (before InitializeTryCounter).
local reverseIndicesBuilt = false -- above EnsureTryCounterRuntimeDbLoaded so its reset binds the local

function Fns.EnsureTryCounterRuntimeDbLoaded()
    if not ns.CollectibleSourceDB then return false end
    local probeObjectID = 469857 -- Overflowing Dumpster — stable self-test fixture
    if not objectDropDB[probeObjectID] then
        reverseIndicesBuilt = false
        Fns.LoadRuntimeSourceTables()
        Fns.MergeTrackDB()
        Fns.BuildReverseIndices()
    elseif not reverseIndicesBuilt then
        Fns.BuildReverseIndices()
    end
    Fns.SyncTryCounterRTTableRefs()
    return objectDropDB[probeObjectID] ~= nil
end

--- Handlers + Loot/Stats satellites read RT.*; LoadRuntimeSourceTables reassigns file-local DB tables — keep RT in sync.
function Fns.SyncTryCounterRTTableRefs()
    RT.npcDropDB = npcDropDB
    RT.objectDropDB = objectDropDB
    RT.fishingDropDB = fishingDropDB
    RT.containerDropDB = containerDropDB
    RT.zoneDropDB = zoneDropDB
    RT.encounterDB = encounterDB
    RT.encounterNameToNpcs = encounterNameToNpcs
    RT.lockoutQuestsDB = lockoutQuestsDB
    RT.npcIDToEncounterID = npcIDToEncounterID
    RT.tryCounterNpcEligible = tryCounterNpcEligible
    RT.instanceBossSlotOutcomeRules = instanceBossSlotOutcomeRules
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
    for npcID in pairs(lockoutQuestsDB or {}) do mark(npcID) end

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
        elseif lockoutQuestsDB and lockoutQuestsDB[npcID] then
            tryCounterNpcEligible[npcID] = true
        else
            -- World / zone farm mounts and collectibles: repeatable, dropDifficulty, or mount/pet/toy
            -- even when lacking statisticIds. They must drive loot-window try counts.
            for i = 1, #drops do
                local d = drops[i]
                if type(d) == "table" and (d.dropDifficulty or d.repeatable or d.type == "mount" or d.type == "pet" or d.type == "toy") then
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

-- REVERSE INDEX BUILDER
-- Called once from InitializeTryCounter after DB references are loaded.
-- Iterates all drop sources once, building O(1) lookup tables keyed by
-- type+itemID. This eliminates the O(N) full-DB scans that previously
-- ran on every cache-miss call to Is*Collectible().

-- Item drops whose collectible yield lags behind the loot itself: the Nether-Warped Egg
-- incubates for 7 days, so C_MountJournal keeps reporting the mount as uncollected and the
-- ONLY thing that can stop the counter is the `obtained` latch. Filled by IndexDrop, drained
-- by ReconcileObtainedFromInventory. See github issue #76.
Fns.delayedYieldItemIDs = {}

function Fns.IndexDrop(drop, npcDifficulty, hasStatistics)
    if not drop or not drop.type or not drop.itemID then return end

    local itemKey = drop.type .. "\0" .. tostring(drop.itemID)

    if drop.type == "item" and not drop.repeatable and drop.yields and #drop.yields > 0 then
        Fns.delayedYieldItemIDs[drop.itemID] = true
    end

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

    -- Wiped here, not with the other indices further down: IndexDropArray below fills it.
    wipe(Fns.delayedYieldItemIDs)

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
    -- Wipe in place: RT.chatLootItemToNpc aliases this table (Handlers reads it); reassigning left RT
    -- on the empty load-time table and chat Path 2 never matched.
    wipe(chatLootItemToNpc)
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
                        -- Ambiguous owner. MergeChatLootItemToNpc ignores a false npcID, so mark directly.
                        chatLootItemToNpc[itemID] = false
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
    for _, containerData in pairs(containerDropDB) do
        local drops = containerData.drops or containerData
        if type(drops) == "table" then
            for i = 1, #drops do
                local drop = drops[i]
                if drop and drop.itemID then
                    chatLootTrackedItems[drop.itemID] = true
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
    Fns.InvalidateIndexLookupCaches()
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
            -- mountID / speciesID keys exist only now; drop answers cached before they did.
            Fns.InvalidateIndexLookupCaches()
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

---Latch `obtained` for delayed-yield item drops the player already holds.
---The flag is otherwise written only from the live loot routes, and there is no way back:
---if a route misses the catch (fast auto-loot closing the window before the slot scan,
---looted on another character, looted before the addon was installed) the drop keeps
---counting misses forever, because its yield stays uncollected while it incubates.
---Bags + bank + reagent bank + WARBAND bank: the last one matters, an egg parked in the
---warband bank is invisible to the 2-argument GetItemCount form.
---Cheap by construction: the candidate set only holds item drops that declare `yields`,
---and each entry leaves the set the moment it is latched.
function Fns.ReconcileObtainedFromInventory()
    if not Fns.EnsureDB() then return end
    local GetCount = C_Item and C_Item.GetItemCount
    if not GetCount then return end

    -- Clearing the current key during pairs() is allowed in Lua 5.1; adding is not, and
    -- nothing here adds.
    for itemID in pairs(Fns.delayedYieldItemIDs) do
        -- true  = already latched, nothing to do.
        -- false = explicitly un-marked by the player (ClearItemObtained). Never re-latch it:
        --         RebuildTrackDB refills this set from scratch, and the next sweep would
        --         otherwise undo their decision from the bags.
        local marker = WarbandNexus.db.global.tryCounts.obtained[itemID]
        if marker ~= nil then
            Fns.delayedYieldItemIDs[itemID] = nil
        else
            local ok, count = pcall(GetCount, itemID, true, false, true, true)
            if ok and count and not (issecretvalue and issecretvalue(count)) then
                count = tonumber(count)
                if count and count > 0 then
                    Fns.MarkItemObtained(itemID)
                    Fns.delayedYieldItemIDs[itemID] = nil
                end
            end
        end
    end
end

---Throttled entry point for the hot collectible filter.
function Fns.MaybeReconcileObtainedFromInventory()
    local now = GetTime()
    if (now - (RT.lastObtainedReconcile or 0)) < (RT.OBTAINED_RECONCILE_INTERVAL or 10) then return end
    RT.lastObtainedReconcile = now
    Fns.ReconcileObtainedFromInventory()
end

-- PUBLIC API (manual get/set/increment - unchanged from before)

---Resolve the quest-starter source itemID backing a mount, if any.
---Extracted from GetTryCount so SetTryCount can align the exact same key set: the
---quest-starter branch below reads keys (tryCounts.item[sourceItemID] and every mount key
---in sourceItemToAllMountKeys) that ForEachTryCountAliasKey never visits.
---@param id number mount id (mountID or itemID)
---@return number|nil sourceItemID
function Fns.ResolveQuestStarterSourceItemID(id)
    local idNum = tonumber(id)
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
    return sourceItemID
end

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
        local sourceItemID = Fns.ResolveQuestStarterSourceItemID(id)
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
        -- C_MountJournal.GetMountItemID does not exist (no wiki page; the journal only exposes
        -- the item->mount direction via GetMountFromItem). The guarded branch that used to sit
        -- here could never run; it read as a working fallback and hid that there is none.
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

---Set the stored attempt count, aligning every key GetTryCount can read back.
---GetTryCount returns the MAX across all keys that can represent one collectible, so a
---write that only touched the exact key was shadowed by a higher stale value: editing a
---mount to 0 in the popup still read back the old count off the itemID key. ResetTryCount
---already zeroes its alias keys for this reason; this mirrors that for explicit sets.
---Other keys are only ever clamped DOWN to `count` and never created, so callers that pass
---a value >= the current max (the statistics ratchet in TryCounterService_Stats) are
---unaffected, while a deliberate sync-down now actually sticks.
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@param count number
function WarbandNexus:SetTryCount(collectibleType, id, count)
    if not VALID_TYPES[collectibleType] or not id then return end
    if not Fns.EnsureDB() then return end
    local idNum = tonumber(id)
    if idNum then id = idNum end
    count = tonumber(count)
    if not count or count < 0 then count = 0 end
    local tc = WarbandNexus.db.global.tryCounts
    local tbl = tc[collectibleType]
    tbl[id] = count

    local function ClampOther(t, key)
        if not t or key == nil then return end
        if type(t[key]) == "number" and t[key] > count then t[key] = count end
    end

    -- Read branch 2: alias keys (mountID <-> itemID, pet itemID -> speciesID).
    Fns.ForEachTryCountAliasKey(collectibleType, id, function(key)
        if key ~= id then ClampOther(tbl, key) end
    end)

    -- Read branch 1: quest-starter mounts resolve to a different key set entirely and
    -- return early in GetTryCount, so the alias pass above never covers them.
    if collectibleType == "mount" then
        local sourceItemID = Fns.ResolveQuestStarterSourceItemID(id)
        if sourceItemID then
            ClampOther(tc.item, sourceItemID) -- separate table: no key ~= id guard needed
            local allKeys = sourceItemToAllMountKeys[sourceItemID]
            if allKeys then
                for i = 1, #allKeys do
                    if allKeys[i] ~= id then ClampOther(tbl, allKeys[i]) end
                end
            end
        end
    end

    Fns.SchedulePlansTryCountUIUpdate()
end

---Resolve teach-item / source item ID for a collectible (e.g. mountID -> itemID).
---@param collectibleType string "mount"|"pet"|"toy"|"item"
---@param id number mountID, speciesID, or itemID
---@return number|nil itemID
function WarbandNexus:GetItemIDForCollectible(collectibleType, id)
    if not collectibleType or not id then return nil end
    local idNum = tonumber(id)
    if not idNum then return nil end
    if collectibleType == "toy" or collectibleType == "item" then
        return idNum
    end
    if collectibleType == "mount" and resolvedIDsReverse and resolvedIDsReverse[idNum] then
        return resolvedIDsReverse[idNum]
    end
    if collectibleType == "mount" and ns.CollectibleSourceDB and ns.CollectibleSourceDB.GetItemIDForMount then
        return ns.CollectibleSourceDB.GetItemIDForMount(idNum)
    end
    return nil
end

---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
---@return number newCount
function WarbandNexus:IncrementTryCount(collectibleType, id)
    return WarbandNexus:AddTryCountDelta(collectibleType, id, 1)
end

---Add multiple attempts at once (AoE farm: N corpses × same repeatable mount table).
---@param collectibleType string
---@param id number
---@param delta number
---@return number newCount
function WarbandNexus:AddTryCountDelta(collectibleType, id, delta)
    if not VALID_TYPES[collectibleType] or not id then return 0 end
    if not Fns.EnsureDB() then return 0 end
    local idNum = tonumber(id)
    if idNum then id = idNum end
    delta = tonumber(delta) or 0
    if delta <= 0 then return WarbandNexus:GetTryCount(collectibleType, id) end
    -- Build on what GetTryCount reports (the max across alias / quest-starter keys), not on the
    -- exact key alone: a higher alias (itemID key written while the mount journal was cold) used to
    -- shadow every later increment of the mountID key, so tries were silently lost.
    local newStored = WarbandNexus:GetTryCount(collectibleType, id) + delta
    WarbandNexus.db.global.tryCounts[collectibleType][id] = newStored
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
    local idNum = tonumber(id)
    if idNum then id = idNum end
    local tc = WarbandNexus.db.global.tryCounts
    local tbl = tc[collectibleType]
    tbl[id] = 0

    local function ZeroOther(t, key)
        if not t or key == nil then return end
        if type(t[key]) == "number" and t[key] > 0 then t[key] = 0 end
    end

    -- Read branch 2: alias keys (mountID <-> itemID, pet itemID -> speciesID).
    Fns.ForEachTryCountAliasKey(collectibleType, id, function(key)
        if key ~= id then ZeroOther(tbl, key) end
    end)

    -- Read branch 1: quest-starter mounts. GetTryCount returns early on this branch and maxes
    -- tryCounts.item[sourceItemID] + every mount key in sourceItemToAllMountKeys, none of which
    -- ForEachTryCountAliasKey visits — a reset that skipped them read back the old count.
    -- Mirrors the same key set SetTryCount clamps.
    if collectibleType == "mount" then
        local sourceItemID = Fns.ResolveQuestStarterSourceItemID(id)
        if sourceItemID then
            ZeroOther(tc.item, sourceItemID) -- separate table: no key ~= id guard needed
            local allKeys = sourceItemToAllMountKeys[sourceItemID]
            if allKeys then
                for i = 1, #allKeys do
                    if allKeys[i] ~= id then ZeroOther(tbl, allKeys[i]) end
                end
            end
        end
    end

    Fns.SchedulePlansTryCountUIUpdate()
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
---Stores `false` rather than nil: the marker is tri-state, and only `== true` counts as
---obtained (IsItemMarkedObtained), so nothing downstream changes. `false` additionally
---tells ReconcileObtainedFromInventory to leave the item alone, which nil could not -
---the sweep would re-latch it from the bags the moment the indices were rebuilt.
---@param itemID number
function WarbandNexus:ClearItemObtained(itemID)
    if not itemID or not Fns.EnsureDB() then return end
    WarbandNexus.db.global.tryCounts.obtained[itemID] = false
    Fns.delayedYieldItemIDs[itemID] = nil
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
        if resolvedIDsReverse[id] ~= drop.itemID then
            resolvedIDsReverse[id] = drop.itemID
            -- A native id that just became resolvable may have been answered "false" already.
            Fns.InvalidateIndexLookupCaches()
        end
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
RT.pendingLootSessionFinalize = V.pendingLootSessionFinalize
RT.lootReady = lootReady
RT.fishingCtx = fishingCtx
RT.repeatableItemDrops = repeatableItemDrops
RT.chatLootItemToNpc = chatLootItemToNpc
RT.chatLootTrackedItems = chatLootTrackedItems
RT.chatLootItemUniqueNpc = chatLootItemUniqueNpc
-- Seconds between inventory reconciliation sweeps (Fns.MaybeReconcileObtainedFromInventory).
RT.OBTAINED_RECONCILE_INTERVAL = 10
RT.lastObtainedReconcile = 0
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
V.lastDifficultySkipChatKey = V.lastDifficultySkipChatKey
V.lastDifficultySkipChatTime = V.lastDifficultySkipChatTime or 0
RT.lastLootSourceGUID = RT.lastLootSourceGUID
RT.lastLootSourceTime = RT.lastLootSourceTime or 0
-- TryCounterService_Loot.lua satellite bindings
RT.npcIDToEncounterID = npcIDToEncounterID
RT.lockoutQuestsDB = lockoutQuestsDB
RT.containerDropDB = containerDropDB
RT.objectDropDB = objectDropDB
RT.zoneDropDB = zoneDropDB
RT.processedGUIDs = processedGUIDs
RT.mergedLootTryCountedAt = mergedLootTryCountedAt
RT.lockoutAttempted = lockoutAttempted
RT.guidNpcIDCache = guidNpcIDCache
RT.guidObjectIDCache = guidObjectIDCache
RT.repeatableCache = repeatableCache
RT.fishingDropDB = fishingDropDB
RT.recentKillByNpcID = recentKillByNpcID
-- RT.DIFFICULTY_ID_TO_LABELS is bound after the table is defined below (Lua 5.1 forward-ref: the local
-- does not exist at this line yet, so binding here would store nil and crash the difficulty-skip path).
-- TryCounterService_Stats.lua satellite bindings
-- (2026-10-22) The statistic seed tables / timings are created directly on RT where they are declared
-- (they had no reader in this chunk; the locals only spent main-chunk slots).
RT.instanceBossSlotOutcomeRules = instanceBossSlotOutcomeRules

function Fns.IsTryCounterReady()
    return tryCounterReady
end

Fns.StatisticSnapshotStorageKey = StatisticSnapshotStorageKey
Fns.RegisterQuestStarterMountKey = RegisterQuestStarterMountKey

function Fns.ScheduleLockoutDiscovery(npcID)
    if not npcID then return end
    V.discoveryPendingNpcID = npcID
    V.discoveryPendingTime = GetTime()
    C_Timer.After(2, Fns.TryDiscoverLockoutQuest)
end

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
    -- Check user override first. SetBuiltinRepeatable (Settings) keys by itemID, but the obtain /
    -- reset paths call this with the native collectibleID (mountID/speciesID) — probe both keys or
    -- the override is silently ignored exactly where it matters.
    if self.db and self.db.global and self.db.global.trackDB then
        local overrides = self.db.global.trackDB.repeatableOverrides
        if overrides then
            local prefix = (collectibleType or "") .. ":"
            local val = overrides[prefix .. tostring(id or 0)]
            if val ~= nil then return val end
            local sourceItemID = id and resolvedIDsReverse[id]
            if sourceItemID then
                val = overrides[prefix .. tostring(sourceItemID)]
                if val ~= nil then return val end
            end
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

---Reset-on-obtain policy for a found drop.
---The counter is keyed on the collectible the try count belongs to, which is NOT always the
---looted drop: `tryCountReflectsTo` moves it onto another collectible (Crackling Shard -> Alunira).
---A repeatable SOURCE must not zero a one-time TARGET's total, and a one-time drop must never
---reset at all — that frozen "tries to obtain" value is what the UI shows after collection.
---@param collectibleType string tcType from GetTryCountTypeAndKey
---@param tryKey number tryKey from GetTryCountTypeAndKey
---@param drop table drop row
---@return boolean
function Fns.ShouldResetOnObtain(collectibleType, tryKey, drop)
    if not drop or not collectibleType or not tryKey then return false end
    if drop.tryCountReflectsTo then
        return WarbandNexus:IsRepeatableCollectible(collectibleType, tryKey) == true
    end
    return drop.repeatable == true
end

-- Session cache for difficulty lookups
local difficultyCache = {}

---Is*Collectible() and GetDropDifficulty cache negative answers too. Anything that adds index keys
---or native-id mappings must drop them, or a lookup made before (tooltip, toast in the first seconds
---after login, a custom drop added later) stays wrong for the whole session.
function Fns.InvalidateIndexLookupCaches()
    wipe(guaranteedCache)
    wipe(repeatableCache)
    wipe(dropSourceCache)
    wipe(difficultyCache)
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
    local diff = dropDifficultyIndex[key]
    if diff and diff ~= "All Difficulties" then
        difficultyCache[cacheKey] = diff
        return diff
    elseif diff == "All Difficulties" then
        difficultyCache[cacheKey] = false
        return nil
    end

    -- For non-toy types, caller may pass a native collectibleID (mountID/speciesID)
    -- but the index is keyed by itemID. Use O(1) reverse map instead of O(N) scan.
    if collectibleType ~= "toy" then
        local sourceItemID = resolvedIDsReverse[id]
        if sourceItemID then
            local altKey = collectibleType .. "\0" .. tostring(sourceItemID)
            local altDiff = dropDifficultyIndex[altKey]
            if altDiff and altDiff ~= "All Difficulties" then
                difficultyCache[cacheKey] = altDiff
                return altDiff
            elseif altDiff == "All Difficulties" then
                difficultyCache[cacheKey] = false
                return nil
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
        spellID = select(2, C_Item.GetItemSpell(itemID))
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
        -- Delayed-yield drops can sit in bags while their yield is still uncollected, so the
        -- latch below is the only thing that can stop them. Re-sync it from the inventory
        -- first; `next` makes this free once every candidate has been latched.
        if drop.yields and next(Fns.delayedYieldItemIDs) then
            Fns.MaybeReconcileObtainedFromInventory()
        end

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
        -- C_MountJournal.GetMountItemID does not exist (no wiki page; the journal only exposes
        -- the item->mount direction via GetMountFromItem). The guarded branch that used to sit
        -- here could never run; it read as a working fallback and hid that there is none.
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

-- Instance loot-miss reconciliation, paired to the kill itself (no timer). The ENCOUNTER_END
-- statistics sync sets a reseed mark once per kill that owns this attempt's count. If the collectible
-- is NOT in the loot, consume that pending mark exactly once so the loot pipeline never adds a second
-- manual +1 for the same kill — no matter how long after the kill the chest is opened. This is the
-- Sylvanas Mythic double-count: the boss stat counts at kill, then the separate chest GameObject
-- (whose objectDropDB row lacks the boss statisticIds, so ShouldUseStatisticsOnlyMiss cannot see the
-- backing) counts again on open. Consume-once: the next kill re-sets its own mark, so repeat farms
-- keep counting; the caller gates this to instances so open-world farms never reach it.
function Fns.ConsumePendingStatReseed(tcType, tryKey)
    if not tcType or not tryKey then return false end
    local mk = tcType .. "\0" .. tostring(tryKey)
    if dropDelayedReseeded[mk] ~= true then return false end
    dropDelayedReseeded[mk] = nil
    return true
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

--- Self-test: snapshot GUID/lockout dedup tables so probes do not leak across each other.
function Fns.SnapshotTryCounterSelfTestDedupState()
    local guids = {}
    for k, v in pairs(processedGUIDs) do
        guids[k] = v
    end
    local lockouts = {}
    for k, v in pairs(lockoutAttempted) do
        lockouts[k] = v
    end
    return { processedGUIDs = guids, lockoutAttempted = lockouts }
end

function Fns.ClearTryCounterSelfTestDedupState()
    wipe(processedGUIDs)
    wipe(lockoutAttempted)
    wipe(mergedLootTryCountedAt)
    RT.lastLootTryOutcomeCommittedAt = nil
    RT.lastLootTryOutcomeCommittedKey = nil
    if V then
        V.lastTryCountSourceKey = nil
        V.lastTryCountSourceTime = 0
        V.lastTryCountLootSourceGUID = nil
    end
end

function Fns.RestoreTryCounterSelfTestDedupState(snap)
    if not snap then return end
    wipe(processedGUIDs)
    for k, v in pairs(snap.processedGUIDs or {}) do
        processedGUIDs[k] = v
    end
    wipe(lockoutAttempted)
    for k, v in pairs(snap.lockoutAttempted or {}) do
        lockoutAttempted[k] = v
    end
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
        if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then
            linkLabel = "|cffa335ee[" .. name .. "]|r"
        end
    elseif tcType == "pet" and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, name = pcall(C_PetJournal.GetPetInfoBySpeciesID, collectibleID)
        if ok and type(name) == "string" and not (issecretvalue and issecretvalue(name)) and name ~= "" then
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
    V.pendingLootSessionFinalize = nil
    RT.pendingLootSessionFinalize = nil
end

function Fns.SetDeferredLootSessionSnapshot(pending)
    V.pendingLootSessionFinalize = pending
    RT.pendingLootSessionFinalize = pending
end

function Fns.SetTryCounterSelfTestSyncMiss(enabled)
    tryCounterSelfTestSyncMiss = not not enabled
end

--- Optional env for slot-first self-tests (SoD Sylvanas replay; no raid / owned-mount safe).
function Fns.SetTryCounterSelfTestSlotOutcomeEnv(env)
    if not env then
        RT.tryCounterSelfTest.slotInstance = nil
        RT.tryCounterSelfTest.bossTrackable = nil
        tryCounterSelfTestBossTrackable = nil
        return
    end
    RT.tryCounterSelfTest.slotInstance = env.instance
    RT.tryCounterSelfTest.bossTrackable = env.bossTrackable
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
        closedRouteRareNpcID = 234480, -- M.A.G.N.O. (no weekly lockout_quest — closed-only probe)
        raidBossNpcID = 241526,
        mechanicaItemID = 234741,
        dumpsterGUID = "GameObject-0-0-0-0-469857-000000000000",
        rareNpcGUID = "Creature-0-0-0-0-230995-000000000000",
        closedRouteRareNpcGUID = "Creature-0-0-0-0-234480-000000000000",
        raidBossGUID = "Creature-0-0-0-0-241526-000000000000",
        herbGUID = "GameObject-0-0-0-0-999999-000000000000",
    }
end

-- Statistics sync: Modules/TryCounterService_Stats.lua (Fns.*)


--- Loot path committed a miss increment — cancel ENCOUNTER_END lootless timers; block late LOOT_OPENED dupes.
function Fns.NotifyLootTryOutcomeCommitted(sourceKey, npcID)
    if sourceKey then
        RT.lastLootTryOutcomeCommittedAt = GetTime()
        RT.lastLootTryOutcomeCommittedKey = sourceKey
    end
    if RT.currentEncounterCache then
        RT.currentEncounterCache.consumed = true
    end
    if Fns.CancelEncounterLootlessMissFallback then
        Fns.CancelEncounterLootlessMissFallback()
    end

    -- Statistics only move when THIS character kills something, so an attributed kill is the one
    -- moment a delta is worth re-reading. ENCOUNTER_END marks instance bosses; open-world rares
    -- never fire it, so mark here too and let the CRITERIA_UPDATE handler re-read just this NPC's
    -- statistic ids. No-op for NPCs without statisticIds.
    local npc = tonumber(npcID)
    if npc and Fns.MarkNpcForRuntimeStatReseed then
        local npcData = RT.npcDropDB and RT.npcDropDB[npc]
        if npcData and Fns.NpcEntryHasStatisticIds and Fns.NpcEntryHasStatisticIds(npcData) then
            Fns.MarkNpcForRuntimeStatReseed(npc, nil)
        end
    end
end

--- Fast auto-loot: LOOT_CLOSED closed route may run before LOOT_OPENED (HK-8 / personal loot).
function Fns.ShouldSkipLateLootOpenedRoute(isFromItem)
    if isFromItem then return false end
    if not Fns.IsAutoTryCounterEnabled() then return false end
    local now = GetTime()
    local committedAt = RT.lastLootTryOutcomeCommittedAt or V.lastTryCountSourceTime
    if not committedAt or (now - committedAt) > LATE_LOOT_OPENED_SKIP_TTL then
        return false
    end
    local key = RT.lastLootTryOutcomeCommittedKey or V.lastTryCountSourceKey
    if not key or type(key) ~= "string" then return false end
    if key:match("^encounter_") or key:match("^inst_slot_") then return true end
    if key:match("^npc_") then
        -- npc_<id> + a 10s window is not enough to identify "the same corpse we just counted".
        -- Farming one rare (or two of the same mob) inside the window made every kill that showed a
        -- loot window skip its route here — and because LOOT_OPENED had already set lootSession.opened,
        -- the LOOT_CLOSED fallback route did not run either, so the attempt vanished with no error.
        -- The corpse GUID is the actual identity; the LOOT_CLOSED debounce already compares on it.
        -- Only suppress when the incoming corpse IS the one just committed; when the GUID is
        -- unavailable or secret, fall back to the old time+key behaviour (skipping a possible
        -- duplicate beats double-counting one).
        local incoming = lootSession.sourceGUIDs and lootSession.sourceGUIDs[1] or lootSession.npcGUID
        local committedGUID = V.lastTryCountLootSourceGUID
        if type(incoming) == "string" and type(committedGUID) == "string"
            and not (issecretvalue and (issecretvalue(incoming) or issecretvalue(committedGUID))) then
            return incoming == committedGUID
        end
        return true
    end
    return false
end

--- Queue miss-increment chat until after loot chat settles (auto-loot CHAT_MSG_LOOT can trail LOOT_CLOSED).
function Fns.IsLootSessionActiveForIncrementAnnounce()
    -- A route processor running after its OWN LOOT_CLOSED still sees the restored snapshot's
    -- opened=true, but no further LOOT_CLOSED is coming to flush the queue -- so deferring there parks
    -- the line until the NEXT loot closes. That is the second half of the same fast-auto-loot frame
    -- race ShouldDeferLootOutcomeUntilClose handles: emit inline, the loot chat is already out.
    if V.lootRouteWindowAlreadyClosed then return false end
    if lootSession.opened then return true end
    if V.pendingLootSessionFinalize then return true end
    return false
end

function Fns.CancelIncrementAnnounceFlush()
    if incrementAnnounceFlushTimer then
        incrementAnnounceFlushTimer:Cancel()
        incrementAnnounceFlushTimer = nil
    end
end

--- Self-test accessor: the timer handle is a file local, and its presence is the only observable
--- proof that scheduling produced something cancelable (see RunTryCounterSelfTest).
function Fns.GetIncrementAnnounceFlushTimer()
    return incrementAnnounceFlushTimer
end

--- Flush queued try-counter lines just after loot chat settles. Reschedule on each self-loot line,
--- but never past INCREMENT_ANNOUNCE_MAX_DEFER measured from the first queued line.
function Fns.ScheduleIncrementAnnounceFlushAfterLoot(delay)
    if #pendingIncrementAnnounces == 0 then return end
    delay = tonumber(delay) or RT.INCREMENT_ANNOUNCE_FLUSH_DELAY
    local queuedAt = RT.pendingIncrementAnnounceQueuedAt or 0
    if queuedAt > 0 then
        local remaining = (queuedAt + RT.INCREMENT_ANNOUNCE_MAX_DEFER) - GetTime()
        if remaining <= 0 then
            -- Deadline spent. Re-arming here would walk the line further out on every bump instead of
            -- capping it, so deliver now: this is what makes MAX_DEFER a real ceiling and not a nudge.
            Fns.CancelIncrementAnnounceFlush()
            Fns.TryCounterAnnounceDebug("flush now (max defer reached, queued=%d)", #pendingIncrementAnnounces)
            Fns.FlushDeferredTryCounterIncrementAnnounces()
            return
        end
        if remaining < delay then delay = remaining end
    end
    Fns.CancelIncrementAnnounceFlush()
    -- C_Timer.After returns nothing (warcraft.wiki.gg/wiki/API_C_Timer.After, verified 2026-08-18), so
    -- the old `= C_Timer.After(...)` left this handle nil and CancelIncrementAnnounceFlush was a silent
    -- no-op: every bump armed ANOTHER live timer, and a leftover one from the previous loot could fire
    -- mid-session and flush the next loot's line early. NewTimer hands back a real :Cancel() handle.
    incrementAnnounceFlushTimer = C_Timer.NewTimer(delay, function()
        incrementAnnounceFlushTimer = nil
        Fns.FlushDeferredTryCounterIncrementAnnounces()
    end)
    Fns.TryCounterAnnounceDebug("flush scheduled in %.2fs (queued=%d)", delay, #pendingIncrementAnnounces)
end

function Fns.BumpIncrementAnnounceFlushAfterLootChat()
    if #pendingIncrementAnnounces == 0 then return end
    Fns.ScheduleIncrementAnnounceFlushAfterLoot(RT.INCREMENT_ANNOUNCE_FLUSH_DELAY)
end

function Fns.RunOrDeferTryCounterIncrementAnnounce(emitFn)
    if type(emitFn) ~= "function" then return end
    if Fns.IsLootSessionActiveForIncrementAnnounce() then
        -- Stamp only on 0 -> 1: the deadline belongs to the batch, not to its newest member.
        if #pendingIncrementAnnounces == 0 then
            RT.pendingIncrementAnnounceQueuedAt = GetTime()
        end
        pendingIncrementAnnounces[#pendingIncrementAnnounces + 1] = emitFn
        return
    end
    emitFn()
end

function Fns.FlushDeferredTryCounterIncrementAnnounces()
    local n = #pendingIncrementAnnounces
    if n == 0 then return end
    -- Drain in place. Rebinding the local to a fresh table orphaned RT.pendingIncrementAnnounces
    -- (aliased once at load), so every `#RT.pendingIncrementAnnounces > 0` guard in
    -- TryCounterService_Handlers.lua read a dead table that still held the first batch forever:
    -- permanently true, and permanently leaking those closures.
    local batch = {}
    for i = 1, n do
        batch[i] = pendingIncrementAnnounces[i]
        pendingIncrementAnnounces[i] = nil
    end
    -- Queue is empty again: the next line queued starts a fresh max-defer window.
    RT.pendingIncrementAnnounceQueuedAt = 0
    for i = 1, n do
        local fn = batch[i]
        if type(fn) == "function" then fn() end
    end
end

function Fns.EmitTryCounterIncrementAnnounce(incrementAnnounce, immediate)
    if not incrementAnnounce or not next(incrementAnnounce) then return end
    local function emitFn()
        for _, info in pairs(incrementAnnounce) do
            local link = info.drop and Fns.GetDropItemLink(info.drop)
            local count = info.finalCount or info.added
            if link and count and count > 0 then
                local tmpl = (ns.L and ns.L["TRYCOUNTER_INCREMENT_CHAT"]) or "%d attempts for %s"
                Fns.TryCounterAnnounceDebug("emit line (count=%s)", tostring(count))
                Fns.TryChat("|cff9370DB[WN-Counter]|r |cffffffff" .. format(tmpl, count, link) .. "|r")
            else
                Fns.TryCounterAnnounceDebug("line dropped: link=%s count=%s",
                    tostring(link ~= nil), tostring(count))
            end
        end
    end
    if immediate and not Fns.IsLootSessionActiveForIncrementAnnounce() then
        emitFn()
    else
        Fns.TryCounterAnnounceDebug("route: sessionActive=%s (opened=%s pendingFinalize=%s)",
            tostring(Fns.IsLootSessionActiveForIncrementAnnounce()),
            tostring(lootSession.opened), tostring(V.pendingLootSessionFinalize ~= nil))
        Fns.RunOrDeferTryCounterIncrementAnnounce(emitFn)
    end
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

    -- Raid/dungeon: the ENCOUNTER_END statistics sync already owns each attempt (it counted this kill
    -- and set the reseed mark). Consume any pending mark here so a later loot-open — no matter how long
    -- after the kill — never adds a second manual +1. This is the Sylvanas Mythic case: the boss stat
    -- counts at kill, then the separate chest GameObject counts again on open. Paired to the kill, not a
    -- timer. Instance-only: open-world farms are never raid/dungeon, so their per-corpse counting stays.
    if Fns.IsRaidOrDungeonInstance() then
        local kept = {}
        for i = 1, #drops do
            local d = drops[i]
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(d)
            if not (tryKey and Fns.ConsumePendingStatReseed(tcType, tryKey)) then
                kept[#kept + 1] = d
            end
        end
        if #kept == 0 then return end
        drops = kept
    end

    local attemptTimes = options and tonumber(options.attemptTimes) or 1
    if attemptTimes < 1 then attemptTimes = 1 end

    -- Raid/dungeon + statisticIds: miss is owned by ENCOUNTER_END stat sync (loot = found only).
    if Fns.ShouldUseStatisticsOnlyMiss(drops, statIds) then
        return
    end

    local allRepeatableMisses = true
    for i = 1, #drops do
        if not drops[i].repeatable then
            allRepeatableMisses = false
            break
        end
    end

    local syncNow = tryCounterSelfTestSyncMiss or (options and options.sync == true)
    local silentAnnounce = options and options.silentAnnounce

    local function runManualMissIncrementJob()
        if not Fns.EnsureDB() then return end
        local WN = WarbandNexus
        local announceTry = Fns.IsAutoTryCounterEnabled() and not silentAnnounce
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
    if not WN then return end
    local reason = Fns.GetTryCounterDisabledReason()
    if not reason then return end
    local L = ns.L
    local key = (reason == "module") and "TRYCOUNTER_DISABLED_MODULE" or "TRYCOUNTER_DISABLED_AUTO"
    local msg = (L and L[key])
        or "Try Counter is disabled in Settings - kills are not counted."
    -- TryChat, not :Print. This is a [WN-Counter] line, but :Print goes to one resolved frame and
    -- ignores notifications.tryCounterChatRoute, so it landed in a different tab than every other
    -- try-counter line -- including the drop lines emitted beside it on instance entry.
    Fns.TryChat("|cffff6600[WN-Counter]|r " .. msg)
end

function Fns.IsAutoTryCounterEnabled()
    local st = RT.tryCounterSelfTest
    if st and st.bypassAutoGate then return true end
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

--- Bobber creature ids learned at runtime (ClassifyLootSession, when IsFishingLoot confirmed it).
--- Shipped FISHING_BOBBER_NPC_IDS only covers three legacy ids, so every expansion's bobber has to be
--- learned. Learning it into a runtime-only table meant re-learning it after every /reload, and the
--- structural (no-API) fishing route stayed blind the whole time. Persist so one confirmed cast is
--- enough, forever, on every character.
function Fns.MergeDiscoveredFishingBobbers()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    local disc = WarbandNexus.db.global.discoveredFishingBobbers
    if type(disc) == "table" then
        for npcID, v in pairs(disc) do
            local nid = tonumber(npcID)
            if nid and v == true then
                FISHING_BOBBER_NPC_IDS[nid] = true
            end
        end
    end
    local objs = WarbandNexus.db.global.discoveredFishingBobberObjects
    if type(objs) == "table" then
        for objectID, v in pairs(objs) do
            local oid = tonumber(objectID)
            if oid and v == true then
                FISHING_BOBBER_OBJECT_IDS[oid] = true
            end
        end
    end
end

--- GameObject side of the same learn-and-persist path. This is the one that matches live fishing.
function Fns.RememberFishingBobberObjectId(objectID)
    local oid = tonumber(objectID)
    if not oid or oid <= 0 then return end
    -- Never learn a tracked object (Overflowing Dumpster, raid chests): it owns its own route, and a
    -- persisted mistake here would reroute that object's loot to fishing on every future session.
    if objectDropDB[oid] then return end
    FISHING_BOBBER_OBJECT_IDS[oid] = true
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    local objs = WarbandNexus.db.global.discoveredFishingBobberObjects
    if type(objs) ~= "table" then
        objs = {}
        WarbandNexus.db.global.discoveredFishingBobberObjects = objs
    end
    objs[oid] = true
end

function Fns.RememberFishingBobberNpcId(npcID)
    local nid = tonumber(npcID)
    if not nid or nid <= 0 then return end
    -- Never learn a tracked NPC as a bobber. IsFishingLoot() being true is normally proof the only
    -- creature source is the bobber, but a merged loot session (fishing loot plus a corpse) would
    -- otherwise teach us a real rare's id — and since this is now persisted, that rare's own try
    -- counting would stay broken across reloads. Refuse the poisoned entry instead.
    if npcDropDB[nid] or tryCounterNpcEligible[nid] then return end
    FISHING_BOBBER_NPC_IDS[nid] = true
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    local disc = WarbandNexus.db.global.discoveredFishingBobbers
    if type(disc) ~= "table" then
        disc = {}
        WarbandNexus.db.global.discoveredFishingBobbers = disc
    end
    disc[nid] = true
end

-- EVENT HANDLERS (encounter): Modules/TryCounterService_Handlers.lua

-- Loot pipeline: Modules/TryCounterService_Loot.lua (loads after IIFE)

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
    wipe(difficultyCache)

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
    if not self.useContainerItemHooked and C_Container and C_Container.UseContainerItem and C_Container.GetContainerItemID then
        local maxCarriedBagID = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
        pcall(function()
            hooksecurefunc(C_Container, "UseContainerItem", function(bagID, slotIndex)
                if bagID and slotIndex then
                    local safeBag = not (issecretvalue and issecretvalue(bagID)) and bagID or nil
                    local safeSlot = not (issecretvalue and issecretvalue(slotIndex)) and slotIndex or nil
                    if safeBag and safeSlot and safeBag >= 0 and safeBag <= maxCarriedBagID then
                        local slotKey = safeBag * 100 + safeSlot
                        local itemID = C_Container.GetContainerItemID(safeBag, safeSlot)
                        if itemID and not (issecretvalue and issecretvalue(itemID)) then
                            V.bagSlotItemCache[slotKey] = itemID
                        else
                            itemID = V.bagSlotItemCache[slotKey]
                        end
                        if itemID and not (issecretvalue and issecretvalue(itemID)) and containerDropDB[itemID] then
                            Fns.ScheduleContainerOpenAttempt(itemID, safeBag, safeSlot)
                        end
                    end
                end
            end)
        end)
        self.useContainerItemHooked = true
    end

    if not self.useItemByNameHooked and C_Item and C_Item.UseItemByName then
        pcall(function()
            hooksecurefunc(C_Item, "UseItemByName", function(nameOrID)
                if nameOrID and not (issecretvalue and issecretvalue(nameOrID)) then
                    local itemID = tonumber(nameOrID)
                    if not itemID and type(nameOrID) == "string" and C_Item.GetItemInfoInstant then
                        itemID = C_Item.GetItemInfoInstant(nameOrID)
                    end
                    if itemID and not (issecretvalue and issecretvalue(itemID)) and containerDropDB[itemID] then
                        Fns.ScheduleContainerOpenAttempt(itemID, nil, nil)
                    end
                end
            end)
        end)
        self.useItemByNameHooked = true
    end

    -- Build reverse lookup indices for O(1) Is*Collectible() queries.
    -- Must run AFTER DB references are loaded and trackDB is merged.
    Fns.BuildReverseIndices()

    -- The per-character Statistics seed runs on every character entry (Statistics are per-character,
    -- so a revisited character's kills only reach the account total through its own pass). The index
    -- and the ID warmup below are therefore always needed: the old "snapshot already warm" shortcut
    -- just pushed the same work into the seed's on-demand retry path.
    -- (2026-10-22) Built one frame later, not inside this login frame: every reader goes through the
    -- lazy EnsureMergedStatisticSeedIndex (loot / encounter handlers, seed, reseed, audit), so a reader
    -- that fires first just builds it itself and the deferred call is a no-op. Still built before the
    -- first runSeed (T+1s), so a seed that lands in combat keeps a populated index as before.
    Fns.InvalidateMergedStatisticSeedIndex()
    C_Timer.After(0, function()
        if not tryCounterReady then return end
        Fns.EnsureMergedStatisticSeedIndex()
    end)

    Fns.MergeDiscoveredFishingBobbers()

    -- Sync lockout state with server quest flags (prevents false increments after /reload mid-farm)
    Fns.SyncLockoutState()
    lastLockoutSyncAt = GetTime() or 0

    -- Pre-resolve mount/pet IDs for all known drop items (warmup cache for SeedFromStatistics, and
    -- for try-count key stability).
    --
    -- Coverage matters beyond seeding: GetTryCountKey returns the mountID only once
    -- ResolveCollectibleID succeeds and falls back to the itemID while the journal is cold. Writes
    -- land on whichever key was current, and GetTryCount reads the MAX across both -- so a key that
    -- flips between sessions starts a fresh bucket at 0 and the displayed count STALLS until it
    -- overtakes the old one. This queue used to walk npcDropDB alone, and only entries carrying
    -- statisticIds, so fishing / container / object drops (and plain rares) were never warmed:
    -- Nether-Warped Drake is a fishing drop and hit the cold path every time.
    -- Delayed 5s (absolute ~T+6.5s). Time-budgeted to prevent frame spikes.
    C_Timer.After(5, function()
        local RESOLVE_BUDGET_MS = 3
        local resolveQueue = {}
        local queued = {}
        local function enqueue(drop)
            if type(drop) ~= "table" or not drop.itemID then return end
            if resolvedIDs[drop.itemID] or queued[drop.itemID] then return end
            queued[drop.itemID] = true
            resolveQueue[#resolveQueue + 1] = drop
            -- tryCountReflectsTo resolves through its OWN itemID (see GetTryCountTypeAndKey), so the
            -- reflected target needs warming too or the reflecting drop keeps flipping keys.
            local ref = drop.tryCountReflectsTo
            if type(ref) == "table" and ref.itemID and not resolvedIDs[ref.itemID]
                and not queued[ref.itemID] then
                queued[ref.itemID] = true
                resolveQueue[#resolveQueue + 1] = ref
            end
        end
        local function enqueueList(list)
            if type(list) ~= "table" then return end
            for j = 1, #list do enqueue(list[j]) end
        end
        -- Statistic-bearing NPCs first: seeding still depends on these being warm soonest.
        for _, npcData in pairs(npcDropDB) do
            if Fns.NpcEntryHasStatisticIds(npcData) then enqueueList(npcData) end
        end
        for _, npcData in pairs(npcDropDB) do enqueueList(npcData) end
        for _, objectData in pairs(objectDropDB) do enqueueList(objectData) end
        for _, mapDrops in pairs(fishingDropDB) do enqueueList(mapDrops) end
        for _, containerData in pairs(containerDropDB) do
            enqueueList(containerData.drops or containerData)
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

    -- Per-character Statistics seed + Rarity max overlay (PLAYER_ENTERING_WORLD also schedules on alt/reload).
    -- Quick pass T+1s, full pass T+8s (after pre-resolve ~T+5s warms mount/pet IDs).
    Fns.SchedulePerCharacterStatisticsAndRaritySync()
    local kSched = StatisticSnapshotStorageKey()
    if kSched then
        V.lastSyncScheduleCharKey = kSched
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
    -- /reload in dungeon or zone-in before T+7.5: PEW may have fired before init; replay entry announce.
    if not tryCounterSkipPostInitInstanceEntry then
        ScheduleTryCounterInstanceEntryIfInside()
    end

    -- WN_COLLECTIBLE_OBTAINED: Handled by unified dispatch in NotificationManager.
    -- Do NOT register here — AceEvent allows only one handler per event per object.
    -- The dispatch handler in NotificationManager calls OnTryCounterCollectibleObtained.

    -- Periodic cleanup of stale GUIDs and kills (every 60s, batched)
    C_Timer.NewTicker(CLEANUP_INTERVAL, function()
        TrimGuidParseCachesIfOversized()
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
    GetItemIDForCollectible = function(_, ct, id) return WarbandNexus:GetItemIDForCollectible(ct, id) end,
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
