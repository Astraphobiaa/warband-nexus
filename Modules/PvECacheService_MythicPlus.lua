--[[
    Warband Nexus - PvE Cache Service: MythicPlus
    Keystone refresh, affixes, best runs, dungeon scores, run history,
    cross-character keystone synergy / reroll recommendations.
    Split from PvECacheService.lua; shared locals come from ns.PvECacheService._bind.
]]

local ADDON_NAME, ns = ...

local B = assert(ns.PvECacheService and ns.PvECacheService._bind, "PvECacheService_MythicPlus: load Modules/PvECacheService.lua first")
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local Utilities = B.Utilities
local Constants = B.Constants
local PvECacheUserDebug = B.PvECacheUserDebug
local ShouldLogPvECacheDiag = B.ShouldLogPvECacheDiag
local CanonicalizePvEKey = B.CanonicalizePvEKey
local GetSessionCanonicalPvEKey = B.GetSessionCanonicalPvEKey
local ApplyMythicPlusSeasonRollover = B.ApplyMythicPlusSeasonRollover
local DungeonScoresBucketHasProgress = B.DungeonScoresBucketHasProgress
local keystoneRetryPending = B.keystoneRetryPending
local keystoneRetryCount = B.keystoneRetryCount
local keystoneZeroSeenAt = B.keystoneZeroSeenAt
local keystoneRefreshLastAt = B.keystoneRefreshLastAt
local keystoneWarmupLastAt = B.keystoneWarmupLastAt
local keystoneLastSeen = B.keystoneLastSeen
local KEYSTONE_REFRESH_MIN_INTERVAL = B.KEYSTONE_REFRESH_MIN_INTERVAL
local KEYSTONE_WARMUP_COOLDOWN = B.KEYSTONE_WARMUP_COOLDOWN
local KEYSTONE_REFRESH_HIGH_PRIORITY = B.KEYSTONE_REFRESH_HIGH_PRIORITY
local KEYSTONE_ZERO_CONFIRM_SECONDS = B.KEYSTONE_ZERO_CONFIRM_SECONDS
local KEYSTONE_RETRY_MAX = B.KEYSTONE_RETRY_MAX
local KEYSTONE_RETRY_DELAYS = B.KEYSTONE_RETRY_DELAYS

---Characters tab reads db.global.characters[].mythicKey; PvE updates must mirror pveCache keystone there.
---@return boolean changed
local function MirrorKeystoneToCharacterRow(addon, pveCharKey, keystoneLevel, mapID)
    if not addon or not addon.db or not addon.db.global or not addon.db.global.characters then return false end
    local tableKey = pveCharKey
    if ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey then
        local sessionTableKey = ns.CharacterService:ResolveCharactersTableKey(addon)
        if sessionTableKey then
            tableKey = sessionTableKey
        elseif ns.Utilities and ns.Utilities.ResolveCharacterRowKey then
            local rowKey = ns.Utilities:ResolveCharacterRowKey(addon, pveCharKey)
            if rowKey then tableKey = rowKey end
        end
    end
    local row = addon.db.global.characters[tableKey]
    if not row then return false end
    local old = row.mythicKey
    local lv = tonumber(keystoneLevel)
    local mid = tonumber(mapID)
    if lv and mid and lv > 0 and mid > 0 then
        local oldLevel = old and tonumber(old.level) or nil
        local oldMap = old and tonumber(old.mapID or old.dungeonID) or nil
        if oldLevel == lv and oldMap == mid then
            local oldName = old and old.dungeonName
            if oldName and oldName ~= "" and oldName ~= "Unknown Dungeon" then
                return false
            end
            local refreshedName = Utilities and Utilities.ResolveKeystoneDungeonName
                and Utilities:ResolveKeystoneDungeonName({ mapID = mid, dungeonID = mid, dungeonName = oldName })
            if refreshedName and refreshedName ~= "Unknown Dungeon" and refreshedName ~= oldName then
                row.mythicKey = {
                    level = lv,
                    dungeonID = mid,
                    dungeonName = refreshedName,
                    mapID = mid,
                    scanTime = time(),
                }
                return true
            end
            return false
        end
        local mapName = Utilities and Utilities.ResolveKeystoneDungeonName
            and Utilities:ResolveKeystoneDungeonName({ mapID = mid, dungeonID = mid })
            or "Unknown Dungeon"
        row.mythicKey = {
            level = lv,
            dungeonID = mid,
            dungeonName = mapName,
            mapID = mid,
            scanTime = time(),
        }
        return true
    else
        if old == nil then
            return false
        end
        row.mythicKey = nil
        return true
    end
