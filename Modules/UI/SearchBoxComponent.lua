--[[
    Search box with icon, placeholder, debounced callback, and SearchStateManager registry.

    WN_FACTORY: Outer shell uses `Factory:CreateContainer` when available (`ApplyVisuals` on same frame); EditBox stays a native widget.
    Debounce SEARCH_DEBOUNCE_SEC (default 0.45s); focus lost flushes pending; ESC clears filter.
]]

local ADDON_NAME, ns = ...

local issecretvalue = issecretvalue
local format = string.format

-- Debug print helper
local DebugPrint = ns.DebugPrint
-- Import dependencies from namespace
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local FontManager = ns.FontManager

-- Per-owner debounce timers (Collections custom EditBox, Plans active list, etc.)
local searchRefreshTimers = {}
local searchRefreshPendingFn = {}

--- Registry: registryKey -> function(fireCallback) clears widget; fireCallback false = visual only.
local searchClearByKey = {}

---@param key string
---@param clearFn function|nil function(fireCallback) — fireCallback false skips filter redraw callback
function ns.UI_RegisterSearchBoxClear(key, clearFn)
    if key and clearFn then
        searchClearByKey[key] = clearFn
    end
end

--- Clear one registered search box. fireCallback false: wipe EditBox + SSM only (no list redraw).
---@param key string
---@param fireCallback boolean|nil default true
function ns.UI_ClearRegisteredSearchBox(key, fireCallback)
    if not key then return end
    if fireCallback == nil then fireCallback = true end
    ns.UI_CancelSearchRefresh(key)
    local clearFn = searchClearByKey[key]
    if clearFn then
        clearFn(fireCallback)
    end
    if not fireCallback then
        local SSM = ns.SearchStateManager
        if SSM and SSM.ClearSearch then
            SSM:ClearSearch(key)
        end
    end
end

--- Clear every CreateSearchBox / registered widget (optional silent mode for tab switches).
function ns.UI_ClearAllRegisteredSearchBoxes(fireCallback)
    for key in pairs(searchClearByKey) do
        ns.UI_ClearRegisteredSearchBox(key, fireCallback)
    end
end

---@return number seconds
local function GetSearchDebounceDelay(explicitDelay)
    if type(explicitDelay) == "number" and explicitDelay > 0 then
        return explicitDelay
    end
    local c = ns.UI_CONSTANTS
    if c and type(c.SEARCH_DEBOUNCE_SEC) == "number" and c.SEARCH_DEBOUNCE_SEC > 0 then
        return c.SEARCH_DEBOUNCE_SEC
    end
    return 0.45
end

--- Cancel a scheduled search refresh without running it.
function ns.UI_CancelSearchRefresh(ownerKey)
    if not ownerKey then return end
    local t = searchRefreshTimers[ownerKey]
    if t then
        t:Cancel()
        searchRefreshTimers[ownerKey] = nil
    end
    searchRefreshPendingFn[ownerKey] = nil
end

--- Run callback after user stops typing (debounce). Resets on each call with the same ownerKey.
function ns.UI_ScheduleSearchRefresh(ownerKey, callback, delaySec)
    if not ownerKey or type(callback) ~= "function" then return end
    ns.UI_CancelSearchRefresh(ownerKey)
    searchRefreshPendingFn[ownerKey] = callback
    local delay = GetSearchDebounceDelay(delaySec)
    searchRefreshTimers[ownerKey] = C_Timer.NewTimer(delay, function()
        searchRefreshTimers[ownerKey] = nil
        local fn = searchRefreshPendingFn[ownerKey]
        searchRefreshPendingFn[ownerKey] = nil
        if fn then fn() end
    end)
end

--- If a debounced refresh is pending, run it now (e.g. focus lost).
function ns.UI_FlushSearchRefresh(ownerKey)
    if not ownerKey then return end
    local fn = searchRefreshPendingFn[ownerKey]
    ns.UI_CancelSearchRefresh(ownerKey)
    if fn then fn() end
end

-- SEARCH BOX COMPONENT

