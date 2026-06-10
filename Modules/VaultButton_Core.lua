--[[ Warband Nexus - Easy Access - VaultButton_Core.lua ]]

local ADDON_NAME, ns = ...
ns.VaultButton = ns.VaultButton or {}
local M = ns.VaultButton
local WarbandNexus = ns.WarbandNexus

local function VB__setfenv()
    return setmetatable({ M = M, ns = ns, WarbandNexus = WarbandNexus, S = M.state }, {
        __index = function(_, k)
            local v = M[k]
            if v ~= nil then return v end
            return _G[k]
        end,
    })
end
setfenv(1, VB__setfenv())
--[[ VaultButton multi-file module: bare names resolve to ns.VaultButton (M) then _G.
     Anything used from another VaultButton_*.lua file MUST be M.* or S.* — never chunk-local.
     WN_FACTORY: Loads before `Modules/UI/SharedWidgets.lua` in `WarbandNexus.toc`.
     Never read `ns.UI.Factory` at chunk load — it appears after SharedWidgets runs.
     All `ns.UI.Factory` / `VF` usages are inside button/table/menu construction paths (runtime).

     WN_* listeners: `M.HookWNMessages` uses `M._msgListeners` as AceEvent self (see VaultButton.lua).
     Intentionally raw CreateFrame highlights: vault root dialogs (BackdropTemplate + global names),
     Blizzard `CheckButton` fallback when themed checkbox is absent, event coalescing frames,
     resize grip (Blizzard size grabber textures), Saved group header as full-surface `Button`,
     lockout row inner highlights, main floating vault `WarbandNexusVaultButton`.]]

-- Constants
M.BUTTON_SIZE = 48
M.BADGE_SIZE = 18
M.ROW_H = 28
M.HEADER_H = 24
M.CHROME_H = 40
M.FRAME_PAD = 8
M.MAX_ROWS = 20
M.ICON_TEXTURE = ns.WARBAND_ADDON_MEDIA_ICON or "Interface\\AddOns\\WarbandNexus\\Media\\icon.tga"
M.ICON_FALLBACK = "Interface\\Icons\\INV_Misc_TreasureChest02"
M.VOIDCORE_ID = 3418
M.MANAFLUX_ID = 3378
M.BOUNTY_ITEM_ID = 252415

M.COL_NAME = 140
M.COL_ILVL = 50
M.COL_RAID = 72
M.COL_DUNGEON = 72
M.COL_WORLD = 72
M.COL_REWARD_ILVL = 106
M.COL_PROGRESS = 108
M.COL_REWARD_PROGRESS = 144
M.COL_BOUNTY = 46   -- Trovehunter's Bounty (done/not)
M.COL_VOIDCORE = 58   -- Nebulous Voidcore (current/seasonMax)
M.COL_MANAFLUX = 58   -- Dawnlight Manaflux (current held)
M.COL_STASH = 58   -- Gilded Stashes (current/max)
M.COL_STATUS = 110

M.TRACK_ICONS = {
    raids      = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    mythicPlus = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
    keystone   = 525134,
    world      = "Interface\\Icons\\INV_Misc_Map_01",
    bounty     = 1064187,
    voidcore   = 7658128,
    manaflux   = "Interface\\Icons\\INV_Enchant_DustArcane",
    gildedStash = "Interface\\Icons\\Inv_cape_special_treasure_c_01",
}
M.KEYSTONE_ICON_ATLAS = "ChromieTime-32x32"

M.CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
M.CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
M.UPARROW = "|A:loottoast-arrow-green:12:12|a"

