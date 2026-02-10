--[[
    Warband Nexus - Reputation Progress Bar Component
    
    Specialized progress bar for faction reputation display.
    
    Features:
    - Handles Paragon, Renown, and Classic reputation systems
    - Dynamic colors based on standing (Hated → Exalted)
    - Maxed reputation indicator (green fill)
    - Pixel-perfect borders with accent color
    - Progress calculation with edge case handling
    
    Extracted from SharedWidgets.lua (153 lines)
    Location: Lines 914-1079
]]

local ADDON_NAME, ns = ...


-- Debug print helper
local function DebugPrint(...)
    local addon = _G.WarbandNexus
    if addon and addon.db and addon.db.profile and addon.db.profile.debugMode then
        _G.print(...)
    end
end
-- Import dependencies from namespace
local COLORS = ns.UI_COLORS
local GetPixelScale = ns.GetPixelScale

--============================================================================
-- RUNTIME DEPENDENCY VALIDATION
--============================================================================

local function ValidateDependencies()
    local missing = {}
    
    if not COLORS then table.insert(missing, "UI_COLORS") end
    
    if #missing > 0 then
        DebugPrint("|cffff0000[WN RepProgressBar ERROR]|r Missing dependencies: " .. table.concat(missing, ", "))
        DebugPrint("|cffff0000[WN RepProgressBar ERROR]|r Ensure SharedWidgets.lua loads before ReputationProgressBar.lua in .toc")
        return false
    end
    
    return true
end

-- Defer validation to first use (allows SharedWidgets to complete loading)

--============================================================================
-- REPUTATION PROGRESS BAR
--============================================================================

