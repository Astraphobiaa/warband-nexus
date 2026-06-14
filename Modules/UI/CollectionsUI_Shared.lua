--[[
    Warband Nexus - Collections tab (shared state, layout, scroll helpers)
    Split from CollectionsUI.lua for Lua 5.1 main-chunk local limit (~200).
    Loaded from WarbandNexus.toc after CollectionsUI_SourceData.lua.
]]

local _, ns = ...
ns.CollectionsUI = ns.CollectionsUI or {}
local M = ns.CollectionsUI

local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local Constants = ns.Constants

local issecretvalue = issecretvalue
local format = string.format
local Utilities = ns.Utilities
function M.SafeLower(s)
    if Utilities and Utilities.SafeLower then
        return Utilities:SafeLower(s)
    end
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

local CreateCard = ns.UI_CreateCard
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local PlanCardFactory = ns.UI_PlanCardFactory
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local UpdateBorderColor = ns.UI_UpdateBorderColor
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local CreateIcon = ns.UI_CreateIcon

-- Single source for layout (matches CurrencyUI, PlansUI, SharedWidgets)
function M.GetLayout()
    return ns.UI_LAYOUT or ns.UI_SPACING or {}
end
local LAYOUT, SIDE_MARGIN, TOP_MARGIN, CARD_GAP, AFTER_ELEMENT, ROW_ICON_SIZE
local DETAIL_ICON_SIZE, STATUS_ICON_SIZE, SCROLL_CONTENT_TOP_PADDING
function M.RefreshCollectionsLayout()
    LAYOUT = M.GetLayout()
    SIDE_MARGIN = LAYOUT.SIDE_MARGIN or (ns.UI_GetTabSideMargin and ns.UI_GetTabSideMargin()) or 12
    TOP_MARGIN = LAYOUT.TOP_MARGIN or 8
    CARD_GAP = LAYOUT.CARD_GAP or 8
    AFTER_ELEMENT = LAYOUT.AFTER_ELEMENT or LAYOUT.afterElement or 8
    ROW_ICON_SIZE = LAYOUT.ROW_ICON_SIZE or 20
    DETAIL_ICON_SIZE = LAYOUT.DETAIL_ICON_SIZE or 64
    STATUS_ICON_SIZE = LAYOUT.STATUS_ICON_SIZE or 16
    SCROLL_CONTENT_TOP_PADDING = LAYOUT.SCROLL_CONTENT_TOP_PADDING or 12
end
M.RefreshCollectionsLayout()

function M.CollectionsFallbackContentWidth(parent, mainFrame)
    local mf = mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
    return (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent)) or 660
end

-- Symmetric layout: all panels use same inset; no magic numbers.
local CONTENT_INSET = LAYOUT.CONTENT_INSET or LAYOUT.CARD_GAP or 8

--- Mount/pet detail description: single line (TOPLEFT+TOPRIGHT); RIGHT-only anchor wraps to two lines in WoW.
function M.PinCollectionsDetailDescriptionLine(fs, textOverlay, anchorFrame, anchorPoint, anchorX, anchorY)
    if not fs or not textOverlay or not anchorFrame then return end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", anchorFrame, anchorPoint, anchorX or 0, anchorY or 0)
    fs:SetPoint("TOPRIGHT", textOverlay, "TOPRIGHT", -CONTENT_INSET, 0)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fs:SetNonSpaceWrap(false)
    if fs.SetMaxLines then fs:SetMaxLines(1) end
end
local CONTAINER_INSET = LAYOUT.CONTAINER_INSET or 2
local TEXT_GAP = AFTER_ELEMENT
local SEARCH_ROW_HEIGHT = math.floor(32 * 1.05 + 0.5)
-- Title card height matches Characters reference (`TITLE_CARD_DEFAULT_HEIGHT` = 64).
local COLLECTIONS_TITLE_CARD_HEIGHT = (ns.UI_SPACING and ns.UI_SPACING.TITLE_CARD_DEFAULT_HEIGHT) or 64
local RECENT_SECTION_ORDER = { "achievement", "mount", "pet", "toy" }
local RECENT_CARD_ICON = 26
local RECENT_CARD_HEADER_PAD = 10
local RECENT_ROW_ICON_BORDER_ALPHA = 0.82
-- Recent column cards: minimum readable width; narrow viewports scroll horizontally (four columns).
local RECENT_CARD_MIN_WIDTH = 160
local SUBTAB_BAR_HEIGHT = LAYOUT.HEADER_HEIGHT or 32
local PROGRESS_ROW_HEIGHT = 28
local BAR_INSET = 2  -- Bar 2px each side = total 4px inside border

function M.CollectionsRecentCategoryLabel(ctype)
    local loc = ns.L
    if ctype == "mount" then return (loc and loc["CATEGORY_MOUNTS"]) or "Mounts"
    elseif ctype == "pet" then return (loc and loc["CATEGORY_PETS"]) or "Pets"
    elseif ctype == "toy" then return (loc and loc["CATEGORY_TOYS"]) or "Toys"
    elseif ctype == "achievement" then return (loc and loc["CATEGORY_ACHIEVEMENTS"]) or "Achievements"
    elseif ctype == "title" then return (loc and loc["CATEGORY_TITLES"]) or "Titles"
    elseif ctype == "illusion" then return (loc and loc["CATEGORY_ILLUSIONS"]) or "Illusions"
    elseif ctype == "transmog" then return (loc and loc["CATEGORY_TRANSMOG"]) or "Transmog"
    end
    return tostring(ctype or "")
end

local COLLECTIONS_SEARCH_CATEGORY_KEYS = {
    recent = "COLLECTIONS_SUBTAB_RECENT",
    achievements = "CATEGORY_ACHIEVEMENTS",
    mounts = "CATEGORY_MOUNTS",
    pets = "CATEGORY_PETS",
    toys = "CATEGORY_TOYS",
}

function M.GetCollectionsSearchPlaceholder(tabKey)
    local loc = ns.L
    local fmt = (loc and loc["SEARCH_CATEGORY_FORMAT"]) or "Search %s..."
    local key = COLLECTIONS_SEARCH_CATEGORY_KEYS[tabKey]
    local category = (key and loc and loc[key])
        or (tabKey == "recent" and "Recent")
        or (tabKey == "achievements" and "Achievements")
        or (tabKey == "mounts" and "Mounts")
        or (tabKey == "pets" and "Pets")
        or (tabKey == "toys" and "Toys")
        or tostring(tabKey or "")
    return format(fmt, category)
