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

--- Toggle main window: hides if already shown, otherwise opens on the last-used tab
local function ToggleMainWindow()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    local mf = WarbandNexus and WarbandNexus.mainFrame
    if mf and mf:IsShown() then
        mf:Hide()
        return
    end
    OpenWNTab(nil)
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
    menuFrame=nil, savedFrame=nil, savedRows={}, savedExpanded={}
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

    if S.button and S.button.BorderTop then
        local Factory = ns.UI and ns.UI.Factory
        local readyCount = CountReady()
        local r, g, b, a
        if readyCount > 0 then
            r, g, b, a = accent[1], accent[2], accent[3], 1
        else
            r, g, b, a = border[1], border[2], border[3], 0.85
        end
        if Factory and Factory.UpdateBorderColor then
            Factory:UpdateBorderColor(S.button, {r, g, b, a})
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
        local slotsReadyLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_SLOTS_READY"]) or "Slots Ready"
        if e.isReady then
            statusFS:SetText("|cff44ff44" .. readyLabel .. "|r")
        elseif (e.slots or 0) > 0 then
            statusFS:SetText("|cff66ddff" .. slotsReadyLabel .. "|r")
        else
            statusFS:SetText("|cffffd700" .. pendingLabel .. "|r")
        end

        -- Row tooltip: iLvl per slot + bounty status (themed)
        row:SetScript("OnEnter", function(self)
            local ilvlLabel = e.itemLevel > 0
                and ("  |cffd4af37" .. string.format("%.0f", e.itemLevel) .. " iLvl|r") or ""
            local lines = {}
            lines[#lines + 1] = { text = FormatCharacterName(e) .. ilvlLabel }
            lines[#lines + 1] = { text = " " }

            for _, cat in ipairs(catDefs) do
                local slots = allSlots[cat.key]
                local parts = {}
                for si = 1, 3 do
                    local s = slots[si]
                    if s.complete then
                        if s.ilvl > 0 then parts[si] = FormatRewardIlvl(s.ilvl, cat.key)
                        elseif s.canUpgrade then parts[si] = UPARROW
                        else parts[si] = CHECK end
                    else
                        parts[si] = CROSS
                    end
                end
                lines[#lines + 1] = {
                    left = cat.label, right = table.concat(parts, "  "),
                    leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 1, 1}
                }
            end

            if columns.bounty ~= false then
                local bountyLabel = b == nil and DASH
                    or (b and CHECK .. " |cff33dd33Collected|r" or "|cffdd3333Not collected|r")
                lines[#lines + 1] = {
                    left = "|T1064187:14:14:0:0|t Trovehunter's Bounty",
                    right = bountyLabel,
                    leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 1, 1}
                }
            end
            if columns.voidcore ~= false and e.voidcore then
                local vc2 = e.voidcore
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
                lines[#lines + 1] = {
                    left = "|T7658128:14:14:0:0|t Nebulous Voidcore",
                    right = vcLabel,
                    leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 1, 1}
                }
            end
            if columns.manaflux == true and e.manaflux then
                lines[#lines + 1] = {
                    left = "|T" .. GetCurrencyIcon(MANAFLUX_ID, TRACK_ICONS.manaflux) .. ":14:14:0:0|t Dawnlight Manaflux",
                    right = "|cffd4af37" .. (e.manaflux.quantity or 0) .. " held|r",
                    leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 1, 1}
                }
            end

            lines[#lines + 1] = { text = " " }
            local readyMsg = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"
            local pendingMsg = (ns.L and ns.L["VAULT_TRACKER_STATUS_PENDING"]) or "Pending..."
            local slotsReadyMsg = (ns.L and ns.L["VAULT_TRACKER_STATUS_SLOTS_READY"]) or "Slots Ready"
            if e.isReady then
                lines[#lines + 1] = { text = readyMsg, color = {0.27, 1, 0.27} }
            elseif (e.slots or 0) > 0 then
                lines[#lines + 1] = { text = string.format("%s (%d)", slotsReadyMsg, e.slots), color = {0.4, 0.85, 1} }
            else
                lines[#lines + 1] = { text = pendingMsg, color = {1, 0.84, 0} }
            end
            lines[#lines + 1] = { text = "|cff888888[Click] Open PvE tab|r" }

            WNTooltipShow(self, { type = "custom", lines = lines, anchor = "ANCHOR_RIGHT" })
        end)
        row:SetScript("OnLeave", function() WNTooltipHide() end)

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
-- Themed tooltip helpers (delegate to ns.UI_ShowTooltip / ns.UI_HideTooltip,
-- with GameTooltip fallback before TooltipService is initialised).
-- ============================================================================
local function WNTooltipShow(anchor, data)
    if ns.UI_ShowTooltip and WarbandNexus and WarbandNexus.Tooltip then
        ns.UI_ShowTooltip(anchor, data)
    else
        GameTooltip:SetOwner(anchor, data.anchor or "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        if data.title then GameTooltip:AddLine(data.title, 1, 1, 1) end
        if data.description then GameTooltip:AddLine(data.description, 0.85, 0.85, 0.85, true) end
        if data.lines then
            for _, line in ipairs(data.lines) do
                if line.left or line.right then
                    local lc, rc = line.leftColor or {1,1,1}, line.rightColor or {1,1,1}
                    GameTooltip:AddDoubleLine(line.left or "", line.right or "",
                        lc[1], lc[2], lc[3], rc[1], rc[2], rc[3])
                else
                    local c = line.color or {1,1,1}
                    GameTooltip:AddLine(line.text or "", c[1], c[2], c[3], line.wrap == true)
                end
            end
        end
        GameTooltip:Show()
    end
end

local function WNTooltipHide()
    if ns.UI_HideTooltip then ns.UI_HideTooltip() else GameTooltip:Hide() end
end

-- ============================================================================
-- Hover tooltip (current character only)
-- ============================================================================
local function ShowHoverTooltip(anchor)
    local readyLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"
    local pendingLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_PENDING"]) or "Pending..."

    local charKey = GetCurrentCharKey()
    local chars = GetCharacters()
    local entry = chars and charKey and chars[charKey]

    local lines = {}
    if not entry then
        lines[#lines + 1] = { text = "No vault data for current character yet.", color = {0.6, 0.6, 0.6} }
    else
        local pveCache = GetPveCache()
        local rewards = pveCache and pveCache.greatVault and pveCache.greatVault.rewards
        local rewardData = rewards and rewards[charKey]
        local isReady = (rewardData and rewardData.hasAvailableRewards) or false

        local nameLine = "|cff" .. GetClassHex(entry.classFile) .. (entry.name or charKey) .. "|r"
        if entry.itemLevel and entry.itemLevel > 0 then
            nameLine = nameLine .. "  |cffd4af37" .. string.format("%.0f", entry.itemLevel) .. " iLvl|r"
        end
        lines[#lines + 1] = { text = nameLine }
        lines[#lines + 1] = { text = " " }

        local catLabels = { raids = "Raid", mythicPlus = "Dungeon", world = "World" }
        for _, key in ipairs({ "raids", "mythicPlus", "world" }) do
            local slots = GetSlotData(charKey, key)
            local parts = {}
            for i = 1, 3 do
                local s = slots[i]
                if s.complete then
                    parts[i] = s.canUpgrade and UPARROW or CHECK
                else
                    parts[i] = CROSS
                end
            end
            lines[#lines + 1] = {
                left = catLabels[key],
                right = table.concat(parts, "  "),
                leftColor = {0.7, 0.7, 0.7},
                rightColor = {1, 1, 1},
            }
        end

        local bounty = GetBountyStatus(charKey)
        if bounty ~= nil then
            local bountyLabel = bounty and (CHECK .. " |cff33dd33Collected|r") or "|cffdd3333Not collected|r"
            lines[#lines + 1] = {
                left = "|T1064187:14:14:0:0|t Trovehunter's Bounty",
                right = bountyLabel,
                leftColor = {0.7, 0.7, 0.7},
                rightColor = {1, 1, 1},
            }
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
            lines[#lines + 1] = {
                left = "|T7658128:14:14:0:0|t Nebulous Voidcore",
                right = vcLabel,
                leftColor = {0.7, 0.7, 0.7},
                rightColor = {1, 1, 1},
            }
        end

        if GetSettings().showManaflux then
            local mf = GetManafluxData(charKey)
            if mf then
                lines[#lines + 1] = {
                    left = "|T" .. GetCurrencyIcon(MANAFLUX_ID, TRACK_ICONS.manaflux) .. ":14:14:0:0|t Dawnlight Manaflux",
                    right = "|cffd4af37" .. (mf.quantity or 0) .. " held|r",
                    leftColor = {0.7, 0.7, 0.7},
                    rightColor = {1, 1, 1},
                }
            end
        end

        lines[#lines + 1] = { text = " " }
        local slotsReadyLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_SLOTS_READY"]) or "Slots Ready"
        local readySlotCount = CountReadySlots(charKey)
        if isReady then
            lines[#lines + 1] = { text = readyLabel, color = {0.27, 1, 0.27} }
        elseif readySlotCount > 0 then
            lines[#lines + 1] = { text = string.format("%s (%d)", slotsReadyLabel, readySlotCount), color = {0.4, 0.85, 1} }
        else
            lines[#lines + 1] = { text = pendingLabel, color = {1, 0.84, 0} }
        end
    end

    lines[#lines + 1] = { text = " " }
    lines[#lines + 1] = { text = "|cff888888[Left-click] Toggle Window  [Right-click] Menu  [Drag] Move|r" }

    WNTooltipShow(anchor, {
        type = "custom",
        title = "Warband Nexus",
        icon = ICON_TEXTURE,
        lines = lines,
        anchor = "ANCHOR_RIGHT",
    })
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
local DIFF_INFO = {
    [17] = { short = "LFR",    name = "Looking For Raid", color = {0.55, 0.55, 0.55}, hex = "aaaaaa" },
    [14] = { short = "N",      name = "Normal",           color = {0.12, 0.78, 0.12}, hex = "1eff00" },
    [15] = { short = "H",      name = "Heroic",           color = {0.00, 0.44, 0.87}, hex = "0070dd" },
    [16] = { short = "M",      name = "Mythic",           color = {0.64, 0.21, 0.93}, hex = "a335ee" },
}
local FALLBACK_DIFF = { short = "?", name = "Unknown", color = {0.4, 0.4, 0.4}, hex = "aaaaaa" }
local DIFFICULTY_ORDER_DESC = { 16, 15, 14, 17 }  -- Mythic > Heroic > Normal > LFR
-- Sort priority for the Saved Instances grid: LFR first, then N, H, M
local DIFF_SORT_RANK = { [17] = 1, [14] = 2, [15] = 3, [16] = 4 }

local function GetDiffInfo(difficulty)
    return DIFF_INFO[difficulty] or FALLBACK_DIFF
end

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
    local nowServer = (GetServerTime and GetServerTime()) or time()
    local groups = {}
    for charKey, instances in pairs(lockouts) do
        if type(instances) == "table" then
            for _, inst in pairs(instances) do
                local expired = inst and inst.resetAt and inst.resetAt <= nowServer
                if inst and inst.name and not expired then
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
                        reset = (function()
                            -- Prefer absolute resetAt (server timestamp) so the
                            -- countdown is accurate for offline alts; fall back
                            -- to the raw `reset` field for legacy cache entries.
                            local now = (GetServerTime and GetServerTime()) or time()
                            if inst.resetAt and inst.resetAt > now then
                                return inst.resetAt - now
                            elseif inst.resetAt and inst.resetAt <= now then
                                return 0  -- already expired
                            end
                            return inst.reset
                        end)(),
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
        local ra = DIFF_SORT_RANK[a.difficulty] or 99
        local rb = DIFF_SORT_RANK[b.difficulty] or 99
        if ra ~= rb then return ra < rb end
        return (a.instanceName or "") < (b.instanceName or "")
    end)
    return list
end

local SAVED_FRAME_W = 760
local SAVED_FILTER_H = 36
local CARD_W, CARD_H = 232, 108
local CARD_GAP = 10
local DOT_SIZE = 12
local DOT_GAP = 4

local function BuildSavedInstancesFrame()
    if S.savedFrame then return end
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}

    local f = CreateFrame("Frame", "WarbandNexusSavedInstances", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusSavedInstances")
    f:SetSize(SAVED_FRAME_W, 480)
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

    -- Filter / search bar
    local filterRow = CreateFrame("Frame", nil, f)
    filterRow:SetHeight(SAVED_FILTER_H)
    -- Match chrome's 2px window inset for visual symmetry
    filterRow:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -(CHROME_H + 4))
    filterRow:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -(CHROME_H + 4))
    if ApplyVisuals then
        ApplyVisuals(filterRow, {0.06, 0.06, 0.08, 1}, {accent[1], accent[2], accent[3], 0.4})
    end

    S.savedFilters = { lfr = false, normal = true, heroic = true, mythic = true }
    S.savedFilterButtons = {}
    local filterBtns = {
        { key = "lfr",     label = "LFR", diff = 17 },
        { key = "normal",  label = "N",   diff = 14 },
        { key = "heroic",  label = "H",   diff = 15 },
        { key = "mythic",  label = "M",   diff = 16 },
    }
    local SIDE_PAD = (ns.UI_SPACING and ns.UI_SPACING.SIDE_MARGIN) or 10
    local fx = SIDE_PAD
    for _, fb in ipairs(filterBtns) do
        local di = GetDiffInfo(fb.diff)
        local b = CreateFrame("Button", nil, filterRow)
        b:SetSize(fb.key == "lfr" and 38 or 28, 22)
        b:SetPoint("LEFT", fx, 0)
        if ApplyVisuals then
            ApplyVisuals(b, {di.color[1] * 0.35, di.color[2] * 0.35, di.color[3] * 0.35, 1}, {di.color[1], di.color[2], di.color[3], 0.85})
        end
        local lbl = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("CENTER")
        lbl:SetText("|cff" .. di.hex .. fb.label .. "|r")
        b:SetScript("OnClick", function()
            S.savedFilters[fb.key] = not S.savedFilters[fb.key]
            RefreshSavedInstances()
        end)
        b._applyState = function()
            local active = S.savedFilters[fb.key]
            if ApplyVisuals then
                local Factory = ns.UI and ns.UI.Factory
                if Factory and Factory.UpdateBorderColor then
                    Factory:UpdateBorderColor(b, {di.color[1], di.color[2], di.color[3], active and 1 or 0.3})
                end
            end
            lbl:SetAlpha(active and 1 or 0.45)
        end
        b._applyState()
        S.savedFilterButtons[fb.key] = b
        fx = fx + b:GetWidth() + 4
    end

    -- Char count summary on the right of filter row (matches addon side margin)
    local summary = filterRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    summary:SetPoint("RIGHT", filterRow, "RIGHT", -SIDE_PAD, 0)
    summary:SetTextColor(0.75, 0.75, 0.8)
    f.summary = summary

    -- Scroll body
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", 0, -4)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(SAVED_FRAME_W - 4, 1)
    scroll:SetScrollChild(content)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        if IsShiftKeyDown and IsShiftKeyDown() then
            -- Horizontal scroll (table can overflow with many characters)
            local maxX = math.max(0, (content:GetWidth() or 0) - (scroll:GetWidth() or 0))
            local cur = scroll:GetHorizontalScroll() or 0
            scroll:SetHorizontalScroll(math.min(maxX, math.max(0, cur - delta * 60)))
        else
            local cur = scroll:GetVerticalScroll()
            scroll:SetVerticalScroll(math.max(0, cur - delta * 40))
        end
    end)

    S.savedFrame = f
    S.savedScroll = scroll
    S.savedContent = content
end

--- Aggregate per-boss state across characters: returns table[bossIdx] = { name, killers={charKey...} }
local function AggregateBosses(group)
    local roster = nil
    for _, c in ipairs(group.characters) do
        if c.encounters and #c.encounters > 0 then roster = c.encounters; break end
    end
    if not roster then return nil end
    local bosses = {}
    for i, e in ipairs(roster) do
        bosses[i] = { name = e.name or ("Boss " .. i), killers = {} }
    end
    for _, c in ipairs(group.characters) do
        if c.encounters then
            for i, e in ipairs(c.encounters) do
                if e.killed and bosses[i] then
                    table.insert(bosses[i].killers, c.charKey)
                end
            end
        end
    end
    return bosses
end

--- Build one row representing a single character's lockout in a given (instance, difficulty)
-- Columns: [Character (class colored)] [Bosses dot row] [X/Y] [reset]
local function BuildLockoutRow(parent, char, encounters, group, totalW)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local hex, charName = GetClassHexFromCharacters(char.charKey)
    local k, t = char.killed or 0, char.total or 0
    local diffInfo = GetDiffInfo(group.difficulty)

    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(totalW, 26)
    row:EnableMouse(true)

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.05, 0.05, 0.07, 0.85)

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.18)

    -- Layout columns (equal-width predictable structure)
    local PAD = 8
    local NAME_W = 150
    local PROGRESS_W = 50
    local RESET_W = 48
    local dotsX = PAD + NAME_W + 8
    local dotsRight = totalW - PAD - PROGRESS_W - 8 - RESET_W - 8
    local dotsW = math.max(40, dotsRight - dotsX)

    -- Character name
    local nameFS
    if FontManager and FontManager.CreateFontString then
        nameFS = FontManager:CreateFontString(row, "body", "OVERLAY")
    else
        nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    nameFS:SetPoint("LEFT", row, "LEFT", PAD, 0)
    nameFS:SetWidth(NAME_W)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetText("|cff" .. hex .. (charName or char.charKey) .. "|r")

    -- Boss dots (one per encounter, scaled to fit dotsW)
    local roster = encounters or {}
    local bossCount = #roster
    if bossCount > 0 then
        local size = math.max(8, math.min(14, math.floor((dotsW - (bossCount - 1) * 3) / bossCount)))
        local gap = math.max(2, math.floor((dotsW - bossCount * size) / math.max(1, bossCount - 1)))
        if bossCount == 1 then gap = 0 end
        for i, e in ipairs(roster) do
            local dot = row:CreateTexture(nil, "ARTWORK")
            dot:SetSize(size, size)
            dot:SetPoint("LEFT", row, "LEFT", dotsX + (i - 1) * (size + gap), 0)
            if e.killed then
                dot:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)
            else
                dot:SetColorTexture(0.18, 0.18, 0.22, 1)
            end
        end
    end

    -- Progress text
    local progFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progFS:SetPoint("RIGHT", row, "RIGHT", -PAD - RESET_W - 8, 0)
    progFS:SetWidth(PROGRESS_W)
    progFS:SetJustifyH("RIGHT")
    local progColor = (t > 0 and k >= t) and "|cff44ff44" or "|cffd4af37"
    progFS:SetText(string.format("%s%d/%d|r", progColor, k, t))

    -- Reset countdown
    local resetFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    resetFS:SetPoint("RIGHT", row, "RIGHT", -PAD, 0)
    resetFS:SetWidth(RESET_W)
    resetFS:SetJustifyH("RIGHT")
    resetFS:SetTextColor(0.55, 0.55, 0.6)
    if char.reset and char.reset > 0 then
        local hours = math.floor(char.reset / 3600)
        local days = math.floor(hours / 24)
        if days > 0 then
            resetFS:SetText(days .. "d")
        elseif hours > 0 then
            resetFS:SetText(hours .. "h")
        else
            resetFS:SetText("<1h")
        end
    end

    -- Hover tooltip: list of bosses killed by this specific character
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine("|cff" .. hex .. (charName or char.charKey) .. "|r")
        GameTooltip:AddLine(group.instanceName .. " — |cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r")
        GameTooltip:AddLine(" ")
        for i, e in ipairs(roster) do
            local mark = e.killed and "|cff44ff44" .. CHECK .. "|r" or "|cff444444" .. CROSS .. "|r"
            GameTooltip:AddDoubleLine(mark .. " " .. (e.name or ("Boss " .. i)),
                e.killed and "|cff44ff44killed|r" or "|cff666666—|r",
                1,1,1, 0.85,0.85,0.85)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

--- Build the section header for an (instance, difficulty) group
local function BuildGroupHeader(parent, group, totalW)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local diffInfo = GetDiffInfo(group.difficulty)

    local header = CreateFrame("Frame", nil, parent)
    header:SetSize(totalW, 30)

    if ApplyVisuals then
        ApplyVisuals(header, {diffInfo.color[1] * 0.18, diffInfo.color[2] * 0.18, diffInfo.color[3] * 0.18, 1},
            {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.85})
    end

    -- Difficulty stripe (left edge)
    local stripe = header:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(3)
    stripe:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)

    -- Difficulty badge
    local badge = CreateFrame("Frame", nil, header)
    badge:SetSize(diffInfo.short == "LFR" and 36 or 22, 16)
    badge:SetPoint("LEFT", 12, 0)
    if ApplyVisuals then
        ApplyVisuals(badge, {diffInfo.color[1] * 0.5, diffInfo.color[2] * 0.5, diffInfo.color[3] * 0.5, 1},
            {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1})
    end
    local badgeFS = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeFS:SetPoint("CENTER")
    badgeFS:SetText("|cffffffff" .. diffInfo.short .. "|r")

    -- Instance name
    local nameFS
    if FontManager and FontManager.CreateFontString then
        nameFS = FontManager:CreateFontString(header, "body", "OVERLAY")
    else
        nameFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    nameFS:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    nameFS:SetText(group.instanceName)
    nameFS:SetTextColor(1, 1, 1)

    -- Right side: aggregate "X chars · Y/Z warband"
    local bosses = AggregateBosses(group)
    local cleared, total = 0, bosses and #bosses or 0
    if bosses then
        for _, b in ipairs(bosses) do if #b.killers > 0 then cleared = cleared + 1 end end
    end
    local statsFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    statsFS:SetPoint("RIGHT", -10, 0)
    statsFS:SetTextColor(0.85, 0.85, 0.9)
    local progColor = (total > 0 and cleared >= total) and "|cff44ff44" or "|cffd4af37"
    statsFS:SetText(string.format("%d %s · %s%d/%d|r warband",
        #group.characters, #group.characters == 1 and "char" or "chars",
        progColor, cleared, total))

    return header
end

local function BuildInstanceCard(parent, group)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local diffInfo = GetDiffInfo(group.difficulty)

    local card = CreateFrame("Button", nil, parent)
    card:SetSize(CARD_W, CARD_H)
    if ApplyVisuals then
        ApplyVisuals(card, {0.04, 0.04, 0.06, 0.96}, {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.55})
    end

    -- Subtle top stripe (difficulty color)
    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("TOPRIGHT", -1, -1)
    stripe:SetHeight(2)
    stripe:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)

    -- Difficulty badge (top-right)
    local badge = CreateFrame("Frame", nil, card)
    badge:SetSize(diffInfo.short == "LFR" and 36 or 22, 16)
    badge:SetPoint("TOPRIGHT", -6, -8)
    if ApplyVisuals then
        ApplyVisuals(badge, {diffInfo.color[1] * 0.45, diffInfo.color[2] * 0.45, diffInfo.color[3] * 0.45, 1},
            {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1})
    end
    local badgeFS = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    badgeFS:SetPoint("CENTER")
    badgeFS:SetText("|cffffffff" .. diffInfo.short .. "|r")

    -- Instance name (single line, truncated by width)
    local FontManager = ns.FontManager
    local nameFS
    if FontManager and FontManager.CreateFontString then
        nameFS = FontManager:CreateFontString(card, "body", "OVERLAY")
    else
        nameFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    end
    nameFS:SetPoint("TOPLEFT", 10, -8)
    nameFS:SetPoint("TOPRIGHT", badge, "TOPLEFT", -6, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetText(group.instanceName)

    -- Boss roster (per-boss aggregate state across warband)
    local bosses = AggregateBosses(group)
    local cleared, total = 0, bosses and #bosses or 0
    if bosses then
        for _, b in ipairs(bosses) do if #b.killers > 0 then cleared = cleared + 1 end end
    end

    -- Boss dots row
    local dotRow = CreateFrame("Frame", nil, card)
    dotRow:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -10)
    dotRow:SetPoint("RIGHT", card, "RIGHT", -10, 0)
    dotRow:SetHeight(DOT_SIZE)

    if bosses and total > 0 then
        local availW = CARD_W - 20
        local needW = total * DOT_SIZE + (total - 1) * DOT_GAP
        local size = DOT_SIZE
        local gap = DOT_GAP
        if needW > availW then
            -- Shrink dots to fit; min 6px, gap 2px
            gap = 2
            size = math.max(6, math.floor((availW - (total - 1) * gap) / total))
        end
        for i, b in ipairs(bosses) do
            local n = #b.killers
            local dot = dotRow:CreateTexture(nil, "ARTWORK")
            dot:SetSize(size, size)
            dot:SetPoint("LEFT", (i - 1) * (size + gap), 0)
            if n == 0 then
                dot:SetColorTexture(0.18, 0.18, 0.22, 1)         -- nobody cleared
            elseif n >= #group.characters then
                dot:SetColorTexture(0.20, 0.85, 0.30, 1)         -- all chars cleared
            else
                dot:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)  -- some cleared
            end
        end
    else
        local fallback = dotRow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fallback:SetPoint("LEFT")
        fallback:SetTextColor(0.5, 0.5, 0.5)
        fallback:SetText("(boss roster unavailable)")
    end

    -- Bottom row: warband progress · character avatars (initials)
    local pct = (total > 0) and (cleared / total) or 0

    -- Slim progress bar
    local barBg = card:CreateTexture(nil, "BACKGROUND")
    barBg:SetPoint("BOTTOMLEFT", 10, 30)
    barBg:SetPoint("BOTTOMRIGHT", -10, 30)
    barBg:SetHeight(3)
    barBg:SetColorTexture(0.10, 0.10, 0.12, 1)
    if pct > 0 then
        local barFill = card:CreateTexture(nil, "ARTWORK")
        barFill:SetPoint("TOPLEFT", barBg, "TOPLEFT", 0, 0)
        barFill:SetPoint("BOTTOMLEFT", barBg, "BOTTOMLEFT", 0, 0)
        barFill:SetWidth(math.max(1, (CARD_W - 20) * pct))
        local color = (cleared >= total) and {0.20, 0.85, 0.30} or {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3]}
        barFill:SetColorTexture(color[1], color[2], color[3], 1)
    end

    -- Warband progress label (left) + character chips (right)
    local progFS = card:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progFS:SetPoint("BOTTOMLEFT", 10, 10)
    local progColor = (total > 0 and cleared >= total) and "|cff44ff44" or "|cffd4af37"
    progFS:SetText(string.format("%s%d/%d|r |cff888888warband|r", progColor, cleared, total))

    -- Character chips (class-colored initials), max 6 visible
    local chipsFrame = CreateFrame("Frame", nil, card)
    chipsFrame:SetPoint("BOTTOMRIGHT", -10, 8)
    chipsFrame:SetSize(120, 18)
    local maxChips = math.min(#group.characters, 6)
    local chipX = 0
    for i = #group.characters, math.max(1, #group.characters - maxChips + 1), -1 do
        local c = group.characters[i]
        local hex, charName = GetClassHexFromCharacters(c.charKey)
        local initial = (charName and charName:sub(1, 1)) or "?"
        local chip = chipsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        chip:SetPoint("RIGHT", -chipX, 0)
        local k, t = c.killed or 0, c.total or 0
        local done = (t > 0 and k >= t)
        chip:SetText(string.format("|cff%s%s|r", hex, initial))
        chip:SetAlpha(done and 1 or 0.55)
        chipX = chipX + 12
    end
    if #group.characters > maxChips then
        local extra = chipsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        extra:SetPoint("RIGHT", -chipX, 0)
        extra:SetText(string.format("|cffaaaaaa+%d|r", #group.characters - maxChips))
    end

    -- Hover tooltip
    card:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine(group.instanceName, 1, 1, 1)
        GameTooltip:AddDoubleLine(
            "|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r",
            string.format("|cffd4af37%d/%d|r |cff888888warband cleared|r", cleared, total),
            1,1,1, 1,1,1)
        GameTooltip:AddLine(" ")

        -- Per-boss with which characters killed it
        if bosses and #bosses > 0 then
            for i, b in ipairs(bosses) do
                local killers = b.killers or {}
                local right
                if #killers == 0 then
                    right = "|cff666666—|r"
                else
                    local parts = {}
                    for _, ck in ipairs(killers) do
                        local hex, charName = GetClassHexFromCharacters(ck)
                        table.insert(parts, "|cff" .. hex .. charName .. "|r")
                    end
                    right = table.concat(parts, ", ")
                end
                local mark = (#killers > 0) and "|cff44ff44" .. CHECK .. "|r" or "|cff444444" .. CROSS .. "|r"
                GameTooltip:AddDoubleLine(mark .. " " .. b.name, right, 1, 1, 1, 0.9, 0.9, 0.9)
            end
            GameTooltip:AddLine(" ")
        end

        -- Per-character summary
        GameTooltip:AddLine("|cffaaaaaaCharacters|r")
        for _, c in ipairs(group.characters) do
            local hex, charName = GetClassHexFromCharacters(c.charKey)
            local k, t = c.killed or 0, c.total or 0
            local color = (t > 0 and k >= t) and "|cff44ff44" or "|cffd4af37"
            local resetSuffix = ""
            if c.reset and c.reset > 0 then
                local hours = math.floor(c.reset / 3600)
                local days = math.floor(hours / 24)
                if days > 0 then resetSuffix = string.format("  |cff666666%dd|r", days)
                elseif hours > 0 then resetSuffix = string.format("  |cff666666%dh|r", hours) end
            end
            GameTooltip:AddDoubleLine(
                "|cff" .. hex .. charName .. "|r",
                string.format("%s%d/%d|r%s", color, k, t, resetSuffix),
                1, 1, 1, 1, 1, 1)
        end
        GameTooltip:Show()
    end)
    card:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return card
end

RefreshSavedInstances = function()
    BuildSavedInstancesFrame()
    local content = S.savedContent
    if not content then return end

    for _, row in ipairs(S.savedRows) do row:Hide() end
    S.savedRows = {}

    local list = BuildSavedInstancesData()

    -- Apply difficulty filter
    local filtered = {}
    local filters = S.savedFilters or {}
    for _, g in ipairs(list) do
        local diff = g.difficulty
        local pass = (diff == 17 and filters.lfr)
                  or (diff == 14 and filters.normal)
                  or (diff == 15 and filters.heroic)
                  or (diff == 16 and filters.mythic)
                  or (diff ~= 14 and diff ~= 15 and diff ~= 16 and diff ~= 17)
        if pass then table.insert(filtered, g) end
    end

    -- Update filter button states (highlight active)
    if S.savedFilterButtons then
        for _, b in pairs(S.savedFilterButtons) do
            if b._applyState then b._applyState() end
        end
    end

    -- Char count summary
    if S.savedFrame and S.savedFrame.summary then
        local charSet = {}
        for _, g in ipairs(filtered) do
            for _, c in ipairs(g.characters) do charSet[c.charKey] = true end
        end
        local n = 0
        for _ in pairs(charSet) do n = n + 1 end
        S.savedFrame.summary:SetText(string.format("%d instances · %d characters", #filtered, n))
    end

    if #filtered == 0 then
        local msg = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        msg:SetPoint("CENTER", content, "CENTER", 0, -20)
        msg:SetTextColor(0.6, 0.6, 0.6)
        if #list == 0 then
            msg:SetText("No raid lockouts recorded yet.\nLogin a character with active lockouts to populate.")
        else
            msg:SetText("No instances match the current filters.")
        end
        msg:SetJustifyH("CENTER")
        content:SetHeight(80)
        table.insert(S.savedRows, msg)
        S.savedFrame:Show()
        return
    end

    -- ────────────────────────────────────────────────────────────────────
    -- Drill-down list:
    --   • Compact summary row per (instance, difficulty) — 38px, scales
    --     comfortably to 60+ instances without horizontal scroll.
    --   • Each row carries a per-boss "heat" segment bar that shows at a
    --     glance which bosses the warband cleared (green = all chars,
    --     diff color = some, gray = none).
    --   • Click a row to expand inline and reveal one detail line per
    --     locked character (boss-by-boss for that toon, kill count,
    --     reset countdown). Only locked chars show — no 60-column matrix.
    -- ────────────────────────────────────────────────────────────────────
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager  = ns.FontManager
    local SIDE_PAD = (ns.UI_SPACING and ns.UI_SPACING.SIDE_MARGIN) or 10
    local rowW       = content:GetWidth() - 2 * SIDE_PAD
    local SUMMARY_H  = 38
    local DETAIL_H   = 24
    local NAME_COL_W = 200
    local STATS_COL_W = 150

    -- Reset content width to viewport (no horizontal scroll needed)
    content:SetWidth(content:GetParent():GetWidth())

    local function MakeGroupKey(g)
        return (g.instanceName or "?") .. "||" .. tostring(g.difficulty or 0)
    end

    local function HeatColor(ratio, diffInfo)
        if ratio >= 1 then return {0.20, 0.85, 0.30, 1} end
        if ratio <= 0 then return {0.16, 0.16, 0.20, 1} end
        local r, g, b = diffInfo.color[1], diffInfo.color[2], diffInfo.color[3]
        local alpha = 0.4 + ratio * 0.55
        return {r, g, b, alpha}
    end

    local function BuildSummaryRow(g, idx, yPos)
        local diffInfo = GetDiffInfo(g.difficulty)
        local bosses = AggregateBosses(g)
        local total = bosses and #bosses or 0
        local cleared = 0
        if bosses then
            for _, b in ipairs(bosses) do if #b.killers > 0 then cleared = cleared + 1 end end
        end

        local row = CreateFrame("Button", nil, content)
        row:SetSize(rowW, SUMMARY_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE_PAD, -yPos)
        row:RegisterForClicks("LeftButtonUp")

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(idx % 2 == 0 and 0.06 or 0.04, idx % 2 == 0 and 0.06 or 0.04, idx % 2 == 0 and 0.08 or 0.06, 0.95)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.15)

        -- Difficulty stripe
        local stripe = row:CreateTexture(nil, "ARTWORK")
        stripe:SetPoint("TOPLEFT", 0, 0)
        stripe:SetPoint("BOTTOMLEFT", 0, 0)
        stripe:SetWidth(3)
        stripe:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)

        -- Difficulty badge
        local badge = CreateFrame("Frame", nil, row)
        badge:SetSize(diffInfo.short == "LFR" and 36 or 24, 18)
        badge:SetPoint("LEFT", 12, 0)
        if ApplyVisuals then
            ApplyVisuals(badge, {diffInfo.color[1] * 0.45, diffInfo.color[2] * 0.45, diffInfo.color[3] * 0.45, 1},
                {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1})
        end
        local badgeFS = badge:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        badgeFS:SetPoint("CENTER")
        badgeFS:SetText("|cffffffff" .. diffInfo.short .. "|r")

        -- Instance name
        local nameFS
        if FontManager and FontManager.CreateFontString then
            nameFS = FontManager:CreateFontString(row, "body", "OVERLAY")
        else
            nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        end
        nameFS:SetPoint("LEFT", badge, "RIGHT", 10, 0)
        nameFS:SetWidth(NAME_COL_W - (badge:GetWidth() + 30))
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        nameFS:SetText(g.instanceName)
        nameFS:SetTextColor(1, 1, 1)

        -- Boss heat segment bar (variable middle column)
        local heatX = NAME_COL_W + 10
        local heatRight = rowW - STATS_COL_W - 30
        local heatW = math.max(40, heatRight - heatX)
        local heatBg = row:CreateTexture(nil, "BACKGROUND")
        heatBg:SetPoint("LEFT", row, "LEFT", heatX, 0)
        heatBg:SetSize(heatW, 14)
        heatBg:SetColorTexture(0.10, 0.10, 0.12, 1)

        if bosses and total > 0 then
            local segGap = 2
            local segW = math.max(4, math.floor((heatW - (total - 1) * segGap) / total))
            local actualSegGap = (total > 1) and math.floor((heatW - total * segW) / (total - 1)) or 0
            for i, b in ipairs(bosses) do
                local ratio = (#g.characters > 0) and (#b.killers / #g.characters) or 0
                local seg = row:CreateTexture(nil, "ARTWORK")
                seg:SetSize(segW, 14)
                seg:SetPoint("LEFT", row, "LEFT", heatX + (i - 1) * (segW + actualSegGap), 0)
                local col = HeatColor(ratio, diffInfo)
                seg:SetColorTexture(col[1], col[2], col[3], col[4])
            end
        end

        -- Stats: warband progress + char count
        local statsFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        statsFS:SetPoint("RIGHT", row, "RIGHT", -32, 0)
        statsFS:SetJustifyH("RIGHT")
        statsFS:SetWidth(STATS_COL_W)
        local progColor = (total > 0 and cleared >= total) and "|cff44ff44" or "|cffd4af37"
        statsFS:SetText(string.format("%s%d/%d|r |cff888888warband|r  |cffaaaaaa· %d %s|r",
            progColor, cleared, total,
            #g.characters, #g.characters == 1 and "char" or "chars"))

        -- Expand chevron
        local chevron = row:CreateTexture(nil, "OVERLAY")
        chevron:SetSize(14, 14)
        chevron:SetPoint("RIGHT", row, "RIGHT", -10, 0)
        local groupKey = MakeGroupKey(g)
        local function UpdateChevron()
            if S.savedExpanded[groupKey] then
                chevron:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover")
            else
                chevron:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover")
            end
        end
        UpdateChevron()

        row:SetScript("OnClick", function()
            S.savedExpanded[groupKey] = not S.savedExpanded[groupKey]
            RefreshSavedInstances()
        end)

        row:SetScript("OnEnter", function(self)
            local lines = {}
            lines[#lines + 1] = { text = "|cff" .. diffInfo.hex .. (g.difficultyName or diffInfo.name) .. "|r" }
            lines[#lines + 1] = { text = string.format("|cffd4af37%d/%d|r |cff888888warband cleared|r", cleared, total) }
            lines[#lines + 1] = { text = " " }
            if bosses then
                for _, b in ipairs(bosses) do
                    local nKilled = #b.killers
                    local label
                    if nKilled == 0 then
                        label = "|cff666666—|r"
                    elseif nKilled >= #g.characters then
                        label = string.format("|cff44ff44%d/%d chars|r", nKilled, #g.characters)
                    else
                        label = string.format("|cffd4af37%d/%d chars|r", nKilled, #g.characters)
                    end
                    lines[#lines + 1] = {
                        left = b.name, right = label,
                        leftColor = {1, 1, 1}, rightColor = {0.85, 0.85, 0.85}
                    }
                end
            end
            lines[#lines + 1] = { text = " " }
            lines[#lines + 1] = { text = "|cff888888Click to expand character lockouts|r" }
            WNTooltipShow(self, {
                type = "custom",
                title = g.instanceName,
                lines = lines,
                anchor = "ANCHOR_RIGHT",
            })
        end)
        row:SetScript("OnLeave", function() WNTooltipHide() end)

        return row
    end

    local function BuildDetailRow(g, char, yPos)
        local diffInfo = GetDiffInfo(g.difficulty)
        local hex, charName = GetClassHexFromCharacters(char.charKey)

        local row = CreateFrame("Frame", nil, content)
        row:SetSize(rowW, DETAIL_H)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE_PAD, -yPos)
        row:EnableMouse(true)

        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.07, 0.07, 0.10, 0.85)

        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.15)

        -- Indent + class-colored character name
        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        nameFS:SetPoint("LEFT", row, "LEFT", 28, 0)
        nameFS:SetWidth(NAME_COL_W - 28)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        nameFS:SetText("|cff" .. hex .. (charName or char.charKey) .. "|r")

        -- Per-boss kill dots for THIS character
        local roster = char.encounters or {}
        local total = #roster
        local k = char.killed or 0
        local heatX = NAME_COL_W + 10
        local heatRight = rowW - STATS_COL_W - 30
        local heatW = math.max(40, heatRight - heatX)
        if total > 0 then
            local size = math.max(8, math.min(12, math.floor((heatW - (total - 1) * 2) / total)))
            local gap = math.max(2, math.floor((heatW - total * size) / math.max(1, total - 1)))
            for i, e in ipairs(roster) do
                local dot = row:CreateTexture(nil, "ARTWORK")
                dot:SetSize(size, size)
                dot:SetPoint("LEFT", row, "LEFT", heatX + (i - 1) * (size + gap), 0)
                if e.killed then
                    dot:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)
                else
                    dot:SetColorTexture(0.18, 0.18, 0.22, 1)
                end
            end
        end

        -- Progress text
        local progressColor = (total > 0 and k >= total) and "|cff44ff44" or "|cffd4af37"
        local progFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        progFS:SetPoint("RIGHT", row, "RIGHT", -90, 0)
        progFS:SetWidth(60)
        progFS:SetJustifyH("RIGHT")
        progFS:SetText(string.format("%s%d/%d|r", progressColor, k, total))

        -- Reset countdown
        local resetFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        resetFS:SetPoint("RIGHT", row, "RIGHT", -32, 0)
        resetFS:SetWidth(50)
        resetFS:SetJustifyH("RIGHT")
        resetFS:SetTextColor(0.55, 0.55, 0.6)
        if char.reset and char.reset > 0 then
            local h = math.floor(char.reset / 3600)
            local d = math.floor(h / 24)
            if d > 0 then resetFS:SetText(d .. "d " .. (h % 24) .. "h")
            elseif h > 0 then resetFS:SetText(h .. "h")
            else resetFS:SetText("<1h") end
        end

        row:SetScript("OnEnter", function(self)
            local lines = {
                { text = g.instanceName .. " — |cff" .. diffInfo.hex .. (g.difficultyName or diffInfo.name) .. "|r" },
                { text = " " },
            }
            for bi, e in ipairs(roster) do
                local mark = e.killed and "|cff44ff44" .. CHECK .. "|r" or "|cff444444" .. CROSS .. "|r"
                lines[#lines + 1] = {
                    left = mark .. " " .. (e.name or ("Boss " .. bi)),
                    right = e.killed and "|cff44ff44killed|r" or "|cff666666—|r",
                    leftColor = {1, 1, 1}, rightColor = {0.85, 0.85, 0.85}
                }
            end
            WNTooltipShow(self, {
                type = "custom",
                title = "|cff" .. hex .. (charName or char.charKey) .. "|r",
                lines = lines,
                anchor = "ANCHOR_RIGHT",
            })
        end)
        row:SetScript("OnLeave", function() WNTooltipHide() end)

        return row
    end

    -- Build distinct char count for summary
    local seen, charKeys = {}, {}
    for _, g in ipairs(filtered) do
        for _, c in ipairs(g.characters) do
            if not seen[c.charKey] then
                seen[c.charKey] = true
                charKeys[#charKeys + 1] = c.charKey
            end
        end
    end
    if S.savedFrame and S.savedFrame.summary then
        S.savedFrame.summary:SetText(string.format("%d instances · %d characters", #filtered, #charKeys))
    end

    -- Render
    local y = 0
    for idx, g in ipairs(filtered) do
        local summaryRow = BuildSummaryRow(g, idx, y)
        table.insert(S.savedRows, summaryRow)
        y = y + SUMMARY_H + 1

        if S.savedExpanded[MakeGroupKey(g)] then
            for _, char in ipairs(g.characters) do
                local detailRow = BuildDetailRow(g, char, y)
                table.insert(S.savedRows, detailRow)
                y = y + DETAIL_H + 1
            end
            y = y + 4  -- breathing room after expanded block
        end
    end

    content:SetHeight(math.max(40, y))
    S.savedScroll:SetVerticalScroll(0)
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
        { label = "Plans / Todo",    icon = "Interface\\Icons\\INV_Inscription_Scroll", action = function()
            if WarbandNexus and WarbandNexus.TogglePlansTrackerWindow then
                if InCombatLockdown and InCombatLockdown() then return end
                WarbandNexus:TogglePlansTrackerWindow()
            end
        end },
        { label = "Settings",        icon = "Interface\\Icons\\Trade_Engineering",      action = function()
            HideMenu(); ToggleOptionsFrame(S.button, "RIGHT")
        end },
    }

    local W = 210
    local rowH = 30
    local headerH = 26
    local pad = 6
    local H = headerH + (#items * (rowH + 2)) + pad + 2

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

    -- Header bar (matches main chrome style)
    local header = CreateFrame("Frame", nil, f)
    header:SetHeight(headerH)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 2, -2)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)
    if ApplyVisuals then
        ApplyVisuals(header, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end

    local headerIcon = header:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(16, 16)
    headerIcon:SetPoint("LEFT", 8, 0)
    headerIcon:SetTexture(ICON_TEXTURE)
    if not headerIcon:GetTexture() then headerIcon:SetTexture(ICON_FALLBACK) end
    headerIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

    local FontManager = ns.FontManager
    local titleFS
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        titleFS = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        titleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    end
    titleFS:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)
    titleFS:SetText("WN Menu")
    titleFS:SetTextColor(1, 1, 1)

    local y = -(headerH + 4)
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

ToggleMenu = function(anchor)
    BuildMenu()
    if not S.menuFrame then return end
    if S.menuFrame:IsShown() then
        S.menuFrame:Hide()
        return
    end
    anchor = anchor or S.button
    S.menuFrame:ClearAllPoints()
    if anchor then
        -- Anchor menu beside the button (never on top of it). Pick the side with the most room.
        local mw = S.menuFrame:GetWidth() or 200
        local mh = S.menuFrame:GetHeight() or 200
        local screenW = UIParent:GetWidth() or 1920
        local screenH = UIParent:GetHeight() or 1080
        local left   = anchor:GetLeft()   or 0
        local right  = anchor:GetRight()  or 0
        local top    = anchor:GetTop()    or 0
        local bottom = anchor:GetBottom() or 0
        local roomLeft   = left
        local roomRight  = screenW - right
        local roomTop    = screenH - top
        local roomBottom = bottom
        local gap = 6

        -- Prefer horizontal placement (looks more like a context menu)
        if roomRight >= mw + gap then
            -- Place to the RIGHT of the button
            local dy = (top - mh < 0) and (mh - (top - bottom)) or 0
            S.menuFrame:SetPoint("TOPLEFT", anchor, "TOPRIGHT", gap, dy)
        elseif roomLeft >= mw + gap then
            -- Place to the LEFT of the button
            local dy = (top - mh < 0) and (mh - (top - bottom)) or 0
            S.menuFrame:SetPoint("TOPRIGHT", anchor, "TOPLEFT", -gap, dy)
        elseif roomBottom >= mh + gap then
            -- Place BELOW the button
            S.menuFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -gap)
        else
            -- Place ABOVE the button
            S.menuFrame:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, gap)
        end
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

    -- Pixel-perfect 1px accent border via the addon's standard visual system,
    -- so the icon fills the whole button instead of looking like "frame in frame".
    local ApplyVisuals = ns.UI_ApplyVisuals
    local btnAccent = (ns.UI_COLORS and ns.UI_COLORS.accent) or {0.40, 0.20, 0.58}
    if ApplyVisuals then
        ApplyVisuals(btn, {0,0,0,0}, {btnAccent[1], btnAccent[2], btnAccent[3], 0.9})
    else
        btn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        btn:SetBackdropColor(0,0,0,0)
    end
    S.border = btn  -- backwards-compat: ApplyTheme refers to S.border for accent updates

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     btn, "TOPLEFT",     1, -1)
    icon:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT", -1, 1)
    icon:SetTexture(ICON_TEXTURE)
    if not icon:GetTexture() then
        icon:SetTexture(ICON_FALLBACK)
    end
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)  -- trim default texture bezel
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

    -- Polled hover detection (OnEnter/OnLeave can flicker when alpha=0 with hideUntilMouseover,
    -- and Blizzard mouse events don't always fire reliably for low-alpha frames). Throttled to
    -- 100ms to keep cost trivial.
    btn._hoverPoll = 0
    btn._hovering  = false
    btn:SetScript("OnUpdate", function(self, elapsed)
        self._hoverPoll = (self._hoverPoll or 0) + elapsed
        if self._hoverPoll < 0.1 then return end
        self._hoverPoll = 0
        local over = self:IsMouseOver() and self:IsVisible()
        if over ~= self._hovering then
            self._hovering = over
            if over then
                ApplyButtonVisibility(true)
                ShowHoverTooltip(self)
            else
                WNTooltipHide()
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                ApplyButtonVisibility(false)
            end
        end
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
            ToggleMenu(self)
        else
            HideMenu()
            ToggleMainWindow()
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
