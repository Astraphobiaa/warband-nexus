--[[
    Warband Nexus - Shared UI Widgets & Helpers
    Common UI components and utility functions used across all tabs
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--============================================================================
-- PIXEL PERFECT HELPERS
--============================================================================

-- Cached pixel scale (calculated once per UI load, reused everywhere)
local CACHED_PIXEL_SCALE = nil

-- Calculate exact pixel size for 1px borders
-- Formula: Physical pixel = (768 / ScreenHeight) / UIScale
-- This ensures borders are always 1 physical pixel regardless of resolution or UI scale
local function GetPixelScale()
    if CACHED_PIXEL_SCALE then return CACHED_PIXEL_SCALE end
    
    -- Get current resolution
    local resolution = GetCVar("gxWindowedResolution") or "1920x1080"
    local width, height = string.match(resolution, "(%d+)x(%d+)")
    height = tonumber(height) or 1080
    
    -- Calculate physical pixel size
    -- 768 is WoW's base resolution height for UI calculations
    local pixelScale = 768 / height
    
    -- Adjust for UI scale
    local uiScale = UIParent:GetScale() or 1
    CACHED_PIXEL_SCALE = pixelScale / uiScale
    
    return CACHED_PIXEL_SCALE
end

-- Reset pixel scale cache (call this if UI scale changes)
local function ResetPixelScale()
    CACHED_PIXEL_SCALE = nil
end

--============================================================================
-- COLOR CONSTANTS
--============================================================================

-- Calculate all theme variations from a master color
local function CalculateThemeColors(masterR, masterG, masterB)
    -- Helper: Desaturate color
    local function Desaturate(r, g, b, amount)
        local gray = (r + g + b) / 3
        return r + (gray - r) * amount, 
               g + (gray - g) * amount, 
               b + (gray - b) * amount
    end
    
    -- Helper: Adjust brightness
    local function AdjustBrightness(r, g, b, factor)
        return math.min(1, r * factor),
               math.min(1, g * factor),
               math.min(1, b * factor)
    end
    
    -- Calculate variations and wrap in arrays
    local darkR, darkG, darkB = AdjustBrightness(masterR, masterG, masterB, 0.7)
    local borderR, borderG, borderB = Desaturate(masterR * 0.5, masterG * 0.5, masterB * 0.5, 0.6)
    local activeR, activeG, activeB = AdjustBrightness(masterR, masterG, masterB, 0.5)
    local hoverR, hoverG, hoverB = AdjustBrightness(masterR, masterG, masterB, 0.6)
    
    return {
        accent = {masterR, masterG, masterB},
        accentDark = {darkR, darkG, darkB},
        border = {borderR, borderG, borderB},
        tabActive = {activeR, activeG, activeB},
        tabHover = {hoverR, hoverG, hoverB},
    }
end

-- Get theme colors from database (with fallbacks)
local function GetThemeColors()
    local db = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local themeColors = db and db.themeColors or {}
    
    return {
        accent = themeColors.accent or {0.40, 0.20, 0.58},
        accentDark = themeColors.accentDark or {0.28, 0.14, 0.41},
        border = themeColors.border or {0.20, 0.20, 0.25},
        tabActive = themeColors.tabActive or {0.20, 0.12, 0.30},
        tabHover = themeColors.tabHover or {0.24, 0.14, 0.35},
    }
end

-- Modern Color Palette (Dynamic - updates from database)
local function GetColors()
    local theme = GetThemeColors()
    
    return {
        bg = {0.06, 0.06, 0.08, 0.98},
        bgLight = {0.10, 0.10, 0.12, 1},
        bgCard = {0.08, 0.08, 0.10, 1},
        border = {theme.border[1], theme.border[2], theme.border[3], 1},
        borderLight = {0.30, 0.30, 0.38, 1},
        accent = {theme.accent[1], theme.accent[2], theme.accent[3], 1},
        accentDark = {theme.accentDark[1], theme.accentDark[2], theme.accentDark[3], 1},
        tabActive = {theme.tabActive[1], theme.tabActive[2], theme.tabActive[3], 1},
        tabHover = {theme.tabHover[1], theme.tabHover[2], theme.tabHover[3], 1},
        tabInactive = {0.08, 0.08, 0.10, 1},
        gold = {1.00, 0.82, 0.00, 1},
        green = {0.30, 0.90, 0.30, 1},
        red = {0.95, 0.30, 0.30, 1},
        textBright = {1, 1, 1, 1},  -- Pure white for all text
        textNormal = {0.85, 0.85, 0.85, 1},
        textDim = {0.55, 0.55, 0.55, 1},
        white = {1, 1, 1, 1},  -- Global white color constant
    }
end

-- Create initial COLORS table
local COLORS = GetColors()
ns.UI_COLORS = COLORS -- Export immediately

--============================================================================
-- SPACING CONSTANTS (Standardized across all tabs)
--============================================================================

-- Unified spacing constants
local UI_SPACING = {
    -- Legacy camelCase (for backward compatibility)
    afterHeader = 75,
    betweenSections = 8,   -- Same as SECTION_SPACING (expansion spacing)
    betweenRows = 0,
    headerSpacing = 40,
    afterElement = 8,
    cardGap = 8,
    rowHeight = 26,
    charRowHeight = 30,
    headerHeight = 32,
    rowSpacing = 26,
    sideMargin = 10,
    topMargin = 8,
    subHeaderSpacing = 40,
    emptyStateSpacing = 100,
    minBottomSpacing = 20,
    
    -- Horizontal indentation (levels)
    BASE_INDENT = 15,          -- Base indent unit (15px per level)
    SUBROW_EXTRA_INDENT = 10,  -- Extra indent for sub-rows (total Level 2 = 40px)
    -- Usage: Level 0 = 0px, Level 1 = BASE_INDENT (15px), Level 2 = BASE_INDENT * 2 + SUBROW_EXTRA_INDENT (40px)
    
    -- Margins
    SIDE_MARGIN = 10,          -- Left/right content margin
    TOP_MARGIN = 8,            -- Top content margin
    
    -- Vertical spacing (between elements)
    HEADER_SPACING = 40,       -- Space after headers
    SUBHEADER_SPACING = 40,    -- Space after sub-headers
    ROW_SPACING = 26,          -- Space after rows (26px height + 0px gap for tight layout)
    SECTION_SPACING = 8,       -- Space between sections (expansion/type spacing, smaller than HEADER_SPACING)
    EMPTY_STATE_SPACING = 100, -- Empty state message spacing
    MIN_BOTTOM_SPACING = 20,   -- Minimum bottom padding
    
    -- Row dimensions
    ROW_HEIGHT = 26,           -- Standard row height
    CHAR_ROW_HEIGHT = 36,      -- Character row height (+20% from 30)
    HEADER_HEIGHT = 32,        -- Collapsible header height
    
    -- Icon standardization
    headerIconSize = 24,       -- Header icon size (reduced from 28 for better balance)
    rowIconSize = 20,          -- Row icon size (reduced from 22 for better balance)
    iconVerticalAlign = 0,     -- CENTER vertical alignment offset
    
    -- Row colors (alternating backgrounds)
    ROW_COLOR_EVEN = {0.08, 0.08, 0.10, 1},  -- Even rows (slightly lighter)
    ROW_COLOR_ODD = {0.06, 0.06, 0.08, 1},   -- Odd rows (slightly darker)
}

-- Export to namespace (both names for compatibility)
ns.UI_SPACING = UI_SPACING
ns.UI_LAYOUT = UI_SPACING  -- Alias for backward compatibility

-- Keep old reference
local UI_LAYOUT = UI_SPACING

-- Refresh COLORS table from database
local function RefreshColors()
    -- Immediate update
    local newColors = GetColors()
    for k, v in pairs(newColors) do
        COLORS[k] = v
    end
    -- Also update the namespace reference
    ns.UI_COLORS = COLORS
    
        -- Update main frame colors if it exists
        if WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame then
            local f = WarbandNexus.UI.mainFrame
            local accentColor = COLORS.accent
            
            -- Update main tab buttons (activeBar highlight and glow only)
            if f.tabButtons then
                for tabKey, btn in pairs(f.tabButtons) do
                    local isActive = f.currentTab == tabKey
                    
                    -- Update activeBar (bottom highlight line)
                    if btn.activeBar then
                        btn.activeBar:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], 1)
                    end
                    
                    -- Update glow
                    if btn.glow then
                        btn.glow:SetColorTexture(accentColor[1], accentColor[2], accentColor[3], isActive and 0.25 or 0.15)
                    end
                end
            end
            
            -- Refresh content to update dynamic elements (without infinite loop)
            if f:IsShown() and WarbandNexus.RefreshUI then
                WarbandNexus:RefreshUI()
            end
        end
    
    -- Notify NotificationManager about color change
    if WarbandNexus and WarbandNexus.RefreshNotificationColors then
        WarbandNexus:RefreshNotificationColors()
    end
end

-- Quality colors (hex)
local QUALITY_COLORS = {
    [0] = "9d9d9d", -- Poor (Gray)
    [1] = "ffffff", -- Common (White)
    [2] = "1eff00", -- Uncommon (Green)
    [3] = "0070dd", -- Rare (Blue)
    [4] = "a335ee", -- Epic (Purple)
    [5] = "ff8000", -- Legendary (Orange)
    [6] = "e6cc80", -- Artifact (Gold)
    [7] = "00ccff", -- Heirloom (Cyan)
}

-- Export to namespace
ns.UI_COLORS = COLORS
ns.UI_QUALITY_COLORS = QUALITY_COLORS

--============================================================================
-- VISUAL SYSTEM (Pixel Perfect 4-Texture Borders)
--============================================================================

-- Apply background and 1px borders to any frame (ElvUI Sandwich Method)
-- Border sits INSIDE the frame, on top of backdrop, below content
local function ApplyVisuals(frame, bgColor, borderColor)
    if not frame then return end
    
    -- Ensure frame has backdrop capability
    if not frame.SetBackdrop then
        Mixin(frame, BackdropTemplateMixin)
    end
    
    -- Set background (NO edgeFile to prevent conflicts)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8"
    })
    
    -- Apply background color
    if bgColor then
        frame:SetBackdropColor(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 1)
    end
    
    -- Create 4-texture border system (Create Once) - SANDWICH METHOD
    -- Borders are INSIDE the frame, using BORDER layer (between backdrop and content)
    if not frame.BorderTop then
        local mult = GetPixelScale()  -- Always 1px
        
        -- Top border (INSIDE frame, at the top edge)
        frame.BorderTop = frame:CreateTexture(nil, "BORDER")
        frame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
        frame.BorderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        frame.BorderTop:SetHeight(1)  -- Hard-coded 1px
        -- Anti-flicker optimization: Let WoW handle sub-pixel smoothing during resize
        frame.BorderTop:SetSnapToPixelGrid(false)
        frame.BorderTop:SetTexelSnappingBias(0)
        frame.BorderTop:SetDrawLayer("BORDER", 0)
        
        -- Bottom border (INSIDE frame, at the bottom edge)
        frame.BorderBottom = frame:CreateTexture(nil, "BORDER")
        frame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
        frame.BorderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
        frame.BorderBottom:SetHeight(1)  -- Hard-coded 1px
        -- Anti-flicker optimization
        frame.BorderBottom:SetSnapToPixelGrid(false)
        frame.BorderBottom:SetTexelSnappingBias(0)
        frame.BorderBottom:SetDrawLayer("BORDER", 0)
        
        -- Left border (INSIDE frame, at the left edge, between top and bottom)
        frame.BorderLeft = frame:CreateTexture(nil, "BORDER")
        frame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -1)
        frame.BorderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 1)
        frame.BorderLeft:SetWidth(1)  -- Hard-coded 1px
        -- Anti-flicker optimization
        frame.BorderLeft:SetSnapToPixelGrid(false)
        frame.BorderLeft:SetTexelSnappingBias(0)
        frame.BorderLeft:SetDrawLayer("BORDER", 0)
        
        -- Right border (INSIDE frame, at the right edge, between top and bottom)
        frame.BorderRight = frame:CreateTexture(nil, "BORDER")
        frame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        frame.BorderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, -1)
        frame.BorderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 1)
        frame.BorderRight:SetWidth(1)  -- Hard-coded 1px
        -- Anti-flicker optimization
        frame.BorderRight:SetSnapToPixelGrid(false)
        frame.BorderRight:SetTexelSnappingBias(0)
        frame.BorderRight:SetDrawLayer("BORDER", 0)
        
        -- Apply border color (only on creation)
        if borderColor then
            local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
            frame.BorderTop:SetVertexColor(r, g, b, a)
            frame.BorderBottom:SetVertexColor(r, g, b, a)
            frame.BorderLeft:SetVertexColor(r, g, b, a)
            frame.BorderRight:SetVertexColor(r, g, b, a)
        end
    end
end

-- Export to namespace
ns.UI_ApplyVisuals = ApplyVisuals
ns.UI_ResetPixelScale = ResetPixelScale

-- Auto-reset pixel scale cache when UI scale changes
-- This ensures borders remain 1px after user changes UI scale via /reload
local scaleWatcher = CreateFrame("Frame")
scaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
scaleWatcher:SetScript("OnEvent", function(self, event)
    if event == "UI_SCALE_CHANGED" then
        ResetPixelScale()
        -- Note: Borders will update on next frame creation, existing frames keep current scale
    end
end)

--[[
    Apply hover effect to a frame
    Creates a highlight texture that shows on mouse-over
    @param frame frame - Frame to apply hover effect to
    @param intensity number - Alpha intensity (0.1=subtle, 0.15=medium, 0.25=strong, default=0.25)
]]
local function ApplyHoverEffect(frame, intensity)
    if not frame then return end
    
    intensity = intensity or 0.25
    
    -- Only create if doesn't exist
    if not frame.hoverTexture then
        local hover = frame:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints(frame)
        hover:SetColorTexture(1, 1, 1, intensity)
        hover:SetBlendMode("ADD")
        
        -- Anti-flicker optimization
        hover:SetSnapToPixelGrid(false)
        hover:SetTexelSnappingBias(0)
        
        frame.hoverTexture = hover
    end
