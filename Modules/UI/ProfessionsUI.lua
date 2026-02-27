--[[
    Warband Nexus - Professions Tab

    Layout: Single row per character, two profession lines stacked vertically.
    Character ordering mirrors CharactersUI (favorites, regular, untracked).
    Collapsible section headers for Favorites / Characters / Untracked.

    Column header bar sits above all sections with alignment matching data:
        LEFT-aligned:  CHARACTER, PROFESSION
        CENTER-aligned: SKILL, CONCENTRATION, KNOWLEDGE, RECIPES

    Column grid (per profession line):
        [FavIcon] [ClassIcon] [Name/Realm]  [ProfIcon] [ProfName] [Skill] [===ConcBar===] [Recharge] [Knowledge] [Recipes] [Open]

    Recipes column shows "known / total" format (e.g. "80 / 103").
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

--============================================================================
-- LAYOUT CONSTANTS
--============================================================================

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
    knowledge   = { width = 70,  spacing = COL_SPACING },
    recipes     = { width = 85,  spacing = COL_SPACING },         -- known / total recipe count
    firstCraft  = { width = 55,  spacing = COL_SPACING },         -- first craft bonus count
    skillUps    = { width = 55,  spacing = COL_SPACING },         -- skill-up recipe count
    cooldowns   = { width = 70,  spacing = COL_SPACING },         -- active recipe cooldowns
    orders      = { width = 55,  spacing = COL_SPACING },         -- crafting orders
    open        = { width = 36,  spacing = 0 },
}

local COLUMN_ORDER = {
    "favIcon", "classIcon", "name",
    "profIcon", "profName", "skill", "conc", "recharge", "knowledge",
    "recipes", "firstCraft", "skillUps", "cooldowns", "orders", "open",
}

local LEFT_PAD = 10

-- Text columns scale with effective font size; icon/bar/button columns stay fixed
local SCALABLE_COLUMNS = {
    name = true, profName = true, skill = true, recharge = true,
    knowledge = true, recipes = true, firstCraft = true,
    skillUps = true, cooldowns = true, orders = true,
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
    { col = "conc",      label = "CONCENTRATION",          text = "Concentration", align = "CENTER",
      getWidth = function() return ColWidth("conc") + COLUMNS.conc.spacing + ColWidth("recharge") end },
    { col = "knowledge", label = "KNOWLEDGE",              text = "Knowledge",     align = "CENTER" },
    { col = "recipes",   label = "RECIPES",                text = "Recipes",       align = "CENTER" },
    { col = "firstCraft",label = "FIRST_CRAFT",            text = "1st Craft",    align = "CENTER" },
    { col = "skillUps",  label = "SKILL_UPS",              text = "Skill Ups",    align = "CENTER" },
    { col = "cooldowns", label = "COOLDOWNS",                text = "Cooldowns",    align = "CENTER" },
    { col = "orders",   label = "ORDERS",                 text = "Orders",       align = "CENTER" },
}

--============================================================================
-- CONCENTRATION BAR
--============================================================================

local BAR_HEIGHT = 16
local BAR_BORDER = 1

local function UpdateConcentrationBar(parent, barKey, xOffset, yOffset, barWidth, current, maximum)
    local bar = parent[barKey]

    if not bar then
        bar = CreateFrame("Frame", nil, parent)
        bar:SetSize(barWidth, BAR_HEIGHT)
        bar:SetFrameLevel(parent:GetFrameLevel() + 2)

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
        for _, c in ipairs(list) do charMap[(c.name or "Unknown") .. "-" .. (c.realm or "Unknown")] = c end
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
        local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
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
-- FORMAT HELPERS (all return white text, colored where meaningful)
--============================================================================

local function GetCurrentExpansionSkill(char, profName)
    local expansions = char.professionExpansions and char.professionExpansions[profName]
    if not expansions or #expansions == 0 then return nil, nil, nil end
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

local function FormatKnowledge(kd)
    if not kd then return "|cffffffff--|r" end
    local spent = kd.spentPoints or 0
    local maxPts = kd.maxPoints or 0
    local unspent = kd.unspentPoints or 0
    local current = spent + unspent
    if current <= 0 and maxPts <= 0 then return "|cffffffff--|r" end

    local color
    if unspent > 0 then color = {1, 0.82, 0}
    elseif maxPts > 0 and current >= maxPts then color = {0.3, 0.9, 0.3}
    else color = {1, 1, 1} end

    local text
    if maxPts > 0 then
        text = FormatValueMax(current, maxPts, color)
    else
        text = format("|cff%02x%02x%02x%d|r", color[1]*255, color[2]*255, color[3]*255, current)
    end
    if unspent > 0 then
        text = text .. format(" |cffffd700(%d)|r", unspent)
    end
    return text
end

local function GetRecipeCount(char, profName)
    if not char.recipes then return 0, 0 end
    local data = char.recipes[profName]
    if not data then
        -- Fallback: keys may be skillLineIDs, check professionName field
        for _, profData in pairs(char.recipes) do
            if type(profData) == "table" and profData.professionName == profName then
                data = profData
                break
            end
        end
    end
    if not data or not data.knownRecipes then return 0, 0 end
    local known = 0
    for _ in pairs(data.knownRecipes) do known = known + 1 end
    local total = data.totalRecipes or 0
    return known, total
end

---Format elapsed time since a timestamp into a human-readable string.
---Reusable across all column tooltips for "Last Scanned" display.
---@param timestamp number Unix timestamp
---@return string|nil Formatted string or nil if invalid
local function FormatElapsedTime(timestamp)
    if not timestamp or timestamp <= 0 then return nil end
    local elapsed = time() - timestamp
    if elapsed < 60 then return (ns.L and ns.L["JUST_NOW"]) or "Just now"
    elseif elapsed < 3600 then return format("%dm ago", math.floor(elapsed / 60))
    elseif elapsed < 86400 then return format("%dh ago", math.floor(elapsed / 3600))
    else return format("%dd ago", math.floor(elapsed / 86400)) end
end

---Get first craft bonus and skill-up counts for a profession.
---Aggregates across all scanned expansions.
---@param char table Character data
---@param profName string Profession name
---@return number firstCraftCount, number skillUpCount, number latestScan
local function GetCraftStats(char, profName)
    local firstCraft, skillUp, latestScan = 0, 0, 0
    if not char.recipes then return firstCraft, skillUp, latestScan end

    for _, profData in pairs(char.recipes) do
        if type(profData) == "table" and profData.professionName == profName then
            firstCraft = firstCraft + (profData.firstCraftCount or 0)
            skillUp = skillUp + (profData.skillUpCount or 0)
            if (profData.lastScan or 0) > latestScan then
                latestScan = profData.lastScan
            end
        end
    end
    return firstCraft, skillUp, latestScan
end

---Get active cooldown count and details for a profession.
---@param char table Character data
---@param profName string Profession name
---@return number activeCDs, table cdList sorted by remaining time
local function GetCooldownInfo(char, profName)
    local cdList = {}
    local now = time()
    if not char.recipeCooldowns or not char.recipeCooldowns[profName] then
        return 0, cdList
    end

    for recipeID, cdData in pairs(char.recipeCooldowns[profName]) do
        if type(cdData) == "table" and cdData.remaining and cdData.scannedAt then
            local elapsed = now - cdData.scannedAt
            local remaining = cdData.remaining - elapsed
            if remaining > 0 then
                cdList[#cdList + 1] = {
                    recipeID     = recipeID,
                    name         = cdData.name or ("Recipe " .. recipeID),
                    remaining    = remaining,
                    isDayCooldown = cdData.isDayCooldown,
                    charges      = cdData.charges or 0,
                    maxCharges   = cdData.maxCharges or 0,
                }
            end
        end
    end

    -- Sort by remaining time ascending (soonest first)
    table.sort(cdList, function(a, b) return a.remaining < b.remaining end)
    return #cdList, cdList
end

---Format remaining seconds into a short human-readable duration.
---@param seconds number
---@return string
local function FormatDuration(seconds)
    if seconds <= 0 then return "Ready" end
    if seconds < 60 then return format("%ds", seconds) end
    if seconds < 3600 then return format("%dm", math.floor(seconds / 60)) end
    if seconds < 86400 then return format("%dh %dm", math.floor(seconds / 3600), math.floor((seconds % 3600) / 60)) end
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    return format("%dd %dh", days, hours)
end

---Get all recipe entries for a profession (may span multiple expansions).
---Returns an array of { storeKey, professionName, known, total, lastScan, expansionName }
---sorted by lastScan descending (most recent first).
---@param char table Character data
---@param profName string Profession name
---@return table entries Array of recipe data entries
local function GetRecipeBreakdown(char, profName)
    local entries = {}
    if not char.recipes then return entries end

    -- Build a skillLineID → expansion name lookup from professionExpansions
    local expNameBySkillLine = {}
    if char.professionExpansions and char.professionExpansions[profName] then
        for _, exp in ipairs(char.professionExpansions[profName]) do
            if exp.skillLineID then
                expNameBySkillLine[exp.skillLineID] = exp.name
            end
        end
    end

    for storeKey, profData in pairs(char.recipes) do
        if type(profData) == "table" and profData.professionName == profName then
            local known = 0
            if profData.knownRecipes then
                for _ in pairs(profData.knownRecipes) do known = known + 1 end
            end
            local total = profData.totalRecipes or 0
            -- Resolve expansion name: try skillLineID lookup, then storeKey itself
            local expName = nil
            if type(storeKey) == "number" then
                expName = expNameBySkillLine[storeKey]
            end
            expName = expName or profData.expansionName or profName

            entries[#entries + 1] = {
                storeKey      = storeKey,
                professionName = profData.professionName,
                known         = known,
                total         = total,
                lastScan      = profData.lastScan or 0,
                expansionName = expName,
            }
        end
    end

    -- Sort by lastScan descending (most recent first)
    table.sort(entries, function(a, b) return a.lastScan > b.lastScan end)
    return entries
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
        sortBtn:SetPoint("RIGHT", titleCard, "RIGHT", -20, 0)
    end
    
    titleCard:Show()
    yOffset = yOffset + 75

    -- ===== EMPTY STATE =====
    if totalProfChars == 0 then
        local emptyText = FontManager:CreateFontString(parent, DATA_FONT, "OVERLAY")
        emptyText:SetPoint("TOPLEFT", SIDE_MARGIN + 20, -yOffset - 30)
        emptyText:SetWidth(width - 40)
        emptyText:SetJustifyH("CENTER")
        emptyText:SetText("|cffffffff" .. ((ns.L and ns.L["NO_PROFESSIONS_DATA"]) or "No profession data available yet. Open your profession window (default: K) on each character to collect data.") .. "|r")
        return yOffset + 100
    end

    -- ===== COLUMN HEADER BAR =====
    local COLUMN_HEADER_HEIGHT = 22
    local colHeaderBar = CreateFrame("Frame", nil, parent)
    colHeaderBar:SetPoint("TOPLEFT", SIDE_MARGIN, -yOffset)
    colHeaderBar:SetPoint("TOPRIGHT", -SIDE_MARGIN, -yOffset)
    colHeaderBar:SetHeight(COLUMN_HEADER_HEIGHT)

    -- Subtle background for the header bar
    local colHeaderBg = colHeaderBar:CreateTexture(nil, "BACKGROUND")
    colHeaderBg:SetAllPoints()
    colHeaderBg:SetColorTexture(1, 1, 1, 0.03)

    -- Bottom separator line
    local colHeaderLine = colHeaderBar:CreateTexture(nil, "ARTWORK")
    colHeaderLine:SetPoint("BOTTOMLEFT", 0, 0)
    colHeaderLine:SetPoint("BOTTOMRIGHT", 0, 0)
    colHeaderLine:SetHeight(1)
    colHeaderLine:SetColorTexture(1, 1, 1, 0.08)

    for _, hdef in ipairs(HEADER_DEFS) do
        local col = hdef.col
        local lbl = FontManager:CreateFontString(colHeaderBar, "small", "OVERLAY")
        lbl:SetText("|cff888888" .. ((ns.L and ns.L[hdef.label]) or hdef.text) .. "|r")
        lbl:SetJustifyH(hdef.align or "CENTER")
        local w = (hdef.getWidth and hdef.getWidth()) or ColWidth(col)
        lbl:SetWidth(w)
        lbl:SetPoint("LEFT", colHeaderBar, "LEFT", ColOffset(col), 0)
    end

    yOffset = yOffset + COLUMN_HEADER_HEIGHT + 4  -- breathing room after header bar

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

    local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
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

    -- KNOWLEDGE
    local knowX = ColOffset("knowledge")
    if not row[p.."Know"] then
        row[p.."Know"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Know"]:SetJustifyH("CENTER")
        row[p.."Know"]:SetMaxLines(1)
    end
    row[p.."Know"]:SetWidth(ColWidth("knowledge"))
    row[p.."Know"]:ClearAllPoints()
    row[p.."Know"]:SetPoint("LEFT", knowX, centerY)

    -- RECIPES
    local recipesX = ColOffset("recipes")
    if not row[p.."Recipes"] then
        row[p.."Recipes"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Recipes"]:SetJustifyH("CENTER")
        row[p.."Recipes"]:SetMaxLines(1)
    end
    row[p.."Recipes"]:SetWidth(ColWidth("recipes"))
    row[p.."Recipes"]:ClearAllPoints()
    row[p.."Recipes"]:SetPoint("LEFT", recipesX, centerY)

    -- FIRST CRAFT
    local firstCraftX = ColOffset("firstCraft")
    if not row[p.."FirstCraft"] then
        row[p.."FirstCraft"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."FirstCraft"]:SetJustifyH("CENTER")
        row[p.."FirstCraft"]:SetMaxLines(1)
    end
    row[p.."FirstCraft"]:SetWidth(ColWidth("firstCraft"))
    row[p.."FirstCraft"]:ClearAllPoints()
    row[p.."FirstCraft"]:SetPoint("LEFT", firstCraftX, centerY)

    -- SKILL UPS
    local skillUpsX = ColOffset("skillUps")
    if not row[p.."SkillUps"] then
        row[p.."SkillUps"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."SkillUps"]:SetJustifyH("CENTER")
        row[p.."SkillUps"]:SetMaxLines(1)
    end
    row[p.."SkillUps"]:SetWidth(ColWidth("skillUps"))
    row[p.."SkillUps"]:ClearAllPoints()
    row[p.."SkillUps"]:SetPoint("LEFT", skillUpsX, centerY)

    -- COOLDOWNS
    local cooldownsX = ColOffset("cooldowns")
    if not row[p.."Cooldowns"] then
        row[p.."Cooldowns"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Cooldowns"]:SetJustifyH("CENTER")
        row[p.."Cooldowns"]:SetMaxLines(1)
    end
    row[p.."Cooldowns"]:SetWidth(ColWidth("cooldowns"))
    row[p.."Cooldowns"]:ClearAllPoints()
    row[p.."Cooldowns"]:SetPoint("LEFT", cooldownsX, centerY)

    -- ORDERS
    local ordersX = ColOffset("orders")
    if not row[p.."Orders"] then
        row[p.."Orders"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Orders"]:SetJustifyH("CENTER")
        row[p.."Orders"]:SetMaxLines(1)
    end
    row[p.."Orders"]:SetWidth(ColWidth("orders"))
    row[p.."Orders"]:ClearAllPoints()
    row[p.."Orders"]:SetPoint("LEFT", ordersX, centerY)

    -- COLUMN HIT-FRAMES (interactive tooltips for skill, recipes, firstCraft, skillUps, cooldowns, orders)
    local skillHit = AcquireColumnHitFrame(row, p.."SkillHit", "skill", centerY)
    local recipesHit = AcquireColumnHitFrame(row, p.."RecipesHit", "recipes", centerY)
    local firstCraftHit = AcquireColumnHitFrame(row, p.."FirstCraftHit", "firstCraft", centerY)
    local skillUpsHit = AcquireColumnHitFrame(row, p.."SkillUpsHit", "skillUps", centerY)
    local cooldownsHit = AcquireColumnHitFrame(row, p.."CooldownsHit", "cooldowns", centerY)
    local ordersHit = AcquireColumnHitFrame(row, p.."OrdersHit", "orders", centerY)

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

        -- Skill
        local curSkill, maxSkill = GetCurrentExpansionSkill(char, profName)
        if curSkill and maxSkill then
            row[p.."Skill"]:SetText(FormatSkill(curSkill, maxSkill))
        elseif prof.skill and prof.maxSkill then
            row[p.."Skill"]:SetText(FormatSkill(prof.skill, prof.maxSkill))
        else
            row[p.."Skill"]:SetText("|cffffffff--|r")
        end

        -- Concentration bar
        local concData = char.concentration and char.concentration[profName]
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

        -- Knowledge
        local kd = char.knowledgeData and char.knowledgeData[profName]
        row[p.."Know"]:SetText(FormatKnowledge(kd))

        -- Recipes (known / total)
        local knownRecipes, totalRecipes = GetRecipeCount(char, profName)
        if knownRecipes > 0 and totalRecipes > 0 then
            local color = (knownRecipes >= totalRecipes) and {0.3, 0.9, 0.3} or {1, 0.82, 0}
            row[p.."Recipes"]:SetText(FormatValueMax(knownRecipes, totalRecipes, color))
        elseif knownRecipes > 0 then
            row[p.."Recipes"]:SetText(format("|cff4de64d%d|r", knownRecipes))
        else
            row[p.."Recipes"]:SetText("|cffffffff--|r")
        end

        -- First Craft + Skill Ups
        local fcCount, suCount, craftStatsScan = GetCraftStats(char, profName)
        if craftStatsScan > 0 then
            row[p.."FirstCraft"]:SetText(fcCount > 0
                and format("|cff4de64d%d|r", fcCount)
                or "|cff888888-|r")
            row[p.."SkillUps"]:SetText(suCount > 0
                and format("|cffffff00%d|r", suCount)
                or "|cff888888-|r")
        else
            row[p.."FirstCraft"]:SetText("|cffffffff--|r")
            row[p.."SkillUps"]:SetText("|cffffffff--|r")
        end

        -- Cooldowns
        local activeCDs, cdList = GetCooldownInfo(char, profName)
        if activeCDs > 0 then
            row[p.."Cooldowns"]:SetText(format("|cffff6666%d|r", activeCDs))
        else
            -- Check if we have ANY cooldown data scanned
            local hasCDData = char.recipeCooldowns and char.recipeCooldowns[profName]
            row[p.."Cooldowns"]:SetText(hasCDData and "|cff4de64d0|r" or "|cffffffff--|r")
        end

        -- Orders
        local orderData = char.craftingOrders and char.craftingOrders[profName]
        if orderData and orderData.lastUpdate then
            local totalOrders = (orderData.personalPending or 0) + (orderData.publicAvailable or 0)
            if totalOrders > 0 then
                row[p.."Orders"]:SetText(format("|cffffff00%d|r", totalOrders))
            else
                row[p.."Orders"]:SetText("|cff4de64d0|r")
            end
        else
            row[p.."Orders"]:SetText("|cffffffff--|r")
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

        -- ===== RECIPES COLUMN TOOLTIP (learned / unlearned breakdown) =====
        recipesHit:SetScript("OnEnter", function(self)
            local lines = {}
            local breakdown = GetRecipeBreakdown(char, profName)
            if #breakdown > 0 then
                -- Aggregate totals across all scanned expansions
                local totalKnown, totalAll, latestScan = 0, 0, 0
                for _, entry in ipairs(breakdown) do
                    totalKnown = totalKnown + entry.known
                    totalAll = totalAll + entry.total
                    if entry.lastScan > latestScan then latestScan = entry.lastScan end
                end
                local totalUnlearned = totalAll - totalKnown

                -- Learned Recipes
                local learnedColor = (totalAll > 0 and totalKnown >= totalAll) and {0.3, 0.9, 0.3} or {1, 0.82, 0}
                lines[#lines + 1] = {
                    left = (ns.L and ns.L["LEARNED_RECIPES"]) or "Learned Recipes",
                    right = tostring(totalKnown),
                    leftColor = {1, 1, 1},
                    rightColor = learnedColor,
                }

                -- Unlearned Recipes
                if totalUnlearned > 0 then
                    lines[#lines + 1] = {
                        left = (ns.L and ns.L["UNLEARNED_RECIPES"]) or "Unlearned Recipes",
                        right = tostring(totalUnlearned),
                        leftColor = {1, 1, 1},
                        rightColor = {0.6, 0.6, 0.6},
                    }
                end

                -- Per-expansion breakdown (if multiple expansions scanned)
                if #breakdown > 1 then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    for _, entry in ipairs(breakdown) do
                        local k, t = entry.known, entry.total
                        local rc = (t > 0 and k >= t) and {0.3, 0.9, 0.3} or (k > 0 and {1, 0.82, 0} or {1, 1, 1})
                        lines[#lines + 1] = {
                            left = "  " .. (entry.expansionName or "?"),
                            right = t > 0 and format("%d / %d", k, t) or tostring(k),
                            leftColor = {0.8, 0.8, 0.8},
                            rightColor = rc,
                        }
                    end
                end

                -- Last scan timestamp (using shared helper)
                local scanText = FormatElapsedTime(latestScan)
                if scanText then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    lines[#lines + 1] = { left = (ns.L and ns.L["LAST_SCANNED"]) or "Last Scanned", right = scanText, leftColor = {0.5, 0.5, 0.5}, rightColor = {0.5, 0.5, 0.5} }
                end
            else
                lines[#lines + 1] = {
                    text = (ns.L and ns.L["RECIPE_NO_DATA"]) or "Open profession window to collect recipe data",
                    color = {0.5, 0.5, 0.5},
                }
            end
            if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["RECIPES"]) or "Recipes", lines = lines, anchor = "ANCHOR_TOP" }) end
        end)
        recipesHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)

        -- ===== FIRST CRAFT COLUMN TOOLTIP =====
        firstCraftHit:SetScript("OnEnter", function(self)
            local lines = {}
            local fc, _, scanTS = GetCraftStats(char, profName)
            if scanTS > 0 then
                lines[#lines + 1] = {
                    left = (ns.L and ns.L["FIRST_CRAFT_AVAILABLE"]) or "Available First Crafts",
                    right = tostring(fc),
                    leftColor = {1, 1, 1},
                    rightColor = fc > 0 and {0.3, 0.9, 0.3} or {0.5, 0.5, 0.5},
                }
                if fc > 0 then
                    lines[#lines + 1] = {
                        text = (ns.L and ns.L["FIRST_CRAFT_DESC"]) or "Recipes that grant bonus XP on first craft",
                        color = {0.7, 0.7, 0.7},
                    }
                end
                local scanText = FormatElapsedTime(scanTS)
                if scanText then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    lines[#lines + 1] = { left = (ns.L and ns.L["LAST_SCANNED"]) or "Last Scanned", right = scanText, leftColor = {0.5, 0.5, 0.5}, rightColor = {0.5, 0.5, 0.5} }
                end
            else
                lines[#lines + 1] = { text = (ns.L and ns.L["RECIPE_NO_DATA"]) or "Open profession window to collect data", color = {0.5, 0.5, 0.5} }
            end
            if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["FIRST_CRAFT"]) or "First Craft", lines = lines, anchor = "ANCHOR_TOP" }) end
        end)
        firstCraftHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)

        -- ===== SKILL UPS COLUMN TOOLTIP =====
        skillUpsHit:SetScript("OnEnter", function(self)
            local lines = {}
            local _, su, scanTS = GetCraftStats(char, profName)
            if scanTS > 0 then
                lines[#lines + 1] = {
                    left = (ns.L and ns.L["SKILLUP_RECIPES"]) or "Skill-up Recipes",
                    right = tostring(su),
                    leftColor = {1, 1, 1},
                    rightColor = su > 0 and {1, 0.82, 0} or {0.5, 0.5, 0.5},
                }
                if su > 0 then
                    lines[#lines + 1] = {
                        text = (ns.L and ns.L["SKILLUP_DESC"]) or "Recipes that can still increase your skill level",
                        color = {0.7, 0.7, 0.7},
                    }
                end
                local scanText = FormatElapsedTime(scanTS)
                if scanText then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    lines[#lines + 1] = { left = (ns.L and ns.L["LAST_SCANNED"]) or "Last Scanned", right = scanText, leftColor = {0.5, 0.5, 0.5}, rightColor = {0.5, 0.5, 0.5} }
                end
            else
                lines[#lines + 1] = { text = (ns.L and ns.L["RECIPE_NO_DATA"]) or "Open profession window to collect data", color = {0.5, 0.5, 0.5} }
            end
            if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["SKILL_UPS"]) or "Skill Ups", lines = lines, anchor = "ANCHOR_TOP" }) end
        end)
        skillUpsHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)

        -- ===== COOLDOWNS COLUMN TOOLTIP =====
        cooldownsHit:SetScript("OnEnter", function(self)
            local lines = {}
            local numCDs, cdDetails = GetCooldownInfo(char, profName)
            if numCDs > 0 then
                for _, cd in ipairs(cdDetails) do
                    local remStr = FormatDuration(cd.remaining)
                    lines[#lines + 1] = {
                        left = cd.name,
                        right = remStr,
                        leftColor = {1, 1, 1},
                        rightColor = cd.remaining < 3600 and {0.3, 0.9, 0.3} or cd.remaining < 86400 and {1, 0.82, 0} or {1, 0.4, 0.4},
                    }
                end
            elseif char.recipeCooldowns and char.recipeCooldowns[profName] then
                lines[#lines + 1] = {
                    text = (ns.L and ns.L["NO_ACTIVE_COOLDOWNS"]) or "No active cooldowns",
                    color = {0.3, 0.9, 0.3},
                }
            else
                lines[#lines + 1] = {
                    text = (ns.L and ns.L["RECIPE_NO_DATA"]) or "Open profession window to collect data",
                    color = {0.5, 0.5, 0.5},
                }
            end
            -- Last Scanned footer for cooldowns
            if char.recipeCooldowns and char.recipeCooldowns[profName] then
                -- Use the scan timestamp from any cooldown entry, or fallback to recipe scan
                local cdScanTime = 0
                for _, cdData in pairs(char.recipeCooldowns[profName]) do
                    if type(cdData) == "table" and (cdData.scannedAt or 0) > cdScanTime then
                        cdScanTime = cdData.scannedAt
                    end
                end
                -- Fallback: use recipe lastScan if no cooldowns with timestamps
                if cdScanTime == 0 then
                    local _, _, rScan = GetCraftStats(char, profName)
                    cdScanTime = rScan
                end
                local scanText = FormatElapsedTime(cdScanTime)
                if scanText then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    lines[#lines + 1] = { left = (ns.L and ns.L["LAST_SCANNED"]) or "Last Scanned", right = scanText, leftColor = {0.5, 0.5, 0.5}, rightColor = {0.5, 0.5, 0.5} }
                end
            end
            if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["COOLDOWNS"]) or "Cooldowns", lines = lines, anchor = "ANCHOR_TOP" }) end
        end)
        cooldownsHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)

        -- ===== ORDERS COLUMN TOOLTIP =====
        ordersHit:SetScript("OnEnter", function(self)
            local lines = {}
            local oData = char.craftingOrders and char.craftingOrders[profName]
            if oData and oData.lastUpdate then
                if (oData.personalPending or 0) > 0 then
                    lines[#lines + 1] = {
                        left = (ns.L and ns.L["PERSONAL_ORDERS"]) or "Personal Orders",
                        right = tostring(oData.personalPending),
                        leftColor = {1, 1, 1},
                        rightColor = {1, 0.82, 0},
                    }
                end
                if (oData.publicAvailable or 0) > 0 then
                    lines[#lines + 1] = {
                        left = (ns.L and ns.L["PUBLIC_ORDERS"]) or "Public Orders",
                        right = tostring(oData.publicAvailable),
                        leftColor = {1, 1, 1},
                        rightColor = {1, 0.82, 0},
                    }
                end
                if (oData.claimsRemaining or 0) > 0 then
                    lines[#lines + 1] = {
                        left = (ns.L and ns.L["CLAIMS_REMAINING"]) or "Claims Remaining",
                        right = tostring(oData.claimsRemaining),
                        leftColor = {1, 1, 1},
                        rightColor = {0.3, 0.9, 0.3},
                    }
                end
                if #lines == 0 then
                    lines[#lines + 1] = {
                        text = (ns.L and ns.L["NO_ACTIVE_ORDERS"]) or "No active orders",
                        color = {0.3, 0.9, 0.3},
                    }
                end
                -- Last Scanned footer
                local scanText = FormatElapsedTime(oData.lastUpdate)
                if scanText then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    lines[#lines + 1] = { left = (ns.L and ns.L["LAST_SCANNED"]) or "Last Scanned", right = scanText, leftColor = {0.5, 0.5, 0.5}, rightColor = {0.5, 0.5, 0.5} }
                end
            else
                lines[#lines + 1] = {
                    text = (ns.L and ns.L["ORDER_NO_DATA"]) or "Open profession at crafting table to scan",
                    color = {0.5, 0.5, 0.5},
                }
            end
            if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["CRAFTING_ORDERS"]) or "Crafting Orders", lines = lines, anchor = "ANCHOR_TOP" }) end
        end)
        ordersHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)

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
                if ShowTooltip then ShowTooltip(self, { type = "custom", icon = prof.icon, title = (ns.L and ns.L["PROF_OPEN_RECIPE_TOOLTIP"]) or "Open this profession's recipe list", lines = {}, anchor = "ANCHOR_TOP" }) end
            end)
            btn:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        else
            btn:Disable(); btn:SetAlpha(0.3); btn.label:SetTextColor(0.5, 0.5, 0.5)
            btn:SetScript("OnClick", nil)
            btn:SetScript("OnEnter", function(self)
                if ShowTooltip then ShowTooltip(self, { type = "custom", icon = prof.icon, title = profName, lines = {{text = (ns.L and ns.L["PROF_ONLY_CURRENT_CHAR"]) or "Only available for the current character", color = {1, 0.5, 0.5}}}, anchor = "ANCHOR_TOP" }) end
            end)
            btn:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        end
        btn:Show()

        -- Icon tooltip (detailed breakdown)
        row[p.."Icon"]:SetScript("OnEnter", function(self)
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
            local kdT = char.knowledgeData and char.knowledgeData[profName]
            if kdT then
                local unspent, spent, maxPts = kdT.unspentPoints or 0, kdT.spentPoints or 0, kdT.maxPoints or 0
                local collectible = (maxPts > 0) and (maxPts - unspent - spent) or 0
                local hasKnowledgeLine = (collectible > 0) or (unspent > 0)
                if hasKnowledgeLine then
                    lines[#lines+1] = { left = " ", leftColor = {1,1,1} }
                    if collectible > 0 then lines[#lines+1] = { left = (ns.L and ns.L["COLLECTIBLE"]) or "Collectible", right = tostring(collectible), leftColor = {1,1,1}, rightColor = {0.3,0.9,0.3} } end
                    if unspent > 0 then lines[#lines+1] = { left = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. unspent .. " " .. ((ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent Points"), leftColor = {1, 0.82, 0} } end
                end
            end
            local concT = char.concentration and char.concentration[profName]
            if concT and concT.max and concT.max > 0 then
                lines[#lines+1] = { left = " ", leftColor = {1,1,1} }
                local est = concT.current or 0
                if WarbandNexus.GetEstimatedConcentration then est = WarbandNexus:GetEstimatedConcentration(concT) end
                local cc = est >= concT.max and {0.3,0.9,0.3} or (est > 0 and {1,0.82,0} or {1,1,1})
                lines[#lines+1] = { left = (ns.L and ns.L["CONCENTRATION"]) or "Concentration", right = format("%d / %d", est, concT.max), leftColor = {1,1,1}, rightColor = cc }
                if est < concT.max and WarbandNexus.GetConcentrationTimeToFull then
                    local ts = WarbandNexus:GetConcentrationTimeToFull(concT)
                    if ts and ts ~= "" and ts ~= "Full" then lines[#lines+1] = { left = (ns.L and ns.L["RECHARGE"]) or "Recharge", right = ts, leftColor = {1,1,1}, rightColor = {1,0.82,0} } end
                end
            end
            local recKnown, recTotal = GetRecipeCount(char, profName)
            if recKnown > 0 then
                lines[#lines+1] = { left = " ", leftColor = {1,1,1} }
                local recStr = recTotal > 0 and format("%d / %d", recKnown, recTotal) or tostring(recKnown)
                local recColor = (recTotal > 0 and recKnown >= recTotal) and {0.3,0.9,0.3} or {1,0.82,0}
                lines[#lines+1] = { left = (ns.L and ns.L["RECIPES"]) or "Recipes", right = recStr, leftColor = {1,1,1}, rightColor = recColor }
            end
            -- Profession Equipment section (per-profession only; no fallback to avoid showing wrong profession's equipment)
            local eqByProf = char.professionEquipment
            local eqData = eqByProf and eqByProf[profName] or nil
            if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
                lines[#lines+1] = { left = " ", leftColor = {1,1,1} }
                local slotKeys = { "tool", "accessory1", "accessory2" }
                local tooltipSvc = ns.TooltipService
                for _, slotKey in ipairs(slotKeys) do
                    local item = eqData[slotKey]
                    if item then
                        local iconStr = item.icon and format("|T%s:0|t ", tostring(item.icon)) or ""
                        -- Get stat lines first to extract actual slot type (Head, Chest, Tool, etc.)
                        local statLines = tooltipSvc and tooltipSvc.GetItemTooltipSummaryLines and tooltipSvc:GetItemTooltipSummaryLines(item.itemLink, item.itemID, slotKey) or {}
                        -- First line contains the slot type (e.g., "Head", "Chest", "Tool")
                        local slotLabel = (statLines[1] and statLines[1].left) or (slotKey == "tool" and "Tool" or "Accessory")
                        lines[#lines+1] = {
                            left = iconStr .. (item.name or "Unknown"),
                            right = slotLabel,
                            leftColor = {1, 1, 1},
                            rightColor = {0.5, 0.5, 0.5},
                        }
                        -- Add remaining stat lines (skip first since it's now used as slot label)
                        for si = 2, #statLines do
                            local sLine = statLines[si]
                            lines[#lines+1] = {
                                left = "    " .. sLine.left,
                                right = sLine.right or "",
                                leftColor = sLine.leftColor or {0.7, 0.7, 0.7},
                                rightColor = sLine.rightColor or {0.7, 0.7, 0.7},
                            }
                        end
                    end
                end
            end
            if ShowTooltip then ShowTooltip(self, { type = "custom", icon = prof.icon, title = profName, lines = lines, anchor = "ANCHOR_RIGHT" }) end
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
        row[p.."Recipes"]:SetText("")
        row[p.."Btn"]:Hide()
        local concX = ColOffset("conc")
        local barTopY = centerY + BAR_HEIGHT / 2 - ROW_HEIGHT / 2
        UpdateConcentrationBar(row, p.."ConcBar", concX, barTopY, ColWidth("conc"), 0, 0)
        if row[p.."ConcBar"] then row[p.."ConcBar"]:Hide() end
        row[p.."FirstCraft"]:SetText("")
        row[p.."SkillUps"]:SetText("")
        row[p.."Cooldowns"]:SetText("")
        row[p.."Orders"]:SetText("")
        if row[p.."Icon"].knowledgeBadge then row[p.."Icon"].knowledgeBadge:Hide() end
        row[p.."Icon"]:SetScript("OnEnter", nil)
        row[p.."Icon"]:SetScript("OnLeave", nil)
        -- Hide hit-frames for empty slots
        skillHit:Hide()
        recipesHit:Hide()
        firstCraftHit:Hide()
        skillUpsHit:Hide()
        cooldownsHit:Hide()
        ordersHit:Hide()
    end
end
