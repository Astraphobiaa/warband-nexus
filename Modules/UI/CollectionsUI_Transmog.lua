--[[
    Warband Nexus - Collections tab (Transmog browse + player dress preview)
    Loaded via WarbandNexus.toc after CollectionsUI_Model.lua.
]]

local _, ns = ...
local M = ns.CollectionsUI
assert(M and M.state, "CollectionsUI_Shared.lua must load before this file")

local WarbandNexus = M.WarbandNexus
local FontManager = M.FontManager
local COLORS = M.COLORS
local ApplyVisuals = M.ApplyVisuals
local Factory = M.Factory
local SD = M.SD
local LAYOUT = M.LAYOUT
local SafeLower = M.SafeLower
local HideEmptyStateCard = M.HideEmptyStateCard
local CONTENT_INSET = M.CONTENT_INSET
local CONTAINER_INSET = M.CONTAINER_INSET
local TEXT_GAP = M.TEXT_GAP or (LAYOUT.AFTER_ELEMENT or 8)
local SCROLLBAR_GAP = M.SCROLLBAR_GAP
local SCROLLBAR_SIDE_GAP = M.SCROLLBAR_SIDE_GAP
local CONTENT_GAP = M.CONTENT_GAP
local PROGRESS_ROW_HEIGHT = M.PROGRESS_ROW_HEIGHT
local DETAIL_ICON_SIZE = M.DETAIL_ICON_SIZE
local DETAIL_SCROLLBAR_VERTICAL_INSET = M.DETAIL_SCROLLBAR_VERTICAL_INSET
local ROW_HEIGHT = M.ROW_HEIGHT
local ROW_STRIDE = M.ROW_STRIDE
local COLLAPSE_HEADER_HEIGHT_COLL = M.COLLAPSE_HEADER_HEIGHT_COLL
local PADDING = M.PADDING
local issecretvalue = issecretvalue
local format = string.format
local tinsert = table.insert
local wipe = table.wipe
local pcall = pcall
local pairs = pairs

local DEFAULT_ICON_TRANSMOG = "Interface\\Icons\\INV_Chest_Chain_05"
local TRANSMOG_PREVIEW_RACE_ID = 1
local TRANSMOG_PREVIEW_DRESS_GENDER = 0
local TRANSMOG_HUMAN_DISPLAY_FALLBACK = 42505

local TRANSMOG_SLOT_CAMERA = {
    head = { zoom = 0.68, ty = 0.20 },
    shoulder = { zoom = 0.82, ty = 0.12 },
    back = { zoom = 0.95, ty = 0.06 },
    chest = { zoom = 0.92, ty = 0.04 },
    shirt = { zoom = 0.92, ty = 0.02 },
    tabard = { zoom = 0.90, ty = 0.0 },
    wrist = { zoom = 0.88, ty = -0.02 },
    hands = { zoom = 0.86, ty = -0.04 },
    waist = { zoom = 0.94, ty = -0.06 },
    legs = { zoom = 1.02, ty = -0.12 },
    feet = { zoom = 1.08, ty = -0.20 },
    mainhand = { zoom = 0.90, ty = 0.0 },
    offhand = { zoom = 0.90, ty = 0.0 },
}

function M.SetTransmogIconTexture(tex, icon, itemID)
    if not tex then return end
    local fileID
    if type(icon) == "number" and icon > 0 and not (issecretvalue and issecretvalue(icon)) then
        fileID = icon
    elseif itemID and C_Item and C_Item.GetItemIconByID then
        local ok, id = pcall(C_Item.GetItemIconByID, itemID)
        if ok and type(id) == "number" and id > 0 then fileID = id end
    end
    if fileID then
        tex:SetTexture(fileID)
    elseif type(icon) == "string" and icon ~= "" then
        tex:SetTexture(icon)
    else
        tex:SetTexture(DEFAULT_ICON_TRANSMOG)
    end
end

function M.ResolveTransmogAppearanceLink(sourceID, itemID)
    if sourceID and C_TransmogCollection and C_TransmogCollection.GetAppearanceSourceInfo then
        local ok, info = pcall(C_TransmogCollection.GetAppearanceSourceInfo, sourceID)
        if ok and info and info.itemLink and info.itemLink ~= ""
            and not (issecretvalue and issecretvalue(info.itemLink)) then
            return info.itemLink
        end
    end
    if itemID and C_Item and C_Item.GetItemInfo then
        local ok, _, link = pcall(C_Item.GetItemInfo, itemID)
        if ok and link and not (issecretvalue and issecretvalue(link)) then
            return link
        end
    end
    return nil
end

function M.ApplyTransmogPreviewCamera(model, categoryKey)
    if not model then return end
    local cam = TRANSMOG_SLOT_CAMERA[categoryKey] or TRANSMOG_SLOT_CAMERA.head
    local baseZoom = 1.1 * (cam.zoom or 1.0)
    local userZoom = model._zoom or 1.0
    pcall(function()
        if model.UseModelCenterToTransform then
            model:UseModelCenterToTransform(true)
        end
        if model.SetPitch then
            model:SetPitch(0)
        end
        if model.SetCamDistanceScale then
            model:SetCamDistanceScale(baseZoom * userZoom)
        end
        if model.SetViewTranslation then
            model:SetViewTranslation(0, cam.ty or 0)
        end
        if model.SetPortraitZoom then
            model:SetPortraitZoom(0)
        end
    end)
end

