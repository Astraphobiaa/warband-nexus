--[[
    Warband Nexus - Plans Tab UI
    User-driven goal tracker for mounts, pets, and toys

    WN_FACTORY: Achievement browse root + Vault slot grid use Factory first (`CreateContainer` / `CreateButton`);
    Custom Plan dialogs (reset-cycle toggles / duration +/-) use Factory-backed buttons where `ApplyVisuals`
    borders apply; legacy `BackdropTemplate` path kept when Factory returns nil.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager  -- Centralized font management

local issecretvalue = issecretvalue

--- Lowercase for search only when the string is safe to touch (Midnight 12.0+).
local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
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
local CreateResultsContainer = ns.UI_CreateResultsContainer
local CreateIcon = ns.UI_CreateIcon
local ApplyVisuals = ns.UI_ApplyVisuals
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
    { key = "transmog", name = (ns.L and ns.L["CATEGORY_TRANSMOG"]) or "Transmog", iconAtlas = "poi-transmogrifier" },
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
    if not categoryBar or not categoryBar.buttons then return end
    local acc = COLORS.accent
    for k, btn in pairs(categoryBar.buttons) do
        local isActive = (k == activeKey)
        btn._active = isActive
        if btn.activeBar then btn.activeBar:SetAlpha(isActive and 1 or 0) end
        if ApplyVisuals then
            if isActive then
                local act = COLORS.tabActive or { acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1 }
                ApplyVisuals(btn, act, { acc[1], acc[2], acc[3], 1 })
            else
                local idleBg = (ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop()) or COLORS.bgCard
                ApplyVisuals(btn, idleBg, { acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1 })
            end
        end
        if btn._text then
            if isActive then
                ns.UI_SetTextColorRole(btn._text, "Bright")
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(btn._text, true)
                end
            else
                ns.UI_SetTextColorRole(btn._text, "Muted")
                if ns.UI_SetNavLabelFontStyle then
                    ns.UI_SetNavLabelFontStyle(btn._text, false)
                end
            end
        end
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
            for vi = 1, #visible do
                local v = visible[vi]
                if v and v.frame then
                    v.frame:Hide()
                    v.frame:ClearAllPoints()
                    rowPool[#rowPool + 1] = v.frame
                end
            end
            st._achVisibleRowFrames = {}
        end
        DetachOwnedPlansInnerScroll(st, nil)
        host._plansAchBrowseState = nil
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
    TeardownPlansScrollChildBrowseArtifacts(parent)
    if HideEmptyStateCard then
        HideEmptyStateCard(parent, "plans")
        HideEmptyStateCard(parent, "plans_browse")
    end
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
    end
    local recycleBin = ns.UI_RecycleBin
    local children = CollectScrollChildFrames(parent)
    for i = 1, #children do
        local child = children[i]
        if child and child ~= parent.emptyStateContainer then
            if ReleasePooledRowsInSubtree then
                ReleasePooledRowsInSubtree(child)
            end
        end
    end
    for i = 1, #children do
        local child = children[i]
        if child and child ~= parent.emptyStateContainer then
            child:Hide()
            child:ClearAllPoints()
            if recycleBin then
                child:SetParent(recycleBin)
            end
        end
    end
    parent._plansCardLayoutManager = nil
    parent._plansBrowseLayoutManager = nil
    parent.plansAchBrowseRoot = nil
    parent._plansAchBrowseState = nil
    parent._plansAchBrowseRowPool = nil
    ns._plansAchPopulateGen = (ns._plansAchPopulateGen or 0) + 1
    ns._plansBrowsePaintGen = (ns._plansBrowsePaintGen or 0) + 1
end

ns.TeardownPlansScrollChildBrowseArtifacts = TeardownPlansScrollChildBrowseArtifacts

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

    -- To-Do List needs the scroll search bar (fixed header only on first DrawPlansTab).
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

    parent:SetHeight(math.max((yOffset or 0) + 20, 1))
    if ns.UI_EnsureMainScrollLayout then
        ns.UI_EnsureMainScrollLayout()
    elseif mf.scroll and UpdateScrollLayout then
        UpdateScrollLayout(mf)
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

-- Icons (no unicode - use game textures)
local ICON_CHECK = "Interface\\RaidFrame\\ReadyCheck-Ready"
local ICON_WAITING = "Interface\\RaidFrame\\ReadyCheck-Waiting"
local ICON_CROSS = "Interface\\RaidFrame\\ReadyCheck-NotReady"
local ICON_GOLD = "Interface\\MONEYFRAME\\UI-GoldIcon"

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

-- Source parser: PlansUI_SourceParser.lua

-- MAIN DRAW FUNCTION

--- Reposition cached Plans fixedHeader chrome (Collections/Items parity — WN-PERF tab revisit).
local function RepositionPlansFixedHeader(hdrCache, headerParent, chrome, headerYOffset, contentSide, subtitleTextContent)
    local titleCard = hdrCache.titleCard
    titleCard:SetParent(headerParent)
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end
    titleCard:Show()
    if hdrCache.subtitleText and subtitleTextContent then
        hdrCache.subtitleText:SetText(subtitleTextContent)
    end
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
    end
    local categoryBar = hdrCache.categoryBar
    if categoryBar then
        categoryBar:SetParent(headerParent)
        categoryBar:ClearAllPoints()
        categoryBar:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        categoryBar:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
        categoryBar:Show()
        ApplyPlansCategoryBarActive(categoryBar, currentCategory)
        local blockGap = (ns.UI_LAYOUT and ns.UI_LAYOUT.TAB_CHROME_BLOCK_GAP) or (GetLayout().afterElement) or 8
        headerYOffset = headerYOffset + (categoryBar:GetHeight() or 40) + blockGap
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
    HideEmptyStateCard(parent, "plans")

    -- Default: To-Do List ("active"). Same session: remember last category until /reload.
    ResolvePlansCategoryFromSession()

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
    local scrollTopY = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8

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
        100, 100, 100, 80, 120, 115,
    })) or 600

    local hdrCache = mf and mf._plansFixedHeaderCache
    local headerChromeDone = false
    if hdrCache and hdrCache.titleCard and hdrCache.categoryBar then
        headerYOffset = RepositionPlansFixedHeader(hdrCache, headerParent, chrome, headerYOffset, contentSide, subtitleTextContent)
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

        -- Add Custom button (using shared widget)
        local titleEdgeInset = tm.edgeInset or 0
        local hdrToolbarGap = tm.gap or (GetLayout().HEADER_TOOLBAR_CONTROL_GAP or 8)
        local addCustomBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_CUSTOM"]) or "Add Custom", 100)
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(addCustomBtn, titleCard, titleCard, "RIGHT", -titleEdgeInset)
        else
            addCustomBtn:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
        end
        -- Store reference for state management
        self.addCustomBtn = addCustomBtn
        addCustomBtn:SetScript("OnClick", function()
            self:ShowCustomPlanDialog()
        end)
        
        -- Add Vault button (using shared widget)
        local addWeeklyBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_VAULT"]) or "Add Vault", 100)
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(addWeeklyBtn, titleCard, addCustomBtn, "LEFT", -hdrToolbarGap)
        else
            addWeeklyBtn:SetPoint("RIGHT", addCustomBtn, "LEFT", -hdrToolbarGap, 0)
        end
        addWeeklyBtn:SetScript("OnClick", function()
            self:ShowWeeklyPlanDialog()
        end)
        
        -- Add Quest button (opens Daily Plan dialog)
        local addDailyBtn = CreateThemedButton(titleCard, (ns.L and ns.L["ADD_QUEST"]) or "Add Quest", 100)
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(addDailyBtn, titleCard, addWeeklyBtn, "LEFT", -hdrToolbarGap)
        else
            addDailyBtn:SetPoint("RIGHT", addWeeklyBtn, "LEFT", -hdrToolbarGap, 0)
        end
        addDailyBtn:SetScript("OnClick", function()
            self:ShowDailyPlanDialog()
        end)

        -- Checkbox (using shared widget) - Next to Add Quest button
        local checkbox = CreateThemedCheckbox(titleCard, showCompleted)
        if checkbox and checkbox.innerDot then
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
        
        -- Reset Completed Plans button (left of Add Quest button)
        local resetBtn = CreateThemedButton(titleCard, (ns.L and ns.L["RESET_LABEL"]) or "Reset", 80)
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(resetBtn, titleCard, addDailyBtn, "LEFT", -hdrToolbarGap)
        else
            resetBtn:SetPoint("RIGHT", addDailyBtn, "LEFT", -hdrToolbarGap, 0)
        end

        -- Checkbox (left of Reset button)
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(checkbox, titleCard, resetBtn, "LEFT", -hdrToolbarGap)
        else
            checkbox:SetPoint("RIGHT", resetBtn, "LEFT", -hdrToolbarGap, 0)
        end
        resetBtn:SetScript("OnClick", function()
            -- Confirmation via StaticPopup
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
        end)
        
        -- Tooltip for reset button
        resetBtn:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText((ns.L and ns.L["REMOVE_COMPLETED_TOOLTIP"]) or "Remove all completed plans from your My Plans list. This will delete all completed custom plans and remove completed mounts/pets/toys from your plans. This action cannot be undone!", 1, 1, 1, 1)
            GameTooltip:Show()
        end)
        resetBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        
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
            if plannedCheckbox.innerDot then
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
        if ns.UI_AdvanceTabChromeYOffset then
            headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        else
            headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
        end
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) elseif fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, scrollTopY, (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List")
        return scrollTopY + cardHeight
    end

    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end
    
    local categoryBar = ns.UI.Factory:CreateContainer(headerParent, nil, nil, false)
    categoryBar:SetPoint("TOPLEFT", contentSide, -headerYOffset)
    categoryBar:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    
    local DEFAULT_CAT_BTN_WIDTH = 150
    local catBtnHeight = 40
    local catBtnSpacing = 8
    local catIconSize = 28
    local catIconLeftPad = 10
    local catIconTextGap = 8
    local catTextRightPad = 10
    local maxWidth = (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
        or math.max(200, (parent:GetWidth() or 600) - (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin() or 12) * 2)
    
    -- Pre-calculate button widths based on text (icon + padding + text + padding)
    local catBtnWidths = {}
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
        -- Measure text width using a temporary FontString
        local tempFs = FontManager:CreateFontString(categoryBar, "body", "OVERLAY")
        tempFs:SetText(cat.name)
        local textW = tempFs:GetStringWidth() or 0
        tempFs:Hide()
        local needed = catIconLeftPad + catIconSize + catIconTextGap + textW + catTextRightPad
        catBtnWidths[i] = math.max(needed, DEFAULT_CAT_BTN_WIDTH)
    end
    
    local currentX = 0
    local currentRow = 0
    local categoryButtons = {}
    
    for i = 1, #CATEGORIES do
        local cat = CATEGORIES[i]
        local catBtnWidth = catBtnWidths[i]
        
        -- Check if button fits in current row
        if currentX + catBtnWidth > maxWidth and currentX > 0 then
            -- Move to next row
            currentX = 0
            currentRow = currentRow + 1
        end
        
        local btn = ns.UI.Factory:CreateButton(categoryBar, catBtnWidth, catBtnHeight)
        btn:SetPoint("TOPLEFT", currentX, -(currentRow * (catBtnHeight + catBtnSpacing)))
        
        -- Check if this is the active category
        local isActive = (cat.key == currentCategory)
        local acc = COLORS.accent

        if ApplyVisuals then
            if isActive then
                local act = COLORS.tabActive or { acc[1] * 0.3, acc[2] * 0.3, acc[3] * 0.3, 1 }
                ApplyVisuals(btn, act, { acc[1], acc[2], acc[3], 1 })
            else
                local idleBg = (ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop()) or COLORS.bgCard
                ApplyVisuals(btn, idleBg, { acc[1] * 0.6, acc[2] * 0.6, acc[3] * 0.6, 1 })
            end
        end

        -- Apply highlight effect (safe check for Factory)
        if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then
            ns.UI.Factory:ApplyHighlight(btn)
        end

        -- Active indicator bar (same as Collections/Items sub-tab)
        local activeBar = btn:CreateTexture(nil, "OVERLAY")
        activeBar:SetHeight(3)
        activeBar:SetPoint("BOTTOMLEFT", 8, 4)
        activeBar:SetPoint("BOTTOMRIGHT", -8, 4)
        activeBar:SetColorTexture(acc[1], acc[2], acc[3], 1)
        activeBar:SetAlpha(isActive and 1 or 0)
        btn.activeBar = activeBar

        -- Use atlas icon if available, otherwise use regular icon path
        local iconFrame
        if cat.iconAtlas then
            -- Create frame for atlas icon (using Factory pattern)
            iconFrame = ns.UI.Factory:CreateContainer(btn, 28, 28)
        iconFrame:SetPoint("LEFT", 10, 0)
            iconFrame:EnableMouse(false)
            
            local iconTexture = iconFrame:CreateTexture(nil, "OVERLAY")
            iconTexture:SetAllPoints()
            local iconSuccess = pcall(function()
                iconTexture:SetAtlas(cat.iconAtlas, false)
            end)
            if not iconSuccess then
                iconFrame:Hide()
                iconFrame = nil
            else
                iconTexture:SetSnapToPixelGrid(false)
                iconTexture:SetTexelSnappingBias(0)
                iconFrame:Show()  -- Show atlas icon!
            end
        end
        
        -- Fallback to regular icon if atlas failed or not available
        if not iconFrame and cat.icon then
            iconFrame = CreateIcon(btn, cat.icon, 28, false, nil, true)
            iconFrame:SetPoint("LEFT", 10, 0)
            iconFrame:Show()  -- Show category tab icon (My Plans, Daily Tasks, Achievements)!
        end
        
        local label = FontManager:CreateFontString(btn, "body", "OVERLAY")
        label._wnNavLabel = true
        label:SetPoint("LEFT", iconFrame, "RIGHT", 8, 0)
        label:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        label:SetText(cat.name)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        btn._text = label
        categoryButtons[cat.key] = btn
        if isActive then
            ns.UI_SetTextColorRole(label, "Bright")
            if ns.UI_SetNavLabelFontStyle then
                ns.UI_SetNavLabelFontStyle(label, true)
            end
        else
            ns.UI_SetTextColorRole(label, "Muted")
            if ns.UI_SetNavLabelFontStyle then
                ns.UI_SetNavLabelFontStyle(label, false)
            end
        end

        btn:SetScript("OnClick", function()
            if currentCategory == cat.key then return end
            local fromCat = currentCategory
            currentCategory = cat.key
            ns._sessionPlansCategory = cat.key
            if ns.UI_ClearPlansCategorySearches then
                ns.UI_ClearPlansCategorySearches()
            end
            searchText = ""
            ns._plansCategoryBodyGen = (ns._plansCategoryBodyGen or 0) + 1
            local bodyGen = ns._plansCategoryBodyGen
            C_Timer.After(0, function()
                if not WarbandNexus then return end
                if ns._plansCategoryBodyGen ~= bodyGen then return end
                if not (WarbandNexus.RefreshPlansCategoryBodyOnly and WarbandNexus:RefreshPlansCategoryBodyOnly(fromCat, cat.key)) then
                    if WarbandNexus.SendMessage then
                        WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
                    end
                end
            end)
        end)
        
        -- Update X position for next button
        currentX = currentX + catBtnWidth + catBtnSpacing
    end
    
    -- Set categoryBar height based on rows
    -- Formula: (rows * buttonHeight) + (gaps_between_rows * spacing)
    -- Example: 2 rows = 2 * 40px + 1 * 8px = 88px (not 96px!)
    local totalHeight = (currentRow + 1) * catBtnHeight + currentRow * catBtnSpacing
    categoryBar:SetHeight(totalHeight)
    categoryBar.buttons = categoryButtons
    if mf then
        mf._plansCategoryBar = categoryBar
    end
    
    local blockGap = (metrics and metrics.blockGap) or (GetLayout().TAB_CHROME_BLOCK_GAP) or (GetLayout().afterElement) or 8
    headerYOffset = headerYOffset + totalHeight + blockGap

    if ns.UI_CommitTabFixedHeader then
        ns.UI_CommitTabFixedHeader(mf, headerYOffset)
    elseif fixedHeader then
        fixedHeader:SetHeight(headerYOffset)
    end

    if mf then
        mf._plansFixedHeaderCache = {
            titleCard = titleCard,
            subtitleText = plansSubtitleText,
            categoryBar = categoryBar,
        }
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
        local bodyY = scrollTopY
        if currentCategory == "active" then
        local padH = PlansContentPadH()
        local searchPlaceholder = (ns.L and ns.L["SEARCH_PLANS"]) or "Search plans..."
        local initialSearch = ns._plansActiveSearch or ""
        local searchBar = CreateSearchBox(parent, width, searchPlaceholder, function(text)
            ns._plansActiveSearch = (text ~= "") and text or nil
            if ns.UI_ScheduleSearchRefresh then
                ns.UI_ScheduleSearchRefresh("plans_active", function()
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
                end)
            else
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "plans", skipCooldown = true })
            end
        end, nil, initialSearch, "plans_active")
        searchBar:SetPoint("TOPLEFT", padH, -bodyY)
        searchBar:SetPoint("TOPRIGHT", -padH, -bodyY)
        searchBar:Show()

        local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
        bodyY = bodyY + searchH + GetLayout().afterElement
        end

        if currentCategory == "active" or currentCategory == "daily_tasks" then
            bodyY = self:DrawActivePlans(parent, bodyY, width, currentCategory)
        else
            bodyY = self:DrawBrowser(parent, bodyY, width, currentCategory)
        end
        return bodyY + 20
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

