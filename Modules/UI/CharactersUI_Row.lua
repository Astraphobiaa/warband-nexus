--[[
    Warband Nexus - Characters tab: character row painting (split from CharactersUI.lua).
    WarbandNexus:DrawCharacterRow (pooled row via ns.UI_AcquireCharacterRow / virtual list populate),
    live-resize interior relayout (ApplyCharacterRowInteriorLayout) and the pending-mail column.
    Column geometry: SharedWidgets_CharRow.lua (CHAR_ROW_COLUMNS, GetColumnOffset, flex widths).
]]

local ADDON_NAME, ns = ...
--- Live markup role table (`SharedWidgets_Theme.lua`). Mutated in place on theme change,
--- so this reference stays current -- never copy a role out of it into another local.
local HEX = ns.UI_HEX
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

-- Profession strip geometry. Two places lay these icons out -- the first paint and the resize
-- relayout -- and they MUST agree: the relayout used to hardcode 39 px while the paint shrank to
-- fit, so four professions were spaced for 39 and drawn at 33, overlapping each other.
local PROF_ICON_MAX = 39
local PROF_ICON_MIN = 22
local PROF_ICON_GAP = 5

--- Largest square that fits `count` icons plus their gaps inside `columnW`.
-- Fixed slot order where the vanilla secondary set exists: the two primaries, then Cooking,
-- Fishing and First Aid. Each keeps its place whether or not the character has it, so a roster of
-- alts lines up column by column instead of shuffling.
--
-- The placeholders are the long-standing Classic icon paths for those three trades. They are
-- referenced by path rather than by file id because a path that no longer resolves simply draws
-- nothing, while a stale numeric id can draw the WRONG art.
local PROF_SLOT_ORDER = {
    { key = 1, empty = true },
    { key = 2, empty = true },
    { key = "firstAid", placeholder = "Interface\\Icons\\Spell_Holy_SealOfSacrifice" },
    { key = "fishing", placeholder = "Interface\\Icons\\Trade_Fishing" },
    { key = "cooking", placeholder = "Interface\\Icons\\Trade_Cooking" },
}

--- Art for a slot the character has not filled: the trade's own icon for a secondary, and a
--- plain cross for a primary, which has no identity of its own until one is chosen.
local function ProfSlotPlaceholder(slot)
    if slot.placeholder then return slot.placeholder end
    if slot.empty and ns.UI_GetIconFile then return ns.UI_GetIconFile("close") end
    return nil
end

local function ProfIconSize(columnW, count)
    if not count or count < 1 then return PROF_ICON_MAX end
    local fit = math.floor(((columnW or 0) - (count - 1) * PROF_ICON_GAP) / count)
    if fit >= PROF_ICON_MAX then return PROF_ICON_MAX end
    return math.max(PROF_ICON_MIN, fit)
end

-- Same square as the profession icons next to them, so the three columns read as one band
-- instead of two sizes of glyph on one row.
local CELL_ICON = 39

--- The name as it should be PRINTED anywhere in this row: Utilities joins the Forever surname
--- and honours the player's "show secondary name" setting, so no call site decides it alone.
local function DisplayName(char)
    local U = ns.Utilities
    if U and U.GetCharacterDisplayName then
        local printed = U:GetCharacterDisplayName(char)
        -- Must be a real string: `if printed then` accepted anything truthy, and a resolver that
        -- answers a number put "Remove 0 from tracking" in a confirmation dialog.
        if type(printed) == "string" and printed ~= "" then return printed end
    end
    return char and char.name
end

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

