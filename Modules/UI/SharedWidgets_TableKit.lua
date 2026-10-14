--[[
    Warband Nexus - SharedWidgets_TableKit (shared table / column-grid kit)
    Loaded after SharedWidgets_RowPool.lua (Factory:ApplyRowBackground) and before FramePoolFactory.lua
    (so also before PvEUI_ColumnPicker.lua and ProfessionsUI.lua, the column picker consumers).

    One column model, one header strip, one pooled row/cell set for every list surface.
    Metrics: ns.UI_LAYOUT.TABLE (SharedWidgets_Layout.lua).

    COLUMN DEFINITION (plain table, owned by the caller; the kit never mutates it):
        {
            key      = "honor",            -- unique per strip; header cells are pooled by key
            label    = "Honor",            -- header label ("\n" allowed in compact mode)
            icon     = "sort_up" | atlas | file path | fileID,  -- registry key first, then atlas, then file
            iconDef  = table,              -- optional opaque payload for opts.applyIcon (legacy resolvers)
            iconSize = 22,                 -- optional per-column header icon size
            iconSlot = true,               -- compact: keep the icon slot (label under it) even when no icon resolves
            width    = 80,                 -- fixed / base width (px)
            min      = 60,                 -- floor for width and for flex columns
            flex     = 1,                  -- >0 = share of leftover width (weight)
            align    = "LEFT" | "CENTER" | "RIGHT",
            sortable = true,
            cell     = "text" | "icon" | "money" | "signedMoney" | "status",   -- TK.PaintRowCells dispatch (default "text")
            tooltip  = "Honor",            -- header hover tooltip title
            tooltipIcon = atlas | file | fileID,  -- optional icon in the header hover tooltip
            tooltipIconIsAtlas = true,     -- tooltipIcon is an atlas name
            gapAfter = 6,                  -- optional gap (px) after this column, overrides the strip gap
        }

    WIDTHS
        local total = TK.ResolveWidths(cols, availW, outWidths, outOffsets, startX, gap)
            Fixed + min + flex distribution into caller-owned scratch tables (no allocation).
            outWidths[i] / outOffsets[i] are x positions relative to the strip/row left edge.
            startX (default 0) reserves a leading area (identity column); gap defaults TABLE.COL_GAP.
            col.gapAfter (number) replaces `gap` after that column only (ignored on the last column).
            availW = total strip width incl. startX; nil/0 = no flex growth (columns get their base width).
            Returns the span of the columns incl. inner gaps (excludes startX).
        local n = TK.BuildDividerXs(widths, offsets, n, outXs)
            Center x of each actual inter-column gap (n - 1 entries, honours gapAfter) for ns.UI_SyncGridColumnDividers.

    HEADER STRIP
        local strip = TK.CreateHeaderStrip(parent, opts)
            opts.mode           "compact" (icon over label, HEADER_H.compact) | "text" (one line, HEADER_H.text)
            opts.height         override strip height
            opts.iconSize       default header icon size (TABLE.ICON)
            opts.iconTop        compact: icon slot top inset (default TABLE.HEADER_ICON_TOP)
            opts.labelGap       compact: icon slot -> label gap (default TABLE.HEADER_LABEL_GAP)
            opts.labelRole      idle label role (default "Muted"); opts.activeLabelRole sorted column (default "Bright")
            opts.labelFont      FontManager category for header labels (default "small"); fixed per strip
            opts.labelColor     { r, g, b, a } idle label ink (theme-sourced table, read at paint time); replaces labelRole
            opts.labelColorFn   function() -> r, g, b, a idle label ink (e.g. ns.UI_GetAccentTextRGBA); wins over labelColor.
                                The sorted column still uses activeLabelRole. Ink is re-read on SetColumns / SetSort /
                                RefreshTheme, so pass a live palette accessor rather than a copied color.
            opts.dividers       true = grid dividers between columns (ns.UI_SyncGridColumnDividers)
            opts.bottomRule     true = 1px accent rule under the strip
            opts.onSortClick    function(key, ascending, strip) -- suggested direction; caller persists + calls SetSort
            opts.applyIcon      function(tex, col, size) -> drawn bool; custom icon resolver tried before col.icon
        strip:SetColumns(cols, widths, offsets, n)   -- n defaults to #cols; hides cells of keys not in cols
        strip:SetSort(key, ascending)                -- key nil clears; arrow uses registry sort_up / sort_down
        strip:GetStripHeight()
        strip:RefreshTheme()                         -- re-apply label ink / shadows / bottom rule after a theme toggle
        Caller anchors and sizes the strip (it is a plain Factory container).

    ROWS + CELLS
        local pool = TK.CreateRowPool(height)                -- once per surface
        local row = TK.AcquireRow(pool, parent, index, width, height, noHover)
            Pooled Button by index; zebra via Factory:ApplyRowBackground, hover via Factory:ApplyHighlight.
            Caller anchors the row (ClearAllPoints already done).
        TK.ReleaseRowsFrom(pool, fromIndex)                  -- hide rows >= fromIndex
        TK.SetTextCell(row, ci, x, w, align, text, role)     -- role default "Bright"; nil text = ""
        TK.SetIconCell(row, ci, x, w, align, icon, size)     -- icon spec as column `icon`
        TK.SetStatusCell(row, ci, x, w, align, statusKey, size)  -- "status_ok" | "status_fail" | "status_warn" | "status_pending"
        TK.SetMoneyCell(row, ci, x, w, align, copper, iconSize)  -- ns.UI_FormatMoney (default align RIGHT)
        TK.SetSignedMoneyCell(row, ci, x, w, align, copper, iconSize)
            Plain (uncolored) digits + coin icons, leading "-" when negative; whole cell inked with the theme
            semantic green (> 0) / red (< 0) via ns.UI_SetInkColor; 0 = "Normal" role. Default align RIGHT.
        TK.FormatSignedMoneyPlain(copper, iconSize) -> string   -- the formatter behind SetSignedMoneyCell
        TK.GetTextCell(row, ci) -> FontString | nil           -- the text cell at column ci (nil if none yet)
        TK.HideRowCellsFrom(row, fromCol)
        TK.PaintRowCells(row, cols, widths, offsets, n, rowData, valueFn)
            valueFn(col, rowData, ci) -> value, role[, r, g, b, a] ; dispatches on col.cell. Define valueFn once
            (no per-row closures). Text cells: when r is returned the cell is inked with ns.UI_SetInkColor(r, g, b, a)
            after the role is applied (class colors, semantic ink); ignored by icon / status / money kinds.
        TK.ApplyIcon(tex, icon, size) -> drawn bool

    COLUMN PICKER ("Columns" toolbar flyout; PvE + Professions adapters)
        local picker = TK.ColumnPicker.Create(spec)          -- once per surface, lazily
            spec.owner          table holding the frame refs (WarbandNexus) -- refs stay readable by legacy callers
            spec.menuRef        owner field for the menu frame      (e.g. "_wnPvEColumnPickerMenu")
            spec.anchorRef      owner field for the anchor button   (e.g. "_wnPvEColumnPickerAnchorBtn")
            spec.catcherRef     owner field for the click-catcher   (e.g. "_wnPvEColumnPickerCatcher")
            spec.catcherName    optional global frame name for the catcher
            spec.getRows(picker) -> { { key, label, checked, onToggle = fn(checked), reorder = false? }, ... } | nil
                                rows are sorted by getOrder rank; nil aborts the build (no profile yet)
            spec.getOrder(picker) -> live profile order array (drag reorder / reset mutate it in place)
            spec.getDefaultOrder(picker) -> defaultOrder, validSet   -- optional; enables "Reset Order"
            spec.showAll(picker)        -- optional; enables "Show All" (adapter flips its own visibility table)
            spec.getExtraSections(picker) -> { { title, rows = { row, ... } }, ... }   -- optional, non-reorderable
            spec.onChange(picker, reason, row)   -- reason "toggle" | "reorder" | "resetOrder" | "showAll"; persist + request tab refresh
            spec.isContextActive(picker) -> bool -- checked next frame; false closes the menu (tab switched / anchor gone)
            spec.width (320), spec.rowHeight (26), spec.maxHeight (80% UIParent), spec.menuPoint / spec.anchorPoint (TOPRIGHT / BOTTOMRIGHT)
        picker:Toggle(anchorBtn) / picker:Open(anchorBtn) / picker:Close() / picker:IsShown()
        picker:RefreshIfShown()      -- re-render after the owning tab redrew (call after updating the anchor ref)
        picker:Populate() / picker:Position(anchorBtn) / picker:ShowCatcher() / picker:GetMenu() / picker:GetAnchor()
        Menu: Factory container + accent border, FULLSCREEN_DIALOG 5100 (catcher 5050), themed checkbox per row,
        drag grip via ns.ColumnOrder.AttachPickerDragReorder, ESC via Factory:EnsureDropdownEscClose; hiding the
        menu by any path hides the catcher.
]]

