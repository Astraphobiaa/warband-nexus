--[[
    Warband Nexus - Reputation Processor (Phase 2)
    
    Responsibilities:
    - Transform raw API data into normalized, UI-ready format
    - Calculate 0-based progress (current/max)
    - Resolve standing names and colors
    - Type-specific processing (Classic, Renown, Friendship, Paragon)
    
    Architecture: Scanner → Processor → Cache → UI
]]

local ADDON_NAME, ns = ...

-- ============================================================================
-- CONSTANTS
-- ============================================================================

-- Standing colors (Custom - Gold for max rank consistency)
local STANDING_COLORS = {
    [1] = {r = 0.6, g = 0.1, b = 0.1}, -- Hated
    [2] = {r = 0.6, g = 0.1, b = 0.1}, -- Hostile
    [3] = {r = 0.6, g = 0.1, b = 0.1}, -- Unfriendly
    [4] = {r = 0.9, g = 0.7, b = 0.0}, -- Neutral
    [5] = {r = 0.0, g = 0.6, b = 0.1}, -- Friendly
    [6] = {r = 0.0, g = 0.6, b = 0.1}, -- Honored
    [7] = {r = 0.0, g = 0.6, b = 0.1}, -- Revered
    [8] = {r = 1.0, g = 0.82, b = 0.0}, -- Exalted (Gold - consistent with Renown/Friendship)
}

-- Standing names
local STANDING_NAMES = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

-- Debug print helper
local function DebugPrint(...)
    if ns.WarbandNexus and ns.WarbandNexus.db and ns.WarbandNexus.db.profile and ns.WarbandNexus.db.profile.debugMode then
        _G.print("|cffff00ff[RepProcessor]|r", ...)
    end
end

-- ============================================================================
-- REPUTATION PROCESSOR
-- ============================================================================

local ReputationProcessor = {}
ns.ReputationProcessor = ReputationProcessor

-- ============================================================================
-- MAIN ENTRY POINT
-- ============================================================================

