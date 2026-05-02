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
local CHROME_H      = 40
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
local COL_STATUS    = 110

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
local UPARROW = "|A:loottoast-arrow-green:12:12|a"
local DASH   = "|cff666666-|r"

-- Maps Vault Button column key -> PvE typeName used by upgrade-detection logic
local CAT_TO_TYPE = { raids = "Raid", mythicPlus = "M+", world = "World" }

local function IsSlotAtMax(activity, typeName)
    if not activity or not activity.level then return false end
    local level = activity.level
    if typeName == "Raid" then
        return level == 16
    elseif typeName == "M+" then
        return level >= 10
    elseif typeName == "World" then
        return level >= 8
    end
    return false
end

local function SlotShowsUpgrade(act, typeName)
    if not act then return false end
    local ni = tonumber(act.nextLevelIlvl) or 0
    if ni > 0 then return true end
    local th = tonumber(act.threshold) or 0
    local prog = tonumber(act.progress) or 0
    if th <= 0 or prog < th then return false end
    if IsSlotAtMax(act, typeName) then return false end
    return true
end

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
    local typeName = CAT_TO_TYPE[category]
    local slots = {}
    for i = 1, 3 do
        local a = cat[i]
        local prog   = a and (tonumber(a.progress) or 0) or 0
        local thresh = a and (tonumber(a.threshold) or 0) or 0
        slots[i] = {
            complete   = thresh > 0 and prog >= thresh,
            ilvl       = a and a.rewardItemLevel or 0,
            progress   = prog,
            threshold  = thresh,
            canUpgrade = SlotShowsUpgrade(a, typeName),
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

--- Open WarbandNexus main window on a specific tab (or no tab change)
local function OpenWNTab(tabKey)
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    if not WarbandNexus or not WarbandNexus.ShowMainWindow then return end
    WarbandNexus:ShowMainWindow()
    if not tabKey then return end
    C_Timer.After(0.05, function()
        local mf = WarbandNexus.mainFrame
        if mf and mf.tabButtons and mf.tabButtons[tabKey] and mf.tabButtons[tabKey].Click then
            mf.tabButtons[tabKey]:Click()
        end
    end)
end

local function OpenWNPveTab() OpenWNTab("pve") end

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
            if settings.showRewardItemLevel then
                parts[i] = FormatRewardIlvl(slot.ilvl, category)
            elseif slot.canUpgrade then
                parts[i] = UPARROW
            else
                parts[i] = CHECK
            end
        else
            parts[i] = CROSS
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
    optionsFrame=nil, optionsWidgets={}, rows={},
    menuFrame=nil, savedFrame=nil, savedRows={}
}

local HideTable
local RefreshTable
local RefreshButtonSettings
local UpdateBadge
local ToggleOptionsFrame
local ToggleMenu
local HideMenu
local ToggleSavedInstances
local HideSavedInstances
local RefreshSavedInstances

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
    -- tableFrame / chrome / optionsFrame border colors auto-update via ns.BORDER_REGISTRY
    if S.separator then
        S.separator:SetColorTexture(accent[1], accent[2], accent[3], 0.55)
    end
    if S.optionsFrame then
        if S.optionsFrame.columnLabel then
            S.optionsFrame.columnLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
        end
        if S.optionsFrame.opacitySlider then
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
    if S.optionsFrame then S.optionsFrame:Hide() end
end

HideMenu = function() if S.menuFrame then S.menuFrame:Hide() end end
HideSavedInstances = function() if S.savedFrame then S.savedFrame:Hide() end end

local function HideAllPanels()
    HideTable()
    HideMenu()
    HideSavedInstances()
end

