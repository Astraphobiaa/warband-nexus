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
-- CACHE STRUCTURE (PERSISTENT IN DB)
-- ============================================================================

local pveCache = {
    mythicPlus = {
        currentAffixes = {},      -- Current week's affixes
        keystones = {},           -- Character keystones {[charKey] = {level, mapID, ...}}
        bestRuns = {},            -- Best M+ runs this season {[charKey] = {[mapID] = level}}
        dungeonScores = {},       -- Dungeon scores {[charKey] = {overallScore, dungeons = {[mapID] = {mapScore, ...}}}}
    },
    greatVault = {
        activities = {},          -- Vault activities {[charKey] = {raids = {...}, mythicPlus = {...}, pvp = {...}}}
        rewards = {},             -- Available rewards {[charKey] = {numSelections, hasAvailableRewards}}
    },
    lockouts = {
        raids = {},               -- Raid lockouts {[charKey] = {[instanceID] = {locked, extended, ...}}}
        worldBosses = {},         -- World boss kills {[charKey] = {[questID] = true}}
    },
    version = CACHE_VERSION,
    lastUpdate = 0,
}

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
            mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {} },
            greatVault = { activities = {}, rewards = {} },
            lockouts = { raids = {}, worldBosses = {} },
            version = CACHE_VERSION,
            lastUpdate = 0,
        }
        DebugPrint("|cff9370DB[WN PvECache]|r Initialized empty PvE cache")
        return
    end
    
    local dbCache = self.db.global.pveCache
    
    -- Version check
    if dbCache.version ~= CACHE_VERSION then
        DebugPrint(string.format("|cffffcc00[WN PvECache]|r Cache version mismatch (DB: %s, Code: %s), clearing cache", 
            tostring(dbCache.version), CACHE_VERSION))
        self.db.global.pveCache = {
            mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {} },
            greatVault = { activities = {}, rewards = {} },
            lockouts = { raids = {}, worldBosses = {} },
            version = CACHE_VERSION,
            lastUpdate = 0,
        }
        return
    end
    
    -- Load from DB
    pveCache.mythicPlus = dbCache.mythicPlus or { currentAffixes = {}, keystones = {}, bestRuns = {} }
    pveCache.greatVault = dbCache.greatVault or { activities = {}, rewards = {} }
    pveCache.lockouts = dbCache.lockouts or { raids = {}, worldBosses = {} }
    pveCache.lastUpdate = dbCache.lastUpdate or 0
    
    -- CRITICAL: Validate and clear corrupted vault data
    -- Each character should have max 3 activities per type (raids, mythicPlus, pvp, world)
    if pveCache.greatVault.activities then
        for charKey, charData in pairs(pveCache.greatVault.activities) do
            if charData.raids and #charData.raids > 9 then
                DebugPrint(string.format("|cffffcc00[WN PvECache]|r Clearing corrupted vault data for %s (had %d raid activities, max is 9)", charKey, #charData.raids))
                pveCache.greatVault.activities[charKey] = nil
            elseif charData.mythicPlus and #charData.mythicPlus > 9 then
                DebugPrint(string.format("|cffffcc00[WN PvECache]|r Clearing corrupted vault data for %s (had %d M+ activities, max is 9)", charKey, #charData.mythicPlus))
                pveCache.greatVault.activities[charKey] = nil
            elseif charData.world and #charData.world > 9 then
                DebugPrint(string.format("|cffffcc00[WN PvECache]|r Clearing corrupted vault data for %s (had %d world activities, max is 9)", charKey, #charData.world))
                pveCache.greatVault.activities[charKey] = nil
            end
        end
    end
    
    -- Cache loaded (silent)
end

---Save PvE cache to DB
function WarbandNexus:SavePvECache()
    if not self.db or not self.db.global then
        DebugPrint("|cffff0000[WN PvECache ERROR]|r Cannot save cache: DB not initialized")
        return
    end
    
    self.db.global.pveCache = {
        mythicPlus = pveCache.mythicPlus,
        greatVault = pveCache.greatVault,
        lockouts = pveCache.lockouts,
        version = CACHE_VERSION,
        lastUpdate = pveCache.lastUpdate,
    }
end

-- ============================================================================
-- MYTHIC+ DATA
-- ============================================================================

---Update current week's Mythic+ affixes
function WarbandNexus:UpdateMythicPlusAffixes()
    if not C_MythicPlus then return end
    
    local affixes = C_MythicPlus.GetCurrentAffixes()
    if affixes then
        pveCache.mythicPlus.currentAffixes = {}
        for i, affixInfo in ipairs(affixes) do
            if affixInfo then
                table.insert(pveCache.mythicPlus.currentAffixes, {
                    id = affixInfo.id,
                    name = affixInfo.name,
                    description = affixInfo.description,
                    icon = affixInfo.filedataid,
                })
            end
        end
    end
end

---Update character's keystone data
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateCharacterKeystone(charKey)
    if not C_MythicPlus or not charKey then return end
    
    local keystoneInfo = C_MythicPlus.GetOwnedKeystoneChallengeMapID()
    local keystoneLevel = C_MythicPlus.GetOwnedKeystoneLevel()
    
    if keystoneInfo and keystoneLevel then
        if not pveCache.mythicPlus.keystones then
            pveCache.mythicPlus.keystones = {}
        end
        
        pveCache.mythicPlus.keystones[charKey] = {
            mapID = keystoneInfo,
            level = keystoneLevel,
            lastUpdate = time(),
        }
    else
        -- Clear keystone if none owned
        if pveCache.mythicPlus.keystones then
            pveCache.mythicPlus.keystones[charKey] = nil
        end
    end
end

---Update character's best M+ runs
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateMythicPlusBestRuns(charKey)
    if not C_MythicPlus or not charKey then return end
    
    -- Get best run level for each dungeon
    local maps = C_ChallengeMode and C_ChallengeMode.GetMapTable()
    if not maps then return end
    
    if not pveCache.mythicPlus.bestRuns then
        pveCache.mythicPlus.bestRuns = {}
    end
    
    if not pveCache.mythicPlus.bestRuns[charKey] then
        pveCache.mythicPlus.bestRuns[charKey] = {}
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
    
    pveCache.mythicPlus.bestRuns[charKey].overallScore = overallScore
    pveCache.mythicPlus.bestRuns[charKey].scoreSource = scoreSource
    
    -- Store best runs for each dungeon
    for _, mapID in ipairs(maps) do
        local _, level, _, onTime = C_MythicPlus.GetWeeklyBestForMap and C_MythicPlus.GetWeeklyBestForMap(mapID)
        if level and level > 0 then
            pveCache.mythicPlus.bestRuns[charKey][mapID] = {
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
    if not C_ChallengeMode or not charKey then return end
    
    -- Initialize cache
    if not pveCache.mythicPlus.dungeonScores then
        pveCache.mythicPlus.dungeonScores = {}
    end
    
    if not pveCache.mythicPlus.dungeonScores[charKey] then
        pveCache.mythicPlus.dungeonScores[charKey] = {
            overallScore = 0,
            dungeons = {},
            lastUpdate = 0,
        }
    end
    
    local scoreData = pveCache.mythicPlus.dungeonScores[charKey]
    
    -- Get overall dungeon score
    if C_ChallengeMode.GetOverallDungeonScore then
        scoreData.overallScore = C_ChallengeMode.GetOverallDungeonScore() or 0
    end
    
    -- Get per-dungeon scores
    local maps = C_ChallengeMode.GetMapTable()
    if maps and C_ChallengeMode.GetMapUIInfo then
        for _, mapID in ipairs(maps) do
            local name, id, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(mapID)
            
            if name and id then
                -- Get score for this specific map
                local intimeInfo, overtimeInfo = C_MythicPlus.GetSeasonBestForMap(mapID)
                
                -- Calculate HIGHEST score from best runs (NOT sum, just take the best)
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
                
                -- Store dungeon info (including bestLevel)
                scoreData.dungeons[mapID] = {
                    name = name,
                    mapID = id,
                    score = dungeonScore,
                    bestLevel = bestLevel,  -- ADD THIS: Store best level
                    texture = texture,
                    timeLimit = timeLimit,
                }
            end
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
    if not C_WeeklyRewards or not charKey then return end
    
    -- CRITICAL: Request data from server (required for data to be available)
    -- This will trigger WEEKLY_REWARDS_UPDATE event when data is ready
    C_WeeklyRewards.OnUIInteract()
    
    -- Data will be processed when WEEKLY_REWARDS_UPDATE fires
end

---Process Great Vault activities after server responds
---@param charKey string Character key (name-realm)
function WarbandNexus:ProcessGreatVaultActivities(charKey)
    if not C_WeeklyRewards or not charKey then return end
    
    local activities = C_WeeklyRewards.GetActivities()
    if not activities then 
        return 
    end
    
    if not pveCache.greatVault.activities then
        pveCache.greatVault.activities = {}
    end
    
    -- Calculate weekly reset time for metadata
    local weeklyResetTime = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and (GetServerTime() + C_DateAndTime.GetSecondsUntilWeeklyReset()) or 0
    
    -- CRITICAL: ALWAYS create fresh arrays (prevent duplication and stale data)
    pveCache.greatVault.activities[charKey] = {
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
                    table.insert(pveCache.greatVault.activities[charKey].raids, data)
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
                    -- Activities = Mythic+ Dungeons
                    table.insert(pveCache.greatVault.activities[charKey].mythicPlus, data)
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                    table.insert(pveCache.greatVault.activities[charKey].pvp, data)
                elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
                    -- World activities (Delves, World Quests, etc.)
                    if not pveCache.greatVault.activities[charKey].world then
                        pveCache.greatVault.activities[charKey].world = {}
                    end
                    table.insert(pveCache.greatVault.activities[charKey].world, data)
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
    if not C_WeeklyRewards or not charKey then return end
    
    local hasAvailable = C_WeeklyRewards.HasAvailableRewards()
    
    if not pveCache.greatVault.rewards then
        pveCache.greatVault.rewards = {}
    end
    
    pveCache.greatVault.rewards[charKey] = {
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
    if not charKey then return end
    
    local numSavedInstances = GetNumSavedInstances()
    if not numSavedInstances or numSavedInstances == 0 then return end
    
    if not pveCache.lockouts.raids then
        pveCache.lockouts.raids = {}
    end
    
    pveCache.lockouts.raids[charKey] = {}
    
    for i = 1, numSavedInstances do
        local name, id, reset, difficulty, locked, extended, instanceIDMostSig, isRaid, maxPlayers, difficultyName, numEncounters, encounterProgress = GetSavedInstanceInfo(i)
        
        if name and isRaid and locked then
            pveCache.lockouts.raids[charKey][id] = {
                name = name,
                difficulty = difficulty,
                difficultyName = difficultyName,
                reset = reset,
                extended = extended or false,
                maxPlayers = maxPlayers,
                numEncounters = numEncounters,
                encounterProgress = encounterProgress,
                lastUpdate = time(),
            }
        end
    end
end

---Update world boss kills for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateWorldBossKills(charKey)
    if not charKey then return end
    
    -- World boss kills tracked via quest completion
    -- Common world boss quest IDs (TWW)
    local worldBossQuests = {
        81653, -- Aggregation of Horrors
        81652, -- Orta, the Broken Mountain
        -- Add more as needed
    }
    
    if not pveCache.lockouts.worldBosses then
        pveCache.lockouts.worldBosses = {}
    end
    
    pveCache.lockouts.worldBosses[charKey] = {}
    
    for _, questID in ipairs(worldBossQuests) do
        if C_QuestLog.IsQuestFlaggedCompleted(questID) then
            pveCache.lockouts.worldBosses[charKey][questID] = true
        end
    end
end

-- ============================================================================
-- UPDATE ORCHESTRATION
-- ============================================================================

---Update all PvE data for current character (throttled)
function WarbandNexus:UpdatePvEData()
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
    
    -- Update all PvE data
    self:UpdateMythicPlusAffixes()
    self:UpdateCharacterKeystone(charKey)
    self:UpdateMythicPlusBestRuns(charKey)
    self:UpdateDungeonScores(charKey)  -- NEW: Update dungeon scores
    self:UpdateGreatVaultActivities(charKey)  -- This will trigger OnUIInteract, WEEKLY_REWARDS_UPDATE will process
    self:UpdateGreatVaultRewards(charKey)
    self:UpdateRaidLockouts(charKey)
    self:UpdateWorldBossKills(charKey)
    
    -- Update timestamp
    pveCache.lastUpdate = time()
    
    -- Save to DB (vault data will be saved when WEEKLY_REWARDS_UPDATE fires)
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
    if charKey then
        local bestRuns = pveCache.mythicPlus.bestRuns and pveCache.mythicPlus.bestRuns[charKey] or {}
        local dungeonScoresData = pveCache.mythicPlus.dungeonScores and pveCache.mythicPlus.dungeonScores[charKey]
        
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
        
        -- Return data for specific character
        local returnData = {
            keystone = pveCache.mythicPlus.keystones and pveCache.mythicPlus.keystones[charKey],
            bestRuns = bestRuns,
            dungeonScores = dungeonScoresData,
            vaultActivities = pveCache.greatVault.activities and pveCache.greatVault.activities[charKey],
            vaultRewards = pveCache.greatVault.rewards and pveCache.greatVault.rewards[charKey],
            raidLockouts = pveCache.lockouts.raids and pveCache.lockouts.raids[charKey],
            worldBosses = pveCache.lockouts.worldBosses and pveCache.lockouts.worldBosses[charKey],
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
        -- Return all data
        return {
            mythicPlus = pveCache.mythicPlus,
            greatVault = pveCache.greatVault,
            lockouts = pveCache.lockouts,
            currentAffixes = pveCache.mythicPlus.currentAffixes,
        }
    end
end

---Clear PvE cache (force refresh)
function WarbandNexus:ClearPvECache()
    pveCache.mythicPlus = { currentAffixes = {}, keystones = {}, bestRuns = {} }
    pveCache.greatVault = { activities = {}, rewards = {} }
    pveCache.lockouts = { raids = {}, worldBosses = {} }
    pveCache.lastUpdate = 0
    
    self:SavePvECache()
    DebugPrint("|cff00ff00[WN PvECache]|r Cache cleared")
end

-- ============================================================================
-- EVENT HANDLERS (Will be registered by EventManager)
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
    
    -- Update timestamp
    pveCache.lastUpdate = time()
    
    -- Save to DB
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
    
    -- Get current character key (same pattern as other functions)
    local charKey = ns.Utilities and ns.Utilities:GetCharacterKey() or (UnitName("player") .. "-" .. GetRealmName())
    if not charKey then return end
    
    if not pveCache.greatVault.activities then
        pveCache.greatVault.activities = {}
    end
    
    if not pveCache.greatVault.activities[charKey] then
        pveCache.greatVault.activities[charKey] = {
            raids = {},
            mythicPlus = {},
            pvp = {},
            world = {},
            lastUpdate = time(),
            weeklyResetTime = (GetServerTime() + (C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset() or 0)),
        }
    end
    
    -- Clear existing data
    local activities = pveCache.greatVault.activities[charKey]
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
