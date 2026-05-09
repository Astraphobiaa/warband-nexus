--[[
    Warband Nexus - Reminder Service
    Provides time-based and location-based reminders for To-Do plans.
    
    Trigger types:
      - onDailyLogin:    First login each day
      - onWeeklyReset:   First login after weekly reset
      - daysBeforeReset: N days before weekly reset (5, 3, 1)
      - onZoneEnter:     Entering a zone relevant to the plan source
    
    Data lives in plan.reminder = { enabled, triggers, lastShown, ... }
    Global settings in db.global.reminderSettings
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local issecretvalue = issecretvalue

local ReminderEvents = {}

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local REMINDER_THROTTLE_SECONDS = 300
local REMINDER_ICON = "minimap-genericevent-hornicon-small"
local MAX_REMINDERS_PER_LOGIN = 5

local TRIGGER_TYPES = {
    DAILY_LOGIN     = "onDailyLogin",
    WEEKLY_RESET    = "onWeeklyReset",
    DAYS_BEFORE     = "daysBeforeReset",
    ZONE_ENTER      = "onZoneEnter",
}

ns.REMINDER_TRIGGER_TYPES = TRIGGER_TYPES

-- ============================================================================
-- DYNAMIC ZONE DISCOVERY (C_Map API)
-- Builds a zoneName -> {mapID = true} lookup from the entire map tree at
-- runtime so every zone, dungeon, and raid is covered without hardcoding.
-- ============================================================================

local ZONE_LOOKUP = nil
local MIN_ZONE_NAME_LEN = 4

local function BuildZoneLookup()
    if ZONE_LOOKUP then return ZONE_LOOKUP end
    ZONE_LOOKUP = {}

    if not C_Map or not C_Map.GetMapChildrenInfo then return ZONE_LOOKUP end

    local function IndexChildren(rootID, mapType)
        local ok, children = pcall(C_Map.GetMapChildrenInfo, rootID, mapType, true)
        if not ok or type(children) ~= "table" then return end
        for i = 1, #children do
            local info = children[i]
            if info and info.name and info.name ~= ""
                and #info.name >= MIN_ZONE_NAME_LEN
                and not (issecretvalue and issecretvalue(info.name)) then
                local lower = info.name:lower()
                if not ZONE_LOOKUP[lower] then
                    ZONE_LOOKUP[lower] = {}
                end
                ZONE_LOOKUP[lower][info.mapID] = true
            end
        end
    end

    local COSMIC = 946
    if Enum and Enum.UIMapType then
        IndexChildren(COSMIC, Enum.UIMapType.Continent)
        IndexChildren(COSMIC, Enum.UIMapType.Zone)
        IndexChildren(COSMIC, Enum.UIMapType.Dungeon)
    else
        IndexChildren(COSMIC, nil)
    end

    return ZONE_LOOKUP
end

-- ============================================================================
-- UTILITY: EXTRACT MAP IDS FROM PLAN SOURCE TEXT
-- Matches zone/dungeon/raid names discovered by C_Map against the plan's
-- source description and name.  Also expands matched maps to include their
-- parent zone so entering the outer zone (e.g. Azj-Kahet) still triggers a
-- reminder for a plan that mentions a dungeon inside it (e.g. Ara-Kara).
-- ============================================================================

local function GetMapIDsFromPlanSource(plan)
    if not plan then return nil end

    local lookup = BuildZoneLookup()
    if not next(lookup) then return nil end

    local sourceText = plan.resolvedSource or plan.source or ""
    local nameText   = plan.resolvedName   or plan.name   or ""
    if issecretvalue and issecretvalue(sourceText) then sourceText = "" end
    if issecretvalue and issecretvalue(nameText) then nameText = "" end
    local combined   = (sourceText .. " " .. nameText):lower()

    if combined:gsub("%s", "") == "" then return nil end

    local matchedMapIDs = {}
    for zoneName, mapIDs in pairs(lookup) do
        if combined:find(zoneName, 1, true) then
            for mapID in pairs(mapIDs) do
                matchedMapIDs[mapID] = true
            end
        end
    end

    if not next(matchedMapIDs) then return nil end

    -- Expand: include parent zones of matched maps so the reminder also
    -- fires when entering the zone that contains the dungeon/raid.
    if C_Map and C_Map.GetMapInfo then
        local parents = {}
        for mapID in pairs(matchedMapIDs) do
            local info = C_Map.GetMapInfo(mapID)
            if info and info.parentMapID and info.parentMapID > 0 then
                parents[info.parentMapID] = true
            end
        end
        for parentID in pairs(parents) do
            matchedMapIDs[parentID] = true
        end
    end

    return matchedMapIDs
end

-- ============================================================================
-- REMINDER DATA HELPERS
-- ============================================================================

local function GetReminderSettings()
    if not WarbandNexus.db or not WarbandNexus.db.global then return nil end
    return WarbandNexus.db.global.reminderSettings
end

local function EnsureReminderField(plan)
    if not plan.reminder then
        plan.reminder = {
            enabled = false,
            onDailyLogin = false,
            onWeeklyReset = false,
            daysBeforeReset = {},
            onZoneEnter = false,
            lastShown = {},
        }
    end
    plan.reminder.lastShown = plan.reminder.lastShown or {}
    plan.reminder.daysBeforeReset = plan.reminder.daysBeforeReset or {}
    return plan.reminder
end

-- ============================================================================
-- PUBLIC API: SET / REMOVE / TOGGLE REMINDER
-- ============================================================================

function WarbandNexus:SetPlanReminder(planID, settings)
    local plan = self:GetPlanByID(planID)
    if not plan then return false end
    
    local r = EnsureReminderField(plan)
    r.enabled = true
    
    if settings then
        if settings.onDailyLogin ~= nil then r.onDailyLogin = settings.onDailyLogin end
        if settings.onWeeklyReset ~= nil then r.onWeeklyReset = settings.onWeeklyReset end
        if settings.daysBeforeReset then r.daysBeforeReset = settings.daysBeforeReset end
        if settings.onZoneEnter ~= nil then
            r.onZoneEnter = settings.onZoneEnter
            r.mapIDs = nil
        end
    end
    
    self:SendMessage(E.PLANS_UPDATED, { action = "reminder_changed", planID = planID })
    return true
end

function WarbandNexus:RemovePlanReminder(planID)
    local plan = self:GetPlanByID(planID)
    if not plan or not plan.reminder then return false end
    
    plan.reminder.enabled = false
    self:SendMessage(E.PLANS_UPDATED, { action = "reminder_changed", planID = planID })
    return true
end

function WarbandNexus:TogglePlanReminder(planID)
    local plan = self:GetPlanByID(planID)
    if not plan then return false end
    
    local r = EnsureReminderField(plan)
    r.enabled = not r.enabled
    self:SendMessage(E.PLANS_UPDATED, { action = "reminder_changed", planID = planID })
    return r.enabled
end

function WarbandNexus:HasPlanReminder(planID)
    local plan = self:GetPlanByID(planID)
    if not plan or not plan.reminder then return false end
    return plan.reminder.enabled == true
end

function WarbandNexus:GetPlanReminderSettings(planID)
    local plan = self:GetPlanByID(planID)
    if not plan then return nil end
    return plan.reminder
end

function WarbandNexus:GetActiveReminders(planID)
    local plan = self:GetPlanByID(planID)
    if not plan or not plan.reminder or not plan.reminder.activeReminders then return nil end
    if #plan.reminder.activeReminders == 0 then return nil end
    return plan.reminder.activeReminders
end

function WarbandNexus:HasActiveReminder(planID)
    return self:GetActiveReminders(planID) ~= nil
end

function WarbandNexus:DismissReminders(planID)
    local plan = self:GetPlanByID(planID)
    if not plan or not plan.reminder then return end
    plan.reminder.activeReminders = nil
    self:SendMessage(E.PLANS_UPDATED, { action = "reminder_dismissed", planID = planID })
end

-- ============================================================================
-- ACTIVE REMINDER STATE (progress-based, no popup notifications)
-- ============================================================================

local function ActivateReminder(plan, triggerLabel)
    if not plan or not plan.reminder then return end
    plan.reminder.activeReminders = plan.reminder.activeReminders or {}

    for i = 1, #plan.reminder.activeReminders do
        if plan.reminder.activeReminders[i] == triggerLabel then
            return
        end
    end

    if #plan.reminder.activeReminders >= MAX_REMINDERS_PER_LOGIN then return end

    plan.reminder.activeReminders[#plan.reminder.activeReminders + 1] = triggerLabel

    WarbandNexus:SendMessage(E.PLANS_UPDATED, {
        action = "reminder_activated",
        planID = plan.id,
    })
end

-- ============================================================================
-- THROTTLE CHECK
-- ============================================================================

local function CanShowReminder(plan, triggerKey)
    if not plan or not plan.reminder or not plan.reminder.lastShown then return true end
    
    local lastShown = plan.reminder.lastShown[triggerKey] or 0
    if lastShown == 0 then return true end
    
    -- Date-stamped keys (daily_YYYYMMDD, days_N_YYYYMMDD) are once-per-day flags:
    -- if the key was ever set, it already fired today — block until the date rolls over
    -- (the caller generates a new key each day, so stale entries are naturally skipped)
    if triggerKey:find("^daily_") or triggerKey:find("^days_") then
        return false
    end
    
    -- Zone and other triggers use the configurable throttle
    local settings = GetReminderSettings()
    local throttle = (settings and settings.throttleSeconds) or REMINDER_THROTTLE_SECONDS
    return (time() - lastShown) >= throttle
end

local function MarkReminderShown(plan, triggerKey)
    if not plan or not plan.reminder then return end
    plan.reminder.lastShown = plan.reminder.lastShown or {}
    plan.reminder.lastShown[triggerKey] = time()
end

local function CleanStaleReminderKeys(plan)
    if not plan or not plan.reminder or not plan.reminder.lastShown then return end
    local today = date("%Y%m%d")
    local toRemove = {}
    for key in pairs(plan.reminder.lastShown) do
        if key:find("^daily_") or key:find("^days_") then
            local keyDate = key:match("(%d%d%d%d%d%d%d%d)$")
            if keyDate and keyDate ~= today then
                toRemove[#toRemove + 1] = key
            end
        end
    end
    for ri = 1, #toRemove do
        plan.reminder.lastShown[toRemove[ri]] = nil
    end
end

-- ============================================================================
-- CHECK: DAILY LOGIN REMINDERS
-- ============================================================================

local function CheckDailyLoginReminders()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    
    local settings = GetReminderSettings()
    if settings and not settings.enabled then return end
    
    local L = ns.L
    local triggerLabel = (L and L["REMINDER_DAILY_LOGIN"]) or "Daily Login"
    
    local today = date("%Y%m%d")
    local triggerKey = "daily_" .. today
    
    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            if plan and plan.reminder and plan.reminder.enabled and plan.reminder.onDailyLogin then
                CleanStaleReminderKeys(plan)
                if not plan.completed then
                    if CanShowReminder(plan, triggerKey) then
                        MarkReminderShown(plan, triggerKey)
                        ActivateReminder(plan, triggerLabel)
                    end
                end
            end
        end
    end
    
    processPlans(WarbandNexus.db.global.plans)
    processPlans(WarbandNexus.db.global.customPlans)
end

-- ============================================================================
-- CHECK: WEEKLY RESET REMINDERS
-- ============================================================================

local function CheckWeeklyResetReminders()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    
    local settings = GetReminderSettings()
    if settings and not settings.enabled then return end
    
    local L = ns.L
    local triggerLabel = (L and L["REMINDER_WEEKLY_RESET"]) or "Weekly Reset"
    
    local hasWeeklyResetOccurred = WarbandNexus.HasWeeklyResetOccurredSince
    if not hasWeeklyResetOccurred then return end
    
    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            if plan and plan.reminder and plan.reminder.enabled and plan.reminder.onWeeklyReset then
                if not plan.completed then
                    local lastWeeklyShown = plan.reminder.lastShown and plan.reminder.lastShown["weekly_reset"] or 0
                    if WarbandNexus:HasWeeklyResetOccurredSince(lastWeeklyShown) then
                        MarkReminderShown(plan, "weekly_reset")
                        ActivateReminder(plan, triggerLabel)
                    end
                end
            end
        end
    end
    
    processPlans(WarbandNexus.db.global.plans)
    processPlans(WarbandNexus.db.global.customPlans)
end

-- ============================================================================
-- CHECK: DAYS BEFORE RESET REMINDERS
-- ============================================================================

local function CheckDaysBeforeResetReminders()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end
    
    local settings = GetReminderSettings()
    if settings and not settings.enabled then return end
    
    local resetTime = WarbandNexus:GetWeeklyResetTime()
    if not resetTime then return end
    
    local now = time()
    local secondsUntilReset = resetTime - now
    if secondsUntilReset <= 0 then return end
    
    local daysUntilReset = math.ceil(secondsUntilReset / 86400)
    
    local L = ns.L
    
    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            if plan and plan.reminder and plan.reminder.enabled then
                local daysList = plan.reminder.daysBeforeReset
                if daysList and #daysList > 0 and not plan.completed then
                    for di = 1, #daysList do
                        local dayThreshold = daysList[di]
                        if daysUntilReset <= dayThreshold then
                            local triggerKey = "days_" .. dayThreshold .. "_" .. tostring(date("%Y%m%d"))
                            if CanShowReminder(plan, triggerKey) then
                                MarkReminderShown(plan, triggerKey)
                                local label = string.format(
                                    (L and L["REMINDER_DAYS_BEFORE"]) or "%d days before reset",
                                    daysUntilReset
                                )
                                ActivateReminder(plan, label)
                            end
                            break
                        end
                    end
                end
            end
        end
    end
    
    processPlans(WarbandNexus.db.global.plans)
    processPlans(WarbandNexus.db.global.customPlans)
end

-- ============================================================================
-- CHECK: ZONE-BASED REMINDERS
-- ============================================================================

local lastCheckedMapID = nil

local function CheckZoneReminders(currentMapID)
    if not currentMapID or currentMapID == 0 then return end
    if currentMapID == lastCheckedMapID then return end
    lastCheckedMapID = currentMapID

    if not WarbandNexus.db or not WarbandNexus.db.global then return end

    local settings = GetReminderSettings()
    if settings and not settings.enabled then return end

    local L = ns.L
    local currentZoneInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(currentMapID)
    local currentZoneName = currentZoneInfo and currentZoneInfo.name or tostring(currentMapID)

    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            if plan and plan.reminder and plan.reminder.enabled and plan.reminder.onZoneEnter then
                if not plan.completed then
                    local mapIDs = plan.reminder.mapIDs
                    if not mapIDs then
                        mapIDs = GetMapIDsFromPlanSource(plan)
                        if mapIDs then
                            plan.reminder.mapIDs = mapIDs
                        end
                    end

                    if mapIDs and mapIDs[currentMapID] then
                        local triggerKey = "zone_" .. currentMapID
                        if CanShowReminder(plan, triggerKey) then
                            MarkReminderShown(plan, triggerKey)
                            local label = string.format(
                                (L and L["REMINDER_ZONE_ENTER"]) or "Entered %s",
                                currentZoneName
                            )
                            ActivateReminder(plan, label)
                        end
                    end
                end
            end
        end
    end

    processPlans(WarbandNexus.db.global.plans)
    processPlans(WarbandNexus.db.global.customPlans)
end

-- ============================================================================
-- EVENT HANDLERS
-- ============================================================================

local function OnZoneChanged()
    if not WarbandNexus.db then return end
    
    local mapID = C_Map.GetBestMapForUnit("player")
    if mapID then
        CheckZoneReminders(mapID)
    end
end

local function OnLoginRemindersCheck()
    CheckDailyLoginReminders()
    CheckWeeklyResetReminders()
    CheckDaysBeforeResetReminders()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function WarbandNexus:InitializeReminderService()
    if not self.db or not self.db.global then return end
    
    self.db.global.reminderSettings = self.db.global.reminderSettings or {
        enabled = true,
        throttleSeconds = 300,
    }
    
    WarbandNexus.RegisterEvent(ReminderEvents, "ZONE_CHANGED_NEW_AREA", OnZoneChanged)
    WarbandNexus.RegisterEvent(ReminderEvents, "ZONE_CHANGED", OnZoneChanged)
    
    C_Timer.After(3, function()
        OnLoginRemindersCheck()
    end)
    
    C_Timer.After(5, function()
        OnZoneChanged()
    end)
end

-- ============================================================================
-- SET ALERT DIALOG
-- ============================================================================

local reminderDialog = nil

function WarbandNexus:ShowSetAlertDialog(planID)
    local plan = self:GetPlanByID(planID)
    if not plan then return end
    
    local L = ns.L
    local COLORS = ns.UI_COLORS or { accent = {0.40, 0.20, 0.58}, accentDark = {0.28, 0.14, 0.41} }
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local r = EnsureReminderField(plan)
    
    if reminderDialog and reminderDialog:IsShown() then
        reminderDialog:Hide()
    end
    
    if not reminderDialog then
        local f = CreateFrame("Frame", "WarbandNexus_ReminderDialog", UIParent, "BackdropTemplate")
        f:SetSize(340, 360)
        f:SetPoint("CENTER")
        f:EnableMouse(true)
        f:SetMovable(true)
        
        if ns.WindowManager then
            ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:InstallESCHandler(f)
            ns.WindowManager:InstallDragHandler(f, f)
        else
            f:SetFrameStrata("FULLSCREEN_DIALOG")
            f:SetFrameLevel(200)
            f:RegisterForDrag("LeftButton")
            f:SetScript("OnDragStart", f.StartMoving)
            f:SetScript("OnDragStop", f.StopMovingOrSizing)
        end
        
        if ApplyVisuals then
            ApplyVisuals(f, {0.04, 0.04, 0.06, 0.98}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.9})
        end
        
        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetHeight(32)
        header:SetPoint("TOPLEFT", 2, -2)
        header:SetPoint("TOPRIGHT", -2, -2)
        if ApplyVisuals then
            ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
        end
        
        local headerTitle = FontManager:CreateFontString(header, "title", "OVERLAY")
        headerTitle:SetPoint("CENTER")
        headerTitle:SetText((L and L["SET_ALERT_TITLE"]) or "Set Alert")
        headerTitle:SetTextColor(1, 1, 1)
        f.headerTitle = headerTitle
        
        local closeBtn = CreateFrame("Button", nil, f)
        closeBtn:SetSize(20, 20)
        closeBtn:SetPoint("TOPRIGHT", -6, -6)
        closeBtn:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        closeBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        closeBtn:SetScript("OnClick", function() f:Hide() end)
        
        local planLabel = FontManager:CreateFontString(f, "body", "OVERLAY")
        planLabel:SetPoint("TOPLEFT", 16, -44)
        planLabel:SetPoint("RIGHT", f, "RIGHT", -16, 0)
        planLabel:SetJustifyH("LEFT")
        planLabel:SetWordWrap(true)
        f.planLabel = planLabel
        
        local yOff = -72
        
        local dailyCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        dailyCheck:SetSize(26, 26)
        dailyCheck:SetPoint("TOPLEFT", 16, yOff)
        local dailyLabel = FontManager:CreateFontString(f, "body", "OVERLAY")
        dailyLabel:SetPoint("LEFT", dailyCheck, "RIGHT", 6, 0)
        dailyLabel:SetText((L and L["REMINDER_OPT_DAILY"]) or "Remind on daily login")
        dailyLabel:SetTextColor(0.9, 0.9, 0.9)
        f.dailyCheck = dailyCheck
        yOff = yOff - 32
        
        local weeklyCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        weeklyCheck:SetSize(26, 26)
        weeklyCheck:SetPoint("TOPLEFT", 16, yOff)
        local weeklyLabel = FontManager:CreateFontString(f, "body", "OVERLAY")
        weeklyLabel:SetPoint("LEFT", weeklyCheck, "RIGHT", 6, 0)
        weeklyLabel:SetText((L and L["REMINDER_OPT_WEEKLY"]) or "Remind after weekly reset")
        weeklyLabel:SetTextColor(0.9, 0.9, 0.9)
        f.weeklyCheck = weeklyCheck
        yOff = yOff - 32
        
        local days5Check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        days5Check:SetSize(26, 26)
        days5Check:SetPoint("TOPLEFT", 16, yOff)
        local days5Label = FontManager:CreateFontString(f, "body", "OVERLAY")
        days5Label:SetPoint("LEFT", days5Check, "RIGHT", 6, 0)
        days5Label:SetText(string.format((L and L["REMINDER_OPT_DAYS_BEFORE"]) or "Remind %d days before reset", 5))
        days5Label:SetTextColor(0.9, 0.9, 0.9)
        f.days5Check = days5Check
        yOff = yOff - 32
        
        local days3Check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        days3Check:SetSize(26, 26)
        days3Check:SetPoint("TOPLEFT", 16, yOff)
        local days3Label = FontManager:CreateFontString(f, "body", "OVERLAY")
        days3Label:SetPoint("LEFT", days3Check, "RIGHT", 6, 0)
        days3Label:SetText(string.format((L and L["REMINDER_OPT_DAYS_BEFORE"]) or "Remind %d days before reset", 3))
        days3Label:SetTextColor(0.9, 0.9, 0.9)
        f.days3Check = days3Check
        yOff = yOff - 32
        
        local days1Check = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        days1Check:SetSize(26, 26)
        days1Check:SetPoint("TOPLEFT", 16, yOff)
        local days1Label = FontManager:CreateFontString(f, "body", "OVERLAY")
        days1Label:SetPoint("LEFT", days1Check, "RIGHT", 6, 0)
        days1Label:SetText(string.format((L and L["REMINDER_OPT_DAYS_BEFORE"]) or "Remind %d days before reset", 1))
        days1Label:SetTextColor(0.9, 0.9, 0.9)
        f.days1Check = days1Check
        yOff = yOff - 32
        
        local zoneCheck = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        zoneCheck:SetSize(26, 26)
        zoneCheck:SetPoint("TOPLEFT", 16, yOff)
        local zoneLabel = FontManager:CreateFontString(f, "body", "OVERLAY")
        zoneLabel:SetPoint("LEFT", zoneCheck, "RIGHT", 6, 0)
        zoneLabel:SetText((L and L["REMINDER_OPT_ZONE"]) or "Remind when entering source zone")
        zoneLabel:SetTextColor(0.9, 0.9, 0.9)
        f.zoneCheck = zoneCheck
        f.zoneLabel = zoneLabel
        yOff = yOff - 40
        
        local saveBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(140, 32)
        saveBtn:SetPoint("BOTTOM", f, "BOTTOM", -75, 16)
        saveBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        saveBtn:SetBackdropColor(COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1)
        saveBtn:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 1)
        local saveTxt = FontManager:CreateFontString(saveBtn, "body", "OVERLAY")
        saveTxt:SetPoint("CENTER")
        saveTxt:SetText("|cffffffff" .. ((L and L["SAVE"]) or "Save") .. "|r")
        saveBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(COLORS.accent[1] * 0.6, COLORS.accent[2] * 0.6, COLORS.accent[3] * 0.6, 1)
        end)
        saveBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(COLORS.accent[1] * 0.4, COLORS.accent[2] * 0.4, COLORS.accent[3] * 0.4, 1)
        end)
        f.saveBtn = saveBtn
        
        local removeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
        removeBtn:SetSize(140, 32)
        removeBtn:SetPoint("BOTTOM", f, "BOTTOM", 75, 16)
        removeBtn:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            tile = false, edgeSize = 1,
            insets = { left = 0, right = 0, top = 0, bottom = 0 }
        })
        removeBtn:SetBackdropColor(0.4, 0.1, 0.1, 1)
        removeBtn:SetBackdropBorderColor(0.8, 0.2, 0.2, 1)
        local removeTxt = FontManager:CreateFontString(removeBtn, "body", "OVERLAY")
        removeTxt:SetPoint("CENTER")
        removeTxt:SetText("|cffffffff" .. ((L and L["REMOVE_ALERT"]) or "Remove Alert") .. "|r")
        removeBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.6, 0.15, 0.15, 1)
        end)
        removeBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.4, 0.1, 0.1, 1)
        end)
        f.removeBtn = removeBtn
        
        reminderDialog = f
    end
    
    local f = reminderDialog
    local displayName = (self.GetResolvedPlanName and self:GetResolvedPlanName(plan))
        or plan.name
        or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    f.planLabel:SetText("|cffffffff" .. displayName .. "|r")
    f._currentPlanID = planID
    
    f.dailyCheck:SetChecked(r.onDailyLogin or false)
    f.weeklyCheck:SetChecked(r.onWeeklyReset or false)
    
    local has5, has3, has1 = false, false, false
    if r.daysBeforeReset then
        local dbr = r.daysBeforeReset
        for di = 1, #dbr do
            local d = dbr[di]
            if d == 5 then has5 = true end
            if d == 3 then has3 = true end
            if d == 1 then has1 = true end
        end
    end
    f.days5Check:SetChecked(has5)
    f.days3Check:SetChecked(has3)
    f.days1Check:SetChecked(has1)
    -- Enable zone-enter only if we can resolve at least one map ID from the plan source/name.
    -- Otherwise the reminder would never fire, so disabling the checkbox is honest.
    local mapIDs = GetMapIDsFromPlanSource(plan)
    if mapIDs and next(mapIDs) ~= nil then
        f.zoneCheck:SetChecked(r.onZoneEnter == true)
        f.zoneCheck:Enable()
        f.zoneCheck:SetAlpha(1)
        f.zoneLabel:SetTextColor(0.9, 0.9, 0.9)
    else
        f.zoneCheck:SetChecked(false)
        f.zoneCheck:Disable()
        f.zoneCheck:SetAlpha(0.4)
        f.zoneLabel:SetTextColor(0.5, 0.5, 0.5)
    end
    
    f.saveBtn:SetScript("OnClick", function()
        local days = {}
        if f.days5Check:GetChecked() then days[#days + 1] = 5 end
        if f.days3Check:GetChecked() then days[#days + 1] = 3 end
        if f.days1Check:GetChecked() then days[#days + 1] = 1 end
        table.sort(days, function(a, b) return a > b end)
        
        local settings = {
            onDailyLogin = f.dailyCheck:GetChecked() or false,
            onWeeklyReset = f.weeklyCheck:GetChecked() or false,
            daysBeforeReset = days,
        }
        if f.zoneCheck:IsEnabled() then
            settings.onZoneEnter = f.zoneCheck:GetChecked() or false
        end
        self:SetPlanReminder(f._currentPlanID, settings)
        
        f:Hide()
    end)
    
    f.removeBtn:SetScript("OnClick", function()
        self:RemovePlanReminder(f._currentPlanID)
        f:Hide()
    end)
    
    f:Show()
end
