--[[
    Warband Nexus - Plans Manager Module
    Handles CRUD operations for user plans (mounts, pets, toys, recipes)
    
    Plans allow users to track collection goals with source information
    and material requirements.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- PLAN TYPES
-- ============================================================================

local PLAN_TYPES = {
    MOUNT = "mount",
    PET = "pet",
    TOY = "toy",
    RECIPE = "recipe",
    ACHIEVEMENT = "achievement",
    ILLUSION = "illusion",
    TITLE = "title",
    WEEKLY_VAULT = "weekly_vault",
}

ns.PLAN_TYPES = PLAN_TYPES

-- ============================================================================
-- PLAN TRACKING & NOTIFICATIONS
-- ============================================================================

--[[
    Initialize plan completion tracking
    Registers events to check for completed plans
]]
function WarbandNexus:InitializePlanTracking()
    -- Register collection events
    self:RegisterEvent("NEW_MOUNT_ADDED", "OnPlanCollectionUpdated")
    self:RegisterEvent("NEW_PET_ADDED", "OnPlanCollectionUpdated")
    self:RegisterEvent("NEW_TOY_ADDED", "OnPlanCollectionUpdated")
    self:RegisterEvent("ACHIEVEMENT_EARNED", "OnPlanCollectionUpdated")
    
    -- Register weekly vault events
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnWeeklyRewardsUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    
    -- Register events that trigger weekly vault progress updates
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnWeeklyRewardsUpdate")  -- M+ completion
    self:RegisterEvent("ENCOUNTER_END", "OnWeeklyRewardsUpdate")  -- Boss kill (raids)
    self:RegisterEvent("QUEST_TURNED_IN", "OnWeeklyRewardsUpdate")  -- World activities
    
    -- Check all plans on login (after delay to ensure APIs are ready)
    C_Timer.After(3, function()
        self:CheckPlansForCompletion()
        self:CheckWeeklyReset()
    end)
end

--[[
    Event handler for collection updates
    Checks if any plans were completed
]]
function WarbandNexus:OnPlanCollectionUpdated(event, ...)
    -- Debounce multiple events
    if self.planCheckTimer then
        self.planCheckTimer:Cancel()
    end
    
    self.planCheckTimer = C_Timer.After(0.5, function()
        self:CheckPlansForCompletion()
    end)
end

--[[
    Check all active plans for completion
    Shows notifications for newly completed plans
]]
function WarbandNexus:CheckPlansForCompletion()
    if not self.db or not self.db.global or not self.db.global.plans then
        return
    end
    
    for _, plan in ipairs(self.db.global.plans) do
        -- Skip if already completed OR already notified
        -- This prevents showing notifications for old completed plans on login
        if not plan.completed and not plan.completionNotified then
            local progress = self:CheckPlanProgress(plan)
            
            -- If plan is now collected, show notification
            if progress and progress.collected then
                self:ShowPlanCompletedNotification(plan)
                plan.completed = true -- Mark as completed
                plan.completionNotified = true -- Mark as notified
            end
        end
    end
end

--[[
    Show a toast notification for a completed plan
    @param plan table - The completed plan
]]
function WarbandNexus:ShowPlanCompletedNotification(plan)
    local planTypeNames = {
        mount = "Mount",
        pet = "Pet",
        toy = "Toy",
        achievement = "Achievement",
        illusion = "Illusion",
        title = "Title",
        recipe = "Recipe",
        custom = "Goal",
    }
    
    -- Icon mapping for plan types
    local planTypeIcons = {
        mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
        pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
        toy = "Interface\\Icons\\INV_Misc_Toy_07",
        achievement = "Interface\\Icons\\Achievement_Quests_Completed_08",
        illusion = "Interface\\Icons\\INV_Enchant_Disenchant",
        title = "Interface\\Icons\\INV_Scroll_11", -- Parşömen scroll
        recipe = "Interface\\Icons\\INV_Scroll_08",
        custom = "Interface\\Icons\\INV_Misc_Note_06", -- Note/parchment for custom plans
    }
    
    local typeName = planTypeNames[plan.type] or "Item"
    local typeIcon = planTypeIcons[plan.type] or "Interface\\Icons\\INV_Misc_QuestionMark"
    
    self:ShowToastNotification({
        icon = typeIcon,
        title = "Plan Completed!",
        message = plan.name,
        subtitle = typeName .. " collected",
        planType = "plan",
        category = "PLAN_COMPLETED",
        playSound = true,
        autoDismiss = 10,
    })
    
    self:Print("|cff00ff00Plan completed:|r " .. plan.name)
end

-- ============================================================================
-- WEEKLY VAULT TRACKING
-- ============================================================================

--[[
    Get weekly vault progress from API
    @param characterName string - Character name (optional, defaults to current)
    @param characterRealm string - Realm name (optional, defaults to current)
    @return table - Progress data with slot-level completion info
]]
function WarbandNexus:GetWeeklyVaultProgress(characterName, characterRealm)
    -- Use current character if not specified
    characterName = characterName or UnitName("player")
    characterRealm = characterRealm or GetRealmName()
    
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
    
    -- Get activities from API
    local activities = C_WeeklyRewards.GetActivities()
    if not activities then
        return progress
    end
    
    -- Parse activities and get slot-level data
    for _, activity in ipairs(activities) do
        local activityProgress = activity.progress or 0
        local activityThreshold = activity.threshold or 0
        local slotCompleted = activityProgress >= activityThreshold
        
        if activity.type == Enum.WeeklyRewardChestThresholdType.Activities then
            -- Mythic+ Dungeons
            progress.dungeonCount = activityProgress
            table.insert(progress.dungeonSlots, {
                threshold = activityThreshold,
                progress = activityProgress,
                completed = slotCompleted
            })
        elseif activity.type == Enum.WeeklyRewardChestThresholdType.Raid then
            -- Raid bosses
            progress.raidBossCount = activityProgress
            table.insert(progress.raidSlots, {
                threshold = activityThreshold,
                progress = activityProgress,
                completed = slotCompleted
            })
        elseif activity.type == Enum.WeeklyRewardChestThresholdType.World then
            -- World activities
            progress.worldActivityCount = activityProgress
            table.insert(progress.worldSlots, {
                threshold = activityThreshold,
                progress = activityProgress,
                completed = slotCompleted
            })
        end
    end
    
    -- Sort slots by threshold
    table.sort(progress.dungeonSlots, function(a, b) return a.threshold < b.threshold end)
    table.sort(progress.raidSlots, function(a, b) return a.threshold < b.threshold end)
    table.sort(progress.worldSlots, function(a, b) return a.threshold < b.threshold end)
    
    return progress
end

--[[
    Create a new weekly vault plan for a character
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @return table - Created plan or nil if failed
]]
function WarbandNexus:CreateWeeklyPlan(characterName, characterRealm)
    if not characterName or not characterRealm then
        self:Print("|cffff0000Error:|r Character name and realm required")
        return nil
    end
    
    -- Check for existing weekly plan for this character
    if self:HasActiveWeeklyPlan(characterName, characterRealm) then
        self:Print("|cffff0000Error:|r " .. characterName .. "-" .. characterRealm .. " already has an active weekly plan")
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
    if characterName == UnitName("player") and characterRealm == GetRealmName() then
        characterClass = currentClass
    end
    
    -- Create weekly plan structure
    local plan = {
        id = planID,
        type = "weekly_vault",
        characterName = characterName,
        characterRealm = characterRealm,
        characterClass = characterClass,  -- Store class for color coding
        name = "Weekly Vault - " .. characterName,
        icon = "Interface\\Icons\\INV_Misc_Chest_03", -- Great Vault chest icon
        createdDate = time(),
        lastReset = time(),
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
            }
        },
        progress = currentProgress
    }
    
    -- Check initial slot completions based on current progress
    self:UpdateWeeklyPlanSlots(plan, true)
    
    table.insert(self.db.global.plans, plan)
    
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
    
    self:Debug(string.format("Current progress: M+=%d, Raid=%d, World=%d", 
        currentProgress.dungeonCount, currentProgress.raidBossCount, currentProgress.worldActivityCount))
    
    -- Store old progress for comparison
    local oldProgress = {
        dungeonCount = plan.progress and plan.progress.dungeonCount or 0,
        raidBossCount = plan.progress and plan.progress.raidBossCount or 0,
        worldActivityCount = plan.progress and plan.progress.worldActivityCount or 0
    }
    
    self:Debug(string.format("Old progress: M+=%d, Raid=%d, World=%d", 
        oldProgress.dungeonCount, oldProgress.raidBossCount, oldProgress.worldActivityCount))
    
    -- Update progress
    plan.progress = plan.progress or {}
    plan.progress.dungeonCount = currentProgress.dungeonCount
    plan.progress.raidBossCount = currentProgress.raidBossCount
    plan.progress.worldActivityCount = currentProgress.worldActivityCount
    
    -- Update slot completions and check for newly completed slots
    self:UpdateWeeklyPlanSlots(plan, skipNotifications, oldProgress)
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
    
    -- Update dungeon slots
    for i, slot in ipairs(plan.slots.dungeon) do
        if not slot.manualOverride then
            local wasCompleted = slot.completed
            slot.completed = plan.progress.dungeonCount >= slot.threshold
            
            -- Check if newly completed
            if slot.completed and not wasCompleted then
                table.insert(newlyCompletedSlots, {category = "dungeon", index = i, threshold = slot.threshold})
            end
        end
    end
    
    -- Update raid slots
    for i, slot in ipairs(plan.slots.raid) do
        if not slot.manualOverride then
            local wasCompleted = slot.completed
            slot.completed = plan.progress.raidBossCount >= slot.threshold
            
            -- Check if newly completed
            if slot.completed and not wasCompleted then
                table.insert(newlyCompletedSlots, {category = "raid", index = i, threshold = slot.threshold})
            end
        end
    end
    
    -- Update world slots
    for i, slot in ipairs(plan.slots.world) do
        if not slot.manualOverride then
            local wasCompleted = slot.completed
            slot.completed = plan.progress.worldActivityCount >= slot.threshold
            
            -- Check if newly completed
            if slot.completed and not wasCompleted then
                table.insert(newlyCompletedSlots, {category = "world", index = i, threshold = slot.threshold})
            end
        end
    end
    
    -- Show notifications for newly completed slots
    if not skipNotifications then
        if #newlyCompletedSlots > 0 then
            self:Debug("Showing " .. #newlyCompletedSlots .. " slot completion notifications")
        end
        for _, slotInfo in ipairs(newlyCompletedSlots) do
            self:Debug("Slot completed: " .. slotInfo.category .. " #" .. slotInfo.index)
            self:ShowWeeklySlotNotification(plan.characterName, slotInfo.category, slotInfo.index, slotInfo.threshold)
        end
    end
    
    -- Check if all slots are completed
    local allCompleted = true
    for _, slot in ipairs(plan.slots.dungeon) do
        if not slot.completed then allCompleted = false break end
    end
    if allCompleted then
        for _, slot in ipairs(plan.slots.raid) do
            if not slot.completed then allCompleted = false break end
        end
    end
    if allCompleted then
        for _, slot in ipairs(plan.slots.world) do
            if not slot.completed then allCompleted = false break end
        end
    end
    
    -- Mark plan as completed if all slots are done
    local wasFullyCompleted = plan.fullyCompleted
    plan.fullyCompleted = allCompleted
    
    -- Show completion notification if just completed
    if not skipNotifications and plan.fullyCompleted and not wasFullyCompleted then
        self:ShowWeeklyPlanCompletionNotification(plan.characterName)
    end
end

--[[
    Show notification for completed weekly slot
    @param characterName string - Character name
    @param category string - "dungeon", "raid", or "world"
    @param slotIndex number - Slot index (1-3)
    @param threshold number - Threshold value
]]
function WarbandNexus:ShowWeeklySlotNotification(characterName, category, slotIndex, threshold)
    local categoryNames = {
        dungeon = "Dungeon",
        raid = "Raid",
        world = "World"
    }
    
    local categoryAtlas = {
        dungeon = "questlog-questtypeicon-heroic",
        raid = "questlog-questtypeicon-raid",
        world = "questlog-questtypeicon-Delves"
    }
    
    local thresholdValues = {
        dungeon = {1, 4, 8},
        raid = {2, 4, 6},
        world = {2, 4, 8}
    }
    
    local categoryName = categoryNames[category] or "Activity"
    local atlas = categoryAtlas[category] or "greatVault-whole-normal"
    local thresholdValue = thresholdValues[category] and thresholdValues[category][slotIndex] or threshold
    
    -- Format: "2/2 Progress Completed"
    local progressText = string.format("%d/%d Progress Completed", thresholdValue, thresholdValue)
    
    self:Debug("Showing notification: " .. categoryName .. " - " .. characterName .. " | " .. progressText)
    
    -- Ensure ShowToastNotification exists
    if not self.ShowToastNotification then
        self:Print("|cffff0000Error:|r ShowToastNotification not found!")
        return
    end
    
    self:ShowToastNotification({
        iconAtlas = atlas,
        itemName = categoryName .. " - " .. characterName,
        action = progressText,
        autoDismiss = 10,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

--[[
    Show notification for fully completed weekly vault plan
    @param characterName string - Character name
]]
function WarbandNexus:ShowWeeklyPlanCompletionNotification(characterName)
    self:ShowToastNotification({
        iconAtlas = "greatVault-whole-normal",
        itemName = "Weekly Vault Plan - " .. characterName,
        action = "All Slots Complete!",
        autoDismiss = 15,
        playSound = true,
        glowAtlas = "TopBottom:UI-Frame-DastardlyDuos-Line",
    })
end

--[[
    Reset all weekly vault plans (called on weekly reset)
]]
function WarbandNexus:ResetWeeklyPlans()
    if not self.db.global.plans then
        return
    end
    
    local resetCount = 0
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "weekly_vault" then
            -- Reset all slots
            for _, slot in ipairs(plan.slots.dungeon) do
                slot.completed = false
                slot.manualOverride = false
            end
            for _, slot in ipairs(plan.slots.raid) do
                slot.completed = false
                slot.manualOverride = false
            end
            for _, slot in ipairs(plan.slots.world) do
                slot.completed = false
                slot.manualOverride = false
            end
            
            -- Reset progress
            plan.progress.dungeonCount = 0
            plan.progress.raidBossCount = 0
            plan.progress.worldActivityCount = 0
            
            -- Update last reset time
            plan.lastReset = time()
            
            resetCount = resetCount + 1
        end
    end
    
    if resetCount > 0 then
        self:Print("|cff00ff00Weekly Great Vault plans have been reset!|r (" .. resetCount .. " plan" .. (resetCount > 1 and "s" or "") .. ")")
    end
end

--[[
    Get next weekly reset time (Tuesday at server reset time)
    @return number - Unix timestamp of next reset
]]
function WarbandNexus:GetWeeklyResetTime()
    local currentTime = time()
    local currentDate = date("*t", currentTime)
    
    -- Calculate days until next Tuesday (1 = Sunday, 2 = Monday, 3 = Tuesday, etc.)
    local dayOfWeek = currentDate.wday
    local daysUntilTuesday = (10 - dayOfWeek) % 7  -- Days until next Tuesday
    
    if daysUntilTuesday == 0 then
        -- It's Tuesday, check if reset has passed (reset is at 15:00 UTC / 10:00 AM EST)
        local resetHour = 15 -- 3 PM UTC
        if currentDate.hour >= resetHour then
            daysUntilTuesday = 7 -- Next week
        end
    end
    
    -- Calculate next Tuesday's date
    local resetDate = date("*t", currentTime + (daysUntilTuesday * 24 * 60 * 60))
    resetDate.hour = 15  -- 3 PM UTC
    resetDate.min = 0
    resetDate.sec = 0
    
    return time(resetDate)
end

--[[
    Format time until reset as readable string
    @param resetTime number - Unix timestamp of reset
    @return string - Formatted string (e.g., "2d 14h")
]]
function WarbandNexus:FormatTimeUntilReset(resetTime)
    local currentTime = time()
    local diff = resetTime - currentTime
    
    if diff <= 0 then
        return "Resetting..."
    end
    
    local days = math.floor(diff / (24 * 60 * 60))
    local hours = math.floor((diff % (24 * 60 * 60)) / (60 * 60))
    local minutes = math.floor((diff % (60 * 60)) / 60)
    
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes)
    else
        return string.format("%dm", minutes)
    end
end

--[[
    Check if character already has an active weekly plan
    @param characterName string - Character name
    @param characterRealm string - Realm name
    @return table|nil - Existing plan if found, nil otherwise
]]
function WarbandNexus:HasActiveWeeklyPlan(characterName, characterRealm)
    if not self.db.global.plans then
        return nil
    end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "weekly_vault" and 
           plan.characterName == characterName and 
           plan.characterRealm == characterRealm then
            return plan
        end
    end
    
    return nil
end

--[[
    Event handler for weekly rewards update
]]
function WarbandNexus:OnWeeklyRewardsUpdate()
    if not self.db.global.plans then
        return
    end
    
    -- Get current character info
    local currentName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- Debug: Log event
    self:Debug("Weekly Rewards Update triggered for: " .. currentName .. "-" .. currentRealm)
    
    -- Update weekly plans for current character
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "weekly_vault" and 
           plan.characterName == currentName and 
           plan.characterRealm == currentRealm then
            self:Debug("Updating weekly plan progress...")
            self:UpdateWeeklyPlanProgress(plan)
        end
    end
end

--[[
    Event handler for player entering world
]]
function WarbandNexus:OnPlayerEnteringWorld(event, isLogin, isReload)
    if isLogin or isReload then
        -- Check for weekly reset on login
        C_Timer.After(3, function()
            self:CheckWeeklyReset()
        end)
    end
end

--[[
    Check for weekly reset on login
]]
function WarbandNexus:CheckWeeklyReset()
    local resetTime = self:GetWeeklyResetTime()
    local currentTime = time()
    
    -- Check each weekly plan to see if it needs reset
    if not self.db.global.plans then
        return
    end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == "weekly_vault" then
            -- Check if last reset was before the most recent Tuesday reset
            if plan.lastReset < (resetTime - 7 * 24 * 60 * 60) then
                -- Plan needs reset
                self:ResetWeeklyPlans()
                return -- Only reset once
            end
        end
    end
end

-- ============================================================================
-- CRUD OPERATIONS
-- ============================================================================

--[[
    Add a new plan
    @param planType string - Type of plan (mount, pet, toy, recipe)
    @param data table - Plan data { itemID, mountID/petID/recipeID, name, icon, source }
    @return number - New plan ID
]]
function WarbandNexus:AddPlan(planType, data)
    if not self.db.global.plans then
        self.db.global.plans = {}
    end
    
    -- Generate unique ID
    local planID = self.db.global.plansNextID or 1
    self.db.global.plansNextID = planID + 1
    
    local plan = {
        id = planID,
        type = planType,
        itemID = data.itemID,
        name = data.name or "Unknown",
        icon = data.icon,
        source = data.source or "Unknown",
        addedAt = time(),
        notes = data.notes or "",
        
        -- Type-specific IDs
        mountID = data.mountID,
        petID = data.petID,
        speciesID = data.speciesID,
        recipeID = data.recipeID,
        achievementID = data.achievementID,
        illusionID = data.illusionID,
        titleID = data.titleID,
        
        -- For recipes: store reagent requirements
        reagents = data.reagents,
        
        -- For achievements: store reward text
        rewardText = data.rewardText,
    }
    
    table.insert(self.db.global.plans, plan)
    
    -- Notify
    self:Print("|cff00ff00Added plan:|r " .. plan.name)
    
    return planID
end

--[[
    Remove a plan by ID
    @param planID number - Plan ID to remove
    @return boolean - Success
]]
function WarbandNexus:RemovePlan(planID)
    -- Check regular plans
    if self.db.global.plans then
        for i, plan in ipairs(self.db.global.plans) do
            if plan.id == planID then
                local name = plan.name
                table.remove(self.db.global.plans, i)
                self:Print("|cffff6600Removed plan:|r " .. name)
                return true
            end
        end
    end
    
    -- Check custom plans
    if self.db.global.customPlans then
        for i, plan in ipairs(self.db.global.customPlans) do
            if plan.id == planID then
                local name = plan.name
                table.remove(self.db.global.customPlans, i)
                self:Print("|cffff6600Removed custom plan:|r " .. name)
                return true
            end
        end
    end
    
    return false
end

--[[
    Remove all completed plans
    @return number - Count of removed plans
]]
function WarbandNexus:ResetCompletedPlans()
    local removedCount = 0
    
    -- Remove completed regular plans (collected mounts/pets/toys)
    if self.db.global.plans then
        local i = 1
        while i <= #self.db.global.plans do
            local plan = self.db.global.plans[i]
            local progress = self:CheckPlanProgress(plan)
            
            if progress and progress.collected then
                table.remove(self.db.global.plans, i)
                removedCount = removedCount + 1
            else
                i = i + 1
            end
        end
    end
    
    -- Remove completed custom plans
    if self.db.global.customPlans then
        local i = 1
        while i <= #self.db.global.customPlans do
            local plan = self.db.global.customPlans[i]
            
            if plan.completed then
                table.remove(self.db.global.customPlans, i)
                removedCount = removedCount + 1
            else
                i = i + 1
            end
        end
    end
    
    return removedCount
end

--[[
    Get all active plans
    @param planType string (optional) - Filter by type
    @return table - Array of plans
]]
function WarbandNexus:GetActivePlans(planType)
    local allPlans = {}
    
    -- Add regular plans
    if self.db.global.plans then
        for _, plan in ipairs(self.db.global.plans) do
            table.insert(allPlans, plan)
        end
    end
    
    -- Add custom plans
    if self.db.global.customPlans then
        for _, plan in ipairs(self.db.global.customPlans) do
            table.insert(allPlans, plan)
        end
    end
    
    if not planType then
        return allPlans
    end
    
    -- Filter by type
    local filtered = {}
    for _, plan in ipairs(allPlans) do
        if plan.type == planType then
            table.insert(filtered, plan)
        end
    end
    
    return filtered
end

--[[
    Get a specific plan by ID
    @param planID number - Plan ID
    @return table|nil - Plan data or nil
]]
function WarbandNexus:GetPlanByID(planID)
    if not self.db.global.plans then return nil end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.id == planID then
            return plan
        end
    end
    
    return nil
end

--[[
    Update plan notes
    @param planID number - Plan ID
    @param notes string - New notes
    @return boolean - Success
]]
function WarbandNexus:UpdatePlanNotes(planID, notes)
    local plan = self:GetPlanByID(planID)
    if plan then
        plan.notes = notes
        return true
    end
    return false
end

--[[
    Check if item is already in plans
    @param planType string - Type of plan
    @param itemID number - Item ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsItemPlanned(planType, itemID)
    if not self.db.global.plans then return false end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == planType and plan.itemID == itemID then
            return true
        end
    end
    
    return false
end

--[[
    Check if mount is already in plans
    @param mountID number - Mount ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsMountPlanned(mountID)
    if not self.db.global.plans then return false end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == PLAN_TYPES.MOUNT and plan.mountID == mountID then
            return true
        end
    end
    
    return false
end

--[[
    Check if pet species is already in plans
    @param speciesID number - Pet species ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsPetPlanned(speciesID)
    if not self.db.global.plans then return false end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == PLAN_TYPES.PET and plan.speciesID == speciesID then
            return true
        end
    end
    
    return false
end

--[[
    Check if achievement is already in plans
    @param achievementID number - Achievement ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsAchievementPlanned(achievementID)
    if not self.db.global.plans then return false end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == PLAN_TYPES.ACHIEVEMENT and plan.achievementID == achievementID then
            return true
        end
    end
    
    return false
end

--[[
    Check if illusion is already in plans
    @param illusionID number - Illusion sourceID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsIllusionPlanned(illusionID)
    if not self.db.global.plans then return false end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == PLAN_TYPES.ILLUSION and (plan.illusionID == illusionID or plan.sourceID == illusionID) then
            return true
        end
    end
    
    return false
end

--[[
    Check if title is already in plans
    @param titleID number - Title ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsTitlePlanned(titleID)
    if not self.db.global.plans then return false end
    
    for _, plan in ipairs(self.db.global.plans) do
        if plan.type == PLAN_TYPES.TITLE and plan.titleID == titleID then
            return true
        end
    end
    
    return false
end


-- ============================================================================
-- COLLECTION DATA FETCHERS
-- ============================================================================

-- ============================================================================
-- SOURCE TEXT KEYWORDS
-- Comprehensive list of all possible source keywords in WoW tooltips
-- ============================================================================
local SOURCE_KEYWORDS = {
    "Vendor:",
    "Sold by:",
    "Drop:",
    "Quest:",
    "Achievement:",
    "Profession:",
    "Crafted:",
    "World Event:",
    "Holiday:",
    "PvP:",
    "Arena:",
    "Rated:",
    "Battleground:",
    "Dungeon:",
    "Raid:",
    "Trading Post:",
    "Treasure:",
    "Discovery:",
    "Contained in:",
    "Reputation:",
    "Faction:",
    "Garrison:",
    "Garrison Building:",  -- WoD garrison building rewards
    "Pet Battle:",
    "Zone:",
    "Store:",
    "Order Hall:",
    "Covenant:",
    "Renown:",
    "Friendship:",
    "Paragon:",
    "Mission:",
    "Expansion:",
    "Scenario:",
    "Class Hall:",
    "Campaign:",
    "Event:",
    "Promotion:",  -- Promotional items
    "Special:",  -- Special events/rewards
    "Brawler's Guild:",  -- Brawler's Guild rewards
    "Challenge Mode:",  -- Challenge Mode rewards (legacy)
    "Mythic+:",  -- Mythic+ rewards
    "Timewalking:",  -- Timewalking vendor rewards
    "Island Expedition:",  -- BfA Island Expeditions
    "Warfront:",  -- BfA Warfronts
    "Torghast:",  -- Shadowlands Torghast
    "Zereth Mortis:",  -- Shadowlands zone-specific
    "Puzzle:",  -- Secret puzzles
    "Hidden:",  -- Hidden secrets
    "Rare:",  -- Rare mob drops
    "World Boss:",  -- World boss drops
}

-- Helper function to check if text contains any source keyword
local function HasSourceKeyword(text)
    if not text then return false end
    for _, keyword in ipairs(SOURCE_KEYWORDS) do
        if text:match(keyword) then
            return true
        end
    end
    return false
end

-- ============================================================================
-- API-BASED UNOBTAINABLE SOURCE TYPES
-- WoW API sourceType enum values (from C_MountJournal.GetMountInfoByID)
-- ============================================================================
--[[
    sourceType values:
    1 = Drop (boss drops, mob drops) - OBTAINABLE
    2 = Quest (quest rewards) - OBTAINABLE
    3 = Vendor (purchased from vendor) - OBTAINABLE
    4 = Profession (crafted) - OBTAINABLE
    5 = Instance (dungeon/raid specific) - OBTAINABLE
    6 = Promotion (BlizzCon, Collector's Edition) - NOT OBTAINABLE
    7 = Achievement (achievement rewards) - OBTAINABLE (mostly)
    8 = World Event (seasonal events) - OBTAINABLE
    9 = TCG (Trading Card Game) - NOT OBTAINABLE (discontinued)
    10 = Store (Blizzard Shop) - OBTAINABLE
]]
local UNOBTAINABLE_SOURCE_TYPES = {
    [6] = true,  -- Promotion (BlizzCon, Collector's Edition, etc.)
    [9] = true,  -- TCG (Trading Card Game - discontinued)
}

-- ============================================================================
-- MINIMAL SOURCE TEXT PATTERNS (for items API can't detect)
-- These are vendor items where the CURRENCY is no longer obtainable
-- ============================================================================
local UNOBTAINABLE_SOURCE_PATTERNS = {
    -- Challenge Mode currencies (no longer obtainable)
    "Ancestral Phoenix Egg",     -- MoP CM currency
    "Challenge Conqueror",       -- WoD CM requirement
    
    -- Removed content keywords
    "No longer obtainable",
    "No longer available",
}

-- ============================================================================
-- UNOBTAINABLE MOUNT NAMES (for mounts the API doesn't properly flag)
-- ============================================================================
local UNOBTAINABLE_MOUNT_NAMES = {
    -- MoP Challenge Mode Phoenix mounts (currency no longer obtainable)
    ["Ashen Pandaren Phoenix"] = true,
    ["Crimson Pandaren Phoenix"] = true,
    ["Emerald Pandaren Phoenix"] = true,
    ["Violet Pandaren Phoenix"] = true,
    
    -- WoD Challenge Mode mounts
    ["Ironside Warwolf"] = true,
    ["Challenger's War Yeti"] = true,
    
    -- AQ Opening Event (2006)
    ["Black Qiraji Battle Tank"] = true,
    ["Black Qiraji Resonating Crystal"] = true,
}

-- Check if source text indicates unobtainable
local function IsSourceUnobtainable(source)
    if not source then return false end
    for _, pattern in ipairs(UNOBTAINABLE_SOURCE_PATTERNS) do
        if source:find(pattern) then
            return true
        end
    end
    return false
end

-- Check if mount name is in unobtainable list
local function IsMountNameUnobtainable(name)
    return name and UNOBTAINABLE_MOUNT_NAMES[name]
end

-- ============================================================================
-- CURRENCY AFFORDABILITY CHECK
-- Uses stored currency data from db.global.currencies
-- ============================================================================

-- Strip all WoW escape sequences from text for clean parsing
local function StripAllEscapes(text)
    if not text then return "" end
    local result = text
    -- Remove |T...|t texture tags (be careful with pattern)
    result = result:gsub("|T.-|t", "")
    -- Remove |c color codes and |r reset
    result = result:gsub("|c%x%x%x%x%x%x%x%x", "")
    result = result:gsub("|r", "")
    return result
end

-- Find currency by name in stored db.global.currencies
local function FindCurrencyByName(currencyName)
    if not currencyName or currencyName == "" then return nil, nil end
    
    local db = WarbandNexus.db
    if not db or not db.global or not db.global.currencies then return nil, nil end
    
    local lowerName = currencyName:lower():gsub("^%s+", ""):gsub("%s+$", "")
    
    -- Search through stored currencies
    for currencyID, currData in pairs(db.global.currencies) do
        if currData.name then
            local storedLower = currData.name:lower()
            -- Exact match
            if storedLower == lowerName then
                return currencyID, currData
            end
            -- Partial match
            if storedLower:find(lowerName, 1, true) or lowerName:find(storedLower, 1, true) then
                return currencyID, currData
            end
        end
    end
    
    return nil, nil
end

-- Get player's current currency amount from stored data or real-time API
local function GetPlayerCurrencyAmount(currencyID)
    if not currencyID then return 0 end
    
    -- Try real-time API first
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.quantity then
            return info.quantity
        end
    end
    
    -- Fallback to stored data
    local db = WarbandNexus.db
    if not db or not db.global or not db.global.currencies then return 0 end
    
    local currData = db.global.currencies[currencyID]
    if not currData then return 0 end
    
    if currData.isAccountWide then
        return currData.value or 0
    else
        local charKey = UnitName("player") .. "-" .. GetRealmName()
        return currData.chars and currData.chars[charKey] or 0
    end
end

-- Common currency mappings for mounts, pets, toys (currency ID -> info)
-- These help identify currencies when only icons are shown in source text
local COMMON_CURRENCIES = {
    -- Timewarped Badge (ID: 1166)
    [1166] = { name = "Timewarped Badge", iconPattern = "timewarp" },
    -- Champion's Seal (ID: 241)
    [241] = { name = "Champion's Seal", iconPattern = "champion" },
    -- Mark of Honor (ID: 1792) 
    [1792] = { name = "Mark of Honor", iconPattern = "honor" },
    -- Polished Pet Charm (ID: 2032)
    [2032] = { name = "Polished Pet Charm", iconPattern = "charm" },
    -- Shiny Pet Charm (ID: 2003) - older pet charm
    [2003] = { name = "Shiny Pet Charm", iconPattern = "shiny" },
    -- Curious Coin (ID: 1275)
    [1275] = { name = "Curious Coin", iconPattern = "curious" },
    -- Darkmoon Prize Ticket (ID: 515)
    [515] = { name = "Darkmoon Prize Ticket", iconPattern = "darkmoon" },
    -- Seafarer's Dubloon (ID: 1710)
    [1710] = { name = "Seafarer's Dubloon", iconPattern = "dubloon" },
    -- Trader's Tender (ID: 2588) - Trading Post
    [2588] = { name = "Trader's Tender", iconPattern = "tender" },
    -- Bloody Tokens (ID: 2123) - War Mode
    [2123] = { name = "Bloody Tokens", iconPattern = "bloody" },
    -- Conquest (ID: 1602)
    [1602] = { name = "Conquest", iconPattern = "conquest" },
    -- Honor (ID: 1792)
    [1792] = { name = "Honor", iconPattern = "honor" },
    -- Renown currencies - TWW
    [2815] = { name = "Resonance Crystals", iconPattern = "resonance" },
    [2803] = { name = "Valorstones", iconPattern = "valorstone" },
    -- TWW Currencies
    [3056] = { name = "Kej", iconPattern = "kej" },
    [2245] = { name = "Flightstones", iconPattern = "flightstone" },
    -- Legacy currencies
    [1580] = { name = "Seal of Wartorn Fate", iconPattern = "seal" },
    [1553] = { name = "Azerite", iconPattern = "azerite" },
    -- Stygia
    [1767] = { name = "Stygia", iconPattern = "stygia" },
    -- Grateful Offering
    [1885] = { name = "Grateful Offering", iconPattern = "grateful" },
}

-- ============================================================================
-- VENDOR/ZONE TO CURRENCY MAPPING
-- Maps known vendors and zones to their currencies for identification
-- ============================================================================
local VENDOR_CURRENCY_MAP = {
    -- Argent Tournament (Icecrown) - Champion's Seal
    ["dame evniki kapsalis"] = 241,
    ["argent tournament"] = 241,
    ["icecrown"] = 241,  -- Zone hint
    
    -- Darkmoon Faire
    ["lhara"] = 515,
    ["darkmoon"] = 515,
    
    -- TWW / Undermine - Kej
    ["undermine"] = 3056,
    ["boatswain hardee"] = 3056,
    ["rocco razzboom"] = 3056,
    ["ando the gat"] = 3056,
    
    -- Timewalking vendors
    ["cupri"] = 1166,  -- Timewarped Badge vendor
    ["auzin"] = 1166,
    
    -- Brawler's Guild - Gold (handled separately)
    ["brawl'gar arena"] = 0,  -- 0 = Gold
    ["bizmo's brawlpub"] = 0,
    
    -- PvP vendors
    ["mark of honor"] = 1792,
    ["bloody coins"] = 2123,
    
    -- Nazmir (Gold)
    ["nazmir"] = 0,
    
    -- Korthia - Stygia or Grateful Offering
    ["korthia"] = 1767,
    ["archivist"] = 1931,  -- Cataloged Research
    
    -- Zereth Mortis - Cosmic Flux
    ["zereth mortis"] = 2009,
    
    -- Dragon Isles
    ["valdrakken"] = 2003,  -- Dragon Isles Supplies
    
    -- The Mad Merchant - Gold (very expensive)
    ["mad merchant"] = 0,
}

-- Helper to identify currency from vendor/zone in source text
local function IdentifyCurrencyFromVendorZone(source)
    if not source then return nil end
    local lowerSource = source:lower()
    
    for pattern, currencyID in pairs(VENDOR_CURRENCY_MAP) do
        if lowerSource:find(pattern, 1, true) then
            if currencyID == 0 then
                return nil, "Gold"  -- Special case for gold
            end
            return currencyID, nil
        end
    end
    
    return nil, nil
end

-- ============================================================================
-- TEXTURE ID TO CURRENCY ID MAPPING
-- Maps icon texture IDs to currency IDs for identifying currencies from source text
-- Texture IDs are extracted from |T<textureID>:<size>|t patterns in source text
-- ============================================================================
local CURRENCY_TEXTURE_MAP = {
    -- Shadowlands currencies
    [3743738] = 1767,   -- Stygia
    [3726260] = 1885,   -- Grateful Offering
    [3546972] = 1813,   -- Reservoir Anima
    [3528288] = 1810,   -- Redeemed Soul
    [3743739] = 1816,   -- Sinstone Fragments
    [3853118] = 1820,   -- Infused Ruby
    [4238797] = 1931,   -- Cataloged Research
    [4217590] = 1904,   -- Tower Knowledge
    [4392588] = 2009,   -- Cosmic Flux
    [4526445] = 1979,   -- Cyphers of the First Ones
    
    -- Dragonflight currencies
    [4638724] = 2003,   -- Dragon Isles Supplies
    [4643977] = 2118,   -- Elemental Overflow
    [4615608] = 1980,   -- Sandworn Relic (ZM)
    [5055977] = 2650,   -- Emerald Dewdrop
    [5003559] = 2594,   -- Paracausal Flakes
    [5061535] = 2657,   -- Mysterious Fragment
    [5003558] = 2593,   -- Undercoin
    
    -- TWW / War Within currencies
    [5872034] = 2815,   -- Resonance Crystals
    [5453417] = 2803,   -- Valorstones
    [5872033] = 2812,   -- Weathered Harbinger Crest
    [5872032] = 2809,   -- Carved Harbinger Crest
    [5872031] = 2806,   -- Runed Harbinger Crest
    [5872030] = 2807,   -- Gilded Harbinger Crest
    [5915096] = 3056,   -- Kej
    [6011623] = 3008,   -- Valorstone Shard
    
    -- PvP currencies
    [1339999] = 1792,   -- Honor
    [135884] = 1602,    -- Conquest
    [1585421] = 2123,   -- Bloody Tokens
    
    -- Pet charms
    [413584] = 2032,    -- Polished Pet Charm
    [2004597] = 2032,   -- Polished Pet Charm (alternate)
    [1380145] = 1885,   -- Shiny Pet Charm (older icon)
    
    -- Legacy/Evergreen currencies  
    [463446] = 515,     -- Darkmoon Prize Ticket
    [236396] = 241,     -- Champion's Seal
    [1357486] = 1166,   -- Timewarped Badge
    [463447] = 1275,    -- Curious Coin
    [2004317] = 1710,   -- Seafarer's Dubloon
    [2032600] = 1560,   -- War Resources
    [2565237] = 1755,   -- Coalescing Visions
    [4555658] = 2588,   -- Trader's Tender
    
    -- BfA currencies
    [2065624] = 1565,   -- Rich Azerite Fragment
    [2000853] = 1553,   -- Azerite
    [2032597] = 1580,   -- Seal of Wartorn Fate
    [2910321] = 1803,   -- Echoes of Ny'alotha
    
    -- Legion currencies
    [1397630] = 1342,   -- Legionfall War Supplies
    [1405818] = 1314,   -- Lingering Soul Fragment
    [1417744] = 1533,   -- Wakening Essence
    [132775] = 1149,    -- Sightless Eye
    [237201] = 1155,    -- Ancient Mana
    [1377091] = 1273,   -- Seal of Broken Fate
    [1417745] = 1508,   -- Veiled Argunite
    
    -- WoD currencies
    [1005027] = 823,    -- Apexis Crystal
    [970406] = 824,     -- Garrison Resources
    [1131085] = 994,    -- Seal of Tempered Fate
    [1131086] = 1101,   -- Oil
    
    -- MoP/Cata currencies
    [463858] = 395,     -- Justice Points
    [463860] = 396,     -- Valor Points
    [133789] = 402,     -- Ironpaw Token
    [237197] = 777,     -- Timeless Coin
    [463859] = 738,     -- Lesser Charm of Good Fortune
    [654533] = 697,     -- Elder Charm of Good Fortune
}

--[[
    Extract currency ID from texture tag in source text
    Looks for pattern |T<textureID or path>:<size>|t and maps to currency ID
    @param source string - Raw source text containing texture tags
    @return currencyID (number or nil), currencyInfo (table or nil)
]]
local function ExtractCurrencyFromTexture(source)
    if not source then return nil, nil end
    
    -- METHOD 1: Try numeric texture IDs first: |T1234567:0|t
    for textureID in source:gmatch("|T(%d+)[:|]") do
        local texID = tonumber(textureID)
        if texID then
            -- Check static texture map first
            local currencyID = CURRENCY_TEXTURE_MAP[texID]
            if currencyID then
                -- Get currency info from API
                if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                    local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                    if info then
                        return currencyID, {
                            name = info.name,
                            quantity = info.quantity or 0,
                            iconFileID = info.iconFileID,
                            maxQuantity = info.maxQuantity,
                        }
                    end
                end
                -- Return just the ID if API call fails
                return currencyID, nil
            end
            
            -- Fallback: check stored currencies in db for matching icon
            local db = WarbandNexus.db
            if db and db.global and db.global.currencies then
                for storedCurrID, currData in pairs(db.global.currencies) do
                    if currData.iconFileID and currData.iconFileID == texID then
                        return storedCurrID, currData
                    end
                end
            end
        end
    end
    
    -- METHOD 2: Handle file path textures: |TInterface\ICONS\filename.blp:0|t
    -- Extract filename and try to match against known patterns
    for texturePath in source:gmatch("|T([^:|]+)[:|]") do
        -- Skip if it's just a number (already handled above)
        if not texturePath:match("^%d+$") then
            local fileName = texturePath:match("([^\\]+)%.%w+$")  -- Extract filename without extension
            if fileName then
                fileName = fileName:upper()  -- Normalize to uppercase
                
                -- Check against stored currencies' icon names
                local db = WarbandNexus.db
                if db and db.global and db.global.currencies then
                    for storedCurrID, currData in pairs(db.global.currencies) do
                        if currData.icon and currData.icon:upper():find(fileName, 1, true) then
                            return storedCurrID, currData
                        end
                    end
                end
                
                -- Try to get currency info using C_CurrencyInfo by iterating known currencies
                if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
                    -- Check our common currencies list
                    for currencyID, currInfo in pairs(COMMON_CURRENCIES) do
                        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
                        if info and info.iconFileID then
                            -- Get icon path from fileID and compare
                            -- This is a fallback, may not always work perfectly
                            return currencyID, {
                                name = info.name,
                                quantity = info.quantity or 0,
                                iconFileID = info.iconFileID,
                                maxQuantity = info.maxQuantity,
                            }
                        end
                    end
                end
            end
        end
    end
    
    return nil, nil
end

--[[
    Get uncollected mounts with source info
    Uses WoW API fully:
    - C_MountJournal.GetMountIDs() - Get all mount IDs
    - C_MountJournal.GetMountInfoByID() - Get mount info including shouldHideOnChar
    - C_MountJournal.GetMountInfoExtraByID() - Get source text
    
    @param searchText string (optional) - Filter by name
    @param limit number (optional) - Max results
    @return table - Array of mount data
]]
function WarbandNexus:GetUncollectedMounts(searchText, limit)
    local mounts = {}
    local count = 0
    limit = limit or 50  -- Default to 50 results
    
    if not C_MountJournal then return mounts end
    
    -- Use GetMountIDs() to get ALL mount IDs (not filtered by journal settings)
    local mountIDs = C_MountJournal.GetMountIDs()
    if not mountIDs then return mounts end
    
    local playerGold = GetMoney()
    local seenMounts = {}  -- Track seen mount IDs to prevent duplicates
    
    for _, mountID in ipairs(mountIDs) do
        if count >= limit then break end
        
        -- Skip duplicates
        if seenMounts[mountID] then
            -- Already processed this mount
        else
            seenMounts[mountID] = true
            
            -- Get FULL mount info from API (all return values)
            -- Returns: name, spellID, icon, isActive, isUsable, sourceType, isFavorite, 
            --          isFactionSpecific, faction, shouldHideOnChar, isCollected, mountID, isSteadyFlight
            local name, spellID, icon, isActive, isUsable, sourceType, isFavorite, 
                  isFactionSpecific, faction, shouldHideOnChar, isCollected = 
                  C_MountJournal.GetMountInfoByID(mountID)
            
            -- FILTER 1: Skip if already collected
            if isCollected then
                -- Skip collected mounts
            -- FILTER 2: Skip if should be hidden from this character (faction/class/race specific)
            elseif shouldHideOnChar then
                -- Skip mounts not available to this character
            -- FILTER 3: Skip if unobtainable source type (Promotion=6, TCG=9)
            elseif sourceType and UNOBTAINABLE_SOURCE_TYPES[sourceType] then
                -- Skip promotional and TCG mounts
            -- FILTER 4: Skip if mount name is in unobtainable list (CM, AQ event, etc.)
            elseif IsMountNameUnobtainable(name) then
                -- Skip known unobtainable mounts by name
            elseif name then
                -- Get extra info including source text
                local creatureDisplayID, description, source = C_MountJournal.GetMountInfoExtraByID(mountID)
                
                -- FILTER 5: Skip if source text indicates unobtainable currency/content
                if IsSourceUnobtainable(source) then
                    -- Skip mounts with unobtainable currency requirements
                -- Check search filter
                elseif not searchText or searchText == "" or name:lower():find(searchText:lower(), 1, true) then
                    table.insert(mounts, {
                        mountID = mountID,
                        name = name,
                        icon = icon,
                        spellID = spellID,
                        source = source or "Unknown",
                        sourceType = sourceType,
                        description = description,
                        isPlanned = self:IsMountPlanned(mountID),
                        faction = faction,
                        isFactionSpecific = isFactionSpecific,
                    })
                    count = count + 1
                end
            end
        end
    end
    
    -- Sort by name
    table.sort(mounts, function(a, b) return a.name < b.name end)
    
    return mounts
end

--[[
    Get uncollected pets with source info
    @param searchText string (optional) - Filter by name
    @param limit number (optional) - Max results
    @return table - Array of pet data
]]
function WarbandNexus:GetUncollectedPets(searchText, limit)
    local pets = {}
    local count = 0
    limit = limit or 50  -- Default to 50 results
    
    if not C_PetJournal then return pets end
    
    local playerGold = GetMoney()
    local seenPets = {}  -- Track seen species to prevent duplicates
    
    -- Save current filter state
    local savedSourceFilters = {}
    local savedTypeFilters = {}
    local savedCollected, savedUncollected
    
    -- Save source filters
    local numSources = C_PetJournal.GetNumPetSources and C_PetJournal.GetNumPetSources() or 10
    for i = 1, numSources do
        if C_PetJournal.IsPetSourceChecked then
            savedSourceFilters[i] = C_PetJournal.IsPetSourceChecked(i)
        end
    end
    
    -- Save type filters
    local numTypes = C_PetJournal.GetNumPetTypes and C_PetJournal.GetNumPetTypes() or 10
    for i = 1, numTypes do
        if C_PetJournal.IsPetTypeChecked then
            savedTypeFilters[i] = C_PetJournal.IsPetTypeChecked(i)
        end
    end
    
    -- Save collected/uncollected filter
    if C_PetJournal.IsFilterChecked then
        savedCollected = C_PetJournal.IsFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED)
        savedUncollected = C_PetJournal.IsFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED)
    end
    
    -- Clear all filters to show all pets
    for i = 1, numSources do
        if C_PetJournal.SetPetSourceChecked then
            C_PetJournal.SetPetSourceChecked(i, true)
        end
    end
    
    for i = 1, numTypes do
        if C_PetJournal.SetPetTypeFilter then
            C_PetJournal.SetPetTypeFilter(i, true)
        end
    end
    
    -- Show only uncollected
    if C_PetJournal.SetFilterChecked then
        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, false)
        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
    end
    
    -- Clear search
    if C_PetJournal.SetSearchFilter then
        C_PetJournal.SetSearchFilter("")
    end
    
    -- Now fetch pets with cleared filters
    local numPets = C_PetJournal.GetNumPets()
    
    for i = 1, numPets do
        if count >= limit then break end
        
        local petID, speciesID, owned, _, _, _, _, speciesName, icon, _, _, sourceText = C_PetJournal.GetPetInfoByIndex(i)
        
        if not owned and speciesID and speciesName then
            -- Skip duplicates
            if not seenPets[speciesID] then
                seenPets[speciesID] = true
                
                -- Skip promotional pets and unobtainable source patterns
                local isUnobtainable = sourceText and (
                    sourceText:find("Promotion") or 
                    sourceText:find("TCG") or 
                    sourceText:find("Trading Card") or
                    sourceText:find("BlizzCon") or
                    sourceText:find("Collector's Edition") or
                    IsSourceUnobtainable(sourceText)
                )
                
                if not isUnobtainable then
                    -- Check search filter (our own search)
                    if not searchText or searchText == "" or speciesName:lower():find(searchText:lower(), 1, true) then
                        table.insert(pets, {
                            speciesID = speciesID,
                            name = speciesName,
                            icon = icon,
                            source = sourceText or "Unknown",
                            isPlanned = self:IsPetPlanned(speciesID),
                        })
                        count = count + 1
                    end
                end
            end
        end
    end
    
    -- Restore original filters
    for i, checked in pairs(savedSourceFilters) do
        if C_PetJournal.SetPetSourceChecked then
            C_PetJournal.SetPetSourceChecked(i, checked)
        end
    end
    
    for i, checked in pairs(savedTypeFilters) do
        if C_PetJournal.SetPetTypeFilter then
            C_PetJournal.SetPetTypeFilter(i, checked)
        end
    end
    
    if C_PetJournal.SetFilterChecked and savedCollected ~= nil then
        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, savedCollected)
        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, savedUncollected)
    end
    
    -- Sort by name
    table.sort(pets, function(a, b) return a.name < b.name end)
    
    return pets
end

--[[
    Get uncollected toys with source info
    @param searchText string (optional) - Filter by name
    @param limit number (optional) - Max results
    @return table - Array of toy data
]]
function WarbandNexus:GetUncollectedToys(searchText, limit)
    local toys = {}
    local count = 0
    limit = limit or 50  -- Default to 50 results
    
    if not C_ToyBox then return toys end
    
    local playerGold = GetMoney()
    local seenToys = {}  -- Track seen toys to prevent duplicates
    
    -- Save current filter state
    local savedCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
    local savedUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
    local savedFilterString = C_ToyBox.GetFilterString and C_ToyBox.GetFilterString() or ""
    
    -- Clear filters to show all uncollected toys
    if C_ToyBox.SetCollectedShown then
        C_ToyBox.SetCollectedShown(false)
    end
    if C_ToyBox.SetUncollectedShown then
        C_ToyBox.SetUncollectedShown(true)
    end
    if C_ToyBox.SetAllSourceTypeFilters then
        C_ToyBox.SetAllSourceTypeFilters(true)
    end
    if C_ToyBox.SetFilterString then
        C_ToyBox.SetFilterString("")
    end
    
    -- Use filtered count after our filters
    local numToys = C_ToyBox.GetNumFilteredToys and C_ToyBox.GetNumFilteredToys() or C_ToyBox.GetNumToys()
    
    for i = 1, numToys do
        if count >= limit then break end
        
        local itemID = C_ToyBox.GetToyFromIndex(i)
        if itemID and not seenToys[itemID] then
            seenToys[itemID] = true
            
            local toyID, toyName, icon, isFavorite, hasFanfare, itemQuality = C_ToyBox.GetToyInfo(itemID)
            
            if toyID and toyName and not PlayerHasToy(toyID) then
                -- Get toy source information using C_TooltipInfo API (modern WoW API)
                local source = nil
                
                -- Use C_TooltipInfo to get structured tooltip data (works for all toys)
                if C_TooltipInfo and C_TooltipInfo.GetToyByItemID then
                    local tooltipData = C_TooltipInfo.GetToyByItemID(itemID)
                    
                    if tooltipData and tooltipData.lines then
                        -- Iterate through tooltip lines and collect source information
                        for i, line in ipairs(tooltipData.lines) do
                            if line.leftText then
                                local text = line.leftText
                                -- Check if this line contains source info keywords
                                if HasSourceKeyword(text) then
                                    -- Exclude "Use:" and "Cost:" lines
                                    if not text:match("^Use:") and not text:match("^Cost:") and text ~= toyName then
                                        if not source then
                                            source = text
                                        else
                                            -- Append new line if it's different content
                                            if not source:find(text, 1, true) then
                                                source = source .. "\n" .. text
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- Fallback 1: Try getting item tooltip instead of toy tooltip (some toys have better item info)
                if not source or source == "" then
                    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
                        local itemTooltipData = C_TooltipInfo.GetItemByID(itemID)
                        
                        if itemTooltipData and itemTooltipData.lines then
                            for i, line in ipairs(itemTooltipData.lines) do
                                if line.leftText then
                                    local text = line.leftText
                                    -- Check if this line contains source info keywords
                                    if HasSourceKeyword(text) then
                                        if not text:match("^Use:") and not text:match("^Cost:") and text ~= toyName then
                                            if not source then
                                                source = text
                                            else
                                                if not source:find(text, 1, true) then
                                                    source = source .. "\n" .. text
                                                end
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                
                -- Fallback 2: Use old tooltip scanning method if C_TooltipInfo didn't work
                if not source or source == "" then
                    -- Create hidden tooltip
                    if not _G["WarbandNexusToyTooltip"] then
                        local tt = CreateFrame("GameTooltip", "WarbandNexusToyTooltip", UIParent, "GameTooltipTemplate")
                        tt:SetOwner(UIParent, "ANCHOR_NONE")
                    end
                    
                    local tooltip = _G["WarbandNexusToyTooltip"]
                    tooltip:ClearLines()
                    tooltip:SetToyByItemID(itemID)
                    
                    -- Scan all tooltip lines
                    for i = 1, tooltip:NumLines() do
                        local line = _G["WarbandNexusToyTooltipTextLeft" .. i]
                        if line then
                            local text = line:GetText()
                            if text and text ~= "" then
                                local r, g, b = line:GetTextColor()
                                
                                -- White or yellow text with source keywords
                                local isWhiteOrYellow = (r > 0.9 and g > 0.9 and b > 0.9) or (r > 0.9 and g > 0.7 and b < 0.2)
                                
                                if isWhiteOrYellow and HasSourceKeyword(text) and not text:match("^Use:") and text ~= toyName then
                                    if not source then
                                        source = text
                                    else
                                        if not source:find(text, 1, true) then
                                            source = source .. "\n" .. text
                                        end
                                    end
                                end
                            end
                        end
                    end
                    
                    tooltip:Hide()
                end
                
                -- Default if still nothing
                if not source or source == "" then
                    source = "Unknown source"
                end
                
                -- Skip promotional toys and unobtainable source patterns
                local isUnobtainable = source and (
                    source:find("Promotion") or 
                    source:find("TCG") or 
                    source:find("Trading Card") or
                    source:find("BlizzCon") or
                    source:find("Collector's Edition") or
                    IsSourceUnobtainable(source)
                )
                
                if not isUnobtainable then
                    -- Check search filter (our own search)
                    if not searchText or searchText == "" or toyName:lower():find(searchText:lower(), 1, true) then
                        table.insert(toys, {
                            itemID = itemID,
                            toyID = toyID,
                            name = toyName,
                            icon = icon,
                            source = source,
                            quality = itemQuality,
                            isPlanned = self:IsItemPlanned(PLAN_TYPES.TOY, itemID),
                        })
                        count = count + 1
                    end
                end
            end
        end
    end
    
    -- Restore original filters
    if C_ToyBox.SetCollectedShown and savedCollected ~= nil then
        C_ToyBox.SetCollectedShown(savedCollected)
    end
    if C_ToyBox.SetUncollectedShown and savedUncollected ~= nil then
        C_ToyBox.SetUncollectedShown(savedUncollected)
    end
    if C_ToyBox.SetFilterString then
        C_ToyBox.SetFilterString(savedFilterString)
    end
    
    -- Sort by name
    table.sort(toys, function(a, b) return a.name < b.name end)
    
    return toys
end

--[[
    Get uncollected achievements with info
    @param searchText string (optional) - Filter by name
    @param limit number (optional) - Max results
    @return table - Array of achievement data
]]
function WarbandNexus:GetUncollectedAchievements(searchText, limit)
    local achievements = {}
    local count = 0
    limit = limit or 50  -- Default to 50 results
    
    local seenAchievements = {}  -- Track seen achievement IDs to prevent duplicates
    
    -- Get all achievement categories
    local categories = GetCategoryList()
    if not categories then return achievements end
    
    -- Iterate through all categories and their achievements
    for _, categoryID in ipairs(categories) do
        if count >= limit then break end
        
        -- Get number of achievements in this category
        local total, completed, incompleted = GetCategoryNumAchievements(categoryID)
        
        if total and total > 0 then
            -- Iterate through achievements in this category
            for i = 1, total do
                if count >= limit then break end
                
                local achievementID, name, points, completed, month, day, year, description, flags, icon, rewardText, isGuild, wasEarnedByMe, earnedBy = GetAchievementInfo(categoryID, i)
                
                if achievementID and name and not seenAchievements[achievementID] then
                    seenAchievements[achievementID] = true
                    
                    -- FILTER 1: Skip if already completed
                    if completed then
                        -- Skip completed achievements
                    -- FILTER 2: Skip guild achievements (unless you want them)
                    elseif isGuild then
                        -- Skip guild achievements
                    -- FILTER 3: Skip Feats of Strength (flags & 0x00008 == hidden from UI)
                    elseif flags and bit.band(flags, 0x00010000) > 0 then
                        -- Skip Feats of Strength category
                    else
                        -- Get the link for the achievement
                        local achievementLink = GetAchievementLink(achievementID)
                        
                        -- Build source text from description and criteria
                        local source = description or ""
                        
                        -- Add criteria count if available
                        local numCriteria = GetAchievementNumCriteria(achievementID)
                        if numCriteria and numCriteria > 0 then
                            local completedCriteria = 0
                            for criteriaIndex = 1, numCriteria do
                                local criteriaString, criteriaType, criteriaCompleted = GetAchievementCriteriaInfo(achievementID, criteriaIndex)
                                if criteriaCompleted then
                                    completedCriteria = completedCriteria + 1
                                end
                            end
                            source = string.format("Progress: %d/%d criteria", completedCriteria, numCriteria)
                            if description and description ~= "" then
                                source = description .. "\n" .. source
                            end
                        end
                        
                        -- Check search filter
                        if not searchText or searchText == "" or name:lower():find(searchText:lower(), 1, true) then
                            table.insert(achievements, {
                                achievementID = achievementID,
                                name = name,
                                icon = icon,
                                points = points or 0,
                                description = description or "",
                                source = source,
                                rewardText = rewardText,
                                categoryID = categoryID,
                                link = achievementLink,
                                isPlanned = self:IsAchievementPlanned(achievementID),
                                numCriteria = numCriteria,
                            })
                            count = count + 1
                        end
                    end
                end
            end
        end
        
        -- Also check subcategories recursively
        -- Note: WoW's achievement system has nested categories, but GetCategoryList() already returns flattened list
    end
    
    -- Sort by name
    table.sort(achievements, function(a, b) return a.name < b.name end)
    
    return achievements
end

-- ============================================================================
-- ILLUSION DATA FETCHERS
-- ============================================================================

--[[
    Get uncollected illusions (weapon enchant appearances)
    @param searchText string (optional) - Filter by name
    @param limit number (optional) - Max results (default 50)
    @return table - Array of illusion data
]]
function WarbandNexus:GetUncollectedIllusions(searchText, limit)
    local illusions = {}
    local count = 0
    limit = limit or 50
    
    if not C_TransmogCollection then 
        return illusions 
    end
    
    local illusionList = C_TransmogCollection.GetIllusions()
    if not illusionList then return illusions end
    
    for _, illusionInfo in ipairs(illusionList) do
        if count >= limit then break end
        
        -- Only show uncollected
        if illusionInfo and illusionInfo.isCollected ~= true then
            local visualID = illusionInfo.visualID
            local illusionIcon = illusionInfo.icon
            local sourceID = illusionInfo.sourceID
            
            -- Get detailed info using sourceID (not visualID)
            local detailedInfo = C_TransmogCollection.GetIllusionInfo(sourceID)
            local illusionName = nil
            local sourceText = "Illusion"
            
            if detailedInfo then
                local name, hyperlink, source = C_TransmogCollection.GetIllusionStrings(sourceID)
                illusionName = name
                sourceText = source or "Illusion"
            end
            
            if illusionName and illusionIcon and sourceID then
                -- Check search filter
                local searchMatch = not searchText or searchText == "" or illusionName:lower():find(searchText:lower(), 1, true)
                
                if searchMatch then
                    local isPlanned = self:IsIllusionPlanned(sourceID)
                    
                    table.insert(illusions, {
                        illusionID = sourceID,
                        visualID = visualID,
                        sourceID = sourceID,
                        name = illusionName,
                        icon = illusionIcon,
                        source = sourceText,
                        isPlanned = isPlanned,
                    })
                    count = count + 1
                end
            end
        end
    end
    
    table.sort(illusions, function(a, b) return a.name < b.name end)
    
    return illusions
end

-- ============================================================================
-- TITLE DATA FETCHERS
-- ============================================================================

--[[
    Get uncollected titles
    @param searchText string (optional) - Filter by name
    @param limit number (optional) - Max results (default 50)
    @return table - Array of title data
]]
function WarbandNexus:GetUncollectedTitles(searchText, limit)
    local titles = {}
    local count = 0
    limit = limit or 50
    
    local numTitles = GetNumTitles()
    if not numTitles or numTitles == 0 then return titles end
    
    for titleIndex = 1, numTitles do
        if count >= limit then break end
        
        local name, playerTitle = GetTitleName(titleIndex)
        local isKnown = IsTitleKnown(titleIndex)
        
        if name and not isKnown then
            local displayName = name
            
            -- Format if playerTitle is a string template
            if type(playerTitle) == "string" and playerTitle:find("%%s") then
                displayName = playerTitle:gsub("%%s", name)
            end
            
            -- Simple source - no expensive achievement scanning
            local sourceText = "Title"
            local titleIcon = "Interface\\Icons\\Achievement_Guildperk_Honorablemention_Rank2"
            
            -- Check search filter
            if not searchText or searchText == "" or displayName:lower():find(searchText:lower(), 1, true) then
                table.insert(titles, {
                    titleID = titleIndex,
                    name = displayName,
                    icon = titleIcon,
                    source = sourceText,
                    isPlanned = self:IsTitlePlanned(titleIndex),
                })
                count = count + 1
            end
        end
    end
    
    table.sort(titles, function(a, b) return a.name < b.name end)
    
    return titles
end

-- ============================================================================
-- RECIPE MATERIAL CHECKER
-- ============================================================================

--[[
    Get recipe schematic (reagents) for a recipe
    @param recipeID number - Recipe ID
    @return table|nil - Array of reagent requirements
]]
function WarbandNexus:GetRecipeReagents(recipeID)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
        return nil
    end
    
    local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false)
    if not schematic or not schematic.reagentSlotSchematics then
        return nil
    end
    
    local reagents = {}
    
    for _, slot in ipairs(schematic.reagentSlotSchematics) do
        if slot.reagents and #slot.reagents > 0 then
            local reagent = slot.reagents[1]  -- Primary reagent
            table.insert(reagents, {
                itemID = reagent.itemID,
                quantity = slot.quantityRequired or 1,
            })
        end
    end
    
    return reagents
end

--[[
    Check materials across warband storage
    @param reagents table - Array of { itemID, quantity }
    @return table - Results with locations and counts
]]
function WarbandNexus:CheckMaterialsAcrossWarband(reagents)
    if not reagents then return {} end
    
    local results = {}
    
    for _, reagent in ipairs(reagents) do
        local itemID = reagent.itemID
        local needed = reagent.quantity
        local found = 0
        local locations = {}
        
        -- Check Warband Bank (V2)
        if self.db.global.warbandBankV2 then
            local wbData = self:DecompressWarbandBank()
            if wbData and wbData.items then
                for bagID, bagData in pairs(wbData.items) do
                    for slotID, item in pairs(bagData) do
                        if item.itemID == itemID then
                            found = found + (item.stackCount or 1)
                            table.insert(locations, {
                                type = "warband",
                                bag = bagID,
                                slot = slotID,
                                count = item.stackCount or 1,
                            })
                        end
                    end
                end
            end
        end
        
        -- Check Personal Banks (V2)
        if self.db.global.personalBanks then
            for charKey, compressedData in pairs(self.db.global.personalBanks) do
                local bankData = self:DecompressPersonalBank(charKey)
                if bankData then
                    for bagID, bagData in pairs(bankData) do
                        for slotID, item in pairs(bagData) do
                            if item.itemID == itemID then
                                found = found + (item.stackCount or 1)
                                table.insert(locations, {
                                    type = "personal",
                                    character = charKey,
                                    bag = bagID,
                                    slot = slotID,
                                    count = item.stackCount or 1,
                                })
                            end
                        end
                    end
                end
            end
        end
        
        -- Check current bags
        for bagID = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            for slot = 1, numSlots do
                local info = C_Container.GetContainerItemInfo(bagID, slot)
                if info and info.itemID == itemID then
                    found = found + (info.stackCount or 1)
                    table.insert(locations, {
                        type = "bags",
                        bag = bagID,
                        slot = slot,
                        count = info.stackCount or 1,
                    })
                end
            end
        end
        
        -- Get item name
        local itemName = C_Item.GetItemNameByID(itemID) or "Item " .. itemID
        local itemIcon = C_Item.GetItemIconByID(itemID)
        
        table.insert(results, {
            itemID = itemID,
            name = itemName,
            icon = itemIcon,
            needed = needed,
            found = found,
            complete = found >= needed,
            locations = locations,
        })
    end
    
    return results
end

--[[
    Find where a specific item is stored
    @param itemID number - Item ID to find
    @return table - Array of locations
]]
function WarbandNexus:FindItemLocations(itemID)
    return self:CheckMaterialsAcrossWarband({{ itemID = itemID, quantity = 1 }})[1]
end

-- ============================================================================
-- PLAN PROGRESS CHECKING
-- ============================================================================

--[[
    Check progress for a plan
    @param plan table - Plan object
    @return table - Progress info
]]
function WarbandNexus:CheckPlanProgress(plan)
    local progress = {
        collected = false,
        canObtain = false,
        details = {},
    }
    
    if plan.type == PLAN_TYPES.MOUNT then
        -- Check if collected
        if plan.mountID and C_MountJournal then
            local name, _, _, _, _, _, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(plan.mountID)
            progress.collected = isCollected
        end
        
    elseif plan.type == PLAN_TYPES.PET then
        -- Check if collected
        if plan.speciesID and C_PetJournal then
            local numOwned = C_PetJournal.GetNumCollectedInfo(plan.speciesID)
            progress.collected = numOwned and numOwned > 0
        end
        
    elseif plan.type == PLAN_TYPES.TOY then
        -- Check if collected
        if plan.itemID then
            progress.collected = PlayerHasToy(plan.itemID)
        end
        
    elseif plan.type == PLAN_TYPES.RECIPE then
        -- Check materials
        if plan.reagents then
            local materialCheck = self:CheckMaterialsAcrossWarband(plan.reagents)
            progress.materials = materialCheck
            
            local allComplete = true
            for _, mat in ipairs(materialCheck) do
                if not mat.complete then
                    allComplete = false
                    break
                end
            end
            progress.canObtain = allComplete
        end
        
    elseif plan.type == PLAN_TYPES.ACHIEVEMENT then
        -- Check if achievement is completed
        if plan.achievementID then
            local _, _, _, completed = GetAchievementInfo(plan.achievementID)
            progress.collected = completed or false
        end
        
    elseif plan.type == PLAN_TYPES.ILLUSION then
        -- Check if illusion is collected
        if plan.illusionID and C_TransmogCollection then
            local illusionList = C_TransmogCollection.GetIllusions()
            if illusionList then
                for _, illusionInfo in ipairs(illusionList) do
                    -- Check both sourceID and illusionID for compatibility
                    if illusionInfo.sourceID == plan.illusionID or illusionInfo.visualID == plan.illusionID then
                        progress.collected = illusionInfo.isCollected or false
                        break
                    end
                end
            end
        end
        
    elseif plan.type == PLAN_TYPES.TITLE then
        -- Check if title is known (use old API)
        if plan.titleID then
            progress.collected = IsTitleKnown(plan.titleID)
        end
        
    elseif plan.type == "custom" then
        -- Custom plans can be manually marked as complete
        progress.collected = plan.completed or false
        progress.canObtain = true
        
    elseif plan.type == "weekly_vault" then
        -- Weekly vault plans never auto-complete (they reset instead)
        progress.collected = false
        progress.progress = plan.progress
        progress.slots = plan.slots
    end
    
    return progress
end

-- ============================================================================
-- MULTI-SOURCE PARSER
-- ============================================================================

--[[
    Strip WoW escape sequences from text for clean display
    Removes texture tags, color codes, hyperlinks
    @param text string - Raw text with escape sequences
    @return string - Clean text
]]
function WarbandNexus:CleanSourceText(text)
    if not text then return "" end
    local result = text
    
    -- Convert WoW newline escape |n to actual newline FIRST
    result = result:gsub("|n", "\n")
    
    -- Remove texture tags: |T...|t
    result = result:gsub("|T.-|t", "")
    -- Remove color codes: |cXXXXXXXX and |r
    result = result:gsub("|c%x%x%x%x%x%x%x%x", "")
    result = result:gsub("|r", "")
    -- Remove hyperlinks: |H...|h and closing |h
    result = result:gsub("|H.-|h", "")
    result = result:gsub("|h", "")
    
    -- Catch-all: remove any remaining |X escape sequences we missed
    result = result:gsub("|%a", "")
    
    -- Clean up extra spaces/tabs (but PRESERVE newlines for parsing)
    result = result:gsub("[ \t]+", " ")
    -- Trim leading/trailing whitespace from each line
    result = result:gsub("^[ \t]+", ""):gsub("[ \t]+$", "")
    result = result:gsub("\n[ \t]+", "\n"):gsub("[ \t]+\n", "\n")
    -- Remove empty lines
    result = result:gsub("\n+", "\n")
    
    return result
end

--[[
    Parse source text to detect multiple vendors/sources
    Some items (like Lightning-Blessed Spire) have multiple vendors in different zones.
    
    @param sourceText string - Raw source text from API
    @return table - Array of parsed source objects
]]
function WarbandNexus:ParseMultipleSources(sourceText)
    local sources = {}
    
    if not sourceText or sourceText == "" then
        return sources
    end
    
    -- Clean the source text first
    sourceText = self:CleanSourceText(sourceText)
    
    -- Split source text by double newlines or repeated "Vendor:" patterns
    -- Pattern: Look for repeated blocks of Vendor/Zone/Cost
    local currentSource = {}
    local hasMultiple = false
    
    -- Check if text contains multiple "Vendor:" entries
    local vendorCount = 0
    for _ in sourceText:gmatch("Vendor:") do
        vendorCount = vendorCount + 1
    end
    hasMultiple = vendorCount > 1
    
    if hasMultiple then
        -- Parse each vendor block
        -- Split by looking for "Vendor:" as delimiter
        local blocks = {}
        local remaining = sourceText
        
        -- Find all vendor blocks (with newlines preserved)
        for block in sourceText:gmatch("Vendor:[^\n]*\nZone:[^\n]*[^\n]*") do
            local vendor = block:match("Vendor:%s*([^\n]+)")
            local zone = block:match("Zone:%s*([^\n]+)")
            local cost = block:match("Cost:%s*([^\n]+)")
            
            -- Clean trailing keywords from vendor
            if vendor then
                vendor = vendor:gsub("%s*Zone:.*$", "")
                vendor = vendor:gsub("%s*Cost:.*$", "")
                vendor = vendor:gsub("%s*$", "")
            end
            if zone then
                zone = zone:gsub("%s*Cost:.*$", "")
                zone = zone:gsub("%s*Vendor:.*$", "")
                zone = zone:gsub("%s*$", "")
            end
            if cost then
                cost = cost:gsub("%s*Zone:.*$", "")
                cost = cost:gsub("%s*Vendor:.*$", "")
                cost = cost:gsub("%s*$", "")
            end
            
            if vendor and vendor ~= "" then
                table.insert(sources, {
                    vendor = vendor,
                    zone = (zone and zone ~= "") and zone or nil,
                    cost = (cost and cost ~= "") and cost or nil,
                    sourceType = "Vendor",
                    raw = block,
                })
            end
        end
        
        -- If pattern didn't match, try simpler split by lines
        if #sources == 0 then
            for line in sourceText:gmatch("[^\n]+") do
                if line:find("Vendor:") then
                    local vendor = line:match("Vendor:%s*([^%s].-)%s*$")
                    -- Clean any trailing keywords
                    if vendor then
                        vendor = vendor:gsub("%s*Zone:.*$", "")
                        vendor = vendor:gsub("%s*Cost:.*$", "")
                        vendor = vendor:gsub("%s*$", "")
                    end
                    if vendor and vendor ~= "" then
                        table.insert(sources, {
                            vendor = vendor,
                            sourceType = "Vendor",
                            raw = line,
                        })
                    end
                end
            end
        end
    end
    
    -- If no multiple sources found, parse as single source
    if #sources == 0 then
        local singleSource = {
            raw = sourceText,
            sourceType = nil,
            vendor = nil,
            zone = nil,
            cost = nil,
            npc = nil,
            faction = nil,
            renown = nil,
        }
        
        -- Determine source type with priority order (most specific first)
        if sourceText:find("Renown") or sourceText:find("Faction:") then
            singleSource.sourceType = "Renown"
        elseif sourceText:find("PvP") or sourceText:find("Arena") or sourceText:find("Rated") or sourceText:find("Battleground") then
            singleSource.sourceType = "PvP"
        elseif sourceText:find("Puzzle") or sourceText:find("Secret") then
            singleSource.sourceType = "Puzzle"
        elseif sourceText:find("World Event") or sourceText:find("Holiday") then
            singleSource.sourceType = "World Event"
        elseif sourceText:find("Treasure") or sourceText:find("Hidden") then
            singleSource.sourceType = "Treasure"
        elseif sourceText:find("Vendor") or sourceText:find("Sold by") then
            singleSource.sourceType = "Vendor"
        elseif sourceText:find("Drop") then
            singleSource.sourceType = "Drop"
        elseif sourceText:find("Pet Battle") then
            singleSource.sourceType = "Pet Battle"
        elseif sourceText:find("Quest") then
            singleSource.sourceType = "Quest"
        elseif sourceText:find("Achievement") then
            singleSource.sourceType = "Achievement"
        elseif sourceText:find("Profession") or sourceText:find("Crafted") then
            singleSource.sourceType = "Crafted"
        elseif sourceText:find("Promotion") or sourceText:find("Blizzard") then
            singleSource.sourceType = "Promotion"
        elseif sourceText:find("Trading Post") then
            singleSource.sourceType = "Trading Post"
        else
            singleSource.sourceType = "Unknown"
        end
        
        -- Extract details using patterns that stop at newline OR next keyword
        -- This handles both properly formatted text and single-line concatenated text
        
        -- Helper function to extract value between a keyword and the next keyword/newline/end
        local function extractField(text, keyword)
            -- Pattern: keyword followed by value, stopping at next keyword or newline
            -- First try: Match until newline
            local pattern = keyword .. ":%s*([^\n]+)"
            local value = text:match(pattern)
            
            if value then
                -- Clean trailing keywords that might have been captured (must be at word boundaries)
                value = value:gsub("%s+Vendor:%s*.*$", "")
                value = value:gsub("%s+Zone:%s*.*$", "")
                value = value:gsub("%s+Cost:%s*.*$", "")
                value = value:gsub("%s+Drop:%s*.*$", "")
                value = value:gsub("%s+Faction:%s*.*$", "")
                value = value:gsub("%s+Renown%s*.*$", "")
                value = value:gsub("%s+Quest:%s*.*$", "")
                value = value:gsub("%s+NPC:%s*.*$", "")
                -- Trim trailing whitespace
                value = value:gsub("%s*$", "")
            end
            return value
        end
        
        singleSource.vendor = extractField(sourceText, "Vendor") or extractField(sourceText, "Sold by")
        singleSource.zone = extractField(sourceText, "Zone")
        singleSource.cost = extractField(sourceText, "Cost")
        singleSource.npc = extractField(sourceText, "Drop")
        singleSource.faction = extractField(sourceText, "Faction") or extractField(sourceText, "Reputation")
        
        -- Extract renown/friendship levels
        local renownLevel = sourceText:match("Renown%s*(%d+)") or sourceText:match("Renown:%s*(%d+)")
        local friendshipLevel = sourceText:match("Friendship%s*(%d+)") or sourceText:match("Friendship:%s*(%d+)")
        
        if renownLevel then
            singleSource.renown = renownLevel
        elseif friendshipLevel then
            singleSource.renown = friendshipLevel
            singleSource.isFriendship = true
        end
        
        table.insert(sources, singleSource)
    end
    
    return sources
end