end

---Schedule staggered keystone re-reads for API warmup races (0.5s / 1.2s / 2.5s).
---Capped at KEYSTONE_RETRY_MAX attempts per session per char.
local function ScheduleKeystoneRetry(charKey, reason)
    if not charKey or keystoneRetryPending[charKey] then
        return
    end
    if not C_Timer or not C_Timer.After then
        return
    end
    local attempts = (keystoneRetryCount[charKey] or 0)
    if attempts >= KEYSTONE_RETRY_MAX then
        return
    end
    keystoneRetryCount[charKey] = attempts + 1
    keystoneRetryPending[charKey] = true
    local delay = KEYSTONE_RETRY_DELAYS[attempts + 1] or KEYSTONE_RETRY_DELAYS[#KEYSTONE_RETRY_DELAYS]
    C_Timer.After(delay, function()
        keystoneRetryPending[charKey] = nil
        if WarbandNexus and WarbandNexus.RequestKeystoneRefresh then
            WarbandNexus:RequestKeystoneRefresh(reason or "keystoneRetry", true)
        end
    end)
end

---Central keystone refresh: C_MythicPlus read, roster cache invalidation, WN_* fan-out.
---@param reason string|nil diagnostic tag (debug only)
---@param forceClearSeen boolean|nil when true, clears keystoneLastSeen and schedules API warmup retries
---@return boolean didChange
function WarbandNexus:RequestKeystoneRefresh(reason, forceClearSeen)
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end
    local charKey = GetSessionCanonicalPvEKey()
    if not charKey then return false end

    local now = GetTime()
    -- Detection must never be throttled while we currently show NO key for this character: the
    -- "no key -> just obtained one" transition (e.g. an NPC / Font of Power keystone landing in the
    -- bags, which fires no CHALLENGE_MODE_* event) has to get through on the first bag tick. Once a
    -- key is cached, the normal throttle applies again, so this cannot spam.
    local ksStore = self.db and self.db.global and self.db.global.pveCache
        and self.db.global.pveCache.mythicPlus and self.db.global.pveCache.mythicPlus.keystones
    local cachedKs = ksStore and ksStore[charKey]
    local hasCachedKey = (cachedKs and tonumber(cachedKs.level) and tonumber(cachedKs.level) > 0) or false
    local highPriority = (reason and KEYSTONE_REFRESH_HIGH_PRIORITY[reason]) or (not hasCachedKey)
    if not highPriority then
        local last = keystoneRefreshLastAt[charKey] or 0
        if (now - last) < KEYSTONE_REFRESH_MIN_INTERVAL then
            return false
        end
    end
    keystoneRefreshLastAt[charKey] = now

    -- Clear dedupe only; keep retry counters so staggered warmup is not reset every call.
    if forceClearSeen then
        keystoneLastSeen[charKey] = nil
    end

    if C_MythicPlus and C_MythicPlus.RequestMapInfo then
        pcall(C_MythicPlus.RequestMapInfo)
    end

    local didChange = self:UpdateCharacterKeystone(charKey)

    -- Only persist / invalidate when the keystone actually changed. With the throttle bypassed for
    -- keyless characters (above), a no-op re-read on every bag tick must stay cheap; UpdateCharacterKeystone
    -- already returns false via its dedupe when nothing changed.
    if didChange then
        if self.InvalidateGetAllCharactersCache then
            self:InvalidateGetAllCharactersCache()
        end
        if self.SavePvECache then
            self:SavePvECache()
        end
        if self.SendMessage and Constants and Constants.EVENTS then
            if Constants.EVENTS.CHARACTER_UPDATED then
                self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, { charKey = charKey, dataType = "mythicKey" })
            end
            if Constants.EVENTS.PVE_UPDATED then
                self:SendMessage(Constants.EVENTS.PVE_UPDATED)
            end
        end
    end

    return didChange
end

-- MYTHIC+ DATA