---Create a reputation progress bar with dynamic fill and colors
---Handles Paragon, Renown, and Classic reputation systems
---@param parent Frame Parent frame (usually a row)
---@param width number|nil Bar width (default 200)
---@param height number|nil Bar height (default 14)
---@param currentValue number Current reputation value
---@param maxValue number Max reputation value
---@param isParagon boolean If true, use paragon styling (pink)
---@param isMaxed boolean If true, fill bar 100% and use green color
---@param standingID number|nil Standing ID for color (1-8)
---@return Frame|nil bgFrame Background frame
---@return Texture|nil fillTexture Fill texture
local function CreateReputationProgressBar(parent, width, height, currentValue, maxValue, isParagon, isMaxed, standingID)
    -- Runtime dependency check (deferred to first use)
    if not COLORS then
        DebugPrint("|cffff0000[WN RepProgressBar ERROR]|r Missing dependencies - SharedWidgets not loaded")
        return nil, nil
    end
    
    if not parent then return nil, nil end
    
    width = width or 200
    height = height or 14
    currentValue = currentValue or 0
    maxValue = maxValue or 1
    
    -- Background frame - set high frame level to ensure border and text are on top
    local bgFrame = CreateFrame("Frame", nil, parent)
    bgFrame:SetSize(width, height)
    bgFrame:SetFrameLevel(parent:GetFrameLevel() + 10)  -- High frame level for proper layering
    
    -- Border is 1px, so inset content by 1px on all sides for symmetry
    local borderInset = GetPixelScale and GetPixelScale() or 1
    local contentWidth = width - (borderInset * 2)
    local contentHeight = height - (borderInset * 2)
    
    -- Background texture (dark) - inset by 1px to sit inside border
    local bgTexture = bgFrame:CreateTexture(nil, "BACKGROUND")
    bgTexture:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", borderInset, -borderInset)
    bgTexture:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", -borderInset, borderInset)
    -- Use COLORS.bgCard or COLORS.bg with alpha
    local bgColor = COLORS.bgCard or {COLORS.bg[1], COLORS.bg[2], COLORS.bg[3], 0.8}
    bgTexture:SetColorTexture(bgColor[1], bgColor[2], bgColor[3], bgColor[4] or 0.8)
    bgTexture:SetSnapToPixelGrid(false)
    bgTexture:SetTexelSnappingBias(0)
    
    -- Calculate progress (handle maxValue = 0 case)
    local progress = 0
    if maxValue > 0 then
        progress = currentValue / maxValue
        progress = math.min(1, math.max(0, progress))
    elseif maxValue == 0 and currentValue == 0 then
        -- Empty reputation with 0/0 - show as 0% progress
        progress = 0
    end
    
    -- If maxed and not paragon, fill 100%
    if isMaxed and not isParagon then
        progress = 1
    end
    
    -- Only create fill if there's progress
    -- Fill bar should be 1px inset from border (borderInset + 1 = 2px from frame edge)
    local fillInset = borderInset + 1  -- 2px total inset (1px border + 1px gap)
    local fillWidth = contentWidth - 2  -- Subtract 2px (1px on each side) for gap
    local fillHeight = contentHeight - 2  -- Subtract 2px (1px on each side) for gap
    
    local fillTexture = nil
    -- Always create fill if there's any value or if maxed (even if currentValue is 0, show empty bar)
    if (currentValue > 0 or isMaxed or maxValue > 0) then
        fillTexture = bgFrame:CreateTexture(nil, "ARTWORK")
        fillTexture:SetPoint("LEFT", bgFrame, "LEFT", fillInset, 0)
        fillTexture:SetPoint("TOP", bgFrame, "TOP", 0, -fillInset)
        fillTexture:SetPoint("BOTTOM", bgFrame, "BOTTOM", 0, fillInset)
        fillTexture:SetWidth(fillWidth * progress)
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
            local goldColor = COLORS.gold or {1, 0.82, 0, 1}
            fillTexture:SetColorTexture(goldColor[1], goldColor[2], goldColor[3], goldColor[4] or 1)
        end
    end
    
    -- Add border in BORDER layer (behind fill bar) for proper hierarchy
    -- Layer order: BACKGROUND < BORDER < ARTWORK < OVERLAY
    -- Border should be behind fill bar, so use BORDER layer
    local accentColor = COLORS.accent or {0.4, 0.6, 1}
    
    -- Create borders in BORDER layer (behind ARTWORK fill bar)
    local borderColor = {accentColor[1], accentColor[2], accentColor[3], 0.6}
    local r, g, b, a = borderColor[1], borderColor[2], borderColor[3], borderColor[4] or 1
    
    -- Top border (BORDER layer - behind fill bar)
    if not bgFrame.BorderTop then
        bgFrame.BorderTop = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderTop:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderTop:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", 0, 0)
        bgFrame.BorderTop:SetPoint("TOPRIGHT", bgFrame, "TOPRIGHT", 0, 0)
        bgFrame.BorderTop:SetHeight(1)
        bgFrame.BorderTop:SetSnapToPixelGrid(false)
        bgFrame.BorderTop:SetTexelSnappingBias(0)
        bgFrame.BorderTop:SetDrawLayer("BORDER", 0)
        bgFrame.BorderTop:SetVertexColor(r, g, b, a)
    end
    
    -- Bottom border
    if not bgFrame.BorderBottom then
        bgFrame.BorderBottom = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderBottom:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderBottom:SetPoint("BOTTOMLEFT", bgFrame, "BOTTOMLEFT", 0, 0)
        bgFrame.BorderBottom:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", 0, 0)
        bgFrame.BorderBottom:SetHeight(1)
        bgFrame.BorderBottom:SetSnapToPixelGrid(false)
        bgFrame.BorderBottom:SetTexelSnappingBias(0)
        bgFrame.BorderBottom:SetDrawLayer("BORDER", 0)
        bgFrame.BorderBottom:SetVertexColor(r, g, b, a)
    end
    
    -- Left border
    if not bgFrame.BorderLeft then
        bgFrame.BorderLeft = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderLeft:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderLeft:SetPoint("TOPLEFT", bgFrame, "TOPLEFT", 0, -1)
        bgFrame.BorderLeft:SetPoint("BOTTOMLEFT", bgFrame, "BOTTOMLEFT", 0, 1)
        bgFrame.BorderLeft:SetWidth(1)
        bgFrame.BorderLeft:SetSnapToPixelGrid(false)
        bgFrame.BorderLeft:SetTexelSnappingBias(0)
        bgFrame.BorderLeft:SetDrawLayer("BORDER", 0)
        bgFrame.BorderLeft:SetVertexColor(r, g, b, a)
    end
    
    -- Right border
    if not bgFrame.BorderRight then
        bgFrame.BorderRight = bgFrame:CreateTexture(nil, "BORDER")
        bgFrame.BorderRight:SetTexture("Interface\\Buttons\\WHITE8x8")
        bgFrame.BorderRight:SetPoint("TOPRIGHT", bgFrame, "TOPRIGHT", 0, -1)
        bgFrame.BorderRight:SetPoint("BOTTOMRIGHT", bgFrame, "BOTTOMRIGHT", 0, 1)
        bgFrame.BorderRight:SetWidth(1)
        bgFrame.BorderRight:SetSnapToPixelGrid(false)
        bgFrame.BorderRight:SetTexelSnappingBias(0)
        bgFrame.BorderRight:SetDrawLayer("BORDER", 0)
        bgFrame.BorderRight:SetVertexColor(r, g, b, a)
    end
    
    return bgFrame, fillTexture
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

ns.UI_CreateReputationProgressBar = CreateReputationProgressBar

-- Module loaded - verbose logging removed
