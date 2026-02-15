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
    name        = { width = 140, spacing = COL_SPACING + 4 },    -- wider for realm names
    profIcon    = { width = 20,  spacing = ICON_COL_SPACING },
    profName    = { width = 110, spacing = COL_SPACING },         -- wider for long profession names
    skill       = { width = 70,  spacing = COL_SPACING },
    conc        = { width = 120, spacing = ICON_COL_SPACING },    -- bar (wider to match rep bar proportions)
    recharge    = { width = 80,  spacing = COL_SPACING },         -- timer text (e.g. "1d 10h 36m")
    knowledge   = { width = 70,  spacing = COL_SPACING },
    recipes     = { width = 85,  spacing = COL_SPACING },         -- known / total recipe count
    open        = { width = 36,  spacing = 0 },
}

local COLUMN_ORDER = {
    "favIcon", "classIcon", "name",
    "profIcon", "profName", "skill", "conc", "recharge", "knowledge", "recipes", "open",
}

local LEFT_PAD = 10

-- Column header definitions — alignment matches each column's data alignment
-- label = locale key; text = fallback if L[label] is nil; align = header text alignment
local HEADER_DEFS = {
    { col = "name",      label = "TABLE_HEADER_CHARACTER", text = "CHARACTER",     align = "LEFT" },
    { col = "profName",  label = "GROUP_PROFESSION",       text = "Profession",    align = "LEFT" },
    { col = "skill",     label = "SKILL",                  text = "Skill",         align = "CENTER" },
    { col = "conc",      label = "CONCENTRATION",          text = "Concentration", align = "CENTER",
      widthOverride = COLUMNS.conc.width + COLUMNS.conc.spacing + COLUMNS.recharge.width },
    { col = "knowledge", label = "KNOWLEDGE",              text = "Knowledge",     align = "CENTER" },
    { col = "recipes",   label = "RECIPES",                text = "Recipes",       align = "CENTER" },
}

local function ColOffset(key)
    local offset = LEFT_PAD
    for _, k in ipairs(COLUMN_ORDER) do
        if k == key then return offset end
        offset = offset + COLUMNS[k].width + COLUMNS[k].spacing
    end
    return offset
end

local function ColWidth(key)
    return COLUMNS[key] and COLUMNS[key].width or 60
end

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
        if char.professions and (char.professions[1] or char.professions[2]) then
            local isTracked = char.isTracked ~= false
            local charKey = (char.name or "Unknown") .. "-" .. (char.realm or "Unknown")
            if not isTracked then table.insert(untracked, char)
            elseif ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey) then table.insert(favorites, char)
            else table.insert(regular, char) end
        end
    end
    return SortCharacters(favorites, "favorites"), SortCharacters(regular, "regular"), SortCharacters(untracked, "untracked")
end

-- Realm display: insert spaces into normalized realm names (e.g. "TwistingNether" -> "Twisting Nether")
local function FormatRealmName(realm)
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

--============================================================================
-- DRAW TAB
--============================================================================

function WarbandNexus:DrawProfessionsTab(parent)
    local yOffset = 8
    local width = parent:GetWidth() - 20

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
        local w = hdef.widthOverride or ColWidth(col)
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
        row[p.."Name"]:SetWidth(ColWidth("profName"))
        row[p.."Name"]:SetJustifyH("LEFT")
        row[p.."Name"]:SetWordWrap(false)
        row[p.."Name"]:SetMaxLines(1)
    end
    row[p.."Name"]:ClearAllPoints()
    row[p.."Name"]:SetPoint("LEFT", nameX, centerY)

    -- SKILL
    local skillX = ColOffset("skill")
    if not row[p.."Skill"] then
        row[p.."Skill"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Skill"]:SetWidth(ColWidth("skill"))
        row[p.."Skill"]:SetJustifyH("CENTER")
        row[p.."Skill"]:SetMaxLines(1)
    end
    row[p.."Skill"]:ClearAllPoints()
    row[p.."Skill"]:SetPoint("LEFT", skillX, centerY)

    -- RECHARGE (timer text, right of bar)
    local rechargeX = ColOffset("recharge")
    if not row[p.."Recharge"] then
        row[p.."Recharge"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Recharge"]:SetWidth(ColWidth("recharge"))
        row[p.."Recharge"]:SetJustifyH("CENTER")
        row[p.."Recharge"]:SetMaxLines(1)
    end
    row[p.."Recharge"]:ClearAllPoints()
    row[p.."Recharge"]:SetPoint("LEFT", rechargeX, centerY)

    -- KNOWLEDGE
    local knowX = ColOffset("knowledge")
    if not row[p.."Know"] then
        row[p.."Know"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Know"]:SetWidth(ColWidth("knowledge"))
        row[p.."Know"]:SetJustifyH("CENTER")
        row[p.."Know"]:SetMaxLines(1)
    end
    row[p.."Know"]:ClearAllPoints()
    row[p.."Know"]:SetPoint("LEFT", knowX, centerY)

    -- RECIPES
    local recipesX = ColOffset("recipes")
    if not row[p.."Recipes"] then
        row[p.."Recipes"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Recipes"]:SetWidth(ColWidth("recipes"))
        row[p.."Recipes"]:SetJustifyH("CENTER")
        row[p.."Recipes"]:SetMaxLines(1)
    end
    row[p.."Recipes"]:ClearAllPoints()
    row[p.."Recipes"]:SetPoint("LEFT", recipesX, centerY)

    -- COLUMN HIT-FRAME (skill only — expansion breakdown is unique data)
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
                lines[#lines+1] = { left = " ", leftColor = {1,1,1} }
                local unspent, spent, maxPts = kdT.unspentPoints or 0, kdT.spentPoints or 0, kdT.maxPoints or 0
                if maxPts > 0 then
                    local collectible = maxPts - unspent - spent
                    if collectible > 0 then lines[#lines+1] = { left = (ns.L and ns.L["COLLECTIBLE"]) or "Collectible", right = tostring(collectible), leftColor = {1,1,1}, rightColor = {0.3,0.9,0.3} } end
                end
                if unspent > 0 then lines[#lines+1] = { left = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. unspent .. " " .. ((ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent Points"), leftColor = {1, 0.82, 0} } end
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
        if row[p.."Icon"].knowledgeBadge then row[p.."Icon"].knowledgeBadge:Hide() end
        row[p.."Icon"]:SetScript("OnEnter", nil)
        row[p.."Icon"]:SetScript("OnLeave", nil)
        -- Hide skill hit-frame for empty slots
        skillHit:Hide()
    end
end
