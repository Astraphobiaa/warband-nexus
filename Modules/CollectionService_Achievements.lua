--[[ CollectionService achievement scan, character points recompute, reward scanner (split from CollectionService.lua) ]]
local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local RT = assert(ns.CollectionServiceRT, 'CollectionService_Achievements: load CollectionService.lua first')
local issecretvalue = issecretvalue
local DebugPrint = RT.DebugPrint
local DebugPrintf = RT.DebugPrintf
local GetCategoryAchievementListCount = RT.GetCategoryAchievementListCount
local EnsurePlansAchievementLoadingState = RT.EnsurePlansAchievementLoadingState
local SafeAchievementDisplayName = RT.SafeAchievementDisplayName
local IsAchievementEarnedByMe = RT.IsAchievementEarnedByMe
local GetAchievementEarnedByMeInfo = RT.GetAchievementEarnedByMeInfo
local GetAchievementInfoByCategoryIndex = RT.GetAchievementInfoByCategoryIndex
local NeedsCharacterAchievementPointsRecompute = RT.NeedsCharacterAchievementPointsRecompute
local PersistCharacterAchievementPoints = RT.PersistCharacterAchievementPoints
local Constants = ns.Constants
local E = Constants.EVENTS
local FRAME_BUDGET_MS = Constants.FRAME_BUDGET_MS
local SendCollectionScanProgress = RT.SendCollectionScanProgress
local collectionStore = RT.collectionStore
local ACHIEVEMENT_STORE_MIN_TRUST = RT.ACHIEVEMENT_STORE_MIN_TRUST
local CountAchievementStoreEntries = RT.CountAchievementStoreEntries
local IsAchievementStoreInadequate = RT.IsAchievementStoreInadequate
local SignalAchievementScanPipelineDone = RT.SignalAchievementScanPipelineDone
local collectionCache = RT.collectionCache
local WipeUncollectedResultsCacheAndMergedAchievements = RT.WipeUncollectedResultsCacheAndMergedAchievements
local activeCoroutines = RT.activeCoroutines

---GetCategoryList() is empty until achievement APIs hydrate (often after login).
local ACHIEVEMENT_CATEGORY_LIST_MIN_IDS = 40
local achievementScanDeferAttempts = 0
local ACHIEVEMENT_SCAN_DEFER_MAX_ATTEMPTS = 24

local function AchievementCategoryListReady()
    if not GetCategoryList then return false end
    local list = GetCategoryList() or {}
    return #list >= ACHIEVEMENT_CATEGORY_LIST_MIN_IDS
end

