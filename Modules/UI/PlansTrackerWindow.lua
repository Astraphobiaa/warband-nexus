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

-- Import UI spacing constants
local UI_SPACING = ns.UI_SPACING or {
    TOP_MARGIN = 8,
    HEADER_HEIGHT = 32,
    SIDE_MARGIN = 10,
    AFTER_ELEMENT = 8,
}

-- ── Layout constants ──
local PADDING = UI_SPACING.TOP_MARGIN
local SCROLLBAR_GAP = 22       -- 16px scrollbar + 6px gap (matches main addon UI.lua pattern)
local HEADER_HEIGHT = UI_SPACING.HEADER_HEIGHT
local CATEGORY_BAR_HEIGHT = 34
local CARD_HEIGHT = 42         -- Icon + Name + Description (2-line card)
local CARD_MARGIN = 2          -- Tracker-specific card margin (intentionally smaller than standard)
local ICON_SIZE = 28
local MIN_WIDTH = 280
local MIN_HEIGHT = 220
local MAX_WIDTH = 600
local MAX_HEIGHT = 800

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
        { key = "weekly_vault",  label = (L and L["WEEKLY_VAULT"]) or "Weekly Vault" },
        { key = "daily_quests",  label = (L and L["CATEGORY_DAILY_TASKS"]) or "Daily Tasks" },
        { key = "custom",        label = (L and L["CUSTOM"]) or "Custom" },
    }
end
local CATEGORY_KEYS = GetCategoryKeys()

local currentCategoryKey = nil -- nil = All
local expandedAchievements = {} -- [achievementID] = true
local expandedVaults = {} -- [planID] = true

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
        WarbandNexus.db.global.plansTracker = { point = "CENTER", x = 0, y = 0, width = 380, height = 420, collapsed = false }
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
        local noReqs = (ns.L and ns.L["NO_REQUIREMENTS"]) or "No requirements (instant completion)"
        return "|cffffffff" .. noReqs .. "|r"
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
    local achieveFmt = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_FORMAT"]) or "%s of %s (%s%%)"
    local header = string.format("|cff00ff00" .. achieveFmt .. "|r\n", FormatNumber(completedCount), FormatNumber(numCriteria), FormatNumber(pct))
    return header .. table.concat(parts, "\n")
end

