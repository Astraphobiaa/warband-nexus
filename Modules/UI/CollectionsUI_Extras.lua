--[[
    Warband Nexus - Collections tab (Illusions, Titles)
    Loaded via WarbandNexus.toc after CollectionsUI_Draw.lua.

    Both sub-tabs reuse the sectioned list pipeline (CollectionsUI_Lists PopulateIllusionList /
    PopulateTitleList) and the store queries in CollectionService_Queries; this file only owns the
    browse grouping, the list/detail layout and the illusion weapon preview.
]]

local _, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local M = ns.CollectionsUI
assert(M and M.state, "CollectionsUI_Shared.lua must load before this file")

local WarbandNexus = M.WarbandNexus
local FontManager = M.FontManager
local issecretvalue = M.issecretvalue
local SafeLower = M.SafeLower
local COLORS = M.COLORS
local ApplyVisuals = M.ApplyVisuals
local SD = M.SD
local Factory = M.Factory
local DETAIL_ICON_SIZE = M.DETAIL_ICON_SIZE
local CONTENT_INSET = M.CONTENT_INSET
local CONTAINER_INSET = M.CONTAINER_INSET
local TEXT_GAP = M.TEXT_GAP
local PROGRESS_ROW_HEIGHT = M.PROGRESS_ROW_HEIGHT
local SCROLLBAR_SIDE_GAP = M.SCROLLBAR_SIDE_GAP
local CONTENT_GAP = M.CONTENT_GAP
local pairs = pairs
local tsort = table.sort

-- Browse fetch cap: queries walk the store with pairs(); a low cap would return an arbitrary subset.
local BROWSE_FETCH_LIMIT = 99999
local DETAIL_HEADER_GAP = 10
-- WardrobeItemsModelTemplate is 78x104 (live Blizzard_Wardrobe.xml, 2026-11-04): the weapon UI cameras
-- from GetAppearanceCameraIDBySource are authored for that aspect.
local ILLUSION_PREVIEW_ASPECT = 78 / 104
local DEFAULT_ICON_ILLUSION = "Interface\\Icons\\INV_Enchant_Disenchant"
local DEFAULT_ICON_TITLE = "Interface\\Icons\\INV_Scroll_11"

-- Titles: achievement-awarded (matched by reward text in CollectionService_Queries) vs everything else.
M.TITLE_LIST_CATEGORIES = {
    { key = "achievement", label = (ns.L and ns.L["SOURCE_TYPE_ACHIEVEMENT"]) or "Achievement" },
    { key = "unknown", label = (ns.L and ns.L["SOURCE_OTHER"]) or "Other" },
}

-- BROWSE DATA

--- Illusion source text (GetIllusionStrings) -> toy source category key. Earliest label in the text wins,
--- the same rule as the To-Do source parser; Blizzard source text opens with its type label.
local function ClassifyIllusionSource(sourceText)
    if issecretvalue and issecretvalue(sourceText) then return "unknown" end
    if type(sourceText) ~= "string" or sourceText == "" then return "unknown" end
    local cats = SD.TOY_SOURCE_CATEGORIES
    local bestKey, bestPos = nil, nil
    for i = 1, #cats do
        local cat = cats[i]
        local label = cat.label
        if cat.key ~= "unknown" and type(label) == "string" and label ~= "" then
            local pos = sourceText:find(label, 1, true)
            if pos and (not bestPos or pos < bestPos) then
                bestPos, bestKey = pos, cat.key
            end
        end
    end
    return bestKey or "unknown"
end

local function SortEntitiesByName(a, b)
    return SafeLower(a.name or "") < SafeLower(b.name or "")
end

local function CollectBrowseEntities(collectedMethod, uncollectedMethod, searchText, showCollected, showUncollected)
    local out = {}
    local WN = WarbandNexus
    if showCollected ~= false and WN[collectedMethod] then
        local rows = WN[collectedMethod](WN, searchText, BROWSE_FETCH_LIMIT) or {}
        for i = 1, #rows do out[#out + 1] = rows[i] end
    end
    if showUncollected ~= false and WN[uncollectedMethod] then
        local rows = WN[uncollectedMethod](WN, searchText, BROWSE_FETCH_LIMIT) or {}
        for i = 1, #rows do out[#out + 1] = rows[i] end
    end
    return out
