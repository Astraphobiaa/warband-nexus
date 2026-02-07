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
-- PLAN LOOKUP INDEX (O(1) Hash Table)
-- ============================================================================
--[[
    O(1) hash table for IsPlanned() lookups.
    Without this, each browse card does O(n) scan through all plans.
    Rebuilt on add/remove/reset operations.
]]

--[[
    Initialize plan lookup index for O(1) IsPlanned() checks
]]
function WarbandNexus:InitializePlanCache()
    self.planCache = {
        mountIDs = {},
        petIDs = {},
        toyIDs = {},
        achievementIDs = {},
        illusionIDs = {},
        titleIDs = {},
        itemIDs = {}  -- For general item lookups
    }
    self:RefreshPlanCache()
end

--[[
    Rebuild lookup index from current plans
]]
function WarbandNexus:RefreshPlanCache()
    if not self.planCache then
        self:InitializePlanCache()
        return
    end
    
    -- Clear existing cache
    self.planCache.mountIDs = {}
    self.planCache.petIDs = {}
    self.planCache.toyIDs = {}
    self.planCache.achievementIDs = {}
    self.planCache.illusionIDs = {}
    self.planCache.titleIDs = {}
    self.planCache.itemIDs = {}
    
    -- Rebuild from db.global.plans
    if self.db and self.db.global and self.db.global.plans then
        for _, plan in ipairs(self.db.global.plans) do
            if plan.mountID then
                self.planCache.mountIDs[plan.mountID] = true
            end
            if plan.speciesID then
                self.planCache.petIDs[plan.speciesID] = true
            end
            if plan.itemID and plan.type == PLAN_TYPES.TOY then
                self.planCache.toyIDs[plan.itemID] = true
            end
            if plan.itemID then
                self.planCache.itemIDs[plan.itemID] = true
            end
            if plan.achievementID then
                self.planCache.achievementIDs[plan.achievementID] = true
            end
            if plan.illusionID then
                self.planCache.illusionIDs[plan.illusionID] = true
            end
            if plan.sourceID then  -- Alternative illusion ID field
                self.planCache.illusionIDs[plan.sourceID] = true
            end
            if plan.titleID then
                self.planCache.titleIDs[plan.titleID] = true
            end
        end
    end
    
    -- Also check custom plans
    if self.db and self.db.global and self.db.global.customPlans then
        for _, plan in ipairs(self.db.global.customPlans) do
            if plan.itemID then
                self.planCache.itemIDs[plan.itemID] = true
            end
        end
    end
end

-- ============================================================================
-- PLAN TRACKING & NOTIFICATIONS
-- ============================================================================

--[[
    Initialize plan completion tracking
    Registers events to check for completed plans
]]
function WarbandNexus:InitializePlanTracking()
    -- Build O(1) lookup index
    self:InitializePlanCache()
    
    -- Collection completion detection
    self:RegisterMessage("WN_COLLECTIBLE_OBTAINED", "OnPlanCollectionUpdated")
    self:RegisterEvent("ACHIEVEMENT_EARNED", "OnPlanCollectionUpdated")
    
    -- Weekly vault progress
    self:RegisterEvent("WEEKLY_REWARDS_UPDATE", "OnWeeklyRewardsUpdate")
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnPlayerEnteringWorld")
    self:RegisterEvent("CHALLENGE_MODE_COMPLETED", "OnWeeklyRewardsUpdate")
    self:RegisterEvent("ENCOUNTER_END", "OnWeeklyRewardsUpdate")
    
    -- Daily quest updates
    self:RegisterMessage("WARBAND_QUEST_PROGRESS_UPDATED", "OnDailyQuestProgressUpdated")
    
    -- Keep plan source text up-to-date when collection scans complete (API > DB flow)
    local Constants = ns.Constants
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_COMPLETE then
        self:RegisterMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function()
            self:UpdatePlanSources()
        end)
    end
    
    -- Initial checks after APIs are ready
    C_Timer.After(3, function()
        self:CheckPlansForCompletion()
        self:CheckWeeklyReset()
        self:UpdatePlanSources()
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
    Handle daily quest progress updates from DailyQuestManager
]]
function WarbandNexus:OnDailyQuestProgressUpdated()
    -- Check if any daily quest plans were completed
    self:CheckPlansForCompletion()
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
                -- For types without their own real-time detection (title),
                -- fire WN_COLLECTIBLE_OBTAINED so they get a toast like mounts/pets/toys
                if plan.type == "title" then
                    self:SendMessage("WN_COLLECTIBLE_OBTAINED", {
                        type = "title",
                        id = plan.titleID,
                        name = self:GetPlanDisplayName(plan),
                        icon = self:GetPlanDisplayIcon(plan)
                    })
                end
                
                self:ShowPlanCompletedNotification(plan)
                plan.completed = true -- Mark as completed
                plan.completionNotified = true -- Mark as notified
                
                -- Fire event for UI update
                self:SendMessage("WN_PLANS_UPDATED", {
                    action = "progress_changed",
                    planID = plan.id,
                    planType = plan.type,
                })
            end
        end
    end
