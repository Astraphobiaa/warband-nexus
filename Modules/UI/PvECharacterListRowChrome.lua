--[[
    PvE tab: paint per-character summary headers to match Characters-tab list rows
    (46px zebra row, faction/race/class, two-line name/realm, level, iLvl — no guild column).
    Inline PvE columns align after the iLvl column (same horizontal slot as gold on Characters).
]]

local ADDON_NAME, ns = ...
local FontManager = ns.FontManager
local max = math.max
local issecretvalue = issecretvalue

local PVE_ILVL_TO_INLINE_GAP = 6

--- Pixels from row inner left (0) to the first inline PvE column (matches tight row chrome after iLvl).
function ns.PvE_ComputeInlineColumnsStartPx(nameW)
    local crc = ns.UI_CHAR_ROW_COLUMNS or {}
    local nw = math.max(crc.name and crc.name.width or 100, tonumber(nameW) or 100)
    local classOff = (ns.UI_GetColumnOffset and ns.UI_GetColumnOffset("class")) or 162
    local iconEnd = classOff + (crc.class and crc.class.width or 33)
    local nameLeft = iconEnd + 8
    local levelOffset = nameLeft + nw + 2
    local itemLevelOffset = levelOffset + (crc.level and crc.level.total or 97)
    return itemLevelOffset + (crc.itemLevel and crc.itemLevel.width or 75) + PVE_ILVL_TO_INLINE_GAP
end

--- Scroll/min-width prefix through identity + iLvl (same start as inline grid).
function ns.PvE_ComputeCharacterRowPrefixToGoldPx(nameW)
    return ns.PvE_ComputeInlineColumnsStartPx(nameW)
end

