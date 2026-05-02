--[[
    WarbandNexus - Vault Ready Button
    Draggable button showing Great Vault status across all characters.
    - Hover: compact list of ready/pending characters
    - Click: full table view (Name | iLvl | Raid | Dungeon | World | Status)
    - Row hover: tooltip showing iLvl reward per vault slot
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

-- ============================================================================
-- Constants
-- ============================================================================
local BUTTON_SIZE   = 48
local BADGE_SIZE    = 18
local ROW_H         = 28
local HEADER_H      = 24
local FRAME_PAD     = 8
local MAX_ROWS      = 20
local ICON_TEXTURE  = "Interface\\AddOns\\WarbandNexus\\Media\\icon"
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_TreasureChest02"
local VOIDCORE_ID   = 3418
local MANAFLUX_ID   = 3378
local BOUNTY_ITEM_ID = 252415

local COL_NAME      = 140
local COL_ILVL      = 50
local COL_RAID      = 62
local COL_DUNGEON   = 62
local COL_WORLD     = 62
local COL_REWARD_ILVL = 72
local COL_BOUNTY    = 46   -- Trovehunter's Bounty (done/not)
local COL_VOIDCORE  = 58   -- Nebulous Voidcore (current/seasonMax)
local COL_MANAFLUX  = 58   -- Dawnlight Manaflux (current held)
local COL_STATUS    = 78

local TRACK_ICONS = {
    raids      = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    mythicPlus = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
    world      = "Interface\\Icons\\INV_Misc_Map_01",
    bounty     = 1064187,
    voidcore   = 7658128,
    manaflux   = "Interface\\Icons\\INV_Enchant_DustArcane",
}

local CHECK  = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local CROSS  = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
local DASH   = "|cff666666-|r"

local function GetCurrencyIcon(currencyID, fallback)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.iconFileID then
            return info.iconFileID
        end
    end
    return fallback
end

local S

-- ============================================================================
-- DB helpers
-- ============================================================================
local function GetThemeColors()
    return ns.UI_COLORS or {
        accent = {0.40, 0.20, 0.58},
        accentDark = {0.28, 0.14, 0.41},
        border = {0.20, 0.20, 0.25},
        bg = {0.06, 0.06, 0.08, 0.98},
        bgCard = {0.08, 0.08, 0.10, 1},
        textDim = {0.55, 0.55, 0.55, 1},
    }
end

local function GetSettings()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then
        return {
            enabled = true,
            hideUntilMouseover = false,
            hideUntilReady = false,
            showRewardItemLevel = false,
            showManaflux = false,
            opacity = 1.0,
            position = { point = "CENTER", relativePoint = "CENTER", x = 600, y = 0 },
        }
    end

    local profile = WarbandNexus.db.profile
    profile.vaultButton = profile.vaultButton or {}
    local settings = profile.vaultButton
    if settings.enabled == nil then settings.enabled = true end
    if settings.hideUntilMouseover == nil then settings.hideUntilMouseover = false end
    if settings.hideUntilReady == nil then settings.hideUntilReady = false end
    if settings.showRealmName == nil then settings.showRealmName = false end
    if settings.showRewardItemLevel == nil then settings.showRewardItemLevel = false end
    if settings.showManaflux == nil then settings.showManaflux = false end
    settings.columns = settings.columns or {}
    if settings.columns.raids == nil then settings.columns.raids = true end
    if settings.columns.mythicPlus == nil then settings.columns.mythicPlus = true end
    if settings.columns.world == nil then settings.columns.world = true end
    if settings.columns.bounty == nil then settings.columns.bounty = true end
    if settings.columns.voidcore == nil then settings.columns.voidcore = true end
    if settings.columns.manaflux == nil then settings.columns.manaflux = settings.showManaflux == true end
    settings.showManaflux = settings.columns.manaflux == true
    settings.opacity = tonumber(settings.opacity) or 1.0
    if settings.opacity < 0.2 then settings.opacity = 0.2 end
    if settings.opacity > 1.0 then settings.opacity = 1.0 end

    if not settings.position then
        local legacy = profile.vaultButtonPos
        settings.position = {
            point = "CENTER",
            relativePoint = "CENTER",
            x = legacy and legacy.x or 600,
            y = legacy and legacy.y or 0,
        }
    end

    return settings
end

local function GetEnabledCategoryDefs()
    local settings = GetSettings()
    local columns = settings.columns or {}
    local width = settings.showRewardItemLevel and COL_REWARD_ILVL or nil
    local defs = {}
    if columns.raids ~= false then
        table.insert(defs, { key="raids", width=width or COL_RAID, label="Raid", icon=TRACK_ICONS.raids, tooltip="Raid" })
    end
    if columns.mythicPlus ~= false then
        table.insert(defs, { key="mythicPlus", width=width or COL_DUNGEON, label="Dungeon", icon=TRACK_ICONS.mythicPlus, tooltip="Dungeon" })
    end
    if columns.world ~= false then
        table.insert(defs, { key="world", width=width or COL_WORLD, label="World", icon=TRACK_ICONS.world, tooltip="World" })
    end
    return defs
end

local function GetTableWidth()
    local settings = GetSettings()
    local columns = settings.columns or {}
    local categoryWidth = 0
    for _, cat in ipairs(GetEnabledCategoryDefs()) do
        categoryWidth = categoryWidth + cat.width
    end
    local optionalWidth = 0
    if columns.bounty ~= false then optionalWidth = optionalWidth + COL_BOUNTY end
    if columns.voidcore ~= false then optionalWidth = optionalWidth + COL_VOIDCORE end
    if columns.manaflux == true then optionalWidth = optionalWidth + COL_MANAFLUX end
    return FRAME_PAD*2 + COL_NAME + COL_ILVL + categoryWidth + optionalWidth + COL_STATUS + 10
end

local RebuildTableFrame

local function GetPveCache()
    return WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
        and WarbandNexus.db.global.pveCache or nil
end

local function GetCharacters()
    return WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
        and WarbandNexus.db.global.characters or nil
end

local function GetSavedPos()
    return GetSettings().position
end

local function SavePos(point, relativePoint, x, y)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return end
    local settings = GetSettings()
    settings.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

local function GetSavedTablePos()
    return GetSettings().tablePosition
end

local function SaveTablePos(point, relativePoint, x, y)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return end
    local settings = GetSettings()
    settings.tablePosition = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

-- ============================================================================
-- Data helpers
-- ============================================================================
local function GetClassHex(classFile)
    local c = RAID_CLASS_COLORS and classFile and RAID_CLASS_COLORS[classFile]
    if c then
        return string.format("%02x%02x%02x",
            math.floor((c.r or 1)*255), math.floor((c.g or 1)*255), math.floor((c.b or 1)*255))
    end
    return "aaaaaa"
end

local function FormatCharacterName(entry)
    local name = entry and entry.name or ""
    local realm = entry and entry.realm or ""
    if GetSettings().showRealmName and realm ~= "" then
        name = name .. " - " .. realm
    end
    return "|cff" .. GetClassHex(entry and entry.classFile) .. name .. "|r"
end

local function GetCurrentCharKey()
    return ns.Utilities and ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey() or nil
end

local function GetCharActivities(charKey)
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    return pveCache.greatVault and pveCache.greatVault.activities
        and pveCache.greatVault.activities[charKey] or nil
end

local function HasAnyProgress(charKey)
    local acts = GetCharActivities(charKey)
    if not acts then return false end
    for _, cat in ipairs({ acts.raids, acts.mythicPlus, acts.world }) do
        if cat then
            for _, a in ipairs(cat) do
                local p = tonumber(a.progress) or 0
                local t = tonumber(a.threshold) or 0
                if t > 0 and p >= t then return true end
            end
        end
    end
    return false
end

local function GetSlotData(charKey, category)
    local acts = GetCharActivities(charKey)
    local cat  = acts and acts[category] or {}
    local slots = {}
    for i = 1, 3 do
        local a = cat[i]
        local prog   = a and (tonumber(a.progress) or 0) or 0
        local thresh = a and (tonumber(a.threshold) or 0) or 0
        slots[i] = {
            complete  = thresh > 0 and prog >= thresh,
            ilvl      = a and a.rewardItemLevel or 0,
            progress  = prog,
            threshold = thresh,
        }
    end
    return slots
end

--- Count how many vault slots are complete across all categories
local function CountReadySlots(charKey)
    local n = 0
    for _, cat in ipairs({ "raids", "mythicPlus", "world" }) do
        for _, s in ipairs(GetSlotData(charKey, cat)) do
            if s.complete then n = n + 1 end
        end
    end
    return n
end

--- Get Trovehunter's Bounty status for a character
--- Returns: true = done, false = not done, nil = unknown (never logged in)
local function GetBountyStatus(charKey)
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    local delveChar = pveCache.delves and pveCache.delves.characters
        and pveCache.delves.characters[charKey]
    if not delveChar then return nil end
    return delveChar.bountifulComplete
end

--- Get Nebulous Voidcore data for a character { current, seasonMax }
--- Uses WarbandNexus:GetCurrencyData which reads from CurrencyCacheService.
--- - quantity    = how many you currently hold (unspent)
--- - totalEarned = season progress (how many earned this season, shown as X/seasonMax)
--- - seasonMax   = season cap (increases by 2 each week)
local function GetVoidcoreData(charKey)
    if not WarbandNexus or not WarbandNexus.GetCurrencyData then return nil end
    local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, VOIDCORE_ID, charKey)
    if not ok or not cd then return nil end
    local sm = tonumber(cd.seasonMax) or 0
    local te = tonumber(cd.totalEarned) or 0
    local qty = tonumber(cd.quantity) or 0
    -- If useTotalEarnedForMaxQty, season progress = totalEarned; otherwise use quantity
    local progress = cd.useTotalEarnedForMaxQty and te or qty
    return {
        quantity    = qty,        -- currently held (unspent)
        progress    = progress,   -- season earned (for X/seasonMax display)
        seasonMax   = sm,
        isCapped    = sm > 0 and progress >= sm,
    }
end

--- Get Dawnlight Manaflux data for a character { quantity }
local function GetManafluxData(charKey)
    if not WarbandNexus or not WarbandNexus.GetCurrencyData then return nil end
    local ok, cd = pcall(WarbandNexus.GetCurrencyData, WarbandNexus, MANAFLUX_ID, charKey)
    if not ok or not cd then return nil end
    return {
        quantity = tonumber(cd.quantity) or 0,
        totalEarned = tonumber(cd.totalEarned) or 0,
    }
end

--- Open WarbandNexus main window on the PvE tab
local function OpenWNPveTab()
    if WarbandNexus and WarbandNexus.ShowMainWindow then
        WarbandNexus:ShowMainWindow()
        C_Timer.After(0.05, function()
            local mf = WarbandNexus.mainFrame
            if mf and mf.tabButtons and mf.tabButtons["pve"] then
                mf.tabButtons["pve"]:Click()
            end
        end)
    end
end

local WORLD_REWARD_QUALITY_BY_ILVL = {
    [233] = 3, [237] = 3, [240] = 3, [243] = 3,
    [246] = 4, [250] = 4, [253] = 4,
    [259] = 5,
}

local function ColorByItemQuality(value, quality)
    local color = ITEM_QUALITY_COLORS and quality and ITEM_QUALITY_COLORS[quality]
    if color and color.hex then
        return color.hex .. tostring(value) .. "|r"
    end
    return "|cffd4af37" .. tostring(value) .. "|r"
end

local function FormatRewardIlvl(ilvl, category)
    ilvl = tonumber(ilvl) or 0
    if ilvl <= 0 then return CHECK end
    if category == "world" then
        return ColorByItemQuality(ilvl, WORLD_REWARD_QUALITY_BY_ILVL[ilvl])
    end
    return "|cffd4af37" .. ilvl .. "|r"
end

local function SlotSymbols(slots, category)
    local settings = GetSettings()
    local parts = {}
    for i = 1, 3 do
        local slot = slots[i]
        if slot.complete then
            table.insert(parts, settings.showRewardItemLevel and FormatRewardIlvl(slot.ilvl, category) or CHECK)
        else
            table.insert(parts, CROSS)
        end
    end
    return table.concat(parts, " ")
end

local function BuildCharList()
    local pveCache   = GetPveCache()
    local characters = GetCharacters()
    if not pveCache or not characters then return {} end
    local rewards    = pveCache.greatVault and pveCache.greatVault.rewards
    local currentKey = GetCurrentCharKey()
    local result     = {}
    for charKey, charData in pairs(characters) do
        local rewardData = rewards and rewards[charKey]
        local isReady    = rewardData and rewardData.hasAvailableRewards or false
        local isPending  = not isReady and HasAnyProgress(charKey)
        if isReady or isPending then
            table.insert(result, {
                charKey   = charKey,
                name      = charData.name or charKey,
                realm     = charData.realm or "",
                classFile = charData.classFile or "WARRIOR",
                itemLevel = charData.itemLevel or 0,
                isReady   = isReady,
                isPending = isPending,
                isCurrent = (charKey == currentKey),
                bounty    = GetBountyStatus(charKey),
                voidcore  = GetVoidcoreData(charKey),
                manaflux  = GetManafluxData(charKey),
                slots     = CountReadySlots(charKey),
            })
        end
    end
    table.sort(result, function(a, b)
        if a.isCurrent ~= b.isCurrent then return a.isCurrent end
        if a.isReady   ~= b.isReady   then return a.isReady   end
        return a.name < b.name
    end)
    return result
end

local function CountReady()
    local n = 0
    for _, e in ipairs(BuildCharList()) do
        if e.isReady then n = n + 1 end
    end
    return n
end

-- ============================================================================
-- UI state
-- ============================================================================
S = {
    button=nil, icon=nil, badge=nil, badgeBg=nil, border=nil,
    tableFrame=nil, title=nil, headerBg=nil, separator=nil,
    optionsFrame=nil, optionsWidgets={}, rows={}
}

local HideTable
local RefreshTable
local RefreshButtonSettings
local UpdateBadge
local ToggleOptionsFrame

local function AddEscCloseFrame(frameName)
    if not frameName or not UISpecialFrames then return end
    for i = 1, #UISpecialFrames do
        if UISpecialFrames[i] == frameName then return end
    end
    table.insert(UISpecialFrames, frameName)
end

RebuildTableFrame = function()
    local wasShown = S.tableFrame and S.tableFrame:IsShown()
    local savedPoint, savedRelativePoint, savedX, savedY
    if wasShown and S.tableFrame then
        savedPoint, _, savedRelativePoint, savedX, savedY = S.tableFrame:GetPoint()
    end
    if S.tableFrame then
        S.tableFrame:Hide()
        S.tableFrame = nil
        S.tableScroll = nil
        S.tableContent = nil
        S.title = nil
        S.headerBg = nil
        S.separator = nil
        S.rows = {}
    end
    if wasShown then
        if savedX and savedY then
            SaveTablePos(savedPoint, savedRelativePoint, savedX, savedY)
        end
        C_Timer.After(0, function()
            RefreshTable()
            if S.tableFrame then
                S.tableFrame:ClearAllPoints()
                local saved = GetSavedTablePos()
                if saved and saved.x and saved.y then
                    S.tableFrame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x, saved.y)
                end
            end
        end)
    end
    return wasShown
