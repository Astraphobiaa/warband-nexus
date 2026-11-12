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
        spacing = 10,
        total = 110,
    },
    -- `min` = readability floor for flex columns: narrow viewports shrink these toward min
    -- (proportional) before the horizontal scrollbar takes over.
    guild = {
        width = 130,
        spacing = 10,
        total = 140,
        min = 60,
    },
    level = {
        width = 82,
        spacing = 10,
        total = 92,
        min = 70,   -- "Zzz 150.00%" rested line
    },
    itemLevel = {
        width = 82,
        spacing = 10,
        total = 92,
        min = 74,   -- "iLvl 288.9"
    },
    gold = {
        -- 190 was padding: `min` already states that 150 fits three coin groups at FormatMoney's
        -- 12-char cap, and the text is right-justified, so the slack showed up as a hole to the
        -- LEFT of the money rather than around it.
        width = 160,
        spacing = 10,
        total = 170,
        min = 150,  -- three coin groups at FormatMoney's 12-char cap
    },
    professions = {
        width = 150,
        spacing = 0,
        total = 150,
        min = 128,  -- 3 icons x 39 + 2 x 5 gaps
    },
    -- WoW Forever only: the realm is a PvE / PvP / RP tag rather than a name, so it gets a
    -- column of its own and the identity block's second line carries the surname instead.
    realmType = {
        width = 54,
        spacing = 10,
        total = 64,
        min = 40,
    },
    -- WoW Forever only (see CHAR_ROW_OPTIONAL_COLUMNS). Skills shows how many abilities are
    -- waiting at the trainer; Talents shows points per tab the way a vanilla build is read.
    -- One icon each, the same 39 px square the profession icons use, and sitting the same 5 px
    -- apart, so the two read as one pair of glyphs rather than two stray columns. Only the second
    -- one carries the wider trailing gap out to whatever follows.
    skills = {
        width = 39,
        spacing = 5,    -- the profession strip's own icon gap
        total = 44,
        min = 39,       -- never smaller than the glyph: the icon would overlap its neighbour
    },
    talents = {
        width = 39,
        spacing = 15,
        total = 54,
        min = 39,
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
    -- Level leads the text block, then the identity (name, guild) and the mail badge beside it.
    -- Only Guild has a measured width, so everything after it is chained off that rather than
    -- read from this order; see ApplyCharacterRowInteriorLayout.
    "favorite", "faction", "race", "class", "level", "name", "guild", "mail", "realmType",
    "itemLevel", "gold", "professions", "skills", "talents", "mythicKey",
    "reorder", "lastSeen", "headerAssign", "tracking", "delete",
}

--- Columns that only mean something where their system exists. On WoW Forever Mythic+ does not,
--- so the Keystone column collapses to zero width and the chained offsets close the gap by
--- themselves. The item level column is NOT in here: GetAverageItemLevel misreports there, but
--- the per-item levels behind it are sound, so DataService computes the average itself rather
--- than the column being hidden.
local CHAR_ROW_OPTIONAL_COLUMNS = {
    mythicKey = "mythicPlus",
    skills = "trainedSpells",
    talents = "classicTalentTree",
    realmType = "realmTypeTag",
}
-- The profession strip is a fixed five slots where the vanilla secondary set exists: two
-- primaries, then Cooking, Fishing and First Aid, each keeping its place whether or not the
-- character has it. Five 39 px squares with 5 px between them need 215. Everywhere else the
-- column keeps the width it has always had, so retail's row does not move.
local PROF_SLOT_ICON = 39
local PROF_SLOT_GAP = 5
local PROF_SLOTS_CLASSIC = 5

local function CharRowProfessionColumnWidth()
    local addon = ns.WarbandNexus
    if addon and addon.SupportsFeature and addon:SupportsFeature("firstAidProfession") then
        return PROF_SLOTS_CLASSIC * PROF_SLOT_ICON + (PROF_SLOTS_CLASSIC - 1) * PROF_SLOT_GAP
    end
    return CHAR_ROW_COLUMNS.professions.width
end
ns.UI_CharRowProfessionColumnWidth = CharRowProfessionColumnWidth

local function CharRowProfessionColumnTotal()
    return CharRowProfessionColumnWidth() + (CHAR_ROW_COLUMNS.professions.spacing or 0)
end

local function CharRowColumnEnabled(key)
    local feature = CHAR_ROW_OPTIONAL_COLUMNS[key]
    if not feature then return true end
    local addon = ns.WarbandNexus
    if addon and addon.SupportsFeature then
        return addon:SupportsFeature(feature)
    end
    return true
end
ns.UI_CharRowColumnEnabled = CharRowColumnEnabled

local function GetColumnOffset(columnKey)
    local offset = 10
    for oi = 1, #CHAR_ROW_COLUMN_ORDER do
        local key = CHAR_ROW_COLUMN_ORDER[oi]
        if key == columnKey then
            return offset
        end
        -- A collapsed column contributes nothing, so the ones after it move up. This only
        -- started mattering when an optional column landed BEFORE others in the order
        -- (realmType); the earlier ones were all at the tail.
        if CharRowColumnEnabled(key) then
            offset = offset + (key == "professions" and CharRowProfessionColumnTotal()
                or CHAR_ROW_COLUMNS[key].total)
        end
    end
    return offset
end