local function TransmogCategoryHeaders()
    local cats = ns.GetTransmogCategories and ns.GetTransmogCategories() or {}
    local headers = {}
    for i = 1, #cats do
        local c = cats[i]
        headers[#headers + 1] = { key = c.key, label = c.name or c.key }
    end
    return headers
end

function M.ResolveTransmogPreviewDisplayID()
    if ns._wnTransmogHumanDisplayID then
        return ns._wnTransmogHumanDisplayID
    end
    if C_PlayerInfo and C_PlayerInfo.GetDisplayIDForPlayer then
        local ok, id = pcall(C_PlayerInfo.GetDisplayIDForPlayer, TRANSMOG_PREVIEW_RACE_ID, TRANSMOG_PREVIEW_DRESS_GENDER)
        if ok and type(id) == "number" and id > 0 and not (issecretvalue and issecretvalue(id)) then
            ns._wnTransmogHumanDisplayID = math.floor(id)
            return ns._wnTransmogHumanDisplayID
        end
    end
    ns._wnTransmogHumanDisplayID = TRANSMOG_HUMAN_DISPLAY_FALLBACK
    return ns._wnTransmogHumanDisplayID
end

function M.ApplyPlayerDressModel(model)
    if not model then return end
    pcall(function()
        if model.SetUnit then
            model:SetUnit(nil)
        end
        model:ClearModel()
        if model.SetUseTransmogSkin then model:SetUseTransmogSkin(true) end
        if model.SetUseTransmogChoices then model:SetUseTransmogChoices(true) end
        if model.SetObeyHideInTransmogFlag then model:SetObeyHideInTransmogFlag(true) end
        if model.SetUnit then
            model:SetUnit("player")
        end
        if model.Dress then
            model:Dress()
        end
        if model.RefreshUnit then
            model:RefreshUnit()
        end
        if model.ClearFog then
            model:ClearFog()
        end
        if model.SetSheathed then
            model:SetSheathed(true)
        end
        if model.SetAnimation then
            model:SetAnimation(0)
        end
        local rot = model._dragRot or model._facing or 0.4
        model._facing = rot
        if model.SetFacing then
            model:SetFacing(rot)
        end
        model._zoom = model._zoom or 0.85
        model:Show()
        M.ApplyTransmogPreviewCamera(model, model._previewCategoryKey or "head")
    end)
end

function M.ApplyNakedHumanMannequin(model)
    if not model then return end
    pcall(function()
        if model.SetUnit then
            model:SetUnit(nil)
        end
        model:ClearModel()
        if model.SetUseTransmogSkin then model:SetUseTransmogSkin(false) end
        if model.SetUseTransmogChoices then model:SetUseTransmogChoices(false) end
        if model.SetObeyHideInTransmogFlag then model:SetObeyHideInTransmogFlag(false) end
        local displayID = M.ResolveTransmogPreviewDisplayID()
        if displayID and model.SetDisplayInfo then
            model:SetDisplayInfo(displayID)
        end
        if model.Undress then
            model:Undress()
        end
        if model.SetSheathed then
            model:SetSheathed(false)
        end
        if model.SetAnimation then
            model:SetAnimation(0)
        end
        if model.SetFacing then
            model:SetFacing(0.4)
        end
        model._zoom = model._zoom or 1.0
        M.ApplyTransmogPreviewCamera(model, model._previewCategoryKey or "head")
    end)
end

function M.TryOnTransmogPreview(model, itemLink, itemID, sourceID, categoryKey)
    if not model then return end
    model._previewCategoryKey = categoryKey or "head"
    M.ApplyPlayerDressModel(model)
    local tryTarget = itemLink
    if (not tryTarget or tryTarget == "") then
        tryTarget = M.ResolveTransmogAppearanceLink(sourceID, itemID)
    end
    if tryTarget and not (issecretvalue and issecretvalue(tryTarget)) and model.TryOn then
        pcall(model.TryOn, model, tryTarget)
    elseif sourceID and model.TryOn then
        pcall(model.TryOn, model, sourceID)
    elseif itemID and model.TryOn then
        pcall(model.TryOn, model, itemID)
    end
    local function refreshPreview()
        if not model or not model:IsShown() then return end
        if model.RefreshUnit then
            pcall(model.RefreshUnit, model)
        end
        M.ApplyTransmogPreviewCamera(model, categoryKey or "head")
    end
    refreshPreview()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, refreshPreview)
    end
end