local function BuildTableFrame()
    if S.tableFrame then return end
    local tableW = GetTableWidth()
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}

    local f = CreateFrame("Frame", "WarbandNexusVaultTable", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultTable")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        f:SetBackdropColor(0.02, 0.02, 0.03, 0.98)
    end
    f:Hide()

    -- ===== CHROME HEADER (matches main window) =====
    local chrome = CreateFrame("Frame", nil, f)
    chrome:SetHeight(CHROME_H)
    chrome:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    chrome:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    chrome:EnableMouse(true)
    chrome:RegisterForDrag("LeftButton")
    chrome:SetScript("OnDragStart", function() f:StartMoving() end)
    chrome:SetScript("OnDragStop", function()
        f:StopMovingOrSizing()
        local point, _, relativePoint, x, y = f:GetPoint()
        SaveTablePos(point, relativePoint, x, y)
    end)
    if ApplyVisuals then
        ApplyVisuals(chrome, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end
    S.headerBg = chrome  -- repurposed for theme refresh

    local titleIcon = chrome:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(24, 24)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture(ICON_TEXTURE)
    if not titleIcon:GetTexture() then titleIcon:SetTexture(ICON_FALLBACK) end

    local FontManager = ns.FontManager
    local title
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        title = FontManager:CreateFontString(chrome, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText("Vault Tracker")
    title:SetTextColor(1, 1, 1)
    S.title = title

    -- Close button (atlas style, matches main window)
    local closeBtn = CreateFrame("Button", nil, chrome)
    closeBtn:SetSize(28, 28)
    closeBtn:SetPoint("RIGHT", -8, 0)
    if ApplyVisuals then
        ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {accent[1], accent[2], accent[3], 0.8})
    end
    local closeIcon = closeBtn:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    closeBtn:SetScript("OnClick", HideTable)
    closeBtn:SetScript("OnEnter", function()
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ApplyVisuals then ApplyVisuals(closeBtn, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1}) end
    end)
    closeBtn:SetScript("OnLeave", function()
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ApplyVisuals then ApplyVisuals(closeBtn, {0.15, 0.15, 0.15, 0.9}, {accent[1], accent[2], accent[3], 0.8}) end
    end)

    -- Settings (gear) button — opens options frame
    local settingsBtn = CreateFrame("Button", nil, chrome)
    settingsBtn:SetSize(28, 28)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    settingsBtn:SetNormalAtlas("mechagon-projects")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() ToggleOptionsFrame(f, "RIGHT") end)

    -- Column header row
    local headerY = -(CHROME_H + 6)
    local hRow = CreateFrame("Frame", nil, f)
    hRow:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, headerY)
    hRow:SetSize(tableW - FRAME_PAD*2, HEADER_H)
    if ApplyVisuals then
        ApplyVisuals(hRow, {0.08, 0.08, 0.10, 1}, {COLORS.border and COLORS.border[1] or 0.20, COLORS.border and COLORS.border[2] or 0.20, COLORS.border and COLORS.border[3] or 0.25, 0.6})
    else
        local hBg = hRow:CreateTexture(nil, "BACKGROUND")
        hBg:SetAllPoints()
        hBg:SetColorTexture(0.08, 0.08, 0.10, 1)
    end

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
        S.tableFrame:SetSize(tableW, CHROME_H + HEADER_H + 80)
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
        local readyLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"
        local pendingLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_PENDING"]) or "Pending..."
        statusFS:SetText(e.isReady and ("|cff44ff44" .. readyLabel .. "|r") or ("|cffffd700" .. pendingLabel .. "|r"))

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
                        if s.ilvl > 0 then
                            parts[si] = FormatRewardIlvl(s.ilvl, cat.key)
                        elseif s.canUpgrade then
                            parts[si] = UPARROW
                        else
                            parts[si] = CHECK
                        end
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
            local readyMsg = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"
            local pendingMsg = (ns.L and ns.L["VAULT_TRACKER_STATUS_PENDING"]) or "Pending..."
            if e.isReady then
                GameTooltip:AddLine("|cff44ff44" .. readyMsg .. "|r")
            else
                GameTooltip:AddLine("|cffffd700" .. pendingMsg .. "|r")
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
    local totalH   = CHROME_H + 6 + HEADER_H + 2 + viewH + FRAME_PAD

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
    GameTooltip:AddLine("Warband Nexus", accent[1], accent[2], accent[3])

    local readyLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"
    local pendingLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_PENDING"]) or "Pending..."

    local charKey = GetCurrentCharKey()
    local chars = GetCharacters()
    local entry = chars and charKey and chars[charKey]

    if not entry then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("No vault data for current character yet.", 0.6, 0.6, 0.6)
    else
        local pveCache = GetPveCache()
        local rewards = pveCache and pveCache.greatVault and pveCache.greatVault.rewards
        local rewardData = rewards and rewards[charKey]
        local isReady = (rewardData and rewardData.hasAvailableRewards) or false

        local nameLine = "|cff" .. GetClassHex(entry.classFile) .. (entry.name or charKey) .. "|r"
        if entry.itemLevel and entry.itemLevel > 0 then
            nameLine = nameLine .. "  |cffd4af37" .. string.format("%.0f", entry.itemLevel) .. " iLvl|r"
        end
        GameTooltip:AddLine(nameLine)
        GameTooltip:AddLine(" ")

        local catLabels = { raids = "Raid", mythicPlus = "Dungeon", world = "World" }
        for _, key in ipairs({ "raids", "mythicPlus", "world" }) do
            local slots = GetSlotData(charKey, key)
            local parts = {}
            for i = 1, 3 do
                local s = slots[i]
                if s.complete then
                    if s.canUpgrade then parts[i] = UPARROW
                    else parts[i] = CHECK end
                else
                    parts[i] = CROSS
                end
            end
            GameTooltip:AddDoubleLine(
                "|cffaaaaaa" .. catLabels[key] .. "|r",
                table.concat(parts, "  "),
                0.7, 0.7, 0.7, 1, 1, 1)
        end

        local bounty = GetBountyStatus(charKey)
        if bounty ~= nil then
            local bountyLabel = bounty and (CHECK .. " |cff33dd33Collected|r") or "|cffdd3333Not collected|r"
            GameTooltip:AddDoubleLine("|T1064187:14:14:0:0|t |cffaaaaaaTrovehunter's Bounty|r", bountyLabel, 0.7,0.7,0.7, 1,1,1)
        end

        local vc = GetVoidcoreData(charKey)
        if vc then
            local sm = vc.seasonMax or 0
            local vcLabel
            if sm > 0 then
                vcLabel = (vc.isCapped and "|cffdd3333" or "|cffd4af37")
                    .. vc.progress .. "/" .. sm
                    .. (vc.isCapped and " (Capped)|r" or "|r")
                    .. (vc.quantity > 0 and ("|cffaaaaaa  (" .. vc.quantity .. " held)|r") or "")
            else
                vcLabel = "|cffd4af37" .. vc.quantity .. " held|r"
            end
            GameTooltip:AddDoubleLine("|T7658128:14:14:0:0|t |cffaaaaaaNebulous Voidcore|r", vcLabel, 0.7,0.7,0.7, 1,1,1)
        end

        if GetSettings().showManaflux then
            local mf = GetManafluxData(charKey)
            if mf then
                GameTooltip:AddDoubleLine(
                    "|T" .. GetCurrencyIcon(MANAFLUX_ID, TRACK_ICONS.manaflux) .. ":14:14:0:0|t |cffaaaaaaDawnlight Manaflux|r",
                    "|cffd4af37" .. (mf.quantity or 0) .. " held|r",
                    0.7,0.7,0.7, 1,1,1)
            end
        end

        GameTooltip:AddLine(" ")
        if isReady then
            GameTooltip:AddLine("|cff44ff44" .. readyLabel .. "|r")
        else
            GameTooltip:AddLine("|cffffd700" .. pendingLabel .. "|r")
        end
    end

    GameTooltip:AddLine("|cff555555[Left-click] Menu  [Drag] Move|r")
    GameTooltip:Show()
