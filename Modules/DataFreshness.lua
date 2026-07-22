--[[
    Warband Nexus — Data freshness policy (fetch-once, event-driven updates)

    After a domain snapshot is persisted in SavedVariables, login/reload must NOT
    re-run full scans. Blizzard events + existing WN_* listeners refresh deltas only.
    Full login warmups run when data is missing, schema version mismatches, or the
    player explicitly forces sync (slash / trade window collectors).
]]

local ADDON_NAME, ns = ...
local DF = {}
ns.DataFreshness = DF

function DF.HasTableRows(t)
    return type(t) == "table" and next(t) ~= nil
end

function DF.SchemaVersionMatches(dbVersion, expected)
    return dbVersion ~= nil and dbVersion == expected
end

--- Resolve a subsidiary bucket (currency/reputation) including legacy Name-Realm alias keys.
---@param bucketMap table|nil
---@param subsidiaryKey string|nil
---@return table|nil
function DF.ResolveWarmSubsidiaryBucket(bucketMap, subsidiaryKey)
    if not bucketMap or not subsidiaryKey then return nil end
    local direct = bucketMap[subsidiaryKey]
    if type(direct) == "table" and next(direct) ~= nil then
        return direct
    end
    if ns.VaultCharKeysMatch then
        for k, row in pairs(bucketMap) do
            if k ~= subsidiaryKey and type(row) == "table" and next(row) ~= nil
                and ns.VaultCharKeysMatch(k, subsidiaryKey) then
                return row
            end
        end
    end
    return nil
end

--- Currency DB warm: current character has rows, schema matches.
--- lastScan may be 0 on legacy SV rows — persisted rows + matching schema still count as warm.
---@param db table|nil currencyData.global subtree
---@param cacheVersion number
---@param currentSubsidiaryKey string|nil
---@return boolean
function DF.IsCurrencyWarm(db, cacheVersion, currentSubsidiaryKey)
    if not db or not DF.HasTableRows(db.currencies) then return false end
    if not DF.SchemaVersionMatches(db.version, cacheVersion) then return false end
    if not currentSubsidiaryKey then return false end
    return DF.HasTableRows(DF.ResolveWarmSubsidiaryBucket(db.currencies, currentSubsidiaryKey))
end

--- Reputation DB warm (same contract as currency).
---@param db table|nil reputationData.global subtree
---@param cacheVersion number
---@param currentSubsidiaryKey string|nil
---@return boolean
function DF.IsReputationWarm(db, cacheVersion, currentSubsidiaryKey)
    if not db then return false end
    if not DF.SchemaVersionMatches(db.version, cacheVersion) then return false end
    if not currentSubsidiaryKey then return false end
    if DF.HasTableRows(DF.ResolveWarmSubsidiaryBucket(db.characters, currentSubsidiaryKey)) then
        return true
    end
    return DF.HasTableRows(db.accountWide)
end

--- Character row already has a full login snapshot (legacy rows without lastFullSaveAt included).
---@param charData table|nil
---@return boolean
function DF.IsCharacterRowWarm(charData)
    if not charData or type(charData) ~= "table" then return false end
    if charData.lastFullSaveAt and tonumber(charData.lastFullSaveAt) then
        return true
    end
    if charData.trackingConfirmed and charData.professions and next(charData.professions) then
        if charData.stats or charData.pveProgress or charData.itemLevel then
            return true
        end
    end
    return false
end

--- Re-read WoW Statistics when the stored seed stamp is older than this (seconds).
--- GetStatistic is the authoritative try-count source for stat-backed bosses (raid/dungeon
--- mounts). The old gate was "seeded once, ever" — so a live increment lost to a secret
--- difficulty, a long cinematic, or an expired encounter TTL could never be repaired by a
--- relog. A daily re-read makes the counter self-healing without login-time scan cost.
DF.TRYCOUNTER_STATISTICS_MAX_AGE = 24 * 60 * 60

--- Try Counter statistics are warm for this character (skip login SeedFromStatistics).
--- Profiles seeded before the stamp existed have no timestamp and re-seed once.
---@param dbGlobal table|nil db.global
---@param charKey string|nil
---@param nowEpoch number|nil server epoch override (tests); defaults to time()
---@return boolean
function DF.IsTryCounterStatisticsWarm(dbGlobal, charKey, nowEpoch)
    if not dbGlobal or not charKey or charKey == "" then return false end
    local tc = dbGlobal.tryCounts
    if not DF.HasTableRows(tc) then return false end
    local seedStamps = dbGlobal.tryCounterStatSeedAt
    local seededAt = type(seedStamps) == "table" and tonumber(seedStamps[charKey]) or nil
    if not seededAt then return false end
    local now = tonumber(nowEpoch) or (time and time()) or 0
    if now > 0 and (now - seededAt) >= DF.TRYCOUNTER_STATISTICS_MAX_AGE then return false end
    local snaps = dbGlobal.statisticSnapshots
    if not snaps or not snaps[charKey] or not next(snaps[charKey]) then return false end
    return true
end

