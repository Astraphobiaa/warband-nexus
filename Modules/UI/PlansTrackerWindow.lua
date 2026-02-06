--[[
    Warband Nexus - Plans Tracker Window
    Standalone floating window (AllTheThings-style) opened via /wn plans or /wn plan.
    Resizable, movable, responsive. Shows active plans by category.
    Card layout: Icon | Name \n Description (source/vendor/zone).
    Achievements: expandable requirements + Blizzard Track button.
    
    Data flow: DB (db.global.plans) → GetActivePlans() [pure read] → UI render
    Progress: CheckPlanProgress() [API calls, cached per refresh cycle]
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateIcon = ns.UI_CreateIcon
local CreateExpandableRow = ns.UI_CreateExpandableRow
local FormatNumber = ns.UI_FormatNumber
local FormatTextNumbers = ns.UI_FormatTextNumbers
local PLAN_TYPES = ns.PLAN_TYPES
local Factory = ns.UI.Factory

-- ── Layout constants ──
local PADDING = 8
local SCROLLBAR_GAP = 22       -- 16px scrollbar + 6px gap (matches main addon UI.lua pattern)
local HEADER_HEIGHT = 30       -- compact title bar
local CATEGORY_BAR_HEIGHT = 34
local CARD_HEIGHT = 42         -- Icon + Name + Description (2-line card)
local CARD_MARGIN = 2
local ICON_SIZE = 28
local MIN_WIDTH = 280
local MIN_HEIGHT = 220
local MAX_WIDTH = 600
local MAX_HEIGHT = 800

-- Display order and labels for categories
local CATEGORY_KEYS = {
    { key = nil,             label = "All" },
    { key = "mount",         label = "Mounts" },
    { key = "pet",           label = "Pets" },
    { key = "toy",           label = "Toys" },
    { key = "illusion",      label = "Illusions" },
    { key = "title",         label = "Titles" },
    { key = "achievement",   label = "Achievements" },
    { key = "weekly_vault",  label = "Weekly Vault" },
    { key = "daily_quests",  label = "Daily Tasks" },
    { key = "custom",        label = "Custom" },
}

local currentCategoryKey = nil -- nil = All
local expandedAchievements = {} -- [achievementID] = true

-- Card colors (consistent border theme)
local CARD_BORDER = { COLORS.accent[1] * 0.7, COLORS.accent[2] * 0.7, COLORS.accent[3] * 0.7, 0.6 }
local CARD_BG = { 0.06, 0.06, 0.08, 1 }
local CARD_HOVER_BORDER = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85 }
local CARD_HOVER_BG = { 0.09, 0.09, 0.12, 1 }

-- ── Refresh debounce ──
local pendingRefresh = false
local progressCache = {} -- [planKey] = { collected = bool, ... } ; cleared each refresh cycle

-- ══════════════════════════════════════════
-- DB helpers
-- ══════════════════════════════════════════
local function GetTrackerFrame()
    return _G.WarbandNexus_PlansTracker
end

local function GetDB()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.global then return nil end
    if not WarbandNexus.db.global.plansTracker then
        WarbandNexus.db.global.plansTracker = { point = "CENTER", x = 0, y = 0, width = 380, height = 420 }
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
    db.width = frame:GetWidth()
    db.height = frame:GetHeight()
end

local function RestorePosition(frame)
    local db = GetDB()
    if not db then return end
    frame:ClearAllPoints()
    frame:SetPoint(db.point or "CENTER", UIParent, db.relativePoint or "CENTER", db.x or 0, db.y or 0)
    frame:SetSize(db.width or 380, db.height or 420)
end

-- ══════════════════════════════════════════
-- Achievement tracking (C_ContentTracking API, TWW 11.0+)
-- Enum.ContentTrackingType: Appearance=0, Mount=1, Achievement=2
-- ══════════════════════════════════════════
local CT_ACHIEVEMENT = 2 -- Enum.ContentTrackingType.Achievement

local function IsAchievementTracked(achievementID)
    if not achievementID then return false end
    -- Modern API (TWW 11.0+)
    if C_ContentTracking and C_ContentTracking.IsTracking then
        local ok, result = pcall(C_ContentTracking.IsTracking, CT_ACHIEVEMENT, achievementID)
        if ok then return result end
    end
    -- Legacy fallback (pre-11.0)
    if GetTrackedAchievements then
        local list = { GetTrackedAchievements() }
        for i = 1, #list do
            if list[i] == achievementID then return true end
        end
    end
    return false
end

local function ToggleAchievementTrack(achievementID)
    if not achievementID then return end
    -- Modern API (TWW 11.0+)
    if C_ContentTracking and C_ContentTracking.ToggleTracking then
        local stopType = (Enum and Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual) or 0
        pcall(C_ContentTracking.ToggleTracking, CT_ACHIEVEMENT, achievementID, stopType)
        return
    end
    -- Legacy fallback (pre-11.0)
    if IsAchievementTracked(achievementID) then
        if RemoveTrackedAchievement then RemoveTrackedAchievement(achievementID) end
    else
        if AddTrackedAchievement then AddTrackedAchievement(achievementID) end
    end
end

local function GetAchievementRequirementsText(achievementID)
    if not achievementID then return "" end
    local numCriteria = GetAchievementNumCriteria(achievementID)
    if not numCriteria or numCriteria == 0 then
        return "|cffffffffNo requirements (instant completion)|r"
    end
    local parts = {}
    local completedCount = 0
    for i = 1, numCriteria do
        local criteriaName, _, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(achievementID, i)
        if criteriaName and criteriaName ~= "" then
            if completed then completedCount = completedCount + 1 end
            local icon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t" or "|cffffffff•|r"
            local color = completed and "|cff44ff44" or "|cffffffff"
            local progress = ""
            if quantity and reqQuantity and reqQuantity > 0 then
                progress = string.format(" (%s/%s)", FormatNumber(quantity), FormatNumber(reqQuantity))
            end
            parts[#parts + 1] = icon .. " " .. color .. FormatTextNumbers(criteriaName) .. "|r" .. progress
        end
    end
    local pct = numCriteria > 0 and math.floor((completedCount / numCriteria) * 100) or 0
    local header = string.format("|cff00ff00%s of %s (%s%%)|r\n", FormatNumber(completedCount), FormatNumber(numCriteria), FormatNumber(pct))
    return header .. table.concat(parts, "\n")
end

-- ══════════════════════════════════════════
-- Content helpers
-- ══════════════════════════════════════════
--- Content width: derived from scrollFrame (already accounts for scrollbar gap)
local function GetContentWidth(frame)
    local sf = frame and frame.contentScrollFrame
    if sf then
        local w = sf:GetWidth()
        if w and w > 0 then return w end
    end
    -- Fallback before layout is ready
    return math.max((frame:GetWidth() or 380) - PADDING - SCROLLBAR_GAP, 200)
end

--- Short description for card subtitle
local function GetPlanDescription(plan)
    local parts = {}
    if plan.source and plan.source ~= "" then
        local src = plan.source
        if WarbandNexus.CleanSourceText then src = WarbandNexus:CleanSourceText(src) end
        parts[#parts + 1] = src
    end
    if #parts == 0 then
        local typeLabel = plan.type or "Unknown"
        for _, cat in ipairs(CATEGORY_KEYS) do
            if cat.key == plan.type then typeLabel = cat.label; break end
        end
        parts[#parts + 1] = typeLabel
    end
    local text = table.concat(parts, " · ")
    if #text > 90 then text = text:sub(1, 87) .. "..." end
    return text
end

--- Full tooltip for plan card hover
local function ShowPlanTooltip(anchor, plan)
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:AddLine(plan.name or "Unknown", 1, 1, 1, true)
    -- Type
    local typeLabel = plan.type or ""
    for _, cat in ipairs(CATEGORY_KEYS) do
        if cat.key == plan.type then typeLabel = cat.label; break end
    end
    GameTooltip:AddLine(typeLabel, 0.6, 0.8, 1)
    -- Source
    if plan.source and plan.source ~= "" then
        local src = plan.source
        if WarbandNexus.CleanSourceText then src = WarbandNexus:CleanSourceText(src) end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Source:", 0.6, 0.6, 0.6)
        GameTooltip:AddLine(src, 1, 0.82, 0, true)
    end
    if plan.zone and plan.zone ~= "" then
        GameTooltip:AddLine("Zone: " .. plan.zone, 0.5, 0.8, 0.5)
    end
    if plan.vendor and plan.vendor ~= "" then
        GameTooltip:AddLine("Vendor: " .. plan.vendor, 0.5, 0.8, 0.5)
    end
    if plan.requirement and plan.requirement ~= "" then
        GameTooltip:AddLine("Requirement: " .. plan.requirement, 1, 0.5, 0.5, true)
    end
    if plan.notes and plan.notes ~= "" then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine(plan.notes, 0.7, 0.7, 0.7, true)
    end
    -- Hint
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Right-click to remove", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

--- Cached progress check (cache cleared each refresh cycle)
local function CheckPlanProgressCached(plan)
    local key = (plan.type or "") .. ":" .. (plan.id or plan.achievementID or plan.name or "")
    if progressCache[key] ~= nil then
        return progressCache[key]
    end
    local result = WarbandNexus:CheckPlanProgress(plan)
    progressCache[key] = result or false
    return result
end

-- ══════════════════════════════════════════
-- RefreshTrackerContent (debounced)
-- ══════════════════════════════════════════
local function RefreshTrackerContentImmediate()
    local frame = GetTrackerFrame()
    if not frame or not frame.contentScrollChild then return end

    local scrollChild = frame.contentScrollChild
    local contentWidth = GetContentWidth(frame)
    scrollChild:SetWidth(contentWidth)
    local width = contentWidth

    -- Clear progress cache for this cycle
    wipe(progressCache)

    local plans = WarbandNexus:GetActivePlans() or {}

    -- Filter by category; exclude collected (cached)
    local filtered = {}
    for i = 1, #plans do
        local plan = plans[i]
        if currentCategoryKey == nil or plan.type == currentCategoryKey then
            if plan.type == "weekly_vault" or plan.type == "daily_quests" or plan.type == "custom" then
                filtered[#filtered + 1] = plan
            else
                local progress = CheckPlanProgressCached(plan)
                if not (progress and progress.collected) then
                    filtered[#filtered + 1] = plan
                end
            end
        end
    end

    -- Clear existing children
    local children = { scrollChild:GetChildren() }
    for _, c in ipairs(children) do
        c:Hide()
        c:SetParent(nil)
    end

    local yOffset = 0

    if #filtered == 0 then
        local empty = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        empty:SetPoint("TOPLEFT", PADDING, -yOffset - 12)
        empty:SetWidth(width - PADDING * 2)
        empty:SetWordWrap(true)
        empty:SetJustifyH("CENTER")
        empty:SetText("|cff666666No plans in this category.\nAdd plans from the Plans tab.|r")
        yOffset = yOffset + 50
    else
        for i = 1, #filtered do
            local plan = filtered[i]
            local isAchievement = (plan.type == "achievement")

            if isAchievement and plan.achievementID then
                -- ── Achievement: expandable row ──
                local isExpanded = expandedAchievements[plan.achievementID]
                local infoText = GetPlanDescription(plan)
                if infoText ~= "" then infoText = "|cff99ccff" .. infoText .. "|r" end
                local requirementsText = GetAchievementRequirementsText(plan.achievementID)
                local rowData = {
                    icon = plan.icon,
                    score = plan.points,
                    title = FormatTextNumbers(plan.name or "Achievement"),
                    information = infoText,
                    criteria = requirementsText,
                }
                local row = CreateExpandableRow(scrollChild, width, CARD_HEIGHT - 4, rowData, isExpanded, function(expanded)
                    expandedAchievements[plan.achievementID] = expanded
                    RefreshTrackerContentImmediate()
                end)
                row:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(row.headerFrame, CARD_BG, CARD_BORDER)
                end
                -- Add accent border to achievement icon (Factory creates it noBorder)
                if row.iconFrame and ApplyVisuals then
                    ApplyVisuals(row.iconFrame, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
                    -- Inset texture so it doesn't bleed into border
                    if row.iconFrame.texture then
                        local inset = 2
                        row.iconFrame.texture:ClearAllPoints()
                        row.iconFrame.texture:SetPoint("TOPLEFT", inset, -inset)
                        row.iconFrame.texture:SetPoint("BOTTOMRIGHT", -inset, inset)
                    end
                end

                -- Track button (Factory button, right side of header)
                -- CRITICAL: Raise frame level above headerFrame so button receives clicks
                -- before headerFrame's OnMouseDown (which triggers ToggleExpand)
                local trackBtn = Factory:CreateButton(row.headerFrame, 52, 18, true)
                trackBtn:SetPoint("RIGHT", row.headerFrame, "RIGHT", -4, 0)
                trackBtn:SetFrameLevel(row.headerFrame:GetFrameLevel() + 10)
                -- Block OnMouseDown propagation to headerFrame (prevents expand toggle on button click)
                trackBtn:SetScript("OnMouseDown", function() end)
                trackBtn:RegisterForClicks("AnyUp")
                local trackLabel = FontManager:CreateFontString(trackBtn, "small", "OVERLAY")
                trackLabel:SetPoint("CENTER")
                local tracked = IsAchievementTracked(plan.achievementID)
                trackLabel:SetText(tracked and "|cff44ff44Tracked|r" or "|cffffcc00Track|r")
                if ApplyVisuals then
                    ApplyVisuals(trackBtn, { 0.10, 0.10, 0.13, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5 })
                end
                trackBtn:SetScript("OnClick", function()
                    ToggleAchievementTrack(plan.achievementID)
                    -- Update label immediately (no full rebuild)
                    local nowTracked = IsAchievementTracked(plan.achievementID)
                    trackLabel:SetText(nowTracked and "|cff44ff44Tracked|r" or "|cffffcc00Track|r")
                end)
                trackBtn:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(trackBtn, "ANCHOR_TOP")
                    GameTooltip:SetText("Track in Blizzard objectives (max 10)")
                    GameTooltip:Show()
                end)
                trackBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                yOffset = yOffset + row:GetHeight() + CARD_MARGIN
            else
                -- ── Standard card: full width, bordered ──
                local card = Factory:CreateContainer(scrollChild, width, CARD_HEIGHT)
                card:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(card, CARD_BG, CARD_BORDER)
                end

                -- Icon
                local iconFrame = CreateIcon(card, plan.icon or "Interface\\Icons\\INV_Misc_QuestionMark", ICON_SIZE, false, nil, false)
                iconFrame:SetPoint("LEFT", PADDING, 0)
                iconFrame:Show()

                -- Name (right of icon, top)
                local nameText = FontManager:CreateFontString(card, "body", "OVERLAY")
                nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 6, -3)
                nameText:SetPoint("RIGHT", card, "RIGHT", -PADDING, 0)
                nameText:SetJustifyH("LEFT")
                nameText:SetWordWrap(false)
                nameText:SetText("|cffffffff" .. FormatTextNumbers(plan.name or "Unknown") .. "|r")

                -- Description (below name)
                local descText = FontManager:CreateFontString(card, "small", "OVERLAY")
                descText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
                descText:SetPoint("RIGHT", card, "RIGHT", -PADDING, 0)
                descText:SetJustifyH("LEFT")
                descText:SetWordWrap(false)
                descText:SetText("|cff888888" .. GetPlanDescription(plan) .. "|r")

                -- Hover: highlight border + full tooltip
                card:EnableMouse(true)
                card:SetScript("OnEnter", function()
                    if ApplyVisuals then
                        ApplyVisuals(card, CARD_HOVER_BG, CARD_HOVER_BORDER)
                    end
                    ShowPlanTooltip(card, plan)
                end)
                card:SetScript("OnLeave", function()
                    if ApplyVisuals then
                        ApplyVisuals(card, CARD_BG, CARD_BORDER)
                    end
                    GameTooltip:Hide()
                end)
                -- Right-click to remove plan
                card:SetScript("OnMouseDown", function(_, button)
                    if button == "RightButton" and plan.id then
                        WarbandNexus:RemovePlan(plan.id)
                        RefreshTrackerContent()
                    end
                end)

                yOffset = yOffset + CARD_HEIGHT + CARD_MARGIN
            end
        end
    end

    -- Update count label
    local frame = GetTrackerFrame()
    if frame and frame.categoryBar and frame.categoryBar.countLabel then
        local total = WarbandNexus:GetActivePlans() or {}
        frame.categoryBar.countLabel:SetText("|cff888888" .. #filtered .. "/" .. #total .. " plans|r")
    end

    -- Set scrollChild height: at least viewport size (required for WoW scroll frame)
    local scrollFrame = frame.contentScrollFrame
    local viewportHeight = scrollFrame and scrollFrame:GetHeight() or 1
    scrollChild:SetHeight(math.max(yOffset + 4, viewportHeight))
    if scrollFrame then
        if scrollFrame.UpdateScrollChildRect then
            scrollFrame:UpdateScrollChildRect()
        end
        -- Update scrollbar visibility (show only when content overflows)
        if scrollFrame.UpdateScrollBarVisibility then
            scrollFrame:UpdateScrollBarVisibility()
        elseif Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scrollFrame)
        end
    end
end

--- Debounced refresh: batches rapid calls into a single frame-deferred refresh
local function RefreshTrackerContent()
    if pendingRefresh then return end
    pendingRefresh = true
    C_Timer.After(0, function()
        pendingRefresh = false
        RefreshTrackerContentImmediate()
    end)
end

-- ══════════════════════════════════════════
-- Custom themed dropdown (matches SettingsUI pattern)
-- ══════════════════════════════════════════
local activeDropdownMenu = nil

local function CreateThemedCategoryDropdown(parent, onCategorySelected)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(CATEGORY_BAR_HEIGHT)
    bar:SetPoint("TOPLEFT", PADDING, -(HEADER_HEIGHT + PADDING))
    bar:SetPoint("TOPRIGHT", -PADDING, -(HEADER_HEIGHT + PADDING))

    -- Dropdown button (Factory)
    local dropdown = Factory:CreateButton(bar, 150, 26, false)
    dropdown:SetPoint("LEFT", 0, 0)
    if ApplyVisuals then
        ApplyVisuals(dropdown, { 0.08, 0.08, 0.10, 1 }, { COLORS.accent[1] * 0.5, COLORS.accent[2] * 0.5, COLORS.accent[3] * 0.5, 0.6 })
    end

    -- Value text
    local valueText = FontManager:CreateFontString(dropdown, "body", "OVERLAY")
    valueText:SetPoint("LEFT", 10, 0)
    valueText:SetPoint("RIGHT", -24, 0)
    valueText:SetJustifyH("LEFT")
    valueText:SetText("All")

    -- Arrow icon
    local arrow = dropdown:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -8, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetTexCoord(0, 1, 0, 1)
    arrow:SetVertexColor(0.7, 0.7, 0.7)

    -- Plan count label (right side of bar)
    local countLabel = FontManager:CreateFontString(bar, "small", "OVERLAY")
    countLabel:SetPoint("RIGHT", -4, 0)
    countLabel:SetJustifyH("RIGHT")
    bar.countLabel = countLabel

    local function UpdateLabel(key)
        local label = "All"
        for _, c in ipairs(CATEGORY_KEYS) do
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
        local contentHeight = math.min(itemCount * itemHeight, 300)
        local menuWidth = self:GetWidth()

        -- Create menu (Factory container)
        local menu = Factory:CreateContainer(UIParent, menuWidth, contentHeight + 8)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetFrameLevel(300)
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)
        menu:SetClampedToScreen(true)
        if ApplyVisuals then
            ApplyVisuals(menu, { 0.08, 0.08, 0.10, 0.98 }, { COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 0.8 })
        end
        activeDropdownMenu = menu

        -- Scroll frame inside menu (for many items)
        local scrollFrame = Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", 4, -4)
        scrollFrame:SetPoint("BOTTOMRIGHT", -22, 4)
        scrollFrame:EnableMouseWheel(true)

        local scrollChild = Factory:CreateContainer(scrollFrame, menuWidth - 8, itemCount * itemHeight)
        scrollFrame:SetScrollChild(scrollChild)

        scrollFrame:SetScript("OnMouseWheel", function(sf, delta)
            local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 16
            local cur = sf:GetVerticalScroll()
            local maxS = sf:GetVerticalScrollRange()
            sf:SetVerticalScroll(math.max(0, math.min(cur - (delta * step), maxS)))
        end)

        if Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scrollFrame)
        end

        -- Create option buttons
        local yPos = 0
        local btnWidth = menuWidth - 8
        for _, cat in ipairs(CATEGORY_KEYS) do
            local btn = Factory:CreateButton(scrollChild, btnWidth, itemHeight, true)
            btn:SetPoint("TOPLEFT", 0, -yPos)

            local btnText = FontManager:CreateFontString(btn, "body", "OVERLAY")
            btnText:SetPoint("LEFT", 10, 0)
            btnText:SetText(cat.label)

            -- Highlight current selection
            if currentCategoryKey == cat.key then
                btnText:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
            else
                btnText:SetTextColor(1, 1, 1)
            end

            -- Hover visual
            if ApplyVisuals then
                ApplyVisuals(btn, { 0.08, 0.08, 0.10, 0 }, { 0, 0, 0, 0 })
            end
            if Factory.ApplyHighlight then
                Factory:ApplyHighlight(btn)
            end

            btn:SetScript("OnClick", function()
                currentCategoryKey = cat.key
                UpdateLabel(cat.key)
                menu:Hide()
                activeDropdownMenu = nil
                if onCategorySelected then onCategorySelected(cat.key) end
            end)

            yPos = yPos + itemHeight
        end

        menu:Show()

        -- Close on click outside (same pattern as SettingsUI)
        C_Timer.After(0.05, function()
            if menu and menu:IsShown() then
                menu:SetScript("OnUpdate", function(menuSelf)
                    if not MouseIsOver(menuSelf) and not MouseIsOver(self) then
                        if IsMouseButtonDown() then
                            menuSelf:Hide()
                            activeDropdownMenu = nil
                        end
                    end
                end)
            end
        end)
    end)

    -- Hover on dropdown button
    dropdown:SetScript("OnEnter", function()
        arrow:SetVertexColor(1, 1, 1)
        if ApplyVisuals then
            ApplyVisuals(dropdown, { 0.10, 0.10, 0.13, 1 }, { COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 0.8 })
        end
    end)
    dropdown:SetScript("OnLeave", function()
        arrow:SetVertexColor(0.7, 0.7, 0.7)
        if ApplyVisuals then
            ApplyVisuals(dropdown, { 0.08, 0.08, 0.10, 1 }, { COLORS.accent[1] * 0.5, COLORS.accent[2] * 0.5, COLORS.accent[3] * 0.5, 0.6 })
        end
    end)

    currentCategoryKey = nil
    return bar, dropdown
end

-- ══════════════════════════════════════════
-- Window creation
-- ══════════════════════════════════════════
function WarbandNexus:CreatePlansTrackerWindow()
    local frame = GetTrackerFrame()
    if frame then
        frame:Show()
        RestorePosition(frame)
        RefreshTrackerContent()
        return
    end

    local db = GetDB()
    local w = db and db.width or 380
    local h = db and db.height or 420

    -- ── Main frame ──
    frame = CreateFrame("Frame", "WarbandNexus_PlansTracker", UIParent)
    frame:SetSize(w, h)
    frame:SetFrameStrata("HIGH")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    frame:SetClampedToScreen(true)

    if ApplyVisuals then
        ApplyVisuals(frame, { 0.04, 0.04, 0.06, 0.97 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
    end

    -- ── Header (compact, draggable) ──
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
    header:EnableMouse(true)
    header:RegisterForDrag("LeftButton")
    header:SetScript("OnDragStart", function() frame:StartMoving() end)
    header:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
    end)
    if ApplyVisuals then
        ApplyVisuals(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 },
            { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end

    -- Header icon
    local hIcon = header:CreateTexture(nil, "ARTWORK")
    hIcon:SetSize(18, 18)
    hIcon:SetPoint("LEFT", PADDING + 2, 0)
    hIcon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")

    -- Title
    local titleText = FontManager:CreateFontString(header, "body", "OVERLAY")
    titleText:SetPoint("LEFT", hIcon, "RIGHT", 6, 0)
    titleText:SetText("|cffffffffCollection Plans|r")

    -- Close button (Factory)
    local closeBtn = Factory:CreateButton(header, 22, 22, true)
    closeBtn:SetPoint("RIGHT", -PADDING, 0)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, { 0.15, 0.15, 0.15, 0.8 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetSize(12, 12)
    closeTex:SetPoint("CENTER")
    closeTex:SetAtlas("uitools-icon-close")
    closeTex:SetVertexColor(0.9, 0.3, 0.3)
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetScript("OnEnter", function()
        closeTex:SetVertexColor(1, 0.15, 0.15)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, { 0.3, 0.08, 0.08, 0.9 }, { 1, 0.1, 0.1, 0.9 })
        end
    end)
    closeBtn:SetScript("OnLeave", function()
        closeTex:SetVertexColor(0.9, 0.3, 0.3)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, { 0.15, 0.15, 0.15, 0.8 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
        end
    end)

    -- ── Custom themed category dropdown ──
    local catBar, dropdown = CreateThemedCategoryDropdown(frame, function()
        RefreshTrackerContent()
    end)
    frame.categoryDropdown = dropdown
    frame.categoryBar = catBar

    -- ── Content area: region below header+category, above bottom ──
    -- Factory's CreateScrollFrame parents ScrollUpBtn/ScrollDownBtn to scrollFrame:GetParent()
    -- and anchors them to parent TOPRIGHT/BOTTOMRIGHT. We create an intermediate frame so
    -- the buttons anchor to the scroll region, not the whole window.
    local scrollTopOffset = HEADER_HEIGHT + CATEGORY_BAR_HEIGHT + PADDING
    local contentArea = CreateFrame("Frame", nil, frame)
    contentArea:SetPoint("TOPLEFT", 0, -scrollTopOffset)
    contentArea:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.contentArea = contentArea

    -- ── Scroll frame inside content area ──
    local scrollFrame = Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, 0)
    scrollFrame:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -SCROLLBAR_GAP, 0)
    scrollFrame:SetPoint("BOTTOM", contentArea, "BOTTOM", 0, PADDING)
    scrollFrame:EnableMouseWheel(true)
    frame.contentScrollFrame = scrollFrame

    -- ── Fix scroll button positions for clean Button-Bar-Button vertical layout ──
    -- Factory hardcodes buttons to parent TOPRIGHT(-8,-8) / BOTTOMRIGHT(-8,8),
    -- which doesn't match our layout. Reposition after creation.
    if scrollFrame.ScrollBar then
        local sb = scrollFrame.ScrollBar
        -- ScrollUpBtn: flush with top of contentArea, aligned with scrollbar
        if sb.ScrollUpBtn then
            sb.ScrollUpBtn:ClearAllPoints()
            sb.ScrollUpBtn:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -3, 0)
        end
        -- ScrollDownBtn: flush with bottom of contentArea (with padding)
        if sb.ScrollDownBtn then
            sb.ScrollDownBtn:ClearAllPoints()
            sb.ScrollDownBtn:SetPoint("BOTTOMRIGHT", contentArea, "BOTTOMRIGHT", -3, PADDING + 12)
        end
        -- ScrollBar already anchored between buttons by Factory (TOP→UpBtn.BOTTOM, BOTTOM→DownBtn.TOP)
    end

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(1)  -- Temporary, updated dynamically on first refresh
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)
    frame.contentScrollChild = scrollChild

    -- Mouse wheel scrolling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local step = ns.UI_GetScrollStep and ns.UI_GetScrollStep() or 16
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local newScroll = math.max(0, math.min(current - (delta * step), maxScroll))
        self:SetVerticalScroll(newScroll)
    end)

    -- ── Resize grip (bottom-right) ──
    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(16, 16)
    resizer:SetPoint("BOTTOMRIGHT", -2, 2)
    resizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizer:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        local sw = scrollFrame:GetWidth()
        if sw and sw > 0 then
            scrollChild:SetWidth(sw)
        end
        RefreshTrackerContent()
    end)

    -- Resize: only update layout when user releases (no continuous render during drag)
    frame:SetScript("OnSizeChanged", function(self, newW, newH)
        local sw = scrollFrame:GetWidth()
        if sw and sw > 0 then
            scrollChild:SetWidth(sw)
        end
    end)

    -- ── Keyboard: only Escape consumed, rest propagates (WASD movement) ──
    frame:EnableKeyboard(true)
    frame:SetPropagateKeyboardInput(true)
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
            -- Close dropdown menu if open
            if activeDropdownMenu and activeDropdownMenu:IsShown() then
                activeDropdownMenu:Hide()
                activeDropdownMenu = nil
            end
        else
            self:SetPropagateKeyboardInput(true)
        end
    end)

    frame:SetScript("OnShow", function()
        RestorePosition(frame)
        RefreshTrackerContent()
    end)
    frame:SetScript("OnHide", function()
        SavePosition(frame)
        -- Close dropdown menu if open
        if activeDropdownMenu and activeDropdownMenu:IsShown() then
            activeDropdownMenu:Hide()
            activeDropdownMenu = nil
        end
    end)

    -- ── Listen for plan updates ──
    WarbandNexus:RegisterMessage("WN_PLANS_UPDATED", function()
        if frame:IsShown() then
            RefreshTrackerContent()
        end
    end)

    RestorePosition(frame)
    frame:Show()
    RefreshTrackerContent()
end

function WarbandNexus:ShowPlansTrackerWindow()
    if not self.CreatePlansTrackerWindow then return end
    self:CreatePlansTrackerWindow()
end

function WarbandNexus:TogglePlansTrackerWindow()
    local frame = GetTrackerFrame()
    if frame and frame:IsShown() then
        frame:Hide()
    else
        self:ShowPlansTrackerWindow()
    end
end