end

local function ApplyTheme()
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}
    local accentDark = colors.accentDark or {0.28, 0.14, 0.41}
    local border = colors.border or accent

    if S.button then
        S.button:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
        S.button:SetBackdropBorderColor(0, 0, 0, 0)
    end
    if S.border then
        local readyCount = CountReady()
        if readyCount > 0 then
            S.border:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1)
        else
            S.border:SetBackdropBorderColor(border[1], border[2], border[3], 0.85)
        end
    end
    if S.badgeBg then
        S.badgeBg:SetColorTexture(accent[1], accent[2], accent[3], 1)
    end
    if S.tableFrame then
        S.tableFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
    end
    if S.title then
        S.title:SetTextColor(accent[1], accent[2], accent[3], 1)
    end
    if S.headerBg then
        S.headerBg:SetColorTexture(accentDark[1], accentDark[2], accentDark[3], 1)
    end
    if S.separator then
        S.separator:SetColorTexture(accent[1], accent[2], accent[3], 0.55)
    end
    if S.optionsFrame then
        S.optionsFrame:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
        if S.optionsFrame.title then
            S.optionsFrame.title:SetTextColor(accent[1], accent[2], accent[3], 1)
        end
        if S.optionsFrame.columnLabel then
            S.optionsFrame.columnLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
        end
        if S.optionsFrame.opacitySlider then
            if S.optionsFrame.opacitySlider.SetBackdropBorderColor then
                S.optionsFrame.opacitySlider:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.7)
            end
            local thumb = S.optionsFrame.opacitySlider:GetThumbTexture()
            if thumb then
                thumb:SetColorTexture(accent[1], accent[2], accent[3], 1)
            end
        end
    end