local _, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
assert(ns.UI and ns.UI.Factory and ns.UI.Factory.ApplyRowBackground and ns.UI_LAYOUT and ns.UI_LAYOUT.TABLE,
    "SharedWidgets_RowPool.lua and SharedWidgets_Layout.lua must load before SharedWidgets_TableKit.lua")

local FontManager = ns.FontManager
local issecretvalue = issecretvalue

local TK = {}
ns.UI_TableKit = TK
ns.UI.TableKit = TK

local TABLE = ns.UI_LAYOUT.TABLE

-- Reused option tables (no allocation per paint).
local SORT_ACTIVE_OPTS = { vertexColor = nil }
local SORT_HOVER_OPTS = { alpha = 0.7 }
local ICON_CROP_L, ICON_CROP_R = 0.08, 0.92

TK.atlasExists = {}

-- ---------------------------------------------------------------------------
-- Widths
-- ---------------------------------------------------------------------------

function TK.ColumnBaseWidth(col)
    local w = col.width or 0
    local m = col.min or 0
    if m > w then w = m end
    return w
end

function TK.ResolveWidths(cols, availW, outWidths, outOffsets, startX, gap)
    local n = cols and #cols or 0
    startX = startX or 0
    gap = gap or TABLE.COL_GAP
    local fixed, flexSum, lastFlex, gaps = 0, 0, 0, 0
    for i = 1, n do
        local col = cols[i]
        local w = TK.ColumnBaseWidth(col)
        outWidths[i] = w
        fixed = fixed + w
        local f = col.flex
        if f and f > 0 then
            flexSum = flexSum + f
            lastFlex = i
        end
        if i < n then
            gaps = gaps + (col.gapAfter or gap)
        end
    end
    local leftover = (availW and availW > 0) and (availW - startX - fixed - gaps) or 0
    if leftover > 0 and flexSum > 0 then
        local given = 0
        for i = 1, n do
            local f = cols[i].flex
            if f and f > 0 then
                local share
                if i == lastFlex then
                    share = leftover - given
                else
                    share = math.floor(leftover * f / flexSum)
                end
                given = given + share
                outWidths[i] = outWidths[i] + share
            end
        end
        fixed = fixed + leftover
    end
    local x = startX
    for i = 1, n do
        outOffsets[i] = x
        x = x + outWidths[i] + (cols[i].gapAfter or gap)
    end
    -- Trim stale scratch entries from a previous, longer column set.
    for i = n + 1, #outWidths do outWidths[i] = nil end
    for i = n + 1, #outOffsets do outOffsets[i] = nil end
    return fixed + gaps
end

--- Gap midpoints come from the resolved offsets, so per-column gapAfter is honoured automatically.
function TK.BuildDividerXs(widths, offsets, n, outXs)
    local count = 0
    for i = 1, n - 1 do
        local rightEdge = offsets[i] + widths[i]
        count = count + 1
        outXs[count] = rightEdge + (offsets[i + 1] - rightEdge) * 0.5
    end
    for i = count + 1, #outXs do outXs[i] = nil end
    return count
end

-- ---------------------------------------------------------------------------
-- Icons
-- ---------------------------------------------------------------------------

function TK.AtlasExists(name)
    local v = TK.atlasExists[name]
    if v == nil then
        v = false
        if C_Texture and C_Texture.GetAtlasInfo then
            local ok, info = pcall(C_Texture.GetAtlasInfo, name)
            v = (ok and info) and true or false
        end
        TK.atlasExists[name] = v
    end
    return v
end

--- icon: registry key (ns.UI_ICONS) | atlas | file path | fileID. Returns true when something was drawn.
function TK.ApplyIcon(tex, icon, size)
    if not tex then return false end
    if size then tex:SetSize(size, size) end
    if icon == nil or icon == "" then
        tex:Hide()
        return false
    end
    if type(icon) == "number" then
        tex:SetTexture(icon)
        tex:SetTexCoord(ICON_CROP_L, ICON_CROP_R, ICON_CROP_L, ICON_CROP_R)
        if ns.UI_EnsureTextureFullColor then ns.UI_EnsureTextureFullColor(tex) end
        tex:Show()
        return true
    end
    if type(icon) ~= "string" then
        tex:Hide()
        return false
    end
    if ns.UI_ICONS and ns.UI_ICONS[icon] and ns.UI_SetIcon then
        if ns.UI_SetIcon(tex, icon) then
            tex:Show()
            return true
        end
        tex:Hide()
        return false
    end
    if TK.AtlasExists(icon) and tex.SetAtlas then
        tex:SetAtlas(icon, false)
        tex:SetVertexColor(1, 1, 1, 1)
        tex:Show()
        return true
    end
    tex:SetTexture(icon)
    tex:SetTexCoord(ICON_CROP_L, ICON_CROP_R, ICON_CROP_L, ICON_CROP_R)
    if ns.UI_EnsureTextureFullColor then ns.UI_EnsureTextureFullColor(tex) end
    tex:Show()
    return tex:GetTexture() ~= nil