local profLayoutScratch = {}  -- ApplyCharacterRowInteriorLayout: shown profession icons, wiped per row

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

    local rowH = row:GetHeight() or 46
    local centerY = -rowH / 2

    -- Level now leads the text block, and everything before it is fixed width, so it reads its
    -- own offset straight from the column order.
    local levelOffset = GetColumnOffset("level")
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

    local guildOffset = GetColumnOffset("guild")
    local guildSpacing = (CHAR_ROW_COLUMNS.guild and CHAR_ROW_COLUMNS.guild.spacing) or 15
    if row.guildText and guildColW then
        row.guildText:ClearAllPoints()
        row.guildText:SetPoint("CENTER", row, "TOPLEFT", guildOffset + (guildColW - 4) / 2, centerY)
        row.guildText:SetWidth(math.max(1, guildColW - 4))
    end

    -- Guild is the only measured column, so from here on the offsets are chained off its real
    -- width instead of the fixed totals the column order carries.
    local guildTotal = guildColW + guildSpacing
    local mailOffset = guildOffset + guildTotal
    local realmTypeOffset = mailOffset + ((CHAR_ROW_COLUMNS.mail and CHAR_ROW_COLUMNS.mail.total) or 46)

    local realmTypeW = (flexCols and flexCols.realmType) or CHAR_ROW_COLUMNS.realmType.width
    if row.realmTypeText then
        if realmTypeW > 0 then
            row.realmTypeText:SetWidth(realmTypeW)
            row.realmTypeText:ClearAllPoints()
            row.realmTypeText:SetPoint("LEFT", realmTypeOffset, 0)
        else
            row.realmTypeText:Hide()
        end
    end

    local itemLevelW = (flexCols and flexCols.itemLevel) or CHAR_ROW_COLUMNS.itemLevel.width
    local itemLevelOffset = realmTypeOffset + realmTypeW
        + ((realmTypeW > 0) and (CHAR_ROW_COLUMNS.realmType.spacing or 0) or 0)
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
        -- Reused scratch: this runs per row on every live-resize step (2026-10-22: was a fresh {} per row).
        local shown = wipe(profLayoutScratch)
        for i = 1, #row.profIcons do
            local pFrame = row.profIcons[i]
            if pFrame and pFrame.IsShown and pFrame:IsShown() then
                shown[#shown + 1] = pFrame
            end
        end
        if WarbandNexus.SupportsFeature and WarbandNexus:SupportsFeature("firstAidProfession") then
            -- Fixed slots: each icon keeps ITS index's place. Packing the visible ones together
            -- here, the way the branch below does, undid the slot layout the paint had just set --
            -- so every resize slid the icons across and an empty primary slot closed up.
            local slots = #PROF_SLOT_ORDER
            local iconSize = ProfIconSize(profW, slots)
            local totalIconWidth = (slots * iconSize) + ((slots - 1) * PROF_ICON_GAP)
            local x = profOffset + (profW - totalIconWidth) / 2
            for i = 1, slots do
                local pFrame = row.profIcons[i]
                if pFrame then
                    pFrame:SetSize(iconSize, iconSize)
                    pFrame:ClearAllPoints()
                    pFrame:SetPoint("LEFT", x, 0)
                end
                x = x + iconSize + PROF_ICON_GAP
            end
        else
        local numProfs = #shown
        if numProfs > 0 then
            local iconSize = ProfIconSize(profW, numProfs)
            local totalIconWidth = (numProfs * iconSize) + ((numProfs - 1) * PROF_ICON_GAP)
            local leftPadding = (profW - totalIconWidth) / 2
            local currentProfX = profOffset + leftPadding
            for i = 1, numProfs do
                local pFrame = shown[i]
                -- Resized as well as moved: a frame built at 39 keeps that size otherwise, and
                -- the row would space them for the smaller square while drawing the larger one.
                pFrame:SetSize(iconSize, iconSize)
                pFrame:ClearAllPoints()
                pFrame:SetPoint("LEFT", currentProfX, 0)
                currentProfX = currentProfX + iconSize + PROF_ICON_GAP
            end
        end
        end
    end

    -- Skills / Talents sit between Professions and Keystone, and all three collapse to zero width
    -- on a client without their system -- so each one's trailing gap goes with it and the next
    -- column moves up instead of leaving a hole.
    local skillsW = (flexCols and flexCols.skills) or CHAR_ROW_COLUMNS.skills.width
    local skillsOffset = profOffset + profW + (CHAR_ROW_COLUMNS.professions.spacing or 0)
    if row.skillsIcon then
        if skillsW > 0 then
            row.skillsIcon:ClearAllPoints()
            row.skillsIcon:SetPoint("LEFT", skillsOffset + (skillsW - CELL_ICON) / 2, 0)
        else
            row.skillsIcon:Hide()
        end
    end

    local talentsW = (flexCols and flexCols.talents) or CHAR_ROW_COLUMNS.talents.width
    local talentsOffset = skillsOffset + skillsW
        + ((skillsW > 0) and (CHAR_ROW_COLUMNS.skills.spacing or 0) or 0)
    if row.talentsIcon then
        if talentsW > 0 then
            row.talentsIcon:ClearAllPoints()
            row.talentsIcon:SetPoint("LEFT", talentsOffset + (talentsW - CELL_ICON) / 2, 0)
        else
            row.talentsIcon:Hide()
        end
    end

    local mythicKeyW = (flexCols and flexCols.mythicKey) or CHAR_ROW_COLUMNS.mythicKey.width
    -- Width 0 = no Mythic+ on this client (see CharRowColumnEnabled): hide, do not just shrink.
    if mythicKeyW == 0 then
        if row.keystoneIcon then row.keystoneIcon:Hide() end
        if row.keystoneText then row.keystoneText:Hide() end
    end
    local mythicKeyOffset = talentsOffset + talentsW
        + ((talentsW > 0) and (CHAR_ROW_COLUMNS.talents.spacing or 0) or 0)
    if row.keystoneIcon then
        row.keystoneIcon:ClearAllPoints()
        row.keystoneIcon:SetPoint("LEFT", mythicKeyOffset + 5, 0)
    end
    if row.keystoneText then
        row.keystoneText:SetWidth(math.max(30, mythicKeyW - 30))
        row.keystoneText:ClearAllPoints()
        row.keystoneText:SetPoint("LEFT", mythicKeyOffset + 34, 0)
    end

    -- mailOffset was chained off the measured guild width above.
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


--- Close glyph is colored art: neutral vertex, hover state is alpha only.
local function StyleCharacterDeleteIcon(icon, highlighted)
    if not icon then return end
    icon:SetDesaturated(false)
    icon:SetVertexColor(1, 1, 1, 1)
    icon:SetAlpha(highlighted and 1 or 0.75)
end

-- Retail shows Cooking alone (Fishing is collected but has never been drawn). On WoW Forever the
-- vanilla secondary set is First Aid + Fishing + Cooking, and all three are things a player tracks
-- across alts -- so the list is per client, and retail's single icon is left exactly as it was.
local SECONDARY_PROF_KEYS_RETAIL = { "cooking" }
local SECONDARY_PROF_KEYS_CLASSIC = { "firstAid", "fishing", "cooking" }
local function SecondaryProfKeys()
    if WarbandNexus.SupportsFeature and WarbandNexus:SupportsFeature("firstAidProfession") then
        return SECONDARY_PROF_KEYS_CLASSIC
    end
    return SECONDARY_PROF_KEYS_RETAIL
end
---Pending-mail badge next to character name: the registry envelope (a Texture; inline |T paths are unreliable).
local function ApplyPendingMailIconTexture(tex)
    ns.UI_SetIcon(tex, "mail")
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

-- Stable Characters-row scripts (no per-paint closures). DrawCharacterRow stores what each handler
-- needs on the row / control (_wnCharRow*, charKey, _wnProf, ...); the shared handlers read those
-- fields at hover / click time (2026-10-22: a row paint created ~15 closures).
local CharRowCb = {}

function CharRowCb.HideTip()
    if HideTooltip then
        HideTooltip()
    elseif ns.TooltipService then
        ns.TooltipService:Hide()
    end
end

function CharRowCb.HideTooltipOnly()
    if HideTooltip then
        HideTooltip()
    end
end

function CharRowCb.RowOnMouseUp(self, button)
    if button ~= "RightButton" then return end
    if not ns.UI_ShowCharacterRowContextMenu then return end
    local char, charKey, isCurrent = self._wnCharRowChar, self._wnCharRowKey, self._wnCharRowIsCurrent
    if not char then return end
    -- Tracking acts on this exact row: its own table index, not the canonical key (Name-Realm for
    -- an untracked row, which can resolve to the logged-in character).
    local chars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
    local rowIndex = char._key
    if not (rowIndex and chars and chars[rowIndex] ~= nil) then rowIndex = nil end
    ns.UI_ShowCharacterRowContextMenu(self, charKey, {
        trackingKey = rowIndex,
        charName = DisplayName(char),
        isTracked = char.isTracked ~= false,
        isCurrent = isCurrent,
        deleteButton = self.deleteBtn,
    })
end

function CharRowCb.FavOnClick(btn)
    local newStatus = false
    if ns.CharacterService then
        newStatus = ns.CharacterService:ToggleFavoriteCharacter(WarbandNexus, btn.charKey)
    end
    -- Recolour immediately: the row no longer jumps to the Favorites block, so without this
    -- the star would only catch up on the next full repaint.
    if btn.SetChecked then
        btn:SetChecked(newStatus and true or false)
    end
    return newStatus
end

function CharRowCb.FavOnEnter(self)
    local isFav = ns.CharacterService and ns.CharacterService:IsFavoriteCharacter(WarbandNexus, self.charKey)
    ShowTooltip(self, {
        type = "custom",
        icon = "favorite_on",
        title = isFav and ((ns.L and ns.L["REMOVE_FROM_FAVORITES"]) or "Remove from Favorites") or ((ns.L and ns.L["ADD_TO_FAVORITES"]) or "Add to Favorites"),
        description = (ns.L and ns.L["FAVORITES_TOOLTIP"]) or "Favorite characters appear at the top of the list",
        lines = {
            {text = HEX.green .. ((ns.L and ns.L["CLICK_TO_TOGGLE"]) or "Click to toggle") .. "|r", color = {1, 1, 1}}
        },
    })
end

--- One profession icon of DrawCharacterRow (module level: no per-paint closure; 2026-10-22).
function CharRowCb.SetupProfIcon(row, char, prof, idx, profX, iconSize)
    if not prof or not prof.icon then return end
    
    -- Reuse or create (with accent border)
    local pFrame = row.profIcons[idx]
    if not pFrame then
        -- Icon border color (accent): built only when an icon is created (was a table per paint).
        local iconBorderColor = {COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6}
        pFrame = CreateIcon(row, nil, iconSize, false, iconBorderColor, false)
        pFrame:EnableMouse(true)
        pFrame.icon = pFrame.texture
        
        row.profIcons[idx] = pFrame
    end
    
    -- Clear previous position and set new centered position
    pFrame:ClearAllPoints()
    pFrame:SetPoint("LEFT", profX, 0)
    pFrame:SetSize(iconSize, iconSize)
    pFrame.icon:SetTexture(prof.icon)
    pFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)  -- Crop default WoW icon border
    -- Undo the greyed placeholder state: the same pooled frame is reused for both.
    pFrame.icon:SetDesaturated(false)
    pFrame.icon:SetAlpha(1)
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
    
    -- Clicking opens the recipe list for that profession, the same way Skills and Talents do.
    -- Nothing happens until that profession's window has been opened once, since the recipe list
    -- is only readable while it is up.
    pFrame._wnProfID = prof.skillLine
    pFrame:SetScript("OnMouseUp", CharRowCb.ProfOnClick)
    
    -- Setup tooltip with detailed information (expansion skills + knowledge + concentration).
    -- Stable shared scripts read the painted profession from the icon (2026-10-22).
    pFrame._wnProf = prof
    pFrame._wnProfChar = char
    pFrame:SetScript("OnEnter", CharRowCb.ProfOnEnter)
    pFrame:SetScript("OnLeave", CharRowCb.HideTip)
    
    return true
