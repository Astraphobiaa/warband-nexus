--[[
    Warband Nexus - Search Results Renderer (View Helper)
    
    Standardized result rendering and container management
    - Safely clears containers while protecting emptyStateContainer
    - Manages empty state visibility and rendering
    - Provides consistent API for all UI tabs
    
    Architecture: View Helper (NOT a Service - UI manipulation only)
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- Import shared UI components
local DrawEmptyState = ns.UI_DrawEmptyState
local ReleaseAllPooledChildren = ns.UI_ReleaseAllPooledChildren

--============================================================================
-- SEARCH RESULTS RENDERER
--============================================================================

local SearchResultsRenderer = {}

--[[
    Prepare container for rendering by safely clearing children
    CRITICAL: Protects emptyStateContainer from being destroyed
    
    @param container Frame - Results container to prepare
]]
function SearchResultsRenderer:PrepareContainer(container)
    if not container then 
        print("[SearchResultsRenderer] ERROR: nil container in PrepareContainer")
        return 
    end
    
    -- Hide empty state container (will be shown again if needed)
    if container.emptyStateContainer then
        container.emptyStateContainer:Hide()
    end
    
    -- Release pooled children back to pool (if pooling is used)
    if ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(container)
    end
    
    -- Clear remaining children EXCEPT emptyStateContainer
    local children = {container:GetChildren()}
    for _, child in ipairs(children) do
        if child ~= container.emptyStateContainer then
            child:Hide()
            child:SetParent(nil)
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
        print("[SearchResultsRenderer] ERROR: nil container in RenderEmptyState")
        return 0
    end
    
    local isSearch = searchText and searchText ~= ""
    
    -- Use shared DrawEmptyState function
    if DrawEmptyState then
        return DrawEmptyState(addon, container, 0, isSearch, searchText)
    else
        print("[SearchResultsRenderer] ERROR: DrawEmptyState not found in namespace")
        return 0
    end
end

--[[
    Check if container needs preparation
    Used to avoid unnecessary clears when container is already clean
    
    @param container Frame - Container to check
    @return boolean - True if container has content that needs clearing
]]
function SearchResultsRenderer:NeedsClearing(container)
    if not container then return false end
    
    local children = {container:GetChildren()}
    
    -- If only emptyStateContainer exists, no clearing needed
    if #children == 0 then return false end
    if #children == 1 and children[1] == container.emptyStateContainer then
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

--============================================================================
-- INITIALIZATION
--============================================================================

-- Expose to namespace
ns.SearchResultsRenderer = SearchResultsRenderer
