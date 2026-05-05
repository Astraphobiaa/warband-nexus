--[[
    Warband Nexus - Try Counter Service
    Automatic try counter: Classify-Lock-Process architecture.
    Each loot session is classified into EXACTLY ONE route; no overlap.

    USER MODEL (matches CollectibleSourceDB + db.global.tryCounts):
      Source tables (CollectibleSourceDB at load + trackDB overlays) define which itemIDs count
      from which NPCs/objects/containers/fishing/zone pools/encounters.
      For each opened loot session we know the trackable rows after difficulty/lockout/collected filters.
        • If a tracked drop’s itemID appears in the loot window (or CHAT_MSG_LOOT for self): treat as
          “found” → ResetTryCount + BuildObtainedChat (first try / after N attempts).
        • If it does not appear: treat as “miss” → ProcessMissedDrops → manual +1 or ReseedStatistics
          (when statisticIds exist) + TRYCOUNTER_INCREMENT_CHAT via Fns.TryChat.
      ENCOUNTER_END (+5s) is a safety net when no loot route counted yet (same miss/reseed rules).

    Midnight 12.0.x: all ENCOUNTER_* / GetLootSourceInfo / UnitGUID / CHAT_MSG_LOOT strings guarded
      with issecretvalue before string ops; no COMBAT_LOG_EVENT_UNFILTERED subscription (forbidden).

    CENTRALIZATION (one engine, data-driven sources)
    -------------------------------------------------
      Goal: add rows in CollectibleSourceDB.sources (+ optional trackDB) only — no per-raid Lua forks.
      The service already implements ONE pipeline for every boss/rare/object:

      (1) CONTEXT — where are we?
          • Instance vs open world: IsInInstance() + instanceType; rules use
            ResolveEffectiveEncounterDifficultyID / tryCounterInstanceDiffCache / ENCOUNTER_* cache.
          • “Personal loot” vs “corpse window” vs “chest” are NOT separate code paths: they differ only
            in which signals Blizzard exposes (slot count, GetLootSourceInfo GUIDs, GameObject vs Creature,
            CHAT_MSG_LOOT). The same Classify → Route → ProcessNPCLoot chain consumes those signals.

      (2) DELIVERY SHAPE (implicit, not a per-instance script)
          • Corpse loot: Creature/Vehicle GUIDs in window or units → P1/P2.
          • Chest / object: GameObject GUID in window or on npc/mouseover/target token → P1/P2
            (objectDropDB); encounter recentKills supply difficulty when the window is empty.
          • Direct-to-bags / “personal”: often numLoot=0 + fast close; P4 recentKills + P5 encounter cache
            + ENCOUNTER_END(+5s) + CHAT_MSG_LOOT debounced fallbacks keep the same miss/found rules.

      (3) SOURCE RESOLUTION — single ordered resolver (below: P1→P5). Same order in raid & world.
      (4) BUSINESS RULES — centralized: FilterDropsByDifficulty, lockout, IsCollectibleCollected,
          ProcessMissedDrops (manual delta vs ReseedStatistics), debounce keys, Fns.TryChat.

      What still needs manual DATA (cannot be inferred safely for all mounts):
        • npcID / objectID / encounterID / encounter_name locale aliases / statisticIds / dropDifficulty —
          Blizzard does not expose a universal “this try maps to mount X” API; CollectibleSourceDB is the
          contract. Optional future: rare `lootDeliveryHint` field only for outliers.

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
        3) FISHING    — IsFishingLoot() OR bobber/pool-shaped sources in a fishable zone;
                        cast-TTL alone never classifies (prevents mob loot after a cast).
        4) NPC/OBJECT — ProcessNPCLoot (exact GUID→ID match only)
      Once classified, ALL other routes are locked out.
    
    ProcessNPCLoot resolver chain (first match wins):
      P1: Per-slot source GUIDs → exact npcID/objectID match
      P2: Unit GUIDs (npc/mo/tg/lastLoot) → only if P1 found nothing
      P3: Zone hostileOnly-only pools (e.g. Crackling Shard / any mob). raresOnly zone mounts
          are NOT matched here — those NPCs are listed in CollectibleSourceDB.npcs; try counts require
          exact GUID→npcID match (P1/P2) so wrong mobs never increment.
      P4: Encounter recentKills → instance boss bookkeeping (ENCOUNTER_END feed); must still run when
          loot GUIDs are Player-* (personal) or non-DB creatures (GuidAllowsEncounterRecentKillFallback).
      P5: ENCOUNTER_START cache → Midnight 12.0 rescue when every other GUID/ID is secret.
          Uses the pull-time snapshot (encounterID/Name/difficultyID) captured at ENCOUNTER_START,
          before secret-value enforcement kicks in. Only triggers inside instances.
      P5b: SoD mythic + unknown GameObject id on the loot list → canonical Sylvanas chest row (368304)
          when the client renames the chest object (Domination-Etched Treasure Cache) but the raid
          template/difficulty still match Sanctum Mythic.
      SlotOutcomeFirst: CollectibleSourceDB.instanceBossSlotOutcomeRules — before ProcessNPCLoot, scan
          loot slots for that boss's trackable rows when a fresh ENCOUNTER_END kill exists (secret GUID /
          chest / personal loot). Add a rule row per boss; no per-encounter Lua in TryCounterService.
    
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
      ENCOUNTER_START, ENCOUNTER_END, BOSS_KILL,
      UNIT_SPELLCAST_SENT, UNIT_SPELLCAST_CHANNEL_START, UNIT_SPELLCAST_INTERRUPTED, UNIT_SPELLCAST_FAILED_QUIET,
      ITEM_LOCK_CHANGED, PLAYER_ENTERING_WORLD, PLAYER_REGEN_ENABLED,
      CRITERIA_UPDATE,
      PLAYER_INTERACTION_MANAGER, PLAYER_TARGET_CHANGED, QUEST_LOG_UPDATE
]]

local ADDON_NAME, ns = ...

