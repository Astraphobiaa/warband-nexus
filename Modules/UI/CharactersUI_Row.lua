--[[
    Warband Nexus - Characters tab: character row painting (split from CharactersUI.lua).
    WarbandNexus:DrawCharacterRow (pooled row via ns.UI_AcquireCharacterRow / virtual list populate),
    live-resize interior relayout (ApplyCharacterRowInteriorLayout) and the pending-mail column.
    Column geometry: SharedWidgets_CharRow.lua (CHAR_ROW_COLUMNS, GetColumnOffset, flex widths).
]]

local ADDON_NAME, ns = ...
-- Pixel-perfect frames (SharedWidgets_Pixel: SetPoint/SetSize snap to whole physical pixels).
local CreateFrame = function(...) return (ns.UI_CreateFrame or _G.CreateFrame)(...) end
local B = assert(ns.CharactersUI and ns.CharactersUI._bind, "CharactersUI_Row: load Modules/UI/CharactersUI.lua first")
local WarbandNexus = B.WarbandNexus
local E = B.E
local FontManager = B.FontManager
local ShowTooltip = B.ShowTooltip
local HideTooltip = B.HideTooltip
local COLORS = B.COLORS
local FormatMoney = B.FormatMoney
local ThemeTextHex = B.ThemeTextHex
local SemanticGoldHex = B.SemanticGoldHex
local PresentFS = B.PresentFS
local CreateCharacterDeleteDialogButton = B.CreateCharacterDeleteDialogButton
local CreateIcon = B.CreateIcon
local AcquireCharacterRow = B.AcquireCharacterRow
local GetCharKey = B.GetCharKey
local IsCharLoggedInSession = B.IsCharLoggedInSession
local GetLayout = B.GetLayout
local BuildGuildText = B.BuildGuildText

local DebugPrint = ns.DebugPrint

local function SemanticGoldRGB()
    if ns.UI_GetSemanticGoldColor then
        return ns.UI_GetSemanticGoldColor()
    end
    return 1, 0.82, 0
end

local CreateFactionIcon = ns.UI_CreateFactionIcon
local CreateRaceIcon = ns.UI_CreateRaceIcon
local CreateClassIcon = ns.UI_CreateClassIcon
local CreateFavoriteButton = ns.UI_CreateFavoriteButton
local GetColumnOffset = ns.UI_GetColumnOffset
local CHAR_ROW_COLUMNS = ns.UI_CHAR_ROW_COLUMNS

--- Live resize: reposition width-dependent columns + class gradient (no full DrawCharacterRow).
local function ApplyCharacterRowInteriorLayout(row, rowW)
    if not row or not rowW or rowW < 1 then return end
    if row.GetWidth then
        local frameW = row:GetWidth()
        if frameW and frameW > 1 then
            rowW = frameW
        end
    end
    local addon = WarbandNexus
    -- Flex layout: guild + middle-block columns shrink toward their minimums on narrow rows
    -- (single source: UI_ComputeCharRowFlexColumns; DrawCharacterRow chains the same widths).
    local flexCols = ns.UI_ComputeCharRowFlexColumns
        and ns.UI_ComputeCharRowFlexColumns(rowW, addon._charListMaxGuildWidth) or nil
    local guildColW = (flexCols and flexCols.guild)
        or addon._charsListStableGuildColW or addon._charListMaxGuildWidth
    if not flexCols and ns.UI_ComputeCharRowGuildColumnWidth and addon._charListMaxGuildWidth then
        local newGuildW = ns.UI_ComputeCharRowGuildColumnWidth(rowW, addon._charListMaxGuildWidth)
        if newGuildW and newGuildW > 0 then
            guildColW = newGuildW
        end
    end
    if guildColW and guildColW > 0 then
        addon._charsListStableGuildColW = guildColW
    end

    local guildOffset = GetColumnOffset("guild")
    local guildSpacing = (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.spacing) or 15
    local rowH = row:GetHeight() or 46
    local centerY = -rowH / 2

    if row.guildText and guildColW then
        row.guildText:ClearAllPoints()
        row.guildText:SetPoint("CENTER", row, "TOPLEFT", guildOffset + (guildColW - 4) / 2, centerY)
        row.guildText:SetWidth(math.max(1, guildColW - 4))
    end

    local guildTotal = guildColW + guildSpacing
    local levelOffset = guildOffset + guildTotal
    local levelColW = (flexCols and flexCols.level) or CHAR_ROW_COLUMNS.level.width

    if row.levelText then
        row.levelText:SetWidth(levelColW)
        row.levelText:ClearAllPoints()
        if row.levelRestedText and row.levelRestedText:IsShown() then
            row.levelText:SetPoint("TOP", row, "TOPLEFT", levelOffset + (levelColW / 2), -7)
        else
            row.levelText:SetPoint("LEFT", levelOffset, 0)
        end
    end
    if row.levelRestedText then
        row.levelRestedText:SetWidth(levelColW)
    end

    local itemLevelW = (flexCols and flexCols.itemLevel) or CHAR_ROW_COLUMNS.itemLevel.width
    local itemLevelOffset = levelOffset + levelColW + (CHAR_ROW_COLUMNS.level.spacing or 15)
    if row.itemLevelText then
        row.itemLevelText:SetWidth(itemLevelW)
        row.itemLevelText:ClearAllPoints()
        row.itemLevelText:SetPoint("LEFT", itemLevelOffset, 0)
    end

    local goldW = (flexCols and flexCols.gold) or CHAR_ROW_COLUMNS.gold.width
    local goldOffset = itemLevelOffset + itemLevelW + (CHAR_ROW_COLUMNS.itemLevel.spacing or 15)
    if row.goldText then
        row.goldText:SetWidth(goldW)
        row.goldText:ClearAllPoints()
        row.goldText:SetPoint("LEFT", goldOffset, 0)
    end

    local profW = (flexCols and flexCols.professions) or CHAR_ROW_COLUMNS.professions.width
    local profOffset = goldOffset + goldW + (CHAR_ROW_COLUMNS.gold.spacing or 15)
    if row.profIcons then
        local shown = {}
        for i = 1, #row.profIcons do
            local pFrame = row.profIcons[i]
            if pFrame and pFrame.IsShown and pFrame:IsShown() then
                shown[#shown + 1] = pFrame
            end
        end
        local numProfs = #shown
        if numProfs > 0 then
            local iconSize = 39
            local iconSpacing = 5
            local totalIconWidth = (numProfs * iconSize) + ((numProfs - 1) * iconSpacing)
            local leftPadding = (profW - totalIconWidth) / 2
            local currentProfX = profOffset + leftPadding
            for i = 1, numProfs do
                local pFrame = shown[i]
                pFrame:ClearAllPoints()
                pFrame:SetPoint("LEFT", currentProfX, 0)
                currentProfX = currentProfX + iconSize + iconSpacing
            end
        end
    end

    local mythicKeyW = (flexCols and flexCols.mythicKey) or CHAR_ROW_COLUMNS.mythicKey.width
    local mythicKeyOffset = profOffset + profW + (CHAR_ROW_COLUMNS.professions.spacing or 0)
    if row.keystoneIcon then
        row.keystoneIcon:ClearAllPoints()
        row.keystoneIcon:SetPoint("LEFT", mythicKeyOffset + 5, 0)
    end
    if row.keystoneText then
        row.keystoneText:SetWidth(math.max(30, mythicKeyW - 30))
        row.keystoneText:ClearAllPoints()
        row.keystoneText:SetPoint("LEFT", mythicKeyOffset + 34, 0)
    end

    local mailOffset = GetColumnOffset("mail")
    if row.mailBtn and row.mailBtn:IsShown() then
        local mailColW = CHAR_ROW_COLUMNS.mail and CHAR_ROW_COLUMNS.mail.width or 36
        local mailBtnSz = row.mailBtn:GetWidth() or 34
        row.mailBtn:ClearAllPoints()
        row.mailBtn:SetPoint("LEFT", mailOffset + math.max(0, (mailColW - mailBtnSz) / 2), 0)
    end

    if row._wnRightRail then
        local railW = (ns.UI_GetCharRowRightRailWidth and ns.UI_GetCharRowRightRailWidth())
            or row._wnRightRail:GetWidth()
        row._wnRightRail:SetSize(railW, rowH)
        row._wnRightRail:ClearAllPoints()
        local R_MARGIN = ns.UI_CHAR_ROW_RIGHT_MARGIN or 6
        row._wnRightRail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -R_MARGIN, 0)
    end

    row._wnRowPaintWidth = rowW
    if row._wnGradientRefresh then
        pcall(row._wnGradientRefresh)
    end
