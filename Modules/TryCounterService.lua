--[[
    Warband Nexus - Try Counter Service
    Automatic try counter: Classify-Lock-Process architecture.
    Each loot session is classified into EXACTLY ONE route; no overlap.
    
    RULE: Only "rare-tier" sources increment try counts:
      world rares, encounter bosses, tooltip name-index bosses, statistic/
      difficulty-gated drops, user custom NPCs. Never shared trash tables.
      Containers, objects, fishing: unchanged. Guaranteed drops excluded.
    
    DB: db.global.tryCounts[type][id] = count
    
    EVENT FLOW (warcraft.wiki.gg verified):
      LOOT_READY  → ALWAYS fires (often twice per open). Loot APIs valid. Capture ALL data here.
                   Second READY while the window is open must not clear lootSession.opened.
      LOOT_OPENED → MAY NOT FIRE (fast auto-loot / addons skip it).
                    When it fires: best-quality path (isFromItem + fresh reads).
      LOOT_CLOSED → ALWAYS fires. Processes from LOOT_READY data when OPENED missed.
                    Note: fires BEFORE CHAT_MSG_LOOT (wiki confirmed).
      CHAT_MSG_LOOT → Fires after LOOT_CLOSED. Strict fallback with global debounce.
    
    CLASSIFY-LOCK-PROCESS:
      ClassifyLootSession() determines one route per loot event:
        1) SKIP       — pickpocket / blocking vendor UI / profession loot /
                        gathering+GameObject (no mob context)
        2) CONTAINER  — isFromItem flag OR recent tracked container use
        3) FISHING    — IsFishingLoot() OR (fish context + source compatible +
                        NO Creature/Vehicle corpse in session or unit context)
        4) NPC/OBJECT — ProcessNPCLoot (exact GUID→ID match only)
      Once classified, ALL other routes are locked out.
    
    ProcessNPCLoot resolver chain (first match wins):
      P1: Per-slot source GUIDs → exact npcID/objectID match
      P2: Unit GUIDs (npc/mo/tg/lastLoot) → only if P1 found nothing
      P3: Zone raresOnly pools → open world + rare-class unit only
      P4: Encounter recentKills → instance boss bookkeeping
    
    MULTI-CORPSE / AoE (zone farm mounts, e.g. Bloodfeaster / Pack Mule):
      Blizzard merges AoE loot into one window. Midnight 12.0+ blocks addon subscription to
      COMBAT_LOG_EVENT_UNFILTERED (ADDON_ACTION_FORBIDDEN even from pcall). Open-world NPC
      matches (no encounter/object) set farmCorpseMult = max(tableMult, npcMult, itemMult):
      tableMult = same npcDropDB table reference; itemMult = corpses whose drop table lists the
      missed itemIDs (runtime CopyDropArray gives different tables per npc id for the same mount).
      Skipped when statisticIds are set (miss path uses ReseedStatistics, not per-corpse mult).
      Mount obtained still resets via loot/chat as before.
    
    Fallbacks (all use global debounce — cannot double-count):
      CHAT_MSG_LOOT → repeatable reset → exact item→NPC → item→encounter → item→fishing
      ENCOUNTER_END → delayed 5s: only if no prior path counted
    
    Events: LOOT_READY, LOOT_OPENED, LOOT_CLOSED, CHAT_MSG_LOOT,
      ENCOUNTER_END, UNIT_SPELLCAST_SENT, ITEM_LOCK_CHANGED, PLAYER_ENTERING_WORLD,
      PLAYER_REGEN_ENABLED,
      PLAYER_INTERACTION_MANAGER
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- =====================================================================
-- CONSTANTS & UPVALUES (performance: resolved once at file load)
-- =====================================================================

local VALID_TYPES = { mount = true, pet = true, toy = true, illusion = true, item = true }
local RECENT_KILL_TTL = 15       -- seconds to keep non-encounter recentKills entries
-- NOTE: Encounter kills (isEncounter=true) never expire by TTL.
-- They persist until loot is processed or the player leaves the instance.
-- This handles arbitrarily long RP phases, cinematics, and AFK between kill and loot.
local PROCESSED_GUID_TTL = 300   -- seconds before allowing same GUID again
-- Same merged loot window (npcID + sorted source GUIDs): block duplicate try increments if a second
-- route fires before processedGUIDs applies, or after GUID TTL in edge cases (partial loot reopen).
local MERGED_LOOT_TRY_DEDUP_TTL = 600
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
local questStarterSourceToStatisticIds = {}  -- sourceItemID -> { statId, ... } for "statistic + local" try count
local questStarterMountList = {}

-- Forward declarations for local functions used before their definition
local ResetLootSession
local CaptureLootSessionState
local PromoteLootReadyToSession
local ClassifyLootSession
local RouteLootSession
local GetSafeMapID
local GetNPCIDFromGUID
local GetObjectIDFromGUID
local SafeGetUnitGUID
local SafeGetTargetGUID
local SafeGetMouseoverGUID
local SafeGuardGUID
local TryDiscoverLockoutQuest
local TryCounterShowInstanceDrops -- assigned later; optional manual / debug use (no longer auto-called on instance entry)
local CurrentUnitsHaveMobLootContext -- OnTryCounterChatMsgLoot (fishing path) runs before `local function` line would be in scope
-- Forward declarations for state variables used in OnEvent closure (declared after it)
local npcDropDB
local tryCounterNpcEligible
local objectDropDB
local isBlockingInteractionOpen
local lastLootSourceGUID
local lastLootSourceTime
local discoveryPendingNpcID
local IsCollectibleCollected

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

---Build "Obtained [Item] after X tries!" chat message with try count included.
---@param baseKey string Locale key for the base message (e.g. "TRYCOUNTER_OBTAINED" or "TRYCOUNTER_OBTAINED_RESET")
---@param baseFallback string English fallback for the base message
---@param itemLink string Formatted item link
---@param preResetCount number|nil Failed attempts before the successful one (total = preResetCount + 1)
---@return string
local function BuildObtainedChat(baseKey, baseFallback, itemLink, preResetCount)
    local base = format((ns.L and ns.L[baseKey]) or baseFallback, itemLink)
    if preResetCount == nil then return "|cff9370DB[WN-Counter]|r " .. base end
    local totalTries = preResetCount + 1
    local trySuffix
    if totalTries <= 1 then
        trySuffix = (ns.L and ns.L["TRYCOUNTER_FIRST_TRY"]) or "on the first try!"
    else
        trySuffix = format((ns.L and ns.L["TRYCOUNTER_AFTER_TRIES"]) or "after %d tries", totalTries)
    end
    return "|cff9370DB[WN-Counter]|r " .. base .. " |cffffff00" .. trySuffix .. "|r"
end