end

--[[
    Check if a collected item completes an active plan
    Called by CollectionService when a mount/pet/toy is collected
    @param data table {type, name, id} from CollectionService
    @return table|nil - The completed plan or nil
]]
function WarbandNexus:CheckItemForPlanCompletion(data)
    if not self.db or not self.db.global or not self.db.global.plans then
        return nil
    end
    
    -- Use global plans (shared across characters)
    for _, plan in ipairs(self.db.global.plans) do
        if not plan.completed and not plan.completionNotified then
            -- Check if plan matches the collected item
            if plan.type == data.type and plan.name == data.name then
                -- Mark as completed and notified
                plan.completed = true
                plan.completionNotified = true
                return plan
            end
        end
    end
    return nil
end

--[[
    Resolve the localized display name for a plan using WoW API.
    Always fetches from API based on type-specific IDs to ensure correct client language.
    Falls back to stored plan.name if API is unavailable.
    @param plan table - Plan data
    @return string - Localized display name
]]
function WarbandNexus:GetPlanDisplayName(plan)
    if not plan then return ((ns.L and ns.L["UNKNOWN"]) or "Unknown") end
    
    if plan.type == "achievement" and plan.achievementID then
        local _, achievementName = GetAchievementInfo(plan.achievementID)
        if achievementName and achievementName ~= "" then return achievementName end
    elseif plan.type == "mount" and plan.mountID then
        local name = C_MountJournal.GetMountInfoByID(plan.mountID)
        if name and name ~= "" then return name end
    elseif plan.type == "pet" and plan.speciesID then
        local name = C_PetJournal.GetPetInfoBySpeciesID(plan.speciesID)
        if name and name ~= "" then return name end
    elseif plan.type == "toy" and plan.itemID then
        local name = C_Item.GetItemNameByID(plan.itemID)
        if name and name ~= "" then return name end
    elseif plan.type == "title" and plan.titleID then
        if GetTitleName then
            local rawTitle = GetTitleName(plan.titleID)
            if rawTitle and rawTitle ~= "" then
                return rawTitle:gsub("^%s+", ""):gsub("%s+$", ""):gsub(",%s*$", "")
            end
        end
    elseif plan.type == "illusion" and plan.illusionID then
        -- Illusions: iterate collection to find by sourceID
        if C_TransmogCollection and C_TransmogCollection.GetIllusions then
            local illusions = C_TransmogCollection.GetIllusions()
            if illusions then
                for _, illusionInfo in ipairs(illusions) do
                    if illusionInfo.sourceID == plan.illusionID then
                        if illusionInfo.name and illusionInfo.name ~= "" then
                            return illusionInfo.name
                        end
                        break
                    end
                end
            end
        end
    elseif (plan.type == "transmog" or plan.type == "recipe") and plan.itemID then
        local name = C_Item.GetItemNameByID(plan.itemID)
        if name and name ~= "" then return name end
    end
    
    -- Fallback to stored name
    return plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
end

--[[
    Resolve the localized source/description for a plan.
    For items with itemID, fetches from tooltip or API.
    Falls back to stored plan.source.
    @param plan table - Plan data
    @return string - Source description
]]
function WarbandNexus:GetPlanDisplaySource(plan)
    if not plan then return "" end
    -- Source text is usually from WoWHead/API data and stored at creation.
    -- Most source texts come from English databases, so return as-is.
    -- Achievement descriptions can be resolved from API.
    if plan.type == "achievement" and plan.achievementID then
        local _, _, _, _, _, _, _, description = GetAchievementInfo(plan.achievementID)
        if description and description ~= "" then return description end
    end
    return plan.source or ""