end

--- A secondary the character has not taken: its own art, desaturated and dimmed, with no
--- tooltip or click because there is nothing behind it yet.
function CharRowCb.SetupProfPlaceholder(row, idx, profX, iconSize, texture)
    if not texture then
        if row.profIcons[idx] then row.profIcons[idx]:Hide() end
        return
    end
    local pFrame = row.profIcons[idx]
    if not pFrame then
        local iconBorderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 }
        pFrame = CreateIcon(row, nil, iconSize, false, iconBorderColor, false)
        if not pFrame then return end
        pFrame:EnableMouse(true)
        pFrame.icon = pFrame.texture
        row.profIcons[idx] = pFrame
    end
    pFrame:SetSize(iconSize, iconSize)
    pFrame:ClearAllPoints()
    pFrame:SetPoint("LEFT", profX, 0)
    pFrame.icon:SetTexture(texture)
    pFrame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    pFrame.icon:SetDesaturated(true)
    pFrame.icon:SetAlpha(0.35)
    if pFrame.knowledgeBadge then pFrame.knowledgeBadge:Hide() end
    pFrame._wnProf, pFrame._wnProfChar, pFrame._wnProfID = nil, nil, nil
    pFrame:SetScript("OnEnter", nil)
    pFrame:SetScript("OnLeave", nil)
    pFrame:SetScript("OnMouseUp", nil)
    pFrame:Show()
end

function CharRowCb.ProfOnEnter(self)
    local prof, char = self._wnProf, self._wnProfChar
    if not prof or not char then return end
    local profName = prof.name or ((ns.L and ns.L["UNKNOWN_PROFESSION"]) or "Unknown Profession")
    local lines = {}

    -- A row with no name and no cap carries nothing a player can read -- it renders as "? -".
    -- Forever produces exactly one of those per profession: the expansion list is seeded from
    -- Midnight child skill lines (Mining picked up 2916) that have no data on a vanilla-plus
    -- client. Skip them here rather than at the source, so a half-streamed retail row is dropped
    -- the same way instead of printing a placeholder.
    local function IsReadableExpansion(exp)
        if type(exp) ~= "table" then return false end
        if exp.name and exp.name ~= "" then return true end
        return (tonumber(exp.maxSkillLevel) or 0) > 0
    end

    local expansions = char.professionExpansions and char.professionExpansions[profName]
    local readable = 0
    if expansions then
        for i = 1, #expansions do
            if IsReadableExpansion(expansions[i]) then readable = readable + 1 end
        end
    end
    if readable > 0 then
        for i = 1, #expansions do
            local exp = expansions[i]
            if IsReadableExpansion(exp) then
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
                    skillText = "-"
                end

                lines[#lines + 1] = {
                    left = exp.name or profName,
                    right = skillText,
                    leftColor = {1, 1, 1},
                    rightColor = skillColor
                }
            end
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
                    left = ns.UI_GetIconMarkup("attention", 0, 0) .. " " .. unspent .. " " .. ((ns.L and ns.L["UNSPENT_POINTS"]) or "Unspent Points"),
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
end

--[[
    Skills / Talents cells (WoW Forever).

    Each column is one icon. The tooltip lists what this character actually HAS -- the talents it
    took and the spells it knows -- not the catalogue of what exists; the full tree, with its
    locked tiers and the trainer's list, is a click away in the popup.

    Both columns collapse to zero width on a client without their system, so each painter checks
    the width it was handed rather than asking the capability again.
]]

--- Shared: one pooled icon per cell, with the hover / click scripts already attached.
--- Built through the Factory's CreateIcon so it carries the project's icon-well border -- a bare
--- texture sat flat beside the bordered profession icons.
local function AcquireCellIcon(row, field, iconKey, onEnter, onClick)
    local btn = row[field]
    if not btn then
        local borderColor = { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 }
        btn = CreateIcon(row, nil, CELL_ICON, false, borderColor, false)
        if not btn then return nil end
        btn.icon = btn.texture
        ns.UI_SetIcon(btn.icon, iconKey)
        btn:EnableMouse(true)
        btn:SetScript("OnEnter", onEnter)
        btn:SetScript("OnLeave", CharRowCb.HideTip)
        btn:SetScript("OnMouseUp", onClick)
        row[field] = btn
    end
    return btn