end

-- ---------------------------------------------------------------------------
-- Header strip
-- ---------------------------------------------------------------------------

function TK.NewContainer(parent, w, h)
    local Factory = ns.UI and ns.UI.Factory
    local f = Factory and Factory.CreateContainer and Factory:CreateContainer(parent, w, h, false)
    if not f then
        f = CreateFrame("Frame", nil, parent)
        f:SetSize(w, h)
    end
    return f
end

function TK.ApplyHeaderLabelShadow(fs)
    if ns.UI_IsLightMode and ns.UI_IsLightMode() then
        fs:SetShadowOffset(0, 0)
        fs:SetShadowColor(0, 0, 0, 0)
    else
        fs:SetShadowOffset(1, -1)
        fs:SetShadowColor(0, 0, 0, 0.9)
    end
end

function TK.HeaderCellOnEnter(cell)
    local strip = cell._tkStrip
    if cell._tkSortable and strip and strip._sortKey ~= cell._tkKey then
        -- Preview what the first click will do (col.defaultAscending, default true).
        TK.ShowSortArrow(cell, cell._tkDefaultAscending and "sort_up" or "sort_down", SORT_HOVER_OPTS)
    end
    local tip = cell._tkTooltip
    if tip and tip ~= "" and ns.UI_ShowTooltip then
        local data = cell._tkTipData
        if not data then
            data = { type = "custom", title = tip, lines = {} }
            cell._tkTipData = data
        end
        data.title = tip
        data.icon = cell._tkTooltipIcon
        data.iconIsAtlas = cell._tkTooltipIconIsAtlas
        ns.UI_ShowTooltip(cell, data)
    end
end

function TK.HeaderCellOnLeave(cell)
    local strip = cell._tkStrip
    if strip then TK.ApplyCellSortVisual(strip, cell) end
    if cell._tkTooltip and ns.UI_HideTooltip then ns.UI_HideTooltip() end
end

function TK.HeaderCellOnMouseUp(cell, button)
    if button ~= "LeftButton" or not cell._tkSortable then return end
    local strip = cell._tkStrip
    if not strip or not strip._onSortClick then return end
    local key = cell._tkKey
    local ascending
    if strip._sortKey == key then
        ascending = not strip._sortAscending
    else
        ascending = cell._tkDefaultAscending
    end
    strip._onSortClick(key, ascending, strip)
end

function TK.CreateHeaderCell(strip, key)
    local cell = TK.NewContainer(strip, 1, strip._height)
    cell._tkStrip = strip
    cell._tkKey = key
    local holder = TK.NewContainer(cell, 1, 1)
    if holder.EnableMouse then holder:EnableMouse(false) end
    local iconTex = holder:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("CENTER", holder, "CENTER", 0, 0)
    cell._tkHolder = holder
    cell._tkIconTex = iconTex
    cell._tkLabel = FontManager:CreateFontString(cell, strip._labelFont, "OVERLAY")
    local arrow = cell:CreateTexture(nil, "OVERLAY")
    arrow:SetSize(TABLE.SORT_ARROW, TABLE.SORT_ARROW)
    arrow:Hide()
    cell._tkArrow = arrow
    cell:SetScript("OnEnter", TK.HeaderCellOnEnter)
    cell:SetScript("OnLeave", TK.HeaderCellOnLeave)
    cell:SetScript("OnMouseUp", TK.HeaderCellOnMouseUp)
    strip._cells[key] = cell
    return cell
end

--- Place the (shown) sort arrow: beside the icon in compact mode, else just after the label text.
function TK.PlaceSortArrow(cell)
    local arrow = cell._tkArrow
    arrow:ClearAllPoints()
    if cell._tkHasIcon then
        arrow:SetPoint("LEFT", cell._tkHolder, "RIGHT", 1, 0)
        return
    end
    local label = cell._tkLabel
    local align = cell._tkAlign
    if align == "RIGHT" then
        arrow:SetPoint("RIGHT", cell, "RIGHT", -TABLE.CELL_PAD_X, 0)
        return
    end
    local sw = label:GetStringWidth() or 0
    local lw = label:GetWidth() or sw
    if sw > lw then sw = lw end
    if align == "CENTER" then
        arrow:SetPoint("LEFT", label, "CENTER", sw * 0.5 + TABLE.SORT_ARROW_GAP, 0)
    else
        arrow:SetPoint("LEFT", label, "LEFT", sw + TABLE.SORT_ARROW_GAP, 0)
    end
end

function TK.ShowSortArrow(cell, iconKey, opts)
    if not ns.UI_SetIcon or not ns.UI_SetIcon(cell._tkArrow, iconKey, opts) then
        cell._tkArrow:Hide()
        return
    end
    TK.PlaceSortArrow(cell)
    cell._tkArrow:Show()
end

function TK.ApplyCellSortVisual(strip, cell)
    local active = cell._tkSortable and strip._sortKey ~= nil and strip._sortKey == cell._tkKey
    if active then
        local colors = ns.UI_COLORS
        SORT_ACTIVE_OPTS.vertexColor = colors and colors.accent or nil
        TK.ShowSortArrow(cell, strip._sortAscending and "sort_up" or "sort_down", SORT_ACTIVE_OPTS)
        SORT_ACTIVE_OPTS.vertexColor = nil
    else
        cell._tkArrow:Hide()
    end
    TK.ApplyHeaderLabelInk(strip, cell._tkLabel, active)
end

--- Idle labels take opts.labelColorFn / opts.labelColor when set, else the label role; the sorted column keeps activeLabelRole.
function TK.ApplyHeaderLabelInk(strip, label, active)
    if not active then
        local r, g, b, a
        local fn = strip._labelColorFn
        if fn then
            r, g, b, a = fn()
        end
        local c = strip._labelColor
        if r == nil and c then
            r, g, b, a = c[1], c[2], c[3], c[4]
        end
        if r ~= nil and ns.UI_SetInkColor then
            ns.UI_SetInkColor(label, r, g, b, a or 1)
            return
        end
    end
    if ns.UI_SetTextColorRole then
        ns.UI_SetTextColorRole(label, active and strip._activeLabelRole or strip._labelRole)
    end
