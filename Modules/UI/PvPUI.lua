--[[
    Warband Nexus - PvP Tab
    Card layout: three progress cards (Level / Honor / Conquest), five rated-bracket
    stat cards, and a mode-filtered recent match log.
    Read-only view over PvPService (db.global.pvpProgress / pvpMatches);
    refreshes on WN_PVP_UPDATED.

    Lifecycle note: PopulateContent parks unflagged scrollChild children into
    the recycle bin on every pass — every cached top-level frame here carries
    _wnKeepOnTabSwitch and is re-parented + re-anchored on each draw.
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager
local COLORS = ns.UI_COLORS

local L = ns.L

local M = ns.PvPUI or {}
ns.PvPUI = M
M.ns = ns
M.WarbandNexus = WarbandNexus
M.FontManager = FontManager
M.COLORS = COLORS
M.L = L

local CARD_PAD = 14
local ROW_H = 24
local HEADER_BLOCK_H = 30 -- card title row height inside a card
local SECTION_GAP = 10
local CARD_GAP = 10
local BAR_H = 16
local TITLE_ICON_SIZE = 20
local TITLE_ICON_GAP = 6

local BRACKET_LABELS = {
    ["2v2"] = "2v2",
    ["3v3"] = "3v3",
    rbg = (L and L["PVP_MODE_RBG"]) or "Rated BG",
    shuffle = (L and L["PVP_MODE_SHUFFLE"]) or "Solo Shuffle",
    blitz = (L and L["PVP_MODE_BLITZ"]) or "Blitz",
    arena = (L and L["PVP_MODE_ARENA"]) or "Arena",
    bg = (L and L["PVP_MODE_BG"]) or "Battleground",
    unknown = "?",
}

-- Recent-match filter keys (match logic lives in PvPService.RECENT_FILTER_DEFS).
local function RecentFilterLabel(key)
    if key == "all" then return (ALL) or "All" end
    if key == "2v2" or key == "3v3" then return key end
    return BRACKET_LABELS[key] or key
end

local RECENT_TITLE_H = 22
local RECENT_FILTER_GAP = 8
local RECENT_FILTER_BTN_H = 26
local RECENT_FILTER_BTN_GAP = 6
local RECENT_FILTER_PAD_H = 8
local RECENT_SUBBAR_LAYOUT_KEY = 1
local RECENT_LIST_DIVIDER_H = 1
local RECENT_FOOTER_H = 36
local RECENT_MATCHES_COLLAPSED = 20
local RECENT_OUTCOME_STRIPE_W = 3
local RECENT_OUTCOME_STRIPE_GAP = 5
local RECENT_OUTCOME_STRIPE_INSET = 2
local PROGRESS_CARD_MIN_W = 160

local function BuildRecentColumns(innerW)
    local gap = 6
    local stripeReserve = RECENT_OUTCOME_STRIPE_W + RECENT_OUTCOME_STRIPE_GAP
    local wOutcome = math.max(56, math.floor(innerW * 0.13))
    local wMode = math.max(64, math.floor(innerW * 0.14))
    local wDelta = math.max(44, math.floor(innerW * 0.09))
    local wDur = math.max(44, math.floor(innerW * 0.08))
    local wAgo = math.max(40, math.floor(innerW * 0.08))
    local wMap = math.max(80, innerW - (wOutcome + wMode + wDelta + wDur + wAgo + gap * 5))
    local x = stripeReserve
    local cols = {}
    local function add(w, justify)
        cols[#cols + 1] = { x = x, w = w, justify = justify or "LEFT" }
        x = x + w + gap
    end
    add(wOutcome, "LEFT")
    add(wMode, "LEFT")
    add(wDelta, "RIGHT")
    add(wDur, "RIGHT")
    add(wMap, "LEFT")
    add(wAgo, "LEFT")
    return cols
end

local RATED_CARD_STAT_H = 18
local RATED_CARD_MIN_W = 108

-- UI_GetTextRoleHex returns the FULL "|cffXXXXXX" escape — never re-prefix it.
local function MutedHex()
    return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffaaaaaa"
end

local function BrightHex()
    return (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Bright")) or "|cffeeeeee"
end

local function OutcomeMarkup(outcome)
    if outcome == "win" then
        local hex = (ns.UI_GetSemanticGreenHex and ns.UI_GetSemanticGreenHex()) or "|cff33cc55"
        return hex .. ((VICTORY) or "Victory") .. "|r"
    elseif outcome == "loss" then
        return "|cffcc4433" .. ((DEFEAT) or "Defeat") .. "|r"
    elseif outcome == "draw" then
        return MutedHex() .. ((L and L["PVP_DRAW"]) or "Draw") .. "|r"
    end
    return MutedHex() .. "?|r"
end

local function FormatDuration(sec)
    sec = tonumber(sec)
    if not sec or sec <= 0 then return "" end
    return string.format("%d:%02d", math.floor(sec / 60), math.floor(sec % 60))
end

local function FormatTimeLeft(sec)
    sec = tonumber(sec)
    if not sec or sec <= 0 then return nil end
    local days = math.floor(sec / 86400)
    local hours = math.floor((sec % 86400) / 3600)
    if days > 0 then
        return string.format("%dd %dh", days, hours)
    end
    local mins = math.floor((sec % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %dm", hours, mins)
    end
    return string.format("%dm", math.max(1, mins))
end

local function FormatTimeAgo(ts)
    ts = tonumber(ts)
    if not ts then return "" end
    local diff = math.max(0, time() - ts)
    if diff < 3600 then
        return string.format("%dm", math.floor(diff / 60))
    elseif diff < 86400 then
        return string.format("%dh", math.floor(diff / 3600))
    end
    return string.format("%dd", math.floor(diff / 86400))
end

-- Cached top-level card: survives PopulateContent teardown via _wnKeepOnTabSwitch,
-- re-parented + re-themed on every draw (tab returns and theme toggles).
local function EnsureCard(bundle, key, parent, height)
    local card = bundle[key]
    if not card then
        card = (ns.UI_CreateCard and ns.UI_CreateCard(parent, height or 100))
            or (ns.UI.Factory and ns.UI.Factory:CreateContainer(parent, 200, height or 100, true))
        card._wnKeepOnTabSwitch = true
        bundle[key] = card
    end
    card:SetParent(parent)
    if ns.UI_ShouldUseBlizzardChrome and ns.UI_ShouldUseBlizzardChrome() then
        if ns.UI_ApplyClassicCardPanelChrome then
            ns.UI_ApplyClassicCardPanelChrome(card)
        end
    elseif ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(card)
    end
    card:Show()
    return card
end

local function EnsureCardTitle(bundle, key, card, text)
    local fs = bundle[key]
    if not fs then
        fs = FontManager:CreateFontString(card, "title", "OVERLAY")
        bundle[key] = fs
    end
    fs:ClearAllPoints()
    fs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD)
    fs:SetText(text)
    ns.UI_SetTextColorRole(fs, "Bright")
    fs:Show()
    return fs
end

local function GetPvPProgressBarChrome()
    local track = (ns.UI_ResolveSurfaceTierColor and ns.UI_ResolveSurfaceTierColor("viewport"))
        or COLORS.surfaceViewport or { 0.05, 0.05, 0.07, 0.95 }
    local border = (ns.UI_GetAccentBorderRGBA and ns.UI_GetAccentBorderRGBA(0.5))
        or (ns.UI_GetBorderStrokeColor and ns.UI_GetBorderStrokeColor())
        or { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.5 }
    return track, border
end

-- Label + status bar + right-aligned "cur / max" value line.
--- opts.uncapped: show progress bar track with no cap; max slot uses L["PVP_INFINITY"].
local function EnsureBarRow(bundle, key, card, y, labelText, cur, maxV, barColor, opts)
    opts = type(opts) == "table" and opts or {}
    local trackBg, borderCol = GetPvPProgressBarChrome()
    local row = bundle[key]
    if not row then
        row = {}
        row.label = FontManager:CreateFontString(card, "body", "OVERLAY")
        row.value = FontManager:CreateFontString(card, "body", "OVERLAY")
        row.bar = ns.UI_CreateStatusBar
            and ns.UI_CreateStatusBar(card, 200, BAR_H, trackBg, borderCol)
        bundle[key] = row
    elseif row.bar and ns.UI_ApplyVisuals and not row.bar._wnBlizzardChrome then
        ns.UI_ApplyVisuals(row.bar, trackBg, borderCol)
    end
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    row.label:SetText(labelText)
    ns.UI_SetTextColorRole(row.label, "Normal")
    row.label:Show()

    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    row.value:SetJustifyH("RIGHT")
    if opts.uncapped then
        local infText = (L and L["PVP_INFINITY"]) or "oo"
        row.value:SetText(BrightHex() .. tostring(cur or 0) .. "|r" .. MutedHex() .. " / " .. infText .. "|r")
    elseif maxV and maxV > 0 then
        row.value:SetText(BrightHex() .. tostring(cur) .. "|r" .. MutedHex() .. " / " .. tostring(maxV) .. "|r")
    else
        row.value:SetText(BrightHex() .. tostring(cur) .. "|r")
    end
    row.value:Show()

    if row.bar then
        row.bar:ClearAllPoints()
        row.bar:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(y + 20))
        row.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -(y + 20))
        row.bar:SetHeight(BAR_H)
        if opts.uncapped then
            row.bar:SetMinMaxValues(0, 1)
            row.bar:SetValue(0)
            row.bar:Show()
        elseif maxV and maxV > 0 then
            row.bar:SetMinMaxValues(0, maxV)
            row.bar:SetValue(math.min(cur or 0, maxV))
            row.bar:Show()
        else
            row.bar:SetMinMaxValues(0, 1)
            row.bar:SetValue(0)
            row.bar:Hide()
        end
        if barColor then
            row.bar:SetStatusBarColor(barColor[1], barColor[2], barColor[3], barColor[4] or 1)
        end
    end
    return row
end

-- Cached row of column cells: bundle[listKey][rowIdx] = { fs1, fs2, ... }.
local function EnsureRowCells(bundle, listKey, rowIdx, card, cols, extraTopOffset)
    bundle[listKey] = bundle[listKey] or {}
    local cells = bundle[listKey][rowIdx]
    if not cells then
        cells = {}
        for c = 1, #cols do
            cells[c] = FontManager:CreateFontString(card, "body", "OVERLAY")
        end
        bundle[listKey][rowIdx] = cells
    end
    local rowY = CARD_PAD + HEADER_BLOCK_H + (extraTopOffset or 0) + (rowIdx - 1) * ROW_H
    local rowCenterY = -rowY - (ROW_H * 0.5)
    for c = 1, #cols do
        local fs = cells[c]
        fs:ClearAllPoints()
        local colLeft = CARD_PAD + cols[c].x
        local colW = cols[c].w
        local justify = cols[c].justify or "LEFT"
        if justify == "RIGHT" then
            fs:SetPoint("RIGHT", card, "TOPLEFT", colLeft + colW, rowCenterY)
        elseif justify == "CENTER" then
            fs:SetPoint("CENTER", card, "TOPLEFT", colLeft + colW * 0.5, rowCenterY)
        else
            fs:SetPoint("LEFT", card, "TOPLEFT", colLeft, rowCenterY)
        end
        fs:SetWidth(colW)
        fs:SetJustifyH(justify)
        if fs.SetJustifyV then
            fs:SetJustifyV("MIDDLE")
        end
        -- Single-line cells: long headers/values truncate instead of wrapping into the next row
        fs:SetWordWrap(false)
        fs:SetMaxLines(1)
        fs:Show()
    end
    return cells
end

local function HideRowsFrom(bundle, listKey, fromIdx)
    local rows = bundle[listKey]
    if not rows then return end
    for i = fromIdx, #rows do
        local cells = rows[i]
        for c = 1, #cells do
            cells[c]:Hide()
        end
    end
end

-- One rated-bracket stat card (2v2, 3v3, …): title + rating / season best / weekly W-P rows.
local function EnsureBracketCard(bundle, bracketKey, parent, width, height)
    local card = EnsureCard(bundle, "ratedCard_" .. bracketKey, parent, height)
    card:SetWidth(width)
    card:SetHeight(height)
    return card
end

local function EnsureBracketStatRow(bundle, bracketKey, rowIdx, card, y, labelText, valueText)
    bundle.ratedStatRows = bundle.ratedStatRows or {}
    bundle.ratedStatRows[bracketKey] = bundle.ratedStatRows[bracketKey] or {}
    local row = bundle.ratedStatRows[bracketKey][rowIdx]
    if not row then
        row = {
            label = FontManager:CreateFontString(card, "body", "OVERLAY"),
            value = FontManager:CreateFontString(card, "body", "OVERLAY"),
        }
        bundle.ratedStatRows[bracketKey][rowIdx] = row
    end
    row.label:ClearAllPoints()
    row.label:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    row.label:SetText(labelText)
    ns.UI_SetTextColorRole(row.label, "Muted")
    row.label:Show()

    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    row.value:SetJustifyH("RIGHT")
    row.value:SetText(valueText)
    row.value:Show()
    return row
end

local function EnsureListDivider(bundle, key, card, y)
    local line = bundle[key]
    if not line then
        line = card:CreateTexture(nil, "ARTWORK")
        bundle[key] = line
    end
    local bc = COLORS.border or COLORS.accent or { 0.5, 0.5, 0.55, 0.45 }
    line:SetColorTexture(bc[1], bc[2], bc[3], bc[4] or 0.45)
    line:ClearAllPoints()
    line:SetHeight(RECENT_LIST_DIVIDER_H)
    line:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -y)
    line:SetPoint("TOPRIGHT", card, "TOPRIGHT", -CARD_PAD, -y)
    line:Show()
end

-- WARBAND ROSTER (one row per tracked character; data from PvPService:GetWarbandOverview)

local ROSTER_BRACKET_ORDER = { "2v2", "3v3", "rbg", "shuffle", "blitz" }
local ROSTER_BRACKET_HEADERS = { "2v2", "3v3", "RBG", "SS", "BL" }
local ROSTER_HONOR_CURRENCY_ID = 1792
local ROSTER_CONQUEST_CURRENCY_ID = 1602

local ROSTER_STAT_HEADER_ICONS = {
    honor = {
        currencyID = ROSTER_HONOR_CURRENCY_ID,
        iconPaths = {
            "Interface\\Icons\\PVPCurrency-Honor-Alliance",
            "Interface\\Icons\\PVPCurrency-Honor-Horde",
        },
        iconFallback = "Interface\\Icons\\PVPCurrency-Honor-Alliance",
    },
    conquest = {
        currencyID = ROSTER_CONQUEST_CURRENCY_ID,
        iconPaths = {
            "Interface\\Icons\\PVPCurrency-Conquest-Alliance",
            "Interface\\Icons\\PVPCurrency-Conquest-Horde",
        },
        iconFallback = "Interface\\Icons\\PVPCurrency-Conquest-Alliance",
    },
    ["2v2"] = {
        iconAtlases = { "pvpqueue-sidebar-icon-arena-2v2", "PVPMatchmaking-Ico-2v2" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\Achievement_PVP_A_02",
        headerIconSize = 16,
    },
    ["3v3"] = {
        iconAtlases = { "pvpqueue-sidebar-icon-arena-3v3", "PVPMatchmaking-Ico-3v3" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\Achievement_PVP_A_03",
        headerIconSize = 18,
    },
    rbg = {
        iconAtlases = { "pvpqueue-sidebar-icon-ratedbattlegroup", "PVPMatchmaking-Ico-RatedBattleground", "pvpqueue-sidebar-icon-battleground" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\Achievement_PVP_H_13",
        headerIconSize = 20,
    },
    shuffle = {
        iconAtlases = { "pvpqueue-sidebar-icon-shuffle", "PVPMatchmaking-Ico-Shuffle" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\Achievement_PVP_G_03",
        headerIconSize = 22,
    },
    blitz = {
        iconAtlases = { "pvpqueue-sidebar-icon-solorbg", "PVPMatchmaking-Ico-SoloRBG", "pvpmatchmaking-icon-solorbg" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\Achievement_PVP_G_01",
        headerIconSize = 24,
    },
    weekly = {
        iconPaths = { "Interface\\Icons\\INV_Scroll_03" },
        iconAtlases = { "questlog-questtypeicon-weekly", "questlog-questtypeicon-daily" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\INV_Scroll_03",
    },
}

local PROGRESS_TITLE_ICONS = {
    level = {
        iconAtlases = { "honorsystem-icon-prestige-11", "honorsystem-icon-honorlevel", "pvpqueue-sidebar-honorlevel" },
        iconIsAtlas = true,
        iconFallback = "Interface\\Icons\\Achievement_PVP_A_01",
    },
    honor = { currencyID = ROSTER_HONOR_CURRENCY_ID },
    conquest = { currencyID = ROSTER_CONQUEST_CURRENCY_ID },
}

local function GetRosterCurrencyIconDef(currencyID)
    if not currencyID or not C_CurrencyInfo or not C_CurrencyInfo.GetCurrencyInfo then return nil end
    local ok, info = pcall(C_CurrencyInfo.GetCurrencyInfo, currencyID)
    if ok and info and info.iconFileID then
        return { icon = info.iconFileID, iconIsAtlas = false }
    end
    return nil
end

local function RosterHeaderIconIsDrawn(iconTex)
    if not iconTex then return false end
    if iconTex.GetAtlas then
        local atlas = iconTex:GetAtlas()
        if atlas and atlas ~= "" then return true end
    end
    if iconTex.GetTexture and iconTex:GetTexture() then return true end
    return false
end

local function TryRosterHeaderFileIcon(iconTex, path, size)
    if not iconTex or not path or path == "" or not iconTex.SetTexture then return false end
    if iconTex.SetAtlas then pcall(iconTex.SetAtlas, iconTex, nil) end
    iconTex:SetTexture(nil)
    if not pcall(iconTex.SetTexture, iconTex, path) then return false end
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconTex:SetSize(size or TITLE_ICON_SIZE, size or TITLE_ICON_SIZE)
    if ns.UI_EnsureTextureFullColor then
        ns.UI_EnsureTextureFullColor(iconTex)
    else
        iconTex:SetVertexColor(1, 1, 1, 1)
    end
    iconTex:Show()
    return RosterHeaderIconIsDrawn(iconTex)
end

local function TryRosterHeaderAtlas(iconTex, atlasName, size)
    if not iconTex or not iconTex.SetAtlas or not atlasName or atlasName == "" then return false end
    iconTex:SetTexture(nil)
    local modes = { false, true }
    for mi = 1, #modes do
        if pcall(iconTex.SetAtlas, iconTex, atlasName, modes[mi]) and RosterHeaderIconIsDrawn(iconTex) then
            iconTex:SetSize(size or TITLE_ICON_SIZE, size or TITLE_ICON_SIZE)
            if ns.UI_EnsureTextureFullColor then
                ns.UI_EnsureTextureFullColor(iconTex)
            else
                iconTex:SetVertexColor(1, 1, 1, 1)
            end
            iconTex:Show()
            return true
        end
        iconTex:SetTexture(nil)
    end
    return false
end

local function ApplyRosterHeaderIconTexture(iconTex, iconDef, iconSize)
    if not iconTex or not iconDef then return end
    local size = iconSize or TITLE_ICON_SIZE
    iconTex:Hide()
    iconTex:SetTexture(nil)

    local PUI = ns.ProfessionsUI
    if PUI and PUI.ApplyProfessionHeaderIconTexture then
        PUI.ApplyProfessionHeaderIconTexture(iconTex, iconDef)
        if PUI.ProfessionHeaderIconIsDrawn and PUI.ProfessionHeaderIconIsDrawn(iconTex) then
            iconTex:SetSize(size, size)
            return
        end
        iconTex:Hide()
        iconTex:SetTexture(nil)
    end

    if iconDef.icon and iconDef.iconIsAtlas == false and type(iconDef.icon) == "number" then
        iconTex:SetTexture(iconDef.icon)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        iconTex:SetSize(size, size)
        if ns.UI_EnsureTextureFullColor then ns.UI_EnsureTextureFullColor(iconTex) end
        iconTex:Show()
        if RosterHeaderIconIsDrawn(iconTex) then return end
    end

    local paths = iconDef.iconPaths
    if type(paths) == "table" then
        for pi = 1, #paths do
            if TryRosterHeaderFileIcon(iconTex, paths[pi], size) then return end
        end
    end
    if iconDef.iconFallback and TryRosterHeaderFileIcon(iconTex, iconDef.iconFallback, size) then return end

    local atlases = iconDef.iconAtlases
    if type(atlases) == "table" then
        for ai = 1, #atlases do
            if TryRosterHeaderAtlas(iconTex, atlases[ai], size) then return end
        end
    end
    if type(iconDef.icon) == "string" and TryRosterHeaderFileIcon(iconTex, iconDef.icon, size) then return end
end

local function ResolveProgressTitleIconDef(iconDef)
    if not iconDef then return nil end
    if iconDef.currencyID then
        return GetRosterCurrencyIconDef(iconDef.currencyID)
    end
    return iconDef
end

--- Card title with optional left icon (progress cards, rated bracket cards).
local function EnsureCardTitleWithIcon(bundle, titleKey, iconKey, card, text, iconDef)
    local fs = bundle[titleKey]
    if not fs then
        fs = FontManager:CreateFontString(card, "title", "OVERLAY")
        bundle[titleKey] = fs
    end
    fs:SetParent(card)
    local resolved = ResolveProgressTitleIconDef(iconDef)
    local iconTex = bundle[iconKey]
    if resolved then
        if not iconTex then
            iconTex = card:CreateTexture(nil, "ARTWORK")
            bundle[iconKey] = iconTex
        end
        iconTex:SetParent(card)
        iconTex:SetSize(TITLE_ICON_SIZE, TITLE_ICON_SIZE)
        iconTex:ClearAllPoints()
        iconTex:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -(CARD_PAD + 1))
        ApplyRosterHeaderIconTexture(iconTex, resolved)
        iconTex:Show()
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", iconTex, "RIGHT", TITLE_ICON_GAP, 0)
        fs:SetPoint("TOP", iconTex, "TOP", 0, 0)
        fs:SetPoint("RIGHT", card, "RIGHT", -CARD_PAD, 0)
        fs:SetJustifyH("LEFT")
    else
        if iconTex then iconTex:Hide() end
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -CARD_PAD)
    end
    fs:SetText(text)
    ns.UI_SetTextColorRole(fs, "Bright")
    fs:Show()
    return fs
end

local function RosterHonorHeaderLabel()
    return (HONOR) or "Honor"
end

local function RosterBracketHeaderLabel(bkey)
    if bkey == "shuffle" then
        return (L and L["PVP_HEADER_SHUFFLE"]) or "Shuffle"
    elseif bkey == "blitz" then
        return (L and L["PVP_MODE_BLITZ"]) or "Blitz"
    end
    for i = 1, #ROSTER_BRACKET_ORDER do
        if ROSTER_BRACKET_ORDER[i] == bkey then
            return ROSTER_BRACKET_HEADERS[i] or bkey
        end
    end
    return bkey
end

local function RosterConquestHeaderLabel()
    return (L and L["PVP_CONQUEST"]) or "Conquest"
end

local function RosterRealmHeaderLabel()
    return (L and L["CUSTOM_HEADER_COL_REALM"]) or "Realm"
end

local function RosterCurrencyQuantity(charKey, currencyID)
    if not charKey or not currencyID or not WarbandNexus or not WarbandNexus.GetCurrencyData then
        return nil
    end
    local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, currencyID, charKey)
    if not ok or not cd then return nil end
    return tonumber(cd.quantity)
end

local function FormatRosterCurrencyQty(qty)
    qty = tonumber(qty)
    if not qty then return nil end
    if qty >= 1e9 then return string.format("%.2fB", qty / 1e9) end
    if qty >= 1e6 then return string.format("%.2fM", qty / 1e6) end
    if qty >= 1e4 then return string.format("%.1fK", qty / 1e3) end
    return tostring(math.floor(qty + 0.5))
end
-- Warband overview grid: Modules/UI/PvPUI_Overview.lua

local function TogglePvPRosterExpanded()
    if not ns._pvpExpandedStates then
        ns._pvpExpandedStates = {}
    end
    local key = "warbandOverview"
    ns._pvpExpandedStates[key] = not ns._pvpExpandedStates[key]
    if WarbandNexus and ns.Constants and ns.Constants.EVENTS then
        WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
            tab = "pvp",
            skipCooldown = true,
        })
    end
end

-- MATCH DETAIL TOOLTIP (Recent Matches row hover; data from entry.score)

local function FormatBigNumber(n)
    n = tonumber(n)
    if not n then return "" end
    if n >= 1e9 then return string.format("%.2fB", n / 1e9) end
    if n >= 1e6 then return string.format("%.2fM", n / 1e6) end
    if n >= 1e4 then return string.format("%.1fK", n / 1e3) end
    return tostring(math.floor(n + 0.5))
end

local function MatchHasTooltipData(m)
    if not m then return false end
    local s = m.score
    if type(s) ~= "table" then return false end
    return s.killingBlows ~= nil or s.deaths ~= nil or s.damageDone ~= nil
        or s.healingDone ~= nil or s.honorGained ~= nil
        or s.prematchMMR ~= nil or s.postmatchMMR ~= nil or s.mmrChange ~= nil
end

local function ShowMatchTooltip(owner, m)
    if not (GameTooltip and MatchHasTooltipData(m)) then return end
    local s = m.score
    local tr, tg, tb = 1, 0.82, 0.2
    if ns.UI_GetTooltipTitleColor then tr, tg, tb = ns.UI_GetTooltipTitleColor() end
    local lr, lg, lb = 0.7, 0.7, 0.7
    if ns.UI_GetTooltipLabelColor then lr, lg, lb = ns.UI_GetTooltipLabelColor() end
    local br, bg, bb = 0.9, 0.9, 0.9
    if ns.UI_GetTooltipBodyColor then br, bg, bb = ns.UI_GetTooltipBodyColor() end

    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    local modeLabel = BRACKET_LABELS[m.mode] or m.mode or "?"
    GameTooltip:AddLine(modeLabel, tr, tg, tb)
    if m.mapName then
        GameTooltip:AddLine(m.mapName, br, bg, bb)
    end

    local function addStat(label, value)
        if value == nil then return end
        GameTooltip:AddDoubleLine(label, tostring(value), lr, lg, lb, br, bg, bb)
    end
    addStat((L and L["PVP_TT_KILLING_BLOWS"]) or "Killing Blows", s.killingBlows)
    addStat((L and L["PVP_TT_DEATHS"]) or "Deaths", s.deaths)
    if s.damageDone ~= nil then
        addStat((L and L["PVP_TT_DAMAGE"]) or "Damage", FormatBigNumber(s.damageDone))
    end
    if s.healingDone ~= nil then
        addStat((L and L["PVP_TT_HEALING"]) or "Healing", FormatBigNumber(s.healingDone))
    end
    addStat((L and L["PVP_TT_HONOR_GAINED"]) or "Honor Gained", s.honorGained)

    local pre, post = tonumber(s.prematchMMR), tonumber(s.postmatchMMR)
    if not post and pre and tonumber(s.mmrChange) then
        post = pre + tonumber(s.mmrChange)
    end
    if pre or post then
        local delta = (post and pre) and (post - pre) or tonumber(s.mmrChange)
        local deltaStr = ""
        if delta and delta ~= 0 then
            local hex = delta > 0
                and ((ns.UI_GetSemanticGreenHex and ns.UI_GetSemanticGreenHex()) or "|cff33cc55")
                or "|cffcc4433"
            deltaStr = string.format(" %s(%s%d)|r", hex, delta > 0 and "+" or "", delta)
        end
        GameTooltip:AddDoubleLine((L and L["PVP_TT_MMR"]) or "MMR",
            string.format("%s > %s%s", pre and tostring(pre) or "?", post and tostring(post) or "?", deltaStr),
            lr, lg, lb, br, bg, bb)
    end
    GameTooltip:Show()
end

-- Invisible pooled hover-catcher over one recent-match row (cells are FontStrings).
local function EnsureRecentHitFrame(bundle, idx, card, rowY, innerW)
    bundle.recentHits = bundle.recentHits or {}
    local hit = bundle.recentHits[idx]
    if not hit then
        hit = (ns.UI.Factory and ns.UI.Factory:CreateContainer(card, innerW, ROW_H, false))
        if not hit then return nil end
        hit:EnableMouse(true)
        hit:SetScript("OnEnter", function(self)
            if self._wnMatch then
                ShowMatchTooltip(self, self._wnMatch)
            end
        end)
        hit:SetScript("OnLeave", function()
            if GameTooltip then GameTooltip:Hide() end
        end)
        bundle.recentHits[idx] = hit
    end
    hit:SetParent(card)
    hit:ClearAllPoints()
    hit:SetPoint("TOPLEFT", card, "TOPLEFT", CARD_PAD, -rowY)
    hit:SetSize(math.max(1, innerW), ROW_H)
    hit:Show()
    return hit
end

local function HideRecentHitsFrom(bundle, fromIdx)
    local hits = bundle.recentHits
    if not hits then return end
    for i = fromIdx, #hits do
        hits[i]._wnMatch = nil
        hits[i]:Hide()
    end
end

local function OutcomeStripeColor(outcome)
    if outcome == "win" then
        if ns.UI_GetSemanticGreenColor then
            return ns.UI_GetSemanticGreenColor()
        end
        return 0.3, 0.9, 0.3, 1
    elseif outcome == "loss" then
        if ns.UI_GetSemanticRedColor then
            return ns.UI_GetSemanticRedColor()
        end
        return 0.78, 0.18, 0.18, 1
    end
    if ns.UI_GetTextRoleRGB then
        return ns.UI_GetTextRoleRGB("Dim")
    end
    return 0.45, 0.45, 0.45, 1
end

-- Win/loss stripe at row start (Statistics class-color bar pattern).
local function EnsureRecentOutcomeStripe(bundle, idx, card, rowY, outcome)
    bundle.recentStripes = bundle.recentStripes or {}
    local stripe = bundle.recentStripes[idx]
    if not stripe then
        stripe = card:CreateTexture(nil, "ARTWORK")
        bundle.recentStripes[idx] = stripe
    end
    stripe:SetParent(card)
    local barH = ROW_H - 4
    stripe:SetSize(RECENT_OUTCOME_STRIPE_W, barH)
    stripe:ClearAllPoints()
    local rowCenterY = -rowY - (ROW_H * 0.5)
    stripe:SetPoint("LEFT", card, "TOPLEFT", CARD_PAD + RECENT_OUTCOME_STRIPE_INSET, rowCenterY)
    local cr, cg, cb, ca = OutcomeStripeColor(outcome)
    stripe:SetColorTexture(cr, cg, cb, ca or 1)
    stripe:Show()
    return stripe
end

local function HideRecentOutcomeStripesFrom(bundle, fromIdx)
    local stripes = bundle.recentStripes
    if not stripes then return end
    for i = fromIdx, #stripes do
        if stripes[i] then
            stripes[i]:Hide()
        end
    end
end

local function ResolveRosterStatHeaderIcon(key)
    local statIcons = ROSTER_STAT_HEADER_ICONS[key]
    if not statIcons then return nil end
    if statIcons.currencyID then
        local cur = GetRosterCurrencyIconDef(statIcons.currencyID)
        if cur then return cur end
    end
    return statIcons
end

-- Export helpers/constants for PvPUI_Draw.lua (M.DrawTab uses M.* only → one upvalue).
M.CARD_PAD = CARD_PAD
M.ROW_H = ROW_H
M.HEADER_BLOCK_H = HEADER_BLOCK_H
M.SECTION_GAP = SECTION_GAP
M.CARD_GAP = CARD_GAP
M.BAR_H = BAR_H
M.BRACKET_LABELS = BRACKET_LABELS
M.RECENT_TITLE_H = RECENT_TITLE_H
M.RECENT_FILTER_GAP = RECENT_FILTER_GAP
M.RECENT_FILTER_BTN_H = RECENT_FILTER_BTN_H
M.RECENT_FILTER_BTN_GAP = RECENT_FILTER_BTN_GAP
M.RECENT_FILTER_PAD_H = RECENT_FILTER_PAD_H
M.RECENT_SUBBAR_LAYOUT_KEY = RECENT_SUBBAR_LAYOUT_KEY
M.RECENT_LIST_DIVIDER_H = RECENT_LIST_DIVIDER_H
M.RECENT_FOOTER_H = RECENT_FOOTER_H
M.RECENT_MATCHES_COLLAPSED = RECENT_MATCHES_COLLAPSED
M.PROGRESS_CARD_MIN_W = PROGRESS_CARD_MIN_W
M.RATED_CARD_STAT_H = RATED_CARD_STAT_H
M.RATED_CARD_MIN_W = RATED_CARD_MIN_W
M.ROSTER_BRACKET_ORDER = ROSTER_BRACKET_ORDER
M.ROSTER_BRACKET_HEADERS = ROSTER_BRACKET_HEADERS
M.ROSTER_HONOR_CURRENCY_ID = ROSTER_HONOR_CURRENCY_ID
M.ROSTER_CONQUEST_CURRENCY_ID = ROSTER_CONQUEST_CURRENCY_ID
M.RecentFilterLabel = RecentFilterLabel
M.BuildRecentColumns = BuildRecentColumns
M.MutedHex = MutedHex
M.BrightHex = BrightHex
M.OutcomeMarkup = OutcomeMarkup
M.FormatDuration = FormatDuration
M.FormatTimeLeft = FormatTimeLeft
M.FormatTimeAgo = FormatTimeAgo
M.EnsureCard = EnsureCard
M.EnsureCardTitle = EnsureCardTitle
M.EnsureCardTitleWithIcon = EnsureCardTitleWithIcon
M.PROGRESS_TITLE_ICONS = PROGRESS_TITLE_ICONS
M.ROSTER_STAT_HEADER_ICONS = ROSTER_STAT_HEADER_ICONS
M.ResolveRosterStatHeaderIcon = ResolveRosterStatHeaderIcon
M.EnsureBarRow = EnsureBarRow
M.EnsureRowCells = EnsureRowCells
M.HideRowsFrom = HideRowsFrom
M.EnsureBracketCard = EnsureBracketCard
M.EnsureBracketStatRow = EnsureBracketStatRow
M.EnsureListDivider = EnsureListDivider
M.RosterHonorHeaderLabel = RosterHonorHeaderLabel
M.RosterBracketHeaderLabel = RosterBracketHeaderLabel
M.RosterConquestHeaderLabel = RosterConquestHeaderLabel
M.RosterCurrencyQuantity = RosterCurrencyQuantity
M.FormatRosterCurrencyQty = FormatRosterCurrencyQty
M.RosterRealmHeaderLabel = RosterRealmHeaderLabel
M.ApplyRosterHeaderIconTexture = ApplyRosterHeaderIconTexture
M.TogglePvPRosterExpanded = TogglePvPRosterExpanded
M.FormatBigNumber = FormatBigNumber
M.MatchHasTooltipData = MatchHasTooltipData
M.ShowMatchTooltip = ShowMatchTooltip
M.EnsureRecentHitFrame = EnsureRecentHitFrame
M.HideRecentHitsFrom = HideRecentHitsFrom
M.EnsureRecentOutcomeStripe = EnsureRecentOutcomeStripe
M.HideRecentOutcomeStripesFrom = HideRecentOutcomeStripesFrom

-- DrawPvPTab lives in PvPUI_Draw.lua (WarbandNexus:DrawPvPTab facade there).


-- Thin listener: data changed → request a debounced tab repaint (no direct draw).
do
    local PvPUIListener = {}
    if WarbandNexus and WarbandNexus.RegisterMessage and ns.Constants and ns.Constants.EVENTS
        and ns.Constants.EVENTS.PVP_UPDATED then
        WarbandNexus.RegisterMessage(PvPUIListener, ns.Constants.EVENTS.PVP_UPDATED, function()
            local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
            if mf and mf:IsShown() and mf.currentTab == "pvp" then
                WarbandNexus:SendMessage(ns.Constants.EVENTS.UI_MAIN_REFRESH_REQUESTED, {
                    tab = "pvp",
                    skipCooldown = true,
                })
            end
        end)
    end
end