end

local function GetButtonVisibleForReadyState()
    local settings = GetSettings()
    if not settings.enabled then return false end
    if settings.hideUntilReady and CountReady() == 0 then return false end
    return true
end

local function ApplyButtonVisibility(isMouseOver)
    if not S.button then return end
    local settings = GetSettings()
    if GetButtonVisibleForReadyState() then
        S.button:Show()
        if isMouseOver then
            S.button:SetAlpha(1)
        elseif settings.hideUntilMouseover then
            S.button:SetAlpha(0)
        else
            S.button:SetAlpha(settings.opacity or 1.0)
        end
    else
        S.button:Hide()
        HideTable()
        if S.optionsFrame then S.optionsFrame:Hide() end
    end
end

-- ============================================================================
-- Table frame
-- ============================================================================
HideTable = function()
    if S.tableFrame then S.tableFrame:Hide() end
end

local function BuildTableFrame()
    if S.tableFrame then return end
    local tableW = GetTableWidth()

    local f = CreateFrame("Frame", "WarbandNexusVaultTable", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultTable")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        SaveTablePos(point, relativePoint, x, y)
    end)
    f:EnableMouse(true)
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    f:SetBackdropColor(0.06, 0.06, 0.09, 0.97)
    f:SetBackdropBorderColor(0.5, 0.4, 0.8, 0.9)
    f:Hide()

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, -6)
    title:SetTextColor(0.7, 0.5, 1.0, 1)
    title:SetText("Warband Nexus Vault Tracker")
    S.title = title

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", HideTable)

    local titleHitBox = CreateFrame("Button", nil, f)
    titleHitBox:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, 0)
    titleHitBox:SetPoint("TOPRIGHT", f, "TOPRIGHT", -28, 0)
    titleHitBox:SetHeight(28)
    titleHitBox:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    titleHitBox:EnableMouse(true)
    titleHitBox:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            f:StartMoving()
        end
    end)
    titleHitBox:SetScript("OnMouseUp", function(self, button)
        if button == "LeftButton" then
            f:StopMovingOrSizing()
            local point, _, relativePoint, x, y = f:GetPoint()
            SaveTablePos(point, relativePoint, x, y)
        elseif button == "RightButton" then
            ToggleOptionsFrame(f, "RIGHT")
        end
    end)
    S.titleHitBox = titleHitBox

    -- Header row
    local headerY = -(HEADER_H + 8)
    local hRow = CreateFrame("Frame", nil, f)
    hRow:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, headerY)
    hRow:SetSize(tableW - FRAME_PAD*2, HEADER_H)
    local hBg = hRow:CreateTexture(nil, "BACKGROUND")
    hBg:SetAllPoints()
    hBg:SetColorTexture(0.12, 0.10, 0.18, 1)
    S.headerBg = hBg

    -- Header cells
    local function HCell(text, x, w, isIcon, iconTex, tooltipTitle, tooltipText, tooltipKind, tooltipID)
        if isIcon and iconTex then
            local icon = hRow:CreateTexture(nil, "ARTWORK")
            icon:SetSize(16, 16)
            icon:SetPoint("CENTER", hRow, "LEFT", x + w/2, 0)
            icon:SetTexture(iconTex)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            if tooltipTitle then
                local hover = CreateFrame("Frame", nil, hRow)
                hover:SetPoint("TOPLEFT", hRow, "TOPLEFT", x, 0)
                hover:SetSize(w, HEADER_H)
                hover:EnableMouse(true)
                hover:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:ClearLines()
                    if tooltipKind == "item" and tooltipID then
                        if GameTooltip.SetItemByID then
                            GameTooltip:SetItemByID(tooltipID)
                        else
                            GameTooltip:SetHyperlink("item:" .. tooltipID)
                        end
                    elseif tooltipKind == "currency" and tooltipID and GameTooltip.SetCurrencyByID then
                        GameTooltip:SetCurrencyByID(tooltipID)
                    else
                        GameTooltip:AddLine(tooltipTitle, 1, 1, 1)
                        if tooltipText then
                            GameTooltip:AddLine(tooltipText, 0.75, 0.75, 0.75, true)
                        end
                    end
                    GameTooltip:Show()
                end)
                hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
            end
        else
            local fs = hRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetPoint("TOPLEFT", hRow, "TOPLEFT", x, 0)
            fs:SetSize(w, HEADER_H)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("MIDDLE")
            fs:SetTextColor(0.8, 0.8, 1.0)
            fs:SetText(text)
        end
    end

    local hx = 0
    HCell("Character",  hx, COL_NAME,    false)              ; hx = hx + COL_NAME
    HCell("iLvl",       hx, COL_ILVL,    false)              ; hx = hx + COL_ILVL
    for _, cat in ipairs(GetEnabledCategoryDefs()) do
        HCell(nil,      hx, cat.width,    true,  cat.icon, cat.label) ; hx = hx + cat.width
    end
    local columns = GetSettings().columns or {}
    if columns.bounty ~= false then
        HCell(nil,      hx, COL_BOUNTY,  true,  TRACK_ICONS.bounty, "Trovehunter's Bounty", nil, "item", BOUNTY_ITEM_ID) ; hx = hx + COL_BOUNTY
    end
    if columns.voidcore ~= false then
        HCell(nil,      hx, COL_VOIDCORE,true,  TRACK_ICONS.voidcore, "Nebulous Voidcore", nil, "currency", VOIDCORE_ID) ; hx = hx + COL_VOIDCORE
    end
    if columns.manaflux == true then
        HCell(nil,      hx, COL_MANAFLUX,true,  GetCurrencyIcon(MANAFLUX_ID, TRACK_ICONS.manaflux), "Dawnlight Manaflux", nil, "currency", MANAFLUX_ID) ; hx = hx + COL_MANAFLUX
    end
    HCell("Status",     hx, COL_STATUS,  false)

    -- Separator
    local sep = f:CreateTexture(nil, "BORDER")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  f, "TOPLEFT",  FRAME_PAD,  headerY - HEADER_H)
    sep:SetPoint("TOPRIGHT", f, "TOPRIGHT", -FRAME_PAD, headerY - HEADER_H)
    sep:SetColorTexture(0.4, 0.3, 0.6, 0.6)
    S.separator = sep

    -- Scroll
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     FRAME_PAD, headerY - HEADER_H - 2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -FRAME_PAD, FRAME_PAD)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetWidth(tableW - FRAME_PAD*2)
    scroll:SetScrollChild(content)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local cur = scroll:GetVerticalScroll()
        scroll:SetVerticalScroll(math.max(0, cur - delta * ROW_H * 2))
    end)

    S.tableFrame   = f
    S.tableScroll  = scroll
    S.tableContent = content
    ApplyTheme()