end

function TK.LayoutCompactCell(strip, cell, col, w)
    local H = strip._height
    local label = cell._tkLabel
    local holder = cell._tkHolder
    local iconTex = cell._tkIconTex
    local hasIcon = (col.iconSlot == true) or (col.icon ~= nil) or (col.iconDef ~= nil)
    cell._tkHasIcon = hasIcon
    local text = col.label or ""
    local secret = issecretvalue and issecretvalue(text)
    label:ClearAllPoints()
    if hasIcon then
        local iconSize = col.iconSize or strip._iconSize
        holder:SetSize(iconSize + 4, iconSize + 4)
        holder:ClearAllPoints()
        holder:SetPoint("TOP", cell, "TOP", 0, -strip._iconTop)
        holder:Show()
        iconTex:SetSize(iconSize, iconSize)
        local drawn = false
        if strip._applyIcon then
            iconTex:SetTexture(nil)
            drawn = strip._applyIcon(iconTex, col, iconSize) and true or false
        end
        if not drawn then
            drawn = TK.ApplyIcon(iconTex, col.icon, iconSize)
        end
        if drawn then iconTex:Show() else iconTex:Hide() end
        local multiline = (not secret) and text:find("\n", 1, true) ~= nil
        label:SetPoint("TOP", holder, "BOTTOM", 0, -strip._labelGap)
        label:SetWidth(math.max(24, w - 4))
        label:SetJustifyH("CENTER")
        label:SetWordWrap(multiline)
        if label.SetJustifyV then label:SetJustifyV("TOP") end
    else
        holder:Hide()
        label:SetPoint("TOPLEFT", cell, "TOPLEFT", 4, 0)
        label:SetPoint("BOTTOMRIGHT", cell, "BOTTOMRIGHT", -4, 0)
        label:SetJustifyH(col.align or "LEFT")
        label:SetWordWrap(false)
        if label.SetJustifyV then label:SetJustifyV("MIDDLE") end
    end
    cell:SetSize(w, H)
end

function TK.LayoutTextCell(strip, cell, col, w)
    local pad = TABLE.CELL_PAD_X
    local label = cell._tkLabel
    cell._tkHasIcon = false
    cell._tkHolder:Hide()
    local reserve = col.sortable and (TABLE.SORT_ARROW + TABLE.SORT_ARROW_GAP) or 0
    label:ClearAllPoints()
    label:SetPoint("LEFT", cell, "LEFT", pad, 0)
    label:SetWidth(math.max(1, w - pad * 2 - reserve))
    label:SetJustifyH(col.align or "LEFT")
    label:SetWordWrap(false)
    if label.SetMaxLines then label:SetMaxLines(1) end
    if label.SetJustifyV then label:SetJustifyV("MIDDLE") end
    cell:SetSize(w, strip._height)
end

function TK.StripSetColumns(strip, cols, widths, offsets, n)
    n = n or #cols
    strip._cols = cols
    strip._n = n
    local gen = (strip._gen or 0) + 1
    strip._gen = gen
    local compact = strip._mode == "compact"
    for i = 1, n do
        local col = cols[i]
        local key = col.key
        local cell = strip._cells[key] or TK.CreateHeaderCell(strip, key)
        cell._tkGen = gen
        cell._tkSortable = col.sortable == true
        cell._tkDefaultAscending = col.defaultAscending ~= false
        cell._tkTooltip = col.tooltip
        cell._tkTooltipIcon = col.tooltipIcon
        cell._tkTooltipIconIsAtlas = col.tooltipIconIsAtlas == true
        cell._tkAlign = col.align or "LEFT"
        local w = widths[i] or TK.ColumnBaseWidth(col)
        cell:SetParent(strip)
        cell:ClearAllPoints()
        cell:SetPoint("TOPLEFT", strip, "TOPLEFT", offsets[i] or 0, 0)
        if compact then
            TK.LayoutCompactCell(strip, cell, col, w)
        else
            TK.LayoutTextCell(strip, cell, col, w)
        end
        local label = cell._tkLabel
        label:SetText(col.label or "")
        TK.ApplyHeaderLabelShadow(label)
        label:Show()
        if cell.EnableMouse then
            cell:EnableMouse(cell._tkSortable or (col.tooltip ~= nil and col.tooltip ~= ""))
        end
        TK.ApplyCellSortVisual(strip, cell)
        cell:Show()
    end
    for _, cell in pairs(strip._cells) do
        if cell._tkGen ~= gen then cell:Hide() end
    end
    if strip._dividers and ns.UI_SyncGridColumnDividers then
        TK.BuildDividerXs(widths, offsets, n, strip._divXs)
        ns.UI_SyncGridColumnDividers(strip, strip._divXs, strip._height)
    end
    if strip._rule then TK.ApplyStripRule(strip) end
end

function TK.StripSetSort(strip, key, ascending)
    strip._sortKey = key
    strip._sortAscending = ascending and true or false
    for _, cell in pairs(strip._cells) do
        if cell._tkGen == strip._gen then TK.ApplyCellSortVisual(strip, cell) end
    end
end

function TK.StripGetHeight(strip)
    return strip._height
end

--- Theme toggle: label ink (colorFn re-read), shadows and the bottom rule follow the live palette.
function TK.StripRefreshTheme(strip)
    for _, cell in pairs(strip._cells) do
        if cell._tkGen == strip._gen then
            TK.ApplyHeaderLabelShadow(cell._tkLabel)
            TK.ApplyCellSortVisual(strip, cell)
        end
    end
    if strip._rule then TK.ApplyStripRule(strip) end
end

function TK.ApplyStripRule(strip)
    local rule = strip._ruleTex
    if not rule then
        rule = strip:CreateTexture(nil, "ARTWORK")
        if ns.UI_SetRuleThickness then ns.UI_SetRuleThickness(rule, "horizontal", 1) else rule:SetHeight(1) end
        rule:SetPoint("BOTTOMLEFT", strip, "BOTTOMLEFT", 0, 0)
        rule:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", 0, 0)
        strip._ruleTex = rule
    end
    local colors = ns.UI_COLORS
    local ac = colors and colors.accent
    if not ac then
        rule:Hide()
        return
    end
    local ruleA = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.35 or 0.55
    rule:SetColorTexture(ac[1] * 0.28, ac[2] * 0.28, ac[3] * 0.28, ruleA)
    rule:Show()
