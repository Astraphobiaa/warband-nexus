--[[
    PvE tab: per-character summary rows aligned with Professions-tab identity strip
    (expand chevron + fav + class + name/realm + level + iLvl, then inline PvE grid).
]]

local ADDON_NAME, ns = ...
local FontManager = ns.FontManager
local max = math.max
local issecretvalue = issecretvalue

local PVE_ILVL_TO_INLINE_GAP = 6
-- ProfessionsUI: LEFT_PAD = 4, COL_SPACING = 8, fav/class = 33px.
local PVE_LEFT_PAD = 4
local PVE_COL_GAP = 8
local PVE_FAV_COL_W = 33
local PVE_CLASS_COL_W = 33
local PVE_NAME_COL_MIN_W = 100
local PVE_NAME_WIDTH_PAD = 4
local PVE_LEVEL_AFTER_NAME_GAP = 2

--- Name + realm stack in one column: width = max line width (not "name - realm" on one line).
function ns.PvE_MeasureStackedNameColumnWidth(measureFs, nameStr, realmStr)
    if not measureFs then return 0 end
    if issecretvalue and nameStr and issecretvalue(nameStr) then
        nameStr = "Unknown"
    end
    if issecretvalue and realmStr and issecretvalue(realmStr) then
        realmStr = ""
    end
    measureFs:SetText(nameStr or "Unknown")
    local nameW = measureFs:GetStringWidth() or 0
    local realmW = 0
    if realmStr and realmStr ~= "" then
        measureFs:SetText(realmStr)
        realmW = measureFs:GetStringWidth() or 0
    end
    return math.max(nameW, realmW)
end

function ns.PvE_ResolveNameColumnWidth(maxMeasuredW)
    return math.max(PVE_NAME_COL_MIN_W, math.ceil(tonumber(maxMeasuredW) or 0) + PVE_NAME_WIDTH_PAD)
end

ns.PVE_NAME_COL_MIN_W = PVE_NAME_COL_MIN_W

--- Expand chevron column (CreateCollapsibleHeader) before Professions identity strip.
local function PvE_GetChevronPrefixPx()
    local ly = ns.UI_LAYOUT or {}
    local chevLeft = ly.SECTION_HEADER_COLLAPSE_CHEVRON_LEFT or 12
    local chevSz = ly.SECTION_COLLAPSE_CHEVRON_SIZE or 26
    return chevLeft + chevSz + 4
end

--- Shared identity layout: Professions fav/class/name rhythm + chevron + PvE level/iLvl.
local _pveIdentityLayoutByNameW = {}
local function PvE_BuildIdentityLayout(nameW)
    local nwKey = math.max(PVE_NAME_COL_MIN_W, tonumber(nameW) or PVE_NAME_COL_MIN_W)
    local cached = _pveIdentityLayoutByNameW[nwKey]
    if cached then return cached end
    local crc = ns.UI_CHAR_ROW_COLUMNS or {}
    local nw = math.max(PVE_NAME_COL_MIN_W, crc.name and crc.name.width or 100, tonumber(nameW) or 100)
    local levelW = crc.level and crc.level.width or 82
    local levelTot = crc.level and crc.level.total or 97
    local ilvlW = crc.itemLevel and crc.itemLevel.width or 75

    local base = PVE_LEFT_PAD + PvE_GetChevronPrefixPx()
    local nameLeft = base + PVE_FAV_COL_W + PVE_COL_GAP + PVE_CLASS_COL_W + PVE_COL_GAP
    local levelLeft = nameLeft + nw + PVE_LEVEL_AFTER_NAME_GAP
    local ilvlLeft = levelLeft + levelTot

    local layout = {
        favCenterX = base + PVE_FAV_COL_W * 0.5,
        classCenterX = base + PVE_FAV_COL_W + PVE_COL_GAP + PVE_CLASS_COL_W * 0.5,
        nameLeft = nameLeft,
        nameColW = nw,
        levelLeft = levelLeft,
        levelColW = levelW,
        levelTot = levelTot,
        ilvlLeft = ilvlLeft,
        ilvlColW = ilvlW,
        inlineStart = ilvlLeft + ilvlW + PVE_ILVL_TO_INLINE_GAP,
        identityGradientEnd = nameLeft + nw,
    }
    _pveIdentityLayoutByNameW[nwKey] = layout
    return layout