end

function M.UpdateCollectionsSearchPlaceholder(hdrCache, tabKey)
    if not hdrCache or not hdrCache.searchBar or not tabKey then return end
    if ns.UI_SetSearchBoxPlaceholder then
        ns.UI_SetSearchBoxPlaceholder(hdrCache.searchBar, M.GetCollectionsSearchPlaceholder(tabKey))
    end
end

function M.FormatCollectionsRecentRelativeTime(ts)
    if not ts or type(ts) ~= "number" then return "" end
    local now = time()
    local sec = now - ts
    if sec < 0 then sec = 0 end
    local loc = ns.L
    if sec < 60 then
        return (loc and loc["COLLECTIONS_RECENT_JUST_NOW"]) or "Just now"
    end
    if sec < 3600 then
        return format((loc and loc["COLLECTIONS_RECENT_MINUTES_AGO"]) or "%d min ago", math.floor(sec / 60))
    end
    if sec < 86400 then
        return format((loc and loc["COLLECTIONS_RECENT_HOURS_AGO"]) or "%d hr ago", math.floor(sec / 3600))
    end
    return format((loc and loc["COLLECTIONS_RECENT_DAYS_AGO"]) or "%d days ago", math.floor(sec / 86400))
end

-- Detail panel: when the addon last logged this collectible (same source as the recent strip).
function M.FormatCollectionsAcquiredDetail(ts)
    if not ts or type(ts) ~= "number" then return nil end
    local loc = ns.L
    local rel = M.FormatCollectionsRecentRelativeTime(ts)
    local label = (loc and loc["COLLECTIONS_ACQUIRED_LABEL"]) or "Recorded"
    return format((loc and loc["COLLECTIONS_ACQUIRED_LINE"]) or "%s: %s", label, rel)
end

local COLLECTIONS_TT_WHITE_R, COLLECTIONS_TT_WHITE_G, COLLECTIONS_TT_WHITE_B = 1, 1, 1

--- Labeled line for Collections GameTooltip (always white).
function M.AddCollectionsTooltipLine(tt, label, value, wrap)
    if not tt or not value or value == "" then return end
    if issecretvalue and issecretvalue(value) then return end
    local text = value
    if label and label ~= "" then
        text = label .. ": " .. value
    end
    tt:AddLine(text, COLLECTIONS_TT_WHITE_R, COLLECTIONS_TT_WHITE_G, COLLECTIONS_TT_WHITE_B, wrap == true)
end

function M.CollectionPlanSlotTooltipHasContent(tip)
    if type(tip) == "string" then
        return tip ~= ""
    end
    if type(tip) ~= "table" then
        return false
    end
    if tip.title and tip.title ~= "" then
        return true
    end
    local lines = tip.lines
    if type(lines) == "table" then
        for i = 1, #lines do
            if lines[i] and lines[i] ~= "" then
                return true
            end
        end
    end
    return false
end

local SD = ns.CollectionsUI_SourceData

-- MOUNT LIST (Factory layout: ScrollFrame + SectionHeader + DataRow)

local Factory = ns.UI.Factory
local PADDING = SIDE_MARGIN
-- Single source: bar/button sizes and column width so Mounts/Pets/Toys/Achievements look identical
local SCROLLBAR_GAP = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
local SCROLLBAR_SIDE_GAP = 5  -- Equal gap between list <-> scrollbar and scrollbar <-> details
-- Match Plans: defer sub-tab draw and heavy work by 0.05s for smooth switching.
local COLLECTION_HEAVY_DELAY = 0.05
--- Avoid synchronous EnsureCollectionData from tab timers when store is already warm; coalesce pipeline start otherwise.
function M.RequestCollectionFillFromUI()
    if ns.CollectionLoadingState and ns.CollectionLoadingState.isLoading then
        return
    end
    if WarbandNexus.IsCollectionEnsureDataComplete and WarbandNexus:IsCollectionEnsureDataComplete() then
        return
    end
    if ns.ScheduleEnsureCollectionDataDeferred then
        ns.ScheduleEnsureCollectionDataDeferred()
    elseif WarbandNexus.EnsureCollectionData then
        WarbandNexus:EnsureCollectionData()
    end
end
-- Process this many mounts/pets per frame to avoid 1s freeze (spread over multiple frames).
local RUN_CHUNK_SIZE = 40
--- Collapsible category headers per frame (Mounts/Pets/Toys/Achievements); full pass while list chrome is deferred.
local COLLECTIONS_HEADER_CHUNK = 4
local COLLECTIONS_HEADER_CHUNK_DEFERRED = 99999

local _collectionsListChromeDeferFrames = {}