end

function TK.CreateHeaderStrip(parent, opts)
    opts = opts or {}
    local mode = (opts.mode == "text") and "text" or "compact"
    local height = opts.height or TABLE.HEADER_H[mode]
    local strip = TK.NewContainer(parent, 1, height)
    strip:SetHeight(height)
    strip._mode = mode
    strip._height = height
    strip._iconSize = opts.iconSize or TABLE.ICON
    strip._iconTop = opts.iconTop or TABLE.HEADER_ICON_TOP
    strip._labelGap = opts.labelGap or TABLE.HEADER_LABEL_GAP
    strip._labelRole = opts.labelRole or "Muted"
    strip._activeLabelRole = opts.activeLabelRole or "Bright"
    strip._labelFont = opts.labelFont or "small"
    strip._labelColor = opts.labelColor
    strip._labelColorFn = opts.labelColorFn
    strip._dividers = opts.dividers == true
    strip._rule = opts.bottomRule == true
    strip._onSortClick = opts.onSortClick
    strip._applyIcon = opts.applyIcon
    strip._cells = {}
    strip._divXs = {}
    strip._gen = 0
    strip.SetColumns = TK.StripSetColumns
    strip.SetSort = TK.StripSetSort
    strip.GetStripHeight = TK.StripGetHeight
    strip.RefreshTheme = TK.StripRefreshTheme
    return strip
end

-- ---------------------------------------------------------------------------
-- Rows + cells
-- ---------------------------------------------------------------------------

function TK.CreateRowPool(height)
    return { rows = {}, height = height or TABLE.ROW_H.standard }
end

function TK.AcquireRow(pool, parent, index, width, height, noHover)
    height = height or pool.height
    local row = pool.rows[index]
    if not row then
        row = CreateFrame("Button", nil, parent)
        row._tkText = {}
        row._tkIcon = {}
        row._tkHover = false
        pool.rows[index] = row
    end
    row:SetParent(parent)
    row:SetSize(width, height)
    row:ClearAllPoints()
    local Factory = ns.UI and ns.UI.Factory
    if Factory then Factory:ApplyRowBackground(row, index) end
    if not noHover and not row._tkHover and Factory and Factory.ApplyHighlight then
        Factory:ApplyHighlight(row)
        row._tkHover = true
    end
    row:Show()
    return row
end

function TK.ReleaseRowsFrom(pool, fromIndex)
    local rows = pool and pool.rows
    if not rows then return end
    for i = fromIndex or 1, #rows do
        rows[i]:Hide()
    end
end

function TK.HideRowCellsFrom(row, fromCol)
    local texts, icons = row._tkText, row._tkIcon
    for i = fromCol, #texts do
        if texts[i] then texts[i]:Hide() end
    end
    for i = fromCol, #icons do
        if icons[i] then icons[i]:Hide() end
    end
end

function TK.SetTextCell(row, ci, x, w, align, text, role)
    local fs = row._tkText[ci]
    if not fs then
        -- Fill holes so the array stays dense for numeric loops.
        for i = #row._tkText + 1, ci - 1 do row._tkText[i] = false end
        fs = FontManager:CreateFontString(row, "body", "OVERLAY")
        fs:SetWordWrap(false)
        if fs.SetMaxLines then fs:SetMaxLines(1) end
        row._tkText[ci] = fs
    end
    local icon = row._tkIcon[ci]
    if icon then icon:Hide() end
    local pad = TABLE.CELL_PAD_X
    fs:ClearAllPoints()
    fs:SetPoint("LEFT", row, "LEFT", x + pad, 0)
    fs:SetWidth(math.max(1, w - pad * 2))
    fs:SetJustifyH(align or "LEFT")
    if ns.UI_SetTextColorRole then ns.UI_SetTextColorRole(fs, role or "Bright") end
    fs:SetText(text or "")
    fs:Show()
    return fs
end

function TK.AcquireIconTexture(row, ci)
    local tex = row._tkIcon[ci]
    if not tex then
        for i = #row._tkIcon + 1, ci - 1 do row._tkIcon[i] = false end
        tex = row:CreateTexture(nil, "ARTWORK")
        row._tkIcon[ci] = tex
    end
    local fs = row._tkText[ci]
    if fs then fs:Hide() end
    return tex
end

function TK.PlaceIcon(row, tex, x, w, align, size)
    tex:ClearAllPoints()
    if align == "CENTER" then
        tex:SetPoint("CENTER", row, "LEFT", x + w * 0.5, 0)
    elseif align == "RIGHT" then
        tex:SetPoint("RIGHT", row, "LEFT", x + w - TABLE.CELL_PAD_X, 0)
    else
        tex:SetPoint("LEFT", row, "LEFT", x + TABLE.CELL_PAD_X, 0)
    end
    tex:SetSize(size, size)
end

function TK.SetIconCell(row, ci, x, w, align, icon, size)
    size = size or TABLE.ICON
    local tex = TK.AcquireIconTexture(row, ci)
    TK.PlaceIcon(row, tex, x, w, align, size)
    TK.ApplyIcon(tex, icon, size)
    return tex
end

function TK.SetStatusCell(row, ci, x, w, align, statusKey, size)
    size = size or TABLE.ICON
    local tex = TK.AcquireIconTexture(row, ci)
    TK.PlaceIcon(row, tex, x, w, align or "CENTER", size)
    if statusKey and ns.UI_SetIcon and ns.UI_SetIcon(tex, statusKey) then
        tex:Show()
    else
        tex:Hide()
    end
    return tex
end

function TK.SetMoneyCell(row, ci, x, w, align, copper, iconSize)
    local text = ""
    if copper ~= nil and ns.UI_FormatMoney then
        text = ns.UI_FormatMoney(copper, iconSize or 12, true)
    end
    return TK.SetTextCell(row, ci, x, w, align or "RIGHT", text, "Bright")
end

function TK.GetTextCell(row, ci)
    local texts = row and row._tkText
    local fs = texts and texts[ci]
    if fs then return fs end
    return nil
end

local MONEY_PARTS = {}  -- scratch for TK.FormatSignedMoneyPlain
local COIN_ICON_FMT = "|TInterface\\MoneyFrame\\UI-%sIcon:%d:%d:0:0|t"

