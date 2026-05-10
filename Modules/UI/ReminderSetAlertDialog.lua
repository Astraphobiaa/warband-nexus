--[[ To-Do plan reminder "Set Alert" dialog (view layer). Data entry points: ns.ReminderServiceBridge. ]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

ns.ReminderSetAlertDialog = ns.ReminderSetAlertDialog or {}

local reminderDialog = nil

function ns.ReminderSetAlertDialog.Show(addon, planID)
    local B = ns.ReminderServiceBridge
    if not B then return end
    local EnsureReminderField = B.EnsureReminderField
    local FindTriggerEntry = B.FindTriggerEntry
    local KIND = B.KIND
    local PlanHasZoneSourceHints = B.PlanHasZoneSourceHints
    local UniqueSortedInts = B.UniqueSortedInts
    local SafeUIMapDisplayName = B.SafeUIMapDisplayName
    local GetReminderToastIconTexture = B.GetReminderToastIconTexture
    local NormalizeZoneReminderUIMapID = B.NormalizeZoneReminderUIMapID

    local plan = addon:GetPlanByID(planID)
    if not plan then return end
    if InCombatLockdown() then return end

    local L = ns.L
    local COLORS = ns.UI_COLORS or { accent = {0.40, 0.20, 0.58}, accentDark = {0.28, 0.14, 0.41} }
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local r = EnsureReminderField(plan)

    if reminderDialog and reminderDialog:IsShown() then
        reminderDialog:Hide()
    end

    if not reminderDialog then
        local Factory = ns.UI and ns.UI.Factory
        local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
        local UI_SP = ns.UI_SPACING or {}
        local sideInset = UI_SP.SIDE_MARGIN or 14
        local afterEl = UI_SP.AFTER_ELEMENT or 8
        local layout = ns.UI_LAYOUT or UI_SP
        local scrollBarW = layout.SCROLLBAR_COLUMN_WIDTH or 22
        local rowGap = 22
        local zoneSubInset = sideInset + (UI_SP.SUBROW_EXTRA_INDENT or 12)
        local footerH = 52
        local dialogW, dialogH = 760, 748
        local CreateIcon = ns.UI_CreateIcon
        local bcRaw = COLORS.border or { 0.22, 0.22, 0.28 }
        local borderCol = { bcRaw[1], bcRaw[2], bcRaw[3], bcRaw[4] or 0.65 }
        local labelMuted = { 0.78, 0.78, 0.82 }
        local labelBody = { 0.94, 0.94, 0.96 }

        local f = CreateFrame("Frame", "WarbandNexus_ReminderDialog", UIParent, "BackdropTemplate")
        f:SetSize(dialogW, dialogH)
        f:SetPoint("CENTER")
        f:EnableMouse(true)
        f:SetMovable(true)

        if ns.WindowManager then
            ns.WindowManager:ApplyStrata(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:Register(f, ns.WindowManager.PRIORITY.POPUP)
            ns.WindowManager:InstallESCHandler(f)
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
        header:SetHeight(40)
        header:SetPoint("TOPLEFT", 3, -3)
        header:SetPoint("TOPRIGHT", -3, -3)
        header:SetFrameLevel(f:GetFrameLevel() + 6)
        if ApplyVisuals then
            ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.55})
        end

        local closeBtn = Factory and Factory:CreateButton(header, 28, 28, false) or CreateFrame("Button", nil, header, "BackdropTemplate")
        closeBtn:SetSize(28, 28)
        closeBtn:SetPoint("RIGHT", header, "RIGHT", -afterEl, 0)
        if ApplyVisuals then
            ApplyVisuals(closeBtn, {0.06, 0.06, 0.09, 0.96}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.45})
        end
        local closeIcon = closeBtn:CreateTexture(nil, "OVERLAY")
        closeIcon:SetSize(16, 16)
        closeIcon:SetPoint("CENTER")
        local closeAtlasOk = pcall(function()
            closeIcon:SetAtlas("uitools-icon-close", false)
        end)
        if not closeAtlasOk then
            closeIcon:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
        end
        closeIcon:SetVertexColor(0.92, 0.35, 0.35)
        closeBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        local headerTitle = FontManager:CreateFontString(header, "title", "OVERLAY")
        headerTitle:SetPoint("LEFT", header, "LEFT", afterEl, 0)
        headerTitle:SetPoint("RIGHT", closeBtn, "LEFT", -afterEl, 0)
        headerTitle:SetJustifyH("LEFT")
        headerTitle:SetMaxLines(1)
        headerTitle:SetText((L and L["SET_ALERT_TITLE"]) or "Set Alert")
        headerTitle:SetTextColor(1, 1, 1)
        f.headerTitle = headerTitle

        header:EnableMouse(true)
        if ns.WindowManager and ns.WindowManager.InstallDragHandler then
            ns.WindowManager:InstallDragHandler(header, f)
        end

        local planRow = CreateFrame("Frame", nil, f)
        planRow:SetPoint("TOPLEFT", header, "BOTTOMLEFT", sideInset, -10)
        planRow:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -sideInset, -10)
        planRow:SetHeight(34)
        f.planRow = planRow

        local hornSz = 26
        local hornIcon = CreateIcon and CreateIcon(planRow, GetReminderToastIconTexture(), hornSz, true, nil, true)
        if hornIcon then
            hornIcon:SetPoint("LEFT", planRow, "LEFT", 0, 0)
            hornIcon:Show()
        end
        f.planHornIcon = hornIcon

        local planTypeBadge = CreateFrame("Frame", nil, planRow)
        planTypeBadge:SetSize(22, 22)
        planTypeBadge:SetPoint("LEFT", hornIcon or planRow, hornIcon and "RIGHT" or "LEFT", hornIcon and 8 or 0, 0)
        local planTypeTex = planTypeBadge:CreateTexture(nil, "OVERLAY")
        planTypeTex:SetAllPoints()
        planTypeBadge:Hide()
        f.planTypeBadge = planTypeBadge
        f.planTypeTex = planTypeTex

        local planTitleFs = FontManager:CreateFontString(planRow, "body", "OVERLAY")
        planTitleFs:SetPoint("TOP", planRow, "TOP", 0, -4)
        planTitleFs:SetPoint("BOTTOM", planRow, "BOTTOM", 0, 4)
        planTitleFs:SetJustifyH("LEFT")
        planTitleFs:SetJustifyV("MIDDLE")
        planTitleFs:SetWordWrap(false)
        planTitleFs:SetMaxLines(1)
        f.planTitleFs = planTitleFs

        local planPointsFs = FontManager:CreateFontString(planRow, "subtitle", "OVERLAY")
        planPointsFs:SetPoint("RIGHT", planRow, "RIGHT", 0, 0)
        planPointsFs:SetPoint("TOP", planRow, "TOP", 0, -4)
        planPointsFs:SetPoint("BOTTOM", planRow, "BOTTOM", 0, 4)
        planPointsFs:SetJustifyH("RIGHT")
        planPointsFs:SetWidth(120)
        planPointsFs:Hide()
        f.planPointsFs = planPointsFs

        local bodyHost = CreateFrame("Frame", nil, f)
        bodyHost:SetPoint("TOPLEFT", planRow, "BOTTOMLEFT", 0, -8)
        bodyHost:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -sideInset, footerH)
        f.reminderBodyHost = bodyHost

        local scrollBarColumn = Factory and Factory:CreateScrollBarColumn(bodyHost, scrollBarW, 0, 0)
        if scrollBarColumn then
            scrollBarColumn:SetPoint("TOPRIGHT", bodyHost, "TOPRIGHT", 0, 0)
            scrollBarColumn:SetPoint("BOTTOMRIGHT", bodyHost, "BOTTOMRIGHT", 0, 0)
        end

        local scrollFrame = Factory and Factory:CreateScrollFrame(bodyHost, "UIPanelScrollFrameTemplate", true)
        if not scrollFrame then
            scrollFrame = CreateFrame("ScrollFrame", nil, bodyHost, "UIPanelScrollFrameTemplate")
        end
        scrollFrame:SetPoint("TOPLEFT", bodyHost, "TOPLEFT", 0, 0)
        if scrollBarColumn then
            scrollFrame:SetPoint("BOTTOMRIGHT", scrollBarColumn, "BOTTOMLEFT", -4, 0)
            if scrollFrame.ScrollBar and Factory and Factory.PositionScrollBarInContainer then
                Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
            end
        else
            scrollFrame:SetPoint("BOTTOMRIGHT", bodyHost, "BOTTOMRIGHT", 0, 0)
        end

        local sc = CreateFrame("Frame", nil, scrollFrame)
        local innerW = math.max(120, (dialogW - sideInset * 2) - scrollBarW - 4)
        sc:SetWidth(innerW)
        scrollFrame:SetScrollChild(sc)
        f.reminderScrollFrame = scrollFrame
        f.reminderScrollChild = sc

        scrollFrame:SetScript("OnSizeChanged", function(self)
            local child = self:GetScrollChild()
            local w = self:GetWidth()
            if child and w then child:SetWidth(w) end
            if f._layoutReminderGrids then
                f._layoutReminderGrids()
            end
            if Factory and Factory.UpdateScrollBarVisibility then
                Factory:UpdateScrollBarVisibility(self)
            end
        end)

        local function AttachOptionLabel(fs, anchorWidget, textStr)
            fs:SetPoint("LEFT", anchorWidget, "RIGHT", 8, 0)
            fs:SetPoint("RIGHT", sc, "RIGHT", -sideInset, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(textStr)
            fs:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
        end

        local function WireLabelToggle(label, cb)
            if not label or not cb then return end
            label:EnableMouse(true)
            if label.RegisterForClicks then
                label:RegisterForClicks("LeftButtonUp")
            end
            label:SetScript("OnMouseUp", function(_, btn)
                if btn ~= "LeftButton" then return end
                if cb:IsEnabled() then
                    cb:Click()
                end
            end)
        end

        local yOff = -4
        local cardPad = 10
        local bgCardCol = COLORS.bgCard or { 0.08, 0.08, 0.10, 1 }

        local scheduleCard = CreateFrame("Frame", nil, sc)
        scheduleCard:SetPoint("TOPLEFT", sideInset, yOff)
        scheduleCard:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -sideInset, yOff)
        scheduleCard:SetHeight(68)
        if ApplyVisuals then
            ApplyVisuals(scheduleCard,
                { bgCardCol[1], bgCardCol[2], bgCardCol[3], bgCardCol[4] or 1 },
                { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end

        local scheduleInner = CreateFrame("Frame", nil, scheduleCard)
        scheduleInner:SetPoint("TOPLEFT", scheduleCard, "TOPLEFT", cardPad, -cardPad)
        scheduleInner:SetPoint("BOTTOMRIGHT", scheduleCard, "BOTTOMRIGHT", -cardPad, cardPad)

        local schedCols = {}
        for si = 1, 2 do
            schedCols[si] = CreateFrame("Frame", nil, scheduleInner)
        end

        local function LayoutScheduleGrid()
            local rw = scheduleInner:GetWidth()
            local rh = scheduleInner:GetHeight()
            if not rw or rw < 80 or not rh or rh < 8 then return end
            local gap = 10
            local cw = (rw - gap) / 2
            schedCols[1]:ClearAllPoints()
            schedCols[1]:SetPoint("TOPLEFT", scheduleInner, "TOPLEFT", 0, 0)
            schedCols[1]:SetSize(cw, rh)
            schedCols[2]:ClearAllPoints()
            schedCols[2]:SetPoint("TOPLEFT", scheduleInner, "TOPLEFT", cw + gap, 0)
            schedCols[2]:SetSize(cw, rh)
        end

        scheduleInner:SetScript("OnSizeChanged", LayoutScheduleGrid)

        local dailyCheck = CreateThemedCheckbox(schedCols[1], false)
        dailyCheck:SetPoint("TOP", schedCols[1], "TOP", 0, -8)
        local dailyLabel = FontManager:CreateFontString(schedCols[1], "body", "OVERLAY")
        dailyLabel:SetPoint("TOPLEFT", schedCols[1], "TOPLEFT", 4, -38)
        dailyLabel:SetPoint("TOPRIGHT", schedCols[1], "TOPRIGHT", -4, -38)
        dailyLabel:SetJustifyH("CENTER")
        dailyLabel:SetWordWrap(true)
        dailyLabel:SetMaxLines(2)
        dailyLabel:SetText((L and L["REMINDER_OPT_DAILY"]) or "Daily Login")
        dailyLabel:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
        WireLabelToggle(dailyLabel, dailyCheck)
        f.dailyCheck = dailyCheck

        local weeklyCheck = CreateThemedCheckbox(schedCols[2], false)
        weeklyCheck:SetPoint("TOP", schedCols[2], "TOP", 0, -8)
        local weeklyLabel = FontManager:CreateFontString(schedCols[2], "body", "OVERLAY")
        weeklyLabel:SetPoint("TOPLEFT", schedCols[2], "TOPLEFT", 4, -38)
        weeklyLabel:SetPoint("TOPRIGHT", schedCols[2], "TOPRIGHT", -4, -38)
        weeklyLabel:SetJustifyH("CENTER")
        weeklyLabel:SetWordWrap(true)
        weeklyLabel:SetMaxLines(2)
        weeklyLabel:SetText((L and L["REMINDER_OPT_WEEKLY"]) or "Weekly Reset")
        weeklyLabel:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
        WireLabelToggle(weeklyLabel, weeklyCheck)
        f.weeklyCheck = weeklyCheck

        yOff = yOff - 68 - 10

        local secDays = FontManager:CreateFontString(sc, "subtitle", "OVERLAY")
        secDays:SetPoint("TOPLEFT", sideInset, yOff)
        secDays:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -sideInset, yOff)
        secDays:SetJustifyH("LEFT")
        secDays:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        secDays:SetText((L and L["SET_ALERT_BEFORE_RESET_GROUP"]) or "Days before weekly reset")
        yOff = yOff - 18

        local daysBeforeCard = CreateFrame("Frame", nil, sc)
        daysBeforeCard:SetPoint("TOPLEFT", sideInset, yOff)
        daysBeforeCard:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -sideInset, yOff)
        daysBeforeCard:SetHeight(80)
        if ApplyVisuals then
            ApplyVisuals(daysBeforeCard,
                { bgCardCol[1], bgCardCol[2], bgCardCol[3], bgCardCol[4] or 1 },
                { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end

        local daysBeforeInner = CreateFrame("Frame", nil, daysBeforeCard)
        daysBeforeInner:SetPoint("TOPLEFT", daysBeforeCard, "TOPLEFT", cardPad, -cardPad)
        daysBeforeInner:SetPoint("BOTTOMRIGHT", daysBeforeCard, "BOTTOMRIGHT", -cardPad, cardPad)

        local dayCols = {}
        for ci = 1, 3 do
            dayCols[ci] = CreateFrame("Frame", nil, daysBeforeInner)
        end

        local dayGridGap = 8

        local function LayoutDaysBeforeGrid()
            local rw = daysBeforeInner:GetWidth()
            local rh = daysBeforeInner:GetHeight()
            if not rw or rw < 120 or not rh or rh < 8 then return end
            local gaps = dayGridGap * 2
            local cw = (rw - gaps) / 3
            for ci = 1, 3 do
                local col = dayCols[ci]
                col:ClearAllPoints()
                col:SetPoint("TOPLEFT", daysBeforeInner, "TOPLEFT", (ci - 1) * (cw + dayGridGap), 0)
                col:SetSize(cw, rh)
            end
        end

        daysBeforeInner:SetScript("OnSizeChanged", LayoutDaysBeforeGrid)

        local function AddDaysBeforeCell(col, daysN)
            local cb = CreateThemedCheckbox(col, false)
            cb:SetPoint("TOP", col, "TOP", 0, -8)
            local lbl = FontManager:CreateFontString(col, "body", "OVERLAY")
            lbl:SetPoint("TOPLEFT", col, "TOPLEFT", 2, -38)
            lbl:SetPoint("TOPRIGHT", col, "TOPRIGHT", -2, -38)
            lbl:SetJustifyH("CENTER")
            lbl:SetJustifyV("TOP")
            lbl:SetWordWrap(true)
            lbl:SetMaxLines(4)
            lbl:SetText(string.format((L and L["REMINDER_OPT_DAYS_BEFORE"]) or "%d days before reset", daysN))
            lbl:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
            WireLabelToggle(lbl, cb)
            return cb
        end

        f.days5Check = AddDaysBeforeCell(dayCols[1], 5)
        f.days3Check = AddDaysBeforeCell(dayCols[2], 3)
        f.days1Check = AddDaysBeforeCell(dayCols[3], 1)

        local function LayoutReminderOptionGrids()
            LayoutScheduleGrid()
            LayoutDaysBeforeGrid()
        end

        f._layoutReminderGrids = LayoutReminderOptionGrids
        LayoutReminderOptionGrids()

        yOff = yOff - 80 - 12

        local secLocation = FontManager:CreateFontString(sc, "subtitle", "OVERLAY")
        secLocation:SetPoint("TOPLEFT", sideInset, yOff)
        secLocation:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -sideInset, yOff)
        secLocation:SetJustifyH("LEFT")
        secLocation:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        secLocation:SetText((L and L["SET_ALERT_SECTION_LOCATION"]) or "Zone & Instance")
        yOff = yOff - 18

        local zoneCheck = CreateThemedCheckbox(sc, false)
        zoneCheck:SetPoint("TOPLEFT", sideInset, yOff)
        local zoneLabel = FontManager:CreateFontString(sc, "body", "OVERLAY")
        AttachOptionLabel(zoneLabel, zoneCheck, (L and L["REMINDER_OPT_ZONE_ENTER_MATCHING"]) or (L and L["REMINDER_OPT_ZONE"]) or "Remind me when enter to matching zone")
        WireLabelToggle(zoneLabel, zoneCheck)
        f.zoneCheck = zoneCheck
        f.zoneLabel = zoneLabel
        zoneCheck:HookScript("OnClick", function()
            if f.ApplyZoneDependentControlsState then
                f:ApplyZoneDependentControlsState()
            end
        end)
        yOff = yOff - rowGap

        local mapGetIdBtn = Factory and Factory:CreateButton(sc, 78, 28, false)
        if not mapGetIdBtn then
            mapGetIdBtn = CreateFrame("Button", nil, sc, "BackdropTemplate")
            mapGetIdBtn:SetSize(78, 28)
            if ApplyVisuals then
                ApplyVisuals(mapGetIdBtn, { 0.12, 0.12, 0.15, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.45 })
            end
        end
        mapGetIdBtn:SetPoint("TOPLEFT", sideInset, yOff)
        local mapGetIdTxt = FontManager:CreateFontString(mapGetIdBtn, "small", "OVERLAY")
        mapGetIdTxt:SetPoint("CENTER")
        mapGetIdTxt:SetText((L and L["REMINDER_ZONE_GET_ID"]) or "Get ID")
        f.mapGetIdBtn = mapGetIdBtn

        local mapEditBg = Factory and Factory:CreateContainer(sc, 120, 28)
        if not mapEditBg then
            mapEditBg = CreateFrame("Frame", nil, sc)
            mapEditBg:SetHeight(28)
        end
        mapEditBg:SetPoint("TOPLEFT", mapGetIdBtn, "TOPRIGHT", 8, 0)
        mapEditBg:SetPoint("TOPRIGHT", sc, "TOPRIGHT", -sideInset, yOff)
        if ApplyVisuals then
            ApplyVisuals(mapEditBg, { 0.08, 0.08, 0.10, 1 }, { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end
        mapEditBg:EnableMouse(true)

        local mapEdit = Factory and Factory:CreateEditBox(mapEditBg)
        if not mapEdit then
            mapEdit = CreateFrame("EditBox", nil, mapEditBg, "BackdropTemplate")
            mapEdit:SetPoint("LEFT", mapEditBg, "LEFT", 4, 0)
            mapEdit:SetPoint("RIGHT", mapEditBg, "RIGHT", -4, 0)
            mapEdit:SetHeight(22)
            mapEdit:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8X8",
                edgeFile = "Interface\\Buttons\\WHITE8X8",
                tile = false,
                edgeSize = 1,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })
            mapEdit:SetBackdropColor(0.06, 0.06, 0.08, 1)
            mapEdit:SetBackdropBorderColor(borderCol[1], borderCol[2], borderCol[3], 0.8)
            mapEdit:SetFontObject(GameFontHighlightSmall)
            mapEdit:SetTextInsets(6, 6, 1, 1)
        end
        mapEdit:SetPoint("LEFT", mapEditBg, "LEFT", 6, 0)
        mapEdit:SetPoint("RIGHT", mapEditBg, "RIGHT", -6, 0)
        mapEdit:SetHeight(22)
        mapEdit:SetNumeric(true)
        mapEdit:SetMaxLetters(12)
        mapEdit:SetTextColor(1, 1, 1, 1)
        mapEdit:SetAutoFocus(false)
        mapEditBg:SetScript("OnMouseDown", function()
            mapEdit:SetFocus()
        end)
        f.mapEdit = mapEdit

        local belowMapRow = CreateFrame("Frame", nil, sc)
        belowMapRow:SetPoint("TOPLEFT", mapGetIdBtn, "BOTTOMLEFT", 0, -8)
        belowMapRow:SetPoint("TOPRIGHT", mapEditBg, "BOTTOMRIGHT", 0, -8)
        belowMapRow:SetHeight(1)

        f.mapFieldHint = FontManager:CreateFontString(sc, "small", "OVERLAY")
        f.mapFieldHint:SetPoint("TOPLEFT", belowMapRow, "BOTTOMLEFT", 0, -4)
        f.mapFieldHint:SetPoint("TOPRIGHT", belowMapRow, "BOTTOMRIGHT", 0, -4)
        f.mapFieldHint:SetJustifyH("LEFT")
        f.mapFieldHint:SetWordWrap(true)
        f.mapFieldHint:SetMaxLines(2)
        f.mapFieldHint:SetTextColor(0.55, 0.58, 0.64)
        f.mapFieldHint:SetText((L and L["REMINDER_ZONE_FIELD_SAVED_WITH_ALERT"]) or "")

        f.mapIdZonePreview = FontManager:CreateFontString(sc, "small", "OVERLAY")
        f.mapIdZonePreview:SetPoint("TOPLEFT", f.mapFieldHint, "BOTTOMLEFT", 0, -6)
        f.mapIdZonePreview:SetPoint("TOPRIGHT", f.mapFieldHint, "BOTTOMRIGHT", 0, -6)
        f.mapIdZonePreview:SetJustifyH("LEFT")
        f.mapIdZonePreview:SetWordWrap(false)
        f.mapIdZonePreview:SetMaxLines(1)
        f.mapIdZonePreview:SetTextColor(labelMuted[1], labelMuted[2], labelMuted[3])

        f.mapsManualCard = CreateFrame("Frame", nil, sc)
        f.mapsManualCard:SetPoint("TOPLEFT", f.mapIdZonePreview, "BOTTOMLEFT", 0, -10)
        f.mapsManualCard:SetPoint("TOPRIGHT", f.mapIdZonePreview, "BOTTOMRIGHT", 0, -10)
        f.mapsManualCard:SetHeight(96)
        if ApplyVisuals then
            ApplyVisuals(f.mapsManualCard,
                { bgCardCol[1], bgCardCol[2], bgCardCol[3], bgCardCol[4] or 1 },
                { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end

        local mmPad = cardPad
        f.mapsManualTitle = FontManager:CreateFontString(f.mapsManualCard, "subtitle", "OVERLAY")
        f.mapsManualTitle:SetPoint("TOPLEFT", f.mapsManualCard, "TOPLEFT", mmPad, -mmPad)
        f.mapsManualTitle:SetPoint("TOPRIGHT", f.mapsManualCard, "TOPRIGHT", -mmPad, -mmPad)
        f.mapsManualTitle:SetJustifyH("LEFT")
        f.mapsManualTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        f.mapsManualTitle:SetText(string.format((L and L["REMINDER_ZONE_MANUAL_COUNT"]) or "Manual maps: %d", 0))

        f.mapsManualEmpty = FontManager:CreateFontString(f.mapsManualCard, "small", "OVERLAY")
        f.mapsManualEmpty:SetPoint("TOPLEFT", f.mapsManualTitle, "BOTTOMLEFT", 0, -8)
        f.mapsManualEmpty:SetPoint("TOPRIGHT", f.mapsManualTitle, "BOTTOMRIGHT", 0, -8)
        f.mapsManualEmpty:SetJustifyH("LEFT")
        f.mapsManualEmpty:SetWordWrap(true)
        f.mapsManualEmpty:SetMaxLines(2)
        f.mapsManualEmpty:SetTextColor(0.55, 0.58, 0.64)
        f.mapsManualEmpty:SetText((L and L["REMINDER_ZONE_MANUAL_EMPTY"]) or "No maps saved yet. Use Get ID, press Enter in the field, or Add from the list below.")

        f.mapsManualRowsHost = CreateFrame("Frame", nil, f.mapsManualCard)
        f.mapsManualRowsHost:SetPoint("TOPLEFT", f.mapsManualTitle, "BOTTOMLEFT", 0, -6)
        f.mapsManualRowsHost:SetPoint("TOPRIGHT", f.mapsManualTitle, "BOTTOMRIGHT", 0, -6)
        f.mapsManualRowsHost:SetClipsChildren(true)

        local MAN_ROW_H = 26
        local MAN_TAG_W = 54
        local MAN_RM_W = 62
        local MAN_ROW_GAP = 4
        local MAX_MANUAL_MAP_ROWS = 28
        local UIMT = Enum and Enum.UIMapType

        local function ManualRowTagText(mapID)
            local UICK = ns.UIMapContentKind
            if UICK and UICK.Resolve and UICK.FormatPickerTag then
                if UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end
                local kind = UICK.Resolve(tonumber(mapID))
                return UICK.FormatPickerTag(kind)
            end
            local Lz = ns.L
            return (Lz and Lz["REMINDER_ZONE_CAT_TAG_ZONE"]) or "[Z]"
        end

        f._manualMapRows = {}
        for mri = 1, MAX_MANUAL_MAP_ROWS do
            local row = CreateFrame("Frame", nil, f.mapsManualRowsHost)
            row:SetHeight(MAN_ROW_H)
            row:Hide()

            row.tagFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.tagFs:SetWidth(MAN_TAG_W)
            row.tagFs:SetPoint("LEFT", row, "LEFT", mmPad, 0)
            row.tagFs:SetJustifyH("CENTER")

            row.rmBtn = Factory and Factory:CreateButton(row, MAN_RM_W, 22, false)
            if not row.rmBtn then
                row.rmBtn = CreateFrame("Button", nil, row, "BackdropTemplate")
                row.rmBtn:SetSize(MAN_RM_W, 22)
            end
            row.rmBtn:SetPoint("RIGHT", row, "RIGHT", -mmPad, 0)
            if ApplyVisuals then
                ApplyVisuals(row.rmBtn, { 0.22, 0.1, 0.1, 1 }, { 0.75, 0.28, 0.28, 0.85 })
            end
            local rmTxt = FontManager:CreateFontString(row.rmBtn, "small", "OVERLAY")
            rmTxt:SetPoint("CENTER")
            rmTxt:SetText((L and L["REMINDER_ZONE_MANUAL_REMOVE"]) or "Remove")

            row.labelFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.labelFs:SetPoint("LEFT", row.tagFs, "RIGHT", 6, 0)
            row.labelFs:SetPoint("RIGHT", row.rmBtn, "LEFT", -8, 0)
            row.labelFs:SetJustifyH("LEFT")
            row.labelFs:SetWordWrap(false)
            row.labelFs:SetMaxLines(1)

            row.rmBtn:SetScript("OnClick", function()
                f:RemoveManualMapId(row._mapId)
            end)

            f._manualMapRows[mri] = row
        end

        function f:RemoveManualMapId(mid)
            mid = tonumber(mid)
            if not mid or mid <= 0 then return end
            local t = self._manualMapIDs
            if not t then return end
            local out = {}
            for ii = 1, #t do
                if t[ii] ~= mid then
                    out[#out + 1] = t[ii]
                end
            end
            self._manualMapIDs = out
            self:RefreshManualMapList()
            if self._zoneGatePlan and self.zoneCheck then
                self.zoneCheck:Enable()
                self.zoneCheck:SetAlpha(1)
                if self.zoneLabel then
                    self.zoneLabel:SetTextColor(0.9, 0.9, 0.9)
                end
            end
            if self.ApplyZoneDependentControlsState then
                self:ApplyZoneDependentControlsState()
            end
        end

        function f:RefreshManualMapList()
            local Lz = ns.L
            local ids = self._manualMapIDs or {}
            local n = #ids
            local unk = (Lz and Lz["UNKNOWN"]) or "?"

            if self.mapsManualTitle then
                self.mapsManualTitle:SetText(string.format((Lz and Lz["REMINDER_ZONE_MANUAL_COUNT"]) or "Manual maps: %d", n))
            end

            local rows = self._manualMapRows or {}
            for ri = 1, #rows do
                local row = rows[ri]
                if row then
                    if ri <= n then
                        local id = ids[ri]
                        row._mapId = id
                        row:ClearAllPoints()
                        if ri == 1 then
                            row:SetPoint("TOPLEFT", self.mapsManualRowsHost, "TOPLEFT", 0, 0)
                            row:SetPoint("TOPRIGHT", self.mapsManualRowsHost, "TOPRIGHT", 0, 0)
                        else
                            row:SetPoint("TOPLEFT", rows[ri - 1], "BOTTOMLEFT", 0, -MAN_ROW_GAP)
                            row:SetPoint("TOPRIGHT", rows[ri - 1], "BOTTOMRIGHT", 0, -MAN_ROW_GAP)
                        end
                        local tStr = ManualRowTagText(id)
                        local okI, mapInf = pcall(C_Map.GetMapInfo, id)
                        if okI and mapInf and UIMT then
                            if mapInf.mapType == UIMT.Dungeon then
                                row.tagFs:SetText("|cffc8b68e" .. tStr .. "|r")
                            elseif mapInf.mapType == UIMT.Orphan then
                                row.tagFs:SetText("|cff8eb0ca" .. tStr .. "|r")
                            else
                                row.tagFs:SetText("|cff9ecfae" .. tStr .. "|r")
                            end
                        else
                            row.tagFs:SetText("|cff9ecfae" .. tStr .. "|r")
                        end
                        local nm = SafeUIMapDisplayName(id)
                        row.labelFs:SetText(string.format(
                            "|cffffffff%s|r |cff888888— %d|r",
                            nm or unk,
                            id
                        ))
                        row:Show()
                    else
                        row._mapId = nil
                        row:Hide()
                        row:ClearAllPoints()
                    end
                end
            end

            local titleH = 22
            local emptyH = 0
            if n == 0 then
                if self.mapsManualEmpty then
                    self.mapsManualEmpty:Show()
                    emptyH = (self.mapsManualEmpty:GetStringHeight() or 28) + 10
                end
                if self.mapsManualRowsHost then
                    self.mapsManualRowsHost:Hide()
                end
            else
                if self.mapsManualEmpty then
                    self.mapsManualEmpty:Hide()
                end
                if self.mapsManualRowsHost then
                    self.mapsManualRowsHost:Show()
                    self.mapsManualRowsHost:ClearAllPoints()
                    self.mapsManualRowsHost:SetPoint("TOPLEFT", self.mapsManualTitle, "BOTTOMLEFT", 0, -6)
                    self.mapsManualRowsHost:SetPoint("TOPRIGHT", self.mapsManualTitle, "BOTTOMRIGHT", 0, -6)
                    local rowsH = n * MAN_ROW_H + math.max(0, n - 1) * MAN_ROW_GAP
                    self.mapsManualRowsHost:SetHeight(rowsH)
                end
                emptyH = 0
            end

            local cardH
            if n == 0 then
                cardH = mmPad + titleH + 6 + emptyH + mmPad
            else
                local rh = (self.mapsManualRowsHost and self.mapsManualRowsHost:GetHeight()) or 0
                cardH = mmPad + titleH + 6 + rh + mmPad
            end
            if self.mapsManualCard then
                self.mapsManualCard:SetHeight(math.max(88, cardH))
            end

            if self.reminderScrollChild then
                local catBoost = (self.zoneCatalogCard and self.zoneCatalogCard:IsShown()) and 300 or 0
                local mh = (self.mapsManualCard and self.mapsManualCard:GetHeight()) or 40
                self.reminderScrollChild:SetHeight(math.max(560, 440 + mh + catBoost))
            end
        end

        local function BindCatalogMouseWheel(scrollFrame)
            if not scrollFrame or not scrollFrame.SetScript then return end
            scrollFrame:EnableMouseWheel(true)
            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                local step = (ns.UI_GetScrollStep and ns.UI_GetScrollStep())
                    or ((ns.UI_LAYOUT or ns.UI_SPACING or {}).SCROLL_BASE_STEP or 28)
                local cur = self:GetVerticalScroll() or 0
                local mx = self:GetVerticalScrollRange() or 0
                local nv = cur - delta * step
                if nv < 0 then nv = 0 end
                if nv > mx then nv = mx end
                self:SetVerticalScroll(nv)
            end)
        end

        local function TruncatePickerLabel(str, maxLen)
            if not str then return "" end
            maxLen = maxLen or 52
            if #str <= maxLen then return str end
            return str:sub(1, maxLen - 1) .. "…"
        end

        local bgCardColCatalog = COLORS.bgCard or { 0.08, 0.08, 0.10, 1 }
        f.zoneCatalogCard = CreateFrame("Frame", nil, sc)
        f.zoneCatalogCard:SetPoint("TOPLEFT", f.mapsManualCard, "BOTTOMLEFT", 0, -12)
        f.zoneCatalogCard:SetPoint("TOPRIGHT", f.mapsManualCard, "BOTTOMRIGHT", 0, -12)
        f.zoneCatalogCard:SetHeight(416)

        if ApplyVisuals then
            ApplyVisuals(f.zoneCatalogCard,
                { bgCardColCatalog[1], bgCardColCatalog[2], bgCardColCatalog[3], bgCardColCatalog[4] or 1 },
                { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end

        local zcPad = 8
        local zoneCatTitle = FontManager:CreateFontString(f.zoneCatalogCard, "subtitle", "OVERLAY")
        zoneCatTitle:SetPoint("TOPLEFT", f.zoneCatalogCard, "TOPLEFT", cardPad, -zcPad)
        zoneCatTitle:SetPoint("TOPRIGHT", f.zoneCatalogCard, "TOPRIGHT", -cardPad, -zcPad)
        zoneCatTitle:SetJustifyH("LEFT")
        zoneCatTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        zoneCatTitle:SetText((L and L["REMINDER_ZONE_CATALOG_TITLE"]) or "Zones by expansion")

        local zoneCatHint = FontManager:CreateFontString(f.zoneCatalogCard, "small", "OVERLAY")
        zoneCatHint:SetPoint("TOPLEFT", zoneCatTitle, "BOTTOMLEFT", 0, -4)
        zoneCatHint:SetPoint("TOPRIGHT", zoneCatTitle, "BOTTOMRIGHT", 0, -4)
        zoneCatHint:SetJustifyH("LEFT")
        zoneCatHint:SetWordWrap(true)
        zoneCatHint:SetMaxLines(3)
        zoneCatHint:SetTextColor(0.55, 0.58, 0.64)
        zoneCatHint:SetText((L and L["REMINDER_ZONE_CATALOG_HINT"]) or "Choose an expansion, tap Add on zones, then Save.")

        local zbScrollW = scrollBarW
        local expInnerW = 154
        local splitGap = 10
        local expPanelOuterW = expInnerW + zbScrollW + 4

        local mapsBody = CreateFrame("Frame", nil, f.zoneCatalogCard)
        mapsBody:SetPoint("TOPLEFT", zoneCatHint, "BOTTOMLEFT", 0, -8)
        mapsBody:SetPoint("BOTTOMRIGHT", f.zoneCatalogCard, "BOTTOMRIGHT", -cardPad, zcPad)

        local colHeadRow = CreateFrame("Frame", nil, mapsBody)
        colHeadRow:SetPoint("TOPLEFT", mapsBody, "TOPLEFT", 0, 0)
        colHeadRow:SetPoint("TOPRIGHT", mapsBody, "TOPRIGHT", 0, 0)
        colHeadRow:SetHeight(18)

        local expHead = FontManager:CreateFontString(colHeadRow, "subtitle", "OVERLAY")
        expHead:SetPoint("TOPLEFT", colHeadRow, "TOPLEFT", 0, 0)
        expHead:SetWidth(expInnerW)
        expHead:SetJustifyH("LEFT")
        expHead:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        expHead:SetText((L and L["REMINDER_ZONE_CATALOG_EXPANSIONS_LABEL"]) or "Expansion")

        local mapsHead = FontManager:CreateFontString(colHeadRow, "subtitle", "OVERLAY")
        mapsHead:SetPoint("TOPLEFT", colHeadRow, "TOPLEFT", expPanelOuterW + splitGap, 0)
        mapsHead:SetPoint("TOPRIGHT", colHeadRow, "TOPRIGHT", 0, 0)
        mapsHead:SetJustifyH("LEFT")
        mapsHead:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        mapsHead:SetText((L and L["REMINDER_ZONE_CATALOG_MAPS_LABEL"]) or "Maps")

        local zonePickSplit = CreateFrame("Frame", nil, mapsBody)
        zonePickSplit:SetPoint("TOPLEFT", colHeadRow, "BOTTOMLEFT", 0, -8)
        zonePickSplit:SetPoint("BOTTOMRIGHT", mapsBody, "BOTTOMRIGHT", 0, 0)

        local expPanel = CreateFrame("Frame", nil, zonePickSplit)
        expPanel:SetWidth(expPanelOuterW)
        expPanel:SetPoint("TOPLEFT", zonePickSplit, "TOPLEFT", 0, 0)
        expPanel:SetPoint("BOTTOMLEFT", zonePickSplit, "BOTTOMLEFT", 0, 0)

        local expBarCol = Factory and Factory:CreateScrollBarColumn(expPanel, zbScrollW, 0, 0)
        if expBarCol then
            expBarCol:SetPoint("TOPRIGHT", expPanel, "TOPRIGHT", 0, 0)
            expBarCol:SetPoint("BOTTOMRIGHT", expPanel, "BOTTOMRIGHT", 0, 0)
        end

        local expScroll = Factory and Factory:CreateScrollFrame(expPanel, "UIPanelScrollFrameTemplate", true)
        if not expScroll then
            expScroll = CreateFrame("ScrollFrame", nil, expPanel, "UIPanelScrollFrameTemplate")
        end
        expScroll:SetPoint("TOPLEFT", expPanel, "TOPLEFT", 0, 0)
        if expBarCol then
            expScroll:SetPoint("BOTTOMRIGHT", expBarCol, "BOTTOMLEFT", -4, 0)
            if expScroll.ScrollBar and Factory and Factory.PositionScrollBarInContainer then
                Factory:PositionScrollBarInContainer(expScroll.ScrollBar, expBarCol, 0)
            end
        else
            expScroll:SetPoint("BOTTOMRIGHT", expPanel, "BOTTOMRIGHT", 0, 0)
        end

        local expScrollChild = CreateFrame("Frame", nil, expScroll)
        expScroll:SetScrollChild(expScrollChild)

        local splitLine = zonePickSplit:CreateTexture(nil, "ARTWORK")
        splitLine:SetWidth(1)
        splitLine:SetColorTexture(borderCol[1], borderCol[2], borderCol[3], 0.45)
        splitLine:SetPoint("TOPLEFT", expPanel, "TOPRIGHT", math.floor(splitGap * 0.5), 0)
        splitLine:SetPoint("BOTTOMLEFT", expPanel, "BOTTOMRIGHT", math.ceil(splitGap * 0.5), 0)

        local mapsPanel = CreateFrame("Frame", nil, zonePickSplit)
        mapsPanel:SetPoint("TOPLEFT", zonePickSplit, "TOPLEFT", expPanelOuterW + splitGap, 0)
        mapsPanel:SetPoint("BOTTOMRIGHT", zonePickSplit, "BOTTOMRIGHT", 0, 0)

        local mapsBarCol = Factory and Factory:CreateScrollBarColumn(mapsPanel, zbScrollW, 0, 0)
        if mapsBarCol then
            mapsBarCol:SetPoint("TOPRIGHT", mapsPanel, "TOPRIGHT", 0, 0)
            mapsBarCol:SetPoint("BOTTOMRIGHT", mapsPanel, "BOTTOMRIGHT", 0, 0)
        end

        local zScroll = Factory and Factory:CreateScrollFrame(mapsPanel, "UIPanelScrollFrameTemplate", true)
        if not zScroll then
            zScroll = CreateFrame("ScrollFrame", nil, mapsPanel, "UIPanelScrollFrameTemplate")
        end
        zScroll:SetPoint("TOPLEFT", mapsPanel, "TOPLEFT", 0, 0)
        if mapsBarCol then
            zScroll:SetPoint("BOTTOMRIGHT", mapsBarCol, "BOTTOMLEFT", -4, 0)
            if zScroll.ScrollBar and Factory and Factory.PositionScrollBarInContainer then
                Factory:PositionScrollBarInContainer(zScroll.ScrollBar, mapsBarCol, 0)
            end
        else
            zScroll:SetPoint("BOTTOMRIGHT", mapsPanel, "BOTTOMRIGHT", 0, 0)
        end

        f.zoneCatalogExpScroll = expScroll
        f._catalogExpBtns = {}
        f._catalogExpansionIdx = 1

        local catalogDef = ns.ReminderZoneCatalog
        local expBtnH = 28
        local expBtnGap = 6
        if catalogDef and catalogDef.sections and #catalogDef.sections > 0 then
            for ei = 1, #catalogDef.sections do
                local sec = catalogDef.sections[ei]
                local eb = Factory and Factory:CreateButton(expScrollChild, expInnerW, expBtnH, false)
                if not eb then
                    eb = CreateFrame("Button", nil, expScrollChild, "BackdropTemplate")
                    eb:SetSize(expInnerW, expBtnH)
                    if ApplyVisuals then
                        ApplyVisuals(eb, { 0.12, 0.12, 0.15, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.35 })
                    end
                end
                if ei == 1 then
                    eb:SetPoint("TOPLEFT", expScrollChild, "TOPLEFT", 0, 0)
                else
                    eb:SetPoint("TOPLEFT", f._catalogExpBtns[ei - 1], "BOTTOMLEFT", 0, -expBtnGap)
                end
                eb:SetSize(expInnerW, expBtnH)
                local ebTxt = FontManager:CreateFontString(eb, "small", "OVERLAY")
                ebTxt:SetPoint("LEFT", eb, "LEFT", 8, 0)
                ebTxt:SetPoint("RIGHT", eb, "RIGHT", -8, 0)
                ebTxt:SetJustifyH("LEFT")
                ebTxt:SetMaxLines(2)
                ebTxt:SetWordWrap(true)
                local lk = sec.localeKey or ""
                ebTxt:SetText((L and lk ~= "" and L[lk]) or lk or "?")
                eb:SetScript("OnClick", function()
                    f._catalogExpansionIdx = ei
                    f:RefreshZoneCatalogRows()
                end)
                f._catalogExpBtns[ei] = eb
            end
            local totalExpH = #catalogDef.sections * (expBtnH + expBtnGap) - expBtnGap
            expScrollChild:SetHeight(math.max(totalExpH, 40))
        end

        expScroll:SetScript("OnSizeChanged", function(self)
            local w = self:GetWidth()
            if expScrollChild and w then
                expScrollChild:SetWidth(math.max(40, w))
            end
            if Factory and Factory.UpdateScrollBarVisibility then
                Factory:UpdateScrollBarVisibility(self)
            end
        end)

        local zChild = CreateFrame("Frame", nil, zScroll)
        local zListInitialW = math.max(140, innerW - cardPad * 2 - expPanelOuterW - splitGap - zbScrollW - 12)
        zChild:SetWidth(zListInitialW)
        zScroll:SetScrollChild(zChild)
        f.zoneCatalogScroll = zScroll
        f.zoneCatalogScrollChild = zChild

        zScroll:SetScript("OnSizeChanged", function(self)
            local child = self:GetScrollChild()
            local w = self:GetWidth()
            if child and w then
                local nw = math.max(80, w)
                child:SetWidth(nw)
                local pool = f._zoneCatalogRows
                if pool then
                    for pi = 1, #pool do
                        local rw = pool[pi]
                        if rw and rw:IsShown() then
                            rw:SetWidth(nw)
                        end
                    end
                end
            end
            if Factory and Factory.UpdateScrollBarVisibility then
                Factory:UpdateScrollBarVisibility(self)
            end
        end)

        BindCatalogMouseWheel(expScroll)
        BindCatalogMouseWheel(zScroll)

        local ADD_BTN_W = 52
        local TAG_COL_W = 54
        local ROW_H = 24
        local HDR_H = 22

        local MAX_CAT_ROWS = math.min(680, math.max(120, (catalogDef and catalogDef.GetMaxDisplayRowCount and catalogDef.GetMaxDisplayRowCount()) or 520))
        f._zoneCatalogRows = {}
        for ri = 1, MAX_CAT_ROWS do
            local row = CreateFrame("Frame", nil, zChild)
            row:SetHeight(ROW_H)
            row:SetWidth(zChild:GetWidth())
            row:SetClipsChildren(true)

            row.headerBar = row:CreateTexture(nil, "BACKGROUND")
            row.headerBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.headerBar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
            row.headerBar:SetWidth(3)
            row.headerBar:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5)
            row.headerBar:Hide()

            row.tagFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.tagFs:SetWidth(TAG_COL_W)
            row.tagFs:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.tagFs:SetJustifyH("CENTER")

            row.labelFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.labelFs:SetJustifyH("LEFT")
            row.labelFs:SetWordWrap(false)
            row.labelFs:SetMaxLines(1)

            local addB = Factory and Factory:CreateButton(row, ADD_BTN_W, 22, false)
            if not addB then
                addB = CreateFrame("Button", nil, row, "BackdropTemplate")
                addB:SetSize(ADD_BTN_W, 22)
                if ApplyVisuals then
                    ApplyVisuals(addB, { 0.14, 0.14, 0.17, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5 })
                end
            end
            addB:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            local addTxt = FontManager:CreateFontString(addB, "small", "OVERLAY")
            addTxt:SetPoint("CENTER")
            addTxt:SetText((L and L["REMINDER_ZONE_CATALOG_ADD"]) or "Add")
            row.addBtn = addB
            row.mapID = nil

            row.labelFs:SetPoint("LEFT", row.tagFs, "RIGHT", 6, 0)
            row.labelFs:SetPoint("RIGHT", addB, "LEFT", -8, 0)

            if ri == 1 then
                row:SetPoint("TOPLEFT", zChild, "TOPLEFT", 0, 0)
            else
                row:SetPoint("TOPLEFT", f._zoneCatalogRows[ri - 1], "BOTTOMLEFT", 0, -2)
            end

            addB:SetScript("OnClick", function()
                local mid = row.mapID
                if mid and f.AddCatalogMapId then
                    f:AddCatalogMapId(mid)
                end
            end)
            row:Hide()
            f._zoneCatalogRows[ri] = row
        end

        function f:RefreshZoneCatalogRows()
            local catalogData = ns.ReminderZoneCatalog
            if not catalogData or not catalogData.sections or #catalogData.sections == 0 then return end
            local UICK = ns.UIMapContentKind
            if UICK and UICK.EnsureJournalLoaded then UICK.EnsureJournalLoaded() end
            local Lz = ns.L
            local idx = self._catalogExpansionIdx or 1
            local sec = catalogData.sections[idx]
            if not sec then return end

            local rows = {}
            if catalogData.GetDisplayRowsForSection then
                rows = catalogData.GetDisplayRowsForSection(idx)
            else
                local legacyMaps = sec.maps or {}
                for mi = 1, #legacyMaps do
                    rows[#rows + 1] = { id = legacyMaps[mi], tag = "zone" }
                end
            end

            local nSec = #catalogData.sections
            for j = 1, nSec do
                local ob = self._catalogExpBtns[j]
                if ob and ApplyVisuals then
                    local sel = (j == idx)
                    ApplyVisuals(ob,
                        sel and { COLORS.accent[1] * 0.42, COLORS.accent[2] * 0.42, COLORS.accent[3] * 0.42, 1 } or { 0.12, 0.12, 0.15, 1 },
                        { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], sel and 0.95 or 0.35 })
                end
            end

            local zw = self.zoneCatalogScrollChild and self.zoneCatalogScrollChild:GetWidth() or 320
            local unk = (Lz and Lz["UNKNOWN"]) or "?"

            for ri = 1, #(self._zoneCatalogRows or {}) do
                local row = self._zoneCatalogRows[ri]
                local entry = rows[ri]
                if entry and row then
                    if entry.headerKey then
                        row.mapID = nil
                        row._isCatalogHeader = true
                        if row.addBtn then row.addBtn:Hide() end
                        if row.tagFs then row.tagFs:Hide() end
                        if row.headerBar then row.headerBar:Show() end
                        row.labelFs:ClearAllPoints()
                        row.labelFs:SetPoint("LEFT", row, "LEFT", 12, 0)
                        row.labelFs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                        local hk = entry.headerKey or ""
                        local ht = (Lz and hk ~= "" and Lz[hk]) or hk
                        row.labelFs:SetText("|cffaaaaaa" .. ht .. "|r")
                        row:SetHeight(HDR_H)
                    elseif entry.id then
                        row._isCatalogHeader = false
                        if row.headerBar then row.headerBar:Hide() end
                        if row.tagFs then row.tagFs:Show() end
                        if row.addBtn then row.addBtn:Show() end
                        row.labelFs:ClearAllPoints()
                        row.labelFs:SetPoint("LEFT", row.tagFs, "RIGHT", 6, 0)
                        row.labelFs:SetPoint("RIGHT", row.addBtn, "LEFT", -8, 0)
                        row.mapID = entry.id
                        local nm = entry.displayName or SafeUIMapDisplayName(entry.id)
                        if not nm or nm == "" then nm = unk end
                        if entry.kind and UICK and UICK.FormatPickerTag then
                            row.tagFs:SetText(UICK.FormatPickerTag(entry.kind))
                        elseif entry.tag == "instance" then
                            row.tagFs:SetText("|cffc8b68e" .. ((Lz and Lz["REMINDER_ZONE_CAT_TAG_INSTANCE"]) or "[I]") .. "|r")
                        elseif entry.tag == "related" then
                            row.tagFs:SetText("|cff8eb0ca" .. ((Lz and Lz["REMINDER_ZONE_CAT_TAG_RELATED"]) or "[+]") .. "|r")
                        else
                            row.tagFs:SetText("|cff9ecfae" .. ((Lz and Lz["REMINDER_ZONE_CAT_TAG_ZONE"]) or "[Z]") .. "|r")
                        end
                        local labelMax = 48
                        if zw and zw > 0 then
                            labelMax = math.max(48, math.min(84, math.floor((zw - TAG_COL_W - ADD_BTN_W - 36) / 6.3)))
                        end
                        row.labelFs:SetText(string.format(
                            "|cffffffff%s|r |cff888888— %d|r",
                            TruncatePickerLabel(nm, labelMax),
                            entry.id
                        ))
                        row:SetHeight(ROW_H)
                    end
                    row:SetWidth(zw)
                    row:Show()
                elseif row then
                    row.mapID = nil
                    row._isCatalogHeader = false
                    if row.headerBar then row.headerBar:Hide() end
                    if row.tagFs then row.tagFs:Hide() end
                    if row.addBtn then row.addBtn:Show() end
                    row:Hide()
                end
            end

            local shown = #rows
            if self.zoneCatalogScrollChild then
                local estH = 0
                for si = 1, shown do
                    local e = rows[si]
                    estH = estH + (e and e.headerKey and HDR_H or ROW_H) + 2
                end
                self.zoneCatalogScrollChild:SetHeight(math.max(28, estH))
            end
            if self.zoneCatalogScroll then
                self.zoneCatalogScroll:SetVerticalScroll(0)
            end
            if Factory and Factory.UpdateScrollBarVisibility then
                if self.zoneCatalogScroll then Factory:UpdateScrollBarVisibility(self.zoneCatalogScroll) end
                if self.zoneCatalogExpScroll then Factory:UpdateScrollBarVisibility(self.zoneCatalogExpScroll) end
            end
        end

        function f:AddCatalogMapId(mid)
            mid = tonumber(mid)
            if not mid or mid <= 0 then return end
            self._manualMapIDs = self._manualMapIDs or {}
            for zi = 1, #self._manualMapIDs do
                if self._manualMapIDs[zi] == mid then return end
            end
            self._manualMapIDs[#self._manualMapIDs + 1] = mid
            self._manualMapIDs = UniqueSortedInts(self._manualMapIDs)
            self:RefreshManualMapList()
            if self._zoneGatePlan and self.zoneCheck then
                self.zoneCheck:Enable()
                self.zoneCheck:SetAlpha(1)
                if self.zoneLabel then
                    self.zoneLabel:SetTextColor(0.9, 0.9, 0.9)
                end
            end
            if self.ApplyZoneDependentControlsState then
                self:ApplyZoneDependentControlsState()
            end
        end

        if not catalogDef or not catalogDef.sections or #catalogDef.sections == 0 then
            f.zoneCatalogCard:Hide()
        end

        function f:RefreshMapIdZonePreview()
            if not self.mapEdit or not self.mapIdZonePreview then return end
            local n = tonumber(self.mapEdit:GetText())
            if not n or n <= 0 then
                self.mapIdZonePreview:SetText("")
                self.mapIdZonePreview:Hide()
                return
            end
            local nm = SafeUIMapDisplayName(n)
            local Lz = ns.L
            if nm then
                local prefix = (Lz and Lz["REMINDER_ZONE_NAME_LABEL"]) or "Zone"
                self.mapIdZonePreview:SetText("|cff9eb0ca" .. prefix .. ":|r |cffffffff" .. nm .. "|r |cff888888— "
                    .. tostring(n) .. "|r")
            else
                self.mapIdZonePreview:SetText("|cff888888" .. ((Lz and Lz["REMINDER_ZONE_NAME_UNKNOWN"]) or "Unknown map ID") .. "|r")
            end
            self.mapIdZonePreview:Show()
        end

        mapEdit:SetScript("OnTextChanged", function()
            f:RefreshMapIdZonePreview()
        end)

        f._zoneDetailWidgets = { mapGetIdBtn, mapEditBg, mapEdit, f.mapFieldHint, f.mapIdZonePreview, f.mapsManualCard, f.zoneCatalogCard }

        sc:SetHeight(math.max(720, math.abs(yOff) + 440))

        local btnW, btnH = 128, 32
        local btnGap = 10

        local saveBtn = (Factory and Factory:CreateButton(f, btnW, btnH, false))
            or CreateFrame("Button", nil, f, "BackdropTemplate")
        saveBtn:SetSize(btnW, btnH)
        saveBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -btnGap * 0.5, 12)
        local saveTxt = FontManager:CreateFontString(saveBtn, "body", "OVERLAY")
        saveTxt:SetPoint("CENTER")
        saveTxt:SetText("|cffffffff" .. ((L and L["SAVE"]) or "Save") .. "|r")
        if ApplyVisuals then
            ApplyVisuals(saveBtn,
                { COLORS.accent[1] * 0.35, COLORS.accent[2] * 0.35, COLORS.accent[3] * 0.35, 1 },
                { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.95 })
        end
        f.saveBtn = saveBtn

        local removeBtn = (Factory and Factory:CreateButton(f, btnW, btnH, false))
            or CreateFrame("Button", nil, f, "BackdropTemplate")
        removeBtn:SetSize(btnW, btnH)
        removeBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", btnGap * 0.5, 12)
        local removeTxt = FontManager:CreateFontString(removeBtn, "body", "OVERLAY")
        removeTxt:SetPoint("CENTER")
        removeTxt:SetText("|cffffffff" .. ((L and L["REMOVE_ALERT"]) or "Remove Alert") .. "|r")
        if ApplyVisuals then
            ApplyVisuals(removeBtn, { 0.34, 0.1, 0.1, 1 }, { 0.82, 0.22, 0.22, 1 })
        end
        f.removeBtn = removeBtn

        function f:ApplyZoneDependentControlsState()
            local zc = self.zoneCheck
            local zoneMaster = zc and zc:GetChecked()
            local detailAlpha = zoneMaster and 1 or 0.38
            local hasCat = catalogDef and catalogDef.sections and #catalogDef.sections > 0
            if self.zoneCatalogCard then
                if zoneMaster and hasCat then
                    self.zoneCatalogCard:Show()
                else
                    self.zoneCatalogCard:Hide()
                end
            end
            local widgets = self._zoneDetailWidgets
            if widgets then
                for wi = 1, #widgets do
                    local w = widgets[wi]
                    if w then
                        if zoneMaster then
                            if w.Enable then w:Enable() end
                        else
                            if w.Disable then w:Disable() end
                        end
                        if w.SetAlpha then
                            w:SetAlpha(detailAlpha)
                        end
                    end
                end
            end
            local mrows = self._manualMapRows
            if mrows then
                for ri = 1, #mrows do
                    local row = mrows[ri]
                    local rb = row and row.rmBtn
                    if rb then
                        if zoneMaster then
                            if rb.Enable then rb:Enable() end
                        else
                            if rb.Disable then rb:Disable() end
                        end
                    end
                end
            end
            if self.RefreshManualMapList then
                self:RefreshManualMapList()
            end
            if zoneMaster and hasCat and self.RefreshZoneCatalogRows then
                self:RefreshZoneCatalogRows()
            end
            if Factory and self.reminderScrollFrame and Factory.UpdateScrollBarVisibility then
                Factory:UpdateScrollBarVisibility(self.reminderScrollFrame)
            end
        end

        reminderDialog = f
    end

    local f = reminderDialog
    local displayName = (addon.GetResolvedPlanName and addon:GetResolvedPlanName(plan))
        or plan.name
        or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")

    local PCF = ns.UI_PlanCardFactory
    local typeAtlas = PCF and PCF.TYPE_ICONS and plan.type and PCF.TYPE_ICONS[plan.type]
    if typeAtlas and f.planTypeTex and f.planTypeBadge then
        local ok = pcall(function()
            f.planTypeTex:SetAtlas(typeAtlas, false)
        end)
        if ok then
            f.planTypeBadge:Show()
        else
            f.planTypeBadge:Hide()
        end
    elseif f.planTypeBadge then
        f.planTypeBadge:Hide()
    end

    local titleLeft = (f.planTypeBadge and f.planTypeBadge:IsShown() and f.planTypeBadge) or f.planHornIcon or f.planRow
    f.planTitleFs:ClearAllPoints()
    f.planTitleFs:SetPoint("TOP", f.planRow, "TOP", 0, -4)
    f.planTitleFs:SetPoint("BOTTOM", f.planRow, "BOTTOM", 0, 4)
    f.planTitleFs:SetPoint("LEFT", titleLeft, "RIGHT", 8, 0)

    local pts = plan.points
    if pts and tonumber(pts) and f.planPointsFs then
        f.planPointsFs:Show()
        local pf = (L and L["ACHIEVEMENT_POINTS_FORMAT"]) or (L and L["POINTS_FORMAT"]) or "%d pts"
        f.planPointsFs:SetText(string.format(pf, tonumber(pts)))
        f.planTitleFs:SetPoint("RIGHT", f.planPointsFs, "LEFT", -8, 0)
    else
        if f.planPointsFs then
            f.planPointsFs:Hide()
        end
        f.planTitleFs:SetPoint("RIGHT", f.planRow, "RIGHT", -4, 0)
    end
    f.planTitleFs:SetJustifyH("LEFT")
    f.planTitleFs:SetText("|cffffffff" .. displayName .. "|r")

    local function SyncThemedCheck(cb, checked)
        if not cb then return end
        local v = checked and true or false
        cb:SetChecked(v)
        if cb.innerDot then
            cb.innerDot:SetShown(v)
        end
    end

    f._currentPlanID = planID
    f._manualMapIDs = {}
    local ze = FindTriggerEntry(r, KIND.ZONE_ENTER)
    if ze and type(ze.manualMapIDs) == "table" then
        for i = 1, #ze.manualMapIDs do
            f._manualMapIDs[#f._manualMapIDs + 1] = tonumber(ze.manualMapIDs[i])
        end
        f._manualMapIDs = UniqueSortedInts(f._manualMapIDs)
    end

    local ie = FindTriggerEntry(r, KIND.INSTANCE_ENTER)
    f._preserveOnInstanceEnter = r.onInstanceEnter == true
    f._preserveInstanceReminder = nil
    if ie and tonumber(ie.instanceID) then
        f._preserveInstanceReminder = {
            instanceID = tonumber(ie.instanceID),
            difficultyID = ie.difficultyID ~= nil and tonumber(ie.difficultyID) or nil,
        }
    end

    local hintsOk = PlanHasZoneSourceHints and PlanHasZoneSourceHints(plan) or false
    f._hintsOkForPlan = hintsOk
    f._zoneGatePlan = plan

    local function RefreshZoneCheckboxGate()
        f.zoneCheck:Enable()
        f.zoneCheck:SetAlpha(1)
        f.zoneLabel:SetTextColor(0.9, 0.9, 0.9)
        if f.ApplyZoneDependentControlsState then
            f:ApplyZoneDependentControlsState()
        end
    end

    local function CommitManualMapId()
        local n = tonumber(f.mapEdit:GetText())
        if not n or n <= 0 then return end
        if NormalizeZoneReminderUIMapID then
            local canon = NormalizeZoneReminderUIMapID(n)
            if canon then n = canon end
        end
        f._manualMapIDs[#f._manualMapIDs + 1] = n
        f._manualMapIDs = UniqueSortedInts(f._manualMapIDs)
        f.mapEdit:SetText("")
        if f.RefreshManualMapList then
            f:RefreshManualMapList()
        end
        RefreshZoneCheckboxGate()
        if f.RefreshMapIdZonePreview then
            f:RefreshMapIdZonePreview()
        end
    end

    if f.RefreshManualMapList then
        f:RefreshManualMapList()
    end
    if f.RefreshZoneCatalogRows and ns.ReminderZoneCatalog and ns.ReminderZoneCatalog.sections and #ns.ReminderZoneCatalog.sections > 0 then
        f:RefreshZoneCatalogRows()
    end

    f.mapGetIdBtn:SetScript("OnClick", function()
        if not C_Map or not C_Map.GetBestMapForUnit then return end
        local ok, mid = pcall(C_Map.GetBestMapForUnit, "player")
        if not ok or mid == nil then return end
        if issecretvalue and issecretvalue(mid) then return end
        mid = tonumber(mid)
        if mid and mid > 0 and NormalizeZoneReminderUIMapID then
            local canon = NormalizeZoneReminderUIMapID(mid)
            if canon then mid = canon end
        end
        if mid and mid > 0 then
            f.mapEdit:SetText(tostring(mid))
        end
        if f.RefreshMapIdZonePreview then
            f:RefreshMapIdZonePreview()
        end
    end)

    if f.mapEdit then
        f.mapEdit:SetScript("OnEnterPressed", function(self)
            CommitManualMapId()
            self:ClearFocus()
        end)
    end

    SyncThemedCheck(f.dailyCheck, r.onDailyLogin or false)
    SyncThemedCheck(f.weeklyCheck, r.onWeeklyReset or false)

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
    SyncThemedCheck(f.days5Check, has5)
    SyncThemedCheck(f.days3Check, has3)
    SyncThemedCheck(f.days1Check, has1)

    SyncThemedCheck(f.zoneCheck, r.onZoneEnter == true)
    f.zoneCheck:Enable()
    f.zoneCheck:SetAlpha(1)
    f.zoneLabel:SetTextColor(0.9, 0.9, 0.9)

    local prof = addon.db and addon.db.profile

    if f.ApplyZoneDependentControlsState then
        f:ApplyZoneDependentControlsState()
    end

    f.saveBtn:SetScript("OnClick", function()
        local days = {}
        if f.days5Check:GetChecked() then days[#days + 1] = 5 end
        if f.days3Check:GetChecked() then days[#days + 1] = 3 end
        if f.days1Check:GetChecked() then days[#days + 1] = 1 end
        table.sort(days, function(a, b) return a > b end)

        local zoneOn = f.zoneCheck:GetChecked() == true
        local zoneHintsSaved = (zoneOn and hintsOk) or false

        local settings = {
            onDailyLogin = f.dailyCheck:GetChecked() or false,
            onWeeklyReset = f.weeklyCheck:GetChecked() or false,
            onMonthlyLogin = r.onMonthlyLogin or false,
            daysBeforeReset = days,
            onZoneEnter = zoneOn,
            zoneUseSourceHints = zoneHintsSaved,
            zoneManualMapIDs = (function()
                if zoneOn then
                    local pending = tonumber(f.mapEdit:GetText())
                    if pending and pending > 0 then
                        local dup = false
                        for zi = 1, #(f._manualMapIDs or {}) do
                            if f._manualMapIDs[zi] == pending then
                                dup = true
                                break
                            end
                        end
                        if not dup then
                            f._manualMapIDs[#f._manualMapIDs + 1] = pending
                            f._manualMapIDs = UniqueSortedInts(f._manualMapIDs)
                        end
                    end
                end
                local z = {}
                for zi = 1, #(f._manualMapIDs or {}) do
                    z[zi] = f._manualMapIDs[zi]
                end
                return z
            end)(),
            onInstanceEnter = f._preserveOnInstanceEnter and true or false,
            instanceReminder = nil,
        }
        if settings.onInstanceEnter and f._preserveInstanceReminder then
            settings.instanceReminder = {
                instanceID = f._preserveInstanceReminder.instanceID,
                difficultyID = f._preserveInstanceReminder.difficultyID,
            }
        end

        addon:SetPlanReminder(f._currentPlanID, settings)

        if prof then
            prof.plansReminderFocusPlanID = nil
        end

        f:Hide()
    end)

    f.removeBtn:SetScript("OnClick", function()
        addon:RemovePlanReminder(f._currentPlanID)
        f:Hide()
    end)

    if f.reminderScrollFrame and f.reminderScrollChild then
        local sf = f.reminderScrollFrame
        local w = sf:GetWidth()
        if w and w > 0 then
            f.reminderScrollChild:SetWidth(w)
        end
        local Fact = ns.UI and ns.UI.Factory
        if Fact and Fact.UpdateScrollBarVisibility then
            Fact:UpdateScrollBarVisibility(sf)
        end
        if f._layoutReminderGrids then
            f._layoutReminderGrids()
        end
    end

    f:Show()
end