--[[
    Warband Nexus - PvE Cache Service: Vault
    Great Vault activities / rewards, dead-run analysis, claim-state refresh,
    Easy Access notify, WeeklyRewardsFrame hooks, vault event handlers.
    Split from PvECacheService.lua; shared locals come from ns.PvECacheService._bind.
]]

local ADDON_NAME, ns = ...

local B = assert(ns.PvECacheService and ns.PvECacheService._bind, "PvECacheService_Vault: load Modules/PvECacheService.lua first")
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local DebugPrint = B.DebugPrint
local Utilities = B.Utilities
local Constants = B.Constants
local vaultState = B.vaultState
local PvECacheUserDebug = B.PvECacheUserDebug
local CanonicalizePvEKey = B.CanonicalizePvEKey
local GetSessionCanonicalPvEKey = B.GetSessionCanonicalPvEKey
local IsSessionPvECharacter = B.IsSessionPvECharacter
local LookupVaultRewardsEntry = B.LookupVaultRewardsEntry
local WriteVaultRewardsCache = B.WriteVaultRewardsCache
local NormalizeResetEpoch = B.NormalizeResetEpoch
local GetCurrentWeeklyResetStartTime = B.GetCurrentWeeklyResetStartTime
local BuildPvESignature = B.BuildPvESignature
local ShouldPreserveCompletedVaultRows = B.ShouldPreserveCompletedVaultRows
local NotifyVaultEasyAccessRefresh = B.NotifyVaultEasyAccessRefresh
local keystoneLastSeen = B.keystoneLastSeen
local keystoneRetryCount = B.keystoneRetryCount

-- GREAT VAULT DATA