end

-- ============================================================================
-- Main button
-- ============================================================================
local function CreateMenuCheckbox(parent, labelText, y, getValue, setValue)
    local cb
    if ns.UI_CreateThemedCheckbox then
        cb = ns.UI_CreateThemedCheckbox(parent, getValue() == true)
    else
        cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
        cb:SetSize(22, 22)
        cb:SetChecked(getValue())
    end
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)

    local FontManager = ns.FontManager
    local label
    if FontManager and FontManager.CreateFontString then
        label = FontManager:CreateFontString(parent, "body", "OVERLAY")
    else
        label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    label:SetPoint("LEFT", cb, "RIGHT", (ns.UI_SPACING and ns.UI_SPACING.AFTER_ELEMENT) or 6, 0)
    label:SetText(labelText)
    label:SetTextColor(1, 1, 1, 1)
    label:SetJustifyH("LEFT")

    -- ThemedCheckbox already has OnClick that toggles innerDot; chain our handler
    local prevOnClick = cb:GetScript("OnClick")
    cb:SetScript("OnClick", function(self, ...)
        if prevOnClick then prevOnClick(self, ...) end
        setValue(self:GetChecked() and true or false)
        RefreshButtonSettings()
    end)

    cb.RefreshValue = function(self)
        local v = getValue() == true
        self:SetChecked(v)
        if self.innerDot then self.innerDot:SetShown(v) end
    end
    table.insert(S.optionsWidgets, cb)
    return cb