end

--- "There is something waiting here" badge, same glyph and corner the profession icons use for
--- unspent knowledge: a talent point not spent, or a spell the character is already high enough
--- to train. Both are things a player would otherwise have to go looking for.
local function SetCellBadge(btn, show)
    if not btn then return end
    if show then
        if not btn.pendingBadge then
            local badge = btn:CreateTexture(nil, "OVERLAY")
            badge:SetSize(16, 16)
            badge:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 5, 0)
            ns.UI_SetIcon(badge, "attention")
            btn.pendingBadge = badge
        end
        btn.pendingBadge:Show()
    elseif btn.pendingBadge then
        btn.pendingBadge:Hide()
    end
end

--- The tree the character actually specced into: the one holding the most points. nil until a
--- point is spent, which is the honest answer on a character below level 10.
local function ActiveTalentTab(talents)
    local best, bestSpent = nil, 0
    for i = 1, #(talents.tabs or {}) do
        local tab = talents.tabs[i]
        if (tab.spent or 0) > bestSpent then
            best, bestSpent = tab, tab.spent
        end
    end
    return best
end

function CharRowCb.TalentsOnEnter(self)
    local char = self._wnTalentsChar
    if not char then return end
    local key = GetCharKey(char)
    local systems = WarbandNexus.GetCharacterSystems and WarbandNexus:GetCharacterSystems(key) or nil
    local talents = systems and systems.talents
    local L = ns.L
    local lines = {}

    local active = talents and ActiveTalentTab(talents)
    if not active then
        lines[#lines + 1] = {
            left = (L and L["TALENTS_NONE_SELECTED"]) or "No talents selected yet",
            leftColor = { 0.7, 0.7, 0.75 },
        }
    else
        lines[#lines + 1] = {
            left = active.name
                or string.format((L and L["TALENTS_TREE"]) or "Tree %d", active.index),
            right = tostring(active.spent or 0),
            leftColor = { 1, 1, 1 },
            rightColor = { 0.3, 0.9, 0.3 },
        }
        -- Only the talents that were taken: that is what "selected" means here.
        for k = 1, #active.tierOrder do
            local tier = active.tiers[active.tierOrder[k]]
            for n = 1, #tier.nodes do
                local node = tier.nodes[n]
                if (node.rank or 0) > 0 then
                    lines[#lines + 1] = {
                        left = "  " .. (node.name or "?"),
                        right = string.format("%d/%d", node.rank, node.maxRanks or 0),
                        leftColor = { 0.9, 0.9, 0.95 },
                        rightColor = { 0.3, 0.9, 0.3 },
                    }
                end
            end
        end
    end
    if talents and (talents.unspent or 0) > 0 then
        local gr, gg, gb = SemanticGoldRGB()
        lines[#lines + 1] = { left = " ", leftColor = { 1, 1, 1 } }
        lines[#lines + 1] = {
            left = (L and L["TALENTS_UNSPENT"]) or "Unspent points",
            right = tostring(talents.unspent),
            leftColor = { 1, 1, 1 },
            rightColor = { gr, gg, gb },
        }
    end

    ShowTooltip(self, {
        type = "custom",
        icon = "talents",
        title = (L and L["CHARS_COL_TALENTS"]) or "Talents",
        lines = lines,
    })
end

function CharRowCb.SkillsOnEnter(self)
    local char = self._wnSkillsChar
    if not char then return end
    local key = GetCharKey(char)
    local systems = WarbandNexus.GetCharacterSystems and WarbandNexus:GetCharacterSystems(key) or nil
    local spells = systems and systems.spells
    local L = ns.L
    local lines = {}

    -- One line. The list itself is a window: a spellbook does not fit in a tooltip, and the icons
    -- are the point of it.
    if spells and spells.known then
        lines[#lines + 1] = {
            left = (L and L["SKILLS_KNOWN"]) or "Known",
            right = tostring(spells.known),
            leftColor = { 1, 1, 1 },
            rightColor = { 0.3, 0.9, 0.3 },
        }
    end
    lines[#lines + 1] = {
        left = HEX.green .. ((L and L["SKILLS_CLICK_TO_OPEN"]) or "Click to open the skill list") .. "|r",
        leftColor = { 1, 1, 1 },
    }

    ShowTooltip(self, {
        type = "custom",
        icon = "skills",
        title = (L and L["CHARS_COL_SKILLS"]) or "Skills",
        lines = lines,
    })
end

--- Clicking either cell opens the full view: the tooltip is what you have, the popup is the tree.
function CharRowCb.SkillsOnClick(self)
    local char = self._wnSkillsChar
    if not char or not WarbandNexus.ShowSkillsPopup then return end
    CharRowCb.HideTip()
    local key = GetCharKey(char)
    local name = (ns.Utilities and ns.Utilities.GetCharacterDisplayName
        and ns.Utilities:GetCharacterDisplayName(char)) or char.name
    WarbandNexus:ShowSkillsPopup(key, name, char.classFile, tonumber(char.level))
end

function CharRowCb.TalentsOnClick(self)
    local char = self._wnTalentsChar
    if not char or not WarbandNexus.ShowTalentTreePopup then return end
    CharRowCb.HideTip()
    local key = GetCharKey(char)
    local name = (ns.Utilities and ns.Utilities.GetCharacterDisplayName
        and ns.Utilities:GetCharacterDisplayName(char)) or char.name
    WarbandNexus:ShowTalentTreePopup(key, name)
end

--- Skills cell: one icon, centred in its column.
function CharRowCb.PaintSkillsCell(row, char, width, offset)
    if width <= 0 then
        if row.skillsIcon then row.skillsIcon:Hide() end
        return
    end
    local btn = AcquireCellIcon(row, "skillsIcon", "skills",
        CharRowCb.SkillsOnEnter, CharRowCb.SkillsOnClick)
    if not btn then return end
    btn._wnSkillsChar = char
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", offset + (width - CELL_ICON) / 2, 0)
    -- Only spells the level already allows: a locked one is not something to act on yet.
    local key, classFile, level = GetCharKey(char), char.classFile, tonumber(char.level)
    local summary = WarbandNexus.GetSkillSummary
        and WarbandNexus:GetSkillSummary(key, classFile, level) or nil
    SetCellBadge(btn, summary and summary.hasTrainerData and #summary.trainable > 0)
    btn:Show()
end

--- Talents cell: one icon, centred in its column.
function CharRowCb.PaintTalentsCell(row, char, width, offset)
    if width <= 0 then
        if row.talentsIcon then row.talentsIcon:Hide() end
        return
    end
    local btn = AcquireCellIcon(row, "talentsIcon", "talents",
        CharRowCb.TalentsOnEnter, CharRowCb.TalentsOnClick)
    if not btn then return end
    btn._wnTalentsChar = char
    btn:ClearAllPoints()
    btn:SetPoint("LEFT", offset + (width - CELL_ICON) / 2, 0)
    local systems = WarbandNexus.GetCharacterSystems
        and WarbandNexus:GetCharacterSystems(GetCharKey(char)) or nil
    local talents = systems and systems.talents
    SetCellBadge(btn, talents and (talents.unspent or 0) > 0)
    btn:Show()
end

--- Realm type cell (WoW Forever): the PvE / PvP / RP tag that used to sit under the character
--- name. It moved out so the identity block's second line could carry the surname instead.
function CharRowCb.PaintRealmTypeCell(row, char, width, offset)
    if width <= 0 then
        if row.realmTypeText then row.realmTypeText:Hide() end
        return
    end
    if not row.realmTypeText then
        row.realmTypeText = FontManager:CreateFontString(row, "small", "OVERLAY")
        row.realmTypeText:SetJustifyH("CENTER")
    end
    -- Two lines: the realm / ruleset tag, then the Self-Found mark when that character has it.
    row.realmTypeText:SetMaxLines(2)
    row.realmTypeText:SetWidth(width)
    row.realmTypeText:ClearAllPoints()
    row.realmTypeText:SetPoint("LEFT", offset, 0)
    -- The row's OWN persisted ruleset first: the live answer belongs to whoever is logged in, so
    -- reading it here gave every row that character's ruleset.
    local rules = type(char.gameRules) == "table" and char.gameRules or nil
    local U = ns.Utilities
    local tag = rules and rules.ruleset
        or (U and U.FormatRealmName and U:FormatRealmName(char.realm)) or char.realm
    if not tag or (issecretvalue and issecretvalue(tag)) then tag = "" end
    local text = (tag == "") and (ThemeTextHex("Muted") .. "-|r") or tag
    if rules and rules.selfFound then
        local goldHex = (ns.UI_GetSemanticGoldHex and ns.UI_GetSemanticGoldHex()) or HEX.gold
        text = text .. "\n" .. goldHex .. ((ns.L and ns.L["CHAR_SELF_FOUND_TAG"]) or "Self-Found") .. "|r"
    end
    row.realmTypeText:SetText(text)
    ns.UI_SetTextColorRole(row.realmTypeText, "Normal")
    row.realmTypeText:Show()
    PresentFS(row.realmTypeText)
end

--- Clicking either cell opens the full view: the tooltip is the summary, the popup is the tree.
function CharRowCb.SkillsOnClick(self)
    local char = self._wnSkillsChar
    if not char or not WarbandNexus.ShowSkillsPopup then return end
    CharRowCb.HideTip()
    local key = GetCharKey(char)
    local name = (ns.Utilities and ns.Utilities.GetCharacterDisplayName
        and ns.Utilities:GetCharacterDisplayName(char)) or char.name
    WarbandNexus:ShowSkillsPopup(key, name, char.classFile, tonumber(char.level))
end

function CharRowCb.TalentsOnClick(self)
    local char = self._wnTalentsChar
    if not char or not WarbandNexus.ShowTalentTreePopup then return end
    CharRowCb.HideTip()
    local key = GetCharKey(char)
    local name = (ns.Utilities and ns.Utilities.GetCharacterDisplayName
        and ns.Utilities:GetCharacterDisplayName(char)) or char.name
    WarbandNexus:ShowTalentTreePopup(key, name)
end


function CharRowCb.ProfOnClick(self)
    local char, profID = self._wnProfChar, self._wnProfID
    if not char or not profID or not WarbandNexus.ShowProfessionRecipesPopup then return end
    -- Recipes only exist once that profession's own window has been opened, so a click before
    -- that would do nothing at all and read as a broken button. Say what is missing instead.
    local have = WarbandNexus.GetProfessionRecipes
        and WarbandNexus:GetProfessionRecipes(GetCharKey(char), profID)
    if not have then
        WarbandNexus:Print(HEX.gold .. "[WN]|r "
            .. ((ns.L and ns.L["RECIPES_OPEN_WINDOW_ONCE"])
                or "Open this profession's window once to list its recipes."))
        return
    end
    CharRowCb.HideTip()
    local name = (ns.Utilities and ns.Utilities.GetCharacterDisplayName
        and ns.Utilities:GetCharacterDisplayName(char)) or char.name
    WarbandNexus:ShowProfessionRecipesPopup(GetCharKey(char), name, profID)
end

function CharRowCb.TrackingOnClick(selfBtn)
    local CS = ns.CharacterService
    if not CS or not CS.ShowTrackingChangeConfirmation then return end
    local addon = WarbandNexus
    local ck = selfBtn.charKey
    local rowKey = (ns.Utilities and ns.Utilities.GetCanonicalCharacterKey and ck)
        and ns.Utilities:GetCanonicalCharacterKey(ck) or ck
    local rowData = addon and addon.db and addon.db.global and addon.db.global.characters
        and rowKey and (addon.db.global.characters[rowKey] or (ck and addon.db.global.characters[ck]))
    if selfBtn.trackingKey and addon.db.global.characters[selfBtn.trackingKey] then
        rowData = addon.db.global.characters[selfBtn.trackingKey]
    end
    local tracked = rowData and rowData.isTracked ~= false
    CS:ShowTrackingChangeConfirmation(addon, selfBtn.trackingKey or rowKey or ck, selfBtn.charName, not tracked)
end

function CharRowCb.TrackingOnEnter(selfBtn)
    local char = selfBtn._wnCharRowChar
    if not char then return end
    local tracked = char.isTracked ~= false
    ShowTooltip(selfBtn, {
        type = "custom",
        title = (ns.L and ns.L["TRACKING_TOGGLE_TOOLTIP_TITLE"]) or "Character tracking",
        description = tracked
            and ((ns.L and ns.L["TRACKING_TOGGLE_DISABLE_HINT"]) or "Click to disable tracking.")
            or ((ns.L and ns.L["TRACKING_TOGGLE_ENABLE_HINT"]) or "Click to enable tracking."),
    })
end

function CharRowCb.ReorderOnClick(selfBtn)
    local rb = selfBtn._wnReorderHost
    if not rb or not rb._wnCharRowChar then return end
    WarbandNexus:ReorderCharacter(rb._wnCharRowChar, rb._wnCharList, rb._wnListKey, selfBtn._wnReorderDir)
end

function CharRowCb.RequestMainRefresh()
    WarbandNexus:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { skipCooldown = true })
end

function CharRowCb.HeaderAssignOnClick(selfBtn)
    if ns.UI_ShowCharacterSectionAssignMenu then
        ns.UI_ShowCharacterSectionAssignMenu(selfBtn, selfBtn._wnCharRowKey, WarbandNexus.db.profile, CharRowCb.RequestMainRefresh)
    end
end

function CharRowCb.HeaderAssignOnEnter(selfBtn)
    ShowTooltip(selfBtn, {
        type = "custom",
        title = (ns.L and ns.L["CUSTOM_HEADER_ASSIGN_TOOLTIP_TITLE"]) or "Custom header",
        description = (ns.L and ns.L["CUSTOM_HEADER_ASSIGN_TOOLTIP_DESC"]) or "Move this character into a header. Use the + button (left of Filter) to create headers, or Filter -> New custom header.",
    })
end

function CharRowCb.DeleteOnClick(self)
    -- Use custom themed delete dialog
    local charKey = self.charKey
    local charName = self.charName
    local char = self._wnCharRowChar
    
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
        icon = ns.UI_GetIconFile("warning"),
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
        warning:SetTextColor(ns.UI_GetSemanticGoldColor())
    end
    local confirmDeleteFmt = (ns.L and ns.L["CONFIRM_DELETE"]) or "Are you sure you want to delete " .. HEX.info .. "%s|r?"
    warning:SetText(string.format(confirmDeleteFmt, charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")))
    
    local subtext = FontManager:CreateFontString(contentFrame, "body", "OVERLAY")
    subtext:SetPoint("TOPLEFT", warning, "BOTTOMLEFT", 0, -10)
    subtext:SetPoint("TOPRIGHT", warning, "BOTTOMRIGHT", 0, -10)
    subtext:SetJustifyH("CENTER")
    if ns.UI_GetSemanticRedColor then
        local rr, rg, rb = ns.UI_GetSemanticRedColor()
        subtext:SetTextColor(rr, rg, rb)
    else
        subtext:SetTextColor(ns.UI_GetSemanticRedColor())
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
end

function CharRowCb.DeleteOnEnter(self)
    if self.icon then
        StyleCharacterDeleteIcon(self.icon, true)
    end
    local removeFromTrackingFmt = (ns.L and ns.L["REMOVE_FROM_TRACKING_FORMAT"]) or "Remove %s from tracking"
    ShowTooltip(self, {
        type = "custom",
        icon = "close",
        title = (ns.L and ns.L["DELETE_CHARACTER"]) or "Delete Character",
        titleColor = {1, 0.4, 0},
        description = string.format(removeFromTrackingFmt, self.charName or ((ns.L and ns.L["THIS_CHARACTER"]) or "this character")),
        lines = {
            {text = HEX.red .. ((ns.L and ns.L["CANNOT_UNDO"]) or "This action cannot be undone!") .. "|r", color = {1, 0.2, 0.2}},
            {type = "spacer"},
            {text = HEX.green .. ((ns.L and ns.L["CLICK_TO_DELETE"]) or "Click to delete") .. "|r", color = {1, 1, 1}}
        },
    })
end

function CharRowCb.DeleteOnLeave(self)
    if self.icon then
        StyleCharacterDeleteIcon(self.icon, false)
    end
    if HideTooltip then
        HideTooltip()
    end
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

    row.mailBtn:SetScript("OnEnter", ShowCharacterMailTooltip)
    row.mailBtn:SetScript("OnClick", TryOpenMailDetailsPopup)
    row.mailBtn:SetScript("OnLeave", CharRowCb.HideTip)
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
    row._wnCharRowChar = char
    row._wnCharRowKey = charKey
    row._wnCharRowIsCurrent = isCurrent
    row:SetScript("OnMouseUp", CharRowCb.RowOnMouseUp)
    
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
        row.favButton:SetScript("OnClick", CharRowCb.FavOnClick)
    end
    
    -- Tooltip for favorite button
    if ShowTooltip and row.favButton.SetScript then
        row.favButton:SetScript("OnEnter", CharRowCb.FavOnEnter)
        row.favButton:SetScript("OnLeave", CharRowCb.HideTooltipOnly)
    end
    
    -- COLUMN 2: Faction icon
    local factionOffset = GetColumnOffset("faction")
    if char.faction then
        if not row.factionIcon then
            row.factionIcon = CreateFactionIcon(row, char.faction, CHAR_ROW_COLUMNS.faction.width, "LEFT", factionOffset + (CHAR_ROW_COLUMNS.faction.spacing / 2), 0)
        end
        if char.faction == "Alliance" then
            ns.UI_SetIcon(row.factionIcon, "faction_alliance")
        elseif char.faction == "Horde" then
            ns.UI_SetIcon(row.factionIcon, "faction_horde")
        else
            ns.UI_SetIcon(row.factionIcon, "faction_alliance")  -- unknown faction keeps the Alliance emblem
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
        ns.UI_ApplyClassIconTexture(row.classIcon, char.classFile)
        row.classIcon:Show()
    elseif row.classIcon then
        row.classIcon:Hide()
    end
    
    -- COLUMN 5: Name
    local nameOffset = GetColumnOffset("name")
    local nameLeftPadding = 4
    -- Name + realm subline + class gradient: shared roster identity (SharedWidgets_RowPool); PvE, PvP and
    -- Professions rows paint the same block. Pooled rows re-anchor every paint.
    ns.UI_ApplyCharacterRowIdentity(row, char, nameOffset + nameLeftPadding, CHAR_ROW_COLUMNS.name.width)
    if row.mailIcon then
        row.mailIcon:Hide()
    end
    
    -- COLUMN: Guild - width from the widest guild name; text centred in its column.
    -- Flex columns: same resolver as ApplyCharacterRowInteriorLayout so first paint and
    -- resize relayout agree on effective widths (narrow rows shrink toward column minimums).
    local flexCols = ns.UI_ComputeCharRowFlexColumns
        and ns.UI_ComputeCharRowFlexColumns(width, self._charListMaxGuildWidth) or nil
    local guildOffset = GetColumnOffset("guild")
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

    -- Level column: level + rested line (DB-driven). Everything before it is fixed width, so it
    -- reads its offset from the column order rather than chaining off Guild.
    local levelOffset = GetColumnOffset("level")
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
            row.levelRestedText:SetText(string.format(HEX.info .. "Zzz %.2f%%|r", restedPct))
        else
            row.levelRestedText:SetText(string.format(HEX.info .. "%.2f%%|r", restedPct))
        end
        PresentFS(row.levelRestedText)
        row.levelRestedText:Show()
    else
        row.levelRestedText:Hide()
    end

    if row.levelRestedIcon then row.levelRestedIcon:Hide() end
    if row.levelRestedHitFrame then row.levelRestedHitFrame:Hide() end

    -- Guild is the only measured column, so the rest of the row is chained off its real width.
    local guildTotal = guildColW + guildSpacing
    local mailOffset = guildOffset + guildTotal
    local realmTypeOffset = mailOffset + ((CHAR_ROW_COLUMNS.mail and CHAR_ROW_COLUMNS.mail.total) or 46)

    -- COLUMN: Realm type (WoW Forever) - PvE / PvP / RP; collapses to 0 elsewhere.
    local realmTypeW = (flexCols and flexCols.realmType) or CHAR_ROW_COLUMNS.realmType.width
    CharRowCb.PaintRealmTypeCell(row, char, realmTypeW, realmTypeOffset)

    -- COLUMN: Item Level (chained from the realm type tag)
    local itemLevelW = (flexCols and flexCols.itemLevel) or CHAR_ROW_COLUMNS.itemLevel.width
    local itemLevelOffset = realmTypeOffset + realmTypeW
        + ((realmTypeW > 0) and (CHAR_ROW_COLUMNS.realmType.spacing or 0) or 0)
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
        local iconSpacing = PROF_ICON_GAP
        local useSlots = WarbandNexus.SupportsFeature
            and WarbandNexus:SupportsFeature("firstAidProfession")

        if useSlots then
            -- Five fixed slots, drawn left to right. A secondary the character has not
            -- taken is still drawn, greyed, so the row says "no fishing" rather than
            -- saying nothing -- and every alt lines up column by column.
            local slots = #PROF_SLOT_ORDER
            local iconSize = ProfIconSize(profW, slots)
            local totalIconWidth = (slots * iconSize) + ((slots - 1) * iconSpacing)
            local x = profOffset + (profW - totalIconWidth) / 2
            for i = 1, slots do
                local slot = PROF_SLOT_ORDER[i]
                local data = char.professions[slot.key]
                if data then
                    CharRowCb.SetupProfIcon(row, char, data, i, x, iconSize)
                else
                    CharRowCb.SetupProfPlaceholder(row, i, x, iconSize, ProfSlotPlaceholder(slot))
                end
                x = x + iconSize + iconSpacing
            end
            -- Exactly five. Pooled frames from a paint that drew more would otherwise hang on
            -- past the strip, which is where the sixth icon came from.
            for i = slots + 1, #row.profIcons do
                row.profIcons[i]:Hide()
            end
        else
            local secondaryKeys = SecondaryProfKeys()

            -- Count total professions first
            local numProfs = 0
            if char.professions[1] then numProfs = numProfs + 1 end
            if char.professions[2] then numProfs = numProfs + 1 end
            for i = 1, #secondaryKeys do
                local sec = secondaryKeys[i]
                if char.professions[sec] then numProfs = numProfs + 1 end
            end
            -- Two primaries plus three secondaries is five icons where the column was sized for
            -- three, so the square shrinks to fit rather than bleeding into the next column.
            local iconSize = ProfIconSize(profW, numProfs)

            -- Calculate centered starting position (within column content area, excluding right spacing)
            local totalIconWidth = (numProfs * iconSize) + ((numProfs - 1) * iconSpacing)
            -- Center the icons within the effective (flex) column width
            local leftPadding = (profW - totalIconWidth) / 2
            local currentProfX = profOffset + leftPadding
        
            local charKey = GetCharKey(char)
        
            local pIdx = 1
            -- Primary
            if char.professions[1] then
                CharRowCb.SetupProfIcon(row, char, char.professions[1], pIdx, currentProfX, iconSize)
                pIdx = pIdx + 1
                currentProfX = currentProfX + iconSize + iconSpacing
            end
            if char.professions[2] then
                CharRowCb.SetupProfIcon(row, char, char.professions[2], pIdx, currentProfX, iconSize)
                pIdx = pIdx + 1
                currentProfX = currentProfX + iconSize + iconSpacing
            end
            -- Secondary
            for i = 1, #secondaryKeys do
                local sec = secondaryKeys[i]
                if char.professions[sec] then
                    CharRowCb.SetupProfIcon(row, char, char.professions[sec], pIdx, currentProfX, iconSize)
                    pIdx = pIdx + 1
                    currentProfX = currentProfX + iconSize + iconSpacing
                end
            end
        end
    end
    
    -- COLUMN: Skills (WoW Forever) - how many abilities are waiting at the class trainer.
    local skillsW = (flexCols and flexCols.skills) or CHAR_ROW_COLUMNS.skills.width
    local skillsOffset = profOffset + profW + (CHAR_ROW_COLUMNS.professions.spacing or 0)
    CharRowCb.PaintSkillsCell(row, char, skillsW, skillsOffset)

    -- COLUMN: Talents (WoW Forever) - points per tab, read left to right as a vanilla build.
    local talentsW = (flexCols and flexCols.talents) or CHAR_ROW_COLUMNS.talents.width
    local talentsOffset = skillsOffset + skillsW
        + ((skillsW > 0) and (CHAR_ROW_COLUMNS.skills.spacing or 0) or 0)
    CharRowCb.PaintTalentsCell(row, char, talentsW, talentsOffset)

    -- COLUMN 10: Mythic Keystone (dynamic offset, chained from the talents column)
    local mythicKeyW = (flexCols and flexCols.mythicKey) or CHAR_ROW_COLUMNS.mythicKey.width
    local mythicKeyOffset = talentsOffset + talentsW
        + ((talentsW > 0) and (CHAR_ROW_COLUMNS.talents.spacing or 0) or 0)

    if mythicKeyW == 0 then
        if row.keystoneIcon then row.keystoneIcon:Hide() end
        if row.keystoneText then row.keystoneText:Hide() end
    else

    -- Create keystone icon (shared for has-key and no-key)
    if not row.keystoneIcon then
        row.keystoneIcon = row:CreateTexture(nil, "ARTWORK")
        row.keystoneIcon:SetSize(24, 24)  -- Increased 20% (20 -> 24)

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
        -- HAS KEY: +Level * Dungeon (colored, bright icon)
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
        -- NO KEY: +0 * None (dimmed, desaturated icon)
        local keystoneText = ThemeTextHex("Muted") .. "+0|r " .. ThemeTextHex("Muted") .. "•|r "
            .. ThemeTextHex("Normal") .. ((ns.L and ns.L["NONE_LABEL"]) or "None") .. "|r"
        
        row.keystoneText:SetText(keystoneText)
        
        -- Dimmed colored item art (GRAY BAN: no desaturated grey or theme ink; alpha only)
        row.keystoneIcon:SetDesaturated(false)
        row.keystoneIcon:SetVertexColor(1, 1, 1, 1)
        row.keystoneIcon:SetAlpha(0.45)
    end
    
    row.keystoneIcon:Show()
    row.keystoneText:Show()

    end
    -- COLUMN: Mail (snapshot from last login on this character)

    -- mailOffset was chained off the measured guild width above.
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
    do
        local chars = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.characters
        local rowIndex = char._key
        row.trackingBtn.trackingKey = (rowIndex and chars and chars[rowIndex] ~= nil) and rowIndex or nil
    end
    row.trackingBtn.charName = DisplayName(char) or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
    if row.trackingBtn.icon then
        if isCharTracked then
            if ns.UI_SetIcon then ns.UI_SetIcon(row.trackingBtn.icon, "status_ok") end
        else
            if ns.UI_SetIcon then ns.UI_SetIcon(row.trackingBtn.icon, "status_fail") end
        end
    end
    if row.trackingBtn.HasScript and row.trackingBtn:HasScript("OnClick") then
        row.trackingBtn:SetScript("OnClick", CharRowCb.TrackingOnClick)
    end
    if ShowTooltip and row.trackingBtn.SetScript then
        row.trackingBtn._wnCharRowChar = char
        row.trackingBtn:SetScript("OnEnter", CharRowCb.TrackingOnEnter)
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
        -- registry glyph on a pooled row (colored art, neutral vertex); tracked so a mono entry would re-tint on theme toggle
        if ns.UI_GetIconFile then
            rb.up:SetNormalTexture(ns.UI_GetIconFile("chevron_up"))
            if ns.UI_SetIcon(rb.up:GetNormalTexture(), "chevron_up") and ns.UI_TrackRegistryIconTint then
                ns.UI_TrackRegistryIconTint(rb.up:GetNormalTexture(), "chevron_up")
            end
        end
        rb.up:EnableMouse(true)
        rb.down = ns.UI.Factory:CreateButton(rb, 18, 18, true)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(rb.down) end
        rb.down:SetPoint("CENTER", 11, 0)
        if ns.UI_GetIconFile then
            rb.down:SetNormalTexture(ns.UI_GetIconFile("chevron_down"))
            if ns.UI_SetIcon(rb.down:GetNormalTexture(), "chevron_down") and ns.UI_TrackRegistryIconTint then
                ns.UI_TrackRegistryIconTint(rb.down:GetNormalTexture(), "chevron_down")
            end
        end
        rb.down:EnableMouse(true)
        row.reorderButtons = rb
    else
        row.reorderButtons:SetParent(rail)
    end
    row.reorderButtons:ClearAllPoints()
    row.reorderButtons:SetPoint("RIGHT", rail, "RIGHT", -insetReorder, 0)
    
    if showReorder and charList then
        row.reorderButtons:Show()
        row.reorderButtons._wnCharRowChar = char
        row.reorderButtons._wnCharList = charList
        row.reorderButtons._wnListKey = listKey
        -- Always set OnClick (WoW Button supports SetScript even without prior script; HasScript can be false before first set)
        if row.reorderButtons.up then
            row.reorderButtons.up:EnableMouse(true)
            row.reorderButtons.up._wnReorderHost = row.reorderButtons
            row.reorderButtons.up._wnReorderDir = -1
            row.reorderButtons.up:SetScript("OnClick", CharRowCb.ReorderOnClick)
        end
        if row.reorderButtons.down then
            row.reorderButtons.down:EnableMouse(true)
            row.reorderButtons.down._wnReorderHost = row.reorderButtons
            row.reorderButtons.down._wnReorderDir = 1
            row.reorderButtons.down:SetScript("OnClick", CharRowCb.ReorderOnClick)
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
                row.onlineText:SetTextColor(ns.UI_GetSemanticGreenColor())
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
                ns.UI_SetIcon(htex, "checklist")
            end
            row.headerAssignBtn = hb
        else
            row.headerAssignBtn:SetParent(rail)
        end
        row.headerAssignBtn:ClearAllPoints()
        row.headerAssignBtn:SetPoint("RIGHT", rail, "RIGHT", -(insetHeader + 11), 0)
        if ns.UI.Factory.ApplyIconOnlyButtonChrome then ns.UI.Factory:ApplyIconOnlyButtonChrome(row.headerAssignBtn) end
        row.headerAssignBtn:Show()
        row.headerAssignBtn._wnCharRowKey = charKey
        row.headerAssignBtn:SetScript("OnClick", CharRowCb.HeaderAssignOnClick)
        if ShowTooltip then
            row.headerAssignBtn:SetScript("OnEnter", CharRowCb.HeaderAssignOnEnter)
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
            if ns.UI_SetIcon then ns.UI_SetIcon(icon, "close") end
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
        row.deleteBtn.charName = DisplayName(char) or ((ns.L and ns.L["UNKNOWN"]) or "Unknown")
        
        -- Safely set OnClick
        if row.deleteBtn.HasScript and row.deleteBtn:HasScript("OnClick") then
            row.deleteBtn._wnCharRowChar = char
            row.deleteBtn:SetScript("OnClick", CharRowCb.DeleteOnClick)
        end
        
        if row.deleteBtn.icon then
            StyleCharacterDeleteIcon(row.deleteBtn.icon, false)
        end

        -- Tooltip for delete button
        if ShowTooltip and row.deleteBtn.SetScript then
            row.deleteBtn:SetScript("OnEnter", CharRowCb.DeleteOnEnter)
            row.deleteBtn:SetScript("OnLeave", CharRowCb.DeleteOnLeave)
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
    
    -- Re-run the identity gradient now that the row has its final width (thunk set by UI_ApplyCharacterRowIdentity).
    if row._wnGradientRefresh then
        row._wnGradientRefresh()
    end

    local betweenRows = GetLayout().betweenRows or 0
    return yOffset + 46 + betweenRows, row  -- Row 46px + spacing + row ref for pool tracking
end

ns.CharactersUI.ApplyCharacterRowInteriorLayout = ApplyCharacterRowInteriorLayout