end

RefreshTable = function()
    BuildTableFrame()
    local tableW = GetTableWidth()
    local content = S.tableContent
    local list    = BuildCharList()

    for _, row in ipairs(S.rows) do row:Hide() end
    S.rows = {}

    if #list == 0 then
        S.tableFrame:SetSize(tableW, 120)
        content:SetSize(tableW - FRAME_PAD*2, 40)
        local msg = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("CENTER", content, "CENTER")
        msg:SetTextColor(0.5, 0.5, 0.5)
        msg:SetText("No vault activity this week.")
        S.tableFrame:Show()
        return
    end

    local catDefs = GetEnabledCategoryDefs()
    local columns = GetSettings().columns or {}
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}

    for i, e in ipairs(list) do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(tableW - FRAME_PAD*2, ROW_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i-1)*ROW_H)
        row:EnableMouse(true)

        -- Background
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if e.isCurrent then
            bg:SetColorTexture(accent[1] * 0.22, accent[2] * 0.22, accent[3] * 0.22, 1.0)
        elseif i % 2 == 0 then
            bg:SetColorTexture(0.08, 0.08, 0.11, 0.95)
        else
            bg:SetColorTexture(0.05, 0.05, 0.08, 0.95)
        end

        -- Hover highlight
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(accent[1], accent[2], accent[3], 0.25)

        -- Left stripe
        local stripe = row:CreateTexture(nil, "BORDER")
        stripe:SetWidth(3)
        stripe:SetPoint("TOPLEFT",    row, "TOPLEFT",    0, 0)
        stripe:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
        if e.isReady then
            stripe:SetColorTexture(0.2, 0.9, 0.3, 1)
        else
            stripe:SetColorTexture(accent[1], accent[2], accent[3], 1)
        end

        -- Row separator
        if i > 1 then
            local rowSep = row:CreateTexture(nil, "BORDER")
            rowSep:SetHeight(1)
            rowSep:SetPoint("TOPLEFT",  row, "TOPLEFT",  3, 0)
            rowSep:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
            rowSep:SetColorTexture(0.2, 0.18, 0.28, 0.5)
        end

        -- Name
        local x = 0
        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", x+6, 0)
        nameFS:SetSize(COL_NAME-6, ROW_H)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")
        nameFS:SetText(FormatCharacterName(e))
        x = x + COL_NAME

        -- iLvl
        local ilvlFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        ilvlFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        ilvlFS:SetSize(COL_ILVL, ROW_H)
        ilvlFS:SetJustifyH("CENTER")
        ilvlFS:SetJustifyV("MIDDLE")
        ilvlFS:SetText(e.itemLevel > 0
            and ("|cffd4af37" .. string.format("%.0f", e.itemLevel) .. "|r")
            or  DASH)
        x = x + COL_ILVL

        -- Vault columns
        local allSlots = {}
        for _, cat in ipairs(catDefs) do
            local slots = GetSlotData(e.charKey, cat.key)
            allSlots[cat.key] = slots
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            fs:SetSize(cat.width, ROW_H)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("MIDDLE")
            fs:SetText(SlotSymbols(slots, cat.key))
            x = x + cat.width
        end

        local b = e.bounty
        if columns.bounty ~= false then
            local bountyFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            bountyFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            bountyFS:SetSize(COL_BOUNTY, ROW_H)
            bountyFS:SetJustifyH("CENTER")
            bountyFS:SetJustifyV("MIDDLE")
            bountyFS:SetText(b == nil and DASH or (b and CHECK or CROSS))
            x = x + COL_BOUNTY
        end

        -- Nebulous Voidcore (current / seasonMax)
        local vc = e.voidcore
        if columns.voidcore ~= false then
            local voidcoreFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            voidcoreFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            voidcoreFS:SetSize(COL_VOIDCORE, ROW_H)
            voidcoreFS:SetJustifyH("CENTER")
            voidcoreFS:SetJustifyV("MIDDLE")
            if not vc then
                voidcoreFS:SetText(DASH)
            else
                local sm = vc.seasonMax or 0
                if sm > 0 then
                    local capColor = vc.isCapped and "|cffdd3333" or "|cffd4af37"
                    voidcoreFS:SetText(capColor .. vc.progress .. "|r|cffaaaaaa/|r|cffd4af37" .. sm .. "|r")
                else
                    voidcoreFS:SetText("|cffd4af37" .. vc.quantity .. "|r")
                end
            end
            x = x + COL_VOIDCORE
        end

        -- Dawnlight Manaflux
        if columns.manaflux == true then
            local manafluxFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            manafluxFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            manafluxFS:SetSize(COL_MANAFLUX, ROW_H)
            manafluxFS:SetJustifyH("CENTER")
            manafluxFS:SetJustifyV("MIDDLE")
            local mf = e.manaflux
            manafluxFS:SetText(mf and ("|cffd4af37" .. (mf.quantity or 0) .. "|r") or DASH)
            x = x + COL_MANAFLUX
        end

        -- Status
        local statusFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        statusFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
        statusFS:SetSize(COL_STATUS, ROW_H)
        statusFS:SetJustifyH("CENTER")
        statusFS:SetJustifyV("MIDDLE")
        statusFS:SetText(e.isReady and "|cff33dd33Ready|r" or "|cffffff00Pending|r")

        -- Row tooltip: iLvl per slot + bounty status
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            local ilvlLabel = e.itemLevel > 0
                and ("  |cffd4af37" .. string.format("%.0f", e.itemLevel) .. " iLvl|r") or ""
            GameTooltip:AddLine(FormatCharacterName(e) .. ilvlLabel)
            GameTooltip:AddLine(" ")
            for _, cat in ipairs(catDefs) do
                local slots = allSlots[cat.key]
                local parts = {}
                for si = 1, 3 do
                    local s = slots[si]
                    if s.complete then
                        parts[si] = s.ilvl > 0
                            and FormatRewardIlvl(s.ilvl, cat.key)
                            or  CHECK
                    else
                        parts[si] = CROSS
                    end
                end
                GameTooltip:AddDoubleLine(
                    "|cffaaaaaa" .. cat.label .. "|r",
                    table.concat(parts, "  "),
                    0.7, 0.7, 0.7, 1, 1, 1)
            end
            -- Bounty line
            if columns.bounty ~= false then
                local bountyLabel = b == nil and DASH
                    or (b and CHECK .. " |cff33dd33Collected|r" or "|cffdd3333Not collected|r")
                GameTooltip:AddDoubleLine("|T1064187:14:14:0:0|t |cffaaaaaaTrovehunter's Bounty|r", bountyLabel, 0.7,0.7,0.7, 1,1,1)
            end
            -- Voidcore line
            if columns.voidcore ~= false then
                local vc2 = e.voidcore
                if vc2 then
                    local sm = vc2.seasonMax or 0
                    local vcLabel
                    if sm > 0 then
                        vcLabel = (vc2.isCapped and "|cffdd3333" or "|cffd4af37")
                            .. vc2.progress .. "/" .. sm
                            .. (vc2.isCapped and " (Capped)|r" or "|r")
                            .. (vc2.quantity > 0 and ("|cffaaaaaa  (" .. vc2.quantity .. " held)|r") or "")
                    else
                        vcLabel = "|cffd4af37" .. vc2.quantity .. " held|r"
                    end
                    GameTooltip:AddDoubleLine("|T7658128:14:14:0:0|t |cffaaaaaaNebulous Voidcore|r", vcLabel, 0.7,0.7,0.7, 1,1,1)
                end
            end
            if columns.manaflux == true then
                local mf2 = e.manaflux
                if mf2 then
                    GameTooltip:AddDoubleLine("|T" .. GetCurrencyIcon(MANAFLUX_ID, TRACK_ICONS.manaflux) .. ":14:14:0:0|t |cffaaaaaaDawnlight Manaflux|r", "|cffd4af37" .. (mf2.quantity or 0) .. " held|r", 0.7,0.7,0.7, 1,1,1)
                end
            end
            GameTooltip:AddLine(" ")
            if e.isReady then
                GameTooltip:AddLine("|cff33dd33Vault ready.|r")
            else
                GameTooltip:AddLine("|cffffff00Available at weekly reset.|r")
            end
            GameTooltip:AddLine("|cff555555[Click] Open PvE tab|r")
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)

        -- Click row to open WN PvE tab
        row:SetScript("OnMouseDown", function(self, btn)
            if btn == "LeftButton" then
                HideTable()
                OpenWNPveTab()
            end
        end)

        table.insert(S.rows, row)
    end

    local visRows  = math.min(#list, MAX_ROWS)
    local contentH = #list * ROW_H
    local viewH    = visRows * ROW_H
    local totalH   = HEADER_H + 10 + viewH + FRAME_PAD + 32

    content:SetSize(tableW - FRAME_PAD*2, contentH)
    S.tableFrame:SetSize(tableW, totalH)
    S.tableScroll:SetVerticalScroll(0)
    S.tableFrame:Show()
end

local function ToggleTable()
    if S.tableFrame and S.tableFrame:IsShown() then
        HideTable()
    else
        RefreshTable()
        if S.tableFrame and S.button then
            S.tableFrame:ClearAllPoints()
            local saved = GetSavedTablePos()
            if saved and saved.x and saved.y then
                S.tableFrame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x, saved.y)
            else
                local bY = S.button:GetTop() or 0
                if bY > GetScreenHeight() / 2 then
                    S.tableFrame:SetPoint("BOTTOMLEFT", S.button, "TOPLEFT", 0, 4)
                else
                    S.tableFrame:SetPoint("TOPLEFT", S.button, "BOTTOMLEFT", 0, -4)
                end
            end
        end
    end
