--[[
    Warband Nexus - PvE Cache Service
    DB-backed cache for Mythic+, Great Vault, lockouts, and weekly rewards.
    Emits WN_PVE_UPDATED after writes.
]]

local ADDON_NAME, ns = ...

-- Trace helper: same channel as ns.DebugPrint but requires debugVerbose (matches Currency/Reputation caches).
local DebugPrint = (ns.CreateDebugPrinter and ns.CreateDebugPrinter(nil, {
    verboseOnly = true,
    suppressWhenTryCounterLoot = true,
})) or function() end
local IsDebugModeEnabled = ns.IsDebugModeEnabled
local WarbandNexus = ns.WarbandNexus
local Utilities = ns.Utilities
local issecretvalue = issecretvalue

-- Vault session state shared with PvECacheService_Vault.lua: one copy, always read through this table.
local vaultState = {
    -- Session flag: true once WEEKLY_REWARDS_UPDATE has fired this session, meaning
    -- OnUIInteract() was called and the server has responded with fresh vault data.
    -- Without this, UpdateGreatVaultRewards() can write hasAvailableRewards=false on
    -- login before Blizzard's API is ready, clearing a valid unclaimed vault chest.
    vaultDataFreshThisSession = false,
    --- After a vault claim/item change, treat false HasAvailableRewards writes as authoritative for a few seconds.
    vaultClaimAllowUntil = 0,
}
-- Session flag: true once UPDATE_INSTANCE_INFO has fired ("Fired when data from RequestRaidInfo is
-- available", warcraft.wiki.gg, verified 2026-10-21). Before that GetNumSavedInstances() can read 0
-- for a character that is saved, and the empty write wiped its stored raid/dungeon lockouts.
local instanceInfoSeenThisSession = false

---Chat-visible diagnostics when Config → Debug Mode is on (SavedVariables-safe summaries only).
---Uses strict IsDebugModeEnabled() so legacy truthy non-boolean profile.debugMode cannot spam chat.
local function PvECacheUserDebug(msg, ...)
    if not (IsDebugModeEnabled and IsDebugModeEnabled()) then return end
    local W = rawget(_G, "WarbandNexus") or WarbandNexus
    if not (W and W.Print) then return end
    local text
    if select("#", ...) > 0 then
        local ok, s = pcall(string.format, msg, ...)
        text = ok and s or tostring(msg)
    else
        text = tostring(msg)
    end
    W:Print("|cff00ccff[PvE Cache]|r " .. text)
end

-- Prevent chat spam for repeated identical diagnostic branches.
local pveCacheDiagLastLogAt = {}
local function ShouldLogPvECacheDiag(key, intervalSec)
    local now = GetTime()
    local last = pveCacheDiagLastLogAt[key] or 0
    local interval = intervalSec or 30
    if (now - last) < interval then
        return false
    end
    pveCacheDiagLastLogAt[key] = now
    return true
end

--- One SavedVariables bucket per logical character: normalize legacy/UI key spellings
--- so imports, migration, and live API paths never split the same toon across multiple keys.
local function CanonicalizePvEKey(charKey)
    if issecretvalue and issecretvalue(charKey) then return nil end
    if charKey == nil or charKey == "" then return charKey end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        local k = ns.Utilities:GetCanonicalCharacterKey(charKey)
        if k and k ~= "" then return k end
    end
    return charKey
end

local function CharKeysMatch(a, b)
    if ns.VaultCharKeysMatch then
        return ns.VaultCharKeysMatch(a, b)
    end
    return a and b and a == b
end

local function GetSessionCanonicalPvEKey()
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, nil)
        if k then return CanonicalizePvEKey(k) end
    end
    local raw = ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
    return CanonicalizePvEKey(raw)
end

local function IsSessionPvECharacter(charKey)
    local sessionKey = GetSessionCanonicalPvEKey()
    charKey = CanonicalizePvEKey(charKey)
    if not sessionKey or not charKey then
        return false
    end
    return CharKeysMatch(charKey, sessionKey)
end

--- Merge alias reward rows; a claimed row (false + claimedAt) wins over a stale true on another key.
local function LookupVaultRewardsEntry(rewards, charKey)
    if not rewards or not charKey then
        return nil
    end
    if ns.LookupPvECacheSubtable then
        return ns.LookupPvECacheSubtable(rewards, charKey)
    end
    charKey = CanonicalizePvEKey(charKey)
    local best, bestUpdate, claimedEntry = nil, -1, nil
    for k, row in pairs(rewards) do
        if type(row) == "table" and CharKeysMatch(k, charKey) then
            local lu = tonumber(row.lastUpdate) or 0
            local ca = tonumber(row.claimedAt) or 0
            if row.hasAvailableRewards == false and ca > 0 then
                claimedEntry = row
            end
            if lu >= bestUpdate then
                bestUpdate = lu
                best = row
            end
        end
    end
    return claimedEntry or best
end

local function PruneVaultRewardAliasKeys(rewards, charKey)
    if not rewards or not charKey then
        return
    end
    local canonKey = CanonicalizePvEKey(charKey)
    if not canonKey then
        return
    end
    for k in pairs(rewards) do
        if k ~= canonKey and CharKeysMatch(k, charKey) then
            rewards[k] = nil
        end
    end
end

--- Drop GUID/Name-Realm duplicate rows across all pveCache per-character buckets.
local function PrunePvECacheAliasKeys(pc, charKey)
    if type(pc) ~= "table" or not charKey then return end
    charKey = CanonicalizePvEKey(charKey)
    if not charKey then return end
    local function prune(tbl)
        if type(tbl) ~= "table" then return end
        for k in pairs(tbl) do
            if k ~= charKey and CharKeysMatch(k, charKey) then
                tbl[k] = nil
            end
        end
    end
    local mp = pc.mythicPlus
    if mp then
        prune(mp.keystones)
        prune(mp.bestRuns)
        prune(mp.dungeonScores)
        prune(mp.runHistory)
        prune(mp.runHistoryWeek)
    end
    local gv = pc.greatVault
    if gv then
        prune(gv.activities)
        prune(gv.rewards)
    end
    local lo = pc.lockouts
    if lo then
        prune(lo.raids)
        prune(lo.dungeons)
        prune(lo.worldBosses)
    end
    if pc.delves and pc.delves.characters then
        prune(pc.delves.characters)
    end
end

--- Persist reward flags on the canonical key only (removes GUID/Name-Realm duplicate rows).
local function WriteVaultRewardsCache(charKey, rewardData)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.pveCache then
        return
    end
    charKey = CanonicalizePvEKey(charKey)
    if not charKey then
        return
    end
    local gv = WarbandNexus.db.global.pveCache.greatVault
    if not gv then
        return
    end
    gv.rewards = gv.rewards or {}
    PruneVaultRewardAliasKeys(gv.rewards, charKey)
    gv.rewards[charKey] = rewardData
end

