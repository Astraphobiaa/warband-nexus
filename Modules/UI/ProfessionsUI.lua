--[[
    Warband Nexus - Professions Tab

    Layout: Single row per character, two profession lines stacked vertically.
    Character ordering mirrors CharactersUI (favorites, regular, untracked).
    Collapsible section headers for Favorites / Characters / Untracked.

    Column header row in scroll content (PvE parity) sits directly above sections:
        LEFT-aligned:  CHARACTER (text header)
        Icon + compact label (PvE parity): PROFESSION and all profession data columns
    Identity (name/realm) is vertically centered in the row; profession lines sit in
    symmetric upper/lower bands (ROW_HEIGHT/4 from midline). Uniform COL_SPACING (8px)
    between all columns. Vertical rules only in the profession data grid (not identity columns).

    Column grid (character row + per profession line):
        [FavIcon] [ClassIcon] [Name/Realm] [Open]  [ProfIcon] [ProfName] [Skill] [===ConcBar===] [Recharge] [Knowledge] …
    Open is one control per character (vertically centered); disabled when no primary profession or not logged in.

    Default column visibility matches prior behavior (Columns toggles persist in SavedVariables).
    Skill column has a hover tooltip showing all expansion skill breakdowns.
    Icon sizes (favIcon, classIcon) match CharactersUI (33px column, visual 65%).
    All data uses "body" font (12px); frozen column headers use subtitle for readability.
    Consistent 8px spacing between all data columns; subtle vertical rules in each gap (header + rows).

    WN_FACTORY: Columns dropdown shell uses Factory + ApplyVisuals (accent rim); pooled profession
    rows are created via FramePoolFactory (Factory bootstrap Button). Tooltip/equipment hit cells
    already prefer Factory helpers with CreateFrame fallback.
]]

local ADDON_NAME, ns = ...
local E = ns.Constants.EVENTS

--- Incremental professions tab paint (WN-PERF heavy tab first paint; Collections RunChunked parity).
ns.ProfessionsUI = ns.ProfessionsUI or {}
local ProfUI = ns.ProfessionsUI
ProfUI.CHUNK_SIZE = 4
ProfUI.CHUNK_MIN_CHARS = 5

local Utilities = ns.Utilities
local function SafeLower(s)
    return Utilities and Utilities.SafeLower and Utilities:SafeLower(s) or ""
end
local function CompareCharNameLower(a, b)
    return SafeLower(a.name) < SafeLower(b.name)
end
local issecretvalue = issecretvalue

-- Unique AceEvent handler identity for ProfessionsUI
local ProfessionsUIEvents = {}
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled

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
local BuildCollapsibleSectionOpts = ns.UI_BuildCollapsibleSectionOpts
local SyncGridColumnDividers = ns.UI_SyncGridColumnDividers

-- Pooling
local AcquireProfessionRow = ns.UI_AcquireProfessionRow
local ReleaseProfessionRow = ns.UI_ReleaseProfessionRow
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- Performance
local format = string.format
local min = math.min
local max = math.max
local tinsert = table.insert
local wipe = table.wipe

-- Session caches: survive across DrawProfessionsTab / PopulateContent so repeated UI gestures
-- (column sort, Columns toggle, expand/collapse) do not re-hit C_TradeSkillUI or rebuild recipe maps.
-- Invalidated on profession/recipe/equipment data messages (see bottom-of-file RegisterMessage hooks).
local profSessionIconBySkillLine = {}
local profSessionRecipeMapByCharKey = {}
-- Per-draw: equipment name fallback scan (pairs(eqByProf)) — at most once per char+prof per redraw.
local profEquipResolveCache = nil
local EQUIP_CACHE_MISS = {}

-- Layout
local function GetLayout() return ns.UI_LAYOUT or {} end
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or 10

