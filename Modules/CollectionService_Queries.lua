--[[ CollectionService GetUncollected* / GetCollected* store queries (split from CollectionService.lua) ]]
local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local RT = assert(ns.CollectionServiceRT, 'CollectionService_Queries: load CollectionService.lua first')
local NormalizeCollectionSearchText = RT.NormalizeCollectionSearchText
local CollectionNameMatchesSearch = RT.CollectionNameMatchesSearch
local ScheduleEnsureCollectionDataDeferred = RT.ScheduleEnsureCollectionDataDeferred
local EmitPlansBrowseCollectionEnsure = RT.EmitPlansBrowseCollectionEnsure
local collectionStore = RT.collectionStore
local collectionCache = RT.collectionCache
local RESULTS_CACHE_TTL = RT.RESULTS_CACHE_TTL
local uncollectedResultsCache = RT.uncollectedResultsCache

-- Coalesced store save for the READ paths below (implementation: CollectionService_Store.lua).
local function ScheduleDeferredCollectionStoreSave()
    if ns.CollectionServiceRT and ns.CollectionServiceRT.ScheduleDeferredCollectionStoreSave then
        ns.CollectionServiceRT.ScheduleDeferredCollectionStoreSave()
    end
end

---Get uncollected mounts (UNIFIED: collectionStore-first, scan if empty). Plans shows uncollected only.
---@return table Array of uncollected mounts {id, name, icon, source, ...}
function WarbandNexus:GetUncollectedMounts(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)

    -- Results cache: avoid expensive store iteration on rapid redraws
    local cacheKey = "mount:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.mount
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        local storeChanged = false
        for mountID, d in pairs(store) do
            if d then
                -- Always resolve from Collections API metadata.
                -- This prevents stale legacy DB source text from leaking into Plans.
                local meta = self:ResolveCollectionMetadata("mount", mountID)

                -- If mountID no longer resolves from API, skip (do NOT prune — API may
                -- be temporarily unavailable during loading or combat lockdown).
                if not meta then
                    -- noop: keep store entry intact for next attempt
                elseif meta.isCollected then
                    -- Keep store in sync when API reports collected.
                    if d.collected ~= true then
                        d.collected = true
                        storeChanged = true
                    end
                else
                    local includeInPlans = true
                    if self.ShouldExcludeMountFromCollectionBrowse and self:ShouldExcludeMountFromCollectionBrowse(mountID) then
                        includeInPlans = false
                    end

                    if includeInPlans then
                    if d.collected ~= false then
                        d.collected = false
                        storeChanged = true
                    end

                    local name = meta.name or ("ID:" .. tostring(mountID))
                    if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                        meta.id = mountID
                        meta.isCollected = false
                        meta.collected = false
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then
                            if storeChanged then
                                ScheduleDeferredCollectionStoreSave()
                            end
                            uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
                            return results
                        end
                    end
                    end
                end
            end
        end
        if storeChanged then
            ScheduleDeferredCollectionStoreSave()
        end
        uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
        return results
    end

    -- Store empty: one deferred ensure per category (Plans browse loop guard via message bus).
    EmitPlansBrowseCollectionEnsure("mount")
    return {}
end

---Get uncollected pets (UNIFIED: collectionStore-first). Plans shows uncollected only.
function WarbandNexus:GetUncollectedPets(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)

    local cacheKey = "pet:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.pet
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for petID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(petID))
                if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                    local meta
                    if d.icon or d.source then
                        meta = { id = petID, name = d.name, icon = d.icon, source = d.source, description = d.description, creatureDisplayID = d.creatureDisplayID, isCollected = false }
                    else
                        meta = self:ResolveCollectionMetadata("pet", petID)
                        if meta then meta.isCollected = false end
                    end
                    if meta then
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then
                            uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
                            return results
                        end
                    end
                end
            end
        end
        uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
        return results
    end

    if self.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
        ScheduleEnsureCollectionDataDeferred()
    end
    return {}
end

---Get uncollected toys (UNIFIED: collectionStore-first). Plans shows uncollected only.
---When store has fallback source ("Toy Collection"/"Toy Box"), re-resolves from tooltip so Plans shows correct source.
function WarbandNexus:GetUncollectedToys(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)

    local cacheKey = "toy:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.toy
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for toyID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(toyID))
                if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                    local meta
                    local sourceOk = self:IsReliableToySource(d.source)
                    if (d.icon or d.source) and sourceOk then
                        meta = { id = toyID, name = d.name, icon = d.icon, source = d.source, description = d.description, isCollected = false }
                    else
                        meta = self:ResolveCollectionMetadata("toy", toyID)
                        if meta then
                            meta.isCollected = false
                            meta.id = toyID
                        end
                    end
                    if meta then
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then
                            uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
                            return results
                        end
                    end
                end
            end
        end
        uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
        return results
    end

    if self.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
        ScheduleEnsureCollectionDataDeferred()
    end
    return {}
end

