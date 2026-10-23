--[[
    Warband Nexus - Try Counter instance entry (split from TryCounterService.lua, 2026-10-22)
    Zone-in drop hint, Encounter Journal lookups and OnTryCounterInstanceEntry (per-character
    statistics schedule, encounter cache reset). Loaded after TryCounterService.lua; uses
    ns.TryCounter.Runtime + TC.Fns. DB tables are read as RT.* at the use site.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime
local V = RT and RT.vars

assert(Fns and RT and V and RT.tryCounterInstanceDiffCache and RT.guidNpcIDCache and RT.guidObjectIDCache,
    "TryCounterService_Instance: load TryCounterService.lua first")

-- Owned by TryCounterService.lua (separate chunk); shared through the Runtime table.
local tryCounterInstanceDiffCache = RT.tryCounterInstanceDiffCache

local pairs = pairs
local C_Map = C_Map
local C_Timer = C_Timer
local InCombatLockdown = InCombatLockdown
local IsInInstance = IsInInstance
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

local tryCounterInstanceEntryAnnounced = {}
local tryCounterJournalIDByTemplateInstID = {
    [2097] = 1178, -- Operation: Mechagon (JournalInstance.ID)
}
local JOURNAL_INSTANCE_TEMPLATE_SCAN_MAX = 2600

-- INSTANCE ENTRY (Encounter Journal helpers kept for debug / TryCounterShowInstanceDrops if invoked manually)
-- Full boss-by-boss chat dump on zone-in was removed (spam). On entry: optional [WN-Drops] lines if the
-- instance has any Try Counter mount in DB (wrong difficulty shows red); else a one-line hint only when
-- at least one drop is trackable on the current difficulty — see TryCounterAnnounceCollectibleMountsOnInstanceEntry.

local function TryCounterAnnounceCollectibleMountsOnInstanceEntry(WN)
    if not WN or not WN.Print then return end
    local autoEnabled = Fns.IsAutoTryCounterEnabled()
    if autoEnabled and Fns.IsTryCounterChatHidden() then return end
    local inI, it = IsInInstance()
    if issecretvalue and issecretvalue(inI) then return end
    if not inI then return end
    if issecretvalue and issecretvalue(it) then it = nil end
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
            local npcIDs = RT.encounterDB[dungeonEncID]
            if npcIDs then
                for ni = 1, #npcIDs do
                    local npcID = npcIDs[ni]
                    local npcDrops = RT.npcDropDB[npcID]
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
            -- Routed like the TryCounterShowInstanceDrops lines in the sibling branch: both belong to
            -- the same instance-entry announce and must not split across two chat tabs.
            Fns.TryChat("|cff9370DB[WN-Counter]|r " .. msg)
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
    if issecretvalue and issecretvalue(journalEncID) then journalEncID = nil end
    if issecretvalue and issecretvalue(dungeonEncID) then dungeonEncID = nil end
    -- Fallback only when ByIndex omitted dungeonEncounterID; pcall must use 6×_ so dex = 7th return (not journalInstanceID).
    if (not dungeonEncID or type(dungeonEncID) ~= "number" or dungeonEncID <= 0)
        and EJ_GetEncounterInfo and journalEncID and type(journalEncID) == "number" and journalEncID > 0 then
        -- Returns: name, desc, journalEncounterID, rootSectionID, link, journalInstanceID, dungeonEncounterID, instanceID
        local okInfo, _, _, _, _, _, _, dex = pcall(EJ_GetEncounterInfo, journalEncID)
        if okInfo and not (issecretvalue and issecretvalue(dex)) and type(dex) == "number" and dex > 0 then
            dungeonEncID = dex
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
        if ok and not (issecretvalue and issecretvalue(ejName)) and ejName and type(ejName) == "string" and ejName ~= "" then
            sawNamedInstance = true
        end
        if ok and not (issecretvalue and issecretvalue(mapTpl)) and mapTpl and type(mapTpl) == "number" and mapTpl == templateInstID then
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
        if not (issecretvalue and issecretvalue(mapID)) and mapID then
            jid = EJ_GetInstanceForMap(mapID)
            if issecretvalue and issecretvalue(jid) then jid = nil end
        end
    end
    if jid and jid ~= 0 then return jid end

    local inInst = IsInInstance()
    if issecretvalue and issecretvalue(inInst) then inInst = nil end
    if inInst and EJ_GetInstanceInfo then
        local _, _, _, _, _, _, _, templateInstID = GetInstanceInfo()
        if not (issecretvalue and issecretvalue(templateInstID)) and templateInstID and type(templateInstID) == "number" and templateInstID > 0 then
            jid = Fns.TryCounterFindJournalInstanceIDByTemplateInstanceID(templateInstID)
            if jid and jid ~= 0 then return jid end
        end
        -- If UiMap was nil but GetSafeMapID still has a floor id, only accept it when EJ template matches GetInstanceInfo (avoids SW cache).
        if EJ_GetInstanceForMap and type(Fns.GetSafeMapID) == "function" then
            local safeUm = Fns.GetSafeMapID()
            if not (issecretvalue and issecretvalue(safeUm)) and safeUm then
                local j2 = EJ_GetInstanceForMap(safeUm)
                if issecretvalue and issecretvalue(j2) then j2 = nil end
                if j2 and j2 ~= 0 and templateInstID and type(templateInstID) == "number" and templateInstID > 0 then
                    local okJ, _, _, _, _, _, _, _, _, _, ejTpl = pcall(EJ_GetInstanceInfo, j2)
                    if okJ and not (issecretvalue and issecretvalue(ejTpl))
                        and type(ejTpl) == "number" and ejTpl == templateInstID then
                        return j2
                    end
                end
            end
        end
    end

    if EJ_GetCurrentInstance then
        jid = EJ_GetCurrentInstance()
        if issecretvalue and issecretvalue(jid) then jid = nil end
        if jid and jid ~= 0 then return jid end
    end

    if jid == 0 then jid = nil end
    return jid
end

---PLAYER_ENTERING_WORLD handler (instance difficulty cache, fishing reset, statistics sync)
function WarbandNexus:OnTryCounterInstanceEntry(event, isInitialLogin, isReloadingUi)
    -- Statistics + Rarity: re-sync when character changes or UI reload (not every zone hop).
    if Fns.IsTryCounterReady() then
        local k = Fns.StatisticSnapshotStorageKey()
        if k then
            if k ~= V.lastSyncScheduleCharKey or isReloadingUi then
                V.lastSyncScheduleCharKey = k
                Fns.SchedulePerCharacterStatisticsAndRaritySync()
            end
        end
    end

    if not Fns.IsAutoTryCounterEnabled() then return end

    -- Refresh safe map cache on zone transitions (login, reload, instance entry/exit)
    Fns.GetSafeMapID()

    local inInstance, instanceType = IsInInstance()
    -- Midnight: IsInInstance() can return a secret value mid-transition (post-encounter cinematics,
    -- in-instance phase hops). The block below is destructive - it wipes every pending encounter kill.
    -- "Unknown" must not be treated as "left the instance", or a boss killed before a long cutscene
    -- loses its recentKills row and its chest can no longer be attributed (Sylvanas Mythic).
    if issecretvalue and issecretvalue(inInstance) then return end
    if issecretvalue and issecretvalue(instanceType) then instanceType = nil end
    if not inInstance then
        tryCounterInstanceDiffCache.instanceID = nil
        tryCounterInstanceDiffCache.difficultyID = nil
        -- ENCOUNTER_START cache is instance-scoped — clear on exit.
        if RT.currentEncounterCache._graceTimer then RT.currentEncounterCache._graceTimer:Cancel() end
        RT.currentEncounterCache.encounterID = nil
        RT.currentEncounterCache.encounterName = nil
        RT.currentEncounterCache.difficultyID = nil
        RT.currentEncounterCache.groupSize = nil
        RT.currentEncounterCache.startTime = 0
        RT.currentEncounterCache.instanceID = nil
        RT.currentEncounterCache.consumed = false
        RT.currentEncounterCache._graceTimer = nil
        for guid, data in pairs(RT.recentKills) do
            if data.isEncounter then
                RT.recentKills[guid] = nil
                -- Purge cached GUID parses for encounter GUIDs no longer relevant.
                RT.guidNpcIDCache[guid] = nil
                RT.guidObjectIDCache[guid] = nil
            end
        end
        wipe(RT.recentKillByNpcID)
        return
    end

    -- Try counter: snapshot instance difficulty at entry (stable vs wrong ENCOUNTER_END args).
    tryCounterInstanceDiffCache.instanceID = nil
    tryCounterInstanceDiffCache.difficultyID = nil
    if instanceType == "party" or instanceType == "raid" then
        local _, _, diffID, _, _, _, _, instanceID = GetInstanceInfo()
        local sid = instanceID
        if issecretvalue and issecretvalue(sid) then sid = nil end
        local gi = diffID
        if issecretvalue and issecretvalue(gi) then gi = nil end
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
    RT.fishingCtx.active = false
    RT.fishingCtx.castTime = 0
    if RT.fishingCtx.resetTimer then RT.fishingCtx.resetTimer:Cancel() RT.fishingCtx.resetTimer = nil end
end
