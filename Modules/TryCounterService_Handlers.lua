--[[
    Warband Nexus - Try Counter encounter/loot handlers (ops-030 slice)
    Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
    Wiki: ENCOUNTER_END / LOOT_READY payloads guarded via issecretvalue (Midnight 12.0).
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local E = ns.Constants and ns.Constants.EVENTS
local Fns = TC.Fns
local RT = TC.Runtime
local V = RT and RT.vars

assert(Fns and RT and V, "TryCounterService_Handlers: load TryCounterService.lua first")

local issecretvalue = issecretvalue
local GetTime = GetTime
local GetNumLootItems = GetNumLootItems
local GetLootSlotLink = GetLootSlotLink
local LootSlotHasItem = LootSlotHasItem
local UnitName = UnitName
local IsInInstance = IsInInstance
local GetInstanceInfo = GetInstanceInfo
local C_Timer = C_Timer
local C_Item = C_Item
local wipe = wipe
local tonumber = tonumber
local format = string.format

local function SendTryCounterCollectibleObtained(self, payload, sourceItemID)
    if not self or not self.SendMessage or not payload then return end
    if not payload.obtainedBy then
        local name = UnitName("player")
        if name and name ~= "" and not (issecretvalue and issecretvalue(name)) then
            payload.obtainedBy = name
        end
    end
    if payload.type and payload.id ~= nil and WarbandNexus and WarbandNexus.RegisterTryCounterLootToastForBagDedupe then
        WarbandNexus:RegisterTryCounterLootToastForBagDedupe(payload.type, payload.id, sourceItemID)
    end
    if E and E.COLLECTIBLE_OBTAINED then
        self:SendMessage(E.COLLECTIBLE_OBTAINED, payload)
    end
end

-- EVENT HANDLERS

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

    if #RT.pendingIncrementAnnounces > 0 then
        Fns.CancelIncrementAnnounceFlush()
        Fns.FlushDeferredTryCounterIncrementAnnounces()
    end

    -- Filter secrets: partial capture is still useful (e.g. have difficultyID + name but not ID).
    local safeEncID = (type(encounterID) == "number" and not (issecretvalue and issecretvalue(encounterID))) and encounterID or nil
    local safeName  = (type(encounterName) == "string" and encounterName ~= ""
        and not (issecretvalue and issecretvalue(encounterName))) and encounterName or nil
    local safeDiff  = (type(difficultyID) == "number" and not (issecretvalue and issecretvalue(difficultyID))) and difficultyID or nil
    local safeSize  = (type(groupSize) == "number" and not (issecretvalue and issecretvalue(groupSize))) and groupSize or nil

    -- Snapshot instanceID for scope (ENCOUNTER_END may leak across instances if we ignore scope).
    local _, _, _, _, _, _, _, iid = GetInstanceInfo()
    if iid and issecretvalue and issecretvalue(iid) then iid = nil end

    RT.currentEncounterCache.encounterID   = safeEncID
    RT.currentEncounterCache.encounterName = safeName
    RT.currentEncounterCache.difficultyID  = safeDiff
    RT.currentEncounterCache.groupSize     = safeSize
    RT.currentEncounterCache.startTime     = GetTime()
    RT.currentEncounterCache.instanceID    = iid

    -- Feed tooltip service so it can surface encounter context (mirrors ENCOUNTER_END path).
    if self.Tooltip and self.Tooltip._feedEncounterKill and safeName then
        -- Only npcIDs list is useful here; ENCOUNTER_END will feed the actual kill entry later.
        local npcIDs = (safeEncID and RT.encounterDB[safeEncID]) or (safeName and RT.encounterNameToNpcs[safeName]) or nil
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
    -- so the full RT.recentKills + delayed-fallback pipeline runs uniformly. success=1 (BOSS_KILL
    -- only fires on kills, never wipes).
    local diffFromCache = RT.currentEncounterCache.difficultyID
    local diffToUse = (type(diffFromCache) == "number" and diffFromCache > 0) and diffFromCache or 172
    local groupSize = RT.currentEncounterCache.groupSize or 0

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
        if RT.currentEncounterCache._graceTimer then RT.currentEncounterCache._graceTimer:Cancel() end
        RT.currentEncounterCache.encounterID = nil
        RT.currentEncounterCache.encounterName = nil
        RT.currentEncounterCache.difficultyID = nil
        RT.currentEncounterCache.groupSize = nil
        RT.currentEncounterCache.startTime = 0
        RT.currentEncounterCache.instanceID = nil
        RT.currentEncounterCache._graceTimer = nil
        return
    end

    -- Record timestamp BEFORE DB lookup. Suppresses zone-based fallback in ProcessNPCLoot
    -- for encounters not in our DB (e.g. Commander Kroluk in March on Quel'Danas) that would
    -- otherwise falsely match zone rare-mount drops in the same map region.
    V.lastEncounterEndTime = GetTime()

    -- Midnight 12.0 rescue: promote non-secret ENCOUNTER_START snapshot when END payload is secret.
    -- The cache is authoritative when startTime is fresh (< TTL) and the cached IDs complement missing
    -- END fields. We never overwrite a non-secret END value with the cached one.
    local cacheFresh = RT.currentEncounterCache.startTime > 0
        and (GetTime() - RT.currentEncounterCache.startTime) <= RT.ENCOUNTER_CACHE_TTL
    if cacheFresh then
        if (not encounterID or (issecretvalue and issecretvalue(encounterID))) and RT.currentEncounterCache.encounterID then
            encounterID = RT.currentEncounterCache.encounterID
        end
        if (not encounterName or type(encounterName) ~= "string" or encounterName == ""
            or (issecretvalue and issecretvalue(encounterName))) and RT.currentEncounterCache.encounterName then
            encounterName = RT.currentEncounterCache.encounterName
        end
        if (not difficultyID or (issecretvalue and issecretvalue(difficultyID))) and RT.currentEncounterCache.difficultyID then
            difficultyID = RT.currentEncounterCache.difficultyID
        end
    end

    local function TryNpcIDsFromEncounterStartCache()
        if not cacheFresh then return nil, nil end
        local eid = RT.currentEncounterCache.encounterID
        if type(eid) ~= "number" or (issecretvalue and issecretvalue(eid)) then return nil, nil end
        local _, _, _, _, _, _, _, curTmpl = GetInstanceInfo()
        if curTmpl and issecretvalue and issecretvalue(curTmpl) then curTmpl = nil end
        if RT.currentEncounterCache.instanceID and curTmpl and RT.currentEncounterCache.instanceID ~= curTmpl then
            return nil, nil
        end
        local list = RT.encounterDB[eid]
        if not list then return nil, nil end
        return list, eid
    end

    local npcIDs = nil
    local encounterKey = nil
    local useNameFallback = false
    local function TryResolveEncounterNPCFromLastTarget()
        -- Fallback for encounters not present in RT.encounterDB/RT.encounterNameToNpcs:
        -- if we recently had a valid tracked target GUID, attribute this kill to that NPC.
        -- This is especially important for custom tracked bosses and new patch encounters.
        if not RT.lastLootSourceGUID then return nil end
        if not RT.lastLootSourceTime or (GetTime() - RT.lastLootSourceTime) > 120 then return nil end
        local fallbackNpcID = Fns.GetNPCIDFromGUID(RT.lastLootSourceGUID)
        if not fallbackNpcID then return nil end
        if not RT.tryCounterNpcEligible[fallbackNpcID] then return nil end
        if not RT.npcDropDB[fallbackNpcID] then return nil end
        return fallbackNpcID
    end

    -- Midnight 12.0: encounterID can be secret in dungeons; cannot use as table key or tostring().
    if issecretvalue and encounterID and issecretvalue(encounterID) then
        if encounterName and not (issecretvalue and issecretvalue(encounterName)) and RT.encounterNameToNpcs[encounterName] then
            npcIDs = RT.encounterNameToNpcs[encounterName]
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
        npcIDs = RT.encounterDB[encounterID]
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
    if V.lastTryCountSourceKey == encounterKey and (now - V.lastTryCountSourceTime) < 10 then return end

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
    local statRefreshScheduled = false
    local lootlessMissNpcID = nil
    local safeDiffID = difficultyID
    if issecretvalue and safeDiffID and issecretvalue(safeDiffID) then safeDiffID = nil end
    for i = 1, #npcIDs do
        local npcID = npcIDs[i]
            if RT.tryCounterNpcEligible[npcID] and RT.npcDropDB[npcID] then
                if Fns.IsRaidOrDungeonInstance() and Fns.NpcEntryHasStatisticIds(RT.npcDropDB[npcID]) then
                    Fns.MarkNpcForRuntimeStatReseed(npcID, safeDiffID)
                    statRefreshScheduled = true
                elseif Fns.IsRaidOrDungeonInstance() and not lootlessMissNpcID
                    and not Fns.NpcEntryHasStatisticIds(RT.npcDropDB[npcID]) then
                    lootlessMissNpcID = npcID
                end
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
            RT.recentKills[syntheticGUID] = {
                npcID = npcID,
                name = safeEncounterDisplayName or "Boss",
                time = now,
                isEncounter = true,
                difficultyID = safeDiffID,
            }
            Fns.UpdateRecentKillByNpcIDCache(syntheticGUID, RT.recentKills[syntheticGUID])
            addedCount = addedCount + 1
        end
    end
    
    -- Raid/dungeon + statisticIds: read GetStatistic on boss death (loot optional / delayed).
    if statRefreshScheduled and Fns.ScheduleEncounterStatisticsRefresh then
        Fns.ScheduleEncounterStatisticsRefresh()
    end
    if lootlessMissNpcID and Fns.ScheduleEncounterLootlessMissFallback then
        Fns.ScheduleEncounterLootlessMissFallback(lootlessMissNpcID, safeDiffID, encounterKey)
    end
    
    -- DEFERRED RETRY: If a chest was opened BEFORE this encounter ended (RP/cinematic timing),
    -- ProcessNPCLoot found no drops because RT.recentKills was empty. Now that we've added
    -- the encounter entries, retry processing. Short delay ensures loot window state is stable.
    if self._pendingEncounterLoot then
        self._pendingEncounterLoot = nil
        self._pendingEncounterLootRetried = true
        local canReplay = RT.pendingEncounterLootSnapshot and (RT.pendingEncounterLootSnapshot.numLoot or 0) > 0
        C_Timer.After(0.5, function()
            self._pendingEncounterLootRetried = nil
            if canReplay and Fns.TryReplayPendingEncounterLoot then
                Fns.TryReplayPendingEncounterLoot(self)
            end
        end)
    end

    -- ENCOUNTER_START cache is consumed by this end event — clear for next pull.
    -- Grace window (300s) so late CHAT_MSG_LOOT / delayed fallbacks can still read the non-secret
    -- difficulty/name across long post-kill cinematics (Sylvanas Mythic). After that we reset to
    -- avoid leaking into subsequent pulls.
    local graceTimer = RT.currentEncounterCache._graceTimer
    if graceTimer then graceTimer:Cancel() end
    RT.currentEncounterCache._graceTimer = C_Timer.NewTimer(300, function()
        RT.currentEncounterCache.encounterID = nil
        RT.currentEncounterCache.encounterName = nil
        RT.currentEncounterCache.difficultyID = nil
        RT.currentEncounterCache.groupSize = nil
        RT.currentEncounterCache.startTime = 0
        RT.currentEncounterCache.instanceID = nil
        RT.currentEncounterCache._graceTimer = nil
    end)
end
-- LOOT READY / LOOT CLOSED HANDLERS

---LOOT_READY handler (warcraft.wiki.gg/wiki/LOOT_READY).
---Fires when looting begins, BEFORE the loot window is shown. Loot APIs valid until LOOT_CLOSED.
---This is the ONLY guaranteed loot event — LOOT_OPENED may be skipped by fast auto-loot / addons.
---We capture ALL state here (slot data + unit GUIDs) so LOOT_CLOSED can process reliably.
---@param autoloot boolean
function WarbandNexus:OnTryCounterLootReady(autoloot)
    -- A second LOOT_READY while the frame is open must not clear RT.lootSession.opened; otherwise
    -- LOOT_CLOSED treats the session as "OPENED missed" and runs the closed route again (duplicate flow logs / work).
    if not RT.lootSession.opened then
        if #RT.pendingIncrementAnnounces > 0 then
            Fns.CancelIncrementAnnounceFlush()
            Fns.FlushDeferredTryCounterIncrementAnnounces()
        end
        Fns.ResetLootSession()
    end
    RT.lootReady.numLoot = (GetNumLootItems and GetNumLootItems()) or 0
    RT.lootReady.sourceGUIDs = Fns.GetAllLootSourceGUIDs() or {}
    wipe(RT.lootReady.slotData)
    for i = 1, RT.lootReady.numLoot do
        local hasItem = LootSlotHasItem and LootSlotHasItem(i)
        local link = GetLootSlotLink and GetLootSlotLink(i)
        if link and issecretvalue and issecretvalue(link) then link = nil end
        RT.lootReady.slotData[i] = { hasItem = not not hasItem, link = link }
    end
    RT.lootReady.mouseoverGUID = Fns.SafeGetMouseoverGUID()
    RT.lootReady.targetGUID = Fns.SafeGetTargetGUID()
    RT.lootReady.npcGUID = Fns.SafeGetUnitGUID("npc")
    RT.lootReady.time = GetTime()
    -- Structural bobber/pool (zone DB) or IsFishingLoot API. Profession loot is excluded so herb/ore
    -- in fishable zones does not set wasFishing (see ClassifyLootSession GameObject-only guard).
    local apiFish = Fns.SafeIsFishingLoot()
    local structuralFish = Fns.LootSourcesLookLikeFishingOnly(RT.lootReady.sourceGUIDs)
        and Fns.IsInTrackableFishingZone()
    -- Cast TTL alone + fishable zone was counting normal mob loot when sources were empty/secret.
    -- IsFishingLoot() is authoritative at LOOT_READY: ignore target/mouseover mob corpses (common while
    -- fishing near kills); mob ground loot has IsFishingLoot() false, so we do not need the old unit guard.
    RT.lootReady.wasFishing = structuralFish
        or (apiFish and not V.isProfessionLooting)
    Fns.TryCancelLockoutFallbackFromSourceGUIDs(RT.lootReady.sourceGUIDs)
end

---LOOT_CLOSED handler (reset fishing flag, pickpocket flag, safety timer)
---processedGUIDs is NOT cleared here — it persists with TTL-based cleanup (300s).
---This prevents double-counting when the same loot source (NPC corpse, chest, container)
---is opened multiple times in quick succession (user takes partial loot, closes, reopens).
---Different loot sources get their own GUID and are counted separately.
function WarbandNexus:OnTryCounterLootClosed()
    -- Loot session resolver: one attempt decision after looting finishes (slot scan + session obtain marks).
    if RT.pendingLootSessionFinalize then
        Fns.FinalizeDeferredLootSessionOutcome(self)
    end

    -- When LOOT_OPENED was missed (fast auto-loot), use LOOT_READY captured data through
    -- the same ClassifyLootSession→RouteLootSession path. Unit GUIDs come from LOOT_READY
    -- snapshot (guaranteed valid) rather than fresh reads (may be nil by now).
    if not RT.lootSession.opened and Fns.IsAutoTryCounterEnabled() then
        local now = GetTime()
        -- After a normal OPENED session, first LOOT_CLOSED clears RT.lootReady; a second client LOOT_CLOSED
        -- would otherwise promote an empty snapshot and spam "closed -> … loot=0" (no work to do).
        local readySnapshotValid = RT.lootReady.time > 0 and (now - RT.lootReady.time) <= RT.LOOT_READY_STATE_TTL
        if readySnapshotValid then
            local incomingPrimary = RT.lootReady.sourceGUIDs and RT.lootReady.sourceGUIDs[1] or RT.lootReady.npcGUID
            local debounced = incomingPrimary and V.lastTryCountLootSourceGUID == incomingPrimary
                and (now - V.lastTryCountSourceTime) < RT.CHAT_LOOT_DEBOUNCE
            if not debounced then
                Fns.PromoteLootReadyToSession()
                Fns.RouteLootSession(self, "closed")
            end
        end
    end

    Fns.ScheduleIncrementAnnounceFlushAfterLoot(RT.CHAT_LOOT_DEBOUNCE)

    -- Full cleanup: wipe both session and ready state so nothing bleeds into next loot event.
    Fns.ResetLootSession()
    RT.lootReady.wasFishing = false
    RT.lootReady.numLoot = 0
    RT.lootReady.time = 0
    RT.lootReady.mouseoverGUID = nil
    RT.lootReady.targetGUID = nil
    RT.lootReady.npcGUID = nil
    wipe(RT.lootReady.slotData)
    wipe(RT.lootReady.sourceGUIDs)

    if RT.fishingCtx.lootWasFishing then
        RT.fishingCtx.active = false
        RT.fishingCtx.castTime = 0
        RT.fishingCtx.lootWasFishing = false
        if RT.fishingCtx.resetTimer then RT.fishingCtx.resetTimer:Cancel() RT.fishingCtx.resetTimer = nil end
    end
    V.isPickpocketing = false
    V.isProfessionLooting = false
    -- NOTE: Do NOT clear isBlockingInteractionOpen here.
    -- It is managed exclusively by PLAYER_INTERACTION_MANAGER_FRAME_SHOW/HIDE events.
    -- Clearing it on LOOT_CLOSED would incorrectly allow NPC loot processing
    -- when a bank/vendor/AH UI is still open (e.g. loot window closed while banking).
    V.lastContainerItemID = nil
    V.lastContainerItemTime = 0
    -- Do not cancel RT.fishingCtx.resetTimer on every close: that blocked the TTL from clearing stale
    -- RT.fishingCtx after non-fishing loot, so cast-window + IsFishingLoot() could count herbs as fishing.
    -- Do NOT clear lastGatherCastName/lastGatherCastTime here (overwritten on next UNIT_SPELLCAST_SENT).
    -- DO NOT clear processedGUIDs here — let TTL-based cleanup handle it (PROCESSED_GUID_TTL = 300s)
end
local function ProcessChatLootEncounterForNpc(self, itemID, npcID, killDifficulty, now, clearRecentKillGuid)
    local drops = RT.npcDropDB[npcID]
    if not drops then return false end
    local inInst = IsInInstance()
    if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
    local encDiff = Fns.ResolveEncounterDifficultyForLootGating(inInst, killDifficulty, nil)
    local trackable = Fns.FilterDropsByDifficulty(drops, encDiff)
    if #trackable == 0 then return false end

    local encForKey = Fns.GetEncounterIDForNpcID(npcID)
    V.lastTryCountSourceKey = encForKey and ("encounter_" .. tostring(encForKey)) or ("npc_" .. tostring(npcID))
    V.lastTryCountSourceTime = now

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

    if foundDrop then
        if not foundDrop.repeatable and foundDrop.type == "item" then Fns.MarkItemObtained(foundDrop.itemID) end
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(foundDrop)
        if tryKey and Fns.IsObtainOutcomeApplied(tcType, tryKey, foundDrop) then
            -- obtain chat+reset already handled (e.g. LOOT_CLOSED finalize)
        elseif tryKey then
            Fns.MarkDropObtainedThisKill(tcType, tryKey, foundDrop)
            local preResetCount = self:GetTryCount(tcType, tryKey)
            preResetCount = Fns.AdjustPreResetForDelayedReseed(preResetCount, tcType, tryKey)
            if foundDrop.repeatable then
                self:ResetTryCount(tcType, tryKey)
            end
            local cacheKey = tcType .. "\0" .. tostring(tryKey)
            RT.pendingPreResetCounts[cacheKey] = preResetCount or 0
            C_Timer.After(30, function() RT.pendingPreResetCounts[cacheKey] = nil end)
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
            Fns.MarkObtainOutcomeApplied(tcType, tryKey, foundDrop)
        end
    end

    if #missed > 0 and not Fns.ShouldUseStatisticsOnlyMiss(missed, drops.statisticIds) then
        Fns.TryCounterLootDebugDropLines(self, clearRecentKillGuid and "Chat-Encounter" or "Chat-NPC", missed)
        Fns.ProcessMissedDrops(missed, drops.statisticIds)
    end

    if clearRecentKillGuid then
        RT.recentKills[clearRecentKillGuid] = nil
        Fns.InvalidateRecentKillByNpcIDForGuid(clearRecentKillGuid)
    end
    return true
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
    if type(message) ~= "string" then return end

    if #RT.pendingIncrementAnnounces > 0 then
        Fns.BumpIncrementAnnounceFlushAfterLootChat()
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

    -- Fast bail: junk loot (e.g. zone mats) must not walk RT.recentKills / drop tables (100ms+ spikes).
    if not RT.repeatableItemDrops[itemID] then
        if RT.chatLootItemToNpc[itemID] == false then return end
        if not RT.chatLootItemToNpc[itemID] and not RT.chatLootTrackedItems[itemID] then
            local fishingMaybe = RT.fishingCtx.active
                and (now - RT.fishingCtx.castTime) <= RT.FISHING_CAST_CONTEXT_TTL
                and Fns.IsInTrackableFishingZone()
                and not Fns.CurrentUnitsHaveMobLootContext()
            if not fishingMaybe then
                return
            end
        end
    end

    -- Global debounce: any route that already ran within the window blocks all CHAT paths.
    if V.lastTryCountSourceKey and (now - V.lastTryCountSourceTime) < RT.CHAT_LOOT_DEBOUNCE then
        return
    end

    -- Loot window guard: deferred loot sessions stage on LOOT_OPENED and finalize on LOOT_CLOSED.
    -- CHAT_MSG_LOOT can fire per-item during manual loot and again after LOOT_CLOSED (wiki order).
    -- During an active/pending session only mark session obtains; full chat+reset runs once at close.
    local lootWindowActive = RT.lootSession.opened

    -- Path 1: Repeatable item obtained → reset + notification (fallback when no deferred session)
    local repDrop = RT.repeatableItemDrops[itemID]
    if repDrop then
        local tcType, tryKey = Fns.GetTryCountTypeAndKey(repDrop)
        if tryKey then
            if Fns.IsObtainOutcomeApplied(tcType, tryKey, repDrop) then
                return
            end
            if lootWindowActive or RT.pendingLootSessionFinalize or Fns.IsLootSessionPendingOrRecent() then
                Fns.TryMarkSessionObtainFromChatItem(itemID)
                return
            end
            Fns.MarkDropObtainedThisKill(tcType, tryKey, repDrop)
            local preResetCount = self:GetTryCount(tcType, tryKey)
            self:ResetTryCount(tcType, tryKey)
            V.lastTryCountSourceKey = "item_" .. tostring(itemID)
            V.lastTryCountSourceTime = now
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
            Fns.MarkObtainOutcomeApplied(tcType, tryKey, repDrop)
        end
        return
    end

    -- Paths 2-4: suppress full chat fallback when loot window is active; still mark session obtains.
    if lootWindowActive then
        Fns.TryMarkSessionObtainFromChatItem(itemID)
        return
    end

    -- Path 2: Exact item→NPC match (RT.chatLootItemToNpc built from eligible NPC + object sources)
    local npcID = RT.chatLootItemToNpc[itemID]
    if npcID == false then return end
    if npcID then
        local inInst = IsInInstance()
        if issecretvalue and inInst and issecretvalue(inInst) then inInst = nil end
        local killDiff = Fns.ResolveChatPath2KillDifficulty(npcID, itemID, inInst)
        if Fns.ProcessChatLootEncounterForNpc(self, itemID, npcID, killDiff, now, nil) then
            return
        end
    end

    -- Path 3 fast: single eligible npc owner (no RT.chatLootItemToNpc mapping — chest-only items)
    local uniqueNpc = RT.chatLootItemUniqueNpc[itemID]
    if uniqueNpc and not RT.chatLootItemToNpc[itemID] then
        local killGuid, killData = Fns.GetFreshEncounterKillForNpc(uniqueNpc)
        if killData then
            local diff = killData.difficultyID
            if issecretvalue and diff and issecretvalue(diff) then diff = nil end
            if Fns.ProcessChatLootEncounterForNpc(self, itemID, uniqueNpc, diff, now, killGuid) then
                return
            end
        end
    end

    -- Path 3 slow: recent encounter kill whose drop table contains this itemID (multi-npc / ambiguous)
    for guid, killData in pairs(RT.recentKills or {}) do
        if killData.isEncounter and killData.npcID and RT.tryCounterNpcEligible[killData.npcID] then
            local drops = RT.npcDropDB[killData.npcID]
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
                local encTtl = RT.ENCOUNTER_OBJECT_TTL or 300
                local encFresh = killData.isEncounter and killData.time
                    and (now - killData.time) <= encTtl
                if itemMatches or encFresh then
                    local diff = killData.difficultyID
                    if issecretvalue and diff and issecretvalue(diff) then diff = nil end
                    if Fns.ProcessChatLootEncounterForNpc(self, itemID, killData.npcID, diff, now, guid) then
                        return
                    end
                end
            end
        end
    end

    -- Path 4: Exact item→fishing (item must be in current zone's fishing drop table)
    if RT.fishingCtx.active and (now - RT.fishingCtx.castTime) <= RT.FISHING_CAST_CONTEXT_TTL
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
                        Fns.MarkDropObtainedThisKill(tcType, tryKey, caughtDrop)
                        local preResetCount = self:GetTryCount(tcType, tryKey)
                        self:ResetTryCount(tcType, tryKey)
                        V.lastTryCountSourceKey = "item_" .. tostring(itemID)
                        V.lastTryCountSourceTime = now
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
                V.lastTryCountSourceKey = "fishing_chat"
                V.lastTryCountSourceTime = now
                Fns.TryCounterLootDebugDropLines(self, "Chat-Fishing", trackable)
                Fns.ProcessMissedDrops(trackable, nil)
                return
            end
        end
    end
end

Fns.ProcessChatLootEncounterForNpc = ProcessChatLootEncounterForNpc
assert(WarbandNexus.OnTryCounterEncounterEnd, "TryCounterService_Handlers: encounter handler missing")
