--[[
    Warband Nexus - Search Results Renderer
    Clears result containers and toggles empty-state rows for tab search UIs.
]]

local ADDON_NAME, ns = ...

-- Debug print helper
local DebugPrint = ns.DebugPrint
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local DrawEmptyState = ns.UI_DrawEmptyState
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

-- SEARCH RESULTS RENDERER

local SearchResultsRenderer = {}

--[[
    Prepare container for rendering by safely clearing children
    CRITICAL: Protects emptyStateContainer from being destroyed
    
    @param container Frame - Results container to prepare
]]
function SearchResultsRenderer:PrepareContainer(container)
    if not container then 
        DebugPrint("[SearchResultsRenderer] ERROR: nil container in PrepareContainer")
        return 
    end
    
    -- Hide empty state container (will be shown again if needed)
    if container.emptyStateContainer then
        container.emptyStateContainer:Hide()
    end
    local searchCardKey = "emptyStateCard_" .. (ns.UI_SEARCH_EMPTY_TAB_KEY or "search")
    if container[searchCardKey] then
        container[searchCardKey]:Hide()
    end
    
    -- Release pooled children back to pool (if pooling is used)
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(container)
    end

    -- Nested list rows (currency/reputation collapsible sections) are not direct children of `container`;
    -- return them to pools before reparenting section wrappers to recycleBin (CurrencyUI / ReputationUI parity).
    local ReleaseCurrencyRowsFromSubtree = ns.UI_ReleaseCurrencyRowsFromSubtree
    local ReleaseReputationRowsFromSubtree = ns.UI_ReleaseReputationRowsFromSubtree

    -- Clear remaining children EXCEPT emptyStateContainer / Plans achievement browse root (virtual list scroll host)
    local bin = ns.UI_RecycleBin
    local IsProtected = ns.UI_IsProtectedResultsEmptyChild
    local children = {container:GetChildren()}
    for i = 1, #children do
        local child = children[i]
        if IsProtected and IsProtected(child, container) then
            -- fillParent empty-state cards are protected from recycle but must not bleed across redraws
            child:Hide()
        else
            if ReleaseCurrencyRowsFromSubtree then
                ReleaseCurrencyRowsFromSubtree(child)
            end
            if ReleaseReputationRowsFromSubtree then
                ReleaseReputationRowsFromSubtree(child)
            end
        end
    end
    for i = 1, #children do
        local child = children[i]
        if IsProtected and IsProtected(child, container) then
            child:Hide()
        else
            child:Hide()
            if bin then child:SetParent(bin) else child:SetParent(nil) end
        end
    end
end

--[[
    Render empty state in container
    
    @param addon table - Addon instance (for DrawEmptyState)
    @param container Frame - Results container
    @param searchText string - Current search query
    @param tabContext string - Tab identifier for context-specific messages
    @return number - Height offset after rendering
]]
function SearchResultsRenderer:RenderEmptyState(addon, container, searchText, tabContext)
    if not container then 
        DebugPrint("[SearchResultsRenderer] ERROR: nil container in RenderEmptyState")
        return 0
    end
    
    local isSearch = searchText and searchText ~= ""
    
    if isSearch and ns.UI_ShowSearchEmptyStateCard then
        return ns.UI_ShowSearchEmptyStateCard(container, searchText, 0, { fillParent = true })
    end

    local tabKey = tabContext
    if tabKey and tabKey ~= "" and ns.UI_ShowTabEmptyStateCard then
        return ns.UI_ShowTabEmptyStateCard(container, tabKey, 0, { fillParent = true })
    end

    if DrawEmptyState then
        return DrawEmptyState(addon, container, 0, isSearch, searchText, tabContext)
    end
    DebugPrint("[SearchResultsRenderer] ERROR: no empty-state renderer available")
    return 0
end

--[[
    Check if container needs preparation
    Used to avoid unnecessary clears when container is already clean
    
    @param container Frame - Container to check
    @return boolean - True if container has content that needs clearing
]]
function SearchResultsRenderer:NeedsClearing(container)
    if not container then return false end
    
    local IsProtected = ns.UI_IsProtectedResultsEmptyChild
    local children = {container:GetChildren()}
    
    -- If only protected empty-state children exist, no clearing needed
    if #children == 0 then return false end
    local protectedOnly = true
    for i = 1, #children do
        if not (IsProtected and IsProtected(children[i], container)) then
            protectedOnly = false
            break
        end
    end
    if protectedOnly then
        return false
    end
    
    return true
end

--[[
    Smart preparation - only clears if needed
    
    @param container Frame - Results container
]]
function SearchResultsRenderer:SmartPrepare(container)
    if self:NeedsClearing(container) then
        self:PrepareContainer(container)
    else
        -- Just hide empty state if it exists
        if container and container.emptyStateContainer then
            container.emptyStateContainer:Hide()
        end
    end
end

-- INITIALIZATION

-- Expose to namespace
ns.SearchResultsRenderer = SearchResultsRenderer