function M.CreateTransmogDressViewer(parent, width, height)
    local panel = Factory:CreateContainer(parent, width, height, false)
    panel:SetSize(width, height)
    if M.ApplyDetailAccentVisuals then
        M.ApplyDetailAccentVisuals(panel)
    end

    local viewport = Factory:CreateContainer(panel, math.max(1, width), math.max(1, height), false)
    viewport:SetAllPoints(panel)
    if viewport.SetClipsChildren then
        viewport:SetClipsChildren(true)
    end
    panel.modelViewport = viewport

    local model = CreateFrame("DressUpModel", nil, viewport)
    model:SetAllPoints(viewport)
    model:SetModelDrawLayer("ARTWORK")
    model:EnableMouse(false)
    model:EnableMouseWheel(false)
    model._zoom = 0.85
    model._dragRot = 0.4
    model._facing = 0.4
    panel.model = model

    local interaction = Factory:CreateContainer(viewport, math.max(1, width), math.max(1, height), false)
    interaction:SetAllPoints(viewport)
    interaction:SetFrameLevel(model:GetFrameLevel() + 20)
    interaction:EnableMouse(true)
    interaction:EnableMouseWheel(true)
    panel.interactionLayer = interaction

    local function interactionScale()
        local s = interaction:GetEffectiveScale()
        return (s and s > 0) and s or 1
    end

    interaction:SetScript("OnMouseDown", function(_, btn)
        if btn == "LeftButton" or btn == "RightButton" then
            model._dragX = GetCursorPosition() / interactionScale()
            model._dragRot = model._facing or model._dragRot or 0.4
            model._dragBtn = btn
        end
    end)
    interaction:SetScript("OnMouseUp", function(_, btn)
        if btn == model._dragBtn then
            model._dragX = nil
            model._dragBtn = nil
        end
    end)
    interaction:SetScript("OnUpdate", function()
        if not model._dragX or not model._dragBtn then return end
        if not IsMouseButtonDown(model._dragBtn) then
            model._dragX = nil
            model._dragBtn = nil
            return
        end
        local x = GetCursorPosition() / interactionScale()
        local dx = x - model._dragX
        model._dragX = x
        local rot = (model._dragRot or 0.4) - dx * 0.02
        model._dragRot = rot
        model._facing = rot
        if model.SetFacing then model:SetFacing(rot) end
    end)
    interaction:SetScript("OnMouseWheel", function(_, delta)
        local z = (model._zoom or 0.85) * ((delta > 0) and 0.92 or 1.08)
        if z < 0.5 then z = 0.5 elseif z > 2.0 then z = 2.0 end
        model._zoom = z
        M.ApplyTransmogPreviewCamera(model, model._previewCategoryKey or "head")
    end)

    model:SetScript("OnModelLoaded", function()
        if model.SetAnimation then
            pcall(model.SetAnimation, model, 0)
        end
        if model.ClearFog then
            pcall(model.ClearFog, model)
        end
        M.ApplyTransmogPreviewCamera(model, model._previewCategoryKey or "head")
    end)

    function panel:SetTransmogItem(itemLink, itemID, sourceID, categoryKey)
        self:Show()
        if self.model then
            self.model:Show()
        end
        M.TryOnTransmogPreview(self.model, itemLink, itemID, sourceID, categoryKey)
    end

    function panel:ClearTransmogItem()
        if self.model then
            M.ApplyPlayerDressModel(self.model)
        end
    end

    function panel:ShowEmpty()
        self:Hide()
    end

    return panel
end