-- Easy Access tooltip / menu copy (shared across VaultButton_* chunks via M)
M.EA_MONEY_ICON = 14
M.EA_LABEL_COLOR = { 0.94, 0.94, 0.96 }
M.EA_VALUE_COLOR = { 0.94, 0.94, 0.96 }
M.EA_SECTION_COLOR = { 1, 1, 1 }
M.EA_FOOTER_COLOR = { 0.88, 0.88, 0.90 }
M.EA_STATUS_ICON = "Interface\\RaidFrame\\ReadyCheck-Ready"
M.EA_CAT_TIP = {
    raids = { key = "EA_TOOLTIP_CAT_RAID", fallback = "Raid", icon = M.TRACK_ICONS.raids },
    mythicPlus = { key = "EA_TOOLTIP_CAT_DUNGEON", fallback = "Dungeon", icon = M.TRACK_ICONS.mythicPlus },
    world = { key = "EA_TOOLTIP_CAT_WORLD", fallback = "World", icon = M.TRACK_ICONS.world },
}

--- VaultTracker font helper: routes through FontManager when available, falls back
--- to GameFontNormal[Small] otherwise. Call sites use one of: "body" | "small" | "title" | "subtitle" | "header".
function M.VBFontString(parent, role, drawLayer)
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
function M.VBGetFrameContentInset()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.FRAME_CONTENT_INSET or 2
end

--- Aligns draggable chrome band height with main window header (`HEADER_BAR_HEIGHT`; fallback preserves legacy CHROME_H).
function M.VBGetChromeBandHeight()
    local ms = ns.UI_LAYOUT and ns.UI_LAYOUT.MAIN_SHELL or {}
    return ms.HEADER_BAR_HEIGHT or CHROME_H
end

--- Draggable chrome band inside backdrop inner edge (`FRAME_CONTENT_INSET`).
---@return number bandHeight for stacking header rows below the band.
function M.VBAnchorChromeBandTop(chrome, parentFrame)
    local inset = VBGetFrameContentInset()
    local h = VBGetChromeBandHeight()
    chrome:SetHeight(h)
    chrome:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", inset, -inset)
    chrome:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -inset, -inset)
    return h
end

--- Full-width row below chrome (`FRAME_CONTENT_INSET` horizontally); adds `belowYOffset` beyond chrome band height.
function M.VBAnchorFullWidthRowBelowChrome(row, rootFrame, chromeBandHeight, belowYOffset)
    local inset = VBGetFrameContentInset()
    local y = -(chromeBandHeight + (belowYOffset or 0))
    row:SetPoint("TOPLEFT", rootFrame, "TOPLEFT", inset, y)
    row:SetPoint("TOPRIGHT", rootFrame, "TOPRIGHT", -inset, y)
end

--- Saved Instances body insets — mirror Vault Tracker table (`FRAME_PAD` on all sides, scroll bar inside scroll frame).
M.SAVED_INSTANCES_LAYOUT_VERSION = 2
function M.VBGetSavedInstancesLayout()
    return {
        pad = FRAME_PAD,
        filterBelowChrome = 4,
        contentTopGap = FRAME_PAD,
        contentBottomPad = FRAME_PAD,
        layoutVersion = SAVED_INSTANCES_LAYOUT_VERSION,
    }
end

M.DASH = "|cff888888-|r"

-- Maps Easy Access column key -> PvE typeName used by upgrade-detection logic
M.CAT_TO_TYPE = { raids = "Raid", mythicPlus = "M+", world = "World" }

function M.IsSlotAtMax(activity, typeName)
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

function M.SlotShowsUpgrade(act, typeName)
    if not act then return false end
    local ni = tonumber(act.nextLevelIlvl) or 0
    if ni > 0 then return true end
    local th = tonumber(act.threshold) or 0
    local prog = tonumber(act.progress) or 0
    if th <= 0 or prog < th then return false end
    if IsSlotAtMax(act, typeName) then return false end
    return true
end

function M.GetCurrencyIcon(currencyID, fallback)
    if C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local info = C_CurrencyInfo.GetCurrencyInfo(currencyID)
        if info and info.iconFileID then
            return info.iconFileID
        end
    end
    return fallback
end