---Update current week's Mythic+ affixes (lean: only IDs stored in SV).
---Metadata (name, description, icon) resolved on-demand from C_ChallengeMode.GetAffixInfo().
function WarbandNexus:UpdateMythicPlusAffixes()
    if not C_MythicPlus or not C_ChallengeMode or not self.db.global.pveCache then return end
    
    -- C_MythicPlus.GetCurrentAffixes() returns affixID list OR struct array
    local affixes = C_MythicPlus.GetCurrentAffixes()
    
    if affixes and #affixes > 0 then
        self.db.global.pveCache.mythicPlus.currentAffixes = {}
        for i = 1, #affixes do
            local affixData = affixes[i]
            local affixID = type(affixData) == "table" and affixData.id or affixData
            
            if affixID and type(affixID) == "number" then
                -- Store only the ID (lean format). Metadata resolved on-demand.
                table.insert(self.db.global.pveCache.mythicPlus.currentAffixes, affixID)
            end
        end
    end
end

---Update character's keystone data
---@return boolean didChange
function WarbandNexus:UpdateCharacterKeystone(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return false
    end
    
    if not C_MythicPlus or not charKey or not self.db.global.pveCache then return false end
    charKey = CanonicalizePvEKey(charKey)
    
    local keystoneInfo = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    if keystoneInfo and issecretvalue and issecretvalue(keystoneInfo) then keystoneInfo = nil end
    if keystoneLevel and issecretvalue and issecretvalue(keystoneLevel) then keystoneLevel = nil end
    local ksStore = self.db.global.pveCache.mythicPlus and self.db.global.pveCache.mythicPlus.keystones
    local existing = ksStore and ksStore[charKey] or nil

    -- Dedupe only definitive API reads (level>0 or confirmed level==0). Do not cache nil|nil —
    -- that blocks retries while C_MythicPlus is still warming up after loot/maps events.
    local seenKey = tostring(keystoneLevel) .. "|" .. tostring(keystoneInfo)
    local levelNum = keystoneLevel and tonumber(keystoneLevel) or nil
    local isDefinitiveRead = (levelNum and levelNum > 0 and keystoneInfo ~= nil) or levelNum == 0
    if isDefinitiveRead and keystoneLastSeen[charKey] == seenKey then
        return false
    end

    local didChange = false
    if keystoneInfo and keystoneLevel and keystoneLevel > 0 then
        if not self.db.global.pveCache.mythicPlus.keystones then
            self.db.global.pveCache.mythicPlus.keystones = {}
        end
        local oldLevel = existing and tonumber(existing.level) or nil
        local oldMap = existing and tonumber(existing.mapID) or nil
        local newLevel = tonumber(keystoneLevel)
        local newMap = tonumber(keystoneInfo)
        local dungeonName = Utilities and Utilities.ResolveKeystoneDungeonName
            and Utilities:ResolveKeystoneDungeonName({
                mapID = newMap,
                dungeonID = newMap,
                dungeonName = existing and existing.dungeonName,
                name = existing and existing.name,
            })
        local nameNeedsRefresh = existing
            and (not existing.dungeonName or existing.dungeonName == "Unknown Dungeon")
            and dungeonName and dungeonName ~= "Unknown Dungeon"
        if oldLevel ~= newLevel or oldMap ~= newMap or nameNeedsRefresh then
            self.db.global.pveCache.mythicPlus.keystones[charKey] = {
                mapID = keystoneInfo,
                level = keystoneLevel,
                dungeonName = dungeonName,
                lastUpdate = time(),
            }
            didChange = true
            PvECacheUserDebug("keystone: STORED key=%s mapID=%s level=%s", tostring(charKey), tostring(keystoneInfo), tostring(keystoneLevel))
        end
        keystoneZeroSeenAt[charKey] = nil
        keystoneRetryCount[charKey] = nil
        keystoneLastSeen[charKey] = seenKey
        if MirrorKeystoneToCharacterRow(self, charKey, keystoneLevel, keystoneInfo) then
            didChange = true
        end
    else
        -- Only clear when API reports "no key" (level 0). Nil map+level often means APIs not ready yet —
        -- do not wipe a good cached key (fixes login / affix race losing alt keys).
        if keystoneLevel == 0 then
            if existing and existing.level and existing.level > 0 then
                local firstSeen = keystoneZeroSeenAt[charKey]
                if not firstSeen then
                    keystoneZeroSeenAt[charKey] = time()
                    PvECacheUserDebug(
                        "keystone: API level 0 (first sight) — keep existing cache key=%s mapID=%s level=%s",
                        tostring(charKey), tostring(existing.mapID), tostring(existing.level))
                    return false
                end
                if (time() - firstSeen) < KEYSTONE_ZERO_CONFIRM_SECONDS then
                    PvECacheUserDebug(
                        "keystone: API level 0 (await confirm) — keep existing cache key=%s age=%ss",
                        tostring(charKey), tostring(time() - firstSeen))
                    return false
                end
            end

            if self.db.global.pveCache.mythicPlus.keystones then
                self.db.global.pveCache.mythicPlus.keystones[charKey] = nil
            end
            didChange = existing ~= nil
            keystoneZeroSeenAt[charKey] = nil
            keystoneLastSeen[charKey] = seenKey
            PvECacheUserDebug("keystone: API level 0 — cleared cache entry key=%s", tostring(charKey))
            if MirrorKeystoneToCharacterRow(self, charKey, nil, nil) then
                didChange = true
            end
        else
            -- API warmup race: keep existing key and schedule one delayed re-read.
            -- Cooldown + retry-pending guard: ITEM_PUSH / UpdatePvEData bursts must not
            -- repaint the same chat line every frame while C_MythicPlus is still nil.
            if not keystoneRetryPending[charKey] then
                local warmupNow = GetTime()
                local warmupLast = keystoneWarmupLastAt[charKey] or 0
                if (warmupNow - warmupLast) >= KEYSTONE_WARMUP_COOLDOWN then
                    keystoneWarmupLastAt[charKey] = warmupNow
                    if C_MythicPlus.RequestMapInfo then
                        pcall(C_MythicPlus.RequestMapInfo)
                    end
                    ScheduleKeystoneRetry(charKey)
                    if ShouldLogPvECacheDiag("keystone_warmup:" .. tostring(charKey), 30) then
                        PvECacheUserDebug(
                            "keystone: no write (API not ready: level=%s mapID=%s) key=%s — existing cache kept",
                            tostring(keystoneLevel), tostring(keystoneInfo), tostring(charKey))
                    end
                end
            end
        end
    end
    return didChange
end

---Update character's best M+ runs
function WarbandNexus:UpdateMythicPlusBestRuns(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_MythicPlus or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)

    -- Must run before anything is read back: a season flip invalidates every stored score.
    ApplyMythicPlusSeasonRollover()

    -- Get best run level for each dungeon
    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable()
    if not maps then return end
    
    if not self.db.global.pveCache.mythicPlus.bestRuns then
        self.db.global.pveCache.mythicPlus.bestRuns = {}
    end
    
    if not self.db.global.pveCache.mythicPlus.bestRuns[charKey] then
        self.db.global.pveCache.mythicPlus.bestRuns[charKey] = {}
    end
    
    -- Get overall M+ rating/score if available
    local overallScore = 0
    local scoreSource = "NONE"
    
    if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
        overallScore = C_ChallengeMode.GetOverallDungeonScore() or 0
        scoreSource = "GetOverallDungeonScore"
    elseif C_PlayerInfo and C_PlayerInfo.GetPlayerMythicPlusRatingSummary then
        local summary = C_PlayerInfo.GetPlayerMythicPlusRatingSummary("player")
        if summary and summary.currentSeasonScore then
            overallScore = summary.currentSeasonScore
            scoreSource = "GetPlayerMythicPlusRatingSummary"
        end
    end
    
    local bestRunsBucket = self.db.global.pveCache.mythicPlus.bestRuns[charKey]
    local prevOverall = bestRunsBucket.overallScore or 0
    local prevSource = bestRunsBucket.scoreSource or "NONE"
    bestRunsBucket.overallScore = overallScore
    bestRunsBucket.scoreSource = scoreSource
    local overallChanged = (prevOverall ~= overallScore) or (prevSource ~= scoreSource)
    local updatedRuns = 0
    
    -- Store best runs for each dungeon
    for i = 1, #maps do
        local mapID = maps[i]
        -- Returns durationSec, level, completionDate, affixIDs, members, dungeonScore (no on-time flag).
        -- Assign outside `and`: `x = cond and Fn()` would truncate to the first return.
        local level
        if C_MythicPlus.GetWeeklyBestForMap then
            local _
            _, level = C_MythicPlus.GetWeeklyBestForMap(mapID)
        end
        if level and level > 0 then
            local old = bestRunsBucket[mapID]
            local oldLevel = old and old.level or 0
            bestRunsBucket[mapID] = {
                level = level,
                lastUpdate = time(),
            }
            if oldLevel ~= level then
                updatedRuns = updatedRuns + 1
            end
        end
    end
    
    if overallChanged or updatedRuns > 0 then
        PvECacheUserDebug(
            "bestRuns: key=%s overall=%s source=%s updatedRuns=%d",
            tostring(charKey), tostring(overallScore), tostring(scoreSource), updatedRuns
        )
    end
end

---Update character's dungeon scores (overall + per-dungeon breakdown)
function WarbandNexus:UpdateDungeonScores(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_ChallengeMode or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)

    -- Must run before the zero-snapshot guard below, or last season's scores survive the flip.
    ApplyMythicPlusSeasonRollover()

    -- Initialize cache
    if not self.db.global.pveCache.mythicPlus.dungeonScores then
        self.db.global.pveCache.mythicPlus.dungeonScores = {}
    end
    
    if not self.db.global.pveCache.mythicPlus.dungeonScores[charKey] then
        self.db.global.pveCache.mythicPlus.dungeonScores[charKey] = {
            overallScore = 0,
            dungeons = {},
            lastUpdate = 0,
        }
    end
    
    local scoreData = self.db.global.pveCache.mythicPlus.dungeonScores[charKey]
    local prevStoredOverall = scoreData.overallScore or 0
    local existingDungeons = scoreData.dungeons or {}
    
    local newOverall = 0
    if C_ChallengeMode.GetOverallDungeonScore then
        newOverall = C_ChallengeMode.GetOverallDungeonScore() or 0
    end
    
    local maps = C_ChallengeMode.GetMapTable()
    local anyIncomingDungeon = false
    local mergedDungeons = {}
    local preservedFromSV = 0
    local changedRows = 0
    
    if maps then
        for i = 1, #maps do
            local mapID = maps[i]
            local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
            
            local dungeonScore = 0
            local bestLevel = 0
            
            if intimeInfo and intimeInfo.level then
                dungeonScore = math.max(dungeonScore, intimeInfo.dungeonScore or 0)
                bestLevel = math.max(bestLevel, intimeInfo.level)
            end
            if overtimeInfo and overtimeInfo.level then
                dungeonScore = math.max(dungeonScore, overtimeInfo.dungeonScore or 0)
                bestLevel = math.max(bestLevel, overtimeInfo.level)
            end
            
            if dungeonScore > 0 or bestLevel > 0 then
                anyIncomingDungeon = true
            end
            
            local old = existingDungeons[mapID]
            -- Never replace a good cached row with an all-zero snapshot (login / affix / API race).
            if dungeonScore == 0 and bestLevel == 0 and old and ((old.score or 0) > 0 or (old.bestLevel or 0) > 0) then
                mergedDungeons[mapID] = { score = old.score or 0, bestLevel = old.bestLevel or 0 }
                preservedFromSV = preservedFromSV + 1
            else
                mergedDungeons[mapID] = { score = dungeonScore, bestLevel = bestLevel }
                local oldScore = old and old.score or 0
                local oldBestLevel = old and old.bestLevel or 0
                if oldScore ~= dungeonScore or oldBestLevel ~= bestLevel then
                    changedRows = changedRows + 1
                end
            end
        end
    end
    
    -- API often returns all zeros before M+ data hydrates; do not wipe a good SavedVariables snapshot.
    if newOverall == 0 and not anyIncomingDungeon and DungeonScoresBucketHasProgress(scoreData) then
        if ShouldLogPvECacheDiag("dungeonScores-skip-" .. tostring(charKey), 45) then
            PvECacheUserDebug(
                "dungeonScores: SKIP write (API overall=0, no per-map data, SV has progress) key=%s prevOverall=%s",
                tostring(charKey), tostring(scoreData.overallScore or 0))
        end
        return
    end
    
    -- GetMapTable() missing (rare): keep per-map SV; still allow overall score when the API returns it.
    if not maps or #maps == 0 then
        if newOverall > 0 then
            scoreData.overallScore = newOverall
            scoreData.lastUpdate = time()
            if prevStoredOverall ~= scoreData.overallScore then
                PvECacheUserDebug("dungeonScores: maps missing; updated overall only=%s key=%s", tostring(newOverall), tostring(charKey))
            end
        else
            if ShouldLogPvECacheDiag("dungeonScores-maps-missing-" .. tostring(charKey), 60) then
                PvECacheUserDebug("dungeonScores: maps missing; no write key=%s apiOverall=0", tostring(charKey))
            end
        end
        return
    end
    
    -- Overall: only overwrite with 0 when we never had a score (or API gave a non-zero update).
    if newOverall > 0 then
        scoreData.overallScore = newOverall
    elseif (scoreData.overallScore or 0) == 0 then
        scoreData.overallScore = 0
    end
    
    scoreData.dungeons = mergedDungeons
    scoreData.lastUpdate = time()
    if changedRows > 0 or prevStoredOverall ~= (scoreData.overallScore or 0) then
        PvECacheUserDebug(
            "dungeonScores: SAVED key=%s apiOverall=%s storedOverall=%s changedRows=%d maps=%d incomingAny=%s preservedRows=%d",
            tostring(charKey),
            tostring(newOverall),
            tostring(scoreData.overallScore or 0),
            changedRows,
            #maps,
            anyIncomingDungeon and "yes" or "no",
            preservedFromSV)
    end
end

---Collect M+ run history for current character (this week only)
function WarbandNexus:UpdateMythicPlusRunHistory(charKey)
    if not charKey or not self.db.global.pveCache then return end
    if not C_MythicPlus or not C_MythicPlus.GetRunHistory then return end
    charKey = CanonicalizePvEKey(charKey)

    if not self.db.global.pveCache.mythicPlus.runHistory then
        self.db.global.pveCache.mythicPlus.runHistory = {}
    end

    -- includePreviousWeeks = false, includeIncompleteRuns = true
    -- In WoW, untimed (completed over-time) runs count fully toward Great Vault progression.
    local runs = C_MythicPlus.GetRunHistory(false, true)
    local mpCache = self.db.global.pveCache.mythicPlus
    local storedRuns = mpCache.runHistory[charKey]
    local storedWeek = mpCache.runHistoryWeek and mpCache.runHistoryWeek[charKey]
    local storedThisWeek = type(storedRuns) == "table" and #storedRuns > 0 and type(storedWeek) == "number"
        and not (WarbandNexus.HasWeeklyResetOccurred and WarbandNexus:HasWeeklyResetOccurred(storedWeek))
    -- Runs are never removed inside a week. A nil / empty history while this week's runs are stored is
    -- an unready read (before CHALLENGE_MODE_MAPS_UPDATE at login), not "no runs": keep them.
    if (not runs or #runs == 0) and storedThisWeek then
        return
    end
    if not runs then
        mpCache.runHistory[charKey] = {}
        return
    end

    local history = {}
    for i = 1, #runs do
        local run = runs[i]
        if run and run.mapChallengeModeID and run.level then
            local dungeonName
            if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                dungeonName = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID)
                if issecretvalue and dungeonName and issecretvalue(dungeonName) then
                    dungeonName = nil
                end
            end
            history[#history + 1] = {
                dungeon = dungeonName or ("Map " .. run.mapChallengeModeID),
                level = run.level,
                timed = run.completed or false,
            }
        end
    end

    table.sort(history, function(a, b) return a.level > b.level end)

    self.db.global.pveCache.mythicPlus.runHistory[charKey] = history
    self.db.global.pveCache.mythicPlus.runHistoryWeek = self.db.global.pveCache.mythicPlus.runHistoryWeek or {}
    self.db.global.pveCache.mythicPlus.runHistoryWeek[charKey] = time()
end

--- Get the cross-character keystone synergy matrix.
--- For every alt holding a keystone, analyzes how that keystone benefits other characters in the warband
--- (e.g. higher level than their current best run for that dungeon, or lifts a vault slot).
--- @return table list of synergies { holderKey, holderName, classFile, keystone, beneficiaries = { ... }, totalRatingPotential }
function WarbandNexus:GetKeystoneSynergyMatrix()
    local result = {}
    if not self.db or not self.db.global or not self.db.global.characters then
        return result
    end

    local chars = self.db.global.characters
    local pve = self.db.global.pveCache
    local runHistory = pve and pve.mythicPlus and pve.mythicPlus.runHistory or {}

    local holders = {}
    for charKey, charData in pairs(chars) do
        local mk = charData.mythicKey
        if mk and mk.level and tonumber(mk.level) and tonumber(mk.level) > 0 then
            holders[#holders + 1] = {
                charKey = charKey,
                charName = charData.name or charKey,
                classFile = charData.classFile or "WARRIOR",
                mythicKey = {
                    level = tonumber(mk.level) or 0,
                    dungeonName = mk.dungeonName or (ns.Utilities and ns.Utilities.ResolveKeystoneDungeonName and ns.Utilities:ResolveKeystoneDungeonName(mk)) or "Keystone",
                    mapChallengeModeID = mk.mapChallengeModeID,
                },
            }
        end
    end

    for hi = 1, #holders do
        local h = holders[hi]
        local kLevel = h.mythicKey.level
        local kDungeon = h.mythicKey.dungeonName
        local beneficiaries = {}

        for otherKey, otherData in pairs(chars) do
            if otherKey ~= h.charKey then
                local otherRuns = runHistory[otherKey] or {}
                local currentBestForDungeon = 0
                for ri = 1, #otherRuns do
                    local r = otherRuns[ri]
                    if r.dungeon and kDungeon and (r.dungeon == kDungeon or string.find(r.dungeon, kDungeon, 1, true) or string.find(kDungeon, r.dungeon, 1, true)) then
                        local rLvl = tonumber(r.level) or 0
                        if rLvl > currentBestForDungeon then
                            currentBestForDungeon = rLvl
                        end
                    end
                end

                if kLevel > currentBestForDungeon then
                    local levelDelta = kLevel - currentBestForDungeon
                    local estRatingGain = math.floor(levelDelta * 7.5)
                    beneficiaries[#beneficiaries + 1] = {
                        charKey = otherKey,
                        charName = otherData.name or otherKey,
                        classFile = otherData.classFile or "PRIEST",
                        currentBest = currentBestForDungeon,
                        keyLevel = kLevel,
                        levelDelta = levelDelta,
                        estRatingGain = estRatingGain,
                    }
                end
            end
        end

        table.sort(beneficiaries, function(a, b)
            return a.estRatingGain > b.estRatingGain
        end)

        if #beneficiaries > 0 then
            local tot = 0
            for bi = 1, #beneficiaries do tot = tot + beneficiaries[bi].estRatingGain end
            result[#result + 1] = {
                holderKey = h.charKey,
                holderName = h.charName,
                classFile = h.classFile,
                keystone = h.mythicKey,
                beneficiaries = beneficiaries,
                totalRatingPotential = tot,
            }
        end
    end

    table.sort(result, function(a, b)
        return a.totalRatingPotential > b.totalRatingPotential
    end)

    return result
end

--- Get recommended dungeons to target for keystone rerolls based on what the warband needs most.
--- @param minLevel number|nil Minimum level threshold (default 7)
--- @return table list of { dungeonName, needyCount, totalPotential }
function WarbandNexus:GetKeystoneRerollRecommendations(minLevel)
    local minLvl = tonumber(minLevel) or 7
    local dungeonNeeds = {}
    if not self.db or not self.db.global or not self.db.global.characters then
        return {}
    end

    local chars = self.db.global.characters
    local pve = self.db.global.pveCache
    local runHistory = pve and pve.mythicPlus and pve.mythicPlus.runHistory or {}

    local seenDungeons = {}
    for _, runs in pairs(runHistory) do
        for i = 1, #runs do
            if runs[i].dungeon then
                seenDungeons[runs[i].dungeon] = true
            end
        end
    end

    for dName in pairs(seenDungeons) do
        local needyCount = 0
        local totalPotential = 0
        for charKey, charData in pairs(chars) do
            local otherRuns = runHistory[charKey] or {}
            local curBest = 0
            for ri = 1, #otherRuns do
                if otherRuns[ri].dungeon == dName then
                    local lvl = tonumber(otherRuns[ri].level) or 0
                    if lvl > curBest then curBest = lvl end
                end
            end
            if curBest < minLvl then
                needyCount = needyCount + 1
                totalPotential = totalPotential + (minLvl - curBest) * 7.5
            end
        end

        if needyCount > 0 then
            dungeonNeeds[#dungeonNeeds + 1] = {
                dungeonName = dName,
                needyCount = needyCount,
                totalPotential = math.floor(totalPotential),
            }
        end
    end

    table.sort(dungeonNeeds, function(a, b)
        if a.needyCount ~= b.needyCount then
            return a.needyCount > b.needyCount
        end
        return a.totalPotential > b.totalPotential
    end)

    return dungeonNeeds
end