--- Signed money without embedded digit colors, so one ink (green / red) covers the whole amount.
--- Part rules mirror ns.UI_FormatMoney: gold when > 0, silver padded under gold, copper always when nothing else.
function TK.FormatSignedMoneyPlain(copper, iconSize)
    copper = tonumber(copper) or 0
    iconSize = iconSize or 12
    local sign = ""
    if copper < 0 then
        sign = "-"
        copper = -copper
    end
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local cop = math.floor(copper % 100)
    local n = 0
    if gold > 0 then
        local gs = ns.UI_FormatNumber and ns.UI_FormatNumber(gold) or tostring(gold)
        n = n + 1
        MONEY_PARTS[n] = gs .. string.format(COIN_ICON_FMT, "Gold", iconSize, iconSize)
    end
    if silver > 0 then
        n = n + 1
        MONEY_PARTS[n] = string.format((gold > 0) and "%02d" or "%d", silver) .. string.format(COIN_ICON_FMT, "Silver", iconSize, iconSize)
    end
    if cop > 0 or n == 0 then
        n = n + 1
        MONEY_PARTS[n] = string.format((n > 1) and "%02d" or "%d", cop) .. string.format(COIN_ICON_FMT, "Copper", iconSize, iconSize)
    end
    for i = n + 1, #MONEY_PARTS do MONEY_PARTS[i] = nil end
    return sign .. table.concat(MONEY_PARTS, " ")
end

function TK.SetSignedMoneyCell(row, ci, x, w, align, copper, iconSize)
    local value = tonumber(copper)
    local text = ""
    if value ~= nil then text = TK.FormatSignedMoneyPlain(value, iconSize or 12) end
    local fs = TK.SetTextCell(row, ci, x, w, align or "RIGHT", text, "Normal")
    if value and value ~= 0 and ns.UI_SetInkColor then
        local r, g, b, a
        if value > 0 then
            if ns.UI_GetSemanticGreenColor then r, g, b, a = ns.UI_GetSemanticGreenColor() end
        elseif ns.UI_GetSemanticRedColor then
            r, g, b, a = ns.UI_GetSemanticRedColor()
        end
        if r then ns.UI_SetInkColor(fs, r, g, b, a) end
    end
    return fs
end

function TK.PaintRowCells(row, cols, widths, offsets, n, rowData, valueFn)
    n = n or #cols
    for ci = 1, n do
        local col = cols[ci]
        local kind = col.cell or "text"
        local value, role, r, g, b, a = valueFn(col, rowData, ci)
        local x, w, align = offsets[ci], widths[ci], col.align
        if kind == "icon" then
            TK.SetIconCell(row, ci, x, w, align or "CENTER", value, col.iconSize)
        elseif kind == "status" then
            TK.SetStatusCell(row, ci, x, w, align, value, col.iconSize)
        elseif kind == "money" then
            TK.SetMoneyCell(row, ci, x, w, align, value)
        elseif kind == "signedMoney" then
            TK.SetSignedMoneyCell(row, ci, x, w, align, value)
        else
            local fs = TK.SetTextCell(row, ci, x, w, align, value, role)
            if r ~= nil and ns.UI_SetInkColor then ns.UI_SetInkColor(fs, r, g, b, a) end
        end
    end
    TK.HideRowCellsFrom(row, n + 1)
end

-- ---------------------------------------------------------------------------
-- Column picker ("Columns" toolbar flyout shared by PvE and Professions)
-- ---------------------------------------------------------------------------

-- Fullscreen dialog layer for interactive menus (avoid tooltip strata misuse).
local PICKER_STRATA = "FULLSCREEN_DIALOG"
local PICKER_MENU_LEVEL = 5100
local PICKER_CATCHER_LEVEL = 5050
local PICKER = { WIDTH = 320, ROW = 26, HEADER_H = 22, SECTION_H = 22, INSET_X = 14, BOTTOM_PAD = 10, ACTION_GAP = 4, SCREEN_FRACTION = 0.8 }
local PICKER_FALLBACK_ACCENT = { 0.40, 0.20, 0.58 }

local ColumnPicker = {}
ColumnPicker.__index = ColumnPicker
TK.ColumnPicker = ColumnPicker

function TK.PickerText(key, fallback)
    local L = ns.L
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback
end

function TK.PickerAccent()
    local colors = ns.UI_COLORS
    return (colors and colors.accent) or PICKER_FALLBACK_ACCENT
end

--- Skip ApplyVisuals on Blizzard template widgets (classic dropdown guards).
function TK.PickerApplyChrome(frame, bg, border)
    if not frame or not ns.UI_ApplyVisuals then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then return end
    ns.UI_ApplyVisuals(frame, bg, border)
end

function TK.PickerControlBackdrop()
    if ns.UI_GetControlChromeBackdrop then return ns.UI_GetControlChromeBackdrop() end
    local colors = ns.UI_COLORS or {}
    return colors.bgCard or colors.bgLight or colors.bg or { 0.08, 0.08, 0.10, 1 }
end

function TK.PickerControlHoverBackdrop()
    if ns.UI_GetControlChromeHoverBackdrop then return ns.UI_GetControlChromeHoverBackdrop() end
    local colors = ns.UI_COLORS or {}
    return colors.surfaceRowEven or colors.bgLight or colors.bg or { 0.10, 0.10, 0.12, 1 }
end

function TK.PickerHideTooltips()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    if ns.UI_HideTooltip then ns.UI_HideTooltip() end
end

function ColumnPicker.Create(spec)
    assert(type(spec) == "table" and spec.owner and spec.menuRef and spec.anchorRef and spec.catcherRef
        and spec.getRows and spec.getOrder,
        "TK.ColumnPicker.Create: owner, menuRef, anchorRef, catcherRef, getRows, getOrder are required")
    local picker = setmetatable({ spec = spec }, ColumnPicker)
    picker._onReorder = function() picker:NotifyChange("reorder") end
    return picker
end

function ColumnPicker:GetMenu()
    return self.spec.owner[self.spec.menuRef]
end

function ColumnPicker:GetAnchor()
    return self.spec.owner[self.spec.anchorRef]
end

function ColumnPicker:SetAnchor(anchorBtn)
    self.spec.owner[self.spec.anchorRef] = anchorBtn
end

function ColumnPicker:IsShown()
    local m = self:GetMenu()
    return (m and m:IsShown()) and true or false
end

function ColumnPicker:EnsureMenu()
    local spec = self.spec
    local m = spec.owner[spec.menuRef]
    if m then return m end
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateContainer then return nil end
    local w = spec.width or PICKER.WIDTH
    m = Factory:CreateContainer(UIParent, w, w, true)
    if not m then return nil end
    m:SetClampedToScreen(true)
    m:SetFrameStrata(PICKER_STRATA)
    m:SetFrameLevel(PICKER_MENU_LEVEL)
    m:EnableMouse(true)
    local accent = TK.PickerAccent()
    TK.PickerApplyChrome(m, TK.PickerControlBackdrop(), { accent[1], accent[2], accent[3], 1 })
    m:Hide()
    local picker = self
    -- Any hide path (ESC, toolbar re-click, close-all) also drops the click-catcher.
    m:HookScript("OnHide", function() picker:HideCatcher() end)
    spec.owner[spec.menuRef] = m
    if Factory.EnsureDropdownEscClose then
        Factory:EnsureDropdownEscClose(m)
    end
    return m
