--[[
    Warband Nexus - Plans Weekly Progress (daily_quests) view
    DrawDailyTasksView, its pooled quest rows and SectionPool ("pln:") section chrome.
    Split from PlansUI.lua (Lua 5.1 local limit). Loaded before PlansUI.lua, which calls WP.Install.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

local WP = ns.PlansUI_WeeklyProgress or {}
ns.PlansUI_WeeklyProgress = WP

local COLORS = ns.UI_COLORS
local CreateCard = ns.UI_CreateCard
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local ChainSectionFrameBelow = ns.UI_ChainSectionFrameBelow
local BuildCollapsibleSectionOpts = ns.UI_BuildCollapsibleSectionOpts
local format = string.format

-- Bound from PlansUI.lua via WP.Install (file-local helpers / layout state there).
local IsSafeDisplayString
local PlanGreenHex
local PlanGoldHex
local PlanBrightHex
local PlanGreenRgb
local ApplyPlansChrome
local GetLayout
local PAGE_STACK
local PlansContentPadH
local CATEGORIES

--- Fixed grey kept in dark, text role in light (ns.UI_GetThemedGreyHex; literal when not loaded) (2026-10-22).
local function PlanGreyHex(darkHex, role)
    return (ns.UI_GetThemedGreyHex and ns.UI_GetThemedGreyHex(darkHex, role)) or darkHex
end

function WP.Install(addon, deps)
    IsSafeDisplayString = deps.IsSafeDisplayString
    PlanGreenHex = deps.PlanGreenHex
    PlanGoldHex = deps.PlanGoldHex
    PlanBrightHex = deps.PlanBrightHex
    PlanGreenRgb = deps.PlanGreenRgb
    ApplyPlansChrome = deps.ApplyPlansChrome
    GetLayout = deps.GetLayout
    PAGE_STACK = deps.PAGE_STACK
    PlansContentPadH = deps.PlansContentPadH
    CATEGORIES = deps.CATEGORIES
end

local function GetCategoryStats(plan, categoryKey)
    if not plan or not plan.questTypes or not plan.questTypes[categoryKey] then
        return 0, 0
    end
    local questList = (plan.quests and plan.quests[categoryKey]) or {}
    if WarbandNexus.FilterWeeklyProgressQuestList then
        questList = WarbandNexus:FilterWeeklyProgressQuestList(plan, categoryKey, questList)
    end
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

--- Stable quest-row handlers (one function each, not per-row closures): pooled rows are re-bound to
--- another quest every paint, so the handlers read the row's current `_wnQuest` (2026-10-22).
local function QuestRowOnEnter(self)
    local quest = self._wnQuest
    if not quest then return end
    local lines = {}
    if IsSafeDisplayString(quest.description) then
        lines[#lines + 1] = { text = quest.description, color = {0.9, 0.9, 0.9} }
    end
    if quest.isSubQuest and quest.eventGroup then
        local parentName = EVENT_GROUP_NAMES[quest.eventGroup] or quest.eventGroup
        lines[#lines + 1] = { text = format((ns.L and ns.L["PART_OF_FORMAT"]) or "Part of: %s", parentName), color = {0.8, 0.5, 1.0} }
    end
    if IsSafeDisplayString(quest.zone) then
        lines[#lines + 1] = { text = quest.zone, color = {0.7, 0.7, 0.7} }
    end
    if IsSafeDisplayString(quest.objective) then
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
end

local function QuestRowOnLeave()
    if ns.TooltipService and ns.TooltipService.Hide then
        ns.TooltipService:Hide()
    else
        GameTooltip:Hide()
    end
end

local function QuestRowOnMouseDown(self)
    local quest = self._wnQuest
    if quest and ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
        ns.UI.Factory:ShowWowheadCopyURL("quest", quest.questID, self)
    end
end

local function AttachQuestRowTooltip(frame, quest)
    frame._wnQuest = quest
    frame:SetScript("OnEnter", QuestRowOnEnter)
    frame:SetScript("OnLeave", QuestRowOnLeave)
    -- A re-used row must drop the Wowhead click of the quest it showed last paint.
    if quest.questID and quest.questID > 0 then
        frame:SetScript("OnMouseDown", QuestRowOnMouseDown)
    else
        frame:SetScript("OnMouseDown", nil)
    end
end

-- Weekly Progress rows are pooled per section body (2026-10-22): every paint used to create each row,
-- its icons and FontStrings anew and park the old ones in the recycle bin (frames are never GC'd).

--- Row `idx` of `body[listField]`, created on first use; placed exactly like Factory:CreateDataRow.
---@return Frame row, number newYOffset
local function AcquireWeeklySectionRow(body, listField, idx, yOffset, rowIndex, height)
    local Factory = ns.UI.Factory
    local rows = body[listField]
    if not rows then
        rows = {}
        body[listField] = rows
    end
    local row = rows[idx]
    if not row then
        local newY
        row, newY = Factory:CreateDataRow(body, yOffset, rowIndex, height)
        rows[idx] = row
        return row, newY
    end
    row:SetHeight(height)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, -yOffset)
    row:SetPoint("RIGHT", body, "RIGHT", 0, 0)
    row:Show()
    Factory:ApplyRowBackground(row, rowIndex)
    return row, yOffset + height
end

local function HideWeeklySectionRowsFrom(body, listField, first)
    local rows = body[listField]
    if not rows then return end
    for i = first, #rows do
        rows[i]:Hide()
    end
end

--- Cached region of a pooled weekly row: FontString when `role` is set, else an ARTWORK texture.
--- With `idx` the region lives in the array `row[field]` (objective lines). Returned unanchored + shown.
local function WeeklyRowRegion(row, field, idx, role)
    local holder, slot = row, field
    if idx then
        holder = row[field]
        if not holder then
            holder = {}
            row[field] = holder
        end
        slot = idx
    end
    local region = holder[slot]
    if not region then
        if role then
            region = FontManager:CreateFontString(row, role, "OVERLAY")
        else
            region = row:CreateTexture(nil, "ARTWORK")
        end
        holder[slot] = region
    end
    region:ClearAllPoints()
    region:Show()
    return region
end

local function HideWeeklyRowRegion(row, field)
    if row[field] then row[field]:Hide() end
end

local function HideWeeklyRowRegionsFrom(row, field, first)
    local list = row[field]
    if not list then return end
    for i = first, #list do
        list[i]:Hide()
    end
end

local function PaintWeeklyEmptyRow(row)
    local emptyIcon = WeeklyRowRegion(row, "_wnPlnEmptyIcon")
    emptyIcon:SetSize(14, 14)
    emptyIcon:SetPoint("LEFT", 14, 0)
    ns.UI_SetIcon(emptyIcon, "status_pending", { alpha = 0.4 })
    local emptyFs = WeeklyRowRegion(row, "_wnPlnEmptyFs", nil, "body")
    emptyFs:SetPoint("LEFT", 32, 0)
    ns.UI_SetTextColorRole(emptyFs, "Dim")
    emptyFs:SetText((ns.L and ns.L["NO_ACTIVE_CONTENT"]) or "No active content this week")
end

--- Bind a pooled row to `quest`; regions the quest does not use are hidden.
local function PaintWeeklyQuestRow(row, quest, width)
    local hasObjectives = (quest.objectives and #quest.objectives > 0) or false
    local isSub = quest.isSubQuest
    local leftIndent = isSub and 26 or 14
    local iconSize = isSub and 12 or 14
    row:EnableMouse(true)

    local statusIcon = WeeklyRowRegion(row, "_wnPlnStatusIcon")
    statusIcon:SetSize(iconSize, iconSize)
    if hasObjectives then
        statusIcon:SetPoint("TOPLEFT", leftIndent, -6)
    else
        statusIcon:SetPoint("LEFT", leftIndent, 0)
    end
    if quest.isComplete then
        statusIcon:SetAtlas("common-icon-checkmark", false)
        statusIcon:SetVertexColor(0.27, 1, 0.27, 1)  -- explicit alpha: a pooled icon may carry 0.6 from "pending"
    elseif quest.isLocked then
        ns.UI_SetIcon(statusIcon, "lock", { vertexColor = { 1, 0.6, 0.2, 1 } })
    else
        ns.UI_SetIcon(statusIcon, "status_pending", { alpha = 0.6 })
    end

    -- Font role is fixed at creation: one title FontString per role, the other one hidden.
    local titleFs = WeeklyRowRegion(row, isSub and "_wnPlnTitleSmall" or "_wnPlnTitleBody", nil, isSub and "small" or "body")
    HideWeeklyRowRegion(row, isSub and "_wnPlnTitleBody" or "_wnPlnTitleSmall")
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
        -- Fixed greys: kept in dark, text role in light (2026-10-22).
        titleFs:SetText(PlanGreyHex("|cffaaaaaa", "Muted") .. (quest.title or "") .. "|r")
    else
        titleFs:SetText(PlanBrightHex() .. (quest.title or "") .. "|r")
    end

    local nObj = 0
    if hasObjectives then
        nObj = #quest.objectives
        local objY = -4
        for oi = 1, nObj do
            local obj = quest.objectives[oi]
            objY = objY - 16
            local objIcon = WeeklyRowRegion(row, "_wnPlnObjIcons", oi)
            objIcon:SetSize(8, 8)
            objIcon:SetPoint("TOPLEFT", leftIndent + iconSize + 8, objY)
            if obj.finished then
                objIcon:SetAtlas("common-icon-checkmark", false)
                objIcon:SetVertexColor(0.27, 1, 0.27)
            else
                ns.UI_SetIcon(objIcon, "status_pending", { alpha = 0.5 })
            end

            local objText = obj.text or format((ns.L and ns.L["OBJECTIVE_INDEX_FORMAT"]) or "Objective %d", oi)
            local objColor = obj.finished and PlanGreenHex() or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted") or "|cffaaaaaa")
            local objFs = WeeklyRowRegion(row, "_wnPlnObjFs", oi, "small")
            objFs:SetPoint("TOPLEFT", leftIndent + iconSize + 20, objY + 2)
            objFs:SetWidth(width * 0.45)
            objFs:SetJustifyH("LEFT")
            objFs:SetWordWrap(false)
            objFs:SetText(objColor .. objText .. "|r")

            local progFs = WeeklyRowRegion(row, "_wnPlnObjProgFs", oi, "small")
            progFs:SetPoint("TOPLEFT", leftIndent + iconSize + 20 + width * 0.46, objY + 2)
            progFs:SetJustifyH("LEFT")
            local progColor = obj.finished and PlanGreenHex() or PlanGoldHex()
            progFs:SetText(format("%s%d/%d|r", progColor, obj.numFulfilled, obj.numRequired))
        end

        HideWeeklyRowRegion(row, "_wnPlnZoneBodyFs")
        HideWeeklyRowRegion(row, "_wnPlnTimeFs")
        if IsSafeDisplayString(quest.zone) then
            local zoneFs = WeeklyRowRegion(row, "_wnPlnZoneSmallFs", nil, "small")
            zoneFs:SetPoint("TOPRIGHT", -14, -6)
            zoneFs:SetJustifyH("RIGHT")
            zoneFs:SetText(PlanGreyHex("|cff888888", "Dim") .. quest.zone .. "|r")
        else
            HideWeeklyRowRegion(row, "_wnPlnZoneSmallFs")
        end
    else
        HideWeeklyRowRegion(row, "_wnPlnZoneSmallFs")
        local zoneFs = WeeklyRowRegion(row, "_wnPlnZoneBodyFs", nil, "body")
        zoneFs:SetPoint("LEFT", 32 + width * 0.52, 0)
        zoneFs:SetWidth(width * 0.25)
        zoneFs:SetJustifyH("LEFT")
        zoneFs:SetWordWrap(false)
        zoneFs:SetText(PlanBrightHex() .. (IsSafeDisplayString(quest.zone) and quest.zone or "") .. "|r")

        if quest.timeLeft and quest.timeLeft > 0 then
            local timeFs = WeeklyRowRegion(row, "_wnPlnTimeFs", nil, "body")
            timeFs:SetPoint("RIGHT", -14, 0)
            timeFs:SetText(PlanBrightHex() .. FormatTimeLeft(quest.timeLeft) .. "|r")
        else
            HideWeeklyRowRegion(row, "_wnPlnTimeFs")
        end
    end
    HideWeeklyRowRegionsFrom(row, "_wnPlnObjIcons", nObj + 1)
    HideWeeklyRowRegionsFrom(row, "_wnPlnObjFs", nObj + 1)
    HideWeeklyRowRegionsFrom(row, "_wnPlnObjProgFs", nObj + 1)

    AttachQuestRowTooltip(row, quest)
end

--- Weekly Progress character-header controls (remove / configure): one stable handler each, reading
--- the plan bound to the button this paint.
local function WeeklyRemoveBtnOnClick(btn)
    WarbandNexus:RemovePlan(btn._wnPlanId)
end

local function WeeklyConfigBtnOnClick(btn)
    if WarbandNexus.ShowWeeklyProgressPlanDialog then
        WarbandNexus:ShowWeeklyProgressPlanDialog(btn._wnPlan)
    end
end

local function WeeklyConfigBtnOnEnter(btn)
    if ns.TooltipService and ns.TooltipService.Show then
        ns.TooltipService:Show(btn, {
            type = "custom",
            title = (ns.L and ns.L["WEEKLY_PROGRESS_CONFIGURE"]) or "Configure tracking",
            icon = false,
            lines = {
                { text = (ns.L and ns.L["WEEKLY_PROGRESS_CONFIGURE_HELP"]) or "Choose categories and specific weekly objectives to track.", color = {0.85, 0.85, 0.85} },
            },
        })
    else
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText((ns.L and ns.L["WEEKLY_PROGRESS_CONFIGURE"]) or "Configure tracking", 1, 1, 1)
        GameTooltip:Show()
    end
end

local function WeeklyConfigBtnOnLeave()
    if ns.TooltipService and ns.TooltipService.Hide then ns.TooltipService:Hide() else GameTooltip:Hide() end
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

    -- Section wraps / bodies / stats strips / headers are pooled on the scroll child (SectionPool,
    -- "pln:" keys) and re-bound every paint instead of being recreated per repaint (2026-10-22).
    local SP = ns.UI_SectionPool
    SP.BeginPass(parent)

    if #filteredPlans == 0 then
        if ns.UI_ShowTabEmptyStateCard then
            return ns.UI_ShowTabEmptyStateCard(parent, "plans_daily_tasks", yOffset, { fillParent = false, sideInset = PAGE_STACK.SIDE })
        end
        local _, height = CreateEmptyStateCard(parent, "plans_daily_tasks", yOffset, { fillParent = false, sideInset = PAGE_STACK.SIDE })
        return yOffset + height
    end

    local CATEGORIES = ns.QUEST_CATEGORIES or {}
    local CAT_DISPLAY = ns.CATEGORY_DISPLAY or {}
    local ROW_H = GetLayout().rowHeight
    local expandedGroups = ns.UI_GetExpandedGroups and ns.UI_GetExpandedGroups() or {}

    -- Persistent across repaints (same pattern as the Characters gold trio):
    -- the bar + its children used to be recreated and binned on every Plans paint.
    local padH = PlansContentPadH()
    -- Classic pane backdrop (tooltip border) needs extra height or the border
    -- art squeezes the 16px icon + label rows.
    local resetBarH = (ns.UI_IsClassicMode and ns.UI_IsClassicMode()) and 36 or 30
    local resetBar = parent._wnPlansResetBar
    local resetTimeText
    if resetBar then
        resetBar:SetParent(parent)
        resetTimeText = resetBar._resetTimeText
    else
        resetBar = CreateCard(parent, resetBarH)
        parent._wnPlansResetBar = resetBar
        resetBar._wnReadoptable = true   -- re-adopted every paint: never registry garbage (SectionPool)

        local resetIcon = resetBar:CreateTexture(nil, "ARTWORK")
        resetIcon:SetSize(16, 16)
        resetIcon:SetPoint("LEFT", 12, 0)
        ns.UI_SetIcon(resetIcon, "clock")

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
    if ApplyPlansChrome then
        local bg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
        ApplyPlansChrome(resetBar, bg, nil, { listHeader = true })
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

    --- After expand/collapse, adjust scrollChild height only — no PopulateContent (Characters tab parity).
    local function SyncWeeklyProgressScrollHeight()
        if not parent then return end
        local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if not mf or mf.currentTab ~= "plans" then return end

        local y = parent._wnWeeklyScrollTop or scrollTop
        local resetBarLocal = parent._wnPlansResetBar
        if resetBarLocal and resetBarLocal:IsShown() then
            y = y + (resetBarLocal:GetHeight() or resetBarH) + 6
        end

        local wraps = parent._wnWeeklyCharWraps
        if wraps then
            for wi = 1, #wraps do
                if wi > 1 then y = y + sectionSpacing end
                local wrapFr = wraps[wi]
                if wrapFr then
                    y = y + (wrapFr:GetHeight() or 0)
                end
            end
        end
        y = y + 10

        local viewportH = (mf.scroll and mf.scroll:GetHeight()) or 0
        if viewportH < 2 and mf.scroll and mf.fixedHeader then
            local fhBot = mf.fixedHeader:GetBottom()
            local sb = mf.scroll:GetBottom()
            if fhBot and sb and fhBot > sb then
                viewportH = fhBot - sb
            end
        end
        local totalScrollH = math.max(y, viewportH)
        parent:SetHeight(totalScrollH)

        local fill = parent._wnScrollBottomFill
        if fill then
            local slack = totalScrollH - y
            if slack > 1 then
                fill:ClearAllPoints()
                fill:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -y)
                fill:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
                fill:Show()
            else
                fill:ClearAllPoints()
                fill:Hide()
            end
        end

        local sc = mf.scroll
        if sc and sc.GetVerticalScrollRange and sc.GetVerticalScroll and sc.SetVerticalScroll then
            local maxV = sc:GetVerticalScrollRange() or 0
            local cur = sc:GetVerticalScroll() or 0
            if cur > maxV then
                sc:SetVerticalScroll(maxV)
            end
        end
        if ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateScrollBarVisibility and mf.scroll then
            ns.UI.Factory:UpdateScrollBarVisibility(mf.scroll)
        end
    end

    local weeklyVisibleScrollBump = SyncWeeklyProgressScrollHeight

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

    local function WeeklySectionToggleNoop() end

    parent._wnWeeklyCharWraps = {}
    parent._wnWeeklyScrollTop = scrollTop

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

        local planPoolKey = tostring(plan.id)
        local charWrap = SP.Acquire(parent, "pln:wrap:" .. planPoolKey, parent, innerW, SECTION_COLLAPSE_H + 0.1)
        parent._wnWeeklyCharWraps[#parent._wnWeeklyCharWraps + 1] = charWrap
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
            "|cff%02x%02x%02x%s|r %s-%s|r",
            classColor.r * 255, classColor.g * 255, classColor.b * 255,
            plan.characterName or "Unknown",
            PlanGreyHex("|cff888888", "Dim"),
            realmHdr
        )

        local charGroupKey = "weekly_char_" .. tostring(plan.id)
        local charExpanded = (expandedGroups[charGroupKey] == true)

        local charSectionBody
        local charHdrKey = "pln:hdr:" .. planPoolKey
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
            SP.HeaderOpts(parent, charHdrKey, BuildCollapsibleSectionOpts({
                wrapFrame = charWrap,
                bodyGetter = function() return charSectionBody end,
                headerHeight = SECTION_COLLAPSE_H,
                hideOnCollapse = true,
                deferOnToggleUntilComplete = true,
                persistFn = function(exp)
                    expandedGroups[charGroupKey] = exp
                end,
                updateVisibleFn = weeklyVisibleScrollBump,
                onComplete = function()
                    ReflowWeeklyProgressCharSectionBody(charSectionBody)
                end,
            }))
        )
        SP.Remember(parent, charHdrKey, charHeader)
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

        -- Header controls are cached on the (pooled) header; the click handlers read the bound plan.
        local removeBtn = charHeader._wnPlnRemoveBtn
        local configBtn = charHeader._wnPlnConfigBtn
        local totalFs = charHeader._wnPlnTotalFs
        if not removeBtn then
            removeBtn = Factory:CreateButton(charHeader, 24, 24, true)
            removeBtn:SetPoint("RIGHT", -8, 0)
            removeBtn:SetNormalTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            removeBtn:SetHighlightTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Highlight")
            removeBtn:SetScript("OnClick", WeeklyRemoveBtnOnClick)

            configBtn = Factory:CreateButton(charHeader, 24, 24, true)
            configBtn:SetPoint("RIGHT", removeBtn, "LEFT", -4, 0)
            configBtn:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
            configBtn:SetHighlightTexture("Interface\\Buttons\\UI-OptionsButton")
            configBtn:SetScript("OnClick", WeeklyConfigBtnOnClick)
            configBtn:SetScript("OnEnter", WeeklyConfigBtnOnEnter)
            configBtn:SetScript("OnLeave", WeeklyConfigBtnOnLeave)

            totalFs = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
            totalFs:SetPoint("RIGHT", configBtn, "LEFT", -6, 0)
            charHeader._wnPlnRemoveBtn = removeBtn
            charHeader._wnPlnConfigBtn = configBtn
            charHeader._wnPlnTotalFs = totalFs
        end
        removeBtn._wnPlanId = plan.id
        configBtn._wnPlan = plan
        removeBtn:SetFrameLevel((charHeader:GetFrameLevel() or 0) + 5)
        configBtn:SetFrameLevel((charHeader:GetFrameLevel() or 0) + 5)
        local totalColor = (totalAll > 0 and completedAll == totalAll) and PlanGreenHex() or PlanGoldHex()
        totalFs:SetText(totalColor .. completedAll .. "/" .. totalAll .. "|r")

        if charHdrTitleFs then
            charHdrTitleFs:SetJustifyH("LEFT")
            charHdrTitleFs:SetWordWrap(false)
            charHdrTitleFs:SetMaxLines(1)
            charHdrTitleFs:SetPoint("RIGHT", totalFs, "LEFT", -10, 0)
        end

        charSectionBody = SP.Acquire(parent, "pln:body:" .. planPoolKey, charWrap, innerW, 0.1)
        charSectionBody:ClearAllPoints()
        charSectionBody:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
        charSectionBody:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)

        local statsStrip = SP.Acquire(parent, "pln:stats:" .. planPoolKey, charSectionBody, innerW, STATS_H)
        statsStrip:SetPoint("TOPLEFT", charSectionBody, "TOPLEFT", 0, 0)
        if statsStrip.SetClipsChildren then
            statsStrip:SetClipsChildren(true)
        end
        -- One cached FontString per category key; categories not shown this paint stay hidden.
        local statFsByCat = statsStrip._wnPlnCatFs
        if not statFsByCat then
            statFsByCat = {}
            statsStrip._wnPlnCatFs = statFsByCat
        end
        for _, statFs in pairs(statFsByCat) do
            statFs:Hide()
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
                    local catFs = statFsByCat[catInfo.key]
                    if not catFs then
                        catFs = FontManager:CreateFontString(statsStrip, "small", "OVERLAY")
                        statFsByCat[catInfo.key] = catFs
                    end
                    catFs:ClearAllPoints()
                    catFs:Show()
                    catFs:SetPoint("LEFT", statsStrip, "LEFT", catX, 0)
                    local cColor = (c == t) and PlanGreenHex() or format("|cff%02x%02x%02x", catColor[1] * 255, catColor[2] * 255, catColor[3] * 255)
                    catFs:SetText(cColor .. catName .. " " .. c .. "/" .. t .. "|r")
                    catX = catX + catFs:GetStringWidth() + 12
                end
            end
        end

        local catChainTail = statsStrip
        local weeklyRowList = charSectionBody._weeklyRowList or {}
        wipe(weeklyRowList)
        weeklyRowList[1] = statsStrip

        for ci = 1, #CATEGORIES do
            local catInfo = CATEGORIES[ci]
            local catKey = catInfo.key
            if plan.questTypes and plan.questTypes[catKey] then
                local questList = (plan.quests and plan.quests[catKey]) or {}
                if self.FilterWeeklyProgressQuestList then
                    questList = self:FilterWeeklyProgressQuestList(plan, catKey, questList)
                end
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

                local catPoolKey = planPoolKey .. ":" .. catKey
                local catWrap = SP.Acquire(parent, "pln:cwrap:" .. catPoolKey, charSectionBody, innerW, SECTION_HDR_H + 0.1)
                if catWrap.SetClipsChildren then
                    catWrap:SetClipsChildren(true)
                end
                catWrap:ClearAllPoints()
                ChainSectionFrameBelow(charSectionBody, catWrap, catChainTail, 0, sectionSpacing, nil)

                weeklyRowList[#weeklyRowList + 1] = catWrap

                local sectionBody
                local catHdrKey = "pln:chdr:" .. catPoolKey
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
                    SP.HeaderOpts(parent, catHdrKey, BuildCollapsibleSectionOpts({
                        wrapFrame = catWrap,
                        bodyGetter = function() return sectionBody end,
                        headerHeight = SECTION_HDR_H,
                        hideOnCollapse = true,
                        deferOnToggleUntilComplete = true,
                        persistFn = function(exp)
                            expandedGroups[groupKey] = exp
                        end,
                        updateVisibleFn = weeklyVisibleScrollBump,
                        onUpdate = function()
                            ReflowWeeklyProgressCharSectionBody(charSectionBody)
                        end,
                        onComplete = function()
                            ReflowWeeklyProgressCharSectionBody(charSectionBody)
                        end,
                    }))
                )
                SP.Remember(parent, catHdrKey, catHeader)
                catHeader:SetPoint("TOPLEFT", catWrap, "TOPLEFT", 0, 0)
                catHeader:SetWidth(innerW)
                catHeader:SetHeight(SECTION_HDR_H)

                sectionBody = SP.Acquire(parent, "pln:cbody:" .. catPoolKey, catWrap, innerW, 0.1)
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

                local countHdrFs = catHeader._wnPlnCountFs
                if not countHdrFs then
                    countHdrFs = FontManager:CreateFontString(catHeader, "body", "OVERLAY")
                    countHdrFs:SetPoint("RIGHT", -14, 0)
                    catHeader._wnPlnCountFs = countHdrFs
                end
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
                    emptyRow, rowY = AcquireWeeklySectionRow(sectionBody, "_wnPlnEmptyRows", 1, rowY, 1, ROW_H)
                    PaintWeeklyEmptyRow(emptyRow)
                    HideWeeklySectionRowsFrom(sectionBody, "_wnPlnRows", 1)
                else
                    HideWeeklySectionRowsFrom(sectionBody, "_wnPlnEmptyRows", 1)
                    for qi = 1, #questList do
                        local quest = questList[qi]
                        local hasObjectives = (quest.objectives and #quest.objectives > 0) or false
                        local nObj = hasObjectives and quest.objectives and #quest.objectives or 0
                        local rowH = ROW_H
                        if hasObjectives and nObj > 0 then
                            rowH = math.max(ROW_H, 14 + 16 * nObj + 18)
                        end

                        local row
                        row, rowY = AcquireWeeklySectionRow(sectionBody, "_wnPlnRows", qi, rowY, qi, rowH)
                        PaintWeeklyQuestRow(row, quest, width)
                    end
                    HideWeeklySectionRowsFrom(sectionBody, "_wnPlnRows", #questList + 1)
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
