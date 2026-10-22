--[[ Warband Nexus - Professions tab draw (Lua 5.1 upvalue cap)
     Loaded after ProfessionsUI.lua; resolves helpers via ProfUI._drawChunk. ]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
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

local profHeaderDefByCol

--- TableKit applyIcon: legacy PROF_HEADER_ICON_BY_COL resolution (file paths -> atlas list -> fallback).
local function ProfHeaderApplyIcon(tex, col)
    local iconDef = col.iconDef
    if not iconDef then return false end
    ApplyProfessionHeaderIconTexture(tex, iconDef)
    return tex:IsShown() and ProfessionHeaderIconIsDrawn(tex)
end

--- Sort cycle stays asc -> desc -> off (persisted to professionColumnSort); redraw re-applies strip:SetSort.
local function ProfHeaderOnSortClick(key)
    ToggleColumnSort(key)
end

local PROF_HEADER_STRIP_OPTS = {
    mode = "compact",
    height = COLUMN_HEADER_HEIGHT,
    iconSize = PROF_COL_ICON_SIZE,
    bottomRule = true,
    onSortClick = ProfHeaderOnSortClick,
    applyIcon = ProfHeaderApplyIcon,
}

--- Fill header fields on the shared layout cols, then paint the strip with the same widths/offsets rows use.
local function PaintProfessionHeaderStrip(strip)
    if not profHeaderDefByCol then
        profHeaderDefByCol = {}
        for hdi = 1, #HEADER_DEFS do
            profHeaderDefByCol[HEADER_DEFS[hdi].col] = HEADER_DEFS[hdi]
        end
    end
    local layout = ResolveProfessionColumnLayout()
    local cols = layout.cols
    for ci = 1, #cols do
        local col = cols[ci]
        local key = col.key
        local hdef = profHeaderDefByCol[key]
        local text = ""
        -- Open: per-row button only, no header label.
        if hdef and key ~= "open" then
            text = StripProfHeaderDisplayText((hdef.label and ns.L and ns.L[hdef.label]) or hdef.text or "")
            if key == "profName" and text == "" then
                text = StripProfHeaderDisplayText((ns.L and ns.L["GROUP_PROFESSION"]) or "Profession")
            end
        end
        col.label = text
        col.tooltip = (text ~= "") and text or nil
        col.align = (hdef and hdef.align) or "CENTER"
        col.sortable = (hdef and hdef.sortable and text ~= "") and true or false
        col.iconDef = (hdef and PROF_HEADER_ICON_BY_COL[key]) or nil
    end
    local sortState = GetColumnSortState()
    if sortState and sortState.col then
        strip:SetSort(sortState.col, sortState.dir == "asc")
    else
        strip:SetSort(nil)
    end
    strip:SetColumns(cols, layout.widths, layout.offsets, #cols)
    -- Data-grid-only dividers (after Profession, none before info), not the kit's every-gap dividers.
    ApplyProfessionColumnDividers(strip, COLUMN_HEADER_HEIGHT)
end

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
    ProfUI.ResetEquipResolveCache()
    SyncProfessionColumnOrder(WarbandNexus.db and WarbandNexus.db.profile)

    if ns.Utilities and ns.Utilities:IsModuleEnabled("professions") and WarbandNexus.RefreshCurrentCharacterKnowledgeProgress then
        WarbandNexus:RefreshCurrentCharacterKnowledgeProgress(true)
    end

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
    -- FLUSH grid (PvE parity): column header row starts at the top of the scroll body, no BODY_TOP gap.
    local scrollTopY = ns.UI_LAYOUT.PAGE_STACK.FLUSH
  -- Single stack width for title card, column headers, sections, and row chrome (Characters-tab parity).
    local stackWidth = (metrics and metrics.bodyWidth and metrics.bodyWidth > 0) and metrics.bodyWidth
        or (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent))
        or math.max(200, ((mf and mf.scroll and mf.scroll:GetWidth()) or 600) - contentSide * 2)
    ProfUI.SetCachedRowWidth(stackWidth)
    parent._wnProfBodyWidth = stackWidth
    parent._wnProfContentSide = contentSide

    -- If module is disabled, show disabled state card
    if not ns.Utilities:IsModuleEnabled("professions") then
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
        local CreateDisabledCard = ns.UI_CreateDisabledModuleCard
        -- No column header in the disabled state: standard body top, not the FLUSH grid top.
        local bodyTop = ns.UI_LAYOUT.PAGE_STACK.BODY_TOP
        local cardHeight = CreateDisabledCard(parent, bodyTop, (ns.L and ns.L["PROFESSIONS_DISABLED_TITLE"]) or "Professions")
        return bodyTop + cardHeight
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

    local tm = ns.UI_GetTitleCardToolbarMetrics and ns.UI_GetTitleCardToolbarMetrics() or {}
    local filterBtnW = tm.columnsW or (ns.UI_GetTitleToolbarPresetWidth and ns.UI_GetTitleToolbarPresetWidth("columns")) or 86
    local hdrGapEc = tm.gap or (GetLayout().HEADER_TOOLBAR_CONTROL_GAP) or 8
    local profToolbarReserve = (ns.UI_ComputeTitleToolbarReserve and ns.UI_ComputeTitleToolbarReserve({
        filterBtnW,
        tm.filterW or 96,
    })) or (filterBtnW + 40 + hdrGapEc)

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

    -- Midnight-only expansion data (no toolbar selector).
    self.db.profile.professionExpansionFilter = "Midnight"

    local toolbarLeft = titleCard

    local sortBtn
    if ns.UI_CreateCharacterTabAdvancedFilterButton then
        if ns.CharacterService and ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        end
        local sortOptions = (ns.UI_BuildCharacterSortOptions and ns.UI_BuildCharacterSortOptions())
            or {}
        if not self.db.profile.professionSort then self.db.profile.professionSort = {} end
        if not self.db.profile.professionSectionFilter then self.db.profile.professionSectionFilter = { sectionKey = "all" } end
        sortBtn = ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.professionSort,
            sortTabId = "professions",
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
            ns.UI_AnchorTitleToolbarControlRight(titleCard, sortBtn)
            toolbarLeft = sortBtn
        end
    elseif ns.UI_CreateCharacterSortDropdown then
        local sortOptions = (ns.UI_BuildCharacterSortOptions and ns.UI_BuildCharacterSortOptions())
            or {}
        if not self.db.profile.professionSort then self.db.profile.professionSort = {} end
        sortBtn = ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.professionSort, function()
            WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
        end, "professions")
        if sortBtn then
            ns.UI_AnchorTitleToolbarControlRight(titleCard, sortBtn)
            toolbarLeft = sortBtn
        end
    end

    local filterBtn = ns.UI_CreateTitleToolbarTextButton(titleCard, {
        preset = "columns",
        localeKey = "COLUMNS_BUTTON",
        onClick = function(btn)
            local menu = WarbandNexus._wnProfColumnPickerMenu
            if menu and menu:IsShown() and WarbandNexus._wnProfColumnPickerAnchorBtn == btn then
                menu:Hide()
                return
            end
            if not WarbandNexus.ShowProfessionColumnPicker then return end
            WarbandNexus:ShowProfessionColumnPicker(btn)
        end,
    })
    if filterBtn and toolbarLeft then
        ns.UI_ChainTitleToolbarControl(titleCard, filterBtn, toolbarLeft)
    end

    if filterBtn and WarbandNexus._wnProfColumnPickerMenu and WarbandNexus._wnProfColumnPickerMenu:IsShown() then
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

    if ns.UI_HideTitleCardExpandCollapseControls then
        ns.UI_HideTitleCardExpandCollapseControls(parent)
    end

    titleCard:Show()
    -- FLUSH exception: title -> column-header grid gap is PAGE_STACK.FLUSH.
    if chrome and ns.UI_PageStack_Place then
        headerYOffset = ns.UI_PageStack_Place(chrome, titleCard, nil, "FLUSH")
    else
        headerYOffset = headerYOffset + (titleCard:GetHeight() or 64) + ns.UI_LAYOUT.PAGE_STACK.FLUSH
    end
    if ns.UI_CommitTabFixedHeader then ns.UI_CommitTabFixedHeader(mf, headerYOffset) elseif fixedHeader then fixedHeader:SetHeight(headerYOffset) end

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

    -- One TableKit header strip (compact: icon over label, 1px accent rule); x/w from the shared resolved layout.
    local colHeaderBar = parent._wnProfColHeaderRow
    if not colHeaderBar then
        colHeaderBar = ns.UI_TableKit.CreateHeaderStrip(parent, PROF_HEADER_STRIP_OPTS)
        parent._wnProfColHeaderRow = colHeaderBar
    end
    ReattachProfessionColumnHeaderBar(colHeaderBar, parent)
    colHeaderBar:SetHeight(COLUMN_HEADER_HEIGHT)
    colHeaderBar:ClearAllPoints()
    colHeaderBar:SetPoint("TOPLEFT", parent, "TOPLEFT", contentSide, -scrollTopY)
    colHeaderBar:SetWidth(math.max(1, profStackW))
    PaintProfessionHeaderStrip(colHeaderBar)
    colHeaderBar:Show()

    local yOffset = scrollTopY + COLUMN_HEADER_HEIGHT + COLUMN_HEADER_PAD

    if parent._wnProfEmptyScrollText then
        parent._wnProfEmptyScrollText:Hide()
    end
    HideEmptyStateCard(parent, "professions")
    if totalProfChars == 0 then
        if ns.UI_ShowTabEmptyStateCard then
            -- parent is the scroll child: page-stack side inset, no extra trailing pad (extent includes it).
            return ns.UI_ShowTabEmptyStateCard(parent, "professions", yOffset, { fillParent = false, sideInset = ns.UI_LAYOUT.PAGE_STACK.SIDE })
        end
        return yOffset + 100
    end

    local currentPlayerKey = (ns.UI_GetSubsidiaryCharKey and ns.UI_GetSubsidiaryCharKey())
        or (ns.CharacterService and ns.CharacterService.ResolveSubsidiaryCharacterKey and ns.CharacterService:ResolveSubsidiaryCharacterKey(WarbandNexus, nil))
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

    local rosterSortKey = (ns.CharacterService and ns.CharacterService.GetTabSortKey)
        and ns.CharacterService:GetTabSortKey(self.db.profile, "professions") or "default"
    local colSortCmp = (rosterSortKey == "manual") and GetColumnSortCharComparator() or nil
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
    local SECTION_HEADER_GAP = ns.UI_LAYOUT.PAGE_STACK.SECTION_GAP
    local previousSectionContent = nil
    local previousSectionHeader = nil
    local previousSectionExpanded = false
    local isFirstSection = true
    local sectionRows = parent._wnProfNestedRows
    parent._wnProfSectionHeaders = {}
    -- Section headers and content frames are pooled on the scroll child (SectionPool, "prf:" keys)
    -- and re-bound every paint instead of being recreated and parked in the recycle bin (2026-10-22).
    local SP = ns.UI_SectionPool
    SP.BeginPass(parent)
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

    local function AcquireSectionContentFrame(anchorHeader, poolKey)
        local hostW = math.max(1, profStackW)
        local Fact = ns.UI and ns.UI.Factory
        local contentFrame
        if Fact and Fact.CreateContainer then
            contentFrame = SP.Acquire(parent, "prf:content:" .. poolKey, anchorHeader, hostW, 1)
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
            SP.HeaderOpts(parent, "prf:hdr:" .. tostring(sectionKey), headerVisualOpts)
        )
        SP.Remember(parent, "prf:hdr:" .. tostring(sectionKey), header)
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
            local countMarkup = ((visualOpts and visualOpts.sectionPreset == "danger") and TextRoleHex("Dim")) or TextRoleHex("Muted")
            if not header._wnProfSectionCount then
                header._wnProfSectionCount = FontManager:CreateFontString(header, FontManager:GetFontRole("mainNavTabCount"), "OVERLAY")
            end
            profSectionCount = header._wnProfSectionCount
            profSectionCount:SetJustifyH("RIGHT")
            profSectionCount:SetText(countMarkup .. FormatNumber(#chars) .. "|r")
            profSectionCount:Show()
        elseif header._wnProfSectionCount then
            -- Hide legacy per-tab count so the unified helper's count is the only badge shown.
            header._wnProfSectionCount:Hide()
        end

        sectionContent = AcquireSectionContentFrame(header, tostring(sectionKey))
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

    -- Collapsed-state hint removed: sections keep whatever expand state the user
    -- left them in, with no notice row and no stack push-down.
    if parent._wnProfCollapsedHint then
        parent._wnProfCollapsedHint:Hide()
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
        ProfUI.RunChunkedRowPaint(self, parent, chunkQueue, drawGen, {
            profStackW = profStackW,
            currentPlayerKey = currentPlayerKey,
            rowIndex = rowIndex,
            onComplete = function()
                parent._wnProfChunkPending = nil
                parent._wnProfEstimatedScrollBody = nil
                parent._wnProfQueuedRowCount = nil
                FinishProfessionsTabChrome(parent)
                local profMod = ns.ProfessionsUI
                if profMod and profMod.FlushDeferredShellRefresh then
                    profMod.FlushDeferredShellRefresh()
                end
            end,
        })
    else
        FinishProfessionsTabChrome(parent)
    end

    local retH = yOffset + 10
    if parent._wnProfEstimatedScrollBody and parent._wnProfEstimatedScrollBody > retH then
        retH = parent._wnProfEstimatedScrollBody
    end
    return retH
end