function M.BuildGroupedTransmogData(flatBrowse, searchText, showCollected, showUncollected)
    local grouped = {}
    if not flatBrowse then return grouped end
    local query = SafeLower(searchText or "")
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    for i = 1, #flatBrowse do
        local row = flatBrowse[i]
        if row and row.visualID then
            local isCollected = (row.isCollected == true) or (row.collected == true)
            if (showC and isCollected) or (showU and not isCollected) then
                local name = row.name or ""
                if query == "" or (name ~= "" and not (issecretvalue and issecretvalue(name)) and SafeLower(name):find(query, 1, true)) then
                    local key = row.categoryKey or "head"
                    if not grouped[key] then grouped[key] = {} end
                    grouped[key][#grouped[key] + 1] = row
                end
            end
        end
    end
    for _, items in pairs(grouped) do
        table.sort(items, function(a, b)
            return SafeLower(a.name or "") < SafeLower(b.name or "")
        end)
    end
    return grouped
end

M.GetTransmogListCategories = TransmogCategoryHeaders

function M.GetTransmogCategoryIcon(key)
    local cats = ns.GetTransmogCategories and ns.GetTransmogCategories() or {}
    for i = 1, #cats do
        local c = cats[i]
        if c.key == key then
            return c.icon or DEFAULT_ICON_TRANSMOG
        end
    end
    return DEFAULT_ICON_TRANSMOG
end

local TRANSMOG_DETAIL_LAYOUT_VERSION = 2
local TRANSMOG_DETAIL_MODEL_SPLIT = 0.46

function M.ComputeTransmogDetailLayoutHeights(detailH)
    local innerH = math.max(1, detailH - (CONTENT_INSET * 2))
    local modelH = math.max(220, math.floor(innerH * TRANSMOG_DETAIL_MODEL_SPLIT))
    local textH = math.max(120, innerH - modelH - TEXT_GAP)
    return innerH, modelH, textH
end

function M.ResetTransmogDetailChromeIfStale()
    if M.state._transmogDetailLayoutVersion == TRANSMOG_DETAIL_LAYOUT_VERSION then return end
    M.state._transmogDetailLayoutVersion = TRANSMOG_DETAIL_LAYOUT_VERSION
    M.state.transmogDetailContainer = nil
    M.state.transmogModelContainer = nil
    M.state.transmogDressViewer = nil
    M.state.transmogDetailScrollBarContainer = nil
    M.state._transmogDetailScroll = nil
    M.state._transmogDetailScrollChild = nil
    M.state._transmogDetailHeaderRow = nil
    M.state._transmogDetailIcon = nil
    M.state._transmogDetailName = nil
    M.state._transmogDetailSlot = nil
    M.state._transmogDetailSource = nil
    M.state._transmogDetailAddContainer = nil
    M.state._transmogDetailAddBtn = nil
    M.state.transmogDetailEmptyOverlay = nil
end

function M.FormatTransmogDetailSources(tm)
    if not tm then return "" end
    local L = ns.L
    local unknown = (L and L["UNKNOWN_SOURCE"]) or "Unknown source"
    local sources = tm.sources
    if not sources or #sources == 0 then
        local src = tm.sourceText
        if (not src or src == "") and tm.sourceID and WarbandNexus and WarbandNexus.GetTransmogSourceText then
            src = WarbandNexus:GetTransmogSourceText(tm.sourceID)
        end
        return src or unknown
    end
    local lines = {}
    local header = (L and L["CREST_SOURCES_HEADER"]) or "Sources:"
    lines[1] = header
    for i = 1, #sources do
        local s = sources[i]
        local label = s.name
        if (not label or label == "") and s.itemID then
            label = format("Item %d", s.itemID)
        end
        if not label or label == "" then
            label = format("Source %d", s.sourceID or i)
        end
        local srcText = s.sourceText
        if (not srcText or srcText == "") and s.sourceID and WarbandNexus and WarbandNexus.GetTransmogSourceText then
            srcText = WarbandNexus:GetTransmogSourceText(s.sourceID)
            s.sourceText = srcText
        end
        lines[#lines + 1] = format("- %s: %s", label, srcText or unknown)
    end
    return table.concat(lines, "\n")
end

function M.FilterTransmogCategoryRows(rows, searchText, showCollected, showUncollected)
    local out = {}
    if not rows then return out end
    local query = SafeLower(searchText or "")
    local showC = (showCollected ~= false)
    local showU = (showUncollected ~= false)
    for i = 1, #rows do
        local row = rows[i]
        if row and row.visualID then
            local isCollected = (row.isCollected == true) or (row.collected == true)
            if (showC and isCollected) or (showU and not isCollected) then
                local name = row.name or ""
                if query == "" or (name ~= "" and not (issecretvalue and issecretvalue(name)) and SafeLower(name):find(query, 1, true)) then
                    out[#out + 1] = row
                end
            end
        end
    end
    table.sort(out, function(a, b)
        return SafeLower(a.name or "") < SafeLower(b.name or "")
    end)
    return out
end

function M.AdaptTransmogRowsForList(rows, categoryKey)
    local out = {}
    local dummyIcon = M.GetTransmogCategoryIcon and M.GetTransmogCategoryIcon(categoryKey) or DEFAULT_ICON_TRANSMOG
    for i = 1, #(rows or {}) do
        local tm = rows[i]
        out[i] = {
            id = tm.visualID,
            name = tm.name,
            icon = dummyIcon,
            isCollected = tm.isCollected,
            collected = tm.isCollected,
            description = tm.sourceText,
            sourceTypeName = tm.categoryName,
            source = tm.sourceText,
            itemID = tm.itemID,
            _transmogRow = tm,
        }
    end
    return out
end

local TRANSMOG_CATEGORY_BAR_H = 44

function M.EnsureTransmogCategoryBar(parent, width, activeKey, onSelect)
    local bar = M.state.transmogCategoryBar
    if not bar then
        bar = Factory:CreateContainer(parent, width, TRANSMOG_CATEGORY_BAR_H, false)
        bar.buttons = {}
        M.state.transmogCategoryBar = bar
        local cats = ns.GetTransmogCategories and ns.GetTransmogCategories() or {}
        local btnSize = 36
        local gap = 6
        local x = 0
        for i = 1, #cats do
            local cat = cats[i]
            local btn = Factory:CreateButton(bar, btnSize, btnSize)
            btn:SetPoint("TOPLEFT", bar, "TOPLEFT", x, 0)
            btn._categoryKey = cat.key
            local iconTex = btn:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(btnSize - 8, btnSize - 8)
            iconTex:SetPoint("CENTER")
            iconTex:SetTexture(cat.icon or DEFAULT_ICON_TRANSMOG)
            btn.iconTex = iconTex
            btn:SetScript("OnClick", function()
                if onSelect then onSelect(cat.key) end
            end)
            if GameTooltip then
                btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
                    GameTooltip:SetText(cat.name or cat.key or "", 1, 1, 1)
                    GameTooltip:Show()
                end)
                btn:SetScript("OnLeave", function()
                    GameTooltip:Hide()
                end)
            end
            bar.buttons[#bar.buttons + 1] = btn
            x = x + btnSize + gap
        end
        bar:SetWidth(math.max(width, x))
    end
    bar:SetParent(parent)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    bar:SetWidth(width)
    bar:Show()
    if bar.buttons then
        for i = 1, #bar.buttons do
            local btn = bar.buttons[i]
            local active = (btn._categoryKey == activeKey)
            if ApplyVisuals then
                if active then
                    ApplyVisuals(btn, COLORS.accent, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.85 })
                else
                    ApplyVisuals(btn, COLORS.surface, { COLORS.border[1], COLORS.border[2], COLORS.border[3], 0.6 })
                end
            end
        end
    end
    return bar
end

function M.AdaptTransmogGroupedForToyList(grouped)
    local out = {}
    if not grouped then return out end
    for key, items in pairs(grouped) do
        local adapted = {}
        for i = 1, #items do
            local tm = items[i]
            adapted[i] = {
                id = tm.visualID,
                name = tm.name,
                icon = tm.icon,
                isCollected = tm.isCollected,
                collected = tm.isCollected,
                description = tm.sourceText,
                sourceTypeName = tm.categoryName,
                source = tm.sourceText,
                itemID = tm.itemID,
                _transmogRow = tm,
            }
        end
        out[key] = adapted
    end
    return out
end

function M.TransmogBrowseContextUnchanged()
    return M.CollectionsSubTabBrowseFiltersUnchanged("transmog")
end

function M.DrawTransmogContent(contentFrame)
    if M.state._drawTransmogContentBusy then
        local now = GetTime()
        M.state._drawTransmogBusyRetryStart = M.state._drawTransmogBusyRetryStart or now
        if (now - M.state._drawTransmogBusyRetryStart) < 1 then
            if C_Timer and C_Timer.After then
                C_Timer.After(0, function()
                    if M.CollectionsDrawRetryAllowed(contentFrame, "transmog") then
                        M.DrawTransmogContent(contentFrame)
                    else
                        M.state._drawTransmogContentBusy = nil
                        M.ReleaseCollectionsDrawBusy("Transmog", M.state._drawTransmogBusyGen)
                    end
                end)
            end
            return
        end
        M.ClearCollectionsDrawBusyFlags()
    end
    M.state._drawTransmogBusyRetryStart = nil
    M.state._drawTransmogContentBusy = true
    M.state._transmogDrawGen = (M.state._transmogDrawGen or 0) + 1
    local drawGen = M.state._transmogDrawGen
    M.state._drawTransmogBusyGen = drawGen

    local parent = contentFrame:GetParent()
    local cw = contentFrame:GetWidth()
    local ch = contentFrame:GetHeight()
    if not cw or cw < 1 then cw = M.CollectionsFallbackContentWidth(parent) end
    if not ch or ch < 1 then ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400 end

    local listContentWidth, listWidth, detailWidth, scrollBarColumnWidth = M.ComputeCollectionsListDetailWidths(cw)
    local headerBlockH, innerCh = M.ApplyCollectionsContentHeader(contentFrame, "transmog", ch)
    M.HideAllCollectionsResultFrames()

    if M.state.transmogCategoryBar then
        M.state.transmogCategoryBar:Hide()
    end

    local listTop = headerBlockH
    local listInnerH = math.max(1, innerCh)

    if M.state.transmogListContainer then
        M.ReanchorCollectionsBrowseListHost(M.state.transmogListContainer, contentFrame, listTop, listInnerH, listContentWidth)
    end

    if not M.state.transmogListContainer then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, listInnerH, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -listTop)
        listContainer:Show()
        M.state.transmogListContainer = listContainer
        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        M.EnableStandardScrollWheel(scrollFrame)
        M.state.transmogListScrollFrame = scrollFrame
        M.state.transmogListScrollChild = M.CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        M.state.transmogListScrollBarContainer = M.EnsureListScrollBarContainer(nil, contentFrame, listContainer, scrollBarColumnWidth, listInnerH, SCROLLBAR_SIDE_GAP)
        local scrollBar = scrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, M.state.transmogListScrollBarContainer, CONTAINER_INSET)
        end
    else
        M.state.transmogListContainer:SetSize(listContentWidth, listInnerH)
        M.state.transmogListScrollBarContainer = M.EnsureListScrollBarContainer(
            M.state.transmogListScrollBarContainer, contentFrame, M.state.transmogListContainer,
            scrollBarColumnWidth, listInnerH, SCROLLBAR_SIDE_GAP)
        local scrollBar = M.state.transmogListScrollFrame and M.state.transmogListScrollFrame.ScrollBar
        if scrollBar then
            Factory:PositionScrollBarInContainer(scrollBar, M.state.transmogListScrollBarContainer, CONTAINER_INSET)
        end
    end
    if M.state.transmogListScrollChild then
        M.state.transmogListScrollChild:SetWidth(listContentWidth - (CONTAINER_INSET * 2))
    end

    local rightCol = M.state.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, detailWidth), math.max(1, innerCh or 400), false)
        rightCol:Show()
        M.state.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", M.state.transmogListScrollBarContainer, "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
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
    local _, modelH, textScrollH = M.ComputeTransmogDetailLayoutHeights(detailH)
    local detailInnerW = detailWidth - (CONTENT_INSET * 2)
    local detailScrollW = detailInnerW - SCROLLBAR_GAP

    M.ResetTransmogDetailChromeIfStale()

    if not M.state.transmogDetailContainer then
        local detailContainer = Factory:CreateContainer(rightCol, detailWidth, detailH, true)
        if pr then
            detailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            detailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        detailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        detailContainer:Show()
        M.state.transmogDetailContainer = detailContainer
        M.ApplyDetailAccentVisuals(detailContainer)
        local emptyOverlay = M.CreateDetailEmptyOverlay(detailContainer, "transmog")
        if emptyOverlay then
            emptyOverlay:SetFrameLevel(detailContainer:GetFrameLevel() + 5)
            M.state.transmogDetailEmptyOverlay = emptyOverlay
        end

        local modelContainer = Factory:CreateContainer(detailContainer, detailInnerW, modelH, true)
        modelContainer:SetPoint("TOPLEFT", detailContainer, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        modelContainer:SetPoint("TOPRIGHT", detailContainer, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        modelContainer:SetHeight(modelH)
        M.ApplyDetailAccentVisuals(modelContainer)
        M.state.transmogModelContainer = modelContainer

        local dressViewer = M.CreateTransmogDressViewer(modelContainer, detailInnerW, modelH)
        dressViewer:SetAllPoints(modelContainer)
        dressViewer:Hide()
        M.state.transmogDressViewer = dressViewer

        M.state.transmogDetailScrollBarContainer = M.EnsureDetailScrollBarContainer(
            M.state.transmogDetailScrollBarContainer,
            detailContainer,
            SCROLLBAR_GAP,
            CONTENT_INSET
        )
        M.state.transmogDetailScrollBarContainer:ClearAllPoints()
        M.state.transmogDetailScrollBarContainer:SetPoint("TOPRIGHT", modelContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
        M.state.transmogDetailScrollBarContainer:SetPoint("BOTTOMRIGHT", detailContainer, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)

        local scroll = Factory:CreateScrollFrame(detailContainer, "UIPanelScrollFrameTemplate", true)
        scroll:SetPoint("TOPLEFT", modelContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
        scroll:SetPoint("BOTTOMRIGHT", M.state.transmogDetailScrollBarContainer, "BOTTOMLEFT", -CONTENT_INSET, CONTENT_INSET)
        M.EnableStandardScrollWheel(scroll)
        M.state._transmogDetailScroll = scroll

        local scrollChild = M.CreateStandardScrollChild(scroll, detailScrollW, 1)
        M.state._transmogDetailScrollChild = scrollChild
        if scroll.ScrollBar then
            Factory:PositionScrollBarInContainer(scroll.ScrollBar, M.state.transmogDetailScrollBarContainer, CONTENT_INSET)
        end

        local TEXT_GAP_LINE = TEXT_GAP or 8
        local CDL = ns.CollectionsDetailHeaderLayout or {}
        local toyRightColH = (CDL.ACTION_SLOT_H or 28) + (CDL.TRY_GAP or 4) + (CDL.TRY_ROW_H or 18)
        local toyHdrH = math.max(ROW_HEIGHT + TEXT_GAP_LINE, DETAIL_ICON_SIZE + TEXT_GAP_LINE, toyRightColH)
        local toyHdrW = math.max(200, detailScrollW)
        local headerRow = Factory:CreateContainer(scrollChild, toyHdrW, toyHdrH, false)
        if not headerRow then
            headerRow = CreateFrame("Frame", nil, scrollChild)
        end
        headerRow:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
        headerRow:SetHeight(toyHdrH)
        M.state._transmogDetailHeaderRow = headerRow

        local iconBorder = Factory:CreateContainer(headerRow, DETAIL_ICON_SIZE, DETAIL_ICON_SIZE, true)
        iconBorder:SetPoint("TOPLEFT", headerRow, "TOPLEFT", 0, 0)
        if M.ApplyCollectionsIconBorder then M.ApplyCollectionsIconBorder(iconBorder, 0.7) end
        local iconTex = iconBorder:CreateTexture(nil, "OVERLAY")
        iconTex:SetAllPoints()
        iconTex:SetTexture(DEFAULT_ICON_TRANSMOG)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        M.state._transmogDetailIcon = iconTex

        local DETAIL_HEADER_GAP = 10
        local goldR, goldG, goldB = 1, 0.82, 0
        if ns.UI_GetSemanticGoldColor then goldR, goldG, goldB = ns.UI_GetSemanticGoldColor() end
        local nameFs = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
        nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
        nameFs:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
        nameFs:SetJustifyH("LEFT")
        nameFs:SetWordWrap(true)
        nameFs:SetNonSpaceWrap(true)
        nameFs:SetTextColor(goldR, goldG, goldB)
        M.state._transmogDetailName = nameFs

        local tmAddCol = Factory.CreateCollectionsDetailRightColumn and Factory:CreateCollectionsDetailRightColumn(headerRow, { withTryRow = false })
        local tmAddContainer = tmAddCol and tmAddCol.root
        local tmActionSlot = tmAddCol and tmAddCol.actionSlot
        if tmAddContainer then
            tmAddContainer:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
            tmAddContainer:Hide()
        end
        M.state._transmogDetailAddContainer = tmAddContainer
        if tmActionSlot then
            M.state._transmogDetailAddBtn = M.CreateCollectionsDetailPlanButton(tmActionSlot)
        end
        if nameFs and tmAddContainer then
            nameFs:ClearAllPoints()
            nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
            nameFs:SetPoint("TOPRIGHT", tmAddContainer, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
        end

        local slotLabel = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        slotLabel:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        slotLabel:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -TEXT_GAP_LINE)
        slotLabel:SetJustifyH("LEFT")
        slotLabel:SetWordWrap(true)
        ns.UI_SetTextColorRole(slotLabel, "Bright")
        M.state._transmogDetailSlot = slotLabel

        local sourceLabel = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        sourceLabel:SetPoint("TOPLEFT", slotLabel, "BOTTOMLEFT", 0, -TEXT_GAP_LINE)
        sourceLabel:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -CONTENT_INSET, 0)
        sourceLabel:SetJustifyH("LEFT")
        sourceLabel:SetWordWrap(true)
        sourceLabel:SetTextColor(goldR, goldG, goldB)
        M.state._transmogDetailSource = sourceLabel
    else
        M.state.transmogDetailContainer:SetParent(rightCol)
        M.state.transmogDetailContainer:SetSize(detailWidth, detailH)
        M.state.transmogDetailContainer:ClearAllPoints()
        if pr then
            M.state.transmogDetailContainer:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
        else
            M.state.transmogDetailContainer:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
        end
        M.state.transmogDetailContainer:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
        M.ApplyDetailAccentVisuals(M.state.transmogDetailContainer)
        if M.state.transmogModelContainer then
            M.state.transmogModelContainer:SetSize(detailInnerW, modelH)
            M.state.transmogModelContainer:ClearAllPoints()
            M.state.transmogModelContainer:SetPoint("TOPLEFT", M.state.transmogDetailContainer, "TOPLEFT", CONTENT_INSET, -CONTENT_INSET)
            M.state.transmogModelContainer:SetPoint("TOPRIGHT", M.state.transmogDetailContainer, "TOPRIGHT", -CONTENT_INSET, -CONTENT_INSET)
            M.state.transmogModelContainer:SetHeight(modelH)
        end
        if M.state.transmogDressViewer then
            M.state.transmogDressViewer:SetSize(detailInnerW, modelH)
            M.state.transmogDressViewer:SetAllPoints(M.state.transmogModelContainer or M.state.transmogDetailContainer)
        end
        M.state.transmogDetailScrollBarContainer = M.EnsureDetailScrollBarContainer(
            M.state.transmogDetailScrollBarContainer,
            M.state.transmogDetailContainer,
            SCROLLBAR_GAP,
            CONTENT_INSET
        )
        if M.state.transmogDetailScrollBarContainer and M.state.transmogModelContainer then
            M.state.transmogDetailScrollBarContainer:ClearAllPoints()
            M.state.transmogDetailScrollBarContainer:SetPoint("TOPRIGHT", M.state.transmogModelContainer, "BOTTOMRIGHT", 0, -TEXT_GAP)
            M.state.transmogDetailScrollBarContainer:SetPoint("BOTTOMRIGHT", M.state.transmogDetailContainer, "BOTTOMRIGHT", -CONTENT_INSET, CONTENT_INSET)
        end
        if M.state._transmogDetailScroll then
            M.state._transmogDetailScroll:ClearAllPoints()
            if M.state.transmogModelContainer then
                M.state._transmogDetailScroll:SetPoint("TOPLEFT", M.state.transmogModelContainer, "BOTTOMLEFT", 0, -TEXT_GAP)
            else
                M.state._transmogDetailScroll:SetPoint("TOPLEFT", M.state.transmogDetailContainer, "TOPLEFT", CONTENT_INSET, -(CONTENT_INSET + DETAIL_SCROLLBAR_VERTICAL_INSET))
            end
            M.state._transmogDetailScroll:SetPoint("BOTTOMRIGHT", M.state.transmogDetailScrollBarContainer, "BOTTOMLEFT", -CONTENT_INSET, CONTENT_INSET)
            if M.state._transmogDetailScroll.ScrollBar then
                Factory:PositionScrollBarInContainer(M.state._transmogDetailScroll.ScrollBar, M.state.transmogDetailScrollBarContainer, CONTENT_INSET)
            end
        end
        if M.state._transmogDetailScrollChild then
            M.state._transmogDetailScrollChild:SetWidth(detailScrollW)
        end
    end

    local function SyncTransmogDetailScrollHeight()
        local scrollChild = M.state._transmogDetailScrollChild
        local scroll = M.state._transmogDetailScroll
        if not scrollChild or not scroll then return end
        local contentH = CONTENT_INSET
        local headerRow = M.state._transmogDetailHeaderRow
        if headerRow then contentH = contentH + (headerRow:GetHeight() or 0) + TEXT_GAP end
        if M.state._transmogDetailSlot then
            contentH = contentH + (M.state._transmogDetailSlot:GetStringHeight() or 0) + TEXT_GAP
        end
        if M.state._transmogDetailSource then
            contentH = contentH + (M.state._transmogDetailSource:GetStringHeight() or 0) + CONTENT_INSET
        end
        scrollChild:SetHeight(math.max(textScrollH, contentH))
        if Factory.UpdateScrollBarVisibility then
            Factory:UpdateScrollBarVisibility(scroll)
        end
    end

    local function UpdateTransmogDetail(tm)
        if not tm or not tm.visualID then
            if M.state.transmogDetailEmptyOverlay then M.state.transmogDetailEmptyOverlay:Show() end
            if M.state.transmogModelContainer then M.state.transmogModelContainer:Hide() end
            if M.state.transmogDressViewer then M.state.transmogDressViewer:ShowEmpty() end
            if M.state._transmogDetailAddContainer then M.state._transmogDetailAddContainer:Hide() end
            return
        end
        if M.state.transmogDetailEmptyOverlay then M.state.transmogDetailEmptyOverlay:Hide() end
        if M.state.transmogModelContainer then M.state.transmogModelContainer:Show() end

        local function paintDetail()
            local displayName = tm.name or tostring(tm.visualID)
            local isCollected = (tm.isCollected == true) or (tm.collected == true)
            if M.state._transmogDetailIcon then
                local catIcon = M.GetTransmogCategoryIcon(tm.categoryKey)
                M.SetTransmogIconTexture(M.state._transmogDetailIcon, catIcon, tm.itemID)
            end
            if M.state._transmogDetailName then
                M.state._transmogDetailName:SetText(displayName)
            end
            if M.state._transmogDetailAddContainer then
                if isCollected then
                    M.state._transmogDetailAddContainer:Hide()
                else
                    M.state._transmogDetailAddContainer:Show()
                    local addBtn = M.state._transmogDetailAddBtn
                    if addBtn and WarbandNexus then
                        local planKey = tm.sourceID
                        local planned = WarbandNexus.IsItemPlanned and WarbandNexus:IsItemPlanned("transmog", planKey)
                        M.RefreshCollectionsDetailPlanButton(addBtn, isCollected, planned, function()
                            if WarbandNexus and WarbandNexus.AddPlan then
                                WarbandNexus:AddPlan({
                                    type = "transmog",
                                    sourceID = tm.sourceID,
                                    itemID = tm.itemID,
                                    name = tm.name,
                                    icon = M.GetTransmogCategoryIcon(tm.categoryKey),
                                    source = tm.categoryName or "",
                                })
                            end
                        end)
                    end
                end
            end
            if M.state._transmogDetailSlot then
                local slotName = tm.categoryName or tm.categoryKey or ""
                local slotTitle = (ns.L and ns.L["EQUIPMENT"]) or "Equipment"
                M.state._transmogDetailSlot:SetText(slotTitle .. ": " .. slotName)
            end
            if M.state._transmogDetailSource then
                M.state._transmogDetailSource:SetText(M.FormatTransmogDetailSources(tm))
            end
            if not tm.link or tm.link == "" then
                tm.link = M.ResolveTransmogAppearanceLink(tm.sourceID, tm.itemID)
            end
            if M.state.transmogDressViewer then
                M.state.transmogDressViewer:SetTransmogItem(tm.link, tm.itemID, tm.sourceID, tm.categoryKey)
            end
            SyncTransmogDetailScrollHeight()
        end

        if tm._namePending and tm.sourceID and WarbandNexus and WarbandNexus.LoadTransmogItemAsync then
            WarbandNexus:LoadTransmogItemAsync(tm.sourceID, function(itemData)
                if not itemData or M.state.selectedTransmogVisualID ~= tm.visualID then return end
                if itemData.name then tm.name = itemData.name end
                if itemData.link then tm.link = itemData.link end
                tm._namePending = nil
                paintDetail()
                if M.state._transmogListRefreshVisible then
                    M.state._transmogListRefreshVisible()
                end
            end)
        end

        paintDetail()
    end

    local function onSelectTransmogRow(visualID)
        local tm = M.state._transmogRowByVisualID and M.state._transmogRowByVisualID[visualID]
        M.state.selectedTransmogVisualID = visualID
        M.state.selectedTransmogSourceID = nil
        UpdateTransmogDetail(tm)
    end

    local sch = M.state.transmogListScrollChild
    local listW = listContentWidth - (CONTAINER_INSET * 2)

    local function showTransmogChrome()
        if M.state.transmogListContainer then M.state.transmogListContainer:Show() end
        if M.state.transmogListScrollBarContainer then M.state.transmogListScrollBarContainer:Show() end
        if M.state.transmogDetailContainer then M.state.transmogDetailContainer:Show() end
        if M.state.collectionRightColumn then M.state.collectionRightColumn:Show() end
        if not M.state.selectedTransmogVisualID then
            if M.state.transmogDetailEmptyOverlay then M.state.transmogDetailEmptyOverlay:Show() end
        else
            if M.state.transmogDetailEmptyOverlay then M.state.transmogDetailEmptyOverlay:Hide() end
        end
    end

    local function finishPopulate(rows, isPartial)
        if drawGen ~= M.state._transmogDrawGen then return end
        rows = rows or {}
        M.state._transmogRowByVisualID = {}
        local collected, total = 0, #rows
        for i = 1, total do
            local row = rows[i]
            if row and row.visualID then
                M.state._transmogRowByVisualID[row.visualID] = row
                if row.isCollected then collected = collected + 1 end
            end
        end
        M.SetCollectionProgress(collected, math.max(total, 1))
        M.state._cachedTransmogBrowse = rows
        local grouped = M.BuildGroupedTransmogData(rows, M.state.searchText, M.state.showCollected, M.state.showUncollected)
        M.state._lastGroupedTransmogData = grouped
        local groupedForList = M.AdaptTransmogGroupedForToyList(grouped)
        if not isPartial and M.state.loadingPanel then M.state.loadingPanel:Hide() end
        showTransmogChrome()
        if not sch or not sch:GetParent() or not contentFrame then
            M.state._drawTransmogContentBusy = nil
            M.ReleaseCollectionsDrawBusy("Transmog", drawGen)
            return
        end
        M.state.transmogListCollapsedHeaders = M.state.transmogListCollapsedHeaders or {}
        M.PopulateTransmogFlatList(sch, listW, groupedForList, M.state.transmogListCollapsedHeaders, M.state.selectedTransmogVisualID, onSelectTransmogRow, contentFrame, M.DrawTransmogContent, drawGen, function()
            if Factory.UpdateScrollBarVisibility and M.state.transmogListScrollFrame then
                Factory:UpdateScrollBarVisibility(M.state.transmogListScrollFrame)
            end
            if not isPartial then
                M.RecordCollectionsSubTabBrowseSnapshot("transmog")
            end
            M.state._drawTransmogContentBusy = nil
            M.ReleaseCollectionsDrawBusy("Transmog", drawGen)
        end)
    end

    if sch and M.state._transmogFlatList and M.FlatListHasDataRows(M.state._transmogFlatList)
        and M.TransmogBrowseContextUnchanged() then
        showTransmogChrome()
        if M.state._transmogListRefreshVisible then
            M.state._transmogListRefreshVisible()
        end
        if Factory.UpdateScrollBarVisibility and M.state.transmogListScrollFrame then
            Factory:UpdateScrollBarVisibility(M.state.transmogListScrollFrame)
        end
        if M.state.selectedTransmogVisualID then
            local tm = M.state._transmogRowByVisualID and M.state._transmogRowByVisualID[M.state.selectedTransmogVisualID]
            if tm then UpdateTransmogDetail(tm) end
        end
        M.state._drawTransmogContentBusy = nil
        return
    end

    if not M.state.loadingPanel and contentFrame then
        M.state.loadingPanel = M.GetOrCreateLoadingPanel(contentFrame)
    end
    if M.state.loadingPanel then
        M.state.loadingPanel:SetParent(contentFrame)
        M.state.loadingPanel:SetAllPoints(contentFrame)
        M.state.loadingPanel:SetFrameLevel(contentFrame:GetFrameLevel() + 20)
        local msg = (ns.L and ns.L["LOADING_TRANSMOG"]) or "Loading transmog..."
        M.state.loadingPanel:ShowLoading(msg, 0, msg)
    end

    if WarbandNexus and WarbandNexus.LoadTransmogBrowseData then
        WarbandNexus:LoadTransmogBrowseData(function(rows)
            if drawGen ~= M.state._transmogDrawGen then return end
            finishPopulate(rows or {}, false)
        end, function(done, total, stage)
            if drawGen ~= M.state._transmogDrawGen then return end
            if M.state.loadingPanel and M.state.loadingPanel.ShowLoading then
                local pct = (total and total > 0) and (done / total) or 0
                local msg = (ns.L and ns.L["LOADING_TRANSMOG"]) or "Loading transmog..."
                M.state.loadingPanel:ShowLoading(msg, pct, stage or msg)
            end
        end, {
            showCollected = M.state.showCollected,
            showUncollected = M.state.showUncollected,
            partialCallback = function(rows)
                if drawGen ~= M.state._transmogDrawGen then return end
                finishPopulate(rows or {}, true)
            end,
        })
    else
        finishPopulate({}, false)
    end
end