end


local function StyleCharacterDeleteIcon(icon, highlighted)
    if not icon then return end
    icon:SetDesaturated(false)
    if highlighted then
        icon:SetVertexColor(1, 0.5, 0.5)
        icon:SetAlpha(1)
    else
        icon:SetVertexColor(0.95, 0.35, 0.35)
        icon:SetAlpha(0.98)
    end
end

local SECONDARY_PROF_KEYS = { "cooking" }
---Pending-mail badge next to character name. Inline |T paths are unreliable in modern clients; use a Texture.
local function ApplyPendingMailIconTexture(tex)
    tex:SetTexCoord(0, 1, 0, 1)
    if C_Texture and C_Texture.GetAtlasInfo then
        local atlasTry = { "Mail-Icon", "minimap-tracking-mailbox", "Mailbox-Tracking" }
        for i = 1, #atlasTry do
            local name = atlasTry[i]
            local ok, info = pcall(C_Texture.GetAtlasInfo, name)
            if ok and info then
                tex:SetAtlas(name)
                return
            end
        end
    end
    if C_Texture and C_Texture.GetFileIDFromPath then
        local paths = { "interface/minimap/tracking/mailbox", "Interface/Minimap/Tracking/Mailbox" }
        for i = 1, #paths do
            local p = paths[i]
            local ok, fid = pcall(C_Texture.GetFileIDFromPath, p)
            if ok and fid and type(fid) == "number" and fid > 0 then
                tex:SetTexture(fid)
                return
            end
        end
    end
    tex:SetTexture("Interface/Minimap/Tracking/Mailbox")
end

---Expiry reminder tint on the envelope: green over a week left, orange within the last
---week, red inside the last day. Mail with no known expiry (pending-only flag, or an alt
---whose mailbox was never opened) stays untinted rather than guessing an urgency.
local function ApplyMailReminderTint(tex, char)
    if not tex then return end
    local MS = ns.MailSnapshot
    local level
    if MS and MS.GetCharacterMailReminderLevel then
        level = MS.GetCharacterMailReminderLevel(char)
    end
    local r, g, b
    if level and ns.UI_GetMailReminderColor then
        r, g, b = ns.UI_GetMailReminderColor(level)
    end
    if r then
        tex:SetVertexColor(r, g, b, 1)
    else
        tex:SetVertexColor(1, 1, 1, 1)
    end
end

local MAIL_COL_BTN_SIZE = 34
local MAIL_COL_ICON_SIZE = 26
local MAIL_TOOLTIP_STABLE_WIDTH = 380

local function EnsureMailTooltipAnchor(btn)
    if not btn then return nil end
    local anchor = btn._wnMailTooltipAnchor
    if not anchor then
        anchor = CreateFrame("Frame", nil, btn)
        anchor:SetSize(MAIL_COL_BTN_SIZE, MAIL_COL_BTN_SIZE)
        anchor:SetPoint("CENTER")
        anchor:EnableMouse(false)
        btn._wnMailTooltipAnchor = anchor
    end
    return anchor
end

local function BuildCharacterMailTooltipData(char, isCurrent)
    local lines = (ns.MailSnapshot and ns.MailSnapshot.BuildTooltipLines(char, isCurrent)) or {}
    return {
        type = "custom",
        icon = false,
        title = (ns.L and ns.L["MAIL_TOOLTIP_TITLE"]) or "Mail",
        lines = lines,
        stableWidth = MAIL_TOOLTIP_STABLE_WIDTH,
        anchor = "ANCHOR_RIGHT",
    }
end

local function ShowCharacterMailTooltip(btn)
    local anchor = EnsureMailTooltipAnchor(btn) or btn
    local tipData = BuildCharacterMailTooltipData(btn._mailChar, btn._mailIsCurrent == true)
    if ShowTooltip then
        ShowTooltip(anchor, tipData)
    elseif ns.TooltipService then
        ns.TooltipService:Show(anchor, tipData)
    end
end

local function TryOpenMailDetailsPopup(btn)
    if not (IsShiftKeyDown and IsShiftKeyDown()) then return false end
    local char = btn._mailChar
    if not char then return false end
    if HideTooltip then
        HideTooltip()
    elseif ns.TooltipService then
        ns.TooltipService:Hide()
    end
    if WarbandNexus.ShowMailDetailsPopup then
        WarbandNexus:ShowMailDetailsPopup(char)
    elseif ns.UI_ShowMailDetailsPopup then
        ns.UI_ShowMailDetailsPopup(char)
    end
    return true
end

local function SetupCharacterMailColumn(row, char, mailOffset, isCurrent)
    local hasMail = ns.MailSnapshot and ns.MailSnapshot.CharHasPendingMail(char)
    if not hasMail then
        if row.mailBtn then
            row.mailBtn:Hide()
        end
        return
    end

    if not row.mailBtn then
        local btn = ns.UI.Factory:CreateButton(row, MAIL_COL_BTN_SIZE, MAIL_COL_BTN_SIZE, true)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then
            ns.UI.Factory:ApplyIconOnlyButtonChrome(btn)
        end
        btn.isPersistentRowElement = true
        btn.icon = btn:CreateTexture(nil, "OVERLAY")
        btn.icon:SetSize(MAIL_COL_ICON_SIZE, MAIL_COL_ICON_SIZE)
        btn.icon:SetPoint("CENTER")
        row.mailBtn = btn
    end

    ApplyPendingMailIconTexture(row.mailBtn.icon)
    ApplyMailReminderTint(row.mailBtn.icon, char)
    local mailColW = CHAR_ROW_COLUMNS.mail and CHAR_ROW_COLUMNS.mail.width or 36
    row.mailBtn:ClearAllPoints()
    row.mailBtn:SetPoint("LEFT", mailOffset + math.max(0, (mailColW - MAIL_COL_BTN_SIZE) / 2), 0)
    row.mailBtn:Show()
    row.mailBtn._mailChar = char
    row.mailBtn._mailIsCurrent = isCurrent

    row.mailBtn:SetScript("OnEnter", function(selfBtn)
        ShowCharacterMailTooltip(selfBtn)
    end)
    row.mailBtn:SetScript("OnClick", function(selfBtn)
        TryOpenMailDetailsPopup(selfBtn)
    end)
    row.mailBtn:SetScript("OnLeave", function()
        if HideTooltip then
            HideTooltip()
        elseif ns.TooltipService then
            ns.TooltipService:Hide()
        end
    end)
end

