--[[ CollectionService background scanning: COLLECTION_CONFIGS + ScanCollection (split from CollectionService.lua) ]]
local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local RT = assert(ns.CollectionServiceRT, 'CollectionService_JournalScan: load CollectionService.lua first')
local issecretvalue = issecretvalue
local Utilities = ns.Utilities
local DebugPrint = RT.DebugPrint
local DebugPrintf = RT.DebugPrintf
local Mat = ns.CollectionMaterialize
local GetCategoryAchievementListCount = RT.GetCategoryAchievementListCount
local SafeAchievementDisplayName = RT.SafeAchievementDisplayName
local GetAchievementInfoByCategoryIndex = RT.GetAchievementInfoByCategoryIndex
local Constants = ns.Constants
local FRAME_BUDGET_MS = Constants.FRAME_BUDGET_MS
local BATCH_SIZE = Constants.BATCH_SIZE
local SendCollectionScanProgress = RT.SendCollectionScanProgress
local collectionStore = RT.collectionStore
local MarkCategoryScanComplete = RT.MarkCategoryScanComplete
local ClearCategoryScanComplete = RT.ClearCategoryScanComplete
local collectionCache = RT.collectionCache
local activeCoroutines = RT.activeCoroutines
local scanCompleteCallbacks = RT.scanCompleteCallbacks
local InvokeScanCompleteCallback = RT.InvokeScanCompleteCallback

-- Defined in the BACKGROUND SCANNING section below; BuildFullCollectionData (CollectionService.lua)
-- reads it through RT.COLLECTION_CONFIGS.
local COLLECTION_CONFIGS

-- BACKGROUND SCANNING (Async Coroutine-Based)

-- Runtime cache for illusions (used during scan to avoid API re-calls)
local illusionRuntimeCache = nil
local illusionDebugCount = 0  -- Debug counter for illusion logging

