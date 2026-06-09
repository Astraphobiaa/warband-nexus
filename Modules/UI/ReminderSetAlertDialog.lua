--[[ To-Do plan reminder "Set Alert" dialog (view layer). Data entry points: ns.ReminderServiceBridge. ]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

ns.ReminderSetAlertDialog = ns.ReminderSetAlertDialog or {}

--[[ WN_FACTORY: Loads after SharedWidgets / WindowFactory in `WarbandNexus.toc`.
     `Factory` is resolved inside `Show` on first build (runtime).

     Remaining intentional raw `CreateFrame`: modal root `f`, header chrome, ScrollFrame ScrollChild scaffold,
     nested grid/card layout Frames, Blizzard `EditBox` fallback, UIPanelScrollFrameTemplate-backed inner scroll hosts.
]]

local reminderDialog = nil
local H = ns.ReminderSetAlertDialogHelpers

function ns.ReminderSetAlertDialog.Show(addon, planID)
    local B = ns.ReminderServiceBridge
    if not B then return end
    local EnsureReminderField = B.EnsureReminderField
    local FindTriggerEntry = B.FindTriggerEntry
    local KIND = B.KIND
    local CopyQuestIDList = B.CopyQuestIDList
    local CopyEventKeysList = B.CopyEventKeysList
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
        local Factory = ns.UI.Factory -- valid at first dialog build only (SharedWidgets already loaded).
        local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
        local UI_SP = ns.UI_SPACING or {}
        local sideInset = UI_SP.SIDE_MARGIN or 14
        local afterEl = UI_SP.AFTER_ELEMENT or 8
        local scrollBarW = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26
        local rowGap = 22
        local zoneSubInset = sideInset + (UI_SP.SUBROW_EXTRA_INDENT or 12)
        local footerH = 52
        -- Wide enough for expansion list + map names + Add column (avoid clipping under scroll bars).
        local dialogW, dialogH = 960, 820
        local RD = {
            cardPad = 10,
            sectionGap = 8,
            whenCardH = 76,
            locationBaseH = 120,
            questEventsMinH = 240,
            questTrackBaseH = 108,
            questHeaderH = 22,
            questOptsH = 88,
            questListChromeH = 54,
            questListScrollMinH = 100,
            worldEventChromeH = 38,
            worldEventScrollMinH = 80,
            selectedBlockMinH = 36,
            catalogMinH = 200,
            zoneCatalogShare = 0.40,
            questCardShare = 0.55,
            expColW = 212,
            splitGap = 10,
            addBtnW = 64,
            tagColW = 56,
            catalogRowH = 26,
            catalogHdrH = 22,
            compactOptH = 28,
        }
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

        local rdShell = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
        local rdInset = rdShell.FRAME_CONTENT_INSET or 2
        local rdHdrH = rdShell.HEADER_BAR_HEIGHT or 40
        local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
        header:SetHeight(rdHdrH)
        header:SetPoint("TOPLEFT", rdInset, -rdInset)
        header:SetPoint("TOPRIGHT", -rdInset, -rdInset)
        header:SetFrameLevel(f:GetFrameLevel() + 6)
        if ApplyVisuals then
            ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.55})
        end

        local closeBtn = Factory:CreateButton(header, 28, 28, false)
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
        bodyHost:SetScript("OnSizeChanged", function()
            if f.LayoutDialogHeights then
                f:LayoutDialogHeights()
            end
        end)

        local innerW = math.max(120, dialogW - sideInset * 2 - 8)
        local tabBarH = 32
        local tabBar = CreateFrame("Frame", nil, bodyHost)
        tabBar:SetPoint("TOPLEFT", bodyHost, "TOPLEFT", 0, 0)
        tabBar:SetPoint("TOPRIGHT", bodyHost, "TOPRIGHT", 0, 0)
        tabBar:SetHeight(tabBarH)
        f.tabBar = tabBar

        local alertTabDefs = {
            { key = "schedule", labelKey = "SET_ALERT_SECTION_SCHEDULE", fallback = "Login & Resets" },
            { key = "zone",     labelKey = "SET_ALERT_SECTION_LOCATION", fallback = "Zone & Instance" },
            { key = "quests",   labelKey = "SET_ALERT_SECTION_QUESTS", fallback = "Quests & Events" },
        }
        f._alertTabKeys = {}
        f._alertTabBtns = {}
        for ti = 1, #alertTabDefs do
            f._alertTabKeys[ti] = alertTabDefs[ti].key
        end

        local function LayoutAlertTabButtons()
            local rw = tabBar:GetWidth()
            if not rw or rw < 180 then return end
            local gap = 6
            local n = #alertTabDefs
            local bw = math.floor((rw - gap * (n - 1)) / n)
            for bi = 1, n do
                local b = f._alertTabBtns[bi]
                if b then
                    b:SetSize(math.max(80, bw), tabBarH - 4)
                    b:ClearAllPoints()
                    if bi == 1 then
                        b:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
                    else
                        b:SetPoint("LEFT", f._alertTabBtns[bi - 1], "RIGHT", gap, 0)
                    end
                end
            end
        end
        tabBar:SetScript("OnSizeChanged", LayoutAlertTabButtons)

        for ti = 1, #alertTabDefs do
            (function(tabDef, tabIdx)
                local tb = Factory:CreateButton(tabBar, 120, tabBarH - 4, false)
                if not tb then
                    tb = CreateFrame("Button", nil, tabBar, "BackdropTemplate")
                    tb:SetSize(120, tabBarH - 4)
                end
                tb.labelFs = FontManager:CreateFontString(tb, "small", "OVERLAY")
                tb.labelFs:SetPoint("CENTER")
                tb.labelFs:SetText((L and L[tabDef.labelKey]) or tabDef.fallback)
                tb:SetScript("OnClick", function()
                    if f.SelectAlertTab then
                        f:SelectAlertTab(tabDef.key)
                    end
                end)
                f._alertTabBtns[tabIdx] = tb
            end)(alertTabDefs[ti], ti)
        end
        LayoutAlertTabButtons()
        f.LayoutAlertTabButtons = LayoutAlertTabButtons

        local contentHost = CreateFrame("Frame", nil, bodyHost)
        contentHost:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
        contentHost:SetPoint("BOTTOMRIGHT", bodyHost, "BOTTOMRIGHT", 0, 0)
        contentHost:SetClipsChildren(true)
        f.contentHost = contentHost

        local function MakeTabPanel(name)
            local panel = CreateFrame("Frame", nil, contentHost)
            panel:SetPoint("TOPLEFT", contentHost, "TOPLEFT", 0, 0)
            panel:SetPoint("BOTTOMRIGHT", contentHost, "BOTTOMRIGHT", 0, 0)
            panel:SetClipsChildren(true)
            panel:Hide()
            return panel
        end

        f.panelSchedule = MakeTabPanel("schedule")
        f.panelZone = MakeTabPanel("zone")
        f.panelQuests = MakeTabPanel("quests")
        f._alertTabPanels = {
            schedule = f.panelSchedule,
            zone = f.panelZone,
            quests = f.panelQuests,
        }

        function f:SelectAlertTab(tabKey)
            tabKey = tabKey or "schedule"
            self._activeAlertTab = tabKey
            local panels = self._alertTabPanels
            if panels then
                for key, panel in pairs(panels) do
                    if panel then
                        if key == tabKey then panel:Show() else panel:Hide() end
                    end
                end
            end
            local keys = self._alertTabKeys or {}
            local btns = self._alertTabBtns or {}
            for bi = 1, #keys do
                local b = btns[bi]
                local sel = (keys[bi] == tabKey)
                if b and b.labelFs then
                    if ApplyVisuals then
                        ApplyVisuals(b,
                            sel and { COLORS.accent[1] * 0.42, COLORS.accent[2] * 0.42, COLORS.accent[3] * 0.42, 1 }
                                or { 0.12, 0.12, 0.15, 1 },
                            { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], sel and 0.95 or 0.35 })
                    end
                end
            end
            if tabKey == "zone" or tabKey == "quests" then
                if self.ApplyAlertLocationQuestMutex then self:ApplyAlertLocationQuestMutex() end
            end
            if tabKey == "zone" then
                if self.ApplyZoneDependentControlsState then self:ApplyZoneDependentControlsState() end
                if not self._zoneCatalogPrimed and self.RefreshZoneCatalogRows then
                    self._zoneCatalogPrimed = true
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            if self:IsShown() and self._activeAlertTab == "zone" and self.RefreshZoneCatalogRows then
                                self:RefreshZoneCatalogRows()
                            end
                        end)
                    else
                        self:RefreshZoneCatalogRows()
                    end
                end
            elseif tabKey == "quests" then
                if self.ApplyQuestTrackControlsState then self:ApplyQuestTrackControlsState() end
            end
            if self.LayoutDialogHeights then self:LayoutDialogHeights() end
        end
        f.SelectAlertTab = f.SelectAlertTab

        local function AttachOptionLabel(fs, anchorWidget, textStr, rightParent)
            rightParent = rightParent or anchorWidget:GetParent() or contentHost
            fs:SetPoint("LEFT", anchorWidget, "RIGHT", 8, 0)
            fs:SetPoint("RIGHT", rightParent, "RIGHT", 0, 0)
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

        function f:ShowMutexTooltip(owner, tipText)
            if not owner or not tipText or tipText == "" then return end
            if ns.UI_SetGameTooltipSmartOwner then
                ns.UI_SetGameTooltipSmartOwner(owner, 0, 0)
            else
                GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            end
            -- Midnight: SetText(text [, color, alpha, wrap]) — not legacy r,g,b,wrap floats.
            GameTooltip:SetText(tipText)
            GameTooltip:Show()
        end

        local function WireMutexHoverTip(widget, tipField)
            if not widget or widget._mutexHoverWired then return end
            widget._mutexHoverWired = true
            widget:EnableMouse(true)
            widget:HookScript("OnEnter", function(self)
                local tip = f[tipField]
                if not tip or tip == "" then return end
                f:ShowMutexTooltip(self, tip)
            end)
            widget:HookScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end

        local function WireMutexTipHost(host)
            if not host or host._mutexTipHooked then return end
            host._mutexTipHooked = true
            host:SetScript("OnEnter", function(self)
                local tip = self._mutexBlockTip
                if not tip or tip == "" then return end
                f:ShowMutexTooltip(self, tip)
            end)
            host:HookScript("OnLeave", function()
                GameTooltip:Hide()
            end)
        end

        local function CreateMutexTipHost(parent, leftWidget, rightWidget)
            if not parent or not leftWidget or not rightWidget then return nil end
            local host = CreateFrame("Frame", nil, parent)
            host:SetPoint("TOPLEFT", leftWidget, "TOPLEFT", -4, 4)
            host:SetPoint("BOTTOMRIGHT", rightWidget, "BOTTOMRIGHT", 4, -4)
            host:Hide()
            host:EnableMouse(false)
            WireMutexTipHost(host)
            return host
        end

        function f:RaiseMutexTipHost(host)
            if not host then return end
            if host.SetFrameStrata then
                host:SetFrameStrata("TOOLTIP")
            end
            if host.SetFrameLevel then
                host:SetFrameLevel(200)
            end
            if host.Raise then
                host:Raise()
            end
        end

        function f:SetAlertMutexTipHost(host, tipText)
            if not host then return end
            if tipText and tipText ~= "" then
                host._mutexBlockTip = tipText
                host:Show()
                host:EnableMouse(true)
                self:RaiseMutexTipHost(host)
            else
                host._mutexBlockTip = nil
                host:Hide()
                host:EnableMouse(false)
            end
        end

        local cardPad = RD.cardPad
        local bgCardCol = COLORS.bgCard or { 0.08, 0.08, 0.10, 1 }

        local function StyleCard(card)
            if ApplyVisuals then
                ApplyVisuals(card,
                    { bgCardCol[1], bgCardCol[2], bgCardCol[3], bgCardCol[4] or 1 },
                    { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
            end
        end

        function f:LayoutDialogHeights()
            local tab = self._activeAlertTab or "schedule"

            if tab == "zone" and self.panelZone and self.locationCard then
                self.locationCard:ClearAllPoints()
                self.locationCard:SetPoint("TOPLEFT", self.panelZone, "TOPLEFT", 0, 0)
                self.locationCard:SetPoint("TOPRIGHT", self.panelZone, "TOPRIGHT", 0, 0)
                if self.zoneCatalogCard and self.zoneCatalogCard:IsShown() then
                    self.zoneCatalogCard:ClearAllPoints()
                    self.zoneCatalogCard:SetPoint("TOPLEFT", self.locationCard, "BOTTOMLEFT", 0, -8)
                    self.zoneCatalogCard:SetPoint("BOTTOMRIGHT", self.panelZone, "BOTTOMRIGHT", 0, 0)
                end
            end

            if tab == "quests" and self.panelQuests and self.questTrackCard then
                self.questTrackCard:ClearAllPoints()
                self.questTrackCard:SetPoint("TOPLEFT", self.panelQuests, "TOPLEFT", 0, 0)
                self.questTrackCard:SetPoint("TOPRIGHT", self.panelQuests, "TOPRIGHT", 0, 0)
                if self.questCatalogCard and self.questCatalogCard:IsShown() then
                    self.questCatalogCard:ClearAllPoints()
                    self.questCatalogCard:SetPoint("TOPLEFT", self.questTrackCard, "BOTTOMLEFT", 0, -8)
                    self.questCatalogCard:SetPoint("BOTTOMRIGHT", self.panelQuests, "BOTTOMRIGHT", 0, 0)
                end
            end

            if self.LayoutZoneCatalogSplit then self:LayoutZoneCatalogSplit() end
            if self.LayoutQuestCatalogSplit then self:LayoutQuestCatalogSplit() end
            if Factory.UpdateScrollBarVisibility then
                if self.questCatalogScroll then Factory:UpdateScrollBarVisibility(self.questCatalogScroll) end
                if self.zoneCatalogScroll then Factory:UpdateScrollBarVisibility(self.zoneCatalogScroll) end
            end
        end

        local whenCard = CreateFrame("Frame", nil, f.panelSchedule)
        whenCard:SetPoint("TOPLEFT", f.panelSchedule, "TOPLEFT", 0, 0)
        whenCard:SetPoint("TOPRIGHT", f.panelSchedule, "TOPRIGHT", 0, 0)
        whenCard:SetHeight(RD.whenCardH)
        StyleCard(whenCard)
        f.whenCard = whenCard

        local whenInner = CreateFrame("Frame", nil, whenCard)
        whenInner:SetPoint("TOPLEFT", whenCard, "TOPLEFT", cardPad, -cardPad)
        whenInner:SetPoint("BOTTOMRIGHT", whenCard, "BOTTOMRIGHT", -cardPad, cardPad)

        local secSchedule = FontManager:CreateFontString(whenInner, "subtitle", "OVERLAY")
        secSchedule:SetPoint("TOPLEFT", whenInner, "TOPLEFT", 0, 0)
        secSchedule:SetPoint("TOPRIGHT", whenInner, "TOPRIGHT", 0, 0)
        secSchedule:SetJustifyH("LEFT")
        secSchedule:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        secSchedule:SetText((L and L["SET_ALERT_SECTION_SCHEDULE"]) or "Login & Resets")

        local whenOptsRow = CreateFrame("Frame", nil, whenInner)
        whenOptsRow:SetPoint("TOPLEFT", secSchedule, "BOTTOMLEFT", 0, -8)
        whenOptsRow:SetPoint("TOPRIGHT", secSchedule, "BOTTOMRIGHT", 0, -8)
        whenOptsRow:SetPoint("BOTTOMLEFT", whenInner, "BOTTOMLEFT", 0, 0)
        whenOptsRow:SetPoint("BOTTOMRIGHT", whenInner, "BOTTOMRIGHT", 0, 0)
        whenOptsRow:SetHeight(RD.compactOptH)
        f.whenOptsRow = whenOptsRow

        local whenOptCols = {}
        for wi = 1, 3 do
            whenOptCols[wi] = CreateFrame("Frame", nil, whenOptsRow)
        end

        local function LayoutWhenOptsRow()
            local rw = whenOptsRow:GetWidth()
            local rh = whenOptsRow:GetHeight()
            if not rw or rw < 200 or not rh or rh < 8 then return end
            local gap = 8
            local dayColW = math.min(220, math.max(150, rw * 0.38))
            local remW = rw - dayColW - gap * 2
            local simpleW = remW / 2
            whenOptCols[1]:ClearAllPoints()
            whenOptCols[1]:SetPoint("TOPLEFT", whenOptsRow, "TOPLEFT", 0, 0)
            whenOptCols[1]:SetSize(simpleW, rh)
            whenOptCols[2]:ClearAllPoints()
            whenOptCols[2]:SetPoint("TOPLEFT", whenOptsRow, "TOPLEFT", simpleW + gap, 0)
            whenOptCols[2]:SetSize(simpleW, rh)
            whenOptCols[3]:ClearAllPoints()
            whenOptCols[3]:SetPoint("TOPLEFT", whenOptsRow, "TOPLEFT", simpleW + gap + simpleW + gap, 0)
            whenOptCols[3]:SetSize(dayColW, rh)
        end

        whenOptsRow:SetScript("OnSizeChanged", LayoutWhenOptsRow)

        local function AddCompactWhenOpt(col, labelText, assignKey)
            local cb = CreateThemedCheckbox(col, false)
            cb:SetPoint("LEFT", col, "LEFT", 0, 0)
            local lbl = FontManager:CreateFontString(col, "small", "OVERLAY")
            lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
            lbl:SetPoint("RIGHT", col, "RIGHT", -2, 0)
            lbl:SetJustifyH("LEFT")
            lbl:SetMaxLines(1)
            lbl:SetWordWrap(false)
            lbl:SetText(labelText)
            lbl:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
            WireLabelToggle(lbl, cb)
            f[assignKey] = cb
        end

        AddCompactWhenOpt(whenOptCols[1], (L and L["REMINDER_OPT_DAILY_SHORT"]) or "Daily", "dailyCheck")
        AddCompactWhenOpt(whenOptCols[2], (L and L["REMINDER_OPT_WEEKLY_SHORT"]) or "Weekly", "weeklyCheck")

        local daysCol = whenOptCols[3]
        f.daysBeforeCheck = CreateThemedCheckbox(daysCol, false)
        f.daysBeforeCheck:SetPoint("LEFT", daysCol, "LEFT", 0, 0)

        local daysEditBg = Factory:CreateContainer(daysCol, 40, 24)
        if not daysEditBg then
            daysEditBg = CreateFrame("Frame", nil, daysCol)
            daysEditBg:SetSize(40, 24)
        end
        daysEditBg:SetPoint("LEFT", f.daysBeforeCheck, "RIGHT", 6, 0)
        if ApplyVisuals then
            ApplyVisuals(daysEditBg, { 0.08, 0.08, 0.10, 1 }, { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end
        daysEditBg:EnableMouse(true)

        local daysBeforeEdit = Factory:CreateEditBox(daysEditBg)
        if not daysBeforeEdit then
            daysBeforeEdit = CreateFrame("EditBox", nil, daysEditBg, "BackdropTemplate")
            daysBeforeEdit:SetFontObject(GameFontHighlightSmall)
            daysBeforeEdit:SetTextInsets(4, 4, 1, 1)
        end
        daysBeforeEdit:SetPoint("LEFT", daysEditBg, "LEFT", 4, 0)
        daysBeforeEdit:SetPoint("RIGHT", daysEditBg, "RIGHT", -4, 0)
        daysBeforeEdit:SetHeight(20)
        daysBeforeEdit:SetNumeric(true)
        daysBeforeEdit:SetMaxLetters(2)
        daysBeforeEdit:SetText("3")
        daysBeforeEdit:SetTextColor(1, 1, 1, 1)
        daysBeforeEdit:SetAutoFocus(false)
        daysEditBg:SetScript("OnMouseDown", function()
            daysBeforeEdit:SetFocus()
        end)
        f.daysBeforeEdit = daysBeforeEdit

        local daysSuffix = FontManager:CreateFontString(daysCol, "small", "OVERLAY")
        daysSuffix:SetPoint("LEFT", daysEditBg, "RIGHT", 6, 0)
        daysSuffix:SetPoint("RIGHT", daysCol, "RIGHT", -2, 0)
        daysSuffix:SetJustifyH("LEFT")
        daysSuffix:SetMaxLines(1)
        daysSuffix:SetWordWrap(false)
        daysSuffix:SetText((L and L["REMINDER_OPT_DAYS_BEFORE_SUFFIX"]) or "days before reset")
        daysSuffix:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
        WireLabelToggle(daysSuffix, f.daysBeforeCheck)

        local function SyncDaysBeforeEditEnabled()
            local on = f.daysBeforeCheck and f.daysBeforeCheck:GetChecked()
            if f.daysBeforeEdit then
                if on then
                    if f.daysBeforeEdit.Enable then f.daysBeforeEdit:Enable() end
                    f.daysBeforeEdit:SetAlpha(1)
                else
                    if f.daysBeforeEdit.Disable then f.daysBeforeEdit:Disable() end
                    f.daysBeforeEdit:SetAlpha(0.45)
                end
            end
            if daysEditBg then
                daysEditBg:SetAlpha(on and 1 or 0.45)
            end
        end
        f.SyncDaysBeforeEditEnabled = SyncDaysBeforeEditEnabled
        f.daysBeforeCheck:HookScript("OnClick", SyncDaysBeforeEditEnabled)

        f._layoutReminderGrids = LayoutWhenOptsRow
        LayoutWhenOptsRow()
        SyncDaysBeforeEditEnabled()

        local locationCard = CreateFrame("Frame", nil, f.panelZone)
        locationCard:SetPoint("TOPLEFT", f.panelZone, "TOPLEFT", 0, 0)
        locationCard:SetPoint("TOPRIGHT", f.panelZone, "TOPRIGHT", 0, 0)
        locationCard:SetHeight(RD.locationBaseH)
        StyleCard(locationCard)
        f.locationCard = locationCard

        local locInner = CreateFrame("Frame", nil, locationCard)
        locInner:SetPoint("TOPLEFT", locationCard, "TOPLEFT", cardPad, -cardPad)
        locInner:SetPoint("BOTTOMRIGHT", locationCard, "BOTTOMRIGHT", -cardPad, cardPad)
        f.locationInner = locInner

        local secLocation = FontManager:CreateFontString(locInner, "subtitle", "OVERLAY")
        secLocation:SetPoint("TOPLEFT", locInner, "TOPLEFT", 0, 0)
        secLocation:SetPoint("TOPRIGHT", locInner, "TOPRIGHT", 0, 0)
        secLocation:SetJustifyH("LEFT")
        secLocation:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        secLocation:SetText((L and L["SET_ALERT_SECTION_LOCATION"]) or "Zone & Instance")

        local zoneCheck = CreateThemedCheckbox(locInner, false)
        zoneCheck:SetPoint("TOPLEFT", secLocation, "BOTTOMLEFT", 0, -8)
        local zoneLabel = FontManager:CreateFontString(locInner, "body", "OVERLAY")
        zoneLabel:SetPoint("LEFT", zoneCheck, "RIGHT", 8, 0)
        zoneLabel:SetPoint("RIGHT", locInner, "RIGHT", 0, 0)
        zoneLabel:SetJustifyH("LEFT")
        zoneLabel:SetWordWrap(true)
        zoneLabel:SetMaxLines(2)
        zoneLabel:SetText((L and L["REMINDER_OPT_ZONE_ENTER_MATCHING"]) or (L and L["REMINDER_OPT_ZONE"]) or "Remind me when enter to matching zone")
        zoneLabel:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
        zoneLabel:EnableMouse(true)
        if zoneLabel.RegisterForClicks then
            zoneLabel:RegisterForClicks("LeftButtonUp")
        end
        zoneLabel:SetScript("OnMouseUp", function(_, btn)
            if btn ~= "LeftButton" then return end
            if f._zoneMutexTipText then return end
            zoneCheck:Click()
        end)
        f.zoneCheck = zoneCheck
        f.zoneLabel = zoneLabel
        f.zoneMutexNotice = FontManager:CreateFontString(locInner, "small", "OVERLAY")
        f.zoneMutexNotice:SetPoint("TOPLEFT", zoneCheck, "BOTTOMLEFT", 0, -6)
        f.zoneMutexNotice:SetPoint("TOPRIGHT", locInner, "TOPRIGHT", 0, -6)
        f.zoneMutexNotice:SetJustifyH("LEFT")
        f.zoneMutexNotice:SetWordWrap(true)
        f.zoneMutexNotice:SetMaxLines(2)
        f.zoneMutexNotice:SetTextColor(0.92, 0.72, 0.42)
        f.zoneMutexNotice:Hide()
        WireMutexHoverTip(zoneLabel, "_zoneMutexTipText")
        WireMutexHoverTip(zoneCheck, "_zoneMutexTipText")

        zoneCheck:HookScript("OnClick", function()
            if f._zoneMutexTipText then
                f:SyncThemedCheck(f.zoneCheck, false)
                return
            end
            f._locationQuestMutexSide = "zone"
            if f.ApplyAlertLocationQuestMutex then f:ApplyAlertLocationQuestMutex() end
            if f.ApplyZoneDependentControlsState then f:ApplyZoneDependentControlsState() end
            if f.ApplyQuestTrackControlsState then f:ApplyQuestTrackControlsState() end
        end)
        f.zoneMutexTipHost = CreateMutexTipHost(locInner, zoneCheck, zoneLabel)
        f:RaiseMutexTipHost(f.zoneMutexTipHost)

        f.selectedZonesBlock = CreateFrame("Frame", nil, locInner)
        f.selectedZonesBlock:SetPoint("TOPLEFT", zoneCheck, "BOTTOMLEFT", 0, -10)
        f.selectedZonesBlock:SetPoint("TOPRIGHT", locInner, "TOPRIGHT", 0, -10)

        local selectedToolbar = CreateFrame("Frame", nil, f.selectedZonesBlock)
        selectedToolbar:SetPoint("TOPLEFT", f.selectedZonesBlock, "TOPLEFT", 0, 0)
        selectedToolbar:SetPoint("TOPRIGHT", f.selectedZonesBlock, "TOPRIGHT", 0, 0)
        selectedToolbar:SetHeight(28)
        f.selectedToolbar = selectedToolbar

        f.mapsManualTitle = FontManager:CreateFontString(selectedToolbar, "subtitle", "OVERLAY")
        f.mapsManualTitle:SetPoint("LEFT", selectedToolbar, "LEFT", 0, 0)
        f.mapsManualTitle:SetPoint("RIGHT", selectedToolbar, "CENTER", -100, 0)
        f.mapsManualTitle:SetJustifyH("LEFT")
        f.mapsManualTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        f.mapsManualTitle:SetText(string.format(
            (L and L["REMINDER_ZONE_SELECTED_COUNT"]) or (L and L["REMINDER_ZONE_MANUAL_COUNT"]) or "Selected zones (%d)",
            0
        ))

        local mapIdRow = CreateFrame("Frame", nil, selectedToolbar)
        mapIdRow:SetPoint("RIGHT", selectedToolbar, "RIGHT", 0, 0)
        mapIdRow:SetSize(220, 28)
        f.mapIdRow = mapIdRow

        local mapGetIdBtn = Factory:CreateButton(mapIdRow, 72, 26, false)
        if not mapGetIdBtn then
            mapGetIdBtn = CreateFrame("Button", nil, mapIdRow, "BackdropTemplate")
            mapGetIdBtn:SetSize(72, 26)
            if ApplyVisuals then
                ApplyVisuals(mapGetIdBtn, { 0.12, 0.12, 0.15, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.45 })
            end
        end
        mapGetIdBtn:SetPoint("LEFT", mapIdRow, "LEFT", 0, 0)
        local mapGetIdTxt = FontManager:CreateFontString(mapGetIdBtn, "small", "OVERLAY")
        mapGetIdTxt:SetPoint("CENTER")
        mapGetIdTxt:SetText((L and L["REMINDER_ZONE_GET_ID"]) or "Get ID")
        f.mapGetIdBtn = mapGetIdBtn

        local mapEditBg = Factory:CreateContainer(mapIdRow, 120, 28)
        if not mapEditBg then
            mapEditBg = CreateFrame("Frame", nil, mapIdRow)
            mapEditBg:SetHeight(28)
        end
        mapEditBg:SetPoint("LEFT", mapGetIdBtn, "RIGHT", 6, 0)
        mapEditBg:SetPoint("RIGHT", mapIdRow, "RIGHT", 0, 0)
        mapEditBg:SetHeight(26)
        if ApplyVisuals then
            ApplyVisuals(mapEditBg, { 0.08, 0.08, 0.10, 1 }, { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end
        mapEditBg:EnableMouse(true)

        local mapEdit = Factory:CreateEditBox(mapEditBg)
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

        f.mapIdZonePreview = FontManager:CreateFontString(f.selectedZonesBlock, "small", "OVERLAY")
        f.mapIdZonePreview:SetPoint("TOPLEFT", selectedToolbar, "BOTTOMLEFT", 0, -2)
        f.mapIdZonePreview:SetPoint("TOPRIGHT", selectedToolbar, "BOTTOMRIGHT", 0, -2)
        f.mapIdZonePreview:SetJustifyH("RIGHT")
        f.mapIdZonePreview:SetWordWrap(false)
        f.mapIdZonePreview:SetMaxLines(1)
        f.mapIdZonePreview:SetTextColor(labelMuted[1], labelMuted[2], labelMuted[3])
        f.mapIdZonePreview:Hide()

        f.mapsManualCard = f.selectedZonesBlock
        local mmPad = 0

        f.mapsManualEmpty = FontManager:CreateFontString(f.selectedZonesBlock, "small", "OVERLAY")
        f.mapsManualEmpty:SetPoint("TOPLEFT", selectedToolbar, "BOTTOMLEFT", 0, -4)
        f.mapsManualEmpty:SetPoint("TOPRIGHT", f.selectedZonesBlock, "TOPRIGHT", 0, -4)
        f.mapsManualEmpty:SetJustifyH("LEFT")
        f.mapsManualEmpty:SetWordWrap(true)
        f.mapsManualEmpty:SetMaxLines(2)
        f.mapsManualEmpty:SetTextColor(0.55, 0.58, 0.64)
        f.mapsManualEmpty:SetText((L and L["REMINDER_ZONE_SELECTED_EMPTY"])
            or (L and L["REMINDER_ZONE_MANUAL_EMPTY"])
            or "No zones selected. Add from the browser below or enter a map ID.")

        f.mapsManualRowsHost = CreateFrame("Frame", nil, f.selectedZonesBlock)
        f.mapsManualRowsHost:SetPoint("TOPLEFT", selectedToolbar, "BOTTOMLEFT", 0, -4)
        f.mapsManualRowsHost:SetPoint("TOPRIGHT", f.selectedZonesBlock, "TOPRIGHT", 0, -4)
        f.mapsManualRowsHost:SetClipsChildren(true)

        local MAN_ROW_H = 26
        local MAN_TAG_W = 54
        local MAN_RM_W = 62
        local MAN_ROW_GAP = 4
        local MAX_MANUAL_MAP_ROWS = 28
        local UIMT = Enum and Enum.UIMapType

        local ManualRowTagText = H and H.ManualRowTagText

        f._manualMapRows = {}
        for mri = 1, MAX_MANUAL_MAP_ROWS do
            local row = CreateFrame("Frame", nil, f.mapsManualRowsHost)
            row:SetHeight(MAN_ROW_H)
            row:Hide()

            row.tagFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.tagFs:SetWidth(MAN_TAG_W)
            row.tagFs:SetPoint("LEFT", row, "LEFT", mmPad, 0)
            row.tagFs:SetJustifyH("CENTER")

            row.rmBtn = Factory:CreateButton(row, MAN_RM_W, 22, false)
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
                local cntKey = (Lz and Lz["REMINDER_ZONE_SELECTED_COUNT"]) or (Lz and Lz["REMINDER_ZONE_MANUAL_COUNT"])
                self.mapsManualTitle:SetText(string.format(cntKey or "Selected zones (%d)", n))
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
                    local anchorBelow = self.selectedToolbar or self.mapsManualTitle
                    if self.mapIdZonePreview and self.mapIdZonePreview:IsShown() then
                        anchorBelow = self.mapIdZonePreview
                    end
                    self.mapsManualRowsHost:SetPoint("TOPLEFT", anchorBelow, "BOTTOMLEFT", 0, -4)
                    self.mapsManualRowsHost:SetPoint("TOPRIGHT", self.selectedZonesBlock or anchorBelow, "TOPRIGHT", 0, -4)
                    local rowsH = n * MAN_ROW_H + math.max(0, n - 1) * MAN_ROW_GAP
                    self.mapsManualRowsHost:SetHeight(rowsH)
                end
                emptyH = 0
            end

            local blockH = 28
            if n == 0 then
                blockH = blockH + emptyH
            else
                local rh = (self.mapsManualRowsHost and self.mapsManualRowsHost:GetHeight()) or 0
                blockH = blockH + rh + 4
            end
            if self.mapIdZonePreview and self.mapIdZonePreview:IsShown() then
                blockH = blockH + 14
            end
            if self.selectedZonesBlock then
                self.selectedZonesBlock:SetHeight(math.max(RD.selectedBlockMinH, blockH))
            end

            local locCard = self.locationCard
            if locCard then
                local pad = RD.cardPad
                local topBlock = 22 + 8 + 22 + 10
                local selH = (self.selectedZonesBlock and self.selectedZonesBlock:GetHeight()) or RD.selectedBlockMinH
                locCard:SetHeight(math.max(RD.locationBaseH, pad + topBlock + selH + pad))
            end
            if self.LayoutDialogHeights then
                self:LayoutDialogHeights()
            end
        end

        local BindCatalogMouseWheel = H and H.BindCatalogMouseWheel
        local TruncatePickerLabel = H and H.TruncatePickerLabel
        local function LocaleOr(key, fallback)
            if H and H.LocaleOr then return H.LocaleOr(L, key, fallback) end
            return fallback or key or ""
        end

        f._selectedWQQuestIDs = {}
        f._selectedEventQuestIDs = {}
        f._selectedWorldEventKeys = {}
        f._questListTab = "worldQuests"
        f._questPickerSectionIdx = 1
        f._questPickerLastScrollW = 0
        f._questPickerPrimed = false
        f._zoneCatalogPrimed = false

        function f:SyncThemedCheck(cb, checked)
            if not cb then return end
            local v = checked and true or false
            cb:SetChecked(v)
            if cb.innerDot then
                cb.innerDot:SetShown(v)
            end
        end

        --- Zone & Instance and Quests & Events cannot both be enabled on one alert.
        function f:ApplyAlertLocationQuestMutex()
            if self._locationQuestMutexLock then return end
            self._locationQuestMutexLock = true

            local zoneOn = self.zoneCheck and self.zoneCheck:GetChecked() == true
            local questOn = self.questTrackCheck and self.questTrackCheck:GetChecked() == true

            if zoneOn and questOn then
                if self._locationQuestMutexSide == "quest" then
                    self:SyncThemedCheck(self.zoneCheck, false)
                    zoneOn = false
                else
                    self:SyncThemedCheck(self.questTrackCheck, false)
                    questOn = false
                end
                self._locationQuestMutexSide = nil
            end

            local zoneBlocksQuest = zoneOn
            local questBlocksZone = questOn

            if self.questTrackCheck and self.questTrackCheck.Enable then
                self.questTrackCheck:Enable()
            end
            if self.zoneCheck and self.zoneCheck.Enable then
                self.zoneCheck:Enable()
            end
            if questBlocksZone and self.zoneCheck then
                self:SyncThemedCheck(self.zoneCheck, false)
            end
            if zoneBlocksQuest and self.questTrackCheck then
                self:SyncThemedCheck(self.questTrackCheck, false)
            end

            if self.questTrackLabel and self.questTrackLabel.SetTextColor then
                local blocked = zoneBlocksQuest and not questOn
                local alpha = blocked and 0.28 or (questOn and 1 or 0.38)
                self.questTrackLabel:SetTextColor(
                    labelBody[1] * alpha + 0.3, labelBody[2] * alpha + 0.3, labelBody[3] * alpha + 0.3)
            end
            if self.zoneLabel and self.zoneLabel.SetTextColor then
                local blocked = questBlocksZone and not zoneOn
                local alpha = blocked and 0.28 or (zoneOn and 1 or 0.38)
                self.zoneLabel:SetTextColor(
                    labelBody[1] * alpha + 0.3, labelBody[2] * alpha + 0.3, labelBody[3] * alpha + 0.3)
            end

            local zoneTabName = (L and L["SET_ALERT_SECTION_LOCATION"]) or "Zone & Instance"
            local questTabName = (L and L["SET_ALERT_SECTION_QUESTS"]) or "Quests & Events"
            local questBlockedFmt = (L and L["SET_ALERT_MUTEX_QUEST_BLOCKED"])
                or "Disabled while %s is enabled. Turn it off to use Quests and Events on this alert."
            local zoneBlockedFmt = (L and L["SET_ALERT_MUTEX_ZONE_BLOCKED"])
                or "Disabled while %s is enabled. Turn it off to use Zone and Instance on this alert."
            local questTip = zoneBlocksQuest and string.format(questBlockedFmt, zoneTabName) or nil
            local zoneTip = questBlocksZone and string.format(zoneBlockedFmt, questTabName) or nil
            self._questMutexTipText = questTip
            self._zoneMutexTipText = zoneTip

            if self.SetAlertMutexTipHost then
                self:SetAlertMutexTipHost(self.questMutexTipHost, questTip)
                self:SetAlertMutexTipHost(self.zoneMutexTipHost, zoneTip)
            end

            if self.zoneMutexNotice then
                if zoneTip then
                    self.zoneMutexNotice:SetText(zoneTip)
                    self.zoneMutexNotice:Show()
                    if self.selectedZonesBlock and self.locationInner then
                        self.selectedZonesBlock:ClearAllPoints()
                        self.selectedZonesBlock:SetPoint("TOPLEFT", self.zoneMutexNotice, "BOTTOMLEFT", 0, -8)
                        self.selectedZonesBlock:SetPoint("TOPRIGHT", self.locationInner, "TOPRIGHT", 0, -10)
                    end
                else
                    self.zoneMutexNotice:Hide()
                    if self.selectedZonesBlock and self.zoneCheck and self.locationInner then
                        self.selectedZonesBlock:ClearAllPoints()
                        self.selectedZonesBlock:SetPoint("TOPLEFT", self.zoneCheck, "BOTTOMLEFT", 0, -10)
                        self.selectedZonesBlock:SetPoint("TOPRIGHT", self.locationInner, "TOPRIGHT", 0, -10)
                    end
                end
            end
            if self.questMutexNotice then
                if questTip then
                    self.questMutexNotice:SetText(questTip)
                    self.questMutexNotice:Show()
                    if self.selectedQuestsBlock and self.questEventsInner then
                        self.selectedQuestsBlock:ClearAllPoints()
                        self.selectedQuestsBlock:SetPoint("TOPLEFT", self.questMutexNotice, "BOTTOMLEFT", 0, -8)
                        self.selectedQuestsBlock:SetPoint("TOPRIGHT", self.questEventsInner, "TOPRIGHT", 0, -10)
                    end
                else
                    self.questMutexNotice:Hide()
                    if self.selectedQuestsBlock and self.questTrackCheck and self.questEventsInner then
                        self.selectedQuestsBlock:ClearAllPoints()
                        self.selectedQuestsBlock:SetPoint("TOPLEFT", self.questTrackCheck, "BOTTOMLEFT", 0, -10)
                        self.selectedQuestsBlock:SetPoint("TOPRIGHT", self.questEventsInner, "TOPRIGHT", 0, -10)
                    end
                end
            end

            if self.LayoutDialogHeights then self:LayoutDialogHeights() end

            self._locationQuestMutexLock = false
        end

        function f:GetActiveQuestPickerSection()
            local RQP = ns.ReminderQuestPickerCatalog
            local sections = (RQP and RQP.GetTypeSections and RQP.GetTypeSections()) or {}
            local idx = self._questPickerSectionIdx or 1
            return sections[idx] or sections[1]
        end

        function f:GetActiveQuestTrackMode()
            local sec = self:GetActiveQuestPickerSection()
            return (sec and sec.trackMode) or self._questListTab or "worldQuests"
        end

        function f:GetActiveQuestTrackSelectionCount()
            local mode = self:GetActiveQuestTrackMode()
            if mode == "contentEvents" then
                return #(self._selectedEventQuestIDs or {})
            end
            if mode == "worldEvents" then
                return #(self._selectedWorldEventKeys or {})
            end
            return #(self._selectedWQQuestIDs or {})
        end

        function f:RefreshSelectedQuestSummary()
            local n = self:GetActiveQuestTrackSelectionCount()
            if self.questSelectedTitle then
                local cntKey = (L and L["REMINDER_QUEST_SELECTED_COUNT"]) or "Selected entries (%d)"
                self.questSelectedTitle:SetText(string.format(cntKey, n))
            end
            if self.questSelectedEmpty then
                if n == 0 then
                    self.questSelectedEmpty:Show()
                else
                    self.questSelectedEmpty:Hide()
                end
            end
            local pad = RD.cardPad
            local topBlock = 22 + 8 + 22 + 10
            local blockH = topBlock + ((n == 0) and 28 or 4)
            if self.selectedQuestsBlock then
                self.selectedQuestsBlock:SetHeight(math.max(36, blockH))
            end
            if self.questTrackCard then
                self.questTrackCard:SetHeight(math.max(RD.questTrackBaseH, pad + blockH + pad))
            end
            if self.LayoutDialogHeights then self:LayoutDialogHeights() end
        end

        function f:SetActiveQuestPickerSectionIdx(idx)
            local RQP = ns.ReminderQuestPickerCatalog
            local sections = (RQP and RQP.GetTypeSections and RQP.GetTypeSections()) or {}
            idx = tonumber(idx) or 1
            if idx < 1 then idx = 1 end
            if #sections > 0 and idx > #sections then idx = #sections end
            local sec = sections[idx]
            if not sec then return end
            if self._questPickerSectionIdx ~= idx and self.questCatalogScroll then
                self.questCatalogScroll:SetVerticalScroll(0)
            end
            self._questPickerSectionIdx = idx
            self._catalogQuestSectionIdx = idx
            self._questListTab = sec.trackMode
            self:RefreshSelectedQuestSummary()
            if self.LayoutQuestCatalogSplit then
                self:LayoutQuestCatalogSplit()
            end
            if self.RefreshQuestTypeButtonHighlight then
                self:RefreshQuestTypeButtonHighlight()
            end
            if self._activeAlertTab == "quests" and self._questPickerPrimed and self.RefreshPickerListRows then
                self:RefreshPickerListRows()
            end
        end

        function f:SetActiveQuestTrackMode(mode)
            if mode ~= "worldQuests" and mode ~= "contentEvents" and mode ~= "worldEvents" then
                mode = "worldQuests"
            end
            local RQP = ns.ReminderQuestPickerCatalog
            local idx = 1
            if RQP and RQP.GetDefaultSectionIndexForTrackMode then
                idx = RQP.GetDefaultSectionIndexForTrackMode(mode)
            end
            self:SetActiveQuestPickerSectionIdx(idx)
        end

        function f:RefreshQuestTypeButtonHighlight()
            local sections = (ns.ReminderQuestPickerCatalog and ns.ReminderQuestPickerCatalog.GetTypeSections
                and ns.ReminderQuestPickerCatalog.GetTypeSections()) or {}
            local idx = self._questPickerSectionIdx or 1
            local btns = self._questTypeBtns
            if not btns then return end
            for bi = 1, #sections do
                local sel = (bi == idx)
                if btns[bi] and ApplyVisuals then
                    ApplyVisuals(btns[bi],
                        sel and { COLORS.accent[1] * 0.42, COLORS.accent[2] * 0.42, COLORS.accent[3] * 0.42, 1 } or { 0.12, 0.12, 0.15, 1 },
                        { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], sel and 0.95 or 0.35 })
                end
            end
        end

        local questTrackCard = CreateFrame("Frame", nil, f.panelQuests)
        questTrackCard:SetPoint("TOPLEFT", f.panelQuests, "TOPLEFT", 0, 0)
        questTrackCard:SetPoint("TOPRIGHT", f.panelQuests, "TOPRIGHT", 0, 0)
        questTrackCard:SetHeight(RD.questTrackBaseH)
        StyleCard(questTrackCard)
        f.questTrackCard = questTrackCard
        f.questEventsCard = questTrackCard

        local trackInner = CreateFrame("Frame", nil, questTrackCard)
        trackInner:SetPoint("TOPLEFT", questTrackCard, "TOPLEFT", cardPad, -cardPad)
        trackInner:SetPoint("BOTTOMRIGHT", questTrackCard, "BOTTOMRIGHT", -cardPad, cardPad)
        f.questEventsInner = trackInner

        local secQuestTrack = FontManager:CreateFontString(trackInner, "subtitle", "OVERLAY")
        secQuestTrack:SetPoint("TOPLEFT", trackInner, "TOPLEFT", 0, 0)
        secQuestTrack:SetPoint("TOPRIGHT", trackInner, "TOPRIGHT", 0, 0)
        secQuestTrack:SetJustifyH("LEFT")
        secQuestTrack:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        secQuestTrack:SetText((L and L["SET_ALERT_SECTION_QUESTS"]) or "Quests & Events")

        local questTrackCheck = CreateThemedCheckbox(trackInner, false)
        questTrackCheck:SetPoint("TOPLEFT", secQuestTrack, "BOTTOMLEFT", 0, -8)
        local questTrackLabel = FontManager:CreateFontString(trackInner, "body", "OVERLAY")
        questTrackLabel:SetPoint("LEFT", questTrackCheck, "RIGHT", 8, 0)
        questTrackLabel:SetPoint("RIGHT", trackInner, "RIGHT", 0, 0)
        questTrackLabel:SetJustifyH("LEFT")
        questTrackLabel:SetWordWrap(true)
        questTrackLabel:SetMaxLines(2)
        questTrackLabel:SetText((L and L["REMINDER_OPT_QUEST_TRACK"])
            or (L and L["REMINDER_OPT_WORLD_QUEST_ACTIVE"])
            or "Remind when selected entries are active on the map")
        questTrackLabel:SetTextColor(labelBody[1], labelBody[2], labelBody[3])
        questTrackLabel:EnableMouse(true)
        if questTrackLabel.RegisterForClicks then
            questTrackLabel:RegisterForClicks("LeftButtonUp")
        end
        questTrackLabel:SetScript("OnMouseUp", function(_, btn)
            if btn ~= "LeftButton" then return end
            if f._questMutexTipText then return end
            questTrackCheck:Click()
        end)
        f.questTrackCheck = questTrackCheck
        f.questTrackLabel = questTrackLabel
        f.questMutexNotice = FontManager:CreateFontString(trackInner, "small", "OVERLAY")
        f.questMutexNotice:SetPoint("TOPLEFT", questTrackCheck, "BOTTOMLEFT", 0, -6)
        f.questMutexNotice:SetPoint("TOPRIGHT", trackInner, "TOPRIGHT", 0, -6)
        f.questMutexNotice:SetJustifyH("LEFT")
        f.questMutexNotice:SetWordWrap(true)
        f.questMutexNotice:SetMaxLines(2)
        f.questMutexNotice:SetTextColor(0.92, 0.72, 0.42)
        f.questMutexNotice:Hide()
        WireMutexHoverTip(questTrackLabel, "_questMutexTipText")
        WireMutexHoverTip(questTrackCheck, "_questMutexTipText")

        questTrackCheck:HookScript("OnClick", function()
            if f._questMutexTipText then
                f:SyncThemedCheck(f.questTrackCheck, false)
                return
            end
            f._locationQuestMutexSide = "quest"
            if f.ApplyAlertLocationQuestMutex then f:ApplyAlertLocationQuestMutex() end
            if f.ApplyZoneDependentControlsState then f:ApplyZoneDependentControlsState() end
            if f.ApplyQuestTrackControlsState then f:ApplyQuestTrackControlsState() end
        end)
        f.questMutexTipHost = CreateMutexTipHost(trackInner, questTrackCheck, questTrackLabel)
        f:RaiseMutexTipHost(f.questMutexTipHost)

        f.selectedQuestsBlock = CreateFrame("Frame", nil, trackInner)
        f.selectedQuestsBlock:SetPoint("TOPLEFT", questTrackCheck, "BOTTOMLEFT", 0, -10)
        f.selectedQuestsBlock:SetPoint("TOPRIGHT", trackInner, "TOPRIGHT", 0, -10)
        f.selectedQuestsBlock:SetHeight(36)

        f.questSelectedTitle = FontManager:CreateFontString(f.selectedQuestsBlock, "subtitle", "OVERLAY")
        f.questSelectedTitle:SetPoint("TOPLEFT", f.selectedQuestsBlock, "TOPLEFT", 0, 0)
        f.questSelectedTitle:SetPoint("TOPRIGHT", f.selectedQuestsBlock, "TOPRIGHT", 0, 0)
        f.questSelectedTitle:SetJustifyH("LEFT")
        f.questSelectedTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        f.questSelectedTitle:SetText(string.format(
            (L and L["REMINDER_QUEST_SELECTED_COUNT"]) or "Selected entries (%d)", 0))

        f.questSelectedEmpty = FontManager:CreateFontString(f.selectedQuestsBlock, "small", "OVERLAY")
        f.questSelectedEmpty:SetPoint("TOPLEFT", f.questSelectedTitle, "BOTTOMLEFT", 0, -4)
        f.questSelectedEmpty:SetPoint("TOPRIGHT", f.selectedQuestsBlock, "TOPRIGHT", 0, -4)
        f.questSelectedEmpty:SetJustifyH("LEFT")
        f.questSelectedEmpty:SetWordWrap(true)
        f.questSelectedEmpty:SetMaxLines(2)
        f.questSelectedEmpty:SetTextColor(0.55, 0.58, 0.64)
        f.questSelectedEmpty:SetText((L and L["REMINDER_QUEST_SELECTED_EMPTY"])
            or "No quests or events selected. Check the list below.")

        f.questPickerCard = CreateFrame("Frame", nil, f.panelQuests)
        f.questPickerCard:SetPoint("TOPLEFT", questTrackCard, "BOTTOMLEFT", 0, -8)
        f.questPickerCard:SetPoint("BOTTOMRIGHT", f.panelQuests, "BOTTOMRIGHT", 0, 0)
        f.questPickerCard:SetClipsChildren(true)
        if ApplyVisuals then
            ApplyVisuals(f.questPickerCard,
                { bgCardCol[1], bgCardCol[2], bgCardCol[3], bgCardCol[4] or 1 },
                { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end

        local questPickerPad = 8
        local questPickerTitle = FontManager:CreateFontString(f.questPickerCard, "subtitle", "OVERLAY")
        questPickerTitle:SetPoint("TOPLEFT", f.questPickerCard, "TOPLEFT", cardPad, -questPickerPad)
        questPickerTitle:SetPoint("TOPRIGHT", f.questPickerCard, "TOPRIGHT", -cardPad, -questPickerPad)
        questPickerTitle:SetJustifyH("LEFT")
        questPickerTitle:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        questPickerTitle:SetText((L and L["REMINDER_QUEST_CATALOG_TITLE"]) or "Quest and event picker")

        local questPickerHint = FontManager:CreateFontString(f.questPickerCard, "small", "OVERLAY")
        questPickerHint:SetPoint("TOPLEFT", questPickerTitle, "BOTTOMLEFT", 0, -4)
        questPickerHint:SetPoint("TOPRIGHT", questPickerTitle, "BOTTOMRIGHT", 0, -4)
        questPickerHint:SetJustifyH("LEFT")
        questPickerHint:SetWordWrap(true)
        questPickerHint:SetMaxLines(2)
        questPickerHint:SetTextColor(0.55, 0.58, 0.64)
        questPickerHint:SetText((L and L["REMINDER_QUEST_CATALOG_HINT_SHORT"])
            or (L and L["SET_ALERT_QUESTS_HINT"])
            or "Region or category on the left; Type and Title on the right.")
        f.questTabHint = questPickerHint
        f.questCatalogCard = f.questPickerCard

        function f:GetQuestSelectionList(mode)
            if mode == "contentEvents" then
                return self._selectedEventQuestIDs
            end
            if mode == "worldQuests" then
                return self._selectedWQQuestIDs
            end
            return nil
        end

        function f:IsQuestSelected(questID, mode)
            questID = tonumber(questID)
            if not questID or not mode then return false end
            local list = self:GetQuestSelectionList(mode)
            if not list then return false end
            for i = 1, #list do
                if list[i] == questID then return true end
            end
            return false
        end

        function f:SetQuestSelected(questID, mode, selected)
            questID = tonumber(questID)
            if not questID or questID <= 0 then return end
            if mode ~= "worldQuests" and mode ~= "contentEvents" then return end
            local list = self:GetQuestSelectionList(mode) or {}
            local out = {}
            local found = false
            for i = 1, #list do
                if list[i] == questID then
                    found = true
                    if selected then out[#out + 1] = questID end
                else
                    out[#out + 1] = list[i]
                end
            end
            if selected and not found then out[#out + 1] = questID end
            table.sort(out)
            if mode == "contentEvents" then
                self._selectedEventQuestIDs = out
            else
                self._selectedWQQuestIDs = out
            end
            if self.RefreshSelectedQuestSummary then self:RefreshSelectedQuestSummary() end
        end

        function f:OnPickerRowCheckClick(row)
            if not row or not row.check then return end
            local mode = row._pickerMode
            if not mode then return end
            local checked = row.check:GetChecked() == true
            if mode == "worldEvents" then
                if row.eventKey and self.SetWorldEventSelected then
                    self:SetWorldEventSelected(row.eventKey, checked)
                end
                return
            end
            if row.questID and (mode == "worldQuests" or mode == "contentEvents") then
                self:SetQuestSelected(row.questID, mode, checked)
            end
        end

        function f:IsWorldEventSelected(eventKey)
            if not eventKey or eventKey == "" then return false end
            local list = self._selectedWorldEventKeys or {}
            for i = 1, #list do
                if list[i] == eventKey then return true end
            end
            return false
        end

        function f:SetWorldEventSelected(eventKey, selected)
            if not eventKey or eventKey == "" then return end
            local list = self._selectedWorldEventKeys or {}
            local out, found = {}, false
            for i = 1, #list do
                if list[i] == eventKey then
                    found = true
                    if selected then out[#out + 1] = eventKey end
                else
                    out[#out + 1] = list[i]
                end
            end
            if selected and not found then out[#out + 1] = eventKey end
            table.sort(out)
            self._selectedWorldEventKeys = out
            if self.RefreshSelectedQuestSummary then self:RefreshSelectedQuestSummary() end
        end

        local qcScrollW = scrollBarW
        local qcSplitGap = RD.splitGap
        local typeInnerW = RD.expColW
        local typePanelOuterW = typeInnerW + 4

        local questMapsBody = CreateFrame("Frame", nil, f.questPickerCard)
        questMapsBody:SetPoint("TOPLEFT", questPickerHint, "BOTTOMLEFT", 0, -8)
        questMapsBody:SetPoint("BOTTOMRIGHT", f.questPickerCard, "BOTTOMRIGHT", -cardPad, questPickerPad)
        f.questMapsBody = questMapsBody
        f.questListArea = questMapsBody
        f.questListSection = questMapsBody

        local questColHeadRow = CreateFrame("Frame", nil, questMapsBody)
        questColHeadRow:SetPoint("TOPLEFT", questMapsBody, "TOPLEFT", 0, 0)
        questColHeadRow:SetPoint("TOPRIGHT", questMapsBody, "TOPRIGHT", 0, 0)
        questColHeadRow:SetHeight(18)
        f.questColHeadRow = questColHeadRow

        local questSectionHead = FontManager:CreateFontString(questColHeadRow, "subtitle", "OVERLAY")
        questSectionHead:SetPoint("TOPLEFT", questColHeadRow, "TOPLEFT", 0, 0)
        questSectionHead:SetWidth(typeInnerW)
        questSectionHead:SetJustifyH("LEFT")
        questSectionHead:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        questSectionHead:SetText((L and L["REMINDER_QUEST_CATALOG_CATEGORY_LABEL"]) or "Category")
        f.questSectionHead = questSectionHead
        f.questTypeHead = questSectionHead

        local questListHead = FontManager:CreateFontString(questColHeadRow, "subtitle", "OVERLAY")
        questListHead:SetPoint("TOPLEFT", questColHeadRow, "TOPLEFT", typePanelOuterW + qcSplitGap, 0)
        questListHead:SetPoint("TOPRIGHT", questColHeadRow, "TOPRIGHT", 0, 0)
        questListHead:SetJustifyH("LEFT")
        questListHead:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        questListHead:SetText((L and L["REMINDER_QUEST_CATALOG_LIST_LABEL"]) or "Quests")
        f.questListHead = questListHead
        f.questEntriesHead = questListHead

        local questPickSplit = CreateFrame("Frame", nil, questMapsBody)
        questPickSplit:SetPoint("TOPLEFT", questColHeadRow, "BOTTOMLEFT", 0, -8)
        questPickSplit:SetPoint("BOTTOMRIGHT", questMapsBody, "BOTTOMRIGHT", 0, 0)
        f.questPickSplit = questPickSplit

        local typePanel = CreateFrame("Frame", nil, questPickSplit)
        typePanel:SetWidth(typePanelOuterW)
        typePanel:SetPoint("TOPLEFT", questPickSplit, "TOPLEFT", 0, 0)
        typePanel:SetPoint("BOTTOMLEFT", questPickSplit, "BOTTOMLEFT", 0, 0)
        if typePanel.SetClipsChildren then
            typePanel:SetClipsChildren(true)
        end
        f.questTypePanel = typePanel

        local typeListHost = CreateFrame("Frame", nil, typePanel)
        typeListHost:SetPoint("TOPLEFT", typePanel, "TOPLEFT", 0, 0)
        typeListHost:SetPoint("BOTTOMRIGHT", typePanel, "BOTTOMRIGHT", 0, 0)
        if typeListHost.SetClipsChildren then
            typeListHost:SetClipsChildren(true)
        end
        f.questTypeListHost = typeListHost
        f.questSectionScrollChild = typeListHost

        local questSplitLine = questPickSplit:CreateTexture(nil, "ARTWORK")
        questSplitLine:SetWidth(1)
        questSplitLine:SetColorTexture(borderCol[1], borderCol[2], borderCol[3], 0.45)
        questSplitLine:SetPoint("TOPLEFT", typePanel, "TOPRIGHT", math.floor(qcSplitGap * 0.5), 0)
        questSplitLine:SetPoint("BOTTOMLEFT", typePanel, "BOTTOMRIGHT", math.ceil(qcSplitGap * 0.5), 0)
        f.questSplitLine = questSplitLine

        local entriesPanel = CreateFrame("Frame", nil, questPickSplit)
        entriesPanel:SetPoint("TOPLEFT", questPickSplit, "TOPLEFT", typePanelOuterW + qcSplitGap, 0)
        entriesPanel:SetPoint("BOTTOMRIGHT", questPickSplit, "BOTTOMRIGHT", 0, 0)
        if entriesPanel.SetClipsChildren then
            entriesPanel:SetClipsChildren(true)
        end
        f.questEntriesPanel = entriesPanel

        f._catalogQuestBtns = {}
        f._catalogQuestSectionIdx = 1
        f._questTypeBtns = f._catalogQuestBtns

        local questPickerDef = ns.ReminderQuestPickerCatalog
        local questSecBtnH = 28
        local questSecBtnGap = 6
        if questPickerDef and questPickerDef.GetTypeSections then
            local sections = questPickerDef.GetTypeSections()
            for si = 1, #sections do
                (function(sec, secIdx)
                    local sb = Factory:CreateButton(typeListHost, typeInnerW, questSecBtnH, false)
                    if not sb then
                        sb = CreateFrame("Button", nil, typeListHost, "BackdropTemplate")
                        sb:SetSize(typeInnerW, questSecBtnH)
                        if ApplyVisuals then
                            ApplyVisuals(sb, { 0.12, 0.12, 0.15, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.35 })
                        end
                    end
                    if secIdx == 1 then
                        sb:SetPoint("TOPLEFT", typeListHost, "TOPLEFT", 0, 0)
                    else
                        sb:SetPoint("TOPLEFT", f._catalogQuestBtns[secIdx - 1], "BOTTOMLEFT", 0, -questSecBtnGap)
                    end
                    sb:SetSize(typeInnerW, questSecBtnH)
                    local lk = sec.labelKey or ""
                    local sbTxt = FontManager:CreateFontString(sb, "small", "OVERLAY")
                    sbTxt:SetPoint("LEFT", sb, "LEFT", 8, 0)
                    sbTxt:SetPoint("RIGHT", sb, "RIGHT", -8, 0)
                    sbTxt:SetJustifyH("LEFT")
                    sbTxt:SetMaxLines(2)
                    sbTxt:SetWordWrap(true)
                    sbTxt:SetText(LocaleOr(lk, sec.fallback or "?"))
                    sb:SetScript("OnClick", function()
                        if f.SetActiveQuestPickerSectionIdx then
                            f:SetActiveQuestPickerSectionIdx(secIdx)
                        end
                    end)
                    f._catalogQuestBtns[secIdx] = sb
                end)(sections[si], si)
            end
            local totalSecH = #sections * (questSecBtnH + questSecBtnGap) - questSecBtnGap
            typeListHost:SetHeight(math.max(totalSecH, 40))
        end

        local questPickColW = RD.addBtnW
        local questTagColW = RD.tagColW
        local questListHdrH = 16

        local questEntriesListColHead = CreateFrame("Frame", nil, entriesPanel)
        questEntriesListColHead:SetPoint("TOPLEFT", entriesPanel, "TOPLEFT", 0, 0)
        questEntriesListColHead:SetPoint("TOPRIGHT", entriesPanel, "TOPRIGHT", 0, 0)
        questEntriesListColHead:SetHeight(questListHdrH)
        f.questEntriesListColHead = questEntriesListColHead
        f.mapsListColHead = questEntriesListColHead

        local questTagColHead = FontManager:CreateFontString(questEntriesListColHead, "small", "OVERLAY")
        questTagColHead:SetWidth(questTagColW)
        questTagColHead:SetPoint("LEFT", questEntriesListColHead, "LEFT", 8, 0)
        questTagColHead:SetJustifyH("CENTER")
        questTagColHead:SetTextColor(0.55, 0.58, 0.64)
        questTagColHead:SetText(LocaleOr("REMINDER_QUEST_CATALOG_COL_TYPE", "Type"))
        f.questEntriesTypeColHead = questTagColHead

        local questPickColHead = FontManager:CreateFontString(questEntriesListColHead, "small", "OVERLAY")
        questPickColHead:SetWidth(questPickColW)
        questPickColHead:SetPoint("RIGHT", questEntriesListColHead, "RIGHT", -6, 0)
        questPickColHead:SetJustifyH("CENTER")
        questPickColHead:SetTextColor(0.55, 0.58, 0.64)
        questPickColHead:SetText(LocaleOr("REMINDER_QUEST_CATALOG_COL_SELECT", "Track"))
        f.questPickColHead = questPickColHead

        local questTitleColHead = FontManager:CreateFontString(questEntriesListColHead, "small", "OVERLAY")
        questTitleColHead:SetPoint("LEFT", questTagColHead, "RIGHT", 6, 0)
        questTitleColHead:SetPoint("RIGHT", questPickColHead, "LEFT", -8, 0)
        questTitleColHead:SetJustifyH("LEFT")
        questTitleColHead:SetTextColor(0.55, 0.58, 0.64)
        questTitleColHead:SetText(LocaleOr("REMINDER_QUEST_CATALOG_COL_QUEST", "Quest"))
        f.questEntriesTitleHead = questTitleColHead
        f.questEntriesEntryHead = questTitleColHead

        local entriesBarCol = Factory:CreateScrollBarColumn(entriesPanel, qcScrollW, 0, 0)
        if entriesBarCol then
            entriesBarCol:SetPoint("TOPRIGHT", entriesPanel, "TOPRIGHT", 0, 0)
            entriesBarCol:SetPoint("BOTTOMRIGHT", entriesPanel, "BOTTOMRIGHT", 0, 0)
        end

        local questListScroll = Factory:CreateScrollFrame(entriesPanel, "UIPanelScrollFrameTemplate", true)
        if not questListScroll then
            questListScroll = CreateFrame("ScrollFrame", nil, entriesPanel, "UIPanelScrollFrameTemplate")
        end
        questListScroll:SetPoint("TOPLEFT", questEntriesListColHead, "BOTTOMLEFT", 0, -4)
        if entriesBarCol then
            questListScroll:SetPoint("BOTTOMRIGHT", entriesBarCol, "BOTTOMLEFT", -4, 0)
            if questListScroll.ScrollBar then
                Factory:PositionScrollBarInContainer(questListScroll.ScrollBar, entriesBarCol, 0)
            end
        else
            questListScroll:SetPoint("BOTTOMRIGHT", entriesPanel, "BOTTOMRIGHT", 0, 0)
        end

        local questListChild = CreateFrame("Frame", nil, questListScroll)
        local qListInitialW = math.max(200, innerW - cardPad * 2 - typePanelOuterW - qcSplitGap - qcScrollW - 16)
        questListChild:SetWidth(qListInitialW)
        questListScroll:SetScrollChild(questListChild)
        f._questCatalogLayout = {
            scrollBarW = qcScrollW,
            splitGap = qcSplitGap,
            typeInnerW = typeInnerW,
            typePanelOuterW = typePanelOuterW,
            addBtnW = questPickColW,
            tagColW = questTagColW,
            rowH = RD.catalogRowH,
            hdrH = RD.catalogHdrH,
        }
        f.questCatalogScroll = questListScroll
        f.questCatalogScrollChild = questListChild
        f.questCatalogEmptyFs = FontManager:CreateFontString(questListChild, "small", "OVERLAY")
        f.questCatalogEmptyFs:SetPoint("TOPLEFT", questListChild, "TOPLEFT", 8, -8)
        f.questCatalogEmptyFs:SetPoint("TOPRIGHT", questListChild, "TOPRIGHT", -8, -8)
        f.questCatalogEmptyFs:SetJustifyH("LEFT")
        f.questCatalogEmptyFs:SetWordWrap(true)
        f.questCatalogEmptyFs:Hide()
        BindCatalogMouseWheel(questListScroll)

        questListScroll:SetScript("OnSizeChanged", function(self)
            local child = self:GetScrollChild()
            local w = self:GetWidth()
            if not w or w <= 0 then return end
            if child then child:SetWidth(math.max(160, w)) end
            local lastW = f._questPickerLastScrollW or 0
            if math.abs(w - lastW) > 1 then
                f._questPickerLastScrollW = w
                if f.RefreshPickerListRows then f:RefreshPickerListRows() end
            end
            if Factory.UpdateScrollBarVisibility then Factory:UpdateScrollBarVisibility(self) end
        end)

        local LIST_ROW_H = RD.catalogRowH
        local LIST_HDR_H = RD.catalogHdrH
        f._questListRows = {}
        f._questListPoolCount = 0
        f._questListPoolMax = nil

        function f:ResolveQuestListPoolMax()
            if self._questListPoolMax then return self._questListPoolMax end
            local RQP_CAT = ns.ReminderQuestPickerCatalog
            local cap = (RQP_CAT and RQP_CAT.GetMaxDisplayRowCount and RQP_CAT.GetMaxDisplayRowCount()) or 120
            self._questListPoolMax = cap
            return cap
        end

        function f:EnsureQuestListRow(poolIdx)
            local maxRows = self:ResolveQuestListPoolMax()
            if not poolIdx or poolIdx < 1 or poolIdx > maxRows then return nil end
            local pool = self._questListRows
            if pool[poolIdx] then return pool[poolIdx] end
            local questListChild = self.questCatalogScrollChild
            if not questListChild then return nil end

            local row = CreateFrame("Frame", nil, questListChild)
            row:SetHeight(LIST_ROW_H)
            row._poolIndex = poolIdx
            row.headerBar = row:CreateTexture(nil, "BACKGROUND")
            row.headerBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.headerBar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.headerBar:SetColorTexture(COLORS.accent[1] * 0.35, COLORS.accent[2] * 0.35, COLORS.accent[3] * 0.35, 0.55)
            row.headerBar:Hide()
            row.tagFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.tagFs:SetWidth(questTagColW)
            row.tagFs:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.tagFs:SetJustifyH("CENTER")
            row.check = CreateThemedCheckbox(row, false)
            row.check:SetPoint("RIGHT", row, "RIGHT", -6, 0)
            row.labelFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.labelFs:SetJustifyH("LEFT")
            row.labelFs:SetWordWrap(false)
            row.labelFs:SetMaxLines(1)
            row.labelFs:SetPoint("LEFT", row.tagFs, "RIGHT", 6, 0)
            row.labelFs:SetPoint("RIGHT", row.check, "LEFT", -8, 0)
            local baseCheckOnClick = row.check:GetScript("OnClick")
            row.check:SetScript("OnClick", function(self)
                if baseCheckOnClick then
                    baseCheckOnClick(self)
                end
                local r = f._questListRows and f._questListRows[poolIdx]
                if r then
                    f:OnPickerRowCheckClick(r)
                end
            end)
            row:Hide()
            pool[poolIdx] = row
            if poolIdx > (self._questListPoolCount or 0) then
                self._questListPoolCount = poolIdx
            end
            return row
        end

        function f:EnsureQuestListPoolSize(needed)
            needed = math.min(needed or 0, self:ResolveQuestListPoolMax())
            for i = 1, needed do
                self:EnsureQuestListRow(i)
            end
        end

        local function LayoutQuestCatalogSplit()
            if not f.questMapsBody or not f.questTypePanel or not f.questEntriesPanel then return end
            local lay = f._questCatalogLayout
            if not lay then return end
            local typeW = RD.expColW
            local outerW = typeW + 4
            lay.typeInnerW = typeW
            lay.typePanelOuterW = outerW

            f.questTypePanel:SetWidth(outerW)
            f.questTypePanel:ClearAllPoints()
            f.questTypePanel:SetPoint("TOPLEFT", f.questPickSplit, "TOPLEFT", 0, 0)
            f.questTypePanel:SetPoint("BOTTOMLEFT", f.questPickSplit, "BOTTOMLEFT", 0, 0)

            local typeBtns = f._catalogQuestBtns
            if typeBtns then
                for bi = 1, #typeBtns do
                    local tb = typeBtns[bi]
                    if tb then
                        tb:SetWidth(typeW)
                    end
                end
            end
            if f.questSectionHead then
                f.questSectionHead:SetWidth(typeW)
            elseif f.questTypeHead then
                f.questTypeHead:SetWidth(typeW)
            end

            f.questEntriesPanel:ClearAllPoints()
            f.questEntriesPanel:SetPoint("TOPLEFT", f.questPickSplit, "TOPLEFT", outerW + lay.splitGap, 0)
            f.questEntriesPanel:SetPoint("BOTTOMRIGHT", f.questPickSplit, "BOTTOMRIGHT", 0, 0)

            if f.questSplitLine and f.questTypePanel then
                f.questSplitLine:ClearAllPoints()
                local halfGap = math.floor(lay.splitGap * 0.5)
                f.questSplitLine:SetPoint("TOPLEFT", f.questTypePanel, "TOPRIGHT", halfGap, 0)
                f.questSplitLine:SetPoint("BOTTOMLEFT", f.questTypePanel, "BOTTOMRIGHT", halfGap, 0)
            end

            if f.questEntriesHead and f.questColHeadRow then
                f.questEntriesHead:ClearAllPoints()
                f.questEntriesHead:SetPoint("TOPLEFT", f.questColHeadRow, "TOPLEFT", outerW + lay.splitGap, 0)
                f.questEntriesHead:SetPoint("TOPRIGHT", f.questColHeadRow, "TOPRIGHT", 0, 0)
            end

            if f.questCatalogScroll then
                local vw = f.questCatalogScroll:GetWidth()
                if f.questCatalogScrollChild and vw and vw > 0 then
                    f.questCatalogScrollChild:SetWidth(math.max(160, vw))
                end
            end
            if f.RefreshPickerListRows and f._questPickerPrimed then
                f:RefreshPickerListRows()
            end
        end
        f.LayoutQuestCatalogSplit = LayoutQuestCatalogSplit

        questMapsBody:SetScript("OnSizeChanged", function()
            LayoutQuestCatalogSplit()
        end)
        LayoutQuestCatalogSplit()

        function f:RefreshPickerListRows()
            local RQP = ns.ReminderQuestPickerCatalog
            local RQC = ns.ReminderQuestCatalog
            local section = self.GetActiveQuestPickerSection and self:GetActiveQuestPickerSection()
            local tab = (section and section.trackMode) or self:GetActiveQuestTrackMode()
            local isWorldEvents = (tab == "worldEvents")
            local isWQ = (tab == "worldQuests")
            local rows = (RQP and RQP.GetDisplayRows and section and RQP.GetDisplayRows(section)) or {}

            local RQPsec = ns.ReminderQuestPickerCatalog
            local questSections = (RQPsec and RQPsec.GetTypeSections and RQPsec.GetTypeSections()) or {}
            local secIdx = self._questPickerSectionIdx or self._catalogQuestSectionIdx or 1
            for j = 1, #questSections do
                local ob = self._catalogQuestBtns and self._catalogQuestBtns[j]
                if ob and ApplyVisuals then
                    local sel = (j == secIdx)
                    ApplyVisuals(ob,
                        sel and { COLORS.accent[1] * 0.42, COLORS.accent[2] * 0.42, COLORS.accent[3] * 0.42, 1 } or { 0.12, 0.12, 0.15, 1 },
                        { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], sel and 0.95 or 0.35 })
                end
            end

            local zw = (self.questCatalogScroll and self.questCatalogScroll:GetWidth())
                or (self.questCatalogScrollChild and self.questCatalogScrollChild:GetWidth()) or 320
            local Lq = ns.L
            local unk = (Lq and Lq["UNKNOWN"]) or "?"
            local activeLbl = (Lq and Lq["REMINDER_WORLD_EVENT_STATUS_ACTIVE"]) or "Active"
            local inactiveLbl = (Lq and Lq["REMINDER_WORLD_EVENT_STATUS_INACTIVE"]) or "Inactive"
            local lay = self._questCatalogLayout or {}
            local pickColW = lay.addBtnW or RD.addBtnW
            local tagColW = lay.tagColW or RD.tagColW
            local dataRowH = lay.rowH or LIST_ROW_H
            local hdrRowH = lay.hdrH or LIST_HDR_H

            if self.questCatalogEmptyFs then
                if #rows == 0 then
                    local ek = isWorldEvents and "REMINDER_WORLD_EVENT_CATALOG_EMPTY"
                        or (isWQ and "REMINDER_QUEST_CATALOG_EMPTY_WQ" or "REMINDER_QUEST_CATALOG_EMPTY_EVENTS")
                    local emptyMsg = (Lq and Lq[ek])
                        or "No quests or events in this list."
                    self.questCatalogEmptyFs:SetText(emptyMsg)
                    self.questCatalogEmptyFs:Show()
                else
                    self.questCatalogEmptyFs:Hide()
                end
            end

            local function LocaleRow(key, fallback)
                if not key or key == "" then return fallback or "" end
                local v = Lq and Lq[key]
                if v and v ~= key then return v end
                return fallback or key
            end

            local function TagText(entry)
                if not entry or not entry.typeTagKey then return "|cff888888?|r" end
                if entry.trackMode == "worldEvents" then
                    if entry.isActive then
                        return "|cff9ecfae" .. activeLbl .. "|r"
                    end
                    return "|cff888888" .. inactiveLbl .. "|r"
                end
                local tk = entry.typeTagKey
                local raw = LocaleRow(tk, tk)
                if tk == "REMINDER_QUEST_TAG_WQ" then
                    return "|cff9ecfae" .. raw .. "|r"
                end
                if tk == "REMINDER_QUEST_TAG_CONTENT_EVENT" or tk == "REMINDER_QUEST_TAG_ZONE_EVENT" then
                    return "|cffc8b68e" .. raw .. "|r"
                end
                return "|cff8eb0ca" .. raw .. "|r"
            end

            local pool = self._questListRows or {}
            local needed = #rows
            self:EnsureQuestListPoolSize(needed)
            local poolLimit = self._questListPoolCount or #pool
            local lastVisibleRow = nil
            local estH = 0
            for ri = 1, poolLimit do
                local row = pool[ri]
                local entry = rows[ri]
                row.questID = nil
                row.eventKey = nil
                row._pickerMode = nil
                row._isCatalogHeader = false
                if entry and row then
                    if entry.headerKey then
                        row._isCatalogHeader = true
                        if row.check then row.check:Hide() end
                        if row.tagFs then row.tagFs:Hide() end
                        if row.headerBar then row.headerBar:Show() end
                        row.labelFs:ClearAllPoints()
                        row.labelFs:SetPoint("LEFT", row, "LEFT", 10, 0)
                        row.labelFs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                        row.labelFs:SetJustifyH("LEFT")
                        local hk = entry.headerKey or ""
                        local ht = LocaleRow(hk, hk)
                        row.labelFs:SetText("|cffcccccc" .. ht .. "|r")
                        row:SetHeight(hdrRowH)
                        estH = estH + hdrRowH + 2
                    elseif entry.eventKey and isWorldEvents then
                        row._pickerMode = "worldEvents"
                        row.eventKey = entry.eventKey
                        if row.headerBar then row.headerBar:Hide() end
                        if row.tagFs then
                            row.tagFs:Show()
                            row.tagFs:SetWidth(tagColW)
                            row.tagFs:SetText(TagText(entry))
                        end
                        if row.check then row.check:Show() end
                        row.labelFs:ClearAllPoints()
                        row.labelFs:SetPoint("LEFT", row.tagFs, "RIGHT", 6, 0)
                        row.labelFs:SetPoint("RIGHT", row.check, "LEFT", -8, 0)
                        local labelMax = 48
                        if zw and zw > 0 then
                            labelMax = math.max(24, math.floor((zw - tagColW - pickColW - 34) / 6.2))
                        end
                        local title = entry.title or entry.label or unk
                        row.labelFs:SetText("|cffffffff" .. TruncatePickerLabel(title, labelMax) .. "|r")
                        f:SyncThemedCheck(row.check, f.IsWorldEventSelected and f:IsWorldEventSelected(entry.eventKey) == true)
                        row:SetHeight(dataRowH)
                        estH = estH + dataRowH + 2
                    elseif entry.questID then
                        row._pickerMode = entry.trackMode or tab
                        row.questID = entry.questID
                        if row.headerBar then row.headerBar:Hide() end
                        if row.tagFs then
                            row.tagFs:Show()
                            row.tagFs:SetWidth(tagColW)
                            row.tagFs:SetText(TagText(entry))
                        end
                        if row.check then row.check:Show() end
                        row.labelFs:ClearAllPoints()
                        row.labelFs:SetPoint("LEFT", row.tagFs, "RIGHT", 6, 0)
                        row.labelFs:SetPoint("RIGHT", row.check, "LEFT", -8, 0)
                        local labelMax = 48
                        if zw and zw > 0 then
                            labelMax = math.max(24, math.floor((zw - tagColW - pickColW - 34) / 6.2))
                        end
                        local title = entry.title or (RQC and RQC.ResolveQuestTitle and RQC.ResolveQuestTitle(entry.questID)) or unk
                        row.labelFs:SetText(string.format(
                            "|cffffffff%s|r |cff888888— %d|r",
                            TruncatePickerLabel(title, labelMax),
                            entry.questID
                        ))
                        f:SyncThemedCheck(row.check, f.IsQuestSelected and f:IsQuestSelected(entry.questID, row._pickerMode) == true)
                        row:SetHeight(dataRowH)
                        estH = estH + dataRowH + 2
                    else
                        entry = nil
                    end
                    if entry then
                        row:ClearAllPoints()
                        if not lastVisibleRow then
                            row:SetPoint("TOPLEFT", self.questCatalogScrollChild, "TOPLEFT", 0, 0)
                        else
                            row:SetPoint("TOPLEFT", lastVisibleRow, "BOTTOMLEFT", 0, -2)
                        end
                        row:SetWidth(zw)
                        lastVisibleRow = row
                        row:Show()
                    else
                        if row.check then row.check:Show() end
                        f:SyncThemedCheck(row.check, false)
                        if row.headerBar then row.headerBar:Hide() end
                        row:ClearAllPoints()
                        row:Hide()
                    end
                elseif row then
                    f:SyncThemedCheck(row.check, false)
                    if row.check then row.check:Show() end
                    if row.tagFs then row.tagFs:Hide() end
                    if row.headerBar then row.headerBar:Hide() end
                    row:ClearAllPoints()
                    row:Hide()
                end
            end

            if self.questCatalogScrollChild then
                self.questCatalogScrollChild:SetHeight(math.max(28, estH > 0 and estH or 40))
                self.questCatalogScrollChild:SetWidth(math.max(160, zw))
            end
            if Factory.UpdateScrollBarVisibility and self.questCatalogScroll then
                Factory:UpdateScrollBarVisibility(self.questCatalogScroll)
            end
        end
        f.RefreshQuestListRows = f.RefreshPickerListRows

        function f:IsQuestTrackEnabledInReminder(reminder)
            if not reminder then return false end
            local wqE = FindTriggerEntry(reminder, KIND.WORLD_QUEST_ACTIVE)
            if wqE and wqE.enabled ~= false then return true end
            local evE = FindTriggerEntry(reminder, KIND.CONTENT_EVENT_ACTIVE)
            if evE and evE.enabled ~= false then return true end
            local weE = FindTriggerEntry(reminder, KIND.WORLD_EVENT_ACTIVE)
            if weE and weE.enabled ~= false then return true end
            return false
        end

        function f:ApplyQuestTrackControlsState()
            if self.ApplyAlertLocationQuestMutex then self:ApplyAlertLocationQuestMutex() end
            local zoneBlocks = self.zoneCheck and self.zoneCheck:GetChecked() == true
            local on = self.questTrackCheck and self.questTrackCheck:GetChecked()
            local detailAlpha = (on and not zoneBlocks) and 1 or 0.38
            if self.questPickerCard then
                if on then self.questPickerCard:Show() else self.questPickerCard:Hide() end
            end
            if self.questTrackLabel and self.questTrackLabel.SetTextColor then
                self.questTrackLabel:SetTextColor(labelBody[1] * detailAlpha + 0.3,
                    labelBody[2] * detailAlpha + 0.3, labelBody[3] * detailAlpha + 0.3)
            end
            if on and self._activeAlertTab == "quests" then
                if not self._questPickerPrimed then
                    self._questPickerPrimed = true
                end
                if self.RefreshPickerListRows then self:RefreshPickerListRows() end
            end
            if self.RefreshSelectedQuestSummary then self:RefreshSelectedQuestSummary() end
            if self.LayoutDialogHeights then self:LayoutDialogHeights() end
        end
        f.ApplyQuestDependentControlsState = f.ApplyQuestTrackControlsState

        function f:ResolveSavedQuestTrackMode(reminder)
            if not reminder then return "worldQuests" end
            local weE = FindTriggerEntry(reminder, KIND.WORLD_EVENT_ACTIVE)
            if weE and weE.enabled ~= false then
                return "worldEvents"
            end
            local evE = FindTriggerEntry(reminder, KIND.CONTENT_EVENT_ACTIVE)
            if evE and evE.enabled ~= false then
                return "contentEvents"
            end
            local wqE = FindTriggerEntry(reminder, KIND.WORLD_QUEST_ACTIVE)
            if wqE and wqE.enabled ~= false then
                return "worldQuests"
            end
            return "worldQuests"
        end

        local catalogDef = ns.ReminderSetAlertDialogZoneCatalog
            and ns.ReminderSetAlertDialogZoneCatalog.Install({
                f = f,
                L = L,
                COLORS = COLORS,
                Factory = Factory,
                FontManager = FontManager,
                ApplyVisuals = ApplyVisuals,
                borderCol = borderCol,
                cardPad = cardPad,
                RD = RD,
                scrollBarW = scrollBarW,
                innerW = innerW,
            })
        f._zoneCatalogDef = catalogDef

        function f:RefreshMapIdZonePreview()
            if not self.mapEdit or not self.mapIdZonePreview then return end
            local n = H and H.SafePositiveIntFromMapEdit(self.mapEdit)
            if not n then
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

        f._zoneDetailWidgets = {
            f.selectedZonesBlock, f.mapIdRow, mapGetIdBtn, mapEditBg, mapEdit,
            f.mapIdZonePreview, f.zoneCatalogCard,
        }

        f:LayoutDialogHeights()

        local btnW, btnH = 128, 32
        local btnGap = 10

        local saveBtn = Factory:CreateButton(f, btnW, btnH, false)
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

        local removeBtn = Factory:CreateButton(f, btnW, btnH, false)
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
            if self.ApplyAlertLocationQuestMutex then self:ApplyAlertLocationQuestMutex() end
            local zc = self.zoneCheck
            local questBlocks = self.questTrackCheck and self.questTrackCheck:GetChecked() == true
            local zoneMaster = zc and zc:GetChecked()
            local detailAlpha = (zoneMaster and not questBlocks) and 1 or 0.38
            local catDef = self._zoneCatalogDef
            local hasCat = catDef and catDef.sections and #catDef.sections > 0
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
            if self.LayoutDialogHeights then
                self:LayoutDialogHeights()
            end
        end

        f:SelectAlertTab("schedule")
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
        local n = H and H.SafePositiveIntFromMapEdit(f.mapEdit)
        if not n then return end
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
    f._zoneCatalogPrimed = false
    f._questPickerPrimed = false

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

    if f.SyncThemedCheck then
        f:SyncThemedCheck(f.dailyCheck, r.onDailyLogin or false)
        f:SyncThemedCheck(f.weeklyCheck, r.onWeeklyReset or false)
    end

    local savedDayN = nil
    if r.daysBeforeReset then
        local dbr = r.daysBeforeReset
        for di = 1, #dbr do
            local d = tonumber(dbr[di])
            if d and d > 0 and (not savedDayN or d > savedDayN) then
                savedDayN = d
            end
        end
    end
    if f.SyncThemedCheck then f:SyncThemedCheck(f.daysBeforeCheck, savedDayN ~= nil) end
    if f.daysBeforeEdit then
        if savedDayN then
            f.daysBeforeEdit:SetText(tostring(savedDayN))
        else
            f.daysBeforeEdit:SetText("3")
        end
    end
    if f.SyncDaysBeforeEditEnabled then
        f:SyncDaysBeforeEditEnabled()
    end

    local zoneSaved = r.onZoneEnter == true
    local questSaved = f.IsQuestTrackEnabledInReminder and f:IsQuestTrackEnabledInReminder(r) or false
    if zoneSaved and questSaved then
        questSaved = false
    end
    if f.SyncThemedCheck then f:SyncThemedCheck(f.zoneCheck, zoneSaved) end
    f.zoneCheck:Enable()
    f.zoneCheck:SetAlpha(1)
    f.zoneLabel:SetTextColor(0.9, 0.9, 0.9)

    f._selectedWQQuestIDs = {}
    f._selectedEventQuestIDs = {}
    f._selectedWorldEventKeys = {}
    if CopyQuestIDList then
        local wqE = FindTriggerEntry(r, KIND.WORLD_QUEST_ACTIVE)
        if wqE and type(wqE.questIDs) == "table" then
            f._selectedWQQuestIDs = CopyQuestIDList(wqE.questIDs)
        end
        local evE = FindTriggerEntry(r, KIND.CONTENT_EVENT_ACTIVE)
        if evE and type(evE.questIDs) == "table" then
            f._selectedEventQuestIDs = CopyQuestIDList(evE.questIDs)
        end
    end
    if CopyEventKeysList then
        local weE = FindTriggerEntry(r, KIND.WORLD_EVENT_ACTIVE)
        if weE and type(weE.eventKeys) == "table" then
            f._selectedWorldEventKeys = CopyEventKeysList(weE.eventKeys)
        end
    end
    local savedTrackMode = (f.ResolveSavedQuestTrackMode and f:ResolveSavedQuestTrackMode(r)) or "worldQuests"
    local RQP = ns.ReminderQuestPickerCatalog
    f._questListTab = savedTrackMode
    f._questPickerSectionIdx = (RQP and RQP.GetDefaultSectionIndexForTrackMode and RQP.GetDefaultSectionIndexForTrackMode(savedTrackMode)) or 1
    if f.questTrackCheck then
        if f.SyncThemedCheck then f:SyncThemedCheck(f.questTrackCheck, questSaved) end
    end
    if f.RefreshSelectedQuestSummary then
        f:RefreshSelectedQuestSummary()
    end

    local prof = addon.db and addon.db.profile

    if f.ApplyAlertLocationQuestMutex then
        f:ApplyAlertLocationQuestMutex()
    end
    if f.ApplyZoneDependentControlsState then
        f:ApplyZoneDependentControlsState()
    end
    if f.ApplyQuestTrackControlsState then
        f:ApplyQuestTrackControlsState()
    end
    if f.SetActiveQuestPickerSectionIdx then
        f:SetActiveQuestPickerSectionIdx(f._questPickerSectionIdx or 1)
    end
    if f.SelectAlertTab then
        f:SelectAlertTab("schedule")
    end

    f.saveBtn:SetScript("OnClick", function()
        local days = {}
        if f.daysBeforeCheck and f.daysBeforeCheck:GetChecked() and f.daysBeforeEdit then
            local n = H and H.SafePositiveIntFromMapEdit(f.daysBeforeEdit)
            if n and n >= 1 and n <= 14 then
                days[#days + 1] = math.floor(n)
            end
        end

        local zoneOn = f.zoneCheck:GetChecked() == true
        local questOn = f.questTrackCheck and f.questTrackCheck:GetChecked() == true
        if zoneOn and questOn then
            questOn = false
        end
        if questOn then
            zoneOn = false
        end
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
                    local pending = H and H.SafePositiveIntFromMapEdit(f.mapEdit)
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
            onInstanceEnter = (zoneOn and f._preserveOnInstanceEnter) and true or false,
            instanceReminder = nil,
        }
        if settings.onInstanceEnter and f._preserveInstanceReminder then
            settings.instanceReminder = {
                instanceID = f._preserveInstanceReminder.instanceID,
                difficultyID = f._preserveInstanceReminder.difficultyID,
            }
        end

        settings.questTriggers = {}
        settings.worldEventTriggers = {}
        if questOn then
            local trackMode = (f.GetActiveQuestTrackMode and f:GetActiveQuestTrackMode()) or "worldQuests"
            if trackMode == "worldQuests" then
                settings.questTriggers[1] = {
                    kind = KIND.WORLD_QUEST_ACTIVE,
                    enabled = true,
                    questIDs = CopyQuestIDList and CopyQuestIDList(f._selectedWQQuestIDs) or {},
                }
            elseif trackMode == "contentEvents" then
                settings.questTriggers[1] = {
                    kind = KIND.CONTENT_EVENT_ACTIVE,
                    enabled = true,
                    questIDs = CopyQuestIDList and CopyQuestIDList(f._selectedEventQuestIDs) or {},
                }
            elseif trackMode == "worldEvents" then
                settings.worldEventTriggers[1] = {
                    kind = KIND.WORLD_EVENT_ACTIVE,
                    enabled = true,
                    eventKeys = CopyEventKeysList and CopyEventKeysList(f._selectedWorldEventKeys) or {},
                }
            end
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

    if f._layoutReminderGrids then
        f._layoutReminderGrids()
    end

    f:Show()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if not f:IsShown() then return end
            if f.LayoutZoneCatalogSplit then f:LayoutZoneCatalogSplit() end
            if f.LayoutQuestCatalogSplit then f:LayoutQuestCatalogSplit() end
            if f.LayoutDialogHeights then f:LayoutDialogHeights() end
        end)
    end
end