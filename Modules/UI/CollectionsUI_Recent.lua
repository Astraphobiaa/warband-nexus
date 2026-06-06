--[[
    Warband Nexus - Collections tab (Recent)
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
local SD = M.SD
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
local COLLECTED_COLOR = M.COLLECTED_COLOR
local DEFAULT_ICON_MOUNT = M.DEFAULT_ICON_MOUNT
local DEFAULT_ICON_PET = M.DEFAULT_ICON_PET
local DEFAULT_ICON_TOY = M.DEFAULT_ICON_TOY
local DEFAULT_ICON_ACHIEVEMENT = M.DEFAULT_ICON_ACHIEVEMENT
local CollectionsRecentCategoryLabel = M.CollectionsRecentCategoryLabel
local FormatCollectionsRecentRelativeTime = M.FormatCollectionsRecentRelativeTime
local format = string.format
local time = time
local date = date
local pcall = pcall
local ipairs = ipairs
local pairs = pairs
local tinsert = table.insert
local tremove = table.remove
local wipe = table.wipe

---@return number cols, number cardW
function M.ComputeRecentCardGrid(innerW, gap)
    local count = #RECENT_SECTION_ORDER
    local idealW = count * RECENT_CARD_MIN_WIDTH + (count - 1) * gap
    if innerW >= idealW then
        return count, (innerW - (count - 1) * gap) / count
    end
    -- Keep all category columns; use main-window horizontal scroll instead of stacking columns.
    return count, RECENT_CARD_MIN_WIDTH
end

--- scrollChild minimum width when Recent grid is wider than the viewport body (main-window h-bar only).
---@param sideMargin number|nil
---@return number|nil
function M.ComputeRecentTabMinScrollWidth(sideMargin)
    local gridW = M.state._recentGridScrollWidth
    if not gridW or gridW < 1 then return nil end
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    local bodyW = (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, mf and mf.scrollChild)) or 0
    if bodyW < 1 or gridW <= bodyW then
        return nil
    end
    local side = sideMargin or SIDE_MARGIN or 12
    return side + gridW + side
end

local function SyncRecentMainHorizontalScroll()
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if not mf or mf.currentTab ~= "collections" or M.state.currentSubTab ~= "recent" then
        return
    end
    local lc = ns.UI_LayoutCoordinator
    local sh = lc and lc._shell
    if sh and sh.updateScrollLayout then
        sh.updateScrollLayout(mf)
    end
    if ns.UI and ns.UI.Factory and ns.UI.Factory.UpdateHorizontalScrollBarVisibility and mf.scroll then
        ns.UI.Factory:UpdateHorizontalScrollBarVisibility(mf.scroll)
    end
end

function M.RecentEntryNameMatches(e, qlower)
    if not e or type(e.name) ~= "string" or e.name == "" then return false end
    if not qlower then return true end
    local nm = e.name
    if issecretvalue and issecretvalue(nm) then return false end
    return SafeLower(nm):find(qlower, 1, true) ~= nil
end

-- Strip legacy "Name — Realm" payloads for Recent display (realm-free; matches CollectiblePayloadObtainedBy).
local UTF8_EM_DASH = "\226\128\148"
function M.RecentCharacterLabelForDisplay(ob)
    if not ob or ob == "" then return nil end
    if issecretvalue and issecretvalue(ob) then return nil end
    local emSep = " " .. UTF8_EM_DASH .. " "
    local cut = ob:find(emSep, 1, true)
    if cut then
        return ob:sub(1, cut - 1)
    end
    cut = ob:find(" - ", 1, true)
    if cut then
        return ob:sub(1, cut - 1)
    end
    return ob
end

function M.RecentAchievementEarnedByLabel(achievementID, storedObtainedBy)
    local ob = M.RecentCharacterLabelForDisplay(storedObtainedBy)
    if ob and ob ~= "" then return ob end
    if not achievementID then return nil end
    local ok, _, _, _, _, _, _, _, _, _, _, _, _, earnedBy = pcall(GetAchievementInfo, achievementID)
    if not ok or not earnedBy or earnedBy == "" then return nil end
    if issecretvalue and issecretvalue(earnedBy) then return nil end
    return M.RecentCharacterLabelForDisplay(earnedBy)
end

function M.RecentEntryIdKey(typ, id)
    if id == nil then return nil end
    return tostring(typ) .. "\31" .. tostring(id)
end

--- Hide only rows recorded as account-prior (alt re-earn). Do not use current char GetAchievementInfo:
--- wasEarnedByMe is per logged-in character and would hide other chars' Recent earns.
function M.RecentAchievementHideFromRecent(_achievementID, entry)
    return entry and entry.accountFirstEarn == false
end

---@param maxN number|nil nil = all matches within DB (retention-pruned list)
function M.RecentPickForType(db, typ, qlower, maxN)
    local out = {}
    local seen = {}
    if type(db) ~= "table" then return out end
    for i = 1, #db do
        local e = db[i]
        if e and e.type == typ and M.RecentEntryNameMatches(e, qlower) then
            local key = M.RecentEntryIdKey(typ, e.id)
            if key and seen[key] then
                -- Newest-first list: keep first (latest) row; skip duplicate id.
            elseif typ == "achievement" and M.RecentAchievementHideFromRecent(e.id, e) then
                -- Account already had this achievement; not a first-time earn for Recent.
            else
                if key then seen[key] = true end
                out[#out + 1] = e
                if maxN and maxN > 0 and #out >= maxN then break end
            end
        end
    end
    return out
end

function M.ApplyRecentRowIconChrome(row)
    if not row or not row._iconBorder or not ApplyVisuals then return end
    local bc = COLORS.border or COLORS.accent or { 0.5, 0.4, 0.7 }
    ApplyVisuals(
        row._iconBorder,
        { 0.10, 0.10, 0.12, 0.96 },
        { bc[1], bc[2], bc[3], RECENT_ROW_ICON_BORDER_ALPHA }
    )
end

function M.PopulateCollectionsRecentTooltip(tt, ctx)
    if not tt or not ctx then return end
    local loc = ns.L
    local wR, wG, wB = 1, 1, 1
    local earnedFmt = (loc and loc["COLLECTIONS_RECENT_TOOLTIP_EARNED_BY"]) or "Earned by %s"
    local recordedFmt = (loc and loc["COLLECTIONS_RECENT_TOOLTIP_RECORDED"]) or "Recorded: %s"

    local timeValue
    if ctx.ts and ctx.ts > 0 then
        local rel = ctx.rel or ""
        if rel ~= "" then
            timeValue = rel
        else
            timeValue = date("%Y-%m-%d %H:%M", ctx.ts)
        end
    elseif ctx.rel and ctx.rel ~= "" then
        timeValue = ctx.rel
    end

    local character = ctx.character
    if character and character ~= "" and issecretvalue and issecretvalue(character) then
        character = nil
    end

    local lineCount = 0
    if character and character ~= "" then
        tt:SetText(format(earnedFmt, character), wR, wG, wB)
        lineCount = 1
    end
    if timeValue and timeValue ~= "" then
        local recordedLine = format(recordedFmt, timeValue)
        if lineCount > 0 then
            tt:AddLine(recordedLine, wR, wG, wB)
        else
            tt:SetText(recordedLine, wR, wG, wB)
        end
    end
end

function M.ClearRecentPanelChildren(panel)
    if not panel then return end
    local ch = { panel:GetChildren() }
    for i = 1, #ch do
        ch[i]:SetParent(nil)
        ch[i]:Hide()
    end
end

function M.GetRecentSectionCategoryIcon(ctype)
    if ctype == "achievement" then
        return "UI-Achievement-Shield-NoPoints", true
    elseif ctype == "mount" then
        return DEFAULT_ICON_MOUNT, false
    elseif ctype == "pet" then
        return DEFAULT_ICON_PET, false
    elseif ctype == "toy" then
        return DEFAULT_ICON_TOY, false
    end
    return DEFAULT_ICON_ACHIEVEMENT, false
end

function M.GetRecentEntryDisplayIcon(ctype, id)
    if WarbandNexus and WarbandNexus.GetPlanDisplayIcon and id ~= nil then
        local plan = { type = ctype }
        if ctype == "achievement" then plan.achievementID = id
        elseif ctype == "mount" then plan.mountID = id
        elseif ctype == "pet" then plan.speciesID = id
        elseif ctype == "toy" then plan.itemID = id
        else return DEFAULT_ICON_ACHIEVEMENT
        end
        return WarbandNexus:GetPlanDisplayIcon(plan)
    end
    local path = select(1, M.GetRecentSectionCategoryIcon(ctype))
    if ctype == "achievement" then return DEFAULT_ICON_ACHIEVEMENT end
    return path or DEFAULT_ICON_ACHIEVEMENT
end

function M.RecentRowNavigateToEntry(ctype, id)
    if not ctype or id == nil then return end
    if ctype == "achievement" then
        M.state.currentSubTab = "achievements"
        ns._sessionCollectionsSubTab = "achievements"
        M.state.selectedAchievementID = id
    elseif ctype == "mount" then
        M.state.currentSubTab = "mounts"
        ns._sessionCollectionsSubTab = "mounts"
        M.state.selectedMountID = id
    elseif ctype == "pet" then
        M.state.currentSubTab = "pets"
        ns._sessionCollectionsSubTab = "pets"
        M.state.selectedPetID = id
    elseif ctype == "toy" then
        M.state.currentSubTab = "toys"
        ns._sessionCollectionsSubTab = "toys"
        M.state.selectedToyID = id
    else
        return
    end
    WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, { tab = "collections", skipCooldown = true })
end

function M.DrawRecentContent(contentFrame)
    if not contentFrame then return end
    M.HideAllCollectionsResultFrames()
    local parent = contentFrame:GetParent()
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    -- Layout from viewport body width only — never scrollChild width (avoids resize feedback loop).
    local bodyW = (ns.UI_ResolveMainTabBodyWidth and ns.UI_ResolveMainTabBodyWidth(mf, parent)) or 0
    if bodyW < 1 then
        bodyW = contentFrame:GetWidth()
    end
    if not bodyW or bodyW < 1 then
        bodyW = M.CollectionsFallbackContentWidth(parent, mf)
    end
    local cw = bodyW
    local ch = M.ResolveCollectionsViewportHeight(contentFrame, mf)
    local viewCap = M.state.recentViewportCap or ch

    local headerBlockH = select(1, M.ApplyCollectionsContentHeader(contentFrame, "recent", viewCap))

    local panel = M.state.recentTabPanel
    if not panel then
        panel = Factory:CreateContainer(contentFrame, cw, math.max(1, viewCap - headerBlockH), false)
        M.state.recentTabPanel = panel
    end
    panel:SetParent(contentFrame)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", 0, -headerBlockH)
    panel:Show()

    if WarbandNexus.PruneCollectionsRecentObtained then
        WarbandNexus:PruneCollectionsRecentObtained()
    end

    local db = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.collectionsRecentObtained
    local loc = ns.L
    local qraw = M.state.searchText or ""
    local qlower
    if qraw and not (issecretvalue and issecretvalue(qraw)) and qraw ~= "" then
        qlower = qraw:lower()
    end

    local searchEmptyTxt = (ns.UI_FormatSearchEmptyMessage and ns.UI_FormatSearchEmptyMessage(qraw))
        or ((loc and loc["NO_ITEMS_MATCH_GENERIC"]) or "No items match your search")
    local noneLine = (loc and loc["COLLECTIONS_RECENT_SECTION_NONE"]) or "No entries yet."
    local inset = CONTENT_INSET or 8
    local gap = CARD_GAP

    M.ClearRecentPanelChildren(panel)
    if panel.emptyStateContainer then
        panel.emptyStateContainer:Hide()
    end

    local pickedLists = {}
    for si = 1, #RECENT_SECTION_ORDER do
        pickedLists[si] = M.RecentPickForType(db, RECENT_SECTION_ORDER[si], qlower, nil)
    end

    if qlower then
        local anyMatch = false
        for si = 1, #RECENT_SECTION_ORDER do
            if #pickedLists[si] > 0 then
                anyMatch = true
                break
            end
        end
        if not anyMatch then
            local inner_viewport = math.max(1, viewCap - headerBlockH)
            local emptyExtent = 40
            if ns.UI_RenderStandardSearchEmptyState then
                emptyExtent = ns.UI_RenderStandardSearchEmptyState(WarbandNexus, panel, qraw, "collections_recent", emptyExtent) or emptyExtent
            end
            local finalContentH = math.max(viewCap, headerBlockH + emptyExtent + inset)
            contentFrame:SetHeight(finalContentH)
            if panel.SetHeight then
                panel:SetHeight(math.max(1, inner_viewport))
            end
            M.ApplyCollectionsContentHeader(contentFrame, "recent", finalContentH)
            SyncRecentMainHorizontalScroll()
            return
        end
    end

    local innerW = math.max(1, cw - 2 * inset)
    local recentCols, cardW = M.ComputeRecentCardGrid(innerW, gap)
    local gridBodyW = 2 * inset + recentCols * cardW + (recentCols - 1) * gap
    M.state._recentGridScrollWidth = gridBodyW
    local recentRows = math.ceil(#RECENT_SECTION_ORDER / recentCols)
    local headerBand = RECENT_CARD_HEADER_PAD + RECENT_CARD_ICON + 8
    local listTopPad = headerBand + 4
    local RECENT_ROW_H_SUB = math.floor(44 * 1.05 + 0.5)

    --- Pixel height of the scrollable list block inside one Recent card (rows only; excludes header band).
    local function RecentColumnListPixelHeight(typ, picked)
        local yList = 0
        if qlower and #picked == 0 then
            return ROW_STRIDE
        elseif #picked == 0 then
            return ROW_STRIDE
        end
        for j = 1, #picked do
            local e = picked[j]
            local ob = (typ == "achievement" and e.id)
                and M.RecentAchievementEarnedByLabel(e.id, e.obtainedBy)
                or M.RecentCharacterLabelForDisplay(e.obtainedBy)
            local rowH = ROW_HEIGHT
            if ob and ob ~= "" then
                rowH = RECENT_ROW_H_SUB
            end
            yList = yList + rowH + ROW_GAP
        end
        return yList
    end

    local maxColContent = 0
    for si = 1, #RECENT_SECTION_ORDER do
        local typ = RECENT_SECTION_ORDER[si]
        local picked = pickedLists[si]
        local colTotal = listTopPad + RecentColumnListPixelHeight(typ, picked) + RECENT_CARD_HEADER_PAD
        if colTotal > maxColContent then
            maxColContent = colTotal
        end
    end

    local inner_viewport = math.max(1, viewCap - headerBlockH)
    local rowGapTotal = (recentRows > 1) and ((recentRows - 1) * gap) or 0
    local minCardFill = math.max(160, (inner_viewport - 2 * inset - rowGapTotal) / recentRows)
    local cardH = math.max(minCardFill, maxColContent)
    local finalContentH = math.max(viewCap, headerBlockH + inset + recentRows * cardH + rowGapTotal + inset)

    contentFrame:SetHeight(finalContentH)
    local panelH = math.max(1, inner_viewport)
    if panel.SetSize then
        panel:SetSize(gridBodyW, panelH)
    elseif panel.SetWidth then
        panel:SetWidth(gridBodyW)
        panel:SetHeight(panelH)
    end
    if contentFrame.SetClipsChildren then
        contentFrame:SetClipsChildren(false)
    end
    M.ApplyCollectionsContentHeader(contentFrame, "recent", finalContentH)

    local rowVisualIndex = 0
    for si = 1, #RECENT_SECTION_ORDER do
        local typ = RECENT_SECTION_ORDER[si]
        local picked = pickedLists[si]
        local cat = CollectionsRecentCategoryLabel(typ)
        local iconTex, iconIsAtlas = M.GetRecentSectionCategoryIcon(typ)
        local defaultEmptyIcon = (typ == "achievement" and DEFAULT_ICON_ACHIEVEMENT)
            or (typ == "mount" and DEFAULT_ICON_MOUNT)
            or (typ == "pet" and DEFAULT_ICON_PET)
            or DEFAULT_ICON_TOY

        local gridCol = (si - 1) % recentCols
        local gridRow = math.floor((si - 1) / recentCols)
        local card = CreateCard(panel, cardH)
        card:SetParent(panel)
        card:SetSize(cardW, cardH)
        card:SetPoint(
            "TOPLEFT",
            panel,
            "TOPLEFT",
            inset + gridCol * (cardW + gap),
            -(inset + gridRow * (cardH + gap))
        )
        if ApplyVisuals then
            local bg = COLORS.bgCard or COLORS.bgLight or COLORS.bg
            ApplyVisuals(card, { bg[1], bg[2], bg[3], 0.96 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.45 })
        end
        card:Show()

        local headerIconBorder = COLORS.border or COLORS.accent or { 0.5, 0.4, 0.7 }
        local iconFr = CreateIcon(card, iconTex, RECENT_CARD_ICON, iconIsAtlas, {
            headerIconBorder[1], headerIconBorder[2], headerIconBorder[3], RECENT_ROW_ICON_BORDER_ALPHA,
        }, false)
        local headerMidY = -(RECENT_CARD_HEADER_PAD + RECENT_CARD_ICON * 0.5)
        if iconFr then
            iconFr:SetPoint("CENTER", card, "TOPLEFT", RECENT_CARD_HEADER_PAD + RECENT_CARD_ICON * 0.5, headerMidY)
            iconFr:Show()
        end

        local resetBtn = Factory:CreateButton(card, 22, 22, true)
        resetBtn:SetPoint("CENTER", card, "TOPRIGHT", -(RECENT_CARD_HEADER_PAD + 11), headerMidY)
        resetBtn:SetFrameLevel((card:GetFrameLevel() or 0) + 8)
        local resetTex = resetBtn:CreateTexture(nil, "ARTWORK")
        resetTex:SetAllPoints()
        local resetAtlasOk = pcall(function() resetTex:SetAtlas("talents-button-reset", true) end)
        if not resetAtlasOk then
            resetTex:SetTexture("Interface\\Buttons\\UI-RefreshButton")
        end
        resetTex:SetVertexColor(1, 1, 1, 1)
        resetBtn:SetScript("OnEnter", function(self)
            resetTex:SetVertexColor(1, 0.95, 0.45, 1)
            GameTooltip:ClearLines()
            if ns.UI_SetGameTooltipSmartOwner then
                ns.UI_SetGameTooltipSmartOwner(self, 0, 0)
            else
                GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            end
            GameTooltip:SetText((loc and loc["COLLECTIONS_RECENT_CARD_RESET_TOOLTIP"]) or "Clear recent list", 1, 1, 1)
            GameTooltip:AddLine(
                (loc and loc["COLLECTIONS_RECENT_CARD_RESET_TOOLTIP_BODY"])
                    or "Removes entries from this Recent category only. Your collection data is not deleted.",
                1, 1, 1, true
            )
            GameTooltip:Show()
        end)
        resetBtn:SetScript("OnLeave", function()
            resetTex:SetVertexColor(1, 1, 1, 1)
            GameTooltip_Hide()
        end)
        resetBtn:SetScript("OnClick", function()
            if WarbandNexus.ClearCollectionsRecentObtainedForType then
                WarbandNexus:ClearCollectionsRecentObtainedForType(typ)
            end
            WarbandNexus:SendMessage(Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                tab = "collections",
                skipCooldown = true,
                instantPopulate = true,
            })
        end)

        local titleFs = FontManager:CreateFontString(card, "header", "OVERLAY")
        titleFs:SetPoint("LEFT", iconFr or card, "RIGHT", 8, 0)
        titleFs:SetPoint("RIGHT", resetBtn, "LEFT", -8, 0)
        titleFs:SetJustifyH("LEFT")
        titleFs:SetJustifyV("MIDDLE")
        titleFs:SetText(cat)
        titleFs:SetTextColor(1, 0.85, 0.45, 1)

        local listWInner = math.max(1, cardW - RECENT_CARD_HEADER_PAD * 2)
        local listHost = Factory:CreateContainer(card, listWInner, 1, false)
        listHost:SetPoint("TOPLEFT", card, "TOPLEFT", RECENT_CARD_HEADER_PAD, -listTopPad)
        listHost:Show()

        local yList = 0
        local function addRow(iconPath, nameRich, rightTime, clickable, onClick, tooltipBuilder, subtitleRich, rowH)
            rowVisualIndex = rowVisualIndex + 1
            rowH = rowH or ROW_HEIGHT
            local row = Factory:CreateCollectionListRow(listHost, rowH)
            row:SetParent(listHost)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", listHost, "TOPLEFT", 0, -yList)
            row:SetWidth(listWInner)
            Factory:ApplyCollectionListRowContent(row, rowVisualIndex, iconPath, nameRich, clickable, false, onClick, rightTime, subtitleRich, nil)
            M.ApplyRecentRowIconChrome(row)
            if tooltipBuilder then
                row:SetScript("OnEnter", function(self)
                    GameTooltip:ClearLines()
                    if ns.UI_SetGameTooltipSmartOwner then
                        ns.UI_SetGameTooltipSmartOwner(self, 0, 0)
                    else
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    end
                    tooltipBuilder(GameTooltip)
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", GameTooltip_Hide)
            else
                row:SetScript("OnEnter", nil)
                row:SetScript("OnLeave", nil)
            end
            yList = yList + rowH + ROW_GAP
        end

        if qlower and #picked == 0 then
            addRow(defaultEmptyIcon, "|cffffffff" .. searchEmptyTxt .. "|r", nil, false, nil, nil, nil, ROW_HEIGHT)
        elseif #picked == 0 then
            addRow(defaultEmptyIcon, "|cffffffff" .. noneLine .. "|r", nil, false, nil, nil, nil, ROW_HEIGHT)
        else
            for j = 1, #picked do
                local e = picked[j]
                local nm = e.name or ""
                if issecretvalue and issecretvalue(nm) then
                    nm = (loc and loc["HIDDEN_ACHIEVEMENT"]) or "—"
                end
                local rel = M.FormatCollectionsRecentRelativeTime(e.t)
                local iconPath = M.GetRecentEntryDisplayIcon(typ, e.id)
                local idCopy, typCopy, tsCopy, nmCopy = e.id, typ, e.t, nm
                local ob = (typCopy == "achievement" and idCopy)
                    and M.RecentAchievementEarnedByLabel(idCopy, e.obtainedBy)
                    or M.RecentCharacterLabelForDisplay(e.obtainedBy)
                local subLine = nil
                local rowH = ROW_HEIGHT
                if ob and ob ~= "" then
                    local cc = (ns.UI_GetClassColorHexForWarbandCharacter and ns.UI_GetClassColorHexForWarbandCharacter(ob))
                        or "|cffffffff"
                    subLine = format((loc and loc["COLLECTIONS_RECENT_ROW_BY"]) or "By %s", cc .. ob .. "|r")
                    rowH = RECENT_ROW_H_SUB
                end
                local trySuffix = ""
                if (typ == "mount" or typ == "pet" or typ == "toy") and SD and SD.FormatMountPetToyListTrySuffix then
                    trySuffix = SD.FormatMountPetToyListTrySuffix(typ, idCopy) or ""
                end
                local nameRich = COLLECTED_COLOR .. nm .. "|r" .. trySuffix

                local function buildTooltip(tt)
                    M.PopulateCollectionsRecentTooltip(tt, {
                        character = ob,
                        ts = tsCopy,
                        rel = rel,
                    })
                end

                addRow(iconPath, nameRich, "|cffffffff" .. rel .. "|r", true, function()
                    M.RecentRowNavigateToEntry(typCopy, idCopy)
                end, buildTooltip, subLine, rowH)
            end
        end

        listHost:SetHeight(math.max(yList, 1))
    end

    SyncRecentMainHorizontalScroll()
end

