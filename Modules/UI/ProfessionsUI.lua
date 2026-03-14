--[[
    Warband Nexus - Professions Tab

    Layout: Single row per character, two profession lines stacked vertically.
    Character ordering mirrors CharactersUI (favorites, regular, untracked).
    Collapsible section headers for Favorites / Characters / Untracked.

    Column header bar sits above all sections with alignment matching data:
        LEFT-aligned:  CHARACTER, PROFESSION
        CENTER-aligned: SKILL, CONCENTRATION, KNOWLEDGE

    Column grid (per profession line):
        [FavIcon] [ClassIcon] [Name/Realm]  [ProfIcon] [ProfName] [Skill] [===ConcBar===] [Recharge] [Knowledge] [Open]

    Skill column has a hover tooltip showing all expansion skill breakdowns.
    Icon sizes (favIcon, classIcon) match CharactersUI (33px column, visual 65%).
    All data uses "body" font (12px), headers use "small" font (10px).
    Consistent 8px spacing between all data columns.
]]

local ADDON_NAME, ns = ...

-- Unique AceEvent handler identity for ProfessionsUI
local ProfessionsUIEvents = {}
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Shared UI
local COLORS = ns.UI_COLORS  -- initialized by SharedWidgets at parse time, always available
local CreateCard = ns.UI_CreateCard
local ApplyVisuals = ns.UI_ApplyVisuals
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateIcon = ns.UI_CreateIcon
local FormatNumber = ns.UI_FormatNumber
local GetAccentHexColor = ns.UI_GetAccentHexColor
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader

-- Pooling
local AcquireProfessionRow = ns.UI_AcquireProfessionRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance
local format = string.format
local min = math.min
local max = math.max

-- Layout
local function GetLayout() return ns.UI_LAYOUT or {} end
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10

-- Canonical character key (Utilities only; no manual key construction).
local function GetCharKey(char)
    if char and char._key then return char._key end
    if not ns.Utilities or not ns.Utilities.GetCharacterKey then return nil end
    return ns.Utilities:GetCharacterKey(char and char.name or "Unknown", char and char.realm or "Unknown")
end

--============================================================================
-- LAYOUT CONSTANTS
--============================================================================

-- Canonical expansion ordering, newest-first, for sorting the filter dropdown
local EXPANSION_ORDER = {
    "Midnight", "Khaz Algar", "Dragon Isles", "Shadowlands",
    "Battle for Azeroth", "Legion", "Warlords of Draenor",
    "Mists of Pandaria", "Cataclysm", "Wrath of the Lich King",
    "The Burning Crusade", "Classic",
}

-- Extracts the base expansion key from an expansion-qualified name.
-- e.g. "Midnight Tailoring" → "Midnight", "Khaz Algar Alchemy" → "Khaz Algar"
local function ExtractExpansionKey(expName)
    if not expName or expName == "" then return nil end
    for _, known in ipairs(EXPANSION_ORDER) do
        if expName:find(known, 1, true) == 1 then return known end
    end
    return expName:match("^(.+)%s+%u%a+$") or expName
end

