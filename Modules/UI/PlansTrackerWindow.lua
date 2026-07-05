--[[
    Warband Nexus - Plans Tracker Window
    Standalone floating window opened via /wn todo.
    Resizable, movable, responsive. Shows active plans by category.
    Card layout: Icon | Name \n Description (source/vendor/zone).
    Achievements: expandable requirements + Blizzard Track button.
    
    Data flow: DB (db.global.plans) â†’ GetActivePlans() [pure read] â†’ UI render
    Completion filter: IsActivePlanComplete() [live CheckPlanProgress + vault/daily rules]

    WN_FACTORY: `ns.UI.Factory` + ApplyVisuals for cards, dropdown, scroll chrome; Blizzard size-grabber
    on resize grip stays raw toolbar art; expandable row internals owned by SharedWidgets.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS or { accent = { 0.5, 0.4, 0.7 }, accentDark = { 0.25, 0.2, 0.35 } }
local PLAN_COLORS = ns.PLAN_UI_COLORS or {}

local function PCol(key, fb)
    return ns.UI_GetPlanUIColor and ns.UI_GetPlanUIColor(key, fb) or (PLAN_COLORS[key] or fb)
end

-- Unique AceEvent handler identity for PlansTrackerWindow
local PlansTrackerEvents = {}
local ApplyVisuals = ns.UI_ApplyVisuals

local TRACKER_VIEWPORT_TRANSPARENT = { 0, 0, 0, 0 }

--- Scroll/viewport stack: invisible unless `/wn debug on` (avoids ApplyVisuals(nil,nil) white backdrop).
local function ApplyTrackerViewportTransparent(frame)
    if not frame then return end
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        if ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(frame)
        end
        return
    end
    if ns.UI_ApplyBorderlessSurface then
        ns.UI_ApplyBorderlessSurface(frame, TRACKER_VIEWPORT_TRANSPARENT, { bgType = "searchChrome" })
    elseif ApplyVisuals then
        ApplyVisuals(frame, TRACKER_VIEWPORT_TRANSPARENT, TRACKER_VIEWPORT_TRANSPARENT)
        if ns.UI_HideFrameBorderQuartet then
            ns.UI_HideFrameBorderQuartet(frame)
        end
        frame._bgType = "searchChrome"
    end
    if frame._wnViewportAtlasUnderlay and frame._wnViewportAtlasUnderlay.Hide then
        frame._wnViewportAtlasUnderlay:Hide()
    end
end

local function IsTrackerViewportDebug()
    return ns.IsDebugModeEnabled and ns.IsDebugModeEnabled()
end

--- Skip ApplyVisuals on Blizzard template widgets (classic tracker dropdown guards).
---@param tier string|nil "card" | "row" | "icon" | "popup" | "bar" — classic routing only
local function ApplyTrackerChrome(frame, bg, border, tier)
    if not frame then return end
    if ns.UI_CanApplyCustomChrome and not ns.UI_CanApplyCustomChrome(frame) then return end
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        if tier == "card" and ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(frame)
        elseif tier == "row" and ns.UI_ApplyClassicThinBorderChrome then
            ns.UI_ApplyClassicThinBorderChrome(frame, bg)
        elseif tier == "icon" and ns.UI_ApplyClassicIconWellChrome then
            ns.UI_ApplyClassicIconWellChrome(frame, bg)
        elseif tier == "popup" and ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(frame)
        elseif ns.UI_ApplyClassicTransparentInterior then
            ns.UI_ApplyClassicTransparentInterior(frame)
        end
        return
    end
    if not ApplyVisuals then return end
    if not bg and not border then
        ApplyTrackerViewportTransparent(frame)
        return
    end
    ApplyVisuals(frame, bg, border)
end
local CreateIcon = ns.UI_CreateIcon
local function CreateExpandableRow(parent, width, rowHeight, data, isExpanded, onToggle)
    local fn = ns.UI_CreateExpandableRow
    if not fn then return nil end
    return fn(parent, width, rowHeight, data, isExpanded, onToggle)
end
local FormatNumber = ns.UI_FormatNumber
local FormatTextNumbers = ns.UI_FormatTextNumbers
local PLAN_TYPES = ns.PLAN_TYPES
local Factory = ns.UI.Factory
local CreateButton = ns.UI_CreateButton
local issecretvalue = issecretvalue
local format = string.format

--- True when zone text is safe to search and does not already include the difficulty label.
local function ZoneNeedsDiffSuffix(zoneText, diff)
    if not zoneText or not diff then return false end
    if issecretvalue and issecretvalue(zoneText) then return false end
    if issecretvalue and issecretvalue(diff) then return false end
    return not zoneText:find("(" .. diff .. ")", 1, true)
end

-- Scrollbar lane: column + gap (aligned with main window SCROLL_INSET_RIGHT).
local TRACK_SB_COL_W = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
local TRACK_SCROLL_RIGHT_RESERVE = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve())
    or (TRACK_SB_COL_W + 2)

-- Import UI spacing constants
local UI_SPACING = ns.UI_SPACING or {
    TOP_MARGIN = 8,
    HEADER_HEIGHT = 32,
    SIDE_MARGIN = 10,
    AFTER_ELEMENT = 8,
}

-- â”€â”€ Layout constants (tracker chrome aligns with main shell: NAV_BAR_HEIGHT + TAB_HEIGHT) â”€â”€
local PADDING = UI_SPACING.TOP_MARGIN
local MAIN_SHELL_PT = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
local CATEGORY_BAR_HEIGHT = MAIN_SHELL_PT.TAB_HEIGHT or 34

-- Tracker header metrics (must be above helpers that read these locals — Lua 5.1 forward-ref)
local PLAN_TRACKER_LAYOUT_VERSION = 14
local TRACKER_HEADER_ICON = 20
local TRACKER_HEADER_BTN = 22
local TRACKER_HEADER_BTN_GAP = 4
local TRACKER_HEADER_ICON_LEFT = 12
local TRACKER_COLLAPSED_MIN_WIDTH = 220
local TRACKER_ROW_BELOW_CHROME = 10
local TRACKER_CATEGORY_TO_CONTENT_GAP = 10

local function GetPlansTrackerHeaderHeight()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.PLANS_TRACKER_HEADER_HEIGHT or 28
end

local function GetPlansTrackerUtilityBtnSize()
    return TRACKER_HEADER_BTN
end

local function GetPlansTrackerCloseBtnWidth()
    return TRACKER_HEADER_BTN
end

local function CanApplyTrackerHeaderButtonChrome(btn)
    return btn and (not ns.UI_CanApplyCustomChrome or ns.UI_CanApplyCustomChrome(btn))
end

local function CreateTrackerHeaderIconButton(parent, size)
    size = size or TRACKER_HEADER_BTN or 22
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(size, size)
    btn:EnableMouse(true)
    btn._wnSkipCustomChrome = true
    if btn.SetBackdrop then
        pcall(btn.SetBackdrop, btn, nil)
    end
    if not (ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome()) then
        if ns.UI and ns.UI.Factory and ns.UI.Factory.ApplyIconOnlyButtonChrome then
            ns.UI.Factory:ApplyIconOnlyButtonChrome(btn)
        end
    elseif ns.UI_ApplyClassicIconWellChrome then
        ns.UI_ApplyClassicIconWellChrome(btn)
    end
    return btn
end

local function ComputeTrackerCollapsedWidth(titleText, utilityBtnSize, closeBtnW, gap, frameInset, utilityRight)
    local titleW = 72
    if titleText and titleText.GetStringWidth then
        local tw = titleText:GetStringWidth()
        if tw and tw > 0 then
            titleW = tw
        end
    end
    local inner = TRACKER_HEADER_ICON_LEFT + TRACKER_HEADER_ICON + 8 + titleW + 10
        + utilityBtnSize + gap + utilityBtnSize + gap + closeBtnW + utilityRight
    return math.max(TRACKER_COLLAPSED_MIN_WIDTH, inner + (frameInset * 2))
end
local CARD_HEIGHT = 48         -- Minimum collapsed achievement header (ExpandableRow); standard cards use dynamic height
local CARD_MARGIN = 8          -- Vertical gap between cards / rows (no overlap)
local MIN_GRID_CARD_H = 54     -- Minimum height for standard grid cards (icon + wrapped text)
local ICON_SIZE = 28
local MIN_WIDTH = 300
local MIN_HEIGHT = 240
local MAX_WIDTH = 600
local MAX_HEIGHT = 800
-- Bump when scroll/shell layout changes so stale floating windows rebuild on /reload or reopen.
-- PLAN_TRACKER_LAYOUT_VERSION + TRACKER_HEADER_* live above header helpers (Lua 5.1 forward-ref).

-- Fallback icons by plan type (ensures every card type has a visible icon)
local PLAN_TYPE_FALLBACK_ICONS = {
    mount = "Interface\\Icons\\Ability_Mount_RidingHorse",
    pet = "Interface\\Icons\\INV_Box_PetCarrier_01",
    toy = "Interface\\Icons\\INV_Misc_Toy_07",
    illusion = "Interface\\Icons\\INV_Enchant_Disenchant",
    achievement = "Interface\\Icons\\Achievement_Quests_Completed_08",
    title = "Interface\\Icons\\INV_Scroll_11",
    weekly_vault = "Interface\\Icons\\INV_Misc_Chest_03",
    daily_quests = "Interface\\Icons\\INV_Misc_Note_06",
    custom = "Interface\\Icons\\INV_Misc_Map_01",
}

-- Display order and labels for categories (localized at runtime)
local function GetCategoryKeys()
    local L = ns.L
    return {
        { key = nil,             label = (L and L["CATEGORY_ALL"]) or "All" },
        { key = "mount",         label = (L and L["CATEGORY_MOUNTS"]) or "Mounts" },
        { key = "pet",           label = (L and L["CATEGORY_PETS"]) or "Pets" },
        { key = "toy",           label = (L and L["CATEGORY_TOYS"]) or "Toys" },
        { key = "illusion",      label = (L and L["CATEGORY_ILLUSIONS"]) or "Illusions" },
        { key = "title",         label = (L and L["CATEGORY_TITLES"]) or "Titles" },
        { key = "achievement",   label = (L and L["CATEGORY_ACHIEVEMENTS"]) or "Achievements" },
        { key = "custom",        label = (L and L["CUSTOM"]) or "Custom" },
    }
end
local CATEGORY_KEYS = GetCategoryKeys()

local currentCategoryKey = nil -- nil = All
local expandedAchievements = {} -- [achievementID] = true
local expandedPlans = {} -- [planID] = true (mount/pet/toy/illusion/title/custom)

-- Card colors (consistent border theme; use COLORS at runtime in case ns.UI_COLORS was nil at load)
local function GetCardColors()
    local c = ns.UI_COLORS or COLORS
    if not c or not c.accent then
        c = { accent = { 0.5, 0.4, 0.7 } }
    end
    local bg = c.bgCard or c.bgLight or c.bg or { 0.118, 0.118, 0.145, 0.98 }
    local hoverBg = c.surfaceRowEven or c.bgLight or bg
    local borderAlpha = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.48 or 0.55
    return {
        border = { c.accent[1] * 0.55, c.accent[2] * 0.55, c.accent[3] * 0.55, borderAlpha },
        bg = { bg[1], bg[2], bg[3], bg[4] or 0.98 },
        hoverBorder = { c.accent[1], c.accent[2], c.accent[3], 0.88 },
        hoverBg = { hoverBg[1], hoverBg[2], hoverBg[3], hoverBg[4] or 1 },
    }
end

local function GetChromeButtonBackdrop()
    return (ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop()) or { 0.15, 0.15, 0.15, 0.8 }
end

local function GetControlChromeBackdrop()
    return (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or { 0.08, 0.08, 0.10, 1 }
end

local function GetIconWellBackdrop()
    local c = ns.UI_COLORS or COLORS
    local row = c and (c.surfaceRowOdd or c.bgLight or c.bg)
    if row then
        return { row[1], row[2], row[3], (row[4] or 1) * 0.95 }
    end
    return { 0.05, 0.05, 0.07, 0.95 }
end

--- Category filter: neutral chrome (no gold thin-border accent on the All control).
local function ApplyTrackerDropdownChrome(dropdown)
    if not dropdown then return end
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        if ns.UI_ApplyClassicPaneBackdrop then
            ns.UI_ApplyClassicPaneBackdrop(dropdown, GetControlChromeBackdrop())
        elseif ns.UI_ApplyClassicInteriorFlatFill then
            ns.UI_ApplyClassicInteriorFlatFill(dropdown, GetControlChromeBackdrop())
        end
    else
        local shell = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or GetControlChromeBackdrop()
        ApplyTrackerChrome(dropdown, shell, nil)
    end
end

-- â”€â”€ Refresh debounce â”€â”€
local pendingRefresh = false

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- DB helpers
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local function GetTrackerFrame()
    return _G.WarbandNexus_PlansTracker
end

local function DestroyStaleTrackerFrame()
    local frame = GetTrackerFrame()
    if not frame then return end
    if (frame._plansTrackerLayoutVersion or 0) >= PLAN_TRACKER_LAYOUT_VERSION then return end
    frame:Hide()
    if frame._plansUpdatedHandler and WarbandNexus and WarbandNexus.UnregisterMessage then
        WarbandNexus.UnregisterMessage(PlansTrackerEvents, E.PLANS_UPDATED)
    end
    frame:SetParent(nil)
    _G.WarbandNexus_PlansTracker = nil
end

local function GetDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return nil end
    if not WarbandNexus.db.global.plansTracker then
        WarbandNexus.db.global.plansTracker = { point = "CENTER", x = 0, y = 0, width = 380, height = 420, collapsed = false, opacity = 1.0 }
    end
    if WarbandNexus.db.global.plansTracker.opacity == nil then
        WarbandNexus.db.global.plansTracker.opacity = 1.0
    end
    return WarbandNexus.db.global.plansTracker
end

local function SavePosition(frame)
    if not frame or not frame:IsShown() then return end
    local db = GetDB()
    if not db then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    db.point = point
    db.relativePoint = relativePoint
    db.x = x
    db.y = y
    if not db.collapsed then
        db.width = frame:GetWidth()
        db.height = frame:GetHeight()
    end
end

local function RestorePosition(frame)
    local db = GetDB()
    if not db then return end
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 0)
    frame:SetSize(db.width or 380, db.height or 420)
end

local function GetAchievementRequirementsText(achievementID)
    if not achievementID then return "" end
    local summary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(achievementID)
    if not summary or (summary.rawNumCriteria or 0) == 0 then
        local noReqs = (ns.L and ns.L["NO_REQUIREMENTS"]) or "No requirements (instant completion)"
        return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee" .. noReqs .. "|r"
    end
    local parts = {}
    local formatRowSuffix = ns.UI_FormatCriterionRowSuffix
    if summary.criteria then
        for i = 1, #summary.criteria do
            local row = summary.criteria[i]
            if row.hasName and row.name then
                local icon = row.completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t" or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
                local color = row.completed and (PLAN_COLORS.completed or "|cff44ff44") or PCol("incomplete")
                local progress = formatRowSuffix and formatRowSuffix(row, summary) or ""
                parts[#parts + 1] = icon .. " " .. color .. FormatTextNumbers(row.name) .. "|r" .. progress
            end
        end
    end
    local headerLine = ns.UI_FormatAchievementProgressHeader and ns.UI_FormatAchievementProgressHeader(summary) or ""
    local header = headerLine ~= "" and ("|cff00ff00" .. headerLine .. "|r\n") or ""
    return header .. table.concat(parts, "\n")
end

-- Content helpers
local function GetTrackerRowInnerPad(frame)
    return (frame and frame._plansRowInnerPad) or PADDING
end

--- Scroll viewport width (list + scrollbar lane already reserved on the host).
local function GetTrackerContentColumnWidth(frame)
    if not frame then return 200 end
    local sf = frame.contentScrollFrame
    if sf then
        local w = sf:GetWidth()
        if w and w > 0 then
            local VB = ns.VaultButton
            if VB and VB.VBGetEasyAccessScrollChildWidth then
                return VB.VBGetEasyAccessScrollChildWidth(w, false)
            end
            return math.max(w, 120)
        end
    end
    local VB = ns.VaultButton
    local bodyLay = (frame and frame._plansBodyLay)
        or (VB and VB.VBGetEasyAccessBodyLayout and VB.VBGetEasyAccessBodyLayout())
    local inset = (bodyLay and bodyLay.inset) or PADDING
    local sbLane = (bodyLay and bodyLay.sbLane) or TRACK_SCROLL_RIGHT_RESERVE
    local rowPad = GetTrackerRowInnerPad(frame)
    local frameW = frame:GetWidth() or 380
    return math.max(frameW - (inset * 2) - sbLane - rowPad, 200)
end

--- Card width inside scroll child (symmetric horizontal inset).
local function GetTrackerCardWidth(frame)
    local colW = GetTrackerContentColumnWidth(frame)
    local pad = GetTrackerRowInnerPad(frame)
    return math.max(colW - (pad * 2), 120)
end

local function GetTrackerListWidth(frame)
    return GetTrackerCardWidth(frame)
end

local function GetContentWidth(frame)
    return GetTrackerCardWidth(frame)
end

local function GetTrackerViewportLayout(eaLay)
    eaLay = eaLay or {}
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    local pcm = ns.UI_PLANS_CARD_METRICS or {}
    local defaultGap = pcm.todoListCardGap or PADDING or 10
    local padH = math.max(eaLay.rowInnerPad or PADDING, 4)
    local padTop = ms.PLANS_TRACKER_VIEWPORT_PAD_TOP or defaultGap
    local padBottom = ms.PLANS_TRACKER_VIEWPORT_PAD_BOTTOM or defaultGap
    return {
        padH = padH,
        padTop = padTop,
        padBottom = padBottom,
        padV = math.max(padTop, padBottom),
    }
end

local function ApplyTrackerViewportShellInsets(frame)
    local shell = frame and frame.contentViewportShell
    local contentArea = frame and frame.contentArea
    if not shell or not contentArea then return end
    local eaLay = frame._plansBodyLay
    local vpLay = GetTrackerViewportLayout(eaLay)
    frame._plansViewportLayout = vpLay
    shell:ClearAllPoints()
    shell:SetPoint("TOPLEFT", contentArea, "TOPLEFT", vpLay.padH, -vpLay.padTop)
    shell:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -vpLay.padH, vpLay.padBottom)
end

local function ApplyTrackerViewportShellChrome(shell)
    if not shell then return end
    if shell._trackerViewportTopEdge and shell._trackerViewportTopEdge.Hide then
        shell._trackerViewportTopEdge:Hide()
    end
    if shell._trackerViewportBottomEdge and shell._trackerViewportBottomEdge.Hide then
        shell._trackerViewportBottomEdge:Hide()
    end
    if not IsTrackerViewportDebug() then
        ApplyTrackerViewportTransparent(shell)
        return
    end
    local c = ns.UI_COLORS or COLORS
    local vp = c.surfaceViewport or c.bgCard or c.bg
    local cc = GetCardColors()
    if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then
        ApplyTrackerChrome(shell, vp, nil, "row")
    else
        ApplyTrackerChrome(shell, vp, cc.border)
    end
    shell:EnableMouse(false)
end

local function SyncTrackerViewportChrome(frame)
    if not frame then return end
    if frame.contentArea then
        ApplyTrackerViewportTransparent(frame.contentArea)
    end
    ApplyTrackerViewportShellInsets(frame)
    if frame.contentViewportShell then
        ApplyTrackerViewportShellChrome(frame.contentViewportShell)
    end
    if frame.contentScrollHost then
        ApplyTrackerViewportTransparent(frame.contentScrollHost)
    end
    if frame.contentScrollChild then
        ApplyTrackerViewportTransparent(frame.contentScrollChild)
    end
end

local function EnsureTrackerViewportShell(frame)
    local shell = frame and frame.contentViewportShell
    if not shell then return end
    local scrollFrame = frame.contentScrollFrame
    local scrollHost = frame.contentScrollHost
    if scrollHost and scrollFrame and scrollFrame:GetFrameLevel() <= shell:GetFrameLevel() then
        scrollHost:SetFrameLevel(shell:GetFrameLevel() + 1)
        scrollFrame:SetFrameLevel(shell:GetFrameLevel() + 2)
    end
    local barCol = frame.contentScrollBarColumn
    if barCol and scrollFrame and barCol:GetFrameLevel() <= scrollFrame:GetFrameLevel() then
        barCol:SetFrameLevel(scrollFrame:GetFrameLevel() + 2)
    end
    SyncTrackerViewportChrome(frame)
end

local function SyncTrackerScrollBar(frame)
    local sf = frame and frame.contentScrollFrame
    if not sf then return end
    local barCol = frame.contentScrollBarColumn
    local syncOpts = sf._wnBarColumnSyncOpts or { width = TRACK_SB_COL_W, gap = 2 }
    if barCol and ns.UI_EnsureScrollBarColumnSync then
        ns.UI_EnsureScrollBarColumnSync(sf, barCol, syncOpts)
    elseif barCol and ns.UI_SyncScrollBarColumnToViewport then
        ns.UI_SyncScrollBarColumnToViewport(sf, barCol, syncOpts)
    elseif sf.ScrollBar and barCol and Factory and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(sf.ScrollBar, barCol, 0, sf)
    end
    if barCol and sf:GetFrameLevel() and barCol:GetFrameLevel() < sf:GetFrameLevel() + 2 then
        barCol:SetFrameLevel(sf:GetFrameLevel() + 4)
    end
    if sf.UpdateScrollChildRect then
        sf:UpdateScrollChildRect()
    end
    EnsureTrackerViewportShell(frame)
    if ns.UI_ApplyScrollLayoutDebugChrome and frame.contentViewportShell then
        ns.UI_ApplyScrollLayoutDebugChrome(sf, barCol, frame.contentViewportShell)
    end
    if Factory and Factory.SyncScrollBarThumb then
        Factory:SyncScrollBarThumb(sf)
    end
    local function tick()
        if not sf or not sf.GetScrollChild then return end
        if sf.UpdateScrollBarVisibility then
            sf:UpdateScrollBarVisibility()
        elseif Factory and Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(sf)
        end
    end
    tick()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, tick)
        C_Timer.After(0.05, tick)
    end