end

-- ============================================================================
-- Badge
-- ============================================================================
UpdateBadge = function()
    if not S.badge then return end
    local count = CountReady()
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}
    local border = colors.border or accent
    if count > 0 then
        S.badge:SetText(count)
        S.badgeBg:Show()
        S.badge:Show()
        if S.badgeBg then S.badgeBg:SetColorTexture(accent[1], accent[2], accent[3], 1.0) end
        if S.border then S.border:SetBackdropBorderColor(accent[1], accent[2], accent[3], 1.0) end
    else
        S.badge:Hide()
        S.badgeBg:Hide()
        if S.border then S.border:SetBackdropBorderColor(border[1], border[2], border[3], 0.85) end
    end
    ApplyButtonVisibility(false)
    if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
end

-- ============================================================================
-- Hover tooltip (simple list)
-- ============================================================================
local function ShowHoverTooltip(anchor)
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}
    GameTooltip:SetOwner(anchor, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine("Warband Nexus Vault Tracker", accent[1], accent[2], accent[3])
    local list = BuildCharList()
    local readyN, pendingN = 0, 0
    for _, e in ipairs(list) do
        if e.isReady then readyN = readyN + 1 else pendingN = pendingN + 1 end
    end
    if #list == 0 then
        GameTooltip:AddLine("No vault activity this week.", 0.5, 0.5, 0.5)
    else
        GameTooltip:AddLine(" ")
        for _, e in ipairs(list) do
            local status = e.isReady
                and "|cff33dd33[Ready]|r"
                or  "|cffffff00[Pending]|r"
            local slotStr = e.slots > 0
                and (" |cffaaaaaa("..e.slots.." slot"..(e.slots==1 and "" or "s")..")|r")
                or ""
            GameTooltip:AddDoubleLine(
                FormatCharacterName(e),
                status..slotStr,
                1,1,1, 1,1,1)
        end
        GameTooltip:AddLine(" ")
        if readyN   > 0 then GameTooltip:AddLine(readyN   .." ready to claim",            0.2, 1.0, 0.3) end
        if pendingN > 0 then GameTooltip:AddLine(pendingN .." in progress (next reset)",  1.0, 1.0, 0.2) end
    end
    GameTooltip:AddLine("|cff555555[Left-click] Full view  [Right-click] Settings  [Drag] Move|r")
    GameTooltip:Show()
end

-- ============================================================================
-- Main button
-- ============================================================================
local function CreateMenuCheckbox(parent, labelText, y, getValue, setValue)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, y)
    cb:SetChecked(getValue())

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    label:SetText(labelText)
    label:SetTextColor(1, 1, 1, 1)

    cb:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        setValue(checked)
        RefreshButtonSettings()
    end)

    cb.RefreshValue = function(self)
        self:SetChecked(getValue())
    end
    table.insert(S.optionsWidgets, cb)
    return cb
