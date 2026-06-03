--[[ Warband Nexus - Professions tab draw (Lua 5.1 upvalue cap)
     Loaded after ProfessionsUI.lua; resolves helpers via ProfUI._drawChunk. ]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local ProfUI = ns.ProfessionsUI

assert(ProfUI._drawChunk, "Load ProfessionsUI.lua before ProfessionsUI_DrawTab.lua")

setfenv(1, setmetatable({
    ns = ns,
    ProfUI = ProfUI,
    WarbandNexus = WarbandNexus,
}, {
    __index = function(_, k)
        local c = ProfUI._drawChunk
        if c and c[k] ~= nil then return c[k] end
        return _G[k]
    end,
}))

local function FinishProfessionsTabChrome(parent)
    RelayoutProfessionRowWidths(parent)
    RefreshVisibleProfessionRowGradients(parent)
    if parent._wnProfRelayoutSectionStack then
        parent._wnProfRelayoutSectionStack()
    end
end

function WarbandNexus:DrawProfessionsTab(parent)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    -- Invalidate any in-flight chunked row paint from a prior draw (tab switch uses AbortTabOperations too).
    ProfUI.AbortChunkedRowPaint()
    profEquipResolveCache = {}
    SyncProfessionColumnOrder(WarbandNexus.db and WarbandNexus.db.profile)

    RegisterProfessionEvents(parent)
    HideEmptyStateCard(parent, "professions")
    -- PopulateContent already released pooled rows on full-tab renders; skip duplicate walk (heavy tab switch).
    if not parent._preparedByPopulate and ReleaseAllPooledChildren then
        ReleaseAllPooledChildren(parent)
    end
    if parent._wnProfNestedRows and ReleaseProfessionRow then
        for i = 1, #parent._wnProfNestedRows do
            local row = parent._wnProfNestedRows[i]
            if row and row.rowType == "profession" then
                ReleaseProfessionRow(row)
            end
        end
    end
    parent._wnProfNestedRows = {}
    parent._wnProfSectionContents = {}
      -- fixedHeader: title card only; column headers live in scrollChild (PvE parity)
    local chrome = ns.UI_BeginTabChromeLayout and ns.UI_BeginTabChromeLayout(mf)
    local metrics = (chrome and chrome.metrics) or (ns.UI_GetMainTabLayoutMetrics and ns.UI_GetMainTabLayoutMetrics(mf))
    local fixedHeader = mf and mf.fixedHeader
    local headerParent = (chrome and chrome.headerParent) or fixedHeader or parent
    local headerYOffset = (chrome and chrome.yOffset) or 0
    local contentSide = (chrome and chrome.side) or (metrics and metrics.sideMargin) or SIDE_MARGIN
    local scrollTopY = (ns.UI_GetTabScrollContentStartY and ns.UI_GetTabScrollContentStartY()) or 8
  -- Single stack width for title card, column headers, sections, and row chrome (Characters-tab parity).
    local stackWidth = (metrics and metrics.bodyWidth and metrics.bodyWidth > 0) and metrics.bodyWidth
        or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
        or math.max(200, ((mf and mf.scroll and mf.scroll:GetWidth()) or 600) - contentSide * 2)
    cachedRowWidth = stackWidth
    parent._wnProfBodyWidth = stackWidth
    parent._wnProfContentSide = contentSide

    -- If module is disabled, show disabled state card
    if not ns.Utilities:IsModuleEnabled("professions") then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, scrollTopY, (ns.L and ns.L["PROFESSIONS_DISABLED_TITLE"]) or "Professions")
        return scrollTopY + cardHeight
    end

    local characters = self:GetAllCharacters()
    local trackedFavorites, groupedById, customGroupsOrdered, trackedRegular, untrackedChars = CategorizeCharacters(characters)
    EnsureProfessionsSectionExpandDefaults(self.db.profile)
    local totalProfChars = #trackedFavorites + #trackedRegular + #untrackedChars
    local charListsForProfCount = { trackedFavorites, trackedRegular, untrackedChars }
    for gci = 1, #customGroupsOrdered do
        local gl = groupedById[customGroupsOrdered[gci].id]
        if gl then
            totalProfChars = totalProfChars + #gl
            charListsForProfCount[#charListsForProfCount + 1] = gl
        end
    end
    local profDataCharCount = CountCharsWithProfessionData(charListsForProfCount)

    local expBadgeWidth = 100
    local filterBtnW = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_WIDTH_DEFAULT) or 80
    local btnHH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32
    local tm = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local hdrGapEc = tm.gap or (GetLayout().HEADER_TOOLBAR_CONTROL_GAP) or 8
    local profToolbarReserve = (ns.UI_ComputeTitleToolbarReserve and ns.UI_ComputeTitleToolbarReserve({
        expBadgeWidth,
        filterBtnW,
        tm.filterW or 96,
    })) or (expBadgeWidth + filterBtnW + 40 + hdrGapEc)

    -- ===== TITLE CARD (in fixedHeader - non-scrolling) — tracked roster vs saved profession rows =====
    local subLine = format(
        (ns.L and ns.L["PROFESSIONS_TRACKED_FORMAT"]) or "%s tracked - %s with profession data",
        FormatNumber(totalProfChars),
        FormatNumber(profDataCharCount)
    )
    local titleCard = select(1, ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "professions",
        titleText = "|cff" .. GetAccentHexColor() .. ((ns.L and ns.L["YOUR_PROFESSIONS"]) or "Warband Professions") .. "|r",
        subtitleText = subLine,
        textRightInset = profToolbarReserve,
    }))
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end

    -- Force fixed expansion view: Midnight only (filter selector removed).
    self.db.profile.professionExpansionFilter = "Midnight"
    local expBadgeHeight = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local expBadge = ns.UI.Factory:CreateButton(titleCard, expBadgeWidth, expBadgeHeight, false)
    if ApplyVisuals then
        ApplyVisuals(expBadge, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    local expBadgeText = FontManager:CreateFontString(expBadge, "body", "OVERLAY")
    expBadgeText:SetPoint("CENTER", 0, 0)
    expBadgeText:SetJustifyH("CENTER")
    expBadgeText:SetText((ns.L and ns.L["CONTENT_MIDNIGHT"]) or "Midnight")
    expBadgeText:SetTextColor(0.9, 0.9, 0.9)
    expBadge:SetScript("OnClick", nil)
    expBadge:SetScript("OnEnter", nil)
    expBadge:SetScript("OnLeave", nil)
    local titleEdgeInset = tm.edgeInset or 0
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(expBadge, titleCard, titleCard, "RIGHT", -titleEdgeInset)
    else
        expBadge:SetPoint("RIGHT", titleCard, "RIGHT", -titleEdgeInset, 0)
    end
    
    -- ===== COLUMNS BUTTON (column visibility toggle) =====
    local filterBtnH = ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT or 32
    local filterBtn = ns.UI.Factory:CreateButton(titleCard, filterBtnW, filterBtnH, false)
    if ApplyVisuals then
        ApplyVisuals(filterBtn, {0.12, 0.12, 0.15, 1}, {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6})
    end
    local filterBtnText = FontManager:CreateFontString(filterBtn, "body", "OVERLAY")
    filterBtnText:SetPoint("CENTER", 0, 0)
    filterBtnText:SetJustifyH("CENTER")
    filterBtnText:SetText((ns.L and ns.L["COLUMNS_BUTTON"]) or "Columns")
    filterBtnText:SetTextColor(0.9, 0.9, 0.9)
    if ns.UI.Factory and ns.UI.Factory.ApplyHighlight then ns.UI.Factory:ApplyHighlight(filterBtn) end
    local hdrGap = tm.gap or (GetLayout().HEADER_TOOLBAR_CONTROL_GAP) or 8
    if ns.UI_AnchorTitleCardToolbarControl then
        ns.UI_AnchorTitleCardToolbarControl(filterBtn, titleCard, expBadge, "LEFT", -hdrGap)
    else
        filterBtn:SetPoint("RIGHT", expBadge, "LEFT", -hdrGap, 0)
    end

    filterBtn:SetScript("OnClick", function(btn)
        local menu = WarbandNexus._wnProfColumnPickerMenu
        if menu and menu:IsShown() and WarbandNexus._wnProfColumnPickerAnchorBtn == btn then
            menu:Hide()
            return
        end
        if not WarbandNexus.ShowProfessionColumnPicker then return end
        WarbandNexus:ShowProfessionColumnPicker(btn)
    end)

    if WarbandNexus._wnProfColumnPickerMenu and WarbandNexus._wnProfColumnPickerMenu:IsShown() then
        WarbandNexus._wnProfColumnPickerAnchorBtn = filterBtn
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                local picker = WarbandNexus._wnProfColumnPickerMenu
                local anchor = WarbandNexus._wnProfColumnPickerAnchorBtn
                local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
                if not picker or not anchor or not mf or mf.currentTab ~= "professions" then
                    ProfColumnPickerHide()
                    return
                end
                ProfColumnPickerPopulateMenu(picker, anchor)
                ProfColumnPickerPositionMenu(picker, anchor)
                picker:Show()
                ProfColumnPickerShowCatcher(picker)
            end)
        end
    end

    local sortBtn
    if ns.UI_CreateCharacterTabAdvancedFilterButton then
        if ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        end
        local sortOptions = {
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
            {key = "realm", label = (ns.L and ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
        }
        if not self.db.profile.professionSort then self.db.profile.professionSort = {} end
        if not self.db.profile.professionSectionFilter then self.db.profile.professionSectionFilter = { sectionKey = "all" } end
        sortBtn = ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.professionSort,
            dbSectionFilter = self.db.profile.professionSectionFilter,
            getCustomSections = function()
                return self.db.profile.characterCustomGroups or {}
            end,
            onRefresh = function()
                WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
            end,
            onDeleteSection = function(groupId, groupName)
                WarbandNexus:ConfirmDeleteCustomCharacterHeader(groupId, groupName)
            end,
        })
        if sortBtn then
            if ns.UI_AnchorTitleCardToolbarControl then
                ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, filterBtn, "LEFT", -hdrGap)
            else
                sortBtn:SetPoint("RIGHT", filterBtn, "LEFT", -hdrGap, 0)
            end
        end
    elseif ns.UI_CreateCharacterSortDropdown then
        local sortOptions = {
            {key = "manual", label = (ns.L and ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
            {key = "name", label = (ns.L and ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
            {key = "level", label = (ns.L and ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
            {key = "ilvl", label = (ns.L and ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
            {key = "gold", label = (ns.L and ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
            {key = "realm", label = (ns.L and ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
        }
        if not self.db.profile.professionSort then self.db.profile.professionSort = {} end
        sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.professionSort, function()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end)
        if ns.UI_AnchorTitleCardToolbarControl then
            ns.UI_AnchorTitleCardToolbarControl(sortBtn, titleCard, filterBtn, "LEFT", -hdrGap)
        else
            sortBtn:SetPoint("RIGHT", filterBtn, "LEFT", -hdrGap, 0)
        end
    end

    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    titleCard:Show()
    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
        if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) end
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    -- ===== COLUMN HEADER ROW (scrollChild — PvE parity; crest/icons sit directly above sections) =====
    local mainFrameRef = WarbandNexus.UI.mainFrame
    local columnHeaderClip = mainFrameRef and mainFrameRef.columnHeaderClip
    if columnHeaderClip then
        columnHeaderClip:SetHeight(1)
        columnHeaderClip:Hide()
    end

    local colHeaderInnerW = ResolveProfessionColumnHeaderInnerWidth(mainFrameRef, parent, stackWidth)
    local profPaintW = colHeaderInnerW
    local profStackW = ProfessionStackBodyWidth(profPaintW, contentSide)
    parent._wnProfStackWidth = profStackW
    parent:SetWidth(math.max(1, profPaintW))
    if mainFrameRef then
        mainFrameRef._profMinScrollWidth = profPaintW
    end
    parent._wnProfColHeaderStripH = COLUMN_HEADER_HEIGHT + COLUMN_HEADER_PAD

    local FactHdr = ns.UI and ns.UI.Factory
    local colHeaderBar = parent._wnProfColHeaderRow
    if not colHeaderBar then
        colHeaderBar = FactHdr and FactHdr:CreateContainer(parent, profStackW, COLUMN_HEADER_HEIGHT, false)
        if not colHeaderBar then
            colHeaderBar = CreateFrame("Frame", nil, parent)
            colHeaderBar:SetSize(profStackW, COLUMN_HEADER_HEIGHT)
        end
        parent._wnProfColHeaderRow = colHeaderBar
    end
    ReattachProfessionColumnHeaderBar(colHeaderBar, parent)
    colHeaderBar:Show()
    colHeaderBar:SetHeight(COLUMN_HEADER_HEIGHT)
    colHeaderBar:ClearAllPoints()
    colHeaderBar:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -scrollTopY)
    if colHeaderBar.SetWidth then
        colHeaderBar:SetWidth(math.max(1, profStackW))
    end

    local accentR = COLORS.accent[1] or 0.40
    local accentG = COLORS.accent[2] or 0.20
    local accentB = COLORS.accent[3] or 0.58
    if colHeaderBar._wnProfColHeaderLine then
        colHeaderBar._wnProfColHeaderLine:Hide()
    end

    for _, fs in pairs(profColHeaderLabels) do
        if fs and fs.Hide then fs:Hide() end
    end
    for colKey, hit in pairs(profColHeaderHits) do
        if hit and hit.Hide then hit:Hide() end
    end

    local SORT_ARROW_SIZE = 11
    local sortState = GetColumnSortState()
    for hdi = 1, #HEADER_DEFS do
        local hdef = HEADER_DEFS[hdi]
        local col = hdef.col
        if IsColumnVisible(col) then
            local w = (hdef.getWidth and hdef.getWidth()) or ColWidth(col)
            local displayText = StripProfHeaderDisplayText(
                (hdef.label and ns.L and ns.L[hdef.label]) or hdef.text or ""
            )
            if col == "profName" and displayText == "" then
                displayText = StripProfHeaderDisplayText((ns.L and ns.L["GROUP_PROFESSION"]) or "Profession")
            end
            if col == "open" then
                -- Per-row Open button only; no header label (avoids "Open" text beside Character sort arrow).
            elseif PROF_HEADER_ICON_BY_COL[col] then
                PaintProfessionCompactColumnHeader(
                    colHeaderBar, col, w, PROF_HEADER_ICON_BY_COL[col], hdef, sortState, displayText,
                    accentR, accentG, accentB, FactHdr
                )
            else
            local isSorted = sortState and sortState.col == col

            if hdef.sortable then
                local hitBtn
                if FactHdr and FactHdr.CreateButton then
                    hitBtn = FactHdr:CreateButton(colHeaderBar, w, COLUMN_HEADER_HEIGHT, true)
                end
                if not hitBtn then
                    hitBtn = CreateFrame("Button", nil, colHeaderBar)
                    hitBtn:SetSize(w, COLUMN_HEADER_HEIGHT)
                end
                if (hdef.align or "CENTER") == "CENTER" then
                    hitBtn:SetPoint("CENTER", colHeaderBar, "LEFT", ColCenterX(col), 0)
                else
                    hitBtn:SetPoint("LEFT", colHeaderBar, "LEFT", ColOffset(col), 0)
                end
                hitBtn:SetFrameLevel(colHeaderBar:GetFrameLevel() + 1)

                -- Keep the sort arrow inside this column so it cannot sit in the gap left of "Character" (reads as "Open I").
                local arrow = hitBtn:CreateTexture(nil, "OVERLAY")
                arrow:SetSize(SORT_ARROW_SIZE, SORT_ARROW_SIZE)
                arrow:SetPoint("RIGHT", hitBtn, "RIGHT", -1, 0)
                if isSorted then
                    if sortState.dir == "asc" then
                        arrow:SetAtlas("hud-MainMenuBar-arrowup")
                    else
                        arrow:SetAtlas("hud-MainMenuBar-arrowdown")
                    end
                    arrow:SetVertexColor(accentR, accentG, accentB, 1)
                    arrow:Show()
                else
                    arrow:Hide()
                end

                local lbl = FontManager:CreateFontString(hitBtn, PROF_COLUMN_HEADER_FONT, "OVERLAY")
                ApplyProfColumnHeaderLabel(lbl, displayText, false)
                lbl:SetJustifyH(hdef.align or "CENTER")
                if lbl.SetJustifyV then lbl:SetJustifyV("MIDDLE") end
                lbl:SetPoint("LEFT", hitBtn, "LEFT", 2, 0)
                lbl:SetPoint("RIGHT", hitBtn, "RIGHT", -2, 0)

                local function SetHeaderLabelArrowInset(showArrow)
                    lbl:ClearAllPoints()
                    lbl:SetPoint("LEFT", hitBtn, "LEFT", 2, 0)
                    local rightPad = showArrow and -(SORT_ARROW_SIZE + 4) or -2
                    lbl:SetPoint("RIGHT", hitBtn, "RIGHT", rightPad, 0)
                end
                SetHeaderLabelArrowInset(isSorted)

                local capturedCol = col
                hitBtn:SetScript("OnClick", function()
                    ToggleColumnSort(capturedCol)
                end)
                hitBtn:SetScript("OnEnter", function()
                    ApplyProfColumnHeaderLabel(lbl, displayText, true)
                    SetHeaderLabelArrowInset(true)
                    if ShowTooltip and displayText ~= "" then
                        ShowTooltip(hitBtn, { type = "custom", title = displayText, lines = {}, anchor = "ANCHOR_TOP" })
                    end
                    if not isSorted then
                        arrow:SetAtlas("hud-MainMenuBar-arrowup")
                        arrow:SetVertexColor(1, 1, 1, 0.4)
                        arrow:Show()
                    end
                end)
                hitBtn:SetScript("OnLeave", function()
                    ApplyProfColumnHeaderLabel(lbl, displayText, false)
                    SetHeaderLabelArrowInset(isSorted)
                    if HideTooltip then HideTooltip() end
                    if not isSorted then
                        arrow:Hide()
                    end
                end)
            else
                -- Clip so header text cannot draw into the fav/class gap (often misread as "Open I" next to sort arrows).
                local clip = FactHdr and FactHdr:CreateContainer(colHeaderBar, w, COLUMN_HEADER_HEIGHT, false)
                if not clip then
                    clip = CreateFrame("Frame", nil, colHeaderBar)
                    clip:SetSize(w, COLUMN_HEADER_HEIGHT)
                end
                if (hdef.align or "CENTER") == "CENTER" then
                    clip:SetPoint("CENTER", colHeaderBar, "LEFT", ColCenterX(col), 0)
                else
                    clip:SetPoint("TOPLEFT", colHeaderBar, "TOPLEFT", ColOffset(col), 0)
                end
                clip:SetClipsChildren(true)
                local lbl = FontManager:CreateFontString(clip, PROF_COLUMN_HEADER_FONT, "OVERLAY")
                ApplyProfColumnHeaderLabel(lbl, displayText, false)
                lbl:SetJustifyH(hdef.align or "CENTER")
                if lbl.SetJustifyV then lbl:SetJustifyV("MIDDLE") end
                lbl:SetPoint("TOPLEFT", clip, "TOPLEFT", 1, 0)
                lbl:SetPoint("BOTTOMRIGHT", clip, "BOTTOMRIGHT", -1, 0)
                BindProfColumnHeaderTooltip(clip, displayText)
            end
            end
        end
    end
    ApplyProfessionColumnDividers(colHeaderBar, COLUMN_HEADER_HEIGHT)
    colHeaderBar:Show()

    local yOffset = scrollTopY + COLUMN_HEADER_HEIGHT + COLUMN_HEADER_PAD

    -- ===== EMPTY STATE =====
    if totalProfChars == 0 then
        local emptyText = FontManager:CreateFontString(parent, DATA_FONT, "OVERLAY")
        emptyText:SetPoint("TOPLEFT", contentSide + 20, -yOffset - 30)
        emptyText:SetWidth(stackWidth - 40)
        emptyText:SetJustifyH("CENTER")
        emptyText:SetText("|cffffffff" .. ((ns.L and ns.L["NO_PROFESSIONS_DATA"]) or "No profession data available yet. Open your profession window (default: K) on each character to collect data.") .. "|r")
        return yOffset + 100
    end

    -- ===== SECTION HEADERS & CHARACTER ROWS =====
    local currentPlayerKey = (ns.CharacterService and ns.CharacterService.ResolveCharactersTableKey and ns.CharacterService:ResolveCharactersTableKey(WarbandNexus))
        or (ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus))
        or ns.Utilities:GetCharacterKey()
    local rowIndex = 0
    local SECTION_COLLAPSE_HEADER_HEIGHT = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36

    self.profRecentlyExpanded = self.profRecentlyExpanded or {}

    -- Column sort: precompute numeric keys once per list (table.sort calls comparator O(n log n) times;
    -- GetCharSortValue does concentration estimates + currency + cooldown scans per call).
    local sortStateForKeys = GetColumnSortState()
    local colForKeys = sortStateForKeys and sortStateForKeys.col
    local function attachProfSortKeys(list)
        if not list or not colForKeys or colForKeys == "name" then return end
        for i = 1, #list do
            list[i]._wnProfSortKey = GetCharSortValue(list[i], colForKeys)
        end
    end
    local function clearProfSortKeys(list)
        if not list then return end
        for i = 1, #list do
            list[i]._wnProfSortKey = nil
        end
    end

    local colSortCmp = GetColumnSortCharComparator()
    if colSortCmp and colForKeys and colForKeys ~= "name" then
        attachProfSortKeys(trackedFavorites)
        for gci = 1, #customGroupsOrdered do
            local gl = groupedById[customGroupsOrdered[gci].id]
            attachProfSortKeys(gl)
        end
        attachProfSortKeys(trackedRegular)
        attachProfSortKeys(untrackedChars)
    end
    if colSortCmp then
        table.sort(trackedFavorites, colSortCmp)
        for gci = 1, #customGroupsOrdered do
            local gl = groupedById[customGroupsOrdered[gci].id]
            if gl then table.sort(gl, colSortCmp) end
        end
        table.sort(trackedRegular, colSortCmp)
        table.sort(untrackedChars, colSortCmp)
    end
    if colSortCmp and colForKeys and colForKeys ~= "name" then
        clearProfSortKeys(trackedFavorites)
        for gci = 1, #customGroupsOrdered do
            local gl = groupedById[customGroupsOrdered[gci].id]
            clearProfSortKeys(gl)
        end
        clearProfSortKeys(trackedRegular)
        clearProfSortKeys(untrackedChars)
    end

    -- Grouped sections with collapsible headers (Characters-tab stack: header chain respects collapsed body height)
    local SECTION_HEADER_GAP = 6
    local previousSectionContent = nil
    local previousSectionHeader = nil
    local previousSectionExpanded = false
    local isFirstSection = true
    local sectionRows = parent._wnProfNestedRows
    parent._wnProfSectionHeaders = {}
    parent._wnProfSectionStack = {}
    parent._wnProfSectionStackTopY = yOffset
    parent:SetHeight(1)

    local function SectionExpandedNow(sectionKey, defaultExpanded, visualOpts)
        if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
            local gid = visualOpts.groupId
            local ge = self.db.profile.characterGroupExpanded
            if ge and ge[gid] ~= nil then
                return ge[gid] == true
            end
            return defaultExpanded == true
        end
        local ui = self.db.profile.ui
        if ui and ui[sectionKey] ~= nil then
            return ui[sectionKey] == true
        end
        return defaultExpanded == true
    end

    local function RelayoutProfessionsSectionStack()
        if parent._wnProfSectionStackRelayoutLock then return end
        parent._wnProfSectionStackRelayoutLock = true
        local stack = parent._wnProfSectionStack
        if not stack or #stack == 0 then
            parent._wnProfSectionStackRelayoutLock = nil
            return
        end
        local w = parent._wnProfStackWidth or stackWidth
        local side = parent._wnProfContentSide or contentSide
        local y = parent._wnProfSectionStackTopY or 0
        local prevHeader, prevContent, prevExpanded
        for si = 1, #stack do
            local entry = stack[si]
            local header = entry.header
            local content = entry.content
            if not header or not content then
                break
            end
            local expanded = SectionExpandedNow(entry.sectionKey, entry.defaultExpanded, entry.visualOpts)
            header:ClearAllPoints()
            header:SetHeight(SECTION_COLLAPSE_HEADER_HEIGHT)
            if header.SetWidth then
                header:SetWidth(math.max(1, w))
            end
            if si == 1 then
                header:SetPoint("TOPLEFT", parent, "TOPLEFT", side, -y)
            elseif prevExpanded and prevContent then
                header:SetPoint("TOPLEFT", prevContent, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
            elseif prevHeader then
                header:SetPoint("TOPLEFT", prevHeader, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
            end
            content:ClearAllPoints()
            content:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, 0)
            content:SetWidth(w)
            local bodyH = math.max(0.1, content._wnSectionFullH or 0.1)
            if expanded then
                content:SetHeight(bodyH)
                content:Show()
            else
                content:SetHeight(0.1)
                content:Hide()
            end
            y = y + SECTION_COLLAPSE_HEADER_HEIGHT + (expanded and bodyH or 0) + SECTION_HEADER_GAP
            prevHeader = header
            prevContent = content
            prevExpanded = expanded
        end
        local mfRef = WarbandNexus.UI and WarbandNexus.UI.mainFrame
        if mfRef and ns.UI_SyncMainTabScrollChrome then
            ns.UI_SyncMainTabScrollChrome(mfRef, parent, y)
        end
        parent._wnProfSectionStackRelayoutLock = nil
    end
    parent._wnProfRelayoutSectionStack = RelayoutProfessionsSectionStack

    local function AcquireSectionContentFrame(anchorHeader)
        local hostW = math.max(1, profStackW)
        local Fact = ns.UI and ns.UI.Factory
        local contentFrame
        if Fact and Fact.CreateContainer then
            contentFrame = Fact:CreateContainer(anchorHeader, hostW, 1, false)
        else
            contentFrame = CreateFrame("Frame", nil, anchorHeader)
            contentFrame:SetSize(hostW, 1)
        end
        if contentFrame.SetClipsChildren then
            contentFrame:SetClipsChildren(false)
        end
        contentFrame._wnAnchorHeader = anchorHeader
        contentFrame._wnSectionFullH = 0
        contentFrame:ClearAllPoints()
        contentFrame:SetPoint("TOPLEFT", anchorHeader, "BOTTOMLEFT", 0, 0)
        contentFrame:SetPoint("TOPRIGHT", anchorHeader, "BOTTOMRIGHT", 0, 0)
        contentFrame:SetHeight(0.1)
        tinsert(parent._wnProfSectionContents, contentFrame)
        return contentFrame
    end

    --- Queue row paint for every character in the section (Characters-tab parity); expand/collapse is show/hide only.
    local function QueueProfessionsSectionRows(contentFrame, chars, sectionExpanded)
        contentFrame._wnProfRunningYOffset = 0
        contentFrame._wnProfSectionPaintExpanded = sectionExpanded
        local betweenRows = (GetLayout().betweenRows) or 0
        local rowStride = ROW_HEIGHT + betweenRows
        local sectionYOffset = 0
        if #chars == 0 then
            contentFrame._wnSectionFullH = 0.1
            return 0
        end
        if not parent._wnProfChunkQueue then
            parent._wnProfChunkQueue = {}
        end
        for chi = 1, #chars do
            tinsert(parent._wnProfChunkQueue, {
                char = chars[chi],
                sectionContent = contentFrame,
            })
            sectionYOffset = sectionYOffset + rowStride
        end
        contentFrame._wnSectionFullH = math.max(0.1, sectionYOffset)
        return sectionYOffset
    end

    local function AnchorSectionHeader(headerFrame)
        headerFrame:SetHeight(SECTION_COLLAPSE_HEADER_HEIGHT)
        if headerFrame.SetWidth then
            headerFrame:SetWidth(math.max(1, profStackW))
        end
        if isFirstSection then
            headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
            isFirstSection = false
        elseif previousSectionExpanded and previousSectionContent then
            headerFrame:SetPoint("TOPLEFT", previousSectionContent, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
        elseif previousSectionHeader then
            headerFrame:SetPoint("TOPLEFT", previousSectionHeader, "BOTTOMLEFT", 0, -SECTION_HEADER_GAP)
        else
            headerFrame:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -yOffset)
        end
    end

    local function DrawSection(chars, headerLabel, sectionKey, defaultExpanded, headerAtlas, visualOpts)
        if #chars == 0 and not (visualOpts and visualOpts.forceWhenEmpty) then return end

        local isExpanded
        local groupId = visualOpts and visualOpts.groupId
        if visualOpts and visualOpts.useCharacterGroupExpand and groupId then
            if not self.db.profile.characterGroupExpanded then self.db.profile.characterGroupExpanded = {} end
            isExpanded = self.db.profile.characterGroupExpanded[groupId]
            if isExpanded == nil then isExpanded = defaultExpanded end
        else
            isExpanded = self.db.profile.ui[sectionKey]
            if isExpanded == nil then isExpanded = defaultExpanded end
        end

        local sectionContent
        local headerVisualOpts = BuildCollapsibleSectionOpts({
            bodyGetter = function() return sectionContent end,
        }) or { animatedContent = function() return sectionContent end }
        if visualOpts and visualOpts.sectionPreset then
            headerVisualOpts.sectionPreset = visualOpts.sectionPreset
        end
        headerVisualOpts.useFullParentWidth = true
        headerVisualOpts.sectionStackWidth = profStackW

        local header, headerExpandIcon, hdrIcon, headerText = CreateCollapsibleHeader(
            parent,
            headerLabel,
            sectionKey,
            isExpanded,
            function(expanded)
                if visualOpts and visualOpts.useCharacterGroupExpand and groupId then
                    if not self.db.profile.characterGroupExpanded then self.db.profile.characterGroupExpanded = {} end
                    self.db.profile.characterGroupExpanded[groupId] = expanded
                    if expanded then self.profRecentlyExpanded["cgrp_" .. tostring(groupId)] = GetTime() end
                else
                    self.db.profile.ui[sectionKey] = expanded
                    if expanded then self.profRecentlyExpanded[sectionKey] = GetTime() end
                end
                if sectionContent then
                    sectionContent._wnProfSectionPaintExpanded = expanded
                end
                if expanded then
                    if sectionContent then
                        sectionContent:Show()
                        sectionContent:SetHeight(math.max(0.1, sectionContent._wnSectionFullH or 0.1))
                    end
                elseif sectionContent then
                    sectionContent:Hide()
                    sectionContent:SetHeight(0.1)
                end
                RelayoutProfessionsSectionStack()
            end,
            headerAtlas,
            true,  -- isAtlas
            nil,
            nil,
            headerVisualOpts
        )
        -- Match Characters tab icon sizing exactly:
        --   Favorites          (gold preset, NO useCharacterGroupExpand) -> 28x28
        --   Custom roster      (useCharacterGroupExpand + groupId)        -> 24x24
        --   Regular / Untracked (default / "danger")                      -> 24x24
        local isCustomRosterSectionForIcon = visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId
        local isFavoritesSectionForIcon = visualOpts and visualOpts.sectionPreset == "gold" and not isCustomRosterSectionForIcon
        if hdrIcon then
            local sz = isFavoritesSectionForIcon and 28 or 24
            hdrIcon:SetSize(sz, sz)
        end
        header:SetHeight(SECTION_COLLAPSE_HEADER_HEIGHT)
        AnchorSectionHeader(header)

        local isCustomRosterSection = visualOpts and visualOpts.groupId
        local profSectionCount
        if not isCustomRosterSection then
            -- Non-custom sections (Favorites / Characters / Untracked) keep the simple count badge.
            local countHex = ((visualOpts and visualOpts.sectionPreset == "danger") and "|cff888888") or "|cffaaaaaa"
            if not header._wnProfSectionCount then
                header._wnProfSectionCount = FontManager:CreateFontString(header, "header", "OVERLAY")
            end
            profSectionCount = header._wnProfSectionCount
            profSectionCount:SetJustifyH("RIGHT")
            profSectionCount:SetText(countHex .. FormatNumber(#chars) .. "|r")
            profSectionCount:Show()
        elseif header._wnProfSectionCount then
            -- Hide legacy per-tab count so the unified helper's count is the only badge shown.
            header._wnProfSectionCount:Hide()
        end

        sectionContent = AcquireSectionContentFrame(header)
        local sectionHeight = QueueProfessionsSectionRows(sectionContent, chars, isExpanded)
        if isExpanded then
            sectionContent:Show()
            sectionContent:SetHeight(math.max(0.1, sectionContent._wnSectionFullH or 0.1))
        else
            sectionContent:Hide()
            sectionContent:SetHeight(0.1)
        end

        if isCustomRosterSection and ns.UI_DecorateCustomHeader then
            -- Unified Custom Header chrome (count + gold star). No [+] button in Professions tab.
            -- Layout: [chevron] [icon] [gold-star] [title] ........ [count]
            ns.UI_DecorateCustomHeader(header, {
                groupId = visualOpts.groupId,
                memberCount = #chars,
                addon = WarbandNexus,
                profile = self.db.profile,
                expandIcon = headerExpandIcon,
                iconFrame = hdrIcon,
                headerText = headerText,
                includeAddButton = false,
                refreshTab = "professions",
                allowSectionHighlightToggle = false,
            })
        elseif profSectionCount then
            -- Non-custom sections (Favorites / Characters / Untracked): simple right-anchored count
            -- badge. Match Characters tab pattern exactly: only count is anchored to RIGHT,-14,0;
            -- headerText keeps its original LEFT-only anchor (no RIGHT constraint).
            profSectionCount:ClearAllPoints()
            profSectionCount:SetPoint("RIGHT", header, "RIGHT", -14, 0)
        end

        tinsert(parent._wnProfSectionHeaders, header)
        tinsert(parent._wnProfSectionStack, {
            header = header,
            content = sectionContent,
            sectionKey = sectionKey,
            defaultExpanded = defaultExpanded,
            visualOpts = visualOpts,
        })
        header._wnProfSectionContent = sectionContent
        sectionContent._wnProfSectionHeader = header
        previousSectionHeader = header
        previousSectionContent = sectionContent
        previousSectionExpanded = isExpanded == true
        yOffset = yOffset + SECTION_COLLAPSE_HEADER_HEIGHT + (isExpanded and sectionHeight or 0) + SECTION_HEADER_GAP
    end

    local sectionFilter = "all"
    if self.db.profile.professionSectionFilter and type(self.db.profile.professionSectionFilter.sectionKey) == "string" then
        sectionFilter = self.db.profile.professionSectionFilter.sectionKey
    end
    local drawFav = (sectionFilter == "all") or (sectionFilter == "favorites")
    local drawReg = (sectionFilter == "all") or (sectionFilter == "regular")
    local drawUnt = (sectionFilter == "untracked") or (sectionFilter == "all" and #untrackedChars > 0)

    -- Same stack as Characters tab: Favorites -> custom groups -> Characters -> inactive (untracked) last.

    if drawFav then
        DrawSection(
            trackedFavorites,
            (ns.L and ns.L["HEADER_FAVORITES"]) or "Favorites",
            "profFavoritesExpanded",
            true,
            "GM-icon-assistActive-hover",
            { sectionPreset = "gold" }
        )
    end

    for pci = 1, #customGroupsOrdered do
        local gMeta = customGroupsOrdered[pci]
        local gid = gMeta.id
        local gList = groupedById[gid] or {}
        local gListKey = (ns.CharacterService and ns.CharacterService.GetCustomGroupListKey and ns.CharacterService:GetCustomGroupListKey(gid)) or ("group_" .. tostring(gid))
        local showGrp = (sectionFilter == "all") or (sectionFilter == gListKey)
        if showGrp then
            local goldStyle = ns.CharacterService and ns.CharacterService.IsProfileCustomSectionHighlighted
                and ns.CharacterService:IsProfileCustomSectionHighlighted(self.db.profile, gid)
            DrawSection(
                gList,
                gMeta.name or gid,
                "profCGrp_" .. tostring(gid),
                false,
                goldStyle and "GM-icon-assistActive-hover" or "GM-icon-headCount",
                { sectionPreset = goldStyle and "gold" or "accent", useCharacterGroupExpand = true, groupId = gid }
            )
        end
    end

    if drawReg then
        DrawSection(
            trackedRegular,
            (ns.L and ns.L["HEADER_CHARACTERS"]) or "Characters",
            "profCharactersExpanded",
            true,
            "GM-icon-headCount",
            nil
        )
    end

    if drawUnt then
        DrawSection(
            untrackedChars,
            (ns.L and ns.L["UNTRACKED_CHARACTERS"]) or "Untracked Characters",
            "profUntrackedExpanded",
            false,
            "DungeonStoneCheckpointDeactivated",
            { sectionPreset = "danger" }
        )
    end

    RelayoutProfessionsSectionStack()

    local function EstimateProfessionsScrollBody()
        local stack = parent._wnProfSectionStack
        if not stack or #stack == 0 then
            return (parent._wnProfSectionStackTopY or yOffset) + 24
        end
        local estY = parent._wnProfSectionStackTopY or yOffset
        for si = 1, #stack do
            local entry = stack[si]
            local expanded = SectionExpandedNow(entry.sectionKey, entry.defaultExpanded, entry.visualOpts)
            local bodyH = 0
            if expanded and entry.content then
                bodyH = math.max(0.1, entry.content._wnSectionFullH or entry.content._wnProfRunningYOffset or 0.1)
            end
            estY = estY + SECTION_COLLAPSE_HEADER_HEIGHT + bodyH + SECTION_HEADER_GAP
        end
        return estY + 24
    end

    if profDataCharCount > 0 and not AnyProfessionsSectionExpanded(self.db.profile, customGroupsOrdered) then
        local hintY = yOffset
        local hint = FontManager:CreateFontString(parent, DATA_FONT, "OVERLAY")
        hint:SetPoint("TOPLEFT", contentSide + 12, -hintY - 8)
        hint:SetWidth(stackWidth - 24)
        hint:SetJustifyH("LEFT")
        hint:SetText("|cffaaaaaa" .. ((ns.L and ns.L["PROF_SECTIONS_COLLAPSED_HINT"])
            or "All profession sections are collapsed. Click Favorites, Characters, or a roster group header to expand and view profession details.") .. "|r")
        yOffset = hintY + 36
        parent._wnProfSectionStackTopY = yOffset
    end

    local mfRef = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    EnsureProfessionRowGradientScrollHook(mfRef)
    EnsureProfessionColumnHeaderStrip(mfRef, parent, stackWidth)

    local chunkQueue = parent._wnProfChunkQueue
    parent._wnProfChunkQueue = nil

    if chunkQueue and #chunkQueue > 0 then
        parent._wnProfChunkPending = true
        parent._wnProfQueuedRowCount = #chunkQueue
        parent._wnProfEstimatedScrollBody = EstimateProfessionsScrollBody()
        local drawGen = ProfUI._drawGen or 0
        local useChunked = #chunkQueue >= (ProfUI.CHUNK_MIN_CHARS or 5)
        ProfUI.RunChunkedRowPaint(self, parent, chunkQueue, drawGen, {
            profStackW = profStackW,
            currentPlayerKey = currentPlayerKey,
            rowIndex = rowIndex,
            syncAll = not useChunked,
            onComplete = function()
                parent._wnProfChunkPending = nil
                parent._wnProfEstimatedScrollBody = nil
                parent._wnProfQueuedRowCount = nil
                FinishProfessionsTabChrome(parent)
            end,
        })
    else
        FinishProfessionsTabChrome()
    end

    local retH = yOffset + 10
    if parent._wnProfEstimatedScrollBody and parent._wnProfEstimatedScrollBody > retH then
        retH = parent._wnProfEstimatedScrollBody
    end
    return retH
end

