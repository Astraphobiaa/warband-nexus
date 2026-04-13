--[[
    Warband Nexus - PvE Cache Service
    Persistent cache for PvE data: Mythic+, Great Vault, Lockouts, Weekly Rewards
    
    Architecture:
    - Event-driven updates (MYTHIC_PLUS_CURRENT_AFFIX_UPDATE, WEEKLY_REWARDS_UPDATE, etc.)
    - DB-backed persistence (no session-only data)
    - Throttled updates (2s for rare changes)
    - Single source of truth for PvE data
    
    Events fired:
    - WN_PVE_UPDATED: PvE data changed (UI should refresh)
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local DebugPrint = ns.DebugPrint
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local Constants = ns.Constants
local CACHE_VERSION = Constants.PVE_CACHE_VERSION
local UPDATE_THROTTLE = Constants.THROTTLE.SHARED_RARE

---Midnight-safe quest completion check (pcall + secret guard).
---@param questID number
---@return boolean
local function SafeIsQuestFlaggedCompleted(questID)
    if not questID or type(questID) ~= "number" then return false end
    if not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local ok, done = pcall(C_QuestLog.IsQuestFlaggedCompleted, questID)
    if not ok or done == nil then return false end
    if issecretvalue and issecretvalue(done) then return false end
    return done == true
end

-- ============================================================================
-- NO LOCAL CACHE - DIRECT DB ACCESS ONLY
-- ============================================================================
-- Architecture: API > DB > UI (same as Reputation and Currency)
-- All data operations go directly to self.db.global.pveCache
-- No local variables, no RAM cache, no sync issues!

-- Throttle timers
local lastUpdateTime = 0
local pendingUpdate = false

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

---Initialize PvE cache from DB
---Called on addon load to restore previous scan results
function WarbandNexus:InitializePvECache()
    if not self.db.global.pveCache then
        self.db.global.pveCache = {
            mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {} },
            greatVault = { activities = {}, rewards = {} },
            lockouts = { raids = {}, worldBosses = {} },
            delves = { companion = {}, season = 0 },
            version = CACHE_VERSION,
            lastUpdate = 0,
        }
        return
    end
    
    -- Version check
    if self.db.global.pveCache.version ~= CACHE_VERSION then
        self.db.global.pveCache = {
            mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {} },
            greatVault = { activities = {}, rewards = {} },
            lockouts = { raids = {}, worldBosses = {} },
            delves = { companion = {}, season = 0 },
            version = CACHE_VERSION,
            lastUpdate = 0,
        }
        return
    end
    
    -- Ensure delves structure exists (for existing DBs pre-delves)
    if not self.db.global.pveCache.delves then
        self.db.global.pveCache.delves = { companion = {}, season = 0 }
    end
    
    -- CRITICAL: Validate and clear corrupted vault data
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

-- ============================================================================
-- MYTHIC+ DATA
-- ============================================================================

