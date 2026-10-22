--[[
    Warband Nexus - PvP Tab (Warband Overview)
    Professions / PvE column-grid parity: section title, 48px header strip, zebra rows, grid dividers.
    Loaded after PvPUI.lua, before PvPUI_Draw.lua.
]]

local _, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local M = ns.PvPUI
assert(M, "PvPUI.lua must load before PvPUI_Overview.lua")

local L = ns.L
local COLORS = ns.UI_COLORS
local FontManager = ns.FontManager
local PUI = ns.ProfessionsUI
local TK = ns.UI_TableKit
assert(TK, "SharedWidgets_TableKit.lua must load before PvPUI_Overview.lua")
local issecretvalue = issecretvalue

--- Key accessor for overview rows; passed to CharacterService:PartitionFavoritesFirst.
local function PvPRowCharKey(row)
    return row and row.charKey or nil
end

local OVERVIEW_SECTION_GAP = 4
local OVERVIEW_COL_HDR_H = 48
local OVERVIEW_COL_HDR_PAD = 2
local OVERVIEW_ROW_H = 46
local OVERVIEW_COL_GAP = 4
local OVERVIEW_COL_RIGHT_MARGIN = 6
local OVERVIEW_COL_PAD = 8
local OVERVIEW_NAME_MIN = (ns.PVE_NAME_COL_MIN_W) or 100
local OVERVIEW_NAME_MAX = 180
local OVERVIEW_CURRENCY_MIN = 76
local OVERVIEW_RATING_MIN = 52
local OVERVIEW_WEEKLY_MIN = 72
local OVERVIEW_HDR_ICON = 22
local OVERVIEW_COL_PREFIX = "pvpOv_"

local function MeasureFsWidth(fs, text)
    if not fs or not text or text == "" then return 0 end
    if issecretvalue and issecretvalue(text) then return 0 end
    fs:SetText(text)
    return fs:GetStringWidth() or 0
end

local function MeasureIdentityNameWidth(measureFs, rosterRows)
    local maxW = 0
    for i = 1, #rosterRows do
        local r = rosterRows[i]
        local nameStr = tostring(r.name or "?")
        if issecretvalue and issecretvalue(nameStr) then nameStr = "?" end
        local realmStr = (ns.Utilities and ns.Utilities.FormatRealmName)
            and ns.Utilities:FormatRealmName(r.realm) or (r.realm or "")
        if issecretvalue and issecretvalue(realmStr) then realmStr = "" end
        if ns.PvE_MeasureStackedNameColumnWidth then
            maxW = math.max(maxW, ns.PvE_MeasureStackedNameColumnWidth(measureFs, nameStr, realmStr))
        else
            maxW = math.max(maxW, MeasureFsWidth(measureFs, nameStr), MeasureFsWidth(measureFs, realmStr))
        end
    end
    maxW = math.max(maxW, MeasureFsWidth(measureFs, (L and L["PVP_COL_CHARACTER"]) or "Character"))
    if ns.PvE_ResolveNameColumnWidth then
        return ns.PvE_ResolveNameColumnWidth(maxW)
    end
    return math.max(OVERVIEW_NAME_MIN, math.min(OVERVIEW_NAME_MAX, math.ceil(maxW + 4)))
end

local function BuildIdentityLayout(nameColW)
    if ns.PvE_GetIdentityLayout then
        return ns.PvE_GetIdentityLayout(nameColW, 0)
    end
    return { nameColW = nameColW, inlineStart = 320, identityGradientEnd = 220 }
end

local function HeaderIconIsDrawn(iconTex)
    if not iconTex then return false end
    if iconTex.GetAtlas then
        local atlas = iconTex:GetAtlas()
        if atlas and atlas ~= "" then return true end
    end
    if iconTex.GetTexture then
        if iconTex:GetTexture() then return true end
    end
    return false
end

local function ResolveColumnIconDef(key)
    if M.ResolveRosterStatHeaderIcon then
        return M.ResolveRosterStatHeaderIcon(key)
    end
    local statIcons = M.ROSTER_STAT_HEADER_ICONS or {}
    return statIcons[key]
end

