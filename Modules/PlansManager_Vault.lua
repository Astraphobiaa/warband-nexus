--[[
    Warband Nexus - Weekly vault plan tracking (ops-034 slice)
    Vault progress sync, defer timer, reset, notifications.
    Loaded before Modules/PlansManager.lua.
]]

local _, ns = ...

local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS
local issecretvalue = issecretvalue
local IsDebugModeEnabled = ns.IsDebugModeEnabled

ns.PLAN_TYPES = ns.PLAN_TYPES or {}
ns.PLAN_TYPES.WEEKLY_VAULT = ns.PLAN_TYPES.WEEKLY_VAULT or "weekly_vault"
local PLAN_TYPES = ns.PLAN_TYPES

local VAULT_PLAN_CHECK_DEFER_SEC = 0.85

-- WEEKLY VAULT TRACKING

--[[
    Get weekly vault progress from API
    @param characterName string - Character name (optional, defaults to current)
    @param characterRealm string - Realm name (optional, defaults to current)
    @return table - Progress data with slot-level completion info
]]
function WarbandNexus:GetWeeklyVaultProgress(characterName, characterRealm)
    -- Use current character if not specified
    characterName = characterName or UnitName("player")
    characterRealm = characterRealm or (GetRealmName and GetRealmName())
    if characterName and issecretvalue and issecretvalue(characterName) then characterName = nil end
    if characterRealm and issecretvalue and issecretvalue(characterRealm) then characterRealm = nil end
    
    -- Check if API is available
    if not C_WeeklyRewards or not C_WeeklyRewards.GetActivities then
        return nil
    end
    
    local progress = {
        dungeonCount = 0,
        raidBossCount = 0,
        worldActivityCount = 0,
        dungeonSlots = {},  -- Slot-level completion {threshold, progress, completed}
        raidSlots = {},
        worldSlots = {}
    }
    -- When Blizzard returns multiple Activities rows (e.g. M+ vs other activity buckets), the last
    -- assignment was wrong and could show e.g. 10/8 on the dungeon bar. Prefer M+ run count API.
    local dungeonActivitiesMax = 0
    local raidProgressMax = 0
    local worldProgressMax = 0
    
    -- Get activities from API
    local activities = C_WeeklyRewards.GetActivities()
    if not activities then
        return progress
    end
    
    -- Parse activities and get slot-level data
    for ai = 1, #activities do
        local activity = activities[ai]
        local activityProgress = activity.progress or 0
        local activityThreshold = activity.threshold or 0
        local slotCompleted = activityProgress >= activityThreshold
        
        if activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
            dungeonActivitiesMax = math.max(dungeonActivitiesMax, activityProgress)
            table.insert(progress.dungeonSlots, {
                threshold = activityThreshold,
                progress = activityProgress,
                completed = slotCompleted
            })
        elseif activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
            raidProgressMax = math.max(raidProgressMax, activityProgress)
            table.insert(progress.raidSlots, {
                threshold = activityThreshold,
                progress = activityProgress,
                completed = slotCompleted
            })
        elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
            worldProgressMax = math.max(worldProgressMax, activityProgress)
            table.insert(progress.worldSlots, {
                threshold = activityThreshold,
                progress = activityProgress,
                completed = slotCompleted
            })
        end
    end

    progress.raidBossCount = raidProgressMax
    progress.worldActivityCount = worldProgressMax
    if C_WeeklyRewards.GetNumCompletedDungeonRuns then
        local ok, numHeroic, numMythic, numMythicPlus = pcall(C_WeeklyRewards.GetNumCompletedDungeonRuns)
        if ok and type(numMythicPlus) == "number" and numMythicPlus >= 0 then
            progress.dungeonCount = numMythicPlus
        else
            progress.dungeonCount = dungeonActivitiesMax
        end
    else
        progress.dungeonCount = dungeonActivitiesMax
    end
    
    -- Sort slots by threshold
    table.sort(progress.dungeonSlots, function(a, b) return a.threshold < b.threshold end)
    table.sort(progress.raidSlots, function(a, b) return a.threshold < b.threshold end)
    table.sort(progress.worldSlots, function(a, b) return a.threshold < b.threshold end)
    
    -- Special Assignments: scan bounties across known zone maps
    local saCompleted, saTotal = 0, 0
    local saMaps = ns.MIDNIGHT_MAPS_FOR_SA
    if saMaps and C_QuestLog and C_QuestLog.GetBountiesForMapID then
        local seenQuests = {}
        for mi = 1, #saMaps do
            local mapID = saMaps[mi]
            local ok, bounties = pcall(C_QuestLog.GetBountiesForMapID, mapID)
            if ok and type(bounties) == "table" then
                for bj = 1, #bounties do
                    local bi = bounties[bj]
                    if bi and bi.questID and not seenQuests[bi.questID] then
                        seenQuests[bi.questID] = true
                        saTotal = saTotal + 1
                        if C_QuestLog.IsQuestFlaggedCompleted(bi.questID) then
                            saCompleted = saCompleted + 1
                        end
                    end
                end
            end
        end
    end
    progress.specialAssignmentCount = saCompleted
    progress.specialAssignmentTotal = math.max(saTotal, 2)
    
    return progress