end

--[[
    Update border color for an existing frame (for dynamic state changes)
    @param frame frame - Frame with borders already created by ApplyVisuals
    @param borderColor table - Border color {r,g,b,a}
]]
local function UpdateBorderColor(frame, borderColor)
    if not frame or not frame.BorderTop then return end
    
    local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
    frame.BorderTop:SetVertexColor(r, g, b, a)
    frame.BorderBottom:SetVertexColor(r, g, b, a)
    frame.BorderLeft:SetVertexColor(r, g, b, a)
    frame.BorderRight:SetVertexColor(r, g, b, a)
end

-- Export to namespace
ns.UI_ApplyHoverEffect = ApplyHoverEffect
ns.UI_UpdateBorderColor = UpdateBorderColor

--============================================================================
-- COMMON UI FRAME WRAPPERS (Reusable Components)
--============================================================================

--[[
    Create a notice/error frame with icon, title, and description
    @param parent frame - Parent frame
    @param title string - Notice title (e.g., "Currency Transfer Limitation")
    @param description string - Notice description text
    @param iconType string - Icon type: "alert", "info", "warning" (optional, defaults to "info")
    @param width number - Frame width (optional, uses parent width - 20)
    @param height number - Frame height (optional, defaults to 60)
    @return frame - Created notice frame
]]
local function CreateNoticeFrame(parent, title, description, iconType, width, height)
    if not parent or not title or not description then return nil end
    
    local parentWidth = parent:GetWidth() or 800
    local frameWidth = width or (parentWidth - 20)
    local frameHeight = height or 60
    
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(frameWidth, frameHeight)
    
    -- Icon selection
    local iconTextures = {
        alert = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
        info = "Interface\\FriendsFrame\\InformationIcon",
        warning = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
    }
    local iconTexture = iconTextures[iconType] or iconTextures.info
    
    -- Icon
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture(iconTexture)
    
    -- Title
    local titleText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", icon, "RIGHT", 10, 5)
    titleText:SetPoint("RIGHT", -10, 5)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("|cffffcc00" .. title .. "|r")
    
    -- Description
    local descText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    descText:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -15)
    descText:SetPoint("RIGHT", -10, 0)
    descText:SetJustifyH("LEFT")
    descText:SetTextColor(1, 1, 1)  -- White
    descText:SetText(description)
    
    return frame
end

--[[
    Create a results container for search/browse results
    @param parent frame - Parent frame
    @param yOffset number - Vertical offset from parent top
    @param sideMargin number - Side margin (optional, defaults to 10)
    @return frame - Created results container
]]
local function CreateResultsContainer(parent, yOffset, sideMargin)
    if not parent then return nil end
    
    local margin = sideMargin or 10
    
    local container = CreateFrame("Frame", nil, parent)
    container:SetPoint("TOPLEFT", margin, -yOffset)
    container:SetPoint("TOPRIGHT", -margin, 0)
    container:SetHeight(2000)  -- Large enough for scroll content
    
    return container
end

--[[
    Create a stats bar with text display
    @param parent frame - Parent frame
    @param height number - Bar height (optional, defaults to 24)
    @return frame, fontString - Created stats bar and text element
]]
local function CreateStatsBar(parent, height)
    if not parent then return nil end
    
    local barHeight = height or 24
    
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(barHeight)
    
    local text = bar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", 10, 0)
    text:SetTextColor(1, 1, 1)  -- White
    
    return bar, text
end

-- Export to namespace
ns.UI_CreateNoticeFrame = CreateNoticeFrame
ns.UI_CreateResultsContainer = CreateResultsContainer
ns.UI_CreateStatsBar = CreateStatsBar

--============================================================================
-- UI COMPONENT FACTORY (Pixel-Perfect Components with Auto-Border)
--============================================================================
--[[
    These factory functions create standard UI components with automatic:
    - Pixel-perfect borders (ElvUI sandwich method)
    - Anti-flicker optimization
    - Consistent styling
    
    Usage:
    Instead of:
        local icon = CreateFrame("Frame", nil, parent)
        local tex = icon:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture(12345)
        -- Missing: border, anti-flicker, pixel perfect
    
    Use:
        local iconFrame = ns.UI_CreateIcon(parent, 12345, 32)
        -- Automatically includes: frame, texture, border, anti-flicker, pixel perfect!
]]

--[[
    Create a pixel-perfect icon with border
    @param parent frame - Parent frame
    @param texture string/number - Texture path, atlas name, or fileID
    @param size number - Icon size (default 32)
    @param isAtlas boolean - If true, use SetAtlas instead of SetTexture (default false)
    @param borderColor table - Border color {r,g,b,a} (default accent)
    @param noBorder boolean - If true, skip border (default false)
    @return frame - Icon frame with .texture accessible
]]
local function CreateIcon(parent, texture, size, isAtlas, borderColor, noBorder)
    if not parent then return nil end
    
    size = size or 32
    isAtlas = isAtlas or false
    borderColor = borderColor or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    noBorder = noBorder or false
    
    -- Container frame
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(size, size)
    
    -- Apply pixel-perfect border (unless noBorder is true)
    if not noBorder then
        ApplyVisuals(frame, {0.05, 0.05, 0.07, 0.95}, borderColor)
    end
    
    -- Icon texture (inset by 2px if border, otherwise fill frame)
    local tex = frame:CreateTexture(nil, "ARTWORK")
    if noBorder then
        tex:SetAllPoints()
    else
        tex:SetPoint("TOPLEFT", 2, -2)
        tex:SetPoint("BOTTOMRIGHT", -2, 2)
    end
    
    -- Set texture or atlas
    if texture then
        if isAtlas then
            -- Use atlas (modern WoW UI system)
            tex:SetAtlas(texture, false)  -- false = don't use atlas size
        else
            -- Use texture path or fileID
            if type(texture) == "string" then
                tex:SetTexture(texture)
            else
                tex:SetTexture(texture)  -- FileID (number)
            end
            -- Zoom effect (trim ugly edges) - only for textures, not atlas
            tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
    
    -- Anti-flicker optimization
    tex:SetSnapToPixelGrid(false)
    tex:SetTexelSnappingBias(0)
    
    -- Store texture reference
    frame.texture = tex
    
    return frame
end

--[[
    Create a pixel-perfect status bar (progress bar) with border
    @param parent frame - Parent frame
    @param width number - Bar width (default 200)
    @param height number - Bar height (default 14)
    @param bgColor table - Background color {r,g,b,a} (default dark)
    @param borderColor table - Border color {r,g,b,a} (default black)
    @return frame - StatusBar frame
]]
local function CreateStatusBar(parent, width, height, bgColor, borderColor)
    if not parent then return nil end
    
    width = width or 200
    height = height or 14
    bgColor = bgColor or {0.05, 0.05, 0.07, 0.95}
    borderColor = borderColor or {0, 0, 0, 1}
    
    -- Container frame
    local frame = CreateFrame("StatusBar", nil, parent)
    frame:SetSize(width, height)
    
    -- Apply pixel-perfect border
    ApplyVisuals(frame, bgColor, borderColor)
    
    -- Status bar texture (solid fill, inset by 1px to not overlap border)
    frame:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
    local barTexture = frame:GetStatusBarTexture()
    barTexture:SetDrawLayer("ARTWORK", 0)
    
    -- Anti-flicker optimization on bar texture
    barTexture:SetSnapToPixelGrid(false)
    barTexture:SetTexelSnappingBias(0)
    
    -- Default values
    frame:SetMinMaxValues(0, 1)
    frame:SetValue(0)
    
    return frame
end