local function ApplyHeaderIcon(iconTex, iconDef, iconSize)
    if not iconTex or not iconDef then return end
    iconSize = iconSize or (iconDef and iconDef.headerIconSize) or OVERVIEW_HDR_ICON
    iconTex:Hide()
    iconTex:SetTexture(nil)
    if M.ApplyRosterHeaderIconTexture then
        M.ApplyRosterHeaderIconTexture(iconTex, iconDef, OVERVIEW_HDR_ICON)
        if HeaderIconIsDrawn(iconTex) then return end
    end
    if iconDef.icon and type(iconDef.icon) == "number" and iconTex.SetTexture then
        iconTex:SetTexture(iconDef.icon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetSize(OVERVIEW_HDR_ICON, OVERVIEW_HDR_ICON)
        if ns.UI_EnsureTextureFullColor then ns.UI_EnsureTextureFullColor(iconTex) end
        iconTex:Show()
    end
end

--- TableKit applyIcon hook: roster iconDef resolver (currency / atlas / file chain) before the kit's own resolver.
local function ApplyOverviewHeaderIcon(iconTex, col, iconSize)
    if not col or not col.iconDef then return false end
    ApplyHeaderIcon(iconTex, col.iconDef, iconSize)
    return HeaderIconIsDrawn(iconTex)
end

local function MeasureHeaderLabelWidth(hdrFs, compactLabel)
    if not hdrFs or not compactLabel or compactLabel == "" then return 0 end
    if issecretvalue and issecretvalue(compactLabel) then return 0 end
    local nl = compactLabel:find("\n", 1, true)
    if not nl then
        return MeasureFsWidth(hdrFs, compactLabel)
    end
    local maxW = 0
    local start = 1
    while true do
        local lineEnd = compactLabel:find("\n", start, true)
        local line = lineEnd and compactLabel:sub(start, lineEnd - 1) or compactLabel:sub(start)
        if line ~= "" then
            maxW = math.max(maxW, MeasureFsWidth(hdrFs, line))
        end
        if not lineEnd then break end
        start = lineEnd + 1
    end
    return maxW
end

local function MeasureIconColumn(hdrFs, bodyFs, compactLabel, minW, samples, iconSize)
    iconSize = iconSize or OVERVIEW_HDR_ICON
    local w = iconSize
    if hdrFs and compactLabel and compactLabel ~= "" then
        w = math.max(w, MeasureHeaderLabelWidth(hdrFs, compactLabel))
    end
    if bodyFs and samples then
        for i = 1, #samples do
            w = math.max(w, MeasureFsWidth(bodyFs, samples[i]))
        end
    end
    return math.max(minW, math.ceil(w + OVERVIEW_COL_PAD * 2))
end

local function MeasureStatColumns(measureFs, hdrFs, rosterRows)
    local honorSamples, conquestSamples, bracketSamples = {}, {}, {}
    local weeklySamples = { "0 / 0", "999 / 999" }
    local bracketOrder = M.ROSTER_BRACKET_ORDER or {}
    local bracketHeaders = M.ROSTER_BRACKET_HEADERS or {}

    for i = 1, #rosterRows do
        local r = rosterRows[i]
        local honorText = M.FormatRosterCurrencyQty(M.RosterCurrencyQuantity(r.charKey, M.ROSTER_HONOR_CURRENCY_ID))
        if honorText then honorSamples[#honorSamples + 1] = honorText end
        local conqText = M.FormatRosterCurrencyQty(M.RosterCurrencyQuantity(r.charKey, M.ROSTER_CONQUEST_CURRENCY_ID))
        if conqText then conquestSamples[#conquestSamples + 1] = conqText end

        local hasBrackets = type(r.brackets) == "table"
        for bi = 1, #bracketOrder do
            local b = hasBrackets and r.brackets[bracketOrder[bi]] or nil
            local rating = b and tonumber(b.rating) or nil
            bracketSamples[#bracketSamples + 1] = (rating and rating > 0) and tostring(rating) or "-"
        end
        if hasBrackets then
            local won, played = 0, 0
            for bi = 1, #bracketOrder do
                local b = r.brackets[bracketOrder[bi]]
                if b then
                    won = won + (tonumber(b.weeklyWon) or 0)
                    played = played + (tonumber(b.weeklyPlayed) or 0)
                end
            end
            weeklySamples[#weeklySamples + 1] = string.format("%d / %d", won, played)
        end
    end

    local honorLabel = M.RosterHonorHeaderLabel()
    local conquestLabel = M.RosterConquestHeaderLabel()
    honorSamples[#honorSamples + 1] = "-"
    conquestSamples[#conquestSamples + 1] = "-"

    -- TableKit column definitions (SharedWidgets_TableKit.lua): compact header, icon slot over label.
    local columns = {}
    local honorIcon = ResolveColumnIconDef("honor")
    columns[#columns + 1] = {
        key = "honor", iconSlot = true, iconDef = honorIcon, iconSize = honorIcon and honorIcon.headerIconSize,
        width = MeasureIconColumn(hdrFs, measureFs, honorLabel, OVERVIEW_CURRENCY_MIN, honorSamples),
        align = "CENTER", label = honorLabel, tooltip = honorLabel,
    }
    local conquestIcon = ResolveColumnIconDef("conquest")
    columns[#columns + 1] = {
        key = "conquest", iconSlot = true, iconDef = conquestIcon, iconSize = conquestIcon and conquestIcon.headerIconSize,
        width = MeasureIconColumn(hdrFs, measureFs, conquestLabel, OVERVIEW_CURRENCY_MIN, conquestSamples),
        align = "CENTER", label = conquestLabel, tooltip = conquestLabel,
    }
    local statIcons = M.ROSTER_STAT_HEADER_ICONS or {}
    local bracketLabels = M.BRACKET_LABELS or {}
    for bi = 1, #bracketOrder do
        local bkey = bracketOrder[bi]
        local iconDef = ResolveColumnIconDef(bkey) or statIcons[bkey]
        local headerLabel = (M.RosterBracketHeaderLabel and M.RosterBracketHeaderLabel(bkey)) or (bracketHeaders[bi] or bkey)
        local iconSize = iconDef and iconDef.headerIconSize or OVERVIEW_HDR_ICON
        columns[#columns + 1] = {
            key = bkey, iconSlot = true, iconDef = iconDef, iconSize = iconDef and iconDef.headerIconSize,
            width = MeasureIconColumn(hdrFs, measureFs, headerLabel, OVERVIEW_RATING_MIN, bracketSamples, iconSize),
            align = "CENTER", label = headerLabel,
            tooltip = bracketLabels[bkey] or bkey,
        }
    end
    local weeklyLabel = (L and L["PVP_WEEKLY"]) or "Weekly W/P"
    local weeklyIcon = ResolveColumnIconDef("weekly")
    columns[#columns + 1] = {
        key = "weekly", iconSlot = true, iconDef = weeklyIcon, iconSize = weeklyIcon and weeklyIcon.headerIconSize,
        width = math.max(
            MeasureIconColumn(hdrFs, measureFs, "W/P", OVERVIEW_WEEKLY_MIN, weeklySamples),
            math.ceil(MeasureFsWidth(hdrFs, weeklyLabel) + OVERVIEW_COL_PAD * 2)),
        align = "CENTER", label = "W/P", tooltip = weeklyLabel,
    }
    return columns
end

local function PvpGroupIdFromSecKey(secKey)
    if type(secKey) ~= "string" then return nil end
    return secKey:match("^pvp_grp:(.+)$")
end

local function GetLocalizedText(key, fallback)
    local val = L and L[key]
    if type(val) == "string" and val ~= "" and val ~= key then return val end
    return fallback
end

local function CompareCharNameLower(a, b)
    local an = (a and a.name) or ""
    local bn = (b and b.name) or ""
    if issecretvalue and issecretvalue(an) then an = "" end
    if issecretvalue and issecretvalue(bn) then bn = "" end
    return string.lower(an) < string.lower(bn)
end

local function BuildPvpPaintOrder(WN, profile, overviewRows)
    local paintOrder = {}
    if not WN or not profile or not overviewRows or #overviewRows == 0 then
        return paintOrder
    end
    local CS = ns.CharacterService
    if not CS then return paintOrder end

    CS:EnsureCustomCharacterSectionsProfile(profile)
    profile.pvpSectionFilter = profile.pvpSectionFilter or { sectionKey = "all" }
    local sectionFilter = profile.pvpSectionFilter.sectionKey or "all"
    local rosterSortKey = CS:GetTabSortKey(profile, "pvp")
    local peelCurrentChar = (rosterSortKey == "default")

    local currentPlayerKey = (ns.UI_GetSubsidiaryCharKey and ns.UI_GetSubsidiaryCharKey())
        or (CS.ResolveSubsidiaryCharacterKey and CS:ResolveSubsidiaryCharacterKey(WN, nil))

    local function sortRows(list, orderKey)
        if CS.SortCharacterRosterList then
            return CS:SortCharacterRosterList(list, profile, orderKey, {
                tabId = "pvp",
                compareNameFn = CompareCharNameLower,
                isLoggedInFn = function(row)
                    return row and row.isCurrent == true
                end,
                getCharKeyFn = function(row) return row and row.charKey end,
            })
        end
        table.sort(list, CompareCharNameLower)
        return list
    end

    -- Section wins over Favorites: a favorited character stays in its section (star only).
    local currentRow, favorites, regularUngrouped = nil, {}, {}
    local groupedById = {}
    for i = 1, #overviewRows do
        local row = overviewRows[i]
        local charKey = row.charKey
        if peelCurrentChar and charKey and (
            charKey == currentPlayerKey
            or (ns.VaultCharKeysMatch and ns.VaultCharKeysMatch(charKey, currentPlayerKey))
        ) then
            currentRow = row
        else
            local gsec = CS:GetCharacterCustomSectionId(WN, charKey)
            if gsec then
                local gk = tostring(gsec)
                groupedById[gk] = groupedById[gk] or {}
                groupedById[gk][#groupedById[gk] + 1] = row
            elseif CS:IsFavoriteCharacter(WN, charKey) then
                favorites[#favorites + 1] = row
            else
                regularUngrouped[#regularUngrouped + 1] = row
            end
        end
    end

    favorites = sortRows(favorites, "favorites")

    local sortModeKey = rosterSortKey
    local customGroupsOrdered = CS:BuildOrderedCustomCharacterGroups(profile, sortModeKey) or {}
    for oci = 1, #customGroupsOrdered do
        local gid0 = customGroupsOrdered[oci].id
        local gk0 = tostring(gid0)
        local gL = groupedById[gk0]
        if gL and #gL > 0 then
            local lk0 = CS:GetCustomGroupListKey(gid0) or "regular"
            gL = sortRows(gL, lk0)
            if CS.PartitionFavoritesFirst then
                CS:PartitionFavoritesFirst(WN, gL, PvPRowCharKey)
            end
            groupedById[gk0] = gL
        end
    end
    regularUngrouped = sortRows(regularUngrouped, "regular")

    local favoritesDisplay, regularDisplay, groupedDisplay = {}, {}, {}
    for fi = 1, #favorites do favoritesDisplay[fi] = favorites[fi] end
    for ri2 = 1, #regularUngrouped do regularDisplay[ri2] = regularUngrouped[ri2] end
    for gid, lst in pairs(groupedById) do
        local copy = {}
        for li = 1, #lst do copy[li] = lst[li] end
        groupedDisplay[gid] = copy
    end

    if currentRow then
        local ck0 = currentRow.charKey
        local curGid = CS:GetCharacterCustomSectionId(WN, ck0)
        if curGid then
            local gkMerge = tostring(curGid)
            local bucket = groupedDisplay[gkMerge] or {}
            bucket[#bucket + 1] = currentRow
            local lk0 = CS:GetCustomGroupListKey(curGid) or ("group_" .. gkMerge)
            bucket = sortRows(bucket, lk0)
            if CS.PartitionFavoritesFirst then
                CS:PartitionFavoritesFirst(WN, bucket, PvPRowCharKey)
            end
            groupedDisplay[gkMerge] = bucket
        elseif CS:IsFavoriteCharacter(WN, ck0) then
            favoritesDisplay[#favoritesDisplay + 1] = currentRow
            favoritesDisplay = sortRows(favoritesDisplay, "favorites")
        else
            regularDisplay[#regularDisplay + 1] = currentRow
            regularDisplay = sortRows(regularDisplay, "regular")
        end
    end

    local drawFav = (sectionFilter == "all") or (sectionFilter == "favorites")
    local drawReg = (sectionFilter == "all") or (sectionFilter == "regular")

    if drawFav and #favoritesDisplay > 0 then
        for fi2 = 1, #favoritesDisplay do
            paintOrder[#paintOrder + 1] = { row = favoritesDisplay[fi2], secKey = "pvp_fav" }
        end
    end
    for oci2 = 1, #customGroupsOrdered do
        local gMeta = customGroupsOrdered[oci2]
        local gid2 = gMeta.id
        local gList2 = groupedDisplay[tostring(gid2)] or {}
        local gListKey = CS:GetCustomGroupListKey(gid2) or ("group_" .. tostring(gid2))
        local showGrp = (sectionFilter == "all") or (sectionFilter == gListKey)
        if showGrp and #gList2 > 0 then
            local sk = "pvp_grp:" .. tostring(gid2)
            for gj2 = 1, #gList2 do
                paintOrder[#paintOrder + 1] = { row = gList2[gj2], secKey = sk }
            end
        end
    end
    for gidOr2, listOr2 in pairs(groupedDisplay) do
        local foundOr2 = false
        for ociOr2 = 1, #customGroupsOrdered do
            if tostring(customGroupsOrdered[ociOr2].id) == tostring(gidOr2) then
                foundOr2 = true
                break
            end
        end
        if not foundOr2 and listOr2 and #listOr2 > 0 then
            local gListKey2 = CS:GetCustomGroupListKey(gidOr2) or ("group_" .. tostring(gidOr2))
            local showOr2 = (sectionFilter == "all") or (sectionFilter == gListKey2)
            if showOr2 then
                local sko = "pvp_grp:" .. tostring(gidOr2)
                for oj2 = 1, #listOr2 do
                    paintOrder[#paintOrder + 1] = { row = listOr2[oj2], secKey = sko }
                end
            end
        end
    end
    if drawReg and #regularDisplay > 0 then
        for ri3 = 1, #regularDisplay do
            paintOrder[#paintOrder + 1] = { row = regularDisplay[ri3], secKey = "pvp_reg" }
        end
    end

    return paintOrder
end

local function ReflowPvpSectionRows(body, rowGap)
    if not body then return end
    rowGap = rowGap or 0
    local rows = body._pvpRowsOrdered or {}
    local y = 0
    for i = 1, #rows do
        local row = rows[i]
        if row and row.Show and row:IsShown() then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -y)
            y = y + OVERVIEW_ROW_H
            if i < #rows then y = y + rowGap end
        end
    end
    local h = math.max(0.1, y)
    body:SetHeight(h)
    body._wnSectionFullH = h
    body._pvpRunningH = h
end

local function FinalizePvpSectionBody(body, profile, secKey, rowGap)
    if not body or not secKey then return end
    ReflowPvpSectionRows(body, rowGap)
    local expanded = false
    if secKey == "pvp_fav" then
        expanded = profile and profile.ui and profile.ui.pvpFavoritesExpanded == true
    elseif secKey == "pvp_reg" then
        expanded = profile and profile.ui and profile.ui.pvpCharactersExpanded == true
    else
        local gidStr = PvpGroupIdFromSecKey(secKey)
        if gidStr and profile then
            if not profile.characterGroupExpanded then profile.characterGroupExpanded = {} end
            local ev = profile.characterGroupExpanded[gidStr]
            if ev == nil then
                local asNum = tonumber(gidStr)
                if asNum then ev = profile.characterGroupExpanded[asNum] end
            end
            expanded = ev == true
        end
    end
    if expanded then
        body:Show()
        body:SetHeight(math.max(0.1, body._wnSectionFullH or body._pvpRunningH or 0.1))
    else
        body:Hide()
        body:SetHeight(0.1)
    end
end

local function PvpExpandKeyFromMeta(sectionMeta)
    if not sectionMeta then return nil end
    if sectionMeta.sectionUiKey then return sectionMeta.sectionUiKey end
    if sectionMeta.visualOpts and sectionMeta.visualOpts.groupId then
        return "cgrp_" .. tostring(sectionMeta.visualOpts.groupId)
    end
    return nil
end

local function TrackPvpShellOrder(scrollChild, expandKey)
    if not scrollChild or not expandKey then return end
    scrollChild._pvpSectionShellOrder = scrollChild._pvpSectionShellOrder or {}
    local order = scrollChild._pvpSectionShellOrder
    for oi = 1, #order do
        if order[oi] == expandKey then return end
    end
    order[#order + 1] = expandKey
end

local function ReflowPvpSectionShellChain(scrollChild, bundle, side, rowGap)
    if not scrollChild or not bundle or not bundle.pvpSectionShells then return end
    local order = scrollChild._pvpSectionShellOrder
    if not order or #order == 0 then return end
    local shells = bundle.pvpSectionShells
    local gap = scrollChild._pvpShellSectionGap or OVERVIEW_SECTION_GAP
    side = side or scrollChild._wnPvpContentSide or 0
    local yTop = scrollChild._pvpColHeaderBottomY
    rowGap = rowGap or 0
    local prevBody = nil
    local layoutTail = nil
    for i = 1, #order do
        local sh = shells[order[i]]
        if sh and sh.header and sh.body then
            sh.header:ClearAllPoints()
            if prevBody then
                sh.header:SetPoint("TOPLEFT", prevBody, "BOTTOMLEFT", 0, -gap)
            elseif yTop then
                sh.header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", side, -yTop)
            else
                sh.header:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", side, 0)
            end
            sh.header:Show()
            sh.body:ClearAllPoints()
            sh.body:SetPoint("TOPLEFT", sh.header, "BOTTOMLEFT", 0, 0)
            if sh.body:IsShown() then
                ReflowPvpSectionRows(sh.body, rowGap)
                local bodyH = math.max(0.1, sh.body._pvpRunningH or sh.body._wnSectionFullH or sh.body:GetHeight() or 0.1)
                sh.body:SetHeight(bodyH)
                sh.body._wnSectionFullH = bodyH
                layoutTail = sh.body
            else
                sh.body:SetHeight(0.1)
            end
            prevBody = sh.body
        end
    end
    scrollChild._pvpLayoutTailBody = layoutTail
end

local function MeasureOverviewBlockH(parent, overviewStartYOffset, tailFrame, fallbackBar)
    local tail = tailFrame
    if (not tail or not tail.IsShown or not tail:IsShown()) and fallbackBar then
        tail = fallbackBar
    end
    if not tail or not parent.GetTop or not tail.GetBottom then return nil end
    local pTop = parent:GetTop()
    local bot = tail:GetBottom()
    if not pTop or not bot then return nil end
    local startWorldY = pTop - (overviewStartYOffset or 0)
    return math.max(1, startWorldY - bot)
end

local function HideOverviewProfHeaders()
    if not PUI or not PUI.profColHeaderLabels then return end
    for key, fs in pairs(PUI.profColHeaderLabels) do
        if type(key) == "string" and key:sub(1, #OVERVIEW_COL_PREFIX) == OVERVIEW_COL_PREFIX and fs and fs.Hide then
            fs:Hide()
        end
    end
end

local function EnsureColumnHeaderBar(bundle, parent, stackW, yTop, sideInset)
    sideInset = sideInset or 0
    local pool = bundle.overviewPool
    if not pool then
        pool = {}
        bundle.overviewPool = pool
    end
    local bar = pool.colHeaderBar
    if not bar then
        bar = TK.CreateHeaderStrip(parent, {
            mode = "compact",
            height = OVERVIEW_COL_HDR_H,
            iconSize = OVERVIEW_HDR_ICON,
            dividers = true,
            bottomRule = true,
            applyIcon = ApplyOverviewHeaderIcon,
        })
        bar._wnKeepOnTabSwitch = true
        pool.colHeaderBar = bar
    end
    bar:SetParent(parent)
    bar:SetHeight(OVERVIEW_COL_HDR_H)
    if bar.SetWidth then bar:SetWidth(math.max(1, stackW)) end
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", parent, "TOPLEFT", sideInset, -yTop)
    if bar.SetClipsChildren then bar:SetClipsChildren(false) end
    bar:Show()
    return bar, pool
end

local function EnsureOverviewRow(bundle, rowIdx, parent, rowW, sideInset)
    sideInset = sideInset or 0
    bundle.overviewRows = bundle.overviewRows or {}
    local row = bundle.overviewRows[rowIdx]
    local FactHdr = ns.UI and ns.UI.Factory
    if not row then
        row = FactHdr and FactHdr:CreateContainer(parent, rowW, OVERVIEW_ROW_H, false)
        if not row then
            row = CreateFrame("Frame", nil, parent)
            row:SetSize(rowW, OVERVIEW_ROW_H)
        end
        bundle.overviewRows[rowIdx] = row
    end
    row._wnKeepOnTabSwitch = true
    row:SetParent(parent)
    row:SetSize(rowW, OVERVIEW_ROW_H)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", sideInset, 0)
    if row.SetClipsChildren then row:SetClipsChildren(true) end
    if row.EnableMouse then row:EnableMouse(false) end
    row:Show()
    return row
end

local function EnsureOverviewCell(bundle, rowIdx, colIdx, row, col)
    bundle.overviewCells = bundle.overviewCells or {}
    bundle.overviewCells[rowIdx] = bundle.overviewCells[rowIdx] or {}
    local fs = bundle.overviewCells[rowIdx][colIdx]
    if not fs then
        fs = FontManager:CreateFontString(row, "body", "OVERLAY")
        bundle.overviewCells[rowIdx][colIdx] = fs
    end
    fs:SetParent(row)
    fs:SetWidth(col.width)
    fs:SetJustifyH(col.align == "RIGHT" and "RIGHT" or (col.align == "CENTER" and "CENTER" or "LEFT"))
    fs:SetWordWrap(false)
    fs:SetMaxLines(1)
    fs:ClearAllPoints()
    local x = bundle.overviewOffsets[colIdx] or 0
    local colRight = x + col.width
    if col.align == "RIGHT" then
        fs:SetPoint("RIGHT", row, "LEFT", colRight, 0)
    elseif col.align == "CENTER" then
        fs:SetPoint("CENTER", row, "LEFT", x + col.width * 0.5, 0)
    else
        fs:SetPoint("LEFT", row, "LEFT", x, 0)
    end
    fs:Show()
    return fs
end

local function HideOverviewRowsFrom(bundle, fromIdx)
    local rows = bundle and bundle.overviewRows
    if rows then
        for i = fromIdx, #rows do
            if rows[i] and rows[i].Hide then rows[i]:Hide() end
        end
    end
    local cells = bundle and bundle.overviewCells
    if cells then
        for i = fromIdx, #cells do
            local rowCells = cells[i]
            if rowCells then
                for c = 1, #rowCells do
                    if rowCells[c] and rowCells[c].Hide then rowCells[c]:Hide() end
                end
            end
        end
    end
end

local function HideLegacyRosterCard(bundle)
    if not bundle then return end
    if bundle.rosterCard then bundle.rosterCard:Hide() end
    if bundle.rosterHdrStrip then bundle.rosterHdrStrip:Hide() end
    if bundle.rosterSeasonFs then bundle.rosterSeasonFs:Hide() end
    if bundle.rosterExpandBtn then bundle.rosterExpandBtn:Hide() end
    if bundle.rosterMoreText then bundle.rosterMoreText:Hide() end
end

local function HideOverviewUI(bundle)
    HideLegacyRosterCard(bundle)
    if bundle.overviewSection then bundle.overviewSection:Hide() end
    if bundle.overviewSeasonLine then bundle.overviewSeasonLine:Hide() end
    if bundle.overviewSortBtn then bundle.overviewSortBtn:Hide() end
    if bundle.overviewPool and bundle.overviewPool.colHeaderBar then
        bundle.overviewPool.colHeaderBar:Hide()
    end
    if bundle.pvpSectionShells then
        for _, sh in pairs(bundle.pvpSectionShells) do
            if sh and sh.header and sh.header.Hide then sh.header:Hide() end
            if sh and sh.body and sh.body.Hide then sh.body:Hide() end
        end
    end
    HideOverviewProfHeaders()
    HideOverviewRowsFrom(bundle, 1)
    if bundle.overviewCurrentTint then bundle.overviewCurrentTint:Hide() end
    if bundle.overviewExpandBtn then bundle.overviewExpandBtn:Hide() end
    if bundle.overviewMoreText then bundle.overviewMoreText:Hide() end
end

local function PvpStackBodyWidth(scrollPaintW, contentSide)
    return math.max(1, scrollPaintW - 2 * contentSide)
end

local function EnsurePvpSectionShell(WN, bundle, parent, profile, opts)
    local CreateShell = ns.PvEUI and ns.PvEUI.CreateTabSectionShell
    if not CreateShell then return nil end
    bundle.pvpSectionShells = bundle.pvpSectionShells or {}
    local expandKey = opts.sectionUiKey
    if not expandKey and opts.visualOpts and opts.visualOpts.groupId then
        expandKey = "cgrp_" .. tostring(opts.visualOpts.groupId)
    end
    if expandKey then
        local existing = bundle.pvpSectionShells[expandKey]
        if existing and existing.body and existing.header then
            -- Reused shells must re-sync width: rows resize every paint (EnsureOverviewRow SetSize),
            -- but a header/body left at its creation width stays stale after a window resize.
            local stackW = opts.stackWidth
            existing.header:SetParent(parent)
            existing.header:ClearAllPoints()
            if stackW and existing.header.SetWidth then
                existing.header:SetWidth(math.max(1, stackW))
            end
            if opts.layoutTailFrame then
                existing.header:SetPoint("TOPLEFT", opts.layoutTailFrame, "BOTTOMLEFT", 0, -4)
            else
                existing.header:SetPoint("TOPLEFT", parent, "TOPLEFT", opts.sideMargin or 0, -(opts.totalLH and opts.totalLH.v or 0))
            end
            existing.header:Show()
            existing.body:SetParent(parent)
            existing.body:ClearAllPoints()
            if stackW and existing.body.SetWidth then
                existing.body:SetWidth(math.max(1, stackW))
            end
            existing.body:SetPoint("TOPLEFT", existing.header, "BOTTOMLEFT", 0, 0)
            existing.body._pvpRowsOrdered = {}
            existing.body:Show()
            return existing.body
        end
    end
    local body = CreateShell(WN, parent, profile, {
        tabPrefix = "pvp",
        refreshTab = "pvp",
        sectionShellRegistry = bundle.pvpSectionShells,
        chars = opts.chars,
        headerLabel = opts.headerLabel,
        sectionUiKey = opts.sectionUiKey,
        defaultExpanded = opts.defaultExpanded,
        headerAtlas = opts.headerAtlas,
        visualOpts = opts.visualOpts,
        layoutTailFrame = opts.layoutTailFrame,
        totalLH = opts.totalLH,
        scrollFrameRef = opts.scrollFrameRef,
        yTop = opts.totalLH and opts.totalLH.v or 0,
        sideMargin = opts.sideMargin,
        stackWidth = opts.stackWidth,
    })
    if body then
        body._pvpRowsOrdered = {}
    end
    return body
end

function M.DrawWarbandOverview(parent, bundle, ctx)
    HideLegacyRosterCard(bundle)

    local rosterRows
    if ns.PvPService and ns.PvPService.GetWarbandOverview then
        rosterRows = select(1, ns.PvPService:GetWarbandOverview())
    end
    rosterRows = rosterRows or {}

    local WN = M.WarbandNexus
    local profile = WN and WN.db and WN.db.profile
    local paintOrder = BuildPvpPaintOrder(WN, profile, rosterRows)
    if #paintOrder == 0 then
        HideOverviewUI(bundle)
        return 0
    end

    local overviewStartY = ctx.yOffset or 0
    local SIDE = ctx.SIDE or (ns.UI_LAYOUT and ns.UI_LAYOUT.SIDE_MARGIN) or 12
    local width = ctx.width or (parent:GetWidth() or 600)
    local yOffset = ctx.yOffset or 0
    local muted = ctx.muted or M.MutedHex()
    local bright = ctx.bright or M.BrightHex()
    local stackW = math.max(320, width - SIDE * 2)

    if bundle.overviewSection then bundle.overviewSection:Hide() end
    if bundle.overviewSortBtn then bundle.overviewSortBtn:Hide() end
    if bundle.overviewSeasonLine then bundle.overviewSeasonLine:Hide() end

    local measureFs = bundle.overviewMeasureFs
    if not measureFs then
        measureFs = FontManager:CreateFontString(parent, "body", "OVERLAY")
        measureFs:Hide()
        bundle.overviewMeasureFs = measureFs
    end
    local hdrMeasureFs = bundle.overviewMeasureHdrFs
    if not hdrMeasureFs then
        hdrMeasureFs = FontManager:CreateFontString(parent, "small", "OVERLAY")
        hdrMeasureFs:Hide()
        bundle.overviewMeasureHdrFs = hdrMeasureFs
    end

    local nameColW = MeasureIdentityNameWidth(measureFs, rosterRows)
    local identityMin = (ns.PvE_ComputeInlineColumnsStartPx and ns.PvE_ComputeInlineColumnsStartPx(nameColW))
        or (BuildIdentityLayout(nameColW).inlineStart or 320)
    local columns = MeasureStatColumns(measureFs, hdrMeasureFs, rosterRows)
    local colGap = OVERVIEW_COL_GAP
    local gridInlineStartX = identityMin
    -- TableKit scratch (reused every paint): offsets are absolute x from the row/strip left edge.
    local colWidths = bundle.overviewWidths or {}
    local colOffsets = bundle.overviewOffsets or {}
    local dividerXs = bundle.overviewDividerXs or {}
    bundle.overviewWidths = colWidths
    bundle.overviewOffsets = colOffsets
    bundle.overviewDividerXs = dividerXs
    local inlineTotal = TK.ResolveWidths(columns, nil, colWidths, colOffsets, gridInlineStartX, colGap)
        + OVERVIEW_COL_RIGHT_MARGIN
    local minScrollW = SIDE * 2 + gridInlineStartX + inlineTotal
    local viewportW = stackW + SIDE * 2
    local gridW = math.max(minScrollW, viewportW)
    local pvpStackW = math.max(PvpStackBodyWidth(gridW, SIDE), stackW)

    bundle.overviewColumns = columns
    bundle.overviewColGap = colGap
    bundle.overviewGridInlineStartX = gridInlineStartX
    bundle.overviewNameColW = nameColW
    TK.BuildDividerXs(colWidths, colOffsets, #columns, dividerXs)

    local mf = WN and WN.UI and WN.UI.mainFrame
    if mf then
        mf._pvpMinScrollWidth = math.max(mf._pvpMinScrollWidth or 0, gridW)
    end
    parent:SetWidth(gridW)

    parent._pvpSectionShellOrder = {}
    parent._pvpShellSectionGap = OVERVIEW_SECTION_GAP
    parent._wnPvpContentSide = SIDE
    if bundle.pvpSectionShells then
        for _, sh in pairs(bundle.pvpSectionShells) do
            if sh and sh.header and sh.header.Hide then sh.header:Hide() end
            if sh and sh.body and sh.body.Hide then sh.body:Hide() end
        end
    end

    local bar = EnsureColumnHeaderBar(bundle, parent, pvpStackW, yOffset, SIDE)
    parent._pvpColHeaderBar = bar
    HideOverviewProfHeaders()
    bar:SetColumns(columns, colWidths, colOffsets, #columns)
    yOffset = yOffset + OVERVIEW_COL_HDR_H + OVERVIEW_COL_HDR_PAD
    parent._pvpColHeaderBottomY = yOffset

    local overallBest = 0
    for i = 1, #rosterRows do
        overallBest = math.max(overallBest, rosterRows[i].bestRating or 0)
    end
    local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffffd700"
    local noData = muted .. "-|r"
    local bracketOrder = M.ROSTER_BRACKET_ORDER or {}
    local ApplyChrome = ns.PvEUI_ApplyCharacterListRowChrome
    local rowGap = (ns.UI_LAYOUT and ns.UI_LAYOUT.betweenRows) or 0
    local scrollFrameRef = parent:GetParent()
    local totalLH = { v = yOffset }
    local layoutTailForShell = bar
    local secBodies = {}
    local currentSecKey = nil
    local rowHost = nil
    local paintedRowIdx = 0
    local CS = ns.CharacterService
    local customGroupsOrdered = (profile and CS and CS.BuildOrderedCustomCharacterGroups)
        and CS:BuildOrderedCustomCharacterGroups(profile, CS:GetTabSortKey(profile, "pvp")) or {}

    local function sectionMetaForKey(sk)
        if sk == "pvp_fav" then
            return {
                chars = {},
                headerLabel = GetLocalizedText("HEADER_FAVORITES", "Favorites"),
                sectionUiKey = "pvpFavoritesExpanded",
                defaultExpanded = false,
                headerAtlas = "GM-icon-assistActive-hover",
                visualOpts = { sectionPreset = "gold" },
            }
        end
        if sk == "pvp_reg" then
            return {
                chars = {},
                headerLabel = GetLocalizedText("HEADER_CHARACTERS", "Characters"),
                sectionUiKey = "pvpCharactersExpanded",
                defaultExpanded = false,
                headerAtlas = "GM-icon-headCount",
                visualOpts = nil,
            }
        end
        local gid = PvpGroupIdFromSecKey(sk)
        if gid then
            local gName = tostring(gid)
            for gi = 1, #customGroupsOrdered do
                if tostring(customGroupsOrdered[gi].id) == tostring(gid) then
                    gName = customGroupsOrdered[gi].name or gName
                    break
                end
            end
            local goldStyle = CS and CS.IsProfileCustomSectionHighlighted
                and CS:IsProfileCustomSectionHighlighted(profile, gid)
            return {
                chars = {},
                headerLabel = gName,
                sectionUiKey = nil,
                defaultExpanded = false,
                headerAtlas = goldStyle and "GM-icon-assistActive-hover" or "GM-icon-headCount",
                visualOpts = {
                    sectionPreset = goldStyle and "gold" or "accent",
                    useCharacterGroupExpand = true,
                    groupId = gid,
                },
            }
        end
        return nil
    end

    local function charsForSection(sk)
        local list = {}
        for poi = 1, #paintOrder do
            if paintOrder[poi].secKey == sk then
                list[#list + 1] = paintOrder[poi].row
            end
        end
        return list
    end

    for pi = 1, #paintOrder do
        local ent = paintOrder[pi]
        local sk = ent.secKey
        if sk ~= currentSecKey then
            if currentSecKey and rowHost then
                FinalizePvpSectionBody(rowHost, profile, currentSecKey, rowGap)
                if rowHost:IsShown() then
                    layoutTailForShell = rowHost
                end
            end
            currentSecKey = sk
            local sectionMeta = sectionMetaForKey(sk)
            if sectionMeta then
                TrackPvpShellOrder(parent, PvpExpandKeyFromMeta(sectionMeta))
            end
            if not secBodies[sk] and sectionMeta then
                secBodies[sk] = EnsurePvpSectionShell(WN, bundle, parent, profile, {
                    chars = charsForSection(sk),
                    headerLabel = sectionMeta.headerLabel,
                    sectionUiKey = sectionMeta.sectionUiKey,
                    defaultExpanded = sectionMeta.defaultExpanded,
                    headerAtlas = sectionMeta.headerAtlas,
                    visualOpts = sectionMeta.visualOpts,
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLH,
                    scrollFrameRef = scrollFrameRef,
                    sideMargin = SIDE,
                    stackWidth = pvpStackW,
                })
            end
            rowHost = secBodies[sk]
            if rowHost then
                rowHost._pvpRowsOrdered = {}
            end
        end
        if not rowHost then
            rowHost = parent
            rowHost._pvpRowsOrdered = rowHost._pvpRowsOrdered or {}
        end

        paintedRowIdx = paintedRowIdx + 1
        local row = EnsureOverviewRow(bundle, paintedRowIdx, rowHost, pvpStackW, 0)
        rowHost._pvpRowsOrdered[#rowHost._pvpRowsOrdered + 1] = row
        if ns.UI_SyncGridColumnDividers and #dividerXs > 0 then
            ns.UI_SyncGridColumnDividers(row, dividerXs, OVERVIEW_ROW_H)
        end

        local rrow = ent.row
        local charKey = rrow.charKey
        local isFavorite = CS and WN and CS:IsFavoriteCharacter(WN, charKey)
        if ApplyChrome then
            ApplyChrome(WN, row, {
                name = rrow.name,
                realm = rrow.realm,
                classFile = rrow.classFile,
                level = rrow.level,
                itemLevel = rrow.itemLevel,
            }, {
                rowIndex = paintedRowIdx,
                charKey = charKey,
                isFavorite = isFavorite,
                isCurrentChar = rrow.isCurrent == true,
                nameWidth = nameColW,
                skipChevronPrefix = true,
            })
        end

        for ci = 1, #columns do
            local col = columns[ci]
            local cell = EnsureOverviewCell(bundle, paintedRowIdx, ci, row, col)
            if col.key == "honor" then
                local t = M.FormatRosterCurrencyQty(M.RosterCurrencyQuantity(rrow.charKey, M.ROSTER_HONOR_CURRENCY_ID))
                cell:SetText(t and (bright .. t .. "|r") or noData)
            elseif col.key == "conquest" then
                local t = M.FormatRosterCurrencyQty(M.RosterCurrencyQuantity(rrow.charKey, M.ROSTER_CONQUEST_CURRENCY_ID))
                cell:SetText(t and (bright .. t .. "|r") or noData)
            elseif col.key == "weekly" then
                local won, played = 0, 0
                local hasBrackets = type(rrow.brackets) == "table"
                if hasBrackets and not rrow.weeklyStale then
                    for bi = 1, #bracketOrder do
                        local b = rrow.brackets[bracketOrder[bi]]
                        if b then
                            won = won + (tonumber(b.weeklyWon) or 0)
                            played = played + (tonumber(b.weeklyPlayed) or 0)
                        end
                    end
                end
                cell:SetText(hasBrackets and (muted .. string.format("%d / %d", won, played) .. "|r") or noData)
            else
                local b = type(rrow.brackets) == "table" and rrow.brackets[col.key] or nil
                local rating = b and tonumber(b.rating) or nil
                if rating and rating > 0 then
                    cell:SetText((rating == overallBest) and (goldHex .. rating .. "|r") or (bright .. rating .. "|r"))
                elseif b then
                    cell:SetText(muted .. "0|r")
                else
                    cell:SetText(noData)
                end
            end
        end
    end

    if currentSecKey and rowHost then
        FinalizePvpSectionBody(rowHost, profile, currentSecKey, rowGap)
        if rowHost:IsShown() then
            layoutTailForShell = rowHost
        end
    end
    ReflowPvpSectionShellChain(parent, bundle, SIDE, rowGap)
    HideOverviewRowsFrom(bundle, paintedRowIdx + 1)

    if bundle.overviewExpandBtn then bundle.overviewExpandBtn:Hide() end
    if bundle.overviewMoreText then bundle.overviewMoreText:Hide() end

    local blockH = MeasureOverviewBlockH(parent, overviewStartY, parent._pvpLayoutTailBody, bar)
    if not blockH then
        local usedSections = {}
        for pi2 = 1, #paintOrder do
            usedSections[paintOrder[pi2].secKey] = true
        end
        local sectionCount = 0
        for _ in pairs(usedSections) do
            sectionCount = sectionCount + 1
        end
        blockH = OVERVIEW_COL_HDR_H + OVERVIEW_COL_HDR_PAD
        blockH = blockH + paintedRowIdx * (OVERVIEW_ROW_H + rowGap)
        local sectionHdrH = (ns.UI_LAYOUT and ns.UI_LAYOUT.SECTION_COLLAPSE_HEADER_HEIGHT) or 36
        blockH = blockH + sectionCount * (sectionHdrH + OVERVIEW_SECTION_GAP)
    end
    -- Inside the roster grid sections stay 4 apart (PvE parity); the block itself ends on a PAGE_STACK section gap.
    return blockH + (M.SECTION_GAP or OVERVIEW_SECTION_GAP)
end