---Process raw API data into normalized format
---@param rawData table Raw faction data from Scanner
---@return table|nil Normalized faction data
function ReputationProcessor:Process(rawData)
    if not rawData or not rawData.factionID then
        return nil
    end
    
    -- Base normalized structure
    local normalized = {
        factionID = rawData.factionID,
        name = rawData.name,
        description = rawData.description,
        
        -- Structure flags
        isHeader = rawData.isHeader or false,
        isHeaderWithRep = rawData.isHeaderWithRep or false,  -- NEW: User requirement
        -- CRITICAL: If parentFactionID exists, this IS a child (even if API says isChild=false)
        isChild = (rawData.parentFactionID ~= nil) or (rawData.isChild or false),
        isCollapsed = rawData.isCollapsed or false,
        isAccountWide = rawData.isAccountWide or false,
        isMajorFaction = rawData.isMajorFaction or false,
        parentFactionID = rawData.parentFactionID,  -- NEW: For parent-child linkage
        
        -- CRITICAL: Convert parentHeaders array to parentFactionName string
        -- BuildHeaders() uses parentFactionName (first expansion header) for grouping
        parentFactionName = (rawData.parentHeaders and rawData.parentHeaders[1]) or nil,
        parentHeaders = rawData.parentHeaders,  -- Keep original array for reference
        
        -- Base standing
        reaction = rawData.reaction or 4, -- Default: Neutral
        
        -- Paragon state (EXPLICIT initialization to avoid nil vs false issues)
        hasParagon = false,  -- Will be set to true if paragon detected below
        
        -- Metadata
        _scanTime = rawData._scanTime or time(),
        _scanSource = rawData._scanSource or "unknown",
        _scanIndex = rawData._scanIndex,  -- Critical: Used for Blizzard UI ordering
    }
    
    -- Determine faction type and process accordingly
    -- CRITICAL: type = base system (renown/friendship/classic)
    -- hasParagon = flag indicating max level + paragon available
    
    if rawData.isHeader and not rawData.isHeaderWithRep then
        -- Pure header (no rep bar)
        normalized.type = "header"
        normalized.standingID = 0
        normalized.standingName = "Header"
        normalized.standingColor = {r = 1, g = 1, b = 1}
        normalized.currentValue = 0
        normalized.maxValue = 1
    elseif rawData.isMajorFaction or rawData.renown then
        -- RENOWN (Major Factions)
        normalized.type = "renown"
        local renownData = self:ProcessRenown(rawData)
        if renownData then
            normalized.renown = renownData
            normalized.standingID = 8
            normalized.standingName = "Renown " .. renownData.level
            normalized.standingColor = {r = 1.0, g = 0.82, b = 0.0}
            normalized.currentValue = renownData.current
            normalized.maxValue = renownData.max
        end
    elseif rawData.friendship then
        -- FRIENDSHIP
        normalized.type = "friendship"
        local friendshipData = self:ProcessFriendship(rawData)
        if friendshipData then
            normalized.friendship = friendshipData
            normalized.standingID = friendshipData.level or 4
            normalized.standingName = friendshipData.reactionText or "Unknown"
            normalized.standingColor = {r = 1.0, g = 0.82, b = 0.0}
            normalized.currentValue = friendshipData.current
            normalized.maxValue = friendshipData.max
        end
    else
        -- CLASSIC
        normalized.type = "classic"
        local classicData = self:ProcessClassic(rawData)
        if classicData then
            normalized.classic = classicData
            normalized.standingID = classicData.standingID
            normalized.standingName = classicData.standingName
            normalized.standingColor = classicData.standingColor
            normalized.currentValue = classicData.current
            normalized.maxValue = classicData.max
        end
    end
    
    -- PARAGON DETECTION (applies to ANY type at max level)
    -- Paragon is a STATE, not a type
    local shouldCheckParagon = false
    local isAtMaxLevel = false
    
    if normalized.type == "classic" and rawData.reaction == 8 then
        -- Classic faction at Exalted
        shouldCheckParagon = true
        isAtMaxLevel = true
    elseif normalized.type == "renown" and rawData.renown then
        -- CRITICAL FIX: Renown Paragon detection
        -- Problem: Factions like "The Severed Threads" (Renown 25) have paragon data but API still returns threshold > 0
        -- Solution: TRUST THE API - if paragon data exists, enable it (API won't return it if not available)
        
        -- Simple check: If Scanner found paragon data for this Renown, enable paragon state
        if rawData.paragon then
            shouldCheckParagon = true
            isAtMaxLevel = true
        end
    elseif normalized.type == "friendship" and rawData.friendshipParagon then
        -- Friendship faction - Scanner already detected max level
        shouldCheckParagon = rawData.friendshipParagon.isMaxLevel
        isAtMaxLevel = true
    end
    
    if shouldCheckParagon and rawData.paragon then
        local paragonData = self:ProcessParagon(rawData)
        if paragonData then
            normalized.hasParagon = true
            normalized.paragon = paragonData
            -- Show paragon progress instead of base type progress
            normalized.currentValue = paragonData.current
            normalized.maxValue = paragonData.max
            normalized.standingName = paragonData.hasRewardPending and "Reward Waiting" or "Paragon"
            normalized.standingColor = {r = 0, g = 0.5, b = 1}  -- Pink/Purple paragon color
        end
    elseif normalized.type == "friendship" and normalized.friendship then
        -- CRITICAL FIX: Friendship Max Display
        -- If at max level WITHOUT paragon, normalize to 1/1 for clean "Max." display
        local friendship = normalized.friendship
        if friendship.level >= friendship.maxLevel and not normalized.hasParagon then
            normalized.currentValue = 1
            normalized.maxValue = 1
        end
    elseif normalized.type == "renown" and normalized.renown then
        -- CRITICAL FIX: Renown Max Display
        -- If at max level WITHOUT paragon, normalize to 1/1 for clean "Max." display
        if normalized.renown.max == 0 and not normalized.hasParagon then
            normalized.currentValue = 1
            normalized.maxValue = 1
        end
    end
    
    -- Preserve character metadata from Scanner (v2.1: Per-character storage)
    normalized._characterKey = rawData._characterKey
    normalized._characterName = rawData._characterName
    normalized._characterRealm = rawData._characterRealm
    normalized._scanTime = time()
    
    -- Preserve scan order from API (for correct sorting in UI)
    -- CRITICAL: Ensure _scanIndex always has a value (fallback to high number if missing)
    normalized._scanIndex = rawData._scanIndex or 99999
    
    -- CRITICAL: Preserve parentHeaders from Scanner (needed for BuildHeaders)
    normalized.parentHeaders = rawData.parentHeaders or {}
    
    return normalized
end

-- ============================================================================
-- CLASSIC REPUTATION
-- ============================================================================

---Process classic reputation (1-8 standing)
---@param rawData table Raw faction data
---@return table|nil Normalized classic data
function ReputationProcessor:ProcessClassic(rawData)
    -- Get standard thresholds from Constants
    local THRESHOLDS = ns.Constants and ns.Constants.CLASSIC_REP_THRESHOLDS or {}
    
    -- VALIDATE all API values
    local reaction = tonumber(rawData.reaction) or 4
    local currentStanding = tonumber(rawData.currentStanding) or 0
    local currentThreshold = tonumber(rawData.currentReactionThreshold) or 0
    local nextThreshold = tonumber(rawData.nextReactionThreshold) or 0
    
    -- Ensure valid standing range (1-8)
    if reaction < 1 then reaction = 1 end
    if reaction > 8 then reaction = 8 end
    
    -- Ensure non-negative values (but allow negative for Hated/Hostile/Unfriendly)
    if currentThreshold < -42000 then currentThreshold = -42000 end
    if nextThreshold < -42000 then nextThreshold = -42000 end
    
    -- Calculate 0-based progress (current level progress)
    local current = currentStanding - currentThreshold
    local max = nextThreshold - currentThreshold
    
    -- VALIDATION: Check against standard thresholds
    local standard = THRESHOLDS[reaction]
    if standard and standard.range > 0 then
        local expectedMax = standard.range
        
        -- Check if calculated max is wildly off (>50% deviation)
        if max > expectedMax * 1.5 or max < expectedMax * 0.5 then
            DebugPrint(string.format(
                "WARNING: Faction '%s' (ID:%d) has unusual threshold for %s: got %d, expected %d",
                rawData.name or "Unknown",
                rawData.factionID or 0,
                STANDING_NAMES[reaction] or "Unknown",
                max,
                expectedMax
            ))
            
            -- FIX: Use standard threshold
            DebugPrint("  → Correcting to standard threshold:", expectedMax)
            current = currentStanding - standard.min
            max = expectedMax
            
            -- Ensure current is within bounds
            if current < 0 then current = 0 end
            if current > max then current = max end
        end
    end
    
    -- Special handling for maxed reputations
    -- If at Exalted (reaction 8) AND either:
    -- 1. nextThreshold <= currentThreshold (no more progress)
    -- 2. nextThreshold >= 999999 (Blizzard uses 999999 for "capped")
    if reaction == 8 and (nextThreshold <= currentThreshold or nextThreshold >= 999999) then
        -- Truly maxed (no paragon, no more progress)
        -- Show "1/1" (completed) instead of huge numbers
        current = 1
        max = 1
    else
        -- Has progress within current level
        -- Ensure non-negative values
        if current < 0 then current = 0 end
        if max <= 0 then max = 1 end  -- Prevent division by zero
        
        -- Clamp current to max (safety check)
        if current > max then current = max end
    end
    
    return {
        standingID = reaction,
        standingName = STANDING_NAMES[reaction] or "Unknown",
        standingColor = STANDING_COLORS[reaction] or {r = 1, g = 1, b = 1},
        
        -- 0-based progress
        current = current,
        max = max,
        
        -- Raw values (for debugging)
        _raw = {
            currentStanding = currentStanding,
            currentThreshold = currentThreshold,
            nextThreshold = nextThreshold,
        }
    }
end

-- ============================================================================
-- RENOWN (MAJOR FACTION)
-- ============================================================================

---Process renown reputation
---@param rawData table Raw faction data
---@return table|nil Normalized renown data
function ReputationProcessor:ProcessRenown(rawData)
    if not rawData.renown then
        return nil
    end
    
    local renown = rawData.renown
    
    -- VALIDATE all API values
    local level = tonumber(renown.renownLevel) or 0
    local current = tonumber(renown.renownReputationEarned) or 0
    local max = tonumber(renown.renownLevelThreshold) or 1
    
    -- DEBUG: Log The K'aresh Trust and The Severed Threads specifically
    if rawData.factionID == 2658 or rawData.factionID == 2600 or 
       rawData.name == "The K'aresh Trust" or rawData.name == "The Severed Threads" then
        print(string.format("|cffff00ff[ProcessRenown]|r %s (ID:%d): API gave level=%d, current=%d, max=%d",
            rawData.name or "Unknown", rawData.factionID or 0, level, current, max))
    end
    
    -- Ensure valid values
    if level < 0 then level = 0 end
    if current < 0 then current = 0 end
    if max < 0 then max = 1 end
    
    -- VALIDATION: Renown thresholds vary by faction (2.5k, 5k, 7.5k, 10k, etc.)
    -- Trust API data, only validate for zero-division (done below)
    
    -- Special case: Max level renowns with 0 threshold
    -- Some renowns at max level show threshold = 0 (waiting for next expansion)
    if max == 0 and level > 0 then
        -- Check if paragon exists (should be handled by paragon detection above)
        -- For display: show "1/1" (completed) instead of "0/0"
        current = 1
        max = 1
    else
        -- Ensure valid values
        if max == 0 then max = 1 end  -- Prevent division by zero
        if current < 0 then current = 0 end
        if current > max then current = max end  -- Clamp to max
    end
    
    return {
        level = level,
        current = current,
        max = max,
        name = renown.name,
        textureKit = renown.textureKit,
        unlockDescription = renown.unlockDescription,
    }
end

-- ============================================================================
-- FRIENDSHIP
-- ============================================================================

---Process friendship reputation
---@param rawData table Raw faction data
---@return table|nil Normalized friendship data
function ReputationProcessor:ProcessFriendship(rawData)
    if not rawData.friendship then
        return nil
    end
    
    local friendship = rawData.friendship
    
    -- VALIDATE all API values (never trust raw data)
    local standing = tonumber(friendship.standing) or 0
    local reactionThreshold = tonumber(friendship.reactionThreshold) or 0
    local nextThreshold = tonumber(friendship.nextThreshold) or 0
    local maxRep = tonumber(friendship.maxRep) or 0
    
    -- Ensure non-negative values
    if standing < 0 then standing = 0 end
    if reactionThreshold < 0 then reactionThreshold = 0 end
    if nextThreshold < 0 then nextThreshold = 0 end
    if maxRep < 0 then maxRep = 0 end
    
    -- VALIDATION: Warn about suspicious threshold values (REMOVED - too many false positives)
    -- NOTE: Friendship systems vary widely:
    -- - Standard (5-10 levels): ~8k-10k per level
    -- - Cumulative (100 levels): Can reach 200k+ total
    -- Trust API data, only validate for negatives/zero-division (done above)
    
    local level = 4 -- Default: Neutral
    local maxLevel = 6
    
    if rawData.friendshipRanks then
        level = tonumber(rawData.friendshipRanks.currentLevel) or level
        maxLevel = tonumber(rawData.friendshipRanks.maxLevel) or maxLevel
        
        -- Validate level values
        if level < 1 then level = 1 end
        if maxLevel < level then maxLevel = level end
    end
    
    -- Calculate progress
    -- STRATEGY: Detect friendship type based on maxLevel and threshold values
    -- 
    -- Type 1: Multi-level CUMULATIVE (Brann - 100 levels)
    --   - standing = cumulative total rep from level 1
    --   - reactionThreshold = total rep needed to reach current level
    --   - nextThreshold = total rep needed to reach next level
    --   - Progress = standing - reactionThreshold (current level progress)
    --   - Max = nextThreshold - reactionThreshold
    --
    -- Type 2: Standard (The Weaver - 9 levels)
    --   - standing = current rank progress only (NOT cumulative)
    --   - Use standing directly as current
    --   - maxRep = threshold for current rank
    
    local current = 0
    local max = 1
    
    -- Detect cumulative system: maxLevel > 10 AND reactionThreshold > 0
    local isCumulative = (maxLevel > 10 and reactionThreshold > 0)
    
    if isCumulative then
        -- Multi-level cumulative system (Brann: 100 levels)
        -- Calculate progress within current level (0-based)
        current = standing - reactionThreshold
        
        -- Max is the level threshold (nextThreshold - reactionThreshold)
        if nextThreshold > reactionThreshold then
            max = nextThreshold - reactionThreshold
        else
            -- Fallback: use maxRep (shouldn't happen for cumulative systems)
            max = friendship.maxRep or 1
        end
        
        -- Ensure non-negative
        if current < 0 then current = 0 end
        if max <= 0 then max = 1 end
        
        -- Clamp to max (safety check)
        if current > max then current = max end
    else
        -- Standard friendship (9 levels or less)
        -- CRITICAL: Determine progress based on available data
        
        if nextThreshold > 0 and reactionThreshold >= 0 then
            -- We have threshold data - use it for accurate progress
            current = standing - reactionThreshold
            max = nextThreshold - reactionThreshold
            
            -- Handle max level case
            if level >= maxLevel then
                -- At max level - check if standing equals maxRep
                if maxRep > 0 and standing >= maxRep then
                    current = 1
                    max = 1  -- Show as complete
                elseif nextThreshold == 0 then
                    current = 1
                    max = 1  -- Show as complete
                end
            end
        elseif maxRep > 0 then
            -- Fallback: use standing and maxRep
            current = standing
            max = maxRep
        else
            -- No valid data - show as complete to avoid confusion
            current = 1
            max = 1
        end
        
        -- VALIDATE: Ensure sensible values
        if max <= 0 then max = 1 end  -- Prevent division by zero
        if current < 0 then current = 0 end  -- Non-negative
        if current > max then
            -- If current exceeds max, might be at max level
            if level >= maxLevel then
                current = max  -- Cap at max
            else
                max = current  -- Expand max to fit current
            end
        end
        
        -- Additional safety for extreme values (ONLY for non-cumulative systems)
        -- NOTE: Cumulative systems (Brann: 100 levels) can have very high thresholds (100k+)
        -- Only cap for standard friendship systems (≤10 levels)
        if max > 50000 and maxLevel <= 10 then
            -- This is likely an error for standard friendship factions
            if level >= maxLevel then
                current = 1
                max = 1
            else
                max = 10000  -- Reasonable cap for standard friendship
                if current > max then current = max end
            end
        end
    end
    
    return {
        level = level,
        maxLevel = maxLevel,
        current = current,
        max = max,
        reactionText = friendship.reaction or "Unknown",
        friendshipFactionID = friendship.friendshipFactionID,
        name = friendship.name,
        texture = friendship.texture,
    }
end

-- ============================================================================
-- PARAGON
-- ============================================================================

---Process paragon reputation (Exalted+)
---@param rawData table Raw faction data
---@return table|nil Normalized paragon data
function ReputationProcessor:ProcessParagon(rawData)
    if not rawData.paragon then
        return nil
    end
    
    local paragon = rawData.paragon
    
    -- VALIDATE all API values
    local totalValue = tonumber(paragon.currentValue) or 0
    local threshold = tonumber(paragon.threshold) or 10000
    
    -- Ensure valid values
    if totalValue < 0 then totalValue = 0 end
    if threshold <= 0 then threshold = 10000 end  -- Default paragon threshold
    
    -- Calculate cycles and current cycle progress
    -- CRITICAL: Handle edge case where totalValue == threshold exactly
    -- Should show FULL bar (threshold/threshold), not empty bar (0/threshold)
    local completedCycles = math.floor(totalValue / threshold)
    local current = totalValue % threshold
    local max = threshold
    
    -- Edge case: If current == 0 AND totalValue > 0, we're at cycle boundary
    -- Show full bar instead of empty bar (user just completed a cycle)
    if current == 0 and totalValue > 0 then
        -- At cycle boundary - show full bar for this cycle
        current = threshold
    end
    
    return {
        current = current,
        max = max,
        completedCycles = completedCycles,
        totalValue = totalValue,
        hasRewardPending = paragon.hasRewardPending or false,
        rewardQuestID = paragon.rewardQuestID,
    }
end

-- ============================================================================
-- BATCH PROCESSING
-- ============================================================================

---Process multiple raw factions
---@param rawFactions table Array of raw faction data
---@return table Array of normalized faction data
function ReputationProcessor:ProcessBatch(rawFactions)
    if not rawFactions or #rawFactions == 0 then
        DebugPrint("ERROR: No raw factions to process")
        return {}
    end
    
    local normalized = {}
    
    for _, rawData in ipairs(rawFactions) do
        local result = self:Process(rawData)
        if result then
            table.insert(normalized, result)
        end
    end
    
    return normalized
end

-- ============================================================================
-- SPEC FORMAT OUTPUT
-- ============================================================================

---Convert normalized faction data to specification format
---@param normalized table Normalized faction data from Process()
---@return table|nil Spec-format output object
function ReputationProcessor:ToSpecFormat(normalized)
    if not normalized then return nil end
    
    -- Determine status based on paragon state
    local status
    if normalized.hasParagon and normalized.paragon and normalized.paragon.hasRewardPending then
        status = "REWARD WAITING"
    elseif normalized.hasParagon then
        status = "PARAGON"
    else
        status = normalized.standingName
    end
    
    -- Calculate progress bar ratio (0-1)
    local progressBar = 0
    if normalized.maxValue and normalized.maxValue > 0 then
        progressBar = normalized.currentValue / normalized.maxValue
    end
    
    return {
        ID = normalized.factionID,
        Name = normalized.name,
        Scope = normalized.isAccountWide and "WARBAND (Account-Wide)" or "CHARACTER (Local)",
        Type = string.upper(normalized.type or "UNKNOWN"), -- "RENOWN", "FRIENDSHIP", "CLASSIC", "HEADER"
        Status = status,
        Progress_Bar = progressBar,
        At_War = normalized.atWarWith or false,
    }
end

---Convert multiple normalized factions to specification format
---@param normalizedFactions table Array of normalized faction data
---@return table Array of spec-format output objects
function ReputationProcessor:ToSpecFormatBatch(normalizedFactions)
    if not normalizedFactions or #normalizedFactions == 0 then
        return {}
    end
    
    local results = {}
    for _, normalized in ipairs(normalizedFactions) do
        local specFormat = self:ToSpecFormat(normalized)
        if specFormat then
            table.insert(results, specFormat)
        end
    end
    
    return results
end

-- ============================================================================
-- DEBUG / VALIDATION
-- ============================================================================

---Global debug function: Test process single faction and show spec format
---Usage: /run WNProcessorTest(factionID)
_G.WNProcessorTest = function(factionID)
    if not ns.ReputationScanner or not ns.ReputationProcessor then
        print("|cffff0000[Error]|r Scanner or Processor not loaded")
        return
    end
    
    -- Fetch raw data
    local rawData = ns.ReputationScanner:FetchFaction(factionID)
    if not rawData then
        print("|cffff0000[Error]|r Faction " .. factionID .. " not found")
        return nil
    end
    
    -- Process to normalized format
    local normalized = ns.ReputationProcessor:Process(rawData)
    if not normalized then
        print("|cffff0000[Error]|r Failed to process faction " .. factionID)
        return nil
    end
    
    -- Convert to spec format
    local specFormat = ns.ReputationProcessor:ToSpecFormat(normalized)
    
    -- Display results
    print("|cff00ff00[Processor Test]|r Faction: " .. (normalized.name or "Unknown"))
    print("  ID: " .. factionID)
    print("  Type: " .. (normalized.type or "unknown"))
    print("  Scope: " .. specFormat.Scope)
    print("  Status: " .. specFormat.Status)
    print("  Progress: " .. string.format("%.1f%%", specFormat.Progress_Bar * 100))
    
    if normalized.hasParagon then
        print("  |cffff00ff[PARAGON ACTIVE]|r")
        print("    Current: " .. (normalized.paragon.current or 0))
        print("    Max: " .. (normalized.paragon.max or 0))
        print("    Reward Pending: " .. tostring(normalized.paragon.hasRewardPending))
        print("    Completed Cycles: " .. (normalized.paragon.completedCycles or 0))
    end
    
    return normalized, specFormat
end

---Global debug function: Test paragon detection for all faction types
---Usage: /run WNProcessorTestParagon()
_G.WNProcessorTestParagon = function()
    if not ns.ReputationScanner or not ns.ReputationProcessor then
        print("|cffff0000[Error]|r Scanner or Processor not loaded")
        return
    end
    
    print("|cff00ff00[Paragon Test]|r Scanning all factions for paragon status...")
    
    local factions = ns.ReputationScanner:FetchAllFactions()
    local paragonFactions = {
        classic = {},
        renown = {},
        friendship = {},
    }
    
    for _, rawData in ipairs(factions) do
        local normalized = ns.ReputationProcessor:Process(rawData)
        if normalized and normalized.hasParagon then
            local typeKey = normalized.type or "unknown"
            if paragonFactions[typeKey] then
                table.insert(paragonFactions[typeKey], {
                    name = normalized.name,
                    factionID = normalized.factionID,
                    status = normalized.standingName,
                    hasReward = normalized.paragon and normalized.paragon.hasRewardPending,
                })
            end
        end
    end
    
    -- Display results
    print("|cff00ff00[Classic Paragons]|r: " .. #paragonFactions.classic)
    for _, f in ipairs(paragonFactions.classic) do
        local reward = f.hasReward and " |cffff0000[REWARD]|r" or ""
        print("  - " .. f.name .. " (ID:" .. f.factionID .. ")" .. reward)
    end
    
    print("|cff00ffff[Renown Paragons]|r: " .. #paragonFactions.renown)
    for _, f in ipairs(paragonFactions.renown) do
        local reward = f.hasReward and " |cffff0000[REWARD]|r" or ""
        print("  - " .. f.name .. " (ID:" .. f.factionID .. ")" .. reward)
    end
    
    print("|cffffcc00[Friendship Paragons]|r: " .. #paragonFactions.friendship)
    for _, f in ipairs(paragonFactions.friendship) do
        local reward = f.hasReward and " |cffff0000[REWARD]|r" or ""
        print("  - " .. f.name .. " (ID:" .. f.factionID .. ")" .. reward)
    end
    
    return paragonFactions
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

return ReputationProcessor
