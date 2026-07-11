--[[
    Warband Nexus - Reminder Set Alert zone catalog picker (view layer).
    Split from ReminderSetAlertDialog.lua (Lua 5.1 local limit).
]]

local _, ns = ...
local H = ns.ReminderSetAlertDialogHelpers

local Z = {}
ns.ReminderSetAlertDialogZoneCatalog = Z

---@param ctx table f, L, COLORS, Factory, FontManager, ApplyVisuals, borderCol, cardPad, RD, scrollBarW, innerW
---@return table|nil catalogDef ns.ReminderZoneCatalog when installed
function Z.Install(ctx)
    local f = ctx.f
    local L = ctx.L
    local COLORS = ctx.COLORS
    local function PickerBrightHex()
        return (ns.UI_GetBrightHex and ns.UI_GetBrightHex()) or (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
    end
    local function PickerMutedHex()
        return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cff888888"
    end
    local Factory = ctx.Factory
    local FontManager = ctx.FontManager
    local ApplyVisuals = ctx.ApplyVisuals
    local borderCol = ctx.borderCol
    local cardPad = ctx.cardPad
    local RD = ctx.RD
    local scrollBarW = ctx.scrollBarW
    local innerW = ctx.innerW
    local B = ns.ReminderServiceBridge
    local UniqueSortedInts = B and B.UniqueSortedInts
    local SafeUIMapDisplayName = B and B.SafeUIMapDisplayName
    local BindCatalogMouseWheel = H and H.BindCatalogMouseWheel
    local TruncatePickerLabel = H and H.TruncatePickerLabel
    local function LocaleOr(key, fallback)
        if H and H.LocaleOr then return H.LocaleOr(L, key, fallback) end
        return fallback or key or ""
    end
        local bgCardColCatalog = COLORS.bgCard or { 0.08, 0.08, 0.10, 1 }
        f.zoneCatalogCard = H.Container(f.panelZone, 1, 1, false)
        f.zoneCatalogCard:SetPoint("TOPLEFT", f.locationCard, "BOTTOMLEFT", 0, -8)
        f.zoneCatalogCard:SetPoint("BOTTOMRIGHT", f.panelZone, "BOTTOMRIGHT", 0, 0)
        f.zoneCatalogCard:SetClipsChildren(true)

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
        zoneCatHint:SetMaxLines(2)
        ns.UI_SetTextColorRole(zoneCatHint, "Dim")
        zoneCatHint:SetText((L and L["REMINDER_ZONE_CATALOG_HINT_SHORT"])
            or (L and L["REMINDER_ZONE_CATALOG_HINT"])
            or "Pick an expansion, then Add on the zones you need.")

        local zbScrollW = scrollBarW
        local splitGap = RD.splitGap
        local expInnerW = RD.expColW
        local expPanelOuterW = expInnerW + 4

        local mapsBody = H.Container(f.zoneCatalogCard, 1, 1, false)
        mapsBody:SetPoint("TOPLEFT", zoneCatHint, "BOTTOMLEFT", 0, -8)
        mapsBody:SetPoint("BOTTOMRIGHT", f.zoneCatalogCard, "BOTTOMRIGHT", -cardPad, zcPad)
        f.zoneMapsBody = mapsBody

        local colHeadRow = H.Container(mapsBody, 1, 18, false)
        colHeadRow:SetPoint("TOPLEFT", mapsBody, "TOPLEFT", 0, 0)
        colHeadRow:SetPoint("TOPRIGHT", mapsBody, "TOPRIGHT", 0, 0)
        f.zoneColHeadRow = colHeadRow

        local expHead = FontManager:CreateFontString(colHeadRow, "subtitle", "OVERLAY")
        expHead:SetPoint("TOPLEFT", colHeadRow, "TOPLEFT", 0, 0)
        expHead:SetWidth(expInnerW)
        expHead:SetJustifyH("LEFT")
        expHead:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        expHead:SetText((L and L["REMINDER_ZONE_CATALOG_EXPANSIONS_LABEL"]) or "Expansion")
        f.zoneExpHead = expHead

        local mapsHead = FontManager:CreateFontString(colHeadRow, "subtitle", "OVERLAY")
        mapsHead:SetPoint("TOPLEFT", colHeadRow, "TOPLEFT", expPanelOuterW + splitGap, 0)
        mapsHead:SetPoint("TOPRIGHT", colHeadRow, "TOPRIGHT", 0, 0)
        mapsHead:SetJustifyH("LEFT")
        mapsHead:SetTextColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3])
        mapsHead:SetText((L and L["REMINDER_ZONE_CATALOG_MAPS_LABEL"]) or "Maps")
        f.mapsHead = mapsHead

        local zonePickSplit = H.Container(mapsBody, 1, 1, false)
        zonePickSplit:SetPoint("TOPLEFT", colHeadRow, "BOTTOMLEFT", 0, -8)
        zonePickSplit:SetPoint("BOTTOMRIGHT", mapsBody, "BOTTOMRIGHT", 0, 0)
        f.zonePickSplit = zonePickSplit

        local expPanel = H.Container(zonePickSplit, expPanelOuterW, 1, false)
        expPanel:SetPoint("TOPLEFT", zonePickSplit, "TOPLEFT", 0, 0)
        expPanel:SetPoint("BOTTOMLEFT", zonePickSplit, "BOTTOMLEFT", 0, 0)
        if expPanel.SetClipsChildren then
            expPanel:SetClipsChildren(true)
        end
        f.zoneExpPanel = expPanel

        local expListHost = H.Container(expPanel, 1, 1, false)
        expListHost:SetPoint("TOPLEFT", expPanel, "TOPLEFT", 0, 0)
        expListHost:SetPoint("BOTTOMRIGHT", expPanel, "BOTTOMRIGHT", 0, 0)
        if expListHost.SetClipsChildren then
            expListHost:SetClipsChildren(true)
        end
        f.zoneExpScrollChild = expListHost

        local splitLine = Factory and Factory.CreateThemeDivider and Factory:CreateThemeDivider(zonePickSplit, {
            orientation = "vertical",
            variant = "section",
            thickness = 1,
        })
        if splitLine then
            splitLine:SetPoint("TOPLEFT", expPanel, "TOPRIGHT", math.floor(splitGap * 0.5), 0)
            splitLine:SetPoint("BOTTOMLEFT", expPanel, "BOTTOMRIGHT", math.ceil(splitGap * 0.5), 0)
        end
        f.zoneSplitLine = splitLine

        local mapsPanel = H.Container(zonePickSplit, 1, 1, false)
        mapsPanel:SetPoint("TOPLEFT", zonePickSplit, "TOPLEFT", expPanelOuterW + splitGap, 0)
        mapsPanel:SetPoint("BOTTOMRIGHT", zonePickSplit, "BOTTOMRIGHT", 0, 0)
        if mapsPanel.SetClipsChildren then
            mapsPanel:SetClipsChildren(true)
        end
        if zonePickSplit.SetClipsChildren then
            zonePickSplit:SetClipsChildren(true)
        end
        f.zoneMapsPanel = mapsPanel

        local mapsListColHead = H.Container(mapsPanel, 1, 16, false)
        mapsListColHead:SetPoint("TOPLEFT", mapsPanel, "TOPLEFT", 0, 0)
        mapsListColHead:SetPoint("TOPRIGHT", mapsPanel, "TOPRIGHT", 0, 0)
        f.mapsListColHead = mapsListColHead

        local tagColHead = FontManager:CreateFontString(mapsListColHead, "small", "OVERLAY")
        tagColHead:SetWidth(RD.tagColW)
        tagColHead:SetPoint("LEFT", mapsListColHead, "LEFT", 8, 0)
        tagColHead:SetJustifyH("CENTER")
        ns.UI_SetTextColorRole(tagColHead, "Dim")
        tagColHead:SetText((L and L["REMINDER_ZONE_CATALOG_COL_TYPE"]) or "Type")

        local addColHead = FontManager:CreateFontString(mapsListColHead, "small", "OVERLAY")
        addColHead:SetWidth(RD.addBtnW)
        addColHead:SetPoint("RIGHT", mapsListColHead, "RIGHT", -6, 0)
        addColHead:SetJustifyH("CENTER")
        ns.UI_SetTextColorRole(addColHead, "Dim")
        addColHead:SetText((L and L["REMINDER_ZONE_CATALOG_ADD"]) or "Add")

        local nameColHead = FontManager:CreateFontString(mapsListColHead, "small", "OVERLAY")
        nameColHead:SetPoint("LEFT", tagColHead, "RIGHT", 6, 0)
        nameColHead:SetPoint("RIGHT", addColHead, "LEFT", -8, 0)
        nameColHead:SetJustifyH("LEFT")
        ns.UI_SetTextColorRole(nameColHead, "Dim")
        nameColHead:SetText((L and L["REMINDER_ZONE_CATALOG_COL_MAP"]) or "Map")

        local zScroll = H.ScrollFrame(mapsPanel)
        assert(zScroll, "ReminderSetAlertDialog zone catalog scroll requires Factory")
        zScroll:SetPoint("TOPLEFT", mapsListColHead, "BOTTOMLEFT", 0, -4)
        local zbLane = (ns.UI_GetVerticalScrollbarLaneReserve and ns.UI_GetVerticalScrollbarLaneReserve()) or (zbScrollW + 4)
        zScroll:SetPoint("BOTTOMRIGHT", mapsPanel, "BOTTOMRIGHT", -zbLane, 0)
        local mapsBarCol = Factory.CreateBareScrollBarColumn and Factory:CreateBareScrollBarColumn(mapsPanel, zbScrollW)
            or Factory:CreateScrollBarColumn(mapsPanel, zbScrollW, 0, 0)
        if Factory.EnsureScrollBarColumnSync and mapsBarCol then
            Factory:EnsureScrollBarColumnSync(zScroll, mapsBarCol, { width = zbScrollW, gap = 4 })
        elseif mapsBarCol and zScroll.ScrollBar and Factory.PositionScrollBarInContainer then
            Factory:PositionScrollBarInContainer(zScroll.ScrollBar, mapsBarCol, 0)
        end
        f.mapsBarCol = mapsBarCol

        f._catalogExpBtns = {}
        f._catalogExpansionIdx = 1

        local catalogDef = ns.ReminderZoneCatalog
        local expBtnH = 28
        local expBtnGap = 6
        if catalogDef and catalogDef.sections and #catalogDef.sections > 0 then
            for ei = 1, #catalogDef.sections do
                local sec = catalogDef.sections[ei]
                local eb = H.Button(expListHost, expInnerW, expBtnH, false)
                if eb then
                    if ei == 1 then
                        eb:SetPoint("TOPLEFT", expListHost, "TOPLEFT", 0, 0)
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
            end
            local totalExpH = #catalogDef.sections * (expBtnH + expBtnGap) - expBtnGap
            expListHost:SetHeight(math.max(totalExpH, 40))
        end

        local zListInitialW = math.max(200, innerW - cardPad * 2 - expPanelOuterW - splitGap - zbScrollW - 16)
        local zChild = H.Container(zScroll, zListInitialW, 1, false)
        zScroll:SetScrollChild(zChild)
        f.zoneCatalogScroll = zScroll
        f.zoneCatalogScrollChild = zChild
        f._zoneCatalogLayout = {
            scrollBarW = zbScrollW,
            splitGap = splitGap,
            addBtnW = RD.addBtnW,
            tagColW = RD.tagColW,
            rowH = RD.catalogRowH,
            hdrH = RD.catalogHdrH,
            expInnerW = expInnerW,
            expPanelOuterW = expPanelOuterW,
        }

        local function LayoutZoneCatalogSplit()
            if not f.zoneMapsBody or not f.zoneExpPanel or not f.zoneMapsPanel then return end
            local lay = f._zoneCatalogLayout
            if not lay then return end
            local expW = RD.expColW
            local outerW = expW + 4
            lay.expInnerW = expW
            lay.expPanelOuterW = outerW

            f.zoneExpPanel:SetWidth(outerW)
            f.zoneExpPanel:ClearAllPoints()
            f.zoneExpPanel:SetPoint("TOPLEFT", f.zonePickSplit, "TOPLEFT", 0, 0)
            f.zoneExpPanel:SetPoint("BOTTOMLEFT", f.zonePickSplit, "BOTTOMLEFT", 0, 0)

            if f.zoneExpScrollChild then
                f.zoneExpScrollChild:SetWidth(expW)
            end
            local btns = f._catalogExpBtns
            if btns then
                for bi = 1, #btns do
                    local eb = btns[bi]
                    if eb then
                        eb:SetWidth(expW)
                    end
                end
            end
            if f.zoneExpHead then
                f.zoneExpHead:SetWidth(expW)
            end

            f.zoneMapsPanel:ClearAllPoints()
            f.zoneMapsPanel:SetPoint("TOPLEFT", f.zonePickSplit, "TOPLEFT", outerW + lay.splitGap, 0)
            f.zoneMapsPanel:SetPoint("BOTTOMRIGHT", f.zonePickSplit, "BOTTOMRIGHT", 0, 0)

            if f.zoneSplitLine and f.zoneExpPanel then
                f.zoneSplitLine:ClearAllPoints()
                local halfGap = math.floor(lay.splitGap * 0.5)
                f.zoneSplitLine:SetPoint("TOPLEFT", f.zoneExpPanel, "TOPRIGHT", halfGap, 0)
                f.zoneSplitLine:SetPoint("BOTTOMLEFT", f.zoneExpPanel, "BOTTOMRIGHT", halfGap, 0)
            end

            if f.mapsHead and f.zoneColHeadRow then
                f.mapsHead:ClearAllPoints()
                f.mapsHead:SetPoint("TOPLEFT", f.zoneColHeadRow, "TOPLEFT", outerW + lay.splitGap, 0)
                f.mapsHead:SetPoint("TOPRIGHT", f.zoneColHeadRow, "TOPRIGHT", 0, 0)
            end

            if f.zoneCatalogScroll then
                local vw = f.zoneCatalogScroll:GetWidth()
                if f.zoneCatalogScrollChild and vw and vw > 0 then
                    f.zoneCatalogScrollChild:SetWidth(math.max(160, vw))
                end
            end
            if f.RefreshZoneCatalogRows then
                f:RefreshZoneCatalogRows()
            end
        end
        f.LayoutZoneCatalogSplit = LayoutZoneCatalogSplit

        zScroll:SetScript("OnSizeChanged", function(self)
            local child = self:GetScrollChild()
            local w = self:GetWidth()
            if child and w and w > 0 then
                child:SetWidth(math.max(120, w))
            end
            if f.RefreshZoneCatalogRows and f._zoneCatalogPrimed then
                f:RefreshZoneCatalogRows()
            end
            if Factory.UpdateScrollBarVisibility then
                Factory:UpdateScrollBarVisibility(self)
            end
        end)

        mapsBody:SetScript("OnSizeChanged", function()
            LayoutZoneCatalogSplit()
        end)

        BindCatalogMouseWheel(zScroll)

        local ADD_BTN_W = f._zoneCatalogLayout.addBtnW
        local TAG_COL_W = f._zoneCatalogLayout.tagColW
        local ROW_H = f._zoneCatalogLayout.rowH
        local HDR_H = f._zoneCatalogLayout.hdrH

        local MAX_CAT_ROWS = math.min(680, math.max(120, (catalogDef and catalogDef.GetMaxDisplayRowCount and catalogDef.GetMaxDisplayRowCount()) or 520))
        f._zoneCatalogRows = {}
        f._zoneCatalogRowPoolCount = 0
        f._zoneCatalogRowPoolMax = MAX_CAT_ROWS

        function f:EnsureZoneCatalogRow(ri)
            local maxRows = self._zoneCatalogRowPoolMax or MAX_CAT_ROWS
            if not ri or ri < 1 or ri > maxRows then return nil end
            local pool = self._zoneCatalogRows
            if pool[ri] then return pool[ri] end
            local zChild = self.zoneCatalogScrollChild
            if not zChild then return nil end

            local row = H.Container(zChild, zChild:GetWidth(), ROW_H, false)
            row:SetHeight(ROW_H)
            row:SetWidth(zChild:GetWidth())
            if row.SetClipsChildren then
                row:SetClipsChildren(false)
            end

            row.headerBar = row:CreateTexture(nil, "BACKGROUND")
            row.headerBar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            row.headerBar:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            row.headerBar:SetColorTexture(COLORS.accent[1] * 0.35, COLORS.accent[2] * 0.35, COLORS.accent[3] * 0.35, 0.55)
            row.headerBar:Hide()

            row.tagFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.tagFs:SetWidth(TAG_COL_W)
            row.tagFs:SetPoint("LEFT", row, "LEFT", 8, 0)
            row.tagFs:SetJustifyH("CENTER")

            row.labelFs = FontManager:CreateFontString(row, "small", "OVERLAY")
            row.labelFs:SetJustifyH("LEFT")
            row.labelFs:SetWordWrap(false)
            row.labelFs:SetMaxLines(1)

            local addB = H.Button(row, ADD_BTN_W, 22, false)
            if not addB then return nil end
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
                row:SetPoint("TOPLEFT", pool[ri - 1], "BOTTOMLEFT", 0, -2)
            end

            addB:SetScript("OnClick", function()
                local mid = row.mapID
                if mid and f.AddCatalogMapId then
                    f:AddCatalogMapId(mid)
                end
            end)
            row:Hide()
            pool[ri] = row
            if ri > (self._zoneCatalogRowPoolCount or 0) then
                self._zoneCatalogRowPoolCount = ri
            end
            return row
        end

        function f:EnsureZoneCatalogPoolSize(needed)
            needed = math.min(needed or 0, self._zoneCatalogRowPoolMax or MAX_CAT_ROWS)
            for i = 1, needed do
                self:EnsureZoneCatalogRow(i)
            end
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
                    local idle = (ns.UI_GetControlChromeBackdrop and ns.UI_GetControlChromeBackdrop()) or { 0.12, 0.12, 0.15, 1 }
                    ApplyVisuals(ob,
                        sel and { COLORS.accent[1] * 0.42, COLORS.accent[2] * 0.42, COLORS.accent[3] * 0.42, 1 } or idle,
                        { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], sel and 0.95 or 0.35 })
                end
            end

            local lay = self._zoneCatalogLayout or {}
            local addBtnW = lay.addBtnW or 56
            local tagColW = lay.tagColW or 54
            local hdrRowH = lay.hdrH or 22
            local dataRowH = lay.rowH or 24
            local zw = (self.zoneCatalogScroll and self.zoneCatalogScroll:GetWidth())
                or (self.zoneCatalogScrollChild and self.zoneCatalogScrollChild:GetWidth())
                or 320
            local unk = (Lz and Lz["UNKNOWN"]) or "?"

            local shown = #rows
            self:EnsureZoneCatalogPoolSize(shown)
            local poolLimit = self._zoneCatalogRowPoolCount or 0

            for ri = 1, poolLimit do
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
                        row.labelFs:SetPoint("LEFT", row, "LEFT", 10, 0)
                        row.labelFs:SetPoint("RIGHT", row, "RIGHT", -10, 0)
                        row.labelFs:SetJustifyH("LEFT")
                        local hk = entry.headerKey or ""
                        local ht = (Lz and hk ~= "" and Lz[hk]) or hk
                        row.labelFs:SetText("|cffcccccc" .. ht .. "|r")
                        row:SetHeight(hdrRowH)
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
                            labelMax = math.max(36, math.floor((zw - tagColW - addBtnW - 34) / 6.2))
                        end
                        row.labelFs:SetText(string.format(
                            PickerBrightHex() .. "%s|r " .. PickerMutedHex() .. "— %d|r",
                            TruncatePickerLabel(nm, labelMax),
                            entry.id
                        ))
                        row:SetHeight(dataRowH)
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
                    estH = estH + (e and e.headerKey and hdrRowH or dataRowH) + 2
                end
                self.zoneCatalogScrollChild:SetHeight(math.max(28, estH))
            end
            if self.zoneCatalogScroll then
                self.zoneCatalogScroll:SetVerticalScroll(0)
            end
            if Factory.UpdateScrollBarVisibility and self.zoneCatalogScroll then
                Factory:UpdateScrollBarVisibility(self.zoneCatalogScroll)
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
                    ns.UI_SetTextColorRole(self.zoneLabel, "Bright")
                end
            end
            if self.ApplyZoneDependentControlsState then
                self:ApplyZoneDependentControlsState()
            end
        end

        if not catalogDef or not catalogDef.sections or #catalogDef.sections == 0 then
            f.zoneCatalogCard:Hide()
        end
    return catalogDef
end