--[[
    Warband Nexus - Plans Tab UI
    User-driven goal tracker for mounts, pets, and toys

    WN_FACTORY: Achievement browse root + Vault slot grid use Factory first (`CreateContainer` / `CreateButton`);
    Custom Plan dialogs (reset-cycle toggles / duration +/-) use Factory-backed buttons where `ApplyVisuals`
    borders apply; legacy `BackdropTemplate` path kept when Factory returns nil.
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management

local issecretvalue = issecretvalue

--- Lowercase for search only when the string is safe to touch (Midnight 12.0+).
local function SafeLower(s)
    if issecretvalue and issecretvalue(s) then return "" end
    if not s or s == "" then return "" end
    return s:lower()
end

local function IsSafeDisplayString(s)
    return type(s) == "string" and not (issecretvalue and issecretvalue(s)) and s ~= ""
end

--- Display-safe player name / realm (Midnight: never concatenate secret API strings).
local function SafePlayerName()
    local n = UnitName("player")
    if not n or (issecretvalue and issecretvalue(n)) then return nil end
    return n
end
local function SafeRealmName()
    local r = GetRealmName and GetRealmName()
    if not r or (issecretvalue and issecretvalue(r)) then return nil end
    return r
end

-- Unique AceEvent handler identity for PlansUI
local PlansUIEvents = {}

-- Expand state for the To-Do List rows (mirrors PlansTrackerWindow). Keyed by plan.id so
-- the user's open/closed choices survive across PopulateContent rebuilds.
local expandedPlans = {}

-- Debug print helper
local DebugPrint = ns.DebugPrint
local IsDebugModeEnabled = ns.IsDebugModeEnabled
local ReleasePooledRowsInSubtree = ns.UI_ReleasePooledRowsInSubtree

-- Services
local SearchStateManager = ns.SearchStateManager
local SearchResultsRenderer = ns.SearchResultsRenderer

-- Import shared UI components
local COLORS = ns.UI_COLORS

local function PlanGreenHex()
    local P = ns.PLAN_UI_COLORS
    return (P and P.completed) or (ns.UI_GetSemanticGreenHex and ns.UI_GetSemanticGreenHex()) or "|cff44ff44"
end

local function PlanGoldHex()
    local P = ns.PLAN_UI_COLORS
    return (P and P.progressLabel) or (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffffcc00"
end

local function PlanBrightHex()
    return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function PlanTryCountSuffix(count)
    local triesLabel = (ns.L and ns.L["TRIES"]) or "Tries"
    local labelHex = (ns.UI_GetSemanticInfoHex and ns.UI_GetSemanticInfoHex()) or "|cffaaddff"
    return labelHex .. triesLabel .. ":|r " .. PlanBrightHex() .. tostring(count) .. "|r"
end
ns.UI_FormatPlanTryCountSuffix = PlanTryCountSuffix

local function PlanGreenRgb()
    local P = ns.PLAN_UI_COLORS
    if P and P.completedRgb then
        return P.completedRgb[1], P.completedRgb[2], P.completedRgb[3]
    end
    return (ns.UI_GetSemanticGreenColor and ns.UI_GetSemanticGreenColor()) or 0.27, 1, 0.27
end

local function ControlChromeBackdrop()
    return (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or COLORS.bgCard
end

local CreateCard = ns.UI_CreateCard
local CreateSearchBox = ns.UI_CreateSearchBox
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local HideAllPlansEmptyStateCards = ns.UI_HideAllPlansEmptyStateCards
local ResolvePlansEmptyStateKey = ns.UI_ResolvePlansEmptyStateKey
local CreateResultsContainer = ns.UI_CreateResultsContainer
local CreateIcon = ns.UI_CreateIcon
local ApplyVisuals = ns.UI_ApplyVisuals
--- Skip custom ApplyVisuals on Blizzard template widgets (classic plan editor guards).
--- opts: listHeader | cardPanel | rowTransparent | iconWell | thin (classic routing)
local function ApplyPlansChrome(frame, bg, border, opts)
    if not frame then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then return end
    opts = type(opts) == "table" and opts or {}

    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() and ns.UI.Factory and ns.UI.Factory.ApplyBorder then
        local tier = "thin"
        if opts.listHeader then
            if ns.UI_ApplyClassicListHeaderChrome then
                ns.UI_ApplyClassicListHeaderChrome(frame, bg)
                return
            end
            tier = "panel"
        elseif opts.rowTransparent then
            tier = "none"
        elseif opts.cardPanel or frame._wnClassicCard then
            tier = "card"
        elseif opts.iconWell then
            tier = "iconWell"
        end
        if tier == "card" and not frame._wnClassicCard then
            ns.UI.Factory:ApplyBorder(frame, { tier = tier })
        elseif tier == "iconWell" then
            if ns.UI_ApplyIconWellChrome then
                ns.UI_ApplyIconWellChrome(frame)
            else
                ns.UI.Factory:ApplyBorder(frame, { tier = tier, bgColor = bg })
            end
        else
            ns.UI.Factory:ApplyBorder(frame, { tier = tier, bgColor = bg })
        end
        return
    end

    if not ApplyVisuals then return end
    ApplyVisuals(frame, bg, border)
end
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateExternalWindow = ns.UI_CreateExternalWindow
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local function CreateExpandableRow(parent, width, rowHeight, data, isExpanded, onToggle)
    local fn = ns.UI_CreateExpandableRow
    if not fn then
        error("WarbandNexus: UI_CreateExpandableRow missing (load ExpandableRowFactory before PlansUI)")
    end
    return fn(parent, width, rowHeight, data, isExpanded, onToggle)
end
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local CardLayoutManager = ns.UI_CardLayoutManager
local BuildCollapsibleSectionOpts = ns.UI_BuildCollapsibleSectionOpts

--- Prefer measured parent width over PopulateContent `width` (browse results container is inset).
local function ResolvePlansContentWidth(parent, fallbackWidth)
    if parent and parent.GetWidth then
        local pw = parent:GetWidth()
        if pw and pw > 1 then
            return pw
        end
    end
    return fallbackWidth or 400
end

-- Loading state for collection scanning (per-category)
ns.PlansLoadingState = ns.PlansLoadingState or {
    -- Structure: { mount = { isLoading, loader }, pet = { isLoading, loader }, toy = { isLoading, loader } }
}

-- Cached achievement category tree (GetCategoryList/GetCategoryInfo are static after APIs are ready).
local cachedCategoryTree = nil
local PLANS_ACH_CATEGORY_CACHE_MIN_IDS = 40

function ns.UI_InvalidatePlansAchievementCategoryTree()
    cachedCategoryTree = nil
end
local PlanCardFactory = ns.UI_PlanCardFactory
local FormatNumber = ns.UI_FormatNumber
local FormatTextNumbers = ns.UI_FormatTextNumbers

--- Session cache: achievementID -> { points, numCriteria, criteriaText, criteriaItems, information }
local PLANS_ACHIEVEMENT_CACHE_VERSION = 4

local function PlansAchievementSessionCache()
    if ns._plansAchievementExpandCacheVersion ~= PLANS_ACHIEVEMENT_CACHE_VERSION then
        ns._plansAchievementExpandCache = {}
        ns._plansAchievementExpandCacheVersion = PLANS_ACHIEVEMENT_CACHE_VERSION
    end
    local c = ns._plansAchievementExpandCache
    if not c then
        c = {}
        ns._plansAchievementExpandCache = c
    end
    return c
end

--- Populate once per achievementID per session (Midnight: guard API strings before use).
local function EnsurePlansAchievementExpandCache(achievementID)
    if not achievementID or type(achievementID) ~= "number" then return nil end
    if issecretvalue and issecretvalue(achievementID) then return nil end

    local cache = PlansAchievementSessionCache()
    local existing = cache[achievementID]
    if existing then return existing end

    local entry = {
        points = nil,
        numCriteria = 0,
        criteriaText = nil,
        criteriaItems = nil,
        information = nil,
    }

    local ok, _, _, pointsRaw, _, _, _, _, achDesc = pcall(GetAchievementInfo, achievementID)
    if not ok then
        cache[achievementID] = entry
        return entry
    end

    if achDesc and not (issecretvalue and issecretvalue(achDesc)) and achDesc ~= "" then
        local bodyHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
        entry.information = bodyHex .. achDesc .. "|r"
    end

    local ptsNum = nil
    if not (issecretvalue and issecretvalue(pointsRaw)) then
        ptsNum = tonumber(pointsRaw)
    end
    entry.points = ptsNum or 0

    local numCriteria = (GetAchievementNumCriteria and GetAchievementNumCriteria(achievementID)) or 0
    if issecretvalue and issecretvalue(numCriteria) then
        numCriteria = 0
    end
    numCriteria = tonumber(numCriteria) or 0
    entry.numCriteria = numCriteria

    if numCriteria > 0 then
        local items, summary
        if ns.UI_BuildAchievementCriteriaListItems then
            items, summary = ns.UI_BuildAchievementCriteriaListItems(achievementID)
        else
            items = {}
            summary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(achievementID)
        end
        entry.criteriaItems = items or {}
        if summary and ns.UI_FormatAchievementProgressHeader then
            entry.criteriaText = ns.UI_FormatAchievementProgressHeader(summary)
        end
    end

    cache[achievementID] = entry
    return entry
end
ns.UI_EnsurePlansAchievementExpandCache = EnsurePlansAchievementExpandCache

--- Drop cached criteria text/items so the next paint re-reads live progress (CRITERIA_UPDATE).
--- Without this the entry stayed for the whole session and only /reload showed completed steps.
function ns.UI_InvalidatePlansAchievementExpandCache(achievementID)
    local cache = ns._plansAchievementExpandCache
    if type(cache) ~= "table" then return end
    if type(achievementID) == "number" then
        cache[achievementID] = nil
    else
        wipe(cache)
    end
end

--- Criteria ticked: both the cached criteria text and the cached cards have to go, whether or not
--- a To-Do surface is on screen right now — otherwise opening the window later paints progress
--- captured before the step was completed.
function ns.UI_MarkPlansAchievementCardsDirty()
    ns.UI_InvalidatePlansAchievementExpandCache()
    ns._plansActiveCardEpoch = (ns._plansActiveCardEpoch or 1) + 1
end

--- After expand/collapse, grow scrollChild so SetClipsChildren on the grid does not clip tall cards.
local function ReflowPlansCardLayout(layoutManager)
    if not layoutManager then return end
    local CLM = CardLayoutManager or ns.UI_CardLayoutManager
    if not CLM then return end
    local PCF = PlanCardFactory or ns.UI_PlanCardFactory
    if PCF and PCF.ReflowAllPlanCards then
        PCF:ReflowAllPlanCards(layoutManager)
    else
        CLM:RecalculateAllPositions(layoutManager)
    end
end

function ns.UI_SyncPlansScrollContentHeight(scrollChild)
    if not scrollChild then return end
    local lm = scrollChild._plansCardLayoutManager or scrollChild._plansBrowseLayoutManager
    local CLM = CardLayoutManager or ns.UI_CardLayoutManager
    if not lm or not CLM then return end
    local pad = (ns.UI_GetTabScrollContentBottomPad and ns.UI_GetTabScrollContentBottomPad()) or 12
    local contentBottom = CLM:GetFinalYOffset(lm) + pad
    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local viewportH = (mf and mf.scroll and mf.scroll:GetHeight()) or 0
    if viewportH < 2 and mf and mf.scroll and mf.fixedHeader then
        local fhBot = mf.fixedHeader:GetBottom()
        local sb = mf.scroll:GetBottom()
        if fhBot and sb and fhBot > sb then
            viewportH = fhBot - sb
        end
    end
    local totalScrollH = math.max(contentBottom, viewportH)
    scrollChild:SetHeight(totalScrollH)
    local fill = scrollChild._wnScrollBottomFill
    if fill then
        local slack = totalScrollH - contentBottom
        if slack > 1 then
            fill:ClearAllPoints()
            fill:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, -contentBottom)
            fill:SetPoint("BOTTOMRIGHT", scrollChild, "BOTTOMRIGHT", 0, 0)
            fill:Show()
        else
            fill:ClearAllPoints()
            fill:Hide()
        end
    end
    local sc = mf and mf.scroll
    if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
        local maxV = sc:GetVerticalScrollRange() or 0
        local cur = sc:GetVerticalScroll() or 0
        if cur > maxV then
            sc:SetVerticalScroll(maxV)
        end
    end
    if ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility and mf and mf.scroll then
        ns.UI.Factory:UpdateScrollBarVisibility(mf.scroll)
    end
end

local NormalizeColonLabelSpacing = ns.UI_NormalizeColonLabelSpacing
local format = string.format

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().HEADER_SPACING or GetLayout().headerSpacing or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or GetLayout().betweenSections or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().SIDE_MARGIN or GetLayout().sideMargin or 10
local TOP_MARGIN = GetLayout().TOP_MARGIN or GetLayout().topMargin or 8
local PAGE_STACK = GetLayout().PAGE_STACK

--- Search bar + card grid share this inset inside the Plans scroll body (see ns.UI_PlansContentPadH).
local function PlansContentPadH()
    return (ns.UI_PlansContentPadH and ns.UI_PlansContentPadH()) or SIDE_MARGIN
end

-- Import PLAN_TYPES from PlansManager
local PLAN_TYPES = ns.PLAN_TYPES

-- Category definitions – My Plans always first, rest alphabetical
local CATEGORIES = {
    { key = "active", name = (ns.L and ns.L["CATEGORY_MY_PLANS"]) or "To-Do List", icon = "Interface\\Icons\\INV_Misc_Map_01" },
    { key = "achievement", name = (ns.L and ns.L["CATEGORY_ACHIEVEMENTS"]) or "Achievements", icon = "Interface\\Icons\\Achievement_General" },
    { key = "daily_tasks", name = (ns.L and ns.L["CATEGORY_DAILY_TASKS"]) or "Weekly Progress", icon = "Interface\\Icons\\INV_Misc_Note_06" },
    { key = "illusion", name = (ns.L and ns.L["CATEGORY_ILLUSIONS"]) or "Illusions", iconAtlas = "UpgradeItem-32x32" },
    { key = "mount", name = (ns.L and ns.L["CATEGORY_MOUNTS"]) or "Mounts", iconAtlas = "dragon-rostrum" },
    { key = "pet", name = (ns.L and ns.L["CATEGORY_PETS"]) or "Pets", iconAtlas = "WildBattlePetCapturable" },
    { key = "title", name = (ns.L and ns.L["CATEGORY_TITLES"]) or "Titles", iconAtlas = "poi-legendsoftheharanir" },
    { key = "toy", name = (ns.L and ns.L["CATEGORY_TOYS"]) or "Toys", iconAtlas = "CreationCatalyst-32x32" },
}

-- Module state
local currentCategory = "active"
local currentDailyContentFilter = "midnight"
local searchText = ""
-- Checkbox mirrors (synced from DB each DrawPlansTab; file load can run before AceDB exists)
local showCompleted = false
local showPlanned = false

ns.PlansUI_GetCurrentCategory = function()
    return currentCategory
end

--- Normalize profile booleans (CheckButton uses 1/nil; AceDB may store true/false).
local function ProfileBool(profile, key, default)
    if not profile then return default end
    local v = profile[key]
    if v == true or v == 1 then return true end
    if v == false or v == nil or v == 0 then return false end
    return default
end

local function NormalizeCheckButtonChecked(button)
    if not button then return false end
    local v = button:GetChecked()
    return v == true or v == 1
end

--- Sync session category key (To-Do browse subtabs).
local function ResolvePlansCategoryFromSession()
    local validCat = {}
    for i = 1, #CATEGORIES do
        validCat[CATEGORIES[i].key] = true
    end
    local sc = ns._sessionPlansCategory
    if sc and validCat[sc] then
        currentCategory = sc
    else
        currentCategory = "active"
    end
    return currentCategory
end

--- Show Planned applies only on browse subtabs (Mounts, Pets, etc.), not To-Do List / Weekly Progress.
local function IsPlansPlannedBrowseLocked()
    ResolvePlansCategoryFromSession()
    return currentCategory == "active" or currentCategory == "daily_tasks"
end

--- Update category bar active styling without rebuilding fixed header (sub-tab perf).
local function ApplyPlansCategoryBarActive(categoryBar, activeKey)
    if categoryBar and categoryBar.SetActiveTab then
        categoryBar:SetActiveTab(activeKey)
    end
end

local function CollectScrollChildFrames(parent)
    if not parent or not parent.GetChildren then return {} end
    return { parent:GetChildren() }
end

--- Retail ScrollFrame:SetScrollChild rejects nil; reparent the child before hiding owned inner scroll.
local function DetachOwnedPlansInnerScroll(st, reparentTo)
    if not st or not st._plansAchInnerScroll then return end
    local inner = st._plansAchInnerScroll
    if inner.GetScrollChild then
        local sc = inner:GetScrollChild()
        if sc and sc.SetParent then
            sc:SetParent(reparentTo)
            if reparentTo then
                sc:ClearAllPoints()
            end
        end
    end
    inner:Hide()
end

--- Stop Plans achievement virtual list (outer-scroll hook + visible row pool) before browse category switch.
local function TeardownPlansAchievementBrowse(host)
    if not host then return end
    local st = host._plansAchBrowseState
    if st then
        st._achPopulateGen = -1
        st._plansCategoryGen = -1
        st._achOuterScrollActive = false
        st._achListRefreshVisible = nil
        if ns._plansAchOuterVirtualState == st then
            ns._plansAchOuterVirtualState = nil
        end
        local rowPool = host._plansAchBrowseRowPool
        local visible = st._achVisibleRowFrames
        if visible then
            if not rowPool then
                rowPool = {}
                host._plansAchBrowseRowPool = rowPool
            end
            local headerPool = st._achHeaderPool
            for vi = 1, #visible do
                local v = visible[vi]
                if v and v.frame then
                    v.frame:Hide()
                    v.frame:ClearAllPoints()
                    -- Section headers live in their own pool; mixing them into the row pool would hand a
                    -- collapsible header back to acquireRow as an achievement row.
                    if v.isHeader then
                        if not headerPool then
                            headerPool = {}
                            st._achHeaderPool = headerPool
                        end
                        headerPool[#headerPool + 1] = v.frame
                    else
                        rowPool[#rowPool + 1] = v.frame
                    end
                end
            end
            st._achVisibleRowFrames = {}
        end
        DetachOwnedPlansInnerScroll(st, nil)
        -- State (flat list, header pool, row pool, scroll child) is KEPT: DrawAchievementsTable reuses
        -- it, so a return to the browse costs a rebind instead of rebuilding the whole category tree.
        -- The gen bumps above already stop any in-flight repaint from touching it.
    end
    if host.plansAchBrowseRoot then
        host.plansAchBrowseRoot:Hide()
        host.plansAchBrowseRoot:ClearAllPoints()
    end
end

local function TeardownPlansScrollChildBrowseArtifacts(scrollChild)
    if not scrollChild then return end
    if ns.UI_AchievementBrowse_ResetPopulateBusy then
        ns.UI_AchievementBrowse_ResetPopulateBusy()
    end
    TeardownPlansAchievementBrowse(scrollChild)
    local children = CollectScrollChildFrames(scrollChild)
    for i = 1, #children do
        local child = children[i]
        if child and child ~= scrollChild.emptyStateContainer then
            TeardownPlansAchievementBrowse(child)
        end
    end
    ns._plansAchOuterVirtualState = nil
end

--- Coalesce achievement virtual-row refresh after Plans browse layout (outer scroll metrics).
local function SchedulePlansVisibleSync(refreshFn)
    if type(refreshFn) ~= "function" then return end
    C_Timer.After(0, function()
        if currentCategory ~= "achievement" then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return end
        refreshFn()
    end)
    C_Timer.After(0.05, function()
        if currentCategory ~= "achievement" then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return end
        refreshFn()
    end)
end

local function ReleasePlansScrollBody(parent)
    if not parent then return end
    -- Stop the virtual browse grid from repainting into a torn-down body during the switch.
    if ns._wnBrowseGridState then
        ns._wnBrowseGridState.active = false
    end
    TeardownPlansScrollChildBrowseArtifacts(parent)
    if HideAllPlansEmptyStateCards then
        HideAllPlansEmptyStateCards(parent)
    end
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    local recycleBin = ns.UI_RecycleBin
    local children = CollectScrollChildFrames(parent)
    for i = 1, #children do
        local child = children[i]
        if child and child ~= parent.emptyStateContainer and not child._wnPlansBrowseKeep then
            if ReleasePooledRowsInSubtree then
                ReleasePooledRowsInSubtree(child)
            end
        end
    end
    for i = 1, #children do
        local child = children[i]
        if child and child ~= parent.emptyStateContainer then
            if child._wnPlansBrowseKeep then
                -- Persistent browse host: HIDE it (so it doesn't bleed onto To-Do List / Weekly Progress /
                -- other non-browse categories) but keep it parented + positioned, so its ~50 pooled cards are
                -- never reparented (that reparent was the 6-7s freeze). DrawBrowser re-shows it on return.
                child:Hide()
            elseif child._wnSectionPooled then
                -- Pooled section chrome (Weekly Progress "pln:" keys and other tabs' keys on this scroll
                -- child): hide it in place; the owning view re-binds it on its next paint (2026-10-22).
                child:Hide()
                child:ClearAllPoints()
            elseif ns.UI_SectionPool then
                -- Anything else is garbage: marked so the theme registries drop it.
                ns.UI_SectionPool.Discard(child)
            else
                child:Hide()
                child:ClearAllPoints()
                if recycleBin then
                    child:SetParent(recycleBin)
                end
            end
        end
    end
    parent._plansCardLayoutManager = nil
    parent._plansBrowseLayoutManager = nil
    -- plansAchBrowseRoot / _plansAchBrowseState / _plansAchBrowseRowPool are persistent (see
    -- TeardownPlansAchievementBrowse): dropping them here forced a full category-tree rebuild on
    -- every populate, which is what froze the tab for 1-2s on a single plan add/remove.
    ns._plansAchPopulateGen = (ns._plansAchPopulateGen or 0) + 1
    ns._plansBrowsePaintGen = (ns._plansBrowsePaintGen or 0) + 1
end

ns.TeardownPlansScrollChildBrowseArtifacts = TeardownPlansScrollChildBrowseArtifacts

local RepositionPlansFixedHeader  -- forward declare (defined above DrawPlansTab)

--- Partial To-Do refresh: category bar + scroll body only (no full PopulateContent).
function WarbandNexus:RefreshPlansCategoryBodyOnly(fromCat, toCat)
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return false end
    if not (self.db and self.db.profile and self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false) then
        return false
    end
    local parent = mf.scrollChild
    if not parent or not mf._plansCategoryBar then return false end

    ResolvePlansCategoryFromSession()
    toCat = toCat or currentCategory
    fromCat = fromCat or toCat
    ApplyPlansCategoryBarActive(mf._plansCategoryBar, currentCategory)

    local plannedLocked = IsPlansPlannedBrowseLocked()
    if mf._plansApplyPlannedBrowseLockVisuals then
        mf._plansApplyPlannedBrowseLockVisuals()
    elseif mf._plansPlannedCheckbox then
        mf._plansPlannedCheckbox:SetAlpha(plannedLocked and 0.42 or 1)
        mf._plansPlannedCheckbox:EnableMouse(true)
    end
    if not mf._plansApplyPlannedBrowseLockVisuals and mf._plansPlannedLabel then
        mf._plansPlannedLabel:SetAlpha(plannedLocked and 0.42 or 1)
    end

    -- Search box is fixedHeader chrome: re-place the cached header for the new category (same path as
    -- DrawPlansTab) so the box swaps / hides and the header height follows.
    local hdrCache = mf._plansFixedHeaderCache
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    if hdrCache and hdrCache.titleCard and chrome then
        RepositionPlansFixedHeader(hdrCache, chrome.headerParent, chrome, chrome.yOffset, chrome.side, nil, currentCategory)
    end

    -- To-Do List repaints through the full populate (virtual host + card cache).
    if currentCategory == "active" then
        if self.SendMessage then
            self:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
        end
        return true
    end

    local perfOn = ns.IsTabPerfMonitorEnabled and ns.IsTabPerfMonitorEnabled()
    local wallStart = perfOn and GetTime() or nil
    if perfOn then
        debugprofilestart()
    end

    ReleasePlansScrollBody(parent)

    if mf.scroll and mf.scroll.SetVerticalScroll then
        mf.scroll:SetVerticalScroll(0)
    end

    local width = mf._plansContentWidth
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)
    local yOffset = mf._plansScrollBodyStartY or ((ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8)

    if currentCategory == "daily_tasks" then
        yOffset = self:DrawActivePlans(parent, yOffset, width, currentCategory)
    else
        yOffset = self:DrawBrowser(parent, yOffset, width, currentCategory)
    end

    parent:SetHeight(math.max((yOffset or 0) + PAGE_STACK.BOTTOM_PAD, 1))
    if ns.UI_EnsureMainScrollLayout then
        ns.UI_EnsureMainScrollLayout()
    end
    if perfOn and ns.EmitPartialTabRefreshPerf then
        local bodyMs = debugprofilestop()
        ns.EmitPartialTabRefreshPerf("plans", fromCat, toCat, bodyMs, wallStart)
    end
    return true
end

ns.RefreshPlansCategoryBodyOnly = function()
    if WarbandNexus and WarbandNexus.RefreshPlansCategoryBodyOnly then
        return WarbandNexus:RefreshPlansCategoryBodyOnly()
    end
    return false
end

--- Rebuild the To-Do List virtual model in place: no tab teardown, no chrome redraw. Cards are cached
--- per plan id and only the ones marked dirty are rebuilt, so a membership change costs a reflow.
function ns.PlansUI_RefreshActiveList()
    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return false end
    local parent = mf.scrollChild
    -- Requires a previous paint: the persistent host owns the card cache this path relies on.
    if not parent or not parent._wnPlansActiveHost then return false end
    local width = mf._plansContentWidth
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)
    local yOffset = mf._plansScrollBodyStartY
        or ((ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8)
    local endY = WarbandNexus:DrawActivePlans(parent, yOffset, width, "active")
    parent:SetHeight(math.max((endY or 0) + PAGE_STACK.BOTTOM_PAD, 1))
    if ns.UI_EnsureMainScrollLayout then
        ns.UI_EnsureMainScrollLayout()
    end
    return true
end

--- Incremental WN_PLANS_UPDATED handling: repaint what the changed plan actually touches.
--- Returns true when the delta was absorbed; false means the caller must repopulate the tab.
function ns.PlansUI_ApplyPlanDelta(planID, action)
    local mf = WarbandNexus and WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return false end
    if planID ~= nil then
        ns._plansDirtyCardIds = ns._plansDirtyCardIds or {}
        ns._plansDirtyCardIds[planID] = true
    end

    ResolvePlansCategoryFromSession()
    if currentCategory == "active" then
        return ns.PlansUI_RefreshActiveList()
    end
    if currentCategory == "daily_tasks" then
        -- Weekly Progress cards are not virtualized; let the caller repopulate.
        return false
    end

    -- Browse categories: add/remove only flips one row's planned badge — unless a planned-dependent
    -- filter is on, in which case list membership changed and the model must be rebuilt.
    local profile = WarbandNexus.db and WarbandNexus.db.profile
    if ProfileBool(profile, "plansShowPlanned", false) or ProfileBool(profile, "plansShowCompleted", false) then
        return false
    end
    if currentCategory == "achievement" then
        -- Nothing to repaint: the achievement row that owns the click updates its own To-Do badge in
        -- place (applyAchRowPlanSlots). Re-windowing the list here would release and re-acquire every
        -- visible row for a one-badge change, which reads as a full-list flash.
        return mf.scrollChild and mf.scrollChild._plansAchBrowseState ~= nil
    end
    if ns.UI_UpdateBrowseGridVisibleRange and ns._wnBrowseGridState and ns._wnBrowseGridState.active then
        ns.UI_UpdateBrowseGridVisibleRange(true)
        return true
    end
    return false
end

--- Browse subtabs only: merge collected + uncollected using isPlanned and the two checkboxes.
--- To-Do List / Weekly Progress do not use this — they filter plans in DrawActivePlans (Show Completed only).
local function ClearPlanReminderForBrowseItem(addon, category, itemID)
    if not addon or not itemID or not addon.RemovePlanReminder then return end
    ns._plansBrowseReminderCleared = ns._plansBrowseReminderCleared or {}
    local memoKey = (category or "") .. ":" .. tostring(itemID)
    if ns._plansBrowseReminderCleared[memoKey] then return end
    local plans = addon.db and addon.db.global and addon.db.global.plans
    if not plans then return end
    for _, plan in pairs(plans) do
        if plan and plan.id and plan.type == category then
            local match = false
            if category == "mount" and plan.mountID == itemID then match = true
            elseif category == "pet" and plan.speciesID == itemID then match = true
            elseif category == "toy" and plan.itemID == itemID then match = true
            elseif category == "illusion" and (plan.illusionID == itemID or plan.sourceID == itemID) then match = true
            elseif category == "achievement" and plan.achievementID == itemID then match = true
            elseif category == "title" and plan.titleID == itemID then match = true
            end
            if match then
                local r = plan.reminder
                if r and r.enabled ~= false then
                    if addon:RemovePlanReminder(plan.id) then
                        ns._plansBrowseReminderCleared[memoKey] = true
                    end
                else
                    ns._plansBrowseReminderCleared[memoKey] = true
                end
                return
            end
        end
    end
    ns._plansBrowseReminderCleared[memoKey] = true
end


-- Throttle state for scan progress UI refreshes
local lastUIRefresh = 0

local Browse = ns.PlansUI_Browse
assert(Browse and Browse.Install, "load PlansUI_Browse.lua before PlansUI.lua")
Browse.Install(WarbandNexus, {
    ReflowPlansCardLayout = ReflowPlansCardLayout,
    TeardownPlansAchievementBrowse = TeardownPlansAchievementBrowse,
    DetachOwnedPlansInnerScroll = DetachOwnedPlansInnerScroll,
    ProfileBool = ProfileBool,
    PlansContentPadH = PlansContentPadH,
    GetLayout = GetLayout,
    cachedCategoryTree = function() return cachedCategoryTree end,
    setCachedCategoryTree = function(v) cachedCategoryTree = v end,
    PLANS_ACH_CATEGORY_CACHE_MIN_IDS = PLANS_ACH_CATEGORY_CACHE_MIN_IDS,
})

local WeeklyProgress = ns.PlansUI_WeeklyProgress
assert(WeeklyProgress and WeeklyProgress.Install, "load PlansUI_WeeklyProgress.lua before PlansUI.lua")
WeeklyProgress.Install(WarbandNexus, {
    IsSafeDisplayString = IsSafeDisplayString,
    PlanGreenHex = PlanGreenHex,
    PlanGoldHex = PlanGoldHex,
    PlanBrightHex = PlanBrightHex,
    PlanGreenRgb = PlanGreenRgb,
    ApplyPlansChrome = ApplyPlansChrome,
    GetLayout = GetLayout,
    PAGE_STACK = PAGE_STACK,
    PlansContentPadH = PlansContentPadH,
    CATEGORIES = CATEGORIES,
})

local Dialogs = ns.PlansUI_Dialogs
assert(Dialogs and Dialogs.Install, "load PlansUI_Dialogs.lua before PlansUI.lua")
Dialogs.Install(WarbandNexus, {
    SafePlayerName = SafePlayerName,
    SafeRealmName = SafeRealmName,
    PlanGreenHex = PlanGreenHex,
    ControlChromeBackdrop = ControlChromeBackdrop,
    ApplyPlansChrome = ApplyPlansChrome,
})

-- Source parser: PlansUI_SourceParser.lua

-- MAIN DRAW FUNCTION

--- Reposition cached Plans fixedHeader chrome (Collections/Items parity — WN-PERF tab revisit).
--- Page stack: title BLOCK_GAP sub-tab bar BLOCK_GAP [search BLOCK_GAP]; same Place calls as the create path.
---@param searchCategory string|nil category whose header search box to show (nil = none, e.g. module off)
function RepositionPlansFixedHeader(hdrCache, headerParent, chrome, headerYOffset, contentSide, subtitleTextContent, searchCategory)
    local titleCard = hdrCache.titleCard
    titleCard:SetParent(headerParent)
    titleCard:Show()
    if hdrCache.subtitleText and subtitleTextContent then
        hdrCache.subtitleText:SetText(subtitleTextContent)
    end
    if chrome then
        chrome.yOffset = headerYOffset
        headerYOffset = ns.UI_PageStack_Place(chrome, titleCard)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
        headerYOffset = headerYOffset + titleCard:GetHeight() + PAGE_STACK.BLOCK_GAP
    end
    local categoryBar = hdrCache.categoryBar
    if categoryBar then
        categoryBar:SetParent(headerParent)
        categoryBar:Show()
        ApplyPlansCategoryBarActive(categoryBar, currentCategory)
        if chrome then
            headerYOffset = ns.UI_PageStack_Place(chrome, categoryBar)
        else
            categoryBar:ClearAllPoints()
            categoryBar:SetPoint("TOPLEFT", contentSide, -headerYOffset)
            categoryBar:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
            headerYOffset = headerYOffset + (categoryBar:GetHeight() or PAGE_STACK.SUB_TAB_HEIGHT) + PAGE_STACK.BLOCK_GAP
        end
    end
    if chrome and Browse.PlaceHeaderSearch then
        headerYOffset = Browse.PlaceHeaderSearch(chrome, searchCategory)
    end
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if ns.UI_CommitTabFixedHeader then
        ns.UI_CommitTabFixedHeader(mf, headerYOffset)
    elseif mf and mf.fixedHeader then
        mf.fixedHeader:SetHeight(headerYOffset)
    end
    return headerYOffset
end

function WarbandNexus:DrawPlansTab(parent)
    -- Hide empty state container (will be shown again if needed)
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    -- Hide standardized empty state card
    if ns.UI_HideAllPlansEmptyStateCards then
        ns.UI_HideAllPlansEmptyStateCards(parent)
    elseif HideEmptyStateCard then
        HideEmptyStateCard(parent, "plans")
    end

    -- Default: To-Do List ("active"). Same session: remember last category until /reload.
    ResolvePlansCategoryFromSession()

    -- Warm the browse card pool during idle so the first Mount/Pet/Toy/Title open is instant too
    -- (no-op after the first schedule; skips itself if a browse grid is already live).
    if ns.UI_SchedulePrewarmBrowseGrid then
        ns.UI_SchedulePrewarmBrowseGrid()
    end

    if currentCategory ~= "achievement" then
        ns._plansAchOuterVirtualState = nil
    end

    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local metrics = ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf)
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or 0
    local contentSide = (chrome and chrome.side) or (metrics and metrics.sideMargin) or SIDE_MARGIN
    local width = (metrics and metrics.contentWidth)
        or (ns.UI_ResolveMainTabContentWidth and ns.UI_ResolveMainTabContentWidth(mf, parent))
        or (parent:GetWidth() or 600)
    local scrollTopY = PAGE_STACK.BODY_TOP

    -- Check if module is enabled (early check for buttons)
    local moduleEnabled = self.db.profile.modulesEnabled and self.db.profile.modulesEnabled.plans ~= false
    
    -- Initialize expanded cards state (persist across refreshes)
    if not ns.expandedCards then
        ns.expandedCards = {}
    end
    
    local activePlanCount = self:GetActiveNonDailyIncompleteCount()
    local titleHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
    local collectionPlansLabel = (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List"
    local titleTextContent = titleHex .. collectionPlansLabel .. "|r"
    local plansSubtitle = (ns.L and ns.L["PLANS_SUBTITLE_TEXT"]) or "Track your weekly goals & collections"
    local activePlanText = activePlanCount ~= 1
        and format((ns.L and ns.L["ACTIVE_PLANS_FORMAT"]) or "%d active plans", activePlanCount)
        or format((ns.L and ns.L["ACTIVE_PLAN_FORMAT"]) or "%d active plan", activePlanCount)
    local subtitleTextContent = plansSubtitle .. " • " .. activePlanText
    local tm = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local plansToolbarReserve = (ns.UI_ComputeTitleToolbarReserve and ns.UI_ComputeTitleToolbarReserve({
        tm.actionW or 100,
        tm.actionW or 100,
        tm.actionW or 100,
        ns.UI_GetTitleToolbarPresetWidth and ns.UI_GetTitleToolbarPresetWidth("default") or 80,
        120,
        115,
    })) or 600

    local hdrCache = mf and mf._plansFixedHeaderCache
    local headerChromeDone = false
    if hdrCache and hdrCache.titleCard and hdrCache.categoryBar then
        headerYOffset = RepositionPlansFixedHeader(hdrCache, headerParent, chrome, headerYOffset, contentSide, subtitleTextContent,
            moduleEnabled and currentCategory or nil)
        if mf._plansApplyPlannedBrowseLockVisuals then
            mf._plansApplyPlannedBrowseLockVisuals()
        end
        headerChromeDone = true
    end

    if not headerChromeDone then
    local titleCard, _, _, _, plansSubtitleText = ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "plans",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = plansToolbarReserve,
    })
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end
    
    -- Only show buttons and "Show Completed" checkbox if module is enabled
    if moduleEnabled then
        local prof = self.db and self.db.profile
        if prof then
            showCompleted = ProfileBool(prof, "plansShowCompleted", false)
            showPlanned = ProfileBool(prof, "plansShowPlanned", false)
        end

        local addCustomBtn = ns.UI_CreateTitleToolbarTextButton(titleCard, {
            preset = "action",
            text = (ns.L and ns.L["ADD_CUSTOM"]) or "Add Custom",
            onClick = function()
                self:ShowCustomPlanDialog()
            end,
        })
        if addCustomBtn then
            ns.UI_AnchorTitleToolbarControlRight(titleCard, addCustomBtn)
        end
        self.addCustomBtn = addCustomBtn
        
        local addWeeklyBtn = ns.UI_CreateTitleToolbarTextButton(titleCard, {
            preset = "action",
            text = (ns.L and ns.L["ADD_VAULT"]) or "Add Vault",
            onClick = function()
                self:ShowWeeklyPlanDialog()
            end,
        })
        if addWeeklyBtn and addCustomBtn then
            ns.UI_ChainTitleToolbarControl(titleCard, addWeeklyBtn, addCustomBtn)
        end
        
        local addDailyBtn = ns.UI_CreateTitleToolbarTextButton(titleCard, {
            preset = "action",
            text = (ns.L and ns.L["ADD_QUEST"]) or "Add Quest",
            onClick = function()
                self:ShowDailyPlanDialog()
            end,
            onEnter = function(btn)
                GameTooltip:SetOwner(btn, "ANCHOR_BOTTOM")
                GameTooltip:SetText((ns.L and ns.L["ADD_QUEST"]) or "Add Quest", 1, 1, 1)
                GameTooltip:AddLine((ns.L and ns.L["ADD_QUEST_TOOLTIP"]) or "Track weekly Midnight objectives for this character.", 0.85, 0.85, 0.85, true)
                GameTooltip:Show()
            end,
            onLeave = function() GameTooltip:Hide() end,
        })
        if addDailyBtn and addWeeklyBtn then
            ns.UI_ChainTitleToolbarControl(titleCard, addDailyBtn, addWeeklyBtn)
        end
        local hdrToolbarGap = tm.gap or (GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8)

        -- Checkbox (using shared widget) - Next to Add Quest button
        local checkbox = CreateThemedCheckbox(titleCard, showCompleted)
        if checkbox and checkbox.innerDot and not checkbox._wnBlizzardCheckbox then
            checkbox.innerDot:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        end
        if not checkbox then
            if IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint("|cffff0000WN DEBUG: CreateThemedCheckbox returned nil! titleCard:|r", titleCard)
            end
            return
        end
        
        if IsDebugModeEnabled and IsDebugModeEnabled() then
            if not checkbox.HasScript then
                DebugPrint("|cffff0000WN DEBUG: Checkbox missing HasScript method! Type:|r", checkbox:GetObjectType())
            elseif not checkbox:HasScript("OnClick") then
                DebugPrint("|cffffff00WN DEBUG: Checkbox type", checkbox:GetObjectType(), "doesn't support OnClick|r")
            end
        end
        
        local resetBtn = ns.UI_CreateTitleToolbarTextButton(titleCard, {
            preset = "default",
            text = (ns.L and ns.L["RESET_LABEL"]) or "Reset",
            onClick = function()
                StaticPopupDialogs["WN_RESET_COMPLETED_PLANS"] = {
                    text = (ns.L and ns.L["RESET_COMPLETED_CONFIRM"]) or "Are you sure you want to remove ALL completed plans?\n\nThis cannot be undone!",
                    button1 = (ns.L and ns.L["YES_RESET"]) or "Yes, Reset",
                    button2 = CANCEL or "Cancel",
                    OnAccept = function()
                        if WarbandNexus.ResetCompletedPlans then
                            local count = WarbandNexus:ResetCompletedPlans()
                            WarbandNexus:Print(format((ns.L and ns.L["REMOVED_PLANS_FORMAT"]) or "Removed %d completed plan(s).", count))
                        end
                    end,
                    timeout = 0,
                    whileDead = true,
                    hideOnEscape = true,
                    preferredIndex = 3,
                }
                StaticPopup_Show("WN_RESET_COMPLETED_PLANS")
            end,
            onEnter = function(self)
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText((ns.L and ns.L["REMOVE_COMPLETED_TOOLTIP"]) or "Remove all completed plans from your My Plans list. This will delete all completed custom plans and remove completed mounts/pets/toys from your plans. This action cannot be undone!", 1, 1, 1, 1)
                GameTooltip:Show()
            end,
            onLeave = function() GameTooltip:Hide() end,
        })
        if resetBtn and addDailyBtn then
            ns.UI_ChainTitleToolbarControl(titleCard, resetBtn, addDailyBtn)
        end

        -- Checkbox (left of Reset button)
        if resetBtn then
            if ns.UI_AnchorTitleCardToolbarControl then
                ns.UI_AnchorTitleCardToolbarControl(checkbox, titleCard, resetBtn, "LEFT", -hdrToolbarGap)
            else
                checkbox:SetPoint("RIGHT", resetBtn, "LEFT", -hdrToolbarGap, 0)
            end
        end
        
        -- Add text label for "Show Completed" checkbox (left of checkbox)
        local checkboxLabel = FontManager:CreateFontString(titleCard, "body", "OVERLAY")
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(checkboxLabel, titleCard, checkbox, "LEFT", -hdrToolbarGap)
        else
            checkboxLabel:SetPoint("RIGHT", checkbox, "LEFT", -hdrToolbarGap, 0)
        end
        checkboxLabel:SetText((ns.L and ns.L["SHOW_COMPLETED"]) or "Show Completed")
        ns.UI_SetTextColorRole(checkboxLabel, "Normal")
        
        -- Override OnClick to add filtering (with safety check)
        local originalOnClick = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnClick") end)
            if success then
                originalOnClick = result
            elseif IsDebugModeEnabled and IsDebugModeEnabled() then
                DebugPrint("WarbandNexus DEBUG: GetScript('OnClick') failed for checkbox:", result)
            end
        end
        checkbox:SetScript("OnClick", function(self)
            if originalOnClick then originalOnClick(self) end
            showCompleted = NormalizeCheckButtonChecked(self)
            -- Save to DB
            if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile then
                WarbandNexus.db.profile.plansShowCompleted = showCompleted
            end
            -- Refresh UI to apply filter
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
        end)
        
        -- Add tooltip (keep border hover effect from shared widget)
        local originalOnEnter = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnEnter") end)
            if success then
                originalOnEnter = result
            end
        end
        checkbox:SetScript("OnEnter", function(self)
            if originalOnEnter then originalOnEnter(self) end
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText((ns.L and ns.L["SHOW_COMPLETED"]) or "Show Completed", 1, 1, 1)
            GameTooltip:AddLine((ns.L and ns.L["SHOW_COMPLETED_HELP"]) or "To-Do List and Weekly Progress: unchecked = plans still in progress; checked = completed plans only. Browse tabs: unchecked = uncollected browse (optionally only To-Do items if Show Planned is on); checked = include collected To-Do entries.", 0.75, 0.75, 0.75, true)
            GameTooltip:Show()
        end)
        
        local originalOnLeave = nil
        if checkbox and checkbox.GetScript then
            local success, result = pcall(function() return checkbox:GetScript("OnLeave") end)
            if success then
                originalOnLeave = result
            end
        end
        checkbox:SetScript("OnLeave", function(self)
            if originalOnLeave then originalOnLeave(self) end
            GameTooltip:Hide()
        end)
        
        -- "Show Planned" only affects browse subtabs; dimmed on To-Do / Weekly Progress but always toggleable.
        local plannedCheckbox, plannedLabel
        plannedCheckbox = CreateThemedCheckbox(titleCard, showPlanned)
        if plannedCheckbox then
            if plannedCheckbox.innerDot and not plannedCheckbox._wnBlizzardCheckbox then
                plannedCheckbox.innerDot:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
            end
            if ns.UI_AnchorTitleCardToolbarControl then
                ns.UI_AnchorTitleCardToolbarControl(plannedCheckbox, titleCard, checkboxLabel, "LEFT", -hdrToolbarGap)
            else
                plannedCheckbox:SetPoint("RIGHT", checkboxLabel, "LEFT", -hdrToolbarGap, 0)
            end

            plannedLabel = FontManager:CreateFontString(titleCard, "body", "OVERLAY")
            if ns.UI_AnchorTitleCardToolbarControl then
                ns.UI_AnchorTitleCardToolbarControl(plannedLabel, titleCard, plannedCheckbox, "LEFT", -hdrToolbarGap)
            else
                plannedLabel:SetPoint("RIGHT", plannedCheckbox, "LEFT", -hdrToolbarGap, 0)
            end
            plannedLabel:SetText((ns.L and ns.L["SHOW_PLANNED"]) or "Show Planned")
            ns.UI_SetTextColorRole(plannedLabel, "Normal")

            local function ApplyPlannedBrowseLockVisuals()
                local dim = IsPlansPlannedBrowseLocked() and 0.42 or 1
                plannedCheckbox:SetAlpha(dim)
                plannedLabel:SetAlpha(dim)
                plannedCheckbox:EnableMouse(true)
            end
            ApplyPlannedBrowseLockVisuals()

            if mf then
                mf._plansPlannedCheckbox = plannedCheckbox
                mf._plansPlannedLabel = plannedLabel
                mf._plansApplyPlannedBrowseLockVisuals = ApplyPlannedBrowseLockVisuals
            end

            local origPlannedOnClick = nil
            if plannedCheckbox.GetScript then
                local ok2, res2 = pcall(function() return plannedCheckbox:GetScript("OnClick") end)
                if ok2 then origPlannedOnClick = res2 end
            end

            local function ToggleShowPlannedFromControl(checkboxFrame)
                if origPlannedOnClick then origPlannedOnClick(checkboxFrame) end
                showPlanned = NormalizeCheckButtonChecked(checkboxFrame)
                if WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile then
                    WarbandNexus.db.profile.plansShowPlanned = showPlanned
                end
                if not IsPlansPlannedBrowseLocked() then
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
                end
            end

            plannedCheckbox:SetScript("OnClick", function(self)
                ToggleShowPlannedFromControl(self)
            end)

            local origPlannedEnter = nil
            if plannedCheckbox.GetScript then
                local ok3, res3 = pcall(function() return plannedCheckbox:GetScript("OnEnter") end)
                if ok3 then origPlannedEnter = res3 end
            end
            local function ShowPlannedTooltip(owner)
                if origPlannedEnter then origPlannedEnter(owner) end
                GameTooltip:SetOwner(owner, "ANCHOR_TOP")
                GameTooltip:SetText((ns.L and ns.L["SHOW_PLANNED"]) or "Show Planned", 1, 1, 1)
                if IsPlansPlannedBrowseLocked() then
                    GameTooltip:AddLine((ns.L and ns.L["SHOW_PLANNED_DISABLED_HERE"]) or "Does not filter the To-Do List or Weekly Progress. Toggle saves your preference for Mounts, Pets, Toys, and other browse tabs.", 0.72, 0.72, 0.76, true)
                else
                    GameTooltip:AddLine((ns.L and ns.L["SHOW_PLANNED_HELP"]) or "Browse tabs only: limit the list to items on your To-Do. Pair with Show Completed for still-needed vs already-finished planned items.", 0.75, 0.75, 0.75, true)
                end
                GameTooltip:Show()
            end
            plannedCheckbox:SetScript("OnEnter", ShowPlannedTooltip)

            local origPlannedLeave = nil
            if plannedCheckbox.GetScript then
                local ok4, res4 = pcall(function() return plannedCheckbox:GetScript("OnLeave") end)
                if ok4 then origPlannedLeave = res4 end
            end
            plannedCheckbox:SetScript("OnLeave", function(self)
                if origPlannedLeave then origPlannedLeave(self) end
                GameTooltip:Hide()
            end)
        end

    end

    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    -- Check if module is disabled (before showing controls)
    if not moduleEnabled then
        titleCard:Show()
        if chrome then
            headerYOffset = ns.UI_PageStack_Place(chrome, titleCard)
        else
            headerYOffset = headerYOffset + titleCard:GetHeight() + PAGE_STACK.BLOCK_GAP
        end
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) elseif fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, scrollTopY, (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List")
        return scrollTopY + cardHeight
    end

    titleCard:Show()
    if chrome then
        headerYOffset = ns.UI_PageStack_Place(chrome, titleCard)
    else
        headerYOffset = headerYOffset + titleCard:GetHeight() + PAGE_STACK.BLOCK_GAP
    end
    if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) elseif fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    
    local maxWidth = (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
        or math.max(200, (parent:GetWidth() or 600) - (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin() or 12) * 2)

    local plansSubTabs = {}
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
        plansSubTabs[i] = {
            key = cat.key,
            label = cat.name,
            icon = cat.icon,
            iconAtlas = cat.iconAtlas,
        }
    end

    local categoryBar = ns.UI_CreateSubTabBar and ns.UI_CreateSubTabBar(headerParent, {
        tabs = plansSubTabs,
        activeKey = currentCategory,
        accent = COLORS.accent,
        wrapRows = true,
        maxWidth = maxWidth,
        onSelect = function(catKey)
            if currentCategory == catKey then return end
            local fromCat = currentCategory
            currentCategory = catKey
            ns._sessionPlansCategory = catKey
            if ns.UI_ClearPlansCategorySearches then
                ns.UI_ClearPlansCategorySearches()
            end
            searchText = ""
            ns._plansCategoryBodyGen = (ns._plansCategoryBodyGen or 0) + 1
            local bodyGen = ns._plansCategoryBodyGen
            C_Timer.After(0, function()
                if not WarbandNexus then return end
                if ns._plansCategoryBodyGen ~= bodyGen then return end
                if not (WarbandNexus.RefreshPlansCategoryBodyOnly and WarbandNexus:RefreshPlansCategoryBodyOnly(fromCat, catKey)) then
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
                    end
                end
            end)
        end,
    })
    if mf then
        mf._plansCategoryBar = categoryBar
    end
    if categoryBar and chrome then
        headerYOffset = ns.UI_PageStack_Place(chrome, categoryBar)
    elseif categoryBar then
        categoryBar:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        categoryBar:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
        headerYOffset = headerYOffset + (categoryBar:GetHeight() or PAGE_STACK.SUB_TAB_HEIGHT) + PAGE_STACK.BLOCK_GAP
    end

    if mf then
        mf._plansFixedHeaderCache = {
            titleCard = titleCard,
            subtitleText = plansSubtitleText,
            categoryBar = categoryBar,
        }
    end
    -- Search row (cached per category on _plansFixedHeaderCache.searchBoxes; hidden on Weekly Progress).
    if chrome and Browse.PlaceHeaderSearch then
        headerYOffset = Browse.PlaceHeaderSearch(chrome, currentCategory)
    end

    if ns.UI_CommitTabFixedHeader then
        ns.UI_CommitTabFixedHeader(mf, headerYOffset)
    elseif fixedHeader then
        fixedHeader:SetHeight(headerYOffset)
    end
    end -- not headerChromeDone

    if not moduleEnabled then
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) elseif fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, scrollTopY, (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List")
        return scrollTopY + cardHeight
    end

    -- One-time event registration (following CurrencyUI pattern)
    if not self._plansEventRegistered then
        local Constants = ns.Constants

        if Constants.EVENTS.PLANS_BROWSE_COLLECTION_ENSURE_REQUESTED then
            WarbandNexus.RegisterMessage(PlansUIEvents, Constants.EVENTS.PLANS_BROWSE_COLLECTION_ENSURE_REQUESTED, function(_, payload)
                local cat = payload and payload.category
                if cat and ns.RequestPlansBrowseCollectionEnsure then
                    ns.RequestPlansBrowseCollectionEnsure(cat)
                end
            end)
        end

        if Constants and Constants.EVENTS then
            WarbandNexus.RegisterMessage(PlansUIEvents, Constants.EVENTS.COLLECTION_SCAN_PROGRESS, function(_, data)
                if not self:IsStillOnTab("plans") then return end
                local scanCategory = data and data.category
                if currentCategory == "active" or currentCategory == "daily_tasks" then
                    if scanCategory and scanCategory ~= currentCategory then return end
                elseif scanCategory and scanCategory ~= currentCategory and scanCategory ~= "all" and scanCategory ~= "build" then
                    return
                end
                local collLoading = ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading
                local catLoading = scanCategory and ns.PlansLoadingState and ns.PlansLoadingState[scanCategory]
                    and ns.PlansLoadingState[scanCategory].isLoading
                if not collLoading and not catLoading then return end
                local progress = tonumber(data and data.progress) or 0
                local scanKey = scanCategory or "all"
                local milestone = progress >= 100 and 100 or (math.floor(progress / 25) * 25)
                if milestone <= (ns._plansBrowseScanUIMilestone[scanKey] or -1) then return end
                ns._plansBrowseScanUIMilestone[scanKey] = milestone
                local now = GetTime()
                if (now - lastUIRefresh) < 1.5 then return end
                lastUIRefresh = now
                C_Timer.After(0.05, function()
                    if self:IsStillOnTab("plans") then
                        WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans" })
                    end
                end)
            end)

            WarbandNexus.RegisterMessage(PlansUIEvents, Constants.EVENTS.COLLECTION_SCAN_COMPLETE, function(_, data)
                local cat = data and data.category
                if cat and ns._plansBrowseCollectionEnsurePending then
                    ns._plansBrowseCollectionEnsurePending[cat] = nil
                end
                if cat and ns._plansBrowseScanUIMilestone then
                    ns._plansBrowseScanUIMilestone[cat] = nil
                end
                ns._plansBrowseScanUIMilestone.all = nil
                ns._plansBrowseScanUIMilestone.build = nil
                if not cat or cat == "achievement" or cat == "all" then
                    if ns.UI_InvalidateAchievementCategoryCaches then
                        ns.UI_InvalidateAchievementCategoryCaches()
                    elseif ns.UI_InvalidatePlansAchievementCategoryTree then
                        ns.UI_InvalidatePlansAchievementCategoryTree()
                    end
                end
            end)
        end

        self._plansEventRegistered = true
    end

    if mf then
        mf._plansScrollBodyStartY = scrollTopY
        mf._plansContentWidth = width
    end

    local function PaintPlansScrollBody()
        -- Search lives in the fixedHeader (Browse.PlaceHeaderSearch): body starts at BODY_TOP.
        local bodyY = scrollTopY
        if currentCategory == "active" or currentCategory == "daily_tasks" then
            bodyY = self:DrawActivePlans(parent, bodyY, width, currentCategory)
        else
            bodyY = self:DrawBrowser(parent, bodyY, width, currentCategory)
        end
        return bodyY + PAGE_STACK.BOTTOM_PAD
    end

    if parent._preparedByPopulate and not parent._plansBodyDeferScheduled then
        parent._plansBodyDeferScheduled = true
        local deferGen = mf and mf._tabSwitchGen or 0
        local deferParent = parent
        C_Timer.After(0, function()
            deferParent._plansBodyDeferScheduled = nil
            if not mf or mf.currentTab ~= "plans" or mf._tabSwitchGen ~= deferGen then return end
            local endY = PaintPlansScrollBody()
            if ns.UI_SyncMainTabScrollChrome then
                ns.UI_SyncMainTabScrollChrome(mf, deferParent, endY)
            end
        end)
        if ns.UI_SyncMainTabScrollChrome then
            ns.UI_SyncMainTabScrollChrome(mf, parent, scrollTopY + 80)
        end
        return scrollTopY + 80
    end

    return PaintPlansScrollBody()
end

-- ACTIVE PLANS DISPLAY

-- Weekly Progress view (DrawDailyTasksView): PlansUI_WeeklyProgress.lua

function WarbandNexus:DrawActivePlans(parent, yOffset, width, category)
    if HideAllPlansEmptyStateCards then
        HideAllPlansEmptyStateCards(parent)
    end
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    -- To-Do List / Weekly Progress are not browse categories: hide the persistent browse grid host so its
    -- cards don't bleed on top of this content. It stays parented (no reparent storm); DrawBrowser re-shows
    -- it on return to a browse sub-tab. Also silence the virtual grid scroll hook.
    if parent._wnPlansBrowsePersistent then
        parent._wnPlansBrowsePersistent:Hide()
    end
    if ns._wnBrowseGridState then
        ns._wnBrowseGridState.active = false
    end
    -- Hide the active-list virtual host up front so the daily_tasks (Weekly Progress) path never shows it;
    -- the "active" (To-Do List) path re-shows it below after (re)building its virtual grid.
    if parent._wnPlansActiveHost then
        parent._wnPlansActiveHost:Hide()
    end

    local plans
    if category == "daily_tasks" then
        plans = {}
        if self.db and self.db.global then
            if self.db.global.plans then
                local p = self.db.global.plans
                for i = 1, #p do
                    local plan = p[i]
                    if plan.type == "daily_quests" then
                        plans[#plans + 1] = plan
                    end
                end
            end
            if self.db.global.customPlans then
                local c = self.db.global.customPlans
                for i = 1, #c do
                    local plan = c[i]
                    if plan.type == "daily_quests" then
                        plans[#plans + 1] = plan
                    end
                end
            end
        end
    else
        plans = self:GetActivePlans()
    end
    
    -- Apply search filter (My Plans global search, skip for daily_tasks)
    if category ~= "daily_tasks" then
        local activeSearch = ns._plansActiveSearch
        if activeSearch and not (issecretvalue and issecretvalue(activeSearch)) and activeSearch ~= "" then
            local query = activeSearch:lower()
            local searchFiltered = {}
            for i = 1, #plans do
                local plan = plans[i]
                local resolvedName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ""
                local name = SafeLower(resolvedName)
                local source = SafeLower(plan.resolvedSource or plan.source or "")
                local ptype = SafeLower(plan.type or "")
                if name:find(query, 1, true) or source:find(query, 1, true) or ptype:find(query, 1, true) then
                    searchFiltered[#searchFiltered + 1] = plan
                end
            end
            plans = searchFiltered
        end
    end

    -- Sort plans: Weekly Progress (daily quests) first, then Great Vault, then others
    local typePriority = { daily_quests = 1, weekly_vault = 2 }
    table.sort(plans, function(a, b)
        local pa = typePriority[a.type] or 99
        local pb = typePriority[b.type] or 99
        if pa ~= pb then return pa < pb end
        local aID = tonumber(a.id) or 0
        local bID = tonumber(b.id) or 0
        return aID < bID
    end)

    -- To-Do List & Weekly Progress: list is already only saved plans. Show Planned is ignored here (browse only).
    -- Show Completed off = in-progress plans only; on = completed plans only.
    local profile = WarbandNexus and WarbandNexus.db and WarbandNexus.db.profile
    local showCompletedNow = ProfileBool(profile, "plansShowCompleted", false)
    local filteredPlans = {}
    local planCompleteMemo = {}
    local function memoIsActivePlanComplete(plan)
        local v = planCompleteMemo[plan]
        if v ~= nil then return v end
        v = self:IsActivePlanComplete(plan)
        planCompleteMemo[plan] = v
        return v
    end
    for i = 1, #plans do
        local plan = plans[i]
        local isComplete = memoIsActivePlanComplete(plan)
        local include = (showCompletedNow and isComplete) or ((not showCompletedNow) and (not isComplete))
        if include then
            filteredPlans[#filteredPlans + 1] = plan
        end
    end
    plans = filteredPlans

    -- 2-column layout: count of "regular" plans before each index (excludes weekly_vault / daily_quests).
    -- Precompute O(n) instead of O(n²) inner loop per card.
    local regularCountBefore = {}
    do
        local rc = 0
        for idx = 1, #plans do
            regularCountBefore[idx] = rc
            local pt = plans[idx].type
            if pt ~= "weekly_vault" and pt ~= "daily_quests" then
                rc = rc + 1
            end
        end
    end

    if category == "daily_tasks" then
        parent._plansCardLayoutManager = nil
        return self:DrawDailyTasksView(parent, yOffset, width, plans)
    end
    
    if #plans == 0 then
        parent._plansCardLayoutManager = nil
        local emptyKey = ResolvePlansEmptyStateKey(category)
        if ns.UI_ShowTabEmptyStateCard then
            return ns.UI_ShowTabEmptyStateCard(parent, emptyKey, yOffset, { fillParent = false, sideInset = PAGE_STACK.SIDE })
        end
        local _, height = CreateEmptyStateCard(parent, emptyKey, yOffset, { fillParent = false, sideInset = PAGE_STACK.SIDE })
        return yOffset + height
    end
    
    local PCM = ns.UI_PLANS_CARD_METRICS
    local gridW = ResolvePlansContentWidth(parent, width)
    local cardWidth, cardSpacing, gridPadH
    if ns.UI_PlansCardGridLayout then
        cardWidth, cardSpacing, gridPadH = ns.UI_PlansCardGridLayout(gridW, 2)
    else
        cardSpacing = (PCM and PCM.todoListCardGap) or 10
        gridPadH = PlansContentPadH()
        cardWidth = ns.UI_PlansCardGridColumnWidth(gridW) or 200
    end
    local todoHeaderH = ns.UI_PlansTodoExpandableHeaderHeight and ns.UI_PlansTodoExpandableHeaderHeight(gridW) or 63
    
    if not CardLayoutManager or not CardLayoutManager.Create then
        return yOffset + 10
    end

    -- Initialize CardLayoutManager for dynamic card positioning
    local layoutManager = CardLayoutManager:Create(parent, 2, cardSpacing, yOffset)
    layoutManager.padH = gridPadH
    -- Always point at the active layout: PopulateContent rebuilds cards but OnSizeChanged is only hooked once;
    -- a stale closure capture would RefreshLayout the wrong (old) instance and corrupt positions after resize/scroll.
    parent._plansCardLayoutManager = layoutManager
    parent._plansBrowseLayoutManager = nil
    if parent.SetClipsChildren then
        parent:SetClipsChildren(false)
    end

    -- Chunked paint: render a few cards per frame so Show Completed (which can reveal a large completed
    -- set) never blocks a single frame on the heavy backdrop first-render. Bounded continuation + a
    -- generation guard, per the CLAUDE.md heavy-tab-first-paint rule (mirrors the old browse pump).
    -- Create (once) + position the card for plan index `i` at explicit (cardX, cardY) inside `host`.
    -- Returns the card. Virtualization owns positioning + recycle; no CardLayoutManager here.
    local function renderActivePlanCard(i, host, cardX, cardY, onExpandReflow)
        local plan = plans[i]
        local progress = self:GetResolvedPlanProgress(plan)
        host = host or parent

        if plan.type == "weekly_vault" then
            local weeklyCardHeight = (ns.UI_MeasureFullWidthPlanCardHeight and ns.UI_MeasureFullWidthPlanCardHeight(plan, gridW)) or 174

            -- Create raw card (no base card - weekly vault is fully custom)
            local card = CreateCard(host, weeklyCardHeight)
            card:EnableMouse(true)

            -- Full-width positioning at the virtual slot.
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", host, "TOPLEFT", gridPadH, -(cardY or 0))
            card:SetPoint("TOPRIGHT", host, "TOPRIGHT", -gridPadH, -(cardY or 0))

            card._layoutInfo = card._layoutInfo or {}
            card._layoutInfo.isFullWidth = true
            card._layoutInfo.yPos = cardY or 0

            -- Apply accent border (My Plans cards)
            if ApplyPlansChrome then
                local borderColor = (ns.UI_GetPanelCardBorder and ns.UI_GetPanelCardBorder())
                    or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
                ApplyPlansChrome(card, COLORS.bgCard, borderColor, { cardPanel = true })
            end

            -- Create weekly vault content via factory
            PlanCardFactory:CreateWeeklyVaultCard(card, plan, progress, nil)

            card:Show()
            return card

        elseif plan.type == "daily_quests" then
            local questCardHeight = (ns.UI_MeasureFullWidthPlanCardHeight and ns.UI_MeasureFullWidthPlanCardHeight(plan, gridW)) or 174

            local card = CreateCard(host, questCardHeight)
            card:EnableMouse(true)

            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", host, "TOPLEFT", gridPadH, -(cardY or 0))
            card:SetPoint("TOPRIGHT", host, "TOPRIGHT", -gridPadH, -(cardY or 0))

            card._layoutInfo = card._layoutInfo or {}
            card._layoutInfo.isFullWidth = true
            card._layoutInfo.yPos = cardY or 0

            if ApplyPlansChrome then
                local borderColor = (ns.UI_GetPanelCardBorder and ns.UI_GetPanelCardBorder())
                    or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
                ApplyPlansChrome(card, COLORS.bgCard, borderColor, { cardPanel = true })
            end

            PlanCardFactory:CreateDailyQuestCard(card, plan)

            card:Show()
            return card

        else
            local listCardWidth = cardWidth
            local planComplete = memoIsActivePlanComplete(plan)

            local PCF = ns.UI_PlanCardFactory
            local typeAtlas = PCF and PCF.TYPE_ICONS and PCF.TYPE_ICONS[plan.type]
            local typeNames = PCF and PCF.TYPE_NAMES
            local resolvedName = (self.GetResolvedPlanName and self:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
            local resolvedIcon = (self.GetResolvedPlanIcon and self:GetResolvedPlanIcon(plan)) or plan.iconAtlas or plan.icon
            local iconIsAtlas = false
            if plan.iconAtlas then iconIsAtlas = true
            elseif plan.type == "custom" and plan.icon and plan.icon ~= "" then iconIsAtlas = true
            elseif type(resolvedIcon) == "string" and ns.Utilities and ns.Utilities.IsAtlasName and ns.Utilities:IsAtlasName(resolvedIcon) then iconIsAtlas = true
            end
            if not resolvedIcon or resolvedIcon == "" then resolvedIcon = "Interface\\Icons\\INV_Misc_QuestionMark" end

            local isExpanded = expandedPlans[plan.id] or false
            if plan.type ~= "achievement" then
                isExpanded = false
                expandedPlans[plan.id] = false
            end
            local titleStr = FormatTextNumbers(resolvedName)
            local achievementPoints, information, criteriaItems, criteriaText, criteriaHeader
            local achievementOnExpandPopulate = nil

            local collectibleID = self.GetPlanCollectibleID and self:GetPlanCollectibleID(plan)
            local trySuffix = ""
            if collectibleID and self.ShouldShowTryCountInUI and self:ShouldShowTryCountInUI(plan.type, collectibleID)
                and WarbandNexus.GetTryCount then
                local count = WarbandNexus:GetTryCount(plan.type, collectibleID) or 0
                local triesLabel = (ns.L and ns.L["TRIES"]) or "Tries"
                trySuffix = PlanTryCountSuffix(count)
            end

            local allSourceItems = ns.UI_BuildPlanCriteriaItemsAll and ns.UI_BuildPlanCriteriaItemsAll(plan)
                or (ns.UI_BuildPlanCriteriaItems and ns.UI_BuildPlanCriteriaItems(plan)) or {}
            local summaryMax = 2
            local summaryLines = ns.UI_BuildPlanTodoSummaryLines and ns.UI_BuildPlanTodoSummaryLines(plan, { maxLines = summaryMax }) or {}
            local achSummary = nil

            if plan.type == "achievement" and plan.achievementID then
                local achID = plan.achievementID
                achSummary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(achID)
                local entry = EnsurePlansAchievementExpandCache(achID)
                achievementPoints = ns.UI_ResolveAchievementPlanPoints and ns.UI_ResolveAchievementPlanPoints(plan, entry) or 0
                criteriaHeader = false
                local allowExpand = ns.UI_ShouldAchievementTodoExpand and ns.UI_ShouldAchievementTodoExpand(achSummary)
                if not allowExpand then
                    isExpanded = false
                    expandedPlans[plan.id] = false
                end
                if isExpanded and allowExpand then
                    criteriaItems = entry.criteriaItems
                end
                achievementOnExpandPopulate = function(data)
                    if not (ns.UI_ShouldAchievementTodoExpand and ns.UI_ShouldAchievementTodoExpand(achSummary)) then
                        return
                    end
                    local e = EnsurePlansAchievementExpandCache(achID)
                    data.information = nil
                    data.hideExpandedDescription = true
                    data.criteria = nil
                    data.criteriaData = e.criteriaItems
                    data.criteriaShowHeader = false
                    data.criteriaSectionLabel = nil
                    data.summaryInHeader = true
                end
            else
                if plan.type == "custom" then
                    local d = ns.UI_GetCustomPlanBodyText and ns.UI_GetCustomPlanBodyText(plan)
                    if d then information = d end
                end
                criteriaItems = isExpanded and allSourceItems or {}
                criteriaHeader = false
                if not achievementOnExpandPopulate then
                    achievementOnExpandPopulate = function(data)
                        local all = ns.UI_BuildPlanCriteriaItemsAll and ns.UI_BuildPlanCriteriaItemsAll(plan) or {}
                        if #all > 1 then
                            local rest = {}
                            for si = 2, #all do
                                rest[#rest + 1] = all[si]
                            end
                            data.criteriaData = rest
                        else
                            data.criteriaData = all
                        end
                        data.criteriaShowHeader = false
                        data.summaryInHeader = true
                    end
                end
            end

            local canExpand = false
            if plan.type == "achievement" and plan.achievementID then
                canExpand = achSummary and ns.UI_ShouldAchievementTodoExpand and ns.UI_ShouldAchievementTodoExpand(achSummary) or false
            end

            local typeBadgeSz = (ns.UI_PlansHeaderActionSize and ns.UI_PlansHeaderActionSize())
                or (PCM and PCM.todoTypeBadgeSize) or 24
            local ACTION_SIZE, ACTION_GAP = typeBadgeSz, 4
            local ACTION_EDGE = (ns.UI_IsClassicMode and ns.UI_IsClassicMode()
                and (PCM and PCM.classicTodoActionRightInset) or 10) or 6
            local titleRightInset = ACTION_EDGE + ACTION_SIZE + ACTION_GAP
            if plan.type == "achievement" and plan.achievementID then
                titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP
            end
            if not planComplete and PlanCardFactory.CreateReminderAlertButton then
                titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP
            end
            if plan.type == "custom" then
                titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP
            end
            if trySuffix ~= "" then
                titleRightInset = titleRightInset + ((PCM and PCM.todoMetaRightReserve) or 76)
            end

            -- One grid height for all unified cards (reserve points + summary slots so mounts align with achievements).
            local collapsedH = (ns.UI_PlansTodoFixedCollapsedHeight and ns.UI_PlansTodoFixedCollapsedHeight(true))
                or todoHeaderH
            -- Guard: CreateExpandableRow fires onSectionResize synchronously while applying the initial
            -- expanded geometry (ExpandableRowFactory ApplyRowExpandedGeometry) BEFORE this card is cached.
            -- Reflowing then re-enters buildSlotCard for the same uncached slot -> infinite recursion /
            -- stack overflow. Suppress the construction-time resize; the post-create reconcile pass in
            -- updateVisible already fixes the true expanded height. Only real (post-build) toggles reflow.
            local rowBuilt = false
            local rowData = {
                todoUnifiedHeader = true,
                summaryInHeader = true,
                canExpand = canExpand,
                icon = resolvedIcon,
                iconIsAtlas = iconIsAtlas,
                iconSize = (PCM and PCM.todoUnifiedIconSize) or (PCM and PCM.todoIconSize) or 40,
                typeAtlas = (plan.type ~= "achievement") and typeAtlas or nil,
                typeBadgeSize = (PCM and PCM.todoTypeBadgeSize) or 24,
                achievementPoints = achievementPoints,
                title = titleStr,
                summaryLines = summaryLines,
                metaRightText = (trySuffix ~= "") and trySuffix or nil,
                collapsedHeight = collapsedH,
                information = (plan.type ~= "achievement") and information or nil,
                hideExpandedDescription = (plan.type == "achievement") or nil,
                criteria = criteriaText,
                criteriaData = criteriaItems,
                criteriaColumns = 2,
                criteriaShowHeader = criteriaHeader,
                titleRightInset = titleRightInset,
                onSectionResize = function(rowFrame, currentH)
                    -- Expand/collapse changes this card's height → let virtualization reflow the flat rows
                    -- below it and resize the host (replaces the old CardLayoutManager path).
                    -- Ignore the synchronous resize emitted during construction (before rowBuilt) — see guard note above.
                    if not rowBuilt then return end
                    if onExpandReflow then
                        onExpandReflow(rowFrame, currentH)
                    end
                end,
                onExpandPopulate = achievementOnExpandPopulate,
            }

            -- Declared before the constructor call so the toggle closure captures the row upvalue.
            local row
            row = CreateExpandableRow(host, listCardWidth, collapsedH, rowData, isExpanded, function(expanded)
                expandedPlans[plan.id] = expanded
                if onExpandReflow then
                    onExpandReflow(row, row and row.GetHeight and row:GetHeight() or collapsedH)
                end
            end)
            -- Row fully constructed: from here real user toggles are allowed to reflow.
            rowBuilt = true
            if row then
            row:SetWidth(listCardWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", host, "TOPLEFT", cardX or 0, -(cardY or 0))

            -- Row chrome: ExpandableRowFactory owns classic dialog-box / modern accent borders.

            -- Header right rail: Tries + actions vertically centered on the portrait icon.
            local rightOffset = ACTION_EDGE
            row._todoActionControls = {}
            row._todoActionOffsets = {}
            local function registerActionControl(ctrl, w)
                if not ctrl then return end
                row._todoActionControls[#row._todoActionControls + 1] = ctrl
                row._todoActionOffsets[#row._todoActionOffsets + 1] = rightOffset
                w = w or ACTION_SIZE
                if ns.UI_PlansAnchorHeaderAction then
                    ns.UI_PlansAnchorHeaderAction(ctrl, row.headerFrame, rightOffset, w, 0, row.iconFrame)
                else
                    ctrl:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
                end
                rightOffset = rightOffset + w + ACTION_GAP
            end
            local function makeIconAction(iconKey, onClick, tooltipKey, tooltipFallback, active)
                local vc = ns.UI_WnIconVertexForKey and ns.UI_WnIconVertexForKey(iconKey, active, false)
                    or (ns.WN_ICON_VERTEX_WHITE or { 1, 1, 1, 1 })
                local btn = ns.UI_CreateIconActionButton and ns.UI_CreateIconActionButton(row.headerFrame, ACTION_SIZE, iconKey, {
                    frameLevelOffset = 10,
                    vertexColor = vc,
                    onClick = onClick,
                    tooltipTitle = (ns.L and ns.L[tooltipKey]) or tooltipFallback,
                    tooltipAnchor = "ANCHOR_TOP",
                })
                if not btn then return nil end
                registerActionControl(btn, ACTION_SIZE)
                return btn
            end

            local function anchorRightControl(control, width)
                if not control then return end
                registerActionControl(control, width or ACTION_SIZE)
            end

            -- Delete (rightmost): prohibited/block icon
            makeIconAction(
                "delete",
                function() if plan.id then self:RemovePlan(plan.id) end end,
                "PLAN_ACTION_DELETE", "Delete the Plan",
                false
            )

            -- Track: Atlas pin (achievement Blizzard objectives)
            if plan.type == "achievement" and plan.achievementID and ns.UI.Factory and ns.UI.Factory.CreateAchievementTrackPinButton then
                local achPin = ns.UI.Factory:CreateAchievementTrackPinButton(row.headerFrame, plan.achievementID, {
                    size = ACTION_SIZE,
                    frameLevelOffset = 30,
                    isDisabled = function() return memoIsActivePlanComplete(plan) end,
                })
                if achPin and achPin.WnRefreshAchievementTrackPin then
                    achPin:WnRefreshAchievementTrackPin()
                end
                anchorRightControl(achPin, ACTION_SIZE)
            end

            -- Alert: reminder / bell icon
            if PlanCardFactory.CreateReminderAlertButton and not memoIsActivePlanComplete(plan) then
                local remBtn = PlanCardFactory.CreateReminderAlertButton(row.headerFrame, plan)
                if remBtn then
                    remBtn:SetFrameLevel((row.headerFrame:GetFrameLevel() or 0) + 12)
                    if remBtn.WnRefreshReminderIcon then
                        remBtn:WnRefreshReminderIcon()
                    end
                    anchorRightControl(remBtn, ACTION_SIZE)
                end
            end

            -- Custom complete: green check (packaged WN icon; atlas-only buttons were invisible when SetAtlas failed)
            if plan.type == "custom" and not planComplete then
                makeIconAction(
                    "complete",
                    function()
                        if self.CompleteCustomPlan then self:CompleteCustomPlan(plan.id) end
                    end,
                    "PLAN_ACTION_COMPLETE", "Complete the Plan",
                    false
                )
            end

            if ns.UI_PlansSyncTitleRightInset then
                ns.UI_PlansSyncTitleRightInset(row, rightOffset)
            end

            row:Show()
            return row
            end
        end
    end

    -- ── Variable-height flat-row VIRTUALIZATION ─────────────────────────────────────────────────────
    -- Replaces the all-cards-in-one-frame render that froze a large Show Completed set. Only cards whose
    -- flat rows intersect the viewport are created; each plan owns its card (created once, cached by
    -- plan.id, shown/hidden as it scrolls) so expand state persists with no rebind. Expand/collapse and
    -- data changes reflow row heights + re-window. Cards rebuild when the plan-data epoch bumps.
    parent._plansCardLayoutManager = nil
    parent._plansBrowseLayoutManager = nil

    local mfActive = self.UI and self.UI.mainFrame
    local ACTIVE_WIN_OVERSCAN = 1
    local ACTIVE_CREATE_CHUNK = 2  -- new cards created per frame during first paint (keeps spikes small)
    local colStride = cardWidth + cardSpacing
    local collapsedRowH = (ns.UI_PlansTodoFixedCollapsedHeight and ns.UI_PlansTodoFixedCollapsedHeight(true)) or todoHeaderH

    -- Persistent protected host (same keep contract as the browse grid: hidden-in-place within Plans,
    -- detached/re-adopted across main-tab switches).
    local host = parent._wnPlansActiveHost
    if host and host:GetParent() ~= parent then host:SetParent(parent) end
    if not host then
        host = CreateFrame("Frame", nil, parent)
        host._wnPlansBrowseKeep = true
        host._wnKeepOnTabSwitch = true
        parent._wnPlansActiveHost = host
    end
    host:ClearAllPoints()
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(yOffset or 0))
    host:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(yOffset or 0))
    host:Show()

    -- Cache invalidation is scoped to what actually changed:
    --   • WN_PLANS_UPDATED / WN_PLAN_COMPLETED carrying a planID → mark THAT plan dirty.
    --   • Bulk changes (no planID) and collection scans → bump the epoch (every card rebuilds).
    -- A single add/remove used to bump the epoch and throw away every cached card, so one changed plan
    -- cost a full rebuild of the visible set. Pure UI toggles (Show Completed) invalidate nothing.
    if not ns._plansActiveEpochHooked and WarbandNexus.RegisterMessage and E then
        ns._plansActiveEpochHooked = true
        ns._plansActiveCardEpoch = ns._plansActiveCardEpoch or 1
        ns._plansDirtyCardIds = ns._plansDirtyCardIds or {}
        local listeners = {}
        ns._plansActiveEpochListeners = listeners
        local function bumpEpoch() ns._plansActiveCardEpoch = (ns._plansActiveCardEpoch or 1) + 1 end
        local function onPlanScopedChange(_, payload)
            local pid = payload and payload.planID
            if pid ~= nil then
                ns._plansDirtyCardIds[pid] = true
            else
                bumpEpoch()
            end
        end
        if E.PLANS_UPDATED then WarbandNexus.RegisterMessage(listeners, E.PLANS_UPDATED, onPlanScopedChange) end
        if E.PLAN_COMPLETED then WarbandNexus.RegisterMessage(listeners, E.PLAN_COMPLETED, onPlanScopedChange) end
        local bulkEvs = { E.COLLECTION_UPDATED, E.COLLECTION_SCAN_COMPLETE }
        for ei = 1, #bulkEvs do
            if bulkEvs[ei] then WarbandNexus.RegisterMessage(listeners, bulkEvs[ei], bumpEpoch) end
        end
    end
    local epoch = ns._plansActiveCardEpoch or 1
    local dirtyCardIds = ns._plansDirtyCardIds or {}
    ns._plansDirtyCardIds = dirtyCardIds

    local cardCache = host._wnActiveCardCache
    if not cardCache then cardCache = {}; host._wnActiveCardCache = cardCache end
    local heightByPlanId = host._wnActiveHeightByPlanId
    if not heightByPlanId then heightByPlanId = {}; host._wnActiveHeightByPlanId = heightByPlanId end

    -- Prune cache entries for plans no longer present (removed / filtered out).
    do
        local present = {}
        for i = 1, #plans do present[plans[i].id] = true end
        for pid, card in pairs(cardCache) do
            if not present[pid] then
                if card then card:Hide(); card:ClearAllPoints() end
                cardCache[pid] = nil
                heightByPlanId[pid] = nil
            end
        end
        for pid in pairs(dirtyCardIds) do
            if not present[pid] then dirtyCardIds[pid] = nil end
        end
    end

    --- A cached card is reusable only if it predates no invalidation for its own plan.
    local function cardIsStale(card, planId)
        if not card then return true end
        if card._epoch ~= epoch then return true end
        if dirtyCardIds[planId] then return true end
        return false
    end

    local function planCardHeight(plan)
        if plan.type == "weekly_vault" or plan.type == "daily_quests" then
            return (ns.UI_MeasureFullWidthPlanCardHeight and ns.UI_MeasureFullWidthPlanCardHeight(plan, gridW)) or 174
        end
        return heightByPlanId[plan.id] or collapsedRowH
    end

    local reflowFrom, updateVisible

    local st = host._wnActiveVState or {}
    host._wnActiveVState = st
    ns._plansActiveGen = (ns._plansActiveGen or 0) + 1
    st.gen = ns._plansActiveGen
    st.host = host
    st.yOffset = yOffset or 0

    -- Column flow, not fixed rows. Each column keeps its own Y cursor, so expanding a card pushes
    -- only the cards below it in that same column. The previous shared row height (max of the pair)
    -- coupled the columns: a tall expanded card left a void under its short neighbour and shoved the
    -- other column down with it. Column assignment stays index-based (odd -> left, even -> right) so
    -- card order remains predictable; only the vertical coupling is removed.
    local function buildRows()
        local rows = {}
        local colY = { 0, 0 }
        local colX = { gridPadH, gridPadH + colStride }
        local maxBottom = 0
        local i = 1
        while i <= #plans do
            local plan = plans[i]
            if plan.type == "weekly_vault" or plan.type == "daily_quests" then
                -- Full-width card spans both columns, so it is a barrier: flush both cursors to it.
                local y = math.max(colY[1], colY[2])
                local h = planCardHeight(plan)
                rows[#rows + 1] = { y = y, height = h, slots = { { idx = i, plan = plan, x = gridPadH, full = true } } }
                local below = y + h + cardSpacing
                colY[1], colY[2] = below, below
                if y + h > maxBottom then maxBottom = y + h end
                i = i + 1
            else
                local placed = 0
                for c = 1, 2 do
                    local p = plans[i]
                    if not p or p.type == "weekly_vault" or p.type == "daily_quests" then break end
                    local y = colY[c]
                    local h = planCardHeight(p)
                    rows[#rows + 1] = { y = y, height = h, slots = { { idx = i, plan = p, x = colX[c], full = false } } }
                    colY[c] = y + h + cardSpacing
                    if y + h > maxBottom then maxBottom = y + h end
                    i = i + 1
                    placed = placed + 1
                end
                if placed == 0 then break end
            end
        end
        st.rows = rows
        local totalH = (#rows > 0) and (maxBottom + 10) or 20
        st.totalH = totalH
        host:SetHeight(math.max(totalH, 1))
        if parent.SetHeight then parent:SetHeight(math.max((st.yOffset) + totalH + 20, 1)) end
    end

    local function buildSlotCard(slot, rowY)
        local plan = slot.plan
        local card = cardCache[plan.id]
        if card and cardIsStale(card, plan.id) then
            card:Hide(); card:ClearAllPoints()
            cardCache[plan.id] = nil
            card = nil
        end
        if not card then
            dirtyCardIds[plan.id] = nil
            card = renderActivePlanCard(slot.idx, host, slot.x, rowY, function(_, currentH)
                if plan.type ~= "weekly_vault" and plan.type ~= "daily_quests" and currentH and currentH > 0 then
                    heightByPlanId[plan.id] = currentH
                end
                if reflowFrom then reflowFrom() end
            end)
            if card then card._epoch = epoch; cardCache[plan.id] = card end
        else
            if card:GetParent() ~= host then card:SetParent(host) end
            card:ClearAllPoints()
            if slot.full then
                card:SetPoint("TOPLEFT", host, "TOPLEFT", gridPadH, -rowY)
                card:SetPoint("TOPRIGHT", host, "TOPRIGHT", -gridPadH, -rowY)
            else
                card:SetPoint("TOPLEFT", host, "TOPLEFT", slot.x, -rowY)
            end
            card:Show()
        end
        return card
    end

    updateVisible = function()
        if st.gen ~= ns._plansActiveGen then return end
        local mf = self.UI and self.UI.mainFrame
        if not mf or not mf:IsShown() or mf.currentTab ~= "plans" then return end
        local scroll = mf.scroll
        local scrollChild = mf.scrollChild
        if not scroll or not scrollChild then return end
        local rows = st.rows
        if not rows then return end
        local scrollTop = scroll:GetVerticalScroll() or 0
        local viewH = scroll:GetHeight() or 0
        local listTop = (ns.UI_ListTopOffsetDownFromScrollContent and ns.UI_ListTopOffsetDownFromScrollContent(host, scrollChild)) or (st.yOffset or 0)
        local localTop = scrollTop - listTop
        local localBottom = localTop + viewH
        local overscanPx = ACTIVE_WIN_OVERSCAN * (collapsedRowH + cardSpacing)
        local created = 0
        local moreToCreate = false
        local anyCreated = false
        local visibleIds = st._visScratch or {}
        wipe(visibleIds)
        st._visScratch = visibleIds
        for r = 1, #rows do
            local row = rows[r]
            if (row.y + row.height) > (localTop - overscanPx) and row.y < (localBottom + overscanPx) then
                for s = 1, #row.slots do
                    local slot = row.slots[s]
                    visibleIds[slot.plan.id] = true
                    local existing = cardCache[slot.plan.id]
                    local needCreate = cardIsStale(existing, slot.plan.id)
                    if needCreate and created >= ACTIVE_CREATE_CHUNK then
                        moreToCreate = true
                    else
                        if needCreate then created = created + 1; anyCreated = true end
                        buildSlotCard(slot, row.y)
                    end
                end
            end
        end
        for pid, card in pairs(cardCache) do
            if not visibleIds[pid] and card and card:IsShown() then card:Hide() end
        end
        if moreToCreate then
            C_Timer.After(0, updateVisible)
        else
            if anyCreated then
                -- Newly created cards may have rendered taller than collapsed (expanded achievement plans);
                -- reconcile their true heights one frame later and reflow if the model was off.
                C_Timer.After(0, function()
                    if st.gen ~= ns._plansActiveGen then return end
                    local changed = false
                    for pid, card in pairs(cardCache) do
                        if card and card:IsShown() and not (card._layoutInfo and card._layoutInfo.isFullWidth) then
                            local h = card:GetHeight()
                            if h and h > 1 and math.abs((heightByPlanId[pid] or collapsedRowH) - h) > 1.5 then
                                heightByPlanId[pid] = h
                                changed = true
                            end
                        end
                    end
                    if changed and reflowFrom then reflowFrom() end
                end)
            end
            if ns.UI_EnsureMainScrollLayout then ns.UI_EnsureMainScrollLayout() end
        end
    end

    reflowFrom = function()
        buildRows()
        updateVisible()
    end

    st.updateVisible = updateVisible
    ns._plansActiveVState = st

    -- Hook the outer scroll once → re-window the active list (gated by gen / active state).
    if mfActive and mfActive.scroll and mfActive.scroll.HookScript and not ns._plansActiveScrollHooked then
        ns._plansActiveScrollHooked = true
        mfActive.scroll:HookScript("OnVerticalScroll", function()
            local s = ns._plansActiveVState
            if s and s.updateVisible and s.gen == ns._plansActiveGen then
                s.updateVisible()
            end
        end)
    end

    buildRows()
    updateVisible()

    return (st.yOffset) + (st.totalH or 20) + 20
end

-- EVENT HANDLERS

--[[
    Handle WN_PLANS_UPDATED event
    Only refreshes if Plans tab is visible (event-driven, no polling)
]]
-- REMOVED: OnPlansUpdated — UI.lua's SchedulePopulateContent handles WN_PLANS_UPDATED centrally.

-- BROWSER (Mounts, Pets, Toys, Recipes)


-- CUSTOM PLAN DIALOG / STORAGE, WEEKLY VAULT PLAN DIALOG, CLOSE ALL PLAN DIALOGS: PlansUI_Dialogs.lua

-- DAILY QUEST PLAN DIALOG (see Modules/UI/PlansUI_WeeklyPlanner.lua)

if ns.UI_LayoutCoordinator and CardLayoutManager then
    local LC = ns.UI_LayoutCoordinator
    LC:RegisterTabAdapter("plans", {
        OnViewportLayoutCommit = function(scrollChild, _contentWidth, mf)
            if not mf or mf.currentTab ~= "plans" or not scrollChild then return false end
            if ns.UI_RefreshFixedHeaderChrome then
                ns.UI_RefreshFixedHeaderChrome(mf)
            end
            local lm = scrollChild._plansCardLayoutManager or scrollChild._plansBrowseLayoutManager
            if lm then
                CardLayoutManager:RefreshLayout(lm)
                return true
            end
            return false
        end,
    })
end
