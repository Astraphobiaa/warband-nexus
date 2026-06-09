--[[
    Warband Nexus - Tab/search empty state cards (elevated chrome).
    Split from SharedWidgets.lua to reduce main chunk size (Lua 5.1 local limit).
    Loaded from WarbandNexus.toc immediately after Modules/UI/SharedWidgets.lua.
]]

local _, ns = ...
local issecretvalue = issecretvalue
local FontManager = ns.FontManager
local UI_SPACING = ns.UI_SPACING or {}
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING

local function UIFontRole(roleKey)
    if FontManager and FontManager.GetFontRole then
        return FontManager:GetFontRole(roleKey)
    end
    return roleKey
end

local function ApplyStandardCardElevatedChrome(frame)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    end
end
--============================================================================
-- DRAW EMPTY STATE (Shared by Items and Storage tabs)
--============================================================================

local function DrawEmptyState(addon, parent, startY, isSearch, searchText, tabContext)
    if not parent or not parent.CreateTexture then
        return startY or 0
    end
    tabContext = tabContext or ""
    if isSearch then
        return ns.UI_ShowSearchEmptyStateCard(parent, searchText, startY, { fillParent = true })
    end
    local tabKey = (tabContext ~= "" and tabContext) or "items"
    if ns.UI_ShowTabEmptyStateCard then
        return ns.UI_ShowTabEmptyStateCard(parent, tabKey, startY, { fillParent = true })
    end
    return startY or 0
end

--============================================================================
-- DRAW SECTION EMPTY STATE (Collapsed section empty message)
--============================================================================

---Draw empty state for a collapsed section
---@param parent Frame Parent frame
---@param message string Empty state message
---@param yOffset number Current Y offset
---@param height number Height of empty state
---@param width number Width of empty state
---@return number newYOffset
local function DrawSectionEmptyState(parent, message, yOffset, height, width)
    if not parent then
        return yOffset
    end
    
    local emptyText = parent:CreateFontString(nil, "OVERLAY")
    FontManager:ApplyFont(emptyText, "body")
    emptyText:SetPoint("TOP", parent, "TOP", 0, -yOffset)
    emptyText:SetText("|cff999999" .. message .. "|r")
    emptyText:SetWidth(width or 300)
    emptyText:SetJustifyH("CENTER")
    
    return yOffset + (height or 30)
end

--============================================================================
-- EMPTY STATE CARD (Standardized "no data" state for all tabs)
--============================================================================

