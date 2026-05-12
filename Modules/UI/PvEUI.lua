--[[
    Warband Nexus - PvE Progress Tab
    Display Great Vault, Mythic+ keystones, and Raid lockouts for all characters
    
    DATA FLOW ARCHITECTURE (CACHE-FIRST):
    ==========================================
    1. PvECacheService: Event-driven data collection (WEEKLY_REWARDS_UPDATE, MYTHIC_PLUS_*, etc.)
    2. Database: Persistent storage (db.global.pveCache)
    3. UI (this file): Reads from cache via GetPvEData(charKey)
    
    ACCEPTABLE API CALLS (UI-only):
    - C_DateAndTime.GetSecondsUntilWeeklyReset() - Fallback for weekly reset timer
    - C_ChallengeMode.GetMapUIInfo() - Dungeon name/icon (not cached, static data)
    - C_CurrencyInfo.GetCurrencyInfo() - Currency details for display (Midnight)
    - C_Item.GetItemIconByID() - Trovehunter's Bounty icon for Bountiful column header
    
    DEPRECATED API CALLS (Moved to PvECacheService):
    - C_MythicPlus.GetOwnedKeystoneLevel() → Use pveData.keystone.level
    - C_MythicPlus.GetOwnedKeystoneChallengeMapID() → Use pveData.keystone.mapID
    - C_MythicPlus.GetCurrentAffixes() → Use allPveData.currentAffixes
    - C_WeeklyRewards.GetActivities() → Use pveData.vaultActivities
    
    Event Registration: WN_PVE_UPDATED (auto-refresh UI when cache updates)
]]

local ADDON_NAME, ns = ...

local issecretvalue = issecretvalue

local function SafeLower(s)
    if not s or s == "" then return "" end
    if issecretvalue and issecretvalue(s) then return "" end
    return s:lower()
end

local function CompareCharNameLower(a, b)
    return SafeLower(a.name) < SafeLower(b.name)
end

-- Unique AceEvent handler identity for PvEUI
local PvEUIEvents = {}
local E = ns.Constants.EVENTS
local WarbandNexus = ns.WarbandNexus
local FontManager = ns.FontManager  -- Centralized font management

-- Tooltip API
local ShowTooltip = ns.UI_ShowTooltip
local HideTooltip = ns.UI_HideTooltip

-- Import shared UI components (always get fresh reference)
local CreateCard = ns.UI_CreateCard
local CreateCollapsibleHeader = ns.UI_CreateCollapsibleHeader
local BuildAccordionVisualOpts = ns.UI_BuildAccordionVisualOpts
local DrawEmptyState = ns.UI_DrawEmptyState
local CreateEmptyStateCard = ns.UI_CreateEmptyStateCard
local HideEmptyStateCard = ns.UI_HideEmptyStateCard
local CreateThemedButton = ns.UI_CreateThemedButton
local CreateThemedCheckbox = ns.UI_CreateThemedCheckbox
local CreateIcon = ns.UI_CreateIcon
local CreateDBVersionBadge = ns.UI_CreateDBVersionBadge
local ApplyVisuals = ns.UI_ApplyVisuals  -- For border re-application
local FormatNumber = ns.UI_FormatNumber
local COLORS = ns.UI_COLORS

-- Import shared UI layout constants
local function GetLayout() return ns.UI_LAYOUT or {} end
local ROW_HEIGHT = GetLayout().rowHeight or 26
local ROW_SPACING = GetLayout().rowSpacing or 28
local HEADER_SPACING = GetLayout().headerSpacing or 44
local SECTION_SPACING = GetLayout().SECTION_SPACING or 8
local BASE_INDENT = GetLayout().BASE_INDENT or 15
local SUBROW_EXTRA_INDENT = GetLayout().SUBROW_EXTRA_INDENT or 10
local SIDE_MARGIN = GetLayout().sideMargin or 10
local TOP_MARGIN = GetLayout().topMargin or 8

-- PvE inline grid: min width for horizontal scroll + columnHeaderInner (see ProfessionsUI / UI.lua).
-- Left prefix through iLvl matches Characters row chrome (see PvE_ComputeCharacterRowPrefixToGoldPx).
local PVE_CHAR_HEADER_H_MARGIN = 20                -- char row inset 10 + 10
local PVE_COLUMN_HEADER_PAD = 2
local PVE_COL_SPACING = 6                        -- uniform baseline spacing for symmetric header rhythm
local PVE_KEY_TO_VAULT_GAP = 8                   -- currency block ↔ vault block
local PVE_VAULT_CLUSTER_GAP = 8                  -- Raid | Dungeon | World internal spacing
local PVE_COL_RIGHT_MARGIN = 8
local PVE_DAWNCREST_COL_W = 128                  -- qty/max (R:rem)
local PVE_COFFER_COL_W = 148
local PVE_KEY_COL_W = 100
local PVE_VAULT_COL_W = 92                       -- keep Raid/Dungeon/World header labels untruncated
local PVE_BOUNTIFUL_COL_W = 64                   -- enough for "Map" label under icon
local PVE_STATUS_COL_W    = 150                  -- enough for "N Slots Ready" values
local PVE_VOIDCORE_COL_W = 72
local PVE_MANAFLUX_COL_W = 72
local PVE_VOIDCORE_ID = 3418
local PVE_MANAFLUX_ID = 3378

-- Great Vault slot glyphs — match Modules/VaultButton.lua SlotSymbols (12×12).
local VAULT_SLOT_CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t"
local VAULT_SLOT_CROSS = "|TInterface\\RaidFrame\\ReadyCheck-NotReady:12:12:0:0|t"
local VAULT_SLOT_UPARROW = "|A:loottoast-arrow-green:12:12|a"

local UI_GetAccentHexColor = ns.UI_GetAccentHexColor

local function GetLocalizedText(key, fallback)
    local L = ns.L
    local value = L and L[key]
    if type(value) == "string" and value ~= "" and value ~= key then
        return value
    end
    return fallback
end

local function GetLowLevelHideThreshold(profile)
    if not profile then return 0 end
    local threshold = tonumber(profile.hideLowLevelThreshold) or 0
    if threshold >= 90 then return 90 end
    if threshold >= 80 then return 80 end
    -- Backward compatibility for older boolean setting.
    if profile.hideLowLevelCharacters == true then
        return 80
    end
    return 0
end

local function GetLowLevelHideCycleNext(current)
    if current == 0 then return 80 end
    if current == 80 then return 90 end
    return 0
end

local function GetLowLevelHideLabel(threshold)
    if threshold == 90 then return GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") end
    if threshold == 80 then return GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") end
    return GetLocalizedText("HIDE_FILTER_STATE_OFF", "Off")
end

local function ApplyLowLevelHideThreshold(addon, threshold)
    local profile = addon and addon.db and addon.db.profile
    if not profile then return end
    local nextThreshold = tonumber(threshold) or 0
    if nextThreshold ~= 80 and nextThreshold ~= 90 then
        nextThreshold = 0
    end
    profile.hideLowLevelThreshold = nextThreshold
    profile.hideLowLevelCharacters = (nextThreshold >= 80)
    local events = ns.Constants and ns.Constants.EVENTS
    if addon and addon.SendMessage and events and events.CHARACTER_TRACKING_CHANGED then
        addon:SendMessage(events.CHARACTER_TRACKING_CHANGED, {
            source = "HideFilter",
            threshold = nextThreshold,
        })
    end
end

local function GetPvEDawnCrestColumnDefinitions()
    local crests = {}
    local MS1 = ns.Constants and ns.Constants.DAWNCREST_UI
    local ordered = MS1 and MS1.COLUMN_IDS
    local labels = MS1 and MS1.PVE_LABEL_KEYS
    if ordered and labels then
        for i = 1, #ordered do
            local id = ordered[i]
            crests[#crests + 1] = { id = id, labelKey = labels[id] }
        end
    else
        crests = {
            { id = 3383, labelKey = "PVE_CREST_ADV" },
            { id = 3341, labelKey = "PVE_CREST_VET" },
            { id = 3343, labelKey = "PVE_CREST_CHAMP" },
            { id = 3345, labelKey = "PVE_CREST_HERO" },
            { id = 3347, labelKey = "PVE_CREST_MYTH" },
        }
    end
    return crests
end

--- Session caches: DrawPvEProgress runs on every PopulateContent — skip repeated pairs(all currencies) and duplicate GetCurrencyInfo.
local _pveDelveCurrencyCache = {
    finishedScan = false,
    shardsID = nil,
    keyID = nil,
    shardsIcon = nil,
    keyIcon = nil,
}
local _pveCurrencyInfoDisplayCache = {}

--- DrawPvEProgress runs often; reuse FontStrings / measurement for column headers and per-character summary cells.
local _pveDrawPool = {
    holder = nil,
    rosterSig = nil,
    colSig = nil,
    nameWidths = {},
    measureFs = nil,
    headerLabels = {},
    inline = {}, -- [charKey] = { [colKey] = { fs = FontString, hit = Frame? } }
}

local function PvE_EnsureDrawPoolHolder()
    local h = _pveDrawPool.holder
    if not h then
        h = CreateFrame("Frame", nil, UIParent)
        h:Hide()
        _pveDrawPool.holder = h
    end
    return h
end

local function PvESyncPvEPools(rosterSig, colSig, currentKeySet, visibleColKeys)
    local pool = _pveDrawPool
    local holder = PvE_EnsureDrawPoolHolder()
    if pool.rosterSig ~= rosterSig then
        for charKey, byCol in pairs(pool.inline) do
            if not currentKeySet[charKey] then
                if byCol then
                    for _, cell in pairs(byCol) do
                        if cell.fs then
                            cell.fs:Hide()
                            cell.fs:SetParent(holder)
                        end
                        if cell.hit then
                            cell.hit:Hide()
                            cell.hit:SetParent(holder)
                            cell.hit:SetScript("OnEnter", nil)
                            cell.hit:SetScript("OnLeave", nil)
                            cell.hit:SetScript("OnMouseUp", nil)
                        end
                    end
                end
                pool.inline[charKey] = nil
            end
        end
        for k in pairs(pool.nameWidths) do
            if not currentKeySet[k] then
                pool.nameWidths[k] = nil
            end
        end
        pool.rosterSig = rosterSig
    end
    if pool.colSig ~= colSig then
        for colKey, fs in pairs(pool.headerLabels) do
            if not visibleColKeys[colKey] then
                fs:Hide()
                fs:SetParent(holder)
            end
        end
        for _, byCol in pairs(pool.inline) do
            if byCol then
                for colKey, cell in pairs(byCol) do
                    if not visibleColKeys[colKey] then
                        if cell.fs then
                            cell.fs:Hide()
                            cell.fs:SetParent(holder)
                        end
                        if cell.hit then
                            cell.hit:Hide()
                            cell.hit:SetParent(holder)
                            cell.hit:SetScript("OnEnter", nil)
                            cell.hit:SetScript("OnLeave", nil)
                            cell.hit:SetScript("OnMouseUp", nil)
                        end
                        byCol[colKey] = nil
                    end
                end
            end
        end
        pool.colSig = colSig
    end
end

local function PvE_GetDrawPoolMeasureFS()
    local pool = _pveDrawPool
    if not pool.measureFs then
        pool.measureFs = FontManager:CreateFontString(PvE_EnsureDrawPoolHolder(), "body", "OVERLAY")
        pool.measureFs:Hide()
    end
    return pool.measureFs
end

local function PvEAcquireColHeaderLabel(colHeaderRow, colKey, hitFrame, compactLabel, compactHex, colWidth)
    local pool = _pveDrawPool
    local fs = pool.headerLabels[colKey]
    if not fs then
        fs = FontManager:CreateFontString(colHeaderRow, "bodySmall", "OVERLAY")
        pool.headerLabels[colKey] = fs
        fs._pvePooledHeaderLabel = true
    else
        fs:SetParent(colHeaderRow)
        fs:Show()
    end
    fs:SetPoint("TOP", hitFrame, "BOTTOM", 0, 0)
    fs:SetWidth(math.max(24, colWidth - 4))
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    fs:SetText("|cff" .. (compactHex or "ffffff") .. compactLabel .. "|r")
    fs:SetShadowOffset(1, -1)
    fs:SetShadowColor(0, 0, 0, 0.9)
    return fs
end

local function PvEAcquireInlineCell(charHeader, charKey, colKey)
    local pool = _pveDrawPool
    local byCol = pool.inline[charKey]
    if not byCol then
        byCol = {}
        pool.inline[charKey] = byCol
    end
    local cell = byCol[colKey]
    if not cell then
        cell = {}
        cell.fs = FontManager:CreateFontString(charHeader, "body", "OVERLAY")
        cell.fs._pvePooledInline = true
        byCol[colKey] = cell
    else
        cell.fs:SetParent(charHeader)
        cell.fs:Show()
    end
    return cell
end

local function GetPvECachedCurrencyDisplay(id)
    if not id then return nil end
    local hit = _pveCurrencyInfoDisplayCache[id]
    if hit ~= nil then
        if hit == false then return nil end
        return hit
    end
    if not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo) then
        _pveCurrencyInfoDisplayCache[id] = false
        return nil
    end
    local info = C_CurrencyInfo.GetCurrencyInfo(id)
    if not info then
        _pveCurrencyInfoDisplayCache[id] = false
        return nil
    end
    local t = { iconFileID = info.iconFileID, name = info.name }
    _pveCurrencyInfoDisplayCache[id] = t
    return t
end

local function ResolvePveDelveCurrencyColumns(addon)
    local c = _pveDelveCurrencyCache
    if c.finishedScan then return end
    if not addon or not addon.GetCurrenciesForUI then
        c.finishedScan = true
        return
    end
    local allCurrencies = addon:GetCurrenciesForUI()
    local anyEntry = false
    for currencyID, entry in pairs(allCurrencies) do
        anyEntry = true
        local rawName = entry and entry.name
        local lowerName = ""
        if rawName and not (issecretvalue and issecretvalue(rawName)) then
            lowerName = string.lower(rawName)
        end
        if lowerName ~= "" then
            if not c.shardsID and lowerName:find("coffer") and lowerName:find("shard") then
                c.shardsID = currencyID
                if entry.icon then c.shardsIcon = entry.icon end
            end
            if not c.keyID and lowerName:find("coffer") and lowerName:find("key") and lowerName:find("restored") then
                c.keyID = currencyID
                if entry.icon then c.keyIcon = entry.icon end
            end
        end
    end
    if anyEntry then
        c.finishedScan = true
    end
end

--- One-time merge: legacy profile.pveVisibleColumns.{bountiful,voidcore,manaflux} -> vaultButton.columns
local function MigrateLegacyPvEColumnsToVault(profile)
    if not profile or not profile.pveVisibleColumns then return end
    local ex = profile.pveVisibleColumns
    if ex._vaultColumnMergeDone then return end
    profile.vaultButton = profile.vaultButton or {}
    local vb = profile.vaultButton
    vb.columns = vb.columns or {}
    local c = vb.columns
    if ex.bountiful ~= nil then c.bounty = ex.bountiful ~= false end
    if ex.voidcore ~= nil then c.voidcore = ex.voidcore ~= false end
    if ex.manaflux ~= nil then
        c.manaflux = ex.manaflux == true
        vb.showManaflux = c.manaflux
    end
    ex._vaultColumnMergeDone = true
end

--- Defaults mirror Modules/VaultButton.lua GetSettings().columns
local function EnsureVaultButtonColumnsForPvE(profile)
    if not profile then return {} end
    profile.vaultButton = profile.vaultButton or {}
    local vb = profile.vaultButton
    vb.columns = vb.columns or {}
    local c = vb.columns
    if c.raids == nil then c.raids = true end
    if c.mythicPlus == nil then c.mythicPlus = true end
    if c.world == nil then c.world = true end
    if c.bounty == nil then c.bounty = true end
    if c.voidcore == nil then c.voidcore = true end
    if c.manaflux == nil then c.manaflux = vb.showManaflux == true end
    if c.status == nil then c.status = true end  -- Vault status (Ready/Slots/Pending) on PvE tab
    vb.showManaflux = c.manaflux == true
    MigrateLegacyPvEColumnsToVault(profile)
    return c
end

--- PvE-only inline columns (crests / coffer / restored key). Vault tracks share vaultButton.columns.
local function EnsurePvEExtraVisibleColumns(profile)
    if not profile then return {} end
    profile.pveVisibleColumns = profile.pveVisibleColumns or {}
    local ex = profile.pveVisibleColumns
    MigrateLegacyPvEColumnsToVault(profile)
    if ex.coffer_shards == nil then ex.coffer_shards = true end
    if ex.restored_key == nil then ex.restored_key = true end
    return ex
end

