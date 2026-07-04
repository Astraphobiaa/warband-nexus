--[[
    Warband Nexus - Reminder Set Alert zone location + manual map list (view layer).
    Split from ReminderSetAlertDialog.lua (Lua 5.1 local limit).
]]

local _, ns = ...
local H = ns.ReminderSetAlertDialogHelpers

local ZP = {}
ns.ReminderSetAlertDialogZonePanel = ZP

---@param ctx table f, L, COLORS, Factory, FontManager, ApplyVisuals, borderCol, cardPad, RD, labelBody, labelMuted, StyleCard, CreateThemedCheckbox, CreateMutexTipHost, WireMutexHoverTip
function ZP.Install(ctx)
    local f = ctx.f
    local L = ctx.L
    local COLORS = ctx.COLORS
    local function PickerBrightHex()
        return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
    end
    local function PickerMutedHex()
        return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cff888888"
    end
    local function PickerLabelHex()
        return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cff9eb0ca"
    end
    local Factory = ctx.Factory
    local FontManager = ctx.FontManager
    local ApplyVisuals = ctx.ApplyVisuals
    local borderCol = ctx.borderCol
    local cardPad = ctx.cardPad
    local RD = ctx.RD
    local labelBody = ctx.labelBody
    local labelMuted = ctx.labelMuted
    local StyleCard = ctx.StyleCard
    local CreateThemedCheckbox = ctx.CreateThemedCheckbox
    local CreateMutexTipHost = ctx.CreateMutexTipHost
    local WireMutexHoverTip = ctx.WireMutexHoverTip
    local B = ns.ReminderServiceBridge
    local SafeUIMapDisplayName = B and B.SafeUIMapDisplayName
    local ManualRowTagText = H and H.ManualRowTagText
        local locationCard = H.Container(f.panelZone, 1, RD.locationBaseH, false)
        locationCard:SetPoint("TOPLEFT", f.panelZone, "TOPLEFT", 0, 0)
        locationCard:SetPoint("TOPRIGHT", f.panelZone, "TOPRIGHT", 0, 0)
        StyleCard(locationCard)
        f.locationCard = locationCard

        local locInner = H.Container(locationCard, 1, 1, false)
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

        f.selectedZonesBlock = H.Container(locInner, 1, 1, false)
        f.selectedZonesBlock:SetPoint("TOPLEFT", zoneCheck, "BOTTOMLEFT", 0, -10)
        f.selectedZonesBlock:SetPoint("TOPRIGHT", locInner, "TOPRIGHT", 0, -10)

        local selectedToolbar = H.Container(f.selectedZonesBlock, 1, 28, false)
        selectedToolbar:SetPoint("TOPLEFT", f.selectedZonesBlock, "TOPLEFT", 0, 0)
        selectedToolbar:SetPoint("TOPRIGHT", f.selectedZonesBlock, "TOPRIGHT", 0, 0)
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

        local mapIdRow = H.Container(selectedToolbar, 220, 28, false)
        mapIdRow:SetPoint("RIGHT", selectedToolbar, "RIGHT", 0, 0)

        f.mapIdRow = mapIdRow

        local mapGetIdBtn = H.Button(mapIdRow, 72, 26, false)
        assert(mapGetIdBtn, "ReminderSetAlertDialog mapGetIdBtn requires Factory")
        mapGetIdBtn:SetPoint("LEFT", mapIdRow, "LEFT", 0, 0)
        local mapGetIdTxt = FontManager:CreateFontString(mapGetIdBtn, "small", "OVERLAY")
        mapGetIdTxt:SetPoint("CENTER")
        mapGetIdTxt:SetText((L and L["REMINDER_ZONE_GET_ID"]) or "Get ID")
        f.mapGetIdBtn = mapGetIdBtn

        local mapEditBg = H.Container(mapIdRow, 120, 26, false)
        mapEditBg:SetPoint("LEFT", mapGetIdBtn, "RIGHT", 6, 0)
        mapEditBg:SetPoint("RIGHT", mapIdRow, "RIGHT", 0, 0)
        if ApplyVisuals then
            local chrome = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or COLORS.bgCard
            ApplyVisuals(mapEditBg, chrome, { borderCol[1], borderCol[2], borderCol[3], borderCol[4] })
        end
        mapEditBg:EnableMouse(true)

        local mapEdit = H.EditBox(mapEditBg)
        assert(mapEdit, "ReminderSetAlertDialog mapEdit requires Factory")
        mapEdit:SetPoint("LEFT", mapEditBg, "LEFT", 6, 0)
        mapEdit:SetPoint("RIGHT", mapEditBg, "RIGHT", -6, 0)
        mapEdit:SetHeight(22)
        mapEdit:SetNumeric(true)
        mapEdit:SetMaxLetters(12)
        ns.UI_SetTextColorRole(mapEdit, "Bright")
        mapEdit:SetAutoFocus(false)
        mapEditBg:SetScript("OnMouseDown", function()
            mapEdit:SetFocus()
        end)
        f.mapEditBg = mapEditBg
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
        ns.UI_SetTextColorRole(f.mapsManualEmpty, "Dim")
        f.mapsManualEmpty:SetText((L and L["REMINDER_ZONE_SELECTED_EMPTY"])
            or (L and L["REMINDER_ZONE_MANUAL_EMPTY"])
            or "No zones selected. Add from the browser below or enter a map ID.")

        f.mapsManualRowsHost = H.Container(f.selectedZonesBlock, 1, 1, false)
        f.mapsManualRowsHost:SetPoint("TOPLEFT", selectedToolbar, "BOTTOMLEFT", 0, -4)
        f.mapsManualRowsHost:SetPoint("TOPRIGHT", f.selectedZonesBlock, "TOPRIGHT", 0, -4)
        if f.mapsManualRowsHost.SetClipsChildren then
            f.mapsManualRowsHost:SetClipsChildren(true)
        end

        local MAN_ROW_H = 26
        local MAN_TAG_W = 54
        local MAN_RM_W = 62
        local MAN_ROW_GAP = 4
        local MAX_MANUAL_MAP_ROWS = 28
        local UIMT = Enum and Enum.UIMapType

        local ManualRowTagText = H and H.ManualRowTagText

        f._manualMapRows = {}
        for mri = 1, MAX_MANUAL_MAP_ROWS do
            local row = H.Container(f.mapsManualRowsHost, 1, MAN_ROW_H, false)
            row:Hide()

            row.tagFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.tagFs:SetWidth(MAN_TAG_W)
            row.tagFs:SetPoint("LEFT", row, "LEFT", mmPad, 0)
            row.tagFs:SetJustifyH("CENTER")

            row.rmBtn = H.Button(row, MAN_RM_W, 22, false)
            assert(row.rmBtn, "ReminderSetAlertDialog manual row remove requires Factory")
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
                    ns.UI_SetTextColorRole(self.zoneLabel, "Bright")
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
                            PickerBrightHex() .. "%s|r " .. PickerMutedHex() .. "— %d|r",
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

        function f:RefreshMapIdZonePreview()
            if not self.mapEdit or not self.mapIdZonePreview then return end
            local n = H and H.SafePositiveIntFromMapEdit(self.mapEdit)
            if not n then
                self.mapIdZonePreview:SetText("")
                self.mapIdZonePreview:Hide()
                return
            end
            local nm = SafeUIMapDisplayName and SafeUIMapDisplayName(n)
            local Lz = ns.L
            if nm then
                local prefix = (Lz and Lz["REMINDER_ZONE_NAME_LABEL"]) or "Zone"
                self.mapIdZonePreview:SetText(PickerLabelHex() .. prefix .. ":|r " .. PickerBrightHex() .. nm .. "|r " .. PickerMutedHex() .. "— "
                    .. tostring(n) .. "|r")
            else
                self.mapIdZonePreview:SetText("|cff888888" .. ((Lz and Lz["REMINDER_ZONE_NAME_UNKNOWN"]) or "Unknown map ID") .. "|r")
            end
            self.mapIdZonePreview:Show()
        end

        if f.mapEdit then
            f.mapEdit:SetScript("OnTextChanged", function()
                f:RefreshMapIdZonePreview()
            end)
        end
end