end

function M.GetFilteredIllusionsGrouped(searchText, showCollected, showUncollected)
    local list = CollectBrowseEntities("GetCollectedIllusions", "GetUncollectedIllusions", searchText, showCollected, showUncollected)
    local grouped = {}
    for i = 1, #list do
        local e = list[i]
        local key = ClassifyIllusionSource(e.source)
        local g = grouped[key]
        if not g then g = {}; grouped[key] = g end
        g[#g + 1] = e
    end
    for _, g in pairs(grouped) do tsort(g, SortEntitiesByName) end
    return grouped
end

function M.GetFilteredTitlesGrouped(searchText, showCollected, showUncollected)
    local list = CollectBrowseEntities("GetCollectedTitles", "GetUncollectedTitles", searchText, showCollected, showUncollected)
    local grouped = {}
    for i = 1, #list do
        local e = list[i]
        local key = e.sourceAchievement and "achievement" or "unknown"
        local g = grouped[key]
        if not g then g = {}; grouped[key] = g end
        g[#g + 1] = e
    end
    for _, g in pairs(grouped) do tsort(g, SortEntitiesByName) end
    return grouped
end

--- Collected / total for the progress bar (whole store, no search or Owned/Missing filter).
local function CountEntities(collectedMethod, uncollectedMethod)
    local WN = WarbandNexus
    local c = WN[collectedMethod] and #(WN[collectedMethod](WN, "", BROWSE_FETCH_LIMIT) or {}) or 0
    local u = WN[uncollectedMethod] and #(WN[uncollectedMethod](WN, "", BROWSE_FETCH_LIMIT) or {}) or 0
    return c, c + u
end

-- ILLUSION PREVIEW (same pipeline as WardrobeItemsCollectionMixin:UpdateItems for enchants)

--- Fallback weapon + its UI camera + illusion visual. APIs (generated docs, live 2026-11-04):
--- C_TransmogCollection.GetIllusionInfo(illusionID).visualID, GetFallbackWeaponAppearance(),
--- GetAppearanceSourceInfo(id).itemAppearanceID/itemSubclass, GetAppearanceCameraIDBySource(id);
--- CharacterModelBase:SetItemAppearance(itemAppearanceID, itemVisualID, itemSubclass);
--- Model_ApplyUICamera (SharedXML Mainline/ModelFrames.lua).
local function ApplyIllusionPreview(model, illusionID)
    if not model then return false end
    model:ClearModel()
    model._wnCameraID = nil
    if not illusionID or not C_TransmogCollection then return false end
    local okInfo, info = pcall(C_TransmogCollection.GetIllusionInfo, illusionID)
    local visualID = okInfo and type(info) == "table" and info.visualID or nil
    if issecretvalue and issecretvalue(visualID) then visualID = nil end
    if type(visualID) ~= "number" then return false end
    local okW, weaponSourceID = pcall(C_TransmogCollection.GetFallbackWeaponAppearance)
    if not okW or type(weaponSourceID) ~= "number" then return false end
    local okS, srcInfo = pcall(C_TransmogCollection.GetAppearanceSourceInfo, weaponSourceID)
    if not okS or type(srcInfo) ~= "table" or type(srcInfo.itemAppearanceID) ~= "number" then return false end
    if not pcall(model.SetItemAppearance, model, srcInfo.itemAppearanceID, visualID, srcInfo.itemSubclass) then
        return false
    end
    local okC, cameraID = pcall(C_TransmogCollection.GetAppearanceCameraIDBySource, weaponSourceID)
    if okC and type(cameraID) == "number" and cameraID > 0 and Model_ApplyUICamera then
        model._wnCameraID = cameraID
        pcall(Model_ApplyUICamera, model, cameraID)
    end
    return true
end

local function LayoutIllusionViewport(panel)
    local slot, viewport = panel._previewSlot, panel._previewViewport
    if not slot or not viewport then return end
    local sw, sh = slot:GetWidth(), slot:GetHeight()
    if not sw or not sh or sw < 2 or sh < 2 then return end
    local vw, vh = sw, sw / ILLUSION_PREVIEW_ASPECT
    if vh > sh then vh = sh; vw = sh * ILLUSION_PREVIEW_ASPECT end
    local padX, padY = math.max(0, (sw - vw) * 0.5), math.max(0, (sh - vh) * 0.5)
    viewport:ClearAllPoints()
    viewport:SetPoint("TOPLEFT", slot, "TOPLEFT", padX, -padY)
    viewport:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -padX, padY)
    local model = panel._previewModel
    if model and model._wnCameraID and Model_ApplyUICamera then
        if model.RefreshCamera then pcall(model.RefreshCamera, model) end
        pcall(Model_ApplyUICamera, model, model._wnCameraID)
    end
end

-- DETAIL PANEL

local function BuildDetailPanel(rightCol, width, height, typeKey, withPreview)
    local panel = Factory:CreateContainer(rightCol, width, height, true)
    M.ApplyDetailAccentVisuals(panel)
    local emptyOverlay = M.CreateDetailEmptyOverlay(panel, typeKey)
    if emptyOverlay then
        emptyOverlay:SetFrameLevel(panel:GetFrameLevel() + 5)
        panel._emptyOverlay = emptyOverlay
    end

    local body = Factory:CreateContainer(panel, width, height, false)
    body:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTAINER_INSET + CONTENT_INSET, -(CONTAINER_INSET + CONTENT_INSET))
    body:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(CONTAINER_INSET + CONTENT_INSET), CONTAINER_INSET + CONTENT_INSET)
    panel._body = body

    local CDL = ns.CollectionsDetailHeaderLayout or {}
    local hdrH = math.max(DETAIL_ICON_SIZE, CDL.ACTION_SLOT_H or 28)
    local headerRow = Factory:CreateContainer(body, width, hdrH, false)
    headerRow:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
    headerRow:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, 0)
    headerRow:SetHeight(hdrH)

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
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    panel._icon = iconTex

    local addCol = Factory.CreateCollectionsDetailRightColumn and Factory:CreateCollectionsDetailRightColumn(headerRow, { withTryRow = false })
    local addRoot = addCol and addCol.root
    if addRoot then
        addRoot:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
    end
    -- No verified Wowhead URL scheme for illusion sourceIDs / title mask IDs: hide the link button.
    if addCol and addCol.wowheadBtn then addCol.wowheadBtn:Hide() end
    panel._addRoot = addRoot
    panel._addBtn = addCol and addCol.actionSlot and M.CreateCollectionsDetailPlanButton(addCol.actionSlot)

    local nameFs = FontManager:CreateFontString(headerRow, "header", "OVERLAY")
    nameFs:SetPoint("TOPLEFT", iconBorder, "TOPRIGHT", DETAIL_HEADER_GAP, 0)
    if addRoot then
        nameFs:SetPoint("TOPRIGHT", addRoot, "TOPLEFT", -DETAIL_HEADER_GAP, 0)
    else
        nameFs:SetPoint("TOPRIGHT", headerRow, "TOPRIGHT", 0, 0)
    end
    nameFs:SetJustifyH("LEFT")
    nameFs:SetWordWrap(true)
    panel._name = nameFs

    local sourceFs = FontManager:CreateFontString(body, "body", "OVERLAY")
    sourceFs:SetPoint("TOPLEFT", headerRow, "BOTTOMLEFT", 0, -(TEXT_GAP or 8))
    sourceFs:SetPoint("TOPRIGHT", headerRow, "BOTTOMRIGHT", 0, -(TEXT_GAP or 8))
    sourceFs:SetJustifyH("LEFT")
    sourceFs:SetWordWrap(true)
    panel._source = sourceFs

    if withPreview then
        -- Full-bleed stage behind the header / source text (same layout as the mount and pet viewer).
        local slot = Factory:CreateContainer(panel, width, height, false)
        slot:SetAllPoints(panel)
        slot:SetFrameLevel(panel:GetFrameLevel() + 1)
        if ns.UI_ApplyBorderlessSurface and M.ResolveCollectionsSurface then
            ns.UI_ApplyBorderlessSurface(slot, M.ResolveCollectionsSurface("viewport"))
        end
        body:SetFrameLevel(slot:GetFrameLevel() + 10)
        panel._previewSlot = slot
        local viewport = Factory:CreateContainer(slot, 1, 1, false)
        if viewport.SetClipsChildren then viewport:SetClipsChildren(true) end
        if ns.UI_ApplyBorderlessSurface and M.ResolveCollectionsSurface then
            ns.UI_ApplyBorderlessSurface(viewport, M.ResolveCollectionsSurface("viewport"))
        end
        panel._previewViewport = viewport
        -- Model widget (no Factory equivalent; same precedent as CollectionsUI_Model PlayerModel).
        local model = CreateFrame("DressUpModel", nil, viewport)
        model:SetAllPoints(viewport)
        model:SetFrameLevel(viewport:GetFrameLevel() + 1)
        model:SetScript("OnModelLoaded", function(self)
            if self._wnCameraID and Model_ApplyUICamera then
                pcall(Model_ApplyUICamera, self, self._wnCameraID)
            end
        end)
        panel._previewModel = model
        slot:SetScript("OnSizeChanged", function() LayoutIllusionViewport(panel) end)
    end
    return panel