---Async achievement scanner (background scanning with coroutine)
---Scans all achievements and populates achievement cache
---NOTE: Titles are now scanned separately via Title API
function WarbandNexus:ScanAchievementsAsync()
    -- Prevent duplicate scans
    if activeCoroutines["achievements"] then
    DebugPrint("|cffffcc00[WN CollectionService]|r Achievement scan already in progress")
        return
    end
    
    -- Use separate lastScan timestamp for achievements
    -- Don't share with mount/pet/toy (they update global lastScan)
    local lastAchievementScan = collectionCache.lastAchievementScan or 0
    local timeSinceLastScan = time() - lastAchievementScan
    
    -- Validate timestamp (prevent negative values from corrupted data)
    if timeSinceLastScan < 0 then
    DebugPrint("|cffffcc00[WN CollectionService]|r Invalid lastAchievementScan timestamp detected, forcing scan")
        timeSinceLastScan = math.huge  -- Force scan
    end
    
    -- Check cooldown (5 minutes) — bypass when persisted store is empty/truncated
    local forceRescan = IsAchievementStoreInadequate()
    if timeSinceLastScan < 300 and not forceRescan then
    DebugPrintf("|cffffcc00[WN CollectionService]|r Achievement scan skipped (last scan %.0f seconds ago)", timeSinceLastScan)
        if NeedsCharacterAchievementPointsRecompute(self) and self.RecomputeCharacterAchievementPointsAsync then
            self:RecomputeCharacterAchievementPointsAsync()
        end
        SignalAchievementScanPipelineDone(self, { category = "achievement", skipped = true })
        return
    end

    if not AchievementCategoryListReady() then
        achievementScanDeferAttempts = achievementScanDeferAttempts + 1
        if achievementScanDeferAttempts >= ACHIEVEMENT_SCAN_DEFER_MAX_ATTEMPTS then
            achievementScanDeferAttempts = 0
            DebugPrint("|cffff0000[WN CollectionService]|r GetCategoryList() still empty after defer — achievement scan aborted")
            EnsurePlansAchievementLoadingState(false)
            ns.CollectionLoadingState.isLoading = false
            if Constants and Constants.EVENTS then
                self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = "achievement", failed = true })
            end
            return
        end
        EnsurePlansAchievementLoadingState(true)
        ns.CollectionLoadingState.isLoading = true
        ns.CollectionLoadingState.loadingProgress = 0
        ns.CollectionLoadingState.currentStage = (ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements..."
        ns.CollectionLoadingState.currentCategory = "achievement"
        DebugPrint("|cffffcc00[WN CollectionService]|r GetCategoryList() not ready — deferring achievement scan")
        C_Timer.After(0.25, function()
            self:ScanAchievementsAsync()
        end)
        return
    end
    achievementScanDeferAttempts = 0
    
    DebugPrint("|cff9370DB[WN CollectionService]|r Starting async achievement scan...")
    
    -- Update loading state (may already be set by GetUncollectedAchievements)
    EnsurePlansAchievementLoadingState(true)
    ns.CollectionLoadingState.isLoading = true
    ns.CollectionLoadingState.loadingProgress = 0
    ns.CollectionLoadingState.currentStage = "Achievements"
    ns.CollectionLoadingState.currentCategory = "achievement"
    ns.CollectionLoadingState.scannedItems = 0
    ns.CollectionLoadingState.totalItems = 0
    
    -- Fire initial progress event to trigger UI update
    SendCollectionScanProgress(self, "achievement", 0, 0, 0)
    
    local startTime = debugprofilestop()  -- Use debugprofilestop for elapsed time measurement
    local totalAchievements = 0
    local scannedCount = 0
    local characterPointsSum = 0
    local totalEstimated = 5000  -- Rough estimate for progress bar
    local lastProgressUpdate = 0  -- Throttle progress events
    local lastYield = debugprofilestop()  -- Track time since last yield
    
    local function scanCoroutine()
        collectionCache.uncollected.achievement = {}
        collectionCache.completed = collectionCache.completed or {}
        collectionCache.completed.achievement = {}

        local categoryList = GetCategoryList()
        if not categoryList or #categoryList == 0 then
    DebugPrint("|cffff0000[WN CollectionService]|r GetCategoryList() returned no categories during scan")
            return
        end
        
        for i = 1, #categoryList do
            local categoryID = categoryList[i]
            if categoryID then
                local numAchievements = GetCategoryAchievementListCount(categoryID)

                for achIndex = 1, numAchievements do
                    local success, id, name, points, completed, month, day, year, description, flags, icon, achRewardText, isGuild, wasEarnedByMe =
                        GetAchievementInfoByCategoryIndex(categoryID, achIndex)
                    
                    -- Update progress (throttled to reduce event spam)
                    scannedCount = scannedCount + 1
                    
                    -- OPTIMIZATION: Only fire progress event every 250 achievements (not 100)
                    -- This reduces UI refresh spam and improves FPS
                    if scannedCount % 250 == 0 then
                        local progress = math.min(100, math.floor((scannedCount / totalEstimated) * 100))
                        local timeSinceLastUpdate = debugprofilestop() - lastProgressUpdate
                        
                        -- Only update if at least 100ms passed (throttle UI updates)
                        if timeSinceLastUpdate >= 100 then
                            ns.CollectionLoadingState.loadingProgress = progress
                            ns.CollectionLoadingState.scannedItems = scannedCount
                            
                            -- Also update PlansLoadingState for UI (achievement uses PlansLoadingState)
                            if ns.PlansLoadingState and ns.PlansLoadingState.achievement then
                                ns.PlansLoadingState.achievement.loadingProgress = progress
                                ns.PlansLoadingState.achievement.currentStage = string.format("Scanning Achievements... (%d/%d)", scannedCount, totalEstimated)
                            end
                            
                            lastProgressUpdate = debugprofilestop()
                            
                            -- Fire progress event (UI will throttle refreshes)
                            SendCollectionScanProgress(self, "achievement", progress, scannedCount, totalEstimated)
                        end
                    end
                    
                    if not success or not id then
                        -- Yield and continue
                    else
                        local rewardItemID, rewardTitle
                        local rewardSuccess, item, title = pcall(GetAchievementReward, id)
                        if rewardSuccess then
                            if type(item) == "number" then rewardItemID = item end
                            if type(title) == "string" and not (issecretvalue and issecretvalue(title)) and title ~= "" then
                                rewardTitle = title
                            elseif type(item) == "string" and not (issecretvalue and issecretvalue(item)) and item ~= "" then
                                rewardTitle = item
                            end
                        end
                        if not rewardTitle and achRewardText and not (issecretvalue and issecretvalue(achRewardText)) and achRewardText ~= "" then
                            rewardTitle = achRewardText
                        end

                        local displayName = SafeAchievementDisplayName(id, name)
                        if not displayName then
                            -- skip secret id
                        else
                        -- Store the achievement's ACTUAL category (not the iterator's parent category)
                        local realCategoryID = categoryID
                        if GetAchievementCategory then
                            local actualCat = GetAchievementCategory(id)
                            if actualCat and actualCat > 0 then
                                realCategoryID = actualCat
                            end
                        end
                        local record = {
                            id = id,
                            name = displayName,
                            icon = icon,
                            points = points,
                            description = description,
                            collected = completed,
                            categoryID = realCategoryID,
                            rewardItemID = rewardItemID,
                            rewardTitle = rewardTitle,
                        }
                        collectionStore.achievement[id] = record
                        local earnedByMe, guildFlag, pt = GetAchievementEarnedByMeInfo(id, points, wasEarnedByMe, isGuild)
                        if IsAchievementEarnedByMe(earnedByMe) and guildFlag ~= true then
                            local ptNum = tonumber(pt)
                            if ptNum and ptNum > 0 then
                                characterPointsSum = characterPointsSum + ptNum
                            end
                        end
                        if completed then
                            collectionCache.completed.achievement[id] = displayName
                        else
                            collectionCache.uncollected.achievement[id] = displayName
                            totalAchievements = totalAchievements + 1
                        end
                        end
                    end
                    
                    -- OPTIMIZATION: Yield every 100 achievements (improved from 20)
                    -- Check frame budget (don't exceed 8ms per frame)
                    if scannedCount % 100 == 0 then
                        -- Check if scan was aborted (tab switch)
                        if not activeCoroutines["achievements"] then
    DebugPrint("|cffffcc00[WN CollectionService]|r Achievement scan aborted")
                            if ns.PlansLoadingState and ns.PlansLoadingState.achievement then
                                ns.PlansLoadingState.achievement.isLoading = false
                            end
                            return  -- Exit coroutine gracefully
                        end
                        
                        local timeSinceYield = debugprofilestop() - lastYield
                        -- If we've used more than 8ms, yield immediately
                        if timeSinceYield >= 8 then
                            lastYield = debugprofilestop()
                            coroutine.yield()
                        end
                    end
                end
            end
        end
        
        -- Achievement-specific timestamp only. Writing the shared lastScan here made
        -- ScanCollection's 5-minute skip gate treat title/illusion caches as fresh and
        -- starve those scans right after an achievement pass.
        local storedAchCount = CountAchievementStoreEntries()
        if storedAchCount >= ACHIEVEMENT_STORE_MIN_TRUST then
            collectionCache.lastAchievementScan = time()
        else
            collectionCache.lastAchievementScan = 0
            DebugPrintf("|cffffcc00[WN CollectionService]|r Achievement scan stored only %d rows — will retry on next request", storedAchCount)
        end
        
        -- Save to DB
        PersistCharacterAchievementPoints(self, characterPointsSum)
        self:SaveCollectionStore()
        self:SaveCollectionCache()
        WipeUncollectedResultsCacheAndMergedAchievements()

        if self.db and self.db.global then
            self.db.global.wnAchievementDirectScanV2 = true
        end
        
        local elapsed = (debugprofilestop() - startTime) / 1000  -- Convert ms to seconds
        
        -- Update loading state
        ns.CollectionLoadingState.isLoading = false
        ns.CollectionLoadingState.loadingProgress = 100
        ns.CollectionLoadingState.scannedItems = scannedCount
        
        -- Update PlansLoadingState for UI (achievement uses PlansLoadingState, not CollectionLoadingState)
        if ns.PlansLoadingState and ns.PlansLoadingState.achievement then
            ns.PlansLoadingState.achievement.isLoading = false
            ns.PlansLoadingState.achievement.loadingProgress = 100
            ns.PlansLoadingState.achievement.currentStage = "Complete!"
        end
        
    DebugPrintf("|cff00ff00[WN CollectionService]|r Achievement scan complete: %d achievements (%.2fs)",
        totalAchievements, elapsed)
        
        -- Fire completion event
        self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, {
            category = "achievement",
            totalAchievements = totalAchievements,
            elapsed = elapsed,
        })
        if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
            self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "achievement")
        end
        
        -- UI refreshes via WN_COLLECTION_SCAN_COMPLETE listener in UI.lua (event-driven).
        
        -- Cleanup
        activeCoroutines["achievements"] = nil
    end
    
    -- Start coroutine
    local co = coroutine.create(scanCoroutine)
    activeCoroutines["achievements"] = co
    
    local function resetAchievementLoadingState()
        -- Normal completion already reset both loading states and sent
        -- COLLECTION_SCAN_COMPLETE from inside the coroutine; firing again here made
        -- every listener (UI refresh, results-cache wipe) process the scan twice.
        -- Only act for abnormal exits (resume error, mid-scan abort).
        local stillLoading = ns.CollectionLoadingState.isLoading
            or (ns.PlansLoadingState and ns.PlansLoadingState.achievement and ns.PlansLoadingState.achievement.isLoading)
        if not stillLoading then return end
        ns.CollectionLoadingState.isLoading = false
        ns.CollectionLoadingState.loadingProgress = 100
        if ns.PlansLoadingState and ns.PlansLoadingState.achievement then
            ns.PlansLoadingState.achievement.isLoading = false
            ns.PlansLoadingState.achievement.loadingProgress = 100
        end
        -- Ensure EnsureCollectionData queue can advance even on failure
        if Constants and Constants.EVENTS then
            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = "achievement" })
        end
    end

    -- Run coroutine with frame budget
    local function resumeCoroutine()
        local co = activeCoroutines["achievements"]
        if not co then return end
        if InCombatLockdown and InCombatLockdown() then
            C_Timer.After(0, resumeCoroutine)
            return
        end

        local budget = FRAME_BUDGET_MS
        local startTime = debugprofilestop()
        
        while (debugprofilestop() - startTime) < budget do
            local status, err = coroutine.resume(co)
            if not status then
    DebugPrint("|cffff0000[WN CollectionService ERROR]|r Achievement scan failed: " .. tostring(err))
                activeCoroutines["achievements"] = nil
                resetAchievementLoadingState()
                return
            end
            
            -- Check if coroutine finished
            if coroutine.status(co) == "dead" then
                activeCoroutines["achievements"] = nil
                resetAchievementLoadingState()
                return
            end
        end
        
        -- Continue next frame
        C_Timer.After(0, resumeCoroutine)
    end
    
    resumeCoroutine()