-- Per-tab empty state configuration
-- Uses the same atlas icons as TAB_HEADER_ICONS but larger and desaturated
local EMPTY_STATE_CONFIG = {
    characters = {
        atlas = "poi-town",
        titleKey = "EMPTY_CHARACTERS_TITLE",
        descKey = "EMPTY_CHARACTERS_DESC",
        titleFallback = "No Characters Found",
        descFallback = "Log in to your characters to start tracking them.\nCharacter data is collected automatically on each login.",
    },
    items = {
        atlas = "Banker",
        titleKey = "EMPTY_ITEMS_TITLE",
        descKey = "EMPTY_ITEMS_DESC",
        titleFallback = "No Items Cached",
        descFallback = "Open your Warband Bank or Personal Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_inventory = {
        atlas = "Backpack",
        titleKey = "EMPTY_INVENTORY_TITLE",
        descKey = "EMPTY_INVENTORY_DESC",
        titleFallback = "No Items in Inventory",
        descFallback = "Your inventory bags are empty.",
    },
    items_personal = {
        atlas = "Banker",
        titleKey = "EMPTY_PERSONAL_BANK_TITLE",
        descKey = "EMPTY_PERSONAL_BANK_DESC",
        titleFallback = "No Items in Personal Bank",
        descFallback = "Open your Personal Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_warband = {
        atlas = "Mobile-WarbandIcon",
        titleKey = "EMPTY_WARBAND_BANK_TITLE",
        descKey = "EMPTY_WARBAND_BANK_DESC",
        titleFallback = "No Items in Warband Bank",
        descFallback = "Open your Warband Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_guild = {
        atlas = "communities-icon-chat",
        titleKey = "EMPTY_GUILD_BANK_TITLE",
        descKey = "EMPTY_GUILD_BANK_DESC",
        titleFallback = "No Items in Guild Bank",
        descFallback = "Open your Guild Bank to scan items.\nItems are cached automatically on first visit.",
    },
    --- Unified search-no-results card (all tabs; description built from query at show time).
    search = {
        atlas = "common-search-magnifyingglass",
        titleKey = "NO_RESULTS",
        titleFallback = "No results",
    },
    storage = {
        atlas = "Quartermaster",
        titleKey = "EMPTY_STORAGE_TITLE",
        descKey = "EMPTY_STORAGE_DESC",
        titleFallback = "No Storage Data",
        descFallback = "Items are scanned when you open banks or bags.\nVisit a bank to start tracking your storage.",
    },
    plans = {
        atlas = "poi-workorders",
        titleKey = "EMPTY_PLANS_TITLE",
        descKey = "EMPTY_PLANS_DESC",
        titleFallback = "No Plans Yet",
        descFallback = "Browse Mounts, Pets, Toys, or Achievements above\nto add collection goals and track your progress.",
    },
    reputation = {
        atlas = "MajorFactions_MapIcons_Centaur64",
        titleKey = "EMPTY_REPUTATION_TITLE",
        descKey = "EMPTY_REPUTATION_DESC",
        titleFallback = "No Reputation Data",
        descFallback = "Reputations are scanned automatically on login.\nLog in to a character to start tracking faction standings.",
    },
    currency = {
        atlas = "AzeriteReady",
        titleKey = "EMPTY_CURRENCY_TITLE",
        descKey = "EMPTY_CURRENCY_DESC",
        titleFallback = "No Currency Data",
        descFallback = "Currencies are tracked automatically across your characters.\nLog in to a character to start tracking currencies.",
    },
    pve = {
        atlas = "Tormentors-Boss",
        titleKey = "EMPTY_PVE_TITLE",
        descKey = "EMPTY_PVE_DESC",
        titleFallback = "No PvE Data",
        descFallback = "PvE progress is tracked when you log into your characters.\nGreat Vault, Mythic+, and Raid lockouts will appear here.",
    },
    -- Weekly Vault Tracker filter: no character has claimable vault (cached + live check)
    pve_vault = {
        atlas = "Tormentors-Boss",
        titleKey = "PVE_VAULT_TRACKER_EMPTY_TITLE",
        descKey = "PVE_VAULT_TRACKER_EMPTY_DESC",
        titleFallback = "No vault rows yet",
        descFallback = "No tracked character has weekly vault progress saved yet.\nTurn off Weekly Vault Tracker to see full PvE progress.",
    },
    statistics = {
        atlas = "racing",
        titleKey = "EMPTY_STATISTICS_TITLE",
        descKey = "EMPTY_STATISTICS_DESC",
        titleFallback = "No Statistics Available",
        descFallback = "Statistics are gathered from your tracked characters.\nLog in to a character to start collecting data.",
    },
    collections = {
        atlas = "dragon-rostrum",
        titleKey = "COLLECTIONS_COMING_SOON_TITLE",
        descKey = "COLLECTIONS_COMING_SOON_DESC",
        titleFallback = "Coming Soon",
        descFallback = "Collection overview (mounts, pets, toys, transmog) will be available here.",
    },
    plans_achievement = {
        atlas = "Achievement-Icon",
        titleKey = "PLANS_ACHIEVEMENTS_EMPTY_TITLE",
        descKey = "PLANS_ACHIEVEMENTS_EMPTY_HINT",
        titleFallback = "No achievements to display",
        descFallback = "Add achievements from this list to your To-Do, or change Show Planned / Show Completed. The list fills as achievements are scanned; try /reload if nothing appears.",
    },
    gear = {
        atlas = "poi-helm",
        titleKey = "GEAR_NO_TRACKED_CHARACTERS_TITLE",
        descKey = "GEAR_NO_TRACKED_CHARACTERS_DESC",
        titleFallback = "No tracked characters",
        descFallback = "Log in to a character to start tracking gear.",
    },
    gear_filter = {
        atlas = "poi-helm",
        titleKey = "GEAR_FILTER_EMPTY_TITLE",
        descKey = "GEAR_FILTER_EMPTY_DESC",
        titleFallback = "No characters match the level filter",
        descFallback = "Turn off Hide or lower the level threshold using the Hide button above to show characters again.",
    },
    professions = {
        atlas = "Professions-Icon-Accept-Order",
        titleFallback = "No profession data",
        descKey = "NO_PROFESSIONS_DATA",
        descFallback = "Open your profession window (default: K) on each character to collect data.",
    },
}

