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
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local Constants = ns.Constants
local CACHE_VERSION = Constants.PVE_CACHE_VERSION
local UPDATE_THROTTLE = Constants.THROTTLE.SHARED_RARE

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
            version = CACHE_VERSION,
            lastUpdate = 0,
        }
        return
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
        for _, affixData in ipairs(affixes) do
            -- Extract affixID (supports both direct ID and struct format)
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
    
    if keystoneInfo and keystoneLevel then
        if not self.db.global.pveCache.mythicPlus.keystones then
            self.db.global.pveCache.mythicPlus.keystones = {}
        end
        
        self.db.global.pveCache.mythicPlus.keystones[charKey] = {
            mapID = keystoneInfo,
            level = keystoneLevel,
            lastUpdate = time(),
        }
    else
        -- Clear keystone if none owned
        if self.db.global.pveCache.mythicPlus.keystones then
            self.db.global.pveCache.mythicPlus.keystones[charKey] = nil
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
    for _, mapID in ipairs(maps) do
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
        for _, mapID in ipairs(maps) do
            -- Get score for this specific map
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
    
    -- CRITICAL: Request data from server (required for data to be available)
    -- This will trigger WEEKLY_REWARDS_UPDATE event when data is ready
    C_WeeklyRewards.OnUIInteract()
    
    -- Data will be processed when WEEKLY_REWARDS_UPDATE fires
end

---Process Great Vault activities after server responds
---@param charKey string Character key (name-realm)
function WarbandNexus:ProcessGreatVaultActivities(charKey)
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    
    local activities = C_WeeklyRewards.GetActivities()
    if not activities then 
        return 
    end
    
    if not self.db.global.pveCache.greatVault.activities then
        self.db.global.pveCache.greatVault.activities = {}
    end
    
    -- Calculate weekly reset time for metadata
    local weeklyResetTime = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and (GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()) or 0
    
    -- CRITICAL: ALWAYS create fresh arrays (prevent duplication and stale data)
    self.db.global.pveCache.greatVault.activities[charKey] = {
        raids = {},
        mythicPlus = {},
        pvp = {},
        world = {},
        lastUpdate = time(),
        weeklyResetTime = weeklyResetTime,
    }
        
        for _, activity in ipairs(activities) do
            if activity then
                local data = {
                    type = activity.type,
                    index = activity.index,
                    progress = activity.progress,
                    threshold = activity.threshold,
                    level = activity.level,
                    id = activity.id,
                    rewards = activity.rewards or nil,
                }
                
                -- Extract reward item level using GetExampleRewardItemHyperlinks (RELIABLE!)
                if activity.id and C_WeeklyRewards.GetExampleRewardItemHyperlinks then
                    local currentLink, upgradeLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
                    
                if currentLink then
                    -- Parse item level from hyperlink
                    local effectiveILvl, _, baseILvl = C_Item.GetDetailedItemLevelInfo(currentLink)
                    -- CRITICAL: Default to 0 if nil (never save nil)
                    data.rewardItemLevel = effectiveILvl or baseILvl or 0
                end
            end
                
                -- Categorize by activity type
                if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
                    table.insert(self.db.global.pveCache.greatVault.activities[charKey].raids, data)
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
                    -- Activities = Mythic+ Dungeons
                    table.insert(self.db.global.pveCache.greatVault.activities[charKey].mythicPlus, data)
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                    table.insert(self.db.global.pveCache.greatVault.activities[charKey].pvp, data)
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
                    -- World activities (Delves, World Quests, etc.)
                    if not self.db.global.pveCache.greatVault.activities[charKey].world then
                        self.db.global.pveCache.greatVault.activities[charKey].world = {}
                    end
                    table.insert(self.db.global.pveCache.greatVault.activities[charKey].world, data)
                end
            end
        end
        
    -- CRITICAL: Save to DB after data is populated
    WarbandNexus:SavePvECache()
    
    -- Fire event to refresh UI
    WarbandNexus:SendMessage(Constants.EVENTS.PVE_UPDATED)
end

