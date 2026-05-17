--[[
    WarbandNexus - Vault Ready Button
    Draggable button showing Great Vault status across all characters.
    - Hover: compact list of ready/pending characters
    - Click: full table view (Name | iLvl | Raid | Dungeon | World | Status)
    - Row hover: tooltip showing iLvl reward per vault slot
]]

local ADDON_NAME, ns = ...
local WarbandNexus = ns.WarbandNexus

--[[ WN_FACTORY: Loads before `Modules/UI/SharedWidgets.lua` in `WarbandNexus.toc`.
     Never read `ns.UI.Factory` at chunk load — it appears after SharedWidgets runs.
     All `ns.UI.Factory` / `VF` usages are inside button/table/menu construction paths (runtime).

     Intentionally raw CreateFrame highlights: vault root dialogs (BackdropTemplate + global names),
     Blizzard `CheckButton` fallback when themed checkbox is absent, event coalescing frames,
     resize grip (Blizzard size grabber textures), Saved group header as full-surface `Button`,
     lockout row inner highlights, main floating vault `WarbandNexusVaultButton`.]]

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
local ICON_TEXTURE  = ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga"
local ICON_FALLBACK = "Interface\\Icons\\INV_Misc_TreasureChest02"
local VOIDCORE_ID   = 3418
local MANAFLUX_ID   = 3378
local BOUNTY_ITEM_ID = 252415

local COL_NAME      = 140
local COL_ILVL      = 50
local COL_RAID      = 72
local COL_DUNGEON   = 72
local COL_WORLD     = 72
local COL_REWARD_ILVL = 106
local COL_PROGRESS  = 108
local COL_REWARD_PROGRESS = 144
local COL_BOUNTY    = 46   -- Trovehunter's Bounty (done/not)
local COL_VOIDCORE  = 58   -- Nebulous Voidcore (current/seasonMax)
local COL_MANAFLUX  = 58   -- Dawnlight Manaflux (current held)
local COL_STASH     = 58   -- Gilded Stashes (current/max)
local COL_STATUS    = 110

local TRACK_ICONS = {
    raids      = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    mythicPlus = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
    world      = "Interface\\Icons\\INV_Misc_Map_01",
    bounty     = 1064187,
    voidcore   = 7658128,
    manaflux   = "Interface\\Icons\\INV_Enchant_DustArcane",
    gildedStash = "Interface\\Icons\\Inv_cape_special_treasure_c_01",
}

local CHECK  = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local CROSS  = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
local UPARROW = "|A:loottoast-arrow-green:12:12|a"

--- VaultTracker font helper: routes through FontManager when available, falls back
--- to GameFontNormal[Small] otherwise. Call sites use one of: "body" | "small" | "title" | "subtitle" | "header".
local function VBFontString(parent, role, drawLayer)
    local FM = ns.FontManager
    if FM and FM.CreateFontString then
        return FM:CreateFontString(parent, role or "body", drawLayer or "OVERLAY")
    end
    local fallback = (role == "small") and "GameFontNormalSmall"
        or (role == "title" or role == "header") and "GameFontHighlight"
        or "GameFontNormal"
    return parent:CreateFontString(nil, drawLayer or "OVERLAY", fallback)
end

--- Matches `MAIN_SHELL` in Modules/UI/SharedWidgets.lua (`ns.UI_LAYOUT` is nil until that file loads; safe at runtime when frames build).
local function VBGetFrameContentInset()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.FRAME_CONTENT_INSET or 2
end

--- Aligns draggable chrome band height with main window header (`HEADER_BAR_HEIGHT`; fallback preserves legacy CHROME_H).
local function VBGetChromeBandHeight()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.HEADER_BAR_HEIGHT or CHROME_H
end

--- Draggable chrome band inside backdrop inner edge (`FRAME_CONTENT_INSET`).
---@return number bandHeight for stacking header rows below the band.
local function VBAnchorChromeBandTop(chrome, parentFrame)
    local inset = VBGetFrameContentInset()
    local h = VBGetChromeBandHeight()
    chrome:SetHeight(h)
    chrome:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", inset, -inset)
    chrome:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -inset, -inset)
    return h
end

--- Full-width row below chrome (`FRAME_CONTENT_INSET` horizontally); adds `belowYOffset` beyond chrome band height.
local function VBAnchorFullWidthRowBelowChrome(row, rootFrame, chromeBandHeight, belowYOffset)
    local inset = VBGetFrameContentInset()
    local y = -(chromeBandHeight + (belowYOffset or 0))
    row:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", inset, y)
    row:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", -inset, y)
end

local DASH   = "|cff888888-|r"

-- Maps Easy Access column key -> PvE typeName used by upgrade-detection logic
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
        bg = {0.04, 0.04, 0.05, 0.98},
        bgCard = {0.04, 0.04, 0.05, 0.98},
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
            showRewardProgress = false,
            showManaflux = false,
            showSummaryOnMouseover = false,
            leftClickAction = "pve",
            includeBountyOnly = false,
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
    if settings.showRewardProgress == nil then settings.showRewardProgress = false end
    if settings.showManaflux == nil then settings.showManaflux = false end
    if settings.showSummaryOnMouseover == nil then settings.showSummaryOnMouseover = false end
    if settings.leftClickAction == nil and settings.leftClickQuickView == true then settings.leftClickAction = "vault" end
    local allowedLeftClick = { pve = true, vault = true, saved = true, plans = true, chars = true }
    if not allowedLeftClick[settings.leftClickAction] then
        settings.leftClickAction = "pve"
    end
    if settings.includeBountyOnly == nil then settings.includeBountyOnly = false end
    settings.columns = settings.columns or {}
    if settings.columns.raids == nil then settings.columns.raids = true end
    if settings.columns.mythicPlus == nil then settings.columns.mythicPlus = true end
    if settings.columns.world == nil then settings.columns.world = true end
    if settings.columns.bounty == nil then settings.columns.bounty = true end
    if settings.columns.voidcore == nil then settings.columns.voidcore = true end
    if settings.columns.manaflux == nil then settings.columns.manaflux = settings.showManaflux == true end
    if settings.columns.gildedStash == nil then settings.columns.gildedStash = false end
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
    local width = settings.showRewardProgress and settings.showRewardItemLevel and COL_REWARD_PROGRESS
        or (settings.showRewardProgress and COL_PROGRESS)
        or (settings.showRewardItemLevel and COL_REWARD_ILVL or nil)
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
    if columns.gildedStash == true then optionalWidth = optionalWidth + COL_STASH end
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
    local CS = ns.CharacterService
    if CS and CS.ResolveSubsidiaryCharacterKey and WarbandNexus then
        local k = CS:ResolveSubsidiaryCharacterKey(WarbandNexus, nil)
        if k then return k end
    end
    local raw = ns.Utilities.GetCharacterStorageKey and ns.Utilities:GetCharacterStorageKey(WarbandNexus)
        or (ns.Utilities.GetCharacterKey and ns.Utilities:GetCharacterKey())
    if not raw then return nil end
    if ns.Utilities.GetCanonicalCharacterKey then
        return ns.Utilities:GetCanonicalCharacterKey(raw) or raw
    end
    return raw
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
    -- isPostReset means data is from last week — treat as no this-week progress
    if acts.isPostReset then return false end
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
    -- isPostReset means data is from last week — show empty slots for this week
    local cat  = (acts and not acts.isPostReset) and acts[category] or {}
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

--- True if `time()` has crossed the stored weeklyResetTime for this char's activities,
--- meaning the cached "ready slots" are now sitting unclaimed in the vault chest.
local function VaultResetCrossedFor(charKey)
    local pveCache = GetPveCache()
    local activities = pveCache and pveCache.greatVault and pveCache.greatVault.activities
        and pveCache.greatVault.activities[charKey] or nil
    if not activities then return false end
    local resetT = tonumber(activities.weeklyResetTime) or 0
    if resetT <= 0 then return false end
    local rewards = pveCache and pveCache.greatVault and pveCache.greatVault.rewards
    local rewardData = rewards and rewards[charKey]
    local claimedResetTime = rewardData and tonumber(rewardData.claimedResetTime) or nil
    if claimedResetTime and claimedResetTime >= resetT then
        return false
    end
    return GetServerTime() >= resetT
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

local function GetGildedStashData(charKey)
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    local delveChar = pveCache.delves and pveCache.delves.characters
        and pveCache.delves.characters[charKey]
    if not delveChar then return nil end
    local current = tonumber(delveChar.gildedStashes)
    if current == nil then return nil end
    return {
        current = current,
        max = tonumber(delveChar.gildedStashesMax) or 4,
        unknown = current < 0,
    }
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
    if not ok or not cd then
        local currencyData = WarbandNexus.db and WarbandNexus.db.global and WarbandNexus.db.global.currencyData
        local stored = currencyData and currencyData.currencies and currencyData.currencies[charKey]
            and currencyData.currencies[charKey][MANAFLUX_ID]
        if type(stored) == "table" then stored = stored.quantity end
        local quantity = tonumber(stored)
        if quantity == nil then return nil end
        return { quantity = quantity, totalEarned = 0 }
    end
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
            -- ShowMainWindow arms a short input grace so the open click cannot hit another tab; allow this scripted switch.
            mf._wnBypassMainTabInputGraceOnce = true
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

local function OpenWNCharsTab() OpenWNTab("chars") end

local function ToggleWNCharsTab()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    local mf = WarbandNexus and WarbandNexus.mainFrame
    if mf and mf:IsShown() and mf.currentTab == "chars" then
        mf:Hide()
        return
    end
    OpenWNCharsTab()
end

local function ToggleWNPveTab()
    if InCombatLockdown and InCombatLockdown() then
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff4040Warband Nexus:|r main window is locked during combat.")
        end
        return
    end
    local mf = WarbandNexus and WarbandNexus.mainFrame
    if mf and mf:IsShown() and mf.currentTab == "pve" then
        mf:Hide()
        return
    end
    OpenWNPveTab()
end

