--[[
    Warband Nexus - Try Counter loot pipeline (ops split: TryCounterService_Loot)
    ProcessNPCLoot / ProcessFishingLoot / ProcessContainerLoot + P1-P5 resolvers.
    Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime
local V = RT and RT.vars

assert(Fns and RT and V, 'TryCounterService_Loot: load TryCounterService.lua first')

local issecretvalue = issecretvalue
local GetTime = GetTime
local GetInstanceInfo = GetInstanceInfo
local IsInInstance = IsInInstance
local C_Timer = C_Timer
local format = string.format
local pairs = pairs

-- DB tables reassigned in LoadRuntimeSourceTables — always read RT.* (never snapshot at load).
local RECENT_KILL_TTL = TC.RECENT_KILL_TTL or 15
local RAID_MYTHIC_DIFFICULTY_ID = TC.RAID_MYTHIC_DIFFICULTY_ID or 16
local SANCTUM_RAID_TEMPLATE_INSTANCE_ID = TC.SANCTUM_RAID_TEMPLATE_INSTANCE_ID or 1193
local SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID = TC.SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID or 368304

--- True when npc drop array (or questStarters) contains any itemID in itemIdSet.
function Fns.NpcDropEntryContainsAnyItemSet(npcData, itemIdSet)
    if not npcData or not itemIdSet then return false end
    for i = 1, #npcData do
        local drop = npcData[i]
        if drop and drop.itemID and itemIdSet[drop.itemID] then return true end
        if drop and drop.questStarters then
            for j = 1, #drop.questStarters do
                local qs = drop.questStarters[j]
                if qs and qs.itemID and itemIdSet[qs.itemID] then return true end
            end
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
    for npcId, dt in pairs(RT.npcDropDB) do
        if RT.tryCounterNpcEligible[npcId] and type(dt) == "table" and Fns.NpcDropEntryContainsAnyItemSet(dt, itemIdSet) then
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
                if nid and RT.tryCounterNpcEligible[nid] and RT.npcDropDB[nid] then
                    if Fns.NpcDropEntryContainsAnyItemSet(RT.npcDropDB[nid], itemIdSet) then
                        ok = true
                    end
                end
                if not ok and candidateNpcIds and #candidateNpcIds > 0 and (g:match("^Creature") or g:match("^Vehicle")) then
                    for c = 1, #candidateNpcIds do
                        local npcId = candidateNpcIds[c]
                        local needle = "-" .. tostring(npcId) .. "-"
                        if g:find(needle, 1, true) and RT.npcDropDB[npcId] and Fns.NpcDropEntryContainsAnyItemSet(RT.npcDropDB[npcId], itemIdSet) then
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

--- Mark corpse/source GUIDs after a try is consumed (deferred open must not mark — LOOT_CLOSED/finalize marks).
function Fns.MarkLootSourceGuidsProcessed(dedupGUID, allSourceGUIDs, targetGUID)
    local now = GetTime()
    if dedupGUID and type(dedupGUID) == "string" and not dedupGUID:match("^zone_") then
        RT.processedGUIDs[dedupGUID] = now
    end
    if allSourceGUIDs then
        for i = 1, #allSourceGUIDs do
            local srcGUID = allSourceGUIDs[i]
            if srcGUID and not RT.processedGUIDs[srcGUID] then
                RT.processedGUIDs[srcGUID] = now
            end
        end
    end
    if targetGUID and not RT.processedGUIDs[targetGUID] then
        RT.processedGUIDs[targetGUID] = now
    end
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
        if type(srcGUID) ~= "string" or (issecretvalue and issecretvalue(srcGUID)) then
            srcGUID = nil
        end
        if srcGUID and srcGUID:match("^GameObject") then ctx.sourceIsGameObject = true end
        if srcGUID and RT.processedGUIDs[srcGUID] then
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
        if type(srcGUID) == "string" and not (issecretvalue and issecretvalue(srcGUID))
            and not RT.processedGUIDs[srcGUID] then
            ctx.dedupGUID = srcGUID
            break
        end
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
    local sources = RT.lootSession.sourceGUIDs

    local candidates = {
        RT.lootSession.npcGUID,
        RT.lootSession.mouseoverGUID,
        RT.lootSession.targetGUID,
    }
    if RT.lastLootSourceGUID and (GetTime() - RT.lastLootSourceTime) <= (RT.LAST_LOOT_SOURCE_TTL or 3) then
        candidates[#candidates + 1] = RT.lastLootSourceGUID
    end
    for i = 1, #candidates do
        local guid = candidates[i]
        if guid and (lootIsEmpty or not RT.processedGUIDs[guid]) then
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
    if not next(RT.zoneDropDB) then return end
    if ctx.sourceIsGameObject or inInstance then return end

    if (GetTime() - V.lastEncounterEndTime) < RECENT_KILL_TTL then return end

    local mapID = Fns.GetSafeMapID()
    while mapID and mapID > 0 do
        local zData = RT.zoneDropDB[mapID]
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
    if nid and RT.tryCounterNpcEligible[nid] and RT.npcDropDB[nid] then return false end
    local oid = Fns.GetObjectIDFromGUID(guid)
    if oid and RT.objectDropDB[oid] then return false end
    return true
end

function Fns.ResolveFromRecentKills(ctx, inInstance)
    if ctx.drops then return end
    local now = GetTime()
    local bestGuid, bestKill = nil, nil
    for guid, killData in pairs(RT.recentKills) do
        if not RT.processedGUIDs[guid] and killData.isEncounter then
            local alive = (now - killData.time < RT.ENCOUNTER_OBJECT_TTL)
            -- Allow linking encounter kill when: no loot GUID yet, chest-shaped sources, or P1's
            -- first unprocessed GUID is not a row we already resolve (Player tokens / random mobs).
            local canMatch = (not ctx.dedupGUID) or ctx.sourceIsGameObject
                or Fns.GuidAllowsEncounterRecentKillFallback(ctx.dedupGUID)
            if alive and canMatch then
                local nid = killData.npcID
                if nid and RT.tryCounterNpcEligible[nid] and RT.npcDropDB[nid] then
                    if not bestKill or killData.time > bestKill.time then
                        bestKill = killData
                        bestGuid = guid
                    end
                end
            end
        end
    end
    if bestGuid and bestKill then
        ctx.drops = RT.npcDropDB[bestKill.npcID]
        ctx.matchedNpcID = bestKill.npcID
        ctx.dedupGUID = bestGuid
    end
end

function Fns.ResolveFromEncounterCache(ctx, inInstance)
    if ctx.drops then return end
    if not inInstance then return end
    local encCache = RT.currentEncounterCache
    if not encCache or encCache.startTime == 0 then return end
    if (GetTime() - encCache.startTime) > (RT.ENCOUNTER_CACHE_TTL or 1200) then return end

    -- Try encounter ID path first (authoritative), then name path.
    local npcIDs = nil
    local dedupTag = nil
    if encCache.encounterID and RT.encounterDB[encCache.encounterID] then
        npcIDs = RT.encounterDB[encCache.encounterID]
        dedupTag = "enc_cache_" .. tostring(encCache.encounterID)
    elseif encCache.encounterName and RT.encounterNameToNpcs[encCache.encounterName] then
        npcIDs = RT.encounterNameToNpcs[encCache.encounterName]
        dedupTag = "enc_cache_name_" .. encCache.encounterName
    end
    if not npcIDs or #npcIDs == 0 then return end

    -- Pick the first eligible NPC that has a drop table. Multi-NPC encounters (e.g. council fights)
    -- share the same encounterID, so first-eligible is correct for attribution.
    for i = 1, #npcIDs do
        local nid = npcIDs[i]
        if nid and RT.tryCounterNpcEligible[nid] and RT.npcDropDB[nid] then
            ctx.drops = RT.npcDropDB[nid]
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
            if not RT.processedGUIDs[g] then
                firstGO = g
                break
            end
        end
    end
    if not firstGO then return end
    local row = RT.objectDropDB and RT.objectDropDB[SYLVANAS_MYTHIC_CHEST_OBJECT_ROW_ID]
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
    local entry = RT.recentKillByNpcID[npcID]
    if not entry or killData.time > entry.killData.time then
        RT.recentKillByNpcID[npcID] = { guid = guid, killData = killData }
    end
end

function Fns.InvalidateRecentKillByNpcIDForGuid(guid)
    if not guid then return end
    for npcID, entry in pairs(RT.recentKillByNpcID) do
        if entry.guid == guid then
            RT.recentKillByNpcID[npcID] = nil
        end
    end
end

function Fns.GetFreshEncounterKillForNpc(npcId)
    if not npcId then return nil, nil end
    local entry = RT.recentKillByNpcID[npcId]
    if not entry then return nil, nil end
    local guid, kd = entry.guid, entry.killData
    if not guid or not kd or RT.recentKills[guid] ~= kd then
        RT.recentKillByNpcID[npcId] = nil
        return nil, nil
    end
    if (GetTime() - kd.time) >= RT.ENCOUNTER_OBJECT_TTL then
        RT.recentKillByNpcID[npcId] = nil
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
    for _, killData in pairs(RT.recentKills or {}) do
        if killData.isEncounter and killData.difficultyID
            and not (issecretvalue and issecretvalue(killData.difficultyID)) then
            if killData.npcID == npcID then
                return killData.difficultyID
            end
            if inInst and itemSet and killData.npcID and RT.npcDropDB[killData.npcID]
                and RT.tryCounterNpcEligible[killData.npcID]
                and (tNow - killData.time) < RT.ENCOUNTER_OBJECT_TTL then
                if Fns.NpcDropEntryContainsAnyItemSet(RT.npcDropDB[killData.npcID], itemSet) and killData.time > bestT then
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
                if nid and nid ~= bossNpcId and RT.tryCounterNpcEligible[nid] and RT.npcDropDB[nid] then
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
    for guid, kd in pairs(RT.recentKills) do
        if kd and kd.isEncounter and kd.npcID == npcId then
            RT.recentKills[guid] = nil
            Fns.InvalidateRecentKillByNpcIDForGuid(guid)
        end
    end
    RT.recentKillByNpcID[npcId] = nil
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
    if not RT.instanceBossSlotOutcomeRules or #RT.instanceBossSlotOutcomeRules == 0 then return false end
    lootRouteSource = lootRouteSource or "opened"

    local _, instType, diff, _, _, _, _, tmpl = GetInstanceInfo()
    if RT.tryCounterSelfTest and RT.tryCounterSelfTest.slotInstance then
        instType = RT.tryCounterSelfTest.slotInstance.instanceType or instType
        diff = RT.tryCounterSelfTest.slotInstance.difficulty or diff
        tmpl = RT.tryCounterSelfTest.slotInstance.templateInstanceID or tmpl
    end
    if issecretvalue and instType and issecretvalue(instType) then instType = nil end
    if issecretvalue and diff and issecretvalue(diff) then diff = nil end
    if issecretvalue and tmpl and issecretvalue(tmpl) then tmpl = nil end

    local bestRule, bestKillTime, bestKillData = nil, 0, nil
    for ri = 1, #RT.instanceBossSlotOutcomeRules do
        local r = RT.instanceBossSlotOutcomeRules[ri]
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

    local sources = RT.lootSession.sourceGUIDs or {}
    if Fns.LootSourcesHaveForeignEligibleCreature(sources, bestRule.bossNpcID) then return false end

    local drops = RT.npcDropDB[bestRule.bossNpcID]
    if not drops then return false end

    local killData = bestKillData

    local recentKillDiff = killData.difficultyID
    if issecretvalue and recentKillDiff and issecretvalue(recentKillDiff) then recentKillDiff = nil end
    local encounterDiffID = Fns.ResolveEncounterDifficultyForLootGating(true, recentKillDiff, diff)
    local trackable = tryCounterSelfTestBossTrackable and tryCounterSelfTestBossTrackable[bestRule.bossNpcID]
        or Fns.FilterDropsByDifficulty(drops, encounterDiffID)
    if #trackable == 0 then return false end

    local numLoot = RT.lootSession.numLoot or 0
    if numLoot < 1 then return false end

    local encounterIDForKey = Fns.GetEncounterIDForNpcID(bestRule.bossNpcID) or bestRule.encounterJournalID
    local slotOutcomeSourceKey = encounterIDForKey
        and ("encounter_" .. tostring(encounterIDForKey))
        or ("inst_slot_" .. tostring(bestRule.bossNpcID))

    if lootRouteSource == "opened" then
        if not Fns.LootSlotsHaveReadableItemLink(RT.lootSession.slotData, numLoot) then
            local foundEarly = Fns.ScanLootForItems(trackable, numLoot, RT.lootSession.slotData)
            local anyEarly = false
            for ti = 1, #trackable do
                if trackable[ti] and foundEarly[trackable[ti].itemID] then anyEarly = true; break end
            end
            -- Miss on chest loot: mount absent but slots have gear (links may stay secret until close).
            if not anyEarly and not Fns.LootSlotsHaveItemsPresent(RT.lootSession.slotData, numLoot) then
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

    local baseline = Fns.CaptureTryCountBaselines(trackable)
    local earlyMissApplied = Fns.ApplyEarlyLootAttemptIncrement({
        kind = "slot_boss",
        trackable = trackable,
        drops = drops,
        slotOutcomeSourceKey = slotOutcomeSourceKey,
        slotBossNpcID = bestRule.bossNpcID,
        allSourceGUIDs = sources,
    })
    local found = Fns.BuildNpcLootFoundMap(trackable, numLoot, RT.lootSession.slotData)
    Fns.ApplySlotBossLootOutcomes(self, {
        trackable = trackable,
        found = found,
        drops = drops,
        slotOutcomeSourceKey = slotOutcomeSourceKey,
        slotBossNpcID = bestRule.bossNpcID,
        allSourceGUIDs = sources,
        baselineTryCounts = baseline,
        earlyMissApplied = earlyMissApplied,
    })
    return true
end

-- ProcessNPCLoot — orchestrator: P1→P2→P3→P4, first match wins, exact IDs only.

function Fns.GetEncounterIDForNpcID(npcID)
    if not npcID then return nil end
    return RT.npcIDToEncounterID[npcID]
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
    local allSourceGUIDs = RT.lootSession.sourceGUIDs
    local numLoot = RT.lootSession.numLoot

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

    -- P4: Encounter RT.recentKills (instance boss bookkeeping)
    if not ctx.drops then
        Fns.ResolveFromRecentKills(ctx, inInstance)
    end

    -- P5: ENCOUNTER_START cache (Midnight 12.0 rescue when all GUIDs are secret).
    -- Only triggers inside an instance; start-time snapshot supplies non-secret IDs
    -- that RT.encounterDB / encounterNameToNpcs can resolve to a drop table.
    if not ctx.drops then
        Fns.ResolveFromEncounterCache(ctx, inInstance)
    end

    if not ctx.drops then
        Fns.ResolveSylvanasMythicChestFromRaidGameObject(ctx, inInstance, allSourceGUIDs)
    end

    if not ctx.drops then
        if inInstance and not self._pendingEncounterLootRetried then
            self._pendingEncounterLoot = true
            if (RT.lootSession.numLoot or 0) > 0 then
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
    if matchedNpcID and RT.lockoutQuestsDB[matchedNpcID] then
        Fns.MarkLockoutLootTouched(matchedNpcID)
        Fns.CancelLockoutQuestFallbackForNpc(matchedNpcID)
    end

    -- Auto-discovery: if this NPC has drops but no lockout quest, schedule discovery
    if matchedNpcID and not RT.lockoutQuestsDB[matchedNpcID] and (RT.npcDropDB[matchedNpcID] or (ns.CollectibleSourceDB and ns.CollectibleSourceDB.rares and ns.CollectibleSourceDB.rares[matchedNpcID])) then
        Fns.ScheduleLockoutDiscovery(matchedNpcID)
    end

    -- Encounter RT.recentKills cleanup runs before filtering (even when #trackable == 0) so multi-boss
    -- raids do not leak encounter entries into unrelated loot events.

    -- Resolve encounter difficulty BEFORE cleanup deletes RT.recentKills.
    local recentKillDiff = nil
    if dedupGUID then
        local killEntry = RT.recentKills[dedupGUID]
        if killEntry and killEntry.difficultyID then recentKillDiff = killEntry.difficultyID end
    end
    if not recentKillDiff and matchedNpcID then
        for _, killData in pairs(RT.recentKills) do
            if killData.isEncounter and killData.npcID == matchedNpcID and killData.difficultyID then
                recentKillDiff = killData.difficultyID
                break
            end
        end
    end
    -- GameObject chests (e.g. Sylvanas's Chest): P1 matches RT.objectDropDB first, so matchedNpcID is nil
    -- and the encounter-kill loop above never runs. Mythic-gated boss rows then fail-closed with nil
    -- encounterDiffID. Reuse difficulty from the freshest recent encounter kill whose NPC table lists
    -- any of this object's loot itemIDs (same boss session).
    if not recentKillDiff and inInstance and lastMatchedObjectID and RT.objectDropDB[lastMatchedObjectID] then
        local objDrops = RT.objectDropDB[lastMatchedObjectID]
        local itemSet = Fns.BuildItemIdSetFromDropList(objDrops)
        local tNow = GetTime()
        local bestT = 0
        for _, killData in pairs(RT.recentKills) do
            if killData.isEncounter and killData.npcID
                and RT.tryCounterNpcEligible[killData.npcID] and RT.npcDropDB[killData.npcID]
                and (tNow - killData.time) < RT.ENCOUNTER_OBJECT_TTL then
                if Fns.NpcDropEntryContainsAnyItemSet(RT.npcDropDB[killData.npcID], itemSet) and killData.time > bestT then
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
        matchedEncounterID = RT.npcIDToEncounterID[matchedNpcID]
        if matchedEncounterID then
            matchedEncounterNpcs = RT.encounterDB[matchedEncounterID]
        end
    end

    -- Clean up encounter entries in RT.recentKills for ALL NPCs in this encounter.
    if matchedNpcID then
        if matchedEncounterNpcs then
            local npcSet = {}
            for i = 1, #matchedEncounterNpcs do
                local nid = matchedEncounterNpcs[i]
                npcSet[nid] = true
            end
            for guid, killData in pairs(RT.recentKills) do
                if killData.isEncounter and npcSet[killData.npcID] then
                    RT.recentKills[guid] = nil
                    Fns.InvalidateRecentKillByNpcIDForGuid(guid)
                end
            end
        else
            for guid, killData in pairs(RT.recentKills) do
                if killData.isEncounter and killData.npcID == matchedNpcID then
                    RT.recentKills[guid] = nil
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
            local currentLabel = RT.DIFFICULTY_ID_TO_LABELS[encounterDiffID] or tostring(encounterDiffID or "?")
            local skipDedupKey = (matchedEncounterID and ("diffskip_enc_" .. tostring(matchedEncounterID)))
                or (matchedNpcID and ("diffskip_npc_" .. tostring(matchedNpcID)))
                or ("diffskip_item_" .. tostring(diffSkipped.drop and diffSkipped.drop.itemID or 0))
            local tSkip = GetTime()
            if skipDedupKey ~= V.lastDifficultySkipChatKey or (tSkip - (V.lastDifficultySkipChatTime or 0)) >= RT.SKIP_CHAT_DEDUP_SEC then
                V.lastDifficultySkipChatKey = skipDedupKey
                V.lastDifficultySkipChatTime = tSkip
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
    -- Baseline before kill +1; closed route (auto-loot) mirrors LOOT_OPENED early miss.
    local baselineTryCounts = Fns.CaptureTryCountBaselines(trackable)
    local earlyMissApplied = false
    if lootRouteSource == "closed" then
        earlyMissApplied = Fns.ApplyEarlyLootAttemptIncrement({
            kind = "npc",
            matchedNpcID = matchedNpcID,
            matchedEncounterID = matchedEncounterID,
            lastMatchedObjectID = lastMatchedObjectID,
            dedupGUID = dedupGUID,
            drops = drops,
            trackable = trackable,
            allSourceGUIDs = allSourceGUIDs,
        })
    end
    local found = Fns.BuildNpcLootFoundMap(trackable, RT.lootSession.numLoot, RT.lootSession.slotData)

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
        earlyMissApplied = earlyMissApplied,
    })
end

---Process loot from fishing.
---Requires fishing evidence (IsFishingLoot API, known bobber, or recent fishing cast).
---One confirmed fishing loot open in a trackable zone = one attempt for zone fishing drops.
function WarbandNexus:ProcessFishingLoot(lootRouteSource)
    lootRouteSource = lootRouteSource or "opened"
    -- Gathering/profession loot windows must never count zone fishing tries (e.g. herb in Voidstorm).
    if V.isProfessionLooting then return end
    if not Fns.LootSessionHasFishingEvidence(RT.lootSession.sourceGUIDs) then return end
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

    RT.fishingCtx.lootWasFishing = true

    if Fns.ShouldDeferLootOutcomeUntilClose(lootRouteSource) then
        Fns.StageDeferredLootSession({ kind = "fishing", trackable = trackable })
        return
    end

    local found = Fns.BuildNpcLootFoundMap(trackable, RT.lootSession.numLoot, RT.lootSession.slotData)
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
    if containerItemID and RT.containerDropDB[containerItemID] then
        local containerData = RT.containerDropDB[containerItemID]
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

        local found = Fns.BuildNpcLootFoundMap(trackable, RT.lootSession.numLoot, RT.lootSession.slotData)
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
    for _, containerData in pairs(RT.containerDropDB) do
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