-- =====================================================================
-- RAW EVENT FRAMES
-- tryCounterFrame: loot, chat, encounter, spellcast, etc.
--
-- Midnight 12.0+: RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED") is a protected action for
-- addons. Invoking it (even inside pcall, even from another frame's OnEvent) still reports
-- ADDON_ACTION_FORBIDDEN and can mark the addon unsafe for the session. No CLEU subscription;
-- open-world AoE farms use loot-based farmCorpseMult (table + npcId + missed-item source scan).
-- =====================================================================
local tryCounterReady = false
local tryCounterInitializing = false
local tryCounterEventsRegistered = false
local tryCounterFrame = CreateFrame("Frame")
local DEBUG_TRACE_EVENTS = {
    LOOT_READY = true,
    LOOT_OPENED = true,
    LOOT_CLOSED = true,
    CHAT_MSG_LOOT = true,
    CHAT_MSG_CURRENCY = true,
    CHAT_MSG_MONEY = true,
    ITEM_LOCK_CHANGED = true,
}

-- MUST be declared before tryCounterFrame:SetScript("OnEvent") — otherwise the closure resolves globals (nil).
local DEBUG_TRACE_DEDUP_LOOT_MS = 0.22
local lastDebugTraceLootTime = { LOOT_READY = 0, LOOT_CLOSED = 0 }

local TRYCOUNTER_EVENTS = {
    "LOOT_READY",
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_CURRENCY",
    "CHAT_MSG_MONEY",
    "ENCOUNTER_END",
    "PLAYER_ENTERING_WORLD",
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "ITEM_LOCK_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_TARGET_CHANGED",
    "QUEST_LOG_UPDATE",
    "PLAYER_REGEN_ENABLED",
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

local function RegisterTryCounterEvents()
    if tryCounterEventsRegistered then
        return true
    end
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
    -- Event trace: helps diagnose "no log" scenarios (e.g. no LOOT_OPENED, only currency chat event).
    if addon and addon.db and addon.db.profile and addon.db.profile.debugTryCounterLoot and DEBUG_TRACE_EVENTS[event] then
        local nowTrace = GetTime()
        local dedupKey = (event == "LOOT_READY" or event == "LOOT_CLOSED") and event or nil
        if dedupKey and lastDebugTraceLootTime[dedupKey]
            and (nowTrace - lastDebugTraceLootTime[dedupKey]) < DEBUG_TRACE_DEDUP_LOOT_MS then
            -- Same event twice in one tick/window — expected from the client; omit duplicate trace line.
        else
            if dedupKey then lastDebugTraceLootTime[dedupKey] = nowTrace end
            addon:Print("|cff9370DB[TC]|r |cff666688" .. event .. "|r")
        end
    end
    -- Early-session bootstrap: first fishing cast/loot can happen before scheduled init
    -- (InitializationService runs TryCounter at T+1.5s). Preserve context and force init on first loot events.
    if not tryCounterReady then
        if addon and event == "UNIT_SPELLCAST_SENT" then
            addon:OnTryCounterSpellcastSent(event, ...)
        end
        if addon and (event == "LOOT_READY" or event == "LOOT_OPENED" or event == "CHAT_MSG_LOOT")
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
    elseif event == "ENCOUNTER_END" then
        addon:OnTryCounterEncounterEnd(event, ...)
    elseif event == "PLAYER_ENTERING_WORLD" then
        addon:OnTryCounterInstanceEntry(event, ...)
    elseif event == "UNIT_SPELLCAST_SENT" then
        addon:OnTryCounterSpellcastSent(event, ...)
    elseif event == "ITEM_LOCK_CHANGED" then
        addon:OnTryCounterItemLockChanged(event, ...)
    elseif event == "UNIT_SPELLCAST_INTERRUPTED" or event == "UNIT_SPELLCAST_FAILED_QUIET" then
        addon:OnTryCounterSpellcastFailed(event, ...)
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        if interactionType and (not issecretvalue or not issecretvalue(interactionType)) and BLOCKING_INTERACTION_TYPES[interactionType] then
            isBlockingInteractionOpen = true
        end
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if interactionType and (not issecretvalue or not issecretvalue(interactionType)) and BLOCKING_INTERACTION_TYPES[interactionType] then
            isBlockingInteractionOpen = false
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        local guid = SafeGetTargetGUID()
        if guid then
            local nid = GetNPCIDFromGUID(guid)
            local oid = GetObjectIDFromGUID(guid)
            if (nid and npcDropDB[nid] and tryCounterNpcEligible[nid]) or (oid and objectDropDB[oid]) then
                lastLootSourceGUID = guid
                lastLootSourceTime = GetTime()
            end
        else
            lastLootSourceGUID = nil
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if discoveryPendingNpcID then
            TryDiscoverLockoutQuest()
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
    [471021] = true,  -- Fishing (Midnight 12.0)
    [471008] = true,  -- Fishing (Midnight 12.0 PTR)
}

-- Pickpocket spell IDs (Rogue): opens loot window on a mob WITHOUT killing it.
-- LOOT_OPENED fires with isFromItem=false, fishingCtx.active=false → would fall through to
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

-- =====================================================================
-- STATE (file-local, zero global pollution)
-- =====================================================================

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
local encounterNameToNpcs = {}  -- [encounterName (enUS)] = { npcID1, ... } — Midnight: fallback when encounterID is secret
local lockoutQuestsDB = {}  -- [npcID] = questID or { questID1, questID2, ... }
-- Merged Statistics API columns per (collectibleType, tryKey): union LFR+N+H+M across DB rows & NPCs (e.g. G.M.O.D.).
local mergedStatSeedByTypeKey = {} -- [type .. "\0" .. key] = { tcType, tryKey, statIds, drops }
local mergedStatSeedGroupList = {} -- stable iteration order for SeedFromStatistics
local statSeedTryKeyPending = {}   -- drops with stat IDs but tryKey nil at seed time (API cold)

-- Runtime state
local recentKills = {}       -- [guid] = { npcID = n, name = s, time = t }
local processedGUIDs = {}    -- [guid] = timestamp
local mergedLootTryCountedAt = {}  -- [fingerprint] = GetTime() — open-world merged loot, one wave per GUID set
--- PLAYER_ENTERING_WORLD: GetInstanceInfo difficulty for current instanceID (ENCOUNTER_END can mismatch).
local tryCounterInstanceDiffCache = { instanceID = nil, difficultyID = nil }
--- Last character key we scheduled Statistics+Rarity sync for (avoids duplicate timers on same char).
local lastSyncScheduleCharKey = nil
--- Bumped when a new per-character sync is scheduled; stale C_Timer callbacks no-op.
local perCharStatSyncSerial = 0
--- Dedupe gray "Skipped" chat when LOOT_OPENED + LOOT_CLOSED both run ProcessNPCLoot.
local lastDifficultySkipChatKey = nil
local lastDifficultySkipChatTime = 0
local lastLockoutSkipChatKey = nil
local lastLockoutSkipChatTime = 0
local SKIP_CHAT_DEDUP_SEC = 15
local fishingCtx = {
    active = false,            -- set on fishing cast, cleared when fishing loot processed (or 30s timer)
    castTime = 0,              -- timestamp of last fishing cast
    lootWasFishing = false,    -- true after ProcessFishingLoot ran with trackable; LOOT_CLOSED only clears active then
    resetTimer = nil,          -- safety timer: auto-reset active after 30s (handles cancelled casts)
}
local FISHING_CAST_CONTEXT_TTL = 35 -- seconds: valid window for treating loot as fishing context
local isPickpocketing = false -- set on pickpocket cast, cleared on LOOT_CLOSED
local isProfessionLooting = false -- set on profession spell cast, cleared on LOOT_CLOSED
isBlockingInteractionOpen = false -- true when bank/vendor/AH/mail/trade UI is open
local lastContainerItemID = nil  -- set on container use
local lastContainerItemTime = 0  -- timestamp when container use/lock was observed (for LOOT_CLOSED fallback)
local resolvedIDs = {}       -- [itemID] = { type, collectibleID } - runtime resolved mount/pet IDs
local resolvedIDsReverse = {} -- [collectibleID] = itemID - reverse lookup for O(1) IndexLookup
local lockoutAttempted = {}  -- [questID] = true : tracks which lockout quests we've already counted this reset period
                             -- Keyed by questID (not npcID) so multiple NPCs sharing the same quest
                             -- (e.g. Arachnoid Harvester 154342/151934 both use quest 55512) are handled correctly.
-- When loot has 0 item slots (only rep/currency), GetLootSourceInfo has nothing to return; target may be cleared.
-- Cache last targeted GUID that is in our DB so we can still attribute the loot open and count the try.
lastLootSourceGUID = nil
lastLootSourceTime = 0
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

-- Forward declaration: defined later in file; used at top of OnTryCounterLootOpened.
local GetAllLootSourceGUIDs
-- Forward declarations: fishing helpers are used by handlers above their definitions.
local GetFishingTrackableForCurrentZone
local GetFishingDropItemIDsForCurrentZone
local IsInTrackableFishingZone

-- CHAT_MSG_LOOT fallback: itemID → npcID when loot window doesn't fire (direct loot, world boss, etc.).
-- Built from npcDropDB in BuildReverseIndices; hardcoded entries merged so they take precedence.
local chatLootItemToNpc = {}
local lastTryCountSourceKey = nil
local lastTryCountSourceTime = 0
--- Primary loot source GUID from the last try-counter NPC/object route (CLOSED-path debounce vs next corpse).
local lastTryCountLootSourceGUID = nil
local lastEncounterEndTime = 0  -- set on ANY successful ENCOUNTER_END (even unmatched); suppresses zone fallback
local CHAT_LOOT_DEBOUNCE = 2.0  -- seconds: avoid double-count if LOOT_OPENED and CHAT_MSG_LOOT both fire

local function IsTryCounterLootDebugEnabled(addon)
    return addon and addon.db and addon.db.profile and addon.db.profile.debugTryCounterLoot
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

---@param addon table
---@param cat string  Color category key (flow/match/skip/miss/count/reset)
---@param fmt string  Format string
---@param ... any     Format args
local function TryCounterLootDebug(addon, cat, fmt, ...)
    if not IsTryCounterLootDebugEnabled(addon) then return end
    local color = LOG_COLORS[cat] or "|cffcccccc"
    local n = select("#", ...)
    local msg = (n > 0) and string.format(tostring(fmt), ...) or tostring(fmt)
    addon:Print("|cff9370DB[TC]|r " .. color .. msg .. "|r")
end

local function CopyDropArray(drops)
    if type(drops) ~= "table" then return {} end
    local copy = {}
    for i = 1, #drops do
        copy[i] = drops[i]
    end
    if drops.statisticIds then copy.statisticIds = drops.statisticIds end
    if drops.dropDifficulty then copy.dropDifficulty = drops.dropDifficulty end
    return copy
end

local function CopyContainerMap(src)
    local out = {}
    for key, data in pairs(src or {}) do
        if type(data) == "table" and data.drops then
            out[key] = { drops = CopyDropArray(data.drops) }
        else
            out[key] = CopyDropArray(data)
        end
    end
    return out
end

local function CopyZoneMap(src)
    local out = {}
    for key, data in pairs(src or {}) do
        if type(data) == "table" and data.drops then
            out[key] = {
                drops = CopyDropArray(data.drops),
                raresOnly = data.raresOnly == true,
                hostileOnly = data.hostileOnly == true,
            }
        else
            out[key] = CopyDropArray(data)
        end
    end
    return out
end

local function CopyEncounterMap(src)
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

local function CopyKeyValueMap(src)
    local out = {}
    for key, value in pairs(src or {}) do
        out[key] = value
    end
    return out
end

local function LoadRuntimeSourceTables()
    local db = ns.CollectibleSourceDB
    if not db then
        npcDropDB, objectDropDB, fishingDropDB, containerDropDB = {}, {}, {}, {}
        zoneDropDB, encounterDB, encounterNameToNpcs, lockoutQuestsDB = {}, {}, {}, {}
        return
    end

    npcDropDB = {}
    for k, v in pairs(db.npcs or {}) do
        npcDropDB[k] = CopyDropArray(v)
    end
    for k, v in pairs(db.rares or {}) do
        if not npcDropDB[k] then
            npcDropDB[k] = CopyDropArray(v)
        end
    end

    objectDropDB = {}
    for k, v in pairs(db.objects or {}) do
        objectDropDB[k] = CopyDropArray(v)
    end

    fishingDropDB = CopyKeyValueMap(db.fishing or {})
    containerDropDB = CopyContainerMap(db.containers or {})
    zoneDropDB = CopyZoneMap(db.zones or {})
    encounterDB = CopyEncounterMap(db.encounters or {})
    encounterNameToNpcs = CopyEncounterMap(db.encounterNames or {})
    lockoutQuestsDB = CopyKeyValueMap(db.lockoutQuests or {})
end

--- Which NPC IDs may drive try-counter increments from corpse GUIDs, unit fallbacks, and CHAT_MSG_LOOT.
--- Merges: world rares, encounter bosses, CollectibleSourceDB.npcNameIndex (minus shared-trash denylist),
--- statistic/difficulty-gated entries, and trackDB custom NPCs.
local function BuildTryCounterNpcEligible()
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
    local function MergeChatLootItemToNpc(itemID, npcID)
        if not itemID or not npcID then return end
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
    -- Hardcoded overrides (e.g. known edge cases)
    chatLootItemToNpc[235910] = 234621  -- Mint Condition Gallagio Anniversary Coin → Gallagio Garbage

    -- Mount list UI / plans use journal mountID; IndexDrop keys are mount\0<itemID> (teach item).
    -- Mirror journal ID onto the same flags so IsDropSourceCollectible(plan.type, mountID) works (e.g. Zul'Aman rare mounts).
    if ns.EnsureBlizzardCollectionsLoaded then
        ns.EnsureBlizzardCollectionsLoaded()
    end
    local function MirrorOneMountJournalIndexKeys(drop)
        if not drop or drop.type ~= "mount" or not drop.itemID then return end
        local itemKey = "mount\0" .. tostring(drop.itemID)
        if not dropSourceIndex[itemKey] then return end
        local journalID = drop.mountID
        if not journalID and C_MountJournal and C_MountJournal.GetMountFromItem then
            journalID = C_MountJournal.GetMountFromItem(drop.itemID)
            if issecretvalue and journalID and issecretvalue(journalID) then journalID = nil end
        end
        journalID = journalID and tonumber(journalID) or nil
        if not journalID or journalID == tonumber(drop.itemID) then return end
        local jKey = "mount\0" .. tostring(journalID)
        dropSourceIndex[jKey] = true
        if guaranteedIndex[itemKey] then guaranteedIndex[jKey] = true end
        if repeatableIndex[itemKey] then repeatableIndex[jKey] = true end
        local diff = dropDifficultyIndex[itemKey]
        if diff then dropDifficultyIndex[jKey] = diff end
    end
    local function MirrorMountJournalKeysInArray(drops)
        if not drops then return end
        for i = 1, #drops do
            MirrorOneMountJournalIndexKeys(drops[i])
        end
    end
    for _, drops in pairs(npcDropDB) do MirrorMountJournalKeysInArray(drops) end
    for _, drops in pairs(objectDropDB) do MirrorMountJournalKeysInArray(drops) end
    for _, drops in pairs(fishingDropDB) do MirrorMountJournalKeysInArray(drops) end
    for _, zData in pairs(zoneDropDB) do
        local drops = zData.drops or zData
        MirrorMountJournalKeysInArray(drops)
    end
    for _, containerData in pairs(containerDropDB) do
        local list = containerData.drops or containerData
        if type(list) == "table" then
            local arr = list.drops or list
            if type(arr) == "table" then MirrorMountJournalKeysInArray(arr) end
        end
    end

    -- Pet journal uses speciesID; DB rows use pet\0<itemID>. Mirror species key for IsDropSourceCollectible / UI.
    local function MirrorOnePetSpeciesIndexKeys(drop)
        if not drop or drop.type ~= "pet" or not drop.itemID then return end
        local itemKey = "pet\0" .. tostring(drop.itemID)
        if not dropSourceIndex[itemKey] then return end
        local speciesID = drop.speciesID
        if not speciesID and C_PetJournal and C_PetJournal.GetPetInfoByItemID then
            local _, _, _, _, _, _, _, _, _, _, _, _, sid = C_PetJournal.GetPetInfoByItemID(drop.itemID)
            speciesID = sid
            if issecretvalue and speciesID and issecretvalue(speciesID) then speciesID = nil end
        end
        speciesID = speciesID and tonumber(speciesID) or nil
        if not speciesID or speciesID == tonumber(drop.itemID) then return end
        local sKey = "pet\0" .. tostring(speciesID)
        dropSourceIndex[sKey] = true
        if guaranteedIndex[itemKey] then guaranteedIndex[sKey] = true end
        if repeatableIndex[itemKey] then repeatableIndex[sKey] = true end
        local diff = dropDifficultyIndex[itemKey]
        if diff then dropDifficultyIndex[sKey] = diff end
    end
    local function MirrorPetSpeciesKeysInArray(drops)
        if not drops then return end
        for i = 1, #drops do
            MirrorOnePetSpeciesIndexKeys(drops[i])
        end
    end
    for _, drops in pairs(npcDropDB) do MirrorPetSpeciesKeysInArray(drops) end
    for _, drops in pairs(objectDropDB) do MirrorPetSpeciesKeysInArray(drops) end
    for _, drops in pairs(fishingDropDB) do MirrorPetSpeciesKeysInArray(drops) end
    for _, zData in pairs(zoneDropDB) do
        local drops = zData.drops or zData
        MirrorPetSpeciesKeysInArray(drops)
    end
    for _, containerData in pairs(containerDropDB) do
        local list = containerData.drops or containerData
        if type(list) == "table" then
            local arr = list.drops or list
            if type(arr) == "table" then MirrorPetSpeciesKeysInArray(arr) end
        end
    end

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

---Mark a non-repeatable drop item as obtained so IsCollectibleCollected stops
---tracking it even when the WoW collection API can't confirm yet (e.g. egg
---hatch timers, unresolvable mountIDs).
---@param itemID number
local function MarkItemObtained(itemID)
    if not itemID or not EnsureDB() then return end
    WarbandNexus.db.global.tryCounts.obtained[itemID] = true
end

---Check if a drop item was previously marked as obtained.
---@param itemID number
---@return boolean
local function IsItemMarkedObtained(itemID)
    if not itemID then return false end
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return false end
    local tc = WarbandNexus.db.global.tryCounts
    return tc and tc.obtained and tc.obtained[itemID] == true
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
    local idNum = tonumber(id)
    if idNum then id = idNum end
    -- Quest Starter = Mount Item = Mount: try count = statistic + local stored
    if collectibleType == "mount" then
        local sourceItemID = questStarterMountToSourceItemID[id] or (idNum and questStarterMountToSourceItemID[idNum])
        if not sourceItemID and C_MountJournal and C_MountJournal.GetMountFromItem then
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
            local localStored = type(itemCount) == "number" and itemCount or 0
            local mountCounts = WarbandNexus.db.global.tryCounts.mount
            if mountCounts then
                -- Check all known keys for this quest-starter mount (itemID, mountID, resolved ID)
                -- to find the highest stored count. Covers legacy data stored under different keys.
                local m1 = type(mountCounts[id]) == "number" and mountCounts[id] or 0
                if m1 > localStored then localStored = m1 end
                -- Check all reverse-mapped keys for this source item (covers itemID/mountID variants)
                for mappedKey, srcID in pairs(questStarterMountToSourceItemID) do
                    if srcID == sourceItemID and mappedKey ~= id then
                        local mv = type(mountCounts[mappedKey]) == "number" and mountCounts[mappedKey] or 0
                        if mv > localStored then localStored = mv end
                    end
                end
            end
            return localStored
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
    if not EnsureDB() then return 0 end
    delta = tonumber(delta) or 0
    if delta <= 0 then return WarbandNexus:GetTryCount(collectibleType, id) end
    local stored = WarbandNexus.db.global.tryCounts[collectibleType][id]
    local currentStored = type(stored) == "number" and stored or 0
    WarbandNexus.db.global.tryCounts[collectibleType][id] = currentStored + delta
    return WarbandNexus:GetTryCount(collectibleType, id)
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

---Mark a drop item as obtained so the try counter stops tracking it.
---Useful for items with delayed yields (e.g. Nether-Warped Egg with 7-day hatch)
---or when the WoW collection API can't resolve the mount/pet ID.
---@param itemID number The item ID of the drop to mark
function WarbandNexus:MarkItemObtained(itemID)
    MarkItemObtained(itemID)
end

---Check if a drop item has been marked as obtained.
---@param itemID number
---@return boolean
function WarbandNexus:IsItemObtained(itemID)
    return IsItemMarkedObtained(itemID)
end

---Clear the obtained marker for a drop item (e.g. if marked by mistake).
---@param itemID number
function WarbandNexus:ClearItemObtained(itemID)
    if not itemID or not EnsureDB() then return end
    WarbandNexus.db.global.tryCounts.obtained[itemID] = nil
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

---Extract NPC ID from a creature/vehicle GUID (retail GUIDs have variable segment counts;
---the old %-.-%-.-…%-(%d+) pattern often grabbed map/instance ids instead of the entry id).
---@param guid string
---@return number|nil npcID
GetNPCIDFromGUID = function(guid)
    if not guid or type(guid) ~= "string" then return nil end
    -- Midnight 12.0: GUID may be a secret value during instanced combat
    if issecretvalue and issecretvalue(guid) then return nil end
    local parts = { strsplit("-", guid) }
    local unitType = parts[1]
    if unitType ~= "Creature" and unitType ~= "Vehicle" then
        return nil
    end
    local n = #parts
    if n < 3 then return nil end
    local last = parts[n]
    -- Final segment is usually hex spawn UID; entry id is the preceding numeric field.
    if last and last:match("^[0-9A-Fa-f]+$") and #last >= 10 then
        local pen = tonumber(parts[n - 1])
        if pen and pen > 0 then return pen end
    end
    if n >= 7 then
        local id6 = tonumber(parts[6])
        if id6 and id6 > 0 then return id6 end
    end
    if n >= 6 then
        local id5 = tonumber(parts[5])
        if id5 and id5 > 0 then return id5 end
    end
    local ut, npcID = guid:match("^(%a+)%-.-%-.-%-.-%-.-%-(%d+)")
    if ut == unitType and npcID then
        return tonumber(npcID)
    end
    return nil
end

---Extract object ID from a GameObject GUID (same segment rules as Creature).
---@param guid string
---@return number|nil objectID
GetObjectIDFromGUID = function(guid)
    if not guid or type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    local parts = { strsplit("-", guid) }
    if parts[1] ~= "GameObject" then
        return nil
    end
    local n = #parts
    if n < 3 then return nil end
    local last = parts[n]
    if last and last:match("^[0-9A-Fa-f]+$") and #last >= 10 then
        local pen = tonumber(parts[n - 1])
        if pen and pen > 0 then return pen end
    end
    if n >= 7 then
        local id6 = tonumber(parts[6])
        if id6 and id6 > 0 then return id6 end
    end
    if n >= 6 then
        local id5 = tonumber(parts[5])
        if id5 and id5 > 0 then return id5 end
    end
    local ut, objectID = guid:match("^(%a+)%-.-%-.-%-.-%-.-%-(%d+)")
    if ut == "GameObject" and objectID then
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
        resolvedIDsReverse[id] = drop.itemID
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

---Get the (type, key) to use for try count storage/display for a drop.
---When drop has tryCountReflectsTo (e.g. Nether-Warped Egg -> Nether-Warped Drake), returns the
---reflected type and key so the count is stored on the mount and shown in mount UI.
---@param drop table { type, itemID, name [, tryCountReflectsTo = { type, itemID [, name ] } ] }
---@return string|nil collectibleType "mount"|"pet"|"toy"|"item"
---@return number|nil tryCountKey
local function GetTryCountTypeAndKey(drop)
    if not drop then return nil, nil end
    if drop.tryCountReflectsTo and drop.tryCountReflectsTo.type and drop.tryCountReflectsTo.itemID then
        local ref = drop.tryCountReflectsTo
        local key = ResolveCollectibleID(ref) or ref.itemID
        return ref.type, key
    end
    local key = GetTryCountKey(drop)
    return drop.type, key
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

---Resolve difficultyID when GetInstanceInfo() returns 0 (seen in Midnight / some dungeons).
---M+ → 8; else GetDungeonDifficultyID / GetRaidDifficultyID.
---@param instanceType string|nil "party"|"raid"|...
---@param giDifficulty number|nil GetInstanceInfo() 3rd return
---@return number|nil
local function ResolveLiveInstanceDifficultyID(instanceType, giDifficulty)
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

---Effective difficulty for loot gating while inside an instance.
---Order: (1) cache from instance entry + matching instanceID, (2) live GetInstanceInfo,
---(3) ENCOUNTER_END snapshot, (4) GetDungeon/GetRaidDifficultyID.
---@param inInstance boolean|nil
---@param recentKillDiff number|nil difficulty from recentKills (ENCOUNTER_END snapshot)
---@return number|nil
local function ResolveEffectiveEncounterDifficultyID(inInstance, recentKillDiff)
    if inInstance then
        local _, typ, liveDiff, _, _, _, _, iid = GetInstanceInfo()
        local safeIid = iid
        if safeIid and issecretvalue and issecretvalue(safeIid) then safeIid = nil end
        local safeLive = liveDiff
        if safeLive and issecretvalue and issecretvalue(safeLive) then safeLive = nil end
        local resolvedLive = ResolveLiveInstanceDifficultyID(typ, safeLive)
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

---Trackable drops for NPC/encounter tables after difficulty gating (same rules as ProcessNPCLoot).
---@param drops table npcDropDB entry
---@param encounterDiffID number|nil
---@return table
---@return table|nil first skipped drop info { drop, required } for user messaging
local function FilterDropsByDifficulty(drops, encounterDiffID)
    local trackable = {}
    local diffSkipped = nil
    if not drops then return trackable, diffSkipped end
    local npcDropDifficulty = drops.dropDifficulty
    for i = 1, #drops do
        local drop = drops[i]
        local reqDiff = drop.dropDifficulty or npcDropDifficulty
        local diffOk = true
        if reqDiff and encounterDiffID then
            diffOk = DoesDifficultyMatch(encounterDiffID, reqDiff)
        end
        if diffOk then
            if drop.repeatable or not IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        elseif not diffSkipped then
            diffSkipped = { drop = drop, required = reqDiff }
        end
    end
    return trackable, diffSkipped
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
IsCollectibleCollected = function(drop)
    if not drop then return false end

    local collectibleID = ResolveCollectibleID(drop)

    if drop.type == "item" then
        -- Short-circuit: if this item was already found in loot and marked as
        -- obtained (e.g. Nether-Warped Egg fished but mount still hatching),
        -- skip the yield/API check entirely.
        if IsItemMarkedObtained(drop.itemID) then return true end

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
                if not IsCollectibleCollected(yieldDrop) then
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

---Scan loot window and return set of found itemIDs.
---When cachedNumLoot and cachedSlotData are provided (from LOOT_OPENED capture), uses them so we don't re-read the window.
---@param expectedDrops table Array of drop entries
---@param cachedNumLoot number|nil Optional: use this instead of GetNumLootItems()
---@param cachedSlotData table|nil Optional: [i] = { hasItem = bool, link = string|nil }
---@return table foundItemIDs Set of itemIDs found in loot { [itemID] = true }
local function ScanLootForItems(expectedDrops, cachedNumLoot, cachedSlotData)
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
        else
            hasItem = LootSlotHasItem and LootSlotHasItem(i)
            link = GetLootSlotLink and GetLootSlotLink(i)
            if link and issecretvalue and issecretvalue(link) then link = nil end
        end
        if hasItem and link then
            local itemID = GetItemInfoInstant(link)
            if itemID and expectedSet[itemID] then
                found[itemID] = true
            end
        end
    end

    return found
end

-- =====================================================================
-- TRY COUNT INCREMENT + CHAT MESSAGE
-- =====================================================================

---Get the item hyperlink (quality-colored) for a drop entry.
---Uses full link from GetItemInfo when cached (quality color comes from link). Falls back to constructed link with quality color when not cached.
---@param drop table { type, itemID, name }
---@return string displayLink Formatted item link (clickable)
local function GetDropItemLink(drop)
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

---True if NPC drop entry has statisticIds at NPC level or on any drop row (per-difficulty stats).
---@param npcData table
---@return boolean
local function NpcEntryHasStatisticIds(npcData)
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

---@param drop table
---@param npcStatIds table|nil
---@return table|nil
local function ResolveReseedStatIdsForDrop(drop, npcStatIds)
    if drop and drop.statisticIds and #drop.statisticIds > 0 then
        return drop.statisticIds
    end
    return npcStatIds
end

---Sum GetStatistic values for a list of statistic IDs (LFR+N+H+M columns, deduped upstream).
---@param statIds table|nil
---@return number
local function SumStatisticTotalsFromIds(statIds)
    if not statIds or #statIds == 0 then return 0 end
    local GetStat = GetStatistic
    if not GetStat then return 0 end
    local total = 0
    for i = 1, #statIds do
        local sid = statIds[i]
        local val = GetStat(sid)
        local num
        if val and not (issecretvalue and issecretvalue(val)) then
            local s = string.gsub(tostring(val), "[^%d]", "")
            if s ~= "" then
                num = tonumber(s)
            end
        end
        if num and num > 0 then
            total = total + num
        end
    end
    return total
end

---Rebuild merge index: one bucket per (tcType, tryKey) with union of all statisticIds from every
---npcDropDB row that maps to that collectible (e.g. G.M.O.D.: Jaina LFR + Mekkatorque N/H/M).
local function RebuildMergedStatisticSeedIndex()
    wipe(mergedStatSeedByTypeKey)
    wipe(mergedStatSeedGroupList)
    wipe(statSeedTryKeyPending)
    if not npcDropDB then return end
    for _, npcData in pairs(npcDropDB) do
        local npcStatIds = npcData.statisticIds
        for idx = 1, #npcData do
            local drop = npcData[idx]
            if type(drop) == "table" and drop.type and drop.itemID and not drop.guaranteed then
                local sids = ResolveReseedStatIdsForDrop(drop, npcStatIds)
                if sids and #sids > 0 then
                    local tcType, tryKey = GetTryCountTypeAndKey(drop)
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
end

---Prefer merged cross-difficulty / cross-NPC stat ID set; else per-drop + npc fallback (ProcessMissedDrops).
---@param drop table
---@param resolvedDropStatIds table|nil
---@return table|nil statIds
local function ResolveMergedStatisticIdsForDrop(drop, resolvedDropStatIds)
    local tcType, tryKey = GetTryCountTypeAndKey(drop)
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

--- Remove statisticSnapshots rows with no matching db.global.characters entry (deleted alts).
--- Prevents inflated global totals when summing snapshots across characters.
local function PruneStatisticSnapshotsOrphanKeys()
    if not EnsureDB() then return end
    local db = WarbandNexus.db.global
    local snaps = db.statisticSnapshots
    local chars = db.characters
    if not snaps or not chars or type(snaps) ~= "table" or type(chars) ~= "table" then return end
    local nChar = 0
    for _ in pairs(chars) do
        nChar = nChar + 1
    end
    if nChar == 0 then return end
    local removed = 0
    for ck in pairs(snaps) do
        if not chars[ck] then
            snaps[ck] = nil
            removed = removed + 1
        end
    end
    if removed > 0 then
        WarbandNexus:Debug("TryCounter: Pruned %d orphan statisticSnapshots (no characters entry)", removed)
    end
end

---Re-read WoW Statistics for specific drops and update try counts.
---Uses merged stat columns per collectible (all difficulties / all NPC sources). Never decreases stored count.
---@param drops table Array of drop entries to re-seed
---@param resolvedDropStatIds table|nil From ResolveReseedStatIdsForDrop(drop, npc.statisticIds) for this row
local function ReseedStatisticsForDrops(drops, resolvedDropStatIds)
    if not drops or #drops == 0 then return end
    if not EnsureDB() then return end
    if not GetStatistic then return end

    RebuildMergedStatisticSeedIndex()

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
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

    local function ProcessSeedDrop(drop, statListOverride)
        if drop and not drop.guaranteed then
            local statList = statListOverride or ResolveMergedStatisticIdsForDrop(drop, resolvedDropStatIds)
            if not statList or #statList == 0 then return end
            local thisCharTotal = SumStatisticTotalsFromIds(statList)
            local tcType, tryKey = GetTryCountTypeAndKey(drop)
            if tryKey and tcType then
                charSnapshot[tryKey] = thisCharTotal
                local globalTotal = 0
                for _, snap in pairs(snapshots) do
                    local charVal = snap[tryKey]
                    if charVal and charVal > 0 then
                        globalTotal = globalTotal + charVal
                    end
                end
                local currentCount = WarbandNexus:GetTryCount(tcType, tryKey) or 0
                local newCount = globalTotal > currentCount and globalTotal or currentCount
                WarbandNexus:SetTryCount(tcType, tryKey, newCount)

                if drop.type == "item" and drop.questStarters then
                    for i = 1, #drop.questStarters do
                        local qs = drop.questStarters[i]
                        if qs.type == "mount" and qs.itemID then
                            local mountKey1 = ResolveCollectibleID(qs)
                            local mountKey2 = qs.itemID
                            local mk = mountKey1 or mountKey2
                            WarbandNexus:SetTryCount("mount", mk, math.max(newCount, WarbandNexus:GetTryCount("mount", mk) or 0))
                            if mountKey1 and mountKey1 ~= mountKey2 then
                                WarbandNexus:SetTryCount("mount", mountKey2, math.max(newCount, WarbandNexus:GetTryCount("mount", mountKey2) or 0))
                            end
                            questStarterMountToSourceItemID[mk] = drop.itemID
                            if mountKey1 and mountKey1 ~= mountKey2 then
                                questStarterMountToSourceItemID[mountKey2] = drop.itemID
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
        WarbandNexus:SendMessage("WN_PLANS_UPDATED", { action = "statistics_reseeded" })
    end
end

---@param drops table
---@param npcStatIds table|nil
---@return boolean
local function DropsHaveStatBackedReseed(drops, npcStatIds)
    for i = 1, #drops do
        local sids = ResolveReseedStatIdsForDrop(drops[i], npcStatIds)
        if sids and #sids > 0 then return true end
    end
    return false
end

---Increment try count and print chat message for unfound drops.
---TRY COUNT RULE: Guaranteed drops excluded. NPC corpse/CHAT use tryCounterNpcEligible;
---containers/objects/fishing/zone rare pools unchanged.
---DEFERRED: Runs on next frame via C_Timer.After(0) to avoid blocking loot frame.
---Counter increments and chat messages don't need to be synchronous.
---
---For bosses with statisticIds: re-seeds from Statistics unless every missed drop is
---repeatable (farm) — then manual +attemptTimes (stats are not per-corpse tries).
---@param drops table Array of drop entries that were NOT found in loot
---@param statIds table|nil Optional statisticIds from the NPC source
---@param options table|nil Optional { attemptTimes = number }
local function ProcessMissedDrops(drops, statIds, options)
    if not drops or #drops == 0 then return end
    if not EnsureDB() then return end
    local attemptTimes = options and tonumber(options.attemptTimes) or 1
    if attemptTimes < 1 then attemptTimes = 1 end

    local allRepeatableMisses = true
    for i = 1, #drops do
        if not drops[i].repeatable then
            allRepeatableMisses = false
            break
        end
    end

    if DropsHaveStatBackedReseed(drops, statIds) and not allRepeatableMisses then
        C_Timer.After(2, function()
            for i = 1, #drops do
                local drop = drops[i]
                local sids = ResolveReseedStatIdsForDrop(drop, statIds)
                if sids and #sids > 0 then
                    ReseedStatisticsForDrops({ drop }, sids)
                end
            end
        end)
        return
    end

    C_Timer.After(0, function()
        if not EnsureDB() then return end
        local WN = WarbandNexus
        local function MirrorQuestStarterMountsToCount(drop, newCount)
            if drop.type ~= "item" or not drop.questStarters or drop.tryCountReflectsTo then return end
            for qi = 1, #drop.questStarters do
                local qs = drop.questStarters[qi]
                if qs.type == "mount" and qs.itemID then
                    local k1 = ResolveCollectibleID(qs)
                    local k2 = qs.itemID
                    WN:SetTryCount("mount", k1 or k2, newCount)
                    if k1 and k1 ~= k2 then
                        WN:SetTryCount("mount", k2, newCount)
                    end
                    questStarterMountToSourceItemID[k1 or k2] = drop.itemID
                    if k1 and k1 ~= k2 then questStarterMountToSourceItemID[k2] = drop.itemID end
                end
            end
        end

        local function ProcessManualDrop(drop, mult)
            mult = tonumber(mult) or attemptTimes
            if mult < 1 then mult = 1 end
            if drop and not drop.guaranteed then
                local tcType, tryKey = GetTryCountTypeAndKey(drop)
                if tryKey then
                    -- Increments only (no per-attempt chat — use UI / plans; milestones still print via Obtained paths).
                    for step = 1, mult do
                        local newCount = WN:AddTryCountDelta(tcType, tryKey, 1)
                        MirrorQuestStarterMountsToCount(drop, newCount)
                        if IsTryCounterLootDebugEnabled(WN) and mult > 1 then
                            TryCounterLootDebug(WN, "count", "try +1 step %d/%d (total %d)", step, mult, newCount)
                        end
                    end
                end
            end
            if drop and drop.questStarters then
                for i = 1, #drop.questStarters do
                    local qs = drop.questStarters[i]
                    if not (drop.type == "item" and qs.type == "mount") then
                        ProcessManualDrop(qs, 1)
                    end
                end
            end
        end

        for i = 1, #drops do
            ProcessManualDrop(drops[i], attemptTimes)
        end
        if WN.SendMessage then
            WN:SendMessage("WN_PLANS_UPDATED", { action = "try_count_set" })
        end
    end)
end

-- =====================================================================
-- SETTING CHECK
-- =====================================================================

---Check if auto try counter is enabled (module toggle AND notification setting must both be on)
---@return boolean
local function IsAutoTryCounterEnabled()
    if not WarbandNexus or not WarbandNexus.db then return false end
    if not WarbandNexus.db.profile then return false end
    if WarbandNexus.db.profile.modulesEnabled and WarbandNexus.db.profile.modulesEnabled.tryCounter == false then return false end
    if not WarbandNexus.db.profile.notifications then return false end
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
-- LOCKOUT QUEST AUTO-DISCOVERY
-- =====================================================================
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

local function GetClaimedQuestIDs()
    local claimed = {}
    for _, questData in pairs(lockoutQuestsDB) do
        local qids = type(questData) == "table" and questData or { questData }
        for i = 1, #qids do claimed[qids[i]] = true end
    end
    return claimed
end

local function TakeDiscoverySnapshot()
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

TryDiscoverLockoutQuest = function()
    if not discoveryPendingNpcID then return end
    if GetTime() - discoveryPendingTime > DISCOVERY_PENDING_TTL then
        discoveryPendingNpcID = nil
        TakeDiscoverySnapshot()
        return
    end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then
        discoveryPendingNpcID = nil
        return
    end

    local claimed = GetClaimedQuestIDs()
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
    TakeDiscoverySnapshot()
end

local function MergeDiscoveredLockoutQuests()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    local disc = WarbandNexus.db.global.discoveredLockoutQuests
    if type(disc) ~= "table" then return end
    for npcID, questID in pairs(disc) do
        if not lockoutQuestsDB[npcID] then
            lockoutQuestsDB[npcID] = questID
        end
    end
end

-- =====================================================================
-- EVENT HANDLERS
-- =====================================================================

---ENCOUNTER_END handler for instanced bosses
---NOTE: Event arguments passed via RegisterEvent are NOT secret values.
---Only CombatLogGetCurrentEventInfo() returns secrets during instanced combat.
---This handler is the primary instanced kill detection path when loot GUIDs are unreliable.
---@param event string
---@param encounterID number
---@param encounterName string
---@param difficultyID number
---@param groupSize number
---@param success number 1 = killed, 0 = wipe
function WarbandNexus:OnTryCounterEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize, success)
    if not IsAutoTryCounterEnabled() then return end
    if success ~= 1 then return end -- Only on successful kills

    -- Record timestamp BEFORE DB lookup. Suppresses zone-based fallback in ProcessNPCLoot
    -- for encounters not in our DB (e.g. Commander Kroluk in March on Quel'Danas) that would
    -- otherwise falsely match zone rare-mount drops in the same map region.
    lastEncounterEndTime = GetTime()

    local npcIDs = nil
    local encounterKey = nil
    local useNameFallback = false
    local function TryResolveEncounterNPCFromLastTarget()
        -- Fallback for encounters not present in encounterDB/encounterNameToNpcs:
        -- if we recently had a valid tracked target GUID, attribute this kill to that NPC.
        -- This is especially important for custom tracked bosses and new patch encounters.
        if not lastLootSourceGUID then return nil end
        if not lastLootSourceTime or (GetTime() - lastLootSourceTime) > 120 then return nil end
        local fallbackNpcID = GetNPCIDFromGUID(lastLootSourceGUID)
        if not fallbackNpcID then return nil end
        if not tryCounterNpcEligible[fallbackNpcID] then return nil end
        if not npcDropDB[fallbackNpcID] then return nil end
        return fallbackNpcID
    end

    -- Midnight 12.0: encounterID can be secret in dungeons; cannot use as table key or tostring().
    if issecretvalue and encounterID and issecretvalue(encounterID) then
        -- Fallback: resolve by encounter name (enUS keys in encounterNameToNpcs; other locales need entries).
        if encounterName and (not issecretvalue or not issecretvalue(encounterName)) and encounterNameToNpcs[encounterName] then
            npcIDs = encounterNameToNpcs[encounterName]
            encounterKey = "name_" .. encounterName
            useNameFallback = true
            if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "flow", "ENC name='%s' npcs=%d (secret ID)", encounterName, #npcIDs) end
        else
            local fallbackNpcID = TryResolveEncounterNPCFromLastTarget()
            if fallbackNpcID then
                npcIDs = { fallbackNpcID }
                encounterKey = "fallback_target_" .. tostring(fallbackNpcID)
                useNameFallback = true
                if IsTryCounterLootDebugEnabled(self) then
                    TryCounterLootDebug(self, "flow", "ENC secret ID fallback target npc=%s", tostring(fallbackNpcID))
                end
            else
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "ENC secret ID, no name/target match") end
                return
            end
        end
    else
        npcIDs = encounterDB[encounterID]
        if not npcIDs then
            local fallbackNpcID = TryResolveEncounterNPCFromLastTarget()
            if fallbackNpcID then
                npcIDs = { fallbackNpcID }
                encounterKey = "fallback_target_" .. tostring(fallbackNpcID)
                useNameFallback = true
                if IsTryCounterLootDebugEnabled(self) then
                    TryCounterLootDebug(self, "flow", "ENC %s fallback target npc=%s", tostring(encounterID), tostring(fallbackNpcID))
                end
            else
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "ENC %s not in DB", tostring(encounterID)) end
                return
            end
        else
            if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "flow", "ENC %s npcs=%d", tostring(encounterID), #npcIDs) end
            encounterKey = "encounter_" .. tostring(encounterID)
        end
    end

    -- Check if this encounter was already processed in last 10 seconds (prevent double-counting)
    local now = GetTime()
    if lastTryCountSourceKey == encounterKey and (now - lastTryCountSourceTime) < 10 then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "ENC %s already counted", tostring(encounterID)) end
        return
    end

    -- Feed localized encounter name to TooltipService for name-based tooltip lookup.
    -- ENCOUNTER_END args are NOT secret values — encounterName is always the correct
    -- localized string. This is the critical fallback for Midnight instances where
    -- UnitGUID is secret AND EJ API may be restricted. When encounterID is secret we pass
    -- npcIDs so TooltipService can still populate nameDropCache/nameNpcIDCache by name.
    if self.Tooltip and self.Tooltip._feedEncounterKill then
        local safeEncID = (not useNameFallback and encounterID and (not issecretvalue or not issecretvalue(encounterID))) and encounterID or nil
        local npcIDsForFeed = (safeEncID == nil and useNameFallback and npcIDs and #npcIDs > 0) and npcIDs or nil
        self.Tooltip._feedEncounterKill(encounterName, safeEncID, npcIDsForFeed)
    end

    -- Create synthetic kill entries for eligible encounter NPCs only.
    local addedCount = 0
    for i = 1, #npcIDs do
        local npcID = npcIDs[i]
        if tryCounterNpcEligible[npcID] and npcDropDB[npcID] then
            local syntheticGUID = useNameFallback
                and ("Encounter-Name-" .. (encounterName or "") .. "-" .. npcID .. "-" .. now)
                or ("Encounter-" .. tostring(encounterID) .. "-" .. npcID .. "-" .. now)
            local safeDiffID = difficultyID
            if issecretvalue and safeDiffID and issecretvalue(safeDiffID) then safeDiffID = nil end
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
    if IsTryCounterLootDebugEnabled(self) and addedCount > 0 then TryCounterLootDebug(self, "flow", "ENC recentKills +%d", addedCount) end

    -- DELAYED FALLBACK: If no loot window opens within 5s, manually increment try counters.
    -- Global debounce prevents double-count vs LOOT_OPENED/CHAT_MSG_LOOT paths.
    if addedCount > 0 then
        local keyForDelayed = encounterKey
        C_Timer.After(5, function()
            if not IsAutoTryCounterEnabled() then return end
            local delayedNow = GetTime()
            if lastTryCountSourceKey and (delayedNow - lastTryCountSourceTime) < 10 then
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "ENC delayed: already counted (%s)", tostring(lastTryCountSourceKey)) end
                return
            end

            local matchedNpcID = nil
            local trackable = {}
            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and (delayedNow - killData.time < 10) and tryCounterNpcEligible[killData.npcID] then
                    local drops = npcDropDB[killData.npcID]
                    if drops then
                        matchedNpcID = killData.npcID
                        local inInst = IsInInstance()
                        if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
                        local encDiff = ResolveEffectiveEncounterDifficultyID(inInst, killData.difficultyID)
                        trackable = FilterDropsByDifficulty(drops, encDiff)
                        break
                    end
                end
            end

            if #trackable > 0 and matchedNpcID then
                lastTryCountSourceKey = keyForDelayed
                lastTryCountSourceTime = delayedNow
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "count", "ENC delayed: npc %s +%d", tostring(matchedNpcID), #trackable) end
                ProcessMissedDrops(trackable, npcDropDB[matchedNpcID].statisticIds)
            end

            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and (delayedNow - killData.time < 10) then recentKills[guid] = nil end
            end
        end)
    end
    
    -- DEFERRED RETRY: If a chest was opened BEFORE this encounter ended (RP/cinematic timing),
    -- ProcessNPCLoot found no drops because recentKills was empty. Now that we've added
    -- the encounter entries, retry processing. Short delay ensures loot window state is stable.
    if self._pendingEncounterLoot then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "flow", "ENC pending retry 0.5s") end
        self._pendingEncounterLoot = nil
        self._pendingEncounterLootRetried = true
        C_Timer.After(0.5, function()
            self._pendingEncounterLootRetried = nil
            self:ProcessNPCLoot()
        end)
    end