end

function ColumnPicker:HideCatcher()
    local c = self.spec.owner[self.spec.catcherRef]
    if c and c:IsShown() then c:Hide() end
end

function ColumnPicker:ShowCatcher()
    local spec = self.spec
    local menu = self:GetMenu()
    if not menu then return end
    local c = spec.owner[spec.catcherRef]
    if not c then
        -- Intentionally raw Button: invisible full-screen click-dismiss layer on UIParent (no chrome).
        c = CreateFrame("Button", spec.catcherName, UIParent)
        c:SetAllPoints(UIParent)
        c:SetAlpha(0)
        c:EnableMouse(true)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if c.SetPropagateMouseClicks then c:SetPropagateMouseClicks(false) end
        local picker = self
        c:SetScript("OnClick", function() picker:Close() end)
        spec.owner[spec.catcherRef] = c
    end
    c:SetFrameStrata(PICKER_STRATA)
    c:SetFrameLevel(PICKER_CATCHER_LEVEL)
    c:Show()
    menu:SetFrameStrata(PICKER_STRATA)
    menu:SetFrameLevel(PICKER_MENU_LEVEL)
    menu:Raise()
end

function ColumnPicker:Close()
    self:HideCatcher()
    local m = self:GetMenu()
    if m then m:Hide() end
end

function ColumnPicker:Position(anchorBtn)
    local menu = self:GetMenu()
    anchorBtn = anchorBtn or self:GetAnchor()
    if not menu or not anchorBtn then return end
    local spec = self.spec
    menu:ClearAllPoints()
    menu:SetPoint(spec.menuPoint or "TOPRIGHT", anchorBtn, spec.anchorPoint or "BOTTOMRIGHT", 0, -4)
end

--- Rebuild + position + show (menu and catcher) against the stored anchor.
function ColumnPicker:Present()
    local menu = self:GetMenu()
    local anchor = self:GetAnchor()
    if not menu or not anchor then return end
    self:Populate()
    self:Position(anchor)
    TK.PickerHideTooltips()
    menu:Show()
    self:ShowCatcher()
end

function ColumnPicker:Open(anchorBtn)
    if anchorBtn then self:SetAnchor(anchorBtn) end
    if not self:EnsureMenu() then return end
    self:Present()
end

function ColumnPicker:Toggle(anchorBtn)
    if anchorBtn then self:SetAnchor(anchorBtn) end
    if self:IsShown() then
        self:Close()
        return
    end
    self:Open()
end

--- Re-render an open picker after its tab redrew (anchor button may have been recreated).
function ColumnPicker:RefreshIfShown()
    if not self:IsShown() then return end
    self:Present()
end

--- Called after every mutation (toggle / reorder / resetOrder / showAll). The adapter persists
--- side effects + requests its tab refresh in spec.onChange; the open menu re-renders next frame.
function ColumnPicker:NotifyChange(reason, row)
    TK.PickerHideTooltips()
    local spec = self.spec
    if spec.onChange then spec.onChange(self, reason, row) end
    if not (C_Timer and C_Timer.After) then return end
    local picker = self
    C_Timer.After(0, function()
        if not picker:IsShown() then return end
        if spec.isContextActive and not spec.isContextActive(picker) then
            picker:Close()
            return
        end
        picker:RefreshIfShown()
    end)
end

function ColumnPicker:ClearMenuChildren(menu)
    local bin = ns.UI_RecycleBin
    local children = { menu:GetChildren() }
    for i = 1, #children do
        children[i]:Hide()
        if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
    end
end

function ColumnPicker:AddCheckboxRow(host, y, width, row, order)
    local Factory = ns.UI.Factory
    local ROW = self.spec.rowHeight or PICKER.ROW
    local rowHost = Factory:CreateContainer(host, width, ROW, false)
    if not rowHost then return y end
    rowHost:SetPoint("TOPLEFT", host, "TOPLEFT", 0, y)
    local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(rowHost, row.checked and true or false)
    if not cb then return y - ROW end
    cb:SetPoint("LEFT", rowHost, "LEFT", PICKER.INSET_X, 0)
    cb:EnableMouse(true)
    local lbl = FontManager:CreateFontString(rowHost, "body", "OVERLAY")
    lbl:SetPoint("LEFT", cb, "RIGHT", (ns.UI_SPACING and ns.UI_SPACING.AFTER_ELEMENT) or 6, 0)
    lbl:SetText(row.label or "")
    if ns.UI_SetTextColorRole then ns.UI_SetTextColorRole(lbl, "Bright") end
    lbl:SetJustifyH("LEFT")
    if lbl.EnableMouse then lbl:EnableMouse(false) end
    local picker = self
    local prevClick = cb:GetScript("OnClick")
    cb:SetScript("OnClick", function(btn, ...)
        if prevClick then prevClick(btn, ...) end
        if row.onToggle then row.onToggle(btn:GetChecked() and true or false) end
        picker:NotifyChange("toggle", row)
    end)
    local ColumnOrder = ns.ColumnOrder
    if order and row.reorder ~= false and ColumnOrder and ColumnOrder.AttachPickerDragReorder then
        ColumnOrder.AttachPickerDragReorder(rowHost, order, row.key, self._onReorder, { label = row.label })
    end
    return y - ROW
end

function ColumnPicker:AddSectionHeader(host, y, text)
    local hdr = FontManager:CreateFontString(host, "small", "OVERLAY")
    hdr:SetPoint("TOPLEFT", host, "TOPLEFT", PICKER.INSET_X, y - 8)
    hdr:SetText(text or "")
    local accent = TK.PickerAccent()
    hdr:SetTextColor(accent[1], accent[2], accent[3], 1)
    if hdr.EnableMouse then hdr:EnableMouse(false) end
    return y - PICKER.SECTION_H
end

