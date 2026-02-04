--[[
    Warband Nexus - Tooltip Factory
    UI frame creation for custom tooltips
    
    Follows SharedWidgets pattern:
    - Theme-aware styling
    - Frame pooling and recycling
    - Consistent visual design
]]

local ADDON_NAME, ns = ...
local FontManager = ns.FontManager  -- Centralized font management

-- ============================================================================
-- TOOLTIP FACTORY
-- ============================================================================

ns.UI = ns.UI or {}
ns.UI.TooltipFactory = {}

-- Cache colors (updated on theme change)
local COLORS = nil

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
        edgeSize = 1,  -- Thin 1px border for minimalist look
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    frame:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 0.98)
    frame:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
    
    -- FontString pools (recycled for performance)
    frame.lines = {}          -- Active lines
    frame.linePool = {}       -- Unused lines ready for reuse
    frame.doubleLines = {}    -- Active double-column lines
    frame.doubleLinePool = {} -- Unused double lines
    frame.titleLine = nil     -- Special title line (larger font)
    
    -- Layout state (FIXED WIDTH for consistency)
    frame.currentHeight = 10
    frame.fixedWidth = 280    -- FIXED width - never changes
    frame.paddingH = 12       -- Horizontal padding
    frame.paddingV = 10       -- Vertical padding
    
    -- ========================================================================
    -- API: Clear all content
    -- ========================================================================
    frame.Clear = function(self)
        -- Hide and clear title line
        if self.titleLine then
            self.titleLine:Hide()
            self.titleLine:SetText("")
            self.titleLine:ClearAllPoints()
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
        
        -- Reset sizing (FIXED WIDTH)
        self.currentHeight = 10
        self.fixedWidth = 280
        self:SetSize(self.fixedWidth, 10)
    end
    
    -- ========================================================================
    -- API: Add single text line
    -- ========================================================================
    frame.AddLine = function(self, text, r, g, b, wrap)
        local line = self:GetOrCreateLine()
        line:SetText(text)
        line:SetTextColor(r or 1, g or 1, b or 1)
        line:SetWordWrap(wrap or false)
        
        -- Always use fixed width minus padding
        local contentWidth = (self.fixedWidth or 280) - (self.paddingH * 2)
        if wrap then
            line:SetWidth(contentWidth)
            line:SetNonSpaceWrap(true)  -- Better wrapping for long words
        else
            -- Even non-wrapped lines respect the fixed width
            line:SetWidth(contentWidth)
        end
        
        line:Show()
        table.insert(self.lines, line)
        
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
        
        self:LayoutLines()
    end
    
    -- ========================================================================
    -- API: Add spacer (empty space with invisible line)
    -- ========================================================================
    frame.AddSpacer = function(self, height)
        height = height or 6
        -- Create an invisible line to occupy space in layout
        local spacerLine = self:GetOrCreateLine()
        spacerLine:SetText("")  -- Empty text
        spacerLine:SetHeight(height)  -- Set custom height
        spacerLine:Show()
        table.insert(self.lines, spacerLine)
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
    -- INTERNAL: Get or create single line from pool
    -- ========================================================================
    frame.GetOrCreateLine = function(self)
        -- Reuse from pool if available
        if #self.linePool > 0 then
            return table.remove(self.linePool)
        end
        
        -- Create new line
        local line = FontManager:CreateFontString(self, "small", "OVERLAY")
        line:SetJustifyH("LEFT")
        return line
    end
    
    -- ========================================================================
    -- INTERNAL: Get or create double line from pool
    -- ========================================================================
    frame.GetOrCreateDoubleLine = function(self)
        -- Reuse from pool
        if #self.doubleLinePool > 0 then
            return table.remove(self.doubleLinePool)
        end
        
        -- Create new double line
        local dLine = {}
        dLine.left = FontManager:CreateFontString(self, "small", "OVERLAY")
        dLine.left:SetJustifyH("LEFT")
        
        dLine.right = FontManager:CreateFontString(self, "small", "OVERLAY")
        dLine.right:SetJustifyH("RIGHT")
        
        return dLine
    end
    
    -- ========================================================================
    -- INTERNAL: Layout all lines and calculate size
    -- ========================================================================
    frame.LayoutLines = function(self)
        local yOffset = -(self.paddingV or 10)
        local padding = self.paddingH or 12
        local lineSpacing = 2
        
        -- Position title line first (if visible)
        if self.titleLine and self.titleLine:IsShown() then
            self.titleLine:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
            yOffset = yOffset - self.titleLine:GetHeight() - (lineSpacing * 2)  -- Extra spacing after title
        end
        
        -- Position single lines
        for i, line in ipairs(self.lines) do
            if i == 1 then
                if self.titleLine and self.titleLine:IsShown() then
                    -- Position after title
                    line:SetPoint("TOPLEFT", self.titleLine, "BOTTOMLEFT", 0, -(lineSpacing * 2))
                else
                    -- Position at top
                    line:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
                end
            else
                -- Position after previous line
                local prevElement = self.lines[i-1]
                if prevElement then
                    line:SetPoint("TOPLEFT", prevElement, "BOTTOMLEFT", 0, -lineSpacing)
                end
            end
            
            yOffset = yOffset - line:GetHeight() - lineSpacing
        end
        
        -- Position double lines
        for i, dLine in ipairs(self.doubleLines) do
            -- Left side
            if #self.lines > 0 and i == 1 then
                dLine.left:SetPoint("TOPLEFT", self.lines[#self.lines], "BOTTOMLEFT", 0, -lineSpacing)
            else
                dLine.left:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
            end
            
            -- Right side (aligned to right edge)
            dLine.right:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, yOffset)
            
            local lineHeight = math.max(dLine.left:GetHeight(), dLine.right:GetHeight())
            yOffset = yOffset - lineHeight - lineSpacing
        end
        
        -- Update frame size (FIXED WIDTH, dynamic height)
        self.currentHeight = math.abs(yOffset) + padding
        self:SetWidth(self.fixedWidth or 280)
        self:SetHeight(self.currentHeight)
    end
    
    -- ========================================================================
    -- API: Update theme colors (called when theme changes)
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