end

-- =====================================================================
-- INSTANCE ENTRY (Encounter Journal helpers kept for debug / TryCounterShowInstanceDrops if invoked manually)
-- Automatic chat dump on zone-in was removed — it spammed chat; use the addon UI or /wn check.
-- =====================================================================

local function TryCounterLoadEncounterJournal()
    if InCombatLockdown() then return end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Blizzard_EncounterJournal")
    end
end

---True if we can select a journal instance and iterate encounters (after Blizzard_EncounterJournal load).
local function TryCounterEJ_HasCoreAPIs()
    return EJ_SelectInstance and EJ_GetEncounterInfoByIndex
        and (EJ_GetCurrentInstance or EJ_GetInstanceForMap)
end

---@param encIndex number 1-based EJ boss index within the instance
---@param journalInstanceID number JournalInstance.ID (pass through to ByIndex for stable rows)
---@return string|nil encName
---@return number|nil dungeonEncounterID keys encounterDB / ENCOUNTER_END
local function TryCounterResolveDungeonEncounterFromEJIndex(encIndex, journalInstanceID)
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
    if EJ_GetEncounterInfo and journalEncID and type(journalEncID) == "number" and journalEncID > 0 then
        -- Returns: name, desc, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID, instanceID
        local okInfo, _, _, _, _, _, dex = pcall(EJ_GetEncounterInfo, journalEncID)
        if okInfo and dex and type(dex) == "number" and dex > 0 then
            if not (issecretvalue and issecretvalue(dex)) then
                dungeonEncID = dex
            end
        end
    end
    return encName, dungeonEncID
end

--- Instance-entry chat / debug: mount collectibles only (direct mount or item→mount chain).
local function ResolveTryCounterMountAnnounceDrop(drop)
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

---Journal instance ID for the player's current position. Prefer EJ_GetInstanceForMap(uiMapID) — EJ_GetCurrentInstance was superseded in 8.0.1.
---@return number|nil
local function TryCounterGetJournalInstanceID()
    local jid
    if EJ_GetCurrentInstance then
        jid = EJ_GetCurrentInstance()
    end
    if (not jid or jid == 0) and EJ_GetInstanceForMap and C_Map and C_Map.GetBestMapForUnit then
        local mapID = C_Map.GetBestMapForUnit("player")
        if mapID and not (issecretvalue and issecretvalue(mapID)) then
            jid = EJ_GetInstanceForMap(mapID)
        end
    end
    if jid == 0 then jid = nil end
    return jid
end