end

local function GoldHex()
    local gold = COLORS.gold or { 1, 0.82, 0 }
    return (M.CollectionsGoldHex and M.CollectionsGoldHex())
        or (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex())
        or ns.UI_RGBToHex(gold[1], gold[2], gold[3])
end

local function PaintDetail(panel, entity, spec)
    if panel._emptyOverlay then panel._emptyOverlay:SetShown(entity == nil) end
    panel._body:SetShown(entity ~= nil)
    if not entity then
        if panel._previewModel then panel._previewModel:ClearModel() end
        return
    end
    local collected = (entity.isCollected == true) or (entity.collected == true)
    panel._icon:SetTexture(entity.icon or spec.defaultIcon)
    panel._name:SetText(GoldHex() .. (entity.name or "") .. "|r")

    local brightHex = M.CollectionsBrightHex and M.CollectionsBrightHex() or "|cffeeeeee"
    -- Secret check first on each candidate (test_secret_check_order).
    local srcText = nil
    local candidates = { entity.source, entity.rewardText }
    for ci = 1, #candidates do
        local c = candidates[ci]
        if not (issecretvalue and issecretvalue(c)) and type(c) == "string" and c ~= "" then
            srcText = c
            break
        end
    end
    if entity.sourceAchievementName and srcText == entity.sourceAchievementName then
        srcText = ((ns.L and ns.L["ACHIEVEMENT"]) or "Achievement") .. ": " .. srcText
    end
    -- Titles without an awarding achievement (PvP ranks, raids...): label them as a player title.
    srcText = srcText or (spec.planType == "title" and ((ns.L and ns.L["FALLBACK_PLAYER_TITLE"]) or "Player Title"))
        or (ns.L and ns.L["SOURCE_UNKNOWN"]) or "Unknown"
    local sourceTitle = (ns.L and ns.L["SOURCE"]) or "Source"
    panel._source:SetText(GoldHex() .. sourceTitle .. ":|r " .. brightHex .. srcText .. "|r")

    if panel._addBtn then
        local WN = WarbandNexus
        local planned = WN and spec.isPlanned(WN, entity.id) or false
        M.RefreshCollectionsDetailPlanButton(panel._addBtn, collected, planned, function()
            if WN and WN.AddPlan then
                local plan = { type = spec.planType, name = entity.name, icon = entity.icon, source = entity.source, rewardText = entity.rewardText }
                plan[spec.planField] = entity.id
                WN:AddPlan(plan)
            end
        end, { type = spec.planType, field = spec.planField, id = entity.id })
    end
    if panel._previewModel then
        ApplyIllusionPreview(panel._previewModel, entity.id)
        LayoutIllusionViewport(panel)
    end