---Update current week's Mythic+ affixes (lean: only IDs stored in SV).
---Metadata (name, description, icon) resolved on-demand from C_ChallengeMode.GetAffixInfo().
function WarbandNexus:UpdateMythicPlusAffixes()
    if not C_MythicPlus or not C_ChallengeMode or not self.db.global.pveCache then return end
    
    -- CRITICAL: C_MythicPlus.GetCurrentAffixes() returns affixID list OR struct array
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
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateCharacterKeystone(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_MythicPlus or not charKey or not self.db.global.pveCache then return end
    
    local keystoneInfo = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    
    if keystoneInfo and keystoneLevel and keystoneLevel > 0 then
        if not self.db.global.pveCache.mythicPlus.keystones then
            self.db.global.pveCache.mythicPlus.keystones = {}
        end
        
        self.db.global.pveCache.mythicPlus.keystones[charKey] = {
            mapID = keystoneInfo,
            level = keystoneLevel,
            lastUpdate = time(),
        }
    else
        -- Only clear when API reports "no key" (level 0). Nil map+level often means APIs not ready yet —
        -- do not wipe a good cached key (fixes login / affix race losing alt keys).
        if keystoneLevel == 0 then
            if self.db.global.pveCache.mythicPlus.keystones then
                self.db.global.pveCache.mythicPlus.keystones[charKey] = nil
            end
        end
    end
end

---Update character's best M+ runs
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateMythicPlusBestRuns(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_MythicPlus or not charKey or not self.db.global.pveCache then return end
    
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
    
    self.db.global.pveCache.mythicPlus.bestRuns[charKey].overallScore = overallScore
    self.db.global.pveCache.mythicPlus.bestRuns[charKey].scoreSource = scoreSource
    
    -- Store best runs for each dungeon
    for i = 1, #maps do
        local mapID = maps[i]
        local _, level, _, onTime = C_MythicPlus.GetWeeklyBestForMap and C_MythicPlus.GetWeeklyBestForMap(mapID)
        if level and level > 0 then
            self.db.global.pveCache.mythicPlus.bestRuns[charKey][mapID] = {
                level = level,
                onTime = onTime or false,
                lastUpdate = time(),
            }
        end
    end
end

---Update character's dungeon scores (overall + per-dungeon breakdown)
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateDungeonScores(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_ChallengeMode or not charKey or not self.db.global.pveCache then return end
    
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
    
    -- Get overall dungeon score
    if C_ChallengeMode.GetOverallDungeonScore then
        scoreData.overallScore = C_ChallengeMode.GetOverallDungeonScore() or 0
    end
    
    -- Get per-dungeon scores (lean: only score + bestLevel stored in SV)
    -- Metadata (name, texture, timeLimit) resolved on-demand from C_ChallengeMode.GetMapUIInfo()
    local maps = C_ChallengeMode.GetMapTable()
    if maps then
        for i = 1, #maps do
            local mapID = maps[i]
            local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
            
            -- Calculate HIGHEST score from best runs
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
            
            -- Store only progress data (no metadata)
            scoreData.dungeons[mapID] = {
                score = dungeonScore,
                bestLevel = bestLevel,
            }
        end
    end
    
    scoreData.lastUpdate = time()
end

-- ============================================================================
-- GREAT VAULT DATA
-- ============================================================================

---Update Great Vault activities for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateGreatVaultActivities(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_WeeklyRewards or not charKey then return end
    
    -- SYNCHRONOUS: Process vault data already cached by WoW client (from previous OnUIInteract).
    -- ProcessGreatVaultActivities guards against empty data (returns early if GetActivities is nil/empty).
    self:ProcessGreatVaultActivities(charKey)
    
    -- NOTE: OnUIInteract() is NOT called here to avoid excessive server requests.
    -- VaultScanner handles the initial request on PLAYER_ENTERING_WORLD.
    -- PvECacheService event handlers (CHALLENGE_MODE_COMPLETED, etc.) call OnUIInteract as needed.
end

---Process Great Vault activities after server responds
---@param charKey string Character key (name-realm)
function WarbandNexus:ProcessGreatVaultActivities(charKey)
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    
    local activities = C_WeeklyRewards.GetActivities()
    if not activities or #activities == 0 then 
        -- CRITICAL: Do NOT create empty arrays when API returns nil/empty.
        -- Server may not have responded to OnUIInteract() yet.
        -- Overwriting with empty data would wipe VaultScanner's persisted data.
        return 
    end
    
    if not self.db.global.pveCache.greatVault.activities then
        self.db.global.pveCache.greatVault.activities = {}
    end
    
    -- Calculate weekly reset time for metadata
    local weeklyResetTime = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and (GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()) or 0
    
    -- Create fresh arrays only when we have real data (prevent stale duplicates)
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
                    if not EJ_GetEncounterInfo and not InCombatLockdown() then
                        pcall(C_AddOns.LoadAddOn, "Blizzard_EncounterJournal")
                    end
                    data.encounters = {}
                    for ei = 1, #encounters do
                        local enc = encounters[ei]
                        local encName, instanceID
                        if EJ_GetEncounterInfo then
                            local name, _, _, _, _, instID = EJ_GetEncounterInfo(enc.encounterID)
                            encName = name
                            instanceID = instID
                        end
                        local instanceName
                        if instanceID and EJ_GetInstanceInfo then
                            instanceName = EJ_GetInstanceInfo(instanceID)
                        end
                        local diffName
                        if enc.bestDifficulty and enc.bestDifficulty > 0 then
                            if DifficultyUtil and DifficultyUtil.GetDifficultyName then
                                diffName = DifficultyUtil.GetDifficultyName(enc.bestDifficulty)
                            elseif GetDifficultyInfo then
                                diffName = GetDifficultyInfo(enc.bestDifficulty)
                            end
                        end
                        -- Guard secret values
                        if issecretvalue and encName and issecretvalue(encName) then encName = nil end
                        if issecretvalue and instanceName and issecretvalue(instanceName) then instanceName = nil end
                        if issecretvalue and diffName and issecretvalue(diffName) then diffName = nil end
                        data.encounters[ei] = {
                            encounterID = enc.encounterID,
                            bestDifficulty = enc.bestDifficulty,
                            uiOrder = enc.uiOrder,
                            instanceID = enc.instanceID or instanceID,
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
        
    -- CRITICAL: Save to DB after data is populated
    WarbandNexus:SavePvECache()
    
    -- NOTE: PVE_UPDATED is NOT fired here. Both callers (UpdatePvEData and
    -- OnVaultDataReceived) fire PVE_UPDATED after this function returns.
    -- Firing here caused a DOUBLE event within milliseconds, and the UI's
    -- 800ms cooldown silently dropped the second (important) one.
end

---Update Great Vault reward availability
---Only sets hasAvailableRewards when rewards are for current period and claimable
---(uses AreRewardsForCurrentRewardPeriod/CanClaimRewards when available; avoids post-season stale true).
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateGreatVaultRewards(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    
    local hasAvailable = false
    if C_WeeklyRewards.HasAvailableRewards and C_WeeklyRewards.HasAvailableRewards() then
        if C_WeeklyRewards.AreRewardsForCurrentRewardPeriod and not C_WeeklyRewards.AreRewardsForCurrentRewardPeriod() then
            hasAvailable = false
        elseif C_WeeklyRewards.CanClaimRewards and not C_WeeklyRewards.CanClaimRewards() then
            hasAvailable = false
        elseif C_WeeklyRewards.GetActivities then
            local activities = C_WeeklyRewards.GetActivities()
            if activities and #activities > 0 then
                hasAvailable = true
            end
        end
    end
    
    if not self.db.global.pveCache.greatVault.rewards then
        self.db.global.pveCache.greatVault.rewards = {}
    end
    
    self.db.global.pveCache.greatVault.rewards[charKey] = {
        hasAvailableRewards = hasAvailable,
        lastUpdate = time(),
    }
end

-- ============================================================================
-- LOCKOUT DATA
-- ============================================================================

---Update raid lockouts for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateRaidLockouts(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not charKey or not self.db.global.pveCache then return end
    
    local numSavedInstances = GetNumSavedInstances()
    if not numSavedInstances or numSavedInstances == 0 then return end
    
    if not self.db.global.pveCache.lockouts.raids then
        self.db.global.pveCache.lockouts.raids = {}
    end
    
    self.db.global.pveCache.lockouts.raids[charKey] = {}
    
    for i = 1, numSavedInstances do
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        
        if issecretvalue and name and issecretvalue(name) then name = nil end
        if issecretvalue and difficulty and issecretvalue(difficulty) then difficulty = nil end
        if issecretvalue and difficultyName and issecretvalue(difficultyName) then difficultyName = nil end
        
        if name and isRaid and locked then
            local encounters = {}
            if numEncounters and numEncounters > 0 then
                for j = 1, numEncounters do
                    local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, j)
                    if issecretvalue and bossName and issecretvalue(bossName) then bossName = nil end
                    if bossName then
                        encounters[#encounters + 1] = {
                            name = bossName,
                            killed = isKilled or false,
                        }
                    end
                end
            end
            self.db.global.pveCache.lockouts.raids[charKey][id] = {
                name = name,
                difficulty = difficulty,
                difficultyName = difficultyName,
                reset = reset,
                extended = extended or false,
                numEncounters = numEncounters,
                encounterProgress = encounterProgress,
                encounters = encounters,
            }
        end
    end
end

---Update world boss kills for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateWorldBossKills(charKey)
    if not charKey or not self.db.global.pveCache then return end
    
    -- World boss kills tracked via quest completion
    -- Midnight 12.0.1 world boss quest IDs
    local worldBossQuests = {
        93913, -- Midnight: World Boss (Quel'Thalas weekly world boss)
    }
    
    if not self.db.global.pveCache.lockouts.worldBosses then
        self.db.global.pveCache.lockouts.worldBosses = {}
    end
    
    self.db.global.pveCache.lockouts.worldBosses[charKey] = {}
    
    for i = 1, #worldBossQuests do
        local questID = worldBossQuests[i]
        if C_QuestLog.IsQuestFlaggedCompleted(questID) then
            self.db.global.pveCache.lockouts.worldBosses[charKey][questID] = true
        end
    end
end

---Collect M+ run history for current character (this week only)
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateMythicPlusRunHistory(charKey)
    if not charKey or not self.db.global.pveCache then return end
    if not C_MythicPlus or not C_MythicPlus.GetRunHistory then return end

    if not self.db.global.pveCache.mythicPlus.runHistory then
        self.db.global.pveCache.mythicPlus.runHistory = {}
    end

    local runs = C_MythicPlus.GetRunHistory(false, false)
    if not runs then
        self.db.global.pveCache.mythicPlus.runHistory[charKey] = {}
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
end

-- ============================================================================
-- DELVES DATA
-- ============================================================================

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

---Update Delves companion data (account-wide) and per-character delve progress.
---Uses C_DelvesUI APIs (Midnight 12.0+) for companion info and season tracking.
function WarbandNexus:UpdateDelvesData(charKey)
    if not self.db.global.pveCache or not self.db.global.pveCache.delves then return end
    
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
                
                -- Resolve companion renown level from reputation API
                if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
                    local factionData = C_MajorFactions.GetMajorFactionData(factionID)
                    if factionData then
                        delves.companion.renownLevel = factionData.renownLevel or 0
                        delves.companion.name = factionData.name
                    end
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
        
        -- Bountiful / Trovehunter weeklies — snapshot for this character when they are logged in (quest API is session-local).
        delves.characters[charKey].bountifulComplete = self.IsBountifulDelveWeeklyDone and self:IsBountifulDelveWeeklyDone() or false
        local crackedID = Constants.PVE_CRACKED_KEYSTONE_WEEKLY_QUEST_ID or 92600
        delves.characters[charKey].crackedKeystoneComplete = SafeIsQuestFlaggedCompleted(crackedID)
        delves.characters[charKey].lastUpdate = time()
    end
end

-- ============================================================================
-- UPDATE ORCHESTRATION
-- ============================================================================

---Update all PvE data for current character (throttled)
function WarbandNexus:UpdatePvEData()
    DebugPrint("|cff9370DB[PvECache]|r [PvE Action] UpdatePvEData triggered")
    -- Align with CollectPvEData / UI: no writes when PvE module disabled
    if ns.Utilities and ns.Utilities.IsModuleEnabled and not ns.Utilities:IsModuleEnabled("pve") then
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
        return
    end
    
    lastUpdateTime = currentTime
    pendingUpdate = false
    
    -- Get current character key (canonical = DB bucket for this character)
    local charKey = ns.Utilities:GetCharacterKey()
    if ns.Utilities.GetCanonicalCharacterKey then
        charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
    end

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
    local hasVaultData = self.db.global.pveCache
        and self.db.global.pveCache.greatVault
        and self.db.global.pveCache.greatVault.activities
        and self.db.global.pveCache.greatVault.activities[charKey]
        and (next(self.db.global.pveCache.greatVault.activities[charKey].raids or {})
            or next(self.db.global.pveCache.greatVault.activities[charKey].mythicPlus or {})
            or next(self.db.global.pveCache.greatVault.activities[charKey].world or {}))
    if not hasVaultData then
        self:UpdateGreatVaultActivities(charKey)
    end
    
    -- Update timestamp (data already in DB)
    self:SavePvECache()
    
    -- Fire event for UI refresh
    self:SendMessage(Constants.EVENTS.PVE_UPDATED)
    
end

---Schedule throttled update (called by pending update timer)
function WarbandNexus:ProcessPendingPvEUpdate()
    if pendingUpdate then
        self:UpdatePvEData()
    end
end

-- ============================================================================
-- PUBLIC API (FOR UI AND DATASERVICE)
-- ============================================================================

---Get PvE data for a specific character or all characters
---@param charKey string|nil Character key (nil = return all)
---@return table PvE data
function WarbandNexus:GetPvEData(charKey)
    -- CRITICAL: Always read directly from DB (no cache)
    local dbCache = self.db and self.db.global and self.db.global.pveCache or {}
    
    if charKey then
        if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
            charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
        end
        local bestRuns = dbCache.mythicPlus and dbCache.mythicPlus.bestRuns and dbCache.mythicPlus.bestRuns[charKey] or {}
        local dungeonScoresData = dbCache.mythicPlus and dbCache.mythicPlus.dungeonScores and dbCache.mythicPlus.dungeonScores[charKey]
        
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
                table.sort(dungeons, function(a, b)
                    return (a.name or "") < (b.name or "")
                end)
            end
        end
        
        -- Hydrate lockouts: convert hash { [id] = compact } to array with display fields
        local rawLockouts = dbCache.lockouts and dbCache.lockouts.raids and dbCache.lockouts.raids[charKey] or {}
        local hydratedLockouts = {}
        for instanceID, lockout in pairs(rawLockouts) do
            local difficultyName
            if lockout.difficulty and GetDifficultyInfo then
                difficultyName = GetDifficultyInfo(lockout.difficulty)
            end
            table.insert(hydratedLockouts, {
                instanceID = instanceID,
                name = lockout.name or ("Instance #" .. instanceID),
                difficulty = lockout.difficulty,
                difficultyName = difficultyName or lockout.difficultyName or "Unknown",
                reset = lockout.reset,
                extended = lockout.extended or false,
                numEncounters = lockout.numEncounters,
                encounterProgress = lockout.encounterProgress,
                encounters = lockout.encounters or {},
                progress = lockout.encounterProgress or 0,
                total = lockout.numEncounters or 0,
                isRaid = true,
            })
        end
        -- Sort by name for consistent display
        table.sort(hydratedLockouts, function(a, b) return (a.name or "") < (b.name or "") end)
        
        -- Return data for specific character
        local vaultActivities = dbCache.greatVault and dbCache.greatVault.activities and dbCache.greatVault.activities[charKey]
        local returnData = {
            keystone = dbCache.mythicPlus and dbCache.mythicPlus.keystones and dbCache.mythicPlus.keystones[charKey],
            bestRuns = bestRuns,
            dungeonScores = dungeonScoresData,
            vaultActivities = vaultActivities,
            vaultRewards = dbCache.greatVault and dbCache.greatVault.rewards and dbCache.greatVault.rewards[charKey],
            greatVault = vaultActivities or {},  -- Alias: PvEDataCollector uses .greatVault
            raidLockouts = hydratedLockouts,
            lockouts = hydratedLockouts,  -- Alias: PvEDataCollector and DataService use .lockouts
            worldBosses = dbCache.lockouts and dbCache.lockouts.worldBosses and dbCache.lockouts.worldBosses[charKey],
            -- Delves data (companion is account-wide, per-char quest status)
            delves = {
                companion = dbCache.delves and dbCache.delves.companion or {},
                season = dbCache.delves and dbCache.delves.season or 0,
                character = dbCache.delves and dbCache.delves.characters and dbCache.delves.characters[charKey] or {},
            },
            -- Add legacy-compatible mythicPlus structure
            mythicPlus = {
                overallScore = overallScore,
                dungeons = dungeons,
                bestRuns = bestRuns,
                dungeonScores = dungeonScoresData,
                runHistory = dbCache.mythicPlus and dbCache.mythicPlus.runHistory and dbCache.mythicPlus.runHistory[charKey] or {},
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

---Import legacy PvE data for a specific character into pveCache.
---Used by DatabaseOptimizer migration and UpdatePvEDataV2 fallback.
---Maps the old DataService progress format → PvECacheService structure.
---@param charKey string Character key (name-realm)
---@param legacyData table Legacy pveProgress entry or CollectPvEData result
function WarbandNexus:ImportLegacyPvEData(charKey, legacyData)
    if not charKey or not legacyData then return end
    
    -- Ensure DB is initialized
    if not self.db or not self.db.global or not self.db.global.pveCache then
        self:InitializePvECache()
    end
    if not self.db.global.pveCache then return end
    
    local pc = self.db.global.pveCache
    
    -- ── M+ Data ──
    if legacyData.mythicPlus then
        local mp = legacyData.mythicPlus
        
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
    end
    
    -- ── Great Vault ──
    if legacyData.greatVault then
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
        
        -- Unclaimed rewards
        if legacyData.hasUnclaimedRewards then
            pc.greatVault.rewards = pc.greatVault.rewards or {}
            pc.greatVault.rewards[charKey] = {
                hasAvailableRewards = true,
                lastUpdate = time(),
            }
        end
    end
    
    -- ── Raid Lockouts ──
    if legacyData.lockouts then
        pc.lockouts.raids = pc.lockouts.raids or {}
        pc.lockouts.raids[charKey] = {}
        
        for i = 1, #legacyData.lockouts do
            local lockout = legacyData.lockouts[i]
            local id = lockout.instanceID or lockout.id
            if id then
                pc.lockouts.raids[charKey][id] = {
                    name = lockout.name,
                    difficulty = lockout.difficulty,
                    reset = lockout.reset,
                    extended = lockout.extended or false,
                    numEncounters = lockout.total or lockout.numEncounters,
                    encounterProgress = lockout.progress or lockout.encounterProgress,
                }
            end
        end
    end
    
    self:SavePvECache()
    DebugPrint(string.format("|cff9370DB[PvECache]|r Imported legacy PvE data for %s", charKey))
end

---Clear PvE cache (force refresh)
function WarbandNexus:ClearPvECache()
    if not self.db or not self.db.global or not self.db.global.pveCache then return end
    
    self.db.global.pveCache.mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {} }
    self.db.global.pveCache.greatVault = { activities = {}, rewards = {} }
    self.db.global.pveCache.lockouts = { raids = {}, worldBosses = {} }
    self.db.global.pveCache.delves = { companion = {}, season = 0 }
    self.db.global.pveCache.lastUpdate = 0
    
    self:SavePvECache()
end

-- ============================================================================
-- EVENT REGISTRATION (Auto-register on module load)
-- ============================================================================

---Register PvE event listeners
function WarbandNexus:RegisterPvECacheEvents()
    if not self.RegisterEvent then
        return
    end
    
    -- Prime C_MythicPlus API cache on login (deferred to ensure API readiness)
    C_Timer.After(3, function()
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            C_MythicPlus.RequestCurrentAffixes()
        end
    end)
    
    -- Vault warm-up: VaultScanner fires OnUIInteract at T+1s, server responds ~T+2-4s.
    -- Re-collect vault data at T+5s to catch any iLvl that arrived after initial scan.
    C_Timer.After(5, function()
        if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
        local charKey = ns.Utilities:GetCharacterKey()
        if ns.Utilities.GetCanonicalCharacterKey then
            charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
        end
        if charKey then
            WarbandNexus:ProcessGreatVaultActivities(charKey)
            WarbandNexus:SavePvECache()
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
    
    -- Mythic+ events
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] CHALLENGE_MODE_COMPLETED triggered")
        
        -- Request fresh data from Blizzard APIs
        if C_MythicPlus then
            C_MythicPlus.RequestMapInfo()
            C_MythicPlus.RequestRewards()
        end
        if C_WeeklyRewards then
            C_WeeklyRewards.OnUIInteract()
        end
        
        ThrottledPvEUpdate()
    end)
    
    self:RegisterEvent("MYTHIC_PLUS_NEW_WEEKLY_RECORD", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] MYTHIC_PLUS_NEW_WEEKLY_RECORD triggered")
        ThrottledPvEUpdate()
    end)
    
    -- CHALLENGE_MODE_MAPS_UPDATE: fires when M+ map/keystone data is refreshed by the server
    -- This is the proper event for keystone detection (instead of bag scanning)
    self:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] CHALLENGE_MODE_MAPS_UPDATE triggered")
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
        ThrottledPvEUpdate()
    end)
    
    self:RegisterEvent("MYTHIC_PLUS_CURRENT_AFFIX_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] MYTHIC_PLUS_CURRENT_AFFIX_UPDATE triggered (weekly reset)")
        
        -- Affix refresh: clear affix IDs. Prune keystones that pre-date the current weekly reset only —
        -- never wipe every character (that event fires outside rollover too; mass-clear hid all alts' keys).
        if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache then
            if WarbandNexus.db.global.pveCache.mythicPlus then
                WarbandNexus.db.global.pveCache.mythicPlus.currentAffixes = {}
                local ks = WarbandNexus.db.global.pveCache.mythicPlus.keystones
                if ks and WarbandNexus.HasWeeklyResetOccurred then
                    for k, v in pairs(ks) do
                        if type(v) == "table" and v.lastUpdate and WarbandNexus:HasWeeklyResetOccurred(v.lastUpdate) then
                            ks[k] = nil
                        end
                    end
                end
            end
            
            WarbandNexus:SavePvECache()
        end
        
        -- Then update with new data
        ThrottledPvEUpdate()
        
        -- Also refresh keystone detection (new weekly key may be in bags)
        if WarbandNexus.OnKeystoneChanged then
            WarbandNexus:OnKeystoneChanged()
        end
    end)
    
    -- Weekly Vault events
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] WEEKLY_REWARDS_UPDATE triggered")
        WarbandNexus:OnVaultDataReceived()
    end)
    
    self:RegisterEvent("WEEKLY_REWARDS_ITEM_CHANGED", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] WEEKLY_REWARDS_ITEM_CHANGED triggered")
        ThrottledPvEUpdate()
    end)
    
    -- Raid lockout events
    self:RegisterEvent("UPDATE_INSTANCE_INFO", function()
        DebugPrint("|cff9370DB[PvECache]|r [PvE Event] UPDATE_INSTANCE_INFO triggered")
        ThrottledPvEUpdate()
    end)
    
    -- Delves events (Midnight 12.0+)
    pcall(function()
        self:RegisterEvent("DELVES_ACCOUNT_DATA_ELEMENT_CHANGED", function()
            DebugPrint("|cff9370DB[PvECache]|r [PvE Event] DELVES_ACCOUNT_DATA_ELEMENT_CHANGED triggered")
            ThrottledPvEUpdate()
        end)
    end)
    
end

-- ============================================================================
-- EVENT HANDLERS (Called by registered events above)
-- ============================================================================

-- REMOVED: OnMythicPlusAffixUpdate — never registered; PvECacheService handles affix updates inline.

---Handle WEEKLY_REWARDS_UPDATE event (vault data received from server)
---NOTE: Named OnVaultDataReceived to avoid collision with PlansManager:OnPvEUpdateCheckPlans
---ARCHITECTURE: Vault activities are processed by VaultScanner → SyncVaultDataFromScanner.
---This handler only updates NON-vault data (keystone, best runs, rewards) to avoid
---overwriting VaultScanner's richer data (nextLevelIlvl, maxIlvl, nextKeyLevel).
function WarbandNexus:OnVaultDataReceived()
    -- Get current character key
    local charKey = ns.Utilities:GetCharacterKey()
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
    end
    
    -- DO NOT call ProcessGreatVaultActivities here!
    -- VaultScanner handles vault activities via SyncVaultDataFromScanner (richer data).
    -- Calling it here would overwrite VaultScanner's enhanced data with basic data.
    
    -- Update non-vault PvE data
    self:UpdateCharacterKeystone(charKey)
    self:UpdateMythicPlusBestRuns(charKey)
    self:UpdateGreatVaultRewards(charKey)
    
    -- Update timestamp (data already in DB)
    self:SavePvECache()
    
    -- Fire event for UI refresh
    self:SendMessage(Constants.EVENTS.PVE_UPDATED)
end

---Sync vault data from VaultScanner to PvECacheService
---@param vaultSlots table Array of vault slot data from VaultScanner
function WarbandNexus:SyncVaultDataFromScanner(vaultSlots)
    if not vaultSlots or type(vaultSlots) ~= "table" then
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
    
    -- Must match PvEUI / GetPvEData: canonical key so vault rows align after character/realm normalization.
    local charKey = ns.Utilities:GetCharacterKey()
    if ns.Utilities.GetCanonicalCharacterKey then
        charKey = ns.Utilities:GetCanonicalCharacterKey(charKey) or charKey
    end
    if not charKey then return end
    
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
            weeklyResetTime = (GetServerTime() + (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset() or 0)),
        }
    end
    
    -- PRESERVE existing iLvl data before clearing.
    -- GetExampleRewardItemHyperlinks() may return nil momentarily after a slot
    -- transitions to complete (server computing rewards). Build a lookup by
    -- activityID so known-good values survive a re-scan that returns 0.
    local activities = self.db.global.pveCache.greatVault.activities[charKey]
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
    
    -- Update timestamp
    activities.lastUpdate = time()
    
    -- Save to DB
    self:SavePvECache()
    
    -- Fire event to refresh UI
    self:SendMessage(Constants.EVENTS.PVE_UPDATED)
end

---Handle UPDATE_INSTANCE_INFO event
function WarbandNexus:OnInstanceInfoUpdate()
    self:UpdatePvEData()
end

---Handle CHALLENGE_MODE_COMPLETED event
function WarbandNexus:OnChallengeModeCompleted()
    self:UpdatePvEData()
end

-- ============================================================================
-- PLAYER_LOGOUT: Flush pending PvE data before session ends
-- ============================================================================
-- Great Vault data arrives asynchronously via WEEKLY_REWARDS_UPDATE.
-- If the player logs out before the event fires, vault data for this session
-- would be lost. This hook does a final synchronous save.

local logoutFrame = CreateFrame("Frame")
logoutFrame:RegisterEvent("PLAYER_LOGOUT")
logoutFrame:SetScript("OnEvent", function()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(WarbandNexus) then return end
    
    -- Process any pending throttled update
    if pendingUpdate then
        WarbandNexus:UpdatePvEData()
    end
    
    -- Final save (ensures all direct DB writes are persisted)
    WarbandNexus:SavePvECache()
end)

-- ============================================================================
-- LOAD MESSAGE
-- ============================================================================

-- Module loaded (silent)
-- Module loaded - verbose logging hidden (debug mode only)