---Update Great Vault activities for current character
function WarbandNexus:UpdateGreatVaultActivities(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_WeeklyRewards or not charKey then return end
    charKey = CanonicalizePvEKey(charKey)
    
    -- SYNCHRONOUS: Process vault data already cached by WoW client (from previous OnUIInteract).
    -- ProcessGreatVaultActivities guards against empty data (returns early if GetActivities is nil/empty).
    self:ProcessGreatVaultActivities(charKey)
    
    -- NOTE: OnUIInteract() is NOT called here to avoid excessive server requests.
    -- VaultScanner handles the initial request on PLAYER_ENTERING_WORLD.
    -- PvECacheService event handlers (CHALLENGE_MODE_COMPLETED, etc.) call OnUIInteract as needed.
end

---Process Great Vault activities after server responds
function WarbandNexus:ProcessGreatVaultActivities(charKey)
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)
    
    local activities = C_WeeklyRewards.GetActivities()
    if not activities or #activities == 0 then 
        -- Do NOT create empty arrays when API returns nil/empty.
        -- Server may not have responded to OnUIInteract() yet.
        -- Overwriting with empty data would wipe VaultScanner's persisted data.
        PvECacheUserDebug(
            "greatVault: GetActivities empty/nil — NOT overwriting cache (key=%s). Open Great Vault or wait for server.",
            tostring(charKey))
        return 
    end
    
    if not self.db.global.pveCache.greatVault.activities then
        self.db.global.pveCache.greatVault.activities = {}
    end

    local rewardData = self.db.global.pveCache.greatVault.rewards
        and self.db.global.pveCache.greatVault.rewards[charKey]
    local rewardClaimedResetTime = rewardData and NormalizeResetEpoch(rewardData.claimedResetTime) or nil
    local previousActivities = self.db.global.pveCache.greatVault.activities[charKey]
    local previousResetTime = GetCurrentWeeklyResetStartTime()
    local rewardClaimedThisReset = rewardClaimedResetTime and previousResetTime and rewardClaimedResetTime >= previousResetTime
    local incomingCompletedRows = false
    for i = 1, #activities do
        local activity = activities[i]
        local progress = activity and tonumber(activity.progress) or 0
        local threshold = activity and tonumber(activity.threshold) or 0
        if threshold > 0 and progress >= threshold then
            incomingCompletedRows = true
            break
        end
    end
    local preserveRows, markPostReset = ShouldPreserveCompletedVaultRows(
        previousActivities, incomingCompletedRows, rewardClaimedThisReset, previousResetTime)
    if preserveRows then
        PvECacheUserDebug(
            "greatVault: preserve completed rows key=%s incomingComplete=no postReset=%s",
            tostring(charKey), markPostReset and "yes" or "no")
        -- Mark as post-reset so PveUI shows this week's 0 progress while vault button
        -- still knows there's an unclaimed chest sitting from last week.
        if markPostReset and previousActivities then
            previousActivities.isPostReset = true
        end
        return
    end
    
    -- Calculate weekly reset time for metadata
    local weeklyResetTime = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and NormalizeResetEpoch(GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()) or 0
    
    -- Create fresh arrays only when we have real data (prevent stale duplicates)
    -- isPostReset is cleared here since we now have real this-week data
    self.db.global.pveCache.greatVault.activities[charKey] = {
        raids = {},
        mythicPlus = {},
        pvp = {},
        world = {},
        lastUpdate = time(),
        weeklyResetTime = weeklyResetTime,
    }
    
    local charData = self.db.global.pveCache.greatVault.activities[charKey]
    
    for i = 1, #activities do
        local activity = activities[i]
        if activity then
            local data = {
                type = activity.type,
                index = activity.index,
                progress = activity.progress,
                threshold = activity.threshold,
                level = activity.level,
                id = activity.id,
                activityTierID = activity.activityTierID,
                raidString = activity.raidString,
                rewards = activity.rewards or nil,
            }
            
            -- Extract reward item level using GetExampleRewardItemHyperlinks
            if activity.id and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
                local currentLink, upgradeLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
                if currentLink then
                    local effectiveILvl, _, baseILvl = C_Item.GetDetailedItemLevelInfo(currentLink)
                    data.rewardItemLevel = effectiveILvl or baseILvl or 0
                end
            end
            
            -- Capture encounter info for raid slots (Blizzard's GetActivityEncounterInfo)
            if activity.type == Enum.WeeklyRewardChestThresholdType.Raid
                and C_WeeklyRewards.GetActivityEncounterInfo then
                local encounters = C_WeeklyRewards.GetActivityEncounterInfo(activity.type, activity.index)
                    if encounters and #encounters > 0 then
                        -- EJ APIs require Blizzard_EncounterJournal to be loaded
                        if not EJ_GetEncounterInfo and not InCombatLockdown() and Utilities and Utilities.SafeLoadAddOn then
                            Utilities:SafeLoadAddOn("Blizzard_EncounterJournal")
                        end
                    data.encounters = {}
                    -- Raw API fields can be secret (difficultyID, encounter IDs); never persist a secret.
                    -- issecretvalue(nil) is false, so no nil test (comparing a secret is itself forbidden).
                    local function plain(v)
                        if issecretvalue and issecretvalue(v) then return nil end
                        return v
                    end
                    for ei = 1, #encounters do
                        local enc = encounters[ei]
                        local encName, instanceID
                        if EJ_GetEncounterInfo and enc.encounterID
                            and not (issecretvalue and issecretvalue(enc.encounterID)) then
                            local okEj, name, _, _, _, instID = pcall(EJ_GetEncounterInfo, enc.encounterID)
                            if okEj then
                                encName = name
                                instanceID = instID
                            end
                        end
                        local instanceName
                        if instanceID and EJ_GetInstanceInfo
                            and not (issecretvalue and issecretvalue(instanceID)) then
                            local okIn, instNm = pcall(EJ_GetInstanceInfo, instanceID)
                            if okIn and instNm and not (issecretvalue and issecretvalue(instNm)) then
                                instanceName = instNm
                            end
                        end
                        local diffName
                        local bestDiff = enc.bestDifficulty
                        if bestDiff and issecretvalue and issecretvalue(bestDiff) then bestDiff = nil end
                        if type(bestDiff) == "number" and bestDiff > 0 then
                            if DifficultyUtil and DifficultyUtil.GetDifficultyName then
                                diffName = DifficultyUtil.GetDifficultyName(bestDiff)
                            elseif GetDifficultyInfo then
                                diffName = GetDifficultyInfo(bestDiff)
                            end
                        end
                        -- Guard secret values
                        if issecretvalue and encName and issecretvalue(encName) then encName = nil end
                        if issecretvalue and instanceName and issecretvalue(instanceName) then instanceName = nil end
                        if issecretvalue and diffName and issecretvalue(diffName) then diffName = nil end
                        data.encounters[ei] = {
                            encounterID = plain(enc.encounterID),
                            bestDifficulty = bestDiff,
                            uiOrder = plain(enc.uiOrder),
                            instanceID = plain(enc.instanceID) or plain(instanceID),
                            name = encName,
                            instanceName = instanceName,
                            difficultyName = diffName,
                        }
                    end
                end
            end
            
            -- Categorize by activity type
            if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
                table.insert(charData.raids, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
                table.insert(charData.mythicPlus, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                table.insert(charData.pvp, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
                table.insert(charData.world, data)
            end
        end
    end
    
    -- Capture dungeon run counts (Heroic/Mythic/M+ separately)
    if C_WeeklyRewards.GetNumCompletedDungeonRuns then
        local numHeroic, numMythic, numMythicPlus = C_WeeklyRewards.GetNumCompletedDungeonRuns()
        charData.dungeonRunCounts = {
            heroic = numHeroic or 0,
            mythic = numMythic or 0,
            mythicPlus = numMythicPlus or 0,
        }
    end
    
    -- Capture sorted world/delve tier progress
    if C_WeeklyRewards.GetSortedProgressForActivity and Enum.WeeklyRewardChestThresholdType.World then
        local ok, worldProgress = pcall(C_WeeklyRewards.GetSortedProgressForActivity,
            Enum.WeeklyRewardChestThresholdType.World, true)
        if ok and worldProgress and #worldProgress > 0 then
            charData.worldTierProgress = {}
            for wi = 1, #worldProgress do
                charData.worldTierProgress[wi] = {
                    activityTierID = worldProgress[wi].activityTierID,
                    difficulty = worldProgress[wi].difficulty,
                    numPoints = worldProgress[wi].numPoints,
                }
            end
        end
    end
    
    PvECacheUserDebug(
        "greatVault: SAVED key=%s activities=%d raidSlots=%d mPlusSlots=%d worldSlots=%d pvpSlots=%d apiZeroSkipped=no",
        tostring(charKey),
        #activities,
        #(charData.raids or {}),
        #(charData.mythicPlus or {}),
        #(charData.world or {}),
        #(charData.pvp or {}))
        
    -- Save to DB after data is populated
    WarbandNexus:SavePvECache()
    
    -- NOTE: PVE_UPDATED is NOT fired here. Both callers (UpdatePvEData and
    -- OnVaultDataReceived) fire PVE_UPDATED after this function returns.
    -- Firing here caused a DOUBLE event within milliseconds, and the UI's
    -- 800ms cooldown silently dropped the second (important) one.
end

---Update Great Vault reward availability
---Only sets hasAvailableRewards when rewards are for current period and claimable
---(uses AreRewardsForCurrentRewardPeriod/CanClaimRewards when available; avoids post-season stale true).
function WarbandNexus:UpdateGreatVaultRewards(charKey, allowClaimTransition)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    charKey = CanonicalizePvEKey(charKey)

    if allowClaimTransition == nil and vaultState.vaultClaimAllowUntil > 0 and GetTime() < vaultState.vaultClaimAllowUntil then
        allowClaimTransition = true
    end

    if not self.db.global.pveCache.greatVault.rewards then
        self.db.global.pveCache.greatVault.rewards = {}
    end
    local rewardsTable = self.db.global.pveCache.greatVault.rewards
    local previousRewardData = LookupVaultRewardsEntry(rewardsTable, charKey)
    local isSessionChar = IsSessionPvECharacter(charKey)

    -- C_WeeklyRewards.* is scoped to the logged-in character only — never apply live reads to alt rows.
    local hasAvailable = false
    if isSessionChar then
        hasAvailable = ns.WeeklyVaultHasPendingRewards()
    else
        hasAvailable = previousRewardData and previousRewardData.hasAvailableRewards == true or false
        if allowClaimTransition ~= true then
            return
        end
    end
    local previousResetTime = GetCurrentWeeklyResetStartTime()
    local claimedResetTime = previousRewardData and NormalizeResetEpoch(previousRewardData.claimedResetTime) or nil
    local claimedAt = previousRewardData and tonumber(previousRewardData.claimedAt) or nil

    -- Determine if the vault was effectively "ready" before this update.
    -- This covers both the normal case (hasAvailableRewards=true) and the post-reset
    -- case where the chest was sitting unclaimed (isPostReset activities + reset crossed).
    local activities = self.db.global.pveCache.greatVault.activities
        and self.db.global.pveCache.greatVault.activities[charKey]
    local wasPostResetReady = activities and activities.isPostReset
        -- weeklyResetTime is the NEXT reset as of the snapshot; once normalized it equals the new
        -- week's start exactly, so "crossed" is <=, not <.
        and previousResetTime and (NormalizeResetEpoch(activities.weeklyResetTime) or 0) <= previousResetTime

    if hasAvailable == false and (
        (previousRewardData and previousRewardData.hasAvailableRewards == true)
        or wasPostResetReady
    ) then
        local vaultFrameShown = WeeklyRewardsFrame and WeeklyRewardsFrame.IsShown and WeeklyRewardsFrame:IsShown()
        -- After WEEKLY_REWARDS_UPDATE, HasAvailableRewards() is reliable. Without this branch,
        -- UpdatePvEData() calls this with allowClaimTransition=nil and (frame closed) would
        -- resurrect hasAvailableRewards=true right after a real claim (race with
        -- WEEKLY_REWARDS_ITEM_CHANGED's deferred refresh).
        local trustNoRewardsWhenVaultFresh = false
        if vaultState.vaultDataFreshThisSession and C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards then
            local ok, avail = pcall(C_WeeklyRewards.HasAvailableRewards)
            trustNoRewardsWhenVaultFresh = ok and avail == false
        end
        if vaultFrameShown or allowClaimTransition == true or trustNoRewardsWhenVaultFresh then
            claimedResetTime = previousResetTime
            claimedAt = time()
            -- The chest is now claimed, so last reset's completed rows are consumed. Drop the stale
            -- slot data (not just the isPostReset flag): clearing only the flag exposed those pre-reset
            -- completed rows as current progress whenever the follow-up ProcessGreatVaultActivities
            -- early-returned (GetActivities not ready yet), pinning the PvE row on "Pending..." until a
            -- /reload. Empty rows read as no-progress (em-dash); a fresh scan repopulates this week.
            if activities then
                activities.raids = {}
                activities.mythicPlus = {}
                activities.pvp = {}
                activities.world = {}
                activities.isPostReset = nil
            end
        else
            hasAvailable = true
        end
    end

    -- GUARD: If HasAvailableRewards() returned false but vault data hasn't been confirmed
    -- fresh this session (WEEKLY_REWARDS_UPDATE not yet fired), don't write false —
    -- the API returns false on login before OnUIInteract() is called and the server
    -- responds. Leave the existing cached value intact to preserve unclaimed vault status.
    if not hasAvailable and not vaultState.vaultDataFreshThisSession
        and not (allowClaimTransition == true)
        and not (WeeklyRewardsFrame and WeeklyRewardsFrame.IsShown and WeeklyRewardsFrame:IsShown()) then
        DebugPrint("|cff9370DB[PvECache]|r UpdateGreatVaultRewards: skipping false write — vault data not fresh this session")
        return
    end

    WriteVaultRewardsCache(charKey, {
        hasAvailableRewards = hasAvailable,
        lastUpdate = time(),
        claimedAt = claimedAt,
        claimedResetTime = claimedResetTime,
    })
end

---Analyze weekly Great Vault runs to calculate dead run floor and upgrade thresholds.
---@param charKey string|nil Canonical character key (defaults to current session)
---@return table Analysis result { mythicPlus = table, world = table }
function WarbandNexus:GetVaultDeadRunAnalysis(charKey)
    local pve = self:GetPvEData(charKey) or {}
    local analysis = {
        mythicPlus = {
            totalRuns = 0,
            deadRunFloor = nil,
            deadRunsCount = 0,
            slotTargets = {},
            sortedRuns = {},
        },
        world = {
            totalActivities = 0,
            deadRunFloor = nil,
            deadRunsCount = 0,
            slotTargets = {},
            sortedActivities = {},
        },
    }

    -- 1. Mythic+ Analysis
    local rawRuns = pve.mythicPlus and pve.mythicPlus.runHistory
    local runs = {}
    if rawRuns and type(rawRuns) == "table" then
        for i = 1, #rawRuns do
            local r = rawRuns[i]
            if r and type(r) == "table" then
                runs[#runs + 1] = {
                    level = tonumber(r.level) or 0,
                    mapChallengeModeID = r.mapChallengeModeID,
                    dungeon = r.dungeon or r.name,
                }
            end
        end
    end
    table.sort(runs, function(a, b)
        local aLvl = a.level or 0
        local bLvl = b.level or 0
        if aLvl ~= bLvl then return aLvl > bLvl end
        return (a.mapChallengeModeID or 0) < (b.mapChallengeModeID or 0)
    end)
    analysis.mythicPlus.sortedRuns = runs
    analysis.mythicPlus.totalRuns = #runs

    local mplusThresholds = { 1, 4, 8 }
    local mplusBaseRuns = { 1, 4, 8 }
    if #runs >= 8 then
        analysis.mythicPlus.deadRunFloor = runs[8].level
        analysis.mythicPlus.deadRunsCount = #runs - 8
    end

    for s = 1, 3 do
        local thresh = mplusThresholds[s]
        local baseIdx = mplusBaseRuns[s]
        local runAtBase = runs[baseIdx]
        local isUnlocked = (#runs >= thresh)
        local curLevel = (isUnlocked and runAtBase) and runAtBase.level or 0
        local nextNeeded = isUnlocked and (curLevel + 1) or nil
        analysis.mythicPlus.slotTargets[s] = {
            slotIndex = s,
            threshold = thresh,
            baseRunIndex = baseIdx,
            isUnlocked = isUnlocked,
            currentLevel = curLevel,
            nextLevelNeeded = nextNeeded,
            runsRemaining = isUnlocked and 0 or (thresh - #runs),
        }
    end

    -- 2. World / Delves Analysis
    local worldTierProgress = pve.vaultActivities and pve.vaultActivities.worldTierProgress
    local worldActivities = {}
    if worldTierProgress and type(worldTierProgress) == "table" then
        for wi = 1, #worldTierProgress do
            local entry = worldTierProgress[wi]
            local count = tonumber(entry.numPoints) or 0
            local tier = tonumber(entry.difficulty) or 0
            for _ = 1, count do
                worldActivities[#worldActivities + 1] = { tier = tier }
            end
        end
    end
    table.sort(worldActivities, function(a, b)
        return (a.tier or 0) > (b.tier or 0)
    end)
    analysis.world.sortedActivities = worldActivities
    analysis.world.totalActivities = #worldActivities

    local worldThresholds = { 2, 4, 8 }
    local worldBaseActivities = { 2, 4, 8 }
    if #worldActivities >= 8 then
        analysis.world.deadRunFloor = worldActivities[8].tier
        analysis.world.deadRunsCount = #worldActivities - 8
    end

    for s = 1, 3 do
        local thresh = worldThresholds[s]
        local baseIdx = worldBaseActivities[s]
        local actAtBase = worldActivities[baseIdx]
        local isUnlocked = (#worldActivities >= thresh)
        local curTier = (isUnlocked and actAtBase) and actAtBase.tier or 0
        local nextNeeded = isUnlocked and (curTier + 1) or nil
        analysis.world.slotTargets[s] = {
            slotIndex = s,
            threshold = thresh,
            baseRunIndex = baseIdx,
            isUnlocked = isUnlocked,
            currentTier = curTier,
            nextTierNeeded = nextNeeded,
            activitiesRemaining = isUnlocked and 0 or (thresh - #worldActivities),
        }
    end

    return analysis
end

-- VAULT CLAIM / KEYSTONE SYNC (Easy Access, PvE tab, Vault Tracker)

-- Blizzard only asks the server to resend Great Vault data when the Great Vault window opens
-- (WeeklyRewardsMixin:OnShow calls C_WeeklyRewards.OnUIInteract). Until that happens the live
-- C_WeeklyRewards state stays whatever it was at login -- which is why the Easy Access badge used
-- to require a visit to that screen before it noticed a claimed or newly-filled vault. We make the
-- same call ourselves on the events that can change vault state. Throttled: it is a server
-- round-trip and several of those events burst (UPDATE_INSTANCE_INFO repeats while zoning).
local lastWeeklyVaultPoke = 0
local WEEKLY_VAULT_POKE_THROTTLE = 2.0

local function PokeWeeklyVaultServer()
    if not (C_WeeklyRewards and C_WeeklyRewards.OnUIInteract) then return end
    local now = (GetTime and GetTime()) or 0
    if lastWeeklyVaultPoke > 0 and (now - lastWeeklyVaultPoke) < WEEKLY_VAULT_POKE_THROTTLE then
        return
    end
    lastWeeklyVaultPoke = now
    pcall(C_WeeklyRewards.OnUIInteract)
end

---Ask the server to resend Great Vault data so the badge can update without the player having to
---open the Great Vault. The reply arrives as WEEKLY_REWARDS_UPDATE, which already refreshes the
---cache and the badge.
---@param delay number|nil seconds to wait first (let the server settle after a claim)
function WarbandNexus:RequestWeeklyVaultRefresh(delay)
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then return end
    if delay and delay > 0 then
        C_Timer.After(delay, PokeWeeklyVaultServer)
    else
        PokeWeeklyVaultServer()
    end
end

---Redraw Easy Access badge / tracker immediately (not gated on main window visibility).
function WarbandNexus:NotifyVaultEasyAccessRefresh()
    local VB = ns.VaultButton
    if not VB then return end
    if VB.BuildButton and not (VB.state and VB.state.badge) then
        VB.BuildButton()
    end
    -- This runs right after a claim / keystone write, so the memoized vault snapshot is stale by
    -- definition. Invalidate BEFORE the immediate UpdateBadge below, otherwise the badge would
    -- re-render the pre-claim count and only correct itself on the deferred refresh.
    if VB.InvalidateVaultSnapshot then
        VB.InvalidateVaultSnapshot()
    end
    if VB.UpdateBadge then
        VB.UpdateBadge()
    end
    if VB.ScheduleDataRefresh then
        VB.ScheduleDataRefresh()
    end
end

---Persist "this character's vault is not waiting" while we are logged into them, so the row cannot
---be resurrected once they drop into the background.
---
---CharHasClaimableVaultReward has TWO ways to call a background character claimable: the cached
---`hasAvailableRewards` flag, and the earned-slots + reset-crossed heuristic. This used to heal only
---the first, so a character that qualified via the heuristic never got a claim stamp -- it read
---correctly from the live API while you played it, then went back to "reward waiting" the moment you
---switched away, forever. Stamp the claim whenever EITHER path would still report it claimable.
function WarbandNexus:HealStaleVaultRewardsCache(charKey)
    if not charKey or not self.db or not self.db.global or not self.db.global.pveCache then
        return
    end
    charKey = CanonicalizePvEKey(charKey)
    if not charKey or not IsSessionPvECharacter(charKey) then
        return
    end
    -- Never stamp "claimed" from live data the server has not sent yet. Before
    -- WEEKLY_REWARDS_UPDATE lands, HasAvailableRewards() reports false even for a vault that IS
    -- waiting, and stamping that would hide a real reward for the rest of the week.
    if not vaultState.vaultDataFreshThisSession then
        return
    end
    if ns.WeeklyVaultHasPendingRewards() then
        return
    end
    local rewardsTable = self.db.global.pveCache.greatVault and self.db.global.pveCache.greatVault.rewards
    local row = LookupVaultRewardsEntry(rewardsTable, charKey)
    -- Already stamped for this reward period: nothing to do.
    if row and ns.VaultRewardsClaimedForCurrentWeek and ns.VaultRewardsClaimedForCurrentWeek(row) then
        return
    end
    local flagSaysReady = (row and row.hasAvailableRewards == true) or false
    local heuristicSaysReady = (ns.CountEarnedVaultSlots and ns.VaultResetCrossedFor
        and (ns.CountEarnedVaultSlots(charKey) or 0) > 0
        and ns.VaultResetCrossedFor(charKey)) or false
    if not flagSaysReady and not heuristicSaysReady then
        return
    end
    local stamp = time()
    local currentWeekStart = GetCurrentWeeklyResetStartTime()
    -- The stamp MUST describe the current reward period. Carrying an older claimedResetTime /
    -- claimedAt forward (what this used to do whenever the row already had one) re-wrote last
    -- week's stamp verbatim, so VaultRewardsClaimedForCurrentWeek stayed false and the
    -- earned-slots heuristic kept reporting the character as "reward waiting" from every other
    -- character -- the heal ran every time and changed nothing.
    local priorClaimedAt = (row and tonumber(row.claimedAt)) or 0
    local claimedAt = stamp
    if currentWeekStart and priorClaimedAt >= currentWeekStart then
        claimedAt = priorClaimedAt  -- genuine claim already made inside this period: keep its time
    end
    WriteVaultRewardsCache(charKey, {
        hasAvailableRewards = false,
        lastUpdate = stamp,
        claimedAt = claimedAt,
        claimedResetTime = currentWeekStart,
    })
    self:SavePvECache()
end

---Print exactly why each tracked character is (or is not) counted as having an unclaimed Great
---Vault. Run it on the character whose vault you just looted, then on another character, and
---compare: the row stamps and the two "claimable" paths show which one is keeping it counted.
function WarbandNexus:PrintVaultDiagnostics()
    local pveCache = self.db and self.db.global and self.db.global.pveCache
    if not pveCache then
        self:Print("|cffff6600[WN Vault]|r no pveCache.")
        return
    end
    local resetStart = GetCurrentWeeklyResetStartTime()
    self:Print(string.format("|cff9370DB[WN Vault]|r session=%s dataFresh=%s weekStart=%s",
        tostring(GetSessionCanonicalPvEKey()), tostring(vaultState.vaultDataFreshThisSession), tostring(resetStart)))

    local liveHas, livePeriod = "n/a", "n/a"
    if C_WeeklyRewards then
        if C_WeeklyRewards.HasAvailableRewards then
            local ok, v = pcall(C_WeeklyRewards.HasAvailableRewards)
            liveHas = ok and tostring(v) or "err"
        end
        if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod then
            local ok, v = pcall(C_WeeklyRewards.AreRewardsForCurrentRewardPeriod)
            livePeriod = ok and tostring(v) or "err"
        end
    end
    self:Print(string.format("  live: hasAvailable=%s currentPeriod=%s pending=%s fromPrevPeriod=%s",
        liveHas, livePeriod, tostring(ns.WeeklyVaultHasPendingRewards()),
        tostring(ns.WeeklyVaultRewardsAreFromPreviousPeriod
            and ns.WeeklyVaultRewardsAreFromPreviousPeriod())))

    local characters = (self.db.global and self.db.global.characters) or {}
    local rewards = pveCache.greatVault and pveCache.greatVault.rewards
    for rosterKey, charData in pairs(characters) do
        if type(charData) == "table" and charData.isTracked == true then
            local row = rewards and LookupVaultRewardsEntry(rewards, rosterKey)
            local claimedWeek = row and ns.VaultRewardsClaimedForCurrentWeek
                and ns.VaultRewardsClaimedForCurrentWeek(row)
            local earned = (ns.CountEarnedVaultSlots and ns.CountEarnedVaultSlots(rosterKey)) or 0
            local crossed = ns.VaultResetCrossedFor and ns.VaultResetCrossedFor(rosterKey)
            local verdict = ns.CharHasClaimableVaultReward and ns.CharHasClaimableVaultReward(rosterKey)
            self:Print(string.format("|cffffcc00%s|r canon=%s isSession=%s",
                tostring(charData.name or rosterKey), tostring(CanonicalizePvEKey(rosterKey)),
                tostring(IsSessionPvECharacter(rosterKey))))
            if row then
                self:Print(string.format("   row: has=%s claimedAt=%s claimedReset=%s claimedThisWeek=%s",
                    tostring(row.hasAvailableRewards), tostring(row.claimedAt),
                    tostring(row.claimedResetTime), tostring(claimedWeek)))
            else
                self:Print("   row: <none>")
            end
            self:Print(string.format("   earnedSlots=%s resetCrossed=%s  => CLAIMABLE=%s",
                tostring(earned), tostring(crossed), tostring(verdict)))
        end
    end
end

---Toast only on false→true claimable transition (not after claim clears the chest).
local function SessionVaultWasClaimable(addon, charKey)
    if not charKey or not IsSessionPvECharacter(charKey) then
        return false
    end
    if ns.WeeklyVaultHasPendingRewards and ns.WeeklyVaultHasPendingRewards() then
        return true
    end
    local rewardsTable = addon.db and addon.db.global and addon.db.global.pveCache
        and addon.db.global.pveCache.greatVault and addon.db.global.pveCache.greatVault.rewards
    local row = LookupVaultRewardsEntry(rewardsTable, charKey)
    if row and row.hasAvailableRewards == true then
        return true
    end
    if ns.CharHasClaimableVaultReward and ns.CharHasClaimableVaultReward(charKey) then
        return true
    end
    return false
end

-- charKey -> true once the "Weekly Vault Ready" toast was shown this session.
local vaultReadyToastShown = {}

---Toast once per session while rewards wait (including rewards already waiting at login),
---and again after a claim once a new reward appears. `wasClaimable` is not used: it reads
---the live API, so at login it already reports "claimable" and the toast never fired.
local function EmitVaultReadyToastIfNewlyClaimable(addon, charKey, wasClaimable, claimableNow)
    if not charKey then return end
    if not claimableNow then
        vaultReadyToastShown[charKey] = nil  -- claimed / nothing waiting: re-arm
        return
    end
    if vaultReadyToastShown[charKey] then
        return
    end
    if not addon or not addon.SendMessage or not Constants or not Constants.EVENTS then
        return
    end
    vaultReadyToastShown[charKey] = true
    if Constants.EVENTS.VAULT_REWARD_AVAILABLE then
        addon:SendMessage(Constants.EVENTS.VAULT_REWARD_AVAILABLE, {
            charKey = charKey,
            claimable = true,
        })
    end
end

---After claiming a Great Vault reward (or closing the vault UI): refresh reward flags,
---keystone (vault can grant a key), and emit WN_PVE_UPDATED for all vault UIs.
function WarbandNexus:RefreshVaultClaimState(charKey)
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    if not charKey then
        charKey = GetSessionCanonicalPvEKey()
    else
        charKey = CanonicalizePvEKey(charKey)
    end
    if not charKey or not self.db or not self.db.global or not self.db.global.pveCache then
        return
    end

    local wasClaimable = SessionVaultWasClaimable(self, charKey)

    ns._vaultClaimSubjectKey = charKey
    vaultState.vaultDataFreshThisSession = true
    vaultState.vaultClaimAllowUntil = GetTime() + 3

    keystoneLastSeen[charKey] = nil
    keystoneRetryCount[charKey] = nil
    if C_MythicPlus then
        if C_MythicPlus.RequestMapInfo then
            pcall(C_MythicPlus.RequestMapInfo)
        end
        if C_MythicPlus.RequestRewards then
            pcall(C_MythicPlus.RequestRewards)
        end
    end
    if C_WeeklyRewards and C_WeeklyRewards.OnUIInteract then
        pcall(C_WeeklyRewards.OnUIInteract)
    end

    local beforeSig = BuildPvESignature(self.db.global.pveCache, charKey)
    if self.RequestKeystoneRefresh then
        self:RequestKeystoneRefresh("vaultClaim", true)
    else
        self:UpdateCharacterKeystone(charKey)
    end
    self:UpdateGreatVaultRewards(charKey, true)
    local claimableNow = IsSessionPvECharacter(charKey) and ns.WeeklyVaultHasPendingRewards()
    if not claimableNow then
        WriteVaultRewardsCache(charKey, {
            hasAvailableRewards = false,
            lastUpdate = time(),
            claimedAt = time(),
            claimedResetTime = GetCurrentWeeklyResetStartTime(),
        })
    end
    self:SavePvECache()
    local afterSig = BuildPvESignature(self.db.global.pveCache, charKey)

    if ns.PvE_ClearVaultStatusScratch then
        ns.PvE_ClearVaultStatusScratch()
    end

    local rewardsCleared = not claimableNow
    if rewardsCleared and IsSessionPvECharacter(charKey) then
        self:ProcessGreatVaultActivities(charKey)
        self:SavePvECache()
        afterSig = BuildPvESignature(self.db.global.pveCache, charKey)
        if ns.PvE_ClearVaultStatusScratch then
            ns.PvE_ClearVaultStatusScratch()
        end
    end

    NotifyVaultEasyAccessRefresh()

    C_Timer.After(0.2, function()
        if not WarbandNexus or not WarbandNexus.ProcessGreatVaultActivities then return end
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
        local sigBefore = BuildPvESignature(WarbandNexus.db.global.pveCache, charKey)
        WarbandNexus:ProcessGreatVaultActivities(charKey)
        WarbandNexus:SavePvECache()
        local sigAfter = BuildPvESignature(WarbandNexus.db.global.pveCache, charKey)
        if sigBefore == sigAfter then return end
        if ns.PvE_ClearVaultStatusScratch then
            ns.PvE_ClearVaultStatusScratch()
        end
        if WarbandNexus.SendMessage and Constants and Constants.EVENTS and Constants.EVENTS.PVE_UPDATED then
            WarbandNexus:SendMessage(Constants.EVENTS.PVE_UPDATED)
        end
        NotifyVaultEasyAccessRefresh()
    end)

    if self.SendMessage and Constants and Constants.EVENTS then
        if beforeSig ~= afterSig and Constants.EVENTS.PVE_UPDATED then
            self:SendMessage(Constants.EVENTS.PVE_UPDATED)
        end
        EmitVaultReadyToastIfNewlyClaimable(self, charKey, wasClaimable, claimableNow)
        if beforeSig ~= afterSig and Constants.EVENTS.CHARACTER_UPDATED then
            self:SendMessage(Constants.EVENTS.CHARACTER_UPDATED, { charKey = charKey, dataType = "vaultClaim" })
        end
    end
end

---After a Great Vault claim, the live C_WeeklyRewards "available" state trails the server by a few
---seconds. Re-check on a self-terminating backoff so the Easy Access badge and PvE row clear on their
---own -- the player never has to open the PvE tab or /reload. Each step re-pokes OnUIInteract and
---force-refreshes the badge, and it stops the instant the character is no longer counted claimable.
---Only ever stamps "claimed" once the live API confirms no rewards remain, so it cannot hide a real
---reward. A per-character generation token means a fresh claim supersedes any in-flight ladder.
function WarbandNexus:SchedulePostClaimVaultHeal(charKey)
    charKey = charKey or ns._weeklyRewardsInteractCharKey or ns._vaultClaimSubjectKey
    if not charKey or not C_Timer or not C_Timer.After then return end
    ns._vaultPostClaimHealGen = ns._vaultPostClaimHealGen or {}
    local gen = (ns._vaultPostClaimHealGen[charKey] or 0) + 1
    ns._vaultPostClaimHealGen[charKey] = gen
    local delays = { 0.2, 0.5, 1.0, 1.8, 3.0, 5.0, 8.0, 12.0, 18.0, 25.0 }
    local function step(i)
        if not WarbandNexus or ns._vaultPostClaimHealGen[charKey] ~= gen then return end
        if WarbandNexus.RefreshVaultClaimState then
            WarbandNexus:RefreshVaultClaimState(charKey)
        end
        NotifyVaultEasyAccessRefresh()
        local stillClaimable = ns.CharHasClaimableVaultReward and ns.CharHasClaimableVaultReward(charKey)
        if not stillClaimable or i >= #delays then
            if ns._vaultPostClaimHealGen[charKey] == gen then
                ns._vaultPostClaimHealGen[charKey] = nil
            end
            return
        end
        C_Timer.After(delays[i + 1], function() step(i + 1) end)
    end
    C_Timer.After(delays[1], function() step(1) end)
end

-- WEEKLY REWARDS FRAME HOOKS

---Hook Blizzard WeeklyRewardsFrame hide so claim/close clears cached Ready state promptly.
function WarbandNexus:EnsureWeeklyRewardsFrameHooks()
    if ns._weeklyRewardsFrameHooked then return end
    if not WeeklyRewardsFrame or not WeeklyRewardsFrame.HookScript then return end
    ns._weeklyRewardsFrameHooked = true
    WeeklyRewardsFrame:HookScript("OnShow", function()
        ns._weeklyRewardsInteractCharKey = GetSessionCanonicalPvEKey()
    end)
    WeeklyRewardsFrame:HookScript("OnHide", function()
        local charKey = ns._weeklyRewardsInteractCharKey or ns._vaultClaimSubjectKey or GetSessionCanonicalPvEKey()
        ns._weeklyRewardsInteractCharKey = nil
        if charKey and WarbandNexus.RefreshVaultClaimState then
            WarbandNexus:RefreshVaultClaimState(charKey)
            if WarbandNexus.SchedulePostClaimVaultHeal then
                WarbandNexus:SchedulePostClaimVaultHeal(charKey)
            end
        end
    end)
end

---Handle WEEKLY_REWARDS_UPDATE event (vault data received from server)
---NOTE: Named OnVaultDataReceived to avoid collision with PlansManager:OnPvEUpdateCheckPlans
---ARCHITECTURE: Vault activities are processed by VaultScanner → SyncVaultDataFromScanner.
---This handler only updates NON-vault data (keystone, best runs, rewards) to avoid
---overwriting VaultScanner's richer data (nextLevelIlvl, maxIlvl, nextKeyLevel).
function WarbandNexus:OnVaultDataReceived()
    local P = ns.Profiler
    if P and P.RunSlice then
        return P:RunSlice(P.CAT.SVC, "PvE_VaultDataReceived", WarbandNexus._OnVaultDataReceivedBody, self)
    end
    return WarbandNexus:_OnVaultDataReceivedBody(self)
end

function WarbandNexus:_OnVaultDataReceivedBody()
    ns._pveVaultHandlerActive = true
    local function releaseVaultBagDefer()
        ns._pveVaultHandlerActive = nil
        local pendingBags = ns._pendingBagUpdateAfterVault
        ns._pendingBagUpdateAfterVault = nil
        if pendingBags and self.OnBagUpdate then
            C_Timer.After(0, function()
                if self and self.OnBagUpdate then
                    self:OnBagUpdate(pendingBags)
                end
            end)
        end
    end

    local charKey = GetSessionCanonicalPvEKey()
    if not charKey then
        releaseVaultBagDefer()
        return
    end
    local wasClaimable = SessionVaultWasClaimable(self, charKey)
    local beforeSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    
    -- DO NOT call ProcessGreatVaultActivities here!
    -- VaultScanner handles vault activities via SyncVaultDataFromScanner (richer data).
    -- Calling it here would overwrite VaultScanner's enhanced data with basic data.
    
    -- Update non-vault PvE data
    self:UpdateCharacterKeystone(charKey)
    self:UpdateMythicPlusBestRuns(charKey)
    self:UpdateGreatVaultRewards(charKey)

    -- The server has just confirmed this character's vault state (this handler only runs on
    -- WEEKLY_REWARDS_UPDATE), so persist "nothing waiting" right here. Previously that fact was
    -- only written if the badge happened to recompute while this character was logged in, so a
    -- character whose vault was already looted went straight back to reporting an unclaimed
    -- reward the moment you switched to another character.
    if IsSessionPvECharacter(charKey) and self.HealStaleVaultRewardsCache then
        self:HealStaleVaultRewardsCache(charKey)
    end

    -- Update timestamp (data already in DB)
    self:SavePvECache()
    
    local claimableNow = IsSessionPvECharacter(charKey) and ns.WeeklyVaultHasPendingRewards()
    local afterSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    if beforeSig ~= afterSig then
        self:SendMessage(Constants.EVENTS.PVE_UPDATED)
    end
    EmitVaultReadyToastIfNewlyClaimable(self, charKey, wasClaimable, claimableNow)
    releaseVaultBagDefer()
end

---Sync vault data from VaultScanner to PvECacheService
function WarbandNexus:SyncVaultDataFromScanner(vaultSlots)
    if not vaultSlots or type(vaultSlots) ~= "table" then
        return
    end
    -- GUARD: never persist vault data for an untracked character. VaultScanner registers
    -- PLAYER_ENTERING_WORLD / WEEKLY_REWARDS_UPDATE unconditionally, so it fires on every login --
    -- but untracked characters must stay Characters-tab only, with no per-character vault rows in
    -- SavedVariables. This mirrors the tracked-gate every sibling PvE writer already has
    -- (UpdatePvEData / UpdateCharacterKeystone / UpdateGreatVaultRewards).
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    -- Never sync an empty slot list into SavedVariables: callers should use
    -- VaultScanner only after GetActivities() returned data. An empty table
    -- would clear per-character vault rows without replacing them.
    if #vaultSlots == 0 then
        return
    end
    
    -- LAZY INIT: VaultScanner fires on PLAYER_ENTERING_WORLD (T+1s),
    -- but InitializePvECache runs at T+2s. On first install, pveCache
    -- doesn't exist yet. Initialize it here so vault data isn't lost.
    if not self.db or not self.db.global then return end
    if not self.db.global.pveCache then
        self:InitializePvECache()
    end
    if not self.db.global.pveCache then return end
    
    -- Must match PvEUI / GetPvEData: one bucket per character after realm normalization.
    local charKey = GetSessionCanonicalPvEKey()
    if not charKey then return end
    local beforeSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    
    if not self.db.global.pveCache.greatVault.activities then
        self.db.global.pveCache.greatVault.activities = {}
    end
    
    if not self.db.global.pveCache.greatVault.activities[charKey] then
        self.db.global.pveCache.greatVault.activities[charKey] = {
            raids = {},
            mythicPlus = {},
            pvp = {},
            world = {},
            lastUpdate = time(),
            weeklyResetTime = NormalizeResetEpoch(GetServerTime() + (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset() or 0)),
        }
    end
    
    -- PRESERVE existing iLvl data before clearing.
    -- GetExampleRewardItemHyperlinks() may return nil momentarily after a slot
    -- transitions to complete (server computing rewards). Build a lookup by
    -- activityID so known-good values survive a re-scan that returns 0.
    local activities = self.db.global.pveCache.greatVault.activities[charKey]
    -- dungeonRunCounts / worldTierProgress are written only by ProcessGreatVaultActivities together
    -- with weeklyResetTime (the NEXT reset at that snapshot). Once that reset has passed they describe
    -- last week: drop them so tooltips do not show last week's Heroic/Mythic runs and delve tiers.
    -- weeklyResetTime itself is left alone: the post-reset "chest waiting" detection reads it.
    do
        local resetStart = GetCurrentWeeklyResetStartTime()
        local snapNext = NormalizeResetEpoch(activities.weeklyResetTime)
        if resetStart and resetStart > 0 and type(snapNext) == "number" and snapNext > 0 and snapNext <= resetStart then
            activities.dungeonRunCounts = nil
            activities.worldTierProgress = nil
        end
    end
    local preservedILvl = {}
    local vaultCategories = {"raids", "mythicPlus", "pvp", "world"}
    for ci = 1, #vaultCategories do
        local category = vaultCategories[ci]
        if activities[category] then
            local catList = activities[category]
            for ai = 1, #catList do
                local a = catList[ai]
                if a.id and a.rewardItemLevel and a.rewardItemLevel > 0 then
                    preservedILvl[a.id] = {
                        rewardItemLevel = a.rewardItemLevel,
                        nextLevelIlvl = a.nextLevelIlvl or 0,
                        maxIlvl = a.maxIlvl or 0,
                    }
                end
            end
        end
    end
    
    -- Keep references so we can roll back if the scanner payload maps to zero
    -- recognized categories (e.g. unexpected typeName) — otherwise we would wipe
    -- good SavedVariables data and show "No vault data" for that character.
    local backupRaids = activities.raids
    local backupMythicPlus = activities.mythicPlus
    local backupPvp = activities.pvp
    local backupWorld = activities.world
    local hadStoredVaultRows = (backupRaids and #backupRaids > 0)
        or (backupMythicPlus and #backupMythicPlus > 0)
        or (backupPvp and #backupPvp > 0)
        or (backupWorld and #backupWorld > 0)
    local previousResetTime = GetCurrentWeeklyResetStartTime()
    local rewardData = self.db.global.pveCache.greatVault.rewards
        and self.db.global.pveCache.greatVault.rewards[charKey]
    local rewardClaimedResetTime = rewardData and NormalizeResetEpoch(rewardData.claimedResetTime) or nil
    local rewardClaimedThisReset = rewardClaimedResetTime and previousResetTime and rewardClaimedResetTime >= previousResetTime
    local incomingCompletedRows = false
    for i = 1, #vaultSlots do
        local slot = vaultSlots[i]
        local progress = slot and tonumber(slot.progress) or 0
        local threshold = slot and tonumber(slot.threshold) or 0
        if threshold > 0 and progress >= threshold then
            incomingCompletedRows = true
            break
        end
    end
    local preserveRows, markPostReset = ShouldPreserveCompletedVaultRows(
        activities, incomingCompletedRows, rewardClaimedThisReset, previousResetTime)
    if preserveRows then
        PvECacheUserDebug(
            "scanner: preserve completed vault rows key=%s incomingComplete=no postReset=%s",
            tostring(charKey), markPostReset and "yes" or "no")
        -- Mark as post-reset so PveUI shows this week's 0 progress while vault button
        -- still knows there's an unclaimed chest sitting from last week.
        if markPostReset then
            activities.isPostReset = true
        end
        return
    end
    
    -- Clear and re-populate from VaultScanner
    activities.raids = {}
    activities.mythicPlus = {}
    activities.pvp = {}
    activities.world = {}
    
    -- Convert VaultScanner format to PvECacheService format
    for i = 1, #vaultSlots do
        local slot = vaultSlots[i]
        local newILvl = slot.currentILvl or 0
        local newNextILvl = slot.nextILvl or 0
        local newMaxILvl = slot.maxILvl or 0
        
        -- Restore preserved iLvl if new scan returned 0 (server not ready)
        if newILvl == 0 and slot.activityID and preservedILvl[slot.activityID] then
            local saved = preservedILvl[slot.activityID]
            newILvl = saved.rewardItemLevel
            newNextILvl = (newNextILvl > 0) and newNextILvl or saved.nextLevelIlvl
            newMaxILvl = (newMaxILvl > 0) and newMaxILvl or saved.maxIlvl
        end
        
        local activity = {
            type = nil,  -- Will be set based on typeName
            index = slot.index,
            progress = slot.progress,
            threshold = slot.threshold,
            level = slot.level,
            id = slot.activityID,
            rewardItemLevel = newILvl,
            nextLevelIlvl = newNextILvl,
            maxIlvl = newMaxILvl,
        }
        
        -- Map typeName to Enum.WeeklyRewardChestThresholdType
        if slot.typeName == "Raid" then
            activity.type = Enum.WeeklyRewardChestThresholdType.Raid
            table.insert(activities.raids, activity)
        elseif slot.typeName == "M+" then
            activity.type = Enum.WeeklyRewardChestThresholdType.Activities
            table.insert(activities.mythicPlus, activity)
        elseif slot.typeName == "World" then
            activity.type = Enum.WeeklyRewardChestThresholdType.World
            table.insert(activities.world, activity)
        elseif slot.typeName == "PvP" then
            activity.type = Enum.WeeklyRewardChestThresholdType.RankedPvP
            table.insert(activities.pvp, activity)
        end
    end
    
    local insertedCount = #activities.raids + #activities.mythicPlus + #activities.pvp + #activities.world
    if insertedCount == 0 and hadStoredVaultRows then
        activities.raids = backupRaids or {}
        activities.mythicPlus = backupMythicPlus or {}
        activities.pvp = backupPvp or {}
        activities.world = backupWorld or {}
        return
    end
    
    -- Update timestamp
    activities.lastUpdate = time()
    -- The scanner has accepted current slot data, so any preserved post-reset
    -- placeholder state must be cleared on this mutable activities table.
    activities.isPostReset = nil
    
    -- Save to DB
    self:SavePvECache()
    
    local afterSig = BuildPvESignature(self.db.global and self.db.global.pveCache, charKey)
    if beforeSig ~= afterSig then
        -- Fire event to refresh UI only when scanner payload changed persisted state.
        self:SendMessage(Constants.EVENTS.PVE_UPDATED)
    end
end