---Update Great Vault reward availability
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateGreatVaultRewards(charKey)
    -- GUARD: Only update if character is tracked
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        return
    end
    
    if not C_WeeklyRewards or not charKey or not self.db.global.pveCache then return end
    
    local hasAvailable = C_WeeklyRewards.HasAvailableRewards()
    
    if not self.db.global.pveCache.greatVault.rewards then
        self.db.global.pveCache.greatVault.rewards = {}
    end
    
    self.db.global.pveCache.greatVault.rewards[charKey] = {
        hasAvailableRewards = hasAvailable or false,
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
        
        if name and isRaid and locked then
            -- Store lean: progress data + name (name can't be resolved from lockout ID alone).
            -- difficultyName resolved on-demand via GetDifficultyInfo(difficulty).
            -- Lockout count is tiny (0-5 per char), so storing name has negligible SV impact.
            self.db.global.pveCache.lockouts.raids[charKey][id] = {
                name = name,
                difficulty = difficulty,
                reset = reset,
                extended = extended or false,
                numEncounters = numEncounters,
                encounterProgress = encounterProgress,
            }
        end
    end
end

---Update world boss kills for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateWorldBossKills(charKey)
    if not charKey or not self.db.global.pveCache then return end
    
    -- World boss kills tracked via quest completion
    -- Common world boss quest IDs (TWW)
    local worldBossQuests = {
        81653, -- Aggregation of Horrors
        81652, -- Orta, the Broken Mountain
        -- Add more as needed
    }
    
    if not self.db.global.pveCache.lockouts.worldBosses then
        self.db.global.pveCache.lockouts.worldBosses = {}
    end
    
    self.db.global.pveCache.lockouts.worldBosses[charKey] = {}
    
    for _, questID in ipairs(worldBossQuests) do
        if C_QuestLog.IsQuestFlaggedCompleted(questID) then
            self.db.global.pveCache.lockouts.worldBosses[charKey][questID] = true
        end
    end
end

-- ============================================================================
-- UPDATE ORCHESTRATION
-- ============================================================================

---Update all PvE data for current character (throttled)
function WarbandNexus:UpdatePvEData()
    DebugPrint("|cff9370DB[PvECache]|r [PvE Action] UpdatePvEData triggered")
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
    
    -- Get current character key
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    
    -- Update all PvE data (API > DB)
    self:UpdateMythicPlusAffixes()
    self:UpdateCharacterKeystone(charKey)
    self:UpdateMythicPlusBestRuns(charKey)
    self:UpdateDungeonScores(charKey)
    self:UpdateGreatVaultActivities(charKey)
    self:UpdateGreatVaultRewards(charKey)
    self:UpdateRaidLockouts(charKey)
    self:UpdateWorldBossKills(charKey)
    
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
                for _, mapID in ipairs(maps) do
                    -- Get dungeon metadata
                    local mapName, _, _, texture = C_ChallengeMode.GetMapUIInfo(mapID)
                    
                    -- Get score and bestLevel from dungeonScores cache (primary source)
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
                difficultyName = difficultyName or "Unknown",
                reset = lockout.reset,
                extended = lockout.extended or false,
                numEncounters = lockout.numEncounters,
                encounterProgress = lockout.encounterProgress,
                -- UI-compatible aliases
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
            -- Add legacy-compatible mythicPlus structure
            mythicPlus = {
                overallScore = overallScore,  -- Use cached score from dungeonScores
                dungeons = dungeons,  -- Includes score from dungeonScores
                bestRuns = bestRuns,
                dungeonScores = dungeonScoresData,
            },
        }
        
        return returnData
    else
        -- Return all data (for global queries like currentAffixes)
        -- Hydrate affixes: SV stores only IDs, resolve name/description/icon on-demand
        local rawAffixes = dbCache.mythicPlus and dbCache.mythicPlus.currentAffixes or {}
        local hydratedAffixes = {}
        for _, affixEntry in ipairs(rawAffixes) do
            -- Handle both lean (number) and legacy (table) format
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
            currentAffixes = hydratedAffixes,
        }
    end
end

---Clear PvE cache (force refresh)
function WarbandNexus:ClearPvECache()
    if not self.db.global.pveCache then return end
    
    self.db.global.pveCache.mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {}, dungeonScores = {} }
    self.db.global.pveCache.greatVault = { activities = {}, rewards = {} }
    self.db.global.pveCache.lockouts = { raids = {}, worldBosses = {} }
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
        
        -- WEEKLY RESET: Clear keystone and affix data (currency stays in CurrencyCacheService)
        if WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.pveCache then
            -- Clear all character keystones
            if WarbandNexus.db.global.pveCache.mythicPlus then
                WarbandNexus.db.global.pveCache.mythicPlus.keystones = {}
                WarbandNexus.db.global.pveCache.mythicPlus.currentAffixes = {}
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
        local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
        WarbandNexus:OnWeeklyRewardsUpdate()
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
    
end

-- ============================================================================
-- EVENT HANDLERS (Called by registered events above)
-- ============================================================================

---Handle MYTHIC_PLUS_CURRENT_AFFIX_UPDATE event
function WarbandNexus:OnMythicPlusAffixUpdate()
    self:UpdatePvEData()
end

---Handle WEEKLY_REWARDS_UPDATE event
function WarbandNexus:OnWeeklyRewardsUpdate()
    -- Get current character key
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    
    -- Process the vault data that server just sent
    self:ProcessGreatVaultActivities(charKey)
    
    -- Also update other PvE data
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
    if not vaultSlots or type(vaultSlots) ~= "table" or not self.db.global.pveCache then
        return
    end
    
    -- Get current character key (same pattern as other functions)
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
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
    
    -- Clear existing data
    local activities = self.db.global.pveCache.greatVault.activities[charKey]
    activities.raids = {}
    activities.mythicPlus = {}
    activities.pvp = {}
    activities.world = {}
    
    -- Convert VaultScanner format to PvECacheService format
    for _, slot in ipairs(vaultSlots) do
        local activity = {
            type = nil,  -- Will be set based on typeName
            index = slot.index,
            progress = slot.progress,
            threshold = slot.threshold,
            level = slot.level,
            id = slot.activityID,
            rewardItemLevel = slot.currentILvl or 0,
            nextLevelIlvl = slot.nextILvl or 0,  -- For tooltip upgrade info
            maxIlvl = slot.maxILvl or 0,  -- For tooltip max tier info
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
-- LOAD MESSAGE
-- ============================================================================

-- Module loaded (silent)
-- Module loaded - verbose logging hidden (debug mode only)
