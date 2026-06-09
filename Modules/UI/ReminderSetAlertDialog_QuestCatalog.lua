--[[
    Warband Nexus - Reminder Set Alert quest/event picker (view layer).
    Split from ReminderSetAlertDialog.lua (Lua 5.1 local limit).
]]

local _, ns = ...
local H = ns.ReminderSetAlertDialogHelpers

local Q = {}
ns.ReminderSetAlertDialogQuestCatalog = Q

---@param ctx table Build context (f, L, COLORS, Factory, FontManager, ApplyVisuals, borderCol, cardPad, RD, scrollBarW, innerW, labelBody, StyleCard, CreateThemedCheckbox, CreateMutexTipHost, FindTriggerEntry, KIND)
function Q.Install(ctx)
    local f = ctx.f
    local L = ctx.L
    local COLORS = ctx.COLORS
    local Factory = ctx.Factory
    local FontManager = ctx.FontManager
    local ApplyVisuals = ctx.ApplyVisuals
    local borderCol = ctx.borderCol
    local cardPad = ctx.cardPad
    local RD = ctx.RD
    local scrollBarW = ctx.scrollBarW
    local innerW = ctx.innerW
    local labelBody = ctx.labelBody
    local StyleCard = ctx.StyleCard
    local CreateThemedCheckbox = ctx.CreateThemedCheckbox
    local CreateMutexTipHost = ctx.CreateMutexTipHost
    local WireMutexHoverTip = ctx.WireMutexHoverTip
    local FindTriggerEntry = ctx.FindTriggerEntry
    local KIND = ctx.KIND
    local bgCardCol = COLORS.bgCard or { 0.08, 0.08, 0.10, 1 }
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
end