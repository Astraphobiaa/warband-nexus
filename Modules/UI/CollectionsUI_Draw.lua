--[[
    Warband Nexus - Collections tab (Draw)
    Loaded via WarbandNexus.toc after CollectionsUI_Shared.lua.
]]

local _, ns = ...
local M = ns.CollectionsUI
assert(M and M.state, "CollectionsUI_Shared.lua must load before this file")

local WarbandNexus = M.WarbandNexus
local FontManager = M.FontManager
local Constants = M.Constants
local Utilities = M.Utilities
local issecretvalue = M.issecretvalue
local SafeLower = M.SafeLower
local CreateCard = M.CreateCard
local CreateEmptyStateCard = M.CreateEmptyStateCard
local HideEmptyStateCard = M.HideEmptyStateCard
local CreateThemedCheckbox = M.CreateThemedCheckbox
local PlanCardFactory = M.PlanCardFactory
local COLORS = M.COLORS
local ApplyVisuals = M.ApplyVisuals
local UpdateBorderColor = M.UpdateBorderColor
local CreateCollapsibleHeader = M.CreateCollapsibleHeader
local ChainSectionFrameBelow = M.ChainSectionFrameBelow
local CreateIcon = M.CreateIcon
local LAYOUT = M.LAYOUT
local SIDE_MARGIN = M.SIDE_MARGIN
local TOP_MARGIN = M.TOP_MARGIN
local CARD_GAP = M.CARD_GAP
local AFTER_ELEMENT = M.AFTER_ELEMENT
local ROW_ICON_SIZE = M.ROW_ICON_SIZE
local DETAIL_ICON_SIZE = M.DETAIL_ICON_SIZE
local STATUS_ICON_SIZE = M.STATUS_ICON_SIZE
local SCROLL_CONTENT_TOP_PADDING = M.SCROLL_CONTENT_TOP_PADDING
local CONTENT_INSET = M.CONTENT_INSET
local CONTAINER_INSET = M.CONTAINER_INSET
local TEXT_GAP = M.TEXT_GAP
local SEARCH_ROW_HEIGHT = M.SEARCH_ROW_HEIGHT
local COLLECTIONS_TITLE_CARD_HEIGHT = M.COLLECTIONS_TITLE_CARD_HEIGHT
local RECENT_SECTION_ORDER = M.RECENT_SECTION_ORDER
local RECENT_CARD_ICON = M.RECENT_CARD_ICON
local RECENT_CARD_HEADER_PAD = M.RECENT_CARD_HEADER_PAD
local RECENT_ROW_ICON_BORDER_ALPHA = M.RECENT_ROW_ICON_BORDER_ALPHA
local RECENT_CARD_MIN_WIDTH = M.RECENT_CARD_MIN_WIDTH
local SUBTAB_BAR_HEIGHT = M.SUBTAB_BAR_HEIGHT
local PROGRESS_ROW_HEIGHT = M.PROGRESS_ROW_HEIGHT
local BAR_INSET = M.BAR_INSET
local SD = M.SD
local Factory = M.Factory
local PADDING = M.PADDING
local SCROLLBAR_GAP = M.SCROLLBAR_GAP
local SCROLLBAR_SIDE_GAP = M.SCROLLBAR_SIDE_GAP
local COLLECTION_HEAVY_DELAY = M.COLLECTION_HEAVY_DELAY
local RUN_CHUNK_SIZE = M.RUN_CHUNK_SIZE
local ROW_HEIGHT = M.ROW_HEIGHT
local ROW_GAP = M.ROW_GAP
local ROW_STRIDE = M.ROW_STRIDE
local COLLAPSE_HEADER_HEIGHT_COLL = M.COLLAPSE_HEADER_HEIGHT_COLL
local COLLECTION_LIST_DETAIL_SPLIT = M.COLLECTION_LIST_DETAIL_SPLIT
local DETAIL_SCROLLBAR_VERTICAL_INSET = M.DETAIL_SCROLLBAR_VERTICAL_INSET
local BORDER_INSET = M.BORDER_INSET
local VALID_COLLECTIONS_SUBTABS = M.VALID_COLLECTIONS_SUBTABS
local collectionsState = M.state
local CONTENT_GAP = M.CONTENT_GAP
local format = string.format
local time = time
local date = date
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local tremove = table.remove
local wipe = table.wipe

function M.SetCollectionProgress(current, total)
    local bar = M.state.collectionProgressBar
    local lbl = M.state.collectionProgressLabel
    if bar then
        bar:SetMinMaxValues(0, 1)
        bar:SetValue((total and total > 0 and current) and (current / total) or 0)
    end
    if lbl then
        lbl:SetText((current ~= nil and total ~= nil) and (tostring(current) .. " / " .. tostring(total)) or "— / —")
    end
end

function M.EnsureCollectionProgressBar(rightCol)
    if M.state.collectionProgressFrame or not rightCol then return end
    local barWidth = (rightCol:GetWidth() and (rightCol:GetWidth() - 4)) or 200
    local pr = Factory:CreateContainer(rightCol, math.max(64, barWidth), PROGRESS_ROW_HEIGHT, false)
    if not pr then
        pr = CreateFrame("Frame", nil, rightCol)
        pr:SetHeight(PROGRESS_ROW_HEIGHT)
    end
    pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
    pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
    local barHeight = 22
    local barWrapper = CreateFrame("Frame", nil, pr, "BackdropTemplate")
    barWrapper:SetAllPoints(pr)
    if ApplyVisuals then
        local barBg, barEdge = M.CollectionsProgressBarColors()
        ApplyVisuals(barWrapper, barBg, barEdge)
    end
    local innerW = math.max(1, barWidth - (BAR_INSET * 2))
    local innerH = math.max(1, barHeight - (BAR_INSET * 2))
    local barTrackBg, barEdge = M.CollectionsProgressBarColors()
    local statusBar = ns.UI_CreateStatusBar and ns.UI_CreateStatusBar(barWrapper, innerW, innerH, barTrackBg, barEdge, true)
    if statusBar then
        statusBar:ClearAllPoints()
        statusBar:SetPoint("TOPLEFT", barWrapper, "TOPLEFT", BAR_INSET, -BAR_INSET)
        statusBar:SetPoint("BOTTOMRIGHT", barWrapper, "BOTTOMRIGHT", -BAR_INSET, BAR_INSET)
        statusBar:SetMinMaxValues(0, 1)
        statusBar:SetValue(0)
        local barTexture = statusBar:GetStatusBarTexture()
        if barTexture then barTexture:SetColorTexture(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85) end
    end
    M.state.collectionProgressBar = statusBar
    local progressFs
    if FontManager.CreateBarOverlayFontString then
        progressFs = FontManager:CreateBarOverlayFontString(pr, "OVERLAY")
    else
        progressFs = FontManager:CreateFontString(pr, "body", "OVERLAY")
        if FontManager.ApplyBarOverlayFont then
            FontManager:ApplyBarOverlayFont(progressFs)
        end
    end
    if progressFs then
        if statusBar then
            progressFs:SetParent(statusBar)
            progressFs:SetDrawLayer("OVERLAY", 7)
            progressFs:SetPoint("CENTER", statusBar, "CENTER", 0, 0)
        else
            progressFs:SetPoint("CENTER", pr, "CENTER", 0, 0)
        end
        progressFs:SetJustifyH("CENTER")
        progressFs:SetJustifyV("MIDDLE")
        ns.UI_SetTextColorRole(progressFs, "Bright")
        progressFs:SetText("— / —")
    end
    M.state.collectionProgressLabel = progressFs
    M.state.collectionProgressFrame = pr
end

