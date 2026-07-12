--[[ To-Do plan reminder "Set Alert" dialog (view layer). Data entry points: ns.ReminderServiceBridge. ]]

local ADDON_NAME, ns = ...
local issecretvalue = issecretvalue

ns.ReminderSetAlertDialog = ns.ReminderSetAlertDialog or {}

--[[ WN_FACTORY: Loads after SharedWidgets / WindowFactory in `WarbandNexus.toc`.
     `Factory` is resolved inside `Show` on first build (runtime).

     Remaining intentional raw `CreateFrame`: none — modal shell + hosts via `H.Container` / Factory scroll/edit.
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
        local labelMuted = COLORS.textMuted or { 0.78, 0.78, 0.82 }
        local labelBody = COLORS.textBright or { 0.94, 0.94, 0.96 }
        local controlChrome = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop())
            or COLORS.bgCard or { 0.08, 0.08, 0.10, 1 }

        local f = H.Container(UIParent, dialogW, dialogH, false, "WarbandNexus_ReminderDialog")
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
            local shell = (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop())
                or COLORS.bg or { 0.04, 0.04, 0.06, 0.98 }
            local ba = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.75 or 0.9
            ApplyVisuals(f, shell, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], ba })
        end

        if ns.UI_RegisterScaledFrame then
            ns.UI_RegisterScaledFrame(f)
        elseif ns.UI_ApplyAddonUIScale then
            ns.UI_ApplyAddonUIScale(f)
        end

        local rdShell = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
        local rdInset = rdShell.FRAME_CONTENT_INSET or 2
        local rdHdrH = rdShell.HEADER_BAR_HEIGHT or 40
        local header = H.Container(f, 1, rdHdrH, false)
        header:SetHeight(rdHdrH)
        header:SetPoint("TOPLEFT", rdInset, -rdInset)
        header:SetPoint("TOPRIGHT", -rdInset, -rdInset)
        header:SetFrameLevel(f:GetFrameLevel() + 6)
        f._reminderHeaderShell = header
        if ApplyVisuals then
            ApplyVisuals(header, {COLORS.accentDark[1], COLORS.accentDark[2], COLORS.accentDark[3], 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.55})
        end

        local closeBtn = Factory:CreateButton(header, 28, 28, false)
        closeBtn:SetSize(28, 28)
        closeBtn:SetPoint("RIGHT", header, "RIGHT", -afterEl, 0)
        if ApplyVisuals then
            local closeBg = (ns.UI_GetCloseButtonBackdrop and ns.UI_GetCloseButtonBackdrop()) or controlChrome
            ApplyVisuals(closeBtn, closeBg, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.45 })
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
        local closeR, closeG, closeB = (ns.UI_GetSemanticRedColor and ns.UI_GetSemanticRedColor()) or 0.92, 0.35, 0.35
        closeIcon:SetVertexColor(closeR, closeG, closeB)
        closeBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        local headerTitle = FontManager:CreateFontString(header, "title", "OVERLAY")
        headerTitle:SetPoint("LEFT", header, "LEFT", afterEl, 0)
        headerTitle:SetPoint("RIGHT", closeBtn, "LEFT", -afterEl, 0)
        headerTitle:SetJustifyH("LEFT")
        headerTitle:SetMaxLines(1)
        headerTitle:SetText((L and L["SET_ALERT_TITLE"]) or "Set Alert")
        ns.UI_SetTextColorRole(headerTitle, "Bright")
        f.headerTitle = headerTitle

        header:EnableMouse(true)
        if ns.WindowManager and ns.WindowManager.InstallDragHandler then
            ns.WindowManager:InstallDragHandler(header, f)
        end

        local planRow = H.Container(f, 1, 1, false)
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

        local planTypeBadge = H.Container(planRow, 1, 1, false)
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

        local bodyHost = H.Container(f, 1, 1, false)
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
        local tabBar = H.Container(bodyHost, 1, 1, false)
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

        local contentHost = H.Container(bodyHost, 1, 1, false)
        contentHost:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
        contentHost:SetPoint("BOTTOMRIGHT", bodyHost, "BOTTOMRIGHT", 0, 0)
        contentHost:SetClipsChildren(true)
        f.contentHost = contentHost

        local function MakeTabPanel(name)
            local panel = H.Container(contentHost, 1, 1, false)
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
                        local idle = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or controlChrome
                        ApplyVisuals(b,
                            sel and { COLORS.accent[1] * 0.42, COLORS.accent[2] * 0.42, COLORS.accent[3] * 0.42, 1 }
                                or idle,
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
            ns.UI_SetTextColorRole(fs, "Bright")
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
            local host = H.Container(parent, 1, 1, false)
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
        f._themeCards = f._themeCards or {}

        local function StyleCard(card)
            if card then
                f._themeCards[#f._themeCards + 1] = card
            end
            if ApplyVisuals then
                local c = ns.UI_COLORS or COLORS
                local bg = c.bgCard or controlChrome
                local bc = c.border or borderCol
                ApplyVisuals(card,
                    { bg[1], bg[2], bg[3], bg[4] or 1 },
                    { bc[1], bc[2], bc[3], bc[4] or borderCol[4] })
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

        local whenCard = H.Container(f.panelSchedule, 1, 1, false)
        whenCard:SetPoint("TOPLEFT", f.panelSchedule, "TOPLEFT", 0, 0)
        whenCard:SetPoint("TOPRIGHT", f.panelSchedule, "TOPRIGHT", 0, 0)
        whenCard:SetHeight(RD.whenCardH)
        StyleCard(whenCard)
        f.whenCard = whenCard

        local whenInner = H.Container(whenCard, 1, 1, false)
        whenInner:SetPoint("TOPLEFT", whenCard, "TOPLEFT", cardPad, -cardPad)
        whenInner:SetPoint("BOTTOMRIGHT", whenCard, "BOTTOMRIGHT", -cardPad, cardPad)

        local secSchedule = FontManager:CreateFontString(whenInner, "subtitle", "OVERLAY")
        secSchedule:SetPoint("TOPLEFT", whenInner, "TOPLEFT", 0, 0)
        secSchedule:SetPoint("TOPRIGHT", whenInner, "TOPRIGHT", 0, 0)
        secSchedule:SetJustifyH("LEFT")
        secSchedule:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        secSchedule:SetText((L and L["SET_ALERT_SECTION_SCHEDULE"]) or "Login & Resets")

        local whenOptsRow = H.Container(whenInner, 1, 1, false)
        whenOptsRow:SetPoint("TOPLEFT", secSchedule, "BOTTOMLEFT", 0, -8)
        whenOptsRow:SetPoint("TOPRIGHT", secSchedule, "BOTTOMRIGHT", 0, -8)
        whenOptsRow:SetPoint("BOTTOMLEFT", whenInner, "BOTTOMLEFT", 0, 0)
        whenOptsRow:SetPoint("BOTTOMRIGHT", whenInner, "BOTTOMRIGHT", 0, 0)
        whenOptsRow:SetHeight(RD.compactOptH)
        f.whenOptsRow = whenOptsRow

        local whenOptCols = {}
        for wi = 1, 3 do
            whenOptCols[wi] = H.Container(whenOptsRow, 1, 1, false)
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

        local daysEditBg = H.Container(daysCol, 40, 24, false)
        daysEditBg:SetPoint("LEFT", f.daysBeforeCheck, "RIGHT", 6, 0)
        if ApplyVisuals then
            ApplyVisuals(daysEditBg, controlChrome, { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end
        daysEditBg:EnableMouse(true)

        local daysBeforeEdit = H.EditBox(daysEditBg)
        daysBeforeEdit:SetPoint("LEFT", daysEditBg, "LEFT", 4, 0)
        daysBeforeEdit:SetPoint("RIGHT", daysEditBg, "RIGHT", -4, 0)
        daysBeforeEdit:SetHeight(20)
        daysBeforeEdit:SetNumeric(true)
        daysBeforeEdit:SetMaxLetters(2)
        daysBeforeEdit:SetText("3")
        ns.UI_SetTextColorRole(daysBeforeEdit, "Bright")
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

        if ns.ReminderSetAlertDialogZonePanel and ns.ReminderSetAlertDialogZonePanel.Install then
            ns.ReminderSetAlertDialogZonePanel.Install({
                f = f,
                L = L,
                COLORS = COLORS,
                Factory = Factory,
                FontManager = FontManager,
                ApplyVisuals = ApplyVisuals,
                borderCol = borderCol,
                cardPad = cardPad,
                RD = RD,
                labelBody = labelBody,
                labelMuted = labelMuted,
                StyleCard = StyleCard,
                CreateThemedCheckbox = CreateThemedCheckbox,
                CreateMutexTipHost = CreateMutexTipHost,
                WireMutexHoverTip = WireMutexHoverTip,
            })
        end

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

        f._zoneCatalogPrimed = false

        if ns.ReminderSetAlertDialogQuestCatalog and ns.ReminderSetAlertDialogQuestCatalog.Install then
            ns.ReminderSetAlertDialogQuestCatalog.Install({
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
                labelBody = labelBody,
                StyleCard = StyleCard,
                CreateThemedCheckbox = CreateThemedCheckbox,
                CreateMutexTipHost = CreateMutexTipHost,
                WireMutexHoverTip = WireMutexHoverTip,
                FindTriggerEntry = FindTriggerEntry,
                KIND = KIND,
            })
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

        f._zoneDetailWidgets = {
            f.selectedZonesBlock, f.mapIdRow, f.mapGetIdBtn, f.mapEditBg, f.mapEdit,
            f.mapIdZonePreview, f.zoneCatalogCard,
        }

        f:LayoutDialogHeights()

        local btnW, btnH = 128, 32
        local btnGap = 10

        local saveBtn = H.Button(f, btnW, btnH, false)
        saveBtn:SetSize(btnW, btnH)
        saveBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -btnGap * 0.5, 12)
        local saveTxt = FontManager:CreateFontString(saveBtn, "body", "OVERLAY")
        saveTxt:SetPoint("CENTER")
        saveTxt:SetText((L and L["SAVE"]) or "Save")
        if ns.UI_SetTextColorRole then ns.UI_SetTextColorRole(saveTxt, "Bright") end
        if ApplyVisuals then
            local bg = ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop() or { COLORS.accent[1] * 0.35, COLORS.accent[2] * 0.35, COLORS.accent[3] * 0.35, 1 }
            local br = ns.UI_GetBorderStrokeColor and ns.UI_GetBorderStrokeColor() or COLORS.accent
            ApplyVisuals(saveBtn, bg, br)
        end
        f.saveBtn = saveBtn

        local removeBtn = H.Button(f, btnW, btnH, false)
        removeBtn:SetSize(btnW, btnH)
        removeBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", btnGap * 0.5, 12)
        local removeTxt = FontManager:CreateFontString(removeBtn, "body", "OVERLAY")
        removeTxt:SetPoint("CENTER")
        removeTxt:SetText((L and L["REMOVE_ALERT"]) or "Remove Alert")
        if ns.UI_SetTextColorRole then ns.UI_SetTextColorRole(removeTxt, "Bright") end
        if ApplyVisuals then
            if ns.UI_GetSemanticNegativeCard then
                local negBg, negBorder = ns.UI_GetSemanticNegativeCard(false)
                ApplyVisuals(removeBtn, negBg, negBorder)
            else
                ApplyVisuals(removeBtn, { 0.34, 0.1, 0.1, 1 }, { 0.82, 0.22, 0.22, 1 })
            end
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

        function f:ApplyThemeChrome()
            local c = ns.UI_COLORS or COLORS
            local shell = (ns.UI_GetExternalShellBackdrop and ns.UI_GetExternalShellBackdrop()) or c.bg
            local ba = (ns.UI_IsLightMode and ns.UI_IsLightMode()) and 0.75 or 0.9
            if ApplyVisuals and shell and c.accent then
                ApplyVisuals(self, shell, { c.accent[1], c.accent[2], c.accent[3], ba })
            end
            if self._reminderHeaderShell and ApplyVisuals and c.accentDark then
                ApplyVisuals(self._reminderHeaderShell,
                    { c.accentDark[1], c.accentDark[2], c.accentDark[3], 1 },
                    { c.accent[1], c.accent[2], c.accent[3], 0.55 })
            end
            local cards = self._themeCards
            if cards and ApplyVisuals then
                local bg = c.bgCard or controlChrome
                local bc = c.border or borderCol
                for ci = 1, #cards do
                    local card = cards[ci]
                    if card then
                        ApplyVisuals(card,
                            { bg[1], bg[2], bg[3], bg[4] or 1 },
                            { bc[1], bc[2], bc[3], bc[4] or borderCol[4] })
                    end
                end
            end
            if self.saveBtn and ApplyVisuals and c.accent then
                ApplyVisuals(self.saveBtn,
                    { c.accent[1] * 0.35, c.accent[2] * 0.35, c.accent[3] * 0.35, 1 },
                    { c.accent[1], c.accent[2], c.accent[3], 0.95 })
            end
            if self.removeBtn and ApplyVisuals and ns.UI_GetSemanticNegativeCard then
                local negBg, negBorder = ns.UI_GetSemanticNegativeCard(false)
                ApplyVisuals(self.removeBtn, negBg, negBorder)
            end
            if self.SelectAlertTab then
                self:SelectAlertTab(self._activeAlertTab or "schedule")
            end
            if ns.UI_RefreshRoleTextColors then
                ns.UI_RefreshRoleTextColors()
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
    if pts and not (issecretvalue and issecretvalue(pts)) and tonumber(pts) and f.planPointsFs then
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
    f.planTitleFs:SetText(displayName)
    if ns.UI_SetTextColorRole then ns.UI_SetTextColorRole(f.planTitleFs, "Bright") end

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
        ns.UI_SetTextColorRole(f.zoneLabel, "Bright")
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
    ns.UI_SetTextColorRole(f.zoneLabel, "Bright")

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

function ns.ReminderSetAlertDialog.RefreshTheme()
    local f = reminderDialog
    if f and f:IsShown() and f.ApplyThemeChrome then
        f:ApplyThemeChrome()
    end
end