-- ══════════════════════════════════════════
-- Content helpers
-- ══════════════════════════════════════════
--- Content width: derived from scrollFrame (already accounts for scrollbar gap)
local function GetContentWidth(frame)
    local sf = frame and frame.contentScrollFrame
    if sf then
        local w = sf and sf:GetWidth() or nil
        if w and w > 0 then return w end
    end
    -- Fallback before layout is ready
    return math.max((frame and frame:GetWidth() or 380) - PADDING - SCROLLBAR_GAP, 200)
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
        local typeLabel = plan.type or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        for _, cat in ipairs(CATEGORY_KEYS) do
            if cat.key == plan.type then typeLabel = cat.label; break end
        end
        parts[#parts + 1] = typeLabel
    end
    local text = table.concat(parts, " · ")
    if #text > 90 then text = text:sub(1, 87) .. "..." end
    return text
end

--- Full tooltip for plan card hover (uses addon's custom TooltipService)
local function ShowPlanTooltip(anchor, plan, isExpanded)
    local TooltipService = ns.TooltipService
    if not TooltipService then return end

    local displayName = (WarbandNexus.GetPlanDisplayName and WarbandNexus:GetPlanDisplayName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    local planIcon = (WarbandNexus.GetPlanDisplayIcon and WarbandNexus:GetPlanDisplayIcon(plan)) or plan.icon
    local iconIsAtlas = ns.Utilities:IsAtlasName(planIcon)

    local lines = {}

    -- Description (custom plan note / achievement description)
    local desc = plan.description or plan.note or ""
    if (desc == "" or desc == "Custom plan") and plan.type == "achievement" and plan.achievementID then
        local _, _, _, _, _, _, _, achDesc = GetAchievementInfo(plan.achievementID)
        if achDesc and achDesc ~= "" then desc = achDesc end
    end
    if desc ~= "" and desc ~= "Custom plan" and desc ~= ((ns.L and ns.L["CUSTOM_PLAN_SOURCE"]) or "Custom plan") then
        lines[#lines + 1] = { text = desc, color = {0.8, 0.8, 0.8}, wrap = true }
        lines[#lines + 1] = { type = "spacer", height = 4 }
    end

    -- Source
    if plan.source and plan.source ~= "" then
        local src = plan.source
        if WarbandNexus.CleanSourceText then src = WarbandNexus:CleanSourceText(src) end
        local sourceLabel = (ns.L and ns.L["SOURCE_LABEL"]) or "Source:"
        lines[#lines + 1] = { left = sourceLabel, right = src, leftColor = {0.6, 0.6, 0.6}, rightColor = {1, 0.82, 0} }
    end

    -- Zone / Vendor
    if plan.zone and plan.zone ~= "" then
        local zoneLabel = (ns.L and ns.L["ZONE_LABEL"]) or "Zone:"
        lines[#lines + 1] = { left = zoneLabel, right = plan.zone, leftColor = {0.6, 0.6, 0.6}, rightColor = {0.5, 0.8, 0.5} }
    end
    if plan.vendor and plan.vendor ~= "" then
        local vendorLabel = (ns.L and ns.L["VENDOR_LABEL"]) or "Vendor:"
        lines[#lines + 1] = { left = vendorLabel, right = plan.vendor, leftColor = {0.6, 0.6, 0.6}, rightColor = {0.5, 0.8, 0.5} }
    end

    -- Requirement
    if plan.requirement and plan.requirement ~= "" then
        local reqLabel = (ns.L and ns.L["REQUIREMENT_LABEL"]) or "Requirement:"
        lines[#lines + 1] = { left = reqLabel, right = plan.requirement, leftColor = {0.6, 0.6, 0.6}, rightColor = {1, 0.5, 0.5} }
    end

    -- Achievement requirements (only when collapsed — expanded cards already show them)
    if plan.type == "achievement" and plan.achievementID and not isExpanded then
        local numCriteria = GetAchievementNumCriteria(plan.achievementID)
        if numCriteria and numCriteria > 0 then
            lines[#lines + 1] = { type = "spacer", height = 4 }
            local completedCount = 0
            local criteriaLines = {}
            for i = 1, numCriteria do
                local criteriaName, _, completed, quantity, reqQuantity = GetAchievementCriteriaInfo(plan.achievementID, i)
                if criteriaName and criteriaName ~= "" then
                    if completed then completedCount = completedCount + 1 end
                    local icon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t" or "|cffffffff•|r"
                    local color = completed and {0.27, 1, 0.27} or {1, 1, 1}
                    local progress = ""
                    if quantity and reqQuantity and reqQuantity > 0 then
                        progress = string.format(" (%s/%s)", FormatNumber(quantity), FormatNumber(reqQuantity))
                    end
                    criteriaLines[#criteriaLines + 1] = { text = icon .. " " .. criteriaName .. progress, color = color }
                end
            end

            -- Header: "X of Y (Z%)"
            local pct = numCriteria > 0 and math.floor((completedCount / numCriteria) * 100) or 0
            local achieveFmt = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_FORMAT"]) or "%s of %s (%s%%)"
            local header = string.format(achieveFmt, FormatNumber(completedCount), FormatNumber(numCriteria), FormatNumber(pct))
            lines[#lines + 1] = { text = header, color = {0.3, 1, 0.3} }

            -- 3-column layout: group criteria into rows of 3
            local cols = 3
            for row = 1, math.ceil(#criteriaLines / cols) do
                local startIdx = (row - 1) * cols + 1
                local rowParts = {}
                for c = 0, cols - 1 do
                    local entry = criteriaLines[startIdx + c]
                    if entry then
                        local colorCode = string.format("|cff%02x%02x%02x", math.floor(entry.color[1]*255), math.floor(entry.color[2]*255), math.floor(entry.color[3]*255))
                        rowParts[#rowParts + 1] = colorCode .. entry.text .. "|r"
                    end
                end
                lines[#lines + 1] = { text = table.concat(rowParts, "  "), color = {1, 1, 1}, wrap = false }
            end
        end
    end

    -- Notes
    if plan.notes and plan.notes ~= "" then
        lines[#lines + 1] = { type = "spacer", height = 4 }
        lines[#lines + 1] = { text = plan.notes, color = {0.7, 0.7, 0.7}, wrap = true }
    end

    TooltipService:Show(anchor, {
        type = "custom",
        icon = planIcon,
        iconIsAtlas = iconIsAtlas,
        title = FormatTextNumbers(displayName),
        anchor = "ANCHOR_RIGHT",
        lines = lines,
    })
end

--- Hide addon tooltip helper
local function HidePlanTooltip()
    if ns.TooltipService then
        ns.TooltipService:Hide()
    end
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
-- RefreshTrackerContent (debounced) – forward declaration
-- ══════════════════════════════════════════
local RefreshTrackerContent  -- forward declare so inner functions can reference it

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

    -- Filter by category; exclude collected/completed plans
    local filtered = {}
    for i = 1, #plans do
        local plan = plans[i]
        if currentCategoryKey == nil or plan.type == currentCategoryKey then
            if plan.type == "weekly_vault" or plan.type == "daily_quests" then
                -- Vault and daily quests always show (they reset)
                filtered[#filtered + 1] = plan
            else
                -- All other types (including custom): hide if completed/collected
                local progress = CheckPlanProgressCached(plan)
                if not (progress and progress.collected) then
                    filtered[#filtered + 1] = plan
                end
            end
        end
    end
    
    -- Sort: weekly vault first, then by type, then by ID
    table.sort(filtered, function(a, b)
        if a.type == "weekly_vault" and b.type ~= "weekly_vault" then return true end
        if a.type ~= "weekly_vault" and b.type == "weekly_vault" then return false end
        if a.type ~= b.type then return (a.type or "") < (b.type or "") end
        local aID = tonumber(a.id) or 0
        local bID = tonumber(b.id) or 0
        return aID < bID
    end)

    -- Clear existing children (frames AND their FontStrings)
    local children = { scrollChild:GetChildren() }
    for _, c in ipairs(children) do
        c:Hide()
        c:SetParent(nil)
    end
    -- Also clear any orphan regions (FontStrings created directly on scrollChild)
    for _, r in ipairs({ scrollChild:GetRegions() }) do
        r:Hide()
        r:ClearAllPoints()
    end

    local yOffset = 0

    -- Grid layout: 2 columns when wide enough, 1 column when narrow
    local cardSpacing = 4
    local numCols = (width >= 400) and 2 or 1
    local colWidth = (width - cardSpacing * (numCols - 1)) / numCols
    local gridCol = 0  -- current column index (0-based)
    local rowMaxHeight = 0  -- tallest card in current row

    if #filtered == 0 then
        -- Wrap empty state in a frame so it gets cleaned up by children cleanup
        local emptyFrame = CreateFrame("Frame", nil, scrollChild)
        emptyFrame:SetSize(width, 50)
        emptyFrame:SetPoint("TOPLEFT", 0, -yOffset)
        local empty = FontManager:CreateFontString(emptyFrame, "body", "OVERLAY")
        empty:SetPoint("TOPLEFT", PADDING, -12)
        empty:SetWidth(width - PADDING * 2)
        empty:SetWordWrap(true)
        empty:SetJustifyH("CENTER")
        local noPlansText = (ns.L and ns.L["NO_PLANS_IN_CATEGORY"]) or "No plans in this category.\nAdd plans from the Plans tab."
        empty:SetText("|cff666666" .. noPlansText .. "|r")
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
                    icon = (WarbandNexus.GetPlanDisplayIcon and WarbandNexus:GetPlanDisplayIcon(plan)) or plan.icon or "Interface\\Icons\\Achievement_Quests_Completed_08",
                    score = plan.points,
                    title = FormatTextNumbers((WarbandNexus.GetPlanDisplayName and WarbandNexus:GetPlanDisplayName(plan)) or plan.name or ((ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement")),
                    information = infoText,
                    criteria = requirementsText,
                    criteriaColumns = 2,  -- Tracker uses 2 columns (compact layout)
                }
                -- Achievements always span full width — flush grid row first
                if gridCol > 0 then
                    yOffset = yOffset + rowMaxHeight + CARD_MARGIN
                    gridCol = 0
                    rowMaxHeight = 0
                end
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
                local trackedLabel = (ns.L and ns.L["TRACKED"]) or "Tracked"
                local trackLabel2 = (ns.L and ns.L["TRACK"]) or "Track"
                trackLabel:SetText(tracked and "|cff44ff44" .. trackedLabel .. "|r" or "|cffffcc00" .. trackLabel2 .. "|r")
                if ApplyVisuals then
                    ApplyVisuals(trackBtn, { 0.10, 0.10, 0.13, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5 })
                end
                trackBtn:SetScript("OnClick", function()
                    ToggleAchievementTrack(plan.achievementID)
                    -- Update label immediately (no full rebuild)
                    local nowTracked = IsAchievementTracked(plan.achievementID)
                    local tLabel = (ns.L and ns.L["TRACKED"]) or "Tracked"
                    local uLabel = (ns.L and ns.L["TRACK"]) or "Track"
                    trackLabel:SetText(nowTracked and "|cff44ff44" .. tLabel .. "|r" or "|cffffcc00" .. uLabel .. "|r")
                end)
                trackBtn:SetScript("OnEnter", function()
                    GameTooltip:SetOwner(trackBtn, "ANCHOR_TOP")
                    local trackText = (ns.L and ns.L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)"
                    GameTooltip:SetText(trackText)
                    GameTooltip:Show()
                end)
                trackBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

                -- Achievement tooltip on header hover
                local origOnEnter = row.headerFrame:GetScript("OnEnter")
                local origOnLeave = row.headerFrame:GetScript("OnLeave")
                row.headerFrame:SetScript("OnEnter", function(self)
                    if origOnEnter then origOnEnter(self) end
                    ShowPlanTooltip(row.headerFrame, plan, isExpanded)
                end)
                row.headerFrame:SetScript("OnLeave", function(self)
                    if origOnLeave then origOnLeave(self) end
                    HidePlanTooltip()
                end)

                yOffset = yOffset + row:GetHeight() + CARD_MARGIN
            elseif plan.type == "weekly_vault" then
                -- ── Weekly Vault: expandable full-width card ──
                -- Flush grid row first
                if gridCol > 0 then
                    yOffset = yOffset + rowMaxHeight + CARD_MARGIN
                    gridCol = 0
                    rowMaxHeight = 0
                end
                
                local isExpanded = expandedVaults[plan.id]
                local VAULT_HEADER_HEIGHT = CARD_HEIGHT
                local VAULT_ROW_HEIGHT = 22
                local VAULT_PADDING = 6
                
                -- Calculate expanded height
                local expandedHeight = VAULT_HEADER_HEIGHT + VAULT_PADDING + (VAULT_ROW_HEIGHT * 3) + VAULT_PADDING + 2
                local cardHeight = isExpanded and expandedHeight or VAULT_HEADER_HEIGHT
                
                local vaultCard = Factory:CreateContainer(scrollChild, width, cardHeight)
                vaultCard:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(vaultCard, CARD_BG, CARD_BORDER)
                end
                
                -- Header area (clickable to expand/collapse)
                local headerFrame = CreateFrame("Frame", nil, vaultCard)
                headerFrame:SetPoint("TOPLEFT", 0, 0)
                headerFrame:SetPoint("TOPRIGHT", 0, 0)
                headerFrame:SetHeight(VAULT_HEADER_HEIGHT)
                headerFrame:EnableMouse(true)
                
                -- Vault icon (atlas)
                local iconFrame = CreateIcon(headerFrame, "greatVault-whole-normal", ICON_SIZE, true, nil, false)
                iconFrame:SetPoint("LEFT", PADDING, 0)
                iconFrame:SetFrameLevel(headerFrame:GetFrameLevel() + 5)
                iconFrame:Show()
                
                -- Character name with class color
                local classColor = {1, 1, 1}
                if plan.characterClass then
                    local cc = RAID_CLASS_COLORS[plan.characterClass]
                    if cc then classColor = {cc.r, cc.g, cc.b} end
                end
                
                local nameText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
                nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 6, -2)
                nameText:SetPoint("RIGHT", headerFrame, "RIGHT", -70, 0)
                nameText:SetJustifyH("LEFT")
                nameText:SetWordWrap(false)
                nameText:SetMaxLines(1)
                local charDisplay = plan.characterName or ""
                if plan.characterRealm and plan.characterRealm ~= "" then
                    charDisplay = charDisplay .. "-" .. plan.characterRealm
                end
                nameText:SetText(string.format("|cff%02x%02x%02x%s|r", 
                    math.floor(classColor[1]*255), math.floor(classColor[2]*255), math.floor(classColor[3]*255), 
                    charDisplay))
                
                -- "Weekly Vault" subtitle
                local subtitleText = FontManager:CreateFontString(headerFrame, "small", "OVERLAY")
                subtitleText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
                subtitleText:SetText("|cff888888" .. ((ns.L and ns.L["WEEKLY_VAULT"]) or "Weekly Vault") .. "|r")
                
                -- Reset timer (compact, right side of header) — reuse shared Utilities formatter
                local resetLabel = FontManager:CreateFontString(headerFrame, "small", "OVERLAY")
                resetLabel:SetPoint("RIGHT", headerFrame, "RIGHT", -PADDING, 0)
                resetLabel:SetJustifyH("RIGHT")
                local resetTimestamp = WarbandNexus.GetWeeklyResetTime and WarbandNexus:GetWeeklyResetTime() or 0
                local resetStr = ns.Utilities:FormatTimeUntilReset(resetTimestamp)
                resetLabel:SetText("|cff66cc66" .. resetStr .. "|r")
                
                -- Expand/collapse arrow
                local arrow = headerFrame:CreateTexture(nil, "OVERLAY")
                arrow:SetSize(12, 12)
                arrow:SetPoint("RIGHT", resetLabel, "LEFT", -4, 0)
                arrow:SetAtlas(isExpanded and "campaign-headericon-open" or "campaign-headericon-closed")
                
                -- Click to expand/collapse
                headerFrame:SetScript("OnMouseDown", function()
                    expandedVaults[plan.id] = not expandedVaults[plan.id]
                    RefreshTrackerContentImmediate()
                end)
                
                -- Hover effect
                headerFrame:SetScript("OnEnter", function()
                    if ApplyVisuals then
                        ApplyVisuals(vaultCard, CARD_HOVER_BG, CARD_HOVER_BORDER)
                    end
                end)
                headerFrame:SetScript("OnLeave", function()
                    if ApplyVisuals then
                        ApplyVisuals(vaultCard, CARD_BG, CARD_BORDER)
                    end
                end)
                
                -- Expanded content: Raid / Dungeon / World progress
                if isExpanded then
                    local currentProgress = WarbandNexus:GetWeeklyVaultProgress(plan.characterName, plan.characterRealm) or {
                        dungeonCount = 0, raidBossCount = 0, worldActivityCount = 0,
                        dungeonSlots = {}, raidSlots = {}, worldSlots = {}
                    }
                    
                    local progressRows = {
                        { label = (ns.L and ns.L["VAULT_SLOT_RAIDS"]) or "Raids",     current = currentProgress.raidBossCount,       max = 6, thresholds = {2, 4, 6} },
                        { label = (ns.L and ns.L["VAULT_SLOT_DUNGEON"]) or "Dungeon",  current = currentProgress.dungeonCount,        max = 8, thresholds = {1, 4, 8} },
                        { label = (ns.L and ns.L["VAULT_SLOT_WORLD"]) or "World",      current = currentProgress.worldActivityCount,  max = 8, thresholds = {2, 4, 8} },
                    }
                    
                    local contentY = -(VAULT_HEADER_HEIGHT + VAULT_PADDING)
                    local barAreaWidth = width - PADDING * 2
                    local labelWidth = 55
                    local barWidth = barAreaWidth - labelWidth - 8
                    
                    for ri, row in ipairs(progressRows) do
                        local rowY = contentY - ((ri - 1) * VAULT_ROW_HEIGHT)
                        
                        -- Row label
                        local lbl = FontManager:CreateFontString(vaultCard, "small", "OVERLAY")
                        lbl:SetPoint("TOPLEFT", vaultCard, "TOPLEFT", PADDING, rowY)
                        lbl:SetWidth(labelWidth)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetText("|cffcccccc" .. row.label .. "|r")
                        
                        -- Progress bar background
                        local barBg = Factory:CreateContainer(vaultCard, barWidth, 14)
                        barBg:SetPoint("TOPLEFT", vaultCard, "TOPLEFT", PADDING + labelWidth + 4, rowY - 1)
                        if ApplyVisuals then
                            ApplyVisuals(barBg, {0.05, 0.05, 0.07, 0.6}, {0.3, 0.3, 0.3, 0.4})
                        end
                        
                        -- Progress fill
                        local fillPct = math.min(1.0, row.current / row.max)
                        local fillW = (barWidth - 2) * fillPct
                        if fillW > 0 then
                            local fill = barBg:CreateTexture(nil, "ARTWORK")
                            fill:SetPoint("LEFT", barBg, "LEFT", 1, 0)
                            fill:SetSize(fillW, 12)
                            fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                            fill:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
                        end
                        
                        -- Threshold markers (small ticks on bar)
                        for _, threshold in ipairs(row.thresholds) do
                            local markerPct = threshold / row.max
                            local markerX = (markerPct * (barWidth - 2)) + 1
                            local tick = barBg:CreateTexture(nil, "OVERLAY")
                            tick:SetSize(1, 14)
                            tick:SetPoint("LEFT", barBg, "LEFT", markerX, 0)
                            tick:SetTexture("Interface\\Buttons\\WHITE8x8")
                            if row.current >= threshold then
                                tick:SetVertexColor(0.2, 1, 0.2, 0.8)
                            else
                                tick:SetVertexColor(0.6, 0.6, 0.6, 0.5)
                            end
                        end
                        
                        -- Progress text on bar
                        local progText = FontManager:CreateFontString(barBg, "small", "OVERLAY")
                        progText:SetPoint("CENTER", barBg, "CENTER", 0, 0)
                        progText:SetText("|cffffffff" .. row.current .. "/" .. row.max .. "|r")
                    end
                end
                
                vaultCard:Show()
                yOffset = yOffset + cardHeight + CARD_MARGIN
            else
                -- ── Standard card: grid layout, bordered ──
                local xPos = gridCol * (colWidth + cardSpacing)
                local card = Factory:CreateContainer(scrollChild, colWidth, CARD_HEIGHT)
                card:SetPoint("TOPLEFT", xPos, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(card, CARD_BG, CARD_BORDER)
                end

                -- Icon: resolve from WoW API first, then fallback chain
                local iconTexture = (WarbandNexus.GetPlanDisplayIcon and WarbandNexus:GetPlanDisplayIcon(plan)) or plan.iconAtlas or plan.icon or PLAN_TYPE_FALLBACK_ICONS[plan.type]
                local iconIsAtlas = false
                if type(iconTexture) == "number" then
                    iconIsAtlas = false
                elseif plan.iconAtlas then
                    iconIsAtlas = true
                elseif plan.type == "custom" and plan.icon and plan.icon ~= "" then
                    iconIsAtlas = true
                elseif ns.Utilities:IsAtlasName(iconTexture) then
                    iconIsAtlas = true
                end
                if not iconTexture or iconTexture == "" then
                    iconTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
                    iconIsAtlas = false
                end
                local iconFrame = CreateIcon(card, iconTexture, ICON_SIZE, iconIsAtlas, nil, false)
                iconFrame:SetPoint("LEFT", PADDING, 0)
                iconFrame:SetFrameLevel(card:GetFrameLevel() + 5)
                iconFrame:Show()
                card:Show()
                
                -- Action buttons: Delete (X) and Complete (checkmark) at top-right
                local ACTION_SIZE = 14
                local ACTION_MARGIN = 4
                local ACTION_GAP = 2
                local rightOffset = ACTION_MARGIN
                
                -- Delete button (X icon, rightmost)
                local deleteBtn = CreateFrame("Button", nil, card)
                deleteBtn:SetSize(ACTION_SIZE, ACTION_SIZE)
                deleteBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -rightOffset, -ACTION_MARGIN)
                deleteBtn:SetFrameLevel(card:GetFrameLevel() + 10)
                deleteBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
                deleteBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
                deleteBtn:SetScript("OnClick", function()
                    if plan.id then
                        -- RemovePlan searches both db.global.plans and db.global.customPlans
                        WarbandNexus:RemovePlan(plan.id)
                        RefreshTrackerContent()
                    end
                end)
                deleteBtn:SetScript("OnEnter", function(self)
                    ns.TooltipService:Show(self, { type = "custom", title = "Delete the Plan", icon = false, anchor = "ANCHOR_TOP", lines = {} })
                end)
                deleteBtn:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                rightOffset = rightOffset + ACTION_SIZE + ACTION_GAP
                
                -- Complete button (checkmark, only for custom plans)
                if plan.type == "custom" then
                    local completeBtn = CreateFrame("Button", nil, card)
                    completeBtn:SetSize(ACTION_SIZE, ACTION_SIZE)
                    completeBtn:SetPoint("TOPRIGHT", card, "TOPRIGHT", -rightOffset, -ACTION_MARGIN)
                    completeBtn:SetFrameLevel(card:GetFrameLevel() + 10)
                    completeBtn:SetNormalTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    completeBtn:SetHighlightTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
                    completeBtn:GetHighlightTexture():SetAlpha(0.5)
                    completeBtn:SetScript("OnClick", function()
                        if WarbandNexus.CompleteCustomPlan then
                            WarbandNexus:CompleteCustomPlan(plan.id)
                        end
                    end)
                    completeBtn:SetScript("OnEnter", function(self)
                        ns.TooltipService:Show(self, { type = "custom", title = "Complete the Plan", icon = false, anchor = "ANCHOR_TOP", lines = {} })
                    end)
                    completeBtn:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                    rightOffset = rightOffset + ACTION_SIZE + ACTION_GAP
                end
                
                -- Try count text (for drop-source collectibles, shown before complete button)
                local tryCountTypes = { mount = "mountID", pet = "speciesID", toy = "itemID", illusion = "illusionID" }
                local idKey = tryCountTypes[plan.type]
                local collectibleID = idKey and (plan[idKey] or (plan.type == "illusion" and plan.sourceID))
                if collectibleID and WarbandNexus and WarbandNexus.GetTryCount then
                    local count = WarbandNexus:GetTryCount(plan.type, collectibleID)
                    if count and count > 0 then
                        local tryText = FontManager:CreateFontString(card, "small", "OVERLAY")
                        tryText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -rightOffset, -ACTION_MARGIN - 1)
                        tryText:SetText("|cffaaddff(" .. tostring(count) .. ")|r")
                        tryText:SetJustifyH("RIGHT")
                        tryText:SetWordWrap(false)
                        rightOffset = rightOffset + tryText:GetStringWidth() + ACTION_GAP
                    end
                end
                
                -- Reset timer for custom plans with reset cycle
                if plan.type == "custom" and plan.resetCycle and plan.resetCycle.enabled then
                    local resetLabel = FontManager:CreateFontString(card, "small", "OVERLAY")
                    resetLabel:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -ACTION_MARGIN, ACTION_MARGIN)
                    resetLabel:SetJustifyH("RIGHT")
                    resetLabel:SetWordWrap(false)
                    
                    local seconds = 0
                    if plan.resetCycle.resetType == "weekly" and WarbandNexus.GetWeeklyResetTime then
                        seconds = WarbandNexus:GetWeeklyResetTime() - GetServerTime()
                    elseif C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset then
                        seconds = C_DateAndTime.GetSecondsUntilDailyReset()
                    end
                    
                    local timeStr = ns.Utilities:FormatTimeCompact(seconds)
                    
                    -- Cycle progress
                    local cycleStr = ""
                    if plan.resetCycle.totalCycles and plan.resetCycle.totalCycles > 0 then
                        local remaining = plan.resetCycle.remainingCycles or 0
                        local total = plan.resetCycle.totalCycles
                        local elapsed = total - remaining
                        cycleStr = string.format(" %d/%d", elapsed, total)
                    end
                    
                    resetLabel:SetText("|cff66cc66" .. timeStr .. cycleStr .. "|r")
                end

                -- Name (right of icon, top) — limit right side to avoid overlapping action buttons
                local nameText = FontManager:CreateFontString(card, "body", "OVERLAY")
                nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 6, -3)
                nameText:SetPoint("RIGHT", card, "RIGHT", -(rightOffset + 2), 0)
                nameText:SetJustifyH("LEFT")
                nameText:SetWordWrap(false)
                nameText:SetNonSpaceWrap(false)
                nameText:SetMaxLines(1)
                local unknownName = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
                local resolvedName = (WarbandNexus.GetPlanDisplayName and WarbandNexus:GetPlanDisplayName(plan)) or plan.name or unknownName
                nameText:SetText("|cffffffff" .. FormatTextNumbers(resolvedName) .. "|r")

                -- Description (below name)
                local descText = FontManager:CreateFontString(card, "small", "OVERLAY")
                descText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
                descText:SetPoint("RIGHT", card, "RIGHT", -PADDING, 0)
                descText:SetJustifyH("LEFT")
                descText:SetWordWrap(false)
                descText:SetNonSpaceWrap(false)
                descText:SetMaxLines(1)
                descText:SetText("|cff888888" .. GetPlanDescription(plan) .. "|r")

                -- Hover: highlight border + custom tooltip
                card:EnableMouse(true)
                card:SetScript("OnEnter", function()
                    if ApplyVisuals then
                        ApplyVisuals(card, CARD_HOVER_BG, CARD_HOVER_BORDER)
                    end
                    ShowPlanTooltip(card, plan, false)
                end)
                card:SetScript("OnLeave", function()
                    if ApplyVisuals then
                        ApplyVisuals(card, CARD_BG, CARD_BORDER)
                    end
                    HidePlanTooltip()
                end)

                -- Grid column tracking
                rowMaxHeight = math.max(rowMaxHeight, CARD_HEIGHT)
                gridCol = gridCol + 1
                if gridCol >= numCols then
                    yOffset = yOffset + rowMaxHeight + CARD_MARGIN
                    gridCol = 0
                    rowMaxHeight = 0
                end
            end
        end
        -- Flush final incomplete grid row
        if gridCol > 0 then
            yOffset = yOffset + rowMaxHeight + CARD_MARGIN
        end
    end

    -- Update count label
    local frame = GetTrackerFrame()
    if frame and frame.categoryBar and frame.categoryBar.countLabel then
        local total = WarbandNexus:GetActivePlans() or {}
        local plansFormat = (ns.L and ns.L["PLANS_COUNT_FORMAT"]) or "%d plans"
        -- Extract suffix from format string (e.g., "%d plans" -> " plans")
        local suffix = plansFormat:gsub("%%d%s*", "")
        local countLabel = frame.categoryBar and frame.categoryBar.countLabel
        if countLabel then
            countLabel:SetText("|cff888888" .. #filtered .. "/" .. #total .. suffix .. "|r")
        end
    end

    -- Set scrollChild height: at least viewport size (required for WoW scroll frame)
    local scrollFrame = frame and frame.contentScrollFrame
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
    valueText:SetText((ns.L and ns.L["CATEGORY_ALL"]) or "All")

    -- Arrow icon
    local arrow = dropdown:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(12, 12)
    arrow:SetPoint("RIGHT", -UI_SPACING.SIDE_MARGIN, 0)
    arrow:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-ScrollDown-Up")
    arrow:SetTexCoord(0, 1, 0, 1)
    arrow:SetVertexColor(0.7, 0.7, 0.7)

    -- Plan count label (right side of bar)
    local countLabel = FontManager:CreateFontString(bar, "small", "OVERLAY")
    countLabel:SetPoint("RIGHT", -4, 0)
    countLabel:SetJustifyH("RIGHT")
    bar.countLabel = countLabel

    local function UpdateLabel(key)
        local label = (ns.L and ns.L["CATEGORY_ALL"]) or "All"
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
        local menu = Factory:CreateContainer(UIParent, menuWidth, contentHeight + UI_SPACING.AFTER_ELEMENT)
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

        local scrollChild = Factory:CreateContainer(scrollFrame, menuWidth - UI_SPACING.SIDE_MARGIN, itemCount * itemHeight)
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
        local btnWidth = menuWidth - UI_SPACING.SIDE_MARGIN
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

        -- Phase 4.6: Replace OnUpdate polling with click-catcher frame
        -- Create click-catcher (full-screen invisible frame)
        local clickCatcher = dropdown._clickCatcher
        if not clickCatcher then
            clickCatcher = CreateFrame("Frame", nil, UIParent)
            clickCatcher:SetAllPoints()
            clickCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
            clickCatcher:SetFrameLevel(menu:GetFrameLevel() - 1)
            clickCatcher:EnableMouse(true)
            clickCatcher:SetScript("OnMouseDown", function()
                menu:Hide()
                activeDropdownMenu = nil
                clickCatcher:Hide()
            end)
            dropdown._clickCatcher = clickCatcher
        end
        
        -- Show click-catcher when menu is shown
        clickCatcher:Show()
        
        -- Ensure click-catcher is hidden when menu is hidden
        local originalOnHide = menu:GetScript("OnHide")
        menu:SetScript("OnHide", function(menuSelf)
            if clickCatcher then
                clickCatcher:Hide()
            end
            if originalOnHide then
                originalOnHide(menuSelf)
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
    header:SetScript("OnDragStart", function()
        if not InCombatLockdown() then
            frame:StartMoving()
        end
    end)
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
    local collectionPlansLabel = (ns.L and ns.L["COLLECTION_PLANS"]) or "Collection Plans"
    titleText:SetText("|cffffffff" .. collectionPlansLabel .. "|r")

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

    -- ── Collapse/Expand toggle button ──
    local collapseBtn = Factory:CreateButton(header, 22, 22, true)
    collapseBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    if ApplyVisuals then
        ApplyVisuals(collapseBtn, { 0.15, 0.15, 0.15, 0.8 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local collapseTex = collapseBtn:CreateTexture(nil, "ARTWORK")
    collapseTex:SetSize(14, 14)
    collapseTex:SetPoint("CENTER")
    frame.collapseBtn = collapseBtn
    frame.collapseTex = collapseTex

    local function ApplyCollapsedState(isCollapsed)
        local tdb = GetDB()
        if tdb then tdb.collapsed = isCollapsed end
        if isCollapsed then
            collapseTex:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover")
            frame.contentArea:Hide()
            if frame.categoryBar then frame.categoryBar:Hide() end
            frame:SetResizable(false)
            frame:SetHeight(HEADER_HEIGHT)
        else
            collapseTex:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover")
            frame.contentArea:Show()
            if frame.categoryBar then frame.categoryBar:Show() end
            frame:SetResizable(true)
            frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
            local savedH = tdb and tdb.height or 420
            if savedH < MIN_HEIGHT then savedH = 420 end
            frame:SetHeight(savedH)
            RefreshTrackerContent()
        end
    end

    collapseBtn:SetScript("OnClick", function()
        local tdb = GetDB()
        local isCollapsed = tdb and tdb.collapsed or false
        ApplyCollapsedState(not isCollapsed)
    end)
    collapseBtn:SetScript("OnEnter", function()
        collapseTex:SetVertexColor(1, 1, 1)
        if ApplyVisuals then
            ApplyVisuals(collapseBtn, { 0.10, 0.10, 0.13, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end
    end)
    collapseBtn:SetScript("OnLeave", function()
        collapseTex:SetVertexColor(0.9, 0.9, 0.9)
        if ApplyVisuals then
            ApplyVisuals(collapseBtn, { 0.15, 0.15, 0.15, 0.8 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
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
    resizer:SetScript("OnMouseDown", function()
        if not InCombatLockdown() then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        local sw = scrollFrame and scrollFrame:GetWidth() or nil
        if sw and sw > 0 then
            scrollChild:SetWidth(sw)
        end
        RefreshTrackerContent()
    end)

    -- Resize: only update layout when user releases (no continuous render during drag)
    frame:SetScript("OnSizeChanged", function(self, newW, newH)
        local sw = scrollFrame and scrollFrame:GetWidth() or nil
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
                local sf = frame.contentScrollFrame
                if sf then
                    local sw = sf:GetWidth()
                    if sw and sw > 0 and frame.contentScrollChild then
                        frame.contentScrollChild:SetWidth(sw)
                    end
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
        -- Unregister message handler
        if frame._plansUpdatedHandler then
            WarbandNexus:UnregisterMessage("WN_PLANS_UPDATED", frame._plansUpdatedHandler)
            frame._plansUpdatedHandler = nil
        end
        -- Clear expanded achievements
        wipe(expandedAchievements)
    end)

    -- ── Listen for plan updates ──
    local function OnPlansUpdated()
        if frame:IsShown() then
            RefreshTrackerContent()
        end
    end
    WarbandNexus:RegisterMessage("WN_PLANS_UPDATED", OnPlansUpdated)
    frame._plansUpdatedHandler = OnPlansUpdated

    -- ── Listen for font changes ──
    WarbandNexus:RegisterMessage("WN_FONT_CHANGED", function()
        if frame and frame:IsShown() then
            RefreshTrackerContent()
        end
    end)

    RestorePosition(frame)
    frame:Show()
    
    -- Block any debounced refreshes until our delayed first refresh fires
    pendingRefresh = true
    
    -- Apply initial collapsed state (OnShow is skipped for first show)
    local initDB = GetDB()
    ApplyCollapsedState(initDB and initDB.collapsed or false)
    
    -- Mark initial show as done — subsequent OnShow will handle itself
    frame._initialShowDone = true
    
    -- Delay first refresh to let scroll frame dimensions settle after layout
    C_Timer.After(0.05, function()
        pendingRefresh = false  -- Unblock debounced refreshes
        if frame and frame:IsShown() then
            -- Force scrollChild width from frame dimensions as fallback
            local sf = frame.contentScrollFrame
            if sf then
                local sw = sf:GetWidth()
                if sw and sw > 0 and frame.contentScrollChild then
                    frame.contentScrollChild:SetWidth(sw)
                end
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
    else
        self:ShowPlansTrackerWindow()
    end
end
