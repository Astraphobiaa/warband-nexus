--[[
    Warband Nexus - Tab/search empty state cards (elevated chrome).
    Split from SharedWidgets.lua to reduce main chunk size (Lua 5.1 local limit).
    Loaded from WarbandNexus.toc immediately after Modules/UI/SharedWidgets.lua.
]]

local _, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local issecretvalue = issecretvalue
local FontManager = ns.FontManager
--- Live markup role table (`SharedWidgets_Theme.lua`). Mutated in place on theme change,
--- so this reference stays current -- never copy a role out of it into another local.
local HEX = ns.UI_HEX
local UI_SPACING = ns.UI_SPACING or {}
local UI_LAYOUT = ns.UI_LAYOUT or UI_SPACING

local function UIFontRole(roleKey)
    if FontManager and FontManager.GetFontRole then
        return FontManager:GetFontRole(roleKey)
    end
    return roleKey
end

local function ResolveEmptyStateHex(role, fallback)
    if ns.UI_GetTextRoleHex then
        return ns.UI_GetTextRoleHex(role)
    end
    return fallback
end

local function ApplyStandardCardElevatedChrome(frame)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    end
end

-- DRAW EMPTY STATE (Shared by Items and Storage tabs)

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

-- DRAW SECTION EMPTY STATE (Collapsed section empty message)

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
    if ns.UI_HookFontStringInk then
        ns.UI_HookFontStringInk(emptyText)
    end
    FontManager:ApplyFont(emptyText, "body")
    emptyText:SetPoint("TOP", parent, "TOP", 0, -yOffset)
    emptyText:SetText(ResolveEmptyStateHex("Dim", HEX.dim) .. message .. "|r")
    emptyText:SetWidth(width or 300)
    emptyText:SetJustifyH("CENTER")
    
    return yOffset + (height or 30)
end

-- EMPTY STATE CARD (Standardized "no data" state for all tabs)