local SEARCH_EMPTY_TAB_KEY = "search"
ns.UI_SEARCH_EMPTY_TAB_KEY = SEARCH_EMPTY_TAB_KEY

local format = string.format

local function BuildSearchEmptyDescription(searchText)
    local L = ns.L
    local q = searchText or ""
    if issecretvalue and issecretvalue(q) then
        q = ""
    end
    local body
    if q ~= "" then
        body = format((L and L["NO_ITEMS_MATCH"]) or "No items match '%s'", q)
    else
        body = (L and L["NO_ITEMS_MATCH_GENERIC"]) or "No items match your search"
    end
    local hint = (L and L["TRY_ADJUSTING_SEARCH"]) or "Try adjusting your search or filters."
    return body .. "\n" .. hint
end

--- @return boolean
function ns.UI_IsProtectedResultsEmptyChild(child, container)
    if not child or not container then return false end
    if child == container.emptyStateContainer then return true end
    if child == container.plansAchBrowseRoot then return true end
    if child._wnExcludedFromStorageExtent then return true end
    if child == container["emptyStateCard_" .. SEARCH_EMPTY_TAB_KEY] then return true end
    return false
end

-- Creates a standardized empty state card for any tab
-- Centered vertically in parent with icon, title, and description
-- @param parent: Parent frame to attach to
-- @param tabName: string - Tab identifier (e.g., "characters", "items", "pve")
-- @param yOffset: number - Y offset from top (default 0)
-- @param opts table|nil { fillParent = true } fills parent width (use inside resultsContainer); { sideInset = n }
-- @return Frame - The empty state frame (shown automatically)
-- @return number - Height delta below yOffset (callers use: return yOffset + secondReturn)
local function CreateEmptyStateCard(parent, tabName, yOffset, opts)
    yOffset = yOffset or 0
    opts = opts or {}
    local FontManager = ns.FontManager
    local fillParent = opts.fillParent == true
    local sideInset = opts.sideInset
    if sideInset == nil then
        sideInset = fillParent and 0 or UI_SPACING.SIDE_MARGIN
    end
    local layout = ns.UI_LAYOUT or {}
    local bottomPad = layout.SECTION_SPACING or UI_SPACING.SIDE_MARGIN or 8

    -- Walk up the parent chain to find the actual ScrollFrame viewport
    -- parent may be a resultsContainer nested inside the scrollChild, so parent:GetParent() alone is unreliable
    local function GetScrollViewportHeight(startFrame)
        local visibleHeight = 600  -- safe fallback
        local current = startFrame
        for i = 1, 5 do
            current = current and current:GetParent()
            if not current then break end
            if current.GetObjectType and current:GetObjectType() == "ScrollFrame" then
                local h = current:GetHeight()
                if h and h > 0 then visibleHeight = h end
                break
            end
        end
        return visibleHeight
    end

    -- Get config for this tab
    local configTabName = tabName
    if tabName == SEARCH_EMPTY_TAB_KEY or (opts.searchText ~= nil) then
        configTabName = SEARCH_EMPTY_TAB_KEY
    end
    local config = EMPTY_STATE_CONFIG[configTabName]
    if opts.titleText or opts.descText or opts.atlas then
        local base = config or {}
        config = {
            atlas = opts.atlas or base.atlas or "shop-icon-housing-characters-up",
            titleKey = base.titleKey,
            descKey = base.descKey,
            titleFallback = opts.titleText or base.titleFallback or "No Data",
            descFallback = opts.descText or base.descFallback or "",
        }
    end
    if not config then
        config = {
            atlas = "shop-icon-housing-characters-up",
            titleKey = "NO_DATA",
            descKey = nil,
            titleFallback = "No Data",
            descFallback = "No data available.",
        }
    end

    local atlasForIcon = opts.atlas or config.atlas
    if configTabName == "reputation" and not opts.atlas and ns.UI_GetTabIcon then
        local dyn = ns.UI_GetTabIcon("reputation")
        if dyn and dyn ~= "" then
            atlasForIcon = dyn
        end
    end

    local function ResolveEmptyTitle()
        if opts.titleText then return opts.titleText end
        return (ns.L and config.titleKey and ns.L[config.titleKey]) or config.titleFallback
    end

    local function ResolveEmptyDesc()
        if configTabName == SEARCH_EMPTY_TAB_KEY then
            return BuildSearchEmptyDescription(opts.searchText)
        end
        if opts.descText then return opts.descText end
        return (ns.L and config.descKey and ns.L[config.descKey]) or config.descFallback
    end

    -- Reuse existing empty state card on parent
    -- PopulateContent moves scrollChild children to recycleBin each pass — reparent back every show.
    local cardStorageKey = opts.cacheKey or configTabName
    if configTabName == SEARCH_EMPTY_TAB_KEY then
        cardStorageKey = SEARCH_EMPTY_TAB_KEY
    end
    local cacheKey = "emptyStateCard_" .. cardStorageKey
    local card = parent[cacheKey]
    local descText = ResolveEmptyDesc()
    if card then
        local visibleHeight = GetScrollViewportHeight(parent)
        local heightTrim = yOffset + sideInset + bottomPad
        if not fillParent then
            heightTrim = heightTrim + sideInset
        end
        local cardHeight = math.max(visibleHeight - heightTrim, 200)
        card:SetParent(parent)
        card:ClearAllPoints()
        card:SetPoint("TOPLEFT", sideInset, -yOffset)
        card:SetPoint("TOPRIGHT", -sideInset, -yOffset)
        card:SetHeight(cardHeight)
        if fillParent then
            card._wnExcludedFromStorageExtent = true
        end
        ApplyStandardCardElevatedChrome(card)
        if card._emptyIcon and atlasForIcon then
            card._emptyIcon:SetAtlas(atlasForIcon)
        end
        if card._emptyTitle then
            card._emptyTitle:SetText("|cff888888" .. ResolveEmptyTitle() .. "|r")
        end
        if card._emptyDesc and descText then
            card._emptyDesc:SetText("|cff666666" .. descText .. "|r")
        end
        card:Show()
        return card, cardHeight + bottomPad
    end

    local visibleHeight = GetScrollViewportHeight(parent)
    local heightTrim = yOffset + sideInset + bottomPad
    if not fillParent then
        heightTrim = heightTrim + sideInset
    end
    local cardHeight = math.max(visibleHeight - heightTrim, 200)

    -- Filled elevated card matching tab title chrome (section atlas underlay)
    card = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate")
    card:SetPoint("TOPLEFT", sideInset, -yOffset)
    card:SetPoint("TOPRIGHT", -sideInset, -yOffset)
    card:SetHeight(cardHeight)
    parent[cacheKey] = card
    if fillParent then
        card._wnExcludedFromStorageExtent = true
    end
    ApplyStandardCardElevatedChrome(card)

    -- Content container (truly centered in card)
    local contentContainer = CreateFrame("Frame", nil, card)
    contentContainer:SetSize(400, 200)
    contentContainer:SetPoint("CENTER", card, "CENTER", 0, 0)

    -- Icon (large, pure)
    local iconSize = 64
    local iconContainer = CreateFrame("Frame", nil, contentContainer)
    iconContainer:SetSize(iconSize, iconSize)
    iconContainer:SetPoint("TOP", contentContainer, "TOP", 0, 0)

    local icon = iconContainer:CreateTexture(nil, "OVERLAY", nil, 7)
    icon:SetAllPoints(iconContainer)
    icon:SetAtlas(atlasForIcon)
    icon:SetAlpha(0.6)
    card._emptyIcon = icon

    -- Title
    local title = FontManager:CreateFontString(contentContainer, UIFontRole("emptyCardTitle"), "OVERLAY")
    title:SetPoint("TOP", iconContainer, "BOTTOM", 0, -20)
    title:SetText("|cff888888" .. ResolveEmptyTitle() .. "|r")
    card._emptyTitle = title

    -- Description
    local desc = FontManager:CreateFontString(contentContainer, UIFontRole("emptyCardBody"), "OVERLAY")
    desc:SetPoint("TOP", title, "BOTTOM", 0, -12)
    desc:SetWidth(380)
    desc:SetJustifyH("CENTER")
    if not descText then
        descText = ResolveEmptyDesc()
    end
    desc:SetText("|cff666666" .. (descText or "") .. "|r")
    card._emptyDesc = desc

    card:Show()
    -- Second value is delta only (callers do: return yOffset + height)
    return card, cardHeight + bottomPad