end

--[[
    Resolve the localized icon for a plan using WoW API.
    @param plan table - Plan data
    @return number|string|nil - Icon texture ID or path
]]
function WarbandNexus:GetPlanDisplayIcon(plan)
    if not plan then return nil end
    
    if plan.type == "achievement" and plan.achievementID then
        local _, _, _, _, _, _, _, _, _, icon = GetAchievementInfo(plan.achievementID)
        if icon then return icon end
    elseif plan.type == "mount" and plan.mountID then
        local _, _, icon = C_MountJournal.GetMountInfoByID(plan.mountID)
        if icon then return icon end
    elseif plan.type == "pet" and plan.speciesID then
        local _, icon = C_PetJournal.GetPetInfoBySpeciesID(plan.speciesID)
        if icon then return icon end
    elseif plan.type == "toy" and plan.itemID then
        local icon = GetItemIcon(plan.itemID)
        if icon then return icon end
    elseif (plan.type == "transmog" or plan.type == "recipe") and plan.itemID then
        local icon = GetItemIcon(plan.itemID)
        if icon then return icon end
    end
    
    return plan.icon
end

--[[
    Show a toast notification for a completed plan
    @param plan table - The completed plan
]]
function WarbandNexus:ShowPlanCompletedNotification(plan)
    local displayName = self:GetPlanDisplayName(plan)
    local displayIcon = self:GetPlanDisplayIcon(plan)
    
    -- Send plan completion event
    self:SendMessage("WN_PLAN_COMPLETED", {
        planType = plan.type,
        name = displayName,
        icon = displayIcon
    })
    
    self:Print("|cff00ff00" .. ((ns.L and ns.L["PLAN_COMPLETED"]) or "Plan completed: ") .. "|r" .. displayName)
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
    local planCharKey = ns.Utilities:GetCharacterKey(characterName, characterRealm)
    if planCharKey == currentKey then
        characterClass = currentClass
    end
    
    -- Create weekly plan structure
    local plan = {
        id = planID,
        type = "weekly_vault",
        characterName = characterName,
        characterRealm = characterRealm,
        characterClass = characterClass,  -- Store class for color coding
        name = string.format((ns.L and ns.L["WEEKLY_VAULT_PLAN_NAME"]) or "Weekly Vault - %s", characterName),
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
    local newlyCompletedCheckpoints = {}
    
    -- Track old progress values for checkpoint detection
    local oldDungeonCount = oldProgress and oldProgress.dungeonCount or plan.progress.dungeonCount
    local oldRaidCount = oldProgress and oldProgress.raidBossCount or plan.progress.raidBossCount
    local oldWorldCount = oldProgress and oldProgress.worldActivityCount or plan.progress.worldActivityCount
    
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
    
    -- Check for newly completed dungeon checkpoints (individual progress gains)
    if plan.progress.dungeonCount > oldDungeonCount then
        table.insert(newlyCompletedCheckpoints, {
            category = "dungeon",
            progress = plan.progress.dungeonCount,
            oldProgress = oldDungeonCount
        })
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
    
    -- Check for newly completed raid checkpoints
    if plan.progress.raidBossCount > oldRaidCount then
        table.insert(newlyCompletedCheckpoints, {
            category = "raid",
            progress = plan.progress.raidBossCount,
            oldProgress = oldRaidCount
        })
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
    
    -- Check for newly completed world checkpoints
    if plan.progress.worldActivityCount > oldWorldCount then
        table.insert(newlyCompletedCheckpoints, {
            category = "world",
            progress = plan.progress.worldActivityCount,
            oldProgress = oldWorldCount
        })
    end
    
    -- Show notifications for newly completed checkpoints (individual progress gains)
    if not skipNotifications then
        for _, checkpoint in ipairs(newlyCompletedCheckpoints) do
            self:Debug("Checkpoint completed: " .. checkpoint.category .. " " .. checkpoint.oldProgress .. " -> " .. checkpoint.progress)
            self:ShowWeeklyCheckpointNotification(plan.characterName, checkpoint.category, checkpoint.progress)
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
    Show notification for completed checkpoint (individual progress)
    @param characterName string - Character name
    @param category string - "dungeon", "raid", or "world"
    @param progress number - Current progress value
]]
function WarbandNexus:ShowWeeklyCheckpointNotification(characterName, category, progress)
    self:Debug("Sending vault checkpoint notification: " .. category .. " - " .. characterName .. " - progress: " .. progress)
    
    -- Send vault checkpoint completion event
    self:SendMessage("WN_VAULT_CHECKPOINT_COMPLETED", {
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
    self:SendMessage("WN_VAULT_SLOT_COMPLETED", {
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
    self:SendMessage("WN_VAULT_PLAN_COMPLETED", {
        characterName = characterName
    })
end

--[[
    Show notification for completed daily quest
    @param characterName string - Character name
    @param category string - Quest category
    @param questTitle string - Quest title
]]
function WarbandNexus:ShowDailyQuestNotification(characterName, category, questTitle)
    self:Debug("Sending quest notification: " .. questTitle)
    
    -- Send quest completion event
    self:SendMessage("WN_QUEST_COMPLETED", {
        characterName = characterName,
        category = category,
        questTitle = questTitle
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
        self:Print("|cff00ff00" .. string.format((ns.L and ns.L["VAULT_PLANS_RESET"]) or "Weekly Great Vault plans have been reset! (%d plan%s)", resetCount, (resetCount > 1 and "s" or "")) .. "|r")
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
            return time() + secondsUntil
        end
    end
    
    -- Fallback: Region-based calculation
    local currentTime = time()
    local currentDate = date("*t", currentTime)
    
    -- Detect region (portal = realm region)
    local region = GetCVar("portal") or "US"
    
    -- Region-specific reset times
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
    
    -- Calculate days until next reset day
    local dayOfWeek = currentDate.wday
    local daysUntilReset = (resetDay - dayOfWeek + 7) % 7
    
    if daysUntilReset == 0 then
        -- It's the reset day, check if reset has passed
        if currentDate.hour >= resetHour then
            daysUntilReset = 7  -- Next week
        end
    end
    
    -- Calculate next reset date
    local resetDate = date("*t", currentTime + (daysUntilReset * 24 * 60 * 60))
    resetDate.hour = resetHour
    resetDate.min = 0
    resetDate.sec = 0
    
    return time(resetDate)
end

-- MOVED: FormatTimeUntilReset() → Utilities.lua
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
        C_Timer.After(3, function()
            self:CheckWeeklyReset()
            self:CheckRecurringPlanResets()
        end)
    end
end

---Check if a Blizzard daily reset has occurred since the given timestamp.
---Uses C_DateAndTime.GetSecondsUntilDailyReset to derive the last reset moment.
---@param sinceTimestamp number epoch seconds
---@return boolean
function WarbandNexus:HasDailyResetOccurredSince(sinceTimestamp)
    if not sinceTimestamp or sinceTimestamp == 0 then return true end
    local secondsUntilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset() or 0
    local lastResetTime = time() + secondsUntilReset - 86400  -- last reset = next reset - 24h
    return sinceTimestamp < lastResetTime
end

---Check if a Blizzard weekly reset has occurred since the given timestamp.
---@param sinceTimestamp number epoch seconds
---@return boolean
function WarbandNexus:HasWeeklyResetOccurredSince(sinceTimestamp)
    if not sinceTimestamp or sinceTimestamp == 0 then return true end
    local secondsUntilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
    local lastResetTime = time() + secondsUntilReset - (7 * 86400)
    return sinceTimestamp < lastResetTime
end

---Check all custom plans with resetCycle and reset completed ones when the cycle fires.
function WarbandNexus:CheckRecurringPlanResets()
    if not self.db or not self.db.global or not self.db.global.customPlans then return end

    local now = time()
    local changed = false

    for _, plan in ipairs(self.db.global.customPlans) do
        local rc = plan.resetCycle
        if rc and rc.enabled and plan.completed then
            local shouldReset = false
            if rc.resetType == "daily" then
                shouldReset = self:HasDailyResetOccurredSince(rc.lastResetTime or 0)
            elseif rc.resetType == "weekly" then
                shouldReset = self:HasWeeklyResetOccurredSince(rc.lastResetTime or 0)
            end

            if shouldReset then
                -- Decrement remaining cycles
                if rc.remainingCycles and rc.remainingCycles > 0 then
                    rc.remainingCycles = rc.remainingCycles - 1
                end

                -- Check if all cycles are exhausted
                if rc.remainingCycles and rc.remainingCycles <= 0 then
                    -- Final cycle completed — disable reset, keep plan completed
                    rc.enabled = false
                    changed = true
                else
                    -- More cycles remain — reset for next cycle
                    plan.completed = false
                    rc.lastResetTime = now
                    rc.completedAt = nil
                    changed = true
                end
            end
        end
    end

    if changed then
        self:SendMessage("WN_PLANS_UPDATED", { action = "recurring_reset" })
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
function WarbandNexus:AddPlan(planData)
    if not self.db.global.plans then
        self.db.global.plans = {}
    end
    
    -- Validate input
    if not planData or type(planData) ~= "table" then
        self:Print("|cffff6600Error: Invalid plan data|r")
        return nil
    end
    
    -- Extract type (required)
    local planType = planData.type
    if not planType then
        self:Print("|cffff6600Error: Plan type is required|r")
        return nil
    end
    
    -- Generate unique ID
    local planID = self.db.global.plansNextID or 1
    self.db.global.plansNextID = planID + 1
    
    local plan = {
        id = planID,
        type = planType,
        itemID = planData.itemID,
        name = planData.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
        icon = planData.icon,
        source = planData.source or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
        addedAt = time(),
        notes = planData.notes or "",
        
        -- Type-specific IDs
        mountID = planData.mountID,
        petID = planData.petID,
        speciesID = planData.speciesID,
        recipeID = planData.recipeID,
        achievementID = planData.achievementID,
        illusionID = planData.illusionID,
        titleID = planData.titleID,
        
        -- For recipes: store reagent requirements
        reagents = planData.reagents,
        
        -- For achievements: store reward text and points
        rewardText = planData.rewardText,
        points = planData.points,
    }
    
    table.insert(self.db.global.plans, plan)
    
    -- Refresh lookup index
    self:RefreshPlanCache()
    
    -- Fire event for UI update (API > DB > UI)
    self:SendMessage("WN_PLANS_UPDATED", {
        action = "added",
        planID = planID,
        planType = planType,
    })
    
    -- Notify (use resolved name for proper localization)
    self:Print("|cff00ff00Added plan:|r " .. self:GetPlanDisplayName(plan))
    
    return planID
end

--[[
    Remove a plan by ID
    @param planID number - Plan ID to remove
    @return boolean - Success
]]
function WarbandNexus:RemovePlan(planID)
    -- Helper: search and remove from a plan list
    local function removeFromList(list, id, label)
        if not list then return false end
        for i = 1, #list do
            if list[i].id == id then
                local name = list[i].name
                local planType = list[i].type
                table.remove(list, i)
                self:RefreshPlanCache()
                self:SendMessage("WN_PLANS_UPDATED", {
                    action = "removed",
                    planID = id,
                    planType = planType,
                })
                self:Print("|cffff6600Removed " .. label .. ":|r " .. name)
                return true
            end
        end
        return false
    end
    
    return removeFromList(self.db.global.plans, planID, "plan")
        or removeFromList(self.db.global.customPlans, planID, "custom plan")
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
    
    -- Refresh cache if any plans were removed
    if removedCount > 0 then
        self:RefreshPlanCache()
    end
    
    return removedCount
end

--[[
    Update plan source text from CollectionService data.
    Called on COLLECTION_SCAN_COMPLETE to keep sources up-to-date.
    Writes updated source text directly into db.global.plans (API > DB flow).
]]
function WarbandNexus:UpdatePlanSources()
    if not ns.CollectionService then return end
    
    local collectionCache = ns.CollectionService.collectionCache
    if not collectionCache or not collectionCache.uncollected then return end
    
    local updated = false
    local plans = self.db.global.plans
    if not plans then return end
    
    for i = 1, #plans do
        local plan = plans[i]
        local newSource = nil
        
        if plan.type == "pet" and plan.speciesID then
            local cached = collectionCache.uncollected.pet and collectionCache.uncollected.pet[plan.speciesID]
            if cached and cached.source then
                newSource = cached.source
            end
        elseif plan.type == "mount" and plan.mountID then
            local cached = collectionCache.uncollected.mount and collectionCache.uncollected.mount[plan.mountID]
            if cached and cached.source then
                newSource = cached.source
            end
        elseif plan.type == "toy" and plan.itemID then
            local cached = collectionCache.uncollected.toy and collectionCache.uncollected.toy[plan.itemID]
            if cached and cached.source then
                newSource = cached.source
            end
        end
        
        if newSource and newSource ~= plan.source then
            plan.source = newSource
            updated = true
        end
    end
    
    -- Notify UI only if sources actually changed
    if updated then
        self:SendMessage("WN_PLANS_UPDATED", {
            action = "sources_refreshed"
        })
    end
end

--[[
    Get all active plans (pure DB read)
    @param planType string (optional) - Filter by type
    @return table - Array of plans
]]
function WarbandNexus:GetActivePlans(planType)
    local allPlans = {}
    
    -- Read from DB (no mutation, no cache coupling)
    if self.db.global.plans then
        for i = 1, #self.db.global.plans do
            allPlans[#allPlans + 1] = self.db.global.plans[i]
        end
    end
    
    if self.db.global.customPlans then
        for i = 1, #self.db.global.customPlans do
            allPlans[#allPlans + 1] = self.db.global.customPlans[i]
        end
    end
    
    if not planType then
        return allPlans
    end
    
    -- Filter by type
    local filtered = {}
    for i = 1, #allPlans do
        if allPlans[i].type == planType then
            filtered[#filtered + 1] = allPlans[i]
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
    -- Use cache for O(1) lookup
    if not self.planCache then
        self:InitializePlanCache()
    end
    
    return self.planCache.itemIDs[itemID] == true
end

--[[
    Check if mount is already in plans
    @param mountID number - Mount ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsMountPlanned(mountID)
    -- Use cache for O(1) lookup
    if not self.planCache then
        self:InitializePlanCache()
    end
    
    return self.planCache.mountIDs[mountID] == true
end

--[[
    Check if pet species is already in plans
    @param speciesID number - Pet species ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsPetPlanned(speciesID)
    -- Use cache for O(1) lookup
    if not self.planCache then
        self:InitializePlanCache()
    end
    
    return self.planCache.petIDs[speciesID] == true
end

--[[
    Check if achievement is already in plans
    @param achievementID number - Achievement ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsAchievementPlanned(achievementID)
    -- Use cache for O(1) lookup
    if not self.planCache then
        self:InitializePlanCache()
    end
    
    return self.planCache.achievementIDs[achievementID] == true
end

--[[
    Check if illusion is already in plans
    @param illusionID number - Illusion sourceID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsIllusionPlanned(illusionID)
    -- Use cache for O(1) lookup
    if not self.planCache then
        self:InitializePlanCache()
    end
    
    return self.planCache.illusionIDs[illusionID] == true
end

--[[
    Check if title is already in plans
    @param titleID number - Title ID to check
    @return boolean - True if already planned
]]
function WarbandNexus:IsTitlePlanned(titleID)
    -- Use cache for O(1) lookup
    if not self.planCache then
        self:InitializePlanCache()
    end
    
    return self.planCache.titleIDs[titleID] == true
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

-- ============================================================================
-- DEAD CODE REMOVED (v2.0 Cleanup)
-- ============================================================================
--[[
    The following currency parsing functions were never used:
    - FindCurrencyByName()
    - GetPlayerCurrencyAmount()
    - IdentifyCurrencyFromVendorZone()
    - ExtractCurrencyFromTexture()
    - COMMON_CURRENCIES table
    - VENDOR_CURRENCY_MAP table
    - CURRENCY_TEXTURE_MAP table
    
    These were likely planned for a vendor/currency tracking feature
    that was never implemented. Removed ~300 lines of dead code.
]]

--[[
    DEPRECATED COLLECTION GETTERS (REMOVED - USE CollectionService INSTEAD)
    ============================================================================
    
    The following functions have been REMOVED to prevent override conflicts:
    - GetUncollectedMounts   → Implemented in CollectionService.lua
    - GetUncollectedPets     → Implemented in CollectionService.lua
    - GetUncollectedToys     → Implemented in CollectionService.lua
    
    These functions were OVERRIDING CollectionService due to .toc load order.
    PlansUI now correctly uses CollectionService implementations.
]]

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