function M.DrawMountsContent(contentFrame)
    M.CollectionsSubTabTrace("DrawMountsContent_enter", { busy = M.state._drawMountsContentBusy and true or false })
    if M.state._drawMountsContentBusy then
        -- Self-heal: a leaked busy flag (abort path that missed its release) would
        -- otherwise spin this retry forever; after ~1s force-clear and draw anyway.
        local now = GetTime()
        M.state._drawMountsBusyRetryStart = M.state._drawMountsBusyRetryStart or now
        if (now - M.state._drawMountsBusyRetryStart) < 1 then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if M.CollectionsDrawRetryAllowed(contentFrame, "mounts") then
                        M.DrawMountsContent(contentFrame)
                    else
                        M.state._drawMountsContentBusy = nil
                        M.state._drawMountsBusyRetryStart = nil
                    end
                end)
            else
                M.state._drawMountsContentBusy = nil
            end
            return
        end
        M.ClearCollectionsDrawBusyFlags()
    end
    M.state._drawMountsBusyRetryStart = nil
    M.state._drawMountsContentBusy = true
    M.state._mountsDrawGen = (M.state._mountsDrawGen or 0) + 1
    local drawGen = M.state._mountsDrawGen
    M.state._drawMountsBusyGen = drawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = M.CollectionsFallbackContentWidth(parent)
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    -- Layout: LEFT = list, gap, scrollbar, gap, RIGHT = 3D viewer (equal SCROLLBAR_SIDE_GAP each side of scrollbar).
    local listContentWidth, listWidth, viewerWidth, scrollBarColumnWidth = M.ComputeCollectionsListDetailWidths(cw)

    local headerBlockH, innerCh = M.ApplyCollectionsContentHeader(contentFrame, "mounts", ch)
    M.HideAllCollectionsResultFrames()
    if M.state.mountListContainer then
        M.ReanchorCollectionsBrowseListHost(M.state.mountListContainer, contentFrame, headerBlockH, innerCh, listContentWidth)
    end

    -- LEFT CONTAINER: List only (scroll frame fills it; scrollbar in a separate column)
    if not M.state.mountListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        listContainer:Show()
        M.state.mountListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        M.EnableStandardScrollWheel(scrollFrame)
        M.state.mountListScrollFrame = scrollFrame

        local scrollChild = M.CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        M.state.mountListScrollChild = scrollChild

        -- SCROLLBAR RESERVE: visible between list and 3D view (equal gap).
        local scrollBarContainer = M.EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP)
        M.state.mountListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        M.state.mountListContainer:SetSize(listContentWidth, innerCh)
        M.state.mountListScrollBarContainer = M.EnsureListScrollBarContainer(
            M.state.mountListScrollBarContainer,
            contentFrame,
            M.state.mountListContainer,
            scrollBarColumnWidth,
            innerCh,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = M.state.mountListScrollFrame and M.state.mountListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, M.state.mountListScrollBarContainer, CONTAINER_INSET)
        end
    end
    M.state.mountListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + 3D viewer (below)
    local rightCol = M.state.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, viewerWidth), math.max(1, innerCh or 400), false)
        rightCol:SetPoint("TOPLEFT", M.state.mountListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
        rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
        rightCol:Show()
        M.state.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", M.state.mountListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    M.EnsureCollectionProgressBar(rightCol)
    local pr = M.state.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    if not M.state.modelViewer then
        local viewerContainer = Factory:CreateContainer(rightCol, viewerWidth, detailH, true)
        viewerContainer:ClearAllPoints()
        if pr then
            viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        viewerContainer:Show()
        M.state.viewerContainer = viewerContainer
        M.ApplyDetailAccentVisuals(viewerContainer)
        local emptyOverlay = M.CreateDetailEmptyOverlay(viewerContainer, "mount")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(viewerContainer:GetFrameLevel() + 5)
            M.state.mountDetailEmptyOverlay = emptyOverlay
        end
        local mv = M.CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        M.state.modelViewer = mv
        if not M.state.selectedMountID then
            mv:Hide()
            if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Show() end
        end
    else
        if M.state.viewerContainer then
            M.state.viewerContainer:SetParent(rightCol)
            M.state.viewerContainer:ClearAllPoints()
            if pr then
                M.state.viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                M.state.viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            M.state.viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
            M.ApplyDetailAccentVisuals(M.state.viewerContainer)
            if not M.state.mountDetailEmptyOverlay then
                local emptyOverlay = M.CreateDetailEmptyOverlay(M.state.viewerContainer, "mount")
                if emptyOverlay then
                    emptyOverlay:SetFrameLevel(M.state.viewerContainer:GetFrameLevel() + 5)
                    M.state.mountDetailEmptyOverlay = emptyOverlay
                end
            end
        end
        M.state.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
    end

    local function onSelectMount(mountID, name, icon, source, creatureDisplayID, description, isCollected)
        M.state.selectedMountID = mountID
        if M.state.mountDetailEmptyOverlay then
            M.state.mountDetailEmptyOverlay:SetShown(not mountID)
        end
        if M.state.modelViewer then
            M.state.modelViewer:SetShown(mountID ~= nil)
            if mountID then
                M.state.modelViewer:SetMount(mountID, creatureDisplayID)
                M.state.modelViewer:SetMountInfo(mountID, name, icon, source, description, isCollected)
            else
                M.state.modelViewer:SetMount(nil)
                M.state.modelViewer:SetMountInfo(nil)
            end
        end
    end
    if M.state.modelViewer and not M.state.selectedMountID then
        if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Show() end
        M.state.modelViewer:Hide()
    else
        if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Hide() end
        if M.state.modelViewer then M.state.modelViewer:Show() end
    end
    if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Hide() end

    -- Sync model viewer content with current tab: on Mounts show only mount or empty, never previous pet.
    if M.state.modelViewer then
        if M.state.selectedMountID then
            local mid = M.state.selectedMountID
            local md
            local am = M.state._cachedMountsData
            if am then
                for i = 1, #am do
                    if am[i].id == mid then md = am[i]; break end
                end
            end
            if md then
                M.state.modelViewer:SetMount(mid, md.creatureDisplayID)
                M.state.modelViewer:SetMountInfo(mid, md.name, md.icon, md.source, md.description, md.isCollected)
            else
                M.state.modelViewer:SetMount(mid, nil)
                M.state.modelViewer:SetMountInfo(mid, nil, nil, nil, nil, nil)
            end
        else
            M.state.modelViewer:SetMount(nil)
            M.state.modelViewer:SetPet(nil)
            M.state.modelViewer:SetMountInfo(nil)
            M.state.modelViewer:SetPetInfo(nil)
        end
    end

    -- Loading only when a scan is in progress or we have not yet completed initial fetch (no cache).
    -- Cache is set even when list is empty so we don't show loading forever for 0 mounts.
    M.EnsureCollectionsBrowseCacheForSubTab("mounts")
    local listW = listContentWidth - (CONTAINER_INSET * 2)
    local sch = M.state.mountListScrollChild
    local filtersOk = M.CollectionsSubTabBrowseFiltersUnchanged("mounts")
    if sch and M.state._mountFlatList and filtersOk then
        M.CollectionsSubTabTrace("DrawMountsContent_path", { path = "fast_visible_only" })
        if M.state.viewerContainer then M.state.viewerContainer:Show() end
        if not M.state.selectedMountID then
            if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Show() end
            if M.state.modelViewer then M.state.modelViewer:Hide() end
        else
            if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Hide() end
            if M.state.modelViewer then M.state.modelViewer:Show() end
        end
        if M.state.mountListContainer then M.state.mountListContainer:Show() end
        if M.state.mountListScrollBarContainer then M.state.mountListScrollBarContainer:Show() end
        if Factory.UpdateScrollBarVisibility and M.state.mountListScrollFrame then
            Factory:UpdateScrollBarVisibility(M.state.mountListScrollFrame)
        end
        if M.state._mountListRefreshVisible then
            M.state._mountListRefreshVisible()
        end
        M.state._drawMountsContentBusy = nil
        return
    end

    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allMounts = M.state._cachedMountsData
    local dataReady = (allMounts ~= nil)
    if not isLoading and not dataReady then
        isLoading = true
    end

    if isLoading then
        M.CollectionsSubTabTrace("DrawMountsContent_path", { path = "loading", dataReady = dataReady })
        M.SetCollectionProgress(nil, nil)
        if not M.state.loadingPanel then
            M.state.loadingPanel = M.GetOrCreateLoadingPanel(contentFrame)
        end
        M.state.loadingPanel:SetParent(contentFrame)
        M.state.loadingPanel:SetAllPoints(contentFrame)
        M.state.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        M.state.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
        if M.state.mountListContainer then M.state.mountListContainer:Hide() end
        if M.state.mountListScrollBarContainer then M.state.mountListScrollBarContainer:Hide() end
        if M.state.viewerContainer then M.state.viewerContainer:Hide() end
        -- No cache and no scan in progress: fetch data after short delay so tab switch stays responsive.
        if not (loadingState and loadingState.isLoading) and not dataReady then
            C_Timer.After(COLLECTION_HEAVY_DELAY, function()
                if M.state._mountsDrawGen ~= drawGen then return end
                if M.state.currentSubTab ~= "mounts" then return end
                if not contentFrame or not contentFrame:IsVisible() then return end
                local am = (WarbandNexus.GetAllMountsData and WarbandNexus:GetAllMountsData()) or {}
                M.state._cachedMountsData = am
                if #am == 0 then
                    RequestCollectionFillFromUI()
                end
                local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
                local collected = (apiCounts and apiCounts.mounts and apiCounts.mounts.collected) or 0
                local total = (apiCounts and apiCounts.mounts and apiCounts.mounts.total) or 0
                M.SetCollectionProgress(collected, total)
                if M.state.loadingPanel then M.state.loadingPanel:Hide() end
                if M.state.mountListContainer then M.state.mountListContainer:Show() end
                if M.state.mountListScrollBarContainer then M.state.mountListScrollBarContainer:Show() end
                if M.state.viewerContainer then M.state.viewerContainer:Show() end
                if not M.state.selectedMountID then
                    if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Show() end
                    if M.state.modelViewer then M.state.modelViewer:Hide() end
                else
                    if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Hide() end
                    if M.state.modelViewer then M.state.modelViewer:Show() end
                end
                local listW = listContentWidth - (CONTAINER_INSET * 2)
                local sch = M.state.mountListScrollChild
                -- Build and populate even when am is empty (show empty list; EnsureCollectionData may fill store later)
                M.RunChunkedMountBuild(
                    am,
                    M.state.searchText or "",
                    M.state.showCollected,
                    M.state.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if M.state._mountsDrawGen ~= drawGen or M.state.currentSubTab ~= "mounts" then return end
                        if not sch or not sch:GetParent() or not contentFrame:IsVisible() then return end
                        M.state._lastGroupedMountData = grouped
                        M.RecordCollectionsSubTabBrowseSnapshot("mounts")
                        C_Timer.After(0, function()
                            if M.state._mountsDrawGen ~= drawGen or M.state.currentSubTab ~= "mounts" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            M.PopulateMountList(sch, listW, grouped, M.state.collapsedHeadersMounts, M.state.selectedMountID, onSelectMount, contentFrame, DrawMountsContent, drawGen, function()
                                if Factory.UpdateScrollBarVisibility and M.state.mountListScrollFrame then
                                    Factory:UpdateScrollBarVisibility(M.state.mountListScrollFrame)
                                end
                                M.ReleaseCollectionsDrawBusy("Mounts", drawGen)
                            end)
                        end)
                    end
                )
            end)
        end
    else
        if M.state.loadingPanel then
            M.state.loadingPanel:Hide()
        end
        if M.state.viewerContainer then M.state.viewerContainer:Show() end
        if not M.state.selectedMountID then
            if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Show() end
            if M.state.modelViewer then M.state.modelViewer:Hide() end
        else
            if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Hide() end
            if M.state.modelViewer then M.state.modelViewer:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = M.state.mountListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.mounts and apiCounts.mounts.collected) or 0
        local total = (apiCounts and apiCounts.mounts and apiCounts.mounts.total) or 0
        M.SetCollectionProgress(collected, total)
        local filtersOk = M.CollectionsSubTabBrowseFiltersUnchanged("mounts")
        local cacheDiag = M.CollectionsSubTabBrowseCacheDiag("mounts")
        -- Tab switch back: grouped cache still valid — populate without chunked rebuild.
        if sch and M.state._lastGroupedMountData and filtersOk then
            M.CollectionsSubTabTrace("DrawMountsContent_path", { path = "populate_only", drawGen = drawGen })
            if M.state.mountListContainer then M.state.mountListContainer:Show() end
            if M.state.mountListScrollBarContainer then M.state.mountListScrollBarContainer:Show() end
            if M.state.viewerContainer then M.state.viewerContainer:Show() end
            M.RecordCollectionsSubTabBrowseSnapshot("mounts")
            M.PopulateMountList(sch, listW, M.state._lastGroupedMountData, M.state.collapsedHeadersMounts, M.state.selectedMountID, onSelectMount, contentFrame, DrawMountsContent, drawGen, function()
                if Factory.UpdateScrollBarVisibility and M.state.mountListScrollFrame then
                    Factory:UpdateScrollBarVisibility(M.state.mountListScrollFrame)
                end
                M.ReleaseCollectionsDrawBusy("Mounts", drawGen)
            end)
            return
        else
            M.CollectionsSubTabTrace("DrawMountsContent_path", {
                path = "full_repopulate",
                drawGen = drawGen,
                hasFlat = cacheDiag.hasFlat,
                hasGrouped = cacheDiag.hasGrouped,
                filtersOk = filtersOk,
            })
            -- First time or list not built: chunked build then populate.
            -- Busy is held across this chain; every abort must release it (gen-token guarded).
            C_Timer.After(0, function()
                if M.state._mountsDrawGen ~= drawGen then M.ReleaseCollectionsDrawBusy("Mounts", drawGen) return end
                if M.state.currentSubTab ~= "mounts" then M.ReleaseCollectionsDrawBusy("Mounts", drawGen) return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then M.ReleaseCollectionsDrawBusy("Mounts", drawGen) return end
                M.RunChunkedMountBuild(
                    allMounts,
                    M.state.searchText or "",
                    M.state.showCollected,
                    M.state.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if M.state._mountsDrawGen ~= drawGen or M.state.currentSubTab ~= "mounts" then M.ReleaseCollectionsDrawBusy("Mounts", drawGen) return end
                        if not sch:GetParent() or not contentFrame:IsVisible() then M.ReleaseCollectionsDrawBusy("Mounts", drawGen) return end
                        M.state._lastGroupedMountData = grouped
                        M.RecordCollectionsSubTabBrowseSnapshot("mounts")
                        C_Timer.After(0, function()
                            if M.state._mountsDrawGen ~= drawGen or M.state.currentSubTab ~= "mounts" then M.ReleaseCollectionsDrawBusy("Mounts", drawGen) return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then M.ReleaseCollectionsDrawBusy("Mounts", drawGen) return end
                            M.PopulateMountList(sch, listW, grouped, M.state.collapsedHeadersMounts, M.state.selectedMountID, onSelectMount, contentFrame, DrawMountsContent, drawGen, function()
                                if Factory.UpdateScrollBarVisibility and M.state.mountListScrollFrame then
                                    Factory:UpdateScrollBarVisibility(M.state.mountListScrollFrame)
                                end
                                M.ReleaseCollectionsDrawBusy("Mounts", drawGen)
                            end)
                        end)
                    end
                )
            end)
            return
        end
    end
    M.state._drawMountsContentBusy = nil