---@param existingRow Frame|nil When set (virtual list), draw into this pooled row instead of acquiring a second frame.
function WarbandNexus:DrawCharacterRow(parent, char, index, width, yOffset, isFavorite, showReorder, charList, listKey, positionInList, totalInList, currentPlayerKey, existingRow)
    local row = existingRow
    if not row then
        row = AcquireCharacterRow(parent)
    else
        row:SetParent(parent)
        row:Show()
        row:SetAlpha(1)
        if row.anim then row.anim:Stop() end
    end
    row:ClearAllPoints()
    row:SetHeight(46)
    if not existingRow then
        row:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -yOffset)
        row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -yOffset)
    end
    if row.SetClipsChildren then
        row:SetClipsChildren(not existingRow)
    end
    row:EnableMouse(true)
    row:SetAlpha(1)
    if row.anim then row.anim:Stop() end

    -- Define charKey for use in buttons (canonical key for DB/service consistency)
    local charKey = GetCharKey(char)
    local isCurrent = IsCharLoggedInSession(char)
    -- `isFavorite` is the section flag (true only for the Favorites block). Since a favorited
    -- character now stays in its custom section, the star has to read per-character state or it
    -- would render grey for every favorite outside that block.
    local rowIsFavorite = isFavorite
    if not rowIsFavorite and charKey and ns.CharacterService and ns.CharacterService.IsFavoriteCharacter then
        rowIsFavorite = ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey) and true or false
    end

    -- Right-click: tracking toggle + delete. `row.deleteBtn` is built further down, so it is read
    -- when the menu opens rather than captured here.
    row:SetScript("OnMouseUp", function(self, button)
        if button ~= "RightButton" then return end
        if not ns.UI_ShowCharacterRowContextMenu then return end
        ns.UI_ShowCharacterRowContextMenu(self, charKey, {
            charName = char.name,
            isTracked = char.isTracked ~= false,
            isCurrent = isCurrent,
            deleteButton = self.deleteBtn,
        })
    end)
    
    -- Set alternating background colors (Factory pattern)
    ns.UI.Factory:ApplyRowBackground(row, index)

    -- Online character highlight (theme-aware)
    ns.UI.Factory:ApplyOnlineCharacterHighlight(row, isCurrent)

    -- Class color
    local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
    
    -- COLUMN 1: Favorite button
    local favOffset = GetColumnOffset("favorite")
    
    if not row.favButton then
        -- Helper creates button, attach to row
        row.favButton = CreateFavoriteButton(row, charKey, rowIsFavorite, CHAR_ROW_COLUMNS.favorite.width, "LEFT", favOffset + (CHAR_ROW_COLUMNS.favorite.spacing / 2), 0, nil)
        row.favButton.isPersistentRowElement = true  -- Mark as persistent to prevent cleanup
        -- Note: callback set below
    end
    -- Update state
    row.favButton.charKey = charKey
    row.favButton:SetChecked(rowIsFavorite)
    
    -- Safely set OnClick (favButton should be a Button type)
    if row.favButton.HasScript and row.favButton:HasScript("OnClick") then
        row.favButton:SetScript("OnClick", function(btn)
            local newStatus = false
            if ns.CharacterService then
                newStatus = ns.CharacterService:ToggleFavoriteCharacter(WarbandNexus, charKey)
            end
            -- Recolour immediately: the row no longer jumps to the Favorites block, so without this
            -- the star would only catch up on the next full repaint.
            if btn.SetChecked then
                btn:SetChecked(newStatus and true or false)
            end
            return newStatus
        end)
    end
    
    -- Tooltip for favorite button
    if ShowTooltip and row.favButton.SetScript then
        row.favButton:SetScript("OnEnter", function(self)
            local isFav = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, charKey)
            ShowTooltip(self, {
                type = "custom",
                icon = "Interface\\Icons\\Achievement_GuildPerk_HappyHour",
                title = isFav and ((ns.L and ns.L["REMOVE_FROM_FAVORITES"]) or "Remove from Favorites") or ((ns.L and ns.L["ADD_TO_FAVORITES"]) or "Add to Favorites"),
                description = (ns.L and ns.L["FAVORITES_TOOLTIP"]) or "Favorite characters appear at the top of the list",
                lines = {
                    {text = "|cff00ff00" .. ((ns.L and ns.L["CLICK_TO_TOGGLE"]) or "Click to toggle") .. "|r", color = {1, 1, 1}}
                },
            })
        end)
        
        row.favButton:SetScript("OnLeave", function(self)
            if HideTooltip then
                HideTooltip()
            end
        end)
    end
    
    -- Icon border color (accent) â€” used for profession icons
    local iconBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
    
    -- COLUMN 2: Faction icon
    local factionOffset = GetColumnOffset("faction")
    if char.faction then
        if not row.factionIcon then
            row.factionIcon = CreateFactionIcon(row, char.faction, CHAR_ROW_COLUMNS.faction.width, "LEFT", factionOffset + (CHAR_ROW_COLUMNS.faction.spacing / 2), 0)
        end
        if char.faction == "Alliance" then
            row.factionIcon:SetAtlas("AllianceEmblem")
        elseif char.faction == "Horde" then
            row.factionIcon:SetAtlas("HordeEmblem")
        else
            row.factionIcon:SetAtlas("bfa-landingbutton-alliance-up")
        end
        row.factionIcon:Show()
    elseif row.factionIcon then
        row.factionIcon:Hide()
    end
    
    -- COLUMN 3: Race icon
    local raceOffset = GetColumnOffset("race")
    if char.raceFile then
        if not row.raceIcon then
            row.raceIcon = CreateRaceIcon(row, char.raceFile, char.gender, CHAR_ROW_COLUMNS.race.width, "LEFT", raceOffset + (CHAR_ROW_COLUMNS.race.spacing / 2), 0)
        end
        local raceAtlas = ns.UI_GetRaceGenderAtlas(char.raceFile, char.gender)
        row.raceIcon:SetAtlas(raceAtlas)
        row.raceIcon:Show()
    elseif row.raceIcon then
        row.raceIcon:Hide()
    end
    
    -- COLUMN 4: Class icon
    local classOffset = GetColumnOffset("class")
    if char.classFile then
        if not row.classIcon then
            row.classIcon = CreateClassIcon(row, char.classFile, CHAR_ROW_COLUMNS.class.width, "LEFT", classOffset + (CHAR_ROW_COLUMNS.class.spacing / 2), 0)
        end
        if ns.UI_ApplyClassIconTexture then
            ns.UI_ApplyClassIconTexture(row.classIcon, char.classFile)
        else
            row.classIcon:SetAtlas("classicon-" .. char.classFile)
        end
        row.classIcon:Show()
    elseif row.classIcon then
        row.classIcon:Hide()
    end
    
    -- COLUMN 5: Name
    local nameOffset = GetColumnOffset("name")
    local nameLeftPadding = 4
    -- Realm subline is optional (profile.showCharacterRealmName, nil = shown); without it the name
    -- centers vertically in the row. Pooled rows re-anchor every paint.
    local showRealm = WarbandNexus.db.profile.showCharacterRealmName ~= false
    
    if not row.nameText then
        row.nameText = FontManager:CreateFontString(row, "subtitle", "OVERLAY")
        row.nameText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.nameText:SetJustifyH("LEFT")
        row.nameText:SetWordWrap(false)
        row.nameText:SetNonSpaceWrap(false)
        row.nameText:SetMaxLines(1)
    end
    row.nameText:ClearAllPoints()
    if showRealm then
        row.nameText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -8)
    else
        row.nameText:SetPoint("LEFT", nameOffset + nameLeftPadding, 0)
    end
    row.nameText:SetText(string.format("|cff%02x%02x%02x%s|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")))
    PresentFS(row.nameText)
    if row.mailIcon then
        row.mailIcon:Hide()
    end
    if not row.realmText then
        row.realmText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.realmText:SetPoint("TOPLEFT", nameOffset + nameLeftPadding, -23)
        row.realmText:SetWidth(CHAR_ROW_COLUMNS.name.width)
        row.realmText:SetJustifyH("LEFT")
        row.realmText:SetWordWrap(false)
        row.realmText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        row.realmText:SetMaxLines(1)  -- Single line only
        ns.UI_SetTextColorRole(row.realmText, "Normal")
    end
    if showRealm then
        local displayRealm = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        ns.UI_SetTextColorRole(row.realmText, "Normal")
        row.realmText:SetText(displayRealm)
        PresentFS(row.realmText)
    else
        -- Empty text keeps the class-gradient width (max of name/realm) on the name alone.
        row.realmText:SetText("")
        row.realmText:Hide()
    end
    
    -- COLUMN: Guild — after mail column; width from max guild name; text centered before Level
    local guildOffset = GetColumnOffset("guild")
    -- Flex columns: same resolver as ApplyCharacterRowInteriorLayout so first paint and
    -- resize relayout agree on effective widths (narrow rows shrink toward column minimums).
    local flexCols = ns.UI_ComputeCharRowFlexColumns
        and ns.UI_ComputeCharRowFlexColumns(width, self._charListMaxGuildWidth) or nil
    local guildColW = (flexCols and flexCols.guild)
        or self._charsListStableGuildColW
        or self._charListMaxGuildWidth
        or (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.width)
        or 130
    local guildSpacing = (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.spacing) or 15
    if not row.guildText then
        row.guildText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.guildText:SetJustifyH("CENTER")
        if row.guildText.SetJustifyV then row.guildText:SetJustifyV("MIDDLE") end
        row.guildText:SetWordWrap(false)
        row.guildText:SetNonSpaceWrap(false)
        row.guildText:SetMaxLines(1)
    end
    row.guildText:ClearAllPoints()
    local rowH = row:GetHeight() or 46
    local centerY = -rowH / 2
    row.guildText:SetPoint("CENTER", row, "TOPLEFT", guildOffset + (guildColW - 4) / 2, centerY)
    row.guildText:SetWidth(guildColW - 4)
    row.guildText:SetText(BuildGuildText(char, isCurrent))
    PresentFS(row.guildText)
    row.guildText:Show()

    -- Level column: level + rested line (DB-driven).
    local guildTotal = guildColW + guildSpacing
    local levelOffset = guildOffset + guildTotal
    local levelColW = (flexCols and flexCols.level) or CHAR_ROW_COLUMNS.level.width
    if not row.levelText then
        row.levelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.levelText:SetJustifyH("CENTER")
        row.levelText:SetWordWrap(false)
        row.levelText:SetMaxLines(1)
    end
    row.levelText:SetWidth(levelColW)

    if not row.levelRestedText then
        row.levelRestedText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.levelRestedText:SetJustifyH("CENTER")
        row.levelRestedText:SetWordWrap(false)
        row.levelRestedText:SetMaxLines(1)
    end
    row.levelRestedText:SetWidth(levelColW)

    local restedState = self.GetCharacterRestedState and self:GetCharacterRestedState(char)
    local maxPlayerLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 80
    local showRestedLine = restedState ~= nil and (char.level or 1) < maxPlayerLevel
    local showZzz = restedState and restedState.isRestingArea

    row.levelText:ClearAllPoints()
    if showRestedLine then
        row.levelText:SetPoint("TOP", row, "TOPLEFT", levelOffset + (levelColW / 2), -7)
    else
        row.levelText:SetPoint("LEFT", levelOffset, 0)
    end
    row.levelText:SetText(string.format("|cff%02x%02x%02x%d|r",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        char.level or 1))
    PresentFS(row.levelText)
    row.levelText:Show()

    if showRestedLine then
        local restedPct = restedState.restedPercentOfLevel or 0
        row.levelRestedText:ClearAllPoints()
        row.levelRestedText:SetPoint("TOP", row.levelText, "BOTTOM", 0, -2)
        if showZzz then
            row.levelRestedText:SetText(string.format("|cff66c0ffZzz %.2f%%|r", restedPct))
        else
            row.levelRestedText:SetText(string.format("|cff66c0ff%.2f%%|r", restedPct))
        end
        PresentFS(row.levelRestedText)
        row.levelRestedText:Show()
    else
        row.levelRestedText:Hide()
    end

    if row.levelRestedIcon then row.levelRestedIcon:Hide() end
    if row.levelRestedHitFrame then row.levelRestedHitFrame:Hide() end

    -- COLUMN: Item Level (dynamic offset, chained from level column)
    local itemLevelW = (flexCols and flexCols.itemLevel) or CHAR_ROW_COLUMNS.itemLevel.width
    local itemLevelOffset = levelOffset + levelColW + (CHAR_ROW_COLUMNS.level.spacing or 15)
    if not row.itemLevelText then
        row.itemLevelText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.itemLevelText:SetJustifyH("CENTER")
        row.itemLevelText:SetMaxLines(1)  -- Single line only
    end
    row.itemLevelText:SetWidth(itemLevelW)
    row.itemLevelText:ClearAllPoints()
    row.itemLevelText:SetPoint("LEFT", itemLevelOffset, 0)
    local itemLevel = char.itemLevel or 0
    if itemLevel > 0 then
        row.itemLevelText:SetText(string.format("%s%s %s|r", SemanticGoldHex(), (ns.L and ns.L["ILVL_SHORT"]) or "iLvl", ns.UI_FormatCharRowItemLevel(itemLevel)))
    else
        row.itemLevelText:SetText(ThemeTextHex("Muted") .. "--|r")
    end
    PresentFS(row.itemLevelText)
    
    -- COLUMN 8: Gold (dynamic offset, chained from itemLevel column)
    local goldW = (flexCols and flexCols.gold) or CHAR_ROW_COLUMNS.gold.width
    local goldOffset = itemLevelOffset + itemLevelW + (CHAR_ROW_COLUMNS.itemLevel.spacing or 15)
    if not row.goldText then
        row.goldText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.goldText:SetJustifyH("RIGHT")
        row.goldText:SetMaxLines(1)  -- Single line only
    end
    row.goldText:SetWidth(goldW)
    row.goldText:ClearAllPoints()
    row.goldText:SetPoint("LEFT", goldOffset, 0)
    local totalCopper = isCurrent and ns.Utilities.GetLiveCharacterMoneyCopper
        and ns.Utilities:GetLiveCharacterMoneyCopper(ns.Utilities:GetCharTotalCopper(char))
        or ns.Utilities:GetCharTotalCopper(char)
    row.goldText:SetText(FormatMoney(totalCopper, 12))
    PresentFS(row.goldText)
    
    -- COLUMN 9: Professions (dynamic offset, chained from gold column)
    local profW = (flexCols and flexCols.professions) or CHAR_ROW_COLUMNS.professions.width
    local profOffset = goldOffset + goldW + (CHAR_ROW_COLUMNS.gold.spacing or 15)
    if not row.profIcons then row.profIcons = {} end
    
    -- Hide all existing profession icons first
    for i = 1, #row.profIcons do
        row.profIcons[i]:Hide()
    end
    
    if char.professions then
        local iconSize = 39  -- Increased 15% (34 â†’ 39)
        local iconSpacing = 5  -- Icon spacing
        
        -- Count total professions first
        local numProfs = 0
        if char.professions[1] then numProfs = numProfs + 1 end
        if char.professions[2] then numProfs = numProfs + 1 end
        for i = 1, #SECONDARY_PROF_KEYS do
            local sec = SECONDARY_PROF_KEYS[i]
            if char.professions[sec] then numProfs = numProfs + 1 end
        end
        
        -- Calculate centered starting position (within column content area, excluding right spacing)
        local totalIconWidth = (numProfs * iconSize) + ((numProfs - 1) * iconSpacing)
        -- Center the icons within the effective (flex) column width
        local leftPadding = (profW - totalIconWidth) / 2
        local currentProfX = profOffset + leftPadding
        
        local charKey = GetCharKey(char)
        local function SetupProfIcon(prof, idx, profSlotKey)
            if not prof or not prof.icon then return end
            
            -- Reuse or create (with accent border)
            local pFrame = row.profIcons[idx]
            if not pFrame then
                pFrame = CreateIcon(row, nil, iconSize, false, iconBorderColor, false)
                pFrame:EnableMouse(true)
                pFrame.icon = pFrame.texture
                
                row.profIcons[idx] = pFrame
            end
            
            -- Clear previous position and set new centered position
            pFrame:ClearAllPoints()
            pFrame:SetPoint("LEFT", currentProfX, 0)
            pFrame.icon:SetTexture(prof.icon)
            pFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Crop default WoW icon border
            pFrame:Show()
            
            -- Unspent knowledge badge (yellow dot)
            local profName = prof.name
            local kd = nil
            if profName and char.knowledgeData then
                -- Prefer highest skillLineID (newest expansion) for current data
                local bestKey = -1
                for key, entry in pairs(char.knowledgeData) do
                    if type(key) == "number" and type(entry) == "table" and entry.professionName == profName then
                        if key > bestKey then
                            bestKey = key
                            kd = entry
                        end
                    end
                end
                -- Fallback: legacy profName-keyed data
                if not kd then
                    kd = char.knowledgeData[profName]
                end
            end
            if kd and kd.unspentPoints and kd.unspentPoints > 0 then
                if not pFrame.knowledgeBadge then
                    local badge = pFrame:CreateTexture(nil, "OVERLAY")
                    badge:SetSize(16, 16)
                    badge:SetPoint("TOPRIGHT", pFrame, "TOPRIGHT", 5, 0)
                    ns.UI_SetIcon(badge, "attention")
                    pFrame.knowledgeBadge = badge
                end
                pFrame.knowledgeBadge:Show()
            else
                if pFrame.knowledgeBadge then
                    pFrame.knowledgeBadge:Hide()
                end
            end
            
            -- Profession detail is now shown automatically when WoW's profession UI opens.
            -- No click action needed on these icons.
            pFrame:SetScript("OnMouseUp", nil)
            
            -- Setup tooltip with detailed information (expansion skills + knowledge + concentration)
            pFrame:SetScript("OnEnter", function(self)
                local profName = prof.name or ((ns.L and ns.L["UNKNOWN_PROFESSION"]) or "Unknown Profession")
                local lines = {}

                local expansions = char.professionExpansions and char.professionExpansions[profName]
                if expansions and #expansions > 0 then
                    for i = 1, #expansions do
                        local exp = expansions[i]
                        local skillColor
                        local maxSkill = exp.maxSkillLevel or 0
                        local curSkill = exp.skillLevel or 0

                        if maxSkill > 0 and curSkill >= maxSkill then
                            skillColor = {0.3, 0.9, 0.3}
                        elseif curSkill > 0 then
                            local gr, gg, gb = SemanticGoldRGB()
                            skillColor = { gr, gg, gb }
                        else
                            skillColor = {0.4, 0.4, 0.4}
                        end

                        local skillText
                        if maxSkill > 0 then
                            skillText = string.format("%d / %d", curSkill, maxSkill)
                        else
                            skillText = "â€”"
                        end

                        lines[#lines + 1] = {
                            left = exp.name or "?",
                            right = skillText,
                            leftColor = {1, 1, 1},
                            rightColor = skillColor
                        }
                    end
                else
                    -- Fallback: no expansion data yet, show basic skill
                    if prof.skill and prof.maxSkill then
                        lines[#lines + 1] = {
                            left = profName,
                            right = string.format("%d / %d", prof.skill, prof.maxSkill),
                            leftColor = {1, 1, 1},
                            rightColor = {0.3, 0.9, 0.3}
                        }
                    end
                end

                local kd = nil
                if char.knowledgeData then
                    -- Prefer highest skillLineID (newest expansion) for current data
                    local bestKey = -1
                    for kKey, kEntry in pairs(char.knowledgeData) do
                        if type(kKey) == "number" and type(kEntry) == "table" and kEntry.professionName == profName then
                            if kKey > bestKey then
                                bestKey = kKey
                                kd = kEntry
                            end
                        end
                    end
                    -- Fallback: legacy profName-keyed data
                    if not kd then
                        kd = char.knowledgeData[profName]
                    end
                end
                if kd then
                    local unspent = kd.unspentPoints or 0
                    local spent = kd.spentPoints or 0
                    local maxPts = kd.maxPoints or 0
                    local collectible = (maxPts > 0) and (maxPts - unspent - spent) or 0
                    local hasKnowledgeLine = (collectible > 0) or (unspent > 0)
                    if hasKnowledgeLine then
                        lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                        local cName = kd.currencyName or ((ns.L and ns.L["KNOWLEDGE"]) or "Knowledge")
                        if collectible > 0 then
                            lines[#lines + 1] = {
                                left = (ns.L and ns.L["COLLECTIBLE"]) or "Collectible",
                                right = tostring(collectible),
                                leftColor = {1, 1, 1},
                                rightColor = {0.3, 0.9, 0.3}
                            }
                        end
                        if unspent > 0 then
                            lines[#lines + 1] = {
                                left = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t " .. unspent .. " " .. ((ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent Points"),
                                leftColor = {1, 0.82, 0}
                            }
                        end
                    end
                end

                -- Current (Midnight) skillLineID entry, not the legacy profName key pinned to the first
                -- expansion ever recorded.
                local concData = WarbandNexus.GetProfessionConcentrationEntry
                    and WarbandNexus:GetProfessionConcentrationEntry(char, profName)
                if concData and concData.max and concData.max > 0 then
                    -- Spacer
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }

                    -- Estimate current concentration (passive regen since snapshot)
                    local estimated = concData.current or 0
                    if WarbandNexus and WarbandNexus.GetEstimatedConcentration then
                        estimated = WarbandNexus:GetEstimatedConcentration(concData)
                    end

                    local concColor = {1, 1, 1}
                    if estimated >= concData.max then
                        concColor = {0.3, 0.9, 0.3}
                    elseif estimated > 0 then
                        concColor = {1, 0.82, 0}
                    end

                    local concText = string.format("%d / %d", estimated, concData.max)

                    lines[#lines + 1] = {
                        left = (ns.L and ns.L["CONCENTRATION"]) or "Concentration",
                        right = concText,
                        leftColor = {1, 1, 1},
                        rightColor = concColor
                    }

                    -- Recharge timer (white label, yellow duration)
                    if estimated < concData.max and WarbandNexus and WarbandNexus.GetConcentrationTimeToFull then
                        local timeStr = WarbandNexus:GetConcentrationTimeToFull(concData)
                        if timeStr and timeStr ~= "" and timeStr ~= ((ns.L and ns.L["FULL"]) or "Full") then
                            lines[#lines + 1] = {
                                left = (ns.L and ns.L["RECHARGE"]) or "Recharge",
                                right = timeStr,
                                leftColor = {1, 1, 1},
                                rightColor = {1, 0.82, 0}
                            }
                        end
                    end
                end

                local eqByProf = char.professionEquipment
                local eqData = eqByProf and eqByProf[profName] or nil
                if eqData and (eqData.tool or eqData.accessory1 or eqData.accessory2) then
                    lines[#lines + 1] = { left = " ", leftColor = {1, 1, 1} }
                    local slotKeys = { "tool", "accessory1", "accessory2" }
                    local tooltipSvc = ns.TooltipService
                    for i = 1, #slotKeys do
                        local slotKey = slotKeys[i]
                        local item = eqData[slotKey]
                        if item then
                            local iconStr = item.icon and string.format("|T%s:0|t ", tostring(item.icon)) or ""
                            -- Get stat lines first to extract actual slot type (Head, Chest, Tool, etc.)
                            local statLines = tooltipSvc and tooltipSvc.GetItemTooltipSummaryLines and tooltipSvc:GetItemTooltipSummaryLines(item.itemLink, item.itemID, slotKey) or {}
                            -- First line contains the slot type (e.g., "Head", "Chest", "Tool")
                            local slotLabel = (statLines[1] and statLines[1].left)
                                or (slotKey == "tool" and ((ns.L and ns.L["TOOL"]) or "Tool") or ((ns.L and ns.L["ACCESSORY"]) or "Accessory"))
                            lines[#lines + 1] = {
                                left = iconStr .. (item.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")),
                                right = slotLabel,
                                leftColor = {1, 1, 1},
                                rightColor = {0.5, 0.5, 0.5},
                            }
                            -- Add remaining stat lines (skip first since it's now used as slot label)
                            for si = 2, #statLines do
                                local sLine = statLines[si]
                                lines[#lines + 1] = {
                                    left = "    " .. sLine.left,
                                    right = sLine.right or "",
                                    leftColor = sLine.leftColor or {0.7, 0.7, 0.7},
                                    rightColor = sLine.rightColor or {0.7, 0.7, 0.7},
                                }
                            end
                        end
                    end
                end

                if not ShowTooltip then
                    -- Fallback: Use TooltipService
                    local tooltipLines = {}
                    for i = 1, #lines do
                        local line = lines[i]
                        if line.right then
                            tooltipLines[#tooltipLines + 1] = {
                                text = (line.left or "") .. "  " .. (line.right or ""),
                                color = line.rightColor or line.leftColor or {1, 1, 1}
                            }
                        elseif line.left and line.left ~= " " then
                            tooltipLines[#tooltipLines + 1] = {
                                text = line.left,
                                color = line.leftColor or {1, 1, 1}
                            }
                        end
                    end
                    ns.TooltipService:Show(self, {
                        type = "custom",
                        icon = prof.icon,
                        title = profName,
                        lines = tooltipLines,
                    })
                    return
                end

                ShowTooltip(self, {
                    type = "custom",
                    icon = prof.icon,
                    title = profName,
                    lines = lines,
                })
            end)
            pFrame:SetScript("OnLeave", function(self)
                if HideTooltip then
                    HideTooltip()
                else
                    ns.TooltipService:Hide()
                end
            end)
            
            return true
        end
        
        local pIdx = 1
        -- Primary
        if char.professions[1] then
            SetupProfIcon(char.professions[1], pIdx, 1)
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        if char.professions[2] then
            SetupProfIcon(char.professions[2], pIdx, 2)
            pIdx = pIdx + 1
            currentProfX = currentProfX + iconSize + iconSpacing
        end
        -- Secondary
        for i = 1, #SECONDARY_PROF_KEYS do
            local sec = SECONDARY_PROF_KEYS[i]
            if char.professions[sec] then
                SetupProfIcon(char.professions[sec], pIdx, sec)
                pIdx = pIdx + 1
                currentProfX = currentProfX + iconSize + iconSpacing
            end
        end
    end
    
    -- COLUMN 10: Mythic Keystone (dynamic offset, chained from professions column)
    local mythicKeyW = (flexCols and flexCols.mythicKey) or CHAR_ROW_COLUMNS.mythicKey.width
    local mythicKeyOffset = profOffset + profW + (CHAR_ROW_COLUMNS.professions.spacing or 0)

    -- Create keystone icon (shared for has-key and no-key)
    if not row.keystoneIcon then
        row.keystoneIcon = row:CreateTexture(nil, "ARTWORK")
        row.keystoneIcon:SetSize(24, 24)  -- Increased 20% (20 â†’ 24)

        -- Mythic Keystone item icon (IconRegistry "keystone"; ChromieTime-32x32 has no 12.1.5 FrameXML ref)
        ns.UI_SetIcon(row.keystoneIcon, "keystone")
    end
    row.keystoneIcon:ClearAllPoints()
    row.keystoneIcon:SetPoint("LEFT", mythicKeyOffset + 5, 0)  -- 5px padding from column edge

    -- Create keystone text (shared for has-key and no-key)
    if not row.keystoneText then
        row.keystoneText = FontManager:CreateFontString(row, "body", "OVERLAY")
        row.keystoneText:SetJustifyH("LEFT")
        row.keystoneText:SetWordWrap(false)
        row.keystoneText:SetNonSpaceWrap(false)  -- Prevent long word overflow
        row.keystoneText:SetMaxLines(1)  -- Single line only
    end
    row.keystoneText:SetWidth(math.max(30, mythicKeyW - 30))
    row.keystoneText:ClearAllPoints()
    row.keystoneText:SetPoint("LEFT", mythicKeyOffset + 34, 0)  -- Icon(24) + gap(5) + padding(5)
    
    -- Format content based on keystone status
    if char.mythicKey and char.mythicKey.level and char.mythicKey.level > 0 then
        -- HAS KEY: +Level â€¢ Dungeon (colored, bright icon)
        local dungeonName = (ns.Utilities and ns.Utilities.ResolveKeystoneDungeonName)
            and ns.Utilities:ResolveKeystoneDungeonName(char.mythicKey)
            or (char.mythicKey.dungeonName or "????")
        local dungeonAbbrev = dungeonName:sub(1, 4):upper()
        local keystoneText = string.format("|cffff8000+%d|r %s•|r %s%s|r",
            char.mythicKey.level, ThemeTextHex("Dim"), SemanticGoldHex(), dungeonAbbrev)
        
        row.keystoneText:SetText(keystoneText)
        
        -- Bright, colored icon
        row.keystoneIcon:SetDesaturated(false)
        row.keystoneIcon:SetVertexColor(1, 1, 1)
        row.keystoneIcon:SetAlpha(1.0)
    else
        -- NO KEY: +0 â€¢ None (dimmed, desaturated icon)
        local keystoneText = ThemeTextHex("Muted") .. "+0|r " .. ThemeTextHex("Muted") .. "•|r "
            .. ThemeTextHex("Normal") .. ((ns.L and ns.L["NONE_LABEL"]) or "None") .. "|r"
        
        row.keystoneText:SetText(keystoneText)
        
        -- Dimmed monochrome icon (GRAY BAN: no desaturated grey; theme ink at 0.45 alpha)
        local kvc = ns.UI_GetMonochromeIconVertex(0.45)
        row.keystoneIcon:SetDesaturated(false)
        row.keystoneIcon:SetVertexColor(kvc[1], kvc[2], kvc[3], kvc[4] or 0.45)
        row.keystoneIcon:SetAlpha(1.0)
    end
    
    row.keystoneIcon:Show()
    row.keystoneText:Show()

    -- COLUMN: Mail (snapshot from last login on this character)
    local mailOffset = GetColumnOffset("mail")
    SetupCharacterMailColumn(row, char, mailOffset, isCurrent)
    
    -- RIGHT RAIL: fixed slot positions (no per-row width reflow flicker on resize)
    local R_MARGIN = ns.UI_CHAR_ROW_RIGHT_MARGIN or 6
    local R_GAP = ns.UI_CHAR_ROW_RIGHT_GAP or 6
    local delW = CHAR_ROW_COLUMNS.delete and CHAR_ROW_COLUMNS.delete.width or 24
    local trackW = CHAR_ROW_COLUMNS.tracking and CHAR_ROW_COLUMNS.tracking.width or 22
    local haTot = CHAR_ROW_COLUMNS.headerAssign and CHAR_ROW_COLUMNS.headerAssign.total or 26
    local lsW = CHAR_ROW_COLUMNS.lastSeen and CHAR_ROW_COLUMNS.lastSeen.width or 60
    local reoW = CHAR_ROW_COLUMNS.reorder and CHAR_ROW_COLUMNS.reorder.width or 44
    local railW = (ns.UI_GetCharRowRightRailWidth and ns.UI_GetCharRowRightRailWidth()) or (R_MARGIN * 2 + delW + R_GAP + trackW + R_GAP + haTot + R_GAP + lsW + R_GAP + reoW)
    local insetDelete = 0
    local insetTrack = delW + R_GAP
    local insetHeader = insetTrack + trackW + R_GAP
    local insetLastSeen = insetHeader + haTot + R_GAP
    local insetReorder = insetLastSeen + lsW + R_GAP

    if not row._wnRightRail then
        row._wnRightRail = CreateFrame("Frame", nil, row)
        row._wnRightRail.isPersistentRowElement = true
    end
    local rail = row._wnRightRail
    rail:SetSize(railW, 46)
    rail:ClearAllPoints()
    rail:SetPoint("TOPRIGHT", row, "TOPRIGHT", -R_MARGIN, 0)
    rail:Show()

    -- COLUMN: Tracking toggle (all rows; login not required for other characters)
    local isCharTracked = char.isTracked ~= false
    if not row.trackingBtn then
        local tbtn = ns.UI.Factory:CreateButton(rail, 22, 22, true)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(tbtn) end
        tbtn.isPersistentRowElement = true
        tbtn.icon = tbtn:CreateTexture(nil, "ARTWORK")
        tbtn.icon:SetAllPoints()
        row.trackingBtn = tbtn
    else
        row.trackingBtn:SetParent(rail)
    end
    row.trackingBtn:ClearAllPoints()
    row.trackingBtn:SetPoint("RIGHT", rail, "RIGHT", -(insetTrack + 11), 0)
    if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(row.trackingBtn) end
    row.trackingBtn.charKey = charKey
    row.trackingBtn.charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    if row.trackingBtn.icon then
        if isCharTracked then
            local ok = pcall(row.trackingBtn.icon.SetAtlas, row.trackingBtn.icon, "common-icon-checkmark", false)
            if not ok then
                row.trackingBtn.icon:SetTexture("Interface\\Icons\\Ability_Hunter_BeastTaming")
            end
            row.trackingBtn.icon:SetVertexColor(0.35, 1, 0.45)
        else
            local ok = pcall(row.trackingBtn.icon.SetAtlas, row.trackingBtn.icon, "common-icon-redx", false)
            if not ok then
                row.trackingBtn.icon:SetTexture("Interface\\Icons\\Spell_Shadow_Teleport")
            end
            row.trackingBtn.icon:SetVertexColor(1, 0.55, 0.42)
        end
    end
    if row.trackingBtn.HasScript and row.trackingBtn:HasScript("OnClick") then
        row.trackingBtn:SetScript("OnClick", function(selfBtn)
            local CS = ns.CharacterService
            if not CS or not CS.ShowTrackingChangeConfirmation then return end
            local addon = WarbandNexus
            local ck = selfBtn.charKey
            local rowKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ck)
                and ns.Utilities:GetCanonicalCharacterKey(ck) or ck
            local rowData = addon and addon.db and addon.db.global and addon.db.global.characters
                and rowKey and (addon.db.global.characters[rowKey] or (ck and addon.db.global.characters[ck]))
            local tracked = rowData and rowData.isTracked ~= false
            CS:ShowTrackingChangeConfirmation(addon, rowKey or ck, selfBtn.charName, not tracked)
        end)
    end
    if ShowTooltip and row.trackingBtn.SetScript then
        row.trackingBtn:SetScript("OnEnter", function(selfBtn)
            local tracked = char.isTracked ~= false
            ShowTooltip(selfBtn, {
                type = "custom",
                title = (ns.L and ns.L["TRACKING_TOGGLE_TOOLTIP_TITLE"]) or "Character tracking",
                description = tracked
                    and ((ns.L and ns.L["TRACKING_TOGGLE_DISABLE_HINT"]) or "Click to disable tracking.")
                    or ((ns.L and ns.L["TRACKING_TOGGLE_ENABLE_HINT"]) or "Click to enable tracking."),
            })
        end)
        row.trackingBtn:SetScript("OnLeave", HideTooltip)
    end
    row.trackingBtn:Show()

    -- Reorder Buttons (leftmost slot in the right rail)
    if not row.reorderButtons then
        local rb = ns.UI.Factory:CreateContainer(rail, CHAR_ROW_COLUMNS.reorder.width, 46)
        rb.isPersistentRowElement = true

        rb.up = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(rb.up) end
        rb.up:SetPoint("CENTER", -11, 0)
        rb.up:SetNormalAtlas("housing-floor-arrow-up-default")
        rb.up:EnableMouse(true)
        rb.down = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(rb.down) end
        rb.down:SetPoint("CENTER", 11, 0)
        rb.down:SetNormalAtlas("housing-floor-arrow-down-default")
        rb.down:EnableMouse(true)
        row.reorderButtons = rb
    else
        row.reorderButtons:SetParent(rail)
    end
    row.reorderButtons:ClearAllPoints()
    row.reorderButtons:SetPoint("RIGHT", rail, "RIGHT", -insetReorder, 0)
    
    if showReorder and charList then
        row.reorderButtons:Show()
        -- Always set OnClick (WoW Button supports SetScript even without prior script; HasScript can be false before first set)
        if row.reorderButtons.up then
            row.reorderButtons.up:EnableMouse(true)
            row.reorderButtons.up:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, -1) end)
        end
        if row.reorderButtons.down then
            row.reorderButtons.down:EnableMouse(true)
            row.reorderButtons.down:SetScript("OnClick", function() WarbandNexus:ReorderCharacter(char, charList, listKey, 1) end)
        end
    else
        row.reorderButtons:Hide()
        if row.reorderButtons.up then row.reorderButtons.up:SetScript("OnClick", nil) end
        if row.reorderButtons.down then row.reorderButtons.down:SetScript("OnClick", nil) end
    end
    
    -- COLUMN: Last Seen (right rail — "Online" only for current character; relative time for alts)
    if not row._wnLastSeenHost then
        row._wnLastSeenHost = CreateFrame("Frame", nil, rail)
        row._wnLastSeenHost.isPersistentRowElement = true
    end
    local lsHost = row._wnLastSeenHost
    lsHost:SetParent(rail)
    lsHost:SetSize(lsW, 46)
    lsHost:ClearAllPoints()
    lsHost:SetPoint("RIGHT", rail, "RIGHT", -insetLastSeen, 0)
    lsHost:Show()

    if isCurrent then
        if not row.onlineText then
            row.onlineText = FontManager:CreateFontString(lsHost, "body", "OVERLAY")
            row.onlineText:SetWidth(lsW)
            row.onlineText:SetJustifyH("CENTER")
            row.onlineText:SetText((ns.L and ns.L["ONLINE"]) or "Online")
            if ns.UI_SetInkColor then
                ns.UI_SetInkColor(row.onlineText, 0, 1, 0, 1)
            else
                row.onlineText:SetTextColor(0, 1, 0)
            end
        else
            row.onlineText:SetParent(lsHost)
        end
        row.onlineText:ClearAllPoints()
        row.onlineText:SetPoint("CENTER", lsHost, "CENTER", 0, 0)
        row.onlineText:Show()
        if row.lastSeenText then row.lastSeenText:Hide() end
    else
        if row.onlineText then row.onlineText:Hide() end

        local timeDiff = char.lastSeen and (time() - char.lastSeen) or math.huge
        local lastSeenStr
        if timeDiff < 60 then
            lastSeenStr = (ns.L and ns.L["TIME_LESS_THAN_MINUTE"]) or "< 1m ago"
        elseif timeDiff < 3600 then
            local minutesFormat = (ns.L and ns.L["TIME_MINUTES_FORMAT"]) or "%dm ago"
            lastSeenStr = string.format(minutesFormat, math.floor(timeDiff / 60))
        elseif timeDiff < 86400 then
            local hoursFormat = (ns.L and ns.L["TIME_HOURS_FORMAT"]) or "%dh ago"
            lastSeenStr = string.format(hoursFormat, math.floor(timeDiff / 3600))
        else
            local daysFormat = (ns.L and ns.L["TIME_DAYS_FORMAT"]) or "%dd ago"
            lastSeenStr = string.format(daysFormat, math.floor(timeDiff / 86400))
        end

        if not row.lastSeenText then
            row.lastSeenText = FontManager:CreateFontString(lsHost, "body", "OVERLAY")
            row.lastSeenText:SetWidth(lsW)
            row.lastSeenText:SetJustifyH("CENTER")
        else
            row.lastSeenText:SetParent(lsHost)
        end
        row.lastSeenText:ClearAllPoints()
        row.lastSeenText:SetPoint("CENTER", lsHost, "CENTER", 0, 0)
        row.lastSeenText:SetText(lastSeenStr)
        ns.UI_SetTextColorRole(row.lastSeenText, "Normal")
        PresentFS(row.lastSeenText)
        row.lastSeenText:Show()
    end
    
    -- COLUMN: Custom section assign (folder) - tracked characters in regular or custom group lists.
    -- Favorites are no longer excluded: they can sit in a section, so they need the assign control
    -- to move or leave it. The listKey gate already keeps this out of the Favorites block.
    local showHeaderAssign = (char.isTracked ~= false)
        and (listKey == "regular" or (ns.CharacterService and ns.CharacterService.ParseCustomGroupIdFromListKey(listKey)))
    if showHeaderAssign then
        if not row.headerAssignBtn then
            local hb = ns.UI.Factory:CreateButton(rail, 22, 22, true)
            if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(hb) end
            hb.isPersistentRowElement = true
            local htex = hb.GetNormalTexture and hb:GetNormalTexture()
            if htex then
                htex:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
                htex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
            row.headerAssignBtn = hb
        else
            row.headerAssignBtn:SetParent(rail)
        end
        row.headerAssignBtn:ClearAllPoints()
        row.headerAssignBtn:SetPoint("RIGHT", rail, "RIGHT", -(insetHeader + 11), 0)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(row.headerAssignBtn) end
        row.headerAssignBtn:Show()
        row.headerAssignBtn:SetScript("OnClick", function(selfBtn)
            if ns.UI_ShowCharacterSectionAssignMenu then
                ns.UI_ShowCharacterSectionAssignMenu(selfBtn, charKey, WarbandNexus.db.profile, function()
                    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
                end)
            end
        end)
        if ShowTooltip then
            row.headerAssignBtn:SetScript("OnEnter", function(selfBtn)
                ShowTooltip(selfBtn, {
                    type = "custom",
                    title = (ns.L and ns.L["CUSTOM_HEADER_ASSIGN_TOOLTIP_TITLE"]) or "Custom header",
                    description = (ns.L and ns.L["CUSTOM_HEADER_ASSIGN_TOOLTIP_DESC"]) or "Move this character into a header. Use the + button (left of Filter) to create headers, or Filter â†’ New custom header.",
                })
            end)
            row.headerAssignBtn:SetScript("OnLeave", HideTooltip)
        end
    elseif row.headerAssignBtn then
        row.headerAssignBtn:Hide()
    end

    -- COLUMN: Delete button (RIGHT-anchored, compact)
    if not isCurrent then
        if not row.deleteBtn then
            local deleteBtn = ns.UI.Factory:CreateButton(rail, 24, 24, true)
            if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(deleteBtn) end
            deleteBtn.isPersistentRowElement = true
            
            -- Add icon texture
            local icon = deleteBtn:CreateTexture(nil, "ARTWORK")
            icon:SetAllPoints()
            icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
            StyleCharacterDeleteIcon(icon, false)
            deleteBtn.texture = icon
            deleteBtn.icon = icon
            
            row.deleteBtn = deleteBtn
        else
            row.deleteBtn:SetParent(rail)
        end
        row.deleteBtn:ClearAllPoints()
        row.deleteBtn:SetPoint("RIGHT", rail, "RIGHT", -(insetDelete + 12), 0)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(row.deleteBtn) end
        
        row.deleteBtn.charKey = charKey
        row.deleteBtn.charName = char.name or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        
        -- Safely set OnClick
        if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
            row.deleteBtn:SetScript("OnClick", function(self)
                -- Use custom themed delete dialog
                local charKey = self.charKey
                local charName = self.charName
                
                -- Get UI functions from namespace
                local CreateExternalWindow = ns.UI_CreateExternalWindow
                local FontManager = ns.FontManager
                
                if not CreateExternalWindow then
                    DebugPrint("[WarbandNexus] ERROR: CreateExternalWindow not found!")
                    return
                end
                
                -- Create custom delete confirmation dialog
                local dialog, contentFrame = CreateExternalWindow({
                    name = "DeleteCharacterDialog",
                    title = (ns.L and ns.L["DELETE_CHARACTER_TITLE"]) or "Delete Character?",
                    icon = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
                    width = 420,
                    height = 180,
                })
                
                if not dialog then
                    DebugPrint("[WarbandNexus] ERROR: Failed to create delete dialog!")
                    return
                end
                
                -- Warning text
                local dlgPS = ns.UI_LAYOUT and ns.UI_LAYOUT.PAGE_STACK
                local dlgPad = (dlgPS and dlgPS.SIDE) or 12
                local warning = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                warning:SetPoint("TOPLEFT", contentFrame, "TOPLEFT", dlgPad, -dlgPad * 2)
                warning:SetPoint("TOPRIGHT", contentFrame, "TOPRIGHT", -dlgPad, -dlgPad * 2)
                warning:SetJustifyH("CENTER")
                if ns.UI_GetSemanticGoldColor then
                    local gr, gg, gb = ns.UI_GetSemanticGoldColor()
                    warning:SetTextColor(gr, gg, gb)
                else
                    warning:SetTextColor(1, 0.85, 0.1)
                end
                local confirmDeleteFmt = (ns.L and ns.L["CONFIRM_DELETE"]) or "Are you sure you want to delete |cff00ccff%s|r?"
                warning:SetText(string.format(confirmDeleteFmt, charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")))
                
                local subtext = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
                subtext:SetPoint("TOPLEFT", warning, "BOTTOMLEFT", 0, -10)
                subtext:SetPoint("TOPRIGHT", warning, "BOTTOMRIGHT", 0, -10)
                subtext:SetJustifyH("CENTER")
                if ns.UI_GetSemanticRedColor then
                    local rr, rg, rb = ns.UI_GetSemanticRedColor()
                    subtext:SetTextColor(rr, rg, rb)
                else
                    subtext:SetTextColor(1, 0.3, 0.3)
                end
                local cannotUndoText = (ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!"
                subtext:SetText(cannotUndoText)
                
                -- Buttons container (using Factory pattern)
                local btnContainer = ns.UI.Factory:CreateContainer(contentFrame, 320, 40)
                btnContainer:SetPoint("BOTTOMLEFT", contentFrame, "BOTTOMLEFT", dlgPad, dlgPad)
                btnContainer:SetPoint("BOTTOMRIGHT", contentFrame, "BOTTOMRIGHT", -dlgPad, dlgPad)
                
                -- Delete button (LEFT)
                local deleteBtnLabel = (ns.L and ns.L["DELETE"]) or "Delete"
                local deleteBtn = CreateCharacterDeleteDialogButton(btnContainer, deleteBtnLabel, 150, true)
                deleteBtn:SetPoint("LEFT", btnContainer, "LEFT", 0, 0)
                deleteBtn:SetScript("OnClick", function()
                    -- Delete the row that was clicked: its own table index first. The canonical key of an
                    -- untracked row is Name-Realm, which resolves to the logged-in character when a stale
                    -- same-name copy is deleted.
                    local chars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
                    local rowIndex = char and char._key
                    if not (rowIndex and chars and chars[rowIndex] ~= nil) then rowIndex = nil end
                    local delKey = rowIndex
                        or ((ns.UI_GetCharKey and char) and ns.UI_GetCharKey(char))
                        or (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ns.Utilities:GetCanonicalCharacterKey(charKey))
                        or charKey
                    local success = WarbandNexus:DeleteCharacter(delKey)
                    if dialog.Close then
                        dialog:Close()
                    else
                        dialog:Hide()
                    end
                end)
                
                -- Cancel button (RIGHT)
                local cancelBtnLabel = (ns.L and ns.L["CANCEL"]) or "Cancel"
                local cancelBtn = CreateCharacterDeleteDialogButton(btnContainer, cancelBtnLabel, 150, false)
                cancelBtn:SetPoint("RIGHT", btnContainer, "RIGHT", 0, 0)
                cancelBtn:SetScript("OnClick", function()
                    if dialog.Close then
                        dialog:Close()
                    else
                        dialog:Hide()
                    end
                end)
                
                -- NOTE: Do NOT override dialog:SetScript("OnHide") here!
                -- WindowFactory's OnHide handles hiding the clickOutsideFrame overlay.
                -- Overriding it leaves an invisible full-screen mouse blocker.
                -- dialog.Close() already handles SetParent(nil) and _G cleanup.
                
                -- Show dialog
                dialog:Show()
            end)
        end
        
        if row.deleteBtn.icon then
            StyleCharacterDeleteIcon(row.deleteBtn.icon, false)
        end

        -- Tooltip for delete button
        if ShowTooltip and row.deleteBtn.SetScript then
            row.deleteBtn:SetScript("OnEnter", function(self)
                if self.icon then
                    StyleCharacterDeleteIcon(self.icon, true)
                end
                local removeFromTrackingFmt = (ns.L and ns.L["REMOVE_FROM_TRACKING_FORMAT"]) or "Remove %s from tracking"
                ShowTooltip(self, {
                    type = "custom",
                    icon = "Interface\\Icons\\Spell_Shadow_SacrificialShield",
                    title = (ns.L and ns.L["DELETE_CHARACTER"]) or "Delete Character",
                    titleColor = {1, 0.4, 0},
                    description = string.format(removeFromTrackingFmt, self.charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")),
                    lines = {
                        {text = "|cffff0000" .. ((ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!") .. "|r", color = {1, 0.2, 0.2}},
                        {type = "spacer"},
                        {text = "|cff00ff00" .. ((ns.L and ns.L["CLICK_TO_DELETE"]) or "Click to delete") .. "|r", color = {1, 1, 1}}
                    },
                })
            end)
            
            row.deleteBtn:SetScript("OnLeave", function(self)
                if self.icon then
                    StyleCharacterDeleteIcon(self.icon, false)
                end
                if HideTooltip then
                    HideTooltip()
                end
            end)
        end
        
        row.deleteBtn:Show()
    else
        if row.deleteBtn then
            row.deleteBtn:Hide()
            -- Clear OnClick when hiding
            if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
                row.deleteBtn:SetScript("OnClick", nil)
            end
        end
    end
    
    row._wnGradientRefresh = function()
        if not row.nameText or not row.realmText or not ns.UI_ApplyCharacterRowClassGradientAccent then
            return
        end
        local nameLeft = nameOffset + nameLeftPadding
        local nameColW = CHAR_ROW_COLUMNS.name.width
        local swName = row.nameText:GetStringWidth() or 0
        local swRealm = row.realmText:GetStringWidth() or 0
        local nameBlockRight = nameLeft + math.min(nameColW, math.max(swName, swRealm) + 4)
        local gradientEnd = nameBlockRight
        local rowW = row._wnRowPaintWidth
        if not rowW or rowW < 2 then
            rowW = row:GetWidth() or 0
        end
        if rowW < 2 and parent and parent.GetWidth then
            rowW = parent:GetWidth() or rowW
        end
        if rowW < 2 then
            rowW = width or 800
        end
        if gradientEnd > rowW - 2 then
            gradientEnd = rowW - 2
        end
        ns.UI_ApplyCharacterRowClassGradientAccent(row, char.classFile, gradientEnd)
    end
    row._wnGradientRefresh()

    local betweenRows = GetLayout().betweenRows or 0
    return yOffset + 46 + betweenRows, row  -- Row 46px + spacing + row ref for pool tracking
end

ns.CharactersUI.ApplyCharacterRowInteriorLayout = ApplyCharacterRowInteriorLayout