---PLAYER_ENTERING_WORLD handler (instance difficulty cache, fishing reset, statistics sync)
function WarbandNexus:OnTryCounterInstanceEntry(event, isInitialLogin, isReloadingUi)
    -- Statistics + Rarity: re-sync when character changes or UI reload (not every zone hop).
    if tryCounterReady then
        local k = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
        if k then
            if k ~= lastSyncScheduleCharKey or isReloadingUi then
                lastSyncScheduleCharKey = k
                SchedulePerCharacterStatisticsAndRaritySync()
            end
        end
    end

    if not IsAutoTryCounterEnabled() then return end

    -- Refresh safe map cache on zone transitions (login, reload, instance entry/exit)
    GetSafeMapID()

    local inInstance, instanceType = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if issecretvalue and instanceType and issecretvalue(instanceType) then instanceType = nil end
    if not inInstance then
        tryCounterInstanceDiffCache.instanceID = nil
        tryCounterInstanceDiffCache.difficultyID = nil
        for guid, data in pairs(recentKills) do
            if data.isEncounter then
                recentKills[guid] = nil
            end
        end
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
        local resolved = ResolveLiveInstanceDifficultyID(instanceType, gi)
        if sid then
            tryCounterInstanceDiffCache.instanceID = sid
            tryCounterInstanceDiffCache.difficultyID = resolved
                or (type(gi) == "number" and gi > 0 and gi)
                or nil
        end
    end

    if IsTryCounterLootDebugEnabled(self) then
        self:TryCounterDebugInstanceProbe()
    end

    -- Clear fishing context on instance entry (prevents false fishing counts in Delves)
    fishingCtx.active = false
    fishingCtx.castTime = 0
    if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() fishingCtx.resetTimer = nil end
end

---When debugTryCounterLoot is on: immediate GetInstanceInfo + cache snapshot; deferred EJ walk vs encounterDB/npcDropDB with FilterDropsByDifficulty (same as loot path).
function WarbandNexus:TryCounterDebugInstanceProbe()
    if not IsTryCounterLootDebugEnabled(self) then return end
    local inInst = IsInInstance()
    if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
    if not inInst then return end

    local name, instType, diffID, _, _, _, _, mapInstID = GetInstanceInfo()
    if name and issecretvalue and issecretvalue(name) then name = nil end
    if instType and issecretvalue and issecretvalue(instType) then instType = nil end
    if diffID and issecretvalue and issecretvalue(diffID) then diffID = nil end
    if mapInstID and issecretvalue and issecretvalue(mapInstID) then mapInstID = nil end

    local uiMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if uiMapID and issecretvalue and issecretvalue(uiMapID) then uiMapID = nil end
    local ddApi = GetDungeonDifficultyID and GetDungeonDifficultyID()
    if ddApi and issecretvalue and issecretvalue(ddApi) then ddApi = nil end
    local rdApi = GetRaidDifficultyID and GetRaidDifficultyID()
    if rdApi and issecretvalue and issecretvalue(rdApi) then rdApi = nil end

    local encDiff = ResolveEffectiveEncounterDifficultyID(true, nil)
    local diffLabel = (encDiff and DIFFICULTY_ID_TO_LABELS[encDiff]) or "?"
    TryCounterLootDebug(self, "flow",
        "ENTER name=%s type=%s mapInstanceID=%s uiMapID=%s liveDiffID=%s | resolvedDiffID=%s (%s) | cache instanceID=%s diffID=%s | API dungeonDiff=%s raidDiff=%s",
        tostring(name or "?"),
        tostring(instType or "?"),
        tostring(mapInstID or "?"),
        tostring(uiMapID or "nil"),
        tostring(diffID or "nil"),
        tostring(encDiff or "nil"),
        tostring(diffLabel),
        tostring(tryCounterInstanceDiffCache.instanceID or "nil"),
        tostring(tryCounterInstanceDiffCache.difficultyID or "nil"),
        tostring(ddApi or "nil"),
        tostring(rdApi or "nil"))

    if instType ~= "party" and instType ~= "raid" then
        TryCounterLootDebug(self, "skip", "EJ/DB boss probe skipped (need party or raid instance type)")
        return
    end

    local WN = self
    C_Timer.After(0.75, function()
        if not WN or not IsTryCounterLootDebugEnabled(WN) then return end
        local inI = IsInInstance()
        if issecretvalue and inI and issecretvalue(inI) then inI = nil end
        if not inI then return end

        TryCounterLoadEncounterJournal()
        if not TryCounterEJ_HasCoreAPIs() then
            TryCounterLootDebug(WN, "miss",
                "DB probe: EJ APIs missing (EJ_SelectInstance=%s EJ_GetEncounterInfoByIndex=%s EJ_GetCurrentInstance=%s EJ_GetInstanceForMap=%s) — need Blizzard_EncounterJournal",
                tostring(not not EJ_SelectInstance),
                tostring(not not EJ_GetEncounterInfoByIndex),
                tostring(not not EJ_GetCurrentInstance),
                tostring(not not EJ_GetInstanceForMap))
            return
        end

        local jid = TryCounterGetJournalInstanceID()
        if not jid or jid == 0 then
            local um = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            if um and issecretvalue and issecretvalue(um) then um = nil end
            TryCounterLootDebug(WN, "miss", "DB probe: journalID unresolved (TryCounterGetJournalInstanceID=%s uiMapID=%s)",
                tostring(jid), tostring(um))
            return
        end

        EJ_SelectInstance(jid)
        local effDiff = ResolveEffectiveEncounterDifficultyID(true, nil)
        local effLabel = (effDiff and DIFFICULTY_ID_TO_LABELS[effDiff]) or "?"
        local um2 = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        if um2 and issecretvalue and issecretvalue(um2) then um2 = nil end
        TryCounterLootDebug(WN, "flow", "DB probe: uiMapID=%s → journalInstanceID=%s | effectiveDiffID=%s (%s) — WN DB (dungeonEncID → npcID → drops):",
            tostring(um2 or "nil"), tostring(jid), tostring(effDiff or "nil"), tostring(effLabel))

        local idx = 1
        local hadDbBoss = false
        while true do
            local encName, dungeonEncID = TryCounterResolveDungeonEncounterFromEJIndex(idx, jid)
            local isSecret = issecretvalue and encName and issecretvalue(encName)
            if not isSecret and not encName then break end
            if not isSecret and dungeonEncID then
                isSecret = issecretvalue and issecretvalue(dungeonEncID)
            end
            if not isSecret and dungeonEncID then
                local npcIDs = encounterDB[dungeonEncID]
                if npcIDs then
                    hadDbBoss = true
                    local parts = {}
                    for ni = 1, #npcIDs do
                        local npcID = npcIDs[ni]
                        local npcDrops = npcDropDB[npcID]
                        if npcDrops then
                            local trackable, diffSkip = FilterDropsByDifficulty(npcDrops, effDiff)
                            for ti = 1, #trackable do
                                local d = trackable[ti]
                                local ann = ResolveTryCounterMountAnnounceDrop(d)
                                if ann then
                                    parts[#parts + 1] = format("npc %s → mount \"%s\" (item %s)",
                                        tostring(npcID), tostring(ann.name or "?"), tostring(ann.itemID))
                                end
                            end
                            if #trackable == 0 and diffSkip then
                                parts[#parts + 1] = format("npc %s → (0 trackable: needs %s)",
                                    tostring(npcID), tostring(diffSkip.required))
                            elseif #trackable == 0 then
                                parts[#parts + 1] = format("npc %s → (0 trackable: gated or collected)", tostring(npcID))
                            end
                        end
                    end
                    if #parts > 0 then
                        TryCounterLootDebug(WN, "flow", "  • %s [enc=%s]: %s",
                            tostring(encName), tostring(dungeonEncID), table.concat(parts, " | "))
                    else
                        TryCounterLootDebug(WN, "skip", "  • %s [enc=%s]: npcIDs in encounterDB but no npcDropDB rows (%s)",
                            tostring(encName), tostring(dungeonEncID), table.concat(npcIDs, ","))
                    end
                end
            end
            idx = idx + 1
        end

        if not hadDbBoss then
            TryCounterLootDebug(WN, "miss", "DB probe: no EJ encounters in this instance map to encounterDB (journal=%s)", tostring(jid))
        end
    end)
end

TryCounterShowInstanceDrops = function(journalInstanceID)
    local WN = WarbandNexus
    if not WN or not WN.Print then return end
    EJ_SelectInstance(journalInstanceID)

    -- Iterate all encounters in this instance and cross-reference with our encounterDB
        local dropsToShow = {} -- { { bossName, drops = { {type, itemID, name}, ... } }, ... }
        local idx = 1
        while true do
            local encName, dungeonEncID = TryCounterResolveDungeonEncounterFromEJIndex(idx, journalInstanceID)
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
                    for i = 1, #npcIDs do
                        local npcID = npcIDs[i]
                        local npcDrops = npcDropDB[npcID]
                        if npcDrops then
                            local npcDiff = npcDrops.dropDifficulty
                            for j = 1, #npcDrops do
                                local drop = npcDrops[j]
                                local ann = ResolveTryCounterMountAnnounceDrop(drop)
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

            local encDiff = ResolveEffectiveEncounterDifficultyID(true, nil)

            local Ltc = ns.L
            local detectPrefix = (Ltc and Ltc["TRYCOUNTER_INSTANCE_COLLECTIBLE_DETECTED"]) or "Collectible Detected : "

            for i = 1, #dropsToShow do
                local entry = dropsToShow[i]
                for j = 1, #entry.drops do
                    local drop = entry.drops[j]
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
                        -- Show try count (use reflected type/key for item->mount so mount count shows)
                        local tryCount = 0
                        if WN.GetTryCount then
                            local tcType, tryKey = GetTryCountTypeAndKey(drop)
                            tryCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
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

                    -- Third segment: (req) colored green/red/amber; gray em dash when DB has no difficulty gate.
                    local diffSegment
                    local reqDiff = entry.diffMap and entry.diffMap[drop.itemID]
                    if reqDiff then
                        if encDiff and not (issecretvalue and issecretvalue(encDiff)) then
                            local color = DoesDifficultyMatch(encDiff, reqDiff) and "|cff00ff00" or "|cffff6666"
                            diffSegment = "(" .. color .. reqDiff .. "|r)"
                        else
                            diffSegment = "(|cffffaa00" .. reqDiff .. "|r)"
                        end
                    else
                        diffSegment = "|cff888888—|r"
                    end

                    TryChat("|cff9370DB[WN-Drops]|r " .. detectPrefix .. entry.bossName .. " - " .. itemLink .. " - "
                        .. diffSegment .. " - " .. status)
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
        fishingCtx.active = true
        fishingCtx.castTime = GetTime()
        -- Safety timer: if the channel times out (fish escapes) and LOOT_CLOSED never fires,
        -- auto-reset after 20s so the next NPC loot is not misrouted to ProcessFishingLoot.
        if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() end
        fishingCtx.resetTimer = C_Timer.NewTimer(20, function()
            fishingCtx.active = false
            fishingCtx.castTime = 0
            fishingCtx.resetTimer = nil
        end)
    elseif PICKPOCKET_SPELLS[spellID] then
        isPickpocketing = true
    elseif PROFESSION_LOOT_SPELLS[spellID] then
        isProfessionLooting = true
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
    fishingCtx.active = false
    fishingCtx.castTime = 0
    if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() fishingCtx.resetTimer = nil end
end

-- =====================================================================
-- SAFE GUID HELPERS (must be defined before event handlers)
-- =====================================================================

---Safely get unit GUID (Midnight 12.0: UnitGUID returns secret values for NPC/object units)
---@param unit string e.g. "target", "mouseover"
---@return string|nil guid Safe GUID string or nil
SafeGetUnitGUID = function(unit)
    if not unit then return nil end
    local ok, guid = pcall(UnitGUID, unit)
    if not ok or not guid then return nil end
    if type(guid) ~= "string" then return nil end
    if issecretvalue and issecretvalue(guid) then return nil end
    return guid
end

SafeGetTargetGUID = function()
    return SafeGetUnitGUID("target")
end

---Mouseover at LOOT_OPENED: when opening an object (e.g. dumpster) by right-click, mouse is often still over it.
SafeGetMouseoverGUID = function()
    return SafeGetUnitGUID("mouseover")
end

---Safely get a GUID string, guarding against Midnight 12.0 secret values.
---@param rawGUID any A potentially secret GUID value
---@return string|nil guid Safe GUID string or nil
SafeGuardGUID = function(rawGUID)
    if not rawGUID then return nil end
    if type(rawGUID) ~= "string" then return nil end
    if issecretvalue and issecretvalue(rawGUID) then return nil end
    return rawGUID
end

---True if loot source GUIDs indicate fishing (bobber/pool) rather than tracked NPC/object.
---Bobber is Creature (NPC 124736); pools are GameObjects. Only reject when source is in our DB.
local function IsFishingSourceCompatible(sourceGUIDs)
    if not sourceGUIDs or #sourceGUIDs == 0 then return true end
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if type(srcGUID) == "string" then
            local typeStr = srcGUID:match("^(%a+)")
            local npcID = GetNPCIDFromGUID(srcGUID)
            if npcID and npcDropDB[npcID] then return false end
            local objectID = GetObjectIDFromGUID(srcGUID)
            if objectID and objectDropDB[objectID] then return false end
        end
    end
    return true
end

-- =====================================================================
-- LOOT READY / LOOT CLOSED HANDLERS
-- =====================================================================

---LOOT_READY handler (warcraft.wiki.gg/wiki/LOOT_READY).
---Fires when looting begins, BEFORE the loot window is shown. Loot APIs valid until LOOT_CLOSED.
---This is the ONLY guaranteed loot event — LOOT_OPENED may be skipped by fast auto-loot / addons.
---We capture ALL state here (slot data + unit GUIDs) so LOOT_CLOSED can process reliably.
---@param autoloot boolean
function WarbandNexus:OnTryCounterLootReady(autoloot)
    -- A second LOOT_READY while the frame is open must not clear lootSession.opened; otherwise
    -- LOOT_CLOSED treats the session as "OPENED missed" and runs the closed route again (duplicate flow logs / work).
    if not lootSession.opened then
        ResetLootSession()
    end
    lootReady.numLoot = (GetNumLootItems and GetNumLootItems()) or 0
    lootReady.sourceGUIDs = GetAllLootSourceGUIDs and GetAllLootSourceGUIDs() or {}
    wipe(lootReady.slotData)
    for i = 1, lootReady.numLoot do
        local hasItem = LootSlotHasItem and LootSlotHasItem(i)
        local link = GetLootSlotLink and GetLootSlotLink(i)
        if link and issecretvalue and issecretvalue(link) then link = nil end
        lootReady.slotData[i] = { hasItem = not not hasItem, link = link }
    end
    lootReady.mouseoverGUID = SafeGetMouseoverGUID and SafeGetMouseoverGUID() or nil
    lootReady.targetGUID = SafeGetTargetGUID and SafeGetTargetGUID() or nil
    lootReady.npcGUID = SafeGetUnitGUID and SafeGetUnitGUID("npc") or nil
    lootReady.time = GetTime()
    lootReady.wasFishing = fishingCtx.active and (lootReady.time - fishingCtx.castTime) <= FISHING_CAST_CONTEXT_TTL
    if IsTryCounterLootDebugEnabled(self) then
        local sig = string.format("%d|%d|%s", lootReady.numLoot, #lootReady.sourceGUIDs, tostring(not not autoloot))
        local tDbg = GetTime()
        if sig ~= lastLootReadyFlowDebugSig or (tDbg - lastLootReadyFlowDebugTime) >= DEBUG_TRACE_DEDUP_LOOT_MS then
            lastLootReadyFlowDebugSig = sig
            lastLootReadyFlowDebugTime = tDbg
            TryCounterLootDebug(self, "flow", "READY loot=%d src=%d auto=%s fish=%s mo=%s tg=%s npc=%s",
                lootReady.numLoot, #lootReady.sourceGUIDs, tostring(not not autoloot), tostring(lootReady.wasFishing),
                lootReady.mouseoverGUID and "Y" or "-", lootReady.targetGUID and "Y" or "-", lootReady.npcGUID and "Y" or "-")
        end
    end
end

---LOOT_CLOSED handler (reset fishing flag, pickpocket flag, safety timer)
---processedGUIDs is NOT cleared here — it persists with TTL-based cleanup (300s).
---This prevents double-counting when the same loot source (NPC corpse, chest, container)
---is opened multiple times in quick succession (user takes partial loot, closes, reopens).
---Different loot sources get their own GUID and are counted separately.
function WarbandNexus:OnTryCounterLootClosed()
    -- When LOOT_OPENED was missed (fast auto-loot), use LOOT_READY captured data through
    -- the same ClassifyLootSession→RouteLootSession path. Unit GUIDs come from LOOT_READY
    -- snapshot (guaranteed valid) rather than fresh reads (may be nil by now).
    if not lootSession.opened and IsAutoTryCounterEnabled() then
        local now = GetTime()
        -- After a normal OPENED session, first LOOT_CLOSED clears lootReady; a second client LOOT_CLOSED
        -- would otherwise promote an empty snapshot and spam "closed -> … loot=0" (no work to do).
        local readySnapshotValid = lootReady.time > 0 and (now - lootReady.time) <= LOOT_READY_STATE_TTL
        if readySnapshotValid then
            local incomingPrimary = lootReady.sourceGUIDs and lootReady.sourceGUIDs[1] or lootReady.npcGUID
            local debounced = incomingPrimary and lastTryCountLootSourceGUID == incomingPrimary
                and (now - lastTryCountSourceTime) < CHAT_LOOT_DEBOUNCE
            if not debounced then
                PromoteLootReadyToSession()
                RouteLootSession(self, "closed")
            elseif IsTryCounterLootDebugEnabled(self) then
                TryCounterLootDebug(self, "skip", "CLOSED debounce (%s)", tostring(lastTryCountSourceKey))
            end
        end
    end

    -- Full cleanup: wipe both session and ready state so nothing bleeds into next loot event.
    ResetLootSession()
    lootReady.wasFishing = false
    lootReady.numLoot = 0
    lootReady.time = 0
    lootReady.mouseoverGUID = nil
    lootReady.targetGUID = nil
    lootReady.npcGUID = nil
    wipe(lootReady.slotData)
    wipe(lootReady.sourceGUIDs)

    if fishingCtx.lootWasFishing then
        fishingCtx.active = false
        fishingCtx.castTime = 0
        fishingCtx.lootWasFishing = false
        if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() fishingCtx.resetTimer = nil end
    end
    isPickpocketing = false
    isProfessionLooting = false
    -- NOTE: Do NOT clear isBlockingInteractionOpen here.
    -- It is managed exclusively by PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE events.
    -- Clearing it on LOOT_CLOSED would incorrectly allow NPC loot processing
    -- when a bank/vendor/AH UI is still open (e.g. loot window closed while banking).
    lastContainerItemID = nil
    lastContainerItemTime = 0
    if fishingCtx.resetTimer then fishingCtx.resetTimer:Cancel() end
    fishingCtx.resetTimer = nil
    -- Do NOT clear lastGatherCastName/lastGatherCastTime here (overwritten on next UNIT_SPELLCAST_SENT).
    -- DO NOT clear processedGUIDs here — let TTL-based cleanup handle it (PROCESSED_GUID_TTL = 300s)
end

---CHAT_MSG_LOOT: strict fallback when loot window path already ran or never opened.
---Priority: repeatable reset → exact item→NPC → exact item→encounter → exact item→fishing.
---Each path requires EXACT itemID match against a known source; no guessing.
---@param message string
---@param author string
function WarbandNexus:OnTryCounterChatMsgLoot(message, author)
    if not message or not IsAutoTryCounterEnabled() then return end
    if issecretvalue then
        if issecretvalue(message) then return end
        if author and issecretvalue(author) then return end
    end

    -- Only process self-loot
    local playerName = UnitName("player")
    if not playerName then return end
    local authorBase = author and author:match("^([^%-]+)") or author
    if author and author ~= "" and author ~= playerName and (not authorBase or authorBase ~= playerName) then return end

    local itemIDStr = message:match("|Hitem:(%d+):")
    local itemID = itemIDStr and tonumber(itemIDStr) or nil
    if not itemID then return end

    local now = GetTime()

    -- Global debounce: any route that already ran within the window blocks all CHAT paths.
    if lastTryCountSourceKey and (now - lastTryCountSourceTime) < CHAT_LOOT_DEBOUNCE then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "CHAT debounce (%s %.1fs)", tostring(lastTryCountSourceKey), now - lastTryCountSourceTime) end
        return
    end

    -- Loot window guard: if a loot session is actively open, the primary path
    -- (LOOT_OPENED → ProcessNPCLoot/ProcessFishingLoot) already handled counting.
    -- CHAT_MSG_LOOT fires per-item during manual loot; suppress NPC/encounter/fishing
    -- paths (2-4) to prevent double-counting when debounce has expired.
    -- Path 1 (repeatable resets) still runs because the primary path may not cover
    -- repeatable items obtained from non-tracked sources.
    local lootWindowActive = lootSession.opened

    -- Path 1: Repeatable item obtained → reset + notification
    local repDrop = repeatableItemDrops[itemID]
    if repDrop then
        local tryKey = GetTryCountKey(repDrop)
        if tryKey then
            local preResetCount = self:GetTryCount(repDrop.type, tryKey)
            self:ResetTryCount(repDrop.type, tryKey)
            lastTryCountSourceKey = "item_" .. tostring(itemID)
            lastTryCountSourceTime = now
            local itemLink = GetDropItemLink(repDrop)
            TryChat(BuildObtainedChat("TRYCOUNTER_OBTAINED_RESET", "Obtained %s! Try counter reset.", itemLink, preResetCount))
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
            local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(repDrop.itemID)
            if self.SendMessage then
                self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                    type = "item", id = repDrop.itemID,
                    name = itemName or repDrop.name or "Unknown", icon = itemIcon,
                    preResetTryCount = preResetCount,
                    fromTryCounter = true,
                })
            end
        end
        return
    end

    -- Paths 2-4: suppress when loot window is active (primary path already counted).
    if lootWindowActive then
        -- CHAT_MSG_LOOT fires once per item; rate-limit this skip line to avoid chat flood.
        if IsTryCounterLootDebugEnabled(self) then
            local tChat = GetTime()
            if tChat - lastChatLootWindowActiveDebugTime >= 1.5 then
                lastChatLootWindowActiveDebugTime = tChat
                TryCounterLootDebug(self, "skip", "CHAT loot window active (item=%s; further lines suppressed ~1.5s)", tostring(itemID))
            end
        end
        return
    end

    -- Path 2: Exact item→NPC match (chatLootItemToNpc built from eligible NPCs only)
    local npcID = chatLootItemToNpc[itemID]
    if npcID == false then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "miss", "CHAT ambiguous NPC item=%s", tostring(itemID)) end
        return
    end
    if npcID then
        local drops = npcDropDB[npcID]
        if drops then
            local inInst = IsInInstance()
            if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
            local encDiff = ResolveEffectiveEncounterDifficultyID(inInst, nil)
            local trackable = FilterDropsByDifficulty(drops, encDiff)
            if #trackable > 0 then
                local encForKey = GetEncounterIDForNpcID(npcID)
                lastTryCountSourceKey = encForKey and ("encounter_" .. tostring(encForKey)) or ("npc_" .. tostring(npcID))
                lastTryCountSourceTime = now

                -- Separate found item from missed items: the looted itemID may be one of our tracked drops.
                -- Without this, the found item would be incorrectly incremented as "missed".
                local foundDrop = nil
                local missed = {}
                for i = 1, #trackable do
                    local drop = trackable[i]
                    if drop.itemID == itemID then
                        foundDrop = drop
                    elseif drop.questStarters then
                        local isQS = false
                        for j = 1, #drop.questStarters do
                            if drop.questStarters[j].itemID == itemID then isQS = true; break end
                        end
                        if isQS then foundDrop = drop else missed[#missed + 1] = drop end
                    else
                        missed[#missed + 1] = drop
                    end
                end

                -- Handle found item: reset try count + celebrate
                if foundDrop then
                    if not foundDrop.repeatable and foundDrop.type == "item" then MarkItemObtained(foundDrop.itemID) end
                    local tcType, tryKey = GetTryCountTypeAndKey(foundDrop)
                    if tryKey then
                        local preResetCount = self:GetTryCount(tcType, tryKey)
                        self:ResetTryCount(tcType, tryKey)
                        if preResetCount and preResetCount > 0 then
                            local cacheKey = tcType .. "\0" .. tostring(tryKey)
                            pendingPreResetCounts[cacheKey] = preResetCount
                            C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                        end
                        local itemLink = GetDropItemLink(foundDrop)
                        local chatKey = foundDrop.repeatable and "TRYCOUNTER_OBTAINED_RESET" or "TRYCOUNTER_OBTAINED"
                        local chatFallback = foundDrop.repeatable and "Obtained %s! Try counter reset." or "Obtained %s!"
                        TryChat(BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                        if self.SendMessage then
                            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                            local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(foundDrop.itemID)
                            self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                                type = tcType, id = (foundDrop.type == "item") and foundDrop.itemID or tryKey,
                                name = itemName or foundDrop.name or "Unknown", icon = itemIcon,
                                preResetTryCount = preResetCount,
                                fromTryCounter = true,
                            })
                        end
                    end
                end

                -- Increment missed drops (items NOT found in this loot)
                if #missed > 0 then
                    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "count", "CHAT npc=%s +%d (item %s)", tostring(npcID), #missed, tostring(itemID)) end
                    ProcessMissedDrops(missed, drops.statisticIds)
                end
                return
            end
        end
    end

    -- Path 3: Exact item→encounter (recent encounter kill whose drop table contains this itemID)
    for guid, killData in pairs(recentKills or {}) do
        if killData.isEncounter and killData.npcID and tryCounterNpcEligible[killData.npcID] then
            local drops = npcDropDB[killData.npcID]
            if drops then
                local itemMatches = false
                for i = 1, #drops do
                    if drops[i].itemID == itemID then itemMatches = true; break end
                    if drops[i].questStarters then
                        for j = 1, #drops[i].questStarters do
                            if drops[i].questStarters[j].itemID == itemID then itemMatches = true; break end
                        end
                    end
                    if itemMatches then break end
                end
                if itemMatches then
                    local inInst = IsInInstance()
                    if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
                    local encDiff = ResolveEffectiveEncounterDifficultyID(inInst, killData.difficultyID)
                    local trackable = FilterDropsByDifficulty(drops, encDiff)
                    if #trackable > 0 then
                        local encForKey = GetEncounterIDForNpcID(killData.npcID)
                        lastTryCountSourceKey = encForKey and ("encounter_" .. tostring(encForKey)) or ("npc_" .. tostring(killData.npcID))
                        lastTryCountSourceTime = now

                        -- Separate found item from missed: the looted itemID is one of our tracked drops.
                        local foundDrop = nil
                        local missed = {}
                        for i = 1, #trackable do
                            local drop = trackable[i]
                            if drop.itemID == itemID then
                                foundDrop = drop
                            elseif drop.questStarters then
                                local isQS = false
                                for j = 1, #drop.questStarters do
                                    if drop.questStarters[j].itemID == itemID then isQS = true; break end
                                end
                                if isQS then foundDrop = drop else missed[#missed + 1] = drop end
                            else
                                missed[#missed + 1] = drop
                            end
                        end

                        -- Handle found item: reset try count + celebrate
                        if foundDrop then
                            if not foundDrop.repeatable and foundDrop.type == "item" then MarkItemObtained(foundDrop.itemID) end
                            local tcType, tryKey = GetTryCountTypeAndKey(foundDrop)
                            if tryKey then
                                local preResetCount = self:GetTryCount(tcType, tryKey)
                                self:ResetTryCount(tcType, tryKey)
                                if preResetCount and preResetCount > 0 then
                                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                                    pendingPreResetCounts[cacheKey] = preResetCount
                                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                                end
                                local itemLink = GetDropItemLink(foundDrop)
                                local chatKey = foundDrop.repeatable and "TRYCOUNTER_OBTAINED_RESET" or "TRYCOUNTER_OBTAINED"
                                local chatFallback = foundDrop.repeatable and "Obtained %s! Try counter reset." or "Obtained %s!"
                                TryChat(BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                                if self.SendMessage then
                                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(foundDrop.itemID)
                                    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                                        type = tcType, id = (foundDrop.type == "item") and foundDrop.itemID or tryKey,
                                        name = itemName or foundDrop.name or "Unknown", icon = itemIcon,
                                        preResetTryCount = preResetCount,
                                        fromTryCounter = true,
                                    })
                                end
                            end
                        end

                        -- Increment missed drops only
                        if #missed > 0 then
                            if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "count", "CHAT enc npc=%s +%d (item %s)", tostring(killData.npcID), #missed, tostring(itemID)) end
                            ProcessMissedDrops(missed, drops.statisticIds)
                        end
                        recentKills[guid] = nil
                        return
                    end
                end
            end
        end
    end

    -- Path 4: Exact item→fishing (item must be in current zone's fishing drop table)
    if fishingCtx.active and (now - fishingCtx.castTime) <= FISHING_CAST_CONTEXT_TTL
        and IsInTrackableFishingZone(true)
        and not CurrentUnitsHaveMobLootContext() then
        local fishingItemIDs = GetFishingDropItemIDsForCurrentZone()
        if fishingItemIDs and fishingItemIDs[itemID] then
            local trackable = GetFishingTrackableForCurrentZone()
            if #trackable > 0 then
                -- Check if the caught item is a trackable (→ reset), else +1
                local caughtDrop = nil
                for i = 1, #trackable do
                    if trackable[i].itemID == itemID then caughtDrop = trackable[i]; break end
                end
                if caughtDrop then
                    if not caughtDrop.repeatable then MarkItemObtained(caughtDrop.itemID) end
                    local tcType, tryKey = GetTryCountTypeAndKey(caughtDrop)
                    if tryKey then
                        local preResetCount = self:GetTryCount(tcType, tryKey)
                        self:ResetTryCount(tcType, tryKey)
                        lastTryCountSourceKey = "item_" .. tostring(itemID)
                        lastTryCountSourceTime = now
                        local itemLink = GetDropItemLink(caughtDrop)
                        local chatKey = caughtDrop.repeatable and "TRYCOUNTER_CAUGHT_RESET" or "TRYCOUNTER_CAUGHT"
                        local chatFallback = caughtDrop.repeatable and "Caught %s! Try counter reset." or "Caught %s!"
                        TryChat(BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "reset", "CHAT fish caught item=%s", tostring(itemID)) end
                        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(caughtDrop.itemID)
                        if self.SendMessage then
                            self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                                type = tcType, id = tryKey,
                                name = itemName or caughtDrop.name or "Unknown", icon = itemIcon,
                                preResetTryCount = preResetCount,
                                fromTryCounter = true,
                            })
                        end
                    end
                    return
                end
                lastTryCountSourceKey = "fishing_chat"
                lastTryCountSourceTime = now
                if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "count", "CHAT fish +1 (item=%s)", tostring(itemID)) end
                ProcessMissedDrops(trackable, nil)
                return
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
    if not bagID or not slotID then return end
    if issecretvalue and (issecretvalue(bagID) or issecretvalue(slotID)) then return end
    if bagID < 0 or bagID > 4 then return end
    if not C_Container or not C_Container.GetContainerItemID then return end

    local itemID = C_Container.GetContainerItemID(bagID, slotID)
    if not itemID then return end
    if issecretvalue and issecretvalue(itemID) then return end
    if not containerDropDB[itemID] then return end

    lastContainerItemID = itemID
    lastContainerItemTime = GetTime()