---Unified collection configuration for background scanning
COLLECTION_CONFIGS = {
    mount = {
        name = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts",
        iterator = function()
            Mat.EnsureBlizzardCollectionsLoaded()
            if not C_MountJournal or not C_MountJournal.GetMountIDs then return {} end
            return C_MountJournal.GetMountIDs() or {}
        end,
        extract = function(mountID)
            -- GetMountInfoByID returns 13 values (mountID at #12, isSteadyFlight at #13; APIDocumentation 12.1.5)
            local name, spellID, icon, _, _, sourceType, _, isFactionSpecific, faction, shouldHideOnChar, isCollected, _mountIDRet, isSteadyFlight = C_MountJournal.GetMountInfoByID(mountID)
            if not name then return nil end
            -- Midnight 12.0: name or isCollected may be a secret value; guard against it
            if issecretvalue and name and issecretvalue(name) then return nil end
            if WarbandNexus.ShouldExcludeMountFromCollectionBrowse and WarbandNexus:ShouldExcludeMountFromCollectionBrowse(mountID) then
                return nil
            end
            local collected = false
            if issecretvalue and isCollected and issecretvalue(isCollected) then
                collected = true
            elseif isCollected == true then
                collected = true
            end
            -- shouldHideOnChar may also be secret
            local hideOnChar = false
            if issecretvalue and shouldHideOnChar and issecretvalue(shouldHideOnChar) then
                hideOnChar = false  -- If secret, assume visible (safe default)
            elseif shouldHideOnChar == true then
                hideOnChar = true
            end

            local creatureDisplayID, description, source = C_MountJournal.GetMountInfoExtraByID(mountID)

            local resolvedSourceType = sourceType
            if issecretvalue and resolvedSourceType and issecretvalue(resolvedSourceType) then
                resolvedSourceType = nil
            end
            if (not resolvedSourceType or resolvedSourceType == 0) and ns._mountIDToSourceIndex then
                local fromMap = ns._mountIDToSourceIndex[mountID]
                if fromMap and fromMap > 0 then resolvedSourceType = fromMap end
            end

            return {
                id = mountID,
                name = name,
                icon = icon,
                spellID = spellID,
                source = source or ((ns.L and ns.L["FALLBACK_UNKNOWN_SOURCE"]) or UNKNOWN or "Unknown"),
                sourceType = resolvedSourceType,
                description = description,
                creatureDisplayID = creatureDisplayID,
                collected = collected,
                shouldHideOnChar = hideOnChar,
                isFactionSpecific = isFactionSpecific,
                faction = faction,
                isSteadyFlight = isSteadyFlight,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            if data.id and WarbandNexus.ShouldExcludeMountFromCollectionBrowse then
                return not WarbandNexus:ShouldExcludeMountFromCollectionBrowse(data.id)
            end
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data then return false end
            if data.id and WarbandNexus.ShouldExcludeMountFromCollectionBrowse then
                return not WarbandNexus:ShouldExcludeMountFromCollectionBrowse(data.id)
            end
            return true
        end,
    },
    
    pet = {
        name = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets",
        iterator = function()
            if not C_PetJournal then return {} end
            
            -- Pet journal filter functions require Blizzard_Collections to be loaded
            Mat.EnsureBlizzardCollectionsLoaded()
            
            -- Save original filter state
            local origSearch = C_PetJournal.GetSearchFilter and C_PetJournal.GetSearchFilter() or ""
            
            -- Reset filters to show ALL pets for accurate scanning
            -- TAINT GUARD: Filter manipulation taints PetJournal; skip during combat to prevent blocked actions
            if not InCombatLockdown() then
                pcall(function()
                    if C_PetJournal.ClearSearchFilter then C_PetJournal.ClearSearchFilter() end
                    -- Show both collected and uncollected
                    if C_PetJournal.SetFilterChecked then
                        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_COLLECTED, true)
                        C_PetJournal.SetFilterChecked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED, true)
                    end
                    -- Show all pet types
                    if C_PetJournal.SetPetTypeFilter then
                        for i = 1, C_PetJournal.GetNumPetTypes() do
                            C_PetJournal.SetPetTypeFilter(i, true)
                        end
                    end
                    -- Show all sources
                    if C_PetJournal.SetPetSourceChecked then
                        for i = 1, C_PetJournal.GetNumPetSources() do
                            C_PetJournal.SetPetSourceChecked(i, true)
                        end
                    end
                end)
            end

            -- Capture per-source speciesID → sourceTypeIndex via filter trick (mirrors GetToysGroupedBySourceType).
            -- Pure API: Blizzard's pet journal source filter is the authoritative classifier.
            local speciesToSource = {}
            local numSources = (C_PetJournal.GetNumPetSources and C_PetJournal.GetNumPetSources()) or 0
            if numSources > 0 and C_PetJournal.SetPetSourceChecked and not InCombatLockdown() then
                pcall(function()
                    for srcIdx = 1, numSources do
                        for i = 1, numSources do
                            C_PetJournal.SetPetSourceChecked(i, i == srcIdx)
                        end
                        local nFiltered = C_PetJournal.GetNumPets() or 0
                        for j = 1, nFiltered do
                            local _, sID = C_PetJournal.GetPetInfoByIndex(j)
                            if sID and not speciesToSource[sID] then
                                speciesToSource[sID] = srcIdx
                            end
                        end
                    end
                    -- Restore "all sources visible" so the next GetNumPets/GetPetInfoByIndex pass sees every species
                    for i = 1, numSources do
                        C_PetJournal.SetPetSourceChecked(i, true)
                    end
                end)
            end
            ns._petSpeciesToSourceIndex = speciesToSource

            local numPets = C_PetJournal.GetNumPets() or 0
            
            -- Resolve speciesIDs NOW while "show all" filters are active
            -- GetPetInfoByIndex depends on current filter state
            local pets = {}
            local seen = {}
            for i = 1, numPets do
                local _, speciesID = C_PetJournal.GetPetInfoByIndex(i)
                if speciesID and not seen[speciesID] then
                    seen[speciesID] = true
                    table.insert(pets, speciesID)
                end
            end
            
            -- Restore original filter state
            -- TAINT GUARD: Same guard as above - skip restore if in combat
            if not InCombatLockdown() then
                pcall(function()
                    if origSearch and origSearch ~= "" and C_PetJournal.SetSearchFilter then
                        C_PetJournal.SetSearchFilter(origSearch)
                    end
                end)
            end
            
            return pets
        end,
        extract = function(speciesID)
            -- speciesID is now passed directly from iterator (not an index)
            if not speciesID then return nil end
            
            -- 12.1 struct API (positional list changed in 12.0.5); secret/type guards inside.
            local petInfo = Utilities:GetPetSpeciesInfo(speciesID)
            local speciesName = petInfo and petInfo.name
            if not speciesName then return nil end
            local icon, petType, companionID = petInfo.icon, petInfo.petType, petInfo.creatureID
            local source, description = petInfo.sourceText, petInfo.description
            local creatureDisplayID_extra = petInfo.displayID

            -- Filter out unobtainable pets (NPC-only, dev/test, tamer pets, cut content)
            if not petInfo.obtainable then return nil end
            
            -- Check if player owns this species
            local numCollected = C_PetJournal.GetNumCollectedInfo(speciesID)
            local owned = numCollected and numCollected > 0
            
            local creatureDisplayID = creatureDisplayID_extra
            if not creatureDisplayID and C_PetJournal.GetNumDisplays and C_PetJournal.GetDisplayIDByIndex then
                local numDisplays = C_PetJournal.GetNumDisplays(speciesID) or 0
                if numDisplays > 0 then
                    creatureDisplayID = C_PetJournal.GetDisplayIDByIndex(speciesID, 1)
                end
            end
            
            local sourceTypeIndex = ns._petSpeciesToSourceIndex and ns._petSpeciesToSourceIndex[speciesID] or nil

            return {
                id = speciesID,
                name = speciesName,
                icon = icon,
                source = source or ((ns.L and ns.L["FALLBACK_PET_COLLECTION"]) or "Pet Collection"),
                sourceTypeIndex = sourceTypeIndex,
                description = description,
                collected = owned,
                petType = petType,
                creatureDisplayID = creatureDisplayID,
                obtainable = petInfo.obtainable,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            -- Pure API hide rule: obtainable == false (Blizzard says species is unobtainable)
            if data.obtainable == false then return false end
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data then return false end
            if data.obtainable == false then return false end
            return true
        end,
    },

    toy = {
        name = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys",
        iterator = function()
            if not C_ToyBox then return {} end
            
            -- C_ToyBox filter functions require Blizzard_Collections to be loaded.
            -- Without it, GetNumFilteredToys() returns 0 and filter manipulation has no effect.
            Mat.EnsureBlizzardCollectionsLoaded()
            
            -- Save original filter state to restore after scan
            local origCollected = C_ToyBox.GetCollectedShown and C_ToyBox.GetCollectedShown()
            local origUncollected = C_ToyBox.GetUncollectedShown and C_ToyBox.GetUncollectedShown()
            local origFilterString = Mat.GetToyBoxSearchText()

            -- Capture per-source itemID → sourceTypeIndex via filter trick (Blizzard ToyBox source filter).
            -- Pure API: Blizzard's source filter is the authoritative classifier.
            local toyToSource = {}
            if WarbandNexus and WarbandNexus.GetToysGroupedBySourceType then
                local _, itemIDToSource = WarbandNexus:GetToysGroupedBySourceType()
                if itemIDToSource then
                    for k, v in pairs(itemIDToSource) do toyToSource[k] = v end
                end
            end
            ns._toyItemIDToSourceIndex = toyToSource

            -- Ensure all toys are visible for scanning (GetToyFromIndex uses filtered list)
            -- TAINT GUARD: ToyBox filter manipulation is protected; skip during combat
            if not InCombatLockdown() then
                pcall(function()
                    C_ToyBox.SetCollectedShown(true)
                    C_ToyBox.SetUncollectedShown(true)
                    C_ToyBox.SetAllSourceTypeFilters(true)
                    C_ToyBox.SetFilterString("")
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
            
            -- Try GetNumFilteredToys first; fall back to GetNumTotalDisplayedToys or GetNumToys
            local numToys = 0
            if C_ToyBox.GetNumFilteredToys then
                numToys = C_ToyBox.GetNumFilteredToys() or 0
            end
            -- If filtered count is 0, the filter may not have applied yet; try total count
            if numToys == 0 and C_ToyBox.GetNumTotalDisplayedToys then
                numToys = C_ToyBox.GetNumTotalDisplayedToys() or 0
            end
            if numToys == 0 and C_ToyBox.GetNumToys then
                numToys = C_ToyBox.GetNumToys() or 0
            end
            
            -- Resolve itemIDs NOW while "show all" filters are active.
            -- GetToyFromIndex uses the current filter state, so we must capture
            -- actual itemIDs before restoring original filters.
            local toys = {}
            for i = 1, numToys do
                local itemID = C_ToyBox.GetToyFromIndex(i)
                if itemID and itemID > 0 then
                    table.insert(toys, itemID)
                end
            end
            
            -- Restore original filter state to avoid side effects on player ToyBox UI
            -- TAINT GUARD: Same guard as above - skip restore if in combat
            if not InCombatLockdown() then
                pcall(function()
                    if origCollected ~= nil then C_ToyBox.SetCollectedShown(origCollected) end
                    if origUncollected ~= nil then C_ToyBox.SetUncollectedShown(origUncollected) end
                    if origFilterString then C_ToyBox.SetFilterString(origFilterString) end
                    if C_ToyBox.ForceToyRefilter then C_ToyBox.ForceToyRefilter() end
                end)
            end
            
            return toys
        end,
        extract = function(itemID)
            if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
            -- 12.0.5: GetToyInfo returns itemID, toyName, icon, isFavorite, hasFanfare, itemQuality
            local retItemID, toyName, toyIcon, _, _, itemQuality = C_ToyBox.GetToyInfo(itemID)
            -- If GetToyInfo returns nil for the itemID, the toy doesn't exist in the ToyBox database
            -- (internal/hidden/removed toy) — exclude it
            if not retItemID then return nil end
            if issecretvalue and toyName and issecretvalue(toyName) then toyName = nil end
            -- If name is nil/empty and retItemID is also nil, this is a ghost entry — skip
            if not toyName or toyName == "" then
                -- Try C_Item fallback for name
                if C_Item and C_Item.GetItemInfo then
                    local itemName = C_Item.GetItemInfo(itemID)
                    if itemName and type(itemName) == "string" then
                        if not (issecretvalue and issecretvalue(itemName)) and itemName ~= "" then
                            toyName = itemName
                        end
                    end
                end
            end
            local name = (toyName and toyName ~= "") and toyName or tostring(itemID)
            local collected = false
            if PlayerHasToy then
                local raw = PlayerHasToy(itemID)
                if issecretvalue and raw and issecretvalue(raw) then collected = true
                else collected = raw == true end
            end
            local sourceTypeIndex = ns._toyItemIDToSourceIndex and ns._toyItemIDToSourceIndex[itemID] or nil
            return { id = itemID, name = name, collected = collected, icon = toyIcon, itemQuality = itemQuality, sourceTypeIndex = sourceTypeIndex }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            -- Pure API: extract already returns nil for hidden/internal toys (GetToyInfo nil).
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data then return false end
            return true
        end,
    },

    achievement = {
        name = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements",
        iterator = function()
            if not GetCategoryList then return {} end
            
            local categoryList = GetCategoryList() or {}
            local allAchievements = {}
            
            for i = 1, #categoryList do
                local categoryID = categoryList[i]
                if categoryID then
                    local numAchievements = GetCategoryAchievementListCount(categoryID)
                    for achIndex = 1, numAchievements do
                        table.insert(allAchievements, {categoryID = categoryID, achIndex = achIndex})
                    end
                end
            end
            
            return allAchievements
        end,
        extract = function(item)
            local success, id, name, points, completed, month, day, year, description, flags, icon =
                GetAchievementInfoByCategoryIndex(item.categoryID, item.achIndex)
            if not success or not id then return nil end
            local displayName = SafeAchievementDisplayName(id, name)
            if not displayName then return nil end
            
            -- Get reward info
            local rewardItemID, rewardTitle
            local rewardSuccess, rewardItem, title = pcall(GetAchievementReward, id)
            if rewardSuccess then
                if type(rewardItem) == "number" then
                    rewardItemID = rewardItem
                end
                if type(title) == "string" and title ~= "" then
                    rewardTitle = title
                elseif type(rewardItem) == "string" and rewardItem ~= "" then
                    rewardTitle = rewardItem
                end
            end
            
            -- Resolve actual category
            local realCategoryID = item.categoryID
            if GetAchievementCategory then
                local actualCat = GetAchievementCategory(id)
                if actualCat and actualCat > 0 then
                    realCategoryID = actualCat
                end
            end
            
            return {
                id = id,
                name = displayName,
                icon = icon,
                points = points,
                description = description,
                source = description or ((ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement"),
                collected = completed,
                categoryID = realCategoryID,
                rewardItemID = rewardItemID,
                rewardTitle = rewardTitle,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end,
        shouldIncludeInAll = function(data)
            return data ~= nil
        end,
    },

    illusion = {
        name = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions",
        iterator = function()
            if not C_TransmogCollection or not C_TransmogCollection.GetIllusions then return {} end
            
            -- Reset debug counter for new scan
            illusionDebugCount = 0
            
            local illusions = C_TransmogCollection.GetIllusions()
            if not illusions then return {} end
            
            -- Cache the full illusion table for extract() to use
            -- This avoids calling GetIllusions() hundreds of times in extract()
            illusionRuntimeCache = {}
            
            local illusionList = {}
            for i = 1, #illusions do
                local illusionInfo = illusions[i]
                if illusionInfo and illusionInfo.sourceID then
                    -- Use sourceID (not visualID!) - GetIllusionStrings needs sourceID
                    illusionRuntimeCache[illusionInfo.sourceID] = illusionInfo
                    table.insert(illusionList, illusionInfo.sourceID)
                end
            end
            
            return illusionList
        end,
        extract = function(sourceID)
            if not C_TransmogCollection then return nil end
            
            -- Use cached illusion data for isCollected check
            local illusionInfo = illusionRuntimeCache and illusionRuntimeCache[sourceID]
            if not illusionInfo then return nil end
            
            -- CORRECT API: GetIllusionStrings(sourceID) - NOT visualID!
            local name, hyperlink, sourceText
            if C_TransmogCollection.GetIllusionStrings then
                local ok, n, h, s = pcall(C_TransmogCollection.GetIllusionStrings, sourceID)
                if ok then
                    name, hyperlink, sourceText = n, h, s
                end
            end
            if name and issecretvalue and issecretvalue(name) then name = nil end
            if sourceText and issecretvalue and issecretvalue(sourceText) then sourceText = nil end
            
            -- Fallback 1: Try basic illusion info if API returns nil
            if not name or name == "" then
                name = illusionInfo.name
            end
            
            -- Fallback 2: Try spell name from spellID if still empty
            if (not name or name == "") and illusionInfo.spellID then
                local spellName = C_Spell and C_Spell.GetSpellName(illusionInfo.spellID)
                if spellName and spellName ~= "" then
                    name = spellName
                end
            end
            
            -- Fallback 3: Use sourceID as last resort
            if not name or name == "" then
                local illusionType = (ns.L and ns.L["TYPE_ILLUSION"]) or "Illusion"
                name = ((ns.L and ns.L["FALLBACK_ILLUSION_FORMAT"]) and string.format(ns.L["FALLBACK_ILLUSION_FORMAT"], sourceID)) or (illusionType .. " " .. sourceID)
            end
            
            -- Clean up sourceText
            if not sourceText or sourceText == "" then
                sourceText = illusionInfo.sourceText or ((ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source")
            end
            
            local icon = illusionInfo.icon or 134400  -- Default icon
            local isCollected = illusionInfo.isCollected
            
            -- DEBUG: Log source info for first few illusions
            if not isCollected then
                if illusionDebugCount < 5 then
    DebugPrintf("|cff00ffff[WN DEBUG Illusion #%d]|r sourceID: %d, visualID: %d",
        illusionDebugCount + 1, sourceID, illusionInfo.visualID or 0)
    DebugPrint("  GetIllusionStrings(" .. sourceID .. ") returned:")
    DebugPrint("    name:", tostring(name))
    DebugPrint("    hyperlink:", tostring(hyperlink))
    DebugPrint("    sourceText:", tostring(sourceText))
                    
                    illusionDebugCount = illusionDebugCount + 1
                end
            end
            
            return {
                id = sourceID,  -- Use sourceID as ID
                name = name,
                icon = icon,
                sourceText = sourceText,
                source = sourceText,
                collected = isCollected,
                visualID = illusionInfo.visualID,  -- Keep for reference
                hyperlink = hyperlink,
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end,
        shouldIncludeInAll = function(data)
            if not data then return false end
            return true
        end,
    },

    title = {
        name = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles",
        iterator = function()
            if not GetNumTitles or not GetTitleName or not IsTitleKnown then return {} end
            
            local numTitles = GetNumTitles()
            if not numTitles or numTitles == 0 then return {} end
            
            local titleList = {}
            for titleMaskID = 1, numTitles do
                table.insert(titleList, titleMaskID)
            end
            
            return titleList
        end,
        extract = function(titleMaskID)
            -- Get title info
            local titleString, playerTitle = GetTitleName(titleMaskID)
            if not titleString or (issecretvalue and issecretvalue(titleString)) or titleString == "" then return nil end
            
            -- Check if player knows this title
            local isKnown = IsTitleKnown(titleMaskID)
            
            -- Format title name (remove %s placeholder)
            local displayName = titleString:gsub("%%s", ""):trim()
            
            return {
                id = titleMaskID,
                name = displayName,
                titleString = titleString,  -- Original format with %s
                playerTitle = playerTitle,  -- Boolean: true = suffix (name Title), false = prefix (Title name)
                collected = isKnown,
                iconAtlas = "poi-legendsoftheharanir",  -- Atlas icon for titles (matches TYPE_ICONS.title)
                icon = nil,  -- No texture icon, use atlas only
                source = (ns.L and ns.L["FALLBACK_PLAYER_TITLE"]) or "Player Title",
                type = "title",
            }
        end,
        shouldInclude = function(data)
            if not data or data.collected then return false end
            return true
        end,
        shouldIncludeInAll = function(data)
            return data ~= nil
        end,
    },
}
RT.COLLECTION_CONFIGS = COLLECTION_CONFIGS

---Display fields for one slim collectionStore row (2026-10-22), resolved on first read.
---Same synchronous reads the scans use for that id; the row's persisted fields are not overridden.
---@param category string mount|pet|achievement|title
---@param id number
---@return table|nil
ns.CollectionServiceRT.ResolveStoreRowDisplay = function(category, id)
    if category == "achievement" then
        if not GetAchievementInfo then return nil end
        local ok, achID, name, _, _, _, _, _, description, _, icon, rewardText = pcall(GetAchievementInfo, id)
        if not ok or not achID then return nil end
        local _sv = issecretvalue
        local rewardItemID, rewardTitle
        local rewardSuccess, item, title = pcall(GetAchievementReward, id)
        if rewardSuccess then
            if type(item) == "number" then rewardItemID = item end
            if type(title) == "string" and title ~= "" and not (_sv and _sv(title)) then
                rewardTitle = title
            elseif type(item) == "string" and item ~= "" and not (_sv and _sv(item)) then
                rewardTitle = item
            end
        end
        if not rewardTitle and rewardText and rewardText ~= "" and not (_sv and _sv(rewardText)) then
            rewardTitle = rewardText
        end
        local categoryID
        if GetAchievementCategory then
            local cat = GetAchievementCategory(id)
            if cat and cat > 0 then categoryID = cat end
        end
        return {
            name = SafeAchievementDisplayName(id, name),
            icon = (icon and not (_sv and _sv(icon))) and icon or nil,
            description = (description and not (_sv and _sv(description))) and description or nil,
            categoryID = categoryID,
            rewardItemID = rewardItemID,
            rewardTitle = rewardTitle,
        }
    end
    local config = COLLECTION_CONFIGS[category]
    if not config or not config.extract then return nil end
    local ok, data = pcall(config.extract, id)
    if ok and type(data) == "table" then return data end
    return nil
end

---Scan a collection type asynchronously (coroutine-based with duplicate protection)
function WarbandNexus:ScanCollection(collectionType, onProgress, onComplete)
    DebugPrint("|cff9370DB[WN CollectionService]|r ScanCollection called for: " .. tostring(collectionType))
    
    -- Ensure Blizzard_Collections is loaded (required for icons, source text, toy filters)
    Mat.EnsureBlizzardCollectionsLoaded()
    
    local config = COLLECTION_CONFIGS[collectionType]
    if not config then
    DebugPrint("|cffff4444[WN CollectionService ERROR]|r Invalid collection type: " .. tostring(collectionType))
        return
    end
    
    -- Prevent duplicate scans (already scanning)
    if activeCoroutines[collectionType] then
        local existing = activeCoroutines[collectionType]
        if existing and coroutine.status(existing) ~= "dead" then
            DebugPrint("|cffffcc00[WN CollectionService]|r Scan already in progress for: " .. tostring(collectionType) .. ", chaining callback")
            if onComplete then
                scanCompleteCallbacks[collectionType] = onComplete
            end
            return
        end
        activeCoroutines[collectionType] = nil
    end

    scanCompleteCallbacks[collectionType] = onComplete
    
    -- Check if scan is needed (collectionStore or collectionCache populated and current)
    local storeHasData = collectionStore[collectionType] and next(collectionStore[collectionType]) ~= nil
    local cacheHasData = collectionCache.uncollected[collectionType] and next(collectionCache.uncollected[collectionType]) ~= nil
    local cacheExists = storeHasData or cacheHasData
    if cacheExists then
        local lastScan = collectionCache.lastScan or 0
        local timeSinceLastScan = time() - lastScan
        
        -- If cache exists and scan was recent (< 5 minutes), skip
        if timeSinceLastScan < 300 then
            DebugPrint("|cffffcc00[WN CollectionService]|r Cache exists and recent for " .. tostring(collectionType) .. " (scanned " .. timeSinceLastScan .. "s ago), skipping scan")
            InvokeScanCompleteCallback(collectionType, collectionStore[collectionType] or {})
            return
        end
    end
    
    DebugPrint("|cff00ff00[WN CollectionService]|r Starting background scan: " .. tostring(collectionType))
    
    -- Initialize loading state for UI
    if not ns.PlansLoadingState then ns.PlansLoadingState = {} end
    if not ns.PlansLoadingState[collectionType] then
        ns.PlansLoadingState[collectionType] = { isLoading = false, loader = nil }
    end
    
    -- Set loading state to true
    ns.PlansLoadingState[collectionType].isLoading = true
    ns.PlansLoadingState[collectionType].loadingProgress = 0
    ns.PlansLoadingState[collectionType].currentStage = "Preparing..."
    
    local co = coroutine.create(function()
        local startTime = debugprofilestop()
        local results = {}
        local items = {}
        local matBudget = FRAME_BUDGET_MS
        if collectionType == "pet" then
            local st = nil
            local matSteps = 0
            local MAX_MATERIALIZE_STEPS = 200000
            while true do
                matSteps = matSteps + 1
                if matSteps > MAX_MATERIALIZE_STEPS then
                    DebugPrint("|cffff0000[WN CollectionService]|r Pet materialize exceeded step cap; aborting scan")
                    items = {}
                    break
                end
                st = Mat.PetJournalBuildMaterializeStep(matBudget, st)
                if st.done then
                    items = st.items
                    ns._petSpeciesToSourceIndex = st.speciesToSource
                    break
                end
                coroutine.yield()
            end
        elseif collectionType == "toy" then
            local st = nil
            local matSteps = 0
            local MAX_MATERIALIZE_STEPS = 200000
            while true do
                matSteps = matSteps + 1
                if matSteps > MAX_MATERIALIZE_STEPS then
                    DebugPrint("|cffff0000[WN CollectionService]|r Toy materialize exceeded step cap; aborting scan")
                    items = {}
                    break
                end
                st = Mat.ToyBoxBuildMaterializeStep(matBudget, st, self)
                if st.done then
                    items = st.items
                    ns._toyItemIDToSourceIndex = st.toyToSource
                    if ns._toyItemIDToSourceIndexCache then
                        ns._toyItemIDToSourceIndexCache.map = st.toyToSource
                    end
                    break
                end
                coroutine.yield()
            end
        else
            items = config.iterator()
        end
        local total = #items
        local Constants = ns.Constants

        -- Handle empty collection (nothing to scan)
        if total == 0 then
            local retryKey = "__" .. collectionType .. "ScanRetryCount"
            local retryTypes = { toy = true, illusion = true, title = true }
            if retryTypes[collectionType] then
                local retryCount = ns[retryKey] or 0
                if retryCount < 3 then
                    ns[retryKey] = retryCount + 1
                    ns.PlansLoadingState[collectionType].isLoading = true
                    ns.PlansLoadingState[collectionType].currentStage = "Retrying..."
                    if collectionType == "illusion" or collectionType == "title" or collectionType == "toy" then
                        if Mat.ResetBlizzardCollectionsLoadState then
                            Mat.ResetBlizzardCollectionsLoadState()
                        elseif ns.ResetBlizzardCollectionsLoadState then
                            ns.ResetBlizzardCollectionsLoadState()
                        end
                        Mat.EnsureBlizzardCollectionsLoaded()
                    end
                    DebugPrint("|cffffcc00[WN CollectionService]|r " .. collectionType .. " scan returned 0 results, scheduling retry " .. (retryCount + 1) .. "/3")
                    local addon = self
                    local pendingCb = scanCompleteCallbacks[collectionType]
                    C_Timer.After(0.5, function()
                        activeCoroutines[collectionType] = nil
                        if addon and addon.ScanCollection then
                            addon:ScanCollection(collectionType, onProgress, pendingCb)
                        end
                    end)
                    return
                end
                ns[retryKey] = nil
            end
            if retryTypes[collectionType] then
                -- Toy/title/illusion APIs should not be empty once Blizzard data is hydrated.
                -- Preserve the existing store and leave the category retryable instead of
                -- persisting a transient zero-result scan as authoritative completion.
                ClearCategoryScanComplete(collectionType)
                ns.PlansLoadingState[collectionType].isLoading = false
                ns.PlansLoadingState[collectionType].loadingProgress = 0
                ns.PlansLoadingState[collectionType].currentStage = "Waiting for data..."
                SendCollectionScanProgress(self, collectionType, 0, 0, 0)
                InvokeScanCompleteCallback(collectionType, collectionStore[collectionType] or results)
                if Constants and Constants.EVENTS then
                    self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, {
                        category = collectionType,
                        results = collectionStore[collectionType] or results,
                        retryableEmptyScan = true,
                    })
                end
                return
            end
            if collectionStore[collectionType] ~= nil then
                collectionStore[collectionType] = results
            end
            collectionCache.uncollected[collectionType] = results
            collectionCache.lastScan = time()
            ns.PlansLoadingState[collectionType].isLoading = false
            ns.PlansLoadingState[collectionType].loadingProgress = 100
            ns.PlansLoadingState[collectionType].currentStage = "Complete!"
            SendCollectionScanProgress(self, collectionType, 100, 0, 0)
            InvokeScanCompleteCallback(collectionType, results)
            if Constants and Constants.EVENTS then
                self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, { category = collectionType, results = results, elapsed = 0 })
            end
            self:SaveCollectionCache()
            return
        end

        SendCollectionScanProgress(self, collectionType, 0, 0, total)

        local shouldIncludeFn = config.shouldIncludeInAll or config.shouldInclude
        for i = 1, #items do
            local item = items[i]
            local data = config.extract(item)

            if data and data.id and shouldIncludeFn and shouldIncludeFn(data) then
                results[data.id] = data
            end

            -- PROGRESSIVE UPDATE: Update loading state every 50 items
            if i % 50 == 0 or i == total then
                local progress = math.min(99, math.floor((i / total) * 100))
                ns.PlansLoadingState[collectionType].loadingProgress = progress
                ns.PlansLoadingState[collectionType].currentStage = string.format("Scanning %s... (%d/%d)", config.name, i, total)
                
                -- Fire progress event for UI refresh
                SendCollectionScanProgress(self, collectionType, progress, i, total)
            end
            
            -- Progress callback (legacy)
            if onProgress and i % BATCH_SIZE == 0 then
                onProgress(i, total, data)
            end
            
            -- Yield every BATCH_SIZE items (frame budget management)
            if i % BATCH_SIZE == 0 then
                -- Check if scan was aborted (tab switch)
                if not activeCoroutines[collectionType] then
    DebugPrint("|cffffcc00[WN CollectionService]|r Scan aborted for: " .. collectionType)
                    ns.PlansLoadingState[collectionType].isLoading = false
                    InvokeScanCompleteCallback(collectionType, results)
                    return
                end
                coroutine.yield()
            end
        end
        
        -- Merkezi kaynak: collectionStore'a tam veri yaz (mount, pet, toy, achievement, title, illusion)
        -- Preserve collected=true from incremental updates (OnNewMount etc.) that may have
        -- run AFTER the scan already processed that ID — prevents race condition overwrite.
        if collectionStore[collectionType] ~= nil then
            local oldStore = collectionStore[collectionType]
            for id, data in pairs(results) do
                if not data.collected and oldStore[id] and oldStore[id].collected == true then
                    data.collected = true
                end
            end
            collectionStore[collectionType] = results
        end
        -- collectionCache.uncollected: id->name map (uncollected only)
        local uncollectedMap = {}
        for id, d in pairs(results) do
            if d and (d.collected == false or d.collected == nil) then
                uncollectedMap[id] = (d.name and d.name ~= "") and d.name or ("ID:" .. tostring(id))
            end
        end
        collectionCache.uncollected[collectionType] = uncollectedMap
        collectionCache.lastScan = time()
        collectionStore.lastBuilt = time()
        if collectionType == "illusion" or collectionType == "title" then
            MarkCategoryScanComplete(collectionType)
        end

        -- FINAL PROGRESS: Set to 100%
        ns.PlansLoadingState[collectionType].loadingProgress = 100
        ns.PlansLoadingState[collectionType].currentStage = "Complete!"
        
        -- Fire final progress event (100%)
        SendCollectionScanProgress(self, collectionType, 100, total, total)
        
        local elapsed = debugprofilestop() - startTime
        local uncollectedCount = 0
        for _ in pairs(results) do uncollectedCount = uncollectedCount + 1 end
        DebugPrintf("|cff00ff00[WN CollectionService]|r Scan complete: %s - %d total, %d uncollected, %.2fms",
            config.name, total, uncollectedCount, elapsed)
        
        -- Verbose-only: listing every cache key is O(categories); skip when debug verbose is off
        if ns.IsDebugVerboseEnabled and ns.IsDebugVerboseEnabled() then
            DebugPrint("|cff00ccff[WN CollectionService DEBUG]|r Cache written to key: '" .. collectionType .. "'")
            DebugPrint("|cff00ccff[WN CollectionService DEBUG]|r Cache now has keys:")
            for key, value in pairs(collectionCache.uncollected) do
                local itemCount = 0
                for _ in pairs(value) do itemCount = itemCount + 1 end
                DebugPrint("|cff00ccff[WN CollectionService]|r   - '" .. key .. "' = " .. itemCount .. " items")
            end
        end
        
        -- PERSIST TO DB (avoid re-scanning on reload)
        self:SaveCollectionCache()
        
        -- Clean up runtime caches (illusion, transmog, etc.)
        if collectionType == "illusion" and illusionRuntimeCache then
            illusionRuntimeCache = nil
            DebugPrint("|cff9370DB[WN CollectionService]|r Cleared runtime cache for illusions")
        end
        
        -- Set loading state to false (scan complete)
        ns.PlansLoadingState[collectionType].isLoading = false

        InvokeScanCompleteCallback(collectionType, results)
        
        -- Fire completion event
        if Constants and Constants.EVENTS then
            self:SendMessage(Constants.EVENTS.COLLECTION_SCAN_COMPLETE, {
                category = collectionType,
                results = results,
                elapsed = elapsed,
            })
        end
        
        -- UI refreshes via WN_COLLECTION_SCAN_COMPLETE listener in UI.lua (event-driven).
        
    end)
    
    -- Store coroutine; resume with FRAME_BUDGET_MS (same pattern as ScanAchievementsAsync)
    activeCoroutines[collectionType] = co

    local function resetScanLoadingStateOnError()
        if ns.PlansLoadingState and ns.PlansLoadingState[collectionType] then
            ns.PlansLoadingState[collectionType].isLoading = false
            ns.PlansLoadingState[collectionType].loadingProgress = 0
            ns.PlansLoadingState[collectionType].currentStage = "Error"
        end
    end

    local function resumeCoroutine()
        local coRef = activeCoroutines[collectionType]
        if not coRef then return end
        if InCombatLockdown and InCombatLockdown() then
            C_Timer.After(0, resumeCoroutine)
            return
        end
        if coroutine.status(coRef) == "dead" then
            activeCoroutines[collectionType] = nil
            return
        end

        local budget = FRAME_BUDGET_MS
        local startTime = debugprofilestop()
        while (debugprofilestop() - startTime) < budget do
            local success, err = coroutine.resume(coRef)
            if not success then
                self:Debug("CollectionService: Scan error - " .. tostring(err))
                activeCoroutines[collectionType] = nil
                resetScanLoadingStateOnError()
                InvokeScanCompleteCallback(collectionType, {})
                return
            end
            if coroutine.status(coRef) == "dead" then
                activeCoroutines[collectionType] = nil
                return
            end
        end
        C_Timer.After(0, resumeCoroutine)
    end

    resumeCoroutine()
end