---Creates a search box with icon, placeholder, and debounced callback
---@param parent Frame Parent frame
---@param width number Search box width
---@param placeholder string Placeholder text (e.g., "Search items...")
---@param onTextChanged function Callback function(searchText) - called after debounce idle
---@param debounceDelay number|nil Override delay in seconds (default UI_CONSTANTS.SEARCH_DEBOUNCE_SEC)
---@param initialValue string|nil Initial text value (optional, for restoring state)
---@param registryKey string|nil SearchStateManager tab id for clear-on-navigation (e.g. "items")
---@return Frame container Search box container frame
---@return function clearFunction function(fireCallback) — clears widget; pass false to skip filter callback
local function CreateSearchBox(parent, width, placeholder, onTextChanged, debounceDelay, initialValue, registryKey)
    local delay = GetSearchDebounceDelay(debounceDelay)
    local debounceTimer = nil
    local pendingSearchText = ""
    local initialText = initialValue or ""

    local Factory = ns.UI and ns.UI.Factory
    local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32

    local container = Factory and Factory.CreateContainer and Factory:CreateContainer(parent, width, searchH, false)
    if not container then
        container = CreateFrame("Frame", nil, parent)
        container:SetSize(width, searchH)
    end
    container.searchFrame = container
    
    if ns.UI_ApplySearchBoxChrome then
        ns.UI_ApplySearchBoxChrome(container)
    else
        local searchBg, searchBorder = ns.UI_GetSearchBoxChromeColors and ns.UI_GetSearchBoxChromeColors()
        if not searchBg then
            searchBg = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()
                or COLORS.bgCard or COLORS.bgLight or COLORS.bg
            local b = ns.UI_GetBorderStrokeColor and ns.UI_GetBorderStrokeColor() or COLORS.border
            searchBorder = { b[1], b[2], b[3], 0.55 }
        end
        ApplyVisuals(container, searchBg, searchBorder)
    end
    
    local searchBox = CreateFrame("EditBox", nil, container)
    searchBox:SetPoint("LEFT", 12, 0)
    searchBox:SetPoint("RIGHT", -10, 0)
    searchBox:SetHeight(20)
    
    local searchRole = FontManager:GetFontRole("searchEditBoxBody")
    FontManager:RegisterManagedEditBox(searchBox, searchRole)
    FontManager:ApplyFontToEditBox(searchBox, searchRole)
    if ns.UI_GetTextRoleRGB then
        local tr, tg, tb, ta = ns.UI_GetTextRoleRGB("Bright")
        searchBox:SetTextColor(tr, tg, tb, ta)
    end
    
    searchBox:SetAutoFocus(false)
    searchBox:SetMaxLetters(50)
    
    if initialText and initialText ~= "" then
        searchBox:SetText(initialText)
    end
    
    local placeholderText = FontManager:CreateFontString(searchBox, FontManager:GetFontRole("searchPlaceholder"), "ARTWORK")
    placeholderText:SetPoint("LEFT", 0, 0)
    placeholderText:SetText(placeholder or "Search...")
    ns.UI_SetTextColorRole(placeholderText, "Muted")
    
    if initialText and initialText ~= "" then
        placeholderText:Hide()
    else
        placeholderText:Show()
    end

    local function CancelDebounce()
        if debounceTimer then
            debounceTimer:Cancel()
            debounceTimer = nil
        end
    end

    local function FireSearchCallback(text)
        if onTextChanged then
            onTextChanged(text)
        end
    end

    local function ScheduleDebouncedSearch(text)
        pendingSearchText = text
        CancelDebounce()
        debounceTimer = C_Timer.NewTimer(delay, function()
            debounceTimer = nil
            FireSearchCallback(pendingSearchText)
        end)
    end
    
    searchBox:SetScript("OnTextChanged", function(self, userInput)
        if not userInput then return end
        
        local text = self:GetText()
        local newSearchText = ""
        if issecretvalue and issecretvalue(text) then
            placeholderText:Show()
            newSearchText = ""
        elseif type(text) == "string" and text ~= "" then
            placeholderText:Hide()
            newSearchText = text:lower()
        else
            placeholderText:Show()
            newSearchText = ""
        end

        ScheduleDebouncedSearch(newSearchText)
    end)
    
    searchBox:SetScript("OnEscapePressed", function(self)
        CancelDebounce()
        self:SetText("")
        placeholderText:Show()
        pendingSearchText = ""
        self:ClearFocus()
        FireSearchCallback("")
    end)
    
    searchBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    searchBox:SetScript("OnEditFocusLost", function()
        if debounceTimer then
            CancelDebounce()
            FireSearchCallback(pendingSearchText)
        end
    end)

    searchBox:SetScript("OnEditFocusGained", function(self)
        self:HighlightText()
    end)
    
    container:SetScript("OnHide", function()
        CancelDebounce()
    end)
    
    local function ClearSearchWidget(fireCallback)
        if fireCallback == nil then fireCallback = true end
        CancelDebounce()
        searchBox:SetText("")
        placeholderText:Show()
        pendingSearchText = ""
        if fireCallback then
            FireSearchCallback("")
        end
    end
    
    container._wnClearSearch = ClearSearchWidget
    container._wnSearchPlaceholder = placeholderText
    if registryKey and registryKey ~= "" then
        searchClearByKey[registryKey] = ClearSearchWidget
        container._wnSearchRegistryKey = registryKey
    end
    
    return container, ClearSearchWidget
