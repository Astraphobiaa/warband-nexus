--[[
    Warband Nexus - Card Layout Manager
    Dynamic card positioning system for grid layouts with expand/collapse support
    
    Extracted from SharedWidgets.lua for better modularity
    Handles card positioning in Plans UI with automatic height adjustment
]]

local ADDON_NAME, ns = ...

local wipe = wipe
local tinsert = table.insert
local sort = table.sort

-- Verbose-only: layout creation is noisy in normal debug mode.
local DebugVerbosePrint = ns.DebugVerbosePrint
local IsDebugVerboseEnabled = ns.IsDebugVerboseEnabled

--============================================================================
-- DYNAMIC CARD LAYOUT MANAGER
--============================================================================

--[[
    Dynamic Card Layout Manager
    Handles card positioning in a grid layout, automatically adjusting when cards expand/collapse
]]
local CardLayoutManager = {}
CardLayoutManager.instances = {}  -- Track layout instances per parent

local function ResolveGridCardWidth(instance, card)
    local parentWidth = instance.parent and instance.parent:GetWidth() or 0
    if parentWidth <= 0 then
        return 200
    end
    local padH = instance.padH or 10
    local sp = instance.cardSpacing or 8
    local cols = instance.columns or 2
    local computed = math.max(100, (parentWidth - 2 * padH - (cols - 1) * sp) / cols)
    local cw = card and card.GetWidth and card:GetWidth()
    if cw and cw > 0 then
        return math.min(cw, computed)
    end
    return computed
end

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
    
    local padH = 10
    if ns.UI_PLANS_CARD_METRICS and ns.UI_PLANS_CARD_METRICS.browseCardPadH then
        padH = ns.UI_PLANS_CARD_METRICS.browseCardPadH
    end

    local instance = {
        parent = parent,
        columns = columns,
        cardSpacing = cardSpacing,
        padH = padH,
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

    if not parent._wnCardLayoutHideHook then
        parent._wnCardLayoutHideHook = true
        parent:HookScript("OnHide", function()
            self.instances[instanceKey] = nil
        end)
    end
    
    if DebugVerbosePrint and IsDebugVerboseEnabled and IsDebugVerboseEnabled() then
        DebugVerbosePrint("|cff9d5cff[WN CardLayoutManager]|r Layout instance created: " ..
              columns .. " columns, " .. cardSpacing .. "px spacing")
    end
    
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
    
    local cardWidth = ResolveGridCardWidth(instance, card)
    local padH = instance.padH or 10
    local xOffset = padH + col * (cardWidth + instance.cardSpacing)

    -- Position card
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", xOffset, -yOffset)
    card:SetWidth(cardWidth)
    
    -- Store card info
    local cardInfo = {
        card = card,
        col = col,
        baseHeight = baseHeight,
        currentHeight = baseHeight,
        yOffset = yOffset,
        rowIndex = #instance.cards,
    }
    tinsert(instance.cards, cardInfo)
    
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
--- Apply pixel height + layout bookkeeping without recomputing the grid (batch reflows).
function CardLayoutManager:ApplyCardGeometry(card, newHeight)
    if not card or not newHeight then return end
    local cardInfo = card._layoutInfo
    if cardInfo then
        cardInfo.currentHeight = newHeight
    end
    card:SetHeight(newHeight)
end

function CardLayoutManager:UpdateCardHeight(card, newHeight)
    local instance = card._layoutManager
    local cardInfo = card._layoutInfo
    
    if not instance or not cardInfo then
        return
    end
    
    self:ApplyCardGeometry(card, newHeight)
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
    Masonry layout: each column advances independently for tight packing
    @param instance table - Layout instance
]]
function CardLayoutManager:RecalculateAllPositions(instance)
    if not instance or not instance.parent then
        return
    end
    
    local parentWidth = instance.parent:GetWidth()
    if parentWidth <= 0 then return end
    local padH = instance.padH or 10
    
    -- Reset column Y offsets
    for col = 0, instance.columns - 1 do
        instance.currentYOffsets[col] = instance.startYOffset
    end
    
    -- Sort cards by their original row index to maintain order (reuse scratch — avoids a new table per reflow)
    local sortedCards = instance._wnSortedScratch
    if not sortedCards then
        sortedCards = {}
        instance._wnSortedScratch = sortedCards
    end
    wipe(sortedCards)
    for i = 1, #instance.cards do
        sortedCards[i] = instance.cards[i]
    end
    sort(sortedCards, function(a, b)
        return a.rowIndex < b.rowIndex
    end)
    
    -- Helper: sync all column Y offsets to the maximum (for full-width cards)
    local function SyncAllColumns()
        local maxY = instance.startYOffset
        for c = 0, instance.columns - 1 do
            maxY = math.max(maxY, instance.currentYOffsets[c] or instance.startYOffset)
        end
        for c = 0, instance.columns - 1 do
            instance.currentYOffsets[c] = maxY
        end
    end
    
    -- Reposition all cards (masonry: each column independent)
    for i = 1, #sortedCards do
        local cardInfo = sortedCards[i]
        local col = cardInfo.col
        local currentHeight = cardInfo.currentHeight or cardInfo.baseHeight
        
        -- Handle full-width cards (weekly vault, daily quest header, etc.)
        if cardInfo.isFullWidth then
            -- Full-width cards need all columns synced first
            SyncAllColumns()
            
            local yOffset = instance.currentYOffsets[0] or instance.startYOffset
            cardInfo.card:ClearAllPoints()
            cardInfo.card:SetPoint("TOPLEFT", instance.parent, "TOPLEFT", padH, -yOffset)
            cardInfo.card:SetPoint("TOPRIGHT", instance.parent, "TOPRIGHT", -padH, -yOffset)
            for c = 0, instance.columns - 1 do
                instance.currentYOffsets[c] = yOffset + currentHeight + instance.cardSpacing
            end
            cardInfo.yOffset = yOffset
        else
            -- Masonry: place card at this column's current Y offset
            local yOffset = instance.currentYOffsets[col] or instance.startYOffset
            local cardWidth = ResolveGridCardWidth(instance, cardInfo.card)
            local xOffset = padH + col * (cardWidth + instance.cardSpacing)

            cardInfo.card:ClearAllPoints()
            cardInfo.card:SetPoint("TOPLEFT", xOffset, -yOffset)
            cardInfo.card:SetWidth(cardWidth)
            
            instance.currentYOffsets[col] = yOffset + currentHeight + instance.cardSpacing
            cardInfo.yOffset = yOffset
        end
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
    
    -- Width changed: reposition for new card widths, then remeasure wrapped text/heights.
    self:RecalculateAllPositions(instance)
    local PCF = ns.UI_PlanCardFactory
    if PCF and PCF.ReflowAllPlanCards then
        PCF:ReflowAllPlanCards(instance)
    end
    self:RecalculateAllPositions(instance)
end

--============================================================================
-- NAMESPACE EXPORTS
--============================================================================

-- Export to namespace
ns.UI_CardLayoutManager = CardLayoutManager

-- Module loaded - verbose logging removed