--- Match `WarbandNexus:DrawCharacterRow` identity stack through iLvl; caller paints PvE columns on the right.
--- @param addon table WarbandNexus AceAddon
--- @param charHeader Button row host (CreateCollapsibleHeader with suppressSectionChrome)
--- @param char table character row data
--- @param opts table rowIndex, charKey, isFavorite, isCurrentChar, expandIconFrame, nameWidth
function ns.PvEUI_ApplyCharacterListRowChrome(addon, charHeader, char, opts)
    if not charHeader or not char or not opts then return end

    local CRC = ns.UI_CHAR_ROW_COLUMNS or {}
    local rowIndex = tonumber(opts.rowIndex) or 1
    local charKey = opts.charKey
    local isFavorite = opts.isFavorite == true
    local isOnline = opts.isCurrentChar == true
    local expandIcon = opts.expandIconFrame
    local nameColW = math.max(CRC.name and CRC.name.width or 100, tonumber(opts.nameWidth) or (CRC.name and CRC.name.width) or 100)

    if charHeader._wnSectionStripe then
        charHeader._wnSectionStripe:Hide()
    end

    if charHeader._pveCharRowGuild then
        charHeader._pveCharRowGuild:Hide()
    end

    if ns.UI and ns.UI.Factory then
        ns.UI.Factory:ApplyRowBackground(charHeader, rowIndex)
        ns.UI.Factory:ApplyOnlineCharacterHighlight(charHeader, isOnline)
    end

    local classColor = RAID_CLASS_COLORS[char.classFile] or { r = 1, g = 1, b = 1 }

    local favBtn = charHeader._pveCharRowFav
    if not favBtn then
        favBtn = ns.UI_CreateFavoriteButton(charHeader, charKey, isFavorite, CRC.favorite.width, "LEFT", 0, 0, function(key)
            if ns.CharacterService and addon then
                return ns.CharacterService:ToggleFavoriteCharacter(addon, key)
            end
            return false
        end)
        charHeader._pveCharRowFav = favBtn
    end
    favBtn.charKey = charKey
    favBtn:SetChecked(isFavorite)
    -- PvE: do not change roster/favorites here (Character tab only). Still absorb clicks so the row header does not toggle expand.
    favBtn:SetScript("OnClick", function() end)
    favBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        -- Midnight: GameTooltip:SetText(text [, color, alpha, wrap]) — not legacy r,g,b,wrap four floats.
        GameTooltip:SetText((ns.L and ns.L["FAVORITE_EDIT_ON_CHARACTER_TAB"]) or "Change favorites on the Character tab.")
        GameTooltip:Show()
    end)
    favBtn:SetScript("OnLeave", GameTooltip_Hide)
    favBtn:ClearAllPoints()
    if expandIcon then
        favBtn:SetPoint("LEFT", expandIcon, "RIGHT", 4, 0)
    else
        local fo = (ns.UI_GetColumnOffset and ns.UI_GetColumnOffset("favorite")) or 10
        favBtn:SetPoint("LEFT", charHeader, "LEFT", fo + ((CRC.favorite and CRC.favorite.spacing) or 5) / 2, 0)
    end
    favBtn:Show()

    local gap = (CRC.favorite and CRC.favorite.spacing) or 5

    local factionIcon = charHeader._pveCharRowFaction
    if char.faction then
        if not factionIcon then
            factionIcon = ns.UI_CreateFactionIcon(charHeader, char.faction, CRC.faction.width, "LEFT", 0, 0)
            charHeader._pveCharRowFaction = factionIcon
        end
        factionIcon:ClearAllPoints()
        factionIcon:SetPoint("LEFT", favBtn, "RIGHT", gap, 0)
        if char.faction == "Alliance" then
            factionIcon:SetAtlas("AllianceEmblem")
        elseif char.faction == "Horde" then
            factionIcon:SetAtlas("HordeEmblem")
        else
            factionIcon:SetAtlas("bfa-landingbutton-alliance-up")
        end
        factionIcon:Show()
    elseif factionIcon then
        factionIcon:Hide()
    end

    local prevRace = factionIcon or favBtn
    local raceIcon = charHeader._pveCharRowRace
    if char.raceFile then
        if not raceIcon then
            raceIcon = ns.UI_CreateRaceIcon(charHeader, char.raceFile, char.gender, CRC.race.width, "LEFT", 0, 0)
            charHeader._pveCharRowRace = raceIcon
        end
        raceIcon:ClearAllPoints()
        raceIcon:SetPoint("LEFT", prevRace, "RIGHT", gap, 0)
        raceIcon:Show()
    elseif raceIcon then
        raceIcon:Hide()
    end

    local prevClass = raceIcon or factionIcon or favBtn
    local classIcon = charHeader._pveCharRowClass
    if char.classFile then
        if not classIcon then
            classIcon = ns.UI_CreateClassIcon(charHeader, char.classFile, CRC.class.width, "LEFT", 0, 0)
            charHeader._pveCharRowClass = classIcon
        end
        classIcon:ClearAllPoints()
        classIcon:SetPoint("LEFT", prevClass, "RIGHT", gap, 0)
        classIcon:SetAtlas("classicon-" .. char.classFile)
        classIcon:Show()
    elseif classIcon then
        classIcon:Hide()
    end

    local anchorRight = classIcon or raceIcon or factionIcon or favBtn

    local nameText = charHeader._pveCharRowName
    if not nameText then
        nameText = FontManager:CreateFontString(charHeader, "subtitle", "OVERLAY")
        charHeader._pveCharRowName = nameText
    end
    nameText:SetWidth(nameColW)
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
    realmText:SetWidth(nameColW)
    realmText:SetJustifyH("LEFT")
    realmText:SetWordWrap(false)
    realmText:SetNonSpaceWrap(false)
    realmText:SetMaxLines(1)
    local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    if issecretvalue and issecretvalue(displayRealm) then
        displayRealm = ""
    end
    realmText:SetText("|cffb0b0b8" .. displayRealm .. "|r")

    -- Horizontal start of the name column (same as gradient / level pack).
    local nameLeft = (anchorRight:GetRight() or 0) - (charHeader:GetLeft() or 0) + 8
    if nameLeft < 40 then
        nameLeft = (ns.UI_GetColumnOffset and ns.UI_GetColumnOffset("name")) or 162
        nameLeft = nameLeft + 4
    end

    -- Vertically center the two-line identity block in the row (level/iLvl stay on row midline).
    local rowH = charHeader:GetHeight() or 46
    local nameRealmGap = 1
    local nh = max(nameText:GetStringHeight() or 0, 12)
    local rh = max(realmText:GetStringHeight() or 0, 10)
    local blockH = nh + nameRealmGap + rh
    local topInset = max((rowH - blockH) / 2, 0)
    nameText:ClearAllPoints()
    realmText:ClearAllPoints()
    nameText:SetPoint("TOPLEFT", charHeader, "TOPLEFT", nameLeft, -topInset)
    realmText:SetPoint("TOPLEFT", nameText, "BOTTOMLEFT", 0, -nameRealmGap)
    if nameText.SetJustifyV then nameText:SetJustifyV("TOP") end
    if realmText.SetJustifyV then realmText:SetJustifyV("TOP") end
    local swName = nameText:GetStringWidth() or 0
    local swRealm = realmText:GetStringWidth() or 0
    local nameBlockW = math.min(nameColW, math.max(swName, swRealm, 1) + 4)
    do
        local gradientEnd = nameLeft + nameBlockW
        local rowW = charHeader:GetWidth() or 800
        if gradientEnd > rowW - 2 then
            gradientEnd = rowW - 2
        end
        if ns.UI_ApplyCharacterRowClassGradientAccent then
            ns.UI_ApplyCharacterRowClassGradientAccent(charHeader, char.classFile, gradientEnd)
        end
    end

    -- Tight pack: level starts right after measured name/realm block (no fixed 100px name column dead space).
    local levelTightGap = 2
    local levelOffset = nameLeft + nameBlockW + levelTightGap
    local levelColW = CRC.level and CRC.level.width or 82

    local levelText = charHeader._pveCharRowLevel
    if not levelText then
        levelText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        charHeader._pveCharRowLevel = levelText
    end
    if charHeader._pveCharRowLevelRested then
        charHeader._pveCharRowLevelRested:Hide()
    end

    levelText:SetWidth(levelColW)
    levelText:SetJustifyH("CENTER")
    if levelText.SetJustifyV then levelText:SetJustifyV("MIDDLE") end
    levelText:SetWordWrap(false)
    levelText:SetMaxLines(1)
    levelText:ClearAllPoints()
    levelText:SetPoint("LEFT", charHeader, "LEFT", levelOffset, 0)
    levelText:SetText(string.format("|cff%02x%02x%02x%d|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        char.level or 1))
    levelText:Show()

    local itemLevelOffset = levelOffset + (CRC.level and CRC.level.total or 97)
    local itemLevelText = charHeader._pveCharRowIlvl
    if not itemLevelText then
        itemLevelText = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        charHeader._pveCharRowIlvl = itemLevelText
    end
    itemLevelText:SetWidth(CRC.itemLevel and CRC.itemLevel.width or 75)
    itemLevelText:SetJustifyH("CENTER")
    if itemLevelText.SetJustifyV then itemLevelText:SetJustifyV("MIDDLE") end
    itemLevelText:SetMaxLines(1)
    itemLevelText:ClearAllPoints()
    itemLevelText:SetPoint("LEFT", charHeader, "LEFT", itemLevelOffset, 0)
    local itemLevel = char.itemLevel or 0
    if itemLevel > 0 then
        itemLevelText:SetText(string.format("|cffffd700%s %d|r", (ns.L and ns.L["ILVL_SHORT"]) or "iLvl", itemLevel))
    else
        itemLevelText:SetText("|cff666666--|r")
    end

    charHeader._pveInlineStartPx = itemLevelOffset + (CRC.itemLevel and CRC.itemLevel.width or 75) + PVE_ILVL_TO_INLINE_GAP
end