end

--- Update placeholder copy on a CreateSearchBox container (e.g. Collections sub-tab switch).
function ns.UI_SetSearchBoxPlaceholder(container, text)
    if not container or not text then return end
    local fs = container._wnSearchPlaceholder
    if fs and fs.SetText then
        fs:SetText(text)
    end
end

ns.UI_CreateSearchBox = CreateSearchBox

-- Tab ids registered with SearchStateManager (main + browse sub-tabs).
ns.UI_SEARCH_TAB_IDS = {
    "items", "gear", "currency", "reputation", "collections",
    "plans_mount", "plans_pet", "plans_toy", "plans_transmog", "plans_illusion", "plans_title", "plans_achievement",
}

local COLLECTIONS_SEARCH_REFRESH_KEYS = {
    "collections_recent", "collections_mounts", "collections_pets", "collections_toys", "collections_achievements",
}

--- Hide FontStrings/textures tagged on scroll bodies (Professions hints, etc.) when switching tabs.
function ns.UI_HideEphemeralScrollRegions(scrollFrame)
    if not scrollFrame or not scrollFrame.GetNumRegions then return end
    local n = scrollFrame:GetNumRegions()
    for i = 1, n do
        local r = select(i, scrollFrame:GetRegions())
        if r and r._wnEphemeralScrollOverlay and r.Hide then
            r:Hide()
        end
    end
end

local function CancelAllSearchRefreshTimers()
    ns.UI_CancelSearchRefresh("plans_active")
    for i = 1, #COLLECTIONS_SEARCH_REFRESH_KEYS do
        ns.UI_CancelSearchRefresh(COLLECTIONS_SEARCH_REFRESH_KEYS[i])
    end
end

--- Clear every in-addon search query (main tab switch, window hide).
function ns.UI_ClearAllSearchQueries()
    CancelAllSearchRefreshTimers()
    ns.UI_ClearAllRegisteredSearchBoxes(false)

    local SSM = ns.SearchStateManager
    local ids = ns.UI_SEARCH_TAB_IDS
    if SSM and SSM.ClearSearch and ids then
        for i = 1, #ids do
            SSM:ClearSearch(ids[i])
        end
    end
    ns._plansActiveSearch = nil
    local coll = ns.CollectionsUI
    if coll and coll.state then
        coll.state.searchText = ""
        local sc = coll.state.searchContainer
        if sc and sc._wnClearSearch then
            sc._wnClearSearch(false)
        end
    end
end

--- Clear To-Do browse + active-plan search when switching Plans category chips.
function ns.UI_ClearPlansCategorySearches()
    local SSM = ns.SearchStateManager
    local ids = ns.UI_SEARCH_TAB_IDS
    if ids then
        for i = 1, #ids do
            local id = ids[i]
            if id:find("^plans_", 1) then
                ns.UI_ClearRegisteredSearchBox(id, false)
                if SSM and SSM.ClearSearch then
                    SSM:ClearSearch(id)
                end
            end
        end
    end
    ns.UI_ClearRegisteredSearchBox("plans_active", false)
    ns._plansActiveSearch = nil
    ns.UI_CancelSearchRefresh("plans_active")
end

--- Standard search-no-results panel (icon + title + body) for every tab.
function ns.UI_RenderStandardSearchEmptyState(addon, parent, searchText, tabContext, startY)
    if parent and parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    if ns.UI_ShowSearchEmptyStateCard then
        return ns.UI_ShowSearchEmptyStateCard(parent, searchText, startY or 0, { fillParent = true })
    end
    return startY or 0
end

--- Returns true when search text is non-empty and safe to filter on.
function ns.UI_IsSearchQueryActive(searchText)
    if not searchText or searchText == "" then return false end
    if issecretvalue and issecretvalue(searchText) then return false end
    return true
end

--- Shared one-line label for inline list rows (Recent column cards, etc.).
function ns.UI_FormatSearchEmptyMessage(searchText)
    local L = ns.L
    local q = searchText or ""
    if q ~= "" then
        return format((L and L["NO_ITEMS_MATCH"]) or "No items match '%s'", q)
    end
    return (L and L["NO_ITEMS_MATCH_GENERIC"]) or "No items match your search"
end
