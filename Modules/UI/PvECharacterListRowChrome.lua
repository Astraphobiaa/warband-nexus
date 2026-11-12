--[[
    PvE tab: per-character summary rows aligned with Professions-tab identity strip
    (expand chevron + fav + class + name/realm + level + iLvl, then inline PvE grid).
]]

local ADDON_NAME, ns = ...
local FontManager = ns.FontManager
--- Live markup role table (`SharedWidgets_Theme.lua`). Mutated in place on theme change,
--- so this reference stays current -- never copy a role out of it into another local.
local HEX = ns.UI_HEX
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
--- Measured in the shared roster identity fonts (ns.UI_MeasureCharacterIdentityWidth); measureFs is only the
--- fallback before SharedWidgets_RowPool loads.
function ns.PvE_MeasureStackedNameColumnWidth(measureFs, nameStr, realmStr)
    if ns.UI_MeasureCharacterIdentityWidth then
        return ns.UI_MeasureCharacterIdentityWidth(nameStr, realmStr)
    end
    if not measureFs then return 0 end
    if issecretvalue and issecretvalue(nameStr) then
        nameStr = "Unknown"
    end
    if issecretvalue and issecretvalue(realmStr) then
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

--- Shared identity layout: Professions fav/class/name rhythm + optional chevron + PvE level/iLvl.
local _pveIdentityLayoutByNameW = {}
--- @param chevronPrefixPx number|nil 0 = no expand chevron (PvP overview); nil = Professions/PvE default.
--- PvE tab Filter > Display toggles (profile.pveHideLevel / pveHideItemLevel). PvP overview passes an
--- explicit chevron prefix and always keeps both columns.
local function PvE_ResolveIdentityColumnFlags(chevronPrefixPx)
    if chevronPrefixPx ~= nil then return false, false end
    local WN = ns.WarbandNexus
    local p = WN and WN.db and WN.db.profile
    if not p then return false, false end
    return p.pveHideLevel == true, p.pveHideItemLevel == true
end

local function PvE_BuildIdentityLayout(nameW, chevronPrefixPx)
    local nwKey = math.max(PVE_NAME_COL_MIN_W, tonumber(nameW) or PVE_NAME_COL_MIN_W)
    local chevKey = (chevronPrefixPx == nil) and "default" or tostring(chevronPrefixPx)
    local hideLevel, hideIlvl = PvE_ResolveIdentityColumnFlags(chevronPrefixPx)
    local cacheKey = nwKey .. ":" .. chevKey .. ":" .. (hideLevel and "L0" or "L1") .. (hideIlvl and "I0" or "I1")
    local cached = _pveIdentityLayoutByNameW[cacheKey]
    if cached then return cached end
    local crc = ns.UI_CHAR_ROW_COLUMNS or {}
    local nw = math.max(PVE_NAME_COL_MIN_W, crc.name and crc.name.width or 100, tonumber(nameW) or 100)
    local levelW = crc.level and crc.level.width or 82
    local levelTot = crc.level and crc.level.total or 97
    local ilvlW = crc.itemLevel and crc.itemLevel.width or 82
    if hideLevel then levelTot = 0 end
    if hideIlvl then ilvlW = 0 end

    local chevron = chevronPrefixPx
    if chevron == nil then chevron = PvE_GetChevronPrefixPx() end
    local base = PVE_LEFT_PAD + chevron
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
        hideLevel = hideLevel,
        hideItemLevel = hideIlvl,
    }
    _pveIdentityLayoutByNameW[cacheKey] = layout
    return layout
end

--- Pixels from row inner left (0) to the first inline PvE column.
function ns.PvE_ComputeInlineColumnsStartPx(nameW, chevronPrefixPx)
    return PvE_BuildIdentityLayout(nameW, chevronPrefixPx).inlineStart
end

--- Identity strip layout (chevronPrefixPx = 0 for PvP overview rows without expand chevron).
function ns.PvE_GetIdentityLayout(nameW, chevronPrefixPx)
    return PvE_BuildIdentityLayout(nameW, chevronPrefixPx)
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
    local chevronPx = opts.chevronPrefixPx
    if chevronPx == nil and opts.skipChevronPrefix then
        chevronPx = 0
    end
    local layout = PvE_BuildIdentityLayout(nameColW, chevronPx)

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
        if ns.UI_SafeSetGameTooltipOwner(self, "ANCHOR_RIGHT") then
            GameTooltip:SetText((ns.L and ns.L["FAVORITE_EDIT_ON_CHARACTER_TAB"]) or "Change favorites on the Character tab.")
            GameTooltip:Show()
        end
    end)
    favBtn:SetScript("OnLeave", ns.UI_SafeHideGameTooltip)
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
        ns.UI_ApplyClassIconTexture(classIcon, char.classFile)
        classIcon:Show()
    elseif classIcon then
        classIcon:Hide()
    end

    -- Name + realm subline + class gradient: shared roster identity (same look as the Characters tab).
    if ns.UI_ApplyCharacterRowIdentity then
        ns.UI_ApplyCharacterRowIdentity(charHeader, char, layout.nameLeft, layout.nameColW, {
            nameField = "_pveCharRowName",
            realmField = "_pveCharRowRealm",
        })
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
    levelText:SetShown(not layout.hideLevel)

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
    local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or HEX.gold
    local dimHex = (ns.UI_GetTextRoleHex and ns.UI_GetTextRoleHex("Dim")) or HEX.dim
    if itemLevel > 0 then
        itemLevelText:SetText(string.format("%s%s %s|r", goldHex, (ns.L and ns.L["ILVL_SHORT"]) or "iLvl", ns.UI_FormatCharRowItemLevel(itemLevel)))
    else
        itemLevelText:SetText(dimHex .. "--|r")
    end
    itemLevelText:SetShown(not layout.hideItemLevel)

    charHeader._pveInlineStartPx = layout.inlineStart
end
