--[[
    Warband Nexus - API Utility Module
    Money formatting and screen/window sizing utilities.
    Simple WoW API calls (C_Container, C_Item, etc.) should be called directly.
]]

local ADDON_NAME, ns = ...

local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- MONEY/GOLD UTILITIES
-- ============================================================================

--[[
    Format money as colored string with icons
    @param amount number - Money in copper
    @return string - Formatted string (e.g., "12g 34s 56c")
]]
function WarbandNexus:API_FormatMoney(amount)
    amount = tonumber(amount) or 0
    if amount < 0 then amount = 0 end
    
    if GetCoinTextureString then
        local success, result = pcall(GetCoinTextureString, amount)
        if success and result then
            return result
        end
    end
    
    if GetMoneyString then
        local success, result = pcall(GetMoneyString, amount)
        if success and result then
            return result
        end
    end
    
    local gold = math.floor(amount / 10000)
    local silver = math.floor((amount % 10000) / 100)
    local copper = math.floor(amount % 100)
    
    local str = ""
    if gold > 0 then
        str = str .. gold .. "g "
    end
    if silver > 0 or gold > 0 then
        str = str .. silver .. "s "
    end
    str = str .. copper .. "c"
    
    return str
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function WarbandNexus:InitializeAPIWrapper()
    -- No-op: kept for backwards compatibility with InitializationService
end

-- ============================================================================
-- SCREEN & UI SCALE UTILITIES
-- ============================================================================

--[[
    Get screen dimensions and UI scale.
    Uses GetPhysicalScreenSize for resolution-based category classification
    (immune to UI scale settings) and UIParent dimensions for layout sizing.
    @return table {width, height, scale, physWidth, physHeight, category}
]]
function WarbandNexus:API_GetScreenInfo()
    local uiWidth = UIParent:GetWidth() or 1920
    local uiHeight = UIParent:GetHeight() or 1080
    local scale = UIParent:GetEffectiveScale() or 1.0

    -- Physical screen dimensions for reliable classification
    local physW, physH = 1920, 1080
    if GetPhysicalScreenSize then
        local pw, ph = GetPhysicalScreenSize()
        if pw and pw > 0 then physW = pw end
        if ph and ph > 0 then physH = ph end
    end

    local aspectRatio = physW / math.max(physH, 1)
    local category = "normal"
    if physW < 1600 then
        category = "small"
    elseif aspectRatio >= 2.2 then
        category = "ultrawide"
    elseif physW >= 3840 then
        category = "xlarge"
    elseif physW >= 2560 then
        category = "large"
    end

    return {
        width = uiWidth,
        height = uiHeight,
        scale = scale,
        physWidth = physW,
        physHeight = physH,
        category = category,
    }
end

--[[
    Calculate optimal window dimensions based on screen size
    @param contentMinWidth number - Minimum width required for content
    @param contentMinHeight number - Minimum height required for content
    @return number, number, number, number - Optimal width, height, max width, max height
]]
function WarbandNexus:API_CalculateOptimalWindowSize(contentMinWidth, contentMinHeight)
    local screen = self:API_GetScreenInfo()

    -- Use physical dimensions for aspect ratio detection (immune to UI scale)
    local aspectRatio = screen.physWidth / math.max(screen.physHeight, 1)
    local widthPct = 0.65
    if aspectRatio >= 3.0 then
        widthPct = 0.35      -- 32:9 super ultra-wide
    elseif aspectRatio >= 2.2 then
        widthPct = 0.45      -- 21:9 ultra-wide
    elseif aspectRatio >= 1.9 then
        widthPct = 0.55      -- Wider-than-16:10 monitors
    end

    -- Use UIParent dimensions for layout (same coordinate space as frame sizing)
    local defaultWidth = math.floor(screen.width * widthPct)
    local defaultHeight = math.floor(screen.height * 0.70)

    local maxWidth = math.floor(screen.width * 0.90)
    local maxHeight = math.floor(screen.height * 0.90)

    local optimalWidth = math.max(contentMinWidth, math.min(defaultWidth, maxWidth))
    local optimalHeight = math.max(contentMinHeight, math.min(defaultHeight, maxHeight))

    return optimalWidth, optimalHeight, maxWidth, maxHeight
end
