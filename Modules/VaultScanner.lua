--[[
    VaultScanner.lua
    
    ARCHITECTURE: Event-driven Great Vault tracker for Mythic+ Dungeons.
    
    WHY THIS EXISTS:
    - WoW server does NOT send vault data automatically on login
    - Must explicitly request data via C_WeeklyRewards.OnUIInteract()
    - This service properly initializes and tracks all 3 M+ vault slots
    
    API FLOW:
    1. PLAYER_ENTERING_WORLD -> Call OnUIInteract() to request data from server
    2. WEEKLY_REWARDS_UPDATE -> Process data when server responds
    3. Store results in cache for UI consumption
    
    RULES:
    - NO hardcoded iLvl tables (use native APIs only)
    - Event-driven only (no polling/OnUpdate)
    - Safe nil handling for all API calls
]]

local addonName, ns = ...

-- Bail if already loaded
if ns.VaultScanner then return end

-- Local cache for vault data
local vaultCache = {
    slots = {},  -- Array of 9 slots with current/next iLvl info
    lastUpdate = 0,
    initialized = false,
    seasonMax = {  -- Season-wide max iLvl caps (memoized)
        mplus = 0,
        world = 0,
        raid = 0,
    }
}

-- Hidden frame for event handling
local scannerFrame = CreateFrame("Frame")

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

---Parse item level from item link using native API
---@param itemLink string Item hyperlink
---@return number Item level (0 if failed)
local function GetItemLevelFromLink(itemLink)
    if not itemLink or itemLink == "" then
        return 0
    end
    
    -- Use C_Item API (safe, no cache delays)
    if C_Item and C_Item.GetDetailedItemLevelInfo then
        local effectiveILvl, _, baseILvl = C_Item.GetDetailedItemLevelInfo(itemLink)
        return effectiveILvl or baseILvl or 0
    end
    
    return 0
end

---Format slot status for debug output
---@param slot table Slot data
---@return string Formatted string
local function FormatSlotStatus(slot)
    if not slot then return "N/A" end
    
    if slot.isLocked then
        return string.format("LOCKED (%d/%d runs)", slot.progress or 0, slot.threshold or 1)
    end
    
    local current = slot.currentILvl or 0
    local next = slot.nextILvl or 0
    local nextKeyLevel = slot.nextKeyLevel or "?"
    
    if next > 0 then
        return string.format("%d iLvl (Next: +%s for %d iLvl)", current, tostring(nextKeyLevel), next)
    elseif current > 0 then
        return string.format("%d iLvl (MAXED)", current)
    else
        return "NO DATA"
    end
end

-- ============================================================================
-- CORE LOGIC
-- ============================================================================

---Probe the season to find maximum item level caps for each activity type
---This runs ONCE (lazy-loaded) and memoizes the results
---@param activities table Optional activities array to scan for Raid/World max
---@return table Season max rewards {mplus, world, raid}
local function GetSeasonMaxRewards(activities)
    -- Return cached values if already probed
    if vaultCache.seasonMax.mplus > 0 then
        return vaultCache.seasonMax
    end
    
    -- ========================================
    -- MYTHIC+ MAX PROBE
    -- ========================================
    if C_WeeklyRewards and C_WeeklyRewards.GetNextMythicPlusIncrease then
        local maxMPlusIlvl = 0
        local safetyCounter = 0
        local currentLevel = 2  -- Start from +2 (safe baseline)
        
        while safetyCounter < 25 do
            safetyCounter = safetyCounter + 1
            
            local hasSeasonData, nextLevel, itemLevel = C_WeeklyRewards.GetNextMythicPlusIncrease(currentLevel)
            
            -- Break if no more data
            if not hasSeasonData or not nextLevel or not itemLevel then
                break
            end
            
            -- Track highest iLvl seen
            if itemLevel > maxMPlusIlvl then
                maxMPlusIlvl = itemLevel
            end
            
            -- Move to next tier
            currentLevel = nextLevel
            
            -- Break if we've reached the cap (nextLevel stops increasing)
            if nextLevel >= 20 then
                break
            end
        end
        
        vaultCache.seasonMax.mplus = maxMPlusIlvl
    end
    
    return vaultCache.seasonMax
end

---Request vault data from server (REQUIRED on login)
local function RequestVaultData()
    if not C_WeeklyRewards then return end
    
    -- This "pokes" the server to send us the data
    C_WeeklyRewards.OnUIInteract()
end