end

--[[
    Create a new weekly vault plan for a character
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @param trackedSlots table|nil - Which vault slots to track {dungeon=bool, raid=bool, world=bool}
    @return table - Created plan or nil if failed
]]
function WarbandNexus:CreateWeeklyPlan(characterName, characterRealm, trackedSlots)
    if not characterName or not characterRealm then
        self:Print("|cffff0000" .. ((ns.L and ns.L["ERROR_LABEL"]) or "Error:") .. "|r " .. ((ns.L and ns.L["ERROR_NAME_REALM_REQUIRED"]) or "Character name and realm required"))
        return nil
    end
    
    -- Check for existing weekly plan for this character
    if self:HasActiveWeeklyPlan(characterName, characterRealm) then
        self:Print("|cffff0000" .. ((ns.L and ns.L["ERROR_LABEL"]) or "Error:") .. "|r " .. string.format((ns.L and ns.L["ERROR_WEEKLY_PLAN_EXISTS"]) or "%s-%s already has an active weekly plan", characterName, characterRealm))
        return nil
    end
    
    -- Initialize plans table if needed
    if not self.db.global.plans then
        self.db.global.plans = {}
    end
    
    -- Generate unique ID
    local planID = self.db.global.plansNextID or 1
    self.db.global.plansNextID = planID + 1
    
    -- Get current progress from API
    local currentProgress = self:GetWeeklyVaultProgress(characterName, characterRealm) or {
        dungeonCount = 0,
        raidBossCount = 0,
        worldActivityCount = 0
    }
    
    -- Get character class (if it's the current character)
    local _, currentClass = UnitClass("player")
    local characterClass = nil
    local currentKey = ns.Utilities:GetCharacterKey()
    local canonCurrent = currentKey
    if currentKey and ns.Utilities.GetCanonicalCharacterKey then
        canonCurrent = ns.Utilities:GetCanonicalCharacterKey(currentKey) or currentKey
    end
    local planCharKey = ns.Utilities:GetCharacterKey(characterName, characterRealm)
    local canonPlan = planCharKey
    if planCharKey and ns.Utilities.GetCanonicalCharacterKey then
        canonPlan = ns.Utilities:GetCanonicalCharacterKey(planCharKey) or planCharKey
    end
    if planCharKey == currentKey or (canonPlan and canonCurrent and canonPlan == canonCurrent) then
        characterClass = currentClass
    end
    
    -- Default: track all slots unless caller specifies
    if not trackedSlots then
        trackedSlots = { dungeon = true, raid = true, world = true }
    end
    
    -- Create weekly plan structure
    local plan = {
        id = planID,
        type = "weekly_vault",
        characterName = characterName,
        characterRealm = characterRealm,
        characterClass = characterClass,
        name = string.format((ns.L and ns.L["WEEKLY_VAULT_PLAN_NAME"]) or "Weekly Vault - %s", characterName),
        icon = "Interface\\Icons\\INV_Misc_Chest_03",
        createdDate = time(),
        lastReset = time(),
        trackedSlots = trackedSlots,
        slots = {
            dungeon = {
                {threshold = 1, completed = false, manualOverride = false},
                {threshold = 4, completed = false, manualOverride = false},
                {threshold = 8, completed = false, manualOverride = false}
            },
            raid = {
                {threshold = 2, completed = false, manualOverride = false},
                {threshold = 4, completed = false, manualOverride = false},
                {threshold = 6, completed = false, manualOverride = false}
            },
            world = {
                {threshold = 2, completed = false, manualOverride = false},
                {threshold = 4, completed = false, manualOverride = false},
                {threshold = 8, completed = false, manualOverride = false}
            },
            specialAssignment = {
                {threshold = 1, completed = false, manualOverride = false},
                {threshold = 2, completed = false, manualOverride = false}
            }
        },
        progress = currentProgress
    }
    
    -- Check initial slot completions based on current progress
    self:UpdateWeeklyPlanSlots(plan, true)
    
    table.insert(self.db.global.plans, plan)
    self:RefreshPlanCache()
    self:SendMessage(E.PLANS_UPDATED, {
        action = "weekly_created",
        planID = plan.id,
        planType = plan.type,
    })
    
    self:Print("|cff00ff00Created weekly vault plan for:|r " .. characterName .. "-" .. characterRealm)
    
    return plan
end

--[[
    Update weekly plan progress from API
    @param plan table - Weekly plan to update
    @param skipNotifications boolean - If true, don't trigger notifications (for initial setup)
]]
function WarbandNexus:UpdateWeeklyPlanProgress(plan, skipNotifications)
    if not plan or plan.type ~= "weekly_vault" then
        return
    end
    
    self:Debug("UpdateWeeklyPlanProgress called for: " .. (plan.characterName or "Unknown"))
    
    -- Get current progress from API
    local currentProgress = self:GetWeeklyVaultProgress(plan.characterName, plan.characterRealm)
    if not currentProgress then
        self:Debug("No progress data from API")
        return
    end

    -- First successful vault sync this session: refresh slots/progress without checkpoint/slot toasts
    -- (avoids 4-5 false "progress" popups when PvE cache / GetActivities stabilizes after login).
    self._wnVaultPlanPostLoginSyncDone = self._wnVaultPlanPostLoginSyncDone or {}
    local planId = plan.id
    local isFirstSessionSync = planId and not self._wnVaultPlanPostLoginSyncDone[planId]
    if not skipNotifications and isFirstSessionSync then
        skipNotifications = true
    end

    if IsDebugModeEnabled and IsDebugModeEnabled() then
        self:Debug(string.format("Current progress: M+=%d, Raid=%d, World=%d",
            currentProgress.dungeonCount, currentProgress.raidBossCount, currentProgress.worldActivityCount))
    end
    
    -- Store old progress for comparison
    local oldProgress = {
        dungeonCount = plan.progress and plan.progress.dungeonCount or 0,
        raidBossCount = plan.progress and plan.progress.raidBossCount or 0,
        worldActivityCount = plan.progress and plan.progress.worldActivityCount or 0,
        specialAssignmentCount = plan.progress and plan.progress.specialAssignmentCount or 0
    }
    
    if IsDebugModeEnabled and IsDebugModeEnabled() then
        self:Debug(string.format("Old progress: M+=%d, Raid=%d, World=%d, SA=%d",
            oldProgress.dungeonCount, oldProgress.raidBossCount, oldProgress.worldActivityCount, oldProgress.specialAssignmentCount))
    end
    
    -- Update progress
    plan.progress = plan.progress or {}
    plan.progress.dungeonCount = currentProgress.dungeonCount
    plan.progress.raidBossCount = currentProgress.raidBossCount
    plan.progress.worldActivityCount = currentProgress.worldActivityCount
    plan.progress.specialAssignmentCount = currentProgress.specialAssignmentCount or 0
    plan.progress.specialAssignmentTotal = currentProgress.specialAssignmentTotal or 2
    
    -- Update slot completions and check for newly completed slots
    self:UpdateWeeklyPlanSlots(plan, skipNotifications, oldProgress)

    if planId then
        self._wnVaultPlanPostLoginSyncDone[planId] = true
    end
end

--[[
    Update slot completion status based on progress
    @param plan table - Weekly plan
    @param skipNotifications boolean - If true, don't trigger notifications
    @param oldProgress table - Previous progress for comparison (optional)
]]
function WarbandNexus:UpdateWeeklyPlanSlots(plan, skipNotifications, oldProgress)
    if not plan or not plan.slots then
        return
    end
    
    local newlyCompletedSlots = {}
    local newlyCompletedCheckpoints = {}

    -- Only toast for categories the user enabled on the weekly vault card (trackedSlots).
    local ts = plan.trackedSlots
    local function vaultCategoryNotifies(cat)
        if not ts then return true end
        return ts[cat] == true
    end
    
    -- Track old progress values for checkpoint detection
    local oldDungeonCount = oldProgress and oldProgress.dungeonCount or plan.progress.dungeonCount
    local oldRaidCount = oldProgress and oldProgress.raidBossCount or plan.progress.raidBossCount
    local oldWorldCount = oldProgress and oldProgress.worldActivityCount or plan.progress.worldActivityCount
    
    -- Update dungeon slots
    local dungeonSlots = plan.slots.dungeon
    for i = 1, #dungeonSlots do
        local slot = dungeonSlots[i]
        if not slot.manualOverride then
            local wasCompleted = slot.completed
            slot.completed = plan.progress.dungeonCount >= slot.threshold
            
            -- Check if newly completed
            if slot.completed and not wasCompleted and vaultCategoryNotifies("dungeon") then
                table.insert(newlyCompletedSlots, {category = "dungeon", index = i, threshold = slot.threshold})
            end
        end
    end
    
    -- Check for newly completed dungeon checkpoints (individual progress gains)
    if plan.progress.dungeonCount > oldDungeonCount and vaultCategoryNotifies("dungeon") then
        table.insert(newlyCompletedCheckpoints, {
            category = "dungeon",
            progress = plan.progress.dungeonCount,
            oldProgress = oldDungeonCount
        })
    end
    
    -- Update raid slots
    local raidSlots = plan.slots.raid
    for i = 1, #raidSlots do
        local slot = raidSlots[i]
        if not slot.manualOverride then
            local wasCompleted = slot.completed
            slot.completed = plan.progress.raidBossCount >= slot.threshold
            
            -- Check if newly completed
            if slot.completed and not wasCompleted and vaultCategoryNotifies("raid") then
                table.insert(newlyCompletedSlots, {category = "raid", index = i, threshold = slot.threshold})
            end
        end
    end
    
    -- Check for newly completed raid checkpoints
    if plan.progress.raidBossCount > oldRaidCount and vaultCategoryNotifies("raid") then
        table.insert(newlyCompletedCheckpoints, {
            category = "raid",
            progress = plan.progress.raidBossCount,
            oldProgress = oldRaidCount
        })
    end
    
    -- Update world slots
    local worldSlots = plan.slots.world
    for i = 1, #worldSlots do
        local slot = worldSlots[i]
        if not slot.manualOverride then
            local wasCompleted = slot.completed
            slot.completed = plan.progress.worldActivityCount >= slot.threshold
            
            -- Check if newly completed
            if slot.completed and not wasCompleted and vaultCategoryNotifies("world") then
                table.insert(newlyCompletedSlots, {category = "world", index = i, threshold = slot.threshold})
            end
        end
    end
    
    -- Check for newly completed world checkpoints
    if plan.progress.worldActivityCount > oldWorldCount and vaultCategoryNotifies("world") then
        table.insert(newlyCompletedCheckpoints, {
            category = "world",
            progress = plan.progress.worldActivityCount,
            oldProgress = oldWorldCount
        })
    end
    
    -- Update special assignment slots
    local oldSACount = oldProgress and oldProgress.specialAssignmentCount or (plan.progress.specialAssignmentCount or 0)
    if plan.slots.specialAssignment then
        local saSlots = plan.slots.specialAssignment
        for i = 1, #saSlots do
            local slot = saSlots[i]
            if not slot.manualOverride then
                local wasCompleted = slot.completed
                slot.completed = (plan.progress.specialAssignmentCount or 0) >= slot.threshold
                if slot.completed and not wasCompleted and vaultCategoryNotifies("specialAssignment") then
                    table.insert(newlyCompletedSlots, {category = "specialAssignment", index = i, threshold = slot.threshold})
                end
            end
        end
    end
    if (plan.progress.specialAssignmentCount or 0) > oldSACount and vaultCategoryNotifies("specialAssignment") then
        table.insert(newlyCompletedCheckpoints, {
            category = "specialAssignment",
            progress = plan.progress.specialAssignmentCount,
            oldProgress = oldSACount
        })
    end
    
    -- Show notifications for newly completed checkpoints (individual progress gains).
    -- When a vault *slot* completes in the same update, its milestone equals checkpoint.progress — skip the
    -- checkpoint toast so we do not duplicate the slot notification (same title, Progress vs Progress Completed).
    if not skipNotifications then
        local slotMilestoneKey = {}
        for si = 1, #newlyCompletedSlots do
            local s = newlyCompletedSlots[si]
            if s and s.category and s.threshold then
                slotMilestoneKey[s.category .. "\0" .. tostring(s.threshold)] = true
            end
        end
        for cpi = 1, #newlyCompletedCheckpoints do
            local checkpoint = newlyCompletedCheckpoints[cpi]
            if checkpoint and checkpoint.category and checkpoint.progress then
                local k = checkpoint.category .. "\0" .. tostring(checkpoint.progress)
                if slotMilestoneKey[k] then
                    self:Debug("Checkpoint skipped (slot notification covers milestone): " .. checkpoint.category .. " " .. tostring(checkpoint.progress))
                else
                    self:Debug("Checkpoint completed: " .. checkpoint.category .. " " .. checkpoint.oldProgress .. " -> " .. checkpoint.progress)
                    self:ShowWeeklyCheckpointNotification(plan.characterName, checkpoint.category, checkpoint.progress)
                end
            end
        end
    end
    
    -- Show notifications for newly completed slots
    if not skipNotifications then
        if #newlyCompletedSlots > 0 then
            self:Debug("Showing " .. #newlyCompletedSlots .. " slot completion notifications")
        end
        for si = 1, #newlyCompletedSlots do
            local slotInfo = newlyCompletedSlots[si]
            self:Debug("Slot completed: " .. slotInfo.category .. " #" .. slotInfo.index)
            self:ShowWeeklySlotNotification(plan.characterName, slotInfo.category, slotInfo.index, slotInfo.threshold)
        end
    end
    
    -- Check if all tracked slots are completed
    local tracked = plan.trackedSlots or { dungeon = true, raid = true, world = true }
    local allCompleted = true
    local slotMap = { dungeon = plan.slots.dungeon, raid = plan.slots.raid, world = plan.slots.world }
    for slotKey, slotList in pairs(slotMap) do
        if tracked[slotKey] then
            for sli = 1, #slotList do
                local slot = slotList[sli]
                if not slot.completed then allCompleted = false break end
            end
            if not allCompleted then break end
        end
    end
    
    -- Mark plan as completed if all slots are done
    local wasFullyCompleted = plan.fullyCompleted
    plan.fullyCompleted = allCompleted
    
    -- Show completion notification if just completed (only when at least one vault row is tracked)
    if not skipNotifications and plan.fullyCompleted and not wasFullyCompleted then
        local t = plan.trackedSlots
        local anyTracked = (not t)
            or t.dungeon == true or t.raid == true or t.world == true or t.specialAssignment == true
        if anyTracked then
            self:ShowWeeklyPlanCompletionNotification(plan.characterName)
        end
    end
end

--[[
    Show notification for completed checkpoint (individual progress)
    @param characterName string - Character name
    @param category string - "dungeon", "raid", or "world"
    @param progress number - Current progress value
]]
function WarbandNexus:ShowWeeklyCheckpointNotification(characterName, category, progress)
    self:Debug("Sending vault checkpoint notification: " .. category .. " - " .. characterName .. " - progress: " .. progress)
    
    -- Send vault checkpoint completion event
    self:SendMessage(E.VAULT_CHECKPOINT_COMPLETED, {
        characterName = characterName,
        category = category,
        progress = progress
    })
end

--[[
    Show notification for completed weekly slot
    @param characterName string - Character name
    @param category string - "dungeon", "raid", or "world"
    @param slotIndex number - Slot index (1-3)
    @param threshold number - Threshold value
]]
function WarbandNexus:ShowWeeklySlotNotification(characterName, category, slotIndex, threshold)
    local thresholdValues = {
        dungeon = {1, 4, 8},
        raid = {2, 4, 6},
        world = {2, 4, 8}
    }
    
    local thresholdValue = thresholdValues[category] and thresholdValues[category][slotIndex] or threshold
    
    self:Debug("Sending vault slot notification: " .. category .. " - " .. characterName)
    
    -- Send vault slot completion event
    self:SendMessage(E.VAULT_SLOT_COMPLETED, {
        characterName = characterName,
        category = category,
        slotIndex = slotIndex,
        threshold = thresholdValue
    })
end

--[[
    Show notification for fully completed weekly vault plan
    @param characterName string - Character name
]]
function WarbandNexus:ShowWeeklyPlanCompletionNotification(characterName)
    -- Send vault plan completion event
    self:SendMessage(E.VAULT_PLAN_COMPLETED, {
        characterName = characterName
    })
end


--[[
    Reset all weekly vault plans (called on weekly reset)
]]
function WarbandNexus:ResetWeeklyPlans()
    if not self.db or not self.db.global or not self.db.global.plans then
        return
    end

    local resetCount = 0

    local function resetOneVaultPlan(plan)
        if not plan or plan.type ~= PLAN_TYPES.WEEKLY_VAULT then return end
        do
            local ds = plan.slots.dungeon
            for si = 1, #ds do
                local slot = ds[si]
                slot.completed = false
                slot.manualOverride = false
            end
        end
        do
            local rs = plan.slots.raid
            for si = 1, #rs do
                local slot = rs[si]
                slot.completed = false
                slot.manualOverride = false
            end
        end
        do
            local ws = plan.slots.world
            for si = 1, #ws do
                local slot = ws[si]
                slot.completed = false
                slot.manualOverride = false
            end
        end
        if plan.slots.specialAssignment then
            local sas = plan.slots.specialAssignment
            for si = 1, #sas do
                local slot = sas[si]
                slot.completed = false
                slot.manualOverride = false
            end
        end
        plan.progress.dungeonCount = 0
        plan.progress.raidBossCount = 0
        plan.progress.worldActivityCount = 0
        plan.progress.specialAssignmentCount = 0
        plan.progress.specialAssignmentTotal = 2
        plan.completed = false
        plan.completionNotified = false
        plan.lastReset = time()
        resetCount = resetCount + 1
    end

    local list = self._weeklyVaultPlansList
    if list and #list > 0 then
        for i = 1, #list do
            resetOneVaultPlan(list[i])
        end
    else
        local _plans = self.db.global.plans
        for _i = 1, #_plans do
            local plan = _plans[_i]
            resetOneVaultPlan(plan)
        end
    end

    if resetCount > 0 then
        self:Print("|cff00ff00" .. string.format((ns.L and ns.L["VAULT_PLANS_RESET"]) or "Weekly Great Vault plans have been reset! (%d plan%s)", resetCount, (resetCount > 1 and "s" or "")) .. "|r")
        self:RefreshPlanCache()
    end
end

--[[
    Get next weekly reset time (region-aware)
    US/NA: Tuesday 15:00 UTC
    EU: Wednesday 07:00 UTC
    KR/TW/CN: Wednesday 15:00 UTC
    @return number - Unix timestamp of next reset
]]
function WarbandNexus:GetWeeklyResetTime()
    -- Try using Blizzard API first (most accurate)
    if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
        local secondsUntil = C_DateAndTime.GetSecondsUntilWeeklyReset()
        if secondsUntil and secondsUntil > 0 then
            local now = (GetServerTime and GetServerTime()) or time()
            return now + secondsUntil
        end
    end
    
    -- Fallback: Region-based calculation.
    -- Reset moments are fixed UTC instants per realm region, so every field below must be UTC:
    -- date("*t") would yield the player's LOCAL wday/hour and compare them against UTC reset
    -- hours, shifting the result by the client's UTC offset (and the wday near local midnight).
    -- Server clock, matching the primary branch above and every caller (they subtract
    -- GetServerTime from this result); time() would drift with the client's own clock.
    local currentTime = (GetServerTime and GetServerTime()) or time()
    local utcNow = date("!*t", currentTime)

    -- Detect region (portal = realm region)
    local region = GetCVar("portal") or "US"

    -- Region-specific reset times (UTC)
    -- wday: 1=Sunday, 2=Monday, 3=Tuesday, 4=Wednesday, 5=Thursday, 6=Friday, 7=Saturday
    local resetDay, resetHour
    if region == "EU" then
        resetDay = 4  -- Wednesday
        resetHour = 7  -- 07:00 UTC
    elseif region == "KR" or region == "TW" or region == "CN" then
        resetDay = 4  -- Wednesday
        resetHour = 15  -- 15:00 UTC
    else  -- US, OCE, others
        resetDay = 3  -- Tuesday
        resetHour = 15  -- 15:00 UTC
    end

    -- Seconds elapsed in the current UTC day, and the epoch of 00:00 UTC today.
    local secondsIntoUtcDay = (utcNow.hour * 3600) + (utcNow.min * 60) + utcNow.sec
    local utcMidnight = currentTime - secondsIntoUtcDay

    -- Days until the next reset weekday, evaluated on the UTC calendar
    local daysUntilReset = (resetDay - utcNow.wday + 7) % 7
    if daysUntilReset == 0 and secondsIntoUtcDay >= (resetHour * 3600) then
        daysUntilReset = 7  -- Today's reset already passed
    end

    -- Pure epoch arithmetic on purpose: time(table) would read the fields as LOCAL time and
    -- need a UTC-offset correction, which is itself DST-dependent and drifts by an hour across
    -- a transition. A UTC day is always exactly 86400s, so this needs neither offset nor isdst.
    return utcMidnight + (daysUntilReset * 86400) + (resetHour * 3600)
end

function WarbandNexus:FormatTimeUntilReset(resetTime)
    return ns.Utilities:FormatTimeUntilReset(resetTime)
end

--[[
    Check if character already has an active weekly plan
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @return table|nil - Existing plan if found, nil otherwise
]]
function WarbandNexus:HasActiveWeeklyPlan(characterName, characterRealm)
    if not self.db or not self.db.global or not self.db.global.plans then
        return nil
    end

    local getKey = ns.Utilities and ns.Utilities.GetCharacterKey
    if getKey then
        local pk = getKey(characterName, characterRealm)
        local vlist = pk and self._weeklyVaultPlansByCharKey and self._weeklyVaultPlansByCharKey[pk]
        if vlist then
            for i = 1, #vlist do
                local plan = vlist[i]
                if plan and plan.type == PLAN_TYPES.WEEKLY_VAULT
                    and plan.characterName == characterName
                    and plan.characterRealm == characterRealm then
                    return plan
                end
            end
        end
    end

    local _plans = self.db.global.plans
    for _i = 1, #_plans do
        local plan = _plans[_i]
        if plan.type == "weekly_vault" and
            plan.characterName == characterName and
            plan.characterRealm == characterRealm then
            return plan
        end
    end

    return nil
end

--[[
    Clear deferred vault-plan check timer and per-plan "first sync" flags (new login / reload).
]]
function WarbandNexus:OnVaultPlanSessionReset()
    self._wnVaultPlanPostLoginSyncDone = {}
    if self._wnVaultPlanCheckTimer then
        self._wnVaultPlanCheckTimer:Cancel()
        self._wnVaultPlanCheckTimer = nil
    end
end

--[[
    Coalesce rapid WN_PVE_UPDATED bursts (login / cache refresh) before reconciling vault plans.
]]
function WarbandNexus:_DeferVaultPlanCheckFromPvE()
    if self._wnVaultPlanCheckTimer then
        self._wnVaultPlanCheckTimer:Cancel()
        self._wnVaultPlanCheckTimer = nil
    end
    self._wnVaultPlanCheckTimer = C_Timer.NewTimer(VAULT_PLAN_CHECK_DEFER_SEC, function()
        self._wnVaultPlanCheckTimer = nil
        if self.OnPvEUpdateCheckPlans then
            self:OnPvEUpdateCheckPlans()
        end
    end)
end

--[[
    Event handler for PvE data update (vault plans progress check)
    NOTE: Named OnPvEUpdateCheckPlans to avoid collision with PvECacheService:OnVaultDataReceived
]]
function WarbandNexus:OnPvEUpdateCheckPlans()
    if not self.db or not self.db.global or not self.db.global.plans then
        return
    end

    local currentName = UnitName("player")
    local currentRealm = GetRealmName and GetRealmName()
    if currentName and issecretvalue and issecretvalue(currentName) then currentName = nil end
    if currentRealm and issecretvalue and issecretvalue(currentRealm) then currentRealm = nil end

    self:Debug("PvE Update - checking vault plans for: "
        .. (currentName or "?") .. "-" .. (currentRealm or "?"))

    local currentKey = ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey()
    local vaultList = currentKey and self._weeklyVaultPlansByCharKey and self._weeklyVaultPlansByCharKey[currentKey]

    if vaultList then
        for i = 1, #vaultList do
            local plan = vaultList[i]
            if plan and plan.type == PLAN_TYPES.WEEKLY_VAULT
                and plan.characterName == currentName
                and plan.characterRealm == currentRealm then
                self:Debug("Updating weekly plan progress...")
                self:UpdateWeeklyPlanProgress(plan)
            end
        end
        return
    end

    local _plans = self.db.global.plans
    for _i = 1, #_plans do
        local plan = _plans[_i]
        if plan.type == "weekly_vault" and
            plan.characterName == currentName and
            plan.characterRealm == currentRealm then
            self:Debug("Updating weekly plan progress...")
            self:UpdateWeeklyPlanProgress(plan)
        end
    end
end
--[[
    Check for weekly reset on login
]]
function WarbandNexus:CheckWeeklyReset()
    local resetTime = self:GetWeeklyResetTime()

    if not self.db or not self.db.global or not self.db.global.plans then
        return
    end

    local threshold = resetTime - 7 * 24 * 60 * 60
    local list = self._weeklyVaultPlansList
    if list and #list > 0 then
        for i = 1, #list do
            local plan = list[i]
            if plan and plan.type == PLAN_TYPES.WEEKLY_VAULT and plan.lastReset < threshold then
                self:ResetWeeklyPlans()
                return
            end
        end
        return
    end

    local _plans = self.db.global.plans
    for _i = 1, #_plans do
        local plan = _plans[_i]
        if plan.type == "weekly_vault" then
            if plan.lastReset < threshold then
                self:ResetWeeklyPlans()
                return
            end
        end
    end
end