function ColumnPicker:AddActionButton(host, y, width, text, onClick)
    local Factory = ns.UI.Factory
    local ROW = self.spec.rowHeight or PICKER.ROW
    local btn = Factory:CreateButton(host, width - PICKER.INSET_X * 2, ROW - 2, false)
    if not btn then return y end
    local accent = TK.PickerAccent()
    TK.PickerApplyChrome(btn, TK.PickerControlHoverBackdrop(), { accent[1], accent[2], accent[3], 0.5 })
    btn:SetPoint("TOPLEFT", host, "TOPLEFT", PICKER.INSET_X, y - PICKER.ACTION_GAP)
    local lbl = FontManager:CreateFontString(btn, "small", "OVERLAY")
    lbl:SetPoint("CENTER", 0, 0)
    local hex = (ns.UI_GetAccentHexColor and ns.UI_GetAccentHexColor()) or "aaaaee"
    lbl:SetText("|cff" .. hex .. text .. "|r")
    if lbl.EnableMouse then lbl:EnableMouse(false) end
    btn:SetScript("OnClick", onClick)
    if Factory.ApplyHighlight then Factory:ApplyHighlight(btn) end
    return y - ROW - PICKER.ACTION_GAP
end

--- Rebuild scroll contents from the adapter. Caller positions + shows menu and catcher.
function ColumnPicker:Populate()
    local spec = self.spec
    local menu = self:GetMenu()
    local Factory = ns.UI and ns.UI.Factory
    if not menu or not Factory then return end
    local rows = spec.getRows(self)
    if type(rows) ~= "table" then return end
    local order = spec.getOrder(self)
    local sections = spec.getExtraSections and spec.getExtraSections(self) or nil

    if type(order) == "table" then
        local rank = {}
        for ri = 1, #order do rank[order[ri]] = ri end
        table.sort(rows, function(a, b)
            return (rank[a.key] or 9999) < (rank[b.key] or 9999)
        end)
    end

    local ROW = spec.rowHeight or PICKER.ROW
    local menuW = spec.width or PICKER.WIDTH
    local dl = Factory.GetDropdownLayout and Factory:GetDropdownLayout() or {}
    local menuPad = dl.menuEdge or 4
    local scrollBarW = dl.scrollBarW or 26
    local hasResetOrder = spec.getDefaultOrder ~= nil and type(order) == "table"
    local hasShowAll = spec.showAll ~= nil

    local contentH = PICKER.HEADER_H + #rows * ROW + PICKER.BOTTOM_PAD
    if sections then
        for si = 1, #sections do
            contentH = contentH + PICKER.SECTION_H + #(sections[si].rows or {}) * ROW
        end
    end
    if hasResetOrder then contentH = contentH + ROW + PICKER.ACTION_GAP end
    if hasShowAll then contentH = contentH + ROW + PICKER.ACTION_GAP end
    -- Show every toggle; only scroll when the list would not fit on screen.
    local maxH = spec.maxHeight or math.floor((UIParent:GetHeight() or 768) * PICKER.SCREEN_FRACTION)
    local viewportInnerH = math.min(contentH, math.max(ROW * 4, maxH - 2 * menuPad))

    menu:SetSize(menuW, viewportInnerH + 2 * menuPad)
    menu:SetParent(UIParent)
    self:ClearMenuChildren(menu)

    local sbLane = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve()) or (scrollBarW + 2)
    local scrollFrame = Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", menuPad, -menuPad)
    scrollFrame:SetPoint("BOTTOMRIGHT", menu, "BOTTOMRIGHT", -sbLane, menuPad)
    scrollFrame:EnableMouseWheel(true)

    local scrollBarColumn = Factory.CreateBareScrollBarColumn and Factory:CreateBareScrollBarColumn(menu, scrollBarW)
        or Factory:CreateScrollBarColumn(menu, scrollBarW, 0, 0)
    if Factory.EnsureScrollBarColumnSync then
        Factory:EnsureScrollBarColumnSync(scrollFrame, scrollBarColumn, {
            width = scrollBarW,
            gap = math.max(0, sbLane - scrollBarW),
        })
    elseif scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end
    if Factory.WireScrollBarColumnLayout then
        Factory:WireScrollBarColumnLayout(scrollFrame, menu, scrollBarColumn, { menuEdge = menuPad })
    end

    local btnWidth = menuW - menuPad * 2 - sbLane
    local scrollChild = TK.NewContainer(scrollFrame, btnWidth, contentH)
    scrollChild:SetWidth(btnWidth)
    scrollChild:SetHeight(contentH)
    scrollFrame:SetScrollChild(scrollChild)

    local logicalRows = math.max(1, math.ceil(contentH / ROW))
    scrollFrame._wnDropdownRowCount = logicalRows
    scrollFrame._wnDropdownMaxVisible = math.max(1, math.ceil(viewportInnerH / ROW))
    scrollFrame._wnDropdownViewportH = viewportInnerH

    if Factory.UpdateScrollBarVisibility then Factory:UpdateScrollBarVisibility(scrollFrame) end
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Factory.UpdateScrollBarVisibility and scrollFrame then
                Factory:UpdateScrollBarVisibility(scrollFrame)
            end
        end)
    end

    self:AddSectionHeader(scrollChild, 0, spec.title or TK.PickerText("COLUMNS_BUTTON", "Columns"))

    local y = -PICKER.HEADER_H
    for ri = 1, #rows do
        y = self:AddCheckboxRow(scrollChild, y, btnWidth, rows[ri], order)
    end
    if sections then
        for si = 1, #sections do
            local sec = sections[si]
            y = self:AddSectionHeader(scrollChild, y, sec.title)
            local secRows = sec.rows or {}
            for ri = 1, #secRows do
                y = self:AddCheckboxRow(scrollChild, y, btnWidth, secRows[ri], nil)
            end
        end
    end

    local picker = self
    if hasResetOrder then
        y = self:AddActionButton(scrollChild, y, btnWidth, TK.PickerText("RESET_COLUMN_ORDER", "Reset Order"), function()
            local ColumnOrder = ns.ColumnOrder
            if ColumnOrder then
                local defaults, validSet = spec.getDefaultOrder(picker)
                ColumnOrder.ResetToDefault(order, defaults or {}, validSet)
            end
            picker:NotifyChange("resetOrder")
        end)
    end
    if hasShowAll then
        y = self:AddActionButton(scrollChild, y, btnWidth, TK.PickerText("SHOW_ALL", "Show All"), function()
            spec.showAll(picker)
            picker:NotifyChange("showAll")
        end)
    end

    if Factory.UpdateScrollBarVisibility then
        local fh = scrollFrame:GetHeight()
        if fh and fh > 0 then
            local slack = (ns.UI_LAYOUT and ns.UI_LAYOUT.DROPDOWN_SCROLL_FIT_SLACK) or 8
            local ch = scrollChild:GetHeight() or 0
            if ch > fh and ch <= fh + slack then
                scrollChild:SetHeight(fh)
            end
        end
        Factory:UpdateScrollBarVisibility(scrollFrame)
    end
end
