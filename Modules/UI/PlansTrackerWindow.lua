--[[
    Warband Nexus - Plans Tracker Window
    Standalone floating window opened via /wn todo.
    Resizable, movable, responsive. Shows active plans by category.
    Card layout: Icon | Name \n Description (source/vendor/zone).
    Achievements: expandable requirements + Blizzard Track button.
    
    Data flow: DB (db.global.plans) → GetActivePlans() [pure read] → UI render
    Completion filter: IsActivePlanComplete() [live CheckPlanProgress + vault/daily rules]
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS or { accent = { 0.5, 0.4, 0.7 }, accentDark = { 0.25, 0.2, 0.35 } }
local PLAN_COLORS = ns.PLAN_UI_COLORS or {}

-- Unique AceEvent handler identity for PlansTrackerWindow
local PlansTrackerEvents = {}
local ApplyVisuals = ns.UI_ApplyVisuals
local CreateIcon = ns.UI_CreateIcon
local CreateExpandableRow = ns.UI_CreateExpandableRow
local FormatNumber = ns.UI_FormatNumber
local FormatTextNumbers = ns.UI_FormatTextNumbers
local PLAN_TYPES = ns.PLAN_TYPES
local Factory = ns.UI.Factory
local issecretvalue = issecretvalue

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
local HEADER_HEIGHT = 36  -- Modernized chrome (was UI_SPACING.HEADER_HEIGHT = 32) to match main shell
local CATEGORY_BAR_HEIGHT = 34
local CARD_HEIGHT = 48         -- Minimum collapsed achievement header (ExpandableRow); standard cards use dynamic height
local CARD_MARGIN = 8          -- Vertical gap between cards / rows (no overlap)
local MIN_GRID_CARD_H = 54     -- Minimum height for standard grid cards (icon + wrapped text)
local ICON_SIZE = 28
local MIN_WIDTH = 300
local MIN_HEIGHT = 240
local MAX_WIDTH = 600
local MAX_HEIGHT = 800
-- Strip at bottom for resize grip (scrollbar/content never draws under it)
local TRACKER_RESIZE_STRIP = 20

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
        { key = "daily_quests",  label = (L and L["CATEGORY_DAILY_TASKS"]) or "Weekly Progress" },
        { key = "custom",        label = (L and L["CUSTOM"]) or "Custom" },
    }
end
local CATEGORY_KEYS = GetCategoryKeys()

local currentCategoryKey = nil -- nil = All
local expandedAchievements = {} -- [achievementID] = true
local expandedVaults = {} -- [planID] = true
local expandedPlans = {} -- [planID] = true (mount/pet/toy/illusion/title/custom)

-- Card colors (consistent border theme; use COLORS at runtime in case ns.UI_COLORS was nil at load)
local function GetCardColors()
    local c = ns.UI_COLORS or COLORS
    if not c or not c.accent then
        c = { accent = { 0.5, 0.4, 0.7 } }
    end
    return {
        border = { c.accent[1] * 0.55, c.accent[2] * 0.55, c.accent[3] * 0.55, 0.55 },
        bg = { 0.074, 0.076, 0.095, 0.98 },
        hoverBorder = { c.accent[1], c.accent[2], c.accent[3], 0.88 },
        hoverBg = { 0.10, 0.102, 0.125, 1 },
    }
end

--- Optional 2px accent rail on the left edge of tracker cards
local function AddTrackerCardAccent(card)
    if not card or not COLORS or not COLORS.accent then return end
    local strip = card:CreateTexture(nil, "BORDER", nil, 1)
    strip:SetWidth(2)
    strip:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -1)
    strip:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 0, 1)
    strip:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.45)
end

-- ── Refresh debounce ──
local pendingRefresh = false

-- ══════════════════════════════════════════
-- DB helpers
-- ══════════════════════════════════════════
local function GetTrackerFrame()
    return _G.WarbandNexus_PlansTracker
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

local function IsAchievementTracked(achievementID)
    if WarbandNexus and WarbandNexus.IsAchievementTracked then
        return WarbandNexus:IsAchievementTracked(achievementID)
    end
    return false
end

local function ToggleAchievementTrack(achievementID)
    if not achievementID then return end
    if WarbandNexus and WarbandNexus.ToggleAchievementTracking then
        WarbandNexus:ToggleAchievementTracking(achievementID)
        return
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
            local icon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t" or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
            local color = completed and (PLAN_COLORS.completed or "|cff44ff44") or (PLAN_COLORS.incomplete or "|cffffffff")
            local progress = ""
            -- Only show progress when reqQuantity > 1 (e.g. 3/10); skip 0/1 and 1/1 for kill objectives
            if quantity and reqQuantity and reqQuantity > 1 then
                progress = string.format(" (%s / %s)", FormatNumber(quantity), FormatNumber(reqQuantity))
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