end

local function BuildOptionsFrame()
    if S.optionsFrame then return end

    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}

    local f = CreateFrame("Frame", "WarbandNexusVaultButtonOptions", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultButtonOptions")
    f:SetSize(286, 424)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(210)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 4, right = 4, top = 4, bottom = 4},
    })
    f:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    f:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.9)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -10)
    title:SetText("Vault Button")
    title:SetTextColor(accent[1], accent[2], accent[3], 1)
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() f:Hide() end)

    CreateMenuCheckbox(f, "Enable Button", -36,
        function() return GetSettings().enabled ~= false end,
        function(value) GetSettings().enabled = value end)
    CreateMenuCheckbox(f, "Hide Until Mouseover", -62,
        function() return GetSettings().hideUntilMouseover == true end,
        function(value) GetSettings().hideUntilMouseover = value end)
    CreateMenuCheckbox(f, "Hide Until Ready", -88,
        function() return GetSettings().hideUntilReady == true end,
        function(value) GetSettings().hideUntilReady = value end)
    CreateMenuCheckbox(f, "Show Realm Names", -114,
        function() return GetSettings().showRealmName == true end,
        function(value)
            GetSettings().showRealmName = value
            if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
        end)
    CreateMenuCheckbox(f, "Show Reward iLvl", -140,
        function() return GetSettings().showRewardItemLevel == true end,
        function(value)
            GetSettings().showRewardItemLevel = value
            RebuildTableFrame()
        end)
    local columnLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    columnLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -172)
    columnLabel:SetText("Columns")
    columnLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
    f.columnLabel = columnLabel

    CreateMenuCheckbox(f, "Raid", -192,
        function() return GetSettings().columns.raids ~= false end,
        function(value)
            GetSettings().columns.raids = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dungeon", -218,
        function() return GetSettings().columns.mythicPlus ~= false end,
        function(value)
            GetSettings().columns.mythicPlus = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "World", -244,
        function() return GetSettings().columns.world ~= false end,
        function(value)
            GetSettings().columns.world = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Trovehunter's Bounty", -270,
        function() return GetSettings().columns.bounty ~= false end,
        function(value)
            GetSettings().columns.bounty = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Nebulous Voidcore", -296,
        function() return GetSettings().columns.voidcore ~= false end,
        function(value)
            GetSettings().columns.voidcore = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dawnlight Manaflux", -322,
        function() return GetSettings().columns.manaflux == true end,
        function(value)
            GetSettings().columns.manaflux = value
            GetSettings().showManaflux = value
            RebuildTableFrame()
        end)

    local opacityLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    opacityLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -356)
    opacityLabel:SetTextColor(1, 1, 1, 1)

    local slider = CreateFrame("Slider", nil, f, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -380)
    slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -380)
    slider:SetHeight(16)
    slider:SetOrientation("HORIZONTAL")
    slider:SetMinMaxValues(0.2, 1.0)
    slider:SetValueStep(0.05)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = {left = 0, right = 0, top = 0, bottom = 0},
    })
    slider:SetBackdropColor(0.10, 0.10, 0.12, 1)
    slider:SetBackdropBorderColor(accent[1], accent[2], accent[3], 0.7)

    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(12, 18)
    thumb:SetColorTexture(accent[1], accent[2], accent[3], 1)
    slider:SetThumbTexture(thumb)
    f.opacitySlider = slider

    local function UpdateOpacityLabel(value)
        opacityLabel:SetText(string.format("Opacity: %d%%", math.floor((value or GetSettings().opacity or 1) * 100 + 0.5)))
    end
    slider:SetValue(GetSettings().opacity or 1.0)
    UpdateOpacityLabel(slider:GetValue())
    slider:SetScript("OnValueChanged", function(_, value)
        if S.refreshingOptions then return end
        value = math.floor(value * 20 + 0.5) / 20
        GetSettings().opacity = value
        UpdateOpacityLabel(value)
        RefreshButtonSettings()
    end)
    f.RefreshValues = function()
        S.refreshingOptions = true
        for _, widget in ipairs(S.optionsWidgets) do
            if widget and widget.RefreshValue then
                widget:RefreshValue()
            end
        end
        slider:SetValue(GetSettings().opacity or 1.0)
        UpdateOpacityLabel(slider:GetValue())
        S.refreshingOptions = false
    end

    S.optionsFrame = f
