--[[
    Warband Nexus - Character row column layout (Characters / PvE list chrome).
    Split from SharedWidgets.lua to reduce main chunk size (Lua 5.1 local limit).
    Loaded from WarbandNexus.toc immediately before Modules/UI/SharedWidgets.lua.
]]

local _, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Define column structure (single source of truth)
local CHAR_ROW_COLUMNS = {
    favorite = {
        width = 33,
        spacing = 5,
        total = 38,
    },
    faction = {
        width = 33,
        spacing = 5,
        total = 38,
    },
    race = {
        width = 33,
        spacing = 5,
        total = 38,
    },
    class = {
        width = 33,
        spacing = 5,
        total = 38,
    },
    name = {
        width = 100,
        spacing = 15,
        total = 115,
    },
    -- `min` = readability floor for flex columns: narrow viewports shrink these toward min
    -- (proportional) before the horizontal scrollbar takes over.
    guild = {
        width = 130,
        spacing = 15,
        total = 145,
        min = 60,
    },
    level = {
        width = 82,
        spacing = 15,
        total = 97,
        min = 70,   -- "Zzz 150.00%" rested line
    },
    itemLevel = {
        width = 75,
        spacing = 15,
        total = 90,
        min = 64,   -- "iLvl 288"
    },
    gold = {
        width = 190,
        spacing = 15,
        total = 205,
        min = 150,  -- three coin groups at FormatMoney's 12-char cap
    },
    professions = {
        width = 150,
        spacing = 0,
        total = 150,
        min = 128,  -- 3 icons x 39 + 2 x 5 gaps
    },
    mythicKey = {
        width = 120,
        spacing = 15,
        total = 135,
        min = 96,   -- icon + "+10 - AD"
    },
    mail = {
        width = 36,
        spacing = 10,
        total = 46,
    },
    reorder = {
        width = 44,
        spacing = 6,
        total = 50,
    },
    lastSeen = {
        width = 60,
        spacing = 6,
        total = 66,
    },
    headerAssign = {
        width = 22,
        spacing = 4,
        total = 26,
    },
    tracking = {
        width = 22,
        spacing = 4,
        total = 26,
    },
    delete = {
        width = 24,
        spacing = 6,
        total = 30,
    },
}

local CHAR_ROW_COLUMN_ORDER = {
    "favorite", "faction", "race", "class", "name", "mail", "guild", "level", "itemLevel",
    "gold", "professions", "mythicKey", "reorder", "lastSeen", "headerAssign", "tracking", "delete",
}

local function GetColumnOffset(columnKey)
    local offset = 10
    for oi = 1, #CHAR_ROW_COLUMN_ORDER do
        local key = CHAR_ROW_COLUMN_ORDER[oi]
        if key == columnKey then
            return offset
        end
        offset = offset + CHAR_ROW_COLUMNS[key].total
    end
    return offset
end

local function GetCharRowTotalWidth()
    local width = 10
    for oi = 1, #CHAR_ROW_COLUMN_ORDER do
        width = width + CHAR_ROW_COLUMNS[CHAR_ROW_COLUMN_ORDER[oi]].total
    end
    return width + 10
end

local function GetCharRowTotalWidthForGuild(guildColW)
    local base = GetCharRowTotalWidth()
    local gCol = CHAR_ROW_COLUMNS.guild or {}
    local gTot = gCol.total or 145
    local actual = (guildColW or gCol.width or 130) + (gCol.spacing or 15)
    return base + math.max(0, actual - gTot)
end

local CHAR_ROW_RIGHT_MARGIN = 6
local CHAR_ROW_RIGHT_GAP = 6

local function GetCharRowRightRailWidth()
    local c = CHAR_ROW_COLUMNS
    return CHAR_ROW_RIGHT_MARGIN
        + (c.delete and c.delete.width or 24)
        + CHAR_ROW_RIGHT_GAP
        + (c.tracking and c.tracking.width or 22)
        + CHAR_ROW_RIGHT_GAP
        + (c.headerAssign and c.headerAssign.total or 26)
        + CHAR_ROW_RIGHT_GAP
        + (c.lastSeen and c.lastSeen.width or 60)
        + CHAR_ROW_RIGHT_GAP
        + (c.reorder and c.reorder.width or 44)
        + CHAR_ROW_RIGHT_MARGIN
end

local function GetCharRowMiddleBlockWidth()
    local c = CHAR_ROW_COLUMNS
    return (c.level and c.level.total or 97)
        + (c.itemLevel and c.itemLevel.total or 90)
        + (c.gold and c.gold.total or 205)
        + (c.professions and c.professions.total or 150)
        + (c.mythicKey and c.mythicKey.total or 135)
end

local function ComputeCharRowGuildColumnWidth(listRowW, measuredGuildW)
    local guildOffset = GetColumnOffset("guild")
    local railW = GetCharRowRightRailWidth()
    local middleW = GetCharRowMiddleBlockWidth()
    local maxGuild = (listRowW or 800) - guildOffset - middleW - railW - 4
    local gCol = CHAR_ROW_COLUMNS.guild or {}
    local measured = measuredGuildW or gCol.width or 130
    return math.min(measured, math.max(gCol.min or 60, maxGuild))
end

local CHAR_ROW_FLEX_ORDER = { "level", "itemLevel", "gold", "professions", "mythicKey" }

