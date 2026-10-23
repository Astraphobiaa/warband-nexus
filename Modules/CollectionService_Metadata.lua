--[[ CollectionService collection metadata resolve + toy source text (split from CollectionService.lua) ]]
local _, ns = ...
local WarbandNexus = ns.WarbandNexus
local RT = assert(ns.CollectionServiceRT, 'CollectionService_Metadata: load CollectionService.lua first')
local issecretvalue = issecretvalue
local Utilities = ns.Utilities
local Mat = ns.CollectionMaterialize
local collectionStore = RT.collectionStore
local collectionData = collectionStore
local WipeUncollectedResultsCacheAndMergedAchievements = RT.WipeUncollectedResultsCacheAndMergedAchievements

-- Session-only RAM cache for collection metadata (icon, source, description). Cleared on tab leave / reload.
local METADATA_CACHE_MAX = 512
local metadataCache = {}
local metadataCacheOrder = {}   -- Circular buffer
local metadataCacheHead = 1     -- Circular buffer head index

---Session-only metadata cache: circular buffer eviction (O(1) instead of O(n) table.remove).
local function metadataCacheSet(cacheKey, meta)
    if #metadataCacheOrder >= METADATA_CACHE_MAX then
        local oldKey = metadataCacheOrder[metadataCacheHead]
        if oldKey then metadataCache[oldKey] = nil end
        metadataCacheOrder[metadataCacheHead] = cacheKey
        metadataCacheHead = (metadataCacheHead % METADATA_CACHE_MAX) + 1
    else
        metadataCacheOrder[#metadataCacheOrder + 1] = cacheKey
    end
    metadataCache[cacheKey] = meta
end

local function GetToyFallbackSources()
    local fallback1 = (ns.L and ns.L["FALLBACK_TOY_COLLECTION"]) or "Toy Collection"
    local fallback2 = (ns.L and ns.L["FALLBACK_TOY_BOX"]) or "Toy Box"
    local fallback3 = (ns.L and ns.L["FALLBACK_WARBAND_TOY"]) or "Warband Toy"
    return fallback1, fallback2, fallback3
end

local function IsToySourceGeneric(sourceText)
    local fallback1, fallback2, fallback3 = GetToyFallbackSources()
    return not sourceText or sourceText == "" or sourceText == fallback1 or sourceText == fallback2 or sourceText == fallback3
end

local function TrimText(text)
    if type(text) ~= "string" then return "" end
    if issecretvalue and issecretvalue(text) then return "" end
    return text:gsub("^%s+", ""):gsub("%s+$", "")
end

---Validate that toy source text is source-like (not random tooltip garbage).
---@return boolean
function WarbandNexus:IsReliableToySource(sourceText)
    if type(sourceText) ~= "string" then return false end
    if issecretvalue and issecretvalue(sourceText) then return false end
    local s = TrimText(sourceText)
    if s == "" or IsToySourceGeneric(s) then return false end

    if s:find("|c", 1, true) or s:find("|r", 1, true) or s:find("|T", 1, true) or s:find("|H", 1, true) then
        return false
    end

    local L = ns.L
    local sourceLabel = ((L and L["SOURCE_LABEL"]) or "Source:"):gsub("[:%s]+$", "")
    local keywords = {
        BATTLE_PET_SOURCE_1 or "Drop",
        BATTLE_PET_SOURCE_2 or "Quest",
        BATTLE_PET_SOURCE_3 or "Vendor",
        BATTLE_PET_SOURCE_4 or "Profession",
        BATTLE_PET_SOURCE_5 or "Pet Battle",
        BATTLE_PET_SOURCE_6 or "Achievement",
        BATTLE_PET_SOURCE_7 or "World Event",
        BATTLE_PET_SOURCE_8 or "Promotion",
        (L and L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",
        (L and L["SOURCE_TYPE_TREASURE"]) or "Treasure",
        (L and L["PARSE_SOLD_BY"]) or "Sold by",
        (L and L["PARSE_CONTAINED_IN"]) or "Contained in",
        (L and L["PARSE_ZONE"]) or ZONE or "Zone",
        (L and L["PARSE_COST"]) or "Cost",
        (L and L["PARSE_AMOUNT"]) or "Amount",
        (L and L["ZONE_DROP"]) or "Zone drop",
        (L and L["FISHING"]) or "Fishing",
        sourceLabel,
    }

    for i = 1, #keywords do
        local kw = keywords[i]
        if type(kw) == "string" and kw ~= "" then
            local escaped = kw:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1")
            if s:match("^%s*" .. escaped .. "%s*:") or s:match("^%s*" .. escaped .. "%s") then
                return true
            end
        end
    end

    return false
end

---Single place for toy metadata: C_ToyBox.GetToyInfo (name, icon, itemQuality) + tooltip (source, description) + CollectibleSourceDB when tooltip is fallback.
---API note: GetToyInfo returns itemID, toyName, icon, isFavorite, hasFanfare, itemQuality — no sourceText; source comes from tooltip/DB.
---@return table|nil { name, icon, source, description, itemQuality } or nil
function WarbandNexus:GetToySourceInfo(itemID)
    if not itemID or not C_ToyBox or not C_ToyBox.GetToyInfo then return nil end
    -- Session cache: reuse only when source already validated as meaningful.
    local cache = WarbandNexus.toySourceInfoCache
    if cache and cache[itemID] then
        local c = cache[itemID]
        if self:IsReliableToySource(c.source) then
            return c
        end
    end

    local _, name, icon, _, _, itemQuality = C_ToyBox.GetToyInfo(itemID)
    if not name then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    if not icon and (C_Item and C_Item.GetItemInfo) then
        local _, _, _, _, _, _, _, _, _, itemTexture = C_Item.GetItemInfo(itemID)
        if itemTexture then icon = itemTexture end
    end

    local sourceText = ""
    local descriptionText = ""
    -- Prefer GetToyByItemID: toy tooltip often has "Source:"; GetItemByID returns item tooltip (e.g. weapon stats) with no source line
    local tooltipData = nil
    if C_TooltipInfo then
        if C_TooltipInfo.GetToyByItemID then
            tooltipData = C_TooltipInfo.GetToyByItemID(itemID)
        end
        if (not tooltipData or not tooltipData.lines or #tooltipData.lines == 0) and C_TooltipInfo.GetItemByID then
            tooltipData = C_TooltipInfo.GetItemByID(itemID)
        end
    end
    local _issecretvalue = issecretvalue
    local function safeText(t)
        if not t or type(t) ~= "string" then return nil end
        if _issecretvalue and _issecretvalue(t) then return nil end
        return t
    end
    local function stripColorCodes(s)
        -- nil-passthrough: callers below fall back to other sources when this stays nil
        if not s or type(s) ~= "string" then return s end
        return Utilities:StripFormattingCodes(s)
    end
    local sourceKeywords = {
        BATTLE_PET_SOURCE_1 or "Drop",
        BATTLE_PET_SOURCE_3 or "Vendor",
        BATTLE_PET_SOURCE_2 or "Quest",
        BATTLE_PET_SOURCE_4 or "Profession",
        BATTLE_PET_SOURCE_7 or "World Event",
        BATTLE_PET_SOURCE_8 or "Promotion",
        (ns.L and ns.L["SOURCE_TYPE_TRADING_POST"]) or "Trading Post",
        (ns.L and ns.L["SOURCE_TYPE_TREASURE"]) or "Treasure",
        (ns.L and ns.L["PARSE_ZONE"]) or ZONE or "Zone",
    }
    local sourceLabel = (ns.L and ns.L["SOURCE_LABEL"]) or "Source:"
    local sourceLabelClean = sourceLabel:gsub("[:%s]+$", "")

    local function isSourceLine(line)
        if not line then return false end
        if line.type == 2 or line.type == 25 then return true end
        local left = safeText(line.leftText)
        local right = safeText(line.rightText)
        if left and sourceLabelClean ~= "" and left:find(sourceLabelClean, 1, true) then return true end
        if right and sourceLabelClean ~= "" and right:find(sourceLabelClean, 1, true) then return true end
        -- Only treat as source if line starts with "Keyword:" so description text containing "drop" etc. is not misclassified
        for i = 1, #sourceKeywords do
            local kw = sourceKeywords[i]
            local escaped = kw:gsub("%%", "%%%%")
            if (left and left:match("^%s*" .. escaped .. "%s*:")) or (right and right:match("^%s*" .. escaped .. "%s*:")) then
                return true
            end
        end
        return false
    end

    if tooltipData and tooltipData.lines then
        local sourceParts = {}
        local descParts = {}
        local lines = tooltipData.lines
        for i = 1, #lines do
            local line = lines[i]
            local left = safeText(line.leftText)
            local right = safeText(line.rightText)
            local lineText = (left and left ~= "" and left) or (right and right ~= "" and right) or nil
            if not lineText then
            elseif isSourceLine(line) then
                -- If line is "Source:" + right-side payload, prefer right-side text.
                if left and right and sourceLabelClean ~= "" and left:find(sourceLabelClean, 1, true) then
                    sourceParts[#sourceParts + 1] = right
                else
                    sourceParts[#sourceParts + 1] = lineText
                end
            elseif i > 1 then
                descParts[#descParts + 1] = lineText
            end
        end
        if #sourceParts > 0 then
            sourceText = table.concat(sourceParts, "\n")
        end
        if #descParts > 0 then
            descriptionText = table.concat(descParts, "\n")
        end
    end
    local fallback1 = GetToyFallbackSources()
    if IsToySourceGeneric(sourceText) then
        local dbSource = ns.CollectibleSourceDB and ns.CollectibleSourceDB.GetSourceStringForToy and ns.CollectibleSourceDB.GetSourceStringForToy(itemID)
        if dbSource and dbSource ~= "" then
            sourceText = dbSource
        end
    end
    sourceText = stripColorCodes(sourceText)
    descriptionText = stripColorCodes(descriptionText)
    if not self:IsReliableToySource(sourceText) then
        sourceText = fallback1
    end
    -- Ensure space before and after every colon in source (e.g. "Vendor:Orix" -> "Vendor : Orix")
    sourceText = sourceText:gsub("([^%s]):([^%s])", "%1 : %2")
    local result = {
        name = name,
        icon = icon,
        source = sourceText,
        description = descriptionText,
        itemQuality = itemQuality,
    }
    -- Session cache (no invalidation; name/source/icon do not change on collect)
    if not WarbandNexus.toySourceInfoCache then WarbandNexus.toySourceInfoCache = {} end
    WarbandNexus.toySourceInfoCache[itemID] = result
    return result
end

---Resolve icon/source/description for a collection entry on demand. Uses session RAM cache; cleared on tab leave.
---Mount metadata is API-authoritative to avoid stale legacy DB source text in Plans.
---@return table|nil { name, icon, source, description, ... } or nil if API fails
function WarbandNexus:ResolveCollectionMetadata(collectionType, id)
    if not id or not collectionType then return nil end
    local cacheKey = collectionType .. ":" .. tostring(id)
    local cachedMeta = metadataCache[cacheKey]
    if cachedMeta then
        if collectionType ~= "mount" then
            return cachedMeta
        end
        -- Mount source text may be stale after DB migrations — re-validate, but only
        -- once per 30 seconds to avoid repeated API calls during tab switching/scrolling.
        local cacheAge = cachedMeta._cacheTime and (debugprofilestop() - cachedMeta._cacheTime) or 999999
        if cacheAge < 30000 then return cachedMeta end -- 30s TTL (debugprofilestop is in ms)
        local cachedSource = cachedMeta.source
        if type(cachedSource) == "string" then
            local sourceTrimmed = cachedSource:gsub("^%s+", ""):gsub("%s+$", "")
            local unknownSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
            local sourceUnknown = (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
            if sourceTrimmed ~= "" and sourceTrimmed ~= "Legacy" and sourceTrimmed ~= "Unknown" and sourceTrimmed ~= unknownSource and sourceTrimmed ~= sourceUnknown then
                return cachedMeta
            end
        else
            return cachedMeta
        end
        metadataCache[cacheKey] = nil
    end

    -- Keep a DB fallback for mounts only when API data is temporarily unavailable.
    local mountFallbackMeta = nil
    if collectionType == "mount" and collectionData.mount and collectionData.mount[id] then
        local d = collectionData.mount[id]
        mountFallbackMeta = {
            name = d.name,
            icon = d.icon or "Interface\\Icons\\Ability_Mount_RidingHorse",
            source = d.source or "",
            description = d.description or "",
            creatureDisplayID = d.creatureDisplayID,
            isCollected = d.collected,
        }
    end
    -- Prefer full collection data from DB (no API calls) for non-mount types.
    if collectionType == "pet" and collectionData.pet and collectionData.pet[id] then
        local d = collectionData.pet[id]
        local meta = {
            name = d.name,
            icon = d.icon or "Interface\\Icons\\INV_Box_PetCarrier_01",
            source = d.source or "",
            description = d.description or "",
            isCollected = d.collected,
            creatureDisplayID = d.creatureDisplayID,
        }
        -- A slim pet row whose API data is not ready yet reads back the "ID:<id>" placeholder;
        -- caching that would keep the placeholder for the whole session.
        if meta.name ~= ("ID:" .. tostring(id)) then
            metadataCache[cacheKey] = meta
        end
        return meta
    end
    if collectionType == "toy" and collectionData.toy and collectionData.toy[id] then
        local d = collectionData.toy[id]
        local source = self:GetToySourceTypeNameForItem(id) or ((ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown")
        if source == "SOURCE_UNKNOWN" then source = "Unknown" end
        local description = d.description or ""
        if description == "" then
            local info = self:GetToySourceInfo(id)
            if info and info.description and info.description ~= "" then description = info.description end
        end
        -- Resolve icon from API when not stored (toys only store id+name in DB)
        local icon = d.icon
        if not icon or icon == "" then
            Mat.EnsureBlizzardCollectionsLoaded()
            if C_ToyBox and C_ToyBox.GetToyInfo then
                local _, _, apiIcon = C_ToyBox.GetToyInfo(id)
                if apiIcon and apiIcon ~= 0 then icon = apiIcon end
            end
            if not icon or icon == "" then
                local info = self:GetToySourceInfo(id)
                if info and info.icon and info.icon ~= "" then icon = info.icon end
            end
        end
        local meta = {
            name = d.name,
            icon = icon or "Interface\\Icons\\INV_Misc_Toy_07",
            source = source,
            description = description,
            isCollected = d.collected,
        }
        metadataCache[cacheKey] = meta
        return meta
    end

    -- Ensure Blizzard_Collections is loaded (required for icons, source text)
    Mat.EnsureBlizzardCollectionsLoaded()

    local meta = nil
    -- Helper: treat 0 and nil as invalid icon (0 is truthy in Lua but invalid fileID)
    local function validIcon(icon)
        if icon and icon ~= 0 then return icon end
        return nil
    end

    -- Track whether we got a real icon from API or used fallback
    local usedFallbackIcon = false
    
    -- Do NOT use `X and X.func()` pattern for multi-return APIs!
    -- In Lua 5.1, `X and func()` truncates to 1 return value because `and` is a
    -- binary expression, not a function call. Only raw function calls at the tail
    -- of an expression list preserve multiple returns.

    if collectionType == "mount" then
        if not C_MountJournal or not C_MountJournal.GetMountInfoByID then return nil end
        local name, spellID, icon, _, _, sourceType, _, _, _, _, isCollected = C_MountJournal.GetMountInfoByID(id)
        if name then
            icon = validIcon(icon)
            -- Fallback: spell texture
            if not icon and spellID then
                if C_Spell and C_Spell.GetSpellTexture then
                    icon = validIcon(C_Spell.GetSpellTexture(spellID))
                end
            end
            if not icon then usedFallbackIcon = true end
            local _, description, source = C_MountJournal.GetMountInfoExtraByID(id)
            if issecretvalue and issecretvalue(sourceType) then sourceType = nil end
            if (not sourceType or sourceType == 0) and self.GetMountBrowseSourceType then
                local resolved = self:GetMountBrowseSourceType(id)
                if resolved and resolved > 0 then sourceType = resolved end
            end
            meta = { name = name, icon = icon or "Interface\\Icons\\Ability_Mount_RidingHorse", source = source or "", sourceType = sourceType, description = description or "" }
            -- Current collected state (Midnight: isCollected may be secret)
            if issecretvalue and issecretvalue(isCollected) then
                meta.isCollected = true
            else
                meta.isCollected = isCollected == true
            end
        end
    elseif collectionType == "pet" then
        if not C_PetJournal then return nil end
        -- 12.1 struct API (positional list changed in 12.0.5); secret/type guards inside.
        local petInfo = Utilities:GetPetSpeciesInfo(id)
        local name = petInfo and petInfo.name
        if name then
            -- Filter unobtainable pets (pure API)
            if not petInfo.obtainable then return nil end
            local source, description = petInfo.sourceText, petInfo.description
            local icon = validIcon(petInfo.icon)
            if not icon then usedFallbackIcon = true end
            local creatureDisplayID = nil
            if C_PetJournal.GetNumDisplays and C_PetJournal.GetDisplayIDByIndex then
                local numDisplays = C_PetJournal.GetNumDisplays(id) or 0
                if numDisplays > 0 then
                    creatureDisplayID = C_PetJournal.GetDisplayIDByIndex(id, 1)
                end
            end
            local numCollected = C_PetJournal.GetNumCollectedInfo and C_PetJournal.GetNumCollectedInfo(id)
            local isCollected = numCollected and numCollected > 0
            local sourceTypeIndex = (collectionStore.pet and collectionStore.pet[id] and collectionStore.pet[id].sourceTypeIndex)
                or (ns._petSpeciesToSourceIndex and ns._petSpeciesToSourceIndex[id])
                or nil
            meta = { name = name, icon = icon or "Interface\\Icons\\INV_Box_PetCarrier_01", source = source or "", sourceTypeIndex = sourceTypeIndex, description = description or "", creatureDisplayID = creatureDisplayID, isCollected = isCollected, obtainable = petInfo.obtainable }
        end
    elseif collectionType == "toy" then
        local info = self:GetToySourceInfo(id)
        if info then
            local icon = validIcon(info.icon)
            if not icon then usedFallbackIcon = true end
            local isCollected
            if PlayerHasToy then
                local isCollectedRaw = PlayerHasToy(id)
                if issecretvalue and issecretvalue(isCollectedRaw) then
                    isCollected = true
                else
                    isCollected = isCollectedRaw == true
                end
            end
            local sourceLine = self:GetToySourceTypeNameForItem(id) or ((ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown")
            if sourceLine == "SOURCE_UNKNOWN" then sourceLine = "Unknown" end
            local sourceTypeIndex = self:GetToySourceTypeIndexForItem(id)
            meta = {
                name = info.name,
                icon = icon or "Interface\\Icons\\INV_Misc_Toy_07",
                source = sourceLine,
                sourceTypeIndex = sourceTypeIndex,
                description = info.description or "",
                itemQuality = info.itemQuality,
                isCollected = isCollected,
            }
        end
    elseif collectionType == "achievement" then
        local ok, _, achName, points, _, _, _, _, description, _, achIcon, achRewardText = pcall(GetAchievementInfo, id)
        if ok and achName then
            achIcon = validIcon(achIcon)
            local categoryID = GetAchievementCategory and GetAchievementCategory(id) or nil
            local rewardItemID, rewardTitle
            local rewardOk, rItem, rTitle = pcall(GetAchievementReward, id)
            if rewardOk then
                if type(rItem) == "number" then rewardItemID = rItem end
                if type(rTitle) == "string" and rTitle ~= "" then
                    rewardTitle = rTitle
                elseif type(rItem) == "string" and rItem ~= "" then
                    rewardTitle = rItem
                end
            end
            if not rewardTitle and achRewardText and achRewardText ~= "" then
                rewardTitle = achRewardText
            end
            meta = { name = achName, icon = achIcon or "Interface\\Icons\\Achievement_General", points = points or 0, description = description or "", source = description or "", categoryID = categoryID, rewardItemID = rewardItemID, rewardTitle = rewardTitle, rewardText = rewardTitle }
        end
    elseif collectionType == "illusion" then
        if not C_TransmogCollection or not C_TransmogCollection.GetIllusionStrings then return nil end
        local name, _, sourceText = C_TransmogCollection.GetIllusionStrings(id)
        if name then
            local illusionIcon = nil
            local illusionSourceFallback = nil
            if C_TransmogCollection.GetIllusionInfo then
                local illusionInfo = C_TransmogCollection.GetIllusionInfo(id)
                if illusionInfo then
                    illusionIcon = validIcon(illusionInfo.icon)
                    -- (TransmogIllusionInfo has no sourceText; GetIllusionStrings above is the only source.)
                end
            end
            local resolvedSource = sourceText
            if not resolvedSource or resolvedSource == "" then
                resolvedSource = illusionSourceFallback or ((ns.L and ns.L["SOURCE_ENCHANTING"]) or "Enchanting")
            end
            meta = { name = name, icon = illusionIcon or "Interface\\Icons\\INV_Enchant_Disenchant", source = resolvedSource, description = "" }
        end
    elseif collectionType == "title" then
        if not GetTitleName then return nil end
        local titleString = GetTitleName(id)
        if not (issecretvalue and issecretvalue(titleString)) and titleString then
            meta = { name = titleString, icon = "Interface\\Icons\\INV_Scroll_11", source = "", description = "" }
        end
    end

    if not meta and collectionType == "mount" and mountFallbackMeta then
        meta = mountFallbackMeta
    end

    if meta then
        meta.id = id
        meta.type = collectionType
        meta.collected = meta.isCollected or false
        if meta.isCollected == nil then
            meta.isCollected = false
        end
        -- Only permanently cache metadata with real API icons.
        -- If fallback icon was used (API returned 0/nil), DON'T cache — allow re-query
        -- on next access so the real icon can be resolved once the data is available.
        if not usedFallbackIcon then
            if collectionType == "mount" then meta._cacheTime = debugprofilestop() end
            metadataCacheSet(cacheKey, meta)
        end
    end
    return meta
end

---Clear session-only metadata cache (call when user leaves Plans tab to free RAM).
function WarbandNexus:ClearCollectionMetadataCache()
    wipe(metadataCache)
    wipe(metadataCacheOrder)
    metadataCacheHead = 1
    WipeUncollectedResultsCacheAndMergedAchievements()
    if ns._toyItemIDToSourceIndexCache then ns._toyItemIDToSourceIndexCache.map = nil end
end