end

ToggleOptionsFrame = function(anchor, placement)
    BuildOptionsFrame()
    if not S.optionsFrame then return end
    if S.optionsFrame:IsShown() then
        S.optionsFrame:Hide()
        return
    end
    S.optionsFrame:ClearAllPoints()
    anchor = anchor or S.button
    if anchor and placement == "RIGHT" then
        S.optionsFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 6, 0)
    elseif anchor then
        S.optionsFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
    else
        S.optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
    S.optionsFrame:Show()
    ApplyTheme()
end

RefreshButtonSettings = function()
    local tableWasShown = S.tableFrame and S.tableFrame:IsShown()
    if S.optionsFrame then
        if S.optionsFrame.RefreshValues then
            S.optionsFrame:RefreshValues()
        end
    end
    ApplyTheme()
    ApplyButtonVisibility(false)
    if tableWasShown and S.button and S.button:IsShown() then
        RefreshTable()
    end
end

local function BuildButton()
    if S.button then return end

    local btn = CreateFrame("Button", "WarbandNexusVaultButton", UIParent, "BackdropTemplate")
    btn:SetSize(BUTTON_SIZE, BUTTON_SIZE)
    btn:SetClampedToScreen(true)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(50)
    btn:SetMovable(true)
    btn:EnableMouse(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeSize = 0,
        insets   = {left=0,right=0,top=0,bottom=0},
    })
    btn:SetBackdropColor(0.06, 0.06, 0.08, 0.92)
    btn:SetBackdropBorderColor(0, 0, 0, 0)

    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetAllPoints(btn)
    border:SetFrameLevel(btn:GetFrameLevel() + 2)
    border:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true, tileSize=16, edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4},
    })
    border:SetBackdropBorderColor(0.5, 0.5, 0.6, 0.8)
    border:EnableMouse(false)
    S.border = border

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     6, -6)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -6, 6)
    icon:SetTexture(ICON_TEXTURE)
    -- Fallback if custom icon didn't load
    if not icon:GetTexture() then
        icon:SetTexture(ICON_FALLBACK)
    end
    S.icon = icon

    local badgeBg = btn:CreateTexture(nil, "OVERLAY")
    badgeBg:SetSize(BADGE_SIZE, BADGE_SIZE)
    badgeBg:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 4)
    badgeBg:SetColorTexture(0.15, 0.75, 0.25, 1.0)
    badgeBg:Hide()
    S.badgeBg = badgeBg

    local badge = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badge:SetSize(BADGE_SIZE, BADGE_SIZE)
    badge:SetPoint("CENTER", badgeBg, "CENTER", 0, 0)
    badge:SetJustifyH("CENTER")
    badge:SetJustifyV("MIDDLE")
    badge:SetTextColor(1, 1, 1, 1)
    badge:Hide()
    S.badge = badge

    local dragged = false

    btn:SetScript("OnEnter", function(self)
        ApplyButtonVisibility(true)
        ShowHoverTooltip(self)
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
        ApplyButtonVisibility(false)
    end)

    btn:SetScript("OnDragStart", function(self)
        dragged = true
        HideTable()
        self:StartMoving()
    end)
    btn:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relativePoint, x, y = self:GetPoint()
        SavePos(point, relativePoint, x, y)
        C_Timer.After(0.05, function() dragged = false end)
    end)
    btn:SetScript("OnClick", function(self, mouseButton)
        if dragged then return end
        GameTooltip:Hide()
        if mouseButton == "RightButton" then
            ToggleOptionsFrame()
        else
            ToggleTable()
        end
    end)

    local pos = GetSavedPos()
    btn:ClearAllPoints()
    if pos and pos.x and pos.y then
        btn:SetPoint(pos.point or "CENTER", UIParent, pos.relativePoint or "CENTER", pos.x, pos.y)
    else
        btn:SetPoint("CENTER", UIParent, "CENTER", 600, 0)
    end

    S.button = btn
    ApplyTheme()
    ApplyButtonVisibility(false)
    UpdateBadge()