--- Collected mounts for Plans "Show Completed" (GetUncollectedMounts only returns uncollected).
function WarbandNexus:GetCollectedMounts(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)
    local cacheKey = "c_mount:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.mount
    if not store or next(store) == nil then
        EmitPlansBrowseCollectionEnsure("mount")
        return {}
    end

    local results = {}
    local count = 0
    for mountID, d in pairs(store) do
        if d then
            local meta = self:ResolveCollectionMetadata("mount", mountID)
            if meta and meta.isCollected then
                if not (self.ShouldExcludeMountFromCollectionBrowse and self:ShouldExcludeMountFromCollectionBrowse(mountID)) then
                    local name = meta.name or ("ID:" .. tostring(mountID))
                    if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                        local row = {}
                        for k, v in pairs(meta) do
                            row[k] = v
                        end
                        row.id = mountID
                        row.isCollected = true
                        row.collected = true
                        results[#results + 1] = row
                        count = count + 1
                        if limit and count >= limit then break end
                    end
                end
            end
        end
    end
    uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
    return results
end

function WarbandNexus:GetCollectedPets(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)
    local cacheKey = "c_pet:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.pet
    if not store or next(store) == nil then
        EmitPlansBrowseCollectionEnsure("pet")
        return {}
    end

    local results = {}
    local count = 0
    for petID, d in pairs(store) do
        if d and d.collected == true then
            local name = d.name or ("ID:" .. tostring(petID))
            if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                local meta
                if d.icon or d.source then
                    meta = { id = petID, name = d.name, icon = d.icon, source = d.source, sourceTypeIndex = d.sourceTypeIndex, description = d.description, creatureDisplayID = d.creatureDisplayID, isCollected = true, collected = true }
                else
                    meta = self:ResolveCollectionMetadata("pet", petID)
                    if meta then
                        meta.id = petID
                        meta.isCollected = true
                        meta.collected = true
                    end
                end
                if meta then
                    results[#results + 1] = meta
                    count = count + 1
                    if limit and count >= limit then break end
                end
            end
        end
    end
    uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
    return results
end

function WarbandNexus:GetCollectedToys(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)
    local cacheKey = "c_toy:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.toy
    if not store or next(store) == nil then
        EmitPlansBrowseCollectionEnsure("toy")
        return {}
    end

    local results = {}
    local count = 0
    for toyID, d in pairs(store) do
        if d and d.collected == true then
            local name = d.name or ("ID:" .. tostring(toyID))
            if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                local meta
                local sourceOk = self:IsReliableToySource(d.source)
                if (d.icon or d.source) and sourceOk then
                    meta = { id = toyID, name = d.name, icon = d.icon, source = d.source, sourceTypeIndex = self:GetToySourceTypeIndexForItem(toyID), description = d.description, isCollected = true, collected = true }
                else
                    meta = self:ResolveCollectionMetadata("toy", toyID)
                    if meta then
                        meta.id = toyID
                        meta.isCollected = true
                        meta.collected = true
                    end
                end
                if meta then
                    results[#results + 1] = meta
                    count = count + 1
                    if limit and count >= limit then break end
                end
            end
        end
    end
    uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
    return results
end

function WarbandNexus:GetCollectedIllusions(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)
    local cacheKey = "c_illusion:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.illusion
    if not store or next(store) == nil then
        if self.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
            ScheduleEnsureCollectionDataDeferred()
        end
        return {}
    end

    local results = {}
    local count = 0
    for illusionID, d in pairs(store) do
        if d and d.collected == true then
            local name = d.name or ("ID:" .. tostring(illusionID))
            if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                local base = (d.icon or d.source) and d or self:ResolveCollectionMetadata("illusion", illusionID)
                local meta = base and { id = illusionID, name = base.name or name, icon = base.icon, source = base.source, isCollected = true, collected = true }
                if meta then
                    results[#results + 1] = meta
                    count = count + 1
                    if limit and count >= limit then break end
                end
            end
        end
    end
    uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
    return results
end

function WarbandNexus:GetCollectedTitles(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)
    local cacheKey = "c_title:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.title
    if not store or next(store) == nil then
        if self.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
            ScheduleEnsureCollectionDataDeferred()
        end
        return {}
    end

    local results = {}
    local count = 0
    for titleID, d in pairs(store) do
        if d and d.collected == true then
            local name = d.name or d.rewardText or ("ID:" .. tostring(titleID))
            if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                local base = (d.icon or d.rewardText) and d or self:ResolveCollectionMetadata("title", titleID)
                local meta = base and {
                    id = titleID,
                    name = base.name or base.rewardText or name,
                    icon = base.icon,
                    rewardText = base.rewardText,
                    isCollected = true,
                    collected = true,
                }
                if meta then
                    results[#results + 1] = meta
                    count = count + 1
                    if limit and count >= limit then break end
                end
            end
        end
    end
    uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
    return results
end

---Get uncollected achievements (UNIFIED: collectionStore-first). Plans shows uncollected only.
function WarbandNexus:GetUncollectedAchievements(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)

    local cacheKey = "ach_u:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.achievement
    local hasData = store and next(store) ~= nil

    if not hasData then
        EmitPlansBrowseCollectionEnsure("achievement")
        return {}
    end

    local results = {}
    local count = 0
    for achID, d in pairs(store) do
        if d and (d.collected == false or d.collected == nil) then
            local name = d.name or ("ID:" .. tostring(achID))
            if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                local meta
                if d.icon or d.points then
                    meta = { id = achID, name = d.name, icon = d.icon, points = d.points, description = d.description, isCollected = false, categoryID = d.categoryID, rewardItemID = d.rewardItemID, rewardTitle = d.rewardTitle, rewardText = d.rewardTitle }
                else
                    meta = self:ResolveCollectionMetadata("achievement", achID)
                    if meta then meta.id = achID; meta.isCollected = false end
                end
                if meta and not meta.categoryID and GetAchievementCategory then
                    meta.categoryID = GetAchievementCategory(achID)
                end
                if meta then
                    results[#results + 1] = meta
                    count = count + 1
                    if limit and count >= limit then
                        uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
                        return results
                    end
                end
            end
        end
    end
    uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
    return results
end

---Get completed achievements (UNIFIED: collectionStore-first). Collections shows collected only.
function WarbandNexus:GetCompletedAchievements(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)

    local cacheKey = "ach_c:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.achievement
    local hasData = store and next(store) ~= nil

    if not hasData then
        if collectionCache.uncollected.achievement and next(collectionCache.uncollected.achievement) then
            return {}
        end
        return self:GetUncollectedAchievements(searchText, 0)
    end

    local results = {}
    local count = 0
    for achID, d in pairs(store) do
        if d and d.collected == true then
            local name = d.name or ("ID:" .. tostring(achID))
            if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                local meta
                if d.icon or d.points then
                    meta = { id = achID, name = d.name, icon = d.icon, points = d.points, description = d.description, isCollected = true, categoryID = d.categoryID, rewardItemID = d.rewardItemID, rewardTitle = d.rewardTitle, rewardText = d.rewardTitle }
                else
                    meta = self:ResolveCollectionMetadata("achievement", achID)
                    if meta then meta.id = achID; meta.isCollected = true end
                end
                if meta and not meta.categoryID and GetAchievementCategory then
                    meta.categoryID = GetAchievementCategory(achID)
                end
                if meta then
                    results[#results + 1] = meta
                    count = count + 1
                    if limit and count >= limit then
                        uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
                        return results
                    end
                end
            end
        end
    end
    uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
    return results
end

---Get uncollected illusions (UNIFIED: collectionStore-first). Plans shows uncollected only.
function WarbandNexus:GetUncollectedIllusions(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)

    local cacheKey = "illusion:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.illusion
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for illusionID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or ("ID:" .. tostring(illusionID))
                if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                    local meta = (d.icon or d.source) and d or self:ResolveCollectionMetadata("illusion", illusionID)
                    if meta then
                        meta = { id = illusionID, name = meta.name or name, icon = meta.icon, source = meta.source, isCollected = false }
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then
                            uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
                            return results
                        end
                    end
                end
            end
        end
        uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
        return results
    end

    if self.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
        ScheduleEnsureCollectionDataDeferred()
    end
    return {}
end

---Get uncollected titles (UNIFIED: collectionStore-first). Plans shows uncollected only.
function WarbandNexus:GetUncollectedTitles(searchText, limit)
    searchText = NormalizeCollectionSearchText(searchText)

    local cacheKey = "title:" .. searchText .. ":" .. tostring(limit or "nil")
    local cached = uncollectedResultsCache[cacheKey]
    if cached and (GetTime() - cached.t) < RESULTS_CACHE_TTL then return cached.r end

    local store = collectionStore.title
    local hasData = store and next(store) ~= nil

    if hasData then
        local results = {}
        local count = 0
        for titleID, d in pairs(store) do
            if d and (d.collected == false or d.collected == nil) then
                local name = d.name or d.rewardText or ("ID:" .. tostring(titleID))
                if searchText == "" or CollectionNameMatchesSearch(name, searchText) then
                    local meta = (d.icon or d.rewardText) and d or self:ResolveCollectionMetadata("title", titleID)
                    if meta then
                        meta = { id = titleID, name = meta.name or meta.rewardText or name, icon = meta.icon, rewardText = meta.rewardText, isCollected = false }
                        results[#results + 1] = meta
                        count = count + 1
                        if limit and count >= limit then
                            uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
                            return results
                        end
                    end
                end
            end
        end
        uncollectedResultsCache[cacheKey] = { r = results, t = GetTime() }
        return results
    end

    if self.EnsureCollectionData and not ns.CollectionLoadingState.isLoading then
        ScheduleEnsureCollectionDataDeferred()
    end
    return {}
end