end

local function BuildOptionsFrame()
    if S.optionsFrame then return end

    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}

    local f = CreateFrame("Frame", "WarbandNexusVaultButtonOptions", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultButtonOptions")
    f:SetSize(286, 460)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(210)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    if ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        f:SetBackdropColor(0.02, 0.02, 0.03, 0.98)
    end
    f:Hide()

    -- Chrome header
    local chrome = CreateFrame("Frame", nil, f)
    chrome:SetHeight(CHROME_H)
    chrome:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    chrome:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    chrome:EnableMouse(true)
    chrome:RegisterForDrag("LeftButton")
    chrome:SetScript("OnDragStart", function() f:StartMoving() end)
    chrome:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    if ApplyVisuals then
        ApplyVisuals(chrome, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end

    local titleIcon = chrome:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(24, 24)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture(ICON_TEXTURE)
    if not titleIcon:GetTexture() then titleIcon:SetTexture(ICON_FALLBACK) end

    local FontManager = ns.FontManager
    local title
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        title = FontManager:CreateFontString(chrome, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText("Vault Button")
    title:SetTextColor(1, 1, 1)
    f.title = title

    local close = CreateFrame("Button", nil, chrome)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -8, 0)
    if ApplyVisuals then
        ApplyVisuals(close, {0.15, 0.15, 0.15, 0.9}, {accent[1], accent[2], accent[3], 0.8})
    end
    local closeIcon = close:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function()
        closeIcon:SetVertexColor(1, 0.2, 0.2)
        if ApplyVisuals then ApplyVisuals(close, {0.3, 0.1, 0.1, 0.9}, {1, 0.1, 0.1, 1}) end
    end)
    close:SetScript("OnLeave", function()
        closeIcon:SetVertexColor(0.9, 0.3, 0.3)
        if ApplyVisuals then ApplyVisuals(close, {0.15, 0.15, 0.15, 0.9}, {accent[1], accent[2], accent[3], 0.8}) end
    end)

    CreateMenuCheckbox(f, "Enable Button", -52,
        function() return GetSettings().enabled ~= false end,
        function(value) GetSettings().enabled = value end)
    CreateMenuCheckbox(f, "Hide Until Mouseover", -78,
        function() return GetSettings().hideUntilMouseover == true end,
        function(value) GetSettings().hideUntilMouseover = value end)
    CreateMenuCheckbox(f, "Hide Until Ready", -104,
        function() return GetSettings().hideUntilReady == true end,
        function(value) GetSettings().hideUntilReady = value end)
    CreateMenuCheckbox(f, "Show Realm Names", -130,
        function() return GetSettings().showRealmName == true end,
        function(value)
            GetSettings().showRealmName = value
            if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
        end)
    CreateMenuCheckbox(f, "Show Reward iLvl", -156,
        function() return GetSettings().showRewardItemLevel == true end,
        function(value)
            GetSettings().showRewardItemLevel = value
            RebuildTableFrame()
        end)
    local columnLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    columnLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -188)
    columnLabel:SetText("Columns")
    columnLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
    f.columnLabel = columnLabel

    CreateMenuCheckbox(f, "Raid", -208,
        function() return GetSettings().columns.raids ~= false end,
        function(value)
            GetSettings().columns.raids = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dungeon", -234,
        function() return GetSettings().columns.mythicPlus ~= false end,
        function(value)
            GetSettings().columns.mythicPlus = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "World", -260,
        function() return GetSettings().columns.world ~= false end,
        function(value)
            GetSettings().columns.world = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Trovehunter's Bounty", -286,
        function() return GetSettings().columns.bounty ~= false end,
        function(value)
            GetSettings().columns.bounty = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Nebulous Voidcore", -312,
        function() return GetSettings().columns.voidcore ~= false end,
        function(value)
            GetSettings().columns.voidcore = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dawnlight Manaflux", -338,
        function() return GetSettings().columns.manaflux == true end,
        function(value)
            GetSettings().columns.manaflux = value
            GetSettings().showManaflux = value
            RebuildTableFrame()
        end)

    local opacityLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    opacityLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -380)
    opacityLabel:SetTextColor(1, 1, 1, 1)

    local slider = CreateFrame("Slider", nil, f, "BackdropTemplate")
    slider:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -410)
    slider:SetPoint("TOPRIGHT", f, "TOPRIGHT", -18, -410)
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

