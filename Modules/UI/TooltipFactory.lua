--[[
    Warband Nexus - Tooltip Factory
    UI frame creation for custom tooltips
    
    Layout:
    ┌──────────────────────────────────┐
    │ [Icon]  Title                    │
    │         Description (optional)   │
    │─────────────────────────────────│
    │ Data lines...                    │
    │ Left:                     Right  │
    └──────────────────────────────────┘
    
    Follows SharedWidgets pattern:
    - Theme-aware styling
    - Frame pooling and recycling
    - Consistent visual design
]]

local ADDON_NAME, ns = ...
local FontManager = ns.FontManager  -- Centralized font management

--- SharedWidgets sets `ns.UI_SPACING`; never capture nil at file load (TOC/embed order can defer assignment).
local function GetTooltipUISpacing()
    local sp = ns.UI_SPACING or ns.UI_LAYOUT
    if sp then return sp end
    return { SIDE_MARGIN = 10, TOP_MARGIN = 8, AFTER_ELEMENT = 8 }
end

-- ============================================================================
-- TOOLTIP FACTORY
-- ============================================================================

ns.UI = ns.UI or {}
ns.UI.TooltipFactory = {}

-- Cache colors (updated on theme change)
local COLORS = nil

-- Layout constants
local ICON_SIZE = 32
local ICON_PADDING = 8
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"

local function TintTooltipAccentLines(frame)
    if not frame then return end
    local c = ns.UI_COLORS or COLORS or {}
    local ac = c.accent or { 0.45, 0.35, 0.72 }
    if frame.separator then
        frame.separator:SetColorTexture(ac[1], ac[2], ac[3], 0.42)
    end
    if frame.iconFrame and frame.iconFrame.border then
        frame.iconFrame.border:SetColorTexture(ac[1], ac[2], ac[3], 0.42)
    end
end

-- Wide tooltips (e.g. PvE vault summary): TooltipService may preset frame.fixedWidth before layout.
local WIDTH_CAP_TOP = 820
local VAULT_GRID_GAP_NAME_REALM = 10
local VAULT_GRID_GAP_BEFORE_VAULT = 12
local VAULT_GRID_GAP_VAULT_COL = 6
-- Minimum width per Raid/M+/World column (three slot icons or “Pending…”).
local VAULT_GRID_TRACK_MIN_W = 72
local VAULT_TRACK_GAP_COL = 10