end

-- DrawPetsContent: same layout as mounts, uses pet API and list.
function M.DrawPetsContent(contentFrame)
    M.CollectionsSubTabTrace("DrawPetsContent_enter", { busy = M.state._drawPetsContentBusy and true or false })
    if M.state._drawPetsContentBusy then
        -- Self-heal: a leaked busy flag (abort path that missed its release) would
        -- otherwise spin this retry forever; after ~1s force-clear and draw anyway.
        local now = GetTime()
        M.state._drawPetsBusyRetryStart = M.state._drawPetsBusyRetryStart or now
        if (now - M.state._drawPetsBusyRetryStart) < 1 then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if M.CollectionsDrawRetryAllowed(contentFrame, "pets") then
                        M.DrawPetsContent(contentFrame)
                    else
                        M.state._drawPetsContentBusy = nil
                        M.state._drawPetsBusyRetryStart = nil
                    end
                end)
            else
                M.state._drawPetsContentBusy = nil
            end
            return
        end
        M.ClearCollectionsDrawBusyFlags()
    end
    M.state._drawPetsBusyRetryStart = nil
    M.state._drawPetsContentBusy = true
    M.state._petDrawGen = (M.state._petDrawGen or 0) + 1
    local drawGen = M.state._petDrawGen
    M.state._drawPetsBusyGen = drawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = M.CollectionsFallbackContentWidth(parent)
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth, listWidth, viewerWidth, scrollBarColumnWidth = M.ComputeCollectionsListDetailWidths(cw)

    local headerBlockH, innerCh = M.ApplyCollectionsContentHeader(contentFrame, "pets", ch)
    M.HideAllCollectionsResultFrames()
    if M.state.petListContainer then
        M.ReanchorCollectionsBrowseListHost(M.state.petListContainer, contentFrame, headerBlockH, innerCh, listContentWidth)
    end

    -- LEFT CONTAINER: Pet list
    if not M.state.petListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        listContainer:Show()
        M.state.petListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        M.EnableStandardScrollWheel(scrollFrame)
        M.state.petListScrollFrame = scrollFrame

        local scrollChild = M.CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        M.state.petListScrollChild = scrollChild

        local scrollBarContainer = M.EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP)
        M.state.petListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        M.state.petListContainer:SetSize(listContentWidth, innerCh)
        M.state.petListScrollBarContainer = M.EnsureListScrollBarContainer(
            M.state.petListScrollBarContainer,
            contentFrame,
            M.state.petListContainer,
            scrollBarColumnWidth,
            innerCh,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = M.state.petListScrollFrame and M.state.petListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, M.state.petListScrollBarContainer, CONTAINER_INSET)
        end
    end
    M.state.petListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + 3D viewer (below)
    local rightCol = M.state.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, viewerWidth), math.max(1, innerCh or 400), false)
        rightCol:Show()
        M.state.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", M.state.petListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    M.EnsureCollectionProgressBar(rightCol)
    local pr = M.state.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    if not M.state.modelViewer then
        local viewerContainer = Factory:CreateContainer(rightCol, viewerWidth, detailH, true)
        viewerContainer:ClearAllPoints()
        if pr then
            viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        viewerContainer:Show()
        M.state.viewerContainer = viewerContainer
        M.ApplyDetailAccentVisuals(viewerContainer)
        local emptyOverlay = M.CreateDetailEmptyOverlay(viewerContainer, "pet")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(viewerContainer:GetFrameLevel() + 5)
            M.state.petDetailEmptyOverlay = emptyOverlay
        end
        local mv = M.CreateModelViewer(viewerContainer, viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        mv:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        M.state.modelViewer = mv
        if not M.state.selectedPetID then
            mv:Hide()
            if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Show() end
        end
    else
        if M.state.viewerContainer then
            M.state.viewerContainer:SetParent(rightCol)
            M.state.viewerContainer:ClearAllPoints()
            if pr then
                M.state.viewerContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                M.state.viewerContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            M.state.viewerContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
            M.ApplyDetailAccentVisuals(M.state.viewerContainer)
            if not M.state.petDetailEmptyOverlay then
                local emptyOverlay = M.CreateDetailEmptyOverlay(M.state.viewerContainer, "pet")
                if emptyOverlay then
                    emptyOverlay:SetFrameLevel(M.state.viewerContainer:GetFrameLevel() + 5)
                    M.state.petDetailEmptyOverlay = emptyOverlay
                end
            end
        end
        M.state.modelViewer:SetSize(viewerWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
    end

    local function onSelectPet(speciesID, name, icon, source, creatureDisplayID, description, isCollected)
        M.state.selectedPetID = speciesID
        if M.state.petDetailEmptyOverlay then
            M.state.petDetailEmptyOverlay:SetShown(not speciesID)
        end
        if M.state.modelViewer then
            M.state.modelViewer:SetShown(speciesID ~= nil)
            if speciesID then
                M.state.modelViewer:SetPet(speciesID, creatureDisplayID)
                M.state.modelViewer:SetPetInfo(speciesID, name, icon, source, description, isCollected)
            else
                M.state.modelViewer:SetPet(nil)
                M.state.modelViewer:SetPetInfo(nil)
            end
        end
    end
    if M.state.modelViewer and not M.state.selectedPetID then
        if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Show() end
        M.state.modelViewer:Hide()
    else
        if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Hide() end
        if M.state.modelViewer then M.state.modelViewer:Show() end
    end
    if M.state.mountDetailEmptyOverlay then M.state.mountDetailEmptyOverlay:Hide() end

    -- Sync model viewer content with current tab: on Pets show only pet or empty, never previous mount.
    if M.state.modelViewer then
        if M.state.selectedPetID then
            local sid = M.state.selectedPetID
            local pd
            local ap = M.state._cachedPetsData
            if ap then
                for i = 1, #ap do
                    if ap[i].id == sid then pd = ap[i]; break end
                end
            end
            if pd then
                M.state.modelViewer:SetPet(sid, pd.creatureDisplayID)
                M.state.modelViewer:SetPetInfo(sid, pd.name, pd.icon, pd.source, pd.description, pd.isCollected)
            else
                M.state.modelViewer:SetPet(sid, nil)
                M.state.modelViewer:SetPetInfo(sid, nil, nil, nil, nil, nil)
            end
        else
            M.state.modelViewer:SetMount(nil)
            M.state.modelViewer:SetPet(nil)
            M.state.modelViewer:SetMountInfo(nil)
            M.state.modelViewer:SetPetInfo(nil)
        end
    end

    -- Pets: avoid sync GetAllPetsData on click (can hitch); cache from WarmCollectionsBrowseCaches or loading branch.
    local listW = listContentWidth - (CONTAINER_INSET * 2)
    local schEarly = M.state.petListScrollChild
    local filtersOkEarly = M.CollectionsSubTabBrowseFiltersUnchanged("pets")
    if schEarly and M.state._petFlatList and filtersOkEarly then
        M.CollectionsSubTabTrace("DrawPetsContent_path", { path = "fast_visible_only" })
        if M.state.viewerContainer then M.state.viewerContainer:Show() end
        if not M.state.selectedPetID then
            if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Show() end
            if M.state.modelViewer then M.state.modelViewer:Hide() end
        else
            if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Hide() end
            if M.state.modelViewer then M.state.modelViewer:Show() end
        end
        if M.state.petListContainer then M.state.petListContainer:Show() end
        if M.state.petListScrollBarContainer then M.state.petListScrollBarContainer:Show() end
        if Factory.UpdateScrollBarVisibility and M.state.petListScrollFrame then
            Factory:UpdateScrollBarVisibility(M.state.petListScrollFrame)
        end
        if M.state._petListRefreshVisible then
            M.state._petListRefreshVisible()
        end
        M.state._drawPetsContentBusy = nil
        return
    end

    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    local allPets = M.state._cachedPetsData
    local dataReady = (allPets ~= nil)
    if not isLoading and not dataReady then
        isLoading = true
    end

    if isLoading then
        M.CollectionsSubTabTrace("DrawPetsContent_path", { path = "loading", dataReady = dataReady and true or false })
        M.SetCollectionProgress(nil, nil)
        if not M.state.loadingPanel then
            M.state.loadingPanel = M.GetOrCreateLoadingPanel(contentFrame)
        end
        M.state.loadingPanel:SetParent(contentFrame)
        M.state.loadingPanel:SetAllPoints(contentFrame)
        M.state.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        M.state.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
        if M.state.petListContainer then M.state.petListContainer:Hide() end
        if M.state.petListScrollBarContainer then M.state.petListScrollBarContainer:Hide() end
        if M.state.viewerContainer then M.state.viewerContainer:Hide() end
        if not (loadingState and loadingState.isLoading) and not dataReady then
            C_Timer.After(COLLECTION_HEAVY_DELAY, function()
                if M.state._petDrawGen ~= drawGen then return end
                if M.state.currentSubTab ~= "pets" then return end
                if not contentFrame or not contentFrame:IsVisible() then return end
                local ap = (WarbandNexus.GetAllPetsData and WarbandNexus:GetAllPetsData()) or {}
                if #ap > 0 then
                    M.state._cachedPetsData = ap
                else
                    RequestCollectionFillFromUI()
                end
                local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
                local collected = (apiCounts and apiCounts.pets and apiCounts.pets.uniqueSpecies) or 0
                local total = (apiCounts and apiCounts.pets and apiCounts.pets.totalSpecies) or 0
                M.SetCollectionProgress(collected, total)
                if M.state.loadingPanel then M.state.loadingPanel:Hide() end
                if M.state.petListContainer then M.state.petListContainer:Show() end
                if M.state.petListScrollBarContainer then M.state.petListScrollBarContainer:Show() end
                if M.state.viewerContainer then M.state.viewerContainer:Show() end
                if not M.state.selectedPetID then
                    if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Show() end
                    if M.state.modelViewer then M.state.modelViewer:Hide() end
                else
                    if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Hide() end
                    if M.state.modelViewer then M.state.modelViewer:Show() end
                end
                local listW = listContentWidth - (CONTAINER_INSET * 2)
                local sch = M.state.petListScrollChild
                M.RunChunkedPetBuild(
                    ap,
                    M.state.searchText or "",
                    M.state.showCollected,
                    M.state.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if M.state._petDrawGen ~= drawGen or M.state.currentSubTab ~= "pets" then return end
                        if not sch or not sch:GetParent() or not contentFrame:IsVisible() then return end
                        M.state._lastGroupedPetData = grouped
                        M.RecordCollectionsSubTabBrowseSnapshot("pets")
                        C_Timer.After(0, function()
                            if M.state._petDrawGen ~= drawGen or M.state.currentSubTab ~= "pets" then return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then return end
                            M.PopulatePetList(sch, listW, grouped, M.state.collapsedHeadersPets, M.state.selectedPetID, onSelectPet, contentFrame, DrawPetsContent, drawGen, function()
                                if Factory.UpdateScrollBarVisibility and M.state.petListScrollFrame then
                                    Factory:UpdateScrollBarVisibility(M.state.petListScrollFrame)
                                end
                                M.ReleaseCollectionsDrawBusy("Pets", drawGen)
                            end)
                        end)
                    end
                )
            end)
        end
    else
        if M.state.loadingPanel then
            M.state.loadingPanel:Hide()
        end
        if M.state.viewerContainer then M.state.viewerContainer:Show() end
        if not M.state.selectedPetID then
            if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Show() end
            if M.state.modelViewer then M.state.modelViewer:Hide() end
        else
            if M.state.petDetailEmptyOverlay then M.state.petDetailEmptyOverlay:Hide() end
            if M.state.modelViewer then M.state.modelViewer:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = M.state.petListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.pets and apiCounts.pets.uniqueSpecies) or 0
        local total = (apiCounts and apiCounts.pets and apiCounts.pets.totalSpecies) or 0
        M.SetCollectionProgress(collected, total)
        local filtersOk = M.CollectionsSubTabBrowseFiltersUnchanged("pets")
        local cacheDiag = M.CollectionsSubTabBrowseCacheDiag("pets")
        if sch and M.state._lastGroupedPetData and filtersOk then
            M.CollectionsSubTabTrace("DrawPetsContent_path", { path = "populate_only", drawGen = drawGen })
            if M.state.petListContainer then M.state.petListContainer:Show() end
            if M.state.petListScrollBarContainer then M.state.petListScrollBarContainer:Show() end
            if M.state.viewerContainer then M.state.viewerContainer:Show() end
            M.RecordCollectionsSubTabBrowseSnapshot("pets")
            M.PopulatePetList(sch, listW, M.state._lastGroupedPetData, M.state.collapsedHeadersPets, M.state.selectedPetID, onSelectPet, contentFrame, DrawPetsContent, drawGen, function()
                if Factory.UpdateScrollBarVisibility and M.state.petListScrollFrame then
                    Factory:UpdateScrollBarVisibility(M.state.petListScrollFrame)
                end
                M.ReleaseCollectionsDrawBusy("Pets", drawGen)
            end)
            return
        else
            M.CollectionsSubTabTrace("DrawPetsContent_path", {
                path = "full_repopulate",
                drawGen = drawGen,
                hasFlat = cacheDiag.hasFlat,
                hasGrouped = cacheDiag.hasGrouped,
                filtersOk = filtersOk,
            })
            -- First time or list not built: chunked build then populate.
            -- Busy is held across this chain; every abort must release it (gen-token guarded).
            C_Timer.After(0, function()
                if M.state._petDrawGen ~= drawGen then M.ReleaseCollectionsDrawBusy("Pets", drawGen) return end
                if M.state.currentSubTab ~= "pets" then M.ReleaseCollectionsDrawBusy("Pets", drawGen) return end
                if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then M.ReleaseCollectionsDrawBusy("Pets", drawGen) return end
                M.RunChunkedPetBuild(
                    allPets,
                    M.state.searchText or "",
                    M.state.showCollected,
                    M.state.showUncollected,
                    drawGen,
                    contentFrame,
                    function(grouped)
                        if M.state._petDrawGen ~= drawGen or M.state.currentSubTab ~= "pets" then M.ReleaseCollectionsDrawBusy("Pets", drawGen) return end
                        if not sch:GetParent() or not contentFrame:IsVisible() then M.ReleaseCollectionsDrawBusy("Pets", drawGen) return end
                        M.state._lastGroupedPetData = grouped
                        M.RecordCollectionsSubTabBrowseSnapshot("pets")
                        C_Timer.After(0, function()
                            if M.state._petDrawGen ~= drawGen or M.state.currentSubTab ~= "pets" then M.ReleaseCollectionsDrawBusy("Pets", drawGen) return end
                            if not sch:GetParent() or not contentFrame:IsVisible() then M.ReleaseCollectionsDrawBusy("Pets", drawGen) return end
                            M.PopulatePetList(sch, listW, grouped, M.state.collapsedHeadersPets, M.state.selectedPetID, onSelectPet, contentFrame, DrawPetsContent, drawGen, function()
                                if Factory.UpdateScrollBarVisibility and M.state.petListScrollFrame then
                                    Factory:UpdateScrollBarVisibility(M.state.petListScrollFrame)
                                end
                                M.ReleaseCollectionsDrawBusy("Pets", drawGen)
                            end)
                        end)
                    end
                )
            end)
            return
        end
    end
    M.state._drawPetsContentBusy = nil
end

-- DrawToysContent: list left (grouped by source), toy detail panel right (icon, name, source, description). No 3D viewer.
function M.DrawToysContent(contentFrame)
    M.CollectionsSubTabTrace("DrawToysContent_enter", { busy = M.state._drawToysContentBusy and true or false })
    if M.state._drawToysContentBusy then
        -- Self-heal: a leaked busy flag (abort path that missed its release) would
        -- otherwise spin this retry forever; after ~1s force-clear and draw anyway.
        local now = GetTime()
        M.state._drawToysBusyRetryStart = M.state._drawToysBusyRetryStart or now
        if (now - M.state._drawToysBusyRetryStart) < 1 then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if M.CollectionsDrawRetryAllowed(contentFrame, "toys") then
                        M.DrawToysContent(contentFrame)
                    else
                        M.state._drawToysContentBusy = nil
                        M.state._drawToysBusyRetryStart = nil
                    end
                end)
            else
                M.state._drawToysContentBusy = nil
            end
            return
        end
        M.ClearCollectionsDrawBusyFlags()
    end
    M.state._drawToysBusyRetryStart = nil
    M.state._drawToysContentBusy = true
    M.state._toysDrawGen = (M.state._toysDrawGen or 0) + 1
    local drawGen = M.state._toysDrawGen
    M.state._drawToysBusyGen = drawGen
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = M.CollectionsFallbackContentWidth(parent)
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth, listWidth, detailWidth, scrollBarColumnWidth = M.ComputeCollectionsListDetailWidths(cw)

    local headerBlockH, innerCh = M.ApplyCollectionsContentHeader(contentFrame, "toys", ch)
    M.HideAllCollectionsResultFrames()
    if M.state.toyListContainer then
        M.ReanchorCollectionsBrowseListHost(M.state.toyListContainer, contentFrame, headerBlockH, innerCh, listContentWidth)
    end

    -- LEFT: Toy list container + scroll
    if not M.state.toyListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        listContainer:Show()
        M.state.toyListContainer = listContainer

        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        M.EnableStandardScrollWheel(scrollFrame)
        M.state.toyListScrollFrame = scrollFrame

        local scrollChild = M.CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        M.state.toyListScrollChild = scrollChild

        local scrollBarContainer = M.EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP)
        M.state.toyListScrollBarContainer = scrollBarContainer

        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, scrollBarContainer, CONTAINER_INSET)
        end
    else
        M.state.toyListContainer:SetSize(listContentWidth, innerCh)
        M.state.toyListScrollBarContainer = M.EnsureListScrollBarContainer(
            M.state.toyListScrollBarContainer,
            contentFrame,
            M.state.toyListContainer,
            scrollBarColumnWidth,
            innerCh,
            SCROLLBAR_SIDE_GAP
        )
        local scrollBar = M.state.toyListScrollFrame and M.state.toyListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, M.state.toyListScrollBarContainer, CONTAINER_INSET)
        end
    end
    M.state.toyListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + toy detail panel (below)
    local rightCol = M.state.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, detailWidth), math.max(1, innerCh or 400), false)
        rightCol:Show()
        M.state.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", M.state.toyListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    M.EnsureCollectionProgressBar(rightCol)
    local pr = M.state.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    -- RIGHT: Toy detail panel — below progress
    local SECTION_BODY_INDENT = (ns.UI_LAYOUT and ns.UI_LAYOUT.BASE_INDENT) or 12
    local TEXT_GAP_LINE = TEXT_GAP or 8
    if not M.state.toyDetailContainer then
        local detailContainer = Factory:CreateContainer(rightCol, detailWidth, detailH, true)
        detailContainer:ClearAllPoints()
        if pr then
            detailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            detailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        detailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        detailContainer:Show()
        M.state.toyDetailContainer = detailContainer
        M.ApplyDetailAccentVisuals(detailContainer)
        local emptyOverlay = M.CreateDetailEmptyOverlay(detailContainer, "toy")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(detailContainer:GetFrameLevel() + 5)
            M.state.toyDetailEmptyOverlay = emptyOverlay
        end

        M.state.toyDetailScrollBarContainer = M.EnsureDetailScrollBarContainer(
            M.state.toyDetailScrollBarContainer,
            detailContainer,
            SCROLLBAR_GAP,
            CONTAINER_INSET
        )
        local scroll = Factory:CreateScrollFrame(detailContainer, "UIPanelScrollFrameTemplate", true)
        scroll:SetPoint("TOPLEFT", detailContainer, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
        scroll:SetPoint("BOTTOMRIGHT", M.state.toyDetailScrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
        M.EnableStandardScrollWheel(scroll)
        M.state._toyDetailScroll = scroll

        local scrollChild = M.CreateStandardScrollChild(scroll, detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP, 1)
        M.state._toyDetailScrollChild = scrollChild
        if scroll.ScrollBar then
            Factory:PositionScrollBarInContainer(scroll.ScrollBar, M.state.toyDetailScrollBarContainer, CONTAINER_INSET)
        end

        -- Header row: same right column as Mounts/Pets (Wowhead + Add + try, try at Add width).
        local CDL = ns.CollectionsDetailHeaderLayout or {}
        local toyRightColH = (CDL.ACTION_SLOT_H or 28) + (CDL.TRY_GAP or 4) + (CDL.TRY_ROW_H or 18)
        local toyHdrH = math.max(ROW_HEIGHT + TEXT_GAP_LINE, DETAIL_ICON_SIZE + TEXT_GAP_LINE, toyRightColH)
        local toyHdrW = math.max(200, detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        local headerRow = Factory:CreateContainer(scrollChild, toyHdrW, toyHdrH, false)
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, scrollChild)
        end
        headerRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetHeight(toyHdrH)
        local iconBorder = Factory:CreateContainer(headerRow, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
        iconBorder:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        if M.ApplyCollectionsIconBorder then
            M.ApplyCollectionsIconBorder(iconBorder, 0.7, { detailWell = true })
        elseif ApplyVisuals then
            local bg, edge = M.CollectionsIconBorderColors(0.7)
            ApplyVisuals(iconBorder, bg, edge)
        end
        local iconTex = iconBorder:CreateTexture(nil, "OVERLAY")
        iconTex:SetAllPoints()
        iconTex:SetTexture(M.DEFAULT_ICON_TOY)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        M.state._toyDetailIcon = iconTex
        M.state._toyDetailIconBorder = iconBorder

        local DETAIL_HEADER_GAP = 10
        local goldR, goldG, goldB = 1, 0.82, 0
        if ns.UI_GetSemanticGoldColor then
            goldR, goldG, goldB = ns.UI_GetSemanticGoldColor()
        elseif COLORS.gold then
            goldR, goldG, goldB = COLORS.gold[1], COLORS.gold[2], COLORS.gold[3]
        end
        local nameFs = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
        nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
        nameFs:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(true)
        nameFs:SetNonSpaceWrap(true)
        nameFs:SetTextColor(goldR, goldG, goldB)
        nameFs:SetText("")
        M.state._toyDetailName = nameFs
        M.state._toyDetailHeaderRow = headerRow

        local toyAddCol = Factory.CreateCollectionsDetailRightColumn and Factory:CreateCollectionsDetailRightColumn(headerRow, { withTryRow = true })
        local toyAddContainer = toyAddCol and toyAddCol.root
        local toyActionSlot = toyAddCol and toyAddCol.actionSlot
        if toyAddContainer then
            toyAddContainer:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
            toyAddContainer:Hide()
        end
        M.state._toyDetailAddContainer = toyAddContainer
        if toyActionSlot then
            M.state._toyDetailAddBtn = M.CreateCollectionsDetailPlanButton(toyActionSlot)
            M.state._toyDetailAddedIndicator = nil
        end
        if nameFs and toyAddContainer then
            nameFs:ClearAllPoints()
            nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
            nameFs:SetPoint("TOPRIGHT", toyAddContainer, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
        end
        M.state._toyDetailWowheadBtn = toyAddCol and toyAddCol.wowheadBtn
        M.state._toyDetailTryCountRow = toyAddCol and toyAddCol.tryCountRow

        local collectedBadge = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        collectedBadge:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        collectedBadge:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
        collectedBadge:SetJustifyH("LEFT")
        collectedBadge:SetWordWrap(true)
        collectedBadge:SetText("")
        collectedBadge:Hide()
        M.state._toyDetailCollectedBadge = collectedBadge

        local sourceLabel = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        sourceLabel:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        sourceLabel:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
        sourceLabel:SetJustifyH("LEFT")
        sourceLabel:SetWordWrap(true)
        sourceLabel:SetText("")
        M.state._toyDetailSourceLabel = sourceLabel

        local toyObtainedLine = M.CreateCollectionsSmallLabel(scrollChild)
        toyObtainedLine:SetJustifyH("LEFT")
        toyObtainedLine:SetWordWrap(true)
        ns.UI_SetTextColorRole(toyObtainedLine, "Dim")
        toyObtainedLine:Hide()
        M.state._toyDetailObtainedLine = toyObtainedLine
    else
        M.state.toyDetailContainer:SetParent(rightCol)
        M.state.toyDetailContainer:SetSize(detailWidth, detailH)
        M.state.toyDetailContainer:ClearAllPoints()
        if pr then
            M.state.toyDetailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            M.state.toyDetailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        M.state.toyDetailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        M.ApplyDetailAccentVisuals(M.state.toyDetailContainer)
        M.state.toyDetailScrollBarContainer = M.EnsureDetailScrollBarContainer(
            M.state.toyDetailScrollBarContainer,
            M.state.toyDetailContainer,
            SCROLLBAR_GAP,
            CONTAINER_INSET
        )
        if M.state._toyDetailScroll then
            M.state._toyDetailScroll:ClearAllPoints()
            M.state._toyDetailScroll:SetPoint("TOPLEFT", M.state.toyDetailContainer, "TOPLEFT", CONTAINER_INSET, -(CONTAINER_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
            M.state._toyDetailScroll:SetPoint("BOTTOMRIGHT", M.state.toyDetailScrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
            if M.state._toyDetailScroll.ScrollBar then
                Factory:PositionScrollBarInContainer(M.state._toyDetailScroll.ScrollBar, M.state.toyDetailScrollBarContainer, CONTAINER_INSET)
            end
        end
        if M.state._toyDetailScrollChild then
            M.state._toyDetailScrollChild:SetWidth(detailWidth - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        end
    end

    local function UpdateToyDetailPanel(itemID, name, icon, isCollected, sourceTypeName)
        if M.state._toyDetailAddContainer then
            if not itemID then
                M.state._toyDetailAddContainer:Hide()
            else
                M.state._toyDetailAddContainer:Show()
                local addBtn = M.state._toyDetailAddBtn
                if addBtn and WarbandNexus then
                    local planned = WarbandNexus.IsItemPlanned and WarbandNexus:IsItemPlanned("toy", itemID)
                    M.RefreshCollectionsDetailPlanButton(addBtn, isCollected, planned, function()
                        if WarbandNexus and WarbandNexus.AddPlan then
                            WarbandNexus:AddPlan({
                                type = "toy",
                                itemID = itemID,
                                name = name,
                                icon = icon,
                                source = sourceTypeName or (ns.L and ns.L["UNKNOWN"]) or "Unknown",
                            })
                        end
                    end)
                end
            end
        end
        -- Resolve display name: avoid showing raw ID when API didn't return name
        local displayName = name and name ~= "" and name or ""
        if (displayName == "" or (itemID and displayName == tostring(itemID))) and itemID and WarbandNexus.ResolveCollectionMetadata then
            local meta = WarbandNexus:ResolveCollectionMetadata("toy", itemID)
            if meta and meta.name and meta.name ~= "" and meta.name ~= tostring(itemID) then
                displayName = meta.name
            elseif itemID and C_Item and C_Item.GetItemInfo then
                local itemName = C_Item.GetItemInfo(itemID)
                if itemName and type(itemName) == "string" and itemName ~= "" then
                    displayName = itemName
                end
            end
        end
        if displayName == "" and itemID then displayName = tostring(itemID) end
        if M.state._toyDetailIcon then
            M.state._toyDetailIcon:SetTexture(icon or M.DEFAULT_ICON_TOY)
            M.state._toyDetailIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        if M.state._toyDetailName then
            local gold = COLORS.gold or { 1, 0.82, 0 }
            local goldHex = ns.UI_RGBToHex(gold[1], gold[2], gold[3])
            local trySuffix = (SD and SD.FormatMountPetToyListTrySuffix and itemID)
                and SD.FormatMountPetToyListTrySuffix("toy", itemID) or ""
            M.state._toyDetailName:SetText(goldHex .. (displayName or "") .. "|r" .. trySuffix)
        end
        if M.state._toyDetailCollectedBadge then
            M.state._toyDetailCollectedBadge:Hide()
        end
        if M.state._toyDetailSourceLabel then
            local srcLabel = M.state._toyDetailSourceLabel
            local srcText = (sourceTypeName and sourceTypeName ~= "") and sourceTypeName or ((ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown")
            if srcText == "SOURCE_UNKNOWN" then srcText = "Unknown" end
            local sourceTitle = (ns.L and ns.L["SOURCE"]) or "Source"
            if sourceTitle == "SOURCE" then sourceTitle = "Source" end
            local gold = COLORS.gold or { 1, 0.82, 0 }
            local goldHex = M.CollectionsGoldHex and M.CollectionsGoldHex()
                or (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex())
                or ns.UI_RGBToHex(gold[1], gold[2], gold[3])
            local brightHex = M.CollectionsBrightHex and M.CollectionsBrightHex() or "|cffeeeeee"
            srcLabel:SetText(goldHex .. sourceTitle .. ":|r " .. brightHex .. srcText .. "|r")
        end
        if M.state._toyDetailObtainedLine and M.state._toyDetailSourceLabel then
            local ol = M.state._toyDetailObtainedLine
            local srcLabel = M.state._toyDetailSourceLabel
            ol:ClearAllPoints()
            if isCollected and itemID and WarbandNexus and WarbandNexus.GetCollectionsAcquiredAt then
                local ts = WarbandNexus:GetCollectionsAcquiredAt("toy", itemID)
                local txt = ts and M.FormatCollectionsAcquiredDetail(ts) or nil
                if txt then
                    ol:SetPoint("TOPLEFT", srcLabel, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
                    ol:SetPoint("TOPRIGHT", srcLabel, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
                    ol:SetText(txt)
                    ol:Show()
                else
                    ol:Hide()
                end
            else
                ol:Hide()
            end
        end
        local toyTryRow = M.state._toyDetailTryCountRow
        if toyTryRow and toyTryRow.WnUpdateTryCount then
            if itemID then
                toyTryRow:WnUpdateTryCount("toy", itemID, displayName)
            else
                toyTryRow:Hide()
            end
        end
        if M.state._toyDetailWowheadBtn then
            if itemID and itemID > 0 then
                M.state._toyDetailWowheadBtn:SetScript("OnClick", function(self)
                    if ns.UI.Factory and ns.UI.Factory.ShowWowheadCopyURL then
                        ns.UI.Factory:ShowWowheadCopyURL("toy", itemID, self)
                    end
                end)
                M.state._toyDetailWowheadBtn:Show()
            else
                M.state._toyDetailWowheadBtn:Hide()
            end
        end
        if M.state._toyDetailScrollChild and C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                local child = M.state._toyDetailScrollChild
                if not child then return end
                local lastEl = M.state._toyDetailObtainedLine
                if not lastEl or not lastEl:IsShown() then
                    lastEl = M.state._toyDetailSourceLabel or M.state._toyDetailCollectedBadge
                end
                if lastEl and lastEl.GetBottom and child.GetTop then
                    local top = child:GetTop()
                    local bot = lastEl:GetBottom()
                    if top and bot then
                        child:SetHeight(math.max(1, top - bot + PADDING))
                    end
                end
            end)
        end
    end

    local function onSelectToy(itemID, name, icon, _source, _description, isCollected, sourceTypeName)
        M.state.selectedToyID = itemID
        if M.state.toyDetailEmptyOverlay then
            M.state.toyDetailEmptyOverlay:SetShown(not itemID)
        end
        if M.state._toyDetailScroll then
            M.state._toyDetailScroll:SetShown(itemID ~= nil)
        end
        UpdateToyDetailPanel(itemID, name or "", icon or M.DEFAULT_ICON_TOY, isCollected, sourceTypeName)
    end

    -- Toys: list from C_ToyBox source type API; warm cache when available.
    M.EnsureCollectionsBrowseCacheForSubTab("toys")
    local listWEarly = listContentWidth - (CONTAINER_INSET * 2)
    local schEarly = M.state.toyListScrollChild
    local filtersOkEarly = M.CollectionsSubTabBrowseFiltersUnchanged("toys")
    if schEarly and M.state._toyFlatList and filtersOkEarly then
        M.CollectionsSubTabTrace("DrawToysContent_path", { path = "fast_visible_only" })
        if M.state.toyDetailContainer then M.state.toyDetailContainer:Show() end
        if not M.state.selectedToyID then
            if M.state.toyDetailEmptyOverlay then M.state.toyDetailEmptyOverlay:Show() end
            if M.state._toyDetailScroll then M.state._toyDetailScroll:Hide() end
        else
            if M.state.toyDetailEmptyOverlay then M.state.toyDetailEmptyOverlay:Hide() end
            if M.state._toyDetailScroll then M.state._toyDetailScroll:Show() end
        end
        if M.state.toyListContainer then M.state.toyListContainer:Show() end
        if M.state.toyListScrollBarContainer then M.state.toyListScrollBarContainer:Show() end
        if Factory.UpdateScrollBarVisibility and M.state.toyListScrollFrame then
            Factory:UpdateScrollBarVisibility(M.state.toyListScrollFrame)
        end
        if M.state._toyListRefreshVisible then
            M.state._toyListRefreshVisible()
        end
        M.state._drawToysContentBusy = nil
        return
    end

    local dataReady = true
    local loadingState = ns.CollectionLoadingState
    local isLoading = loadingState and loadingState.isLoading
    if not dataReady and not isLoading then
        isLoading = true
    end

    if isLoading and not dataReady then
        M.CollectionsSubTabTrace("DrawToysContent_path", { path = "loading" })
        M.SetCollectionProgress(nil, nil)
        if not M.state.loadingPanel then
            M.state.loadingPanel = M.GetOrCreateLoadingPanel(contentFrame)
        end
        M.state.loadingPanel:SetParent(contentFrame)
        M.state.loadingPanel:SetAllPoints(contentFrame)
        M.state.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or ((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Loading collections...")
        M.state.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_COLLECTIONS"]) or "Scanning collections...", progress, stage)
        if M.state.toyListContainer then M.state.toyListContainer:Hide() end
        if M.state.toyListScrollBarContainer then M.state.toyListScrollBarContainer:Hide() end
        if M.state.toyDetailContainer then M.state.toyDetailContainer:Hide() end
        C_Timer.After(COLLECTION_HEAVY_DELAY, function()
            if M.state._toysDrawGen ~= drawGen or M.state.currentSubTab ~= "toys" then return end
            if not contentFrame or not contentFrame:IsVisible() then return end
            RequestCollectionFillFromUI()
            local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
            local collected = (apiCounts and apiCounts.toys and apiCounts.toys.collected) or 0
            local total = (apiCounts and apiCounts.toys and apiCounts.toys.total) or 0
            M.SetCollectionProgress(collected, total)
            if M.state.loadingPanel then M.state.loadingPanel:Hide() end
            if M.state.toyListContainer then M.state.toyListContainer:Show() end
            if M.state.toyListScrollBarContainer then M.state.toyListScrollBarContainer:Show() end
            if M.state.toyDetailContainer then M.state.toyDetailContainer:Show() end
            if not M.state.selectedToyID then
                if M.state.toyDetailEmptyOverlay then M.state.toyDetailEmptyOverlay:Show() end
                if M.state._toyDetailScroll then M.state._toyDetailScroll:Hide() end
            else
                if M.state.toyDetailEmptyOverlay then M.state.toyDetailEmptyOverlay:Hide() end
                if M.state._toyDetailScroll then M.state._toyDetailScroll:Show() end
            end
            local listW = listContentWidth - (CONTAINER_INSET * 2)
            local sch = M.state.toyListScrollChild
            local grouped = M.GetFilteredToysGrouped(M.state.searchText or "", M.state.showCollected, M.state.showUncollected)
            if M.state._toysDrawGen == drawGen and M.state.currentSubTab == "toys" and sch and sch:GetParent() and contentFrame:IsVisible() then
                M.state._lastGroupedToyData = grouped
                M.PopulateToyList(sch, listW, grouped, M.state.collapsedHeadersToys, M.state.selectedToyID, onSelectToy, contentFrame, DrawToysContent, drawGen, function()
                    if Factory.UpdateScrollBarVisibility and M.state.toyListScrollFrame then
                        Factory:UpdateScrollBarVisibility(M.state.toyListScrollFrame)
                    end
                    M.ReleaseCollectionsDrawBusy("Toys", drawGen)
                end)
            end
        end)
    else
        if M.state.loadingPanel then M.state.loadingPanel:Hide() end
        if M.state.toyDetailContainer then M.state.toyDetailContainer:Show() end
        if not M.state.selectedToyID then
            if M.state.toyDetailEmptyOverlay then M.state.toyDetailEmptyOverlay:Show() end
            if M.state._toyDetailScroll then M.state._toyDetailScroll:Hide() end
        else
            if M.state.toyDetailEmptyOverlay then M.state.toyDetailEmptyOverlay:Hide() end
            if M.state._toyDetailScroll then M.state._toyDetailScroll:Show() end
        end

        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local sch = M.state.toyListScrollChild
        local apiCounts = WarbandNexus.GetCollectionCountsFromAPI and WarbandNexus:GetCollectionCountsFromAPI()
        local collected = (apiCounts and apiCounts.toys and apiCounts.toys.collected) or 0
        local total = (apiCounts and apiCounts.toys and apiCounts.toys.total) or 0
        M.SetCollectionProgress(collected, total)
        local filtersOk = M.CollectionsSubTabBrowseFiltersUnchanged("toys")
        if sch and M.state._lastGroupedToyData and filtersOk then
            M.CollectionsSubTabTrace("DrawToysContent_path", { path = "populate_only", drawGen = drawGen })
            if M.state.toyListContainer then M.state.toyListContainer:Show() end
            if M.state.toyListScrollBarContainer then M.state.toyListScrollBarContainer:Show() end
            M.RecordCollectionsSubTabBrowseSnapshot("toys")
            M.PopulateToyList(sch, listW, M.state._lastGroupedToyData, M.state.collapsedHeadersToys, M.state.selectedToyID, onSelectToy, contentFrame, DrawToysContent, drawGen, function()
                if Factory.UpdateScrollBarVisibility and M.state.toyListScrollFrame then
                    Factory:UpdateScrollBarVisibility(M.state.toyListScrollFrame)
                end
                M.ReleaseCollectionsDrawBusy("Toys", drawGen)
            end)
            return
        end
        M.CollectionsSubTabTrace("DrawToysContent_path", { path = "full_repopulate", drawGen = drawGen })
        if M.state._toysDrawGen ~= drawGen or M.state.currentSubTab ~= "toys" then
            M.state._drawToysContentBusy = nil
            return
        end
        if not sch or not sch:GetParent() or not contentFrame or not contentFrame:IsVisible() then
            M.state._drawToysContentBusy = nil
            return
        end
        local grouped = M.GetFilteredToysGrouped(M.state.searchText or "", M.state.showCollected, M.state.showUncollected)
        M.RecordCollectionsSubTabBrowseSnapshot("toys")
        M.state._lastGroupedToyData = grouped
        M.PopulateToyList(sch, listW, grouped, M.state.collapsedHeadersToys, M.state.selectedToyID, onSelectToy, contentFrame, DrawToysContent, drawGen, function()
            if Factory.UpdateScrollBarVisibility and M.state.toyListScrollFrame then
                Factory:UpdateScrollBarVisibility(M.state.toyListScrollFrame)
            end
            M.ReleaseCollectionsDrawBusy("Toys", drawGen)
        end)
        return
    end
    M.state._drawToysContentBusy = nil
end

-- DrawAchievementsContent: list left, achievement detail panel right (parent/children, criteria).
function M.DrawAchievementsContent(contentFrame)
    M.CollectionsSubTabTrace("DrawAchievementsContent_enter", { busy = M.state._drawAchievementsContentBusy and true or false })
    if M.state._drawAchievementsContentBusy then
        -- Self-heal: a leaked busy flag (abort path that missed its release) would
        -- otherwise spin this retry forever; after ~1s force-clear and draw anyway.
        local now = GetTime()
        M.state._drawAchievementsBusyRetryStart = M.state._drawAchievementsBusyRetryStart or now
        if (now - M.state._drawAchievementsBusyRetryStart) < 1 then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if M.CollectionsDrawRetryAllowed(contentFrame, "achievements") then
                        M.DrawAchievementsContent(contentFrame)
                    else
                        M.state._drawAchievementsContentBusy = nil
                        M.state._drawAchievementsBusyRetryStart = nil
                    end
                end)
            else
                M.state._drawAchievementsContentBusy = nil
            end
            return
        end
        M.ClearCollectionsDrawBusyFlags()
    end
    M.state._drawAchievementsBusyRetryStart = nil
    M.state._drawAchievementsContentBusy = true
    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then
        cw = M.CollectionsFallbackContentWidth(parent)
    end
    if not ch or ch < 1 then
        ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400
    end

    local listContentWidth, listWidth, detailWidth, scrollBarColumnWidth = M.ComputeCollectionsListDetailWidths(cw)

    local headerBlockH, innerCh = M.ApplyCollectionsContentHeader(contentFrame, "achievements", ch)
    M.HideAllCollectionsResultFrames()
    if M.state.achievementListContainer then
        M.ReanchorCollectionsBrowseListHost(M.state.achievementListContainer, contentFrame, headerBlockH, innerCh, listContentWidth)
    end

    -- Achievements: list container | scrollbar column | detail (same pattern as Mounts/Pets/Toys)
    local achListContainer = M.state.achievementListContainer
    if not achListContainer then
        achListContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        achListContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        M.state.achievementListContainer = achListContainer
        local scrollFrame = Factory:CreateScrollFrame(achListContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", achListContainer, "BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        M.EnableStandardScrollWheel(scrollFrame)
        M.state.achievementListScrollFrame = scrollFrame
        local scrollChild = M.CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        M.state.achievementListScrollChild = scrollChild
        M.state.achievementListScrollBarContainer = M.EnsureListScrollBarContainer(
            nil, contentFrame, achListContainer, scrollBarColumnWidth, innerCh, SCROLLBAR_SIDE_GAP
        )
    end
    achListContainer = M.state.achievementListContainer
    achListContainer:SetSize(listContentWidth, innerCh)
    achListContainer:Show()
    -- No border around the list
    M.state.achievementListScrollBarContainer = M.EnsureListScrollBarContainer(
        M.state.achievementListScrollBarContainer,
        contentFrame,
        achListContainer,
        scrollBarColumnWidth,
        innerCh,
        SCROLLBAR_SIDE_GAP
    )
    M.state.achievementListScrollBarContainer:Show()
    local achScrollBar = M.state.achievementListScrollFrame and M.state.achievementListScrollFrame.ScrollBar
    if achScrollBar and M.state.achievementListScrollBarContainer then
        Factory:PositionScrollBarInContainer(achScrollBar, M.state.achievementListScrollBarContainer, CONTAINER_INSET)
        achScrollBar:Show()
        if achScrollBar.ScrollUpBtn then achScrollBar.ScrollUpBtn:Show() end
        if achScrollBar.ScrollDownBtn then achScrollBar.ScrollDownBtn:Show() end
    end
    M.state.achievementListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))

    -- RIGHT COLUMN: progress bar (top) + achievement detail panel (below)
    local rightCol = M.state.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, detailWidth), math.max(1, innerCh or 400), false)
        rightCol:Show()
        M.state.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", M.state.achievementListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    M.EnsureCollectionProgressBar(rightCol)
    local pr = M.state.collectionProgressFrame
    local gap = CONTENT_GAP or 4
    if pr then
        pr:SetParent(rightCol)
        pr:ClearAllPoints()
        pr:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        pr:SetPoint("TOPRIGHT", rightCol, "TOPRIGHT", 0, 0)
        pr:Show()
    end
    local detailTop = (pr and (pr:GetHeight() or PROGRESS_ROW_HEIGHT) + gap) or 0
    local detailH = math.max(1, innerCh - detailTop)

    if M.state.achievementDetailContainer then
        M.state.achievementDetailContainer:Show()
    end

    local function onSelectAchievement(ach)
        M.state.selectedAchievementID = ach and ach.id
        if M.state.achDetailEmptyOverlay then
            M.state.achDetailEmptyOverlay:SetShown(not (ach and ach.id))
        end
        if M.state.achievementDetailPanel then
            M.state.achievementDetailPanel:SetShown(ach and ach.id ~= nil)
            M.state.achievementDetailPanel:SetAchievement(ach)
        end
    end

    if not M.state.achievementDetailPanel then
        local detailContainer = Factory:CreateContainer(rightCol, detailWidth, detailH, false)
        detailContainer:ClearAllPoints()
        if pr then
            detailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            detailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        detailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        detailContainer:Show()
        M.state.achievementDetailContainer = detailContainer
        M.ApplyDetailAccentVisuals(detailContainer)
        local emptyOverlay = M.CreateDetailEmptyOverlay(detailContainer, "achievement")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(detailContainer:GetFrameLevel() + 5)
            M.state.achDetailEmptyOverlay = emptyOverlay
        end
        M.state.achievementDetailPanel = M.CreateAchievementDetailPanel(detailContainer, detailWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2), onSelectAchievement)
        M.state.achievementDetailPanel:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
    else
        if M.state.achievementDetailContainer then
            M.state.achievementDetailContainer:SetParent(rightCol)
            M.state.achievementDetailContainer:SetSize(detailWidth, detailH)
            M.state.achievementDetailContainer:ClearAllPoints()
            if pr then
                M.state.achievementDetailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
            else
                M.state.achievementDetailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
            end
            M.state.achievementDetailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        end
        M.ApplyDetailAccentVisuals(M.state.achievementDetailContainer)
        M.state.achievementDetailPanel:SetSize(detailWidth - (CONTAINER_INSET * 2), detailH - (CONTAINER_INSET * 2))
        if M.state.achievementDetailPanel._scrollBarContainer then
            M.state.achievementDetailPanel._scrollBarContainer = M.EnsureDetailScrollBarContainer(
                M.state.achievementDetailPanel._scrollBarContainer,
                M.state.achievementDetailPanel,
                SCROLLBAR_GAP,
                CONTAINER_INSET
            )
        end
        if M.state.achievementDetailPanel.scrollFrame and M.state.achievementDetailPanel._scrollBarContainer then
            M.state.achievementDetailPanel.scrollFrame:ClearAllPoints()
            M.state.achievementDetailPanel.scrollFrame:SetPoint("TOPLEFT", M.state.achievementDetailPanel, "TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
            M.state.achievementDetailPanel.scrollFrame:SetPoint("BOTTOMRIGHT", M.state.achievementDetailPanel._scrollBarContainer, "BOTTOMLEFT", -CONTAINER_INSET, 0)
            if M.state.achievementDetailPanel.scrollFrame.ScrollBar then
                Factory:PositionScrollBarInContainer(M.state.achievementDetailPanel.scrollFrame.ScrollBar, M.state.achievementDetailPanel._scrollBarContainer, CONTAINER_INSET)
            end
        end
        local achChild = M.state.achievementDetailPanel.scrollFrame and M.state.achievementDetailPanel.scrollFrame:GetScrollChild()
        if achChild then
            achChild:SetWidth((detailWidth - (CONTAINER_INSET * 2)) - (CONTAINER_INSET * 2) - SCROLLBAR_GAP)
        end
    end
    if not M.state.selectedAchievementID then
        if M.state.achDetailEmptyOverlay then M.state.achDetailEmptyOverlay:Show() end
        if M.state.achievementDetailPanel then M.state.achievementDetailPanel:Hide() end
    else
        if M.state.achDetailEmptyOverlay then M.state.achDetailEmptyOverlay:Hide() end
        if M.state.achievementDetailPanel then M.state.achievementDetailPanel:Show() end
    end

    local loadingState = ns.PlansLoadingState and ns.PlansLoadingState.achievement
    local collLoading = ns.CollectionLoadingState
    local achStoreEmpty = WarbandNexus.IsPlansBrowseCategoryStoreEmpty
        and WarbandNexus:IsPlansBrowseCategoryStoreEmpty("achievement")
    if achStoreEmpty then
        M.state._achGroupedCache = nil
        M.state._lastAchievementCategoryData = nil
        M.state._achFlatList = nil
        if ns.RequestPlansBrowseCollectionEnsure then
            ns.RequestPlansBrowseCollectionEnsure("achievement")
        end
    end
    -- Loading only when a scan/load is actually in progress; not when filters result in empty list (e.g. both Owned and Missing unchecked)
    local isLoading = (loadingState and loadingState.isLoading)
        or (collLoading and collLoading.isLoading and collLoading.currentCategory == "achievement")
        or achStoreEmpty

    if isLoading then
        M.CollectionsSubTabTrace("DrawAchievementsContent_path", { path = "loading" })
        M.SetCollectionProgress(nil, nil)
        if not M.state.loadingPanel then
            M.state.loadingPanel = M.GetOrCreateLoadingPanel(contentFrame)
        end
        M.state.loadingPanel:SetParent(contentFrame)
        M.state.loadingPanel:SetAllPoints(contentFrame)
        M.state.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local progress = (loadingState and loadingState.loadingProgress) or (collLoading and collLoading.loadingProgress) or 0
        local stage = (loadingState and loadingState.currentStage) or (collLoading and collLoading.currentStage) or ((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...")
        M.state.loadingPanel:ShowLoading((ns.L and ns.L["LOADING_ACHIEVEMENTS"]) or "Loading achievements...", progress, stage)
        if M.state.achievementListContainer then M.state.achievementListContainer:Hide() end
        if M.state.achievementListScrollBarContainer then M.state.achievementListScrollBarContainer:Hide() end
        if M.state.achievementDetailContainer then M.state.achievementDetailContainer:Hide() end
    else
        if M.state.loadingPanel then M.state.loadingPanel:Hide() end

        local allAchsForProgress = WarbandNexus.GetAllAchievementsData and WarbandNexus:GetAllAchievementsData() or {}
        local achTotal = allAchsForProgress._wnAchTotal or #allAchsForProgress
        local achCollected = allAchsForProgress._wnAchCollected
        if type(achCollected) ~= "number" then
            achCollected = 0
            for i = 1, achTotal do
                local e = allAchsForProgress[i]
                if e and (e.isCollected or e.completed or e.collected) then achCollected = achCollected + 1 end
            end
            allAchsForProgress._wnAchCollected = achCollected
        end
        M.SetCollectionProgress(achCollected, achTotal)

        M.state._achPopulateGen = (M.state._achPopulateGen or 0) + 1
        local popGen = M.state._achPopulateGen
        M.state._drawAchievementsBusyGen = popGen
        local listW = listContentWidth - (CONTAINER_INSET * 2)
        local searchSnap = M.state.searchText or ""
        local showCSnap = M.state.showCollected
        local showUSnap = M.state.showUncollected
        local selAchID = M.state.selectedAchievementID
        local sch = M.state.achievementListScrollChild
        local filtersOk = M.CollectionsSubTabBrowseFiltersUnchanged("achievements")

        if M.state.currentSubTab ~= "achievements" or M.state._achPopulateGen ~= popGen then
            M.state._drawAchievementsContentBusy = nil
            return
        end

        -- Tab switch back: list already populated and filters unchanged — refresh visible rows only (Mounts/Pets/Toys parity).
        if sch and M.state._achFlatList and M.state._lastAchievementCategoryData and filtersOk then
            M.CollectionsSubTabTrace("DrawAchievementsContent_path", { path = "fast_visible_only" })
            if M.state.achievementListContainer then M.state.achievementListContainer:Show() end
            if M.state.achievementListScrollBarContainer then M.state.achievementListScrollBarContainer:Show() end
            if M.state.achievementDetailContainer then M.state.achievementDetailContainer:Show() end
            if Factory.UpdateScrollBarVisibility and M.state.achievementListScrollFrame then
                Factory:UpdateScrollBarVisibility(M.state.achievementListScrollFrame)
            end
            if M.state._achListRefreshVisible then
                M.state._achListRefreshVisible()
            end
            M.state._drawAchievementsContentBusy = nil
            return
        end

        if M.state.achievementDetailContainer then M.state.achievementDetailContainer:Show() end

        M.CollectionsSubTabTrace("DrawAchievementsContent_path", { path = "full_repopulate", popGen = popGen })
        local categoryData, rootCategories = M.BuildGroupedAchievementData(searchSnap, showCSnap, showUSnap)
        M.state._lastAchievementCategoryData = categoryData
        M.state._lastAchievementRootCategories = rootCategories
        M.PopulateAchievementList(
            M.state.achievementListScrollChild,
            listW,
            categoryData,
            rootCategories,
            M.state.collapsedHeaders,
            selAchID,
            onSelectAchievement,
            contentFrame,
            DrawAchievementsContent,
            popGen,
            function()
                if M.state.currentSubTab ~= "achievements" or M.state._achPopulateGen ~= popGen then
                    M.ReleaseCollectionsDrawBusy("Achievements", popGen)
                    return
                end
                M.RecordCollectionsSubTabBrowseSnapshot("achievements")
                if selAchID then
                    local allAchs = WarbandNexus:GetAllAchievementsData()
                    for i = 1, #allAchs do
                        if allAchs[i].id == selAchID then
                            M.state.achievementDetailPanel:SetAchievement(allAchs[i])
                            break
                        end
                    end
                else
                    M.state.achievementDetailPanel:SetAchievement(nil)
                end
                if Factory.UpdateScrollBarVisibility and M.state.achievementListScrollFrame then
                    Factory:UpdateScrollBarVisibility(M.state.achievementListScrollFrame)
                end
                M.ReleaseCollectionsDrawBusy("Achievements", popGen)
            end
        )
        return
    end
    M.state._drawAchievementsContentBusy = nil
end