end

---Resolve the player's current mapID safely, caching the last known good value.
---Midnight 12.0: GetBestMapForUnit may return nil/secret during instanced combat.
---@return number|nil mapID
GetSafeMapID = function()
    local rawMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local mapID = (rawMapID and (not issecretvalue or not issecretvalue(rawMapID))) and rawMapID or nil
    if mapID then
        lastSafeMapID = mapID
    else
        mapID = lastSafeMapID
    end
    return mapID
end

---Collect ALL fishing drops for the player's current zone (global + map chain).
---Single source of truth for the instance-check → map-chain-walk → fishingDropDB merge
---pattern. Returns raw (unfiltered) drop array.
---@return table drops, boolean inInstance
local function CollectFishingDropsForZone()
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if inInstance then return {}, true end
    local mapID = GetSafeMapID()
    local drops = {}
    local seen = {}  -- dedup: same drop registered at child + parent map would double-count
    -- IMPORTANT:
    -- Do not auto-merge fishingDropDB[0] (global pool) into every map.
    -- Global entries (e.g. Sea Turtle) would make every zone look like a fishing
    -- try-counter zone and cause wrong attribution in Midnight maps.
    local currentMapID = mapID
    while currentMapID and currentMapID > 0 do
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
        currentMapID = (nextID and (not issecretvalue or not issecretvalue(nextID))) and nextID or nil
    end
    return drops, false
end