--- True when the logged-in character has ANY unclaimed Great Vault loot waiting -- including loot
--- earned in an earlier reward period, which stays in the chest and stays claimable.
--- Uses HasAvailableRewards only; does not require CanClaimRewards (that is false whenever the
--- player still has to travel to the Great Vault, matching Blizzard's unclaimed prompt).
---@return boolean
function ns.WeeklyVaultHasPendingRewards()
    if ns._vaultSelfTestOverridePending == true then
        return true
    end
    if ns._vaultSelfTestOverridePending == false then
        return false
    end
    if not C_WeeklyRewards or not C_WeeklyRewards.HasAvailableRewards then
        return false
    end
    local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
    if not ok or not has then
        return false
    end
    -- Rewards from an OLDER reward period are still sitting in the chest and are still claimable.
    -- Blizzard's own vault frame proves it: WeeklyRewardsMixin:UpdatePreviousClaim shows
    -- PreviousRewardNotification for exactly `HasAvailableRewards() and not
    -- AreRewardsForCurrentRewardPeriod()`. This used to early-return false in that case, which
    -- hid the vault of anyone who left it unclaimed for a week or more -- and worse, let the cache
    -- heal stamp them "claimed this week", hiding it permanently from their other characters too.
    -- Use ns.WeeklyVaultRewardsAreFromPreviousPeriod() when the age of the loot matters.
    return true
end

--- True when the loot waiting in the vault was earned in an EARLIER reward period (still
--- claimable; Blizzard flags it with its own "previous reward" notice). Label/diagnostic use only
--- -- never gate "is something waiting" on this.
---@return boolean
function ns.WeeklyVaultRewardsAreFromPreviousPeriod()
    if not C_WeeklyRewards or not C_WeeklyRewards.HasAvailableRewards then
        return false
    end
    local ok, has = pcall(C_WeeklyRewards.HasAvailableRewards)
    if not ok or not has then
        return false
    end
    if not C_WeeklyRewards.AreRewardsForCurrentRewardPeriod then
        return false
    end
    local okP, periodCurrent = pcall(C_WeeklyRewards.AreRewardsForCurrentRewardPeriod)
    return okP and periodCurrent == false
end

--- True when vault rewards can be claimed at the current location (vault frame / NPC proximity).
---@return boolean
function ns.WeeklyVaultCanClaimAtLocation()
    if not ns.WeeklyVaultHasPendingRewards() then
        return false
    end
    if C_WeeklyRewards and C_WeeklyRewards.CanClaimRewards then
        local ok, can = pcall(C_WeeklyRewards.CanClaimRewards)
        return ok and can == true
    end
    return true
end

local function CmpNameSort(a, b)
    return (Utilities and Utilities.SafeLower and Utilities:SafeLower(a.name) or "") < (Utilities and Utilities.SafeLower and Utilities:SafeLower(b.name) or "")
end

local function SafeSavedInstanceNumber(value)
    if issecretvalue and issecretvalue(value) then return nil end
    if value == nil then return nil end
    return tonumber(value)
end

local function BuildSavedInstanceStorageKey(slotIndex, lockoutID, journalInstanceID, difficultyID)
    if not (issecretvalue and issecretvalue(lockoutID)) and lockoutID ~= nil then
        local numericID = tonumber(lockoutID)
        if numericID then return numericID end
        if type(lockoutID) == "string" and lockoutID ~= "" then return lockoutID end
    end

    local slot = SafeSavedInstanceNumber(slotIndex) or 0
    local instanceID = SafeSavedInstanceNumber(journalInstanceID)
    local difficulty = SafeSavedInstanceNumber(difficultyID)
    if instanceID then
        return table.concat({ "instance", tostring(instanceID), tostring(difficulty or 0), tostring(slot) }, ":")
    end
    return "slot:" .. tostring(slot)
end

---Boss rows for one GetSavedInstances() slot index (Encounter Journal order).
---@return table[]
local function BuildSavedInstanceEncounterList(slotIndex, numEncounters)
    local encounters = {}
    numEncounters = SafeSavedInstanceNumber(numEncounters)
    if not numEncounters or numEncounters <= 0 then return encounters end
    for j = 1, numEncounters do
        local bossName, _, isKilled = GetSavedInstanceEncounterInfo(slotIndex, j)
        if issecretvalue and bossName and issecretvalue(bossName) then bossName = nil end
        if issecretvalue and issecretvalue(isKilled) then isKilled = nil end
        if bossName then
            encounters[#encounters + 1] = {
                name = bossName,
                killed = isKilled == true,
            }
        end
    end
    return encounters
end

---GetSavedInstanceInfo may return isRaid as boolean or 1/0; it can also be nil in edge builds.
---Use DifficultyID + maxPlayers as fallback so 5-player lockouts still land in dungeons.
---@return boolean|nil true = raid, false = dungeon / small-group saved instance, nil = unknown
local function CoerceSavedInstanceIsRaid(raw, maxPlayers, difficultyId)
    if issecretvalue and issecretvalue(raw) then
        raw = nil
    end
    if raw == true or raw == 1 then return true end
    if raw == false or raw == 0 then return false end

    if type(difficultyId) == "number" and not (issecretvalue and issecretvalue(difficultyId)) then
        -- Raid-style difficulties (see DifficultyID / wow-api-guardian, Midnight 12.0.1)
        if difficultyId == 14 or difficultyId == 15 or difficultyId == 16 or difficultyId == 17
            or difficultyId == 3 or difficultyId == 4 or difficultyId == 5 or difficultyId == 6
            or difficultyId == 9 or difficultyId == 33 or difficultyId == 220 or difficultyId == 241 then
            return true
        end
        -- Party / M+ / timewalking party / delve-ish small group
        if difficultyId == 1 or difficultyId == 2 or difficultyId == 8 or difficultyId == 23
            or difficultyId == 24 or difficultyId == 150 or difficultyId == 205
            or difficultyId == 208 or difficultyId == 236 then
            return false
        end
    end

    if type(maxPlayers) == "number" and maxPlayers > 0
        and not (issecretvalue and issecretvalue(maxPlayers)) then
        if maxPlayers <= 5 then return false end
        if maxPlayers >= 10 then return true end
    end

    return nil
end

---Only lockouts with a known future reset time (resetAt) count as active.
---@return boolean
local function SavedLockoutRowIsActive(lockout, nowS)
    if not lockout or type(nowS) ~= "number" then return false end
    local ra = lockout.resetAt
    if type(ra) ~= "number" then return false end
    if issecretvalue and issecretvalue(ra) then return false end
    return ra > nowS
end

---@return table[]
local function HydrateSavedLockoutsForChar(rawMap, isRaidFlag)
    local hydrated = {}
    local nowS = (GetServerTime and GetServerTime()) or time()
    for instanceID, lockout in pairs(rawMap or {}) do
        if SavedLockoutRowIsActive(lockout, nowS) then
            local displayInstanceID = lockout.instanceID or instanceID
            local difficultyName
            if lockout.difficulty and GetDifficultyInfo then
                difficultyName = GetDifficultyInfo(lockout.difficulty)
            end
            hydrated[#hydrated + 1] = {
                instanceID = displayInstanceID,
                name = lockout.name or ("Instance #" .. tostring(displayInstanceID)),
                difficulty = lockout.difficulty,
                difficultyName = difficultyName or lockout.difficultyName or "Unknown",
                reset = lockout.reset,
                resetAt = lockout.resetAt,
                extended = lockout.extended or false,
                numEncounters = lockout.numEncounters,
                encounterProgress = lockout.encounterProgress,
                encounters = lockout.encounters or {},
                progress = lockout.encounterProgress or 0,
                total = lockout.numEncounters or 0,
                isRaid = isRaidFlag,
            }
        end
    end
    table.sort(hydrated, CmpNameSort)
    return hydrated
end

local function BuildAffixSignature(pveCache)
    local mp = pveCache and pveCache.mythicPlus
    local aff = mp and mp.currentAffixes
    if type(aff) ~= "table" or #aff == 0 then return "" end
    local ids = {}
    for i = 1, #aff do
        local v = aff[i]
        local id = (type(v) == "table" and v.id) or v
        id = tonumber(id)
        if id and id > 0 then
            ids[#ids + 1] = id
        end
    end
    table.sort(ids)
    local parts = {}
    for i = 1, #ids do
        parts[i] = tostring(ids[i])
    end
    return table.concat(parts, ",")
end

local function BuildRunsSignature(runHistory)
    if type(runHistory) ~= "table" or #runHistory == 0 then return "" end
    local parts = {}
    for i = 1, #runHistory do
        local r = runHistory[i]
        if r then
            parts[#parts + 1] = tostring(r.level or 0) .. ":" .. tostring(r.dungeon or "") .. ":" .. ((r.timed and "1") or "0")
        end
    end
    return table.concat(parts, "|")
end

local WEEK_SECONDS = 7 * 86400

---Snap a reset epoch (stored or computed) to the minute; see ResetService.NormalizeResetEpoch.
---@param epoch any
---@return number|nil
local function NormalizeResetEpoch(epoch)
    if ns.NormalizeResetEpoch then return ns.NormalizeResetEpoch(epoch) end
    epoch = tonumber(epoch)
    if not epoch or epoch <= 0 then return epoch end
    return math.floor((epoch + 30) / 60) * 60
end

---Best-effort weekly reset start timestamp (epoch seconds), minute-normalized.
---@return number|nil
local function GetCurrentWeeklyResetStartTime()
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and GetServerTime then
        local secsUntil = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if secsUntil ~= nil and secsUntil >= 0 then
            return NormalizeResetEpoch(GetServerTime() + secsUntil - WEEK_SECONDS)
        end
    end
    if WarbandNexus and WarbandNexus.GetWeeklyResetTime then
        local nextReset = WarbandNexus:GetWeeklyResetTime()
        if nextReset and nextReset > 0 then
            return NormalizeResetEpoch(nextReset - WEEK_SECONDS)
        end
    end
    return nil
end
ns.GetCurrentWeeklyResetStartTime = GetCurrentWeeklyResetStartTime

---Live read of the Tormented Soul aura on the player (pcall + secret guards).
---C_UnitAuras.GetPlayerAuraBySpellID returns AuraData or nil; the return is secret while unit aura
---access is restricted (warcraft.wiki.gg, verified 2026-10-15).
---@return boolean|nil active nil when unknown (API missing / secret)
---@return number|nil appliedAt epoch seconds derived from expirationTime - duration, when readable
local function ReadTormentedSoulAura()
    local C = ns.Constants
    local spellID = C and C.PVE_TORMENTED_SOUL_SPELL_ID
    if not spellID or not (C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID) then return nil, nil end
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if not ok then return nil, nil end
    if issecretvalue and issecretvalue(aura) then return nil, nil end
    if aura == nil then return false, nil end
    if type(aura) ~= "table" then return nil, nil end
    local appliedAt
    local exp, dur = aura.expirationTime, aura.duration
    if GetTime and not (issecretvalue and (issecretvalue(exp) or issecretvalue(dur)))
        and exp ~= nil and dur ~= nil
        and type(exp) == "number" and type(dur) == "number" and exp > 0 and dur > 0 then
        appliedAt = time() - (GetTime() - (exp - dur))
    end
    return true, appliedAt
end

---Derive the weekly Tormented Soul state from a per-character delve snapshot.
---"available" = not used since the weekly reset; "pending" = used this week, aura still up;
---"done" = used this week, aura consumed/expired. nil = never snapshotted.
---@param delveChar table|nil
---@param liveActive boolean|nil live aura state (logged-in character only); overrides the snapshot
---@return string|nil
local function ResolveTormentedSoulStatus(delveChar, liveActive)
    if type(delveChar) ~= "table" then return nil end
    local usedAt = tonumber(delveChar.tormentedSoulUsedAt)
    local resetStart = GetCurrentWeeklyResetStartTime()
    if not usedAt or (resetStart and resetStart > 0 and usedAt < resetStart) then
        if delveChar.lastUpdate == nil then return nil end
        return "available"
    end
    if liveActive ~= nil then
        return liveActive and "pending" or "done"
    end
    local C = ns.Constants
    local maxAge = (C and C.PVE_TORMENTED_SOUL_BUFF_MAX_SECONDS) or 86400
    if delveChar.tormentedSoulBuffActive == true and (time() - usedAt) < maxAge then
        return "pending"
    end
    return "done"
end

---Build a compact change signature for current character PvE UI payload.
---@return string
local function BuildPvESignature(pveCache, charKey)
    local mp = pveCache and pveCache.mythicPlus
    local gv = pveCache and pveCache.greatVault
    local lo = pveCache and pveCache.lockouts
    local delves = pveCache and pveCache.delves

    local key = mp and mp.keystones and mp.keystones[charKey]
    local keySig = tostring(key and key.level or 0) .. ":" .. tostring(key and key.mapID or 0)

    local ds = mp and mp.dungeonScores and mp.dungeonScores[charKey]
    local overall = ds and tonumber(ds.overallScore) or 0
    local dungeonCount = 0
    local dungeonSum = 0
    if ds and type(ds.dungeons) == "table" then
        for _, row in pairs(ds.dungeons) do
            dungeonCount = dungeonCount + 1
            dungeonSum = dungeonSum + tonumber((row and row.score) or 0) + tonumber((row and row.bestLevel) or 0)
        end
    end

    local rewards = gv and gv.rewards and gv.rewards[charKey]
    local rewardSig = rewards and rewards.hasAvailableRewards and "1" or "0"
    -- Include claimedResetTime so a claim transition (false→claimedResetTime set) fires PVE_UPDATED
    -- even when hasAvailableRewards was already false (e.g. post-reset unclaimed chest case).
    local claimedSig = tostring(rewards and rewards.claimedResetTime or 0)
    -- Include claimedAt so a claim still refreshes when claimedResetTime is unchanged (same reset week).
    local claimedAtSig = tostring(rewards and rewards.claimedAt or 0)

    local acts = gv and gv.activities and gv.activities[charKey]
    local raidN = acts and acts.raids and #acts.raids or 0
    local mPlusN = acts and acts.mythicPlus and #acts.mythicPlus or 0
    local pvpN = acts and acts.pvp and #acts.pvp or 0
    local worldN = acts and acts.world and #acts.world or 0
    local postResetSig = acts and acts.isPostReset and "1" or "0"
    local vaultILvlSig = "0"
    if acts then
        local ilvlParts = {}
        local ilvlCats = {"raids", "mythicPlus", "pvp", "world"}
        for ci = 1, #ilvlCats do
            local list = acts[ilvlCats[ci]]
            if list then
                for i = 1, #list do
                    local a = list[i]
                    if a then
                        ilvlParts[#ilvlParts + 1] = tostring(a.rewardItemLevel or 0)
                        ilvlParts[#ilvlParts + 1] = tostring(a.nextLevelIlvl or 0)
                        ilvlParts[#ilvlParts + 1] = tostring(a.maxIlvl or 0)
                    end
                end
            end
        end
        if #ilvlParts > 0 then
            vaultILvlSig = table.concat(ilvlParts, ",")
        end
    end

    local runSig = BuildRunsSignature(mp and mp.runHistory and mp.runHistory[charKey])
    local affSig = BuildAffixSignature(pveCache)

    local lockN = 0
    if lo and lo.raids and type(lo.raids[charKey]) == "table" then
        for _ in pairs(lo.raids[charKey]) do lockN = lockN + 1 end
    end

    local wbN = 0
    if lo and lo.worldBosses and type(lo.worldBosses[charKey]) == "table" then
        for k in pairs(lo.worldBosses[charKey]) do
            if type(k) == "number" then wbN = wbN + 1 end
        end
    end

    local delveChar = delves and delves.characters and delves.characters[charKey]
    local resetStart = GetCurrentWeeklyResetStartTime()
    local isDelveStale = resetStart and resetStart > 0 and (delveChar and delveChar.lastUpdate or 0) < resetStart
    local delveSig = tostring(delves and delves.season or 0)
        .. ":" .. ((delveChar and not isDelveStale and delveChar.bountifulComplete) and "1" or "0")
        .. ":" .. ((delveChar and not isDelveStale and delveChar.crackedKeystoneComplete) and "1" or "0")
        .. ":" .. ((delveChar and not isDelveStale and delveChar.nightmareTaskComplete) and "1" or "0")
        .. ":" .. ((delveChar and not isDelveStale and delveChar.purgingVaultsComplete) and "1" or "0")
        .. ":" .. ((delveChar and not isDelveStale and delveChar.delveNemesisComplete) and "1" or "0")
        .. ":" .. tostring(ResolveTormentedSoulStatus(delveChar, nil) or "-")
        .. ":" .. tostring((not isDelveStale and delveChar and delveChar.gildedStashes) or (isDelveStale and 0) or -1)
        .. ":" .. tostring(delves and delves.companion and delves.companion.renownLevel or 0)

    return table.concat({
        keySig,
        tostring(overall),
        tostring(dungeonCount),
        tostring(dungeonSum),
        rewardSig,
        claimedSig,
        claimedAtSig,
        tostring(raidN), tostring(mPlusN), tostring(pvpN), tostring(worldN),
        postResetSig,
        vaultILvlSig,
        tostring(lockN), tostring(wbN),
        delveSig,
        affSig,
        runSig,
    }, ";")
end

---Prune keystones that belong to a previous weekly cycle.
---Runs on init/update so stale keys never survive a weekly reset.
local function PruneExpiredKeystonesForWeeklyReset()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.pveCache then
        return 0
    end
    local mp = WarbandNexus.db.global.pveCache.mythicPlus
    if not mp then return 0 end
    if not mp.keystones then
        mp.keystones = {}
        return 0
    end

    local resetStart = GetCurrentWeeklyResetStartTime()
    local removed = 0
    for key, data in pairs(mp.keystones) do
        local stamp = type(data) == "table" and data.lastUpdate or nil
        local stale = false
        if resetStart and resetStart > 0 then
            stale = type(stamp) ~= "number" or stamp < resetStart
        elseif WarbandNexus.HasWeeklyResetOccurred then
            stale = type(stamp) ~= "number" or WarbandNexus:HasWeeklyResetOccurred(stamp)
        end
        if stale then
            mp.keystones[key] = nil
            removed = removed + 1
        end
    end

    if resetStart and resetStart > 0 then
        mp.lastKeystoneWeeklyReset = resetStart
    end
    return removed
end

---Prune world boss kills that belong to a previous weekly cycle.
---Runs on init/update so stale kills never survive a weekly reset.
local function PruneExpiredWorldBossesForWeeklyReset()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.pveCache then
        return 0
    end
    local lo = WarbandNexus.db.global.pveCache.lockouts
    if not lo or not lo.worldBosses then return 0 end

    local resetStart = GetCurrentWeeklyResetStartTime()
    local removed = 0
    for charKey, data in pairs(lo.worldBosses) do
        local stamp = type(data) == "table" and data.lastUpdate or nil
        local stale = false
        if resetStart and resetStart > 0 then
            stale = type(stamp) ~= "number" or stamp < resetStart
        elseif WarbandNexus.HasWeeklyResetOccurredSince then
            stale = type(stamp) ~= "number" or WarbandNexus:HasWeeklyResetOccurredSince(stamp)
        end
        if stale then
            lo.worldBosses[charKey] = nil
            removed = removed + 1
        end
    end
    return removed
end

---Prune Delve weekly progress (bounties, weekly quests, gilded stashes) for a new weekly cycle.
local function PruneExpiredDelvesForWeeklyReset()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.pveCache then
        return 0
    end
    local d = WarbandNexus.db.global.pveCache.delves
    if not d or not d.characters then return 0 end

    local resetStart = GetCurrentWeeklyResetStartTime()
    local updated = 0
    for charKey, delveChar in pairs(d.characters) do
        if type(delveChar) == "table" then
            local stamp = delveChar.lastUpdate
            local stale = false
            if resetStart and resetStart > 0 then
                stale = type(stamp) ~= "number" or stamp < resetStart
            elseif WarbandNexus.HasWeeklyResetOccurredSince then
                stale = type(stamp) ~= "number" or WarbandNexus:HasWeeklyResetOccurredSince(stamp)
            end
            if stale then
                delveChar.bountifulComplete = false
                delveChar.gildedStashes = 0
                delveChar.crackedKeystoneComplete = false
                delveChar.nightmareTaskComplete = false
                delveChar.purgingVaultsComplete = false
                delveChar.delveNemesisComplete = false
                -- Tormented Soul: once per week per character. Keep a use stamped after this reset
                -- (cast recorded before the next snapshot refreshed lastUpdate).
                local usedAt = tonumber(delveChar.tormentedSoulUsedAt)
                if not (usedAt and resetStart and resetStart > 0 and usedAt >= resetStart) then
                    delveChar.tormentedSoulUsedAt = nil
                    delveChar.tormentedSoulBuffActive = false
                end
                updated = updated + 1
            end
        end
    end
    return updated
end

---Prune Mythic+ run history that belongs to a previous weekly cycle.
local function PruneExpiredRunHistoryForWeeklyReset()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.pveCache then
        return 0
    end
    local mp = WarbandNexus.db.global.pveCache.mythicPlus
    if not mp or not mp.runHistory then return 0 end

    local resetStart = GetCurrentWeeklyResetStartTime()
    local removed = 0
    local weeks = mp.runHistoryWeek or {}
    for charKey in pairs(mp.runHistory) do
        local weekRecorded = weeks[charKey]
        local stale = false
        if resetStart and resetStart > 0 then
            stale = type(weekRecorded) ~= "number" or weekRecorded < (resetStart - 60)
        elseif WarbandNexus.HasWeeklyResetOccurredSince then
            stale = type(weekRecorded) ~= "number" or WarbandNexus:HasWeeklyResetOccurredSince(weekRecorded)
        end
        if stale then
            mp.runHistory[charKey] = nil
            weeks[charKey] = nil
            removed = removed + 1
        end
    end
    mp.runHistoryWeek = weeks
    return removed
end

local function PruneAllPvEWeeklyData()
    local count = 0
    count = count + (PruneExpiredKeystonesForWeeklyReset() or 0)
    count = count + (PruneExpiredWorldBossesForWeeklyReset() or 0)
    count = count + (PruneExpiredDelvesForWeeklyReset() or 0)
    count = count + (PruneExpiredRunHistoryForWeeklyReset() or 0)
    return count
end

WarbandNexus.PruneAllPvEWeeklyData = PruneAllPvEWeeklyData
ns.PruneAllPvEWeeklyData = PruneAllPvEWeeklyData

---Drop Mythic+ score buckets when the season rolls over.
---Scores are season-scoped: C_MythicPlus.GetSeasonBestForMap only ever reports runs from the
---running season, so on a flip every map reads back empty. UpdateDungeonScores deliberately
---refuses to overwrite a populated row with an all-zero snapshot (login / API races), which would
---otherwise freeze last season's scores on screen until that exact dungeon is re-run.
---GetCurrentSeason returns -1 until RequestMapInfo has been called at least once, and 0 when no
---season is running (warcraft.wiki.gg/wiki/API_C_MythicPlus.GetCurrentSeason, verified 2026-08-19)
---- both are treated as "not known yet" and leave the cache untouched.
---@return boolean cleared true when a rollover was detected and the score buckets were dropped
local function ApplyMythicPlusSeasonRollover()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global or not WarbandNexus.db.global.pveCache then
        return false
    end
    local mp = WarbandNexus.db.global.pveCache.mythicPlus
    if not mp then return false end
    if not C_MythicPlus or not C_MythicPlus.GetCurrentSeason then return false end

    local ok, seasonID = pcall(C_MythicPlus.GetCurrentSeason)
    if not ok or type(seasonID) ~= "number" or seasonID <= 0 then
        return false
    end

    local stored = tonumber(mp.season) or 0
    if stored == seasonID then return false end
    mp.season = seasonID

    -- stored == 0 means the cache predates this stamp, so there is no way to tell which season
    -- wrote it - and the stamp shipped in the same build that Season 2 opened in, so in practice
    -- every unstamped cache holds Season 1 scores. Treat unknown as stale rather than trusting it:
    -- the current character re-scans immediately, and an alt showing nothing beats an alt showing
    -- a rating it no longer has.
    -- Every stored score belongs to the previous season, alts included, so drop them all.
    if type(mp.dungeonScores) == "table" then wipe(mp.dungeonScores) else mp.dungeonScores = {} end
    if type(mp.bestRuns) == "table" then wipe(mp.bestRuns) else mp.bestRuns = {} end
    if type(mp.currentAffixes) == "table" then wipe(mp.currentAffixes) end

    DebugPrint("|cff9370DB[PvECache]|r Mythic+ season "
        .. (stored == 0 and "stamped -> " or ("rollover " .. tostring(stored) .. " -> "))
        .. tostring(seasonID) .. "; dungeon scores and best runs cleared")
    return true
end

-- CONSTANTS

local Constants = ns.Constants
local CACHE_VERSION = Constants.PVE_CACHE_VERSION
local UPDATE_THROTTLE = Constants.THROTTLE.SHARED_RARE
local GreatVaultActivityHasRows
local GreatVaultActivityHasCompletedRows
local ShouldPreserveCompletedVaultRows
local LegacyGreatVaultArrayHasCompleted

---Midnight-safe quest completion check (pcall + secret guard).
---@return boolean
local function SafeIsQuestFlaggedCompleted(questID)
    if not questID or type(questID) ~= "number" then return false end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if issecretvalue and issecretvalue(done) then return false end
    if not ok or done == nil then return false end
    return done == true
end

--- Parse "2 / 4" style progress from Delves UI copy (guards Midnight secret strings).
---@return number|nil current
---@return number|nil weeklyMax
local function ParseGildedStashFraction(text)
    if issecretvalue and issecretvalue(text) then return nil, nil end
    if text == nil then return nil, nil end
    if text == "" then return nil, nil end
    local cur, max = text:match("(%d+)%s*/%s*(%d+)")
    if not cur then return nil, nil end
    return tonumber(cur), tonumber(max)
end

--- Collect candidate strings from a spell-display widget payload.
local function CollectGildedStashWidgetTexts(widget)
    local out = {}
    if not widget then return out end
    local spellInfo = widget.spellInfo
    if spellInfo then
        local fields = {
            spellInfo.tooltip,
            spellInfo.text,
            spellInfo.header,
            spellInfo.headerText,
            spellInfo.description,
            spellInfo.subText,
        }
        for i = 1, #fields do
            local v = fields[i]
            if v and not (issecretvalue and issecretvalue(v)) and v ~= "" then
                out[#out + 1] = v
            end
        end
    end
    if widget.text and not (issecretvalue and issecretvalue(widget.text)) and widget.text ~= "" then
        out[#out + 1] = widget.text
    end
    return out
end

--- Read Gilded Stash weekly progress from Delves UI (widget 7591) or spell tooltip lines.
local function GetGildedStashCounts()
    local weeklyMax = (Constants and Constants.PVE_GILDED_STASH_WEEKLY_MAX) or 4
    local widgetID = (Constants and Constants.PVE_GILDED_STASH_WIDGET_ID) or 7591
    local spellID = (Constants and Constants.PVE_GILDED_STASH_SPELL_ID) or 1216211
    local current = -1

    if C_UIWidgetManager and C_UIWidgetManager.GetSpellDisplayVisualizationInfo then
        local ok, widget = pcall(C_UIWidgetManager.GetSpellDisplayVisualizationInfo, widgetID)
        if ok and widget then
            local texts = CollectGildedStashWidgetTexts(widget)
            for ti = 1, #texts do
                local cur, max = ParseGildedStashFraction(texts[ti])
                if cur ~= nil then
                    current = cur
                    if max and max > 0 then weeklyMax = max end
                    break
                end
            end
        end
    end

    if current < 0 and C_TooltipInfo and C_TooltipInfo.GetSpellByID then
        local ok, data = pcall(C_TooltipInfo.GetSpellByID, spellID)
        if ok and data and data.lines then
            for li = 1, #data.lines do
                local line = data.lines[li]
                local left = line and (line.leftText or line.leftString)
                local right = line and line.rightText
                local cur, max = ParseGildedStashFraction(left)
                if cur == nil then
                    cur, max = ParseGildedStashFraction(right)
                end
                if cur == nil and left and right
                    and not (issecretvalue and (issecretvalue(left) or issecretvalue(right))) then
                    cur, max = ParseGildedStashFraction(tostring(left) .. " " .. tostring(right))
                end
                if cur ~= nil then
                    current = cur
                    if max and max > 0 then weeklyMax = max end
                    break
                end
            end
        end
    end

    return current, weeklyMax
end

--- Resolve the Delves companion's level and display name.
--- The companion is NOT always a major faction: in Midnight 12.x it is a *friendship*
--- faction (Valeera Sanguinar, factionID 2744, verified 2026-08-30 against live
--- reputationData), so C_MajorFactions.GetMajorFactionData returns nil for it and the
--- renown-only branch left companion.renownLevel / companion.name unwritten forever.
--- Major faction is still tried first so a future renown-based companion keeps working.
---@param factionID number
---@return number|nil level current renown level or friendship rank
---@return number|nil maxLevel only known for friendship companions
---@return string|nil name
local function GetCompanionLevelInfo(factionID)
    local level, maxLevel, name

    if C_Reputation and C_Reputation.IsMajorFaction and C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local okMajor, isMajor = pcall(C_Reputation.IsMajorFaction, factionID)
        if okMajor and isMajor then
            local ok, majorData = pcall(C_MajorFactions.GetMajorFactionData, factionID)
            if ok and majorData then
                level = majorData.renownLevel
                name = majorData.name
            end
        end
    end

    -- Friendship companion: rank lives on the gossip ranks API, not on renown.
    if level == nil and C_GossipInfo and C_GossipInfo.GetFriendshipReputationRanks then
        local ok, ranks = pcall(C_GossipInfo.GetFriendshipReputationRanks, factionID)
        if ok and ranks and (tonumber(ranks.maxLevel) or 0) > 0 then
            level = ranks.currentLevel
            maxLevel = ranks.maxLevel
        end
    end

    if not name and C_Reputation and C_Reputation.GetFactionDataByID then
        local ok, data = pcall(C_Reputation.GetFactionDataByID, factionID)
        if ok and data and data.name and not (issecretvalue and issecretvalue(data.name)) then
            name = data.name
        end
    end

    return level, maxLevel, name
end

-- Persisted in db.global.pveCache (no separate RAM mirror).

-- Throttle timers
local lastUpdateTime = 0
local pendingUpdate = false
local pvePendingUpdateTimer = nil
local keystoneRetryPending = {}
local keystoneRetryCount = {}
local keystoneZeroSeenAt = {}
local keystoneRefreshLastAt = {}
local keystoneWarmupLastAt = {}
local KEYSTONE_REFRESH_MIN_INTERVAL = 3.0
local KEYSTONE_WARMUP_COOLDOWN = 5.0
-- High-priority reasons bypass RequestKeystoneRefresh throttle (loot / maps / pedestal).
local KEYSTONE_REFRESH_HIGH_PRIORITY = {
    CHAT_MSG_LOOT = true,
    OnKeystoneChanged = true,
    CHALLENGE_MODE_MAPS_UPDATE = true,
    vaultClaim = true,
}
-- Track last observed (level, mapID) per char so repeated identical API results
-- (very common: UPDATE_INSTANCE_INFO + CHALLENGE_MODE_MAPS_UPDATE bursts during
-- reload/zone all read the same values) become no-ops instead of re-running the
-- write/log path. Stored as "level|mapID" strings; nil API → "nil|nil".
local keystoneLastSeen = {}

local KEYSTONE_ZERO_CONFIRM_SECONDS = 2
local KEYSTONE_RETRY_MAX = 3
local KEYSTONE_RETRY_DELAYS = { 0.5, 1.2, 2.5 }

---@param message string
---@return boolean
local function LootMessageIsMythicKeystone(message)
    if not message or type(message) ~= "string" then return false end
    if issecretvalue and issecretvalue(message) then return false end
    -- Wiki: CHAT_MSG_LOOT arg1 is loot text with item hyperlink (may be secret in secure contexts).
    if message:find("|Hkeystone:", 1, true) then return true end
    local itemID = tonumber(message:match("|Hitem:(%d+):"))
    if itemID and C_Item and C_Item.IsItemKeystoneByID then
        local ok, isKs = pcall(C_Item.IsItemKeystoneByID, itemID)
        if ok and isKs then return true end
    end
    local name = message:match("%[(.-)%]")
    if name and not (issecretvalue and issecretvalue(name)) and name:find("Keystone", 1, true) then
        return true
    end
    return false
end

---Self-loot only: CHAT_MSG_LOOT arg2 is author (wiki); guard secrets before string ops.
---@param author string|nil
---@return boolean
local function ChatLootAuthorIsPlayer(author)
    local playerName = UnitName("player")
    if not playerName or (issecretvalue and issecretvalue(playerName)) then return false end
    -- Secret check first: comparing a secret value (even with "") is itself disallowed.
    if issecretvalue and issecretvalue(author) then return false end
    if author == nil or author == "" then return true end
    local authorBase = author:match("^([^%-]+)") or author
    return author == playerName or authorBase == playerName
end

-- INITIALIZATION

---Initialize PvE cache from DB
---Called on addon load to restore previous scan results
function WarbandNexus:InitializePvECache()
    if not self.db.global.pveCache then
        self.db.global.pveCache = {
            mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {}, season = 0 },
            greatVault = { activities = {}, rewards = {} },
            lockouts = { raids = {}, dungeons = {}, worldBosses = {} },
            delves = { companion = {}, season = 0 },
            version = CACHE_VERSION,
            lastUpdate = 0,
        }
        return
    end
    
    -- Non-destructive version migration.
    -- Bumping CACHE_VERSION must NOT wipe per-character Great Vault / keystone data,
    -- otherwise alts show empty until each one is logged into and re-scanned.
    -- The current character's data is refreshed on PLAYER_LOGIN regardless; for alts
    -- we keep whatever is already stored and just ensure the expected sub-tables exist.
    local cache = self.db.global.pveCache
    cache.mythicPlus = cache.mythicPlus or { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {}, season = 0 }
    cache.mythicPlus.currentAffixes = cache.mythicPlus.currentAffixes or {}
    cache.mythicPlus.keystones      = cache.mythicPlus.keystones      or {}
    cache.mythicPlus.bestRuns       = cache.mythicPlus.bestRuns       or {}
    cache.mythicPlus.dungeonScores  = cache.mythicPlus.dungeonScores  or {}
    -- Season the stored scores belong to; 0 = never stamped (see ApplyMythicPlusSeasonRollover).
    cache.mythicPlus.season         = tonumber(cache.mythicPlus.season) or 0

    cache.greatVault = cache.greatVault or { activities = {}, rewards = {} }
    cache.greatVault.activities = cache.greatVault.activities or {}
    cache.greatVault.rewards    = cache.greatVault.rewards    or {}

    cache.lockouts = cache.lockouts or { raids = {}, dungeons = {}, worldBosses = {} }
    cache.lockouts.raids       = cache.lockouts.raids       or {}
    cache.lockouts.dungeons    = cache.lockouts.dungeons    or {}
    cache.lockouts.worldBosses = cache.lockouts.worldBosses or {}

    cache.delves = cache.delves or { companion = {}, season = 0 }
    cache.delves.companion = cache.delves.companion or {}
    cache.delves.season    = cache.delves.season    or 0

    cache.version = CACHE_VERSION
    cache.lastUpdate = cache.lastUpdate or 0

    -- Weekly hygiene: do not keep stale pre-reset data across sessions.
    PruneAllPvEWeeklyData()
    
    -- Validate and clear corrupted vault data
    -- Each character should have max 3 activities per type (raids, mythicPlus, pvp, world)
    if self.db.global.pveCache.greatVault and self.db.global.pveCache.greatVault.activities then
        for charKey, charData in pairs(self.db.global.pveCache.greatVault.activities) do
            if charData.raids and #charData.raids > 9 then
                self.db.global.pveCache.greatVault.activities[charKey] = nil
            elseif charData.mythicPlus and #charData.mythicPlus > 9 then
                self.db.global.pveCache.greatVault.activities[charKey] = nil
            elseif charData.world and #charData.world > 9 then
                self.db.global.pveCache.greatVault.activities[charKey] = nil
            end
        end
    end
    
    self:LiftLegacyPveProgressToCache()
end

--- One-time import of db.global.pveProgress rows into pveCache (authoritative store).
---@return number lifted Row count processed
function WarbandNexus:LiftLegacyPveProgressToCache()
    if not self.db or not self.db.global then return 0 end
    if self.db.global._pveProgressLiftV1 then return 0 end

    local legacy = self.db.global.pveProgress
    if type(legacy) ~= "table" or not next(legacy) then
        self.db.global._pveProgressLiftV1 = true
        return 0
    end

    local lifted = 0
    for charKey, progress in pairs(legacy) do
        if type(progress) == "table" and self.ImportLegacyPvEData then
            self:ImportLegacyPvEData(charKey, progress)
            lifted = lifted + 1
        end
    end

    self.db.global._pveProgressLiftV1 = true
    if lifted > 0 and DebugPrint then
        DebugPrint(string.format("|cff9370DB[PvECache]|r Lifted %d legacy pveProgress row(s) into pveCache", lifted))
    end
    return lifted
end

---Save PvE cache to DB
function WarbandNexus:SavePvECache()
    if not self.db or not self.db.global or not self.db.global.pveCache then
        return
    end
    
    -- Update metadata (data is already in DB from direct writes)
    self.db.global.pveCache.version = CACHE_VERSION
    self.db.global.pveCache.lastUpdate = time()
    
end

---True if a dungeonScores bucket has any non-zero progress (used to avoid wiping API race zeros).
local function DungeonScoresBucketHasProgress(scoreEntry)
    if not scoreEntry then return false end
    if type(scoreEntry.overallScore) == "number" and scoreEntry.overallScore > 0 then return true end
    local dungeons = scoreEntry.dungeons
    if type(dungeons) ~= "table" then return false end
    for _, row in pairs(dungeons) do
        if row then
            if (type(row.score) == "number" and row.score > 0) or (type(row.bestLevel) == "number" and row.bestLevel > 0) then
                return true
            end
        end
    end
    return false
end

-- LOCKOUT DATA

---Update saved instance lockouts (raids + dungeons) for current character
function WarbandNexus:UpdateRaidLockouts(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    if not self.db.global.pveCache.lockouts.raids then
        self.db.global.pveCache.lockouts.raids = {}
    end
    if not self.db.global.pveCache.lockouts.dungeons then
        self.db.global.pveCache.lockouts.dungeons = {}
    end

    local numSavedInstances = GetNumSavedInstances()
    if not numSavedInstances or numSavedInstances == 0 then
        -- Saved-instance list not loaded yet this session: keep the stored lockouts.
        if not instanceInfoSeenThisSession then return end
        self.db.global.pveCache.lockouts.raids[charKey] = {}
        self.db.global.pveCache.lockouts.dungeons[charKey] = {}
        return
    end

    self.db.global.pveCache.lockouts.raids[charKey] = {}
    self.db.global.pveCache.lockouts.dungeons[charKey] = {}

    local nowServer = (GetServerTime and GetServerTime()) or time()

    for i = 1, numSavedInstances do
        -- 13=extendDisabled, 14=instanceId (10.0.5+); keep full tail so encounter fields stay aligned.
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress, _extDis, _instId = GetSavedInstanceInfo(i)

        if issecretvalue and name and issecretvalue(name) then name = nil end
        if issecretvalue and difficulty and issecretvalue(difficulty) then difficulty = nil end
        if issecretvalue and difficultyName and issecretvalue(difficultyName) then difficultyName = nil end
        if issecretvalue and issecretvalue(locked) then locked = nil end
        if issecretvalue and issecretvalue(extended) then extended = nil end

        local difficultyID = SafeSavedInstanceNumber(difficulty)
        local journalInstanceID = SafeSavedInstanceNumber(_instId)
        local numEncountersSafe = SafeSavedInstanceNumber(numEncounters)
        local encProg = SafeSavedInstanceNumber(encounterProgress)
        local hasBossProgress = encProg and encProg > 0
        -- Some 5-player rows report locked=false while still on the saved list; boss progress implies a real lock.
        local lockedFlag = locked == true or locked == 1
        local extendedFlag = extended == true or extended == 1
        local activeLock = lockedFlag or extendedFlag or hasBossProgress
        if not name or not activeLock then
            -- Nothing to track for this row.
        else
            local resetSec = SafeSavedInstanceNumber(reset)
            -- Do not persist expired lockouts (GetSavedInstanceInfo reset is seconds until weekly reset).
            if not resetSec or resetSec <= 0 then
                -- Skip: already reset or no countdown.
            else
                local raidFlag = CoerceSavedInstanceIsRaid(isRaid, maxPlayers, difficultyID)
                local storageKey = BuildSavedInstanceStorageKey(i, id, journalInstanceID, difficultyID)
                local encounters = BuildSavedInstanceEncounterList(i, numEncountersSafe)
                local row = {
                    name = name,
                    instanceID = journalInstanceID,
                    difficulty = difficultyID,
                    difficultyName = difficultyName,
                    reset = resetSec,
                    resetAt = nowServer + resetSec,
                    extended = extendedFlag,
                    numEncounters = numEncountersSafe,
                    encounterProgress = encProg,
                    encounters = encounters,
                }
                if raidFlag == true then
                    self.db.global.pveCache.lockouts.raids[charKey][storageKey] = row
                elseif raidFlag == false then
                    self.db.global.pveCache.lockouts.dungeons[charKey][storageKey] = row
                end
                -- raidFlag nil: could not classify safely; skip.
            end
        end
    end
end

---Update world boss kills for current character
function WarbandNexus:UpdateWorldBossKills(charKey)
    if not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    -- World boss kills tracked via quest completion
    -- Midnight 12.0.5 world boss quest IDs
    local worldBossQuests = {
        93913, -- Midnight: World Boss (Quel'Thalas weekly world boss)
    }
    
    if not self.db.global.pveCache.lockouts.worldBosses then
        self.db.global.pveCache.lockouts.worldBosses = {}
    end
    
    -- A kill recorded earlier this reset period stays recorded: an unready or secret quest read
    -- (login burst, instance) must not turn it back into "not killed" for the rest of the week.
    local prev = self.db.global.pveCache.lockouts.worldBosses[charKey]
    local resetStart = GetCurrentWeeklyResetStartTime()
    local keepKills = type(prev) == "table" and resetStart and resetStart > 0
        and (tonumber(prev.lastUpdate) or 0) >= resetStart

    local row = { lastUpdate = time() }
    for i = 1, #worldBossQuests do
        local questID = worldBossQuests[i]
        if SafeIsQuestFlaggedCompleted(questID) or (keepKills and prev[questID] == true) then
            row[questID] = true
        end
    end
    self.db.global.pveCache.lockouts.worldBosses[charKey] = row
end

-- DELVES DATA

---True if any configured Bountiful / Trovehunter weekly quest is flagged complete for the **current** client session.
---Call only while the relevant character is logged in; PvE UI uses per-char cache from UpdateDelvesData for other rows.
---@return boolean
function WarbandNexus:IsBountifulDelveWeeklyDone()
    local ids = Constants.PVE_BOUNTIFUL_WEEKLY_QUEST_IDS
    if not ids or #ids == 0 then return false end
    for i = 1, #ids do
        local qid = ids[i]
        if qid and SafeIsQuestFlaggedCompleted(qid) then
            return true
        end
    end
    return false
end

---True when a PvE weekly quest is flagged complete for the **current** client session.
---Alt rows read the per-character snapshot written by UpdateDelvesData instead.
---@param questID number
---@return boolean
function WarbandNexus:IsPvEWeeklyQuestDone(questID)
    return SafeIsQuestFlaggedCompleted(tonumber(questID))
end

---Weekly Tormented Soul state for a PvE row ("available" | "pending" | "done" | nil when never snapshotted).
---The logged-in character reads the live aura; alts use the persisted snapshot + aura lifetime bound.
---@param delveChar table|nil per-character delve snapshot (GetPvEData(charKey).delves.character)
---@param isCurrentChar boolean|nil
---@return string|nil
function WarbandNexus:GetTormentedSoulStatus(delveChar, isCurrentChar)
    local liveActive
    if isCurrentChar then
        liveActive = ReadTormentedSoulAura()
    end
    return ResolveTormentedSoulStatus(delveChar, liveActive)
end

---True when the hidden daily "Looted Tormented Soul" trigger is flagged for the **current** character.
---@return boolean
function WarbandNexus:IsTormentedSoulLootedToday()
    return SafeIsQuestFlaggedCompleted(Constants.PVE_TORMENTED_SOUL_LOOT_QUEST_ID)
end

---Record a Tormented Soul use for the session character (UNIT_SPELLCAST_SUCCEEDED on 1306916).
function WarbandNexus:RecordTormentedSoulUse()
    local pveCache = self.db and self.db.global and self.db.global.pveCache
    local delves = pveCache and pveCache.delves
    if not delves then return end
    local charKey = GetSessionCanonicalPvEKey()
    if not charKey then return end
    if not delves.characters then delves.characters = {} end
    local delveChar = delves.characters[charKey]
    if not delveChar then
        delveChar = {}
        delves.characters[charKey] = delveChar
    end
    delveChar.tormentedSoulUsedAt = time()
    delveChar.tormentedSoulBuffActive = true
    DebugPrint("|cff9370DB[PvECache]|r [PvE Event] Tormented Soul used")
    if self.SendMessage and Constants.EVENTS and Constants.EVENTS.PVE_UPDATED then
        self:SendMessage(Constants.EVENTS.PVE_UPDATED, charKey)
    end
end

---Register / drop the player-only cast watcher for Tormented Soul (PvE module gate).
---UNIT_SPELLCAST_SUCCEEDED payload: unitTarget, castGUID, spellID, castBarID (warcraft.wiki.gg,
---verified 2026-10-15). Frame:RegisterUnitEvent keeps it to "player" so raid casts never wake it.
function WarbandNexus:SyncTormentedSoulCastWatcher()
    local enabled = ns.Utilities and ns.Utilities:IsModuleEnabled("pve")
    local frame = self._tormentedSoulCastFrame
    if not enabled then
        if frame then frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
        return
    end
    if not frame then
        frame = CreateFrame("Frame")
        self._tormentedSoulCastFrame = frame
        frame:SetScript("OnEvent", function(_, _, _, _, spellID)
            -- spellID can be secret while unit spellcasts are restricted; never compare a secret.
            if (issecretvalue and issecretvalue(spellID)) or spellID == nil then return end
            if spellID ~= Constants.PVE_TORMENTED_SOUL_SPELL_ID then return end
            if not (ns.Utilities and ns.Utilities:IsModuleEnabled("pve")) then return end
            if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
            WarbandNexus:RecordTormentedSoulUse()
        end)
    end
    frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
end

---Update Delves companion data (account-wide) and per-character delve progress.
---Uses C_DelvesUI APIs (Midnight 12.0+) for companion info and season tracking.
function WarbandNexus:UpdateDelvesData(charKey)
    if not self.db.global.pveCache or not self.db.global.pveCache.delves then return end
    if charKey and charKey ~= "" then
        charKey = CanonicalizePvEKey(charKey)
    end
    
    local delves = self.db.global.pveCache.delves
    
    -- Season number (account-wide)
    if C_DelvesUI and C_DelvesUI.GetCurrentDelvesSeasonNumber then
        local seasonNum = C_DelvesUI.GetCurrentDelvesSeasonNumber()
        if seasonNum and type(seasonNum) == "number" then
            delves.season = seasonNum
        end
    end
    
    -- Companion info (account-wide — same companion for all characters)
    if C_DelvesUI and C_DelvesUI.GetCompanionInfoForActivePlayer then
        local companionInfoID = C_DelvesUI.GetCompanionInfoForActivePlayer()
        if companionInfoID and not (issecretvalue and issecretvalue(companionInfoID)) then
            delves.companion.infoID = companionInfoID
        end
        
        -- Companion faction (for renown/level tracking)
        if C_DelvesUI.GetFactionForCompanion then
            local factionID = C_DelvesUI.GetFactionForCompanion()
            if factionID and type(factionID) == "number" then
                delves.companion.factionID = factionID

                -- Companion level + display name. `renownLevel` keeps its name for the
                -- existing dirty-signature / export consumers, but for a friendship
                -- companion it holds the friendship rank (see GetCompanionLevelInfo).
                -- Only write on a real read so a cold API call cannot wipe a good value.
                local level, maxLevel, factionName = GetCompanionLevelInfo(factionID)
                if level ~= nil then
                    delves.companion.renownLevel = level
                end
                if maxLevel ~= nil then
                    delves.companion.maxLevel = maxLevel
                end
                if factionName then
                    delves.companion.name = factionName
                end
            end
        end
        
        -- Companion role info
        if C_DelvesUI.GetRoleNodeForCompanion then
            local roleNodeID = C_DelvesUI.GetRoleNodeForCompanion()
            if roleNodeID and not (issecretvalue and issecretvalue(roleNodeID)) then
                delves.companion.roleNodeID = roleNodeID
            end
        end
    end
    
    delves.companion.lastUpdate = time()
    
    -- Per-character: bountiful delve quest completion
    if charKey then
        if not delves.characters then delves.characters = {} end
        if not delves.characters[charKey] then delves.characters[charKey] = {} end
        
        -- Weekly completion flags only rise inside one reset period. SafeIsQuestFlaggedCompleted
        -- reports "unknown" (unready login read, secret, pcall error) as false; without this floor
        -- one such read turned a done weekly back into "not done" on every alt's PvE row.
        local dc = delves.characters[charKey]
        local flagResetStart = GetCurrentWeeklyResetStartTime()
        local keepDone = flagResetStart and flagResetStart > 0 and (tonumber(dc.lastUpdate) or 0) >= flagResetStart
        local function SetWeeklyFlag(field, done)
            dc[field] = (done == true) or (keepDone and dc[field] == true) or false
        end

        -- Bountiful / Trovehunter weeklies — snapshot for this character when they are logged in (quest API is session-local).
        SetWeeklyFlag("bountifulComplete", self.IsBountifulDelveWeeklyDone and self:IsBountifulDelveWeeklyDone())
        local gildedStashes, gildedStashesMax = GetGildedStashCounts()
        local priorGildedStashes = tonumber(delves.characters[charKey].gildedStashes)
        if gildedStashes >= 0 or priorGildedStashes == nil then
            delves.characters[charKey].gildedStashes = gildedStashes
        end
        delves.characters[charKey].gildedStashesMax = gildedStashesMax
        local crackedID = Constants.PVE_CRACKED_KEYSTONE_WEEKLY_QUEST_ID or 92600
        SetWeeklyFlag("crackedKeystoneComplete", SafeIsQuestFlaggedCompleted(crackedID))
        -- Midnight 12.1 weeklies that also award a Trovehunter's Bounty (PvE tab columns).
        local nightmareID = Constants.PVE_NIGHTMARE_TASK_WEEKLY_QUEST_ID or 94446
        SetWeeklyFlag("nightmareTaskComplete", SafeIsQuestFlaggedCompleted(nightmareID))
        local purgingID = Constants.PVE_PURGING_VAULTS_WEEKLY_QUEST_ID or 95520
        SetWeeklyFlag("purgingVaultsComplete", SafeIsQuestFlaggedCompleted(purgingID))
        local nemesisID = Constants.PVE_DELVE_NEMESIS_WEEKLY_QUEST_ID or 92887
        SetWeeklyFlag("delveNemesisComplete", SafeIsQuestFlaggedCompleted(nemesisID))
        -- Tormented Soul aura snapshot (alts read this; logged-in row also queries live).
        local tsChar = delves.characters[charKey]
        local tsActive, tsAppliedAt = ReadTormentedSoulAura()
        if tsActive ~= nil then
            tsChar.tormentedSoulBuffActive = tsActive
            if tsActive then
                local usedAt = tonumber(tsChar.tormentedSoulUsedAt)
                local resetStart = GetCurrentWeeklyResetStartTime()
                if not usedAt or (resetStart and resetStart > 0 and usedAt < resetStart) then
                    -- Best effort: aura is up but the cast was not seen (addon off / used on another UI).
                    -- Prefer the aura's own start time; an aura applied before this reset belongs to last week.
                    local stamp = tsAppliedAt or time()
                    if not (resetStart and resetStart > 0 and stamp < resetStart) then
                        tsChar.tormentedSoulUsedAt = stamp
                    end
                end
            end
        end
        delves.characters[charKey].lastUpdate = time()
    end
end

-- UPDATE ORCHESTRATION

---True when completed vault rows exist but reward iLvl is still zero (API warmup).
local function VaultActivitiesMissingILvl(bucket)
    if not bucket or bucket.isPostReset then
        return false
    end
    local vaultCategories = {"raids", "mythicPlus", "world"}
    for ci = 1, #vaultCategories do
        local activities = bucket[vaultCategories[ci]]
        if activities then
            for ai = 1, #activities do
                local a = activities[ai]
                if a and a.progress and a.threshold and a.progress >= a.threshold then
                    if not a.rewardItemLevel or a.rewardItemLevel == 0 then
                        return true
                    end
                end
            end
        end
    end
    return false
end

--- Skip login full PvE collect when pveCache already has a snapshot for this character.
---@return boolean
function WarbandNexus:IsPvERowPersistedWarm()
    if not self.db or not self.db.global then return false end
    local charKey = ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey
        and ns.CharacterService:ResolveSubsidiaryCharacterKey(self)
    if not charKey and ns.Utilities and ns.Utilities.GetCharacterStorageKey then
        charKey = ns.Utilities:GetCharacterStorageKey(self)
    end
    if not charKey then return false end
    local DF = ns.DataFreshness
    local ver = Constants and Constants.PVE_CACHE_VERSION
    return DF and DF.IsPvEWarm and DF.IsPvEWarm(self.db.global, ver, charKey) == true
end

---Update all PvE data for current character (throttled)
function WarbandNexus:UpdatePvEData()
    DebugPrint("|cff9370DB[PvECache]|r [PvE Action] UpdatePvEData triggered")
    -- Module gate: PvE tab, Plans (vault plans) and VaultButton all consume this data.
    if not (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then
        return
    end
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    -- Ensure DB is initialized
    if not self.db or not self.db.global or not self.db.global.pveCache then
        self:InitializePvECache()
    end
    
    -- Throttle check
    local currentTime = GetTime()
    if currentTime - lastUpdateTime < UPDATE_THROTTLE then
        pendingUpdate = true
        if not pvePendingUpdateTimer then
            local delay = UPDATE_THROTTLE - (currentTime - lastUpdateTime)
            if delay < 0.01 then delay = 0.01 end
            pvePendingUpdateTimer = C_Timer.NewTimer(delay, function()
                pvePendingUpdateTimer = nil
                if WarbandNexus and WarbandNexus.ProcessPendingPvEUpdate then
                    WarbandNexus:ProcessPendingPvEUpdate()
                end
            end)
        end
        return
    end
    
    lastUpdateTime = currentTime
    pendingUpdate = false
    
    -- Get current character key (canonical = one pveCache bucket per character)
    local charKey = GetSessionCanonicalPvEKey()
    if not charKey then return end

    local beforeSig = BuildPvESignature(self.db.global.pveCache, charKey)

    -- Ensure weekly reset stale keys/lockouts are pruned even if affix event did not fire this session.
    PruneAllPvEWeeklyData()

    -- Update all PvE data (API > DB)
    self:UpdateMythicPlusAffixes()
    self:UpdateCharacterKeystone(charKey)
    self:UpdateMythicPlusBestRuns(charKey)
    self:UpdateDungeonScores(charKey)
    self:UpdateGreatVaultRewards(charKey)
    self:UpdateRaidLockouts(charKey)
    self:UpdateWorldBossKills(charKey)
    self:UpdateMythicPlusRunHistory(charKey)
    self:UpdateDelvesData(charKey)
    
    -- FALLBACK: Populate vault activities from C_WeeklyRewards.GetActivities() only if
    -- VaultScanner hasn't already provided richer data for this character.
    -- VaultScanner is the primary source (PLAYER_ENTERING_WORLD → SyncVaultDataFromScanner)
    -- but may fail on fresh installs, timing issues, or empty API responses.
    local vaultActivities = self.db.global.pveCache
        and self.db.global.pveCache.greatVault
        and self.db.global.pveCache.greatVault.activities
        and self.db.global.pveCache.greatVault.activities[charKey]
    if not GreatVaultActivityHasRows(vaultActivities) then
        self:UpdateGreatVaultActivities(charKey)
    elseif VaultActivitiesMissingILvl(vaultActivities) then
        self:ProcessGreatVaultActivities(charKey)
    end

    PrunePvECacheAliasKeys(self.db.global.pveCache, charKey)
    
    -- Update timestamp (data already in DB)
    self:SavePvECache()
    
    local afterSig = BuildPvESignature(self.db.global.pveCache, charKey)
    if beforeSig ~= afterSig then
        -- Fire event only when API→DB produced a real data change.
        self:SendMessage(Constants.EVENTS.PVE_UPDATED)
    end
    
end

---Schedule throttled update (called by pending update timer)
function WarbandNexus:ProcessPendingPvEUpdate()
    if pendingUpdate then
        pendingUpdate = false
        self:UpdatePvEData()
    end
end

---Persist PvE cache on PLAYER_LOGOUT without API refresh.
function WarbandNexus:FlushPvECacheOnLogout()
    if pvePendingUpdateTimer then
        pvePendingUpdateTimer:Cancel()
        pvePendingUpdateTimer = nil
    end
    pendingUpdate = false
    if not self.db or not self.db.global then return end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then return end
    self:SavePvECache()
end

-- PUBLIC API (FOR UI AND DATASERVICE)

---Stored keystone row -> display row (dungeon name resolved); rows without a level pass through.
local function HydratePvEKeystoneRow(rawKeystone)
    if rawKeystone and tonumber(rawKeystone.level) and tonumber(rawKeystone.level) > 0 then
        local dungeonName = Utilities and Utilities.ResolveKeystoneDungeonName
            and Utilities:ResolveKeystoneDungeonName(rawKeystone)
        return {
            mapID = rawKeystone.mapID,
            level = rawKeystone.level,
            lastUpdate = rawKeystone.lastUpdate,
            dungeonName = dungeonName,
            name = dungeonName,
        }
    end
    return rawKeystone
end

---One per-character pveCache subtable, same key resolution as GetPvEData.
local function LookupPvECharSub(sub, charKey)
    if not sub or not charKey then return nil end
    charKey = CanonicalizePvEKey(charKey)
    if not charKey then return nil end
    local Lookup = ns.LookupPvECacheSubtable
    if Lookup then return Lookup(sub, charKey) end
    return sub[charKey]
end

---GetPvEData(charKey).keystone without hydrating the rest of the PvE snapshot.
---Keystone tooltip and /wn keys read this for every roster character (2026-10-22).
---@return table|nil
function WarbandNexus:GetPvEKeystone(charKey)
    local mp = self.db and self.db.global and self.db.global.pveCache and self.db.global.pveCache.mythicPlus
    return HydratePvEKeystoneRow(LookupPvECharSub(mp and mp.keystones, charKey))
end

---GetPvEData(charKey).vaultActivities without hydrating the rest of the PvE snapshot.
---@return table|nil
function WarbandNexus:GetPvEVaultActivities(charKey)
    local gv = self.db and self.db.global and self.db.global.pveCache and self.db.global.pveCache.greatVault
    return LookupPvECharSub(gv and gv.activities, charKey)
end

---Get PvE data for a specific character or all characters
---@return table PvE data
function WarbandNexus:GetPvEData(charKey)
    -- Always read directly from DB (no cache)
    local dbCache = self.db and self.db.global and self.db.global.pveCache or {}
    
    if charKey then
        charKey = CanonicalizePvEKey(charKey)
        local Lookup = ns.LookupPvECacheSubtable
        local function PveSub(sub)
            if not sub then return nil end
            if Lookup then return Lookup(sub, charKey) end
            return sub[charKey]
        end

        local bestRuns = PveSub(dbCache.mythicPlus and dbCache.mythicPlus.bestRuns) or {}
        local dungeonScoresData = PveSub(dbCache.mythicPlus and dbCache.mythicPlus.dungeonScores)
        
        -- Get overall score from dungeonScores (primary) or bestRuns (fallback)
        local overallScore = 0
        if dungeonScoresData and dungeonScoresData.overallScore then
            overallScore = dungeonScoresData.overallScore
        else
            overallScore = bestRuns.overallScore or 0
        end
        
        -- Build dungeon list from dungeonScores (for UI rendering)
        local dungeons = {}
        
        if C_ChallengeMode then
            local maps = C_ChallengeMode.GetMapTable()
            if maps then
                for i = 1, #maps do
                    local mapID = maps[i]
                    local mapName, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
                    if issecretvalue and mapName and issecretvalue(mapName) then mapName = nil end
                    
                    local dungeonScore = 0
                    local bestLevel = 0
                    
                    if dungeonScoresData and dungeonScoresData.dungeons and dungeonScoresData.dungeons[mapID] then
                        local dungeonData = dungeonScoresData.dungeons[mapID]
                        dungeonScore = dungeonData.score or 0
                        bestLevel = dungeonData.bestLevel or 0
                    end
                    
                    -- Fallback to bestRuns if dungeonScores doesn't have bestLevel
                    if bestLevel == 0 then
                        local runData = bestRuns[mapID]
                        bestLevel = runData and runData.level or 0
                    end
                    
                    table.insert(dungeons, {
                        mapID = mapID,
                        name = mapName or ("Dungeon " .. mapID),
                        texture = texture,
                        bestLevel = bestLevel,  -- From dungeonScores or bestRuns
                        score = dungeonScore,  -- From dungeonScores cache
                    })
                end
                
                -- Sort by name
                table.sort(dungeons, CmpNameSort)
            end
        end
        
        -- Hydrate lockouts: raids vs dungeons (Instance Tracker merges both; PvE raid panel uses raids only).
        local rawRaids = PveSub(dbCache.lockouts and dbCache.lockouts.raids) or {}
        local rawDungeons = PveSub(dbCache.lockouts and dbCache.lockouts.dungeons) or {}
        local raidLockouts = HydrateSavedLockoutsForChar(rawRaids, true)
        local dungeonLockouts = HydrateSavedLockoutsForChar(rawDungeons, false)
        local combinedLockouts = {}
        for i = 1, #raidLockouts do combinedLockouts[#combinedLockouts + 1] = raidLockouts[i] end
        for i = 1, #dungeonLockouts do combinedLockouts[#combinedLockouts + 1] = dungeonLockouts[i] end
        table.sort(combinedLockouts, CmpNameSort)

        -- Return data for specific character
        local vaultActivities = PveSub(dbCache.greatVault and dbCache.greatVault.activities)
        local keystoneData = HydratePvEKeystoneRow(PveSub(dbCache.mythicPlus and dbCache.mythicPlus.keystones))
        local worldBosses = PveSub(dbCache.lockouts and dbCache.lockouts.worldBosses)
        local rawDelveCharacter = PveSub(dbCache.delves and dbCache.delves.characters) or {}
        local rawRunHistory = PveSub(dbCache.mythicPlus and dbCache.mythicPlus.runHistory) or {}
        local runHistoryWeek = dbCache.mythicPlus and dbCache.mythicPlus.runHistoryWeek
        local weekRecorded = runHistoryWeek and (PveSub(runHistoryWeek) or runHistoryWeek[charKey])
        local resetStart = GetCurrentWeeklyResetStartTime()
        local runHistory = rawRunHistory
        if resetStart and resetStart > 0 and (type(weekRecorded) ~= "number" or weekRecorded < (resetStart - 60)) then
            runHistory = {}
        end
        local delveCharacter = rawDelveCharacter
        if resetStart and resetStart > 0 and (delveCharacter.lastUpdate or 0) < resetStart then
            delveCharacter = {
                bountifulComplete = false,
                gildedStashes = 0,
                gildedStashesMax = delveCharacter.gildedStashesMax,
                crackedKeystoneComplete = false,
                nightmareTaskComplete = false,
                purgingVaultsComplete = false,
                delveNemesisComplete = false,
                tormentedSoulUsedAt = nil,
                tormentedSoulBuffActive = false,
                lastUpdate = delveCharacter.lastUpdate,
            }
            -- A use recorded after this reset survives (cast stamped before lastUpdate was refreshed).
            local tsUsedAt = tonumber(rawDelveCharacter.tormentedSoulUsedAt)
            if tsUsedAt and tsUsedAt >= resetStart then
                delveCharacter.tormentedSoulUsedAt = tsUsedAt
                delveCharacter.tormentedSoulBuffActive = rawDelveCharacter.tormentedSoulBuffActive == true
            end
        end
        local returnData = {
            keystone = keystoneData,
            bestRuns = bestRuns,
            dungeonScores = dungeonScoresData,
            vaultActivities = vaultActivities,
            vaultRewards = dbCache.greatVault and dbCache.greatVault.rewards
                and LookupVaultRewardsEntry(dbCache.greatVault.rewards, charKey),
            greatVault = vaultActivities or {},  -- Alias for legacy consumers
            raidLockouts = raidLockouts,
            dungeonLockouts = dungeonLockouts,
            lockouts = combinedLockouts,  -- Raids + dungeons for DataService / debug
            worldBosses = worldBosses,
            -- Delves data (companion is account-wide, per-char quest status)
            delves = {
                companion = dbCache.delves and dbCache.delves.companion or {},
                season = dbCache.delves and dbCache.delves.season or 0,
                character = delveCharacter,
            },
            -- Add legacy-compatible mythicPlus structure
            mythicPlus = {
                overallScore = overallScore,
                dungeons = dungeons,
                bestRuns = bestRuns,
                dungeonScores = dungeonScoresData,
                runHistory = runHistory,
            },
        }
        
        return returnData
    else
        -- Return all data (for global queries like currentAffixes)
        -- Hydrate affixes: SV stores only IDs, resolve name/description/icon on-demand
        local rawAffixes = dbCache.mythicPlus and dbCache.mythicPlus.currentAffixes or {}
        local hydratedAffixes = {}
        for i = 1, #rawAffixes do
            local affixEntry = rawAffixes[i]
            local affixID = type(affixEntry) == "number" and affixEntry or (type(affixEntry) == "table" and affixEntry.id)
            if affixID and C_ChallengeMode then
                local name, description, filedataid = C_ChallengeMode.GetAffixInfo(affixID)
                if name then
                    table.insert(hydratedAffixes, {
                        id = affixID,
                        name = name,
                        description = description or "",
                        icon = filedataid,
                    })
                end
            end
        end
        
        return {
            mythicPlus = dbCache.mythicPlus or {},
            greatVault = dbCache.greatVault or {},
            lockouts = dbCache.lockouts or {},
            delves = dbCache.delves or {},
            currentAffixes = hydratedAffixes,
        }
    end
end

---True if CollectPvEData produced real M+ rows (not an error/empty pre-hydration snapshot).
local function LegacyMythicSnapshotHasData(mp)

    if not mp or type(mp) ~= "table" then return false end
    if mp.keystone and type(mp.keystone.level) == "number" and mp.keystone.level > 0 and mp.keystone.mapID then
        return true
    end
    if type(mp.overallScore) == "number" and mp.overallScore > 0 then return true end
    if mp.dungeons then
        for i = 1, #mp.dungeons do
            local d = mp.dungeons[i]
            if d and ((type(d.score) == "number" and d.score > 0) or (type(d.bestLevel) == "number" and d.bestLevel > 0)) then
                return true
            end
        end
    end
    if mp.dungeonProgress then
        for _, data in pairs(mp.dungeonProgress) do
            if data and ((type(data.score) == "number" and data.score > 0) or (type(data.bestLevel) == "number" and data.bestLevel > 0)) then
                return true
            end
        end
    end
    return false
end

GreatVaultActivityHasRows = function(bucket)
    if not bucket or type(bucket) ~= "table" then return false end
    if bucket.raids and #bucket.raids > 0 then return true end
    if bucket.mythicPlus and #bucket.mythicPlus > 0 then return true end
    if bucket.world and #bucket.world > 0 then return true end
    if bucket.pvp and #bucket.pvp > 0 then return true end
    return false
end

GreatVaultActivityHasCompletedRows = function(bucket)
    if not bucket or type(bucket) ~= "table" then return false end
    local gvCategories = { "raids", "mythicPlus", "world", "pvp" }
    for ci = 1, #gvCategories do
        local category = gvCategories[ci]
        local rows = bucket[category]
        if type(rows) == "table" then
            for i = 1, #rows do
                local row = rows[i]
                local progress = row and tonumber(row.progress) or 0
                local threshold = row and tonumber(row.threshold) or 0
                if threshold > 0 and progress >= threshold then
                    return true
                end
            end
        end
    end
    return false
end

---Keep completed vault rows when an incoming snapshot has none (post-reset chest + mid-week API races).
---Does not mix current-week incomplete progress into a preserved last-week bucket — callers return early.
---@param prevBucket table|nil
---@param incomingHasCompleted boolean
---@param rewardClaimedThisReset boolean|nil
---@param previousResetTime number|nil
---@return boolean preserve
---@return boolean markPostReset
ShouldPreserveCompletedVaultRows = function(prevBucket, incomingHasCompleted, rewardClaimedThisReset, previousResetTime)
    if not GreatVaultActivityHasCompletedRows(prevBucket) then
        return false, false
    end
    if rewardClaimedThisReset or incomingHasCompleted then
        return false, false
    end
    local storedBeforeReset = previousResetTime and (tonumber(prevBucket.lastUpdate) or 0) < previousResetTime
    return true, storedBeforeReset and true or false
end

---True when a flat CollectPvEData greatVault array has any completed slot.
---@param legacyArr table|nil
---@return boolean
LegacyGreatVaultArrayHasCompleted = function(legacyArr)
    if type(legacyArr) ~= "table" then return false end
    for i = 1, #legacyArr do
        local activity = legacyArr[i]
        local progress = activity and tonumber(activity.progress) or 0
        local threshold = activity and tonumber(activity.threshold) or 0
        if threshold > 0 and progress >= threshold then
            return true
        end
    end
    return false
end

---Import legacy PvE data for a specific character into pveCache.
---Used by DatabaseOptimizer migration and UpdatePvEDataV2 fallback.
---Maps the old DataService progress format → PvECacheService structure.
function WarbandNexus:ImportLegacyPvEData(charKey, legacyData)
    if not charKey or not legacyData then return end
    charKey = CanonicalizePvEKey(charKey)
    if not charKey or charKey == "" then return end
    
    PvECacheUserDebug(
        "import: START key=%s has.mythicPlus=%s has.greatVault=%s has.lockouts=%s",
        tostring(charKey),
        legacyData.mythicPlus and "yes" or "no",
        legacyData.greatVault and ("yes len=" .. tostring(#legacyData.greatVault)) or "no",
        legacyData.lockouts and ("yes len=" .. tostring(#legacyData.lockouts)) or "no")
    
    -- Ensure DB is initialized
    if not self.db or not self.db.global or not self.db.global.pveCache then
        self:InitializePvECache()
    end
    if not self.db.global.pveCache then return end
    
    local pc = self.db.global.pveCache
    
    -- ── M+ Data ──
    if legacyData.mythicPlus then
        local mp = legacyData.mythicPlus
        local existingScores = pc.mythicPlus.dungeonScores and pc.mythicPlus.dungeonScores[charKey]
        local hadCachedMythic = DungeonScoresBucketHasProgress(existingScores)
            or (pc.mythicPlus.keystones and pc.mythicPlus.keystones[charKey] and pc.mythicPlus.keystones[charKey].level and pc.mythicPlus.keystones[charKey].level > 0)
        -- SaveCharacter can run before Challenge Mode APIs hydrate; do not replace good SV with zeros.
        if hadCachedMythic and not LegacyMythicSnapshotHasData(mp) then
            local prevOverall = existingScores and type(existingScores.overallScore) == "number" and existingScores.overallScore or 0
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint(string.format("|cff9370DB[PvECache]|r ImportLegacyPvEData: skip mythic for %s (stale/empty snapshot)", charKey))
            end
            PvECacheUserDebug(
                "import: SKIP mythic (empty snapshot, cache kept) key=%s prevOverall=%s snapshotOverall=%s nonzero=%s",
                tostring(charKey), tostring(prevOverall), tostring(mp and mp.overallScore or 0),
                (prevOverall > 0) and "yes" or "no")
        else
        
        -- Keystone: challenge mapID + level (reject legacy CollectPvEData bag scans that stored itemID as mapID).
        if mp.keystone and mp.keystone.level and mp.keystone.level > 0 and mp.keystone.mapID then
            local mid = mp.keystone.mapID
            if type(mid) == "number" and mid > 0 then
                local accept = false
                if C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                    local mapName = C_ChallengeMode.GetMapUIInfo(mid)
                    if mapName and not (issecretvalue and issecretvalue(mapName)) and mapName ~= "" then
                        accept = true
                    end
                end
                if not accept and mid < 100000 then
                    accept = true
                end
                if accept then
                    pc.mythicPlus.keystones = pc.mythicPlus.keystones or {}
                    pc.mythicPlus.keystones[charKey] = {
                        mapID = mid,
                        level = mp.keystone.level,
                        lastUpdate = mp.keystone.lastUpdate or time(),
                    }
                end
            end
        end
        
        -- Overall score → dungeonScores
        pc.mythicPlus.dungeonScores = pc.mythicPlus.dungeonScores or {}
        pc.mythicPlus.dungeonScores[charKey] = pc.mythicPlus.dungeonScores[charKey] or {}
        pc.mythicPlus.dungeonScores[charKey].overallScore = mp.overallScore or 0
        
        -- Dungeon progress → bestRuns + dungeonScores.dungeons
        if mp.dungeonProgress then
            pc.mythicPlus.bestRuns = pc.mythicPlus.bestRuns or {}
            pc.mythicPlus.bestRuns[charKey] = pc.mythicPlus.bestRuns[charKey] or {}
            pc.mythicPlus.bestRuns[charKey].overallScore = mp.overallScore or 0
            
            pc.mythicPlus.dungeonScores[charKey].dungeons = pc.mythicPlus.dungeonScores[charKey].dungeons or {}
            
            for mapID, data in pairs(mp.dungeonProgress) do
                pc.mythicPlus.bestRuns[charKey][mapID] = {
                    level = data.bestLevel or 0,
                    score = data.score or 0,
                }
                pc.mythicPlus.dungeonScores[charKey].dungeons[mapID] = {
                    score = data.score or 0,
                    bestLevel = data.bestLevel or 0,
                }
            end
        end
        
        -- Legacy format: dungeons as array (from CollectPvEData)
        if mp.dungeons then
            pc.mythicPlus.bestRuns = pc.mythicPlus.bestRuns or {}
            pc.mythicPlus.bestRuns[charKey] = pc.mythicPlus.bestRuns[charKey] or {}
            pc.mythicPlus.bestRuns[charKey].overallScore = mp.overallScore or 0
            
            pc.mythicPlus.dungeonScores[charKey].dungeons = pc.mythicPlus.dungeonScores[charKey].dungeons or {}
            
            for i = 1, #mp.dungeons do
                local dungeon = mp.dungeons[i]
                if dungeon.mapID then
                    pc.mythicPlus.bestRuns[charKey][dungeon.mapID] = {
                        level = dungeon.bestLevel or 0,
                        score = dungeon.score or 0,
                    }
                    pc.mythicPlus.dungeonScores[charKey].dungeons[dungeon.mapID] = {
                        score = dungeon.score or 0,
                        bestLevel = dungeon.bestLevel or 0,
                    }
                end
            end
        end
        local appliedOverall = pc.mythicPlus.dungeonScores[charKey] and pc.mythicPlus.dungeonScores[charKey].overallScore or 0
        PvECacheUserDebug(
            "import: mythic APPLIED key=%s storedOverall=%s nonzero=%s",
            tostring(charKey), tostring(appliedOverall), (appliedOverall > 0) and "yes" or "no")
        end
    end
    
    -- ── Great Vault ──
    if legacyData.greatVault then
        local prevVault = pc.greatVault.activities and pc.greatVault.activities[charKey]
        local previousResetTime = GetCurrentWeeklyResetStartTime()
        local rewardData = pc.greatVault.rewards and pc.greatVault.rewards[charKey]
        local rewardClaimedResetTime = rewardData and NormalizeResetEpoch(rewardData.claimedResetTime) or nil
        local rewardClaimedThisReset = rewardClaimedResetTime and previousResetTime
            and rewardClaimedResetTime >= previousResetTime
        local incomingCompleted = LegacyGreatVaultArrayHasCompleted(legacyData.greatVault)
        local preserveRows, markPostReset = ShouldPreserveCompletedVaultRows(
            prevVault, incomingCompleted, rewardClaimedThisReset, previousResetTime)

        local skipVaultReplace = false
        if #legacyData.greatVault == 0 and GreatVaultActivityHasRows(prevVault) then
            -- CollectPvEData / staggered stage can hand an empty array before the weekly API hydrates.
            skipVaultReplace = true
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint(string.format("|cff9370DB[PvECache]|r ImportLegacyPvEData: skip empty greatVault for %s (keeping cache)", charKey))
            end
            PvECacheUserDebug(
                "import: SKIP greatVault (legacy [] but cache had rows) key=%s — vault preserved",
                tostring(charKey))
        elseif preserveRows then
            -- Non-empty current-week zero-progress arrays used to REPLACE preserved post-reset
            -- completed rows (and mid-week completed rows during an API race). SaveCharacter →
            -- CollectPvEData → ImportLegacyPvEData hit this every full save after weekly reset.
            skipVaultReplace = true
            if markPostReset and prevVault then
                prevVault.isPostReset = true
            end
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint(string.format(
                    "|cff9370DB[PvECache]|r ImportLegacyPvEData: skip zero-progress greatVault for %s (keeping completed cache)",
                    charKey))
            end
            PvECacheUserDebug(
                "import: SKIP greatVault (incoming incomplete, cache had completed) key=%s postReset=%s — vault preserved",
                tostring(charKey), markPostReset and "yes" or "no")
        end

        if not skipVaultReplace then
        pc.greatVault.activities = pc.greatVault.activities or {}
        local vaultData = { raids = {}, mythicPlus = {}, pvp = {}, world = {}, lastUpdate = time() }
        
        for i = 1, #legacyData.greatVault do
            local activity = legacyData.greatVault[i]
            local entry = {
                progress = activity.progress or 0,
                threshold = activity.threshold or 0,
                level = activity.level or 0,
                rewardItemLevel = activity.rewardItemLevel,
            }
            
            local actType = activity.type
            if actType == 1 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Raid) then
                table.insert(vaultData.raids, entry)
            elseif actType == 2 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Activities) then
                table.insert(vaultData.mythicPlus, entry)
            elseif actType == 3 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.RankedPvP) then
                table.insert(vaultData.pvp, entry)
            elseif actType == 4 or actType == (Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.World) then
                table.insert(vaultData.world, entry)
            end
        end
        
        pc.greatVault.activities[charKey] = vaultData
        
        PvECacheUserDebug(
            "import: greatVault APPLIED key=%s raid=%d mPlus=%d world=%d pvp=%d unclaimed=%s",
            tostring(charKey),
            #vaultData.raids, #vaultData.mythicPlus, #vaultData.world, #vaultData.pvp,
            legacyData.hasUnclaimedRewards and "yes" or "no")
        end

        -- Unclaimed rewards flag can still advance while activities are preserved.
        if legacyData.hasUnclaimedRewards then
            pc.greatVault.rewards = pc.greatVault.rewards or {}
            pc.greatVault.rewards[charKey] = {
                hasAvailableRewards = true,
                lastUpdate = time(),
            }
        end
    end
    
    -- ── Saved instance lockouts (raids + dungeons) ──
    if legacyData.lockouts then
        local prevRaids = pc.lockouts.raids and pc.lockouts.raids[charKey]
        local prevDungeons = pc.lockouts.dungeons and pc.lockouts.dungeons[charKey]
        local hadPrevLockouts = (type(prevRaids) == "table" and next(prevRaids))
            or (type(prevDungeons) == "table" and next(prevDungeons))
        if legacyData.lockouts and #legacyData.lockouts == 0 and hadPrevLockouts then
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint(string.format("|cff9370DB[PvECache]|r ImportLegacyPvEData: skip empty lockouts for %s (keeping cache)", charKey))
            end
            PvECacheUserDebug(
                "import: SKIP lockouts (legacy [] but cache had rows) key=%s",
                tostring(charKey))
        else
        pc.lockouts.raids = pc.lockouts.raids or {}
        pc.lockouts.dungeons = pc.lockouts.dungeons or {}
        pc.lockouts.raids[charKey] = {}
        pc.lockouts.dungeons[charKey] = {}

        local nowImp = (GetServerTime and GetServerTime()) or time()
        for i = 1, #legacyData.lockouts do
            local lockout = legacyData.lockouts[i]
            local id = lockout.instanceID or lockout.id
            if id then
                local rRaw = lockout.reset
                local resetSec = nil
                if not (issecretvalue and issecretvalue(rRaw)) and rRaw ~= nil then
                    resetSec = tonumber(rRaw)
                end
                if resetSec and resetSec > 0 then
                    local row = {
                        name = lockout.name,
                        difficulty = lockout.difficulty or lockout.difficultyID,
                        reset = rRaw,
                        resetAt = nowImp + resetSec,
                        extended = lockout.extended or false,
                        numEncounters = lockout.total or lockout.numEncounters,
                        encounterProgress = lockout.progress or lockout.encounterProgress,
                    }
                    if lockout.isRaid == true then
                        pc.lockouts.raids[charKey][id] = row
                    elseif lockout.isRaid == false then
                        pc.lockouts.dungeons[charKey][id] = row
                    else
                        pc.lockouts.raids[charKey][id] = row
                    end
                end
            end
        end
        local nRaid, nDung = 0, 0
        if pc.lockouts.raids[charKey] then
            for _ in pairs(pc.lockouts.raids[charKey]) do nRaid = nRaid + 1 end
        end
        if pc.lockouts.dungeons[charKey] then
            for _ in pairs(pc.lockouts.dungeons[charKey]) do nDung = nDung + 1 end
        end
        PvECacheUserDebug(
            "import: lockouts APPLIED key=%s raids=%d dungeons=%d nonzero=%s",
            tostring(charKey), nRaid, nDung, ((nRaid + nDung) > 0) and "yes" or "no")
        end
    end
    
    self:SavePvECache()
    if IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint(string.format("|cff9370DB[PvECache]|r Imported legacy PvE data for %s", charKey))
    end
    PvECacheUserDebug("import: DONE key=%s (SavedVariables write)", tostring(charKey))
end

---Clear PvE cache (force refresh)
function WarbandNexus:ClearPvECache()
    if not self.db or not self.db.global or not self.db.global.pveCache then return end
    
    self.db.global.pveCache.mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {}, season = 0 }
    self.db.global.pveCache.greatVault = { activities = {}, rewards = {} }
    self.db.global.pveCache.lockouts = { raids = {}, dungeons = {}, worldBosses = {} }
    self.db.global.pveCache.delves = { companion = {}, season = 0 }
    self.db.global.pveCache.lastUpdate = 0
    
    self:SavePvECache()
end

-- WarbandNexus:NotifyVaultEasyAccessRefresh lives in PvECacheService_Vault.lua.
local function NotifyVaultEasyAccessRefresh()
    if WarbandNexus and WarbandNexus.NotifyVaultEasyAccessRefresh then
        WarbandNexus:NotifyVaultEasyAccessRefresh()
    end
end

-- EVENT REGISTRATION (Auto-register on module load)

---Register PvE event listeners
function WarbandNexus:RegisterPvECacheEvents()
    if not self.RegisterEvent then
        return
    end

    if self.EnsureWeeklyRewardsFrameHooks then
        self:EnsureWeeklyRewardsFrameHooks()
    end
    
    -- Prime C_MythicPlus API cache on login (deferred to ensure API readiness)
    C_Timer.After(3, function()
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            C_MythicPlus.RequestCurrentAffixes()
        end
    end)
    
    -- Vault warm-up: VaultScanner fires OnUIInteract at T+1s, server responds ~T+2-4s.
    -- Use the thinner API fallback only if the scanner did not populate rows.
    C_Timer.After(5, function()
        if not (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then return end
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
        local charKey = GetSessionCanonicalPvEKey()
        if not charKey then return end
        local pveCache = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache
        local beforeSig = BuildPvESignature(pveCache, charKey)
        local vaultActivities = pveCache
            and pveCache.greatVault
            and pveCache.greatVault.activities
            and pveCache.greatVault.activities[charKey]
        if not GreatVaultActivityHasRows(vaultActivities) then
            WarbandNexus:ProcessGreatVaultActivities(charKey)
        end
        local afterSig = BuildPvESignature(pveCache, charKey)
        if beforeSig ~= afterSig and WarbandNexus.SendMessage and Constants and Constants.EVENTS and Constants.EVENTS.PVE_UPDATED then
            WarbandNexus:SendMessage(Constants.EVENTS.PVE_UPDATED)
        end
    end)

    -- Deferred vault iLvl / keystone backfill after API warmup (no PvE tab required).
    -- Same warm gate as Core's T+5.5s call: with a persisted row the RequestMapInfo /
    -- RequestRaidInfo answers (CHALLENGE_MODE_MAPS_UPDATE, UPDATE_INSTANCE_INFO) already drive
    -- the throttled refresh, so an unconditional run here was a second full collect (2026-10-22).
    C_Timer.After(3, function()
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
        if WarbandNexus.IsPvERowPersistedWarm and WarbandNexus:IsPvERowPersistedWarm() then return end
        if WarbandNexus.UpdatePvEData then
            WarbandNexus:UpdatePvEData()
        end
    end)
    
    -- Throttle timer for PvE updates
    local pveUpdateTimer = nil
    local function ThrottledPvEUpdate()
        -- GUARD: Only process if character is tracked
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then
            return
        end
        
        -- Cancel pending update
        if pveUpdateTimer then
            pveUpdateTimer:Cancel()
        end
        
        -- Wait 1.0s before updating (API needs time to update)
        pveUpdateTimer = C_Timer.NewTimer(1.0, function()
            WarbandNexus:UpdatePvEData()
            pveUpdateTimer = nil
        end)
    end

    -- (post-claim vault heal is handled by WarbandNexus:SchedulePostClaimVaultHeal)
    
    -- Mythic+ events
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] CHALLENGE_MODE_COMPLETED triggered")
        -- Module gate: keystone path always runs; vault/M+ refresh only while a consumer is on.
        local vaultOn = (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled())
        
        -- Request fresh data from Blizzard APIs
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            if vaultOn then
                C_MythicPlus.RequestRewards()
            end
        end
        if vaultOn and C_WeeklyRewards then
            C_WeeklyRewards.OnUIInteract()
        end
        
        if WarbandNexus.RequestKeystoneRefresh then
            WarbandNexus:RequestKeystoneRefresh("CHALLENGE_MODE_COMPLETED", true)
        end
        if vaultOn then
            ThrottledPvEUpdate()
        end
    end)
    
    self:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] MYTHIC_PLUS_NEW_WEEKLY_RECORD triggered")
        if not (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then return end
        ThrottledPvEUpdate()
    end)
    
    -- CHALLENGE_MODE_MAPS_UPDATE: fires when M+ map/keystone data is refreshed by the server
    -- This is the proper event for keystone detection (instead of bag scanning)
    self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] CHALLENGE_MODE_MAPS_UPDATE triggered")
        if WarbandNexus.RequestKeystoneRefresh then
            WarbandNexus:RequestKeystoneRefresh("CHALLENGE_MODE_MAPS_UPDATE", true)
        end
        -- Keystone refresh above is always-on; the full PvE refresh is gated.
        if (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then
            ThrottledPvEUpdate()
        end
    end)
    
    self:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] MYTHIC_PLUS_CURRENT_AFFIX_UPDATE triggered (weekly reset)")
        
        -- Affix refresh: clear affix IDs, then prune stale keystones for the new weekly cycle.
        if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache then
            if WarbandNexus.db.global.pveCache.mythicPlus then
                WarbandNexus.db.global.pveCache.mythicPlus.currentAffixes = {}
                PruneAllPvEWeeklyData()
            end
            
            WarbandNexus:SavePvECache()
        end
        
        -- Module gate: weekly prune above and keystone refresh below stay always-on.
        if (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then
            -- Then update with new data
            ThrottledPvEUpdate()

            -- Weekly reset just rolled over: last week's vault is now claimable, so pull fresh vault
            -- data instead of waiting for the player to open the Great Vault.
            WarbandNexus:RequestWeeklyVaultRefresh()
        end

        -- Also refresh keystone detection (new weekly key may be in bags)
        if WarbandNexus.RequestKeystoneRefresh then
            WarbandNexus:RequestKeystoneRefresh("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", true)
        end
    end)
    
    if self.RegisterMessage and Constants and Constants.EVENTS and Constants.EVENTS.WEEKLY_RESET_OCCURRED then
        self:RegisterMessage(Constants.EVENTS.WEEKLY_RESET_OCCURRED, function()
            DebugPrint("|cff9370DB[PvECache]|r [PvE Event] WN_WEEKLY_RESET_OCCURRED triggered")
            if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache then
                if WarbandNexus.db.global.pveCache.mythicPlus then
                    WarbandNexus.db.global.pveCache.mythicPlus.currentAffixes = {}
                end
                PruneAllPvEWeeklyData()
                WarbandNexus:SavePvECache()
                -- Weekly rows were just cleared: announce the data change (2026-10-22).
                WarbandNexus:SendMessage(Constants.EVENTS.PVE_UPDATED)
            end
            if (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then
                ThrottledPvEUpdate()
                if WarbandNexus.RequestWeeklyVaultRefresh then
                    WarbandNexus:RequestWeeklyVaultRefresh()
                end
            end
            if WarbandNexus.RequestKeystoneRefresh then
                WarbandNexus:RequestKeystoneRefresh("WEEKLY_RESET_OCCURRED", true)
            end
        end)
    end
    
    -- Weekly Vault events
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] WEEKLY_REWARDS_UPDATE triggered")
        vaultState.vaultDataFreshThisSession = true  -- Server has responded; HasAvailableRewards() is now reliable
        if not (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then return end
        WarbandNexus:EnsureWeeklyRewardsFrameHooks()
        WarbandNexus:OnVaultDataReceived()
    end)
    
    self:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] WEEKLY_REWARDS_ITEM_CHANGED triggered")
        if not (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then return end
        WarbandNexus:EnsureWeeklyRewardsFrameHooks()
        if WeeklyRewardsFrame and WeeklyRewardsFrame.IsShown and WeeklyRewardsFrame:IsShown() then
            ns._weeklyRewardsInteractCharKey = GetSessionCanonicalPvEKey()
        end
        if WarbandNexus.RefreshVaultClaimState then
            local key = ns._weeklyRewardsInteractCharKey or ns._vaultClaimSubjectKey
            WarbandNexus:RefreshVaultClaimState(key)
        end
        NotifyVaultEasyAccessRefresh()
        -- Re-poke the server after the claim settles: without this the live C_WeeklyRewards state
        -- still reports the pre-claim vault, so the badge kept counting a vault already looted
        -- until the player reopened the Great Vault.
        WarbandNexus:RequestWeeklyVaultRefresh(0.5)
        -- The live C_WeeklyRewards "available" state can trail the server by several seconds after a
        -- claim (and a vault key reward can land a frame or two late). Self-terminating heal ladder so
        -- the badge + PvE row clear on their own instead of the player opening the PvE tab or /reload.
        WarbandNexus:SchedulePostClaimVaultHeal(ns._weeklyRewardsInteractCharKey or ns._vaultClaimSubjectKey)
    end)
    
    -- Raid lockout events
    self:RegisterEvent("UPDATE_INSTANCE_INFO", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] UPDATE_INSTANCE_INFO triggered")
        instanceInfoSeenThisSession = true
        if not (ns.Utilities and ns.Utilities:IsPvEVaultConsumerEnabled()) then return end
        -- A raid boss kill can fill a vault slot; ask for fresh vault data too (throttled).
        WarbandNexus:RequestWeeklyVaultRefresh()
        ThrottledPvEUpdate()
    end)
    -- Ask for the saved-instance list once per session so UPDATE_INSTANCE_INFO arrives even when no
    -- other module requests it (the empty-lockout write above waits for it).
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    
    -- Delves events (Midnight 12.0+)
    pcall(function()
        self:RegisterEvent("DELVES_ACCOUNT_DATA_ELEMENT_CHANGED", function()
            DebugPrint("|cff9370DB[PvECache]|r [PvE Event] DELVES_ACCOUNT_DATA_ELEMENT_CHANGED triggered")
            -- Delve data feeds PvE (vault/delves) and Reputations (companion renown).
            if not (ns.Utilities and ns.Utilities:IsAnyModuleEnabled("pve", "reputations")) then return end
            -- Delve completion can fill the world vault slot.
            WarbandNexus:RequestWeeklyVaultRefresh()
            ThrottledPvEUpdate()
        end)
    end)

    -- Keystone loot toast: CHAT_MSG_LOOT arg1 = message (wiki); guard issecretvalue before string ops.
    self:RegisterEvent("CHAT_MSG_LOOT", function(_, message, author)
        -- Author first: group loot lines skip the link parse + C_Item keystone probe (2026-10-22).
        if not ChatLootAuthorIsPlayer(author) then return end
        if not LootMessageIsMythicKeystone(message) then return end
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] CHAT_MSG_LOOT mythic keystone")
        if WarbandNexus.RequestKeystoneRefresh then
            WarbandNexus:RequestKeystoneRefresh("CHAT_MSG_LOOT", true)
        end
    end)

    -- ITEM_PUSH intentionally not registered: fires on every bag item and caused keystone
    -- refresh + debug spam while C_MythicPlus returned nil|nil. CHAT_MSG_LOOT +
    -- CHALLENGE_MODE_MAPS_UPDATE cover keystone acquisition.

    -- Tormented Soul use (player-only cast watcher; follows the PvE module toggle).
    self:SyncTormentedSoulCastWatcher()
    ns._pveTormentedSoulToggleSink = ns._pveTormentedSoulToggleSink or {}
    WarbandNexus.RegisterMessage(ns._pveTormentedSoulToggleSink, Constants.EVENTS.MODULE_TOGGLED, function(_, moduleName)
        if moduleName ~= "pve" then return end
        WarbandNexus:SyncTormentedSoulCastWatcher()
    end)
    
end

-- EVENT HANDLERS (Called by registered events above)

---Handle UPDATE_INSTANCE_INFO event
function WarbandNexus:OnInstanceInfoUpdate()
    local P = ns.Profiler
    if P and P.RunSlice then
        return P:RunSlice(P.CAT.SVC, "PvE_InstanceInfoUpdate", self.UpdatePvEData, self)
    end
    self:UpdatePvEData()
end

---Handle CHALLENGE_MODE_COMPLETED event
function WarbandNexus:OnChallengeModeCompleted()
    local P = ns.Profiler
    if P and P.RunSlice then
        return P:RunSlice(P.CAT.SVC, "PvE_ChallengeModeCompleted", self.UpdatePvEData, self)
    end
    self:UpdatePvEData()
end

-- PvECacheService_MythicPlus.lua and PvECacheService_Vault.lua read this table
-- (TOC: PvECacheService.lua before both satellites).
ns.PvECacheService = ns.PvECacheService or {}
ns.PvECacheService._bind = {
    DebugPrint = DebugPrint,
    Utilities = Utilities,
    Constants = Constants,
    vaultState = vaultState,
    PvECacheUserDebug = PvECacheUserDebug,
    ShouldLogPvECacheDiag = ShouldLogPvECacheDiag,
    CanonicalizePvEKey = CanonicalizePvEKey,
    GetSessionCanonicalPvEKey = GetSessionCanonicalPvEKey,
    IsSessionPvECharacter = IsSessionPvECharacter,
    LookupVaultRewardsEntry = LookupVaultRewardsEntry,
    WriteVaultRewardsCache = WriteVaultRewardsCache,
    NormalizeResetEpoch = NormalizeResetEpoch,
    GetCurrentWeeklyResetStartTime = GetCurrentWeeklyResetStartTime,
    BuildPvESignature = BuildPvESignature,
    ApplyMythicPlusSeasonRollover = ApplyMythicPlusSeasonRollover,
    DungeonScoresBucketHasProgress = DungeonScoresBucketHasProgress,
    ShouldPreserveCompletedVaultRows = ShouldPreserveCompletedVaultRows,
    NotifyVaultEasyAccessRefresh = NotifyVaultEasyAccessRefresh,
    keystoneRetryPending = keystoneRetryPending,
    keystoneRetryCount = keystoneRetryCount,
    keystoneZeroSeenAt = keystoneZeroSeenAt,
    keystoneRefreshLastAt = keystoneRefreshLastAt,
    keystoneWarmupLastAt = keystoneWarmupLastAt,
    keystoneLastSeen = keystoneLastSeen,
    KEYSTONE_REFRESH_MIN_INTERVAL = KEYSTONE_REFRESH_MIN_INTERVAL,
    KEYSTONE_WARMUP_COOLDOWN = KEYSTONE_WARMUP_COOLDOWN,
    KEYSTONE_REFRESH_HIGH_PRIORITY = KEYSTONE_REFRESH_HIGH_PRIORITY,
    KEYSTONE_ZERO_CONFIRM_SECONDS = KEYSTONE_ZERO_CONFIRM_SECONDS,
    KEYSTONE_RETRY_MAX = KEYSTONE_RETRY_MAX,
    KEYSTONE_RETRY_DELAYS = KEYSTONE_RETRY_DELAYS,
}

-- PLAYER_LOGOUT flush is coordinated from Core.lua:OnPlayerLogout (FlushPvECacheOnLogout).

-- Module loaded (silent)
-- Module loaded - verbose logging hidden (debug mode only)