-- ============================================================================
-- Saved Instances (Raid Info)
-- ============================================================================
local DIFFICULTY_ORDER = { LFR=1, Raid=2, Normal=3, Heroic=4, Mythic=5 }
local DIFF_COLOR = {
    [14] = "|cff1eff00",  -- Normal (green)
    [15] = "|cff0070dd",  -- Heroic (blue)
    [16] = "|cffa335ee",  -- Mythic (purple)
    [17] = "|cffaaaaaa",  -- LFR (grey)
}

local function GetClassHexFromCharacters(charKey)
    local chars = GetCharacters()
    local entry = chars and chars[charKey]
    return GetClassHex(entry and entry.classFile), entry and entry.name or charKey
end

local function BuildSavedInstancesData()
    local pveCache = GetPveCache()
    local lockouts = pveCache and pveCache.lockouts and pveCache.lockouts.raids
    if not lockouts then return {} end

    -- Group by (instanceName + difficultyName) -> list of {charKey, killed, total}
    local groups = {}
    for charKey, instances in pairs(lockouts) do
        if type(instances) == "table" then
            for _, inst in pairs(instances) do
                if inst and inst.name then
                    local diffName = inst.difficultyName or "Unknown"
                    local key = inst.name .. "||" .. diffName
                    local g = groups[key]
                    if not g then
                        g = {
                            instanceName = inst.name,
                            difficultyName = diffName,
                            difficulty = inst.difficulty,
                            characters = {},
                        }
                        groups[key] = g
                    end
                    local total = tonumber(inst.numEncounters) or (inst.encounters and #inst.encounters) or 0
                    local killed = tonumber(inst.encounterProgress) or 0
                    if killed == 0 and inst.encounters then
                        for _, e in ipairs(inst.encounters) do
                            if e.killed then killed = killed + 1 end
                        end
                    end
                    table.insert(g.characters, {
                        charKey = charKey,
                        killed = killed,
                        total = total,
                        reset = inst.reset,
                        encounters = inst.encounters,
                    })
                end
            end
        end
    end

    local list = {}
    for _, g in pairs(groups) do
        table.sort(g.characters, function(a, b) return (a.charKey or "") < (b.charKey or "") end)
        table.insert(list, g)
    end
    table.sort(list, function(a, b)
        if a.instanceName ~= b.instanceName then return a.instanceName < b.instanceName end
        return (a.difficulty or 0) > (b.difficulty or 0)
    end)
    return list
end

local function BuildSavedInstancesFrame()
    if S.savedFrame then return end
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}

    local f = CreateFrame("Frame", "WarbandNexusSavedInstances", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusSavedInstances")
    f:SetSize(540, 420)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    end
    f:Hide()

    local chrome = CreateFrame("Frame", nil, f)
    chrome:SetHeight(CHROME_H)
    chrome:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    chrome:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    chrome:EnableMouse(true)
    chrome:RegisterForDrag("LeftButton")
    chrome:SetScript("OnDragStart", function() f:StartMoving() end)
    chrome:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)
    if ApplyVisuals then
        ApplyVisuals(chrome, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end

    local titleIcon = chrome:CreateTexture(nil, "ARTWORK")
    titleIcon:SetSize(24, 24)
    titleIcon:SetPoint("LEFT", 15, 0)
    titleIcon:SetTexture("Interface\\Icons\\INV_Misc_Bell_01")

    local FontManager = ns.FontManager
    local title
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        title = FontManager:CreateFontString(chrome, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText("Saved Instances")
    title:SetTextColor(1, 1, 1)

    local close = CreateFrame("Button", nil, chrome)
    close:SetSize(28, 28)
    close:SetPoint("RIGHT", -8, 0)
    if ApplyVisuals then
        ApplyVisuals(close, {0.15, 0.15, 0.15, 0.9}, {accent[1], accent[2], accent[3], 0.8})
    end
    local closeIcon = close:CreateTexture(nil, "ARTWORK")
    closeIcon:SetSize(16, 16)
    closeIcon:SetPoint("CENTER")
    closeIcon:SetAtlas("uitools-icon-close")
    closeIcon:SetVertexColor(0.9, 0.3, 0.3)
    close:SetScript("OnClick", function() f:Hide() end)
    close:SetScript("OnEnter", function() closeIcon:SetVertexColor(1, 0.2, 0.2) end)
    close:SetScript("OnLeave", function() closeIcon:SetVertexColor(0.9, 0.3, 0.3) end)

    -- Scroll body
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, -(CHROME_H + 6))
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -FRAME_PAD, FRAME_PAD)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(540 - FRAME_PAD * 2, 1)
    scroll:SetScrollChild(content)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local cur = scroll:GetVerticalScroll()
        scroll:SetVerticalScroll(math.max(0, cur - delta * 40))
    end)

    S.savedFrame = f
    S.savedScroll = scroll
    S.savedContent = content
