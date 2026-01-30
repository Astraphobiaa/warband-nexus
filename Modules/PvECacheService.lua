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
        print("|cff9370DB[WN PvECache]|r Initialized empty PvE cache")
        return
    end
    
    local dbCache = self.db.global.pveCache
    
    -- Version check
    if dbCache.version ~= CACHE_VERSION then
        print(string.format("|cffffcc00[WN PvECache]|r Cache version mismatch (DB: %s, Code: %s), clearing cache", 
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
    
    print("|cff00ff00[WN PvECache]|r Loaded PvE cache from DB")
end

---Save PvE cache to DB
function WarbandNexus:SavePvECache()
    if not self.db or not self.db.global then
        print("|cffff0000[WN PvECache ERROR]|r Cannot save cache: DB not initialized")
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
    local maps = C_ChallengeMode.GetMapTable()
    if not maps then return end
    
    if not pveCache.mythicPlus.bestRuns then
        pveCache.mythicPlus.bestRuns = {}
    end
    
    if not pveCache.mythicPlus.bestRuns[charKey] then
        pveCache.mythicPlus.bestRuns[charKey] = {}
    end
    
    for _, mapID in ipairs(maps) do
        local _, level, _, onTime = C_MythicPlus.GetWeeklyBestForMap(mapID)
        if level and level > 0 then
            pveCache.mythicPlus.bestRuns[charKey][mapID] = {
                level = level,
                onTime = onTime or false,
            }
        end
    end
end

-- ============================================================================
-- GREAT VAULT DATA
-- ============================================================================

---Update Great Vault activities for current character
---@param charKey string Character key (name-realm)
function WarbandNexus:UpdateGreatVaultActivities(charKey)
    if not C_WeeklyRewards or not charKey then return end
    
    local activities = C_WeeklyRewards.GetActivities()
    if not activities then return end
    
    if not pveCache.greatVault.activities then
        pveCache.greatVault.activities = {}
    end
    
    pveCache.greatVault.activities[charKey] = {
        raids = {},
        mythicPlus = {},
        pvp = {},
        lastUpdate = time(),
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
            }
            
            -- Categorize by activity type
            if activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
                table.insert(pveCache.greatVault.activities[charKey].raids, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.MythicPlus then
                table.insert(pveCache.greatVault.activities[charKey].mythicPlus, data)
            elseif activity.type == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                table.insert(pveCache.greatVault.activities[charKey].pvp, data)
            end
        end
    end
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
    self:UpdateGreatVaultActivities(charKey)
    self:UpdateGreatVaultRewards(charKey)
    self:UpdateRaidLockouts(charKey)
    self:UpdateWorldBossKills(charKey)
    
    -- Update timestamp
    pveCache.lastUpdate = time()
    
    -- Save to DB
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
        -- Return data for specific character
        return {
            keystone = pveCache.mythicPlus.keystones and pveCache.mythicPlus.keystones[charKey],
            bestRuns = pveCache.mythicPlus.bestRuns and pveCache.mythicPlus.bestRuns[charKey],
            vaultActivities = pveCache.greatVault.activities and pveCache.greatVault.activities[charKey],
            vaultRewards = pveCache.greatVault.rewards and pveCache.greatVault.rewards[charKey],
            raidLockouts = pveCache.lockouts.raids and pveCache.lockouts.raids[charKey],
            worldBosses = pveCache.lockouts.worldBosses and pveCache.lockouts.worldBosses[charKey],
        }
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
    print("|cff00ff00[WN PvECache]|r Cache cleared")
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
    self:UpdatePvEData()
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

print("|cff00ff00[WN PvECache]|r Loaded successfully")
print("|cff9370DB[WN PvECache]|r Features: M+ tracking, Great Vault, Raid lockouts, World bosses")
print("|cff9370DB[WN PvECache]|r Cache version: " .. CACHE_VERSION)