-- Builds expansion filter options dynamically from all characters' discovered expansion data.
-- Always "All" first, then discovered expansions sorted newest→oldest.
-- Falls back to "Midnight" when no expansion data has been collected yet.
local function BuildDynamicExpansionOptions()
    local seen = {}
    local keys = {}
    local db = WarbandNexus and WarbandNexus.db
    if db and db.global and db.global.characters then
        for _, charData in pairs(db.global.characters) do
            if charData.professionExpansions then
                for _, expList in pairs(charData.professionExpansions) do
                    if type(expList) == "table" then
                        for _, exp in ipairs(expList) do
                            local key = exp.name and ExtractExpansionKey(exp.name)
                            if key and not seen[key] then
                                seen[key] = true
                                keys[#keys + 1] = key
                            end
                        end
                    end
                end
            end
        end
    end
    table.sort(keys, function(a, b)
        local pa, pb = 99, 99
        for i, name in ipairs(EXPANSION_ORDER) do
            if a == name then pa = i end
            if b == name then pb = i end
        end
        return pa < pb
    end)
    if not seen["Midnight"] then
        keys[#keys + 1] = "Midnight"
    end
    local options = {{key = "All", label = (ns.L and ns.L["PROF_FILTER_ALL"]) or "All"}}
    for _, key in ipairs(keys) do
        options[#options + 1] = {key = key, label = key}
    end
    return options
end

local ROW_HEIGHT = 52
local COL_SPACING = 8                -- Standard spacing between all columns
local ICON_COL_SPACING = 4           -- Tighter spacing after icon columns
local DATA_FONT = "body"             -- 12px - used for ALL data text

-- Vertical positioning (center-relative via LEFT anchor)
local LINE1_Y = 12                   -- Line 1: above row center
local LINE2_Y = -12                  -- Line 2: below row center

--============================================================================
-- COLUMN DEFINITIONS
-- Each column: width, spacing (gap after this column), align for data
-- Order matters for offset calculation.
--============================================================================

local COLUMNS = {
    favIcon     = { width = 33,  spacing = 5 },                  -- favorite star (matches Characters tab)
    classIcon   = { width = 33,  spacing = 5 },                  -- class icon (matches Characters tab)
    name        = { width = 120, spacing = COL_SPACING + 4 },    -- character name + realm
    profIcon    = { width = 20,  spacing = ICON_COL_SPACING },
    profName    = { width = 115, spacing = COL_SPACING },         -- fits Blacksmithing/Leatherworking at 12px
    skill       = { width = 70,  spacing = COL_SPACING },
    conc        = { width = 120, spacing = ICON_COL_SPACING },    -- bar (wider to match rep bar proportions)
    recharge    = { width = 65,  spacing = COL_SPACING },         -- timer text
    knowledge   = { width = 74,  spacing = COL_SPACING },
    recipes     = { width = 68,  spacing = COL_SPACING },         -- known / total (Midnight only)
    firstCraft  = { width = 68,  spacing = COL_SPACING },
    uniques     = { width = 68,  spacing = COL_SPACING },
    treatise    = { width = 68,  spacing = COL_SPACING },
    weeklyQuest = { width = 68,  spacing = COL_SPACING },
    treasure    = { width = 68,  spacing = COL_SPACING },
    gathering   = { width = 68,  spacing = COL_SPACING },
    catchUp     = { width = 68,  spacing = COL_SPACING },
    moxie       = { width = 56,  spacing = COL_SPACING },         -- Artisan Moxie currency (Midnight)
    open        = { width = 36,  spacing = 4 },
    info        = { width = 30,  spacing = 0 },                  -- read-only detail window
}

local COLUMN_ORDER = {
    "favIcon", "classIcon", "name",
    "profIcon", "profName", "skill", "conc", "recharge", "knowledge",
    "recipes", "firstCraft", "uniques", "treatise", "weeklyQuest", "treasure", "gathering", "catchUp", "moxie",
    "open", "info",
}

local LEFT_PAD = 10

-- Calculate the base total grid width from all columns (for horizontal scroll).
-- Computed at load time since COLUMNS and COLUMN_ORDER are static.
do
    local total = LEFT_PAD
    for _, k in ipairs(COLUMN_ORDER) do
        total = total + COLUMNS[k].width + COLUMNS[k].spacing
    end
    ns.MIN_PROFESSIONS_GRID_W = total + LEFT_PAD
end

-- Expansion filter: dynamically built from discovered expansion data across all characters.
-- Falls back to a static list if no character data is available yet.
local EXPANSION_FILTER_STATIC_FALLBACK = {
    { key = "All",          label = (ns.L and ns.L["PROF_FILTER_ALL"]) and ns.L["PROF_FILTER_ALL"] or "All" },
    { key = "Midnight",     label = "Midnight" },
    { key = "Khaz Algar",   label = "Khaz Algar" },
    { key = "Dragon Isles", label = "Dragon Isles" },
}

-- Known expansion ordering: newest first. Expansions not in this list go after these.
local EXPANSION_SORT_ORDER = {
    ["Midnight"]     = 1,
    ["Khaz Algar"]   = 2,
    ["Dragon Isles"] = 3,
}

-- Midnight profession skillLineID -> Artisan Moxie currency ID (DB2 / Wowhead).
local MIDNIGHT_MOXIE_CURRENCY = {
    [2906] = 3256,  -- Alchemy
    [2907] = 3257,  -- Blacksmithing
    [2909] = 3258,  -- Enchanting
    [2910] = 3259,  -- Engineering
    [2912] = 3260,  -- Herbalism
    [2913] = 3261,  -- Inscription
    [2914] = 3262,  -- Jewelcrafting
    [2915] = 3263,  -- Leatherworking
    [2916] = 3264,  -- Mining
    [2917] = 3265,  -- Skinning
    [2918] = 3266,  -- Tailoring
}


-- Text columns scale with effective font size; icon/bar/button columns stay fixed
local SCALABLE_COLUMNS = {
    name = true, profName = true, skill = true, recharge = true, knowledge = true,
    recipes = true, firstCraft = true, uniques = true, treatise = true, weeklyQuest = true,
    treasure = true, gathering = true, catchUp = true, moxie = true,
}

-- Cached row width — set once per DrawProfessionsTab call so columns fill available space.
local cachedRowWidth = nil

-- Scale factor considers two inputs and picks the larger:
--   1) Font-based:  actualFontSize / 12  (keeps text from overflowing when fonts grow)
--   2) Width-based:  available row width / base total  (distributes extra space to text columns)
-- This eliminates truncation at any resolution / UI-scale combination.
local function GetColumnScaleFactor()
    local fontScale = 1.0
    if FontManager and FontManager.GetFontSize then
        local actualSize = FontManager:GetFontSize(DATA_FONT)
        if actualSize and actualSize > 0 then
            fontScale = max(1.0, actualSize / 12)
        end
    end

    if cachedRowWidth and cachedRowWidth > 0 then
        local baseTotal = LEFT_PAD
        local scalableBase = 0
        for _, k in ipairs(COLUMN_ORDER) do
            baseTotal = baseTotal + COLUMNS[k].width + COLUMNS[k].spacing
            if SCALABLE_COLUMNS[k] then
                scalableBase = scalableBase + COLUMNS[k].width
            end
        end
        if scalableBase > 0 then
            local fixedTotal = baseTotal - scalableBase
            if cachedRowWidth > fixedTotal then
                local widthScale = (cachedRowWidth - fixedTotal) / scalableBase
                widthScale = min(2.0, max(1.0, widthScale))
                fontScale = max(fontScale, widthScale)
            end
        end
    end

    return fontScale
end

local function ColWidth(key)
    local base = COLUMNS[key] and COLUMNS[key].width or 60
    if SCALABLE_COLUMNS[key] then
        return base * GetColumnScaleFactor()
    end
    return base
end

local function ColOffset(key)
    local offset = LEFT_PAD
    local scaleFactor = GetColumnScaleFactor()
    for _, k in ipairs(COLUMN_ORDER) do
        if k == key then return offset end
        local w = COLUMNS[k].width
        if SCALABLE_COLUMNS[k] then
            w = w * scaleFactor
        end
        offset = offset + w + COLUMNS[k].spacing
    end
    return offset
end

-- Column header definitions — alignment matches each column's data alignment
-- label = locale key; text = fallback if L[label] is nil; align = header text alignment
local HEADER_DEFS = {
    { col = "name",      label = "TABLE_HEADER_CHARACTER", text = "CHARACTER",     align = "LEFT" },
    { col = "profName",  label = "GROUP_PROFESSION",       text = "Profession",    align = "LEFT" },
    { col = "skill",     label = "SKILL",                  text = "Skill",         align = "CENTER" },
    { col = "conc",      label = "CONCENTRATION",          text = "Concentration", align = "CENTER" },
    { col = "recharge",  label = "RECHARGE",               text = "Recharge",      align = "CENTER" },
    { col = "knowledge", label = "KNOWLEDGE",              text = "Knowledge",     align = "CENTER" },
    { col = "recipes",    label = "RECIPES",               text = "Recipes",       align = "CENTER" },
    { col = "firstCraft",  label = "FIRST_CRAFT",          text = "First Craft",   align = "CENTER" },
    { col = "uniques",     label = "UNIQUES",              text = "Uniques",       align = "CENTER" },
    { col = "treatise",    label = "TREATISE",             text = "Treatise",      align = "CENTER" },
    { col = "weeklyQuest", label = "WEEKLY_QUEST_CAT",     text = "Weekly Quest",  align = "CENTER" },
    { col = "treasure",    label = "SOURCE_TYPE_TREASURE", text = "Treasure",      align = "CENTER" },
    { col = "gathering",   label = "GATHERING",            text = "Gathering",     align = "CENTER" },
    { col = "catchUp",     label = "CATCH_UP",             text = "Catch Up",      align = "CENTER" },
    { col = "moxie",       label = "MOXIE",                text = "Moxie",         align = "CENTER" },
}

--============================================================================
-- CONCENTRATION BAR
--============================================================================

local BAR_HEIGHT = 16
local BAR_BORDER = 1

local function UpdateConcentrationBar(parent, barKey, xOffset, yOffset, barWidth, current, maximum)
    local bar = parent[barKey]

    if not bar then
        bar = ns.UI.Factory:CreateContainer(parent, barWidth, BAR_HEIGHT, false)
        if bar then bar:SetFrameLevel(parent:GetFrameLevel() + 2) end

        -- Background
        bar.bg = bar:CreateTexture(nil, "BACKGROUND")
        bar.bg:SetAllPoints()
        bar.bg:SetColorTexture(0.08, 0.08, 0.1, 0.9)
        bar.bg:SetSnapToPixelGrid(false)
        bar.bg:SetTexelSnappingBias(0)

        -- Fill (inset by border)
        bar.fill = bar:CreateTexture(nil, "ARTWORK")
        bar.fill:SetPoint("TOPLEFT", bar, "TOPLEFT", BAR_BORDER, -BAR_BORDER)
        bar.fill:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", BAR_BORDER, BAR_BORDER)
        bar.fill:SetTexture("Interface\\Buttons\\WHITE8x8")
        bar.fill:SetSnapToPixelGrid(false)
        bar.fill:SetTexelSnappingBias(0)

        -- Border (OVERLAY so it always covers fill edges)
        local cr, cg, cb, ca = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5

        local function Border(p1, p2, w, h)
            local t = bar:CreateTexture(nil, "OVERLAY")
            t:SetTexture("Interface\\Buttons\\WHITE8x8")
            t:SetPoint(p1, bar, p1, 0, 0)
            t:SetPoint(p2, bar, p2, 0, 0)
            if w then t:SetWidth(w) end
            if h then t:SetHeight(h) end
            t:SetVertexColor(cr, cg, cb, ca)
            t:SetSnapToPixelGrid(false)
            t:SetTexelSnappingBias(0)
            return t
        end

        bar.bTop   = Border("TOPLEFT", "TOPRIGHT", nil, BAR_BORDER)
        bar.bBot   = Border("BOTTOMLEFT", "BOTTOMRIGHT", nil, BAR_BORDER)
        bar.bLeft  = Border("TOPLEFT", "BOTTOMLEFT", BAR_BORDER, nil)
        bar.bRight = Border("TOPRIGHT", "BOTTOMRIGHT", BAR_BORDER, nil)

        -- Value text
        bar.valueText = FontManager:CreateFontString(bar, "small", "OVERLAY")
        bar.valueText:SetPoint("CENTER", 0, 0)
        bar.valueText:SetJustifyH("CENTER")

        parent[barKey] = bar
    end
    if not bar then return nil end

    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", xOffset, yOffset)
    bar:SetSize(barWidth, BAR_HEIGHT)

    if not maximum or maximum <= 0 then
        bar.fill:SetWidth(0.001)
        bar.fill:Hide()
        bar.valueText:SetText("|cffffffff--|r")
        bar:Show()
        return bar
    end

    local contentWidth = barWidth - (BAR_BORDER * 2)
    local progress = min(1, max(0, current / maximum))
    local fillW = contentWidth * progress
    if fillW < 0.001 then fillW = 0.001 end
    bar.fill:SetWidth(fillW)
    bar.fill:Show()

    if current >= maximum then
        bar.fill:SetVertexColor(0.2, 0.8, 0.2, 1)
    elseif progress >= 0.5 then
        bar.fill:SetVertexColor(1, 0.82, 0, 1)
    else
        bar.fill:SetVertexColor(0.9, 0.45, 0.2, 1)
    end

    bar.valueText:SetText(format("|cffffffff%d / %d|r", current, maximum))
    bar:Show()
    return bar
end

--============================================================================
-- EVENT REGISTRATION
--============================================================================

local function RegisterProfessionEvents(parent)
    if parent.professionUpdateHandler then return end
    parent.professionUpdateHandler = true
    local Constants = ns.Constants

    local function Refresh()
        if WarbandNexus.UI and WarbandNexus.UI.mainFrame and WarbandNexus.UI.mainFrame.currentTab == "professions" then
            WarbandNexus:RefreshUI()
        end
    end

    -- CONCENTRATION_UPDATED, KNOWLEDGE_UPDATED, RECIPE_DATA_UPDATED: REMOVED —
    -- UI.lua's SchedulePopulateContent already handles professions tab refresh for these events.
    -- Having both caused double PopulateContent → DrawProfessionsTab per event.
    
    -- Keep CHARACTER_UPDATED + CHARACTER_TRACKING_CHANGED: UI.lua does NOT handle
    -- professions tab for these events (it only handles chars tab for CHARACTER_UPDATED).
    WarbandNexus.RegisterMessage(ProfessionsUIEvents, Constants.EVENTS.CHARACTER_UPDATED, Refresh)
    WarbandNexus.RegisterMessage(ProfessionsUIEvents, "WN_CHARACTER_TRACKING_CHANGED", Refresh)
end

--============================================================================
-- CHARACTER SORTING (mirrors CharactersUI)
--============================================================================

local function SortCharacters(list, orderKey)
    if not WarbandNexus.db or not WarbandNexus.db.profile then
        table.sort(list, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
        return list
    end
    
    local sortMode = WarbandNexus.db.profile.professionSort and WarbandNexus.db.profile.professionSort.key
    if sortMode and sortMode ~= "manual" then
        table.sort(list, function(a, b)
            if sortMode == "name" then
                return (a.name or ""):lower() < (b.name or ""):lower()
            elseif sortMode == "level" then
                if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                return (a.name or ""):lower() < (b.name or ""):lower()
            elseif sortMode == "ilvl" then
                if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return (a.itemLevel or 0) > (b.itemLevel or 0) end
                return (a.name or ""):lower() < (b.name or ""):lower()
            elseif sortMode == "gold" then
                local goldA = ns.Utilities:GetCharTotalCopper(a)
                local goldB = ns.Utilities:GetCharTotalCopper(b)
                if goldA ~= goldB then return goldA > goldB end
                return (a.name or ""):lower() < (b.name or ""):lower()
            end
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
        return list
    end

    if not WarbandNexus.db.profile.characterOrder then
        WarbandNexus.db.profile.characterOrder = { favorites = {}, regular = {}, untracked = {} }
    end
    local customOrder = WarbandNexus.db.profile.characterOrder[orderKey] or {}
    if #customOrder > 0 then
        local ordered, charMap = {}, {}
        for _, c in ipairs(list) do charMap[GetCharKey(c)] = c end
        for _, ck in ipairs(customOrder) do
            if charMap[ck] then table.insert(ordered, charMap[ck]); charMap[ck] = nil end
        end
        local remaining = {}
        for _, c in pairs(charMap) do table.insert(remaining, c) end
        table.sort(remaining, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
        for _, c in ipairs(remaining) do table.insert(ordered, c) end
        return ordered
    else
        table.sort(list, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
        return list
    end
end

local function CategorizeCharacters(characters)
    local favorites, regular, untracked = {}, {}, {}
    for _, char in ipairs(characters) do
        -- Include ALL tracked characters, even those with no professions.
        -- DrawProfessionLine already handles empty slots with "No Profession" text.
        local isTracked = char.isTracked ~= false
        local charKey = GetCharKey(char)
        if not isTracked then table.insert(untracked, char)
        elseif ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey) then table.insert(favorites, char)
        else table.insert(regular, char) end
    end
    return SortCharacters(favorites, "favorites"), SortCharacters(regular, "regular"), SortCharacters(untracked, "untracked")
end

-- Realm display: use centralized Utilities:FormatRealmName
local function FormatRealmName(realm)
    if ns.Utilities and ns.Utilities.FormatRealmName then
        return ns.Utilities:FormatRealmName(realm)
    end
    if not realm or realm == "" then return "" end
    return realm:gsub("(%l)(%u)", "%1 %2")
end

--============================================================================
-- EXPANSION FILTER HELPERS (strict: only selected expansion's data)
--============================================================================

local function GetExpansionFilter()
    return "Midnight"
end

local function ExpansionNameMatchesFilter(expansionName, filterKey)
    if not expansionName or expansionName == "" then return false end
    if filterKey == "All" then return true end
    -- Match by prefix (e.g. "Midnight Tailoring" vs "Midnight") or by extracted key
    if expansionName == filterKey or expansionName:sub(1, #filterKey) == filterKey then return true end
    local key = ExtractExpansionKey(expansionName)
    return key and key == filterKey
end

-- Fallback resolver for cases where strict expansion-name matching fails
-- (e.g. localized expansion names or stale naming formats).
-- Preference order:
-- 1) Skill line with concrete profession payload (weekly/recipes/knowledge/concentration)
-- 2) Highest max skill line
-- 3) First available skill line
local function GetBestAvailableSkillLineID(char, expansions)
    if not expansions or #expansions == 0 then return nil end

    local bestBySkill = nil
    local bestMaxSkill = -1
    local firstSkillLine = nil

    for i = 1, #expansions do
        local exp = expansions[i]
        local slID = exp and exp.skillLineID
        if slID and slID > 0 then
            if not firstSkillLine then firstSkillLine = slID end
            local hasPayload =
                (char.professionData and char.professionData.bySkillLine and char.professionData.bySkillLine[slID])
                or (char.recipes and char.recipes[slID])
                or (char.knowledgeData and char.knowledgeData[slID])
                or (char.concentration and char.concentration[slID])
                or (char.professionWeeklyKnowledge and char.professionWeeklyKnowledge[slID])
            if hasPayload then
                return slID
            end
            local maxSkill = exp.maxSkillLevel or 0
            if maxSkill > bestMaxSkill then
                bestMaxSkill = maxSkill
                bestBySkill = slID
            end
        end
    end

    return bestBySkill or firstSkillLine
end

---Returns the skillLineID for char+profName that matches the current expansion filter.
---Used to look up concentration and knowledge (all stored by skillLineID).
---
---Uses professionExpansions as the PRIMARY source because its names are always
---expansion-qualified (from GetChildProfessionInfos / GetProfessionInfoBySkillLineID),
---ensuring correct expansion matching.
---@param char table
---@param profName string
---@return number|nil skillLineID or nil
local function GetSkillLineIDForFilter(char, profName)
    local filter = GetExpansionFilter()
    local expansions = char.professionExpansions and char.professionExpansions[profName]

    -- Primary: professionExpansions has guaranteed expansion-qualified names
    if expansions and #expansions > 0 then
        if filter == "All" then
            return expansions[1].skillLineID
        else
            for _, exp in ipairs(expansions) do
                if exp.name and exp.skillLineID and ExpansionNameMatchesFilter(exp.name, filter) then
                    return exp.skillLineID
                end
            end
            return GetBestAvailableSkillLineID(char, expansions)
        end
    end

    return nil
end

--============================================================================
-- FORMAT HELPERS (all return white text, colored where meaningful)
--============================================================================

---Returns skill level for the expansion that matches the current expansion filter.
---When filter is "All", returns first expansion with skill; otherwise the matching expansion.
local function GetCurrentExpansionSkill(char, profName)
    local expansions = char.professionExpansions and char.professionExpansions[profName]
    if not expansions or #expansions == 0 then return nil, nil, nil end
    local filter = GetExpansionFilter()
    if filter ~= "All" then
        for i = 1, #expansions do
            local exp = expansions[i]
            if exp and exp.name and ExpansionNameMatchesFilter(exp.name, filter) then
                return exp.skillLevel or 0, exp.maxSkillLevel or 0, exp.name
            end
        end
        -- If strict filter match is unavailable, keep overview populated with
        -- the most meaningful known skill line for this profession.
        local fallbackSkillLine = GetBestAvailableSkillLineID(char, expansions)
        if fallbackSkillLine then
            for i = 1, #expansions do
                local exp = expansions[i]
                if exp and exp.skillLineID == fallbackSkillLine then
                    return exp.skillLevel or 0, exp.maxSkillLevel or 0, exp.name
                end
            end
        end
        return nil, nil, nil
    end
    for _, exp in ipairs(expansions) do
        if exp.skillLevel and exp.skillLevel > 0 then
            return exp.skillLevel, exp.maxSkillLevel or 0, exp.name
        end
    end
    local first = expansions[1]
    return first.skillLevel or 0, first.maxSkillLevel or 0, first.name
end

local function FormatValueMax(current, maximum, color)
    if not current or not maximum or maximum <= 0 then return "|cffffffff--|r" end
    return format("|cff%02x%02x%02x%d|r |cffffffff/|r |cff%02x%02x%02x%d|r",
        color[1]*255, color[2]*255, color[3]*255, current,
        color[1]*255, color[2]*255, color[3]*255, maximum)
end

local function FormatSkill(curSkill, maxSkill)
    if not curSkill or not maxSkill or maxSkill <= 0 then return "|cffffffff--|r" end
    local color
    if curSkill >= maxSkill then color = {0.3, 0.9, 0.3}
    elseif curSkill > 0 then color = {1, 0.82, 0}
    else color = {1, 1, 1} end
    return FormatValueMax(curSkill, maxSkill, color)
end

---Format knowledge as "Current / Max". Current = spent + unspent; Max = maxPoints from spec tree.
local function FormatKnowledge(kd)
    if not kd then return "|cffffffff--|r" end
    local spent = kd.spentPoints or 0
    local maxPts = kd.maxPoints or 0
    local unspent = kd.unspentPoints or 0
    local current = spent + unspent
    if current <= 0 and (not maxPts or maxPts <= 0) then return "|cffffffff--|r" end
    local displayMax = (maxPts and maxPts > 0) and maxPts or nil
    local color
    if unspent > 0 then color = {1, 0.82, 0}
    elseif displayMax and current >= displayMax then color = {0.3, 0.9, 0.3}
    else color = {1, 1, 1} end
    if displayMax then
        return FormatValueMax(current, displayMax, color)
    end
    return format("|cff%02x%02x%02x%d|r |cffffffff/|r |cff888888--|r", color[1]*255, color[2]*255, color[3]*255, current)
end

local function FormatProgressPair(entry)
    if not entry then return "|cffffffff--|r" end
    local current = tonumber(entry.current or 0) or 0
    local total = tonumber(entry.total or 0) or 0
    if total <= 0 then return "|cffffffff--|r" end
    if current > total then current = total end
    local color = (current >= total) and "ff4de64d" or "ffffffff"
    return format("|c%s%d / %d|r", color, current, total)
end

--============================================================================
-- DRAW TAB
--============================================================================

function WarbandNexus:DrawProfessionsTab(parent)
    local yOffset = 8
    local width = parent:GetWidth() - 20
    cachedRowWidth = width

    RegisterProfessionEvents(parent)
    HideEmptyStateCard(parent, "professions")
    if ReleaseAllPooledChildren then ReleaseAllPooledChildren(parent) end

    -- If module is disabled, show disabled state card
    if not ns.Utilities:IsModuleEnabled("professions") then
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, (ns.L and ns.L["PROFESSIONS_DISABLED_TITLE"]) or "Professions")
        return yOffset + cardHeight
    end

    local characters = self:GetAllCharacters()
    local trackedFavorites, trackedRegular, untrackedChars = CategorizeCharacters(characters)
    local totalProfChars = #trackedFavorites + #trackedRegular + #untrackedChars

    -- ===== TITLE CARD =====
    local titleCard = CreateCard(parent, 70)
    titleCard:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    titleCard:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    if ApplyVisuals then
        ApplyVisuals(titleCard, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end

    local CreateHeaderIcon = ns.UI_CreateHeaderIcon
    local GetTabIcon = ns.UI_GetTabIcon
    local headerIcon = CreateHeaderIcon(titleCard, GetTabIcon("professions") or "Vehicle-HammerGold")
    headerIcon.border:SetPoint("CENTER", titleCard, "LEFT", 35, 0)

    local titleTextContainer = ns.UI.Factory:CreateContainer(titleCard, 250, 40)
    local titleText = FontManager:CreateFontString(titleTextContainer, "header", "OVERLAY")
    titleText:SetText("|cff" .. GetAccentHexColor() .. ((ns.L and ns.L["YOUR_PROFESSIONS"]) or "Warband Professions") .. "|r")
    titleText:SetJustifyH("LEFT")

    local subtitleText = FontManager:CreateFontString(titleTextContainer, "subtitle", "OVERLAY")
    subtitleText:SetTextColor(1, 1, 1)
    subtitleText:SetText(format((ns.L and ns.L["PROFESSIONS_TRACKED_FORMAT"]) or "%s characters with professions", FormatNumber(totalProfChars)))
    subtitleText:SetJustifyH("LEFT")

    titleText:SetPoint("BOTTOM", titleTextContainer, "CENTER", 0, 0)
    titleText:SetPoint("LEFT", titleTextContainer, "LEFT", 0, 0)
    subtitleText:SetPoint("TOP", titleTextContainer, "CENTER", 0, -4)
    subtitleText:SetPoint("LEFT", titleTextContainer, "LEFT", 0, 0)
    titleTextContainer:SetPoint("LEFT", headerIcon.border, "RIGHT", 12, 0)
    titleTextContainer:SetPoint("CENTER", titleCard, "CENTER", 0, 0)

    -- Force fixed expansion view: Midnight only (filter selector removed).
    self.db.profile.professionExpansionFilter = "Midnight"
    local expBadgeWidth = 100
    local expBadgeHeight = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local expBadge = ns.UI.Factory:CreateButton(titleCard, expBadgeWidth, expBadgeHeight, false)
    if ApplyVisuals then
        ApplyVisuals(expBadge, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    local expBadgeText = FontManager:CreateFontString(expBadge, "body", "OVERLAY")
    expBadgeText:SetPoint("CENTER", 0, 0)
    expBadgeText:SetJustifyH("CENTER")
    expBadgeText:SetText("Midnight")
    expBadgeText:SetTextColor(0.9, 0.9, 0.9)
    expBadge:SetScript("OnClick", nil)
    expBadge:SetScript("OnEnter", nil)
    expBadge:SetScript("OnLeave", nil)
    expBadge:SetPoint("RIGHT", titleCard, "RIGHT", -20, 0)
    
    if ns.UI_CreateCharacterSortDropdown then
        local sortOptions = {
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
        }
        if not self.db.profile.professionSort then self.db.profile.professionSort = {} end
        local sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.professionSort, function() self:RefreshUI() end)
        sortBtn:SetPoint("RIGHT", expBadge, "LEFT", -8, 0)
    end
    
    titleCard:Show()
    yOffset = yOffset + 75

    -- ===== COLUMN HEADER BAR (always show so user sees column layout even with no data) =====
    local COLUMN_HEADER_HEIGHT = 22
    local colHeaderBar = CreateFrame("Frame", nil, parent)
    colHeaderBar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    colHeaderBar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    colHeaderBar:SetHeight(COLUMN_HEADER_HEIGHT)

    local colHeaderBg = colHeaderBar:CreateTexture(nil, "BACKGROUND")
    colHeaderBg:SetAllPoints()
    colHeaderBg:SetColorTexture(1, 1, 1, 0.03)

    local colHeaderLine = colHeaderBar:CreateTexture(nil, "ARTWORK")
    colHeaderLine:SetPoint("BOTTOMLEFT", 0, 0)
    colHeaderLine:SetPoint("BOTTOMRIGHT", 0, 0)
    colHeaderLine:SetHeight(1)
    colHeaderLine:SetColorTexture(1, 1, 1, 0.08)

    -- Use hdef.text (English) so column headers are always correct regardless of game locale.
    for _, hdef in ipairs(HEADER_DEFS) do
        local col = hdef.col
        local lbl = FontManager:CreateFontString(colHeaderBar, "small", "OVERLAY")
        lbl:SetText("|cffffffff" .. (hdef.text or (ns.L and ns.L[hdef.label]) or "") .. "|r")
        lbl:SetJustifyH(hdef.align or "CENTER")
        local w = (hdef.getWidth and hdef.getWidth()) or ColWidth(col)
        lbl:SetWidth(w)
        lbl:SetPoint("LEFT", colHeaderBar, "LEFT", ColOffset(col), 0)
    end
    colHeaderBar:Show()

    yOffset = yOffset + COLUMN_HEADER_HEIGHT + 4

    -- ===== EMPTY STATE =====
    if totalProfChars == 0 then
        local emptyText = FontManager:CreateFontString(parent, DATA_FONT, "OVERLAY")
        emptyText:SetPoint("TOPLEFT", SIDE_MARGIN + 20, -yOffset - 30)
        emptyText:SetWidth(width - 40)
        emptyText:SetJustifyH("CENTER")
        emptyText:SetText("|cffffffff" .. ((ns.L and ns.L["NO_PROFESSIONS_DATA"]) or "No profession data available yet. Open your profession window (default: K) on each character to collect data.") .. "|r")
        return yOffset + 100
    end

    -- ===== SECTION HEADERS & CHARACTER ROWS =====
    local currentPlayerKey = ns.Utilities:GetCharacterKey()
    local rowIndex = 0
    local HEADER_HEIGHT = GetLayout().HEADER_HEIGHT or 32

    -- Initialize expand state tracking
    if not self.db.profile.ui then self.db.profile.ui = {} end
    self.profRecentlyExpanded = self.profRecentlyExpanded or {}

    -- Helper: draw a section with collapsible header
    local function DrawSection(chars, headerLabel, sectionKey, defaultExpanded, headerAtlas, borderColor)
        if #chars == 0 then return end

        local isExpanded = self.db.profile.ui[sectionKey]
        if isExpanded == nil then isExpanded = defaultExpanded end

        local header, _, hdrIcon = CreateCollapsibleHeader(
            parent,
            string.format(headerLabel .. " |cff888888(%s)|r", FormatNumber(#chars)),
            sectionKey,
            isExpanded,
            function(expanded)
                self.db.profile.ui[sectionKey] = expanded
                if expanded then self.profRecentlyExpanded[sectionKey] = GetTime() end
                self:RefreshUI()
            end,
            headerAtlas,
            true  -- isAtlas
        )
        if hdrIcon then
            hdrIcon:SetSize(34, 34)
        end
        header:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
        header:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
        if ApplyVisuals then
            ApplyVisuals(header, {0.08, 0.08, 0.10, 0.95}, borderColor)
        end
        yOffset = yOffset + HEADER_HEIGHT

        if isExpanded then
            for _, char in ipairs(chars) do
                rowIndex = rowIndex + 1
                yOffset = self:DrawProfessionRow(parent, char, rowIndex, width, yOffset, currentPlayerKey)
            end
        end

        yOffset = yOffset + 4  -- breathing room between sections
    end

    -- Favorites section (always visible if has entries)
    DrawSection(
        trackedFavorites,
        (ns.L and ns.L["HEADER_FAVORITES"]) or "Favorites",
        "profFavoritesExpanded",
        true,
        "GM-icon-assistActive-hover",
        {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    )

    -- Regular characters section
    DrawSection(
        trackedRegular,
        (ns.L and ns.L["HEADER_CHARACTERS"]) or "Characters",
        "profCharactersExpanded",
        true,
        "GM-icon-headCount",
        {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    )

    -- Untracked characters section
    DrawSection(
        untrackedChars,
        (ns.L and ns.L["UNTRACKED_CHARACTERS"]) or "Untracked Characters",
        "profUntrackedExpanded",
        false,
        "DungeonStoneCheckpointDeactivated",
        {0.8, 0.2, 0.2, 0.6}  -- Red border for untracked
    )

    return yOffset + 10
end

--============================================================================
-- DRAW CHARACTER ROW
--============================================================================

function WarbandNexus:DrawProfessionRow(parent, char, index, width, yOffset, currentPlayerKey)
    local row = AcquireProfessionRow(parent)
    row:ClearAllPoints()
    row:SetSize(width, ROW_HEIGHT)
    row:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    row:EnableMouse(true)
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end

    ns.UI.Factory:ApplyRowBackground(row, index)

    local charKey = GetCharKey(char)
    local isCurrent = (charKey == currentPlayerKey)
    local isFavorite = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey)
    local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}

    -- FAVORITE ICON (own column, left of class icon)
    -- Visual star size = column width * 0.65, matching CreateFavoriteButton in Characters tab
    local favX = ColOffset("favIcon")
    local favColW = ColWidth("favIcon")
    local favIconSize = favColW * 0.65
    if not row.favIcon then
        row.favIcon = row:CreateTexture(nil, "OVERLAY")
        row.favIcon:SetAtlas("transmog-icon-favorite")
        row.favIcon:SetDesaturated(false)
        row.favIcon:SetVertexColor(1, 0.84, 0)
    end
    row.favIcon:SetSize(favIconSize, favIconSize)
    row.favIcon:ClearAllPoints()
    row.favIcon:SetPoint("LEFT", favX + (favColW - favIconSize) / 2, 0)
    if isFavorite then
        row.favIcon:Show()
    else
        row.favIcon:Hide()
    end

    -- CLASS ICON (vertically centered in row, same size as Characters tab)
    local classX = ColOffset("classIcon")
    local classSize = ColWidth("classIcon")
    if not row.classIcon then
        local CreateClassIcon = ns.UI_CreateClassIcon
        if CreateClassIcon and char.classFile then
            row.classIcon = CreateClassIcon(row, char.classFile, classSize, "LEFT", classX, 0)
        end
    end
    if row.classIcon then
        row.classIcon:SetSize(classSize, classSize)
        if char.classFile then row.classIcon:SetAtlas("classicon-" .. char.classFile); row.classIcon:Show()
        else row.classIcon:Hide() end
    end

    -- NAME COLUMN (name above center, realm below)
    local nameX = ColOffset("name")
    local nameW = ColWidth("name")

    if not row.nameText then
        row.nameText = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetMaxLines(1)
    end
    row.nameText:ClearAllPoints()
    row.nameText:SetPoint("LEFT", nameX, 6)
    row.nameText:SetWidth(nameW)
    row.nameText:SetText(format("|cff%02x%02x%02x%s|r", classColor.r*255, classColor.g*255, classColor.b*255, char.name or "Unknown"))

    if not row.realmText then
        row.realmText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.realmText:SetJustifyH("LEFT")
        row.realmText:SetWordWrap(false)
        row.realmText:SetMaxLines(1)
    end
    row.realmText:ClearAllPoints()
    row.realmText:SetPoint("LEFT", nameX, -7)
    row.realmText:SetWidth(nameW)
    row.realmText:SetTextColor(1, 1, 1)
    row.realmText:SetText(FormatRealmName(char.realm or ""))

    -- PROFESSION LINES
    self:DrawProfessionLine(row, char, char.professions and char.professions[1], 1, LINE1_Y, isCurrent)
    self:DrawProfessionLine(row, char, char.professions and char.professions[2], 2, LINE2_Y, isCurrent)

    -- Row hover
    row:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
    row:SetScript("OnLeave", function(self) self:SetAlpha(1) end)

    return yOffset + ROW_HEIGHT + (GetLayout().betweenRows or 0)
end

--============================================================================
-- COLUMN TOOLTIP HIT-FRAME HELPER
-- Creates an invisible button over a column area for mouse-over tooltips.
-- Reuses frames across redraws via row[key].
--============================================================================

local function AcquireColumnHitFrame(row, key, colKey, centerY)
    local frame = row[key]
    if not frame then
        frame = CreateFrame("Button", nil, row)
        frame:SetFrameLevel(row:GetFrameLevel() + 3)
        frame:EnableMouse(true)
        row[key] = frame
    end
    frame:SetSize(ColWidth(colKey), ROW_HEIGHT / 2)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", ColOffset(colKey), centerY)
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
    frame:Show()
    return frame
end

--============================================================================
-- DRAW PROFESSION LINE (single profession within a row)
--============================================================================

function WarbandNexus:DrawProfessionLine(row, char, prof, lineIndex, centerY, isCurrent)
    local p = "l" .. lineIndex

    local iconSize = ColWidth("profIcon")

    -- ICON
    local iconX = ColOffset("profIcon")
    if not row[p.."Icon"] then
        row[p.."Icon"] = CreateIcon(row, nil, iconSize)
        row[p.."Icon"]:EnableMouse(true)
        row[p.."Icon"].icon = row[p.."Icon"].texture
    end
    row[p.."Icon"]:ClearAllPoints()
    row[p.."Icon"]:SetPoint("LEFT", iconX, centerY)

    -- NAME
    local nameX = ColOffset("profName")
    if not row[p.."Name"] then
        row[p.."Name"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Name"]:SetJustifyH("LEFT")
        row[p.."Name"]:SetWordWrap(false)
        row[p.."Name"]:SetMaxLines(1)
    end
    row[p.."Name"]:SetWidth(ColWidth("profName"))
    row[p.."Name"]:ClearAllPoints()
    row[p.."Name"]:SetPoint("LEFT", nameX, centerY)

    -- SKILL
    local skillX = ColOffset("skill")
    if not row[p.."Skill"] then
        row[p.."Skill"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Skill"]:SetJustifyH("CENTER")
        row[p.."Skill"]:SetMaxLines(1)
    end
    row[p.."Skill"]:SetWidth(ColWidth("skill"))
    row[p.."Skill"]:ClearAllPoints()
    row[p.."Skill"]:SetPoint("LEFT", skillX, centerY)

    -- RECHARGE (timer text, right of bar)
    local rechargeX = ColOffset("recharge")
    if not row[p.."Recharge"] then
        row[p.."Recharge"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Recharge"]:SetJustifyH("CENTER")
        row[p.."Recharge"]:SetMaxLines(1)
    end
    row[p.."Recharge"]:SetWidth(ColWidth("recharge"))
    row[p.."Recharge"]:ClearAllPoints()
    row[p.."Recharge"]:SetPoint("LEFT", rechargeX, centerY)

    -- KNOWLEDGE (text + optional unspent warning triangle)
    local knowX = ColOffset("knowledge")
    local knowW = ColWidth("knowledge")
    if not row[p.."Know"] then
        row[p.."Know"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Know"]:SetJustifyH("CENTER")
        row[p.."Know"]:SetMaxLines(1)
    end
    row[p.."Know"]:SetWidth(knowW - 16)
    row[p.."Know"]:ClearAllPoints()
    row[p.."Know"]:SetPoint("LEFT", knowX, centerY)
    if not row[p.."KnowWarn"] then
        local warnFrame = CreateFrame("Frame", nil, row)
        warnFrame:SetSize(16, 16)
        warnFrame:EnableMouse(true)
        local tex = warnFrame:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetAtlas("icons_64x64_important")
        warnFrame.texture = tex
        row[p.."KnowWarn"] = warnFrame
    end
    row[p.."KnowWarn"]:ClearAllPoints()
    row[p.."KnowWarn"]:SetPoint("RIGHT", row, "LEFT", knowX + knowW - 2, centerY)

    local function EnsureProgressCell(fieldKey, colKey)
        local key = p .. fieldKey
        if not row[key] then
            row[key] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
            row[key]:SetJustifyH("CENTER")
            row[key]:SetMaxLines(1)
        end
        row[key]:SetWidth(ColWidth(colKey))
        row[key]:ClearAllPoints()
        row[key]:SetPoint("LEFT", ColOffset(colKey), centerY)
        return row[key]
    end

    local recipesText = EnsureProgressCell("Recipes", "recipes")
    local firstCraftText = EnsureProgressCell("FirstCraft", "firstCraft")
    local uniquesText = EnsureProgressCell("Uniques", "uniques")
    local treatiseText = EnsureProgressCell("Treatise", "treatise")
    local weeklyQuestText = EnsureProgressCell("WeeklyQuest", "weeklyQuest")
    local treasureText = EnsureProgressCell("Treasure", "treasure")
    local gatheringText = EnsureProgressCell("Gathering", "gathering")
    local catchUpText = EnsureProgressCell("CatchUp", "catchUp")
    local moxieText = EnsureProgressCell("Moxie", "moxie")

    -- COLUMN HIT-FRAMES (interactive tooltips for skill)
    local skillHit = AcquireColumnHitFrame(row, p.."SkillHit", "skill", centerY)

    -- OPEN BUTTON
    local openX = ColOffset("open")
    if not row[p.."Btn"] then
        local btn = CreateFrame("Button", nil, row)
        btn:SetSize(ColWidth("open"), 18)
        if ApplyVisuals then
            ApplyVisuals(btn, {0.15, 0.15, 0.18, 0.8}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5})
        end
        btn.label = FontManager:CreateFontString(btn, "small", "OVERLAY")
        btn.label:SetPoint("CENTER", 0, 0)
        btn.label:SetText((ns.L and ns.L["PROF_OPEN_RECIPE"]) or "Open")
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(btn) end
        row[p.."Btn"] = btn
    end
    row[p.."Btn"]:ClearAllPoints()
    row[p.."Btn"]:SetPoint("LEFT", openX, centerY)

    -- INFO BUTTON (read-only detail window)
    local infoX = ColOffset("info")
    if not row[p.."InfoBtn"] then
        local ibtn = CreateFrame("Button", nil, row)
        ibtn:SetSize(ColWidth("info"), 18)
        if ApplyVisuals then
            ApplyVisuals(ibtn, {0.12, 0.12, 0.15, 0.8}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4})
        end
        local iicon = ibtn:CreateTexture(nil, "ARTWORK")
        iicon:SetSize(14, 14)
        iicon:SetPoint("CENTER", 0, 0)
        iicon:SetAtlas("QuestTurnin")
        ibtn.iconTex = iicon
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(ibtn) end
        row[p.."InfoBtn"] = ibtn
    end
    row[p.."InfoBtn"]:ClearAllPoints()
    row[p.."InfoBtn"]:SetPoint("LEFT", infoX, centerY)

    -- ===== POPULATE =====
    if prof and prof.name then
        local profName = prof.name

        -- Icon
        if row[p.."Icon"].icon then
            row[p.."Icon"].icon:SetTexture(prof.icon)
            row[p.."Icon"].icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        row[p.."Icon"]:Show()

        -- Name
        row[p.."Name"]:SetText("|cffffffff" .. profName .. "|r")

        -- Skill: use expansion-specific data from professionExpansions.
        -- Only fall back to the base prof.skill in "All" mode (it reflects the latest expansion
        -- and is acceptable as a last-resort when no per-expansion data has been collected yet).
        local curSkill, maxSkill = GetCurrentExpansionSkill(char, profName)
        if curSkill and maxSkill then
            row[p.."Skill"]:SetText(FormatSkill(curSkill, maxSkill))
        elseif GetExpansionFilter() == "All" and prof.skill and prof.maxSkill then
            row[p.."Skill"]:SetText(FormatSkill(prof.skill, prof.maxSkill))
        else
            row[p.."Skill"]:SetText("|cffffffff--|r")
        end

        -- Concentration: keyed by skillLineID (expansion-specific).
        -- String-key legacy fallback only in "All" mode to prevent cross-expansion data bleed.
        local slID = GetSkillLineIDForFilter(char, profName)
        local concData = slID and char.concentration and char.concentration[slID]
        if not concData and GetExpansionFilter() == "All" then
            concData = char.concentration and char.concentration[profName]
        end
        local concCurrent, concMax = 0, 0
        local rechargeStr = ""
        if concData and concData.max and concData.max > 0 then
            concCurrent = concData.current or 0
            if WarbandNexus.GetEstimatedConcentration then
                concCurrent = WarbandNexus:GetEstimatedConcentration(concData)
            end
            concMax = concData.max
            if concCurrent >= concMax then
                rechargeStr = "|cff4de64d" .. ((ns.L and ns.L["FULL"]) or "Full") .. "|r"
            elseif WarbandNexus.GetConcentrationTimeToFull then
                local ts = WarbandNexus:GetConcentrationTimeToFull(concData)
                if ts and ts ~= "" and ts ~= "Full" then
                    rechargeStr = "|cffffffff" .. ts .. "|r"
                end
            end
        end
        local concX = ColOffset("conc")
        local barTopY = centerY + BAR_HEIGHT / 2 - ROW_HEIGHT / 2
        UpdateConcentrationBar(row, p.."ConcBar", concX, barTopY, ColWidth("conc"), concCurrent, concMax)
        row[p.."Recharge"]:SetText(rechargeStr)

        -- Knowledge: keyed by skillLineID (expansion-specific). Always show Current / Max.
        -- String-key legacy fallback only in "All" mode to prevent cross-expansion data bleed.
        local kd = slID and char.knowledgeData and char.knowledgeData[slID]
        if not kd and GetExpansionFilter() == "All" then
            kd = char.knowledgeData and char.knowledgeData[profName]
        end
        row[p.."Know"]:SetText(FormatKnowledge(kd))
        local unspent = (kd and kd.unspentPoints) and kd.unspentPoints or 0
        if unspent > 0 then
            row[p.."KnowWarn"]:Show()
            row[p.."KnowWarn"]:SetScript("OnEnter", function(self)
                local msg
                if ns.L and ns.L["UNSPENT_KNOWLEDGE_COUNT"] then
                    msg = format(ns.L["UNSPENT_KNOWLEDGE_COUNT"], unspent)
                else
                    msg = ((ns.L and ns.L["UNSPENT_KNOWLEDGE_TOOLTIP"]) or "Unspent knowledge points") .. ": " .. tostring(unspent)
                end
                if ShowTooltip then ShowTooltip(self, { type = "custom", title = msg, lines = {}, anchor = "ANCHOR_TOP" }) end
            end)
            row[p.."KnowWarn"]:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        else
            row[p.."KnowWarn"]:Hide()
            row[p.."KnowWarn"]:SetScript("OnEnter", nil)
            row[p.."KnowWarn"]:SetScript("OnLeave", nil)
        end

        -- Recipes summary: keyed by skillLineID; in All mode fallback to matching profession name.
        local recipeData = slID and char.recipes and char.recipes[slID]
        if not recipeData and GetExpansionFilter() == "All" and char.recipes then
            for _, entry in pairs(char.recipes) do
                if type(entry) == "table" and entry.professionName == profName then
                    recipeData = entry
                    break
                end
            end
        end
        local progressData = nil
        if slID and char.professionData and char.professionData.bySkillLine and char.professionData.bySkillLine[slID] then
            progressData = char.professionData.bySkillLine[slID].weeklyKnowledge
        end
        if not progressData and slID and char.professionWeeklyKnowledge then
            progressData = char.professionWeeklyKnowledge[slID]
        end

        -- First Craft: only show when data is from Midnight (avoid TWW/DF recipe counts mixing in).
        local isMidnightRecipeData = recipeData and recipeData.expansionName and recipeData.expansionName:find("Midnight", 1, true)
        local firstCraftProgress = progressData and progressData.firstCraft
        if isMidnightRecipeData then
            local doneCount = recipeData.firstCraftDoneCount
            local totalBonusCount = recipeData.firstCraftTotalCount
            local recipeProgress = nil
            if totalBonusCount and totalBonusCount > 0 then
                recipeProgress = {
                    current = doneCount or 0,
                    total = totalBonusCount or 0,
                }
            end
            -- Recipe summary is authoritative; override stale weekly snapshot when they differ.
            if recipeProgress and (
                not firstCraftProgress
                or (firstCraftProgress.total or 0) <= 0
                or (firstCraftProgress.current or 0) ~= (recipeProgress.current or 0)
                or (firstCraftProgress.total or 0) ~= (recipeProgress.total or 0)
            ) then
                firstCraftProgress = recipeProgress
            end
        end

        -- Recipes: known / total (Midnight only to avoid mixing expansions).
        if isMidnightRecipeData and recipeData.knownCount ~= nil and recipeData.totalCount and recipeData.totalCount > 0 then
            recipesText:SetText(FormatProgressPair({ current = recipeData.knownCount, total = recipeData.totalCount }))
        else
            recipesText:SetText("|cffffffff--|r")
        end

        firstCraftText:SetText(FormatProgressPair(firstCraftProgress))
        uniquesText:SetText(FormatProgressPair(progressData and progressData.uniques))
        treatiseText:SetText(FormatProgressPair(progressData and progressData.treatise))
        weeklyQuestText:SetText(FormatProgressPair(progressData and progressData.weeklyQuest))
        treasureText:SetText(FormatProgressPair(progressData and progressData.treasure))
        gatheringText:SetText(FormatProgressPair(progressData and progressData.gathering))
        catchUpText:SetText(FormatProgressPair(progressData and progressData.catchUp))

        -- Moxie: Artisan Moxie currency for this profession (Midnight; from DB/currency cache).
        local charKey = (ns.Utilities and ns.Utilities.GetCharacterKey) and ns.Utilities:GetCharacterKey(char.name, char.realm) or nil
        local moxieCurrencyID = slID and MIDNIGHT_MOXIE_CURRENCY[slID]
        if charKey and moxieCurrencyID and WarbandNexus.GetCurrencyData then
            local moxieData = WarbandNexus:GetCurrencyData(moxieCurrencyID, charKey)
            local qty = (moxieData and (moxieData.quantity or moxieData.value)) or 0
            moxieText:SetText(qty > 0 and format("|cffffffff%d|r", qty) or "|cffffffff--|r")
        else
            moxieText:SetText("|cffffffff--|r")
        end

        -- ===== SKILL COLUMN TOOLTIP (expansion breakdown — unique data) =====
        skillHit:SetScript("OnEnter", function(self)
            local lines = {}
            local expansions = char.professionExpansions and char.professionExpansions[profName]
            if expansions and #expansions > 0 then
                for _, exp in ipairs(expansions) do
                    local maxS = exp.maxSkillLevel or 0
                    local curS = exp.skillLevel or 0
                    local sc = (maxS > 0 and curS >= maxS) and {0.3,0.9,0.3} or (curS > 0 and {1,0.82,0} or {1,1,1})
                    lines[#lines+1] = { left = exp.name or "?", right = maxS > 0 and format("%d / %d", curS, maxS) or "--", leftColor = {1,1,1}, rightColor = sc }
                end
            end
            if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["SKILL"]) or "Skill", lines = lines, anchor = "ANCHOR_TOP" }) end
        end)
        skillHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)

        -- Unspent knowledge badge
        if kd and kd.unspentPoints and kd.unspentPoints > 0 then
            if not row[p.."Icon"].knowledgeBadge then
                local badge = row[p.."Icon"]:CreateTexture(nil, "OVERLAY")
                badge:SetSize(10, 10)
                badge:SetPoint("TOPRIGHT", row[p.."Icon"], "TOPRIGHT", 2, 0)
                badge:SetAtlas("icons_64x64_important")
                row[p.."Icon"].knowledgeBadge = badge
            end
            row[p.."Icon"].knowledgeBadge:Show()
        elseif row[p.."Icon"].knowledgeBadge then
            row[p.."Icon"].knowledgeBadge:Hide()
        end

        -- Open button
        local btn = row[p.."Btn"]
        if isCurrent then
            btn:Enable(); btn:SetAlpha(1); btn.label:SetTextColor(1, 1, 1)
            btn:SetScript("OnClick", function()
                if InCombatLockdown() then return end
                if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill then
                    local slot = char.professions and char.professions[lineIndex]
                    if slot and slot.skillLine then
                        C_TradeSkillUI.OpenTradeSkill(slot.skillLine)
                    elseif slot and slot.skillLineID then
                        C_TradeSkillUI.OpenTradeSkill(slot.skillLineID)
                    else
                        ToggleProfessionsBook()
                    end
                else
                    ToggleProfessionsBook()
                end
            end)
            btn:SetScript("OnEnter", function(self)
                if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["PROF_OPEN_RECIPE_TOOLTIP"]) or "Open recipe list", lines = {}, anchor = "ANCHOR_TOP" }) end
            end)
            btn:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        else
            btn:Disable(); btn:SetAlpha(0.3); btn.label:SetTextColor(0.5, 0.5, 0.5)
            btn:SetScript("OnClick", nil)
            btn:SetScript("OnEnter", function(self)
                if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["PROF_ONLY_CURRENT_CHAR"]) or "Only on current character", lines = {}, anchor = "ANCHOR_TOP" }) end
            end)
            btn:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        end
        btn:Show()

        -- Info button: always enabled — shows read-only DB data for any character
        local infoBtn = row[p.."InfoBtn"]
        local infoProfSlot = prof
        local infoCharKey = GetCharKey(char)
        infoBtn:Enable()
        infoBtn:SetAlpha(1)
        infoBtn:SetScript("OnClick", function()
            if WarbandNexus.ShowProfessionInfo then
                WarbandNexus:ShowProfessionInfo(infoCharKey, profName, infoProfSlot)
            end
        end)
        infoBtn:SetScript("OnEnter", function(self)
            if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["PROF_INFO_TOOLTIP"]) or "View profession details", lines = {}, anchor = "ANCHOR_TOP" }) end
        end)
        infoBtn:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        infoBtn:Show()

        -- Icon tooltip: only when there is meaningful data (skill per expansion, knowledge, concentration, equipment).
        -- Capture this row's profession name so equipment lookup is per-profession (no cross-show).
        local rowProfName = profName
        row[p.."Icon"]:SetScript("OnEnter", function(self)
            local lines = {}
            local expansions = char.professionExpansions and char.professionExpansions[rowProfName]
            if expansions and #expansions > 0 then
                for _, exp in ipairs(expansions) do
                    local maxS = exp.maxSkillLevel or 0
                    local curS = exp.skillLevel or 0
                    local sc = (maxS > 0 and curS >= maxS) and {0.3,0.9,0.3} or (curS > 0 and {1,0.82,0} or {1,1,1})
                    lines[#lines+1] = { left = exp.name or "?", right = maxS > 0 and format("%d / %d", curS, maxS) or "--", leftColor = {1,1,1}, rightColor = sc }
                end
            end
            local kdT = (slID and char.knowledgeData and char.knowledgeData[slID]) or (char.knowledgeData and char.knowledgeData[rowProfName])
            if kdT then
                local unspent, spent, maxPts = kdT.unspentPoints or 0, kdT.spentPoints or 0, kdT.maxPoints or 0
                local collectible = (maxPts > 0) and (maxPts - unspent - spent) or 0
                if collectible > 0 then lines[#lines+1] = { left = (ns.L and ns.L["COLLECTIBLE"]) or "Collectible", right = tostring(collectible), leftColor = {1,1,1}, rightColor = {0.3,0.9,0.3} } end
                if unspent > 0 then lines[#lines+1] = { left = (ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent", right = tostring(unspent), leftColor = {1, 0.82, 0}, rightColor = {1, 0.82, 0} } end
            end
            local concT = (slID and char.concentration and char.concentration[slID]) or (char.concentration and char.concentration[rowProfName])
            if concT and concT.max and concT.max > 0 then
                local est = concT.current or 0
                if WarbandNexus.GetEstimatedConcentration then est = WarbandNexus:GetEstimatedConcentration(concT) end
                local cc = est >= concT.max and {0.3,0.9,0.3} or (est > 0 and {1,0.82,0} or {1,1,1})
                lines[#lines+1] = { left = (ns.L and ns.L["CONCENTRATION"]) or "Concentration", right = format("%d / %d", est, concT.max), leftColor = {1,1,1}, rightColor = cc }
                if est < concT.max and WarbandNexus.GetConcentrationTimeToFull then
                    local ts = WarbandNexus:GetConcentrationTimeToFull(concT)
                    if ts and ts ~= "" and ts ~= "Full" then lines[#lines+1] = { left = (ns.L and ns.L["RECHARGE"]) or "Recharge", right = ts, leftColor = {1,1,1}, rightColor = {1,0.82,0} } end
                end
            end
            -- Equipment: show per-profession gear; fallback lookup by base name if key differs.
            local eqByProf = char.professionEquipment
            local eqKey = rowProfName and rowProfName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "") or rowProfName
            local eqData = eqByProf and (eqByProf[rowProfName] or eqByProf[eqKey]) or nil
            if not eqData and eqByProf and (rowProfName or eqKey) then
                for k, v in pairs(eqByProf) do
                    if k ~= "_legacy" and type(v) == "table" and (v.tool or v.accessory1 or v.accessory2) then
                        local norm = k:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
                        if norm == eqKey or norm == (rowProfName and rowProfName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "") or nil) or (eqKey and k:find(eqKey, 1, true)) then
                            eqData = v
                            break
                        end
                    end
                end
            end
            if not eqData and eqByProf and type(eqByProf._legacy) == "table" then
                local legacy = eqByProf._legacy
                if legacy.tool or legacy.accessory1 or legacy.accessory2 then
                    eqData = legacy
                end
            end
            if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
                local slotKeys = { "tool", "accessory1", "accessory2" }
                local tooltipSvc = ns.TooltipService
                for _, slotKey in ipairs(slotKeys) do
                    local item = eqData[slotKey]
                    if item then
                        local iconStr = item.icon and format("|T%s:0|t ", tostring(item.icon)) or ""
                        local statLines = tooltipSvc and tooltipSvc.GetItemTooltipSummaryLines and tooltipSvc:GetItemTooltipSummaryLines(item.itemLink, item.itemID, slotKey) or {}
                        local slotLabel = (statLines[1] and statLines[1].left) or (slotKey == "tool" and "Tool" or "Accessory")
                        lines[#lines+1] = { left = iconStr .. (item.name or "Unknown"), right = slotLabel, leftColor = {1,1,1}, rightColor = {0.5,0.5,0.5} }
                    end
                end
            else
                local eqHint = (ns.L and ns.L["PROF_EQUIPMENT_HINT"]) or "Open profession (K) on this character to scan equipment."
                lines[#lines+1] = { left = (ns.L and ns.L["EQUIPMENT"]) or "Equipment", right = eqData and "--" or "|cff888888" .. eqHint .. "|r", leftColor = {0.7,0.7,0.7}, rightColor = {0.5,0.5,0.5} }
            end
            if #lines > 0 and ShowTooltip then ShowTooltip(self, { type = "custom", icon = prof.icon, title = rowProfName, lines = lines, anchor = "ANCHOR_RIGHT" }) end
        end)
        row[p.."Icon"]:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
    else
        -- Empty slot
        if row[p.."Icon"].icon then row[p.."Icon"].icon:SetTexture(nil) end
        row[p.."Icon"]:Hide()
        row[p.."Name"]:SetText("|cffffffff" .. ((ns.L and ns.L["NO_PROFESSION"]) or "No Profession") .. "|r")
        row[p.."Skill"]:SetText("")
        row[p.."Recharge"]:SetText("")
        row[p.."Know"]:SetText("")
        if row[p.."KnowWarn"] then row[p.."KnowWarn"]:Hide() end
        recipesText:SetText("")
        firstCraftText:SetText("")
        uniquesText:SetText("")
        treatiseText:SetText("")
        weeklyQuestText:SetText("")
        treasureText:SetText("")
        gatheringText:SetText("")
        catchUpText:SetText("")
        moxieText:SetText("")
        row[p.."Btn"]:Hide()
        if row[p.."InfoBtn"] then row[p.."InfoBtn"]:Hide() end
        local concX = ColOffset("conc")
        local barTopY = centerY + BAR_HEIGHT / 2 - ROW_HEIGHT / 2
        UpdateConcentrationBar(row, p.."ConcBar", concX, barTopY, ColWidth("conc"), 0, 0)
        if row[p.."ConcBar"] then row[p.."ConcBar"]:Hide() end
        if row[p.."Icon"].knowledgeBadge then row[p.."Icon"].knowledgeBadge:Hide() end
        row[p.."Icon"]:SetScript("OnEnter", nil)
        row[p.."Icon"]:SetScript("OnLeave", nil)
        -- Hide hit-frames for empty slots
        skillHit:Hide()
    end
end