end

local function FindEntity(grouped, id)
    if not id or not grouped then return nil end
    for _, list in pairs(grouped) do
        for i = 1, #list do
            if list[i].id == id then return list[i] end
        end
    end
    return nil
end

-- SUB-TAB DRAW

local function DrawSimpleCollectionSubTab(contentFrame, spec)
    local st = M.state
    -- No busy gate: PopulateSectionedList retries a busy pump itself and aborts superseded gens.
    st[spec.genKey] = (st[spec.genKey] or 0) + 1
    local drawGen = st[spec.genKey]

    local parent = contentFrame:GetParent()
    local cw, ch = contentFrame:GetWidth(), contentFrame:GetHeight()
    if not cw or cw < 1 then cw = M.CollectionsFallbackContentWidth(parent) end
    if not ch or ch < 1 then ch = (parent and parent:GetHeight() and (parent:GetHeight() - 200)) or 400 end

    local listContentWidth, _, detailWidth, scrollBarColumnWidth = M.ComputeCollectionsListDetailWidths(cw)
    local headerBlockH, innerCh = M.ApplyCollectionsContentHeader(contentFrame, spec.sub, ch)
    M.HideAllCollectionsResultFrames()

    local p = spec.prefix
    local kList, kScroll, kChild, kBar = p .. "ListContainer", p .. "ListScrollFrame", p .. "ListScrollChild", p .. "ListScrollBarContainer"
    if not st[kList] then
        local listContainer = Factory:CreateContainer(contentFrame, listContentWidth, innerCh, false)
        listContainer:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
        st[kList] = listContainer
        local scrollFrame = Factory:CreateScrollFrame(listContainer, "UIPanelScrollFrameTemplate", true)
        scrollFrame:SetPoint("TOPLEFT", CONTAINER_INSET, -CONTAINER_INSET)
        scrollFrame:SetPoint("BOTTOMRIGHT", -CONTAINER_INSET, CONTAINER_INSET)
        M.EnableStandardScrollWheel(scrollFrame)
        st[kScroll] = scrollFrame
        st[kChild] = M.CreateStandardScrollChild(scrollFrame, listContentWidth - (CONTAINER_INSET * 2))
        st[kBar] = M.EnsureListScrollBarContainer(nil, contentFrame, scrollFrame, scrollBarColumnWidth, SCROLLBAR_SIDE_GAP)
    else
        M.ReanchorCollectionsBrowseListHost(st[kList], contentFrame, headerBlockH, innerCh, listContentWidth)
        st[kList]:SetSize(listContentWidth, innerCh)
        st[kBar] = M.EnsureListScrollBarContainer(st[kBar], contentFrame, st[kScroll], scrollBarColumnWidth, SCROLLBAR_SIDE_GAP)
    end
    st[kChild]:SetWidth(listContentWidth - (CONTAINER_INSET * 2))
    st[kList]:Show()
    if st[kBar] then st[kBar]:Show() end

    -- Right column: shared progress bar + this tab's detail panel.
    local rightCol = st.collectionRightColumn
    if not rightCol then
        rightCol = Factory:CreateContainer(contentFrame, math.max(1, detailWidth), math.max(1, innerCh or 400), false)
        st.collectionRightColumn = rightCol
    end
    rightCol:ClearAllPoints()
    rightCol:SetPoint("TOPLEFT", st[kBar], "TOPRIGHT", SCROLLBAR_SIDE_GAP, 0)
    rightCol:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", 0, 0)
    rightCol:Show()
    M.EnsureCollectionProgressBar(rightCol)
    local pr = st.collectionProgressFrame
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

    local kDetail = p .. "DetailContainer"
    local panel = st[kDetail]
    if not panel then
        panel = BuildDetailPanel(rightCol, detailWidth, detailH, spec.typeKey, spec.withPreview)
        st[kDetail] = panel
    else
        panel:SetParent(rightCol)
        panel:SetSize(detailWidth, detailH)
        M.ApplyDetailAccentVisuals(panel)
    end
    panel:ClearAllPoints()
    if pr then
        panel:SetPoint("TOPLEFT", pr, "BOTTOMLEFT", 0, -gap)
    else
        panel:SetPoint("TOPLEFT", rightCol, "TOPLEFT", 0, 0)
    end
    panel:SetPoint("BOTTOMRIGHT", rightCol, "BOTTOMRIGHT", 0, 0)
    panel:Show()

    local collected, total = CountEntities(spec.collectedMethod, spec.uncollectedMethod)
    M.SetCollectionProgress(collected, total)

    local grouped = spec.groupFn(st.searchText or "", st.showCollected, st.showUncollected)
    local collapsed = st[spec.collapsedKey]
    if not collapsed then
        collapsed = {}
        st[spec.collapsedKey] = collapsed
    end
    -- Sections open by default (BuildFlatToyList treats nil as collapsed).
    for key in pairs(grouped) do
        if collapsed[key] == nil then collapsed[key] = false end
    end

    local function onSelect(entity)
        st[spec.selectedKey] = entity and entity.id or nil
        PaintDetail(panel, entity, spec)
    end
    PaintDetail(panel, FindEntity(grouped, st[spec.selectedKey]), spec)

    spec.populate(st[kChild], listContentWidth - (CONTAINER_INSET * 2), grouped, collapsed, st[spec.selectedKey], onSelect,
        contentFrame, spec.redraw, drawGen, function()
            if Factory.UpdateScrollBarVisibility and st[kScroll] then
                Factory:UpdateScrollBarVisibility(st[kScroll])
            end
        end)
