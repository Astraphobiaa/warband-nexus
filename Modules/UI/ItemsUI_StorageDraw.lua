--[[ ItemsUI storage tree draw (ops split) ]]
local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local B = assert(ns.ItemsUI and ns.ItemsUI._bind, "ItemsUI_StorageDraw: load Modules/UI/ItemsUI.lua first")
local issecretvalue = issecretvalue
local format = string.format
local ipairs = ipairs
local pairs = pairs
local wipe = wipe
local tinsert = table.insert
local InCombatLockdown = InCombatLockdown
local C_Timer = C_Timer
local FormatNumber = ns.UI_FormatNumber
local L = ns.L
local GetQualityHex = ns.UI_GetQualityHex
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip
local GetLayout = B.GetLayout
local SIDE_MARGIN = B.SIDE_MARGIN
local BASE_INDENT = B.BASE_INDENT
local SECTION_SPACING = B.SECTION_SPACING
local ITEMS_BANK_SUBTAB_BTN_HEIGHT = B.ITEMS_BANK_SUBTAB_BTN_HEIGHT
local STORAGE_ROW_HEIGHT = B.STORAGE_ROW_HEIGHT
local STORAGE_ROW_STRIDE = B.STORAGE_ROW_STRIDE
local STORAGE_LEAF_ROW_CHUNK = B.STORAGE_LEAF_ROW_CHUNK
local STORAGE_LEAF_ROW_SYNC_MAX = B.STORAGE_LEAF_ROW_SYNC_MAX
local STORAGE_LEAF_ROW_SYNC_MAX_EMBED = B.STORAGE_LEAF_ROW_SYNC_MAX_EMBED
local STORAGE_WARBAND_TYPE_CHUNK_EMBED = B.STORAGE_WARBAND_TYPE_CHUNK_EMBED
local STORAGE_WARBAND_TYPE_SYNC_MAX_EMBED = B.STORAGE_WARBAND_TYPE_SYNC_MAX_EMBED
local STORAGE_WARBAND_TYPE_CHUNK = B.STORAGE_WARBAND_TYPE_CHUNK
local STORAGE_WARBAND_TYPE_SYNC_MAX = B.STORAGE_WARBAND_TYPE_SYNC_MAX
local STORAGE_CHAR_CHUNK_EMBED = B.STORAGE_CHAR_CHUNK_EMBED
local STORAGE_CHAR_SYNC_MAX_EMBED = B.STORAGE_CHAR_SYNC_MAX_EMBED
local STORAGE_CHAR_CHUNK = B.STORAGE_CHAR_CHUNK
local STORAGE_CHAR_SYNC_MAX = B.STORAGE_CHAR_SYNC_MAX
local ItemsDimMarkup = B.ItemsDimMarkup
local FormatItemsBankStatsLine = B.FormatItemsBankStatsLine
local ResolveItemsSubTabStatsMetrics = B.ResolveItemsSubTabStatsMetrics
local CanViewGuildBankSubTab = B.CanViewGuildBankSubTab
local ItemsUsesStorageTreeEmbed = B.ItemsUsesStorageTreeEmbed
local ItemsWarbandUsesStorageTree = B.ItemsWarbandUsesStorageTree
local ItemsGuildUsesStorageTree = B.ItemsGuildUsesStorageTree
local ItemsResultsTopGap = B.ItemsResultsTopGap
local PackChildrenInto = B.PackChildrenInto
local _wnStorTopScratch = B._wnStorTopScratch
local EnsureWarbandDrawIndicator = B.EnsureWarbandDrawIndicator
local ReflowStorageStackParentBody = B.ReflowStorageStackParentBody
local MeasureStorageResultsContentExtent = B.MeasureStorageResultsContentExtent
local SyncItemsTabScrollChrome = B.SyncItemsTabScrollChrome
local StorageChunkedPaintStillValid = B.StorageChunkedPaintStillValid
local CompareCharNameLower = B.CompareCharNameLower
local ShowItemsSearchEmptyState = B.ShowItemsSearchEmptyState
local ShowItemsResultsEmptyState = B.ShowItemsResultsEmptyState
local SafeLower = B.SafeLower
local StorageSectionLayout = B.StorageSectionLayout
local BuildCollapsibleSectionOpts = B.BuildCollapsibleSectionOpts
local CreateCollapsibleHeader = B.CreateCollapsibleHeader
local ChainSectionFrameBelow = B.ChainSectionFrameBelow
local GetTypeIcon = B.GetTypeIcon
local AcquireStorageRow = B.AcquireStorageRow
local ReleaseStorageRow = B.ReleaseStorageRow
local ReleasePooledRowsInSubtree = B.ReleasePooledRowsInSubtree
local CreateResultsContainer = B.CreateResultsContainer
local ResolveItemCategoryName = B.ResolveItemCategoryName
local GetItemClassID = B.GetItemClassID
local GetItemTypeName = B.GetItemTypeName
local FontManager = B.FontManager
local StorageScanAllowLazyBackfill = B.StorageScanAllowLazyBackfill
local StorageTreeHasExpandedPrefixCategory = B.StorageTreeHasExpandedPrefixCategory
local StorageEmbedHasVisibleExpandedSections = B.StorageEmbedHasVisibleExpandedSections
local StoragePersonalSectionVisible = B.StoragePersonalSectionVisible
local StorageWarbandSectionVisible = B.StorageWarbandSectionVisible
local StorageGuildSectionVisible = B.StorageGuildSectionVisible

ns.ItemsUI = ns.ItemsUI or {}

--- Extracted from DrawStorageResults — nested row paint must not capture 60+ DrawStorage upvalues (Lua 5.1).
local function ItemsUI_PopulateStorageRowDirect(row, item, rowIdx, rowWidth, locText)
    local U = ns.Utilities
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end
    ns.UI.Factory:ApplyRowBackground(row, rowIdx)

    row.qtyText:SetText(ns.UI_FormatStackCountMarkup and ns.UI_FormatStackCountMarkup(item.stackCount or 1)
        or format("|cffffcc00%s|r", FormatNumber(item.stackCount or 1)))
    row.icon:SetTexture(U and U.ResolveItemRowIcon and U:ResolveItemRowIcon(item) or (item.iconFileID or 134400))

    local nameCache = ns.ItemsUI._storageNameCache
    local baseName = item.name
    if not baseName and item.link and not (issecretvalue and issecretvalue(item.link)) then
        baseName = item.link:match("%[(.-)%]")
    end
    if not baseName and item.pending then
        baseName = (ns.L and ns.L["ITEM_LOADING_NAME"]) or "Loading..."
    end
    if not baseName and item.itemID and nameCache then
        local iid = item.itemID
        local cachedName = nameCache[iid]
        if cachedName == nil then
            cachedName = C_Item.GetItemInfo(iid) or false
            nameCache[iid] = cachedName
        end
        if cachedName and cachedName ~= false then
            baseName = cachedName
        end
    end
    baseName = baseName or format((ns.L and ns.L["ITEM_FALLBACK_FORMAT"]) or "Item %s", tostring(item.itemID or "?"))

    local displayName = WarbandNexus:GetItemDisplayName(item.itemID, baseName, item.classID)
    if item.pending then
        row.nameText:SetText(ItemsDimMarkup(displayName))
    else
        row.nameText:SetText(format("|cff%s%s|r", GetQualityHex(item.quality), displayName))
    end

    row.locationText:SetText(locText or "")
    ns.UI_SetTextColorRole(row.locationText, "Bright")
    row.locationText:SetWordWrap(false)
    row.locationText:SetNonSpaceWrap(false)

    row:SetScript("OnEnter", function(self)
        if not ShowTooltip then
            if item.itemLink then
                ns.TooltipService:Show(self, { type = "item", itemID = item.itemID, itemLink = item.itemLink })
            end
            return
        end
        ShowTooltip(self, { type = "item", itemID = item.itemID, itemLink = item.itemLink })
    end)
    row:SetScript("OnLeave", function()
        if HideTooltip then HideTooltip() else ns.TooltipService:Hide() end
    end)
end

function WarbandNexus:ScheduleStorageResultsRedraw()
    if self._wnStorageResultsRedrawPending then
        return
    end
    self._wnStorageResultsRedrawPending = true
    if not (C_Timer and C_Timer.After) then
        self._wnStorageResultsRedrawPending = nil
        if self.RedrawStorageResultsOnly then
            self:RedrawStorageResultsOnly()
        end
        return
    end
    C_Timer.After(0, function()
        self._wnStorageResultsRedrawPending = nil
        if self.RedrawStorageResultsOnly then
            self:RedrawStorageResultsOnly()
        end
    end)
end