--- Knowledge persisted for one expansion skill line (knowledgeData or professionData bucket).
---@param charData table
---@param skillLineID number
---@return boolean
function DF.HasPersistedKnowledgeForSkillLine(charData, skillLineID)
    if not charData or not skillLineID then return false end
    local kd = charData.knowledgeData
    if kd and kd[skillLineID] and type(kd[skillLineID]) == "table" then
        local row = kd[skillLineID]
        if row.lastUpdate and tonumber(row.lastUpdate) then return true end
        if row.maxPoints or row.spentPoints or row.specTabs then return true end
    end
    local pd = charData.professionData
    if pd and pd.bySkillLine then
        local bucket = pd.bySkillLine[skillLineID]
        if bucket and bucket.knowledge and type(bucket.knowledge) == "table" then
            local kn = bucket.knowledge
            if kn.lastUpdate and tonumber(kn.lastUpdate) then return true end
            if kn.maxPoints or kn.spentPoints or kn.specTabs then return true end
        end
    end
    return false
end

--- All discovered profession skill lines have persisted knowledge (login warmup skip).
---@param charData table|nil
---@return boolean
function DF.IsKnowledgeWarmForCharacter(charData)
    if not charData or not charData.discoveredSkillLines then return false end
    local anyLine = false
    for _, skillLines in pairs(charData.discoveredSkillLines) do
        if skillLines and #skillLines > 0 then
            for sli = 1, #skillLines do
                local sl = skillLines[sli]
                local slID = sl and (sl.id or sl)
                if slID then
                    anyLine = true
                    if not DF.HasPersistedKnowledgeForSkillLine(charData, slID) then
                        return false
                    end
                end
            end
        end
    end
    return anyLine
end

--- Expansion skill levels already stored for discovered skill lines (skip login C_TradeSkillUI refresh).
---@param charData table|nil
---@return boolean
function DF.IsExpansionProfessionsWarm(charData)
    if not charData or not charData.discoveredSkillLines then return false end
    local exp = charData.professionExpansions
    if not DF.HasTableRows(exp) then return false end
    local anyDiscovered = false
    for profName, skillLines in pairs(charData.discoveredSkillLines) do
        if skillLines and #skillLines > 0 then
            anyDiscovered = true
            local profExp = exp[profName]
            if not profExp or #profExp == 0 then return false end
            local hasSkill = false
            for i = 1, #profExp do
                local row = profExp[i]
                if row and row.skillLineID and (row.maxSkillLevel or 0) > 0 then
                    hasSkill = true
                    break
                end
            end
            if not hasSkill then return false end
        end
    end
    return anyDiscovered
end

--- Concentration rows exist for discovered lines (skip login discovery scan).
---@param charData table|nil
---@return boolean
function DF.IsConcentrationWarm(charData)
    if not charData or not charData.discoveredSkillLines then return false end
    local conc = charData.concentration
    if not DF.HasTableRows(conc) then return false end
    for _, skillLines in pairs(charData.discoveredSkillLines) do
        if skillLines and #skillLines > 0 then
            for sli = 1, #skillLines do
                local sl = skillLines[sli]
                local slID = sl and (sl.id or sl)
                if slID then
                    local row = conc[slID] or conc[tostring(slID)]
                    if not row or not tonumber(row.lastUpdate) then
                        return false
                    end
                end
            end
        end
    end
    return true
end

--- Profession equipment snapshot exists (skip login gear detection scan).
---@param charData table|nil
---@return boolean
function DF.IsProfessionEquipmentWarm(charData)
    local eq = charData and charData.professionEquipment
    if not eq or type(eq) ~= "table" then return false end
    if eq._last and tonumber(eq._last.lastUpdate) then return true end
    for key, row in pairs(eq) do
        if key ~= "_last" and key ~= "_legacy" and type(row) == "table" then
            if tonumber(row.lastUpdate) or row.tool or row.accessory1 or row.accessory2 then
                return true
            end
        end
    end
    return false
end

--- PvE cache warm for current character (skip login UpdatePvEData full collect).
---@param dbGlobal table|nil
---@param cacheVersion number
---@param charKey string|nil
---@return boolean
function DF.IsPvEWarm(dbGlobal, cacheVersion, charKey)
    if not dbGlobal or not charKey or charKey == "" then return false end
    local cache = dbGlobal.pveCache
    if not cache or type(cache) ~= "table" then return false end
    if not DF.SchemaVersionMatches(cache.version, cacheVersion) then return false end
    if (cache.lastUpdate or 0) <= 0 then return false end
    local mp = cache.mythicPlus
    if mp then
        local ks = mp.keystones and mp.keystones[charKey]
        if ks and (ks.lastUpdate or ks.mapID or ks.level) then return true end
        local runs = mp.bestRuns and mp.bestRuns[charKey]
        if DF.HasTableRows(runs) then return true end
        local scores = mp.dungeonScores and mp.dungeonScores[charKey]
        if scores and tonumber(scores.lastUpdate) then return true end
    end
    local gv = cache.greatVault and cache.greatVault.activities and cache.greatVault.activities[charKey]
    if DF.HasTableRows(gv) then return true end
    local lo = cache.lockouts and cache.lockouts[charKey]
    if DF.HasTableRows(lo) then return true end
    return false
end