--[[
    Create a pixel-perfect button with border (for rows, cards, etc.)
    @param parent frame - Parent frame
    @param width number - Button width
    @param height number - Button height
    @param bgColor table - Background color {r,g,b,a} (default dark)
    @param borderColor table - Border color {r,g,b,a} (default accent)
    @return button - Button frame
]]
local function CreateButton(parent, width, height, bgColor, borderColor)
    if not parent then return nil end
    
    bgColor = bgColor or {0.05, 0.05, 0.07, 0.95}
    borderColor = borderColor or {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    
    -- Button frame
    local button = CreateFrame("Button", nil, parent)
    if width and height then
        button:SetSize(width, height)
    end
    
    -- Apply pixel-perfect border
    ApplyVisuals(button, bgColor, borderColor)
    
    -- Apply strong hover effect (0.25 intensity)
    ApplyHoverEffect(button, 0.25)
    
    return button
end

--[[
    Create a two-line button (character row style)
    Includes space for icon, main text, and sub text
    @param parent frame - Parent frame
    @param width number - Button width
    @param height number - Button height (default 38)
    @return button - Button with .icon, .mainText, .subText
]]
local function CreateTwoLineButton(parent, width, height)
    if not parent then return nil end
    
    height = height or 38
    
    -- Create button with border
    local button = CreateButton(parent, width, height)
    
    -- Icon (left side, inset by 5px from border)
    button.icon = button:CreateTexture(nil, "ARTWORK")
    button.icon:SetSize(28, 28)
    button.icon:SetPoint("LEFT", 10, 0)
    button.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    -- Anti-flicker
    button.icon:SetSnapToPixelGrid(false)
    button.icon:SetTexelSnappingBias(0)
    
    -- Main text (upper line)
    button.mainText = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    button.mainText:SetPoint("LEFT", button.icon, "RIGHT", 8, 6)
    button.mainText:SetJustifyH("LEFT")
    button.mainText:SetTextColor(1, 1, 1)
    
    -- Sub text (lower line, smaller)
    button.subText = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    button.subText:SetPoint("LEFT", button.icon, "RIGHT", 8, -6)
    button.subText:SetJustifyH("LEFT")
    button.subText:SetTextColor(0.7, 0.7, 0.7)
    
    return button
end

--[[
    Create a reputation progress bar with dynamic fill and colors
    Handles Paragon, Renown, and Classic reputation systems
    @param parent frame - Parent frame (usually a row)
    @param width number - Bar width (default 200)
    @param height number - Bar height (default 14)
    @param currentValue number - Current reputation value
    @param maxValue number - Max reputation value
    @param isParagon boolean - If true, use paragon styling
    @param isMaxed boolean - If true, fill bar 100% and use green color
    @param standingID number - Standing ID for color (optional)
    @return bgFrame, fillTexture - Background frame and fill texture
]]
local function CreateReputationProgressBar(parent, width, height, currentValue, maxValue, isParagon, isMaxed, standingID)
    if not parent then return nil, nil end
    
    width = width or 200
    height = height or 14
    currentValue = currentValue or 0
    maxValue = maxValue or 1
    
    -- Background frame
    local bgFrame = CreateFrame("Frame", nil, parent)
    bgFrame:SetSize(width, height)
    
    -- Background texture (dark)
    local bgTexture = bgFrame:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetAllPoints()
    bgTexture:SetColorTexture(0.1, 0.1, 0.1, 0.8)
    bgTexture:SetSnapToPixelGrid(false)
    bgTexture:SetTexelSnappingBias(0)
    
    -- Calculate progress
    local progress = maxValue > 0 and (currentValue / maxValue) or 0
    progress = math.min(1, math.max(0, progress))
    
    -- If maxed and not paragon, fill 100%
    if isMaxed and not isParagon then
        progress = 1
    end
    
    -- Only create fill if there's progress
    local fillTexture = nil
    if currentValue > 0 or isMaxed then
        fillTexture = bgFrame:CreateTexture(nil, "ARTWORK")
        fillTexture:SetPoint("LEFT", bgFrame, "LEFT", 0, 0)
        fillTexture:SetHeight(height)
        fillTexture:SetWidth(width * progress)
        fillTexture:SetSnapToPixelGrid(false)
        fillTexture:SetTexelSnappingBias(0)
        
        -- Color based on type
        if isMaxed and not isParagon then
            -- Maxed: Green
            fillTexture:SetColorTexture(0, 0.8, 0, 1)
        elseif isParagon then
            -- Paragon: Pink
            fillTexture:SetColorTexture(1, 0.4, 1, 1)
        elseif standingID then
            -- Use standing color
            local function GetStandingColor(standingID)
                local colors = {
                    [1] = {0.8, 0.13, 0.13}, -- Hated
                    [2] = {0.8, 0.13, 0.13}, -- Hostile
                    [3] = {0.75, 0.27, 0}, -- Unfriendly
                    [4] = {0.9, 0.7, 0}, -- Neutral
                    [5] = {0, 0.6, 0.1}, -- Friendly
                    [6] = {0, 0.6, 0.1}, -- Honored
                    [7] = {0, 0.6, 0.1}, -- Revered
                    [8] = {0, 0.6, 0.1}, -- Exalted
                }
                local color = colors[standingID] or {0.9, 0.7, 0}
                return color[1], color[2], color[3]
            end
            local r, g, b = GetStandingColor(standingID)
            fillTexture:SetColorTexture(r, g, b, 1)
        else
            -- Default: Gold (for Renown/Friendship)
            fillTexture:SetColorTexture(1, 0.82, 0, 1)
        end
    end
    
    return bgFrame, fillTexture
end

-- Export factory functions to namespace
ns.UI_CreateIcon = CreateIcon
ns.UI_CreateStatusBar = CreateStatusBar
ns.UI_CreateButton = CreateButton
ns.UI_CreateTwoLineButton = CreateTwoLineButton
ns.UI_CreateReputationProgressBar = CreateReputationProgressBar

--============================================================================
-- FRAME POOLING SYSTEM (Performance Optimization)
--============================================================================
-- Reuse frames instead of creating new ones on every refresh
-- This dramatically reduces memory churn and GC pressure

local ItemRowPool = {}
local StorageRowPool = {}
local CurrencyRowPool = {}
local CharacterRowPool = {}
local ReputationRowPool = {}

-- Get a character row from pool or create new
local function AcquireCharacterRow(parent)
    local row = table.remove(CharacterRowPool)
    
    if not row then
        row = CreateFrame("Button", nil, parent)
        row.isPooled = true
        row.rowType = "character"
        
        -- Apply hover effect to character rows
        ApplyHoverEffect(row, 0.25)
    end
    
    row:SetParent(parent)
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return character row to pool
local function ReleaseCharacterRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    
    -- Note: Child elements (favButton, etc.) are kept and reused
    
    table.insert(CharacterRowPool, row)
end

-- Get a reputation row from pool or create new
local function AcquireReputationRow(parent)
    local row = table.remove(ReputationRowPool)
    
    if not row then
        row = CreateFrame("Button", nil, parent)
        row.isPooled = true
        row.rowType = "reputation"
        
        -- Apply hover effect to reputation rows
        ApplyHoverEffect(row, 0.25)
    end
    
    row:SetParent(parent)
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return reputation row to pool
local function ReleaseReputationRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    
    table.insert(ReputationRowPool, row)
end

-- Get a currency row from pool or create new
local function AcquireCurrencyRow(parent, width, rowHeight)
    local row = table.remove(CurrencyRowPool)
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Apply hover effect to currency rows
        ApplyHoverEffect(row, 0.25)
        
        -- No background
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.rowIconSize
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 15, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", 43, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Amount text
        row.amountText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.amountText:SetPoint("RIGHT", -10, 0)
        row.amountText:SetWidth(150)
        row.amountText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.rowType = "currency"  -- Mark as CurrencyRow
    end
    
    -- CRITICAL: Always set parent when acquiring from pool
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return currency row to pool
local function ReleaseCurrencyRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    
    -- Reset icon
    if row.icon then
        row.icon:SetTexture(nil)
        row.icon:SetAlpha(1)
    end
    
    -- Reset texts
    if row.nameText then
        row.nameText:SetText("")
        row.nameText:SetTextColor(1, 1, 1)
    end
    
    if row.amountText then
        row.amountText:SetText("")
        row.amountText:SetTextColor(1, 1, 1)
    end
    
    -- Reset badge text (for Show All mode)
    if row.badgeText then
        row.badgeText:SetText("")
        row.badgeText:Hide()
    end
    
    -- Reset background removed (no backdrop)
    
    table.insert(CurrencyRowPool, row)
end

-- Get an item row from pool or create new
local function AcquireItemRow(parent, width, rowHeight)
    local row = table.remove(ItemRowPool)
    
    if not row then
        -- Create new button with all children
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Apply hover effect to item rows
        ApplyHoverEffect(row, 0.25)
        
        -- Background texture
        row.bg = row:CreateTexture(nil, "BACKGROUND")
        row.bg:SetAllPoints()
        -- Anti-flicker optimization
        row.bg:SetSnapToPixelGrid(false)
        row.bg:SetTexelSnappingBias(0)
        
        -- Quantity text (left)
        row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.rowIconSize
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 70, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Location text
        row.locationText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(60)
        row.locationText:SetJustifyH("RIGHT")

        row.isPooled = true
        row.rowType = "item"  -- Mark as ItemRow
    end
    
    -- No border for items rows
    row:SetParent(parent)
    row:SetSize(width, rowHeight)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return item row to pool
local function ReleaseItemRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    row:SetScript("OnEnter", nil)
    row:SetScript("OnLeave", nil)
    
    table.insert(ItemRowPool, row)
end

-- Get storage row from pool (updated to match Items tab style)
local function AcquireStorageRow(parent, width, rowHeight)
    local row = table.remove(StorageRowPool)
    
    if not row then
        -- Create new button with all children (Button for hover effects)
        row = CreateFrame("Button", nil, parent)
        row:EnableMouse(true)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        
        -- Apply hover effect to storage rows
        ApplyHoverEffect(row, 0.25)
        
        -- Background texture removed (naked frame)
        
        -- Quantity text (left)
        row.qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.qtyText:SetPoint("LEFT", 15, 0)
        row.qtyText:SetWidth(45)
        row.qtyText:SetJustifyH("RIGHT")
        
        -- Icon
        row.icon = row:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.rowIconSize
        row.icon:SetSize(iconSize, iconSize)
        row.icon:SetPoint("LEFT", 70, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Padding for cleaner edges
        -- Anti-flicker optimization
        row.icon:SetSnapToPixelGrid(false)
        row.icon:SetTexelSnappingBias(0)
        
        -- Name text
        row.nameText = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.nameText:SetPoint("LEFT", 98, 0)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        
        -- Location text
        row.locationText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        row.locationText:SetPoint("RIGHT", -10, 0)
        row.locationText:SetWidth(60)
        row.locationText:SetJustifyH("RIGHT")
        
        row.isPooled = true
        row.isPooled = true
        row.rowType = "storage"  -- Mark as StorageRow
    end
    
    -- No border for storage rows
    
    row:SetParent(parent)
    row:SetSize(width, rowHeight or 26)
    row:SetFrameLevel(parent:GetFrameLevel() + 1)  -- Ensure proper z-order
    row:Show()
    
    -- CRITICAL FIX: Reset alpha and stop animations to prevent invisible rows
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    
    return row
end

-- Return storage row to pool
local function ReleaseStorageRow(row)
    if not row or not row.isPooled then return end
    
    row:Hide()
    row:ClearAllPoints()
    
    -- Only clear scripts that exist
    if row.HasScript and row:HasScript("OnEnter") then
        row:SetScript("OnEnter", nil)
    end
    if row.HasScript and row:HasScript("OnLeave") then
        row:SetScript("OnLeave", nil)
    end
    if row.HasScript and row:HasScript("OnClick") then
        row:SetScript("OnClick", nil)
    end
    
    table.insert(StorageRowPool, row)
end

-- Release all pooled children of a frame (and hide non-pooled ones)
local function ReleaseAllPooledChildren(parent)
    local children = {parent:GetChildren()}  -- Reuse table, don't create new one each iteration
    for i, child in pairs(children) do
        if child.isPooled and child.rowType then
            -- Use rowType to determine which pool to release to
            if child.rowType == "item" then
                ReleaseItemRow(child)
            elseif child.rowType == "storage" then
                ReleaseStorageRow(child)
            elseif child.rowType == "currency" then
                ReleaseCurrencyRow(child)
            elseif child.rowType == "character" then
                ReleaseCharacterRow(child)
            elseif child.rowType == "reputation" then
                ReleaseReputationRow(child)
            end
        else
            -- Non-pooled frame (like headers, cards, etc.)
            -- Skip persistent row elements (reorderButtons, deleteBtn, etc.)
            -- These are managed by their parent row and should not be hidden here
            if not child.isPersistentRowElement then
                pcall(function()
                    child:Hide()
                    child:ClearAllPoints()
                end)
            end
            
            -- Clear scripts only for widgets that support them
            -- Use HasScript to check if the widget actually supports the script type
            if child.SetScript and child.HasScript then
                local childType = child:GetObjectType()
                -- Only clear scripts that the widget actually supports
                if child:HasScript("OnClick") then
                    local success = pcall(function() child:SetScript("OnClick", nil) end)
                    if not success then
                        print("|cffff0000WN DEBUG: Failed to clear OnClick on", childType, "at index", i, "|r")
                    end
                end
                if child:HasScript("OnEnter") then
                    pcall(function() child:SetScript("OnEnter", nil) end)
                end
                if child:HasScript("OnLeave") then
                    pcall(function() child:SetScript("OnLeave", nil) end)
                end
                if child:HasScript("OnMouseDown") then
                    pcall(function() child:SetScript("OnMouseDown", nil) end)
                end
                if child:HasScript("OnMouseUp") then
                    pcall(function() child:SetScript("OnMouseUp", nil) end)
                end
            end
        end
    end
end

--============================================================================
-- UI HELPER FUNCTIONS
--============================================================================

-- Get quality color as hex string
local function GetQualityHex(quality)
    return QUALITY_COLORS[quality] or "ffffff"
end

-- Get accent color as hex string
local function GetAccentHexColor()
    local c = COLORS.accent
    return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Create a card frame (common UI element)
local function CreateCard(parent, height)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(height or 100)
    
    -- Apply pixel-perfect visuals with accent border (ElvUI sandwich method)
    local accentColor = COLORS.accent
    ApplyVisuals(card, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    
    return card
end

-- Format gold amount with separators and icon (legacy - simple gold display)
local function FormatGold(copper)
    local gold = math.floor((copper or 0) / 10000)
    local goldStr = tostring(gold)
    local k
    while true do
        goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1.%2')
        if k == 0 then break end
    end
    return goldStr .. "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
end

--[[
    Format money with gold, silver, and copper
    @param copper number - Total copper amount
    @param iconSize number - Icon size (optional, default 14)
    @param showZero boolean - Show zero values (optional, default false)
    @return string - Formatted money string with colors and icons
]]
local function FormatMoney(copper, iconSize, showZero)
    -- Validate and sanitize inputs
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    iconSize = tonumber(iconSize) or 14
    -- Clamp iconSize to safe range to prevent integer overflow in texture rendering
    if iconSize < 8 then iconSize = 8 end
    if iconSize > 32 then iconSize = 32 end
    showZero = showZero or false
    
    -- Calculate gold, silver, copper with explicit floor operations
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = math.floor(copper % 100)
    
    -- Build formatted string
    local parts = {}
    
    -- Gold (yellow/golden)
    if gold > 0 or showZero then
        -- Add thousand separators for gold
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        table.insert(parts, string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t", goldStr, iconSize, iconSize))
    end
    
    -- Silver (silver/gray) - Only pad if gold exists
    if silver > 0 or (showZero and gold > 0) then
        local fmt = (gold > 0) and "%02d" or "%d"
        table.insert(parts, string.format("|cffc7c7cf" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t", silver, iconSize, iconSize))
    end
    
    -- Copper (bronze/copper) - Only pad if silver or gold exists
    if copperAmount > 0 or showZero or (gold == 0 and silver == 0) then
        local fmt = (gold > 0 or silver > 0) and "%02d" or "%d"
        table.insert(parts, string.format("|cffeda55f" .. fmt .. "|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t", copperAmount, iconSize, iconSize))
    end
    
    return table.concat(parts, " ")
end

--[[
    Format money compact (short version, only highest denomination)
    @param copper number - Total copper amount
    @param iconSize number - Icon size (optional, default 14)
    @return string - Compact formatted money string
]]
local function FormatMoneyCompact(copper, iconSize)
    -- Validate and sanitize inputs
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    iconSize = tonumber(iconSize) or 14
    -- Clamp iconSize to safe range to prevent integer overflow in texture rendering
    if iconSize < 8 then iconSize = 8 end
    if iconSize > 32 then iconSize = 32 end
    
    local gold = math.floor(copper / 10000)
    local silver = math.floor((copper % 10000) / 100)
    local copperAmount = math.floor(copper % 100)
    
    -- Show only the highest denomination
    if gold > 0 then
        local goldStr = tostring(gold)
        local k
        while true do
            goldStr, k = string.gsub(goldStr, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return string.format("|cffffd700%s|r|TInterface\\MoneyFrame\\UI-GoldIcon:%d:%d:2:0|t", goldStr, iconSize, iconSize)
    elseif silver > 0 then
        return string.format("|cffc7c7cf%d|r|TInterface\\MoneyFrame\\UI-SilverIcon:%d:%d:2:0|t", silver, iconSize, iconSize)
    else
        return string.format("|cffeda55f%d|r|TInterface\\MoneyFrame\\UI-CopperIcon:%d:%d:2:0|t", copperAmount, iconSize, iconSize)
    end
end

-- Create collapsible header with expand/collapse button (NO pooling - headers are few)
local function CreateCollapsibleHeader(parent, text, key, isExpanded, onToggle, iconTexture, isAtlas, indentLevel)
    -- Support for nested headers (indentLevel: 0 = root, 1 = child, etc.)
    indentLevel = indentLevel or 0
    local indent = indentLevel * UI_LAYOUT.BASE_INDENT
    
    -- Create new header (no pooling for headers - they're infrequent and context-specific)
    local header = CreateFrame("Button", nil, parent)
    header:SetSize(parent:GetWidth() - 20 - indent, 32)
    
    -- Apply pixel-perfect visuals with accent border
    local accentColor = COLORS.accent
    ApplyVisuals(header, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    
    -- Expand/Collapse icon (texture-based)
    local expandIcon = header:CreateTexture(nil, "ARTWORK")
    expandIcon:SetSize(16, 16)
    expandIcon:SetPoint("LEFT", 12 + indent, 0)
    
    -- Use WoW's built-in plus/minus button textures
    if isExpanded then
        expandIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
    else
        expandIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
    end
    -- Dynamic theme color tint
    local iconTint = COLORS.accent
    expandIcon:SetVertexColor(iconTint[1] * 1.5, iconTint[2] * 1.5, iconTint[3] * 1.5)
    -- Anti-flicker optimization
    expandIcon:SetSnapToPixelGrid(false)
    expandIcon:SetTexelSnappingBias(0)
    
    local textAnchor = expandIcon
    local textOffset = 8
    
    -- Optional icon (supports both texture paths and atlas names)
    local categoryIcon = nil
    if iconTexture then
        categoryIcon = header:CreateTexture(nil, "ARTWORK")
        local iconSize = UI_LAYOUT.headerIconSize
        categoryIcon:SetSize(iconSize, iconSize)
        categoryIcon:SetPoint("LEFT", expandIcon, "RIGHT", 8, 0)
        
        -- Use atlas if specified, otherwise texture path
        if isAtlas then
            categoryIcon:SetAtlas(iconTexture, false)
        else
            categoryIcon:SetTexture(iconTexture)
            -- Add texture coordinate padding for cleaner edges (only for textures, not atlas)
            categoryIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        -- Anti-flicker optimization
        categoryIcon:SetSnapToPixelGrid(false)
        categoryIcon:SetTexelSnappingBias(0)
        
        textAnchor = categoryIcon
        textOffset = 8
    end
    
    -- Header text
    local headerText = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    headerText:SetPoint("LEFT", textAnchor, "RIGHT", textOffset, 0)
    headerText:SetText(text)
    headerText:SetTextColor(1, 1, 1)  -- White
    
    -- Click handler
    header:SetScript("OnClick", function()
        isExpanded = not isExpanded
        -- Update icon texture
        if isExpanded then
            expandIcon:SetTexture("Interface\\Buttons\\UI-MinusButton-Up")
        else
            expandIcon:SetTexture("Interface\\Buttons\\UI-PlusButton-Up")
        end
        onToggle(isExpanded)
    end)
    
    -- Apply hover effect
    ApplyHoverEffect(header, 0.25)
    
    return header, expandIcon, categoryIcon
end

-- Get item type name from class ID
local function GetItemTypeName(classID)
    local typeName = GetItemClassInfo(classID)
    return typeName or "Other"
end

-- Get item class ID from item ID
local function GetItemClassID(itemID)
    if not itemID then return 15 end -- Miscellaneous
    local _, _, _, _, _, classID = C_Item.GetItemInfoInstant(itemID)
    return classID or 15
end

-- Get icon texture for item type
local function GetTypeIcon(classID)
    local icons = {
        [0] = "Interface\\Icons\\INV_Potion_51",          -- Consumable (Potion)
        [1] = "Interface\\Icons\\INV_Box_02",             -- Container
        [2] = "Interface\\Icons\\INV_Sword_27",           -- Weapon
        [3] = "Interface\\Icons\\INV_Misc_Gem_01",        -- Gem
        [4] = "Interface\\Icons\\INV_Chest_Cloth_07",     -- Armor
        [5] = "Interface\\Icons\\INV_Enchant_DustArcane", -- Reagent
        [6] = "Interface\\Icons\\INV_Ammo_Arrow_02",      -- Projectile
        [7] = "Interface\\Icons\\Trade_Engineering",      -- Trade Goods
        [8] = "Interface\\Icons\\INV_Misc_EnchantedScroll", -- Item Enhancement
        [9] = "Interface\\Icons\\INV_Scroll_04",          -- Recipe
        [12] = "Interface\\Icons\\INV_Misc_Key_03",       -- Quest (Key icon)
        [15] = "Interface\\Icons\\INV_Misc_Gear_01",      -- Miscellaneous
        [16] = "Interface\\Icons\\INV_Inscription_Tradeskill01", -- Glyph
        [17] = "Interface\\Icons\\PetJournalPortrait",    -- Battlepet
        [18] = "Interface\\Icons\\WoW_Token01",           -- WoW Token
    }
    return icons[classID] or "Interface\\Icons\\INV_Misc_Gear_01"
end

--============================================================================
-- CHARACTER ICON HELPERS (Faction, Race, Class)
--============================================================================

--[[
    Get faction icon texture path
    @param faction string - "Alliance", "Horde", or "Neutral"
    @return string - Texture path
]]
local function GetFactionIcon(faction)
    if faction == "Alliance" then
        return "Interface\\FriendsFrame\\PlusManz-Alliance"
    elseif faction == "Horde" then
        return "Interface\\FriendsFrame\\PlusManz-Horde"
    else
        -- Neutral (Pandaren starting zone or unknown)
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    end
end

--[[
    Get race-gender icon atlas name
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female)
    @return string - Atlas name
]]
local function GetRaceGenderAtlas(raceFile, gender)
    if not raceFile then
        return "shop-icon-housing-characters-up"
    end
    
    -- Map race file names to atlas names
    local raceMap = {
        ["BloodElf"] = "bloodelf",
        ["DarkIronDwarf"] = "darkirondwarf",
        ["Dracthyr"] = "dracthyrvisage",  -- Dracthyr uses visage form
        ["Draenei"] = "draenei",
        ["Dwarf"] = "dwarf",
        ["Earthen"] = "earthen",
        ["Gnome"] = "gnome",
        ["Goblin"] = "goblin",
        ["HighmountainTauren"] = "highmountain",
        ["Human"] = "human",
        ["KulTiran"] = "kultiran",
        ["LightforgedDraenei"] = "lightforged",
        ["MagharOrc"] = "magharorc",
        ["Mechagnome"] = "mechagnome",
        ["Nightborne"] = "nightborne",
        ["NightElf"] = "nightelf",
        ["Orc"] = "orc",
        ["Pandaren"] = "pandaren",
        ["Tauren"] = "tauren",
        ["Troll"] = "troll",
        ["Scourge"] = "undead",  -- Undead is "Scourge" in API
        ["Worgen"] = "worgen",
        ["ZandalariTroll"] = "zandalari",
        ["VoidElf"] = "voidelf",
        ["Vulpera"] = "vulpera",
    }
    
    local atlasRace = raceMap[raceFile]
    if not atlasRace then
        return "shop-icon-housing-characters-up"  -- Fallback
    end
    
    local genderStr = (gender == 3) and "female" or "male"
    
    return string.format("raceicon128-%s-%s", atlasRace, genderStr)
end

--[[
    Get race icon - NOW RETURNS ATLAS (not texture path)
    @param raceFile string - English race name (e.g., "BloodElf", "Human")
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @return string - Atlas name
]]
local function GetRaceIcon(raceFile, gender)
    -- NEW: Use atlas system with gender support
    return GetRaceGenderAtlas(raceFile, gender or 2)  -- Default to male if not provided
end

--[[
    Create faction icon on a frame
    @param parent frame - Parent frame
    @param faction string - "Alliance", "Horde", "Neutral"
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateFactionIcon(parent, faction, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetFactionIcon(faction))
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    return icon
end

--[[
    Create race icon on a frame (NEW: Auto-uses race-gender atlases)
    @param parent frame - Parent frame
    @param raceFile string - English race name
    @param gender number - Gender (2=male, 3=female) - Optional, defaults to male
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateRaceIcon(parent, raceFile, gender, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size or 28, size or 28)
    icon:SetPoint(point, x, y)
    
    -- Always use atlas system
    local atlasName = GetRaceIcon(raceFile, gender)  -- GetRaceIcon now returns atlas name
    icon:SetAtlas(atlasName, false)  -- false = don't use atlas size (we set it manually)
    
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    
    return icon
end

-- Export to namespace
ns.UI_GetFactionIcon = GetFactionIcon
ns.UI_GetRaceIcon = GetRaceIcon
ns.UI_GetRaceGenderAtlas = GetRaceGenderAtlas
ns.UI_CreateFactionIcon = CreateFactionIcon
ns.UI_CreateRaceIcon = CreateRaceIcon

-- ============================================================================
-- HEADER ICON SYSTEM (Standardized icon+border for all tab headers)
-- ============================================================================

-- Centralized icon mapping for all tabs
local TAB_HEADER_ICONS = {
    characters = "poi-town",
    items = "Banker",
    storage = "VignetteLoot",
    plans = "poi-islands-table",
    currency = "Auctioneer",
    reputation = "MajorFactions_MapIcons_Centaur64",
    pve = "Tormentors-Boss",
    statistics = "racing",
}

-- Centralized size configuration
local HEADER_ICON_SIZE = 41      -- Icon size
local HEADER_BORDER_SIZE = 51    -- Border size
local HEADER_ICON_XOFFSET = 18   -- X position
local HEADER_ICON_YOFFSET = 0    -- Y position

-- Export icon mapping for external use
ns.UI_GetTabIcon = function(tabName)
    return TAB_HEADER_ICONS[tabName] or "shop-icon-housing-characters-up"
end

-- Export size configuration
ns.UI_GetHeaderIconSize = function()
    return HEADER_ICON_SIZE, HEADER_BORDER_SIZE, HEADER_ICON_XOFFSET, HEADER_ICON_YOFFSET
end

--[[
    Create a standardized header icon with character-style ring border
    This creates the same icon+border style used in "Your Characters" and "Current Character"
    Border color adapts to theme accent color
    @param parent frame - Parent frame (typically a card/header)
    @param atlasName string - Atlas name for the inner icon (e.g., "charactercreate-gendericon-female-selected")
    @param size number - Icon size (default: from HEADER_ICON_SIZE)
    @param borderSize number - Border size (default: from HEADER_BORDER_SIZE)
    @param point string - Anchor point (default: "LEFT")
    @param x number - X offset (default: from HEADER_ICON_XOFFSET)
    @param y number - Y offset (default: from HEADER_ICON_YOFFSET)
    @return table - {icon=texture, border=texture} for further manipulation if needed
]]
local function CreateHeaderIcon(parent, atlasName, size, borderSize, point, x, y)
    size = size or HEADER_ICON_SIZE
    borderSize = borderSize or HEADER_BORDER_SIZE
    point = point or "LEFT"
    x = x or HEADER_ICON_XOFFSET
    y = y or HEADER_ICON_YOFFSET
    
    -- Create container frame for border
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(size + 4, size + 4)  -- Slightly larger for border
    container:SetPoint(point, x, y)
    
    -- Apply border with theme color
    ApplyVisuals(container, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    
    -- Apply hover effect
    ApplyHoverEffect(container, 0.25)
    
    -- Inner icon (inset by 2px for border)
    local icon = container:CreateTexture(nil, "ARTWORK", nil, 0)
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetAtlas(atlasName, false)
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    
    return {
        icon = icon,
        border = container  -- Return container as "border" for positioning compatibility
    }
end

-- Export header icon system
ns.UI_CreateHeaderIcon = CreateHeaderIcon

-- ============================================================================
-- CURRENT CHARACTER ICON (Global, easily customizable)
-- ============================================================================

--[[
    Get the atlas name for "Current Character" icon
    This is a global setting that applies to all "Current Character" displays
    Change this function to customize the icon globally
    @return string - Atlas name for the current character icon
]]
local function GetCurrentCharacterIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all "Current Character" icons
    -- Default: "charactercreate-gendericon-female-selected" (generic character icon)
    -- Alternatives: 
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    --   "Banker" (banker icon)
    return "charactercreate-gendericon-female-selected"
end

-- Export
ns.UI_GetCurrentCharacterIcon = GetCurrentCharacterIcon

-- ============================================================================
-- CHARACTER-SPECIFIC ICON (Used in headers across multiple tabs)
-- ============================================================================

--[[
    Get the atlas name for "Character-Specific" contexts
    This icon is used for headers and sections that represent character-specific data
    
    Used in:
    - Characters tab → "Characters" header
    - Storage tab → "Personal Banks" header
    - Reputations tab → "Character-Based Reputations" header
    
    @return string - Atlas name for character-specific icon
]]
local function GetCharacterSpecificIcon()
    -- CUSTOMIZE HERE: Change this atlas to change all character-specific headers
    -- Current: "honorsystem-icon-prestige-9" (honor prestige badge, character-specific indicator)
    -- Alternatives:
    --   "charactercreate-gendericon-female-selected" (generic character)
    --   "shop-icon-housing-characters-up" (house character)
    --   "charactercreate-icon-customize-body" (body customization)
    return "honorsystem-icon-prestige-9"
end

-- Export
ns.UI_GetCharacterSpecificIcon = GetCharacterSpecificIcon

--[[
    Get currency header icon texture path
    
    Returns appropriate icon for currency category headers (Legacy, expansions, etc.)
    Note: Blizzard API does not provide icons for headers, so we use manual mapping
    
    @param headerName string - Header name (e.g., "Legacy", "War Within", "Season 3")
    @return string|nil - Texture path or nil if no icon
]]
local function GetCurrencyHeaderIcon(headerName)
    -- Legacy (all old expansions)
    if headerName:find("Legacy") then
        return "Interface\\Icons\\INV_Misc_Coin_01"
    -- Current content
    elseif headerName:find("Season 3") or headerName:find("Season3") then
        return "Interface\\Icons\\Achievement_BG_winAB_underXminutes"
    -- Expansions
    elseif headerName:find("War Within") then
        return "Interface\\Icons\\INV_Misc_Gem_Diamond_01"
    elseif headerName:find("Dragonflight") then
        return "Interface\\Icons\\INV_Misc_Head_Dragon_Bronze"
    elseif headerName:find("Shadowlands") then
        return "Interface\\Icons\\INV_Misc_Bone_HumanSkull_01"
    elseif headerName:find("Battle for Azeroth") then
        return "Interface\\Icons\\INV_Sword_39"
    elseif headerName:find("Legion") then
        return "Interface\\Icons\\Spell_Shadow_Twilight"
    elseif headerName:find("Warlords of Draenor") or headerName:find("Draenor") then
        return "Interface\\Icons\\INV_Misc_Tournaments_banner_Orc"
    elseif headerName:find("Mists of Pandaria") or headerName:find("Pandaria") then
        return "Interface\\Icons\\Achievement_Character_Pandaren_Female"
    elseif headerName:find("Cataclysm") then
        return "Interface\\Icons\\Spell_Fire_Flameshock"
    elseif headerName:find("Wrath") or headerName:find("Lich King") then
        return "Interface\\Icons\\Spell_Shadow_SoulLeech_3"
    elseif headerName:find("Burning Crusade") or headerName:find("Outland") then
        return "Interface\\Icons\\Spell_Fire_FelFlameStrike"
    elseif headerName:find("PvP") or headerName:find("Player vs") then
        return "Interface\\Icons\\Achievement_BG_returnXflags_def_WSG"
    elseif headerName:find("Dungeon") or headerName:find("Raid") then
        return "Interface\\Icons\\achievement_boss_archaedas"
    elseif headerName:find("Miscellaneous") then
        return "Interface\\Icons\\INV_Misc_Gear_01"
    end
    return nil
end

-- Export
ns.UI_GetCurrencyHeaderIcon = GetCurrencyHeaderIcon

--[[
    Get class icon texture path (clean, frameless icons)
    @param classFile string - English class name (e.g., "WARRIOR", "MAGE")
    @return string - Texture path
]]
local function GetClassIcon(classFile)
    -- Use class crest icons (clean, no frame)
    local classIcons = {
        ["WARRIOR"] = "Interface\\Icons\\ClassIcon_Warrior",
        ["PALADIN"] = "Interface\\Icons\\ClassIcon_Paladin",
        ["HUNTER"] = "Interface\\Icons\\ClassIcon_Hunter",
        ["ROGUE"] = "Interface\\Icons\\ClassIcon_Rogue",
        ["PRIEST"] = "Interface\\Icons\\ClassIcon_Priest",
        ["DEATHKNIGHT"] = "Interface\\Icons\\ClassIcon_DeathKnight",
        ["SHAMAN"] = "Interface\\Icons\\ClassIcon_Shaman",
        ["MAGE"] = "Interface\\Icons\\ClassIcon_Mage",
        ["WARLOCK"] = "Interface\\Icons\\ClassIcon_Warlock",
        ["MONK"] = "Interface\\Icons\\ClassIcon_Monk",
        ["DRUID"] = "Interface\\Icons\\ClassIcon_Druid",
        ["DEMONHUNTER"] = "Interface\\Icons\\ClassIcon_DemonHunter",
        ["EVOKER"] = "Interface\\Icons\\ClassIcon_Evoker",
    }
    
    return classIcons[classFile] or "Interface\\Icons\\INV_Misc_QuestionMark"
end

--[[
    Create class icon on a frame
    @param parent frame - Parent frame
    @param classFile string - English class name (e.g., "WARRIOR")
    @param size number - Icon size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateClassIcon(parent, classFile, size, point, x, y)
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint(point, x, y)
    icon:SetTexture(GetClassIcon(classFile))
    -- Anti-flicker optimization
    icon:SetSnapToPixelGrid(false)
    icon:SetTexelSnappingBias(0)
    return icon
end

-- Exports
ns.UI_GetClassIcon = GetClassIcon
ns.UI_CreateClassIcon = CreateClassIcon

--============================================================================
-- FAVORITE ICON HELPERS
--============================================================================

-- Constants
local FAVORITE_ICON_TEXTURE = "Interface\\COMMON\\FavoritesIcon"
local FAVORITE_COLOR_ACTIVE = {1, 0.84, 0}  -- Gold
local FAVORITE_COLOR_INACTIVE = {0.5, 0.5, 0.5}  -- Gray

--[[
    Get favorite icon texture path (always same texture, color changes)
    @return string - Texture path
]]
local function GetFavoriteIconTexture()
    return FAVORITE_ICON_TEXTURE
end

--[[
    Apply favorite icon styling
    @param texture texture - Texture object to style
    @param isFavorite boolean - Whether character is favorited
]]
local function StyleFavoriteIcon(texture, isFavorite)
    texture:SetTexture(FAVORITE_ICON_TEXTURE)
    if isFavorite then
        texture:SetDesaturated(false)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_ACTIVE))
    else
        texture:SetDesaturated(true)
        texture:SetVertexColor(unpack(FAVORITE_COLOR_INACTIVE))
    end
end

--[[
    Create complete favorite button with click handler
    @param parent frame - Parent frame
    @param charKey string - Character key (name-realm)
    @param isFavorite boolean - Current favorite status
    @param size number - Button size
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @param onToggle function - Callback(charKey) returns new status
    @return button - Created button
]]
local function CreateFavoriteButton(parent, charKey, isFavorite, size, point, x, y, onToggle)
    -- Make favorite icon 15% larger and shift 2px down
    local iconSize = size * 1.15
    local yOffset = y - 2  -- Negative moves down in WoW
    
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)  -- Keep button hitbox same size
    btn:SetPoint(point, x, yOffset)
    
    local icon = btn:CreateTexture(nil, "ARTWORK")
    -- Center the larger icon within the button
    local sizeDiff = (iconSize - size) / 2
    icon:SetSize(iconSize, iconSize)
    icon:SetPoint("CENTER", 0, 0)
    StyleFavoriteIcon(icon, isFavorite)
    
    btn.icon = icon
    btn.charKey = charKey
    btn.isFavorite = isFavorite
    
    btn:SetScript("OnClick", function(self)
        local newStatus = onToggle(self.charKey)
        self.isFavorite = newStatus
        StyleFavoriteIcon(self.icon, newStatus)
    end)
    
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.isFavorite then
            GameTooltip:SetText("|cffffd700Favorite Character|r\nClick to remove from favorites")
        else
            GameTooltip:SetText("Click to add to favorites\n|cff888888Favorites are always shown at the top|r")
        end
        GameTooltip:Show()
    end)
    
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    
    -- Add SetChecked method (mimic CheckButton) for compatibility
    function btn:SetChecked(checked)
        self.isFavorite = checked
        StyleFavoriteIcon(self.icon, checked)
    end
    
    return btn
end

-- Exports
ns.UI_GetFavoriteIconTexture = GetFavoriteIconTexture
ns.UI_StyleFavoriteIcon = StyleFavoriteIcon
ns.UI_CreateFavoriteButton = CreateFavoriteButton

--============================================================================
-- ONLINE INDICATOR HELPERS
--============================================================================

-- Constants
local ONLINE_ICON_TEXTURE = "Interface\\FriendsFrame\\StatusIcon-Online"
local ONLINE_ICON_SIZE = 16

--[[
    Get online indicator texture path
    @return string - Texture path
]]
local function GetOnlineIconTexture()
    return ONLINE_ICON_TEXTURE
end

--[[
    Create online indicator (simple texture, no interaction)
    @param parent frame - Parent frame
    @param size number - Icon size (optional, defaults to 16)
    @param point string - Anchor point
    @param x number - X offset
    @param y number - Y offset
    @return texture - Created texture
]]
local function CreateOnlineIndicator(parent, size, point, x, y)
    local indicator = parent:CreateTexture(nil, "ARTWORK")
    indicator:SetSize(size or ONLINE_ICON_SIZE, size or ONLINE_ICON_SIZE)
    indicator:SetPoint(point, x, y)
    indicator:SetTexture(ONLINE_ICON_TEXTURE)
    return indicator
end

-- Exports
ns.UI_GetOnlineIconTexture = GetOnlineIconTexture
ns.UI_CreateOnlineIndicator = CreateOnlineIndicator
ns.UI_ONLINE_ICON_SIZE = ONLINE_ICON_SIZE

--============================================================================
-- CHARACTER ROW COLUMN CONFIGURATION
--============================================================================

-- Define column structure (single source of truth)
local CHAR_ROW_COLUMNS = {
    favorite = {
        width = 29,    -- Icon size increased 20% (24 → 29)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 34,    -- 29 + 5
    },
    faction = {
        width = 29,    -- Icon size increased 20% (24 → 29)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 34,    -- 29 + 5
    },
    race = {
        width = 29,    -- Icon size increased 20% (24 → 29)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 34,    -- 29 + 5
    },
    class = {
        width = 29,    -- Icon size increased 20% (24 → 29)
        spacing = 5,   -- Icon columns: tight 5px spacing
        total = 34,    -- 29 + 5
    },
    name = {
        width = 100,   -- Character name only (realm shown below)
        spacing = 15,  -- Standardized to 15px
        total = 115,   -- 100 + 15
    },
    level = {
        width = 40,    -- Optimized: "80" centered
        spacing = 15,  -- Standardized to 15px
        total = 55,    -- 40 + 15
    },
    itemLevel = {
        width = 75,    -- "iLvl 639" centered
        spacing = 15,  -- Standardized to 15px
        total = 90,    -- 75 + 15
    },
    gold = {
        width = 175,   -- "9,999,999g 99s 99c" with icons
        spacing = 15,  -- Standardized to 15px
        total = 190,   -- 175 + 15
    },
    professions = {
        width = 204,   -- INCREASED 20%: 10px padding + 5 icons × 34px (170) + 4 gaps × 5px (20) = 200px minimum
        spacing = 15,  -- Standardized to 15px
        total = 219,   -- 204 + 15
    },
    mythicKey = {
        width = 120,   -- Increased from 100 to 120 for more room (text was truncating)
        spacing = 15,  -- Standardized to 15px
        total = 135,   -- 120 + 15
    },
    reorder = {
        width = 60,    -- Move Up/Down buttons (2x 24px buttons + spacing)
        spacing = 15,  -- Standardized to 15px
        total = 75,    -- 60 + 15
    },
    spacer = {
        width = 150,   -- Flexible space between professions and last seen
        spacing = 0,   -- No spacing (intentional)
        total = 150,
    },
    lastSeen = {
        width = 100,
        spacing = 15,  -- Standardized to 15px
        total = 115,   -- 100 + 15
    },
    delete = {
        width = 30,
        spacing = 15,  -- Standardized to 15px
        total = 45,    -- 30 + 15
    },
}

--[[
    Calculate column offset from left
    @param columnKey string - Column key (e.g., "name", "level")
    @return number - X offset from left
]]
local function GetColumnOffset(columnKey)
    local offset = 10  -- Base left padding
    local order = {"favorite", "faction", "race", "class", "name", "level", "itemLevel", "gold", "professions", "mythicKey", "spacer", "reorder", "lastSeen", "delete"}
    
    for _, key in ipairs(order) do
        if key == columnKey then
            return offset
        end
        offset = offset + CHAR_ROW_COLUMNS[key].total
    end
    
    return offset
end

--[[
    Calculate total width needed for all character row columns
    @return number - Total width (base padding + all columns + right padding)
]]
local function GetCharRowTotalWidth()
    local width = 10  -- Base left padding
    local order = {"favorite", "faction", "race", "class", "name", "level", "itemLevel", "gold", "professions", "mythicKey", "spacer", "reorder", "lastSeen", "delete"}
    
    for _, key in ipairs(order) do
        width = width + CHAR_ROW_COLUMNS[key].total
    end
    
    width = width + 10  -- Right padding
    return width
end

--[[
    Create column divider at specified offset
    @param parent frame - Parent frame
    @param xOffset number - X position for divider
    @return texture - Created divider texture
]]
local function CreateCharRowColumnDivider(parent, xOffset)
    local divider = parent:CreateTexture(nil, "BACKGROUND", nil, 1)
    divider:SetColorTexture(0.3, 0.3, 0.35, 0.4)
    divider:SetSize(1, 38)
    divider:SetPoint("LEFT", xOffset, 0)
    return divider
end

-- Exports
ns.UI_CHAR_ROW_COLUMNS = CHAR_ROW_COLUMNS
ns.UI_GetColumnOffset = GetColumnOffset
ns.UI_GetCharRowTotalWidth = GetCharRowTotalWidth
ns.UI_CreateCharRowColumnDivider = CreateCharRowColumnDivider

--============================================================================
-- SORTABLE TABLE HEADER (Reusable for any table with sorting)
--============================================================================

--[[
    Creates a sortable table header with clickable columns
    
    @param parent - Parent frame
    @param columns - Array of column definitions:
        {
            {key="name", label="CHARACTER", align="LEFT", offset=12},
            {key="level", label="LEVEL", align="LEFT", offset=200},
            {key="gold", label="GOLD", align="RIGHT", offset=-120},
            {key="lastSeen", label="LAST SEEN", align="RIGHT", offset=-20}
        }
    @param width - Total header width
    @param onSortChanged - Callback: function(sortKey, isAscending)
    @param defaultSortKey - Initial sort column (optional)
    @param defaultAscending - Initial sort direction (optional, default true)
    
    @return header frame, getCurrentSort function
]]
local function CreateSortableTableHeader(parent, columns, width, onSortChanged, defaultSortKey, defaultAscending)
    -- State
    local currentSortKey = defaultSortKey or (columns[1] and columns[1].key)
    local isAscending = (defaultAscending ~= false) -- Default true

    -- Create header frame with backdrop (like collapsible headers)
    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(width, 28)
    
    -- Backdrop removed (naked frame)
    
    -- Column buttons
    local columnButtons = {}
    
    for i, col in ipairs(columns) do
        -- Create clickable button (no backdrop = no box!)
        local btn = CreateFrame("Button", nil, header)
        btn:SetSize(col.width or 100, 28)
        
        if col.align == "LEFT" then
            btn:SetPoint("LEFT", col.offset or 0, 0)
        elseif col.align == "RIGHT" then
            btn:SetPoint("RIGHT", col.offset or 0, 0)
        else
            btn:SetPoint("CENTER", col.offset or 0, 0)
        end
        
        -- Label text (position based on alignment)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")  -- Normal size font
        if col.align == "LEFT" then
            btn.label:SetPoint("LEFT", 5, 0)  -- Small padding
            btn.label:SetJustifyH("LEFT")
        elseif col.align == "RIGHT" then
            btn.label:SetPoint("RIGHT", -17, 0) -- Space for arrow on right
            btn.label:SetJustifyH("RIGHT")
        else
            btn.label:SetPoint("CENTER", -6, 0)
            btn.label:SetJustifyH("CENTER")
        end
        btn.label:SetText(col.label)
        btn.label:SetTextColor(1, 1, 1)  -- White text for all labels
        
        -- Sort arrow (^ ascending, v descending, - sortable)
        btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal") -- Bigger font!
        if col.align == "RIGHT" then
            btn.arrow:SetPoint("RIGHT", 0, 0)
        else
            btn.arrow:SetPoint("LEFT", btn.label, "RIGHT", 4, 0)
        end
        btn.arrow:SetText("◆") -- Default: sortable indicator
        btn.arrow:SetTextColor(1, 1, 1, 0.3) -- White with low alpha for inactive
        
        -- Update arrow visibility
        local function UpdateArrow()
            if currentSortKey == col.key then
                btn.arrow:SetText(isAscending and "▲" or "▼")
                btn.arrow:SetTextColor(0.6, 0.4, 0.8, 1) -- Brighter purple for active
                btn.label:SetTextColor(1, 1, 1) -- White for active column
            else
                btn.arrow:SetText("◆") -- Sortable hint (diamond)
                btn.arrow:SetTextColor(1, 1, 1, 0.3) -- White with low alpha for inactive
                btn.label:SetTextColor(1, 1, 1) -- White
            end
        end
        
        UpdateArrow()
        
        -- Hover effect
        btn:SetScript("OnEnter", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(1, 1, 1)
            end
        end)
        
        btn:SetScript("OnLeave", function(self)
            if currentSortKey ~= col.key then
                self.label:SetTextColor(1, 1, 1)  -- White
            end
        end)
        
        -- Click handler
        btn:SetScript("OnClick", function()
            if currentSortKey == col.key then
                -- Same column - toggle direction
                isAscending = not isAscending
            else
                -- New column - default to ascending
                currentSortKey = col.key
                isAscending = true
            end
            
            -- Update all arrows
            for _, otherBtn in pairs(columnButtons) do
                if otherBtn.updateArrow then
                    otherBtn.updateArrow()
                end
            end
            
            -- Notify parent
            if onSortChanged then
                onSortChanged(currentSortKey, isAscending)
            end
        end)
        
        btn.updateArrow = UpdateArrow
        columnButtons[i] = btn
    end
    
    -- Function to get current sort state
    local function GetCurrentSort()
        return currentSortKey, isAscending
    end
    
    return header, GetCurrentSort
end

--============================================================================
-- DRAW EMPTY STATE (Shared by Items and Storage tabs)
--============================================================================

local function DrawEmptyState(addon, parent, startY, isSearch, searchText)
    -- Validate parent frame
    if not parent or not parent.CreateTexture then
        return startY or 0
    end
    
    local yOffset = startY + 50
    
    local icon = parent:CreateTexture(nil, "ARTWORK")
    icon:SetSize(48, 48)
    icon:SetPoint("TOP", 0, -yOffset)
    icon:SetTexture(isSearch and "Interface\\Icons\\INV_Misc_Spyglass_02" or "Interface\\Icons\\INV_Misc_Bag_10_Blue")
    icon:SetDesaturated(true)
    icon:SetAlpha(0.4)
    yOffset = yOffset + 60
    
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -yOffset)
    title:SetText(isSearch and "|cff666666No results|r" or "|cff666666No items cached|r")
    yOffset = yOffset + 30
    
    local desc = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    desc:SetPoint("TOP", 0, -yOffset)
    desc:SetTextColor(1, 1, 1)  -- White
    local displayText = searchText or ""
    desc:SetText(isSearch and ("No items match '" .. displayText .. "'") or "Open your Warband Bank to scan items")
    
    return yOffset + 50
end

--============================================================================
-- SEARCH BOX (Reusable component for Items and Storage tabs)
--============================================================================

--[[
    Creates a search box with icon, placeholder, and throttled callback
    
    @param parent - Parent frame
    @param width - Search box width
    @param placeholder - Placeholder text (e.g., "Search items...")
    @param onTextChanged - Callback function(searchText) - called after throttle
    @param throttleDelay - Delay in seconds before callback (default 0.3)
    @param initialValue - Initial text value (optional, for restoring state)
    
    @return searchContainer frame, clearFunction
]]
local function CreateSearchBox(parent, width, placeholder, onTextChanged, throttleDelay, initialValue)
    local delay = throttleDelay or 0.3
    local throttleTimer = nil
    local initialText = initialValue or ""
    
    -- Container frame
    local container = CreateFrame("Frame", nil, parent)
    container:SetSize(width, 32)
    
    -- Background frame with pixel-perfect border
    local searchFrame = CreateFrame("Frame", nil, container)
    container.searchFrame = searchFrame  -- Store reference for color updates
    searchFrame:SetAllPoints()
    
    -- Apply pixel-perfect visuals with accent border
    local accentColor = COLORS.accent
    ApplyVisuals(searchFrame, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    
    -- Search icon
    local searchIcon = searchFrame:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(16, 16)
    searchIcon:SetPoint("LEFT", 10, 0)
    searchIcon:SetTexture("Interface\\Icons\\INV_Misc_Spyglass_03")
    searchIcon:SetAlpha(0.5)
    -- Anti-flicker optimization
    searchIcon:SetSnapToPixelGrid(false)
    searchIcon:SetTexelSnappingBias(0)
    
    -- EditBox
    local searchBox = CreateFrame("EditBox", nil, searchFrame)
    searchBox:SetPoint("LEFT", searchIcon, "RIGHT", 8, 0)
    searchBox:SetPoint("RIGHT", -10, 0)
    searchBox:SetHeight(20)
    searchBox:SetFontObject("GameFontNormal")
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    
    -- Set initial value if provided
    if initialText and initialText ~= "" then
        searchBox:SetText(initialText)
    end
    
    -- Placeholder text
    local placeholderText = searchBox:CreateFontString(nil, "ARTWORK", "GameFontDisable")
    placeholderText:SetPoint("LEFT", 0, 0)
    placeholderText:SetText(placeholder or "Search...")
    placeholderText:SetTextColor(1, 1, 1, 0.4)  -- White with transparency
    
    -- Show/hide placeholder based on initial text
    if initialText and initialText ~= "" then
        placeholderText:Hide()
    else
        placeholderText:Show()
    end
    
    -- OnTextChanged handler with throttle
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        
        local text = self:GetText()
        local newSearchText = ""
        
        if text and text ~= "" then
            placeholderText:Hide()
            newSearchText = text:lower()
        else
            placeholderText:Show()
            newSearchText = ""
        end
        
        -- Cancel previous throttle
        if throttleTimer then
            throttleTimer:Cancel()
        end
        
        -- Throttle callback - refresh after delay (live search)
        throttleTimer = C_Timer.NewTimer(delay, function()
            if onTextChanged then
                onTextChanged(newSearchText)
            end
            throttleTimer = nil
        end)
    end)
    
    -- Escape to clear
    searchBox:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    
    -- Enter to defocus
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    
    -- Focus handlers removed (no backdrop)
    
    -- Clear function
    local function ClearSearch()
        searchBox:SetText("")
        placeholderText:Show()
    end
    
    return container, ClearSearch
end

--============================================================================
-- SEARCH TEXT GETTERS
--============================================================================

local function GetCurrencySearchText()
    return (ns.currencySearchText or ""):lower()
end

--============================================================================
-- CURRENCY TRANSFER POPUP
--============================================================================

--[[
    Create a currency transfer popup dialog
    @param currencyData table - Currency information
    @param currentCharacterKey string - Current character key
    @param onConfirm function - Callback(targetCharKey, amount)
    @return frame - Popup frame
]]
local function CreateCurrencyTransferPopup(currencyData, currentCharacterKey, onConfirm)
    -- Create backdrop overlay
    local overlay = CreateFrame("Frame", nil, UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")  -- Highest strata
    overlay:SetFrameLevel(1000)
    overlay:SetAllPoints()
    overlay:EnableMouse(true)
    overlay:SetScript("OnMouseDown", function(self)
        self:Hide()
    end)
    
    -- Create popup frame
    local popup = CreateFrame("Frame", nil, overlay)
    popup:SetSize(400, 380)  -- Increased height for instructions
    popup:SetPoint("CENTER")
    popup:SetFrameStrata("FULLSCREEN_DIALOG")
    popup:SetFrameLevel(overlay:GetFrameLevel() + 10)
    popup:EnableMouse(true)
    
    -- Title
    local title = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -15)
    title:SetText("|cff6a0dadTransfer Currency|r")
    
    -- Get WarbandNexus and current character info
    local WarbandNexus = ns.WarbandNexus
    local currentPlayerName = UnitName("player")
    local currentRealm = GetRealmName()
    
    -- From Character (current/online)
    local fromText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fromText:SetPoint("TOP", 0, -38)
    fromText:SetText(string.format("|cff888888From:|r |cff00ff00%s|r |cff888888(Online)|r", currentPlayerName))
    
    -- Currency Icon
    local icon = popup:CreateTexture(nil, "ARTWORK")
    icon:SetSize(32, 32)
    icon:SetPoint("TOP", 0, -65)
    if currencyData.iconFileID then
        icon:SetTexture(currencyData.iconFileID)
    end
    
    -- Currency Name
    local nameText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    nameText:SetPoint("TOP", 0, -105)
    nameText:SetText(currencyData.name or "Unknown Currency")
    nameText:SetTextColor(1, 0.82, 0)
    
    -- Available Amount
    local availableText = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    availableText:SetPoint("TOP", 0, -125)
    availableText:SetText(string.format("|cff888888Available:|r |cffffffff%d|r", currencyData.quantity or 0))
    
    -- Amount Input Label
    local amountLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    amountLabel:SetPoint("TOPLEFT", 30, -155)
    amountLabel:SetText("Amount:")
    
    -- Amount Input Box
    local amountBox = CreateFrame("EditBox", nil, popup)
    amountBox:SetSize(100, 28)
    amountBox:SetPoint("LEFT", amountLabel, "RIGHT", 10, 0)
    amountBox:SetFontObject("GameFontNormal")
    amountBox:SetTextInsets(8, 8, 0, 0)
    amountBox:SetAutoFocus(false)
    amountBox:SetNumeric(true)
    amountBox:SetMaxLetters(10)
    amountBox:SetText("1")
    
    -- Max Button
    local maxBtn = CreateThemedButton(popup, "Max", 70)
    maxBtn:SetPoint("LEFT", amountBox, "RIGHT", 5, 0)
    maxBtn:SetScript("OnClick", function()
        amountBox:SetText(tostring(currencyData.quantity or 0))
    end)
    
    -- Confirm Button (create early so it can be referenced)
    local confirmBtn = CreateThemedButton(popup, "Open & Guide", 120)
    confirmBtn:SetPoint("BOTTOMRIGHT", -20, 15)
    confirmBtn:Disable() -- Initially disabled until character selected
    
    -- Cancel Button
    local cancelBtn = CreateThemedButton(popup, "Cancel", 90)
    cancelBtn:SetPoint("RIGHT", confirmBtn, "LEFT", -5, 0)
    cancelBtn:SetScript("OnClick", function()
        overlay:Hide()
    end)
    
    -- Info note at bottom
    local infoNote = popup:CreateFontString(nil, "OVERLAY", "GameFontNormalTiny")
    infoNote:SetPoint("BOTTOM", 0, 50)
    infoNote:SetWidth(360)
    infoNote:SetText("|cff00ff00✓|r Currency window will be opened automatically.\n|cff888888You'll need to manually right-click the currency to transfer.|r")
    infoNote:SetJustifyH("CENTER")
    infoNote:SetWordWrap(true)
    
    -- Target Character Label
    local targetLabel = popup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    targetLabel:SetPoint("TOPLEFT", 30, -195)
    targetLabel:SetText("To Character:")
    
    -- Get WarbandNexus addon reference
    local WarbandNexus = ns.WarbandNexus
    
    -- Build character list (exclude current character)
    local characterList = {}
    if WarbandNexus and WarbandNexus.db and WarbandNexus.db.global.characters then
        for charKey, charData in pairs(WarbandNexus.db.global.characters) do
            -- Filter: Skip untracked characters
            if charKey ~= currentCharacterKey and charData.name and charData.isTracked ~= false then
                table.insert(characterList, {
                    key = charKey,
                    name = charData.name,
                    realm = charData.realm or "",
                    class = charData.class or "UNKNOWN",
                    level = charData.level or 0,
                })
            end
        end
        
        -- Sort by name
        table.sort(characterList, function(a, b) return a.name < b.name end)
    end
    
    -- Selected character
    local selectedTargetKey = nil
    local selectedCharData = nil
    
    -- Character selection dropdown container
    local charDropdown = CreateFrame("Frame", nil, popup)
    charDropdown:SetSize(320, 28)
    charDropdown:SetPoint("TOPLEFT", 30, -215)
    charDropdown:EnableMouse(true)
    
    local charText = charDropdown:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    charText:SetPoint("LEFT", 10, 0)
    charText:SetText("|cff888888Select character...|r")
    charText:SetJustifyH("LEFT")
    
    -- Dropdown arrow icon
    local arrowIcon = charDropdown:CreateTexture(nil, "ARTWORK")
    arrowIcon:SetSize(16, 16)
    arrowIcon:SetPoint("RIGHT", -5, 0)
    arrowIcon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    
    -- Character list frame (dropdown menu)
    local charListFrame = CreateFrame("Frame", nil, popup)
    charListFrame:SetSize(320, math.min(#characterList * 28 + 4, 200))  -- Max 200px height
    charListFrame:SetPoint("TOPLEFT", charDropdown, "BOTTOMLEFT", 0, -2)
    charListFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    charListFrame:SetFrameLevel(popup:GetFrameLevel() + 20)
    charListFrame:Hide()  -- Initially hidden
    
    -- Scroll frame for character list (if many characters)
    local scrollFrame = CreateFrame("ScrollFrame", nil, charListFrame)
    scrollFrame:SetPoint("TOPLEFT", 2, -2)
    scrollFrame:SetPoint("BOTTOMRIGHT", -2, 2)
    
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:SetSize(316, #characterList * 28)
    
    -- Create character buttons
    for i, charData in ipairs(characterList) do
        local charBtn = CreateFrame("Button", nil, scrollChild)
        charBtn:SetSize(316, 26)
        charBtn:SetPoint("TOPLEFT", 0, -(i-1) * 28)
        
        -- Class color
        local classColor = RAID_CLASS_COLORS[charData.class] or {r=1, g=1, b=1}
        
        local btnText = charBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btnText:SetPoint("LEFT", 8, 0)
        btnText:SetText(string.format("|c%s%s|r |cff888888(%d - %s)|r", 
            string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
            charData.name,
            charData.level,
            charData.realm
        ))
        btnText:SetJustifyH("LEFT")
        
        -- Hover effects removed (no backdrop)
        charBtn:SetScript("OnClick", function(self)
            selectedTargetKey = charData.key
            selectedCharData = charData
            charText:SetText(string.format("|c%s%s|r", 
                string.format("%02x%02x%02x%02x", 255, classColor.r*255, classColor.g*255, classColor.b*255),
                charData.name
            ))
            charListFrame:Hide()
            confirmBtn:Enable()  -- Enable confirm button
        end)
    end
    
    -- Toggle dropdown
    charDropdown:SetScript("OnMouseDown", function(self)
        if charListFrame:IsShown() then
            charListFrame:Hide()
        else
            charListFrame:Show()
        end
    end)
    
    -- Set confirm button click handler (now that we have all variables)
    confirmBtn:SetScript("OnClick", function()
        local amount = tonumber(amountBox:GetText()) or 0
        if amount > 0 and amount <= (currencyData.quantity or 0) and selectedTargetKey and selectedCharData then
            -- STEP 1: Open Currency Frame (SAFE - No Taint)
            -- TWW (11.x) uses different frame name
            if not CharacterFrame or not CharacterFrame:IsShown() then
                ToggleCharacter("PaperDollFrame")
            end
            
            -- Switch to currency tab
            C_Timer.After(0.1, function()
                if CharacterFrame and CharacterFrame:IsShown() then
                    -- Click the Token (Currency) tab
                    if CharacterFrameTab4 then
                        CharacterFrameTab4:Click()
                    end
                end
            end)
            
            -- STEP 2: Try to expand currency categories (SAFE)
            C_Timer.After(0.3, function()
                -- Expand all currency categories so user can see target currency
                for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
                    local info = C_CurrencyInfo.GetCurrencyListInfo(i)
                    if info and info.isHeader and not info.isHeaderExpanded then
                        C_CurrencyInfo.ExpandCurrencyList(i, true)
                    end
                end
            end)
            
            -- STEP 3: Show instructions in chat
            local WarbandNexus = ns.WarbandNexus
            if WarbandNexus then
                WarbandNexus:Print("|cff00ff00=== Currency Transfer Instructions ===|r")
                WarbandNexus:Print(string.format("|cffffaa00Currency:|r %s", currencyData.name))
                WarbandNexus:Print(string.format("|cffffaa00Amount:|r %d", amount))
                WarbandNexus:Print(string.format("|cffffaa00From:|r %s |cff888888(current character)|r", currentPlayerName))
                WarbandNexus:Print(string.format("|cffffaa00To:|r |cff00ff00%s|r", selectedCharData.name))
                WarbandNexus:Print(" ")
                WarbandNexus:Print("|cff00aaffNext steps:|r")
                WarbandNexus:Print("|cff00ff001.|r Find |cffffffff" .. currencyData.name .. "|r in the Currency window")
                WarbandNexus:Print("|cff00ff002.|r |cffff8800Right-click|r on it")
                WarbandNexus:Print("|cff00ff003.|r Select |cffffffff'Transfer to Warband'|r")
                WarbandNexus:Print("|cff00ff004.|r Choose |cff00ff00" .. selectedCharData.name .. "|r")
                WarbandNexus:Print("|cff00ff005.|r Enter amount: |cffffffff" .. amount .. "|r")
                WarbandNexus:Print(" ")
                WarbandNexus:Print("|cff00ff00✓|r Currency window is now open!")
                WarbandNexus:Print("|cff888888(Blizzard security prevents automatic transfer)|r")
            end
            
            overlay:Hide()
        end
    end)
    
    -- Store reference for cleanup
    overlay.popup = popup
    
    -- Show overlay
    overlay:Show()
    
    return overlay
end

--============================================================================
-- SHARED UI CONSTANTS
--============================================================================

local UI_CONSTANTS = {
    BUTTON_HEIGHT = 28,
    BORDER_SIZE = 1,
    BUTTON_BORDER_COLOR = function() return COLORS.accent end,
    BUTTON_BG_COLOR = {0.1, 0.1, 0.1, 1},
}

ns.UI_CONSTANTS = UI_CONSTANTS

--============================================================================
-- SHARED BUTTON WIDGET
--============================================================================

--[[
    Create a themed button with consistent styling
    @param parent - Parent frame
    @param text - Button text
    @param width - Button width
    @return button - Created button
]]
local function CreateThemedButton(parent, text, width)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 100, UI_CONSTANTS.BUTTON_HEIGHT)
    
    -- Apply border with theme color
    ApplyVisuals(btn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    
    -- Apply strong hover effect
    ApplyHoverEffect(btn, 0.25)
    
    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btnText:SetPoint("CENTER")
    btnText:SetText(text)
    btn.text = btnText
    
    return btn
end

--============================================================================
-- SHARED CHECKBOX WIDGET
--============================================================================

--[[
    Create a themed checkbox with consistent styling
    @param parent - Parent frame
    @param initialState - Initial checked state (boolean)
    @return checkbox - Created checkbox
]]
local function CreateThemedCheckbox(parent, initialState)
    if not parent then
        print("WarbandNexus DEBUG: CreateThemedCheckbox called with nil parent!")
        return nil
    end
    
    local checkbox = CreateFrame("CheckButton", nil, parent)
    checkbox:SetSize(UI_CONSTANTS.BUTTON_HEIGHT, UI_CONSTANTS.BUTTON_HEIGHT)
    
    -- Apply border
    ApplyVisuals(checkbox, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    
    -- Apply hover effect
    ApplyHoverEffect(checkbox, 0.25)
    
    -- Green tick texture
    local checkTexture = checkbox:CreateTexture(nil, "OVERLAY")
    checkTexture:SetSize(20, 20)
    checkTexture:SetPoint("CENTER")
    checkTexture:SetTexture("Interface\\BUTTONS\\UI-CheckBox-Check")
    checkTexture:SetVertexColor(0, 1, 0, 1) -- Green color
    checkbox.checkTexture = checkTexture
    
    if initialState then
        checkTexture:Show()
        checkbox:SetChecked(true)
    else
        checkTexture:Hide()
        checkbox:SetChecked(false)
    end
    
    checkbox:SetScript("OnClick", function(self)
        if self:GetChecked() then
            self.checkTexture:Show()
        else
            self.checkTexture:Hide()
        end
    end)
    
    return checkbox
end

--============================================================================
-- TABLE ROW FACTORY
--============================================================================

--[[
    Create a generic table row with configurable columns
    @param parent - Parent frame
    @param width - Row width
    @param height - Row height (default 32)
    @param columns - Array of column definitions: { {width=100, align="LEFT"}, ... }
    @return row - Created row frame with column anchors
]]
local function CreateTableRow(parent, width, height, columns)
    if not parent then return nil end
    
    height = height or 32
    
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(width, height)
    row:EnableMouse(true)
    
    -- Store column anchors for content placement
    row.columns = {}
    
    if columns then
        local xOffset = 0
        for i, col in ipairs(columns) do
            row.columns[i] = {
                x = xOffset,
                width = col.width,
                align = col.align or "LEFT"
            }
            xOffset = xOffset + col.width
        end
    end
    
    return row
end

--============================================================================
-- EXPANDABLE ROW FACTORY
--============================================================================

--[[
    Create an expandable row for achievements/collections
    @param parent - Parent frame
    @param width - Row width
    @param rowHeight - Collapsed row height (default 32)
    @param data - Row data { icon, score, title, information, criteria }
    @param isExpanded - Initial expanded state
    @param onToggle - Callback function(isExpanded)
    @return row - Created expandable row frame
]]
local function CreateExpandableRow(parent, width, rowHeight, data, isExpanded, onToggle)
    if not parent then return nil end
    
    rowHeight = rowHeight or 34
    local COLORS = GetColors()
    
    -- Main container (will grow/shrink but header stays at top)
    local row = CreateFrame("Frame", nil, parent)
    row:SetWidth(width)
    row:SetHeight(rowHeight) -- Initial height
    
    -- Store state
    row.isExpanded = isExpanded or false
    row.data = data
    row.rowHeight = rowHeight
    row.onToggle = onToggle
    
    -- Alternating row color (set by caller based on index)
    row.bgColor = {0.08, 0.08, 0.10, 1}
    
    -- Header frame (FIXED HEIGHT, always visible at top)
    local headerFrame = CreateFrame("Frame", nil, row)
    headerFrame:SetPoint("TOPLEFT", 0, 0)
    headerFrame:SetPoint("TOPRIGHT", 0, 0)
    headerFrame:SetHeight(rowHeight)
    row.headerFrame = headerFrame
    
    -- Apply background and gradient border to header
    if ApplyVisuals then
        -- Gradient border: brighter at top, darker at bottom
        local borderColor = {
            COLORS.accent[1] * 0.8,
            COLORS.accent[2] * 0.8,
            COLORS.accent[3] * 0.8,
            0.4
        }
        ApplyVisuals(headerFrame, row.bgColor, borderColor)
    else
        -- Fallback: simple border
        if headerFrame.SetBackdrop then
            headerFrame:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                tileSize = 1,
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 }
            })
            headerFrame:SetBackdropColor(row.bgColor[1], row.bgColor[2], row.bgColor[3], row.bgColor[4])
            headerFrame:SetBackdropBorderColor(0.3, 0.3, 0.35, 0.5)
        end
    end
    
    -- Hover effect for header
    if ApplyHoverEffect then
        ApplyHoverEffect(headerFrame, 0.15)
    end
    
    -- Toggle function (header stays fixed, only details expand below)
    local function ToggleExpand()
        row.isExpanded = not row.isExpanded
        
        if row.isExpanded then
            row.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
            row.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-MinusButton-Up")
            
            -- Create details frame if not exists (positioned BELOW header)
            if not row.detailsFrame then
                local detailsFrame = CreateFrame("Frame", nil, row)
                detailsFrame:SetPoint("TOPLEFT", row.headerFrame, "BOTTOMLEFT", 0, -1) -- -1 for seamless connection
                detailsFrame:SetPoint("TOPRIGHT", row.headerFrame, "BOTTOMRIGHT", 0, -1)
                
                -- Background and border for expanded section (darker gradient border)
                local detailsBgColor = {row.bgColor[1] * 0.7, row.bgColor[2] * 0.7, row.bgColor[3] * 0.7, 1}
                local detailsBorderColor = {
                    COLORS.accent[1] * 0.4,
                    COLORS.accent[2] * 0.4,
                    COLORS.accent[3] * 0.4,
                    0.6
                }
                
                if ApplyVisuals then
                    ApplyVisuals(detailsFrame, detailsBgColor, detailsBorderColor)
                else
                    -- Fallback
                    if detailsFrame.SetBackdrop then
                        detailsFrame:SetBackdrop({
                            bgFile = "Interface\\Buttons\\WHITE8X8",
                            edgeFile = "Interface\\Buttons\\WHITE8X8",
                            tile = false,
                            edgeSize = 1,
                            insets = { left = 0, right = 0, top = 0, bottom = 0 }
                        })
                        detailsFrame:SetBackdropColor(detailsBgColor[1], detailsBgColor[2], detailsBgColor[3], detailsBgColor[4])
                        detailsFrame:SetBackdropBorderColor(detailsBorderColor[1], detailsBorderColor[2], detailsBorderColor[3], detailsBorderColor[4])
                    end
                end
                
                -- Divider line between header and details
                local divider = detailsFrame:CreateTexture(nil, "OVERLAY")
                divider:SetTexture("Interface\\Buttons\\WHITE8X8")
                divider:SetHeight(1)
                divider:SetPoint("TOPLEFT", 0, 0)
                divider:SetPoint("TOPRIGHT", 0, 0)
                divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
                
                local yOffset = -8
                local leftMargin = 48
                local rightMargin = 16
                local sectionSpacing = 6
                
                -- Information Section (no divider)
                if data.information and data.information ~= "" then
                    -- Section header
                    local infoHeader = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    infoHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
                    infoHeader:SetText("|cff88cc88Description:|r")
                    
                    yOffset = yOffset - 18
                    
                    -- Section content (bigger font)
                    local infoText = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    infoText:SetPoint("TOPLEFT", leftMargin + 4, yOffset)
                    infoText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
                    infoText:SetJustifyH("LEFT")
                    infoText:SetText("|cffdddddd" .. data.information .. "|r")
                    infoText:SetWordWrap(true)
                    infoText:SetSpacing(2)
                    
                    local textHeight = infoText:GetStringHeight()
                    yOffset = yOffset - textHeight - sectionSpacing - 4
                end
                
                -- Criteria Section (single line, compact)
                if data.criteria and data.criteria ~= "" then
                    -- Section header (bigger font)
                    local criteriaHeader = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    criteriaHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
                    criteriaHeader:SetText("|cffffcc00Requirements:|r")
                    
                    yOffset = yOffset - 18
                    
                    -- Single line criteria text (no wrapping, all in one line)
                    local criteriaText = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                    criteriaText:SetPoint("TOPLEFT", leftMargin + 4, yOffset)
                    criteriaText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
                    criteriaText:SetJustifyH("LEFT")
                    criteriaText:SetText("|cffeeeeee" .. data.criteria .. "|r")
                    criteriaText:SetWordWrap(true)
                    criteriaText:SetSpacing(2)
                    
                    local textHeight = criteriaText:GetStringHeight()
                    yOffset = yOffset - textHeight - sectionSpacing
                end
                
                -- Set height based on content (WoW-like: tight)
                local detailsHeight = math.abs(yOffset) + 8
                detailsFrame:SetHeight(detailsHeight)
                
                row.detailsFrame = detailsFrame
            end
            
            -- Show details and resize row
            row.detailsFrame:Show()
            local totalHeight = rowHeight + row.detailsFrame:GetHeight()
            row:SetHeight(totalHeight)
        else
            row.expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
            row.expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Up")
            
            -- Hide details and collapse row
            if row.detailsFrame then
                row.detailsFrame:Hide()
            end
            row:SetHeight(rowHeight)
        end
        
        -- Callback
        if row.onToggle then
            row.onToggle(row.isExpanded)
        end
    end
    
    -- Expand/Collapse button (inside header)
    local expandBtn = CreateFrame("Button", nil, headerFrame)
    expandBtn:SetSize(20, 20)
    expandBtn:SetPoint("LEFT", 6, 0)
    expandBtn:SetNormalTexture("Interface\\Buttons\\UI-PlusButton-Up")
    expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Up")
    expandBtn:GetHighlightTexture():SetAlpha(0.3)
    expandBtn:SetScript("OnClick", function()
        ToggleExpand()
    end)
    row.expandBtn = expandBtn
    
    -- Make entire header clickable for expand/collapse
    headerFrame:EnableMouse(true)
    headerFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            ToggleExpand()
        end
    end)
    
    -- Item Icon (after expand button) - WoW-like smaller
    if data.icon then
        local iconFrame = CreateIcon(headerFrame, data.icon, 28, false, nil, true)
        iconFrame:SetPoint("LEFT", 32, 0)
        row.iconFrame = iconFrame
    end
    
    -- Score (for achievements) or Type badge - WoW-like compact
    if data.score then
        local scoreText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        scoreText:SetPoint("LEFT", 68, 0)
        scoreText:SetWidth(60)
        scoreText:SetJustifyH("LEFT")
        scoreText:SetText("|cffffd700" .. data.score .. " pts|r")
        row.scoreText = scoreText
    end
    
    -- Title - WoW-like normal font
    local titleText = headerFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    titleText:SetPoint("LEFT", data.score and 134 or 68, 0)
    titleText:SetPoint("RIGHT", -90, 0)
    titleText:SetJustifyH("LEFT")
    titleText:SetText("|cffffffff" .. (data.title or "Unknown") .. "|r")
    titleText:SetWordWrap(false)
    row.titleText = titleText
    
    -- Expanded details container (created on demand)
    row.detailsFrame = nil
    
    -- Initialize expanded state (without triggering callbacks)
    if isExpanded then
        row.isExpanded = true
        expandBtn:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-Up")
        expandBtn:SetHighlightTexture("Interface\\Buttons\\UI-MinusButton-Up")
        
        -- Manually create and show details without calling ToggleExpand
        -- (to avoid triggering onToggle callback during initialization)
        -- CRITICAL: Details anchored BELOW header, not at row top
        local detailsFrame = CreateFrame("Frame", nil, row)
        detailsFrame:SetPoint("TOPLEFT", headerFrame, "BOTTOMLEFT", 0, -1)
        detailsFrame:SetPoint("TOPRIGHT", headerFrame, "BOTTOMRIGHT", 0, -1)
        
        -- Background and border for expanded section
        local detailsBgColor = {row.bgColor[1] * 0.7, row.bgColor[2] * 0.7, row.bgColor[3] * 0.7, 1}
        local detailsBorderColor = {
            COLORS.accent[1] * 0.4,
            COLORS.accent[2] * 0.4,
            COLORS.accent[3] * 0.4,
            0.6
        }
        
        if ApplyVisuals then
            ApplyVisuals(detailsFrame, detailsBgColor, detailsBorderColor)
        else
            if detailsFrame.SetBackdrop then
                detailsFrame:SetBackdrop({
                    bgFile = "Interface\\Buttons\\WHITE8X8",
                    edgeFile = "Interface\\Buttons\\WHITE8X8",
                    tile = false,
                    edgeSize = 1,
                    insets = { left = 0, right = 0, top = 0, bottom = 0 }
                })
                detailsFrame:SetBackdropColor(detailsBgColor[1], detailsBgColor[2], detailsBgColor[3], detailsBgColor[4])
                detailsFrame:SetBackdropBorderColor(detailsBorderColor[1], detailsBorderColor[2], detailsBorderColor[3], detailsBorderColor[4])
            end
        end
        
        -- Divider line between header and details
        local divider = detailsFrame:CreateTexture(nil, "OVERLAY")
        divider:SetTexture("Interface\\Buttons\\WHITE8X8")
        divider:SetHeight(1)
        divider:SetPoint("TOPLEFT", 0, 0)
        divider:SetPoint("TOPRIGHT", 0, 0)
        divider:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.3)
        
        local yOffset = -8
        local leftMargin = 48
        local rightMargin = 16
        local sectionSpacing = 6
        
        -- Information Section (no divider)
        if data.information and data.information ~= "" then
            local infoHeader = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            infoHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
            infoHeader:SetText("|cff88cc88Description:|r")
            
            yOffset = yOffset - 18
            
            local infoText = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            infoText:SetPoint("TOPLEFT", leftMargin + 4, yOffset)
            infoText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
            infoText:SetJustifyH("LEFT")
            infoText:SetText("|cffdddddd" .. data.information .. "|r")
            infoText:SetWordWrap(true)
            infoText:SetSpacing(2)
            
            local textHeight = infoText:GetStringHeight()
            yOffset = yOffset - textHeight - sectionSpacing - 4
        end
        
        -- Criteria Section (2-column layout)
        if data.criteria and data.criteria ~= "" then
            local criteriaHeader = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            criteriaHeader:SetPoint("TOPLEFT", leftMargin, yOffset)
            criteriaHeader:SetText("|cffffcc00Requirements:|r")
            
            yOffset = yOffset - 18
            
            -- Single line criteria text
            local criteriaText = detailsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            criteriaText:SetPoint("TOPLEFT", leftMargin + 4, yOffset)
            criteriaText:SetPoint("TOPRIGHT", -rightMargin, yOffset)
            criteriaText:SetJustifyH("LEFT")
            criteriaText:SetText("|cffeeeeee" .. data.criteria .. "|r")
            criteriaText:SetWordWrap(true)
            criteriaText:SetSpacing(2)
            
            local textHeight = criteriaText:GetStringHeight()
            yOffset = yOffset - textHeight - sectionSpacing
        end
        
        local detailsHeight = math.abs(yOffset) + 8
        detailsFrame:SetHeight(detailsHeight)
        
        row.detailsFrame = detailsFrame
        detailsFrame:Show()
        
        local totalHeight = rowHeight + detailsFrame:GetHeight()
        row:SetHeight(totalHeight)
    end
    
    return row
end

--============================================================================
-- CATEGORY SECTION FACTORY
--============================================================================

--[[
    Create a category section with header and item rows
    @param parent - Parent frame
    @param width - Section width
    @param categoryName - Category display name
    @param categoryKey - Unique key for expand state
    @param items - Array of items to display
    @param isExpanded - Initial expanded state
    @param onToggle - Callback function(isExpanded)
    @param createRowFunc - Function to create item rows: function(parent, item, index)
    @return section - Created section frame with header and rows
]]
local function CreateCategorySection(parent, width, categoryName, categoryKey, items, isExpanded, onToggle, createRowFunc)
    if not parent or not categoryName then return nil end
    
    local section = CreateFrame("Frame", nil, parent)
    section:SetWidth(width)
    
    -- Store state
    section.categoryKey = categoryKey
    section.items = items or {}
    section.isExpanded = isExpanded
    section.createRowFunc = createRowFunc
    
    -- Create collapsible header
    local header = CreateCollapsibleHeader(
        section,
        string.format("%s (%d)", categoryName, #section.items),
        categoryKey,
        isExpanded,
        onToggle,
        nil -- icon (optional)
    )
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetWidth(width)
    section.header = header
    
    -- Rows container
    local rowsContainer = CreateFrame("Frame", nil, section)
    rowsContainer:SetPoint("TOPLEFT", 0, -UI_LAYOUT.HEADER_HEIGHT)
    rowsContainer:SetWidth(width)
    section.rowsContainer = rowsContainer
    
    -- Calculate total height
    local totalHeight = UI_LAYOUT.HEADER_HEIGHT
    if isExpanded and #section.items > 0 then
        -- Rows will be added by caller
        totalHeight = totalHeight + (#section.items * (UI_LAYOUT.rowHeight or 32))
    end
    section:SetHeight(totalHeight)
    
    return section
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_GetQualityHex = GetQualityHex
ns.UI_GetAccentHexColor = GetAccentHexColor
ns.UI_CreateCard = CreateCard
ns.UI_FormatGold = FormatGold
ns.UI_FormatMoney = FormatMoney
ns.UI_FormatMoneyCompact = FormatMoneyCompact
ns.UI_CreateCollapsibleHeader = CreateCollapsibleHeader
ns.UI_GetItemTypeName = GetItemTypeName
ns.UI_GetItemClassID = GetItemClassID
ns.UI_GetTypeIcon = GetTypeIcon
ns.UI_CreateSortableTableHeader = CreateSortableTableHeader
ns.UI_DrawEmptyState = DrawEmptyState
ns.UI_CreateSearchBox = CreateSearchBox
ns.UI_GetCurrencySearchText = GetCurrencySearchText
ns.UI_RefreshColors = RefreshColors
ns.UI_CalculateThemeColors = CalculateThemeColors

-- Frame pooling exports
ns.UI_AcquireItemRow = AcquireItemRow
ns.UI_ReleaseItemRow = ReleaseItemRow
ns.UI_AcquireStorageRow = AcquireStorageRow
ns.UI_ReleaseStorageRow = ReleaseStorageRow
ns.UI_AcquireCurrencyRow = AcquireCurrencyRow
ns.UI_ReleaseCurrencyRow = ReleaseCurrencyRow
ns.UI_AcquireCharacterRow = AcquireCharacterRow
ns.UI_ReleaseCharacterRow = ReleaseCharacterRow
ns.UI_AcquireReputationRow = AcquireReputationRow
ns.UI_ReleaseReputationRow = ReleaseReputationRow
ns.UI_ReleaseAllPooledChildren = ReleaseAllPooledChildren

-- Shared widget exports
ns.UI_CreateThemedButton = CreateThemedButton
ns.UI_CreateThemedCheckbox = CreateThemedCheckbox

-- Table factory exports
ns.UI_CreateTableRow = CreateTableRow
ns.UI_CreateExpandableRow = CreateExpandableRow
ns.UI_CreateCategorySection = CreateCategorySection

-- Currency transfer popup export
ns.UI_CreateCurrencyTransferPopup = CreateCurrencyTransferPopup

-- ============================================================================
-- CREATE EXTERNAL WINDOW (Unified Dialog System)
-- ============================================================================
--[[
    Creates a standardized external window/dialog with:
    - Duplicate prevention
    - Click outside to close
    - Draggable header
    - Modern styling with borders
    - Close button
    
    Parameters:
    - config = {
        name = "UniqueDialogName" (required),
        title = "Dialog Title" (required),
        icon = "Interface\\Icons\\..." (required),
        width = 500 (default 400),
        height = 400 (default 300),
        onClose = function() end (optional),
        preventDuplicates = true (default true)
    }
    
    Returns:
    - dialog: Main dialog frame
    - contentFrame: Frame where you add your content
    - header: Header frame (for custom additions)
]]
local function CreateExternalWindow(config)
    -- Validate config
    if not config or not config.name or not config.title or not config.icon then
        error("CreateExternalWindow: name, title, and icon are required")
        return nil
    end
    
    local globalName = "WarbandNexus_" .. config.name
    local width = config.width or 400
    local height = config.height or 300
    local preventDuplicates = (config.preventDuplicates ~= false) -- default true
    
    -- Prevent duplicates
    if preventDuplicates then
        if _G[globalName] and _G[globalName]:IsShown() then
            return nil -- Already open
        end
    end
    
    local COLORS = ns.UI_COLORS
    
    -- Create dialog frame
    local dialog = CreateFrame("Frame", globalName, UIParent)
    dialog:SetSize(width, height)
    dialog:SetPoint("CENTER")
    dialog:SetFrameStrata("FULLSCREEN_DIALOG")
    dialog:SetFrameLevel(100)
    
    -- Apply border and background
    if ApplyVisuals then
        ApplyVisuals(dialog, {0.05, 0.05, 0.07, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8})
    end
    
    dialog:EnableMouse(true)
    dialog:SetMovable(true)
    
    -- Header bar
    local header = CreateFrame("Frame", nil, dialog)
    header:SetHeight(45)
    header:SetPoint("TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", -8, -8)
    
    -- Apply header border
    if ApplyVisuals then
        ApplyVisuals(header, {0.08, 0.08, 0.10, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.4})
    end
    
    -- Make header draggable
    header:EnableMouse(true)
    header:SetMovable(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function()
        dialog:StartMoving()
    end)
    header:SetScript("OnDragStop", function()
        dialog:StopMovingOrSizing()
    end)
    
    -- Icon
    local iconFrame = CreateIcon(header, config.icon, 28, false, nil, true)
    iconFrame:SetPoint("LEFT", 12, 0)
    
    -- Title
    local titleText = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleText:SetPoint("LEFT", iconFrame, "RIGHT", 10, 0)
    titleText:SetText("|cffffffff" .. config.title .. "|r")
    
    -- Close button (X) - Modern styled
    local closeBtn = CreateFrame("Button", nil, header)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    
    -- Apply border and background to close button
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 1}, {0.5, 0.1, 0.1, 1})
    end
    if ApplyHoverEffect then
        ApplyHoverEffect(closeBtn, 0.25)
    end
    
    local closeBtnText = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    closeBtnText:SetPoint("CENTER", 0, 0)
    closeBtnText:SetText("|cffffffff×|r")
    
    -- Close function
    local function CloseDialog()
        if config.onClose then
            config.onClose()
        end
        dialog:Hide()
        dialog:SetParent(nil)
        _G[globalName] = nil
    end
    
    closeBtn:SetScript("OnClick", CloseDialog)
    
    -- Content frame (where users add their content)
    local contentFrame = CreateFrame("Frame", nil, dialog)
    contentFrame:SetPoint("TOPLEFT", 8, -53) -- Below header
    contentFrame:SetPoint("BOTTOMRIGHT", -8, 8)
    
    -- Click outside to close (using OnUpdate to detect clicks)
    local clickOutsideFrame = CreateFrame("Frame", nil, UIParent)
    clickOutsideFrame:SetAllPoints()
    clickOutsideFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    clickOutsideFrame:SetFrameLevel(99) -- Just below dialog
    clickOutsideFrame:EnableMouse(true)
    clickOutsideFrame:SetScript("OnMouseDown", function()
        CloseDialog()
    end)
    
    -- Hide click outside frame when dialog is hidden
    dialog:SetScript("OnHide", function()
        clickOutsideFrame:Hide()
        if config.onClose then
            config.onClose()
        end
    end)
    
    dialog:SetScript("OnShow", function()
        clickOutsideFrame:Show()
    end)
    
    -- Close on Escape
    dialog:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            CloseDialog()
        end
    end)
    dialog:SetPropagateKeyboardInput(true)
    
    -- Store close function
    dialog.Close = CloseDialog
    
    return dialog, contentFrame, header
end

ns.UI_CreateExternalWindow = CreateExternalWindow