end

-- ============================================================================
-- Events
-- ============================================================================
local eFrame = CreateFrame("Frame")
eFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eFrame:SetScript("OnEvent", function()
    C_Timer.After(2, function() BuildButton(); UpdateBadge() end)
end)

local function HookWNMessages()
    if not WarbandNexus or not WarbandNexus.RegisterMessage then return end
    local E = ns.Constants and ns.Constants.EVENTS
    if not E then return end
    if E.PVE_UPDATED then
        WarbandNexus:RegisterMessage(E.PVE_UPDATED, function() UpdateBadge() end)
    end
    if E.CHARACTER_UPDATED then
        WarbandNexus:RegisterMessage(E.CHARACTER_UPDATED, function() UpdateBadge() end)
    end
end

function WarbandNexus:RefreshVaultButtonSettings()
    if not S.button then
        BuildButton()
    end
    RebuildTableFrame()
    RefreshButtonSettings()
    UpdateBadge()
end

function WarbandNexus:SetVaultButtonEnabled(enabled)
    GetSettings().enabled = enabled and true or false
    self:RefreshVaultButtonSettings()
end

local function HookThemeRefresh()
    if ns._vaultButtonThemeRefreshHooked or not ns.UI_RefreshColors then return end
    ns._vaultButtonThemeRefreshHooked = true
    local originalRefreshColors = ns.UI_RefreshColors
    ns.UI_RefreshColors = function(...)
        originalRefreshColors(...)
        ApplyTheme()
        RefreshButtonSettings()
    end
end

local hFrame = CreateFrame("Frame")
hFrame:RegisterEvent("ADDON_LOADED")
hFrame:SetScript("OnEvent", function(self, event, addonName)
    if addonName == "WarbandNexus" then
        HookThemeRefresh()
        C_Timer.After(1, HookWNMessages)
        self:UnregisterEvent("ADDON_LOADED")
    end
end)