local function GetCategoryStats(plan, categoryKey)
    if not plan or not plan.questTypes or not plan.questTypes[categoryKey] then
        return 0, 0
    end
    local questList = (plan.quests and plan.quests[categoryKey]) or {}
    local total, completed = 0, 0
    for i = 1, #questList do
        local q = questList[i]
        if q and not q.isSubQuest then
            total = total + 1
            if q.isComplete then completed = completed + 1 end
        end
    end
    return completed, total
end

local function FormatTimeLeft(minutes)
    if not minutes or minutes <= 0 then return "" end
    local L = ns.L
    local Day = (L and L["PLAYED_DAY"]) or "Day"
    local Days = (L and L["PLAYED_DAYS"]) or "Days"
    local Hour = (L and L["PLAYED_HOUR"]) or "Hour"
    local Hours = (L and L["PLAYED_HOURS"]) or "Hours"
    local Minute = (L and L["PLAYED_MINUTE"]) or "Minute"
    local Minutes = (L and L["PLAYED_MINUTES"]) or "Minutes"
    if minutes >= 1440 then
        local days = math.floor(minutes / 1440)
        local hours = math.floor((minutes % 1440) / 60)
        if hours > 0 then
            return format("%d %s %d %s", days, days == 1 and Day or Days, hours, hours == 1 and Hour or Hours)
        end
        return format("%d %s", days, days == 1 and Day or Days)
    elseif minutes >= 60 then
        local hours = math.floor(minutes / 60)
        local mins = minutes % 60
        if mins > 0 then
            return format("%d %s %d %s", hours, hours == 1 and Hour or Hours, mins, mins == 1 and Minute or Minutes)
        end
        return format("%d %s", hours, hours == 1 and Hour or Hours)
    end
    return format("%d %s", minutes, minutes == 1 and Minute or Minutes)
end

local EVENT_GROUP_NAMES = {
    soiree     = (ns.L and ns.L["EVENT_GROUP_SOIREE"]) or "Saltheril's Soiree",
    abundance  = (ns.L and ns.L["EVENT_GROUP_ABUNDANCE"]) or "Abundance",
    haranir    = (ns.L and ns.L["EVENT_GROUP_HARANIR"]) or "Legends of the Haranir",
    stormarion = (ns.L and ns.L["EVENT_GROUP_STORMARION"]) or "Stormarion Assault",
}