end

-- Hide empty state card for a specific tab
-- @param parent: Parent frame
-- @param tabName: string - Tab identifier
local function HideEmptyStateCard(parent, tabName)
    if not parent then return end
    local cacheKey = "emptyStateCard_" .. tabName
    if parent[cacheKey] then
        parent[cacheKey]:Hide()
    end
end

-- Export empty state helpers
ns.UI_CreateEmptyStateCard = CreateEmptyStateCard
ns.UI_HideEmptyStateCard = HideEmptyStateCard
ns.UI_EMPTY_STATE_CONFIG = EMPTY_STATE_CONFIG

--- True when a virtual flat list contains at least one data row.
function ns.UI_FlatListHasDataRows(flatList)
    if not flatList then return false end
    for i = 1, #flatList do
        if flatList[i].type == "row" then return true end
    end
    return false
end

--- Show unified search-no-results card when query is active; returns true if shown.
function ns.UI_TryShowSearchEmptyInContainer(parent, searchText, yOffset)
    if not parent then return false end
    local q = searchText or ""
    if q == "" or (issecretvalue and issecretvalue(q)) then
        return false
    end
    if ns.UI_ShowSearchEmptyStateCard then
        ns.UI_ShowSearchEmptyStateCard(parent, q, yOffset or 0, { fillParent = true })
        return true
    end
    return false
