--[[
    Warband Nexus - Reminder Service
    Provides time-based and location-based reminders for To-Do plans.

    Canonical reminder triggers live in plan.reminder.triggers.entries (versioned table).
    Legacy flat booleans (onDailyLogin, onWeeklyReset, …) stay synced for backward compatibility.

    Trigger kinds:
      - daily_login / weekly_reset / monthly_login / days_before_reset
      - zone_enter (manual uiMapIDs + optional name/source hints; Set Alert always allows enabling zone)
      - instance_enter (optional Blizzard instance ID + optional difficulty filter)

    Zone enter: raw GetBestMapForUnit + parent-chain ancestry — configured parent uiMapID (e.g. Stormwind 84)
    matches child micro-maps without listing every district. Delve floors still use alternateUIMapIDs collapse
    only (picker parent walk is not used for matching). Stable zone key = walk up until any configured
    reminder map id is hit, so moving inside the same parent does not re-fire zone_enter spam.

    Zone/instance reminders apply to all matching plans (no per-plan location focus).

    Login burst: PLAYER_ENTERING_WORLD runs calendar checks before zone/instance so session-start
    triggers (daily/monthly/weekly/days-before) take precedence; zone/instance are suppressed for the
    same plan for a short window after any calendar reminder activates.

    Daily login uses Blizzard daily reset (HasDailyResetOccurredSince), not calendar date().
    Weekly reset already uses HasWeeklyResetOccurredSince; a C_Timer reschedules the same calendar checks
    at the next daily or weekly reset boundary so long sessions still see reminders without relogging.

    Global settings in db.global.reminderSettings (throttleLocationReminders: opt-in throttle for zone/instance)

    Calendar toasts (daily / monthly / weekly / days-before) from one OnLoginRemindersCheck pass: if more than
    CALENDAR_REMINDER_TOAST_AGGREGATE_THRESHOLD fire, a single aggregated toast is shown instead of N popups.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local E = ns.Constants.EVENTS
local issecretvalue = issecretvalue

local ReminderEvents = {}

local function ReminderToastThemeFields()
    local c = ns.Constants and ns.Constants.REMINDER_HORN_UI_COLOR
    local r, g, b = 1, 0.82, 0.22
    if type(c) == "table" and tonumber(c[1]) and tonumber(c[2]) and tonumber(c[3]) then
        r, g, b = tonumber(c[1]), tonumber(c[2]), tonumber(c[3])
    end
    return {
        titleColor = { r, g, b },
        progressGlow = true,
    }
end

-- ============================================================================
-- CONSTANTS
-- ============================================================================

local REMINDER_THROTTLE_SECONDS = 300
local MAX_REMINDERS_PER_LOGIN = 5

--- Calendar toasts (daily / weekly / monthly / days-before) coalesced when many fire in one login check.
local CALENDAR_REMINDER_TOAST_AGGREGATE_THRESHOLD = 5
-- When non-nil, ActivateReminder queues non-location toasts here; flushed at end of OnLoginRemindersCheck.
local calendarToastBatch = nil

--- After PLAYER_ENTERING_WORLD, suppress zone/instance for a plan if a calendar reminder already activated.
local REMINDER_LOGIN_BURST_SECONDS = 15
local loginBurstUntil = nil
local loginBurstCalendarActivated = {}

local function BeginReminderLoginBurst()
    loginBurstUntil = GetTime() + REMINDER_LOGIN_BURST_SECONDS
    wipe(loginBurstCalendarActivated)
end

local function PlanKeyForLoginBurst(plan)
    if not plan or plan.id == nil then return nil end
    return tostring(plan.id)
end

local function LoginBurstSuppressLocationReminder(plan)
    if not loginBurstUntil then return false end
    if GetTime() >= loginBurstUntil then return false end
    local k = PlanKeyForLoginBurst(plan)
    if not k then return false end
    return loginBurstCalendarActivated[k] == true
end

local function LoginBurstMarkCalendarActivated(plan)
    if not loginBurstUntil then return end
    if GetTime() >= loginBurstUntil then return end
    local k = PlanKeyForLoginBurst(plan)
    if k then loginBurstCalendarActivated[k] = true end
end

local function GetReminderToastIconTexture()
    return "minimap-genericevent-hornicon-small"
end

--- Prefer plan journal icon (fileID); fallback horn atlas for toast.
local function GetPlanReminderToastIcon(plan)
    if plan then
        local fid = tonumber(plan.resolvedIcon) or tonumber(plan.icon)
        if fid and fid > 0 then
            return fid
        end
    end
    return GetReminderToastIconTexture()
end

local TRIGGER_TYPES = {
    DAILY_LOGIN = "onDailyLogin",
    WEEKLY_RESET = "onWeeklyReset",
    MONTHLY_LOGIN = "onMonthlyLogin",
    DAYS_BEFORE = "daysBeforeReset",
    ZONE_ENTER = "onZoneEnter",
    INSTANCE_ENTER = "onInstanceEnter",
}

--- Canonical serialized trigger kinds (plan.reminder.triggers.entries[].kind)
local KIND = {
    DAILY_LOGIN = "daily_login",
    WEEKLY_RESET = "weekly_reset",
    MONTHLY_LOGIN = "monthly_login",
    DAYS_BEFORE_RESET = "days_before_reset",
    ZONE_ENTER = "zone_enter",
    INSTANCE_ENTER = "instance_enter",
}

ns.REMINDER_TRIGGER_TYPES = TRIGGER_TYPES
ns.REMINDER_TRIGGER_KINDS = KIND

local REMINDER_TRIGGERS_VERSION = 1

-- ============================================================================
-- DYNAMIC ZONE DISCOVERY (C_Map API)
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
-- MAP IDS FROM PLAN SOURCE / NAME (hints only — no Blizzard “required zone” API)
-- Do not inject parentMapID closures here: adding e.g. Eastern Kingdoms (13) after matching
-- “Stormwind City” makes ancestor-based zone_enter match every EK sub-zone (Silvermoon, etc.).
-- Dungeon name hints likewise pulled in Silvermoon when the dungeon’s parent is that city.
-- ============================================================================

local function GetMapIDsFromPlanSource(plan)
    if not plan then return nil end

    local lookup = BuildZoneLookup()
    if not next(lookup) then return nil end

    local sourceText = plan.resolvedSource or plan.source or ""
    local nameText = plan.resolvedName or plan.name or ""
    if issecretvalue and issecretvalue(sourceText) then sourceText = "" end
    if issecretvalue and issecretvalue(nameText) then nameText = "" end
    local combined = (sourceText .. " " .. nameText):lower()

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

    return matchedMapIDs
end

-- ============================================================================
-- TRIGGER TABLE HELPERS
-- ============================================================================

local function EnsureTriggersStructure(r)
    if not r.triggers or type(r.triggers) ~= "table" then
        r.triggers = { version = REMINDER_TRIGGERS_VERSION, entries = {} }
    end
    r.triggers.version = r.triggers.version or REMINDER_TRIGGERS_VERSION
    if type(r.triggers.entries) ~= "table" then
        r.triggers.entries = {}
    end
end

--- Merge manual uiMapIDs, optional serialized map hash, and optional plan source/name hints.
local function CollectZoneMapIDsFromEntry(plan, entry)
    local merged = {}
    if not entry then return merged end
    if entry.manualMapIDs then
        for mi = 1, #entry.manualMapIDs do
            local id = tonumber(entry.manualMapIDs[mi])
            if id then merged[id] = true end
        end
    end
    if entry.mapIDs and type(entry.mapIDs) == "table" then
        for mid in pairs(entry.mapIDs) do
            local id = tonumber(mid)
            if id then merged[id] = true end
        end
    end
    if plan and entry.useSourceHints ~= false then
        local hinted = GetMapIDsFromPlanSource(plan)
        if hinted then
            for mid in pairs(hinted) do
                merged[mid] = true
            end
        end
    end
    return merged
end

local function SortDaysCopy(days)
    local out = {}
    if not days then return out end
    for i = 1, #days do
        local d = tonumber(days[i])
        if d then out[#out + 1] = d end
    end
    table.sort(out, function(a, b) return a > b end)
    return out
end

local function MigrateReminderTriggersFromLegacy(plan)
    local r = plan.reminder
    if not r or r._reminderTriggersV1 then return end

    EnsureTriggersStructure(r)

    if #r.triggers.entries > 0 then
        r._reminderTriggersV1 = true
        return
    end

    local entries = {}

    if r.onDailyLogin then
        entries[#entries + 1] = { kind = KIND.DAILY_LOGIN, enabled = true }
    end
    if r.onWeeklyReset then
        entries[#entries + 1] = { kind = KIND.WEEKLY_RESET, enabled = true }
    end
    if r.onMonthlyLogin then
        entries[#entries + 1] = { kind = KIND.MONTHLY_LOGIN, enabled = true }
    end

    local dCopy = SortDaysCopy(r.daysBeforeReset)
    if #dCopy > 0 then
        entries[#entries + 1] = { kind = KIND.DAYS_BEFORE_RESET, enabled = true, days = dCopy }
    end

    if r.onZoneEnter then
        local manual = {}
        if r.mapIDs then
            for mid in pairs(r.mapIDs) do
                local n = tonumber(mid)
                if n then manual[#manual + 1] = n end
            end
            table.sort(manual)
        end
        entries[#entries + 1] = {
            kind = KIND.ZONE_ENTER,
            enabled = true,
            useSourceHints = true,
            manualMapIDs = manual,
        }
    end

    if r.onInstanceEnter and r.instanceReminder then
        local ir = r.instanceReminder
        local iid = ir.instanceID and tonumber(ir.instanceID)
        if iid then
            entries[#entries + 1] = {
                kind = KIND.INSTANCE_ENTER,
                enabled = true,
                instanceID = iid,
                difficultyID = ir.difficultyID ~= nil and tonumber(ir.difficultyID) or nil,
            }
        end
    end

    r.triggers.entries = entries
    r._reminderTriggersV1 = true
end

local function SyncLegacyFromTriggers(plan)
    local r = plan and plan.reminder
    if not r then return end
    EnsureTriggersStructure(r)
    r.onDailyLogin = false
    r.onWeeklyReset = false
    r.onMonthlyLogin = false
    r.onZoneEnter = false
    r.onInstanceEnter = false
    r.daysBeforeReset = {}
    r.mapIDs = nil
    r.instanceReminder = nil

    for i = 1, #r.triggers.entries do
        local e = r.triggers.entries[i]
        if not e or not e.enabled then
            -- skip
        elseif e.kind == KIND.DAILY_LOGIN then
            r.onDailyLogin = true
        elseif e.kind == KIND.WEEKLY_RESET then
            r.onWeeklyReset = true
        elseif e.kind == KIND.MONTHLY_LOGIN then
            r.onMonthlyLogin = true
        elseif e.kind == KIND.ZONE_ENTER then
            r.onZoneEnter = true
            local merged = CollectZoneMapIDsFromEntry(plan, e)
            if merged and next(merged) then
                r.mapIDs = merged
            end
        elseif e.kind == KIND.INSTANCE_ENTER then
            r.onInstanceEnter = true
            r.instanceReminder = {
                instanceID = tonumber(e.instanceID),
                difficultyID = e.difficultyID ~= nil and tonumber(e.difficultyID) or nil,
            }
        elseif e.kind == KIND.DAYS_BEFORE_RESET and type(e.days) == "table" then
            r.daysBeforeReset = SortDaysCopy(e.days)
        end
    end
end

local function FindTriggerEntry(r, kind)
    EnsureTriggersStructure(r)
    for i = 1, #r.triggers.entries do
        local e = r.triggers.entries[i]
        if e and e.kind == kind then return e end
    end
    return nil
end

local function UpsertTriggerEntry(r, entry)
    EnsureTriggersStructure(r)
    local idx = nil
    for i = 1, #r.triggers.entries do
        if r.triggers.entries[i].kind == entry.kind then
            idx = i
            break
        end
    end
    if idx then
        r.triggers.entries[idx] = entry
    else
        r.triggers.entries[#r.triggers.entries + 1] = entry
    end
end

-- ============================================================================
-- SETTINGS / DATA HELPERS
-- ============================================================================

local function GetReminderSettings()
    if not WarbandNexus.db or not WarbandNexus.db.global then return nil end
    return WarbandNexus.db.global.reminderSettings
end

local function PlanAllowsLocationReminder(plan)
    if not plan then return false end
    return true
end

local function EnsureReminderField(plan)
    if not plan.reminder then
        plan.reminder = {
            enabled = false,
            onDailyLogin = false,
            onWeeklyReset = false,
            onMonthlyLogin = false,
            daysBeforeReset = {},
            onZoneEnter = false,
            onInstanceEnter = false,
            lastShown = {},
        }
    end
    plan.reminder.lastShown = plan.reminder.lastShown or {}
    plan.reminder.daysBeforeReset = plan.reminder.daysBeforeReset or {}
    MigrateReminderTriggersFromLegacy(plan)
    SyncLegacyFromTriggers(plan)
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

    if settings and settings.replaceTriggers and type(settings.entries) == "table" then
        EnsureTriggersStructure(r)
        r.triggers.entries = settings.entries
        r._reminderTriggersV1 = true
        SyncLegacyFromTriggers(plan)
        self:SendMessage(E.PLANS_UPDATED, { action = "reminder_changed", planID = planID })
        return true
    end

    if settings then
        if settings.onDailyLogin ~= nil then r.onDailyLogin = settings.onDailyLogin end
        if settings.onWeeklyReset ~= nil then r.onWeeklyReset = settings.onWeeklyReset end
        if settings.onMonthlyLogin ~= nil then r.onMonthlyLogin = settings.onMonthlyLogin end
        if settings.daysBeforeReset then r.daysBeforeReset = settings.daysBeforeReset end
        if settings.onZoneEnter ~= nil then r.onZoneEnter = settings.onZoneEnter end
        if settings.onInstanceEnter ~= nil then r.onInstanceEnter = settings.onInstanceEnter end
        if settings.instanceReminder ~= nil then r.instanceReminder = settings.instanceReminder end
        if settings.onZoneEnter ~= nil and settings.onZoneEnter == false then
            r.mapIDs = nil
        end
    end

    EnsureTriggersStructure(r)
    r.triggers.entries = {}
    if r.onDailyLogin then UpsertTriggerEntry(r, { kind = KIND.DAILY_LOGIN, enabled = true }) end
    if r.onWeeklyReset then UpsertTriggerEntry(r, { kind = KIND.WEEKLY_RESET, enabled = true }) end
    if r.onMonthlyLogin then UpsertTriggerEntry(r, { kind = KIND.MONTHLY_LOGIN, enabled = true }) end
    local dSorted = SortDaysCopy(r.daysBeforeReset)
    if #dSorted > 0 then
        UpsertTriggerEntry(r, { kind = KIND.DAYS_BEFORE_RESET, enabled = true, days = dSorted })
    end
    if r.onZoneEnter then
        local manual = {}
        if settings and type(settings.zoneManualMapIDs) == "table" then
            for i = 1, #settings.zoneManualMapIDs do
                local id = tonumber(settings.zoneManualMapIDs[i])
                if id then manual[#manual + 1] = id end
            end
            table.sort(manual)
        elseif r.mapIDs then
            for mid in pairs(r.mapIDs) do
                local id = tonumber(mid)
                if id then manual[#manual + 1] = id end
            end
            table.sort(manual)
        end
        UpsertTriggerEntry(r, {
            kind = KIND.ZONE_ENTER,
            enabled = true,
            useSourceHints = settings and settings.zoneUseSourceHints ~= false,
            manualMapIDs = manual,
        })
    end
    if r.onInstanceEnter and r.instanceReminder and tonumber(r.instanceReminder.instanceID) then
        UpsertTriggerEntry(r, {
            kind = KIND.INSTANCE_ENTER,
            enabled = true,
            instanceID = tonumber(r.instanceReminder.instanceID),
            difficultyID = r.instanceReminder.difficultyID ~= nil and tonumber(r.instanceReminder.difficultyID) or nil,
        })
    end

    r._reminderTriggersV1 = true
    SyncLegacyFromTriggers(plan)

    self:SendMessage(E.PLANS_UPDATED, { action = "reminder_changed", planID = planID })
    return true
end

function WarbandNexus:RemovePlanReminder(planID)
    local plan = self:GetPlanByID(planID)
    if not plan or not plan.reminder then return false end

    local r = plan.reminder
    r.enabled = false
    r.activeReminders = nil
    r.lastShown = {}
    r.onDailyLogin = false
    r.onWeeklyReset = false
    r.onMonthlyLogin = false
    r.daysBeforeReset = {}
    r.onZoneEnter = false
    r.onInstanceEnter = false
    r.mapIDs = nil
    r.instanceReminder = nil
    EnsureTriggersStructure(r)
    r.triggers.entries = {}
    r._reminderTriggersV1 = true
    SyncLegacyFromTriggers(plan)

    local prof = self.db and self.db.profile
    if prof and prof.plansReminderFocusPlanID == planID then
        prof.plansReminderFocusPlanID = nil
    end

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
    EnsureReminderField(plan)
    return plan.reminder.enabled == true
end

function WarbandNexus:GetPlanReminderSettings(planID)
    local plan = self:GetPlanByID(planID)
    if not plan then return nil end
    EnsureReminderField(plan)
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
-- ACTIVE REMINDER STATE
-- ============================================================================

local function SafePlanToastTitle(plan)
    if not plan then
        return (ns.L and ns.L["TAB_PLANS"]) or "To-Do"
    end
    local name = (WarbandNexus.GetResolvedPlanName and WarbandNexus:GetResolvedPlanName(plan))
        or plan.resolvedName
        or plan.name
    if not name or (issecretvalue and issecretvalue(name)) then
        return (ns.L and ns.L["TAB_PLANS"]) or "To-Do"
    end
    return name
end

--- Single plan reminder toast (zone/instance or calendar). Respects notification settings.
---@param fromLocation boolean When true, omit action line (zone/instance compact layout).
local function SendPlanReminderToast(plan, triggerLabel, fromLocation)
    local prof = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not prof or not prof.enabled or prof.showPlanReminderToast == false then return end
    local planTitle = SafePlanToastTitle(plan)
    local toastData = {
        compact = true,
        planReminderToast = true,
        criteriaTitle = (ns.L and ns.L["REMINDER_TOAST_TITLE"]) or "To-Do reminder",
        itemName = planTitle,
        icon = GetPlanReminderToastIcon(plan),
        playSound = true,
        autoDismiss = 3,
    }
    local theme = ReminderToastThemeFields()
    toastData.titleColor = theme.titleColor
    toastData.progressGlow = theme.progressGlow
    if not fromLocation then
        local safeMsg = triggerLabel
        if safeMsg and issecretvalue and issecretvalue(safeMsg) then
            safeMsg = nil
        end
        if safeMsg and safeMsg ~= "" then
            toastData.action = safeMsg
        end
    end
    WarbandNexus:SendMessage(E.SHOW_REMINDER_TOAST, { data = toastData })
end

local function BeginCalendarToastBatch()
    calendarToastBatch = {}
end

local function FlushCalendarToastBatch()
    if not calendarToastBatch or #calendarToastBatch == 0 then
        calendarToastBatch = nil
        return
    end
    local batch = calendarToastBatch
    calendarToastBatch = nil

    local prof = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
    if not prof or not prof.enabled or prof.showPlanReminderToast == false then
        return
    end

    if #batch <= CALENDAR_REMINDER_TOAST_AGGREGATE_THRESHOLD then
        for i = 1, #batch do
            SendPlanReminderToast(batch[i].plan, batch[i].triggerLabel, false)
        end
        return
    end

    local L = ns.L
    local n = #batch
    local bodyFmt = (L and L["REMINDER_AGGREGATE_CALENDAR_BODY"]) or "You have %d to-do reminders."
    local body = string.format(bodyFmt, n)
    local toastData = {
        compact = true,
        planReminderToast = true,
        criteriaTitle = (L and L["REMINDER_TOAST_TITLE"]) or "To-Do reminder",
        itemName = (L and L["REMINDER_AGGREGATE_CALENDAR_TITLE"]) or "Multiple reminders",
        icon = GetReminderToastIconTexture(),
        playSound = true,
        autoDismiss = 4,
        action = body,
    }
    local theme = ReminderToastThemeFields()
    toastData.titleColor = theme.titleColor
    toastData.progressGlow = theme.progressGlow
    WarbandNexus:SendMessage(E.SHOW_REMINDER_TOAST, { data = toastData })
end

---@param opts table|nil repeatLocationNotify: bypass active-reminder dedupe + max list cap so zone/instance can toast every entry; throttle still gated separately via reminderSettings.
---@param opts.fromLocation boolean zone/instance triggers; suppressed during login burst if calendar already activated for this plan.
local function ActivateReminder(plan, triggerLabel, opts)
    opts = opts or {}
    if not plan or not plan.reminder then return end

    local fromLocation = opts.fromLocation == true
    if fromLocation and LoginBurstSuppressLocationReminder(plan) then
        return
    end

    plan.reminder.activeReminders = plan.reminder.activeReminders or {}

    local repeatLoc = opts.repeatLocationNotify == true

    local isDup = false
    for i = 1, #plan.reminder.activeReminders do
        if plan.reminder.activeReminders[i] == triggerLabel then
            isDup = true
            break
        end
    end

    if isDup and not repeatLoc then
        return
    end

    if not isDup then
        if #plan.reminder.activeReminders >= MAX_REMINDERS_PER_LOGIN then
            if not repeatLoc then
                return
            end
        else
            plan.reminder.activeReminders[#plan.reminder.activeReminders + 1] = triggerLabel
        end
    end

    if not fromLocation then
        LoginBurstMarkCalendarActivated(plan)
    end

    WarbandNexus:SendMessage(E.PLANS_UPDATED, {
        action = "reminder_activated",
        planID = plan.id,
    })

    WarbandNexus:SendMessage(E.REMINDER_ACTIVATED, {
        planID = plan.id,
        triggerLabel = triggerLabel,
    })

    if fromLocation then
        SendPlanReminderToast(plan, triggerLabel, true)
    else
        local prof = WarbandNexus.db and WarbandNexus.db.profile and WarbandNexus.db.profile.notifications
        if prof and prof.enabled and prof.showPlanReminderToast ~= false then
            if calendarToastBatch then
                calendarToastBatch[#calendarToastBatch + 1] = { plan = plan, triggerLabel = triggerLabel }
            else
                SendPlanReminderToast(plan, triggerLabel, false)
            end
        end
    end
end

-- ============================================================================
-- THROTTLE CHECK
-- ============================================================================

local function CanShowReminder(plan, triggerKey)
    if not plan or not plan.reminder or not plan.reminder.lastShown then return true end

    local lastShown = plan.reminder.lastShown[triggerKey] or 0
    if lastShown == 0 then return true end

    if triggerKey:find("^daily_") or triggerKey:find("^days_") or triggerKey:find("^monthly_") then
        return false
    end

    -- Zone / instance: show every matching entry unless user explicitly enables location throttling.
    if triggerKey:find("^zone_") or triggerKey:find("^inst_") then
        local settings = GetReminderSettings()
        if not settings or settings.throttleLocationReminders ~= true then
            return true
        end
    end

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
    local thisMonth = date("%Y%m")
    local toRemove = {}
    for key in pairs(plan.reminder.lastShown) do
        if key:find("^daily_") or key:find("^days_") then
            local keyDate = key:match("(%d%d%d%d%d%d%d%d)$")
            if keyDate and keyDate ~= today then
                toRemove[#toRemove + 1] = key
            end
        elseif key:find("^monthly_") then
            local keyYm = key:match("^monthly_(%d%d%d%d%d%d)$")
            if keyYm and keyYm ~= thisMonth then
                toRemove[#toRemove + 1] = key
            end
        end
    end
    for ri = 1, #toRemove do
        plan.reminder.lastShown[toRemove[ri]] = nil
    end
end

-- ============================================================================
-- CHECK: DAILY / MONTHLY LOGIN REMINDERS
-- ============================================================================

local function CheckDailyLoginReminders()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end

    local settings = GetReminderSettings()
    if settings and not settings.enabled then return end

    local L = ns.L
    local triggerLabel = (L and L["REMINDER_DAILY_LOGIN"]) or "Daily Login"

    -- Prefer Blizzard daily reset boundary (C_DateAndTime) so "daily" matches the game day, not local midnight.
    local useBlizzardDaily = WarbandNexus.HasDailyResetOccurredSince
        and C_DateAndTime
        and C_DateAndTime.GetSecondsUntilDailyReset

    local today = date("%Y%m%d")
    local triggerKey = "daily_" .. today

    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            if plan and plan.reminder and plan.reminder.enabled and plan.reminder.onDailyLogin then
                CleanStaleReminderKeys(plan)
                if not plan.completed then
                    local shouldFire = false
                    if useBlizzardDaily then
                        local lastAt = tonumber(plan.reminder.lastDailyLoginReminderAt) or 0
                        if WarbandNexus:HasDailyResetOccurredSince(lastAt) then
                            shouldFire = true
                        end
                    else
                        if CanShowReminder(plan, triggerKey) then
                            shouldFire = true
                        end
                    end
                    if shouldFire then
                        if useBlizzardDaily then
                            plan.reminder.lastDailyLoginReminderAt = time()
                        else
                            MarkReminderShown(plan, triggerKey)
                        end
                        ActivateReminder(plan, triggerLabel)
                    end
                end
            end
        end
    end

    processPlans(WarbandNexus.db.global.plans)
    processPlans(WarbandNexus.db.global.customPlans)
end

local function CheckMonthlyLoginReminders()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end

    local settings = GetReminderSettings()
    if settings and not settings.enabled then return end

    local L = ns.L
    local triggerLabel = (L and L["REMINDER_MONTHLY_LOGIN"]) or "Monthly login"

    local ym = date("%Y%m")
    local triggerKey = "monthly_" .. ym

    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            EnsureReminderField(plan)
            if plan.reminder and plan.reminder.enabled and plan.reminder.onMonthlyLogin then
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
-- INSTANCE HELPERS (secret-safe)
-- ============================================================================

local function SafeIsInInstance()
    local ok, a = pcall(IsInInstance)
    if not ok then return false end
    if a ~= nil and issecretvalue and issecretvalue(a) then return false end
    return a == true
end

local function SafeGetInstanceInfo()
    local ok, name, instType, difficultyID, difficultyName, maxPlayers, dynamicDifficulty, isDynamic, instanceID, instanceGUID, flags = pcall(GetInstanceInfo)
    if not ok then return nil end
    if name ~= nil and issecretvalue and issecretvalue(name) then
        name = nil
    end
    if difficultyID ~= nil and issecretvalue and issecretvalue(difficultyID) then
        difficultyID = nil
    else
        difficultyID = tonumber(difficultyID)
    end
    instanceID = tonumber(instanceID)
    return {
        name = name,
        instanceType = tonumber(instType),
        difficultyID = difficultyID,
        instanceID = instanceID,
    }
end

-- Zone uiMapID helpers before CheckZoneReminders (Lua 5.1: later `local function` is not visible above).

--- uiMapID → localized map name (nil if unknown / secret).
local function SafeUIMapDisplayName(mapID)
    local id = tonumber(mapID)
    if not id or id <= 0 then return nil end
    if not C_Map or not C_Map.GetMapInfo then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, id)
    if not ok or not info then return nil end
    local name = info.name
    if not name or name == "" then return nil end
    if issecretvalue and issecretvalue(name) then return nil end
    return name
end

--- Raw player uiMapID for zone reminders (no picker normalization — avoids district vs capital mismatch).
local function SafeGetRawPlayerUIMapID()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local ok, mapID = pcall(C_Map.GetBestMapForUnit, "player")
    if not ok or mapID == nil then return nil end
    if issecretvalue and issecretvalue(mapID) then return nil end
    mapID = tonumber(mapID)
    if not mapID or mapID <= 0 then return nil end
    return mapID
end

local function SafeParentUIMapIDForReminders(mid)
    if not mid or mid <= 0 then return nil end
    if not C_Map or not C_Map.GetMapInfo then return nil end
    local ok, info = pcall(C_Map.GetMapInfo, mid)
    if not ok or not info then return nil end
    local p = info.parentMapID
    if p == nil or p == 0 then return nil end
    if issecretvalue and issecretvalue(p) then return nil end
    p = tonumber(p)
    if not p or p <= 0 then return nil end
    return p
end

--- True if descendantId equals ancestorId or ancestorId appears on parent walk from descendantId.
local function MapIsUnderAncestor(descendantId, ancestorId)
    local target = tonumber(ancestorId)
    local cur = tonumber(descendantId)
    if not target or not cur then return false end
    local guard = 0
    while cur and cur > 0 and guard < 64 do
        guard = guard + 1
        if cur == target then return true end
        cur = SafeParentUIMapIDForReminders(cur)
    end
    return false
end

--- Union of all uiMapIDs on enabled zone_enter triggers (manual + serialized row maps + name hints only).
--- Hint expansion intentionally excludes parent chains — see GetMapIDsFromPlanSource.
local function BuildAllConfiguredZoneIdsUnion()
    local u = {}
    if not WarbandNexus.db or not WarbandNexus.db.global then return u end
    local function scan(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            EnsureReminderField(plan)
            if plan.reminder and plan.reminder.enabled and plan.reminder.onZoneEnter and not plan.completed then
                local ze = FindTriggerEntry(plan.reminder, KIND.ZONE_ENTER)
                if ze and ze.enabled ~= false then
                    local mapIDs = CollectZoneMapIDsFromEntry(plan, ze)
                    if mapIDs then
                        for mid, _ in pairs(mapIDs) do
                            local id = tonumber(mid)
                            if id then u[id] = true end
                        end
                    end
                end
            end
        end
    end
    scan(WarbandNexus.db.global.plans)
    scan(WarbandNexus.db.global.customPlans)
    return u
end

--- First configured reminder map encountered walking up from raw player map (alt-collapse only first).
--- Constant while flying within the same configured parent (e.g. all Stormwind districts → stable 84).
local function StableReminderZoneKey(rawMapID, configuredUnion)
    local r = tonumber(rawMapID)
    if not r or r <= 0 then return nil end
    local RCI = ns.ReminderContentIndex
    if RCI and RCI.CollapseAlternateUIMapOnly then
        local cr = RCI.CollapseAlternateUIMapOnly(r)
        if cr then r = cr end
    end
    if configuredUnion[r] then return r end
    local cur = r
    local guard = 0
    while cur and cur > 0 and guard < 64 do
        guard = guard + 1
        if configuredUnion[cur] then return cur end
        cur = SafeParentUIMapIDForReminders(cur)
    end
    return r
end

--- Zone reminders: alternate collapse (delves) + equality or configured map is strict ancestor of player map.
local function ZoneConfiguredMatchesCurrentMap(mapIDs, rawCurrentMapID)
    if not mapIDs or not rawCurrentMapID then return false end
    local cur = tonumber(rawCurrentMapID)
    if not cur or cur <= 0 then return false end
    local RCI = ns.ReminderContentIndex
    if RCI and RCI.CollapseAlternateUIMapOnly then
        local cr = RCI.CollapseAlternateUIMapOnly(cur)
        if cr then cur = cr end
    end
    for mid, _ in pairs(mapIDs) do
        local s = tonumber(mid)
        if s then
            if RCI and RCI.CollapseAlternateUIMapOnly then
                local cs = RCI.CollapseAlternateUIMapOnly(s)
                if cs then s = cs end
            end
            if s == cur then return true end
            if MapIsUnderAncestor(cur, s) then return true end
        end
    end
    return false
end

local lastStableReminderZoneKey = nil
local lastInstanceFingerprint = nil

local function CheckZoneReminders(rawMapID)
    if not rawMapID or rawMapID == 0 then return end
    if not WarbandNexus.db or not WarbandNexus.db.global then return end

    local settings = GetReminderSettings()
    if settings and not settings.enabled then
        lastStableReminderZoneKey = nil
        return
    end

    local configuredUnion = BuildAllConfiguredZoneIdsUnion()
    if not next(configuredUnion) then
        lastStableReminderZoneKey = nil
        return
    end

    local stable = StableReminderZoneKey(rawMapID, configuredUnion)
    if not stable then return end
    if stable == lastStableReminderZoneKey then return end
    lastStableReminderZoneKey = stable

    local L = ns.L
    local displayZoneName = tostring(rawMapID)
    if C_Map and C_Map.GetMapInfo then
        local okZ, currentZoneInfo = pcall(C_Map.GetMapInfo, rawMapID)
        if okZ and currentZoneInfo and currentZoneInfo.name
            and not (issecretvalue and issecretvalue(currentZoneInfo.name)) then
            displayZoneName = currentZoneInfo.name
        end
    end

    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            EnsureReminderField(plan)
            if plan.reminder and plan.reminder.enabled and plan.reminder.onZoneEnter then
                if not PlanAllowsLocationReminder(plan) then
                    -- skip location triggers when focus is set to another plan
                elseif not plan.completed then
                    local ze = FindTriggerEntry(plan.reminder, KIND.ZONE_ENTER)
                    if ze and ze.enabled ~= false then
                        local mapIDs = CollectZoneMapIDsFromEntry(plan, ze)
                        if mapIDs and next(mapIDs) ~= nil and ZoneConfiguredMatchesCurrentMap(mapIDs, rawMapID) then
                            local triggerKey = "zone_" .. tostring(stable)
                            if CanShowReminder(plan, triggerKey) then
                                if not LoginBurstSuppressLocationReminder(plan) then
                                    MarkReminderShown(plan, triggerKey)
                                    local label = string.format(
                                        (L and L["REMINDER_ZONE_ENTER"]) or "Entered %s",
                                        displayZoneName
                                    )
                                    ActivateReminder(plan, label, { repeatLocationNotify = true, fromLocation = true })
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    processPlans(WarbandNexus.db.global.plans)
    processPlans(WarbandNexus.db.global.customPlans)
end

local function CheckInstanceReminders()
    if not WarbandNexus.db or not WarbandNexus.db.global then return end

    local settings = GetReminderSettings()
    if settings and not settings.enabled then return end

    if not SafeIsInInstance() then
        lastInstanceFingerprint = nil
        return
    end

    local info = SafeGetInstanceInfo()
    if not info or not info.instanceID then return end

    local fingerprint = tostring(info.instanceID) .. "_" .. tostring(info.difficultyID or "any")
    if fingerprint == lastInstanceFingerprint then return end
    lastInstanceFingerprint = fingerprint

    local L = ns.L
    local displayName = info.name
    if not displayName or displayName == "" then
        displayName = (L and L["REMINDER_INSTANCE_GENERIC"]) or "Dungeon or raid"
    end

    local function processPlans(planList)
        if not planList then return end
        for i = 1, #planList do
            local plan = planList[i]
            EnsureReminderField(plan)
            if plan.reminder and plan.reminder.enabled and plan.reminder.onInstanceEnter then
                if not PlanAllowsLocationReminder(plan) then
                    -- skip
                elseif not plan.completed then
                    local ie = FindTriggerEntry(plan.reminder, KIND.INSTANCE_ENTER)
                    if ie and ie.enabled and tonumber(ie.instanceID) == info.instanceID then
                        local wantDiff = ie.difficultyID ~= nil and tonumber(ie.difficultyID) or nil
                        if wantDiff == nil or wantDiff == info.difficultyID then
                            local triggerKey = "inst_" .. tostring(info.instanceID) .. "_" .. tostring(info.difficultyID or "any")
                            if CanShowReminder(plan, triggerKey) then
                                if not LoginBurstSuppressLocationReminder(plan) then
                                    MarkReminderShown(plan, triggerKey)
                                    local label = string.format(
                                        (L and L["REMINDER_INSTANCE_ENTER"]) or "Entered instance (%s)",
                                        displayName
                                    )
                                    ActivateReminder(plan, label, { repeatLocationNotify = true, fromLocation = true })
                                end
                            end
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

local zoneChangeTimer = nil
local calendarResetReminderTimer = nil

--- Seconds until the earlier of the next daily or weekly Blizzard reset (+ small skew), or nil if APIs missing.
local function NextCalendarReminderDelay()
    local d = C_DateAndTime and C_DateAndTime.GetSecondsUntilDailyReset and C_DateAndTime.GetSecondsUntilDailyReset()
    local w = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset and C_DateAndTime.GetSecondsUntilWeeklyReset()
    local best = nil
    if type(d) == "number" and d >= 0 then
        local adj = (d < 1) and 2 or (d + 2)
        best = adj
    end
    if type(w) == "number" and w >= 0 then
        local adj = (w < 1) and 2 or (w + 2)
        if not best or adj < best then
            best = adj
        end
    end
    if not best then
        return nil
    end
    if best < 2 then
        best = 2
    end
    if best > 604800 then
        best = 604800
    end
    return best
end

local function CancelCalendarResetReminderTimer()
    if calendarResetReminderTimer then
        calendarResetReminderTimer:Cancel()
        calendarResetReminderTimer = nil
    end
end

local function ScheduleCalendarResetReminderTimer()
    CancelCalendarResetReminderTimer()
    if not (C_DateAndTime and (C_DateAndTime.GetSecondsUntilDailyReset or C_DateAndTime.GetSecondsUntilWeeklyReset)) then
        return
    end
    local delay = NextCalendarReminderDelay()
    if not delay then
        return
    end
    calendarResetReminderTimer = C_Timer.NewTimer(delay, function()
        calendarResetReminderTimer = nil
        OnLoginRemindersCheck()
        ScheduleCalendarResetReminderTimer()
    end)
end

local function RunZoneOrInstanceChangedNow()
    local mapID = SafeGetRawPlayerUIMapID()
    if mapID then
        CheckZoneReminders(mapID)
    end
    CheckInstanceReminders()
end

--- Coalesce ZONE_CHANGED* bursts (several events fire per transition).
local function OnZoneOrInstanceChanged()
    if zoneChangeTimer then
        zoneChangeTimer:Cancel()
        zoneChangeTimer = nil
    end
    zoneChangeTimer = C_Timer.NewTimer(0.12, function()
        zoneChangeTimer = nil
        RunZoneOrInstanceChangedNow()
    end)
end

local function OnLoginRemindersCheck()
    BeginCalendarToastBatch()
    CheckDailyLoginReminders()
    CheckMonthlyLoginReminders()
    CheckWeeklyResetReminders()
    CheckDaysBeforeResetReminders()
    FlushCalendarToastBatch()
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function WarbandNexus:InitializeReminderService()
    if not self.db or not self.db.global then return end

    CancelCalendarResetReminderTimer()

    self.db.global.reminderSettings = self.db.global.reminderSettings or {
        enabled = true,
        throttleSeconds = 300,
        throttleLocationReminders = false,
    }
    local rs = self.db.global.reminderSettings
    if rs.throttleLocationReminders == nil then
        rs.throttleLocationReminders = false
    end

    WarbandNexus.RegisterEvent(ReminderEvents, "ZONE_CHANGED_NEW_AREA", OnZoneOrInstanceChanged)
    WarbandNexus.RegisterEvent(ReminderEvents, "ZONE_CHANGED", OnZoneOrInstanceChanged)
    WarbandNexus.RegisterEvent(ReminderEvents, "ZONE_CHANGED_INDOORS", OnZoneOrInstanceChanged)
    local function OnPlayerEnteringWorldReminders()
        if ns.ReminderZoneCatalog and ns.ReminderZoneCatalog.InvalidateZoneApiCache then
            ns.ReminderZoneCatalog.InvalidateZoneApiCache()
        end
        BeginReminderLoginBurst()
        OnLoginRemindersCheck()
        RunZoneOrInstanceChangedNow()
    end

    WarbandNexus.RegisterEvent(ReminderEvents, "PLAYER_ENTERING_WORLD", OnPlayerEnteringWorldReminders)

    C_Timer.After(3, function()
        OnLoginRemindersCheck()
    end)

    C_Timer.After(5, function()
        RunZoneOrInstanceChangedNow()
    end)

    ScheduleCalendarResetReminderTimer()
end


local function UniqueSortedInts(t)
    local seen = {}
    local out = {}
    for i = 1, #t do
        local n = tonumber(t[i])
        if n and not seen[n] then
            seen[n] = true
            out[#out + 1] = n
        end
    end
    table.sort(out)
    return out
end

--- True when plan name/source text yields at least one uiMapID from C_Map child index (optional merge).
local function PlanHasZoneSourceHints(plan)
    local hinted = GetMapIDsFromPlanSource(plan)
    return hinted ~= nil and next(hinted) ~= nil
end

--- Set Alert always allows zone_enter: user checks the box then adds manual IDs / catalog / Get ID.
--- (Previously returning false when hints were missing deadlocked the UI: zone off disables the map row.)
local function ZoneTriggerAllowsConfigure(plan)
    return true
end

ns.ReminderServiceBridge = {
    EnsureReminderField = EnsureReminderField,
    FindTriggerEntry = FindTriggerEntry,
    KIND = KIND,
    UniqueSortedInts = UniqueSortedInts,
    ZoneTriggerAllowsConfigure = ZoneTriggerAllowsConfigure,
    PlanHasZoneSourceHints = PlanHasZoneSourceHints,
    SafeUIMapDisplayName = SafeUIMapDisplayName,
    GetReminderToastIconTexture = GetReminderToastIconTexture,
    --- Align GetBestMapForUnit child floors with ReminderContentIndex picker rows (Set Alert "Get ID").
    NormalizeZoneReminderUIMapID = function(mapID)
        local RCI = ns.ReminderContentIndex
        if RCI and RCI.NormalizeToCanonicalPickerMap then
            return RCI.NormalizeToCanonicalPickerMap(mapID)
        end
        return tonumber(mapID)
    end,
}

function WarbandNexus:ShowSetAlertDialog(planID)
    if InCombatLockdown() then return end
    local D = ns.ReminderSetAlertDialog
    if D and D.Show then
        D.Show(self, planID)
    end
end

