--[[
    Warband Nexus - Try Counter diagnostics (split from TryCounterService.lua, 2026-10-22)
    Loot debug log helpers, instance probe / drop listing, statistic bucket audit, debug report and
    CheckTargetDrops. Loaded after TryCounterService.lua; uses ns.TryCounter.Runtime + TC.Fns.
    DB tables are reassigned by LoadRuntimeSourceTables, so they are read as RT.* at the use site.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local TC = ns.TryCounter or {}
local Fns = TC.Fns
local RT = TC.Runtime

assert(Fns and RT, "TryCounterService_Debug: load TryCounterService.lua first")

local GetItemInfo = C_Item.GetItemInfo
local GetNumLootItems = GetNumLootItems
local tonumber = tonumber
local pairs = pairs
local format = string.format
local C_MountJournal = C_MountJournal
local C_PetJournal = C_PetJournal
local PlayerHasToy = PlayerHasToy
local C_Map = C_Map
local C_Timer = C_Timer
local IsInInstance = IsInInstance
local issecretvalue = issecretvalue  -- nil pre-12.0, function in 12.0+

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

--- Trace the attempt-announce chain (branch taken, deltas, sink) under the loot debug flag.
--- Counts incrementing while no "N attempts" line reaches chat is otherwise invisible: every
--- stage returns silently, so field reports could only say "it does not print".
function Fns.TryCounterAnnounceDebug(fmt, ...)
    local addon = WarbandNexus
    if not Fns.IsTryCounterLootDebugEnabled(addon) then return end
    local n = select("#", ...)
    local msg = (n > 0) and format(tostring(fmt), ...) or tostring(fmt)
    addon:Print("|cff9370DB[WN-TC]|r |cff88ccffannounce: " .. msg .. "|r")
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
                local npcIDs = RT.encounterDB[dungeonEncID]
                if npcIDs then
                    hadDbBoss = true
                    local printedMountLine = false
                    for ni = 1, #npcIDs do
                        local npcID = npcIDs[ni]
                        local npcDrops = RT.npcDropDB[npcID]
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
                local npcIDs = dungeonEncID and RT.encounterDB[dungeonEncID]
                if npcIDs then
                    local encounterDrops = {}
                    local seenItems = {}
                    local dropDiffMap = {}
                    for i = 1, #npcIDs do
                        local npcID = npcIDs[i]
                        local npcDrops = RT.npcDropDB[npcID]
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
            local inTW = (encDiff == 24 or encDiff == 33 or encDiff == 151)

            local Ltc = ns.L
            local printed = 0
            local omitted = 0

            for i = 1, #dropsToShow do
                local entry = dropsToShow[i]
                for j = 1, #entry.drops do
                    local drop = entry.drops[j]
                    local reqDiff = entry.diffMap and entry.diffMap[drop.itemID]
                    if reqDiff == "Timewalking" and not inTW then
                        -- Suppress Timewalking drop when not in a Timewalking instance
                    elseif maxLines and printed >= maxLines then
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

                    -- Third segment: accepted difficulties, current one greened; em dash when ungated.
                    local diffSegment = Fns.FormatDropDifficultySegment(reqDiff, encDiff)

                        -- Drop the " - " separators around the bare em dash, or a gate-less drop reads
                        -- "[Item] - — - (4 attempts)" -- three dash glyphs in a row.
                        local sep = reqDiff and " - " or " "
                        Fns.TryChat("|cff9370DB[WN-Drops]|r " .. itemLink .. sep .. diffSegment .. sep .. status)
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

---Debug: list merged Statistics-ID buckets for mounts (cross-difficulty / cross-NPC merge). Requires profile.debugMode.
function WarbandNexus:TryCounterAuditMountStatisticBuckets()
    if not self.db or not self.db.profile or not self.db.profile.debugMode then
        if self.Print then
            self:Print("|cffff6600[WN]|r Enable debug first: |cff00ccff/wn debug|r")
        end
        return
    end
    if not Fns.IsTryCounterReady() then
        if self.Print then
            self:Print("|cffff6600[WN]|r Try counter not ready yet.")
        end
        return
    end
    Fns.EnsureMergedStatisticSeedIndex()
    local n = 0
    local multi = 0
    for i = 1, #RT.mergedStatSeedGroupList do
        local b = RT.mergedStatSeedGroupList[i]
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
    local raidLabel = (raidDiff and RT.DIFFICULTY_ID_TO_LABELS[raidDiff]) or "(unknown)"
    local dungeonLabel = (dungeonDiff and RT.DIFFICULTY_ID_TO_LABELS[dungeonDiff]) or "(unknown)"
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
                    local inNpc = nid and RT.npcDropDB[nid] and "yes" or "no"
                    local inObj = oid and RT.objectDropDB[oid] and "yes" or "no"
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
        msg("  npcID=" .. safeStr(nid) .. " inNpcDB=" .. (nid and RT.npcDropDB[nid] and "yes" or "no") .. " objectID=" .. safeStr(oid) .. " inObjDB=" .. (oid and RT.objectDropDB[oid] and "yes" or "no"))
    end

    -- 5. recentKills (sample)
    local count = 0
    for guid, data in pairs(RT.recentKills) do
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
    msg("Map: mapID=" .. safeStr(mapID) .. " zoneDropDB[mapID]=" .. (mapID and RT.zoneDropDB[mapID] and "yes" or "no"))
    if mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(mapID)
        local parent = info and info.parentMapID
        if parent then
            msg("  parentMapID=" .. tostring(parent) .. " zoneDropDB[parent]=" .. (RT.zoneDropDB[parent] and "yes" or "no"))
        end
    end

    -- 7. Statistics (sample)
    local sampleStatIds = {}
    for npcID, data in pairs(RT.npcDropDB) do
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
    if type(rawUnitName) == "string"
        and not (issecretvalue and issecretvalue(rawUnitName)) and rawUnitName ~= "" then
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
        
        local drops = RT.npcDropDB[npcID]
        if drops then
            msg("|cff00ff00✓ This NPC has tracked drops!|r")
            msg("")
            
            -- Check if it's a boss with encounter mapping
            local encounterIDs = {}
            for encID, npcList in pairs(RT.encounterDB or {}) do
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
        
        local drops = RT.objectDropDB[objectID]
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