end

--- Elevated card empty state for active search with zero matches (same chrome as tab empty cards).
function ns.UI_ShowSearchEmptyStateCard(parent, searchText, yOffset, opts)
    if not parent then return yOffset or 0 end
    opts = opts or {}
    if opts.fillParent == nil then
        opts.fillParent = true
    end
    opts.searchText = searchText or ""
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    local _, extent = CreateEmptyStateCard(parent, SEARCH_EMPTY_TAB_KEY, yOffset or 0, opts)
    return (yOffset or 0) + (extent or 200)
end

--- Standard tab/filter empty state (elevated card; use inside results containers).
function ns.UI_ShowTabEmptyStateCard(parent, tabName, yOffset, opts)
    if not parent then return yOffset or 0 end
    opts = opts or {}
    if opts.fillParent == nil then
        opts.fillParent = true
    end
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    if parent["emptyStateCard_" .. SEARCH_EMPTY_TAB_KEY] then
        parent["emptyStateCard_" .. SEARCH_EMPTY_TAB_KEY]:Hide()
    end
    local _, extent = CreateEmptyStateCard(parent, tabName or "items", yOffset or 0, opts)
    return (yOffset or 0) + (extent or 200)
end

ns.UI_DrawEmptyState = DrawEmptyState
ns.UI_DrawSectionEmptyState = DrawSectionEmptyState