end

local function IsNonSecretNonEmptyString(s)
    if type(s) ~= "string" or s == "" then return false end
    if issecretvalue and issecretvalue(s) then return false end
    return true
end

local function IsPlaceholderSourceText(sourceText)
    if type(sourceText) ~= "string" then return true end
    if issecretvalue and issecretvalue(sourceText) then return true end
    local s = sourceText:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return true end
    local unknownSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
    local sourceUnknown = (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
    return s == "Unknown" or s == unknownSource or s == "Legacy"
end

--- Short description for card subtitle (same style as My Plans: Quest/Drop/Source with icon when applicable)
local function GetPlanDescription(plan)
    if not plan then return "" end
    local planSource = plan.source
    -- Resolve placeholder source for mount/pet so Tracker shows correct source (e.g. Nether-Warped Drake)
    if (plan.type == "mount" or plan.type == "pet") and IsPlaceholderSourceText(planSource) and WarbandNexus and WarbandNexus.GetPlanDisplaySource then
        local resolved = WarbandNexus:GetPlanDisplaySource(plan)
        if IsNonSecretNonEmptyString(resolved) then
            plan.source = resolved
            planSource = resolved
        end
    end
    local parts = {}
    if IsNonSecretNonEmptyString(planSource) then
        local src = planSource
        if WarbandNexus.CleanSourceText then src = WarbandNexus:CleanSourceText(src) end
        parts[#parts + 1] = src
    end
    if #parts == 0 then
        local typeLabel = plan.type or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        for ci = 1, #CATEGORY_KEYS do
            local cat = CATEGORY_KEYS[ci]
            if cat.key == plan.type then typeLabel = cat.label; break end
        end
        parts[#parts + 1] = typeLabel
    end
    local text = table.concat(parts, " Â· ")
    -- Card UI uses word wrap; keep a generous cap for performance only
    if #text > 240 then text = text:sub(1, 237) .. "..." end
    return text
end

--- Formatted card subtitle with Quest/Drop/Source styling (matches My Plans; uses PLAN_UI_COLORS)
local function GetPlanDescriptionFormatted(plan)
    local raw = GetPlanDescription(plan)
    if not raw or raw == "" then return PCol("descDim", "|cff888888") .. ((ns.L and ns.L["UNKNOWN"]) or "Unknown") .. "|r" end
    if issecretvalue and issecretvalue(raw) then
        return PCol("descDim", "|cff888888") .. ((ns.L and ns.L["UNKNOWN"]) or "Unknown") .. "|r"
    end
    local srcLabel = PCol("label")
    local body = PCol("body")
    local dim = PCol("descDim", "|cff888888")
    local prefix = raw:match("^([^:]+:%s*)(.*)$")
    if prefix then
        local sourceType, sourceDetail = raw:match("^([^:]+:%s*)(.*)$")
        if sourceDetail and sourceDetail ~= "" then
            local icon = ""
            local IconMk = ns.UI_PlanSourceIconMarkup
            if IconMk and sourceType and not (issecretvalue and issecretvalue(sourceType)) then
                local sl = string.lower(sourceType)
                local szSm = (ns.UI_PLAN_SOURCE_ICON_SM) or math.floor(12 * 1.3 + 0.5)
                if sl:match("quest") then
                    icon = IconMk("quest", szSm) .. " "
                elseif sl:match("drop") or sl:match("loot") then
                    icon = IconMk("loot", szSm) .. " "
                elseif sl:match("location") or sl:match("zone") then
                    icon = IconMk("location", szSm) .. " "
                end
            end
            return dim .. icon .. srcLabel .. sourceType .. "|r" .. body .. sourceDetail .. "|r"
        end
    end
    return dim .. raw .. "|r"
end

--- Achievement description for expanded row "Description:" line (from API; avoids "Unknown")
local function GetAchievementDescriptionForRow(plan)
    if plan.type ~= "achievement" or not plan.achievementID then return "" end
    local _, _, _, _, _, _, _, achDesc = GetAchievementInfo(plan.achievementID)
    if IsNonSecretNonEmptyString(achDesc) then return achDesc end
    return ""
end

--- Resolve mount/pet ids from journal APIs when plan rows only stored item/species placeholders.
local function EnsureTrackerPlanIdentity(plan)
    if not plan or not WarbandNexus then return end
    if plan.type == "mount" and (not plan.mountID or plan.mountID <= 0) then
        if plan.itemID and C_MountJournal and C_MountJournal.GetMountFromItem then
            local ok, mid = pcall(C_MountJournal.GetMountFromItem, plan.itemID)
            if ok and type(mid) == "number" and mid > 0
                and not (issecretvalue and issecretvalue(mid)) then
                plan.mountID = mid
            end
        end
        if (not plan.mountID or plan.mountID <= 0) and WarbandNexus.GetPlanCollectibleID then
            local mid = WarbandNexus:GetPlanCollectibleID(plan)
            if type(mid) == "number" and mid > 0 then
                plan.mountID = mid
            end
        end
    elseif plan.type == "pet" and (not plan.speciesID or plan.speciesID <= 0) and WarbandNexus.GetPlanCollectibleID then
        local sid = WarbandNexus:GetPlanCollectibleID(plan)
        if type(sid) == "number" and sid > 0 then
            plan.speciesID = sid
        end
    end
end

--- One criteria/summary line for raw journal source text (no "Source:" before "Achievement:").
local function FormatPlanSourceCriteriaText(rawText)
    if not IsNonSecretNonEmptyString(rawText) then return nil end
    local src = rawText
    if WarbandNexus and WarbandNexus.CleanSourceText then
        src = WarbandNexus:CleanSourceText(src)
    end
    if not IsNonSecretNonEmptyString(src) then return nil end
    src = src:gsub("\n", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    if src == "" then return nil end

    local labCol = PCol("label")
    local body = PCol("body")
    local szMd = (ns.UI_PLAN_SOURCE_ICON_MD) or math.floor(14 * 1.3 + 0.5)
    local IconMk = ns.UI_PlanSourceIconMarkup
    local sourceType, sourceDetail = src:match("^([^:]+:%s*)(.*)$")
    if sourceType and sourceDetail and sourceDetail ~= "" then
        local icon = ""
        if IconMk and not (issecretvalue and issecretvalue(sourceType)) then
            local sl = string.lower(sourceType)
            if sl:match("quest") then
                icon = IconMk("quest", szMd) .. " "
            elseif sl:match("drop") or sl:match("loot") then
                icon = IconMk("loot", szMd) .. " "
            elseif sl:match("location") or sl:match("zone") then
                icon = IconMk("location", szMd) .. " "
            else
                icon = IconMk("class", szMd) .. " "
            end
        end
        local normType = ns.UI_NormalizeColonLabelSpacing and ns.UI_NormalizeColonLabelSpacing(sourceType) or sourceType
        return icon .. labCol .. normType .. "|r" .. body .. sourceDetail .. "|r"
    end
    local srcLab = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:")
    local icon = (IconMk and IconMk("class", szMd)) or ""
    return icon .. labCol .. srcLab .. "|r " .. body .. src .. "|r"
end
ns.UI_FormatPlanSourceCriteriaText = FormatPlanSourceCriteriaText

local function ResolveTrackerPlanDisplaySource(plan)
    if not plan then return nil end
    EnsureTrackerPlanIdentity(plan)
    local planSource = plan.source
    if (plan.type == "mount" or plan.type == "pet") and IsPlaceholderSourceText(planSource)
        and WarbandNexus and WarbandNexus.GetPlanDisplaySource then
        local resolved = WarbandNexus:GetPlanDisplaySource(plan)
        if IsNonSecretNonEmptyString(resolved) then
            plan.source = resolved
            return resolved
        end
    end
    if IsNonSecretNonEmptyString(planSource) then
        return planSource
    end
    if WarbandNexus and WarbandNexus.GetPlanDisplaySource then
        local resolved = WarbandNexus:GetPlanDisplaySource(plan)
        if IsNonSecretNonEmptyString(resolved) then
            plan.source = resolved
            return resolved
        end
    end
    return nil
end

--- Resolve parsed sources for a plan using the central WarbandNexus:ParseMultipleSources helper.
--- Mirrors PlanCardFactory:CreateSourceInfo's data path so tracker rows show the same Drop/Vendor/Quest/Zone breakdown.
---@param plan table
---@return table list of { vendor, npc, quest, zone, cost }
local function ResolveTrackerPlanSources(plan)
    if not plan then return {} end
    EnsureTrackerPlanIdentity(plan)
    -- Mount/Pet: resolve placeholder source from API for parity with main UI.
    local planSource = ResolveTrackerPlanDisplaySource(plan)
    -- Toy reliability filter (same as main UI).
    if plan.type == "toy" and plan.itemID and WarbandNexus and WarbandNexus.ResolveCollectionMetadata then
        local function reliable(s)
            if not IsNonSecretNonEmptyString(s) then return false end
            if WarbandNexus.IsReliableToySource then return WarbandNexus:IsReliableToySource(s) end
            return true
        end
        if not reliable(planSource) then
            local meta = WarbandNexus:ResolveCollectionMetadata("toy", plan.itemID)
            if meta and reliable(meta.source) then
                plan.source = meta.source
                planSource = meta.source
            end
        end
    end
    if not IsNonSecretNonEmptyString(planSource) then return {} end
    if WarbandNexus and WarbandNexus.ParseMultipleSources then
        local ok, result = pcall(function() return WarbandNexus:ParseMultipleSources(planSource) end)
        if ok and result then return result end
    end
    return {}
end

--- Build a stack of icon+label info rows (Drop/Vendor/Quest/Zone) on a parent frame.
--- Anchored TOP to whichever is LOWER: topAnchor.BOTTOM or minTopY (negative offset from parent.TOP).
local function BuildPlanInfoRows(parent, plan, topAnchor, leftX, rightInset, minTopY)
    local sources = ResolveTrackerPlanSources(plan)
    local L = ns.L
    local P = PLAN_COLORS or {}
    local labCol = PCol("label")
    local body = PCol("body")
    local dim = PCol("descDim", "|cff888888")

    local rows = {}
    local szLg = (ns.UI_PLAN_SOURCE_ICON_LG) or math.floor(16 * 1.3 + 0.5)
    local IconMk = ns.UI_PlanSourceIconMarkup
    local classMk = IconMk and IconMk("class", szLg) or format("|A:Class:%d:%d|a", szLg, szLg)
    local lootMk = IconMk and IconMk("loot", szLg) or format("|A:Banker:%d:%d|a", szLg, szLg)
    local questMk = IconMk and IconMk("quest", szLg) or format("|A:Islands-QuestTurnin:%d:%d|a", szLg, szLg)
    local locMk = IconMk and IconMk("location", szLg) or format("|A:poi-islands-table:%d:%d|a", szLg, szLg)
    -- Inline markup matches PlanCardFactory:CreateSourceInfo (Loot / Quest / Location atlases).
    local function addRow(iconMarkup, labelKey, fallback, value, valueColor)
        if not value or value == "" then return end
        local label = ns.UI_NormalizeColonLabelSpacing((L and L[labelKey]) or fallback)
        local fs = FontManager:CreateFontString(parent, "small", "OVERLAY")
        fs:SetPoint("LEFT", parent, "LEFT", leftX, 0)
        fs:SetPoint("RIGHT", parent, "RIGHT", -rightInset, 0)
        if #rows == 0 then
            -- First row: anchor to absolute Y (below portrait icon AND below name) so it never
            -- overlaps with header content regardless of which is taller.
            fs:SetPoint("TOPLEFT", parent, "TOPLEFT", leftX, minTopY or -32)
            fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -rightInset, minTopY or -32)
        else
            fs:SetPoint("TOP", rows[#rows], "BOTTOM", 0, -2)
        end
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        fs:SetMaxLines(2)
        fs:SetNonSpaceWrap(false)
        fs:SetText((iconMarkup or "") .. " " .. labCol .. label .. "|r " .. (valueColor or body) .. tostring(value) .. "|r")
        rows[#rows + 1] = fs
    end

    -- Use the first parsed source block (compact tracker view); main UI shows all when expanded.
    local first = sources and sources[1]
    if first then
        if first.vendor then
            addRow(classMk, "VENDOR_LABEL", "Vendor:", first.vendor)
        elseif first.npc then
            addRow(lootMk, "DROP_LABEL", "Drop:", first.npc)
        elseif first.quest then
            addRow(questMk, "QUEST_LABEL", "Quest:", first.quest)
        end
        if first.zone then
            local zoneSuffix = ""
            if plan.type == "mount" and plan.mountID and WarbandNexus and WarbandNexus.GetDropDifficulty then
                local diff = WarbandNexus:GetDropDifficulty("mount", plan.mountID)
                if ZoneNeedsDiffSuffix(first.zone, diff) then
                    zoneSuffix = " " .. body .. "(" .. diff .. ")|r"
                end
            end
            addRow(locMk, "LOCATION_LABEL", "Location:", first.zone .. zoneSuffix)
        end
    end

    return rows
end

--- Build expanded-row criteria items (Drop / Vendor / Quest / Location lines as criteriaData entries).
--- Exposed as ns.UI_BuildPlanCriteriaItems so the To-Do tab (PlansUI) can reuse the same parsed
--- source pipeline â€” single source of truth for the tracker and the in-window list.
local function BuildPlanCriteriaItems(plan)
    local items = {}
    local sources = ResolveTrackerPlanSources(plan)
    local first = sources and sources[1]
    if not first then
        local displaySrc = ResolveTrackerPlanDisplaySource(plan)
        local formatted = FormatPlanSourceCriteriaText(displaySrc)
        if formatted then
            items[#items + 1] = { text = formatted }
        end
        return items
    end
    local L = ns.L
    local labCol = PCol("label")
    local body = PCol("body")
    local function row(iconMarkup, key, fallback, value)
        if not value or value == "" then return end
        local label = ns.UI_NormalizeColonLabelSpacing((L and L[key]) or fallback)
        items[#items + 1] = { text = (iconMarkup or "") .. " " .. labCol .. label .. "|r " .. body .. tostring(value) .. "|r" }
    end
    local szMd = (ns.UI_PLAN_SOURCE_ICON_MD) or math.floor(14 * 1.3 + 0.5)
    local IconMk = ns.UI_PlanSourceIconMarkup
    local classMk14 = IconMk and IconMk("class", szMd) or format("|A:Class:%d:%d|a", szMd, szMd)
    local lootMk14 = IconMk and IconMk("loot", szMd) or format("|A:Banker:%d:%d|a", szMd, szMd)
    local questMk14 = IconMk and IconMk("quest", szMd) or format("|A:Islands-QuestTurnin:%d:%d|a", szMd, szMd)
    local locMk14 = IconMk and IconMk("location", szMd) or format("|A:poi-islands-table:%d:%d|a", szMd, szMd)
    if first.vendor then
        row(classMk14, "VENDOR_LABEL", "Vendor:", first.vendor)
    elseif first.npc then
        row(lootMk14, "DROP_LABEL", "Drop:", first.npc)
    elseif first.quest then
        row(questMk14, "QUEST_LABEL", "Quest:", first.quest)
    elseif first.achievement then
        local achLabel = ns.UI_NormalizeColonLabelSpacing(
            (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement")
        items[#items + 1] = {
            text = classMk14 .. " " .. labCol .. achLabel .. "|r " .. body .. tostring(first.achievement) .. "|r",
        }
    end
    if first.zone then
        local zoneSuffix = ""
        if plan.type == "mount" and plan.mountID and WarbandNexus and WarbandNexus.GetDropDifficulty then
            local diff = WarbandNexus:GetDropDifficulty("mount", plan.mountID)
            if ZoneNeedsDiffSuffix(first.zone, diff) then
                zoneSuffix = " (" .. diff .. ")"
            end
        end
        row(locMk14, "LOCATION_LABEL", "Location:", first.zone .. zoneSuffix)
    end
    if #items == 0 then
        local displaySrc = ResolveTrackerPlanDisplaySource(plan)
        local formatted = FormatPlanSourceCriteriaText(displaySrc)
        if formatted then
            items[#items + 1] = { text = formatted }
        end
    end
    return items
end
ns.UI_BuildPlanCriteriaItems = BuildPlanCriteriaItems

--- All parsed source lines for expanded collectible rows (collapsed header shows first line only).
function ns.UI_BuildPlanCriteriaItemsAll(plan)
    local items = {}
    local sources = ResolveTrackerPlanSources(plan)
    if not sources or #sources == 0 then
        local formatted = FormatPlanSourceCriteriaText(ResolveTrackerPlanDisplaySource(plan))
        if formatted then
            items[#items + 1] = { text = formatted }
        end
        return items
    end
    local L = ns.L
    local labCol = PCol("label")
    local body = PCol("body")
    local szMd = (ns.UI_PLAN_SOURCE_ICON_MD) or math.floor(14 * 1.3 + 0.5)
    local IconMk = ns.UI_PlanSourceIconMarkup
    local classMk14 = IconMk and IconMk("class", szMd) or format("|A:Class:%d:%d|a", szMd, szMd)
    local lootMk14 = IconMk and IconMk("loot", szMd) or format("|A:Banker:%d:%d|a", szMd, szMd)
    local questMk14 = IconMk and IconMk("quest", szMd) or format("|A:Islands-QuestTurnin:%d:%d|a", szMd, szMd)
    local locMk14 = IconMk and IconMk("location", szMd) or format("|A:poi-islands-table:%d:%d|a", szMd, szMd)
    local function row(iconMarkup, key, fallback, value)
        if not value or value == "" then return end
        local label = ns.UI_NormalizeColonLabelSpacing((L and L[key]) or fallback)
        items[#items + 1] = { text = (iconMarkup or "") .. " " .. labCol .. label .. "|r " .. body .. tostring(value) .. "|r" }
    end
    for si = 1, #sources do
        local src = sources[si]
        if src.vendor then
            row(classMk14, "VENDOR_LABEL", "Vendor:", src.vendor)
        elseif src.npc then
            row(lootMk14, "DROP_LABEL", "Drop:", src.npc)
        elseif src.quest then
            row(questMk14, "QUEST_LABEL", "Quest:", src.quest)
        elseif src.achievement then
            local achLabel = ns.UI_NormalizeColonLabelSpacing(
                (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement")
            items[#items + 1] = {
                text = classMk14 .. " " .. labCol .. achLabel .. "|r " .. body .. tostring(src.achievement) .. "|r",
            }
        end
        if src.zone then
            local zoneSuffix = ""
            if plan.type == "mount" and plan.mountID and WarbandNexus and WarbandNexus.GetDropDifficulty then
                local diff = WarbandNexus:GetDropDifficulty("mount", plan.mountID)
                if ZoneNeedsDiffSuffix(src.zone, diff) then
                    zoneSuffix = " (" .. diff .. ")"
                end
            end
            row(locMk14, "LOCATION_LABEL", "Location:", src.zone .. zoneSuffix)
        end
    end
    return items
end

--- One-line summary under the portrait (collapsed To-Do row). Expand shows full criteria/sources.
function ns.UI_BuildPlanTodoSummaryLine(plan, opts)
    if not plan then return "" end
    opts = type(opts) == "table" and opts or {}
    local L = ns.L
    local P = PLAN_COLORS or {}
    local labCol = PCol("label")
    local body = PCol("body")
    local dim = PCol("descDim", "|cff888888")

    if plan.type == "achievement" and plan.achievementID then
        local achLines = ns.UI_BuildAchievementTodoSummaryLines
            and ns.UI_BuildAchievementTodoSummaryLines(
                ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(plan.achievementID),
                plan.achievementID,
                plan.description
            )
        if achLines and achLines[1] then
            return achLines[1]
        end
        return ""
    end

    if plan.type == "custom" then
        if ns.UI_BuildCustomPlanTodoSummaryLines then
            local lines = ns.UI_BuildCustomPlanTodoSummaryLines(plan)
            if lines and lines[1] then return lines[1] end
        end
        return ""
    end

    local items = BuildPlanCriteriaItems(plan)
    if #items == 0 then return "" end
    local line = items[1].text or ""
    if #items > 1 then
        local moreFmt = "+%d more"
        local locMore = L and L["TODO_SUMMARY_MORE_SOURCES"]
        if type(locMore) == "string" and locMore ~= "" and locMore ~= "TODO_SUMMARY_MORE_SOURCES" and locMore:find("%%", 1, true) then
            moreFmt = locMore
        end
        line = line .. " " .. dim .. format(moreFmt, #items - 1) .. "|r"
    end

    if opts.trySuffix and opts.trySuffix ~= "" then
        line = line .. " " .. opts.trySuffix
    end
    return line
end

--- Collapsed To-Do row: up to `maxLines` criteria/source lines (drop, location, …).
function ns.UI_BuildPlanTodoSummaryLines(plan, opts)
    opts = type(opts) == "table" and opts or {}
    local maxLines = tonumber(opts.maxLines) or 2
    if not plan then return {} end
    if plan.type == "custom" then
        if ns.UI_BuildCustomPlanTodoSummaryLines then
            local lines = ns.UI_BuildCustomPlanTodoSummaryLines(plan)
            if #lines > maxLines then
                local trimmed = {}
                for i = 1, maxLines do trimmed[i] = lines[i] end
                return trimmed
            end
            return lines
        end
        return {}
    end
    if plan.type == "achievement" and plan.achievementID then
        maxLines = math.max(maxLines, 2)
        if ns.UI_BuildAchievementTodoSummaryLines then
            local summary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(plan.achievementID)
            local lines = summary and ns.UI_BuildAchievementTodoSummaryLines(summary, plan.achievementID, plan.description) or {}
            if #lines > maxLines then
                local trimmed = {}
                for i = 1, maxLines do trimmed[i] = lines[i] end
                return trimmed
            end
            return lines
        end
    end
    if maxLines < 1 then maxLines = 1 end
    local items = BuildPlanCriteriaItems(plan)
    if #items == 0 then return {} end
    local lines = {}
    local limit = math.min(#items, maxLines)
    for i = 1, limit do
        local t = items[i].text
        if t and t ~= "" then lines[#lines + 1] = t end
    end
    if #items > maxLines and #lines > 0 then
        local L = ns.L
        local dim = PCol("descDim", "|cff888888")
        local moreFmt = "+%d more"
        local locMore = L and L["TODO_SUMMARY_MORE_SOURCES"]
        if type(locMore) == "string" and locMore ~= "" and locMore ~= "TODO_SUMMARY_MORE_SOURCES" and locMore:find("%%", 1, true) then
            moreFmt = locMore
        end
        lines[#lines] = lines[#lines] .. " " .. dim .. format(moreFmt, #items - maxLines) .. "|r"
    end
    return lines
end

--- Browse grid: all source lines for expanded rows (Mounts / Pets / Toys / etc.).
function ns.UI_BuildBrowseSourceCriteriaItems(item, category, sources)
    local items = {}
    if not sources or #sources == 0 then return items end
    local L = ns.L
    local labCol = PCol("label")
    local body = PCol("body")
    local szMd = (ns.UI_PLAN_SOURCE_ICON_MD) or math.floor(14 * 1.3 + 0.5)
    local IconMk = ns.UI_PlanSourceIconMarkup
    local classMk14 = IconMk and IconMk("class", szMd) or format("|A:Class:%d:%d|a", szMd, szMd)
    local lootMk14 = IconMk and IconMk("loot", szMd) or format("|A:Banker:%d:%d|a", szMd, szMd)
    local questMk14 = IconMk and IconMk("quest", szMd) or format("|A:Islands-QuestTurnin:%d:%d|a", szMd, szMd)
    local locMk14 = IconMk and IconMk("location", szMd) or format("|A:poi-islands-table:%d:%d|a", szMd, szMd)
    local function row(iconMarkup, key, fallback, value)
        if not value or value == "" then return end
        local label = ns.UI_NormalizeColonLabelSpacing((L and L[key]) or fallback)
        items[#items + 1] = { text = (iconMarkup or "") .. " " .. labCol .. label .. "|r " .. body .. tostring(value) .. "|r" }
    end
    for si = 1, #sources do
        local src = sources[si]
        if src.vendor then
            row(classMk14, "VENDOR_LABEL", "Vendor:", src.vendor)
        elseif src.npc then
            row(lootMk14, "DROP_LABEL", "Drop:", src.npc)
        elseif src.quest then
            row(questMk14, "QUEST_LABEL", "Quest:", src.quest)
        elseif src.faction then
            local factionLabel = ns.UI_NormalizeColonLabelSpacing((L and L["FACTION_LABEL"]) or "Faction:")
            local displayText = classMk14 .. " " .. factionLabel .. src.faction
            if src.renown then
                local repType = src.isFriendship and ((L and L["FRIENDSHIP_LABEL"]) or "Friendship") or ((L and L["RENOWN_TYPE_LABEL"]) or "Renown")
                displayText = displayText .. " |cffffcc00(" .. repType .. " " .. src.renown .. ")|r"
            end
            items[#items + 1] = { text = displayText }
        end
        if src.zone then
            row(locMk14, "LOCATION_LABEL", "Location:", src.zone)
        end
    end
    if #items == 0 and category ~= "title" and item.source and item.source ~= "" then
        if not (issecretvalue and issecretvalue(item.source)) then
            local formatted = FormatPlanSourceCriteriaText(item.source)
            if formatted then
                items[#items + 1] = { text = formatted }
            end
        end
    end
    return items
end

--- One-line collapsed summary for Plans browse cards (To-Do unified header).
function ns.UI_BuildBrowseTodoSummaryLine(item, category, sources, opts)
    if not item then return "" end
    opts = type(opts) == "table" and opts or {}
    local L = ns.L
    local P = PLAN_COLORS or {}
    local dim = PCol("descDim", "|cff888888")
    local labCol = PCol("label")
    local body = PCol("body")

    if category == "title" and item.sourceAchievement then
        local sourceLabel = ns.UI_NormalizeColonLabelSpacing((L and L["SOURCE_LABEL"]) or "Source:")
        local achievementType = (L and L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement"
        local srcFmt = (L and L["SOURCE_ACHIEVEMENT_FORMAT"]) or "%s %s"
        local line = format(srcFmt, sourceLabel, achievementType .. " " .. tostring(item.sourceAchievement))
        if #line > 72 then line = line:sub(1, 69) .. "..." end
        return labCol .. line .. "|r"
    end

    local criteriaItems = ns.UI_BuildBrowseSourceCriteriaItems(item, category, sources)
    if #criteriaItems == 0 then return "" end
    local line = criteriaItems[1].text or ""
    if #criteriaItems > 1 then
        local moreFmt = "+%d more"
        local locMore = L and L["TODO_SUMMARY_MORE_SOURCES"]
        if type(locMore) == "string" and locMore ~= "" and locMore ~= "TODO_SUMMARY_MORE_SOURCES" and locMore:find("%%", 1, true) then
            moreFmt = locMore
        end
        line = line .. " " .. dim .. format(moreFmt, #criteriaItems - 1) .. "|r"
    end
    return line
end

--- Collapsed browse card: up to `maxLines` source lines (no tries — use metaRightText on row 1).
function ns.UI_BuildBrowseTodoSummaryLines(item, category, sources, opts)
    opts = type(opts) == "table" and opts or {}
    local maxLines = tonumber(opts.maxLines) or 2
    if maxLines < 1 then maxLines = 1 end
    if category == "title" and item and item.sourceAchievement then
        local one = ns.UI_BuildBrowseTodoSummaryLine and ns.UI_BuildBrowseTodoSummaryLine(item, category, sources, opts) or ""
        return one ~= "" and { one } or {}
    end
    local criteriaItems = ns.UI_BuildBrowseSourceCriteriaItems(item, category, sources)
    if #criteriaItems == 0 then return {} end
    local lines = {}
    local limit = math.min(#criteriaItems, maxLines)
    for i = 1, limit do
        local t = criteriaItems[i].text
        if t and t ~= "" then lines[#lines + 1] = t end
    end
    if #criteriaItems > maxLines and #lines > 0 then
        local L = ns.L
        local dim = PCol("descDim", "|cff888888")
        local moreFmt = "+%d more"
        local locMore = L and L["TODO_SUMMARY_MORE_SOURCES"]
        if type(locMore) == "string" and locMore ~= "" and locMore ~= "TODO_SUMMARY_MORE_SOURCES" and locMore:find("%%", 1, true) then
            moreFmt = locMore
        end
        lines[#lines] = lines[#lines] .. " " .. dim .. format(moreFmt, #criteriaItems - maxLines) .. "|r"
    end
    return lines
end

local PlanCardFactory = ns.UI_PlanCardFactory
local CreateCard = ns.UI_CreateCard

--- Pick tooltip side from anchor frame screen position (avoids clipping off-screen edges).
local function ResolvePlanTooltipAnchor(anchorFrame)
    if not anchorFrame or not anchorFrame.GetLeft then return "ANCHOR_AUTO" end
    local left = anchorFrame:GetLeft()
    local right = anchorFrame:GetRight()
    if not left or not right then return "ANCHOR_AUTO" end
    local screenW = GetScreenWidth()
    if right > screenW * 0.58 then return "ANCHOR_LEFT" end
    if left < screenW * 0.42 then return "ANCHOR_RIGHT" end
    return "ANCHOR_AUTO"
end

--- Full tooltip for plan card hover (uses addon's custom TooltipService)
local function ShowPlanTooltip(anchor, plan, isExpanded)
    local TooltipService = ns.TooltipService
    if not TooltipService then return end

    local lblR, lblG, lblB = (ns.UI_GetTooltipLabelColor and ns.UI_GetTooltipLabelColor()) or 0.6, 0.6, 0.6
    local bodyR, bodyG, bodyB = (ns.UI_GetTooltipBodyColor and ns.UI_GetTooltipBodyColor()) or 0.8, 0.8, 0.8
    local noteR, noteG, noteB = (ns.UI_GetTooltipDescColor and ns.UI_GetTooltipDescColor()) or 0.7, 0.7, 0.7
    local goldR, goldG, goldB = (ns.UI_GetSemanticGoldColor and ns.UI_GetSemanticGoldColor()) or 1, 0.82, 0
    local greenR, greenG, greenB = (ns.UI_GetSemanticGreenColor and ns.UI_GetSemanticGreenColor()) or 0.3, 1, 0.3
    local brightR, brightG, brightB = (ns.UI_GetTextRoleRGB and ns.UI_GetTextRoleRGB("Bright")) or 1, 1, 1
    local reqR, reqG, reqB = (ns.UI_GetSemanticRedColor and ns.UI_GetSemanticRedColor()) or 1, 0.5, 0.5
    local zoneR, zoneG, zoneB = greenR, greenG, greenB
    local rewardLblR, rewardLblG, rewardLblB = greenR, greenG, greenB
    local rewardValR, rewardValG, rewardValB = greenR, greenG, greenB
    if not (ns.UI_IsLightMode and ns.UI_IsLightMode()) then
        rewardLblR, rewardLblG, rewardLblB = 0.53, 1, 0.53
        rewardValR, rewardValG, rewardValB = 0, 1, 0
        zoneR, zoneG, zoneB = 0.5, 0.8, 0.5
    end

    local displayName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    local planIcon = (WarbandNexus.GetResolvedPlanIcon and WarbandNexus:GetResolvedPlanIcon(plan)) or plan.icon
    local iconIsAtlas = ns.Utilities:IsAtlasName(planIcon)

    local lines = {}

    -- Achievement points (right under the title) â€” pulled from live API, not duplicated state.
    if plan.type == "achievement" and plan.achievementID then
        local ok, _, _, points = pcall(GetAchievementInfo, plan.achievementID)
        if ok and points and points > 0 then
            local pointsLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["POINTS_LABEL"]) or "Points")
            lines[#lines + 1] = { left = pointsLabel, right = tostring(points), leftColor = { lblR, lblG, lblB }, rightColor = { goldR, goldG, goldB } }
        end
    end

    -- Description (custom plan note / achievement description)
    local desc = plan.description or plan.note or ""
    if (desc == "" or desc == "Custom plan") and plan.type == "achievement" and plan.achievementID then
        local _, _, _, _, _, _, _, achDesc = GetAchievementInfo(plan.achievementID)
        if achDesc and achDesc ~= "" then desc = achDesc end
    end
    if desc ~= "" and desc ~= "Custom plan" and desc ~= ((ns.L and ns.L["CUSTOM_PLAN_SOURCE"]) or "Custom plan") then
        lines[#lines + 1] = { text = desc, color = { bodyR, bodyG, bodyB }, wrap = true }
        lines[#lines + 1] = { type = "spacer", height = 4 }
    end

    -- Reward (for achievement plans)
    if plan.type == "achievement" then
        local rewardDisplay = plan.rewardText
        if (not rewardDisplay or rewardDisplay == "") and plan.achievementID and WarbandNexus.GetAchievementRewardInfo then
            local ri = WarbandNexus:GetAchievementRewardInfo(plan.achievementID)
            if ri then rewardDisplay = ri.title or ri.itemName end
        end
        if rewardDisplay and IsNonSecretNonEmptyString(rewardDisplay) then
            local rewardLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["REWARD_LABEL"]) or "Reward:")
            lines[#lines + 1] = { left = rewardLabel, right = rewardDisplay, leftColor = { rewardLblR, rewardLblG, rewardLblB }, rightColor = { rewardValR, rewardValG, rewardValB } }
        end
    end

    -- Source
    if IsNonSecretNonEmptyString(plan.source) then
        local src = plan.source
        if WarbandNexus.CleanSourceText then src = WarbandNexus:CleanSourceText(src) end
        local sourceLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:")
        lines[#lines + 1] = { left = sourceLabel, right = src, leftColor = { lblR, lblG, lblB }, rightColor = { goldR, goldG, goldB } }
    end

    -- Zone / Vendor
    if IsNonSecretNonEmptyString(plan.zone) then
        local zoneLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["ZONE_LABEL"]) or "Zone:")
        lines[#lines + 1] = { left = zoneLabel, right = plan.zone, leftColor = { lblR, lblG, lblB }, rightColor = { zoneR, zoneG, zoneB } }
    end
    if IsNonSecretNonEmptyString(plan.vendor) then
        local vendorLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["VENDOR_LABEL"]) or "Vendor:")
        lines[#lines + 1] = { left = vendorLabel, right = plan.vendor, leftColor = { lblR, lblG, lblB }, rightColor = { zoneR, zoneG, zoneB } }
    end

    -- Requirement
    if plan.requirement and plan.requirement ~= "" then
        local reqLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENT_LABEL"]) or "Requirement:")
        lines[#lines + 1] = { left = reqLabel, right = plan.requirement, leftColor = { lblR, lblG, lblB }, rightColor = { reqR, reqG, reqB } }
    end

    -- Achievement requirements (only when collapsed â€” expanded cards already show them)
    if plan.type == "achievement" and plan.achievementID and not isExpanded then
        local summary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(plan.achievementID)
        if summary and (summary.rawNumCriteria or 0) > 0 then
            lines[#lines + 1] = { type = "spacer", height = 4 }
            local criteriaLines = {}
            local formatRowSuffix = ns.UI_FormatCriterionRowSuffix
            if summary.criteria then
                for i = 1, #summary.criteria do
                    local row = summary.criteria[i]
                    if row.hasName and row.name then
                        local icon = row.completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t" or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
                        local incRgb = PLAN_COLORS.incompleteRgb
                        if not incRgb and ns.UI_GetTextRoleRGB then
                            local ir, ig, ib = ns.UI_GetTextRoleRGB("Bright")
                            incRgb = { ir, ig, ib }
                        end
                        local color = row.completed and (PLAN_COLORS.completedRgb or {0.27, 1, 0.27}) or (incRgb or {1, 1, 1})
                        local progress = formatRowSuffix and formatRowSuffix(row, summary) or ""
                        criteriaLines[#criteriaLines + 1] = { text = icon .. " " .. row.name .. progress, color = color }
                    end
                end
            end

            local header = ns.UI_FormatAchievementProgressHeader and ns.UI_FormatAchievementProgressHeader(summary) or ""
            lines[#lines + 1] = { text = header, color = { greenR, greenG, greenB } }

            -- 3-column layout: group criteria into rows of 3
            local cols = 3
            for row = 1, math.ceil(#criteriaLines / cols) do
                local startIdx = (row - 1) * cols + 1
                local rowParts = {}
                for c = 0, cols - 1 do
                    local entry = criteriaLines[startIdx + c]
                    if entry then
                        local colorCode = format("|cff%02x%02x%02x", math.floor(entry.color[1]*255), math.floor(entry.color[2]*255), math.floor(entry.color[3]*255))
                        rowParts[#rowParts + 1] = colorCode .. entry.text .. "|r"
                    end
                end
                lines[#lines + 1] = { text = table.concat(rowParts, "  "), color = { brightR, brightG, brightB }, wrap = false }
            end
        end
    end

    -- Notes
    if plan.notes and plan.notes ~= "" then
        lines[#lines + 1] = { type = "spacer", height = 4 }
        lines[#lines + 1] = { text = plan.notes, color = { noteR, noteG, noteB }, wrap = true }
    end

    TooltipService:Show(anchor, {
        type = "custom",
        icon = planIcon,
        iconIsAtlas = iconIsAtlas,
        title = FormatTextNumbers(displayName),
        lines = lines,
        anchor = ResolvePlanTooltipAnchor(anchor),
    })
end

--- Hide addon tooltip helper
local function HidePlanTooltip()
    if ns.TooltipService then
        ns.TooltipService:Hide()
    end
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- RefreshTrackerContent (debounced) â€“ forward declaration
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local RefreshTrackerContent  -- forward declare so inner functions can reference it

-- Track rows in vertical order so expand/collapse can reposition siblings per layout pass
-- without rebuilding the list. Rebuilt fresh on each RefreshTrackerContentImmediate() call.
local trackerRowOrder = {}
local LIST_GAP_DEFAULT = 8

--- Reposition every tracked row by walking the ordered list and stacking them top-down using
--- their CURRENT GetHeight(). Cheap (O(n) y-anchor updates, no frame creation), called per
--- animation frame so the surrounding rows breathe with the toggling one.
local function RepositionTrackerRows()
    local frame = GetTrackerFrame()
    local scrollChild = frame and frame.contentScrollChild
    if not scrollChild then return 0 end
    local rowPadH = GetTrackerRowInnerPad(frame)
    local vpLay = (frame and frame._plansViewportLayout)
        or GetTrackerViewportLayout(frame and frame._plansBodyLay)
    local padBottom = (vpLay and vpLay.padBottom) or rowPadH
    local y = rowPadH
    for i = 1, #trackerRowOrder do
        local r = trackerRowOrder[i]
        if r and r:IsShown() then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", rowPadH, -y)
            y = y + (r:GetHeight() or 0) + LIST_GAP_DEFAULT
        end
    end
    if y > rowPadH then
        y = y - LIST_GAP_DEFAULT
    end
    y = y + padBottom
    scrollChild:SetHeight(math.max(y, 1))
    SyncTrackerScrollBar(frame)
    return y
end

--- Full-width vault / daily cards — same factory + height as Plans To-Do tab.
local function CreateTrackerFullWidthPlanCard(scrollChild, plan, width)
    local PCF = ns.UI_PlanCardFactory
    local cardH = (ns.UI_MeasureFullWidthPlanCardHeight and ns.UI_MeasureFullWidthPlanCardHeight(plan, width)) or 174
    local card = Factory and Factory:CreateContainer(scrollChild, width, cardH, false)
    if not card then
        card = CreateFrame("Frame", nil, scrollChild)
        card:SetSize(width, cardH)
    end
    if ApplyTrackerChrome then
        ApplyTrackerChrome(card, GetCardColors().bg, GetCardColors().border, "card")
    end
    if plan.type == "weekly_vault" and PCF and PCF.CreateWeeklyVaultCard then
        local progress = WarbandNexus.GetResolvedPlanProgress and WarbandNexus:GetResolvedPlanProgress(plan)
        PCF:CreateWeeklyVaultCard(card, plan, progress, nil)
    elseif plan.type == "daily_quests" and PCF and PCF.CreateDailyQuestCard then
        PCF:CreateDailyQuestCard(card, plan)
    end
    card:SetHeight(cardH)
    card:Show()
    return card
end

local function RefreshTrackerContentImmediate()
    local frame = GetTrackerFrame()
    if not frame or not frame.contentScrollChild then return end

    if currentCategoryKey == "weekly_vault" or currentCategoryKey == "daily_quests" then
        currentCategoryKey = nil
        if frame.categoryBar and frame.categoryBar.syncCategoryLabel then
            frame.categoryBar.syncCategoryLabel(nil)
        end
    end

    local scrollChild = frame.contentScrollChild
    local cardWidth = GetTrackerCardWidth(frame)
    scrollChild:SetWidth(GetTrackerContentColumnWidth(frame))
    local width = cardWidth

    -- Reset the ordered row tracker; the loop below appends each row as it's created.
    wipe(trackerRowOrder)

    local plans = WarbandNexus:GetActivePlans() or {}

    local function IsTrackerListPlan(plan)
        return plan and plan.type ~= "weekly_vault" and plan.type ~= "daily_quests"
    end

    local function IsTrackerFullWidthPlan(plan)
        return plan and (plan.type == "weekly_vault" or plan.type == "daily_quests")
    end

    -- Tracker: never list completed plans (only active / in-progress goals).
    local filtered = {}
    local fullWidthPlans = {}
    local trackerEligibleTotal = 0
    local planDoneMemo = {}
    local function memoIsPlanDone(plan)
        local v = planDoneMemo[plan]
        if v ~= nil then return v end
        if WarbandNexus.IsActivePlanComplete then
            v = WarbandNexus:IsActivePlanComplete(plan)
        else
            v = false
        end
        planDoneMemo[plan] = v
        return v
    end
    for i = 1, #plans do
        local plan = plans[i]
        if IsTrackerFullWidthPlan(plan) then
            if not memoIsPlanDone(plan) then
                fullWidthPlans[#fullWidthPlans + 1] = plan
            end
        elseif not IsTrackerListPlan(plan) then
            -- unknown type
        elseif not memoIsPlanDone(plan) then
            trackerEligibleTotal = trackerEligibleTotal + 1
            if currentCategoryKey == nil or plan.type == currentCategoryKey then
                filtered[#filtered + 1] = plan
            end
        end
    end

    local typePriority = { daily_quests = 1, weekly_vault = 2 }
    table.sort(fullWidthPlans, function(a, b)
        local pa = typePriority[a.type] or 99
        local pb = typePriority[b.type] or 99
        if pa ~= pb then return pa < pb end
        local aID = tonumber(a.id) or 0
        local bID = tonumber(b.id) or 0
        return aID < bID
    end)

    table.sort(filtered, function(a, b)
        if (a.type or "") ~= (b.type or "") then return (a.type or "") < (b.type or "") end
        local aID = tonumber(a.id) or 0
        local bID = tonumber(b.id) or 0
        return aID < bID
    end)

    -- Clear existing children (frames AND their FontStrings)
    local bin = ns.UI_RecycleBin
    local children = { scrollChild:GetChildren() }
    for ci = 1, #children do
        local c = children[ci]
        c:Hide()
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    -- Also clear any orphan regions (FontStrings created directly on scrollChild)
    local regions = { scrollChild:GetRegions() }
    for ri = 1, #regions do
        local r = regions[ri]
        r:Hide()
        r:ClearAllPoints()
    end

    for fw = 1, #fullWidthPlans do
        local fwPlan = fullWidthPlans[fw]
        local fwCard = CreateTrackerFullWidthPlanCard(scrollChild, fwPlan, width)
        if fwCard then
            trackerRowOrder[#trackerRowOrder + 1] = fwCard
        end
    end

    if #fullWidthPlans == 0 and #filtered == 0 then
        local emptyFrame = Factory and Factory:CreateContainer(scrollChild, width, 50, false)
        if not emptyFrame then
            emptyFrame = CreateFrame("Frame", nil, scrollChild)
            emptyFrame:SetSize(width, 50)
        end
        local empty = FontManager:CreateFontString(emptyFrame, "body", "OVERLAY")
        empty:SetPoint("TOPLEFT", PADDING, -12)
        empty:SetWidth(math.max(1, width))
        empty:SetWordWrap(true)
        empty:SetJustifyH("CENTER")
        local noPlansText = (ns.L and ns.L["NO_PLANS_IN_CATEGORY"]) or "No plans in this category.\nAdd plans from the Plans tab."
        empty:SetText((ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Dim") or "|cff666666") .. noPlansText .. "|r")
        trackerRowOrder[#trackerRowOrder + 1] = emptyFrame
    else
        for i = 1, #filtered do
            local plan = filtered[i]
            local PCM = ns.UI_PLANS_CARD_METRICS
            local PCF = ns.UI_PlanCardFactory
            local isExpanded
            if plan.type == "achievement" and plan.achievementID then
                isExpanded = expandedAchievements[plan.achievementID]
            else
                isExpanded = false
                if plan.id then expandedPlans[plan.id] = false end
            end

            local resolvedName = FormatTextNumbers((WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown"))
            local resolvedIcon = (WarbandNexus.GetResolvedPlanIcon and WarbandNexus:GetResolvedPlanIcon(plan)) or plan.iconAtlas or plan.icon or PLAN_TYPE_FALLBACK_ICONS[plan.type]
            local iconIsAtlas = plan.iconAtlas ~= nil
            if plan.type == "custom" and plan.icon and plan.icon ~= "" then iconIsAtlas = true end
            if type(resolvedIcon) == "string" and ns.Utilities and ns.Utilities.IsAtlasName and ns.Utilities:IsAtlasName(resolvedIcon) then
                iconIsAtlas = true
            end

            local trySuffix = ""
            local collectibleID = WarbandNexus.GetPlanCollectibleID and WarbandNexus:GetPlanCollectibleID(plan)
            if collectibleID and WarbandNexus.ShouldShowTryCountInUI and WarbandNexus:ShouldShowTryCountInUI(plan.type, collectibleID)
                and WarbandNexus.GetTryCount then
                local count = WarbandNexus:GetTryCount(plan.type, collectibleID) or 0
                if ns.UI_FormatPlanTryCountSuffix then
                    trySuffix = ns.UI_FormatPlanTryCountSuffix(count)
                else
                    trySuffix = (ns.UI_GetSemanticInfoHex and ns.UI_GetSemanticInfoHex() or "|cffaaddff")
                        .. ((ns.L and ns.L["TRIES"]) or "Tries") .. ":|r "
                        .. ((ns.UI_GetBrightHex and ns.UI_GetBrightHex())
                            or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright"))
                            or "|cffeeeeee")
                        .. tostring(count) .. "|r"
                end
            end

            local allSourceItems = ns.UI_BuildPlanCriteriaItemsAll and ns.UI_BuildPlanCriteriaItemsAll(plan) or BuildPlanCriteriaItems(plan)
            local summaryMax = 2
            local summaryLines = ns.UI_BuildPlanTodoSummaryLines and ns.UI_BuildPlanTodoSummaryLines(plan, { maxLines = summaryMax }) or {}

            local achievementPoints, information, criteriaItems, criteriaText, criteriaHeader
            local onExpandPopulate
            local achSummary = nil
            if plan.type == "achievement" and plan.achievementID then
                local achID = plan.achievementID
                achSummary = ns.UI_SummarizeAchievementCriteria and ns.UI_SummarizeAchievementCriteria(achID)
                local entry = ns.UI_EnsurePlansAchievementExpandCache and ns.UI_EnsurePlansAchievementExpandCache(achID)
                achievementPoints = ns.UI_ResolveAchievementPlanPoints and ns.UI_ResolveAchievementPlanPoints(plan, entry) or 0
                criteriaHeader = false
                local allowExpand = ns.UI_ShouldAchievementTodoExpand and ns.UI_ShouldAchievementTodoExpand(achSummary)
                if not allowExpand then
                    isExpanded = false
                end
                if isExpanded and allowExpand and entry then
                    criteriaItems = entry.criteriaItems
                end
                onExpandPopulate = function(data)
                    if not (ns.UI_ShouldAchievementTodoExpand and ns.UI_ShouldAchievementTodoExpand(achSummary)) then
                        return
                    end
                    local e = ns.UI_EnsurePlansAchievementExpandCache and ns.UI_EnsurePlansAchievementExpandCache(achID)
                    if not e then return end
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
                onExpandPopulate = function(data)
                    local all = ns.UI_BuildPlanCriteriaItemsAll and ns.UI_BuildPlanCriteriaItemsAll(plan) or BuildPlanCriteriaItems(plan)
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

            local canExpand = false
            if plan.type == "achievement" and plan.achievementID then
                canExpand = achSummary and ns.UI_ShouldAchievementTodoExpand and ns.UI_ShouldAchievementTodoExpand(achSummary) or false
            end

            local typeBadgeSz = (ns.UI_PlansHeaderActionSize and ns.UI_PlansHeaderActionSize()) or 24
            local ACTION_SIZE, ACTION_GAP = typeBadgeSz, 4
            local titleRightInset = 6 + ACTION_SIZE + ACTION_GAP
            if plan.type == "achievement" and plan.achievementID then
                titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP
            end
            if plan.type == "custom" and not memoIsPlanDone(plan) then
                titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP
            end
            if trySuffix ~= "" then
                titleRightInset = titleRightInset + ((PCM and PCM.todoMetaRightReserve) or 76)
            end

            local typeAtlas = PCF and PCF.TYPE_ICONS and PCF.TYPE_ICONS[plan.type]

            local collapsedH = ns.UI_PlansTodoFixedCollapsedHeight and ns.UI_PlansTodoFixedCollapsedHeight(true)
                or (ns.UI_PlansTodoExpandableHeaderHeight and ns.UI_PlansTodoExpandableHeaderHeight(width) or 92)
            local rowData = {
                todoUnifiedHeader = true,
                summaryInHeader = true,
                collapsedHeight = collapsedH,
                canExpand = canExpand,
                icon = resolvedIcon,
                iconIsAtlas = iconIsAtlas,
                iconSize = (PCM and PCM.todoUnifiedIconSize) or 40,
                typeAtlas = (plan.type ~= "achievement") and typeAtlas or nil,
                typeBadgeSize = (PCM and PCM.todoTypeBadgeSize) or 24,
                achievementPoints = achievementPoints,
                title = resolvedName,
                summaryLines = summaryLines,
                metaRightText = (trySuffix ~= "") and trySuffix or nil,
                information = (plan.type ~= "achievement" and isExpanded) and information or nil,
                hideExpandedDescription = (plan.type == "achievement") or nil,
                criteria = isExpanded and criteriaText or nil,
                criteriaData = criteriaItems,
                criteriaColumns = 2,
                criteriaShowHeader = criteriaHeader,
                titleRightInset = titleRightInset,
                onSectionResize = RepositionTrackerRows,
                onExpandPopulate = onExpandPopulate,
            }

            local row = CreateExpandableRow(scrollChild, width, collapsedH, rowData, isExpanded, function(expanded)
                if plan.type == "achievement" and plan.achievementID then
                    expandedAchievements[plan.achievementID] = expanded
                else
                    expandedPlans[plan.id] = expanded
                end
            end)
            if row then
            -- ExpandableRowFactory paints unified To-Do card chrome; do not stack row/icon borders (PlansUI parity).

            local rightOffset = 6
            row._todoActionControls = {}
            row._todoActionOffsets = {}
            local function anchorHeaderAction(btn, w)
                if not btn then return end
                w = w or ACTION_SIZE
                row._todoActionControls[#row._todoActionControls + 1] = btn
                row._todoActionOffsets[#row._todoActionOffsets + 1] = rightOffset
                if ns.UI_PlansAnchorHeaderAction then
                    ns.UI_PlansAnchorHeaderAction(btn, row.headerFrame, rightOffset, w, 0, row.iconFrame)
                else
                    btn:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
                end
                rightOffset = rightOffset + w + ACTION_GAP
            end
            local delBtn = ns.UI_CreateIconActionButton and ns.UI_CreateIconActionButton(row.headerFrame, ACTION_SIZE, "delete", {
                frameLevelOffset = 10,
                onClick = function()
                    WarbandNexus:RemovePlan(plan.id)
                    RefreshTrackerContent()
                end,
                tooltipTitle = (ns.L and ns.L["PLAN_ACTION_DELETE"]) or "Delete the Plan",
                tooltipAnchor = "ANCHOR_TOP",
            })
            if delBtn then anchorHeaderAction(delBtn) end
            if plan.type == "custom" and not memoIsPlanDone(plan) and ns.UI_CreateIconActionButton then
                local completeBtn = ns.UI_CreateIconActionButton(row.headerFrame, ACTION_SIZE, "complete", {
                    frameLevelOffset = 10,
                    onClick = function()
                        if WarbandNexus.CompleteCustomPlan and plan.id then
                            WarbandNexus:CompleteCustomPlan(plan.id)
                            RefreshTrackerContent()
                        end
                    end,
                    tooltipTitle = (ns.L and ns.L["PLAN_ACTION_COMPLETE"]) or "Complete the Plan",
                    tooltipAnchor = "ANCHOR_TOP",
                })
                if completeBtn then anchorHeaderAction(completeBtn) end
            end
            if plan.type == "achievement" and plan.achievementID and Factory.CreateAchievementTrackPinButton then
                local achPin = Factory:CreateAchievementTrackPinButton(row.headerFrame, plan.achievementID, {
                    size = ACTION_SIZE,
                    frameLevelOffset = 30,
                    isDisabled = function() return memoIsPlanDone(plan) end,
                })
                if achPin then anchorHeaderAction(achPin) end
            end
            if ns.UI_PlansSyncTitleRightInset then
                ns.UI_PlansSyncTitleRightInset(row, rightOffset)
            end
            row.headerFrame:SetScript("OnEnter", function() ShowPlanTooltip(row.headerFrame, plan, isExpanded) end)
            row.headerFrame:SetScript("OnLeave", HidePlanTooltip)
            row:Show()
            trackerRowOrder[#trackerRowOrder + 1] = row
        end
    end
    end

    RepositionTrackerRows()

    -- Update count label
    local frame = GetTrackerFrame()
    if frame and frame.categoryBar and frame.categoryBar.countLabel then
        local plansFormat = (ns.L and ns.L["PLANS_COUNT_FORMAT"]) or "%d plans"
        -- Extract suffix from format string (e.g., "%d plans" -> " plans")
        local suffix = plansFormat:gsub("%%d%s*", "")
        local countLabel = frame.categoryBar and frame.categoryBar.countLabel
        if countLabel then
            countLabel:SetText((ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Dim") or "|cff888888")
                .. #filtered .. "/" .. trackerEligibleTotal .. suffix .. "|r")
        end
    end

    SyncTrackerScrollBar(frame)
end

--- Debounced refresh: batches rapid calls into a single frame-deferred refresh
RefreshTrackerContent = function()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0, function()
        pendingRefresh = false
        local frame = GetTrackerFrame()
        if frame and frame:IsShown() then
            RefreshTrackerContentImmediate()
        end
    end)
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Custom themed dropdown (matches SettingsUI pattern)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local activeDropdownMenu = nil

local function CreateThemedCategoryDropdown(parent, onCategorySelected, opts)
    opts = opts or {}
    local VB = ns.VaultButton
    local bodyLay = opts.bodyLay
    if not bodyLay and VB and VB.VBGetEasyAccessBodyLayout then
        bodyLay = VB.VBGetEasyAccessBodyLayout()
    end
    bodyLay = bodyLay or { inset = PADDING, rowBelowChrome = 6 }
    local inset = bodyLay.inset or PADDING
    local sbLane = bodyLay.sbLane or TRACK_SCROLL_RIGHT_RESERVE
    local rowInnerPad = bodyLay.rowInnerPad or PADDING
    local chromeBandH = opts.chromeBandH
    chromeBandH = chromeBandH or GetPlansTrackerHeaderHeight()
    local rowY = -(chromeBandH + TRACKER_ROW_BELOW_CHROME)

    local bar = Factory and Factory:CreateContainer(parent, 420, CATEGORY_BAR_HEIGHT, false)
    if not bar then
        bar = CreateFrame("Frame", nil, parent)
        bar:SetHeight(CATEGORY_BAR_HEIGHT)
    end
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", inset + rowInnerPad, rowY)
    bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(inset + sbLane), rowY)
    if ApplyTrackerChrome then
        ApplyTrackerChrome(bar, nil, nil, "bar")
    end

    -- Plan count label (right side of bar) — dropdown fills remaining width
    local countLabel = FontManager:CreateFontString(bar, "small", "OVERLAY")
    countLabel:SetPoint("RIGHT", -rowInnerPad, 0)
    countLabel:SetPoint("TOP", bar, "TOP", 0, 0)
    countLabel:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    countLabel:SetJustifyH("RIGHT")
    bar.countLabel = countLabel

    -- Dropdown button spans full bar width (same as plan cards below)
    local dropdown = Factory:CreateButton(bar, 120, 26, false)
    dropdown:SetPoint("LEFT", bar, "LEFT", rowInnerPad, 0)
    dropdown:SetPoint("RIGHT", countLabel, "LEFT", -8, 0)
    dropdown:SetPoint("TOP", bar, "TOP", 0, 0)
    dropdown:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)
    dropdown:SetHeight(26)
    ApplyTrackerDropdownChrome(dropdown)

    -- Value text
    local valueText = FontManager:CreateFontString(dropdown, "body", "OVERLAY")
    valueText:SetPoint("LEFT", 10, 0)
    valueText:SetPoint("RIGHT", -10, 0)
    valueText:SetPoint("TOP", dropdown, "TOP", 0, 0)
    valueText:SetPoint("BOTTOM", dropdown, "BOTTOM", 0, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetText((ns.L and ns.L["CATEGORY_ALL"]) or "All")

    local function UpdateLabel(key)
        local label = (ns.L and ns.L["CATEGORY_ALL"]) or "All"
        for ci = 1, #CATEGORY_KEYS do
            local c = CATEGORY_KEYS[ci]
            if c.key == key then label = c.label; break end
        end
        valueText:SetText(label)
    end

    -- Dropdown click: open custom menu
    dropdown:SetScript("OnClick", function(self)
        -- Toggle: close if already open
        if activeDropdownMenu and activeDropdownMenu:IsShown() then
            activeDropdownMenu:Hide()
            activeDropdownMenu = nil
            return
        end
        if activeDropdownMenu then
            activeDropdownMenu:Hide()
            activeDropdownMenu = nil
        end

        local itemCount = #CATEGORY_KEYS
        local itemHeight = 24
        local menuWidth = self:GetWidth()

        local menu = dropdown._dropdownMenu
        if not menu then
            menu = Factory:CreateContainer(UIParent, menuWidth, 200, true)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(300)
            menu:SetClampedToScreen(true)
            if ApplyVisuals then
                local menuBg = (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop()) or GetControlChromeBackdrop()
                ApplyVisuals(menu, menuBg, { COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 0.8 })
            end
            menu:SetScript("OnHide", function()
                local catcher = dropdown._clickCatcher
                if catcher then
                    catcher:Hide()
                end
                activeDropdownMenu = nil
            end)
            dropdown._dropdownMenu = menu
        end
        menu:SetWidth(menuWidth)
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        activeDropdownMenu = menu

        local scrollFrame, scrollChild = ns.UI_ApplyDropdownScrollLayout(menu, itemCount, itemHeight)
        if scrollFrame then
            scrollFrame:EnableMouseWheel(true)
            if ns.UI_EnableStandardScrollWheel then
                ns.UI_EnableStandardScrollWheel(scrollFrame)
            end
            if scrollChild and ns.UI_WireScrollChildMouseWheel then
                ns.UI_WireScrollChildMouseWheel(scrollFrame, scrollChild)
            end
        end

        if scrollChild then
            local bin = ns.UI_RecycleBin
            local ch = { scrollChild:GetChildren() }
            for i = 1, #ch do
                ch[i]:Hide()
                ch[i]:ClearAllPoints()
                if bin then ch[i]:SetParent(bin) else ch[i]:SetParent(nil) end
            end
        end

        local yPos = (ns.UI_LAYOUT and ns.UI_LAYOUT.DROPDOWN_INSET_TOP) or 4
        local btnWidth = (scrollChild and scrollChild:GetWidth()) or (menuWidth - 16)
        for ci = 1, #CATEGORY_KEYS do
            local cat = CATEGORY_KEYS[ci]
            local btn = Factory:CreateButton(scrollChild, btnWidth, itemHeight, true)
            btn:SetPoint("TOPLEFT", 0, -yPos)

            local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
            btnText:SetPoint("LEFT", 10, 0)
            btnText:SetText(cat.label)

            -- Highlight current selection
            if currentCategoryKey == cat.key then
                ns.UI_SetTextColorRole(btnText, "Bright")
            else
                ns.UI_SetTextColorRole(btnText, "Normal")
            end

            -- Hover visual
            if ApplyVisuals then
                ApplyVisuals(btn, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 })
            end
            if Factory.ApplyHighlight then
                Factory:ApplyHighlight(btn)
            end

            btn:SetScript("OnClick", function()
                if currentCategoryKey == cat.key then
                    menu:Hide()
                    activeDropdownMenu = nil
                    return
                end
                currentCategoryKey = cat.key
                UpdateLabel(cat.key)
                menu:Hide()
                activeDropdownMenu = nil
                if onCategorySelected then onCategorySelected(cat.key) end
            end)

            yPos = yPos + itemHeight
        end

        ns.UI_ApplyDropdownScrollLayout(menu, itemCount, itemHeight)
        scrollFrame = menu._wnDropdownScroll
        scrollChild = menu._wnDropdownScrollChild

        menu:Show()

        -- Phase 4.6: Replace OnUpdate polling with click-catcher frame
        -- Create click-catcher (full-screen invisible frame)
        local clickCatcher = dropdown._clickCatcher
        if not clickCatcher then
            clickCatcher = Factory and Factory:CreateContainer(UIParent, 100, 100, false)
            if not clickCatcher then
                clickCatcher = CreateFrame("Frame", nil, UIParent)
            end
            clickCatcher:SetAllPoints()
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel(menu:GetFrameLevel() - 1)
            clickCatcher:EnableMouse(true)
            clickCatcher:SetScript("OnMouseDown", function()
                if activeDropdownMenu then
                    activeDropdownMenu:Hide()
                end
                activeDropdownMenu = nil
                clickCatcher:Hide()
            end)
            dropdown._clickCatcher = clickCatcher
        end
        
        -- Show click-catcher when menu is shown
        clickCatcher:Show()
        
    end)

    -- Hover on dropdown button
    dropdown:SetScript("OnEnter", function()
        if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then return end
        if ApplyVisuals then
            local hoverBg = (ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop()) or GetControlChromeBackdrop()
            ApplyVisuals(dropdown, hoverBg, { COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 0.8 })
        end
    end)
    dropdown:SetScript("OnLeave", function()
        if ns.UI_IsClassicMode and ns.UI_IsClassicMode() then return end
        if ApplyVisuals then
            local shell = (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop()) or GetControlChromeBackdrop()
            local ba = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.65 or 0.6
            ApplyVisuals(dropdown, shell, { COLORS.accent[1] * 0.5, COLORS.accent[2] * 0.5, COLORS.accent[3] * 0.5, ba })
        end
    end)

    bar.syncCategoryLabel = UpdateLabel
    currentCategoryKey = nil
    UpdateLabel(nil)
    return bar, dropdown
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Window creation
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
function WarbandNexus:CreatePlansTrackerWindow()
    DestroyStaleTrackerFrame()
    local frame = GetTrackerFrame()
    if frame then
        frame:Show()
        RestorePosition(frame)
        -- Delay refresh to let layout settle after Show()
        C_Timer.After(0.05, function()
            if frame and frame:IsShown() then
                RefreshTrackerContentImmediate()
            end
        end)
        return
    end

    local db = GetDB()
    local w = db and db.width or 380
    local h = db and db.height or 420

    -- â”€â”€ Main frame (Factory shell; draggable/resizable behavior unchanged) â”€â”€
    if not Factory or not Factory.CreateContainer then return end
    frame = Factory:CreateContainer(UIParent, w, h, false, "WarbandNexus_PlansTracker")
    if not frame then return end
    frame._plansTrackerLayoutVersion = PLAN_TRACKER_LAYOUT_VERSION
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    frame:SetClampedToScreen(true)

    -- WindowManager: standardized strata/level + ESC + combat hide
    if ns.WindowManager then
        ns.WindowManager:ApplyStrata(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:Register(frame, ns.WindowManager.PRIORITY.FLOATING)
        ns.WindowManager:InstallESCHandler(frame)
    else
        frame:SetFrameStrata("HIGH")
        frame:SetFrameLevel(120)
    end

    if ns.UI_ApplyFloatingWindowShellChrome then
        ns.UI_ApplyFloatingWindowShellChrome(frame)
    elseif ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    elseif ApplyTrackerChrome then
        local shell = (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop()) or GetCardColors().bg
        local ba = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.65 or 0.7
        ApplyTrackerChrome(frame, shell, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], ba })
    end
    frame:SetAlpha(math.max(0.2, math.min(1.0, db and db.opacity or 1.0)))

    if ns.UI_RegisterScaledFrame then
        ns.UI_RegisterScaledFrame(frame)
    elseif ns.UI_ApplyAddonUIScale then
        ns.UI_ApplyAddonUIScale(frame)
    end

    -- Header (compact, draggable; shell inset matches Vault Tracker / Saved Instances)
    local VB = ns.VaultButton
    local eaLay = (VB and VB.VBGetEasyAccessBodyLayout and VB.VBGetEasyAccessBodyLayout())
        or { inset = PADDING, rowBelowChrome = 6, scrollTopGap = 2, bottomPad = PADDING, sbLane = TRACK_SCROLL_RIGHT_RESERVE, rowInnerPad = PADDING }
    local shellInset = eaLay.inset or PADDING
    local rowInnerPad = eaLay.rowInnerPad or PADDING
    frame._plansRowInnerPad = rowInnerPad
    frame._plansBodyLay = eaLay

    local header = Factory:CreateContainer(frame, math.max(1, w), GetPlansTrackerHeaderHeight(), false)
    if not header then return end
    frame._plansTrackerHeaderShell = header
    local frameInset = (VB and VB.VBGetFrameContentInset and VB.VBGetFrameContentInset()) or shellInset
    local chromeBandH = GetPlansTrackerHeaderHeight()
    header:SetHeight(chromeBandH)
    header:SetPoint("TOPLEFT", frame, "TOPLEFT", frameInset, -frameInset)
    header:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -frameInset, -frameInset)
    frame._plansChromeBandH = chromeBandH
    header:EnableMouse(true)
    if ns.WindowManager and ns.WindowManager.InstallDragHandler then
        ns.WindowManager:InstallDragHandler(header, frame, function()
            SavePosition(frame)
        end)
    else
        header:RegisterForDrag("LeftButton")
        header:SetScript("OnDragStart", function()
            if not InCombatLockdown() then
                frame:StartMoving()
            end
        end)
        header:SetScript("OnDragStop", function()
            frame:StopMovingOrSizing()
            SavePosition(frame)
        end)
    end
    if ApplyTrackerChrome then
        if ns.UI_ApplyFloatingWindowHeaderChrome then
            ns.UI_ApplyFloatingWindowHeaderChrome(header)
        else
            ApplyTrackerChrome(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 },
                { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
        end
    end
    header:SetFrameLevel(frame:GetFrameLevel() + 10)

    local headerUtilityRight = math.max(shellInset, 8)

    -- Header icon holder (same rhythm as UI_MainShell: LEFT anchor y=0 centers on band)
    local iconHolder = CreateFrame("Frame", nil, header)
    iconHolder:SetSize(TRACKER_HEADER_ICON, TRACKER_HEADER_ICON)
    iconHolder:SetPoint("LEFT", header, "LEFT", TRACKER_HEADER_ICON_LEFT, 0)
    iconHolder:SetFrameLevel(header:GetFrameLevel() + 8)
    local hIcon = iconHolder:CreateTexture(nil, "OVERLAY", nil, 1)
    hIcon:SetAllPoints(iconHolder)
    if ns.UI_ApplyMainWindowTitleIcon then
        ns.UI_ApplyMainWindowTitleIcon(hIcon)
    else
        hIcon:SetTexture(ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga")
        if not hIcon:GetTexture() then
            hIcon:SetTexture("Interface\\Icons\\INV_Inscription_Scroll")
        end
        hIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    end
    frame._plansTrackerIconHolder = iconHolder

    -- Title (uses windowChromeTitle role like the main shell)
    local titleText
    if FontManager.GetFontRole then
        titleText = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        titleText = FontManager:CreateFontString(header, "body", "OVERLAY")
    end
    titleText:SetPoint("LEFT", iconHolder, "RIGHT", 8, 0)
    local collectionPlansLabel = (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List"
    titleText:SetText(collectionPlansLabel)
    ns.UI_SetTextColorRole(titleText, "Bright")
    frame._plansTrackerTitle = titleText

    local utilityBtnSize = GetPlansTrackerUtilityBtnSize()
    local closeBtnW = GetPlansTrackerCloseBtnWidth()

    -- Close button (compact icon well; same size as gear/collapse in classic + modern)
    local closeBtn
    local chromeBorder = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 }
    local closeR, closeG, closeB = (ns.UI_GetSemanticRedColor and ns.UI_GetSemanticRedColor()) or 0.9, 0.3, 0.3
    closeBtn = CreateTrackerHeaderIconButton(header, utilityBtnSize)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -headerUtilityRight, 0)
    if CanApplyTrackerHeaderButtonChrome(closeBtn) and ApplyVisuals then
        ApplyVisuals(closeBtn, GetChromeButtonBackdrop(), chromeBorder)
    end
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetSize(14, 14)
    closeTex:SetPoint("CENTER")
    closeTex:SetAtlas("uitools-icon-close")
    closeTex:SetVertexColor(closeR, closeG, closeB)
    closeBtn._wnCloseTex = closeTex
    closeBtn:SetScript("OnEnter", function()
        closeTex:SetVertexColor(1, 0.15, 0.15)
        if CanApplyTrackerHeaderButtonChrome(closeBtn) and ApplyVisuals and ns.UI_GetSemanticNegativeCard then
            local bg, border = ns.UI_GetSemanticNegativeCard(true)
            ApplyVisuals(closeBtn, bg, border)
        end
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetVertexColor(closeR, closeG, closeB)
        if CanApplyTrackerHeaderButtonChrome(closeBtn) and ApplyVisuals then
            ApplyVisuals(closeBtn, GetChromeButtonBackdrop(), chromeBorder)
        end
    end)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetFrameLevel(header:GetFrameLevel() + 5)

    -- Collapse/Expand toggle (icon-only; no panel chrome in classic)
    local collapseBtn = CreateTrackerHeaderIconButton(header, utilityBtnSize)
    collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -TRACKER_HEADER_BTN_GAP, 0)
    collapseBtn:SetFrameLevel(header:GetFrameLevel() + 5)
    if CanApplyTrackerHeaderButtonChrome(collapseBtn) and ApplyVisuals then
        ApplyVisuals(collapseBtn, GetChromeButtonBackdrop(), chromeBorder)
    end
    local collapseTex = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseTex:SetSize(14, 14)
    collapseTex:SetPoint("CENTER")
    frame.collapseBtn = collapseBtn
    frame.collapseTex = collapseTex

    local function ApplyCollapsedState(isCollapsed)
        local tdb = GetDB()
        if tdb then tdb.collapsed = isCollapsed end
        local collapsedH = chromeBandH + (frameInset * 2)
        if isCollapsed then
            if tdb and frame:GetWidth() and frame:GetWidth() > TRACKER_COLLAPSED_MIN_WIDTH then
                tdb.width = frame:GetWidth()
            end
            collapseTex:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover")
            frame.contentArea:Hide()
            if frame.categoryBar then frame.categoryBar:Hide() end
            frame:SetResizable(false)
            frame:SetWidth(ComputeTrackerCollapsedWidth(titleText, utilityBtnSize, closeBtnW, TRACKER_HEADER_BTN_GAP, frameInset, headerUtilityRight))
            frame:SetHeight(collapsedH)
            -- Grip would sit inside the title bar and cover collapse/close â€” hide when collapsed
            if frame.resizeGrip then frame.resizeGrip:Hide() end
        else
            collapseTex:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover")
            frame.contentArea:Show()
            if frame.categoryBar then frame.categoryBar:Show() end
            frame:SetResizable(true)
            frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
            local savedW = tdb and tdb.width or 380
            if savedW < MIN_WIDTH then savedW = 380 end
            frame:SetWidth(savedW)
            local savedH = tdb and tdb.height or 420
            if savedH < MIN_HEIGHT then savedH = 420 end
            frame:SetHeight(savedH)
            if frame.resizeGrip then frame.resizeGrip:Show() end
            RefreshTrackerContent()
        end
    end

    collapseBtn:SetScript("OnClick", function()
        local tdb = GetDB()
        local isCollapsed = tdb and tdb.collapsed or false
        ApplyCollapsedState(not isCollapsed)
    end)
    collapseBtn:SetScript("OnEnter", function()
        collapseTex:SetVertexColor(COLORS.textBright[1], COLORS.textBright[2], COLORS.textBright[3])
        if CanApplyTrackerHeaderButtonChrome(collapseBtn) and ApplyVisuals then
            local hoverBg = (ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop()) or GetControlChromeBackdrop()
            ApplyVisuals(collapseBtn, hoverBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end
    end)
    collapseBtn:SetScript("OnLeave", function()
        collapseTex:SetVertexColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        if CanApplyTrackerHeaderButtonChrome(collapseBtn) and ApplyVisuals then
            ApplyVisuals(collapseBtn, GetChromeButtonBackdrop(), chromeBorder)
        end
    end)

    -- Settings (gear) button + opacity popup
    local gearBtn = CreateTrackerHeaderIconButton(header, utilityBtnSize)
    gearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -TRACKER_HEADER_BTN_GAP, 0)
    gearBtn:SetFrameLevel(header:GetFrameLevel() + 5)
    if CanApplyTrackerHeaderButtonChrome(gearBtn) and ApplyVisuals then
        ApplyVisuals(gearBtn, GetChromeButtonBackdrop(), chromeBorder)
    end
    local gearTex = gearBtn:CreateTexture(nil, "ARTWORK")
    gearTex:SetSize(14, 14)
    gearTex:SetPoint("CENTER")
    gearTex:SetTexture("Interface\\Icons\\Trade_Engineering")
    gearTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    gearTex:SetVertexColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])

    titleText:SetPoint("RIGHT", gearBtn, "LEFT", -10, 0)
    titleText:SetWordWrap(false)
    titleText:SetMaxLines(1)

    local settingsPopup
    local function BuildSettingsPopup()
        if settingsPopup then return settingsPopup end
        local popup = Factory:CreateContainer(frame, 200, 64, false)
        if not popup then
            popup = CreateFrame("Frame", nil, frame)
            popup:SetSize(200, 64)
        end
        popup:SetPoint("TOPRIGHT", gearBtn, "BOTTOMRIGHT", 0, -4)
        popup:SetFrameStrata(frame:GetFrameStrata())
        popup:SetFrameLevel(frame:GetFrameLevel() + 50)
        if ApplyTrackerChrome then
            local popupBg = (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop()) or GetControlChromeBackdrop()
            ApplyTrackerChrome(popup, popupBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 }, "popup")
        end

        local label = FontManager:CreateFontString(popup, "small", "OVERLAY")
        label:SetPoint("TOPLEFT", 10, -8)
        local opacityLabel = "Opacity"

        local valueText = FontManager:CreateFontString(popup, "small", "OVERLAY")
        valueText:SetPoint("TOPRIGHT", -10, -8)

        local current = (GetDB() and GetDB().opacity) or 1.0
        local function FormatLabel(v)
            local mutedHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffcccccc"
            local brightHex = (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
            label:SetText(mutedHex .. opacityLabel .. "|r")
            valueText:SetText(brightHex .. format("%d%%|r", math.floor(v * 100 + 0.5)))
        end

        local slider = Factory:CreateThemedSlider(popup, {
            min = 0.2, max = 1.0, step = 0.05, value = current, height = 16,
            onChange = function(v)
                v = math.max(0.2, math.min(1.0, v))
                FormatLabel(v)
                frame:SetAlpha(v)
                local d = GetDB()
                if d then d.opacity = v end
            end,
        })
        slider:SetPoint("TOPLEFT", 10, -28)
        slider:SetPoint("TOPRIGHT", -10, -28)
        FormatLabel(current)

        popup:Hide()
        settingsPopup = popup
        return popup
    end

    gearBtn:SetScript("OnClick", function()
        local popup = BuildSettingsPopup()
        if not popup then return end
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
    gearBtn:SetScript("OnEnter", function()
        gearTex:SetVertexColor(COLORS.textBright[1], COLORS.textBright[2], COLORS.textBright[3])
        if CanApplyTrackerHeaderButtonChrome(gearBtn) and ApplyVisuals then
            local hoverBg = (ns.UI_GetControlChromeHoverBackdrop and ns.UI_GetControlChromeHoverBackdrop()) or GetControlChromeBackdrop()
            ApplyVisuals(gearBtn, hoverBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end
    end)
    gearBtn:SetScript("OnLeave", function()
        gearTex:SetVertexColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        if CanApplyTrackerHeaderButtonChrome(gearBtn) and ApplyVisuals then
            ApplyVisuals(gearBtn, GetChromeButtonBackdrop(), chromeBorder)
        end
    end)

    frame._applyHeaderChromeIdle = function()
        if closeBtn and CanApplyTrackerHeaderButtonChrome(closeBtn) and ApplyVisuals then
            ApplyVisuals(closeBtn, GetChromeButtonBackdrop(), chromeBorder)
            ApplyVisuals(collapseBtn, GetChromeButtonBackdrop(), chromeBorder)
            ApplyVisuals(gearBtn, GetChromeButtonBackdrop(), chromeBorder)
        end
        if closeBtn and closeBtn._wnCloseTex then
            closeBtn._wnCloseTex:SetVertexColor(closeR, closeG, closeB)
        end
        collapseTex:SetVertexColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
        gearTex:SetVertexColor(COLORS.textNormal[1], COLORS.textNormal[2], COLORS.textNormal[3])
    end

    -- â”€â”€ Custom themed category dropdown â”€â”€
    local catBar, dropdown = CreateThemedCategoryDropdown(frame, function()
        RefreshTrackerContent()
    end, { chromeBandH = chromeBandH, bodyLay = eaLay })
    frame.categoryDropdown = dropdown
    frame.categoryBar = catBar

    -- â”€â”€ Content area: region below header+category, above bottom â”€â”€
    -- Factory's CreateScrollFrame parents ScrollUpBtn/ScrollDownBtn to scrollFrame:GetParent()
    -- and anchors them to parent TOPRIGHT/BOTTOMRIGHT. We create an intermediate frame so
    -- the buttons anchor to the scroll region, not the whole window.
    local scrollTopOffset = chromeBandH + TRACKER_ROW_BELOW_CHROME + CATEGORY_BAR_HEIGHT + TRACKER_CATEGORY_TO_CONTENT_GAP
    local contentArea = Factory and Factory:CreateContainer(frame, math.max(1, w), math.max(1, h - scrollTopOffset - shellInset), false)
    if not contentArea then
        contentArea = CreateFrame("Frame", nil, frame)
    end
    contentArea:SetPoint("TOPLEFT", frame, "TOPLEFT", shellInset, -scrollTopOffset)
    contentArea:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -shellInset, shellInset)
    frame.contentArea = contentArea
    ApplyTrackerViewportTransparent(contentArea)

    frame._plansBodyLay = eaLay
    frame._plansViewportLayout = GetTrackerViewportLayout(eaLay)

    local viewportShell = Factory and Factory:CreateContainer(contentArea, 1, 1, false)
    if not viewportShell then
        viewportShell = CreateFrame("Frame", nil, contentArea)
        viewportShell:SetSize(1, 1)
    end
    frame.contentViewportShell = viewportShell
    ApplyTrackerViewportShellInsets(frame)
    ApplyTrackerViewportShellChrome(viewportShell)

    local scrollHost, scrollFrame, scrollChild, barColumn
    if VB and VB.VBCreateEasyAccessScrollBody then
        scrollHost, scrollFrame, scrollChild, barColumn = VB.VBCreateEasyAccessScrollBody(viewportShell, {
            topY = 0,
            padLeft = 0,
            padRight = 0,
            bottom = 0,
            keepScrollLane = true,
        })
    end
    if not scrollFrame then
        scrollFrame = Factory:CreateScrollFrame(viewportShell, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", viewportShell, "TOPLEFT", 0, 0)
        scrollFrame:SetPoint("TOPRIGHT", viewportShell, "TOPRIGHT", -TRACK_SCROLL_RIGHT_RESERVE, 0)
        scrollFrame:SetPoint("BOTTOM", viewportShell, "BOTTOM", 0, 0)
        scrollFrame:EnableMouseWheel(true)
        local scrollBarColumn = Factory.CreateBareScrollBarColumn and Factory:CreateBareScrollBarColumn(viewportShell, TRACK_SB_COL_W)
            or Factory:CreateScrollBarColumn(viewportShell, TRACK_SB_COL_W, 0, 0)
        if Factory.EnsureScrollBarColumnSync then
            Factory:EnsureScrollBarColumnSync(scrollFrame, scrollBarColumn, { width = TRACK_SB_COL_W, gap = 2 })
        elseif Factory.SyncScrollBarColumnToViewport then
            Factory:SyncScrollBarColumnToViewport(scrollFrame, scrollBarColumn, { width = TRACK_SB_COL_W, gap = 2 })
        elseif scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
            Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
        end
        barColumn = scrollBarColumn
        scrollChild = Factory:CreateContainer(scrollFrame, 1, 1, false)
        if not scrollChild then
            scrollChild = CreateFrame("Frame", nil, scrollFrame)
            scrollChild:SetWidth(1)
            scrollChild:SetHeight(1)
        end
        scrollFrame:SetScrollChild(scrollChild)
        if ns.UI_EnableStandardScrollWheel then
            ns.UI_EnableStandardScrollWheel(scrollFrame)
        else
            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                if ns.UI_ScrollFrameByMouseWheel then
                    ns.UI_ScrollFrameByMouseWheel(self, delta)
                end
            end)
        end
    end
    if scrollFrame and scrollChild and ns.UI_WireScrollChildMouseWheel then
        ns.UI_WireScrollChildMouseWheel(scrollFrame, scrollChild)
    end
    if scrollHost and scrollFrame and ns.UI_ScrollFrameByMouseWheel then
        scrollHost:EnableMouseWheel(true)
        scrollHost:SetScript("OnMouseWheel", function(_, delta)
            ns.UI_ScrollFrameByMouseWheel(scrollFrame, delta)
        end)
    end
    frame.contentScrollHost = scrollHost
    frame.contentScrollFrame = scrollFrame
    frame.contentScrollChild = scrollChild
    frame.contentScrollBarColumn = barColumn
    SyncTrackerScrollBar(frame)

    -- Resize grip: window shell corner (not inside scroll content).
    local resizer = Factory and Factory.CreateButton and Factory:CreateButton(frame, 18, 18, true)
    if not resizer then
        resizer = CreateButton(frame, 18, 18, nil, nil, true)
    end
    if not resizer then
        resizer = CreateFrame("Button", nil, frame)
        resizer:SetSize(18, 18)
    end
    resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -math.max(shellInset - 2, 4), math.max(shellInset - 2, 4))
    resizer:SetFrameStrata(frame:GetFrameStrata())
    resizer:SetFrameLevel(frame:GetFrameLevel() + 40)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function()
        if not InCombatLockdown() and frame:IsResizable() then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    local trackerResizeToken = 0
    local function TrackerSatelliteLiveLayout(fr, rebuildCards)
        if fr._plansTrackerHeaderShell then
            fr._plansTrackerHeaderShell:SetWidth(math.max(1, fr:GetWidth()))
        end
        if scrollChild then
            scrollChild:SetWidth(GetTrackerContentColumnWidth(fr))
        end
        SyncTrackerScrollBar(fr)
        if rebuildCards then
            trackerResizeToken = trackerResizeToken + 1
            local token = trackerResizeToken
            C_Timer.After(0, function()
                if token ~= trackerResizeToken or not fr or not fr:IsShown() then
                    return
                end
                RefreshTrackerContent()
            end)
        end
    end

    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        TrackerSatelliteLiveLayout(frame, false)
        SyncTrackerScrollBar(frame)
        local LC = ns.UI_LayoutCoordinator
        if LC and LC.OnSatelliteMetricsChanged then
            LC:OnSatelliteMetricsChanged(frame, frame:GetWidth(), frame:GetHeight(), true)
        else
            RefreshTrackerContent()
        end
    end)
    frame.resizeGrip = resizer

    local LC = ns.UI_LayoutCoordinator
    if LC and LC.RegisterSatelliteFrame then
        LC:RegisterSatelliteFrame(frame, {
            onLive = function(fr)
                TrackerSatelliteLiveLayout(fr, true)
            end,
            onCommit = function()
                RefreshTrackerContent()
            end,
        })
    else
        frame:SetScript("OnSizeChanged", function()
            TrackerSatelliteLiveLayout(frame, true)
        end)
    end

    -- â”€â”€ Keyboard: ESC does NOT close window (close only via X button). ESC only closes dropdown if open. â”€â”€
    if not InCombatLockdown() then
        frame:EnableKeyboard(true)
        frame:SetPropagateKeyboardInput(true)
    end
    -- ESC: only close dropdown if open; never consume ESC so game can close map etc.
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            if activeDropdownMenu and activeDropdownMenu:IsShown() then
                activeDropdownMenu:Hide()
                activeDropdownMenu = nil
            end
            -- Do not call SetPropagateKeyboardInput(false) â€” let ESC propagate to game
        end
        if not InCombatLockdown() then self:SetPropagateKeyboardInput(true) end
    end)

    frame._initialShowDone = false  -- Flag to skip first OnShow (handled by creation code)
    frame:SetScript("OnShow", function()
        -- First show is handled explicitly by creation code
        if not frame._initialShowDone then return end
        
        RestorePosition(frame)
        local tdb = GetDB()
        ApplyCollapsedState(tdb and tdb.collapsed or false)
        -- Delay refresh to let layout settle
        C_Timer.After(0.05, function()
            if frame and frame:IsShown() then
                if frame.contentScrollChild then
                    frame.contentScrollChild:SetWidth(GetTrackerContentColumnWidth(frame))
                end
                RefreshTrackerContentImmediate()
            end
        end)
    end)
    frame:SetScript("OnHide", function()
        SavePosition(frame)
        -- Close dropdown menu if open
        if activeDropdownMenu and activeDropdownMenu:IsShown() then
            activeDropdownMenu:Hide()
            activeDropdownMenu = nil
        end
        -- Unregister message handler (uses PlansTrackerEvents as 'self' key)
        if frame._plansUpdatedHandler then
            WarbandNexus.UnregisterMessage(PlansTrackerEvents, E.PLANS_UPDATED)
            frame._plansUpdatedHandler = nil
        end
        -- Clear expanded achievements
        wipe(expandedAchievements)
    end)

    -- â”€â”€ Listen for plan updates â”€â”€
    -- NOTE: Uses PlansTrackerEvents as 'self' key to avoid overwriting PlansUI's handler.
    local function OnPlansUpdated()
        if frame:IsShown() then
            RefreshTrackerContent()
        end
    end
    WarbandNexus.RegisterMessage(PlansTrackerEvents, E.PLANS_UPDATED, OnPlansUpdated)
    frame._plansUpdatedHandler = OnPlansUpdated

    -- â”€â”€ Listen for font changes â”€â”€
    WarbandNexus.RegisterMessage(PlansTrackerEvents, E.FONT_CHANGED, function()
        if frame and frame:IsShown() then
            RefreshTrackerContent()
        end
    end)

    if E.UI_DEBUG_HEADER_SYNC then
        WarbandNexus.RegisterMessage(PlansTrackerEvents, E.UI_DEBUG_HEADER_SYNC, function()
            local f = GetTrackerFrame()
            if not f then return end
            SyncTrackerViewportChrome(f)
            SyncTrackerScrollBar(f)
        end)
    end

    RestorePosition(frame)
    frame:Show()
    
    -- Block any debounced refreshes until our delayed first refresh fires
    pendingRefresh = true
    
    -- Apply initial collapsed state (OnShow is skipped for first show)
    local initDB = GetDB()
    ApplyCollapsedState(initDB and initDB.collapsed or false)
    
    -- Mark initial show as done â€” subsequent OnShow will handle itself
    frame._initialShowDone = true
    
    -- Delay first refresh to let scroll frame dimensions settle after layout
    C_Timer.After(0.05, function()
        pendingRefresh = false  -- Unblock debounced refreshes
        if frame and frame:IsShown() then
            -- Force scrollChild width from frame dimensions as fallback
            if frame.contentScrollChild then
                frame.contentScrollChild:SetWidth(GetTrackerContentColumnWidth(frame))
            end
            RefreshTrackerContentImmediate()
        end
    end)
end

function WarbandNexus:ShowPlansTrackerWindow()
    if not self.CreatePlansTrackerWindow then return end
    self:CreatePlansTrackerWindow()
end

function WarbandNexus:TogglePlansTrackerWindow()
    local frame = GetTrackerFrame()
    if frame and frame:IsShown() then
        frame:Hide()
        return
    end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        local L = ns.L or {}
        self:Print("|cffff8800" .. (L["TRACKING_TAB_LOCKED_TITLE"] or "Character is not tracked") .. ". " .. (L["OPEN_CHARACTERS_TAB"] or "Open Characters") .. ".|r")
        return
    end
    self:ShowPlansTrackerWindow()
end

---@return boolean closed
function ns.PlansTracker_CloseOpenDropdown()
    if activeDropdownMenu and activeDropdownMenu:IsShown() then
        activeDropdownMenu:Hide()
        activeDropdownMenu = nil
        return true
    end
    return false
end

ns.PlansTrackerWindow = ns.PlansTrackerWindow or {}
function ns.PlansTrackerWindow.RefreshTheme()
    if ns.FontManager and ns.FontManager.RefreshThemeTypography then
        ns.FontManager:RefreshThemeTypography()
    end
    local frame = GetTrackerFrame()
    if not frame then return end
    if ns.UI_ApplyFloatingWindowShellChrome then
        ns.UI_ApplyFloatingWindowShellChrome(frame)
    elseif ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    end
    if frame._plansTrackerHeaderShell and ApplyVisuals and COLORS.accent then
        if ns.UI_ApplyFloatingWindowHeaderChrome then
            ns.UI_ApplyFloatingWindowHeaderChrome(frame._plansTrackerHeaderShell)
        else
            ApplyVisuals(frame._plansTrackerHeaderShell,
                { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 },
                { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
        end
    end
    if frame.categoryBar and ApplyTrackerChrome then
        ApplyTrackerChrome(frame.categoryBar, nil, nil, "bar")
    end
    if frame.contentArea then
        ApplyTrackerViewportTransparent(frame.contentArea)
    end
    SyncTrackerViewportChrome(frame)
    SyncTrackerScrollBar(frame)
    if frame.categoryDropdown then
        ApplyTrackerDropdownChrome(frame.categoryDropdown)
    end
    if frame._applyHeaderChromeIdle then
        frame._applyHeaderChromeIdle()
    end
    if not frame:IsShown() then return end
    RefreshTrackerContentImmediate()
end