local function OpenWNSettingsTab()
    if WarbandNexus and WarbandNexus.OpenOptions then
        WarbandNexus:OpenOptions()
    else
        OpenWNTab("settings")
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
    local progress, nextThreshold, maxThreshold = 0, nil, 0
    for i = 1, 3 do
        local slot = slots[i]
        progress = math.max(progress, tonumber(slot.progress) or 0)
        maxThreshold = math.max(maxThreshold, tonumber(slot.threshold) or 0)
        if not slot.complete and slot.threshold and slot.threshold > 0 and (not nextThreshold or slot.threshold < nextThreshold) then
            nextThreshold = slot.threshold
        end
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
    local text = table.concat(parts, " ")
    if settings.showRewardProgress then
        local target = nextThreshold or maxThreshold
        if target and target > 0 then
            text = text .. " |cffaaaaaa(" .. math.min(progress, target) .. "/" .. target .. ")|r"
        end
    end
    return text
end

local function BuildCharList()
    local pveCache   = GetPveCache()
    local characters = GetCharacters()
    if not pveCache or not characters then return {} end
    local rewards    = pveCache.greatVault and pveCache.greatVault.rewards
    local currentKey = GetCurrentCharKey()
    local settings   = GetSettings()
    local result     = {}
    -- For the logged-in char, prefer live HasAvailableRewards() so post-reset carry-over
    -- chests flip the Ready badge immediately (matches the Great Vault\226\128\153s own prompt).
    local liveCurrentReady = false
    if currentKey and C_WeeklyRewards and C_WeeklyRewards.HasAvailableRewards
        and C_WeeklyRewards.HasAvailableRewards() then
        liveCurrentReady = true
    end
    for charKey, charData in pairs(characters) do
        local rewardData = rewards and rewards[charKey]
        local isReady    = rewardData and rewardData.hasAvailableRewards or false
        if charKey == currentKey and liveCurrentReady then isReady = true end
        -- Alt auto-flip: cached \226\128\156slots earned\226\128\157 last week + reset crossed -> sitting chest.
        if not isReady and charKey ~= currentKey
            and (CountReadySlots(charKey) or 0) > 0
            and VaultResetCrossedFor(charKey) then
            isReady = true
        end
        local isPending  = not isReady and HasAnyProgress(charKey)
        local bounty = GetBountyStatus(charKey)
        if isReady or isPending or (settings.includeBountyOnly and bounty == true) then
            table.insert(result, {
                charKey   = charKey,
                name      = charData.name or charKey,
                realm     = charData.realm or "",
                classFile = charData.classFile or "WARRIOR",
                itemLevel = charData.itemLevel or 0,
                isReady   = isReady,
                isPending = isPending,
                isCurrent = (charKey == currentKey),
                bounty    = bounty,
                voidcore  = GetVoidcoreData(charKey),
                manaflux  = GetManafluxData(charKey),
                gildedStash = GetGildedStashData(charKey),
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
    menuFrame=nil, savedFrame=nil, savedRows={}, savedExpanded={}, savedInstanceCollapsed={},
    savedGroupCollapsed={},
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
local StartSavedInstancesLiveRefresh
local StopSavedInstancesLiveRefresh
local WNTooltipShow
local WNTooltipHide

local function ReleaseSavedInstanceRows()
    if not S.savedRows then
        S.savedRows = {}
        return
    end

    local bin = ns.UI_RecycleBin
    for i = 1, #S.savedRows do
        local row = S.savedRows[i]
        if row then
            if row.SetScript then
                pcall(row.SetScript, row, "OnClick", nil)
                pcall(row.SetScript, row, "OnEnter", nil)
                pcall(row.SetScript, row, "OnLeave", nil)
                pcall(row.SetScript, row, "OnMouseWheel", nil)
            end
            if row.Hide then pcall(row.Hide, row) end
            if row.ClearAllPoints then pcall(row.ClearAllPoints, row) end
            if row.SetParent then
                pcall(row.SetParent, row, bin or nil)
            end
        end
    end
    S.savedRows = {}
end

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
        local VF = ns.UI.Factory
        local readyCount = CountReady()
        local r, g, b, a
        if readyCount > 0 then
            r, g, b, a = accent[1], accent[2], accent[3], 1
        else
            r, g, b, a = border[1], border[2], border[3], 0.85
        end
        if VF and VF.UpdateBorderColor then
            VF:UpdateBorderColor(S.button, {r, g, b, a})
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
    -- Saved Instances rows/headers are rebuilt with current theme colors.
    if S.savedFrame and S.savedFrame:IsShown() and RefreshSavedInstances then
        RefreshSavedInstances()
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

HideMenu = function() 
    if S.menuFrame then S.menuFrame:Hide() end 
    if S.menuCatcher then S.menuCatcher:Hide() end
end
HideSavedInstances = function()
    if S.savedFrame then S.savedFrame:Hide() end
    StopSavedInstancesLiveRefresh()
end

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
    local VF = ns.UI.Factory

    local f = CreateFrame("Frame", "WarbandNexusVaultTable", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultTable")
    f:SetClampedToScreen(true)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(200)
    f:SetMovable(true)
    f:EnableMouse(true)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    elseif ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        f:SetBackdropColor(0.02, 0.02, 0.03, 0.98)
    end
    f:Hide()

    -- ===== CHROME HEADER (matches main window) =====
    local chrome = VF:CreateContainer(f, 32, 32, false)
    local chromeBandH = VBAnchorChromeBandTop(chrome, f)
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
        title = VBFontString(chrome, "body")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText("Vault Tracker")
    title:SetTextColor(1, 1, 1)
    S.title = title

    -- Close button (atlas style, matches main window)
    local closeBtn = VF:CreateButton(chrome, 28, 28, true)
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
    local settingsBtn = VF:CreateButton(chrome, 28, 28, true)
    settingsBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    settingsBtn:SetNormalAtlas("mechagon-projects")
    settingsBtn:SetHighlightTexture("Interface\\BUTTONS\\UI-Common-MouseHilight")
    settingsBtn:SetScript("OnClick", function() ToggleOptionsFrame(f, "RIGHT") end)

    -- Column header row
    local headerY = -(chromeBandH + 6)
    local hRow = VF:CreateContainer(f, tableW - FRAME_PAD * 2, HEADER_H, false)
    hRow:SetPoint("TOPLEFT", f, "TOPLEFT", FRAME_PAD, headerY)
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
                local hover = VF:CreateContainer(hRow, w, HEADER_H, false)
                hover:SetPoint("TOPLEFT", hRow, "TOPLEFT", x, 0)
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
            local fs = VBFontString(hRow, "small")
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
    if columns.gildedStash == true then
        HCell(nil,      hx, COL_STASH,   true,  TRACK_ICONS.gildedStash, "Gilded Stashes", "Weekly gilded stashes claimed.") ; hx = hx + COL_STASH
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

    -- Scroll (factory-styled scrollbar; matches Saved Instances / main UI)
    local scroll = VF:CreateScrollFrame(f, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",     FRAME_PAD, headerY - HEADER_H - 2)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -FRAME_PAD, FRAME_PAD)
    local content = VF:CreateContainer(scroll, tableW - FRAME_PAD * 2, 8, false)
    scroll:SetScrollChild(content)

    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(self, delta)
        local cur = scroll:GetVerticalScroll() or 0
        local maxY = math.max(0, (content:GetHeight() or 0) - (scroll:GetHeight() or 0))
        scroll:SetVerticalScroll(math.min(maxY, math.max(0, cur - delta * ROW_H * 2)))
    end)

    S.tableFrame   = f
    S.tableScroll  = scroll
    S.tableContent = content
    ApplyTheme()
end

RefreshTable = function()
    BuildTableFrame()
    local VF = ns.UI.Factory
    local tableW = GetTableWidth()
    local content = S.tableContent
    local list    = BuildCharList()

    for _, row in ipairs(S.rows) do row:Hide() end
    S.rows = {}

    if #list == 0 then
        S.tableFrame:SetSize(tableW, VBGetChromeBandHeight() + HEADER_H + 80)
        content:SetSize(tableW - FRAME_PAD*2, 40)
        local msg = VBFontString(content, "body")
        msg:SetPoint("CENTER", content, "CENTER")
        msg:SetTextColor(0.5, 0.5, 0.5)
        msg:SetText("No vault activity this week.")
        S.tableFrame:Show()
        local vf0 = ns.UI.Factory
        if vf0 and vf0.UpdateScrollBarVisibility and S.tableScroll then
            vf0:UpdateScrollBarVisibility(S.tableScroll)
        end
        return
    end

    local catDefs = GetEnabledCategoryDefs()
    local columns = GetSettings().columns or {}
    local colors = GetThemeColors()
    local accent = colors.accent or {0.40, 0.20, 0.58}

    for i, e in ipairs(list) do
        local row = VF:CreateContainer(content, tableW - FRAME_PAD * 2, ROW_H, false)
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
        local nameFS = VBFontString(row, "body")
        nameFS:SetPoint("TOPLEFT", row, "TOPLEFT", x+6, 0)
        nameFS:SetSize(COL_NAME-6, ROW_H)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetJustifyV("MIDDLE")
        nameFS:SetText(FormatCharacterName(e))
        x = x + COL_NAME

        -- iLvl
        local ilvlFS = VBFontString(row, "body")
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
            local fs = VBFontString(row, "body")
            fs:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            fs:SetSize(cat.width, ROW_H)
            fs:SetJustifyH("CENTER")
            fs:SetJustifyV("MIDDLE")
            fs:SetText(SlotSymbols(slots, cat.key))
            x = x + cat.width
        end

        local b = e.bounty
        if columns.bounty ~= false then
            local bountyFS = VBFontString(row, "body")
            bountyFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            bountyFS:SetSize(COL_BOUNTY, ROW_H)
            bountyFS:SetJustifyH("CENTER")
            bountyFS:SetJustifyV("MIDDLE")
            bountyFS:SetText(b == nil and DASH or (b and CHECK or CROSS))
            x = x + COL_BOUNTY
        end

        if columns.gildedStash == true then
            local stashFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            stashFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            stashFS:SetSize(COL_STASH, ROW_H)
            stashFS:SetJustifyH("CENTER")
            stashFS:SetJustifyV("MIDDLE")
            local stash = e.gildedStash
            if not stash then
                stashFS:SetText(DASH)
            elseif stash.unknown then
                stashFS:SetText("|cffaaaaaa?/|r|cffd4af37" .. (stash.max or 4) .. "|r")
            else
                local color = (stash.current or 0) >= (stash.max or 4) and "|cff44ff44" or "|cffd4af37"
                stashFS:SetText(color .. (stash.current or 0) .. "|r|cffaaaaaa/|r|cffd4af37" .. (stash.max or 4) .. "|r")
            end
            x = x + COL_STASH
        end

        -- Nebulous Voidcore (current / seasonMax)
        local vc = e.voidcore
        if columns.voidcore ~= false then
            local voidcoreFS = VBFontString(row, "body")
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
            local manafluxFS = VBFontString(row, "body")
            manafluxFS:SetPoint("TOPLEFT", row, "TOPLEFT", x, 0)
            manafluxFS:SetSize(COL_MANAFLUX, ROW_H)
            manafluxFS:SetJustifyH("CENTER")
            manafluxFS:SetJustifyV("MIDDLE")
            local mf = e.manaflux
            manafluxFS:SetText(mf and ("|cffd4af37" .. (mf.quantity or 0) .. "|r") or DASH)
            x = x + COL_MANAFLUX
        end

        -- Status
        local statusFS = VBFontString(row, "body")
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
            if columns.gildedStash == true then
                local stash = e.gildedStash
                if stash then
                    local stashLabel = stash.unknown and ("|cffaaaaaa?/" .. (stash.max or 4) .. "|r")
                        or ("|cffd4af37" .. (stash.current or 0) .. "/" .. (stash.max or 4) .. " claimed|r")
                    lines[#lines + 1] = {
                        left = "|T" .. TRACK_ICONS.gildedStash .. ":14:14:0:0|t Gilded Stashes",
                        right = stashLabel,
                        leftColor = {0.7, 0.7, 0.7}, rightColor = {1, 1, 1}
                    }
                end
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
    local totalH   = VBGetChromeBandHeight() + 6 + HEADER_H + 2 + viewH + FRAME_PAD

    content:SetSize(tableW - FRAME_PAD*2, contentH)
    S.tableFrame:SetSize(tableW, totalH)
    S.tableScroll:SetVerticalScroll(0)
    local vfTbl = ns.UI.Factory
    if vfTbl and vfTbl.UpdateScrollBarVisibility and S.tableScroll then
        vfTbl:UpdateScrollBarVisibility(S.tableScroll)
    end
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

local function ShowQuickView(anchor)
    HideAllPanels()
    RefreshTable()
    if S.tableFrame and (anchor or S.button) then
        anchor = anchor or S.button
        S.tableFrame:ClearAllPoints()
        local saved = GetSavedTablePos()
        if saved and saved.x and saved.y then
            S.tableFrame:SetPoint(saved.point or "CENTER", UIParent, saved.relativePoint or "CENTER", saved.x, saved.y)
        else
            S.tableFrame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
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
WNTooltipShow = function(anchor, data)
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

WNTooltipHide = function()
    if ns.UI_HideTooltip then ns.UI_HideTooltip() else GameTooltip:Hide() end
end

-- ============================================================================
-- Hover tooltip (current character only)
-- ============================================================================
local function ShowHoverTooltip(anchor)
    if GetSettings().showSummaryOnMouseover then
        local list = BuildCharList()
        local readyN, pendingN = 0, 0
        local lines = {}
        if #list == 0 then
            lines[#lines + 1] = { text = "No vault activity this week.", color = {0.5, 0.5, 0.5} }
        else
            for _, e in ipairs(list) do
                local bountyOnly = GetSettings().includeBountyOnly == true and e.bounty == true and (e.slots or 0) == 0 and not e.isReady
                if e.isReady then readyN = readyN + 1 elseif not bountyOnly then pendingN = pendingN + 1 end
                local status = e.isReady and "|cff33dd33[Ready]|r" or (bountyOnly and "|cff33dd33[Bounty Only]|r" or "|cff66ddff[Earned]|r")
                local slotStr = e.slots > 0
                    and (" |cffaaaaaa("..e.slots.." slot"..(e.slots==1 and "" or "s")..")|r")
                    or ""
                lines[#lines + 1] = { left = FormatCharacterName(e), right = status..slotStr, leftColor = {1,1,1}, rightColor = {1,1,1} }
            end
            lines[#lines + 1] = { text = " " }
            if readyN   > 0 then lines[#lines + 1] = { text = readyN .. " ready to claim", color = {0.2, 1.0, 0.3} } end
            if pendingN > 0 then lines[#lines + 1] = { text = pendingN .. " in progress / tracked", color = {1.0, 1.0, 0.2} } end
        end
        lines[#lines + 1] = { text = " " }
        lines[#lines + 1] = { text = "|cff888888[Left-click] Action  [Right-click] Menu  [Drag] Move|r" }
        WNTooltipShow(anchor, {
            type = "custom",
            title = "Warband Nexus Vault Tracker",
            icon = ICON_TEXTURE,
            lines = lines,
            anchor = "ANCHOR_RIGHT",
        })
        return
    end
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

        local currentColumns = GetSettings().columns or {}
        if currentColumns.gildedStash == true then
            local stash = GetGildedStashData(charKey)
            if stash then
                local stashLabel = stash.unknown and ("|cffaaaaaa?/" .. (stash.max or 4) .. "|r")
                    or ("|cffd4af37" .. (stash.current or 0) .. "/" .. (stash.max or 4) .. " claimed|r")
                GameTooltip:AddDoubleLine("|T" .. TRACK_ICONS.gildedStash .. ":14:14:0:0|t |cffaaaaaaGilded Stashes|r", stashLabel, 0.7,0.7,0.7, 1,1,1)
            end
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
    lines[#lines + 1] = { text = "|cff888888[Left-click] Action  [Right-click] Menu  [Drag] Move|r" }

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
local function CreateMenuCheckbox(parent, labelText, y, getValue, setValue, tooltipText)
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
        label = VBFontString(parent, "small")
    end
    label:SetPoint("LEFT", cb, "RIGHT", (ns.UI_SPACING and ns.UI_SPACING.AFTER_ELEMENT) or 6, 0)
    label:SetText(labelText)
    label:SetTextColor(1, 1, 1, 1)
    label:SetJustifyH("LEFT")

    if tooltipText and tooltipText ~= "" then
        local function ShowTooltip(owner)
            GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
            GameTooltip:ClearLines()
            GameTooltip:AddLine(labelText, 1, 1, 1)
            GameTooltip:AddLine(tooltipText, 0.85, 0.85, 0.85, true)
            GameTooltip:Show()
        end
        cb:SetScript("OnEnter", ShowTooltip)
        cb:SetScript("OnLeave", function() GameTooltip:Hide() end)
        label:EnableMouse(true)
        label:SetScript("OnEnter", ShowTooltip)
        label:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

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
    local VF = ns.UI.Factory

    local f = CreateFrame("Frame", "WarbandNexusVaultButtonOptions", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusVaultButtonOptions")
    f:SetSize(286, 372)
    f:SetFrameStrata("DIALOG")
    f:SetFrameLevel(210)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:SetMovable(true)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    elseif ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        f:SetBackdropColor(0.02, 0.02, 0.03, 0.98)
    end
    f:Hide()

    -- Chrome header
    local chrome = VF:CreateContainer(f, 32, 32, false)
    VBAnchorChromeBandTop(chrome, f)
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
        title = VBFontString(chrome, "body")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText("Vault Tracker")
    title:SetTextColor(1, 1, 1)
    f.title = title

    local close = VF:CreateButton(chrome, 28, 28, true)
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

    CreateMenuCheckbox(f, "Show Realm Names", -52,
        function() return GetSettings().showRealmName == true end,
        function(value)
            GetSettings().showRealmName = value
            if S.tableFrame and S.tableFrame:IsShown() then RefreshTable() end
        end)
    CreateMenuCheckbox(f, "Show Reward iLvl", -78,
        function() return GetSettings().showRewardItemLevel == true end,
        function(value)
            GetSettings().showRewardItemLevel = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Show Reward Progress", -104,
        function() return GetSettings().showRewardProgress == true end,
        function(value)
            GetSettings().showRewardProgress = value
            RebuildTableFrame()
        end,
        "Show current progress toward the next vault reward threshold.")
    CreateMenuCheckbox(f, "Include Delver's Bounty", -130,
        function() return GetSettings().includeBountyOnly == true end,
        function(value)
            GetSettings().includeBountyOnly = value
            RebuildTableFrame()
        end,
        "Also show characters that have only looted a Delver's Bounty.")
    local columnLabel = VBFontString(f, "small")
    columnLabel:SetPoint("TOPLEFT", f, "TOPLEFT", 14, -168)
    columnLabel:SetText("Columns")
    columnLabel:SetTextColor(accent[1], accent[2], accent[3], 1)
    f.columnLabel = columnLabel

    CreateMenuCheckbox(f, "Raid", -188,
        function() return GetSettings().columns.raids ~= false end,
        function(value)
            GetSettings().columns.raids = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dungeon", -214,
        function() return GetSettings().columns.mythicPlus ~= false end,
        function(value)
            GetSettings().columns.mythicPlus = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "World", -240,
        function() return GetSettings().columns.world ~= false end,
        function(value)
            GetSettings().columns.world = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Trovehunter's Bounty", -266,
        function() return GetSettings().columns.bounty ~= false end,
        function(value)
            GetSettings().columns.bounty = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Gilded Stashes", -292,
        function() return GetSettings().columns.gildedStash == true end,
        function(value)
            GetSettings().columns.gildedStash = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Nebulous Voidcore", -318,
        function() return GetSettings().columns.voidcore ~= false end,
        function(value)
            GetSettings().columns.voidcore = value
            RebuildTableFrame()
        end)
    CreateMenuCheckbox(f, "Dawnlight Manaflux", -344,
        function() return GetSettings().columns.manaflux == true end,
        function(value)
            GetSettings().columns.manaflux = value
            GetSettings().showManaflux = value
            RebuildTableFrame()
        end)
    f.RefreshValues = function()
        S.refreshingOptions = true
        for _, widget in ipairs(S.optionsWidgets) do
            if widget and widget.RefreshValue then
                widget:RefreshValue()
            end
        end
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
-- Saved Instances (raid + dungeon lockouts)
-- ============================================================================
local DIFF_INFO = {
    [17] = { short = "LFR",    name = "Looking For Raid", color = {0.55, 0.55, 0.55}, hex = "aaaaaa" },
    [14] = { short = "N",      name = "Normal",           color = {0.12, 0.78, 0.12}, hex = "1eff00" },
    [15] = { short = "H",      name = "Heroic",           color = {0.00, 0.44, 0.87}, hex = "0070dd" },
    [16] = { short = "M",      name = "Mythic",           color = {0.64, 0.21, 0.93}, hex = "a335ee" },
    -- 5-player saved instances (GetSavedInstanceInfo difficultyID)
    [1]  = { short = "N",      name = "Normal",           color = {0.12, 0.78, 0.12}, hex = "1eff00" },
    [2]  = { short = "H",      name = "Heroic",           color = {0.00, 0.44, 0.87}, hex = "0070dd" },
    [23] = { short = "M",      name = "Mythic",           color = {0.64, 0.21, 0.93}, hex = "a335ee" },
    [8]  = { short = "M+",     name = "Mythic Keystone",  color = {0.90, 0.45, 0.10}, hex = "ff8000" },
}
local FALLBACK_DIFF = { short = "?", name = "Unknown", color = {0.4, 0.4, 0.4}, hex = "aaaaaa" }
local DIFFICULTY_ORDER_DESC = { 16, 15, 14, 17 }  -- Mythic > Heroic > Normal > LFR
-- Sort priority for the Saved Instances grid: LFR first, then N, H, M (dungeons align to same tiers)
local DIFF_SORT_RANK = { [17] = 1, [14] = 2, [1] = 2, [15] = 3, [2] = 3, [16] = 4, [23] = 4, [8] = 5 }

local function GetDiffInfo(difficulty)
    return DIFF_INFO[difficulty] or FALLBACK_DIFF
end

local function GetClassHexFromCharacters(charKey)
    local chars = GetCharacters()
    local entry = chars and chars[charKey]
    return GetClassHex(entry and entry.classFile), entry and entry.name or charKey
end

---Saved lockout rows must carry resetAt (absolute server time); never show expired or unknown-age rows.
local function IsSavedLockoutRowActive(inst, nowS)
    if not inst or type(nowS) ~= "number" then return false end
    local ra = inst.resetAt
    if type(ra) ~= "number" then return false end
    if issecretvalue and issecretvalue(ra) then return false end
    return ra > nowS
end

local function BuildSavedInstancesData()
    local pveCache = GetPveCache()
    local lo = pveCache and pveCache.lockouts
    if not lo then return {} end
    local raidLockouts = lo.raids
    local dungeonLockouts = lo.dungeons

    -- Group by (instanceName + difficultyName) -> list of {charKey, killed, total}
    local nowServer = (GetServerTime and GetServerTime()) or time()
    local groups = {}

    local function AccumulateLockoutBranch(lockoutsByChar)
        if not lockoutsByChar or type(lockoutsByChar) ~= "table" then return end
        for charKey, instances in pairs(lockoutsByChar) do
            if type(instances) == "table" then
                for _, inst in pairs(instances) do
                    if inst and inst.name and IsSavedLockoutRowActive(inst, nowServer) then
                        local diffName = inst.difficultyName or "Unknown"
                        local key = inst.name .. "||" .. diffName
                        local g = groups[key]
                        if not g then
                            g = {
                                instanceName = inst.name,
                                difficultyName = diffName,
                                difficulty = inst.difficulty,
                                instanceID = inst.instanceID,
                                characters = {},
                            }
                            groups[key] = g
                        elseif (not g.instanceID) and inst.instanceID then
                            g.instanceID = inst.instanceID
                        end
                        local total = tonumber(inst.numEncounters) or (inst.encounters and #inst.encounters) or 0
                        local killed = tonumber(inst.encounterProgress) or 0
                        if killed == 0 and inst.encounters then
                            for ei = 1, #inst.encounters do
                                local e = inst.encounters[ei]
                                if e and e.killed then killed = killed + 1 end
                            end
                        end
                        g.characters[#g.characters + 1] = {
                            charKey = charKey,
                            killed = killed,
                            total = total,
                            reset = (function()
                                local now = (GetServerTime and GetServerTime()) or time()
                                if inst.resetAt and inst.resetAt > now then
                                    return inst.resetAt - now
                                elseif inst.resetAt and inst.resetAt <= now then
                                    return 0
                                end
                                return inst.reset
                            end)(),
                            encounters = inst.encounters,
                        }
                    end
                end
            end
        end
    end

    AccumulateLockoutBranch(raidLockouts)
    AccumulateLockoutBranch(dungeonLockouts)

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
local SAVED_CARD_BASE = 190
local SAVED_CARD_MIN = 152
local SAVED_CARD_MAX = 240
local CARD_GAP = 10
local SAVED_GROUP_CHEVRON_SIZE = 20
local SAVED_GROUP_PROGRESS_W = 62

local savedLiveEventFrame = nil
local savedLiveRefreshPending = false

local function ScheduleSavedInstancesLiveRefresh(triggerPvEUpdate)
    if triggerPvEUpdate and WarbandNexus and WarbandNexus.UpdatePvEData then
        pcall(WarbandNexus.UpdatePvEData, WarbandNexus)
    end
    if RequestRaidInfo then
        pcall(RequestRaidInfo)
    end
    if savedLiveRefreshPending then return end
    savedLiveRefreshPending = true
    C_Timer.After(0.12, function()
        savedLiveRefreshPending = false
        if S.savedFrame and S.savedFrame:IsShown() then
            RefreshSavedInstances()
        end
    end)
end

StartSavedInstancesLiveRefresh = function()
    if savedLiveEventFrame then return end
    savedLiveEventFrame = CreateFrame("Frame")
    savedLiveEventFrame:RegisterEvent("UPDATE_INSTANCE_INFO")
    savedLiveEventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    savedLiveEventFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED")
    savedLiveEventFrame:RegisterEvent("RAID_INSTANCE_WELCOME")
    savedLiveEventFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
    savedLiveEventFrame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
    savedLiveEventFrame:RegisterEvent("ENCOUNTER_END")
    savedLiveEventFrame:SetScript("OnEvent", function(_, event)
        if not (S.savedFrame and S.savedFrame:IsShown()) then return end
        if event == "ENCOUNTER_END" then
            -- Encounter end can race cache writes; small delay keeps list accurate.
            C_Timer.After(0.2, function()
                if S.savedFrame and S.savedFrame:IsShown() then
                    ScheduleSavedInstancesLiveRefresh(true)
                end
            end)
            return
        end
        ScheduleSavedInstancesLiveRefresh(true)
    end)
end

StopSavedInstancesLiveRefresh = function()
    if not savedLiveEventFrame then return end
    savedLiveEventFrame:SetScript("OnEvent", nil)
    savedLiveEventFrame:UnregisterAllEvents()
    savedLiveEventFrame = nil
    savedLiveRefreshPending = false
end

local function BuildSavedInstancesFrame()
    if S.savedFrame then return end
    local ApplyVisuals = ns.UI_ApplyVisuals
    local COLORS = ns.UI_COLORS or {}
    local accent = COLORS.accent or {0.40, 0.20, 0.58}
    local accentDark = COLORS.accentDark or {0.28, 0.14, 0.41}
    local VF = ns.UI.Factory

    local f = CreateFrame("Frame", "WarbandNexusSavedInstances", UIParent, "BackdropTemplate")
    AddEscCloseFrame("WarbandNexusSavedInstances")
    f:SetSize(SAVED_FRAME_W, 480)
    f:SetClampedToScreen(true)
    -- Above normal panels/menus; still below world map full-screen if any.
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(100)
    f:SetMovable(true)
    f:SetResizable(true)
    if f.SetResizeBounds then
        f:SetResizeBounds(560, 420, 1200, 920)
    else
        f:SetMinResize(560, 420)
    end
    f:EnableMouse(true)
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    elseif ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    end
    f:Hide()
    f:SetScript("OnShow", function()
        StartSavedInstancesLiveRefresh()
        ScheduleSavedInstancesLiveRefresh(true)
    end)
    f:SetScript("OnHide", function()
        StopSavedInstancesLiveRefresh()
        ReleaseSavedInstanceRows()
    end)

    local chrome = VF:CreateContainer(f, 32, 32, false)
    local chromeBandH = VBAnchorChromeBandTop(chrome, f)
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
        title = VBFontString(chrome, "body")
    end
    title:SetPoint("LEFT", titleIcon, "RIGHT", 8, 0)
    title:SetText((ns.L and ns.L["SAVED_INSTANCES_TITLE"]) or "Saved Instances")
    title:SetTextColor(1, 1, 1)

    local close = VF:CreateButton(chrome, 28, 28, true)
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
    VBAnchorFullWidthRowBelowChrome(filterRow, f, chromeBandH, 4)
    if ApplyVisuals then
        ApplyVisuals(filterRow, {0.06, 0.06, 0.08, 1}, {accent[1], accent[2], accent[3], 0.4})
    end

    S.savedFilters = { lfr = true, normal = true, heroic = true, mythic = true }
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
        local lbl
        if FontManager and FontManager.CreateFontString then
            lbl = FontManager:CreateFontString(b, "small", "OVERLAY")
        else
            lbl = VBFontString(b, "small")
        end
        lbl:SetPoint("CENTER")
        lbl:SetText("|cff" .. di.hex .. fb.label .. "|r")
        b:SetScript("OnClick", function()
            S.savedFilters[fb.key] = not S.savedFilters[fb.key]
            RefreshSavedInstances()
        end)
        b._applyState = function()
            local active = S.savedFilters[fb.key]
            if ApplyVisuals then
                local vf = ns.UI.Factory
                if vf and vf.UpdateBorderColor then
                    vf:UpdateBorderColor(b, {di.color[1], di.color[2], di.color[3], active and 1 or 0.3})
                end
            end
            lbl:SetAlpha(active and 1 or 0.45)
        end
        b._applyState()
        S.savedFilterButtons[fb.key] = b
        fx = fx + b:GetWidth() + 4
    end

    -- Char count summary on the right of filter row (matches addon side margin)
    local summary
    if FontManager and FontManager.CreateFontString then
        summary = FontManager:CreateFontString(filterRow, "small", "OVERLAY")
    else
        summary = VBFontString(filterRow, "small")
    end
    summary:SetPoint("RIGHT", filterRow, "RIGHT", -SIDE_PAD, 0)
    summary:SetTextColor(0.75, 0.75, 0.8)
    f.summary = summary

    -- Scroll body + themed scrollbar (same pattern as NotificationManager / main UI)
    local CONTENT_PAD = (ns.UI_SPACING and ns.UI_SPACING.SIDE_MARGIN) or 10
    local SCROLLBAR_COL_W = (ns.UI_GetScrollbarColumnWidth and ns.UI_GetScrollbarColumnWidth()) or 26

    local scroll = VF:CreateScrollFrame(f, "UIPanelScrollFrameTemplate", true)
    scroll:SetPoint("TOPLEFT", filterRow, "BOTTOMLEFT", CONTENT_PAD, -CONTENT_PAD)
    scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(2 + CONTENT_PAD + SCROLLBAR_COL_W), 2 + CONTENT_PAD)

    local scrollBarColumn = nil
    if scroll.ScrollBar then
        local topInset = VBGetChromeBandHeight() + SAVED_FILTER_H + CONTENT_PAD + 2
        local bottomInset = CONTENT_PAD + 2
        scrollBarColumn = VF:CreateScrollBarColumn(f, SCROLLBAR_COL_W, topInset, bottomInset)
        VF:PositionScrollBarInContainer(scroll.ScrollBar, scrollBarColumn, 0)
    end

    local contentW = math.max(320, SAVED_FRAME_W - 4 - CONTENT_PAD * 2 - SCROLLBAR_COL_W)
    local content = VF:CreateContainer(scroll, contentW, 1, false)
    scroll:SetScrollChild(content)

    f.savedScrollBarColumn = scrollBarColumn

    local resizeGrip = CreateFrame("Button", nil, f)
    resizeGrip:SetSize(16, 16)
    resizeGrip:SetPoint("BOTTOMRIGHT", -2, 2)
    resizeGrip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeGrip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeGrip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeGrip:SetScript("OnMouseDown", function()
        if not InCombatLockdown or not InCombatLockdown() then
            f:StartSizing("BOTTOMRIGHT")
        end
    end)
    resizeGrip:SetScript("OnMouseUp", function()
        f:StopMovingOrSizing()
        if f:IsShown() then
            RefreshSavedInstances()
        end
    end)

    f._savedResizeToken = 0
    f:SetScript("OnSizeChanged", function(self)
        if not self:IsShown() then return end
        self._savedResizeToken = (self._savedResizeToken or 0) + 1
        local token = self._savedResizeToken
        if C_Timer and C_Timer.After then
            C_Timer.After(0.05, function()
                if S.savedFrame and S.savedFrame:IsShown() and S.savedFrame._savedResizeToken == token then
                    RefreshSavedInstances()
                end
            end)
        else
            RefreshSavedInstances()
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

    local row = ns.UI.Factory:CreateContainer(parent, totalW, 26, false)
    row:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(row, {0.06, 0.06, 0.09, 0.95}, {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.28})
    else
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.06, 0.06, 0.09, 0.95)
    end

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.25)

    -- Layout columns (equal-width predictable structure)
    local PAD = 8
    local NAME_W = 150
    local PROGRESS_W = SAVED_GROUP_PROGRESS_W
    local RESET_W = 48
    local dotsX = PAD + NAME_W + 8
    local dotsRight = totalW - PAD - PROGRESS_W - 8 - RESET_W - 8
    local dotsW = math.max(40, dotsRight - dotsX)

    -- Character name
    local nameFS
    if FontManager and FontManager.CreateFontString then
        nameFS = FontManager:CreateFontString(row, "body", "OVERLAY")
    else
        nameFS = VBFontString(row, "body")
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
            -- Boss dot border (subtle outline for better definition)
            local dotBorder = row:CreateTexture(nil, "ARTWORK", nil, 0)
            dotBorder:SetSize(size + 2, size + 2)
            dotBorder:SetPoint("LEFT", row, "LEFT", dotsX + (i - 1) * (size + gap) - 1, 0)
            dotBorder:SetColorTexture(0.10, 0.10, 0.14, 1)
            local dot = row:CreateTexture(nil, "ARTWORK", nil, 1)
            dot:SetSize(size, size)
            dot:SetPoint("LEFT", row, "LEFT", dotsX + (i - 1) * (size + gap), 0)
            if e.killed then
                dot:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)
            else
                dot:SetColorTexture(0.14, 0.14, 0.18, 1)
            end
        end
    end

    -- Progress text
    local progFS
    if FontManager and FontManager.CreateFontString then
        progFS = FontManager:CreateFontString(row, "small", "OVERLAY")
    else
        progFS = VBFontString(row, "small")
    end
    progFS:SetPoint("RIGHT", row, "RIGHT", -PAD - RESET_W - 8, 0)
    progFS:SetWidth(PROGRESS_W)
    progFS:SetJustifyH("CENTER")
    local progColor = (t > 0 and k >= t) and "|cff44ff44" or "|cffd4af37"
    progFS:SetText(string.format("%s%2d/%-2d|r", progColor, k, t))

    -- Reset countdown
    local resetFS
    if FontManager and FontManager.CreateFontString then
        resetFS = FontManager:CreateFontString(row, "small", "OVERLAY")
    else
        resetFS = VBFontString(row, "small")
    end
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
                e.killed and "|cff44ff44killed|r" or "|cff888888—|r",
                1,1,1, 0.85,0.85,0.85)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return row
end

--- Stable key for Saved Instances group collapse state (instance + difficulty).
local function MakeSavedGroupKey(group)
    return string.format("%s||%s", group.instanceName or "?", tostring(group.difficulty or 0))
end

--- Build the section header for an (instance, difficulty) group
local function BuildGroupHeader(parent, group, totalW, collapsed)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local diffInfo = GetDiffInfo(group.difficulty)

    local header = CreateFrame("Button", nil, parent)
    header:SetSize(totalW, 30)
    header:EnableMouse(true)
    header:RegisterForClicks("LeftButtonUp")

    if ApplyVisuals then
        ApplyVisuals(header, {diffInfo.color[1] * 0.18, diffInfo.color[2] * 0.18, diffInfo.color[3] * 0.18, 1},
            {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.85})
    end

    local hover = header:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(1, 1, 1, 0.06)

    -- Difficulty stripe (left edge)
    local stripe = header:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("BOTTOMLEFT", 1, 1)
    stripe:SetWidth(3)
    stripe:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)

    -- Difficulty badge
    local badgeW = diffInfo.short == "LFR" and 36 or 22
    local badge = ns.UI.Factory:CreateContainer(header, badgeW, 16, false)
    badge:SetPoint("LEFT", 12, 0)
    if ApplyVisuals then
        ApplyVisuals(badge, {diffInfo.color[1] * 0.5, diffInfo.color[2] * 0.5, diffInfo.color[3] * 0.5, 1},
            {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1})
    end
    local badgeFS
    if FontManager and FontManager.CreateFontString then
        badgeFS = FontManager:CreateFontString(badge, "small", "OVERLAY")
    else
        badgeFS = VBFontString(badge, "small")
    end
    badgeFS:SetPoint("CENTER")
    badgeFS:SetText("|cffffffff" .. diffInfo.short .. "|r")

    -- Instance name
    local nameFS
    if FontManager and FontManager.CreateFontString then
        nameFS = FontManager:CreateFontString(header, "body", "OVERLAY")
    else
        nameFS = VBFontString(header, "body")
    end
    nameFS:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    nameFS:SetPoint("RIGHT", header, "RIGHT", -110, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetMaxLines(1)
    nameFS:SetText(group.instanceName)
    nameFS:SetTextColor(1, 1, 1)

    -- Right side fixed columns: [characters] [progress]
    local bosses = AggregateBosses(group)
    local cleared, total = 0, bosses and #bosses or 0
    if bosses then
        for _, b in ipairs(bosses) do if #b.killers > 0 then cleared = cleared + 1 end end
    end

    local chev = header:CreateTexture(nil, "OVERLAY")
    chev:SetSize(SAVED_GROUP_CHEVRON_SIZE, SAVED_GROUP_CHEVRON_SIZE)
    chev:SetPoint("RIGHT", -10, 0)
    local function UpdateChevron()
        if collapsed then
            chev:SetAtlas("glues-characterSelect-icon-arrowDown-small-hover")
        else
            chev:SetAtlas("glues-characterSelect-icon-arrowUp-small-hover")
        end
    end
    UpdateChevron()

    local progressFS
    if FontManager and FontManager.CreateFontString then
        progressFS = FontManager:CreateFontString(header, "small", "OVERLAY")
    else
        progressFS = VBFontString(header, "small")
    end
    progressFS:SetJustifyH("CENTER")
    progressFS:SetWordWrap(false)
    progressFS:SetTextColor(0.85, 0.85, 0.9)
    progressFS:SetWidth(SAVED_GROUP_PROGRESS_W)
    progressFS:SetPoint("RIGHT", chev, "LEFT", -10, 0)
    local progColor = (total > 0 and cleared >= total) and "|cff44ff44" or "|cffd4af37"
    progressFS:SetText(string.format("%s%2d/%-2d|r", progColor, cleared, total))

    local countLabelFS
    if FontManager and FontManager.CreateFontString then
        countLabelFS = FontManager:CreateFontString(header, "small", "OVERLAY")
    else
        countLabelFS = VBFontString(header, "small")
    end
    countLabelFS:SetJustifyH("LEFT")
    countLabelFS:SetWordWrap(false)
    countLabelFS:SetTextColor(0.85, 0.85, 0.9)
    countLabelFS:SetWidth(86)
    countLabelFS:SetPoint("RIGHT", progressFS, "LEFT", -10, 0)
    countLabelFS:SetText(#group.characters == 1 and "character" or "characters")

    local countNumFS
    if FontManager and FontManager.CreateFontString then
        countNumFS = FontManager:CreateFontString(header, "small", "OVERLAY")
    else
        countNumFS = VBFontString(header, "small")
    end
    countNumFS:SetJustifyH("RIGHT")
    countNumFS:SetWordWrap(false)
    countNumFS:SetTextColor(0.85, 0.85, 0.9)
    countNumFS:SetWidth(18)
    countNumFS:SetPoint("RIGHT", countLabelFS, "LEFT", -6, 0)
    countNumFS:SetText(string.format("%2d", #group.characters))

    nameFS:ClearAllPoints()
    nameFS:SetPoint("LEFT", badge, "RIGHT", 10, 0)
    nameFS:SetPoint("RIGHT", countNumFS, "LEFT", -12, 0)

    header:SetScript("OnEnter", function(self)
        WNTooltipShow(self, {
            type = "custom",
            title = group.instanceName or "?",
            lines = {
                { text = "|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r" },
                { text = " " },
                { text = (ns.L and ns.L["SAVED_INSTANCES_EXPAND_HINT"]) or "Click to expand/collapse character lockouts" },
            },
            anchor = "ANCHOR_RIGHT",
        })
    end)
    header:SetScript("OnLeave", function() WNTooltipHide() end)

    return header
end

local function BuildSavedInstanceArtCache()
    if S.savedInstanceArtByName then return S.savedInstanceArtByName end
    S.savedInstanceArtByName = {}
    if not EJ_GetInstanceByIndex or not EJ_GetInstanceInfo then
        return S.savedInstanceArtByName
    end

    for raidFlag = 0, 1 do
        for idx = 1, 250 do
            local okIdx, journalID = pcall(EJ_GetInstanceByIndex, idx, raidFlag == 1)
            if not okIdx or not journalID then break end
            if not (issecretvalue and issecretvalue(journalID)) then
                local okInfo, name, _, bgImage, buttonImage, loreImage = pcall(EJ_GetInstanceInfo, journalID)
                if okInfo and name and type(name) == "string" and not (issecretvalue and issecretvalue(name)) then
                    local key = string.lower(name)
                    if key ~= "" and not S.savedInstanceArtByName[key] then
                        S.savedInstanceArtByName[key] = buttonImage or loreImage or bgImage
                    end
                end
            end
        end
    end
    return S.savedInstanceArtByName
end

local function GetSavedInstanceArt(group)
    if not group then return nil end
    if group.instanceID and EJ_GetInstanceInfo and not (issecretvalue and issecretvalue(group.instanceID)) then
        local okInfo, _, _, bgImage, buttonImage, loreImage = pcall(EJ_GetInstanceInfo, group.instanceID)
        local direct = okInfo and (buttonImage or loreImage or bgImage) or nil
        if direct then return direct end
    end

    local name = group.instanceName
    if not name or type(name) ~= "string" or (issecretvalue and issecretvalue(name)) then
        return nil
    end
    local map = BuildSavedInstanceArtCache()
    return map and map[string.lower(name)] or nil
end

local function FormatSavedResetShort(secondsLeft)
    if not secondsLeft or secondsLeft <= 0 then return "" end
    local hours = math.floor(secondsLeft / 3600)
    local days = math.floor(hours / 24)
    if days > 0 then
        local fmt = (ns.L and ns.L["SAVED_INSTANCES_RESET_DAYS"]) or "%dd"
        return string.format(fmt, days)
    end
    if hours > 0 then
        local fmt = (ns.L and ns.L["SAVED_INSTANCES_RESET_HOURS"]) or "%dh"
        return string.format(fmt, hours)
    end
    return (ns.L and ns.L["SAVED_INSTANCES_RESET_LESS_HOUR"]) or "<1h"
end

local function BuildInstanceCard(parent, group, cardSize)
    local ApplyVisuals = ns.UI_ApplyVisuals
    local FontManager = ns.FontManager
    local diffInfo = GetDiffInfo(group.difficulty)
    local bosses = AggregateBosses(group)
    local total = bosses and #bosses or 0
    local cleared = 0
    if bosses then
        for i = 1, #bosses do
            if #bosses[i].killers > 0 then
                cleared = cleared + 1
            end
        end
    end

    local card = CreateFrame("Button", nil, parent)
    card:SetSize(cardSize, cardSize)
    card:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(card, {0.04, 0.04, 0.06, 0.96}, {diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 0.65})
    end

    local stripe = card:CreateTexture(nil, "ARTWORK")
    stripe:SetPoint("TOPLEFT", 1, -1)
    stripe:SetPoint("TOPRIGHT", -1, -1)
    stripe:SetHeight(2)
    stripe:SetColorTexture(diffInfo.color[1], diffInfo.color[2], diffInfo.color[3], 1)

    local titleFS = FontManager and FontManager.CreateFontString
        and FontManager:CreateFontString(card, "body", "OVERLAY")
        or VBFontString(card, "body")
    titleFS:SetPoint("TOPLEFT", 8, -8)
    titleFS:SetPoint("TOPRIGHT", -8, -8)
    titleFS:SetJustifyH("CENTER")
    titleFS:SetJustifyV("TOP")
    titleFS:SetWordWrap(true)
    titleFS:SetMaxLines(2)
    titleFS:SetText(group.instanceName or "?")

    local art = card:CreateTexture(nil, "BORDER")
    art:SetPoint("TOPLEFT", 12, -40)
    art:SetPoint("TOPRIGHT", -12, -40)
    art:SetPoint("BOTTOM", card, "BOTTOM", 0, 28)
    art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local instanceArt = GetSavedInstanceArt(group)
    art:SetTexture(instanceArt or "Interface\\Icons\\INV_Misc_QuestionMark")
    if not instanceArt then
        art:SetDesaturated(true)
        art:SetVertexColor(0.65, 0.65, 0.65, 1)
    else
        art:SetDesaturated(false)
        art:SetVertexColor(1, 1, 1, 1)
    end

    local diffFS = VBFontString(card, "small")
    diffFS:SetPoint("BOTTOM", card, "BOTTOM", 0, 11)
    diffFS:SetText("|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r")

    local progFS = VBFontString(card, "small")
    progFS:SetPoint("BOTTOM", diffFS, "TOP", 0, 2)
    local pColor = (total > 0 and cleared >= total) and "|cff44ff44" or "|cffd4af37"
    progFS:SetText(string.format("%s%d/%d|r", pColor, cleared, total))

    card:SetScript("OnEnter", function(self)
        local lines = {}
        lines[#lines + 1] = { text = "|cff999999Difficulty|r" }
        lines[#lines + 1] = { text = "|cff" .. diffInfo.hex .. (group.difficultyName or diffInfo.name) .. "|r" }
        lines[#lines + 1] = { text = " " }
        lines[#lines + 1] = { text = "|cff999999Bosses -> Characters|r" }

        if bosses and #bosses > 0 then
            for bi = 1, #bosses do
                local b = bosses[bi]
                local killers = b.killers or {}
                local right
                if #killers == 0 then
                    right = "|cff888888—|r"
                else
                    local parts = {}
                    for ki = 1, #killers do
                        local hex, name = GetClassHexFromCharacters(killers[ki])
                        parts[#parts + 1] = "|cff" .. hex .. name .. "|r"
                    end
                    right = table.concat(parts, ", ")
                end
                lines[#lines + 1] = {
                    left = string.format("%d. %s", bi, b.name or ("Boss " .. tostring(bi))),
                    right = right,
                    leftColor = {1, 1, 1},
                    rightColor = {0.88, 0.88, 0.9},
                }
            end
        else
            lines[#lines + 1] = { text = "|cff666666Boss data unavailable|r" }
        end

        lines[#lines + 1] = { text = " " }
        lines[#lines + 1] = { text = "|cff999999Completed characters|r" }
        local completed = {}
        for ci = 1, #group.characters do
            local c = group.characters[ci]
            local killed = c.killed or 0
            local totalBoss = c.total or 0
            if totalBoss > 0 and killed >= totalBoss then
                local hex, name = GetClassHexFromCharacters(c.charKey)
                local resetTag = FormatSavedResetShort(c.reset)
                if resetTag ~= "" then
                    completed[#completed + 1] = string.format("|cff%s%s|r |cff777777(%s)|r", hex, name or c.charKey, resetTag)
                else
                    completed[#completed + 1] = string.format("|cff%s%s|r", hex, name or c.charKey)
                end
            end
        end
        if #completed == 0 then
            lines[#lines + 1] = { text = "|cff666666None|r" }
        else
            for i = 1, #completed do
                lines[#lines + 1] = { text = completed[i] }
            end
        end

        WNTooltipShow(self, {
            type = "custom",
            title = group.instanceName or "?",
            lines = lines,
            anchor = "ANCHOR_RIGHT",
        })
    end)
    card:SetScript("OnLeave", function() WNTooltipHide() end)

    return card
end

RefreshSavedInstances = function()
    BuildSavedInstancesFrame()
    local content = S.savedContent
    if not content then return end

    ReleaseSavedInstanceRows()

    local list = BuildSavedInstancesData()
    local filtered = {}
    local filters = S.savedFilters or {}
    for i = 1, #list do
        local g = list[i]
        local diff = g.difficulty
        local pass = (diff == 17 and filters.lfr)
            or (diff == 14 and filters.normal)
            or (diff == 15 and filters.heroic)
            or (diff == 16 and filters.mythic)
            or (diff ~= 14 and diff ~= 15 and diff ~= 16 and diff ~= 17)
        if pass then
            filtered[#filtered + 1] = g
        end
    end

    if S.savedFilterButtons then
        for _, b in pairs(S.savedFilterButtons) do
            if b._applyState then b._applyState() end
        end
    end

    if S.savedFrame and S.savedFrame.summary then
        local charSet = {}
        for i = 1, #filtered do
            local g = filtered[i]
            for ci = 1, #g.characters do
                charSet[g.characters[ci].charKey] = true
            end
        end
        local n = 0
        for _ in pairs(charSet) do n = n + 1 end
        local sumFmt = (ns.L and ns.L["SAVED_INSTANCES_SUMMARY"]) or "%d instances · %d characters"
        S.savedFrame.summary:SetText(string.format(sumFmt, #filtered, n))
    end

    local viewportW = (S.savedScroll and S.savedScroll.GetWidth and S.savedScroll:GetWidth()) or SAVED_FRAME_W
    content:SetWidth(math.max(320, viewportW))

    if #filtered == 0 then
        local FontManager = ns.FontManager
        local msg
        if FontManager and FontManager.CreateFontString then
            msg = FontManager:CreateFontString(content, "body", "OVERLAY")
        else
            msg = VBFontString(content, "body")
        end
        msg:SetPoint("CENTER", content, "CENTER", 0, -20)
        msg:SetTextColor(0.6, 0.6, 0.6)
        if #list == 0 then
            msg:SetText((ns.L and ns.L["SAVED_INSTANCES_EMPTY"]) or "No saved lockouts yet.\nLog in a character with raid or dungeon lockouts.")
        else
            msg:SetText((ns.L and ns.L["SAVED_INSTANCES_NO_FILTER_MATCH"]) or "No instances match the current filters.")
        end
        msg:SetJustifyH("CENTER")
        content:SetHeight(80)
        S.savedRows[#S.savedRows + 1] = msg
        local vf = ns.UI.Factory
        if vf and vf.UpdateScrollBarVisibility and S.savedScroll then
            vf:UpdateScrollBarVisibility(S.savedScroll)
        end
        S.savedFrame:Show()
        return
    end

    table.sort(filtered, function(a, b)
        local nameA = a.instanceName or ""
        local nameB = b.instanceName or ""
        if nameA ~= nameB then return nameA < nameB end
        local ra = DIFF_SORT_RANK[a.difficulty] or 99
        local rb = DIFF_SORT_RANK[b.difficulty] or 99
        if ra ~= rb then return ra < rb end
        return (a.difficultyName or "") < (b.difficultyName or "")
    end)

    local SIDE_PAD = (ns.UI_SPACING and ns.UI_SPACING.SIDE_MARGIN) or 10
    local GROUP_GAP = 12
    local ROW_GAP = 3
    local rowW = math.max(260, content:GetWidth() - (SIDE_PAD * 2))
    local y = 8
    local prevScroll = (S.savedScroll and S.savedScroll.GetVerticalScroll and S.savedScroll:GetVerticalScroll()) or 0

    S.savedGroupCollapsed = S.savedGroupCollapsed or {}

    for gi = 1, #filtered do
        local group = filtered[gi]
        if gi > 1 then
            y = y + GROUP_GAP
        end

        local groupKey = MakeSavedGroupKey(group)
        local collapsed = S.savedGroupCollapsed[groupKey] == true

        local header = BuildGroupHeader(content, group, rowW, collapsed)
        header._savedGroupKey = groupKey
        header:SetScript("OnClick", function()
            local key = header._savedGroupKey
            if not key then return end
            S.savedGroupCollapsed[key] = not S.savedGroupCollapsed[key]
            RefreshSavedInstances()
        end)
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE_PAD, -y)
        S.savedRows[#S.savedRows + 1] = header
        y = y + header:GetHeight() + ROW_GAP

        if not collapsed then
            local roster = group.characters or {}
            table.sort(roster, function(a, b)
                local _, nameA = GetClassHexFromCharacters(a.charKey)
                local _, nameB = GetClassHexFromCharacters(b.charKey)
                return (nameA or a.charKey or "") < (nameB or b.charKey or "")
            end)

            for ci = 1, #roster do
                local c = roster[ci]
                local charRow = BuildLockoutRow(content, c, c.encounters, group, rowW)
                charRow:ClearAllPoints()
                charRow:SetPoint("TOPLEFT", content, "TOPLEFT", SIDE_PAD, -y)
                S.savedRows[#S.savedRows + 1] = charRow
                y = y + charRow:GetHeight() + ROW_GAP
            end
        end
    end

    content:SetHeight(math.max(40, y))
    local viewportH = (S.savedScroll and S.savedScroll.GetHeight and S.savedScroll:GetHeight()) or 0
    local maxY = math.max(0, (content:GetHeight() or 0) - viewportH)
    S.savedScroll:SetVerticalScroll(math.min(maxY, math.max(0, prevScroll)))
    local vf = ns.UI.Factory
    if vf and vf.UpdateScrollBarVisibility and S.savedScroll then
        vf:UpdateScrollBarVisibility(S.savedScroll)
    end
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
    -- Fresh open: explicitly start at the top before RefreshSavedInstances clamps the new content.
    if S.savedScroll and S.savedScroll.SetVerticalScroll then
        S.savedScroll:SetVerticalScroll(0)
    end
    RefreshSavedInstances()
end

-- ============================================================================
-- Easy Access shortcut menu
-- ============================================================================
local function CreateMenuItem(parent, opts, y)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(parent:GetWidth() - 8, 30)
    btn:SetPoint("TOPLEFT", parent, "TOPLEFT", 4, y)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    local accent = (ns.UI_COLORS and ns.UI_COLORS.accent) or {0.40, 0.20, 0.58}
    hl:SetColorTexture(accent[1], accent[2], accent[3], 0.25)

    local MENU_ICON_SIZE = 20
    if opts.iconAtlas or opts.icon then
        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(MENU_ICON_SIZE, MENU_ICON_SIZE)
        icon:SetPoint("LEFT", 6, 0)
        if opts.iconAtlas and icon.SetAtlas then
            icon:SetTexture(nil)
            local ok = pcall(icon.SetAtlas, icon, opts.iconAtlas, false)
            if not ok and opts.icon then
                icon:SetTexture(opts.icon)
                icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end
        elseif opts.icon then
            icon:SetTexture(opts.icon)
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end

    local FontManager = ns.FontManager
    local label
    if FontManager and FontManager.CreateFontString then
        label = FontManager:CreateFontString(btn, "body", "OVERLAY")
    else
        label = VBFontString(btn, "body")
    end
    label:SetPoint("LEFT", 32, 0)
    label:SetText(opts.label)
    label:SetTextColor(1, 1, 1)

    -- Left-click indicator (larger than legacy GameFont "*" glyph)
    local STAR_SIZE = 18
    local star = btn:CreateTexture(nil, "OVERLAY")
    star:SetSize(STAR_SIZE, STAR_SIZE)
    star:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    star:Hide()
    if star.SetAtlas then
        local ok = pcall(star.SetAtlas, star, "PetJournal-FavoritesIcon", false)
        if ok then
            star:SetVertexColor(1, 0.9, 0.2)
        else
            star:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
        end
    else
        star:SetTexture("Interface\\RaidFrame\\ReadyCheck-Waiting")
    end
    btn.selectionStar = star
    btn.leftClickAction = opts.leftClickAction

    btn.RefreshSelection = function(self)
        local selected = self.leftClickAction and GetSettings().leftClickAction == self.leftClickAction
        if self.selectionStar then
            self.selectionStar:SetShown(selected == true)
        end
    end
    btn:RefreshSelection()

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and self.leftClickAction then
            GetSettings().leftClickAction = self.leftClickAction
            if S.menuFrame then
                S.menuFrame.leftClickAction = self.leftClickAction
                for _, row in ipairs(S.menuFrame.menuItems or {}) do
                    if row.RefreshSelection then row:RefreshSelection() end
                end
            end
            return
        end
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

    local GetTabIcon = ns.UI_GetTabIcon
    local tabIcon = function(key)
        return (GetTabIcon and GetTabIcon(key)) or nil
    end
    -- Order: Characters first; icons match main-window tab header atlases (SharedWidgets TAB_HEADER_ICONS)
    -- plus PvE vault / lockout column textures where no standalone tab exists.
    local items = {
        { label = "Characters Tab", leftClickAction = "chars",
          iconAtlas = tabIcon("characters"), icon = "Interface\\Icons\\Achievement_Character_Human_Male",
          action = function()
            HideAllPanels()
            ToggleWNCharsTab()
        end },
        { label = "PvE Tab", leftClickAction = "pve",
          iconAtlas = tabIcon("pve"), icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
          action = function()
            HideAllPanels()
            ToggleWNPveTab()
        end },
        { label = "Vault Tracker",
          leftClickAction = "vault",
          iconAtlas = "GreatVault-32x32",
          icon = "Interface\\Icons\\Achievement_Boss_Argus",
          action = function()
            ShowQuickView(S.button)
          end },
        { label = "Saved Instances", leftClickAction = "saved", icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01", action = function()
            HideTable(); HideMenu(); ToggleSavedInstances()
        end },
        { label = "Plans / Todo", leftClickAction = "plans",
          iconAtlas = tabIcon("plans"), icon = "Interface\\Icons\\INV_Inscription_Scroll",
          action = function()
            if WarbandNexus and WarbandNexus.TogglePlansTrackerWindow then
                if InCombatLockdown and InCombatLockdown() then return end
                WarbandNexus:TogglePlansTrackerWindow()
            end
        end },
        { label = "Settings",
          iconAtlas = "mechagon-projects", icon = "Interface\\Icons\\Trade_Engineering",
          action = function()
            HideMenu(); OpenWNSettingsTab()
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
    if ns.UI_ApplyStandardCardElevatedChrome then
        ns.UI_ApplyStandardCardElevatedChrome(f)
    elseif ApplyVisuals then
        ApplyVisuals(f, {0.02, 0.02, 0.03, 0.98}, {accent[1], accent[2], accent[3], 1})
    end
    f:Hide()
    f.leftClickAction = GetSettings().leftClickAction

    -- Header bar (matches main chrome style)
    local header = CreateFrame("Frame", nil, f)
    local menuInset = VBGetFrameContentInset()
    header:SetHeight(headerH)
    header:SetPoint("TOPLEFT", f, "TOPLEFT", menuInset, -menuInset)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -menuInset, -menuInset)
    if ApplyVisuals then
        ApplyVisuals(header, {accentDark[1], accentDark[2], accentDark[3], 1}, {accent[1], accent[2], accent[3], 0.8})
    end
    header:EnableMouse(true)
    header:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:ClearLines()
        GameTooltip:AddLine((ns.L and ns.L["CONFIG_VAULT_BUTTON_SECTION"]) or "Easy Access", 1, 1, 1)
        GameTooltip:AddLine("The star marks the current left-click action.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine("Right-click a menu option to set it as the left-click action.", 0.85, 0.85, 0.85, true)
        GameTooltip:Show()
    end)
    header:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    local headerIcon = header:CreateTexture(nil, "ARTWORK")
    headerIcon:SetSize(16, 16)
    headerIcon:SetPoint("LEFT", 8, 0)
    headerIcon:SetTexture(ICON_TEXTURE)
    if not headerIcon:GetTexture() then
        headerIcon:SetTexture(ICON_FALLBACK)
        headerIcon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    else
        headerIcon:SetTexCoord(0, 1, 0, 1)
    end

    local FontManager = ns.FontManager
    local titleFS
    if FontManager and FontManager.CreateFontString and FontManager.GetFontRole then
        titleFS = FontManager:CreateFontString(header, FontManager:GetFontRole("windowChromeTitle"), "OVERLAY")
    else
        titleFS = VBFontString(header, "small")
    end
    titleFS:SetPoint("LEFT", headerIcon, "RIGHT", 6, 0)
    titleFS:SetText((ns.L and ns.L["CONFIG_VAULT_BUTTON_SECTION"]) or "Easy Access")
    titleFS:SetTextColor(1, 1, 1)

    local y = -(headerH + 4)
    f.menuItems = {}
    for _, opt in ipairs(items) do
        local row = CreateMenuItem(f, opt, y)
        table.insert(f.menuItems, row)
        y = y - (rowH + 2)
    end

    -- Auto-hide on focus loss: close when mouse leaves and not over a child
    f:SetScript("OnUpdate", function(self, elapsed)
        elapsed = elapsed or 0
        if self:IsMouseOver() then
            self._hideElapsed = 0
        else
            self._hideElapsed = (self._hideElapsed or 0) + elapsed
            if self._hideElapsed > 2.5 then
                self:Hide()
            end
        end
    end)

    S.menuFrame = f
end

ToggleMenu = function(anchor, atCursor)
    local leftClickAction = GetSettings().leftClickAction
    if S.menuFrame and S.menuFrame.leftClickAction ~= leftClickAction then
        S.menuFrame:Hide()
        S.menuFrame = nil
    end
    BuildMenu()
    if not S.menuFrame then return end
    if S.menuFrame:IsShown() and not atCursor then
        S.menuFrame:Hide()
        return
    end
    S.menuFrame:ClearAllPoints()
    if atCursor then
        local scale = UIParent:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        x = (x or 0) / scale
        y = (y or 0) / scale

        local mw = S.menuFrame:GetWidth() or 200
        local mh = S.menuFrame:GetHeight() or 200
        local screenW = UIParent:GetWidth() or 1920
        local screenH = UIParent:GetHeight() or 1080
        local gap = 8

        x = math.max(gap, math.min(x + gap, screenW - mw - gap))
        y = math.max(mh + gap, math.min(y - gap, screenH - gap))
        S.menuFrame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x, y)
    else
        anchor = anchor or S.button
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
    end
    S.menuFrame._hideElapsed = 0
    S.menuFrame:Show()
end

function WarbandNexus:OpenVaultButtonQuickMenu(anchor)
    ToggleMenu(anchor or S.button)
end

function WarbandNexus:OpenVaultButtonQuickMenuAtCursor()
    ToggleMenu(nil, true)
end

local function RunLeftClickAction(anchor)
    local action = GetSettings().leftClickAction
    if action == "vault" then
        if S.tableFrame and S.tableFrame:IsShown() then
            HideTable()
        else
            ShowQuickView(anchor or S.button)
        end
    elseif action == "saved" then
        HideTable()
        HideMenu()
        ToggleSavedInstances()
    elseif action == "plans" then
        HideTable()
        HideMenu()
        if WarbandNexus and WarbandNexus.TogglePlansTrackerWindow then
            if InCombatLockdown and InCombatLockdown() then return end
            WarbandNexus:TogglePlansTrackerWindow()
        end
    elseif action == "chars" then
        HideAllPanels()
        ToggleWNCharsTab()
    elseif action == "pve" or not action then
        HideAllPanels()
        ToggleWNPveTab()
    end
end

RefreshButtonSettings = function()
    local tableWasShown = S.tableFrame and S.tableFrame:IsShown()
    if S.optionsFrame then
        if S.optionsFrame.RefreshValues then
            S.optionsFrame:RefreshValues()
        end
    end
    if S.menuFrame then
        S.menuFrame:Hide()
        S.menuFrame = nil
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
        icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)  -- Blizzard inventory icons: slight inset
    else
        icon:SetTexCoord(0, 1, 0, 1) -- packaged square `Media/icon.tga`: full UV (inset distorted the glyph)
    end
    S.icon = icon

    local badgeBg = btn:CreateTexture(nil, "OVERLAY")
    badgeBg:SetSize(BADGE_SIZE, BADGE_SIZE)
    badgeBg:SetPoint("TOPRIGHT", btn, "TOPRIGHT", 4, 4)
    badgeBg:SetColorTexture(0.15, 0.75, 0.25, 1.0)
    badgeBg:Hide()
    S.badgeBg = badgeBg

    local badge = VBFontString(btn, "small")
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
        -- Suppress tooltip while the context menu is open to prevent overlap
        local menuOpen = S.menuFrame and S.menuFrame:IsShown()
        if over ~= self._hovering then
            self._hovering = over
            if over and not menuOpen then
                ApplyButtonVisibility(true)
                ShowHoverTooltip(self)
            else
                WNTooltipHide()
                if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
                if not over then
                    ApplyButtonVisibility(false)
                end
            end
        elseif over and menuOpen then
            -- Menu opened while hovering — hide tooltip immediately
            WNTooltipHide()
            if GameTooltip:GetOwner() == self then GameTooltip:Hide() end
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
        -- Always hide tooltip on any click to prevent overlap with menu
        WNTooltipHide()
        GameTooltip:Hide()
        if mouseButton == "RightButton" then
            ToggleMenu(self)
        else
            HideMenu()
            RunLeftClickAction(self)
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

-- Coalesce burst of cache messages (PVE_UPDATED + CHARACTER_UPDATED + VAULT_* often fire in
-- the same frame) into a single redraw. Without this, each open Saved Instances toggle would
-- rebuild its rows up to four times per cache wave.
local pendingDataRefresh = false
local function ScheduleDataRefresh()
    if pendingDataRefresh then return end
    pendingDataRefresh = true
    C_Timer.After(0.1, function()
        pendingDataRefresh = false
        UpdateBadge()
        if S.tableFrame and S.tableFrame:IsShown() then
            RefreshTable()
        end
        if S.savedFrame and S.savedFrame:IsShown() then
            RefreshSavedInstances()
        end
    end)
end

local OnDataChanged = ScheduleDataRefresh

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
        WarbandNexus:RegisterMessage(E.CURRENCY_UPDATED, OnDataChanged)
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

--- Public toggle for the Vault Tracker quick window (used by /wn vt and the
--- minimap context menu).
function WarbandNexus:ToggleVaultTrackerWindow()
    if S.tableFrame and S.tableFrame:IsShown() then
        if HideTable then HideTable() end
        return
    end
    if RefreshTable then
        RefreshTable()
        if S.tableFrame and not S.tableFrame:GetPoint() then
            S.tableFrame:ClearAllPoints()
            S.tableFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
    end
end

--- Public toggle for the Saved Instances window.
function WarbandNexus:ToggleSavedInstancesWindow()
    if ToggleSavedInstances then ToggleSavedInstances() end
end

--- Get vault status for a character (used by PvE tab Status column + Vault Tracker).
--- Logic:
---   * Logged-in char: prefer live `C_WeeklyRewards.HasAvailableRewards()` so post-reset
---     carry-over chests show Ready immediately (matches the Great Vault\226\128\153s own prompt).
---     When the player claims, WEEKLY_REWARDS_ITEM_CHANGED clears the cache automatically.
---   * Other chars: cached `hasAvailableRewards` is authoritative when true; if it's false
---     but the char had completed slots AND weekly reset has crossed, auto-flip to Ready
---     (those slots are now a sitting chest \226\128\148 they\226\128\153ll log in to claim).
--- Returns: { isReady, isPending, readySlots } or nil when there's no progress to show.
function WarbandNexus:GetVaultStatusForChar(charKey)
    if not charKey then return nil end
    local pveCache = GetPveCache()
    if not pveCache then return nil end
    local rewards    = pveCache.greatVault and pveCache.greatVault.rewards
    local rewardData = rewards and rewards[charKey]
    local isReady    = rewardData and rewardData.hasAvailableRewards == true or false

    local readySlots = CountReadySlots(charKey) or 0
    local currentKey = GetCurrentCharKey()

    if currentKey and charKey == currentKey and C_WeeklyRewards
        and C_WeeklyRewards.HasAvailableRewards then
        if C_WeeklyRewards.HasAvailableRewards() then
            isReady = true
        end
    elseif not isReady and readySlots > 0 and VaultResetCrossedFor(charKey) then
        -- Alt had ready slots last week; reset has crossed -> chest is sitting unclaimed.
        isReady = true
    end

    local hasProg = readySlots > 0 or HasAnyProgress(charKey)
    if not isReady and not hasProg then return nil end
    return {
        isReady    = isReady,
        isPending  = not isReady and hasProg,
        readySlots = readySlots,
    }
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