end

--- Pixels from row inner left (0) to the first inline PvE column.
function ns.PvE_ComputeInlineColumnsStartPx(nameW)
    return PvE_BuildIdentityLayout(nameW).inlineStart
end

--- Scroll/min-width prefix through identity + iLvl (same start as inline grid).
function ns.PvE_ComputeCharacterRowPrefixToGoldPx(nameW)
    return ns.PvE_ComputeInlineColumnsStartPx(nameW)
end

--- Match Professions / compact roster rows: fav + class + name block + level + iLvl.
--- @param addon table WarbandNexus AceAddon
--- @param charHeader Button row host (CreateCollapsibleHeader with suppressSectionChrome)
--- @param char table character row data
--- @param opts table rowIndex, charKey, isFavorite, isCurrentChar, expandIconFrame, nameWidth
function ns.PvEUI_ApplyCharacterListRowChrome(addon, charHeader, char, opts)
    if not charHeader or not char or not opts then return end

    local rowIndex = tonumber(opts.rowIndex) or 1
    local charKey = opts.charKey
    local isFavorite = opts.isFavorite == true
    local isOnline = opts.isCurrentChar == true
    local nameColW = math.max(PVE_NAME_COL_MIN_W, tonumber(opts.nameWidth) or PVE_NAME_COL_MIN_W)
    local layout = PvE_BuildIdentityLayout(nameColW)

    if charHeader._wnSectionStripe then
        charHeader._wnSectionStripe:Hide()
    end
    if charHeader._pveCharRowGuild then charHeader._pveCharRowGuild:Hide() end
    if charHeader._pveCharRowFaction then charHeader._pveCharRowFaction:Hide() end
    if charHeader._pveCharRowRace then charHeader._pveCharRowRace:Hide() end

    if charHeader._wnCollHeaderText then
        charHeader._wnCollHeaderText:SetText("")
        charHeader._wnCollHeaderText:Hide()
    end
    if charHeader.SetText then
        charHeader:SetText("")
    end

    if ns.UI and ns.UI.Factory then
        ns.UI.Factory:ApplyRowBackground(charHeader, rowIndex)
        ns.UI.Factory:ApplyOnlineCharacterHighlight(charHeader, isOnline)
    end

    local classColor = RAID_CLASS_COLORS[char.classFile] or { r = 1, g = 1, b = 1 }

    local favBtn = charHeader._pveCharRowFav
    if not favBtn then
        favBtn = ns.UI_CreateFavoriteButton(charHeader, charKey, isFavorite, PVE_FAV_COL_W, "CENTER", 0, 0, function(key)
            if ns.CharacterService and addon then
                return ns.CharacterService:ToggleFavoriteCharacter(addon, key)
            end
            return false
        end)
        charHeader._pveCharRowFav = favBtn
    end
    favBtn.charKey = charKey
    favBtn:SetChecked(isFavorite)
    favBtn:SetScript("OnClick", function() end)
    favBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText((ns.L and ns.L["FAVORITE_EDIT_ON_CHARACTER_TAB"]) or "Change favorites on the Character tab.")
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", GameTooltip_Hide)
    favBtn:ClearAllPoints()
    favBtn:SetPoint("CENTER", charHeader, "LEFT", layout.favCenterX, 0)
    favBtn:Show()

    local classIcon = charHeader._pveCharRowClass
    if char.classFile then
        if not classIcon then
            classIcon = ns.UI_CreateClassIcon(charHeader, char.classFile, PVE_CLASS_COL_W, "CENTER", 0, 0)
            charHeader._pveCharRowClass = classIcon
        end
        classIcon:SetSize(PVE_CLASS_COL_W, PVE_CLASS_COL_W)
        classIcon:ClearAllPoints()
        classIcon:SetPoint("CENTER", charHeader, "LEFT", layout.classCenterX, 0)
        classIcon:SetAtlas("classicon-" .. char.classFile)
        classIcon:Show()
    elseif classIcon then
        classIcon:Hide()
    end

    local nameText = charHeader._pveCharRowName
    if not nameText then
        nameText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        charHeader._pveCharRowName = nameText
    end
    nameText:SetWidth(layout.nameColW)
    nameText:SetJustifyH("LEFT")
    nameText:SetWordWrap(false)
    nameText:SetNonSpaceWrap(false)
    nameText:SetMaxLines(1)
    do
        local nm = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        if issecretvalue and issecretvalue(nm) then
            nm = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
        end
        nameText:SetText(string.format("|cff%02x%02x%02x%s|r",
            classColor.r * 255, classColor.g * 255, classColor.b * 255,
            nm))
    end

    local realmText = charHeader._pveCharRowRealm
    if not realmText then
        realmText = FontManager:CreateFontString(charHeader, "small", "OVERLAY")
        charHeader._pveCharRowRealm = realmText
    end
    realmText:SetWidth(layout.nameColW)
    realmText:SetJustifyH("LEFT")
    realmText:SetWordWrap(false)
    realmText:SetNonSpaceWrap(false)
    realmText:SetMaxLines(1)
    local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    if issecretvalue and issecretvalue(displayRealm) then
        displayRealm = ""
    end
    local realmHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Muted")) or "|cffb0b0b8"
    realmText:SetText(realmHex .. displayRealm .. "|r")

    local rowH = charHeader:GetHeight() or 46
    local nameRealmGap = 1
    local nh = max(nameText:GetStringHeight() or 0, 12)
    local rh = max(realmText:GetStringHeight() or 0, 10)
    local blockH = nh + nameRealmGap + rh
    local topInset = max((rowH - blockH) / 2, 0)

    nameText:ClearAllPoints()
    realmText:ClearAllPoints()
    nameText:SetPoint("TOPLEFT", charHeader, "TOPLEFT", layout.nameLeft, -topInset)
    realmText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -nameRealmGap)
    if nameText.SetJustifyV then nameText:SetJustifyV("TOP") end
    if realmText.SetJustifyV then realmText:SetJustifyV("TOP") end
    if nameText.SetShadowOffset then
        nameText:SetShadowOffset(0, 0)
    end
    nameText:Show()
    realmText:Show()

    do
        local gradientEnd = layout.identityGradientEnd
        local rowW = charHeader:GetWidth() or 800
        if gradientEnd > rowW - 2 then
            gradientEnd = rowW - 2
        end
        if ns.UI_ApplyCharacterRowClassGradientAccent then
            ns.UI_ApplyCharacterRowClassGradientAccent(charHeader, char.classFile, gradientEnd)
        end
    end

    local levelText = charHeader._pveCharRowLevel
    if not levelText then
        levelText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        charHeader._pveCharRowLevel = levelText
    end
    if charHeader._pveCharRowLevelRested then
        charHeader._pveCharRowLevelRested:Hide()
    end
    levelText:SetWidth(layout.levelColW)
    levelText:SetJustifyH("CENTER")
    if levelText.SetJustifyV then levelText:SetJustifyV("MIDDLE") end
    levelText:SetWordWrap(false)
    levelText:SetMaxLines(1)
    levelText:ClearAllPoints()
    levelText:SetPoint("LEFT", charHeader, "LEFT", layout.levelLeft, 0)
    levelText:SetText(string.format("|cff%02x%02x%02x%d|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        char.level or 1))
    levelText:Show()

    local itemLevelText = charHeader._pveCharRowIlvl
    if not itemLevelText then
        itemLevelText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        charHeader._pveCharRowIlvl = itemLevelText
    end
    itemLevelText:SetWidth(layout.ilvlColW)
    itemLevelText:SetJustifyH("CENTER")
    if itemLevelText.SetJustifyV then itemLevelText:SetJustifyV("MIDDLE") end
    itemLevelText:SetMaxLines(1)
    itemLevelText:ClearAllPoints()
    itemLevelText:SetPoint("LEFT", charHeader, "LEFT", layout.ilvlLeft, 0)
    local itemLevel = char.itemLevel or 0
    local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or "|cffffd700"
    local dimHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Dim")) or "|cff666666"
    if itemLevel > 0 then
        itemLevelText:SetText(string.format("%s%s %d|r", goldHex, (ns.L and ns.L["ILVL_SHORT"]) or "iLvl", itemLevel))
    else
        itemLevelText:SetText(dimHex .. "--|r")
    end
    itemLevelText:Show()

    charHeader._pveInlineStartPx = layout.inlineStart
end