local GetCharKey = ns.UI_GetCharKey

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
    if issecretvalue and issecretvalue(expName) then return nil end
    for ei = 1, #EXPANSION_ORDER do
        local known = EXPANSION_ORDER[ei]
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
                        for exi = 1, #expList do
                            local exp = expList[exi]
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
        for ei = 1, #EXPANSION_ORDER do
            local name = EXPANSION_ORDER[ei]
            if a == name then pa = ei end
            if b == name then pb = ei end
        end
        return pa < pb
    end)
    if not seen["Midnight"] then
        keys[#keys + 1] = "Midnight"
    end
    local options = {{key = "All", label = (ns.L and ns.L["PROF_FILTER_ALL"]) or "All"}}
    for ki = 1, #keys do
        local key = keys[ki]
        options[#options + 1] = {key = key, label = key}
    end
    return options
end

local ROW_HEIGHT = 52
local COL_SPACING = 8                -- Uniform gap after every column (WN-UI-layout single rhythm)
local OPEN_PROF_GAP = COL_SPACING  -- Same rhythm as other columns (no extra gap after Open)
local DATA_FONT = "body"             -- 12px - used for ALL data text

-- Column header row in scrollChild (PvE parity): 48px icons/labels + 2px before first section.
local COLUMN_HEADER_HEIGHT = 48
local COLUMN_HEADER_PAD = 2
local PROF_COLUMN_HEADER_FONT = "subtitle"
local PROF_COL_ICON_SIZE = 22

-- Two profession bands per row: centers at +/- ROW_HEIGHT/4 from row midline (symmetric halves).
local PROF_LINE_CENTER_Y = ROW_HEIGHT / 4
local LINE1_Y = PROF_LINE_CENTER_Y
local LINE2_Y = -PROF_LINE_CENTER_Y
local PROF_BAND_HEIGHT = ROW_HEIGHT / 2

--============================================================================
-- COLUMN DEFINITIONS
-- Each column: width, spacing (gap after this column), align for data
-- Order matters for offset calculation.
--============================================================================

local COLUMNS = {
    favIcon     = { width = 33,  spacing = COL_SPACING },
    classIcon   = { width = 33,  spacing = COL_SPACING },
    name        = { width = 100, spacing = COL_SPACING },
    open        = { width = 46,  spacing = OPEN_PROF_GAP },
    profIcon    = { width = 20,  spacing = COL_SPACING },
    profName    = { width = 100, spacing = COL_SPACING },
    equipment   = { width = 88,  spacing = COL_SPACING },
    skill       = { width = 70,  spacing = COL_SPACING },
    conc        = { width = 120, spacing = COL_SPACING },
    recharge    = { width = 65,  spacing = COL_SPACING },
    knowledge   = { width = 74,  spacing = COL_SPACING },
    recipes     = { width = 68,  spacing = COL_SPACING },
    firstCraft  = { width = 68,  spacing = COL_SPACING },
    uniques     = { width = 68,  spacing = COL_SPACING },
    treatise    = { width = 68,  spacing = COL_SPACING },
    weeklyQuest = { width = 68,  spacing = COL_SPACING },
    treasure    = { width = 68,  spacing = COL_SPACING },
    gathering   = { width = 68,  spacing = COL_SPACING },
    catchUp     = { width = 68,  spacing = COL_SPACING },
    moxie       = { width = 56,  spacing = COL_SPACING },
    cooldowns   = { width = 68,  spacing = COL_SPACING },
    info        = { width = 30,  spacing = 0 },
}

local ColumnOrder = ns.ColumnOrder

local PROF_IDENTITY_PREFIX = { "favIcon", "classIcon", "name", "open", "profIcon", "profName" }
local PROF_IDENTITY_SUFFIX = { "info" }
local PROF_TOGGLEABLE_DEFAULT_ORDER = {
    "equipment", "skill", "conc", "recharge", "knowledge",
    "recipes", "firstCraft", "uniques", "treatise", "weeklyQuest", "treasure", "gathering", "catchUp", "moxie",
    "cooldowns",
}
local PROF_TOGGLEABLE_KEY_SET = {}
for _pki = 1, #PROF_TOGGLEABLE_DEFAULT_ORDER do
    PROF_TOGGLEABLE_KEY_SET[PROF_TOGGLEABLE_DEFAULT_ORDER[_pki]] = true
end

local STATIC_COLUMN_ORDER = {
    "favIcon", "classIcon", "name", "open",
    "profIcon", "profName", "equipment", "skill", "conc", "recharge", "knowledge",
    "recipes", "firstCraft", "uniques", "treatise", "weeklyQuest", "treasure", "gathering", "catchUp", "moxie",
    "cooldowns",
    "info",
}
local columnOrder = STATIC_COLUMN_ORDER

local function EnsureProfessionColumnOrder(profile)
    if not profile or not ColumnOrder then return PROF_TOGGLEABLE_DEFAULT_ORDER end
    if type(profile.professionColumnOrder) ~= "table" then
        profile.professionColumnOrder = {}
    end
    local merged = ColumnOrder.MergeOrder(
        profile.professionColumnOrder,
        PROF_TOGGLEABLE_DEFAULT_ORDER,
        PROF_TOGGLEABLE_KEY_SET
    )
    for i = #profile.professionColumnOrder, 1, -1 do
        profile.professionColumnOrder[i] = nil
    end
    for i = 1, #merged do
        profile.professionColumnOrder[i] = merged[i]
    end
    return profile.professionColumnOrder
end

local function SyncProfessionColumnOrder(profile)
    if not ColumnOrder then
        columnOrder = STATIC_COLUMN_ORDER
        return columnOrder
    end
    local middle = EnsureProfessionColumnOrder(profile)
    local full = {}
    for pi = 1, #PROF_IDENTITY_PREFIX do full[#full + 1] = PROF_IDENTITY_PREFIX[pi] end
    for mi = 1, #middle do full[#full + 1] = middle[mi] end
    for si = 1, #PROF_IDENTITY_SUFFIX do full[#full + 1] = PROF_IDENTITY_SUFFIX[si] end
    columnOrder = full
    return columnOrder
end

local LEFT_PAD = 4                   -- In-row inset; row already anchored with SIDE_MARGIN

ns.MIN_PROFESSIONS_GRID_W = 0

-- Expansion filter: dynamically built from discovered expansion data across all characters.
-- Falls back to a static list if no character data is available yet.
local EXPANSION_FILTER_STATIC_FALLBACK = {
    { key = "All",          label = (ns.L and ns.L["PROF_FILTER_ALL"]) or "All" },
    { key = "Midnight",     label = (ns.L and ns.L["CONTENT_MIDNIGHT"]) or "Midnight" },
    { key = "Khaz Algar",   label = (ns.L and ns.L["CONTENT_KHAZ_ALGAR"]) or "Khaz Algar" },
    { key = "Dragon Isles", label = (ns.L and ns.L["CONTENT_DRAGON_ISLES"]) or "Dragon Isles" },
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

local function IsMidnightSkillLineID(skillLineID)
    return type(skillLineID) == "number" and MIDNIGHT_MOXIE_CURRENCY[skillLineID] ~= nil
end

-- Columns that users can toggle on/off via the Columns button.
-- Keys match COLUMNS table; display labels shown in the dropdown.
local TOGGLEABLE_COLUMNS = {
    { key = "skill",       label = (ns.L and ns.L["SKILL"]) or "Skill" },
    { key = "conc",        label = (ns.L and ns.L["CONCENTRATION"]) or "Concentration" },
    { key = "recharge",    label = (ns.L and ns.L["RECHARGE"]) or "Recharge" },
    { key = "knowledge",   label = (ns.L and ns.L["KNOWLEDGE"]) or "Knowledge" },
    { key = "recipes",     label = (ns.L and ns.L["RECIPES"]) or "Recipes" },
    { key = "firstCraft",  label = (ns.L and ns.L["FIRST_CRAFT"]) or "First Craft" },
    { key = "uniques",     label = (ns.L and ns.L["UNIQUES"]) or "Uniques" },
    { key = "treatise",    label = (ns.L and ns.L["TREATISE"]) or "Treatise" },
    { key = "weeklyQuest", label = (ns.L and ns.L["WEEKLY_QUEST_CAT"]) or "Weekly Quest" },
    { key = "treasure",    label = (ns.L and ns.L["SOURCE_TYPE_TREASURE"]) or "Treasure" },
    { key = "gathering",   label = (ns.L and ns.L["GATHERING"]) or "Gathering" },
    { key = "catchUp",     label = (ns.L and ns.L["CATCH_UP"]) or "Catch Up" },
    { key = "moxie",       label = (ns.L and ns.L["MOXIE"]) or "Moxie" },
    { key = "cooldowns",   label = (ns.L and ns.L["COOLDOWNS"]) or "Cooldowns" },
    { key = "equipment",   label = (ns.L and ns.L["EQUIPMENT"]) or "Equipment" },
}

local COLUMN_DEFAULT_VISIBLE = {
    cooldowns = false,
}

local function GetToggleableColumnsInPickerOrder(profile)
    local order = EnsureProfessionColumnOrder(profile)
    local byKey = {}
    for tci = 1, #TOGGLEABLE_COLUMNS do
        byKey[TOGGLEABLE_COLUMNS[tci].key] = TOGGLEABLE_COLUMNS[tci]
    end
    local out = {}
    for oi = 1, #order do
        local tc = byKey[order[oi]]
        if tc then out[#out + 1] = tc end
    end
    return out, order
end

--- Merge toggleable keys + defaults; migrate legacy tool/acc* slots to `equipment`.
local function EnsureProfessionVisibleColumns(profile)
    if not profile then return nil end
    profile.professionVisibleColumns = profile.professionVisibleColumns or {}
    local vis = profile.professionVisibleColumns
    if vis.tool == false or vis.acc1 == false or vis.acc2 == false then
        vis.equipment = false
    end
    vis.tool, vis.acc1, vis.acc2 = nil, nil, nil
    for tci = 1, #TOGGLEABLE_COLUMNS do
        local colKey = TOGGLEABLE_COLUMNS[tci].key
        if vis[colKey] == nil then
            local def = COLUMN_DEFAULT_VISIBLE[colKey]
            vis[colKey] = (def == nil)
        end
    end
    return vis
end

local function IsColumnVisible(key)
    local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    if not profile then
        local def = COLUMN_DEFAULT_VISIBLE[key]
        return def == nil
    end
    local vis = EnsureProfessionVisibleColumns(profile)
    if not vis then
        local def = COLUMN_DEFAULT_VISIBLE[key]
        return def == nil
    end
    return vis[key] ~= false
end

local function RequestProfessionColumnsRefresh()
    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, {
        tab = "professions",
        skipCooldown = true,
        instantPopulate = true,
    })
end

local function ProfColumnPickerHide()
    local menu = WarbandNexus._wnProfColumnPickerMenu
    if menu then menu:Hide() end
    local catcher = WarbandNexus._wnProfColumnPickerCatcher
    if catcher then catcher:Hide() end
end

local function ProfColumnPickerPositionMenu(menu, anchorBtn)
    if not menu or not anchorBtn then return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -4)
end

local function ProfColumnPickerShowCatcher(menu)
    local catcher = WarbandNexus._wnProfColumnPickerCatcher
    if not catcher then
        local FactDd = ns.UI and ns.UI.Factory
        catcher = FactDd and FactDd:CreateContainer(UIParent, 1, 1, false)
        if not catcher then
            catcher = CreateFrame("Button", "WarbandNexusProfColumnPickerCatcher", UIParent)
        end
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(math.max(1, (menu:GetFrameLevel() or 100) - 1))
        catcher:EnableMouse(true)
        catcher:Hide()
        catcher:SetScript("OnMouseDown", function()
            if not menu:IsShown() then
                catcher:Hide()
                return
            end
            local anchor = WarbandNexus._wnProfColumnPickerAnchorBtn
            if menu:IsMouseOver() or (anchor and anchor.IsMouseOver and anchor:IsMouseOver()) then
                return
            end
            menu:Hide()
        end)
        WarbandNexus._wnProfColumnPickerCatcher = catcher
    end
    catcher:SetFrameLevel(math.max(1, (menu:GetFrameLevel() or 100) - 1))
    catcher:Show()
end

local function ProfColumnPickerPopulateMenu(menu, anchorBtn)
    if not menu or not anchorBtn then return end
    local profile = WarbandNexus.db and WarbandNexus.db.profile
    if not profile then return end
    local vis = EnsureProfessionVisibleColumns(profile)
    if not vis then return end

    local ROW_H = (GetLayout().DROPDOWN_MENU_ROW_HEIGHT) or (GetLayout().ROW_HEIGHT) or 26
    local PAD = 6
    local FactDd = ns.UI and ns.UI.Factory
    local pickerCols, colOrder = GetToggleableColumnsInPickerOrder(profile)
    local contentH = #pickerCols * ROW_H + PAD * 2 + ROW_H + ROW_H
    menu:SetSize(228, contentH)

    local bin = ns.UI_RecycleBin
    local kids = { menu:GetChildren() }
    for i = 1, #kids do
        kids[i]:Hide()
        if bin then kids[i]:SetParent(bin) else kids[i]:SetParent(nil) end
    end

    local function RepopulatePickerAfterOrderChange()
        RequestProfessionColumnsRefresh()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                local picker = WarbandNexus._wnProfColumnPickerMenu
                local anchor = WarbandNexus._wnProfColumnPickerAnchorBtn
                local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
                if not picker or not anchor or not mf or mf.currentTab ~= "professions" then
                    ProfColumnPickerHide()
                    return
                end
                if not anchor.GetTop or not anchor:GetTop() then
                    ProfColumnPickerHide()
                    return
                end
                ProfColumnPickerPopulateMenu(picker, anchor)
                ProfColumnPickerPositionMenu(picker, anchor)
                picker:Show()
                ProfColumnPickerShowCatcher(picker)
            end)
        end
    end

    local yOff = -PAD
    for tci = 1, #pickerCols do
        local tc = pickerCols[tci]
        local isVisible = IsColumnVisible(tc.key)
        local checkRow = FactDd and FactDd.CreateButton and FactDd:CreateButton(menu, 216, ROW_H, true)
        if not checkRow then
            checkRow = CreateFrame("Button", nil, menu)
            checkRow:SetSize(216, ROW_H)
        end
        checkRow:SetPoint("TOPLEFT", PAD, yOff)

        local checkTex = checkRow:CreateTexture(nil, "ARTWORK")
        checkTex:SetSize(14, 14)
        checkTex:SetPoint("LEFT", 4, 0)
        if isVisible then
            checkTex:SetAtlas("common-icon-checkmark")
            checkTex:SetVertexColor(0.3, 0.9, 0.3)
        else
            checkTex:SetAtlas("common-icon-redx")
            checkTex:SetVertexColor(0.5, 0.5, 0.5)
        end

        local lbl = FontManager:CreateFontString(checkRow, "small", "OVERLAY")
        lbl:SetPoint("LEFT", checkTex, "RIGHT", 6, 0)
        lbl:SetText(isVisible and ("|cffffffff" .. tc.label .. "|r") or ("|cff888888" .. tc.label .. "|r"))
        lbl:SetJustifyH("LEFT")

        local capturedKey = tc.key
        checkRow:SetScript("OnClick", function()
            vis[capturedKey] = not IsColumnVisible(capturedKey)
            RepopulatePickerAfterOrderChange()
        end)
        checkRow:SetScript("OnEnter", function(f) f:SetAlpha(0.8) end)
        checkRow:SetScript("OnLeave", function(f) f:SetAlpha(1) end)
        checkRow:Show()

        if ColumnOrder and ColumnOrder.AttachPickerReorderButtons then
            ColumnOrder.AttachPickerReorderButtons(checkRow, colOrder, capturedKey, RepopulatePickerAfterOrderChange)
        end

        yOff = yOff - ROW_H
    end

    local resetOrderRow = FactDd and FactDd.CreateButton and FactDd:CreateButton(menu, 216, ROW_H, true)
    if not resetOrderRow then
        resetOrderRow = CreateFrame("Button", nil, menu)
        resetOrderRow:SetSize(216, ROW_H)
    end
    resetOrderRow:SetPoint("TOPLEFT", PAD, yOff)
    local resetOrderLbl = FontManager:CreateFontString(resetOrderRow, "small", "OVERLAY")
    resetOrderLbl:SetPoint("CENTER", 0, 0)
    resetOrderLbl:SetText("|cff" .. GetAccentHexColor() .. ((ns.L and ns.L["RESET_COLUMN_ORDER"]) or "Reset Order") .. "|r")
    resetOrderLbl:SetJustifyH("CENTER")
    resetOrderRow:SetScript("OnClick", function()
        if ColumnOrder then
            ColumnOrder.ResetToDefault(colOrder, PROF_TOGGLEABLE_DEFAULT_ORDER, PROF_TOGGLEABLE_KEY_SET)
        end
        RepopulatePickerAfterOrderChange()
    end)
    resetOrderRow:SetScript("OnEnter", function(f) f:SetAlpha(0.8) end)
    resetOrderRow:SetScript("OnLeave", function(f) f:SetAlpha(1) end)
    resetOrderRow:Show()
    yOff = yOff - ROW_H

    local resetRow = FactDd and FactDd.CreateButton and FactDd:CreateButton(menu, 216, ROW_H, true)
    if not resetRow then
        resetRow = CreateFrame("Button", nil, menu)
        resetRow:SetSize(216, ROW_H)
    end
    resetRow:SetPoint("TOPLEFT", PAD, yOff)
    local resetLbl = FontManager:CreateFontString(resetRow, "small", "OVERLAY")
    resetLbl:SetPoint("CENTER", 0, 0)
    resetLbl:SetText("|cff" .. GetAccentHexColor() .. ((ns.L and ns.L["SHOW_ALL"]) or "Show All") .. "|r")
    resetLbl:SetJustifyH("CENTER")
    resetRow:SetScript("OnClick", function()
        for ri = 1, #TOGGLEABLE_COLUMNS do
            vis[TOGGLEABLE_COLUMNS[ri].key] = true
        end
        RepopulatePickerAfterOrderChange()
    end)
    resetRow:SetScript("OnEnter", function(f) f:SetAlpha(0.8) end)
    resetRow:SetScript("OnLeave", function(f) f:SetAlpha(1) end)
    resetRow:Show()
end

function WarbandNexus:ShowProfessionColumnPicker(anchorBtn)
    if not anchorBtn then return end
    WarbandNexus._wnProfColumnPickerAnchorBtn = anchorBtn
    local FactDd = ns.UI and ns.UI.Factory
    local menu = WarbandNexus._wnProfColumnPickerMenu
    if not menu then
        menu = FactDd and FactDd:CreateContainer(UIParent, 228, 80, false)
        if not menu then
            menu = CreateFrame("Frame", "WarbandNexusProfColumnPickerMenu", UIParent, "BackdropTemplate")
            menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            menu:SetBackdropColor(0.08, 0.08, 0.1, 1)
        elseif ApplyVisuals then
            ApplyVisuals(menu, { 0.08, 0.08, 0.1, 1 },
                { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
        end
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(120)
        menu:SetClampedToScreen(true)
        menu:EnableMouse(true)
        menu:EnableMouseWheel(true)
        menu:SetScript("OnMouseWheel", function() end)
        menu:SetScript("OnHide", function()
            local catcher = WarbandNexus._wnProfColumnPickerCatcher
            if catcher then catcher:Hide() end
        end)
        WarbandNexus._wnProfColumnPickerMenu = menu
    end
    if WarbandNexus.db and WarbandNexus.db.profile then
        EnsureProfessionVisibleColumns(WarbandNexus.db.profile)
    end
    ProfColumnPickerPopulateMenu(menu, anchorBtn)
    ProfColumnPickerPositionMenu(menu, anchorBtn)
    menu:Show()
    ProfColumnPickerShowCatcher(menu)
end

function WarbandNexus:HideProfessionColumnPicker()
    ProfColumnPickerHide()
end

-- Text columns scale with effective font size; icon/bar/button columns stay fixed
local SCALABLE_COLUMNS = {
    name = true, profName = true, skill = true, recharge = true, knowledge = true,
    recipes = true, firstCraft = true, uniques = true, treatise = true, weeklyQuest = true,
    treasure = true, gathering = true, catchUp = true, moxie = true, cooldowns = true,
}

-- Dynamic grid width: accounts for current column visibility and font-based scaling.
-- Called every time the professions tab is drawn or the window is resized so that
-- the scrollChild is always wide enough to show all visible columns without clipping.
function ns.ComputeProfessionsGridWidth()
    SyncProfessionColumnOrder(WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile)
    local fontScale = 1.0
    if FontManager and FontManager.GetFontSize then
        local actualSize = FontManager:GetFontSize(DATA_FONT)
        if actualSize and actualSize > 0 then
            fontScale = math.max(1.0, actualSize / 12)
        end
    end

    local total = 0
    for ki = 1, #columnOrder do
        local k = columnOrder[ki]
        if IsColumnVisible(k) then
            local w = COLUMNS[k].width
            if SCALABLE_COLUMNS[k] then
                w = w * fontScale
            end
            total = total + w + COLUMNS[k].spacing
        end
    end

    local sideMargin = (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 10
    return math.ceil(2 * sideMargin + LEFT_PAD + total)
end

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
        for ki = 1, #columnOrder do
            local k = columnOrder[ki]
            if IsColumnVisible(k) then
                baseTotal = baseTotal + COLUMNS[k].width + COLUMNS[k].spacing
                if SCALABLE_COLUMNS[k] then
                    scalableBase = scalableBase + COLUMNS[k].width
                end
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
    if not IsColumnVisible(key) then return 0 end
    local base = COLUMNS[key] and COLUMNS[key].width or 60
    if SCALABLE_COLUMNS[key] then
        return base * GetColumnScaleFactor()
    end
    return base
end

local function ColOffset(key)
    local offset = LEFT_PAD
    local scaleFactor = GetColumnScaleFactor()
    for ki = 1, #columnOrder do
        local k = columnOrder[ki]
        if k == key then return offset end
        if IsColumnVisible(k) then
            local w = COLUMNS[k].width
            if SCALABLE_COLUMNS[k] then
                w = w * scaleFactor
            end
            offset = offset + w + COLUMNS[k].spacing
        end
    end
    return offset
end

--- Horizontal center of a column (for CENTER anchors / header alignment).
local function ColCenterX(key)
    return ColOffset(key) + ColWidth(key) / 2
end

--- Center X of gaps in the profession data grid only (after Profession column — not identity/open).
local function BuildProfessionColumnDividerXs()
    local xs = {}
    local inDataGrid = false
    for ki = 1, #columnOrder - 1 do
        local k = columnOrder[ki]
        if k == "profName" then
            inDataGrid = true
        end
        if not inDataGrid or not IsColumnVisible(k) then
            -- identity columns: no per-column dividers
        else
            local hasNextVisible = false
            for kj = ki + 1, #columnOrder do
                if IsColumnVisible(columnOrder[kj]) then
                    hasNextVisible = true
                    break
                end
            end
            if hasNextVisible then
                local nextKey
                for kj = ki + 1, #columnOrder do
                    if IsColumnVisible(columnOrder[kj]) then
                        nextKey = columnOrder[kj]
                        break
                    end
                end
                -- No rule before the info (?) column — too tight against the button.
                if nextKey ~= "info" then
                    local spacing = (COLUMNS[k] and COLUMNS[k].spacing) or COL_SPACING
                    xs[#xs + 1] = ColOffset(k) + ColWidth(k) + spacing * 0.5
                end
            end
        end
    end
    return xs
end

local function ApplyProfessionColumnDividers(parent, height)
    if SyncGridColumnDividers and parent then
        SyncGridColumnDividers(parent, BuildProfessionColumnDividerXs(), height)
    end
end

--- Uniform tint width for every row (fav + class + name + open); avoids per-name width gaps when scrolling horizontally.
local function GetProfessionIdentityGradientEnd()
    if IsColumnVisible("profIcon") then
        return ColOffset("profIcon")
    end
    if IsColumnVisible("open") then
        return ColOffset("open") + ColWidth("open")
    end
    if IsColumnVisible("name") then
        return ColOffset("name") + ColWidth("name")
    end
    return ColOffset("classIcon") + ColWidth("classIcon")
end

--- Anchor a cell to its column: LEFT edge or horizontal CENTER on the row midline.
local function AnchorCellInColumn(frame, colKey, row, centerY, hAlign)
    if not frame or not colKey or not row then return end
    local w = ColWidth(colKey)
    if w <= 0 then return end
    frame:ClearAllPoints()
    if hAlign == "CENTER" then
        frame:SetPoint("CENTER", row, "LEFT", ColCenterX(colKey), centerY)
    else
        frame:SetPoint("LEFT", row, "LEFT", ColOffset(colKey), centerY)
    end
end

--- Plain header text (no |c escapes — they wrap as stray "|..." in narrow columns).
local function StripProfHeaderDisplayText(text)
    if type(text) ~= "string" then return "" end
    return text
        :gsub("|c%x%x%x%x%x%x%x%x", "")
        :gsub("|r", "")
        :gsub("|T.-|t", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
end

local PROF_HDR_COLOR = { 0.72, 0.72, 0.75 }
local PROF_HDR_COLOR_HILITE = { 1, 1, 1 }

local function ApplyProfColumnHeaderLabel(lbl, displayText, highlighted)
    if not lbl then return end
    if lbl.SetWordWrap then lbl:SetWordWrap(false) end
    if lbl.SetMaxLines then lbl:SetMaxLines(1) end
    local c = highlighted and PROF_HDR_COLOR_HILITE or PROF_HDR_COLOR
    lbl:SetTextColor(c[1], c[2], c[3])
    lbl:SetText(displayText or "")
end

local ToggleColumnSort

local function BindProfColumnHeaderTooltip(frame, tooltipTitle)
    if not frame or not tooltipTitle or tooltipTitle == "" then return end
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if ShowTooltip then
            ShowTooltip(self, { type = "custom", title = tooltipTitle, lines = {}, anchor = "ANCHOR_TOP" })
        end
    end)
    frame:SetScript("OnLeave", function()
        if HideTooltip then HideTooltip() end
    end)
end

local function ProfessionHeaderIconIsDrawn(iconTex)
    if not iconTex then return false end
    if iconTex.GetAtlas then
        local atlas = iconTex:GetAtlas()
        if atlas and atlas ~= "" then return true end
    end
    if iconTex.GetTexture then
        local tex = iconTex:GetTexture()
        if tex and tex ~= "" then return true end
    end
    return false
end

local function TryApplyProfessionHeaderAtlas(iconTex, atlasName)
    if not iconTex or not iconTex.SetAtlas or not atlasName or atlasName == "" then return false end
    iconTex:SetTexture(nil)
    local modes = { false, true }
    local ign = _G.TextureKitConstants and TextureKitConstants.IgnoreAtlasSize
    if ign ~= nil then
        modes[#modes + 1] = ign
    end
    local tryNames = { atlasName, string.format("%s:%d:%d", atlasName, PROF_COL_ICON_SIZE, PROF_COL_ICON_SIZE) }
    for ni = 1, #tryNames do
        local name = tryNames[ni]
        for mi = 1, #modes do
            if pcall(iconTex.SetAtlas, iconTex, name, modes[mi]) and ProfessionHeaderIconIsDrawn(iconTex) then
                iconTex:SetSize(PROF_COL_ICON_SIZE, PROF_COL_ICON_SIZE)
                iconTex:SetVertexColor(1, 1, 1, 1)
                iconTex:Show()
                return true
            end
            iconTex:SetTexture(nil)
        end
    end
    return false
end

local function ApplyProfessionHeaderFileIcon(iconTex, path)
    if not iconTex or not path or path == "" then return false end
    iconTex:SetTexture(nil)
    if not pcall(iconTex.SetTexture, iconTex, path) then return false end
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconTex:SetVertexColor(1, 1, 1, 1)
    iconTex:Show()
    return ProfessionHeaderIconIsDrawn(iconTex)
end

local function ApplyProfessionHeaderIconTexture(iconTex, iconDef)
    if not iconTex or not iconDef then return end
    iconTex:Hide()
    iconTex:SetTexture(nil)
    local paths = iconDef.iconPaths
    if type(paths) ~= "table" then paths = {} end
    if iconDef.iconFallback and iconDef.iconFallback ~= "" then
        local hasFallback = false
        for pi = 1, #paths do
            if paths[pi] == iconDef.iconFallback then
                hasFallback = true
                break
            end
        end
        if not hasFallback then
            paths[#paths + 1] = iconDef.iconFallback
        end
    end
    for pi = 1, #paths do
        if ApplyProfessionHeaderFileIcon(iconTex, paths[pi]) then return end
    end
    if iconDef.icon and iconDef.iconIsAtlas == false then
        if ApplyProfessionHeaderFileIcon(iconTex, iconDef.icon) then return end
    end
    if iconTex.SetAtlas and (iconDef.iconIsAtlas or type(iconDef.iconAtlases) == "table") then
        local candidates = iconDef.iconAtlases
        if type(candidates) ~= "table" or #candidates == 0 then
            candidates = iconDef.icon and { iconDef.icon } or nil
        end
        if type(candidates) == "table" then
            for ci = 1, #candidates do
                if TryApplyProfessionHeaderAtlas(iconTex, candidates[ci]) then
                    return
                end
            end
        end
    elseif iconDef.icon then
        if ApplyProfessionHeaderFileIcon(iconTex, iconDef.icon) then return end
    end
    if iconDef.iconFallback then
        ApplyProfessionHeaderFileIcon(iconTex, iconDef.iconFallback)
    end
end

local PROF_COMPACT_HEADER_HEX = "aaaaaa"

local function BuildProfCompactHeaderLabel(col, displayText)
    if type(displayText) ~= "string" or displayText == "" then return "", PROF_COMPACT_HEADER_HEX end
    local shortByCol = {
        profName = (ns.L and ns.L["GROUP_PROFESSION"]) or "Profession",
        equipment = (ns.L and ns.L["EQUIPMENT"]) or "Equip",
        skill = (ns.L and ns.L["SKILL"]) or "Skill",
        conc = (ns.L and ns.L["CONCENTRATION"]) or "Conc",
        recharge = (ns.L and ns.L["RECHARGE"]) or "Regen",
        knowledge = (ns.L and ns.L["KNOWLEDGE"]) or "Know",
        recipes = (ns.L and ns.L["RECIPES"]) or "Recipes",
        firstCraft = (ns.L and ns.L["FIRST_CRAFT"]) or "1st",
        uniques = (ns.L and ns.L["UNIQUES"]) or "Unique",
        treatise = (ns.L and ns.L["TREATISE"]) or "Treat",
        weeklyQuest = (ns.L and ns.L["WEEKLY_QUEST_CAT"]) or "Weekly",
        treasure = (ns.L and ns.L["SOURCE_TYPE_TREASURE"]) or "Treas",
        gathering = (ns.L and ns.L["GATHERING"]) or "Gather",
        catchUp = (ns.L and ns.L["CATCH_UP"]) or "Catch",
        moxie = (ns.L and ns.L["MOXIE"]) or "Moxie",
        cooldowns = (ns.L and ns.L["COOLDOWNS"]) or "CD",
    }
    if col and shortByCol[col] then
        return shortByCol[col], PROF_COMPACT_HEADER_HEX
    end
    if #displayText > 10 then
        return displayText:sub(1, 9) .. ".", PROF_COMPACT_HEADER_HEX
    end
    return displayText, PROF_COMPACT_HEADER_HEX
end

local profColHeaderLabels = {}
local profColHeaderHits = {}

--- PopulateContent parks scrollChild children in recycleBin; reattach when Professions redraws.
local function ReattachProfessionColumnHeaderBar(colHeaderBar, parent)
    if not colHeaderBar or not parent then return end
    if colHeaderBar:GetParent() ~= parent then
        colHeaderBar:SetParent(parent)
    end
    colHeaderBar._wnProfColumnHeaderStrip = true
    if colHeaderBar.SetFrameStrata and parent.GetFrameStrata then
        colHeaderBar:SetFrameStrata(parent:GetFrameStrata())
    end
    if colHeaderBar.SetFrameLevel and parent.GetFrameLevel then
        colHeaderBar:SetFrameLevel(parent:GetFrameLevel() + 2)
    end
end

--- Hide profession-only column headers when another main tab is active (must not use _wnKeepOnTabSwitch).
function ns.UI_HideProfessionColumnHeaderStrip(scrollChild)
    if not scrollChild then return end
    local bar = scrollChild._wnProfColHeaderRow
    if bar then
        bar._wnKeepOnTabSwitch = nil
        bar:Hide()
        bar:ClearAllPoints()
    end
    for _, fs in pairs(profColHeaderLabels) do
        if fs and fs.Hide then fs:Hide() end
    end
    for _, hit in pairs(profColHeaderHits) do
        if hit and hit.Hide then hit:Hide() end
    end
end

local function ProfAcquireColHeaderLabel(colHeaderBar, colKey, hitFrame, compactLabel, compactHex, colWidth)
    if not colHeaderBar or not hitFrame or not compactLabel or compactLabel == "" then return nil end
    local fs = profColHeaderLabels[colKey]
    if not fs then
        fs = FontManager:CreateFontString(colHeaderBar, "bodySmall", "OVERLAY")
        profColHeaderLabels[colKey] = fs
    else
        fs:SetParent(colHeaderBar)
        fs:Show()
    end
    fs:SetPoint("TOP", hitFrame, "BOTTOM", 0, 0)
    fs:SetWidth(math.max(24, colWidth - 4))
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetText("|cff" .. (compactHex or PROF_COMPACT_HEADER_HEX) .. compactLabel .. "|r")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    return fs
end

--- Icon + compact label (PvE column header parity); full locale title on hover.
local function PaintProfessionCompactColumnHeader(colHeaderBar, col, w, iconDef, hdef, sortState, tooltipTitle, accentR, accentG, accentB, FactHdr)
    if not colHeaderBar or not iconDef or w <= 0 then return end
    local hitW, hitH = PROF_COL_ICON_SIZE + 4, PROF_COL_ICON_SIZE + 4
    local sortable = hdef and hdef.sortable
    local hitBtn = profColHeaderHits[col]
    if not hitBtn then
        if sortable then
            hitBtn = FactHdr and FactHdr:CreateButton(colHeaderBar, hitW, hitH, true)
            if not hitBtn then
                hitBtn = CreateFrame("Button", nil, colHeaderBar)
                hitBtn:SetSize(hitW, hitH)
            end
            hitBtn:EnableMouse(true)
        else
            hitBtn = FactHdr and FactHdr:CreateContainer(colHeaderBar, hitW, hitH, false)
            if not hitBtn then
                hitBtn = CreateFrame("Frame", nil, colHeaderBar)
                hitBtn:SetSize(hitW, hitH)
            end
            hitBtn:EnableMouse(true)
        end
        local iconTex = hitBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(PROF_COL_ICON_SIZE, PROF_COL_ICON_SIZE)
        iconTex:SetPoint("CENTER", hitBtn, "CENTER", 0, 0)
        hitBtn._wnHeaderIconTex = iconTex
        profColHeaderHits[col] = hitBtn
    else
        hitBtn:SetParent(colHeaderBar)
        hitBtn:SetSize(hitW, hitH)
        hitBtn:Show()
        if sortable and hitBtn.EnableMouse then hitBtn:EnableMouse(true) end
    end
    if FactHdr and FactHdr.ApplyIconOnlyButtonChrome and hitBtn.GetObjectType and hitBtn:GetObjectType() == "Button" then
        FactHdr:ApplyIconOnlyButtonChrome(hitBtn)
    end
    hitBtn:ClearAllPoints()
    hitBtn:SetPoint("LEFT", colHeaderBar, "LEFT", ColOffset(col) + (w - hitW) * 0.5, 6)
    hitBtn:SetFrameLevel(colHeaderBar:GetFrameLevel() + 2)

    local iconTex = hitBtn._wnHeaderIconTex
    if not iconTex or not iconTex.SetTexture then
        iconTex = hitBtn:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(PROF_COL_ICON_SIZE, PROF_COL_ICON_SIZE)
        iconTex:SetPoint("CENTER", hitBtn, "CENTER", 0, 0)
        hitBtn._wnHeaderIconTex = iconTex
    end
    ApplyProfessionHeaderIconTexture(iconTex, iconDef)
    BindProfColumnHeaderTooltip(hitBtn, tooltipTitle)

    local compactLabel, compactHex = BuildProfCompactHeaderLabel(col, tooltipTitle)
    if compactLabel ~= "" then
        ProfAcquireColHeaderLabel(colHeaderBar, col, hitBtn, compactLabel, compactHex, w)
    end

    if not hdef or not hdef.sortable then
        return
    end

    local isSorted = sortState and sortState.col == col
    local arrow = hitBtn._wnSortArrow
    if not arrow then
        arrow = hitBtn:CreateTexture(nil, "OVERLAY")
        arrow:SetSize(11, 11)
        arrow:SetPoint("TOPRIGHT", hitBtn, "TOPRIGHT", -1, -2)
        hitBtn._wnSortArrow = arrow
    end
    if isSorted then
        if sortState.dir == "asc" then
            arrow:SetAtlas("hud-MainMenuBar-arrowup")
        else
            arrow:SetAtlas("hud-MainMenuBar-arrowdown")
        end
        arrow:SetVertexColor(accentR, accentG, accentB, 1)
        arrow:Show()
    else
        arrow:Hide()
    end

    local capturedCol = col
    local prevOnEnter = hitBtn:GetScript("OnEnter")
    local prevOnLeave = hitBtn:GetScript("OnLeave")
    hitBtn:SetScript("OnClick", function()
        if ToggleColumnSort then
            ToggleColumnSort(capturedCol)
        end
    end)
    hitBtn:SetScript("OnEnter", function(self)
        if prevOnEnter then prevOnEnter(self) end
        if not isSorted then
            arrow:SetAtlas("hud-MainMenuBar-arrowup")
            arrow:SetVertexColor(1, 1, 1, 0.4)
            arrow:Show()
        end
    end)
    hitBtn:SetScript("OnLeave", function(self)
        if prevOnLeave then prevOnLeave(self) end
        if not isSorted then
            arrow:Hide()
        end
    end)
end

-- Column header definitions — alignment matches each column's data alignment
-- label = locale key; text = fallback if L[label] is nil; align = header text alignment
-- sortable = true means clicking the header toggles ascending/descending sort
--- Column header icons mapped to retail profession UI (Gethe/wow-ui-source live, May 2026).
--- Order: iconPaths (file) -> iconAtlases (C_Texture.GetAtlasInfo + SetAtlas) -> iconFallback.
--- Sources: Blizzard_ProfessionsTemplates (recipe/schematic), Blizzard_ProfessionsSpecializations (knowledge ring),
--- Blizzard_ProfessionsRecipeList (skill tier icons), Blizzard_ProfessionsCurrencyTemplate (UI_Concentration),
--- ProfessionsTemplates.lua (auctionhouse-icon-clock = expiration/recharge column).
local PROF_HEADER_ICON_BY_COL = {
    -- Recipe list / profession book tab parity
    profName    = { iconAtlases = { "professions-icon-book", "professions_recipes_abilitytab", "Professions-recipe-header-left" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Misc_Book_09" },
    -- Equipment slots: Professions-Slot-Plus (Templates); legacy creationgear fallback
    equipment   = { iconAtlases = { "Professions-Slot-Plus", "creationgear-32x32", "ItemUpgrade_Icon" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Hammer_20" },
    -- Skill-ups: Professions-Icon-Skill-* (RecipeList.lua); in_progress is reliable legacy fallback
    skill       = { iconAtlases = { "professions_recipes_in_progress", "Professions-Icon-Skill-Medium", "Professions-Icon-Skill-High", "Professions-Icon-Skill-Low" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\Trade_Engineering" },
    -- Concentration currency icon (ProfessionsCurrencyTemplate XML — file, not atlas)
    conc        = { iconPaths = { "Interface\\ICONS\\UI_Concentration" }, iconAtlases = { "Capacitance-General-32x32" }, iconFallback = "Interface\\Icons\\Spell_Nature_Manaregen" },
    -- Recharge / expiration: auctionhouse-icon-clock (Templates sort header)
    recharge    = { iconAtlases = { "auctionhouse-icon-clock", "Capacitance-General-WorkOrderArrow", "Capacitance-General-32x32" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\Spell_Nature_TimeStop" },
    -- Specialization knowledge sample ring (Specializations.xml); unspent badge alt
    knowledge   = { iconAtlases = { "QuestDaily", "icons_64x64_important", "spec-sampleabilityring" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Misc_Book_09" },
    -- Active recipe row overlay (RecipeList.xml)
    recipes     = { iconAtlases = { "Professions_Recipe_Active", "professions_recipes_abilitytab", "Professions_Recipe_Hover" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Misc_Book_09" },
    -- First-craft affordance (RecipeSchematicForm.xml)
    firstCraft  = { iconAtlases = { "professions_icon_firsttimecraft", "crafting-crafting-order-icon" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Scroll_04" },
    -- Unique craft star + favorite affordance (RecipeSchematicForm.xml)
    uniques     = { iconAtlases = { "tradeskills-star", "auctionhouse-icon-favorite" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Misc_Organizer_01" },
    treatise    = { iconPaths = { "Interface\\Icons\\INV_Inscription_Tradeskill01" } },
    weeklyQuest = { iconAtlases = { "questlog-questtypeicon-weekly", "questlog-questtypeicon-daily" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Scroll_03" },
    -- Treasure discovery reward chest (Templates / CrafterOrderView)
    treasure    = { iconAtlases = { "ui_icon_chest_npcreward", "worldquest-questmarker-rare" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Misc_TreasureMap" },
    gathering   = { iconAtlases = { "poi-gather", "Professions-Icon-Skill-Low" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Misc_Powder_Ardent" },
    -- Catch-up reagent affordance (RecipeReagentSlotBase.xml)
    catchUp     = { iconAtlases = { "tradeskills-icon-add", "XPBarAnim-OrangeSpark" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\XPBarAnim-OrangeSpark" },
    moxie       = { iconAtlases = { "currency-icon-moxie" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\INV_Misc_Coin_01" },
    cooldowns   = { iconAtlases = { "auctionhouse-icon-clock", "ui-hud-refreshbutton-icon", "Capacitance-General-WorkOrderArrow" }, iconIsAtlas = true, iconFallback = "Interface\\Icons\\Spell_Holy_GreaterHeal" },
}

local HEADER_DEFS = {
    { col = "open",        label = "PROF_OPEN_RECIPE",       text = ns.L and ns.L["PROF_OPEN_RECIPE"],          align = "CENTER", sortable = false },
    { col = "name",        label = "MONEY_LOGS_COLUMN_CHARACTER", text = ns.L and ns.L["MONEY_LOGS_COLUMN_CHARACTER"], align = "LEFT",   sortable = true },
    { col = "profName",    label = "GROUP_PROFESSION",       text = ns.L and ns.L["GROUP_PROFESSION"],    align = "LEFT",   sortable = true },
    { col = "equipment",   label = "EQUIPMENT",              text = ns.L and ns.L["EQUIPMENT"],     align = "CENTER", sortable = false },
    { col = "skill",       label = "SKILL",                  text = ns.L and ns.L["SKILL"],         align = "CENTER", sortable = true },
    { col = "conc",        label = "CONCENTRATION",          text = ns.L and ns.L["CONCENTRATION"], align = "CENTER", sortable = true },
    { col = "recharge",    label = "RECHARGE",               text = ns.L and ns.L["RECHARGE"],      align = "CENTER", sortable = true },
    { col = "knowledge",   label = "KNOWLEDGE",              text = ns.L and ns.L["KNOWLEDGE"],     align = "CENTER", sortable = true },
    { col = "recipes",     label = "RECIPES",                text = ns.L and ns.L["RECIPES"],       align = "CENTER", sortable = true },
    { col = "firstCraft",  label = "FIRST_CRAFT",            text = ns.L and ns.L["FIRSTCRAFT"],   align = "CENTER", sortable = true },
    { col = "uniques",     label = "UNIQUES",                text = ns.L and ns.L["UNIQUES"],       align = "CENTER", sortable = true },
    { col = "treatise",    label = "TREATISE",               text = ns.L and ns.L["TREATISE"],      align = "CENTER", sortable = true },
    { col = "weeklyQuest", label = "WEEKLY_QUEST_CAT",       text = ns.L and ns.L["QUEST_TYPE_WEEKLY"],  align = "CENTER", sortable = true },
    { col = "treasure",    label = "SOURCE_TYPE_TREASURE",   text = ns.L and ns.L["SOURCE_TYPE_TREASURE"],      align = "CENTER", sortable = true },
    { col = "gathering",   label = "GATHERING",              text = ns.L and ns.L["GATHERING"],     align = "CENTER", sortable = true },
    { col = "catchUp",     label = "CATCH_UP",               text = ns.L and ns.L["CATCH_UP"],      align = "CENTER", sortable = true },
    { col = "moxie",       label = "MOXIE",                  text = ns.L and ns.L["MOXIE"],         align = "CENTER", sortable = true },
    { col = "cooldowns",   label = "COOLDOWNS",              text = ns.L and ns.L["COOLDOWNS"],     align = "CENTER", sortable = true },
}

--============================================================================
-- COLUMN SORT STATE & COMPARATORS
-- Stored in db.profile.professionColumnSort = { col = "skill", dir = "asc"|"desc" }
--============================================================================

local function GetColumnSortState()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    return db and db.professionColumnSort
end

local function SetColumnSortState(col, dir)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return end
    if not col then
        WarbandNexus.db.profile.professionColumnSort = nil
    else
        WarbandNexus.db.profile.professionColumnSort = { col = col, dir = dir }
    end
end

ToggleColumnSort = function(col)
    local state = GetColumnSortState()
    if state and state.col == col then
        if state.dir == "asc" then
            SetColumnSortState(col, "desc")
        else
            SetColumnSortState(nil)
        end
    else
        SetColumnSortState(col, "asc")
    end
    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "professions", skipCooldown = true })
end

--============================================================================
-- CONCENTRATION BAR
--============================================================================

local BAR_HEIGHT = 16
local BAR_BORDER = 1

--- TOPLEFT Y for concentration bar so its vertical center matches profession line centerY.
local function ColBarTopY(centerY)
    return centerY + (BAR_HEIGHT / 2) - (ROW_HEIGHT / 2)
end

local function UpdateConcentrationBar(parent, barKey, xOffset, yOffset, barWidth, current, maximum)
    current = current or 0
    maximum = maximum or 0
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
        local cr, cg, cb, ca = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.22

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

local function InvalidateProfessionsTradeSessionCaches()
    wipe(profSessionIconBySkillLine)
    wipe(profSessionRecipeMapByCharKey)
end

local function RegisterProfessionEvents(parent)
    if parent.professionUpdateHandler then return end
    parent.professionUpdateHandler = true
    local Constants = ns.Constants

    local function Refresh()
        wipe(profSessionRecipeMapByCharKey)
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mf and mf:IsShown() and mf.currentTab == "professions" then
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "professions", skipCooldown = true })
        end
    end

    -- CONCENTRATION_UPDATED, KNOWLEDGE_UPDATED, RECIPE_DATA_UPDATED: REMOVED —
    -- UI.lua's SchedulePopulateContent already handles professions tab refresh for these events.
    -- Having both caused double PopulateContent → DrawProfessionsTab per event.
    
    -- Keep CHARACTER_UPDATED: UI.lua does not schedule professions-tab refresh for this event.
    WarbandNexus.RegisterMessage(ProfessionsUIEvents, Constants.EVENTS.CHARACTER_UPDATED, Refresh)
    -- CHARACTER_TRACKING_CHANGED refresh is centralized in UI.lua.
end

--============================================================================
-- CHARACTER SORTING (mirrors CharactersUI)
--============================================================================

local function SortCharacters(list, orderKey)
    if not WarbandNexus.db or not WarbandNexus.db.profile then
        table.sort(list, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return CompareCharNameLower(a, b)
        end)
        return list
    end
    
    local sortMode = WarbandNexus.db.profile.professionSort and WarbandNexus.db.profile.professionSort.key
    if sortMode and sortMode ~= "manual" then
        table.sort(list, function(a, b)
            if sortMode == "name" then
                return CompareCharNameLower(a, b)
            elseif sortMode == "level" then
                if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                return CompareCharNameLower(a, b)
            elseif sortMode == "ilvl" then
                if (a.itemLevel or 0) ~= (b.itemLevel or 0) then return (a.itemLevel or 0) > (b.itemLevel or 0) end
                return CompareCharNameLower(a, b)
            elseif sortMode == "gold" then
                local goldA = ns.Utilities:GetCharTotalCopper(a)
                local goldB = ns.Utilities:GetCharTotalCopper(b)
                if goldA ~= goldB then return goldA > goldB end
                return CompareCharNameLower(a, b)
            elseif sortMode == "realm" then
                local ra = SafeLower(a.realm or "")
                local rb = SafeLower(b.realm or "")
                if ra ~= rb then return ra < rb end
                return CompareCharNameLower(a, b)
            end
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return CompareCharNameLower(a, b)
        end)
        return list
    end

    if not WarbandNexus.db.profile.characterOrder then
        WarbandNexus.db.profile.characterOrder = { favorites = {}, regular = {}, untracked = {} }
    end
    local customOrder = WarbandNexus.db.profile.characterOrder[orderKey] or {}
    if #customOrder > 0 then
        local ordered, charMap = {}, {}
        for li = 1, #list do
            local c = list[li]
            charMap[GetCharKey(c)] = c
        end
        for coi = 1, #customOrder do
            local ck = customOrder[coi]
            if charMap[ck] then tinsert(ordered, charMap[ck]); charMap[ck] = nil end
        end
        local remaining = {}
        for _, c in pairs(charMap) do tinsert(remaining, c) end
        table.sort(remaining, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return CompareCharNameLower(a, b)
        end)
        for ri = 1, #remaining do tinsert(ordered, remaining[ri]) end
        return ordered
    else
        table.sort(list, function(a, b)
            if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
            return CompareCharNameLower(a, b)
        end)
        return list
    end
end

local function CategorizeCharacters(characters)
    local favorites, regular, untracked = {}, {}, {}
    local profile = WarbandNexus.db and WarbandNexus.db.profile
    if profile and ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
        ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
    end
    local sortKey = (profile and profile.characterSort and profile.characterSort.key) or "default"
    local customGroupsOrdered = (profile and ns.CharacterService and ns.CharacterService.BuildOrderedCustomCharacterGroups)
        and ns.CharacterService:BuildOrderedCustomCharacterGroups(profile, sortKey)
        or ((profile and profile.characterCustomGroups) or {})
    local assignments = (profile and profile.characterGroupAssignments) or {}
    local groupedById = {}
    for gi = 1, #customGroupsOrdered do
        groupedById[customGroupsOrdered[gi].id] = {}
    end
    for chi = 1, #characters do
        local char = characters[chi]
        local isTracked = char.isTracked ~= false
        local charKey = GetCharKey(char)
        if not isTracked then
            tinsert(untracked, char)
        elseif ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey) then
            tinsert(favorites, char)
        else
            local gid = nil
            if charKey and ns.CharacterService and ns.CharacterService.GetCharacterCustomSectionId then
                gid = ns.CharacterService:GetCharacterCustomSectionId(WarbandNexus, charKey)
            elseif charKey then
                gid = assignments[charKey]
            end
            if gid and groupedById[gid] then
                tinsert(groupedById[gid], char)
            else
                tinsert(regular, char)
            end
        end
    end
    return SortCharacters(favorites, "favorites"), groupedById, customGroupsOrdered, SortCharacters(regular, "regular"), SortCharacters(untracked, "untracked")
end

-- Realm display: use centralized Utilities:FormatRealmName
local function FormatRealmName(realm)
    if ns.Utilities and ns.Utilities.FormatRealmName then
        return ns.Utilities:FormatRealmName(realm)
    end
    if not realm or realm == "" then return "" end
    if issecretvalue and issecretvalue(realm) then return "" end
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
    if issecretvalue and issecretvalue(expansionName) then return false end
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
            -- Locale-safe fast path: Midnight skill lines are fixed IDs.
            if filter == "Midnight" then
                for exi = 1, #expansions do
                    local exp = expansions[exi]
                    if exp and exp.skillLineID and IsMidnightSkillLineID(exp.skillLineID) then
                        return exp.skillLineID
                    end
                end
            end
            for exi = 1, #expansions do
                local exp = expansions[exi]
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
        if filter == "Midnight" then
            for i = 1, #expansions do
                local exp = expansions[i]
                if exp and exp.skillLineID and IsMidnightSkillLineID(exp.skillLineID) then
                    return exp.skillLevel or 0, exp.maxSkillLevel or 0, exp.name
                end
            end
        end
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
    for exi = 1, #expansions do
        local exp = expansions[exi]
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

--- True when char.professions[1|2] has a learned primary profession (matches DrawProfessionLine / DataService).
local function CharacterHasPrimaryProfession(char)
    if not char or not char.professions then return false end
    for pi = 1, 2 do
        local prof = char.professions[pi]
        if prof then
            local nm = prof.name
            if nm and nm ~= "" then
                if issecretvalue and issecretvalue(nm) then
                    if prof.skillLine or prof.skillLineID then return true end
                else
                    return true
                end
            elseif prof.skillLine or prof.skillLineID then
                return true
            end
        end
    end
    return false
end

--- Count roster entries with saved primary profession slots (subtitle / empty-state hints).
local function CountCharsWithProfessionData(charLists)
    local n = 0
    if not charLists then return n end
    for li = 1, #charLists do
        local list = charLists[li]
        if list then
            for ci = 1, #list do
                if CharacterHasPrimaryProfession(list[ci]) then
                    n = n + 1
                end
            end
        end
    end
    return n
end

--- First-visit defaults: match Characters tab (Favorites + Characters open; Untracked closed).
local function EnsureProfessionsSectionExpandDefaults(profile)
    if not profile then return end
    if not profile.ui then profile.ui = {} end
    if profile.ui.profFavoritesExpanded == nil then
        profile.ui.profFavoritesExpanded = true
    end
    if profile.ui.profCharactersExpanded == nil then
        profile.ui.profCharactersExpanded = true
    end
    if profile.ui.profUntrackedExpanded == nil then
        profile.ui.profUntrackedExpanded = false
    end
end

--- First primary profession slot for OpenTradeSkill (skillLine / skillLineID from CollectProfessionData).
local function GetFirstPrimaryProfessionSlot(char)
    if not char or not char.professions then return nil end
    for pi = 1, 2 do
        local prof = char.professions[pi]
        if prof and (prof.skillLine or prof.skillLineID or prof.name) then
            return prof
        end
    end
    return nil
end

local function SetProfessionOpenButtonState(btn, enabled, tooltipTitle)
    if not btn then return end
    btn:Show()
    btn:EnableMouse(true)
    if btn.label then
        btn.label:SetText((ns.L and ns.L["PROF_OPEN_RECIPE"]) or "Open")
    end
    if enabled then
        btn:Enable()
        btn:SetAlpha(1)
        if btn.label then btn.label:SetTextColor(1, 1, 1) end
    else
        btn:Disable()
        btn:SetAlpha(0.45)
        if btn.label then btn.label:SetTextColor(0.55, 0.55, 0.58) end
    end
    local tipTitle = tooltipTitle or ((ns.L and ns.L["PROF_OPEN_RECIPE_TOOLTIP"]) or "Open recipe list")
    btn:SetScript("OnEnter", function(self)
        if ShowTooltip then ShowTooltip(self, { type = "custom", title = tipTitle, lines = {}, anchor = "ANCHOR_TOP" }) end
    end)
    btn:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
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
-- COLUMN SORT: FLAT LIST BUILDER & COMPARATOR
-- Placed after all helper functions to ensure GetExpansionFilter,
-- GetSkillLineIDForFilter, GetCurrentExpansionSkill are in scope.
--============================================================================

-- Extracts the best (max across both professions) sortable numeric value for a character.
local function GetCharSortValue(char, col)
    if col == "name" then return nil end

    local filter = GetExpansionFilter()
    local bestVal = -999999999
    local CONC_PER_SEC = 10 / 3600

    local PROGRESS_KEY_MAP = {
        firstCraft = "firstCraft", uniques = "uniques", treatise = "treatise",
        weeklyQuest = "weeklyQuest", treasure = "treasure", gathering = "gathering",
        catchUp = "catchUp",
    }

    for profIdx = 1, 2 do
        local prof = char.professions and char.professions[profIdx]
        local profName = prof and prof.name
        if profName then
            local val = -1
            local slID = GetSkillLineIDForFilter(char, profName)

            if col == "profName" then
                if issecretvalue and issecretvalue(profName) then
                    val = 0
                else
                    val = profName:lower():byte() or 0
                end
            elseif col == "skill" then
                local cs, ms = GetCurrentExpansionSkill(char, profName)
                cs = cs or 0; ms = ms or 0
                val = ms > 0 and (cs / ms) or -1
            elseif col == "conc" or col == "recharge" then
                local concData = slID and char.concentration and char.concentration[slID]
                if not concData and filter == "All" then
                    concData = char.concentration and char.concentration[profName]
                end
                if concData and concData.max and concData.max > 0 then
                    local est = concData.current or 0
                    if WarbandNexus.GetEstimatedConcentration then
                        local ok, v = pcall(WarbandNexus.GetEstimatedConcentration, WarbandNexus, concData)
                        if ok and type(v) == "number" then est = v end
                    end
                    if col == "conc" then
                        val = est / concData.max
                    elseif est >= concData.max then
                        val = 0
                    else
                        val = (concData.max - est) / CONC_PER_SEC
                    end
                else
                    val = col == "recharge" and 999999999 or -1
                end
            elseif col == "knowledge" then
                local kd = slID and char.knowledgeData and char.knowledgeData[slID]
                if not kd and filter == "All" then kd = char.knowledgeData and char.knowledgeData[profName] end
                if kd then
                    local cur = (kd.spentPoints or 0) + (kd.unspentPoints or 0)
                    local mx = kd.maxPoints or 0
                    val = mx > 0 and (cur / mx) or -1
                end
            elseif col == "moxie" then
                local charKey = GetCharKey(char)
                local moxieCurrencyID = slID and MIDNIGHT_MOXIE_CURRENCY[slID]
                if charKey and moxieCurrencyID and WarbandNexus.GetCurrencyData then
                    local moxieData = WarbandNexus:GetCurrencyData(moxieCurrencyID, charKey)
                    val = (moxieData and (moxieData.quantity or moxieData.value)) or 0
                end
            elseif col == "cooldowns" then
                local charKey = GetCharKey(char)
                if charKey and slID then
                    local charData = ns.db and ns.db.global and ns.db.global.characters and ns.db.global.characters[charKey]
                    local cdTable = charData and charData.professionCooldowns and charData.professionCooldowns[slID]
                    if cdTable then
                        local ready, total = 0, 0
                        local now = time()
                        for _, info in pairs(cdTable) do
                            total = total + 1
                            if (info.cooldownEnd or 0) <= now then ready = ready + 1 end
                        end
                        val = total > 0 and (ready / total) or -1
                    end
                end
            elseif col == "recipes" then
                local recipeData = slID and char.recipes and char.recipes[slID]
                if recipeData and (recipeData.totalCount or 0) > 0 then
                    val = (recipeData.knownCount or 0) / recipeData.totalCount
                end
            elseif PROGRESS_KEY_MAP[col] then
                local progressData = nil
                if slID and char.professionData and char.professionData.bySkillLine and char.professionData.bySkillLine[slID] then
                    progressData = char.professionData.bySkillLine[slID].weeklyKnowledge
                end
                if not progressData and slID and char.professionWeeklyKnowledge then
                    progressData = char.professionWeeklyKnowledge[slID]
                end
                local pd = progressData and progressData[PROGRESS_KEY_MAP[col]]
                if pd then
                    local cur = tonumber(pd.current or 0) or 0
                    local tot = tonumber(pd.total or 0) or 0
                    val = tot > 0 and (cur / tot) or -1
                end
            end

            bestVal = max(bestVal, val)
        end
    end

    return bestVal
end

-- Returns a character comparator for sorting within sections by column header.
-- pcall-protected so table.sort never aborts on data edge cases.
local function GetColumnSortCharComparator()
    local state = GetColumnSortState()
    if not state or not state.col then return nil end

    local col = state.col
    local isAsc = (state.dir == "asc")

    local function SafeCompare(a, b)
        if col == "name" then
            local nameA = SafeLower(a.name)
            local nameB = SafeLower(b.name)
            if nameA ~= nameB then
                if isAsc then return nameA < nameB else return nameA > nameB end
            end
            return false
        end

        local valA = (a._wnProfSortKey ~= nil) and a._wnProfSortKey or GetCharSortValue(a, col) or -999999999
        local valB = (b._wnProfSortKey ~= nil) and b._wnProfSortKey or GetCharSortValue(b, col) or -999999999

        if valA ~= valB then
            if isAsc then return valA < valB else return valA > valB end
        end
        if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
        return CompareCharNameLower(a, b)
    end

    return function(a, b)
        local ok, result = pcall(SafeCompare, a, b)
        if ok then return result end
        return false
    end
end

--============================================================================
-- DRAW TAB
--============================================================================

local PROF_STRETCH_RELAYOUT_OPTS = {
    rowsKey = "_wnProfNestedRows",
    rowHeight = ROW_HEIGHT,
    yOffsetKey = "_wnYOffset",
    sideMargin = 0,
}

local function ProfessionStretchRelayoutOpts(scrollChild)
    local opts = PROF_STRETCH_RELAYOUT_OPTS
    if scrollChild and scrollChild._wnProfSectionContents then
        opts = {
            rowsKey = PROF_STRETCH_RELAYOUT_OPTS.rowsKey,
            sections = scrollChild._wnProfSectionContents,
            rowHeight = PROF_STRETCH_RELAYOUT_OPTS.rowHeight,
            yOffsetKey = PROF_STRETCH_RELAYOUT_OPTS.yOffsetKey,
            sideMargin = PROF_STRETCH_RELAYOUT_OPTS.sideMargin,
        }
    end
    return opts
end

local function RefreshVisibleProfessionRowGradients(scrollChild)
    if scrollChild and scrollChild._wnProfNestedRows and ns.UI_RefreshRegisteredRowGradients then
        ns.UI_RefreshRegisteredRowGradients(scrollChild._wnProfNestedRows)
    end
end
ns.UI_RefreshProfessionRowGradients = RefreshVisibleProfessionRowGradients

local function RelayoutProfessionRowWidths(scrollChild)
    if not scrollChild then return end
    local bodyW = scrollChild._wnProfStackWidth or scrollChild._wnProfBodyWidth
    local rows = scrollChild._wnProfNestedRows
    if not rows then return end
    local rowH = ROW_HEIGHT
    local yKey = "_wnYOffset"
    for ri = 1, #rows do
        local row = rows[ri]
        if row and row:IsShown() then
            local rowParent = row:GetParent()
            if rowParent then
                local yOff = row[yKey] or 0
                row:ClearAllPoints()
                if rowH and row.SetHeight then
                    row:SetHeight(rowH)
                end
                row:SetPoint("TOPLEFT", rowParent, "TOPLEFT", 0, -yOff)
                if bodyW and bodyW > 0 then
                    row:SetWidth(bodyW)
                    row._wnRowPaintWidth = bodyW
                elseif rowParent.GetWidth then
                    local pw = rowParent:GetWidth()
                    if pw and pw > 0 then
                        row:SetWidth(pw)
                        row._wnRowPaintWidth = pw
                    end
                end
                if row.SetClipsChildren then
                    row:SetClipsChildren(false)
                end
                if row.bg and row.bg.SetAllPoints then
                    row.bg:SetAllPoints()
                end
                if row._wnGradientRefresh then
                    pcall(row._wnGradientRefresh)
                end
            end
        end
    end
    if scrollChild._wnProfSectionContents and ns.UI_RelayoutStretchSectionBodies then
        ns.UI_RelayoutStretchSectionBodies(scrollChild, ProfessionStretchRelayoutOpts(scrollChild))
    end
end
ns.UI_RelayoutProfessionRowWidths = RelayoutProfessionRowWidths

local function ResolveProfessionColumnHeaderInnerWidth(mf, scrollChild, bodyWidth)
    local w = tonumber(bodyWidth) or 0
    if mf and mf.scroll and mf.scroll.GetWidth then
        local sw = mf.scroll:GetWidth()
        if sw and sw > 1 then
            w = math.max(w, sw)
        end
    end
    if scrollChild and scrollChild.GetWidth then
        local scw = scrollChild:GetWidth()
        if scw and scw > 1 then
            w = math.max(w, scw)
        end
    end
    if ns.ComputeProfessionsGridWidth then
        w = math.max(w, ns.ComputeProfessionsGridWidth())
    end
    return math.max(1, w)
end

--- Inner stack width after symmetric tab side insets (header/sections anchor at contentSide).
local function ProfessionStackBodyWidth(scrollPaintW, contentSide)
    local side = contentSide or SIDE_MARGIN
    return math.max(1, (tonumber(scrollPaintW) or 1) - 2 * side)
end

local function EnsureProfessionColumnHeaderStrip(mf, scrollChild, bodyWidth)
    if not mf or not scrollChild then return end
    local clip = mf.columnHeaderClip
    if clip then
        clip:SetHeight(1)
        clip:Hide()
    end
    local colHeaderRow = scrollChild._wnProfColHeaderRow
    if not colHeaderRow then return end
    ReattachProfessionColumnHeaderBar(colHeaderRow, scrollChild)
    local stackW = bodyWidth or scrollChild._wnProfStackWidth or scrollChild._wnProfBodyWidth
    local side = scrollChild._wnProfContentSide or SIDE_MARGIN
    local paintW = ResolveProfessionColumnHeaderInnerWidth(mf, scrollChild, stackW)
    local barW = ProfessionStackBodyWidth(paintW, side)
    local scrollTopY = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
    colHeaderRow:ClearAllPoints()
    colHeaderRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", side, -scrollTopY)
    if colHeaderRow.SetWidth then
        colHeaderRow:SetWidth(math.max(1, barW))
    end
end

--- Live viewport resize: stretch rows + gradients only (no PopulateContent mid-drag).
local function ProfessionsBodyWidthFromViewport(contentWidth, scrollChild)
    local side = (scrollChild and scrollChild._wnProfContentSide)
        or (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin())
        or SIDE_MARGIN
    if contentWidth and contentWidth > 0 then
        return math.max(200, contentWidth - side * 2)
    end
    return nil
end

local function ScheduleProfessionViewportRelayout(mf, scrollChild, contentWidth)
    if not mf or mf.currentTab ~= "professions" or not scrollChild then return end
    local bodyW = ProfessionsBodyWidthFromViewport(contentWidth, scrollChild)
    local paintW
    if bodyW and bodyW > 0 then
        cachedRowWidth = bodyW
        scrollChild._wnProfBodyWidth = bodyW
        paintW = ResolveProfessionColumnHeaderInnerWidth(mf, scrollChild, bodyW)
        local side = scrollChild._wnProfContentSide or SIDE_MARGIN
        scrollChild._wnProfStackWidth = ProfessionStackBodyWidth(paintW, side)
    elseif mf and ns.UI_GetMainTabViewportWidth then
        local vp = ns.UI_GetMainTabViewportWidth(mf)
        if vp and vp > 0 then
            cachedRowWidth = vp
            paintW = ResolveProfessionColumnHeaderInnerWidth(mf, scrollChild, vp)
            local side = scrollChild._wnProfContentSide or SIDE_MARGIN
            scrollChild._wnProfStackWidth = ProfessionStackBodyWidth(paintW, side)
        end
    end
    EnsureProfessionColumnHeaderStrip(mf, scrollChild, bodyW)
    RelayoutProfessionRowWidths(scrollChild)
    if scrollChild._wnProfRelayoutSectionStack then
        scrollChild._wnProfRelayoutSectionStack()
    end
end

local function DebounceProfessionRowGradientRefresh(mf)
    if not mf or mf.currentTab ~= "professions" then return end
    local sc = mf.scrollChild
    if not sc then return end
    if sc._wnProfGradScrollTimer then
        sc._wnProfGradScrollTimer:Cancel()
    end
    if C_Timer and C_Timer.After then
        sc._wnProfGradScrollTimer = C_Timer.After(0.05, function()
            sc._wnProfGradScrollTimer = nil
            if mf.currentTab == "professions" then
                RelayoutProfessionRowWidths(sc)
                RefreshVisibleProfessionRowGradients(sc)
            end
        end)
    else
        RefreshVisibleProfessionRowGradients(sc)
    end
end

local function EnsureProfessionRowGradientScrollHook(mf)
    if not mf or not mf.scroll or mf.scroll._wnProfGradScrollHook then return end
    mf.scroll._wnProfGradScrollHook = true
    -- ScrollFrame exposes OnVerticalScroll, not OnScroll (see UI.lua main scroll setup).
    local ok = pcall(function()
        mf.scroll:HookScript("OnVerticalScroll", function()
            DebounceProfessionRowGradientRefresh(mf)
        end)
    end)
    if not ok and IsDebugModeEnabled and IsDebugModeEnabled() then
        DebugPrint("|cffff9900[ProfessionsUI]|r OnVerticalScroll hook skipped for gradient refresh")
    end
end

ns.UI_DebounceProfessionRowGradientRefresh = DebounceProfessionRowGradientRefresh

function WarbandNexus:DrawProfessionsTab(parent)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    profEquipResolveCache = {}
    SyncProfessionColumnOrder(WarbandNexus.db and WarbandNexus.db.profile)

    RegisterProfessionEvents(parent)
    HideEmptyStateCard(parent, "professions")
    -- PopulateContent already released pooled rows on full-tab renders; skip duplicate walk (heavy tab switch).
    if not parent._preparedByPopulate and ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(parent)
    end
    if parent._wnProfNestedRows and ReleaseProfessionRow then
        for i = 1, #parent._wnProfNestedRows do
            local row = parent._wnProfNestedRows[i]
            if row and row.rowType == "profession" then
                ReleaseProfessionRow(row)
            end
        end
    end
    parent._wnProfNestedRows = {}
    parent._wnProfSectionContents = {}
      -- fixedHeader: title card only; column headers live in scrollChild (PvE parity)
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local metrics = (chrome and chrome.metrics) or (ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf))
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or 0
    local contentSide = (chrome and chrome.side) or (metrics and metrics.sideMargin) or SIDE_MARGIN
    local scrollTopY = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
  -- Single stack width for title card, column headers, sections, and row chrome (Characters-tab parity).
    local stackWidth = (metrics and metrics.bodyWidth and metrics.bodyWidth > 0) and metrics.bodyWidth
        or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
        or math.max(200, ((mf and mf.scroll and mf.scroll:GetWidth()) or 600) - contentSide * 2)
    cachedRowWidth = stackWidth
    parent._wnProfBodyWidth = stackWidth
    parent._wnProfContentSide = contentSide

    -- If module is disabled, show disabled state card
    if not ns.Utilities:IsModuleEnabled("professions") then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, scrollTopY, (ns.L and ns.L["PROFESSIONS_DISABLED_TITLE"]) or "Professions")
        return scrollTopY + cardHeight
    end

    local characters = self:GetAllCharacters()
    local trackedFavorites, groupedById, customGroupsOrdered, trackedRegular, untrackedChars = CategorizeCharacters(characters)
    EnsureProfessionsSectionExpandDefaults(self.db.profile)
    local totalProfChars = #trackedFavorites + #trackedRegular + #untrackedChars
    local charListsForProfCount = { trackedFavorites, trackedRegular, untrackedChars }
    for gci = 1, #customGroupsOrdered do
        local gl = groupedById[customGroupsOrdered[gci].id]
        if gl then
            totalProfChars = totalProfChars + #gl
            charListsForProfCount[#charListsForProfCount + 1] = gl
        end
    end
    local profDataCharCount = CountCharsWithProfessionData(charListsForProfCount)

    local expBadgeWidth = 100
    local filterBtnW = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_WIDTH_DEFAULT) or 80
    local btnHH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local tm = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local hdrGapEc = tm.gap or (GetLayout().HEADER_TOOLBAR_CONTROL_GAP) or 8
    local profToolbarReserve = (ns.UI_ComputeTitleToolbarReserve and ns.UI_ComputeTitleToolbarReserve({
        expBadgeWidth,
        filterBtnW,
        tm.filterW or 96,
    })) or (expBadgeWidth + filterBtnW + 40 + hdrGapEc)

    -- ===== TITLE CARD (in fixedHeader - non-scrolling) — tracked roster vs saved profession rows =====
    local subLine = format(
        (ns.L and ns.L["PROFESSIONS_TRACKED_FORMAT"]) or "%s tracked - %s with profession data",
        FormatNumber(totalProfChars),
        FormatNumber(profDataCharCount)
    )
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "professions",
        titleText = "|cff" .. GetAccentHexColor() .. ((ns.L and ns.L["YOUR_PROFESSIONS"]) or "Warband Professions") .. "|r",
        subtitleText = subLine,
        textRightInset = profToolbarReserve,
    }))
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end

    -- Force fixed expansion view: Midnight only (filter selector removed).
    self.db.profile.professionExpansionFilter = "Midnight"
    local expBadgeHeight = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local expBadge = ns.UI.Factory:CreateButton(titleCard, expBadgeWidth, expBadgeHeight, false)
    if ApplyVisuals then
        ApplyVisuals(expBadge, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    local expBadgeText = FontManager:CreateFontString(expBadge, "body", "OVERLAY")
    expBadgeText:SetPoint("CENTER", 0, 0)
    expBadgeText:SetJustifyH("CENTER")
    expBadgeText:SetText((ns.L and ns.L["CONTENT_MIDNIGHT"]) or "Midnight")
    expBadgeText:SetTextColor(0.9, 0.9, 0.9)
    expBadge:SetScript("OnClick", nil)
    expBadge:SetScript("OnEnter", nil)
    expBadge:SetScript("OnLeave", nil)
    local titleEdgeInset = tm.edgeInset or 0
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(expBadge, titleCard, titleCard, "RIGHT", -titleEdgeInset)
    else
        expBadge:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
    end
    
    -- ===== COLUMNS BUTTON (column visibility toggle) =====
    local filterBtnH = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local filterBtn = ns.UI.Factory:CreateButton(titleCard, filterBtnW, filterBtnH, false)
    if ApplyVisuals then
        ApplyVisuals(filterBtn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    local filterBtnText = FontManager:CreateFontString(filterBtn, "body", "OVERLAY")
    filterBtnText:SetPoint("CENTER", 0, 0)
    filterBtnText:SetJustifyH("CENTER")
    filterBtnText:SetText((ns.L and ns.L["COLUMNS_BUTTON"]) or "Columns")
    filterBtnText:SetTextColor(0.9, 0.9, 0.9)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(filterBtn) end
    local hdrGap = tm.gap or (GetLayout().HEADER_TOOLBAR_CONTROL_GAP) or 8
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(filterBtn, titleCard, expBadge, "LEFT", -hdrGap)
    else
        filterBtn:SetPoint("RIGHT", expBadge, "LEFT", -hdrGap, 0)
    end

    filterBtn:SetScript("OnClick", function(btn)
        local menu = WarbandNexus._wnProfColumnPickerMenu
        if menu and menu:IsShown() and WarbandNexus._wnProfColumnPickerAnchorBtn == btn then
            menu:Hide()
            return
        end
        if not WarbandNexus.ShowProfessionColumnPicker then return end
        WarbandNexus:ShowProfessionColumnPicker(btn)
    end)

    if WarbandNexus._wnProfColumnPickerMenu and WarbandNexus._wnProfColumnPickerMenu:IsShown() then
        WarbandNexus._wnProfColumnPickerAnchorBtn = filterBtn
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                local picker = WarbandNexus._wnProfColumnPickerMenu
                local anchor = WarbandNexus._wnProfColumnPickerAnchorBtn
                local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
                if not picker or not anchor or not mf or mf.currentTab ~= "professions" then
                    ProfColumnPickerHide()
                    return
                end
                ProfColumnPickerPopulateMenu(picker, anchor)
                ProfColumnPickerPositionMenu(picker, anchor)
                picker:Show()
                ProfColumnPickerShowCatcher(picker)
            end)
        end
    end

    local sortBtn
    if ns.UI_CreateCharacterTabAdvancedFilterButton then
        if ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        end
        local sortOptions = {
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
            {key = "realm", label = (ns.L and ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
        }
        if not self.db.profile.professionSort then self.db.profile.professionSort = {} end
        if not self.db.profile.professionSectionFilter then self.db.profile.professionSectionFilter = { sectionKey = "all" } end
        sortBtn = ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.professionSort,
            dbSectionFilter = self.db.profile.professionSectionFilter,
            getCustomSections = function()
                return self.db.profile.characterCustomGroups or {}
            end,
            onRefresh = function()
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
            end,
            onDeleteSection = function(groupId, groupName)
                WarbandNexus:ConfirmDeleteCustomCharacterHeader(groupId, groupName)
            end,
        })
        if sortBtn then
            if ns.UI_AnchorTitleCardToolbarControl then
                ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, filterBtn, "LEFT", -hdrGap)
            else
                sortBtn:SetPoint("RIGHT", filterBtn, "LEFT", -hdrGap, 0)
            end
        end
    elseif ns.UI_CreateCharacterSortDropdown then
        local sortOptions = {
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
            {key = "realm", label = (ns.L and ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
        }
        if not self.db.profile.professionSort then self.db.profile.professionSort = {} end
        sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.professionSort, function()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, filterBtn, "LEFT", -hdrGap)
        else
            sortBtn:SetPoint("RIGHT", filterBtn, "LEFT", -hdrGap, 0)
        end
    end

    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    -- ===== COLUMN HEADER ROW (scrollChild — PvE parity; crest/icons sit directly above sections) =====
    local mainFrameRef = WarbandNexus.UI.mainFrame
    local columnHeaderClip = mainFrameRef and mainFrameRef.columnHeaderClip
    if columnHeaderClip then
        columnHeaderClip:SetHeight(1)
        columnHeaderClip:Hide()
    end

    local colHeaderInnerW = ResolveProfessionColumnHeaderInnerWidth(mainFrameRef, parent, stackWidth)
    local profPaintW = colHeaderInnerW
    local profStackW = ProfessionStackBodyWidth(profPaintW, contentSide)
    parent._wnProfStackWidth = profStackW
    parent:SetWidth(math.max(1, profPaintW))
    if mainFrameRef then
        mainFrameRef._profMinScrollWidth = profPaintW
    end
    parent._wnProfColHeaderStripH = COLUMN_HEADER_HEIGHT + COLUMN_HEADER_PAD

    local FactHdr = ns.UI and ns.UI.Factory
    local colHeaderBar = parent._wnProfColHeaderRow
    if not colHeaderBar then
        colHeaderBar = FactHdr and FactHdr:CreateContainer(parent, profStackW, COLUMN_HEADER_HEIGHT, false)
        if not colHeaderBar then
            colHeaderBar = CreateFrame("Frame", nil, parent)
            colHeaderBar:SetSize(profStackW, COLUMN_HEADER_HEIGHT)
        end
        parent._wnProfColHeaderRow = colHeaderBar
    end
    ReattachProfessionColumnHeaderBar(colHeaderBar, parent)
    colHeaderBar:Show()
    colHeaderBar:SetHeight(COLUMN_HEADER_HEIGHT)
    colHeaderBar:ClearAllPoints()
    colHeaderBar:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -scrollTopY)
    if colHeaderBar.SetWidth then
        colHeaderBar:SetWidth(math.max(1, profStackW))
    end

    local accentR = COLORS.accent[1] or 0.40
    local accentG = COLORS.accent[2] or 0.20
    local accentB = COLORS.accent[3] or 0.58
    if colHeaderBar._wnProfColHeaderLine then
        colHeaderBar._wnProfColHeaderLine:Hide()
    end

    for _, fs in pairs(profColHeaderLabels) do
        if fs and fs.Hide then fs:Hide() end
    end
    for colKey, hit in pairs(profColHeaderHits) do
        if hit and hit.Hide then hit:Hide() end
    end

    local SORT_ARROW_SIZE = 11
    local sortState = GetColumnSortState()
    for hdi = 1, #HEADER_DEFS do
        local hdef = HEADER_DEFS[hdi]
        local col = hdef.col
        if IsColumnVisible(col) then
            local w = (hdef.getWidth and hdef.getWidth()) or ColWidth(col)
            local displayText = StripProfHeaderDisplayText(
                (hdef.label and ns.L and ns.L[hdef.label]) or hdef.text or ""
            )
            if col == "profName" and displayText == "" then
                displayText = StripProfHeaderDisplayText((ns.L and ns.L["GROUP_PROFESSION"]) or "Profession")
            end
            if col == "open" then
                -- Per-row Open button only; no header label (avoids "Open" text beside Character sort arrow).
            elseif PROF_HEADER_ICON_BY_COL[col] then
                PaintProfessionCompactColumnHeader(
                    colHeaderBar, col, w, PROF_HEADER_ICON_BY_COL[col], hdef, sortState, displayText,
                    accentR, accentG, accentB, FactHdr
                )
            else
            local isSorted = sortState and sortState.col == col

            if hdef.sortable then
                local hitBtn
                if FactHdr and FactHdr.CreateButton then
                    hitBtn = FactHdr:CreateButton(colHeaderBar, w, COLUMN_HEADER_HEIGHT, true)
                end
                if not hitBtn then
                    hitBtn = CreateFrame("Button", nil, colHeaderBar)
                    hitBtn:SetSize(w, COLUMN_HEADER_HEIGHT)
                end
                if (hdef.align or "CENTER") == "CENTER" then
                    hitBtn:SetPoint("CENTER", colHeaderBar, "LEFT", ColCenterX(col), 0)
                else
                    hitBtn:SetPoint("LEFT", colHeaderBar, "LEFT", ColOffset(col), 0)
                end
                hitBtn:SetFrameLevel(colHeaderBar:GetFrameLevel() + 1)

                -- Keep the sort arrow inside this column so it cannot sit in the gap left of "Character" (reads as "Open I").
                local arrow = hitBtn:CreateTexture(nil, "OVERLAY")
                arrow:SetSize(SORT_ARROW_SIZE, SORT_ARROW_SIZE)
                arrow:SetPoint("RIGHT", hitBtn, "RIGHT", -1, 0)
                if isSorted then
                    if sortState.dir == "asc" then
                        arrow:SetAtlas("hud-MainMenuBar-arrowup")
                    else
                        arrow:SetAtlas("hud-MainMenuBar-arrowdown")
                    end
                    arrow:SetVertexColor(accentR, accentG, accentB, 1)
                    arrow:Show()
                else
                    arrow:Hide()
                end

                local lbl = FontManager:CreateFontString(hitBtn, PROF_COLUMN_HEADER_FONT, "OVERLAY")
                ApplyProfColumnHeaderLabel(lbl, displayText, false)
                lbl:SetJustifyH(hdef.align or "CENTER")
                if lbl.SetJustifyV then lbl:SetJustifyV("MIDDLE") end
                lbl:SetPoint("LEFT", hitBtn, "LEFT", 2, 0)
                lbl:SetPoint("RIGHT", hitBtn, "RIGHT", -2, 0)

                local function SetHeaderLabelArrowInset(showArrow)
                    lbl:ClearAllPoints()
                    lbl:SetPoint("LEFT", hitBtn, "LEFT", 2, 0)
                    local rightPad = showArrow and -(SORT_ARROW_SIZE + 4) or -2
                    lbl:SetPoint("RIGHT", hitBtn, "RIGHT", rightPad, 0)
                end
                SetHeaderLabelArrowInset(isSorted)

                local capturedCol = col
                hitBtn:SetScript("OnClick", function()
                    ToggleColumnSort(capturedCol)
                end)
                hitBtn:SetScript("OnEnter", function()
                    ApplyProfColumnHeaderLabel(lbl, displayText, true)
                    SetHeaderLabelArrowInset(true)
                    if ShowTooltip and displayText ~= "" then
                        ShowTooltip(hitBtn, { type = "custom", title = displayText, lines = {}, anchor = "ANCHOR_TOP" })
                    end
                    if not isSorted then
                        arrow:SetAtlas("hud-MainMenuBar-arrowup")
                        arrow:SetVertexColor(1, 1, 1, 0.4)
                        arrow:Show()
                    end
                end)
                hitBtn:SetScript("OnLeave", function()
                    ApplyProfColumnHeaderLabel(lbl, displayText, false)
                    SetHeaderLabelArrowInset(isSorted)
                    if HideTooltip then HideTooltip() end
                    if not isSorted then
                        arrow:Hide()
                    end
                end)
            else
                -- Clip so header text cannot draw into the fav/class gap (often misread as "Open I" next to sort arrows).
                local clip = FactHdr and FactHdr:CreateContainer(colHeaderBar, w, COLUMN_HEADER_HEIGHT, false)
                if not clip then
                    clip = CreateFrame("Frame", nil, colHeaderBar)
                    clip:SetSize(w, COLUMN_HEADER_HEIGHT)
                end
                if (hdef.align or "CENTER") == "CENTER" then
                    clip:SetPoint("CENTER", colHeaderBar, "LEFT", ColCenterX(col), 0)
                else
                    clip:SetPoint("TOPLEFT", colHeaderBar, "TOPLEFT", ColOffset(col), 0)
                end
                clip:SetClipsChildren(true)
                local lbl = FontManager:CreateFontString(clip, PROF_COLUMN_HEADER_FONT, "OVERLAY")
                ApplyProfColumnHeaderLabel(lbl, displayText, false)
                lbl:SetJustifyH(hdef.align or "CENTER")
                if lbl.SetJustifyV then lbl:SetJustifyV("MIDDLE") end
                lbl:SetPoint("TOPLEFT", clip, "TOPLEFT", 1, 0)
                lbl:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", -1, 0)
                BindProfColumnHeaderTooltip(clip, displayText)
            end
            end
        end
    end
    ApplyProfessionColumnDividers(colHeaderBar, COLUMN_HEADER_HEIGHT)
    colHeaderBar:Show()

    local yOffset = scrollTopY + COLUMN_HEADER_HEIGHT + COLUMN_HEADER_PAD

    -- ===== EMPTY STATE =====
    if totalProfChars == 0 then
        local emptyText = FontManager:CreateFontString(parent, DATA_FONT, "OVERLAY")
        emptyText:SetPoint("TOPLEFT", contentSide + 20, -yOffset - 30)
        emptyText:SetWidth(stackWidth - 40)
        emptyText:SetJustifyH("CENTER")
        emptyText:SetText("|cffffffff" .. ((ns.L and ns.L["NO_PROFESSIONS_DATA"]) or "No profession data available yet. Open your profession window (default: K) on each character to collect data.") .. "|r")
        return yOffset + 100
    end

    -- ===== SECTION HEADERS & CHARACTER ROWS =====
    local currentPlayerKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(WarbandNexus))
        or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus))
        or ns.Utilities:GetCharacterKey()
    local rowIndex = 0
    local SECTION_COLLAPSE_HEADER_HEIGHT = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36

    self.profRecentlyExpanded = self.profRecentlyExpanded or {}

    -- Column sort: precompute numeric keys once per list (table.sort calls comparator O(n log n) times;
    -- GetCharSortValue does concentration estimates + currency + cooldown scans per call).
    local sortStateForKeys = GetColumnSortState()
    local colForKeys = sortStateForKeys and sortStateForKeys.col
    local function attachProfSortKeys(list)
        if not list or not colForKeys or colForKeys == "name" then return end
        for i = 1, #list do
            list[i]._wnProfSortKey = GetCharSortValue(list[i], colForKeys)
        end
    end
    local function clearProfSortKeys(list)
        if not list then return end
        for i = 1, #list do
            list[i]._wnProfSortKey = nil
        end
    end

    local colSortCmp = GetColumnSortCharComparator()
    if colSortCmp and colForKeys and colForKeys ~= "name" then
        attachProfSortKeys(trackedFavorites)
        for gci = 1, #customGroupsOrdered do
            local gl = groupedById[customGroupsOrdered[gci].id]
            attachProfSortKeys(gl)
        end
        attachProfSortKeys(trackedRegular)
        attachProfSortKeys(untrackedChars)
    end
    if colSortCmp then
        table.sort(trackedFavorites, colSortCmp)
        for gci = 1, #customGroupsOrdered do
            local gl = groupedById[customGroupsOrdered[gci].id]
            if gl then table.sort(gl, colSortCmp) end
        end
        table.sort(trackedRegular, colSortCmp)
        table.sort(untrackedChars, colSortCmp)
    end
    if colSortCmp and colForKeys and colForKeys ~= "name" then
        clearProfSortKeys(trackedFavorites)
        for gci = 1, #customGroupsOrdered do
            local gl = groupedById[customGroupsOrdered[gci].id]
            clearProfSortKeys(gl)
        end
        clearProfSortKeys(trackedRegular)
        clearProfSortKeys(untrackedChars)
    end

    -- Grouped sections with collapsible headers (Characters-tab stack: header chain respects collapsed body height)
    local SECTION_HEADER_GAP = 6
    local previousSectionContent = nil
    local previousSectionHeader = nil
    local previousSectionExpanded = false
    local isFirstSection = true
    local sectionRows = parent._wnProfNestedRows
    parent._wnProfSectionHeaders = {}
    parent._wnProfSectionStack = {}
    parent._wnProfSectionStackTopY = yOffset
    parent:SetHeight(1)

    local function SectionExpandedNow(sectionKey, defaultExpanded, visualOpts)
        if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
            local gid = visualOpts.groupId
            local ge = self.db.profile.characterGroupExpanded
            if ge and ge[gid] ~= nil then
                return ge[gid] == true
            end
            return defaultExpanded == true
        end
        local ui = self.db.profile.ui
        if ui and ui[sectionKey] ~= nil then
            return ui[sectionKey] == true
        end
        return defaultExpanded == true
    end

    local function RelayoutProfessionsSectionStack()
        local stack = parent._wnProfSectionStack
        if not stack or #stack == 0 then return end
        local w = parent._wnProfStackWidth or stackWidth
        local side = parent._wnProfContentSide or contentSide
        local y = parent._wnProfSectionStackTopY or 0
        local prevHeader, prevContent, prevExpanded
        for si = 1, #stack do
            local entry = stack[si]
            local header = entry.header
            local content = entry.content
            if not header or not content then
                break
            end
            local expanded = SectionExpandedNow(entry.sectionKey, entry.defaultExpanded, entry.visualOpts)
            header:ClearAllPoints()
            header:SetHeight(SECTION_COLLAPSE_HEADER_HEIGHT)
            if header.SetWidth then
                header:SetWidth(math.max(1, w))
            end
            if si == 1 then
                header:SetPoint("TOPLEFT", parent, "TOPLEFT", side, -y)
            elseif prevExpanded and prevContent then
                header:SetPoint("TOPLEFT", prevContent, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
            elseif prevHeader then
                header:SetPoint("TOPLEFT", prevHeader, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
            end
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            content:SetWidth(w)
            local bodyH = math.max(0.1, content._wnSectionFullH or 0.1)
            if expanded then
                content:SetHeight(bodyH)
                content:Show()
            else
                content:SetHeight(0.1)
                content:Hide()
            end
            y = y + SECTION_COLLAPSE_HEADER_HEIGHT + (expanded and bodyH or 0) + SECTION_HEADER_GAP
            prevHeader = header
            prevContent = content
            prevExpanded = expanded
        end
        local mfRef = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mfRef and ns.UI_SyncMainTabScrollChrome then
            ns.UI_SyncMainTabScrollChrome(mfRef, parent, y)
        end
    end
    parent._wnProfRelayoutSectionStack = RelayoutProfessionsSectionStack

    local function AcquireSectionContentFrame(anchorHeader)
        local contentFrame = CreateFrame("Frame", nil, parent)
        contentFrame:SetHeight(0.1)
        if contentFrame.SetClipsChildren then
            contentFrame:SetClipsChildren(false)
        end
        contentFrame._wnAnchorHeader = anchorHeader
        contentFrame._wnSectionFullH = 0
        contentFrame:ClearAllPoints()
        contentFrame:SetPoint("TOPLEFT", anchorHeader, "BOTTOMLEFT", 0, 0)
        contentFrame:SetWidth(profStackW)
        tinsert(parent._wnProfSectionContents, contentFrame)
        return contentFrame
    end

    local function AnchorSectionHeader(headerFrame)
        headerFrame:SetHeight(SECTION_COLLAPSE_HEADER_HEIGHT)
        if headerFrame.SetWidth then
            headerFrame:SetWidth(math.max(1, profStackW))
        end
        if isFirstSection then
            headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
            isFirstSection = false
        elseif previousSectionExpanded and previousSectionContent then
            headerFrame:SetPoint("TOPLEFT", previousSectionContent, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
        elseif previousSectionHeader then
            headerFrame:SetPoint("TOPLEFT", previousSectionHeader, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
        else
            headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
        end
    end

    local function DrawSection(chars, headerLabel, sectionKey, defaultExpanded, headerAtlas, visualOpts)
        if #chars == 0 and not (visualOpts and visualOpts.forceWhenEmpty) then return end

        local isExpanded
        if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
            local gid = visualOpts.groupId
            if not self.db.profile.characterGroupExpanded then self.db.profile.characterGroupExpanded = {} end
            isExpanded = self.db.profile.characterGroupExpanded[gid]
            if isExpanded == nil then isExpanded = defaultExpanded end
        else
            isExpanded = self.db.profile.ui[sectionKey]
            if isExpanded == nil then isExpanded = defaultExpanded end
        end

        local sectionContent
        local headerVisualOpts = BuildCollapsibleSectionOpts({
            bodyGetter = function() return sectionContent end,
            hideOnCollapse = true,
            showOnExpand = true,
            persistFn = function(exp)
                if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
                    local gid = visualOpts.groupId
                    if not self.db.profile.characterGroupExpanded then self.db.profile.characterGroupExpanded = {} end
                    self.db.profile.characterGroupExpanded[gid] = exp
                    if exp then self.profRecentlyExpanded["cgrp_" .. tostring(gid)] = GetTime() end
                else
                    self.db.profile.ui[sectionKey] = exp
                    if exp then self.profRecentlyExpanded[sectionKey] = GetTime() end
                end
            end,
        }) or {}
        if visualOpts and visualOpts.sectionPreset then
            headerVisualOpts.sectionPreset = visualOpts.sectionPreset
        end
        headerVisualOpts.useFullParentWidth = true
        headerVisualOpts.sectionStackWidth = profStackW

        local header, headerExpandIcon, hdrIcon, headerText = CreateCollapsibleHeader(
            parent,
            headerLabel,
            sectionKey,
            isExpanded,
            function(_expanded)
                RelayoutProfessionsSectionStack()
            end,
            headerAtlas,
            true,  -- isAtlas
            nil,
            nil,
            headerVisualOpts
        )
        -- Match Characters tab icon sizing exactly:
        --   Favorites          (gold preset, NO useCharacterGroupExpand) -> 28x28
        --   Custom roster      (useCharacterGroupExpand + groupId)        -> 24x24
        --   Regular / Untracked (default / "danger")                      -> 24x24
        local isCustomRosterSectionForIcon = visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId
        local isFavoritesSectionForIcon = visualOpts and visualOpts.sectionPreset == "gold" and not isCustomRosterSectionForIcon
        if hdrIcon then
            local sz = isFavoritesSectionForIcon and 28 or 24
            hdrIcon:SetSize(sz, sz)
        end
        header:SetHeight(SECTION_COLLAPSE_HEADER_HEIGHT)
        AnchorSectionHeader(header)

        local isCustomRosterSection = visualOpts and visualOpts.groupId
        local profSectionCount
        if not isCustomRosterSection then
            -- Non-custom sections (Favorites / Characters / Untracked) keep the simple count badge.
            local countHex = ((visualOpts and visualOpts.sectionPreset == "danger") and "|cff888888") or "|cffaaaaaa"
            if not header._wnProfSectionCount then
                header._wnProfSectionCount = FontManager:CreateFontString(header, "header", "OVERLAY")
            end
            profSectionCount = header._wnProfSectionCount
            profSectionCount:SetJustifyH("RIGHT")
            profSectionCount:SetText(countHex .. FormatNumber(#chars) .. "|r")
            profSectionCount:Show()
        elseif header._wnProfSectionCount then
            -- Hide legacy per-tab count so the unified helper's count is the only badge shown.
            header._wnProfSectionCount:Hide()
        end

        sectionContent = AcquireSectionContentFrame(header)
        sectionContent._wnProfRunningYOffset = 0
        local sectionYOffset = 0
        if isExpanded then
            if not parent._wnProfChunkQueue then
                parent._wnProfChunkQueue = {}
            end
            for chi = 1, #chars do
                tinsert(parent._wnProfChunkQueue, {
                    char = chars[chi],
                    sectionContent = sectionContent,
                })
            end
            sectionContent._wnSectionFullH = 0.1
            sectionContent:SetHeight(0.1)
            sectionContent:Show()
            sectionYOffset = 0.1
        else
            sectionContent._wnSectionFullH = 0.1
            sectionContent:SetHeight(0.1)
            sectionContent:Hide()
        end

        if isCustomRosterSection and ns.UI_DecorateCustomHeader then
            -- Unified Custom Header chrome (count + gold star). No [+] button in Professions tab.
            -- Layout: [chevron] [icon] [gold-star] [title] ........ [count]
            ns.UI_DecorateCustomHeader(header, {
                groupId = visualOpts.groupId,
                memberCount = #chars,
                addon = WarbandNexus,
                profile = self.db.profile,
                expandIcon = headerExpandIcon,
                iconFrame = hdrIcon,
                headerText = headerText,
                includeAddButton = false,
                refreshTab = "professions",
                allowSectionHighlightToggle = false,
            })
        elseif profSectionCount then
            -- Non-custom sections (Favorites / Characters / Untracked): simple right-anchored count
            -- badge. Match Characters tab pattern exactly: only count is anchored to RIGHT,-14,0;
            -- headerText keeps its original LEFT-only anchor (no RIGHT constraint).
            profSectionCount:ClearAllPoints()
            profSectionCount:SetPoint("RIGHT", header, "RIGHT", -14, 0)
        end

        tinsert(parent._wnProfSectionHeaders, header)
        tinsert(parent._wnProfSectionStack, {
            header = header,
            content = sectionContent,
            sectionKey = sectionKey,
            defaultExpanded = defaultExpanded,
            visualOpts = visualOpts,
        })
        header._wnProfSectionContent = sectionContent
        sectionContent._wnProfSectionHeader = header
        previousSectionHeader = header
        previousSectionContent = sectionContent
        previousSectionExpanded = isExpanded == true
        yOffset = yOffset + SECTION_COLLAPSE_HEADER_HEIGHT + (isExpanded and sectionYOffset or 0) + SECTION_HEADER_GAP
    end

    local sectionFilter = "all"
    if self.db.profile.professionSectionFilter and type(self.db.profile.professionSectionFilter.sectionKey) == "string" then
        sectionFilter = self.db.profile.professionSectionFilter.sectionKey
    end
    local drawFav = (sectionFilter == "all") or (sectionFilter == "favorites")
    local drawReg = (sectionFilter == "all") or (sectionFilter == "regular")
    local drawUnt = (sectionFilter == "untracked") or (sectionFilter == "all" and #untrackedChars > 0)

    -- Same stack as Characters tab: Favorites -> custom groups -> Characters -> inactive (untracked) last.

    if drawFav then
        DrawSection(
            trackedFavorites,
            (ns.L and ns.L["HEADER_FAVORITES"]) or "Favorites",
            "profFavoritesExpanded",
            false,
            "GM-icon-assistActive-hover",
            { sectionPreset = "gold" }
        )
    end

    for pci = 1, #customGroupsOrdered do
        local gMeta = customGroupsOrdered[pci]
        local gid = gMeta.id
        local gList = groupedById[gid] or {}
        local gListKey = (ns.CharacterService and ns.CharacterService.GetCustomGroupListKey and ns.CharacterService:GetCustomGroupListKey(gid)) or ("group_" .. tostring(gid))
        local showGrp = (sectionFilter == "all") or (sectionFilter == gListKey)
        if showGrp then
            local goldStyle = ns.CharacterService and ns.CharacterService.IsProfileCustomSectionHighlighted
                and ns.CharacterService:IsProfileCustomSectionHighlighted(self.db.profile, gid)
            DrawSection(
                gList,
                gMeta.name or gid,
                "profCGrp_" .. tostring(gid),
                false,
                goldStyle and "GM-icon-assistActive-hover" or "GM-icon-headCount",
                { sectionPreset = goldStyle and "gold" or "accent", useCharacterGroupExpand = true, groupId = gid }
            )
        end
    end

    if drawReg then
        DrawSection(
            trackedRegular,
            (ns.L and ns.L["HEADER_CHARACTERS"]) or "Characters",
            "profCharactersExpanded",
            false,
            "GM-icon-headCount",
            nil
        )
    end

    if drawUnt then
        DrawSection(
            untrackedChars,
            (ns.L and ns.L["UNTRACKED_CHARACTERS"]) or "Untracked Characters",
            "profUntrackedExpanded",
            false,
            "DungeonStoneCheckpointDeactivated",
            { sectionPreset = "danger" }
        )
    end

    RelayoutProfessionsSectionStack()

    local mfRef = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    EnsureProfessionRowGradientScrollHook(mfRef)
    EnsureProfessionColumnHeaderStrip(mfRef, parent, stackWidth)

    local chunkQueue = parent._wnProfChunkQueue
    parent._wnProfChunkQueue = nil

    local function FinishProfessionsTabChrome()
        RelayoutProfessionRowWidths(parent)
        RefreshVisibleProfessionRowGradients(parent)
        if parent._wnProfRelayoutSectionStack then
            parent._wnProfRelayoutSectionStack()
        end
    end

    if chunkQueue and #chunkQueue > 0 then
        ProfUI.AbortChunkedRowPaint()
        local drawGen = ProfUI._drawGen or 0
        local useChunked = #chunkQueue >= (ProfUI.CHUNK_MIN_CHARS or 5)
        ProfUI.RunChunkedRowPaint(self, parent, chunkQueue, drawGen, {
            profStackW = profStackW,
            currentPlayerKey = currentPlayerKey,
            rowIndex = rowIndex,
            syncAll = not useChunked,
            onComplete = FinishProfessionsTabChrome,
        })
    else
        FinishProfessionsTabChrome()
    end

    return yOffset + 10
end

--============================================================================
-- DRAW CHARACTER ROW
--============================================================================

function WarbandNexus:DrawProfessionRow(parent, char, index, width, yOffset, currentPlayerKey)
    local row = AcquireProfessionRow(parent)
    row._wnYOffset = yOffset
    row:ClearAllPoints()
    row:SetHeight(ROW_HEIGHT)
    -- Row chrome spans full grid width (PvE pveGridW parity); viewport narrower -> horizontal scroll.
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
    row:SetWidth(width)
    if row.SetClipsChildren then
        row:SetClipsChildren(false)
    end
    row:EnableMouse(true)
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    row._wnRowPaintWidth = width
    ns.UI.Factory:ApplyRowBackground(row, index)
    if row.bg and row.bg.SetAllPoints then
        row.bg:SetAllPoints()
    end

    local charKey = GetCharKey(char)
    local isCurrent = (charKey == currentPlayerKey)
    ns.UI.Factory:ApplyOnlineCharacterHighlight(row, isCurrent)
    local isFavorite = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey)
    local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}

    -- FAVORITE ICON (own column, left of class icon)
    -- Visual star size = column width * 0.65, matching CreateFavoriteButton in Characters tab
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
    row.favIcon:SetPoint("CENTER", row, "LEFT", ColCenterX("favIcon"), 0)
    if isFavorite then
        row.favIcon:Show()
    else
        row.favIcon:Hide()
    end

    -- CLASS ICON (vertically centered in row, same size as Characters tab)
    local classSize = ColWidth("classIcon")
    local classCenterX = ColCenterX("classIcon")
    if not row.classIcon then
        local CreateClassIcon = ns.UI_CreateClassIcon
        if CreateClassIcon and char.classFile then
            row.classIcon = CreateClassIcon(row, char.classFile, classSize, "CENTER", classCenterX, 0)
        end
    end
    if row.classIcon then
        row.classIcon:SetSize(classSize, classSize)
        row.classIcon:ClearAllPoints()
        row.classIcon:SetPoint("CENTER", row, "LEFT", classCenterX, 0)
        if char.classFile then row.classIcon:SetAtlas("classicon-" .. char.classFile); row.classIcon:Show()
        else row.classIcon:Hide() end
    end

    -- NAME COLUMN (name + realm stacked; block vertically centered in row)
    local nameX = ColOffset("name")
    local nameW = ColWidth("name")

    if not row.nameText then
        row.nameText = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetMaxLines(1)
    end
    row.nameText:ClearAllPoints()
    row.nameText:SetWidth(nameW)
    row.nameText:SetText(format(
        "|cff%02x%02x%02x%s|r",
        classColor.r*255,
        classColor.g*255,
        classColor.b*255,
        char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    ))

    if not row.realmText then
        row.realmText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.realmText:SetJustifyH("LEFT")
        row.realmText:SetWordWrap(false)
        row.realmText:SetMaxLines(1)
    end
    row.realmText:ClearAllPoints()
    row.realmText:SetWidth(nameW)
    row.realmText:SetTextColor(0.75, 0.75, 0.78)
    row.realmText:SetText("|cffb0b0b8" .. FormatRealmName(char.realm or "") .. "|r")

    -- Vertically center name + realm block with icon column (icons use y=0 on row LEFT).
    local nameRealmGap = 1
    local nh = max(row.nameText:GetStringHeight() or 0, 12)
    local rh = max(row.realmText:GetStringHeight() or 0, 10)
    local blockH = nh + nameRealmGap + rh
    local topInset = max((ROW_HEIGHT - blockH) / 2, 0)
    row.nameText:SetPoint("TOPLEFT", row, "TOPLEFT", nameX, -topInset)
    row.realmText:SetPoint("TOPLEFT", row.nameText, "BOTTOMLEFT", 0, -nameRealmGap)
    if row.nameText.SetJustifyV then row.nameText:SetJustifyV("TOP") end
    if row.realmText.SetJustifyV then row.realmText:SetJustifyV("TOP") end

    -- Class tint: fixed width through identity strip (fav/class/name/open), same for every row.
    local function ApplyProfessionRowClassGradient()
        if not ns.UI_ApplyCharacterRowClassGradientAccent then return end
        local gradientEnd = GetProfessionIdentityGradientEnd()
        local rowW = row:GetWidth() or row._wnRowPaintWidth or width
        if rowW and rowW >= 2 and gradientEnd > rowW - 2 then
            gradientEnd = rowW - 2
        end
        ns.UI_ApplyCharacterRowClassGradientAccent(row, char.classFile, gradientEnd)
    end
    row._wnGradientRefresh = ApplyProfessionRowClassGradient

    -- OPEN (character-level; after identity columns, before profession lines)
    local FactRow = ns.UI and ns.UI.Factory
    if not row.openBtn then
        local btn = FactRow and FactRow:CreateButton(row, ColWidth("open"), 18, true)
        if not btn then
            btn = CreateFrame("Button", nil, row)
            btn:SetSize(ColWidth("open"), 18)
        end
        if ApplyVisuals then
            ApplyVisuals(btn, {0.15, 0.15, 0.18, 0.8}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5})
        end
        btn.label = FontManager:CreateFontString(btn, "small", "OVERLAY")
        btn.label:SetPoint("CENTER", 0, 0)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(btn) end
        row.openBtn = btn
    end
    row.openBtn:ClearAllPoints()
    row.openBtn:SetPoint("CENTER", row, "LEFT", ColCenterX("open"), 0)

    local hasPrimaryProf = CharacterHasPrimaryProfession(char)
    local canOpenProf = isCurrent and hasPrimaryProf
    local openTip
    if not hasPrimaryProf then
        openTip = (ns.L and ns.L["NO_PROFESSION"]) or "No Profession"
    elseif not isCurrent then
        openTip = (ns.L and ns.L["GEAR_NO_PREVIEW_HINT"]) or "Log in on this character to refresh the appearance preview."
    else
        openTip = (ns.L and ns.L["PROF_OPEN_RECIPE_TOOLTIP"]) or "Open recipe list"
    end
    SetProfessionOpenButtonState(row.openBtn, canOpenProf, openTip)
    if canOpenProf then
        row.openBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            local slot = GetFirstPrimaryProfessionSlot(char)
            if C_TradeSkillUI and C_TradeSkillUI.OpenTradeSkill and slot then
                if slot.skillLine then
                    C_TradeSkillUI.OpenTradeSkill(slot.skillLine)
                elseif slot.skillLineID then
                    C_TradeSkillUI.OpenTradeSkill(slot.skillLineID)
                else
                    ToggleProfessionsBook()
                end
            else
                ToggleProfessionsBook()
            end
        end)
    else
        row.openBtn:SetScript("OnClick", nil)
    end

    ApplyProfessionRowClassGradient()

    -- PROFESSION LINES
    self:DrawProfessionLine(row, char, char.professions and char.professions[1], 1, LINE1_Y)
    self:DrawProfessionLine(row, char, char.professions and char.professions[2], 2, LINE2_Y)

    if row._wnProfMidRule then
        row._wnProfMidRule:Hide()
    end

    ApplyProfessionColumnDividers(row, ROW_HEIGHT)

    -- Row hover
    row:SetScript("OnEnter", function(self) self:SetAlpha(0.9) end)
    row:SetScript("OnLeave", function(self) self:SetAlpha(1) end)

    return yOffset + ROW_HEIGHT + (GetLayout().betweenRows or 0), row
end

--============================================================================
-- COLUMN TOOLTIP HIT-FRAME HELPER
-- Creates an invisible button over a column area for mouse-over tooltips.
-- Reuses frames across redraws via row[key].
--============================================================================

local function AcquireColumnHitFrame(row, key, colKey, centerY)
    local FactHit = ns.UI and ns.UI.Factory
    local frame = row[key]
    if not frame then
        local colW = ColWidth(colKey)
        if FactHit and FactHit.CreateButton then
            frame = FactHit:CreateButton(row, colW, PROF_BAND_HEIGHT, true)
        end
        if not frame then
            frame = CreateFrame("Button", nil, row)
            frame:SetSize(colW, PROF_BAND_HEIGHT)
        end
        frame:SetFrameLevel(row:GetFrameLevel() + 3)
        frame:EnableMouse(true)
        row[key] = frame
    end
    frame:SetSize(ColWidth(colKey), PROF_BAND_HEIGHT)
    frame:ClearAllPoints()
    frame:SetPoint("LEFT", row, "LEFT", ColOffset(colKey), centerY)
    frame:SetScript("OnEnter", nil)
    frame:SetScript("OnLeave", nil)
    frame:Show()
    return frame
end

-- Sets an equipment icon cell's texture and tooltip from profession equipment data.
local SLOT_DISPLAY_NAMES = {
    tool       = "Tool",
    accessory1 = "Accessory 1",
    accessory2 = "Accessory 2",
}

local function SetEquipCell(cell, eqData, slotKey)
    local item = eqData and eqData[slotKey]
    if item and item.icon then
        cell.icon:SetTexture(item.icon)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cell.icon:SetDesaturated(false)
        cell.icon:SetVertexColor(1, 1, 1, 1)
        cell.icon:Show()
        if not cell.warnTex then
            cell.warnTex = cell:CreateTexture(nil, "OVERLAY")
            cell.warnTex:SetSize(12, 12)
            cell.warnTex:SetPoint("TOPRIGHT", cell.icon, "TOPRIGHT", 3, 3)
            cell.warnTex:SetAtlas("services-icon-warning")
        end
        cell.warnTex:Hide()
        cell:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if item.itemLink then
                GameTooltip:SetHyperlink(item.itemLink)
            else
                local nm = item.name
                if nm and issecretvalue and issecretvalue(nm) then
                    nm = nil
                end
                GameTooltip:AddLine(nm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"), 1, 1, 1)
            end
            GameTooltip:Show()
        end)
        cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
    else
        cell.icon:SetTexture(nil)
        cell.icon:Hide()
        if cell.warnTex then cell.warnTex:Hide() end
        cell:SetScript("OnEnter", nil)
        cell:SetScript("OnLeave", nil)
    end
end

--- Resolve professionEquipment row for char+profName; caches pairs(eqByProf) fallback per draw.
local function ResolveProfessionEquipmentData(charKey, profName)
    if not charKey or not profName or profName == "" then return nil end
    if issecretvalue and issecretvalue(profName) then return nil end
    local charData = ns.db and ns.db.global and ns.db.global.characters and ns.db.global.characters[charKey]
    local eqByProf = charData and charData.professionEquipment
    if not eqByProf then return nil end
    local cache = profEquipResolveCache
    local function NormalizeEquipmentPayload(data)
        if not data or type(data) ~= "table" then return nil end
        if data.tool or data.accessory1 or data.accessory2 then return data end
        return nil
    end

    if cache then
        local byChar = cache[charKey]
        if byChar then
            local v = byChar[profName]
            if v ~= nil then
                if v == EQUIP_CACHE_MISS then return nil end
                return NormalizeEquipmentPayload(v)
            end
        end
    end
    local eqData
    local baseName = profName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
    eqData = eqByProf[profName] or eqByProf[baseName]
    if not eqData then
        local normName = baseName:gsub("%s+", ""):lower()
        for storedName, data in pairs(eqByProf) do
            if type(data) == "table" and storedName ~= "_legacy" and type(storedName) == "string"
                and not (issecretvalue and issecretvalue(storedName)) then
                local storedNorm = storedName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", ""):gsub("%s+", ""):lower()
                if storedNorm == normName then
                    eqData = data
                    break
                end
            end
        end
    end
    if cache then
        if not cache[charKey] then cache[charKey] = {} end
        cache[charKey][profName] = eqData or EQUIP_CACHE_MISS
    end
    return NormalizeEquipmentPayload(eqData)
end

-- Profession icon column: resolve stored icon, skillLineID API, or fallback (missing DB icon / bad fileID).
local PROF_ICON_FALLBACK = "Interface\\Icons\\INV_Misc_QuestionMark"

local function ResolveProfessionIconForDisplay(prof)
    if not prof then return nil end
    local ic = prof.icon
    if ic and not (issecretvalue and issecretvalue(ic)) then
        if type(ic) == "number" and ic > 0 then return ic end
        if type(ic) == "string" and ic ~= "" then return ic end
    end
    local slId = prof.skillLineID or prof.skillLine
    if type(slId) ~= "number" or slId <= 0 then return nil end
    local cached = profSessionIconBySkillLine[slId]
    if cached ~= nil then
        if cached == false then return nil end
        return cached
    end
    if not (C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID) then
        profSessionIconBySkillLine[slId] = false
        return nil
    end
    local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, slId)
    if not ok or type(info) ~= "table" then
        profSessionIconBySkillLine[slId] = false
        return nil
    end
    local keys = { "iconFileID", "texture", "iconTexture", "fileID" }
    for ki = 1, #keys do
        local v = info[keys[ki]]
        if v and not (issecretvalue and issecretvalue(v)) then
            if type(v) == "number" and v > 0 then
                profSessionIconBySkillLine[slId] = v
                return v
            end
            if type(v) == "string" and v ~= "" then
                profSessionIconBySkillLine[slId] = v
                return v
            end
        end
    end
    profSessionIconBySkillLine[slId] = false
    return nil
end

--- "All" expansion mode: build professionName -> recipe entry once per character per tab draw (was pairs(char.recipes) per profession line).
local function GetRecipeDataForProfessionAllMode(char, profName)
    if not char or not char.recipes or not profName then return nil end
    local ck = GetCharKey(char)
    if not ck then return nil end
    local m = profSessionRecipeMapByCharKey[ck]
    if not m then
        m = {}
        profSessionRecipeMapByCharKey[ck] = m
        for _, entry in pairs(char.recipes) do
            if type(entry) == "table" and entry.professionName then
                m[entry.professionName] = entry
            end
        end
    end
    return m[profName]
end

local function SetProfessionLineIconTexture(tex, prof, isEmptySlot)
    if not tex then return end
    if tex.SetDesaturated then tex:SetDesaturated(false) end
    if isEmptySlot then
        tex:SetTexture(PROF_ICON_FALLBACK)
        tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        tex:SetVertexColor(0.55, 0.56, 0.62, 1)
        tex:Show()
        return
    end
    tex:SetVertexColor(1, 1, 1, 1)
    local resolved = ResolveProfessionIconForDisplay(prof)
    local applied = false
    if resolved then
        local ok = pcall(function()
            if type(resolved) == "number" then
                tex:SetTexture(resolved)
            else
                tex:SetTexture(resolved)
            end
            applied = true
        end)
        if not ok then applied = false end
    end
    if not applied then
        tex:SetTexture(PROF_ICON_FALLBACK)
    end
    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    tex:Show()
end

--============================================================================
-- DRAW PROFESSION LINE (single profession within a row)
--============================================================================

function WarbandNexus:DrawProfessionLine(row, char, prof, lineIndex, centerY)
    local p = "l" .. lineIndex
    local FactRow = ns.UI and ns.UI.Factory
    local charKey = GetCharKey(char)

    local iconSize = ColWidth("profIcon")

    -- ICON
    if not row[p.."Icon"] then
        row[p.."Icon"] = CreateIcon(row, nil, iconSize)
        row[p.."Icon"]:EnableMouse(true)
        row[p.."Icon"].icon = row[p.."Icon"].texture
    end
    AnchorCellInColumn(row[p.."Icon"], "profIcon", row, centerY, "CENTER")

    -- NAME
    if not row[p.."Name"] then
        row[p.."Name"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Name"]:SetJustifyH("LEFT")
        row[p.."Name"]:SetWordWrap(false)
        row[p.."Name"]:SetMaxLines(1)
    end
    row[p.."Name"]:SetWidth(ColWidth("profName"))
    AnchorCellInColumn(row[p.."Name"], "profName", row, centerY, "LEFT")
    if row[p.."Name"].SetJustifyV then row[p.."Name"]:SetJustifyV("MIDDLE") end

    -- SKILL
    local skillVisible = IsColumnVisible("skill")
    if not row[p.."Skill"] then
        row[p.."Skill"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Skill"]:SetJustifyH("CENTER")
        row[p.."Skill"]:SetMaxLines(1)
    end
    if skillVisible then
        row[p.."Skill"]:SetWidth(ColWidth("skill"))
        AnchorCellInColumn(row[p.."Skill"], "skill", row, centerY, "CENTER")
        row[p.."Skill"]:Show()
    else
        row[p.."Skill"]:Hide()
    end

    -- RECHARGE (timer text, right of bar)
    local rechargeVisible = IsColumnVisible("recharge")
    if not row[p.."Recharge"] then
        row[p.."Recharge"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Recharge"]:SetJustifyH("CENTER")
        row[p.."Recharge"]:SetMaxLines(1)
    end
    if rechargeVisible then
        row[p.."Recharge"]:SetWidth(ColWidth("recharge"))
        AnchorCellInColumn(row[p.."Recharge"], "recharge", row, centerY, "CENTER")
        row[p.."Recharge"]:Show()
    else
        row[p.."Recharge"]:Hide()
    end

    -- KNOWLEDGE (text + optional unspent warning triangle)
    local knowVisible = IsColumnVisible("knowledge")
    local knowW = ColWidth("knowledge")
    if not row[p.."Know"] then
        row[p.."Know"] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
        row[p.."Know"]:SetJustifyH("CENTER")
        row[p.."Know"]:SetMaxLines(1)
    end
    if not row[p.."KnowWarn"] then
        local warnFrame = FactRow and FactRow:CreateContainer(row, 16, 16, false)
        if not warnFrame then
            warnFrame = CreateFrame("Frame", nil, row)
            warnFrame:SetSize(16, 16)
        end
        warnFrame:EnableMouse(true)
        local tex = warnFrame:CreateTexture(nil, "OVERLAY")
        tex:SetAllPoints()
        tex:SetAtlas("icons_64x64_important")
        warnFrame.texture = tex
        row[p.."KnowWarn"] = warnFrame
    end
    if knowVisible then
        row[p.."Know"]:SetWidth(knowW - 16)
        AnchorCellInColumn(row[p.."Know"], "knowledge", row, centerY, "CENTER")
        row[p.."Know"]:Show()
        row[p.."KnowWarn"]:ClearAllPoints()
        row[p.."KnowWarn"]:SetPoint("CENTER", row, "LEFT", ColCenterX("knowledge") + (knowW / 2) - 10, centerY)
    else
        row[p.."Know"]:Hide()
        row[p.."KnowWarn"]:Hide()
    end

    local function EnsureProgressCell(fieldKey, colKey)
        local key = p .. fieldKey
        if not row[key] then
            row[key] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
            row[key]:SetJustifyH("CENTER")
            row[key]:SetMaxLines(1)
        end
        if IsColumnVisible(colKey) then
            row[key]:SetWidth(ColWidth(colKey))
            AnchorCellInColumn(row[key], colKey, row, centerY, "CENTER")
            row[key]:Show()
        else
            row[key]:Hide()
        end
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
    local cooldownsText = EnsureProgressCell("Cooldowns", "cooldowns")

    -- EQUIPMENT ICONS (tool + acc1 + acc2 in single "equipment" column)
    local EQUIP_ICON_SIZE = 22
    local EQUIP_ICON_GAP = 4
    local equipVisible = IsColumnVisible("equipment")
    local equipX = ColOffset("equipment")
    local equipW = ColWidth("equipment")

    local function EnsureEquipIcon(fieldKey, iconIndex)
        local key = p .. fieldKey
        if not row[key] then
            local btn = FactRow and FactRow:CreateButton(row, EQUIP_ICON_SIZE, EQUIP_ICON_SIZE, true)
            if not btn then
                btn = CreateFrame("Button", nil, row)
                btn:SetSize(EQUIP_ICON_SIZE, EQUIP_ICON_SIZE)
            end
            btn:EnableMouse(true)
            btn.icon = btn:CreateTexture(nil, "ARTWORK")
            btn.icon:SetSize(EQUIP_ICON_SIZE, EQUIP_ICON_SIZE)
            btn.icon:SetPoint("CENTER", 0, 0)
            btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            row[key] = btn
        end
        local btn = row[key]
        if equipVisible then
            btn:SetSize(EQUIP_ICON_SIZE, EQUIP_ICON_SIZE)
            btn:ClearAllPoints()
            local xOff = equipX + (iconIndex - 1) * (EQUIP_ICON_SIZE + EQUIP_ICON_GAP)
            local padding = math.floor((equipW - 3 * EQUIP_ICON_SIZE - 2 * EQUIP_ICON_GAP) / 2)
            btn:SetPoint("LEFT", xOff + padding, centerY)
            btn:Show()
        else
            btn:Hide()
        end
        return btn
    end

    local toolCell = EnsureEquipIcon("Tool", 1)
    local acc1Cell = EnsureEquipIcon("Acc1", 2)
    local acc2Cell = EnsureEquipIcon("Acc2", 3)

    -- COLUMN HIT-FRAMES (interactive tooltips for skill + cooldowns + recharge)
    local skillHit = AcquireColumnHitFrame(row, p.."SkillHit", "skill", centerY)
    if skillVisible then skillHit:Show() else skillHit:Hide() end
    local cdHit = AcquireColumnHitFrame(row, p.."CdHit", "cooldowns", centerY)
    if IsColumnVisible("cooldowns") then cdHit:Show() else cdHit:Hide() end
    local rechargeHit = AcquireColumnHitFrame(row, p.."RechargeHit", "recharge", centerY)
    if rechargeVisible then rechargeHit:Show() else rechargeHit:Hide() end

    -- Per-line Open retired (character-level row.openBtn); hide pooled legacy buttons.
    if row[p.."Btn"] then
        row[p.."Btn"]:Hide()
        row[p.."Btn"]:SetScript("OnClick", nil)
        row[p.."Btn"]:SetScript("OnEnter", nil)
        row[p.."Btn"]:SetScript("OnLeave", nil)
    end

    -- INFO BUTTON (read-only detail window)
    if not row[p.."InfoBtn"] then
        local ibtn = FactRow and FactRow:CreateButton(row, ColWidth("info"), 18, true)
        if not ibtn then
            ibtn = CreateFrame("Button", nil, row)
            ibtn:SetSize(ColWidth("info"), 18)
        end
        if ApplyVisuals then
            ApplyVisuals(ibtn, {0.12, 0.12, 0.15, 0.8}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4})
        end
        local iicon = ibtn:CreateTexture(nil, "ARTWORK")
        iicon:SetSize(14, 14)
        iicon:SetPoint("CENTER", 0, 0)
        if not (iicon.SetAtlas and (pcall(iicon.SetAtlas, iicon, "QuestTurnin", false) or pcall(iicon.SetAtlas, iicon, "QuestTurnin", true))) then
            iicon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            iicon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        ibtn.iconTex = iicon
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(ibtn) end
        row[p.."InfoBtn"] = ibtn
    end
    AnchorCellInColumn(row[p.."InfoBtn"], "info", row, centerY, "CENTER")

    -- ===== POPULATE =====
    if prof and prof.name then
        if row[p .. "EquipEmpty"] then row[p .. "EquipEmpty"]:Hide() end
        local profName = prof.name

        -- Icon (resolve fileID/path; refresh from skillLineID when DB icon missing)
        SetProfessionLineIconTexture(row[p.."Icon"].icon, prof, false)
        row[p.."Icon"]:Show()

        -- Name (secondary profession line slightly muted for hierarchy)
        local nameHex = (lineIndex == 2) and "d4d4dc" or "ffffff"
        row[p.."Name"]:SetText("|cff" .. nameHex .. profName .. "|r")

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
            concMax = concData.max or 0
            if WarbandNexus.GetEstimatedConcentration then
                local estOk, estVal = pcall(WarbandNexus.GetEstimatedConcentration, WarbandNexus, concData)
                if estOk and type(estVal) == "number" then
                    concCurrent = estVal
                end
            end
            if concCurrent >= concMax then
                rechargeStr = "|cff4de64d" .. ((ns.L and ns.L["FULL"]) or "Full") .. "|r"
            elseif WarbandNexus.GetConcentrationTimeToFull then
                local tsOk, ts = pcall(WarbandNexus.GetConcentrationTimeToFull, WarbandNexus, concData)
                if tsOk and ts and ts ~= "" and ts ~= "Full" then
                    rechargeStr = "|cffffffff" .. ts .. "|r"
                end
            end
        end
        local concVisible = IsColumnVisible("conc")
        local concX = ColOffset("conc")
        if concVisible then
            UpdateConcentrationBar(row, p.."ConcBar", concX, ColBarTopY(centerY), ColWidth("conc"), concCurrent, concMax)
        elseif row[p.."ConcBar"] then
            row[p.."ConcBar"]:Hide()
        end
        if rechargeVisible then
            row[p.."Recharge"]:SetText(rechargeStr)
        end

        -- Recharge tooltip: show detailed time breakdown on hover
        if rechargeVisible and concData and concData.max and concData.max > 0 then
            local capturedConcData = concData
            rechargeHit:SetScript("OnEnter", function(self)
                local est = capturedConcData.current or 0
                if WarbandNexus.GetEstimatedConcentration then
                    local eOk, eVal = pcall(WarbandNexus.GetEstimatedConcentration, WarbandNexus, capturedConcData)
                    if eOk and type(eVal) == "number" then est = eVal end
                end
                if est >= (capturedConcData.max or 0) then return end
                if WarbandNexus.GetConcentrationTimeToFullDetailed then
                    local dOk, detailed = pcall(WarbandNexus.GetConcentrationTimeToFullDetailed, WarbandNexus, capturedConcData)
                    if dOk and detailed and detailed ~= "" and detailed ~= "Full" then
                        local lines = {
                            { left = (ns.L and ns.L["RECHARGE"]) or "Recharge", right = detailed, leftColor = {1,1,1}, rightColor = {1, 0.82, 0} },
                        }
                        if ShowTooltip then ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["CONCENTRATION"]) or "Concentration", lines = lines, anchor = "ANCHOR_TOP" }) end
                    end
                end
            end)
            rechargeHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        else
            rechargeHit:SetScript("OnEnter", nil)
            rechargeHit:SetScript("OnLeave", nil)
        end

        -- Knowledge: keyed by skillLineID (expansion-specific). Always show Current / Max.
        -- String-key legacy fallback only in "All" mode to prevent cross-expansion data bleed.
        local kd = slID and char.knowledgeData and char.knowledgeData[slID]
        if not kd and GetExpansionFilter() == "All" then
            kd = char.knowledgeData and char.knowledgeData[profName]
        end
        if knowVisible then row[p.."Know"]:SetText(FormatKnowledge(kd)) end
        local unspent = (kd and kd.unspentPoints) and kd.unspentPoints or 0
        if knowVisible and unspent > 0 then
            row[p.."KnowWarn"]:Show()
            row[p.."KnowWarn"]:SetScript("OnEnter", function(self)
                local msg
                local msgTemplate = (ns.L and ns.L["UNSPENT_KNOWLEDGE_COUNT"]) or "%d unspent knowledge points"
                local ok, formatted = pcall(format, msgTemplate, unspent)
                if ok and formatted and formatted ~= "" then
                    msg = formatted
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
            recipeData = GetRecipeDataForProfessionAllMode(char, profName)
        end
        local progressData = nil
        if slID and char.professionData and char.professionData.bySkillLine and char.professionData.bySkillLine[slID] then
            progressData = char.professionData.bySkillLine[slID].weeklyKnowledge
        end
        if not progressData and slID and char.professionWeeklyKnowledge then
            progressData = char.professionWeeklyKnowledge[slID]
        end

        -- First Craft: only show when data is from Midnight (avoid TWW/DF recipe counts mixing in).
        local recipeExpName = recipeData and recipeData.expansionName
        local recipeExpMidnight = recipeExpName and type(recipeExpName) == "string"
            and not (issecretvalue and issecretvalue(recipeExpName))
            and recipeExpName:find("Midnight", 1, true)
        local isMidnightRecipeData =
            (slID and IsMidnightSkillLineID(slID))
            or (recipeData and recipeData.skillLineID and IsMidnightSkillLineID(recipeData.skillLineID))
            or recipeExpMidnight
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
        local moxieCurrencyID = slID and MIDNIGHT_MOXIE_CURRENCY[slID]
        if charKey and moxieCurrencyID and WarbandNexus.GetCurrencyData then
            local moxieData = WarbandNexus:GetCurrencyData(moxieCurrencyID, charKey)
            local qty = (moxieData and (moxieData.quantity or moxieData.value)) or 0
            moxieText:SetText(qty > 0 and format("|cffffffff%d|r", qty) or "|cffffffff--|r")
        else
            moxieText:SetText("|cffffffff--|r")
        end

        -- COOLDOWNS: count of ready / total recipes with cooldowns for this profession's skillLineID.
        local cdReady, cdTotal = 0, 0
        if charKey and slID then
            local charData = ns.db and ns.db.global and ns.db.global.characters and ns.db.global.characters[charKey]
            local cdTable = charData and charData.professionCooldowns and charData.professionCooldowns[slID]
            if cdTable then
                local now = time()
                for _, info in pairs(cdTable) do
                    cdTotal = cdTotal + 1
                    if (info.cooldownEnd or 0) <= now then
                        cdReady = cdReady + 1
                    end
                end
            end
        end
        if cdTotal > 0 then
            local clr = cdReady == cdTotal and "|cff00ff00" or (cdReady > 0 and "|cffffff00" or "|cffff4444")
            cooldownsText:SetText(format("%s%d / %d|r", clr, cdReady, cdTotal))
        else
            cooldownsText:SetText("|cffffffff--|r")
        end

        -- Cooldown tooltip: show individual recipe cooldowns when hovering.
        if cdTotal > 0 and charKey and slID then
            local capturedCharKey, capturedSlID = charKey, slID
            cdHit:SetScript("OnEnter", function(self)
                local lines = {}
                local cData = ns.db and ns.db.global and ns.db.global.characters and ns.db.global.characters[capturedCharKey]
                local tbl = cData and cData.professionCooldowns and cData.professionCooldowns[capturedSlID]
                if tbl then
                    local now = time()
                    local sorted = {}
                    for _, info in pairs(tbl) do sorted[#sorted+1] = info end
                    table.sort(sorted, function(a,b) return (a.cooldownEnd or 0) < (b.cooldownEnd or 0) end)
                    for si = 1, #sorted do
                        local info = sorted[si]
                        local remaining = (info.cooldownEnd or 0) - now
                        local iconStr = info.recipeIcon and format("|T%s:0|t ", tostring(info.recipeIcon)) or ""
                        local rName = iconStr .. (info.recipeName or "?")
                        local rStatus, rColor
                        if remaining <= 0 then
                            rStatus = "Ready"
                            rColor = {0.3, 0.9, 0.3}
                        else
                            local h = math.floor(remaining / 3600)
                            local m = math.floor((remaining % 3600) / 60)
                            rStatus = h > 0 and format("%dh %dm", h, m) or format("%dm", m)
                            rColor = {1, 0.82, 0}
                        end
                        lines[#lines+1] = { left = rName, right = rStatus, leftColor = {1,1,1}, rightColor = rColor }
                    end
                end
                if #lines > 0 and ShowTooltip then
                    ShowTooltip(self, { type = "custom", title = (ns.L and ns.L["COOLDOWNS"]) or "Cooldowns", lines = lines, anchor = "ANCHOR_TOP" })
                end
            end)
            cdHit:SetScript("OnLeave", function() if HideTooltip then HideTooltip() end end)
        else
            cdHit:SetScript("OnEnter", nil)
            cdHit:SetScript("OnLeave", nil)
        end

        local eqData
        if charKey then
            eqData = ResolveProfessionEquipmentData(charKey, profName)
        end
        SetEquipCell(toolCell, eqData, "tool")
        SetEquipCell(acc1Cell, eqData, "accessory1")
        SetEquipCell(acc2Cell, eqData, "accessory2")

        -- ===== SKILL COLUMN TOOLTIP (expansion breakdown — unique data) =====
        skillHit:SetScript("OnEnter", function(self)
            local lines = {}
            local expansions = char.professionExpansions and char.professionExpansions[profName]
            if expansions and #expansions > 0 then
                for exi = 1, #expansions do
                    local exp = expansions[exi]
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
                for exi = 1, #expansions do
                    local exp = expansions[exi]
                    local maxS = exp.maxSkillLevel or 0
                    local curS = exp.skillLevel or 0
                    local sc = (maxS > 0 and curS >= maxS) and {0.3,0.9,0.3} or (curS > 0 and {1,0.82,0} or {1,1,1})
                    lines[#lines+1] = { left = exp.name or "?", right = maxS > 0 and format("%d / %d", curS, maxS) or "--", leftColor = {1,1,1}, rightColor = sc }
                end
            end
            local kdT = (slID and char.knowledgeData and char.knowledgeData[slID]) or (char.knowledgeData and char.knowledgeData[rowProfName])
            if kdT then
                local unspent = kdT.unspentPoints or 0
                if unspent > 0 then lines[#lines+1] = { left = (ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent", right = tostring(unspent), leftColor = {1, 0.82, 0}, rightColor = {1, 0.82, 0} } end
            end
            local concT = (slID and char.concentration and char.concentration[slID]) or (char.concentration and char.concentration[rowProfName])
            if concT and concT.max and concT.max > 0 then
                local est = concT.current or 0
                if WarbandNexus.GetEstimatedConcentration then
                    local estOk, estVal = pcall(WarbandNexus.GetEstimatedConcentration, WarbandNexus, concT)
                    if estOk and type(estVal) == "number" then est = estVal end
                end
                local concMax = concT.max or 0
                local cc = est >= concMax and {0.3,0.9,0.3} or (est > 0 and {1,0.82,0} or {1,1,1})
                lines[#lines+1] = { left = (ns.L and ns.L["CONCENTRATION"]) or "Concentration", right = format("%d / %d", est, concMax), leftColor = {1,1,1}, rightColor = cc }
                if est < concMax and WarbandNexus.GetConcentrationTimeToFullDetailed then
                    local tsOk, ts = pcall(WarbandNexus.GetConcentrationTimeToFullDetailed, WarbandNexus, concT)
                    if tsOk and ts and ts ~= "" and ts ~= "Full" then lines[#lines+1] = { left = (ns.L and ns.L["RECHARGE"]) or "Recharge", right = ts, leftColor = {1,1,1}, rightColor = {1,0.82,0} } end
                end
            end
            -- Equipment: show per-profession gear; fallback lookup by base name if key differs (secret-safe string ops).
            local eqByProf = char.professionEquipment
            local eqData = nil
            if eqByProf and rowProfName and type(rowProfName) == "string" and not (issecretvalue and issecretvalue(rowProfName)) then
                local eqKey = rowProfName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
                eqData = eqByProf[rowProfName] or eqByProf[eqKey]
                if not eqData then
                    local rowNorm = rowProfName:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
                    for k, v in pairs(eqByProf) do
                        if k ~= "_legacy" and type(k) == "string" and not (issecretvalue and issecretvalue(k))
                            and type(v) == "table" and (v.tool or v.accessory1 or v.accessory2) then
                            local norm = k:gsub("^Midnight ", ""):gsub("^Khaz Algar ", ""):gsub("^Dragon Isles ", "")
                            local eqSafe = eqKey and not (issecretvalue and issecretvalue(eqKey))
                            if norm == eqKey or norm == rowNorm or (eqSafe and k:find(eqKey, 1, true)) then
                                eqData = v
                                break
                            end
                        end
                    end
                end
            end
            if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
                local slotKeys = { "tool", "accessory1", "accessory2" }
                local tooltipSvc = ns.TooltipService
                for ski = 1, #slotKeys do
                    local slotKey = slotKeys[ski]
                    local item = eqData[slotKey]
                    if item then
                        local iconStr = item.icon and format("|T%s:0|t ", tostring(item.icon)) or ""
                        local statLines = tooltipSvc and tooltipSvc.GetItemTooltipSummaryLines and tooltipSvc:GetItemTooltipSummaryLines(item.itemLink, item.itemID, slotKey) or {}
                        local slotLabel = (statLines[1] and statLines[1].left) or (slotKey == "tool" and "Tool" or "Accessory")
                        lines[#lines+1] = {
                            left = iconStr .. (item.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")),
                            right = slotLabel,
                            leftColor = {1,1,1},
                            rightColor = {0.5,0.5,0.5}
                        }
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
        -- Empty slot: dim placeholders; consistent gray "No Profession" + question-mark icon (symmetry with filled rows).
        local emptyCell = "|cff6a6a75--|r"
        row[p.."Icon"]:Show()
        SetProfessionLineIconTexture(row[p.."Icon"].icon, nil, true)
        local emptyLabel = (ns.L and ns.L["NO_PROFESSION"]) or "No Profession"
        row[p.."Name"]:SetText("|cffaaaaaa" .. emptyLabel .. "|r")
        if skillVisible then row[p.."Skill"]:SetText(emptyCell) end
        if rechargeVisible then row[p.."Recharge"]:SetText(emptyCell) end
        if knowVisible then row[p.."Know"]:SetText(emptyCell) end
        if row[p.."KnowWarn"] then row[p.."KnowWarn"]:Hide() end
        if IsColumnVisible("recipes") then recipesText:SetText(emptyCell) end
        if IsColumnVisible("firstCraft") then firstCraftText:SetText(emptyCell) end
        if IsColumnVisible("uniques") then uniquesText:SetText(emptyCell) end
        if IsColumnVisible("treatise") then treatiseText:SetText(emptyCell) end
        if IsColumnVisible("weeklyQuest") then weeklyQuestText:SetText(emptyCell) end
        if IsColumnVisible("treasure") then treasureText:SetText(emptyCell) end
        if IsColumnVisible("gathering") then gatheringText:SetText(emptyCell) end
        if IsColumnVisible("catchUp") then catchUpText:SetText(emptyCell) end
        if IsColumnVisible("moxie") then moxieText:SetText(emptyCell) end
        if IsColumnVisible("cooldowns") then cooldownsText:SetText(emptyCell) end
        SetEquipCell(toolCell, nil, "tool")
        SetEquipCell(acc1Cell, nil, "accessory1")
        SetEquipCell(acc2Cell, nil, "accessory2")
        if equipVisible then
            local eqEmptyKey = p .. "EquipEmpty"
            if not row[eqEmptyKey] then
                row[eqEmptyKey] = FontManager:CreateFontString(row, DATA_FONT, "OVERLAY")
                row[eqEmptyKey]:SetJustifyH("CENTER")
                row[eqEmptyKey]:SetMaxLines(1)
            end
            row[eqEmptyKey]:SetWidth(equipW)
            row[eqEmptyKey]:ClearAllPoints()
            row[eqEmptyKey]:SetPoint("CENTER", row, "LEFT", ColCenterX("equipment"), centerY)
            row[eqEmptyKey]:SetText(emptyCell)
            row[eqEmptyKey]:Show()
        elseif row[p .. "EquipEmpty"] then
            row[p .. "EquipEmpty"]:Hide()
        end
        if row[p.."Btn"] then
            row[p.."Btn"]:Hide()
            row[p.."Btn"]:SetScript("OnClick", nil)
            row[p.."Btn"]:SetScript("OnEnter", nil)
            row[p.."Btn"]:SetScript("OnLeave", nil)
        end
        if row[p.."InfoBtn"] then row[p.."InfoBtn"]:Hide() end
        local concX = ColOffset("conc")
        UpdateConcentrationBar(row, p.."ConcBar", concX, ColBarTopY(centerY), ColWidth("conc"), 0, 0)
        if row[p.."ConcBar"] then row[p.."ConcBar"]:Hide() end
        if row[p.."Icon"].knowledgeBadge then row[p.."Icon"].knowledgeBadge:Hide() end
        row[p.."Icon"]:SetScript("OnEnter", nil)
        row[p.."Icon"]:SetScript("OnLeave", nil)
        -- Hide hit-frames for empty slots
        skillHit:Hide()
        cdHit:Hide()
        rechargeHit:Hide()
    end
end

--- Cancel in-flight chunked row paint (tab switch / PopulateContent supersede).
function ProfUI.AbortChunkedRowPaint()
    ProfUI._drawGen = (ProfUI._drawGen or 0) + 1
end

--- Paint profession character rows across frames; generation token cancels on tab leave.
---@param addon table WarbandNexus
---@param parent Frame scrollChild
---@param queue table[] { char, sectionContent }
---@param drawGen number
---@param ctx table profStackW, currentPlayerKey, rowIndex, onComplete
function ProfUI.RunChunkedRowPaint(addon, parent, queue, drawGen, ctx)
    if not queue or #queue == 0 then
        if ctx.onComplete then ctx.onComplete() end
        return
    end
    local chunkSize = ProfUI.CHUNK_SIZE or 4
    local rowIndex = ctx.rowIndex or 0
    local rowStride = ROW_HEIGHT + ((GetLayout().betweenRows) or 0)
    local idx = 1

    local function relayoutTouched(fromIdx, toIdx)
        local touched = {}
        for qi = fromIdx, toIdx do
            local job = queue[qi]
            local sc = job and job.sectionContent
            if sc and not touched[sc] then
                touched[sc] = true
                local h = math.max(0.1, sc._wnProfRunningYOffset or 0.1)
                sc._wnSectionFullH = h
                sc:SetHeight(h)
                sc:Show()
            end
        end
        if parent._wnProfRelayoutSectionStack then
            parent._wnProfRelayoutSectionStack()
        end
    end

    local function pump()
        if ProfUI._drawGen ~= drawGen then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or not mf:IsShown() or mf.currentTab ~= "professions" then return end
        if not parent or not parent.GetParent then return end

        local fromIdx = idx
        local limit = ctx.syncAll and #queue or math.min(idx + chunkSize - 1, #queue)
        for qi = fromIdx, limit do
            local job = queue[qi]
            local sectionContent = job.sectionContent
            local char = job.char
            if sectionContent and char then
                rowIndex = rowIndex + 1
                local sectionYOffset = sectionContent._wnProfRunningYOffset or 0
                local ok, nextYOffset, rowFrame = pcall(addon.DrawProfessionRow, addon, sectionContent, char, rowIndex, ctx.profStackW, sectionYOffset, ctx.currentPlayerKey)
                if ok and nextYOffset then
                    sectionContent._wnProfRunningYOffset = nextYOffset
                    if rowFrame and parent._wnProfNestedRows then
                        tinsert(parent._wnProfNestedRows, rowFrame)
                    end
                else
                    sectionContent._wnProfRunningYOffset = sectionYOffset + rowStride
                end
            end
        end
        idx = limit + 1
        relayoutTouched(fromIdx, limit)

        if idx > #queue then
            if ctx.onComplete then ctx.onComplete() end
            return
        end
        C_Timer.After(0, pump)
    end

    if ctx.syncAll then
        pump()
    else
        C_Timer.After(0, pump)
    end
end

--- Tab switch (AbortTabOperations): clear session profession caches so GUID/API-heavy maps are not retained across tabs.
function WarbandNexus:AbortProfessionsTabWork()
    ProfUI.AbortChunkedRowPaint()
    InvalidateProfessionsTradeSessionCaches()
end

-- Session profession caches: register invalidation at load so data updates clear stale API/icon maps
-- even if DrawProfessionsTab has not run yet (e.g. professions module off).
do
    local Constants = ns.Constants
    local ev = Constants and Constants.EVENTS
    if ev then
        WarbandNexus.RegisterMessage(ProfessionsUIEvents, ev.RECIPE_DATA_UPDATED, InvalidateProfessionsTradeSessionCaches)
        WarbandNexus.RegisterMessage(ProfessionsUIEvents, ev.PROFESSION_DATA_UPDATED, InvalidateProfessionsTradeSessionCaches)
        WarbandNexus.RegisterMessage(ProfessionsUIEvents, ev.PROFESSION_EQUIPMENT_UPDATED, InvalidateProfessionsTradeSessionCaches)
        WarbandNexus.RegisterMessage(ProfessionsUIEvents, ev.CRAFTING_ORDERS_UPDATED, InvalidateProfessionsTradeSessionCaches)
    end
end

if ns.UI_RegisterTabViewportResize then
    ns.UI_RegisterTabViewportResize("professions", {
        mode = ns.UI_VIEWPORT_RESIZE_MODE and ns.UI_VIEWPORT_RESIZE_MODE.STRETCH_ROWS,
        tabKey = "professions",
        onLive = function(scrollChild, contentWidth, mf)
            ScheduleProfessionViewportRelayout(mf, scrollChild, contentWidth)
        end,
        stretch = ProfessionStretchRelayoutOpts,
        refreshHeader = true,
        onCommit = function(scrollChild, contentWidth, mf)
            local bodyW = ProfessionsBodyWidthFromViewport(contentWidth, scrollChild)
            local paintW
            if bodyW and bodyW > 0 then
                cachedRowWidth = bodyW
                scrollChild._wnProfBodyWidth = bodyW
                paintW = ResolveProfessionColumnHeaderInnerWidth(mf, scrollChild, bodyW)
                local side = scrollChild._wnProfContentSide or SIDE_MARGIN
                scrollChild._wnProfStackWidth = ProfessionStackBodyWidth(paintW, side)
            end
            EnsureProfessionColumnHeaderStrip(mf, scrollChild or mf.scrollChild, bodyW)
            RelayoutProfessionRowWidths(scrollChild or mf.scrollChild)
            local sc = scrollChild or mf.scrollChild
            if sc and sc._wnProfRelayoutSectionStack then
                sc._wnProfRelayoutSectionStack()
            end
            EnsureProfessionRowGradientScrollHook(mf)
            return false
        end,
    })
end
