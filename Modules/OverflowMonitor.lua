--[[
    Warband Nexus - Overflow Detection Service
    Simple real-time checking of actual UI elements
]]

local ADDON_NAME, ns = ...

local OverflowMonitor = {}
ns.OverflowMonitor = OverflowMonitor

--============================================================================
-- SIMPLE OVERFLOW CHECK
--============================================================================

--[[
    Check if a FontString's text is overflowing its container
    @param fontString FontString - The text element to check
    @return boolean - True if text is overflowing
]]
local function IsTextOverflowing(fontString)
    if not fontString then return false end

    local contentWidth = fontString:GetStringWidth()
    local containerWidth = fontString:GetWidth()
    
    if containerWidth <= 1 and fontString:GetParent() then
        containerWidth = fontString:GetParent():GetWidth() - 10
    end
    
    local canWrap = fontString:CanWordWrap()
    
    -- AGGRESSIVE DETECTION: If text is using >90% of container width, flag it
    local usagePercent = (contentWidth / containerWidth) * 100
    local isNearLimit = usagePercent >= 90
    
    return not canWrap and isNearLimit
end

ns.OverflowMonitor.IsTextOverflowing = IsTextOverflowing

--[[
    Check visible character rows for overflow
    @return boolean - True if any overflow detected
]]
function OverflowMonitor:CheckCharacterRows()
    -- TAINT FIX: Use cached reference instead of _G
    local mainFrame = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
    if not mainFrame then return false end
    
    local scrollChild = mainFrame.scrollChild
    if not scrollChild then return false end
    
    local children = {scrollChild:GetChildren()}
    
    local checkedCount = 0
    for i, child in ipairs(children) do
        if child:IsShown() and child.nameText then
            checkedCount = checkedCount + 1
            
            if IsTextOverflowing(child.nameText) then
                return true
            end
            
            if checkedCount >= 3 then break end
        end
    end
    
    return false
end

--[[
    Check visible plan cards for overflow
    @return boolean - True if any overflow detected
]]
function OverflowMonitor:CheckPlanCards()
    -- TAINT FIX: Use cached reference instead of _G
    local mainFrame = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
    if not mainFrame then return false end
    
    local scrollChild = mainFrame.scrollChild
    if not scrollChild then return false end
    
    local children = {scrollChild:GetChildren()}
    
    local checkedCount = 0
    for i, child in ipairs(children) do
        if child:IsShown() and child.planNameText then
            checkedCount = checkedCount + 1
            if IsTextOverflowing(child.planNameText) then
                return true
            end
            
            if checkedCount >= 5 then break end
        end
    end
    
    return false
end

--[[
    Check any visible UI for overflow
    @return boolean - True if any overflow detected
]]
function OverflowMonitor:CheckAll()
    return self:CheckCharacterRows() or self:CheckPlanCards()
end