local function BuildPvEColumnKeySequence(profile)
    local seq = {}
    if not profile then return seq end
    local vc = EnsureVaultButtonColumnsForPvE(profile)
    local ex = EnsurePvEExtraVisibleColumns(profile)
    local crestDefs = GetPvEDawnCrestColumnDefinitions()
    for i = 1, #crestDefs do
        local id = crestDefs[i].id
        local k = "crest_" .. tostring(id)
        if ex[k] ~= false then
            seq[#seq + 1] = k
        end
    end
    if ex.coffer_shards ~= false then seq[#seq + 1] = "coffer_shards" end
    if ex.restored_key ~= false then seq[#seq + 1] = "restored_key" end
    if vc.voidcore ~= false then seq[#seq + 1] = "voidcore" end
    if vc.manaflux == true then seq[#seq + 1] = "manaflux" end
    if vc.raids ~= false then seq[#seq + 1] = "slot1" end
    if vc.mythicPlus ~= false then seq[#seq + 1] = "slot2" end
    if vc.world ~= false then seq[#seq + 1] = "slot3" end
    if vc.bounty ~= false then seq[#seq + 1] = "bountiful" end
    return seq
end

local function PvE_GetGapAfterColumnKey(leftKey, visibleKeySet)
    if leftKey == "slot1" or leftKey == "slot2" then return PVE_VAULT_CLUSTER_GAP end
    if leftKey == "slot3" then return PVE_KEY_TO_VAULT_GAP end
    if leftKey == "manaflux" then return PVE_KEY_TO_VAULT_GAP end
    if leftKey == "voidcore" and (not visibleKeySet.manaflux) then return PVE_KEY_TO_VAULT_GAP end
    if leftKey == "restored_key" and (not visibleKeySet.voidcore) and (not visibleKeySet.manaflux) then
        return PVE_KEY_TO_VAULT_GAP
    end
    return PVE_COL_SPACING
end

-- PvE Columns dropdown: fullscreen dialog layer for interactive menus (avoid tooltip strata misuse).
local PVE_COLUMN_PICKER_STRATA = "FULLSCREEN_DIALOG"
local PVE_COLUMN_PICKER_MENU_LEVEL = 5100
local PVE_COLUMN_PICKER_CATCHER_LEVEL = 5050

local function PvE_ColumnPickerHideTooltipLayers()
    if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end
    if HideTooltip then HideTooltip() end
end

local function PvE_ColumnPickerHideCatcher()
    local c = WarbandNexus._wnPvEColumnPickerCatcher
    if c and c:IsShown() then c:Hide() end
end

function WarbandNexus:HidePvEColumnPickerMenu()
    PvE_ColumnPickerHideCatcher()
    local m = WarbandNexus._wnPvEColumnPickerMenu
    if m then m:Hide() end
end

local function PvE_ColumnPickerPositionMenu(menu, anchorBtn)
    if not menu or not anchorBtn then return end
    menu:ClearAllPoints()
    menu:SetPoint("TOPRIGHT", anchorBtn, "BOTTOMRIGHT", 0, -4)
end

local function PvE_ColumnPickerShowCatcher(menu)
    local c = WarbandNexus._wnPvEColumnPickerCatcher
    if not c then
        c = CreateFrame("Button", "WarbandNexusPvEColumnPickerCatcher", UIParent)
        c:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
        c:SetFrameLevel(PVE_COLUMN_PICKER_CATCHER_LEVEL)
        c:SetAllPoints(UIParent)
        c:SetAlpha(0)
        c:EnableMouse(true)
        c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if c.SetPropagateMouseClicks then c:SetPropagateMouseClicks(false) end
        c:SetScript("OnClick", function()
            WarbandNexus:HidePvEColumnPickerMenu()
        end)
        WarbandNexus._wnPvEColumnPickerCatcher = c
    end
    c:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
    c:SetFrameLevel(PVE_COLUMN_PICKER_CATCHER_LEVEL)
    c:Show()
    menu:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
    menu:SetFrameLevel(PVE_COLUMN_PICKER_MENU_LEVEL)
    menu:Raise()
end

local function PvE_GetOrCreateColumnPickerMenu()
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateContainer then return nil end
    local m = WarbandNexus._wnPvEColumnPickerMenu
    if m then return m end
    local accent = COLORS.accent or { 0.40, 0.20, 0.58 }
    m = Factory:CreateContainer(UIParent, 292, 320, true)
    if not m then return nil end
    m:SetClampedToScreen(true)
    m:SetFrameStrata(PVE_COLUMN_PICKER_STRATA)
    m:SetFrameLevel(PVE_COLUMN_PICKER_MENU_LEVEL)
    m:EnableMouse(true)
    if ApplyVisuals then
        ApplyVisuals(m, { 0.02, 0.02, 0.03, 0.98 }, { accent[1], accent[2], accent[3], 1 })
    end
    m:Hide()
    WarbandNexus._wnPvEColumnPickerMenu = m
    return m
end

-- Forward declaration: referenced inside PvE_ColumnPickerPopulateMenu callback.
local PvE_ColumnPickerTryRefreshAfterDraw

--- Rebuild scroll contents from DB. Caller raises menu + catcher.
local function PvE_ColumnPickerPopulateMenu(menu, addon)
    local Factory = ns.UI and ns.UI.Factory
    if not menu or not Factory or not addon then return end

    local profile = addon.db and addon.db.profile
    if not profile then return end

    local accent = COLORS.accent or { 0.40, 0.20, 0.58 }
    local menuW = 292
    local menuPad = 6
    local scrollBarW = 22
    local ROW = 26
    local HEADER_H = 22

    local crestDefs = GetPvEDawnCrestColumnDefinitions()
    local toggleCount = #crestDefs + 8
    local contentH = HEADER_H + toggleCount * ROW + ROW + 10
    local viewportH = math.min(contentH, 300)
    local menuH = viewportH + menuPad * 2

    menu:SetSize(menuW, menuH)
    menu:SetParent(UIParent)

    local bin = ns.UI_RecycleBin
    local children = { menu:GetChildren() }
    for i = 1, #children do
        children[i]:Hide()
        if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
    end

    local scrollFrame = Factory:CreateScrollFrame(menu, "UIPanelScrollFrameTemplate", true)
    scrollFrame:SetPoint("TOPLEFT", menuPad, -menuPad)
    scrollFrame:SetPoint("BOTTOMRIGHT", -scrollBarW, menuPad)
    scrollFrame:EnableMouseWheel(true)

    local scrollBarColumn = Factory:CreateScrollBarColumn(menu, scrollBarW, menuPad, menuPad)
    if scrollFrame.ScrollBar and Factory.PositionScrollBarInContainer then
        Factory:PositionScrollBarInContainer(scrollFrame.ScrollBar, scrollBarColumn, 0)
    end

    local btnWidth = menuW - menuPad * 2 - scrollBarW
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(btnWidth)
    scrollChild:SetHeight(contentH)
    scrollFrame:SetScrollChild(scrollChild)

    if Factory.UpdateScrollBarVisibility then Factory:UpdateScrollBarVisibility(scrollFrame) end

    local columnHdr = FontManager:CreateFontString(scrollChild, "small", "OVERLAY")
    columnHdr:SetPoint("TOPLEFT", 14, -8)
    columnHdr:SetText(GetLocalizedText("COLUMNS_BUTTON", "Columns"))
    columnHdr:SetTextColor(accent[1], accent[2], accent[3], 1)
    if columnHdr.EnableMouse then columnHdr:EnableMouse(false) end

    local vc = EnsureVaultButtonColumnsForPvE(profile)
    local ex = EnsurePvEExtraVisibleColumns(profile)

    local function applyColumnPickerChange(vaultColTouched)
        if vaultColTouched and WarbandNexus.RefreshVaultButtonSettings then
            WarbandNexus:RefreshVaultButtonSettings()
        end
        PvE_ColumnPickerHideTooltipLayers()
        if addon and addon.SendMessage then
            addon:SendMessage(E.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
        end
        C_Timer.After(0, function()
            local picker = WarbandNexus._wnPvEColumnPickerMenu
            if not picker or not picker:IsShown() then return end
            local mf = WarbandNexus.mainFrame or (WarbandNexus.UI and WarbandNexus.UI.mainFrame)
            if not mf or mf.currentTab ~= "pve" then
                WarbandNexus:HidePvEColumnPickerMenu()
                return
            end
            PvE_ColumnPickerTryRefreshAfterDraw(WarbandNexus)
        end)
    end

    local function addCheckboxRow(y, labelText, isChecked, onToggle)
        local cb = CreateThemedCheckbox(scrollChild, isChecked)
        if not cb then return y end
        cb:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 14, y)
        cb:EnableMouse(true)
        local lbl = FontManager:CreateFontString(scrollChild, "body", "OVERLAY")
        lbl:SetPoint("LEFT", cb, "RIGHT", (ns.UI_SPACING and ns.UI_SPACING.AFTER_ELEMENT) or 6, 0)
        lbl:SetText(labelText)
        lbl:SetTextColor(1, 1, 1, 1)
        lbl:SetJustifyH("LEFT")
        if lbl.EnableMouse then lbl:EnableMouse(false) end
        local prevClick = cb:GetScript("OnClick")
        cb:SetScript("OnClick", function(self, ...)
            if prevClick then prevClick(self, ...) end
            onToggle(self:GetChecked() and true or false)
        end)
        return y - ROW
    end

    local y = -HEADER_H
    for i = 1, #crestDefs do
        local id = crestDefs[i].id
        local labelKey = crestDefs[i].labelKey
        local crestLabel = labelKey and GetLocalizedText(labelKey, GetLocalizedText("PVE_CREST_GENERIC", "Dawncrest")) or GetLocalizedText("PVE_CREST_GENERIC", "Dawncrest")
        local ck = "crest_" .. tostring(id)
        y = addCheckboxRow(y, crestLabel, ex[ck] ~= false, function(checked)
            ex[ck] = checked
            applyColumnPickerChange(false)
        end)
    end

    y = addCheckboxRow(y, (ns.L and ns.L["PVE_COL_COFFER_SHARDS"]) or "Coffer Shards", ex.coffer_shards ~= false, function(checked)
        ex.coffer_shards = checked
        applyColumnPickerChange(false)
    end)

    y = addCheckboxRow(y, (ns.L and ns.L["PVE_COL_RESTORED_KEY"]) or "Restored Key", ex.restored_key ~= false, function(checked)
        ex.restored_key = checked
        applyColumnPickerChange(false)
    end)

    y = addCheckboxRow(y, GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"), vc.raids ~= false, function(checked)
        vc.raids = checked
        applyColumnPickerChange(true)
    end)

    y = addCheckboxRow(y, GetLocalizedText("VAULT_DUNGEON", "Dungeon"), vc.mythicPlus ~= false, function(checked)
        vc.mythicPlus = checked
        applyColumnPickerChange(true)
    end)

    y = addCheckboxRow(y, GetLocalizedText("VAULT_SLOT_WORLD", "World"), vc.world ~= false, function(checked)
        vc.world = checked
        applyColumnPickerChange(true)
    end)

    y = addCheckboxRow(y, GetLocalizedText("BOUNTIFUL_DELVE", "Trovehunter's Bounty"), vc.bounty ~= false, function(checked)
        vc.bounty = checked
        applyColumnPickerChange(true)
    end)

    y = addCheckboxRow(y, GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"), vc.voidcore ~= false, function(checked)
        vc.voidcore = checked
        applyColumnPickerChange(true)
    end)

    y = addCheckboxRow(y, GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"), vc.manaflux == true, function(checked)
        vc.manaflux = checked
        profile.vaultButton = profile.vaultButton or {}
        profile.vaultButton.showManaflux = checked
        applyColumnPickerChange(true)
    end)

    local resetBtn = Factory:CreateButton(scrollChild, btnWidth - 28, ROW - 2, false)
    if resetBtn and ApplyVisuals then
        ApplyVisuals(resetBtn, { 0.08, 0.08, 0.10, 1 }, { accent[1], accent[2], accent[3], 0.5 })
    end
    if resetBtn then
        resetBtn:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 14, y - 4)
        local resetLbl = FontManager:CreateFontString(resetBtn, "small", "OVERLAY")
        resetLbl:SetPoint("CENTER", 0, 0)
        local hex = (UI_GetAccentHexColor and UI_GetAccentHexColor()) or "aaaaee"
        resetLbl:SetText("|cff" .. hex .. ((ns.L and ns.L["SHOW_ALL"]) or "Show All") .. "|r")
        if resetLbl.EnableMouse then resetLbl:EnableMouse(false) end
        resetBtn:SetScript("OnClick", function()
            for j = 1, #crestDefs do
                ex["crest_" .. tostring(crestDefs[j].id)] = true
            end
            ex.coffer_shards = true
            ex.restored_key = true
            vc.raids = true
            vc.mythicPlus = true
            vc.world = true
            vc.bounty = true
            vc.voidcore = true
            vc.manaflux = true
            profile.vaultButton = profile.vaultButton or {}
            profile.vaultButton.showManaflux = true
            applyColumnPickerChange(true)
        end)
        if Factory.ApplyHighlight then Factory:ApplyHighlight(resetBtn) end
    end
end

PvE_ColumnPickerTryRefreshAfterDraw = function(addon)
    local menu = WarbandNexus._wnPvEColumnPickerMenu
    local anchor = WarbandNexus._wnPvEColumnPickerAnchorBtn
    if not menu or not menu:IsShown() or not anchor or not addon then return end
    PvE_ColumnPickerPopulateMenu(menu, addon)
    PvE_ColumnPickerPositionMenu(menu, anchor)
    PvE_ColumnPickerHideTooltipLayers()
    menu:Show()
    PvE_ColumnPickerShowCatcher(menu)
end

--- Columns picker: Vault Tracker options styling (Factory container + scroll + themed toggles).
local function PvE_AttachInlineColumnPicker(titleCard, sortAnchor, addon)
    local Factory = ns.UI and ns.UI.Factory
    if not Factory or not Factory.CreateButton then return sortAnchor end

    local hideBtn = Factory:CreateButton(titleCard, 84, (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32, false)
    if ApplyVisuals then
        ApplyVisuals(hideBtn, { 0.12, 0.12, 0.15, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local hideBtnText = FontManager:CreateFontString(hideBtn, "body", "OVERLAY")
    hideBtnText:SetPoint("CENTER", 0, 0)
    hideBtnText:SetJustifyH("CENTER")
    hideBtnText:SetTextColor(0.9, 0.9, 0.9)
    hideBtnText:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"))
    if Factory.ApplyHighlight then Factory:ApplyHighlight(hideBtn) end
    hideBtn:SetPoint("RIGHT", sortAnchor, "LEFT", -8, 0)

    local function HideMenuClose()
        if hideBtn._menu and hideBtn._menu:IsShown() then hideBtn._menu:Hide() end
        if hideBtn._catcher and hideBtn._catcher:IsShown() then hideBtn._catcher:Hide() end
    end
    local function HideMenuApply(threshold, keepMenuOpen)
        ApplyLowLevelHideThreshold(addon, threshold)
        if not keepMenuOpen then
            HideMenuClose()
        end
    end
    local function HideMenuBuild()
        local menu = hideBtn._menu
        if not menu then
            menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetFrameLevel(5200)
            menu:SetSize(132, 66)
            menu:SetBackdrop({
                bgFile = "Interface\\Buttons\\WHITE8x8",
                edgeFile = "Interface\\Buttons\\WHITE8x8",
                edgeSize = 1,
                insets = { left = 0, right = 0, top = 0, bottom = 0 },
            })
            menu:SetBackdropColor(0.08, 0.08, 0.10, 0.98)
            menu:SetBackdropBorderColor(COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.75)
            hideBtn._menu = menu
        end
        local profile = addon and addon.db and addon.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        local options = {
            { value = 80, label = GetLocalizedText("HIDE_FILTER_LEVEL_80", "Level 80") },
            { value = 90, label = GetLocalizedText("HIDE_FILTER_LEVEL_90", "Level 90") },
        }
        local children = { menu:GetChildren() }
        local bin = ns.UI_RecycleBin
        for i = 1, #children do
            children[i]:Hide()
            if bin then children[i]:SetParent(bin) else children[i]:SetParent(nil) end
        end
        local rowH = 30
        for i = 1, #options do
            local opt = options[i]
            local row = CreateFrame("Button", nil, menu, "BackdropTemplate")
            row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * rowH)
            row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * rowH)
            row:SetHeight(rowH - 2)
            row:RegisterForClicks("LeftButtonUp")
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
            row:SetBackdropColor((opt.value == cur) and 0.16 or 0.10, (opt.value == cur) and 0.16 or 0.10, (opt.value == cur) and 0.20 or 0.10, 1)
            local cb = ns.UI_CreateThemedCheckbox and ns.UI_CreateThemedCheckbox(row, opt.value == cur)
            if not cb then return menu end
            cb:SetSize(16, 16)
            cb:SetPoint("LEFT", row, "LEFT", 6, 0)
            cb:EnableMouse(false)
            local fs = FontManager:CreateFontString(row, "body", "OVERLAY")
            fs:SetPoint("LEFT", cb, "RIGHT", 6, 0)
            fs:SetJustifyH("LEFT")
            fs:SetText(opt.label)
            fs:SetTextColor(1, 1, 1)
            row:SetScript("OnClick", function()
                local active = GetLowLevelHideThreshold(addon and addon.db and addon.db.profile)
                local nextThreshold = (active == opt.value) and 0 or opt.value
                HideMenuApply(nextThreshold, true)
                HideMenuBuild()
            end)
        end
        return menu
    end
    hideBtn:SetScript("OnClick", function(self)
        local menu = hideBtn._menu
        if menu and menu:IsShown() then
            HideMenuClose()
            return
        end
        -- avoid overlap with columns menu
        WarbandNexus:HidePvEColumnPickerMenu()
        menu = HideMenuBuild()
        menu:ClearAllPoints()
        menu:SetPoint("TOPRIGHT", self, "BOTTOMRIGHT", 0, -4)
        menu:Show()
        local catcher = hideBtn._catcher
        if not catcher then
            catcher = CreateFrame("Button", nil, UIParent)
            catcher:SetAllPoints(UIParent)
            catcher:SetFrameStrata("FULLSCREEN_DIALOG")
            catcher:SetFrameLevel(5199)
            catcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            catcher:SetScript("OnClick", function(_, button)
                if menu and menu:IsShown() and not menu:IsMouseOver() and not hideBtn:IsMouseOver() then
                    HideMenuClose()
                end
            end)
            hideBtn._catcher = catcher
        end
        catcher:Show()
    end)
    hideBtn:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:SetText(GetLocalizedText("HIDE_FILTER_BUTTON", "Hide"), 1, 1, 1)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_TOGGLE", "Toggle filters: Level 80 / Level 90"), 0.8, 0.8, 0.8)
        local profile = addon and addon.db and addon.db.profile
        local cur = GetLowLevelHideThreshold(profile)
        GameTooltip:AddLine(GetLocalizedText("HIDE_FILTER_TOOLTIP_CURRENT", "Current: %s"):format(GetLowLevelHideLabel(cur)), 0.4, 1, 0.4)
        GameTooltip:Show()
    end)
    hideBtn:SetScript("OnLeave", function()
        if GameTooltip then GameTooltip:Hide() end
    end)

    local columnsBtn = Factory:CreateButton(titleCard, 86, (ns.UI_CONSTANTS and ns.UI_CONSTANTS.BUTTON_HEIGHT) or 32, false)
    if ApplyVisuals then
        ApplyVisuals(columnsBtn, { 0.12, 0.12, 0.15, 1 }, { COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.6 })
    end
    local columnsBtnText = FontManager:CreateFontString(columnsBtn, "body", "OVERLAY")
    columnsBtnText:SetPoint("CENTER", 0, 0)
    columnsBtnText:SetJustifyH("CENTER")
    columnsBtnText:SetText((ns.L and ns.L["COLUMNS_BUTTON"]) or "Columns")
    columnsBtnText:SetTextColor(0.9, 0.9, 0.9)
    if Factory.ApplyHighlight then Factory:ApplyHighlight(columnsBtn) end
    columnsBtn:SetPoint("RIGHT", hideBtn, "LEFT", -8, 0)

    WarbandNexus._wnPvEColumnPickerAnchorBtn = columnsBtn

    columnsBtn:SetScript("OnClick", function(btn)
        WarbandNexus._wnPvEColumnPickerAnchorBtn = btn
        local menu = WarbandNexus._wnPvEColumnPickerMenu
        if menu and menu:IsShown() then
            WarbandNexus:HidePvEColumnPickerMenu()
            return
        end

        menu = PvE_GetOrCreateColumnPickerMenu()
        if not menu then return end

        PvE_ColumnPickerPopulateMenu(menu, addon)
        PvE_ColumnPickerPositionMenu(menu, btn)
        PvE_ColumnPickerHideTooltipLayers()
        menu:Show()
        PvE_ColumnPickerShowCatcher(menu)
    end)

    return columnsBtn
end

--- Header icon for Bountiful column — Blizzard art from Trovehunter's Bounty item.
---@return number|string fileID from API, or texture path fallback
local function GetTrovehunterBountyColumnIcon()
    local Constants = ns.Constants
    local primary = (Constants and Constants.TROVEHUNTERS_BOUNTY_ITEM_ID) or 252415
    local alt = Constants and Constants.TROVEHUNTERS_BOUNTY_ITEM_ID_ALT
    if C_Item and C_Item.GetItemIconByID then
        local ok, fileID = pcall(C_Item.GetItemIconByID, primary)
        if ok and type(fileID) == "number" and fileID > 0 then
            return fileID
        end
        if alt and alt ~= primary then
            local ok2, fileID2 = pcall(C_Item.GetItemIconByID, alt)
            if ok2 and type(fileID2) == "number" and fileID2 > 0 then
                return fileID2
            end
        end
    end
    return "Interface\\Icons\\INV_10_WorldQuests_Scroll"
end

--- Minimum scrollChild width so inline columns do not overlap; enables horizontal scrollbar.
function ns.ComputePvEMinScrollWidth(self)
    if not self or not self.GetAllCharacters then return 0 end
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    local profile = self.db and self.db.profile
    local minLevel = GetLowLevelHideThreshold(profile)
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        local lvl = tonumber(char.level) or 0
        if char.isTracked ~= false and (minLevel == 0 or lvl >= minLevel) then
            characters[#characters + 1] = char
        end
    end
    local maxNameRealmWidth = 0
    local FM = ns.FontManager
    if FM and #characters > 0 then
        local tempMeasure = FM:CreateFontString(UIParent, "body", "OVERLAY")
        tempMeasure:Hide()
        for i = 1, #characters do
            local c = characters[i]
            local realmStr = ns.Utilities and ns.Utilities:FormatRealmName(c.realm) or c.realm or ""
            tempMeasure:SetText((c.name or "Unknown") .. "  -  " .. realmStr)
            local w = tempMeasure:GetStringWidth()
            if w and w > maxNameRealmWidth then maxNameRealmWidth = w end
        end
        tempMeasure:SetParent(nil)
    end
    local nameWidth = math.max(200, math.ceil(maxNameRealmWidth) + 8)
    local prefixW = (ns.PvE_ComputeCharacterRowPrefixToGoldPx and ns.PvE_ComputeCharacterRowPrefixToGoldPx(nameWidth)) or 400
    if not profile then return PVE_CHAR_HEADER_H_MARGIN + prefixW + PVE_COL_RIGHT_MARGIN end
    local columnSeq = BuildPvEColumnKeySequence(profile)
    local visibleKeySet = {}
    for i = 1, #columnSeq do
        visibleKeySet[columnSeq[i]] = true
    end

    local widthByKey = {
        coffer_shards = PVE_COFFER_COL_W,
        restored_key = PVE_KEY_COL_W,
        voidcore = PVE_VOIDCORE_COL_W,
        manaflux = PVE_MANAFLUX_COL_W,
        slot1 = PVE_VAULT_COL_W,
        slot2 = PVE_VAULT_COL_W,
        slot3 = PVE_VAULT_COL_W,
        bountiful = PVE_BOUNTIFUL_COL_W,
    }
    local inlineTotal = 0
    for i = 1, #columnSeq do
        local key = columnSeq[i]
        if key:find("^crest_") then
            inlineTotal = inlineTotal + PVE_DAWNCREST_COL_W
        else
            inlineTotal = inlineTotal + (widthByKey[key] or 0)
        end
    end

    for i = 1, #columnSeq - 1 do
        inlineTotal = inlineTotal + PvE_GetGapAfterColumnKey(columnSeq[i], visibleKeySet)
    end
    inlineTotal = inlineTotal + PVE_COL_RIGHT_MARGIN
    return PVE_CHAR_HEADER_H_MARGIN + prefixW + inlineTotal
end

-- Performance: Local function references
local format = string.format
local date = date

--- Tooltip / icon frames use EnableMouse and would block wheel; forward to main tab ScrollFrame.
local function BindForwardScrollWheel(frame)
    local fwd = ns.UI_ForwardMouseWheelToScrollAncestor
    if not frame or not fwd then return end
    frame:EnableMouseWheel(true)
    frame:SetScript("OnMouseWheel", function(self, delta)
        fwd(self, delta)
    end)
end

-- Expand/Collapse State Management
local expandedStates = {}

local function IsExpanded(key, defaultState)
    -- Check for Expand All override
    if WarbandNexus and WarbandNexus.pveExpandAllActive then
        return true
    end
    if expandedStates[key] == nil then
        expandedStates[key] = defaultState
    end
    return expandedStates[key]
end

-- PvE event refresh is centralized in UI.lua SchedulePopulateContent (WN_PVE_UPDATED).

--============================================================================
-- GREAT VAULT HELPER FUNCTIONS
--============================================================================

--[[
    Determine if a vault activity slot is at maximum completion level
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name ("Raid", "M+", "World", "PvP")
    @return boolean - True if at maximum level, false otherwise
]]
local function IsVaultSlotAtMax(activity, typeName)
    if not activity or not activity.level then
        return false
    end
    
    local level = activity.level
    
    -- Define max thresholds per activity type
    if typeName == "Raid" then
        -- DifficultyIDs: 14=Normal, 15=Heroic, 16=Mythic, 17=LFR
        return level == 16 -- Only Mythic is max
    elseif typeName == "M+" then
        -- For M+: 0=Mythic 0 (base mythic), 2+=Keystone level
        -- Max is keystone level 10 or higher
        return level >= 10
    elseif typeName == "World" then
        -- For World/Delves, Tier 8 is max
        return level >= 8
    elseif typeName == "PvP" then
        -- PvP has no tier progression
        return true
    end
    
    return false
end

--- Canonical PvE cache key for a character row (matches GetPvEData / pveCache writes).
local function PvE_GetCanonicalKeyForChar(char)
    if not char then return nil end
    local raw = char._key
    if (not raw or raw == "") and ns.Utilities and ns.Utilities.GetCharacterKey then
        raw = ns.Utilities:GetCharacterKey(char.name or "Unknown", char.realm or "Unknown")
    end
    if not raw or raw == "" then return nil end
    if ns.Utilities and ns.Utilities.GetCanonicalCharacterKey then
        return ns.Utilities:GetCanonicalCharacterKey(raw) or raw
    end
    return raw
end

--- Completed slot but reward can still improve (API iLvl or difficulty/M+ tier ceiling).
local function PvE_SlotShowsVaultUpgrade(act, typeName)
    if not act then return false end
    local ni = tonumber(act.nextLevelIlvl) or 0
    if ni > 0 then return true end
    local th = tonumber(act.threshold) or 0
    local prog = tonumber(act.progress) or 0
    if th <= 0 or prog < th then return false end
    if IsVaultSlotAtMax(act, typeName) then return false end
    return true
end

--- One vault column string (Raid / M+ / World). Slot glyphs match Vault Tracker table (12px + spaced).
local function PvE_FormatVaultTrackColumn(activityList, slotCount, typeName, vaultLootClaimable, _)
    local READY = VAULT_SLOT_CHECK
    local NOT_READY = VAULT_SLOT_CROSS
    local GREEN_ARROW = VAULT_SLOT_UPARROW
    local readyClaimLabel = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"
    if vaultLootClaimable then
        return "|cff44ff44" .. readyClaimLabel .. "|r"
    end
    slotCount = slotCount or 3
    if slotCount < 1 then slotCount = 3 end
    local parts = {}
    local hasIncomplete = false
    local hasUpgrade = false
    for s = 1, slotCount do
        local act = activityList and activityList[s]
        local th = tonumber(act and act.threshold) or 0
        local prog = tonumber(act and act.progress) or 0
        local complete = (th > 0 and prog >= th)
        if not complete then
            hasIncomplete = true
            parts[s] = NOT_READY
        elseif PvE_SlotShowsVaultUpgrade(act, typeName) then
            hasUpgrade = true
            parts[s] = GREEN_ARROW
        else
            parts[s] = READY
        end
    end
    if not hasIncomplete and not hasUpgrade and slotCount > 0 then
        local done = {}
        for s = 1, slotCount do
            done[s] = READY
        end
        return table.concat(done, " ")
    end
    return table.concat(parts, " ")
end

--- All slots in one vault track meet threshold (weekly objectives done for that row).
local function PvE_VaultTrackSlotsAllComplete(activityList, slotCount)
    slotCount = tonumber(slotCount) or 0
    if slotCount < 1 then return false end
    for s = 1, slotCount do
        local act = activityList and activityList[s]
        local th = tonumber(act and act.threshold) or 0
        local prog = tonumber(act and act.progress) or 0
        if th <= 0 or prog < th then
            return false
        end
    end
    return true
end

--- Raid + M+ + World tracks all slots complete (same idea as full vault grid filled).
local function PvE_AllVaultTracksComplete(vaultActs)
    if not vaultActs then return false end
    local raidT = vaultActs.raids and #vaultActs.raids or 3
    local dT = vaultActs.mythicPlus and #vaultActs.mythicPlus or 3
    local wT = vaultActs.world and #vaultActs.world or 3
    return PvE_VaultTrackSlotsAllComplete(vaultActs.raids, raidT)
        and PvE_VaultTrackSlotsAllComplete(vaultActs.mythicPlus, dT)
        and PvE_VaultTrackSlotsAllComplete(vaultActs.world, wT)
end

--[[
    Get reward item level from activity data or calculate fallback
    @param activity table - Activity data from Great Vault
    @return number|nil - Item level or nil if unavailable
]]
local function GetRewardItemLevel(activity)
    if not activity then
        return nil
    end
    
    -- Priority: Use rewardItemLevel field (extracted from C_WeeklyRewards.GetExampleRewardItemHyperlinks)
    if activity.rewardItemLevel and activity.rewardItemLevel > 0 then
        return activity.rewardItemLevel
    end
    
    return nil
end

--[[
    Get next tier/difficulty name for upgrade display
    @param activity table - Activity data from Great Vault
    @param typeName string - Activity type name
    @return string|nil - Next tier/difficulty name (e.g., "Tier 2", "+6", "Mythic")
]]
local function GetNextTierName(activity, typeName)
    if not activity or not activity.level then
        return nil
    end
    
    local currentLevel = activity.level
    
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local normalLabel = (ns.L and ns.L["DIFFICULTY_NORMAL"]) or "Normal"
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    
    -- World/Delves tier progression (Tier 1-8)
    if typeName == "World" then
        if currentLevel >= 8 then
            return nil -- Already at max (Tier 8)
        end
        return string.format(tierFmt, currentLevel + 1)
    end
    
    -- Raid difficulty progression: LFR(17) → Normal(14) → Heroic(15) → Mythic(16)
    if typeName == "Raid" then
        if currentLevel == 16 then
            return nil -- Already at Mythic (max)
        elseif currentLevel == 15 then
            return mythicLabel
        elseif currentLevel == 14 then
            return heroicLabel
        elseif currentLevel == 17 then
            return normalLabel
        end
    end
    
    -- M+ keystone progression: 0=Mythic 0, 2+=Keystone level → Tier X
    if typeName == "M+" or typeName == "Dungeon" then
        if currentLevel >= 10 then
            return nil
        end
        local nextLevel = currentLevel + 1
        if currentLevel == 0 then
            nextLevel = 2
        end
        return string.format(tierFmt, nextLevel)
    end
    
    return nil
end

--[[
    Get maximum tier/difficulty name
    @param typeName string - Activity type name
    @return string|nil - Max tier/difficulty name
]]
local function GetMaxTierName(typeName)
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    if typeName == "World" then
        return string.format(tierFmt, 8)
    elseif typeName == "Raid" then
        return (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    elseif typeName == "M+" or typeName == "Dungeon" then
        return string.format(tierFmt, 10)
    elseif typeName == "PvP" then
        return nil -- PvP has no progression
    end
    return nil
end

--[[
    Get display text for vault activity completion
    @param activity table - Activity data
    @param typeName string - Activity type name
    @return string - Display text for the activity (e.g., "Heroic", "+7", "Tier 1")
]]
local function GetVaultActivityDisplayText(activity, typeName)
    local unknownLabel = (ns.L and ns.L["UNKNOWN"]) or "Unknown"
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local normalLabel = (ns.L and ns.L["DIFFICULTY_NORMAL"]) or "Normal"
    local lfrLabel = (ns.L and ns.L["DIFFICULTY_LFR"]) or "LFR"
    local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
    local pvpLabel = (ns.L and ns.L["PVP_TYPE"]) or "PvP"
    
    if not activity then
        return unknownLabel
    end
    
    if typeName == "Raid" then
        local difficulty = unknownLabel
        if activity.level then
            -- Raid difficultyIDs: 14=Normal, 15=Heroic, 16=Mythic, 17=LFR
            -- CRITICAL: Use exact matches — LFR (17) > Mythic (16) by ID
            if activity.level == 16 then
                difficulty = mythicLabel
            elseif activity.level == 15 then
                difficulty = heroicLabel
            elseif activity.level == 14 then
                difficulty = normalLabel
            elseif activity.level == 17 then
                difficulty = lfrLabel
            end
        end
        return difficulty
    elseif typeName == "M+" or typeName == "Dungeon" then
        local level = activity.level or 0
        if level == 0 then
            return mythicLabel .. " 0"
        else
            return string.format(tierFmt, level)
        end
    elseif typeName == "World" then
        local tier = activity.level or 1
        return string.format(tierFmt, tier)
    elseif typeName == "PvP" then
        return pvpLabel
    end
    
    return typeName
end

--[[
    Build raid encounter lines for vault tooltips using cached GetActivityEncounterInfo data.
    Blizzard pattern: sorts by instanceID then uiOrder, groups by instance, shows bestDifficulty.
    @param lines table - Tooltip lines array to append to
    @param encounters table - Array of cached encounter info from PvECacheService
]]
local function BuildRaidEncounterLines(lines, encounters)
    if not encounters or #encounters == 0 then return end
    
    -- Sort: completed first within same instance, then by uiOrder (matches Blizzard EncountersSort)
    local sorted = {}
    for i = 1, #encounters do
        sorted[#sorted + 1] = encounters[i]
    end
    table.sort(sorted, function(a, b)
        if (a.instanceID or 0) ~= (b.instanceID or 0) then
            return (a.instanceID or 0) < (b.instanceID or 0)
        end
        local aCompleted = (a.bestDifficulty or 0) > 0
        local bCompleted = (b.bestDifficulty or 0) > 0
        if aCompleted ~= bCompleted then
            return aCompleted
        end
        return (a.uiOrder or 0) < (b.uiOrder or 0)
    end)
    
    local lastInstanceID = nil
    local encounterListLabel = (ns.L and ns.L["VAULT_ENCOUNTER_LIST_FORMAT"]) or "%s"
    for i = 1, #sorted do
        local enc = sorted[i]
        if (enc.instanceID or 0) ~= (lastInstanceID or 0) then
            table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
            local instName = enc.instanceName or ""
            table.insert(lines, {
                text = string.format("|cffffffcc" .. encounterListLabel .. "|r", instName),
                color = {1, 1, 0.8}
            })
            lastInstanceID = enc.instanceID
        end
        if enc.name then
            if (enc.bestDifficulty or 0) > 0 then
                local diffName = enc.difficultyName or "?"
                table.insert(lines, {
                    text = string.format("  |cff00ff00%s|r |cff888888(%s)|r", enc.name, diffName),
                    color = {0, 1, 0}
                })
            else
                table.insert(lines, {
                    text = string.format("  |cff666666- %s|r", enc.name),
                    color = {0.4, 0.4, 0.4}
                })
            end
        end
    end
end

--[[
    Fallback: Build raid boss lines from lockout data when GetActivityEncounterInfo isn't cached.
    Groups lockouts by instance, deduplicates bosses, shows highest difficulty per boss.
    @param lines table - Tooltip lines array to append to
    @param raidLockouts table - Array of raid lockout data from PvECacheService
]]
local DIFF_PRIORITY = { [16] = 4, [23] = 4, [15] = 3, [2] = 3, [14] = 2, [1] = 2, [17] = 1, [7] = 1 }
local function BuildRaidBossLinesFromLockouts(lines, raidLockouts)
    if not raidLockouts or #raidLockouts == 0 then return end

    local instances = {}
    local instanceOrder = {}
    for li = 1, #raidLockouts do
        local lockout = raidLockouts[li]
        if lockout.encounters and lockout.name then
            local instName = lockout.name
            if not instances[instName] then
                instances[instName] = {}
                instanceOrder[#instanceOrder + 1] = instName
            end
            local diff = lockout.difficultyName or "?"
            local prio = DIFF_PRIORITY[lockout.difficulty] or 0
            local bossMap = instances[instName]
            for ei = 1, #lockout.encounters do
                local enc = lockout.encounters[ei]
                if enc.name then
                    local existing = bossMap[enc.name]
                    if not existing then
                        bossMap[enc.name] = {
                            name = enc.name,
                            killed = enc.killed or false,
                            difficulty = diff,
                            priority = prio,
                            order = ei,
                        }
                    elseif enc.killed and (not existing.killed or prio > existing.priority) then
                        existing.killed = true
                        existing.difficulty = diff
                        existing.priority = prio
                    end
                end
            end
        end
    end

    local encounterListLabel = (ns.L and ns.L["VAULT_ENCOUNTER_LIST_FORMAT"]) or "%s"
    for ii = 1, #instanceOrder do
        local instName = instanceOrder[ii]
        local bossMap = instances[instName]
        if bossMap then
            local bossList = {}
            for _, boss in pairs(bossMap) do
                if type(boss) == "table" and boss.name then
                    bossList[#bossList + 1] = boss
                end
            end
            table.sort(bossList, function(a, b) return (a.order or 0) < (b.order or 0) end)
            if #bossList > 0 then
                table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                table.insert(lines, {
                    text = string.format("|cffffffcc" .. encounterListLabel .. "|r", instName),
                    color = {1, 1, 0.8}
                })
                for bi = 1, #bossList do
                    local boss = bossList[bi]
                    if boss.killed then
                        table.insert(lines, {
                            text = string.format("  |cff00ff00%s|r |cff888888(%s)|r", boss.name, boss.difficulty),
                            color = {0, 1, 0}
                        })
                    else
                        table.insert(lines, {
                            text = string.format("  |cff666666- %s|r", boss.name),
                            color = {0.4, 0.4, 0.4}
                        })
                    end
                end
            end
        end
    end
end

--[[
    Build dungeon run lines for vault tooltips using Blizzard pattern.
    Uses C_MythicPlus.GetRunHistory for keystone runs + GetNumCompletedDungeonRuns for non-keystone.
    @param lines table - Tooltip lines array to append to
    @param runHistory table|nil - Runs from PvECacheService (keystone only, sorted desc by level)
    @param dungeonRunCounts table|nil - {heroic, mythic, mythicPlus} from GetNumCompletedDungeonRuns
    @param threshold number - Number of top runs to show for this slot
]]
local function BuildDungeonRunLines(lines, runHistory, dungeonRunCounts, threshold)
    if threshold <= 0 then return end
    
    local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"
    local heroicLabel = (ns.L and ns.L["DIFFICULTY_HEROIC"]) or "Heroic"
    local topRunsLabel = (ns.L and ns.L["VAULT_TOP_RUNS_FORMAT"]) or "Top %d Runs This Week"
    
    table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
    table.insert(lines, {
        text = string.format("|cffffffcc" .. topRunsLabel .. "|r", threshold),
        color = {1, 1, 0.8}
    })
    
    -- Keystone runs (sorted descending by level)
    local runs = {}
    if runHistory then
        for ri = 1, #runHistory do
            runs[#runs + 1] = runHistory[ri]
        end
    end
    table.sort(runs, function(a, b)
        local aLvl = a.level or 0
        local bLvl = b.level or 0
        if aLvl ~= bLvl then return aLvl > bLvl end
        return (a.mapChallengeModeID or 0) < (b.mapChallengeModeID or 0)
    end)
    
    -- Show keystone runs (Blizzard pattern: level + dungeon name)
    local shown = 0
    for ri = 1, math.min(#runs, threshold) do
        local run = runs[ri]
        local dungeonName = run.dungeon or run.name or ""
        if not dungeonName or dungeonName == "" then
            if run.mapChallengeModeID and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
                dungeonName = C_ChallengeMode.GetMapUIInfo(run.mapChallengeModeID) or ""
            end
        end
        local lvl = run.level or 0
        local runText
        if lvl > 0 then
            runText = string.format("  |cffffffff+%d %s|r", lvl, dungeonName)
        else
            runText = string.format("  |cffffffff%s 0 %s|r", mythicLabel, dungeonName)
        end
        table.insert(lines, { text = runText, color = {1, 1, 1} })
        shown = shown + 1
    end
    
    -- Fill remaining slots with non-keystone runs (Mythic 0, Heroic) - Blizzard pattern
    local remaining = threshold - shown
    if remaining > 0 and dungeonRunCounts then
        local numMythic = dungeonRunCounts.mythic or 0
        local numHeroic = dungeonRunCounts.heroic or 0
        while numMythic > 0 and remaining > 0 do
            table.insert(lines, {
                text = string.format("  |cffffffff%s 0|r", mythicLabel),
                color = {1, 1, 1}
            })
            numMythic = numMythic - 1
            remaining = remaining - 1
        end
        while numHeroic > 0 and remaining > 0 do
            table.insert(lines, {
                text = string.format("  |cffffffff%s|r", heroicLabel),
                color = {1, 1, 1}
            })
            numHeroic = numHeroic - 1
            remaining = remaining - 1
        end
    end
end

--[[
    Build world/delve tier progress lines for vault tooltips using cached GetSortedProgressForActivity.
    Blizzard pattern: sorted descending by difficulty, shows tier and completion count.
    @param lines table - Tooltip lines array to append to
    @param worldTierProgress table|nil - Cached tier progress from PvECacheService
    @param threshold number - Desired number of runs to show
]]
local function BuildWorldProgressLines(lines, worldTierProgress, threshold)
    if not worldTierProgress or #worldTierProgress == 0 or threshold <= 0 then return end
    
    local topRunsLabel = (ns.L and ns.L["VAULT_TOP_RUNS_FORMAT"]) or "Top %d Runs This Week"
    local delveTierFmt = (ns.L and ns.L["VAULT_DELVE_TIER_FORMAT"]) or "Tier %d (%d)"
    
    table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
    table.insert(lines, {
        text = string.format("|cffffffcc" .. topRunsLabel .. "|r", threshold),
        color = {1, 1, 0.8}
    })
    
    local desiredRuns = threshold
    for wi = 1, #worldTierProgress do
        local tierProg = worldTierProgress[wi]
        local numRuns = math.min(tierProg.numPoints or 0, desiredRuns)
        if numRuns <= 0 then break end
        desiredRuns = desiredRuns - numRuns
        table.insert(lines, {
            text = string.format("  |cffffffff" .. delveTierFmt .. "|r", tierProg.difficulty or 0, numRuns),
            color = {1, 1, 1}
        })
    end
end

--- Paint the 3x3 Great Vault grid (Raid / Dungeon / World x 3 slots) on vaultCard.
--- Shared by expanded PvE summary vault card and Weekly Vault Tracker cards.
--- @return cardHeight, cardWidth
function WarbandNexus:PaintPvEVaultGridOnCard(vaultCard, opt)
    local baseCardWidth = opt.baseCardWidth
    local baseCardHeight = opt.baseCardHeight
    local vaultByType = opt.vaultByType
    local pve = opt.pve
    local vaultActivitiesData = opt.vaultActivitiesData
    local isCurrentChar = opt.isCurrentChar
    -- WVT: enable slot clicks + tooltips for every card (Great Vault is global); expanded row uses current char only.
    local vaultSlotInteract = (opt.enableVaultSlotInteraction == true) or isCurrentChar
    -- Weekly Vault Tracker: plain container + no extra chrome; tighter rows/slots optional.
    local applyVaultCardChrome = (opt.applyVaultCardChrome ~= false)
    local minSlotBtnH = opt.minSlotBtnH or 44
    local rowVPad = opt.vaultRowVPad
    if rowVPad == nil then rowVPad = 4 end
    local trackIconSize = opt.trackIconSize or 18
    local slotFontKey = opt.slotFontKey or "body"
    local rowLabelFontKey = opt.rowLabelFontKey or "body"
    local slotTierYOffset = opt.slotTierYOffset
    if slotTierYOffset == nil then slotTierYOffset = 7 end
    -- Weekly Vault Tracker: fewer nested borders — flat rows, soft separators, subtle hover (no per-slot ApplyVisuals).
    local compactSlotStyle = (opt.compactSlotStyle == true)

    local VAULT_LEFT_PAD  = 4
    local VAULT_RIGHT_PAD = 4
    local VAULT_COL_GAP   = 5   -- gap between columns
    local vaultColGap = opt.vaultColGap or VAULT_COL_GAP
    local leftPad = opt.vaultLeftPad or VAULT_LEFT_PAD
    local rightPad = opt.vaultRightPad or VAULT_RIGHT_PAD
    local VAULT_ROW_VPAD  = 4   -- row vertical padding (tighter = taller buttons)
    local borderPadding   = opt.borderPadding or 2
    local numRows         = 3
    local numCols         = 4   -- label + 3 slots

    local cardWidth = baseCardWidth
    local availableWidth  = cardWidth - (borderPadding * 2)
    local availableHeight = baseCardHeight - (borderPadding * 2)

    -- Compute one cell width, shared by ALL 4 columns
    local gapsTotal = leftPad + rightPad + vaultColGap * (numCols - 1)
    local VAULT_COL_W = math.floor((availableWidth - gapsTotal) / numCols)
    -- Alias for slot/label (they're identical)
    local VAULT_LABEL_W = VAULT_COL_W
    local VAULT_SLOT_W  = VAULT_COL_W

    local cellHeight = math.floor(availableHeight / numRows)
    local btnH       = math.max(minSlotBtnH, cellHeight - rowVPad * 2)

    local cardHeight = cellHeight * numRows + borderPadding * 2

    -- CRITICAL: Set card dimensions for proper border
    vaultCard:SetHeight(cardHeight)
    vaultCard:SetWidth(cardWidth)

    -- Re-apply border after dimension change (skip when painting onto a plain container — WVT outer card already framed)
    if ApplyVisuals and applyVaultCardChrome then
        local accentColor = COLORS.accent
        ApplyVisuals(vaultCard, {0.05, 0.05, 0.07, 0.95}, {accentColor[1], accentColor[2], accentColor[3], 0.6})
    end

    -- Default thresholds for each activity type (when no data exists)
    local defaultThresholds = {
        ["Raid"] = {2, 4, 6},
        ["Dungeon"] = {1, 4, 8},
        ["World"] = {3, 3, 3},
        ["PvP"] = {3, 3, 3}
    }

    -- Table Rows (3 ROWS - perfect grid alignment)
    local sortedTypes = {"Raid", "Dungeon", "World"}

    for rowIndex = 1, #sortedTypes do
        local typeName = sortedTypes[rowIndex]
        -- Map display name to actual data key
        local dataKey = typeName
        if typeName == "Dungeon" then
            dataKey = "M+"
        end
        local activities = vaultByType[dataKey]

        -- Calculate Y position (row 0, 1, 2) with border padding
        local rowY = borderPadding + ((rowIndex - 1) * cellHeight)

        -- Create row frame container (using Factory pattern)
        local rowFrame = ns.UI.Factory:CreateContainer(vaultCard)
        rowFrame:SetPoint("TOPLEFT", borderPadding, -rowY)
        rowFrame:SetSize(cardWidth - (borderPadding * 2), cellHeight)

        -- Row background
        if not rowFrame.bg then
            rowFrame.bg = rowFrame:CreateTexture(nil, "BACKGROUND")
            rowFrame.bg:SetAllPoints()
        end
        if compactSlotStyle then
            rowFrame.bg:SetColorTexture(0.09, 0.09, 0.11, 0.72)
        else
            rowFrame.bg:SetColorTexture(0.05, 0.05, 0.07, 0.95)
        end

        -- Track icon + label (left column, vertically centered)
        local trackIcons = {
            Raid    = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
            Dungeon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            World   = "Interface\\Icons\\INV_Misc_Map_01",
        }
        local trackIcon = rowFrame:CreateTexture(nil, "ARTWORK")
        trackIcon:SetSize(trackIconSize, trackIconSize)
        trackIcon:SetPoint("LEFT", rowFrame, "LEFT", leftPad, 0)
        trackIcon:SetTexture(trackIcons[typeName] or "Interface\\Icons\\INV_Misc_QuestionMark")
        trackIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

        local typeDisplayName = typeName
        if typeName == "Raid" then
            typeDisplayName = (ns.L and ns.L["VAULT_SLOT_RAIDS"]) or "Raids"
        elseif typeName == "Dungeon" then
            typeDisplayName = (ns.L and ns.L["VAULT_SLOT_DUNGEON"]) or "Dungeons"
        elseif typeName == "World" then
            typeDisplayName = (ns.L and ns.L["VAULT_WORLD"]) or "World"
        end
        local label = FontManager:CreateFontString(rowFrame, rowLabelFontKey, "OVERLAY")
        label:SetPoint("LEFT", trackIcon, "RIGHT", 5, 0)
        -- Icon + gap consumed; rest of the column is text
        label:SetWidth(VAULT_LABEL_W - (trackIconSize + 5))
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        label:SetText(string.format(compactSlotStyle and "|cffbbbbbb%s|r" or "|cffe8e8e8%s|r", typeDisplayName))

        -- Row separator line (except for first row)
        if rowIndex > 1 then
            local sep = rowFrame:CreateTexture(nil, "BORDER")
            sep:SetHeight(1)
            sep:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", leftPad, 0)
            sep:SetPoint("TOPRIGHT", rowFrame, "TOPRIGHT", -rightPad, 0)
            if compactSlotStyle then
                sep:SetColorTexture(0.22, 0.22, 0.28, 0.38)
            else
                sep:SetColorTexture(0.20, 0.20, 0.24, 0.6)
            end
        end

        -- Slot thresholds
        local thresholds = defaultThresholds[typeName] or {3, 3, 3}

        -- Vault toggle: click opens, click again closes
        local function OpenGreatVault()
            if WeeklyRewardsFrame and WeeklyRewardsFrame:IsShown() then
                WeeklyRewardsFrame:Hide()
                return
            end
            if InCombatLockdown() then return end
            local U = ns.Utilities
            if U and U.SafeLoadAddOn then
                U:SafeLoadAddOn("Blizzard_WeeklyRewards")
            end
            if WeeklyRewardsFrame then
                WeeklyRewardsFrame:Show()
            end
        end

        -- Theme accent color for online-char slot border
        local ac = ns.UI_COLORS and ns.UI_COLORS.accent or {0.40, 0.20, 0.58}

        for slotIndex = 1, 3 do
            -- Slot col index = 1..3 (col 0 is label). Uniform column widths + gaps.
            local xOffset = leftPad + slotIndex * (VAULT_COL_W + vaultColGap)
            local yOffset = -(cellHeight - btnH) / 2  -- vertically centered

            local slotFrame = CreateFrame("Button", nil, rowFrame)
            slotFrame:SetSize(VAULT_SLOT_W, btnH)
            slotFrame:SetPoint("TOPLEFT", rowFrame, "TOPLEFT", xOffset, yOffset)

            -- Slot base: very dark bg, no visible border yet (state sets it below)
            if not slotFrame.bg then
                slotFrame.bg = slotFrame:CreateTexture(nil, "BACKGROUND")
                slotFrame.bg:SetAllPoints()
            end
            if compactSlotStyle then
                slotFrame.bg:SetColorTexture(0.10, 0.10, 0.12, 0.82)
            else
                slotFrame.bg:SetColorTexture(0.06, 0.06, 0.09, 0.95)
            end

            -- Left-side state stripe (slimmer in compact tracker layout)
            if not slotFrame.stripe then
                slotFrame.stripe = slotFrame:CreateTexture(nil, "BORDER")
                slotFrame.stripe:SetWidth(compactSlotStyle and 2 or 3)
                slotFrame.stripe:SetPoint("TOPLEFT", slotFrame, "TOPLEFT", 0, 0)
                slotFrame.stripe:SetPoint("BOTTOMLEFT", slotFrame, "BOTTOMLEFT", 0, 0)
            end

            -- Current char or WVT: click opens/closes Great Vault (compact = soft hover, no heavy slot border)
            if vaultSlotInteract then
                slotFrame:RegisterForClicks("LeftButtonUp")
                slotFrame:SetScript("OnClick", OpenGreatVault)
                slotFrame:SetScript("OnMouseDown", function(self) self:SetAlpha(compactSlotStyle and 0.88 or 0.65) end)
                slotFrame:SetScript("OnMouseUp", function(self) self:SetAlpha(1) end)
                if compactSlotStyle then
                    local hlTex = slotFrame:CreateTexture(nil, "HIGHLIGHT")
                    hlTex:SetBlendMode("ADD")
                    hlTex:SetAllPoints()
                    hlTex:SetColorTexture(1, 1, 1, 0.07)
                    slotFrame:SetHighlightTexture(hlTex)
                else
                    ApplyVisuals(slotFrame,
                        {ac[1] * 0.14, ac[2] * 0.14, ac[3] * 0.18, 1},
                        {ac[1] * 0.70, ac[2] * 0.70, ac[3] * 0.70, 0.70})
                    local hl = slotFrame:CreateTexture(nil, "HIGHLIGHT")
                    hl:SetAllPoints()
                    hl:SetColorTexture(ac[1], ac[2], ac[3], 0.14)
                end
            end

            -- Get activity data for this slot
            local activity = activities and activities[slotIndex]

            local threshold = (activity and activity.threshold) or thresholds[slotIndex] or 0
            local progress = activity and activity.progress or 0
            local isComplete = (threshold > 0 and progress >= threshold)

            if activity and isComplete then
                local isAtMax = IsVaultSlotAtMax(activity, dataKey)
                -- State: completed — green tint (softer in compact tracker style)
                if compactSlotStyle then
                    slotFrame.stripe:SetColorTexture(0.20, 0.62, 0.26, 0.65)
                    slotFrame.bg:SetColorTexture(0.07, 0.14, 0.09, 0.88)
                else
                    slotFrame.stripe:SetColorTexture(0.20, 0.75, 0.20, 0.90)
                    slotFrame.bg:SetColorTexture(0.04, 0.10, 0.04, 0.95)
                end

                local displayText = GetVaultActivityDisplayText(activity, dataKey)
                local rewardIlvl  = GetRewardItemLevel(activity)
                local hasArrow    = not isAtMax
                -- ALL slot text uses identical width + centered position (equal everywhere)
                local textW = VAULT_SLOT_W - 12

                local tierText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                tierText:SetPoint("CENTER", slotFrame, "CENTER", 0, slotTierYOffset)
                tierText:SetWidth(textW)
                tierText:SetJustifyH("CENTER")
                tierText:SetWordWrap(false)
                tierText:SetText(string.format("|cff33dd33%s|r", displayText))

                if rewardIlvl and rewardIlvl > 0 then
                    local ilvlText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                    ilvlText:SetPoint("TOP", tierText, "BOTTOM", 0, -2)
                    ilvlText:SetWidth(textW)
                    ilvlText:SetJustifyH("CENTER")
                    ilvlText:SetWordWrap(false)
                    local ilvlFormat = (ns.L and ns.L["ILVL_FORMAT"]) or "iLvl %d"
                    ilvlText:SetText(string.format("|cffffd700" .. ilvlFormat .. "|r", rewardIlvl))
                end

                -- Upgrade arrow: `loottoast-arrow-green` (Blizzard loot toast); sublayer 7 so slot text stays underneath
                if hasArrow and slotFrame.stripe then
                    local arrowTexture = slotFrame:CreateTexture(nil, "OVERLAY", nil, 7)
                    arrowTexture:SetSize(compactSlotStyle and 18 or 22, compactSlotStyle and 18 or 22)
                    arrowTexture:SetPoint("LEFT", slotFrame.stripe, "RIGHT", 2, 0)
                    arrowTexture:SetAtlas("loottoast-arrow-green", false)
                end

                -- Add tooltip for completed slots
                if ShowTooltip then
                    slotFrame:EnableMouse(true)
                    slotFrame:SetScript("OnEnter", function(self)
                        local lines = {}
                        local displayText = GetVaultActivityDisplayText(activity, dataKey)
                        local rewardIlvl = GetRewardItemLevel(activity)
                        local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
                        local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"

                        -- Current Reward header + value
                        if rewardIlvl and rewardIlvl > 0 then
                            table.insert(lines, {
                                text = string.format("|cff00ff00%s|r",
                                    (ns.L and ns.L["VAULT_REWARD"]) or "Current Reward"),
                                color = {0.5, 1, 0.5}
                            })
                            table.insert(lines, {
                                text = string.format("|cffffd700iLvl %d|r  |cffffffff- (%s)|r",
                                    rewardIlvl, displayText),
                                color = {1, 1, 1}
                            })
                        end

                        -- Upgrade: "Improve to iLvl X: Complete on Y difficulty"
                        local isAtMaxSlot = IsVaultSlotAtMax(activity, dataKey)
                        if not isAtMaxSlot then
                            local nextTierName = GetNextTierName(activity, dataKey)
                            if nextTierName then
                                table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                                local improveLabel = (ns.L and ns.L["VAULT_IMPROVE_TO"]) or "Improve to"
                                if activity.nextLevelIlvl and activity.nextLevelIlvl > 0 then
                                    table.insert(lines, {
                                        text = string.format("|cffa0d0ff%s iLvl %d:|r",
                                            improveLabel, activity.nextLevelIlvl),
                                        color = {0.63, 0.82, 1}
                                    })
                                end
                                local completeOnLabel = (ns.L and ns.L["VAULT_COMPLETE_ON"]) or "Complete this activity on %s"
                                table.insert(lines, {
                                    text = string.format("|cff888888" .. completeOnLabel .. "|r", nextTierName),
                                    color = {0.5, 0.5, 0.5}
                                })
                            end
                        end

                        -- RAID: Encounter list (primary: vault API, fallback: lockouts)
                        if dataKey == "Raid" then
                            if activity.encounters and #activity.encounters > 0 then
                                BuildRaidEncounterLines(lines, activity.encounters)
                            elseif pve.raidLockouts and #pve.raidLockouts > 0 then
                                BuildRaidBossLinesFromLockouts(lines, pve.raidLockouts)
                            end
                        end

                        -- DUNGEON: Top runs (Blizzard pattern: GetRunHistory + GetNumCompletedDungeonRuns)
                        if dataKey == "M+" then
                            local rawHistory = pve.mythicPlus and pve.mythicPlus.runHistory
                            local dungeonRunCounts = vaultActivitiesData and vaultActivitiesData.dungeonRunCounts
                            BuildDungeonRunLines(lines, rawHistory, dungeonRunCounts, threshold)
                        end

                        -- WORLD: Tier progress from GetSortedProgressForActivity (Blizzard pattern)
                        if dataKey == "World" then
                            local worldTierProgress = vaultActivitiesData and vaultActivitiesData.worldTierProgress
                            BuildWorldProgressLines(lines, worldTierProgress, threshold)
                        end

                        if vaultSlotInteract then
                            table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                            table.insert(lines, { text = "|cff00ccff" .. ((ns.L and ns.L["VAULT_CLICK_TO_OPEN"]) or "Click to open Great Vault") .. "|r", color = {0, 0.8, 1} })
                        end
                        local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                        ShowTooltip(self, {
                            type = "custom",
                            icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                            title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                            lines = lines,
                            anchor = "ANCHOR_TOP"
                        })
                    end)

                    slotFrame:SetScript("OnLeave", function(self)
                        if HideTooltip then
                            HideTooltip()
                        end
                    end)
                    BindForwardScrollWheel(slotFrame)
                end


            elseif activity and not isComplete then
                -- State: in-progress — amber tint
                if compactSlotStyle then
                    slotFrame.stripe:SetColorTexture(0.55, 0.42, 0.14, 0.58)
                    slotFrame.bg:SetColorTexture(0.11, 0.09, 0.05, 0.86)
                else
                    slotFrame.stripe:SetColorTexture(0.85, 0.60, 0.10, 0.85)
                    slotFrame.bg:SetColorTexture(0.10, 0.08, 0.02, 0.95)
                end

                local progressText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                progressText:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
                progressText:SetWidth(VAULT_SLOT_W - 12)
                progressText:SetJustifyH("CENTER")
                progressText:SetWordWrap(false)
                progressText:SetText(string.format("|cffffcc00%s|r|cff666666/|r|cff888888%s|r",
                    FormatNumber(progress), FormatNumber(threshold)))

                -- Add tooltip for incomplete slots
                if ShowTooltip then
                    slotFrame:EnableMouse(true)
                    slotFrame:SetScript("OnEnter", function(self)
                        local lines = {}
                        local tierFmt = (ns.L and ns.L["TIER_FORMAT"]) or "Tier %d"
                        local mythicLabel = (ns.L and ns.L["DIFFICULTY_MYTHIC"]) or "Mythic"

                        local activityHint = ""
                        if dataKey == "M+" then
                            activityHint = (ns.L and ns.L["VAULT_DUNGEONS"]) or "dungeons"
                        elseif dataKey == "Raid" then
                            activityHint = (ns.L and ns.L["VAULT_BOSS_KILLS"]) or "boss kills"
                        elseif dataKey == "World" then
                            activityHint = (ns.L and ns.L["VAULT_WORLD_ACTIVITIES"]) or "world activities"
                        else
                            activityHint = (ns.L and ns.L["VAULT_ACTIVITIES"]) or "activities"
                        end

                        -- Unlock Reward header
                        local unlockLabel = (ns.L and ns.L["VAULT_UNLOCK_REWARD"]) or "Unlock Reward"
                        table.insert(lines, {
                            text = string.format("|cff00ff00%s|r", unlockLabel),
                            color = {0.5, 1, 0.5}
                        })

                        -- "Complete N more X to unlock"
                        local remaining = threshold - progress
                        if remaining > 0 then
                            local completeMoreLabel = (ns.L and ns.L["VAULT_COMPLETE_MORE_FORMAT"]) or "Complete %d more %s this week to unlock."
                            table.insert(lines, {
                                text = string.format("|cffffffff" .. completeMoreLabel .. "|r",
                                    remaining, activityHint),
                                color = {1, 1, 1}
                            })
                        end

                        -- M+ specific: "The item level will be based on the lowest of your top N runs (currently X)"
                        if dataKey == "M+" then
                            local currentTierText = GetVaultActivityDisplayText(activity, dataKey)
                            table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                            local basedOnLabel = (ns.L and ns.L["VAULT_BASED_ON_FORMAT"]) or "The item level of this reward will be based on the lowest of your top %d runs this week (currently %s)."
                            table.insert(lines, {
                                text = string.format("|cff888888" .. basedOnLabel .. "|r",
                                    threshold, currentTierText),
                                color = {0.5, 0.5, 0.5}
                            })
                        end

                        -- Raid specific: "The item level will be based on the difficulty of your boss kills"
                        if dataKey == "Raid" then
                            local currentDiffText = GetVaultActivityDisplayText(activity, dataKey)
                            table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                            local raidBasedLabel = (ns.L and ns.L["VAULT_RAID_BASED_FORMAT"]) or "Reward based on highest difficulty defeated (currently %s)."
                            table.insert(lines, {
                                text = string.format("|cff888888" .. raidBasedLabel .. "|r", currentDiffText),
                                color = {0.5, 0.5, 0.5}
                            })
                        end

                        -- RAID: Encounter list (primary: vault API, fallback: lockouts)
                        if dataKey == "Raid" then
                            if activity.encounters and #activity.encounters > 0 then
                                BuildRaidEncounterLines(lines, activity.encounters)
                            elseif pve.raidLockouts and #pve.raidLockouts > 0 then
                                BuildRaidBossLinesFromLockouts(lines, pve.raidLockouts)
                            end
                        end

                        -- DUNGEON: Top runs (Blizzard pattern)
                        if dataKey == "M+" and progress > 0 then
                            local rawHistory = pve.mythicPlus and pve.mythicPlus.runHistory
                            local dungeonRunCounts = vaultActivitiesData and vaultActivitiesData.dungeonRunCounts
                            BuildDungeonRunLines(lines, rawHistory, dungeonRunCounts, threshold)
                        end

                        -- WORLD: Tier progress (Blizzard pattern)
                        if dataKey == "World" and progress > 0 then
                            local worldTierProgress = vaultActivitiesData and vaultActivitiesData.worldTierProgress
                            BuildWorldProgressLines(lines, worldTierProgress, threshold)
                        end

                        if vaultSlotInteract then
                            table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                            table.insert(lines, { text = "|cff00ccff" .. ((ns.L and ns.L["VAULT_CLICK_TO_OPEN"]) or "Click to open Great Vault") .. "|r", color = {0, 0.8, 1} })
                        end
                        local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                        ShowTooltip(self, {
                            type = "custom",
                            icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                            title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                            lines = lines,
                            anchor = "ANCHOR_TOP"
                        })
                    end)

                    slotFrame:SetScript("OnLeave", function(self)
                        if HideTooltip then
                            HideTooltip()
                        end
                    end)
                    BindForwardScrollWheel(slotFrame)
                end
            else
                -- State: no data — dim stripe / neutral cell
                if compactSlotStyle then
                    slotFrame.stripe:SetColorTexture(0.16, 0.16, 0.20, 0.42)
                    slotFrame.bg:SetColorTexture(0.10, 0.10, 0.12, 0.78)
                else
                    slotFrame.stripe:SetColorTexture(0.22, 0.22, 0.28, 0.60)
                end

                local emptyText = FontManager:CreateFontString(slotFrame, slotFontKey, "OVERLAY")
                emptyText:SetPoint("CENTER", slotFrame, "CENTER", 0, 0)
                emptyText:SetWidth(VAULT_SLOT_W - 12)
                emptyText:SetJustifyH("CENTER")
                emptyText:SetWordWrap(false)
                if threshold > 0 then
                    emptyText:SetText(string.format("|cff555555%s|r|cff444444/|r|cff555555%s|r", FormatNumber(0), FormatNumber(threshold)))

                    -- Add tooltip for empty slots
                    if ShowTooltip then
                        slotFrame:EnableMouse(true)
                        slotFrame:SetScript("OnEnter", function(self)
                            local lines = {}

                            local activityHint = ""
                            if dataKey == "M+" then
                                activityHint = (ns.L and ns.L["VAULT_DUNGEONS"]) or "dungeons"
                            elseif dataKey == "Raid" then
                                activityHint = (ns.L and ns.L["VAULT_BOSS_KILLS"]) or "boss kills"
                            elseif dataKey == "World" then
                                activityHint = (ns.L and ns.L["VAULT_WORLD_ACTIVITIES"]) or "world activities"
                            else
                                activityHint = (ns.L and ns.L["VAULT_ACTIVITIES"]) or "activities"
                            end

                            local unlockLabel = (ns.L and ns.L["VAULT_UNLOCK_REWARD"]) or "Unlock Reward"
                            table.insert(lines, {
                                text = string.format("|cff00ff00%s|r", unlockLabel),
                                color = {0.5, 1, 0.5}
                            })
                            local completeMoreLabel = (ns.L and ns.L["VAULT_COMPLETE_MORE_FORMAT"]) or "Complete %d more %s this week to unlock."
                            table.insert(lines, {
                                text = string.format("|cffffffff" .. completeMoreLabel .. "|r",
                                    threshold, activityHint),
                                color = {1, 1, 1}
                            })

                            if vaultSlotInteract then
                                table.insert(lines, { text = " ", color = {0.3, 0.3, 0.3} })
                                table.insert(lines, { text = "|cff00ccff" .. ((ns.L and ns.L["VAULT_CLICK_TO_OPEN"]) or "Click to open Great Vault") .. "|r", color = {0, 0.8, 1} })
                            end
                            local slotTitleFormat = (ns.L and ns.L["VAULT_SLOT_FORMAT"]) or "%s Slot %d"
                            ShowTooltip(self, {
                                type = "custom",
                                icon = "Interface\\Icons\\INV_Misc_Lockbox_1",
                                title = string.format(slotTitleFormat, typeDisplayName, slotIndex),
                                lines = lines,
                                anchor = "ANCHOR_TOP"
                            })
                        end)

                        slotFrame:SetScript("OnLeave", function(self)
                            if HideTooltip then
                                HideTooltip()
                            end
                        end)
                        BindForwardScrollWheel(slotFrame)
                    end
                else
                    emptyText:SetText("|cff666666-|r")
                end
            end
        end

        -- No need to increment vaultY anymore (using rowIndex)
    end

    return cardHeight, cardWidth
end

--============================================================================
-- WEEKLY VAULT TRACKER — 3-column card grid (no expand/collapse headers)
--============================================================================

function WarbandNexus:DrawPvEVaultTrackerCardGrid(parent, startYOffset, characters, currentPlayerKey)
    local mf = WarbandNexus.UI and WarbandNexus.UI.mainFrame
    if mf and mf.columnHeaderClip then
        mf.columnHeaderClip:Hide()
    end

    local scrollFrame = parent:GetParent()
    local viewportW = (scrollFrame and scrollFrame:GetWidth()) or 800
    parent:SetWidth(math.max(viewportW, 520))
    if mf and mf.columnHeaderInner then
        mf.columnHeaderInner:SetWidth(parent:GetWidth())
    end

    local SIDE_PAD = 8
    local GAP = 6
    local COLS = 3
    local innerW = math.max(100, parent:GetWidth() - SIDE_PAD * 2)
    local gapBetweenCards = (COLS - 1) * GAP
    local cardW = math.floor((innerW - gapBetweenCards) / COLS)
    -- Compact WVT: fixed row height; vault opens/closes only from grid slots (not whole card).
    local cardH = 206
    local HDR_ICON = 24
    local PAD = 5

    local pendingStr = (ns.L and ns.L["VAULT_TRACKER_STATUS_PENDING"]) or "Pending..."
    local readyClaimStr = (ns.L and ns.L["VAULT_TRACKER_STATUS_READY_CLAIM"]) or "Ready to Claim"

    local layoutIdx = 0
    for i = 1, #characters do
        local char = characters[i]
        local charKey = PvE_GetCanonicalKeyForChar(char)
        if charKey then
            layoutIdx = layoutIdx + 1
            local col = (layoutIdx - 1) % COLS
            local row = math.floor((layoutIdx - 1) / COLS)
            local x = SIDE_PAD + col * (cardW + GAP)
            local yTop = startYOffset + row * (cardH + GAP)

            local pveData = self:GetPvEData(charKey) or {}
            local vaultActs = pveData.vaultActivities or {}

            local claim = pveData.vaultRewards and pveData.vaultRewards.hasAvailableRewards == true
            local isCurrentChar = (charKey == currentPlayerKey)
            if (not claim) and isCurrentChar and self.HasUnclaimedVaultRewards then
                local ok, v = pcall(self.HasUnclaimedVaultRewards, self)
                claim = ok and v == true
            end

            local classColor = RAID_CLASS_COLORS[char.classFile] or { r = 1, g = 1, b = 1 }
            local card = CreateCard(parent, cardH)
            card:SetWidth(cardW)
            card:SetPoint("TOPLEFT", parent, "TOPLEFT", x, -yTop)

            local ac = ns.UI_COLORS and ns.UI_COLORS.accent or { 0.40, 0.20, 0.58 }
            if card.SetBackdropBorderColor then
                if isCurrentChar then
                    card:SetBackdropBorderColor(ac[1], ac[2], ac[3], 0.95)
                else
                    card:SetBackdropBorderColor(ac[1] * 0.85, ac[2] * 0.85, ac[3] * 0.85, 0.75)
                end
            end

            -- Full-width header strip: identity left, vault status right (same inner width as grid below).
            local innerW = cardW - 2 * PAD
            local HEADER_H = 40
            local HDR_AFTER_GAP = 3
            local GRID_AFTER_SEP = 4

            local vaultComplete = PvE_AllVaultTracksComplete(vaultActs)
            local showStatus = claim or vaultComplete
            local statusReserve = showStatus and 104 or 8

            local headerBar = ns.UI.Factory:CreateContainer(card, innerW, HEADER_H)
            headerBar:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -PAD)

            local vaultHeadIcon = CreateIcon(headerBar, "BonusLoot-Chest", HDR_ICON, true, nil, true)
            vaultHeadIcon:SetPoint("CENTER", headerBar, "LEFT", HDR_ICON * 0.5, 0)
            vaultHeadIcon:Show()

            local nameColW = math.max(56, innerW - HDR_ICON - 5 - statusReserve)
            local realmDisp = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ""

            local nameFs = FontManager:CreateFontString(headerBar, FontManager:GetFontRole("pveVaultCardCharName"), "OVERLAY")
            nameFs:SetPoint("TOPLEFT", headerBar, "TOPLEFT", HDR_ICON + 5, -4)
            nameFs:SetWidth(nameColW)
            nameFs:SetJustifyH("LEFT")
            nameFs:SetWordWrap(false)
            nameFs:SetText(string.format(
                "|cff%02x%02x%02x%s|r",
                classColor.r * 255,
                classColor.g * 255,
                classColor.b * 255,
                char.name or "?"
            ))

            local realmFs = FontManager:CreateFontString(headerBar, FontManager:GetFontRole("pveVaultCardRealm"), "OVERLAY")
            realmFs:SetPoint("TOPLEFT", nameFs, "BOTTOMLEFT", 0, -1)
            realmFs:SetWidth(nameColW)
            realmFs:SetJustifyH("LEFT")
            realmFs:SetWordWrap(false)
            realmFs:SetText(realmDisp ~= "" and ("|cffaaaaaa" .. realmDisp .. "|r") or " ")

            local statusFs = FontManager:CreateFontString(headerBar, FontManager:GetFontRole("pveVaultCardStatus"), "OVERLAY")
            statusFs:SetWidth(statusReserve)
            statusFs:SetJustifyH("RIGHT")
            statusFs:SetWordWrap(false)
            if claim then
                statusFs:SetTextColor(0.35, 1, 0.35)
                statusFs:SetText(readyClaimStr)
                statusFs:Show()
            elseif vaultComplete then
                statusFs:SetTextColor(1, 0.82, 0.35)
                statusFs:SetText(pendingStr)
                statusFs:Show()
            else
                statusFs:Hide()
            end
            statusFs:SetPoint("CENTER", headerBar, "RIGHT", -math.floor(statusReserve * 0.5), 0)

            local hdrSep = card:CreateTexture(nil, "BORDER")
            hdrSep:SetHeight(1)
            hdrSep:SetColorTexture(ac[1] * 0.42, ac[2] * 0.42, ac[3] * 0.42, 0.5)
            hdrSep:SetPoint("TOPLEFT", headerBar, "BOTTOMLEFT", 0, -HDR_AFTER_GAP)
            hdrSep:SetPoint("TOPRIGHT", headerBar, "BOTTOMRIGHT", 0, -HDR_AFTER_GAP)

            local vaultInnerW = innerW
            local baseVaultGridH = 136
            local vaultGridHost = ns.UI.Factory:CreateContainer(card, vaultInnerW, baseVaultGridH)
            vaultGridHost:SetPoint("TOPLEFT", hdrSep, "BOTTOMLEFT", 0, -GRID_AFTER_SEP)

            local vaultByType = {}
            if vaultActs.raids then vaultByType["Raid"] = vaultActs.raids end
            if vaultActs.mythicPlus then vaultByType["M+"] = vaultActs.mythicPlus end
            if vaultActs.world then vaultByType["World"] = vaultActs.world end

            select(1, self:PaintPvEVaultGridOnCard(vaultGridHost, {
                baseCardWidth = vaultInnerW,
                baseCardHeight = baseVaultGridH,
                vaultByType = vaultByType,
                pve = pveData,
                vaultActivitiesData = vaultActs,
                isCurrentChar = isCurrentChar,
                enableVaultSlotInteraction = true,
                applyVaultCardChrome = false,
                compactSlotStyle = true,
                borderPadding = 0,
                vaultColGap = 3,
                vaultLeftPad = 3,
                vaultRightPad = 3,
                minSlotBtnH = 28,
                vaultRowVPad = 2,
                trackIconSize = 13,
                slotFontKey = "body",
                rowLabelFontKey = "body",
                slotTierYOffset = 5,
            }))
            -- Great Vault toggle only via slot buttons (OnClick already opens/closes WeeklyRewardsFrame).

            card:Show()
        end
    end

    local rows = layoutIdx > 0 and math.ceil(layoutIdx / COLS) or 0
    local bottom = startYOffset + math.max(0, rows) * (cardH + GAP) + 24
    return bottom
end

--- Populates expanded PvE per-character detail (M+, keystone, vault grid).
--- Extracted from DrawPvEProgress to avoid Lua 5.1 "more than 60 upvalues" on nested closures.
local function PvEUI_PopulateExpandedCharacterDetail(self, parent, charDetailContent, charExpandKey, charKey, pve, pveData, isCurrentChar)
            if not charDetailContent or charDetailContent._wnPopulateKey == charExpandKey then
                return
            end
            charDetailContent._wnPopulateKey = charExpandKey

            local cardContainer = ns.UI.Factory:CreateContainer(charDetailContent)
            cardContainer:SetPoint("TOPLEFT", charDetailContent, "TOPLEFT", 0, 0)
            cardContainer:SetPoint("TOPRIGHT", charDetailContent, "TOPRIGHT", 0, 0)

            -- Calculate responsive card widths (pixel-snapped)
            -- Order: Overall Score (35%) → Keystone+Affixes (35%) → Vault (30%)
            local PixelSnap = ns.PixelSnap or function(v) return v end
            local totalWidth = PixelSnap(parent:GetWidth() - 20)
            -- Vault card: 4 equal columns (Label + 3 slots), each needs room for "Dungeons" + icon
            local card3Width = PixelSnap(math.max(360, totalWidth * 0.40))  -- Vault (min 360px)
            local remaining  = totalWidth - card3Width
            local card1Width = PixelSnap(remaining * 0.48)  -- Overall Score (M+ dungeons)
            local card2Width = PixelSnap(remaining - card1Width)  -- Keystone + Affixes
            local cardSpacing = 5
            
            -- Card height will be calculated from vault card grid (with fallback)
            local cardHeight = 200  -- Default fallback height
            
            -- === CARD 1: OVERALL SCORE + M+ DUNGEONS (35%) ===
            local baseCardHeight = 200
            local mplusCard = CreateCard(cardContainer, baseCardHeight)
            mplusCard:SetPoint("TOPLEFT", 0, 0)
            mplusCard:SetWidth(PixelSnap(card1Width - cardSpacing))
            
            local mplusY = 15
            
            if not pve.mythicPlus then
                pve.mythicPlus = { overallScore = 0, bestRuns = {} }
            end
            
            local totalScore = pve.mythicPlus.overallScore or 0
            local scoreText = FontManager:CreateFontString(mplusCard, "title", "OVERLAY")
            scoreText:SetPoint("TOP", mplusCard, "TOP", 0, -mplusY)
            
            local scoreColor
            if totalScore >= 2500 then
                scoreColor = "|cffff8000"
            elseif totalScore >= 2000 then
                scoreColor = "|cffa335ee"
            elseif totalScore >= 1500 then
                scoreColor = "|cff0070dd"
            elseif totalScore >= 1000 then
                scoreColor = "|cff1eff00"
            elseif totalScore >= 500 then
                scoreColor = "|cffffffff"
            else
                scoreColor = "|cff9d9d9d"
            end
            
            local overallScoreLabel = (ns.L and ns.L["OVERALL_SCORE_LABEL"]) or "Overall Score:"
            scoreText:SetText(string.format("%s %s%s|r", overallScoreLabel, scoreColor, FormatNumber(totalScore)))
            mplusY = mplusY + 35
            
            -- Tall M+ grids need more than baseCardHeight; otherwise icons/scores extend past the card bottom border.
            local mplusNeededH = baseCardHeight
            
            if pve.mythicPlus.dungeons and #pve.mythicPlus.dungeons > 0 then
                local totalDungeons = #pve.mythicPlus.dungeons
                local iconSize = 48
                local maxIconsPerRow = 6
                local iconSpacing = 6
                
                local numRows = math.ceil(totalDungeons / maxIconsPerRow)
                
                local highestKeyLevel = 0
                for i = 1, #pve.mythicPlus.dungeons do
                    local dungeon = pve.mythicPlus.dungeons[i]
                    if dungeon.bestLevel and dungeon.bestLevel > highestKeyLevel then
                        highestKeyLevel = dungeon.bestLevel
                    end
                end
                
                local cardWidthInner = (card1Width - cardSpacing)
                local borderPadding = 2
                local gridY = mplusY
                local rowSpacing = 24
                
                local dungeonsByRow = {}
                for i = 1, numRows do
                    dungeonsByRow[i] = {}
                end
                
                local mplusDungeons = pve.mythicPlus.dungeons
                for di = 1, #mplusDungeons do
                    local dungeon = mplusDungeons[di]
                    local row = math.floor((di - 1) / maxIconsPerRow) + 1
                    table.insert(dungeonsByRow[row], dungeon)
                end
                
                local sidePadding = 12
                local firstRowIcons = math.min(maxIconsPerRow, totalDungeons)
                local availableWidth = cardWidthInner - (2 * (borderPadding + sidePadding))
                local consistentSpacing = (availableWidth - (firstRowIcons * iconSize)) / (firstRowIcons - 1)
                
                for rowIndex = 1, #dungeonsByRow do
                    local dungeons = dungeonsByRow[rowIndex]
                    local iconsInThisRow = #dungeons
                    local rowY = gridY + ((rowIndex - 1) * (iconSize + rowSpacing))
                    
                    local startX
                    
                    if rowIndex == 1 and iconsInThisRow >= 4 then
                        startX = borderPadding + sidePadding
                    else
                        local totalRowWidth = (iconsInThisRow * iconSize) + ((iconsInThisRow - 1) * consistentSpacing)
                        startX = (cardWidthInner - totalRowWidth) / 2
                    end
                    
                    for colIndex = 1, #dungeons do
                        local dungeon = dungeons[colIndex]
                        local iconX = startX + ((colIndex - 1) * (iconSize + consistentSpacing))
                        
                        local iconFrame = CreateIcon(mplusCard, dungeon.texture or "Interface\\Icons\\INV_Misc_QuestionMark", iconSize, false, nil, false)
                        local roundedX = math.floor(iconX + 0.5)
                        local roundedY = math.floor(rowY + 0.5)
                        iconFrame:SetPoint("TOPLEFT", roundedX, -roundedY)
                        iconFrame:EnableMouse(true)
                        BindForwardScrollWheel(iconFrame)
                        
                        local texture = iconFrame.texture
                        
                        if texture then
                            texture:SetTexCoord(0.05, 0.95, 0.05, 0.95)
                        end
                        local hasBestLevel = dungeon.bestLevel and dungeon.bestLevel > 0
                        local isHighest = hasBestLevel and dungeon.bestLevel == highestKeyLevel and highestKeyLevel >= 10
                        
                        if iconFrame.BorderTop then
                            local r, g, b, a
                            if isHighest then
                                r, g, b, a = 1, 0.82, 0, 0.9
                            elseif hasBestLevel then
                                local accentColor = COLORS.accent
                                r, g, b, a = accentColor[1], accentColor[2], accentColor[3], 0.8
                            else
                                r, g, b, a = 0.4, 0.4, 0.4, 0.6
                            end
                            iconFrame.BorderTop:SetVertexColor(r, g, b, a)
                            iconFrame.BorderBottom:SetVertexColor(r, g, b, a)
                            iconFrame.BorderLeft:SetVertexColor(r, g, b, a)
                            iconFrame.BorderRight:SetVertexColor(r, g, b, a)
                        end
                    
                    if hasBestLevel then
                        local backdrop = iconFrame:CreateTexture(nil, "BACKGROUND")
                        backdrop:SetSize(iconSize * 0.8, iconSize * 0.5)
                        backdrop:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        backdrop:SetColorTexture(0, 0, 0, 0.7)
                        
                        local levelShadow = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        levelShadow:SetPoint("CENTER", iconFrame, "CENTER", 1, -1)
                        levelShadow:SetText(string.format("|cff000000+%d|r", dungeon.bestLevel))
                        
                        local levelText = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        levelText:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        levelText:SetText(string.format("|cffffcc00+%d|r", dungeon.bestLevel))
                        
                        local dungeonScore = FontManager:CreateFontString(iconFrame, "title", "OVERLAY")
                        dungeonScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        
                        local score = dungeon.score or 0
                        local dScoreColor
                        if score >= 312 then
                            dScoreColor = "|cffff8000"
                        elseif score >= 250 then
                            dScoreColor = "|cffa335ee"
                        elseif score >= 187 then
                            dScoreColor = "|cff0070dd"
                        elseif score >= 125 then
                            dScoreColor = "|cff1eff00"
                        elseif score >= 62 then
                            dScoreColor = "|cffffffff"
                        else
                            dScoreColor = "|cff9d9d9d"
                        end
                        
                        dungeonScore:SetText(string.format("%s%s|r", dScoreColor, FormatNumber(score)))
                    else
                        texture:SetDesaturated(true)
                        texture:SetAlpha(0.4)
                        
                        local notDone = FontManager:CreateFontString(iconFrame, "header", "OVERLAY")
                        notDone:SetPoint("CENTER", iconFrame, "CENTER", 0, 0)
                        notDone:SetText("|cff666666?|r")
                        
                        local zeroScore = FontManager:CreateFontString(iconFrame, "title", "OVERLAY")
                        zeroScore:SetPoint("TOP", iconFrame, "BOTTOM", 0, -3)
                        zeroScore:SetText("|cff444444-|r")
                    end
                    
                    if ShowTooltip and HideTooltip then
                        iconFrame:SetScript("OnEnter", function(self)
                            local tooltipLines = {}
                            if dungeon.name then
                                table.insert(tooltipLines, { text = dungeon.name, color = {1, 1, 1} })
                            end
                            if hasBestLevel then
                                local bestKeyLabel = (ns.L and ns.L["VAULT_BEST_KEY"]) or "Best Key:"
                                table.insert(tooltipLines, {
                                    text = string.format("%s |cffffcc00+%d|r", bestKeyLabel, dungeon.bestLevel),
                                    color = {0.9, 0.9, 0.9}
                                })
                                local scoreLabel = (ns.L and ns.L["VAULT_SCORE"]) or "Score:"
                                table.insert(tooltipLines, {
                                    text = string.format("%s |cffffffff%s|r", scoreLabel, FormatNumber(dungeon.score or 0)),
                                    color = {0.9, 0.9, 0.9}
                                })
                            else
                                local notCompletedLabel = (ns.L and ns.L["NOT_COMPLETED_SEASON"]) or "Not completed this season"
                                table.insert(tooltipLines, {
                                    text = "|cff888888" .. notCompletedLabel .. "|r",
                                    color = {0.6, 0.6, 0.6}
                                })
                            end
                            ShowTooltip(self, {
                                type = "custom",
                                icon = dungeon.texture or "Interface\\Icons\\INV_Misc_QuestionMark",
                                title = dungeon.name or ((ns.L and ns.L["VAULT_DUNGEON"]) or "Dungeon"),
                                lines = tooltipLines,
                                anchor = "ANCHOR_TOP"
                            })
                        end)
                        iconFrame:SetScript("OnLeave", function(self)
                            HideTooltip()
                        end)
                    end
                    
                    iconFrame:Show()
                    end
                end
                
                local lastRowY = gridY + (numRows - 1) * (iconSize + rowSpacing)
                mplusNeededH = math.max(baseCardHeight, lastRowY + iconSize + 34 + 10)
            else
                local noData = FontManager:CreateFontString(mplusCard, "small", "OVERLAY")
                noData:SetPoint("TOPLEFT", 15, -mplusY)
                local noDataLabel = (ns.L and ns.L["NO_DATA"]) or "No data"
                noData:SetText("|cff666666" .. noDataLabel .. "|r")
                mplusNeededH = math.max(baseCardHeight, mplusY + 40)
            end
            
            mplusCard:SetHeight(mplusNeededH)
            mplusCard:Show()
            
            -- === CARD 2: KEYSTONE + AFFIXES (35%) ===
            local summaryCard = CreateCard(cardContainer, cardHeight)
            summaryCard:SetPoint("TOPLEFT", PixelSnap(card1Width), 0)
            summaryCard:SetWidth(PixelSnap(card2Width - cardSpacing))
            
            local cardPadding = 10
            local columnSpacing = 15
            local topColumnWidth = (card2Width - cardSpacing - cardPadding * 2 - columnSpacing) / 2
            
            -- Keystone (Left Column)
            local col1X = cardPadding
            local col1Y = 12
            
            local keystoneTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            keystoneTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col1X + topColumnWidth / 2, -col1Y)
            local keystoneLabel = (ns.L and ns.L["KEYSTONE"]) or "Keystone"
            keystoneTitle:SetText("|cffffffff" .. keystoneLabel .. "|r")
            keystoneTitle:SetJustifyH("CENTER")
            
            local keystoneData = pveData and pveData.keystone
            
            if keystoneData and keystoneData.level and keystoneData.level > 0 and keystoneData.mapID then
                local keystoneLevel = keystoneData.level
                local keystoneMapID = keystoneData.mapID
                
                if C_ChallengeMode then
                    local mapName, _, timeLimit, texture = C_ChallengeMode.GetMapUIInfo(keystoneMapID)
                    
                    local iconSize = 50
                    local keystoneIcon = CreateIcon(summaryCard, texture or "Interface\\Icons\\Achievement_ChallengeMode_Gold", iconSize, false, nil, false)
                    keystoneIcon:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -5)
                    
                    if keystoneIcon.BorderTop then
                        local r, g, b, a = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8
                        keystoneIcon.BorderTop:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderBottom:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderLeft:SetVertexColor(r, g, b, a)
                        keystoneIcon.BorderRight:SetVertexColor(r, g, b, a)
                    end
                    keystoneIcon:Show()
                    
                    local kLevelText = FontManager:CreateFontString(summaryCard, "header", "OVERLAY")
                    kLevelText:SetPoint("TOP", keystoneIcon, "BOTTOM", 0, -3)
                    kLevelText:SetText(string.format("|cff00ff00+%d|r", keystoneLevel))
                    kLevelText:SetJustifyH("CENTER")
                    
                    local nameText = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
                    nameText:SetPoint("TOP", kLevelText, "BOTTOM", 0, 0)
                    nameText:SetWidth(topColumnWidth - 10)
                    nameText:SetJustifyH("CENTER")
                    nameText:SetWordWrap(true)
                    nameText:SetMaxLines(2)
                    nameText:SetText(mapName or ((ns.L and ns.L["KEYSTONE"]) or "Keystone"))
                else
                    local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                    noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                    local noKeyLabel = (ns.L and ns.L["NO_KEY"]) or "No Key"
                    noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                    noKeyText:SetJustifyH("CENTER")
                end
            else
                local noKeyText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noKeyText:SetPoint("TOP", keystoneTitle, "BOTTOM", 0, -20)
                local noKeyLabel = (ns.L and ns.L["NO_KEY"]) or "No Key"
                noKeyText:SetText("|cff888888" .. noKeyLabel .. "|r")
                noKeyText:SetJustifyH("CENTER")
            end
            
            -- Affixes (Right Column)
            local col2X = col1X + topColumnWidth + columnSpacing
            local col2Y = col1Y
            local summaryAffixBottom = col2Y + 82
            
            local affixesTitle = FontManager:CreateFontString(summaryCard, "body", "OVERLAY")
            affixesTitle:SetPoint("TOP", summaryCard, "TOPLEFT", col2X + topColumnWidth / 2, -col2Y)
            local affixesLabel = (ns.L and ns.L["AFFIXES"]) or "Affixes"
            affixesTitle:SetText("|cffffffff" .. affixesLabel .. "|r")
            affixesTitle:SetJustifyH("CENTER")
            
            local allPveData = self:GetPvEData()
            local currentAffixes = allPveData and allPveData.currentAffixes
            
            if currentAffixes and #currentAffixes > 0 then
                local affixSize = 38
                local affixSpacing = 10
                local maxAffixes = math.min(#currentAffixes, 4)
                
                local aTotalWidth = (maxAffixes * affixSize) + ((maxAffixes - 1) * affixSpacing)
                local aStartX = col2X + (topColumnWidth - aTotalWidth) / 2
                local aStartY = col2Y + 23
                
                for i = 1, #currentAffixes do
                    local affixData = currentAffixes[i]
                    if i <= maxAffixes then
                        local name = affixData.name
                        local description = affixData.description
                        local filedataid = affixData.icon
                        
                        if filedataid then
                            local xOffset = aStartX + ((i - 1) * (affixSize + affixSpacing))
                            local yOffset = aStartY
                            
                            local affixIcon = CreateIcon(summaryCard, filedataid, affixSize, false, nil, false)
                            local roundedX = math.floor(xOffset + 0.5)
                            local roundedY = math.floor(yOffset + 0.5)
                            affixIcon:SetPoint("TOPLEFT", roundedX, -roundedY)
                            
                            if affixIcon.BorderTop then
                                local r, g, b, a = COLORS.accent[1], COLORS.accent[2], COLORS.accent[3], 0.8
                                affixIcon.BorderTop:SetVertexColor(r, g, b, a)
                                affixIcon.BorderBottom:SetVertexColor(r, g, b, a)
                                affixIcon.BorderLeft:SetVertexColor(r, g, b, a)
                                affixIcon.BorderRight:SetVertexColor(r, g, b, a)
                            end
                            
                            if ShowTooltip then
                                affixIcon:EnableMouse(true)
                                affixIcon:SetScript("OnEnter", function(self)
                                    ShowTooltip(self, {
                                        type = "custom",
                                        icon = filedataid,
                                        title = name or ((ns.L and ns.L["AFFIX_TITLE_FALLBACK"]) or "Affix"),
                                        description = description,
                                        lines = {},
                                        anchor = "ANCHOR_RIGHT"
                                    })
                                end)
                                affixIcon:SetScript("OnLeave", function(self)
                                    if HideTooltip then HideTooltip() end
                                end)
                                BindForwardScrollWheel(affixIcon)
                            end
                            
                            affixIcon:Show()
                        end
                    end
                end
                summaryAffixBottom = math.max(summaryAffixBottom, aStartY + affixSize + 22)
            else
                local noAffixesText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                noAffixesText:SetPoint("TOP", affixesTitle, "BOTTOM", 0, -30)
                local noAffixesLabel = (ns.L and ns.L["NO_AFFIXES"]) or "No Affixes"
                noAffixesText:SetText("|cff888888" .. noAffixesLabel .. "|r")
                noAffixesText:SetJustifyH("CENTER")
            end

            -- Bottom row: Dawncrest/currency snapshot (restored under Keystone card)
            local crestCurrencies = {}
            do
                local MS1 = ns.Constants and ns.Constants.DAWNCREST_UI
                if MS1 and MS1.COLUMN_IDS then
                    for i = 1, #MS1.COLUMN_IDS do
                        crestCurrencies[#crestCurrencies + 1] = { id = MS1.COLUMN_IDS[i], fallbackIcon = 134400 }
                    end
                else
                    crestCurrencies = {
                        { id = 3383, fallbackIcon = 134400 },
                        { id = 3341, fallbackIcon = 134400 },
                        { id = 3343, fallbackIcon = 134400 },
                        { id = 3345, fallbackIcon = 134400 },
                        { id = 3347, fallbackIcon = 134400 },
                    }
                end
            end
            local numCurrencies = #crestCurrencies
            local rowIconSize = 30
            local rowSpacing = 8
            local rowTopY = 138
            local rowAvailableW = (card2Width - cardSpacing) - (cardPadding * 2)
            local rowItemW = (rowAvailableW - (rowSpacing * (numCurrencies - 1))) / numCurrencies
            local rowStartX = cardPadding

            for ci = 1, numCurrencies do
                local curr = crestCurrencies[ci]
                local currencyEntry = WarbandNexus:GetCurrencyData(curr.id, charKey)
                local iconFileID = currencyEntry and currencyEntry.icon or curr.fallbackIcon
                local quantity = currencyEntry and currencyEntry.quantity or 0
                local maxQuantity = currencyEntry and currencyEntry.maxQuantity or 0
                local currencyName = currencyEntry and currencyEntry.name or ((ns.L and ns.L["TAB_CURRENCY"]) or "Currency")

                local slotX = rowStartX + ((ci - 1) * (rowItemW + rowSpacing))
                local iconCenterX = slotX + (rowItemW * 0.5)

                local crestIcon = CreateIcon(summaryCard, iconFileID, rowIconSize, false, nil, false)
                crestIcon:SetPoint("TOP", summaryCard, "TOPLEFT", math.floor(iconCenterX + 0.5), -rowTopY)
                crestIcon:Show()

                local amountText = FontManager:CreateFontString(summaryCard, "small", "OVERLAY")
                amountText:SetPoint("TOP", crestIcon, "BOTTOM", 0, -2)
                amountText:SetWidth(rowItemW + 8)
                amountText:SetJustifyH("CENTER")
                amountText:SetWordWrap(false)
                if ns.UI_BindSeasonProgressAmount then
                    -- Shift-aware: default = current only (cap-colored), Shift = expanded current\194\183earned/cap.
                    ns.UI_BindSeasonProgressAmount(amountText, currencyEntry)
                elseif ns.UI_FormatSeasonProgressCurrencyLine then
                    amountText:SetText(ns.UI_FormatSeasonProgressCurrencyLine(currencyEntry))
                else
                    local amtColor = "|cffffffff"
                    if maxQuantity > 0 then
                        local pct = (quantity / maxQuantity) * 100
                        if pct >= 100 then amtColor = "|cffff4444"
                        elseif pct >= 80 then amtColor = "|cffffaa00" end
                    end
                    amountText:SetText(string.format("%s%s|r", amtColor, FormatNumber(quantity)))
                end

                if ShowTooltip and HideTooltip then
                    crestIcon:EnableMouse(true)
                    crestIcon:SetScript("OnEnter", function(self)
                        ShowTooltip(self, {
                            type = "currency",
                            currencyID = curr.id,
                            charKey = charKey,
                            anchor = "ANCHOR_TOP",
                        })
                    end)
                    crestIcon:SetScript("OnLeave", function()
                        HideTooltip()
                    end)
                    BindForwardScrollWheel(crestIcon)
                end
            end
            
            local crestBottomY = rowTopY + rowIconSize + 28
            local summaryNeededH = math.max(200, crestBottomY + cardPadding, summaryAffixBottom + cardPadding)
            summaryCard:SetHeight(summaryNeededH)
            summaryCard:Show()
            
            -- === CARD 3: GREAT VAULT (30%) ===
            local vaultCard = CreateCard(cardContainer, baseCardHeight)
            vaultCard:SetPoint("TOPLEFT", PixelSnap(card1Width + card2Width), 0)
            local baseCardWidth = card3Width
            
            -- Helper function to get WoW icon textures for vault activity types
            local function GetVaultTypeIcon(typeName)
                local icons = {
                    ["Raid"] = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
                    ["M+"] = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
                    ["World"] = "Interface\\Icons\\INV_Misc_Map_01"
                }
                return icons[typeName] or "Interface\\Icons\\INV_Misc_QuestionMark"
            end
            
            local vaultY = 0  -- No top padding - start from 0
        
        -- Get vault activities (from PvECacheService structure)
        local vaultActivitiesData = pve.vaultActivities
        
        -- CRITICAL: Create a NEW table on each render (don't reuse old data)
        local vaultActivities = {}
        
        -- Flatten vault activities (raids, mythicPlus, pvp, world) into single array
        if vaultActivitiesData then
            if vaultActivitiesData.raids then
                for i = 1, #vaultActivitiesData.raids do
                    local activity = vaultActivitiesData.raids[i]
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.mythicPlus then
                for i = 1, #vaultActivitiesData.mythicPlus do
                    local activity = vaultActivitiesData.mythicPlus[i]
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.pvp then
                for i = 1, #vaultActivitiesData.pvp do
                    local activity = vaultActivitiesData.pvp[i]
                    table.insert(vaultActivities, activity)
                end
            end
            if vaultActivitiesData.world then
                for i = 1, #vaultActivitiesData.world do
                    local activity = vaultActivitiesData.world[i]
                    table.insert(vaultActivities, activity)
                end
            end
        end
        
        if #vaultActivities > 0 then
            local vaultByType = {}
            for i = 1, #vaultActivities do
                local activity = vaultActivities[i]
                -- CRITICAL: Use locale-independent internal keys for vaultByType.
                -- Helper functions (IsVaultSlotAtMax, GetVaultActivityDisplayText, etc.)
                -- expect "Raid", "M+", "World", "PvP" — NOT locale strings.
                local internalKey = nil
                local typeNum = activity.type
                
                if Enum and Enum.WeeklyRewardChestThresholdType then
                    if typeNum == Enum.WeeklyRewardChestThresholdType.Raid then internalKey = "Raid"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.Activities then internalKey = "M+"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.RankedPvP then internalKey = "PvP"
                    elseif typeNum == Enum.WeeklyRewardChestThresholdType.World then internalKey = "World"
                    end
                else
                    -- Fallback numeric values based on API:
                    -- 1 = Activities (M+), 2 = RankedPvP, 3 = Raid, 6 = World
                    if typeNum == 3 then internalKey = "Raid"
                    elseif typeNum == 1 then internalKey = "M+"
                    elseif typeNum == 2 then internalKey = "PvP"
                    elseif typeNum == 6 then internalKey = "World"
                    end
                end
                
                if internalKey then
                    if not vaultByType[internalKey] then vaultByType[internalKey] = {} end
                    table.insert(vaultByType[internalKey], activity)
                end
            end
            
            local paintedH = select(1, self:PaintPvEVaultGridOnCard(vaultCard, {
                baseCardWidth = baseCardWidth,
                baseCardHeight = baseCardHeight,
                vaultByType = vaultByType,
                pve = pve,
                vaultActivitiesData = vaultActivitiesData,
                isCurrentChar = isCurrentChar,
            }))
            cardHeight = paintedH
        else
            -- No vault data: Still set card dimensions so it's visible
            vaultCard:SetHeight(baseCardHeight)
            vaultCard:SetWidth(baseCardWidth)
            
            local noVault = FontManager:CreateFontString(vaultCard, "small", "OVERLAY")
            noVault:SetPoint("CENTER", vaultCard, "CENTER", 0, 0)
            local noVaultLabel = (ns.L and ns.L["NO_VAULT_DATA"]) or "No vault data"
            noVault:SetText("|cff666666" .. noVaultLabel .. "|r")
        end
        
        vaultCard:Show()

            -- Single row height: all three cards share the same bottom edge (vault/M+ often tallest).
            local vaultPaintedH = cardHeight or baseCardHeight
            local mH = mplusCard:GetHeight() or baseCardHeight
            local sH = summaryCard:GetHeight() or baseCardHeight
            local vH = vaultCard:GetHeight() or vaultPaintedH
            local unifiedRowH = math.max(160, mH, sH, vH)
            mplusCard:SetHeight(unifiedRowH)
            summaryCard:SetHeight(unifiedRowH)
            vaultCard:SetHeight(unifiedRowH)
            cardContainer:SetHeight(unifiedRowH)
            charDetailContent._wnAccordionFullH = unifiedRowH
end

--- Group id from secKey "pve_grp:<id>". Prefix is 8 chars ("pve_grp:"); using sub(10) strips the first id character and breaks lookups.
local function PveGroupIdFromSectionSecKey(secKey)
    if type(secKey) ~= "string" then return nil end
    return secKey:match("^pve_grp:(.+)$")
end

--- One Favorites / custom / Characters accordion on the PvE scroll child (ProfessionsUI-style shell; rows painted separately).
--- @param layoutTailFrame nil or frame to stack below (last character detail or previous section body)
--- @return sectionContent frame to parent per-character PvE rows under
local function PvEUI_CreatePvETabSectionShell(addon, scrollParent, profile, opts)
    local chars = opts.chars
    local headerLabel = opts.headerLabel
    local sectionUiKey = opts.sectionUiKey -- profile.ui key when not using characterGroupExpanded
    local defaultExpanded = opts.defaultExpanded ~= false
    local headerAtlas = opts.headerAtlas
    local visualOpts = opts.visualOpts
    local layoutTailFrame = opts.layoutTailFrame
    local totalLH = opts.totalLH
    local scrollFrameRef = opts.scrollFrameRef
    local yTop = opts.yTop
    local SIDE_MARGIN0 = opts.sideMargin or SIDE_MARGIN

    if not chars or #chars == 0 then return nil end
    if not profile.ui then profile.ui = {} end

    local SECTION_COLLAPSE_HEADER_HEIGHT = GetLayout().SECTION_COLLAPSE_HEADER_HEIGHT or 36
    local isExpanded
    if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
        local gid = visualOpts.groupId
        if not profile.characterGroupExpanded then profile.characterGroupExpanded = {} end
        isExpanded = profile.characterGroupExpanded[gid]
        if isExpanded == nil then isExpanded = defaultExpanded end
    else
        isExpanded = profile.ui[sectionUiKey]
        if isExpanded == nil then isExpanded = defaultExpanded end
    end

    local sectionContent
    local headerVisualOpts = BuildAccordionVisualOpts({
        bodyGetter = function() return sectionContent end,
        persistFn = function(exp)
            if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
                local gid = visualOpts.groupId
                if not profile.characterGroupExpanded then profile.characterGroupExpanded = {} end
                profile.characterGroupExpanded[gid] = exp
            else
                profile.ui[sectionUiKey] = exp
            end
        end,
        -- Do not resize scrollParent from section accordion tweens (same class of bug as per-character rows).
        onUpdate = function()
            if scrollFrameRef and scrollFrameRef.GetVerticalScrollRange and scrollFrameRef.GetVerticalScroll and scrollFrameRef.SetVerticalScroll then
                local maxV = scrollFrameRef:GetVerticalScrollRange() or 0
                local cur = scrollFrameRef:GetVerticalScroll() or 0
                scrollFrameRef:SetVerticalScroll(math.min(math.max(cur, 0), maxV))
            end
        end,
        onComplete = function()
            if scrollFrameRef and scrollFrameRef.GetVerticalScrollRange and scrollFrameRef.GetVerticalScroll and scrollFrameRef.SetVerticalScroll then
                local maxV = scrollFrameRef:GetVerticalScrollRange() or 0
                local cur = scrollFrameRef:GetVerticalScroll() or 0
                scrollFrameRef:SetVerticalScroll(math.min(math.max(cur, 0), maxV))
            end
        end,
    }) or {}
    if visualOpts and visualOpts.sectionPreset then
        headerVisualOpts.sectionPreset = visualOpts.sectionPreset
    end

    local expandKey = opts.expandKey
    if not expandKey then
        if visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId then
            -- Same identity as Characters tab custom sections (SharedWidgets / roster parity).
            expandKey = "cgrp_" .. tostring(visualOpts.groupId)
        else
            expandKey = sectionUiKey or "pveSection"
        end
    end

    local header, grpExpandIcon, hdrIcon, grpHeaderText = CreateCollapsibleHeader(
        scrollParent,
        headerLabel,
        expandKey,
        isExpanded,
        function(expanded)
            if sectionContent then
                if expanded then
                    sectionContent:Show()
                    sectionContent:SetHeight(math.max(0.1, sectionContent._wnAccordionFullH or 0.1))
                else
                    sectionContent:Hide()
                    sectionContent:SetHeight(0.1)
                end
            end
        end,
        headerAtlas,
        true,
        nil,
        nil,
        headerVisualOpts
    )
    local isCustomRosterSection = visualOpts and visualOpts.useCharacterGroupExpand and visualOpts.groupId
    -- Match Characters tab icon sizing exactly:
    --   Favorites          (gold preset, NO useCharacterGroupExpand) -> 28x28
    --   Custom roster      (useCharacterGroupExpand + groupId)        -> 24x24
    --   Regular Characters (no visualOpts)                            -> 24x24
    local isFavoritesSectionForIcon = visualOpts and visualOpts.sectionPreset == "gold" and not isCustomRosterSection
    if hdrIcon then
        local sz = isFavoritesSectionForIcon and 28 or 24
        hdrIcon:SetSize(sz, sz)
    end
    header:SetHeight(SECTION_COLLAPSE_HEADER_HEIGHT)
    if layoutTailFrame then
        header:SetPoint("TOPLEFT", layoutTailFrame, "BOTTOMLEFT", SIDE_MARGIN0, -4)
        header:SetPoint("TOPRIGHT", layoutTailFrame, "BOTTOMRIGHT", -SIDE_MARGIN0, -4)
    else
        header:SetPoint("TOPLEFT", scrollParent, "TOPLEFT", SIDE_MARGIN0, -yTop)
        header:SetPoint("TOPRIGHT", scrollParent, "TOPRIGHT", -SIDE_MARGIN0, -yTop)
    end

    totalLH.v = totalLH.v + SECTION_COLLAPSE_HEADER_HEIGHT

    -- Custom roster sections: count + gold star (same as Professions). Roster edits only on Character tab.
    -- Non-custom sections (Favorites / Characters): simple right-anchored count badge to match
    -- Characters tab pattern (count:SetPoint("RIGHT", -14, 0); headerText keeps default LEFT anchor).
    if isCustomRosterSection and ns.UI_DecorateCustomHeader then
        ns.UI_DecorateCustomHeader(header, {
            groupId = visualOpts.groupId,
            memberCount = #chars,
            addon = addon,
            profile = profile,
            expandIcon = grpExpandIcon,
            iconFrame = hdrIcon,
            headerText = grpHeaderText,
            includeAddButton = false,
            refreshTab = "pve",
            allowSectionHighlightToggle = false,
        })
    else
        local FormatNumberFn = ns.UI_FormatNumber or function(n) return tostring(n or 0) end
        local countHex = ((visualOpts and visualOpts.sectionPreset == "danger") and "|cff888888") or "|cffaaaaaa"
        if not header._wnPveSectionCount then
            header._wnPveSectionCount = FontManager:CreateFontString(header, "header", "OVERLAY")
        end
        local cntFs = header._wnPveSectionCount
        cntFs:ClearAllPoints()
        cntFs:SetPoint("RIGHT", header, "RIGHT", -14, 0)
        cntFs:SetJustifyH("RIGHT")
        cntFs:SetText(countHex .. FormatNumberFn(#chars) .. "|r")
        cntFs:Show()
    end

    if ns.UI and ns.UI.Factory and ns.UI.Factory.CreateContainer then
        sectionContent = ns.UI.Factory:CreateContainer(scrollParent, math.max(1, scrollParent:GetWidth()), 1, false)
    else
        sectionContent = CreateFrame("Frame", nil, scrollParent)
        sectionContent:SetSize(math.max(1, scrollParent:GetWidth()), 1)
    end
    sectionContent:ClearAllPoints()
    sectionContent:SetPoint("TOPLEFT", header, "BOTTOMLEFT", -SIDE_MARGIN0, 0)
    sectionContent:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", SIDE_MARGIN0, 0)
    sectionContent:SetHeight(0.1)
    sectionContent._wnAccordionFullH = 0
    sectionContent._pveRunningH = 0

    if isExpanded then
        sectionContent:Show()
        sectionContent:SetHeight(math.max(0.1, sectionContent._wnAccordionFullH or 0.1))
    else
        sectionContent:Hide()
        sectionContent:SetHeight(0.1)
    end

    return sectionContent
end

--============================================================================
-- DRAW PVE PROGRESS (Great Vault, Lockouts, M+)
--============================================================================

-- Packed chunk locals for PvE draw body (Lua 5.1 max 60 upvalues per function).
if not ns.PvEDrawLibs then
    ns.PvEDrawLibs = {
        ns = ns,
        E = E,
        issecretvalue = issecretvalue,
        WarbandNexus = WarbandNexus,
        FontManager = FontManager,
        ShowTooltip = ShowTooltip,
        HideTooltip = HideTooltip,
        CreateCard = CreateCard,
        CreateCollapsibleHeader = CreateCollapsibleHeader,
        BuildAccordionVisualOpts = BuildAccordionVisualOpts,
        DrawEmptyState = DrawEmptyState,
        CreateEmptyStateCard = CreateEmptyStateCard,
        HideEmptyStateCard = HideEmptyStateCard,
        CreateThemedButton = CreateThemedButton,
        CreateThemedCheckbox = CreateThemedCheckbox,
        CreateIcon = CreateIcon,
        CreateDBVersionBadge = CreateDBVersionBadge,
        ApplyVisuals = ApplyVisuals,
        FormatNumber = FormatNumber,
        COLORS = COLORS,
        GetLayout = GetLayout,
        ROW_HEIGHT = ROW_HEIGHT,
        ROW_SPACING = ROW_SPACING,
        HEADER_SPACING = HEADER_SPACING,
        SECTION_SPACING = SECTION_SPACING,
        BASE_INDENT = BASE_INDENT,
        SUBROW_EXTRA_INDENT = SUBROW_EXTRA_INDENT,
        SIDE_MARGIN = SIDE_MARGIN,
        TOP_MARGIN = TOP_MARGIN,
        PVE_CHAR_HEADER_H_MARGIN = PVE_CHAR_HEADER_H_MARGIN,
        PvE_ComputeCharacterRowPrefixToGoldPx = ns.PvE_ComputeCharacterRowPrefixToGoldPx,
        PvEUI_ApplyCharacterListRowChrome = ns.PvEUI_ApplyCharacterListRowChrome,
        PVE_COLUMN_HEADER_PAD = PVE_COLUMN_HEADER_PAD,
        PVE_COL_SPACING = PVE_COL_SPACING,
        PVE_KEY_TO_VAULT_GAP = PVE_KEY_TO_VAULT_GAP,
        PVE_VAULT_CLUSTER_GAP = PVE_VAULT_CLUSTER_GAP,
        PVE_COL_RIGHT_MARGIN = PVE_COL_RIGHT_MARGIN,
        PVE_DAWNCREST_COL_W = PVE_DAWNCREST_COL_W,
        PVE_COFFER_COL_W = PVE_COFFER_COL_W,
        PVE_KEY_COL_W = PVE_KEY_COL_W,
        PVE_VAULT_COL_W = PVE_VAULT_COL_W,
        PVE_BOUNTIFUL_COL_W = PVE_BOUNTIFUL_COL_W,
        PVE_STATUS_COL_W = PVE_STATUS_COL_W,
        PVE_VOIDCORE_COL_W = PVE_VOIDCORE_COL_W,
        PVE_MANAFLUX_COL_W = PVE_MANAFLUX_COL_W,
        PVE_VOIDCORE_ID = PVE_VOIDCORE_ID,
        PVE_MANAFLUX_ID = PVE_MANAFLUX_ID,
        VAULT_SLOT_CHECK = VAULT_SLOT_CHECK,
        VAULT_SLOT_CROSS = VAULT_SLOT_CROSS,
        VAULT_SLOT_UPARROW = VAULT_SLOT_UPARROW,
        GetLocalizedText = GetLocalizedText,
        GetLowLevelHideThreshold = GetLowLevelHideThreshold,
        GetPvEDawnCrestColumnDefinitions = GetPvEDawnCrestColumnDefinitions,
        _pveDelveCurrencyCache = _pveDelveCurrencyCache,
        _pveCurrencyInfoDisplayCache = _pveCurrencyInfoDisplayCache,
        _pveDrawPool = _pveDrawPool,
        PvE_EnsureDrawPoolHolder = PvE_EnsureDrawPoolHolder,
        PvESyncPvEPools = PvESyncPvEPools,
        PvE_GetDrawPoolMeasureFS = PvE_GetDrawPoolMeasureFS,
        PvEAcquireColHeaderLabel = PvEAcquireColHeaderLabel,
        PvEAcquireInlineCell = PvEAcquireInlineCell,
        GetPvECachedCurrencyDisplay = GetPvECachedCurrencyDisplay,
        EnsureVaultButtonColumnsForPvE = EnsureVaultButtonColumnsForPvE,
        EnsurePvEExtraVisibleColumns = EnsurePvEExtraVisibleColumns,
        ResolvePveDelveCurrencyColumns = ResolvePveDelveCurrencyColumns,
        GetTrovehunterBountyColumnIcon = GetTrovehunterBountyColumnIcon,
        PvE_AttachInlineColumnPicker = PvE_AttachInlineColumnPicker,
        PvE_GetCanonicalKeyForChar = PvE_GetCanonicalKeyForChar,
        CompareCharNameLower = CompareCharNameLower,
        SafeLower = SafeLower,
        expandedStates = expandedStates,
        IsExpanded = IsExpanded,
        PvEUI_CreatePvETabSectionShell = PvEUI_CreatePvETabSectionShell,
        PvEUI_PopulateExpandedCharacterDetail = PvEUI_PopulateExpandedCharacterDetail,
        PvE_FormatVaultTrackColumn = PvE_FormatVaultTrackColumn,
        BindForwardScrollWheel = BindForwardScrollWheel,
    }
end

local function PvEUI_DrawPvEProgressBody(self, parent, L)
    parent._pvePaintedCoreH = nil
    local width = parent:GetWidth() - 20
    -- Weekly Vault Tracker mode removed from PvE tab; standalone Easy Access window covers this.
    local vaultTrackerMode = false

    local fixedHeader = L.WarbandNexus.UI.mainFrame and L.WarbandNexus.UI.mainFrame.fixedHeader
    local headerParent = fixedHeader or parent
    local headerYOffset = 8
    
    -- Add DB version badge (for debugging/monitoring)
    if not parent.dbVersionBadge then
        local dataSource = "db.global.pveProgress"
        if self.db.global.pveCache and self.db.global.pveCache.version then
            local cacheVersion = self.db.global.pveCache.version or "unknown"
            dataSource = "PvECache v" .. cacheVersion
        end
        parent.dbVersionBadge = L.CreateDBVersionBadge(parent, dataSource, "TOPRIGHT", -10, -5)
    end
    
    -- Hide empty state card (will be shown again if needed)
    L.HideEmptyStateCard(parent, "pve")
    
    -- ===== AUTO-REFRESH CHECK (FULLY AUTOMATIC) =====
    local charKey = (L.ns.Utilities.GetCharacterStorageKey and L.ns.Utilities:GetCharacterStorageKey(L.WarbandNexus))
        or L.ns.Utilities:GetCharacterKey()
    local pveData = self:GetPvEData(charKey)
    
    -- Check multiple data completeness signals, not just keystone
    local needsRefresh = false
    if not pveData or not pveData.keystone then
        needsRefresh = true
    elseif pveData.vaultActivities then
        -- Check if any unlocked vault slot is missing iLvl (server was slow)
        local vaultCategories = {"raids", "mythicPlus", "world"}
        for ci = 1, #vaultCategories do
            local cat = vaultCategories[ci]
            local activities = pveData.vaultActivities[cat]
            if activities then
                for ai = 1, #activities do
                    local a = activities[ai]
                    if a and a.progress and a.threshold and a.progress >= a.threshold then
                        if not a.rewardItemLevel or a.rewardItemLevel == 0 then
                            needsRefresh = true
                            break
                        end
                    end
                end
            end
            if needsRefresh then break end
        end
    end
    
    -- Trigger refresh if needed (rate-limited to avoid spam)
    if needsRefresh and not L.ns.PvELoadingState.isLoading then
        local timeSinceLastAttempt = time() - (L.ns.PvELoadingState.lastAttempt or 0)
        if timeSinceLastAttempt > 10 then
            L.ns.PvELoadingState.lastAttempt = time()
            -- Poke server for fresh vault data before collecting
            if C_WeeklyRewards and C_WeeklyRewards.OnUIInteract then
                C_WeeklyRewards.OnUIInteract()
            end
            if self.UpdatePvEData then
                self:UpdatePvEData()
            end
            -- Schedule a follow-up refresh after server responds (vault iLvl needs time)
            C_Timer.After(3, function()
                if self.UpdatePvEData then
                    self:UpdatePvEData()
                end
            end)
        end
    end
    
    -- ===== HEADER CARD (in fixedHeader - non-scrolling) — Characters-tab layout; reserve right for timer/sort/WVT =====
    local r, g, b = L.COLORS.accent[1], L.COLORS.accent[2], L.COLORS.accent[3]
    local hexColor = string.format("%02x%02x%02x", r * 255, g * 255, b * 255)
    local titleTextContent = "|cff" .. hexColor .. ((L.ns.L and L.ns.L["PVE_TITLE"]) or "PvE Progress") .. "|r"
    local subtitleTextContent = (L.ns.L and L.ns.L["PVE_SUBTITLE"]) or "Great Vault, Raid Lockouts & Mythic+ across your Warband"
    if vaultTrackerMode then
        subtitleTextContent = (L.ns.L and L.ns.L["PVE_VAULT_TRACKER_SUBTITLE"]) or
            "Unclaimed rewards and cleared vault rows"
    end
    -- Room for weekly reset + sort/section filter + column picker (approximate, avoids overlap)
    local PVE_TITLE_RIGHT_RESERVE = 620
    local titleCard = select(1, L.ns.UI_CreateStandardTabTitleCard(headerParent, {
        tabKey = "pve",
        titleText = titleTextContent,
        subtitleText = subtitleTextContent,
        textRightInset = PVE_TITLE_RIGHT_RESERVE,
    }))
    titleCard:SetPoint("TOPLEFT", L.SIDE_MARGIN, -headerYOffset)
    titleCard:SetPoint("TOPRIGHT", -L.SIDE_MARGIN, -headerYOffset)
    
    -- Weekly reset timer (standardized widget)
    local CreateResetTimer = L.ns.UI_CreateResetTimer
    local titleCardRightInset = L.GetLayout().TITLE_CARD_CONTROL_RIGHT_INSET or 20
    local resetTimer = CreateResetTimer(
        titleCard,
        "RIGHT",
        -titleCardRightInset,
        0,
        function()
            -- Use centralized GetWeeklyResetTime from PlansManager
            if L.WarbandNexus.GetWeeklyResetTime then
                local resetTimestamp = L.WarbandNexus:GetWeeklyResetTime()
                return resetTimestamp - GetServerTime()
            end
            
            -- Fallback: Use Blizzard API
            if C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset then
                return C_DateAndTime.GetSecondsUntilWeeklyReset() or 0
            end
            
            return 0
        end
    )
    
    -- Sort + section filter (Characters/Professions parity) or legacy sort-only control
    local sortAnchor = resetTimer.container
    local sortOptions = {
        {key = "manual", label = (L.ns.L and L.ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
        {key = "name", label = (L.ns.L and L.ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
        {key = "level", label = (L.ns.L and L.ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
        {key = "ilvl", label = (L.ns.L and L.ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
        {key = "gold", label = (L.ns.L and L.ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
        {key = "realm", label = (L.ns.L and L.ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
    }
    if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
    if L.ns.UI_CreateCharacterTabAdvancedFilterButton and L.ns.CharacterService and L.ns.CharacterService.EnsureCustomCharacterSectionsProfile then
        L.ns.CharacterService:EnsureCustomCharacterSectionsProfile(self.db.profile)
        if not self.db.profile.pveSectionFilter then self.db.profile.pveSectionFilter = { sectionKey = "all" } end
        local sortBtn = L.ns.UI_CreateCharacterTabAdvancedFilterButton(titleCard, {
            sortOptions = sortOptions,
            dbSortTable = self.db.profile.pveSort,
            dbSectionFilter = self.db.profile.pveSectionFilter,
            getCustomSections = function()
                return self.db.profile.characterCustomGroups or {}
            end,
            onRefresh = function()
                L.WarbandNexus:SendMessage(L.E.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
            end,
            -- PvE: section filter only — roster edits (delete custom header) stay on Character tab.
        })
        if sortBtn then
            sortBtn:SetPoint("RIGHT", resetTimer.container, "LEFT", -15, 0)
            sortAnchor = sortBtn
        end
    elseif L.ns.UI_CreateCharacterSortDropdown then
        local sortBtn = L.ns.UI_CreateCharacterSortDropdown(titleCard, sortOptions, self.db.profile.pveSort, function()
            L.WarbandNexus:SendMessage(L.E.UI_MAIN_REFRESH_REQUESTED, { tab = "pve", skipCooldown = true })
        end)
        sortBtn:SetPoint("RIGHT", resetTimer.container, "LEFT", -15, 0)
        sortAnchor = sortBtn
    end

    -- Column visibility (Vault Tracker parity: vaultButton.columns + PvE crest/shard/key toggles)
    sortAnchor = L.PvE_AttachInlineColumnPicker(titleCard, sortAnchor, self)

    titleCard:Show()
    headerYOffset = headerYOffset + L.GetLayout().afterHeader
    -- Title only; column headers live in columnHeaderClip (horizontal sync with scroll child)
    if fixedHeader then fixedHeader:SetHeight(headerYOffset) end

    -- ===== COLUMN HEADER ROW (inline PvE status summary) =====
    -- All Midnight Dawncrest tiers — IDs from Constants.MIDNIGHT_S1 (same as Gear / Currency cache)
    local PVE_DAWNCRESTS = L.GetPvEDawnCrestColumnDefinitions()
    local PVE_RESTORED_KEY_FALLBACK_ID = 3089
    L.ResolvePveDelveCurrencyColumns(self)
    local PVE_SHARDS_ID = L._pveDelveCurrencyCache.shardsID
    local PVE_RESTORED_KEY_ID = L._pveDelveCurrencyCache.keyID
    local PVE_SHARDS_ICON = L._pveDelveCurrencyCache.shardsIcon or "Interface\\Icons\\INV_Misc_Gem_Variety_01"
    local PVE_RESTORED_KEY_ICON = L._pveDelveCurrencyCache.keyIcon or "Interface\\Icons\\INV_Misc_Key_13"

    -- Fallback for Restored Coffer Key when dynamic lookup doesn't resolve.
    if not PVE_RESTORED_KEY_ID then
        PVE_RESTORED_KEY_ID = PVE_RESTORED_KEY_FALLBACK_ID
    end

    local profile = self.db and self.db.profile
    local vaultCols = L.EnsureVaultButtonColumnsForPvE(profile)
    local pveExtraCols = L.EnsurePvEExtraVisibleColumns(profile)
    local PVE_COLUMNS = {}
    for i = 1, #PVE_DAWNCRESTS do
        local crestEntry = PVE_DAWNCRESTS[i]
        local ck = "crest_" .. tostring(crestEntry.id)
        if pveExtraCols[ck] ~= false then
            local crestIcon = 134400
            local crestLabel = ""
            local disp = L.GetPvECachedCurrencyDisplay(crestEntry.id)
            if disp then
                if disp.iconFileID then
                    crestIcon = disp.iconFileID
                end
                if disp.name and disp.name ~= "" and not (L.issecretvalue and L.issecretvalue(disp.name)) then
                    crestLabel = disp.name
                end
            end
            if crestLabel == "" and crestEntry.labelKey then
                crestLabel = L.GetLocalizedText(crestEntry.labelKey, "")
            end
            PVE_COLUMNS[#PVE_COLUMNS + 1] = {
                key = ck,
                label = "",
                width = L.PVE_DAWNCREST_COL_W,
                icon = crestIcon,
                crestCurrencyId = crestEntry.id,
                headerLabel = crestLabel,
            }
        end
    end
    if pveExtraCols.coffer_shards ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "coffer_shards",
            label = "",
            width = L.PVE_COFFER_COL_W,
            icon = PVE_SHARDS_ICON,
            tooltipTitle = L.GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"),
            headerLabel = L.GetLocalizedText("PVE_COL_COFFER_SHARDS", "Coffer Shards"),
        }
    end
    if pveExtraCols.restored_key ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "restored_key",
            label = "",
            width = L.PVE_KEY_COL_W,
            icon = PVE_RESTORED_KEY_ICON,
            tooltipTitle = L.GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Key"),
            headerLabel = L.GetLocalizedText("PVE_COL_RESTORED_KEY", "Restored Key"),
        }
    end
    if vaultCols.voidcore ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "voidcore",
            label = "",
            width = L.PVE_VOIDCORE_COL_W,
            icon = 7658128,
            tooltipTitle = L.GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"),
            headerLabel = L.GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"),
        }
    end
    if vaultCols.manaflux == true then
        local manafluxIcon = "Interface\\Icons\\INV_Enchant_DustArcane"
        local mfDisp = L.GetPvECachedCurrencyDisplay(L.PVE_MANAFLUX_ID)
        if mfDisp and mfDisp.iconFileID then
            manafluxIcon = mfDisp.iconFileID
        end
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "manaflux",
            label = "",
            width = L.PVE_MANAFLUX_COL_W,
            icon = manafluxIcon,
            tooltipTitle = L.GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"),
            headerLabel = L.GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"),
        }
    end
    if vaultCols.raids ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot1",
            label = "",
            width = L.PVE_VAULT_COL_W,
            icon = "Interface\\Icons\\INV_Misc_Head_Dragon_01",
            tooltipTitle = (L.ns.L and L.ns.L["PVE_HEADER_RAIDS"]) or "Raids",
            headerLabel = L.GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"),
        }
    end
    if vaultCols.mythicPlus ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot2",
            label = "",
            width = L.PVE_VAULT_COL_W,
            icon = "Interface\\Icons\\Achievement_ChallengeMode_Gold",
            tooltipTitle = (L.ns.L and L.ns.L["PVE_HEADER_DUNGEONS"]) or "Dungeons",
            headerLabel = L.GetLocalizedText("VAULT_DUNGEON", "Dungeon"),
        }
    end
    if vaultCols.world ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "slot3",
            label = "",
            width = L.PVE_VAULT_COL_W,
            icon = "Interface\\Icons\\INV_Misc_Map_01",
            tooltipTitle = (L.ns.L and L.ns.L["VAULT_WORLD"]) or "World",
            headerLabel = L.GetLocalizedText("VAULT_SLOT_WORLD", "World"),
        }
    end
    -- Bountiful weekly — Trovehunter's Bounty item icon (live fileID when API returns it)
    if vaultCols.bounty ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "bountiful",
            label = "",
            width = L.PVE_BOUNTIFUL_COL_W,
            icon = L.GetTrovehunterBountyColumnIcon(),
            tooltipTitle = (L.ns.L and L.ns.L["BOUNTIFUL_DELVE"]) or "Trovehunter's Bounty",
            headerLabel = L.GetLocalizedText("PVE_HEADER_MAP_SHORT", "Map"),
        }
    end
    -- Vault Status — same Ready/Slots Earned/Pending readout as the Vault Tracker quick window.
    if vaultCols.status ~= false then
        PVE_COLUMNS[#PVE_COLUMNS + 1] = {
            key = "vault_status",
            label = "",
            width = L.PVE_STATUS_COL_W,
            icon = "Interface\\Icons\\Achievement_Boss_Argus",
            tooltipTitle = (L.ns.L and L.ns.L["PVE_COL_VAULT_STATUS"]) or "Vault Status",
            headerLabel = L.GetLocalizedText("PVE_HEADER_STATUS_SHORT", "Status"),
        }
    end

    local COL_SPACING = L.PVE_COL_SPACING
    local COL_RIGHT_MARGIN = L.PVE_COL_RIGHT_MARGIN
    local COL_ICON_SIZE = 24
    local COL_HEADER_HEIGHT = 48
    local visiblePveColumnKeys = {}
    local colSigParts = {}
    for i = 1, #PVE_COLUMNS do
        local ck = PVE_COLUMNS[i].key
        visiblePveColumnKeys[ck] = true
        colSigParts[i] = ck
    end
    local colSig = table.concat(colSigParts, "\1")
    local function GapBetweenColumns(leftIdx)
        local leftCol = PVE_COLUMNS[leftIdx]
        if not leftCol then return L.PVE_COL_SPACING end
        local key = leftCol.key
        if key == "manaflux" then return L.PVE_KEY_TO_VAULT_GAP end
        if key == "voidcore" and (not visiblePveColumnKeys.manaflux) then return L.PVE_KEY_TO_VAULT_GAP end
        if key == "restored_key" and (not visiblePveColumnKeys.voidcore) and (not visiblePveColumnKeys.manaflux) then
            return L.PVE_KEY_TO_VAULT_GAP
        end
        if key == "slot1" or key == "slot2" then return L.PVE_VAULT_CLUSTER_GAP end
        if key == "slot3" then return L.PVE_KEY_TO_VAULT_GAP end
        return L.PVE_COL_SPACING
    end

    local yOffset = 8

    -- Check if module is disabled - show beautiful disabled state card (before column strip / scroll width)
    if not L.ns.Utilities:IsModuleEnabled("pve") then
        L.WarbandNexus._pveVaultTooltipCharsSnapshot = {}
        local CreateDisabledCard = L.ns.UI_CreateDisabledModuleCard
        local cardHeight = CreateDisabledCard(parent, yOffset, (L.ns.L and L.ns.L["PVE_TITLE"]) or "PvE Progress")
        return yOffset + cardHeight
    end
    
    -- Get all characters (filter tracked only for PvE display).
    -- Also honor profile.hideLowLevelThreshold: 0 (off), 80, or 90.
    local allCharacters = self:GetAllCharacters()
    local characters = {}
    local minLevel = L.GetLowLevelHideThreshold(profile)
    for i = 1, #allCharacters do
        local char = allCharacters[i]
        local lvl = tonumber(char.level) or 0
        if char.isTracked ~= false and (minLevel == 0 or lvl >= minLevel) then
            table.insert(characters, char)
        end
    end

    local function GetRowCanonicalPvEKey(char)
        return L.PvE_GetCanonicalKeyForChar(char)
    end
    
    -- Canonical key must match PvECacheService writes and GetPvEData(charKey) lookups
    local currentPlayerKey = (L.ns.CharacterService and L.ns.CharacterService.ResolveCharactersTableKey and L.ns.CharacterService:ResolveCharactersTableKey(L.WarbandNexus))
        or (L.ns.Utilities.GetCharacterStorageKey and L.ns.Utilities:GetCharacterStorageKey(L.WarbandNexus))
        or L.ns.Utilities:GetCharacterKey()
    if L.ns.Utilities.GetCanonicalCharacterKey and currentPlayerKey then
        currentPlayerKey = L.ns.Utilities:GetCanonicalCharacterKey(currentPlayerKey) or currentPlayerKey
    end
    
    -- Load sorting preferences from profile (persistent across sessions)
    if not parent.sortPrefsLoaded then
        parent.sortKey = self.db.profile.pveSort.key
        parent.sortAscending = self.db.profile.pveSort.ascending
        parent.sortPrefsLoaded = true
    end
    
    local sortOptions = {
        {key = "manual", label = (L.ns.L and L.ns.L["SORT_MODE_MANUAL"]) or "Manual (Custom Order)"},
        {key = "name", label = (L.ns.L and L.ns.L["SORT_MODE_NAME"]) or "Name (A-Z)"},
        {key = "level", label = (L.ns.L and L.ns.L["SORT_MODE_LEVEL"]) or "Level (Highest)"},
        {key = "ilvl", label = (L.ns.L and L.ns.L["SORT_MODE_ILVL"]) or "Item Level (Highest)"},
        {key = "gold", label = (L.ns.L and L.ns.L["SORT_MODE_GOLD"]) or "Gold (Highest)"},
        {key = "realm", label = (L.ns.L and L.ns.L["SORT_MODE_REALM"]) or "Realm (A-Z)"},
    }
    
    if not self.db.profile.pveSort then self.db.profile.pveSort = {} end
    if profile then
        if not profile.pveSectionFilter then profile.pveSectionFilter = { sectionKey = "all" } end
        if L.ns.CharacterService and L.ns.CharacterService.EnsureCustomCharacterSectionsProfile then
            L.ns.CharacterService:EnsureCustomCharacterSectionsProfile(profile)
        end
    end

    -- ===== SORT CHARACTERS WITH FAVORITES ALWAYS ON TOP =====
    -- Use the same sorting logic as Characters tab
    local currentChar = nil
    local favorites = {}
    local regular = {}
    
    for i = 1, #characters do
        local char = characters[i]
        -- CRITICAL: Same canonical key as PvECacheService + row loop below (vault/M+ are per-key in pveCache)
        local charKey = GetRowCanonicalPvEKey(char)
        
        -- Separate current character
        if charKey == currentPlayerKey then
            currentChar = char
        elseif L.ns.CharacterService and L.ns.CharacterService:IsFavoriteCharacter(self, charKey) then
            table.insert(favorites, char)
        else
            table.insert(regular, char)
        end
    end
    
    -- Sort function (with custom order support, same as Characters tab)
    local function sortCharacters(list, orderKey)
        local sortMode = self.db.profile.pveSort and self.db.profile.pveSort.key
        
        if sortMode and sortMode ~= "manual" then
            table.sort(list, function(a, b)
                if sortMode == "name" then
                    return L.CompareCharNameLower(a, b)
                elseif sortMode == "level" then
                    if (a.level or 0) ~= (b.level or 0) then
                        return (a.level or 0) > (b.level or 0)
                    else
                        return L.CompareCharNameLower(a, b)
                    end
                elseif sortMode == "ilvl" then
                    if (a.itemLevel or 0) ~= (b.itemLevel or 0) then
                        return (a.itemLevel or 0) > (b.itemLevel or 0)
                    else
                        return L.CompareCharNameLower(a, b)
                    end
                elseif sortMode == "gold" then
                    local goldA = L.ns.Utilities:GetCharTotalCopper(a)
                    local goldB = L.ns.Utilities:GetCharTotalCopper(b)
                    if goldA ~= goldB then
                        return goldA > goldB
                    else
                        return L.CompareCharNameLower(a, b)
                    end
                elseif sortMode == "realm" then
                    local ra = L.SafeLower(a.realm or "")
                    local rb = L.SafeLower(b.realm or "")
                    if ra ~= rb then
                        return ra < rb
                    else
                        return L.CompareCharNameLower(a, b)
                    end
                end
                -- Fallback
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return L.CompareCharNameLower(a, b)
                end
            end)
            return list
        end
        
        local customOrder = self.db.profile.characterOrder and self.db.profile.characterOrder[orderKey] or {}
        
        -- If custom order exists and has items, use it
        if #customOrder > 0 then
            local ordered = {}
            local charMap = {}
            
            -- Create a map for quick lookup
            for i = 1, #list do
                local char = list[i]
                local key = GetRowCanonicalPvEKey(char)
                if key then charMap[key] = char end
            end
            
            -- Add characters in custom order
            for i = 1, #customOrder do
                local charKey = customOrder[i]
                if charMap[charKey] then
                    table.insert(ordered, charMap[charKey])
                    charMap[charKey] = nil  -- Remove to track remaining
                end
            end
            
            -- Add any new characters not in custom order (at the end, sorted)
            local remaining = {}
            for _, char in pairs(charMap) do
                table.insert(remaining, char)
            end
            table.sort(remaining, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return L.CompareCharNameLower(a, b)
                end
            end)
            for i = 1, #remaining do
                local char = remaining[i]
                table.insert(ordered, char)
            end
            
            return ordered
        else
            -- Default sort: level desc → name asc
            table.sort(list, function(a, b)
                if (a.level or 0) ~= (b.level or 0) then
                    return (a.level or 0) > (b.level or 0)
                else
                    return L.CompareCharNameLower(a, b)
                end
            end)
            return list
        end
    end
    
    -- Sort favorites; split non-favorites into custom sections + main list (Characters tab parity)
    favorites = sortCharacters(favorites, "favorites")
    local groupedById = {}
    local regularUngrouped = {}
    for rxi = 1, #regular do
        local rchar = regular[rxi]
        local rKey = GetRowCanonicalPvEKey(rchar)
        local gsec = L.ns.CharacterService and L.ns.CharacterService.GetCharacterCustomSectionId
            and L.ns.CharacterService:GetCharacterCustomSectionId(self, rKey) or nil
        if gsec then
            -- Keys must match gMeta.id / PveGroupIdFromSectionSecKey (string) — mixed number|string IDs broke groupedDisplay lookup.
            local gk = tostring(gsec)
            if not groupedById[gk] then groupedById[gk] = {} end
            groupedById[gk][#groupedById[gk] + 1] = rchar
        else
            regularUngrouped[#regularUngrouped + 1] = rchar
        end
    end
    local sortModeKey = (self.db.profile.pveSort and self.db.profile.pveSort.key) or "default"
    local customGroupsOrdered = {}
    if profile and L.ns.CharacterService and L.ns.CharacterService.BuildOrderedCustomCharacterGroups then
        customGroupsOrdered = L.ns.CharacterService:BuildOrderedCustomCharacterGroups(profile, sortModeKey)
    end
    for oci = 1, #customGroupsOrdered do
        local gid0 = customGroupsOrdered[oci].id
        local gk0 = tostring(gid0)
        local gL = groupedById[gk0]
        if gL and #gL > 0 then
            local lk0 = (L.ns.CharacterService and L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(gid0)) or "regular"
            groupedById[gk0] = sortCharacters(gL, lk0)
        end
    end
    regularUngrouped = sortCharacters(regularUngrouped, "regular")

    -- Merge: current first, then favorites, then each custom group in order, then ungrouped regular
    local sortedCharacters = {}
    if currentChar then
        sortedCharacters[#sortedCharacters + 1] = currentChar
    end
    for fi = 1, #favorites do
        sortedCharacters[#sortedCharacters + 1] = favorites[fi]
    end
    for oci = 1, #customGroupsOrdered do
        local gid1 = customGroupsOrdered[oci].id
        local gL2 = groupedById[tostring(gid1)]
        if gL2 then
            for gj = 1, #gL2 do
                sortedCharacters[#sortedCharacters + 1] = gL2[gj]
            end
        end
    end
    for ui = 1, #regularUngrouped do
        sortedCharacters[#sortedCharacters + 1] = regularUngrouped[ui]
    end
    for gidOr, listOr in pairs(groupedById) do
        local foundOr = false
        for ociOr = 1, #customGroupsOrdered do
            if tostring(customGroupsOrdered[ociOr].id) == tostring(gidOr) then
                foundOr = true
                break
            end
        end
        if not foundOr and listOr and #listOr > 0 then
            for oj = 1, #listOr do
                sortedCharacters[#sortedCharacters + 1] = listOr[oj]
            end
        end
    end
    characters = sortedCharacters
    do
        local snap = {}
        for i = 1, #characters do
            snap[i] = characters[i]
        end
        L.WarbandNexus._pveVaultTooltipCharsSnapshot = snap
    end

    local rosterSigParts = {}
    local currentKeySet = {}
    for i = 1, #characters do
        local rk = GetRowCanonicalPvEKey(characters[i])
        if rk then
            rosterSigParts[#rosterSigParts + 1] = rk
            currentKeySet[rk] = true
        end
    end
    table.sort(rosterSigParts)
    local rosterSig = tostring(#rosterSigParts) .. "\0" .. table.concat(rosterSigParts, "\1")
    local rosterChanged = (L._pveDrawPool.rosterSig ~= rosterSig)
    L.PvESyncPvEPools(rosterSig, colSig, currentKeySet, visiblePveColumnKeys)

    if vaultTrackerMode then
        --- Slots meeting vault threshold (Raid / M+ / World / PvP tracks), same rules as inline grid.
        local function CountVaultSlotsUnlocked(vaultActs)
            if not vaultActs then return 0 end
            local unlocked = 0
            local function countTrack(activityList)
                if not activityList then return end
                for idx = 1, #activityList do
                    local act = activityList[idx]
                    if act and act.threshold and act.threshold > 0 and act.progress and act.progress >= act.threshold then
                        unlocked = unlocked + 1
                    end
                end
            end
            countTrack(vaultActs.raids)
            countTrack(vaultActs.mythicPlus)
            countTrack(vaultActs.world)
            countTrack(vaultActs.pvp)
            return unlocked
        end

        local function ResolveVaultClaimable(charKey, charPveData)
            local hasClaimable = charPveData.vaultRewards and charPveData.vaultRewards.hasAvailableRewards == true
            if (not hasClaimable) and charKey == currentPlayerKey and self.HasUnclaimedVaultRewards then
                local ok, liveHasRewards = pcall(self.HasUnclaimedVaultRewards, self)
                hasClaimable = ok and liveHasRewards == true
            end
            return hasClaimable
        end

        --- True when PvE cache has at least one Great Vault activity row (Raid / M+ / World / PvP).
        local function HasVaultActivitySnapshot(vaultActs)
            if not vaultActs then return false end
            local keys = { "raids", "mythicPlus", "world", "pvp" }
            for ki = 1, #keys do
                local list = vaultActs[keys[ki]]
                if list and #list > 0 then
                    return true
                end
            end
            return false
        end

        --- WVT: only toons with vault data (cached activity rows, unlocked vault slots, or rewards to claim).
        local function IncludeInVaultTracker(charKey, charPveData)
            if ResolveVaultClaimable(charKey, charPveData) then
                return true
            end
            local vaultActs = charPveData.vaultActivities
            if HasVaultActivitySnapshot(vaultActs) then
                return true
            end
            if CountVaultSlotsUnlocked(vaultActs) >= 1 then
                return true
            end
            return false
        end

        local claimFirst = {}
        local rest = {}
        for i = 1, #characters do
            local char = characters[i]
            local charKey = GetRowCanonicalPvEKey(char)
            if charKey then
                local charPveData = self:GetPvEData(charKey) or {}
                if IncludeInVaultTracker(charKey, charPveData) then
                    if ResolveVaultClaimable(charKey, charPveData) then
                        claimFirst[#claimFirst + 1] = char
                    else
                        rest[#rest + 1] = char
                    end
                end
            end
        end
        characters = {}
        for j = 1, #claimFirst do characters[#characters + 1] = claimFirst[j] end
        for j = 1, #rest do characters[#characters + 1] = rest[j] end
    end

    -- ===== LOADING / ERROR / EMPTY (before column strip — vault tracker uses alternate layout) =====
    if L.ns.PvELoadingState and L.ns.PvELoadingState.isLoading then
        local UI_CreateLoadingStateCard = L.ns.UI_CreateLoadingStateCard
        if UI_CreateLoadingStateCard then
            local newYOffset = UI_CreateLoadingStateCard(
                parent,
                yOffset,
                L.ns.PvELoadingState,
                (L.ns.L and L.ns.L["LOADING_PVE"]) or "Loading PvE Data..."
            )
            return newYOffset + 50
        end
    end

    if L.ns.PvELoadingState and L.ns.PvELoadingState.error and not L.ns.PvELoadingState.isLoading then
        local UI_CreateErrorStateCard = L.ns.UI_CreateErrorStateCard
        if UI_CreateErrorStateCard then
            yOffset = UI_CreateErrorStateCard(parent, yOffset, L.ns.PvELoadingState.error)
        end
    end

    if #characters == 0 then
        local emptyTab = vaultTrackerMode and "pve_vault" or "pve"
        local _, height = L.CreateEmptyStateCard(parent, emptyTab, yOffset)
        return yOffset + height
    end

    if vaultTrackerMode then
        return self:DrawPvEVaultTrackerCardGrid(parent, yOffset, characters, currentPlayerKey)
    end
    
    -- ===== NAME WIDTH (measured from longest name; no compression — scroll handles overflow) =====
    local tempMeasure = L.PvE_GetDrawPoolMeasureFS()
    tempMeasure:Hide()
    local maxNameRealmWidth = 0
    if rosterChanged then
        for i = 1, #characters do
            local c = characters[i]
            local k = GetRowCanonicalPvEKey(c)
            if k then
                local nameStr = c.name or "Unknown"
                if L.issecretvalue and L.issecretvalue(nameStr) then
                    nameStr = "Unknown"
                end
                local realmStr = L.ns.Utilities and L.ns.Utilities:FormatRealmName(c.realm) or c.realm or ""
                if realmStr ~= "" and L.issecretvalue and L.issecretvalue(realmStr) then
                    realmStr = ""
                end
                tempMeasure:SetText(nameStr .. "  -  " .. realmStr)
                local w = tempMeasure:GetStringWidth() or 0
                L._pveDrawPool.nameWidths[k] = w
                if w > maxNameRealmWidth then maxNameRealmWidth = w end
            end
        end
    else
        for i = 1, #characters do
            local k = GetRowCanonicalPvEKey(characters[i])
            if k then
                local w = L._pveDrawPool.nameWidths[k]
                if w and w > maxNameRealmWidth then maxNameRealmWidth = w end
            end
        end
    end
    local nameWidth = math.max(200, math.ceil(maxNameRealmWidth) + 8)

    -- Wide enough for left cluster + name + level/ilvl + inline columns → horizontal scrollbar when needed
    local scrollFrame = parent:GetParent()
    local viewportW = (scrollFrame and scrollFrame:GetWidth()) or 800
    local inlineTotal = 0
    for pci = 1, #PVE_COLUMNS do
        inlineTotal = inlineTotal + PVE_COLUMNS[pci].width
    end
    for gi = 1, #PVE_COLUMNS - 1 do
        inlineTotal = inlineTotal + GapBetweenColumns(gi)
    end
    inlineTotal = inlineTotal + COL_RIGHT_MARGIN
    local prefixW = (L.PvE_ComputeCharacterRowPrefixToGoldPx and L.PvE_ComputeCharacterRowPrefixToGoldPx(nameWidth)) or 400
    local minScrollW = L.PVE_CHAR_HEADER_H_MARGIN + prefixW + inlineTotal
    parent:SetWidth(math.max(viewportW, minScrollW))

    -- Frozen column header strip (scrolls horizontally with data — same pattern as ProfessionsUI)
    local mainFrameRef = L.WarbandNexus.UI and L.WarbandNexus.UI.mainFrame
    local columnHeaderClip = mainFrameRef and mainFrameRef.columnHeaderClip
    local columnHeaderInner = mainFrameRef and mainFrameRef.columnHeaderInner
    local colHeaderParent = columnHeaderInner or headerParent
    local colHeaderOverlayH = 0

    if columnHeaderClip then
        columnHeaderClip:Show()
        columnHeaderClip:SetHeight(COL_HEADER_HEIGHT + L.PVE_COLUMN_HEADER_PAD)
        colHeaderOverlayH = COL_HEADER_HEIGHT + L.PVE_COLUMN_HEADER_PAD
    end
    if columnHeaderInner then
        columnHeaderInner:SetWidth(parent:GetWidth())
    end

    -- ===== COLUMN HEADER ROW (icon + compact two-line labels) =====
    local colHeaderRow = L.ns.UI.Factory:CreateContainer(colHeaderParent, 10, COL_HEADER_HEIGHT)
    if columnHeaderInner then
        colHeaderRow:SetPoint("TOPLEFT", L.SIDE_MARGIN, 0)
        colHeaderRow:SetPoint("TOPRIGHT", -L.SIDE_MARGIN, 0)
    else
        colHeaderRow:SetPoint("TOPLEFT", headerParent, "TOPLEFT", L.SIDE_MARGIN, -headerYOffset)
        colHeaderRow:SetPoint("TOPRIGHT", headerParent, "TOPRIGHT", -L.SIDE_MARGIN, -headerYOffset)
        headerYOffset = headerYOffset + COL_HEADER_HEIGHT + 2
        if fixedHeader then fixedHeader:SetHeight(headerYOffset) end
    end

    local PVE_COMPACT_HEADER_BY_KEY = {
        coffer_shards = { text = L.GetLocalizedText("PVE_COMPACT_COFFER_SHARD", "Coffer Shard"), hex = "ffffff" },
        restored_key = { text = L.GetLocalizedText("PVE_COMPACT_RESTORED", "Restored"), hex = "ffffff" },
        voidcore = { text = L.GetLocalizedText("PVE_COMPACT_VOIDCORE", "Voidcore"), hex = "ffffff" },
        manaflux = { text = L.GetLocalizedText("PVE_COMPACT_MANAFLUX", "Manaflux"), hex = "ffffff" },
        slot1 = { text = L.GetLocalizedText("PVE_HEADER_RAID_SHORT", "Raid"), hex = "ffffff" },
        slot2 = { text = L.GetLocalizedText("VAULT_DUNGEON", "Dungeon"), hex = "ffffff" },
        slot3 = { text = L.GetLocalizedText("VAULT_SLOT_WORLD", "World"), hex = "ffffff" },
        bountiful = { text = L.GetLocalizedText("PVE_HEADER_MAP_SHORT", "Map"), hex = "ffffff" },
        vault_status = { text = L.GetLocalizedText("PVE_HEADER_STATUS_SHORT", "Status"), hex = "ffffff" },
    }
    local PVE_COMPACT_CREST_BY_ID = {
        [3383] = { text = L.GetLocalizedText("PVE_CREST_ADV", "Adventurer"), hex = "9d9d9d" },
        [3341] = { text = L.GetLocalizedText("PVE_CREST_VET", "Veteran"), hex = "1eff00" },
        [3343] = { text = L.GetLocalizedText("PVE_CREST_CHAMP", "Champion"), hex = "0070dd" },
        [3345] = { text = L.GetLocalizedText("PVE_CREST_HERO", "Hero"), hex = "a335ee" },
        [3347] = { text = L.GetLocalizedText("PVE_CREST_MYTH", "Myth"), hex = "ff8000" },
    }

    local function BuildCompactHeaderLabel(col)
        local rawLabel = col and (col.headerLabel or col.tooltipTitle) or ""
        if not rawLabel or rawLabel == "" then return "", "ffffff" end
        if L.issecretvalue and L.issecretvalue(rawLabel) then return "", "ffffff" end

        local key = col and col.key or ""
        if PVE_COMPACT_HEADER_BY_KEY[key] then
            local entry = PVE_COMPACT_HEADER_BY_KEY[key]
            return entry.text, entry.hex
        elseif key:match("^crest_") then
            local crestID = tonumber(key:match("^crest_(%d+)$"))
            if crestID and PVE_COMPACT_CREST_BY_ID[crestID] then
                local entry = PVE_COMPACT_CREST_BY_ID[crestID]
                return entry.text, entry.hex
            end
            return L.GetLocalizedText("PVE_CREST_GENERIC", "Crest"), "ffffff"
        end
        return "", "ffffff"
    end

    local colX = -COL_RIGHT_MARGIN
    for hci = #PVE_COLUMNS, 1, -1 do
        local col = PVE_COLUMNS[hci]
        colX = colX - col.width
        local colCenterX = colX + col.width * 0.5

        if col.icon or col.iconAtlas then
            local hitFrame = CreateFrame("Frame", nil, colHeaderRow)
            hitFrame:SetSize(COL_ICON_SIZE + 4, COL_ICON_SIZE + 4)
            hitFrame:SetPoint("RIGHT", colHeaderRow, "RIGHT", colCenterX + COL_ICON_SIZE * 0.5 + 2, 6)

            local iconTex = hitFrame:CreateTexture(nil, "ARTWORK")
            iconTex:SetSize(COL_ICON_SIZE, COL_ICON_SIZE)
            iconTex:SetPoint("CENTER")
            if col.iconAtlas and iconTex.SetAtlas then
                iconTex:SetTexture(nil)
                pcall(function()
                    iconTex:SetAtlas(col.iconAtlas)
                end)
                local okAtlas = iconTex.GetAtlas and iconTex:GetAtlas()
                if not okAtlas and col.icon then
                    iconTex:SetTexture(col.icon)
                    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
                end
            elseif col.icon then
                iconTex:SetTexture(col.icon)
                iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
            end

            local compactLabel, compactHex = BuildCompactHeaderLabel(col)
            if compactLabel ~= "" then
                L.PvEAcquireColHeaderLabel(colHeaderRow, col.key, hitFrame, compactLabel, compactHex, col.width)
            end

            if L.ShowTooltip then
                hitFrame:EnableMouse(true)
                local tooltipTitle = col.tooltipTitle
                if not tooltipTitle then
                    if col.crestCurrencyId then
                        local meta = L.GetPvECachedCurrencyDisplay(col.crestCurrencyId)
                        tooltipTitle = meta and meta.name
                    end
                    tooltipTitle = tooltipTitle or col.key or ""
                end
                hitFrame:SetScript("OnEnter", function(self)
                    L.ShowTooltip(self, {
                        type = "custom",
                        icon = col.iconAtlas or col.icon,
                        iconIsAtlas = col.iconAtlas ~= nil,
                        title = tooltipTitle,
                        lines = {},
                        anchor = "ANCHOR_BOTTOM"
                    })
                end)
                hitFrame:SetScript("OnLeave", function()
                    if L.HideTooltip then L.HideTooltip() end
                end)
                L.BindForwardScrollWheel(hitFrame)
            end
        end

        if hci > 1 then
            colX = colX - GapBetweenColumns(hci - 1)
        end
    end

    colHeaderRow:Show()

    -- Push scroll content below frozen column header overlay (ProfessionsUI pattern)
    yOffset = yOffset + colHeaderOverlayH

    local totalLHBox = { v = yOffset }
    -- Same vertical rhythm as Characters virtual rows: `betweenRows` (often 0) after each 46px row.
    local PVE_CHAR_ROW_GAP = L.GetLayout().betweenRows or 0
    local PVE_CHAR_ROW_HEADER_H = 46
    local scrollFrameRef = parent:GetParent()

    local sectionFilter = "all"
    if profile and profile.pveSectionFilter and type(profile.pveSectionFilter.sectionKey) == "string" then
        sectionFilter = profile.pveSectionFilter.sectionKey
    end
    local drawFav = (sectionFilter == "all") or (sectionFilter == "favorites")
    local drawReg = (sectionFilter == "all") or (sectionFilter == "regular")

    -- Characters tab parity: the online character lives inside Favorites / a custom header / Characters,
    -- never as a separate "pinned" row (which broke layout and skipped custom-group membership).
    local favoritesDisplay = {}
    for fi = 1, #favorites do
        favoritesDisplay[fi] = favorites[fi]
    end
    local regularDisplay = {}
    for ri = 1, #regularUngrouped do
        regularDisplay[ri] = regularUngrouped[ri]
    end
    local groupedDisplay = {}
    for gid, lst in pairs(groupedById) do
        local copy = {}
        for li = 1, #lst do
            copy[li] = lst[li]
        end
        groupedDisplay[tostring(gid)] = copy
    end
    if currentChar then
        local ck0 = GetRowCanonicalPvEKey(currentChar)
        if ck0 and L.ns.CharacterService then
            local inFav = L.ns.CharacterService.IsFavoriteCharacter and L.ns.CharacterService:IsFavoriteCharacter(self, ck0)
            local curGid = (not inFav) and L.ns.CharacterService.GetCharacterCustomSectionId
                and L.ns.CharacterService:GetCharacterCustomSectionId(self, ck0) or nil
            if inFav then
                favoritesDisplay[#favoritesDisplay + 1] = currentChar
                favoritesDisplay = sortCharacters(favoritesDisplay, "favorites")
            elseif curGid then
                local gkMerge = tostring(curGid)
                local bucket = groupedDisplay[gkMerge]
                if not bucket then
                    bucket = {}
                    groupedDisplay[gkMerge] = bucket
                end
                bucket[#bucket + 1] = currentChar
                local lk0 = (L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(curGid))
                    or ("group_" .. gkMerge)
                groupedDisplay[gkMerge] = sortCharacters(bucket, lk0)
            else
                regularDisplay[#regularDisplay + 1] = currentChar
                regularDisplay = sortCharacters(regularDisplay, "regular")
            end
        end
    end

    local paintOrder = {}
    if drawFav and #favoritesDisplay > 0 then
        for fi2 = 1, #favoritesDisplay do
            paintOrder[#paintOrder + 1] = { char = favoritesDisplay[fi2], secKey = "pve_fav" }
        end
    end
    for oci2 = 1, #customGroupsOrdered do
        local gMeta = customGroupsOrdered[oci2]
        local gid2 = gMeta.id
        local gList2 = groupedDisplay[tostring(gid2)] or {}
        local gListKey = (L.ns.CharacterService and L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(gid2)) or ("group_" .. tostring(gid2))
        local showGrp = (sectionFilter == "all") or (sectionFilter == gListKey)
        if showGrp and #gList2 > 0 then
            local sk = "pve_grp:" .. tostring(gid2)
            for gj2 = 1, #gList2 do
                paintOrder[#paintOrder + 1] = { char = gList2[gj2], secKey = sk }
            end
        end
    end
    for gidOr2, listOr2 in pairs(groupedDisplay) do
        local foundOr2 = false
        for ociOr2 = 1, #customGroupsOrdered do
            if tostring(customGroupsOrdered[ociOr2].id) == tostring(gidOr2) then
                foundOr2 = true
                break
            end
        end
        if not foundOr2 and listOr2 and #listOr2 > 0 then
            local gListKey2 = (L.ns.CharacterService and L.ns.CharacterService.GetCustomGroupListKey and L.ns.CharacterService:GetCustomGroupListKey(gidOr2)) or ("group_" .. tostring(gidOr2))
            local showOr2 = (sectionFilter == "all") or (sectionFilter == gListKey2)
            if showOr2 then
                local sko = "pve_grp:" .. tostring(gidOr2)
                for oj2 = 1, #listOr2 do
                    paintOrder[#paintOrder + 1] = { char = listOr2[oj2], secKey = sko }
                end
            end
        end
    end
    if drawReg and #regularDisplay > 0 then
        for ri2 = 1, #regularDisplay do
            paintOrder[#paintOrder + 1] = { char = regularDisplay[ri2], secKey = "pve_reg" }
        end
    end

    local secBodies = {}
    local layoutTailForShell = nil

    local function finalizePveSectionContent(secKey)
        if not secKey or not profile then return end
        local body = secBodies[secKey]
        if not body then return end
        local h = body._pveRunningH or 0.1
        body._wnAccordionFullH = h
        if not profile.ui then profile.ui = {} end
        local expanded = true
        if secKey == "pve_fav" then
            expanded = profile.ui.pveFavoritesExpanded ~= false
        elseif secKey == "pve_reg" then
            expanded = profile.ui.pveCharactersExpanded ~= false
        elseif PveGroupIdFromSectionSecKey(secKey) then
            local gidStr = tostring(PveGroupIdFromSectionSecKey(secKey))
            if not profile.characterGroupExpanded then profile.characterGroupExpanded = {} end
            local cg = profile.characterGroupExpanded
            local ev = cg[gidStr]
            if ev == nil then
                local asNum = tonumber(gidStr)
                if asNum then
                    ev = cg[asNum]
                end
            end
            expanded = ev ~= false
        end
        if expanded then
            body:Show()
            body:SetHeight(math.max(0.1, h))
        else
            body:Hide()
            body:SetHeight(0.1)
        end
        body._pvePaintedSectionH = math.max(0.1, h)
        layoutTailForShell = body
    end

    local prevDet = nil

    -- ===== CHARACTER ROWS (Favorites / custom / Characters sections only; online toon merged above) =====
    for i = 1, #paintOrder do
        local ent = paintOrder[i]
        local sk = ent.secKey
        local nextEnt = paintOrder[i + 1]
        local interRowGap = (nextEnt and nextEnt.secKey == sk) and PVE_CHAR_ROW_GAP or 0
        if i > 1 then
            local prevEnt = paintOrder[i - 1]
            if (sk or "") ~= (prevEnt.secKey or "") then
                finalizePveSectionContent(prevEnt.secKey)
                prevDet = nil
            end
        end

        -- All PvE character rows live under the accordion section body (never directly under scrollChild).
        local rowHost
        if sk == "pve_fav" then
            if not secBodies[sk] then
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = favoritesDisplay,
                    headerLabel = (L.ns.L and L.ns.L["HEADER_FAVORITES"]) or "Favorites",
                    sectionUiKey = "pveFavoritesExpanded",
                    defaultExpanded = true,
                    headerAtlas = "GM-icon-assistActive-hover",
                    visualOpts = { sectionPreset = "gold" },
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = L.SIDE_MARGIN,
                })
            end
            rowHost = secBodies[sk]
        elseif sk == "pve_reg" then
            if not secBodies[sk] then
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = regularDisplay,
                    headerLabel = (L.ns.L and L.ns.L["HEADER_CHARACTERS"]) or "Characters",
                    sectionUiKey = "pveCharactersExpanded",
                    defaultExpanded = true,
                    headerAtlas = "GM-icon-headCount",
                    visualOpts = nil,
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = L.SIDE_MARGIN,
                })
            end
            rowHost = secBodies[sk]
        elseif sk and PveGroupIdFromSectionSecKey(sk) then
            if not secBodies[sk] then
                local gid4 = tostring(PveGroupIdFromSectionSecKey(sk))
                local gName = gid4
                for gi3 = 1, #customGroupsOrdered do
                    if tostring(customGroupsOrdered[gi3].id) == gid4 then
                        gName = customGroupsOrdered[gi3].name or gid4
                        break
                    end
                end
                local goldStyle = L.ns.CharacterService and L.ns.CharacterService.IsProfileCustomSectionHighlighted
                    and L.ns.CharacterService:IsProfileCustomSectionHighlighted(profile, gid4)
                secBodies[sk] = L.PvEUI_CreatePvETabSectionShell(self, parent, profile, {
                    chars = groupedDisplay[tostring(gid4)] or {},
                    headerLabel = gName,
                    sectionUiKey = nil,
                    defaultExpanded = true,
                    headerAtlas = goldStyle and "GM-icon-assistActive-hover" or "GM-icon-headCount",
                    visualOpts = {
                        sectionPreset = goldStyle and "gold" or "accent",
                        useCharacterGroupExpand = true,
                        groupId = gid4,
                    },
                    layoutTailFrame = layoutTailForShell,
                    totalLH = totalLHBox,
                    scrollFrameRef = scrollFrameRef,
                    yTop = totalLHBox.v,
                    sideMargin = L.SIDE_MARGIN,
                })
            end
            rowHost = secBodies[sk]
        end
        assert(rowHost, "PvE row missing section body (sk=" .. tostring(sk) .. ")")

        local char = ent.char
        local classColor = RAID_CLASS_COLORS[char.classFile] or {r = 1, g = 1, b = 1}
        -- CRITICAL: Match DB keys (currency + PvE cache) — prefer characters table index via _key for canonical resolution.
        local charKey = GetRowCanonicalPvEKey(char)
        local isFavorite = L.ns.CharacterService and L.ns.CharacterService:IsFavoriteCharacter(self, charKey)
        
        -- Get PvE data from PvECacheService
        local pveData = self:GetPvEData(charKey) or {}
        
        -- Build legacy-compatible structure for rendering (backward compatibility)
        local pve = {
            keystone = pveData.keystone,
            vaultActivities = pveData.vaultActivities,
            hasUnclaimedRewards = pveData.vaultRewards and pveData.vaultRewards.hasAvailableRewards,
            raidLockouts = pveData.raidLockouts,
            worldBosses = pveData.worldBosses,
            mythicPlus = pveData.mythicPlus,
            delves = pveData.delves,
        }
        
        -- Only the current (online) character starts expanded; all others collapsed.
        local charExpandKey = "pve-char-" .. charKey
        local isCurrentChar = (charKey == currentPlayerKey)
        local hasVaultReward = pve.hasUnclaimedRewards or false
        
        local charExpanded = L.IsExpanded(charExpandKey, isCurrentChar)

        local charDetailContent
        local buildPvEDetailIfNeeded

        local accVisual = L.BuildAccordionVisualOpts({
                bodyGetter = function() return charDetailContent end,
                -- Runs before SharedWidgets reads _wnAccordionFullH for AnimateAccordion target (expand path).
                persistFn = function(exp)
                    L.expandedStates[charExpandKey] = exp
                    if exp and charDetailContent and buildPvEDetailIfNeeded then
                        buildPvEDetailIfNeeded()
                    end
                end,
                -- Do not drive `scrollParent:SetHeight` from tweens (that inflated the whole tab).
                -- Do live-adjust section body + scroll child while this row's detail height tweens so
                -- siblings reflow and the scroll range matches content (PopulateContent only runs on full refresh).
                onUpdate = function(drawH)
                    if scrollFrameRef and scrollFrameRef.GetVerticalScrollRange and scrollFrameRef.GetVerticalScroll and scrollFrameRef.SetVerticalScroll then
                        local maxV = scrollFrameRef:GetVerticalScrollRange() or 0
                        local cur = scrollFrameRef:GetVerticalScroll() or 0
                        scrollFrameRef:SetVerticalScroll(math.min(math.max(cur, 0), maxV))
                    end
                    local dh = tonumber(drawH) or 0.1
                    local baseD = charDetailContent and charDetailContent._pvePaintedDetailH
                    local baseS = rowHost and rowHost._pvePaintedSectionH
                    local sc = scrollFrameRef and scrollFrameRef.GetScrollChild and scrollFrameRef:GetScrollChild()
                    if charDetailContent and rowHost and baseD and baseS and sc and sc._pvePaintedCoreH then
                        local secH = baseS + dh - baseD
                        rowHost._wnAccordionFullH = secH
                        rowHost:SetHeight(math.max(0.1, secH))
                        local pad = 8
                        local viewportH = (scrollFrameRef.GetHeight and scrollFrameRef:GetHeight()) or 0
                        local contentBottom = sc._pvePaintedCoreH + dh - baseD + pad
                        sc:SetHeight(math.max(viewportH, contentBottom))
                    end
                end,
                onComplete = function()
                    if scrollFrameRef and scrollFrameRef.GetVerticalScrollRange and scrollFrameRef.GetVerticalScroll and scrollFrameRef.SetVerticalScroll then
                        local maxV = scrollFrameRef:GetVerticalScrollRange() or 0
                        local cur = scrollFrameRef:GetVerticalScroll() or 0
                        scrollFrameRef:SetVerticalScroll(math.min(math.max(cur, 0), maxV))
                    end
                    if charDetailContent then
                        charDetailContent._pvePaintedDetailH = math.max(0.1, charDetailContent:GetHeight() or 0.1)
                    end
                    if rowHost then
                        rowHost._pvePaintedSectionH = math.max(0.1, rowHost:GetHeight() or rowHost._wnAccordionFullH or 0.1)
                    end
                    local sc = scrollFrameRef and scrollFrameRef.GetScrollChild and scrollFrameRef:GetScrollChild()
                    if sc and scrollFrameRef and scrollFrameRef.GetHeight then
                        local pad = 8
                        local viewportH = scrollFrameRef:GetHeight() or 0
                        sc._pvePaintedCoreH = math.max(1, (sc:GetHeight() or 1) - pad)
                    end
                end,
            }) or {}
        accVisual.suppressSectionChrome = true
        accVisual.sectionHeaderHeight = 46
        -- Expand: run onToggle after height tween so row height is not snapped to full before AnimateAccordion
        -- resets to startH (avoids sibling rows jumping one frame then easing).
        accVisual.deferOnToggleUntilComplete = true

        local charHeader, expandIconTex = L.CreateCollapsibleHeader(
            rowHost,
            "",
            charExpandKey,
            charExpanded,
            function(isExpanded)
                if isExpanded then
                    if charDetailContent then
                        charDetailContent:Show()
                        charDetailContent:SetHeight(math.max(0.1, charDetailContent._wnAccordionFullH or 0.1))
                    end
                elseif charDetailContent then
                    charDetailContent:Hide()
                    charDetailContent:SetHeight(0.1)
                end
            end,
            nil, nil, nil, true,
            accVisual
        )
        if prevDet == nil then
            charHeader:SetPoint("TOPLEFT", rowHost, "TOPLEFT", 10, 0)
            charHeader:SetPoint("TOPRIGHT", rowHost, "TOPRIGHT", -10, 0)
        else
            charHeader:SetPoint("TOPLEFT", prevDet, "BOTTOMLEFT", 0, -interRowGap)
            charHeader:SetPoint("TOPRIGHT", prevDet, "BOTTOMRIGHT", 0, -interRowGap)
        end
        if charHeader.SetClippingChildren then
            charHeader:SetClippingChildren(true)
        end

        if L.PvEUI_ApplyCharacterListRowChrome then
            L.PvEUI_ApplyCharacterListRowChrome(self, charHeader, char, {
                rowIndex = i,
                charKey = charKey,
                isFavorite = isFavorite,
                isCurrentChar = isCurrentChar,
                expandIconFrame = expandIconTex,
                nameWidth = nameWidth,
            })
        end

        totalLHBox.v = totalLHBox.v + PVE_CHAR_ROW_HEADER_H

        -- ===== INLINE COLUMN DATA (right-aligned, matching column headers) =====
        do
            local shardData = (PVE_SHARDS_ID and L.WarbandNexus:GetCurrencyData(PVE_SHARDS_ID, charKey)) or nil
            local shardQty = shardData and shardData.quantity or 0
            local shardMax = shardData and shardData.maxQuantity or 0
            local shardTE = shardData and shardData.totalEarned
            local shardSM = shardData and shardData.seasonMax

            local keyData = (PVE_RESTORED_KEY_ID and L.WarbandNexus:GetCurrencyData(PVE_RESTORED_KEY_ID, charKey)) or nil
            local keyQty = keyData and keyData.quantity or 0

            -- Vault summary from activities
            local vaultActs = pve.vaultActivities or {}

            -- Claimable Great Vault loot (not the same as "threshold progress completed" ticks below).
            -- Prefer live API for current character, but never let transient API timing
            -- wipe a known cached "unclaimed rewards" state.
            local vaultLootClaimable = (pve.hasUnclaimedRewards == true)
            if isCurrentChar and L.WarbandNexus.HasUnclaimedVaultRewards then
                local ok, v = pcall(L.WarbandNexus.HasUnclaimedVaultRewards, L.WarbandNexus)
                if ok then
                    vaultLootClaimable = (v == true) or vaultLootClaimable
                end
            end

            local function FormatVaultTrackSlots(activityList, slotCount, typeName)
                return L.PvE_FormatVaultTrackColumn(activityList, slotCount, typeName, vaultLootClaimable, 12)
            end

            --- Format currency for inline row: always show current quantity.
            local function FormatCurrencyStatus(qty)
                qty = qty or 0
                if qty > 0 then
                    return L.FormatNumber(qty)
                end
                return "\226\128\148"
            end

            local function BuildCurrencyTooltip(currencyID, currencyName, qty, maxQty, totalEarned, seasonMax)
                local lines = {}
                local currentLabel = (L.ns.L and L.ns.L["CURRENT_ENTRIES_LABEL"]) or "Current:"
                local seasonLabel = (L.ns.L and L.ns.L["SEASON"]) or "Season"
                local weeklyLabel = (L.ns.L and L.ns.L["CURRENCY_LABEL_WEEKLY"]) or "Weekly"
                local remainingSuffix = (L.ns.L and L.ns.L["VAULT_REMAINING_SUFFIX"]) or "remaining"
                local cappedText = CAPPED or "Capped"
                qty = qty or 0
                maxQty = maxQty or 0
                local sm = tonumber(seasonMax) or 0
                local teN = tonumber(totalEarned)

                if L.ns.Utilities and L.ns.Utilities.IsCofferKeyShardCurrency and L.ns.Utilities:IsCofferKeyShardCurrency(currencyID, currencyName) then
                    local wCap = tonumber(maxQty) or 0
                    local teForWeek = (teN ~= nil) and teN or 0
                    table.insert(lines, { text = string.format("%s %s", currentLabel, L.FormatNumber(qty)), color = {1, 1, 1} })
                    if wCap > 0 then
                        local remWeek = math.max(wCap - teForWeek, 0)
                        table.insert(lines, { text = string.format("%s: %s / %s", weeklyLabel, L.FormatNumber(teForWeek), L.FormatNumber(wCap)), color = {1, 1, 1} })
                        if remWeek > 0 then
                            table.insert(lines, { text = string.format("%s %s", L.FormatNumber(remWeek), remainingSuffix), color = {0.5, 1, 0.5} })
                        else
                            table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                        end
                    end
                    return lines
                end

                local hasSeasonProgress = sm > 0
                if hasSeasonProgress then
                    local teForSeason = (teN ~= nil) and teN or 0
                    local remSeason = math.max(sm - teForSeason, 0)
                    table.insert(lines, { text = string.format("%s %s", currentLabel, L.FormatNumber(qty)), color = {1, 1, 1} })
                    table.insert(lines, { text = string.format("%s: %s / %s", seasonLabel, L.FormatNumber(teForSeason), L.FormatNumber(sm)), color = {1, 1, 1} })
                    if remSeason > 0 then
                        table.insert(lines, { text = string.format("%s %s", L.FormatNumber(remSeason), remainingSuffix), color = {0.5, 1, 0.5} })
                    else
                        table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                    end
                    -- Crest sources: when the currency is a Dawncrest, append "Sources" block (Midnight S1 data).
                    local Constants = L.ns.Constants
                    local sources = Constants and Constants.DAWNCREST_UI and Constants.DAWNCREST_UI.SOURCES
                        and Constants.DAWNCREST_UI.SOURCES[currencyID] or nil
                    if sources and #sources > 0 then
                        table.insert(lines, { text = " ", color = {1, 1, 1} })
                        table.insert(lines, {
                            text = (L.ns.L and L.ns.L["CREST_SOURCES_HEADER"]) or "Sources:",
                            color = {1, 0.82, 0},
                        })
                        for si = 1, #sources do
                            table.insert(lines, { text = "\194\183 " .. sources[si], color = {0.82, 0.86, 0.95} })
                        end
                        if remSeason > 0 then
                            table.insert(lines, {
                                text = string.format("%s %s",
                                    L.FormatNumber(remSeason),
                                    (L.ns.L and L.ns.L["CREST_TO_CAP_SUFFIX"]) or "to season cap"),
                                color = {0.55, 0.85, 0.55},
                            })
                        end
                    end
                    return lines
                end

                local cap = maxQty
                if cap and cap > 0 then
                    local rem = math.max(cap - qty, 0)
                    table.insert(lines, { text = string.format("%s / %s", L.FormatNumber(qty), L.FormatNumber(cap)), color = {1, 1, 1} })
                    if rem > 0 then
                        table.insert(lines, { text = string.format("%s %s", L.FormatNumber(rem), remainingSuffix), color = {0.5, 1, 0.5} })
                    else
                        table.insert(lines, { text = cappedText, color = {1, 0.35, 0.35} })
                    end
                    return lines
                end

                table.insert(lines, { text = L.FormatNumber(qty), color = {1, 1, 1} })
                return lines
            end

            -- Render inline values (right to left, matching column header positions)
            local inlineX = -COL_RIGHT_MARGIN
            local colValuesByKey = {}

            -- |cff888888 parity with FormatHelpers CC_MUTED / Utilities (placeholder & EM dash)
            local MUTED_RGB = 136 / 255
            local DIM_COLOR = { MUTED_RGB, MUTED_RGB, MUTED_RGB }
            local NORMAL_COLOR = {1, 1, 1}
            local CAP_OPEN_COLOR = {0.5, 1, 0.5}
            local CAPPED_COLOR = {1, 0.35, 0.35}
            local EM_DASH = "\226\128\148"
            local EM_DASH_RICH = "|cff888888" .. EM_DASH .. "|r"

            local function GetCapStateColor(currencyID, currencyName, qty, maxQty, totalEarned, seasonMax)
                if L.ns.Utilities and L.ns.Utilities.IsCofferKeyShardCurrency and L.ns.Utilities:IsCofferKeyShardCurrency(currencyID, currencyName) then
                    local cap = tonumber(maxQty) or 0
                    local teN = tonumber(totalEarned)
                    if cap > 0 and teN ~= nil then
                        return (teN >= cap) and CAPPED_COLOR or CAP_OPEN_COLOR
                    end
                    return NORMAL_COLOR
                end
                local sm = tonumber(seasonMax) or 0
                if sm > 0 then
                    local teN = tonumber(totalEarned)
                    if teN == nil then
                        return NORMAL_COLOR
                    end
                    local rem = math.max(sm - teN, 0)
                    return (rem > 0) and CAP_OPEN_COLOR or CAPPED_COLOR
                end
                if maxQty and maxQty > 0 then
                    local rem = math.max(maxQty - (qty or 0), 0)
                    return (rem > 0) and CAP_OPEN_COLOR or CAPPED_COLOR
                end
                return NORMAL_COLOR
            end

            local FormatSeasonLine = L.ns.UI_FormatSeasonProgressCurrencyLine
            for i = 1, #PVE_DAWNCRESTS do
                local cd = L.WarbandNexus:GetCurrencyData(PVE_DAWNCRESTS[i].id, charKey)
                local q = cd and cd.quantity or 0
                local m = cd and cd.maxQuantity or 0
                local te = cd and cd.totalEarned
                local sm = cd and cd.seasonMax
                local txt = FormatSeasonLine and FormatSeasonLine(cd) or FormatCurrencyStatus(q)
                local tipTitle = PVE_DAWNCRESTS[i] and PVE_DAWNCRESTS[i].name or ((L.ns.L and L.ns.L["TAB_CURRENCY"]) or "Currency")
                colValuesByKey["crest_" .. tostring(PVE_DAWNCRESTS[i].id)] = {
                    text = txt,
                    richText = FormatSeasonLine ~= nil,
                    color = (not FormatSeasonLine) and ((txt == EM_DASH) and DIM_COLOR or GetCapStateColor(PVE_DAWNCRESTS[i].id, cd and cd.name, q, m, te, sm)) or nil,
                    tooltip = BuildCurrencyTooltip(PVE_DAWNCRESTS[i].id, cd and cd.name, q, m, te, sm),
                    tooltipTitle = tipTitle,
                    tooltipIcon = cd and cd.icon,
                    currencyID = PVE_DAWNCRESTS[i].id,
                    seasonProgressData = cd,  -- enables shift-aware live binding in render loop
                }
            end

            local shardTxt = FormatSeasonLine and FormatSeasonLine(shardData) or FormatCurrencyStatus(shardQty)
            colValuesByKey.coffer_shards = {
                text = shardTxt,
                richText = FormatSeasonLine ~= nil,
                color = (not FormatSeasonLine) and ((shardTxt == EM_DASH) and DIM_COLOR or GetCapStateColor(PVE_SHARDS_ID, shardData and shardData.name, shardQty, shardMax, shardTE, shardSM)) or nil,
                tooltip = BuildCurrencyTooltip(PVE_SHARDS_ID, shardData and shardData.name, shardQty, shardMax, shardTE, shardSM),
                tooltipTitle = (L.ns.L and L.ns.L["PVE_COL_COFFER_SHARDS"]) or "Coffer Shards",
                tooltipIcon = shardData and shardData.icon,
                currencyID = PVE_SHARDS_ID,
                seasonProgressData = shardData,
            }
            colValuesByKey.restored_key = { text = keyQty > 0 and L.FormatNumber(keyQty) or EM_DASH, color = keyQty > 0 and NORMAL_COLOR or DIM_COLOR }
            local raidTotal = vaultActs.raids and #vaultActs.raids or 3
            local dungeonTotal = vaultActs.mythicPlus and #vaultActs.mythicPlus or 3
            local worldTotal = vaultActs.world and #vaultActs.world or 3
            -- Per-slot tooltip helper: shows achieved difficulty per slot (Heroic/Mythic raid, +N keys, Tier N world).
            -- Activity `level` field: raid = difficulty ID (use GetDifficultyInfo); M+ = key level int; World = tier int.
            local function FormatSlotDifficultyLabel(activity, category)
                if not activity then return nil end
                local lvl = tonumber(activity.level) or 0
                if lvl <= 0 then return nil end
                if category == "Raid" then
                    if GetDifficultyInfo then
                        local diffName = GetDifficultyInfo(lvl)
                        if diffName and diffName ~= "" then return diffName end
                    end
                    return "Difficulty " .. lvl
                elseif category == "M+" then
                    return "+" .. lvl
                else
                    return "Tier " .. lvl
                end
            end

            local function BuildVaultSlotTooltipLines(activities, category, totalSlots)
                local lines = {}
                local catTitle = (category == "Raid") and ((L.ns.L and L.ns.L["PVE_HEADER_RAIDS"]) or "Raids")
                    or (category == "M+") and ((L.ns.L and L.ns.L["PVE_HEADER_DUNGEONS"]) or "Dungeons")
                    or ((L.ns.L and L.ns.L["VAULT_WORLD"]) or "World")
                table.insert(lines, { text = catTitle, color = {1, 0.82, 0} })
                for i = 1, (totalSlots or 3) do
                    local a = activities and activities[i]
                    local prog   = a and (tonumber(a.progress) or 0) or 0
                    local thresh = a and (tonumber(a.threshold) or 0) or 0
                    local complete = thresh > 0 and prog >= thresh
                    local diffLabel = complete and FormatSlotDifficultyLabel(a, category) or nil
                    local rewardIlvl = a and (tonumber(a.rewardItemLevel) or 0) or 0
                    if complete then
                        local rhs = diffLabel or ""
                        if rewardIlvl > 0 then
                            rhs = (rhs ~= "" and (rhs .. "  ") or "")
                                .. ((L.ns.L and L.ns.L["ILVL_FORMAT"] and string.format(L.ns.L["ILVL_FORMAT"], rewardIlvl)) or ("iLvl " .. rewardIlvl))
                        end
                        table.insert(lines, {
                            text = L.GetLocalizedText("PVE_VAULT_SLOT_COMPLETE_FORMAT", "Slot %d: |cff80ff80\226\156\147|r %s"):format(i, rhs ~= "" and rhs or L.GetLocalizedText("PVE_VAULT_SLOT_UNLOCKED", "Unlocked")),
                            color = {0.85, 0.9, 0.95},
                        })
                    elseif thresh > 0 then
                        table.insert(lines, {
                            text = L.GetLocalizedText("PVE_VAULT_SLOT_PROGRESS_FORMAT", "Slot %d: |cffff8888%d/%d|r"):format(i, prog, thresh),
                            color = {0.65, 0.65, 0.65},
                        })
                    else
                        table.insert(lines, { text = L.GetLocalizedText("PVE_VAULT_SLOT_EMPTY_FORMAT", "Slot %d: \226\128\148"):format(i), color = { MUTED_RGB, MUTED_RGB, MUTED_RGB } })
                    end
                end
                return lines
            end

            colValuesByKey.slot1 = {
                text = FormatVaultTrackSlots(vaultActs.raids, raidTotal, "Raid"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.raids, "Raid", raidTotal),
                tooltipTitle = (L.ns.L and L.ns.L["PVE_HEADER_RAIDS"]) or "Raids",
            }
            colValuesByKey.slot2 = {
                text = FormatVaultTrackSlots(vaultActs.mythicPlus, dungeonTotal, "M+"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.mythicPlus, "M+", dungeonTotal),
                tooltipTitle = (L.ns.L and L.ns.L["PVE_HEADER_DUNGEONS"]) or "Dungeons",
            }
            colValuesByKey.slot3 = {
                text = FormatVaultTrackSlots(vaultActs.world, worldTotal, "World"),
                color = {1, 1, 1},
                tooltip = BuildVaultSlotTooltipLines(vaultActs.world, "World", worldTotal),
                tooltipTitle = (L.ns.L and L.ns.L["VAULT_WORLD"]) or "World",
            }
            -- Trovehunter's Bounty / bountiful weeklies: per-character snapshot from PvE cache (not live API on every row).
            local delveChar = (pve.delves and pve.delves.character) or {}
            local bountifulDone = delveChar.bountifulComplete
            if bountifulDone == nil and isCurrentChar then
                bountifulDone = L.WarbandNexus.IsBountifulDelveWeeklyDone and L.WarbandNexus:IsBountifulDelveWeeklyDone() or false
            end
            local bountifulTitle = (L.ns.L and L.ns.L["BOUNTIFUL_DELVE"]) or "Trovehunter's Bounty"
            local bountifulUnknown = (bountifulDone == nil)
            local bountifulTip = {
                {
                    text = bountifulUnknown and ((L.ns.L and L.ns.L["PVE_BOUNTY_NEED_LOGIN"]) or "No saved status for this character. Log in to refresh.")
                        or (bountifulDone and ((L.ns.L and L.ns.L["VAULT_COMPLETED_ACTIVITIES"]) or "Completed")
                            or ((L.ns.L and L.ns.L["ACHIEVEMENT_NOT_COMPLETED"]) or "Not Completed")),
                    color = {1, 1, 1},
                },
            }
            colValuesByKey.bountiful = {
                text = bountifulUnknown and EM_DASH or (bountifulDone and L.VAULT_SLOT_CHECK or L.VAULT_SLOT_CROSS),
                color = bountifulUnknown and DIM_COLOR or {1, 1, 1},
                tooltip = bountifulTip,
                tooltipTitle = bountifulTitle,
                tooltipIcon = L.GetTrovehunterBountyColumnIcon(),
            }
            local voidcoreData = L.WarbandNexus:GetCurrencyData(L.PVE_VOIDCORE_ID, charKey)
            -- Voidcore: cell shows owned amount only (green if under cap, red if capped); cap/progress in tooltip.
            local vqty = (voidcoreData and tonumber(voidcoreData.quantity)) or 0
            local vcap = (voidcoreData and (tonumber(voidcoreData.seasonMax) or tonumber(voidcoreData.maxQuantity))) or 0
            local voidcoreTxt
            if vcap > 0 then
                local capped = vqty >= vcap
                local col = capped and "|cffff5959" or "|cff80ff80"
                voidcoreTxt = col .. L.FormatNumber(vqty) .. "|r"
            elseif vqty > 0 then
                voidcoreTxt = "|cffffffff" .. L.FormatNumber(vqty) .. "|r"
            else
                voidcoreTxt = EM_DASH_RICH
            end
            colValuesByKey.voidcore = {
                text = voidcoreTxt,
                richText = true,
                tooltip = BuildCurrencyTooltip(L.PVE_VOIDCORE_ID, voidcoreData and voidcoreData.name, vqty, voidcoreData and voidcoreData.maxQuantity or 0, voidcoreData and voidcoreData.totalEarned, voidcoreData and voidcoreData.seasonMax),
                tooltipTitle = L.GetLocalizedText("PVE_COL_NEBULOUS_VOIDCORE", "Nebulous Voidcore"),
                tooltipIcon = voidcoreData and voidcoreData.icon,
                currencyID = L.PVE_VOIDCORE_ID,
                -- seasonProgressData intentionally omitted: voidcore must NOT use shift-aware binder.
            }
            -- Vault Status (matches Vault Tracker quick window readout):
            --   Ready -> "Ready to Claim" (green)
            --   ReadySlots > 0 -> "<n> Slots Earned" (cyan)
            --   Pending only -> "Pending..." (gold)
            --   No progress -> em-dash dimmed
            do
                local vs = L.WarbandNexus.GetVaultStatusForChar and L.WarbandNexus:GetVaultStatusForChar(charKey)
                local statusTxt
                if not vs then
                    statusTxt = EM_DASH_RICH
                elseif vs.isReady then
                    statusTxt = "|cff44ff44" .. ((L.ns.L and L.ns.L["VAULT_READY_TO_CLAIM"]) or "Ready to Claim") .. "|r"
                elseif (vs.readySlots or 0) > 0 then
                    statusTxt = "|cff66ddff" .. L.GetLocalizedText("VAULT_SLOTS_SHORT_FORMAT", "%d Slots"):format(tonumber(vs.readySlots) or 0) .. "|r"
                else
                    statusTxt = "|cffffd700" .. ((L.ns.L and L.ns.L["VAULT_PENDING"]) or "Pending\226\128\166") .. "|r"
                end
                colValuesByKey.vault_status = {
                    text = statusTxt,
                    richText = true,
                }
            end

            local manafluxData = L.WarbandNexus:GetCurrencyData(L.PVE_MANAFLUX_ID, charKey)
            local manafluxQty = (manafluxData and manafluxData.quantity) or 0
            colValuesByKey.manaflux = {
                text = manafluxQty > 0 and L.FormatNumber(manafluxQty) or EM_DASH,
                color = manafluxQty > 0 and NORMAL_COLOR or DIM_COLOR,
                tooltip = BuildCurrencyTooltip(L.PVE_MANAFLUX_ID, manafluxData and manafluxData.name, manafluxQty, manafluxData and manafluxData.maxQuantity or 0, manafluxData and manafluxData.totalEarned, manafluxData and manafluxData.seasonMax),
                tooltipTitle = L.GetLocalizedText("PVE_COL_DAWNLIGHT_MANAFLUX", "Dawnlight Manaflux"),
                tooltipIcon = manafluxData and manafluxData.icon,
                currencyID = L.PVE_MANAFLUX_ID,
            }

            local UnbindSeason = L.ns.UI_UnbindSeasonProgressAmount
            for ci = #PVE_COLUMNS, 1, -1 do
                local col = PVE_COLUMNS[ci]
                local val = colValuesByKey[col.key]
                if val then
                    local cw = col.width
                    inlineX = inlineX - cw
                    local cell = L.PvEAcquireInlineCell(charHeader, charKey, col.key)
                    local colText = cell.fs
                    colText:SetPoint("CENTER", charHeader, "RIGHT", inlineX + cw * 0.5, 0)
                    colText:SetWidth(cw)
                    colText:SetJustifyH("CENTER")
                    if colText.SetJustifyV then colText:SetJustifyV("MIDDLE") end
                    colText:SetWordWrap(false)
                    if val.seasonProgressData and L.ns.UI_BindSeasonProgressAmount then
                        L.ns.UI_BindSeasonProgressAmount(colText, val.seasonProgressData)
                        colText:SetTextColor(1, 1, 1)
                    else
                        if UnbindSeason then UnbindSeason(colText) end
                        colText:SetText(val.text)
                        if not val.richText and val.color then
                            colText:SetTextColor(val.color[1], val.color[2], val.color[3])
                        elseif val.richText then
                            colText:SetTextColor(1, 1, 1)
                        end
                    end
                    if val.tooltip and L.ShowTooltip then
                        local hit = cell.hit
                        if not hit then
                            hit = CreateFrame("Frame", nil, charHeader)
                            cell.hit = hit
                            hit:EnableMouse(true)
                            L.BindForwardScrollWheel(hit)
                        end
                        hit:SetParent(charHeader)
                        hit:SetPoint("CENTER", charHeader, "RIGHT", inlineX + cw * 0.5, 0)
                        hit:SetSize(cw, math.max(L.ROW_HEIGHT or 26, charHeader:GetHeight() or 46))
                        hit:Show()
                        hit:SetScript("OnEnter", function(self)
                            if val.currencyID then
                                L.ShowTooltip(self, {
                                    type = "currency",
                                    currencyID = val.currencyID,
                                    charKey = charKey,
                                    anchor = "ANCHOR_TOP",
                                })
                            else
                                L.ShowTooltip(self, {
                                    type = "custom",
                                    icon = val.tooltipIcon or "Interface\\Icons\\INV_Misc_QuestionMark",
                                    title = val.tooltipTitle or ((L.ns.L and L.ns.L["TAB_CURRENCY"]) or "Currency"),
                                    lines = val.tooltip,
                                    anchor = "ANCHOR_TOP",
                                })
                            end
                        end)
                        hit:SetScript("OnLeave", function()
                            if L.HideTooltip then L.HideTooltip() end
                        end)
                        hit:SetScript("OnMouseUp", function(_, button)
                            if button == "LeftButton" and charHeader then
                                charHeader:Click()
                            end
                        end)
                    elseif cell.hit then
                        cell.hit:Hide()
                        cell.hit:SetScript("OnEnter", nil)
                        cell.hit:SetScript("OnLeave", nil)
                        cell.hit:SetScript("OnMouseUp", nil)
                    end
                    if ci > 1 then
                        inlineX = inlineX - GapBetweenColumns(ci - 1)
                    end
                end
            end
        end
        
        charHeader:SetAlpha(1)

        -- Parent must be rowHost (section body or scroll child for pinned rows), not the root scroll
        -- child alone: detail was a sibling of section bodies, so reserved _pveRunningH / layoutTail did not
        -- match painted geometry and following section headers overlapped expanded rows (Characters tab
        -- keeps row bodies under AcquireSectionContentFrame / section content).
        charDetailContent = L.ns.UI.Factory:CreateContainer(rowHost)
        charDetailContent:SetPoint("TOPLEFT", charHeader, "BOTTOMLEFT", 0, 0)
        charDetailContent:SetPoint("TOPRIGHT", charHeader, "BOTTOMRIGHT", 0, 0)
        if charDetailContent.SetClipsChildren then
            charDetailContent:SetClipsChildren(true)
        end

        buildPvEDetailIfNeeded = function()
            L.PvEUI_PopulateExpandedCharacterDetail(self, parent, charDetailContent, charExpandKey, charKey, pve, pveData, isCurrentChar)
        end


        if charExpanded then
            buildPvEDetailIfNeeded()
            local dh = charDetailContent._wnAccordionFullH or 200
            charDetailContent:SetHeight(dh)
            charDetailContent:Show()
            charDetailContent._pvePaintedDetailH = dh
            totalLHBox.v = totalLHBox.v + dh + interRowGap
        else
            charDetailContent:SetHeight(0.1)
            charDetailContent:Hide()
            charDetailContent._pvePaintedDetailH = 0.1
            totalLHBox.v = totalLHBox.v + 0.1 + interRowGap
        end

        local bod = secBodies[sk]
        if bod then
            local inc
            if charExpanded then
                -- interRowGap: same-section next row only (matches SetPoint gap); not afterElement (that duplicated the anchor gap).
                inc = PVE_CHAR_ROW_HEADER_H + (charDetailContent._wnAccordionFullH or 200) + interRowGap
            else
                inc = PVE_CHAR_ROW_HEADER_H + 0.1 + interRowGap
            end
            bod._pveRunningH = (bod._pveRunningH or 0) + inc
            bod._pvePaintedSectionH = bod._pveRunningH
        end

        prevDet = charDetailContent

    -- Character sections flow directly one after another (like Characters tab)
    end

    if #paintOrder > 0 then
        finalizePveSectionContent(paintOrder[#paintOrder].secKey)
    end

    local coreH = totalLHBox.v + 12
    parent._pvePaintedCoreH = coreH
    return coreH
end

--- Header chest icon: all tracked characters' vault column summaries (Raid / M+ / World), width-aware row cap.

function WarbandNexus:DrawPvEProgress(parent)
    return PvEUI_DrawPvEProgressBody(self, parent, ns.PvEDrawLibs)
end

function WarbandNexus:ShowPvEVaultAllCharactersTooltip(anchorFrame)
    if not anchorFrame or not ShowTooltip then return end

    local snap = self._pveVaultTooltipCharsSnapshot
    local lines = {}

    local title = (ns.L and ns.L["VAULT_SUMMARY_ALL_TITLE"]) or "Great Vault — all characters"
    table.insert(lines, {
        text = (ns.L and ns.L["VAULT_SUMMARY_ALL_SUB"]) or "Raid · Mythic+ · World columns match the PvE tab.",
        color = { 0.72, 0.72, 0.76 },
    })
    table.insert(lines, { type = "spacer", height = 6 })

    local currentKey = ns.Utilities:GetCharacterKey()
    if ns.Utilities.GetCanonicalCharacterKey then
        currentKey = ns.Utilities:GetCanonicalCharacterKey(currentKey) or currentKey
    end

    local sh = GetScreenHeight() or 1080
    local sw = GetScreenWidth() or 1920
    local maxRows = math.max(24, math.min(100, math.floor((sh * 0.52) / 15)))
    local maxW = math.floor(sw * 0.42)
    if maxW < 360 then maxW = 360 end
    if maxW > 620 then maxW = 620 end

    if not snap or #snap == 0 then
        table.insert(lines, {
            text = (ns.L and ns.L["VAULT_SUMMARY_NO_CHARS"]) or "No tracked characters.",
            color = { 0.55, 0.55, 0.58 },
        })
    else
        local rows = {}
        local listed = 0
        local idx = 1
        while idx <= #snap and listed < maxRows do
            local char = snap[idx]
            idx = idx + 1
            local charKey = PvE_GetCanonicalKeyForChar(char)
            if charKey then
                listed = listed + 1
                local pveData = self:GetPvEData(charKey) or {}
                local vaultActs = pveData.vaultActivities or {}
                local raidT = vaultActs.raids and #vaultActs.raids or 3
                local dT = vaultActs.mythicPlus and #vaultActs.mythicPlus or 3
                local wT = vaultActs.world and #vaultActs.world or 3

                local claim = pveData.vaultRewards and pveData.vaultRewards.hasAvailableRewards == true
                if (not claim) and charKey == currentKey and self.HasUnclaimedVaultRewards then
                    local ok, v = pcall(self.HasUnclaimedVaultRewards, self)
                    claim = ok and v == true
                end

                local r = PvE_FormatVaultTrackColumn(vaultActs.raids, raidT, "Raid", claim, 12)
                local dcol = PvE_FormatVaultTrackColumn(vaultActs.mythicPlus, dT, "M+", claim, 12)
                local wcol = PvE_FormatVaultTrackColumn(vaultActs.world, wT, "World", claim, 12)

                local classColor = RAID_CLASS_COLORS[char.classFile] or { r = 1, g = 1, b = 1 }
                local nameStr = string.format(
                    "|cff%02x%02x%02x%s|r",
                    classColor.r * 255,
                    classColor.g * 255,
                    classColor.b * 255,
                    char.name or "?"
                )
                local realmDisp = ns.Utilities and ns.Utilities:FormatRealmName(char.realm) or char.realm or ""
                if realmDisp ~= "" and #realmDisp > 14 then
                    realmDisp = realmDisp:sub(1, 11) .. "…"
                end
                local realmCol = ""
                if realmDisp ~= "" then
                    realmCol = "|cffaaaaaa" .. realmDisp .. "|r"
                end

                rows[#rows + 1] = {
                    nameStr = nameStr,
                    realmStr = realmCol,
                    r = r,
                    d = dcol,
                    w = wcol,
                }
            end
        end

        local hdrName = (ns.L and ns.L["VAULT_SUMMARY_COL_NAME"]) or "Character"
        local hdrRealm = (ns.L and ns.L["VAULT_SUMMARY_COL_REALM"]) or "Realm"
        local hdrRaid = (ns.L and ns.L["PVE_HEADER_RAIDS"]) or "Raids"
        local hdrMPlus = (ns.L and ns.L["PVE_HEADER_DUNGEONS"]) or "M+"
        local hdrWorld = (ns.L and ns.L["VAULT_WORLD"]) or "World"

        local FontManager = ns.FontManager
        local measure = FontManager and FontManager:CreateFontString(UIParent, "medium", "OVERLAY")
        local maxN, maxRm, maxVR, maxVM, maxVW = 52, 52, 40, 40, 40
        if measure and #rows > 0 then
            measure:Hide()
            measure:SetText(hdrName)
            maxN = math.max(maxN, measure:GetStringWidth() or 0)
            measure:SetText(hdrRealm)
            maxRm = math.max(maxRm, measure:GetStringWidth() or 0)
            measure:SetText(hdrRaid)
            maxVR = math.max(maxVR, measure:GetStringWidth() or 0)
            measure:SetText(hdrMPlus)
            maxVM = math.max(maxVM, measure:GetStringWidth() or 0)
            measure:SetText(hdrWorld)
            maxVW = math.max(maxVW, measure:GetStringWidth() or 0)
            for ri = 1, #rows do
                local rd = rows[ri]
                measure:SetText(rd.nameStr)
                maxN = math.max(maxN, measure:GetStringWidth() or 0)
                measure:SetText(rd.realmStr ~= "" and rd.realmStr or " ")
                maxRm = math.max(maxRm, measure:GetStringWidth() or 0)
                measure:SetText(rd.r)
                maxVR = math.max(maxVR, measure:GetStringWidth() or 0)
                measure:SetText(rd.d)
                maxVM = math.max(maxVM, measure:GetStringWidth() or 0)
                measure:SetText(rd.w)
                maxVW = math.max(maxVW, measure:GetStringWidth() or 0)
            end
            measure:SetParent(nil)
        end

        -- Raid / M+ / World: identical width (match TooltipFactory VAULT_GRID_TRACK_MIN_W); center via SetJustifyH there.
        local vaultColW = math.max(maxVR or 40, maxVM or 40, maxVW or 40, 72)
        local widths = { maxN, maxRm, vaultColW, vaultColW, vaultColW }

        if #rows > 0 then
            table.insert(lines, {
                type = "vault_grid_row",
                name = hdrName,
                realm = hdrRealm,
                colRaid = hdrRaid,
                colMplus = hdrMPlus,
                colWorld = hdrWorld,
                widths = widths,
                isHeader = true,
            })
            for ri = 1, #rows do
                local rd = rows[ri]
                table.insert(lines, {
                    type = "vault_grid_row",
                    name = rd.nameStr,
                    realm = rd.realmStr ~= "" and rd.realmStr or " ",
                    colRaid = rd.r,
                    colMplus = rd.d,
                    colWorld = rd.w,
                    widths = widths,
                })
            end
        end

        local notShown = #snap - (idx - 1)
        if notShown > 0 then
            table.insert(lines, { type = "spacer", height = 4 })
            table.insert(lines, {
                text = string.format((ns.L and ns.L["VAULT_SUMMARY_MORE"]) or "… and %d more (see PvE list).", notShown),
                color = { 0.5, 0.52, 0.58 },
            })
        end
    end

    ShowTooltip(anchorFrame, {
        type = "custom",
        -- Blizzard UI atlas (same pattern as StatisticsUI CreateIcon); avoids missing Interface\\Icons paths on some builds.
        icon = "BonusLoot-Chest",
        iconIsAtlas = true,
        title = title,
        lines = lines,
        anchor = "ANCHOR_RIGHT",
        maxWidth = maxW,
    })
end