end

local ILLUSION_SPEC = {
    sub = "illusions", prefix = "illusion", typeKey = "illusion", genKey = "_illusionsDrawGen",
    selectedKey = "selectedIllusionID", collapsedKey = "collapsedHeadersIllusions",
    collectedMethod = "GetCollectedIllusions", uncollectedMethod = "GetUncollectedIllusions",
    planType = "illusion", planField = "illusionID", defaultIcon = DEFAULT_ICON_ILLUSION, withPreview = true,
    isPlanned = function(WN, id) return WN.IsIllusionPlanned and WN:IsIllusionPlanned(id) or false end,
    groupFn = function(...) return M.GetFilteredIllusionsGrouped(...) end,
    populate = function(...) return M.PopulateIllusionList(...) end,
    redraw = function(cf) return M.DrawIllusionsContent(cf) end,
}

local TITLE_SPEC = {
    sub = "titles", prefix = "title", typeKey = "title", genKey = "_titlesDrawGen",
    selectedKey = "selectedTitleID", collapsedKey = "collapsedHeadersTitles",
    collectedMethod = "GetCollectedTitles", uncollectedMethod = "GetUncollectedTitles",
    planType = "title", planField = "titleID", defaultIcon = DEFAULT_ICON_TITLE, withPreview = false,
    isPlanned = function(WN, id) return WN.IsTitlePlanned and WN:IsTitlePlanned(id) or false end,
    groupFn = function(...) return M.GetFilteredTitlesGrouped(...) end,
    populate = function(...) return M.PopulateTitleList(...) end,
    redraw = function(cf) return M.DrawTitlesContent(cf) end,
}