-- DB helpers
function M.GetThemeColors()
    return ns.UI_COLORS or {
        accent = {0.40, 0.20, 0.58},
        accentDark = {0.28, 0.14, 0.41},
        border = {0.20, 0.20, 0.25},
        bg = {0.04, 0.04, 0.05, 0.98},
        bgCard = {0.04, 0.04, 0.05, 0.98},
        textDim = {0.55, 0.55, 0.55, 1},
    }
end

-- Launcher registry (Easy Access menu, Settings left-click, minimap shortcut menu)

---@type table<string, boolean>
local LAUNCHER_LEFT_CLICK_LOOKUP

--- Ordered assignable left-click action ids (`plans` = Plans Tracker mini window; `plans_tab` = main To-Do tab).
M.LAUNCHER_LEFT_CLICK_ORDER = {
    "chars",
    "items",
    "gear",
    "currency",
    "reputations",
    "pve",
    "professions",
    "collections",
    "plans_tab",
    "stats",
    "vault",
    "saved",
    "plans",
    "settings",
}

--- Easy Access right-click menu only (classic shortcuts; not every main-window tab).
M.LAUNCHER_MENU_ORDER = {
    "chars",
    "pve",
    "vault",
    "saved",
    "plans",
    "settings",
}

---@class WnLauncherActionDef
---@field kind "main_tab"|"vault"|"saved_instances"|"plans_tracker"|"settings"
---@field tabKey string|nil main window tab for kind == main_tab
---@field labelKey string locale for menu row
---@field labelFallback string
---@field settingsLabelKey string|nil Settings > Easy Access left-click checkbox
---@field settingsDescKey string|nil
---@field iconTab string|nil `UI_GetTabIcon` key
---@field iconAtlas string|nil
---@field icon string|nil texture path fallback
---@field menuLeftClick boolean|nil false = row cannot be assigned as left-click target (Settings row)

M.LAUNCHER_ACTION_DEFS = {
    chars = {
        kind = "main_tab", tabKey = "chars",
        labelKey = "TAB_CHARACTERS", labelFallback = "Characters",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_CHARS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_CHARS_DESC",
        iconTab = "characters",
    },
    items = {
        kind = "main_tab", tabKey = "items",
        labelKey = "TAB_ITEMS", labelFallback = "Bank",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_ITEMS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_ITEMS_DESC",
        iconTab = "items",
    },
    gear = {
        kind = "main_tab", tabKey = "gear",
        labelKey = "TAB_GEAR", labelFallback = "Gear",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_GEAR", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_GEAR_DESC",
        iconTab = "gear",
    },
    currency = {
        kind = "main_tab", tabKey = "currency",
        labelKey = "TAB_CURRENCIES", labelFallback = "Currencies",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_CURRENCY", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_CURRENCY_DESC",
        iconTab = "currency",
    },
    reputations = {
        kind = "main_tab", tabKey = "reputations",
        labelKey = "TAB_REPUTATIONS", labelFallback = "Reputations",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_REPUTATIONS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_REPUTATIONS_DESC",
        iconTab = "reputations",
    },
    pve = {
        kind = "main_tab", tabKey = "pve",
        labelKey = "TAB_PVE", labelFallback = "PvE",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_PVE", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_PVE_DESC",
        iconTab = "pve",
    },
    professions = {
        kind = "main_tab", tabKey = "professions",
        labelKey = "TAB_PROFESSIONS", labelFallback = "Professions",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_PROFESSIONS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_PROFESSIONS_DESC",
        iconTab = "professions",
    },
    collections = {
        kind = "main_tab", tabKey = "collections",
        labelKey = "TAB_COLLECTIONS", labelFallback = "Collections",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_COLLECTIONS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_COLLECTIONS_DESC",
        iconTab = "collections",
    },
    plans_tab = {
        kind = "main_tab", tabKey = "plans",
        labelKey = "TAB_PLANS", labelFallback = "To-Do",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_PLANS_TAB", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_PLANS_TAB_DESC",
        iconTab = "plans",
    },
    stats = {
        kind = "main_tab", tabKey = "stats",
        labelKey = "TAB_STATISTICS", labelFallback = "Statistics",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_STATS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_STATS_DESC",
        iconTab = "stats",
    },
    vault = {
        kind = "vault",
        labelKey = "VAULT_BUTTON_MENU_TRACKER", labelFallback = "Vault Tracker",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_VAULT", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_VAULT_DESC",
        iconAtlas = "GreatVault-32x32",
        icon = "Interface\\Icons\\Achievement_Boss_Argus",
    },
    saved = {
        kind = "saved_instances",
        labelKey = "VAULT_BUTTON_MENU_SAVED", labelFallback = "Saved Instances",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_SAVED", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_SAVED_DESC",
        icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
    },
    plans = {
        kind = "plans_tracker",
        labelKey = "VAULT_BUTTON_MENU_PLANS", labelFallback = "Plans / Todo",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_PLANS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_PLANS_DESC",
        iconTab = "plans",
    },
    settings = {
        kind = "settings",
        labelKey = "VAULT_BUTTON_MENU_SETTINGS", labelFallback = "Settings",
        settingsLabelKey = "CONFIG_VAULT_LEFT_CLICK_SETTINGS", settingsDescKey = "CONFIG_VAULT_LEFT_CLICK_SETTINGS_DESC",
        iconAtlas = "mechagon-projects",
        icon = "Interface\\Icons\\Trade_Engineering",
        menuLeftClick = false,
    },
}