--- List + scrollbar frames for a Collections browse sub-tab (detail/viewer column stays visible during populate).
function M.CollectionsListChromeFramesForSubTab(subTabKey, extraFrame)
    local out = {}
    local function add(f)
        if f then out[#out + 1] = f end
    end
    if subTabKey == "mounts" then
        add(M.state.mountListContainer)
        add(M.state.mountListScrollBarContainer)
    elseif subTabKey == "pets" then
        add(M.state.petListContainer)
        add(M.state.petListScrollBarContainer)
    elseif subTabKey == "toys" then
        add(M.state.toyListContainer)
        add(M.state.toyListScrollBarContainer)
    elseif subTabKey == "achievements" then
        add(M.state.achievementListContainer)
        add(M.state.achievementListScrollBarContainer)
    end
    add(extraFrame)
    return out
end

function M.CollectionsBeginListChromeDefer(frames)
    wipe(_collectionsListChromeDeferFrames)
    if type(frames) ~= "table" then
        return false
    end
    for i = 1, #frames do
        local f = frames[i]
        if f then
            _collectionsListChromeDeferFrames[#_collectionsListChromeDeferFrames + 1] = f
            f:Hide()
        end
    end
    return #_collectionsListChromeDeferFrames > 0
end

function M.CollectionsEndListChromeDefer()
    for i = 1, #_collectionsListChromeDeferFrames do
        _collectionsListChromeDeferFrames[i]:Show()
    end
    wipe(_collectionsListChromeDeferFrames)
end

--- Snapshot key prefix per browse sub-tab: `_mountLastSearchText`, `_achLastSearchText`, etc.
function M.CollectionsBrowseSnapshotPrefix(subTabKey)
    if subTabKey == "mounts" then return "mount" end
    if subTabKey == "pets" then return "pet" end
    if subTabKey == "toys" then return "toy" end
    if subTabKey == "achievements" then return "ach" end
    return nil
end

--- True when search + Owned/Missing filters match last populate (nil last-* = never snapshotted, treated as match).
function M.CollectionsSubTabBrowseFiltersUnchanged(subTabKey)
    local prefix = M.CollectionsBrowseSnapshotPrefix(subTabKey)
    local st = M.state
    if not prefix or not st then return false end
    local curSearch = st.searchText or ""
    local lastSearch = st["_" .. prefix .. "LastSearchText"]
    if lastSearch == nil then lastSearch = "" end
    if lastSearch ~= curSearch then return false end
    local function showOn(val)
        return val ~= false
    end
    local lastC = st["_" .. prefix .. "LastShowCollected"]
    if lastC ~= nil and showOn(lastC) ~= showOn(st.showCollected) then return false end
    local lastU = st["_" .. prefix .. "LastShowUncollected"]
    if lastU ~= nil and showOn(lastU) ~= showOn(st.showUncollected) then return false end
    return true
end

function M.RecordCollectionsSubTabBrowseSnapshot(subTabKey)
    local prefix = M.CollectionsBrowseSnapshotPrefix(subTabKey)
    local st = M.state
    if not prefix or not st then return end
    st["_" .. prefix .. "LastSearchText"] = st.searchText or ""
    st["_" .. prefix .. "LastShowCollected"] = st.showCollected
    st["_" .. prefix .. "LastShowUncollected"] = st.showUncollected
end

function M.CollectionsSubTabBrowseCacheDiag(subTabKey)
    local prefix = M.CollectionsBrowseSnapshotPrefix(subTabKey)
    local st = M.state
    if not prefix or not st then return {} end
    local flatKey = (subTabKey == "achievements") and "_achFlatList" or ("_" .. prefix .. "FlatList")
    local groupedKey = (subTabKey == "mounts") and "_lastGroupedMountData"
        or (subTabKey == "pets") and "_lastGroupedPetData"
        or (subTabKey == "toys") and "_lastGroupedToyData"
        or (subTabKey == "achievements") and "_lastAchievementCategoryData"
    return {
        hasFlat = st[flatKey] ~= nil,
        hasGrouped = groupedKey and st[groupedKey] ~= nil,
        filtersOk = M.CollectionsSubTabBrowseFiltersUnchanged(subTabKey),
        lastSearch = st["_" .. prefix .. "LastSearchText"],
        curSearch = st.searchText or "",
    }
end

--- Sub-tab draw/populate trace (Profiler trace buffer). Enable: Settings Debug + Debug Verbose, or `/wn profiler tabperf on`.
function M.CollectionsSubTabTrace(stage, detail)
    local on = (ns.IsUserDebugTraceActive and ns.IsUserDebugTraceActive())
        or (ns.IsTabPerfMonitorEnabled and ns.IsTabPerfMonitorEnabled())
    if not on then return end
    local parts = { "|cff9370DB[WN Collections SubTab]|r", tostring(stage or "?") }
    local st = M.state
    if st then
        if st._collectionsSubTabGen then
            parts[#parts + 1] = "gen=" .. tostring(st._collectionsSubTabGen)
        end
        if st.currentSubTab then
            parts[#parts + 1] = "sub=" .. tostring(st.currentSubTab)
        end
    end
    if detail ~= nil then
        if type(detail) == "table" then
            local kv = {}
            for k, v in pairs(detail) do
                kv[#kv + 1] = tostring(k) .. "=" .. tostring(v)
            end
            table.sort(kv)
            for i = 1, #kv do
                parts[#parts + 1] = kv[i]
            end
        else
            parts[#parts + 1] = tostring(detail)
        end
    end
    local P = ns.Profiler
    if P and P.AppendUserTraceLine then
        P:AppendUserTraceLine(table.concat(parts, " "))
    end
end
-- Same row/header dimensions for all three sub-tabs (Mounts, Pets, Achievements); matches SharedWidgets/UI_SPACING
local ROW_HEIGHT = math.floor(32 * 1.05 * 1.25 + 0.5)
local ROW_GAP = (ns.UI_DataRowGap and ns.UI_DataRowGap()) or (ns.UI_LAYOUT and ns.UI_LAYOUT.dataRowGap) or 4
local ROW_STRIDE = ROW_HEIGHT + ROW_GAP
-- Mount/Pet/Toy category headers: must match CreateCollapsibleHeader + CollectionVirtual_FillRowScrollIndex (collapsible sections + virtual rows).
local COLLAPSE_HEADER_HEIGHT_COLL = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT) or 36
-- List | scrollbar | detail split — single ratio for Mounts, Pets, Toys, Achievements (WN-UI-layout symmetry).
local COLLECTION_LIST_DETAIL_SPLIT = 0.50

--- Theme-aware surface rgba (profile themeMode + live COLORS).
---@param tier string|nil viewport|card|elevated|rowEven|rowOdd|section
---@return table rgba
function M.ResolveCollectionsSurface(tier)
    if ns.UI_ResolveSurfaceTierColor then
        return ns.UI_ResolveSurfaceTierColor(tier or "card")
    end
    local c = COLORS
    if tier == "viewport" then
        return c.surfaceViewport or c.bg
    elseif tier == "rowEven" then
        return c.surfaceRowEven or c.bgLight or c.bg
    elseif tier == "rowOdd" then
        return c.surfaceRowOdd or c.bgLight or c.bg
    elseif tier == "section" or tier == "headerChrome" then
        return c.surfaceHeaderChrome or c.bgLight or c.bg
    end
    return c.bgCard or c.bgLight or c.bg
end

--- Icon shell fill + edge for list/detail icons (light-mode safe).
---@param edgeAlpha number|nil
---@return table bg, table edge
function M.CollectionsIconBorderColors(edgeAlpha)
    edgeAlpha = edgeAlpha or 0.72
    local bg = M.ResolveCollectionsSurface("rowOdd")
    local bc = COLORS.border or COLORS.accent or { 0.5, 0.4, 0.7 }
    return { bg[1], bg[2], bg[3], bg[4] or 0.96 }, { bc[1], bc[2], bc[3], edgeAlpha }
end

function M.ApplyCollectionsIconBorder(frame, edgeAlpha)
    if not frame or not ApplyVisuals then return end
    local bg, edge = M.CollectionsIconBorderColors(edgeAlpha)
    ApplyVisuals(frame, bg, edge)
end

function M.ApplyCollectionsRowIconChrome(row)
    if row and row._iconBorder then
        M.ApplyCollectionsIconBorder(row._iconBorder, RECENT_ROW_ICON_BORDER_ALPHA)
    end
end

function M.CollectionsSearchChromeColors()
    if ns.UI_GetSearchBoxChromeColors then
        return ns.UI_GetSearchBoxChromeColors()
    end
    local bg = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()
        or M.ResolveCollectionsSurface("elevated")
    local b = ns.UI_GetBorderStrokeColor and ns.UI_GetBorderStrokeColor() or COLORS.border
    return bg, { b[1], b[2], b[3], 0.55 }
end

function M.CollectionsProgressBarColors()
    local bg = M.ResolveCollectionsSurface("rowOdd")
    local acc = COLORS.accent
    return bg, { acc[1], acc[2], acc[3], 0.55 }
end

function M.CollectionsBrightHex()
    return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or "|cffeeeeee"
end

function M.CollectionsGoldHex()
    return (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffffcc00"
end

function M.CollectionsCollectedHex()
    local g = COLORS.green or { 0.30, 0.90, 0.30, 1 }
    return format("|cff%02x%02x%02x", g[1] * 255, g[2] * 255, g[3] * 255)
end

--- Small metadata line (try count, acquired time): bar overlay font with standard outline.
---@return FontString|nil
function M.CreateCollectionsSmallLabel(parent)
    if not parent or not FontManager then return nil end
    local fs
    if FontManager.CreateBarOverlayFontString then
        fs = FontManager:CreateBarOverlayFontString(parent, "OVERLAY")
    else
        fs = FontManager:CreateFontString(parent, "small", "OVERLAY")
        if FontManager.ApplyBarOverlayFont then
            FontManager:ApplyBarOverlayFont(fs)
        end
    end
    return fs
end

function M.CollectionsSubTabInactiveBg()
    return ns.UI_GetNavTabInactiveBackdrop and ns.UI_GetNavTabInactiveBackdrop()
        or M.ResolveCollectionsSurface("rowOdd")
end

function M.CollectionsSubTabActiveBg()
    local t = COLORS.tabActive or COLORS.accent
    return { t[1], t[2], t[3], t[4] or 1 }
end

function M.CollectionsSubTabHoverBg()
    return ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop()
        or M.ResolveCollectionsSurface("rowEven")
end

-- Detail container border: SharedWidgets 4-texture border system (accent)
function M.ApplyDetailAccentVisuals(frame)
    if ns.UI_ApplyDetailContainerVisuals then
        ns.UI_ApplyDetailContainerVisuals(frame)
    elseif frame and ApplyVisuals and COLORS then
        local bg = M.ResolveCollectionsSurface("card")
        ApplyVisuals(
            frame,
            { bg[1], bg[2], bg[3], (bg[4] or 1) * 0.95 },
            { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 }
        )
    end
end

function M.ScrollFrameByMouseWheel(scrollFrame, delta)
    if not scrollFrame then return end
    local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 28
    local cur = scrollFrame:GetVerticalScroll()
    local maxS = scrollFrame:GetVerticalScrollRange()
    local newScroll = math.max(0, math.min(cur - (delta * step), maxS))
    scrollFrame:SetVerticalScroll(newScroll)
    if scrollFrame.ScrollBar and scrollFrame.ScrollBar.SetValue then
        scrollFrame.ScrollBar:SetValue(newScroll)
    end
end

function M.EnableStandardScrollWheel(scrollFrame)
    if not scrollFrame then return end
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        M.ScrollFrameByMouseWheel(self, delta)
    end)
end

function M.CreateStandardScrollChild(scrollFrame, width, height)
    if not scrollFrame or not Factory or not Factory.CreateContainer then return nil end
    local scrollChild = Factory:CreateContainer(scrollFrame, width or 1, height or 1, false)
    if width then
        scrollChild:SetWidth(width)
    end
    if height then
        scrollChild:SetHeight(height)
    end
    scrollFrame:SetScrollChild(scrollChild)
    scrollChild:EnableMouseWheel(true)
    scrollChild:SetScript("OnMouseWheel", function(_, delta)
        M.ScrollFrameByMouseWheel(scrollFrame, delta)
    end)
    return scrollChild
end

function M.EnsureListScrollBarContainer(existingContainer, parent, anchorFrame, columnWidth, height, sideGap)
    local container = existingContainer
    if not container then
        container = Factory:CreateContainer(parent, columnWidth, height, false)
    end
    container:SetSize(columnWidth, height)
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", anchorFrame, "TOPRIGHT", sideGap or 0, 0)
    container:SetFrameLevel((anchorFrame and anchorFrame:GetFrameLevel() or 0) + 4)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

-- Details scrollbar: top/bottom inset (smaller = longer scrollbar, extends up/down)
local DETAIL_SCROLLBAR_VERTICAL_INSET = 4

function M.EnsureDetailScrollBarContainer(existingContainer, parent, columnWidth, inset, verticalInset)
    verticalInset = verticalInset or DETAIL_SCROLLBAR_VERTICAL_INSET
    local container = existingContainer
    if not container then
        container = Factory:CreateContainer(parent, columnWidth, 1, false)
    end
    container:ClearAllPoints()
    container:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -inset, -verticalInset)
    container:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -inset, verticalInset)
    container:SetWidth(columnWidth)
    container:SetFrameLevel((parent and parent:GetFrameLevel() or 0) + 4)
    container:SetClipsChildren(false)
    container:Show()
    return container
end

-- DETAILS WINDOW DIFFERENCES: Mounts vs ToyBox vs Achievement
-- Mounts: viewerContainer (CreateContainer) → mountDetailEmptyOverlay + modelViewer (CreateModelViewer).
--   Single panel: icon, name, source, description, 3D model. No scroll; content fixed in one panel.
-- ToyBox: toyDetailContainer (CreateContainer) → toyDetailEmptyOverlay + _toyDetailScroll (ScrollFrame).
--   ScrollChild has: headerRow (icon, name), collectedBadge, sourceLabel. Scroll-based; no 3D model.
-- Achievement: achievementDetailContainer (CreateContainer) → achDetailEmptyOverlay + achievementDetailPanel.
--   achievementDetailPanel = CreateAchievementDetailPanel (Frame + inner ScrollFrame, dynamic content:
--   description, achievement series list, criteria). Panel has its own border/ApplyVisuals and scroll.
-- All three use M.CreateDetailEmptyOverlay(container, typeKey) for empty state; same overlay styling.

-- Empty detail state: single centered line "Select a X to see details." (all 4 collection tabs)
-- Neutral grey background, no border. Inset by 1px so parent's accent border stays visible.
local BORDER_INSET = 1
function M.CreateDetailEmptyOverlay(parent, typeKey)
    if not parent then return nil end
    local w = parent:GetWidth() or 200
    local h = parent:GetHeight() or 200
    local overlay = Factory:CreateContainer(parent, w, h, false)
    if not overlay then return nil end
    overlay:SetPoint("TOPLEFT", parent, "TOPLEFT", BORDER_INSET, -BORDER_INSET)
    overlay:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -BORDER_INSET, BORDER_INSET)
    overlay:EnableMouse(false)
    if ApplyVisuals then
        local bg = M.ResolveCollectionsSurface("card")
        ApplyVisuals(overlay, { bg[1], bg[2], bg[3], bg[4] or 0.98 }, { 0, 0, 0, 0 })
    end
    local fmt = (ns.L and ns.L["SELECT_TO_SEE_DETAILS"]) or "Select a %s to see details."
    if fmt == "SELECT_TO_SEE_DETAILS" then fmt = "Select a %s to see details." end
    local typeName = (typeKey == "mount" and ((ns.L and ns.L["TYPE_MOUNT"]) or "mount"))
        or (typeKey == "pet" and ((ns.L and ns.L["TYPE_PET"]) or "pet"))
        or (typeKey == "toy" and ((ns.L and ns.L["TYPE_TOY"]) or "toy"))
        or (typeKey == "achievement" and ((ns.L and ns.L["ACHIEVEMENT"]) or "achievement"))
        or typeKey
    if typeName == "TYPE_MOUNT" then typeName = "mount" end
    if typeName == "TYPE_PET" then typeName = "pet" end
    if typeName == "TYPE_TOY" then typeName = "toy" end
    if typeName == "ACHIEVEMENT" then typeName = "achievement" end
    local text = format(fmt, typeName)
    local fs = FontManager:CreateFontString(overlay, "body", "OVERLAY")
    fs:SetPoint("CENTER", overlay, "CENTER", 0, 0)
    fs:SetJustifyH("CENTER")
    fs:SetJustifyV("MIDDLE")
    fs:SetText(M.CollectionsBrightHex() .. text .. "|r")
    fs:SetWordWrap(true)
    overlay.text = fs
    overlay:Hide()
    return overlay
end

-- State for Collections tab (must be defined before PopulateMountList / ApplySessionCollectionsSubTab — Lua 5.1 local scope)
M.VALID_COLLECTIONS_SUBTABS = {
    recent = true,
    mounts = true,
    pets = true,
    toys = true,
    achievements = true,
}

-- Must appear before ApplySessionCollectionsSubTab: Lua 5.1 local scope starts after this statement,
-- so a function defined above would otherwise resolve `M.state` as a nil global.
M.state = M.state or {
    currentSubTab = "recent",
    mountListContainer = nil,
    mountListScrollFrame = nil,
    mountListScrollChild = nil,
    petListContainer = nil,
    petListScrollFrame = nil,
    petListScrollChild = nil,
    modelViewer = nil,
    descriptionPanel = nil,
    loadingPanel = nil,
    searchContainer = nil,
    contentFrame = nil,
    subTabBar = nil,
    showCollected = true,
    showUncollected = true,
    collapsedHeaders = {},
    collapsedHeadersMounts = {},
    collapsedHeadersPets = {},
    selectedMountID = nil,
    selectedPetID = nil,
    selectedAchievementID = nil,
    achievementListContainer = nil,
    achievementListScrollFrame = nil,
    achievementListScrollChild = nil,
    achievementListScrollBarContainer = nil,
    achievementDetailPanel = nil,
    toyListContainer = nil,
    toyListScrollFrame = nil,
    toyListScrollChild = nil,
    toyListScrollBarContainer = nil,
    toyDetailContainer = nil,
    toyDetailScrollBarContainer = nil,
    collapsedHeadersToys = {},
    selectedToyID = nil,
    initialized = false,
    recentTabPanel = nil,
    --- Last viewport height cap for Recent layout (rows fill vs main-window scroll); refreshed in DrawCollectionsTab.
    recentViewportCap = nil,
    _recentEmptyFs = nil,
}

function M.WarmCollectionsBrowseCaches()
    local WN = WarbandNexus
    if not M.state._cachedMountsData and WN.GetAllMountsData then
        M.state._cachedMountsData = WN:GetAllMountsData() or {}
    end
    if not M.state._cachedToysData and WN.GetAllToysData then
        M.state._cachedToysData = WN:GetAllToysData() or {}
    end
    -- Pets: defer to PrewarmCollectionsSubTabData (GetAllPetsData can hitch one frame).
end

function M.EnsureCollectionsBrowseCacheForSubTab(subTabKey)
    local WN = WarbandNexus
    if subTabKey == "mounts" and not M.state._cachedMountsData and WN.GetAllMountsData then
        M.state._cachedMountsData = WN:GetAllMountsData() or {}
    elseif subTabKey == "pets" and not M.state._cachedPetsData and WN.GetAllPetsData then
        M.state._cachedPetsData = WN:GetAllPetsData() or {}
    elseif subTabKey == "toys" and not M.state._cachedToysData and WN.GetAllToysData then
        M.state._cachedToysData = WN:GetAllToysData() or {}
    end
end

function M.CollectionsPrewarmActive()
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    return mf and mf:IsShown() and mf.currentTab == "collections"
end

function M.ReanchorCollectionsBrowseListHost(container, contentFrame, headerBlockH, innerCh, listContentWidth)
    if not container or not contentFrame then return end
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -(headerBlockH or 0))
    if innerCh and listContentWidth then
        container:SetSize(listContentWidth, innerCh)
    end
end

local COLLECTIONS_PREWARM_SUBS = { "achievements", "mounts", "pets", "toys" }

function M.PrewarmCollectionsSubTabData(subTabKey, prewarmGen, onDone)
    local st = M.state
    local cf = st.contentFrame
    local search, showC, showU = "", true, true
    local function finish()
        if type(onDone) == "function" then onDone() end
    end
    if prewarmGen ~= st._collectionsPrewarmGen or not M.CollectionsPrewarmActive() then
        finish()
        return
    end
    M.CollectionsSubTabTrace("Prewarm_sub_start", { sub = subTabKey, gen = prewarmGen })
    if subTabKey == "achievements" then
        if not st._lastAchievementCategoryData and M.BuildGroupedAchievementData then
            local categoryData, rootCategories = M.BuildGroupedAchievementData(search, showC, showU)
            st._lastAchievementCategoryData = categoryData
            st._lastAchievementRootCategories = rootCategories
        end
        M.RecordCollectionsSubTabBrowseSnapshot("achievements")
        M.CollectionsSubTabTrace("Prewarm_sub_done", { sub = subTabKey, gen = prewarmGen })
        finish()
    elseif subTabKey == "mounts" then
        if st._lastGroupedMountData then
            M.CollectionsSubTabTrace("Prewarm_sub_skip", { sub = subTabKey, reason = "grouped_cached" })
            finish()
            return
        end
        M.EnsureCollectionsBrowseCacheForSubTab("mounts")
        local allMounts = st._cachedMountsData or {}
        M.RunChunkedMountBuild(allMounts, search, showC, showU, 0, cf, function(grouped)
            if prewarmGen ~= st._collectionsPrewarmGen or not M.CollectionsPrewarmActive() then finish() return end
            st._lastGroupedMountData = grouped
            M.RecordCollectionsSubTabBrowseSnapshot("mounts")
            M.CollectionsSubTabTrace("Prewarm_sub_done", { sub = subTabKey, gen = prewarmGen })
            finish()
        end, prewarmGen)
    elseif subTabKey == "pets" then
        if st._lastGroupedPetData then
            M.CollectionsSubTabTrace("Prewarm_sub_skip", { sub = subTabKey, reason = "grouped_cached" })
            finish()
            return
        end
        local function runPetPrewarmBuild()
            local allPets = st._cachedPetsData or {}
            M.RunChunkedPetBuild(allPets, search, showC, showU, 0, cf, function(grouped)
                if prewarmGen ~= st._collectionsPrewarmGen or not M.CollectionsPrewarmActive() then finish() return end
                st._lastGroupedPetData = grouped
                M.RecordCollectionsSubTabBrowseSnapshot("pets")
                M.CollectionsSubTabTrace("Prewarm_sub_done", { sub = subTabKey, gen = prewarmGen })
                finish()
            end, prewarmGen)
        end
        if not st._cachedPetsData and WarbandNexus.GetAllPetsData then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if prewarmGen ~= st._collectionsPrewarmGen or not M.CollectionsPrewarmActive() then finish() return end
                    if not st._cachedPetsData then
                        st._cachedPetsData = WarbandNexus:GetAllPetsData() or {}
                    end
                    runPetPrewarmBuild()
                end)
            else
                finish()
            end
            return
        end
        runPetPrewarmBuild()
    elseif subTabKey == "toys" then
        if not st._lastGroupedToyData and M.GetFilteredToysGrouped then
            st._lastGroupedToyData = M.GetFilteredToysGrouped(search, showC, showU)
        end
        M.RecordCollectionsSubTabBrowseSnapshot("toys")
        M.CollectionsSubTabTrace("Prewarm_sub_done", { sub = subTabKey, gen = prewarmGen })
        finish()
    else
        finish()
    end
end

--- Staged grouped-data prewarm (C_Timer.After chain; WN-PERF — not coroutine/yield).
function M.ScheduleCollectionsSubTabPrewarm()
    M.state._collectionsPrewarmGen = (M.state._collectionsPrewarmGen or 0) + 1
    local prewarmGen = M.state._collectionsPrewarmGen
    M.CollectionsSubTabTrace("Prewarm_schedule", { gen = prewarmGen })
    if not (C_Timer and C_Timer.After) then
        M.WarmCollectionsBrowseCaches()
        return
    end
    M.WarmCollectionsBrowseCaches()
    local idx = 0
    local function step()
        if prewarmGen ~= M.state._collectionsPrewarmGen or not M.CollectionsPrewarmActive() then
            M.CollectionsSubTabTrace("Prewarm_abort", { gen = prewarmGen, at = idx })
            return
        end
        idx = idx + 1
        local subKey = COLLECTIONS_PREWARM_SUBS[idx]
        if not subKey then
            M.CollectionsSubTabTrace("Prewarm_done", { gen = prewarmGen })
            return
        end
        M.PrewarmCollectionsSubTabData(subKey, prewarmGen, function()
            C_Timer.After(0, step)
        end)
    end
    C_Timer.After(0, step)
end

--- Per login/reload: nil → default Recent. After user picks a sub-tab, restored while the UI session lasts.
function M.ApplySessionCollectionsSubTab()
    local s = ns._sessionCollectionsSubTab
    if s and M.VALID_COLLECTIONS_SUBTABS[s] then
        M.state.currentSubTab = s
    else
        M.state.currentSubTab = "recent"
    end
end

---@return number listContentWidth, number listWidth, number detailWidth, number scrollBarColumnWidth
function M.ComputeCollectionsListDetailWidths(contentWidth)
    local cw = math.max(1, contentWidth or 660)
    local scrollBarColumnWidth = SCROLLBAR_GAP
    local listContentWidth = math.max(120, math.floor(cw * COLLECTION_LIST_DETAIL_SPLIT) - SCROLLBAR_GAP)
    local listWidth = listContentWidth + (SCROLLBAR_SIDE_GAP * 2) + scrollBarColumnWidth
    local detailWidth = math.max(1, cw - listWidth)
    return listContentWidth, listWidth, detailWidth, scrollBarColumnWidth
end

--- Viewport height for list/detail sub-tabs (avoids stale tall height after Recent).
function M.ResolveCollectionsViewportHeight(contentFrame, mainFrame)
    local mf = mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
    if mf and ns.UI_GetMainTabLayoutMetrics then
        local metrics = ns.UI_GetMainTabLayoutMetrics(mf)
        local yOffset = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
        local scrollFrame = mf.scroll
        local viewHeight = (scrollFrame and scrollFrame:GetHeight()) or 450
        local bottomPad = (metrics and metrics.contentBottomPad) or 0
        return math.max(250, viewHeight - yOffset - bottomPad)
    end
    local cap = M.state.recentViewportCap
    local ch = contentFrame and contentFrame:GetHeight()
    if cap and cap > 0 then
        return cap
    end
    if ch and ch > 0 then
        return ch
    end
    local parent = contentFrame and contentFrame:GetParent()
    return (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
end

--- Clear per-sub-tab draw locks left behind when async populate is aborted mid-flight.
function M.CollectionsDrawRetryAllowed(contentFrame, subTabKey)
    if M.state.currentSubTab ~= subTabKey then
        return false
    end
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mf and (not mf:IsShown() or mf.currentTab ~= "collections") then
        return false
    end
    if not contentFrame or not contentFrame:GetParent() then
        return false
    end
    if contentFrame.IsVisible and not contentFrame:IsVisible() then
        return false
    end
    return true
end

function M.ClearCollectionsDrawBusyFlags()
    M.state._drawMountsContentBusy = nil
    M.state._drawPetsContentBusy = nil
    M.state._drawToysContentBusy = nil
    M.state._drawAchievementsContentBusy = nil
    M.CollectionsEndListChromeDefer()
    if ns.UI_AchievementBrowse_ResetPopulateBusy then
        ns.UI_AchievementBrowse_ResetPopulateBusy()
    end
end

--- Release a sub-tab draw busy flag, but only when the releasing chain still owns it.
--- Async populate chains capture the drawGen they started with; a newer draw takes
--- ownership by writing its own gen, so a stale chain's release becomes a no-op.
function M.ReleaseCollectionsDrawBusy(kind, gen)
    if gen == nil or M.state["_draw" .. kind .. "BusyGen"] == gen then
        M.state["_draw" .. kind .. "ContentBusy"] = nil
    end
end

--- Bump draw generations so RunChunked* callbacks exit (tab switch / AbortTabOperations).
function WarbandNexus:AbortCollectionsChunkedBuilds()
    M.state._mountsDrawGen = (M.state._mountsDrawGen or 0) + 1
    M.state._petDrawGen = (M.state._petDrawGen or 0) + 1
    M.state._toysDrawGen = (M.state._toysDrawGen or 0) + 1
    M.state._achPopulateGen = (M.state._achPopulateGen or 0) + 1
    M.ClearCollectionsDrawBusyFlags()
end

local function DrawActiveCollectionsSubTab(contentFrame)
    if not contentFrame or not contentFrame:GetParent() then
        return
    end
    local sub = M.state.currentSubTab
    M.CollectionsSubTabTrace("DrawActiveSubTab", { target = sub })
    if sub == "recent" then
        M.DrawRecentContent(contentFrame)
    elseif sub == "mounts" then
        M.DrawMountsContent(contentFrame)
    elseif sub == "pets" then
        M.DrawPetsContent(contentFrame)
    elseif sub == "toys" then
        M.DrawToysContent(contentFrame)
    elseif sub == "achievements" then
        M.DrawAchievementsContent(contentFrame)
    end
end

--- Coalesce rapid Collections sub-tab clicks into one redraw (avoids empty body after aborted chunk pumps).
function M.ScheduleCollectionsSubTabRedraw(fromSub, toSub, perfWallStart)
    M.state._collectionsSubTabGen = (M.state._collectionsSubTabGen or 0) + 1
    M.CollectionsSubTabTrace("ScheduleSubTabRedraw", { from = fromSub, to = toSub })
    if WarbandNexus.AbortCollectionsChunkedBuilds then
        WarbandNexus:AbortCollectionsChunkedBuilds()
    else
        M.ClearCollectionsDrawBusyFlags()
    end
    M.state._collectionsSubTabRedrawFrom = fromSub
    M.state._collectionsSubTabRedrawTo = toSub
    M.state._collectionsSubTabRedrawPerfStart = perfWallStart

    local cf = M.state.contentFrame
    if not (C_Timer and C_Timer.After) then
        if cf then
            DrawActiveCollectionsSubTab(cf)
        end
        return
    end
    if M.state._collectionsSubTabRedrawScheduled then
        M.CollectionsSubTabTrace("ScheduleSubTabRedraw_coalesce_skip", { from = fromSub, to = toSub })
        return
    end
    M.state._collectionsSubTabRedrawScheduled = true
    C_Timer.After(0, function()
        M.state._collectionsSubTabRedrawScheduled = nil
        M.CollectionsSubTabTrace("SubTabRedraw_timer_fire", {
            from = M.state._collectionsSubTabRedrawFrom,
            to = M.state._collectionsSubTabRedrawTo,
        })
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mf and (not mf:IsShown() or mf.currentTab ~= "collections") then
            return
        end
        local contentFrame = M.state.contentFrame
        if not contentFrame or not contentFrame:GetParent() then
            return
        end
        local perfOn = ns.IsTabPerfMonitorEnabled and ns.IsTabPerfMonitorEnabled()
        if perfOn then
            debugprofilestart()
        end
        DrawActiveCollectionsSubTab(contentFrame)
        local bodyMs = perfOn and debugprofilestop() or nil
        M.CollectionsSubTabTrace("SubTabRedraw_body_done", {
            from = M.state._collectionsSubTabRedrawFrom,
            to = M.state._collectionsSubTabRedrawTo,
            bodyMs = bodyMs,
        })
        if perfOn and bodyMs and ns.EmitPartialTabRefreshPerf then
            ns.EmitPartialTabRefreshPerf(
                "collections",
                M.state._collectionsSubTabRedrawFrom,
                M.state._collectionsSubTabRedrawTo,
                bodyMs,
                M.state._collectionsSubTabRedrawPerfStart
            )
        end
    end)
end

local _populateMountListBusy = false

--- Coalesce virtual-list visible-range refreshes after layout (scroll metrics). Two passes (0 + 50ms)
--- were enough for header/width sync; a third pass at 120ms duplicated heavy work (mount/pet/toy lists).
function M.ScheduleCollectionsVisibleSync(subTabKey, refreshFn)
    if type(refreshFn) ~= "function" then return end
    C_Timer.After(0, function()
        if M.state.currentSubTab == subTabKey then
            refreshFn()
        end
    end)
    C_Timer.After(0.05, function()
        if M.state.currentSubTab == subTabKey then
            refreshFn()
        end
    end)
end

--- True when flat list contains at least one data row (not just headers).
function M.FlatListHasDataRows(flatList)
    if not flatList then return false end
    for i = 1, #flatList do
        if flatList[i].type == "row" then return true end
    end
    return false
end

--- Standard search-no-results card inside Collections list scrollChild.
---@return boolean shown
function M.TryShowCollectionsListSearchEmpty(scrollChild)
    if not scrollChild then return false end
    local q = M.state and M.state.searchText or ""
    if ns.UI_TryShowSearchEmptyInContainer then
        return ns.UI_TryShowSearchEmptyInContainer(scrollChild, q, 0)
    end
    return false
end

-- Bind shared symbols for satellite modules (avoid duplicate locals in main chunk).
M.WarbandNexus = WarbandNexus
M.FontManager = FontManager
M.Constants = Constants
M.Utilities = Utilities
M.issecretvalue = issecretvalue
M.SafeLower = M.SafeLower
M.CreateCard = CreateCard
M.CreateEmptyStateCard = CreateEmptyStateCard
M.HideEmptyStateCard = HideEmptyStateCard
M.CreateThemedCheckbox = CreateThemedCheckbox
M.PlanCardFactory = PlanCardFactory
M.COLORS = COLORS
M.ApplyVisuals = ApplyVisuals
M.UpdateBorderColor = UpdateBorderColor
M.CreateCollapsibleHeader = CreateCollapsibleHeader
M.ChainSectionFrameBelow = ChainSectionFrameBelow
M.CreateIcon = CreateIcon
M.LAYOUT = LAYOUT
M.SIDE_MARGIN = SIDE_MARGIN
M.TOP_MARGIN = TOP_MARGIN
M.CARD_GAP = CARD_GAP
M.AFTER_ELEMENT = AFTER_ELEMENT
M.ROW_ICON_SIZE = ROW_ICON_SIZE
M.DETAIL_ICON_SIZE = DETAIL_ICON_SIZE
M.STATUS_ICON_SIZE = STATUS_ICON_SIZE
M.SCROLL_CONTENT_TOP_PADDING = SCROLL_CONTENT_TOP_PADDING
M.CONTENT_INSET = CONTENT_INSET
M.CONTAINER_INSET = CONTAINER_INSET
M.TEXT_GAP = TEXT_GAP
M.SEARCH_ROW_HEIGHT = SEARCH_ROW_HEIGHT
M.COLLECTIONS_TITLE_CARD_HEIGHT = COLLECTIONS_TITLE_CARD_HEIGHT
M.RECENT_SECTION_ORDER = RECENT_SECTION_ORDER
M.RECENT_CARD_ICON = RECENT_CARD_ICON
M.RECENT_CARD_HEADER_PAD = RECENT_CARD_HEADER_PAD
M.RECENT_ROW_ICON_BORDER_ALPHA = RECENT_ROW_ICON_BORDER_ALPHA
M.RECENT_CARD_MIN_WIDTH = RECENT_CARD_MIN_WIDTH
M.SUBTAB_BAR_HEIGHT = SUBTAB_BAR_HEIGHT
M.PROGRESS_ROW_HEIGHT = PROGRESS_ROW_HEIGHT
M.BAR_INSET = BAR_INSET
M.SD = SD
M.Factory = Factory
M.PADDING = PADDING
M.SCROLLBAR_GAP = SCROLLBAR_GAP
M.SCROLLBAR_SIDE_GAP = SCROLLBAR_SIDE_GAP
M.COLLECTION_HEAVY_DELAY = COLLECTION_HEAVY_DELAY
M.RUN_CHUNK_SIZE = RUN_CHUNK_SIZE
M.COLLECTIONS_HEADER_CHUNK = COLLECTIONS_HEADER_CHUNK
M.COLLECTIONS_HEADER_CHUNK_DEFERRED = COLLECTIONS_HEADER_CHUNK_DEFERRED
M.ROW_HEIGHT = ROW_HEIGHT
M.ROW_GAP = ROW_GAP
M.ROW_STRIDE = ROW_STRIDE
M.COLLAPSE_HEADER_HEIGHT_COLL = COLLAPSE_HEADER_HEIGHT_COLL
M.COLLECTION_LIST_DETAIL_SPLIT = COLLECTION_LIST_DETAIL_SPLIT
M.DETAIL_SCROLLBAR_VERTICAL_INSET = DETAIL_SCROLLBAR_VERTICAL_INSET
M.BORDER_INSET = BORDER_INSET
M.VALID_COLLECTIONS_SUBTABS = M.VALID_COLLECTIONS_SUBTABS

function M.ResetSessionCollapsedHeaders()
    if not M.state then return end
    M.state._mountListCollapsedHeaders = nil
    M.state._petListCollapsedHeaders = nil
    M.state._toyListCollapsedHeaders = nil
end

local function CollectionsCollapsedHeadersAnyExpanded()
    local function anyExpanded(tbl)
        if not tbl then return false end
        for _, v in pairs(tbl) do
            if v == false then return true end
        end
        return false
    end
    local st = M.state
    return anyExpanded(st._mountListCollapsedHeaders)
        or anyExpanded(st._petListCollapsedHeaders)
        or anyExpanded(st._toyListCollapsedHeaders)
end

local function CollectionsExpandAllCategoryHeaders()
    local SD = M.SD
    if not SD or not M.state then return end
    local function fillFrom(cats)
        local out = {}
        if not cats then return out end
        for i = 1, #cats do
            out[cats[i].key] = false
        end
        return out
    end
    M.state._mountListCollapsedHeaders = fillFrom(SD.SOURCE_CATEGORIES)
    M.state._petListCollapsedHeaders = fillFrom(SD.PET_SOURCE_CATEGORIES)
    M.state._toyListCollapsedHeaders = fillFrom(SD.SOURCE_CATEGORIES)
end

function M.CollectionsToolbarAnyExpanded()
    return CollectionsCollapsedHeadersAnyExpanded()
end

function M.CollectionsToolbarExpandAll()
    CollectionsExpandAllCategoryHeaders()
end

function M.CollectionsToolbarCollapseAll()
    M.ResetSessionCollapsedHeaders()
end