function WarbandNexus:DrawStorageResults(parent, yOffset, width, storageSearchText)
    local mfPaint = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfPaint and (mfPaint.currentTab ~= "items" or not ItemsUsesStorageTreeEmbed()) then
        return yOffset or 0
    end
    local leafPaintGen = 0
    if mfPaint then
        leafPaintGen = (mfPaint._wnStorageLeafPaintGen or 0) + 1
        mfPaint._wnStorageLeafPaintGen = leafPaintGen
        mfPaint._wnStorageLeafStage = { gen = leafPaintGen, pending = 0 }
    end

    local storageSearchActive = storageSearchText
        and not (issecretvalue and issecretvalue(storageSearchText))
        and storageSearchText ~= ""

    local mfEmbed = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local embedItemsWarband = mfEmbed and mfEmbed.currentTab == "items" and ItemsWarbandUsesStorageTree()
    local embedItemsGuild = mfEmbed and mfEmbed.currentTab == "items" and ItemsGuildUsesStorageTree()
    local searchResultTabKey = (embedItemsWarband or embedItemsGuild) and "items" or "storage"
    local emptyRenderTab = (embedItemsWarband or embedItemsGuild) and "items" or "storage"
    local stackW = (ns.UI_ResolveListContentWidth and ns.UI_ResolveListContentWidth(parent, width, 0)) or width
    --- Match Bags/Bank/Guild virtual list: first major section sits below SECTION_SPACING from container top.
    local resultsTopGap = ItemsResultsTopGap(yOffset)

    -- Type leaf toggles: WarbandNexus:_ApplyStorageTypeLeafTogglePartial (CreateCollapsibleHeader calls
    -- onToggle before expand height; see SharedWidgets expand branch).

    local P = ns.Profiler
    local profOn = P and P.enabled
    local function stStart(name)
        if profOn and P.StartSlice then P:StartSlice(P.CAT.UI, name) end
    end
    local function stStop(name)
        if profOn and P.StopSlice then P:StopSlice(P.CAT.UI, name) end
    end

    stStart("Stor_teardown")
    local mfForVirtual = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mfForVirtual and ns.VirtualListModule and ns.VirtualListModule.ClearVirtualScroll then
        ns.VirtualListModule.ClearVirtualScroll(mfForVirtual)
    end

    -- Clean up rows created for subheader section containers in previous render.
    if parent._wnStorageAnimatedRows and ReleaseStorageRow then
        for i = 1, #parent._wnStorageAnimatedRows do
            local row = parent._wnStorageAnimatedRows[i]
            if row and row.rowType == "storage" then
                ReleaseStorageRow(row)
            end
        end
    end
    parent._wnStorageAnimatedRows = {}

    -- Clean up old children (headers, section containers, rows) from previous render.
    local recycleBin = ns.UI_RecycleBin
    if ReleasePooledRowsInSubtree then
        ReleasePooledRowsInSubtree(parent)
    end
    local nTop = PackChildrenInto(_wnStorTopScratch, parent)
    for i = 1, nTop do
        local child = _wnStorTopScratch[i]
        if not child._isVirtualRow and not child._wnSkipStorageTeardown then
            child:Hide()
            child:ClearAllPoints()
            child:SetParent(recycleBin or UIParent)
        end
    end
    stStop("Stor_teardown")

    parent._wnStorageApplyRowVisual = nil
    if not parent._wnStorageRowRefs then
        parent._wnStorageRowRefs = {}
    else
        wipe(parent._wnStorageRowRefs)
    end

    local loadIndicator = nil
    local function hideWarbandBanner()
        if loadIndicator then loadIndicator:Hide() end
    end
    --- Delay hiding the Warband "building" banner while staged leaf renders are pending (same generation).
    local function hideDrawIndicatorWithStagingGate()
        if mfPaint and mfPaint._wnStorageLeafStage then
            local st = mfPaint._wnStorageLeafStage
            if st.gen == leafPaintGen and (st.pending or 0) > 0 then
                return
            end
        end
        hideWarbandBanner()
    end
    loadIndicator = EnsureWarbandDrawIndicator(parent)

    local globalRowIdxAll = 0
    --- Vertical chain tail: major headers + type wraps share one anchor stack so sibling layout
    --- tracks section height immediately (instant layout; no tween).
    local storageStackAnchor = nil

    -- Session-only expand state (see WarbandNexus:GetStorageTreeExpandState / ResetStorageTreeExpandState in Core.lua).
    local expanded = self:GetStorageTreeExpandState()

    local function CreateStorageRowsContainer(contentParent, anchorFrame, leftOffset, rightOffset)
        contentParent = contentParent or parent
        local frame = ns.UI.Factory:CreateContainer(contentParent, math.max(1, contentParent:GetWidth()), 1, false)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", anchorFrame, "BOTTOMLEFT", leftOffset or 0, 0)
        frame:SetPoint("TOPRIGHT", anchorFrame, "BOTTOMRIGHT", rightOffset or 0, 0)
        frame:SetHeight(0.1)
        frame._wnSectionFullH = 0
        return frame
    end

    local TYPE_SECTION_HEADER_H = StorageSectionLayout.GetTypeSectionHeaderHeight()
    local MAIN_SECTION_HEADER_H = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36

    --- After a type (leaf) section height change, section bodies/wraps above the type row stay at initial heights.
    --- Reflow measured stacks so character rows and items below sit below expanded content (not drawn on top).
    --- ctx: { contentBody, sectionWrap, sectionHeaderH, stackParent?, outerSectionWrap?, outerSectionHeaderH? }
    local function ApplyStorageLeafAncestorReflow(ctx)
        if not ctx or not ctx.contentBody or not ctx.sectionWrap or not ctx.sectionHeaderH then return end
        ReflowStorageStackParentBody(ctx.contentBody, ctx.sectionWrap, ctx.sectionHeaderH)
        ctx.contentBody._wnSectionFullH = math.max(0.1, ctx.contentBody:GetHeight() or 0.1)
        if ctx.stackParent and ctx.outerSectionWrap and ctx.outerSectionHeaderH then
            ReflowStorageStackParentBody(ctx.stackParent, ctx.outerSectionWrap, ctx.outerSectionHeaderH)
            ctx.stackParent._wnSectionFullH = math.max(0.1, ctx.stackParent:GetHeight() or 0.1)
        end
        WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
    end

    --- Major section (Personal / Warband / Guild / character): wrapped header + body (instant expand/collapse).
    --- Optional `stackReflowCtx`: { stackParent, outerWrap, outerHeaderH } for nested stacks (Personal â†’ characters).
    --- Optional `sectionPreset`: SharedWidgets_Collapsible chrome (`accent`, `gold`, `danger`).
    local function MajorStorageSectionOpts(wrapFrame, bodyGetter, headerH, persistFn, stackReflowCtx, sectionPreset)
        local opts = BuildCollapsibleSectionOpts({
            wrapFrame = wrapFrame,
            bodyGetter = bodyGetter,
            headerHeight = headerH,
            hideOnCollapse = true,
            persistFn = function(exp)
                if type(exp) == "boolean" and persistFn then
                    persistFn(exp)
                end
            end,
            -- Per-frame: outer stack tracks wrap tween; defer full SyncStorageResultsLayoutFromTail to onComplete.
            onUpdate = function(_drawH)
                if stackReflowCtx and stackReflowCtx.stackParent then
                    ReflowStorageStackParentBody(
                        stackReflowCtx.stackParent,
                        stackReflowCtx.outerWrap,
                        stackReflowCtx.outerHeaderH
                    )
                end
            end,
            onComplete = function(exp)
                if not exp then
                    local b = bodyGetter()
                    if b then
                        b:Hide()
                        b:SetHeight(0.1)
                    end
                end
                if stackReflowCtx and stackReflowCtx.stackParent then
                    ReflowStorageStackParentBody(
                        stackReflowCtx.stackParent,
                        stackReflowCtx.outerWrap,
                        stackReflowCtx.outerHeaderH
                    )
                end
                WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            end,
            -- Bodies that were collapsed during this DrawStorageResults pass never ran the inner build; they keep
            -- placeholder _wnSectionFullH (~0.1). CreateCollapsibleHeader expand uses that height and the char
            -- onToggle is a no-op, so rows stay missing until a full tab redraw. Rebuild next frame (defer: avoid
            -- tearing down the clicked header inside its own OnClick).
            refreshFn = function(exp)
                if not exp then return end
                local populate = wrapFrame and wrapFrame._wnStorageMajorPopulateFn
                if type(populate) == "function" then
                    populate()
                    local b = bodyGetter()
                    if b and b._wnSectionFullH and b._wnSectionFullH >= 2 then
                        if wrapFrame and headerH then
                            wrapFrame:SetHeight(headerH + b:GetHeight())
                        end
                        WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
                        return
                    end
                end
                local b = bodyGetter()
                local fh = b and b._wnSectionFullH
                if fh and fh < 2 and WarbandNexus.ScheduleStorageResultsRedraw then
                    WarbandNexus:ScheduleStorageResultsRedraw()
                end
            end,
        }) or {}
        if sectionPreset then
            opts.sectionPreset = sectionPreset
        end
        return opts
    end

    --- Leaf type rows live under `rowsContainer`; instant resize without full tab redraw.
    --- Optional `ancestorReflowCtx`: reflow char/warband/guild section + Personal outer after height changes.
    local function LeafTypeSectionVisualOpts(wrapFrame, rowsGetter, leafKey, ancestorReflowCtx)
        return BuildCollapsibleSectionOpts({
            wrapFrame = wrapFrame,
            bodyGetter = rowsGetter,
            headerHeight = TYPE_SECTION_HEADER_H,
            hideOnCollapse = true,
            persistFn = function(exp)
                if type(exp) == "boolean" then
                    expanded.categories[leafKey] = exp
                end
            end,
            onUpdate = function(_drawH)
                if ancestorReflowCtx then
                    ApplyStorageLeafAncestorReflow(ancestorReflowCtx)
                end
            end,
            onComplete = function(exp)
                if not exp then
                    local rc = rowsGetter()
                    if rc then
                        rc:Hide()
                        rc:SetHeight(0.1)
                    end
                end
                if ancestorReflowCtx then
                    ApplyStorageLeafAncestorReflow(ancestorReflowCtx)
                else
                    WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
                end
            end,
        })
    end

    -- Per-draw caches: class/type work repeats per slot; rows duplicate C_Item.GetItemInfo for shared itemIDs (cold charsâ†’storage path).
    local storageDrawClassIDByItemID = {}
    local storageDrawTypeNameByClassID = {}
    local storageDrawItemInfoNameByItemID = {}
    ns.ItemsUI._storageNameCache = storageDrawItemInfoNameByItemID

    local function ResolvedStorageClassID(entry)
        if entry.classID then return entry.classID end
        local id = entry.itemID
        if not id then return 15 end
        local c = storageDrawClassIDByItemID[id]
        if not c then
            c = GetItemClassID(id)
            storageDrawClassIDByItemID[id] = c
        end
        entry.classID = c
        return c
    end

    local function ResolvedStorageTypeName(entry)
        if ResolveItemCategoryName then
            return ResolveItemCategoryName(entry)
        end
        local classID = ResolvedStorageClassID(entry)
        local t = storageDrawTypeNameByClassID[classID]
        if not t then
            t = GetItemTypeName(classID)
            storageDrawTypeNameByClassID[classID] = t
        end
        return t
    end

    -- Search filtering helper
    local function ItemMatchesSearch(item)
        if not storageSearchActive then
            return true
        end
        local itemName = SafeLower(item.name)
        local linkStr = item.itemLink or item.link
        local itemLink = SafeLower(linkStr)
        return itemName:find(storageSearchText, 1, true) or itemLink:find(storageSearchText, 1, true)
    end

    --- Type-leaf item rows under a collapsible header (`rowsContainer`).
    --- Warband/storage aggregate: small lists sync; larger lists chunked via `STORAGE_LEAF_ROW_*` + paint generation cancel (`WN-PERF-warband-nexus`).
    local function RenderStorageLeafRows(rowsContainer, rowWidth, typeItemsForRows, locTextForItem)
        rowsContainer._wnVirtualContentHeight = nil
        if not rowsContainer then
            return 0
        end
        local stride = STORAGE_ROW_STRIDE

        local matchN = 0
        for mxi = 1, #typeItemsForRows do
            if ItemMatchesSearch(typeItemsForRows[mxi]) then
                matchN = matchN + 1
            end
        end
        if matchN <= 0 then
            rowsContainer:SetHeight(0.1)
            rowsContainer._wnStorageLeafStaging = nil
            return 0
        end

        local function finalizeSyncedHeight(yy)
            if yy <= 0 then
                rowsContainer:SetHeight(0.1)
                return 0
            end
            rowsContainer._wnVirtualContentHeight = yy
            rowsContainer:SetHeight(math.max(0.1, yy))
            return yy
        end

        local rowSyncMax = embedItemsWarband and STORAGE_LEAF_ROW_SYNC_MAX_EMBED or STORAGE_LEAF_ROW_SYNC_MAX
        if matchN <= rowSyncMax then
            local yy = 0
            for ti = 1, #typeItemsForRows do
                local item = typeItemsForRows[ti]
                if ItemMatchesSearch(item) then
                    globalRowIdxAll = globalRowIdxAll + 1
                    local row = AcquireStorageRow(rowsContainer, rowWidth, STORAGE_ROW_HEIGHT)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", rowsContainer, "TOPLEFT", 0, -yy)
                    row:Show()
                    pcall(ItemsUI_PopulateStorageRowDirect, row, item, globalRowIdxAll, rowWidth, locTextForItem(item))
                    row._wnStorageItemRef = item
                    row._wnStorageRowIdx = globalRowIdxAll
                    row._wnStorageLocText = locTextForItem(item) or ""
                    table.insert(parent._wnStorageRowRefs, row)
                    yy = yy + stride
                end
            end
            rowsContainer._wnStorageLeafStaging = nil
            return finalizeSyncedHeight(yy)
        end

        local reservedH = matchN * stride
        rowsContainer:SetHeight(math.max(0.1, reservedH))
        rowsContainer._wnVirtualContentHeight = reservedH
        rowsContainer._wnStorageLeafStaging = true

        local stPatch = mfPaint and mfPaint._wnStorageLeafStage
        if stPatch and stPatch.gen == leafPaintGen then
            stPatch.pending = (stPatch.pending or 0) + 1
        end

        local leafCreditConsumed = false
        local function consumeLeafStagingCredit()
            if leafCreditConsumed then return end
            leafCreditConsumed = true
            local st = mfPaint and mfPaint._wnStorageLeafStage
            if st and st.gen == leafPaintGen then
                st.pending = math.max(0, (st.pending or 1) - 1)
                if st.pending <= 0 then
                    hideWarbandBanner()
                end
            end
        end

        local function chromeAfterChunk()
            WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            if embedItemsWarband and mfPaint then
                local sc = parent:GetParent()
                if sc then
                    local ext = MeasureStorageResultsContentExtent(parent)
                    SyncItemsTabScrollChrome(mfPaint, sc, ext or (parent.GetHeight and parent:GetHeight()) or 1)
                end
            end
        end

        local tiCursor = 1
        local yAcc = 0
        if loadIndicator then loadIndicator:Show() end

        local function processChunk()
            if not StorageChunkedPaintStillValid(mfPaint, leafPaintGen) then
                consumeLeafStagingCredit()
                return
            end
            if InCombatLockdown and InCombatLockdown() then
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, processChunk)
                end
                return
            end

            local emittedThis = 0
            while tiCursor <= #typeItemsForRows do
                if emittedThis >= STORAGE_LEAF_ROW_CHUNK then
                    break
                end
                local item = typeItemsForRows[tiCursor]
                tiCursor = tiCursor + 1
                if ItemMatchesSearch(item) then
                    globalRowIdxAll = globalRowIdxAll + 1
                    local row = AcquireStorageRow(rowsContainer, rowWidth, STORAGE_ROW_HEIGHT)
                    row:ClearAllPoints()
                    row:SetPoint("TOPLEFT", rowsContainer, "TOPLEFT", 0, -yAcc)
                    row:Show()
                    pcall(ItemsUI_PopulateStorageRowDirect, row, item, globalRowIdxAll, rowWidth, locTextForItem(item))
                    row._wnStorageItemRef = item
                    row._wnStorageRowIdx = globalRowIdxAll
                    row._wnStorageLocText = locTextForItem(item) or ""
                    table.insert(parent._wnStorageRowRefs, row)
                    yAcc = yAcc + stride
                    emittedThis = emittedThis + 1
                end
            end

            rowsContainer._wnVirtualContentHeight = math.max(yAcc, 1)
            rowsContainer:SetHeight(math.max(0.1, reservedH))
            chromeAfterChunk()

            if tiCursor > #typeItemsForRows then
                rowsContainer._wnVirtualContentHeight = yAcc
                rowsContainer:SetHeight(math.max(0.1, yAcc))
                rowsContainer._wnStorageLeafStaging = nil
                consumeLeafStagingCredit()
                chromeAfterChunk()
                return
            end

            if C_Timer and C_Timer.After then
                C_Timer.After(0, processChunk)
            else
                processChunk()
            end
        end

        if C_Timer and C_Timer.After then
            C_Timer.After(0, processChunk)
        else
            processChunk()
        end

        return reservedH
    end
    
    stStart("Stor_scan")
    -- PRE-SCAN: If search is active, find which categories have matches
    local categoriesWithMatches = {}
    local hasAnyMatches = false
    local allCharacters = self:GetAllCharacters() or {}
    local trackedCharacters = {}
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        if char.isTracked ~= false then
            trackedCharacters[#trackedCharacters + 1] = char
        end
    end

    -- Search: personal/warband/guild match counts from pre-scan. No-search: tallied in hasAnyData pass.
    local personalTotalMatches = 0
    local warbandTotalMatches = 0
    local guildTotalMatches = 0
    
    if storageSearchActive then
        if embedItemsGuild then
            local gb = self.db.global.guildBank
            if gb then
                for guildName, guildData in pairs(gb) do
                    if guildName and not (issecretvalue and issecretvalue(guildName)) and guildData then
                        for _, tabData in pairs(guildData.tabs or {}) do
                            for _, item in pairs(tabData.items or {}) do
                                if item.itemID and ItemMatchesSearch(item) then
                                    local classID = ResolvedStorageClassID(item)
                                    local typeName = ResolvedStorageTypeName(item)
                                    local guildCategoryKey = "guild_" .. guildName
                                    local typeKey = guildCategoryKey .. "_" .. typeName
                                    categoriesWithMatches[typeKey] = true
                                    categoriesWithMatches[guildCategoryKey] = true
                                    hasAnyMatches = true
                                    guildTotalMatches = guildTotalMatches + 1
                                end
                            end
                        end
                    end
                end
            end
        else
        -- Scan Warband Bank (NEW ItemsCacheService API)
        local warbandData = self:GetWarbandBankData()
        if warbandData and warbandData.items then
            local wbItems = warbandData.items
            for ii = 1, #wbItems do
                local item = wbItems[ii]
                if item.itemID and ItemMatchesSearch(item) then
                    local classID = ResolvedStorageClassID(item)
                    local typeName = ResolvedStorageTypeName(item)
                    local categoryKey = "warband_" .. typeName
                    categoriesWithMatches[categoryKey] = true
                    categoriesWithMatches["warband"] = true
                    hasAnyMatches = true
                    warbandTotalMatches = warbandTotalMatches + 1
                end
            end
        end
        
        -- Scan Personal Items (Bank + Bags) (NEW ItemsCacheService API)
        -- Direct DB access (DB-First pattern)
        local characters = trackedCharacters
        
        for ci = 1, #characters do
            local char = characters[ci]
            local charKey = char._key
            local itemsData = self:GetItemsData(charKey)
            if itemsData then
                -- Scan bags
                if itemsData.bags then
                    local bags = itemsData.bags
                    for bi = 1, #bags do
                        local item = bags[bi]
                        if item.itemID and ItemMatchesSearch(item) then
                            local classID = ResolvedStorageClassID(item)
                            local typeName = ResolvedStorageTypeName(item)
                            local charCategoryKey = "personal_" .. charKey
                            local typeKey = charCategoryKey .. "_" .. typeName
                            categoriesWithMatches[typeKey] = true
                            categoriesWithMatches[charCategoryKey] = true
                            categoriesWithMatches["personal"] = true
                            hasAnyMatches = true
                            personalTotalMatches = personalTotalMatches + 1
                        end
                    end
                end
                
                -- Scan bank
                if itemsData.bank then
                    local bankItems = itemsData.bank
                    for bi = 1, #bankItems do
                        local item = bankItems[bi]
                        if item.itemID and ItemMatchesSearch(item) then
                            local classID = ResolvedStorageClassID(item)
                            local typeName = ResolvedStorageTypeName(item)
                            local charCategoryKey = "personal_" .. charKey
                            local typeKey = charCategoryKey .. "_" .. typeName
                            categoriesWithMatches[typeKey] = true
                            categoriesWithMatches[charCategoryKey] = true
                            categoriesWithMatches["personal"] = true
                            hasAnyMatches = true
                            personalTotalMatches = personalTotalMatches + 1
                        end
                    end
                end
            end
        end
        
        end -- not embedItemsGuild search branch
    end
    
    -- If search is active but no matches, show empty state and return
    if storageSearchActive and not hasAnyMatches then
        stStop("Stor_scan")
        hideDrawIndicatorWithStagingGate()
        local height = ShowItemsSearchEmptyState(parent, storageSearchText, yOffset)
        SearchStateManager:UpdateResults(searchResultTabKey, 0)
        return height
    end
    
    -- Quick check for general "no data" empty state (no search). Also tally personal item rows once.
    if not storageSearchActive then
        local hasAnyData = false
        local expandAllActive = self.storageExpandAllActive == true

        if embedItemsGuild then
            local entries = self.GetGuildBankSortedEntries and self:GetGuildBankSortedEntries() or {}
            for ei = 1, #entries do
                local gd = entries[ei].data
                local slots = gd.usedSlots or 0
                if slots <= 0 and self.CountGuildBankOccupiedSlots then
                    slots = self:CountGuildBankOccupiedSlots(gd)
                end
                guildTotalMatches = guildTotalMatches + slots
                if slots > 0 or (gd.cachedGold or 0) > 0 then
                    hasAnyData = true
                end
            end
            if not hasAnyData and StorageTreeHasExpandedPrefixCategory(expanded, "guild_") then
                hasAnyData = true
            end
        else
        local allowBackfill = StorageScanAllowLazyBackfill(embedItemsWarband, expanded, expandAllActive)

        local wbSlots, _, wbLast = 0, 0, 0
        if self.GetWarbandBankOccupiedSlotTally then
            wbSlots, _, wbLast = self:GetWarbandBankOccupiedSlotTally(allowBackfill)
        end
        if wbSlots > 0 or (not allowBackfill and wbLast > 0) then
            hasAnyData = true
            warbandTotalMatches = math.max(wbSlots, (wbLast > 0 and 1 or 0))
        end

        for i = 1, #trackedCharacters do
            local char = trackedCharacters[i]
            local charKey = char._key
            local bagN, _, bagLast = 0, 0, 0
            local bankN, _, bankLast = 0, 0, 0
            if self.GetItemStorageOccupiedSlotTally then
                bagN, _, bagLast = self:GetItemStorageOccupiedSlotTally(charKey, "bags", allowBackfill)
                bankN, _, bankLast = self:GetItemStorageOccupiedSlotTally(charKey, "bank", allowBackfill)
            else
                local itemsData = self:GetItemsData(charKey)
                if itemsData then
                    bagN = itemsData.bags and #itemsData.bags or 0
                    bankN = itemsData.bank and #itemsData.bank or 0
                    bagLast = itemsData.bagsLastUpdate or 0
                    bankLast = itemsData.bankLastUpdate or 0
                end
            end
            local charSlots = bagN + bankN
            if charSlots <= 0 and not allowBackfill and (bagLast > 0 or bankLast > 0) then
                charSlots = 1
            end
            personalTotalMatches = personalTotalMatches + charSlots
            if charSlots > 0 then
                hasAnyData = true
            end
        end

        if not hasAnyData and embedItemsWarband and StorageEmbedHasVisibleExpandedSections(expandAllActive, expanded) then
            hasAnyData = true
            if personalTotalMatches <= 0 and StoragePersonalSectionVisible(0, embedItemsWarband, expandAllActive, expanded) then
                personalTotalMatches = 1
            end
            if warbandTotalMatches <= 0 and StorageWarbandSectionVisible(0, embedItemsWarband, expandAllActive, expanded) then
                warbandTotalMatches = 1
            end
        end

        end -- not embedItemsGuild hasAnyData branch

        if not hasAnyData then
            stStop("Stor_scan")
            hideDrawIndicatorWithStagingGate()
            local emptyKey = embedItemsGuild and "items_guild" or (embedItemsWarband and "items_warband" or "storage")
            local height = ShowItemsResultsEmptyState(parent, emptyKey, yOffset)
            SearchStateManager:UpdateResults(searchResultTabKey, 0)
            return height
        end

        self._wnStorageScanPersonalHint = personalTotalMatches
        self._wnStorageScanWarbandHint = warbandTotalMatches
        self._wnStorageScanGuildHint = guildTotalMatches
    end
    
    stStop("Stor_scan")
    
    local characters = trackedCharacters
    local expandAllActive = self.storageExpandAllActive == true
    
    -- Only render Personal Banks section if it has matching items (or user left a subtree expanded).
    stStart("Stor_personal")
    if not embedItemsGuild and StoragePersonalSectionVisible(personalTotalMatches, embedItemsWarband, expandAllActive, expanded) then
        if personalTotalMatches <= 0 then
            personalTotalMatches = 1
        end
        -- Default collapsed; expand-all / search matches override.
        local personalExpanded = (self.storageExpandAllActive == true) or (expanded.personal == true)
        if storageSearchActive and categoriesWithMatches["personal"] then
            personalExpanded = true
        end
        
        local GetCharacterSpecificIcon = ns.UI_GetCharacterSpecificIcon

        local personalWrap = ns.UI.Factory:CreateContainer(parent, math.max(1, stackW), MAIN_SECTION_HEADER_H + 0.1, false)
        personalWrap:ClearAllPoints()
        if personalWrap.SetClipsChildren then
            personalWrap:SetClipsChildren(true)
        end
        ChainSectionFrameBelow(parent, personalWrap, storageStackAnchor, 0, storageStackAnchor and SECTION_SPACING or nil, resultsTopGap)

        local personalBody
        local personalHeader = CreateCollapsibleHeader(
            personalWrap,
            (ns.L and ns.L["PERSONAL_ITEMS"]) or "Personal Items",
            "personal",
            personalExpanded,
            function()
                if type(personalWrap._wnStorageMajorPopulateFn) == "function" then
                    personalWrap._wnStorageMajorPopulateFn()
                end
            end,
            GetCharacterSpecificIcon(),
            true,
            nil,
            nil,
            MajorStorageSectionOpts(personalWrap, function() return personalBody end, MAIN_SECTION_HEADER_H, function(exp)
                expanded.personal = exp
            end, nil, "accent")
        )
        if ns.UI_AnchorSectionHeaderInWrap then
            ns.UI_AnchorSectionHeaderInWrap(personalHeader, personalWrap, stackW)
        else
            personalHeader:SetPoint("TOPLEFT", personalWrap, "TOPLEFT", 0, 0)
            personalHeader:SetWidth(math.max(1, stackW))
        end

        personalBody = ns.UI.Factory:CreateContainer(personalWrap, math.max(1, stackW), 0.1, false)
        personalBody:ClearAllPoints()
        personalBody:SetPoint("TOPLEFT", personalHeader, "BOTTOMLEFT", 0, 0)
        personalBody:SetPoint("TOPRIGHT", personalHeader, "BOTTOMRIGHT", 0, 0)

        local personalInnerTail = nil
        local personalInnerAccum = 0

        local function populatePersonalMajorBody()
            if personalBody._wnStorageMajorBodyBuilt then
                return
            end
        yOffset = yOffset + HEADER_SPACING
        local hasAnyPersonalItems = false

        -- Direct DB access (DB-First pattern) (tracked only)
        local characters = {}
        for i = 1, #trackedCharacters do
            characters[i] = trackedCharacters[i]
        end
        
        -- Sort Characters (account-wide roster sort)
        local CS = ns.CharacterService
        local profile = self.db.profile
        if CS and CS.SortCharacterRosterList then
            CS:SortCharacterRosterList(characters, profile, "regular", {
                tabId = "storage",
                compareNameFn = CompareCharNameLower,
                isLoggedInFn = function(char)
                    local ck = (ns.UI_GetCharKey and ns.UI_GetCharKey(char))
                    return CS:IsLoggedInCharacterRow(self, ck)
                end,
                getCharKeyFn = function(char)
                    return (ns.UI_GetCharKey and ns.UI_GetCharKey(char))
                end,
            })
        else
            table.sort(characters, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then return (a.level or 0) > (b.level or 0) end
                return CompareCharNameLower(a, b)
            end)
        end
        
        local charsToPaint = {}
        for ci = 1, #characters do
            local char = characters[ci]
            local charKey = char._key
            local charCategoryKey = "personal_" .. charKey
            local charCategoryExpanded = expanded.categories[charCategoryKey] == true
            local bagN, bankN, bagLast, bankLast = 0, 0, 0, 0
            if self.GetItemStorageOccupiedSlotTally then
                local charScanBackfill = StorageScanAllowLazyBackfill(embedItemsWarband, expanded, expandAllActive)
                    or charCategoryExpanded
                    or expandAllActive
                bagN, _, bagLast = self:GetItemStorageOccupiedSlotTally(charKey, "bags", charScanBackfill)
                bankN, _, bankLast = self:GetItemStorageOccupiedSlotTally(charKey, "bank", charScanBackfill)
            end
            local hasCharStorage = (bagN + bankN) > 0 or bagLast > 0 or bankLast > 0
                or charCategoryExpanded
                or expandAllActive
            local itemsData = self:GetItemsData(charKey)
            if hasCharStorage and itemsData and (itemsData.bags or itemsData.bank) then
                if not (storageSearchActive and not categoriesWithMatches[charCategoryKey]) then
                    charsToPaint[#charsToPaint + 1] = char
                end
            end
        end

        local function finalizePersonalBodyShell()
            personalBody._wnSectionFullH = math.max(0.1, personalInnerAccum - SECTION_SPACING)
            personalBody:Show()
            personalBody:SetHeight(personalBody._wnSectionFullH)
            personalBody._wnStorageMajorBodyBuilt = true
        end

        local function syncPersonalChromePartial()
            personalWrap:SetHeight(MAIN_SECTION_HEADER_H + personalBody:GetHeight())
            storageStackAnchor = personalWrap
            parent._wnStorageLayoutTail = storageStackAnchor
            WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            if embedItemsWarband and mfPaint then
                local sc = parent:GetParent()
                if sc then
                    local ext = MeasureStorageResultsContentExtent(parent)
                    SyncItemsTabScrollChrome(mfPaint, sc, ext or (parent.GetHeight and parent:GetHeight()) or 1)
                end
            end
        end

        local function buildPersonalCharSection(char)
            local charKey = char._key
            local charCategoryKey = "personal_" .. charKey
            local itemsData = self:GetItemsData(charKey)
            if not itemsData or not (itemsData.bags or itemsData.bank) then
                return false
            end
            local charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
            local charRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
            local classColor = RAID_CLASS_COLORS[char.classFile or char.class] or {r=1, g=1, b=1}
            local charDisplayName = format("|cff%02x%02x%02x%s  -  %s|r",
                classColor.r * 255, classColor.g * 255, classColor.b * 255,
                charName,
                charRealm)
            local isCharExpanded = (self.storageExpandAllActive == true) or (expanded.categories[charCategoryKey] == true)
                    if storageSearchActive and categoriesWithMatches[charCategoryKey] then
                        isCharExpanded = true
                    end
                    
                    -- Get character class icon
                    local charIcon = "Interface\\Icons\\Achievement_Character_Human_Male"  -- Default
                    if char.classFile then
                        charIcon = "Interface\\Icons\\ClassIcon_" .. char.classFile
                    end
                    
                    -- Character block: wrapped header + body (major section); types always built inside body.
                    local charIndent = BASE_INDENT * 1  -- 15px
                    local charStackW = math.max(1, stackW - charIndent)
                    local charWrap = ns.UI.Factory:CreateContainer(personalBody, charStackW, MAIN_SECTION_HEADER_H + 0.1, false)
                    charWrap:ClearAllPoints()
                    if charWrap.SetClipsChildren then
                        charWrap:SetClipsChildren(true)
                    end
                    if personalInnerTail then
                        ChainSectionFrameBelow(personalBody, charWrap, personalInnerTail, charIndent, SECTION_SPACING, nil)
                    else
                        ChainSectionFrameBelow(personalBody, charWrap, nil, charIndent, nil, SECTION_SPACING)
                    end

                    local charBody
                    local charHeader, charBtn = CreateCollapsibleHeader(
                        charWrap,
                        (charDisplayName or charKey),
                        charCategoryKey,
                        isCharExpanded,
                        function()
                            if type(charWrap._wnStorageMajorPopulateFn) == "function" then
                                charWrap._wnStorageMajorPopulateFn()
                            end
                        end,
                        charIcon,
                        false,
                        1,
                        nil,
                        MajorStorageSectionOpts(charWrap, function() return charBody end, MAIN_SECTION_HEADER_H, function(exp)
                            expanded.categories[charCategoryKey] = exp
                        end, {
                            stackParent = personalBody,
                            outerWrap = personalWrap,
                            outerHeaderH = MAIN_SECTION_HEADER_H,
                        })
                    )
                    if ns.UI_AnchorSectionHeaderInWrap then
                        ns.UI_AnchorSectionHeaderInWrap(charHeader, charWrap, charStackW)
                    else
                        charHeader:SetPoint("TOPLEFT", charWrap, "TOPLEFT", 0, 0)
                        charHeader:SetWidth(charStackW)
                    end

                    charBody = ns.UI.Factory:CreateContainer(charWrap, charStackW, 0.1, false)
                    charBody:ClearAllPoints()
                    charBody:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
                    charBody:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)

                    local charBodyAdvance = SECTION_SPACING
                    local function populateCharMajorBody()
                        if charBody._wnStorageMajorBodyBuilt then
                            return
                        end
                    local stackAnchor = nil
                    local gapBelowStack = SECTION_SPACING
                    -- Group character's items by type (NEW: Array-based iteration)
                    local charItems = {}
                    
                    -- Process bags
                    if itemsData.bags then
                        local bags = itemsData.bags
                        for bi = 1, #bags do
                            local item = bags[bi]
                            if item.itemID then
                                local classID = ResolvedStorageClassID(item)
                                local typeName = ResolvedStorageTypeName(item)

                                if not charItems[typeName] then
                                    charItems[typeName] = {}
                                end
                                table.insert(charItems[typeName], item)
                            end
                        end
                    end
                    
                    -- Process bank
                    if itemsData.bank then
                        local bankItems = itemsData.bank
                        for bi = 1, #bankItems do
                            local item = bankItems[bi]
                            if item.itemID then
                                local classID = ResolvedStorageClassID(item)
                                local typeName = ResolvedStorageTypeName(item)

                                if not charItems[typeName] then
                                    charItems[typeName] = {}
                                end
                                table.insert(charItems[typeName], item)
                            end
                        end
                    end
                    
                    -- Sort types alphabetically - only include types with matching items
                    local charSortedTypes = {}
                    for typeName in pairs(charItems) do
                        -- Only include types that have matching items
                        local hasMatchingItems = false
                        if storageSearchActive then
                            local typeItems = charItems[typeName]
                            for ti = 1, #typeItems do
                                local item = typeItems[ti]
                                if ItemMatchesSearch(item) then
                                    hasMatchingItems = true
                                    break
                                end
                            end
                        else
                            hasMatchingItems = #charItems[typeName] > 0
                        end
                        
                        if hasMatchingItems then
                            table.insert(charSortedTypes, typeName)
                        end
                    end
                    table.sort(charSortedTypes)
-- Draw each type category for this character
                    for sti = 1, #charSortedTypes do
                        local typeName = charSortedTypes[sti]
                        local typeKey = "personal_" .. charKey .. "_" .. typeName
                        
                        -- Skip category if search active and no matches
                        if storageSearchActive and not categoriesWithMatches[typeKey] then
                            -- Skip this category
                        else
                            -- Default collapsed; expand-all / search matches override.
                            local isTypeExpanded = (self.storageExpandAllActive == true) or (expanded.categories[typeKey] == true)
                            if storageSearchActive and categoriesWithMatches[typeKey] then
                                isTypeExpanded = true
                            end
                            
                            -- Count items that match search (for display)
                            local matchCount = 0
                            local typeItemsForCount = charItems[typeName]
                            for ti = 1, #typeItemsForCount do
                                local item = typeItemsForCount[ti]
                                if ItemMatchesSearch(item) then
                                    matchCount = matchCount + 1
                                end
                            end
                            
                            -- Calculate display count
                            local displayCount = (storageSearchActive) and matchCount or #charItems[typeName]
                            
                            -- Skip header if it has no items to show
                            if displayCount == 0 then
                                -- Skip this empty header
                            else
                                -- Get icon from first item in category
                                local typeIcon2 = nil
                                if charItems[typeName][1] and charItems[typeName][1].classID then
                                    typeIcon2 = GetTypeIcon(charItems[typeName][1].classID)
                                end
                                
                                -- Type header + rows: synchronous leaf rows (see RenderStorageLeafRows).
                                local typeIndent = BASE_INDENT * 2  -- 30px
                                local typeSectionWrap = ns.UI.Factory:CreateContainer(charBody, math.max(1, charBody:GetWidth() - typeIndent), TYPE_SECTION_HEADER_H + 0.1, false)
                                typeSectionWrap:ClearAllPoints()
                                if typeSectionWrap.SetClipsChildren then
                                    typeSectionWrap:SetClipsChildren(true)
                                end
                                if stackAnchor then
                                    ChainSectionFrameBelow(charBody, typeSectionWrap, stackAnchor, typeIndent, gapBelowStack, nil)
                                else
                                    ChainSectionFrameBelow(charBody, typeSectionWrap, nil, typeIndent, nil, SECTION_SPACING)
                                end
                                gapBelowStack = SECTION_SPACING
                                stackAnchor = typeSectionWrap

                                local leafAncestorCtxPersonal = {
                                    contentBody = charBody,
                                    sectionWrap = charWrap,
                                    sectionHeaderH = MAIN_SECTION_HEADER_H,
                                    stackParent = personalBody,
                                    outerSectionWrap = personalWrap,
                                    outerSectionHeaderH = MAIN_SECTION_HEADER_H,
                                }
                                local function locTextForPersonalStorageItem(item)
                                    if not item then
                                        return ""
                                    end
                                    local locText = ""
                                    if item.actualBagID then
                                        if item.actualBagID == -1 then
                                            locText = (ns.L and ns.L["CHARACTER_BANK"]) or "Bank"
                                        elseif item.actualBagID >= 0 and item.actualBagID <= 5 then
                                            locText = format((ns.L and ns.L["BAG_FORMAT"]) or "Bag %d", item.actualBagID)
                                        else
                                            locText = format((ns.L and ns.L["BANK_BAG_FORMAT"]) or "Bank Bag %d", item.actualBagID - 5)
                                        end
                                    end
                                    return locText
                                end

                                local rowsContainer
                                local typeHeader2, typeBtn2 = CreateCollapsibleHeader(
                                typeSectionWrap,
                                typeName .. " (" .. FormatNumber(displayCount) .. ")",
                                typeKey,
                                isTypeExpanded,
                                function()
                                    WarbandNexus:_ApplyStorageTypeLeafTogglePartial(typeSectionWrap)
                                end,
                                typeIcon2,
                                false,  -- isAtlas = false (item icons are texture paths)
                                0,      -- indent in wrap only; typeSectionWrap already offset under character header
                                nil,
                                LeafTypeSectionVisualOpts(typeSectionWrap, function() return rowsContainer end, typeKey, leafAncestorCtxPersonal)
                            )
                            if ns.UI_AnchorSectionHeaderInWrap then
                                ns.UI_AnchorSectionHeaderInWrap(typeHeader2, typeSectionWrap)
                            else
                                typeHeader2:ClearAllPoints()
                                typeHeader2:SetPoint("TOPLEFT", typeSectionWrap, "TOPLEFT", 0, 0)
                                typeHeader2:SetWidth(typeSectionWrap:GetWidth())
                            end
                            rowsContainer = CreateStorageRowsContainer(typeSectionWrap, typeHeader2, 0, 0)
                            -- Match typeSectionWrap width (charBody full width minus typeIndent); warband path uses the same idea.
                            local rowWidthPersonal = math.max(1, width - charIndent - typeIndent)
                            local typeItemsForRows = charItems[typeName]
                            local rowsYOffset
                            if isTypeExpanded then
                                rowsYOffset = RenderStorageLeafRows(rowsContainer, rowWidthPersonal, typeItemsForRows, locTextForPersonalStorageItem)
                            else
                                rowsYOffset = 0
                            end
                            rowsContainer._wnSectionFullH = rowsYOffset
                            if isTypeExpanded then
                                rowsContainer:Show()
                                rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
                            else
                                rowsContainer:Hide()
                                rowsContainer:SetHeight(0.1)
                            end
                            typeSectionWrap:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
                            typeSectionWrap._wnRowsContainer = rowsContainer
                            typeSectionWrap._wnStorageLeafMeta = {
                                storageKey = typeKey,
                                kind = "personal_type",
                                charKey = charKey,
                                typeName = typeName,
                                rowWidth = rowWidthPersonal,
                                typeHeaderH = TYPE_SECTION_HEADER_H,
                                locTextForItem = locTextForPersonalStorageItem,
                                populateRow = ItemsUI_PopulateStorageRowDirect,
                                searchQueryTabKey = searchResultTabKey,
                            }
                            charBodyAdvance = charBodyAdvance + typeSectionWrap:GetHeight() + SECTION_SPACING
                            end
                        end
                    end

                    local charInnerH = math.max(0.1, charBodyAdvance - SECTION_SPACING)
                    charBody._wnSectionFullH = charInnerH
                    charBody:Show()
                    charBody:SetHeight(charInnerH)
                    charWrap:SetHeight(MAIN_SECTION_HEADER_H + charBody:GetHeight())
                    charBody._wnStorageMajorBodyBuilt = true
                    end  -- populateCharMajorBody

                    charWrap._wnStorageMajorPopulateFn = populateCharMajorBody
                    if isCharExpanded then
                        populateCharMajorBody()
                    else
                        charBody._wnSectionFullH = 0.1
                        charBody:Hide()
                        charBody:SetHeight(0.1)
                        charWrap:SetHeight(MAIN_SECTION_HEADER_H + 0.1)
                    end
            personalInnerAccum = personalInnerAccum + charWrap:GetHeight() + SECTION_SPACING
            personalInnerTail = charWrap
            hasAnyPersonalItems = true
            return true
        end

        local charSyncMax = embedItemsWarband and STORAGE_CHAR_SYNC_MAX_EMBED or STORAGE_CHAR_SYNC_MAX
        local charChunkSize = embedItemsWarband and STORAGE_CHAR_CHUNK_EMBED or STORAGE_CHAR_CHUNK
        local useCharPump = #charsToPaint > charSyncMax and C_Timer and C_Timer.After

        if not useCharPump then
            for pci = 1, #charsToPaint do
                buildPersonalCharSection(charsToPaint[pci])
            end
            finalizePersonalBodyShell()
        else
            if loadIndicator then loadIndicator:Show() end
            local stPatchChars = mfPaint and mfPaint._wnStorageLeafStage
            if stPatchChars and stPatchChars.gen == leafPaintGen then
                stPatchChars.pending = (stPatchChars.pending or 0) + 1
            end
            local charCreditConsumed = false
            local function consumeCharStagingCredit()
                if charCreditConsumed then return end
                charCreditConsumed = true
                local st = mfPaint and mfPaint._wnStorageLeafStage
                if st and st.gen == leafPaintGen then
                    st.pending = math.max(0, (st.pending or 1) - 1)
                    if st.pending <= 0 then
                        hideWarbandBanner()
                    end
                end
            end

            local charPaintIdx = 1
            local function pumpPersonalChars()
                if not StorageChunkedPaintStillValid(mfPaint, leafPaintGen) then
                    consumeCharStagingCredit()
                    return
                end
                if InCombatLockdown and InCombatLockdown() then
                    C_Timer.After(0, pumpPersonalChars)
                    return
                end
                local limit = math.min(charPaintIdx + charChunkSize - 1, #charsToPaint)
                for pci = charPaintIdx, limit do
                    buildPersonalCharSection(charsToPaint[pci])
                end
                charPaintIdx = limit + 1
                syncPersonalChromePartial()

                if charPaintIdx <= #charsToPaint then
                    C_Timer.After(0, pumpPersonalChars)
                else
                    finalizePersonalBodyShell()
                    consumeCharStagingCredit()
                    hideDrawIndicatorWithStagingGate()
                end
            end

            personalInnerAccum = math.max(
                personalInnerAccum,
                #charsToPaint * (MAIN_SECTION_HEADER_H + SECTION_SPACING + 20)
            )
            personalBody:SetHeight(math.max(0.1, personalInnerAccum - SECTION_SPACING))
            syncPersonalChromePartial()
            pumpPersonalChars()
        end
        end  -- populatePersonalMajorBody

        personalWrap._wnStorageMajorPopulateFn = populatePersonalMajorBody
        if personalExpanded then
            populatePersonalMajorBody()
        else
            personalBody._wnSectionFullH = 0.1
            personalBody:Hide()
            personalBody:SetHeight(0.1)
        end
        personalWrap:SetHeight(MAIN_SECTION_HEADER_H + personalBody:GetHeight())
        storageStackAnchor = personalWrap
    end
    stStop("Stor_personal")
    
    stStart("Stor_warband")
    -- Warband Bank: default collapsed. Skip per-item class/type grouping when collapsed + no search (large banks).
    local warbandExpanded = (self.storageExpandAllActive == true) or (expanded.warband == true)
    if storageSearchActive and categoriesWithMatches["warband"] then
        warbandExpanded = true
    end
    local scanWarbandSlotHint = self._wnStorageScanWarbandHint or warbandTotalMatches

    local warbandItems = {}
    local needWarbandPayload = warbandExpanded or (storageSearchActive and categoriesWithMatches["warband"])
        or StorageTreeHasExpandedPrefixCategory(expanded, "warband_")
    local warbandData
    local wbItems2

    if needWarbandPayload then
        warbandData = self:GetWarbandBankData()
        wbItems2 = warbandData and warbandData.items
    elseif self.GetWarbandBankOccupiedSlotTally then
        local wbBackfill = StorageScanAllowLazyBackfill(embedItemsWarband, expanded, expandAllActive)
        local wbSlots, _, wbLast = self:GetWarbandBankOccupiedSlotTally(wbBackfill)
        warbandTotalMatches = math.max(wbSlots, (wbLast > 0 and 1 or 0))
    else
        warbandData = self:GetWarbandBankData()
        wbItems2 = warbandData and warbandData.items
    end

    if wbItems2 then
        -- Build type index only when the warband body is expanded or search needs grouped hits (WN-PERF).
        local needWarbandTypeIndex = warbandExpanded
            or (storageSearchActive and categoriesWithMatches["warband"])
            or StorageTreeHasExpandedPrefixCategory(expanded, "warband_")
        if storageSearchActive and not categoriesWithMatches["warband"] and not warbandExpanded then
            -- No warband search hits and body collapsed: avoid scanning thousands of slots for grouping.
        elseif needWarbandTypeIndex then
            for ii = 1, #wbItems2 do
                local item = wbItems2[ii]
                if item.itemID then
                    if storageSearchActive and not ItemMatchesSearch(item) then
                        -- Index only matches when a filter is active.
                    else
                        local classID = ResolvedStorageClassID(item)
                        local typeName = ResolvedStorageTypeName(item)
                        if not warbandItems[typeName] then
                            warbandItems[typeName] = {}
                        end
                        table.insert(warbandItems[typeName], item)
                    end
                end
            end
            warbandTotalMatches = 0
            for _tn, items in pairs(warbandItems) do
                warbandTotalMatches = warbandTotalMatches + #items
            end
        else
            -- Collapsed, no search: item count only (no GetItemClassID / type tables).
            local nwb = 0
            for jj = 1, #wbItems2 do
                if wbItems2[jj] and wbItems2[jj].itemID then
                    nwb = nwb + 1
                end
            end
            warbandTotalMatches = nwb
        end
    end

    if warbandTotalMatches < scanWarbandSlotHint then
        warbandTotalMatches = scanWarbandSlotHint
    end
    if warbandTotalMatches <= 0 and StorageWarbandSectionVisible(0, embedItemsWarband, expandAllActive, expanded) then
        warbandTotalMatches = math.max(scanWarbandSlotHint, 1)
    end

    -- Only render Warband Bank section if it has matching items (or user left a subtree expanded).
    if not embedItemsGuild and StorageWarbandSectionVisible(warbandTotalMatches, embedItemsWarband, expandAllActive, expanded) then
        if warbandTotalMatches <= 0 then
            warbandTotalMatches = 1
        end
        local warbandWrap = ns.UI.Factory:CreateContainer(parent, math.max(1, stackW), MAIN_SECTION_HEADER_H + 0.1, false)
        warbandWrap:ClearAllPoints()
        if warbandWrap.SetClipsChildren then
            warbandWrap:SetClipsChildren(true)
        end
        ChainSectionFrameBelow(parent, warbandWrap, storageStackAnchor, 0, storageStackAnchor and SECTION_SPACING or nil, resultsTopGap)

        local warbandBody
        local warbandHeader, expandBtn, warbandIcon = CreateCollapsibleHeader(
            warbandWrap,
            (ns.L and ns.L["STORAGE_WARBAND_BANK"]) or "Warband Bank",
            "warband",
            warbandExpanded,
            function()
                if type(warbandWrap._wnStorageMajorPopulateFn) == "function" then
                    warbandWrap._wnStorageMajorPopulateFn()
                end
            end,
            "dummy",
            false,
            nil,
            nil,
            MajorStorageSectionOpts(warbandWrap, function() return warbandBody end, MAIN_SECTION_HEADER_H, function(exp)
                expanded.warband = exp
            end, nil, "accent")
        )
        if ns.UI_AnchorSectionHeaderInWrap then
            ns.UI_AnchorSectionHeaderInWrap(warbandHeader, warbandWrap, stackW)
        else
            warbandHeader:SetPoint("TOPLEFT", warbandWrap, "TOPLEFT", 0, 0)
            warbandHeader:SetWidth(math.max(1, stackW))
        end

        warbandBody = ns.UI.Factory:CreateContainer(warbandWrap, math.max(1, stackW), 0.1, false)
        warbandBody:ClearAllPoints()
        warbandBody:SetPoint("TOPLEFT", warbandHeader, "BOTTOMLEFT", 0, 0)
        warbandBody:SetPoint("TOPRIGHT", warbandHeader, "BOTTOMRIGHT", 0, 0)

        -- Replace with Warband atlas icon (27x36 for proper aspect ratio)
        if warbandIcon then
            warbandIcon:SetTexture(nil)  -- Clear dummy texture
            warbandIcon:SetAtlas("warbands-icon")
            warbandIcon:SetSize(27, 36)  -- Native atlas proportions (23:31)
        end

        local warbandBodyAdvance = SECTION_SPACING

        local function ensureWarbandItemsIndexed()
            if next(warbandItems) then
                return true
            end
            local data = self:GetWarbandBankData()
            local items = data and data.items
            if not items then
                return false
            end
            for ii = 1, #items do
                local item = items[ii]
                if item.itemID then
                    if not storageSearchActive or ItemMatchesSearch(item) then
                        local classID = ResolvedStorageClassID(item)
                        local typeName = ResolvedStorageTypeName(item)
                        if not warbandItems[typeName] then
                            warbandItems[typeName] = {}
                        end
                        tinsert(warbandItems[typeName], item)
                    end
                end
            end
            return next(warbandItems) ~= nil
        end

        local function populateWarbandMajorBody()
            if warbandBody._wnStorageMajorBodyBuilt then
                return
            end
            if not ensureWarbandItemsIndexed() then
                warbandBody._wnSectionFullH = 0.1
                return
            end
            warbandBodyAdvance = SECTION_SPACING
        local stackAnchor = nil
        local gapBelowStack = SECTION_SPACING
        -- Sort types alphabetically
            local sortedTypes = {}
            for typeName in pairs(warbandItems) do
                -- Only include types that have matching items
                local hasMatchingItems = false
                if storageSearchActive then
                    local wbTypeItems = warbandItems[typeName]
                    for wi = 1, #wbTypeItems do
                        local item = wbTypeItems[wi]
                        if ItemMatchesSearch(item) then
                            hasMatchingItems = true
                            break
                        end
                    end
                else
                    hasMatchingItems = #warbandItems[typeName] > 0
                end
                
                if hasMatchingItems then
                    table.insert(sortedTypes, typeName)
                end
            end
            table.sort(sortedTypes)

        local function finalizeWarbandBodyShell()
            warbandBody._wnSectionFullH = math.max(0.1, warbandBodyAdvance - SECTION_SPACING)
            warbandBody:Show()
            warbandBody:SetHeight(warbandBody._wnSectionFullH)
            warbandWrap:SetHeight(MAIN_SECTION_HEADER_H + warbandBody:GetHeight())
            storageStackAnchor = warbandWrap
            parent._wnStorageLayoutTail = storageStackAnchor
        end

        local function syncWarbandChromePartial()
            WarbandNexus:SyncStorageResultsLayoutFromTail(parent)
            if embedItemsWarband and mfPaint then
                local sc = parent:GetParent()
                if sc then
                    local ext = MeasureStorageResultsContentExtent(parent)
                    SyncItemsTabScrollChrome(mfPaint, sc, ext or (parent.GetHeight and parent:GetHeight()) or 1)
                end
            end
        end

        local function buildWarbandTypeSection(sti)
            local typeName = sortedTypes[sti]
            local categoryKey = "warband_" .. typeName
            -- Items > Warband embed: default type groups to expanded when state is unset (nil), so rows
            -- appear after the per-subtab reset in UI.lua; explicit false preserves user collapse.
            if embedItemsWarband and not storageSearchActive and expanded.categories[categoryKey] == nil then
                expanded.categories[categoryKey] = true
            end

            -- Skip category if search active and no matches
            if storageSearchActive and not categoriesWithMatches[categoryKey] then
                return
            end

            -- Default collapsed; expand-all / search matches override.
            local isTypeExpanded = (self.storageExpandAllActive == true) or (expanded.categories[categoryKey] == true)
            if storageSearchActive and categoriesWithMatches[categoryKey] then
                isTypeExpanded = true
            end
            
            -- Count items that match search (for display)
            local matchCount = 0
            local wbTypeItems2 = warbandItems[typeName]
            for wi = 1, #wbTypeItems2 do
                local item = wbTypeItems2[wi]
                if ItemMatchesSearch(item) then
                    matchCount = matchCount + 1
                end
            end
            
            -- Calculate display count
            local displayCount = (storageSearchActive) and matchCount or #warbandItems[typeName]
            
            -- Skip header if it has no items to show
            if displayCount == 0 then
                return
            end

            -- Get icon from first item in category
            local typeIcon = nil
            if warbandItems[typeName][1] and warbandItems[typeName][1].classID then
                typeIcon = GetTypeIcon(warbandItems[typeName][1].classID)
            end
            
            local typeIndentWB = BASE_INDENT
            local typeSectionWrapWB = ns.UI.Factory:CreateContainer(warbandBody, math.max(1, warbandBody:GetWidth() - typeIndentWB), TYPE_SECTION_HEADER_H + 0.1, false)
            typeSectionWrapWB:ClearAllPoints()
            if typeSectionWrapWB.SetClipsChildren then
                typeSectionWrapWB:SetClipsChildren(true)
            end
            if stackAnchor then
                ChainSectionFrameBelow(warbandBody, typeSectionWrapWB, stackAnchor, typeIndentWB, gapBelowStack, nil)
            else
                ChainSectionFrameBelow(warbandBody, typeSectionWrapWB, nil, typeIndentWB, nil, SECTION_SPACING)
            end
            gapBelowStack = SECTION_SPACING
            stackAnchor = typeSectionWrapWB

            local leafAncestorCtxWarband = {
                contentBody = warbandBody,
                sectionWrap = warbandWrap,
                sectionHeaderH = MAIN_SECTION_HEADER_H,
            }
            local function locTextForWarbandStorageItem(item)
                if not item then
                    return ""
                end
                return item.tabIndex and format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex) or ""
            end

            local rowsContainer
            local typeHeader, typeBtn = CreateCollapsibleHeader(
                typeSectionWrapWB,
                typeName .. " (" .. FormatNumber(displayCount) .. ")",
                categoryKey,
                isTypeExpanded,
                function()
                    WarbandNexus:_ApplyStorageTypeLeafTogglePartial(typeSectionWrapWB)
                end,
                typeIcon,
                false,
                nil,
                nil,
                LeafTypeSectionVisualOpts(typeSectionWrapWB, function() return rowsContainer end, categoryKey, leafAncestorCtxWarband)
            )
            if ns.UI_AnchorSectionHeaderInWrap then
                ns.UI_AnchorSectionHeaderInWrap(typeHeader, typeSectionWrapWB)
            else
                typeHeader:ClearAllPoints()
                typeHeader:SetPoint("TOPLEFT", typeSectionWrapWB, "TOPLEFT", 0, 0)
                typeHeader:SetWidth(typeSectionWrapWB:GetWidth())
            end
            rowsContainer = CreateStorageRowsContainer(typeSectionWrapWB, typeHeader, 0, 0)
            local rowWidthWB = width - BASE_INDENT
            local wbTypeItems3 = warbandItems[typeName]
            local rowsYOffset
            if isTypeExpanded then
                rowsYOffset = RenderStorageLeafRows(rowsContainer, rowWidthWB, wbTypeItems3, locTextForWarbandStorageItem)
            else
                rowsYOffset = 0
            end
            rowsContainer._wnSectionFullH = rowsYOffset
            if isTypeExpanded then
                rowsContainer:Show()
                rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
            else
                rowsContainer:Hide()
                rowsContainer:SetHeight(0.1)
            end
            typeSectionWrapWB:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
            typeSectionWrapWB._wnRowsContainer = rowsContainer
            typeSectionWrapWB._wnStorageLeafMeta = {
                storageKey = categoryKey,
                kind = "warband_type",
                typeName = typeName,
                rowWidth = rowWidthWB,
                typeHeaderH = TYPE_SECTION_HEADER_H,
                locTextForItem = locTextForWarbandStorageItem,
                populateRow = ItemsUI_PopulateStorageRowDirect,
                searchQueryTabKey = searchResultTabKey,
            }
            warbandBodyAdvance = warbandBodyAdvance + typeSectionWrapWB:GetHeight() + SECTION_SPACING
        end

        local typeCount = #sortedTypes
        local typeSyncMax = embedItemsWarband and STORAGE_WARBAND_TYPE_SYNC_MAX_EMBED or STORAGE_WARBAND_TYPE_SYNC_MAX
        local typeChunkSize = embedItemsWarband and STORAGE_WARBAND_TYPE_CHUNK_EMBED or STORAGE_WARBAND_TYPE_CHUNK
        local useTypePump = typeCount > typeSyncMax and C_Timer and C_Timer.After

        if not useTypePump then
            for sti = 1, typeCount do
                buildWarbandTypeSection(sti)
            end
            finalizeWarbandBodyShell()
        else
            if loadIndicator then loadIndicator:Show() end
            local stPatchTypes = mfPaint and mfPaint._wnStorageLeafStage
            if stPatchTypes and stPatchTypes.gen == leafPaintGen then
                stPatchTypes.pending = (stPatchTypes.pending or 0) + 1
            end
            local typeCreditConsumed = false
            local function consumeTypeStagingCredit()
                if typeCreditConsumed then return end
                typeCreditConsumed = true
                local st = mfPaint and mfPaint._wnStorageLeafStage
                if st and st.gen == leafPaintGen then
                    st.pending = math.max(0, (st.pending or 1) - 1)
                    if st.pending <= 0 then
                        hideWarbandBanner()
                    end
                end
            end

            local typeIdx = 1
            local function pumpWarbandTypes()
                if not StorageChunkedPaintStillValid(mfPaint, leafPaintGen) then
                    consumeTypeStagingCredit()
                    return
                end
                if InCombatLockdown and InCombatLockdown() then
                    C_Timer.After(0, pumpWarbandTypes)
                    return
                end
                local limit = math.min(typeIdx + typeChunkSize - 1, typeCount)
                for sti = typeIdx, limit do
                    buildWarbandTypeSection(sti)
                end
                typeIdx = limit + 1
                finalizeWarbandBodyShell()
                syncWarbandChromePartial()

                if typeIdx <= typeCount then
                    C_Timer.After(0, pumpWarbandTypes)
                else
                    consumeTypeStagingCredit()
                    hideDrawIndicatorWithStagingGate()
                end
            end
            finalizeWarbandBodyShell()
            pumpWarbandTypes()
        end
            warbandBody._wnStorageMajorBodyBuilt = true
        end  -- populateWarbandMajorBody

        warbandWrap._wnStorageMajorPopulateFn = populateWarbandMajorBody
        if warbandExpanded then
            populateWarbandMajorBody()
        else
            warbandBody._wnSectionFullH = 0.1
            warbandBody:Hide()
            warbandBody:SetHeight(0.1)
        end
        warbandWrap:SetHeight(MAIN_SECTION_HEADER_H + warbandBody:GetHeight())
        storageStackAnchor = warbandWrap
    end
    stStop("Stor_warband")
    
    stStart("Stor_guild")
    if embedItemsGuild then
        local guildEntries = self:GetGuildBankSortedEntries() or {}
        for gei = 1, #guildEntries do
            local guildName = guildEntries[gei].name
            local guildData = guildEntries[gei].data
            local guildCategoryKey = "guild_" .. guildName
            local guildItemSlots = guildData.usedSlots or 0
            if guildItemSlots <= 0 and self.CountGuildBankOccupiedSlots then
                guildItemSlots = self:CountGuildBankOccupiedSlots(guildData)
            end

            if storageSearchActive and not categoriesWithMatches[guildCategoryKey] then
                -- skip guild with no search hits
            elseif guildItemSlots <= 0 and not storageSearchActive
                and not expandAllActive
                and not expanded.categories[guildCategoryKey]
                and not StorageTreeHasExpandedPrefixCategory(expanded, guildCategoryKey .. "_") then
                -- skip empty guild unless user left subtree expanded
            else
                local guildExpanded = (self.storageExpandAllActive == true) or (expanded.categories[guildCategoryKey] == true)
                if embedItemsGuild and not storageSearchActive and expanded.categories[guildCategoryKey] == nil then
                    guildExpanded = true
                end
                if storageSearchActive and categoriesWithMatches[guildCategoryKey] then
                    guildExpanded = true
                end

                local guildWrap = ns.UI.Factory:CreateContainer(parent, math.max(1, stackW), MAIN_SECTION_HEADER_H + 0.1, false)
                guildWrap:ClearAllPoints()
                if guildWrap.SetClipsChildren then
                    guildWrap:SetClipsChildren(true)
                end
                ChainSectionFrameBelow(parent, guildWrap, storageStackAnchor, 0, storageStackAnchor and SECTION_SPACING or nil, gei == 1 and resultsTopGap or nil)

                local guildBody
                local guildHeader, _, guildIcon = CreateCollapsibleHeader(
                    guildWrap,
                    guildName .. " (" .. FormatNumber(guildItemSlots) .. ")",
                    guildCategoryKey,
                    guildExpanded,
                    function()
                        if type(guildWrap._wnStorageMajorPopulateFn) == "function" then
                            guildWrap._wnStorageMajorPopulateFn()
                        end
                    end,
                    "Interface\\Icons\\INV_Shirt_GuildTabard_01",
                    false,
                    nil,
                    nil,
                    MajorStorageSectionOpts(guildWrap, function() return guildBody end, MAIN_SECTION_HEADER_H, function(exp)
                        expanded.categories[guildCategoryKey] = exp
                    end, nil, "accent")
                )
                if guildIcon then
                    guildIcon:SetTexture("Interface\\Icons\\INV_Shirt_GuildTabard_01")
                    guildIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                    guildIcon:SetSize(28, 28)
                end
                if ns.UI_AnchorSectionHeaderInWrap then
                    ns.UI_AnchorSectionHeaderInWrap(guildHeader, guildWrap, stackW)
                else
                    guildHeader:SetPoint("TOPLEFT", guildWrap, "TOPLEFT", 0, 0)
                    guildHeader:SetWidth(math.max(1, stackW))
                end

                guildBody = ns.UI.Factory:CreateContainer(guildWrap, math.max(1, stackW), 0.1, false)
                guildBody:ClearAllPoints()
                guildBody:SetPoint("TOPLEFT", guildHeader, "BOTTOMLEFT", 0, 0)
                guildBody:SetPoint("TOPRIGHT", guildHeader, "BOTTOMRIGHT", 0, 0)

                local guildItemsByType = {}
                local function ensureGuildItemsIndexed()
                    if next(guildItemsByType) then
                        return true
                    end
                    for tabIndex, tabData in pairs(guildData.tabs or {}) do
                        for slotID, item in pairs(tabData.items or {}) do
                            if item and item.itemID then
                                if not storageSearchActive or ItemMatchesSearch(item) then
                                    local classID = ResolvedStorageClassID(item)
                                    local typeName = ResolvedStorageTypeName(item)
                                    item.tabIndex = tabIndex
                                    item.slotID = slotID
                                    item.tabName = tabData.name
                                    item.guildName = guildName
                                    item.source = "guild"
                                    if not guildItemsByType[typeName] then
                                        guildItemsByType[typeName] = {}
                                    end
                                    tinsert(guildItemsByType[typeName], item)
                                end
                            end
                        end
                    end
                    return next(guildItemsByType) ~= nil
                end

                local function populateGuildMajorBody()
                    if guildBody._wnStorageMajorBodyBuilt then
                        return
                    end
                    if not ensureGuildItemsIndexed() then
                        if guildExpanded then
                            local hintH = 28
                            local hint = FontManager:CreateFontString(guildBody, "body", "OVERLAY")
                            hint:SetPoint("TOPLEFT", guildBody, "TOPLEFT", BASE_INDENT, -8)
                            hint:SetPoint("TOPRIGHT", guildBody, "TOPRIGHT", -BASE_INDENT, -8)
                            hint:SetJustifyH("LEFT")
                            hint:SetWordWrap(true)
                            hint:SetText((ns.L and ns.L["EMPTY_GUILD_BANK_DESC"]) or "Open your Guild Bank to scan items.")
                            ns.UI_SetTextColorRole(hint, "Muted")
                            guildBody._wnSectionFullH = hintH
                            guildBody:Show()
                            guildBody:SetHeight(hintH)
                            guildWrap:SetHeight(MAIN_SECTION_HEADER_H + hintH)
                            storageStackAnchor = guildWrap
                            parent._wnStorageLayoutTail = storageStackAnchor
                        else
                            guildBody._wnSectionFullH = 0.1
                        end
                        guildBody._wnStorageMajorBodyBuilt = true
                        return
                    end

                    local guildBodyAdvance = SECTION_SPACING
                    local stackAnchor = nil
                    local gapBelowStack = SECTION_SPACING

                    local sortedTypes = {}
                    for typeName in pairs(guildItemsByType) do
                        local typeKey = guildCategoryKey .. "_" .. typeName
                        local hasMatchingItems = false
                        if storageSearchActive then
                            if categoriesWithMatches[typeKey] then
                                hasMatchingItems = true
                            end
                        else
                            hasMatchingItems = #guildItemsByType[typeName] > 0
                        end
                        if hasMatchingItems then
                            tinsert(sortedTypes, typeName)
                        end
                    end
                    table.sort(sortedTypes)

                    local function finalizeGuildBodyShell()
                        guildBody._wnSectionFullH = math.max(0.1, guildBodyAdvance - SECTION_SPACING)
                        guildBody:Show()
                        guildBody:SetHeight(guildBody._wnSectionFullH)
                        guildWrap:SetHeight(MAIN_SECTION_HEADER_H + guildBody:GetHeight())
                        storageStackAnchor = guildWrap
                        parent._wnStorageLayoutTail = storageStackAnchor
                    end

                    local function locTextForGuildStorageItem(item)
                        if not item then return "" end
                        if item.tabName and not (issecretvalue and issecretvalue(item.tabName)) then
                            return item.tabName
                        end
                        if item.tabIndex then
                            return format((ns.L and ns.L["TAB_FORMAT"]) or "Tab %d", item.tabIndex)
                        end
                        return ""
                    end

                    for sti = 1, #sortedTypes do
                        local typeName = sortedTypes[sti]
                        local typeKey = guildCategoryKey .. "_" .. typeName
                        if embedItemsGuild and not storageSearchActive and expanded.categories[typeKey] == nil then
                            expanded.categories[typeKey] = true
                        end

                        local isTypeExpanded = (self.storageExpandAllActive == true) or (expanded.categories[typeKey] == true)
                        if storageSearchActive and categoriesWithMatches[typeKey] then
                            isTypeExpanded = true
                        end

                        local matchCount = 0
                        local typeItems = guildItemsByType[typeName]
                        for ti = 1, #typeItems do
                            if ItemMatchesSearch(typeItems[ti]) then
                                matchCount = matchCount + 1
                            end
                        end
                        local displayCount = storageSearchActive and matchCount or #typeItems
                        if displayCount == 0 then
                            -- skip
                        else
                            local typeIcon = nil
                            if typeItems[1] and typeItems[1].classID then
                                typeIcon = GetTypeIcon(typeItems[1].classID)
                            end

                            local typeIndent = BASE_INDENT
                            local typeSectionWrap = ns.UI.Factory:CreateContainer(guildBody, math.max(1, guildBody:GetWidth() - typeIndent), TYPE_SECTION_HEADER_H + 0.1, false)
                            typeSectionWrap:ClearAllPoints()
                            if typeSectionWrap.SetClipsChildren then
                                typeSectionWrap:SetClipsChildren(true)
                            end
                            if stackAnchor then
                                ChainSectionFrameBelow(guildBody, typeSectionWrap, stackAnchor, typeIndent, gapBelowStack, nil)
                            else
                                ChainSectionFrameBelow(guildBody, typeSectionWrap, nil, typeIndent, nil, SECTION_SPACING)
                            end
                            gapBelowStack = SECTION_SPACING
                            stackAnchor = typeSectionWrap

                            local leafAncestorCtxGuild = {
                                contentBody = guildBody,
                                sectionWrap = guildWrap,
                                sectionHeaderH = MAIN_SECTION_HEADER_H,
                            }

                            local rowsContainer
                            local typeHeader = CreateCollapsibleHeader(
                                typeSectionWrap,
                                typeName .. " (" .. FormatNumber(displayCount) .. ")",
                                typeKey,
                                isTypeExpanded,
                                function()
                                    WarbandNexus:_ApplyStorageTypeLeafTogglePartial(typeSectionWrap)
                                end,
                                typeIcon,
                                false,
                                nil,
                                nil,
                                LeafTypeSectionVisualOpts(typeSectionWrap, function() return rowsContainer end, typeKey, leafAncestorCtxGuild)
                            )
                            if ns.UI_AnchorSectionHeaderInWrap then
                                ns.UI_AnchorSectionHeaderInWrap(typeHeader, typeSectionWrap)
                            else
                                typeHeader:ClearAllPoints()
                                typeHeader:SetPoint("TOPLEFT", typeSectionWrap, "TOPLEFT", 0, 0)
                                typeHeader:SetWidth(typeSectionWrap:GetWidth())
                            end
                            rowsContainer = CreateStorageRowsContainer(typeSectionWrap, typeHeader, 0, 0)
                            local rowWidthGuild = width - BASE_INDENT
                            local rowsYOffset = 0
                            if isTypeExpanded then
                                rowsYOffset = RenderStorageLeafRows(rowsContainer, rowWidthGuild, typeItems, locTextForGuildStorageItem)
                            end
                            rowsContainer._wnSectionFullH = rowsYOffset
                            if isTypeExpanded then
                                rowsContainer:Show()
                                rowsContainer:SetHeight(math.max(0.1, rowsYOffset))
                            else
                                rowsContainer:Hide()
                                rowsContainer:SetHeight(0.1)
                            end
                            typeSectionWrap:SetHeight(TYPE_SECTION_HEADER_H + math.max(0.1, rowsContainer:GetHeight() or 0.1))
                            typeSectionWrap._wnRowsContainer = rowsContainer
                            typeSectionWrap._wnStorageLeafMeta = {
                                storageKey = typeKey,
                                kind = "guild_type",
                                guildName = guildName,
                                typeName = typeName,
                                rowWidth = rowWidthGuild,
                                typeHeaderH = TYPE_SECTION_HEADER_H,
                                locTextForItem = locTextForGuildStorageItem,
                                populateRow = ItemsUI_PopulateStorageRowDirect,
                                searchQueryTabKey = searchResultTabKey,
                            }
                            guildBodyAdvance = guildBodyAdvance + typeSectionWrap:GetHeight() + SECTION_SPACING
                        end
                    end

                    finalizeGuildBodyShell()
                    guildBody._wnStorageMajorBodyBuilt = true
                end

                guildWrap._wnStorageMajorPopulateFn = populateGuildMajorBody
                if guildExpanded then
                    populateGuildMajorBody()
                else
                    guildBody._wnSectionFullH = 0.1
                    guildBody:Hide()
                    guildBody:SetHeight(0.1)
                end
                guildWrap:SetHeight(MAIN_SECTION_HEADER_H + guildBody:GetHeight())
                storageStackAnchor = guildWrap
            end
        end
    end
    stStop("Stor_guild")

    local stageNow = mfPaint and mfPaint._wnStorageLeafStage
    local hasAsyncLeaves = stageNow and stageNow.gen == leafPaintGen and (stageNow.pending or 0) > 0
    if (parent._wnStorageRowRefs and #parent._wnStorageRowRefs > 0) or hasAsyncLeaves then
        parent._wnStorageApplyRowVisual = function(row, item, rowIdx, rowWidth, locText)
            ItemsUI_PopulateStorageRowDirect(row, item, rowIdx, rowWidth, locText)
        end
    else
        parent._wnStorageApplyRowVisual = nil
    end
    local pad = GetLayout().minBottomSpacing or 0
    parent._wnStorageLayoutTail = storageStackAnchor
    local extent = MeasureStorageResultsContentExtent(parent)
    if extent then
        hideDrawIndicatorWithStagingGate()
        return math.max(1, extent + pad, yOffset + pad)
    end
    if storageStackAnchor and parent.GetTop and storageStackAnchor.GetBottom then
        local pTop = parent:GetTop()
        local bot = storageStackAnchor:GetBottom()
        if pTop and bot then
            local measured = pTop - bot + pad
            hideDrawIndicatorWithStagingGate()
            return math.max(1, measured, yOffset + pad)
        end
    end
    hideDrawIndicatorWithStagingGate()
    return yOffset + pad
end -- DrawStorageResults

-- Light-weight Items sub-tab switch: updates gold/stats + results only (avoids full PopulateContent / header rebuild).
local function ApplyItemsSubTabGoldDisplay(goldDisplay, currentItemsSubTab)
    if not goldDisplay then return end
    local FormatMoney = ns.UI_FormatMoney
    if currentItemsSubTab == "personal" then
        goldDisplay:Hide()
        return
    end
    goldDisplay:Show()
    if currentItemsSubTab == "warband" then
        local warbandGold = ns.Utilities:GetWarbandBankMoney() or 0
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(warbandGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(warbandGold))
        end
    elseif currentItemsSubTab == "guild" then
        local guildGold = nil
        if IsInGuild() then
            local guildName = GetGuildInfo("player")
            if guildName and issecretvalue and issecretvalue(guildName) then guildName = nil end
            if guildName and WarbandNexus.db.global.guildBank and WarbandNexus.db.global.guildBank[guildName] then
                guildGold = WarbandNexus.db.global.guildBank[guildName].cachedGold
            end
        elseif WarbandNexus.GetGuildBankCacheAggregateStats then
            local agg = WarbandNexus:GetGuildBankCacheAggregateStats()
            guildGold = agg and agg.cachedGold
        end
        if guildGold then
            if FormatMoney then
                goldDisplay:SetText(FormatMoney(guildGold, 14))
            else
                goldDisplay:SetText(WarbandNexus:API_FormatMoney(guildGold))
            end
        elseif CanViewGuildBankSubTab() then
            goldDisplay:SetText(ItemsDimMarkup(((ns.L and ns.L["NO_SCAN"]) or "Not scanned")))
        else
            goldDisplay:SetText(ItemsDimMarkup(((ns.L and ns.L["NOT_IN_GUILD"]) or "Not in guild")))
        end
    elseif currentItemsSubTab == "inventory" then
        local charGold = ns.Utilities:GetLiveCharacterMoneyCopper(0)
        if FormatMoney then
            goldDisplay:SetText(FormatMoney(charGold, 14))
        else
            goldDisplay:SetText(WarbandNexus:API_FormatMoney(charGold))
        end
    elseif goldDisplay:IsShown() then
        goldDisplay:SetText("")
    end
end

local function ApplyItemsSubTabStatsText(addon, statsText, currentItemsSubTab)
    if not statsText then return end
    local itemCount, usedSlots, totalSlots, lastScan, colorHex =
        ResolveItemsSubTabStatsMetrics(addon, currentItemsSubTab)
    statsText:SetText(FormatItemsBankStatsLine(colorHex, itemCount, usedSlots, totalSlots, lastScan))
end

function WarbandNexus:RefreshItemsSubTabBodyOnly(fromSub, toSub)
    local mf = self.UI and self.UI.mainFrame
    if not mf or not mf:IsShown() or mf.currentTab ~= "items" then return false end
    if not ns.Utilities:IsModuleEnabled("items") then return false end
    local sc = mf.scrollChild
    if not sc or not sc._itemsSubTabBar or not sc._itemsStatsText then return false end
    local sub = toSub or (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "inventory"
    fromSub = fromSub or sub

    -- Cancel in-flight storage leaf / warband-type chunk pumps before sub-tab chrome updates.
    if self.AbortStorageChunkedPaint then
        self:AbortStorageChunkedPaint()
    end

    local perfOn = ns.IsTabPerfMonitorEnabled and ns.IsTabPerfMonitorEnabled()
    local wallStart = perfOn and GetTime() or nil
    if perfOn then
        debugprofilestart()
    end

    sc._itemsSubTabBar:SetActiveTab(sub)
    if sc._itemsSubTabBar.RefreshGuildLock then
        sc._itemsSubTabBar:RefreshGuildLock()
    end
    ApplyItemsSubTabGoldDisplay(sc._itemsGoldDisplay, sub)
    ApplyItemsSubTabStatsText(self, sc._itemsStatsText, sub)

    local function finishPerf()
        if not perfOn then return end
        local bodyMs = debugprofilestop()
        if ns.EmitPartialTabRefreshPerf then
            ns.EmitPartialTabRefreshPerf("items", fromSub, sub, bodyMs, wallStart)
        end
    end

    local function runBodyRedraw()
        if not (self.UI and self.UI.mainFrame and self.UI.mainFrame.currentTab == "items") then return end
        if sub == "personal" and self.RequestPersonalBankScanIfNeeded then
            self:RequestPersonalBankScanIfNeeded()
        end
        self:RedrawItemsResultsOnly()
        finishPerf()
    end

    runBodyRedraw()
    return true
end

--- Reposition cached Items fixedHeader chrome (Collections _fixedHeaderCache parity â€” WN-PERF tab revisit).
local function RepositionItemsFixedHeader(mf, hdrCache, headerParent, chrome, headerYOffset, contentSide, addon)
    local titleCard = hdrCache.titleCard
    titleCard:SetParent(headerParent)
    if chrome and ns.UI_AnchorTabTitleCard then
        ns.UI_AnchorTabTitleCard(titleCard, chrome)
    else
        titleCard:ClearAllPoints()
        titleCard:SetPoint("TOPLEFT", contentSide, -headerYOffset)
        titleCard:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    end
    titleCard:Show()

    if ns.UI_AdvanceTabChromeYOffset then
        headerYOffset = ns.UI_AdvanceTabChromeYOffset(headerYOffset, titleCard:GetHeight())
    else
        headerYOffset = headerYOffset + (GetLayout().afterHeader or 72)
    end

    local subTab = (ns.UI_GetItemsSubTab and ns.UI_GetItemsSubTab()) or "inventory"
    local subTabBar = hdrCache.subTabBar
    subTabBar:SetParent(headerParent)
    subTabBar:ClearAllPoints()
    subTabBar:SetPoint("TOPLEFT", contentSide, -headerYOffset)
    subTabBar:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    subTabBar:Show()
    subTabBar:SetActiveTab(subTab)
    if subTabBar.RefreshGuildLock then
        subTabBar:RefreshGuildLock()
    end
    ApplyItemsSubTabGoldDisplay(hdrCache.goldDisplay, subTab)

    headerYOffset = headerYOffset + ITEMS_BANK_SUBTAB_BTN_HEIGHT + GetLayout().afterElement

    local searchBox = hdrCache.searchBox
    searchBox:SetParent(headerParent)
    searchBox:ClearAllPoints()
    searchBox:SetPoint("TOPLEFT", contentSide, -headerYOffset)
    searchBox:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    searchBox:Show()
    if ns.UI_ApplySearchBoxChrome then
        ns.UI_ApplySearchBoxChrome(searchBox.searchFrame or searchBox, { editBoxHost = true })
    end
    local searchH = (ns.UI_CONSTANTS and ns.UI_CONSTANTS.SEARCH_BOX_HEIGHT) or 32
    if searchBox.SetHeight then
        searchBox:SetHeight(searchH)
    end

    headerYOffset = headerYOffset + searchH + GetLayout().afterElement

    local statsBar = hdrCache.statsBar
    statsBar:SetParent(headerParent)
    statsBar:ClearAllPoints()
    statsBar:SetPoint("TOPLEFT", contentSide, -headerYOffset)
    statsBar:SetPoint("TOPRIGHT", -contentSide, -headerYOffset)
    statsBar:SetHeight(24)
    statsBar:Show()
    if ns.UI_ApplySearchBoxChrome then
        ns.UI_ApplySearchBoxChrome(statsBar)
    end
    ApplyItemsSubTabStatsText(addon, hdrCache.statsText, subTab)

    headerYOffset = headerYOffset + 24 + GetLayout().afterElement
    return headerYOffset
end

-- DRAW ITEM LIST (Main Items Tab)

local function AcquireItemsResultsContainer(parent, scrollTopY, contentSide)
    local margin = contentSide or SIDE_MARGIN
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if not mf or mf.currentTab ~= "items" then
        local parked = parent.resultsContainer
        if parked and parked.Hide then
            parked:Hide()
            if parked:GetParent() == parent and ns.UI_RecycleBin then
                parked:SetParent(ns.UI_RecycleBin)
            end
        end
        return parked
    end
    local rc = parent.resultsContainer
    if rc and rc._wnKeepOnTabSwitch then
        rc:SetParent(parent)
        rc:ClearAllPoints()
        rc:SetPoint("TOPLEFT", margin, -scrollTopY)
        rc:SetPoint("TOPRIGHT", -margin, 0)
        rc:Show()
        return rc
    end
    rc = CreateResultsContainer(parent, scrollTopY, margin)
    rc._wnKeepOnTabSwitch = true
    parent.resultsContainer = rc
    return rc
end

ns.ItemsUI.AcquireItemsResultsContainer = AcquireItemsResultsContainer
ns.ItemsUI.RepositionItemsFixedHeader = RepositionItemsFixedHeader