---Process vault data when server responds
local function UpdateVaultData()
    if not C_WeeklyRewards then
        return
    end
    
    -- Get ALL activities (not filtered by type)
    local activities = C_WeeklyRewards.GetActivities()
    
    if not activities or #activities == 0 then
        return
    end
    
    -- CRITICAL: Probe season max rewards (pass activities for Raid/World detection)
    local seasonMax = GetSeasonMaxRewards(activities)
    
    -- Sort by index to ensure proper slot order
    table.sort(activities, function(a, b)
        return (a.index or 0) < (b.index or 0)
    end)
    
    -- Clear cache
    vaultCache.slots = {}
    
    -- Group activities by type
    local activitiesByType = {
        Raid = {},
        ["M+"] = {},
        World = {},
        PvP = {},
    }
    
    for _, activity in ipairs(activities) do
        local typeName = "Unknown"
        local typeNum = activity.type
        
        if Enum and Enum.WeeklyRewardChestThresholdType then
            if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then
                typeName = "Raid"
            elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then
                typeName = "M+"
            elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then
                typeName = "World"
            elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then
                typeName = "PvP"
            end
        else
            -- Fallback numeric values
            if typeNum == 3 then typeName = "Raid"
            elseif typeNum == 1 then typeName = "M+"
            elseif typeNum == 6 then typeName = "World"
            elseif typeNum == 2 then typeName = "PvP"
            end
        end
        
        if not activitiesByType[typeName] then
            activitiesByType[typeName] = {}
        end
        table.insert(activitiesByType[typeName], activity)
    end
    
    -- Process each type
    for typeName, typeActivities in pairs(activitiesByType) do
        if #typeActivities > 0 then
            for _, activity in ipairs(typeActivities) do
                local slot = {
                    index = activity.index,
                    activityID = activity.id,
                    progress = activity.progress or 0,
                    threshold = activity.threshold or 1,
                    level = activity.level or 0,
                    typeName = typeName,
                    isLocked = (activity.progress or 0) < (activity.threshold or 1),
                    currentILvl = 0,
                    nextILvl = 0,
                    maxILvl = 0,
                    nextKeyLevel = nil,
                }
                
                -- Check if slot is unlocked
                if not slot.isLocked and activity.id then
                    -- Get reward hyperlinks (current and next upgrade)
                    local currentLink, upgradeLink = C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)
                    
                    -- Parse current iLvl
                    if currentLink then
                        slot.currentILvl = GetItemLevelFromLink(currentLink)
                    end
                    
                    -- Parse next upgrade iLvl
                    if upgradeLink then
                        slot.nextILvl = GetItemLevelFromLink(upgradeLink)
                        
                        -- For M+, try to determine what key level gives this upgrade
                        if typeName == "M+" and slot.level and slot.level > 0 and C_WeeklyRewards.GetNextMythicPlusIncrease then
                            local hasSeasonData, nextKeyLevel, nextILvl = C_WeeklyRewards.GetNextMythicPlusIncrease(slot.level)
                            if hasSeasonData and nextKeyLevel then
                                slot.nextKeyLevel = nextKeyLevel
                            end
                        end
                    else
                        -- No upgrade link = player is maxed out
                        if typeName == "M+" and C_WeeklyRewards.GetNextMythicPlusIncrease and slot.level then
                            local hasSeasonData, nextKeyLevel, nextILvl = C_WeeklyRewards.GetNextMythicPlusIncrease(slot.level)
                            if not hasSeasonData or not nextKeyLevel then
                                -- Truly maxed out
                                slot.nextILvl = 0
                                slot.nextKeyLevel = "MAX"
                            else
                                -- There IS a next tier, populate it
                                slot.nextILvl = nextILvl or 0
                                slot.nextKeyLevel = nextKeyLevel
                            end
                        end
                    end
                    
                    -- Set MAX iLvl only for M+ (Raid/World don't need it)
                    if typeName == "M+" then
                        slot.maxILvl = seasonMax.mplus or 0
                    else
                        slot.maxILvl = 0
                    end
                end
                
                -- Store slot
                table.insert(vaultCache.slots, slot)
            end
        end
    end
    
    -- Update metadata
    vaultCache.lastUpdate = time()
    vaultCache.initialized = true
    
    -- VaultScanner logs disabled for clean output
    
    -- CRITICAL: Forward data to PvECacheService for UI consumption
    if ns.WarbandNexus and ns.WarbandNexus.SyncVaultDataFromScanner then
        ns.WarbandNexus:SyncVaultDataFromScanner(vaultCache.slots)
    end
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

scannerFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
scannerFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")

scannerFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Player logged in or reloaded UI
        -- Request data from server
        C_Timer.After(1, function()
            RequestVaultData()
        end)
        
    elseif event == "WEEKLY_REWARDS_UPDATE" then
        -- Server sent us vault data
        -- Process immediately
        UpdateVaultData()
    end
end)

-- ============================================================================
-- PUBLIC API
-- ============================================================================

ns.VaultScanner = {
    ---Get cached vault slot data
    ---@return table Array of 3 slots with current/next iLvl info
    GetSlots = function()
        return vaultCache.slots
    end,
    
    ---Get last update timestamp
    ---@return number Unix timestamp
    GetLastUpdate = function()
        return vaultCache.lastUpdate
    end,
    
    ---Check if scanner has initialized
    ---@return boolean
    IsInitialized = function()
        return vaultCache.initialized
    end,
    
    ---Manually trigger a refresh (calls OnUIInteract)
    Refresh = function()
        RequestVaultData()
    end,
}