-- Per-tab empty state configuration
-- Icons come from EMPTY_STATE_ICON_KEYS (registry); `atlas` only where no registry key exists yet
local EMPTY_STATE_CONFIG = {
    characters = {
        titleKey = "EMPTY_CHARACTERS_TITLE",
        descKey = "EMPTY_CHARACTERS_DESC",
        titleFallback = "No Characters Found",
        descFallback = "Log in to your characters to start tracking them.\nCharacter data is collected automatically on each login.",
    },
    items = {
        titleKey = "EMPTY_ITEMS_TITLE",
        descKey = "EMPTY_ITEMS_DESC",
        titleFallback = "No Items Cached",
        descFallback = "Open your Warband Bank or Personal Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_inventory = {
        titleKey = "EMPTY_INVENTORY_TITLE",
        descKey = "EMPTY_INVENTORY_DESC",
        titleFallback = "No Items in Inventory",
        descFallback = "Your inventory bags are empty.",
    },
    items_personal = {
        titleKey = "EMPTY_PERSONAL_BANK_TITLE",
        descKey = "EMPTY_PERSONAL_BANK_DESC",
        titleFallback = "No Items in Personal Bank",
        descFallback = "Open your Personal Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_warband = {
        titleKey = "EMPTY_WARBAND_BANK_TITLE",
        descKey = "EMPTY_WARBAND_BANK_DESC",
        titleFallback = "No Items in Warband Bank",
        descFallback = "Open your Warband Bank to scan items.\nItems are cached automatically on first visit.",
    },
    items_guild = {
        titleKey = "EMPTY_GUILD_BANK_TITLE",
        descKey = "EMPTY_GUILD_BANK_DESC",
        titleFallback = "No Items in Guild Bank",
        descFallback = "Open your Guild Bank to scan items.\nItems are cached automatically on first visit.",
    },
    --- Unified search-no-results card (all tabs; description built from query at show time).
    search = {
        titleKey = "NO_RESULTS",
        titleFallback = "No results",
    },
    storage = {
        titleKey = "EMPTY_STORAGE_TITLE",
        descKey = "EMPTY_STORAGE_DESC",
        titleFallback = "No Storage Data",
        descFallback = "Items are scanned when you open banks or bags.\nVisit a bank to start tracking your storage.",
    },
    plans = {
        titleKey = "EMPTY_PLANS_TITLE",
        descKey = "EMPTY_PLANS_DESC",
        titleFallback = "No Plans Yet",
        descFallback = "Browse Mounts, Pets, Toys, or Achievements above\nto add collection goals and track your progress.",
    },
    plans_active = {
        titleKey = "EMPTY_PLANS_ACTIVE_TITLE",
        descKey = "EMPTY_PLANS_ACTIVE_DESC",
        titleFallback = "No To-Do Items Yet",
        descFallback = "Browse Mounts, Pets, Toys, or Achievements above to add goals to your list,\nor use Add Vault to track Great Vault progress.",
    },
    plans_daily_tasks = {
        titleKey = "EMPTY_PLANS_WEEKLY_TITLE",
        descKey = "EMPTY_PLANS_WEEKLY_DESC",
        titleFallback = "No Weekly Progress Yet",
        descFallback = "Use Add Quest above to start tracking weekly quest progress\non your characters.",
    },
    reputation = {
        titleKey = "EMPTY_REPUTATION_TITLE",
        descKey = "EMPTY_REPUTATION_DESC",
        titleFallback = "No Reputation Data",
        descFallback = "Reputations are scanned automatically on login.\nLog in to a character to start tracking faction standings.",
    },
    currency = {
        titleKey = "EMPTY_CURRENCY_TITLE",
        descKey = "EMPTY_CURRENCY_DESC",
        titleFallback = "No Currency Data",
        descFallback = "Currencies are tracked automatically across your characters.\nLog in to a character to start tracking currencies.",
    },
    pve = {
        titleKey = "EMPTY_PVE_TITLE",
        descKey = "EMPTY_PVE_DESC",
        titleFallback = "No PvE Data",
        descFallback = "PvE progress is tracked when you log into your characters.\nGreat Vault, Mythic+, and Raid lockouts will appear here.",
    },
    -- Weekly Vault Tracker filter: no character has claimable vault (cached + live check)
    pve_vault = {
        titleKey = "PVE_VAULT_TRACKER_EMPTY_TITLE",
        descKey = "PVE_VAULT_TRACKER_EMPTY_DESC",
        titleFallback = "No vault rows yet",
        descFallback = "No tracked character has weekly vault progress saved yet.\nTurn off Weekly Vault Tracker to see full PvE progress.",
    },
    statistics = {
        titleKey = "EMPTY_STATISTICS_TITLE",
        descKey = "EMPTY_STATISTICS_DESC",
        titleFallback = "No Statistics Available",
        descFallback = "Statistics are gathered from your tracked characters.\nLog in to a character to start collecting data.",
    },
    collections = {
        titleKey = "COLLECTIONS_COMING_SOON_TITLE",
        descKey = "COLLECTIONS_COMING_SOON_DESC",
        titleFallback = "Coming Soon",
        descFallback = "Collection overview (mounts, pets, toys) will be available here.",
    },
    collections_recent = {
        titleKey = "COLLECTIONS_RECENT_TAB_EMPTY",
        descKey = "COLLECTIONS_RECENT_TAB_EMPTY_DESC",
        titleFallback = "Nothing recorded yet.",
        descFallback = "Recent mounts, pets, toys, and achievements you earn will appear here.",
    },
    collections_mounts = {
        titleKey = "EMPTY_COLLECTIONS_MOUNTS_TITLE",
        descKey = "EMPTY_COLLECTIONS_MOUNTS_DESC",
        titleFallback = "No mounts to show",
        descFallback = "Adjust search or filters, or wait for the mount journal to finish loading.",
    },
    collections_pets = {
        titleKey = "EMPTY_COLLECTIONS_PETS_TITLE",
        descKey = "EMPTY_COLLECTIONS_PETS_DESC",
        titleFallback = "No pets to show",
        descFallback = "Adjust search or filters, or wait for the pet journal to finish loading.",
    },
    collections_toys = {
        titleKey = "EMPTY_COLLECTIONS_TOYS_TITLE",
        descKey = "EMPTY_COLLECTIONS_TOYS_DESC",
        titleFallback = "No toys to show",
        descFallback = "Adjust search or filters, or wait for the toy box to finish loading.",
    },
    collections_illusions = {
        titleKey = "EMPTY_COLLECTIONS_ILLUSIONS_TITLE",
        descKey = "EMPTY_COLLECTIONS_ILLUSIONS_DESC",
        titleFallback = "No illusions to show",
        descFallback = "Adjust search or filters, or wait for the illusion list to finish loading.",
    },
    collections_titles = {
        titleKey = "EMPTY_COLLECTIONS_TITLES_TITLE",
        descKey = "EMPTY_COLLECTIONS_TITLES_DESC",
        titleFallback = "No titles to show",
        descFallback = "Adjust search or filters, or wait for the title list to finish loading.",
    },
    collections_achievements = {
        titleKey = "EMPTY_COLLECTIONS_ACHIEVEMENTS_TITLE",
        descKey = "EMPTY_COLLECTIONS_ACHIEVEMENTS_DESC",
        titleFallback = "No achievements to show",
        descFallback = "Adjust search or filters, or try /reload if the achievement list stays blank.",
    },
    plans_achievement = {
        titleKey = "PLANS_ACHIEVEMENTS_EMPTY_TITLE",
        descKey = "PLANS_ACHIEVEMENTS_EMPTY_HINT",
        titleFallback = "No achievements to display",
        descFallback = "Add achievements from this list to your To-Do, or change Show Planned / Show Completed. The list fills as achievements are scanned; try /reload if nothing appears.",
    },
    plans_mount = {
        titleKey = "EMPTY_PLANS_MOUNT_TITLE",
        descKey = "EMPTY_PLANS_MOUNT_DESC",
        titleFallback = "No mounts to show",
        descFallback = "Add mounts from this tab to your To-Do, or adjust Show Planned / Show Completed.",
    },
    plans_pet = {
        titleKey = "EMPTY_PLANS_PET_TITLE",
        descKey = "EMPTY_PLANS_PET_DESC",
        titleFallback = "No pets to show",
        descFallback = "Add pets from this tab to your To-Do, or adjust Show Planned / Show Completed.",
    },
    plans_toy = {
        titleKey = "EMPTY_PLANS_TOY_TITLE",
        descKey = "EMPTY_PLANS_TOY_DESC",
        titleFallback = "No toys to show",
        descFallback = "Add toys from this tab to your To-Do, or adjust Show Planned / Show Completed.",
    },
    plans_illusion = {
        titleKey = "EMPTY_PLANS_ILLUSION_TITLE",
        descKey = "EMPTY_PLANS_ILLUSION_DESC",
        titleFallback = "No illusions to show",
        descFallback = "Add illusions from this tab to your To-Do, or adjust Show Planned / Show Completed.",
    },
    plans_title = {
        titleKey = "EMPTY_PLANS_TITLE_TAB_TITLE",
        descKey = "EMPTY_PLANS_TITLE_TAB_DESC",
        titleFallback = "No titles to show",
        descFallback = "Add titles from this tab to your To-Do, or adjust Show Planned / Show Completed.",
    },
    gear = {
        titleKey = "GEAR_NO_TRACKED_CHARACTERS_TITLE",
        descKey = "GEAR_NO_TRACKED_CHARACTERS_DESC",
        titleFallback = "No tracked characters",
        descFallback = "Log in to a character to start tracking gear.",
    },
    gear_filter = {
        titleKey = "GEAR_FILTER_EMPTY_TITLE",
        descKey = "GEAR_FILTER_EMPTY_DESC",
        titleFallback = "No characters match the level filter",
        descFallback = "Turn off Hide or lower the level threshold using the Hide button above to show characters again.",
    },
    legacy = {
        titleKey = "LEGACY_EMPTY_TITLE",
        descKey = "LEGACY_EMPTY_DESC",
        titleFallback = "No Legacy data yet",
        descFallback = "Legacy progress is read a few seconds after login.\nLog in on WoW Forever to load your Legacy points and challenges.",
    },
    professions = {
        titleFallback = "No profession data",
        descKey = "NO_PROFESSIONS_DATA",
        descFallback = "Open your profession window (default: K) on each character to collect data.",
    },
}