function M.GetLauncherActionLabel(actionId)
    local def = M.LAUNCHER_ACTION_DEFS[actionId]
    if not def then return actionId or "?" end
    return EAL(def.labelKey, def.labelFallback)
end

function M.GetLauncherLeftClickLookup()
    if LAUNCHER_LEFT_CLICK_LOOKUP then return LAUNCHER_LEFT_CLICK_LOOKUP end
    local t = {}
    for i = 1, #LAUNCHER_LEFT_CLICK_ORDER do
        t[LAUNCHER_LEFT_CLICK_ORDER[i]] = true
    end
    LAUNCHER_LEFT_CLICK_LOOKUP = t
    return t
end

function M.IsAllowedLeftClickAction(actionId)
    if not actionId or actionId == "" then return false end
    return M.GetLauncherLeftClickLookup()[actionId] == true
end

function M.NormalizeLeftClickAction(actionId)
    if M.IsAllowedLeftClickAction(actionId) then return actionId end
    return "pve"
end

function M.GetMinimapSettings()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then
        return { leftClickAction = "toggle" }
    end
    local profile = WarbandNexus.db.profile
    profile.minimap = profile.minimap or {}
    local settings = profile.minimap
    if settings.leftClickAction == nil then
        settings.leftClickAction = "toggle"
    end
    if settings.leftClickAction ~= "toggle" and not M.IsAllowedLeftClickAction(settings.leftClickAction) then
        settings.leftClickAction = "toggle"
    end
    return settings
end

function M.NormalizeMinimapLeftClickAction(actionId)
    if actionId == "toggle" then return "toggle" end
    if M.IsAllowedLeftClickAction(actionId) then return actionId end
    return "toggle"
end

M.EA_DISPLAY_DEFAULTS = {
    tooltipVault = true,
    tooltipGold = true,
    tooltipTodo = true,
    tooltipBounty = true,
    tooltipVoidcore = true,
    tooltipGildedStash = false,
    tooltipManaflux = false,
    tooltipKeystone = true,
    tooltipMythicScore = true,
    menuVault = true,
    menuKeystone = true,
    menuMythicScore = false,
}

function M.EnsureDisplaySettings(settings)
    settings.display = settings.display or {}
    for key, defaultVal in pairs(EA_DISPLAY_DEFAULTS) do
        if settings.display[key] == nil then
            settings.display[key] = defaultVal
        end
    end
end
ns.EnsureVaultButtonDisplaySettings = M.EnsureDisplaySettings

