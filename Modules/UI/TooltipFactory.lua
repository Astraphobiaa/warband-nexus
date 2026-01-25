--[[
    Warband Nexus - Tooltip Factory
    UI frame creation for custom tooltips
    
    Follows SharedWidgets pattern:
    - Theme-aware styling
    - Frame pooling and recycling
    - Consistent visual design
]]

local ADDON_NAME, ns = ...

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
    
    -- Backdrop with theme colors
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4])
    frame:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 1)
    
    -- FontString pools (recycled for performance)
    frame.lines = {}          -- Active lines
    frame.linePool = {}       -- Unused lines ready for reuse
    frame.doubleLines = {}    -- Active double-column lines
    frame.doubleLinePool = {} -- Unused double lines
    
    -- Layout state
    frame.currentHeight = 10
    frame.maxWidth = 150
    
    -- ========================================================================
    -- API: Clear all content
    -- ========================================================================
    frame.Clear = function(self)
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
        
        -- Reset sizing
        self.currentHeight = 10
        self.maxWidth = 150
        self:SetSize(150, 10)
    end
    
    -- ========================================================================
    -- API: Add single text line
    -- ========================================================================
    frame.AddLine = function(self, text, r, g, b, wrap)
        local line = self:GetOrCreateLine()
        line:SetText(text)
        line:SetTextColor(r or 1, g or 1, b or 1)
        line:SetWordWrap(wrap or false)
        
        if wrap then
            line:SetWidth(self.maxWidth - 16)
        else
            line:SetWidth(0) -- Auto-width
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
    -- API: Add spacer (empty space)
    -- ========================================================================
    frame.AddSpacer = function(self, height)
        height = height or 8
        self.currentHeight = self.currentHeight + height
        self:SetHeight(self.currentHeight)
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
        local line = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
        dLine.left = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dLine.left:SetJustifyH("LEFT")
        
        dLine.right = self:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dLine.right:SetJustifyH("RIGHT")
        
        return dLine
    end
    
    -- ========================================================================
    -- INTERNAL: Layout all lines and calculate size
    -- ========================================================================
    frame.LayoutLines = function(self)
        local yOffset = -8  -- Top padding
        local maxWidth = 150
        local padding = 8
        local lineSpacing = 2
        
        -- Position single lines
        for i, line in ipairs(self.lines) do
            if i == 1 then
                line:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
            else
                -- Check if previous was a double line or single line
                local prevElement = self.lines[i-1]
                if prevElement then
                    line:SetPoint("TOPLEFT", prevElement, "BOTTOMLEFT", 0, -lineSpacing)
                end
            end
            
            local lineWidth = line:GetStringWidth()
            if lineWidth > maxWidth then
                maxWidth = lineWidth
            end
            
            yOffset = yOffset - line:GetHeight() - lineSpacing
        end
        
        -- Position double lines (interleaved with single lines)
        for i, dLine in ipairs(self.doubleLines) do
            local prevY = yOffset
            
            -- Left side
            if #self.lines > 0 and i == 1 then
                dLine.left:SetPoint("TOPLEFT", self.lines[#self.lines], "BOTTOMLEFT", 0, -lineSpacing)
            else
                dLine.left:SetPoint("TOPLEFT", self, "TOPLEFT", padding, yOffset)
            end
            
            -- Right side (aligned to right edge)
            dLine.right:SetPoint("TOPRIGHT", self, "TOPRIGHT", -padding, yOffset)
            
            -- Calculate combined width
            local leftWidth = dLine.left:GetStringWidth()
            local rightWidth = dLine.right:GetStringWidth()
            local totalWidth = leftWidth + rightWidth + 20 -- Gap between columns
            
            if totalWidth > maxWidth then
                maxWidth = totalWidth
            end
            
            local lineHeight = math.max(dLine.left:GetHeight(), dLine.right:GetHeight())
            yOffset = yOffset - lineHeight - lineSpacing
        end
        
        -- Update frame size
        self.maxWidth = maxWidth
        self.currentHeight = math.abs(yOffset) + padding
        
        self:SetWidth(math.max(150, maxWidth + (padding * 2)))
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
