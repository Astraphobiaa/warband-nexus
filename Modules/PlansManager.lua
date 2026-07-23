--[[
    Warband Nexus - Plans Manager Module
    Handles CRUD operations for user plans (mounts, pets, toys, recipes)
    
    Plans allow users to track collection goals with source information
    and material requirements.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local Constants = ns.Constants
local E = Constants.EVENTS
local issecretvalue = issecretvalue
local IsDebugModeEnabled = ns.IsDebugModeEnabled

---@return string|nil text safe for :find/:match/:gsub (nil when secret or empty)
local function SafeTextForStringOps(text)
    if not text or text == "" then return nil end
    if issecretvalue and issecretvalue(text) then return nil end
    return text
end

-- Unique AceEvent handler identity for PlansManager
local PlansManagerEvents = {}


-- GetIllusions() is huge; To-Do / tracker call CheckPlanProgress many times per redraw.
-- Short TTL avoids O(plans * illusions) while staying fresh enough for collection learns.
local illusionCollectedById = nil
local illusionLookupCacheAt = 0
local ILLUSION_LOOKUP_CACHE_TTL = 4

local function InvalidateIllusionLookupCache()
    illusionCollectedById = nil
    illusionLookupCacheAt = 0
end

ns.InvalidateIllusionLookupCache = InvalidateIllusionLookupCache

local function GetIllusionCollectedForPlanId(illusionKey)
    if not illusionKey or illusionKey <= 0 then return false end
    local now = GetTime()
    if not illusionCollectedById or (now - illusionLookupCacheAt) > ILLUSION_LOOKUP_CACHE_TTL then
        InvalidateIllusionLookupCache()
        illusionLookupCacheAt = now
        illusionCollectedById = {}
        if C_TransmogCollection and C_TransmogCollection.GetIllusions then
            local list = C_TransmogCollection.GetIllusions()
            if list then
                for ii = 1, #list do
                    local info = list[ii]
                    if info then
                        local rawColl = info.isCollected
                        local coll = false
                        if not (issecretvalue and issecretvalue(rawColl)) and rawColl == true then
                            coll = true
                        end
                        if info.sourceID then
                            local sid = info.sourceID
                            if coll then
                                illusionCollectedById[sid] = true
                            elseif illusionCollectedById[sid] == nil then
                                illusionCollectedById[sid] = false
                            end
                        end
                        if info.visualID then
                            local vid = info.visualID
                            if coll then
                                illusionCollectedById[vid] = true
                            elseif illusionCollectedById[vid] == nil then
                                illusionCollectedById[vid] = false
                            end
                        end
                    end
                end
            end
        end
    end
    return illusionCollectedById[illusionKey] == true
end

-- PLAN TYPES

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

-- PLAN LOOKUP INDEX (O(1) Hash Table)
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
    
    local wvIdx = self._weeklyVaultPlansByCharKey
    if not wvIdx then
        wvIdx = {}
        self._weeklyVaultPlansByCharKey = wvIdx
    else
        for k in pairs(wvIdx) do
            wvIdx[k] = nil
        end
    end

    local wvList = self._weeklyVaultPlansList
    if not wvList then
        wvList = {}
        self._weeklyVaultPlansList = wvList
    else
        for i = #wvList, 1, -1 do
            wvList[i] = nil
        end
    end

    local byId = self._plansById
    if not byId then
        byId = {}
        self._plansById = byId
    else
        for k in pairs(byId) do
            byId[k] = nil
        end
    end

    local inc = self._incompleteTodoPlansList
    if not inc then
        inc = {}
        self._incompleteTodoPlansList = inc
    else
        for i = #inc, 1, -1 do
            inc[i] = nil
        end
    end

    local pc = self._plansByCollectibleKey
    if not pc then
        pc = {
            mount = {},
            pet = {},
            toy = {},
            achievement = {},
            illusion = {},
            title = {},
        }
        self._plansByCollectibleKey = pc
    else
        for _, sub in pairs(pc) do
            for k in pairs(sub) do
                sub[k] = nil
            end
        end
    end

    local function pushCollectiblePlan(ptype, entityId, plan)
        if not entityId or entityId == 0 then return end
        local sub = pc[ptype]
        if not sub then return end
        local arr = sub[entityId]
        if not arr then
            arr = {}
            sub[entityId] = arr
        end
        arr[#arr + 1] = plan
    end

    -- Rebuild from db.global.plans
    if self.db and self.db.global and self.db.global.plans then
        local _plans = self.db.global.plans
        for _i = 1, #_plans do
            local plan = _plans[_i]
            if plan.id then
                byId[plan.id] = plan
            end
            if plan.type == PLAN_TYPES.MOUNT and plan.mountID then
                pushCollectiblePlan("mount", plan.mountID, plan)
            elseif plan.type == PLAN_TYPES.PET and plan.speciesID then
                pushCollectiblePlan("pet", plan.speciesID, plan)
            elseif plan.type == PLAN_TYPES.TOY and plan.itemID then
                pushCollectiblePlan("toy", plan.itemID, plan)
            elseif plan.type == PLAN_TYPES.ACHIEVEMENT and plan.achievementID then
                pushCollectiblePlan("achievement", plan.achievementID, plan)
            elseif plan.type == PLAN_TYPES.ILLUSION then
                if plan.illusionID then
                    pushCollectiblePlan("illusion", plan.illusionID, plan)
                end
                if plan.sourceID then
                    pushCollectiblePlan("illusion", plan.sourceID, plan)
                end
            elseif plan.type == PLAN_TYPES.TITLE and plan.titleID then
                pushCollectiblePlan("title", plan.titleID, plan)
            end
            if plan.type == PLAN_TYPES.WEEKLY_VAULT then
                wvList[#wvList + 1] = plan
                if ns.Utilities and ns.Utilities.GetCharacterKey then
                    local pk = ns.Utilities:GetCharacterKey(plan.characterName, plan.characterRealm)
                    if pk and pk ~= "" then
                        local arr = wvIdx[pk]
                        if not arr then
                            arr = {}
                            wvIdx[pk] = arr
                        end
                        arr[#arr + 1] = plan
                    end
                end
            end
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
            if not plan.completed and not plan.completionNotified then
                inc[#inc + 1] = plan
            end
        end
    end
    
    -- Also check custom plans
    if self.db and self.db.global and self.db.global.customPlans then
        local _customPlans = self.db.global.customPlans
        for _i = 1, #_customPlans do
            local plan = _customPlans[_i]
            if plan.id then
                byId[plan.id] = plan
            end
            if plan.itemID then
                self.planCache.itemIDs[plan.itemID] = true
            end
        end
    end
end

-- PLAN TRACKING & NOTIFICATIONS

--[[
    Initialize plan completion tracking
    Registers events to check for completed plans
]]
function WarbandNexus:InitializePlanTracking()
    -- PLAYER_LOGIN fires before this init runs, so an AceEvent registration here can never
    -- fire — and it silently replaced Core's PLAYER_LOGIN handler (one handler per event per
    -- object). The direct call below covers login, /reload, and re-init.
    if self.OnVaultPlanSessionReset then
        self:OnVaultPlanSessionReset()
    end
    -- Build O(1) lookup index
    self:InitializePlanCache()
    
    -- WN_COLLECTIBLE_OBTAINED: Handled by unified dispatch in NotificationManager.
    -- Do NOT register here — AceEvent allows only one handler per event per object.
    -- The dispatch handler in NotificationManager calls OnPlanCollectionUpdated.
    
    -- Weekly vault progress — listen to PvECacheService message (single event owner)
    -- WEEKLY_REWARDS_UPDATE / CHALLENGE_MODE_COMPLETED / UPDATE_INSTANCE_INFO: owned by PvECacheService
    -- NOTE: Uses PlansManagerEvents as 'self' key to avoid overwriting PvEUI's handler.
    WarbandNexus.RegisterMessage(PlansManagerEvents, Constants.EVENTS.PVE_UPDATED, function()
        if WarbandNexus._DeferVaultPlanCheckFromPvE then
            WarbandNexus:_DeferVaultPlanCheckFromPvE()
        end
    end)
    -- The live rewards API can hydrate from false to true while the persisted PvE signature is
    -- already true, so WEEKLY_REWARDS_UPDATE does not always produce PVE_UPDATED. Use the separate
    -- event sink and the same debounce to refresh cached To-Do cards after the server response.
    WarbandNexus.RegisterEvent(PlansManagerEvents, "WEEKLY_REWARDS_UPDATE", function()
        if WarbandNexus._DeferVaultPlanCheckFromPvE then
            WarbandNexus:_DeferVaultPlanCheckFromPvE()
        end
    end)
    -- ENCOUNTER_END still needed (not a PvE cache event, fires when boss is killed)
    self:RegisterEvent("ENCOUNTER_END", "OnPvEUpdateCheckPlans")
    
    -- Daily quest updates
    WarbandNexus.RegisterMessage(PlansManagerEvents, E.QUEST_PROGRESS_UPDATED, function(event)
        if WarbandNexus.OnDailyQuestProgressUpdated then
            WarbandNexus:OnDailyQuestProgressUpdated(event)
        end
    end)
    
    -- Keep plan source text up-to-date when collection scans complete (API > DB flow)
    local Constants = ns.Constants
    if Constants and Constants.EVENTS and Constants.EVENTS.COLLECTION_SCAN_COMPLETE then
        WarbandNexus.RegisterMessage(PlansManagerEvents, Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function()
            WarbandNexus:UpdatePlanSources()
        end)
    end
    
    -- Initial checks after APIs are ready
    C_Timer.After(3, function()
        self:CheckPlansForCompletion()
        self:CheckWeeklyReset()
        self:UpdatePlanSources()
        self:PreResolvePlansData()
    end)
end

-- PRE-RESOLVE PLAN DATA (Login-Time API Resolution)
--[[
    Resolve all plan display data (name, icon, source, progress) at login time
    and store results in DB. The Plans tab then reads ONLY from DB fields.
    
    Resolved fields per plan:
      - resolvedName: Localized name from API
      - resolvedIcon: Icon texture from API
      - resolvedSource: Source description from API
      - resolvedCollected: Whether the collectible is obtained
      - resolvedCanObtain: Whether materials are available (recipes)
      - resolvedAt: Timestamp of last resolution
]]
function WarbandNexus:PreResolvePlansData()
    if not self.db or not self.db.global then return end
    
    local plans = self.db.global.plans
    local customPlans = self.db.global.customPlans
    local now = time()
    
    if plans then
        for i = 1, #plans do
            self:_ResolveSinglePlan(plans[i], now)
        end
    end
    
    if customPlans then
        for i = 1, #customPlans do
            self:_ResolveSinglePlan(customPlans[i], now)
        end
    end
    
    self:SendMessage(E.PLANS_UPDATED, { action = "pre_resolved" })
end

function WarbandNexus:_ResolveSinglePlan(plan, now)
    if not plan then return end
    
    plan.resolvedName = self:GetPlanDisplayName(plan)
    plan.resolvedIcon = self:GetPlanDisplayIcon(plan)
    plan.resolvedSource = self:GetPlanDisplaySource(plan)
    plan.resolvedAt = now
    
    local progress = self:CheckPlanProgress(plan)
    if progress then
        plan.resolvedCollected = progress.collected or false
        plan.resolvedCanObtain = progress.canObtain or false
    end
end

--[[
    DB-only getters for Plans tab (no API calls)
    These read pre-resolved fields stored at login time.
    Falls back to stored plan fields if resolution hasn't happened yet.
]]
function WarbandNexus:GetResolvedPlanName(plan)
    if not plan then return ((ns.L and ns.L["UNKNOWN"]) or "Unknown") end
    return plan.resolvedName or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
end

function WarbandNexus:GetResolvedPlanIcon(plan)
    if not plan then return "Interface\\Icons\\INV_Misc_Note_06" end
    -- Toys: always try API (Blizzard_Collections may not have been loaded at resolve time)
    if plan.type == "toy" and plan.itemID then
        local apiIcon = self:GetPlanDisplayIcon(plan)
        if apiIcon and apiIcon ~= "Interface\\Icons\\INV_Misc_Note_06" then
            return apiIcon
        end
    end
    return plan.resolvedIcon or plan.icon or "Interface\\Icons\\INV_Misc_Note_06"
end

function WarbandNexus:GetResolvedPlanSource(plan)
    if not plan then return "" end
    return plan.resolvedSource or plan.source or ""
end

function WarbandNexus:GetResolvedPlanProgress(plan)
    if not plan then return { collected = false, canObtain = false } end
    return {
        collected = plan.resolvedCollected or false,
        canObtain = plan.resolvedCanObtain or false,
        progress = plan.progress,
        slots = plan.slots,
    }
end

--[[
    Event handler for collection updates
    Checks if any plans were completed
]]
function WarbandNexus:OnPlanCollectionUpdated(event, ...)
    -- Immediate match on payload (WN_COLLECTIBLE_OBTAINED uses id=, not mountID=/speciesID=).
    -- Deferred CheckPlansForCompletion can miss mounts when GetMountInfoByID(..., isCollected) is secret right after learn.
    local data = ...
    if data and type(data) == "table" and data.type then
        self:TryCompletePlanFromCollectibleObtained(data)
    end

    -- Debounce full scan for plans not tied to this event (and late API consistency)
    if self.planCheckTimer then
        self.planCheckTimer:Cancel()
    end
    self.planCheckTimer = C_Timer.NewTimer(0.5, function()
        self.planCheckTimer = nil
        self:CheckPlansForCompletion()
    end)
end

---Run pending plan completion check on PLAYER_LOGOUT.
function WarbandNexus:FlushPlansOnLogout()
    if self.planCheckTimer then
        self.planCheckTimer:Cancel()
        self.planCheckTimer = nil
        self:CheckPlansForCompletion()
    end
end


--[[
    Rebuild list of plans that still need completion checks (not completed, not notified).
    Keeps _incompleteTodoPlansList in sync after RefreshPlanCache or mid-session completions.
]]
function WarbandNexus:RebuildIncompleteTodoPlansList()
    local list = self._incompleteTodoPlansList
    if not list then
        list = {}
        self._incompleteTodoPlansList = list
    else
        for i = #list, 1, -1 do
            list[i] = nil
        end
    end
    if not self.db or not self.db.global or not self.db.global.plans then return end
    local plans = self.db.global.plans
    for i = 1, #plans do
        local plan = plans[i]
        if plan and not plan.completed and not plan.completionNotified then
            list[#list + 1] = plan
        end
    end
end

--[[
    Check all active plans for completion
    Shows notifications for newly completed plans
]]
function WarbandNexus:CheckPlansForCompletion()
    if not self.db or not self.db.global or not self.db.global.plans then
        return
    end

    local list = self._incompleteTodoPlansList
    local useList = list and #list > 0

    local anyCompleted = false
    local function processPlan(plan)
        if not plan or plan.completed or plan.completionNotified then return end
        local progress = self:CheckPlanProgress(plan)
        if not (progress and progress.collected) then return end
        if plan.type == "title" then
            self:SendMessage(E.COLLECTIBLE_OBTAINED, {
                type = "title",
                id = plan.titleID,
                name = self:GetPlanDisplayName(plan),
                icon = self:GetPlanDisplayIcon(plan)
            })
        end
        self:ShowPlanCompletedNotification(plan)
        plan.completed = true
        plan.completionNotified = true
        plan.resolvedCollected = true
        self:SendMessage(E.PLANS_UPDATED, {
            action = "progress_changed",
            planID = plan.id,
            planType = plan.type,
        })
        anyCompleted = true
    end

    if useList then
        for i = 1, #list do
            processPlan(list[i])
        end
    else
        local _plans = self.db.global.plans
        for _i = 1, #_plans do
            local plan = _plans[_i]
            processPlan(plan)
        end
    end

    if anyCompleted then
        self:RebuildIncompleteTodoPlansList()
    end
end

--[[
    When WN_COLLECTIBLE_OBTAINED fires, complete matching To-Do plan immediately (chat + toast).
    Payload uses type + id; plan rows use mountID, speciesID, itemID, etc.
    @param data table e.g. { type = "mount", id = mountID, name, icon }
    @return table|nil completed plan
]]
function WarbandNexus:TryCompletePlanFromCollectibleObtained(data)
    if not data or type(data) ~= "table" or not data.type then return nil end
    if not self.db or not self.db.global or not self.db.global.plans then return nil end

    local function applyCollectibleCompletion(plan)
        self:ShowPlanCompletedNotification(plan)
        plan.completed = true
        plan.completionNotified = true
        plan.resolvedCollected = true
        self:SendMessage(E.PLANS_UPDATED, {
            action = "progress_changed",
            planID = plan.id,
            planType = plan.type,
        })
        self:RebuildIncompleteTodoPlansList()
        return plan
    end

    local dType = data.type
    local idMount = data.mountID or data.id
    local idPet = data.speciesID or data.id
    local idToy = data.itemID or data.id
    local idAch = data.achievementID or data.id
    local idIll = data.illusionID or data.id
    local idTitle = data.titleID or data.id

    local function tryBucket(sub, lookupId)
        if not sub or not lookupId then return nil end
        local arr = sub[lookupId]
        if not arr then return nil end
        for i = 1, #arr do
            local plan = arr[i]
            if plan and not plan.completed and not plan.completionNotified and plan.type == dType then
                return applyCollectibleCompletion(plan)
            end
        end
        return nil
    end

    local pc = self._plansByCollectibleKey
    if pc then
        if dType == "illusion" then
            local done = tryBucket(pc.illusion, idIll)
            if done then return done end
            if data.sourceID and data.sourceID ~= idIll then
                done = tryBucket(pc.illusion, data.sourceID)
                if done then return done end
            end
        else
            local sub = pc[dType]
            local lookupId = (dType == "mount" and idMount)
                or (dType == "pet" and idPet)
                or (dType == "toy" and idToy)
                or (dType == "achievement" and idAch)
                or (dType == "title" and idTitle)
            local done = tryBucket(sub, lookupId)
            if done then return done end
        end
    end

    -- Fallback: full scan (unknown dType key, cold _plansByCollectibleKey, or edge match)
    local _plans = self.db.global.plans
    for _i = 1, #_plans do
        local plan = _plans[_i]
        if not plan.completed and not plan.completionNotified and plan.type == dType then
            local matched = false
            if plan.type == "mount" and plan.mountID and idMount then
                matched = (plan.mountID == idMount)
            elseif plan.type == "pet" and plan.speciesID and idPet then
                matched = (plan.speciesID == idPet)
            elseif plan.type == "toy" and plan.itemID and idToy then
                matched = (plan.itemID == idToy)
            elseif plan.type == "achievement" and plan.achievementID and idAch then
                matched = (plan.achievementID == idAch)
            elseif plan.type == "illusion" and plan.illusionID and idIll then
                matched = (plan.illusionID == idIll)
            elseif plan.type == "illusion" and plan.sourceID and (data.sourceID or idIll) then
                matched = (plan.sourceID == data.sourceID) or (plan.sourceID == idIll)
            elseif plan.type == "title" and plan.titleID and idTitle then
                matched = (plan.titleID == idTitle)
            elseif plan.name and data.name and type(data.name) == "string" and type(plan.name) == "string" then
                if not (issecretvalue and issecretvalue(data.name)) then
                    matched = (plan.name == data.name)
                end
            end
            if matched then
                return applyCollectibleCompletion(plan)
            end
        end
    end
    return nil
end

--[[
    Check if a collected item completes an active plan
    @param data table from WN_COLLECTIBLE_OBTAINED or equivalent
    @return table|nil - The completed plan or nil
]]
function WarbandNexus:CheckItemForPlanCompletion(data)
    return self:TryCompletePlanFromCollectibleObtained(data)
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
            local rawTitle = SafeTextForStringOps(GetTitleName(plan.titleID))
            if rawTitle then
                return rawTitle:gsub("^%s+", ""):gsub("%s+$", ""):gsub(",%s*$", "")
            end
        end
    elseif plan.type == "illusion" and plan.illusionID then
        -- Illusions: iterate collection to find by sourceID
        if C_TransmogCollection and C_TransmogCollection.GetIllusions then
            local illusions = C_TransmogCollection.GetIllusions()
            if illusions then
                for ii = 1, #illusions do
                    local illusionInfo = illusions[ii]
                    if illusionInfo.sourceID == plan.illusionID then
                        if illusionInfo.name and illusionInfo.name ~= "" then
                            return illusionInfo.name
                        end
                        break
                    end
                end
            end
        end
    elseif plan.type == "recipe" and plan.itemID then
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
    Mount/Pet: when plan.source is empty, resolves from C_MountJournal/C_PetJournal
    so My Plans shows the same source as the Mounts/Pets browser (e.g. "Voidstorm Fishing").
    @param plan table - Plan data
    @return string - Source description
]]
function WarbandNexus:GetPlanDisplaySource(plan)
    if not plan then return "" end
    local function IsPlaceholderSource(sourceText)
        local safe = SafeTextForStringOps(sourceText)
        if not safe then return true end
        local s = safe:gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then return true end
        local unknownSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        local sourceUnknown = (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
        local sourceNotAvailable = (ns.L and ns.L["SOURCE_NOT_AVAILABLE"]) or "Source information not available"
        return s == "Unknown" or s == unknownSource or s == sourceUnknown or s == sourceNotAvailable or s == "Legacy"
    end
    -- Achievement descriptions can be resolved from API.
    if plan.type == "achievement" and plan.achievementID then
        local _, _, _, _, _, _, _, description = GetAchievementInfo(plan.achievementID)
        local safeDesc = SafeTextForStringOps(description)
        if safeDesc then return safeDesc end
    end
    -- Stored source takes precedence when present.
    if plan.source and not IsPlaceholderSource(plan.source) then
        return plan.source
    end
    -- Mount: resolve from journal so My Plans matches Mounts tab (e.g. Nether-Warped Drake -> Voidstorm Fishing).
    if plan.type == "mount" and plan.mountID then
        if C_MountJournal and C_MountJournal.GetMountInfoExtraByID then
            local ok, displayID, description, source = pcall(C_MountJournal.GetMountInfoExtraByID, plan.mountID)
            if ok and source and type(source) == "string" and source ~= "" then
                if not (issecretvalue and issecretvalue(source)) then
                    return source
                end
            end
        end
        -- Fallback: collection metadata (e.g. Nether-Warped Drake when API returns empty)
        if self.ResolveCollectionMetadata then
            local meta = self:ResolveCollectionMetadata("mount", plan.mountID)
            if meta and type(meta.source) == "string" and meta.source ~= "" then
                return meta.source
            end
        end
        -- Fallback: CollectibleSourceDB when WoW API returns empty for known mounts (e.g. Nether-Warped Drake from fishing)
        if ns.CollectibleSourceDB and ns.CollectibleSourceDB.GetSourceStringForMount then
            local dbSource = ns.CollectibleSourceDB:GetSourceStringForMount(plan.mountID)
            if dbSource and dbSource ~= "" then
                return dbSource
            end
        end
    end
    -- Pet: resolve from journal so My Plans matches Pets tab.
    if plan.type == "pet" and plan.speciesID and C_PetJournal and C_PetJournal.GetPetInfoBySpeciesID then
        local ok, name, icon, petType, creatureID, sourceText, description, isWild, canBattle, tradeable, unique, obtainable = pcall(C_PetJournal.GetPetInfoBySpeciesID, plan.speciesID)
        if ok and sourceText and type(sourceText) == "string" and sourceText ~= "" then
            if issecretvalue and issecretvalue(sourceText) then return "" end
            return sourceText
        end
    end
    return ""
end

--[[
    Resolve the localized icon for a plan using WoW API.
    @param plan table - Plan data
    @return number|string|nil - Icon texture ID or path
]]
function WarbandNexus:GetPlanDisplayIcon(plan)
    if not plan then return "Interface\\Icons\\INV_Misc_Note_06" end
    
    -- Ensure Blizzard_Collections is loaded (required for mount/pet/toy API icons)
    if ns.EnsureBlizzardCollectionsLoaded then ns.EnsureBlizzardCollectionsLoaded() end
    
    -- Category-specific fallback icons (mirrors NotificationManager.CATEGORY_ICONS)
    local PLAN_TYPE_ICONS = {
        mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
        pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
        toy = "Interface\\Icons\\INV_Misc_Toy_07",
        illusion = "Interface\\Icons\\INV_Enchant_Disenchant",
        achievement = "Interface\\Icons\\Achievement_Quests_Completed_08",
        title = "Interface\\Icons\\INV_Scroll_11",
        recipe = "Interface\\Icons\\INV_Scroll_03",
        custom = "Interface\\Icons\\INV_Misc_Note_06",
        vault = "Interface\\Icons\\achievement_guildperk_bountifulbags",
        quest = "Interface\\Icons\\INV_Misc_Map_01",
    }
    
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
        if C_ToyBox and C_ToyBox.GetToyInfo then
            local _, _, icon = C_ToyBox.GetToyInfo(plan.itemID)
            if icon then return icon end
        end
        local icon = GetItemIcon(plan.itemID)
        if icon then return icon end
    elseif plan.type == "recipe" and plan.itemID then
        local icon = GetItemIcon(plan.itemID)
        if icon then return icon end
    end
    
    -- Fallback chain: stored icon → plan type icon → generic note icon
    return plan.icon or PLAN_TYPE_ICONS[plan.type] or "Interface\\Icons\\INV_Misc_Note_06"
end

--[[
    Show a toast notification for a completed plan
    @param plan table - The completed plan
]]
function WarbandNexus:ShowPlanCompletedNotification(plan)
    local displayName = self:GetPlanDisplayName(plan)
    local displayIcon = self:GetPlanDisplayIcon(plan)
    
    -- Achievement plans may also fire WN_COLLECTIBLE_OBTAINED (achievement toast) in the same
    -- burst; both toasts are intentional (plan lane + achievement lane stay separate).
    self:SendMessage(E.PLAN_COMPLETED, {
        planType = plan.type,
        name = displayName,
        icon = displayIcon
    })
    
    self:Print("|cff00ff00" .. ((ns.L and ns.L["PLAN_COMPLETED"]) or "Plan completed: ") .. "|r" .. displayName)
end


---Check if a Blizzard daily reset has occurred since the given timestamp.
---Uses C_DateAndTime.GetSecondsUntilDailyReset to derive the last reset moment.
---@return boolean
function WarbandNexus:HasDailyResetOccurredSince(sinceTimestamp)
    if not sinceTimestamp or sinceTimestamp == 0 then return true end
    local secondsUntilReset = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset() or 0
    local lastResetTime = time() + secondsUntilReset - 86400  -- last reset = next reset - 24h
    return sinceTimestamp < lastResetTime
end

---Check if a Blizzard weekly reset has occurred since the given timestamp.
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

    local _customPlans = self.db.global.customPlans
    for _i = 1, #_customPlans do
        local plan = _customPlans[_i]
        local rc = plan.resetCycle
        if rc and rc.enabled and plan.completed then
            local shouldReset = false
            if rc.resetType == "daily" then
                shouldReset = self:HasDailyResetOccurredSince(rc.lastResetTime or 0)
            elseif rc.resetType == "weekly" then
                shouldReset = self:HasWeeklyResetOccurredSince(rc.lastResetTime or 0)
            end

            if shouldReset then
                if rc.infiniteRepeat then
                    -- Repeat until the user deletes the plan: reopen next cycle, never exhaust.
                    plan.completed = false
                    plan.completionNotified = false
                    rc.lastResetTime = now
                    rc.completedAt = nil
                    changed = true
                else
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
                        plan.completionNotified = false  -- Reset notification flag for next cycle
                        rc.lastResetTime = now
                        rc.completedAt = nil
                        changed = true
                    end
                end
            end
        end
    end

    if changed then
        self:SendMessage(E.PLANS_UPDATED, { action = "recurring_reset" })
    end
end


-- CRUD OPERATIONS

---Build AddPlan() payload for a journal achievement (single source for Blizzard UI quick-add).
---@return table|nil
function WarbandNexus:BuildAchievementPlanPayload(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return nil end
    if issecretvalue and issecretvalue(achievementID) then return nil end

    local ok, id, name, points, _, _, _, _, _, icon, _, rewardText = pcall(GetAchievementInfo, achievementID)
    if not ok or not id or id ~= achievementID then return nil end
    if issecretvalue then
        if name and issecretvalue(name) then name = nil end
        if points and issecretvalue(points) then points = nil end
        if icon and issecretvalue(icon) then icon = nil end
        if rewardText and issecretvalue(rewardText) then rewardText = nil end
    end

    local sourceText = ""
    if GetAchievementCategory then
        local okc, catID = pcall(GetAchievementCategory, achievementID)
        if okc and type(catID) == "number" and catID > 0 and GetCategoryInfo then
            local oki, catTitle = pcall(GetCategoryInfo, catID)
            if oki and type(catTitle) == "string" and catTitle ~= "" and not (issecretvalue and issecretvalue(catTitle)) then
                sourceText = catTitle
            end
        end
    end

    local rewardLine = nil
    if self.GetAchievementRewardInfo then
        local info = self:GetAchievementRewardInfo(achievementID)
        if info then
            rewardLine = info.title or info.itemName
        end
    end
    if not rewardLine or rewardLine == "" then
        rewardLine = (type(rewardText) == "string" and rewardText ~= "" and not (issecretvalue and issecretvalue(rewardText))) and rewardText or nil
    end

    return {
        type = PLAN_TYPES.ACHIEVEMENT,
        achievementID = achievementID,
        name = name or ((ns.L and ns.L["HIDDEN_ACHIEVEMENT"]) or "Hidden Achievement"),
        icon = icon,
        points = (type(points) == "number" and points >= 0) and points or nil,
        source = sourceText,
        rewardText = rewardLine,
    }
end

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
    
    -- Prevent duplicate plans for the same collectible/achievement
    if planType == "achievement" and planData.achievementID and self:IsAchievementPlanned(planData.achievementID) then return nil end
    if planType == "mount" and planData.mountID and self:IsMountPlanned(planData.mountID) then return nil end
    if planType == "pet" and planData.speciesID and self:IsPetPlanned(planData.speciesID) then return nil end
    if planType == "toy" and planData.itemID and self:IsItemPlanned("toy", planData.itemID) then return nil end
    if planType == "illusion" and planData.illusionID and self:IsIllusionPlanned(planData.illusionID) then return nil end
    if planType == "title" and planData.titleID and self:IsTitlePlanned(planData.titleID) then return nil end
    if planType == "recipe" and planData.itemID and self:IsItemPlanned(planType, planData.itemID) then return nil end
    
    -- Generate unique ID
    local planID = self.db.global.plansNextID or 1
    self.db.global.plansNextID = planID + 1
    
    local sourceText = SafeTextForStringOps(planData.source) or ""
    sourceText = sourceText:gsub("^%s+", ""):gsub("%s+$", "")
    do
        local unknownSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        local sourceUnknown = (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
        local sourceNotAvailable = (ns.L and ns.L["SOURCE_NOT_AVAILABLE"]) or "Source information not available"
        if sourceText == "Unknown" or sourceText == unknownSource or sourceText == sourceUnknown or sourceText == sourceNotAvailable or sourceText == "Legacy" then
            sourceText = ""
        end
    end

    local plan = {
        id = planID,
        type = planType,
        itemID = planData.itemID,
        name = planData.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"),
        icon = planData.icon,
        source = sourceText,
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
    
    -- Resolve display data immediately so My Plans renders complete info
    self:_ResolveSinglePlan(plan, time())
    
    -- Refresh lookup index
    self:RefreshPlanCache()
    
    -- Fire event for UI update (API > DB > UI)
    self:SendMessage(E.PLANS_UPDATED, {
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
    local function resetTryCountsForRemovedPlan(plan)
        if not plan or not self.ResetTryCount then return end
        local t = plan.type
        if t == "mount" and plan.mountID then
            self:ResetTryCount("mount", plan.mountID)
        elseif t == "pet" and plan.speciesID then
            self:ResetTryCount("pet", plan.speciesID)
        elseif t == "toy" and plan.itemID then
            self:ResetTryCount("toy", plan.itemID)
        elseif t == "illusion" then
            if plan.sourceID then self:ResetTryCount("illusion", plan.sourceID) end
            if plan.illusionID and plan.illusionID ~= plan.sourceID then
                self:ResetTryCount("illusion", plan.illusionID)
            end
        end
    end

    local function removeFromList(list, id, label)
        if not list then return false end
        for i = 1, #list do
            if list[i].id == id then
                local plan = list[i]
                resetTryCountsForRemovedPlan(plan)
                local name = plan.name
                local planType = plan.type
                table.remove(list, i)
                self:RefreshPlanCache()
                self:SendMessage(E.PLANS_UPDATED, {
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
        self:SendMessage(E.PLANS_UPDATED, {
            action = "reset_completed",
            removedCount = removedCount,
        })
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

    local updated = false
    local plans = self.db.global.plans
    if not plans then return end
    
    local function IsPlaceholderSource(sourceText)
        local safe = SafeTextForStringOps(sourceText)
        if not safe then return true end
        local s = safe:gsub("^%s+", ""):gsub("%s+$", "")
        if s == "" then return true end
        local unknownSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
        local sourceUnknown = (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
        local sourceNotAvailable = (ns.L and ns.L["SOURCE_NOT_AVAILABLE"]) or "Source information not available"
        return s == "Unknown" or s == unknownSource or s == sourceUnknown or s == sourceNotAvailable or s == "Legacy"
    end

    for i = 1, #plans do
        local plan = plans[i]
        local newSource = nil
        
        if plan.type == "pet" and plan.speciesID then
            local meta = self.ResolveCollectionMetadata and self:ResolveCollectionMetadata("pet", plan.speciesID)
            if meta and type(meta.source) == "string" and meta.source ~= "" then
                newSource = meta.source
            end
        elseif plan.type == "mount" and plan.mountID then
            local meta = self.ResolveCollectionMetadata and self:ResolveCollectionMetadata("mount", plan.mountID)
            if meta and type(meta.source) == "string" and meta.source ~= "" then
                newSource = meta.source
            end
        elseif plan.type == "toy" and plan.itemID then
            local meta = self.ResolveCollectionMetadata and self:ResolveCollectionMetadata("toy", plan.itemID)
            if meta and type(meta.source) == "string" and meta.source ~= "" then
                newSource = meta.source
            end
        end
        
        if newSource and (IsPlaceholderSource(plan.source) or newSource ~= plan.source) then
            plan.source = newSource
            updated = true
        end
    end
    
    -- Notify UI only if sources actually changed
    if updated then
        self:SendMessage(E.PLANS_UPDATED, {
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
    Total plan rows in db.global.plans + db.global.customPlans (no merged table allocation).
]]
function WarbandNexus:GetActivePlanTotalCount()
    if not self.db or not self.db.global then return 0 end
    local n = 0
    if self.db.global.plans then
        n = n + #self.db.global.plans
    end
    if self.db.global.customPlans then
        n = n + #self.db.global.customPlans
    end
    return n
end

--[[
    Header / summary: incomplete non–daily_quests plans (same rules as Plans tab title count).
]]
function WarbandNexus:GetActiveNonDailyIncompleteCount()
    if not self.db or not self.db.global then return 0 end
    local n = 0
    local memo = {}
    local function planIncomplete(plan)
        if not plan or plan.type == "daily_quests" then return false end
        local c = memo[plan]
        if c ~= nil then return c end
        c = not self:IsActivePlanComplete(plan)
        memo[plan] = c
        return c
    end
    local function tally(list)
        if not list then return end
        for i = 1, #list do
            if planIncomplete(list[i]) then
                n = n + 1
            end
        end
    end
    tally(self.db.global.plans)
    tally(self.db.global.customPlans)
    return n
end

--- Statistics tab: completed vs total saved To-Do rows (plans + customPlans).
---@return table { total = number, completed = number }
function WarbandNexus:GetPlansStatisticsCounts()
    if not self.db or not self.db.global then
        return { total = 0, completed = 0 }
    end
    local total, completed = 0, 0
    local memo = {}
    local function tally(list)
        if not list then return end
        for i = 1, #list do
            local plan = list[i]
            total = total + 1
            local isComplete = memo[plan]
            if isComplete == nil then
                isComplete = self:IsActivePlanComplete(plan) == true
                memo[plan] = isComplete
            end
            if isComplete then
                completed = completed + 1
            end
        end
    end
    tally(self.db.global.plans)
    tally(self.db.global.customPlans)
    return { total = total, completed = completed }
end

--[[
    Get a specific plan by ID
    @param planID number - Plan ID
    @return table|nil - Plan data or nil
]]
function WarbandNexus:GetPlanByID(planID)
    if not planID then return nil end

    local byId = self._plansById
    if byId then
        local p = byId[planID]
        if p then return p end
    end

    if self.db and self.db.global then
        if self.db.global.plans then
            local _plans = self.db.global.plans
            for _i = 1, #_plans do
                local plan = _plans[_i]
                if plan.id == planID then
                    return plan
                end
            end
        end
        if self.db.global.customPlans then
            local _customPlans = self.db.global.customPlans
            for _i = 1, #_customPlans do
                local plan = _customPlans[_i]
                if plan.id == planID then
                    return plan
                end
            end
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

---Check whether an achievement is tracked in Blizzard objectives.
---@return boolean
function WarbandNexus:IsAchievementTracked(achievementID)
    if not achievementID then return false end

    local contentTracking = C_ContentTracking
    if contentTracking and contentTracking.IsTracking then
        local ok, result = pcall(contentTracking.IsTracking, 2, achievementID)
        if ok then
            return result == true
        end
    end

    if GetTrackedAchievements then
        local tracked = { GetTrackedAchievements() }
        for i = 1, #tracked do
            if tracked[i] == achievementID then
                return true
            end
        end
    end

    return false
end

---Toggle achievement tracking in Blizzard objectives and broadcast event.
---@return boolean changed True when a toggle attempt was made
function WarbandNexus:ToggleAchievementTracking(achievementID)
    if not achievementID then return false end

    local trackedBefore = self:IsAchievementTracked(achievementID)
    local toggled = false

    local contentTracking = C_ContentTracking
    if contentTracking and contentTracking.ToggleTracking then
        local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 0
        local ok = pcall(contentTracking.ToggleTracking, 2, achievementID, stopType)
        toggled = ok == true
    else
        if trackedBefore then
            if RemoveTrackedAchievement then
                RemoveTrackedAchievement(achievementID)
                toggled = true
            end
        else
            if AddTrackedAchievement then
                AddTrackedAchievement(achievementID)
                toggled = true
            end
        end
    end

    if not toggled then return false end

    local trackedNow = self:IsAchievementTracked(achievementID)
    self:SendMessage(E.ACHIEVEMENT_TRACKING_UPDATED, {
        achievementID = achievementID,
        tracked = trackedNow,
        previousTracked = trackedBefore,
    })

    return true
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

-- COLLECTION DATA FETCHERS

-- SOURCE TEXT KEYWORDS (LOCALIZED)
-- Uses Blizzard globals and L[] keys to match API-localized source text
local function BuildSourceKeywords()
    local L = ns.L
    local keywords = {}
    local function add(val)
        if val and val ~= "" then
            keywords[#keywords + 1] = val .. ":"
        end
    end
    -- Blizzard BATTLE_PET_SOURCE_* globals (auto-localized)
    add(BATTLE_PET_SOURCE_1)  -- Drop
    add(BATTLE_PET_SOURCE_2)  -- Quest
    add(BATTLE_PET_SOURCE_3)  -- Vendor
    add(BATTLE_PET_SOURCE_4)  -- Profession
    add(BATTLE_PET_SOURCE_5)  -- Pet Battle
    add(BATTLE_PET_SOURCE_6)  -- Achievement
    add(BATTLE_PET_SOURCE_7)  -- World Event
    add(BATTLE_PET_SOURCE_8)  -- Promotion
    -- Blizzard standalone globals
    add(PVP)                   -- PvP
    add(FACTION)               -- Faction
    add(REPUTATION)            -- Reputation
    -- Locale keys for parsing (translated per language)
    if L then
        add(L["PARSE_SOLD_BY"])
        add(L["PARSE_CRAFTED"])
        add(L["PARSE_ZONE"])
        add(L["PARSE_COST"])
        add(L["PARSE_ARENA"])
        add(L["PARSE_DUNGEON"])
        add(L["PARSE_RAID"])
        add(L["PARSE_HOLIDAY"])
        add(L["PARSE_RATED"])
        add(L["PARSE_BATTLEGROUND"])
        add(L["PARSE_DISCOVERY"])
        add(L["PARSE_CONTAINED_IN"])
        add(L["PARSE_GARRISON"])
        add(L["PARSE_GARRISON_BUILDING"])
        add(L["SOURCE_TYPE_TRADING_POST"])
        add(L["SOURCE_TYPE_TREASURE"])
        add(L["PARSE_STORE"])
        add(L["PARSE_ORDER_HALL"])
        add(L["PARSE_COVENANT"])
        add(L["SOURCE_TYPE_RENOWN"])
        add(L["PARSE_FRIENDSHIP"])
        add(L["PARSE_PARAGON"])
        add(L["PARSE_MISSION"])
        add(L["PARSE_EXPANSION"])
        add(L["PARSE_SCENARIO"])
        add(L["PARSE_CLASS_HALL"])
        add(L["PARSE_CAMPAIGN"])
        add(L["PARSE_EVENT"])
        add(L["PARSE_SPECIAL"])
        add(L["PARSE_BRAWLERS_GUILD"])
        add(L["PARSE_CHALLENGE_MODE"])
        add(L["PARSE_MYTHIC_PLUS"])
        add(L["PARSE_TIMEWALKING"])
        add(L["PARSE_ISLAND_EXPEDITION"])
        add(L["PARSE_WARFRONT"])
        add(L["PARSE_TORGHAST"])
        add(L["PARSE_ZERETH_MORTIS"])
        add(L["SOURCE_TYPE_PUZZLE"])
        add(L["PARSE_HIDDEN"])
        add(L["PARSE_RARE"])
        add(L["PARSE_WORLD_BOSS"])
    end
    return keywords
end

local SOURCE_KEYWORDS  -- lazy-init (locale must be loaded first)

local function HasSourceKeyword(text)
    text = SafeTextForStringOps(text)
    if not text then return false end
    if not SOURCE_KEYWORDS then
        SOURCE_KEYWORDS = BuildSourceKeywords()
    end
    for ki = 1, #SOURCE_KEYWORDS do
        local keyword = SOURCE_KEYWORDS[ki]
        if text:find(keyword, 1, true) then
            return true
        end
    end
    return false
end

-- CURRENCY AFFORDABILITY CHECK
-- Uses stored currency data from db.global.currencyData (CurrencyCacheService)

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

-- RECIPE MATERIAL CHECKER

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
    local slotSchematics = schematic.reagentSlotSchematics
    
    for rsi = 1, #slotSchematics do
        local slot = slotSchematics[rsi]
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

    local tinsert = table.insert
    local results = {}

    -- Read once per call through the live ItemsCacheService model (session-cached
    -- decompression). This used to gate on the deprecated warbandBankV2/personalBanks
    -- tables and call Decompress* methods that no longer exist anywhere — a guaranteed
    -- nil-call error whenever those transitional tables were present.
    local wbItems = nil
    if self.GetWarbandBankData then
        local wbData = self:GetWarbandBankData()
        wbItems = wbData and wbData.items
    end

    local bankDecoded = {}
    if self.GetItemsData and self.db.global and self.db.global.characters then
        for charKey in pairs(self.db.global.characters) do
            local itemsData = self:GetItemsData(charKey)
            if itemsData and itemsData.bank and #itemsData.bank > 0 then
                bankDecoded[charKey] = itemsData.bank
            end
        end
    end

    local function addWarbandMatches(itemID, locations)
        local found = 0
        if not wbItems then return found end
        for i = 1, #wbItems do
            local item = wbItems[i]
            if item.itemID == itemID then
                found = found + (item.stackCount or 1)
                tinsert(locations, {
                    type = "warband",
                    bag = item.bagID,
                    slot = item.slot,
                    count = item.stackCount or 1,
                })
            end
        end
        return found
    end

    local function addPersonalBankMatches(itemID, locations)
        local found = 0
        for charKey, bankItems in pairs(bankDecoded) do
            for i = 1, #bankItems do
                local item = bankItems[i]
                if item.itemID == itemID then
                    found = found + (item.stackCount or 1)
                    tinsert(locations, {
                        type = "personal",
                        character = charKey,
                        bag = item.bagID,
                        slot = item.slot,
                        count = item.stackCount or 1,
                    })
                end
            end
        end
        return found
    end

    for ri = 1, #reagents do
        local reagent = reagents[ri]
        local itemID = reagent.itemID
        local needed = reagent.quantity
        local found = 0
        local locations = {}

        found = found + addWarbandMatches(itemID, locations)
        found = found + addPersonalBankMatches(itemID, locations)

        for bagID = 0, 4 do
            local numSlots = C_Container.GetContainerNumSlots(bagID)
            if numSlots and numSlots > 0 then
                for slot = 1, numSlots do
                    local info = C_Container.GetContainerItemInfo(bagID, slot)
                    if info and info.itemID == itemID then
                        found = found + (info.stackCount or 1)
                        tinsert(locations, {
                            type = "bags",
                            bag = bagID,
                            slot = slot,
                            count = info.stackCount or 1,
                        })
                    end
                end
            end
        end

        local itemName = C_Item.GetItemNameByID(itemID) or ((ns.L and ns.L["ITEM_LOADING_NAME"]) or "Loading...")
        local itemIcon = C_Item.GetItemIconByID(itemID)

        tinsert(results, {
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

-- PLAN PROGRESS CHECKING

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
            -- Midnight 12.0: isCollected may be a secret value; do not use as boolean directly
            if issecretvalue and isCollected and issecretvalue(isCollected) then
                progress.collected = (plan.resolvedCollected == true) or (plan.completed == true)
            else
                progress.collected = isCollected == true
            end
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
            for mi = 1, #materialCheck do
                local mat = materialCheck[mi]
                if not mat.complete then
                    allComplete = false
                    break
                end
            end
            progress.canObtain = allComplete
        end
        
    elseif plan.type == PLAN_TYPES.ACHIEVEMENT then
        -- Check if achievement is completed (4th return); guard secret values (Midnight)
        if plan.achievementID then
            local _, _, _, completed = GetAchievementInfo(plan.achievementID)
            if issecretvalue and issecretvalue(completed) then
                progress.collected = (plan.resolvedCollected == true) or (plan.completed == true)
            else
                progress.collected = completed == true
            end
        end
        
    elseif plan.type == PLAN_TYPES.ILLUSION then
        if plan.illusionID and C_TransmogCollection then
            progress.collected = GetIllusionCollectedForPlanId(plan.illusionID)
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

--[[
    Whether an active To-Do plan counts as "done" for filtering (Show Completed on/off)
    and header counts. Uses live CheckPlanProgress where applicable so UI matches the game
    even if resolvedCollected lagged after login.
]]
function WarbandNexus:IsActivePlanComplete(plan)
    if not plan then return false end
    if plan.type == PLAN_TYPES.WEEKLY_VAULT or plan.type == "weekly_vault" then
        return plan.fullyCompleted == true
    end
    if plan.type == "daily_quests" then
        local totalQuests, completedQuests = 0, 0
        local categoryOrder = { "weeklyQuests", "worldQuests", "assignments", "dailyQuests", "events" }
        for cki = 1, #categoryOrder do
            local cat = categoryOrder[cki]
            if plan.questTypes and plan.questTypes[cat] then
                local questList = plan.quests and plan.quests[cat] or {}
                if self.FilterWeeklyProgressQuestList then
                    questList = self:FilterWeeklyProgressQuestList(plan, cat, questList)
                end
                for qi = 1, #questList do
                    local quest = questList[qi]
                    if quest and not quest.isSubQuest then
                        totalQuests = totalQuests + 1
                        if quest.isComplete then
                            completedQuests = completedQuests + 1
                        end
                    end
                end
            end
        end
        return totalQuests > 0 and completedQuests == totalQuests
    end
    local prog = self:CheckPlanProgress(plan)
    if prog and prog.collected then
        return true
    end
    if plan.completed == true then
        return true
    end
    return false
end

-- MULTI-SOURCE PARSER

--[[
    Strip WoW escape sequences from text for clean display
    Removes texture tags, color codes, hyperlinks
    @param text string - Raw text with escape sequences
    @return string - Clean text
]]
function WarbandNexus:CleanSourceText(text)
    local safe = SafeTextForStringOps(text)
    if not safe then return "" end
    local result = safe
    
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
    
    -- Use Blizzard globals for parsing API-localized source text
    -- BATTLE_PET_SOURCE_* match the keywords Blizzard uses in journal source descriptions
    local L = ns.L
    local vendorKey = BATTLE_PET_SOURCE_3 or (L and L["PARSE_SOLD_BY"]) or "Vendor"
    local zoneKey = (L and L["PARSE_ZONE"]) or ZONE or "Zone"
    local costKey = (L and L["PARSE_COST"]) or "Cost"
    
    -- Split source text by double newlines or repeated vendor patterns
    local currentSource = {}
    local hasMultiple = false
    
    -- Check if text contains multiple vendor entries (localized)
    local vendorCount = 0
    for _ in sourceText:gmatch(vendorKey .. ":") do
        vendorCount = vendorCount + 1
    end
    -- Also check "Sold by" pattern (localized)
    if vendorCount == 0 then
        local soldByKey = (L and L["PARSE_SOLD_BY"]) or "Sold by"
        for _ in sourceText:gmatch(soldByKey .. ":") do
            vendorCount = vendorCount + 1
        end
    end
    hasMultiple = vendorCount > 1
    
    -- Helper: Extract field value from text using localized keyword
    local function extractFieldFromBlock(block, localizedKey)
        if not localizedKey then return nil end
        return block:match(localizedKey .. ":%s*([^\n]+)")
    end
    
    if hasMultiple then
        -- Parse each vendor block using localized patterns
        local vendorPattern = vendorKey .. ":[^\n]*\n" .. zoneKey .. ":[^\n]*[^\n]*"
        for block in sourceText:gmatch(vendorPattern) do
            local vendor = extractFieldFromBlock(block, vendorKey)
            local zone = extractFieldFromBlock(block, zoneKey)
            local cost = extractFieldFromBlock(block, costKey)
            
            -- Clean trailing keywords from vendor
            if vendor then
                vendor = vendor:gsub("%s*" .. zoneKey .. ":.*$", "")
                vendor = vendor:gsub("%s*" .. costKey .. ":.*$", "")
                vendor = vendor:gsub("%s*$", "")
            end
            if zone then
                zone = zone:gsub("%s*" .. costKey .. ":.*$", "")
                zone = zone:gsub("%s*" .. vendorKey .. ":.*$", "")
                zone = zone:gsub("%s*$", "")
            end
            if cost then
                cost = cost:gsub("%s*" .. zoneKey .. ":.*$", "")
                cost = cost:gsub("%s*" .. vendorKey .. ":.*$", "")
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
                local soldByKey = (L and L["PARSE_SOLD_BY"]) or "Sold by"
                if line:find(vendorKey .. ":", 1, true) or line:find(soldByKey, 1, true) then
                    local vendor = extractFieldFromBlock(line, vendorKey)
                    -- Clean any trailing keywords
                    if vendor then
                        vendor = vendor:gsub("%s*" .. zoneKey .. ":.*$", "")
                        vendor = vendor:gsub("%s*" .. costKey .. ":.*$", "")
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
            quest = nil,
            achievement = nil,
            faction = nil,
            renown = nil,
        }
        
        -- Determine source type using Blizzard's localized BATTLE_PET_SOURCE_* globals
        -- These globals are auto-localized by WoW client for all supported languages
        local L = ns.L
        local sourceTypePatterns = {
            { pattern = (L and L["SOURCE_TYPE_RENOWN"]) or "Renown",             type = "Renown" },
            { pattern = (FACTION or (L and L["PARSE_FACTION"]) or "Faction") .. ":", type = "Renown" },
            { pattern = PVP or "PvP",                                              type = "PvP" },
            { pattern = (L and L["PARSE_ARENA"]) or ARENA or "Arena",              type = "PvP" },
            { pattern = (L and L["SOURCE_TYPE_PUZZLE"]) or "Puzzle",               type = "Puzzle" },
            { pattern = BATTLE_PET_SOURCE_7 or "World Event",                      type = "World Event" },
            { pattern = (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure",           type = "Treasure" },
            { pattern = BATTLE_PET_SOURCE_3 or "Vendor",                           type = "Vendor" },
            { pattern = (L and L["PARSE_SOLD_BY"]) or "Sold by",                   type = "Vendor" },
            { pattern = BATTLE_PET_SOURCE_1 or "Drop",                             type = "Drop" },
            { pattern = BATTLE_PET_SOURCE_5 or "Pet Battle",                       type = "Pet Battle" },
            { pattern = BATTLE_PET_SOURCE_2 or "Quest",                            type = "Quest" },
            { pattern = BATTLE_PET_SOURCE_6 or "Achievement",                      type = "Achievement" },
            { pattern = BATTLE_PET_SOURCE_4 or "Profession",                       type = "Crafted" },
            { pattern = (L and L["PARSE_CRAFTED"]) or "Crafted",                   type = "Crafted" },
            { pattern = BATTLE_PET_SOURCE_8 or "Promotion",                        type = "Promotion" },
            { pattern = (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",   type = "Trading Post" },
        }
        
        singleSource.sourceType = (L and L["SOURCE_TYPE_UNKNOWN"]) or UNKNOWN or "Unknown"
        for ei = 1, #sourceTypePatterns do
            local entry = sourceTypePatterns[ei]
            if entry.pattern and sourceText:find(entry.pattern, 1, true) then
                singleSource.sourceType = entry.type
                break
            end
        end
        
        -- Extract details using patterns that stop at newline OR next keyword
        -- This handles both properly formatted text and single-line concatenated text
        
        -- Localized keywords for field extraction (from Blizzard globals / L[])
        local dropKey = BATTLE_PET_SOURCE_1 or (L and L["PARSE_DROP"]) or "Drop"
        local soldByKey = (L and L["PARSE_SOLD_BY"]) or "Sold by"
        local factionKey = FACTION or (L and L["PARSE_FACTION"]) or "Faction"
        local repKey = REPUTATION or (L and L["PARSE_REPUTATION"]) or "Reputation"
        local renownKey = (L and L["SOURCE_TYPE_RENOWN"]) or "Renown"
        local friendKey = (L and L["PARSE_FRIENDSHIP"]) or "Friendship"
        local questKey = BATTLE_PET_SOURCE_2 or "Quest"
        local achievementKey = BATTLE_PET_SOURCE_6 or (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement"
        local npcKey = (L and L["PARSE_NPC"]) or "NPC"
        
        local function extractField(text, keyword)
            local pattern = keyword .. ":%s*([^\n]+)"
            local value = text:match(pattern)
            
            if value then
                -- Clean trailing keywords that might have been captured (using localized keys)
                value = value:gsub("%s+" .. vendorKey .. ":%s*.*$", "")
                value = value:gsub("%s+" .. zoneKey .. ":%s*.*$", "")
                value = value:gsub("%s+" .. costKey .. ":%s*.*$", "")
                value = value:gsub("%s+" .. dropKey .. ":%s*.*$", "")
                value = value:gsub("%s+" .. factionKey .. ":%s*.*$", "")
                value = value:gsub("%s+" .. renownKey .. "%s*.*$", "")
                value = value:gsub("%s+" .. questKey .. ":%s*.*$", "")
                value = value:gsub("%s+" .. npcKey .. ":%s*.*$", "")
                -- Trim trailing whitespace
                value = value:gsub("%s*$", "")
            end
            return value
        end
        
        singleSource.vendor = extractField(sourceText, vendorKey) or extractField(sourceText, soldByKey)
        singleSource.zone = extractField(sourceText, zoneKey)
        singleSource.cost = extractField(sourceText, costKey)
        singleSource.npc = extractField(sourceText, dropKey)
        singleSource.quest = extractField(sourceText, questKey)
        singleSource.achievement = extractField(sourceText, achievementKey)
        singleSource.faction = extractField(sourceText, factionKey) or extractField(sourceText, repKey)
        
        -- Extract renown/friendship levels (using localized keywords)
        local renownLevel = sourceText:match(renownKey .. "%s*(%d+)") or sourceText:match(renownKey .. ":%s*(%d+)")
        local friendshipLevel = sourceText:match(friendKey .. "%s*(%d+)") or sourceText:match(friendKey .. ":%s*(%d+)")
        
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

-- CHAT LINKS (To-Do plan cards: mount / pet / toy / achievement / item types)

local function SafeChatLinkString(link)
    if not link or type(link) ~= "string" or link == "" then return nil end
    if issecretvalue and issecretvalue(link) then return nil end
    return link
end

--- Resolve the collectible id used for try-count storage/display on plan cards.
---@return number|nil
function WarbandNexus:GetPlanCollectibleID(plan)
    if not plan or not plan.type then return nil end
    local t = plan.type
    if t == "mount" then
        if plan.mountID and type(plan.mountID) == "number" then return plan.mountID end
        if plan.itemID and type(plan.itemID) == "number" and C_MountJournal and C_MountJournal.GetMountFromItem then
            local ok, mid = pcall(C_MountJournal.GetMountFromItem, plan.itemID)
            if ok and type(mid) == "number" and mid > 0
                and not (issecretvalue and issecretvalue(mid)) then
                return mid
            end
        end
        if plan.itemID and type(plan.itemID) == "number" then return plan.itemID end
        return nil
    end
    if t == "pet" then
        if plan.speciesID and type(plan.speciesID) == "number" then return plan.speciesID end
        if plan.petID and type(plan.petID) == "number" then return plan.petID end
        return nil
    end
    if t == "toy" and plan.itemID and type(plan.itemID) == "number" then return plan.itemID end
    if t == "illusion" then
        if plan.sourceID and type(plan.sourceID) == "number" then return plan.sourceID end
        if plan.illusionID and type(plan.illusionID) == "number" then return plan.illusionID end
    end
    return nil
end

--- Whether the plan type can expose a WoW chat hyperlink (button shown on card).
function WarbandNexus:PlanSupportsChatLink(plan)
    if not plan or not plan.type then return false end
    local t = plan.type
    if t == "mount" and plan.mountID then return true end
    if t == "pet" and plan.speciesID then return true end
    if (t == "toy" or t == "recipe") and plan.itemID then return true end
    if t == "illusion" and plan.itemID then return true end
    if t == "achievement" and plan.achievementID then return true end
    return false
end

--- Returns a full chat hyperlink string, or nil if not available / not loaded yet.
function WarbandNexus:GetPlanChatLink(plan)
    if not plan or not plan.type then return nil end
    local t = plan.type

    if t == "mount" and plan.mountID and type(plan.mountID) == "number" then
        if C_MountJournal then
            if C_MountJournal.GetMountLink then
                local ok, link = pcall(C_MountJournal.GetMountLink, plan.mountID)
                local s = SafeChatLinkString(ok and link)
                if s then return s end
            end
            if C_MountJournal.GetMountItemID and C_Item and C_Item.GetItemLinkByID then
                local ok, itemID = pcall(C_MountJournal.GetMountItemID, plan.mountID)
                if ok and itemID and type(itemID) == "number" and itemID > 0 then
                    local ok2, link = pcall(C_Item.GetItemLinkByID, itemID)
                    local s = SafeChatLinkString(ok2 and link)
                    if s then return s end
                end
            end
        end
        return nil
    end

    if t == "pet" and plan.speciesID and type(plan.speciesID) == "number" and C_PetJournal then
        if C_PetJournal.GetPetLink then
            local ok, link = pcall(C_PetJournal.GetPetLink, plan.speciesID)
            local s = SafeChatLinkString(ok and link)
            if s then return s end
        end
        return nil
    end

    if (t == "toy" or t == "recipe") and plan.itemID and type(plan.itemID) == "number" and C_Item and C_Item.GetItemLinkByID then
        local ok, link = pcall(C_Item.GetItemLinkByID, plan.itemID)
        return SafeChatLinkString(ok and link)
    end

    if t == "illusion" and plan.itemID and type(plan.itemID) == "number" and C_Item and C_Item.GetItemLinkByID then
        local ok, link = pcall(C_Item.GetItemLinkByID, plan.itemID)
        return SafeChatLinkString(ok and link)
    end

    if t == "achievement" and plan.achievementID and type(plan.achievementID) == "number" then
        if C_AchievementInfo and C_AchievementInfo.GetAchievementLink then
            local ok, link = pcall(C_AchievementInfo.GetAchievementLink, plan.achievementID)
            local s = SafeChatLinkString(ok and link)
            if s then return s end
        end
        if GetAchievementLink then
            local ok, link = pcall(GetAchievementLink, plan.achievementID)
            return SafeChatLinkString(ok and link)
        end
        return nil
    end

    return nil
end

--- Inserts the plan's chat link into the edit box, or opens chat with the link prefilled.
function WarbandNexus:InsertPlanChatLink(plan)
    local link = self:GetPlanChatLink(plan)
    if not link then
        local L = ns.L
        local msg = (L and L["PLAN_CHAT_LINK_UNAVAILABLE"]) or "Chat link is not available for this entry."
        if self.Print then
            self:Print("|cffff9900" .. msg .. "|r")
        end
        return
    end
    local edit = ChatEdit_GetActiveWindow and ChatEdit_GetActiveWindow()
    if edit and ChatEdit_InsertLink then
        ChatEdit_InsertLink(link)
        return
    end
    if ChatFrame_OpenChat then
        pcall(ChatFrame_OpenChat, link)
    elseif ChatEdit_InsertLink then
        pcall(ChatEdit_InsertLink, link)
    end
end

