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

-- Unique AceEvent handler identity for PlansTrackerWindow
local PlansTrackerEvents = {}
local ApplyVisuals = ns.UI_ApplyVisuals
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
local HEADER_HEIGHT = MAIN_SHELL_PT.NAV_BAR_HEIGHT or 36
local CATEGORY_BAR_HEIGHT = MAIN_SHELL_PT.TAB_HEIGHT or 34
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

-- â”€â”€ Refresh debounce â”€â”€
local pendingRefresh = false

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- DB helpers
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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
                progress = format(" (%s / %s)", FormatNumber(quantity), FormatNumber(reqQuantity))
            end
            parts[#parts + 1] = icon .. " " .. color .. FormatTextNumbers(criteriaName) .. "|r" .. progress
        end
    end
    local pct = numCriteria > 0 and math.floor((completedCount / numCriteria) * 100) or 0
    local achieveFmt = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_FORMAT"]) or "%s of %s (%s%%)"
    local header = format("|cff00ff00" .. achieveFmt .. "|r\n", FormatNumber(completedCount), FormatNumber(numCriteria), FormatNumber(pct))
    return header .. table.concat(parts, "\n")
end

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Content helpers
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
--- Content width: derived from scrollFrame (already accounts for scrollbar gap)
local function GetContentWidth(frame)
    local sf = frame and frame.contentScrollFrame
    if sf then
        local w = sf and sf:GetWidth() or nil
        if w and w > 0 then return w end
    end
    -- Fallback before layout is ready
    return math.max((frame and frame:GetWidth() or 380) - PADDING - TRACK_SCROLL_RIGHT_RESERVE, 200)
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
--- source pipeline â€” single source of truth for the tracker and the in-window list.
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

--- All parsed source lines for expanded collectible rows (collapsed header shows first line only).
function ns.UI_BuildPlanCriteriaItemsAll(plan)
    local items = {}
    local sources = ResolveTrackerPlanSources(plan)
    if not sources or #sources == 0 then return items end
    local L = ns.L
    local labCol = (PLAN_COLORS.sourceLabel or "|cff99ccff")
    local body = (PLAN_COLORS.body or "|cffffffff")
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
        end
        if src.zone then
            local zoneSuffix = ""
            if plan.type == "mount" and plan.mountID and WarbandNexus and WarbandNexus.GetDropDifficulty then
                local diff = WarbandNexus:GetDropDifficulty("mount", plan.mountID)
                if diff and not src.zone:find("(" .. diff .. ")", 1, true) then
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
    local labCol = P.sourceLabel or "|cff99ccff"
    local body = P.body or "|cffffffff"
    local dim = P.descDim or "|cff888888"

    if plan.type == "achievement" and plan.achievementID then
        local achID = plan.achievementID
        local numCriteria = (GetAchievementNumCriteria and GetAchievementNumCriteria(achID)) or 0
        if issecretvalue and issecretvalue(numCriteria) then numCriteria = 0 end
        numCriteria = tonumber(numCriteria) or 0
        if numCriteria > 0 then
            local completed = 0
            for cidx = 1, numCriteria do
                local cName, _, cDone = GetAchievementCriteriaInfo(achID, cidx)
                if cName and cName ~= "" and cDone then completed = completed + 1 end
            end
            local pct = numCriteria > 0 and math.floor((completed / numCriteria) * 100) or 0
            local reqLab = ns.UI_NormalizeColonLabelSpacing((L and L["REQUIREMENTS_LABEL"]) or "Requirements:")
            local achFmt = (L and L["ACHIEVEMENT_PROGRESS_FORMAT"]) or "%s of %s (%s%%)"
            local progress = format(achFmt, FormatNumber(completed), FormatNumber(numCriteria), FormatNumber(pct))
            return (P.progressLabel or "|cffffcc00") .. reqLab .. "|r " .. (P.incomplete or "|cffffffff") .. progress .. "|r"
        end
        local _, _, _, _, _, _, _, achDesc = GetAchievementInfo(achID)
        if achDesc and achDesc ~= "" and not (issecretvalue and issecretvalue(achDesc)) then
            local descLab = ns.UI_NormalizeColonLabelSpacing((L and L["DESCRIPTION_LABEL"]) or "Description:")
            local d = achDesc:gsub("\n", " "):gsub("%s+", " ")
            if #d > 72 then d = d:sub(1, 69) .. "..." end
            return labCol .. descLab .. "|r " .. body .. d .. "|r"
        end
        return ""
    end

    if plan.type == "custom" then
        local d = plan.description or plan.note or ""
        if d ~= "" and d ~= "Custom plan" then
            if #d > 72 then d = d:sub(1, 69) .. "..." end
            return dim .. d .. "|r"
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
    if plan and plan.type == "achievement" then
        maxLines = 1
    end
    if maxLines < 1 then maxLines = 1 end
    local one = ns.UI_BuildPlanTodoSummaryLine and ns.UI_BuildPlanTodoSummaryLine(plan, opts) or ""
    if not plan then return {} end
    if plan.type == "achievement" or plan.type == "custom" then
        return one ~= "" and { one } or {}
    end
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
        local dim = (PLAN_COLORS and PLAN_COLORS.descDim) or "|cff888888"
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
    local labCol = (PLAN_COLORS.sourceLabel or "|cff99ccff")
    local body = (PLAN_COLORS.body or "|cffffffff")
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
            local srcLab = ns.UI_NormalizeColonLabelSpacing((L and L["SOURCE_LABEL"]) or "Source:")
            items[#items + 1] = { text = labCol .. srcLab .. "|r " .. body .. tostring(item.source) .. "|r" }
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
    local dim = P.descDim or "|cff888888"
    local labCol = P.sourceLabel or "|cff99ccff"
    local body = P.body or "|cffffffff"

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
        local dim = (PLAN_COLORS and PLAN_COLORS.descDim) or "|cff888888"
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

--- Full tooltip for plan card hover (uses addon's custom TooltipService)
local function ShowPlanTooltip(anchor, plan, isExpanded)
    local TooltipService = ns.TooltipService
    if not TooltipService then return end

    local displayName = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan)) or plan.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    local planIcon = (WarbandNexus.GetResolvedPlanIcon and WarbandNexus:GetResolvedPlanIcon(plan)) or plan.icon
    local iconIsAtlas = ns.Utilities:IsAtlasName(planIcon)

    local lines = {}

    -- Achievement points (right under the title) â€” pulled from live API, not duplicated state.
    if plan.type == "achievement" and plan.achievementID then
        local ok, _, _, points = pcall(GetAchievementInfo, plan.achievementID)
        if ok and points and points > 0 then
            local pointsLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["POINTS_LABEL"]) or "Points")
            lines[#lines + 1] = { left = pointsLabel, right = tostring(points), leftColor = {0.6, 0.6, 0.6}, rightColor = {1, 0.85, 0.45} }
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
            local rewardLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["REWARD_LABEL"]) or "Reward:")
            lines[#lines + 1] = { left = rewardLabel, right = rewardDisplay, leftColor = {0.53, 1, 0.53}, rightColor = {0, 1, 0} }
        end
    end

    -- Source
    if plan.source and plan.source ~= "" then
        local src = plan.source
        if WarbandNexus.CleanSourceText then src = WarbandNexus:CleanSourceText(src) end
        local sourceLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["SOURCE_LABEL"]) or "Source:")
        lines[#lines + 1] = { left = sourceLabel, right = src, leftColor = {0.6, 0.6, 0.6}, rightColor = {1, 0.82, 0} }
    end

    -- Zone / Vendor
    if plan.zone and plan.zone ~= "" then
        local zoneLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["ZONE_LABEL"]) or "Zone:")
        lines[#lines + 1] = { left = zoneLabel, right = plan.zone, leftColor = {0.6, 0.6, 0.6}, rightColor = {0.5, 0.8, 0.5} }
    end
    if plan.vendor and plan.vendor ~= "" then
        local vendorLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["VENDOR_LABEL"]) or "Vendor:")
        lines[#lines + 1] = { left = vendorLabel, right = plan.vendor, leftColor = {0.6, 0.6, 0.6}, rightColor = {0.5, 0.8, 0.5} }
    end

    -- Requirement
    if plan.requirement and plan.requirement ~= "" then
        local reqLabel = ns.UI_NormalizeColonLabelSpacing((ns.L and ns.L["REQUIREMENT_LABEL"]) or "Requirement:")
        lines[#lines + 1] = { left = reqLabel, right = plan.requirement, leftColor = {0.6, 0.6, 0.6}, rightColor = {1, 0.5, 0.5} }
    end

    -- Achievement requirements (only when collapsed â€” expanded cards already show them)
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
                        progress = format(" (%s / %s)", FormatNumber(quantity), FormatNumber(reqQuantity))
                    end
                    criteriaLines[#criteriaLines + 1] = { text = icon .. " " .. criteriaName .. progress, color = color }
                end
            end

            -- Header: "X of Y (Z%)"
            local pct = numCriteria > 0 and math.floor((completedCount / numCriteria) * 100) or 0
            local achieveFmt = (ns.L and ns.L["ACHIEVEMENT_PROGRESS_FORMAT"]) or "%s of %s (%s%%)"
            local header = format(achieveFmt, FormatNumber(completedCount), FormatNumber(numCriteria), FormatNumber(pct))
            lines[#lines + 1] = { text = header, color = {0.3, 1, 0.3} }

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
        if currentCategoryKey == nil or plan.type == currentCategoryKey then
            if not memoIsPlanDone(plan) then
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

    local yOffset = 0
    -- Single-column list: full width, predictable vertical rhythm (no 2Ã—2 grid)
    local LIST_GAP = 8
    local colWidth = width

    if #filtered == 0 then
        -- Wrap empty state in a frame so it gets cleaned up by children cleanup
        local emptyFrame = Factory and Factory:CreateContainer(scrollChild, width, 50, false)
        if not emptyFrame then
            emptyFrame = CreateFrame("Frame", nil, scrollChild)
            emptyFrame:SetSize(width, 50)
        end
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
            if plan.type == "weekly_vault" then
                -- â”€â”€ Weekly Vault (unchanged custom card) â”€â”€
                local isExpanded = expandedVaults[plan.id]
                local VAULT_HEADER_HEIGHT = math.max(CARD_HEIGHT, 56)
                local VAULT_ROW_HEIGHT = 22
                local VAULT_PADDING = 8
                local NUM_VAULT_PROGRESS_ROWS = 4
                local expandedHeight = VAULT_HEADER_HEIGHT + VAULT_PADDING + (VAULT_ROW_HEIGHT * NUM_VAULT_PROGRESS_ROWS) + VAULT_PADDING + 4
                local cardHeight = isExpanded and expandedHeight or VAULT_HEADER_HEIGHT
                local vaultCard = Factory:CreateContainer(scrollChild, width, cardHeight)
                vaultCard:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then
                    ApplyVisuals(vaultCard, GetCardColors().bg, GetCardColors().border)
                end
                AddTrackerCardAccent(vaultCard)
                local headerFrame = Factory and Factory:CreateContainer(vaultCard, width, VAULT_HEADER_HEIGHT, false)
                if not headerFrame then
                    headerFrame = CreateFrame("Frame", nil, vaultCard)
                    headerFrame:SetHeight(VAULT_HEADER_HEIGHT)
                end
                headerFrame:SetPoint("TOPLEFT", 0, 0)
                headerFrame:SetPoint("TOPRIGHT", 0, 0)
                headerFrame:SetHeight(VAULT_HEADER_HEIGHT)
                headerFrame:EnableMouse(true)
                local iconFrame = CreateIcon(headerFrame, "greatVault-whole-normal", ICON_SIZE, true, nil, false)
                iconFrame:SetPoint("LEFT", PADDING, 0)
                iconFrame:Show()
                local classColor = {1, 1, 1}
                if plan.characterClass then
                    local cc = RAID_CLASS_COLORS[plan.characterClass]
                    if cc then classColor = {cc.r, cc.g, cc.b} end
                end
                local nameText = FontManager:CreateFontString(headerFrame, "body", "OVERLAY")
                nameText:SetPoint("TOPLEFT", iconFrame, "TOPRIGHT", 6, -2)
                nameText:SetPoint("RIGHT", headerFrame, "RIGHT", -70, 0)
                nameText:SetJustifyH("LEFT")
                nameText:SetMaxLines(2)
                local charDisplay = plan.characterName or ""
                if plan.characterRealm and plan.characterRealm ~= "" then
                    local rShown = (ns.Utilities and ns.Utilities.FormatRealmName and ns.Utilities:FormatRealmName(plan.characterRealm)) or plan.characterRealm
                    charDisplay = charDisplay .. "-" .. rShown
                end
                nameText:SetText(format("|cff%02x%02x%02x%s|r",
                    math.floor(classColor[1]*255), math.floor(classColor[2]*255), math.floor(classColor[3]*255),
                    charDisplay))
                local subtitleText = FontManager:CreateFontString(headerFrame, "small", "OVERLAY")
                subtitleText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -1)
                subtitleText:SetText("|cff888888" .. ((ns.L and ns.L["WEEKLY_VAULT"]) or "Weekly Vault") .. "|r")
                local resetLabel = FontManager:CreateFontString(headerFrame, "small", "OVERLAY")
                resetLabel:SetPoint("RIGHT", headerFrame, "RIGHT", -PADDING, 0)
                resetLabel:SetJustifyH("RIGHT")
                local resetTimestamp = WarbandNexus.GetWeeklyResetTime and WarbandNexus:GetWeeklyResetTime() or 0
                resetLabel:SetText("|cff66cc66" .. ns.Utilities:FormatTimeUntilReset(resetTimestamp) .. "|r")
                local arrow = headerFrame:CreateTexture(nil, "OVERLAY")
                arrow:SetSize(12, 12)
                arrow:SetPoint("RIGHT", resetLabel, "LEFT", -4, 0)
                arrow:SetAtlas(isExpanded and "campaign-headericon-open" or "campaign-headericon-closed")
                headerFrame:SetScript("OnMouseDown", function()
                    expandedVaults[plan.id] = not expandedVaults[plan.id]
                    RefreshTrackerContentImmediate()
                end)
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
                        { label = (ns.L and ns.L["VAULT_SLOT_RAIDS"]) or "Raids", current = currentProgress.raidBossCount, max = 6, thresholds = {2, 4, 6} },
                        { label = (ns.L and ns.L["VAULT_SLOT_DUNGEON"]) or "Dungeon", current = currentProgress.dungeonCount, max = 8, thresholds = {1, 4, 8} },
                        { label = (ns.L and ns.L["VAULT_SLOT_WORLD"]) or "World", current = currentProgress.worldActivityCount, max = 8, thresholds = {2, 4, 8} },
                        { label = (ns.L and ns.L["VAULT_SLOT_SA"]) or "SA", current = currentProgress.specialAssignmentCount or 0, max = saMax, thresholds = {1, saMax} },
                    }
                    local contentY = -(VAULT_HEADER_HEIGHT + VAULT_PADDING)
                    local barAreaWidth = width - PADDING * 2
                    local labelWidth = 55
                    local barWidth = barAreaWidth - labelWidth - 8
                    local readyLabel = (ns.L and ns.L["VAULT_LOOT_READY_SHORT"]) or "Ready!"
                    for ri = 1, #progressRows do
                        local row = progressRows[ri]
                        local rowY = contentY - ((ri - 1) * VAULT_ROW_HEIGHT)
                        local lbl = FontManager:CreateFontString(vaultCard, "small", "OVERLAY")
                        lbl:SetPoint("TOPLEFT", vaultCard, "TOPLEFT", PADDING, rowY)
                        lbl:SetWidth(labelWidth)
                        lbl:SetJustifyH("LEFT")
                        lbl:SetText("|cffcccccc" .. row.label .. "|r")
                        local barBg = Factory:CreateContainer(vaultCard, barWidth, 14)
                        barBg:SetPoint("TOPLEFT", vaultCard, "TOPLEFT", PADDING + labelWidth + 4, rowY - 1)
                        if ApplyVisuals then
                            ApplyVisuals(barBg, {0.05, 0.05, 0.07, 0.6}, {0.3, 0.3, 0.3, 0.4})
                        end
                        local fillPct = math.min(1.0, row.current / row.max)
                        local fillW = (barWidth - 2) * fillPct
                        if fillW > 0 then
                            local fill = barBg:CreateTexture(nil, "ARTWORK")
                            fill:SetPoint("LEFT", barBg, "LEFT", 1, 0)
                            fill:SetSize(fillW, 12)
                            fill:SetTexture("Interface\\Buttons\\WHITE8x8")
                            fill:SetVertexColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9)
                        end
                        for ti = 1, #row.thresholds do
                            local threshold = row.thresholds[ti]
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
                        local progText = FontManager:CreateFontString(barBg, "small", "OVERLAY")
                        progText:SetPoint("CENTER", barBg, "CENTER", 0, 0)
                        progText:SetText("|cffffffff" .. row.current .. "/" .. row.max .. "|r")
                    end
                end
                vaultCard:Show()
                trackerRowOrder[#trackerRowOrder + 1] = vaultCard
                yOffset = yOffset + cardHeight + LIST_GAP
            elseif plan.type == "daily_quests" then
                local dqH = 170
                local dqCard = Factory and Factory:CreateContainer(scrollChild, width, dqH, false)
                if not dqCard then
                    dqCard = CreateFrame("Frame", nil, scrollChild)
                    dqCard:SetSize(width, dqH)
                end
                dqCard:SetPoint("TOPLEFT", 0, -yOffset)
                if ApplyVisuals then ApplyVisuals(dqCard, GetCardColors().bg, GetCardColors().border) end
                local PCF = ns.UI_PlanCardFactory
                if PCF and PCF.CreateDailyQuestCard then PCF:CreateDailyQuestCard(dqCard, plan) end
                AddTrackerCardAccent(dqCard)
                dqCard:Show()
                trackerRowOrder[#trackerRowOrder + 1] = dqCard
                yOffset = yOffset + dqH + LIST_GAP
            else
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
            local tryCountTypes = { mount = "mountID", pet = "speciesID", toy = "itemID", illusion = "sourceID" }
            local idKey = tryCountTypes[plan.type]
            local collectibleID = idKey and (plan[idKey] or (plan.type == "illusion" and plan.illusionID))
            if collectibleID and WarbandNexus.ShouldShowTryCountInUI and WarbandNexus:ShouldShowTryCountInUI(plan.type, collectibleID)
                and WarbandNexus.GetTryCount then
                local count = WarbandNexus:GetTryCount(plan.type, collectibleID) or 0
                trySuffix = "|cffaaddff" .. ((ns.L and ns.L["TRIES"]) or "Tries") .. ":|r |cffffffff" .. tostring(count) .. "|r"
            end

            local allSourceItems = ns.UI_BuildPlanCriteriaItemsAll and ns.UI_BuildPlanCriteriaItemsAll(plan) or BuildPlanCriteriaItems(plan)
            local summaryMax = (plan.type == "achievement") and 1 or 2
            local summaryLines = ns.UI_BuildPlanTodoSummaryLines and ns.UI_BuildPlanTodoSummaryLines(plan, { maxLines = summaryMax }) or {}

            local achievementPoints, information, criteriaItems, criteriaText, criteriaHeader
            local onExpandPopulate
            if plan.type == "achievement" and plan.achievementID then
                local achID = plan.achievementID
                local entry = ns.UI_EnsurePlansAchievementExpandCache and ns.UI_EnsurePlansAchievementExpandCache(achID)
                achievementPoints = ns.UI_ResolveAchievementPlanPoints and ns.UI_ResolveAchievementPlanPoints(plan, entry) or 0
                criteriaHeader = true
                if isExpanded and entry then
                    information = entry.information
                    criteriaText = entry.criteriaText
                    criteriaItems = entry.criteriaItems
                end
                if not isExpanded then
                    onExpandPopulate = function(data)
                        local e = ns.UI_EnsurePlansAchievementExpandCache and ns.UI_EnsurePlansAchievementExpandCache(achID)
                        if not e then return end
                        data.information = e.information
                        data.criteria = e.criteriaText
                        data.criteriaData = e.criteriaItems
                        data.criteriaShowHeader = true
                        data.summaryInHeader = true
                    end
                end
            else
                if plan.type == "custom" then
                    local d = GetPlanDescription(plan)
                    if d and d ~= "" then information = d end
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
                local nc = (GetAchievementNumCriteria and GetAchievementNumCriteria(plan.achievementID)) or 0
                if issecretvalue and issecretvalue(nc) then nc = 0 end
                canExpand = (tonumber(nc) or 0) > 0
                if not canExpand and information and information ~= "" then canExpand = true end
            end

            local typeBadgeSz = (ns.UI_PlansHeaderActionSize and ns.UI_PlansHeaderActionSize()) or 24
            local ACTION_SIZE, ACTION_GAP = typeBadgeSz, 4
            local titleRightInset = 6 + ACTION_SIZE + ACTION_GAP
            if plan.type == "achievement" and plan.achievementID then
                titleRightInset = titleRightInset + ACTION_SIZE + ACTION_GAP
            end
            if trySuffix ~= "" then
                titleRightInset = titleRightInset + ((PCM and PCM.todoMetaRightReserve) or 76)
            end

            local typeAtlas = PCF and PCF.TYPE_ICONS and PCF.TYPE_ICONS[plan.type]

            local headerH = ns.UI_PlansTodoFixedCollapsedHeight and ns.UI_PlansTodoFixedCollapsedHeight(true)
                or (ns.UI_PlansTodoExpandableHeaderHeight and ns.UI_PlansTodoExpandableHeaderHeight(width) or 92)
            local rowData = {
                todoUnifiedHeader = true,
                summaryInHeader = true,
                canExpand = canExpand,
                icon = resolvedIcon,
                iconIsAtlas = iconIsAtlas,
                iconSize = (PCM and PCM.todoUnifiedIconSize) or 40,
                typeAtlas = (plan.type ~= "achievement") and typeAtlas or nil,
                achievementPoints = achievementPoints,
                title = resolvedName,
                summaryLines = summaryLines,
                metaRightText = (trySuffix ~= "") and trySuffix or nil,
                information = isExpanded and information or nil,
                criteria = isExpanded and criteriaText or nil,
                criteriaData = criteriaItems,
                criteriaColumns = 2,
                criteriaShowHeader = criteriaHeader,
                titleRightInset = titleRightInset,
                onSectionResize = RepositionTrackerRows,
                onExpandPopulate = onExpandPopulate,
            }

            local row = CreateExpandableRow(scrollChild, width, headerH, rowData, isExpanded, function(expanded)
                if plan.type == "achievement" and plan.achievementID then
                    expandedAchievements[plan.achievementID] = expanded
                else
                    expandedPlans[plan.id] = expanded
                end
            end)
            if not row then
                yOffset = yOffset + headerH + 8
            else
            row:SetPoint("TOPLEFT", 0, -yOffset)
            if ApplyVisuals then
                ApplyVisuals(row, GetCardColors().bg, GetCardColors().border)
            end
            AddTrackerCardAccent(row)
            if row.iconFrame and ApplyVisuals then
                ApplyVisuals(row.iconFrame, {0.05, 0.05, 0.07, 0.95}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
            end

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
            yOffset = yOffset + headerH + LIST_GAP
            end
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

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Custom themed dropdown (matches SettingsUI pattern)
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
local activeDropdownMenu = nil

local function CreateThemedCategoryDropdown(parent, onCategorySelected)
    local bar = Factory and Factory:CreateContainer(parent, 420, CATEGORY_BAR_HEIGHT, false)
    if not bar then
        bar = CreateFrame("Frame", nil, parent)
        bar:SetHeight(CATEGORY_BAR_HEIGHT)
    end
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
        scrollFrame:SetPoint("BOTTOMRIGHT", -TRACK_SCROLL_RIGHT_RESERVE, 4)
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
        for ci = 1, #CATEGORY_KEYS do
            local cat = CATEGORY_KEYS[ci]
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

-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
-- Window creation
-- â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•
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

    -- â”€â”€ Main frame (Factory shell; draggable/resizable behavior unchanged) â”€â”€
    if not Factory or not Factory.CreateContainer then return end
    frame = Factory:CreateContainer(UIParent, w, h, false, "WarbandNexus_PlansTracker")
    if not frame then return end
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

    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(frame)
    elseif ApplyVisuals then
        ApplyVisuals(frame, { 0.04, 0.04, 0.06, 0.97 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.7 })
    end
    frame:SetAlpha(math.max(0.2, math.min(1.0, db and db.opacity or 1.0)))

    -- â”€â”€ Header (compact, draggable; Factory shell, width follows frame) â”€â”€
    local header = Factory:CreateContainer(frame, math.max(1, w), HEADER_HEIGHT, false)
    if not header then return end
    frame._plansTrackerHeaderShell = header
    header:SetPoint("TOPLEFT", 0, 0)
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
    hIcon:SetTexture(ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga")
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

    -- â”€â”€ Collapse/Expand toggle button â”€â”€
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
            -- Grip would sit inside the title bar and cover collapse/close â€” hide when collapsed
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

    -- â”€â”€ Settings (gear) button + opacity popup â”€â”€
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
        local popup = Factory:CreateContainer(frame, 200, 64, false)
        if not popup then
            popup = CreateFrame("Frame", nil, frame)
            popup:SetSize(200, 64)
        end
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
            label:SetText(format("|cffcccccc%s|r", opacityLabel))
            valueText:SetText(format("|cffffffff%d%%|r", math.floor(v * 100 + 0.5)))
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

    -- â”€â”€ Custom themed category dropdown â”€â”€
    local catBar, dropdown = CreateThemedCategoryDropdown(frame, function()
        RefreshTrackerContent()
    end)
    frame.categoryDropdown = dropdown
    frame.categoryBar = catBar

    -- â”€â”€ Content area: region below header+category, above bottom â”€â”€
    -- Factory's CreateScrollFrame parents ScrollUpBtn/ScrollDownBtn to scrollFrame:GetParent()
    -- and anchors them to parent TOPRIGHT/BOTTOMRIGHT. We create an intermediate frame so
    -- the buttons anchor to the scroll region, not the whole window.
    local scrollTopOffset = HEADER_HEIGHT + CATEGORY_BAR_HEIGHT + PADDING
    local contentArea = Factory and Factory:CreateContainer(frame, math.max(1, w), math.max(1, h - scrollTopOffset - TRACKER_RESIZE_STRIP), false)
    if not contentArea then
        contentArea = CreateFrame("Frame", nil, frame)
    end
    contentArea:SetPoint("TOPLEFT", 0, -scrollTopOffset)
    contentArea:SetPoint("BOTTOMRIGHT", 0, TRACKER_RESIZE_STRIP)
    frame.contentArea = contentArea

    -- â”€â”€ Scroll frame (Collections pattern: bar column + PositionScrollBarInContainer) â”€â”€
    local scrollFrame = Factory:CreateScrollFrame(contentArea, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", contentArea, "TOPLEFT", PADDING, 0)
    scrollFrame:SetPoint("TOPRIGHT", contentArea, "TOPRIGHT", -TRACK_SCROLL_RIGHT_RESERVE, 0)
    scrollFrame:SetPoint("BOTTOM", contentArea, "BOTTOM", 0, PADDING)
    scrollFrame:EnableMouseWheel(true)
    frame.contentScrollFrame = scrollFrame

    local scrollBarColumn = Factory:CreateScrollBarColumn(contentArea, TRACK_SB_COL_W, 0, PADDING)
    if scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end

    local scrollChild = Factory:CreateContainer(scrollFrame, 1, 1, false)
    if not scrollChild then
        scrollChild = CreateFrame("Frame", nil, scrollFrame)
        scrollChild:SetWidth(1)
        scrollChild:SetHeight(1)
    end
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

    -- â”€â”€ Resize grip (bottom-right): above scroll/scrollbar, never under title bar when collapsed â”€â”€
    local resizer = Factory and Factory.CreateButton and Factory:CreateButton(frame, 18, 18, true)
    if not resizer then
        resizer = CreateButton(frame, 18, 18, nil, nil, true)
    end
    if not resizer then
        resizer = CreateFrame("Button", nil, frame)
        resizer:SetSize(18, 18)
    end
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
    local function TrackerSatelliteLiveLayout(fr)
        if fr._plansTrackerHeaderShell then
            fr._plansTrackerHeaderShell:SetWidth(math.max(1, fr:GetWidth()))
        end
        local sw = scrollFrame and scrollFrame:GetWidth() or nil
        if sw and sw > 0 and scrollChild then
            scrollChild:SetWidth(sw)
        end
    end

    resizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        SavePosition(frame)
        TrackerSatelliteLiveLayout(frame)
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
            onLive = TrackerSatelliteLiveLayout,
            onCommit = function()
                RefreshTrackerContent()
            end,
        })
    else
        frame:SetScript("OnSizeChanged", function()
            TrackerSatelliteLiveLayout(frame)
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