--- Registry icon per empty-state key (Modules/UI/IconRegistry.lua). Keys without an entry keep their atlas,
--- or fall back to the generic "character" icon when they have none.
local EMPTY_STATE_ICON_KEYS = {
    search = "search",
    characters = "character",
    items = "bag", items_inventory = "bag", items_personal = "vault", items_warband = "warband", items_guild = "guild",
    storage = "crate",
    plans = "checklist", plans_active = "checklist", plans_daily_tasks = "calendar",
    plans_achievement = "trophy", plans_mount = "book", plans_pet = "paw", plans_toy = "gift", plans_illusion = "illusion", plans_title = "title",
    reputation = "medal",
    currency = "token",
    pve = "dungeon", pve_vault = "dungeon",
    statistics = "bar_chart",
    collections = "book", collections_recent = "book", collections_mounts = "book", collections_pets = "paw",
    collections_toys = "gift", collections_achievements = "trophy",
    collections_illusions = "illusion", collections_titles = "title",
    gear = "cuirass", gear_filter = "cuirass",
    professions = "anvil",
    legacy = "trophy",
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
    -- Plans To-Do virtual browse: pooled grid cards + the persistent host must be hidden in place, never
    -- reparented to the recycle bin (reparenting the backdrop-heavy cards was the 6-7s freeze).
    if child._wnPlansBrowseKeep then return true end
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
            atlas = opts.atlas or base.atlas,
            titleKey = base.titleKey,
            descKey = base.descKey,
            titleFallback = opts.titleText or base.titleFallback or "No Data",
            descFallback = opts.descText or base.descFallback or "",
        }
    end
    if not config then
        config = {
            titleKey = "NO_DATA",
            descKey = nil,
            titleFallback = "No Data",
            descFallback = "No data available.",
        }
    end

    local atlasForIcon = opts.atlas or config.atlas
    -- Empty states show the addon registry icon (theme tint) for their tab / sub-view instead of a Blizzard atlas.
    local registryIconKey = nil
    if not opts.atlas then
        registryIconKey = EMPTY_STATE_ICON_KEYS[configTabName] or ((not config.atlas) and "character") or nil
    end
    local function ApplyEmptyStateIcon(tex)
        if registryIconKey and ns.UI_SetIcon and ns.UI_SetIcon(tex, registryIconKey) then
            if ns.UI_TrackRegistryIconTint then ns.UI_TrackRegistryIconTint(tex, registryIconKey) end
            return
        end
        if atlasForIcon then
            tex:SetAtlas(atlasForIcon)
        end
    end

    local function ResolveEmptyTitle()
        if opts.titleText then return opts.titleText end
        if config.titleKey and ns.L_GameType then return ns.L_GameType(config.titleKey, config.titleFallback) end
        return (ns.L and config.titleKey and ns.L[config.titleKey]) or config.titleFallback
    end

    local function ResolveEmptyDesc()
        if configTabName == SEARCH_EMPTY_TAB_KEY then
            return BuildSearchEmptyDescription(opts.searchText)
        end
        if opts.descText then return opts.descText end
        if config.descKey and ns.L_GameType then return ns.L_GameType(config.descKey, config.descFallback) end
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
        if card._emptyIcon then
            ApplyEmptyStateIcon(card._emptyIcon)
        end
        if card._emptyTitle then
            card._emptyTitle:SetText(ResolveEmptyStateHex("Dim", HEX.dim) .. ResolveEmptyTitle() .. "|r")
        end
        if card._emptyDesc and descText then
            card._emptyDesc:SetText(ResolveEmptyStateHex("Muted", HEX.dim) .. descText .. "|r")
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
    card._wnReadoptable = true   -- cached + re-adopted: never registry garbage (SectionPool)
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
    ApplyEmptyStateIcon(icon)
    icon:SetAlpha(0.6)
    card._emptyIcon = icon

    -- Title
    local title = FontManager:CreateFontString(contentContainer, UIFontRole("emptyCardTitle"), "OVERLAY")
    title:SetPoint("TOP", iconContainer, "BOTTOM", 0, -20)
    title:SetText(ResolveEmptyStateHex("Dim", HEX.dim) .. ResolveEmptyTitle() .. "|r")
    card._emptyTitle = title

    -- Description
    local desc = FontManager:CreateFontString(contentContainer, UIFontRole("emptyCardBody"), "OVERLAY")
    desc:SetPoint("TOP", title, "BOTTOM", 0, -12)
    desc:SetWidth(380)
    desc:SetJustifyH("CENTER")
    if not descText then
        descText = ResolveEmptyDesc()
    end
    desc:SetText(ResolveEmptyStateHex("Muted", HEX.dim) .. (descText or "") .. "|r")
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

local PLANS_EMPTY_STATE_KEYS = {
    active = "plans_active",
    daily_tasks = "plans_daily_tasks",
}

function ns.UI_ResolvePlansEmptyStateKey(category)
    return PLANS_EMPTY_STATE_KEYS[category] or "plans"
end

function ns.UI_HideAllPlansEmptyStateCards(parent)
    if not parent then return end
    HideEmptyStateCard(parent, "plans")
    HideEmptyStateCard(parent, "plans_active")
    HideEmptyStateCard(parent, "plans_daily_tasks")
    HideEmptyStateCard(parent, "plans_browse")
    HideEmptyStateCard(parent, "plans_achievement")
    local browseCats = { "mount", "pet", "toy", "illusion", "title", "achievement" }
    for i = 1, #browseCats do
        HideEmptyStateCard(parent, "plans_browse_" .. browseCats[i])
    end
end

-- Export empty state helpers
ns.UI_CreateEmptyStateCard = CreateEmptyStateCard
ns.UI_HideEmptyStateCard = HideEmptyStateCard

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
    if (issecretvalue and issecretvalue(q)) or q == "" then
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