--- Effective column widths for a given row width. At or above the ideal total every column
--- keeps its ideal width; below it, guild compresses first (measured cap), then the flex pool
--- shrinks proportionally toward each column's `min`. Offsets stay chained in the callers.
---@param rowW number|nil Row paint width
---@param measuredGuildW number|nil Widest guild name measured for the roster
---@return table effWidths { guild, level, itemLevel, gold, professions, mythicKey }
local function ComputeCharRowFlexColumns(rowW, measuredGuildW)
    local c = CHAR_ROW_COLUMNS
    local out = {
        guild = ComputeCharRowGuildColumnWidth(rowW, measuredGuildW),
        level = c.level.width,
        itemLevel = c.itemLevel.width,
        gold = c.gold.width,
        professions = c.professions.width,
        mythicKey = c.mythicKey.width,
    }
    if not rowW or rowW < 1 then return out end
    local deficit = GetCharRowTotalWidthForGuild(out.guild) - rowW
    if deficit <= 0 then return out end
    local slack = 0
    for i = 1, #CHAR_ROW_FLEX_ORDER do
        local col = c[CHAR_ROW_FLEX_ORDER[i]]
        slack = slack + math.max(0, col.width - (col.min or col.width))
    end
    if slack <= 0 then return out end
    local ratio = math.min(1, deficit / slack)
    for i = 1, #CHAR_ROW_FLEX_ORDER do
        local key = CHAR_ROW_FLEX_ORDER[i]
        local col = c[key]
        local give = math.max(0, col.width - (col.min or col.width)) * ratio
        out[key] = math.floor(col.width - give + 0.5)
    end
    return out
end

local function GetCharRowTotalWidthAtMinimums()
    local width = 10
    for oi = 1, #CHAR_ROW_COLUMN_ORDER do
        local col = CHAR_ROW_COLUMNS[CHAR_ROW_COLUMN_ORDER[oi]]
        local w = (col.min or col.width) + (col.spacing or 0)
        width = width + math.min(col.total, w)
    end
    return width + 10
end

local function ComputeCharactersMinScrollWidth(_addon, _guildColW)
    -- Flex columns absorb the difference down to their minimums; only below this floor does
    -- the horizontal scrollbar take over. Ideal widths must NOT drive the floor (that pinned
    -- the tab at ~1350px and broke responsive shrink after a window resize).
    return math.max(720, GetCharRowTotalWidthAtMinimums())
end

local function ResolveCharactersTabRowWidth(mainFrame, scrollParent, metrics, guildColW)
    local minW = ComputeCharactersMinScrollWidth(WarbandNexus, guildColW)
    local viewportW = minW
    if metrics and metrics.bodyWidth and metrics.bodyWidth > 0 then
        viewportW = metrics.bodyWidth
    elseif mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.bodyWidth and m.bodyWidth > 0 then
            viewportW = m.bodyWidth
        end
    elseif scrollParent and scrollParent.GetWidth then
        viewportW = scrollParent:GetWidth() or minW
    end
    return math.max(minW, viewportW)
end

function ns.UI_ResolveCharactersTabRowWidthForLive(mainFrame, scrollParent, metrics, guildColW)
    local viewportW = 200
    if metrics and metrics.bodyWidth and metrics.bodyWidth > 0 then
        viewportW = metrics.bodyWidth
    elseif mainFrame and ns.UI_GetMainTabLayoutMetrics then
        local m = ns.UI_GetMainTabLayoutMetrics(mainFrame)
        if m and m.bodyWidth and m.bodyWidth > 0 then
            viewportW = m.bodyWidth
        end
    elseif scrollParent and scrollParent.GetWidth then
        viewportW = scrollParent:GetWidth() or 200
    else
        viewportW = 200
    end
    return math.max(200, viewportW)
end

local GRID_COL_DIVIDER_RGBA = { 0.3, 0.3, 0.35, 0.4 }

local function EnsureGridColumnDivider(parent, index, x, height)
    if not parent or not x then return nil end
    parent._wnGridColDividers = parent._wnGridColDividers or {}
    local divider = parent._wnGridColDividers[index]
    if not divider then
        divider = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
        parent._wnGridColDividers[index] = divider
    end
    divider:SetColorTexture(GRID_COL_DIVIDER_RGBA[1], GRID_COL_DIVIDER_RGBA[2], GRID_COL_DIVIDER_RGBA[3], GRID_COL_DIVIDER_RGBA[4])
    divider:SetWidth(1)
    divider:SetHeight(height or 38)
    divider:ClearAllPoints()
    divider:SetPoint("CENTER", parent, "LEFT", x, 0)
    divider:Show()
    return divider
end

local function SyncGridColumnDividers(parent, xPositions, height)
    if not parent then return end
    local positions = xPositions or {}
    local h = height or 38
    for i = 1, #positions do
        EnsureGridColumnDivider(parent, i, positions[i], h)
    end
    local dividers = parent._wnGridColDividers
    if dividers then
        for i = #positions + 1, #dividers do
            dividers[i]:Hide()
        end
    end
end

ns.UI_CHAR_ROW_COLUMNS = CHAR_ROW_COLUMNS
ns.UI_GetColumnOffset = GetColumnOffset
ns.UI_GetCharRowRightRailWidth = GetCharRowRightRailWidth
ns.UI_ComputeCharRowGuildColumnWidth = ComputeCharRowGuildColumnWidth
ns.UI_CHAR_ROW_RIGHT_MARGIN = CHAR_ROW_RIGHT_MARGIN
ns.UI_CHAR_ROW_RIGHT_GAP = CHAR_ROW_RIGHT_GAP
ns.UI_ResolveCharactersTabRowWidth = ResolveCharactersTabRowWidth
ns.UI_ComputeCharactersMinScrollWidth = ComputeCharactersMinScrollWidth
ns.UI_ComputeCharRowFlexColumns = ComputeCharRowFlexColumns
ns.UI_SyncGridColumnDividers = SyncGridColumnDividers