end

RefreshSavedInstances = function()
    BuildSavedInstancesFrame()
    local content = S.savedContent
    if not content then return end

    for _, row in ipairs(S.savedRows) do row:Hide() end
    S.savedRows = {}

    local list = BuildSavedInstancesData()
    if #list == 0 then
        local msg = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("CENTER", content, "CENTER")
        msg:SetTextColor(0.6, 0.6, 0.6)
        msg:SetText("No raid lockouts recorded yet.\nLogin a character with active lockouts to populate.")
        msg:SetJustifyH("CENTER")
        content:SetHeight(80)
        S.savedFrame:Show()
        table.insert(S.savedRows, msg)
        return
    end

    local FontManager = ns.FontManager
    local rowH = 56
    local pad = 8
    local y = 0
    local contentW = content:GetWidth()

    for i, g in ipairs(list) do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(contentW, rowH)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        if i % 2 == 0 then
            bg:SetColorTexture(0.08, 0.08, 0.10, 0.95)
        else
            bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
        end

        local nameFS
        if FontManager and FontManager.CreateFontString then
            nameFS = FontManager:CreateFontString(row, "body", "OVERLAY")
        else
            nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", pad, -6)
        nameFS:SetText(g.instanceName)
        nameFS:SetTextColor(1, 1, 1)

        local diffColor = DIFF_COLOR[g.difficulty] or "|cffaaaaaa"
        local diffFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        diffFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -2)
        diffFS:SetText(diffColor .. (g.difficultyName or "") .. "|r")

        -- Character chips on right
        local chipParent = row
        local chipLine = chipParent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chipLine:SetPoint("TOPRIGHT", row, "TOPRIGHT", -pad, -8)
        chipLine:SetPoint("BOTTOMLEFT", diffFS, "BOTTOMRIGHT", 30, 0)
        chipLine:SetJustifyH("RIGHT")
        chipLine:SetWordWrap(true)
        chipLine:SetSpacing(2)
        local parts = {}
        for _, c in ipairs(g.characters) do
            local hex, charName = GetClassHexFromCharacters(c.charKey)
            local progressColor = "|cffd4af37"
            if c.total > 0 and c.killed >= c.total then progressColor = "|cff44ff44" end
            table.insert(parts, string.format("|cff%s%s|r %s%d/%d|r",
                hex, charName, progressColor, c.killed or 0, c.total or 0))
        end
        chipLine:SetText(table.concat(parts, "  "))

        table.insert(S.savedRows, row)
        y = y + rowH + 2
    end

    content:SetHeight(math.max(40, y))
    S.savedFrame:Show()
end

ToggleSavedInstances = function()
    if S.savedFrame and S.savedFrame:IsShown() then
        S.savedFrame:Hide()
        return
    end
    BuildSavedInstancesFrame()
    if S.savedFrame and S.button and not S.savedFrame:GetPoint() then
        S.savedFrame:ClearAllPoints()
        S.savedFrame:SetPoint("TOPLEFT", S.button, "BOTTOMLEFT", 0, -6)
    end
    if RequestRaidInfo then pcall(RequestRaidInfo) end
    RefreshSavedInstances()
end