---@return table trackable  Uncollected fishing drops for current zone
GetFishingTrackableForCurrentZone = function()
    local drops, inInstance = CollectFishingDropsForZone()
    if inInstance then return {} end
    local trackable = {}
    for i = 1, #drops do
        local d = drops[i]
        if d.repeatable or not IsCollectibleCollected(d) then trackable[#trackable + 1] = d end
    end
    return trackable
end

---@return table|nil  [itemID]=true set of ALL fishing drop itemIDs in zone, or nil
GetFishingDropItemIDsForCurrentZone = function()
    local drops, inInstance = CollectFishingDropsForZone()
    if inInstance or #drops == 0 then return nil end
    local set = {}
    for i = 1, #drops do
        local id = drops[i] and drops[i].itemID
        if id then set[id] = true end
    end
    return set
end

---@param includeGlobal boolean|nil  When true, also checks fishingDropDB[0] (global drops).
IsInTrackableFishingZone = function(includeGlobal)
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if inInstance then return false end
    local mapID = GetSafeMapID()
    if not mapID then return false end
    local current = mapID
    while current and current > 0 do
        if fishingDropDB[current] then return true end
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(current)
        local nextID = mapInfo and mapInfo.parentMapID
        current = (nextID and (not issecretvalue or not issecretvalue(nextID))) and nextID or nil
    end
    return false
end

-- =====================================================================
-- LOOT SESSION HELPERS (shared by LOOT_READY, LOOT_OPENED, LOOT_CLOSED)
-- =====================================================================

---True if GUID is a Creature or Vehicle (corpse / NPC loot context). Gathering nodes are GameObject.
local function UnitGuidLooksLikeMobCorpse(guid)
    if type(guid) ~= "string" then return false end
    return guid:match("^Creature") ~= nil or guid:match("^Vehicle") ~= nil
end

---Any loot slot source is a mob corpse — not limited to try-counter-eligible NPCs.
---Without this, trash mobs fail LootEligibleNpcFromGuid() and ClassifyLootSession
---misroutes corpse loot to ProcessFishingLoot when fishingCtx is fresh (Nether-Warped Egg +1).
local function LootSessionHasAnyMobCorpseSources(sourceGUIDs)
    for i = 1, #(sourceGUIDs or {}) do
        if UnitGuidLooksLikeMobCorpse(sourceGUIDs[i]) then return true end
    end
    return false
end

---Eligible try-counter NPC from corpse GUID (nil if not a rare-tier source we track on corpses).
local function LootEligibleNpcFromGuid(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local nid = GetNPCIDFromGUID(guid)
    if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then return nid end
    return nil
end

local function CurrentUnitsHaveEligibleNpcContext()
    local mo = SafeGetMouseoverGUID and SafeGetMouseoverGUID()
    local tg = SafeGetTargetGUID and SafeGetTargetGUID()
    local npc = SafeGetUnitGUID and SafeGetUnitGUID("npc")
    return LootEligibleNpcFromGuid(mo) or LootEligibleNpcFromGuid(tg) or LootEligibleNpcFromGuid(npc)
end

---Uses lootSession snapshot (deferred/opened capture). When set, mob loot should run even if
---GetLootSourceInfo reports a GameObject (seen after a recent herb/ore cast in same session).
local function LootSessionHasMobLootContext()
    return UnitGuidLooksLikeMobCorpse(lootSession.mouseoverGUID)
        or UnitGuidLooksLikeMobCorpse(lootSession.targetGUID)
        or UnitGuidLooksLikeMobCorpse(lootSession.npcGUID)
end

---Fresh read at call site (e.g. LOOT_CLOSED before session is promoted).
CurrentUnitsHaveMobLootContext = function()
    local mo = SafeGetMouseoverGUID and SafeGetMouseoverGUID()
    local tg = SafeGetTargetGUID and SafeGetTargetGUID()
    local npc = SafeGetUnitGUID and SafeGetUnitGUID("npc")
    return UnitGuidLooksLikeMobCorpse(mo) or UnitGuidLooksLikeMobCorpse(tg) or UnitGuidLooksLikeMobCorpse(npc)
end

---Fully reset lootSession to a clean state. Called at the start of every new
---loot event (LOOT_READY) and at the end of LOOT_CLOSED to prevent stale data
---from bleeding into the next session.
ResetLootSession = function()
    lootSession.numLoot = 0
    lootSession.sourceGUIDs = {}
    wipe(lootSession.slotData)
    lootSession.mouseoverGUID = nil
    lootSession.targetGUID = nil
    lootSession.npcGUID = nil
    lootSession.opened = false
end

---Snapshot unit GUIDs + loot window data into lootSession (same-frame read before fast auto-loot clears it).
CaptureLootSessionState = function()
    ResetLootSession()
    lootSession.mouseoverGUID = SafeGetMouseoverGUID and SafeGetMouseoverGUID() or nil
    lootSession.targetGUID = SafeGetTargetGUID and SafeGetTargetGUID() or nil
    lootSession.npcGUID = SafeGetUnitGUID and SafeGetUnitGUID("npc") or nil
    lootSession.numLoot = (GetNumLootItems and GetNumLootItems()) or 0
    lootSession.sourceGUIDs = GetAllLootSourceGUIDs() or {}
    wipe(lootSession.slotData)
    for i = 1, lootSession.numLoot do
        local hasItem = LootSlotHasItem and LootSlotHasItem(i)
        local link = GetLootSlotLink and GetLootSlotLink(i)
        if link and issecretvalue and issecretvalue(link) then link = nil end
        lootSession.slotData[i] = { hasItem = not not hasItem, link = link }
    end
end

---Promote LOOT_READY captured data into lootSession when LOOT_OPENED was missed.
---Uses unit GUIDs captured at LOOT_READY time (guaranteed valid) instead of fresh reads
---(which may be nil by the time LOOT_CLOSED fires if the player moved on).
PromoteLootReadyToSession = function()
    ResetLootSession()
    if lootReady.time > 0 and (GetTime() - lootReady.time) <= LOOT_READY_STATE_TTL then
        lootSession.mouseoverGUID = lootReady.mouseoverGUID
        lootSession.targetGUID = lootReady.targetGUID
        lootSession.npcGUID = lootReady.npcGUID
        lootSession.sourceGUIDs = lootReady.sourceGUIDs
        lootSession.numLoot = lootReady.numLoot
        for i = 1, #lootReady.slotData do lootSession.slotData[i] = lootReady.slotData[i] end
    end
end

-- =====================================================================
-- CLASSIFY-LOCK-PROCESS ROUTER
-- Determines exactly ONE route per loot session. Once classified, no
-- other source type can run. Each classification is based on hard
-- signals (API flags, exact GUID types, spell context) — never heuristic
-- fallthrough from one source type to another.
--
-- Priority (first match wins, all others locked out):
--   1. SKIP       — pickpocket / blocking vendor UI / profession loot
--   2. CONTAINER  — isFromItem flag OR recent tracked container use
--   3. FISHING    — IsFishingLoot() API OR (fishing spell context + source
--                   compatible + NO eligible NPC/object GUID in session)
--   4. NPC/OBJECT — ProcessNPCLoot (exact GUID→ID match only)
-- =====================================================================

---Classify the loot session source into exactly one route.
---@return string route "skip"|"container"|"fishing"|"npc"|"none"
ClassifyLootSession = function(source, isFromItem)
    -- 1. SKIP: non-combat loot sources
    if isPickpocketing then return "skip" end
    if isBlockingInteractionOpen then return "skip" end
    if isProfessionLooting then return "skip" end

    -- Gathering cast + only GameObject sources (herb/ore node) → skip
    local now = GetTime()
    if lastGatherCastTime and (now - lastGatherCastTime) < 5 then
        local anyGameObject, anyMob = false, false
        for i = 1, #lootSession.sourceGUIDs do
            local guid = lootSession.sourceGUIDs[i]
            if type(guid) == "string" then
                if guid:match("^GameObject") then anyGameObject = true end
                if guid:match("^Creature") or guid:match("^Vehicle") then anyMob = true end
            end
        end
        if anyGameObject and not anyMob and not LootSessionHasMobLootContext() then
            return "skip"
        end
    end

    -- 2. CONTAINER: isFromItem flag (Blizzard API) or recent tracked container use
    local safeIsFromItem = isFromItem
    if issecretvalue and safeIsFromItem and issecretvalue(safeIsFromItem) then safeIsFromItem = nil end
    if not safeIsFromItem and source ~= "opened" then
        safeIsFromItem = lastContainerItemID and containerDropDB[lastContainerItemID] and (now - lastContainerItemTime) < 3
    end
    if safeIsFromItem then return "container" end

    -- 3. FISHING: IsFishingLoot() API or (fishing spell context + source compatible + no eligible NPC corpse)
    local fishingLootAPI = false
    if source == "opened" then
        fishingLootAPI = IsFishingLoot and IsFishingLoot()
        if issecretvalue and fishingLootAPI and issecretvalue(fishingLootAPI) then fishingLootAPI = false end
    end
    local fishingContextFresh = fishingCtx.active and (now - fishingCtx.castTime) <= FISHING_CAST_CONTEXT_TTL
    local sourceCompatible = fishingContextFresh and IsFishingSourceCompatible(lootSession.sourceGUIDs)
    local fishingByHeuristic = IsInTrackableFishingZone(true) and sourceCompatible
    if fishingLootAPI or fishingByHeuristic then
        -- Any corpse loot (including untracked trash) must use NPC path, not fishing.
        local corpsePresent = LootSessionHasAnyMobCorpseSources(lootSession.sourceGUIDs)
            or LootSessionHasMobLootContext()
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

---Unified routing: classify then dispatch to exactly one processor.
---@param self table WarbandNexus addon reference
---@param source string "opened"|"closed"
---@param isFromItem boolean|nil Container item flag (only from LOOT_OPENED)
RouteLootSession = function(self, source, isFromItem)
    if not IsAutoTryCounterEnabled() then return end

    local route = ClassifyLootSession(source, isFromItem)

    if IsTryCounterLootDebugEnabled(self) then
        TryCounterLootDebug(self, "flow", "%s -> %s | loot=%d src=%d mo=%s tg=%s",
            source, route, lootSession.numLoot, #lootSession.sourceGUIDs,
            lootSession.mouseoverGUID and "Y" or "-", lootSession.targetGUID and "Y" or "-")
    end

    if route == "skip" then return end
    if route == "container" then self:ProcessContainerLoot(); return end
    if route == "fishing" then self:ProcessFishingLoot(); return end
    if route == "npc" then self:ProcessNPCLoot(); return end
end

-- =====================================================================
-- LOOT EVENT HANDLERS
-- =====================================================================

---LOOT_OPENED handler (warcraft.wiki.gg/wiki/LOOT_OPENED).
---Fires AFTER LOOT_READY, but ONLY when the loot frame is actually rendered.
---Fast auto-loot or third-party auto-loot addons may skip this entirely.
---When it does fire, it provides the best-quality data: fresh unit GUIDs + isFromItem flag.
---@param event string
---@param autoLoot boolean
---@param isFromItem boolean Added in 8.3.0, true if loot is from opening a container item
function WarbandNexus:OnTryCounterLootOpened(event, autoLoot, isFromItem)
    CaptureLootSessionState()
    lootSession.opened = true
    RouteLootSession(self, "opened", isFromItem)
end


-- =====================================================================
-- PROCESSING PATHS
-- =====================================================================

---Collect ALL unique loot source GUIDs from the loot window.
---GetLootSourceInfo(slot) returns guid1, quantity1, guid2, quantity2, ... for merged loot.
---Using only the first return misses every other corpse in a combined AoE window (try count ×1).
---Falls back to UnitGUID("npc") which is set during some NPC/object interactions.
---@return table uniqueGUIDs Array of unique safe GUID strings (may be empty)
GetAllLootSourceGUIDs = function()
    local uniqueGUIDs = {}
    local seen = {}

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
                    local safeGUID = SafeGuardGUID(sourceGUID)
                    if safeGUID and not seen[safeGUID] then
                        seen[safeGUID] = true
                        uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
                    end
                end
            end
        end
    end

    -- Method 2: UnitGUID("npc") — only real mob corpses; Player tokens inflate src= without matching npcId.
    local ok, npcGUID = pcall(UnitGUID, "npc")
    if ok and npcGUID then
        local safeGUID = SafeGuardGUID(npcGUID)
        if safeGUID and not seen[safeGUID] then
            local pfx = safeGUID:match("^(%a+)")
            if pfx == "Creature" or pfx == "Vehicle" or GetNPCIDFromGUID(safeGUID) then
                seen[safeGUID] = true
                uniqueGUIDs[#uniqueGUIDs + 1] = safeGUID
            end
        end
    end

    return uniqueGUIDs
end

-- =====================================================================
-- SOURCE RESOLVERS (P1-P4) — each populates ctx when a match is found.
-- ProcessNPCLoot calls them in strict sequence; first match wins.
-- Every match requires EXACT ID equality (npcID in npcDropDB, objectID
-- in objectDropDB, etc.). No heuristic guessing.
-- =====================================================================

---Shared context for source resolution chain.
---@class ResolveCtx
---@field drops table|nil       Drop table matched (exactly one or nil)
---@field matchedNpcID number|nil  NPC ID if matched via npcDropDB
---@field dedupGUID string|nil     GUID to mark as processed
---@field targetGUID string|nil    GUID from unit fallback path
---@field sourceIsGameObject boolean  True if any source GUID was a GameObject
---@field lastMatchedObjectID number|nil  Object ID if matched via objectDropDB

---Exact-match a single GUID against npcDropDB (eligible only) and objectDropDB.
---@param guid string
---@return table|nil drops, number|nil npcID, number|nil objectID
local function MatchGuidExact(guid)
    if not guid or type(guid) ~= "string" then return nil end
    local npcID = GetNPCIDFromGUID(guid)
    if npcID and tryCounterNpcEligible[npcID] and npcDropDB[npcID] then
        return npcDropDB[npcID], npcID, nil
    end
    local objectID = GetObjectIDFromGUID(guid)
    if objectID and objectDropDB[objectID] then
        return objectDropDB[objectID], nil, objectID
    end
    return nil
end

---How many distinct non-GameObject loot sources in this window share the same npcDropDB
---table as `dropsTable` (Lua reference equality only).
---NOTE: LoadRuntimeSourceTables uses CopyDropArray per NPC id, so clones of the same logical mount
---(e.g. Bloodfeaster on Ritualist vs Drudge) are different tables — use CountCorpsesForMissedDropItems.
---@param allSourceGUIDs table
---@param dropsTable table
---@return number
local function CountCorpsesSharingDropTable(allSourceGUIDs, dropsTable)
    if not dropsTable or not allSourceGUIDs or #allSourceGUIDs == 0 then return 1 end
    local seen = {}
    local n = 0
    for i = 1, #allSourceGUIDs do
        local g = allSourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) then
            if not g:match("^GameObject") and not seen[g] then
                seen[g] = true
                local d2 = MatchGuidExact(g)
                if d2 == dropsTable then
                    n = n + 1
                end
            end
        end
    end
    return math.max(1, n)
end

---Distinct sources for this npc: strict id from parser, else Creature/Vehicle GUID containing "-npcID-"
---(spawn UID quirks can make GetNPCIDFromGUID miss one corpse while the entry id still appears in the string).
---@param allSourceGUIDs table
---@param npcID number
---@return number
local function CountUniqueLootSourcesForNpcID(allSourceGUIDs, npcID)
    if not npcID or not allSourceGUIDs or #allSourceGUIDs == 0 then return 0 end
    local needle = "-" .. tostring(npcID) .. "-"
    local seen = {}
    local n = 0
    for i = 1, #allSourceGUIDs do
        local g = allSourceGUIDs[i]
        if type(g) == "string" and not (issecretvalue and issecretvalue(g)) and not seen[g] then
            seen[g] = true
            if not g:match("^GameObject") then
                if GetNPCIDFromGUID(g) == npcID then
                    n = n + 1
                elseif (g:match("^Creature") or g:match("^Vehicle")) and g:find(needle, 1, true) then
                    n = n + 1
                end
            end
        end
    end
    return n
end

local function NpcDropEntryContainsAnyItemSet(dropsTable, itemIdSet)
    if not dropsTable or not itemIdSet then return false end
    for i = 1, #dropsTable do
        local d = dropsTable[i]
        if type(d) == "table" and d.itemID and itemIdSet[d.itemID] then
            return true
        end
    end
    return false
end

---@param dlist table[]
---@return table itemID -> true
local function BuildItemIdSetFromDropList(dlist)
    local s = {}
    if not dlist then return s end
    for i = 1, #dlist do
        local d = dlist[i]
        if d and d.itemID then s[d.itemID] = true end
    end
    return s
end

---NPC ids eligible for try counter whose drop table lists any of the missed itemIDs (same mount, many npc templates).
---@param itemIdSet table
---@return number[]
local function BuildNpcIdsEligibleForDropItemSet(itemIdSet)
    local out = {}
    if not itemIdSet then return out end
    local any = false
    for _ in pairs(itemIdSet) do any = true; break end
    if not any then return out end
    for npcId, dt in pairs(npcDropDB) do
        if tryCounterNpcEligible[npcId] and type(dt) == "table" and NpcDropEntryContainsAnyItemSet(dt, itemIdSet) then
            out[#out + 1] = npcId
        end
    end
    return out
end

---Corpses in merged loot that can drop the same missed item(s), across npc ids (fixes CopyDropArray table split).
---@param allSourceGUIDs table
---@param itemIdSet table
---@param candidateNpcIds number[]
---@return number
local function CountCorpsesForMissedDropItems(allSourceGUIDs, itemIdSet, candidateNpcIds)
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
                local nid = GetNPCIDFromGUID(g)
                if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then
                    if NpcDropEntryContainsAnyItemSet(npcDropDB[nid], itemIdSet) then
                        ok = true
                    end
                end
                if not ok and candidateNpcIds and #candidateNpcIds > 0 and (g:match("^Creature") or g:match("^Vehicle")) then
                    for c = 1, #candidateNpcIds do
                        local npcId = candidateNpcIds[c]
                        local needle = "-" .. tostring(npcId) .. "-"
                        if g:find(needle, 1, true) and npcDropDB[npcId] and NpcDropEntryContainsAnyItemSet(npcDropDB[npcId], itemIdSet) then
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

---Stable key for open-world merged loot (order-independent source GUID list).
---@param guids table
---@return string
local function BuildSortedSourceFingerprint(guids)
    if not guids or #guids == 0 then return "" end
    local t = {}
    for i = 1, #guids do
        t[i] = guids[i]
    end
    table.sort(t)
    return table.concat(t, "\0")
end

---P1: Resolve from per-slot source GUIDs (GetLootSourceInfo + UnitGUID("npc")).
---Each GUID is checked in order; first MatchGuidExact hit wins (see file header: AoE).
---Already-processed GUIDs are skipped.
---@return boolean|nil earlyExit  true = all GUIDs processed (caller should return)
local function ResolveFromGUIDs(ctx, sourceGUIDs, addon)
    if not sourceGUIDs or #sourceGUIDs == 0 then return nil end

    local allProcessed = true
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if srcGUID:match("^GameObject") then ctx.sourceIsGameObject = true end
        if processedGUIDs[srcGUID] then
            -- already handled
        else
            allProcessed = false
            local drops, npcID, objectID = MatchGuidExact(srcGUID)
            if drops then
                ctx.drops = drops
                ctx.matchedNpcID = npcID
                ctx.lastMatchedObjectID = objectID
                ctx.dedupGUID = srcGUID
                if IsTryCounterLootDebugEnabled(addon) then
                    TryCounterLootDebug(addon, "match", "P1 %s npc=%s obj=%s", srcGUID:sub(1,20), tostring(npcID), tostring(objectID))
                end
                return nil
            end
        end
    end
    if allProcessed then
        -- Every source GUID was already counted this session (PROCESSED_GUID_TTL). Partial loot + reopen
        -- hits this path so we do not apply another try increment for the same corpses.
        if IsTryCounterLootDebugEnabled(addon) then TryCounterLootDebug(addon, "skip", "P1 all GUIDs processed") end
        return true
    end
    -- Keep first unprocessed GUID for housekeeping even when no drop table matched
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if not processedGUIDs[srcGUID] then ctx.dedupGUID = srcGUID; break end
    end
    return nil
end

---P2: Resolve from unit GUIDs (npc/mouseover/target/lastLoot).
---Only runs when P1 found no match. Each GUID requires exact ID equality.
local function ResolveFromUnits(ctx, numLoot, addon)
    if ctx.drops then return end
    local lootIsEmpty = (numLoot == 0)

    if IsTryCounterLootDebugEnabled(addon) then
        local now = GetTime()
        TryCounterLootDebug(addon, "flow", "P2 npc=%s mo=%s tg=%s last=%s",
            lootSession.npcGUID and "Y" or "-", lootSession.mouseoverGUID and "Y" or "-",
            lootSession.targetGUID and "Y" or "-", lastLootSourceGUID and "Y" or "-")
    end

    -- Try each candidate; first exact match wins.
    local candidates = {
        lootSession.npcGUID,
        lootSession.mouseoverGUID,
        lootSession.targetGUID,
    }
    if lastLootSourceGUID and (GetTime() - lastLootSourceTime) <= LAST_LOOT_SOURCE_TTL then
        candidates[#candidates + 1] = lastLootSourceGUID
    end
    for i = 1, #candidates do
        local guid = candidates[i]
        if guid and (lootIsEmpty or not processedGUIDs[guid]) then
            local drops, npcID, objectID = MatchGuidExact(guid)
            if drops then
                ctx.drops = drops
                ctx.matchedNpcID = npcID
                ctx.lastMatchedObjectID = objectID
                ctx.dedupGUID = guid
                ctx.targetGUID = guid
                if IsTryCounterLootDebugEnabled(addon) then
                    TryCounterLootDebug(addon, "match", "P2 %s npc=%s obj=%s", guid:sub(1,20), tostring(npcID), tostring(objectID))
                end
                return
            end
        end
    end
    if IsTryCounterLootDebugEnabled(addon) then TryCounterLootDebug(addon, "miss", "P2 no match") end
end

---P3: Resolve from zone pools (rare-only or hostile-only zones).
---raresOnly: requires rare-class unit on mouseover/target/npc + open world.
---hostileOnly: any killable mob in zone (looting a corpse implies hostile).
local function ResolveFromZone(ctx, inInstance, addon)
    if ctx.drops then return end
    if not next(zoneDropDB) then return end
    if ctx.sourceIsGameObject or inInstance then return end

    if (GetTime() - lastEncounterEndTime) < RECENT_KILL_TTL then
        if IsTryCounterLootDebugEnabled(addon) then TryCounterLootDebug(addon, "skip", "P3 suppressed (recent ENC)") end
        return
    end

    local rareLike
    local function CheckRareLike()
        if rareLike ~= nil then return rareLike end
        rareLike = false
        local rareUnitTokens = {"mouseover", "target", "npc"}
        for i = 1, #rareUnitTokens do
            local unit = rareUnitTokens[i]
            local ok, cls = pcall(UnitClassification, unit)
            if ok and cls and (not issecretvalue or not issecretvalue(cls)) then
                if cls == "rare" or cls == "rareelite" or cls == "worldboss" then
                    rareLike = true
                    break
                end
            end
        end
        return rareLike
    end

    local mapID = GetSafeMapID()
    while mapID and mapID > 0 do
        local zData = zoneDropDB[mapID]
        if type(zData) == "table" then
            if zData.hostileOnly == true then
                ctx.drops = zData.drops or zData
                if IsTryCounterLootDebugEnabled(addon) then TryCounterLootDebug(addon, "match", "P3 zone=%s (hostileOnly)", tostring(mapID)) end
                return
            end
            if zData.raresOnly == true and CheckRareLike() then
                ctx.drops = zData.drops or zData
                if IsTryCounterLootDebugEnabled(addon) then TryCounterLootDebug(addon, "match", "P3 zone=%s (raresOnly)", tostring(mapID)) end
                return
            end
        end
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
        local nextID = mapInfo and mapInfo.parentMapID
        mapID = (nextID and (not issecretvalue or not issecretvalue(nextID))) and nextID or nil
    end
end

---P4: Resolve from recentKills (ENCOUNTER_END boss entries).
---Only matches encounter NPCs that are in npcDropDB AND eligible.
local function ResolveFromRecentKills(ctx, inInstance)
    if ctx.drops then return end
    local now = GetTime()
    for guid, killData in pairs(recentKills) do
        if not processedGUIDs[guid] and killData.isEncounter then
            local alive = (now - killData.time < ENCOUNTER_OBJECT_TTL)
            -- When P1/P2 identified a GameObject source but no drops matched,
            -- an encounter chest (boss loot chest) should still attribute to the boss.
            local canMatch = not ctx.dedupGUID or ctx.sourceIsGameObject
            if alive and canMatch then
                local nid = killData.npcID
                if nid and tryCounterNpcEligible[nid] and npcDropDB[nid] then
                    ctx.drops = npcDropDB[nid]
                    ctx.matchedNpcID = nid
                    ctx.dedupGUID = guid
                    return
                end
            end
        end
    end
end

-- =====================================================================
-- ProcessNPCLoot — orchestrator: P1→P2→P3→P4, first match wins, exact IDs only.
-- =====================================================================

---DungeonEncounterID for CHAT/loot dedup (must match BuildTryCountSourceKey encounter_*).
---@param npcID number|nil
---@return number|nil
local function GetEncounterIDForNpcID(npcID)
    if not npcID or not encounterDB then return nil end
    for encID, npcList in pairs(encounterDB) do
        for j = 1, #npcList do
            if npcList[j] == npcID then return encID end
        end
    end
    return nil
end

---Try-counter source key for dedup. Open-world NPCs append loot GUID so each corpse counts;
---encounters use encounter id only (double paths, same kill).
---@param matchedEncounterID number|nil
---@param matchedNpcID number|nil
---@param lastMatchedObjectID number|nil
---@param dedupGUID string|nil
---@return string|nil
local function BuildTryCountSourceKey(matchedEncounterID, matchedNpcID, lastMatchedObjectID, dedupGUID)
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

function WarbandNexus:ProcessNPCLoot()
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
    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "flow", "NPC loot=%d src=%d", numLoot, #allSourceGUIDs) end

    -- P1: Per-slot source GUIDs (most reliable — exact GUID→ID)
    local earlyExit = ResolveFromGUIDs(ctx, allSourceGUIDs, self)
    if earlyExit then return end

    -- P2: Unit GUIDs — only when P1 found nothing (no fallback after a P1 match)
    if not ctx.drops then
        ResolveFromUnits(ctx, numLoot, self)
    end

    -- P3: Zone raresOnly pools (Midnight zone rare mounts, open world only)
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if not ctx.drops then
        ResolveFromZone(ctx, inInstance, self)
    end

    -- P4: Encounter recentKills (instance boss bookkeeping)
    if not ctx.drops then
        ResolveFromRecentKills(ctx, inInstance)
    end

    if not ctx.drops then
        local recentKillsCount = 0
        for _ in pairs(recentKills) do recentKillsCount = recentKillsCount + 1 end
        if IsTryCounterLootDebugEnabled(self) then
            TryCounterLootDebug(self, "miss", "NPC no match loot=%d src=%d kills=%d", numLoot, #allSourceGUIDs, recentKillsCount)
        end
        if inInstance and not self._pendingEncounterLootRetried then
            self._pendingEncounterLoot = true
        end
        return
    end
    self._pendingEncounterLoot = nil
    if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "match", "NPC drops matched") end

    -- Unpack ctx into locals for readability in post-match processing
    local drops = ctx.drops
    local matchedNpcID = ctx.matchedNpcID
    local dedupGUID = ctx.dedupGUID
    local lastMatchedObjectID = ctx.lastMatchedObjectID

    -- Daily/weekly lockout check
    local isLockoutSkip = matchedNpcID and IsLockoutDuplicate(matchedNpcID)
    if isLockoutSkip then if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "lockout npc=%s", tostring(matchedNpcID)) end end

    -- Auto-discovery: if this NPC has drops but no lockout quest, schedule discovery
    if matchedNpcID and not lockoutQuestsDB[matchedNpcID] and (npcDropDB[matchedNpcID] or (ns.CollectibleSourceDB and ns.CollectibleSourceDB.rares and ns.CollectibleSourceDB.rares[matchedNpcID])) then
        discoveryPendingNpcID = matchedNpcID
        discoveryPendingTime = GetTime()
        C_Timer.After(2, TryDiscoverLockoutQuest)
    end

    -- ===================================================================
    -- HOUSEKEEPING: Mark GUIDs and clean encounter entries BEFORE filtering.
    -- These MUST run even when all drops are collected (#trackable == 0),
    -- otherwise encounter entries leak and block subsequent boss loot in
    -- multi-boss raids, or cause spurious matches on mining/herbing/skinning
    -- LOOT_OPENED events while still inside the instance.
    -- ===================================================================

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
    local encounterDiffID = ResolveEffectiveEncounterDifficultyID(inInstance, recentKillDiff)
    if IsTryCounterLootDebugEnabled(self) and recentKillDiff and encounterDiffID
        and recentKillDiff ~= encounterDiffID then
        TryCounterLootDebug(self, "flow", "diff prefer instance=%s over ENC=%s",
            tostring(encounterDiffID), tostring(recentKillDiff))
    end

    -- Look up encounter ID for this NPC (reused for cleanup, dedup, and key setting).
    local matchedEncounterID = nil
    local matchedEncounterNpcs = nil
    if matchedNpcID then
        for encID, npcList in pairs(encounterDB or {}) do
            for j = 1, #npcList do
                local nid = npcList[j]
                if nid == matchedNpcID then
                    matchedEncounterID = encID
                    matchedEncounterNpcs = npcList
                    break
                end
            end
            if matchedEncounterID then break end
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
                if killData.isEncounter and npcSet[killData.npcID] then recentKills[guid] = nil end
            end
        else
            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and killData.npcID == matchedNpcID then recentKills[guid] = nil end
            end
        end
    end

    -- Filter drops: repeatable + uncollected, difficulty-gated (shared with CHAT / ENC delayed).
    local trackable, diffSkipped = FilterDropsByDifficulty(drops, encounterDiffID)
    if #trackable == 0 then
        if IsTryCounterLootDebugEnabled(self) then
            TryCounterLootDebug(self, "skip", "NPC trackable=0 (collected/diff)")
        end
        if diffSkipped then
            local itemLink = GetDropItemLink(diffSkipped.drop)
            local currentLabel = DIFFICULTY_ID_TO_LABELS[encounterDiffID] or tostring(encounterDiffID or "?")
            local skipDedupKey = (matchedEncounterID and ("diffskip_enc_" .. tostring(matchedEncounterID)))
                or (matchedNpcID and ("diffskip_npc_" .. tostring(matchedNpcID)))
                or ("diffskip_item_" .. tostring(diffSkipped.drop and diffSkipped.drop.itemID or 0))
            local tSkip = GetTime()
            if skipDedupKey ~= lastDifficultySkipChatKey or (tSkip - lastDifficultySkipChatTime) >= SKIP_CHAT_DEDUP_SEC then
                lastDifficultySkipChatKey = skipDedupKey
                lastDifficultySkipChatTime = tSkip
                TryChat(format(
                    "|cff9370DB[WN-Counter]|r |cff888888" ..
                    ((ns.L and ns.L["TRYCOUNTER_DIFFICULTY_SKIP"]) or "Skipped: %s requires %s difficulty (current: %s)"),
                    itemLink, diffSkipped.required, currentLabel
                ))
            end
        end
        -- Dedup: same encounter key as successful loot path so ENC delayed / CHAT cannot +1 this kill.
        if matchedEncounterID then
            lastTryCountSourceKey = "encounter_" .. tostring(matchedEncounterID)
            lastTryCountSourceTime = GetTime()
        end
        return
    end

    -- Scan loot window (use state captured at LOOT_OPENED start)
    local found = ScanLootForItems(trackable, lootSession.numLoot, lootSession.slotData)
    if IsTryCounterLootDebugEnabled(self) then
        local foundCount = 0
        for _ in pairs(found) do foundCount = foundCount + 1 end
        TryCounterLootDebug(self, "flow", "NPC track=%d found=%d loot=%d", #trackable, foundCount, numLoot)
    end

    -- Repeatable drops FOUND in loot → reset try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = GetTryCountTypeAndKey(drop)
            if tryKey then
                local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                if drop.type == "item" then
                    lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    lastTryCountSourceTime = GetTime()
                end
                if tcType ~= "item" and preResetCount and preResetCount > 0 then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = GetDropItemLink(drop)
                TryChat(BuildObtainedChat("TRYCOUNTER_OBTAINED_RESET", "Obtained %s! Try counter reset.", itemLink, preResetCount))
                if drop.type == "item" and WarbandNexus.SendMessage then
                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                    WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                        type = "item",
                        id = drop.itemID,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                        fromTryCounter = true,
                    })
                end
            end
        end
    end

    -- Non-repeatable drops FOUND in loot → notification (mount/pet/toy from boss)
    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and found[drop.itemID] then
            if drop.type == "item" then MarkItemObtained(drop.itemID) end
            local tcType, tryKey = GetTryCountTypeAndKey(drop)
            if tryKey then
                local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
                if currentCount and currentCount > 0 then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = currentCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = GetDropItemLink(drop)
                TryChat(BuildObtainedChat("TRYCOUNTER_OBTAINED", "Obtained %s!", itemLink, currentCount))
                if WarbandNexus.SendMessage then
                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(drop.itemID)
                    WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                        type = drop.type,
                        id = (drop.type == "item") and drop.itemID or tryKey,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = currentCount,
                        fromTryCounter = true,
                    })
                end
            end
        end
    end

    -- Pre-cache try counts for all non-repeatable mounts/pets/toys (BoP auto-collect handling).
    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and drop.type ~= "item" then
            local tryKey = GetTryCountKey(drop)
            if tryKey then
                local currentCount = WarbandNexus:GetTryCount(drop.type, tryKey)
                local cacheKey = drop.type .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = currentCount
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
            end
        end
    end

    -- Skip increment if lockout duplicate (GUID + encounter cleanup above still ran).
    if isLockoutSkip then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "lockout active") end
        local lockDedupKey = (matchedEncounterID and ("lockskip_enc_" .. tostring(matchedEncounterID)))
            or (matchedNpcID and ("lockskip_npc_" .. tostring(matchedNpcID)))
            or "lockskip_generic"
        local tLock = GetTime()
        if lockDedupKey ~= lastLockoutSkipChatKey or (tLock - lastLockoutSkipChatTime) >= SKIP_CHAT_DEDUP_SEC then
            lastLockoutSkipChatKey = lockDedupKey
            lastLockoutSkipChatTime = tLock
            TryChat("|cff9370DB[WN-Counter]|r |cff888888" .. ((ns.L and ns.L["TRYCOUNTER_LOCKOUT_SKIP"]) or "Skipped: daily/weekly lockout active for this NPC."))
        end
        return
    end

    -- Build increment list (drops NOT found in loot).
    local dropsToIncrement = {}
    for i = 1, #trackable do
        if not found[trackable[i].itemID] then dropsToIncrement[#dropsToIncrement + 1] = trackable[i] end
    end

    -- Merged AoE loot: count distinct creature sources. tableMult uses Lua table identity on npcDropDB
    -- (runtime CopyDropArray splits shared logical drops across npc ids — see itemMult).
    -- Must run for non-repeatable mounts/pets too (CLEU path removed on Midnight). When
    -- statisticIds exist, ProcessMissedDrops uses ReseedStatistics instead of manual deltas;
    -- keep mult=1 there to avoid implying per-corpse stats (attemptTimes unused on that branch).
    local farmCorpseMult = 1
    do
        local statBacked = drops and NpcEntryHasStatisticIds(drops)
        if matchedNpcID and not matchedEncounterID and not lastMatchedObjectID and not statBacked then
            local tableMult = CountCorpsesSharingDropTable(allSourceGUIDs, drops)
            local npcMult = CountUniqueLootSourcesForNpcID(allSourceGUIDs, matchedNpcID)
            local tryItemSet = BuildItemIdSetFromDropList(dropsToIncrement)
            local candidateList = BuildNpcIdsEligibleForDropItemSet(tryItemSet)
            local itemMult = CountCorpsesForMissedDropItems(allSourceGUIDs, tryItemSet, candidateList)
            farmCorpseMult = math.max(1, tableMult, npcMult, itemMult)
            if IsTryCounterLootDebugEnabled(self) and farmCorpseMult > 1 then
                TryCounterLootDebug(self, "count", "NPC farm corpses=%d (table=%d npcId=%d item=%d src=%d)",
                    farmCorpseMult, tableMult, npcMult, itemMult, #allSourceGUIDs)
            end
        end
    end

    -- Same kill / double-path dedup only (key includes corpse GUID for open-world NPCs).
    local tryCountSourceKey = BuildTryCountSourceKey(matchedEncounterID, matchedNpcID, lastMatchedObjectID, dedupGUID)
    if #dropsToIncrement > 0 and tryCountSourceKey and lastTryCountSourceKey == tryCountSourceKey and (now - lastTryCountSourceTime) < 15 then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "already counted (%s)", tostring(lastTryCountSourceKey)) end
        dropsToIncrement = {}
    end

    -- Fingerprint dedup: same npc + same multiset of loot source GUIDs = one miss-increment wave.
    local mergeFp = nil
    local openWorldFarm = matchedNpcID and not matchedEncounterID and not lastMatchedObjectID
    local statNoStats = not (drops and NpcEntryHasStatisticIds(drops))
    if openWorldFarm and statNoStats and #dropsToIncrement > 0 and #allSourceGUIDs > 0 then
        mergeFp = tostring(matchedNpcID) .. "\1" .. BuildSortedSourceFingerprint(allSourceGUIDs)
        local tMerge = mergedLootTryCountedAt[mergeFp]
        if tMerge and (now - tMerge) < MERGED_LOOT_TRY_DEDUP_TTL then
            if IsTryCounterLootDebugEnabled(self) then
                TryCounterLootDebug(self, "skip", "merged loot fp dedup (%.0fs ago)", now - tMerge)
            end
            dropsToIncrement = {}
            farmCorpseMult = 1
            mergeFp = nil
        end
    end

    local willIncrementMisses = #dropsToIncrement > 0

    lastTryCountSourceKey = tryCountSourceKey
    lastTryCountSourceTime = GetTime()
    if tryCountSourceKey then
        lastTryCountLootSourceGUID = (type(dedupGUID) == "string" and dedupGUID) or allSourceGUIDs[1]
    else
        lastTryCountLootSourceGUID = nil
    end

    -- Increment try counts
    local statIds = drops and drops.statisticIds or nil
    if IsTryCounterLootDebugEnabled(self) and #dropsToIncrement > 0 then
        TryCounterLootDebug(self, "flow", "NPC missDrops=%d corpseMult=%d", #dropsToIncrement, farmCorpseMult)
        TryCounterLootDebug(self, "count", "NPC +%d row(s) x%d corpseMult (%s)",
            #dropsToIncrement, farmCorpseMult,
            matchedNpcID and ("npc " .. tostring(matchedNpcID)) or (lastMatchedObjectID and ("obj " .. tostring(lastMatchedObjectID)) or "zone"))
    end
    ProcessMissedDrops(dropsToIncrement, statIds, { attemptTimes = farmCorpseMult })
    if mergeFp and willIncrementMisses then
        mergedLootTryCountedAt[mergeFp] = GetTime()
    end
end

---Process loot from fishing.
---Algorithm (source-agnostic): one loot open in a trackable zone = one attempt.
---We do NOT care what dropped (common/rare); we only check: is the trackable drop (e.g. Nether-Warped Egg) in the loot?
---If yes → reset try count; if no → increment. So every fishing LOOT_OPENED in zone is counted.
function WarbandNexus:ProcessFishingLoot()
    local drops, inInstance = CollectFishingDropsForZone()
    if inInstance then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "FISH in instance") end
        return
    end
    if #drops == 0 then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "FISH no drops for zone") end
        return
    end
    local trackable = {}
    for i = 1, #drops do
        local d = drops[i]
        if d.repeatable or not IsCollectibleCollected(d) then trackable[#trackable + 1] = d end
    end
    if #trackable == 0 then
        if IsTryCounterLootDebugEnabled(self) then TryCounterLootDebug(self, "skip", "FISH all collected") end
        return
    end

    fishingCtx.lootWasFishing = true -- so LOOT_CLOSED only clears fishingCtx.active when this loot window closes (avoids clearing after unrelated loot)

    -- Scan loot window (use state captured at LOOT_OPENED start)
    local found = ScanLootForItems(trackable, lootSession.numLoot, lootSession.slotData)
    if IsTryCounterLootDebugEnabled(self) then
        local foundCount = 0
        for _ in pairs(found) do foundCount = foundCount + 1 end
        TryCounterLootDebug(self, "flow", "FISH track=%d found=%d loot=%d", #trackable, foundCount, lootSession.numLoot)
    end

    -- Check for repeatable mounts that were FOUND in loot -> reset their try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = GetTryCountTypeAndKey(drop)
            if tryKey then
                local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                
                -- Set debounce key to prevent CHAT_MSG_LOOT from also resetting (if item type is "item")
                if drop.type == "item" then
                    lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    lastTryCountSourceTime = GetTime()
                end
                
                if tcType ~= "item" and preResetCount and preResetCount > 0 then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = GetDropItemLink(drop)
                TryChat(BuildObtainedChat("TRYCOUNTER_CAUGHT_RESET", "Caught %s! Try counter reset.", itemLink, preResetCount))
                -- Fire notification (BAM moment)
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                if WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                        type = tcType,
                        id = tryKey,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                        fromTryCounter = true,
                    })
                end
            end
        end
    end

    -- Non-repeatable drops FOUND in loot (e.g. Nether-Warped Egg -> Nether-Warped Drake): reset reflected try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and found[drop.itemID] and drop.tryCountReflectsTo then
            MarkItemObtained(drop.itemID)
            local tcType, tryKey = GetTryCountTypeAndKey(drop)
            if tryKey then
                local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                if preResetCount and preResetCount > 0 then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                lastTryCountSourceTime = GetTime()
                local itemLink = GetDropItemLink(drop)
                TryChat(BuildObtainedChat("TRYCOUNTER_CAUGHT", "Caught %s!", itemLink, preResetCount))
                -- Fire notification (BAM moment)
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                if WarbandNexus.SendMessage then
                    WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                        type = tcType,
                        id = tryKey,
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                        fromTryCounter = true,
                    })
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

    if IsTryCounterLootDebugEnabled(self) then
        TryCounterLootDebug(self, (#missed > 0) and "count" or "reset", "FISH %s", (#missed > 0) and ("+" .. #missed) or "reset (caught)")
    end
    if #missed > 0 then
        lastTryCountSourceKey = "fishing_open"
        lastTryCountSourceTime = GetTime()
    end
        ProcessMissedDrops(missed, nil)
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
            -- Repeatable container opens always count; one-time only while uncollected
            if drop.repeatable or not IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        end
        if #trackable == 0 then return end

        -- Scan loot window (use state captured at LOOT_OPENED start)
        local found = ScanLootForItems(trackable, lootSession.numLoot, lootSession.slotData)

        -- Check for drops that were FOUND in loot (repeatable or not) -> reset try count (use reflected type/key for item->mount)
        for i = 1, #trackable do
            local drop = trackable[i]
            if found[drop.itemID] then
                if not drop.repeatable and drop.type == "item" then
                    MarkItemObtained(drop.itemID)
                end
                local tcType, tryKey = GetTryCountTypeAndKey(drop)
                if tryKey then
                    ResolveCollectibleID(drop)
                    local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                    WarbandNexus:ResetTryCount(tcType, tryKey)
                    if drop.type == "item" then
                        lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                        lastTryCountSourceTime = GetTime()
                    end
                    if tcType ~= "item" and preResetCount and preResetCount > 0 then
                        local cacheKey = tcType .. "\0" .. tostring(tryKey)
                        pendingPreResetCounts[cacheKey] = preResetCount
                        C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                    end
                    local itemLink = GetDropItemLink(drop)
                    local chatKey = drop.repeatable and "TRYCOUNTER_CONTAINER_RESET" or "TRYCOUNTER_CONTAINER"
                    local chatFallback = drop.repeatable and "Obtained %s from container! Try counter reset." or "Obtained %s from container!"
                    TryChat(BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                    -- Fire notification for all types (BAM moment)
                    if WarbandNexus.SendMessage then
                        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                        WarbandNexus:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                            type = tcType,
                            id = (drop.type == "item") and drop.itemID or tryKey,
                            name = itemName or drop.name or "Unknown",
                            icon = itemIcon,
                            preResetTryCount = preResetCount,
                            fromTryCounter = true,
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
                    for i = 1, #drops do
                        local drop = drops[i]
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
                for i = 1, #drops do
                    local drop = drops[i]
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
    end
    BuildTryCounterNpcEligible()
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

--- Rarity's AceDB often isn't readable on the same frame as WN login; re-run max-merge after Statistics seed.
--- `perCharStatSyncSerial` matches SchedulePerCharacterStatisticsAndRaritySync so alt-swaps cancel stale timers.
local function ScheduleDeferredRarityMountMaxSync(delaySec)
    local syncSerial = perCharStatSyncSerial
    delaySec = tonumber(delaySec) or 2
    C_Timer.After(delaySec, function()
        if syncSerial ~= perCharStatSyncSerial then return end
        if not tryCounterReady or not EnsureDB() then return end
        if WarbandNexus.SyncRarityMountAttemptsMax then
            WarbandNexus:SyncRarityMountAttemptsMax()
        end
    end)
end

local function SeedFromStatistics()
    if not EnsureDB() then return end
    if not GetStatistic then return end

    PruneStatisticSnapshotsOrphanKeys()
    RebuildMergedStatisticSeedIndex()

    local charKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if not charKey then return end

    local P = ns.Profiler
    if P then P:StartAsync("SeedFromStatistics") end
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
    local seedQueue = {}
    for i = 1, #mergedStatSeedGroupList do
        seedQueue[#seedQueue + 1] = { bucket = mergedStatSeedGroupList[i] }
    end
    for p = 1, #statSeedTryKeyPending do
        local pend = statSeedTryKeyPending[p]
        local sids = ResolveReseedStatIdsForDrop(pend.drop, pend.npcStatIds)
        if sids and #sids > 0 then
            seedQueue[#seedQueue + 1] = {
                drop = pend.drop,
                statIds = sids,
                npcStatIds = pend.npcStatIds,
            }
        end
    end

    local queueIdx = 1
    local seeded = 0
    local unresolvedDrops = {}

    local function ProcessBatch()
        if not EnsureDB() then return end
        local batchStart = debugprofilestop()

        while queueIdx <= #seedQueue do
            local entry = seedQueue[queueIdx]

            local function ProcessBatchDrop(drop, thisCharTotal, npcStatIdsForUnresolved)
                if not drop.guaranteed then
                    local tcType, tryKey = GetTryCountTypeAndKey(drop)
                    if tryKey then
                        charSnapshot[tryKey] = thisCharTotal
                        local globalTotal = 0
                        for _, snap in pairs(snapshots) do
                            local charVal = snap[tryKey]
                            if charVal and charVal > 0 then
                                globalTotal = globalTotal + charVal
                            end
                        end
                        local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
                        if globalTotal > currentCount then
                            WarbandNexus:SetTryCount(tcType, tryKey, globalTotal)
                            if drop.type == "item" and drop.questStarters then
                                for j = 1, #drop.questStarters do
                                    local qs = drop.questStarters[j]
                                    if qs and qs.type == "mount" and qs.itemID then
                                        local k1 = ResolveCollectibleID(qs)
                                        local k2 = qs.itemID
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
                            npcStatIds = npcStatIdsForUnresolved,
                        }
                    end
                end
                if drop and drop.questStarters then
                    for j = 1, #drop.questStarters do
                        local qs = drop.questStarters[j]
                        ProcessBatchDrop(qs, thisCharTotal, npcStatIdsForUnresolved)
                    end
                end
            end

            if entry.bucket then
                local b = entry.bucket
                local thisCharTotal = SumStatisticTotalsFromIds(b.statIds)
                for di = 1, #b.drops do
                    ProcessBatchDrop(b.drops[di], thisCharTotal, nil)
                end
            else
                local thisCharTotal = SumStatisticTotalsFromIds(entry.statIds)
                ProcessBatchDrop(entry.drop, thisCharTotal, entry.npcStatIds)
            end

            queueIdx = queueIdx + 1

            if debugprofilestop() - batchStart > SEED_BUDGET_MS then
                C_Timer.After(0, ProcessBatch)
                return
            end
        end

        if P then P:StopAsync("SeedFromStatistics") end
        if LT then LT:Complete("trycounts") end
        if seeded > 0 then
            WarbandNexus:Debug("TryCounter: Seeded %d entries from WoW Statistics (char: %s)", seeded, charKey)
            if WarbandNexus.SendMessage then
                WarbandNexus:SendMessage("WN_PLANS_UPDATED", { action = "statistics_seeded" })
            end
        end

        -- Rarity may load after this batch; two passes catch late `groups.mounts` availability (max never lowers WN).
        ScheduleDeferredRarityMountMaxSync(2)
        ScheduleDeferredRarityMountMaxSync(10)

        if #unresolvedDrops > 0 then
            WarbandNexus:Debug("TryCounter: %d drops unresolved, retrying in 10s...", #unresolvedDrops)
            C_Timer.After(10, function()
                if not EnsureDB() then return end
                RebuildMergedStatisticSeedIndex()
                local retrySeeded = 0
                local stillUnresolved = {}
                for i = 1, #unresolvedDrops do
                    local uEntry = unresolvedDrops[i]
                    local drop = uEntry.drop
                    local tcType, tryKey = GetTryCountTypeAndKey(drop)
                    if tryKey then
                        local statList = ResolveMergedStatisticIdsForDrop(drop, ResolveReseedStatIdsForDrop(drop, uEntry.npcStatIds))
                        local t = SumStatisticTotalsFromIds(statList)
                        charSnapshot[tryKey] = t
                        local globalTotal = 0
                        for _, snap in pairs(snapshots) do
                            local charVal = snap[tryKey]
                            if charVal and charVal > 0 then
                                globalTotal = globalTotal + charVal
                            end
                        end
                        local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
                        if globalTotal > currentCount then
                            WarbandNexus:SetTryCount(tcType, tryKey, globalTotal)
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
                ScheduleDeferredRarityMountMaxSync(2)

                if #stillUnresolved > 0 then
                    WarbandNexus:Debug("TryCounter: %d still unresolved, final retry in 30s...", #stillUnresolved)
                    C_Timer.After(30, function()
                        if not EnsureDB() then return end
                        RebuildMergedStatisticSeedIndex()
                        local finalSeeded = 0
                        local snaps = WarbandNexus.db.global.statisticSnapshots
                        for j = 1, #stillUnresolved do
                            local fEntry = stillUnresolved[j]
                            local drop = fEntry.drop
                            local tcType, finalKey = GetTryCountTypeAndKey(drop)
                            if finalKey and snaps then
                                local statList = ResolveMergedStatisticIdsForDrop(drop, ResolveReseedStatIdsForDrop(drop, fEntry.npcStatIds))
                                local t = SumStatisticTotalsFromIds(statList)
                                if snaps[charKey] then
                                    snaps[charKey][finalKey] = t
                                end
                                local total = 0
                                for _, snap in pairs(snaps) do
                                    local v = snap[finalKey]
                                    if v and v > 0 then total = total + v end
                                end
                                local cur = WarbandNexus:GetTryCount(tcType, finalKey)
                                if total > cur then
                                    WarbandNexus:SetTryCount(tcType, finalKey, total)
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
                        ScheduleDeferredRarityMountMaxSync(2)
                    end)
                end
            end)
        end
    end

    ProcessBatch()
end

--- Schedule Statistics seed + Rarity max-merge for the current character (10s login delay; Rarity pass deferred so addon DB is up).
--- Serial token cancels superseded timers when the user swaps alts quickly or PEW fires twice.
local function SchedulePerCharacterStatisticsAndRaritySync()
    perCharStatSyncSerial = perCharStatSyncSerial + 1
    local serial = perCharStatSyncSerial
    C_Timer.After(10, function()
        if serial ~= perCharStatSyncSerial then return end
        if not tryCounterReady or not EnsureDB() then return end
        RebuildMergedStatisticSeedIndex()
        SeedFromStatistics()
    end)
    C_Timer.After(18, function()
        if serial ~= perCharStatSyncSerial then return end
        if WarbandNexus.SyncRarityMountAttemptsMax then
            WarbandNexus:SyncRarityMountAttemptsMax()
        end
    end)
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

    -- Re-load from static CollectibleSourceDB (typed sources already materialized there)
    LoadRuntimeSourceTables()

    -- Apply custom entries + disabled entries
    MergeTrackDB()

    -- Rebuild O(1) lookup indices
    BuildReverseIndices()
    RebuildMergedStatisticSeedIndex()
end

-- =====================================================================
-- INITIALIZATION
-- =====================================================================

---Initialize the automatic try counter system
function WarbandNexus:InitializeTryCounter()
    if tryCounterReady or tryCounterInitializing then return end
    tryCounterInitializing = true

    EnsureDB()

    -- Load DB references (initial load from static CollectibleSourceDB)
    LoadRuntimeSourceTables()

    -- Merge user-defined custom entries and remove disabled entries
    -- BEFORE building reverse indices so custom items are queryable.
    MergeTrackDB()

    -- Set lastContainerItemID before LOOT_OPENED: hook UseContainerItem so we know which
    -- container was opened even when LOOT_OPENED fires before ITEM_LOCK_CHANGED (e.g. Pinnacle Cache).
    if not self.useContainerItemHooked and _G.UseContainerItem and C_Container and C_Container.GetContainerItemID then
        local hookSelf = self
        local ok = pcall(function()
            hookSelf:RawHook("UseContainerItem", function(bagID, slotIndex)
                if bagID and slotIndex then
                    local safeBag = (not issecretvalue or not issecretvalue(bagID)) and bagID or nil
                    local safeSlot = (not issecretvalue or not issecretvalue(slotIndex)) and slotIndex or nil
                    if safeBag and safeSlot and safeBag >= 0 and safeBag <= 4 then
                        local itemID = C_Container.GetContainerItemID(safeBag, safeSlot)
                        if itemID and (not issecretvalue or not issecretvalue(itemID)) and containerDropDB[itemID] then
                            lastContainerItemID = itemID
                            lastContainerItemTime = GetTime()
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
    BuildReverseIndices()
    RebuildMergedStatisticSeedIndex()

    -- Merge previously discovered lockout quests from SavedVariables
    MergeDiscoveredLockoutQuests()

    -- Sync lockout state with server quest flags (prevents false increments after /reload mid-farm)
    SyncLockoutState()

    -- Pre-resolve mount/pet IDs for all known drop items (warmup cache for SeedFromStatistics)
    -- This ensures resolvedIDs is populated before statistics seeding runs.
    -- Delayed 5s (absolute ~T+6.5s). Time-budgeted to prevent frame spikes.
    C_Timer.After(5, function()
        local RESOLVE_BUDGET_MS = 3
        local resolveQueue = {}
        for _, npcData in pairs(npcDropDB) do
            if NpcEntryHasStatisticIds(npcData) then
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

    -- Per-character Statistics seed + Rarity max overlay (PLAYER_ENTERING_WORLD also schedules on alt/reload).
    -- Delayed 10s/11s — after pre-resolve (+5s) warms mount/pet IDs.
    SchedulePerCharacterStatisticsAndRaritySync()
    local kSched = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    if kSched then
        lastSyncScheduleCharKey = kSched
    end

    -- Sync lockout state with server quest flags (clean stale + pre-populate).
    -- Delayed 2s to ensure quest log data is available after login/reload.
    -- Also refreshes discovery snapshot so auto-discovery has a clean baseline.
    C_Timer.After(2, function()
        SyncLockoutState()
        TakeDiscoverySnapshot()
    end)

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
            if not data.isEncounter and now - data.time > RECENT_KILL_TTL then
                recentKills[guid] = nil
            end
        end
        for fp, ts in pairs(mergedLootTryCountedAt) do
            if now - ts > MERGED_LOOT_TRY_DEDUP_TTL + 120 then
                mergedLootTryCountedAt[fp] = nil
            end
        end
    end)

    tryCounterInitializing = false
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
    RebuildMergedStatisticSeedIndex()
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
        if #sources == 0 then
            msg("  slot " .. slot .. ": (no GetLootSourceInfo)")
        else
            for k = 1, #sources, 2 do
                local guid = sources[k]
                local qty = sources[k + 1]
                local safeGuid = guid and SafeGuardGUID(guid) or nil
                local guidStr = safeStr(guid)
                local pairLabel = (#sources > 2) and (" pair " .. ((k + 1) / 2)) or ""
                if safeGuid then
                    local nid = GetNPCIDFromGUID(safeGuid)
                    local oid = GetObjectIDFromGUID(safeGuid)
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
    for i = 1, #sampleStatIds do
        local sid = sampleStatIds[i]
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

-- =====================================================================
-- LEGACY MOUNT TRACKER IMPORT (optional cross-addon merge)
-- Reads a third-party addon global (AceDB profile.groups.mounts); only mount rows with attempts > 0.
-- Try keys: mount journal ID from C_MountJournal.GetMountFromItem(itemId), else itemId.
-- =====================================================================

local LEGACY_MOUNT_TRACKER_GLOBAL = "Ra" .. "rity"

local function ResolveMountTryKeyFromItemId(itemId)
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

--- Apply one Rarity-style row: max(WN mount keys, external attempts). Caller should load collections if needed.
---@return boolean changed
local function ApplyRarityMountAttemptsMaxToWN(self, itemId, extAttempts)
    if not itemId or itemId < 1 or not extAttempts or extAttempts < 1 then
        return false
    end
    local mountKey = ResolveMountTryKeyFromItemId(itemId)
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

--- Persist Rarity itemID → attempts in SavedVariables so users can disable Rarity and still restore via /wn rarityrestore.
local function MergeRarityProfileMountsIntoWnBackup(mounts)
    if not EnsureDB() or type(mounts) ~= "table" then
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
    if not EnsureDB() then
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
            if ApplyRarityMountAttemptsMaxToWN(self, itemId, attempts) then
                updated = updated + 1
            end
        end
    end
    if updated > 0 and self.SendMessage then
        self:SendMessage("WN_PLANS_UPDATED", { action = "legacy_mount_tracker_import" })
    end
    return updated, scanned
end

--- One-time handoff: try to load Rarity, merge several times (late AceDB init), refresh backup each successful read.
function WarbandNexus:ImportRarityMountHandoff()
    if not EnsureDB() then
        return
    end
    if InCombatLockdown() then
        self:Print("|cffff6600[WN]|r Exit combat, then run |cff00ccff/wn rarityimport|r again.")
        return
    end
    if C_AddOns and C_AddOns.LoadAddOn then
        pcall(C_AddOns.LoadAddOn, "Rarity")
    elseif LoadAddOn then
        pcall(LoadAddOn, "Rarity")
    end

    local delays = { 0.2, 1.0, 3.0, 8.0 }
    local pass = 0
    for i = 1, #delays do
        C_Timer.After(delays[i], function()
            if not EnsureDB() then
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
                        "|cff00ff00[WN]|r Rarity handoff complete. |cffffffff%d|r mount itemID(s) copied into WN backup + try counts (max). You can disable Rarity. If a count looks wrong: |cff00ccff/wn rarityrestore|r.|r",
                        bn
                    ))
                else
                    self:Print("|cffff6600[WN]|r No Rarity mount data found. Enable the |cffffcc00Rarity|r addon in Esc → AddOns, |cff00ccff/reload|r, then |cff00ccff/wn rarityimport|r.|r")
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
    if not EnsureDB() then
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
                    if ApplyRarityMountAttemptsMaxToWN(self, itemId, attempts) then
                        updated = updated + 1
                    end
                end
            end
        end
    end

    if scanned > 0 then
        MergeRarityProfileMountsIntoWnBackup(mounts)
        local tc = WarbandNexus.db.global.tryCounts
        tc.legacyMountTrackerSeedComplete = true
    end

    if updated > 0 and self.SendMessage then
        self:SendMessage("WN_PLANS_UPDATED", { action = "legacy_mount_tracker_import" })
    end

    return updated, scanned
end

---@deprecated Use SyncRarityMountAttemptsMax; kept for slash/API compatibility.
function WarbandNexus:ImportLegacyMountTrackerAttempts()
    return self:SyncRarityMountAttemptsMax()
end

function WarbandNexus:DebugResetLegacyMountTrackerSeed()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then
        self:Print("|cffff6600[WN]|r Enable debug mode first (/wn debug).")
        return
    end
    if not EnsureDB() then
        return
    end
    WarbandNexus.db.global.tryCounts.legacyMountTrackerSeedComplete = false
    self:Print("|cff00ff00[WN]|r Seed flag cleared (informational). Rarity merge does not use this flag — use |cff00ccff/wn raritysync|r with Rarity enabled, or wait for post-login sync.")
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
                    local mk = ResolveMountTryKeyFromItemId(itemId)
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

-- =====================================================================
-- NAMESPACE EXPORT
-- =====================================================================

--- Called from DatabaseCleanup (delayed) to drop snapshot rows for removed characters.
function WarbandNexus:PruneOrphanStatisticSnapshots()
    PruneStatisticSnapshotsOrphanKeys()
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