function M.DrawIllusionsContent(contentFrame)
    M.CollectionsSubTabTrace("DrawIllusionsContent_enter", {})
    DrawSimpleCollectionSubTab(contentFrame, ILLUSION_SPEC)
end

function M.DrawTitlesContent(contentFrame)
    M.CollectionsSubTabTrace("DrawTitlesContent_enter", {})
    DrawSimpleCollectionSubTab(contentFrame, TITLE_SPEC)
end

--- Frames HideAllCollectionsResultFrames / ResetCollectionsListScrollPositions must also cover.
function M.HideIllusionTitleResultFrames()
    local st = M.state
    local keys = {
        "illusionListContainer", "illusionListScrollBarContainer", "illusionDetailContainer",
        "titleListContainer", "titleListScrollBarContainer", "titleDetailContainer",
    }
    for i = 1, #keys do
        local f = st[keys[i]]
        if f then f:Hide() end
    end
end

function M.ResetIllusionTitleScrollPositions()
    local st = M.state
    if st.illusionListScrollFrame and st.illusionListScrollFrame.SetVerticalScroll then st.illusionListScrollFrame:SetVerticalScroll(0) end
    if st.titleListScrollFrame and st.titleListScrollFrame.SetVerticalScroll then st.titleListScrollFrame:SetVerticalScroll(0) end
end

--- contentFrame recreated: drop frames parented to the old one.
function M.ClearIllusionTitleFrameRefs()
    local st = M.state
    st.illusionListContainer, st.illusionListScrollFrame, st.illusionListScrollChild = nil, nil, nil
    st.illusionListScrollBarContainer, st.illusionDetailContainer = nil, nil
    st.titleListContainer, st.titleListScrollFrame, st.titleListScrollChild = nil, nil, nil
    st.titleListScrollBarContainer, st.titleDetailContainer = nil, nil
    st._illusionFlatList, st._titleFlatList = nil, nil
end