end

---Sum wasEarnedByMe points from persisted achievement store (GetAchievementInfo per ID).
---Runs when full scan is on cooldown but character score was never persisted.
function WarbandNexus:RecomputeCharacterAchievementPointsAsync()
    if activeCoroutines["achievement_char_points"] or activeCoroutines["achievements"] then
        return
    end
    if not NeedsCharacterAchievementPointsRecompute(self) then
        return
    end
    if IsAchievementStoreInadequate() then
        self:ScanAchievementsAsync()
        return
    end

    local function worker()
        local sum = 0
        local scanned = 0
        local store = collectionStore.achievement
        if type(store) ~= "table" then
            activeCoroutines["achievement_char_points"] = nil
            return
        end
        for achID, record in pairs(store) do
            if not activeCoroutines["achievement_char_points"] then return end
            local id = achID
            if type(record) == "table" and type(record.id) == "number" then
                id = record.id
            end
            if type(id) == "number" and not (issecretvalue and issecretvalue(id)) then
                local wasEarnedByMe, isGuild, points = GetAchievementEarnedByMeInfo(id)
                if IsAchievementEarnedByMe(wasEarnedByMe) and isGuild ~= true then
                    local pt = tonumber(points) or 0
                    if pt > 0 then sum = sum + pt end
                end
            end
            scanned = scanned + 1
            if scanned % 100 == 0 then
                coroutine.yield()
            end
        end
        PersistCharacterAchievementPoints(self, sum)
        if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_UPDATED then
            self:SendMessage(Constants.EVENTS.COLLECTION_UPDATED, "achievement")
        end
        activeCoroutines["achievement_char_points"] = nil
    end

    local co = coroutine.create(worker)
    activeCoroutines["achievement_char_points"] = co

    local function resumeCharPoints()
        local c = activeCoroutines["achievement_char_points"]
        if not c then return end
        if InCombatLockdown and InCombatLockdown() then
            C_Timer.After(0, resumeCharPoints)
            return
        end
        local budget = FRAME_BUDGET_MS
        local t0 = debugprofilestop()
        while (debugprofilestop() - t0) < budget do
            local ok, err = coroutine.resume(c)
            if not ok then
                DebugPrint("|cffff0000[WN CollectionService ERROR]|r Char achievement points recompute failed: " .. tostring(err))
                activeCoroutines["achievement_char_points"] = nil
                return
            end
            if coroutine.status(c) == "dead" then
                activeCoroutines["achievement_char_points"] = nil
                return
            end
        end
        C_Timer.After(0, resumeCharPoints)
    end
    resumeCharPoints()