function M.GetSettings()
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then
        local settings = {
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
            display = {},
        }
        EnsureDisplaySettings(settings)
        return settings
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
    settings.leftClickAction = M.NormalizeLeftClickAction(settings.leftClickAction)
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
    EnsureDisplaySettings(settings)

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

function M.ShowEasyAccessDisplay(key)
    local display = GetSettings().display
    if not display or display[key] == nil then
        return EA_DISPLAY_DEFAULTS[key] ~= false
    end
    return display[key] == true
end

--- Locale helper for Easy Access tooltips (must be above all EAL callers in this file).
function M.EAL(key, fallback, ...)
    local fmt = (ns.L and ns.L[key]) or fallback
    if select("#", ...) > 0 then
        return string.format(fmt, ...)
    end
    return fmt
end

function M.GetEnabledCategoryDefs()
    local settings = GetSettings()
    local columns = settings.columns or {}
    local width = settings.showRewardProgress and settings.showRewardItemLevel and COL_REWARD_PROGRESS
        or (settings.showRewardProgress and COL_PROGRESS)
        or (settings.showRewardItemLevel and COL_REWARD_ILVL or nil)
        or ns.ResolveVaultTrackerColumnWidth(settings.showRewardProgress, settings.showRewardItemLevel)
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

--- Column boundary X positions for Vault Tracker grid separators (matches header/row layout).
function M.BuildVaultTableColumnDividerXs(catDefs, columns)
    local xs = {}
    local x = COL_NAME
    xs[#xs + 1] = x
    x = x + COL_ILVL
    for ci = 1, #catDefs do
        xs[#xs + 1] = x
        x = x + catDefs[ci].width
    end
    if columns.bounty ~= false then
        xs[#xs + 1] = x
        x = x + COL_BOUNTY
    end
    if columns.gildedStash == true then
        xs[#xs + 1] = x
        x = x + COL_STASH
    end
    if columns.voidcore ~= false then
        xs[#xs + 1] = x
        x = x + COL_VOIDCORE
    end
    if columns.manaflux == true then
        xs[#xs + 1] = x
        x = x + COL_MANAFLUX
    end
    return xs
end

function M.GetTableWidth()
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

function M.GetPveCache()
    return WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
        and WarbandNexus.db.global.pveCache or nil
end

function M.GetCharacters()
    return WarbandNexus and WarbandNexus.db and WarbandNexus.db.global
        and WarbandNexus.db.global.characters or nil
end

function M.GetSavedPos()
    return GetSettings().position
end

function M.SavePos(point, relativePoint, x, y)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return end
    local settings = GetSettings()
    settings.position = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

function M.GetSavedTablePos()
    return GetSettings().tablePosition
end

function M.SaveTablePos(point, relativePoint, x, y)
    if not WarbandNexus or not WarbandNexus.db or not WarbandNexus.db.profile then return end
    local settings = GetSettings()
    settings.tablePosition = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = x or 0,
        y = y or 0,
    }
end

M.state = M.state or {
    button=nil, icon=nil, badge=nil, badgeBg=nil, border=nil,
    tableFrame=nil, title=nil, headerBg=nil, separator=nil,
    optionsFrame=nil, optionsWidgets={}, rows={},
    menuFrame=nil, savedFrame=nil, savedRows={}, savedExpanded={}, savedInstanceCollapsed={},
    savedGroupCollapsed={},
    eaTooltipHover=nil,
    vaultShiftWatcher=nil,
    vaultSlotProgressBindings=nil,
    vaultColumnBindings=nil,
    vaultColumnCellBindings=nil,
}

do
    local st = M.state
    if not st.eaTooltipHover then
        st.eaTooltipHover = { anchor = nil, charKey = nil, entry = nil }
    end
    local weakKeys = { __mode = "k" }
    if not st.vaultSlotProgressBindings then
        st.vaultSlotProgressBindings = setmetatable({}, weakKeys)
        st.vaultColumnBindings = setmetatable({}, weakKeys)
        st.vaultColumnCellBindings = setmetatable({}, weakKeys)
    end
end