local function IsPlaceholderSourceText(sourceText)
    if type(sourceText) ~= "string" then return true end
    local s = sourceText:gsub("^%s+", ""):gsub("%s+$", "")
    if s == "" then return true end
    local unknownSource = (ns.L and ns.L["UNKNOWN_SOURCE"]) or "Unknown source"
    local sourceUnknown = (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
    return s == "Unknown" or s == unknownSource or s == "Legacy"
end

--- Short description for card subtitle (same style as My Plans: Quest/Drop/Source with icon when applicable)
local function GetPlanDescription(plan)
    -- Resolve placeholder source for mount/pet so Tracker shows correct source (e.g. Nether-Warped Drake)
    if (plan.type == "mount" or plan.type == "pet") and IsPlaceholderSourceText(plan.source) and WarbandNexus and WarbandNexus.GetPlanDisplaySource then
        local resolved = WarbandNexus:GetPlanDisplaySource(plan)
        if resolved and resolved ~= "" then
            plan.source = resolved
        end
    end
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
    -- Card UI uses word wrap; keep a generous cap for performance only
    if #text > 240 then text = text:sub(1, 237) .. "..." end
    return text
end

--- Formatted card subtitle with Quest/Drop/Source styling (matches My Plans; uses PLAN_UI_COLORS)
local function GetPlanDescriptionFormatted(plan)
    local raw = GetPlanDescription(plan)
    if not raw or raw == "" then return (PLAN_COLORS.descDim or "|cff888888") .. ((ns.L and ns.L["UNKNOWN"]) or "Unknown") .. "|r" end
    if issecretvalue and issecretvalue(raw) then
        return (PLAN_COLORS.descDim or "|cff888888") .. ((ns.L and ns.L["UNKNOWN"]) or "Unknown") .. "|r"
    end
    local srcLabel = PLAN_COLORS.sourceLabel or "|cff99ccff"
    local body = PLAN_COLORS.body or "|cffffffff"
    local dim = PLAN_COLORS.descDim or "|cff888888"
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
    if achDesc and achDesc ~= "" then return achDesc end
    return ""
end

--- Resolve parsed sources for a plan using the central WarbandNexus:ParseMultipleSources helper.
--- Mirrors PlanCardFactory:CreateSourceInfo's data path so tracker rows show the same Drop/Vendor/Quest/Zone breakdown.
---@param plan table
---@return table list of { vendor, npc, quest, zone, cost }
local function ResolveTrackerPlanSources(plan)
    if not plan then return {} end
    -- Mount/Pet: resolve placeholder source from API for parity with main UI.
    if (plan.type == "mount" or plan.type == "pet") and IsPlaceholderSourceText(plan.source) and WarbandNexus and WarbandNexus.GetPlanDisplaySource then
        local resolved = WarbandNexus:GetPlanDisplaySource(plan)
        if resolved and resolved ~= "" then plan.source = resolved end
    end
    -- Toy reliability filter (same as main UI).
    if plan.type == "toy" and plan.itemID and WarbandNexus and WarbandNexus.ResolveCollectionMetadata then
        local function reliable(s)
            if WarbandNexus.IsReliableToySource then return WarbandNexus:IsReliableToySource(s) end
            return s and s ~= ""
        end
        if not reliable(plan.source) then
            local meta = WarbandNexus:ResolveCollectionMetadata("toy", plan.itemID)
            if meta and reliable(meta.source) then plan.source = meta.source end
        end
    end
    if not plan.source or plan.source == "" or type(plan.source) ~= "string" then return {} end
    if WarbandNexus and WarbandNexus.ParseMultipleSources then
        local ok, result = pcall(function() return WarbandNexus:ParseMultipleSources(plan.source) end)
        if ok and result then return result end
    end
    return {}
end

--- Build a stack of icon+label info rows (Drop/Vendor/Quest/Zone) on a parent frame.
--- Anchored TOP to whichever is LOWER: topAnchor.BOTTOM or minTopY (negative offset from parent.TOP).
--- This ensures info rows sit under the portrait icon AND under the name (no overlap with either).
local function BuildPlanInfoRows(parent, plan, topAnchor, leftX, rightInset, minTopY)
    local sources = ResolveTrackerPlanSources(plan)
    local L = ns.L
    local P = PLAN_COLORS or {}
    local labCol = P.sourceLabel or "|cff99ccff"
    local body = P.body or "|cffffffff"
    local dim = P.descDim or "|cff888888"

    local rows = {}
    local szLg = (ns.UI_PLAN_SOURCE_ICON_LG) or math.floor(16 * 1.3 + 0.5)
    local IconMk = ns.UI_PlanSourceIconMarkup
    local classMk = IconMk and IconMk("class", szLg) or string.format("|A:Class:%d:%d|a", szLg, szLg)
    local lootMk = IconMk and IconMk("loot", szLg) or string.format("|A:Banker:%d:%d|a", szLg, szLg)
    local questMk = IconMk and IconMk("quest", szLg) or string.format("|A:Islands-QuestTurnin:%d:%d|a", szLg, szLg)
    local locMk = IconMk and IconMk("location", szLg) or string.format("|A:poi-islands-table:%d:%d|a", szLg, szLg)
    -- Inline markup matches PlanCardFactory:CreateSourceInfo (Loot / Quest / Location atlases).
    local function addRow(iconMarkup, labelKey, fallback, value, valueColor)
        if not value or value == "" then return end
        local label = (L and L[labelKey]) or fallback
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
                if diff and not first.zone:find("(" .. diff .. ")", 1, true) then
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
--- source pipeline — single source of truth for the tracker and the in-window list.
local function BuildPlanCriteriaItems(plan)
    local items = {}
    local sources = ResolveTrackerPlanSources(plan)
    local first = sources and sources[1]
    if not first then return items end
    local L = ns.L
    local labCol = (PLAN_COLORS.sourceLabel or "|cff99ccff")
    local body = (PLAN_COLORS.body or "|cffffffff")
    local function row(iconMarkup, key, fallback, value)
        if not value or value == "" then return end
        local label = (L and L[key]) or fallback
        items[#items + 1] = { text = (iconMarkup or "") .. " " .. labCol .. label .. "|r " .. body .. tostring(value) .. "|r" }
    end
    local szMd = (ns.UI_PLAN_SOURCE_ICON_MD) or math.floor(14 * 1.3 + 0.5)
    local IconMk = ns.UI_PlanSourceIconMarkup
    local classMk14 = IconMk and IconMk("class", szMd) or string.format("|A:Class:%d:%d|a", szMd, szMd)
    local lootMk14 = IconMk and IconMk("loot", szMd) or string.format("|A:Banker:%d:%d|a", szMd, szMd)
    local questMk14 = IconMk and IconMk("quest", szMd) or string.format("|A:Islands-QuestTurnin:%d:%d|a", szMd, szMd)
    local locMk14 = IconMk and IconMk("location", szMd) or string.format("|A:poi-islands-table:%d:%d|a", szMd, szMd)
    if first.vendor then
        row(classMk14, "VENDOR_LABEL", "Vendor:", first.vendor)
    elseif first.npc then
        row(lootMk14, "DROP_LABEL", "Drop:", first.npc)
    elseif first.quest then
        row(questMk14, "QUEST_LABEL", "Quest:", first.quest)
    end
    if first.zone then
        local zoneSuffix = ""
        if plan.type == "mount" and plan.mountID and WarbandNexus and WarbandNexus.GetDropDifficulty then
            local diff = WarbandNexus:GetDropDifficulty("mount", plan.mountID)
            if diff and not first.zone:find("(" .. diff .. ")", 1, true) then
                zoneSuffix = " (" .. diff .. ")"
            end
        end
        row(locMk14, "LOCATION_LABEL", "Location:", first.zone .. zoneSuffix)
    end
    return items
end
ns.UI_BuildPlanCriteriaItems = BuildPlanCriteriaItems

--- Full tooltip for plan card hover (uses addon's custom TooltipService)
local function ShowPlanTooltip(anchor, plan, isExpanded)
    local TooltipService = ns.TooltipService
    if not TooltipService then return end

    local displayName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    local planIcon = (WarbandNexus.GetResolvedPlanIcon and WarbandNexus:GetResolvedPlanIcon(plan)) or plan.icon
    local iconIsAtlas = ns.Utilities:IsAtlasName(planIcon)

    local lines = {}

    -- Achievement points (right under the title) — pulled from live API, not duplicated state.
    if plan.type == "achievement" and plan.achievementID then
        local ok, _, _, points = pcall(GetAchievementInfo, plan.achievementID)
        if ok and points and points > 0 then
            local pointsLabel = (ns.L and ns.L["POINTS_LABEL"]) or "Points"
            lines[#lines + 1] = { left = pointsLabel .. ":", right = tostring(points), leftColor = {0.6, 0.6, 0.6}, rightColor = {1, 0.85, 0.45} }
        end
    end

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

    -- Reward (for achievement plans)
    if plan.type == "achievement" then
        local rewardDisplay = plan.rewardText
        if (not rewardDisplay or rewardDisplay == "") and plan.achievementID and WarbandNexus.GetAchievementRewardInfo then
            local ri = WarbandNexus:GetAchievementRewardInfo(plan.achievementID)
            if ri then rewardDisplay = ri.title or ri.itemName end
        end
        if rewardDisplay and rewardDisplay ~= "" then
            local rewardLabel = (ns.L and ns.L["REWARD_LABEL"]) or "Reward:"
            lines[#lines + 1] = { left = rewardLabel, right = rewardDisplay, leftColor = {0.53, 1, 0.53}, rightColor = {0, 1, 0} }
        end
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
                    local icon = completed and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t" or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
                    local color = completed and (PLAN_COLORS.completedRgb or {0.27, 1, 0.27}) or (PLAN_COLORS.incompleteRgb or {1, 1, 1})
                    local progress = ""
                    if quantity and reqQuantity and reqQuantity > 1 then
                        progress = string.format(" (%s / %s)", FormatNumber(quantity), FormatNumber(reqQuantity))
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

-- ══════════════════════════════════════════
-- RefreshTrackerContent (debounced) – forward declaration
-- ══════════════════════════════════════════
local RefreshTrackerContent  -- forward declare so inner functions can reference it

-- Track rows in vertical order so the accordion animation can reposition siblings per frame
-- without rebuilding the list. Rebuilt fresh on each RefreshTrackerContentImmediate() call.
local trackerRowOrder = {}
local LIST_GAP_DEFAULT = 8

--- Reposition every tracked row by walking the ordered list and stacking them top-down using
--- their CURRENT GetHeight(). Cheap (O(n) y-anchor updates, no frame creation), called per
--- animation frame so the surrounding rows breathe with the toggling one.
local function RepositionTrackerRows()
    local y = 0
    for i = 1, #trackerRowOrder do
        local r = trackerRowOrder[i]
        if r and r:IsShown() then
            r:ClearAllPoints()
            r:SetPoint("TOPLEFT", 0, -y)
            y = y + (r:GetHeight() or 0) + LIST_GAP_DEFAULT
        end
    end
    local frame = GetTrackerFrame()
    if frame and frame.contentScrollChild then
        frame.contentScrollChild:SetHeight(math.max(1, y))
    end
end

local function RefreshTrackerContentImmediate()
    local frame = GetTrackerFrame()
    if not frame or not frame.contentScrollChild then return end

    local scrollChild = frame.contentScrollChild
    local contentWidth = GetContentWidth(frame)
    scrollChild:SetWidth(contentWidth)
    local width = contentWidth

    -- Reset the ordered row tracker; the loop below appends each row as it's created.
    wipe(trackerRowOrder)

    local plans = WarbandNexus:GetActivePlans() or {}

    -- Tracker: never list completed plans (only active / in-progress goals).
    local filtered = {}
    for i = 1, #plans do
        local plan = plans[i]
        if currentCategoryKey == nil or plan.type == currentCategoryKey then
            local isDone = false
            if WarbandNexus.IsActivePlanComplete then
                isDone = WarbandNexus:IsActivePlanComplete(plan)
            end
            if not isDone then
                filtered[#filtered + 1] = plan
            end
        end
    end
    
    -- Sort: Weekly Progress (daily_quests) first, then Great Vault, then other types, then by ID
    local typePriority = { daily_quests = 1, weekly_vault = 2 }
    table.sort(filtered, function(a, b)
        local pa = typePriority[a.type] or 50
        local pb = typePriority[b.type] or 50
        if pa ~= pb then return pa < pb end
        if (a.type or "") ~= (b.type or "") then return (a.type or "") < (b.type or "") end
        local aID = tonumber(a.id) or 0
        local bID = tonumber(b.id) or 0
        return aID < bID
    end)

    -- Clear existing children (frames AND their FontStrings)
    local bin = ns.UI_RecycleBin
    local children = { scrollChild:GetChildren() }
    for _, c in ipairs(children) do
        c:Hide()
        if bin then c:SetParent(bin) else c:SetParent(nil) end
    end
    -- Also clear any orphan regions (FontStrings created directly on scrollChild)
    for _, r in ipairs({ scrollChild:GetRegions() }) do
        r:Hide()
        r:ClearAllPoints()
    end

    local yOffset = 0
    -- Single-column list: full width, predictable vertical rhythm (no 2×2 grid)
    local LIST_GAP = 8
    local colWidth = width

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
                local infoText = GetAchievementDescriptionForRow(plan)
                if infoText == "" then infoText = GetPlanDescription(plan) end
                if infoText ~= "" then infoText = "|cff99ccff" .. infoText .. "|r" end
                local requirementsText = GetAchievementRequirementsText(plan.achievementID)
                -- Border-framed collectible icon stays as the achievement portrait. The TYPE atlas
                -- (shield) is rendered separately as a small badge before the name (handled below
                -- by ExpandableRow via data.typeAtlas). Score moves under the title (data.scoreBelow).
                local PCF = ns.UI_PlanCardFactory
                local achAtlas = PCF and PCF.TYPE_ICONS and PCF.TYPE_ICONS.achievement or "UI-Achievement-Shield-NoPoints"
                local resolvedTitle = FormatTextNumbers((WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or BATTLE_PET_SOURCE_6 or "Achievement"))
                local pts = plan.points
                if (not pts or pts == 0) and plan.achievementID then
                    local ok, _, _, p = pcall(GetAchievementInfo, plan.achievementID)
                    if ok and p then pts = p end
                end
                local titleWithPoints = resolvedTitle
                if pts and pts > 0 then
                    titleWithPoints = resolvedTitle .. string.format(" - |cffffd700(%d pts)|r", pts)
                end
                local rowData = {
                    icon = (WarbandNexus.GetResolvedPlanIcon and WarbandNexus:GetResolvedPlanIcon(plan)) or plan.icon or "Interface\\Icons\\Achievement_Quests_Completed_08",
                    iconSize = 41,
                    typeAtlas = achAtlas,
                    typeBadgeSize = 24,
                    title = titleWithPoints,
                    information = infoText,
                    criteria = requirementsText,
                    criteriaColumns = 2,  -- Tracker uses 2 columns (compact layout)
                    titleRightInset = 70,  -- room for the Track button on the right
                    onAccordionResize = RepositionTrackerRows,
                }
                local achHeaderH = math.max(60, math.min(68, math.floor(width * 0.10)))
                local row = CreateExpandableRow(scrollChild, width, achHeaderH, rowData, isExpanded, function(expanded)
                    -- Persist state only — the row's height is already final and siblings have
                    -- been kept in sync per-frame by RepositionTrackerRows. No full rebuild here.
                    expandedAchievements[plan.achievementID] = expanded
                end)
                row:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(row, GetCardColors().bg, GetCardColors().border)
                end
                AddTrackerCardAccent(row)
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
                -- Track: Add ile aynı köşesiz stil (border/background yok)
                local trackBtn = Factory:CreateButton(row.headerFrame, 52, 18, true)
                trackBtn:SetPoint("RIGHT", row.headerFrame, "RIGHT", -4, 0)
                trackBtn:SetFrameLevel(row.headerFrame:GetFrameLevel() + 10)
                trackBtn:SetScript("OnMouseDown", function() end)
                trackBtn:RegisterForClicks("AnyUp")
                local trackLabel = FontManager:CreateFontString(trackBtn, "body", "OVERLAY")
                trackLabel:SetPoint("CENTER")
                local tracked = IsAchievementTracked(plan.achievementID)
                local trackedLabel = (ns.L and ns.L["TRACKED"]) or "Tracked"
                local trackLabel2 = (ns.L and ns.L["TRACK"]) or "Track"
                trackLabel:SetText(tracked and (PLAN_COLORS.tracked or "|cff44ff44") .. trackedLabel .. "|r" or (PLAN_COLORS.notTracked or "|cffffcc00") .. trackLabel2 .. "|r")
                trackBtn:SetScript("OnEnter", function()
                    if trackLabel then trackLabel:SetTextColor(0.6, 0.9, 1, 1) end
                    GameTooltip:SetOwner(trackBtn, "ANCHOR_TOP")
                    GameTooltip:SetText((ns.L and ns.L["TRACK_BLIZZARD_OBJECTIVES"]) or "Track in Blizzard objectives (max 10)")
                    GameTooltip:Show()
                end)
                trackBtn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                    if trackLabel then
                        local nowTracked = IsAchievementTracked(plan.achievementID)
                        trackLabel:SetText(nowTracked and (PLAN_COLORS.tracked or "|cff44ff44") .. trackedLabel .. "|r" or (PLAN_COLORS.notTracked or "|cffffcc00") .. trackLabel2 .. "|r")
                    end
                end)
                trackBtn:SetScript("OnClick", function()
                    ToggleAchievementTrack(plan.achievementID)
                    local nowTracked = IsAchievementTracked(plan.achievementID)
                    local tLabel = (ns.L and ns.L["TRACKED"]) or "Tracked"
                    local uLabel = (ns.L and ns.L["TRACK"]) or "Track"
                    trackLabel:SetText(nowTracked and (PLAN_COLORS.tracked or "|cff44ff44") .. tLabel .. "|r" or (PLAN_COLORS.notTracked or "|cffffcc00") .. uLabel .. "|r")
                end)

                -- Achievement tooltip on header hover (Frame may have no prior OnEnter/OnLeave — guard GetScript)
                local origOnEnter, origOnLeave = nil, nil
                do
                    local ok, res = pcall(function() return row.headerFrame:GetScript("OnEnter") end)
                    if ok then origOnEnter = res end
                    ok, res = pcall(function() return row.headerFrame:GetScript("OnLeave") end)
                    if ok then origOnLeave = res end
                end
                row.headerFrame:SetScript("OnEnter", function(self)
                    if origOnEnter then origOnEnter(self) end
                    ShowPlanTooltip(row.headerFrame, plan, isExpanded)
                end)
                row.headerFrame:SetScript("OnLeave", function(self)
                    if origOnLeave then origOnLeave(self) end
                    HidePlanTooltip()
                end)

                trackerRowOrder[#trackerRowOrder + 1] = row
                yOffset = yOffset + row:GetHeight() + LIST_GAP
            elseif plan.type == "weekly_vault" then
                -- ── Weekly Vault: expandable full-width card ──
                local isExpanded = expandedVaults[plan.id]
                -- Room for 2-line character name + "Weekly Vault" subtitle without clipping
                local VAULT_HEADER_HEIGHT = math.max(CARD_HEIGHT, 56)
                local VAULT_ROW_HEIGHT = 22
                local VAULT_PADDING = 8
                local NUM_VAULT_PROGRESS_ROWS = 4
                
                -- Expanded: header + one row per vault track (raid / dungeon / world / SA)
                local expandedHeight = VAULT_HEADER_HEIGHT + VAULT_PADDING + (VAULT_ROW_HEIGHT * NUM_VAULT_PROGRESS_ROWS) + VAULT_PADDING + 4
                local cardHeight = isExpanded and expandedHeight or VAULT_HEADER_HEIGHT
                
                local vaultCard = Factory:CreateContainer(scrollChild, width, cardHeight)
                vaultCard:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(vaultCard, GetCardColors().bg, GetCardColors().border)
                end
                AddTrackerCardAccent(vaultCard)
                
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
                nameText:SetJustifyV("TOP")
                nameText:SetWordWrap(true)
                nameText:SetMaxLines(2)
                nameText:SetNonSpaceWrap(false)
                local charDisplay = plan.characterName or ""
                if plan.characterRealm and plan.characterRealm ~= "" then
                    local rShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(plan.characterRealm)) or plan.characterRealm
                    charDisplay = charDisplay .. "-" .. rShown
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
                        ApplyVisuals(vaultCard, GetCardColors().hoverBg, GetCardColors().hoverBorder)
                    end
                end)
                headerFrame:SetScript("OnLeave", function()
                    if ApplyVisuals then
                        ApplyVisuals(vaultCard, GetCardColors().bg, GetCardColors().border)
                    end
                end)
                
                -- Expanded content: Raid / Dungeon / World progress
                if isExpanded then
                    local currentProgress = WarbandNexus:GetWeeklyVaultProgress(plan.characterName, plan.characterRealm) or {
                        dungeonCount = 0, raidBossCount = 0, worldActivityCount = 0, specialAssignmentCount = 0, specialAssignmentTotal = 2,
                        dungeonSlots = {}, raidSlots = {}, worldSlots = {}
                    }

                    local vaultLootReady = false
                    if WarbandNexus.HasUnclaimedVaultRewards then
                        local ok, v = pcall(WarbandNexus.HasUnclaimedVaultRewards, WarbandNexus)
                        vaultLootReady = ok and v == true
                    end

                    local saMax = currentProgress.specialAssignmentTotal or 2
                    local progressRows = {
                        { label = (ns.L and ns.L["VAULT_SLOT_RAIDS"]) or "Raids",     current = currentProgress.raidBossCount,       max = 6, thresholds = {2, 4, 6} },
                        { label = (ns.L and ns.L["VAULT_SLOT_DUNGEON"]) or "Dungeon",  current = currentProgress.dungeonCount,        max = 8, thresholds = {1, 4, 8} },
                        { label = (ns.L and ns.L["VAULT_SLOT_WORLD"]) or "World",      current = currentProgress.worldActivityCount,  max = 8, thresholds = {2, 4, 8} },
                        { label = (ns.L and ns.L["VAULT_SLOT_SA"]) or "SA",            current = currentProgress.specialAssignmentCount or 0, max = saMax, thresholds = {1, saMax} },
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
                        
                        -- Threshold markers — or "Ready!" at each slot when vault loot is claimable
                        local readyLabel = (ns.L and ns.L["VAULT_LOOT_READY_SHORT"]) or "Ready!"
                        for _, threshold in ipairs(row.thresholds) do
                            local markerPct = threshold / row.max
                            local markerX = (markerPct * (barWidth - 2)) + 1
                            if vaultLootReady then
                                local rl = FontManager:CreateFontString(barBg, "small", "OVERLAY")
                                rl:SetPoint("CENTER", barBg, "LEFT", markerX, 0)
                                rl:SetWidth(math.max(28, barWidth / math.max(1, #row.thresholds) - 2))
                                rl:SetJustifyH("CENTER")
                                rl:SetText("|cff44ff44" .. readyLabel .. "|r")
                            else
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
                        end
                        
                        -- Progress text on bar
                        local progText = FontManager:CreateFontString(barBg, "small", "OVERLAY")
                        progText:SetPoint("CENTER", barBg, "CENTER", 0, 0)
                        progText:SetText("|cffffffff" .. row.current .. "/" .. row.max .. "|r")
                    end
                end
                
                vaultCard:Show()
                trackerRowOrder[#trackerRowOrder + 1] = vaultCard
                yOffset = yOffset + cardHeight + LIST_GAP
            elseif plan.type == "daily_quests" then
                -- ── Weekly / daily quest plan: same rich card as main To-Do tab ──
                local dqH = 170
                local dqCard = CreateFrame("Frame", nil, scrollChild)
                dqCard:SetSize(width, dqH)
                dqCard:SetPoint("TOPLEFT", 0, -yOffset)
                if not dqCard.SetBackdrop then
                    Mixin(dqCard, BackdropTemplateMixin)
                end
                if ApplyVisuals then
                    ApplyVisuals(dqCard, GetCardColors().bg, GetCardColors().border)
                end
                local PCF = ns.UI_PlanCardFactory
                if PCF and PCF.CreateDailyQuestCard then
                    PCF:CreateDailyQuestCard(dqCard, plan)
                end
                AddTrackerCardAccent(dqCard)
                dqCard:Show()
                trackerRowOrder[#trackerRowOrder + 1] = dqCard
                yOffset = yOffset + dqH + LIST_GAP
            else
                -- ── Standard plan: collapsible row matching the achievement layout ──
                local isExpanded = expandedPlans[plan.id] or false

                local iconTexture = (WarbandNexus.GetResolvedPlanIcon and WarbandNexus:GetResolvedPlanIcon(plan)) or plan.iconAtlas or plan.icon or PLAN_TYPE_FALLBACK_ICONS[plan.type]
                local iconIsAtlas = false
                if type(iconTexture) == "number" then
                    iconIsAtlas = false
                elseif plan.iconAtlas then
                    iconIsAtlas = true
                elseif plan.type == "custom" and plan.icon and plan.icon ~= "" then
                    iconIsAtlas = true
                elseif type(iconTexture) == "string" and ns.Utilities:IsAtlasName(iconTexture) then
                    iconIsAtlas = true
                end
                if not iconTexture or iconTexture == "" then
                    iconTexture = "Interface\\Icons\\INV_Misc_QuestionMark"
                    iconIsAtlas = false
                end

                local PCF = ns.UI_PlanCardFactory
                local typeAtlas = PCF and PCF.TYPE_ICONS and PCF.TYPE_ICONS[plan.type]
                local resolvedName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")

                -- Reserve right-side space for action buttons (delete + optional complete)
                -- and the optional Tries pill so the title never overlaps them.
                local tryCountTypes = { mount = "mountID", pet = "speciesID", toy = "itemID", illusion = "sourceID" }
                local idKey = tryCountTypes[plan.type]
                local collectibleID = idKey and (plan[idKey] or (plan.type == "illusion" and plan.illusionID))
                local showTryRow = collectibleID and Factory and Factory.CreateTryCountClickable and WarbandNexus and WarbandNexus.ShouldShowTryCountInUI
                    and WarbandNexus:ShouldShowTryCountInUI(plan.type, collectibleID)
                local titleRightInset = 6 + 16 + 4  -- rightOffset (6) + delete button (16) + gap (4)
                if plan.type == "custom" then titleRightInset = titleRightInset + 16 + 4 end
                if showTryRow then titleRightInset = titleRightInset + 78 + 4 end

                -- Custom plans show their user-entered note as description; collectibles already
                -- surface Drop/Vendor/Quest/Location through criteriaData, so don't duplicate
                -- the same parsed source as a Description line above the Requirements block.
                local information
                if plan.type == "custom" then
                    local descRaw = GetPlanDescription(plan)
                    if descRaw and descRaw ~= "" then information = descRaw end
                end

                local rowData = {
                    icon = iconTexture,
                    iconSize = 41,
                    iconIsAtlas = iconIsAtlas,
                    typeAtlas = typeAtlas,
                    typeBadgeSize = 24,
                    title = FormatTextNumbers(resolvedName),
                    information = information,
                    criteriaData = BuildPlanCriteriaItems(plan),
                    criteriaColumns = 1,
                    criteriaShowHeader = false,  -- collectibles: bare Drop/Location rows, no "Requirements:" header
                    titleRightInset = titleRightInset,
                    onAccordionResize = RepositionTrackerRows,
                }

                local headerH = math.max(60, math.min(68, math.floor(width * 0.10)))
                local row = CreateExpandableRow(scrollChild, width, headerH, rowData, isExpanded, function(expanded)
                    expandedPlans[plan.id] = expanded
                end)
                row:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(row, GetCardColors().bg, GetCardColors().border)
                end
                AddTrackerCardAccent(row)
                if row.iconFrame and ApplyVisuals then
                    ApplyVisuals(row.iconFrame, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
                    if row.iconFrame.texture then
                        local inset = 2
                        row.iconFrame.texture:ClearAllPoints()
                        row.iconFrame.texture:SetPoint("TOPLEFT", inset, -inset)
                        row.iconFrame.texture:SetPoint("BOTTOMRIGHT", -inset, inset)
                    end
                end

                -- Right-side actions (delete + optional complete for custom). Frame level above headerFrame
                -- so the buttons consume clicks before headerFrame's expand-toggle handler.
                local ACTION_SIZE = 16
                local ACTION_GAP = 4
                local rightOffset = 6
                local function makeAction(normalTex, highlightTex, onClick, tooltipKey, tooltipFallback)
                    local btn = CreateFrame("Button", nil, row.headerFrame)
                    btn:SetSize(ACTION_SIZE, ACTION_SIZE)
                    btn:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
                    btn:SetFrameLevel(row.headerFrame:GetFrameLevel() + 10)
                    btn:SetNormalTexture(normalTex)
                    btn:SetHighlightTexture(highlightTex)
                    btn:SetScript("OnMouseDown", function() end)
                    btn:RegisterForClicks("AnyUp")
                    btn:SetScript("OnClick", onClick)
                    btn:SetScript("OnEnter", function(self)
                        ns.TooltipService:Show(self, {
                            type = "custom",
                            title = (ns.L and ns.L[tooltipKey]) or tooltipFallback,
                            icon = false, anchor = "ANCHOR_TOP", lines = {},
                        })
                    end)
                    btn:SetScript("OnLeave", function() ns.TooltipService:Hide() end)
                    rightOffset = rightOffset + ACTION_SIZE + ACTION_GAP
                    return btn
                end

                makeAction(
                    "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
                    "Interface\\Buttons\\UI-GroupLoot-Pass-Highlight",
                    function()
                        if plan.id then
                            WarbandNexus:RemovePlan(plan.id)
                            RefreshTrackerContent()
                        end
                    end,
                    "PLAN_ACTION_DELETE", "Delete the Plan"
                )

                if plan.type == "custom" then
                    makeAction(
                        "Interface\\RaidFrame\\ReadyCheck-Ready",
                        "Interface\\RaidFrame\\ReadyCheck-Ready",
                        function()
                            if WarbandNexus.CompleteCustomPlan then
                                WarbandNexus:CompleteCustomPlan(plan.id)
                            end
                        end,
                        "PLAN_ACTION_COMPLETE", "Complete the Plan"
                    )
                end

                -- Try counter pill (mount/pet/toy/illusion only) — sits on the right, left of the action buttons.
                if showTryRow then
                    local TRY_W, TRY_H = 78, 18
                    local tryRow = Factory:CreateTryCountClickable(row.headerFrame, {
                        height = TRY_H, frameLevelOffset = 15, showTooltip = true, popupOnRightClick = false,
                    })
                    tryRow:SetSize(TRY_W, TRY_H)
                    tryRow:ClearAllPoints()
                    tryRow:SetPoint("RIGHT", row.headerFrame, "RIGHT", -rightOffset, 0)
                    tryRow:WnUpdateTryCount(plan.type, collectibleID, resolvedName)
                end

                -- Tooltip on header hover (preserve any prior OnEnter/OnLeave for hover highlight)
                local origOnEnter, origOnLeave = nil, nil
                do
                    local ok, res = pcall(function() return row.headerFrame:GetScript("OnEnter") end)
                    if ok then origOnEnter = res end
                    ok, res = pcall(function() return row.headerFrame:GetScript("OnLeave") end)
                    if ok then origOnLeave = res end
                end
                row.headerFrame:SetScript("OnEnter", function(self)
                    if origOnEnter then origOnEnter(self) end
                    ShowPlanTooltip(self, plan, isExpanded)
                end)
                row.headerFrame:SetScript("OnLeave", function(self)
                    if origOnLeave then origOnLeave(self) end
                    HidePlanTooltip()
                end)

                trackerRowOrder[#trackerRowOrder + 1] = row
                yOffset = yOffset + row:GetHeight() + LIST_GAP
            end
        end
    end

    -- Update count label
    local frame = GetTrackerFrame()
    if frame and frame.categoryBar and frame.categoryBar.countLabel then
        local totalCount = WarbandNexus:GetActivePlanTotalCount()
        local plansFormat = (ns.L and ns.L["PLANS_COUNT_FORMAT"]) or "%d plans"
        -- Extract suffix from format string (e.g., "%d plans" -> " plans")
        local suffix = plansFormat:gsub("%%d%s*", "")
        local countLabel = frame.categoryBar and frame.categoryBar.countLabel
        if countLabel then
            countLabel:SetText("|cff888888" .. #filtered .. "/" .. totalCount .. suffix .. "|r")
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

        -- Reuse menu (prevents creating new frame trees on every open).
        local menu = dropdown._dropdownMenu
        if not menu then
            menu = Factory:CreateContainer(UIParent, menuWidth, contentHeight + UI_SPACING.AFTER_ELEMENT)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(300)
            menu:SetClampedToScreen(true)
            if ApplyVisuals then
                ApplyVisuals(menu, { 0.08, 0.08, 0.10, 0.98 }, { COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 0.8 })
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
        menu:SetSize(menuWidth, contentHeight + UI_SPACING.AFTER_ELEMENT)
        menu:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -2)

        local children = { menu:GetChildren() }
        for i = 1, #children do
            local child = children[i]
            child:Hide()
            child:SetParent(nil)
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

    if ApplyVisuals then
        ApplyVisuals(frame, { 0.04, 0.04, 0.06, 0.97 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
    end
    frame:SetAlpha(math.max(0.2, math.min(1.0, db and db.opacity or 1.0)))

    -- ── Header (compact, draggable) ──
    local header = CreateFrame("Frame", nil, frame)
    header:SetHeight(HEADER_HEIGHT)
    header:SetPoint("TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", 0, 0)
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
    if ApplyVisuals then
        ApplyVisuals(header, { COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1 },
            { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    header:SetFrameLevel(frame:GetFrameLevel() + 10)

    -- Header icon (matches main window addon icon proportions)
    local hIcon = header:CreateTexture(nil, "ARTWORK")
    hIcon:SetSize(22, 22)
    hIcon:SetPoint("LEFT", PADDING + 2, 0)
    hIcon:SetTexture("Interface\\AddOns\\WarbandNexus\\Media\\icon")
    if not hIcon:GetTexture() then
        hIcon:SetTexture("Interface\\Icons\\INV_Inscription_Scroll")
    end
    hIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

    -- Title (uses windowChromeTitle role like the main shell)
    local titleText
    if FontManager.GetFontRole then
        titleText = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        titleText = FontManager:CreateFontString(header, "body", "OVERLAY")
    end
    titleText:SetPoint("LEFT", hIcon, "RIGHT", 8, 0)
    local collectionPlansLabel = (ns.L and ns.L["COLLECTION_PLANS"]) or "To-Do List"
    titleText:SetText(collectionPlansLabel)
    titleText:SetTextColor(1, 1, 1)

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
    closeBtn:SetFrameLevel(header:GetFrameLevel() + 5)
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
    collapseBtn:SetFrameLevel(header:GetFrameLevel() + 5)
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
            -- Grip would sit inside the title bar and cover collapse/close — hide when collapsed
            if frame.resizeGrip then frame.resizeGrip:Hide() end
        else
            collapseTex:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover")
            frame.contentArea:Show()
            if frame.categoryBar then frame.categoryBar:Show() end
            frame:SetResizable(true)
            frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
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

    -- ── Settings (gear) button + opacity popup ──
    local gearBtn = Factory:CreateButton(header, 22, 22, true)
    gearBtn:SetPoint("RIGHT", collapseBtn, "LEFT", -4, 0)
    gearBtn:SetFrameLevel(header:GetFrameLevel() + 5)
    if ApplyVisuals then
        ApplyVisuals(gearBtn, { 0.15, 0.15, 0.15, 0.8 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local gearTex = gearBtn:CreateTexture(nil, "ARTWORK")
    gearTex:SetSize(14, 14)
    gearTex:SetPoint("CENTER")
    gearTex:SetTexture("Interface\\Icons\\Trade_Engineering")
    gearTex:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    gearTex:SetVertexColor(0.9, 0.9, 0.9)

    local settingsPopup
    local function BuildSettingsPopup()
        if settingsPopup then return settingsPopup end
        local popup = CreateFrame("Frame", nil, frame)
        popup:SetSize(200, 64)
        popup:SetPoint("TOPRIGHT", gearBtn, "BOTTOMRIGHT", 0, -4)
        popup:SetFrameStrata(frame:GetFrameStrata())
        popup:SetFrameLevel(frame:GetFrameLevel() + 50)
        if ApplyVisuals then
            ApplyVisuals(popup, { 0.06, 0.06, 0.08, 0.98 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end

        local label = FontManager:CreateFontString(popup, "small", "OVERLAY")
        label:SetPoint("TOPLEFT", 10, -8)
        local opacityLabel = "Opacity"

        local valueText = FontManager:CreateFontString(popup, "small", "OVERLAY")
        valueText:SetPoint("TOPRIGHT", -10, -8)

        local current = (GetDB() and GetDB().opacity) or 1.0
        local function FormatLabel(v)
            label:SetText(string.format("|cffcccccc%s|r", opacityLabel))
            valueText:SetText(string.format("|cffffffff%d%%|r", math.floor(v * 100 + 0.5)))
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
        if popup:IsShown() then popup:Hide() else popup:Show() end
    end)
    gearBtn:SetScript("OnEnter", function()
        gearTex:SetVertexColor(1, 1, 1)
        if ApplyVisuals then
            ApplyVisuals(gearBtn, { 0.10, 0.10, 0.13, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8 })
        end
    end)
    gearBtn:SetScript("OnLeave", function()
        gearTex:SetVertexColor(0.9, 0.9, 0.9)
        if ApplyVisuals then
            ApplyVisuals(gearBtn, { 0.15, 0.15, 0.15, 0.8 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
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
    contentArea:SetPoint("BOTTOMRIGHT", 0, TRACKER_RESIZE_STRIP)
    frame.contentArea = contentArea

    -- ── Scroll frame (Collections pattern: bar column + PositionScrollBarInContainer) ──
    local scrollFrame = Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, 0)
    scrollFrame:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -SCROLLBAR_GAP, 0)
    scrollFrame:SetPoint("BOTTOM", contentArea, "BOTTOM", 0, PADDING)
    scrollFrame:EnableMouseWheel(true)
    frame.contentScrollFrame = scrollFrame

    local scrollBarColumn = Factory:CreateScrollBarColumn(contentArea, SCROLLBAR_GAP, 0, PADDING)
    if scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
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

    -- ── Resize grip (bottom-right): above scroll/scrollbar, never under title bar when collapsed ──
    local resizer = CreateFrame("Button", nil, frame)
    resizer:SetSize(18, 18)
    resizer:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -3, 3)
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
    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        local sw = scrollFrame and scrollFrame:GetWidth() or nil
        if sw and sw > 0 then
            scrollChild:SetWidth(sw)
        end
        RefreshTrackerContent()
    end)
    frame.resizeGrip = resizer

    -- Resize: only update layout when user releases (no continuous render during drag)
    frame:SetScript("OnSizeChanged", function(self, newW, newH)
        local sw = scrollFrame and scrollFrame:GetWidth() or nil
        if sw and sw > 0 then
            scrollChild:SetWidth(sw)
        end
    end)

    -- ── Keyboard: ESC does NOT close window (close only via X button). ESC only closes dropdown if open. ──
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
            -- Do not call SetPropagateKeyboardInput(false) — let ESC propagate to game
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
        -- Unregister message handler (uses PlansTrackerEvents as 'self' key)
        if frame._plansUpdatedHandler then
            WarbandNexus.UnregisterMessage(PlansTrackerEvents, E.PLANS_UPDATED)
            frame._plansUpdatedHandler = nil
        end
        -- Clear expanded achievements
        wipe(expandedAchievements)
    end)

    -- ── Listen for plan updates ──
    -- NOTE: Uses PlansTrackerEvents as 'self' key to avoid overwriting PlansUI's handler.
    local function OnPlansUpdated()
        if frame:IsShown() then
            RefreshTrackerContent()
        end
    end
    WarbandNexus.RegisterMessage(PlansTrackerEvents, E.PLANS_UPDATED, OnPlansUpdated)
    frame._plansUpdatedHandler = OnPlansUpdated

    -- ── Listen for font changes ──
    WarbandNexus.RegisterMessage(PlansTrackerEvents, E.FONT_CHANGED, function()
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
        return
    end
    if not ns.CharacterService or not ns.CharacterService:IsCharacterTracked(self) then
        local L = ns.L or {}
        self:Print("|cffff8800" .. (L["TRACKING_TAB_LOCKED_TITLE"] or "Character is not tracked") .. ". " .. (L["OPEN_CHARACTERS_TAB"] or "Open Characters") .. ".|r")
        return
    end
    self:ShowPlansTrackerWindow()
end