-- ============================================================================
-- Vault Button shortcut menu
-- ============================================================================
local function CreateMenuItem(parent, opts, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(parent:GetWidth() - 8, 30)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or {0.40, 0.20, 0.58}
    hl:SetColorTexture(accent[1], accent[2], accent[3], 0.25)

    if opts.icon then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("LEFT", 6, 0)
        icon:SetTexture(opts.icon)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end

    local FontManager = ns.FontManager
    local label
    if FontManager and FontManager.CreateFontString then
        label = FontManager:CreateFontString(btn, "body", "OVERLAY")
    else
        label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    label:SetPoint("LEFT", 32, 0)
    label:SetText(opts.label)
    label:SetTextColor(1, 1, 1)

    btn:SetScript("OnClick", function()
        HideMenu()
        if opts.action then opts.action() end
    end)
    return btn
end

local function BuildMenu()
    if S.menuFrame then return end
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}

    local items = {
        { label = "Vault Tracker", icon = "Interface\\Icons\\INV_Misc_Bag_EnchantedRunecloth", action = function()
            HideAllPanels()
            RefreshTable()
            if S.tableFrame and S.button then
                S.tableFrame:ClearAllPoints()
                local saved = GetSavedTablePos()
                if saved and saved.x and saved.y then
                    S.tableFrame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x, saved.y)
                else
                    S.tableFrame:SetPoint("TOPLEFT", S.button, "BOTTOMLEFT", 0, -6)
                end
            end
        end },
        { label = "Saved Instances", icon = "Interface\\Icons\\INV_Misc_Bell_01", action = function()
            HideTable(); HideMenu(); ToggleSavedInstances()
        end },
        { label = "Plans / Todo",    icon = "Interface\\Icons\\INV_Inscription_Scroll", action = function() OpenWNTab("plans") end },
        { label = "Open Warband Nexus", icon = ICON_TEXTURE,                            action = function() OpenWNTab(nil) end },
        { label = "Settings",        icon = "Interface\\Icons\\Trade_Engineering",      action = function()
            HideMenu(); ToggleOptionsFrame(S.button, "RIGHT")
        end },
    }

    local W = 200
    local rowH = 30
    local headerH = 8
    local pad = 6
    local H = headerH + (#items * (rowH + 2)) + pad

    local f = CreateFrame("Frame", "WarbandNexusVaultMenu", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultMenu")
    f:SetSize(W, H)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(220)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    end
    f:Hide()

    local stripe = f:CreateTexture(nil, "BORDER")
    stripe:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    stripe:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    stripe:SetHeight(headerH - 2)
    stripe:SetColorTexture(accentDark[1], accentDark[2], accentDark[3], 1)

    local y = -headerH - 2
    for _, opt in ipairs(items) do
        CreateMenuItem(f, opt, y)
        y = y - (rowH + 2)
    end

    -- Auto-hide on focus loss: close when mouse leaves and not over a child
    f:SetScript("OnUpdate", function(self)
        if not self:IsMouseOver() then
            self._hideTimer = (self._hideTimer or 0) + 1
            if self._hideTimer > 90 then  -- ~1.5s @ 60fps
                self:Hide()
            end
        else
            self._hideTimer = 0
        end
    end)

    S.menuFrame = f
end

ToggleMenu = function()
    BuildMenu()
    if not S.menuFrame then return end
    if S.menuFrame:IsShown() then
        S.menuFrame:Hide()
        return
    end
    S.menuFrame:ClearAllPoints()
    if S.button then
        S.menuFrame:SetPoint("TOPLEFT", S.button, "BOTTOMLEFT", 0, -4)
    else
        S.menuFrame:SetPoint("CENTER")
    end
    S.menuFrame._hideTimer = 0
    S.menuFrame:Show()
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
            -- Right-click is a no-op (drag is handled separately); the menu owns navigation now.
            HideMenu()
        else
            ToggleMenu()
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
eFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    C_Timer.After(2, function() BuildButton(); UpdateBadge() end)
end)

local function OnDataChanged()
    UpdateBadge()
    if S.tableFrame and S.tableFrame:IsShown() then
        RefreshTable()
    end
    if S.savedFrame and S.savedFrame:IsShown() then
        RefreshSavedInstances()
    end
end

local function HookWNMessages()
    if not WarbandNexus or not WarbandNexus.RegisterMessage then return end
    local E = ns.Constants and ns.Constants.EVENTS
    if not E then return end
    if E.PVE_UPDATED then
        WarbandNexus:RegisterMessage(E.PVE_UPDATED, OnDataChanged)
    end
    if E.CHARACTER_UPDATED then
        WarbandNexus:RegisterMessage(E.CHARACTER_UPDATED, OnDataChanged)
    end
    if E.VAULT_REWARD_AVAILABLE then
        WarbandNexus:RegisterMessage(E.VAULT_REWARD_AVAILABLE, OnDataChanged)
    end
    if E.VAULT_SLOT_COMPLETED then
        WarbandNexus:RegisterMessage(E.VAULT_SLOT_COMPLETED, OnDataChanged)
    end
    if E.CURRENCY_UPDATED then
        WarbandNexus:RegisterMessage(E.CURRENCY_UPDATED, function()
            if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
        end)
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
