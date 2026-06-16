--[[
    Warband Nexus - Blizzard Collections loader + chunked pet/toy journal materialize.
    Split from CollectionService.lua (Lua 5.1 local limit).
    Loaded before Modules/CollectionService.lua.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local issecretvalue = issecretvalue
local Utilities = ns.Utilities

local DebugPrint = ns.DebugPrint
local function DebugPrintf(fmt, ...)
    if ns.IsDebugVerboseEnabled and ns.IsDebugVerboseEnabled() then
        if DebugPrint then DebugPrint(string.format(fmt, ...)) end
    end
end
local blizzardCollectionsLoaded = false
local function EnsureBlizzardCollectionsLoaded()
    if blizzardCollectionsLoaded then return end
    if InCombatLockdown() then return end
    blizzardCollectionsLoaded = true
    local P = ns.Profiler
    if P and P.enabled then P:Start("EnsureBlizzard_CollectionsLoad") end
    if Utilities and Utilities.SafeLoadAddOn then
        Utilities:SafeLoadAddOn("Blizzard_Collections")
    end
    if P and P.enabled then P:Stop("EnsureBlizzard_CollectionsLoad") end
    DebugPrint("|cff00ff00[WN CollectionService]|r Ensured Blizzard_Collections is loaded for API data")
end
ns.EnsureBlizzardCollectionsLoaded = EnsureBlizzardCollectionsLoaded

---Chunked pet journal prep for BuildFullCollectionData (replaces synchronous COLLECTION_CONFIGS.pet.iterator).
---Spreads SetPetSourceChecked / GetPetInfoByIndex work across frames using FRAME_BUDGET_MS.
---@param budgetMs number
---@param state table|nil
---@return table state { done, items, speciesToSource }
local function PetJournalBuildMaterializeStep(budgetMs, state)
    local _iv = issecretvalue
    if not state then
        state = {
            done = false,
            phase = "start",
            items = {},
            speciesToSource = {},
            origSearch = "",
            numSources = 0,
            srcIdx = 1,
            numPets = 0,
            listI = 1,
            seen = {},
        }
    end
    if state.done then return state end

    local function needYield(t0)
        return (debugprofilestop() - t0) >= budgetMs
    end

    while not state.done do
        local t0 = debugprofilestop()

        if state.phase == "start" then
            if not C_PetJournal then
                state.items = {}
                state.speciesToSource = {}
                state.done = true
                break
            end
            EnsureBlizzardCollectionsLoaded()
            state.origSearch = (C_PetJournal.GetSearchFilter and C_PetJournal.GetSearchFilter()) or ""
            if _iv and state.origSearch and _iv(state.origSearch) then state.origSearch = "" end
            if not InCombatLockdown() then
                pcall(function()
                    if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
                    if C_PetJournal.SetFilterChecked then
                        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
                        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
                    end
                    if C_PetJournal.SetPetTypeFilter then
                        for i = 1, C_PetJournal.GetNumPetTypes() do
                            C_PetJournal.SetPetTypeFilter(i, true)
                        end
                    end
                    if C_PetJournal.SetPetSourceChecked then
                        for i = 1, C_PetJournal.GetNumPetSources() do
                            C_PetJournal.SetPetSourceChecked(i, true)
                        end
                    end
                end)
            end
            state.numSources = (C_PetJournal.GetNumPetSources and C_PetJournal.GetNumPetSources()) or 0
            if not InCombatLockdown() and ns._petSpeciesToSourceIndex and next(ns._petSpeciesToSourceIndex) then
                -- Reuse session source classification (BuildFullCollectionData / prior materialize); skip O(n^2) source scan.
                state.speciesToSource = ns._petSpeciesToSourceIndex
                state.phase = "after_sources"
            elseif InCombatLockdown() or state.numSources <= 0 or not C_PetJournal.SetPetSourceChecked then
                state.phase = "after_sources"
            else
                state.srcIdx = 1
                state.phase = "sources"
            end
        elseif state.phase == "sources" then
            while state.srcIdx <= state.numSources do
                local srcIdx = state.srcIdx
                pcall(function()
                    for i = 1, state.numSources do
                        C_PetJournal.SetPetSourceChecked(i, i == srcIdx)
                    end
                    local nFiltered = C_PetJournal.GetNumPets() or 0
                    for j = 1, nFiltered do
                        local _, sID = C_PetJournal.GetPetInfoByIndex(j)
                        if sID and not (_iv and _iv(sID)) then
                            if not state.speciesToSource[sID] then
                                state.speciesToSource[sID] = srcIdx
                            end
                        end
                    end
                end)
                state.srcIdx = state.srcIdx + 1
                if needYield(t0) then return state end
            end
            if not InCombatLockdown() then
                pcall(function()
                    for i = 1, state.numSources do
                        C_PetJournal.SetPetSourceChecked(i, true)
                    end
                end)
            end
            state.phase = "after_sources"
        elseif state.phase == "after_sources" then
            state.numPets = C_PetJournal.GetNumPets() or 0
            if _iv and state.numPets and _iv(state.numPets) then state.numPets = 0 end
            state.listI = 1
            state.seen = {}
            state.items = {}
            state.phase = "build_list"
            if needYield(t0) then return state end
        elseif state.phase == "build_list" then
            while state.listI <= state.numPets do
                local _, speciesID = C_PetJournal.GetPetInfoByIndex(state.listI)
                if speciesID and not (_iv and _iv(speciesID)) and not state.seen[speciesID] then
                    state.seen[speciesID] = true
                    state.items[#state.items + 1] = speciesID
                end
                state.listI = state.listI + 1
                if needYield(t0) then return state end
            end
            if not InCombatLockdown() then
                pcall(function()
                    if state.origSearch and state.origSearch ~= "" and C_PetJournal.SetSearchFilter then
                        C_PetJournal.SetSearchFilter(state.origSearch)
                    end
                end)
            end
            state.done = true
            break
        else
            state.done = true
            break
        end

        if needYield(t0) then return state end
    end

    return state
end

---Chunked toy box source map + item id list for BuildFullCollectionData (replaces synchronous toy.iterator prep).
---@param budgetMs number
---@param state table|nil
---@param addon table WarbandNexus
---@return table state
local function ToyBoxBuildMaterializeStep(budgetMs, state, addon)
    local _iv = issecretvalue
    if not C_ToyBox then
        state = state or {}
        state.done = true
        state.items = {}
        state.toyToSource = {}
        return state
    end

    if not state then
        state = {
            done = false,
            phase = "start",
            items = {},
            toyToSource = {},
            count = 0,
            sourceIndex = 1,
            numToys = 0,
            toyI = 1,
            origCollected = nil,
            origUncollected = nil,
            origFilterString = "",
            origSourceFilters = {},
        }
    end
    if state.done then return state end

    local function needYield(t0)
        return (debugprofilestop() - t0) >= budgetMs
    end

    while not state.done do
        local t0 = debugprofilestop()

        if state.phase == "start" then
            EnsureBlizzardCollectionsLoaded()
            state.origCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
            state.origUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
            state.origFilterString = (C_ToyBox.GetFilterString and C_ToyBox.GetFilterString()) or ""
            if _iv and state.origFilterString and _iv(state.origFilterString) then state.origFilterString = "" end
            if InCombatLockdown() then
                state.toyToSource = {}
                state.phase = "prep_list_filters"
            elseif ns._toyItemIDToSourceIndex and next(ns._toyItemIDToSourceIndex) then
                -- Reuse session itemID->source map; skip per-source ToyBox filter sweep.
                state.toyToSource = ns._toyItemIDToSourceIndex
                state.phase = "prep_list_filters"
            else
                state.count = (addon and addon.GetToySourceTypeCount and addon:GetToySourceTypeCount()) or 16
                for i = 1, state.count do
                    if C_ToyBox.IsSourceTypeFilterChecked then
                        local ok, checked = pcall(C_ToyBox.IsSourceTypeFilterChecked, i)
                        if ok and checked ~= nil then state.origSourceFilters[i] = checked end
                    end
                end
                state.sourceIndex = 1
                state.phase = "source_map"
            end
        elseif state.phase == "source_map" then
            if state.sourceIndex == 1 then
                pcall(function()
                    C_ToyBox.SetCollectedShown(true)
                    C_ToyBox.SetUncollectedShown(true)
                    C_ToyBox.SetFilterString("")
                end)
            end
            while state.sourceIndex <= state.count do
                local si = state.sourceIndex
                pcall(function()
                    C_ToyBox.SetAllSourceTypeFilters(false)
                    C_ToyBox.SetSourceTypeFilter(si, true)
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                    local numFiltered = (C_ToyBox.GetNumFilteredToys and C_ToyBox.GetNumFilteredToys()) or 0
                    if _iv and numFiltered and _iv(numFiltered) then numFiltered = 0 end
                    for j = 1, numFiltered do
                        local itemID = C_ToyBox.GetToyFromIndex(j)
                        if itemID and itemID > 0 and not (_iv and _iv(itemID)) then
                            if not state.toyToSource[itemID] then
                                state.toyToSource[itemID] = si
                            end
                        end
                    end
                end)
                state.sourceIndex = state.sourceIndex + 1
                if needYield(t0) then return state end
            end
            pcall(function()
                C_ToyBox.SetAllSourceTypeFilters(true)
                if state.origCollected ~= nil then C_ToyBox.SetCollectedShown(state.origCollected) end
                if state.origUncollected ~= nil then C_ToyBox.SetUncollectedShown(state.origUncollected) end
                if state.origFilterString then C_ToyBox.SetFilterString(state.origFilterString) end
                for i, checked in pairs(state.origSourceFilters) do
                    if C_ToyBox.SetSourceTypeFilter then C_ToyBox.SetSourceTypeFilter(i, checked) end
                end
                if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
            end)
            state.phase = "prep_list_filters"
            if needYield(t0) then return state end
        elseif state.phase == "prep_list_filters" then
            if not InCombatLockdown() then
                pcall(function()
                    C_ToyBox.SetCollectedShown(true)
                    C_ToyBox.SetUncollectedShown(true)
                    C_ToyBox.SetAllSourceTypeFilters(true)
                    C_ToyBox.SetFilterString("")
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
            state.numToys = 0
            if C_ToyBox.GetNumFilteredToys then
                state.numToys = C_ToyBox.GetNumFilteredToys() or 0
            end
            if state.numToys == 0 and C_ToyBox.GetNumTotalDisplayedToys then
                state.numToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
            end
            if state.numToys == 0 and C_ToyBox.GetNumToys then
                state.numToys = C_ToyBox.GetNumToys() or 0
            end
            if _iv and state.numToys and _iv(state.numToys) then state.numToys = 0 end
            state.toyI = 1
            state.items = {}
            state.phase = "build_list"
            if needYield(t0) then return state end
        elseif state.phase == "build_list" then
            while state.toyI <= state.numToys do
                local itemID = C_ToyBox.GetToyFromIndex(state.toyI)
                if itemID and itemID > 0 and not (_iv and _iv(itemID)) then
                    state.items[#state.items + 1] = itemID
                end
                state.toyI = state.toyI + 1
                if needYield(t0) then return state end
            end
            if not InCombatLockdown() then
                pcall(function()
                    if state.origCollected ~= nil then C_ToyBox.SetCollectedShown(state.origCollected) end
                    if state.origUncollected ~= nil then C_ToyBox.SetUncollectedShown(state.origUncollected) end
                    if state.origFilterString then C_ToyBox.SetFilterString(state.origFilterString) end
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
            state.done = true
            if next(state.toyToSource or {}) then
                ns._toyGroupedFromMapValid = true
            end
            break
        else
            state.done = true
            break
        end

        if needYield(t0) then return state end
    end

    return state
end

local Mat = {
    EnsureBlizzardCollectionsLoaded = EnsureBlizzardCollectionsLoaded,
    PetJournalBuildMaterializeStep = PetJournalBuildMaterializeStep,
    ToyBoxBuildMaterializeStep = ToyBoxBuildMaterializeStep,
}
ns.CollectionMaterialize = Mat
ns.EnsureBlizzardCollectionsLoaded = EnsureBlizzardCollectionsLoaded