local function AttachQuestRowTooltip(frame, quest)
    frame:SetScript("OnEnter", function(self)
        local lines = {}
        if quest.description and quest.description ~= "" then
            lines[#lines + 1] = { text = quest.description, color = {0.9, 0.9, 0.9} }
        end
        if quest.isSubQuest and quest.eventGroup then
            local parentName = EVENT_GROUP_NAMES[quest.eventGroup] or quest.eventGroup
            lines[#lines + 1] = { text = format((ns.L and ns.L["PART_OF_FORMAT"]) or "Part of: %s", parentName), color = {0.8, 0.5, 1.0} }
        end
        if quest.zone and quest.zone ~= "" then
            lines[#lines + 1] = { text = quest.zone, color = {0.7, 0.7, 0.7} }
        end
        if quest.objective and quest.objective ~= "" then
            lines[#lines + 1] = { text = quest.objective, color = {1, 1, 1} }
        end
        if quest.progress and not quest.isComplete then
            local pct = math.floor((quest.progress.percent or 0) * 100)
            lines[#lines + 1] = {
                text = format(
                    (ns.L and ns.L["QUEST_PROGRESS_FORMAT"]) or "Progress: %d/%d (%d%%)",
                    quest.progress.totalFulfilled or 0,
                    quest.progress.totalRequired or 0,
                    pct
                ),
                color = pct >= 100 and {0.27, 1, 0.27} or {1, 0.82, 0.2},
            }
        end
        if quest.timeLeft and quest.timeLeft > 0 then
            local timeColor = quest.timeLeft < 60 and {1, 0.3, 0.3} or {0.7, 0.7, 0.7}
            lines[#lines + 1] = {
                text = format(
                    (ns.L and ns.L["QUEST_TIME_REMAINING_FORMAT"]) or "%s remaining",
                    FormatTimeLeft(quest.timeLeft)
                ),
                color = timeColor
            }
        end
        if quest.isComplete then
            local gr, gg, gb = PlanGreenRgb()
            lines[#lines + 1] = { text = PlanGreenHex() .. ((ns.L and ns.L["COMPLETE_LABEL"]) or "Complete") .. "|r", color = { gr, gg, gb } }
        elseif quest.isLocked then
            lines[#lines + 1] = { text = "|cffff9933" .. ((ns.L and ns.L["LOCKED_WORLD_QUESTS"]) or "Locked — complete World Quests to unlock") .. "|r", color = {1, 0.6, 0.2} }
        end
        if quest.questID then
            lines[#lines + 1] = { text = format((ns.L and ns.L["QUEST_ID_FORMAT"]) or "Quest ID: %s", quest.questID), color = {0.5, 0.5, 0.5} }
            lines[#lines + 1] = { text = (ns.L and ns.L["CLICK_FOR_WOWHEAD_LINK"]) or "Click for Wowhead link", color = {0.5, 0.4, 0.7} }
        end

        if ns.TooltipService and ns.TooltipService.Show then
            ns.TooltipService:Show(self, {
                type = "custom",
                title = quest.title or ((ns.L and ns.L["SOURCE_TYPE_QUEST"]) or "Quest"),
                icon = false,
                lines = lines,
            })
        else
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(quest.title or ((ns.L and ns.L["SOURCE_TYPE_QUEST"]) or "Quest"), 1, 1, 1)
            for i = 1, #lines do
                local c = lines[i].color or {1, 1, 1}
                GameTooltip:AddLine(lines[i].text, c[1], c[2], c[3], true)
            end
            GameTooltip:Show()
        end
    end)
    frame:SetScript("OnLeave", function()
        if ns.TooltipService and ns.TooltipService.Hide then
            ns.TooltipService:Hide()
        else
            GameTooltip:Hide()
        end
    end)
    if quest.questID and quest.questID > 0 then
        frame:SetScript("OnMouseDown", function(self)
            if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                ns.UI.Factory:ShowWowheadCopyURL("quest", quest.questID, self)
            end
        end)
    end
end

function WarbandNexus:DrawDailyTasksView(parent, yOffset, width, plans)
    local filteredPlans = {}
    for i = 1, #plans do
        if plans[i].contentType == "midnight" then
            filteredPlans[#filteredPlans + 1] = plans[i]
        end
    end

    table.sort(filteredPlans, function(a, b)
        return ((a.characterName or "") .. (a.characterRealm or ""))
             < ((b.characterName or "") .. (b.characterRealm or ""))
    end)

    if #filteredPlans == 0 then
        if ns.UI_ShowTabEmptyStateCard then
            return ns.UI_ShowTabEmptyStateCard(parent, "plans", yOffset, { fillParent = true }) + 10
        end
        local _, height = CreateEmptyStateCard(parent, "plans", yOffset, { fillParent = true })
        return yOffset + height + 10
    end

    local CATEGORIES = ns.QUEST_CATEGORIES or {}
    local CAT_DISPLAY = ns.CATEGORY_DISPLAY or {}
    local ROW_H = GetLayout().rowHeight
    local expandedGroups = ns.UI_GetExpandedGroups and ns.UI_GetExpandedGroups() or {}

    -- Persistent across repaints (same pattern as the Characters gold trio):
    -- the bar + its children used to be recreated and binned on every Plans paint.
    local padH = PlansContentPadH()
    local resetBarH = 30
    local resetBar = parent._wnPlansResetBar
    local resetTimeText
    if resetBar then
        resetBar:SetParent(parent)
        resetTimeText = resetBar._resetTimeText
    else
        resetBar = CreateCard(parent, resetBarH)
        parent._wnPlansResetBar = resetBar

        local resetIcon = resetBar:CreateTexture(nil, "ARTWORK")
        resetIcon:SetSize(16, 16)
        resetIcon:SetPoint("LEFT", 12, 0)
        resetIcon:SetAtlas("characterupdate_clock-icon", true)

        local resetLabel = FontManager:CreateFontString(resetBar, "body", "OVERLAY")
        resetLabel:SetPoint("LEFT", resetIcon, "RIGHT", 6, 0)
        ns.UI_SetTextColorRole(resetLabel, "Normal")
        resetLabel:SetText((ns.L and ns.L["WEEKLY_RESET_LABEL"]) or "Weekly Reset")

        resetTimeText = FontManager:CreateFontString(resetBar, "body", "OVERLAY")
        resetTimeText:SetPoint("RIGHT", -12, 0)
        if ns.UI_GetSemanticGreenColor then
            local gr, gg, gb = ns.UI_GetSemanticGreenColor()
            resetTimeText:SetTextColor(gr, gg, gb)
        else
            resetTimeText:SetTextColor(0.3, 0.9, 0.3)
        end
        resetBar._resetTimeText = resetTimeText
    end
    resetBar:SetHeight(resetBarH)
    resetBar:ClearAllPoints()
    resetBar:SetPoint("TOPLEFT", padH, -yOffset)
    resetBar:SetPoint("TOPRIGHT", -padH, -yOffset)
    if ApplyVisuals then
        local bg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
        ApplyVisuals(resetBar, bg, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7})
    end
    do
        local ok, seconds = pcall(function()
            if self.GetWeeklyResetTime then
                return self:GetWeeklyResetTime() - GetServerTime()
            elseif C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
            end
            return 0
        end)
        local sec = (ok and type(seconds) == "number") and seconds or 0
        resetTimeText:SetText(ns.Utilities:FormatTimeCompact(sec))
    end

    if resetBar._weeklyResetTicker then
        resetBar._weeklyResetTicker:Cancel()
        resetBar._weeklyResetTicker = nil
    end
    resetBar._weeklyResetTicker = C_Timer.NewTicker(60, function()
        local ok2, sec2 = pcall(function()
            if WarbandNexus.GetWeeklyResetTime then
                return WarbandNexus:GetWeeklyResetTime() - GetServerTime()
            elseif C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
            end
            return 0
        end)
        local s = (ok2 and type(sec2) == "number") and sec2 or 0
        resetTimeText:SetText(ns.Utilities:FormatTimeCompact(s))
    end)
    resetBar:SetScript("OnHide", function(self2)
        if self2._weeklyResetTicker then
            self2._weeklyResetTicker:Cancel()
            self2._weeklyResetTicker = nil
        end
    end)

    resetBar:Show()
    yOffset = yOffset + resetBarH + 6

    local Factory = ns.UI.Factory
    local SECTION_COLLAPSE_H = (GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT) or 36
    local sectionSpacing = (GetLayout().SECTION_SPACING) or 8
    local innerW = math.max(1, width - 2 * padH)
    local STATS_H = 28
    local scrollTop = yOffset
    local weeklyChainTail = nil
    local totalBlockH = 0

    if parent._weeklyScrollFixTimer then
        parent._weeklyScrollFixTimer:Cancel()
        parent._weeklyScrollFixTimer = nil
    end

    --- Sum stacked rows (stats strip + category wraps) so inner section height updates outer height.
    local function ReflowWeeklyProgressCharSectionBody(body)
        if not body or not body._weeklyRowList then return end
        local list = body._weeklyRowList
        local sp = body._weeklySectionSpacing or sectionSpacing
        local h = (list[1] and list[1]:GetHeight()) or STATS_H
        for ri = 2, #list do
            local rowFr = list[ri]
            if rowFr then
                h = h + sp + (rowFr:GetHeight() or 0.1)
            end
        end
        h = math.max(0.1, h + 6)
        body._wnSectionFullH = h
        local wrap = body._weeklyParentWrap
        local hdrH = (wrap and wrap._weeklyHeaderH) or SECTION_COLLAPSE_H
        if body:IsShown() then
            body:SetHeight(h)
            if wrap then
                wrap:SetHeight(hdrH + h)
            end
        end
    end

    local function ScheduleWeeklyProgressScrollSync()
        if not parent then return end
        if parent._weeklyScrollFixTimer then
            parent._weeklyScrollFixTimer:Cancel()
        end
        parent._weeklyScrollFixTimer = C_Timer.NewTimer(0.06, function()
            parent._weeklyScrollFixTimer = nil
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mf and mf.currentTab == "plans" then
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, {
                    tab = "plans",
                    skipCooldown = true,
                    instantPopulate = true,
                })
            end
        end)
    end

    local function WeeklySectionToggleNoop() end

    for pi = 1, #filteredPlans do
        local plan = filteredPlans[pi]
        local classColor = RAID_CLASS_COLORS[plan.characterClass or "PRIEST"] or {r = 1, g = 1, b = 1}

        local totalAll, completedAll = 0, 0
        for ci = 1, #CATEGORIES do
            local catInfo = CATEGORIES[ci]
            if plan.questTypes and plan.questTypes[catInfo.key] then
                local c, t = GetCategoryStats(plan, catInfo.key)
                completedAll = completedAll + c
                totalAll = totalAll + t
            end
        end

        if weeklyChainTail then
            totalBlockH = totalBlockH + sectionSpacing
        end

        local charWrap = Factory:CreateContainer(parent, innerW, SECTION_COLLAPSE_H + 0.1, false)
        if charWrap.SetClipsChildren then
            charWrap:SetClipsChildren(true)
        end
        charWrap:ClearAllPoints()
        ChainSectionFrameBelow(parent, charWrap, weeklyChainTail, padH, weeklyChainTail and sectionSpacing or nil, weeklyChainTail and nil or scrollTop)

        local realmHdr = plan.characterRealm or ""
        if realmHdr ~= "" and ns.Utilities and ns.Utilities.FormatRealmName then
            realmHdr = ns.Utilities:FormatRealmName(realmHdr)
        end
        local charTitlePlain = format(
            "|cff%02x%02x%02x%s|r |cff888888-%s|r",
            classColor.r * 255, classColor.g * 255, classColor.b * 255,
            plan.characterName or "Unknown",
            realmHdr
        )

        local charGroupKey = "weekly_char_" .. tostring(plan.id)
        local charExpanded = (expandedGroups[charGroupKey] == true)

        local charSectionBody
        local charHeader, charHdrExpandIcon, _, charHdrTitleFs = CreateCollapsibleHeader(
            charWrap,
            charTitlePlain,
            charGroupKey,
            charExpanded,
            WeeklySectionToggleNoop,
            nil,
            true,
            0,
            true,
            BuildCollapsibleSectionOpts({
                wrapFrame = charWrap,
                bodyGetter = function() return charSectionBody end,
                headerHeight = SECTION_COLLAPSE_H,
                hideOnCollapse = true,
                deferOnToggleUntilComplete = true,
                persistFn = function(exp)
                    expandedGroups[charGroupKey] = exp
                end,
                onComplete = function()
                    ReflowWeeklyProgressCharSectionBody(charSectionBody)
                    ScheduleWeeklyProgressScrollSync()
                end,
            })
        )
        charHeader:SetPoint("TOPLEFT", charWrap, "TOPLEFT", 0, 0)
        charHeader:SetWidth(innerW)

        if charHeader._wnSectionStripe then
            charHeader._wnSectionStripe:SetColorTexture(classColor.r, classColor.g, classColor.b, 0.9)
        end
        if charHdrExpandIcon and charHdrExpandIcon._wnCollapseTex then
            local r = math.min(1, classColor.r * 1.5)
            local g = math.min(1, classColor.g * 1.5)
            local b = math.min(1, classColor.b * 1.5)
            charHdrExpandIcon._wnCollapseTex:SetVertexColor(r, g, b)
            charHdrExpandIcon._wnCollapseVertexColor = { r, g, b, 1 }
        end

        local removeBtn = Factory:CreateButton(charHeader, 24, 24, true)
        removeBtn:SetPoint("RIGHT", -8, 0)
        removeBtn:SetFrameLevel((charHeader:GetFrameLevel() or 0) + 5)
        removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
        removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
        removeBtn:SetScript("OnClick", function()
            self:RemovePlan(plan.id)
        end)

        local totalFs = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        totalFs:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
        local totalColor = (totalAll > 0 and completedAll == totalAll) and PlanGreenHex() or PlanGoldHex()
        totalFs:SetText(totalColor .. completedAll .. "/" .. totalAll .. "|r")

        if charHdrTitleFs then
            charHdrTitleFs:SetJustifyH("LEFT")
            charHdrTitleFs:SetWordWrap(false)
            charHdrTitleFs:SetMaxLines(1)
            charHdrTitleFs:SetPoint("RIGHT", totalFs, "LEFT", -10, 0)
        end

        charSectionBody = Factory:CreateContainer(charWrap, innerW, 0.1, false)
        charSectionBody:ClearAllPoints()
        charSectionBody:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
        charSectionBody:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)

        local statsStrip = Factory:CreateContainer(charSectionBody, innerW, STATS_H, false)
        statsStrip:SetPoint("TOPLEFT", charSectionBody, "TOPLEFT", 0, 0)
        if statsStrip.SetClipsChildren then
            statsStrip:SetClipsChildren(true)
        end

        local catX = 8
        for ci = 1, #CATEGORIES do
            local catInfo = CATEGORIES[ci]
            if plan.questTypes and plan.questTypes[catInfo.key] then
                local display = CAT_DISPLAY[catInfo.key] or {}
                local catColor = display.color or {0.8, 0.8, 0.8}
                local catName = display.name and display.name() or catInfo.key
                local c, t = GetCategoryStats(plan, catInfo.key)
                if t > 0 then
                    local catFs = FontManager:CreateFontString(statsStrip, "small", "OVERLAY")
                    catFs:SetPoint("LEFT", statsStrip, "LEFT", catX, 0)
                    local cColor = (c == t) and PlanGreenHex() or format("|cff%02x%02x%02x", catColor[1] * 255, catColor[2] * 255, catColor[3] * 255)
                    catFs:SetText(cColor .. catName .. " " .. c .. "/" .. t .. "|r")
                    catX = catX + catFs:GetStringWidth() + 12
                end
            end
        end

        local catChainTail = statsStrip
        local weeklyRowList = { statsStrip }

        for ci = 1, #CATEGORIES do
            local catInfo = CATEGORIES[ci]
            local catKey = catInfo.key
            if plan.questTypes and plan.questTypes[catKey] then
                local questList = (plan.quests and plan.quests[catKey]) or {}
                local display = CAT_DISPLAY[catKey] or {}
                local catColor = display.color or {0.8, 0.8, 0.8}
                local catName = display.name and display.name() or catKey

                local completed, total = GetCategoryStats(plan, catKey)
                local groupKey = "dq_" .. tostring(plan.id) .. "_" .. catKey
                local isExpanded = (expandedGroups[groupKey] == true)

                local SECTION_HDR_H = (GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT) or 36
                local catAtlas = (display and display.atlas) or "questlog-questtypeicon-weekly"
                local catTitleHex = format(
                    "|cff%02x%02x%02x%s|r",
                    math.floor(catColor[1] * 255),
                    math.floor(catColor[2] * 255),
                    math.floor(catColor[3] * 255),
                    catName
                )

                local catWrap = Factory:CreateContainer(charSectionBody, innerW, SECTION_HDR_H + 0.1, false)
                if catWrap.SetClipsChildren then
                    catWrap:SetClipsChildren(true)
                end
                catWrap:ClearAllPoints()
                ChainSectionFrameBelow(charSectionBody, catWrap, catChainTail, 0, sectionSpacing, nil)

                weeklyRowList[#weeklyRowList + 1] = catWrap

                local sectionBody
                local catHeader, hdrExpandIcon, hdrCategoryIcon, catHdrTitleFs = CreateCollapsibleHeader(
                    catWrap,
                    catTitleHex,
                    groupKey,
                    isExpanded,
                    WeeklySectionToggleNoop,
                    catAtlas,
                    true,
                    0,
                    nil,
                    BuildCollapsibleSectionOpts({
                        wrapFrame = catWrap,
                        bodyGetter = function() return sectionBody end,
                        headerHeight = SECTION_HDR_H,
                        hideOnCollapse = true,
                        deferOnToggleUntilComplete = true,
                        persistFn = function(exp)
                            expandedGroups[groupKey] = exp
                        end,
                        onUpdate = function()
                            ReflowWeeklyProgressCharSectionBody(charSectionBody)
                        end,
                        onComplete = function()
                            ReflowWeeklyProgressCharSectionBody(charSectionBody)
                            ScheduleWeeklyProgressScrollSync()
                        end,
                    })
                )
                catHeader:SetPoint("TOPLEFT", catWrap, "TOPLEFT", 0, 0)
                catHeader:SetWidth(innerW)
                catHeader:SetHeight(SECTION_HDR_H)

                sectionBody = Factory:CreateContainer(catWrap, innerW, 0.1, false)
                sectionBody:ClearAllPoints()
                sectionBody:SetPoint("TOPLEFT", catHeader, "BOTTOMLEFT", 0, 0)
                sectionBody:SetPoint("TOPRIGHT", catHeader, "BOTTOMRIGHT", 0, 0)

                if catHeader._wnSectionStripe then
                    catHeader._wnSectionStripe:SetColorTexture(catColor[1], catColor[2], catColor[3], 0.9)
                end
                if hdrExpandIcon and hdrExpandIcon._wnCollapseTex then
                    local r2 = math.min(1, catColor[1] * 1.5)
                    local g2 = math.min(1, catColor[2] * 1.5)
                    local b2 = math.min(1, catColor[3] * 1.5)
                    hdrExpandIcon._wnCollapseTex:SetVertexColor(r2, g2, b2)
                    hdrExpandIcon._wnCollapseVertexColor = { r2, g2, b2, 1 }
                end
                if hdrCategoryIcon then
                    hdrCategoryIcon:SetVertexColor(catColor[1], catColor[2], catColor[3])
                end

                local countHdrFs = FontManager:CreateFontString(catHeader, "body", "OVERLAY")
                countHdrFs:SetPoint("RIGHT", -14, 0)
                local countColorHdr = (completed == total and total > 0) and PlanGreenHex() or PlanBrightHex()
                countHdrFs:SetText(countColorHdr .. completed .. "/" .. total .. "|r")

                if catHdrTitleFs then
                    catHdrTitleFs:SetJustifyH("LEFT")
                    catHdrTitleFs:SetWordWrap(false)
                    catHdrTitleFs:SetMaxLines(1)
                    catHdrTitleFs:SetPoint("RIGHT", countHdrFs, "LEFT", -10, 0)
                end

                local rowY = 4
                if #questList == 0 then
                    local emptyRow
                    emptyRow, rowY = Factory:CreateDataRow(sectionBody, rowY, 1, ROW_H)
                    local emptyIcon = emptyRow:CreateTexture(nil, "ARTWORK")
                    emptyIcon:SetSize(14, 14)
                    emptyIcon:SetPoint("LEFT", 14, 0)
                    emptyIcon:SetAtlas("Objective-Nub", false)
                    emptyIcon:SetVertexColor(0.4, 0.4, 0.4)
                    local emptyFs = FontManager:CreateFontString(emptyRow, "body", "OVERLAY")
                    emptyFs:SetPoint("LEFT", 32, 0)
                    ns.UI_SetTextColorRole(emptyFs, "Dim")
                    emptyFs:SetText((ns.L and ns.L["NO_ACTIVE_CONTENT"]) or "No active content this week")
                else
                    for qi = 1, #questList do
                        local quest = questList[qi]
                        local hasObjectives = (quest.objectives and #quest.objectives > 0) or false
                        local isSub = quest.isSubQuest
                        local leftIndent = isSub and 26 or 14
                        local iconSize = isSub and 12 or 14
                        local nObj = hasObjectives and quest.objectives and #quest.objectives or 0
                        local rowH = ROW_H
                        if hasObjectives and nObj > 0 then
                            rowH = math.max(ROW_H, 14 + 16 * nObj + 18)
                        end

                        local row
                        row, rowY = Factory:CreateDataRow(sectionBody, rowY, qi, rowH)
                        row:EnableMouse(true)

                        local statusIcon = row:CreateTexture(nil, "ARTWORK")
                        statusIcon:SetSize(iconSize, iconSize)
                        if hasObjectives then
                            statusIcon:SetPoint("TOPLEFT", leftIndent, -6)
                        else
                            statusIcon:SetPoint("LEFT", leftIndent, 0)
                        end
                        if quest.isComplete then
                            statusIcon:SetAtlas("common-icon-checkmark", false)
                            statusIcon:SetVertexColor(0.27, 1, 0.27)
                        elseif quest.isLocked then
                            statusIcon:SetAtlas("Padlock", false)
                            statusIcon:SetVertexColor(1, 0.6, 0.2)
                        else
                            statusIcon:SetAtlas("Objective-Nub", false)
                            statusIcon:SetVertexColor(0.6, 0.6, 0.6)
                        end

                        local titleFs = FontManager:CreateFontString(row, isSub and "small" or "body", "OVERLAY")
                        if hasObjectives then
                            titleFs:SetPoint("TOPLEFT", leftIndent + iconSize + 4, -4)
                        else
                            titleFs:SetPoint("LEFT", leftIndent + iconSize + 4, 0)
                        end
                        titleFs:SetWidth(width * 0.50)
                        titleFs:SetJustifyH("LEFT")
                        titleFs:SetWordWrap(false)
                        if quest.isComplete then
                            titleFs:SetText(PlanGreenHex() .. (quest.title or "") .. "|r")
                        elseif quest.isLocked then
                            titleFs:SetText("|cffff9933" .. (quest.title or "") .. "|r")
                        elseif isSub then
                            titleFs:SetText("|cffaaaaaa" .. (quest.title or "") .. "|r")
                        else
                            titleFs:SetText(PlanBrightHex() .. (quest.title or "") .. "|r")
                        end

                        if hasObjectives then
                            local objY = -4
                            for oi = 1, #quest.objectives do
                                local obj = quest.objectives[oi]
                                objY = objY - 16
                                local objIcon = row:CreateTexture(nil, "ARTWORK")
                                objIcon:SetSize(8, 8)
                                objIcon:SetPoint("TOPLEFT", leftIndent + iconSize + 8, objY)
                                if obj.finished then
                                    objIcon:SetAtlas("common-icon-checkmark", false)
                                    objIcon:SetVertexColor(0.27, 1, 0.27)
                                else
                                    objIcon:SetAtlas("Objective-Nub", false)
                                    objIcon:SetVertexColor(0.5, 0.5, 0.5)
                                end

                                local objText = obj.text or format((ns.L and ns.L["OBJECTIVE_INDEX_FORMAT"]) or "Objective %d", oi)
                                local objColor = obj.finished and PlanGreenHex() or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted") or "|cffaaaaaa")
                                local objFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                objFs:SetPoint("TOPLEFT", leftIndent + iconSize + 20, objY + 2)
                                objFs:SetWidth(width * 0.45)
                                objFs:SetJustifyH("LEFT")
                                objFs:SetWordWrap(false)
                                objFs:SetText(objColor .. objText .. "|r")

                                local progFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                progFs:SetPoint("TOPLEFT", leftIndent + iconSize + 20 + width * 0.46, objY + 2)
                                progFs:SetJustifyH("LEFT")
                                local progColor = obj.finished and PlanGreenHex() or PlanGoldHex()
                                progFs:SetText(format("%s%d/%d|r", progColor, obj.numFulfilled, obj.numRequired))
                            end

                            if quest.zone and quest.zone ~= "" then
                                local zoneFs = FontManager:CreateFontString(row, "small", "OVERLAY")
                                zoneFs:SetPoint("TOPRIGHT", -14, -6)
                                zoneFs:SetJustifyH("RIGHT")
                                zoneFs:SetText("|cff888888" .. quest.zone .. "|r")
                            end
                        else
                            local zoneFs = FontManager:CreateFontString(row, "body", "OVERLAY")
                            zoneFs:SetPoint("LEFT", 32 + width * 0.52, 0)
                            zoneFs:SetWidth(width * 0.25)
                            zoneFs:SetJustifyH("LEFT")
                            zoneFs:SetWordWrap(false)
                            zoneFs:SetText(PlanBrightHex() .. (quest.zone or "") .. "|r")

                            if quest.timeLeft and quest.timeLeft > 0 then
                                local timeFs = FontManager:CreateFontString(row, "body", "OVERLAY")
                                timeFs:SetPoint("RIGHT", -14, 0)
                                timeFs:SetText(PlanBrightHex() .. FormatTimeLeft(quest.timeLeft) .. "|r")
                            end
                        end

                        AttachQuestRowTooltip(row, quest)
                    end
                end

                local sectionBodyH = rowY + 4
                sectionBody._wnSectionFullH = math.max(0.1, sectionBodyH)
                if isExpanded then
                    sectionBody:Show()
                    sectionBody:SetHeight(math.max(0.1, sectionBodyH))
                else
                    sectionBody:Hide()
                    sectionBody:SetHeight(0.1)
                end

                local catWrapH = SECTION_HDR_H + (isExpanded and sectionBodyH or 0.1)
                catWrap:SetHeight(catWrapH)
                catChainTail = catWrap
            end
        end

        charSectionBody._weeklyRowList = weeklyRowList
        charSectionBody._weeklySectionSpacing = sectionSpacing
        charSectionBody._weeklyParentWrap = charWrap
        charWrap._weeklyHeaderH = SECTION_COLLAPSE_H

        if charExpanded then
            charSectionBody:Show()
            charSectionBody:SetAlpha(1)
        else
            charSectionBody:Hide()
            charSectionBody:SetHeight(0.1)
        end

        ReflowWeeklyProgressCharSectionBody(charSectionBody)

        if charExpanded then
            local fullH = charSectionBody._wnSectionFullH or 0.1
            charSectionBody:SetHeight(math.max(0.1, fullH))
            charWrap:SetHeight(SECTION_COLLAPSE_H + charSectionBody:GetHeight())
        else
            charSectionBody:Hide()
            charSectionBody:SetHeight(0.1)
            charWrap:SetHeight(SECTION_COLLAPSE_H + 0.1)
        end

        local charTotalH = charWrap:GetHeight()
        totalBlockH = totalBlockH + charTotalH
        weeklyChainTail = charWrap
    end

    return scrollTop + totalBlockH + 10
end

function WarbandNexus:DrawActivePlans(parent, yOffset, width, category)
    if HideEmptyStateCard then
        HideEmptyStateCard(parent, "plans")
        HideEmptyStateCard(parent, "plans_browse")
    end
    if parent.emptyStateContainer then
        parent.emptyStateContainer:Hide()
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
        if ns.UI_ShowTabEmptyStateCard then
            return ns.UI_ShowTabEmptyStateCard(parent, "plans", yOffset, { fillParent = true }) + 10
        end
        local _, height = CreateEmptyStateCard(parent, "plans", yOffset, { fillParent = true })
        return yOffset + height + 10
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

    for i = 1, #plans do
        local plan = plans[i]
        local progress = self:GetResolvedPlanProgress(plan)
        
        if plan.type == "weekly_vault" then
            local weeklyCardHeight = (ns.UI_MeasureFullWidthPlanCardHeight and ns.UI_MeasureFullWidthPlanCardHeight(plan, gridW)) or 174

            -- Create raw card (no base card - weekly vault is fully custom)
            local card = CreateCard(parent, weeklyCardHeight)
            card:EnableMouse(true)
            
            -- Add to layout manager
            local yPos = CardLayoutManager:AddCard(layoutManager, card, 0, weeklyCardHeight)
            
            -- Override positioning to make it full width
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", gridPadH, -yPos)
            card:SetPoint("TOPRIGHT", -gridPadH, -yPos)
            
            -- Update layout manager for full-width card
            layoutManager.currentYOffsets[0] = yPos + weeklyCardHeight + cardSpacing
            layoutManager.currentYOffsets[1] = yPos + weeklyCardHeight + cardSpacing
            
            -- Mark as full width
            card._layoutInfo = card._layoutInfo or {}
            card._layoutInfo.isFullWidth = true
            card._layoutInfo.yPos = yPos
            
            -- Apply accent border (My Plans cards)
            if ApplyVisuals then
                local borderColor = (ns.UI_GetPanelCardBorder and ns.UI_GetPanelCardBorder())
                    or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
                ApplyVisuals(card, COLORS.bgCard, borderColor)
            end
            
            -- Create weekly vault content via factory
            PlanCardFactory:CreateWeeklyVaultCard(card, plan, progress, nil)
            
            card:Show()
        
        elseif plan.type == "daily_quests" then
            local questCardHeight = (ns.UI_MeasureFullWidthPlanCardHeight and ns.UI_MeasureFullWidthPlanCardHeight(plan, gridW)) or 174

            local card = CreateCard(parent, questCardHeight)
            card:EnableMouse(true)
            
            local yPos = CardLayoutManager:AddCard(layoutManager, card, 0, questCardHeight)
            
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", gridPadH, -yPos)
            card:SetPoint("TOPRIGHT", -gridPadH, -yPos)
            
            layoutManager.currentYOffsets[0] = yPos + questCardHeight + cardSpacing
            layoutManager.currentYOffsets[1] = yPos + questCardHeight + cardSpacing
            
            card._layoutInfo = card._layoutInfo or {}
            card._layoutInfo.isFullWidth = true
            card._layoutInfo.yPos = yPos
            
            if ApplyVisuals then
                local borderColor = (ns.UI_GetPanelCardBorder and ns.UI_GetPanelCardBorder())
                    or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }
                ApplyVisuals(card, COLORS.bgCard, borderColor)
            end
            
            PlanCardFactory:CreateDailyQuestCard(card, plan)
            
            card:Show()
        
        else
            local listCardWidth = cardWidth
            local col = (regularCountBefore[i] or 0) % 2
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
            local titleRightInset = 6 + ACTION_SIZE + ACTION_GAP
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

            local hasPtsRow = plan.type == "achievement" and (tonumber(achievementPoints) or 0) > 0
            local summarySlotLines = math.max(#summaryLines, (PCM and PCM.todoUnifiedSlotLines) or 2)
            if #summaryLines == 0 then
                summarySlotLines = (PCM and PCM.todoUnifiedSlotLines) or 2
            end
            local collapsedH = ns.UI_PlansTodoCollapsedHeight and ns.UI_PlansTodoCollapsedHeight(summarySlotLines) or todoHeaderH
            if hasPtsRow and PCM then
                collapsedH = collapsedH + (PCM.todoPointsRowH or 14) + (PCM.todoSummaryGap or 4)
            end
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
                    if CardLayoutManager and CardLayoutManager.UpdateCardHeight then
                        CardLayoutManager:UpdateCardHeight(rowFrame, currentH)
                    end
                    if ns.UI_SyncPlansScrollContentHeight then
                        ns.UI_SyncPlansScrollContentHeight(parent)
                    end
                end,
                onExpandPopulate = achievementOnExpandPopulate,
            }

            local row = CreateExpandableRow(parent, listCardWidth, collapsedH, rowData, isExpanded, function(expanded)
                expandedPlans[plan.id] = expanded
            end)
            if row then
            row:SetWidth(listCardWidth)
            CardLayoutManager:AddCard(layoutManager, row, col, collapsedH)
            if row.isExpanded then
                CardLayoutManager:UpdateCardHeight(row, row:GetHeight())
            end

            if ApplyVisuals then
                local borderColor = { COLORS.accent[1] * 0.8, COLORS.accent[2] * 0.8, COLORS.accent[3] * 0.8, 0.4 }
                ApplyVisuals(row, COLORS.bgCard, borderColor)
            end

            -- Header right rail: Tries + actions vertically centered on the portrait icon.
            local rightOffset = 6
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
            end
        end
    end

    -- Sync row offsets after all cards are added (prevents gaps from mixed-height cards)
    ReflowPlansCardLayout(layoutManager)
    if ns.UI_SyncPlansScrollContentHeight then
        ns.UI_SyncPlansScrollContentHeight(parent)
    end

    -- Get final Y offset from layout manager
    local finalYOffset = CardLayoutManager:GetFinalYOffset(layoutManager)
    
    return finalYOffset
end

-- EVENT HANDLERS

--[[
    Handle WN_PLANS_UPDATED event
    Only refreshes if Plans tab is visible (event-driven, no polling)
]]
-- REMOVED: OnPlansUpdated — UI.lua's SchedulePopulateContent handles WN_PLANS_UPDATED centrally.

-- BROWSER (Mounts, Pets, Toys, Recipes)


-- CUSTOM PLAN DIALOG

function WarbandNexus:ShowCustomPlanDialog()
    -- Disable Add Custom button to prevent multiple dialogs
    if self.addCustomBtn then
        self.addCustomBtn:Disable()
        self.addCustomBtn:SetAlpha(0.5)
    end

    -- Get character info
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "CustomPlanDialog",
        title = (ns.L and ns.L["CREATE_CUSTOM_PLAN"]) or "Create Custom Plan",
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,
        width = 450,
        height = 500,  -- Title + description + reset cycle + duration + infinite option
        onClose = function()
            -- Re-enable Add Custom button
            if WarbandNexus.addCustomBtn then
                WarbandNexus.addCustomBtn:Enable()
                WarbandNexus.addCustomBtn:SetAlpha(1)
            end
        end
    })
    
    -- If dialog creation failed (duplicate), return
    if not dialog then
        if self.addCustomBtn then
            self.addCustomBtn:Enable()
            self.addCustomBtn:SetAlpha(1)
        end
        return
    end
    
    -- Character section with icon (using Factory pattern)
    local charFrame = ns.UI.Factory:CreateContainer(contentFrame, 420, 45)
    charFrame:SetPoint("TOP", 0, -15)
    
    -- Get race-gender info
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player")
    local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
    
    -- Character race icon with border (using Factory pattern)
    local iconContainer = ns.UI.Factory:CreateContainer(charFrame, 36, 36)
    iconContainer:SetPoint("LEFT", 12, 0)
    
    -- Apply border with class color
    if ApplyVisuals then
        if classColors then
            ApplyVisuals(iconContainer, COLORS.bgCard, {classColors.r, classColors.g, classColors.b, 1})
        else
            ApplyVisuals(iconContainer, COLORS.bgCard, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
        end
    end
    
    -- Character race icon (using atlas)
    local charIconFrame = CreateIcon(iconContainer, raceAtlas, 28, true, nil, true)
    charIconFrame:SetPoint("CENTER", 0, 0)
    charIconFrame:Show()
    
    -- Character name with class color (larger font)
    local charText = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", 10, 0)
    if classColors then
        charText:SetTextColor(classColors.r, classColors.g, classColors.b)
    elseif ns.UI_GetSemanticGoldColor then
        local gr, gg, gb = ns.UI_GetSemanticGoldColor()
        charText:SetTextColor(gr, gg, gb)
    else
        charText:SetTextColor(1, 0.8, 0)
    end
    charText:SetText(currentName .. "-" .. currentRealm)
    
    -- Title label
    local titleLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    titleLabel:SetPoint("TOPLEFT", 12, -75)
    local mutedHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffaaaaaa"
    titleLabel:SetText(mutedHex .. ((ns.L and ns.L["TITLE_LABEL"]) or "Title:") .. "|r")
    
    -- Title input container (using Factory pattern)
    local titleInputBg = ns.UI.Factory:CreateContainer(contentFrame, 410, 35)
    titleInputBg:SetPoint("TOPLEFT", 12, -97)
    
    -- Apply border to input
    if ApplyVisuals then
        ApplyVisuals(titleInputBg, COLORS.bgCard, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    local titleInput = ns.UI.Factory:CreateEditBox(titleInputBg)
    titleInput:SetSize(395, 30)
    titleInput:SetPoint("LEFT", 8, 0)
    ns.UI_SetTextColorRole(titleInput, "Bright")
    titleInput:SetAutoFocus(false)
    titleInput:SetMaxLetters(32)  -- Max 32 characters
    titleInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    titleInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    -- Prevent Enter key from creating new lines
    titleInput:SetScript("OnChar", function(self, char)
        if char == "\n" or char == "\r" then
            local text = self:GetText()
            if not text or (issecretvalue and issecretvalue(text)) then return end
            self:SetText(text:gsub("[\n\r]", ""))
        end
    end)
    
    -- Make container clickable to focus EditBox
    titleInputBg:EnableMouse(true)
    titleInputBg:SetScript("OnMouseDown", function()
        titleInput:SetFocus()
    end)
    
    -- Description label
    local descLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    descLabel:SetPoint("TOPLEFT", 12, -145)
    descLabel:SetText(mutedHex .. NormalizeColonLabelSpacing((ns.L and ns.L["DESCRIPTION_LABEL"]) or "Description:") .. "|r")
    
    -- Description input container (scrollable, single line) (using Factory pattern)
    local descInputBg = ns.UI.Factory:CreateContainer(contentFrame, 410, 35)  -- Reduced height for single line
    descInputBg:SetPoint("TOPLEFT", 12, -167)
    
    -- Apply border to input
    if ApplyVisuals then
        ApplyVisuals(descInputBg, COLORS.bgCard, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6})
    end
    
    local descInput = ns.UI.Factory:CreateEditBox(descInputBg)
    descInput:SetSize(395, 30)
    descInput:SetPoint("LEFT", 8, 0)
    ns.UI_SetTextColorRole(descInput, "Bright")
    descInput:SetAutoFocus(false)
    descInput:SetMultiLine(false)  -- Single line only - prevents Enter from creating new lines
    descInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    descInput:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    -- Limit to 300 characters total, max 30 characters per word
    descInput:SetScript("OnTextChanged", function(self)
        local text = self:GetText()
        if not text then return end
        if issecretvalue and issecretvalue(text) then return end
        -- Remove any newlines that might have been inserted
        text = text:gsub("[\n\r]", " ")
        
        -- Enforce word length limit (max 30 chars per word)
        local maxWordLength = 30
        local words = {}
        local modified = false
        
        for word in text:gmatch("%S+") do  -- Split by whitespace
            if string.len(word) > maxWordLength then
                -- Truncate long word
                word = string.sub(word, 1, maxWordLength)
                modified = true
            end
            table.insert(words, word)
        end
        
        -- Reconstruct text with single spaces
        if modified then
            text = table.concat(words, " ")
        end
        
        -- Enforce 300 character limit
        local maxChars = 300
        if string.len(text) > maxChars then
            text = string.sub(text, 1, maxChars)
            modified = true
        end
        
        -- Update text if modified
        if modified then
            local cur = self:GetText()
            if cur and issecretvalue and issecretvalue(cur) then return end
            if text ~= cur then
                local cursorPos = self:GetCursorPosition()
                self:SetText(text)
                self:SetCursorPosition(math.min(cursorPos, string.len(text)))
            end
        end
    end)
    
    -- Prevent Enter key from creating new lines
    descInput:SetScript("OnChar", function(self, char)
        if char == "\n" or char == "\r" then
            local text = self:GetText()
            if not text or (issecretvalue and issecretvalue(text)) then return end
            local cursorPos = self:GetCursorPosition()
            self:SetText(text:gsub("[\n\r]", " "))
            self:SetCursorPosition(cursorPos)
        end
    end)
    
    -- Make container clickable to focus EditBox
    descInputBg:EnableMouse(true)
    descInputBg:SetScript("OnMouseDown", function()
        descInput:SetFocus()
    end)
    
    -- Reset Cycle selection
    local resetLabel = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    resetLabel:SetPoint("TOPLEFT", 12, -215)
    resetLabel:SetText(mutedHex .. ((ns.L and ns.L["RESET_CYCLE_LABEL"]) or "Reset Cycle:") .. "|r")
    
    local PlanDlgF = ns.UI and ns.UI.Factory
    
    --- Factory rows use BORDER_REGISTRY textures (UpdateBorderColor); legacy uses SetBackdropBorderColor.
    local function PlanDlgPulseBorder(btn, borderRgb)
        if not btn then return end
        if btn.BorderTop and UpdateBorderColor then
            UpdateBorderColor(btn, borderRgb)
        elseif btn.SetBackdropBorderColor then
            local r, g, b, a = borderRgb[1], borderRgb[2], borderRgb[3], borderRgb[4] or 1
            btn:SetBackdropBorderColor(r, g, b, a)
        end
    end

    -- Reset cycle toggle state
    local selectedResetType = "none"
    local selectedCycleCount = 7  -- Default cycle count
    local selectedInfiniteRepeat = false
    
    local function CreateResetToggle(parent, label, value, xOffset)
        local btn = PlanDlgF and PlanDlgF:CreateButton(parent, 120, 28, false)
        if btn then btn._wnPlanDlgFactoryToggle = true end
        if not btn then
            btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
            btn:SetBackdrop({
                bgFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeFile = "Interface\\BUTTONS\\WHITE8X8",
                edgeSize = 1,
                insets = { left = 1, right = 1, top = 1, bottom = 1 },
            })
            btn:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1)
            btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
        elseif ApplyVisuals then
            ApplyVisuals(btn, { COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1 },
                { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
        end
        btn:SetPoint("TOPLEFT", xOffset, -237)

        local text = FontManager:CreateFontString(btn, "body", "OVERLAY")
        text:SetPoint("CENTER")
        text:SetText(label)
        ns.UI_SetTextColorRole(text, "Muted")
        btn.label = text
        btn.value = value

        return btn
    end
    
    local resetBtnNone = CreateResetToggle(contentFrame, (ns.L and ns.L["RESET_NONE"]) or "None", "none", 12)
    local resetBtnDaily = CreateResetToggle(contentFrame, (ns.L and ns.L["DAILY_RESET"]) or "Daily Reset", "daily", 142)
    local resetBtnWeekly = CreateResetToggle(contentFrame, (ns.L and ns.L["WEEKLY_RESET"]) or "Weekly Reset", "weekly", 272)
    
    local resetButtons = { resetBtnNone, resetBtnDaily, resetBtnWeekly }
    
    -- Duration row (hidden by default, shown when Daily/Weekly selected)
    local durationRow = PlanDlgF and PlanDlgF:CreateContainer(contentFrame, 420, 54, false)
    if not durationRow then
        durationRow = CreateFrame("Frame", nil, contentFrame)
        durationRow:SetSize(420, 54)
    end
    durationRow:SetPoint("TOPLEFT", 12, -275)
    durationRow:Hide()
    
    local durationLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    durationLabel:SetPoint("TOPLEFT", 0, -2)
    ns.UI_SetTextColorRole(durationLabel, "Muted")
    
    -- Minus button (paired with Factory +plusBtn where SharedWidgets Factory is live)
    local minusBtn = PlanDlgF and PlanDlgF:CreateButton(durationRow, 28, 28, false)
    if minusBtn then minusBtn._wnPlanDlgDurStepper = true end
    local chromeBg = ControlChromeBackdrop()
    if not minusBtn then
        minusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
        minusBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        minusBtn:SetBackdropColor(chromeBg[1], chromeBg[2], chromeBg[3], chromeBg[4] or 1)
        minusBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    elseif ApplyVisuals then
        ApplyVisuals(minusBtn, chromeBg, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end
    minusBtn:SetPoint("TOPLEFT", 160, -2)
    local minusText = FontManager:CreateFontString(minusBtn, "title", "OVERLAY")
    minusText:SetPoint("CENTER", 0, 1)
    minusText:SetText("-")
    ns.UI_SetTextColorRole(minusText, "Bright")
    
    -- Count display
    local countDisplay = FontManager:CreateFontString(durationRow, "title", "OVERLAY")
    countDisplay:SetPoint("TOPLEFT", minusBtn, "TOPRIGHT", 12, 0)
    ns.UI_SetTextColorRole(countDisplay, "Bright")
    countDisplay:SetWidth(30)
    countDisplay:SetJustifyH("CENTER")
    
    local plusBtn = PlanDlgF and PlanDlgF:CreateButton(durationRow, 28, 28, false)
    if plusBtn then plusBtn._wnPlanDlgDurStepper = true end
    if not plusBtn then
        plusBtn = CreateFrame("Button", nil, durationRow, "BackdropTemplate")
        plusBtn:SetBackdrop({
            bgFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeFile = "Interface\\BUTTONS\\WHITE8X8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        plusBtn:SetBackdropColor(chromeBg[1], chromeBg[2], chromeBg[3], chromeBg[4] or 1)
        plusBtn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
    elseif ApplyVisuals then
        ApplyVisuals(plusBtn, chromeBg, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end
    plusBtn:SetPoint("TOPLEFT", countDisplay, "TOPRIGHT", 12, 0)
    local plusText = FontManager:CreateFontString(plusBtn, "title", "OVERLAY")
    plusText:SetPoint("CENTER", 0, 1)
    plusText:SetText("+")
    ns.UI_SetTextColorRole(plusText, "Bright")
    
    -- Update duration display
    local function UpdateDurationDisplay()
        countDisplay:SetText(tostring(selectedCycleCount))
        durationLabel:SetText(((ns.L and ns.L["DURATION_LABEL"]) or "Duration") .. ":  ")
    end
    
    -- Unit label after count
    local unitLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    unitLabel:SetPoint("TOPLEFT", plusBtn, "TOPRIGHT", 10, 0)
    ns.UI_SetTextColorRole(unitLabel, "Muted")

    local foreverCb = CreateThemedCheckbox(durationRow, false)
    if foreverCb then
        foreverCb:SetPoint("TOPLEFT", durationRow, "TOPLEFT", 0, -34)
    end
    local foreverLabel = FontManager:CreateFontString(durationRow, "body", "OVERLAY")
    if foreverCb then
        foreverLabel:SetPoint("LEFT", foreverCb, "RIGHT", 8, 0)
    else
        foreverLabel:SetPoint("TOPLEFT", durationRow, "TOPLEFT", 0, -34)
    end
    foreverLabel:SetPoint("TOPRIGHT", durationRow, "TOPRIGHT", 0, -34)
    foreverLabel:SetJustifyH("LEFT")
    ns.UI_SetTextColorRole(foreverLabel, "Muted")
    foreverLabel:SetWordWrap(true)
    foreverLabel:SetMaxLines(2)
    foreverLabel:SetText((ns.L and ns.L["CUSTOM_PLAN_REPEAT_UNTIL_REMOVED"]) or "Repeat until this plan is deleted")
    
    local function UpdateUnitLabel()
        if selectedResetType == "daily" then
            unitLabel:SetText((ns.L and ns.L["DAYS_LABEL"]) or "days")
        elseif selectedResetType == "weekly" then
            unitLabel:SetText((ns.L and ns.L["WEEKS_LABEL"]) or "weeks")
        end
    end
    
    minusBtn:SetScript("OnClick", function()
        if selectedCycleCount > 1 then
            selectedCycleCount = selectedCycleCount - 1
            UpdateDurationDisplay()
        end
    end)
    minusBtn:SetScript("OnEnter", function(self)
        PlanDlgPulseBorder(self, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
    end)
    minusBtn:SetScript("OnLeave", function(self)
        PlanDlgPulseBorder(self, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end)
    
    plusBtn:SetScript("OnClick", function()
        if selectedCycleCount < 99 then
            selectedCycleCount = selectedCycleCount + 1
            UpdateDurationDisplay()
        end
    end)
    plusBtn:SetScript("OnEnter", function(self)
        PlanDlgPulseBorder(self, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
    end)
    plusBtn:SetScript("OnLeave", function(self)
        PlanDlgPulseBorder(self, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
    end)

    local function UpdateInfiniteDurationUI()
        if foreverCb then
            foreverCb:SetChecked(selectedInfiniteRepeat)
            if foreverCb.innerDot then
                foreverCb.innerDot:SetShown(selectedInfiniteRepeat)
            end
        end
        if selectedInfiniteRepeat then
            minusBtn:Disable()
            plusBtn:Disable()
            countDisplay:SetWidth(56)
            countDisplay:SetText("--")
            unitLabel:SetText("")
        else
            minusBtn:Enable()
            plusBtn:Enable()
            countDisplay:SetWidth(30)
            UpdateDurationDisplay()
            UpdateUnitLabel()
        end
    end

    if foreverCb then
        foreverCb:SetScript("OnClick", function(self)
            local checked = self:GetChecked()
            if self.innerDot then
                self.innerDot:SetShown(checked)
            end
            selectedInfiniteRepeat = (checked == true or checked == 1)
            UpdateInfiniteDurationUI()
        end)
    end
    
    -- Update button visuals based on selection
    local function UpdateResetButtons()
        for bi = 1, #resetButtons do
            local btn = resetButtons[bi]
            if btn._wnPlanDlgFactoryToggle and ApplyVisuals then
                if btn.value == selectedResetType then
                    ApplyVisuals(btn,
                        { COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1 },
                        { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1 })
                else
                    ApplyVisuals(btn,
                        { COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1 },
                        { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
                end
                btn.label:SetTextColor((btn.value == selectedResetType) and 1 or 0.7,
                    (btn.value == selectedResetType) and 1 or 0.7,
                    (btn.value == selectedResetType) and 1 or 0.7)
            elseif btn.value == selectedResetType then
                btn:SetBackdropColor(COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1)
                btn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
                ns.UI_SetTextColorRole(btn.label, "Bright")
            else
                btn:SetBackdropColor(COLORS.bgCard[1], COLORS.bgCard[2], COLORS.bgCard[3], COLORS.bgCard[4] or 1)
                btn:SetBackdropBorderColor(COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6)
                ns.UI_SetTextColorRole(btn.label, "Muted")
            end
        end
        
        -- Show/hide duration row based on selection
        if selectedResetType == "none" then
            selectedInfiniteRepeat = false
            durationRow:Hide()
        else
            -- Set default cycle counts based on type
            if selectedResetType == "daily" then
                selectedCycleCount = math.max(1, math.min(selectedCycleCount, 99))
            elseif selectedResetType == "weekly" then
                selectedCycleCount = math.max(1, math.min(selectedCycleCount, 99))
            end
            UpdateDurationDisplay()
            UpdateUnitLabel()
            UpdateInfiniteDurationUI()
            durationRow:Show()
        end
    end
    
    for bi = 1, #resetButtons do
        local btn = resetButtons[bi]
        btn:SetScript("OnClick", function(self)
            selectedResetType = self.value
            -- Set sensible defaults when switching type
            if self.value == "daily" then
                selectedCycleCount = 7
            elseif self.value == "weekly" then
                selectedCycleCount = 4
            end
            UpdateResetButtons()
        end)
        btn:SetScript("OnEnter", function(self)
            if self.value ~= selectedResetType then
                PlanDlgPulseBorder(self, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
            end
        end)
        btn:SetScript("OnLeave", function(self)
            if self.value ~= selectedResetType then
                PlanDlgPulseBorder(self, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
            end
        end)
    end
    
    -- Set initial state (None selected)
    UpdateResetButtons()
    
    -- Buttons (symmetrically centered with more spacing from inputs)
    local saveBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["SAVE"]) or "Save", 100)
    saveBtn:SetPoint("BOTTOM", -55, 12)
    saveBtn:SetScript("OnClick", function()
        local title = titleInput:GetText()
        local description = descInput:GetText()
        if title and issecretvalue and issecretvalue(title) then return end
        if description and issecretvalue and issecretvalue(description) then
            description = nil
        end
        
        if title and title ~= "" then
            local cycleCount = (selectedResetType ~= "none") and selectedCycleCount or nil
            local infiniteRepeat = (selectedResetType ~= "none") and selectedInfiniteRepeat or false
            WarbandNexus:SaveCustomPlan(title, description, selectedResetType, cycleCount, infiniteRepeat)
            dialog.Close()
        end
    end)
    
    local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", 100)
    cancelBtn:SetPoint("BOTTOM", 55, 12)
    cancelBtn:SetScript("OnClick", function()
        dialog.Close()
    end)
    
    dialog:Show()
    titleInput:SetFocus()
end

-- CUSTOM PLAN STORAGE

function WarbandNexus:SaveCustomPlan(title, description, resetType, cycleCount, infiniteRepeat)
    if not self.db.global.customPlans then
        self.db.global.customPlans = {}
    end

    local wantInfinite = infiniteRepeat and resetType and resetType ~= "none"
    local finiteCount = (not wantInfinite and cycleCount) or nil
    if not wantInfinite and (not finiteCount or finiteCount < 1) then
        finiteCount = 1
    end
    
    local customPlan = {
        id = "custom_" .. time() .. "_" .. math.random(1000, 9999),
        type = "custom",
        name = title,
        source = description or ((ns.L and ns.L["CUSTOM_PLAN_SOURCE"]) or "Custom plan"),
        icon = "Bonus-Objective-Star",  -- Use atlas for custom plans
        iconIsAtlas = true,  -- Mark as atlas
        isCustom = true,
        completed = false,
        resetCycle = (resetType and resetType ~= "none") and {
            enabled = true,
            resetType = resetType,
            lastResetTime = time(),
            infiniteRepeat = wantInfinite or false,
            totalCycles = wantInfinite and nil or finiteCount,
            remainingCycles = wantInfinite and nil or finiteCount,
        } or nil,
    }
    
    table.insert(self.db.global.customPlans, customPlan)

    -- Resolve display data immediately so My Plans renders complete info
    if self._ResolveSinglePlan then
        self:_ResolveSinglePlan(customPlan, time())
    end
    self:SendMessage(E.PLANS_UPDATED, {
        action = "custom_created",
        planID = customPlan.id,
    })
end

function WarbandNexus:GetCustomPlans()
    return self.db.global.customPlans or {}
end

function WarbandNexus:CompleteCustomPlan(planId)
    if not self.db.global.customPlans then return false end

    local customPlansList = self.db.global.customPlans
    for pi = 1, #customPlansList do
        local plan = customPlansList[pi]
        if plan.id == planId then
            if plan.completed then return true end -- Already completed
            
            plan.completed = true
            self:Print(format((ns.L and ns.L["CUSTOM_PLAN_COMPLETED"]) or "Custom plan '%s' %scompleted|r", FormatTextNumbers(plan.name), PlanGreenHex()))

            -- Track completion time for recurring reset
            if plan.resetCycle and plan.resetCycle.enabled then
                plan.resetCycle.completedAt = time()
            end

            -- Fire event immediately so UI refreshes instantly
            self:SendMessage(E.PLANS_UPDATED, {
                action = "completed",
                planID = plan.id,
            })

            -- Notification deferred slightly so UI refresh completes first
            if self.Notify then
                local planName = FormatTextNumbers(plan.name)
                local planIcon = plan.icon
                C_Timer.After(0.1, function()
                    if WarbandNexus and WarbandNexus.Notify then
                        WarbandNexus:Notify("plan", planName, planIcon)
                    end
                end)
            end

            return true
        end
    end
    return false
end

function WarbandNexus:RemoveCustomPlan(planId)
    if not self.db.global.customPlans then return end
    
    for i = 1, #self.db.global.customPlans do
        local plan = self.db.global.customPlans[i]
        if plan.id == planId then
            table.remove(self.db.global.customPlans, i)
            break
        end
    end
end

-- WEEKLY VAULT PLAN DIALOG

function WarbandNexus:ShowWeeklyPlanDialog()
    local COLORS = ns.UI_COLORS
    local VAULT_DLG_W = 640
    local VAULT_DLG_H_HAS = 280
    local VAULT_DLG_H_NEW = 468

    -- Get current character info
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    
    -- Check if current character already has a weekly plan
    local existingPlan = self:HasActiveWeeklyPlan(currentName, currentRealm)
    
    -- Create external window using helper
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "WeeklyPlanDialog",
        title = (ns.L and ns.L["WEEKLY_VAULT_TRACKER"]) or "Weekly Vault Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",  -- Same as Daily Quest
        width = VAULT_DLG_W,
        height = existingPlan and VAULT_DLG_H_HAS or VAULT_DLG_H_NEW
    })
    
    -- If dialog creation failed (duplicate), return
    if not dialog then
        return
    end
    
    -- Content area starts at top of content frame
    local contentY = -12
    
    -- Show existing plan message or creation form
    if existingPlan then
        -- Character already has a weekly plan
        local warningIconFrame3 = CreateIcon(contentFrame, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertOther", 48, false, nil, true)
        warningIconFrame3:SetPoint("TOP", 0, contentY)
        warningIconFrame3:Show()
        local warningIcon = warningIconFrame3.texture
        
        local warningText = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
        warningText:SetPoint("TOP", warningIcon, "BOTTOM", 0, -15)
        warningText:SetText("|cffff9900" .. ((ns.L and ns.L["WEEKLY_PLAN_EXISTS"]) or "Weekly Plan Already Exists") .. "|r")
        
        local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -10)
        infoText:SetWidth(VAULT_DLG_W - 48)
        infoText:SetWordWrap(true)
        infoText:SetJustifyH("CENTER")
        local descText = (ns.L and ns.L["WEEKLY_PLAN_EXISTS_DESC"] and format(ns.L["WEEKLY_PLAN_EXISTS_DESC"], currentName .. "-" .. currentRealm)) or (currentName .. "-" .. currentRealm .. " already has an active weekly vault plan. You can find it in the 'My Plans' category.")
        infoText:SetText("|cffaaaaaa" .. descText .. "|r")
        
        -- Calculate text height to position button below
        local textHeight = infoText:GetStringHeight()
        
        -- OK button (positioned below text)
        local okBtn = CreateThemedButton(contentFrame, OKAY or "OK", 120)
        okBtn:SetPoint("TOP", infoText, "BOTTOM", 0, -20)
        okBtn:SetScript("OnClick", function()
            dialog.Close()
        end)
    else
        -- Create new weekly plan form
        
        -- Same horizontal band as the three vault cards (content inset 8+8, row padding 20+20).
        local charBarW = VAULT_DLG_W - 16 - 40
        local charFrame = ns.UI.Factory:CreateContainer(contentFrame, charBarW, 48)
        charFrame:SetPoint("TOP", 0, -14)
        
        -- Character race and class info
        local _, currentClass = UnitClass("player")
        local classColors = RAID_CLASS_COLORS[currentClass]
        local _, englishRace = UnitRace("player")
        local gender = UnitSex("player")
        local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
        
        -- Character race icon with border (centered within charFrame) (using Factory pattern)
        local iconContainer = ns.UI.Factory:CreateContainer(charFrame, 36, 36)
        iconContainer:SetPoint("LEFT", 0, 0)  -- Start from left edge
        
        -- Apply border with class color
        if ApplyVisuals then
            if classColors then
                ApplyVisuals(iconContainer, COLORS.bgCard, {classColors.r, classColors.g, classColors.b, 1})
            else
                ApplyVisuals(iconContainer, COLORS.bgCard, {COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.8})
            end
        end
        
        -- Character race icon (using atlas)
        local charIconFrame = CreateIcon(iconContainer, raceAtlas, 28, true, nil, true)
        charIconFrame:SetPoint("CENTER", 0, 0)
        charIconFrame:Show()
        
        -- Character name with class color (larger font)
        local charName = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
        charName:SetPoint("LEFT", iconContainer, "RIGHT", 10, 0)
        if classColors then
            charName:SetTextColor(classColors.r, classColors.g, classColors.b)
        else
            ns.UI_SetTextColorRole(charName, "Bright")
        end
        charName:SetText(currentName .. "-" .. currentRealm)
        
        -- Current progress preview (if API available)
        local progress = self:GetWeeklyVaultProgress(currentName, currentRealm)
        
        -- Fallback: If API not ready, use 0/0/0 progress
        if not progress then
            progress = {
                dungeonCount = 0,
                raidBossCount = 0,
                worldActivityCount = 0
            }
        end
        
        -- Weekly plan: which vault rows to track (toggled by clicking Mythic+ / Raids / World cards)
        local selectedSlots = { dungeon = true, raid = true, world = true }
        local slotColumnRefreshers = {}
        local function RefreshWeeklyPlanSlotSelections()
            for ri = 1, #slotColumnRefreshers do
                slotColumnRefreshers[ri]()
            end
        end

        if progress then
            local progressHeader = FontManager:CreateFontString(contentFrame, "header", "OVERLAY")
            progressHeader:SetPoint("TOP", 0, -78)
            ns.UI_SetTextColorRole(progressHeader, "Bright")
            progressHeader:SetText((ns.L and ns.L["CURRENT_PROGRESS"]) or "Current Progress")

            -- Card row: three equal columns; width from dialog shell (content not always laid out yet).
            local contentW = math.max(120, VAULT_DLG_W - 16)
            local rowSidePad = 20
            local colSpacing = 16
            local usable = contentW - 2 * rowSidePad
            local colWidth = math.floor((usable - 2 * colSpacing) / 3)
            local totalWidth = colWidth * 3 + colSpacing * 2
            -- Card height = icon + title + slot row + padding (no per-slot panel fills).
            local ICON_TOP_PAD = 10
            local ICON_SIZE = 48
            local TITLE_UNDER_ICON = 6
            local TITLE_BLOCK = 26
            local BAND_TOP_GAP = 6
            local SLOT_STAR = 24
            local SLOT_STAR_TEXT_GAP = 6
            local SLOT_TEXT_BLOCK = 22
            local CARD_BOTTOM_PAD = 10
            local slotsBandH = SLOT_STAR + SLOT_STAR_TEXT_GAP + SLOT_TEXT_BLOCK
            local colHeight = ICON_TOP_PAD + ICON_SIZE + TITLE_UNDER_ICON + TITLE_BLOCK + BAND_TOP_GAP + slotsBandH + CARD_BOTTOM_PAD
            local startX = -(totalWidth / 2) + (colWidth / 2)
            local accentBorder = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.95 }
            local unselectedBorder = { 0.32, 0.32, 0.36, 0.8 }
            local disabledBorder = { 0.22, 0.22, 0.25, 0.45 }
            local baseBg = COLORS.bgLight
            local unselBg = COLORS.bg
            local disabledBg = COLORS.bg

            local function CreateProgressCol(index, iconAtlas, title, current, thresholds, slotKey)
                local xPos = startX + (index - 1) * (colWidth + colSpacing)
                local maxThreshold = thresholds[#thresholds] or 0
                local fullyComplete = maxThreshold > 0 and (current >= maxThreshold)
                if fullyComplete then
                    selectedSlots[slotKey] = false
                end

                local col = ns.UI.Factory:CreateContainer(contentFrame, colWidth, colHeight)
                col:SetPoint("TOP", xPos, -100)
                col:SetClipsChildren(true)

                -- Large category icon
                local iconFrame2 = CreateIcon(col, iconAtlas, ICON_SIZE, true, nil, true)
                iconFrame2:SetPoint("TOP", 0, -ICON_TOP_PAD)
                iconFrame2:Show()

                local titleText = FontManager:CreateFontString(col, "title", "OVERLAY")
                titleText:SetWidth(colWidth - 10)
                titleText:SetWordWrap(true)
                if titleText.SetMaxLines then titleText:SetMaxLines(2) end
                titleText:SetJustifyH("CENTER")
                titleText:SetPoint("TOP", iconFrame2, "BOTTOM", 0, -TITLE_UNDER_ICON)
                ns.UI_SetTextColorRole(titleText, "Bright")
                titleText:SetText(title)

                -- Three vault slots in a row: star + text only (no slot panel background).
                local bandPad = 8
                local PUF = ns.UI and ns.UI.Factory
                local slotsBand = PUF and PUF:CreateContainer(col, math.max(40, colWidth - bandPad * 2), slotsBandH, false)
                if not slotsBand then
                    slotsBand = CreateFrame("Frame", nil, col)
                end
                slotsBand:SetSize(colWidth - bandPad * 2, slotsBandH)
                slotsBand:SetPoint("TOP", titleText, "BOTTOM", 0, -BAND_TOP_GAP)

                local nSlots = #thresholds
                local slotGap = 8
                local slotW = (slotsBand:GetWidth() - (nSlots - 1) * slotGap) / nSlots

                for ti = 1, nSlots do
                    local box = PUF and PUF:CreateContainer(slotsBand, math.max(8, slotW), slotsBandH, false)
                    if not box then
                        box = CreateFrame("Frame", nil, slotsBand)
                    end
                    box:SetSize(slotW, slotsBandH)
                    box:SetPoint("TOPLEFT", slotsBand, "TOPLEFT", (ti - 1) * (slotW + slotGap), 0)

                    local isComplete = current >= thresholds[ti]

                    local starTex = box:CreateTexture(nil, "ARTWORK")
                    starTex:SetSize(SLOT_STAR, SLOT_STAR)
                    starTex:SetPoint("TOP", box, "TOP", 0, -2)
                    starTex:SetAtlas("PetJournal-FavoritesIcon")
                    if isComplete then
                        starTex:SetVertexColor(1, 0.9, 0.25)
                    else
                        starTex:SetVertexColor(0.32, 0.32, 0.34)
                    end

                    local milestoneText = FontManager:CreateFontString(box, "subtitle", "OVERLAY")
                    milestoneText:SetWidth(slotW - 4)
                    milestoneText:SetPoint("TOP", starTex, "BOTTOM", 0, -SLOT_STAR_TEXT_GAP)
                    milestoneText:SetJustifyH("CENTER")
                    if milestoneText.SetJustifyV then milestoneText:SetJustifyV("MIDDLE") end
                    if isComplete then
                        if ns.UI_GetSemanticGreenColor then
                            local gr, gg, gb = ns.UI_GetSemanticGreenColor()
                            milestoneText:SetTextColor(gr, gg, gb)
                        else
                            milestoneText:SetTextColor(0.35, 1, 0.4)
                        end
                    else
                        ns.UI_SetTextColorRole(milestoneText, "Muted")
                    end
                    milestoneText:SetText(
                        format("%s / %s", FormatNumber(math.min(current, thresholds[ti])), FormatNumber(thresholds[ti]))
                    )
                end

                local clickPad = PUF and PUF:CreateButton(col, math.max(40, colWidth), 120, true)
                if not clickPad then
                    clickPad = CreateFrame("Button", nil, col)
                end
                clickPad:SetAllPoints()
                clickPad:SetFrameLevel((col:GetFrameLevel() or 0) + 25)
                clickPad:RegisterForClicks("LeftButtonUp")
                clickPad:EnableMouse(not fullyComplete)
                local hl = clickPad:CreateTexture(nil, "HIGHLIGHT")
                hl:SetAllPoints()
                hl:SetColorTexture(1, 1, 1, 0.08)
                clickPad:SetHighlightTexture(hl)
                if fullyComplete then
                    clickPad:Hide()
                end
                clickPad:SetScript("OnClick", function(_, btn)
                    if btn ~= "LeftButton" or fullyComplete then return end
                    selectedSlots[slotKey] = not selectedSlots[slotKey]
                    RefreshWeeklyPlanSlotSelections()
                end)

                local function refreshThisColumn()
                    if fullyComplete then
                        if ApplyVisuals then
                            ApplyVisuals(col, disabledBg, disabledBorder)
                        end
                        col:SetAlpha(0.42)
                        clickPad:Hide()
                    elseif selectedSlots[slotKey] then
                        if ApplyVisuals then
                            ApplyVisuals(col, baseBg, accentBorder)
                        end
                        col:SetAlpha(1)
                        clickPad:Show()
                        clickPad:EnableMouse(true)
                    else
                        if ApplyVisuals then
                            ApplyVisuals(col, unselBg, unselectedBorder)
                        end
                        col:SetAlpha(0.58)
                        clickPad:Show()
                        clickPad:EnableMouse(true)
                    end
                end
                table.insert(slotColumnRefreshers, refreshThisColumn)
                refreshThisColumn()
            end
            
            -- Dungeons (column 1)
            CreateProgressCol(
                1,
                "questlog-questtypeicon-heroic",
                (ns.L and ns.L["MYTHIC_PLUS_LABEL"]) or "Mythic+",
                progress.dungeonCount,
                {1, 4, 8},  -- Thresholds
                "dungeon"
            )
            
            -- Raids (column 2)
            CreateProgressCol(
                2,
                "questlog-questtypeicon-raid",
                (ns.L and ns.L["RAIDS_LABEL"]) or "Raids",
                progress.raidBossCount,
                {2, 4, 6},  -- Thresholds
                "raid"
            )
            
            -- World (column 3)
            CreateProgressCol(
                3,
                "questlog-questtypeicon-Delves",
                (ns.L and ns.L["QUEST_CAT_WORLD"]) or "World",
                progress.worldActivityCount,
                {2, 4, 8},  -- Thresholds
                "world"
            )
            
            contentY = contentY - 95
        end
        
        -- Buttons (symmetrically centered)
        local createBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["CREATE_PLAN"]) or "Create Plan", 120)
        createBtn:SetPoint("BOTTOM", -65, 8)
        createBtn:SetScript("OnClick", function()
            -- Create the weekly plan with selected slots
            local plan = self:CreateWeeklyPlan(currentName, currentRealm, selectedSlots)
            if plan then
                -- Close dialog
                dialog.Close()
            end
        end)
        
        local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", 120)
        cancelBtn:SetPoint("BOTTOM", 65, 8)
        cancelBtn:SetScript("OnClick", function()
            dialog.Close()
        end)
    end
    
    dialog:Show()
end

-- CLOSE ALL PLAN DIALOGS

function WarbandNexus:CloseAllPlanDialogs()
    -- Close Weekly Plan Dialog
    if _G["WarbandNexus_WeeklyPlanDialog"] and _G["WarbandNexus_WeeklyPlanDialog"].Close then
        _G["WarbandNexus_WeeklyPlanDialog"].Close()
    end
    
    -- Close Daily Plan Dialog
    if _G["WarbandNexus_DailyPlanDialog"] and _G["WarbandNexus_DailyPlanDialog"].Close then
        _G["WarbandNexus_DailyPlanDialog"].Close()
    end
    
    -- Close Custom Plan Dialog
    if _G["WarbandNexus_CustomPlanDialog"] and _G["WarbandNexus_CustomPlanDialog"].Close then
        _G["WarbandNexus_CustomPlanDialog"].Close()
    end
end

-- DAILY QUEST PLAN DIALOG

function WarbandNexus:ShowDailyPlanDialog()
    local COLORS = ns.UI_COLORS
    local CAT_DISPLAY = ns.CATEGORY_DISPLAY or {}
    
    local currentName = SafePlayerName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local currentRealm = SafeRealmName() or ((ns.L and ns.L["UNKNOWN"]) or "?")
    local _, currentClass = UnitClass("player")
    local classColors = RAID_CLASS_COLORS[currentClass]
    
    local existingPlan = self:HasActiveDailyPlan(currentName, currentRealm)
    
    local dialog, contentFrame, header = CreateExternalWindow({
        name = "DailyPlanDialog",
        title = (ns.L and ns.L["DAILY_QUEST_TRACKER"]) or "Midnight Quest Tracker",
        icon = "Interface\\Icons\\INV_Misc_Note_06",
        width = 460,
        height = existingPlan and 220 or 470,
    })
    
    if not dialog then return end
    
    -- Existing plan warning
    if existingPlan then
        local warningIconFrame = CreateIcon(contentFrame, "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew", 40, false, nil, true)
        warningIconFrame:SetPoint("TOP", 0, -30)
        warningIconFrame:Show()
        
        local warningText = FontManager:CreateFontString(contentFrame, "title", "OVERLAY")
        warningText:SetPoint("TOP", warningIconFrame, "BOTTOM", 0, -10)
        warningText:SetText("|cffff9900" .. ((ns.L and ns.L["DAILY_PLAN_EXISTS"]) or "Plan Already Exists") .. "|r")
        
        local infoText = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        infoText:SetPoint("TOP", warningText, "BOTTOM", 0, -8)
        infoText:SetWidth(400)
        infoText:SetWordWrap(true)
        infoText:SetJustifyH("CENTER")
        local charFullName = currentName .. "-" .. currentRealm
        local dailyExistsDesc = (ns.L and ns.L["DAILY_PLAN_EXISTS_DESC"]) or "%s already has an active weekly quest plan. You can find it in the 'Weekly Progress' category."
        infoText:SetText("|cffaaaaaa" .. format(dailyExistsDesc, charFullName) .. "|r")
        
        local okBtn = CreateThemedButton(contentFrame, OKAY or "OK", 120)
        okBtn:SetPoint("TOP", infoText, "BOTTOM", 0, -16)
        okBtn:SetScript("OnClick", function() dialog.Close() end)
        
        dialog:Show()
        return
    end
    
    -- Character display
    local charFrame = ns.UI.Factory:CreateContainer(contentFrame, 420, 42)
    charFrame:SetPoint("TOP", 0, -12)
    
    local _, englishRace = UnitRace("player")
    local gender = UnitSex("player")
    local raceAtlas = ns.UI_GetRaceIcon(englishRace, gender)
    
    local iconContainer = ns.UI.Factory:CreateContainer(charFrame, 32, 32)
    iconContainer:SetPoint("LEFT", 10, 0)
    if ApplyVisuals and classColors then
        ApplyVisuals(iconContainer, COLORS.bgCard, {classColors.r, classColors.g, classColors.b, 1})
    end
    
    local charIconFrame = CreateIcon(iconContainer, raceAtlas, 26, true, nil, true)
    charIconFrame:SetPoint("CENTER")
    charIconFrame:Show()
    
    local charText = FontManager:CreateFontString(charFrame, "title", "OVERLAY")
    charText:SetPoint("LEFT", iconContainer, "RIGHT", 8, 0)
    if classColors then charText:SetTextColor(classColors.r, classColors.g, classColors.b) end
    charText:SetText(currentName .. "-" .. currentRealm)
    
    -- "Midnight" content label
    local contentLabel = FontManager:CreateFontString(charFrame, "small", "OVERLAY")
    contentLabel:SetPoint("RIGHT", -10, 0)
    contentLabel:SetText("|cff888888" .. ((ns.L and ns.L["CONTENT_MIDNIGHT"]) or "Midnight") .. "|r")
    
    -- Quest type checkboxes
    local selectedQuestTypes = {
        weeklyQuests = true,
        worldQuests  = true,
        assignments  = true,
        dailyQuests  = true,
        events       = true,
    }
    
    local questTypeY = -68
    local sectionLabel = FontManager:CreateFontString(contentFrame, "subtitle", "OVERLAY")
    sectionLabel:SetPoint("TOPLEFT", 16, questTypeY)
    ns.UI_SetTextColorRole(sectionLabel, "Bright")
    sectionLabel:SetText((ns.L and ns.L["QUEST_TYPES"]) or "Track Categories:")
    
    local CATEGORIES = ns.QUEST_CATEGORIES or {}
    local categoryDescs = {
        weeklyQuests = (ns.L and ns.L["QUEST_CATEGORY_DESC_WEEKLY"]) or "Weekly objectives, hunts, sparks, world boss, delves",
        worldQuests  = (ns.L and ns.L["QUEST_CATEGORY_DESC_WORLD"]) or "Zone-wide repeatable world quests",
        assignments  = (ns.L and ns.L["QUEST_CATEGORY_DESC_ASSIGNMENTS"]) or "Special Assignments and weekly assignment progress",
        dailyQuests  = (ns.L and ns.L["QUEST_CATEGORY_DESC_DAILY"]) or "Daily repeatable quests from NPCs",
        events       = (ns.L and ns.L["QUEST_CATEGORY_DESC_EVENTS"]) or "Bonus objectives, tasks, and activities",
    }
    
    for i = 1, #CATEGORIES do
        local catInfo = CATEGORIES[i]
        local catKey = catInfo.key
        local display = CAT_DISPLAY[catKey] or {}
        local catColor = display.color or {0.8, 0.8, 0.8}
        local catName = display.name and display.name() or catKey
        
        local cb = CreateThemedCheckbox(contentFrame, selectedQuestTypes[catKey])
        cb:SetPoint("TOPLEFT", 16, questTypeY - 28 - (i - 1) * 46)
        
        local colorBar = contentFrame:CreateTexture(nil, "ARTWORK")
        colorBar:SetSize(3, 30)
        colorBar:SetPoint("LEFT", cb, "RIGHT", 6, 0)
        colorBar:SetColorTexture(catColor[1], catColor[2], catColor[3], 0.9)
        
        local label = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
        label:SetPoint("LEFT", colorBar, "RIGHT", 6, 5)
        ns.UI_SetTextColorRole(label, "Bright")
        label:SetText(catName)
        
        local desc = FontManager:CreateFontString(contentFrame, "small", "OVERLAY")
        desc:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -2)
        ns.UI_SetTextColorRole(desc, "Muted")
        desc:SetText(categoryDescs[catKey] or "")
        
        cb:SetScript("OnClick", function(self)
            local isChecked = self:GetChecked()
            selectedQuestTypes[catKey] = isChecked
            if self.innerDot then self.innerDot:SetShown(isChecked) end
        end)
    end
    
    -- Buttons
    local createBtn = CreateThemedButton(contentFrame, (ns.L and ns.L["CREATE_PLAN"]) or "Track Character", 140)
    createBtn:SetPoint("BOTTOM", -75, 10)
    createBtn:SetScript("OnClick", function()
        local plan = self:CreateDailyPlan(currentName, currentRealm, selectedQuestTypes)
        if plan then
            dialog.Close()
        end
    end)
    
    local cancelBtn = CreateThemedButton(contentFrame, CANCEL or "Cancel", 100)
    cancelBtn:SetPoint("BOTTOM", 75, 10)
    cancelBtn:SetScript("OnClick", function() dialog.Close() end)
    
    dialog:Show()
end

-- TRANSMOG BROWSER

-- Module state for transmog browser
local currentTransmogSubCategory = "all"
local transmogResults = {}
local transmogLoading = false
local transmogLoadAttempted = false  -- Track if we've tried to load at least once
local transmogLoadProgress = {current = 0, total = 0, message = ""}
local transmogSearchText = ""  -- Search query text
local transmogCache = {}  -- Cache results per category: {categoryKey = {results, timestamp}}

--[[
    Draw transmog browser with sub-category filters
    @param parent Frame - Parent frame
    @param yOffset number - Current Y offset
    @param width number - Width of parent
    @return number - New Y offset
]]
function WarbandNexus:DrawTransmogBrowser(parent, yOffset, width)
    local COLORS = ns.UI_COLORS
    
    -- Work in Progress screen (full area, not centered)
    local wipCard = CreateCard(parent, 230)
    
    -- Anchor to top, stretch horizontally (like other content)
    wipCard:SetPoint("TOPLEFT", 10, -(yOffset + 10))
    wipCard:SetPoint("TOPRIGHT", -10, -(yOffset + 10))
    wipCard:SetHeight(230)
    
    local wipIconFrame2 = CreateIcon(wipCard, "Interface\\Icons\\INV_Misc_EngGizmos_20", 64, false, nil, true)
    wipIconFrame2:SetPoint("CENTER", wipCard, "CENTER", 0, 40)  -- Move icon slightly up from center
    local wipIcon = wipIconFrame2.texture
    
    local wipTitle = FontManager:CreateFontString(wipCard, "header", "OVERLAY")
    wipTitle:SetPoint("TOP", wipIcon, "BOTTOM", 0, -20)
    ns.UI_SetTextColorRole(wipTitle, "Bright")
    wipTitle:SetText((ns.L and ns.L["WORK_IN_PROGRESS"]) or "Work in Progress")
    
    local wipDesc = FontManager:CreateFontString(wipCard, "body", "OVERLAY")
    wipDesc:SetPoint("TOP", wipTitle, "BOTTOM", 0, -15)
    wipDesc:SetWidth(width - 100)
    ns.UI_SetTextColorRole(wipDesc, "Bright") -- White
    wipDesc:SetJustifyH("CENTER")
    wipDesc:SetText((ns.L and ns.L["TRANSMOG_WIP_DESC"]) or "Transmog collection tracking is currently under development.\n\nThis feature will be available in a future update with improved\nperformance and better integration with Warband systems.")
    
    -- Show the card and icon!
    wipCard:Show()
    wipIconFrame2:Show()
    
    return yOffset + 250  -- Return yOffset + card height + spacing
end

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