--[[
    Create singleton tooltip frame
    @return Frame - Reusable tooltip frame
]]
function ns.UI.TooltipFactory:CreateTooltipFrame()
    -- Get current theme colors
    COLORS = ns.UI_COLORS or {
        bgCard = {0.08, 0.08, 0.10, 1},
        border = {0.20, 0.20, 0.25, 1},
        accent = {0.45, 0.35, 0.72},
    }
    
    -- Create frame
    local frame = CreateFrame("Frame", "WarbandNexusTooltip", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(10000)
    frame:SetSize(250, 100)
    frame:Hide()
    
    -- Phase 2: elevated surface + atlas underlay + accent inset border (parity with tab cards).
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    else
        frame:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8",
            edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        frame:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 0.98)
        frame:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
    end
    
    -- Icon (top-left, created once, reused)
    local iconFrame = CreateFrame("Frame", nil, frame)
    iconFrame:SetSize(ICON_SIZE, ICON_SIZE)
    
    local iconTexture = iconFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetAllPoints()
    iconTexture:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconFrame.texture = iconTexture
    
    -- Icon border (thin accent border)
    local iconBorder = iconFrame:CreateTexture(nil, "OVERLAY")
    iconBorder:SetPoint("TOPLEFT", -1, 1)
    iconBorder:SetPoint("BOTTOMRIGHT", 1, -1)
    iconFrame.border = iconBorder
    
    -- Icon sits behind the texture (border effect)
    iconTexture:SetDrawLayer("ARTWORK", 1)
    iconBorder:SetDrawLayer("ARTWORK", 0)
    
    frame.iconFrame = iconFrame
    
    -- Separator line (thin horizontal line between header and body)
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    frame.separator = separator
    
    TintTooltipAccentLines(frame)
    
    -- FontString pools (recycled for performance)
    frame.lines = {}
    frame.linePool = {}
    frame.doubleLines = {}
    frame.doubleLinePool = {}
    frame.vaultGridRows = {}
    frame.vaultGridLinePool = {}
    frame.vaultTrackRows = {}
    frame.vaultTrackLinePool = {}
    frame.titleLine = nil
    frame.descLine = nil
    frame.titleAffixLines = {}
    frame.hasTitleAffixPair = false
    frame.titleAffixPairLeft = nil
    frame.titleAffixPairRight = nil
    frame.bodyDividerPool = {}
    frame.allLines = {}
    frame._balancedSplit = nil
    frame._deferLayout = false
    frame._layoutDirty = false

    local function RequestLayout(tooltipFrame)
        if tooltipFrame._deferLayout then
            tooltipFrame._layoutDirty = true
            return
        end
        tooltipFrame:LayoutLines()
    end

    frame.BeginBatchLayout = function(self)
        self._deferLayout = true
        self._layoutDirty = false
    end

    frame.EndBatchLayout = function(self)
        self._deferLayout = false
        RequestLayout(self)
        self._layoutDirty = false
    end
    
    -- Layout state (dynamic width, clamped to min/max)
    local MIN_WIDTH = 120
    local MAX_WIDTH = 450
    frame.currentHeight = 10
    frame.fixedWidth = 350
    local spacing = GetTooltipUISpacing()
    frame.paddingH = spacing.SIDE_MARGIN + 2
    frame.paddingV = spacing.SIDE_MARGIN
    frame.hasIcon = false
    
    -- ========================================================================
    -- API: Clear all content
    -- ========================================================================
    frame.Clear = function(self)
        -- Hide icon
        self.iconFrame:Hide()
        self.hasIcon = false
        self.separator:Hide()
        
        -- Hide and clear title line
        if self.titleLine then
            self.titleLine:Hide()
            self.titleLine:SetText("")
            self.titleLine:ClearAllPoints()
        end
        
        -- Hide and clear description line
        if self.descLine then
            self.descLine:Hide()
            self.descLine:SetText("")
            self.descLine:ClearAllPoints()
        end

        for i = 1, #self.titleAffixLines do
            local tLine = self.titleAffixLines[i]
            tLine:Hide()
            tLine:SetText("")
            tLine:ClearAllPoints()
            table.insert(self.linePool, tLine)
        end
        table.wipe(self.titleAffixLines)

        if self.titleAffixPairLeft then
            self.titleAffixPairLeft:Hide()
            self.titleAffixPairRight:Hide()
            self.titleAffixPairLeft:SetText("")
            self.titleAffixPairRight:SetText("")
            self.titleAffixPairLeft:ClearAllPoints()
            self.titleAffixPairRight:ClearAllPoints()
        end
        self.hasTitleAffixPair = false
        for i = 1, #self.bodyDividerPool do
            local div = self.bodyDividerPool[i]
            if div then
                div:Hide()
                div:ClearAllPoints()
            end
        end
        self._balancedSplit = nil
        
        -- Return all lines to pool
        for i = 1, #self.lines do
            local line = self.lines[i]
            line:Hide()
            line:SetText("")
            line:ClearAllPoints()
            if line.SetJustifyH then
                line:SetJustifyH("LEFT")
            end
            table.insert(self.linePool, line)
        end
        table.wipe(self.lines)
        
        -- Return double lines to pool
        for i = 1, #self.doubleLines do
            local dLine = self.doubleLines[i]
            dLine.left:Hide()
            dLine.right:Hide()
            dLine.left:SetText("")
            dLine.right:SetText("")
            dLine.left:ClearAllPoints()
            dLine.right:ClearAllPoints()
            table.insert(self.doubleLinePool, dLine)
        end
        table.wipe(self.doubleLines)

        for i = 1, #self.vaultGridRows do
            local vr = self.vaultGridRows[i]
            vr.nameFs:Hide()
            vr.realmFs:Hide()
            vr.raidFs:Hide()
            vr.mplusFs:Hide()
            vr.worldFs:Hide()
            vr.nameFs:SetText("")
            vr.realmFs:SetText("")
            vr.raidFs:SetText("")
            vr.mplusFs:SetText("")
            vr.worldFs:SetText("")
            vr.nameFs:ClearAllPoints()
            vr.realmFs:ClearAllPoints()
            vr.raidFs:ClearAllPoints()
            vr.mplusFs:ClearAllPoints()
            vr.worldFs:ClearAllPoints()
            table.insert(self.vaultGridLinePool, vr)
        end
        table.wipe(self.vaultGridRows)

        for i = 1, #self.vaultTrackRows do
            local tr = self.vaultTrackRows[i]
            tr.raidFs:Hide()
            tr.mplusFs:Hide()
            tr.worldFs:Hide()
            tr.raidFs:SetText("")
            tr.mplusFs:SetText("")
            tr.worldFs:SetText("")
            tr.raidFs:ClearAllPoints()
            tr.mplusFs:ClearAllPoints()
            tr.worldFs:ClearAllPoints()
            table.insert(self.vaultTrackLinePool, tr)
        end
        table.wipe(self.vaultTrackRows)
        
        for i = 1, #self.allLines do
            local lineData = self.allLines[i]
            if lineData.type == "divider" and lineData.element then
                local div = lineData.element
                div:Hide()
                div:ClearAllPoints()
                table.insert(self.bodyDividerPool, div)
            end
        end

        -- Clear unified line list
        table.wipe(self.allLines)
        
        -- Reset sizing (MAX_WIDTH as initial, LayoutLines will compute actual)
        self.currentHeight = 10
        self.fixedWidth = MAX_WIDTH
        local spacing = GetTooltipUISpacing()
        self.paddingH = spacing.SIDE_MARGIN + 2
        self.paddingV = spacing.SIDE_MARGIN
        self:SetSize(self.fixedWidth, 10)
        self._deferLayout = false
        self._layoutDirty = false
    end
    
    -- ========================================================================
    -- API: Set icon (top-left corner)
    -- ========================================================================
    frame.SetIcon = function(self, iconPath, isAtlas)
        local tex = self.iconFrame.texture
        if iconPath then
            if isAtlas then
                local ok = pcall(function()
                    tex:SetAtlas(iconPath, false)
                end)
                if ok then
                    tex:SetTexCoord(0, 1, 0, 1)
                else
                    tex:SetTexture("Interface\\Icons\\INV_Misc_Chest_03")
                    tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            elseif type(iconPath) == "number" then
                tex:SetTexture(iconPath)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            else
                tex:SetTexture(iconPath)
                tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        else
            tex:SetTexture(FALLBACK_ICON)
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        self.hasIcon = true
        self.iconFrame:Show()
    end
    
    -- ========================================================================
    -- API: Set title (always at top, next to icon if present)
    -- ========================================================================
    frame.SetTitle = function(self, text, r, g, b)
        local titleLine = self:GetOrCreateTitleLine()
        titleLine:SetText(text or "")
        titleLine:SetTextColor(r or 1, g or 0.82, b or 0)
        titleLine:Show()
    end

    -- Lines directly under the colored title (before separator) — e.g. Gear "need more crests".
    frame.AddTitleAffix = function(self, text, r, g, b, wrap)
        local line = self:GetOrCreateLine()
        line:SetText(text or "")
        line:SetTextColor(r or 1, g or 1, b or 1)
        local contentWidth = (self.fixedWidth or MAX_WIDTH) - (self.paddingH * 2)
        line:SetWidth(contentWidth)
        if wrap then
            line:SetWordWrap(true)
            line:SetNonSpaceWrap(true)
            line:SetMaxLines(0)
            line:SetHeight(0)
        else
            line:SetWordWrap(false)
            line:SetHeight(0)
        end
        line:Show()
        table.insert(self.titleAffixLines, line)
        RequestLayout(self)
    end

    -- Character row under title: name (left) + ilvl (right), header band only.
    frame.AddTitleAffixPair = function(self, leftText, rightText, lr, lg, lb, rr, rg, rb)
        if not self.titleAffixPairLeft then
            self.titleAffixPairLeft = FontManager:CreateFontString(self, "large", "OVERLAY")
            self.titleAffixPairRight = FontManager:CreateFontString(self, "medium", "OVERLAY")
            self.titleAffixPairLeft:SetJustifyH("LEFT")
            self.titleAffixPairRight:SetJustifyH("RIGHT")
        end
        self.titleAffixPairLeft:SetText(leftText or "")
        self.titleAffixPairLeft:SetTextColor(lr or 1, lg or 1, lb or 1)
        self.titleAffixPairRight:SetText(rightText or "")
        self.titleAffixPairRight:SetTextColor(rr or 1, rg or 1, rb or 1)
        self.titleAffixPairLeft:Show()
        self.titleAffixPairRight:Show()
        self.hasTitleAffixPair = true
        RequestLayout(self)
    end
    
    -- ========================================================================
    -- API: Set description (below title, smaller font, wrapping)
    -- ========================================================================
    frame.SetDescription = function(self, text, r, g, b)
        if not text or text == "" then return end
        local descLine = self:GetOrCreateDescLine()
        descLine:SetText(text)
        descLine:SetTextColor(r or 0.8, g or 0.8, b or 0.8)
        descLine:SetWordWrap(true)
        descLine:SetNonSpaceWrap(true)
        descLine:SetMaxLines(0)
        descLine:Show()
    end
    
    -- ========================================================================
    -- API: Add single text line
    -- ========================================================================
    frame.AddLine = function(self, text, r, g, b, wrap)
        local line = self:GetOrCreateLine()
        line:SetText(text)
        line:SetTextColor(r or 1, g or 1, b or 1)
        
        local contentWidth = (self.fixedWidth or MAX_WIDTH) - (self.paddingH * 2)
        line:SetWidth(contentWidth)
        
        if wrap then
            line:SetWordWrap(true)
            line:SetNonSpaceWrap(true)
            line:SetMaxLines(0)
            line:SetHeight(0)
        else
            line:SetWordWrap(false)
            line:SetHeight(0)
        end
        
        line:Show()
        table.insert(self.lines, line)
        table.insert(self.allLines, {type = "single", element = line})
        
        RequestLayout(self)
    end
    
    -- ========================================================================
    -- API: Add double-column line (left/right text)
    -- ========================================================================
    frame.AddDoubleLine = function(self, leftText, rightText, lr, lg, lb, rr, rg, rb, opts)
        opts = opts or {}
        local dLine = self:GetOrCreateDoubleLine()
        
        dLine.left:SetText(leftText)
        dLine.left:SetTextColor(lr or 1, lg or 1, lb or 1)
        
        dLine.right:SetText(rightText)
        dLine.right:SetTextColor(rr or 1, rg or 1, rb or 1)
        dLine.right:SetJustifyH("RIGHT")
        
        dLine.left:Show()
        dLine.right:Show()
        
        table.insert(self.doubleLines, dLine)
        table.insert(self.allLines, {
            type = "double",
            element = dLine,
            balanced = opts.balanced == true,
        })
        
        RequestLayout(self)
    end

    frame.AddCenteredLine = function(self, text, r, g, b)
        local line = self:GetOrCreateLine()
        line:SetText(text or "")
        line:SetTextColor(r or 1, g or 1, b or 1)
        line:SetJustifyH("CENTER")
        line:Show()
        table.insert(self.lines, line)
        table.insert(self.allLines, { type = "centered", element = line })
        RequestLayout(self)
    end

    frame.AddSectionLabel = function(self, text, r, g, b)
        local line
        if #self.linePool > 0 then
            line = table.remove(self.linePool)
        else
            line = FontManager:CreateFontString(self, "small", "OVERLAY")
        end
        line:SetText(text or "")
        line:SetTextColor(r or 0.62, g or 0.64, b or 0.72)
        line:SetJustifyH("CENTER")
        line:Show()
        table.insert(self.lines, line)
        table.insert(self.allLines, { type = "section_label", element = line })
        RequestLayout(self)
    end

    frame.GetOrCreateBodyDivider = function(self)
        if #self.bodyDividerPool > 0 then
            return table.remove(self.bodyDividerPool)
        end
        local div = self:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        return div
    end

    frame.AddBodyDivider = function(self)
        self:AddSpacer(6)
        local div = self:GetOrCreateBodyDivider()
        local ac = (COLORS and COLORS.accent) or { 0.45, 0.35, 0.72 }
        div:SetColorTexture(ac[1], ac[2], ac[3], 0.32)
        div:Show()
        table.insert(self.allLines, { type = "divider", element = div })
        self:AddSpacer(6)
    end

    -- ========================================================================
    -- API: Add spacer
    -- ========================================================================
    frame.AddSpacer = function(self, height)
        height = height or 6
        local spacerLine = self:GetOrCreateLine()
        spacerLine:SetText("")
        spacerLine:SetHeight(height)
        spacerLine:Show()
        table.insert(self.lines, spacerLine)
        table.insert(self.allLines, {type = "spacer", element = spacerLine, height = height})
        RequestLayout(self)
    end
    
    -- ========================================================================
    -- INTERNAL: Get or create title line (larger font)
    -- ========================================================================
    frame.GetOrCreateTitleLine = function(self)
        if not self.titleLine then
            self.titleLine = FontManager:CreateFontString(self, "large", "OVERLAY")
            self.titleLine:SetJustifyH("LEFT")
        end
        return self.titleLine
    end
    
    -- ========================================================================
    -- INTERNAL: Get or create description line
    -- ========================================================================
    frame.GetOrCreateDescLine = function(self)
        if not self.descLine then
            self.descLine = FontManager:CreateFontString(self, "body", "OVERLAY")
            self.descLine:SetJustifyH("LEFT")
        end
        return self.descLine
    end
    
    -- ========================================================================
    -- INTERNAL: Get or create single line from pool
    -- ========================================================================
    frame.GetOrCreateLine = function(self)
        if #self.linePool > 0 then
            return table.remove(self.linePool)
        end
        local line = FontManager:CreateFontString(self, "medium", "OVERLAY")
        line:SetJustifyH("LEFT")
        return line
    end
    
    -- ========================================================================
    -- INTERNAL: Get or create double line from pool
    -- ========================================================================
    frame.GetOrCreateDoubleLine = function(self)
        if #self.doubleLinePool > 0 then
            return table.remove(self.doubleLinePool)
        end
        local dLine = {}
        dLine.left = FontManager:CreateFontString(self, "medium", "OVERLAY")
        dLine.left:SetJustifyH("LEFT")
        dLine.right = FontManager:CreateFontString(self, "medium", "OVERLAY")
        dLine.right:SetJustifyH("RIGHT")
        return dLine
    end

    -- ========================================================================
    -- INTERNAL: Vault summary row — fixed columns (name | realm | raid | m+ | world)
    -- ========================================================================
    frame.GetOrCreateVaultGridRow = function(self)
        if #self.vaultGridLinePool > 0 then
            return table.remove(self.vaultGridLinePool)
        end
        local row = {}
        row.nameFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.nameFs:SetJustifyH("LEFT")
        row.nameFs:SetWordWrap(false)
        row.realmFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.realmFs:SetJustifyH("LEFT")
        row.realmFs:SetWordWrap(false)
        row.raidFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.raidFs:SetJustifyH("CENTER")
        row.raidFs:SetWordWrap(false)
        row.mplusFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.mplusFs:SetJustifyH("CENTER")
        row.mplusFs:SetWordWrap(false)
        row.worldFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.worldFs:SetJustifyH("CENTER")
        row.worldFs:SetWordWrap(false)
        return row
    end

    --[[
        Five-column row for Great Vault summary tooltip (aligned name/realm + vault tracks).
        widths = { nameW, realmW, raidW, mplusW, worldW } in pixels.
        opts.isHeader — gold column labels for vault headers.
    ]]
    frame.AddVaultGridRow = function(self, nameText, realmText, colRaid, colMplus, colWorld, widths, opts)
        opts = opts or {}
        local row = self:GetOrCreateVaultGridRow()
        row.nameFs:SetText(nameText or "")
        row.realmFs:SetText(realmText or "")
        row.raidFs:SetText(colRaid or "")
        row.mplusFs:SetText(colMplus or "")
        row.worldFs:SetText(colWorld or "")
        row.widthName = (widths and widths[1]) or 80
        row.widthRealm = (widths and widths[2]) or 80
        row.widthRaid = (widths and widths[3]) or 48
        row.widthMplus = (widths and widths[4]) or 48
        row.widthWorld = (widths and widths[5]) or 48
        row.isHeader = opts.isHeader == true
        if opts.isHeader then
            local hr, hg, hb = 1, 0.82, 0.35
            row.nameFs:SetTextColor(hr, hg, hb)
            row.realmFs:SetTextColor(hr, hg, hb)
            row.raidFs:SetTextColor(hr, hg, hb)
            row.mplusFs:SetTextColor(hr, hg, hb)
            row.worldFs:SetTextColor(hr, hg, hb)
        else
            row.nameFs:SetTextColor(1, 1, 1)
            row.realmFs:SetTextColor(1, 1, 1)
            row.raidFs:SetTextColor(1, 1, 1)
            row.mplusFs:SetTextColor(1, 1, 1)
            row.worldFs:SetTextColor(1, 1, 1)
        end
        row.nameFs:Show()
        row.realmFs:Show()
        row.raidFs:SetJustifyH("CENTER")
        row.mplusFs:SetJustifyH("CENTER")
        row.worldFs:SetJustifyH("CENTER")
        row.raidFs:Show()
        row.mplusFs:Show()
        row.worldFs:Show()
        table.insert(self.vaultGridRows, row)
        table.insert(self.allLines, { type = "vault_grid", element = row })
        RequestLayout(self)
    end

    -- ========================================================================
    -- INTERNAL: Three-column vault track row (Raid / M+ / World only)
    -- ========================================================================
    frame.GetOrCreateVaultTrackRow = function(self)
        if #self.vaultTrackLinePool > 0 then
            return table.remove(self.vaultTrackLinePool)
        end
        local row = {}
        row.raidFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.raidFs:SetJustifyH("CENTER")
        row.raidFs:SetWordWrap(false)
        row.mplusFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.mplusFs:SetJustifyH("CENTER")
        row.mplusFs:SetWordWrap(false)
        row.worldFs = FontManager:CreateFontString(self, "medium", "OVERLAY")
        row.worldFs:SetJustifyH("CENTER")
        row.worldFs:SetWordWrap(false)
        return row
    end

    frame.AddVaultTrackRow = function(self, colRaid, colMplus, colWorld, colW, opts)
        opts = opts or {}
        local row = self:GetOrCreateVaultTrackRow()
        row.raidFs:SetText(colRaid or "")
        row.mplusFs:SetText(colMplus or "")
        row.worldFs:SetText(colWorld or "")
        row.colW = tonumber(colW) or VAULT_GRID_TRACK_MIN_W
        row.isHeader = opts.isHeader == true
        if opts.isHeader then
            local hr, hg, hb = 1, 0.82, 0.35
            row.raidFs:SetTextColor(hr, hg, hb)
            row.mplusFs:SetTextColor(hr, hg, hb)
            row.worldFs:SetTextColor(hr, hg, hb)
        else
            row.raidFs:SetTextColor(1, 1, 1)
            row.mplusFs:SetTextColor(1, 1, 1)
            row.worldFs:SetTextColor(1, 1, 1)
        end
        row.raidFs:Show()
        row.mplusFs:Show()
        row.worldFs:Show()
        table.insert(self.vaultTrackRows, row)
        table.insert(self.allLines, { type = "vault_track", element = row })
        RequestLayout(self)
    end
    
    -- ========================================================================
    -- INTERNAL: Layout - header (icon + title + desc) then body lines
    -- ========================================================================
    frame.LayoutLines = function(self)
        local spacing = GetTooltipUISpacing()
        local padding = self.paddingH or (spacing.SIDE_MARGIN + 2)
        local paddingV = self.paddingV or spacing.SIDE_MARGIN
        local lineSpacing = 2
        
        -- ── Phase 1: Measure natural content width ──
        local maxContentW = 0
        
        -- Measure title
        if self.titleLine and self.titleLine:IsShown() then
            self.titleLine:SetWidth(0)  -- Unconstrain to measure natural width
            local tw = self.titleLine:GetStringWidth() or 0
            local headerW = tw + (self.hasIcon and (ICON_SIZE + ICON_PADDING) or 0)
            if headerW > maxContentW then maxContentW = headerW end
        end
        
        -- Measure description
        if self.descLine and self.descLine:IsShown() then
            self.descLine:SetWidth(0)
            local dw = self.descLine:GetStringWidth() or 0
            local descHeaderW = dw + (self.hasIcon and (ICON_SIZE + ICON_PADDING) or 0)
            if descHeaderW > maxContentW then maxContentW = descHeaderW end
            if dw > maxContentW then maxContentW = dw end
        end

        -- Measure title affixes (lines under the item name, right of icon)
        if self.titleAffixLines then
            for i = 1, #self.titleAffixLines do
                local aLine = self.titleAffixLines[i]
                aLine:SetWidth(0)
                local w = aLine:GetStringWidth() or 0
                local withIcon = w + (self.hasIcon and (ICON_SIZE + ICON_PADDING) or 0)
                if withIcon > maxContentW then maxContentW = withIcon end
            end
        end

        if self.hasTitleAffixPair and self.titleAffixPairLeft and self.titleAffixPairRight then
            self.titleAffixPairLeft:SetWidth(0)
            self.titleAffixPairRight:SetWidth(0)
            local pairW = (self.titleAffixPairLeft:GetStringWidth() or 0) + (self.titleAffixPairRight:GetStringWidth() or 0) + 28
            local withIcon = pairW + (self.hasIcon and (ICON_SIZE + ICON_PADDING) or 0)
            if withIcon > maxContentW then maxContentW = withIcon end
        end
        
        -- Measure body lines
        local maxBalancedLeft = 0
        for i = 1, #self.allLines do
            local lineData = self.allLines[i]
            if lineData.type == "single" then
                lineData.element:SetWidth(0)
                local lw = lineData.element:GetStringWidth() or 0
                if lw > maxContentW then maxContentW = lw end
            elseif lineData.type == "centered" or lineData.type == "section_label" then
                lineData.element:SetWidth(0)
                local lw = lineData.element:GetStringWidth() or 0
                if lw > maxContentW then maxContentW = lw end
            elseif lineData.type == "double" then
                lineData.element.left:SetWidth(0)
                lineData.element.right:SetWidth(0)
                local lw = (lineData.element.left:GetStringWidth() or 0) + (lineData.element.right:GetStringWidth() or 0) + 20
                if lw > maxContentW then maxContentW = lw end
                if lineData.balanced then
                    maxBalancedLeft = math.max(maxBalancedLeft, lineData.element.left:GetStringWidth() or 0)
                end
            elseif lineData.type == "vault_grid" then
                local v = lineData.element
                local lw = v.widthName + VAULT_GRID_GAP_NAME_REALM + v.widthRealm + VAULT_GRID_GAP_BEFORE_VAULT
                    + v.widthRaid + VAULT_GRID_GAP_VAULT_COL + v.widthMplus + VAULT_GRID_GAP_VAULT_COL + v.widthWorld
                if lw > maxContentW then maxContentW = lw end
            elseif lineData.type == "vault_track" then
                local t = lineData.element
                local lw = t.colW * 3 + VAULT_TRACK_GAP_COL * 2
                if lw > maxContentW then maxContentW = lw end
            end
        end
        
        -- Clamp width: respect TooltipService maxWidth preset (Vault summary), cap at WIDTH_CAP_TOP.
        local requestedCap = tonumber(self.fixedWidth) or MAX_WIDTH
        local widthCap = math.min(WIDTH_CAP_TOP, math.max(MAX_WIDTH, requestedCap))
        local computedWidth = math.max(MIN_WIDTH, math.min(widthCap, maxContentW + padding * 2))
        self.fixedWidth = computedWidth
        self:SetWidth(computedWidth)
        self._balancedSplit = (maxBalancedLeft > 0) and (padding + maxBalancedLeft + 14) or nil
        
        -- Re-constrain wrapping lines to the new width
        local contentWidth = computedWidth - padding * 2
        for i = 1, #self.allLines do
            local lineData = self.allLines[i]
            if lineData.type == "single" or lineData.type == "centered" or lineData.type == "section_label" then
                lineData.element:SetWidth(contentWidth)
            end
        end
        if self.titleLine and self.titleLine:IsShown() then
            local textLeftX = self.hasIcon and (padding + ICON_SIZE + ICON_PADDING) or padding
            self.titleLine:SetWidth(computedWidth - textLeftX - padding)
        end
        if self.descLine and self.descLine:IsShown() then
            local textLeftX = self.hasIcon and (padding + ICON_SIZE + ICON_PADDING) or padding
            self.descLine:SetWidth(computedWidth - textLeftX - padding)
        end
        if self.titleAffixLines and #self.titleAffixLines > 0 then
            local tlx = self.hasIcon and (padding + ICON_SIZE + ICON_PADDING) or padding
            for i = 1, #self.titleAffixLines do
                local aLine = self.titleAffixLines[i]
                aLine:SetWidth(computedWidth - tlx - padding)
            end
        end
        
        -- ── Phase 2: Position elements ──
        local yOffset = -paddingV
        
        -- ===== HEADER SECTION: Icon + Title + Description =====
        local textLeftX = padding
        local headerBottom = yOffset
        
        if self.hasIcon then
            -- Position icon top-left
            self.iconFrame:ClearAllPoints()
            self.iconFrame:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
            textLeftX = padding + ICON_SIZE + ICON_PADDING
        end
        
        -- Title (right of icon if present)
        local titleBottom = yOffset
        if self.titleLine and self.titleLine:IsShown() then
            self.titleLine:ClearAllPoints()
            self.titleLine:SetPoint("TOPLEFT", self, "TOPLEFT", textLeftX, yOffset)
            self.titleLine:SetWidth((self.fixedWidth or 350) - textLeftX - padding)
            titleBottom = yOffset - self.titleLine:GetHeight()
        end

        -- Title affix pair (character + ilvl)
        local afterHeaderText = titleBottom
        if self.hasTitleAffixPair and self.titleAffixPairLeft and self.titleAffixPairRight then
            local yTop = titleBottom - 2
            self.titleAffixPairLeft:ClearAllPoints()
            self.titleAffixPairRight:ClearAllPoints()
            self.titleAffixPairLeft:SetPoint("TOPLEFT", self, "TOPLEFT", textLeftX, yTop)
            self.titleAffixPairRight:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, yTop)
            local pairH = math.max(self.titleAffixPairLeft:GetStringHeight(), self.titleAffixPairRight:GetStringHeight())
            afterHeaderText = yTop - pairH
        end

        -- Title affixes: directly under the colored name (before separator, same indent as title)
        if self.titleAffixLines and #self.titleAffixLines > 0 then
            local yTop = titleBottom
            for i = 1, #self.titleAffixLines do
                local aLine = self.titleAffixLines[i]
                yTop = yTop - 2
                aLine:ClearAllPoints()
                aLine:SetPoint("TOPLEFT", self, "TOPLEFT", textLeftX, yTop)
                aLine:SetWidth((self.fixedWidth or 350) - textLeftX - padding)
                aLine:SetHeight(0)
                yTop = yTop - aLine:GetStringHeight()
            end
            afterHeaderText = yTop
        end
        
        -- Description (below title/affix, still indented if icon)
        local descBottom = afterHeaderText
        if self.descLine and self.descLine:IsShown() then
            self.descLine:ClearAllPoints()
            self.descLine:SetPoint("TOPLEFT", self, "TOPLEFT", textLeftX, afterHeaderText - 2)
            self.descLine:SetWidth((self.fixedWidth or 350) - textLeftX - padding)
            self.descLine:SetHeight(0)
            descBottom = afterHeaderText - 2 - self.descLine:GetStringHeight()
        else
            descBottom = afterHeaderText
        end
        
        -- Header bottom = lowest of icon bottom vs text bottom
        local iconBottom = yOffset
        if self.hasIcon then
            iconBottom = yOffset - ICON_SIZE
        end
        headerBottom = math.min(iconBottom, descBottom)
        
        -- ===== SEPARATOR =====
        local bodyStartY = headerBottom
        local showSeparator = false
        if self.titleLine and self.titleLine:IsShown() and #self.allLines > 0 then
            -- Only show separator if there's both header and body content
            for i = 1, #self.allLines do
                local lineData = self.allLines[i]
                if lineData.type ~= "spacer" and lineData.type ~= "divider" then
                    showSeparator = true
                    break
                end
            end
        end
        
        if showSeparator then
            bodyStartY = headerBottom - 3
            self.separator:ClearAllPoints()
            self.separator:SetPoint("TOPLEFT", self, "TOPLEFT", padding, bodyStartY)
            self.separator:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, bodyStartY)
            self.separator:Show()
            bodyStartY = bodyStartY - 1 - 4  -- separator height + gap to first body line
        else
            self.separator:Hide()
        end
        
        -- ===== BODY LINES =====
        yOffset = bodyStartY
        local prevElement = nil
        
        for i = 1, #self.allLines do
            local lineData = self.allLines[i]
            if lineData.type == "single" or lineData.type == "spacer" then
                local line = lineData.element
                line:ClearAllPoints()
                
                if prevElement then
                    line:SetPoint("TOPLEFT", prevElement, "BOTTOMLEFT", 0, -lineSpacing)
                else
                    line:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
                end
                
                yOffset = yOffset - line:GetHeight() - lineSpacing
                prevElement = line

            elseif lineData.type == "centered" or lineData.type == "section_label" then
                local line = lineData.element
                line:ClearAllPoints()
                line:SetJustifyH("CENTER")
                line:SetWidth(contentWidth)
                if prevElement then
                    line:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset - lineSpacing)
                else
                    line:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
                end
                local lineHeight = line:GetStringHeight()
                yOffset = yOffset - lineHeight - lineSpacing
                prevElement = line

            elseif lineData.type == "divider" then
                local div = lineData.element
                div:ClearAllPoints()
                local divY = yOffset - 4
                div:SetPoint("TOPLEFT", self, "TOPLEFT", padding, divY)
                div:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, divY)
                yOffset = divY - 1 - 6
                prevElement = div

            elseif lineData.type == "double" then
                local dLine = lineData.element
                dLine.left:ClearAllPoints()
                dLine.right:ClearAllPoints()
                
                if prevElement then
                    dLine.left:SetPoint("TOPLEFT", prevElement, "BOTTOMLEFT", 0, -lineSpacing)
                else
                    dLine.left:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
                end
                
                if lineData.balanced and self._balancedSplit then
                    dLine.right:SetJustifyH("LEFT")
                    dLine.right:SetPoint("TOPLEFT", self, "TOPLEFT", self._balancedSplit, yOffset)
                else
                    dLine.right:SetJustifyH("RIGHT")
                    dLine.right:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, yOffset)
                end
                
                local lineHeight = math.max(dLine.left:GetHeight(), dLine.right:GetHeight())
                yOffset = yOffset - lineHeight - lineSpacing
                prevElement = dLine.left
            elseif lineData.type == "vault_grid" then
                local v = lineData.element
                v.nameFs:ClearAllPoints()
                v.realmFs:ClearAllPoints()
                v.raidFs:ClearAllPoints()
                v.mplusFs:ClearAllPoints()
                v.worldFs:ClearAllPoints()

                if prevElement then
                    v.nameFs:SetPoint("TOPLEFT", prevElement, "BOTTOMLEFT", 0, -lineSpacing)
                else
                    v.nameFs:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
                end

                v.nameFs:SetWidth(v.widthName)
                v.realmFs:SetWidth(v.widthRealm)
                v.raidFs:SetWidth(v.widthRaid)
                v.mplusFs:SetWidth(v.widthMplus)
                v.worldFs:SetWidth(v.widthWorld)

                v.realmFs:SetPoint("TOPLEFT", v.nameFs, "TOPRIGHT", VAULT_GRID_GAP_NAME_REALM, 0)
                v.raidFs:SetPoint("TOPLEFT", v.realmFs, "TOPRIGHT", VAULT_GRID_GAP_BEFORE_VAULT, 0)
                v.mplusFs:SetPoint("TOPLEFT", v.raidFs, "TOPRIGHT", VAULT_GRID_GAP_VAULT_COL, 0)
                v.worldFs:SetPoint("TOPLEFT", v.mplusFs, "TOPRIGHT", VAULT_GRID_GAP_VAULT_COL, 0)

                local lineHeight = math.max(
                    v.nameFs:GetStringHeight(),
                    v.realmFs:GetStringHeight(),
                    v.raidFs:GetStringHeight(),
                    v.mplusFs:GetStringHeight(),
                    v.worldFs:GetStringHeight()
                )
                yOffset = yOffset - lineHeight - lineSpacing
                prevElement = v.nameFs
            elseif lineData.type == "vault_track" then
                local t = lineData.element
                local contentWidth = (self.fixedWidth or 350) - padding * 2
                local trackW = t.colW * 3 + VAULT_TRACK_GAP_COL * 2
                local trackLeft = padding + math.max(0, math.floor((contentWidth - trackW) * 0.5))

                t.raidFs:ClearAllPoints()
                t.mplusFs:ClearAllPoints()
                t.worldFs:ClearAllPoints()

                if prevElement then
                    t.raidFs:SetPoint("TOPLEFT", prevElement, "BOTTOMLEFT", 0, -lineSpacing)
                else
                    t.raidFs:SetPoint("TOPLEFT", self, "TOPLEFT", trackLeft, yOffset)
                end

                t.raidFs:SetWidth(t.colW)
                t.mplusFs:SetWidth(t.colW)
                t.worldFs:SetWidth(t.colW)
                t.mplusFs:SetPoint("TOPLEFT", t.raidFs, "TOPRIGHT", VAULT_TRACK_GAP_COL, 0)
                t.worldFs:SetPoint("TOPLEFT", t.mplusFs, "TOPRIGHT", VAULT_TRACK_GAP_COL, 0)

                local lineHeight = math.max(
                    t.raidFs:GetStringHeight(),
                    t.mplusFs:GetStringHeight(),
                    t.worldFs:GetStringHeight()
                )
                yOffset = yOffset - lineHeight - lineSpacing
                prevElement = t.raidFs
            end
        end
        
        -- Update frame size
        self.currentHeight = math.abs(yOffset) + paddingV
        self:SetWidth(self.fixedWidth or 350)
        self:SetHeight(self.currentHeight)
    end
    
    -- ========================================================================
    -- API: Update theme colors
    -- ========================================================================
    frame.UpdateTheme = function(self)
        COLORS = ns.UI_COLORS or {
            bgCard = {0.08, 0.08, 0.10, 1},
            border = {0.20, 0.20, 0.25, 1},
            accent = {0.45, 0.35, 0.72},
        }

        if ns.UI_ApplyStandardCardElevatedChrome then
            ns.UI_ApplyStandardCardElevatedChrome(self)
        else
            self:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            self:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 0.98)
            self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
        end
        TintTooltipAccentLines(self)
    end
    
    return frame
end
