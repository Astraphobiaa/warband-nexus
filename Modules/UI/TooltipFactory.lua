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
local UI_SPACING = ns.UI_SPACING  -- Standardized spacing constants

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

--[[
    Create singleton tooltip frame
    @return Frame - Reusable tooltip frame
]]
function ns.UI.TooltipFactory:CreateTooltipFrame()
    -- Get current theme colors
    COLORS = ns.UI_COLORS or {
        bgCard = {0.08, 0.08, 0.10, 1},
        border = {0.20, 0.20, 0.25, 1},
    }
    
    -- Create frame
    local frame = CreateFrame("Frame", "WarbandNexusTooltip", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("TOOLTIP")
    frame:SetFrameLevel(10000)
    frame:SetSize(250, 100)
    frame:Hide()
    
    -- Backdrop with theme colors (minimalist design)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 0.98)
    frame:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
    
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
    iconBorder:SetColorTexture(0.3, 0.3, 0.3, 0.8)
    iconFrame.border = iconBorder
    
    -- Icon sits behind the texture (border effect)
    iconTexture:SetDrawLayer("ARTWORK", 1)
    iconBorder:SetDrawLayer("ARTWORK", 0)
    
    frame.iconFrame = iconFrame
    
    -- Separator line (thin horizontal line between header and body)
    local separator = frame:CreateTexture(nil, "ARTWORK")
    separator:SetHeight(1)
    separator:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    frame.separator = separator
    
    -- FontString pools (recycled for performance)
    frame.lines = {}
    frame.linePool = {}
    frame.doubleLines = {}
    frame.doubleLinePool = {}
    frame.titleLine = nil
    frame.descLine = nil
    frame.allLines = {}
    
    -- Layout state (FIXED WIDTH for consistency)
    frame.currentHeight = 10
    frame.fixedWidth = 350
    frame.paddingH = UI_SPACING.SIDE_MARGIN + 2
    frame.paddingV = UI_SPACING.SIDE_MARGIN
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
        
        -- Return all lines to pool
        for _, line in ipairs(self.lines) do
            line:Hide()
            line:SetText("")
            line:ClearAllPoints()
            table.insert(self.linePool, line)
        end
        table.wipe(self.lines)
        
        -- Return double lines to pool
        for _, dLine in ipairs(self.doubleLines) do
            dLine.left:Hide()
            dLine.right:Hide()
            dLine.left:SetText("")
            dLine.right:SetText("")
            dLine.left:ClearAllPoints()
            dLine.right:ClearAllPoints()
            table.insert(self.doubleLinePool, dLine)
        end
        table.wipe(self.doubleLines)
        
        -- Clear unified line list
        table.wipe(self.allLines)
        
        -- Reset sizing
        self.currentHeight = 10
        self.fixedWidth = 350
        self.paddingH = UI_SPACING.SIDE_MARGIN + 2
        self.paddingV = UI_SPACING.SIDE_MARGIN
        self:SetSize(self.fixedWidth, 10)
    end
    
    -- ========================================================================
    -- API: Set icon (top-left corner)
    -- ========================================================================
    frame.SetIcon = function(self, iconPath, isAtlas)
        local tex = self.iconFrame.texture
        if iconPath then
            if isAtlas then
                tex:SetAtlas(iconPath)
                tex:SetTexCoord(0, 1, 0, 1)
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
        
        local contentWidth = (self.fixedWidth or 350) - (self.paddingH * 2)
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
        
        self:LayoutLines()
    end
    
    -- ========================================================================
    -- API: Add double-column line (left/right text)
    -- ========================================================================
    frame.AddDoubleLine = function(self, leftText, rightText, lr, lg, lb, rr, rg, rb)
        local dLine = self:GetOrCreateDoubleLine()
        
        dLine.left:SetText(leftText)
        dLine.left:SetTextColor(lr or 1, lg or 1, lb or 1)
        
        dLine.right:SetText(rightText)
        dLine.right:SetTextColor(rr or 1, rg or 1, rb or 1)
        
        dLine.left:Show()
        dLine.right:Show()
        
        table.insert(self.doubleLines, dLine)
        table.insert(self.allLines, {type = "double", element = dLine})
        
        self:LayoutLines()
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
        self:LayoutLines()
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
    -- INTERNAL: Layout - header (icon + title + desc) then body lines
    -- ========================================================================
    frame.LayoutLines = function(self)
        local padding = self.paddingH or (UI_SPACING.SIDE_MARGIN + 2)
        local paddingV = self.paddingV or UI_SPACING.SIDE_MARGIN
        local lineSpacing = 2
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
        
        -- Description (below title, still indented if icon)
        local descBottom = titleBottom
        if self.descLine and self.descLine:IsShown() then
            self.descLine:ClearAllPoints()
            self.descLine:SetPoint("TOPLEFT", self, "TOPLEFT", textLeftX, titleBottom - 2)
            self.descLine:SetWidth((self.fixedWidth or 350) - textLeftX - padding)
            self.descLine:SetHeight(0)
            descBottom = titleBottom - 2 - self.descLine:GetStringHeight()
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
            for _, lineData in ipairs(self.allLines) do
                if lineData.type ~= "spacer" then
                    showSeparator = true
                    break
                end
            end
        end
        
        if showSeparator then
            bodyStartY = headerBottom - 6
            self.separator:ClearAllPoints()
            self.separator:SetPoint("TOPLEFT", self, "TOPLEFT", padding, bodyStartY)
            self.separator:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, bodyStartY)
            self.separator:Show()
            bodyStartY = bodyStartY - 1 - 6  -- separator height + bottom gap
        else
            self.separator:Hide()
        end
        
        -- ===== BODY LINES =====
        yOffset = bodyStartY
        local prevElement = nil
        
        for i, lineData in ipairs(self.allLines) do
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
                
            elseif lineData.type == "double" then
                local dLine = lineData.element
                dLine.left:ClearAllPoints()
                dLine.right:ClearAllPoints()
                
                if prevElement then
                    dLine.left:SetPoint("TOPLEFT", prevElement, "BOTTOMLEFT", 0, -lineSpacing)
                else
                    dLine.left:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
                end
                
                dLine.right:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, yOffset)
                
                local lineHeight = math.max(dLine.left:GetHeight(), dLine.right:GetHeight())
                yOffset = yOffset - lineHeight - lineSpacing
                prevElement = dLine.left
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
        }
        
        self:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4])
        self:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
    end
    
    return frame
end