end

-- ACHIEVEMENT REWARD SCANNER

---Scan achievement rewards and categorize them (mount, pet, toy, transmog, etc.)
---@return table|nil Reward info {type, itemID, itemName, icon}
function WarbandNexus:GetAchievementRewardInfo(achievementID)
    if not achievementID then return nil end
    
    local rewardItemID, rewardTitle
    local success, ret1, ret2 = pcall(GetAchievementReward, achievementID)
    if success then
        if type(ret1) == "number" then rewardItemID = ret1 end
        if type(ret2) == "string" and ret2 ~= "" then
            rewardTitle = ret2
        elseif type(ret1) == "string" and ret1 ~= "" then
            rewardTitle = ret1
        end
    end
    
    -- Title reward
    if rewardTitle and not (issecretvalue and issecretvalue(rewardTitle)) and rewardTitle ~= "" then
        local _, name, _, _, _, _, _, _, _, icon = GetAchievementInfo(achievementID)
        local safeName = (name and not (issecretvalue and issecretvalue(name))) and name or nil
        return {
            type = "title",
            title = rewardTitle,
            achievementName = safeName,
            achievementID = achievementID,
            icon = icon or 134400
        }
    end
    
    -- Item reward (mount, pet, toy, transmog)
    if rewardItemID then
        local GetItemInfoFn = C_Item and C_Item.GetItemInfo or GetItemInfo
        local itemName, _, _, _, _, _, _, _, _, itemIcon = GetItemInfoFn(rewardItemID)
        if not itemName then
            local item = Item:CreateFromItemID(rewardItemID)
            if item then
                item:ContinueOnItemLoad(function()
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage(E.ITEM_METADATA_READY, achievementID)
                    end
                end)
            end
            -- Return text-only fallback from GetAchievementInfo while item loads
            local infoOk, _, _, _, _, _, _, _, _, _, _, achRewardText = pcall(GetAchievementInfo, achievementID)
            if infoOk and achRewardText and achRewardText ~= "" then
                return { type = "item", itemID = rewardItemID, itemName = achRewardText, icon = nil, achievementID = achievementID }
            end
            return nil
        end
        
        -- Determine item type
        local rewardType = "item"
        if C_MountJournal and C_MountJournal.GetMountFromItem and C_MountJournal.GetMountFromItem(rewardItemID) then
            rewardType = "mount"
        elseif C_PetJournal and C_PetJournal.GetPetInfoByItemID and C_PetJournal.GetPetInfoByItemID(rewardItemID) then
            rewardType = "pet"
        elseif C_ToyBox and C_ToyBox.GetToyInfo and C_ToyBox.GetToyInfo(rewardItemID) then
            rewardType = "toy"
        end
        
        return {
            type = rewardType,
            itemID = rewardItemID,
            itemName = itemName,
            icon = itemIcon,
            achievementID = achievementID
        }
    end
    
    -- Final fallback: GetAchievementInfo's rewardText covers rewards
    -- not exposed by GetAchievementReward (e.g. "Reward: Pathfinder's Overcoat")
    local infoOk, _, _, _, _, _, _, _, _, _, _, fallbackRewardText = pcall(GetAchievementInfo, achievementID)
    if infoOk and fallbackRewardText and fallbackRewardText ~= "" then
        return {
            type = "text",
            title = fallbackRewardText,
            achievementID = achievementID,
        }
    end
    
    return nil
end

---Add achievement link to item description
---@return table Enhanced item data with achievement link
function WarbandNexus:EnhanceItemWithAchievement(itemData, achievementID)
    if not itemData or not achievementID then return itemData end
    
    local _, achievementName, _, _, _, _, _, _, _, achievementIcon = GetAchievementInfo(achievementID)
    if achievementName then
        itemData.sourceAchievement = achievementID
        itemData.sourceAchievementName = achievementName
        itemData.sourceAchievementIcon = achievementIcon
        local fromAchLabel = (ns.L and ns.L["PARSE_FROM_ACHIEVEMENT"]) or "From Achievement"
        itemData.description = (itemData.description or "") .. "\n\n|cff00ff00" .. fromAchLabel .. ":|r " .. achievementName
    end
    
    return itemData
end
