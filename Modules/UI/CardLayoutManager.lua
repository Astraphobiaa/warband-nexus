--[[
    Warband Nexus - Card Layout Manager
    Dynamic card positioning system for grid layouts with expand/collapse support
    
    Extracted from SharedWidgets.lua for better modularity
    Handles card positioning in Plans UI with automatic height adjustment
]]

local ADDON_NAME, ns = ...

--============================================================================
-- DYNAMIC CARD LAYOUT MANAGER
--============================================================================

--[[
    Dynamic Card Layout Manager
    Handles card positioning in a grid layout, automatically adjusting when cards expand/collapse
]]
local CardLayoutManager = {}
CardLayoutManager.instances = {}  -- Track layout instances per parent

--[[
    Create a new card layout manager for a parent container
    @param parent Frame - Parent container
    @param columns number - Number of columns (default 2)
    @param cardSpacing number - Spacing between cards (default 8)
    @param startYOffset number - Starting Y offset (default 0)
    @return table - Layout manager instance
]]
function CardLayoutManager:Create(parent, columns, cardSpacing, startYOffset)
    columns = columns or 2
    cardSpacing = cardSpacing or 8
    startYOffset = startYOffset or 0
    
    local instance = {
        parent = parent,
        columns = columns,
        cardSpacing = cardSpacing,
        cards = {},  -- Array of {card, col, rowIndex}
        currentYOffsets = {},  -- Track Y offset for each column
        startYOffset = startYOffset,
    }
    
    -- Initialize column offsets
    for col = 0, columns - 1 do
        instance.currentYOffsets[col] = startYOffset
    end
    
    -- Store instance
    local instanceKey = tostring(parent)
    self.instances[instanceKey] = instance
    
    print("|cff9d5cff[WN CardLayoutManager]|r Layout instance created: " .. 
          columns .. " columns, " .. cardSpacing .. "px spacing")
    
    return instance
end

--[[
    Add a card to the layout
    @param instance table - Layout instance
    @param card Frame - Card frame
    @param col number - Column index (0-based)
    @param baseHeight number - Base height of card (before expansion)
    @return number - Y offset where card was placed
]]
function CardLayoutManager:AddCard(instance, card, col, baseHeight)
    col = col or 0
    baseHeight = baseHeight or 130
    
    -- Get current Y offset for this column
    local yOffset = instance.currentYOffsets[col] or instance.startYOffset
    
    -- Calculate X offset
    local cardWidth = (instance.parent:GetWidth() - (instance.columns - 1) * instance.cardSpacing - 20) / instance.columns
    local xOffset = 10 + col * (cardWidth + instance.cardSpacing)
    
    -- Position card
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", xOffset, -yOffset)
    
    -- Store card info
    local cardInfo = {
        card = card,
        col = col,
        baseHeight = baseHeight,
        currentHeight = baseHeight,
        yOffset = yOffset,
        rowIndex = #instance.cards,
    }
    table.insert(instance.cards, cardInfo)
    
    -- Update column Y offset
    instance.currentYOffsets[col] = yOffset + baseHeight + instance.cardSpacing
    
    -- Store layout reference on card
    card._layoutManager = instance
    card._layoutInfo = cardInfo
    
    return yOffset
end

--[[
    Update layout when a card's height changes
    @param card Frame - Card that changed height
    @param newHeight number - New height of the card
]]
function CardLayoutManager:UpdateCardHeight(card, newHeight)
    local instance = card._layoutManager
    local cardInfo = card._layoutInfo
    
    if not instance or not cardInfo then
        return
    end
    
    -- Update stored height
    cardInfo.currentHeight = newHeight
    
    -- Recalculate all positions to handle cross-column scenarios
    self:RecalculateAllPositions(instance)
end

--[[
    Get final Y offset (for return value)
    @param instance table - Layout instance
    @return number - Maximum Y offset across all columns
]]
function CardLayoutManager:GetFinalYOffset(instance)
    local maxY = instance.startYOffset
    for col = 0, instance.columns - 1 do
        local colY = instance.currentYOffsets[col] or instance.startYOffset
        if colY > maxY then
            maxY = colY
        end
    end
    return maxY
end

--[[
    Recalculate all card positions from scratch
    Handles expanded cards, window resize, and cross-column scenarios
    @param instance table - Layout instance
]]
function CardLayoutManager:RecalculateAllPositions(instance)
    if not instance or not instance.parent then
        return
    end
    
    -- Recalculate card width based on current parent width
    local cardWidth = (instance.parent:GetWidth() - (instance.columns - 1) * instance.cardSpacing - 20) / instance.columns
    
    -- Reset column Y offsets
    for col = 0, instance.columns - 1 do
        instance.currentYOffsets[col] = instance.startYOffset
    end
    
    -- Sort cards by their original row index to maintain order
    local sortedCards = {}
    for i, cardInfo in ipairs(instance.cards) do
        table.insert(sortedCards, cardInfo)
    end
    table.sort(sortedCards, function(a, b)
        return a.rowIndex < b.rowIndex
    end)
    
    -- Reposition all cards, maintaining column assignment but recalculating Y positions
    for i, cardInfo in ipairs(sortedCards) do
        local col = cardInfo.col
        local currentHeight = cardInfo.currentHeight or cardInfo.baseHeight
        
        -- Get current Y offset for this column
        local yOffset = instance.currentYOffsets[col] or instance.startYOffset
        
        -- Handle full-width cards (weekly vault, daily quest header, etc.)
        if cardInfo.isFullWidth then
            -- Full width card: span both columns
            cardInfo.card:ClearAllPoints()
            cardInfo.card:SetPoint("TOPLEFT", instance.parent, "TOPLEFT", 10, -yOffset)
            cardInfo.card:SetPoint("TOPRIGHT", instance.parent, "TOPRIGHT", -10, -yOffset)
            -- Update both columns to same Y offset
            instance.currentYOffsets[0] = yOffset + currentHeight + instance.cardSpacing
            instance.currentYOffsets[1] = yOffset + currentHeight + instance.cardSpacing
        else
            -- Regular card: single column
            local xOffset = 10 + col * (cardWidth + instance.cardSpacing)
            
            -- Update card position
            cardInfo.card:ClearAllPoints()
            cardInfo.card:SetPoint("TOPLEFT", xOffset, -yOffset)
            cardInfo.card:SetWidth(cardWidth)
            
            -- Update column Y offset for next card
            instance.currentYOffsets[col] = yOffset + currentHeight + instance.cardSpacing
        end
        
        -- Update stored Y offset
        cardInfo.yOffset = yOffset
    end
end

--[[
    Refresh layout when parent frame is resized
    Recalculates both X and Y positions for all cards
    @param instance table - Layout instance
]]
function CardLayoutManager:RefreshLayout(instance)
    if not instance or not instance.parent then
        return
    end
    
    -- Use RecalculateAllPositions to handle both X and Y repositioning
    self:RecalculateAllPositions(instance)
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Export to namespace
ns.UI_CardLayoutManager = CardLayoutManager

print("|cff00ff00[WN CardLayoutManager]|r Module loaded successfully")