local function GetCharRowTotalWidth()
    local width = 10
    for oi = 1, #CHAR_ROW_COLUMN_ORDER do
        local key = CHAR_ROW_COLUMN_ORDER[oi]
        if CharRowColumnEnabled(key) then
            width = width + (key == "professions" and CharRowProfessionColumnTotal()
                or CHAR_ROW_COLUMNS[key].total)
        end
    end
    return width + 10
end

--- Name column width.
---
--- This used to widen to 165 px on WoW Forever so "Elementalist Vhorzen" fit on one line. It no
--- longer has to: the surname moved onto the identity block's second line (where the realm used
--- to sit, now a column of its own), so the widest line is a single word again. Widening also
--- disagreed with the column's own `total`, which the offset chain is built from -- the name
--- text ran 65 px into whatever came next.
local function CharRowNameWidth()
    return CHAR_ROW_COLUMNS.name.width
end
ns.UI_CharRowNameWidth = CharRowNameWidth

local function CharRowMythicKeyEnabled()
    return CharRowColumnEnabled("mythicKey")
end
ns.UI_CharRowMythicKeyEnabled = CharRowMythicKeyEnabled

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
        + CharRowProfessionColumnTotal()
        + (CharRowColumnEnabled("realmType") and (c.realmType and c.realmType.total or 66) or 0)
        + (CharRowColumnEnabled("skills") and (c.skills and c.skills.total or 72) or 0)
        + (CharRowColumnEnabled("talents") and (c.talents and c.talents.total or 104) or 0)
        + (CharRowColumnEnabled("mythicKey") and (c.mythicKey and c.mythicKey.total or 135) or 0)
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

local CHAR_ROW_FLEX_ORDER = { "level", "itemLevel", "gold", "professions", "skills", "talents", "mythicKey" }

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
        professions = CharRowProfessionColumnWidth(),
        realmType = CharRowColumnEnabled("realmType") and c.realmType.width or 0,
        skills = CharRowColumnEnabled("skills") and c.skills.width or 0,
        talents = CharRowColumnEnabled("talents") and c.talents.width or 0,
        mythicKey = CharRowColumnEnabled("mythicKey") and c.mythicKey.width or 0,
    }
    if not rowW or rowW < 1 then return out end
    local deficit = GetCharRowTotalWidthForGuild(out.guild) - rowW
    if deficit <= 0 then return out end
    -- A collapsed column has no width to give and must not be handed any back: writing
    -- out[key] unconditionally below would resurrect a hidden column as soon as the row got
    -- narrow enough to have a deficit.
    local slack = 0
    for i = 1, #CHAR_ROW_FLEX_ORDER do
        local key = CHAR_ROW_FLEX_ORDER[i]
        if CharRowColumnEnabled(key) then
            local col = c[key]
            slack = slack + math.max(0, col.width - (col.min or col.width))
        end
    end
    if slack <= 0 then return out end
    local ratio = math.min(1, deficit / slack)
    for i = 1, #CHAR_ROW_FLEX_ORDER do
        local key = CHAR_ROW_FLEX_ORDER[i]
        if CharRowColumnEnabled(key) then
            local col = c[key]
            local give = math.max(0, col.width - (col.min or col.width)) * ratio
            out[key] = math.floor(col.width - give + 0.5)
        end
    end
    return out
end

local function GetCharRowTotalWidthAtMinimums()
    local width = 10
    for oi = 1, #CHAR_ROW_COLUMN_ORDER do
        local key = CHAR_ROW_COLUMN_ORDER[oi]
        if CharRowColumnEnabled(key) then
            local col = CHAR_ROW_COLUMNS[key]
            if key == "professions" then
                width = width + CharRowProfessionColumnTotal()
            else
                local w = (col.min or col.width) + (col.spacing or 0)
                width = width + math.min(col.total, w)
            end
        end
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
    if ns.UI_SetRuleThickness then ns.UI_SetRuleThickness(divider, "vertical", 1) else divider:SetWidth(1) end
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

--- Average item level for roster cells at one decimal ("206.1"). Truncates rather than rounds
--- (206.97 -> "206.9") so the cell never reads above the real equipped average; the epsilon
--- absorbs float noise (206.1 * 10 = 2060.9999...).
---@param itemLevel number|nil Raw fractional GetAverageItemLevel() value
---@return string|nil
local function FormatCharRowItemLevel(itemLevel)
    local n = tonumber(itemLevel)
    if not n then return nil end
    return string.format("%.1f", math.floor(n * 10 + 1e-6) / 10)
end

ns.UI_CHAR_ROW_COLUMNS = CHAR_ROW_COLUMNS
ns.UI_FormatCharRowItemLevel = FormatCharRowItemLevel
ns.UI_GetColumnOffset = GetColumnOffset
ns.UI_GetCharRowRightRailWidth = GetCharRowRightRailWidth
ns.UI_ComputeCharRowGuildColumnWidth = ComputeCharRowGuildColumnWidth
ns.UI_CHAR_ROW_RIGHT_MARGIN = CHAR_ROW_RIGHT_MARGIN
ns.UI_CHAR_ROW_RIGHT_GAP = CHAR_ROW_RIGHT_GAP
ns.UI_ResolveCharactersTabRowWidth = ResolveCharactersTabRowWidth
ns.UI_ComputeCharactersMinScrollWidth = ComputeCharactersMinScrollWidth
ns.UI_ComputeCharRowFlexColumns = ComputeCharRowFlexColumns
ns.UI_SyncGridColumnDividers = SyncGridColumnDividers