-- IIFE: Lua 5.1 / WoW cap ~200 locals per function; main chunk exceeded limit.
;(function()
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local E = ns.Constants.EVENTS
-- Packed internal funcs: Lua 5.1 / WoW ~200 locals per function scope.
local Fns = {}

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
local ENCOUNTER_OBJECT_TTL = 300  -- seconds: max time between boss kill and chest loot for encounter+GameObject match
--- Sanctum of Domination (raid): GetInstanceInfo()[8] template id; mythic Sylvanas chest may use a new GameObject id.
local SANCTUM_RAID_TEMPLATE_INSTANCE_ID = 1193
local RAID_MYTHIC_DIFFICULTY_ID = 16
local SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID = 368304

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
local lastLootSourceGUID
local lastLootSourceTime
local discoveryPendingNpcID

---Send try counter / drops lines via ns.ChatOutput.SendTryCounterMessage (Loot, WN_TRYCOUNTER, or all tabs — profile).
---Honors hideTryCounterChat: when true, all chat output is suppressed while counting continues.
---Falls back to WarbandNexus:Print if ChatMessageService not available.
---@param message string
function Fns.TryChat(message)
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
        and WarbandNexus.db.profile.notifications
        and WarbandNexus.db.profile.notifications.hideTryCounterChat then
        return
    end
    if ns.ChatOutput and ns.ChatOutput.SendTryCounterMessage then
        ns.ChatOutput.SendTryCounterMessage(message)
    elseif ns.SendToChatFramesLootRepCurrency then
        ns.SendToChatFramesLootRepCurrency(message)
    elseif WarbandNexus and WarbandNexus.Print then
        WarbandNexus:Print(message)
    end
end

---Build try-counter chat line: "N attempts for [item]" (or first-attempt variant), optional context tags.
---@param baseKey string Locale key for no-count fallback (e.g. TRYCOUNTER_OBTAINED)
---@param baseFallback string English fallback when preResetCount is nil
---@param itemLink string Formatted item link
---@param preResetCount number|nil Failed attempts before the successful one (total = preResetCount + 1)
---@return string
function Fns.BuildObtainedChat(baseKey, baseFallback, itemLink, preResetCount)
    local L = ns.L
    local prefix = "|cff9370DB[WN-Counter]|r "
    if preResetCount == nil then
        return prefix .. format((L and L[baseKey]) or baseFallback, itemLink)
    end
    local totalTries = preResetCount + 1
    local tags = {}
    if baseKey and strfind(baseKey, "CONTAINER", 1, true) then
        tags[#tags + 1] = (L and L["TRYCOUNTER_CHAT_TAG_CONTAINER"]) or "container"
    end
    if baseKey and strfind(baseKey, "CAUGHT", 1, true) then
        tags[#tags + 1] = (L and L["TRYCOUNTER_CHAT_TAG_FISHING"]) or "fishing"
    end
    if baseKey and strfind(baseKey, "RESET", 1, true) then
        tags[#tags + 1] = (L and L["TRYCOUNTER_CHAT_TAG_RESET"]) or "counter reset"
    end
    local tagStr = (#tags > 0) and (" |cff888888(" .. tconcat(tags, " · ") .. ")|r") or ""
    -- Success lines must not reuse TRYCOUNTER_INCREMENT_CHAT wording ("N attempts for …"), which reads like a miss.
    if totalTries <= 1 then
        local fmt = (L and L["TRYCOUNTER_CHAT_OBTAINED_FIRST_LINK"])
            or (L and L["TRYCOUNTER_CHAT_FIRST_FOR_LINK"])
            or "You got %s on your first try!"
        return prefix .. "|cffffffff" .. format(fmt, itemLink) .. "|r" .. tagStr
    end
    local fmt = (L and L["TRYCOUNTER_CHAT_OBTAINED_AFTER_LINK"])
        or "You got %s after %d attempts!"
    return prefix .. "|cffffffff" .. format(fmt, itemLink, totalTries) .. "|r" .. tagStr
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
    CHAT_MSG_CURRENCY = true,
    CHAT_MSG_MONEY = true,
    ITEM_LOCK_CHANGED = true,
    UNIT_SPELLCAST_SENT = true,
    UNIT_SPELLCAST_CHANNEL_START = true,
    UNIT_SPELLCAST_INTERRUPTED = true,
    ENCOUNTER_START = true,
    ENCOUNTER_END = true,
    BOSS_KILL = true,
}

-- MUST be declared before tryCounterFrame:SetScript("OnEvent") — otherwise the closure resolves globals (nil).
local DEBUG_TRACE_DEDUP_LOOT_MS = 0.22
local lastDebugTraceLootTime = { LOOT_READY = 0 }

local TRYCOUNTER_EVENTS = {
    "LOOT_READY",
    "LOOT_OPENED",
    "LOOT_CLOSED",
    "CHAT_MSG_LOOT",
    "CHAT_MSG_CURRENCY",
    "CHAT_MSG_MONEY",
    -- Encounter lifecycle:
    --   ENCOUNTER_START fires at pull (values typically non-secret; best window to capture IDs).
    --   ENCOUNTER_END fires on kill/wipe (12.0: encounterID/Name/difficultyID may be secret).
    --   BOSS_KILL complements ENCOUNTER_END for world bosses and some legacy content.
    "ENCOUNTER_START",
    "ENCOUNTER_END",
    "BOSS_KILL",
    "PLAYER_ENTERING_WORLD",
    "UNIT_SPELLCAST_SENT",
    "UNIT_SPELLCAST_CHANNEL_START",
    "UNIT_SPELLCAST_INTERRUPTED",
    "UNIT_SPELLCAST_FAILED_QUIET",
    "ITEM_LOCK_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW",
    "PLAYER_INTERACTION_MANAGER_FRAME_HIDE",
    "PLAYER_TARGET_CHANGED",
    "QUEST_LOG_UPDATE",
    "PLAYER_REGEN_ENABLED",
    "CRITERIA_UPDATE",
    -- Definitive drop-acquired signals (Rarity/ATT priority #1). NEW_MOUNT_ADDED fires once per
    -- mount learn including post-cinematic chest grants where no creature LOOT_OPENED ever ties
    -- to the kill. Consuming the drop's mark here makes "obtained after N attempts" reliable for
    -- Sylvanas SoD chest, LK Frozen Throne, etc., even if all other paths missed.
    "NEW_MOUNT_ADDED",
    "NEW_PET_ADDED",
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
        elseif WarbandNexus and WarbandNexus.Debug then
            WarbandNexus:Debug("[TryCounter] RegisterEvent failed for %s: %s", tostring(ev), tostring(err))
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
    if addon and addon.db and addon.db.profile and addon.db.profile.debugTryCounterLoot and DEBUG_TRACE_EVENTS[event] then
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
        if addon and (event == "UNIT_SPELLCAST_SENT" or event == "UNIT_SPELLCAST_CHANNEL_START") then
            if event == "UNIT_SPELLCAST_SENT" then
                addon:OnTryCounterSpellcastSent(event, ...)
            else
                addon:OnTryCounterSpellcastChannelStart(event, ...)
            end
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
                lastLootSourceGUID = guid
                lastLootSourceTime = GetTime()
            end
        else
            lastLootSourceGUID = nil
        end
    elseif event == "QUEST_LOG_UPDATE" then
        if discoveryPendingNpcID then
            Fns.TryDiscoverLockoutQuest()
        end
    elseif event == "CRITERIA_UPDATE" then
        Fns.RequestTryCounterStatisticsRuntimeRefresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        Fns.RequestTryCounterStatisticsRuntimeRefresh()
    end
end)

-- Fishing cast spell IDs (fired on UNIT_SPELLCAST_SENT / UNIT_SPELLCAST_CHANNEL_START).
-- NOTE: Spell 471021 / 471008 are PASSIVE profession-rank unlocks for Midnight Fishing —
-- they never fire UNIT_SPELLCAST_* events and were removed accordingly (see warcraft.wiki.gg).
-- The actual Midnight cast uses 1239033 / 1257770 / 1239227 / 1281823 / 1281824 variants.
local FISHING_SPELLS = {
    -- Classic / Cataclysm / MoP
    [7620]    = true,  -- Fishing (classic legacy)
    [131474]  = true,  -- Fishing (Cataclysm/MoP base channel)
    [110412]  = true,  -- Fishing (Zen Master, Pandaria)
    -- Battle for Azeroth
    [271616]  = true,  -- Fishing (BfA base cast)
    [271990]  = true,  -- Fishing (BfA Kul Tiran rank)
    [271991]  = true,  -- Fishing (BfA Zandalari rank)
    -- Dragonflight
    [384481]  = true,  -- Fishing (Dragonflight)
    [389234]  = true,  -- Fishing (Dragonflight alt)
    -- The War Within
    [463743]  = true,  -- Fishing (TWW Astral Void)
    -- Midnight 12.0+ (all observed cast variants)
    [1239033] = true,  -- Fishing (Midnight base)
    [1239227] = true,  -- Fishing for Salmon (Midnight)
    [1257770] = true,  -- Midnight Fishing (3.2s channel)
    [1281823] = true,  -- Fishing (Midnight variant)
    [1281824] = true,  -- Fishing (Midnight instant cast)
}

-- Creature NPC ids for the fishing bobber (GUID type is Creature — not a lootable corpse).
-- Without this, LootSessionHasAnyMobCorpseSources blocks the fishing route and auto-loot
-- (LOOT_OPENED skipped) misroutes to ProcessNPCLoot → P2 no match.
local FISHING_BOBBER_NPC_IDS = {
    [124736] = true, -- default Fishing Bobber
    [35591] = true,  -- alternate bobber (some clients/expansions)
    [216204] = true, -- Fishing Bobber (retail alternate template, DF+)
}

function Fns.IsFishingBobberNpcId(npcID)
    return npcID and FISHING_BOBBER_NPC_IDS[npcID] == true
end

---Loot API sources are only fishing bobbers (Creature) and/or pools (GameObject) — no real mob corpse GUIDs.
---Used when spell-cast context was cleared but auto-loot still skipped LOOT_OPENED (fish=false in debug).
---@param sourceGUIDs table|nil
---@return boolean
---True when every loot source GUID is a GameObject (herb/ore/chest/pool). Empty = false.
---@param sourceGUIDs table|nil
---@return boolean
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
--- CollectibleSourceDB.instanceBossSlotOutcomeRules — slot-first boss outcome (see DB header).
local instanceBossSlotOutcomeRules = {}
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
--- ENCOUNTER_START snapshot: capture encounterID/Name/difficultyID at pull so ENCOUNTER_END and loot paths
--- have a non-secret fallback when Midnight 12.0 encounter restrictions mask those fields in the END payload.
--- Cleared on ENCOUNTER_END (matching encID), PLAYER_ENTERING_WORLD (instance swap), or 20-minute TTL.
local currentEncounterCache = {
    encounterID = nil,          -- number|nil (non-secret, captured at start)
    encounterName = nil,        -- string|nil (non-secret)
    difficultyID = nil,         -- number|nil (non-secret, preferred over END's secret value)
    groupSize = nil,            -- number|nil
    startTime = 0,              -- GetTime() at ENCOUNTER_START
    instanceID = nil,           -- GetInstanceInfo()[8] snapshot for scope checks
}
--- How long an ENCOUNTER_START cache entry stays authoritative without a matching ENCOUNTER_END.
local ENCOUNTER_CACHE_TTL = 1200  -- 20 minutes (covers long wipes, phase-heavy fights, AFK loot)
--- One hint per instance+difficulty per login (replaces old multi-line chat dump).
local tryCounterInstanceEntryAnnounced = {}
--- GetInstanceInfo()[8] template InstanceID → JournalInstance.ID (EJ_GetInstanceInfo 10th return); false = scanned, no match.
--- Pre-seed hot rows to skip EJ scan on zone-in (InstanceID is global, not locale-specific).
local tryCounterJournalIDByTemplateInstID = {
    [2097] = 1178, -- Operation: Mechagon (JournalInstance.ID)
}
--- Upper bound for JournalInstance.ID scan (covers retail dungeons/raids; adjust if Blizzard adds higher IDs).
local JOURNAL_INSTANCE_TEMPLATE_SCAN_MAX = 2600
--- Last character key we scheduled Statistics+Rarity sync for (avoids duplicate timers on same char).
local lastSyncScheduleCharKey = nil
--- Bumped when a new per-character sync is scheduled; stale C_Timer callbacks no-op.
local perCharStatSyncSerial = 0
--- Debounced + rate-limited Statistics re-seed when GetStatistic updates mid-session (no relog).
--- Independent of perCharStatSyncSerial so login/alt sync timers are not cancelled.
local statRuntimeDebounceSerial = 0
local lastStatRuntimeFullSeedAt = 0
local STAT_RUNTIME_DEBOUNCE_SEC = 5
local STAT_RUNTIME_MIN_INTERVAL_SEC = 15
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

-- CHAT_MSG_LOOT fallback: itemID → npcID when loot window doesn't fire (direct loot, world boss, etc.).
-- Built from npcDropDB in BuildReverseIndices; hardcoded entries merged so they take precedence.
local chatLootItemToNpc = {}
local lastTryCountSourceKey = nil
local lastTryCountSourceTime = 0
--- Primary loot source GUID from the last try-counter NPC/object route (CLOSED-path debounce vs next corpse).
local lastTryCountLootSourceGUID = nil
local lastEncounterEndTime = 0  -- set on ANY successful ENCOUNTER_END (even unmatched); suppresses zone fallback
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
function Fns.TryCounterLootDebug(addon, cat, fmt, ...)
    if not Fns.IsTryCounterLootDebugEnabled(addon) then return end
    local color = LOG_COLORS[cat] or "|cffcccccc"
    local n = select("#", ...)
    local msg = (n > 0) and string.format(tostring(fmt), ...) or tostring(fmt)
    addon:Print("|cff9370DB[WN-TC]|r " .. color .. msg .. "|r")
end

---Print structured debug lines for each drop being incremented (one line per drop).
---@param addon table WarbandNexus
---@param source string "NPC"|"Encounter"|"Fishing"|"Chat"|"Container" etc.
---@param drops table Array of drop entries being incremented
---@param mult number|nil farmCorpseMult (default 1)
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

---@param link string|nil
---@return number|nil
function Fns.LootDebugParseItemIDFromLink(link)
    if not link or type(link) ~= "string" then return nil end
    if issecretvalue and issecretvalue(link) then return nil end
    local id = link:match("item:(%d+)")
    return id and tonumber(id) or nil
end

---Human-readable loot origin from GetLootSourceInfo GUID list (not Blizzard "source type" integers).
---@param sourceGUIDs table|nil
---@param wasFishing boolean|nil
---@return string
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

---@param guid string|nil
---@return string
function Fns.FormatLootUnitToken(guid)
    if not guid or type(guid) ~= "string" then return "-" end
    local nid = Fns.GetNPCIDFromGUID(guid)
    if nid then return "npc:" .. tostring(nid) end
    local oid = Fns.GetObjectIDFromGUID(guid)
    if oid then return "obj:" .. tostring(oid) end
    local pfx = guid:match("^(%a+)")
    return pfx or "?"
end

---Summarize loot slots for debug: try-counter drop DB hit, repeatable flag, typed id + name per slot.
---@param slotData table|nil
---@param numLoot number|nil
---@param addon table WarbandNexus
---@return boolean hasTryCollectible
---@return boolean repeatableAny
---@return string whatIs
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

---Map every NPC in encounterDB to its encounter's full npcIDs list, then for each CollectibleSourceDB.npcNameIndex
---entry, if any listed NPC appears in an encounter, copy that encounter's npc list to encounterNameToNpcs[name].
---ENCOUNTER_END may pass localized boss names when encounterID is secret; npcNameIndex already carries many locales
---for tooltip fallback — without this merge, only explicit encounter_name rows were consulted (a handful).
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
        wipe(instanceBossSlotOutcomeRules)
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
end

--- Which NPC IDs may drive try-counter increments from corpse GUIDs, unit fallbacks, and CHAT_MSG_LOOT.
--- Merges: world rares, encounter bosses, CollectibleSourceDB.npcNameIndex (minus shared-trash denylist),
--- statistic/difficulty-gated entries, and trackDB custom NPCs.
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

---Index all drops from a flat array
---@param drops table|nil Array of drop entries (may also have .dropDifficulty / .statisticIds at the NPC level)
function Fns.IndexDropArray(drops)
    if not drops then return end
    local npcDifficulty = drops.dropDifficulty  -- NPC-level difficulty (e.g. "Mythic")
    local hasStatistics = drops.statisticIds and #drops.statisticIds > 0
    for i = 1, #drops do
        Fns.IndexDrop(drops[i], npcDifficulty, hasStatistics)
    end
end

---Build all reverse lookup indices from the loaded CollectibleSourceDB.
---Called once from InitializeTryCounter. After this, Is*Collectible()
---uses O(1) hash lookups instead of full-DB scans.
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

---Deferred journal-key mirror pass (mount journalID / pet speciesID).
---Keeps startup responsive; base itemID indices are already ready synchronously.
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

-- Helper: keep sourceItemToAllMountKeys in sync when questStarterMountToSourceItemID is updated at runtime.
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

-- =====================================================================
-- DATABASE HELPERS
-- =====================================================================

---Ensure SavedVariable structure exists
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

---Mark a non-repeatable drop item as obtained so IsCollectibleCollected stops
---tracking it even when the WoW collection API can't confirm yet (e.g. egg
---hatch timers, unresolvable mountIDs).
---@param itemID number
function Fns.MarkItemObtained(itemID)
    if not itemID or not Fns.EnsureDB() then return end
    WarbandNexus.db.global.tryCounts.obtained[itemID] = true
end

---Check if a drop item was previously marked as obtained.
---@param itemID number
---@return boolean
function Fns.IsItemMarkedObtained(itemID)
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
    return type(count) == "number" and count or 0
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
---@param collectibleType string "mount"|"pet"|"toy"|"illusion"
---@param id number
function WarbandNexus:ResetTryCount(collectibleType, id)
    if not VALID_TYPES[collectibleType] or not id then return end
    if not Fns.EnsureDB() then return end
    WarbandNexus.db.global.tryCounts[collectibleType][id] = 0
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

-- =====================================================================
-- GUID PARSING (minimal allocation)
-- =====================================================================

---Extract NPC ID from a creature/vehicle GUID (retail GUIDs have variable segment counts;
---the old %-.-%-.-…%-(%d+) pattern often grabbed map/instance ids instead of the entry id).
---@param guid string
---@return number|nil npcID
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

---Extract object ID from a GameObject GUID (same segment rules as Creature).
---@param guid string
---@return number|nil objectID
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

-- =====================================================================
-- COLLECTIBLE ID RESOLUTION (runtime mount/pet ID lookup)
-- =====================================================================

---Resolve collectibleID from itemID at runtime
---Returns the native collectible ID (mountID/speciesID) if the API can resolve it.
---Does NOT cache nil results so the API can be retried on subsequent loot events
---(Blizzard_Collections may not be loaded on first call).
---@param drop table { type, itemID, name }
---@return number|nil collectibleID
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

---Get the try count key for a drop entry.
---Uses native collectibleID if available, falls back to itemID.
---This ensures try counts ALWAYS increment even if the API can't resolve the ID.
---@param drop table { type, itemID, name }
---@return number tryCountKey The ID to use for try count storage
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

---Get the (type, key) to use for try count storage/display for a drop.
---When drop has tryCountReflectsTo (e.g. Nether-Warped Egg -> Nether-Warped Drake), returns the
---reflected type and key so the count is stored on the mount and shown in mount UI.
---@param drop table { type, itemID, name [, tryCountReflectsTo = { type, itemID [, name ] } ] }
---@return string|nil collectibleType "mount"|"pet"|"toy"|"item"
---@return number|nil tryCountKey
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

---Map ENCOUNTER_END / GetInstanceInfo difficulty IDs to drop-gate labels.
---Uses static table first; then GetDifficultyInfo so legacy LFR / TW / new IDs still match (e.g. BoD Jaina LFR + G.M.O.D.).
---@param difficultyID number|nil
---@return string|nil label for DoesDifficultyMatch ("LFR", "Mythic", ...)
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

---Resolve difficultyID when GetInstanceInfo() returns 0 (seen in Midnight / some dungeons).
---M+ → 8; else GetDungeonDifficultyID / GetRaidDifficultyID.
---@param instanceType string|nil "party"|"raid"|...
---@param giDifficulty number|nil GetInstanceInfo() 3rd return
---@return number|nil
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

---Match a difficulty label against a single requirement string using threshold semantics.
---Private helper for DoesDifficultyMatch — NOT called directly from loot paths.
---@param label string resolved label from ResolveDifficultyLabel
---@param requiredDifficulty string
---@return boolean
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

---Check if a difficultyID satisfies a dropDifficulty requirement.
---Midnight 12.0: guards against secret values to avoid ADDON_ACTION_FORBIDDEN.
---
---Supports THREE requirement formats:
---  1. string: "Mythic" / "Heroic" / "25H" / "Normal" / "LFR" / "25-man" / "All Difficulties"
---     Threshold semantics — "Heroic" matches Heroic + Mythic + 25H.
---  2. table (array of strings): { "Heroic", "Mythic" } — explicit whitelist (ANY match = true).
---     Used when a mount drops from a discrete set of difficulties that don't form a threshold
---     (e.g. a legacy raid mount that drops on Normal OR Mythic but not Heroic).
---  3. nil / "All Difficulties": always matches.
---
---@param difficultyID number WoW difficultyID from ENCOUNTER_END or difficulty API
---@param requiredDifficulty string|table|nil "Mythic"|{"Heroic","Mythic"}|nil
---@return boolean true if the difficulty qualifies for the drop
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

---Effective difficulty for loot gating while inside an instance.
---Order: (1) cache from instance entry + matching instanceID, (2) live GetInstanceInfo,
---(3) ENCOUNTER_END snapshot, (4) GetDungeon/GetRaidDifficultyID.
---@param inInstance boolean|nil
---@param recentKillDiff number|nil difficulty from recentKills (ENCOUNTER_END snapshot)
---@return number|nil
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

---Mythic-gated boss rows need a numeric difficultyID. ENCOUNTER_END may omit difficultyID (Midnight
---secret), and object-chest paths may not attach a kill GUID — ResolveEffectiveEncounterDifficultyID
---can return nil while GetInstanceInfo still reports the raid difficulty. Use live instance diff last.
---@param inInstance boolean|nil
---@param recentKillDiff number|nil
---@param liveDifficultyID number|nil Optional GetInstanceInfo() 3rd return from caller (avoids extra call).
---@return number|nil
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

---Trackable drops for NPC/encounter tables after difficulty gating (same rules as ProcessNPCLoot).
---@param drops table npcDropDB entry
---@param encounterDiffID number|nil
---@return table
---@return table|nil first skipped drop info { drop, required } for user messaging
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

---Localized plain text for dropDifficulty gate (Try Counter debug probe only).
---@param reqDiff string|nil
---@return string
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

---Single mount line for TryCounterDebugInstanceProbe: boss > mount > drop difficulties > status.
---@param WN table
---@param encName string
---@param ann table announce drop (mount item)
---@param drop table original npc row
---@param npcDropDifficulty string|nil
---@param effDiff number|nil
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

-- =====================================================================
-- COLLECTED CHECK (skip already-owned collectibles)
-- =====================================================================

---True if the summoning spell for this mount item is known (mount already learned).
---Midnight 12.0+: GetMountFromItem / GetMountInfoByID may return secret values in instances;
---spell + IsSpellKnown still reflects account-wide collection for most mounts.
---@param itemID number
---@return boolean
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

---Companion pets: same teach-spell pattern as mounts when journal returns secret/nil.
---@param itemID number
---@return boolean
function Fns.IsPetLearnedByItemSpell(itemID)
    return Fns.IsMountLearnedByItemSpell(itemID)
end

---Check if a collectible is already collected
---Uses native collectibleID for accurate checks, with itemID-based fallbacks
---@param drop table { type, itemID, name }
---@return boolean
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

-- =====================================================================
-- LOOT WINDOW SCANNING
-- =====================================================================

---Scan loot window and return set of found itemIDs.
---When cachedNumLoot and cachedSlotData are provided (from LOOT_OPENED capture), uses them so we don't re-read the window.
---@param expectedDrops table Array of drop entries
---@param cachedNumLoot number|nil Optional: use this instead of GetNumLootItems()
---@param cachedSlotData table|nil Optional: [i] = { hasItem = bool, link = string|nil }
---@return table foundItemIDs Set of itemIDs found in loot { [itemID] = true }
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
        else
            hasItem = LootSlotHasItem and LootSlotHasItem(i)
            link = GetLootSlotLink and GetLootSlotLink(i)
            if link and issecretvalue and issecretvalue(link) then link = nil end
        end
        if hasItem and link and type(link) == "string" then
            -- GetItemInfoInstant's first return is item name, not ID — parse the hyperlink.
            local lootItemID = tonumber(link:match("|Hitem:(%d+):"))
            if lootItemID and expectedSet[lootItemID] then
                found[lootItemID] = true
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

---Item/mount-style hyperlink for try-counter obtain chat (CollectionService path has no drop row).
---@param data table WN_COLLECTIBLE_OBTAINED payload: type, id, name
---@return string
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

---Mirror NotificationManager obtain toast: print try line to chat when learn event did not come from TryCounter loot (no fromTryCounter).
---@param addon table WarbandNexus
---@param data table
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

---True if NPC drop entry has statisticIds at NPC level or on any drop row (per-difficulty stats).
---@param npcData table
---@return boolean
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

---@param drop table
---@param npcStatIds table|nil
---@return table|nil
function Fns.ResolveReseedStatIdsForDrop(drop, npcStatIds)
    if drop and drop.statisticIds and #drop.statisticIds > 0 then
        return drop.statisticIds
    end
    return npcStatIds
end

---Mark a drop's tryKey as "stat-backed reseed counted this kill". Used ONLY by stat-backed
---ReseedStatisticsForDrops when GetStatistic(killStatID) reflects the just-made kill. Manual
---+1 increments (open-world rares) intentionally do NOT mark — see dropDelayedReseeded comment.
---@param tcType string
---@param tryKey string|number
function Fns.MarkDropReseeded(tcType, tryKey)
    if not tcType or not tryKey then return end
    dropDelayedReseeded[tcType .. "\0" .. tostring(tryKey)] = true
end

---True if this drop's count was raised by a stat-backed reseed that included the latest kill.
---Reserved for callers that need to know whether the locally stored count is "post-kill" rather
---than "pre-kill". Currently unused outside of this module's adjustment helper.
---@param tcType string
---@param tryKey string|number
---@return boolean
function Fns.IsDropAlreadyCounted(tcType, tryKey)
    if not tcType or not tryKey then return false end
    return dropDelayedReseeded[tcType .. "\0" .. tostring(tryKey)] == true
end

---When a drop is found in loot, subtract 1 from preResetCount if a recent miss-path counter
---increment (manual +1 for non-stat drops, or stat-driven reseed for stat-backed bosses) has
---already counted the kill that just produced this drop. Consumes the marker on use.
---@param preResetCount number|nil
---@param tcType string|nil
---@param tryKey string|number|nil
---@return number|nil
function Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, tryKey)
    if not preResetCount or preResetCount <= 0 then return preResetCount end
    if not tcType or not tryKey then return preResetCount end
    local mk = tcType .. "\0" .. tostring(tryKey)
    if not dropDelayedReseeded[mk] then return preResetCount end
    dropDelayedReseeded[mk] = nil
    return preResetCount - 1
end

---Sum GetStatistic values for a list of statistic IDs (LFR+N+H+M columns, deduped upstream).
---@param statIds table|nil
---@return number
function Fns.SumStatisticTotalsFromIds(statIds)
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
function Fns.RebuildMergedStatisticSeedIndex()
    wipe(mergedStatSeedByTypeKey)
    wipe(mergedStatSeedGroupList)
    wipe(statSeedTryKeyPending)
    if not npcDropDB then return end
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
end

---Prefer merged cross-difficulty / cross-NPC stat ID set; else per-drop + npc fallback (ProcessMissedDrops).
---@param drop table
---@param resolvedDropStatIds table|nil
---@return table|nil statIds
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

--- Remove statisticSnapshots rows with no matching db.global.characters entry (deleted alts).
--- Prevents inflated global totals when summing snapshots across characters.
function Fns.PruneStatisticSnapshotsOrphanKeys()
    if not Fns.EnsureDB() then return end
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
function Fns.ReseedStatisticsForDrops(drops, resolvedDropStatIds)
    if not drops or #drops == 0 then return end
    if not Fns.EnsureDB() then return end
    if not GetStatistic then return end

    Fns.RebuildMergedStatisticSeedIndex()

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
            local skipStatSeed = (drop.type == "mount" or drop.type == "pet" or drop.type == "toy")
                and Fns.IsCollectibleCollected(drop)
            if not skipStatSeed then
                local statList = statListOverride or Fns.ResolveMergedStatisticIdsForDrop(drop, resolvedDropStatIds)
                if statList and #statList > 0 then
                    local thisCharTotal = Fns.SumStatisticTotalsFromIds(statList)
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
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
end

---@param drops table
---@param npcStatIds table|nil
---@return boolean
function Fns.DropsHaveStatBackedReseed(drops, npcStatIds)
    for i = 1, #drops do
        local sids = Fns.ResolveReseedStatIdsForDrop(drops[i], npcStatIds)
        if sids and #sids > 0 then return true end
    end
    return false
end

---Increment try count for unfound drops; optional chat when Auto-Track is on.
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
function Fns.ProcessMissedDrops(drops, statIds, options)
    if not drops or #drops == 0 then return end
    if not Fns.EnsureDB() then return end

    -- Drop entries queued before deferred run may now resolve as collected (journal/spell).
    -- Repeatable farm mounts stay eligible even when owned.
    -- NOTE: We intentionally do NOT filter by `IsDropAlreadyCounted` here. The mark is keyed on
    -- (tcType, tryKey), which is shared across many open-world rares that drop the same mount —
    -- filtering here would silently skip every rare farm kill after the first. Same-kill dedup
    -- (ENCOUNTER_END + LOOT_OPENED race for one boss) is handled by the source-key check in
    -- ProcessNPCLoot, which is per-corpse-GUID and naturally distinguishes consecutive kills.
    local filtered = {}
    for i = 1, #drops do
        local d = drops[i]
        if d and (d.repeatable or not Fns.IsCollectibleCollected(d)) then
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
        C_Timer.After(2, function()
            if not Fns.EnsureDB() then return end
            local WN = WarbandNexus
            local incrementAnnounce = {}
            for i = 1, #drops do
                local drop = drops[i]
                local sids = Fns.ResolveReseedStatIdsForDrop(drop, statIds)
                if sids and #sids > 0 then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    local prevCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
                    local statSumBefore = Fns.SumStatisticTotalsFromIds(sids)
                    Fns.ReseedStatisticsForDrops({ drop }, sids)
                    local newCount = (tryKey and WN:GetTryCount(tcType, tryKey)) or 0
                    -- GetStatistic can lag behind a kill; re-seed never exceeds stat-derived totals. When the
                    -- stored counter is already ahead of stats (imports) or both are zero (first pull), a
                    -- real loot miss still needs +1. Skip when stats match the stored count (already synced).
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
                for _, info in pairs(incrementAnnounce) do
                    local link = info.drop and Fns.GetDropItemLink(info.drop)
                    if link and info.finalCount and info.finalCount > 0 then
                        local tmpl = (ns.L and ns.L["TRYCOUNTER_INCREMENT_CHAT"]) or "%d attempts for %s"
                        Fns.TryChat("|cff9370DB[WN-Counter]|r |cffffffff" .. format(tmpl, info.finalCount, link) .. "|r")
                    end
                end
            end
        end)
        return
    end

    C_Timer.After(0, function()
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
            -- Defense: deferred paths may run after learn; never increment for already-owned collectibles.
            -- Include item-type drops (yields / quest chains): IsCollectibleCollected is true when all goals are met.
            -- Repeatable farm sources stay eligible even when owned (BoE / world farm mounts).
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
                    -- NO MarkDropReseeded here. The mark exists strictly for the stat-backed
                    -- found-path "-1" correction (GetStatistic includes this very kill, so the
                    -- displayed total is `count`, not `count + 1`). Manual +1 increments only
                    -- account for PRIOR misses — the dropping kill itself is not pre-counted in
                    -- this branch, so the found-path's natural `preResetCount + 1` is correct.
                    -- Marking here caused the "after N-1 attempts" off-by-one on open-world rare
                    -- farms where 4 prior misses + drop on kill 5 displayed "after 4 attempts".
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
            for _, info in pairs(incrementAnnounce) do
                local link = info.drop and Fns.GetDropItemLink(info.drop)
                if link and info.added and info.added > 0 then
                    local tmpl = (ns.L and ns.L["TRYCOUNTER_INCREMENT_CHAT"]) or "%d attempts for %s"
                    Fns.TryChat("|cff9370DB[WN-Counter]|r |cffffffff" .. format(tmpl, info.finalCount or 0, link) .. "|r")
                end
            end
        end
        if WN.SendMessage then
            WN:SendMessage(E.PLANS_UPDATED, { action = "try_count_set" })
        end
    end)
end

-- =====================================================================
-- SETTING CHECK
-- =====================================================================

---Check if auto try counter is enabled (module toggle AND notification setting must both be on)
---@return boolean
function Fns.IsAutoTryCounterEnabled()
    if not WarbandNexus or not WarbandNexus.db then return false end
    if not WarbandNexus.db.profile then return false end
    if WarbandNexus.db.profile.modulesEnabled and WarbandNexus.db.profile.modulesEnabled.tryCounter == false then return false end
    if not WarbandNexus.db.profile.notifications then return false end
    return WarbandNexus.db.profile.notifications.autoTryCounter == true
end

---Whether try counter chat output is suppressed (processing continues, chat lines hidden).
---@return boolean
function Fns.IsTryCounterChatHidden()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile
        or not WarbandNexus.db.profile.notifications then
        return false
    end
    return WarbandNexus.db.profile.notifications.hideTryCounterChat == true
end

---Instance entry: full [WN-Drops] lines (difficulty green/red/amber) vs single TRYCOUNTER_INSTANCE_ENTRY_HINT.
---@return boolean
function Fns.IsTryCounterInstanceEntryDropLinesEnabled()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile or not WarbandNexus.db.profile.notifications then
        return true
    end
    local v = WarbandNexus.db.profile.notifications.tryCounterInstanceEntryDropLines
    if v == false then return false end
    return true
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

---Sync lockout state with server quest flags on login/reload.
---Two-phase operation:
---  1. Clean stale entries: remove lockoutAttempted quest IDs that are no longer flagged
---  2. Pre-populate: mark quest IDs that are already flagged (from prior session)
---This prevents false try count increments after /reload mid-farm-session.
---Without phase 2, a /reload would reset lockoutAttempted to empty, causing the next
---kill of an already-locked rare to be incorrectly counted as a "first attempt".
function Fns.SyncLockoutState()
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

-- =====================================================================
-- EVENT HANDLERS
-- =====================================================================

---ENCOUNTER_START handler (warcraft.wiki.gg/wiki/ENCOUNTER_START).
---Fires at pull (before heavy secret-value enforcement in many contexts) with payload:
---  encounterID (number), encounterName (string), difficultyID (number), groupSize (number)
---We cache this snapshot so ENCOUNTER_END and loot-processing paths have a non-secret fallback
---when Midnight 12.0 encounter-restriction secrets arrive in later events.
---@param event string
---@param encounterID number|userdata
---@param encounterName string|userdata
---@param difficultyID number|userdata
---@param groupSize number|userdata
function WarbandNexus:OnTryCounterEncounterStart(event, encounterID, encounterName, difficultyID, groupSize)
    if not Fns.IsAutoTryCounterEnabled() then return end

    -- Filter secrets: partial capture is still useful (e.g. have difficultyID + name but not ID).
    local safeEncID = (type(encounterID) == "number" and not (issecretvalue and issecretvalue(encounterID))) and encounterID or nil
    local safeName  = (type(encounterName) == "string" and encounterName ~= ""
        and not (issecretvalue and issecretvalue(encounterName))) and encounterName or nil
    local safeDiff  = (type(difficultyID) == "number" and not (issecretvalue and issecretvalue(difficultyID))) and difficultyID or nil
    local safeSize  = (type(groupSize) == "number" and not (issecretvalue and issecretvalue(groupSize))) and groupSize or nil

    -- Snapshot instanceID for scope (ENCOUNTER_END may leak across instances if we ignore scope).
    local _, _, _, _, _, _, _, iid = GetInstanceInfo()
    if iid and issecretvalue and issecretvalue(iid) then iid = nil end

    currentEncounterCache.encounterID   = safeEncID
    currentEncounterCache.encounterName = safeName
    currentEncounterCache.difficultyID  = safeDiff
    currentEncounterCache.groupSize     = safeSize
    currentEncounterCache.startTime     = GetTime()
    currentEncounterCache.instanceID    = iid

    -- Feed tooltip service so it can surface encounter context (mirrors ENCOUNTER_END path).
    if self.Tooltip and self.Tooltip._feedEncounterKill and safeName then
        -- Only npcIDs list is useful here; ENCOUNTER_END will feed the actual kill entry later.
        local npcIDs = (safeEncID and encounterDB[safeEncID]) or (safeName and encounterNameToNpcs[safeName]) or nil
        self.Tooltip._feedEncounterKill(safeName, safeEncID, npcIDs)
    end
end

---BOSS_KILL handler (warcraft.wiki.gg/wiki/BOSS_KILL).
---Complements ENCOUNTER_END for world bosses and a handful of legacy raid encounters
---where ENCOUNTER_END may be unreliable. Payload: encounterID, encounterName.
---Routes through the same encounter bookkeeping as ENCOUNTER_END but without difficulty/success
---fields (world bosses use Normal difficulty per DIFFICULTY_ID_TO_LABELS[172]).
---@param event string
---@param encounterID number|userdata
---@param encounterName string|userdata
function WarbandNexus:OnTryCounterBossKill(event, encounterID, encounterName)
    if not Fns.IsAutoTryCounterEnabled() then return end

    local safeEncID = (type(encounterID) == "number" and not (issecretvalue and issecretvalue(encounterID))) and encounterID or nil
    local safeName  = (type(encounterName) == "string" and encounterName ~= ""
        and not (issecretvalue and issecretvalue(encounterName))) and encounterName or nil

    if not safeEncID and not safeName then return end

    -- World bosses: difficultyID 172 ("World Boss" → Normal). Delegate to ENCOUNTER_END handler
    -- so the full recentKills + delayed-fallback pipeline runs uniformly. success=1 (BOSS_KILL
    -- only fires on kills, never wipes).
    local diffFromCache = currentEncounterCache.difficultyID
    local diffToUse = (type(diffFromCache) == "number" and diffFromCache > 0) and diffFromCache or 172
    local groupSize = currentEncounterCache.groupSize or 0

    self:OnTryCounterEncounterEnd(event, safeEncID, safeName, diffToUse, groupSize, 1)
end

---ENCOUNTER_END handler for instanced bosses
---NOTE: Midnight 12.0 can return secret values in ENCOUNTER_END args in some contexts.
---This handler defensively guards encounterID/encounterName/difficultyID before comparisons or keying.
---This handler is the primary instanced kill detection path when loot GUIDs are unreliable.
---@param event string
---@param encounterID number
---@param encounterName string
---@param difficultyID number
---@param groupSize number
---@param success number 1 = killed, 0 = wipe
function WarbandNexus:OnTryCounterEncounterEnd(event, encounterID, encounterName, difficultyID, groupSize, success)
    if not Fns.IsAutoTryCounterEnabled() then return end

    -- On WIPE (success != 1) we still clear the ENCOUNTER_START cache so the next pull starts fresh.
    -- Kept in-line (not deferred) because there's no loot/chat path that needs the cached values.
    if success ~= 1 then
        if currentEncounterCache._graceTimer then currentEncounterCache._graceTimer:Cancel() end
        currentEncounterCache.encounterID = nil
        currentEncounterCache.encounterName = nil
        currentEncounterCache.difficultyID = nil
        currentEncounterCache.groupSize = nil
        currentEncounterCache.startTime = 0
        currentEncounterCache.instanceID = nil
        currentEncounterCache._graceTimer = nil
        return
    end

    -- Record timestamp BEFORE DB lookup. Suppresses zone-based fallback in ProcessNPCLoot
    -- for encounters not in our DB (e.g. Commander Kroluk in March on Quel'Danas) that would
    -- otherwise falsely match zone rare-mount drops in the same map region.
    lastEncounterEndTime = GetTime()

    -- Midnight 12.0 rescue: promote non-secret ENCOUNTER_START snapshot when END payload is secret.
    -- The cache is authoritative when startTime is fresh (< TTL) and the cached IDs complement missing
    -- END fields. We never overwrite a non-secret END value with the cached one.
    local cacheFresh = currentEncounterCache.startTime > 0
        and (GetTime() - currentEncounterCache.startTime) <= ENCOUNTER_CACHE_TTL
    if cacheFresh then
        if (not encounterID or (issecretvalue and issecretvalue(encounterID))) and currentEncounterCache.encounterID then
            encounterID = currentEncounterCache.encounterID
        end
        if (not encounterName or type(encounterName) ~= "string" or encounterName == ""
            or (issecretvalue and issecretvalue(encounterName))) and currentEncounterCache.encounterName then
            encounterName = currentEncounterCache.encounterName
        end
        if (not difficultyID or (issecretvalue and issecretvalue(difficultyID))) and currentEncounterCache.difficultyID then
            difficultyID = currentEncounterCache.difficultyID
        end
    end

    ---When END is fully secret and the player is on the chest (not targeting the boss), fall back to
    ---ENCOUNTER_START's non-secret Journal encounter id so recentKills still seeds for P4 retry.
    local function TryNpcIDsFromEncounterStartCache()
        if not cacheFresh then return nil, nil end
        local eid = currentEncounterCache.encounterID
        if type(eid) ~= "number" or (issecretvalue and issecretvalue(eid)) then return nil, nil end
        local _, _, _, _, _, _, _, curTmpl = GetInstanceInfo()
        if curTmpl and issecretvalue and issecretvalue(curTmpl) then curTmpl = nil end
        if currentEncounterCache.instanceID and curTmpl and currentEncounterCache.instanceID ~= curTmpl then
            return nil, nil
        end
        local list = encounterDB[eid]
        if not list then return nil, nil end
        return list, eid
    end

    local npcIDs = nil
    local encounterKey = nil
    local useNameFallback = false
    local function TryResolveEncounterNPCFromLastTarget()
        -- Fallback for encounters not present in encounterDB/encounterNameToNpcs:
        -- if we recently had a valid tracked target GUID, attribute this kill to that NPC.
        -- This is especially important for custom tracked bosses and new patch encounters.
        if not lastLootSourceGUID then return nil end
        if not lastLootSourceTime or (GetTime() - lastLootSourceTime) > 120 then return nil end
        local fallbackNpcID = Fns.GetNPCIDFromGUID(lastLootSourceGUID)
        if not fallbackNpcID then return nil end
        if not tryCounterNpcEligible[fallbackNpcID] then return nil end
        if not npcDropDB[fallbackNpcID] then return nil end
        return fallbackNpcID
    end

    -- Midnight 12.0: encounterID can be secret in dungeons; cannot use as table key or tostring().
    if issecretvalue and encounterID and issecretvalue(encounterID) then
        if encounterName and not (issecretvalue and issecretvalue(encounterName)) and encounterNameToNpcs[encounterName] then
            npcIDs = encounterNameToNpcs[encounterName]
            useNameFallback = true
            -- Normalize: resolve canonical encounter_<ID> key via the first matched NPC.
            local canonicalEncID = Fns.GetEncounterIDForNpcID(npcIDs[1])
            if canonicalEncID then
                encounterKey = "encounter_" .. tostring(canonicalEncID)
            else
                encounterKey = "name_" .. encounterName
            end
        else
            local fallbackNpcID = TryResolveEncounterNPCFromLastTarget()
            if fallbackNpcID then
                npcIDs = { fallbackNpcID }
                useNameFallback = true
                local canonicalEncID = Fns.GetEncounterIDForNpcID(fallbackNpcID)
                if canonicalEncID then
                    encounterKey = "encounter_" .. tostring(canonicalEncID)
                else
                    encounterKey = "fallback_target_" .. tostring(fallbackNpcID)
                end
            else
                local cachedList, cachedEid = TryNpcIDsFromEncounterStartCache()
                if cachedList then
                    npcIDs = cachedList
                    useNameFallback = false
                    encounterKey = "encounter_" .. tostring(cachedEid)
                else
                    return
                end
            end
        end
    else
        npcIDs = encounterDB[encounterID]
        if npcIDs then
            encounterKey = "encounter_" .. tostring(encounterID)
        else
            local cachedList, cachedEid = TryNpcIDsFromEncounterStartCache()
            if cachedList then
                npcIDs = cachedList
                encounterKey = "encounter_" .. tostring(cachedEid)
            end
        end
        if not npcIDs then
            local fallbackNpcID = TryResolveEncounterNPCFromLastTarget()
            if fallbackNpcID then
                npcIDs = { fallbackNpcID }
                useNameFallback = true
                local canonicalEncID = Fns.GetEncounterIDForNpcID(fallbackNpcID)
                if canonicalEncID then
                    encounterKey = "encounter_" .. tostring(canonicalEncID)
                else
                    encounterKey = "fallback_target_" .. tostring(fallbackNpcID)
                end
            else
                return
            end
        end
    end

    -- Check if this encounter was already processed in last 10 seconds (prevent double-counting)
    local now = GetTime()
    if lastTryCountSourceKey == encounterKey and (now - lastTryCountSourceTime) < 10 then return end

    -- Safe display name for storage / synthetic keys (Midnight: never concat or store secret encounterName)
    local safeEncounterDisplayName = nil
    if type(encounterName) == "string" and not (issecretvalue and issecretvalue(encounterName)) and encounterName ~= "" then
        safeEncounterDisplayName = encounterName
    end

    -- Feed localized encounter name to TooltipService for name-based tooltip lookup.
    -- Skip when name is secret/empty — caches are keyed by name; TryCounter passes npcIDs when ID is secret.
    if self.Tooltip and self.Tooltip._feedEncounterKill and safeEncounterDisplayName then
        local safeEncID = (not useNameFallback and encounterID and not (issecretvalue and issecretvalue(encounterID))) and encounterID or nil
        local npcIDsForFeed = (safeEncID == nil and useNameFallback and npcIDs and #npcIDs > 0) and npcIDs or nil
        self.Tooltip._feedEncounterKill(safeEncounterDisplayName, safeEncID, npcIDsForFeed)
    end

    -- Create synthetic kill entries for eligible encounter NPCs only.
    local addedCount = 0
    for i = 1, #npcIDs do
        local npcID = npcIDs[i]
        if tryCounterNpcEligible[npcID] and npcDropDB[npcID] then
            local syntheticGUID
            if useNameFallback then
                if safeEncounterDisplayName then
                    syntheticGUID = "Encounter-Name-" .. safeEncounterDisplayName .. "-" .. npcID .. "-" .. now
                else
                    syntheticGUID = "Encounter-Fallback-" .. npcID .. "-" .. now
                end
            else
                syntheticGUID = "Encounter-" .. tostring(encounterID) .. "-" .. npcID .. "-" .. now
            end
            local safeDiffID = difficultyID
            if issecretvalue and safeDiffID and issecretvalue(safeDiffID) then safeDiffID = nil end
            recentKills[syntheticGUID] = {
                npcID = npcID,
                name = safeEncounterDisplayName or "Boss",
                time = now,
                isEncounter = true,
                difficultyID = safeDiffID,
            }
            addedCount = addedCount + 1
        end
    end
    

    -- DELAYED FALLBACK: If no loot window opens within 5s, manually increment try counters.
    -- Global debounce prevents double-count vs LOOT_OPENED/CHAT_MSG_LOOT paths.
    if addedCount > 0 then
        local keyForDelayed = encounterKey
        -- Counting is event-driven by ENCOUNTER_END(success=1). We schedule on the NEXT frame
        -- (C_Timer.After(0)) instead of waiting 5s — Wowpedia/Rarity confirm GetStatistic is
        -- updated by then, and our drop-key mark + IsDropAlreadyCounted filter is the dedup
        -- mechanism (replaces the old 5s race window vs LOOT_OPENED). If LOOT_OPENED runs first,
        -- it marks the drops and our ProcessMissedDrops here filters them out; if it runs after,
        -- the found-path consumes the mark we just set. Either order is correct.
        C_Timer.After(0, function()
            if not Fns.IsAutoTryCounterEnabled() then return end
            local delayedNow = GetTime()
            -- Dedup ONLY against prior paths that already counted *this same encounter*. A repeatable
            -- item / currency / unrelated-NPC chat path setting lastTryCountSourceKey ("item_X" /
            -- "npc_Y") would previously suppress the entire encounter fallback (e.g. Sylvanas drops
            -- Anima Vessels and tier tokens via CHAT_MSG_LOOT during the kill window — those bumped
            -- lastTryCountSourceTime and silently killed Vengeance counting).
            if keyForDelayed and lastTryCountSourceKey == keyForDelayed
                and (delayedNow - lastTryCountSourceTime) < 10 then
                return
            end

            local matchedNpcID = nil
            local trackable = {}
            local bestGuid, bestKill = nil, nil
            for guid, killData in pairs(recentKills) do
                if killData.isEncounter and (delayedNow - killData.time < 10) and tryCounterNpcEligible[killData.npcID] then
                    local drops = npcDropDB[killData.npcID]
                    if drops and (not bestKill or killData.time > bestKill.time) then
                        bestGuid = guid
                        bestKill = killData
                    end
                end
            end
            if bestKill then
                matchedNpcID = bestKill.npcID
                local inInst = IsInInstance()
                if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
                local encDiff = Fns.ResolveEncounterDifficultyForLootGating(inInst, bestKill.difficultyID, nil)
                trackable = Fns.FilterDropsByDifficulty(npcDropDB[matchedNpcID], encDiff)
            end

            if #trackable > 0 and matchedNpcID then
                lastTryCountSourceKey = keyForDelayed
                lastTryCountSourceTime = delayedNow
                Fns.TryCounterLootDebugDropLines(self, "Encounter", trackable)
                Fns.ProcessMissedDrops(trackable, npcDropDB[matchedNpcID].statisticIds, {
                    statReseedLootMissFallback = true,
                })
            end
        end)
        -- Statistics panel / GetStatistic often lags kill by many seconds; re-seed when APIs catch up.
        Fns.RequestTryCounterStatisticsRuntimeRefresh()
    end
    
    -- DEFERRED RETRY: If a chest was opened BEFORE this encounter ended (RP/cinematic timing),
    -- ProcessNPCLoot found no drops because recentKills was empty. Now that we've added
    -- the encounter entries, retry processing. Short delay ensures loot window state is stable.
    if self._pendingEncounterLoot then
        
        self._pendingEncounterLoot = nil
        self._pendingEncounterLootRetried = true
        C_Timer.After(0.5, function()
            self._pendingEncounterLootRetried = nil
            self:ProcessNPCLoot()
        end)
    end

    -- ENCOUNTER_START cache is consumed by this end event — clear for next pull.
    -- Kept brief grace window (2s) so late CHAT_MSG_LOOT / delayed fallbacks can still read the
    -- non-secret difficulty/name. After that we reset to avoid leaking into subsequent pulls.
    local graceTimer = currentEncounterCache._graceTimer
    if graceTimer then graceTimer:Cancel() end
    currentEncounterCache._graceTimer = C_Timer.NewTimer(300, function()
        currentEncounterCache.encounterID = nil
        currentEncounterCache.encounterName = nil
        currentEncounterCache.difficultyID = nil
        currentEncounterCache.groupSize = nil
        currentEncounterCache.startTime = 0
        currentEncounterCache.instanceID = nil
        currentEncounterCache._graceTimer = nil
    end)
end

-- =====================================================================
-- INSTANCE ENTRY (Encounter Journal helpers kept for debug / TryCounterShowInstanceDrops if invoked manually)
-- Full boss-by-boss chat dump on zone-in was removed (spam). On entry: optional [WN-Drops] lines if the
-- instance has any Try Counter mount in DB (wrong difficulty shows red); else a one-line hint only when
-- at least one drop is trackable on the current difficulty — see TryCounterAnnounceCollectibleMountsOnInstanceEntry.
-- =====================================================================

local function TryCounterAnnounceCollectibleMountsOnInstanceEntry(WN)
    if not WN or not WN.Print or not Fns.IsAutoTryCounterEnabled() then return end
    if Fns.IsTryCounterChatHidden() then return end
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
    -- hasAnyMount: any Try Counter mount row in this instance (TryCounterShowInstanceDrops lists these with red/green).
    -- hasTrackableOnDiff: at least one row that counts on *current* difficulty (uncollected or repeatable) — for the short hint only.
    local hasAnyMount = false
    local hasTrackableOnDiff = false
    while true do
        local encName, dungeonEncID = Fns.TryCounterResolveDungeonEncounterFromEJIndex(idx, jid)
        local isSecret = issecretvalue and encName and issecretvalue(encName)
        if not isSecret and not encName then break end
        if not isSecret and dungeonEncID then
            isSecret = issecretvalue and issecretvalue(dungeonEncID)
        end
        if not isSecret and dungeonEncID then
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

---True if we can select a journal instance and iterate encounters (after Blizzard_EncounterJournal load).
function Fns.TryCounterEJ_HasCoreAPIs()
    return EJ_SelectInstance and EJ_GetEncounterInfoByIndex
        and (EJ_GetCurrentInstance or EJ_GetInstanceForMap)
end

---@param encIndex number 1-based EJ boss index within the instance
---@param journalInstanceID number JournalInstance.ID (pass through to ByIndex for stable rows)
---@return string|nil encName
---@return number|nil dungeonEncounterID keys encounterDB / ENCOUNTER_END
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

--- Instance-entry chat / debug: mount collectibles only (direct mount or item→mount chain).
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

---Resolve JournalInstance.ID when UiMap is not ready (common on instance load: GetBestMapForUnit nil briefly).
---Uses EJ_GetInstanceInfo(jid): 10th return is template InstanceID (matches GetInstanceInfo 8th inside the same dungeon).
---@param templateInstID number
---@return number|nil
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

---JournalInstance.ID for Try Counter EJ walks.
---Blizzard pipeline: EJ_GetInstanceForMap(uiMapID) needs C_Map.GetBestMapForUnit (often nil for a tick after load).
---Fallback: GetInstanceInfo instance template ID ↔ EJ_GetInstanceInfo(...).mapID (field 10).
---Last resort: EJ_GetCurrentInstance (can be stale if the journal was left on another instance).
---@return number|nil
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
        local k = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
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
        local hadDbBoss = false
        while true do
            local encName, dungeonEncID = Fns.TryCounterResolveDungeonEncounterFromEJIndex(idx, jid)
            local isSecret = issecretvalue and encName and issecretvalue(encName)
            if not isSecret and not encName then break end
            if not isSecret and dungeonEncID then
                isSecret = issecretvalue and issecretvalue(dungeonEncID)
            end
            if not isSecret and dungeonEncID then
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

---Print one [WN-Drops] line per collectible: item link — difficulty (green/red/amber) — attempts or (Collected).
---@param journalInstanceID number JournalInstance.ID
---@param opts table|nil { maxLines = number|nil }
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
        while true do
            local encName, dungeonEncID = Fns.TryCounterResolveDungeonEncounterFromEJIndex(idx, journalInstanceID)
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

---UNIT_SPELLCAST_SENT handler (detect fishing casts)
function WarbandNexus:OnTryCounterSpellcastSent(event, unit, target, castGUID, spellID)
    if unit ~= "player" then return end
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
    
    local isFishing = spellID and FISHING_SPELLS[spellID]
    -- Midnight 12.0: dynamically detect unknown fishing spells via icon fallback.
    -- C_Spell.GetSpellInfo can return secret iconID; pcall + issecretvalue guard.
    if not isFishing and spellID and C_Spell and C_Spell.GetSpellInfo then
        local ok, spellInfo = pcall(C_Spell.GetSpellInfo, spellID)
        if ok and spellInfo then
            local iconID = spellInfo.iconID
            if iconID and not (issecretvalue and issecretvalue(iconID)) and iconID == 136245 then
                isFishing = true
                FISHING_SPELLS[spellID] = true
            end
        end
    end

    if isFishing then
        self:TryCounterBeginFishingContext(spellID)
    elseif spellID and PICKPOCKET_SPELLS[spellID] then
        isPickpocketing = true
    elseif spellID and PROFESSION_LOOT_SPELLS[spellID] then
        isProfessionLooting = true
    end
end

---UNIT_SPELLCAST_CHANNEL_START — some fishing variants channel without a separate SENT we map.
---Args: unitTarget, castGUID, spellID
function WarbandNexus:OnTryCounterSpellcastChannelStart(event, unit, castGUID, spellID)
    if unit ~= "player" then return end
    
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
        isFishing = spellID and FISHING_SPELLS[spellID]
    end
    
    -- Midnight 12.0: dynamically detect unknown fishing channel spells via icon fallback.
    if not isFishing and validSpellID and C_Spell and C_Spell.GetSpellInfo then
        local ok, spellInfo = pcall(C_Spell.GetSpellInfo, validSpellID)
        if ok and spellInfo then
            local iconID = spellInfo.iconID
            if iconID and not (issecretvalue and issecretvalue(iconID)) and iconID == 136245 then
                isFishing = true
                FISHING_SPELLS[validSpellID] = true
            end
        end
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

-- =====================================================================
-- SAFE GUID HELPERS (must be defined before event handlers)
-- =====================================================================

---Safely get unit GUID (Midnight 12.0: UnitGUID returns secret values for NPC/object units)
---@param unit string e.g. "target", "mouseover"
---@return string|nil guid Safe GUID string or nil
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

---Mouseover at LOOT_OPENED: when opening an object (e.g. dumpster) by right-click, mouse is often still over it.
Fns.SafeGetMouseoverGUID = function()
    return Fns.SafeGetUnitGUID("mouseover")
end

---Safely get a GUID string, guarding against Midnight 12.0 secret values.
---@param rawGUID any A potentially secret GUID value
---@return string|nil guid Safe GUID string or nil
Fns.SafeGuardGUID = function(rawGUID)
    if not rawGUID then return nil end
    if type(rawGUID) ~= "string" then return nil end
    if issecretvalue and issecretvalue(rawGUID) then return nil end
    return rawGUID
end

---Blizzard IsFishingLoot() with pcall + secret guard (Midnight-safe).
---@return boolean
function Fns.SafeIsFishingLoot()
    if not IsFishingLoot then return false end
    local ok, v = pcall(IsFishingLoot)
    if not ok or v == nil then return false end
    if issecretvalue and issecretvalue(v) then return false end
    return not not v
end

---True if loot source GUIDs indicate fishing (bobber/pool) rather than tracked NPC/object.
---Bobber is Creature (NPC 124736); pools are GameObjects. Only reject when source is in our DB.
function Fns.IsFishingSourceCompatible(sourceGUIDs)
    if not sourceGUIDs or #sourceGUIDs == 0 then return true end
    for i = 1, #sourceGUIDs do
        local srcGUID = sourceGUIDs[i]
        if type(srcGUID) == "string" then
            local typeStr = srcGUID:match("^(%a+)")
            local npcID = Fns.GetNPCIDFromGUID(srcGUID)
            if npcID and npcDropDB[npcID] then return false end
            local objectID = Fns.GetObjectIDFromGUID(srcGUID)
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
        Fns.ResetLootSession()
    end
    lootReady.numLoot = (GetNumLootItems and GetNumLootItems()) or 0
    lootReady.sourceGUIDs = Fns.GetAllLootSourceGUIDs() or {}
    wipe(lootReady.slotData)
    for i = 1, lootReady.numLoot do
        local hasItem = LootSlotHasItem and LootSlotHasItem(i)
        local link = GetLootSlotLink and GetLootSlotLink(i)
        if link and issecretvalue and issecretvalue(link) then link = nil end
        lootReady.slotData[i] = { hasItem = not not hasItem, link = link }
    end
    lootReady.mouseoverGUID = Fns.SafeGetMouseoverGUID()
    lootReady.targetGUID = Fns.SafeGetTargetGUID()
    lootReady.npcGUID = Fns.SafeGetUnitGUID("npc")
    lootReady.time = GetTime()
    -- Structural bobber/pool (zone DB) or IsFishingLoot API. Profession loot is excluded so herb/ore
    -- in fishable zones does not set wasFishing (see ClassifyLootSession GameObject-only guard).
    local apiFish = Fns.SafeIsFishingLoot()
    local structuralFish = Fns.LootSourcesLookLikeFishingOnly(lootReady.sourceGUIDs)
        and Fns.IsInTrackableFishingZone()
    -- Cast TTL alone + fishable zone was counting normal mob loot when sources were empty/secret.
    -- IsFishingLoot() is authoritative at LOOT_READY: ignore target/mouseover mob corpses (common while
    -- fishing near kills); mob ground loot has IsFishingLoot() false, so we do not need the old unit guard.
    lootReady.wasFishing = structuralFish
        or (apiFish and not isProfessionLooting)
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
    if not lootSession.opened and Fns.IsAutoTryCounterEnabled() then
        local now = GetTime()
        -- After a normal OPENED session, first LOOT_CLOSED clears lootReady; a second client LOOT_CLOSED
        -- would otherwise promote an empty snapshot and spam "closed -> … loot=0" (no work to do).
        local readySnapshotValid = lootReady.time > 0 and (now - lootReady.time) <= LOOT_READY_STATE_TTL
        if readySnapshotValid then
            local incomingPrimary = lootReady.sourceGUIDs and lootReady.sourceGUIDs[1] or lootReady.npcGUID
            local debounced = incomingPrimary and lastTryCountLootSourceGUID == incomingPrimary
                and (now - lastTryCountSourceTime) < CHAT_LOOT_DEBOUNCE
            if not debounced then
                Fns.PromoteLootReadyToSession()
                Fns.RouteLootSession(self, "closed")
            end
        end
    end

    -- Full cleanup: wipe both session and ready state so nothing bleeds into next loot event.
    Fns.ResetLootSession()
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
    -- Do not cancel fishingCtx.resetTimer on every close: that blocked the TTL from clearing stale
    -- fishingCtx after non-fishing loot, so cast-window + IsFishingLoot() could count herbs as fishing.
    -- Do NOT clear lastGatherCastName/lastGatherCastTime here (overwritten on next UNIT_SPELLCAST_SENT).
    -- DO NOT clear processedGUIDs here — let TTL-based cleanup handle it (PROCESSED_GUID_TTL = 300s)
end

---NEW_MOUNT_ADDED / NEW_PET_ADDED: definitive drop-acquired signal that fires
---even when no LOOT_OPENED window matches the kill (Sylvanas SoD post-cinematic chest, direct
---account-wide grants). Consumes the drop's reseed mark so the obtained-chat shows the correct
---attempt count. CollectionService still owns the obtained toast / journal sync; this handler
---only ensures the try-counter line is correct and the mark is cleared.
---@param tcType "mount"|"pet"|"toy"
---@param collectibleID number Native journal ID (mountID for NEW_MOUNT_ADDED, speciesID for pet, itemID for toy)
function Fns.HandleNewCollectibleAdded(tcType, collectibleID)
    if not Fns.IsAutoTryCounterEnabled() then return end
    if not collectibleID or type(collectibleID) ~= "number" or collectibleID <= 0 then return end
    if not Fns.EnsureDB() then return end

    -- Probe candidate marker keys: native journal ID first, then any teaching itemIDs the addon
    -- already resolved (`resolvedIDsReverse[mountID] = itemID`, populated when GetTryCountKey ran
    -- during ProcessMissedDrops). Pet/toy marks are itemID-keyed; for those we additionally probe
    -- via the addon's resolution caches if they exist.
    local candidateKeys = { collectibleID }
    if tcType == "mount" and resolvedIDsReverse then
        local itemID = resolvedIDsReverse[collectibleID]
        if type(itemID) == "number" and itemID > 0 and itemID ~= collectibleID then
            candidateKeys[#candidateKeys + 1] = itemID
        end
    end

    -- Resolve a display name once via pcall (Blizzard API can throw on stale IDs after expansion
    -- pre-patches). Each pcall return prefixed with `ok` boolean — vararg unpacks past it.
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
            return  -- consume only the first matching key
        end
    end
end

function WarbandNexus:OnTryCounterNewMountAdded(mountID)
    if issecretvalue and mountID and issecretvalue(mountID) then return end
    Fns.HandleNewCollectibleAdded("mount", tonumber(mountID))
end

function WarbandNexus:OnTryCounterNewPetAdded(petGUID)
    -- NEW_PET_ADDED payload is a battle-pet GUID string ("BattlePet-0-..."), NOT a speciesID.
    -- Resolve via C_PetJournal.GetPetInfoByPetID; the addon's pet try counts are speciesID-keyed.
    if not petGUID or type(petGUID) ~= "string" or petGUID == "" then return end
    if issecretvalue and issecretvalue(petGUID) then return end
    if not C_PetJournal or not C_PetJournal.GetPetInfoByPetID then return end
    local ok, speciesID = pcall(C_PetJournal.GetPetInfoByPetID, petGUID)
    if not ok or type(speciesID) ~= "number" or speciesID <= 0 then return end
    if issecretvalue and issecretvalue(speciesID) then return end
    Fns.HandleNewCollectibleAdded("pet", speciesID)
end

---CHAT_MSG_LOOT: strict fallback when loot window path already ran or never opened.
---Priority: repeatable reset → exact item→NPC → exact item→encounter → exact item→fishing.
---Each path requires EXACT itemID match against a known source; no guessing.
---@param message string
---@param author string
function WarbandNexus:OnTryCounterChatMsgLoot(message, author)
    if not message or not Fns.IsAutoTryCounterEnabled() then return end
    if issecretvalue then
        if issecretvalue(message) then return end
        if author and issecretvalue(author) then return end
    end

    -- Only process self-loot
    local playerName = UnitName("player")
    if not playerName or (issecretvalue and issecretvalue(playerName)) then return end
    local authorBase = author and author:match("^([^%-]+)") or author
    if author and author ~= "" and author ~= playerName and (not authorBase or authorBase ~= playerName) then return end

    local itemIDStr = message:match("|Hitem:(%d+):")
    local itemID = itemIDStr and tonumber(itemIDStr) or nil
    if not itemID then return end

    local now = GetTime()

    -- Global debounce: any route that already ran within the window blocks all CHAT paths.
    if lastTryCountSourceKey and (now - lastTryCountSourceTime) < CHAT_LOOT_DEBOUNCE then
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
        local tryKey = Fns.GetTryCountKey(repDrop)
        if tryKey then
            local preResetCount = self:GetTryCount(repDrop.type, tryKey)
            self:ResetTryCount(repDrop.type, tryKey)
            lastTryCountSourceKey = "item_" .. tostring(itemID)
            lastTryCountSourceTime = now
            local itemLink = Fns.GetDropItemLink(repDrop)
            Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_OBTAINED_RESET", "Obtained %s! Try counter reset.", itemLink, preResetCount))
            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
            local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(repDrop.itemID)
            SendTryCounterCollectibleObtained(self, {
                type = "item", id = repDrop.itemID,
                name = itemName or repDrop.name or "Unknown", icon = itemIcon,
                preResetTryCount = preResetCount,
                fromTryCounter = true,
            }, repDrop.itemID)
        end
        return
    end

    -- Paths 2-4: suppress when loot window is active (primary path already counted).
    if lootWindowActive then return end

    -- Path 2: Exact item→NPC match (chatLootItemToNpc built from eligible NPCs only)
    local npcID = chatLootItemToNpc[itemID]
    if npcID == false then return end
    if npcID then
        local drops = npcDropDB[npcID]
        if drops then
            local inInst = IsInInstance()
            if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
            -- Resolve difficulty from recentKills for this NPC's encounter (mirrors LOOT path).
            local chatP2KillDiff = nil
            for _, killData in pairs(recentKills or {}) do
                if killData.isEncounter and killData.npcID == npcID and killData.difficultyID
                    and not (issecretvalue and issecretvalue(killData.difficultyID)) then
                    chatP2KillDiff = killData.difficultyID
                    break
                end
            end
            -- Same chest/session idea as ProcessNPCLoot: freshest encounter kill whose table lists this
            -- chat item (covers edge cases where strict npcID match missed a difficulty snapshot).
            if not chatP2KillDiff and inInst then
                local itemSet = { [itemID] = true }
                local tNow = GetTime()
                local bestT = 0
                for _, killData in pairs(recentKills or {}) do
                    if killData.isEncounter and killData.difficultyID
                        and not (issecretvalue and issecretvalue(killData.difficultyID))
                        and killData.npcID and npcDropDB[killData.npcID]
                        and tryCounterNpcEligible[killData.npcID]
                        and (tNow - killData.time) < ENCOUNTER_OBJECT_TTL then
                        if Fns.NpcDropEntryContainsAnyItemSet(npcDropDB[killData.npcID], itemSet) and killData.time > bestT then
                            bestT = killData.time
                            chatP2KillDiff = killData.difficultyID
                        end
                    end
                end
            end
            local encDiff = Fns.ResolveEncounterDifficultyForLootGating(inInst, chatP2KillDiff, nil)
            local trackable = Fns.FilterDropsByDifficulty(drops, encDiff)
            if #trackable > 0 then
                local encForKey = Fns.GetEncounterIDForNpcID(npcID)
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
                    if not foundDrop.repeatable and foundDrop.type == "item" then Fns.MarkItemObtained(foundDrop.itemID) end
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(foundDrop)
                    if tryKey then
                        local preResetCount = self:GetTryCount(tcType, tryKey)
                        preResetCount = Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, tryKey)
                        self:ResetTryCount(tcType, tryKey)
                        local cacheKey = tcType .. "\0" .. tostring(tryKey)
                        pendingPreResetCounts[cacheKey] = preResetCount or 0
                        C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                        local itemLink = Fns.GetDropItemLink(foundDrop)
                        local chatKey = foundDrop.repeatable and "TRYCOUNTER_OBTAINED_RESET" or "TRYCOUNTER_OBTAINED"
                        local chatFallback = foundDrop.repeatable and "Obtained %s! Try counter reset." or "Obtained %s!"
                        Fns.TryChat(Fns.BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                        if self.SendMessage then
                            local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                            local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(foundDrop.itemID)
                            SendTryCounterCollectibleObtained(self, {
                                type = tcType, id = (foundDrop.type == "item") and foundDrop.itemID or tryKey,
                                name = itemName or foundDrop.name or "Unknown", icon = itemIcon,
                                preResetTryCount = preResetCount,
                                fromTryCounter = true,
                            }, foundDrop.itemID)
                        end
                    end
                end

                -- Increment missed drops (items NOT found in this loot)
                if #missed > 0 then
                    Fns.TryCounterLootDebugDropLines(self, "Chat-NPC", missed)
                    Fns.ProcessMissedDrops(missed, drops.statisticIds)
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
                    local encDiff = Fns.ResolveEncounterDifficultyForLootGating(inInst, killData.difficultyID, nil)
                    local trackable = Fns.FilterDropsByDifficulty(drops, encDiff)
                    if #trackable > 0 then
                        local encForKey = Fns.GetEncounterIDForNpcID(killData.npcID)
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
                            if not foundDrop.repeatable and foundDrop.type == "item" then Fns.MarkItemObtained(foundDrop.itemID) end
                            local tcType, tryKey = Fns.GetTryCountTypeAndKey(foundDrop)
                            if tryKey then
                                local preResetCount = self:GetTryCount(tcType, tryKey)
                                preResetCount = Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, tryKey)
                                self:ResetTryCount(tcType, tryKey)
                                local cacheKey = tcType .. "\0" .. tostring(tryKey)
                                pendingPreResetCounts[cacheKey] = preResetCount or 0
                                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                                local itemLink = Fns.GetDropItemLink(foundDrop)
                                local chatKey = foundDrop.repeatable and "TRYCOUNTER_OBTAINED_RESET" or "TRYCOUNTER_OBTAINED"
                                local chatFallback = foundDrop.repeatable and "Obtained %s! Try counter reset." or "Obtained %s!"
                                Fns.TryChat(Fns.BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                                if self.SendMessage then
                                    local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                                    local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(foundDrop.itemID)
                                    SendTryCounterCollectibleObtained(self, {
                                        type = tcType, id = (foundDrop.type == "item") and foundDrop.itemID or tryKey,
                                        name = itemName or foundDrop.name or "Unknown", icon = itemIcon,
                                        preResetTryCount = preResetCount,
                                        fromTryCounter = true,
                                    }, foundDrop.itemID)
                                end
                            end
                        end

                        -- Increment missed drops only
                        if #missed > 0 then
                            Fns.TryCounterLootDebugDropLines(self, "Chat-Encounter", missed)
                            Fns.ProcessMissedDrops(missed, drops.statisticIds)
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
        and Fns.IsInTrackableFishingZone()
        and not Fns.CurrentUnitsHaveMobLootContext() then
        local fishingItemIDs = Fns.GetFishingDropItemIDsForCurrentZone()
        if fishingItemIDs and fishingItemIDs[itemID] then
            local trackable = Fns.GetFishingTrackableForCurrentZone()
            if #trackable > 0 then
                -- Check if the caught item is a trackable (→ reset), else +1
                local caughtDrop = nil
                for i = 1, #trackable do
                    if trackable[i].itemID == itemID then caughtDrop = trackable[i]; break end
                end
                if caughtDrop then
                    if not caughtDrop.repeatable and caughtDrop.type == "item" then Fns.MarkItemObtained(caughtDrop.itemID) end
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(caughtDrop)
                    if tryKey then
                        local preResetCount = self:GetTryCount(tcType, tryKey)
                        self:ResetTryCount(tcType, tryKey)
                        lastTryCountSourceKey = "item_" .. tostring(itemID)
                        lastTryCountSourceTime = now
                        local itemLink = Fns.GetDropItemLink(caughtDrop)
                        local chatKey = caughtDrop.repeatable and "TRYCOUNTER_CAUGHT_RESET" or "TRYCOUNTER_CAUGHT"
                        local chatFallback = caughtDrop.repeatable and "Caught %s! Try counter reset." or "Caught %s!"
                        Fns.TryChat(Fns.BuildObtainedChat(chatKey, chatFallback, itemLink, preResetCount))
                        
                        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(caughtDrop.itemID)
                        if self.SendMessage then
                            SendTryCounterCollectibleObtained(self, {
                                type = tcType, id = tryKey,
                                name = itemName or caughtDrop.name or "Unknown", icon = itemIcon,
                                preResetTryCount = preResetCount,
                                fromTryCounter = true,
                            }, caughtDrop.itemID)
                        end
                    end
                    return
                end
                lastTryCountSourceKey = "fishing_chat"
                lastTryCountSourceTime = now
                Fns.TryCounterLootDebugDropLines(self, "Chat-Fishing", trackable)
                Fns.ProcessMissedDrops(trackable, nil)
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
    if not Fns.IsAutoTryCounterEnabled() then return end
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

---Collect ALL fishing drops for the player's current zone (global + map chain).
---Single source of truth for the instance-check → map-chain-walk → fishingDropDB merge
---pattern. Returns raw (unfiltered) drop array.
---@return table drops, boolean inInstance
function Fns.CollectFishingDropsForZone()
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if inInstance then return {}, true end
    local mapID = Fns.GetSafeMapID()
    local drops = {}
    local seen = {}  -- dedup: same drop registered at child + parent map would double-count
    -- IMPORTANT:
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

---@return table trackable  Uncollected fishing drops for current zone
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

---@return table|nil  [itemID]=true set of ALL fishing drop itemIDs in zone, or nil
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

-- =====================================================================
-- LOOT SESSION HELPERS (shared by LOOT_READY, LOOT_OPENED, LOOT_CLOSED)
-- =====================================================================

---True if GUID is a Creature or Vehicle (corpse / NPC loot context). Gathering nodes are GameObject.
function Fns.UnitGuidLooksLikeMobCorpse(guid)
    if type(guid) ~= "string" then return false end
    return guid:match("^Creature") ~= nil or guid:match("^Vehicle") ~= nil
end

---Any loot slot source is a mob corpse — not limited to try-counter-eligible NPCs.
---Without this, trash mobs fail LootEligibleNpcFromGuid() and ClassifyLootSession
---misroutes corpse loot to ProcessFishingLoot when fishingCtx is fresh (Nether-Warped Egg +1).
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

---Eligible try-counter NPC from corpse GUID (nil if not a rare-tier source we track on corpses).
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

---Uses lootSession snapshot (deferred/opened capture). When set, mob loot should run even if
---GetLootSourceInfo reports a GameObject (seen after a recent herb/ore cast in same session).
function Fns.LootSessionHasMobLootContext()
    return IsBlockingMobCorpseGuid(lootSession.mouseoverGUID)
        or IsBlockingMobCorpseGuid(lootSession.targetGUID)
        or IsBlockingMobCorpseGuid(lootSession.npcGUID)
end

---Same as LootSessionHasMobLootContext but for LOOT_READY snapshot (lootSession not filled yet).
---@param mouseoverGUID string|nil
---@param targetGUID string|nil
---@param npcGUID string|nil
---@return boolean
function Fns.LootReadySnapshotHasMobLootContext(mouseoverGUID, targetGUID, npcGUID)
    return IsBlockingMobCorpseGuid(mouseoverGUID)
        or IsBlockingMobCorpseGuid(targetGUID)
        or IsBlockingMobCorpseGuid(npcGUID)
end

---Fresh read at call site (e.g. LOOT_CLOSED before session is promoted).
Fns.CurrentUnitsHaveMobLootContext = function()
    local mo = Fns.SafeGetMouseoverGUID()
    local tg = Fns.SafeGetTargetGUID()
    local npc = Fns.SafeGetUnitGUID("npc")
    return IsBlockingMobCorpseGuid(mo) or IsBlockingMobCorpseGuid(tg) or IsBlockingMobCorpseGuid(npc)
end

---Fully reset lootSession to a clean state. Called at the start of every new
---loot event (LOOT_READY) and at the end of LOOT_CLOSED to prevent stale data
---from bleeding into the next session.
Fns.ResetLootSession = function()
    lootSession.numLoot = 0
    lootSession.sourceGUIDs = {}
    wipe(lootSession.slotData)
    lootSession.mouseoverGUID = nil
    lootSession.targetGUID = nil
    lootSession.npcGUID = nil
    lootSession.opened = false
end

---Snapshot unit GUIDs + loot window data into lootSession (same-frame read before fast auto-loot clears it).
Fns.CaptureLootSessionState = function()
    Fns.ResetLootSession()
    lootSession.mouseoverGUID = Fns.SafeGetMouseoverGUID()
    lootSession.targetGUID = Fns.SafeGetTargetGUID()
    lootSession.npcGUID = Fns.SafeGetUnitGUID("npc")
    lootSession.numLoot = (GetNumLootItems and GetNumLootItems()) or 0
    lootSession.sourceGUIDs = Fns.GetAllLootSourceGUIDs() or {}
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
--   3. FISHING    — IsFishingLoot() API OR structural bobber/pool sources in fishable zone;
--                   never from cast timer + empty sources alone.
--   4. NPC/OBJECT — ProcessNPCLoot (exact GUID→ID match only)
-- =====================================================================

---Classify the loot session source into exactly one route.
---@return string route "skip"|"container"|"fishing"|"npc"|"none"
Fns.ClassifyLootSession = function(source, isFromItem)
    -- 1. SKIP: non-combat loot sources
    if isPickpocketing then return "skip" end
    if isBlockingInteractionOpen then return "skip" end
    if isProfessionLooting then return "skip" end

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
            return "skip"
        end
    end

    -- GameObject-only loot (herb/ore) in open-world maps that have fishing DB entries is not fishing
    -- unless API or structural bobber/pool says so (prevents false ProcessFishingLoot on Thorncap etc.).
    local inInstance = IsInInstance()
    if issecretvalue and inInstance and issecretvalue(inInstance) then inInstance = nil end
    if not inInstance and Fns.LootSessionSourcesAreOnlyGameObjects(lootSession.sourceGUIDs) and Fns.IsInTrackableFishingZone() then
        local structFish = Fns.LootSourcesLookLikeFishingOnly(lootSession.sourceGUIDs)
        local apiOpen = (source == "opened" and Fns.SafeIsFishingLoot() and not isProfessionLooting)
        local closedFish = (source == "closed" and lootReady.wasFishing)
        if not structFish and not apiOpen and not closedFish then
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

    -- 3. FISHING: IsFishingLoot() API, LOOT_READY snapshot, or structural bobber/pool sources in zone.
    --    Removed: "fishable zone + cast TTL + empty sources" — that misclassified normal kills after fishing.
    local fishingFromSourcesOnly = Fns.LootSourcesLookLikeFishingOnly(lootSession.sourceGUIDs)
        and Fns.IsInTrackableFishingZone()
    local fishingLootAPI = false
    if source == "opened" then
        fishingLootAPI = Fns.SafeIsFishingLoot() and not isProfessionLooting
    elseif source == "closed" then
        -- LOOT_OPENED is often skipped by auto-loot; use LOOT_READY snapshot and API while still valid.
        if lootReady.wasFishing then
            fishingLootAPI = true
        else
            fishingLootAPI = Fns.SafeIsFishingLoot() and not isProfessionLooting
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

---Unified routing: classify then dispatch to exactly one processor.
---@param self table WarbandNexus addon reference
---@param source string "opened"|"closed"
---@param isFromItem boolean|nil Container item flag (only from LOOT_OPENED)
Fns.RouteLootSession = function(self, source, isFromItem)
    if not Fns.IsAutoTryCounterEnabled() then return end

    local route = Fns.ClassifyLootSession(source, isFromItem)

    if route == "skip" then return end
    if route == "container" then self:ProcessContainerLoot(); return end
    if route == "fishing" then self:ProcessFishingLoot(); return end
    if route == "npc" then
        -- SoD Mythic: mount outcome from slot links alone (secret GUID chest / personal loot).
        if Fns.TryInstanceBossSlotOutcomeFirst(self) then return end
        self:ProcessNPCLoot()
        return
    end
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
    Fns.CaptureLootSessionState()
    lootSession.opened = true
    Fns.RouteLootSession(self, "opened", isFromItem)
end


-- =====================================================================
-- PROCESSING PATHS
-- =====================================================================

---Collect ALL unique loot source GUIDs from the loot window.
---GetLootSourceInfo(slot) returns guid1, quantity1, guid2, quantity2, ... for merged loot.
---Using only the first return misses every other corpse in a combined AoE window (try count ×1).
---Falls back to UnitGUID("npc") which is set during some NPC/object interactions.
---@return table uniqueGUIDs Array of unique safe GUID strings (may be empty)
Fns.GetAllLootSourceGUIDs = function()
    local uniqueGUIDs = {}
    local seen = {}

    local inRaidForGo = false
    do
        local okII, inI, instType = pcall(IsInInstance)
        if okII and inI and instType and not (issecretvalue and issecretvalue(instType)) and instType == "raid" then
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
                    end
                end
            end
        end
    end

    -- Method 2: UnitGUID("npc" / "mouseover" / "target") when slots are empty (instant autoloot) or
    -- GetLootSourceInfo missed a source. Include GameObjects listed in objectDropDB (e.g. Sylvanas chest)
    -- — the old logic only allowed Creature/Vehicle, so 0-slot chest opens produced no GUIDs and
    -- ProcessNPCLoot could not resolve the boss/object row before recentKills expired.
    local unitTokens = { "npc", "mouseover", "target" }
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

---How many distinct non-GameObject loot sources in this window share the same npcDropDB
---table as `dropsTable` (Lua reference equality only).
---NOTE: LoadRuntimeSourceTables uses CopyDropArray per NPC id, so clones of the same logical mount
---(e.g. Bloodfeaster on Ritualist vs Drudge) are different tables — use CountCorpsesForMissedDropItems.
---@param allSourceGUIDs table
---@param dropsTable table
---@return number
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

---Distinct sources for this npc: strict id from parser, else Creature/Vehicle GUID containing "-npcID-"
---(spawn UID quirks can make GetNPCIDFromGUID miss one corpse while the entry id still appears in the string).
---@param allSourceGUIDs table
---@param npcID number
---@return number
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

---@param dlist table[]
---@return table itemID -> true
function Fns.BuildItemIdSetFromDropList(dlist)
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

---Corpses in merged loot that can drop the same missed item(s), across npc ids (fixes CopyDropArray table split).
---@param allSourceGUIDs table
---@param itemIdSet table
---@param candidateNpcIds number[]
---@return number
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

---Stable key for open-world merged loot (order-independent source GUID list).
---@param guids table
---@return string
function Fns.BuildSortedSourceFingerprint(guids)
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

---P2: Resolve from unit GUIDs (npc/mouseover/target/lastLoot).
---Only runs when P1 found no match. Each GUID requires exact ID equality.
function Fns.ResolveFromUnits(ctx, numLoot, addon)
    if ctx.drops then return end
    local lootIsEmpty = (numLoot == 0)

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

---P3: Resolve from zone pools that are truly zone-wide (hostileOnly, no raresOnly).
---Midnight "zone rare mount" entries use raresOnly+hostileOnly for tooltips; they must NOT drive try
---counts unless P1/P2 matched a corpse GUID to an npcID in npcDropDB (explicit rare list).
---Previous bug: hostileOnly was checked before raresOnly, so any normal mob in Zul'Aman/Quel'Thalas/etc.
---incremented Amani Sharptalon and other shared-pool mounts.
function Fns.ResolveFromZone(ctx, inInstance, addon)
    if ctx.drops then return end
    if not next(zoneDropDB) then return end
    if ctx.sourceIsGameObject or inInstance then return end

    if (GetTime() - lastEncounterEndTime) < RECENT_KILL_TTL then return end

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

---True when P1 left a housekeeping dedupGUID that is NOT an exact tracked npc/object row.
---Personal / group loot often lists Player-* or unrelated Creature GUIDs first; the old
---`not dedupGUID or sourceIsGameObject` rule blocked P4 entirely so encounter misses never counted.
---@param guid string|nil
---@return boolean
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

---P4: Resolve from recentKills (ENCOUNTER_END boss entries).
---Only matches encounter NPCs that are in npcDropDB AND eligible.
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

---P5: Resolve from ENCOUNTER_START cache when in an instance and every prior path failed.
---Midnight 12.0 rescue path — handles the worst-case scenario where:
---  * GetLootSourceInfo returns secret GUIDs (P1 empty after SafeGuardGUID)
---  * UnitGUID("npc"/"target"/"mouseover") returns secrets (P2 empty)
---  * ENCOUNTER_END hasn't fired yet OR fired with fully secret payload (P4 empty)
---The cached ENCOUNTER_START data gives us a non-secret encounterID/Name → encounterDB → npcIDs.
---Only activates when inInstance=true and the cache is fresh.
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

---P5b: SoD mythic post-boss chest when Blizzard uses a new GameObject id (e.g. Domination-Etched Treasure Cache).
---Raid + mythic + template 1193 + any unprocessed GameObject GUID → canonical objectDrop row 368304
---so difficulty/stat overlap logic still runs against recentKills / npc 175732.
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

---True when current raid instance is Sanctum of Domination on Mythic (template id + difficulty).
function Fns.IsSanctumMythicRaid()
    local _, instType, diff, _, _, _, _, tmpl = GetInstanceInfo()
    if issecretvalue and instType and issecretvalue(instType) then instType = nil end
    if issecretvalue and diff and issecretvalue(diff) then diff = nil end
    if issecretvalue and tmpl and issecretvalue(tmpl) then tmpl = nil end
    return instType == "raid" and diff == RAID_MYTHIC_DIFFICULTY_ID and tmpl == SANCTUM_RAID_TEMPLATE_INSTANCE_ID
end

---@param rule table CollectibleSourceDB.instanceBossSlotOutcomeRules[] entry
---@param instType string|nil GetInstanceInfo instanceType
---@param diff number|nil difficultyID
---@param tmpl number|nil template instance id (GetInstanceInfo 8th)
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

---Newest recentKills encounter entry for bossNpcID within ENCOUNTER_OBJECT_TTL.
---@return string|nil killGuid
---@return table|nil killData
function Fns.GetFreshEncounterKillForNpc(npcId)
    if not npcId then return nil, nil end
    local now = GetTime()
    local bestGuid, bestKill = nil, nil
    for guid, kd in pairs(recentKills) do
        if kd and kd.isEncounter and kd.npcID == npcId and (now - kd.time) < ENCOUNTER_OBJECT_TTL then
            if not bestKill or kd.time > bestKill.time then
                bestKill = kd
                bestGuid = guid
            end
        end
    end
    return bestGuid, bestKill
end

---Another tracked eligible corpse in merged loot (not this boss) — let ProcessNPCLoot own that session.
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

---At least one loot slot has a non-secret item link (so "mount not in list" is trustworthy vs all-secret).
function Fns.LootSlotsHaveReadableItemLink(slotData, numLoot)
    if not numLoot or numLoot < 1 or not slotData then return false end
    for i = 1, numLoot do
        local sd = slotData[i]
        if sd and sd.hasItem and sd.link and type(sd.link) == "string" and not (issecretvalue and issecretvalue(sd.link)) then
            return true
        end
    end
    return false
end

function Fns.ClearEncounterRecentKillsForNpcId(npcId)
    if not npcId then return end
    for guid, kd in pairs(recentKills) do
        if kd and kd.isEncounter and kd.npcID == npcId then
            recentKills[guid] = nil
        end
    end
end

---Repeatable / non-repeatable found + BoP pre-cache (mirrors ProcessNPCLoot slot scan handlers).
function Fns.ApplyBossSlotOutcomeFoundHandlers(trackable, found, drops)
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop and drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                preResetCount = Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, tryKey)
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
            end
        end
    end
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop and not drop.repeatable and found[drop.itemID] then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
                currentCount = Fns.AdjustPreResetForDelayedReseed(currentCount, tcType, tryKey)
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

---CollectibleSourceDB.instanceBossSlotOutcomeRules: slot scan before GUID resolution (chest / secret sources).
---@param self WarbandNexus
---@return boolean handled When true, ProcessNPCLoot must not run for this session.
function Fns.TryInstanceBossSlotOutcomeFirst(self)
    if not self or not Fns.IsAutoTryCounterEnabled() then return false end
    if #instanceBossSlotOutcomeRules == 0 then return false end

    local _, instType, diff, _, _, _, _, tmpl = GetInstanceInfo()
    if issecretvalue and instType and issecretvalue(instType) then instType = nil end
    if issecretvalue and diff and issecretvalue(diff) then diff = nil end
    if issecretvalue and tmpl and issecretvalue(tmpl) then tmpl = nil end

    local bestRule, bestKillTime = nil, 0
    for ri = 1, #instanceBossSlotOutcomeRules do
        local r = instanceBossSlotOutcomeRules[ri]
        if Fns.SlotOutcomeRuleMatchesInstance(r, instType, diff, tmpl) then
            if not Fns.IsLockoutDuplicate(r.bossNpcID) then
                local _, kd = Fns.GetFreshEncounterKillForNpc(r.bossNpcID)
                if kd and kd.time > bestKillTime then
                    bestKillTime = kd.time
                    bestRule = r
                end
            end
        end
    end
    if not bestRule then return false end

    local sources = lootSession.sourceGUIDs or {}
    if Fns.LootSourcesHaveForeignEligibleCreature(sources, bestRule.bossNpcID) then return false end

    local drops = npcDropDB[bestRule.bossNpcID]
    if not drops then return false end

    local _, killData = Fns.GetFreshEncounterKillForNpc(bestRule.bossNpcID)
    if not killData then return false end

    local recentKillDiff = killData.difficultyID
    if issecretvalue and recentKillDiff and issecretvalue(recentKillDiff) then recentKillDiff = nil end
    local encounterDiffID = Fns.ResolveEncounterDifficultyForLootGating(true, recentKillDiff, diff)
    local trackable = Fns.FilterDropsByDifficulty(drops, encounterDiffID)
    if #trackable == 0 then return false end

    local numLoot = lootSession.numLoot or 0
    if numLoot < 1 then return false end

    local found = Fns.ScanLootForItems(trackable, numLoot, lootSession.slotData)

    local anyFound = false
    for ti = 1, #trackable do
        local d = trackable[ti]
        if d and found[d.itemID] then
            anyFound = true
            break
        end
    end

    local now = GetTime()
    local encounterIDForKey = Fns.GetEncounterIDForNpcID(bestRule.bossNpcID) or bestRule.encounterJournalID
    local slotOutcomeSourceKey = encounterIDForKey
        and ("encounter_" .. tostring(encounterIDForKey))
        or ("inst_slot_" .. tostring(bestRule.bossNpcID))
    if anyFound then
        Fns.ClearEncounterRecentKillsForNpcId(bestRule.bossNpcID)
        Fns.ApplyBossSlotOutcomeFoundHandlers(trackable, found, drops)
        lastTryCountSourceKey = slotOutcomeSourceKey
        lastTryCountSourceTime = now
        lastTryCountLootSourceGUID = sources[1]
        return true
    end

    if not Fns.LootSlotsHaveReadableItemLink(lootSession.slotData, numLoot) then return false end

    local missed = {}
    for mi = 1, #trackable do
        local d = trackable[mi]
        if d and not found[d.itemID] then
            missed[#missed + 1] = d
        end
    end
    if #missed == 0 then return false end

    Fns.ClearEncounterRecentKillsForNpcId(bestRule.bossNpcID)
    if slotOutcomeSourceKey and lastTryCountSourceKey == slotOutcomeSourceKey and (now - lastTryCountSourceTime) < 15 then
        lastTryCountLootSourceGUID = sources[1]
        return true
    end
    Fns.TryCounterLootDebugDropLines(self, "SlotOutcome", missed, 1)
    Fns.ProcessMissedDrops(missed, drops.statisticIds, {
        attemptTimes = 1,
        statReseedLootMissFallback = true,
    })
    lastTryCountSourceKey = slotOutcomeSourceKey
    lastTryCountSourceTime = now
    lastTryCountLootSourceGUID = sources[1]
    return true
end

-- =====================================================================
-- ProcessNPCLoot — orchestrator: P1→P2→P3→P4, first match wins, exact IDs only.
-- =====================================================================

---DungeonEncounterID for CHAT/loot dedup (must match BuildTryCountSourceKey encounter_*).
---@param npcID number|nil
---@return number|nil
function Fns.GetEncounterIDForNpcID(npcID)
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
        end
        return
    end
    self._pendingEncounterLoot = nil

    -- Unpack ctx into locals for readability in post-match processing
    local drops = ctx.drops
    local matchedNpcID = ctx.matchedNpcID
    local dedupGUID = ctx.dedupGUID
    local lastMatchedObjectID = ctx.lastMatchedObjectID

    -- Daily/weekly lockout check
    local isLockoutSkip = matchedNpcID and Fns.IsLockoutDuplicate(matchedNpcID)

    -- Auto-discovery: if this NPC has drops but no lockout quest, schedule discovery
    if matchedNpcID and not lockoutQuestsDB[matchedNpcID] and (npcDropDB[matchedNpcID] or (ns.CollectibleSourceDB and ns.CollectibleSourceDB.rares and ns.CollectibleSourceDB.rares[matchedNpcID])) then
        discoveryPendingNpcID = matchedNpcID
        discoveryPendingTime = GetTime()
        C_Timer.After(2, Fns.TryDiscoverLockoutQuest)
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
        -- Do NOT set lastTryCountSourceKey here: no try was consumed. Setting it blocked the ENCOUNTER_END
        -- 5s delayed fallback (debounce saw a "phantom" encounter touch within 10s) and left mythic chest
        -- paths with nil difficulty permanently uncounted until a reload.
        return
    end

    -- Scan loot window (use state captured at LOOT_OPENED start)
    local found = Fns.ScanLootForItems(trackable, lootSession.numLoot, lootSession.slotData)

    -- Repeatable drops FOUND in loot → reset try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                preResetCount = Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, tryKey)
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
            end
        end
    end

    -- Non-repeatable drops FOUND in loot → notification (mount/pet/toy from boss)
    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and found[drop.itemID] then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                local currentCount = WarbandNexus:GetTryCount(tcType, tryKey)
                currentCount = Fns.AdjustPreResetForDelayedReseed(currentCount, tcType, tryKey)
                -- Always cache (even when 0 = first try) so BoP auto-collect events
                -- from CollectionService read the correct pre-reset count.
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
            end
        end
    end

    -- Pre-cache try counts for all non-repeatable mounts/pets/toys (BoP auto-collect handling).
    -- Skip drops already found in loot — their pendingPreResetCounts were set correctly
    -- (with AdjustPreResetForDelayedReseed) in the found-drop handler above.
    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and drop.type ~= "item" and not found[drop.itemID] then
            local tryKey = Fns.GetTryCountKey(drop)
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
        
        local lockDedupKey = (matchedEncounterID and ("lockskip_enc_" .. tostring(matchedEncounterID)))
            or (matchedNpcID and ("lockskip_npc_" .. tostring(matchedNpcID)))
            or "lockskip_generic"
        local tLock = GetTime()
        if lockDedupKey ~= lastLockoutSkipChatKey or (tLock - lastLockoutSkipChatTime) >= SKIP_CHAT_DEDUP_SEC then
            lastLockoutSkipChatKey = lockDedupKey
            lastLockoutSkipChatTime = tLock
            Fns.TryChat("|cff9370DB[WN-Counter]|r |cff888888" .. ((ns.L and ns.L["TRYCOUNTER_LOCKOUT_SKIP"]) or "Skipped: daily/weekly lockout active for this NPC."))
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

    -- Same-kill dedup: when ENCOUNTER_END just incremented this same encounter/npc/object/corpse
    -- and LOOT_OPENED also fires, the source-key match on a recent timestamp tells us this is the
    -- SAME kill (different path), not a NEW kill. Per-corpse GUID is part of the source key for
    -- open-world rares, so consecutive rare kills produce different source keys and never dedup —
    -- ID-stable AT THE KILL LEVEL while still preventing same-kill double-counting.
    -- Stat-backed drops bypass this filter: ReseedStatisticsForDrops is idempotent (max(stat,
    -- current)) and re-running it can only catch up to a later GetStatistic value, never inflate.
    local tryCountSourceKey = Fns.BuildTryCountSourceKey(matchedEncounterID, matchedNpcID, lastMatchedObjectID, dedupGUID)
    if #dropsToIncrement > 0 and tryCountSourceKey
        and lastTryCountSourceKey == tryCountSourceKey and (now - lastTryCountSourceTime) < 15 then
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

    -- Fingerprint dedup: same npc + same multiset of loot source GUIDs = one miss-increment wave.
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

    lastTryCountSourceKey = tryCountSourceKey
    lastTryCountSourceTime = GetTime()
    if tryCountSourceKey then
        lastTryCountLootSourceGUID = (type(dedupGUID) == "string" and dedupGUID) or allSourceGUIDs[1]
    else
        lastTryCountLootSourceGUID = nil
    end

    -- Increment try counts
    local statIds = drops and drops.statisticIds or nil
    Fns.TryCounterLootDebugDropLines(self, "NPC", dropsToIncrement, farmCorpseMult)
    Fns.ProcessMissedDrops(dropsToIncrement, statIds, { attemptTimes = farmCorpseMult })
    if mergeFp and willIncrementMisses then
        mergedLootTryCountedAt[mergeFp] = GetTime()
    end
end

---Process loot from fishing.
---Algorithm (source-agnostic): one loot open in a trackable zone = one attempt.
---We do NOT care what dropped (common/rare); we only check: is the trackable drop (e.g. Nether-Warped Egg) in the loot?
---If yes → reset try count; if no → increment. So every fishing LOOT_OPENED in zone is counted.
function WarbandNexus:ProcessFishingLoot()
    -- Gathering/profession loot windows must never count zone fishing tries (e.g. herb in Voidstorm).
    if isProfessionLooting then return end
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

    fishingCtx.lootWasFishing = true -- so LOOT_CLOSED only clears fishingCtx.active when this loot window closes (avoids clearing after unrelated loot)

    -- Scan loot window (use state captured at LOOT_OPENED start)
    local found = Fns.ScanLootForItems(trackable, lootSession.numLoot, lootSession.slotData)
    -- Check for repeatable mounts that were FOUND in loot -> reset their try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if drop.repeatable and found[drop.itemID] then
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                
                -- Set debounce key to prevent CHAT_MSG_LOOT from also resetting (if item type is "item")
                if drop.type == "item" then
                    lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                    lastTryCountSourceTime = GetTime()
                end
                
                if tcType ~= "item" then
                    local cacheKey = tcType .. "\0" .. tostring(tryKey)
                    pendingPreResetCounts[cacheKey] = preResetCount or 0
                    C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                end
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_CAUGHT_RESET", "Caught %s! Try counter reset.", itemLink, preResetCount))
                -- Fire notification (BAM moment)
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType,
                    id = tryKey,
                    name = itemName or drop.name or "Unknown",
                    icon = itemIcon,
                    preResetTryCount = preResetCount,
                    fromTryCounter = true,
                }, drop.itemID)
            end
        end
    end

    -- Non-repeatable drops FOUND in loot (e.g. Nether-Warped Egg -> Nether-Warped Drake, or direct mount drops): reset reflected try count
    for i = 1, #trackable do
        local drop = trackable[i]
        if not drop.repeatable and found[drop.itemID] then
            if drop.type == "item" then Fns.MarkItemObtained(drop.itemID) end
            local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
            if tryKey then
                local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                WarbandNexus:ResetTryCount(tcType, tryKey)
                local cacheKey = tcType .. "\0" .. tostring(tryKey)
                pendingPreResetCounts[cacheKey] = preResetCount or 0
                C_Timer.After(30, function() pendingPreResetCounts[cacheKey] = nil end)
                lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                lastTryCountSourceTime = GetTime()
                local itemLink = Fns.GetDropItemLink(drop)
                Fns.TryChat(Fns.BuildObtainedChat("TRYCOUNTER_CAUGHT", "Caught %s!", itemLink, preResetCount))
                -- Fire notification (BAM moment)
                local GetItemInfoFn = C_Item and C_Item.GetItemInfo or _G.GetItemInfo
                local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn and GetItemInfoFn(drop.itemID)
                SendTryCounterCollectibleObtained(WarbandNexus, {
                    type = tcType,
                    id = tryKey,
                    name = itemName or drop.name or "Unknown",
                    icon = itemIcon,
                    preResetTryCount = preResetCount,
                    fromTryCounter = true,
                }, drop.itemID)
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

    Fns.TryCounterLootDebugDropLines(self, "Fishing", missed)
    if #missed > 0 then
        lastTryCountSourceKey = "fishing_open"
        lastTryCountSourceTime = GetTime()
    end
        Fns.ProcessMissedDrops(missed, nil)
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
            if drop.repeatable or not Fns.IsCollectibleCollected(drop) then
                trackable[#trackable + 1] = drop
            end
        end
        if #trackable == 0 then return end

        -- Scan loot window (use state captured at LOOT_OPENED start)
        local found = Fns.ScanLootForItems(trackable, lootSession.numLoot, lootSession.slotData)

        -- Check for drops that were FOUND in loot (repeatable or not) -> reset try count (use reflected type/key for item->mount)
        for i = 1, #trackable do
            local drop = trackable[i]
            if found[drop.itemID] then
                if not drop.repeatable and drop.type == "item" then
                    Fns.MarkItemObtained(drop.itemID)
                end
                local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                if tryKey then
                    Fns.ResolveCollectibleID(drop)
                    local preResetCount = WarbandNexus:GetTryCount(tcType, tryKey)
                    WarbandNexus:ResetTryCount(tcType, tryKey)
                    if drop.type == "item" then
                        lastTryCountSourceKey = "item_" .. tostring(drop.itemID)
                        lastTryCountSourceTime = GetTime()
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
                        name = itemName or drop.name or "Unknown",
                        icon = itemIcon,
                        preResetTryCount = preResetCount,
                        fromTryCounter = true,
                    }, drop.itemID)
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

        Fns.ProcessMissedDrops(missed)
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

-- =====================================================================
-- TRACKDB MERGE (Custom entries overlay on CollectibleSourceDB)
-- =====================================================================

--- Merge user-defined custom entries into runtime DB tables and
--- remove entries the user has disabled. Called from InitializeTryCounter
--- BEFORE BuildReverseIndices() so indices include custom entries.
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

function Fns.SeedFromStatistics()
    if not Fns.EnsureDB() then return end
    if not GetStatistic then return end

    Fns.PruneStatisticSnapshotsOrphanKeys()
    Fns.RebuildMergedStatisticSeedIndex()

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
        local sids = Fns.ResolveReseedStatIdsForDrop(pend.drop, pend.npcStatIds)
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
        if not Fns.EnsureDB() then return end
        local batchStart = debugprofilestop()

        while queueIdx <= #seedQueue do
            local entry = seedQueue[queueIdx]

            local function ProcessBatchDrop(drop, thisCharTotal, npcStatIdsForUnresolved)
                if not drop.guaranteed then
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
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
                        ProcessBatchDrop(qs, thisCharTotal, npcStatIdsForUnresolved)
                    end
                end
            end

            if entry.bucket then
                local b = entry.bucket
                local thisCharTotal = Fns.SumStatisticTotalsFromIds(b.statIds)
                for di = 1, #b.drops do
                    ProcessBatchDrop(b.drops[di], thisCharTotal, nil)
                end
            else
                local thisCharTotal = Fns.SumStatisticTotalsFromIds(entry.statIds)
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
                Fns.RebuildMergedStatisticSeedIndex()
                local retrySeeded = 0
                local stillUnresolved = {}
                for i = 1, #unresolvedDrops do
                    local uEntry = unresolvedDrops[i]
                    local drop = uEntry.drop
                    local tcType, tryKey = Fns.GetTryCountTypeAndKey(drop)
                    if tryKey then
                        local statList = Fns.ResolveMergedStatisticIdsForDrop(drop, Fns.ResolveReseedStatIdsForDrop(drop, uEntry.npcStatIds))
                        local t = Fns.SumStatisticTotalsFromIds(statList)
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
                        WarbandNexus:SendMessage(E.PLANS_UPDATED, { action = "statistics_seeded" })
                    end
                end
                Fns.ScheduleDeferredRarityMountMaxSync(2)

                if #stillUnresolved > 0 then
                    WarbandNexus:Debug("TryCounter: %d still unresolved, final retry in 30s...", #stillUnresolved)
                    C_Timer.After(30, function()
                        if not Fns.EnsureDB() then return end
                        Fns.RebuildMergedStatisticSeedIndex()
                        local finalSeeded = 0
                        local snaps = WarbandNexus.db.global.statisticSnapshots
                        for j = 1, #stillUnresolved do
                            local fEntry = stillUnresolved[j]
                            local drop = fEntry.drop
                            local tcType, finalKey = Fns.GetTryCountTypeAndKey(drop)
                            if finalKey and snaps then
                                local statList = Fns.ResolveMergedStatisticIdsForDrop(drop, Fns.ResolveReseedStatIdsForDrop(drop, fEntry.npcStatIds))
                                local t = Fns.SumStatisticTotalsFromIds(statList)
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

--- Coalesce CRITERIA_UPDATE / regen / encounter-kill into one GetStatistic re-read.
--- CRITERIA_UPDATE is high-frequency; debounce + min interval keep SeedFromStatistics off hot paths.
function Fns.RequestTryCounterStatisticsRuntimeRefresh()
    if not GetStatistic then return end
    if not Fns.IsAutoTryCounterEnabled() then return end
    statRuntimeDebounceSerial = statRuntimeDebounceSerial + 1
    local token = statRuntimeDebounceSerial
    C_Timer.After(STAT_RUNTIME_DEBOUNCE_SEC, function()
        if token ~= statRuntimeDebounceSerial then return end
        if not tryCounterReady or not Fns.EnsureDB() then return end
        if not Fns.IsAutoTryCounterEnabled() then return end
        local now = GetTime()
        if (now - lastStatRuntimeFullSeedAt) < STAT_RUNTIME_MIN_INTERVAL_SEC then return end
        lastStatRuntimeFullSeedAt = now
        Fns.RebuildMergedStatisticSeedIndex()
        Fns.SeedFromStatistics()
        Fns.ScheduleDeferredRarityMountMaxSync(2)
    end)
end

--- Schedule Statistics seed + Rarity max-merge for the current character (10s login delay; Rarity pass deferred so addon DB is up).
--- Serial token cancels superseded timers when the user swaps alts quickly or PEW fires twice.
function Fns.SchedulePerCharacterStatisticsAndRaritySync()
    perCharStatSyncSerial = perCharStatSyncSerial + 1
    local serial = perCharStatSyncSerial
    C_Timer.After(10, function()
        if serial ~= perCharStatSyncSerial then return end
        if not tryCounterReady or not Fns.EnsureDB() then return end
        Fns.RebuildMergedStatisticSeedIndex()
        Fns.SeedFromStatistics()
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
    Fns.LoadRuntimeSourceTables()

    -- Apply custom entries + disabled entries
    Fns.MergeTrackDB()

    -- Rebuild O(1) lookup indices
    Fns.BuildReverseIndices()
    Fns.RebuildMergedStatisticSeedIndex()
end

-- =====================================================================
-- INITIALIZATION
-- =====================================================================

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

    -- Set lastContainerItemID before LOOT_OPENED: hook UseContainerItem so we know which
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
    Fns.BuildReverseIndices()
    Fns.RebuildMergedStatisticSeedIndex()

    -- Merge previously discovered lockout quests from SavedVariables
    Fns.MergeDiscoveredLockoutQuests()

    -- Sync lockout state with server quest flags (prevents false increments after /reload mid-farm)
    Fns.SyncLockoutState()
    lastLockoutSyncAt = GetTime() or 0

    -- Pre-resolve mount/pet IDs for all known drop items (warmup cache for SeedFromStatistics)
    -- This ensures resolvedIDs is populated before statistics seeding runs.
    -- Delayed 5s (absolute ~T+6.5s). Time-budgeted to prevent frame spikes.
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

    -- Per-character Statistics seed + Rarity max overlay (PLAYER_ENTERING_WORLD also schedules on alt/reload).
    -- Delayed 10s/11s — after pre-resolve (+5s) warms mount/pet IDs.
    Fns.SchedulePerCharacterStatisticsAndRaritySync()
    local kSched = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
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
    Fns.RebuildMergedStatisticSeedIndex()
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

-- =====================================================================
-- CHECK TARGET DROPS (debug helper)
-- =====================================================================

---Check what collectibles drop from current target or mouseover
---Prints detailed info about NPC/Object drops, encounter mapping, and collection status
function WarbandNexus:CheckTargetDrops()
    local function msg(text) self:Print("|cff9370DB[WN-DropCheck]|r " .. text) end
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

-- =====================================================================
-- LEGACY MOUNT TRACKER IMPORT (optional cross-addon merge)
-- Reads a third-party addon global (AceDB profile.groups.mounts); only mount rows with attempts > 0.
-- Try keys: mount journal ID from C_MountJournal.GetMountFromItem(itemId), else itemId.
-- =====================================================================

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

--- Apply one Rarity-style row: max(WN mount keys, external attempts). Caller should load collections if needed.
---@return boolean changed
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

--- Persist Rarity itemID → attempts in SavedVariables so users can disable Rarity and still restore via /wn rarityrestore.
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
        self:Print("|cffff6600[WN]|r Exit combat, then run |cff00ccff/wn rarityimport|r again.")
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

---@deprecated Use SyncRarityMountAttemptsMax; kept for slash/API compatibility.
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

-- =====================================================================
-- NAMESPACE EXPORT
-- =====================================================================

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

end)()
